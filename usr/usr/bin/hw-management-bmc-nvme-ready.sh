#!/bin/bash
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# BMC-equipped platforms: on graceful host shutdown/reboot request from the BMC
# (cpu_shutdown_req / graceful_power_off path), quiesce NVMe storage and assert
# cpu_power_off_ready so BMC powerctrl.sh can complete wait_for_cpu_shutdown()
# before removing host/aux power.
#
# Not for no-BMC platforms (those use the systemd-shutdown nvme hook instead).
##################################################################################

set -u

readonly LOGGER_TAG="hw-management-bmc-nvme-ready"
readonly HW_MGMT_SYSTEM=/var/run/hw-management/system
readonly READY_FILE=${HW_MGMT_SYSTEM}/cpu_power_off_ready
readonly LOCK_FILE=/run/hw-management-bmc-nvme-ready.lock

log_msg()  { logger -t "$LOGGER_TAG" -p user.notice -- "$@" 2>/dev/null || echo "$LOGGER_TAG: $*"; }
log_warn() { logger -t "$LOGGER_TAG" -p user.warning -- "$@" 2>/dev/null || echo "$LOGGER_TAG: $*"; }

flush_nvme_block_devices() {
	local dev
	local n=0

	sync 2>/dev/null || true
	for dev in /dev/nvme*n* /dev/nvme*n*p*; do
		[ -b "$dev" ] || continue
		if blockdev --flushbufs "$dev" 2>/dev/null; then
			n=$((n + 1))
		fi
	done
	sync 2>/dev/null || true
	echo "$n"
}

assert_cpu_power_off_ready() {
	if [ ! -f "$READY_FILE" ]; then
		log_warn "cpu_power_off_ready not present ($READY_FILE); skip"
		return 1
	fi
	if ! echo 1 >"$READY_FILE" 2>/dev/null; then
		log_warn "failed to write $READY_FILE"
		return 1
	fi
	return 0
}

main() {
	# Serialize: request edge can race with other event paths.
	exec 9>"$LOCK_FILE"
	if ! flock -n 9; then
		log_msg "another instance holds lock; skip"
		return 0
	fi

	# Primary gate: handshake attr exists ⇒ BMC OpenBMC wait path applies.
	if [ ! -f "$READY_FILE" ]; then
		log_warn "no $READY_FILE on this platform; skip"
		return 0
	fi

	log_msg "BMC graceful request: quiescing NVMe then asserting cpu_power_off_ready"
	flushed=$(flush_nvme_block_devices)
	log_msg "flushed ${flushed} NVMe block device(s)"

	if assert_cpu_power_off_ready; then
		log_msg "cpu_power_off_ready=1"
		return 0
	fi
	return 1
}

main "$@"
