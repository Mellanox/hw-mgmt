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
readonly GRACE_FILE=${HW_MGMT_SYSTEM}/graceful_power_off
# Wall-clock budget for sync + flushbufs after the BMC request is
# asserted. Re-arm gap (graceful_power_off=0 for 1s) is separate so
# it does not steal this window. Default 3s vs BMC REBOOT_TO 5s.
# Timeout/skip => no ack.
readonly FLUSH_TIMEOUT_SECS=${HW_MGMT_BMC_NVME_FLUSH_TIMEOUT_SECS:-3}
# Never ack after this many seconds from helper start. Default 3s so
# the updater's 1 Hz detect (up to 1s) plus this cap stay under BMC
# REBOOT_TO 5s. A 4s cap would start after detect and miss the last
# BMC sample (GT-0915-10).
readonly ACK_CAP_SECS=${HW_MGMT_BMC_NVME_ACK_CAP_SECS:-3}
# BMC wait_for_cpu_shutdown: echo 0; sleep 1; echo 1.
readonly GRACE_WAIT_SECS=2

NVME_DEADLINE_SEC=0
NVME_GRACE_WAS_1=0
NVME_GRACE_DROPPED=0
NVME_GRACE_MTIME=

log_msg()  { logger -t "$LOGGER_TAG" -p user.notice -- "$@" 2>/dev/null || echo "$LOGGER_TAG: $*" >&2; }
log_warn() { logger -t "$LOGGER_TAG" -p user.warning -- "$@" 2>/dev/null || echo "$LOGGER_TAG: $*" >&2; }

ack_time_left() {
	local r=$((ACK_CAP_SECS - SECONDS))

	[ "$r" -gt 0 ] || r=0
	echo "$r"
}

deadline_init() {
	local cap flush_win

	cap=$(ack_time_left)
	if [ "$cap" -lt 1 ]; then
		NVME_DEADLINE_SEC=$SECONDS
		return
	fi
	flush_win=$FLUSH_TIMEOUT_SECS
	[ "$flush_win" -gt "$cap" ] && flush_win=$cap
	NVME_DEADLINE_SEC=$((SECONDS + flush_win))
}

remaining_sec() {
	local r=$((NVME_DEADLINE_SEC - SECONDS))
	local cap

	cap=$(ack_time_left)
	[ "$r" -gt 0 ] || r=0
	[ "$r" -le "$cap" ] || r=$cap
	echo "$r"
}

