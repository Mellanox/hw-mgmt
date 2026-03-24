#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Simulate leakage hotplug udev events for one A2D leak detector index:
#   hw-management-bmc-events.sh hotplug-event LEAKAGE<n> 1
#   hw-management-bmc-events.sh hotplug-event LEAKAGE<n> 0
# (see usr/etc/HI189/hw-management-bmc-events.sh — spawns leakage-handler.)
#
# Before and after, records every .../leakage/<n>/<channel>/input value under the
# detector tree (same layout as runtime: .../leakage/<n>/<m>/input).
#
# Usage: hw-management-bmc-leak-simulation.sh <leakage index>
#
# Environment (optional):
#   HW_MGMT_ROOT=/var/run/hw-management
#   HW_MANAGEMENT_BMC_EVENTS=/usr/bin/hw-management-bmc-events.sh
#   LEAK_SIM_EVENT_DELAY_SEC=1   — sleep between the two hotplug-event calls
#   LEAK_SIM_POST_DELAY_SEC=1    — sleep after last event before final sample
#
# Exit: 0 on success; 1 on usage error or missing paths.

set -u
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_BMC="${REPO_BMC:-$(cd "$SCRIPT_DIR/.." && pwd)}"

HW_MGMT_ROOT="${HW_MGMT_ROOT:-/var/run/hw-management}"
LEAKAGE_ROOT="$HW_MGMT_ROOT/leakage"

EVENTS_BIN="${HW_MANAGEMENT_BMC_EVENTS:-/usr/bin/hw-management-bmc-events.sh}"
LEAK_SIM_EVENT_DELAY_SEC="${LEAK_SIM_EVENT_DELAY_SEC:-1}"
LEAK_SIM_POST_DELAY_SEC="${LEAK_SIM_POST_DELAY_SEC:-1}"

read_trim()
{
	tr -d '\r\n' <"$1" 2>/dev/null || true
}

resolve_events_bin()
{
	if [[ -x "$EVENTS_BIN" ]]; then
		echo "$EVENTS_BIN"
		return 0
	fi
	if [[ -f "$EVENTS_BIN" ]]; then
		echo "$EVENTS_BIN"
		return 0
	fi
	local p="$REPO_BMC/usr/etc/HI189/hw-management-bmc-events.sh"
	if [[ -x "$p" ]]; then
		echo "$p"
		return 0
	fi
	if [[ -f "$p" ]]; then
		echo "$p"
		return 0
	fi
	echo ""
	return 1
}

# Print relative path under leakage/<idx>/ and raw input value (one line each).
dump_leakage_inputs()
{
	local idx="$1" tag="$2"
	local base="$LEAKAGE_ROOT/$idx"
	local f rel v any=0

	echo ""
	echo "=== $tag — $base/*/input ==="
	if [[ ! -d "$base" ]]; then
		echo "(missing directory: $base)" >&2
		return 1
	fi

	while IFS= read -r f; do
		[[ -e "$f" ]] || continue
		rel=${f#"$base"/}
		v=$(read_trim "$f")
		printf '%s=%s\n' "$rel" "$v"
		any=1
	done < <(find "$base" -mindepth 2 -maxdepth 2 -name input 2>/dev/null | LC_ALL=C sort)

	if [[ "$any" -eq 0 ]]; then
		echo "(no .../input nodes under $base)"
	fi
	return 0
}

usage()
{
	cat >&2 <<EOF
Usage: $0 <leakage index>
  Records .../leakage/<n>/<m>/input, runs hotplug-event LEAKAGE<n> 1 then 0, records again.

Environment:
  HW_MGMT_ROOT=/var/run/hw-management
  HW_MANAGEMENT_BMC_EVENTS=/usr/bin/hw-management-bmc-events.sh
  LEAK_SIM_EVENT_DELAY_SEC=1
  LEAK_SIM_POST_DELAY_SEC=1

Example: $0 1
EOF
	exit 1
}

main()
{
	local idx evbin rc

	case "${1:-}" in
	""|-h|--help) usage ;;
	esac
	[[ "$1" =~ ^[0-9]+$ ]] || usage
	idx=$1

	echo "hw-management-bmc-leak-simulation — leakage index=$idx ($(date -Iseconds 2>/dev/null || date))"
	echo "LEAKAGE_ROOT=$LEAKAGE_ROOT"

	if [[ ! -d "$LEAKAGE_ROOT/$idx" ]]; then
		echo "ERROR: leakage detector directory not found: $LEAKAGE_ROOT/$idx" >&2
		exit 1
	fi

	dump_leakage_inputs "$idx" "BEFORE hotplug-event" || exit 1

	evbin=$(resolve_events_bin) || true
	if [[ -z "$evbin" ]]; then
		echo "ERROR: hw-management-bmc-events.sh not found (set HW_MANAGEMENT_BMC_EVENTS)" >&2
		exit 1
	fi
	echo "EVENTS_BIN=$evbin"

	echo ""
	echo "=== hotplug-event LEAKAGE${idx} 1 ==="
	if [[ -x "$evbin" ]]; then
		"$evbin" hotplug-event "LEAKAGE${idx}" 1
	else
		bash "$evbin" hotplug-event "LEAKAGE${idx}" 1
	fi
	rc=$?
	if [[ "$rc" -ne 0 ]]; then
		echo "ERROR: hotplug-event LEAKAGE${idx} 1 exited with $rc" >&2
		exit 1
	fi

	sleep "${LEAK_SIM_EVENT_DELAY_SEC}"

	echo ""
	echo "=== hotplug-event LEAKAGE${idx} 0 ==="
	if [[ -x "$evbin" ]]; then
		"$evbin" hotplug-event "LEAKAGE${idx}" 0
	else
		bash "$evbin" hotplug-event "LEAKAGE${idx}" 0
	fi
	rc=$?
	if [[ "$rc" -ne 0 ]]; then
		echo "ERROR: hotplug-event LEAKAGE${idx} 0 exited with $rc" >&2
		exit 1
	fi

	sleep "${LEAK_SIM_POST_DELAY_SEC}"

	dump_leakage_inputs "$idx" "AFTER hotplug-event" || exit 1

	echo ""
	echo "Done."
	exit 0
}

main "$@"
