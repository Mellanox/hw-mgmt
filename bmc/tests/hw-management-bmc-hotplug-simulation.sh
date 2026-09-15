#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Simulate mlxreg-hotplug udev "change" rules from 5-hw-management-bmc-events.rules:
# for each rule, require a matching name under /var/run/hw-management/system, run the
# same argv as RUN+, then validate journal (and special cases) against hw-management-bmc-events.sh.
#
# Output: /tmp/hw-management-bmc-hotplug-simulation (append; includes summary counters).

set -u
set +e
set +o pipefail

RULES_FILE="${RULES_FILE:-}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_BMC="${REPO_BMC:-$(cd "$SCRIPT_DIR/.." && pwd)}"
if [[ -z "$RULES_FILE" ]]; then
	RULES_FILE="$REPO_BMC/usr/etc/HI189/5-hw-management-bmc-events.rules"
fi

SYSTEM_DIR="${HW_MANAGEMENT_SYSTEM_DIR:-/var/run/hw-management/system}"
LEAKAGE_ROOT="${HW_MANAGEMENT_LEAKAGE_ROOT:-/var/run/hw-management/leakage}"
EVENTS_BIN="${HW_MANAGEMENT_BMC_EVENTS:-/usr/bin/hw-management-bmc-events.sh}"
REPORT_LOG="${HW_MANAGEMENT_BMC_HOTPLUG_SIM_LOG:-/tmp/hw-management-bmc-hotplug-simulation}"
JOURNAL_TAG="hw-management-events"
SYSFS_ROOT="/sys"

LED_HOST_RESET="/sys/class/leds/mlxreg:status:green/brightness"

# Counters
TOTAL_RULES=0
SKIPPED=0
EXECUTED=0
PASSED=0
FAILED=0

log_line()
{
	printf '%s\n' "$*" | tee -a "$REPORT_LOG"
}

have_journalctl()
{
	command -v journalctl >/dev/null 2>&1 || return 1
	journalctl -q -n 0 >/dev/null 2>&1
}

leakage_state_fp()
{
	local idx=$1
	local f
	find "${LEAKAGE_ROOT}/$idx" -type f \( -name last_event -o -name last_sample \) 2>/dev/null | LC_ALL=C sort | while read -r f; do
		stat -c '%n %Y %s' "$f" 2>/dev/null
	done
}

discover_hotplug_devpath()
{
	local p
	shopt -s nullglob
	for p in /sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0ff00.i2c-bus/i2c-14/14-0031/mlxreg-hotplug/hwmon/hwmon*; do
		if [[ -d "$p" ]]; then
			printf '%s' "${p#/sys}"
			return 0
		fi
	done
	printf '%s' \
'/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0ff00.i2c-bus/i2c-14/14-0031/mlxreg-hotplug/hwmon/hwmon0'
	return 1
}

extract_run_cmd()
{
	# RUN+="/usr/bin/hw-management-bmc-events.sh ..."
	local line=$1
	if [[ "$line" =~ RUN\+=\"([^\"]+)\" ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
		return 0
	fi
	return 1
}

extract_prereq_name()
{
	local line=$1
	if [[ "$line" =~ ATTR\{([^}]+)\} ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
		return 0
	fi
	if [[ "$line" =~ ENV\{([^}]+)\} ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
		return 0
	fi
	return 1
}

expand_run_cmd()
{
	local cmd=$1
	local devpath=$2
	local out=${cmd//%S/$SYSFS_ROOT}
	out=${out//%p/$devpath}
	printf '%s' "$out"
}

# Args: $1 = epoch seconds (journal window start), $2... = argv for hw-management-bmc-events.sh (no script path)
verify_expectation()
{
	local t0=$1
	shift
	local action=${1:-}
	local event=${2:-}
	local status=${3:-}

	local jmsg
	if ! have_journalctl; then
		log_line "VERIFY: journalctl unavailable or empty — cannot validate MESSAGE (fail)."
		return 1
	fi

	jmsg=$(journalctl -q -t "$JOURNAL_TAG" --since "@$t0" 2>/dev/null || true)

	case "$action" in
	change)
		if [[ "$event" == "hotplug_asic" ]]; then
			if grep -Fq "ACTION=${action} EVENT=${event} STATUS=${status}" <<<"$jmsg"; then
				return 0
			fi
			log_line "VERIFY: missing default log for change/hotplug_asic (ACTION/EVENT/STATUS)."
			return 1
		fi
		log_line "VERIFY: unexpected change EVENT=${event}"
		return 1
		;;
	hotplug-event)
		case "$event" in
		CPU_RESET)
			if ! grep -Fq "CPU reset - going up" <<<"$jmsg"; then
				log_line "VERIFY: missing CPU reset - going up"
				return 1
			fi
			if ! grep -Fq "CPLD dump:" <<<"$jmsg"; then
				log_line "VERIFY: missing CPLD dump"
				return 1
			fi
			if [[ -w "$LED_HOST_RESET" ]]; then
				local br
				br=$(tr -d ' \t\r\n' <"$LED_HOST_RESET" 2>/dev/null || echo "")
				if [[ "$br" != "0" ]]; then
					log_line "VERIFY: LED $LED_HOST_RESET expected 0, got $br"
					return 1
				fi
			fi
			return 0
			;;
		APML_SMB_ALERT)
			grep -Fq "APML SMB alert" <<<"$jmsg" && return 0
			log_line "VERIFY: missing APML SMB alert"
			return 1
			;;
		GRACEFUL_POWER_OFF_REQ)
			grep -Fq "Request host for gracefull power off" <<<"$jmsg" && return 0
			log_line "VERIFY: missing GRACEFUL_POWER_OFF_REQ message"
			return 1
			;;
		LEAKAGE_AGGR)
			case "$status" in
			0)
				grep -Fq "Leakage detected" <<<"$jmsg" && return 0
				;;
			1)
				grep -Fq "Leakage cleared" <<<"$jmsg" && return 0
				;;
			*)
				if grep -Fq "Hotplug event ${event} ${status}" <<<"$jmsg"; then
					return 0
				fi
				return 1
				;;
			esac
			log_line "VERIFY: LEAKAGE_AGGR status=${status} message mismatch"
			return 1
			;;
		*)
			if [[ "$event" =~ ^LEAKAGE[0-9]+$ ]]; then
				if ! grep -Fq "Activate leakage handler for event ${event#LEAKAGE} received at timestamp" <<<"$jmsg"; then
					log_line "VERIFY: missing leakage handler journal line for ${event}"
					return 1
				fi
				return 0
			fi
			if grep -Fq "ACTION=hotplug-event EVENT=${event} STATUS=${status}" <<<"$jmsg"; then
				return 0
			fi
			log_line "VERIFY: missing default hotplug-event log for EVENT=${event} STATUS=${status}"
			return 1
			;;
		esac
		;;
	*)
		log_line "VERIFY: unknown action=$action"
		return 1
		;;
	esac
}

