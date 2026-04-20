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
#    notice, this list, and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
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
# SUBSTITUTE GOODS OR SERVICES; LOSS OF DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
################################################################################
# BMC debug bundle (SONiC BMC): dmesg, /proc/interrupts, ifconfig (or ip),
# i2cdetect per non-mux bus, CPLD grid dump, systemctl for hw-management-bmc
# units, systemd-analyze (time, blame, critical-chain), and /var/run/hw-management
# tree + file contents (EEPROM via hexdump -C).
# Output: gzip-compressed tar (default /tmp/hw-mgmt-bmc-dump.tar.gz). Pattern
# aligned with usr/usr/bin/hw-management-generate-dump.sh (CPU).
#
# BusyBox: requires bash (see README). Uses POSIX/BusyBox-friendly utilities:
# tar|gzip pipeline (not GNU tar -I), find + ls -ld (not GNU find -ls),
# readlink fallback if -f unsupported. grep/awk/sort/cat/timeout/hexdump from
# BusyBox are OK when those applets are enabled.
################################################################################

# Best-effort canonical path (GNU readlink -f, BusyBox readlink, or realpath).
readlink_canonical()
{
	local p=$1
	local o
	if command -v realpath >/dev/null 2>&1; then
		o=$(realpath "$p" 2>/dev/null) && {
			printf '%s\n' "$o"
			return
		}
	fi
	o=$(readlink -f "$p" 2>/dev/null) && {
		printf '%s\n' "$o"
		return
	}
	readlink "$p" 2>/dev/null
}

export LOG_TAG="hw-management-bmc-generate-dump"
# shellcheck source=/dev/null
source /usr/bin/hw-management-bmc-helpers-common.sh

DUMP_FOLDER="/tmp/hw-mgmt-bmc-dump"
HW_MGMT="/var/run/hw-management"
OUTPUT_TAR="${1:-/tmp/hw-mgmt-bmc-dump.tar.gz}"
dump_process_pid=$$

