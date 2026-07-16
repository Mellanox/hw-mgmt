#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Validate hw-management-bmc-generate-dump.sh offline.
# Pure helper functions (safe_unit_fname, safe_rel_fname, is_eeprom_path,
# readlink_canonical) are reproduced inline — sourcing the script would
# trigger the full dump collection and call exit.  Arg-parsing tests run a
# patched copy (stub helpers-common) directly.
#
# Tests:
#   1. Script presence, executable, syntax (bash -n)
#   2. safe_unit_fname: /, @, : → _ ; plain names unchanged
#   3. safe_rel_fname: strips /var/run/hw-management prefix, / → _
#   4. safe_rel_fname: bare HW_MGMT path → "root"
#   5. is_eeprom_path: eeprom/* paths, eeprom sysfs nodes, eeprom_* basenames → 0
#   6. is_eeprom_path: non-eeprom paths → 1
#   7. readlink_canonical: returns a non-empty path for an existing file
#   8. parse_args: -h prints usage and exits 0
#   9. parse_args: unknown option exits 1
#  10. parse_args: -v sets VERBOSE=1; positional arg overrides OUTPUT_TAR
#
# Environment (optional):
#   GENERATE_DUMP_SCRIPT — path to hw-management-bmc-generate-dump.sh
#
# Exit: 0 if all checks pass; 1 otherwise.

set -u
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_BMC=$(cd "$SCRIPT_DIR/.." && pwd)
GEN_DUMP_SCRIPT="${GENERATE_DUMP_SCRIPT:-$REPO_BMC/usr/usr/bin/hw-management-bmc-generate-dump.sh}"

failures=0
warns=0