run_simulation()
{
	local devpath
	devpath=$(discover_hotplug_devpath)

	: >"$REPORT_LOG"
	log_line "=== hw-management-bmc-hotplug-simulation $(date -Is) ==="
	log_line "RULES_FILE=$RULES_FILE"
	log_line "SYSTEM_DIR=$SYSTEM_DIR EVENTS_BIN=$EVENTS_BIN"
	log_line "DEVPATH=$devpath"

	if [[ ! -f "$RULES_FILE" ]]; then
		log_line "ERROR: rules file not found: $RULES_FILE"
		return 1
	fi
	if [[ ! -f "$EVENTS_BIN" ]]; then
		log_line "ERROR: events script not found: $EVENTS_BIN"
		return 1
	fi

	local line run_cmd expanded prereq key
	declare -A seen_run

	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		[[ "$line" =~ mlxreg-hotplug ]] || continue
		[[ "$line" =~ ACTION==\"change\" ]] || continue
		[[ "$line" =~ RUN\+\= ]] || continue

		run_cmd=$(extract_run_cmd "$line") || continue
		key="$run_cmd"
		[[ -n "${seen_run[$key]:-}" ]] && continue
		seen_run[$key]=1

		prereq=$(extract_prereq_name "$line") || {
			log_line "SKIP (no ATTR/ENV): ${line:0:120}..."
			((SKIPPED++)) || true
			((TOTAL_RULES++)) || true
			continue
		}

		((TOTAL_RULES++)) || true

		if [[ ! -e "$SYSTEM_DIR/$prereq" ]] && [[ ! -L "$SYSTEM_DIR/$prereq" ]]; then
			log_line "SKIP missing system entry: $SYSTEM_DIR/$prereq | $run_cmd"
			((SKIPPED++)) || true
			continue
		fi

		expanded=$(expand_run_cmd "$run_cmd" "$devpath")
		local -a parts=()
		read -r -a parts <<<"$expanded"
		if [[ "${parts[0]##*/}" != "hw-management-bmc-events.sh" ]]; then
			log_line "SKIP unexpected handler path: ${parts[0]}"
			((SKIPPED++)) || true
			continue
		fi
		parts[0]="$EVENTS_BIN"

		local t0 leakage_idx="" lf_before lf_after
		t0=$(date +%s)
		if [[ "${parts[1]:-}" == "hotplug-event" ]] && [[ "${parts[2]:-}" =~ ^LEAKAGE[0-9]+$ ]]; then
			leakage_idx=${parts[2]#LEAKAGE}
			lf_before=$(leakage_state_fp "$leakage_idx")
		fi
		"${parts[@]}" || true
		if [[ -n "$leakage_idx" ]]; then
			sleep 0.4
			lf_after=$(leakage_state_fp "$leakage_idx")
			if [[ -n "$lf_before" || -n "$lf_after" ]]; then
				if [[ "$lf_before" != "$lf_after" ]]; then
					log_line "LEAKAGE${leakage_idx}: last_event/last_sample state changed under ${LEAKAGE_ROOT}/${leakage_idx}/"
				else
					log_line "LEAKAGE${leakage_idx}: note — last_event/last_sample unchanged (handler may skip in-band samples)."
				fi
			fi
		fi
		((EXECUTED++)) || true

		if verify_expectation "$t0" "${parts[@]:1}"; then
			log_line "PASS $run_cmd"
			((PASSED++)) || true
		else
			log_line "FAIL $run_cmd"
			((FAILED++)) || true
		fi
	done <"$RULES_FILE"

	log_line "---"
	log_line "SUMMARY: total_rules=$TOTAL_RULES skipped=$SKIPPED executed=$EXECUTED pass=$PASSED fail=$FAILED"
	return 0
}

usage()
{
	cat <<EOF
Usage: $0
  Environment:
    RULES_FILE              Path to 5-hw-management-bmc-events.rules (default: under repo HI189)
    HW_MANAGEMENT_SYSTEM_DIR  (default: /var/run/hw-management/system)
    HW_MANAGEMENT_BMC_EVENTS  Path to hw-management-bmc-events.sh (default: /usr/bin/...)
    HW_MANAGEMENT_BMC_HOTPLUG_SIM_LOG  (default: /tmp/hw-management-bmc-hotplug-simulation)
    REPO_BMC                bmc/ directory if RULES_FILE not set
EOF
}

case "${1:-}" in
-h|--help) usage; exit 0 ;;
esac

run_simulation
exit 0
