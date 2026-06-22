#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Validate hw-management-bmc-cpld-dump.sh offline.
# cpld_format_byte is reproduced inline for unit tests.  A patched copy
# of the script with a stub helpers-common is used for arg-parsing and
# full-dump tests.
#
# Tests:
#   1. Script presence, executable, syntax (bash -n)
#   2. cpld_format_byte: 0xHH → lowercase 2-digit hex
#   3. cpld_format_byte: *ER* → "ER", *NA* → "NA"
#   4. cpld_format_byte: leading/trailing whitespace stripped before matching
#   5. cpld_format_byte: unrecognised token (single digit, long hex, garbage) → "--"
#   6. No-arg invocation: exits 1 + includes usage hint
#   7. -h: exits 0
#   8. Missing -p (only -i given): exits 1
#   9. Full dump with mocked i2ctransfer: .tar.xz created, grid header + byte values present
#
# Environment (optional):
#   CPLD_DUMP_SCRIPT — path to hw-management-bmc-cpld-dump.sh
#
# Exit: 0 if all checks pass; 1 otherwise.

set -u
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_BMC=$(cd "$SCRIPT_DIR/.." && pwd)
CPLD_DUMP_SCRIPT="${CPLD_DUMP_SCRIPT:-$REPO_BMC/usr/usr/bin/hw-management-bmc-cpld-dump.sh}"

failures=0
warns=0

