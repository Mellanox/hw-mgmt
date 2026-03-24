#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Exercise mlxreg LEDs under /sys/class/leds/: for each mlxreg entry, read
# brightness, force "no color" (brightness 0), verify, enumerate available
# colors (sibling LEDs sharing the same mlxreg:<function>: prefix), verify
# sysfs reads on those nodes, then restore original brightness and trigger.
#
# Typical names: mlxreg:power:amber mlxreg:status:green mlxreg:uid:blue …
#
# Environment (optional):
#   LED_CLASS=/sys/class/leds
#   LED_STRICT=1  — exit with failure if no mlxreg LEDs are present (default: warn and skip)
#
# Requires write access to LED sysfs (usually root). Exit: 0 on success or skip; 1 on failure.

set -u
set +e

LED_CLASS="${LED_CLASS:-/sys/class/leds}"

declare -A LED_GROUP_MEMBERS

failures=0
warns=0

warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
ok() { echo "OK: $*"; }

is_mlxreg_led_name()
{
	case "$1" in
	mlxreg*) return 0 ;;
	*) return 1 ;;
	esac
}

# Sibling group key: everything before the last ':' (mlxreg:power:amber -> mlxreg:power).
sibling_key()
{
	local n="$1"
	echo "${n%:*}"
}

read_trim()
{
	# shellcheck disable=SC2002
	cat "$1" 2>/dev/null | tr -d '\n' | tr -d '\r'
}

collect_mlxreg_leds()
{
	local p
	shopt -s nullglob
	for p in "$LED_CLASS"/mlxreg*; do
		[[ -d "$p" ]] || continue
		is_mlxreg_led_name "$(basename "$p")" || continue
		if [[ -r "$p/brightness" && -w "$p/brightness" ]]; then
			echo "$p"
		fi
	done
	shopt -u nullglob
}

# Build map: sibling_key -> space-separated list of full LED names (basename).
build_sibling_map()
{
	LED_GROUP_MEMBERS=()
	local p n k
	shopt -s nullglob
	for p in "$LED_CLASS"/mlxreg*; do
		[[ -d "$p" ]] || continue
		n=$(basename "$p")
		is_mlxreg_led_name "$n" || continue
		[[ -r "$p/brightness" ]] || continue
		k=$(sibling_key "$n")
		LED_GROUP_MEMBERS["$k"]+="${n} "
	done
	shopt -u nullglob
}

validate_available_colors_group()
{
	local name="$1" key mem m path mb
	key=$(sibling_key "$name")
	mem="${LED_GROUP_MEMBERS[$key]:-}"

	if [[ -z "$mem" ]]; then
		warn "no sibling map for $name (key=$key)"
		return
	fi

	ok "available colors for '$key': $mem"

	for m in $mem; do
		path="$LED_CLASS/$m"
		if [[ ! -d "$path" ]]; then
			fail "sibling LED missing: $path"
			continue
		fi
		if [[ -r "$path/max_brightness" ]]; then
			mb=$(read_trim "$path/max_brightness")
			if [[ "$mb" =~ ^[0-9]+$ ]]; then
				ok "  $m: max_brightness=$mb"
			else
				fail "  $m: max_brightness not numeric: '$mb'"
			fi
		else
			warn "  $m: no max_brightness (optional)"
		fi
		if [[ -r "$path/brightness" ]]; then
			ok "  $m: brightness=$(read_trim "$path/brightness") (readback)"
		fi
	done
}

test_one_led()
{
	local led_path="$1"
	local name
	name=$(basename "$led_path")

	local orig_b orig_t cur new_b
	orig_b=$(read_trim "$led_path/brightness")
	orig_t="none"
	if [[ -r "$led_path/trigger" ]]; then
		orig_t=$(read_trim "$led_path/trigger")
	fi

	ok "LED $name: initial brightness=$orig_b trigger=$orig_t"

	if [[ "$orig_t" != "none" ]] && [[ -w "$led_path/trigger" ]]; then
		if ! echo none >"$led_path/trigger" 2>/dev/null; then
			warn "LED $name: could not set trigger to none; brightness writes may fail"
		else
			ok "LED $name: set trigger none (was: $orig_t)"
		fi
	fi

	if ! echo 0 >"$led_path/brightness" 2>/dev/null; then
		fail "LED $name: cannot write brightness 0 (need root or blocked trigger?)"
		echo "$orig_b" >"$led_path/brightness" 2>/dev/null || true
		if [[ "$orig_t" != "none" ]] && [[ -w "$led_path/trigger" ]]; then
			echo "$orig_t" >"$led_path/trigger" 2>/dev/null || true
		fi
		return
	fi

	cur=$(read_trim "$led_path/brightness")
	if [[ "$cur" == "0" ]]; then
		ok "LED $name: brightness after off=0 (readback)"
	else
		fail "LED $name: expected brightness 0 after write, got '$cur'"
	fi

	validate_available_colors_group "$name"

	if ! echo "$orig_b" >"$led_path/brightness" 2>/dev/null; then
		fail "LED $name: cannot restore brightness $orig_b"
	else
		new_b=$(read_trim "$led_path/brightness")
		if [[ "$new_b" == "$orig_b" ]]; then
			ok "LED $name: restored brightness=$new_b (matches saved $orig_b)"
		else
			# Some stacks normalize (e.g. 1 vs 255); still OK if both represent "on"
			if [[ "$orig_b" != "0" && "$new_b" != "0" ]]; then
				ok "LED $name: restored brightness=$new_b (saved was $orig_b; driver may normalize)"
			else
				fail "LED $name: restore mismatch: saved=$orig_b readback=$new_b"
			fi
		fi
	fi

	if [[ -w "$led_path/trigger" ]]; then
		if ! echo "$orig_t" >"$led_path/trigger" 2>/dev/null; then
			warn "LED $name: could not restore trigger '$orig_t'"
		else
			ok "LED $name: restored trigger=$orig_t"
		fi
	fi
}

main()
{
	local paths p n count
	echo "mlxreg LED validation ($(date -Iseconds 2>/dev/null || date))"
	echo "LED class: $LED_CLASS"

	if [[ ! -d "$LED_CLASS" ]]; then
		fail "missing $LED_CLASS"
		echo "Summary: failures=$failures"
		exit 1
	fi

	mapfile -t paths < <(collect_mlxreg_leds)
	count=${#paths[@]}

	if [[ "$count" -eq 0 ]]; then
		if [[ -n "${LED_STRICT:-}" ]]; then
			fail "no writable mlxreg LEDs under $LED_CLASS (set LED_STRICT unset to skip)"
			exit 1
		fi
		warn "no writable mlxreg LEDs under $LED_CLASS — nothing to test (use LED_STRICT=1 to fail)"
		exit 0
	fi

	ok "found $count mlxreg LED sysfs nodes with readable+writable brightness"

	build_sibling_map

	for p in "${paths[@]}"; do
		echo ""
		test_one_led "$p"
	done

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
