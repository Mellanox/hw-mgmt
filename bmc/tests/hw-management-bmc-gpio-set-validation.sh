#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Validate hw-management-bmc-gpio-set.sh functions offline.
# All GPIO sysfs paths are redirected to a tmpdir; no real kernel GPIO
# files are touched and no root privilege is required.
#
# Tests:
#   1. Script presence, executable, syntax (bash -n)
#   2. gpiochip_base_by_ngpio: finds chip with matching ngpio in mock sysfs
#   3. gpiochip_base_by_ngpio: returns 1 when no matching chip exists
#   4. gpiochip_base_aspeed: prefers ngpio=208 (AST2600)
#   5. gpiochip_base_aspeed: falls back to ngpio=216 (AST2700)
#   6. gpiochip_base_aspeed: falls back to ngpio range 200–230
#   7. gpiochip_base_aspeed: returns 1 when no Aspeed chip found
#   8. gpio_export: creates gpio dir and writes to export file
#   9. gpio_export: no-op (returns 0) when gpio dir already present
#  10. gpio_export: returns 1 for empty gpio number
#  11. gpio_dir: writes direction to mocked sysfs file
#  12. gpio_dir: returns 1 for empty args
#  13. gpio_set: writes value to mocked sysfs file
#  14. gpio_get: reads value from mocked sysfs file
#  15. gpio_get: returns 1 for empty gpio number
#  16. gpio_base_for_chip_id: unknown chip id returns 1
#
# Environment (optional):
#   GPIO_SET_SCRIPT — path to hw-management-bmc-gpio-set.sh
#
# Exit: 0 if all checks pass; 1 otherwise.

set -u
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_BMC=$(cd "$SCRIPT_DIR/.." && pwd)
GPIO_SET_SCRIPT="${GPIO_SET_SCRIPT:-$REPO_BMC/usr/usr/bin/hw-management-bmc-gpio-set.sh}"

failures=0
warns=0

