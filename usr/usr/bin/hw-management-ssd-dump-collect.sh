#!/bin/sh
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
# DAMAGE.
#

# Not a user CLI. generate-dump.sh dump_cmd always passes the
# two allowlisted paths below. Do not invoke this helper with
# other directories. Custom location / FAE:
#   sudo hw-management-ssd-dump.py [--outdir DIR]
# Allowlist stays: this script rm -rf SSD_LOG_DIR and copies
# into DUMP_FOLDER as root. Python --no-tar: leave the work
# dir for the helper to copy as ssd-dump/. Then the helper
# removes /var/log/ssd-dump (standalone --no-tar keeps it).
# Do not copy /var/log/ssd-dump.tar.gz into DUMP_FOLDER.
# Best-effort: always exit 0 after a valid invoke so
# generate-dump still packs the rest of DUMP_FOLDER. A failed
# copy is written to stderr (ssd-dump-collect.log) as
# "SSD dump tool failed:" (Python defers succeeded for
# --quiet --no-tar until this helper copies). The work dir
# is kept.
# One SSD dump collection at a time, enforced by flock on
# /run/hw-management-ssd-dump.lock. Both because the work dir is
# a single fixed location that every collect removes, and
# because a vendor dump tool supports only one instance at a
# time. The lock covers the SSD dump only, so generate-dump
# always collects and packs everything else.
# The full system dump has priority over a standalone SSD dump,
# so a busy lock does not make this helper give up: it retries
# every 2 s up to the vendor budget read from the JSON. The
# standalone collector does the opposite and exits at once,
# which is what leaves this helper a turn to take.
# When the lock frees, the collection we waited for may already
# have produced a dump in the default location
# (/var/log/ssd-dump.tar.gz, or /var/log/ssd-dump with
# --no-tar). A finished one, status: ok, is reused instead of
# driving the SSD again, and is left where its owner put it.
# Anything else, including a failed leftover, is collected
# again. Only if the wait runs out does this helper report into
# DUMP_FOLDER/ssd-dump, leave $SSD_LOG_DIR untouched and exit 3
# — the only non-zero exit of a valid invoke, and generate-dump
# ignores it. Paths must be real, not symlinks.
#
# Usage:
#   hw-management-ssd-dump-collect.sh <DUMP_FOLDER> <SSD_LOG_DIR>
# Example:
#   hw-management-ssd-dump-collect.sh /tmp/hw-mgmt-dump \
#     /var/log/ssd-dump
#
# FAE / standalone nandlog (not this helper):
#   sudo hw-management-ssd-dump.py
# Full hw-mgmt dump:
#   sudo hw-management-generate-dump.sh

DUMP_FOLDER=$1
SSD_LOG_DIR=$2
SSD_TOOL_TIMEOUT=195
SSD_TOOL_KILL_AFTER=5
LOCK_FILE=/run/hw-management-ssd-dump.lock
# Same code as the collector: a busy lock is not a dump failure.
RC_LOCKED=3
# 195 = JSON vendor timeout (max 120) + status/copy.
# JSON timeout_sec is capped at 120 so this wrapper cannot
# kill a still-legal collect. Standalone --timeout may be
# higher (FAE); generate-dump always uses JSON only.
# 195+5=200, plus a lock wait of at most LOCK_WAIT_CAP, is why
# dump_cmd allows 330: 120+200 leaves ~10 s to copy or extract.
LOCK_POLL_SEC=2
# Upper bound on the wait whatever the JSON says, and the
# fallback when it cannot be read. Must stay in step with the
# collector's TIMEOUT_SEC_JSON_MAX and DEFAULT_CONFIG;
# tests/offline/test_hw_management_ssd_dump.py checks both.
# SSD_DUMP_CONFIG overrides the path for testing. It only feeds
# the wait budget, which is clamped below either way.
LOCK_WAIT_CAP=120
SSD_DUMP_CONFIG=${SSD_DUMP_CONFIG:-/usr/share/ssd-dump-tools/ssd-dump-config.json}
STATUS_NAME=ssd-dump-status.log

if [ -z "$DUMP_FOLDER" ] || [ -z "$SSD_LOG_DIR" ]; then
	echo "Usage: hw-management-ssd-dump-collect.sh <DUMP_FOLDER> <SSD_LOG_DIR>" >&2
	exit 1
fi

