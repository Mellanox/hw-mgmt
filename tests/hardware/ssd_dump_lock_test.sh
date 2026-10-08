#!/bin/sh
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause

# On-target test for the SSD dump lock
# (/run/hw-management-ssd-dump.lock, flock, exit code 3).
#
# Scenarios:
#   0  baseline, no contention: a collect runs, packs
#      /var/log/ssd-dump.tar.gz and leaves the lock free
#   1  collect running + second hw-management-ssd-dump.py
#   2  collect running + hw-management-ssd-dump.py --verify
#   3  collect running + hw-management-generate-dump.sh (which
#      calls the collector through its own helper)
#   4  hw-management-ssd-dump-collect.sh running + collector
#   5  collect running + hw-management-ssd-dump-collect.sh,
#      which waits the whole budget and then gives up
#   6  hw-management-generate-dump.sh running + collector
#   7  collect finishes while the helper waits: reuse its dump
#   8  helper waits for another helper, then collects itself
#   9  --no-tar collect finishes while the helper waits: reuse
#  10  an old dump in the default location is not reused
#  11  no usable lock: the helper collects nothing at all
#  12  a verify result is not mistaken for a dump
#
# The process that holds the lock is a real collector run whose
# vendor tool is replaced, via a generated --config, by a stub
# that writes one dump file and then blocks until this script
# releases it, so the hold is deterministic. Everything that
# collects here uses that config, the helper under test included
# (through a PATH shim in front of hw-management-ssd-dump.py),
# so the vendor package (ssd-dump-tools) is not needed and the
# result does not depend on which SSD the target has.
#
# DESTRUCTIVE. /var/log/ssd-dump, /var/log/ssd-dump.tar.gz,
# /tmp/hw-mgmt-dump and /tmp/hw-mgmt-dump.tar.gz are moved aside
# on start and restored on exit, including on Ctrl-C.
#
# Usage: sudo ./ssd_dump_lock_test.sh [-h] [-l] [-k] [SCENARIO...]
# -h lists the options, the scenarios and the environment
# variables; it is the one copy of that text, so it cannot drift
# from the code the way a second copy here would.
#
# Exit: 0 all checks passed, 1 a check failed, 2 prerequisites
# not met or bad usage.

LOCK_FILE=/run/hw-management-ssd-dump.lock
SSD_LOG_DIR=/var/log/ssd-dump
SSD_TARBALL=/var/log/ssd-dump.tar.gz
DUMP_FOLDER=/tmp/hw-mgmt-dump
DUMP_TARBALL=/tmp/hw-mgmt-dump.tar.gz
RC_LOCKED=3
MSG_BUSY="SSD dump tool busy:"
MSG_WAITING="SSD dump tool waiting:"
MSG_NO_LOCK="no usable SSD dump lock"
MSG_REUSED="SSD dump tool reused:"
MSG_SUCCEEDED="SSD dump tool succeeded"

GENERATE_DUMP_MODE=${GENERATE_DUMP_MODE:-compact}
GENERATE_DUMP_WAIT=${GENERATE_DUMP_WAIT:-420}
# The collector refuses a --timeout above TIMEOUT_SEC_CLI_MAX.
HOLD_TIMEOUT=${HOLD_TIMEOUT:-600}
# timeout_sec in the generated config, which is what the helper
# waits for a busy lock. Long enough for a holder to finish and
# pack while a waiting helper polls, short enough that waiting
# it out is quick.
LOCK_WAIT_SEC=${LOCK_WAIT_SEC:-20}

ALL_SCENARIOS="0 1 2 3 4 5 6 7 8 9 10 11 12"
# Scenarios that need the helper to wait for a busy lock rather
# than refuse at once.
WAIT_SCENARIOS="3 5 7 8 9 10 12"
NOLOCK_SCENARIOS="11"
KEEP_WORK=0
CHECKS=0
FAILED=0
SCENARIO_FAILED=0
HOLDER_PID=""
HOLDER_LOCK_PID=""
FLOCK=""
SECOND_PID=""
WORK=""
BACKUP=""
CLEANED=0

usage() {
	cat <<'EOF'
On-target test for the SSD dump lock.

Usage: ssd_dump_lock_test.sh [-h] [-l] [-k] [SCENARIO...]
  -l        list the scenarios and exit
  -k        keep the work directory for inspection
  SCENARIO  one or more of 0 1 2 3 4 5 6 7 8 9 10 11 12 (default: all)

DESTRUCTIVE: /var/log/ssd-dump, /var/log/ssd-dump.tar.gz,
/tmp/hw-mgmt-dump and /tmp/hw-mgmt-dump.tar.gz are moved aside
on start and restored on exit. Must run as root.

Environment:
  SSD_DUMP_BIN_DIR    take the scripts from this directory
                      instead of PATH (testing a build tree)
  GENERATE_DUMP_MODE  generate-dump argument, default compact
  GENERATE_DUMP_WAIT  seconds to wait for generate-dump to reach
                      its SSD step in scenario 6, default 420
  HOLD_TIMEOUT        max seconds a holder may block, 600;
                      the collector caps --timeout at 600
  LOCK_WAIT_SEC       timeout_sec written into the generated
                      config, which is how long the helper waits
                      for a busy lock, default 20

Exit: 0 all checks passed, 1 a check failed, 2 prerequisites
not met or bad usage.
EOF
}

list_scenarios() {
	cat <<'EOF'
0  baseline: one collect, no contention
1  collect holds the lock, hw-management-ssd-dump.py is called
2  collect holds the lock, hw-management-ssd-dump.py --verify
3  collect holds the lock, hw-management-generate-dump.sh runs
4  hw-management-ssd-dump-collect.sh holds, collector is called
5  collect never releases, the helper waits the budget out
6  hw-management-generate-dump.sh holds, collector is called
7  collect finishes while the helper waits, its archive is reused
8  helper waits for another helper, finds nothing, collects itself
9  --no-tar collect finishes while the helper waits, dir is reused
10 an old archive the holder never touched is not reused
11 no usable lock, so the work dir is left untouched
12 a --verify result in the default location is not reused
EOF
}

