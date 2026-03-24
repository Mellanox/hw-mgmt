#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Validate /var/run/hw-management/{config,leakage,system,eeprom,thermal} against
# expected thresholds and packaged reference configs (HI189 or override paths).
#
# - system / thermal / eeprom: entry count uses the same rule as
#   hw-management-bmc-boot-complete.sh (ls -A | wc -l) and compares to
#   SYSFS_*_COUNTER in hw-management-bmc-boot-complete.conf (>=).
# - config: expects exactly four entries: bom, cpu_type, hid, pn.
# - leakage: expected detector count = length of top-level JSON array in
#   hw-management-bmc-a2d-leakage-config.json; actual = numeric subdirs under
#   leakage/ (1, 2, …). Optionally prints total regular file count for info.
#
# Environment (optional):
#   HW_MGMT_ROOT=/var/run/hw-management
#   BOOT_COMPLETE_CONF=/etc/hw-management-bmc-boot-complete.conf
#   LEAKAGE_JSON=/etc/hw-management-bmc-a2d-leakage-config.json
#   REPO_HI189=…/bmc/usr/etc/HI189  — if /etc paths missing, fall back for CI.
#
# Exit: 0 if all checks pass; 1 otherwise.

set -u
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_BMC_DEFAULT=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_HI189="${REPO_HI189:-$REPO_BMC_DEFAULT/usr/etc/HI189}"

HW_MGMT_ROOT="${HW_MGMT_ROOT:-/var/run/hw-management}"
CONFIG_DIR="$HW_MGMT_ROOT/config"
LEAKAGE_ROOT="$HW_MGMT_ROOT/leakage"
SYSTEM_DIR="$HW_MGMT_ROOT/system"
EEPROM_DIR="$HW_MGMT_ROOT/eeprom"
THERMAL_DIR="$HW_MGMT_ROOT/thermal"

BOOT_COMPLETE_CONF="${BOOT_COMPLETE_CONF:-/etc/hw-management-bmc-boot-complete.conf}"
LEAKAGE_JSON="${LEAKAGE_JSON:-/etc/hw-management-bmc-a2d-leakage-config.json}"

# Minimum expected config entries (fixed set for SMBIOS / ready path).
CONFIG_REQUIRED_NAMES=(bom cpu_type hid pn)
CONFIG_REQUIRED_COUNT=4

failures=0
warns=0

warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
ok() { echo "OK: $*"; }

resolve_boot_complete_conf()
{
	if [[ -r "$BOOT_COMPLETE_CONF" ]]; then
		echo "$BOOT_COMPLETE_CONF"
		return 0
	fi
	if [[ -r "$REPO_HI189/hw-management-bmc-boot-complete.conf" ]]; then
		echo "$REPO_HI189/hw-management-bmc-boot-complete.conf"
		return 0
	fi
	echo ""
	return 1
}

resolve_leakage_json()
{
	if [[ -r "$LEAKAGE_JSON" ]]; then
		echo "$LEAKAGE_JSON"
		return 0
	fi
	if [[ -r "$REPO_HI189/hw-management-bmc-a2d-leakage-config.json" ]]; then
		echo "$REPO_HI189/hw-management-bmc-a2d-leakage-config.json"
		return 0
	fi
	echo ""
	return 1
}

count_entries_boot_complete()
{
	local _d="$1"
	if [[ ! -d "$_d" ]]; then
		echo 0
		return
	fi
	# Match hw-management-bmc-boot-complete.sh: all entries (files, dirs, symlinks).
	ls -A "$_d" 2>/dev/null | wc -l
}

json_array_length()
{
	local jf="$1"
	if command -v jq >/dev/null 2>&1; then
		jq 'length' "$jf" 2>/dev/null
		return
	fi
	if command -v python3 >/dev/null 2>&1; then
		python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$jf" 2>/dev/null
		return
	fi
	fail "jq or python3 required to parse $jf (top-level array length)"
	echo 0
}

count_leakage_detector_dirs()
{
	local n=0 d
	if [[ ! -d "$LEAKAGE_ROOT" ]]; then
		echo 0
		return
	fi
	shopt -s nullglob
	for d in "$LEAKAGE_ROOT"/*; do
		[[ -d "$d" ]] || continue
		case "$(basename "$d")" in
		*[!0-9]*) ;;
		*)
			if [[ "$(basename "$d")" =~ ^[1-9][0-9]*$ || "$(basename "$d")" == "0" ]]; then
				# Only strictly positive detector indices (1-based in docs)
				if [[ "$(basename "$d")" =~ ^[0-9]+$ ]]; then
					n=$((n + 1))
				fi
			fi
			;;
		esac
	done
	shopt -u nullglob
	echo "$n"
}

# Simpler: only digit-only directory names (1, 2, …)
count_leakage_numeric_dirs()
{
	local n=0 d base
	[[ -d "$LEAKAGE_ROOT" ]] || { echo 0; return; }
	for d in "$LEAKAGE_ROOT"/*/; do
		[[ -d "$d" ]] || continue
		base=$(basename "$d")
		if [[ "$base" =~ ^[0-9]+$ ]]; then
			n=$((n + 1))
		fi
	done
	echo "$n"
}