# Slice work to 1s so a BMC re-arm (grace=0 for 1s) is visible.
# A single timeout sync of 2-3s can miss that gap and ack a new txn.
run_with_timeout() {
	local rem rc

	while true; do
		rem=$(remaining_sec)
		if [ "$rem" -lt 1 ]; then
			log_warn "flush budget exhausted; skip: $*"
			return 1
		fi
		if ! grace_still_active; then
			log_warn "graceful_power_off dropped; skip: $*"
			return 1
		fi
		timeout --foreground 1 "$@"
		rc=$?
		[ "$rc" -eq 0 ] && return 0
		# 124: timeout(1) sliced; retry while budget remains.
		[ "$rc" -eq 124 ] || return "$rc"
	done
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
		if [ "$(remaining_sec)" -lt 1 ]; then
			log_warn "flush budget exhausted; skip remaining flushbufs"
			rc=1
			break
		fi
		if ! grace_still_active; then
			log_warn "graceful_power_off dropped during flush; skip ack"
			rc=1
			break
		fi
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

# Generation is bumped only by the lock owner. Duplicate udev+updater
# starts must not bump first: that would invalidate the in-flight ack.
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

# BMC wait_for_cpu_shutdown re-arm drives graceful_power_off 1->0->1.
# cpu_shutdown_req is often sticky RO, so generation/req cannot name the
# BMC transaction. If this attr exists: must have seen 1, and any later
# 0 is sticky fail (do not ack the new 1 with the old flush).
grace_still_active() {
	local v

	[ -r "$GRACE_FILE" ] || return 0
	[ "$NVME_GRACE_DROPPED" = "1" ] && return 1
	[ "$NVME_GRACE_WAS_1" = "1" ] || return 1
	v=$(tr -d '[:space:]' <"$GRACE_FILE")
	if [ "$v" != "1" ]; then
		NVME_GRACE_DROPPED=1
		return 1
	fi
	return 0
}

still_this_request() {
	local myseq=$1
	[ "$(current_request_seq)" = "$myseq" ] || return 1
	request_still_active || return 1
	grace_still_active || return 1
	grace_txn_unchanged
}

grace_is_one() {
	[ -r "$GRACE_FILE" ] || return 1
	[ "$(tr -d '[:space:]' <"$GRACE_FILE")" = "1" ]
}

grace_mtime() {
	stat -c %Y "$GRACE_FILE" 2>/dev/null || echo 0
}

# BMC re-arm rewrites graceful_power_off (0 then 1). Host seq cannot
# name that transaction; mtime can. Skip ack if it changed since we
# first observed grace=1. Same-second TOCTOU remains.
grace_txn_unchanged() {
	local now

	[ -r "$GRACE_FILE" ] || return 0
	[ -n "$NVME_GRACE_MTIME" ] || return 0
	now=$(grace_mtime)
	[ "$now" = "$NVME_GRACE_MTIME" ]
}

mark_grace_asserted() {
	NVME_GRACE_WAS_1=1
	NVME_GRACE_MTIME=$(grace_mtime)
}

# If graceful_power_off exists, do not start flush while it is 0 (BMC
# re-arm gap). Wait until it is 1 so NVME_GRACE_WAS_1 is not recorded
# as 0 and then skipped for the rest of the run.
wait_for_bmc_grace_request() {
	local until cap

	[ -r "$GRACE_FILE" ] || return 0
	cap=$(ack_time_left)
	[ "$cap" -ge 1 ] || cap=0
	until=$((SECONDS + GRACE_WAIT_SECS))
	[ "$((SECONDS + cap))" -lt "$until" ] && until=$((SECONDS + cap))
	while [ "$SECONDS" -lt "$until" ]; do
		if grace_is_one; then
			mark_grace_asserted
			return 0
		fi
		if ready_already_asserted; then
			# Do not proceed to flush with WAS_1=0 (GT-06).
			return 0
		fi
		sleep 0.2
	done
	log_warn "graceful_power_off not 1 within wait; skip"
	return 1
}

ready_already_asserted() {
	local v

	[ -r "$READY_FILE" ] || return 1
	v=$(tr -d '[:space:]' <"$READY_FILE")
	[ "$v" = "1" ]
}

retract_cpu_power_off_ready() {
	echo 0 >"$READY_FILE" 2>/dev/null || true
}

assert_cpu_power_off_ready() {
	local myseq=$1

	if [ ! -f "$READY_FILE" ]; then
		log_warn "cpu_power_off_ready not present ($READY_FILE); skip"
		return 1
	fi
	# Re-check immediately before the write: BMC re-arm can clear
	# graceful_power_off after still_this_request and before this echo.
	if ! still_this_request "$myseq"; then
		log_msg "request changed before ack; skip"
		return 1
	fi
	if [ -r "$GRACE_FILE" ] && ! grace_is_one; then
		log_msg "graceful_power_off not 1 before ack; skip"
		return 1
	fi
	if ! grace_txn_unchanged; then
		log_msg "graceful_power_off changed before ack; skip"
		return 1
	fi
	if [ "$(ack_time_left)" -lt 1 ]; then
		log_warn "ack cap ${ACK_CAP_SECS}s exceeded; skip"
		return 1
	fi
	if ! echo 1 >"$READY_FILE" 2>/dev/null; then
		log_warn "failed to write $READY_FILE"
		return 1
	fi
	# GT-0915-11: last-instruction TOCTOU. If re-arm won the race,
	# retract so the new BMC wait does not see a stale ready=1.
	if ! still_this_request "$myseq" || \
	   { [ -r "$GRACE_FILE" ] && ! grace_is_one; } || \
	   ! grace_txn_unchanged || \
	   [ "$(ack_time_left)" -lt 1 ]; then
		retract_cpu_power_off_ready
		log_msg "retracted cpu_power_off_ready after re-arm/cap; skip"
		return 1
	fi
	return 0
}

main() {
	local myseq flushed flush_rc

	# Primary gate: handshake attr exists ⇒ BMC wait path applies.
	if [ ! -f "$READY_FILE" ]; then
		log_warn "no $READY_FILE on this platform; skip"
		return 0
	fi

	# Serialize flush/ack. Short wait only: flock -n skipped a
	# newer helper while a stale owner still acked (Aug 31 P1);
	# flock -w 3 stacked past REBOOT_TO. Duplicate udev+updater
	# coalesce in ~1s; if still busy, skip (owner is flushing).
	exec 9>"$LOCK_FILE"
	if ! flock -w 1 9; then
		log_warn "lock busy; skip duplicate helper"
		return 1
	fi
	if ready_already_asserted; then
		log_msg "cpu_power_off_ready already 1; skip duplicate helper"
		return 0
	fi
	if [ "$(ack_time_left)" -lt 1 ]; then
		log_warn "ack cap ${ACK_CAP_SECS}s exceeded before flush; skip"
		return 1
	fi
	NVME_GRACE_WAS_1=0
	NVME_GRACE_DROPPED=0
	NVME_GRACE_MTIME=
	if ! wait_for_bmc_grace_request; then
		return 0
	fi
	if ready_already_asserted; then
		log_msg "cpu_power_off_ready already 1; skip duplicate helper"
		return 0
	fi
	# Attr present but never saw 1: would skip grace checks (GT-06).
	if [ -r "$GRACE_FILE" ] && [ "$NVME_GRACE_WAS_1" != "1" ]; then
		log_warn "graceful_power_off never 1; skip"
		return 0
	fi
	if [ "$(ack_time_left)" -lt 1 ]; then
		log_warn "ack cap ${ACK_CAP_SECS}s exceeded before flush; skip"
		return 1
	fi
	deadline_init
	myseq=$(bump_request_seq)

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

	if ready_already_asserted; then
		log_msg "cpu_power_off_ready already 1 after flush; skip"
		return 0
	fi

	if assert_cpu_power_off_ready "$myseq"; then
		log_msg "cpu_power_off_ready=1"
		return 0
	fi
	return 1
}

main "$@"
