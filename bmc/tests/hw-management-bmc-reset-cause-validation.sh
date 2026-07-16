#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Validate hw-management-bmc-get-reset-cause.sh logic offline.
# Uses a tmpdir as OUT_DIR and a mock fw_printenv shim to inject SCU register
# values without hardware.  No devmem access, no root required.
#
# Tests:
#   1. normalize_hex: hex string → integer with 0x/no-prefix variants
#   2. set_reset_file routing: domain names go under domains/, others under OUT_DIR
#   3. Full script run with known SCU values: verify output files exist and have
#      expected 0/1 content for power_on, watchdog, software, external, others
#   4. reset-cause-logger: verify it exits 0 and writes a log file (mocked paths)
#
# Environment (optional):
#   GET_RESET_CAUSE_SCRIPT — path to hw-management-bmc-get-reset-cause.sh
#   LOGGER_SCRIPT          — path to hw-management-bmc-reset-cause-logger.sh
#
# Exit: 0 if all checks pass; 1 otherwise.

set -u
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_BMC=$(cd "$SCRIPT_DIR/.." && pwd)
BIN_DIR="$REPO_BMC/usr/usr/bin"

GET_RESET_CAUSE_SCRIPT="${GET_RESET_CAUSE_SCRIPT:-$BIN_DIR/hw-management-bmc-get-reset-cause.sh}"
LOGGER_SCRIPT="${LOGGER_SCRIPT:-$BIN_DIR/hw-management-bmc-reset-cause-logger.sh}"

failures=0
warns=0

ok()   { echo "OK: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ── helpers ───────────────────────────────────────────────────────────────────

check_file_exists() {
    local f="$1" label="$2"
    if [[ -f "$f" ]]; then
        ok "$label: file exists ($f)"
    else
        fail "$label: missing file ($f)"
    fi
}

check_file_value() {
    local f="$1" expected="$2" label="$3"
    if [[ ! -f "$f" ]]; then
        fail "$label: file missing ($f)"
        return
    fi
    local actual
    actual=$(tr -d '[:space:]' <"$f" 2>/dev/null)
    if [[ "$actual" == "$expected" ]]; then
        ok "$label: value='$actual'"
    else
        fail "$label: expected='$expected' actual='$actual' ($f)"
    fi
}

# ── script presence ───────────────────────────────────────────────────────────

echo "hw-management-bmc reset-cause validation ($(date -Iseconds 2>/dev/null || date))"
echo ""
echo "== script presence =="

if [[ ! -f "$GET_RESET_CAUSE_SCRIPT" ]]; then
    fail "get-reset-cause script not found: $GET_RESET_CAUSE_SCRIPT"
else
    ok "found: $GET_RESET_CAUSE_SCRIPT"
fi

if [[ ! -f "$LOGGER_SCRIPT" ]]; then
    fail "reset-cause-logger not found: $LOGGER_SCRIPT"
else
    ok "found: $LOGGER_SCRIPT"
fi

# ── normalize_hex unit tests (sourced inline) ─────────────────────────────────

echo ""
echo "== normalize_hex (inline unit test) =="

# Reproduce normalize_hex from the script for offline testing.
normalize_hex() {
    local in="$1"
    case "${in}" in
    0x* | 0X*) hex="${in}" ;;
    *) hex="0x${in}" ;;
    esac
    local digits="${hex#0x}"
    digits="${digits#0X}"
    case "${digits}" in
    '' | *[!0-9A-Fa-f]*)
        return 1
        ;;
    esac
    val=$(( hex ))
    return 0
}

run_normalize_hex_test() {
    local input="$1" expected_val="$2" expect_pass="$3" label="$4"
    local val
    if normalize_hex "$input"; then
        if [[ "$expect_pass" == "1" ]]; then
            if [[ "$val" -eq "$expected_val" ]]; then
                ok "normalize_hex($input): val=$val ✓"
            else
                fail "normalize_hex($input): expected $expected_val, got $val"
            fi
        else
            fail "normalize_hex($input): expected failure but passed (val=$val)"
        fi
    else
        if [[ "$expect_pass" == "0" ]]; then
            ok "normalize_hex($input): correctly rejected ($label)"
        else
            fail "normalize_hex($input): expected success but failed"
        fi
    fi
}

run_normalize_hex_test "0x00000800" 2048       1 "0x prefix power_on bit"
run_normalize_hex_test "0x00000001" 1          1 "0x prefix external bit"
run_normalize_hex_test "00000000"   0          1 "no prefix zero"
run_normalize_hex_test "DEADBEEF"   3735928559 1 "no prefix uppercase hex"
run_normalize_hex_test "0xGGGG"     0          0 "invalid hex digits"
run_normalize_hex_test ""           0          0 "empty string"