# Refuse unexpected paths. generate-dump always passes these
# two; the checks are for anyone else who runs this helper.
# Also refuse if an allowlisted path is a symlink (do not
# follow into another tree). DUMP_FOLDER must be a real
# directory owned by this uid (generate-dump mkdir is 0755).
# If a local user planted /tmp/hw-mgmt-dump, root recreates it
# so SSD collection cannot be blocked; never rm -rf a symlink.
DUMP_FOLDER=${DUMP_FOLDER%/}
SSD_LOG_DIR=${SSD_LOG_DIR%/}
case "$DUMP_FOLDER" in
	/tmp/hw-mgmt-dump) ;;
	*)
		echo "Invalid DUMP_FOLDER: $DUMP_FOLDER" >&2
		exit 1
		;;
esac
case "$SSD_LOG_DIR" in
	/var/log/ssd-dump) ;;
	*)
		echo "Invalid SSD_LOG_DIR: $SSD_LOG_DIR" >&2
		exit 1
		;;
esac

if [ -L "$SSD_LOG_DIR" ]; then
	echo "Invalid SSD_LOG_DIR symlink: $SSD_LOG_DIR" >&2
	exit 1
fi

# What a plain standalone run leaves instead of the work dir.
# Never copied into DUMP_FOLDER as an archive, only unpacked.
SSD_TARBALL="$SSD_LOG_DIR.tar.gz"

reset_dump_folder() {
	if [ -L "$DUMP_FOLDER" ]; then
		rm -f -- "$DUMP_FOLDER" || return 1
	elif [ -d "$DUMP_FOLDER" ]; then
		rm -rf -- "$DUMP_FOLDER" || return 1
	elif [ -e "$DUMP_FOLDER" ]; then
		rm -f -- "$DUMP_FOLDER" || return 1
	fi
	return 0
}

if [ -L "$DUMP_FOLDER" ] || [ -e "$DUMP_FOLDER" ]; then
	need_reset=0
	if [ -L "$DUMP_FOLDER" ]; then
		need_reset=1
	elif [ -d "$DUMP_FOLDER" ]; then
		if [ "$(stat -c '%u' "$DUMP_FOLDER" 2>/dev/null)" != "$(id -u)" ]; then
			need_reset=1
		fi
	else
		need_reset=1
	fi
	if [ "$need_reset" = "1" ]; then
		if [ "$(id -u)" != "0" ]; then
			echo "DUMP_FOLDER must be a real directory owned by uid $(id -u): $DUMP_FOLDER" >&2
			exit 1
		fi
		reset_dump_folder || {
			echo "Cannot reset DUMP_FOLDER: $DUMP_FOLDER" >&2
			exit 1
		}
	fi
fi
mkdir -p "$DUMP_FOLDER" || {
	echo "Cannot create DUMP_FOLDER: $DUMP_FOLDER" >&2
	exit 1
}
if [ ! -d "$DUMP_FOLDER" ] || [ -L "$DUMP_FOLDER" ]; then
	echo "Invalid DUMP_FOLDER type: $DUMP_FOLDER" >&2
	exit 1
fi
if [ "$(stat -c '%u' "$DUMP_FOLDER" 2>/dev/null)" != "$(id -u)" ]; then
	echo "DUMP_FOLDER must be owned by uid $(id -u): $DUMP_FOLDER" >&2
	exit 1
fi
chmod 0755 "$DUMP_FOLDER" || {
	echo "Cannot set DUMP_FOLDER permissions: $DUMP_FOLDER" >&2
	exit 1
}

write_status_warning() {
	mkdir -p "$SSD_LOG_DIR"
	echo "status: warning" > "$SSD_LOG_DIR/ssd-dump-status.log"
	echo "warning: $1" >> "$SSD_LOG_DIR/ssd-dump-status.log"
	echo "Status: error" >> "$SSD_LOG_DIR/ssd-dump-status.log"
	logger -t hw-management-ssd-dump -p user.warning "$1" 2>/dev/null || true
}

# Lock contention: $SSD_LOG_DIR belongs to the running
# collection, so report into DUMP_FOLDER without touching it.
write_dump_folder_warning() {
	rm -rf "$DUMP_FOLDER/ssd-dump"
	mkdir -p "$DUMP_FOLDER/ssd-dump" || return 1
	{
		echo "status: warning"
		echo "locked: yes"
		echo "warning: $1"
		echo "Status: error"
	} > "$DUMP_FOLDER/ssd-dump/ssd-dump-status.log"
	logger -t hw-management-ssd-dump -p user.warning "$1" 2>/dev/null || true
}

lock_holder() {
	_h=$(cat "$LOCK_FILE" 2>/dev/null)
	case "$_h" in
		"" | *[!0-9]*) echo "$LOCK_FILE" ;;
		*) echo "pid $_h" ;;
	esac
}