say() {
	echo "$*"
}

die() {
	echo "ssd_dump_lock_test: $*" >&2
	exit 2
}

# --- check helpers -------------------------------------------------

pass() {
	CHECKS=$((CHECKS + 1))
	echo "    PASS  $1"
}

fail() {
	CHECKS=$((CHECKS + 1))
	FAILED=$((FAILED + 1))
	SCENARIO_FAILED=1
	echo "    FAIL  $1"
	[ -n "$2" ] && echo "          $2"
}

ok_eq() { # desc expected actual
	if [ "$2" = "$3" ]; then
		pass "$1"
	else
		fail "$1" "expected [$2], got [$3]"
	fi
}

ok_grep() { # desc file pattern
	if [ -f "$2" ] && grep -q -F -- "$3" "$2"; then
		pass "$1"
	else
		fail "$1" "not found in $2: $3"
	fi
}

ok_nogrep() { # desc file pattern
	if [ -f "$2" ] && grep -q -F -- "$3" "$2"; then
		fail "$1" "unexpectedly found in $2: $3"
	else
		pass "$1"
	fi
}

STALE_HINT="a helper older than the lock wait refuses at once instead"

# The wait is the newest part of the helper, so point at a stale
# install, the likeliest cause, rather than only at the missing
# line.
ok_waited() { # desc file
	if [ -f "$2" ] && grep -q -F -- "$MSG_WAITING" "$2"; then
		pass "$1"
	else
		fail "$1" \
			"no \"$MSG_WAITING\" in $2; $STALE_HINT"
	fi
}

ok_file() { # desc path
	if [ -f "$2" ] && [ -s "$2" ]; then
		pass "$1"
	else
		fail "$1" "missing or empty: $2"
	fi
}

ok_absent() { # desc path
	if [ -e "$2" ] || [ -L "$2" ]; then
		fail "$1" "still present: $2"
	else
		pass "$1"
	fi
}

# --- lock helpers --------------------------------------------------

# flock in a subshell: a failed redirection on exec must not
# terminate this script.
lock_is_free() {
	( exec 9>> "$LOCK_FILE"; "$FLOCK" -n -x 9; ) 2>/dev/null
}

lock_pid() {
	cat "$LOCK_FILE" 2>/dev/null
}

wait_lock() { # want(busy|free) seconds
	_want=$1
	_left=$(($2 * POLL_PER_SEC))
	while [ "$_left" -gt 0 ]; do
		if lock_is_free; then _state=free; else _state=busy; fi
		[ "$_state" = "$_want" ] && return 0
		sleep "$POLL"
		_left=$((_left - 1))
	done
	return 1
}

wait_file() { # path seconds
	_left=$(($2 * POLL_PER_SEC))
	while [ "$_left" -gt 0 ]; do
		[ -e "$1" ] && return 0
		sleep "$POLL"
		_left=$((_left - 1))
	done
	return 1
}

wait_grep() { # file pattern seconds
	_left=$(($3 * POLL_PER_SEC))
	while [ "$_left" -gt 0 ]; do
		grep -q -F -- "$2" "$1" 2>/dev/null && return 0
		sleep "$POLL"
		_left=$((_left - 1))
	done
	return 1
}

# How many times the stub vendor tool has driven the SSD. A
# reused dump must not add a run.
stub_runs() {
	grep -c . "$RUNS_FILE" 2>/dev/null || echo 0
}

# --- directory snapshots -------------------------------------------

# Content fingerprint, so a scenario can prove that a refused
# caller did not touch the work dir of the running collection.
snapshot_dir() { # path
	if [ ! -d "$1" ]; then
		echo "ABSENT $1"
		return 0
	fi
	( cd "$1" 2>/dev/null || exit 0
	  find . | sort | while IFS= read -r p; do
		if [ -f "$p" ]; then
			echo "$p $(cksum < "$p")"
		else
			echo "$p NOT-A-FILE"
		fi
	  done )
}

# --- holders -------------------------------------------------------

# A holder keeps the lock until release_holder(). The stub
# touches the ready file once its dump file is complete, so a
# scenario can snapshot the work dir without racing the holder.
# $1 is how long the lock may take to appear: generate-dump
# reaches its SSD step only near the end of a full collection.
holder_ready() { # [seconds]
	HOLDER_LOCK_PID=""
	_left=$((${1:-30} * POLL_PER_SEC))
	while [ "$_left" -gt 0 ]; do
		lock_is_free || break
		if ! kill -0 "$HOLDER_PID" 2>/dev/null; then
			fail "the running collection takes $LOCK_FILE" \
				"it exited without locking; see $WORK/holder.out"
			return 1
		fi
		sleep "$POLL"
		_left=$((_left - 1))
	done
	if [ "$_left" -le 0 ]; then
		fail "the running collection takes $LOCK_FILE" \
			"never locked, so this scenario cannot run; see $WORK/holder.out"
		return 1
	fi
	HOLDER_LOCK_PID=$(lock_pid)
	if ! wait_file "$READY_FILE" 60; then
		fail "the running collection reaches its vendor tool" \
			"see $WORK/holder.out"
		return 1
	fi
	return 0
}

start_collect_holder() { # [extra collector arguments]
	rm -f "$READY_FILE"
	: > "$HOLD_FILE"
	"$SSD_DUMP_PY" --config "$CFG" --timeout "$HOLD_TIMEOUT" \
		--outdir "$SSD_LOG_DIR" "$@" > "$WORK/holder.out" 2>&1 &
	HOLDER_PID=$!
	holder_ready
}

# The lock is taken by the helper that generate-dump spawns for
# its SSD step, not by generate-dump itself, so this holder has
# to be found through the lock file.
start_generate_dump_holder() {
	rm -f "$READY_FILE"
	: > "$HOLD_FILE"
	(
		# shellcheck disable=SC2030,SC2031
		PATH="$SHIM_DIR:$PATH"   # the shim stays in the subshell
		export PATH
		exec "$GENERATE_DUMP_SH" "$GENERATE_DUMP_MODE"
	) > "$WORK/holder.out" 2>&1 &
	HOLDER_PID=$!
	holder_ready "$GENERATE_DUMP_WAIT"
}