count_leakage_files_only()
{
	# All regular files under leakage/ tree (for reports).
	if [[ ! -d "$LEAKAGE_ROOT" ]]; then
		echo 0
		return
	fi
	find "$LEAKAGE_ROOT" -type f 2>/dev/null | wc -l
}

validate_config_dir()
{
	local found=0 name c
	echo ""
	echo "== config ($CONFIG_DIR) — expect $CONFIG_REQUIRED_COUNT entries: ${CONFIG_REQUIRED_NAMES[*]} =="
	if [[ ! -d "$CONFIG_DIR" ]]; then
		fail "missing directory $CONFIG_DIR"
		return
	fi
	c=$(ls -A "$CONFIG_DIR" 2>/dev/null | wc -l)
	c=${c// /}
	if [[ "$c" -ne "$CONFIG_REQUIRED_COUNT" ]]; then
		fail "config entry count $c != $CONFIG_REQUIRED_COUNT ($(ls -A "$CONFIG_DIR" 2>/dev/null | tr '\n' ' '))"
	else
		ok "config entry count = $CONFIG_REQUIRED_COUNT"
	fi
	for name in "${CONFIG_REQUIRED_NAMES[@]}"; do
		if [[ -e "$CONFIG_DIR/$name" ]]; then
			ok "config: present '$name'"
		else
			fail "config: missing required entry '$name'"
		fi
	done
}

validate_boot_complete_dirs()
{
	local conf conf_path need_sys need_thr need_eep c_sys c_thr c_eep
	echo ""
	echo "== system / thermal / eeprom (vs hw-management-bmc-boot-complete.conf) =="
	conf_path=$(resolve_boot_complete_conf) || true
	if [[ -z "$conf_path" ]]; then
		fail "boot-complete conf not found (try BOOT_COMPLETE_CONF or REPO_HI189)"
		warn "skipping system/thermal/eeprom threshold check"
		return
	fi
	# shellcheck source=/dev/null
	. "$conf_path"
	need_sys="${SYSFS_SYSTEM_COUNTER:?}"
	need_thr="${SYSFS_THERMAL_COUNTER:?}"
	need_eep="${SYSFS_EEPROM_COUNTER:?}"
	ok "using thresholds from $conf_path (system>=$need_sys thermal>=$need_thr eeprom>=$need_eep)"

	c_sys=$(count_entries_boot_complete "$SYSTEM_DIR")
	c_thr=$(count_entries_boot_complete "$THERMAL_DIR")
	c_eep=$(count_entries_boot_complete "$EEPROM_DIR")

	if [[ "$c_sys" -ge "$need_sys" ]]; then
		ok "system count=$c_sys (need >= $need_sys)"
	else
		fail "system count=$c_sys < $need_sys ($SYSTEM_DIR)"
	fi
	if [[ "$c_thr" -ge "$need_thr" ]]; then
		ok "thermal count=$c_thr (need >= $need_thr)"
	else
		fail "thermal count=$c_thr < $need_thr ($THERMAL_DIR)"
	fi
	if [[ "$c_eep" -ge "$need_eep" ]]; then
		ok "eeprom count=$c_eep (need >= $need_eep)"
	else
		fail "eeprom count=$c_eep < $need_eep ($EEPROM_DIR)"
	fi
}

validate_leakage()
{
	local jf len actual files
	echo ""
	echo "== leakage ($LEAKAGE_ROOT) vs a2d-leakage JSON =="
	jf=$(resolve_leakage_json) || true
	if [[ -z "$jf" ]]; then
		fail "leakage JSON not found (LEAKAGE_JSON or REPO_HI189)"
		return
	fi
	len=$(json_array_length "$jf")
	if ! [[ "$len" =~ ^[0-9]+$ ]]; then
		fail "could not get detector count from $jf"
		return
	fi
	ok "expected leakage detectors (JSON array length) = $len from $jf"

	actual=$(count_leakage_numeric_dirs)
	files=$(count_leakage_files_only)
	ok "leakage numeric detector dirs (1…N) = $actual"
	ok "leakage total regular files (tree) = $files (informational)"

	if [[ "$actual" -eq "$len" ]]; then
		ok "leakage detector dir count matches JSON ($actual == $len)"
	else
		fail "leakage detector dirs $actual != JSON length $len"
	fi
}

validate_roots_exist()
{
	echo "hw-management sysfs validation ($(date -Iseconds 2>/dev/null || date))"
	echo "Root: $HW_MGMT_ROOT"
	local d
	for d in config leakage system eeprom thermal; do
		if [[ -d "$HW_MGMT_ROOT/$d" ]]; then
			ok "directory exists: $HW_MGMT_ROOT/$d"
		else
			fail "missing directory: $HW_MGMT_ROOT/$d"
		fi
	done
}

main()
{
	validate_roots_exist
	validate_config_dir
	validate_boot_complete_dirs
	validate_leakage

	echo ""
	echo "-------------------------------------------------------------------"
	if [[ "$failures" -eq 0 ]]; then
		echo "Summary: all checks passed (warnings=$warns)."
		exit 0
	fi
	echo "Summary: failures=$failures warnings=$warns"
	exit 1
}

main "$@"
