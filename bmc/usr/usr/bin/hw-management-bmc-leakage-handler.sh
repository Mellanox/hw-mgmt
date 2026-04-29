#!/bin/bash

# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
################################################################################
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# HID-agnostic: how many A2Ds and channels exist is determined by a2d/leakage config
# (directories under /var/run/hw-management/leakage/), not by this script.
# Args: $1 = A2D / leak-detector index (matches /var/run/hw-management/leakage/<i>/)
#       $2 = monotonic timestamp in milliseconds (caller-provided, e.g. from event time)
################################################################################

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