# Longest a collection we are waiting for may legitimately take,
# so the longest it is worth waiting. Largest timeout_sec in the
# JSON, since the model of the busy collection is not known
# here. Only an upper bound: the wait ends as soon as the lock
# frees. No python3, no config, junk in it, or a budget shorter
# than one poll falls back to the cap.
read_lock_wait_sec() {
	_w=""
	if command -v python3 >/dev/null 2>&1; then
		_w=$(python3 - "$SSD_DUMP_CONFIG" 2>/dev/null <<-'PY'
		import json, sys
		try:
		    cfg = json.load(open(sys.argv[1]))
		except Exception:
		    raise SystemExit(1)

		def sec(obj):
		    v = (obj or {}).get("timeout_sec")
		    return v if isinstance(v, int) and not isinstance(v, bool) else 0

		best = sec(cfg.get("defaults"))
		for vendor in (cfg.get("vendors") or {}).values():
		    for model in ((vendor or {}).get("models") or {}).values():
		        best = max(best, sec(model))
		print(best)
		PY
		)
	fi
	# 0 means no timeout_sec anywhere, so the budget is unknown
	# and the cap is the only safe guess. A real but tiny budget
	# is not unknown: honour it, rounded up to one poll, instead
	# of turning the shortest configured wait into the longest.
	case "$_w" in
		"" | *[!0-9]* | 0) _w=$LOCK_WAIT_CAP ;;
	esac
	[ "$_w" -lt "$LOCK_POLL_SEC" ] && _w=$LOCK_POLL_SEC
	[ "$_w" -gt "$LOCK_WAIT_CAP" ] && _w=$LOCK_WAIT_CAP
	echo "$_w"
}

# Retry rather than flock -w: the retry is also where the wait
# is reported, and -w is not on every flock. Sets lock_waited
# and lock_wait_elapsed for the caller.
acquire_lock() { # max seconds to wait
	lock_wait_elapsed=0
	lock_wait_started=$(date +%s 2>/dev/null)
	while :; do
		if /usr/bin/flock -n -x 9; then
			return 0
		fi
		[ "$lock_wait_elapsed" -ge "$1" ] && return 1
		if [ "$lock_waited" = "0" ]; then
			lock_waited=1
			_msg="waiting up to ${1}s for another SSD dump collection to finish ($(lock_holder))"
			echo "SSD dump tool waiting: $_msg" >&2
			logger -t hw-management-ssd-dump -p user.info "$_msg" \
				2>/dev/null || true
		fi
		sleep "$LOCK_POLL_SEC"
		lock_wait_elapsed=$((lock_wait_elapsed + LOCK_POLL_SEC))
	done
}

reuse_note() { # source
	_msg="reusing the SSD dump collected by the run we waited ${lock_wait_elapsed}s for: $1"
	echo "SSD dump tool reused: $_msg" >&2
	logger -t hw-management-ssd-dump -p user.info "$_msg" 2>/dev/null || true
}

# Only what the collection we waited for produced while we were
# waiting may be reused. The holder need not have written the
# default location at all: it may have been a --verify, or a
# collect with a custom --outdir, which removes its own tarball
# and leaves this one alone. Without the age check an
# ssd-dump.tar.gz from days ago would be packed into the system
# dump as the current SSD state.
# No usable timestamp on either side means the age cannot be
# established, so there is nothing to reuse: collect instead.
newer_than_wait() { # path
	_m=$(stat -c %Y "$1" 2>/dev/null)
	case "$_m" in
		"" | *[!0-9]*) return 1 ;;
	esac
	case "$lock_wait_started" in
		"" | *[!0-9]*) return 1 ;;
	esac
	[ "$_m" -ge "$lock_wait_started" ]
}

# The collection we waited for may have finished the job for us.
# Only a status: ok result counts; a failed leftover has to be
# collected again. Nothing is removed from the default location:
# the dump there belongs to whoever ran it.
reuse_existing_dump() {
	if [ -f "$SSD_TARBALL" ] && [ ! -L "$SSD_TARBALL" ] &&
		newer_than_wait "$SSD_TARBALL" &&
		tar -xzOf "$SSD_TARBALL" "ssd-dump/$STATUS_NAME" 2>/dev/null |
			grep -q '^status: ok$'; then
		rm -rf "$DUMP_FOLDER/ssd-dump"
		if tar -xzf "$SSD_TARBALL" -C "$DUMP_FOLDER" \
			"ssd-dump" 2>/dev/null &&
			[ -f "$DUMP_FOLDER/ssd-dump/$STATUS_NAME" ]; then
			reuse_note "$SSD_TARBALL"
			return 0
		fi
		rm -rf "$DUMP_FOLDER/ssd-dump"
	fi
	if [ -d "$SSD_LOG_DIR" ] && [ ! -L "$SSD_LOG_DIR" ] &&
		newer_than_wait "$SSD_LOG_DIR/$STATUS_NAME" &&
		grep -q '^status: ok$' "$SSD_LOG_DIR/$STATUS_NAME" 2>/dev/null; then
		rm -rf "$DUMP_FOLDER/ssd-dump"
		if cp -a "$SSD_LOG_DIR" "$DUMP_FOLDER/ssd-dump"; then
			reuse_note "$SSD_LOG_DIR"
			return 0
		fi
		rm -rf "$DUMP_FOLDER/ssd-dump"
	fi
	return 1
}

