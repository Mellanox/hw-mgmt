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
# BMC debug bundle (SONiC BMC): dmesg, journalctl -b0, /proc/interrupts,
# ifconfig (or ip), i2cdetect per non-mux bus, CPLD grid dump, systemctl for
# hw-management-bmc units, systemd-analyze (time, blame, critical-chain), and
# /var/run/hw-management tree + file contents (EEPROM via hexdump -C).
# Output: gzip-compressed tar (default /tmp/hw-mgmt-bmc-dump.tar.gz). Pattern
# aligned with usr/usr/bin/hw-management-generate-dump.sh (CPU).
#
# BusyBox: requires bash (see README). Uses POSIX/BusyBox-friendly utilities:
# tar|gzip pipeline (not GNU tar -I), find + ls -ld (not GNU find -ls),
# readlink fallback if -f unsupported. grep/awk/sort/cat/timeout/hexdump from
# BusyBox are OK when those applets are enabled.
#
# Reset cause: collect_hw_management_runtime() writes hw-management-bmc-show-reset-cause.sh
# (all sections) to ${HW_MGMT}/bmc/show-reset-cause first; that file is then archived with
# the rest of /var/run/hw-management (tree + values).
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
OUTPUT_TAR="/tmp/hw-mgmt-bmc-dump.tar.gz"
VERBOSE=0
dump_process_pid=$$

help()
{
	cat <<EOF
Usage: hw-management-bmc-generate-dump.sh [-v|--verbose] [output_tarball]

  Collects dmesg, journalctl -b0 (gzip'd on the fly), /proc/interrupts,
  ifconfig (fallback: ip addr), i2cdetect -y for each bus from
  "i2cdetect -l | grep -v mux", CPLD dump (hw-management-bmc-cpld-dump),
  systemctl status/show for all hw-management-bmc* units, and
  /var/run/hw-management tree + values (EEPROM paths: hexdump -C).
  Before archiving, hw-management-bmc-show-reset-cause.sh output is written to
  /var/run/hw-management/bmc/show-reset-cause so it is included with the
  runtime snapshot.

  -v, --verbose   Also collect systemd-analyze (time, blame, critical-chain);
                  slow (~1 min).

  Default output: /tmp/hw-mgmt-bmc-dump.tar.gz
EOF
}

parse_args()
{
	while [ $# -gt 0 ]; do
		case "$1" in
		-h | --help)
			help
			exit 0
			;;
		-v | --verbose)
			VERBOSE=1
			;;
		-*)
			log_message err "Unknown option: $1"
			help
			exit 1
			;;
		*)
			OUTPUT_TAR="$1"
			;;
		esac
		shift
	done
}

parse_args "$@"

# Default worker count for parallel sections (hw-mgmt values, systemd-analyze per-unit).
if [ -z "${MAX_PARALLEL:-}" ]; then
	_cpus=$(nproc 2>/dev/null) || _cpus=4
	MAX_PARALLEL=$((_cpus + 1))
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
	local tree_dir values_dir show

	tree_dir="${out_root}/tree"
	values_dir="${out_root}/values"
	mkdir -p "$tree_dir" "$values_dir"

	if [ -d "$HW_MGMT" ]; then
		mkdir -p "${HW_MGMT}/bmc"
		show="/usr/bin/hw-management-bmc-show-reset-cause.sh"
		if [ -x "$show" ]; then
			"$show" >"${HW_MGMT}/bmc/show-reset-cause" 2>&1 \
				|| log_message warning "hw-management-bmc-show-reset-cause.sh returned non-zero"
		else
			log_message warning "hw-management-bmc-show-reset-cause.sh not installed — stub ${HW_MGMT}/bmc/show-reset-cause"
			echo "hw-management-bmc-show-reset-cause.sh not found or not executable" >"${HW_MGMT}/bmc/show-reset-cause"
		fi
	fi

	if [ ! -d "$HW_MGMT" ]; then
		log_message warning "Missing $HW_MGMT — skipping runtime tree"
		echo "Directory $HW_MGMT does not exist" >"${tree_dir}/missing.txt"
		return 0
	fi

	ls -Rla "$HW_MGMT" >"${tree_dir}/ls-Rla.txt" 2>&1

	# Single-pass find: walk $HW_MGMT once, save NUL-separated paths, then reuse
	# the listing for sorted paths, ls -ld per path, and the value-capture loop.
	local paths_nul="${tree_dir}/.paths.nul"
	find "$HW_MGMT" -xdev -print0 2>/dev/null >"$paths_nul"

	tr '\0' '\n' <"$paths_nul" | LC_ALL=C sort >"${tree_dir}/find_paths_sorted.txt"

	# GNU find -ls is not in BusyBox; iterate the same listing with ls -ld per path.
	{
		while IFS= read -r -d '' p; do
			ls -ld "$p" 2>/dev/null || printf '%s\n' "$p"
		done <"$paths_nul"
	} >"${tree_dir}/find_ls.txt" 2>&1

	local -a all_paths=()
	local f
	while IFS= read -r -d '' f; do
		all_paths+=("$f")
	done <"$paths_nul"
	rm -f "$paths_nul"

	local total="${#all_paths[@]}"
	local workers="${HW_MGMT_BMC_DUMP_WORKERS:-${HW_MGMT_CAPTURE_PARALLEL_MAX:-$MAX_PARALLEL}}"
	[ "$workers" -lt 1 ] && workers=1
	if [ "$total" -gt 0 ] && [ "$workers" -gt "$total" ]; then
		workers="$total"
	fi

	_hwm_value_worker() {
		local stride=$1 offset=$2
		local j f rel outf
		for ((j = offset; j < total; j += stride)); do
			f="${all_paths[$j]}"
			[ -e "$f" ] || [ -L "$f" ] || continue
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
				# -r follows symlinks: write-only targets get a one-line marker
				# instead of a failed cat and a syslog warning per file.
				if [ ! -r "$f" ]; then
					echo "(not readable / write-only)"
				elif is_eeprom_path "$f"; then
					timeout 60 hexdump -C "$f" 2>&1 || echo "(hexdump returned non-zero)"
				else
					timeout 20 cat "$f" 2>&1 || echo "(cat returned non-zero; likely write-only or EIO)"
				fi
			} >"$outf"
		done
	}

	if [ "$total" -gt 0 ]; then
		local i
		for ((i = 0; i < workers; i++)); do
			_hwm_value_worker "$workers" "$i" &
		done
		wait
	fi
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