# The helper takes the lock itself and then runs the collector
# with HW_MGMT_SSD_DUMP_LOCK_HELD=1. A PATH shim adds --config so
# the inner collector is the real one, on the stub vendor tool.
start_helper_holder() {
	rm -f "$READY_FILE"
	: > "$HOLD_FILE"
	(
		# shellcheck disable=SC2030,SC2031
		PATH="$SHIM_DIR:$PATH"   # the shim stays in the subshell
		export PATH
		exec "$COLLECT_SH" "$DUMP_FOLDER" "$SSD_LOG_DIR"
	) > "$WORK/holder.out" 2>&1 &
	HOLDER_PID=$!
	holder_ready
}

release_holder() {
	[ -n "$HOLDER_PID" ] || return 0
	rm -f "$HOLD_FILE"
	wait "$HOLDER_PID" 2>/dev/null
	HOLDER_RC=$?
	HOLDER_PID=""
	return 0
}

# Killing a holder is not enough: generate-dump spawns the SSD
# helper, which spawns the collector, so the process holding the
# lock is a grandchild and outlives its parent. Left running, it
# would rm -rf and recollect /var/log/ssd-dump after cleanup has
# restored the real data there.
kill_tree() { # pid
	for _child in $(pgrep -P "$1" 2>/dev/null); do
		kill_tree "$_child"
	done
	kill "$1" 2>/dev/null
	return 0
}

# Nothing may still be collecting when the saved data goes back.
no_ssd_dump_procs() { # seconds
	_left=$(($1 * POLL_PER_SEC))
	while [ "$_left" -gt 0 ]; do
		pgrep -f hw-management-ssd-dump >/dev/null 2>&1 || return 0
		sleep "$POLL"
		_left=$((_left - 1))
	done
	return 1
}

kill_holder() {
	if [ -n "$SECOND_PID" ]; then
		rm -f "$HOLD_FILE"
		kill_tree "$SECOND_PID"
		wait "$SECOND_PID" 2>/dev/null
		SECOND_PID=""
	fi
	[ -n "$HOLDER_PID" ] || return 0
	rm -f "$HOLD_FILE"
	wait_lock free 20
	kill_tree "$HOLDER_PID"
	wait "$HOLDER_PID" 2>/dev/null
	HOLDER_PID=""
	return 0
}

# Collector and helper both record their pid, so a refusal always
# names the process that is holding the lock. The helper's $$ is
# $! here because start_helper_holder execs it.
ok_holder_named() { # desc file
	ok_grep "$1" "$2" "pid $HOLDER_PID"
}

# Scenario 6 cannot compare against $HOLDER_PID: the holder is a
# grandchild. Read the recorded pid, but confirm against /proc
# that it really is the SSD helper before believing it.
ok_holder_is_helper() { # desc file
	case "$HOLDER_LOCK_PID" in
		"" | *[!0-9]*)
			fail "$1" "no pid recorded in $LOCK_FILE"
			return 0
			;;
	esac
	if ! grep -q -F -- "pid $HOLDER_LOCK_PID" "$2" 2>/dev/null; then
		fail "$1" "refusal does not name pid $HOLDER_LOCK_PID"
		return 0
	fi
	_cmd=""
	if [ -r "/proc/$HOLDER_LOCK_PID/cmdline" ]; then
		_cmd=$(tr '\0' ' ' < "/proc/$HOLDER_LOCK_PID/cmdline")
	fi
	case "$_cmd" in
		*hw-management-ssd-dump-collect.sh*)
			pass "$1"
			;;
		*)
			fail "$1" \
				"pid $HOLDER_LOCK_PID is not the generate-dump SSD helper"
			;;
	esac
}

# --- second callers ------------------------------------------------

# stdout and stderr are kept apart: the status fields go to
# stdout, the console lines to stderr.
run_second() { # command...
	"$@" > "$WORK/second.out" 2> "$WORK/second.err"
	SECOND_RC=$?
	return 0
}

# The helper no longer gives up on a busy lock, so the scenarios
# that let it through have to start it, watch it enter the wait,
# and only then free the lock.
start_waiting_helper() {
	: > "$WORK/second.out"
	: > "$WORK/second.err"
	(
		# shellcheck disable=SC2030,SC2031
		PATH="$SHIM_DIR:$PATH"   # it may end up collecting
		export PATH
		exec "$COLLECT_SH" "$DUMP_FOLDER" "$SSD_LOG_DIR"
	) > "$WORK/second.out" 2> "$WORK/second.err" &
	SECOND_PID=$!
	if ! wait_grep "$WORK/second.err" "$MSG_WAITING" 30; then
		fail "the helper waits for the busy lock" \
			"no \"$MSG_WAITING\" in $WORK/second.err; $STALE_HINT"
		return 1
	fi
	return 0
}

reap_waiting_helper() {
	wait "$SECOND_PID" 2>/dev/null
	SECOND_RC=$?
	SECOND_PID=""
	return 0
}

# --- scenarios -----------------------------------------------------

scenario_0() {
	say "[ RUN  ] 0: baseline, one collect, no contention"
	rm -f "$HOLD_FILE"
	"$SSD_DUMP_PY" --config "$CFG" --timeout "$HOLD_TIMEOUT" \
		--outdir "$SSD_LOG_DIR" > "$WORK/second.out" 2> "$WORK/second.err"
	SECOND_RC=$?
	ok_eq "collect returns 0" 0 "$SECOND_RC"
	ok_file "$SSD_TARBALL is created" "$SSD_TARBALL"
	ok_grep "console reports success" "$WORK/second.err" "$MSG_SUCCEEDED"
	ok_absent "work dir is packed away" "$SSD_LOG_DIR"
	if lock_is_free; then
		pass "lock is free again"
	else
		fail "lock is free again" "$LOCK_FILE still held"
	fi
	ok_eq "lock file keeps no stale pid" "" "$(lock_pid)"
}

