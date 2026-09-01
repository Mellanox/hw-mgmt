#!/bin/bash
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# BMC-equipped platforms: on BMC shutdown/reboot request
# (cpu_shutdown_req / graceful_power_off — used by both graceful wait and
# the shorter non-graceful BMC window), quiesce NVMe storage and assert
# cpu_power_off_ready so BMC powerctrl can complete wait_for_cpu_shutdown()
# before removing host/aux power.
#
# Not for no-BMC platforms (those use the systemd-shutdown nvme hook instead).
##################################################################################

set -u

readonly LOGGER_TAG="hw-management-bmc-nvme-ready"
readonly HW_MGMT_SYSTEM=/var/run/hw-management/system
readonly READY_FILE=${HW_MGMT_SYSTEM}/cpu_power_off_ready
readonly LOCK_FILE=/run/hw-management-bmc-nvme-ready.lock
readonly SEQ_FILE=/run/hw-management-bmc-nvme-ready.seq
readonly SEQ_LOCK=/run/hw-management-bmc-nvme-ready.seq.lock
readonly REQ_FILE=${HW_MGMT_SYSTEM}/cpu_shutdown_req
# Bound sync/flushbufs so a hung NVMe cannot stall peripheral-updater
# (os.system of this script). Timeout is treated as flush failure: do not
# assert ready; BMC waits out GRACE_TO/REBOOT_TO.
readonly FLUSH_TIMEOUT_SECS=${HW_MGMT_BMC_NVME_FLUSH_TIMEOUT_SECS:-3}

log_msg()  { logger -t "$LOGGER_TAG" -p user.notice -- "$@" 2>/dev/null || echo "$LOGGER_TAG: $*" >&2; }
log_warn() { logger -t "$LOGGER_TAG" -p user.warning -- "$@" 2>/dev/null || echo "$LOGGER_TAG: $*" >&2; }

run_with_timeout() {
	timeout --foreground "${FLUSH_TIMEOUT_SECS}" "$@"
}

flush_nvme_block_devices() {
	local dev n=0 rc=0
	local -a devs

	if ! run_with_timeout sync; then
		log_warn "sync failed or timed out before NVMe flush"
		rc=1
	fi

	shopt -s nullglob
	devs=(/dev/nvme*n*)
	shopt -u nullglob

	for dev in "${devs[@]}"; do
		[ -b "$dev" ] || continue
		# Namespaces only; partition flush is redundant with nvmeXnY.
		case "$dev" in
		*p[0-9]*) continue ;;
		esac
		if run_with_timeout blockdev --flushbufs "$dev"; then
			n=$((n + 1))
		else
			log_warn "blockdev --flushbufs failed or timed out for $dev"
			rc=1
		fi
	done

	if ! run_with_timeout sync; then
		log_warn "sync failed or timed out after NVMe flush"
		rc=1
	fi

	echo "$n"
	return "$rc"
}

# Each invocation bumps a generation so an in-flight helper cannot ack a
# later BMC wait with an earlier flush (chassis-events starts this script
# in the background; flock -n used to drop the new run).
bump_request_seq() {
	local s=0
	exec 8>"$SEQ_LOCK"
	flock 8
	if [ -r "$SEQ_FILE" ]; then
		s=$(<"$SEQ_FILE")
	fi
	[[ "$s" =~ ^[0-9]+$ ]] || s=0
	s=$((s + 1))
	echo "$s" >"$SEQ_FILE"
	echo "$s"
}

current_request_seq() {
	local s=0
	if [ -r "$SEQ_FILE" ]; then
		s=$(<"$SEQ_FILE")
	fi
	[[ "$s" =~ ^[0-9]+$ ]] || s=0
	echo "$s"
}

request_still_active() {
	local v
	if [ -r "$REQ_FILE" ]; then
		v=$(<"$REQ_FILE")
		[ "$v" = "1" ] || return 1
	fi
	return 0
}

still_this_request() {
	local myseq=$1
	[ "$(current_request_seq)" = "$myseq" ] || return 1
	request_still_active
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
	local myseq flushed flush_rc lock_wait

	# Primary gate: handshake attr exists ⇒ BMC wait path applies.
	if [ ! -f "$READY_FILE" ]; then
		log_warn "no $READY_FILE on this platform; skip"
		return 0
	fi

	myseq=$(bump_request_seq)

	# Serialize flush/ack. Wait (do not flock -n skip) so a new edge is
	# not dropped while an older helper still holds the lock. Bound the
	# wait so peripheral-updater os.system cannot hang forever.
	lock_wait=$((FLUSH_TIMEOUT_SECS * 4 + 2))
	exec 9>"$LOCK_FILE"
	if ! flock -w "${lock_wait}" 9; then
		log_warn "could not acquire lock within ${lock_wait}s; skip"
		return 1
	fi
	if ! still_this_request "$myseq"; then
		log_msg "superseded by a newer shutdown request; skip ack"
		return 0
	fi

	log_msg "BMC shutdown request: quiescing NVMe then asserting cpu_power_off_ready"
	flushed=$(flush_nvme_block_devices)
	flush_rc=$?
	log_msg "flushed ${flushed} NVMe namespace(s) (flush_rc=${flush_rc})"

	if [ "${flush_rc}" -ne 0 ]; then
		log_warn "NVMe quiesce failed; not asserting cpu_power_off_ready (BMC will wait out timeout)"
		return 1
	fi

	if ! still_this_request "$myseq"; then
		log_msg "superseded after flush; not asserting cpu_power_off_ready"
		return 0
	fi

	if assert_cpu_power_off_ready; then
		log_msg "cpu_power_off_ready=1"
		return 0
	fi
	return 1
}

main "$@"