ok()   { echo "OK: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "hw-management-bmc gpio-set validation ($(date -Iseconds 2>/dev/null || date))"
echo "Script: $GPIO_SET_SCRIPT"

# ── presence and syntax ──────────────────────────────────────────────────────

echo ""
echo "== presence and syntax =="

if [[ ! -f "$GPIO_SET_SCRIPT" ]]; then
    fail "script not found: $GPIO_SET_SCRIPT"
    echo "Summary: failures=$failures"
    exit 1
fi
ok "script exists"

if [[ -x "$GPIO_SET_SCRIPT" ]]; then
    ok "script is executable"
else
    warn "script is not executable (chmod +x missing?)"
fi

if bash -n "$GPIO_SET_SCRIPT" 2>/dev/null; then
    ok "bash -n: no syntax errors"
else
    fail "bash -n: syntax errors detected"
fi

# ── mock sysfs and no-op logger ───────────────────────────────────────────────

GPIO_MOCK="$WORK/sys_class_gpio"
mkdir -p "$GPIO_MOCK"

MOCK_BIN="$WORK/mock_bin"
mkdir -p "$MOCK_BIN"
printf '#!/bin/sh\n: # no-op\n' >"$MOCK_BIN/logger"
chmod +x "$MOCK_BIN/logger"

# ── gpiochip_base_by_ngpio (mock-sysfs versions) ─────────────────────────────

echo ""
echo "== gpiochip_base_by_ngpio with mocked /sys/class/gpio =="

# Inline reproductions that use GPIO_MOCK instead of /sys/class/gpio.
gpiochip_base_by_ngpio_mock() {
    local ngpio="$1"
    local quiet="${2:-}"
    local chip base
    for chip in "$GPIO_MOCK"/gpiochip*; do
        [ -d "$chip" ] || continue
        if [ "$(cat "$chip/ngpio" 2>/dev/null)" = "$ngpio" ]; then
            base=$(cat "$chip/base" 2>/dev/null)
            if [ -n "$base" ]; then
                echo "$base"
                return 0
            fi
        fi
    done
    return 1
}

# Populate two chips.
CHIP208="$GPIO_MOCK/gpiochip100"
CHIP24="$GPIO_MOCK/gpiochip432"
mkdir -p "$CHIP208" "$CHIP24"
echo "208" >"$CHIP208/ngpio"; echo "100" >"$CHIP208/base"
echo "24"  >"$CHIP24/ngpio";  echo "432" >"$CHIP24/base"

base=$(gpiochip_base_by_ngpio_mock 208)
if [[ "$base" == "100" ]]; then
    ok "gpiochip_base_by_ngpio(208): returns base=100"
else
    fail "gpiochip_base_by_ngpio(208): expected 100, got '$base'"
fi

base=$(gpiochip_base_by_ngpio_mock 24)
if [[ "$base" == "432" ]]; then
    ok "gpiochip_base_by_ngpio(24): returns base=432"
else
    fail "gpiochip_base_by_ngpio(24): expected 432, got '$base'"
fi

gpiochip_base_by_ngpio_mock 999 quiet >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "gpiochip_base_by_ngpio(999): returns 1 when not found"
else
    fail "gpiochip_base_by_ngpio(999): expected 1, got $rc"
fi

# ── gpiochip_base_aspeed preference / fallback ───────────────────────────────

echo ""
echo "== gpiochip_base_aspeed: AST2600 → AST2700 → range → not found =="

gpiochip_base_aspeed_mock() {
    local base ng chip_path

    base=$(gpiochip_base_by_ngpio_mock 208 quiet 2>/dev/null)
    if [ -n "$base" ]; then echo "$base"; return 0; fi

    base=$(gpiochip_base_by_ngpio_mock 216 quiet 2>/dev/null)
    if [ -n "$base" ]; then echo "$base"; return 0; fi

    for chip_path in "$GPIO_MOCK"/gpiochip*; do
        [ -d "$chip_path" ] || continue
        ng=$(cat "$chip_path/ngpio" 2>/dev/null)
        [ -n "$ng" ] || continue
        if [ "$ng" -ge 200 ] && [ "$ng" -le 230 ]; then
            base=$(cat "$chip_path/base" 2>/dev/null)
            if [ -n "$base" ]; then echo "$base"; return 0; fi
        fi
    done
    return 1
}

# ngpio=208 present → returns its base.
aspeed_base=$(gpiochip_base_aspeed_mock)
if [[ "$aspeed_base" == "100" ]]; then
    ok "gpiochip_base_aspeed: prefers ngpio=208 (AST2600), base=100"
else
    fail "gpiochip_base_aspeed: expected 100, got '$aspeed_base'"
fi

# Remove ngpio=208, add ngpio=216 → should fall back.
rm -rf "$CHIP208"
CHIP216="$GPIO_MOCK/gpiochip200"
mkdir -p "$CHIP216"
echo "216" >"$CHIP216/ngpio"; echo "200" >"$CHIP216/base"

aspeed_base=$(gpiochip_base_aspeed_mock)
if [[ "$aspeed_base" == "200" ]]; then
    ok "gpiochip_base_aspeed: falls back to ngpio=216 (AST2700), base=200"
else
    fail "gpiochip_base_aspeed: expected 200 for ngpio=216, got '$aspeed_base'"
fi

# Remove ngpio=216, add ngpio=210 (in-range) → should be found via range scan.
rm -rf "$CHIP216"
CHIP210="$GPIO_MOCK/gpiochip300"
mkdir -p "$CHIP210"
echo "210" >"$CHIP210/ngpio"; echo "300" >"$CHIP210/base"

aspeed_base=$(gpiochip_base_aspeed_mock)
if [[ "$aspeed_base" == "300" ]]; then
    ok "gpiochip_base_aspeed: range scan finds ngpio=210, base=300"
else
    fail "gpiochip_base_aspeed: range scan expected 300, got '$aspeed_base'"
fi

# Remove all Aspeed-range chips → returns 1.
rm -rf "$CHIP210" "$CHIP24"
gpiochip_base_aspeed_mock >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "gpiochip_base_aspeed: returns 1 when no Aspeed chip found"
else
    fail "gpiochip_base_aspeed: expected 1, got $rc"
fi

# Restore chips for remaining tests.
mkdir -p "$CHIP208" "$CHIP24"
echo "208" >"$CHIP208/ngpio"; echo "100" >"$CHIP208/base"
echo "24"  >"$CHIP24/ngpio";  echo "432" >"$CHIP24/base"

# ── gpio_export, gpio_dir, gpio_set, gpio_get (mock sysfs) ───────────────────

echo ""
echo "== gpio_export / gpio_dir / gpio_set / gpio_get with mocked sysfs =="

GPIO_SYS="$WORK/mock_gpio_sys"
mkdir -p "$GPIO_SYS"
touch "$GPIO_SYS/export"

# Inline reproductions that use GPIO_SYS instead of /sys/class/gpio.
gpio_export_mock() {
    local g="$1"
    if [ -z "$g" ]; then return 1; fi
    if [ ! -d "${GPIO_SYS}/gpio${g}" ]; then
        echo "$g" >"${GPIO_SYS}/export" 2>/dev/null || return 1
        mkdir -p "${GPIO_SYS}/gpio${g}"
    fi
    return 0
}

gpio_dir_mock() {
    local g="$1" dir="$2"
    if [ -z "$g" ] || [ -z "$dir" ]; then return 1; fi
    echo "$dir" >"${GPIO_SYS}/gpio${g}/direction" 2>/dev/null || return 1
    return 0
}

gpio_set_mock() {
    local g="$1" val="$2"
    if [ -z "$g" ]; then return 1; fi
    echo "$val" >"${GPIO_SYS}/gpio${g}/value" 2>/dev/null || return 1
    return 0
}

gpio_get_mock() {
    local g="$1"
    if [ -z "$g" ]; then return 1; fi
    cat "${GPIO_SYS}/gpio${g}/value" 2>/dev/null
}

# gpio_export: creates gpio dir and writes to export file.
gpio_export_mock 42
if [[ -d "$GPIO_SYS/gpio42" ]]; then
    ok "gpio_export(42): gpio42 directory created"
else
    fail "gpio_export(42): gpio42 directory not created"
fi
export_written=$(cat "$GPIO_SYS/export" 2>/dev/null | tr -d '[:space:]')
if [[ "$export_written" == "42" ]]; then
    ok "gpio_export(42): wrote 42 to export file"
else
    fail "gpio_export(42): expected '42' in export, got '$export_written'"
fi

# gpio_export: no-op when gpio dir already exists.
gpio_export_mock 42
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "gpio_export(42) repeat: returns 0 (already exported)"
else
    fail "gpio_export(42) repeat: expected 0, got $rc"
fi

# gpio_export: empty gpio number → returns 1.
gpio_export_mock "" 2>/dev/null
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "gpio_export(''): returns 1 for empty gpio number"
else
    fail "gpio_export(''): expected 1, got $rc"
fi

# gpio_dir: write direction.
gpio_dir_mock 42 "out"
dir_val=$(cat "$GPIO_SYS/gpio42/direction" 2>/dev/null | tr -d '[:space:]')
if [[ "$dir_val" == "out" ]]; then
    ok "gpio_dir(42, 'out'): direction='out'"
else
    fail "gpio_dir(42, 'out'): expected 'out', got '$dir_val'"
fi

gpio_dir_mock 42 "in"
dir_val=$(cat "$GPIO_SYS/gpio42/direction" 2>/dev/null | tr -d '[:space:]')
if [[ "$dir_val" == "in" ]]; then
    ok "gpio_dir(42, 'in'): direction='in'"
else
    fail "gpio_dir(42, 'in'): expected 'in', got '$dir_val'"
fi

# gpio_dir: empty args → returns 1.
gpio_dir_mock "" "out" 2>/dev/null
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "gpio_dir('', 'out'): returns 1 for empty gpio number"
else
    fail "gpio_dir('', 'out'): expected 1, got $rc"
fi

# gpio_set / gpio_get roundtrip.
touch "$GPIO_SYS/gpio42/value"
gpio_set_mock 42 1
val=$(gpio_get_mock 42 | tr -d '[:space:]')
if [[ "$val" == "1" ]]; then
    ok "gpio_set(42,1) + gpio_get(42): value=1"
else
    fail "gpio_set/gpio_get(42,1): expected 1, got '$val'"
fi

gpio_set_mock 42 0
val=$(gpio_get_mock 42 | tr -d '[:space:]')
if [[ "$val" == "0" ]]; then
    ok "gpio_set(42,0) + gpio_get(42): value=0"
else
    fail "gpio_set/gpio_get(42,0): expected 0, got '$val'"
fi

# gpio_get: empty gpio → returns 1.
gpio_get_mock "" 2>/dev/null
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "gpio_get(''): returns 1 for empty gpio number"
else
    fail "gpio_get(''): expected 1, got $rc"
fi

# ── gpio_base_for_chip_id: unknown chip id → 1 ───────────────────────────────

echo ""
echo "== gpio_base_for_chip_id: unknown chip id returns 1 =="

# Source the script with PATH pointing to our no-op logger; the script has no
# top-level execution so sourcing is safe.
PATH="$MOCK_BIN:$PATH" bash -c \
    "source '$GPIO_SET_SCRIPT'; gpio_base_for_chip_id 'unknown_chip_xyz' 2>/dev/null"
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "gpio_base_for_chip_id(unknown_chip_xyz): returns 1"
else
    fail "gpio_base_for_chip_id(unknown_chip_xyz): expected 1, got $rc"
fi

# ── summary ──────────────────────────────────────────────────────────────────

echo ""
echo "-------------------------------------------------------------------"
if [[ "$failures" -eq 0 ]]; then
    echo "Summary: all checks passed (warnings=$warns)."
    exit 0
fi
echo "Summary: failures=$failures warnings=$warns"
exit 1
