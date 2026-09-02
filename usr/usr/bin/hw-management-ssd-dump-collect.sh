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

# Called from hw-management-generate-dump.sh via dump_cmd.
# Recreate $SSD_LOG_DIR, run hw-management-ssd-dump.py. Python packs
# $SSD_TAR only on status ok. Else this helper packs leftover dir.
# Copy into DUMP_FOLDER. Best-effort: always exit 0 after a valid invoke.
#
# Usage:
#   hw-management-ssd-dump-collect.sh <DUMP_FOLDER> <SSD_LOG_DIR> <SSD_TAR>
# Example:
#   hw-management-ssd-dump-collect.sh /tmp/hw-mgmt-dump \
#     /var/log/ssd-dump /var/log/ssd-dump.tar.gz
#
# FAE / standalone nandlog (not this helper):
#   sudo hw-management-ssd-dump.py
# Full hw-mgmt dump:
#   sudo hw-management-generate-dump.sh

DUMP_FOLDER=$1
SSD_LOG_DIR=$2
SSD_TAR=$3
SSD_TOOL_TIMEOUT=180
SSD_TOOL_KILL_AFTER=10

if [ -z "$DUMP_FOLDER" ] || [ -z "$SSD_LOG_DIR" ] || [ -z "$SSD_TAR" ]; then
	echo "Usage: hw-management-ssd-dump-collect.sh <DUMP_FOLDER> <SSD_LOG_DIR> <SSD_TAR>" >&2
	exit 1
fi

# Refuse rm -rf / rm -f on unexpected paths (generate-dump always
# passes these three). Also refuse if an allowlisted path is a
# symlink (do not follow into another tree). DUMP_FOLDER must be a
# real directory owned by this uid, mode 0700 (chmod after mkdir).
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
case "$SSD_TAR" in
	/var/log/ssd-dump.tar.gz) ;;
	*)
		echo "Invalid SSD_TAR: $SSD_TAR" >&2
		exit 1
		;;
esac

if [ -L "$DUMP_FOLDER" ]; then
	echo "Invalid DUMP_FOLDER symlink: $DUMP_FOLDER" >&2
	exit 1
fi
if [ -L "$SSD_LOG_DIR" ]; then
	echo "Invalid SSD_LOG_DIR symlink: $SSD_LOG_DIR" >&2
	exit 1
fi
if [ -L "$SSD_TAR" ]; then
	echo "Invalid SSD_TAR symlink: $SSD_TAR" >&2
	exit 1
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
chmod 700 "$DUMP_FOLDER" || {
	echo "Cannot chmod DUMP_FOLDER: $DUMP_FOLDER" >&2
	exit 1
}
if [ "$(stat -c '%a' "$DUMP_FOLDER" 2>/dev/null)" != "700" ]; then
	echo "DUMP_FOLDER must have mode 0700: $DUMP_FOLDER" >&2
	exit 1
fi

# Same lock file as hw-management-ssd-dump.py. Non-blocking: do not
# stall generate-dump if FAE already holds it. Python skips flock
# when HW_MGMT_SSD_DUMP_LOCKED=1 (parent+child deadlock).
if command -v flock >/dev/null 2>&1; then
	SSD_DUMP_LOCK=/run/hw-management-ssd-dump.lock
	if ! touch "$SSD_DUMP_LOCK" 2>/dev/null; then
		SSD_DUMP_LOCK=/var/lock/hw-management-ssd-dump.lock
		touch "$SSD_DUMP_LOCK" 2>/dev/null || true
	fi
	if exec 9>>"$SSD_DUMP_LOCK"; then
		if ! flock -n 9; then
			echo "status: warning" > "$DUMP_FOLDER/ssd-dump-status.log"
			echo "warning: another ssd-dump is running" >> \
				"$DUMP_FOLDER/ssd-dump-status.log"
			logger -t hw-management-ssd-dump -p user.warning \
				"another ssd-dump is running" 2>/dev/null || true
			exit 0
		fi
		export HW_MGMT_SSD_DUMP_LOCKED=1
	fi
fi

write_status_warning() {
	mkdir -p "$SSD_LOG_DIR"
	echo "status: warning" > "$SSD_LOG_DIR/ssd-dump-status.log"
	echo "warning: $1" >> "$SSD_LOG_DIR/ssd-dump-status.log"
	logger -t hw-management-ssd-dump -p user.warning "$1" 2>/dev/null || true
}

rm -f "$SSD_TAR"
rm -rf "$SSD_LOG_DIR"

if ! command -v python3 >/dev/null 2>&1; then
	write_status_warning "python3 not found on PATH"
elif [ -x "$(command -v hw-management-ssd-dump.py)" ]; then
	timeout --kill-after="$SSD_TOOL_KILL_AFTER" "$SSD_TOOL_TIMEOUT" \
		hw-management-ssd-dump.py --quiet \
		--outdir "$SSD_LOG_DIR" || true
else
	write_status_warning "hw-management-ssd-dump.py not found on PATH"
fi

if [ ! -f "$SSD_TAR" ]; then
	mkdir -p "$SSD_LOG_DIR"
	if [ ! -f "$SSD_LOG_DIR/ssd-dump-status.log" ]; then
		write_status_warning \
			"hw-management-ssd-dump.py terminated before packing"
	fi
	if tar -czf "$SSD_TAR" -C "$(dirname "$SSD_LOG_DIR")" \
		"$(basename "$SSD_LOG_DIR")" 2>/dev/null; then
		rm -rf "$SSD_LOG_DIR"
	fi
fi

if [ -f "$SSD_TAR" ]; then
	cp -a "$SSD_TAR" "$DUMP_FOLDER/" 2>/dev/null || true
fi
if [ -d "$SSD_LOG_DIR" ]; then
	rm -rf "$DUMP_FOLDER/ssd-dump"
	cp -a "$SSD_LOG_DIR" "$DUMP_FOLDER/ssd-dump" 2>/dev/null || true
fi

exit 0
