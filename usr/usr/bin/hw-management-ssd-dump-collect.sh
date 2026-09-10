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
# copy is written to stderr (ssd-dump-collect.log) and the
# work dir is kept.
# One caller at a time (no lock). Paths must be real, not
# symlinks.
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
# 195 = JSON vendor timeout (max 120) + status/copy.
# JSON timeout_sec is capped at 120 so this wrapper cannot
# kill a still-legal collect. Standalone --timeout may be
# higher (FAE); generate-dump always uses JSON only.
# 195+5=200; dump_cmd 210 leaves ~10 s to copy leftover dir.

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
	else
		msg="failed to copy $SSD_LOG_DIR to $DUMP_FOLDER/ssd-dump"
		echo "$msg" >&2
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
