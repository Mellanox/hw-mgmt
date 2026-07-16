#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Validate hw-management-bmc-show-reset-cause.sh offline.
# Uses tmpdir fixtures for all directory lookups; no real hw-management
# paths are touched.
#
# Tests:
#   1. Script presence, executable, syntax (bash -n)
#   2. --help / -h: prints usage, exits 0
#   3. Unknown section: exits 1
#   4. No-arg run with empty dirs: exits 0
#   5. emit_active_reset_basenames: missing dir → "directory missing" diagnostic
#   6. emit_active_reset_basenames: no reset_* files → diagnostic message
#   7. emit_active_reset_basenames: only files with value=1 are listed
#   8. bmc section: all-zero files → "no reset_* with value 1" diagnostic
#   9. bmc-raw section: raw_scu* values printed correctly
#  10. bmc-domain section: active resets listed, inactive suppressed
#  11. host section: host-specific diagnostic when no reset_* files
#  12. Full multi-section run with fixture data: exits 0, all headers present
#
# Environment (optional):
#   SHOW_RESET_CAUSE_SCRIPT — path to hw-management-bmc-show-reset-cause.sh
#
# Exit: 0 if all checks pass; 1 otherwise.

set -u
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_BMC=$(cd "$SCRIPT_DIR/.." && pwd)
SHOW_SCRIPT="${SHOW_RESET_CAUSE_SCRIPT:-$REPO_BMC/usr/usr/bin/hw-management-bmc-show-reset-cause.sh}"

failures=0
warns=0