# Run one systemd-analyze subcommand in background (separate outfile per caller).
run_systemd_analyze_cmd_bg()
{
	local timeout_sec=$1
	local outfile=$2
	local label
	shift 2

	label=$(basename "$outfile" .txt)

	(
		local t0=$SECONDS rc elapsed

		log_message info "systemd-analyze ${label}: start"
		if timeout "$timeout_sec" systemd-analyze "$@" --no-pager >"$outfile" 2>&1; then
			rc=0
		else
			rc=$?
			log_message warning "systemd-analyze $* failed or timed out"
		fi
		elapsed=$((SECONDS - t0))
		if [ "$rc" -eq 0 ]; then
			log_message info "systemd-analyze ${label}: end (${elapsed}s)"
		else
			log_message warning "systemd-analyze ${label}: end (${elapsed}s, exit=${rc})"
		fi
		exit "$rc"
	) &
}

# systemd-analyze: boot/startup timing, per-unit blame (incl. oneshot duration), critical-chain.
# Independent subcommands run in parallel; per-unit critical-chain uses a concurrency cap.
collect_systemd_analyze()
{
	local d=$1
	local u uf units n max_cc max_parallel pid
	local -a pids

	mkdir -p "$d"
	if ! command -v systemd-analyze >/dev/null 2>&1; then
		log_message warning "systemd-analyze not found — skipping boot timing section"
		echo "systemd-analyze not in PATH" >"${d}/skipped.txt"
		return 0
	fi

	max_cc=16
	max_parallel="${SYSTEMD_ANALYZE_PARALLEL_MAX:-$MAX_PARALLEL}"

	run_systemd_analyze_cmd_bg 30 "${d}/time.txt" time
	# Blame lists units sorted by startup time (oneshots included as wall-clock in chain).
	run_systemd_analyze_cmd_bg 120 "${d}/blame.txt" blame
	run_systemd_analyze_cmd_bg 90 "${d}/critical-chain_default.target.txt" critical-chain default.target
	run_systemd_analyze_cmd_bg 90 "${d}/critical-chain_sysinit.target.txt" critical-chain sysinit.target
	wait

	if [ -f "${d}/blame.txt" ]; then
		grep 'hw-management-bmc' "${d}/blame.txt" >"${d}/blame_hw-management-bmc_only.txt" 2>/dev/null \
			|| echo "(no hw-management-bmc lines in blame output)" >"${d}/blame_hw-management-bmc_only.txt"
	fi

	# Per-unit critical-chain for hw-management-bmc *.service (oneshot ordering); cap count/time so dumps stay bounded.
	units=$(
		(
			systemctl list-unit-files --no-legend 2>/dev/null
			systemctl list-units --all --no-legend 2>/dev/null
		) | awk '$1 ~ /^hw-management-bmc/ && $1 ~ /\.service$/ {print $1}' | sort -u
	)
	mkdir -p "${d}/critical-chain_per_unit"
	pids=()
	n=0
	for u in $units; do
		[ -n "$u" ] || continue
		n=$((n + 1))
		if [ "$n" -gt "$max_cc" ]; then
			printf 'Stopped after %s units (cap=%s); see full blame.txt for all startup times.\n' "$((n - 1))" "$max_cc" \
				>"${d}/critical-chain_per_unit/README_cap.txt"
			break
		fi
		uf=$(safe_unit_fname "$u")
		run_systemd_analyze_cmd_bg 25 "${d}/critical-chain_per_unit/${uf}.txt" critical-chain "$u"
		pids+=($!)
		if [ "${#pids[@]}" -ge "$max_parallel" ]; then
			pid=${pids[0]}
			pids=("${pids[@]:1}")
			wait "$pid" 2>/dev/null || true
		fi
	done
	for pid in "${pids[@]}"; do
		wait "$pid" 2>/dev/null || true
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

collect_journalctl_boot()
{
	local d=$1
	mkdir -p "$d"
	if ! command -v journalctl >/dev/null 2>&1; then
		log_message warning "journalctl not found — skipping boot journal"
		echo "journalctl not found" >"${d}/skipped.txt"
		return 0
	fi
	if ! command -v gzip >/dev/null 2>&1; then
		log_message warning "gzip not found — skipping boot journal"
		echo "gzip not found" >"${d}/skipped.txt"
		return 0
	fi
	# Stream through gzip so a long-lived / verbose boot cannot exhaust /tmp
	# (often a small tmpfs) while still keeping the full current-boot journal.
	# stderr is merged into the stream so failures land in the .gz too.
	if ! (
		set -o pipefail 2>/dev/null || true
		timeout 60 journalctl -b0 --no-pager 2>&1 | gzip -5 >"${d}/journalctl-b0.txt.gz"
	); then
		log_message warning "journalctl -b0 | gzip failed or timed out"
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

# Run a collector in a background subshell; log start/end and wall time (journal + stderr).
run_collect_bg()
{
	local name=$1
	shift

	(
		local t0=$SECONDS rc elapsed

		log_message info "collect ${name}: start"
		"$@"
		rc=$?
		elapsed=$((SECONDS - t0))
		if [ "$rc" -eq 0 ]; then
			log_message info "collect ${name}: end (${elapsed}s)"
		else
			log_message warning "collect ${name}: end (${elapsed}s, exit=${rc})"
		fi
		exit "$rc"
	) &
}

# --- main ---
rm -rf "$DUMP_FOLDER"
mkdir -p "$DUMP_FOLDER"

uname -a >"${DUMP_FOLDER}/uname.txt" 2>&1
[ -f /etc/os-release ] && cat /etc/os-release >>"${DUMP_FOLDER}/uname.txt" 2>&1

timeout 20 dmesg >"${DUMP_FOLDER}/dmesg.txt" 2>&1 || log_message warning "dmesg failed or timed out"

run_collect_bg journalctl_boot collect_journalctl_boot "${DUMP_FOLDER}/journal"
run_collect_bg proc_interrupts collect_proc_interrupts "${DUMP_FOLDER}/proc"
run_collect_bg network_ifconfig collect_network_ifconfig "${DUMP_FOLDER}/network"
run_collect_bg i2c_non_mux collect_i2c_non_mux "${DUMP_FOLDER}/i2c"
run_collect_bg systemctl_bmc collect_systemctl_bmc "${DUMP_FOLDER}/systemctl"
if [ "$VERBOSE" -eq 1 ]; then
	run_collect_bg systemd_analyze collect_systemd_analyze "${DUMP_FOLDER}/systemd-analyze"
else
	mkdir -p "${DUMP_FOLDER}/systemd-analyze"
	echo "systemd-analyze collection skipped (use -v or --verbose)" \
		>"${DUMP_FOLDER}/systemd-analyze/skipped.txt"
	log_message info "systemd-analyze skipped (not verbose mode)"
fi
run_collect_bg cpld collect_cpld "${DUMP_FOLDER}/cpld"
run_collect_bg hw_management_runtime collect_hw_management_runtime "${DUMP_FOLDER}/var_run_hw-management"

wait

pkill -P "$dump_process_pid" 2>/dev/null || true

# BusyBox tar has no GNU -I/--use-compress-program; pipe to gzip (BusyBox or GNU).
if ! command -v gzip >/dev/null 2>&1; then
	log_message err "gzip not found — cannot create $OUTPUT_TAR"
	rm -rf "$DUMP_FOLDER"
	exit 1
fi
archive_t0=$SECONDS
log_message info "archive: start"
set -o pipefail 2>/dev/null || true
if ! tar cf - -C "$DUMP_FOLDER" . | gzip -9 >"$OUTPUT_TAR"; then
	log_message err "Failed to create archive $OUTPUT_TAR"
	rm -rf "$DUMP_FOLDER"
	exit 1
fi
set +o pipefail 2>/dev/null || true
log_message info "archive: end ($((SECONDS - archive_t0))s)"

rm -rf "$DUMP_FOLDER"
log_message info "BMC dump created: $OUTPUT_TAR"
exit 0
