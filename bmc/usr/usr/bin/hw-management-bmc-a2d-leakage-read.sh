#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# A2D leakage channel reader. For every detector the config script laid out under
# /var/run/hw-management/leakage/<i>/<ch>/, publishes value = input * scale, where
# input is the kernel IIO reading and scale comes from the JSON "Scale" field.

LEAKAGE_BASE="/var/run/hw-management/leakage"
LOG_TAG="a2d_read"

# shellcheck source=/dev/null
source /usr/bin/hw-management-bmc-helpers-common.sh

log_message()
{
	logger -t "$LOG_TAG" -p "daemon.$1" "$2"
	echo "[$1] $2"
}

# Publish volts = input * scale for one channel dir. scale is taken from the
# config-written scale file (JSON "Scale"), never hardcoded.
read_channel()
{
	local ch="$1" scale raw v
	[ -r "$ch/input" ] && [ -r "$ch/scale" ] || return 1
	scale=$(tr -d ' \t\r\n' <"$ch/scale")
	IFS= read -r raw <"$ch/input" 2>/dev/null
	raw=$(printf '%s' "$raw" | tr -d ' \t\r\n')
	# raw must be a plain signed integer; reject junk (e.g. --1, 1e-3) before bc.
	case "$raw" in ''|-|*[!0-9-]*|?*-*) return 1 ;; esac
	[ -n "$scale" ] || return 1
	v=$(echo "scale=10; $raw * $scale" | hw_mgmt_bc)
	[ -n "$v" ] || return 1
	case "$v" in .*) v="0$v" ;; esac
	printf '%s\n' "$v" >"$ch/value"
}

# Read every channel of one detector dir (leakage/<i>/).
process_device()
{
	local dir="$1" type ch n read=0 skip=0
	type=$(cat "$dir/device_type" 2>/dev/null)
	log_message info "Processing ${type:-?} at $dir"
	for ch in "$dir"/[0-9]*; do
		[ -d "$ch" ] || continue
		n=$(basename "$ch")
		if read_channel "$ch"; then
			log_message info "Channel $n: $(cat "$ch/value") V"
			read=$((read + 1))
		else
			log_message warning "Channel $n: read failed"
			skip=$((skip + 1))
		fi
	done
	log_message info "${type:-?} read complete: $read read, $skip skipped"
	[ "$read" -gt 0 ]
}

main()
{
	log_message info "A2D Leakage Channel Reader"
	hw_mgmt_bc_available || { log_message err "bc not available"; exit 1; }
	[ -d "$LEAKAGE_BASE" ] || { log_message err "No $LEAKAGE_BASE"; exit 1; }

	local dir done=0 fail=0
	for dir in "$LEAKAGE_BASE"/[0-9]*; do
		[ -d "$dir" ] && [ -f "$dir/device_type" ] || continue
		if process_device "$dir"; then done=$((done + 1)); else fail=$((fail + 1)); fi
	done

	log_message info "Scan complete: $done processed, $fail failed"
}

main "$@"
