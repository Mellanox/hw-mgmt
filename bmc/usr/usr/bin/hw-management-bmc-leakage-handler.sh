#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause
#
# HID-agnostic: how many A2Ds and channels exist is determined by a2d/leakage config
# (directories under /var/run/hw-management/leakage/), not by this script.
# Args: $1 = A2D / leak-detector index (matches /var/run/hw-management/leakage/<i>/)
#       $2 = monotonic timestamp in milliseconds (caller-provided, e.g. from event time)

set -euo pipefail

A2D_INDEX="${1:-}"
TS_MS="${2:-}"

if [[ -z "$A2D_INDEX" || -z "$TS_MS" ]]; then
	echo "Usage: $0 <a2d_index> <timestamp_ms>" >&2
	exit 1
fi

BASE="/var/run/hw-management/leakage/${A2D_INDEX}"

if [[ ! -d "$BASE" ]]; then
	exit 0
fi

# 12-bit aligned ADC code from raw sysfs reading (12-bit mask)
align12()
{
	awk -v s="$1" 'BEGIN {
		if (s == "" || s !~ /^-?[0-9]+$/) { print ""; exit 0 }
		v = int(s)
		r = v % 4096
		if (r < 0) { r += 4096 }
		print r
	}'
}

process_channel()
{
	local ch_dir="$1"
	local input_path sample min_v max_v aligned cmp_s raw_sample scale_f

	input_path="$ch_dir/input"
	if [[ -L "$input_path" ]] || [[ -f "$input_path" ]]; then
		IFS= read -r sample <"$input_path" 2>/dev/null || sample=""
		sample="${sample//$'\r'/}"
		sample="${sample// /}"
	else
		return 0
	fi
	[[ -z "$sample" ]] && return 0

	min_v=""
	max_v=""
	[[ -f "$ch_dir/min" ]] && min_v=$(tr -d ' \t\r\n' <"$ch_dir/min")
	[[ -f "$ch_dir/max" ]] && max_v=$(tr -d ' \t\r\n' <"$ch_dir/max")
	[[ -z "$min_v" || -z "$max_v" ]] && return 0

	raw_sample="$sample"
	cmp_s="$sample"
	scale_f=""
	[[ -f "$ch_dir/scale" ]] && scale_f=$(tr -d ' \t\r\n' <"$ch_dir/scale")
	if [[ -n "$scale_f" ]]; then
		cmp_s=$(awk -v s="$sample" -v sc="$scale_f" 'BEGIN {
			if (s == "" || s !~ /^-?[0-9]+$/) { print ""; exit }
			printf "%.12g\n", (s + 0) * (sc + 0)
		}')
		[[ -z "$cmp_s" ]] && return 0
	fi

	# Out of band: sample < min OR sample > max (cmp_s matches min/max units)
	if awk -v s="$cmp_s" -v mn="$min_v" -v mx="$max_v" 'BEGIN {
		exit !((s + 0) < (mn + 0) || (s + 0) > (mx + 0))
	}'; then
		:
	else
		return 0
	fi

	aligned=$(align12 "$raw_sample")
	[[ -z "$aligned" ]] && return 0

	echo "$aligned" >"$ch_dir/last_sample"
	echo "$TS_MS" >"$ch_dir/last_event"
}

shopt -s nullglob
for ch_dir in "$BASE"/*; do
	[[ -d "$ch_dir" ]] || continue
	case "$(basename "$ch_dir")" in
	*[!0-9]*) continue ;;
	esac
	process_channel "$ch_dir"
done

exit 0
