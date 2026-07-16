#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Unit tests for hw-management-bmc-json-parser.sh.
# Sources the library and tests each function against known JSON fixtures.
# No hardware access required; fully offline.
#
# Exit: 0 if all checks pass; 1 otherwise.

set -u
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PARSER_LIB="$SCRIPT_DIR/../usr/usr/bin/hw-management-bmc-json-parser.sh"

failures=0
warns=0

ok()   { echo "OK: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }

# ── fixtures ──────────────────────────────────────────────────────────────────

TMPDIR_TESTS=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

SIMPLE_JSON="$TMPDIR_TESTS/simple.json"
cat >"$SIMPLE_JSON" <<'EOF'
[
  {
    "chip": "pca9548",
    "Bus": 5,
    "Addr": 112,
    "enabled": true,
    "nested": {
      "key": "value"
    }
  },
  {
    "chip": "lm75",
    "Bus": 4,
    "Addr": 72,
    "enabled": false
  }
]
EOF

NESTED_JSON="$TMPDIR_TESTS/nested.json"
cat >"$NESTED_JSON" <<'EOF'
{
  "devices": [
    { "name": "sensor0", "channel": 0 },
    { "name": "sensor1", "channel": 1 }
  ]
}
EOF

BAD_JSON="$TMPDIR_TESTS/bad.json"
printf '{ "foo": "bar" \n' >"$BAD_JSON"

# ── load library ─────────────────────────────────────────────────────────────

if [[ ! -f "$PARSER_LIB" ]]; then
    fail "parser library not found: $PARSER_LIB"
    echo "Summary: failures=$failures"
    exit 1
fi
# shellcheck source=/dev/null
source "$PARSER_LIB"

echo "hw-management-bmc JSON parser validation ($(date -Iseconds 2>/dev/null || date))"
echo "Library: $PARSER_LIB"

# ── json_validate ─────────────────────────────────────────────────────────────

echo ""
echo "== json_validate =="
if json_validate "$SIMPLE_JSON"; then
    ok "json_validate: well-formed array JSON passes"
else
    fail "json_validate: well-formed array JSON unexpectedly failed"
fi

if json_validate "$BAD_JSON"; then
    fail "json_validate: malformed JSON (unbalanced braces) should have failed"
else
    ok "json_validate: malformed JSON correctly rejected"
fi

if json_validate "$TMPDIR_TESTS/nonexistent.json" 2>/dev/null; then
    fail "json_validate: nonexistent file should return 1"
else
    ok "json_validate: nonexistent file correctly rejected"
fi

# ── json_get_array_element ────────────────────────────────────────────────────

echo ""
echo "== json_get_array_element =="
elem0=$(json_get_array_element "$SIMPLE_JSON" 0)
if [[ -n "$elem0" ]]; then
    ok "json_get_array_element: index 0 returned non-empty block"
else
    fail "json_get_array_element: index 0 returned empty"
fi

elem1=$(json_get_array_element "$SIMPLE_JSON" 1)
if echo "$elem1" | grep -q '"lm75"'; then
    ok "json_get_array_element: index 1 contains 'lm75'"
else
    fail "json_get_array_element: index 1 missing 'lm75' (got: $(echo "$elem1" | head -1))"
fi

elem_oob=$(json_get_array_element "$SIMPLE_JSON" 99)
if [[ -z "$elem_oob" ]]; then
    ok "json_get_array_element: out-of-bounds index returns empty"
else
    fail "json_get_array_element: out-of-bounds index should return empty"
fi

# ── json_count_array_elements ─────────────────────────────────────────────────

echo ""
echo "== json_count_array_elements =="
count=$(json_count_array_elements "$SIMPLE_JSON")
if [[ "$count" -eq 2 ]]; then
    ok "json_count_array_elements: 2-element array → count=$count"
else
    fail "json_count_array_elements: expected 2, got '$count'"
fi

# ── json_get_string ────────────────────────────────────────────────────────────

echo ""
echo "== json_get_string =="
chip0=$(echo "$elem0" | json_get_string "chip")
if [[ "$chip0" == "pca9548" ]]; then
    ok "json_get_string: chip='$chip0'"
else
    fail "json_get_string: expected 'pca9548', got '$chip0'"
fi

chip1=$(echo "$elem1" | json_get_string "chip")
if [[ "$chip1" == "lm75" ]]; then
    ok "json_get_string: chip='$chip1' (second element)"
else
    fail "json_get_string: expected 'lm75', got '$chip1'"
fi

missing_str=$(echo "$elem0" | json_get_string "nonexistent_key")
if [[ -z "$missing_str" ]]; then
    ok "json_get_string: missing key returns empty string"
else
    fail "json_get_string: missing key should return empty, got '$missing_str'"
fi

# ── json_get_number ────────────────────────────────────────────────────────────

echo ""
echo "== json_get_number =="
bus0=$(echo "$elem0" | json_get_number "Bus")
if [[ "$bus0" == "5" ]]; then
    ok "json_get_number: Bus=$bus0"
else
    fail "json_get_number: expected 5, got '$bus0'"
fi

addr0=$(echo "$elem0" | json_get_number "Addr")
if [[ "$addr0" == "112" ]]; then
    ok "json_get_number: Addr=$addr0"
else
    fail "json_get_number: expected 112, got '$addr0'"
fi

bus1=$(echo "$elem1" | json_get_number "Bus")
if [[ "$bus1" == "4" ]]; then
    ok "json_get_number: Bus=$bus1 (second element)"
else
    fail "json_get_number: expected 4, got '$bus1'"
fi

missing_num=$(echo "$elem0" | json_get_number "nonexistent_key")
if [[ -z "$missing_num" ]]; then
    ok "json_get_number: missing key returns empty"
else
    fail "json_get_number: missing key should return empty, got '$missing_num'"
fi

# ── json_get_bool ──────────────────────────────────────────────────────────────

echo ""
echo "== json_get_bool =="
en0=$(echo "$elem0" | json_get_bool "enabled")
if [[ "$en0" == "true" ]]; then
    ok "json_get_bool: enabled=true for element 0"
else
    fail "json_get_bool: expected 'true', got '$en0'"
fi

en1=$(echo "$elem1" | json_get_bool "enabled")
if [[ "$en1" == "false" ]]; then
    ok "json_get_bool: enabled=false for element 1"
else
    fail "json_get_bool: expected 'false', got '$en1'"
fi

# ── json_get_nested_array_element ─────────────────────────────────────────────

echo ""
echo "== json_get_nested_array_element =="
nested_elem0=$(cat "$NESTED_JSON" | json_get_nested_array_element "devices" 0)
if echo "$nested_elem0" | grep -q '"sensor0"'; then
    ok "json_get_nested_array_element: index 0 contains 'sensor0'"
else
    fail "json_get_nested_array_element: index 0 missing 'sensor0' (got: $nested_elem0)"
fi

nested_elem1=$(cat "$NESTED_JSON" | json_get_nested_array_element "devices" 1)
if echo "$nested_elem1" | grep -q '"sensor1"'; then
    ok "json_get_nested_array_element: index 1 contains 'sensor1'"
else
    fail "json_get_nested_array_element: index 1 missing 'sensor1' (got: $nested_elem1)"
fi

# ── json_count_nested_array ───────────────────────────────────────────────────

echo ""
echo "== json_count_nested_array =="
nested_count=$(cat "$NESTED_JSON" | json_count_nested_array "devices")
if [[ "$nested_count" -eq 2 ]]; then
    ok "json_count_nested_array: 'devices' → count=$nested_count"
else
    fail "json_count_nested_array: expected 2, got '$nested_count'"
fi

# ── real config files ─────────────────────────────────────────────────────────

echo ""
echo "== real HI189 config files (smoke test) =="
REPO_BMC=$(cd "$SCRIPT_DIR/.." && pwd)
LEAKAGE_JSON="${REPO_BMC}/usr/etc/HI189/hw-management-bmc-a2d-leakage-config.json"
EARLY_I2C_JSON="${REPO_BMC}/usr/etc/HI189/hw-management-bmc-early-i2c-devices.json"
GPIO_JSON="${REPO_BMC}/usr/etc/HI189/hw-management-bmc-gpio-pins.json"

for jf in "$LEAKAGE_JSON" "$EARLY_I2C_JSON" "$GPIO_JSON"; do
    if [[ ! -f "$jf" ]]; then
        warn "config not in repo: $jf (skip)"
        continue
    fi
    if json_validate "$jf"; then
        cnt=$(json_count_array_elements "$jf")
        ok "$(basename "$jf"): valid, top-level elements=$cnt"
    else
        fail "$(basename "$jf"): json_validate failed"
    fi
done

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "-------------------------------------------------------------------"
if [[ "$failures" -eq 0 ]]; then
    echo "Summary: all checks passed (warnings=$warns)."
    exit 0
fi
echo "Summary: failures=$failures warnings=$warns"
exit 1