# ── set_reset_file routing (offline) ─────────────────────────────────────────

echo ""
echo "== set_reset_file routing (offline) =="

OUT_DIR_TEST="$WORK/bmc"
DOMAINS_DIR_TEST="$OUT_DIR_TEST/domains"
mkdir -p "$OUT_DIR_TEST" "$DOMAINS_DIR_TEST"

# Replicate set_reset_file from the script.
set_reset_file_test() {
    local name="$1" value="$2"
    case "${name}" in
    ahb|caliptra|emmc|espi|external|msi|soc|spi|usb)
        echo "${value}" >"${DOMAINS_DIR_TEST}/reset_${name}"
        ;;
    *)
        echo "${value}" >"${OUT_DIR_TEST}/reset_${name}"
        ;;
    esac
}

for domain_name in ahb caliptra emmc espi external msi soc spi usb; do
    set_reset_file_test "$domain_name" "1"
    if [[ -f "${DOMAINS_DIR_TEST}/reset_${domain_name}" ]]; then
        ok "domain '$domain_name' → domains/reset_${domain_name}"
    else
        fail "domain '$domain_name' should go under domains/"
    fi
    if [[ -f "${OUT_DIR_TEST}/reset_${domain_name}" ]]; then
        fail "domain '$domain_name' should NOT be in OUT_DIR root"
    fi
done

for top_name in power_on watchdog software cpu security_watchdog2 others; do
    set_reset_file_test "$top_name" "0"
    if [[ -f "${OUT_DIR_TEST}/reset_${top_name}" ]]; then
        ok "top-level '$top_name' → OUT_DIR/reset_${top_name}"
    else
        fail "top-level '$top_name' should be in OUT_DIR root"
    fi
    if [[ -f "${DOMAINS_DIR_TEST}/reset_${top_name}" ]]; then
        fail "top-level '$top_name' should NOT be under domains/"
    fi
done

# ── full script run with mocked fw_printenv ───────────────────────────────────

echo ""
echo "== full get-reset-cause script run (mocked hw) =="

if [[ ! -f "$GET_RESET_CAUSE_SCRIPT" ]]; then
    warn "skipping full-run test (script missing)"
else
    MOCK_BIN="$WORK/mock_bin"
    mkdir -p "$MOCK_BIN"

    # SCU values chosen so:
    #   power_on = 1  (SCU1_LOG0 bit 11 set)
    #   watchdog = 0  (SCU1_LOG3=0, SCU0_LOG2=0)
    #   software = 0
    #   external = 0
    #   others   = 0  (power_on is set, so others = !(1|0|0|0|0) = 0)
    # SCU0_LOG0 = 0x00000800  → bit 11 → power_on via scu0 path (combined OR)
    # SCU1_LOG0 = 0x00000800  → bit 11 → power_on via scu1 path
    # SCU0_LOG2 = 0x00000000
    # SCU1_LOG3 = 0x00000000

    cat >"$MOCK_BIN/fw_printenv" <<'SHIM'
#!/bin/sh
case "$2" in
reset_cause_scu0_0) echo "0x00000800" ;;
reset_cause_scu0_2) echo "0x00000000" ;;
reset_cause_scu1_0) echo "0x00000800" ;;
reset_cause_scu1_3) echo "0x00000000" ;;
*) exit 1 ;;
esac
SHIM
    chmod +x "$MOCK_BIN/fw_printenv"

    # Disable devmem — should not be called when fw_printenv succeeds.
    cat >"$MOCK_BIN/devmem" <<'SHIM'