ok()   { echo "OK: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "hw-management-bmc generate-dump validation ($(date -Iseconds 2>/dev/null || date))"
echo "Script: $GEN_DUMP_SCRIPT"

# ── presence and syntax ──────────────────────────────────────────────────────

echo ""
echo "== presence and syntax =="

if [[ ! -f "$GEN_DUMP_SCRIPT" ]]; then
    fail "script not found: $GEN_DUMP_SCRIPT"
    echo "Summary: failures=$failures"
    exit 1
fi
ok "script exists"

if [[ -x "$GEN_DUMP_SCRIPT" ]]; then
    ok "script is executable"
else
    warn "script is not executable (chmod +x missing?)"
fi

if bash -n "$GEN_DUMP_SCRIPT" 2>/dev/null; then
    ok "bash -n: no syntax errors"
else
    fail "bash -n: syntax errors detected"
fi

# ── inline reproductions of pure helper functions ─────────────────────────────
# Sourcing generate-dump.sh would trigger the full dump collection and call
# exit.  The four functions below are verbatim copies from the script.

HW_MGMT="/var/run/hw-management"

safe_unit_fname()
{
    echo "$1" | tr '/@:' '___'
}

safe_rel_fname()
{
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
    [[ "$f" == */eeprom/* ]] && return 0
    [[ "$f" == */eeprom"" ]] && return 0
    [[ "$base" == eeprom ]] && return 0
    [[ "$base" == eeprom_* ]] && return 0
    return 1
}

readlink_canonical()
{
    local p=$1
    local o
    if command -v realpath >/dev/null 2>&1; then
        o=$(realpath "$p" 2>/dev/null) && { printf '%s\n' "$o"; return; }
    fi
    o=$(readlink -f "$p" 2>/dev/null) && { printf '%s\n' "$o"; return; }
    readlink "$p" 2>/dev/null
}

# ── safe_unit_fname ───────────────────────────────────────────────────────────

echo ""
echo "== safe_unit_fname =="

check_unit_fname() {
    local input="$1" expected="$2"
    local result
    result=$(safe_unit_fname "$input")
    if [[ "$result" == "$expected" ]]; then
        ok "safe_unit_fname('$input'): '$result'"
    else
        fail "safe_unit_fname('$input'): expected '$expected', got '$result'"
    fi
}

check_unit_fname "hw-management-bmc@1.service"          "hw-management-bmc_1.service"
check_unit_fname "dbus-org.freedesktop.hostname1.service" "dbus-org.freedesktop.hostname1.service"
check_unit_fname "var/run/hw-management"                "var_run_hw-management"
check_unit_fname "a:b:c"                                "a_b_c"
check_unit_fname "a/b/c"                                "a_b_c"
check_unit_fname "a@b/c:d"                              "a_b_c_d"
check_unit_fname "plain-name"                           "plain-name"
check_unit_fname ""                                     ""

# ── safe_rel_fname ────────────────────────────────────────────────────────────

echo ""
echo "== safe_rel_fname =="

check_rel_fname() {
    local input="$1" expected="$2"
    local result
    result=$(safe_rel_fname "$input")
    if [[ "$result" == "$expected" ]]; then
        ok "safe_rel_fname('$input'): '$result'"
    else
        fail "safe_rel_fname('$input'): expected '$expected', got '$result'"
    fi
}

check_rel_fname "/var/run/hw-management/thermal/cpu_temp"   "thermal_cpu_temp"
check_rel_fname "/var/run/hw-management/system/fan1_speed"  "system_fan1_speed"
check_rel_fname "/var/run/hw-management/eeprom/eeprom_bmc"  "eeprom_eeprom_bmc"
check_rel_fname "/var/run/hw-management/bmc/reset_power_on" "bmc_reset_power_on"
check_rel_fname "/var/run/hw-management"                    "var_run_hw-management"
check_rel_fname "/var/run/hw-management/"                   "root"
check_rel_fname "/var/run/hw-management/a/b/c"              "a_b_c"

# ── is_eeprom_path ────────────────────────────────────────────────────────────

echo ""
echo "== is_eeprom_path =="

check_eeprom() {
    local f="$1" expected_rc="$2" label="$3"
    is_eeprom_path "$f"
    local rc=$?
    if [[ "$rc" -eq "$expected_rc" ]]; then
        ok "is_eeprom_path($label): rc=$rc"
    else
        fail "is_eeprom_path($label): expected rc=$expected_rc, got $rc"
    fi
}

check_eeprom "/var/run/hw-management/eeprom/eeprom_system"  0 "path under eeprom/"
check_eeprom "/var/run/hw-management/eeprom/eeprom_bmc"     0 "eeprom_bmc under eeprom/"
check_eeprom "/sys/bus/i2c/devices/0-0050/eeprom"           0 "sysfs eeprom node"
check_eeprom "/var/run/hw-management/eeprom"                0 "bare .../eeprom path"
check_eeprom "/var/run/hw-management/eeprom_system"         0 "eeprom_* basename"
check_eeprom "/var/run/hw-management/eeprom_bmc"            0 "eeprom_bmc basename"
check_eeprom "/var/run/hw-management/thermal/cpu_temp"      1 "thermal path"
check_eeprom "/var/run/hw-management/system/fan1_speed"     1 "system path"
check_eeprom "/var/run/hw-management/bmc/reset_power_on"    1 "bmc reset file"
check_eeprom "/tmp/debug.log"                               1 "unrelated path"

# ── readlink_canonical ────────────────────────────────────────────────────────

echo ""
echo "== readlink_canonical =="

REAL_FILE="$WORK/canon_test.txt"
echo "content" >"$REAL_FILE"

canon=$(readlink_canonical "$REAL_FILE")
if [[ -n "$canon" ]]; then
    ok "readlink_canonical(existing file): returned '$canon'"
    if [[ -f "$canon" ]]; then
        ok "readlink_canonical: returned path resolves to a real file"
    else
        warn "readlink_canonical: returned path not accessible (realpath/readlink -f may be unavailable)"
    fi
else
    warn "readlink_canonical returned empty (realpath/readlink -f unavailable?)"
fi

# ── patched script for invocation tests ──────────────────────────────────────
# Stub helpers-common so log_message is available without the real install.

STUB_HELPERS="$WORK/hw-management-bmc-helpers-common.sh"
cat >"$STUB_HELPERS" <<'HELPERS'
#!/bin/bash
log_message() { echo "[$1] $2" >&2; }
HELPERS

PATCHED_RUN="$WORK/gen_dump_run.sh"
sed "s|source /usr/bin/hw-management-bmc-helpers-common.sh|source ${STUB_HELPERS}|g" \
    "$GEN_DUMP_SCRIPT" >"$PATCHED_RUN"
chmod +x "$PATCHED_RUN"

# ── parse_args: -h exits 0 ────────────────────────────────────────────────────

echo ""
echo "== parse_args: -h exits 0 and prints usage =="

help_out=$(bash "$PATCHED_RUN" -h 2>&1)
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "parse_args -h: exits 0"
else
    fail "parse_args -h: exits $rc (expected 0)"
fi
if echo "$help_out" | grep -qi "usage\|collect\|output\|-v"; then
    ok "parse_args -h: output contains usage info"
else
    fail "parse_args -h: output missing usage info (got: $(echo "$help_out" | head -1))"
fi

# ── parse_args: unknown option exits 1 ───────────────────────────────────────

echo ""
echo "== parse_args: unknown option exits 1 =="

bash "$PATCHED_RUN" --unknown-option-xyz >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "parse_args unknown option: exits 1"
else
    fail "parse_args unknown option: exits $rc (expected 1)"
fi

# ── parse_args: -v and positional arg ────────────────────────────────────────

echo ""
echo "== parse_args: -v sets VERBOSE; positional sets OUTPUT_TAR =="

# Call parse_args in an isolated subshell by sourcing the function definition
# from the script (extract just the function block, not the full script).
parse_args_result=$(bash -c "
$(grep -A 50 '^parse_args()' "$GEN_DUMP_SCRIPT" | awk '/^parse_args\(\)/{found=1} found{print} /^}$/ && found{exit}')
VERBOSE=0
OUTPUT_TAR='/tmp/default.tar.gz'
parse_args -v '/tmp/custom_output.tar.gz'
echo \"VERBOSE=\$VERBOSE OUTPUT_TAR=\$OUTPUT_TAR\"
" 2>/dev/null)

if echo "$parse_args_result" | grep -q "VERBOSE=1"; then
    ok "parse_args -v: VERBOSE=1"
else
    fail "parse_args -v: expected VERBOSE=1, got: $parse_args_result"
fi
if echo "$parse_args_result" | grep -q "OUTPUT_TAR=/tmp/custom_output.tar.gz"; then
    ok "parse_args positional: OUTPUT_TAR=/tmp/custom_output.tar.gz"
else
    fail "parse_args positional: expected custom tar path, got: $parse_args_result"
fi

# -v alone should leave OUTPUT_TAR at its default.
verbose_only=$(bash -c "
$(grep -A 50 '^parse_args()' "$GEN_DUMP_SCRIPT" | awk '/^parse_args\(\)/{found=1} found{print} /^}$/ && found{exit}')
VERBOSE=0
OUTPUT_TAR='/tmp/default.tar.gz'
parse_args -v
echo \"VERBOSE=\$VERBOSE OUTPUT_TAR=\$OUTPUT_TAR\"
" 2>/dev/null)

if echo "$verbose_only" | grep -q "OUTPUT_TAR=/tmp/default.tar.gz"; then
    ok "parse_args -v only: OUTPUT_TAR unchanged"
else
    fail "parse_args -v only: OUTPUT_TAR should stay default, got: $verbose_only"
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
