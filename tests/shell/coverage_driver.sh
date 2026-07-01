#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Shell coverage driver: exercises production scripts so kcov can measure line
# coverage via ptrace.  Run through kcov (not shellspec) so that direct script
# execs are tracked.  Mirrors the scenarios in the shellspec test suite.
#
# Usage:
#   kcov --include-path=REPO/usr/usr/bin COVDIR tests/shell/coverage_driver.sh REPO_ROOT
#   OR
#   tests/shell/coverage_driver.sh REPO_ROOT   (no coverage, smoke test)

REPO_ROOT="$(cd "${1:-$(dirname "$0")/../..}" && pwd)"
SCRIPT_DIR="${REPO_ROOT}/usr/usr/bin"

PASS=0
FAIL=0

_check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc — expected '$expected', got '$actual'" >&2
    fi
}

_check_rc() {
    local desc="$1" expected_rc="$2" actual_rc="$3"
    if [ "$actual_rc" = "$expected_rc" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc — expected rc=$expected_rc, got rc=$actual_rc" >&2
    fi
}

_check_contains() {
    local desc="$1" pattern="$2" actual="$3"
    if echo "$actual" | grep -q "$pattern"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc — expected to contain '$pattern', got: $actual" >&2
    fi
}

###############################################################################
# hw-management-led-state-conversion.sh
###############################################################################
LED_SCRIPT="${SCRIPT_DIR}/hw-management-led-state-conversion.sh"
LED_TMP=$(mktemp -d)
trap 'rm -rf "$LED_TMP" "$BIN_TMP" "$VR_DEVTREE" "$VR_FW_BASE"' EXIT

# Symlink makes $0 = LED_TMP/led_status_state so the script computes:
#   DNAME = LED_TMP, LED_NAME = led_status
_led_run() {
    # Recreate symlink each time (_led_clean uses find -type f, which skips it,
    # but _led_run is defensive so it always exists before exec)
    ln -sf "$LED_SCRIPT" "$LED_TMP/led_status_state"
    rm -f "$LED_TMP/led_status"
    "$LED_TMP/led_status_state" 2>/dev/null
    cat "$LED_TMP/led_status" 2>/dev/null
}

# Remove regular LED data files only; -type f skips the led_status_state symlink
_led_clean() {
    find "$LED_TMP" -maxdepth 1 -type f -name "led_status*" -delete 2>/dev/null
}

# No LED files → none
_led_clean
_check "LED none (no files)" "none" "$(_led_run)"

# Red solid
_led_clean
echo 255 > "$LED_TMP/led_status_red"; echo 0 > "$LED_TMP/led_status_green"
_check "LED red solid" "red" "$(_led_run)"

# Green solid
_led_clean
echo 0 > "$LED_TMP/led_status_red"; echo 255 > "$LED_TMP/led_status_green"
_check "LED green solid" "green" "$(_led_run)"

# Blue solid
_led_clean
echo 1 > "$LED_TMP/led_status_blue"; echo 0 > "$LED_TMP/led_status_red"
_check "LED blue solid" "blue" "$(_led_run)"

# Amber solid
_led_clean
echo 100 > "$LED_TMP/led_status_amber"; echo 0 > "$LED_TMP/led_status_red"
_check "LED amber solid" "amber" "$(_led_run)"

# All zeros → none
_led_clean
echo 0 > "$LED_TMP/led_status_red"; echo 0 > "$LED_TMP/led_status_green"
_check "LED none (all zero)" "none" "$(_led_run)"

# Red blinking
_led_clean
echo 255 > "$LED_TMP/led_status_red"
echo 500 > "$LED_TMP/led_status_red_delay_on"
echo 500 > "$LED_TMP/led_status_red_delay_off"
echo 0   > "$LED_TMP/led_status_green"
_check "LED red_blink" "red_blink" "$(_led_run)"

# Green blinking
_led_clean
echo 255 > "$LED_TMP/led_status_green"
echo 200 > "$LED_TMP/led_status_green_delay_on"
echo 200 > "$LED_TMP/led_status_green_delay_off"
echo 0   > "$LED_TMP/led_status_red"
_check "LED green_blink" "green_blink" "$(_led_run)"

# Amber blinking
_led_clean
echo 200  > "$LED_TMP/led_status_amber"
echo 1000 > "$LED_TMP/led_status_amber_delay_on"
echo 1000 > "$LED_TMP/led_status_amber_delay_off"
echo 0    > "$LED_TMP/led_status_red"
echo 0    > "$LED_TMP/led_status_green"
_check "LED amber_blink" "amber_blink" "$(_led_run)"

# delay_on=0 → no blink (solid red)
_led_clean
echo 255 > "$LED_TMP/led_status_red"
echo 0   > "$LED_TMP/led_status_red_delay_on"
echo 500 > "$LED_TMP/led_status_red_delay_off"
_check "LED no blink when delay_on=0" "red" "$(_led_run)"

# delay_off=0 → no blink (solid red)
_led_clean
echo 255 > "$LED_TMP/led_status_red"
echo 500 > "$LED_TMP/led_status_red_delay_on"
echo 0   > "$LED_TMP/led_status_red_delay_off"
_check "LED no blink when delay_off=0" "red" "$(_led_run)"

# brightness=0 with delay files → none
_led_clean
echo 0   > "$LED_TMP/led_status_red"
echo 500 > "$LED_TMP/led_status_red_delay_on"
echo 500 > "$LED_TMP/led_status_red_delay_off"
_check "LED none when brightness=0" "none" "$(_led_run)"

# _state and _capability files are ignored
_led_clean
echo "some_state" > "$LED_TMP/led_status_state_extra"
echo "caps"       > "$LED_TMP/led_status_capability"
echo 255 > "$LED_TMP/led_status_red"
_check "LED ignores _state/_capability" "red" "$(_led_run)"

# Multiple colors: green active
_led_clean
echo 0   > "$LED_TMP/led_status_red"
echo 255 > "$LED_TMP/led_status_green"
echo 0   > "$LED_TMP/led_status_blue"
echo 0   > "$LED_TMP/led_status_amber"
_check "LED multi-color: green active" "green" "$(_led_run)"

# Real-world: system healthy (green solid, delays=0)
_led_clean
echo 0   > "$LED_TMP/led_status_red"
echo 255 > "$LED_TMP/led_status_green"
echo 0   > "$LED_TMP/led_status_green_delay_on"
echo 0   > "$LED_TMP/led_status_green_delay_off"
_check "LED healthy (green solid, delays=0)" "green" "$(_led_run)"

# Real-world: error (red blink)
_led_clean
echo 255 > "$LED_TMP/led_status_red"
echo 250 > "$LED_TMP/led_status_red_delay_on"
echo 250 > "$LED_TMP/led_status_red_delay_off"
echo 0   > "$LED_TMP/led_status_green"
_check "LED error (red_blink)" "red_blink" "$(_led_run)"

###############################################################################
# hw-management-read-vr-model-version.sh
###############################################################################
READ_VR="${SCRIPT_DIR}/hw-management-read-vr-model-version.sh"

# Stub i2c tools: i2cget returns empty output (exit 0), i2cset/i2ctransfer exit 0
BIN_TMP=$(mktemp -d)
for _t in i2cset i2ctransfer; do
    printf '#!/bin/sh\nexit 0\n' > "${BIN_TMP}/${_t}"
    chmod +x "${BIN_TMP}/${_t}"
done
# i2cget returns empty line (so read_smbus_word gets empty string → get_model fails gracefully)
printf '#!/bin/sh\nexit 0\n' > "${BIN_TMP}/i2cget"
chmod +x "${BIN_TMP}/i2cget"

# Devtrees for different scenarios
VR_DEVTREE=$(mktemp)
VR_FW_BASE=$(mktemp -d)

# Scenario 1: single unsupported device — --show --json (original test)
echo "tps53679 0x40 X voltmon-test0" > "$VR_DEVTREE"
VR_OUTPUT=$(PATH="${BIN_TMP}:$PATH" DEVTREE_FILE="$VR_DEVTREE" \
            bash "$READ_VR" --show --json 2>/dev/null)
_check_contains "read-vr JSON: voltmon_name field" '"voltmon_name":"voltmon-test0"' "$VR_OUTPUT"
_check_contains "read-vr JSON: model=Not supported" '"model":"Not supported"' "$VR_OUTPUT"

# Scenario 2: multiple devices in devtree — --show --json
{
    echo "tps53679 0x40 X voltmon-dev0"
    echo "mp2975 0x41 X voltmon-dev1"
} > "$VR_DEVTREE"
VR_OUTPUT=$(PATH="${BIN_TMP}:$PATH" DEVTREE_FILE="$VR_DEVTREE" \
            bash "$READ_VR" --show --json 2>/dev/null)
_check_contains "read-vr JSON multi-device: dev0" '"voltmon_name":"voltmon-dev0"' "$VR_OUTPUT"
_check_contains "read-vr JSON multi-device: dev1" '"voltmon_name":"voltmon-dev1"' "$VR_OUTPUT"

# Scenario 3: --show (table mode, no json) with unsupported device
echo "tps53679 0x40 X voltmon-tbl0" > "$VR_DEVTREE"
VR_TABLE=$(PATH="${BIN_TMP}:$PATH" DEVTREE_FILE="$VR_DEVTREE" \
           bash "$READ_VR" --show 2>/dev/null)
_check_contains "read-vr table mode: header" "Voltmon Name" "$VR_TABLE"
_check_contains "read-vr table mode: device row" "voltmon-tbl0" "$VR_TABLE"
_check_contains "read-vr table mode: Not supported" "Not supported" "$VR_TABLE"

# Scenario 4: --show (table mode) with supported device type (mp2975, numeric bus)
# i2cget returns empty → model=N/A
echo "mp2975 0x40 0 voltmon-sup0" > "$VR_DEVTREE"
VR_TABLE=$(PATH="${BIN_TMP}:$PATH" DEVTREE_FILE="$VR_DEVTREE" \
           bash "$READ_VR" --show 2>/dev/null)
_check_contains "read-vr table supported device: header" "Voltmon Name" "$VR_TABLE"
_check_contains "read-vr table supported device: row" "voltmon-sup0" "$VR_TABLE"

# Scenario 5: --show (table mode) with unknown device type
echo "some_unknown_driver 0x40 X voltmon-unk0" > "$VR_DEVTREE"
VR_TABLE=$(PATH="${BIN_TMP}:$PATH" DEVTREE_FILE="$VR_DEVTREE" \
           bash "$READ_VR" --show 2>/dev/null)
_check_contains "read-vr table unknown device: Unknown device" "Unknown device" "$VR_TABLE"

# Scenario 6: --json without --show (error path)
echo "tps53679 0x40 X voltmon0" > "$VR_DEVTREE"
bash "$READ_VR" --json >/dev/null 2>&1
_check_rc "read-vr: --json without --show exits non-zero" "1" "$?"

# Scenario 7: unknown option (error path)
bash "$READ_VR" --unknown-option >/dev/null 2>&1
_check_rc "read-vr: unknown option exits non-zero" "1" "$?"

# Scenario 8: --help (usage output)
HELP_OUT=$(bash "$READ_VR" --help 2>&1)
_check_rc "read-vr: --help exits zero" "0" "$?"

# Scenario 9: missing DEVTREE_FILE with --show --json
rm -f "$VR_DEVTREE"
bash "$READ_VR" --show --json >/dev/null 2>&1 \
    < /dev/null
_check_rc "read-vr: missing devtree --show --json exits non-zero" "1" "$?"

# Re-create for next tests
echo "tps53679 0x40 X voltmon-test0" > "$VR_DEVTREE"

# Scenario 10: missing DEVTREE_FILE with --show
rm -f "$VR_DEVTREE"
bash "$READ_VR" --show >/dev/null 2>&1
_check_rc "read-vr: missing devtree --show exits non-zero" "1" "$?"

# Scenario 11: parse_devtree mode (no --show) with unsupported device (tps53679)
# This exercises parse_devtree(), get_model_version() unsupported branch
echo "tps53679 0x40 0 voltmon-parse0" > "$VR_DEVTREE"
PATH="${BIN_TMP}:$PATH" DEVTREE_FILE="$VR_DEVTREE" FIRMWARE_BASE="$VR_FW_BASE" \
    bash "$READ_VR" >/dev/null 2>&1
_check_rc "read-vr: parse_devtree unsupported device exits zero" "0" "$?"

# Scenario 12: parse_devtree mode with supported device (mp2975, numeric bus)
# Exercises get_model_version(), get_model(), get_revision(), copy_to_ui_firmware()
echo "mp2975 0x40 0 voltmon-parse1" > "$VR_DEVTREE"
PATH="${BIN_TMP}:$PATH" DEVTREE_FILE="$VR_DEVTREE" FIRMWARE_BASE="$VR_FW_BASE" \
    bash "$READ_VR" >/dev/null 2>&1
_check_rc "read-vr: parse_devtree supported device exits zero" "0" "$?"
# device_name file should be written
_check_contains "read-vr: parse_devtree device_name written" "mp2975" \
    "$(cat "$VR_FW_BASE/voltmon-parse1/device_name" 2>/dev/null)"

# Scenario 13: parse_devtree with non-voltmon device (should be skipped)
echo "some_driver 0x40 0 sensorX" > "$VR_DEVTREE"
PATH="${BIN_TMP}:$PATH" DEVTREE_FILE="$VR_DEVTREE" FIRMWARE_BASE="$VR_FW_BASE" \
    bash "$READ_VR" >/dev/null 2>&1
_check_rc "read-vr: parse_devtree non-voltmon device exits zero" "0" "$?"

# Scenario 14: JSON mode with multiple devices including non-voltmon entry
{
    echo "tps53679 0x40 X voltmon-j0"
    echo "some_sensor 0x50 X sensorX"
    echo "mp2975 0x41 X voltmon-j1"
} > "$VR_DEVTREE"
VR_OUTPUT=$(PATH="${BIN_TMP}:$PATH" DEVTREE_FILE="$VR_DEVTREE" \
            bash "$READ_VR" --show --json 2>/dev/null)
_check_contains "read-vr JSON: only voltmon-j0 and voltmon-j1" '"voltmon_name":"voltmon-j0"' "$VR_OUTPUT"
_check_contains "read-vr JSON: voltmon-j1 present" '"voltmon_name":"voltmon-j1"' "$VR_OUTPUT"

# Scenario 15: JSON mode with xdpe1a2g7b (byte_offset=1 path in get_device_registers)
echo "xdpe1a2g7b 0x40 X voltmon-xdpe" > "$VR_DEVTREE"
VR_OUTPUT=$(PATH="${BIN_TMP}:$PATH" DEVTREE_FILE="$VR_DEVTREE" \
            bash "$READ_VR" --show --json 2>/dev/null)
_check_contains "read-vr JSON xdpe1a2g7b: device_name" '"device_name":"xdpe1a2g7b"' "$VR_OUTPUT"

# Scenario 16: JSON mode with mp29816 (supported, page-based registers)
echo "mp29816 0x40 X voltmon-mp" > "$VR_DEVTREE"
VR_OUTPUT=$(PATH="${BIN_TMP}:$PATH" DEVTREE_FILE="$VR_DEVTREE" \
            bash "$READ_VR" --show --json 2>/dev/null)
_check_contains "read-vr JSON mp29816: device_name" '"device_name":"mp29816"' "$VR_OUTPUT"

###############################################################################
# Summary
###############################################################################
echo "coverage_driver: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
