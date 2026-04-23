#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Validate hw-management-bmc systemd units: load/active state, Result, and
# ExecMainDurationUSec (main process runtime for oneshot/exited jobs; often
# empty for long-running Type=simple services).
#
# Run on the BMC (or any host with these units installed). Requires systemctl.
#
# Usage: hw-management-bmc-services-validation.sh [--no-discover]
#   --no-discover  Use built-in unit list if list-unit-files finds nothing.
#
# Exit: 0 if no unit is failed; 1 if any unit is failed.

set -u
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

UNITS_DEFAULT=(
	hw-management-bmc-reset-cause-logger.service
	hw-management-bmc-plat-specific-preps.service
	hw-management-bmc-early-config.service
	hw-management-bmc-early-i2c-init.service
	hw-management-bmc-init.service
	hw-management-bmc-boot-complete.service
	hw-management-bmc-health-monitor.service
	hw-management-bmc-i2c-slave-setup.service
	hw-management-bmc-recovery-handler.service
)

discover_units()
{
	systemctl list-unit-files 'hw-management-bmc*.service' --no-legend 2>/dev/null \
		| awk '$1 ~ /\.service$/ {print $1}' | LC_ALL=C sort -u
}

duration_from_usec()
{
	local us="$1"
	case "$us" in
	''|0) printf '%s' '—' ;;
	*)
		if [[ "$us" =~ ^[0-9]+$ ]]; then
			awk -v u="$us" 'BEGIN { printf "%.3fs", u / 1000000.0 }'
		else
			printf '%s' '—'
		fi
		;;
	esac
}

main()
{
	local discover=1
	local units=()
	local u
	local t0 t1 wall
	local fail_count=0
	local ok_count=0
	local skip_count=0
	local load active sub result us
	local state

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--no-discover) discover=0 ;;
		-h|--help)
			head -n 18 "$0" | tail -n +2
			exit 0
			;;
		*) echo "Unknown option: $1" >&2; exit 2 ;;
		esac
		shift
	done

	if ! command -v systemctl >/dev/null 2>&1; then
		echo "systemctl not found; this script is intended for systemd hosts." >&2
		exit 2
	fi

	if [[ "$discover" -eq 1 ]]; then
		mapfile -t units < <(discover_units)
	fi
	if [[ ${#units[@]} -eq 0 ]]; then
		units=("${UNITS_DEFAULT[@]}")
	fi

	echo "hw-management-bmc services validation ($(date -Iseconds 2>/dev/null || date))"
	echo "Columns: unit | load | active | sub | result | ExecMainDuration | state"
	echo "  (ExecMainDuration = main process time from systemd; — if N/A or still running)"
	echo "-------------------------------------------------------------------"

	t0=$(date +%s.%N 2>/dev/null || date +%s)

	for u in "${units[@]}"; do
		load=$(systemctl show "$u" -p LoadState --value 2>/dev/null | tr -d '\n')
		active=$(systemctl show "$u" -p ActiveState --value 2>/dev/null | tr -d '\n')
		sub=$(systemctl show "$u" -p SubState --value 2>/dev/null | tr -d '\n')
		result=$(systemctl show "$u" -p Result --value 2>/dev/null | tr -d '\n')
		us=$(systemctl show "$u" -p ExecMainDurationUSec --value 2>/dev/null | tr -d '\n')

		if [[ "$load" != "loaded" && "$load" != "masked" ]]; then
			state=SKIP
			skip_count=$((skip_count + 1))
		elif systemctl is-failed --quiet "$u" 2>/dev/null; then
			state=FAIL
			fail_count=$((fail_count + 1))
		else
			state=OK
			ok_count=$((ok_count + 1))
		fi

		printf '%-46s %-8s %-10s %-14s %-10s %-12s %s\n' \
			"$u" "${load:-?}" "${active:-?}" "${sub:-?}" "${result:-?}" \
			"$(duration_from_usec "$us")" "$state"

		if [[ "$state" == "FAIL" ]]; then
			systemctl status "$u" --no-pager -l 2>&1 | head -n 20 >&2 || true
			echo "  ^ $u" >&2
		fi
	done

	t1=$(date +%s.%N 2>/dev/null || date +%s)
	if command -v bc >/dev/null 2>&1 && [[ "$t0" == *.* ]]; then
		wall=$(echo "scale=3; $t1 - $t0" | bc)
	else
		wall=$((t1 - t0))
		wall="${wall}s (approx)"
	fi

	echo "-------------------------------------------------------------------"
	printf 'Summary: OK=%d FAILED=%d SKIP=%d script_wall_time=%s\n' \
		"$ok_count" "$fail_count" "$skip_count" "$wall"
	if [[ "$fail_count" -gt 0 ]]; then
		exit 1
	fi
	exit 0
}

main "$@"