scenario_1() {
	say "[ RUN  ] 1: collect holds the lock, a second collector is called"
	start_collect_holder || return 0
	before=$(snapshot_dir "$SSD_LOG_DIR")

	run_second "$SSD_DUMP_PY"

	ok_eq "second collector returns $RC_LOCKED" "$RC_LOCKED" "$SECOND_RC"
	ok_grep "console says busy" "$WORK/second.err" "$MSG_BUSY"
	ok_holder_named "refusal names the holder" "$WORK/second.err"
	ok_nogrep "no success claimed" "$WORK/second.err" "$MSG_SUCCEEDED"
	ok_nogrep "not reported as a dump failure" "$WORK/second.err" \
		"SSD dump tool failed:"
	ok_eq "running collection keeps its work dir" \
		"$before" "$(snapshot_dir "$SSD_LOG_DIR")"

	release_holder
	ok_eq "the holder still completes" 0 "$HOLDER_RC"
	ok_file "the holder still packs its archive" "$SSD_TARBALL"
}

scenario_2() {
	say "[ RUN  ] 2: collect holds the lock, --verify is called"
	start_collect_holder || return 0
	before=$(snapshot_dir "$SSD_LOG_DIR")

	run_second "$SSD_DUMP_PY" --verify

	ok_eq "--verify returns $RC_LOCKED" "$RC_LOCKED" "$SECOND_RC"
	ok_grep "console says busy" "$WORK/second.err" "$MSG_BUSY"
	ok_holder_named "refusal names the holder" "$WORK/second.err"
	ok_grep "status fields report the lock" "$WORK/second.out" "locked: yes"
	ok_nogrep "verify does not claim to have passed" "$WORK/second.err" \
		"verify passed"
	ok_nogrep "no success claimed" "$WORK/second.err" "$MSG_SUCCEEDED"
	ok_eq "running collection keeps its work dir" \
		"$before" "$(snapshot_dir "$SSD_LOG_DIR")"

	release_holder
	ok_eq "the holder still completes" 0 "$HOLDER_RC"
}

scenario_3() {
	say "[ RUN  ] 3: collect holds the lock, generate-dump runs"
	if [ -z "$GENERATE_DUMP_SH" ]; then
		say "[ SKIP ] 3: hw-management-generate-dump.sh not found"
		return 0
	fi
	start_collect_holder || return 0
	before=$(snapshot_dir "$SSD_LOG_DIR")

	say "         running $GENERATE_DUMP_SH $GENERATE_DUMP_MODE (slow)"
	run_second "$GENERATE_DUMP_SH" "$GENERATE_DUMP_MODE"

	ok_eq "generate-dump returns 0" 0 "$SECOND_RC"
	ok_file "the hw-mgmt dump is still packed" "$DUMP_TARBALL"

	s3="$WORK/s3"
	rm -rf "$s3"
	mkdir -p "$s3"
	tar -tzf "$DUMP_TARBALL" > "$s3/listing" 2>/dev/null
	tar -xzf "$DUMP_TARBALL" -C "$s3" ./ssd-dump/ssd-dump-status.log 2>/dev/null
	tar -xzf "$DUMP_TARBALL" -C "$s3" ./ssd-dump-collect.log 2>/dev/null

	# The lock covers the SSD dump only: everything else in the
	# hw-mgmt dump must still have been collected.
	ok_grep "the rest of the dump was collected" "$s3/listing" "./sys_version"
	ok_grep "the SSD section is reported" "$s3/listing" \
		"./ssd-dump/ssd-dump-status.log"
	ok_grep "the SSD section is marked locked" \
		"$s3/ssd-dump/ssd-dump-status.log" "locked: yes"
	ok_grep "the SSD section is a warning" \
		"$s3/ssd-dump/ssd-dump-status.log" "status: warning"
	ok_waited "the helper waited before giving up" \
		"$s3/ssd-dump-collect.log"
	ok_grep "the helper log says busy" "$s3/ssd-dump-collect.log" "$MSG_BUSY"
	ok_nogrep "the helper log claims no success" \
		"$s3/ssd-dump-collect.log" "$MSG_SUCCEEDED"
	ok_eq "running collection keeps its work dir" \
		"$before" "$(snapshot_dir "$SSD_LOG_DIR")"

	release_holder
	ok_eq "the holder still completes" 0 "$HOLDER_RC"
	ok_file "the holder still packs its archive" "$SSD_TARBALL"
}

scenario_4() {
	say "[ RUN  ] 4: the generate-dump helper holds the lock, a collector is called"
	start_helper_holder || return 0
	before=$(snapshot_dir "$SSD_LOG_DIR")

	run_second "$SSD_DUMP_PY"

	ok_eq "collector returns $RC_LOCKED" "$RC_LOCKED" "$SECOND_RC"
	ok_grep "console says busy" "$WORK/second.err" "$MSG_BUSY"
	ok_holder_named "refusal names the holder" "$WORK/second.err"
	ok_nogrep "no success claimed" "$WORK/second.err" "$MSG_SUCCEEDED"
	ok_eq "the helper keeps its work dir" \
		"$before" "$(snapshot_dir "$SSD_LOG_DIR")"
	ok_absent "the refused caller packed nothing" "$SSD_TARBALL"

	release_holder
	ok_eq "the helper still completes" 0 "$HOLDER_RC"
	ok_file "the helper still delivered its copy" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log"
	ok_grep "the helper copy is ok" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log" "status: ok"
}

