#!/bin/bash
###########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
# This script brings up the USB network interface to the BMC. It is started by
# hw-management-ifupdown@<interface>.service, which UDEV pulls in through
# SYSTEMD_WANTS when the interface appears, and which is ordered after the
# networking service to stay out of its ifup window.
# Usage: hw-management-ifupdown.sh <interface>

source /usr/bin/hw-management-helpers.sh

INTERFACE=$1

if [ -z "${INTERFACE}" ]; then
	log_err "Missing interface parameter"
	exit 1
fi

# Runtime directory of the ifupdown tools. Its contents - the lock and the state
# files of the run that raced with us - are reported when ifup fails.
IFUPDOWN_RUN_DIR="/run/network"
# Matches the ifupdown tools and the NOS networking service script, which is the
# other user of the lock. ifupdown2 tools are python scripts, so their command
# line starts with the interpreter and the tool appears as a path. The command
# line also tells which phase the networking service is in: "ifup --allow=mgmt",
# "ifup -a" or the "ifup usb0" of its hotplug phase.
IFUPDOWN_PROCS='/(ifup|ifdown|ifreload|ifquery)([[:space:]]|$)|start-networking'
# Upper bounds keeping a failure report in syslog small: lines reported per
# failed attempt, lines reported for the last attempt, and message length.
IFUP_REASON_LINES=10
IFUP_LOG_LINES=40
IFUP_LOG_WIDTH=500

# Whether ifup gave up because another instance was holding the lock. ifupdown2
# serializes its runs with a non-blocking flock() and bails out immediately when
# the lock is busy, so such a failure only means that the interface has to be
# brought up later, once the other instance is done.
failed_on_lock()
{
	printf '%s\n' "$1" | grep -qai "already running"
}

# Log the captured ifup output line by line, since logger mangles multi-line
# messages. $2 is "reason" to report why a single attempt failed, or "full" to
# report the sequence that led to the final failure.
log_ifup_output()
{
	local output="$1" mode="$2" reported limit line

	if [ "${mode}" = "reason" ]; then
		# Error and warning lines carry the reason of the failure. Not every
		# ifup version tags them, hence the fallback to the last lines.
		reported=$(printf '%s\n' "${output}" | grep -aiE 'error|warn|traceback|exception')
		[ -n "${reported}" ] || reported=$(printf '%s\n' "${output}" | tail -n 5)
		limit=${IFUP_REASON_LINES}
	else
		reported=$(printf '%s\n' "${output}" | tail -n "${IFUP_LOG_LINES}")
		limit=${IFUP_LOG_LINES}
	fi

	while IFS= read -r line; do
		[ -n "${line}" ] || continue
		log_err "ifup ${INTERFACE}: out: ${line:0:${IFUP_LOG_WIDTH}}"
	done < <(printf '%s\n' "${reported}" | head -n "${limit}")

	return 0
}

# Log the other ifupdown instances still running, with their run time in seconds.
# The one that raced with us may already be gone by the time ifup gave up.
log_ifupdown_peers()
{
	local pids line

	pids=$(pgrep -f "${IFUPDOWN_PROCS}" 2>/dev/null | grep -v "^$$\$" | tr '\n' ',')
	if [ -z "${pids}" ]; then
		log_err "ifup ${INTERFACE}: no other ifupdown instance is running"
		return 0
	fi

	while IFS= read -r line; do
		log_err "ifup ${INTERFACE}: peer: ${line:0:${IFUP_LOG_WIDTH}}"
	done < <(ps -o pid=,etimes=,args= -p "${pids%,}" 2>/dev/null | head -n 10)

	return 0
}

# State of the interface. usb0 is expected to be present with carrier up, since
# the BMC boots before hw-management starts.
log_interface_state()
{
	local sysfs="/sys/class/net/${INTERFACE}"
	local link addresses runstate check

	link="operstate=$(cat "${sysfs}/operstate" 2>/dev/null)"
	link="${link} carrier=$(cat "${sysfs}/carrier" 2>/dev/null)"
	link="${link} flags=$(cat "${sysfs}/flags" 2>/dev/null)"
	addresses=$(ip -o addr show dev "${INTERFACE}" 2>&1 | tr '\n' ';')
	runstate=$(ls -A "${IFUPDOWN_RUN_DIR}" 2>&1 | tr '\n' ' ')

	log_err "ifup ${INTERFACE}: link: ${link}"
	log_err "ifup ${INTERFACE}: addresses: ${addresses:0:${IFUP_LOG_WIDTH}}"
	log_err "ifup ${INTERFACE}: lock and state files: ${runstate:0:${IFUP_LOG_WIDTH}}"

	# Whether the running state already matches /etc/network/interfaces, telling
	# a lost race apart from a real configuration error: the NOS networking
	# service brings up allow-hotplug interfaces in its own ifup_hotplug phase,
	# so usb0 may well be configured by the time ifup gives up here. Query
	# operations take no lock, so this is safe next to a running instance.
	if [ "${IFUPDOWN2}" -eq 1 ]; then
		check=$(ifquery -c "${INTERFACE}" 2>&1 | tr '\n' ';')
		log_err "ifup ${INTERFACE}: ifquery -c: ${check:0:${IFUP_LOG_WIDTH}}"
	fi

	return 0
}