ok()   { echo "OK: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "hw-management-bmc cpld-dump validation ($(date -Iseconds 2>/dev/null || date))"
echo "Script: $CPLD_DUMP_SCRIPT"

# ── presence and syntax ──────────────────────────────────────────────────────

echo ""
echo "== presence and syntax =="

if [[ ! -f "$CPLD_DUMP_SCRIPT" ]]; then
    fail "script not found: $CPLD_DUMP_SCRIPT"
    echo "Summary: failures=$failures"
    exit 1
fi
ok "script exists"

if [[ -x "$CPLD_DUMP_SCRIPT" ]]; then
    ok "script is executable"
else
    warn "script is not executable (chmod +x missing?)"
fi

if bash -n "$CPLD_DUMP_SCRIPT" 2>/dev/null; then
    ok "bash -n: no syntax errors"
else
    fail "bash -n: syntax errors detected"
fi

# ── cpld_format_byte unit tests (inline reproduction) ────────────────────────

echo ""
echo "== cpld_format_byte (inline unit tests) =="

cpld_format_byte()
{
    local raw=$1
    local b

    raw=${raw#"${raw%%[![:space:]]*}"}
    raw=${raw%"${raw##*[![:space:]]}"}

    case "$raw" in
    0x* | 0X*)
        b=${raw#0x}
        b=${b#0X}
        b=${b,,}
        if [[ $b =~ ^[0-9a-f]{2}$ ]]; then
            printf '%s' "$b"
            return 0
        fi
        ;;
    *ER*)
        printf 'ER'
        return 0
        ;;
    *NA*)
        printf 'NA'
        return 0
        ;;
    esac
    printf '%s' '--'
}

check_format_byte() {
    local input="$1" expected="$2" label="$3"
    local result
    result=$(cpld_format_byte "$input")
    if [[ "$result" == "$expected" ]]; then
        ok "cpld_format_byte($label): '$result'"
    else
        fail "cpld_format_byte($label): expected '$expected', got '$result'"
    fi
}

check_format_byte "0x1a"      "1a"  "lowercase hex"
check_format_byte "0x1A"      "1a"  "uppercase hex → lowercase"
check_format_byte "0xAB"      "ab"  "0xAB → ab"
check_format_byte "0x00"      "00"  "zero byte"
check_format_byte "0xFF"      "ff"  "0xFF → ff"
check_format_byte "0X2b"      "2b"  "0X prefix"
check_format_byte " 0x3c "    "3c"  "leading/trailing whitespace stripped"
check_format_byte "	0xde	" "de"  "tab whitespace stripped"
check_format_byte "ERROR"     "ER"  "ERROR token → ER"
check_format_byte "ER"        "ER"  "bare ER passthrough"
check_format_byte "i2cERROR"  "ER"  "*ER* substring"
check_format_byte "NACK"      "NA"  "NACK → NA (contains NA)"
check_format_byte "NA"        "NA"  "bare NA passthrough"
check_format_byte "0x1"       "--"  "single hex digit → --"
check_format_byte "0x1abc"    "--"  "four hex digits → --"
check_format_byte "garbage"   "--"  "non-hex garbage → --"
check_format_byte ""          "--"  "empty string → --"
check_format_byte "0xGG"      "--"  "invalid hex chars → --"
check_format_byte "0x"        "--"  "bare 0x prefix → --"

# ── patched script setup ──────────────────────────────────────────────────────
# Stub out helpers-common so log_message is available without the real install.

STUB_HELPERS="$WORK/hw-management-bmc-helpers-common.sh"
cat >"$STUB_HELPERS" <<'HELPERS'
#!/bin/bash
log_message() { echo "[$1] $2" >&2; }
HELPERS

PATCHED_SCRIPT="$WORK/cpld_dump_patched.sh"
sed "s|source /usr/bin/hw-management-bmc-helpers-common.sh|source ${STUB_HELPERS}|g" \
    "$CPLD_DUMP_SCRIPT" >"$PATCHED_SCRIPT"
chmod +x "$PATCHED_SCRIPT"

# ── no-arg invocation exits 1 ────────────────────────────────────────────────

echo ""
echo "== no-arg invocation: exits 1 + usage hint =="

no_arg_out=$(bash "$PATCHED_SCRIPT" 2>&1)
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "no-arg exit code = 1"
else
    fail "no-arg exit code = $rc (expected 1)"
fi
if echo "$no_arg_out" | grep -qi "usage\|help\|-p"; then
    ok "no-arg output includes usage hint"
else
    fail "no-arg output missing usage hint (got: $(echo "$no_arg_out" | head -1))"
fi

# ── -h exits 0 ───────────────────────────────────────────────────────────────

echo ""
echo "== -h: exits 0 =="

bash "$PATCHED_SCRIPT" -h >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "-h exit code = 0"
else
    fail "-h exit code = $rc (expected 0)"
fi

# ── missing -p exits 1 ───────────────────────────────────────────────────────

echo ""
echo "== missing -p argument: exits 1 =="

bash "$PATCHED_SCRIPT" -i 42 >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "missing -p exit code = 1"
else
    fail "missing -p exit code = $rc (expected 1)"
fi

# ── full dump with mocked i2ctransfer ─────────────────────────────────────────

echo ""
echo "== full dump with mocked i2ctransfer =="

MOCK_BIN="$WORK/mock_bin"
mkdir -p "$MOCK_BIN"

# Return a fixed byte for every register read so output is deterministic.
cat >"$MOCK_BIN/i2ctransfer" <<'SHIM'
#!/bin/sh
echo "0x42"
SHIM
chmod +x "$MOCK_BIN/i2ctransfer"

DUMP_DEST="$WORK/dump_dest"
mkdir -p "$DUMP_DEST"

PATH="$MOCK_BIN:$PATH" bash "$PATCHED_SCRIPT" -p "$DUMP_DEST" -i "12345678" >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "full dump exits 0"
else
    fail "full dump exits $rc (expected 0)"
fi

# Expect a .tar.xz archive copied to DUMP_DEST.
shopt -s nullglob
tar_files=("$DUMP_DEST"/*.tar.xz)
shopt -u nullglob
if [[ "${#tar_files[@]}" -gt 0 ]] && [[ -f "${tar_files[0]}" ]]; then
    ok "dump archive created: $(basename "${tar_files[0]}")"
    # Verify the archive contains cpld_dump.log with grid header.
    EXTRACT_DIR="$WORK/extracted"
    mkdir -p "$EXTRACT_DIR"
    tar -xJf "${tar_files[0]}" -C "$EXTRACT_DIR" 2>/dev/null
    cpld_log=$(find "$EXTRACT_DIR" -name "cpld_dump.log" 2>/dev/null | head -1)
    if [[ -f "$cpld_log" ]]; then
        ok "cpld_dump.log found in archive"
        if grep -q "^Offset" "$cpld_log"; then
            ok "cpld_dump.log contains grid header 'Offset'"
        else
            fail "cpld_dump.log missing grid header 'Offset'"
        fi
        if grep -q "^0x00:" "$cpld_log"; then
            ok "cpld_dump.log contains row 0x00:"
        else
            fail "cpld_dump.log missing first data row 0x00:"
        fi
        if grep -q "42" "$cpld_log"; then
            ok "cpld_dump.log contains mocked byte value '42'"
        else
            fail "cpld_dump.log does not contain expected mocked value '42'"
        fi
    else
        warn "cpld_dump.log not found in extracted archive"
    fi
else
    fail "no .tar.xz archive found in $DUMP_DEST"
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
