#!/bin/bash

# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
################################################################################
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
################################################################################
# BMC ABR watchdog heartbeat.
#
# AST2700 ABR (Alternate Boot Recovery) watchdog is intended for systems that
# boot from redundant SPI flashes: on expiry the BootMCU switches the boot
# source to the backup SPI image. On the SONiC BMC the BMC boots from eMMC
# while the SPI flash holds the OpenBMC image, so an ABR expiry would switch to
# the undesired OpenBMC image. The ABR watchdog is only armed once the OTP fuse
# is programmed (production systems).
#
# Until SONiC settles on a final solution, this service brings up the MCTP
# stack (mctpd + the mctpirot link), discovers the Bali (Caliptra) endpoint EID
# via the MCTP bus owner (falling back to a configured EID), and periodically
# sends the "service watchdog" request to it over MCTP (mctp-client), so the
# ABR watchdog is serviced before it can expire.

LOG_TAG="hw-management-bmc-wd-heartbeat"

# shellcheck source=/dev/null
source /usr/bin/hw-management-bmc-helpers-common.sh

CONFIG_FILE="${HW_MANAGEMENT_BMC_WD_HEARTBEAT_CONF:-/etc/hw-management-bmc-wd-heartbeat.conf}"

# Defaults (overridden by CONFIG_FILE if present).
WD_HEARTBEAT_ENABLE=1
WD_HEARTBEAT_INTERFACE="mctpirot0"
WD_HEARTBEAT_EID=8
WD_HEARTBEAT_MSG_TYPE="control"
WD_HEARTBEAT_DATA="80 03"
WD_HEARTBEAT_INTERVAL=30
WD_HEARTBEAT_CMD_TIMEOUT=10
WD_HEARTBEAT_MCTP_CLIENT=""
WD_HEARTBEAT_MCTPD_SERVICE="mctpd"
WD_HEARTBEAT_SETUP_ENDPOINT=1

if [ -f "$CONFIG_FILE" ]; then
	# shellcheck source=/dev/null
	source "$CONFIG_FILE"
else
	log_message "warning" "Config $CONFIG_FILE not found; using built-in defaults"
fi

# Disabled by configuration: exit cleanly so systemd does not treat it as a
# failure and does not restart us.
if [ "${WD_HEARTBEAT_ENABLE}" != "1" ]; then
	log_message "notice" "ABR watchdog heartbeat disabled (WD_HEARTBEAT_ENABLE=${WD_HEARTBEAT_ENABLE}); exiting"
	exit 0
fi

# Resolve the mctp-client binary. Without it there is nothing to do (e.g. an
# image that does not ship the MCTP tooling): exit 0 so we do not restart-loop.
MCTP_CLIENT="${WD_HEARTBEAT_MCTP_CLIENT:-}"
if [ -z "$MCTP_CLIENT" ]; then
	MCTP_CLIENT="$(command -v mctp-client 2>/dev/null)"
fi
if [ -z "$MCTP_CLIENT" ] || [ ! -x "$MCTP_CLIENT" ]; then
	log_message "warning" "mctp-client not found; ABR watchdog heartbeat cannot run; exiting"
	exit 0
fi

# Validate the send period and the per-call timeout, and keep the timeout below
# the period. Worst-case gap between consecutive heartbeats is
# WD_HEARTBEAT_CMD_TIMEOUT + WD_HEARTBEAT_INTERVAL (each loop: up to CMD_TIMEOUT
# for the call, then INTERVAL sleep); that sum must be shorter than the ABR
# watchdog timeout. A hung mctp-client / busctl call must NOT stall the loop:
# if the transport is unhealthy an unbounded call would block forever, no
# further heartbeats would be sent, the ABR watchdog would expire, and the
# BootMCU would switch to the OpenBMC image - the exact failure this service
# prevents.
case "$WD_HEARTBEAT_INTERVAL" in
	''|*[!0-9]*) WD_HEARTBEAT_INTERVAL=30 ;;
esac
[ "$WD_HEARTBEAT_INTERVAL" -lt 1 ] 2>/dev/null && WD_HEARTBEAT_INTERVAL=30

case "$WD_HEARTBEAT_CMD_TIMEOUT" in
	''|*[!0-9]*) WD_HEARTBEAT_CMD_TIMEOUT=10 ;;
esac
[ "$WD_HEARTBEAT_CMD_TIMEOUT" -lt 1 ] 2>/dev/null && WD_HEARTBEAT_CMD_TIMEOUT=10
if [ "$WD_HEARTBEAT_CMD_TIMEOUT" -ge "$WD_HEARTBEAT_INTERVAL" ] 2>/dev/null; then
	if [ "$WD_HEARTBEAT_INTERVAL" -gt 1 ]; then
		WD_HEARTBEAT_CMD_TIMEOUT=$((WD_HEARTBEAT_INTERVAL - 1))
	else
		WD_HEARTBEAT_CMD_TIMEOUT=1
	fi
fi

# timeout(1) (coreutils or busybox) bounds each external call. If it is missing
# we run unguarded and warn, since the time bound cannot be enforced.
TIMEOUT_BIN="$(command -v timeout 2>/dev/null)"
if [ -z "$TIMEOUT_BIN" ]; then
	log_message "warning" "timeout(1) not found; mctp-client/busctl calls will run without a time bound"
