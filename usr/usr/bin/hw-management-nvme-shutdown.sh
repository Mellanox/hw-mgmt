#!/bin/bash
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Software-only NVMe quiesce for no-BMC platforms during system shutdown.
# No CPLD or cpu_power_off_ready interaction.
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
##################################################################################

set -euo pipefail

if [ -f /etc/default/hw-management-nvme-shutdown ]; then
	# shellcheck disable=SC1091
	. /etc/default/hw-management-nvme-shutdown
fi

readonly LOGGER_TAG="hw-management-nvme-shutdown"
readonly NVME_SHUTDOWN_TIMEOUT_SEC="${NVME_SHUTDOWN_TIMEOUT_SEC:-120}"
readonly NVME_SHUTDOWN_WAIT_SEC="${NVME_SHUTDOWN_WAIT_SEC:-10}"
readonly NVME_SHUTDOWN_OVERHEAD_SEC=5

NVME_SHUTDOWN_WAIT_SEC_EFFECTIVE=$NVME_SHUTDOWN_WAIT_SEC
NVME_SHUTDOWN_CTRLS=()

log_msg()  { logger -t "$LOGGER_TAG" -p user.notice -- "$@"; }
log_warn() { logger -t "$LOGGER_TAG" -p user.warning -- "$@"; }

nvme_controllers() {
	local ctrl
	for ctrl in /sys/class/nvme/nvme*; do
		[ -d "$ctrl" ] || continue
		printf '%s\n' "$ctrl"
	done
}

nvme_controller_state() {
	local ctrl=$1 name state_path

	name=$(basename "$ctrl")
	for state_path in \
		"$ctrl/state" \
		"$ctrl/$name/state"
	do
		if [ -f "$state_path" ]; then
			cat "$state_path"
			return 0
		fi
	done

	echo "unknown"
}

nvme_state_is_pending() {
	case "$1" in
		live|resetting|connecting|deleting|deleting_noio)
			return 0
			;;
	esac
	return 1
}

validate_time_budget() {
	local wait=$NVME_SHUTDOWN_WAIT_SEC
	local max_wait=$((NVME_SHUTDOWN_TIMEOUT_SEC - NVME_SHUTDOWN_OVERHEAD_SEC))

	if [ "$max_wait" -lt 1 ]; then
		log_warn "NVME_SHUTDOWN_TIMEOUT_SEC (${NVME_SHUTDOWN_TIMEOUT_SEC}) " \
			"too small; using wait=1"
		NVME_SHUTDOWN_WAIT_SEC_EFFECTIVE=1
		return
	fi

	if [ "$wait" -gt "$max_wait" ]; then
		log_warn "NVME_SHUTDOWN_WAIT_SEC clamped from ${wait} to ${max_wait} " \
			"(timeout=${NVME_SHUTDOWN_TIMEOUT_SEC})"
		wait=$max_wait
	fi

	if [ "$wait" -lt 1 ]; then
		log_warn "Invalid wait value; using wait=1"
		wait=1
	fi

	NVME_SHUTDOWN_WAIT_SEC_EFFECTIVE=$wait
}

flush_block_devices() {
	local dev

	for dev in /dev/nvme*n* /dev/nvme*n*p*; do
		[ -b "$dev" ] || continue
		blockdev --flushbufs "$dev" 2>/dev/null || true
	done
}

request_nvme_shutdown() {
	local ctrl name

	NVME_SHUTDOWN_CTRLS=()

	while IFS= read -r ctrl; do
		[ -n "$ctrl" ] || continue
		name=$(basename "$ctrl")
		if [ ! -f "$ctrl/shutdown" ]; then
			log_warn "No shutdown attribute for $name"
			continue
		fi
		log_msg "Requesting NVMe shutdown: $name"
		if echo 1 >"$ctrl/shutdown" 2>/dev/null; then
			NVME_SHUTDOWN_CTRLS+=("$ctrl")
		else
			log_warn "Failed to write $ctrl/shutdown"
		fi
	done < <(nvme_controllers)
}

wait_nvme_shutdown() {
	local ctrl name state elapsed=0 pending

	if [ "${#NVME_SHUTDOWN_CTRLS[@]}" -eq 0 ]; then
		return 0
	fi

	while [ "$elapsed" -lt "$NVME_SHUTDOWN_WAIT_SEC_EFFECTIVE" ]; do
		pending=0

		for ctrl in "${NVME_SHUTDOWN_CTRLS[@]}"; do
			name=$(basename "$ctrl")
			state=$(nvme_controller_state "$ctrl")

			if nvme_state_is_pending "$state"; then
				pending=1
				log_msg "$name state=$state (waiting)"
			else
				log_msg "$name state=$state"
			fi
		done

		[ "$pending" -eq 0 ] && return 0
		sleep 1
		elapsed=$((elapsed + 1))
	done

	log_warn "NVMe shutdown wait timed out after " \
		"${NVME_SHUTDOWN_WAIT_SEC_EFFECTIVE}s"
	return 0
}

main() {
	local requested action="${1:-unknown}"

	if ! /usr/bin/hw-management-nvme-shutdown-condition.sh; then
		exit 0
	fi

	mapfile -t _nvme_ctrls < <(nvme_controllers)
	if [ "${#_nvme_ctrls[@]}" -eq 0 ]; then
		log_warn "No NVMe controllers in sysfs"
		exit 0
	fi

	validate_time_budget

	log_msg "Starting software-only NVMe shutdown (action=${action})"

	sync
	flush_block_devices

	request_nvme_shutdown
	requested="${#NVME_SHUTDOWN_CTRLS[@]}"
	if [ "$requested" -gt 0 ]; then
		wait_nvme_shutdown
	else
		log_warn "No controller accepted shutdown request; " \
			"relying on sync/flush only"
	fi

	sync

	log_msg "Software-only NVMe shutdown completed"
}

main "$@"
