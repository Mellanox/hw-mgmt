#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Validate hw-management-bmc-boot-complete.sh offline.
# All tests use tmpdir conf + mock hw-management directories;
# no real /var/run/hw-management paths are touched.
#
# Tests:
#   1. Script presence, executable, syntax (bash -n)
#   2. count_entries: nonexistent dir → 0
#   3. count_entries: empty dir → 0
#   4. count_entries: dir with N files → N
#   5. Missing conf: exits 1
#   6. Conf with missing required variable: exits non-zero
#   7. Thresholds all 0: exits 0 immediately (no sleep)
#   8. Thresholds met by populated dirs: exits 0 immediately
#   9. Timeout (max_wait=2, poll=1): exits 1 after ~2 s
#
# Environment (optional):
#   BOOT_COMPLETE_SCRIPT — path to hw-management-bmc-boot-complete.sh
#
# Exit: 0 if all checks pass; 1 otherwise.

set -u
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_BMC=$(cd "$SCRIPT_DIR/.." && pwd)
BOOT_SCRIPT="${BOOT_COMPLETE_SCRIPT:-$REPO_BMC/usr/usr/bin/hw-management-bmc-boot-complete.sh}"

failures=0
warns=0

ok()   { echo "OK: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "hw-management-bmc boot-complete validation ($(date -Iseconds 2>/dev/null || date))"
echo "Script: $BOOT_SCRIPT"

# ── presence and syntax ──────────────────────────────────────────────────────

echo ""
echo "== presence and syntax =="

if [[ ! -f "$BOOT_SCRIPT" ]]; then
    fail "script not found: $BOOT_SCRIPT"
    echo "Summary: failures=$failures"
    exit 1
fi
ok "script exists"

if [[ -x "$BOOT_SCRIPT" ]]; then
    ok "script is executable"
else
    warn "script is not executable (chmod +x missing?)"
fi

if bash -n "$BOOT_SCRIPT" 2>/dev/null; then
    ok "bash -n: no syntax errors"
else
    fail "bash -n: syntax errors detected"
fi

# ── count_entries (inline unit tests) ────────────────────────────────────────

echo ""
echo "== count_entries (inline unit tests) =="

count_entries() {
    _d="$1"
    if [ ! -d "$_d" ]; then
        echo 0
        return
    fi
    ls -A "$_d" 2>/dev/null | wc -l
}

NON_EXIST="$WORK/does_not_exist_xyz"
EMPTY_DIR="$WORK/empty"
POPULATED="$WORK/populated"
mkdir -p "$EMPTY_DIR" "$POPULATED"
touch "$POPULATED/a" "$POPULATED/b" "$POPULATED/c"

ce=$(count_entries "$NON_EXIST" | tr -d '[:space:]')
if [[ "$ce" -eq 0 ]]; then
    ok "count_entries(nonexistent dir): 0"
else
    fail "count_entries(nonexistent dir): expected 0, got $ce"
fi

ce=$(count_entries "$EMPTY_DIR" | tr -d '[:space:]')
if [[ "$ce" -eq 0 ]]; then
    ok "count_entries(empty dir): 0"
else
    fail "count_entries(empty dir): expected 0, got $ce"
fi

ce=$(count_entries "$POPULATED" | tr -d '[:space:]')
if [[ "$ce" -eq 3 ]]; then
    ok "count_entries(3 files): 3"
else
    fail "count_entries(3 files): expected 3, got $ce"
fi

# ── missing conf → exit 1 ────────────────────────────────────────────────────

echo ""
echo "== missing conf: exits 1 =="

BOOT_COMPLETE_CONF="$WORK/nonexistent.conf" sh "$BOOT_SCRIPT" >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "missing conf exits 1"
else
    fail "missing conf exits $rc (expected 1)"
fi

# ── conf with missing required variable → non-zero ───────────────────────────

echo ""
echo "== conf missing required variable: exits non-zero =="

CONF_PARTIAL="$WORK/partial.conf"
echo "SYSFS_SYSTEM_COUNTER=5" >"$CONF_PARTIAL"
# SYSFS_THERMAL_COUNTER and SYSFS_EEPROM_COUNTER intentionally omitted.

BOOT_COMPLETE_CONF="$CONF_PARTIAL" sh "$BOOT_SCRIPT" >/dev/null 2>&1
rc=$?
if [[ "$rc" -ne 0 ]]; then
    ok "conf with missing required var exits non-zero ($rc)"
else
    fail "conf with missing required var should exit non-zero, got 0"
fi

# ── thresholds all 0: exits 0 immediately ────────────────────────────────────

echo ""
echo "== thresholds all 0: exits 0 immediately =="

CONF_ZERO="$WORK/zero.conf"
cat >"$CONF_ZERO" <<'CONF'
SYSFS_SYSTEM_COUNTER=0
SYSFS_THERMAL_COUNTER=0
SYSFS_EEPROM_COUNTER=0
CONF

# count_entries on any dir returns 0, which satisfies >= 0 for all thresholds.
BOOT_COMPLETE_CONF="$CONF_ZERO" sh "$BOOT_SCRIPT" >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "thresholds=0: exits 0 immediately"
else
    fail "thresholds=0: exits $rc (expected 0)"
fi

# ── thresholds met by populated dirs: exits 0 ────────────────────────────────

echo ""
echo "== thresholds met by populated dirs: exits 0 =="

CONF_MET="$WORK/met.conf"
cat >"$CONF_MET" <<'CONF'
SYSFS_SYSTEM_COUNTER=2
SYSFS_THERMAL_COUNTER=1
SYSFS_EEPROM_COUNTER=3
CONF

SYS_DIR_MET="$WORK/met_sys"
THR_DIR_MET="$WORK/met_thr"
EEP_DIR_MET="$WORK/met_eep"
mkdir -p "$SYS_DIR_MET" "$THR_DIR_MET" "$EEP_DIR_MET"
touch "$SYS_DIR_MET/a" "$SYS_DIR_MET/b"                         # 2 >= 2 ✓
touch "$THR_DIR_MET/a"                                           # 1 >= 1 ✓
touch "$EEP_DIR_MET/a" "$EEP_DIR_MET/b" "$EEP_DIR_MET/c"        # 3 >= 3 ✓

# Patch the hardcoded SYS_DIR/THERMAL_DIR/EEPROM_DIR assignments.
PATCHED_BOOT="$WORK/boot_patched.sh"
sed \
    "s|SYS_DIR=/var/run/hw-management/system|SYS_DIR=${SYS_DIR_MET}|g; \
     s|THERMAL_DIR=/var/run/hw-management/thermal|THERMAL_DIR=${THR_DIR_MET}|g; \
     s|EEPROM_DIR=/var/run/hw-management/eeprom|EEPROM_DIR=${EEP_DIR_MET}|g" \
    "$BOOT_SCRIPT" >"$PATCHED_BOOT"
chmod +x "$PATCHED_BOOT"

BOOT_COMPLETE_CONF="$CONF_MET" sh "$PATCHED_BOOT" >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "thresholds met: exits 0"
else
    fail "thresholds met: exits $rc (expected 0)"
fi

# ── thresholds not met + timeout: exits 1 ────────────────────────────────────

echo ""
echo "== timeout (max_wait=2 poll=1 thresholds=999): exits 1 =="

CONF_TIMEOUT="$WORK/timeout.conf"
cat >"$CONF_TIMEOUT" <<'CONF'
SYSFS_SYSTEM_COUNTER=999
SYSFS_THERMAL_COUNTER=999
SYSFS_EEPROM_COUNTER=999
BOOT_COMPLETE_MAX_WAIT_SEC=2
BOOT_COMPLETE_POLL_SEC=1
CONF

# The patched dirs still have their 2/1/3 files, all far below 999.
BOOT_COMPLETE_CONF="$CONF_TIMEOUT" sh "$PATCHED_BOOT" >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "timeout: exits 1 after max_wait exceeded"
else
    fail "timeout: exits $rc (expected 1)"
fi

# ── conf output message contains threshold info ───────────────────────────────

echo ""
echo "== progress message format on stdout/stderr =="

# Use zero thresholds so it exits immediately and we can capture the message.
msg_out=$(BOOT_COMPLETE_CONF="$CONF_ZERO" sh "$BOOT_SCRIPT" 2>&1)
if echo "$msg_out" | grep -qi "thresholds met\|system=\|thermal=\|eeprom="; then
    ok "progress message contains threshold info"
else
    warn "progress message format unexpected: $(echo "$msg_out" | head -1)"
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