ok()   { echo "OK: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "hw-management-bmc show-reset-cause validation ($(date -Iseconds 2>/dev/null || date))"
echo "Script: $SHOW_SCRIPT"

# ── presence and syntax ──────────────────────────────────────────────────────

echo ""
echo "== presence and syntax =="

if [[ ! -f "$SHOW_SCRIPT" ]]; then
    fail "script not found: $SHOW_SCRIPT"
    echo "Summary: failures=$failures"
    exit 1
fi
ok "script exists"

if [[ -x "$SHOW_SCRIPT" ]]; then
    ok "script is executable"
else
    warn "script is not executable (chmod +x missing?)"
fi

if bash -n "$SHOW_SCRIPT" 2>/dev/null; then
    ok "bash -n: no syntax errors"
else
    fail "bash -n: syntax errors detected"
fi

# ── help flag ────────────────────────────────────────────────────────────────

echo ""
echo "== --help / -h: exits 0 and prints usage =="

help_out=$(sh "$SHOW_SCRIPT" --help 2>&1)
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "--help exit code = 0"
else
    fail "--help exit code = $rc (expected 0)"
fi
if echo "$help_out" | grep -qi "usage"; then
    ok "--help output contains 'Usage'"
else
    fail "--help output missing 'Usage' (got: $(echo "$help_out" | head -1))"
fi

sh "$SHOW_SCRIPT" -h >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "-h exit code = 0"
else
    fail "-h exit code = $rc (expected 0)"
fi

# ── unknown section exits 1 ──────────────────────────────────────────────────

echo ""
echo "== unknown section exits 1 =="

sh "$SHOW_SCRIPT" totally_unknown_section >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "unknown section exit code = 1"
else
    fail "unknown section exit code = $rc (expected 1)"
fi

# ── no-arg run with empty dirs exits 0 ───────────────────────────────────────

echo ""
echo "== no-arg run with empty dirs exits 0 =="

EMPTY_BMC="$WORK/empty_bmc"
EMPTY_HOST="$WORK/empty_host"
EMPTY_DOMAINS="$WORK/empty_domains"
mkdir -p "$EMPTY_BMC" "$EMPTY_HOST" "$EMPTY_DOMAINS"

BMC_DIR="$EMPTY_BMC" BMC_DOMAINS_DIR="$EMPTY_DOMAINS" HOST_SYSTEM_DIR="$EMPTY_HOST" \
    sh "$SHOW_SCRIPT" >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "no-arg run (empty dirs) exits 0"
else
    fail "no-arg run exits $rc (expected 0)"
fi

# ── missing directory diagnostic ─────────────────────────────────────────────

echo ""
echo "== missing directory → 'directory missing' diagnostic =="

out=$(BMC_DIR="$WORK/does_not_exist" BMC_DOMAINS_DIR="$WORK/x" HOST_SYSTEM_DIR="$WORK/y" \
    sh "$SHOW_SCRIPT" bmc 2>&1)
if echo "$out" | grep -q "directory missing"; then
    ok "bmc section: 'directory missing' diagnostic for absent dir"
else
    fail "bmc section: expected 'directory missing', got: $(echo "$out" | head -1)"
fi

# ── no reset_* files diagnostic ──────────────────────────────────────────────

echo ""
echo "== no reset_* files → diagnostic =="

BMC_NOFILES="$WORK/bmc_nofiles"
mkdir -p "$BMC_NOFILES"
touch "$BMC_NOFILES/other_file"   # non-reset_ file should be ignored

out=$(BMC_DIR="$BMC_NOFILES" BMC_DOMAINS_DIR="$WORK/x" HOST_SYSTEM_DIR="$WORK/y" \
    sh "$SHOW_SCRIPT" bmc 2>&1)
if echo "$out" | grep -q "no reset_\* files"; then
    ok "bmc section: 'no reset_* files' diagnostic when dir has no reset_* files"
else
    fail "bmc section: expected 'no reset_* files' diagnostic, got: $(echo "$out" | head -2)"
fi

# ── only value=1 files are listed ────────────────────────────────────────────

echo ""
echo "== only reset_* files with value=1 are listed =="

BMC_DATA="$WORK/bmc_data"
mkdir -p "$BMC_DATA"
echo "1" >"$BMC_DATA/reset_power_on"
echo "0" >"$BMC_DATA/reset_watchdog"
echo "1" >"$BMC_DATA/reset_software"
echo "0" >"$BMC_DATA/reset_cpu"

out=$(BMC_DIR="$BMC_DATA" BMC_DOMAINS_DIR="$WORK/x" HOST_SYSTEM_DIR="$WORK/y" \
    sh "$SHOW_SCRIPT" bmc 2>&1)

if echo "$out" | grep -q "reset_power_on"; then
    ok "bmc section: reset_power_on (value=1) listed"
else
    fail "bmc section: reset_power_on (value=1) missing from output"
fi
if echo "$out" | grep -q "reset_software"; then
    ok "bmc section: reset_software (value=1) listed"
else
    fail "bmc section: reset_software (value=1) missing from output"
fi
if echo "$out" | grep -q "reset_watchdog"; then
    fail "bmc section: reset_watchdog (value=0) should NOT appear in output"
else
    ok "bmc section: reset_watchdog (value=0) correctly suppressed"
fi
if echo "$out" | grep -q "reset_cpu"; then
    fail "bmc section: reset_cpu (value=0) should NOT appear in output"
else
    ok "bmc section: reset_cpu (value=0) correctly suppressed"
fi
if echo "$out" | grep -q "=== bmc"; then
    ok "bmc section: section header present"
else
    fail "bmc section: section header missing"
fi

# ── all-zero files → "no reset_* with value 1" diagnostic ───────────────────

echo ""
echo "== all reset_* files zero → 'no reset_* with value 1' diagnostic =="

BMC_ALL_ZERO="$WORK/bmc_all_zero"
mkdir -p "$BMC_ALL_ZERO"
echo "0" >"$BMC_ALL_ZERO/reset_power_on"
echo "0" >"$BMC_ALL_ZERO/reset_watchdog"

out=$(BMC_DIR="$BMC_ALL_ZERO" BMC_DOMAINS_DIR="$WORK/x" HOST_SYSTEM_DIR="$WORK/y" \
    sh "$SHOW_SCRIPT" bmc 2>&1)
if echo "$out" | grep -q "no reset_\* with value 1"; then
    ok "bmc section: 'no reset_* with value 1' diagnostic when all zeros"
else
    fail "bmc section: expected 'no reset_* with value 1', got: $(echo "$out" | head -2)"
fi

# ── bmc-raw section ───────────────────────────────────────────────────────────

echo ""
echo "== bmc-raw section: raw_scu* values printed =="

BMC_RAW="$WORK/bmc_raw"
mkdir -p "$BMC_RAW"
echo "0x00000800" >"$BMC_RAW/raw_scu0_reset_event_log0"
echo "0x00000000" >"$BMC_RAW/raw_scu0_reset_event_log2"
echo "0x00000800" >"$BMC_RAW/raw_scu1_reset_event_log0"
echo "0x00000000" >"$BMC_RAW/raw_scu1_reset_event_log3"

out=$(BMC_DIR="$BMC_RAW" BMC_DOMAINS_DIR="$WORK/x" HOST_SYSTEM_DIR="$WORK/y" \
    sh "$SHOW_SCRIPT" bmc-raw 2>&1)

if echo "$out" | grep -q "=== bmc-raw"; then
    ok "bmc-raw: section header present"
else
    fail "bmc-raw: section header missing"
fi
for raw_f in raw_scu0_reset_event_log0 raw_scu0_reset_event_log2 \
             raw_scu1_reset_event_log0 raw_scu1_reset_event_log3; do
    if echo "$out" | grep -q "$raw_f"; then
        ok "bmc-raw: $raw_f appears in output"
    else
        fail "bmc-raw: $raw_f missing from output"
    fi
done
if echo "$out" | grep -q "0x00000800"; then
    ok "bmc-raw: raw value '0x00000800' appears in output"
else
    fail "bmc-raw: raw value '0x00000800' missing from output"
fi

# bmc-raw: no raw files → diagnostic
BMC_RAW_EMPTY="$WORK/bmc_raw_empty"
mkdir -p "$BMC_RAW_EMPTY"
out=$(BMC_DIR="$BMC_RAW_EMPTY" BMC_DOMAINS_DIR="$WORK/x" HOST_SYSTEM_DIR="$WORK/y" \
    sh "$SHOW_SCRIPT" bmc-raw 2>&1)
if echo "$out" | grep -q "no raw_scu"; then
    ok "bmc-raw: 'no raw_scu*' diagnostic when no raw files"
else
    fail "bmc-raw: expected 'no raw_scu*' diagnostic, got: $(echo "$out" | head -2)"
fi

# ── bmc-domain section ────────────────────────────────────────────────────────

echo ""
echo "== bmc-domain section: active resets listed, inactive suppressed =="

BMC_DOMAINS="$WORK/bmc_domains"
mkdir -p "$BMC_DOMAINS"
echo "1" >"$BMC_DOMAINS/reset_ahb"
echo "0" >"$BMC_DOMAINS/reset_soc"
echo "1" >"$BMC_DOMAINS/reset_external"

out=$(BMC_DIR="$WORK/x" BMC_DOMAINS_DIR="$BMC_DOMAINS" HOST_SYSTEM_DIR="$WORK/y" \
    sh "$SHOW_SCRIPT" bmc-domain 2>&1)

if echo "$out" | grep -q "=== bmc-domain"; then
    ok "bmc-domain: section header present"
else
    fail "bmc-domain: section header missing"
fi
if echo "$out" | grep -q "reset_ahb"; then
    ok "bmc-domain: reset_ahb (value=1) listed"
else
    fail "bmc-domain: reset_ahb (value=1) missing"
fi
if echo "$out" | grep -q "reset_external"; then
    ok "bmc-domain: reset_external (value=1) listed"
else
    fail "bmc-domain: reset_external (value=1) missing"
fi
if echo "$out" | grep -q "reset_soc"; then
    fail "bmc-domain: reset_soc (value=0) should not appear"
else
    ok "bmc-domain: reset_soc (value=0) correctly suppressed"
fi

# ── host section uses host-specific diagnostic ───────────────────────────────

echo ""
echo "== host section: host-specific diagnostic for missing reset_* =="

HOST_NOFILES="$WORK/host_nofiles"
mkdir -p "$HOST_NOFILES"

out=$(BMC_DIR="$WORK/x" BMC_DOMAINS_DIR="$WORK/y" HOST_SYSTEM_DIR="$HOST_NOFILES" \
    sh "$SHOW_SCRIPT" host 2>&1)
if echo "$out" | grep -q "host reset-cause attributes not present"; then
    ok "host section: host-specific 'not present' diagnostic"
else
    fail "host section: expected host-specific diagnostic, got: $(echo "$out" | head -2)"
fi

# ── full multi-section run ────────────────────────────────────────────────────

echo ""
echo "== full multi-section run with fixture data =="

FULL_BMC="$WORK/full_bmc"
FULL_DOMAINS="$WORK/full_domains"
FULL_HOST="$WORK/full_host"
mkdir -p "$FULL_BMC" "$FULL_DOMAINS" "$FULL_HOST"

echo "1" >"$FULL_BMC/reset_power_on"
echo "0" >"$FULL_BMC/reset_watchdog"
echo "0x00000800" >"$FULL_BMC/raw_scu0_reset_event_log0"
echo "0x00000000" >"$FULL_BMC/raw_scu1_reset_event_log3"
echo "1" >"$FULL_DOMAINS/reset_external"
echo "0" >"$FULL_DOMAINS/reset_soc"

out=$(BMC_DIR="$FULL_BMC" BMC_DOMAINS_DIR="$FULL_DOMAINS" HOST_SYSTEM_DIR="$FULL_HOST" \
    sh "$SHOW_SCRIPT" 2>&1)
rc=$?

if [[ "$rc" -eq 0 ]]; then
    ok "full run: exits 0"
else
    fail "full run: exits $rc (expected 0)"
fi
for hdr in "=== bmc " "=== host " "=== bmc-domain " "=== bmc-raw "; do
    if echo "$out" | grep -q "$hdr"; then
        ok "full run: section header '$hdr' present"
    else
        fail "full run: section header '$hdr' missing"
    fi
done
if echo "$out" | grep -q "reset_power_on"; then
    ok "full run: reset_power_on (value=1) appears in bmc section"
else
    fail "full run: reset_power_on missing from output"
fi
if echo "$out" | grep -q "reset_external"; then
    ok "full run: reset_external (value=1) appears in bmc-domain section"
else
    fail "full run: reset_external missing from output"
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