scenario_5() {
	say "[ RUN  ] 5: collect never releases, the generate-dump helper waits it out"
	start_collect_holder || return 0
	before=$(snapshot_dir "$SSD_LOG_DIR")

	started=$(date +%s)
	run_second "$COLLECT_SH" "$DUMP_FOLDER" "$SSD_LOG_DIR"
	elapsed=$(($(date +%s) - started))

	ok_waited "the helper waits instead of giving up" \
		"$WORK/second.err"
	if [ "$elapsed" -ge "$LOCK_WAIT_SEC" ]; then
		pass "it waited the whole ${LOCK_WAIT_SEC}s budget"
	else
		fail "it waited the whole ${LOCK_WAIT_SEC}s budget" \
			"gave up after ${elapsed}s"
	fi
	ok_eq "then returns $RC_LOCKED" "$RC_LOCKED" "$SECOND_RC"
	ok_grep "console says busy" "$WORK/second.err" "$MSG_BUSY"
	ok_grep "the refusal says it waited" "$WORK/second.err" \
		"still running after"
	ok_holder_named "refusal names the holder" "$WORK/second.err"
	# The race the lock exists for: the helper rm -rf's
	# $SSD_LOG_DIR right after it takes the lock.
	ok_eq "the helper did not wipe the running work dir" \
		"$before" "$(snapshot_dir "$SSD_LOG_DIR")"
	ok_file "the refusal is recorded for generate-dump" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log"
	ok_grep "the recorded status is locked" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log" "locked: yes"
	ok_grep "the recorded status is a warning" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log" "status: warning"

	release_holder
	ok_eq "the holder still completes" 0 "$HOLDER_RC"
	ok_file "the holder still packs its archive" "$SSD_TARBALL"
}

scenario_7() {
	say "[ RUN  ] 7: collect finishes while the helper waits, its dump is reused"
	start_collect_holder || return 0
	runs_before=$(stub_runs)

	start_waiting_helper || return 0
	release_holder
	ok_eq "the collect it waited for completes" 0 "$HOLDER_RC"
	reap_waiting_helper

	ok_eq "the helper returns 0" 0 "$SECOND_RC"
	ok_grep "it reports the reuse" "$WORK/second.err" "$MSG_REUSED"
	ok_grep "it names the archive it took" "$WORK/second.err" "$SSD_TARBALL"
	# The point of reusing: the SSD is not driven a second time.
	ok_eq "the vendor tool did not run again" \
		"$runs_before" "$(stub_runs)"
	ok_file "generate-dump gets the dump" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log"
	ok_grep "and it is the finished one" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log" "status: ok"
	ok_grep "the reused dump carries the vendor file" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log" "stub-nandlog.bin"
	ok_grep "console reports success" "$WORK/second.err" "$MSG_SUCCEEDED"
	ok_nogrep "not reported as locked" "$WORK/second.err" "$MSG_BUSY"
	# Reuse copies, it does not consume: the archive belongs to
	# whoever ran the standalone dump.
	ok_file "the standalone archive is left alone" "$SSD_TARBALL"
}

scenario_8() {
	say "[ RUN  ] 8: helper waits for another helper, then collects for itself"
	start_helper_holder || return 0
	runs_before=$(stub_runs)

	start_waiting_helper || return 0
	release_holder
	ok_eq "the helper it waited for completes" 0 "$HOLDER_RC"
	reap_waiting_helper

	ok_eq "the second helper returns 0" 0 "$SECOND_RC"
	ok_waited "it waited first" "$WORK/second.err"
	# A helper leaves nothing in the default location, so there
	# is nothing to reuse and the dump has to be collected.
	ok_nogrep "nothing was there to reuse" "$WORK/second.err" "$MSG_REUSED"
	ok_eq "so it ran the vendor tool itself" \
		"$((runs_before + 1))" "$(stub_runs)"
	ok_file "generate-dump gets the dump" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log"
	ok_grep "and it is a fresh ok one" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log" "status: ok"
	ok_grep "console reports success" "$WORK/second.err" "$MSG_SUCCEEDED"
	ok_nogrep "not reported as locked" "$WORK/second.err" "$MSG_BUSY"
}

scenario_9() {
	say "[ RUN  ] 9: a --no-tar collect finishes while the helper waits"
	start_collect_holder --no-tar || return 0
	runs_before=$(stub_runs)

	start_waiting_helper || return 0
	release_holder
	ok_eq "the collect it waited for completes" 0 "$HOLDER_RC"
	reap_waiting_helper

	ok_eq "the helper returns 0" 0 "$SECOND_RC"
	# --no-tar leaves the work dir instead of an archive, so
	# that is what gets reused.
	ok_grep "it reports the reuse" "$WORK/second.err" "$MSG_REUSED"
	ok_grep "it names the work dir it took" "$WORK/second.err" "$SSD_LOG_DIR"
	ok_eq "the vendor tool did not run again" \
		"$runs_before" "$(stub_runs)"
	ok_grep "generate-dump gets the finished dump" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log" "status: ok"
	ok_grep "console reports success" "$WORK/second.err" "$MSG_SUCCEEDED"
	# A --no-tar run keeps its work dir on purpose; reusing it
	# must not take it away from its owner.
	if [ -d "$SSD_LOG_DIR" ]; then
		pass "the standalone work dir is left in place"
	else
		fail "the standalone work dir is left in place" \
			"$SSD_LOG_DIR was removed"
	fi
}

scenario_10() {
	say "[ RUN  ] 10: an old archive in the default location is not reused"
	# The holder collects into its own --outdir, so it never
	# touches /var/log/ssd-dump.tar.gz; a --verify holder would
	# not either. What is already there is somebody else's older
	# dump and must not be passed off as the current SSD state.
	rm -f "$HOLD_FILE"
	if ! "$SSD_DUMP_PY" --config "$CFG" --timeout "$HOLD_TIMEOUT" \
		--outdir "$SSD_LOG_DIR" > "$WORK/stale.out" 2>&1; then
		fail "an old archive can be staged" "see $WORK/stale.out"
		return 0
	fi
	touch -d "@$(($(date +%s) - 3600))" "$SSD_TARBALL" 2>/dev/null
	ok_file "an old archive is in the default location" "$SSD_TARBALL"
	stale=$(cksum < "$SSD_TARBALL")

	start_collect_holder --outdir "$WORK/ssd-dump" || return 0
	runs_before=$(stub_runs)
	ok_eq "the holder left the old archive alone" \
		"$stale" "$(cksum < "$SSD_TARBALL")"

	start_waiting_helper || return 0
	release_holder
	ok_eq "the holder completes" 0 "$HOLDER_RC"
	ok_file "the holder packed its own archive" "$WORK/ssd-dump.tar.gz"
	reap_waiting_helper

	ok_eq "the helper returns 0" 0 "$SECOND_RC"
	ok_nogrep "it did not reuse the old archive" \
		"$WORK/second.err" "$MSG_REUSED"
	ok_eq "it collected instead" \
		"$((runs_before + 1))" "$(stub_runs)"
	ok_grep "generate-dump gets a fresh ok dump" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log" "status: ok"
	ok_grep "console reports success" "$WORK/second.err" "$MSG_SUCCEEDED"
}

