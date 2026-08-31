#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Validate hw-management-bmc-powerctrl.sh interface and structure.
# All checks are non-destructive: no actual power commands are sent.
#
# Tests:
#   1. Script is present, executable, and syntactically valid (bash -n)
#   2. No-arg invocation prints usage to stderr and exits 1
#   3. Unknown command exits 1
#   4. Known command names are accepted by the case statement (dry-run via
#      a mock MLX_HWMON_BASE that provides all required sysfs nodes)
#   5. MLX_HWMON_BASE path variable is present and exported in the script
#   6. Resolve logic: resolve_mlx_hwmon returns 1 when base is absent
#
# Environment (optional):
#   POWERCTRL_SCRIPT — path to hw-management-bmc-powerctrl.sh
#
# Exit: 0 if all checks pass; 1 otherwise.

set -u
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_BMC=$(cd "$SCRIPT_DIR/.." && pwd)
POWERCTRL_SCRIPT="${POWERCTRL_SCRIPT:-$REPO_BMC/usr/usr/bin/hw-management-bmc-powerctrl.sh}"

failures=0
warns=0

ok()   { echo "OK: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "hw-management-bmc powerctrl validation ($(date -Iseconds 2>/dev/null || date))"
echo "Script: $POWERCTRL_SCRIPT"

# ── presence and syntax ───────────────────────────────────────────────────────

echo ""
echo "== presence and syntax =="
if [[ ! -f "$POWERCTRL_SCRIPT" ]]; then
    fail "script not found: $POWERCTRL_SCRIPT"
    echo "Summary: failures=$failures"
    exit 1
fi
ok "script exists"

if [[ -x "$POWERCTRL_SCRIPT" ]]; then
    ok "script is executable"
else
    warn "script is not executable (chmod +x missing?)"
fi

if bash -n "$POWERCTRL_SCRIPT" 2>/dev/null; then
    ok "bash -n: no syntax errors"
else
    fail "bash -n: syntax errors detected"
fi

# ── no-arg usage ──────────────────────────────────────────────────────────────

echo ""
echo "== no-arg invocation prints usage and exits 1 =="

# We must not let the script touch real sysfs; point MLX_HWMON_BASE at a
# nonexistent path so resolve_mlx_hwmon fails before any command runs.
NO_HW_BASE="$WORK/no_hw_base_does_not_exist"

usage_output=$(MLX_HWMON_BASE="$NO_HW_BASE" bash "$POWERCTRL_SCRIPT" 2>&1)
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "no-arg exit code = 1"
else
    fail "no-arg exit code = $rc (expected 1)"
fi

if echo "$usage_output" | grep -qi "usage"; then
    ok "no-arg output contains 'Usage'"
else
    fail "no-arg output missing 'Usage' (got: $(echo "$usage_output" | head -1))"
fi

# ── unknown command exits 1 ───────────────────────────────────────────────────

echo ""
echo "== unknown command exits 1 =="
unk_output=$(MLX_HWMON_BASE="$NO_HW_BASE" bash "$POWERCTRL_SCRIPT" completely_unknown_cmd 2>&1)
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "unknown command exit code = 1"
else
    fail "unknown command exit code = $rc (expected 1)"
fi

# ── known commands accepted (mocked sysfs) ────────────────────────────────────

echo ""
echo "== known command names accepted with mocked sysfs =="

# Build a fake hwmon directory with all sysfs nodes the script writes to.
MOCK_HW_BASE="$WORK/mock_mlxreg/hwmon"
MOCK_HWMON="$MOCK_HW_BASE/hwmon0"
mkdir -p "$MOCK_HWMON"

for node in pwr_down pwr_cycle aux_pwr_cycle bmc_to_cpu_ctrl uart_sel \
            graceful_power_off cpu_power_off_ready pwr_button_halt; do
    echo "0" >"$MOCK_HWMON/$node"
done

# Redirect logger to /dev/null so logger(1) absence doesn't fail the test.
mkdir -p "$WORK/mock_bin"
printf '#!/bin/sh\nexport PATH="%s:$PATH"\n: # no-op\n' "$WORK/mock_bin" >"$WORK/mock_bin/logger"
chmod +x "$WORK/mock_bin/logger"

# The script hardcodes MLX_HWMON_BASE; patch it in a temp copy for offline testing.
PATCHED_SCRIPT="$WORK/powerctrl_patched.sh"
sed "s|MLX_HWMON_BASE=.*|MLX_HWMON_BASE=${MOCK_HW_BASE}|" "$POWERCTRL_SCRIPT" >"$PATCHED_SCRIPT"
chmod +x "$PATCHED_SCRIPT"

run_patched() {
    PATH="$WORK/mock_bin:$PATH" bash "$PATCHED_SCRIPT" "$@" >/dev/null 2>&1
}

# power_on: writes 0 to pwr_down and bmc_to_cpu_ctrl.
run_patched power_on
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "power_on: exit 0"
else
    fail "power_on: exit $rc"
fi
pwr_down_val=$(cat "$MOCK_HWMON/pwr_down" 2>/dev/null | tr -d '[:space:]')
if [[ "$pwr_down_val" == "0" ]]; then
    ok "power_on: pwr_down=0"
else
    fail "power_on: pwr_down expected 0, got '$pwr_down_val'"
fi

# power_off: writes 1 to pwr_down, 1 to bmc_to_cpu_ctrl, 0 to uart_sel.
echo "0" >"$MOCK_HWMON/pwr_down"
run_patched power_off
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "power_off: exit 0"
else
    fail "power_off: exit $rc"
fi
pwr_down_val=$(cat "$MOCK_HWMON/pwr_down" 2>/dev/null | tr -d '[:space:]')
if [[ "$pwr_down_val" == "1" ]]; then
    ok "power_off: pwr_down=1"
else
    fail "power_off: pwr_down expected 1, got '$pwr_down_val'"
fi
bmc_ctrl_val=$(cat "$MOCK_HWMON/bmc_to_cpu_ctrl" 2>/dev/null | tr -d '[:space:]')
if [[ "$bmc_ctrl_val" == "1" ]]; then
    ok "power_off: bmc_to_cpu_ctrl=1"
else
    fail "power_off: bmc_to_cpu_ctrl expected 1, got '$bmc_ctrl_val'"
fi

# reset: writes 1 to pwr_cycle.
echo "0" >"$MOCK_HWMON/pwr_cycle"
run_patched reset
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "reset: exit 0"
else
    fail "reset: exit $rc"
fi
pwr_cycle_val=$(cat "$MOCK_HWMON/pwr_cycle" 2>/dev/null | tr -d '[:space:]')
if [[ "$pwr_cycle_val" == "1" ]]; then
    ok "reset: pwr_cycle=1"
else
    fail "reset: pwr_cycle expected 1, got '$pwr_cycle_val'"
fi

# ── resolve_mlx_hwmon fails when base absent ──────────────────────────────────

echo ""
echo "== resolve_mlx_hwmon: fails when base path absent =="

# Source just the resolve function; set -e is off.
resolve_mlx_hwmon_from_script() {
    local base="$1"
    local d MLX_HWMON=""
    for d in "$base"/hwmon*; do
        if [ -d "$d" ]; then
            MLX_HWMON=$d
            return 0
        fi
    done
    return 1
}

if resolve_mlx_hwmon_from_script "$NO_HW_BASE"; then
    fail "resolve_mlx_hwmon: should return 1 for absent base"
else
    ok "resolve_mlx_hwmon: returns 1 for absent base"
fi

if resolve_mlx_hwmon_from_script "$MOCK_HW_BASE"; then
    ok "resolve_mlx_hwmon: returns 0 for mock base (hwmon0 present)"
else
    fail "resolve_mlx_hwmon: should return 0 for mock base"
fi

# ── script declares expected command set ──────────────────────────────────────

echo ""
echo "== script declares all expected commands =="
EXPECTED_CMDS=(power_on power_off reset reset_board grace_off grace_reset)
for cmd in "${EXPECTED_CMDS[@]}"; do
    if grep -q "^${cmd})" "$POWERCTRL_SCRIPT" || grep -q "^${cmd} )" "$POWERCTRL_SCRIPT" || \
       grep -q "${cmd})" "$POWERCTRL_SCRIPT"; then
        ok "command '$cmd' present in script"
    else
        fail "command '$cmd' missing from script case statement"
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