#!/bin/sh
echo "MOCK-devmem-should-not-run: $*" >&2
exit 1
SHIM
    chmod +x "$MOCK_BIN/devmem"

    RUN_OUT="$WORK/run_out"
    RUN_DOMAINS="$RUN_OUT/domains"

    PATH="$MOCK_BIN:$PATH" \
    OUT_DIR="$RUN_OUT" \
    DOMAINS_DIR="$RUN_DOMAINS" \
    sh "$GET_RESET_CAUSE_SCRIPT" >/dev/null 2>&1
    rc=$?

    if [[ "$rc" -eq 0 ]]; then
        ok "get-reset-cause script exited 0"
    else
        fail "get-reset-cause script exited $rc"
    fi

    # Verify raw SCU log files.
    for raw_f in raw_scu0_reset_event_log0 raw_scu0_reset_event_log2 \
                 raw_scu1_reset_event_log0 raw_scu1_reset_event_log3; do
        check_file_exists "$RUN_OUT/$raw_f" "$raw_f"
    done

    check_file_value "$RUN_OUT/reset_power_on"          "1" "reset_power_on"
    check_file_value "$RUN_OUT/reset_watchdog"          "0" "reset_watchdog"
    check_file_value "$RUN_OUT/reset_software"          "0" "reset_software"
    check_file_value "$RUN_OUT/reset_cpu"               "0" "reset_cpu"
    check_file_value "$RUN_OUT/reset_security_watchdog2" "0" "reset_security_watchdog2"
    check_file_value "$RUN_OUT/reset_others"            "0" "reset_others"
    check_file_value "$RUN_DOMAINS/reset_external"      "0" "domains/reset_external"
    check_file_value "$RUN_DOMAINS/reset_ahb"           "0" "domains/reset_ahb"
    check_file_value "$RUN_DOMAINS/reset_soc"           "0" "domains/reset_soc"

    # Verify raw word formatting (must be 0x followed by 8 hex digits).
    for raw_f in raw_scu0_reset_event_log0 raw_scu0_reset_event_log2 \
                 raw_scu1_reset_event_log0 raw_scu1_reset_event_log3; do
        v=$(tr -d '[:space:]' <"$RUN_OUT/$raw_f" 2>/dev/null)
        if [[ "$v" =~ ^0x[0-9a-fA-F]{8}$ ]]; then
            ok "$raw_f format: '$v' matches 0x????????"
        else
            fail "$raw_f format: '$v' does not match 0x????????"
        fi
    done

    # Second run: watchdog-only reset (SCU1_LOG3 non-zero WDT SOC nibble, bit 2 set = 0x4).
    cat >"$MOCK_BIN/fw_printenv" <<'SHIM'
#!/bin/sh
case "$2" in
reset_cause_scu0_0) echo "0x00000000" ;;
reset_cause_scu0_2) echo "0x00000000" ;;
reset_cause_scu1_0) echo "0x00000000" ;;
reset_cause_scu1_3) echo "0x00000004" ;;
*) exit 1 ;;
esac
SHIM
    RUN_OUT2="$WORK/run_out2"
    PATH="$MOCK_BIN:$PATH" OUT_DIR="$RUN_OUT2" sh "$GET_RESET_CAUSE_SCRIPT" >/dev/null 2>&1
    check_file_value "$RUN_OUT2/reset_watchdog" "1" "watchdog run: reset_watchdog=1"
    check_file_value "$RUN_OUT2/reset_power_on" "0" "watchdog run: reset_power_on=0"
    check_file_value "$RUN_OUT2/reset_others"   "0" "watchdog run: reset_others=0"
fi

# ── reset-cause-logger smoke test ─────────────────────────────────────────────

echo ""
echo "== reset-cause-logger smoke test =="

if [[ ! -f "$LOGGER_SCRIPT" ]]; then
    warn "skipping logger test (script missing)"
else
    MOCK_LOG="$WORK/bmc-reset-cause.log"
    MOCK_CRASH="$WORK/bmc-crashes"

    # The script hardcodes /var/log paths; patch them in a temp copy for offline testing.
    PATCHED_LOGGER="$WORK/logger_patched.sh"
    sed \
        "s|/var/log/bmc-reset-cause.log|$MOCK_LOG|g; \
         s|/var/log/bmc-crashes|$MOCK_CRASH|g" \
        "$LOGGER_SCRIPT" >"$PATCHED_LOGGER"
    chmod +x "$PATCHED_LOGGER"

    bash "$PATCHED_LOGGER" >/dev/null 2>&1
    rc=$?
    if [[ "$rc" -eq 0 ]]; then
        ok "reset-cause-logger exited 0"
    else
        fail "reset-cause-logger exited $rc"
    fi

    if [[ -f "$MOCK_LOG" ]]; then
        ok "reset-cause-logger created log file: $MOCK_LOG"
    else
        fail "reset-cause-logger did not create log file: $MOCK_LOG"
    fi

    if grep -q "BMC Boot at" "$MOCK_LOG" 2>/dev/null; then
        ok "reset-cause-logger: log contains 'BMC Boot at' header"
    else
        fail "reset-cause-logger: 'BMC Boot at' missing from log"
    fi

    if grep -q "End of boot analysis" "$MOCK_LOG" 2>/dev/null; then
        ok "reset-cause-logger: log contains 'End of boot analysis' footer"
    else
        fail "reset-cause-logger: 'End of boot analysis' missing from log"
    fi
fi

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "-------------------------------------------------------------------"
if [[ "$failures" -eq 0 ]]; then
    echo "Summary: all checks passed (warnings=$warns)."
    exit 0
fi
echo "Summary: failures=$failures warnings=$warns"
exit 1