scenario_11() {
	say "[ RUN  ] 11: without a usable lock the helper collects nothing"
	# Blocking the lock file stands in for a system with no flock
	# at all. The helper must not touch $SSD_LOG_DIR then: the
	# work dir may belong to a collection in progress, and every
	# collect starts by removing it.
	rm -f "$LOCK_FILE"
	if ! mkdir "$LOCK_FILE" 2>/dev/null; then
		fail "the lock file can be blocked" "mkdir $LOCK_FILE failed"
		return 0
	fi
	rm -rf "$SSD_LOG_DIR"
	mkdir -p "$SSD_LOG_DIR"
	printf 'in-progress collection\n' > "$SSD_LOG_DIR/nandlog_0.bin"
	before=$(snapshot_dir "$SSD_LOG_DIR")
	runs_before=$(stub_runs)

	run_second "$COLLECT_SH" "$DUMP_FOLDER" "$SSD_LOG_DIR"

	rmdir "$LOCK_FILE" 2>/dev/null
	ok_eq "the helper returns 0" 0 "$SECOND_RC"
	ok_grep "it reports the missing lock" "$WORK/second.err" \
		"SSD dump tool failed: $MSG_NO_LOCK"
	ok_nogrep "no success claimed" "$WORK/second.err" "$MSG_SUCCEEDED"
	# The point of refusing: an unlocked helper must not delete
	# the results another collection is still writing.
	ok_eq "the work dir is untouched" \
		"$before" "$(snapshot_dir "$SSD_LOG_DIR")"
	ok_eq "the vendor tool did not run" "$runs_before" "$(stub_runs)"
	ok_grep "generate-dump is told why" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log" "status: warning"
	# Not contention: nobody held the lock, it was unusable.
	ok_nogrep "it is not reported as contention" \
		"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log" "locked: yes"
}

scenario_12() {
	say "[ RUN  ] 12: a --verify result in the default location is not reused"
	# A --verify passes its checks without reading the SSD and
	# still writes status: ok into the default location, so the
	# helper must not take it for a dump. The fixture is a real
	# verify run, planted while the helper is already waiting so
	# that it is as fresh as one that finished during the wait.
	rm -rf "$SSD_LOG_DIR"
	if ! "$SSD_DUMP_PY" --config "$CFG" --verify \
		> "$WORK/verify.out" 2>&1; then
		fail "a verify result can be staged" "see $WORK/verify.out"
		return 0
	fi
	ok_grep "verify reports status: ok" \
		"$SSD_LOG_DIR/ssd-dump-status.log" "status: ok"
	ok_grep "and marks itself a verify" \
		"$SSD_LOG_DIR/ssd-dump-status.log" "verify: yes"
	cp "$SSD_LOG_DIR/ssd-dump-status.log" "$WORK/verify-status.log"
	rm -rf "$SSD_LOG_DIR"

	rm -f "$HOLD_FILE"
	start_collect_holder --outdir "$WORK/ssd-dump" || return 0
	runs_before=$(stub_runs)
	start_waiting_helper || return 0

	# The helper is blocked on the lock, so this cannot race it.
	mkdir -p "$SSD_LOG_DIR"
	cp "$WORK/verify-status.log" "$SSD_LOG_DIR/ssd-dump-status.log"
	release_holder
	ok_eq "the holder completes" 0 "$HOLDER_RC"
	reap_waiting_helper

	ok_eq "the helper returns 0" 0 "$SECOND_RC"
	ok_nogrep "it did not reuse the verify result" \
		"$WORK/second.err" "$MSG_REUSED"
	ok_eq "it collected instead" \
		"$((runs_before + 1))" "$(stub_runs)"
	ok_file "the dump holds real vendor data" \
		"$DUMP_FOLDER/ssd-dump/stub-nandlog.bin"
	ok_grep "console reports success" "$WORK/second.err" "$MSG_SUCCEEDED"
}

scenario_6() {
	say "[ RUN  ] 6: generate-dump is running, a collector is called"
	if [ -z "$GENERATE_DUMP_SH" ]; then
		say "[ SKIP ] 6: hw-management-generate-dump.sh not found"
		return 0
	fi
	say "         waiting for $GENERATE_DUMP_SH $GENERATE_DUMP_MODE" \
		"to reach its SSD step (slow)"
	start_generate_dump_holder || return 0
	before=$(snapshot_dir "$SSD_LOG_DIR")

	run_second "$SSD_DUMP_PY"

	ok_eq "collector returns $RC_LOCKED" "$RC_LOCKED" "$SECOND_RC"
	ok_grep "console says busy" "$WORK/second.err" "$MSG_BUSY"
	ok_holder_is_helper "refusal names the generate-dump helper" \
		"$WORK/second.err"
	ok_nogrep "no success claimed" "$WORK/second.err" "$MSG_SUCCEEDED"
	ok_eq "generate-dump keeps its SSD work dir" \
		"$before" "$(snapshot_dir "$SSD_LOG_DIR")"
	ok_absent "the refused caller packed nothing" "$SSD_TARBALL"

	release_holder
	ok_eq "generate-dump returns 0" 0 "$HOLDER_RC"
	ok_file "the hw-mgmt dump is packed" "$DUMP_TARBALL"

	s6="$WORK/s6"
	rm -rf "$s6"
	mkdir -p "$s6"
	tar -xzf "$DUMP_TARBALL" -C "$s6" ./ssd-dump/ssd-dump-status.log 2>/dev/null

	# The refused caller must not have cost generate-dump its own
	# SSD dump: this is the run that held the lock, so it wins.
	ok_grep "generate-dump still got its SSD dump" \
		"$s6/ssd-dump/ssd-dump-status.log" "status: ok"
	ok_nogrep "generate-dump is not the one reported locked" \
		"$s6/ssd-dump/ssd-dump-status.log" "locked: yes"
}

