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
# Leave 1s so the completion log can run before the hook's outer timeout.
readonly NVME_SHUTDOWN_TAIL_SEC=1

NVME_DEADLINE_SEC=0
NVME_SHUTDOWN_CTRLS=()

log_msg()  { logger -t "$LOGGER_TAG" -p user.notice -- "$@"; }
log_warn() { logger -t "$LOGGER_TAG" -p user.warning -- "$@"; }

deadline_init() {
	NVME_DEADLINE_SEC=$((SECONDS + NVME_SHUTDOWN_TIMEOUT_SEC))
}

remaining_sec() {
	local r=$((NVME_DEADLINE_SEC - SECONDS - NVME_SHUTDOWN_TAIL_SEC))

	[ "$r" -gt 0 ] || r=0
	echo "$r"
}

# Run a blocking command with the remaining deadline. Never trip set -e.
run_bounded() {
	local rem

	rem=$(remaining_sec)
	if [ "$rem" -lt 1 ]; then
		log_warn "deadline reached; skip: $*"
		return 0
	fi
	if command -v timeout >/dev/null 2>&1; then
		timeout --foreground "$rem" "$@" || \
			log_warn "timed out or failed (${rem}s): $*"
	else
		"$@" || log_warn "failed: $*"
	fi
	return 0
}

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

flush_block_devices() {
	local dev
	local -a devs

	# Namespaces only; partition flush is redundant with nvmeXnY.
	shopt -s nullglob
	devs=(/dev/nvme*n*)
	shopt -u nullglob

	for dev in "${devs[@]}"; do
		[ -b "$dev" ] || continue
		case "$dev" in
		*p[0-9]*) continue ;;
		esac
		[ "$(remaining_sec)" -ge 1 ] || {
			log_warn "deadline reached; skip remaining flushbufs"
			return 0
		}
		run_bounded blockdev --flushbufs "$dev"
	done
}

request_nvme_shutdown() {
	local ctrl name

	NVME_SHUTDOWN_CTRLS=()

	while IFS= read -r ctrl; do
		[ -n "$ctrl" ] || continue
		name=$(basename "$ctrl")
		if [ ! -f "$ctrl/shutdown" ]; then
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
	local ctrl name state elapsed=0 pending rem wait_cap

	if [ "${#NVME_SHUTDOWN_CTRLS[@]}" -eq 0 ]; then
		return 0
	fi

	wait_cap=$NVME_SHUTDOWN_WAIT_SEC
	[ "$wait_cap" -ge 1 ] || wait_cap=1

	while :; do
		rem=$(remaining_sec)
		if [ "$rem" -lt 1 ]; then
			log_warn "deadline reached during NVMe shutdown wait"
			return 0
		fi
		if [ "$elapsed" -ge "$wait_cap" ]; then
			log_warn "NVMe shutdown wait timed out after ${wait_cap}s"
			return 0
		fi

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
		run_bounded sleep 1
		elapsed=$((elapsed + 1))
	done
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

	deadline_init
	log_msg "Starting software-only NVMe shutdown (action=${action} " \
		"timeout=${NVME_SHUTDOWN_TIMEOUT_SEC}s)"

	run_bounded sync
	flush_block_devices

	if [ "$(remaining_sec)" -ge 1 ]; then
		request_nvme_shutdown
		requested="${#NVME_SHUTDOWN_CTRLS[@]}"
		if [ "$requested" -gt 0 ]; then
			wait_nvme_shutdown
		else
			log_warn "No controller accepted shutdown request; " \
				"relying on sync/flush only"
		fi
	else
		log_warn "deadline reached; skip NVMe shutdown request"
	fi

	run_bounded sync

	log_msg "Software-only NVMe shutdown completed"
}

main "$@"