# Skip ifup only when SONiC host and BMC/host images agree (NOS contract file present).
# If the host is SONiC but the contract file is absent, BMC may still use static
# usb0 and the host must run ifup as on non-SONiC images.
if [ "${INTERFACE}" = "usb0" ] && check_host_usb0_managed_by_nos; then
	log_info "SONiC host: skip ifup ${INTERFACE} (NOS-owned, contract file present)"
	exit 0
fi

if [ ! -e "/sys/class/net/${INTERFACE}" ]; then
	log_info "Interface ${INTERFACE} is missing"
	exit 0
fi

if [ ! -e /etc/network/interfaces ]; then
	log_info "/etc/network/interfaces is missing"
	exit 0
fi

if ! ifquery "$INTERFACE" >/dev/null 2>&1; then
	log_err "Interface $INTERFACE is not defined in /etc/network/interfaces"
	exit 1
fi

# ifup output is otherwise lost, as UDEV discards the output of RUN programs
# unless it runs with debug log priority. Capture it to report why an attempt
# failed. Only ifupdown2 knows -d and "ifquery -c", so probe for it first.
IFUP_OPTS=(-v)
IFUPDOWN2=0
if ifup --help 2>&1 | grep -q -- "--debug"; then
	IFUPDOWN2=1
	IFUP_OPTS+=(-d)
fi

# Budget for bringing the interface up. A lock conflict is retried for the whole
# IFUP_TIMEOUT, because the instance holding the lock keeps it for as long as its
# own ifup run takes - up to a DHCP timeout for "ifup -a" - which a fixed number
# of short retries cannot outlast. Failures unrelated to the lock are unlikely to
# resolve themselves, so they get MAX_RETRIES short retries instead. No single
# ifup run may outlast the budget either, hence IFUP_MIN_TIMEOUT as the smallest
# limit given to a run that starts close to the deadline.
IFUP_TIMEOUT=90
IFUP_MIN_TIMEOUT=20
MAX_RETRIES=5
RETRY_DELAY=2

# UDEV exports ACTION to the programs it runs. Should this script still be invoked
# from a UDEV RUN rule - an old rules file left behind by an upgrade - keep the
# short budget it was written for, as a UDEV worker must not be blocked for long.
if [ -n "${ACTION:-}" ]; then
	IFUP_TIMEOUT=8
	log_info "ifup ${INTERFACE}: running from UDEV (ACTION=${ACTION}), limiting the retries"
fi

# A single run can never be given more than the whole budget.
[ "${IFUP_MIN_TIMEOUT}" -le "${IFUP_TIMEOUT}" ] || IFUP_MIN_TIMEOUT=${IFUP_TIMEOUT}

START_TIME=$SECONDS
IFUP_DEADLINE=$((START_TIME + IFUP_TIMEOUT))
attempt=0
diag_logged=0
while :; do
	attempt=$((attempt + 1))
	# Bound the run by what is left of the budget. A hook or a DHCP client that
	# never returns would otherwise keep ifup running past the deadline, until
	# systemd stops the service and the report below is never written. A run
	# that starts close to the deadline still gets IFUP_MIN_TIMEOUT, as killing
	# it right away would leave the interface down for nothing; the service
	# allows for that overshoot in TimeoutStartSec.
	attempt_limit=$((IFUP_DEADLINE - SECONDS))
	[ "${attempt_limit}" -ge "${IFUP_MIN_TIMEOUT}" ] || attempt_limit=${IFUP_MIN_TIMEOUT}
	attempt_time=$SECONDS
	ifup_out=$(timeout -k 5s "${attempt_limit}s" ifup "${IFUP_OPTS[@]}" "${INTERFACE}" 2>&1)
	ifup_rc=$?
	attempt_time=$((SECONDS - attempt_time))

	if [ "${ifup_rc}" -eq 0 ]; then
		log_info "ifup ${INTERFACE} succeeded on attempt ${attempt} after $((SECONDS - START_TIME))s"
		exit 0
	fi

	# 124, or 137 when SIGTERM was not enough, is how timeout(1) reports that it
	# had to stop the run.
	if [ "${ifup_rc}" -eq 124 ] || [ "${ifup_rc}" -eq 137 ]; then
		log_err "ifup ${INTERFACE}: attempt ${attempt} did not finish in ${attempt_limit}s and was stopped"
	else
		log_err "ifup ${INTERFACE}: attempt ${attempt} failed (rc=${ifup_rc}) after ${attempt_time}s"
	fi

	# Report the details of the first failure only. Waiting out a lock conflict
	# can take many attempts, and a repeated report would flood syslog.
	if [ "${diag_logged}" -eq 0 ]; then
		log_ifup_output "${ifup_out}" "reason"
		log_ifupdown_peers
		diag_logged=1
	fi

	# The budget bounds every kind of failure, and a failure other than a lock
	# conflict is retried a few times only.
	if [ "${SECONDS}" -ge "${IFUP_DEADLINE}" ]; then
		break
	fi
	if ! failed_on_lock "${ifup_out}" && [ "${attempt}" -ge "${MAX_RETRIES}" ]; then
		break
	fi

	# Every attempt is reported above already, so announce the retries once.
	if [ "${attempt}" -eq 1 ]; then
		log_info "ifup ${INTERFACE}: retrying every ${RETRY_DELAY}s, for up to ${IFUP_TIMEOUT}s"
	fi
	sleep "${RETRY_DELAY}"
done

log_err "Failed to ifup interface ${INTERFACE} after ${attempt} attempts, $((SECONDS - START_TIME))s"
log_ifup_output "${ifup_out}" "full"
log_ifupdown_peers
log_interface_state
exit 1