# --- setup / teardown ----------------------------------------------

# The marker is written only once the path is ours to delete:
# either it was moved aside or there was nothing there. A signal
# between two save_path calls, or a move that fails and dies,
# otherwise leaves cleanup removing a path whose only copy is
# still the operator's. A failed move takes its fragment with
# it, so nothing is left for cleanup to mistake for the copy.
save_path() { # path
	_base="$BACKUP/$(basename "$1")"
	if [ -e "$1" ] || [ -L "$1" ]; then
		mv -- "$1" "$_base.saved" 2>/dev/null || {
			rm -rf -- "$_base.saved"
			die "cannot move $1 aside"
		}
	fi
	: > "$_base.taken"
}

# Without the marker the setup never finished with this path,
# and then the path itself says what happened. $BACKUP is on
# another filesystem than /var/log, so the move is a copy and an
# unlink: it empties the path only once the copy is whole. A
# path still there is therefore the operator's, beside at most a
# fragment of a move that failed, and a path gone has a complete
# copy waiting even if the signal arrived before the marker.
# With the marker, whatever is there now is the test's own.
restore_path() { # path
	_base="$BACKUP/$(basename "$1")"
	if ! [ -f "$_base.taken" ] && { [ -e "$1" ] || [ -L "$1" ]; }; then
		rm -rf -- "$_base.saved"
		return 0
	fi
	rm -rf -- "$1"
	if [ -e "$_base.saved" ] || [ -L "$_base.saved" ]; then
		mv -- "$_base.saved" "$1" 2>/dev/null
	fi
	return 0
}

cleanup() {
	[ "$CLEANED" = "1" ] && return 0
	CLEANED=1
	kill_holder
	if [ -n "$BACKUP" ] && [ -d "$BACKUP" ]; then
		if no_ssd_dump_procs 60; then
			restore_path "$SSD_LOG_DIR"
			restore_path "$SSD_TARBALL"
			restore_path "$DUMP_FOLDER"
			restore_path "$DUMP_TARBALL"
		else
			# Restoring now would hand the live collection the
			# operator's data to delete. Leave it saved instead.
			KEEP_WORK=1
			say "an SSD dump is still running; the saved data is" \
				"left in $BACKUP, restore it by hand"
		fi
	fi
	if [ -n "$WORK" ] && [ -d "$WORK" ]; then
		if [ "$KEEP_WORK" = "1" ]; then
			say "work directory kept: $WORK"
		else
			rm -rf "$WORK"
		fi
	fi
	return 0
}

resolve_bin() { # name
	if [ -n "$SSD_DUMP_BIN_DIR" ] && [ -x "$SSD_DUMP_BIN_DIR/$1" ]; then
		echo "$SSD_DUMP_BIN_DIR/$1"
		return 0
	fi
	command -v "$1" 2>/dev/null
}

selected_includes() { # list
	for _s in $SCENARIOS; do
		for _w in $1; do
			[ "$_s" = "$_w" ] && return 0
		done
	done
	return 1
}

prerequisites() {
	[ "$(id -u)" = "0" ] ||
		die "must run as root: the lock lives in /run and the collectors write /var/log"
	# Looked up, not hard-coded, because the helper looks it up
	# too: a flock outside /usr/bin must not read as "no flock".
	FLOCK=$(command -v flock 2>/dev/null)
	if [ -z "$FLOCK" ] || [ ! -x "$FLOCK" ]; then
		die "flock not found on PATH (util-linux); the lock cannot be tested"
	fi
	command -v pgrep >/dev/null 2>&1 ||
		die "pgrep not found (procps); a killed holder could outlive cleanup"
	if [ -n "$SSD_DUMP_BIN_DIR" ]; then
		# shellcheck disable=SC2031  # not a subshell, SC2030 fallout
		PATH="$SSD_DUMP_BIN_DIR:$PATH"
		export PATH
	fi
	SSD_DUMP_PY=$(resolve_bin hw-management-ssd-dump.py)
	[ -n "$SSD_DUMP_PY" ] || die "hw-management-ssd-dump.py not found"
	COLLECT_SH=$(resolve_bin hw-management-ssd-dump-collect.sh)
	[ -n "$COLLECT_SH" ] || die "hw-management-ssd-dump-collect.sh not found"
	GENERATE_DUMP_SH=$(resolve_bin hw-management-generate-dump.sh)
	command -v python3 >/dev/null 2>&1 || die "python3 not found"

	# An install older than the feature under test is the
	# likeliest reason for a run full of unexplained failures,
	# so say so once here instead of failing the same way in
	# every scenario. A script that cannot even print the line
	# a scenario waits for certainly does not have the feature;
	# finding the line is not proof that it does, which is why
	# the scenarios still check the behaviour.
	grep -q -F "$MSG_BUSY" "$SSD_DUMP_PY" 2>/dev/null ||
		die "$SSD_DUMP_PY predates the SSD dump lock; install the current hw-management scripts"
	if selected_includes "$WAIT_SCENARIOS"; then
		grep -q -F "$MSG_WAITING" "$COLLECT_SH" 2>/dev/null ||
			die "$COLLECT_SH predates the lock wait (scenarios $WAIT_SCENARIOS); install the current hw-management scripts"
	fi

	if selected_includes "$NOLOCK_SCENARIOS"; then
		grep -q -F "$MSG_NO_LOCK" "$COLLECT_SH" 2>/dev/null ||
			die "$COLLECT_SH predates the no-lock refusal (scenarios $NOLOCK_SCENARIOS); install the current hw-management scripts"
	fi

	# No NVMe means the collector skips instead of collecting, so
	# it would never hold the lock and nothing could be tested.
	[ -n "$(ls /sys/class/nvme 2>/dev/null)" ] ||
		die "no NVMe controller in /sys/class/nvme"

	( exec 9>> "$LOCK_FILE"; ) 2>/dev/null ||
		die "cannot create $LOCK_FILE"
	lock_is_free ||
		die "an SSD dump collection is already running (pid $(lock_pid)); rerun later"
}

