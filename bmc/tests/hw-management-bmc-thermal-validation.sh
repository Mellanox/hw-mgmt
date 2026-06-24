#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# Validate the BMC thermal sysfs layout under /var/run/hw-management/thermal/.
#
# HI189 expected layout (per bmc/examples/hw-management-bmc-thermal-sysfs.txt):
#   cpu_temp_input  — symlink to …/15-004c/…/hwmon*/temp1_input
#   cpu_temp        — symlink to …/temp1_max
#   cpu_min         — symlink to …/temp1_min
#   bmc_temp_input  — symlink to …/4-0048/…/hwmon*/temp1_input
#   bmc_temp        — symlink to …/temp1_max
#   (NO bmc_min — lm75 has no temp1_min register)
#
# On live hardware the thermal dir is populated by udev via
# hw-management-bmc-events.sh.  On a CI/dev host those sysfs paths will be
# absent — the test gracefully degrades to structural checks (naming, absence
# of bmc_min) and skips value reads.
#
# Environment (optional):
#   HW_MGMT_THERMAL_DIR=/var/run/hw-management/thermal
#   THERMAL_STRICT=1  — exit 1 if thermal dir does not exist at all
#
# Exit: 0 on success (or graceful skip); 1 on failure.

set -u
set +e

THERMAL_DIR="${HW_MGMT_THERMAL_DIR:-/var/run/hw-management/thermal}"

failures=0
warns=0

ok()   { echo "OK: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
warn() { echo "WARN: $*" >&2; warns=$((warns + 1)); }

# Expected symlinks for HI189 (cpu_* uses sbtsi; bmc_* uses lm75).
EXPECTED_SYMLINKS=(cpu_temp_input cpu_temp cpu_min bmc_temp_input bmc_temp)

# lm75 has no temp1_min → bmc_min must NOT exist.
MUST_NOT_EXIST=(bmc_min)

read_millideg() {
    local f="$1"
    local v
    v=$(cat "$f" 2>/dev/null | tr -d '[:space:]')
    echo "$v"
}

is_numeric() {
    [[ "$1" =~ ^-?[0-9]+$ ]]
}

echo "hw-management-bmc thermal validation ($(date -Iseconds 2>/dev/null || date))"
echo "Thermal dir: $THERMAL_DIR"

if [[ ! -d "$THERMAL_DIR" ]]; then
    if [[ -n "${THERMAL_STRICT:-}" ]]; then
        fail "thermal dir does not exist: $THERMAL_DIR"
        echo "Summary: failures=$failures"
        exit 1
    fi
    warn "thermal dir absent ($THERMAL_DIR) — hardware may not be running; skipping live checks"
    echo "Summary: SKIP (thermal dir absent; use THERMAL_STRICT=1 to fail here)"
    exit 0
fi

# ── presence and symlink checks ───────────────────────────────────────────────

echo ""
echo "== expected symlink presence =="
for name in "${EXPECTED_SYMLINKS[@]}"; do
    path="$THERMAL_DIR/$name"
    if [[ -L "$path" ]]; then
        target=$(readlink "$path" 2>/dev/null)
        ok "symlink: $name → $target"
    elif [[ -f "$path" ]]; then
        warn "$name: exists as regular file, expected symlink"
    else
        warn "$name: not present (udev may not have fired yet)"
    fi
done

# ── naming convention ─────────────────────────────────────────────────────────

echo ""
echo "== naming convention (cpu_* / bmc_*) =="
shopt -s nullglob
for f in "$THERMAL_DIR"/*; do
    base=$(basename "$f")
    case "$base" in
    cpu_*|bmc_*)
        ok "name follows convention: $base"
        ;;
    *)
        warn "unexpected entry '$base' (does not start with cpu_/bmc_)"
        ;;
    esac
done
shopt -u nullglob

# ── lm75 / bmc_min must-not-exist check ──────────────────────────────────────

echo ""
echo "== lm75 constraint: bmc_min must NOT exist =="
for name in "${MUST_NOT_EXIST[@]}"; do
    path="$THERMAL_DIR/$name"
    if [[ -e "$path" ]] || [[ -L "$path" ]]; then
        fail "$name: must NOT exist for lm75-backed sensor (lm75 has no temp1_min)"
    else
        ok "$name: correctly absent (lm75 has no temp1_min)"
    fi
done

# ── symlink target sanity (hwmon path pattern) ────────────────────────────────

echo ""
echo "== symlink target sanity =="
for name in "${EXPECTED_SYMLINKS[@]}"; do
    path="$THERMAL_DIR/$name"
    [[ -L "$path" ]] || continue
    target=$(readlink -f "$path" 2>/dev/null)
    if [[ -z "$target" ]]; then
        warn "$name: dangling symlink (target does not exist — device not probed?)"
        continue
    fi
    # Target must be under /sys/
    if [[ "$target" == /sys/* ]]; then
        ok "$name: target under /sys/ ($target)"
    else
        fail "$name: target not under /sys/ ($target)"
    fi
    # Must end in a known hwmon temperature attribute.
    case "$target" in
    */temp1_input|*/temp1_max|*/temp1_min)
        ok "$name: target attribute name valid ($(basename "$target"))"
        ;;
    *)
        fail "$name: unexpected attribute in target path: $(basename "$target")"
        ;;
    esac
done

# ── cpu I2C address check (15-004c) ──────────────────────────────────────────

echo ""
echo "== CPU sensor I2C address (15-004c expected) =="
for name in cpu_temp_input cpu_temp cpu_min; do
    path="$THERMAL_DIR/$name"
    [[ -L "$path" ]] || continue
    target=$(readlink -f "$path" 2>/dev/null)
    [[ -z "$target" ]] && continue
    if echo "$target" | grep -q "15-004c"; then
        ok "$name: target path contains '15-004c' (sbtsi expected addr)"
    else
        warn "$name: target path does not contain '15-004c' (may be ok for non-HI189)"
    fi
done

# ── bmc sensor I2C address check (4-0048) ────────────────────────────────────

echo ""
echo "== BMC sensor I2C address (4-0048 expected) =="
for name in bmc_temp_input bmc_temp; do
    path="$THERMAL_DIR/$name"
    [[ -L "$path" ]] || continue
    target=$(readlink -f "$path" 2>/dev/null)
    [[ -z "$target" ]] && continue
    if echo "$target" | grep -q "4-0048"; then
        ok "$name: target path contains '4-0048' (lm75 expected addr)"
    else
        warn "$name: target path does not contain '4-0048' (may be ok for non-HI189)"
    fi
done

# ── value sanity reads (live hardware only) ───────────────────────────────────

echo ""
echo "== temperature value reads (live hardware) =="
for name in cpu_temp_input bmc_temp_input; do
    path="$THERMAL_DIR/$name"
    [[ -L "$path" ]] || { warn "$name: not present, skip value read"; continue; }
    target=$(readlink -f "$path" 2>/dev/null)
    [[ -z "$target" ]] && { warn "$name: dangling symlink, skip value read"; continue; }
    val=$(read_millideg "$target")
    if is_numeric "$val"; then
        # Sanity: -40°C..125°C in millidegrees (-40000..125000)
        if [[ "$val" -ge -40000 && "$val" -le 125000 ]]; then
            ok "$name: value=${val} m°C (plausible range)"
        else
            warn "$name: value=${val} m°C outside plausible -40000..125000 range"
        fi
    else
        fail "$name: non-numeric value read: '$val'"
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
