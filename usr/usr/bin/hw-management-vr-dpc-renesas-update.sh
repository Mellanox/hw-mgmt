#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# Renesas VR DPC Update Tool (Gen3.5)
# Implements HEX file execution using PMBus/DMA commands
# Reference (Gen3.5): HEX header = first 4 lines (0x49...) and is NOT written to the device.

################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults
I2C_BUS=""
DEVICE_ADDR=""
CONFIG_FILE=""
MODE=""
HEADER_MAX=4
REDUNDANCY=1
RESTORE_CFG_ID=""

DRY_RUN=0
ASSUME_YES=0
VERBOSE=0
FORCE_FLASH=0
REPEAT_UNTIL_FULL=0   # set by -r max: keep programming until NVM saves are exhausted

# Idempotency: the expected CONFIG_CRC lives on a specific data line of the .hex, NOT in the header.
# Line number (1-based) = CONFIG_INDEX * STRIDE + BASE. For the first config (index 0) -> line 336.
# That line is a write record whose 4 data bytes are the config CRC (e.g. line 336: 0007C0C6 71FD9F8F D1).
RENESAS_CRC_LINE_BASE=${RENESAS_CRC_LINE_BASE:-336}
RENESAS_CRC_LINE_STRIDE=${RENESAS_CRC_LINE_STRIDE:-469}
RENESAS_CRC_CONFIG_INDEX=${RENESAS_CRC_CONFIG_INDEX:-0}

# PEC (optional). Guide notes file CRC8 is per-line only and can be ignored if PEC not used.
USE_I2C_PEC=0
I2C_XFER_FLAGS="-y"

# Retries
I2C_MAX_RETRY=${I2C_MAX_RETRY:-3}
I2C_RETRY_DELAY=${I2C_RETRY_DELAY:-0.05}

# Poll timeout (record type 0x11). Uses a deterministic iteration budget instead of
# wall-clock: `date +%s%3N` has no %N on BusyBox and would otherwise disable the timeout,
# allowing an infinite poll on a stuck device.
POLL_MAX_MS=${POLL_MAX_MS:-2000}
POLL_INTERVAL_MS=${POLL_INTERVAL_MS:-50}

# PMBus common commands (standard telemetry / status)
PMBUS_PAGE=0x00
PMBUS_OPERATION=0x01
PMBUS_CLEAR_FAULTS=0x03

PMBUS_STATUS_BYTE=0x78
PMBUS_STATUS_WORD=0x79

PMBUS_READ_VIN=0x88
PMBUS_READ_VOUT=0x8B
PMBUS_READ_IOUT=0x8C
PMBUS_READ_TEMPERATURE_1=0x8D
PMBUS_READ_POUT=0x96
PMBUS_READ_PIN=0x97

PMBUS_MFR_ID=0x99
PMBUS_MFR_MODEL=0x9A
PMBUS_MFR_REVISION=0x9B
PMBUS_MFR_DATE=0x9D
PMBUS_MFR_SERIAL=0x9E

# Driver unbind/rebind (raw i2c-tools access when kernel driver is bound)
DRIVER_UNBIND_DEVID=""
DRIVER_UNBIND_NAME=""
UNBIND_STATE_FILE="/var/run/hw-management/vr_dpc_renesas_unbound"

# Renesas PMBus / DMA command codes (per programming guide)
CMD_IC_DEVICE_ID=0xAD
CMD_IC_DEVICE_REV=0xAE
CMD_DMA_DATA=0xC5
CMD_DMA_SEQ=0xC6
CMD_DMA_ADDR=0xC7
CMD_RESTORE_CFG=0xF2