# Hold the lock across rm, collect and copy so that a parallel
# SSD dump cannot delete $SSD_LOG_DIR while we read it. python3
# takes the same lock, so tell it we already hold it. No flock
# or no writable lock file keeps the old best-effort flow. Probe
# in a subshell first: a failed redirection on exec or on a
# special built-in would terminate this shell.
lock_busy=0
lock_waited=0
lock_wait_elapsed=0
lock_wait_started=
if [ -x /usr/bin/flock ] && ( : >> "$LOCK_FILE" ) 2>/dev/null; then
	exec 9>> "$LOCK_FILE"
	if acquire_lock "$(read_lock_wait_sec)"; then
		HW_MGMT_SSD_DUMP_LOCK_HELD=1
		export HW_MGMT_SSD_DUMP_LOCK_HELD
		# Name this helper in the refusal a parallel caller
		# prints, as the collector does. Truncating through
		# another fd is safe: we hold the lock until exit.
		echo $$ > "$LOCK_FILE"
		trap ': > "$LOCK_FILE"' EXIT
	else
		lock_busy=1
	fi
fi

if [ "$lock_busy" = "1" ]; then
	msg="another SSD dump collection is still running after ${lock_wait_elapsed}s ($(lock_holder))"
	echo "SSD dump tool busy: $msg" >&2
	write_dump_folder_warning "$msg"
	exit "$RC_LOCKED"
fi

# Reuse only after a wait. Without one there was no competing
# collection, and whatever sits in the default location is
# somebody's older dump, not a result collected just now.
reused=0
if [ "$lock_waited" = "1" ] && reuse_existing_dump; then
	reused=1
fi

if [ "$reused" = "1" ]; then
	if grep -q '^status: ok$' \
		"$DUMP_FOLDER/ssd-dump/$STATUS_NAME" 2>/dev/null; then
		echo "SSD dump tool results: $DUMP_FOLDER/ssd-dump/" >&2
		echo "SSD dump tool succeeded" >&2
	fi
	exit 0
fi

rm -rf "$SSD_LOG_DIR"

if ! command -v python3 >/dev/null 2>&1; then
	write_status_warning "python3 not found on PATH"
elif [ -x "$(command -v hw-management-ssd-dump.py)" ]; then
	timeout --kill-after="$SSD_TOOL_KILL_AFTER" "$SSD_TOOL_TIMEOUT" \
		hw-management-ssd-dump.py --quiet --no-tar \
		--outdir "$SSD_LOG_DIR" || true
else
	write_status_warning "hw-management-ssd-dump.py not found on PATH"
fi

if [ -d "$SSD_LOG_DIR" ]; then
	st="$SSD_LOG_DIR/ssd-dump-status.log"
	if [ ! -f "$st" ]; then
		write_status_warning \
			"hw-management-ssd-dump.py terminated before status"
	fi
fi

if [ -d "$SSD_LOG_DIR" ]; then
	rm -rf "$DUMP_FOLDER/ssd-dump"
	if cp -a "$SSD_LOG_DIR" "$DUMP_FOLDER/ssd-dump"; then
		rm -rf "$SSD_LOG_DIR"
		if grep -q '^status: ok$' \
			"$DUMP_FOLDER/ssd-dump/ssd-dump-status.log" \
			2>/dev/null; then
			echo "SSD dump tool results: $DUMP_FOLDER/ssd-dump/" >&2
			echo "SSD dump tool succeeded" >&2
		fi
	else
		msg="failed to copy $SSD_LOG_DIR to $DUMP_FOLDER/ssd-dump"
		echo "$msg" >&2
		echo "SSD dump tool failed: $msg" >&2
		write_status_warning "$msg"
		rm -rf "$DUMP_FOLDER/ssd-dump"
		mkdir -p "$DUMP_FOLDER/ssd-dump"
		if [ -f "$SSD_LOG_DIR/ssd-dump-status.log" ]; then
			cp -a "$SSD_LOG_DIR/ssd-dump-status.log" \
				"$DUMP_FOLDER/ssd-dump/" 2>/dev/null || true
		fi
	fi
fi

exit 0