fi

# Run "$@" bounded by WD_HEARTBEAT_CMD_TIMEOUT seconds when timeout(1) exists,
# otherwise run it directly. timeout exits 124 on expiry, which the callers
# treat as a normal failure (retry / fall back).
run_bounded() {
	if [ -n "$TIMEOUT_BIN" ]; then
		"$TIMEOUT_BIN" "$WD_HEARTBEAT_CMD_TIMEOUT" "$@"
	else
		"$@"
	fi
}

# Bring up the MCTP stack: start mctpd and set the IRoT link up. Best-effort -
# mctpd may already be running and the link already up; failures here are
# logged but do not abort (the heartbeat loop below still retries).
if [ -n "$WD_HEARTBEAT_MCTPD_SERVICE" ] && command -v systemctl >/dev/null 2>&1; then
	if systemctl start "$WD_HEARTBEAT_MCTPD_SERVICE" >/dev/null 2>&1; then
		log_message "info" "Started ${WD_HEARTBEAT_MCTPD_SERVICE}"
	else
		log_message "warning" "Failed to start ${WD_HEARTBEAT_MCTPD_SERVICE} (may already be running)"
	fi
fi

if [ -n "$WD_HEARTBEAT_INTERFACE" ] && command -v mctp >/dev/null 2>&1; then
	if mctp link set "$WD_HEARTBEAT_INTERFACE" up >/dev/null 2>&1; then
		log_message "info" "Set MCTP link ${WD_HEARTBEAT_INTERFACE} up"
	else
		log_message "warning" "Failed to set MCTP link ${WD_HEARTBEAT_INTERFACE} up (may already be up)"
	fi
fi

# Discover the Bali (Caliptra) endpoint EID from the MCTP bus owner.
# busctl SetupEndpoint returns a reply whose second field is the assigned EID
# (e.g. "yisb 8 1 "/.../endpoints/8" true"). If discovery fails or yields no
# usable EID, fall back to the configured WD_HEARTBEAT_EID (default 8).
discover_eid() {
	local iface="$1"
	local out eid
	command -v busctl >/dev/null 2>&1 || return 1
	out=$(run_bounded busctl call au.com.codeconstruct.MCTP1 \
		"/au/com/codeconstruct/mctp1/interfaces/${iface}" \
		au.com.codeconstruct.MCTP.BusOwner1 SetupEndpoint ay 0 2>/dev/null) || return 1
	# log_message echoes to stdout; this function's stdout IS the EID (captured
	# via command substitution), so send the log to stderr to avoid polluting it.
	log_message "info" "SetupEndpoint(${iface}) -> ${out}" >&2
	eid=$(echo "$out" | awk '{print $2}')
	case "$eid" in
		''|*[!0-9]*) return 1 ;;
	esac
	echo "$eid"
}

EID=""
if [ "${WD_HEARTBEAT_SETUP_ENDPOINT}" = "1" ] && [ -n "$WD_HEARTBEAT_INTERFACE" ]; then
	EID=$(discover_eid "$WD_HEARTBEAT_INTERFACE") || EID=""
fi
if [ -z "$EID" ]; then
	EID="$WD_HEARTBEAT_EID"
	log_message "notice" "Using fallback EID=${EID} (endpoint discovery unavailable or skipped)"
fi

# EID must be numeric; without it there is nothing to address.
case "$EID" in
	''|*[!0-9]*)
		log_message "err" "No valid MCTP EID (got '${EID}'); cannot address Bali (Caliptra); refusing to start"
		exit 1
		;;
esac

log_message "info" "Starting ABR watchdog heartbeat: eid=${EID} type=${WD_HEARTBEAT_MSG_TYPE} data=[${WD_HEARTBEAT_DATA}] interval=${WD_HEARTBEAT_INTERVAL}s timeout=${WD_HEARTBEAT_CMD_TIMEOUT}s worst_case=$((WD_HEARTBEAT_CMD_TIMEOUT + WD_HEARTBEAT_INTERVAL))s via ${MCTP_CLIENT}"

# Log only on state change (ok<->fail) to avoid flooding the journal every
# interval while the link is healthy.
_prev_ok=-1

while true; do
	# shellcheck disable=SC2086
	# WD_HEARTBEAT_DATA is intentionally unquoted so each hex byte becomes a
	# separate mctp-client argument (matches "data 80 03"). run_bounded caps the
	# call at WD_HEARTBEAT_CMD_TIMEOUT so a hung transport cannot stall the loop.
	if run_bounded "$MCTP_CLIENT" eid "$EID" type "$WD_HEARTBEAT_MSG_TYPE" data $WD_HEARTBEAT_DATA >/dev/null 2>&1; then
		if [ "$_prev_ok" != "1" ]; then
			log_message "info" "ABR watchdog heartbeat OK (eid=${EID})"
			_prev_ok=1
		fi
	else
		if [ "$_prev_ok" != "0" ]; then
			log_message "warning" "ABR watchdog heartbeat request failed or timed out (eid=${EID}); will keep retrying"
			_prev_ok=0
		fi
	fi
	sleep "$WD_HEARTBEAT_INTERVAL"
done