# --------------------------------
# Logging
# --------------------------------
log_info()  { echo -e "${GREEN}[INFO]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_dbg()   { [ "${VERBOSE:-0}" -gt 0 ] && echo "[DEBUG] $*" >&2; return 0; }
# Level-2 verbose (-vv): log each raw I2C transaction (TX/RX). Always returns 0 so it
# never affects the exit status of a surrounding command sequence.
log_trace() { [ "${VERBOSE:-0}" -ge 2 ] && echo "[I2C]  $*" >&2; return 0; }

# BusyBox-safe sub-second sleep. Many BusyBox builds ship a `sleep` that rejects
# fractional seconds. Try fractional sleep, then usleep, then give up silently
# (best-effort pacing) rather than blocking a full second. Always returns 0.
_sleep_frac() {
    local s="${1:-0}"
    sleep "$s" 2>/dev/null && return 0
    if command -v usleep >/dev/null 2>&1; then
        local us
        us=$(awk -v x="$s" 'BEGIN{printf "%d", (x*1000000)}' 2>/dev/null)
        [ -n "$us" ] && [ "$us" -gt 0 ] 2>/dev/null && usleep "$us" 2>/dev/null
    fi
    return 0
}

# --------------------------------
# Usage
# --------------------------------
_SELF_BN=$(basename -- "${BASH_SOURCE[0]}")


usage() {
  local status=${1:-1}
  cat <<EOF
Renesas VR DPC Update Tool (Gen3.5)

USAGE: ${_SELF_BN} <mode> [options]
       ${_SELF_BN} -h | --help | help

MODES:
  flash       Program device with configuration file (.hex)
  verify      Verify file/device compatibility (IC_DEVICE_ID/REV)
  info        Read device identification (IC_DEVICE_ID/REV)
  status      Show programming status read-only: BANK_STATUS (decoded), CONFIG_CRC,
              NVM saves, MCUFLT. No flash, no NVM save consumed (aliases: bank, bankstatus)
  monitor     Monitor device telemetry
  dump        Dump device registers
  scan        Scan I2C bus (i2cdetect)
  unbind      Unbind kernel i2c driver for the device
  rebind      Rebind previously unbound device

FLASH/VERIFY/INFO OPTIONS:
  -b <bus>        I2C bus number
  -a <addr>       Device I2C address (hex, e.g. 0x60)
  -f <file>       Programming file path (typically .hex)

FLASH OPTIONS:
  -n              Dry run: simulate the flash. No config WRITES are sent to the device, but
                  diagnostic READS still run (device detect, IC_DEVICE_ID/REV, CONFIG_CRC,
                  NVM saves, BANK_STATUS). Use it to preview what a real flash would do and to
                  see whether the device is already programmed. It never modifies the device.
  -F              Force: flash even if the device is already programmed with this config
                  (by default an already-programmed device is skipped to avoid wasting an
                  NVM save). Each real flash consumes one NVM save.
  -y              Non-interactive: skip the "Continue?" confirmation prompt (for batch use).
  -P0 | -P1       SMBus PEC on/off for i2ctransfer helpers (default: OFF)
  -r <n>          Repeat programming N times (redundancy). Each run consumes NVM saves.
  -r max          Repeat programming until the NVM saves are exhausted (fills all NVM slots).
                  Stops cleanly when there are not enough saves left for another run.
                  NOTE: -r N (N>1) and -r max also re-flash a device that is already programmed
                        (an explicit repeat request overrides the already-programmed skip).
  -v              Verbose. Repeat for more: -vv also logs every raw I2C transaction
                  (TX bytes sent / RX bytes received, with retry count) to stderr.
  -S <id>         After flash, force-load Configuration ID <id> (0..15) from NVM into RAM using
                  RESTORE_CFG (0xF2), then read the active CONFIG_CRC (DMA @0x00F8). A Renesas
                  DPC device can hold several stored configurations (IDs 0..15); -S lets you
                  select and verify which one is active after programming. Omit -S to just read
                  the current CONFIG_CRC without switching config.
                  WARNING: RESTORE_CFG must NOT be issued while the rail is regulating.

IDEMPOTENCY (avoid re-flashing every time):
  Before flashing, the tool reads the device CONFIG_CRC (DMA @0x00F8) and compares it to the
  expected CRC taken from a data line of the .hex file (NOT the header). The CRC line (1-based) is
  CONFIG_INDEX*STRIDE + BASE; for the first config that is line 336 (its 4 data bytes are the CRC).
  If they match, the device is already programmed and the flash is SKIPPED (use -F to override).
  Env overrides: RENESAS_CRC_LINE_BASE (default 336), RENESAS_CRC_LINE_STRIDE (default 469),
  RENESAS_CRC_CONFIG_INDEX (default 0).

VERIFY MODE (read-only, no writes):
  ${_SELF_BN} verify -b <bus> -a <addr> -f <file.hex>
  Checks, WITHOUT touching the device, that:
    - the file matches the device  -> IC_DEVICE_ID (0xAD) must match (REV/version are info only);
    - whether the device is ALREADY programmed with this file -> compares the live CONFIG_CRC
      (DMA @0x00F8) against the CRC stored in the file. It reports ALREADY PROGRAMMED / needs
      programming, so you can decide whether a flash is needed. Safe to run while regulating.
  NOTE: the confirmation prompt is skipped only by -y (non-interactive); -n (dry-run) and -F
        (force) are separate and never auto-confirm by themselves.

MONITOR MODE OPTIONS:
  -b <bus>        I2C bus number
  -a <addr>       Device I2C address
  -i <interval>   Update interval in seconds (default: 1)

DUMP MODE OPTIONS:
  -b <bus>        I2C bus number
  -a <addr>       Device I2C address
  -o <file>       Output file (optional)

SCAN OPTIONS:
  -b <bus>        I2C bus number

ENV (optional):
  I2C_MAX_RETRY   Retries per I2C op (default 3)
  I2C_RETRY_DELAY Delay between retries (default 0.05)
  POLL_MAX_MS     Max time to wait on a poll (0x11) record before timeout (default 2000)
  POLL_INTERVAL_MS Poll re-read interval (default 50)


EXAMPLES:
  # Read device identity, NVM saves, CONFIG_CRC, BANK_STATUS, MCUFLT
  ${_SELF_BN} info -b 12 -a 0x60

  # Quick read-only programming status (BANK_STATUS/CONFIG_CRC/NVM/MCUFLT), no flash
  ${_SELF_BN} status -b 12 -a 0x60

  # Check the bus / find the device
  ${_SELF_BN} scan -b 12

  # Verify a file matches the device and whether it is already programmed (no writes)
  ${_SELF_BN} verify -b 12 -a 0x60 -f RAA228249-0_0x60_on.hex

  # Dry run: preview a flash (detect + verify + CRC check, but no writes)
  ${_SELF_BN} flash -n -b 12 -a 0x60 -f RAA228249-0_0x60_on.hex

  # Flash (interactive confirm). Skips automatically if already programmed.
  ${_SELF_BN} flash -b 12 -a 0x60 -f RAA228249-0_0x60_on.hex

  # Flash non-interactively (batch), forcing even if already programmed
  ${_SELF_BN} flash -y -F -b 12 -a 0x60 -f RAA228249-0_0x60_on.hex

  # Flash, then load+verify stored Configuration ID 0 and print its CONFIG_CRC
  ${_SELF_BN} flash -y -b 12 -a 0x60 -f RAA228249-0_0x60_on.hex -S 0

NOTES (Gen3.5):
  - HEX file header is the first 4 lines (0x49...) and must NOT be written to the device.
  - HEX record types supported: 00 write, 10 read+compare, 11 poll, 12 mask, 20 wait, 49 header.
  - IC_DEVICE_ID (0xAD) is the mandatory file<->device match; IC_DEVICE_REV/version are informational.
  - BANK_STATUS (DMA @0x0084): "Unaffected" banks are NORMAL (a config writes only the bank(s) it
    needs). A successful flash shows "Written OK" on the touched bank(s) with no FAIL nibbles.
    If ALL banks are "Unaffected", nothing was rewritten (config already present or RAM-only);
    power-cycle / restart the rail to apply the configuration.

EOF

  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    exit "$status"
  fi
  return "$status"
}

# --------------------------------
# Dependencies
# --------------------------------
check_dependencies() {
    local missing=0
    for cmd in i2cdetect i2ctransfer i2cget i2cset awk sed tr; do
        command -v "$cmd" >/dev/null 2>&1 || { log_error "Missing dependency: $cmd"; missing=1; }
    done
    [ $missing -eq 1 ] && return 1
    return 0
}

# --------------------------------
# DMA Readings
# --------------------------------

dma_set_addr() {
    local addr="$1"     # es: 0x0035, 0x00F8, 0xEC01
    local a=$((addr))   # normalizza in int

    # Gen3.5: DMA Address (0xC7) accetta 2 byte: LSB poi MSB
    local b0 b1
    b0=$(printf '0x%02x' $(( a        & 0xff )))   # LSB
    b1=$(printf '0x%02x' $(( (a >> 8) & 0xff )))   # MSB

    log_dbg "DMA_SET_ADDR (0xC7): addr=0x$(printf '%04x' $((a & 0xffff))) bytes=$b0 $b1"

    # NOTE: setting the DMA read pointer (0xC7) is NON-destructive (it only selects
    # which register the next 0xC5 read returns). It must run even in dry-run so that
    # diagnostic reads (CONFIG_CRC @0x00F8, NVM saves @0x0035, BANK_STATUS @0x0084) are
    # accurate. Only the actual config writes (execute_write_line / RESTORE_CFG) are skipped in dry-run.

    # Route through i2c_write -> i2c_rw_wrapper so the DMA pointer set gets the same
    # retry logic (I2C_MAX_RETRY) and PEC handling ($I2C_XFER_FLAGS) as the config-write path.
    # ESEMPIO reale (NVM saves): i2ctransfer -y 1 w3@0x60 0xC7 0x35 0x00
    i2c_write "$I2C_BUS" "$DEVICE_ADDR" "$CMD_DMA_ADDR" "$b0" "$b1" >/dev/null
}

dma_read32() {
    local addr="$1"
    dma_set_addr "$addr" || return 1

    # DMA data read (0xC5) as a 4-byte read. Route through i2c_read_n -> i2c_rw_wrapper so
    # it inherits retry (I2C_MAX_RETRY) and PEC, AND its short-read guard: a truncated but
    # otherwise-successful transfer is rejected instead of being silently padded to 0x00000000
    # (which would fool the blank-device / CONFIG_CRC / NVM-saves / BANK_STATUS decisions).
    # ESEMPIO reale: i2ctransfer -y 1 w1@0x60 0xC5 r4
    local line b0 b1 b2 b3
    line=$(i2c_read_n "$I2C_BUS" "$DEVICE_ADDR" "$CMD_DMA_DATA" 4) || return 1
    read -r b0 b1 b2 b3 <<< "$line"

    # Belt-and-suspenders: require all 4 bytes to be present (non-empty).
    if [ -z "$b0" ] || [ -z "$b1" ] || [ -z "$b2" ] || [ -z "$b3" ]; then
        log_dbg "dma_read32 @$addr: short/truncated read '$line' -> fail (not 0x00000000)"
        return 1
    fi

    # line = "ZZ YY XX WW" (bus order, LSB first) -> host order 0xWWXXYYZZ
    printf "0x%02x%02x%02x%02x\n" "$((16#${b3#0x}))" "$((16#${b2#0x}))" "$((16#${b1#0x}))" "$((16#${b0#0x}))"
}


read_nvm_saves_available() {
    local v_hex
    v_hex=$(dma_read32 0x0035) || return 1

    # Gen3.5: contatore 0..24 (usa LSB = ZZ)
    local v_dec=$(( 16#${v_hex#0x} & 0xFF ))
    echo "$v_dec"
}


read_dma_field() {
    local addr="$1"
    local lsb="$2"
    local msb="$3"

    local raw
    raw=$(dma_read32 "$addr" 2>/dev/null) || { echo "N/A"; return; }

    local val=$((16#${raw#0x}))

    if [ -n "$lsb" ] && [ -n "$msb" ]; then
        local width=$((msb - lsb + 1))
        local mask=$(( (1 << width) - 1 ))
        val=$(( (val >> lsb) & mask ))
        printf "0x%x\n" "$val"
    else
        echo "$raw"
    fi
}

# --------------------------------
# Driver unbind/rebind (generic)
# --------------------------------
unbind_driver_for_device() {
    [ -n "$I2C_BUS" ] && [ -n "$DEVICE_ADDR" ] || return 0
    local addr_hex dev_id_4 dev_id_2 dev_path driver_link driver_name unbind_file dev_id

    addr_hex=$(printf '%02x' $((DEVICE_ADDR)))
    dev_id_4="${I2C_BUS}-$(printf '%04x' $((DEVICE_ADDR)))"
    dev_id_2="${I2C_BUS}-${addr_hex}"
    dev_path=""

    for id in "$dev_id_4" "$dev_id_2"; do
        if [ -d "/sys/bus/i2c/devices/$id" ]; then
            dev_path="/sys/bus/i2c/devices/$id"
            break
        fi
    done
    [ -z "$dev_path" ] && return 0
    [ -L "$dev_path/driver" ] || return 0

    driver_link=$(readlink "$dev_path/driver" 2>/dev/null) || return 0
    driver_name=$(basename "$driver_link" 2>/dev/null) || return 0
    unbind_file="/sys/bus/i2c/drivers/$driver_name/unbind"
    [ -f "$unbind_file" ] || return 0

    dev_id=$(basename "$dev_path")
    if echo "$dev_id" > "$unbind_file"; then
        DRIVER_UNBIND_DEVID="$dev_id"
        DRIVER_UNBIND_NAME="$driver_name"
        _sleep_frac 0.2
    fi
    return 0
}

rebind_driver_if_unbound() {
    [ -n "$DRIVER_UNBIND_DEVID" ] && [ -n "$DRIVER_UNBIND_NAME" ] || return 0
    local bind_file="/sys/bus/i2c/drivers/$DRIVER_UNBIND_NAME/bind"
    [ -f "$bind_file" ] || { DRIVER_UNBIND_DEVID=""; DRIVER_UNBIND_NAME=""; return 0; }
    local delay=${REBIND_DELAY:-1}
    [ "$delay" -gt 0 ] 2>/dev/null && sleep "$delay"
    if echo "$DRIVER_UNBIND_DEVID" > "$bind_file"; then
        log_info "Driver $DRIVER_UNBIND_NAME rebound to $DRIVER_UNBIND_DEVID"
    else
        log_warn "Rebind failed for $DRIVER_UNBIND_NAME to $DRIVER_UNBIND_DEVID"
    fi
    DRIVER_UNBIND_DEVID=""
    DRIVER_UNBIND_NAME=""
    return 0
}

save_unbind_state() {
    [ -n "$DRIVER_UNBIND_DEVID" ] && [ -n "$DRIVER_UNBIND_NAME" ] || return 1
    mkdir -p "$(dirname "$UNBIND_STATE_FILE")" 2>/dev/null || return 1
    echo "$DRIVER_UNBIND_DEVID" > "$UNBIND_STATE_FILE" 2>/dev/null || return 1
    echo "$DRIVER_UNBIND_NAME" >> "$UNBIND_STATE_FILE" 2>/dev/null || return 1
    return 0
}

rebind_driver_from_state_file() {
    [ -f "$UNBIND_STATE_FILE" ] || return 1
    DRIVER_UNBIND_DEVID=$(sed -n '1p' "$UNBIND_STATE_FILE" 2>/dev/null)
    DRIVER_UNBIND_NAME=$(sed -n '2p' "$UNBIND_STATE_FILE" 2>/dev/null)
    rm -f "$UNBIND_STATE_FILE" 2>/dev/null
    [ -n "$DRIVER_UNBIND_DEVID" ] && [ -n "$DRIVER_UNBIND_NAME" ] || return 1
    rebind_driver_if_unbound
    return 0
}

# --------------------------------
# SMBus PEC (optional) + retry i2ctransfer
# --------------------------------
_pec_slave_w() { local a="${1#0x}"; echo $(( (16#$a << 1) & 0xff )); }
_pec_slave_r() { echo $(( ($1 | 1) & 0xff )); }

calc_pec() {
    local crc=0 val i byte
    for byte in "$@"; do
        val=$((byte))
        crc=$((crc ^ val))
        for i in 1 2 3 4 5 6 7 8; do
            if [ $((crc & 0x80)) -ne 0 ]; then
                crc=$(((crc << 1) ^ 0x07))
            else
                crc=$((crc << 1))
            fi
        done
        crc=$((crc & 0xFF))
    done
    printf '0x%02x' "$crc"
}

i2c_rw_wrapper() {
    local bus=$1 addr=$2 readlen=$3 wkm1=$4
    shift 4
    local -a wb; wb=("$@")
    local nwb=${#wb[@]}
    local expect=$((wkm1 + 1))
    [ "$nwb" -ne "$expect" ] && { log_error "i2c_rw_wrapper: expected $expect write bytes, got $nwb"; return 1; }

    local max="$I2C_MAX_RETRY"
    [ "$max" -lt 1 ] 2>/dev/null && max=1
    local delay="$I2C_RETRY_DELAY"
    local attempt=0 addr_w addr_r raw line p_rx expected j
    local -a rd

    addr_w=$(_pec_slave_w "$addr")
    addr_r=$(_pec_slave_r "$addr_w")

    if [ "$readlen" -eq 0 ]; then
        while [ $attempt -lt "$max" ]; do
            if [ "${USE_I2C_PEC:-0}" -eq 1 ]; then
                local wp; wp=$(calc_pec "$addr_w" "${wb[@]}")
                log_trace "TX w$((nwb + 1))@$addr ${wb[*]} $wp (PEC, try $((attempt + 1))/$max)"
                raw=$(i2ctransfer $I2C_XFER_FLAGS "$bus" "w$((nwb + 1))@$addr" "${wb[@]}" "$wp") && return 0
            else
                log_trace "TX w${nwb}@$addr ${wb[*]} (try $((attempt + 1))/$max)"
                raw=$(i2ctransfer -y "$bus" "w${nwb}@$addr" "${wb[@]}") && return 0
            fi
            attempt=$((attempt + 1))
            [ $attempt -lt "$max" ] && _sleep_frac "$delay"
        done
        log_trace "TX FAILED w${nwb}@$addr ${wb[*]} after $max tries"
        return 1
    fi

    local nread=$readlen
    [ "${USE_I2C_PEC:-0}" -eq 1 ] && nread=$((readlen + 1))

    attempt=0
    while [ $attempt -lt "$max" ]; do
        if [ "${USE_I2C_PEC:-0}" -eq 1 ]; then
            log_trace "TX w${nwb}@$addr ${wb[*]} r${nread} (PEC, try $((attempt + 1))/$max)"
            raw=$(i2ctransfer $I2C_XFER_FLAGS "$bus" "w${nwb}@$addr" "${wb[@]}" "r${nread}") || {
                attempt=$((attempt + 1)); [ $attempt -lt "$max" ] && _sleep_frac "$delay"; continue; }
        else
            log_trace "TX w${nwb}@$addr ${wb[*]} r${readlen} (try $((attempt + 1))/$max)"
            raw=$(i2ctransfer -y "$bus" "w${nwb}@$addr" "${wb[@]}" "r${readlen}") || {
                attempt=$((attempt + 1)); [ $attempt -lt "$max" ] && _sleep_frac "$delay"; continue; }
        fi

        log_trace "RX $raw"
        line=$(echo "$raw" | sed 's/0x//g')
        read -ra rd <<< "$line"

        if [ "${USE_I2C_PEC:-0}" -eq 1 ]; then
            [ "${#rd[@]}" -lt $((readlen + 1)) ] && { attempt=$((attempt + 1)); [ $attempt -lt "$max" ] && _sleep_frac "$delay"; continue; }
            p_rx=$(printf '0x%02x' $((16#${rd[readlen]})))
            local -a pec_args; pec_args=("$addr_w" "${wb[@]}" "$addr_r")
            for ((j=0; j<readlen; j++)); do pec_args+=("0x${rd[j]}"); done
            expected=$(calc_pec "${pec_args[@]}")
            [ "$p_rx" != "$expected" ] && { attempt=$((attempt + 1)); [ $attempt -lt "$max" ] && _sleep_frac "$delay"; continue; }
        else
            [ "${#rd[@]}" -lt "$readlen" ] && { attempt=$((attempt + 1)); [ $attempt -lt "$max" ] && _sleep_frac "$delay"; continue; }
        fi

        echo "$(printf '%s ' "${rd[@]:0:readlen}" | sed 's/[[:space:]]*$//')"
        return 0
    done
    return 1
}

i2c_send_byte() { local bus=$1 addr=$2 reg=$3; i2c_rw_wrapper "$bus" "$addr" 0 0 "$reg"; }

i2c_write() {
    local bus=$1 addr=$2 reg=$3
    shift 3
    local -a data; data=("$@")
    if [ ${#data[@]} -eq 0 ]; then
        i2c_rw_wrapper "$bus" "$addr" 0 0 "$reg"
    else
        i2c_rw_wrapper "$bus" "$addr" 0 "${#data[@]}" "$reg" "${data[@]}"
    fi
}

# Read N bytes from a command code (no length prefix)
i2c_read_n() {
    local bus=$1 addr=$2 reg=$3 len=${4:-4}
    i2c_rw_wrapper "$bus" "$addr" "$len" 0 "$reg"
}

# Read PMBus block read of 4 bytes: expects first returned byte == 0x04 then 4 bytes payload
pmbus_block_read4() {
    local bus=$1 addr=$2 cmd=$3
    local line b0 d1 d2 d3 d4
    line=$(i2c_rw_wrapper "$bus" "$addr" 5 0 "$cmd") || return 1
    read -r b0 d1 d2 d3 d4 <<< "$line" || return 1
    [ $((16#${b0})) -ne 4 ] && return 1
    echo "$d1 $d2 $d3 $d4"
}

# Reverse 4 bytes (bus order) -> host order (WWXXYYZZ) as hex u32 string
rev4_to_u32() {
    local b0=$1 b1=$2 b2=$3 b3=$4
    printf '0x%02x%02x%02x%02x' $((16#$b3)) $((16#$b2)) $((16#$b1)) $((16#$b0))
}

# Reverse 4 bytes tokens -> array string
rev4_bytes() {
    local b0=$1 b1=$2 b2=$3 b3=$4
    echo "$b3 $b2 $b1 $b0"
}

# --------------------------------
# Device detection / ID
# --------------------------------
detect_device() {
    log_info "Detecting device at $DEVICE_ADDR on bus $I2C_BUS..."
    local out addr_hex
    addr_hex=$(printf '%02x' $((DEVICE_ADDR)))

    # 1) Reliable check first: a sysfs i2c device node exists whenever a kernel driver is
    #    bound (the same reason 'sensors' can read it). On the CPU path the regulator is
    #    usually bound, so i2cdetect probing can be unreliable/blocked while the node exists.
    local id
    for id in "${I2C_BUS}-$(printf '%04x' $((DEVICE_ADDR)))" "${I2C_BUS}-${addr_hex}"; do
        if [ -d "/sys/bus/i2c/devices/$id" ]; then
            log_info "Device detected (sysfs: /sys/bus/i2c/devices/$id; kernel driver bound — will unbind for raw access)"
            return 0
        fi
    done

    # 2) Fallback to i2cdetect (device shows its address when free, or 'UU' when bound).
    out=$(i2cdetect -y "$I2C_BUS" "$DEVICE_ADDR" "$DEVICE_ADDR" 2>/dev/null)
    if echo "$out" | grep -qE " (${addr_hex}|UU)( |$)"; then
        log_info "Device detected"
        return 0
    fi

    log_error "Device not detected at $DEVICE_ADDR on bus $I2C_BUS"
    log_error "Hint: if 'sensors' shows it, the kernel driver holds the bus. Check 'i2cdetect -y $I2C_BUS' (look for 'UU' at $addr_hex), confirm the bus number, or run '${_SELF_BN} unbind -b $I2C_BUS -a $DEVICE_ADDR'."
    return 1
}

read_ic_device_id() {
    # Read IC_DEVICE_ID using command code 0xAD as block read of 4 bytes (per guide)
    local line b0 b1 b2 b3
    line=$(pmbus_block_read4 "$I2C_BUS" "$DEVICE_ADDR" "$CMD_IC_DEVICE_ID") || return 1
    read -r b0 b1 b2 b3 <<< "$line"
    rev4_to_u32 "$b0" "$b1" "$b2" "$b3"
}

read_ic_device_rev() {
    local line b0 b1 b2 b3
    line=$(pmbus_block_read4 "$I2C_BUS" "$DEVICE_ADDR" "$CMD_IC_DEVICE_REV") || return 1
    read -r b0 b1 b2 b3 <<< "$line"
    rev4_to_u32 "$b0" "$b1" "$b2" "$b3"
}


# --------------------------------
# File parsing helpers (.hex line format)
# --------------------------------
# Strip whitespace, keep only hex line; empty => ""
normalize_hex_line() {
    local s="$1"
    s=$(echo "$s" | tr -d ' \t\r' )
    # skip blank / comments
    [ -z "$s" ] && { echo ""; return 0; }
    case "$s" in
        \#*|//* ) echo ""; return 0 ;;
    esac
    # accept only pure hex
    echo "$s" | grep -qiE '^[0-9a-f]+$' || { echo ""; return 0; }
    echo "$s"
}

# Parse hex string into bytes array
hex_to_bytes() {
    local h="$1"
    local n=${#h}
    [ $((n % 2)) -ne 0 ] && return 1
    local i=0
    while [ $i -lt $n ]; do
        echo "0x${h:$i:2}"
        i=$((i + 2))
    done
}

print_dma_field() {
    local name="$1"
    local addr="$2"
    local lsb="$3"
    local msb="$4"

    local val
    val=$(read_dma_field "$addr" "$lsb" "$msb")

    printf "  %-20s: %s\n" "$name" "$val"
}

# --------------------------------
# Execute .hex commands 
# --------------------------------
MASK_U32=""     # optional mask for next read/poll

execute_write_line() {
    local cmd=$1; shift
    local -a data; data=("$@")
    [ $DRY_RUN -eq 1 ] && { log_dbg "[DRY_RUN] write cmd=$cmd data=${data[*]}"; return 0; }
    i2c_write "$I2C_BUS" "$DEVICE_ADDR" "$cmd" "${data[@]}"
}

read_u32_bytes() {
    local cmd=$1
    local line b0 b1 b2 b3
    line=$(i2c_read_n "$I2C_BUS" "$DEVICE_ADDR" "$cmd" 4) || return 1
    read -r b0 b1 b2 b3 <<< "$line" || return 1
    echo "$b0 $b1 $b2 $b3"
}

u32_from_bytes_hostorder() {
    local b0=$1 b1=$2 b2=$3 b3=$4
    # device returns bus order; convert to u32 display in host order
    rev4_to_u32 "$b0" "$b1" "$b2" "$b3"
}

and_u32_hex() {
    local a="${1#0x}" b="${2#0x}"
    printf '0x%08x' $(( (16#$a) & (16#$b) ))
}

eq_u32_hex() {
    [ "$(printf '0x%08x' $((16#${1#0x})))" = "$(printf '0x%08x' $((16#${2#0x})))" ]
}

execute_read_compare_line() {
    local cmd=$1 exp_b0=$2 exp_b1=$3 exp_b2=$4 exp_b3=$5

    # Expected value uses the SAME single byte-reversal as the read side (rev4_to_u32),
    # matching the canonical LSB-first convention used everywhere else (dma_read32, CONFIG_CRC,
    # parse_expected_config_crc). A prior extra rev4_bytes pre-reversal made the expected value
    # big-endian while the read value stayed little-endian, so identical file/device bytes were
    # flagged as a MISMATCH (and poll waited on the byte-swapped bit position).
    local exp_u32; exp_u32=$(rev4_to_u32 "${exp_b0#0x}" "${exp_b1#0x}" "${exp_b2#0x}" "${exp_b3#0x}" 2>/dev/null)

    local line rb0 rb1 rb2 rb3
    line=$(read_u32_bytes "$cmd") || { log_error "Read failed for cmd=$cmd"; return 1; }
    read -r rb0 rb1 rb2 rb3 <<< "$line"
    local read_u32; read_u32=$(u32_from_bytes_hostorder "$rb0" "$rb1" "$rb2" "$rb3")

    if [ -n "$MASK_U32" ]; then
        local m="$MASK_U32"
        local read_m; read_m=$(and_u32_hex "$read_u32" "$m")
        local exp_m;  exp_m=$(and_u32_hex "$exp_u32"  "$m")
        if ! eq_u32_hex "$read_m" "$exp_m"; then
            log_error "READ+MASK mismatch cmd=$cmd read=$read_u32 (masked=$read_m) expected=$exp_u32 (masked=$exp_m)"
            return 1
        fi
        log_dbg "READ+MASK OK cmd=$cmd read=$read_u32 mask=$m expected=$exp_u32"
    else
        if ! eq_u32_hex "$read_u32" "$exp_u32"; then
            log_error "READ mismatch cmd=$cmd read=$read_u32 expected=$exp_u32"
            return 1
        fi
        log_dbg "READ OK cmd=$cmd read=$read_u32 expected=$exp_u32"
    fi

    MASK_U32=""
    return 0
}

execute_poll_line() {
    local cmd=$1 exp_b0=$2 exp_b1=$3 exp_b2=$4 exp_b3=$5

    # Expected value uses the SAME single byte-reversal as the read side (rev4_to_u32),
    # matching the canonical LSB-first convention used everywhere else (dma_read32, CONFIG_CRC,
    # parse_expected_config_crc). A prior extra rev4_bytes pre-reversal made the expected value
    # big-endian while the read value stayed little-endian, so identical file/device bytes were
    # flagged as a MISMATCH (and poll waited on the byte-swapped bit position).
    local exp_u32; exp_u32=$(rev4_to_u32 "${exp_b0#0x}" "${exp_b1#0x}" "${exp_b2#0x}" "${exp_b3#0x}" 2>/dev/null)

    # expected bit mask (guide says one bit enabled in poll value)
    local bitmask="$exp_u32"
    [ -n "$MASK_U32" ] && bitmask=$(and_u32_hex "$bitmask" "$MASK_U32")

    # Timeout is BusyBox-robust and enforced two independent ways so the poll can never
    # loop forever, regardless of `date`/`sleep` capabilities:
    #   1) wall-clock in whole SECONDS via `date +%s` (BusyBox supports %s, just not %N);
    #   2) an iteration-count backstop, used when `date +%s` is unusable.
    # Sub-second pacing is best-effort (_sleep_frac): if BusyBox cannot fractional-sleep,
    # the loop simply polls faster (more I2C reads) but stays bounded by (1)/(2).
    local interval_ms=${POLL_INTERVAL_MS:-50}
    [ "$interval_ms" -ge 1 ] 2>/dev/null || interval_ms=50
    local sleep_s; sleep_s=$(awk -v m="$interval_ms" 'BEGIN{printf "%.3f", (m/1000.0)}' 2>/dev/null)
    [ -n "$sleep_s" ] || sleep_s="0.05"

    local timeout_s=$(( ( ${POLL_MAX_MS:-2000} + 999 ) / 1000 ))   # ceil to whole seconds
    [ "$timeout_s" -ge 1 ] || timeout_s=1
    # Backstop: generous so it never ends BEFORE timeout_s when sleeps are skipped
    # (fast spin), but still finite if `date` is broken. ~POLL_MAX_MS/ms + 100k margin.
    local iter_cap=$(( ${POLL_MAX_MS:-2000} / interval_ms + 100000 ))

    local start_s; start_s=$(date +%s 2>/dev/null)
    case "$start_s" in ''|*[!0-9]*) start_s="" ;; esac

    local iter=0
    while : ; do
        local line rb0 rb1 rb2 rb3
        line=$(read_u32_bytes "$cmd") || { log_error "Poll read failed cmd=$cmd"; MASK_U32=""; return 1; }
        read -r rb0 rb1 rb2 rb3 <<< "$line"
        local read_u32; read_u32=$(u32_from_bytes_hostorder "$rb0" "$rb1" "$rb2" "$rb3")

        local read_m="$read_u32"
        [ -n "$MASK_U32" ] && read_m=$(and_u32_hex "$read_u32" "$MASK_U32")

        # success if expected bit(s) are set
        local bm="${bitmask#0x}"
        local rm="${read_m#0x}"
        if [ $(( (16#$rm) & (16#$bm) )) -ne 0 ]; then
            log_dbg "POLL OK cmd=$cmd read=$read_u32 bitmask=0x$bm (iter=$iter)"
            MASK_U32=""
            return 0
        fi

        iter=$((iter + 1))

        # ---- stop conditions ----
        if [ -n "$start_s" ]; then
            local now_s; now_s=$(date +%s 2>/dev/null)
            case "$now_s" in ''|*[!0-9]*) now_s="$start_s" ;; esac
            [ $(( now_s - start_s )) -ge "$timeout_s" ] && break
        fi
        [ "$iter" -ge "$iter_cap" ] && break

        _sleep_frac "$sleep_s"
    done

    log_error "POLL timeout cmd=$cmd bitmask=$bitmask after ~${POLL_MAX_MS:-2000}ms (iter=$iter)"
    MASK_U32=""
    return 1
}

execute_mask_line() {
    local b0=$1 b1=$2 b2=$3 b3=$4
    # Mask uses the SAME single byte-reversal as the read value (rev4_to_u32): MASK_U32 is ANDed
    # against read_u32 (LSB-first), so it must be in the same byte order. A prior extra rev4_bytes
    # made the mask big-endian and masked the wrong byte lanes of the little-endian read value.
    MASK_U32=$(rev4_to_u32 "${b0#0x}" "${b1#0x}" "${b2#0x}" "${b3#0x}" 2>/dev/null)
    log_dbg "MASK set: $MASK_U32"
    return 0
}

execute_wait_line() {
    # Guard against a truncated 0x20 record with missing bytes: default to 0 so the
    # 16# arithmetic below never sees an empty operand.
    local hi="${1:-0x00}" lo="${2:-0x00}"
    hi="${hi#0x}"; lo="${lo#0x}"
    [ -n "$hi" ] || hi=0
    [ -n "$lo" ] || lo=0
    local ms=$(( (16#$hi << 8) + 16#$lo ))
    log_dbg "WAIT ${ms}ms"
    # Try a fractional sleep first. If BusyBox rejects it, fall back to an INTEGER-second
    # sleep rounded UP (never under-sleep a device-mandated wait: too-short could be unsafe,
    # too-long is harmless). A 0ms wait is a no-op.
    local secs_frac; secs_frac=$(awk -v m="$ms" 'BEGIN{printf "%.3f", (m/1000.0)}' 2>/dev/null)
    if [ "$ms" -gt 0 ] && ! sleep "${secs_frac:-1}" 2>/dev/null; then
        local secs_ceil=$(( (ms + 999) / 1000 ))
        [ "$secs_ceil" -ge 1 ] || secs_ceil=1
        sleep "$secs_ceil"
    fi
    return 0
}

# --------------------------------
# Parse header (first 15 x 0x49 lines) and verify device/file versions
# --------------------------------
EXPECTED_ID_U32=""
EXPECTED_REV_U32=""
EXPECTED_VER_STR=""      # firmware/config version string from header idcode 0x01 (e.g. "5.5.210")

parse_header_line_49() {
    # bytes: 49 <len> <addr8> <idcode> <data...> <crc>
    local len=$1 addr8=$2 idcode=$3
    shift 3
    local -a data; data=("$@")

    # We care about idcode AD (IC_DEVICE_ID), AE (IC_DEVICE_REV) and 01 (ASCII version string).
    # NOTE: the expected CONFIG_CRC is NOT in the header; it is on a data line of the file
    # (see parse_expected_config_crc / RENESAS_CRC_LINE_*).
    if [ "$idcode" = "0xAD" ] && [ ${#data[@]} -ge 4 ]; then
        local -a fix; read -r -a fix <<< "$(rev4_bytes "${data[0]}" "${data[1]}" "${data[2]}" "${data[3]}")"
        EXPECTED_ID_U32=$(rev4_to_u32 "${fix[0]#0x}" "${fix[1]#0x}" "${fix[2]#0x}" "${fix[3]#0x}" 2>/dev/null)
        log_dbg "Header expected IC_DEVICE_ID: $EXPECTED_ID_U32"
    elif [ "$idcode" = "0xAE" ] && [ ${#data[@]} -ge 4 ]; then
        local -a fix; read -r -a fix <<< "$(rev4_bytes "${data[0]}" "${data[1]}" "${data[2]}" "${data[3]}")"
        EXPECTED_REV_U32=$(rev4_to_u32 "${fix[0]#0x}" "${fix[1]#0x}" "${fix[2]#0x}" "${fix[3]#0x}" 2>/dev/null)
        log_dbg "Header expected IC_DEVICE_REV: $EXPECTED_REV_U32"
    elif [ "$idcode" = "0x01" ] && [ ${#data[@]} -ge 1 ]; then
        # ASCII version string (printable bytes only), e.g. 35 2E 35 2E 32 31 30 -> "5.5.210"
        local s="" b v
        for b in "${data[@]}"; do
            v=$((b))
            [ "$v" -ge 32 ] && [ "$v" -le 126 ] && s+=$(printf '%b' "$(printf '\\x%02x' "$v")")
        done
        EXPECTED_VER_STR="$s"
        log_dbg "Header file version (0x01): '$EXPECTED_VER_STR'"
    fi
}

# Extract the expected CONFIG_CRC from the .hex itself (it is NOT in the header).
# The CRC is on line (RENESAS_CRC_CONFIG_INDEX * RENESAS_CRC_LINE_STRIDE + RENESAS_CRC_LINE_BASE),
# 1-based; that line is a write record (e.g. "0007C0C6 71FD9F8F D1") whose 4 data bytes are the CRC.
# Sets EXPECTED_CONFIG_CRC (host order, same representation as dma_read32 @0x00F8). Returns 1 if unavailable.
EXPECTED_CONFIG_CRC=""
parse_expected_config_crc() {
    EXPECTED_CONFIG_CRC=""
    local base=$((RENESAS_CRC_LINE_BASE)) stride=$((RENESAS_CRC_LINE_STRIDE)) idx=$((RENESAS_CRC_CONFIG_INDEX))
    local ln=$(( idx * stride + base ))
    [ "$ln" -ge 1 ] || { log_dbg "CRC line number invalid: $ln"; return 1; }

    local raw h
    raw=$(sed -n "${ln}p" "$CONFIG_FILE" 2>/dev/null)
    [ -n "$raw" ] || { log_warn "CRC line $ln not found in $CONFIG_FILE (config index $idx)"; return 1; }
    h=$(normalize_hex_line "$raw")
    [ -n "$h" ] || { log_warn "CRC line $ln is not a valid hex record: '$raw'"; return 1; }

    # NOTE: `mapfile < <(cmd)` exits on mapfile's own status, not cmd's, so hex_to_bytes
    # returning 1 (odd-length line) would be swallowed. Capture first, then check.
    local -a bytes; local _hb
    _hb=$(hex_to_bytes "$h") || return 1
    mapfile -t bytes <<< "$_hb"
    # Need rectype + len + addr8 + cmd + 4 data bytes = at least 8 bytes.
    if [ "${#bytes[@]}" -lt 8 ] || [ "${bytes[0]}" != "0x00" ]; then
        log_warn "CRC line $ln does not look like a 4-byte write record: '$h'"
        return 1
    fi
    EXPECTED_CONFIG_CRC=$(rev4_to_u32 "${bytes[4]#0x}" "${bytes[5]#0x}" "${bytes[6]#0x}" "${bytes[7]#0x}" 2>/dev/null)
    log_dbg "Expected CONFIG_CRC from line $ln (cmd ${bytes[3]}, data ${bytes[4]} ${bytes[5]} ${bytes[6]} ${bytes[7]}): $EXPECTED_CONFIG_CRC"
    return 0
}

# Verify the file belongs to this device.
# IC_DEVICE_ID (0xAD) is the ONLY hard requirement (mismatch => wrong file => abort).
# IC_DEVICE_REV (0xAE) and the version string (0x01) are INFORMATIONAL only and never block.
verify_device_against_header() {
    unbind_driver_for_device

    if [ -n "$EXPECTED_ID_U32" ]; then
        local dev_id; dev_id=$(read_ic_device_id) || { log_error "Failed to read IC_DEVICE_ID"; return 1; }
        if ! eq_u32_hex "$dev_id" "$EXPECTED_ID_U32"; then
            log_error "IC_DEVICE_ID mismatch: this file is NOT for this device (device=$dev_id file=$EXPECTED_ID_U32)"
            return 1
        fi
        log_info "IC_DEVICE_ID match: $dev_id (file is for this device)"
    else
        log_warn "No IC_DEVICE_ID (0xAD) in header; cannot confirm the file matches the device"
    fi

    [ -n "$EXPECTED_VER_STR" ] && log_info "File firmware/config version (header 0x01): $EXPECTED_VER_STR"

    if [ -n "$EXPECTED_REV_U32" ]; then
        local dev_rev; dev_rev=$(read_ic_device_rev) || dev_rev="<read failed>"
        if [ "$dev_rev" = "<read failed>" ]; then
            log_info "IC_DEVICE_REV (info only): device=<read failed> file=$EXPECTED_REV_U32"
        else
            dev_rev=$(and_u32_hex "$dev_rev" 0xFFFFFFFE)
            local file_rev; file_rev=$(and_u32_hex "$EXPECTED_REV_U32" 0xFFFFFFFE)
            log_info "IC_DEVICE_REV (info only): device=$dev_rev file=$file_rev"
        fi
    fi
    return 0
}

# Idempotency: is the device already programmed with this config?
# Compares the live CONFIG_CRC (DMA @0x00F8) against EXPECTED_CONFIG_CRC parsed from the file
# (see parse_expected_config_crc). Sets DEVICE_CONFIG_CRC and ALREADY_PROGRAMMED = yes|no|unknown.
# Never errors out. Safe-by-design: a blank device (0x00000000 / 0xffffffff) is never "yes",
# and if the expected CRC is unknown we report "unknown" (caller then flashes rather than skip).
DEVICE_CONFIG_CRC=""
ALREADY_PROGRAMMED="unknown"
device_already_programmed() {
    ALREADY_PROGRAMMED="unknown"
    local crc
    crc=$(dma_read32 0x00F8 2>/dev/null) || { ALREADY_PROGRAMMED="unknown"; return 0; }
    DEVICE_CONFIG_CRC="$crc"

    # No expected CRC parsed from the file -> cannot decide.
    [ -z "$EXPECTED_CONFIG_CRC" ] && { ALREADY_PROGRAMMED="unknown"; return 0; }

    # Never match an erased/blank CRC value.
    case "$(printf '0x%08x' $((16#${crc#0x})) 2>/dev/null)" in
        0x00000000|0xffffffff) ALREADY_PROGRAMMED="no"; return 0 ;;
    esac

    if eq_u32_hex "$crc" "$EXPECTED_CONFIG_CRC"; then
        ALREADY_PROGRAMMED="yes"
    else
        ALREADY_PROGRAMMED="no"
    fi
    return 0
}

# --------------------------------
# FLASH: execute .hex
# --------------------------------
# Replay the .hex file to the device. Pre-flight (detect, file-vs-device verify,
# already-programmed check, and the "Continue?" prompt) is done once by
# flash_with_redundancy before this function runs.
program_device() {
    [ -f "$CONFIG_FILE" ] || { log_error "Config file not found: $CONFIG_FILE"; return 1; }

    case "${CONFIG_FILE,,}" in
	*.hex) : ;;
	*) log_error "Only .hex files are supported in this Gen3.5 tool: $CONFIG_FILE"; return 1 ;;
    esac

    EXPECTED_ID_U32=""
    EXPECTED_REV_U32=""
    MASK_U32=""

    local header_seen=0
    local header_count=0

    # Determine expected 8-bit address from user input (for warnings only)
    local addr7="${DEVICE_ADDR#0x}"
    local exp_addr8
    exp_addr8=$(printf '0x%02x' $(( (16#$addr7 << 1) & 0xFE )))

    while IFS= read -r rawline || [ -n "$rawline" ]; do
        local h
        h=$(normalize_hex_line "$rawline")
        [ -z "$h" ] && continue

        # Convert to byte list. Capture then map: `mapfile < <(cmd)` ignores cmd's exit
        # status, so an odd-length line (hex_to_bytes -> 1) would otherwise pass silently.
        local -a bytes; local _hb
        _hb=$(hex_to_bytes "$h") || { log_error "Bad hex line (odd length?): $rawline"; return 1; }
        mapfile -t bytes <<< "$_hb"

        # A valid record has at least rectype + len + addr8 + cmd = 4 bytes.
        if [ "${#bytes[@]}" -lt 4 ]; then
            log_error "Malformed record (need >=4 bytes): $rawline"
            return 1
        fi

        local rectype="${bytes[0]}"
        local len="${bytes[1]}"
        local addr8="${bytes[2]}"

        # The 3rd byte of each record is the device's 8-bit write address (7-bit addr << 1),
        # e.g. 0xD0 for 0x68. It is informational only — the tool always uses the -a address.
        # Compare by VALUE (not string) so 0xD0 vs 0xd0 are equal: the .hex stores uppercase hex
        # while exp_addr8 is lowercase, otherwise this warned on every single line. A real
        # difference is harmless (file built for another address) and shown only with -v.
        if [ "$((16#${addr8#0x}))" -ne "$((16#${exp_addr8#0x}))" ]; then
            log_dbg "File record addr8=$addr8 (7-bit $(printf '0x%02x' $((16#${addr8#0x} >> 1)))) differs from -a $DEVICE_ADDR (8-bit $exp_addr8); using -a address"
        fi

        # Header lines (0x49): first 15 are header, do not execute
        if [ "$rectype" = "0x49" ] && [ $header_count -lt "$HEADER_MAX" ]; then
            header_seen=1
            header_count=$((header_count + 1))
            # Need rectype+len+addr8+idcode+...+crc (>=5) before slicing data; a shorter
            # line would make the slice length negative (bash: unintended slice).
            if [ "${#bytes[@]}" -lt 5 ]; then
                log_warn "Malformed header (0x49) line (need >=5 bytes), skipping: $h"
                continue
            fi
            # header: bytes[3] is ID (e.g. AD/AE), bytes[4..(end-2)] data, last is CRC
            local idcode="${bytes[3]}"
            # data bytes exclude last CRC byte
            local -a data=("${bytes[@]:4:$(( ${#bytes[@]} - 5 ))}")
            parse_header_line_49 "$len" "$addr8" "$idcode" "${data[@]}"
            continue
        fi

        # First non-header line reached (device/file compatibility already checked in pre-flight).
        if [ $header_seen -eq 1 ]; then
            header_seen=0
        fi

        case "$rectype" in
            0x00)
                # 00 write: bytes[3]=cmd, bytes[4..(end-2)] data, last is CRC.
                # Need >=5 bytes (cmd + CRC, data optional) so the slice length is never negative.
                [ "${#bytes[@]}" -ge 5 ] || { log_error "Malformed write (0x00) record, need >=5 bytes: $h"; return 1; }
                local cmd="${bytes[3]}"
                local -a data=("${bytes[@]:4:$(( ${#bytes[@]} - 5 ))}")
                execute_write_line "$cmd" "${data[@]}" || return 1
                ;;
            0x10)
                # 10 read+compare: bytes[3]=cmd, bytes[4..7]=expected(4), last CRC
                [ "${#bytes[@]}" -ge 8 ] || { log_error "Malformed read+compare (0x10) record, need >=8 bytes: $h"; return 1; }
                local cmd="${bytes[3]}"
                execute_read_compare_line "$cmd" "${bytes[4]}" "${bytes[5]}" "${bytes[6]}" "${bytes[7]}" || return 1
                ;;
            0x11)
                # 11 poll: bytes[3]=cmd, bytes[4..7]=expected bit mask (4)
                [ "${#bytes[@]}" -ge 8 ] || { log_error "Malformed poll (0x11) record, need >=8 bytes: $h"; return 1; }
                local cmd="${bytes[3]}"
                execute_poll_line "$cmd" "${bytes[4]}" "${bytes[5]}" "${bytes[6]}" "${bytes[7]}" || return 1
                ;;
            0x12)
                # 12 mask: bytes[3..6]=mask(4)
                [ "${#bytes[@]}" -ge 7 ] || { log_error "Malformed mask (0x12) record, need >=7 bytes: $h"; return 1; }
                execute_mask_line "${bytes[3]}" "${bytes[4]}" "${bytes[5]}" "${bytes[6]}" || return 1
                ;;
            0x20)
                # 20 wait: bytes[3]=ms_hi, bytes[4]=ms_lo
                [ "${#bytes[@]}" -ge 5 ] || { log_error "Malformed wait (0x20) record, need >=5 bytes: $h"; return 1; }
                execute_wait_line "${bytes[3]}" "${bytes[4]}" || return 1
                ;;
            *)
                log_warn "Skipping unsupported record type: $rectype"
                ;;
        esac
    done < "$CONFIG_FILE"

    log_info "Programming file execution completed"
    return 0
}


# --------------------------------
# Post-flash verification (Gen3.5)
# --------------------------------

decode_bank_status() {
    # BANK_STATUS via DMA @0x0084; format 0xSTUVWXYZ (Bank7..Bank0)
    # Bits (per nibble):
    # 0x8 Fail: CRC mismatch OTP
    # 0x4 Fail: CRC mismatch RAM
    # 0x2 Reserved
    # 0x1 Bank Written (No Failures)
    # 0x0 Bank Unaffected
    # Source: Gen3.5 programming guide / app note
    local v_hex="$1"  # expects 0xXXXXXXXX
    local x="${v_hex#0x}"
    x=$(echo "$x" | tr '[:upper:]' '[:lower:]')
    printf -v x "%08s" "$x"
    x=${x// /0}
    x=${x: -8}   # keep exactly 8 nibbles (a u32); guards a malformed over-length value

    local fail=0
    local bank=0
    log_info "BANK_STATUS (DMA @0x0084) = 0x$x"
    for bank in 0 1 2 3 4 5 6 7; do
        # bank0 is last nibble (Z), bank7 is first nibble (S)
        local idx=$((7 - bank))
        local nib="${x:$idx:1}"
        local n=$((16#$nib))
        local msg=""
        # Test the fail BITS (0x8 OTP, 0x4 RAM) instead of matching exact nibble values, so a
        # fault bit combined with any other bit (e.g. 0x5, 0x9, 0xC, 0xD) is still reported as a
        # failure. The prior exact-match case treated such combos as "Unknown" and left fail=0,
        # letting post_flash_checks / read_status silently pass a bank CRC mismatch.
        if [ $((n & 0x8)) -ne 0 ] && [ $((n & 0x4)) -ne 0 ]; then
            msg="FAIL: CRC mismatch OTP+RAM" ; fail=1
        elif [ $((n & 0x8)) -ne 0 ]; then
            msg="FAIL: CRC mismatch OTP" ; fail=1
        elif [ $((n & 0x4)) -ne 0 ]; then
            msg="FAIL: CRC mismatch RAM" ; fail=1
        elif [ $((n & 0x1)) -ne 0 ]; then
            msg="Written OK"
        elif [ $((n & 0x2)) -ne 0 ]; then
            msg="Reserved"
        else
            msg="Unaffected"
        fi
        log_info "  Bank $bank: 0x$nib -> $msg"
    done

    return $fail
}

restore_cfg_and_read_crc() {
    local cfg_id="$1"
    cfg_id=$((cfg_id)) 2>/dev/null || cfg_id=0
    cfg_id=$((cfg_id & 0x0F))

    # RESTORE_CFG (0xF2) payload bits[3:0] = config id. Do not use while regulating.
    # Source: Gen3.5 docs/app note.
    log_warn "RESTORE_CFG (0xF2) should NOT be used while regulating."  # documented
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY_RUN] Would RESTORE_CFG id=$cfg_id and read CONFIG_CRC (DMA @0x00F8)"
        return 0
    fi

    i2c_write "$I2C_BUS" "$DEVICE_ADDR" "$CMD_RESTORE_CFG" "0x$(printf '%02x' $cfg_id)" || return 1
    _sleep_frac 0.05

    local crc_hex
    crc_hex=$(dma_read32 0x00F8) || return 1
    log_info "CONFIG_CRC (DMA @0x00F8) after RESTORE_CFG id=$cfg_id : $crc_hex"
    return 0
}

read_nvm_stable() {
    local v1 v2
    v1=$(read_nvm_saves_available 2>/dev/null || echo "")
    _sleep_frac 0.05
    v2=$(read_nvm_saves_available 2>/dev/null || echo "")

    if [ -n "$v2" ]; then
	echo "$v2"
    else
	echo "$v1"
    fi
}

post_flash_checks() {
    # BANK_STATUS
    local bs
    bs=$(dma_read32 0x0084) || { log_warn "BANK_STATUS read failed (DMA @0x0084)"; bs=""; }
    if [ -n "$bs" ]; then
        if ! decode_bank_status "$bs"; then
            log_error "BANK_STATUS indicates failure (CRC mismatch)."
            return 1
        fi
        # Explanation for the common "all banks Unaffected" result:
        # - "Unaffected" = that NVM bank is NOT used by this configuration; this is NORMAL.
        #   A config typically writes only the bank(s) it needs, so most banks stay Unaffected.
        # - A successful program shows "Written OK" on the bank(s) it touched (no FAIL nibbles).
        # - If ALL banks are "Unaffected", no NVM bank was rewritten: usually the config was
        #   already present (CRC unchanged) or only RAM was updated. The new settings become
        #   active after the rail is restarted (power-cycle / OPERATION off->on), not necessarily
        #   immediately. Use 'info'/'verify' to confirm CONFIG_CRC, and power-cycle to apply.
        case "${bs#0x}" in
            0|00|000|0000|00000|000000|0000000|00000000)
                log_info "BANK_STATUS: all banks Unaffected (normal if config unchanged or RAM-only). Power-cycle the rail to apply." ;;
        esac
    fi

    # Optional RESTORE_CFG + CRC
    if [ -n "${RESTORE_CFG_ID:-}" ]; then
        restore_cfg_and_read_crc "$RESTORE_CFG_ID" || {
            log_error "RESTORE_CFG/CRC check failed"
            return 1
        }
    else
        local crc_hex
        crc_hex=$(dma_read32 0x00F8) || crc_hex=""
        [ -n "$crc_hex" ] && log_info "CONFIG_CRC (DMA @0x00F8) (no RESTORE_CFG): $crc_hex"
    fi

    # MCUFLT
    local mf
    mf=$(dma_read32 0xEC01) || { log_warn "MCUFLT read failed (DMA @0xEC01)"; mf=""; }
    if [ -n "$mf" ]; then
        log_info "MCUFLT (DMA @0xEC01) = $mf"
        if ! eq_u32_hex "$mf" "0x00000000"; then
            log_error "MCUFLT indicates errors (expected 0x00000000)."
            return 1
        fi
    fi

    return 0
}

# Parse the file header (first HEADER_MAX 0x49 lines) without touching the device.
# Populates EXPECTED_ID_U32 / EXPECTED_REV_U32 / EXPECTED_VER_STR.
# Sets HEADER_LINES_PARSED. Returns 1 only on unreadable file.
HEADER_LINES_PARSED=0
scan_file_header() {
    EXPECTED_ID_U32=""; EXPECTED_REV_U32=""; EXPECTED_VER_STR=""
    HEADER_LINES_PARSED=0
    local rawline h
    local -a bytes
    while IFS= read -r rawline || [ -n "$rawline" ]; do
        h=$(normalize_hex_line "$rawline")
        [ -z "$h" ] && continue
        local _hb; _hb=$(hex_to_bytes "$h") || return 1
        mapfile -t bytes <<< "$_hb"
        [ "${bytes[0]}" = "0x49" ] || break
        # Header line must have rectype+len+addr8+idcode+...+crc (>=5) before slicing.
        if [ "${#bytes[@]}" -lt 5 ]; then
            log_warn "Malformed header line in $CONFIG_FILE (need >=5 bytes): $h"
            break
        fi
        local idcode="${bytes[3]}"
        local -a data=("${bytes[@]:4:$(( ${#bytes[@]} - 5 ))}")
        parse_header_line_49 "${bytes[1]}" "${bytes[2]}" "$idcode" "${data[@]}"
        HEADER_LINES_PARSED=$((HEADER_LINES_PARSED + 1))
        [ "$HEADER_LINES_PARSED" -ge "$HEADER_MAX" ] && break
    done < "$CONFIG_FILE"
    return 0
}

# One-time pre-flight before flashing: detect device, parse header, confirm the file
# matches this device (IC_DEVICE_ID), report version + live CONFIG_CRC, and decide whether
# the device is already programmed with this config (sets ALREADY_PROGRAMMED). No writes.
preflight_check() {
    detect_device || return 1
    [ -f "$CONFIG_FILE" ] || { log_error "Config file not found: $CONFIG_FILE"; return 1; }

    case "${CONFIG_FILE,,}" in
        *.hex) : ;;
        *) log_error "Only .hex files are supported in this Gen3.5 tool: $CONFIG_FILE"; return 1 ;;
    esac

    scan_file_header || { log_error "Failed to read file header: $CONFIG_FILE"; return 1; }
    [ "$HEADER_LINES_PARSED" -eq 0 ] && log_warn "No header (0x49...) at start of file; cannot confirm file/device match"

    # IC_DEVICE_ID match is mandatory (wrong file => abort); REV/version are informational.
    verify_device_against_header || return 1

    # Expected CONFIG_CRC comes from a data line of the file (not the header).
    parse_expected_config_crc || log_warn "Could not read expected CONFIG_CRC from file; idempotency check disabled (will program)."

    device_already_programmed
    case "$ALREADY_PROGRAMMED" in
        yes) log_info "CONFIG_CRC: device=$DEVICE_CONFIG_CRC matches file expected=$EXPECTED_CONFIG_CRC => ALREADY PROGRAMMED" ;;
        no)  log_info "CONFIG_CRC: device=${DEVICE_CONFIG_CRC:-N/A} differs from file expected=${EXPECTED_CONFIG_CRC:-N/A} => needs programming" ;;
        *)   log_info "CONFIG_CRC: device=${DEVICE_CONFIG_CRC:-N/A}; expected CRC unavailable => cannot decide (will program unless skipped)" ;;
    esac
    return 0
}

flash_with_redundancy() {
    local rep=${REDUNDANCY:-1}
    [ "$rep" -lt 1 ] 2>/dev/null && rep=1
    local until_full=${REPEAT_UNTIL_FULL:-0}

    # Pre-flight ONCE: detect, verify file<->device, report version/CONFIG_CRC, idempotency.
    preflight_check || return 1

    # Program even if the chip already matches the file when the user explicitly asks to:
    #   -F (force), -r N (N>1 repeats), or -r max (repeat until NVM full).
    local force_flash=$FORCE_FLASH
    { [ "$rep" -gt 1 ] || [ "$until_full" -eq 1 ]; } && force_flash=1

    if [ "$ALREADY_PROGRAMMED" = "yes" ]; then
        if [ "$force_flash" -eq 0 ]; then
            log_info "Device already programmed with this configuration -> skipping flash."
            log_info "  To re-flash anyway: -F (once), -r N (N times), or -r max (repeat until NVM saves are exhausted)."
            return 0
        fi
        log_warn "Device already programmed; re-flashing anyway as requested (each run consumes one NVM save)."
    fi

    # A CRC difference means we are about to OVERWRITE a different configuration: make it explicit.
    if [ "$ALREADY_PROGRAMMED" = "no" ]; then
        log_warn "Chip configuration DIFFERS from file (device CONFIG_CRC=${DEVICE_CONFIG_CRC:-N/A} vs file=${EXPECTED_CONFIG_CRC:-N/A}); flashing will OVERWRITE the current config."
    elif [ "$ALREADY_PROGRAMMED" = "unknown" ]; then
        log_warn "Could not confirm the chip's current configuration (CONFIG_CRC=${DEVICE_CONFIG_CRC:-N/A}); flashing will (re)program the device."
    fi

    # Confirm ONCE before any device write. The flash NEVER writes without this confirmation
    # in interactive mode; -y is the explicit opt-out for batch/automation. Dry-run never prompts.
    if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
        local confirm=""
        read -r -p "Proceed and overwrite the chip with $CONFIG_FILE ? (yes/no): " confirm || { log_error "Non-interactive environment? use -y"; return 1; }
        confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
        [[ "$confirm" =~ ^(yes|y)$ ]] || { log_info "Cancelled"; return 1; }
    fi

    # Read initial NVM saves
    local saves_before saves_after used
    saves_before=$(read_nvm_saves_available) || {
        log_warn "Unable to read NVM saves available (DMA @0x0035). Continuing without slot checks."
        saves_before=""
    }

    if [ -n "$saves_before" ]; then
        log_info "NVM saves available (before): $saves_before"
        if [ "$saves_before" -le 0 ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                log_warn "No NVM saves available (0). A real flash would be refused; continuing dry-run (no writes)."
            else
                log_error "No NVM saves available (0). Cannot program."
                return 1
            fi
        fi
    fi

    local i=1
    local used_per_run=""
    local safety_cap=64   # hard upper bound for -r max, in case NVM accounting misbehaves

    while : ; do
        # ----- stop conditions (before each run) -----
        if [ "$until_full" -eq 1 ]; then
            if [ "$i" -gt "$safety_cap" ]; then
                log_warn "Safety cap reached ($safety_cap runs); stopping '-r max'."
                break
            fi
            if [ -z "$saves_before" ]; then
                # Without NVM accounting we cannot detect exhaustion: do one run only.
                [ "$i" -gt 1 ] && { log_warn "No NVM accounting available; stopping '-r max' after 1 run."; break; }
            else
                local need=${used_per_run:-1}
                if [ "$saves_before" -le 0 ] || [ "$saves_before" -lt "$need" ]; then
                    log_info "NVM saves exhausted (remaining=$saves_before, need >= $need) -> stopping after $((i - 1)) run(s)."
                    break
                fi
            fi
        else
            [ "$i" -le "$rep" ] || break
            # If we learned used_per_run, check remaining before next run
            if [ -n "$saves_before" ] && [ -n "$used_per_run" ] && [ "$saves_before" -lt "$used_per_run" ]; then
                log_error "Not enough NVM saves for redundancy run $i/$rep: remaining=$saves_before needed=$used_per_run"
                return 1
            fi
        fi

        # ----- one programming run -----
        if [ "$until_full" -eq 1 ]; then
            log_info "Programming run $i (repeat until NVM full): $CONFIG_FILE  (NVM saves left: ${saves_before:-N/A})"
        elif [ "$rep" -gt 1 ]; then
            log_info "Redundancy run $i/$rep: programming $CONFIG_FILE  (NVM saves left: ${saves_before:-N/A})"
        fi

        program_device || return 1
        post_flash_checks || return 1

        # After run, re-check NVM saves and compute delta
        if [ -n "$saves_before" ]; then
	_sleep_frac 0.1
	saves_after=$(read_nvm_stable)

            if [ -n "$saves_after" ]; then
                used=$((saves_before - saves_after))
                [ "$used" -lt 0 ] && used=0

                # If the HEX contains multiple configs, used may be > 1 (multi-config)
                log_info "NVM saves available (after run $i): $saves_after  (used this run: $used)"

                # '-r max' means "keep programming until NVM is full". If a run consumed
                # ZERO saves (RAM-only / config already matches so nothing is persisted),
                # further runs would also consume 0 -> we would spin uselessly up to the
                # safety cap. Stop now instead.
                if [ "$until_full" -eq 1 ] && [ "$used" -eq 0 ]; then
                    log_warn "Run $i consumed 0 NVM saves (RAM-only / nothing to persist); stopping '-r max'."
                    saves_before="$saves_after"
                    break
                fi

                # Learn how many saves this file consumes per run (first run establishes baseline)
                if [ -z "$used_per_run" ] && [ "$used" -gt 0 ]; then
                    used_per_run="$used"
                    # For fixed redundancy, fail early if there aren't enough saves for all runs.
                    if [ "$until_full" -eq 0 ]; then
                        local remaining_runs=$((rep - i))
                        local needed_more=$((used_per_run * remaining_runs))
                        if [ "$saves_after" -lt "$needed_more" ]; then
                            log_error "Not enough NVM saves to complete redundancy: remaining=$saves_after needed_for_remaining_runs=$needed_more (used_per_run=$used_per_run)"
                            return 1
                        fi
                    fi
                fi

                saves_before="$saves_after"
            else
                log_warn "Unable to read NVM saves after run $i. Skipping further slot accounting."
                saves_before=""
                # Without accounting, '-r max' cannot know when to stop -> stop now.
                [ "$until_full" -eq 1 ] && { log_warn "Stopping '-r max' (no NVM accounting after run $i)."; break; }
            fi
        fi

        i=$((i + 1))
    done

    [ "$until_full" -eq 1 ] && log_info "Completed $((i - 1)) programming run(s) until NVM exhaustion."
    return 0
}

verify_mode() {
    detect_device || return 1
    [ -f "$CONFIG_FILE" ] || { log_error "Config file not found: $CONFIG_FILE"; return 1; }

    # Parse ALL header lines (fixes prior off-by-one that skipped the last header line,
    # so e.g. IC_DEVICE_REV / CONFIG fields on the 4th line were missed).
    scan_file_header || { log_error "Failed to read file header: $CONFIG_FILE"; return 1; }

    if [ "$HEADER_LINES_PARSED" -eq 0 ]; then
        log_warn "No header (0x49...) found at start of file; cannot verify file/device versions"
        return 1
    fi

    # IC_DEVICE_ID match (mandatory); REV/version informational.
    verify_device_against_header || return 1

    # Expected CONFIG_CRC from a data line of the file (not the header).
    parse_expected_config_crc || log_warn "Could not read expected CONFIG_CRC from file."

    # Report whether the device is already programmed with this config (no writes).
    device_already_programmed
    case "$ALREADY_PROGRAMMED" in
        yes) log_info "Result: device is ALREADY PROGRAMMED with this file (CONFIG_CRC=$DEVICE_CONFIG_CRC)" ;;
        no)  log_info "Result: device is NOT programmed with this file (device CONFIG_CRC=${DEVICE_CONFIG_CRC:-N/A}, file expects=${EXPECTED_CONFIG_CRC:-N/A})" ;;
        *)   log_info "Result: cannot determine programmed state (device CONFIG_CRC=${DEVICE_CONFIG_CRC:-N/A}; expected CRC unavailable)" ;;
    esac
    return 0
}

scan_bus() {
    log_info "I2C Bus $I2C_BUS Device Map:"
    i2cdetect -y "$I2C_BUS"
}

monitor_telemetry() {
    local bus=$1 addr=$2 interval=${3:-1}
    I2C_BUS=$bus DEVICE_ADDR=$addr

    detect_device || return 1
    unbind_driver_for_device

    log_info "Monitoring device telemetry (press any key to exit and rebind driver)"
    log_info "Bus: $bus, Address: $addr, Interval: ${interval}s"
    echo ""

    while true; do
        echo "=== Renesas DMP Device Monitor ==="
        echo "Time: $(date)"
        echo "Bus: $bus, Address: $addr"
        echo ""

        # Try PAGE 0 and 1 like Infineon (if unsupported, reads may fail -> N/A)
        for page in 0 1; do
            echo "--- Page $page ---"
            i2cset -y "$bus" "$addr" $PMBUS_PAGE $page 2>/dev/null || true

            local vin vout iout temp pout pin st
            vin=$(i2cget -y "$bus" "$addr" $PMBUS_READ_VIN w 2>/dev/null || echo "N/A")
            vout=$(i2cget -y "$bus" "$addr" $PMBUS_READ_VOUT w 2>/dev/null || echo "N/A")
            iout=$(i2cget -y "$bus" "$addr" $PMBUS_READ_IOUT w 2>/dev/null || echo "N/A")
            temp=$(i2cget -y "$bus" "$addr" $PMBUS_READ_TEMPERATURE_1 w 2>/dev/null || echo "N/A")
            pout=$(i2cget -y "$bus" "$addr" $PMBUS_READ_POUT w 2>/dev/null || echo "N/A")
            pin=$(i2cget -y "$bus" "$addr" $PMBUS_READ_PIN w 2>/dev/null || echo "N/A")
            st=$(i2cget -y "$bus" "$addr" $PMBUS_STATUS_BYTE 2>/dev/null || echo "N/A")

            echo "  VIN:              $vin"
            echo "  VOUT:             $vout"
            echo "  IOUT:             $iout"
            echo "  TEMP:             $temp"
            echo "  POUT:             $pout"
            echo "  PIN:              $pin"
            echo "  STATUS_BYTE:      $st"
            echo ""
        done

        # Extra Renesas programming health (quick glance)
        local nvm bs mf
        nvm=$(dma_read32 0x0035 2>/dev/null || echo "")
        bs=$(dma_read32 0x0084 2>/dev/null || echo "")
        mf=$(dma_read32 0xEC01 2>/dev/null || echo "")
        [ -n "$nvm" ] && echo "NVM_SAVES_AVAILABLE: $nvm"
        [ -n "$bs" ] && echo "BANK_STATUS:         $bs"
        [ -n "$mf" ] && echo "MCUFLT:              $mf"
        echo ""

        echo "Press any key to exit (rebind driver)..."
        read -t "$interval" -n 1 2>/dev/null && break
        echo ""
    done
    return 0
}

dump_registers() {
    local bus=$1 addr=$2 output_file=${3:-""}
    I2C_BUS=$bus DEVICE_ADDR=$addr

    detect_device || return 1
    unbind_driver_for_device

    {
        echo "Renesas DMP Register Dump (PMBus cmd 0x00..0xFF, best-effort)"
        echo "Date: $(date)"
        echo "Bus: $bus, Address: $addr"
        echo ""
        printf "%-8s %-10s\n" "Reg" "Value"
        echo "----------------------------------------"

        local reg hex_reg value dec ascii
	printf "%-8s %-12s\n" "Addr" "DMA32"
	echo "----------------------------------------"

	for reg in $(seq 0 255); do
	    hex_reg=$(printf "0x%04x" $reg)

	    val=$(dma_read32 "$hex_reg" 2>/dev/null)

	    if [ -n "$val" ]; then
		printf "%-8s %-12s\n" "$hex_reg" "$val"
	    else
		printf "%-8s %-12s\n" "$hex_reg" "N/A"
	    fi
	done

        echo ""
	echo "=== DMA REGISTERS ==="

	print_dma_field "FW_STATE"          0x0031
	print_dma_field "FW_STATUS"         0x0032
	print_dma_field "PATCH_VERSION"     0x0030

	print_dma_field "IC_DEVICE_ID"      0xE0AD
	print_dma_field "IC_DEVICE_REV"     0xE0AE

	print_dma_field "MCUFLT"            0xEC01
	print_dma_field "DIAGFLT"           0xEC02

	print_dma_field "STATUS_WORD_LO"    0xE079 0 15
	print_dma_field "STATUS_WORD_HI"    0xE079 16 31

	print_dma_field "SERIAL_RAW"        0xE9FF
	print_dma_field "UNIQUE_SERIAL"     0xE9FF 15 31

	echo ""
	echo "=== NVM / PROGRAMMING STATUS ==="

	nvm_hex=$(dma_read32 0x0035 2>/dev/null || echo "")
	if [ -n "$nvm_hex" ]; then
	  nvm=$((16#${nvm_hex#0x} & 0xFF))
	  echo "  NVM_SAVES_AVAILABLE   : $nvm_hex (count=$nvm)"
	else
	  echo "  NVM_SAVES_AVAILABLE   : N/A"
	fi

	print_dma_field "BANK_STATUS"       0x0084
	print_dma_field "CONFIG_CRC"        0x00F8
	print_dma_field "MCUFLT_CONFIRM"    0xEC01
    } | if [ -n "$output_file" ]; then
        tee "$output_file"
        log_info "Register dump saved to: $output_file"
    else
        cat
    fi

    return 0
}

read_pmbus_block_string() {
    local bus="$1"
    local addr="$2"
    local cmd="$3"

    # Route through i2c_read_n -> i2c_rw_wrapper for retry (and PEC). It returns bytes
    # WITHOUT a 0x prefix, so parse with 16# below.
    local raw
    raw=$(i2c_read_n "$bus" "$addr" "$cmd" 32) || return 1

    set -- $raw

    # First byte is the SMBus block length; clamp to the number of bytes actually returned.
    local len=$(( 16#${1#0x} ))
    shift
    local avail=$#
    [ "$len" -gt "$avail" ] && len="$avail"

    # nessuna stringa
    if [ "$len" -le 0 ]; then
        echo ""
        return 0
    fi

    local out=""
    local i=0 b val c
    for b in "$@"; do
        [ "$i" -ge "$len" ] && break

        # ignora byte non ASCII printable
        val=$(( 16#${b#0x} ))
        if [ "$val" -ge 32 ] && [ "$val" -le 126 ]; then
            # Two-step so \xNN is actually interpreted (single-step printf "\x%02x" emits
            # the literal string "\xNN" -> "missing hex digit"). Matches parse_header_line_49.
            printf -v c '%b' "$(printf '\\x%02x' "$val")"
            out+="$c"
        fi

        i=$((i+1))
    done

    echo "$out"
}


read_device_info() {
    local bus=$1 addr=$2
    I2C_BUS=$bus DEVICE_ADDR=$addr

    detect_device || return 1
    unbind_driver_for_device


    log_info "Reading device information (DMA)..."
    log_info "Device: Bus $bus, Address $addr"

    # ---- DMA CORE INFO ----
    local fw_state fw_status patch_version
    local ic_id ic_rev mcu_flt diag_flt status_word serial

    fw_state=$(dma_read32 0x0031 2>/dev/null || echo "N/A")
    fw_status=$(dma_read32 0x0032 2>/dev/null || echo "N/A")
    patch_version=$(dma_read32 0x0030 2>/dev/null || echo "N/A")

    ic_id=$(dma_read32 0xE0AD 2>/dev/null || echo "N/A")
    ic_rev=$(dma_read32 0xE0AE 2>/dev/null || echo "N/A")

    mcu_flt=$(dma_read32 0xEC01 2>/dev/null || echo "N/A")
    diag_flt=$(dma_read32 0xEC02 2>/dev/null || echo "N/A")

    status_word=$(dma_read32 0xE079 2>/dev/null || echo "N/A")

    serial=$(dma_read32 0xE9FF 2>/dev/null || echo "N/A")

    # ---- PRINT ----
    log_info "  $(printf '%-24s' 'FW_STATE'): $fw_state"
    log_info "  $(printf '%-24s' 'FW_STATUS'): $fw_status"
    log_info "  $(printf '%-24s' 'PATCH_VERSION'): $patch_version"

    log_info "  $(printf '%-24s' 'IC_DEVICE_ID'): $ic_id"
    log_info "  $(printf '%-24s' 'IC_DEVICE_REV'): $ic_rev"

    log_info "  $(printf '%-24s' 'MCUFLT'): $mcu_flt"
    log_info "  $(printf '%-24s' 'DIAGFLT'): $diag_flt"

    # ---- STATUS WORD SPLIT ----
    if [ "$status_word" != "N/A" ]; then
        sw_val=$((16#${status_word#0x}))
        sw_lo=$((sw_val & 0xFFFF))
        sw_hi=$(( (sw_val >> 16) & 0xFFFF ))

        log_info "  $(printf '%-24s' 'STATUS_WORD_LO'): 0x$(printf '%x' $sw_lo)"
        log_info "  $(printf '%-24s' 'STATUS_WORD_HI'): 0x$(printf '%x' $sw_hi)"
    else
        log_info "  $(printf '%-24s' 'STATUS_WORD_LO'): N/A"
        log_info "  $(printf '%-24s' 'STATUS_WORD_HI'): N/A"
    fi

    # ---- SERIAL ----
    log_info "  $(printf '%-24s' 'SERIAL_RAW'): $serial"

    if [ "$serial" != "N/A" ]; then
        ser_val=$((16#${serial#0x}))
        unique=$(( (ser_val >> 15) & 0x1FFFF ))
        log_info "  $(printf '%-24s' 'UNIQUE_SERIAL'): 0x$(printf '%x' $unique)"
    else
        log_info "  $(printf '%-24s' 'UNIQUE_SERIAL'): N/A"
    fi



    # Renesas ID/REV via 0xAD/0xAE (already implemented)
    local id rev
    id=$(read_ic_device_id)  || id="<read failed>"
    rev=$(read_ic_device_rev) || rev="<read failed>"
    log_info "  $(printf '%-24s' 'IC_DEVICE_ID (0xAD)'): $id"
    log_info "  $(printf '%-24s' 'IC_DEVICE_REV(0xAE)'): $rev"

    # Post-flash / programming verification registers (DMA)
    local nvm bs crc mf nvm_cnt
    nvm=$(dma_read32 0x0035 2>/dev/null) || nvm=""
    if [ -n "$nvm" ]; then
        nvm_cnt=$(( 16#${nvm#0x} & 0xFF ))
        log_info "  $(printf '%-24s' 'NVM_SAVES_AVAILABLE'): $nvm (remaining saves: $nvm_cnt / 24)"
    else
        log_info "  $(printf '%-24s' 'NVM_SAVES_AVAILABLE'): N/A"
    fi

    bs=$(dma_read32 0x0084 2>/dev/null) || bs=""
    [ -n "$bs" ] && decode_bank_status "$bs" || true

    crc=$(dma_read32 0x00F8 2>/dev/null) || crc=""
    [ -n "$crc" ] && log_info "  $(printf '%-24s' 'CONFIG_CRC (0x00F8)'): $crc"

    mf=$(dma_read32 0xEC01 2>/dev/null) || mf=""
    [ -n "$mf" ] && log_info "  $(printf '%-24s' 'MCUFLT (0xEC01)'): $mf"

    return 0
}

# Read-only programming status: BANK_STATUS (decoded), CONFIG_CRC, NVM saves, MCUFLT.
# Same info the flash prints in post_flash_checks, but WITHOUT programming (no NVM save
# consumed). Only DMA reads + non-destructive DMA pointer sets (0xC7) are issued.
read_status() {
    local bus=$1 addr=$2
    I2C_BUS=$bus DEVICE_ADDR=$addr

    detect_device || return 1
    unbind_driver_for_device

    log_info "Programming status (read-only) for bus $bus, address $addr:"

    # NVM saves remaining
    local nvm nvm_cnt
    nvm=$(dma_read32 0x0035 2>/dev/null) || nvm=""
    if [ -n "$nvm" ]; then
        nvm_cnt=$(( 16#${nvm#0x} & 0xFF ))
        log_info "NVM_SAVES_AVAILABLE (DMA @0x0035): $nvm (remaining saves: $nvm_cnt / 24)"
    else
        log_warn "NVM saves read failed (DMA @0x0035)"
    fi

    # BANK_STATUS (decoded per bank)
    local bs rc_bank=0
    bs=$(dma_read32 0x0084 2>/dev/null) || bs=""
    if [ -n "$bs" ]; then
        decode_bank_status "$bs" || { rc_bank=1; log_error "BANK_STATUS indicates a failure (CRC mismatch)."; }
        case "${bs#0x}" in
            0|00|000|0000|00000|000000|0000000|00000000)
                log_info "BANK_STATUS: all banks Unaffected (no bank rewritten since last power-up, or config unchanged)." ;;
        esac
    else
        log_warn "BANK_STATUS read failed (DMA @0x0084)"
    fi

    # CONFIG_CRC
    local crc
    crc=$(dma_read32 0x00F8 2>/dev/null) || crc=""
    [ -n "$crc" ] && log_info "CONFIG_CRC (DMA @0x00F8): $crc"

    # MCUFLT
    local mf
    mf=$(dma_read32 0xEC01 2>/dev/null) || mf=""
    if [ -n "$mf" ]; then
        log_info "MCUFLT (DMA @0xEC01): $mf"
        eq_u32_hex "$mf" "0x00000000" || log_warn "MCUFLT non-zero (fault flags set)."
    fi

    return $rc_bank
}

# --------------------------------
# Main
# --------------------------------
main() {
    MODE=${1:-}
    shift || true

    local OPTIND
    local MONITOR_INTERVAL=1
    local OUTPUT_FILE=""
    local PEC_CLI_SET=0   # 1 once an explicit -P0/-P1 is seen, so env I2C_PEC cannot override it

    while getopts "P:b:a:f:r:S:i:o:nyvhF" opt; do
        case $opt in
            P)
                case "$OPTARG" in
                    0|no|off|false) USE_I2C_PEC=0; PEC_CLI_SET=1 ;;
                    1|yes|on|true)  USE_I2C_PEC=1; PEC_CLI_SET=1 ;;
                    *) log_error "Invalid -P$OPTARG (use -P0 or -P1)"; usage ;;
                esac
                ;;
            b) I2C_BUS=$OPTARG ;;
            a) DEVICE_ADDR=$OPTARG ;;
            f) CONFIG_FILE=$OPTARG ;;
            r) case "${OPTARG,,}" in
                   max|all|full|nvm) REPEAT_UNTIL_FULL=1 ;;
                   *) REDUNDANCY=$OPTARG ;;
               esac ;;
            S) RESTORE_CFG_ID=$OPTARG ;;
            i) MONITOR_INTERVAL=$OPTARG ;;
            o) OUTPUT_FILE=$OPTARG ;;
            n) DRY_RUN=1 ;;
            F) FORCE_FLASH=1 ;;
            y) ASSUME_YES=1 ;;
            v) VERBOSE=$((VERBOSE + 1)) ;;
            h) usage 0 ;;
            *) usage ;;
        esac
    done

    HEADER_MAX=4   # Gen3.5: HEX header uses first 4 lines 

    # Env I2C_PEC is only a fallback default; an explicit -P0/-P1 on the command line wins.
    if [ "${PEC_CLI_SET:-0}" -eq 0 ]; then
        case "${I2C_PEC:-}" in
            0|no|off|false) USE_I2C_PEC=0 ;;
            1|yes|on|true)  USE_I2C_PEC=1 ;;
        esac
    fi
    if [ "${USE_I2C_PEC:-0}" -eq 1 ]; then
        I2C_XFER_FLAGS="-f -y"
        log_info "SMBus PEC enabled"
    else
        I2C_XFER_FLAGS="-y"
    fi

    # normalize addr format
    if [ -n "$DEVICE_ADDR" ] && [[ ! "$DEVICE_ADDR" == 0x* ]]; then
        DEVICE_ADDR="0x$DEVICE_ADDR"
    fi

    # --- Validate numeric inputs early: a safety tool must reject bad -b/-a/-r/-i/-S up
    #     front rather than let `$(( ... ))` throw arithmetic errors mid-flow. ---
    if [ -n "$I2C_BUS" ] && ! [[ "$I2C_BUS" =~ ^[0-9]+$ ]]; then
        log_error "Invalid bus -b '$I2C_BUS' (expected a non-negative integer)"; exit 1
    fi
    if [ -n "$DEVICE_ADDR" ]; then
        if ! [[ "$DEVICE_ADDR" =~ ^0x[0-9a-fA-F]+$ ]]; then
            log_error "Invalid address -a '$DEVICE_ADDR' (expected hex, e.g. 0x60)"; exit 1
        fi
        # Reject addresses outside the valid 7-bit I2C range (0x03..0x77): a safety tool must not
        # target a reserved/general-call address or an out-of-range value that i2ctransfer would
        # otherwise mangle. 0x00..0x02 and 0x78..0x7F are reserved; anything > 0x7F is not 7-bit.
        if [ "$((DEVICE_ADDR))" -lt 3 ] || [ "$((DEVICE_ADDR))" -gt 119 ]; then
            log_error "Address -a '$DEVICE_ADDR' out of valid 7-bit I2C range (0x03..0x77)"; exit 1
        fi
    fi
    if [ "$REPEAT_UNTIL_FULL" -eq 0 ] && ! [[ "$REDUNDANCY" =~ ^[0-9]+$ ]]; then
        log_error "Invalid -r '$REDUNDANCY' (expected a positive integer or 'max')"; exit 1
    fi
    if ! [[ "$MONITOR_INTERVAL" =~ ^[0-9]+$ ]] || [ "$MONITOR_INTERVAL" -lt 1 ]; then
        log_error "Invalid -i '$MONITOR_INTERVAL' (expected a positive integer, seconds)"; exit 1
    fi
    if [ -n "$RESTORE_CFG_ID" ] && { ! [[ "$RESTORE_CFG_ID" =~ ^[0-9]+$ ]] || [ "$RESTORE_CFG_ID" -gt 15 ]; }; then
        log_error "Invalid -S '$RESTORE_CFG_ID' (expected a Configuration ID 0..15)"; exit 1
    fi

    check_dependencies || { log_error "Dependency check failed"; exit 1; }

    # Rebind on exit (skip for unbind/rebind modes). Trap SIGINT/TERM/HUP too, not just
    # EXIT: a Ctrl-C during the confirm prompt or a long sleep (poll/wait) could otherwise
    # leave the kernel i2c driver unbound on a live power rail.
    if [ "$MODE" != "unbind" ] && [ "$MODE" != "rebind" ]; then
        trap 'rebind_driver_if_unbound' EXIT INT TERM HUP
    fi

    case "$MODE" in
        flash)
            [ -n "$I2C_BUS" ] && [ -n "$DEVICE_ADDR" ] && [ -n "$CONFIG_FILE" ] || { log_error "flash requires -b -a -f"; usage; }
            flash_with_redundancy
            ;;
        verify)
            [ -n "$I2C_BUS" ] && [ -n "$DEVICE_ADDR" ] && [ -n "$CONFIG_FILE" ] || { log_error "verify requires -b -a -f"; usage; }
            verify_mode
            ;;
        info)
            [ -n "$I2C_BUS" ] && [ -n "$DEVICE_ADDR" ] || { log_error "info requires -b -a"; usage; }
            read_device_info "$I2C_BUS" "$DEVICE_ADDR"
            ;;
        status|bank|bankstatus)
            [ -n "$I2C_BUS" ] && [ -n "$DEVICE_ADDR" ] || { log_error "status requires -b -a"; usage; }
            read_status "$I2C_BUS" "$DEVICE_ADDR"
            ;;
        scan)
            [ -n "$I2C_BUS" ] || { log_error "scan requires -b"; usage; }
            scan_bus
            ;;
        monitor)
            [ -n "$I2C_BUS" ] && [ -n "$DEVICE_ADDR" ] || { log_error "monitor requires -b -a"; usage; }
            monitor_telemetry "$I2C_BUS" "$DEVICE_ADDR" "$MONITOR_INTERVAL"
            ;;
        dump)
            [ -n "$I2C_BUS" ] && [ -n "$DEVICE_ADDR" ] || { log_error "dump requires -b -a"; usage; }
            dump_registers "$I2C_BUS" "$DEVICE_ADDR" "$OUTPUT_FILE"
            ;;
        unbind)
            [ -n "$I2C_BUS" ] && [ -n "$DEVICE_ADDR" ] || { log_error "unbind requires -b -a"; usage; }
            unbind_driver_for_device
            if [ -z "$DRIVER_UNBIND_DEVID" ] || [ -z "$DRIVER_UNBIND_NAME" ]; then
                log_info "No driver bound (or unbind not needed)"
                exit 0
            fi
            save_unbind_state && log_info "Unbound $DRIVER_UNBIND_NAME from $DRIVER_UNBIND_DEVID; run 'rebind' to restore" || exit 1
            ;;
        rebind)
            rebind_driver_from_state_file || { log_error "No saved unbind state (run unbind first)"; exit 1; }
            ;;
        -h|--help|help|"")
            usage 0
            ;;
        *)
            log_error "Unknown mode: $MODE"
            usage
            ;;
    esac
}

main "$@"