make_work_area() {
	WORK=$(mktemp -d /tmp/ssd-dump-lock-test.XXXXXX) ||
		die "cannot create a work directory"
	BACKUP="$WORK/backup"
	SHIM_DIR="$WORK/shim"
	HOLD_FILE="$WORK/hold"
	READY_FILE="$WORK/ready"
	RUNS_FILE="$WORK/stub-runs"
	CFG="$WORK/ssd-dump-config.json"
	STUB="$WORK/stub-vendor-tool.sh"
	mkdir -p "$BACKUP" "$SHIM_DIR"
	: > "$RUNS_FILE"

	# Stub vendor tool. cwd is the work dir, so the marker is
	# what the collector packs. Every run is counted, which is
	# how a scenario tells a reused dump from a fresh one. The
	# ready file is touched only after the marker is complete.
	# Blocks until the hold file goes away; the iteration cap
	# keeps a stuck test bounded.
	cat > "$STUB" <<EOF
#!/bin/sh
echo "stub vendor tool args: \$*"
echo "\$\$" >> "$RUNS_FILE"
printf 'ssd dump lock test marker\n' > stub-nandlog.bin
: > "$READY_FILE"
i=0
while [ -e "$HOLD_FILE" ] && [ "\$i" -lt "$HOLD_TIMEOUT" ]; do
	sleep 1
	i=\$((i + 1))
done
exit 0
EOF
	chmod 0755 "$STUB"

	# "*" matches any model through the config fnmatch fallback,
	# so the holder works on every target. timeout_sec is the
	# budget the helper waits for a busy lock, kept short so a
	# scenario that waits it out does not take two minutes; every
	# collector call here passes --timeout, which overrides it
	# for the vendor run itself.
	cat > "$CFG" <<EOF
{
  "defaults": { "timeout_sec": $LOCK_WAIT_SEC, "min_free_mb": 1 },
  "vendors": {
    "LockTest": {
      "models": {
        "*": {
          "tool": "$STUB",
          "args": ["{device}"],
          "device_form": "controller",
          "timeout_sec": $LOCK_WAIT_SEC
        }
      }
    }
  }
}
EOF
	# The helper reads its wait budget from here.
	SSD_DUMP_CONFIG="$CFG"
	export SSD_DUMP_CONFIG

	# The helper looks the collector up on PATH, so this shim is
	# how scenario 4 points the real collector at the stub.
	cat > "$SHIM_DIR/hw-management-ssd-dump.py" <<EOF
#!/bin/sh
exec "$SSD_DUMP_PY" --config "$CFG" --timeout "$HOLD_TIMEOUT" "\$@"
EOF
	chmod 0755 "$SHIM_DIR/hw-management-ssd-dump.py"
}

reset_state() {
	rm -rf "$SSD_LOG_DIR" "$SSD_TARBALL" "$DUMP_FOLDER" "$DUMP_TARBALL"
}

# --- main ----------------------------------------------------------

while [ $# -gt 0 ]; do
	case "$1" in
		-h | --help) usage; exit 0 ;;
		-l | --list) list_scenarios; exit 0 ;;
		-k | --keep) KEEP_WORK=1 ;;
		-*) die "unknown option: $1 (-h for usage)" ;;
		*) break ;;
	esac
	shift
done

SCENARIOS=$*
[ -n "$SCENARIOS" ] || SCENARIOS=$ALL_SCENARIOS
for s in $SCENARIOS; do
	case "$s" in
		0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12) ;;
		*) die "unknown scenario: $s (-l to list)" ;;
	esac
done

POLL=0.2
POLL_PER_SEC=5
if ! sleep 0.2 2>/dev/null; then
	POLL=1
	POLL_PER_SEC=1
fi

prerequisites
make_work_area
trap 'cleanup' EXIT
trap 'cleanup; exit 1' INT TERM

say "collector:    $SSD_DUMP_PY"
say "helper:       $COLLECT_SH"
say "generate:     ${GENERATE_DUMP_SH:-<not found, scenarios 3 and 6 skipped>}"
say "lock file:    $LOCK_FILE"
say "work dir:     $WORK"
say ""

# Scenario 0 is also the environment check: if a plain collect
# cannot complete here, the contention scenarios would only
# report that same failure five more times.
save_path "$SSD_LOG_DIR"
save_path "$SSD_TARBALL"
save_path "$DUMP_FOLDER"
save_path "$DUMP_TARBALL"

SCENARIO_FAILED=0
scenario_0
if [ "$SCENARIO_FAILED" = "1" ]; then
	say "[ FAIL ] 0: baseline"
	say ""
	say "A plain collect does not work here, so the lock scenarios"
	say "cannot be trusted. See $WORK/second.err"
	KEEP_WORK=1
	exit 1
fi
say "[ PASS ] 0"

for s in $SCENARIOS; do
	[ "$s" = "0" ] && continue
	say ""
	reset_state
	SCENARIO_FAILED=0
	"scenario_$s"
	kill_holder
	if [ "$SCENARIO_FAILED" = "1" ]; then
		say "[ FAIL ] $s"
	else
		say "[ PASS ] $s"
	fi
done

say ""
say "----------------------------------------------------------"
if [ "$FAILED" = "0" ]; then
	say "$CHECKS checks passed"
	exit 0
fi
say "$FAILED of $CHECKS checks FAILED"
exit 1