help()
{
	cat <<EOF
Usage: hw-management-bmc-generate-dump.sh [output_tarball]

  Collects dmesg, /proc/interrupts, ifconfig (fallback: ip addr), i2cdetect -y
  for each bus from "i2cdetect -l | grep -v mux", CPLD dump (hw-management-bmc-cpld-dump),
  systemctl status/show for all hw-management-bmc* units, systemd-analyze time/blame
  (plus hw-management-bmc-only lines) and critical-chain for default.target/sysinit.target,
  and /var/run/hw-management tree + values (EEPROM paths: hexdump -C).

  Default output: /tmp/hw-mgmt-bmc-dump.tar.gz
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	help
	exit 0
fi

safe_unit_fname()
{
	echo "$1" | tr '/@:' '___'
}

safe_rel_fname()
{
	# /var/run/hw-management/foo/bar -> foo_bar
	local rel="${1#"${HW_MGMT}/"}"
	rel="${rel#/}"
	if [ -z "$rel" ]; then
		echo "root"
	else
		echo "$rel" | tr '/' '_'
	fi
}

is_eeprom_path()
{
	local f="$1" base
	base=$(basename "$f")
	# Symlinks under .../eeprom/ (eeprom_system, eeprom_bmc) or sysfs node named "eeprom"
	[[ "$f" == */eeprom/* ]] && return 0
	[[ "$f" == */eeprom ]] && return 0
	[[ "$base" == eeprom ]] && return 0
	[[ "$base" == eeprom_* ]] && return 0
	return 1
}

collect_hw_management_runtime()
{
	local out_root=$1
	local tree_dir values_dir

	tree_dir="${out_root}/tree"
	values_dir="${out_root}/values"
	mkdir -p "$tree_dir" "$values_dir"

	if [ ! -d "$HW_MGMT" ]; then
		log_message warning "Missing $HW_MGMT — skipping runtime tree"
		echo "Directory $HW_MGMT does not exist" >"${tree_dir}/missing.txt"
		return 0
	fi

	ls -Rla "$HW_MGMT" >"${tree_dir}/ls-Rla.txt" 2>&1
	find "$HW_MGMT" -xdev 2>/dev/null | LC_ALL=C sort >"${tree_dir}/find_paths_sorted.txt"
	# GNU find -ls is not in BusyBox; use ls -ld per path (bash process substitution).
	{
		while IFS= read -r -d '' p; do
			ls -ld "$p" 2>/dev/null || printf '%s\n' "$p"
		done < <(find "$HW_MGMT" -xdev -print0 2>/dev/null)
	} >"${tree_dir}/find_ls.txt" 2>&1

	local f rel outf
	while IFS= read -r -d '' f; do
		[ -e "$f" ] || continue
		[ -d "$f" ] && continue
		[ -p "$f" ] && continue
		[ -S "$f" ] && continue

		rel=$(safe_rel_fname "$f")
		outf="${values_dir}/${rel}.txt"

		{
			echo "=== path: $f ==="
			if [ -L "$f" ]; then
				echo "symlink: $(readlink "$f" 2>/dev/null)"
				readlink_canonical "$f" | sed 's/^/resolved: /'
			fi
			if [ ! -r "$f" ] && [ ! -L "$f" ]; then
				echo "(not readable)"
			elif is_eeprom_path "$f"; then
				timeout 60 hexdump -C "$f" 2>&1
			else
				timeout 20 cat "$f" 2>&1
			fi
		} >"$outf" || log_message warning "Failed to capture: $f"
	done < <(find "$HW_MGMT" -xdev \( -type f -o -type l \) ! -type s ! -type p -print0 2>/dev/null)
}

collect_systemctl_bmc()
{
	local d=$1
	local u uf units

	mkdir -p "$d"
	systemctl list-units 'hw-management-bmc*' --all --no-pager >"${d}/list-units.txt" 2>&1
	systemctl list-unit-files 'hw-management-bmc*' --no-pager >"${d}/list-unit-files.txt" 2>&1

	units=$(
		(
			systemctl list-unit-files --no-legend 2>/dev/null
			systemctl list-units --all --no-legend 2>/dev/null
		) | awk '$1 ~ /^hw-management-bmc/ {print $1}' | sort -u
	)

	for u in $units; do
		uf=$(safe_unit_fname "$u")
		systemctl status "$u" -l --no-pager >"${d}/${uf}.status.txt" 2>&1
		systemctl show "$u" --all >"${d}/${uf}.show.txt" 2>&1
	done
}

# systemd-analyze: boot/startup timing, per-unit blame (incl. oneshot duration), critical-chain.
collect_systemd_analyze()
{
	local d=$1
	mkdir -p "$d"
	if ! command -v systemd-analyze >/dev/null 2>&1; then
		log_message warning "systemd-analyze not found — skipping boot timing section"
		echo "systemd-analyze not in PATH" >"${d}/skipped.txt"
		return 0
	fi

	timeout 30 systemd-analyze time --no-pager >"${d}/time.txt" 2>&1 \
		|| log_message warning "systemd-analyze time failed or timed out"

	# Blame lists units sorted by startup time (oneshots included as wall-clock in chain).
	timeout 120 systemd-analyze blame --no-pager >"${d}/blame.txt" 2>&1 \
		|| log_message warning "systemd-analyze blame failed or timed out"

	if [ -f "${d}/blame.txt" ]; then
		grep 'hw-management-bmc' "${d}/blame.txt" >"${d}/blame_hw-management-bmc_only.txt" 2>/dev/null \
			|| echo "(no hw-management-bmc lines in blame output)" >"${d}/blame_hw-management-bmc_only.txt"
	fi

	timeout 90 systemd-analyze critical-chain default.target --no-pager >"${d}/critical-chain_default.target.txt" 2>&1 \
		|| log_message warning "systemd-analyze critical-chain default.target failed or timed out"
	timeout 90 systemd-analyze critical-chain sysinit.target --no-pager >"${d}/critical-chain_sysinit.target.txt" 2>&1 \
		|| log_message warning "systemd-analyze critical-chain sysinit.target failed or timed out"

	# Per-unit critical-chain for hw-management-bmc *.service (oneshot ordering); cap count/time so dumps stay bounded.
	local u uf units n max_cc
	n=0
	max_cc=16
	units=$(
		(
			systemctl list-unit-files --no-legend 2>/dev/null
			systemctl list-units --all --no-legend 2>/dev/null
		) | awk '$1 ~ /^hw-management-bmc/ && $1 ~ /\.service$/ {print $1}' | sort -u
	)
	mkdir -p "${d}/critical-chain_per_unit"
	for u in $units; do
		[ -n "$u" ] || continue
		n=$((n + 1))
		if [ "$n" -gt "$max_cc" ]; then
			printf 'Stopped after %s units (cap=%s); see full blame.txt for all startup times.\n' "$((n - 1))" "$max_cc" \
				>"${d}/critical-chain_per_unit/README_cap.txt"
			break
		fi
		uf=$(safe_unit_fname "$u")
		timeout 25 systemd-analyze critical-chain "$u" --no-pager >"${d}/critical-chain_per_unit/${uf}.txt" 2>&1 \
			|| log_message warning "systemd-analyze critical-chain $u failed or timed out"
	done
}

collect_cpld()
{
	local d=$1
	mkdir -p "$d"
	if [ ! -f /usr/bin/hw-management-bmc-cpld-dump.sh ]; then
		log_message warning "hw-management-bmc-cpld-dump.sh not installed — skipping CPLD"
		echo "hw-management-bmc-cpld-dump.sh not found" >"${d}/skipped.txt"
		return 0
	fi
	# shellcheck source=/dev/null
	if ! source /usr/bin/hw-management-bmc-cpld-dump.sh; then
		log_message warning "Could not source hw-management-bmc-cpld-dump.sh"
		echo "source failed" >"${d}/skipped.txt"
		return 0
	fi
	if ! declare -F take_cpld_dump >/dev/null 2>&1; then
		log_message warning "take_cpld_dump missing after source"
		return 0
	fi
	take_cpld_dump "$d" || log_message warning "take_cpld_dump returned non-zero"
}

collect_proc_interrupts()
{
	local d=$1
	mkdir -p "$d"
	if [ -r /proc/interrupts ]; then
		cat /proc/interrupts >"${d}/interrupts.txt" 2>&1
	else
		echo "/proc/interrupts not readable" >"${d}/interrupts.txt"
	fi
}

collect_network_ifconfig()
{
	local d=$1
	mkdir -p "$d"
	if command -v ifconfig >/dev/null 2>&1; then
		timeout 20 ifconfig -a >"${d}/ifconfig.txt" 2>&1 || log_message warning "ifconfig failed or timed out"
	else
		{
			echo "ifconfig not in PATH; fallback: ip addr show"
			timeout 20 ip addr show 2>&1
		} >"${d}/ifconfig.txt"
	fi
}

# i2cdetect -y for each adapter not matching mux (see i2cdetect -l | grep -v mux).
collect_i2c_non_mux()
{
	local d=$1
	local buses b

	mkdir -p "$d"

	if ! command -v i2cdetect >/dev/null 2>&1; then
		log_message warning "i2cdetect not installed — skipping I2C scan"
		echo "i2cdetect not found" >"${d}/skipped.txt"
		return 0
	fi

	i2cdetect -l >"${d}/i2cdetect-l.txt" 2>&1
	i2cdetect -l 2>/dev/null | grep -v mux >"${d}/i2cdetect-l_grep-v-mux.txt" 2>&1

	buses=$(i2cdetect -l 2>/dev/null | grep -v mux | awk '/^i2c-[0-9]+/ { split($1, a, "-"); print a[2] }' | sort -nu)
	if [ -z "$buses" ]; then
		echo "No i2c-N adapters matched (or only mux adapters)" >"${d}/i2cdetect-y_note.txt"
	fi

	for b in $buses; do
		timeout 60 i2cdetect -y "$b" >"${d}/i2cdetect-y_${b}.txt" 2>&1 || log_message warning "i2cdetect -y $b failed or timed out"
	done
}

# --- main ---
rm -rf "$DUMP_FOLDER"
mkdir -p "$DUMP_FOLDER"

uname -a >"${DUMP_FOLDER}/uname.txt" 2>&1
[ -f /etc/os-release ] && cat /etc/os-release >>"${DUMP_FOLDER}/uname.txt" 2>&1

timeout 20 dmesg >"${DUMP_FOLDER}/dmesg.txt" 2>&1 || log_message warning "dmesg failed or timed out"

collect_proc_interrupts "${DUMP_FOLDER}/proc"
collect_network_ifconfig "${DUMP_FOLDER}/network"
collect_i2c_non_mux "${DUMP_FOLDER}/i2c"

collect_systemctl_bmc "${DUMP_FOLDER}/systemctl"
collect_systemd_analyze "${DUMP_FOLDER}/systemd-analyze"
collect_cpld "${DUMP_FOLDER}/cpld"
collect_hw_management_runtime "${DUMP_FOLDER}/var_run_hw-management"

pkill -P "$dump_process_pid" 2>/dev/null || true

# BusyBox tar has no GNU -I/--use-compress-program; pipe to gzip (BusyBox or GNU).
if ! command -v gzip >/dev/null 2>&1; then
	log_message err "gzip not found — cannot create $OUTPUT_TAR"
	rm -rf "$DUMP_FOLDER"
	exit 1
fi
set -o pipefail 2>/dev/null || true
if ! tar cf - -C "$DUMP_FOLDER" . | gzip -9 >"$OUTPUT_TAR"; then
	log_message err "Failed to create archive $OUTPUT_TAR"
	rm -rf "$DUMP_FOLDER"
	exit 1
fi
set +o pipefail 2>/dev/null || true

rm -rf "$DUMP_FOLDER"
log_message info "BMC dump created: $OUTPUT_TAR"
exit 0
