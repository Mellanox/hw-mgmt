#!/bin/bash
#
# Infineon XDPE1x2xx Voltage Regulator Management Tool
# Combined flash and diagnostic utility for Infineon XDPE devices
# Based on: AN001-XDPE1x2xx Programming Guide
#

# Note: set -e removed to allow proper handling of interactive prompts
# and graceful error handling in automated environments

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
I2C_BUS=""
DEVICE_ADDR=""
CONFIG_FILE=""
VERIFY_ONLY=0
DRY_RUN=0
# Flash: skip "Continue? (yes/no)" prompt (non-interactive / batch)
ASSUME_YES=0
VERBOSE=0
MODE=""
# Flash only one section by HeaderCode (e.g. -s 0x0B); empty = flash all sections
FLASH_SECTION_HC=""
# Cached 4-byte scratchpad memory address from CMD_GET_SCRATCHPAD_ADDR (0x2e), e.g. 0x2005e000; set once per run.
SCPAD_HEX_ADDR=""

# When the kernel driver (e.g. xdpe1a2g7b) is bound, raw i2cget/i2cset cannot access the device.
# We unbind the driver for verify/flash and rebind on exit.
DRIVER_UNBIND_DEVID=""
DRIVER_UNBIND_NAME=""
# State file for unbind/rebind modes (so rebind can run in a separate invocation)
UNBIND_STATE_FILE="/var/run/hw-management/vr_dpc_infineon_unbound"
# Scratchpad (0xD0) accepts only a multi-byte block write; the I2C adapter must support i2ctransfer block writes.

# SMBus PEC (CRC-8): default on (same algorithm as Infineon PEC examples, e.g. head-example-0324-0x66.sh).
# Disable with -P0 or I2C_PEC=0; override with -P1 / I2C_PEC=1.
USE_I2C_PEC=1
I2C_XFER_FLAGS="-f -y"
# Transient I²C retries (see head-example-0324-0x66.sh). Override with env I2C_MAX_RETRY / I2C_RETRY_DELAY.
I2C_MAX_RETRY=3
I2C_RETRY_DELAY=0.05

# PMBus/MFR Specific Commands
PMBUS_PAGE=0x00
PMBUS_OPERATION=0x01
PMBUS_CLEAR_FAULTS=0x03
PMBUS_WRITE_PROTECT=0x10
PMBUS_MFR_ID=0x99
PMBUS_MFR_MODEL=0x9A
PMBUS_MFR_REVISION=0x9B
PMBUS_MFR_LOCATION=0x9C
PMBUS_MFR_DATE=0x9D
PMBUS_MFR_SERIAL=0x9E
PMBUS_MFR_DEVICE_ID=0xAD
PMBUS_VOUT_MODE=0x20
PMBUS_STATUS_WORD=0x79
PMBUS_STATUS_BYTE=0x78
PMBUS_STATUS_CML=0x7E
PMBUS_READ_VIN=0x88
PMBUS_READ_VOUT=0x8B
PMBUS_READ_IOUT=0x8C
PMBUS_READ_TEMPERATURE_1=0x8D
PMBUS_READ_POUT=0x96
PMBUS_READ_PIN=0x97

# MFR specific registers
MFR_FW_COMMAND=0xFE
MFR_FW_COMMAND_DATA=0xFD
MFR_SPECIFIC_00=0xD0
MFR_RPTR=0xCE
MFR_REG_WRITE=0xDE
MFR_REG_READ=0xDF

# AN001 Table 4 commands (0xFE register)
CMD_SCRATCHPAD_WRITE=0x01
CMD_OTP_CONFIG_STORE=0x11
CMD_OTP_SECTION_INVALIDATE=0x12
CMD_OTP_PARTITION_SIZE_REMAINING=0x10
CMD_FW_VERSION=0x01
CMD_GET_CRC=0x2D
CMD_GET_SCRATCHPAD_ADDR=0x2e

# OTP partition 0 base (AN001 10.1)
OTP_BASE=0x10020000

# Header Codes for configuration sections (AN001). Full flash (no -s): invalidate HCs not listed in the config file.
OTP_SECTION_HC_ALL=(0x04 0x07 0x09 0x0A 0x0B 0x0D 0x0E 0x0F 0x11)

usage() {
    cat << EOF
Infineon XDPE1x2xx Voltage Regulator Management Tool

USAGE: $(basename $0) <mode> [options]

MODES:
    flash       Program device with configuration file
    verify      Verify device configuration
    scan        Scan I2C bus for Infineon devices
    info        Read device information
    monitor     Monitor device telemetry
    dump        Dump device registers
    unbind      Unbind kernel driver for device (raw I2C access)
    rebind      Rebind kernel driver previously unbound with 'unbind'
    scpad-addr  Get scratchpad register address (controllers supporting 0x2e)
    parse       Convert .txt/.mic to .bin then show AN001 sections; or parse .bin by sections (-o = section dir for .bin only)
    readback    Read OTP sections from device to read_NN.bin; with -f .txt compare to config
    readback-all   Read full 32 KB OTP to outdir/otp-full.bin
    compare     Compare two configuration files

FLASH MODE OPTIONS:
    Required:
        -b <bus>        I2C bus number (e.g., 0, 1, 2)
        -a <addr>       Device I2C address in hex (e.g., 0x40)
        -f <file>       Configuration file path

    Optional:
        -s <hc>         Flash only section(s) with this HeaderCode (e.g. -s 0x0B); parse full config, invalidate and upload only matching section(s)
        -n              Skip finalize (dry run): write to scratchpad only, do not upload to OTP or reset
        -y              Do not prompt for confirmation before OTP-changing flash steps (non-interactive)
        -P0 | -P1       SMBus PEC for i2ctransfer helpers (append CRC-8; verify on reads). Default is PEC on (-P1). Use -P0 to disable. Env I2C_PEC=0 or =1 overrides after parsing -P.
        -v              Verbose: repeat for more (-v = verbose, -vv = debug)

    Environment (optional, I2C flash path):
        I2C_MAX_RETRY   Transient I2C retries per op (default 3; minimum 1). Same role as max_retry in Infineon PEC examples.
        I2C_RETRY_DELAY Seconds between attempts (default 0.05).

    After each scratchpad write, data is read back to <file>.scpad and compared; mismatch aborts flash.
    For .txt/.mic flash: section .bin live in a temp dir during the run; after the section loop (including -n dry run) they are copied to <config_basename>_flash_work/ (.bin, .params, .scpad per flashed section). Direct -f *.bin keeps *.bin.scpad next to the .bin.
    Full .txt/.mic flash (no -s): if the file contains "Configuration Checksum : 0x........" and it matches the device total OTP CRC (GET_CRC with header code 0), programming is skipped (no prompt, no invalidate). Otherwise: invalidate only OTP sections whose Header Code is not present in the file (known HC list). Per-section upload is skipped if GET_CRC matches section_crc_expected (see .params): Partial PMBus (HC 0x0B) builds <section>_crc_input.bin during .txt parse (LE bytes of 3rd DWORD on each 000 row + LE bytes of the DWORD on the following 010 row), then crc32(1) on that file; other sections use the last 4 bytes LE of the section .bin. Requires crc32 in PATH for 0x0B expected CRC.

SCAN MODE OPTIONS:
    -b <bus>            I2C bus number

INFO MODE OPTIONS:
    -b <bus>            I2C bus number
    -a <addr>           Device I2C address

MONITOR MODE OPTIONS:
    -b <bus>            I2C bus number
    -a <addr>           Device I2C address
    -i <interval>       Update interval in seconds (default: 1)

DUMP MODE OPTIONS:
    -b <bus>            I2C bus number
    -a <addr>           Device I2C address
    -o <file>           Output file (optional)

UNBIND MODE OPTIONS:
    -b <bus>            I2C bus number
    -a <addr>           Device I2C address (hex, e.g. 0x6c)

REBIND MODE OPTIONS:
    (none)              Rebinds the device saved by last 'unbind'

SCPAD-ADDR MODE OPTIONS:
    -b <bus>            I2C bus number
    -a <addr>           Device I2C address (hex, e.g. 0x6c)

PARSE MODE OPTIONS:
    -f <file>           Configuration file path (.bin = parse by AN001 sections; .txt/.mic = convert to binary)
    -o <path>           Output: .bin path when converting .txt/.mic; or output dir for section_*_hc_*.bin when parsing .bin

READBACK MODE OPTIONS:
    -b <bus>            I2C bus number (required)
    -a <addr>           Device I2C address in hex (required)
    -f <file>           Optional: .txt/.mic config; if given, read sections by header code and compare with config
    -o <dir>            Output directory for read_NN.bin files (default: current dir). Without -f, all OTP sections are dumped in order.

READBACK-ALL MODE OPTIONS:
    -b <bus>            I2C bus number
    -a <addr>           Device I2C address
    -o <dir>            Output directory (default: current dir). Writes otp-full.bin (32 KB).
    Note: Readback requires I2C/SMBus block write and block read. If your adapter does not support these, use another I2C adapter or skip readback.

COMPARE MODE OPTIONS:
    -f <file1>          First configuration file
    -c <file2>          Second configuration file

EXAMPLES:
    # Flash device (-n = scratchpad only, no OTP upload)
    $(basename $0) flash -b 2 -a 0x40 -f config.bin -n
    $(basename $0) flash -b 2 -a 0x40 -f config.bin
    $(basename $0) flash -y -b 2 -a 0x40 -f config.bin   # no confirmation prompt
    # Flash only section(s) with HeaderCode 0x0B (e.g. Partial PMBus)
    $(basename $0) flash -b 2 -a 0x40 -f config.txt -s 0x0B

    # Verify configuration
    $(basename $0) verify -b 2 -a 0x40 -f config.bin

    # Scan bus for devices
    $(basename $0) scan -b 2

    # Read device info
    $(basename $0) info -b 2 -a 0x40

    # Monitor telemetry
    $(basename $0) monitor -b 2 -a 0x40 -i 2

    # Dump registers
    $(basename $0) dump -b 2 -a 0x40 -o dump.txt

    # Parse/analyze binary config or convert .txt to .bin
    $(basename $0) parse -f config.bin
    $(basename $0) parse -f config.txt -o config.bin

    # Readback: dump all OTP sections to read_NN.bin (no config)
    $(basename $0) readback -b 2 -a 0x6c -o ./readback
    # Readback with config: read by section header and compare with .txt
    $(basename $0) readback -f config.txt -b 2 -a 0x6c -o ./readback

    # Compare configs
    $(basename $0) compare -f old.bin -c new.bin

EOF
    exit 1
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [ "${VERBOSE:-0}" -gt 1 ]; then
        echo -e "[DEBUG] $1" >&2
    fi
}

# Log to stderr when -v (verbose) is set; -vv enables log_debug as well
log_verbose() {
    if [ "${VERBOSE:-0}" -gt 0 ]; then
        echo -e "[VERBOSE] $1" >&2
    fi
}

# Byte hex/decimal dump: BusyBox od often lacks -t/-A (see VV-notes). hexdump -e '1/1 "…"' works on BusyBox + util-linux.
_od_hex_n() {
    local n=$1 f=$2
    hexdump -v -n "$n" -e '1/1 "%02x"' "$f" 2>/dev/null
}

# Whole file -> space-separated lowercase hex bytes (scratchpad array / dword walk).
_od_hex_all_spaced() {
    local f=$1
    hexdump -v -e '1/1 "%02x "' "$f" 2>/dev/null | sed 's/[[:space:]]*$//'
}

# Last 4 bytes as unsigned decimal octets (one line: b0 b1 b2 b3) for LE dword from tail.
_od_tail4_u1() {
    tail -c 4 "$1" | hexdump -v -n 4 -e '1/1 "%u "' 2>/dev/null | sed 's/[[:space:]]*$//'
}

# 7-bit address -> SMBus slave write address byte (W=0).
_pec_slave_w() {
    local a="${1#0x}"
    echo $(( (16#$a << 1) & 0xff ))
}

# Slave read address byte (R=1) from write-address byte.
_pec_slave_r() {
    echo $(( ($1 | 1) & 0xff ))
}

# SMBus PEC: CRC-8 over all listed bytes (decimal or 0x hex). Prints e.g. 0x76 (no newline).
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

# Single i2ctransfer entry point (Infineon head-example i2c_rw_prefix style + PEC + I2C_MAX_RETRY).
# Usage: i2c_rw_wrapper <bus> <addr> <readlen> <wkm1> [write_byte ...]
#   readlen — 0 = write only; >0 = read this many payload bytes (adds 1 on wire when USE_I2C_PEC).
#   wkm1    — (count of write bytes) minus 1; the following args must be exactly wkm1+1 bytes (first is often PMBus command reg).
# On read success: prints space-separated hex (no 0x), readlen tokens. On write success: returns 0.
# Mapping:  i2c_block_write reg+d[]     -> i2c_rw_wrapper b a 0 ${#d[@]} reg "${d[@]}"
#           i2c_write reg + data[]      -> i2c_rw_wrapper b a 0 ${#data[@]} reg "${data[@]}"
#           i2c_send_byte reg           -> i2c_rw_wrapper b a 0 0 reg
#           i2c_block_read N          -> i2c_rw_wrapper b a N 0 reg
#           i2c_read byte             -> i2c_rw_wrapper b a 1 0 reg  (w1 + r(N+PEC); same block-read PEC rule as head-example read path)
i2c_rw_wrapper() {
    local bus=$1 addr=$2 readlen=$3 wkm1=$4
    shift 4
    local -a wb
    wb=("$@")
    local nwb=${#wb[@]}
    local expect=$((wkm1 + 1))
    if [ "$nwb" -ne "$expect" ]; then
        log_error "i2c_rw_wrapper: expected $expect write bytes, got $nwb"
        return 1
    fi
    readlen=$(($readlen))
    wkm1=$(($wkm1))
    local max="${I2C_MAX_RETRY:-3}"
    [ "$max" -lt 1 ] 2>/dev/null && max=1
    local delay="${I2C_RETRY_DELAY:-0.05}"
    local attempt=0 addr_w addr_r raw line p_rx expected j pec_args wp
    local -a rd

    addr_w=$(_pec_slave_w "$addr")
    addr_r=$(_pec_slave_r "$addr_w")

    if [ "$readlen" -eq 0 ]; then
        while [ $attempt -lt "$max" ]; do
            if [ "${USE_I2C_PEC:-0}" -eq 1 ]; then
                wp=$(calc_pec "$addr_w" "${wb[@]}")
                log_debug "i2ctransfer $I2C_XFER_FLAGS $bus w$((nwb + 1))@$addr ${wb[*]} $wp # PEC"
                if i2ctransfer $I2C_XFER_FLAGS $bus "w$((nwb + 1))@$addr" "${wb[@]}" "$wp"; then
                    return 0
                fi
            else
                log_debug "i2ctransfer -y $bus w${nwb}@$addr ${wb[*]} # no PEC"
                if i2ctransfer -y $bus "w${nwb}@$addr" "${wb[@]}"; then
                    return 0
                fi
            fi
            attempt=$((attempt + 1))
            [ $attempt -lt "$max" ] && { log_verbose "i2c_rw_wrapper write retry $attempt/$max"; sleep "$delay"; }
        done
        log_error "i2c_rw_wrapper write failed after $max attempts"
        return 1
    fi

    local nread=$readlen
    [ "${USE_I2C_PEC:-0}" -eq 1 ] && nread=$((readlen + 1))
    attempt=0
    while [ $attempt -lt "$max" ]; do
        if [ "${USE_I2C_PEC:-0}" -eq 1 ]; then
            log_debug "i2ctransfer $I2C_XFER_FLAGS $bus w${nwb}@$addr ${wb[*]} r${nread} # PEC"
            raw=$(i2ctransfer $I2C_XFER_FLAGS $bus "w${nwb}@$addr" "${wb[@]}" "r${nread}") || {
                attempt=$((attempt + 1))
                [ $attempt -lt "$max" ] && { log_verbose "i2c_rw_wrapper read retry $attempt/$max"; sleep "$delay"; }
                continue
            }
        else
            log_debug "i2ctransfer -y $bus w${nwb}@$addr ${wb[*]} r${readlen} # no PEC"
            raw=$(i2ctransfer -y $bus "w${nwb}@$addr" "${wb[@]}" "r${readlen}") || {
                attempt=$((attempt + 1))
                [ $attempt -lt "$max" ] && { log_verbose "i2c_rw_wrapper read retry $attempt/$max"; sleep "$delay"; }
                continue
            }
        fi
        line=$(echo "$raw" | sed 's/0x//g')
        read -ra rd <<< "$line"
        if [ "${USE_I2C_PEC:-0}" -eq 1 ]; then
            [ "${#rd[@]}" -lt $((readlen + 1)) ] && {
                attempt=$((attempt + 1))
                [ $attempt -lt "$max" ] && sleep "$delay"
                continue
            }
            p_rx=$(printf '0x%02x' $((16#${rd[readlen]})))
            pec_args=("$addr_w" "${wb[@]}" "$addr_r")
            for ((j = 0; j < readlen; j++)); do
                pec_args+=("0x${rd[j]}")
            done
            expected=$(calc_pec "${pec_args[@]}")
            if [ "$p_rx" != "$expected" ]; then
                attempt=$((attempt + 1))
                [ $attempt -lt "$max" ] && { log_verbose "i2c_rw_wrapper PEC mismatch $p_rx vs $expected, retry $attempt/$max"; sleep "$delay"; }
                continue
            fi
        else
            [ "${#rd[@]}" -lt "$readlen" ] && {
                attempt=$((attempt + 1))
                [ $attempt -lt "$max" ] && sleep "$delay"
                continue
            }
        fi
        echo "$(printf '%s ' "${rd[@]:0:readlen}" | sed 's/[[:space:]]*$//')"
        return 0
    done
    log_error "i2c_rw_wrapper read failed after $max attempts"
    return 1
}

# Send single byte (command only, no data) — e.g. PMBUS_CLEAR_FAULTS per SMBus "send byte".
i2c_send_byte() {
    local bus=$1 addr=$2 reg=$3
    i2c_rw_wrapper "$bus" "$addr" 0 0 "$reg"
}

# Execute i2c command with error handling (reg + data bytes → i2ctransfer via i2c_rw_wrapper).
i2c_write() {
    local bus=$1 addr=$2 reg=$3
    shift 3
    local data=("$@")
    if [ ${#data[@]} -eq 0 ]; then
        i2c_rw_wrapper "$bus" "$addr" 0 0 "$reg"
    else
        i2c_rw_wrapper "$bus" "$addr" 0 "${#data[@]}" "$reg" "${data[@]}"
    fi
}

i2c_read() {
    local bus=$1 addr=$2 reg=$3
    local length=${4:-1}
    local line b max delay attempt result

    if [ "$length" = "0" ]; then
        log_error "i2c_read: length 0 invalid (writes use i2c_write / i2c_rw_wrapper readlen=0)"
        return 1
    fi

    if [ "$length" = "1" ]; then
        line=$(i2c_rw_wrapper "$bus" "$addr" 1 0 "$reg") || return 1
        b=$(echo "$line" | awk '{print $1}')
        if [ "${USE_I2C_PEC:-0}" -eq 1 ]; then
            log_debug "i2c_read byte: 0x$b # PEC"
        else
            log_debug "i2c_read byte: 0x$b # no PEC"
        fi
        echo -n "0x$b"
        return 0
    fi

    max="${I2C_MAX_RETRY:-3}"
    [ "$max" -lt 1 ] 2>/dev/null && max=1
    delay="${I2C_RETRY_DELAY:-0.05}"
    attempt=0
    while [ $attempt -lt "$max" ]; do
        result=$(i2cget -y $bus $addr $reg w)
        if [ $? -eq 0 ]; then
            log_debug "i2cget result: $result"
            echo -n "$result"
            return 0
        fi
        attempt=$((attempt + 1))
        [ $attempt -lt "$max" ] && { log_verbose "I2C i2cget word retry $attempt/$max"; sleep "$delay"; }
    done
    log_error "Failed to read word from device after $max attempts"
    return 1
}

# Write one DWORD (4 bytes) to reg. For RPTR use with length prefix: write_dword bus addr MFR_RPTR 0x04 b0 b1 b2 b3.
# For scratchpad use without prefix: write_dword bus addr MFR_SPECIFIC_00 b0 b1 b2 b3.
# All addresses and config data in little-endian (b0=LSB, b3=MSB).
write_dword() {
    local bus=$1
    local addr=$2
    local reg=$3
    shift 3
    i2c_block_write $bus $addr $reg "$@"
}

# Block read: write reg (1 byte), then read N bytes. Returns space-separated hex bytes (no 0x).
i2c_block_read() {
    local bus=$1 addr=$2 reg=$3 num_bytes=${4:-4}
    local line
    line=$(i2c_rw_wrapper "$bus" "$addr" "$num_bytes" 0 "$reg") || return 1
    line=$(echo "$line" | sed 's/0x//g')
    if [ "${USE_I2C_PEC:-0}" -eq 1 ]; then
        log_debug "block read result: $line # PEC"
    else
        log_debug "block read result: $line # no PEC"
    fi
    echo "$line"
    return 0
}

# BLOCK_READ(MFR_FW_COMMAND_DATA, 5): byte0 = block length, must be 4; bytes 1..4 = payload (hex tokens, no 0x).
# Echoes four space-separated hex byte tokens (same as former d1..d4 after length check).
read_dword_bytes() {
    local bus=$1 addr=$2
    local line d0 d1 d2 d3 d4
    line=$(i2c_block_read "$bus" "$addr" "$MFR_FW_COMMAND_DATA" 5) || return 1
    read -r d0 d1 d2 d3 d4 <<< "$line" || return 1
    if (( 16#${d0:-0} != 4 )); then
        log_error "read_dword_bytes: expected block length 4 (0x04), got 0x${d0:-?} (bus=$bus addr=$addr reg=$MFR_FW_COMMAND_DATA)"
        return 1
    fi
    echo "$d1 $d2 $d3 $d4"
}

# Same block read as read_dword_bytes; interprets the four payload bytes as little-endian uint32.
# Prints one line: 0xXXXXXXXX (8 lowercase hex digits).
read_dword_u32() {
    local bus=$1 addr=$2
    local line d1 d2 d3 d4
    line=$(read_dword_bytes "$bus" "$addr") || return 1
    read -r d1 d2 d3 d4 <<< "$line" || return 1
    [ -z "$d1" ] && return 1
    printf '0x%08x\n' $(( 16#$d1 + (16#$d2 << 8) + (16#$d3 << 16) + (16#$d4 << 24) ))
}

# Retrieve scratchpad register address for controllers that support CMD_GET_SCRATCHPAD_ADDR (0x2e).
# Sequence: BLOCK_WRITE(0xFD, 4, 2,0,0,0), WRITE_BYTE(0xFE, 0x2e), wait ~500us, BLOCK_READ(0xFD, 5).
# Response: block length 0x04 then 4-byte scratchpad address LE (e.g. 0x2005e000). read_dword_bytes/u32 enforce length.
# Prints one line only: 32-bit addr as 0xXXXXXXXX (scratchpad flow uses PMBus reg 0x04 / phase — not echoed).
# If payload is 0xffffffff (all 0xff), treat as invalid and return empty (use default 0xD0).
get_scratchpad_address() {
    local bus=$1
    local addr=$2

    # BLOCK_WRITE(PMB_Addr, 0xfd, 4, 2, 0, 0, 0)
    write_dword $bus $addr $MFR_FW_COMMAND_DATA 0x04 0x02 0x00 0x00 0x00 || return 1
    # WRITE_BYTE(0xfe, 0x2e)
    i2c_write $bus $addr $MFR_FW_COMMAND $CMD_GET_SCRATCHPAD_ADDR || return 1
    sleep 0.001
    local addr_hex
    addr_hex=$(read_dword_u32 "$bus" "$addr") || return 1
    log_debug "BLOCK_READ(0xfd,5) response: 0x04 payload LE $addr_hex"
    [ "$addr_hex" = "0xffffffff" ] && return 1
    printf '%s\n' "$addr_hex"
    return 0
}

# Run get_scratchpad_address and print result (for manual use via 'scpad-addr' mode).
# Usage: get_scpad_addr <bus> <addr>
get_scpad_addr() {
    local bus=$1
    local addr=$2
    local addr4
    log_info "Querying scratchpad address (CMD_GET_SCRATCHPAD_ADDR 0x2e)..."
    local full
    full=$(get_scratchpad_address "$bus" "$addr") || true
    addr4=$(echo "$full" | head -n1)
    if [ -n "$addr4" ]; then
        log_info "Scratchpad: PMBus reg 0x04 (for writes), 4-byte addr: $addr4"
        SCPAD_HEX_ADDR="$addr4"
        return 0
    else
        log_warn "Controller did not return scratchpad address; default is MFR_SPECIFIC_00 (0xD0)"
        echo "$MFR_SPECIFIC_00"
        return 1
    fi
}

# Multi-byte write: reg + data via i2ctransfer only (no SMBus block / i2cset block).
i2c_block_write() {
    local bus=$1 addr=$2 reg=$3
    shift 3
    local data=("$@")
    if ! i2c_rw_wrapper "$bus" "$addr" 0 "${#data[@]}" "$reg" "${data[@]}"; then
        log_error "Failed i2c_block_write (i2c_rw_wrapper)"
        return 1
    fi
    return 0
}

# Read one DWORD (4 bytes) from MFR_REG_READ; RPTR must be set and auto-increments.
# Device returns 5 bytes: length (0x04) then 4 data bytes (r5, or r6 with read PEC via i2c_rw_wrapper).
read_otp_dword_hex() {
    local bus=$1 addr=$2
    local line _d0 _d1 _d2 _d3 _d4
    line=$(i2c_rw_wrapper "$bus" "$addr" 5 0 "$MFR_REG_READ") || return 1
    line=$(echo "$line" | sed 's/0x//g')
    read -r _d0 _d1 _d2 _d3 _d4 <<< "$line"
    line="$_d1 $_d2 $_d3 $_d4"
    if [ "${USE_I2C_PEC:-0}" -eq 1 ]; then
        log_debug "read DWORD: $line # PEC"
    else
        log_debug "read DWORD: $line # no PEC"
    fi
    echo "$line"
}

# Append 4 hex bytes (as from read_otp_dword_hex) as binary to file.
hex_dword_to_file() {
    local hex="$1"
    local file="$2"
    local esc=""
    local b
    for b in $hex; do
        esc+="\\x${b}"
    done
    printf '%b' "$esc" >> "$file"
}

# Read num_bytes (multiple of 4) from OTP at current RPTR and append to file. RPTR must be set.
read_otp_bytes_to_file() {
    local bus=$1
    local addr=$2
    local num_bytes=$3
    local out_file=$4
    local count=$((num_bytes / 4))
    local i
    for ((i=0; i<count; i++)); do
        local hex
        hex=$(read_otp_dword_hex $bus $addr) || return 1
        hex_dword_to_file "$hex" "$out_file"
    done
    return 0
}

# True if readback (-f) should concatenate every OTP section with this HC/XV until HC=0x00 (AN001 partial types: 0x0A/0x0B/0x11).
readback_otp_multi_section_hc() {
    case $(($1)) in
        10|11|17) return 0 ;;
        *) return 1 ;;
    esac
}

# Scan OTP from base for sections with the given HC (and XV).
# Optional 6th arg concat_all (default 1): 1 = append every matching section until HC=0x00 (partial types); 0 = read first match only then return.
read_otp_sections_by_hc_until_stop() {
    local bus=$1
    local addr=$2
    local header_code=$(( $3 ))
    local xvcode=$(( ${4:-0} ))
    local out_file=$5
    local concat_all="${6:-1}"
    local addr_32=$((OTP_BASE))
    local max_addr=$((OTP_BASE + 32768))
    local max_iters=512
    local iters=0
    local count=0

    : > "$out_file" || return 1
    if [ "$concat_all" -eq 1 ]; then
        log_verbose "Reading all OTP sections with HC=0x$(printf '%02x' $header_code) XV=0x$(printf '%02x' $xvcode) until HC=0x00..."
    else
        log_verbose "Reading first OTP section with HC=0x$(printf '%02x' $header_code) XV=0x$(printf '%02x' $xvcode)..."
    fi

    while (( addr_32 < max_addr && iters < max_iters )); do
        iters=$((iters + 1))
        set_rptr $bus $addr $addr_32 || return 1
        local hd_hex sz_hex
        hd_hex=$(read_otp_dword_hex $bus $addr) || return 1
        sz_hex=$(read_otp_dword_hex $bus $addr) || return 1
        local h0 h1 h2 h3 s0 s1 s2 s3
        read -r h0 h1 h2 h3 <<< "$hd_hex"
        read -r s0 s1 s2 s3 <<< "$sz_hex"
        local size=$(( 16#$s0 + (16#$s1 << 8) ))
        local hc=$((16#$h0))
        local xv=$((16#$h1))
        if [ "$size" -gt 32768 ]; then
            size=8
        fi
        local pr_otp
        pr_otp="OTP offset $(printf '0x%04x' $((addr_32 - OTP_BASE)))"
        if [ "$hc" -eq 0 ]; then
            log_verbose "$pr_otp HC=0x00 (stop) -- done"
            return 0
        fi
        if [ "$size" -le 0 ]; then
            log_error "Invalid OTP section size 0 at 0x$(printf '%x' $addr_32)"
            return 1
        fi
        if [ "$hc" -eq "$header_code" ] && [ "$xv" -eq "$xvcode" ]; then
            hex_dword_to_file "$hd_hex" "$out_file"
            hex_dword_to_file "$sz_hex" "$out_file"
            if [ $size -gt 8 ]; then
                read_otp_bytes_to_file $bus $addr $((size - 8)) "$out_file" || return 1
            fi
            count=$((count + 1))
            log_verbose "Appended section $count (size 0x$(printf '%04x' $size))"
            [ "$concat_all" -eq 0 ] && return 0
        fi
        addr_32=$((addr_32 + size))
    done
    log_info "Read $count section(s) with HC=0x$(printf '%02x' $header_code) (stopped at max addr or iterations)"
    return 0
}

# Set register pointer RPTR to 32-bit address (little-endian per AN001).
# BLOCK_WRITE(PMB_Addr, RPTR, 4, b0, b1, b2, b3) -> reg, length 0x04, then 4 bytes LE.
set_rptr() {
    local bus=$1
    local addr=$2
    local addr_32=$3
    local b0=$(( (addr_32)       & 0xff ))
    local b1=$(( (addr_32 >> 8)  & 0xff ))
    local b2=$(( (addr_32 >> 16) & 0xff ))
    local b3=$(( (addr_32 >> 24) & 0xff ))
    write_dword $bus $addr $MFR_RPTR 0x04 0x$(printf '%02x' $b0) 0x$(printf '%02x' $b1) 0x$(printf '%02x' $b2) 0x$(printf '%02x' $b3) || return 1
    return 0
}

# Check if required tools are installed. Optional tools set HAS_* for use elsewhere.
check_dependencies() {
    log_debug "Checking dependencies..."

    local missing=0
    for cmd in i2cdetect i2cget i2cset i2ctransfer cmp hexdump awk tail dd head tr; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        log_error "Install missing packages (e.g. i2c-tools, diffutils for cmp; hexdump + awk + tail + head + dd + tr — typically BusyBox or util-linux)"
        return 1
    fi

    HAS_MD5SUM=""
    HAS_SHA256SUM=""
    HAS_CRC32=""
    command -v md5sum &> /dev/null && HAS_MD5SUM=1
    command -v sha256sum &> /dev/null && HAS_SHA256SUM=1
    command -v crc32 &> /dev/null && HAS_CRC32=1

    log_debug "All dependencies satisfied"
    return 0
}

# Detect device on I2C bus
detect_device() {
    log_info "Detecting device at address $DEVICE_ADDR on bus $I2C_BUS..."

    local i2c_out
    i2c_out=$(i2cdetect -y $I2C_BUS $DEVICE_ADDR $DEVICE_ADDR)
    local addr_hex
    addr_hex=$(printf '%02x' $((DEVICE_ADDR)))
    # Accept either the address hex (device probed) or "UU" (address in use by kernel driver)
    if ! echo "$i2c_out" | grep -qi "$addr_hex" && ! echo "$i2c_out" | grep -q "UU"; then
        log_error "Device not detected at address $DEVICE_ADDR on bus $I2C_BUS"
        return 1
    fi

    log_info "Device detected"
    return 0
}

# Unbind kernel driver so raw i2cget/i2cset can access the device (device shows as UU when bound).
# Idempotent: no-op if already unbound or unbind not possible. Sets globals for rebind on exit.
unbind_driver_for_device() {
    [ -n "$I2C_BUS" ] && [ -n "$DEVICE_ADDR" ] || return 0
    local addr_hex
    addr_hex=$(printf '%02x' $((DEVICE_ADDR)))
    local dev_id_4="${I2C_BUS}-$(printf '%04x' $((DEVICE_ADDR)))"
    local dev_id_2="${I2C_BUS}-${addr_hex}"
    local dev_path=""
    for id in "$dev_id_4" "$dev_id_2"; do
        if [ -d "/sys/bus/i2c/devices/$id" ]; then
            dev_path="/sys/bus/i2c/devices/$id"
            break
        fi
    done
    [ -z "$dev_path" ] && return 0
    [ -L "$dev_path/driver" ] || return 0
    local driver_link
    driver_link=$(readlink "$dev_path/driver" 2>/dev/null) || return 0
    local driver_name
    driver_name=$(basename "$driver_link" 2>/dev/null) || return 0
    local unbind_file="/sys/bus/i2c/drivers/$driver_name/unbind"
    [ -f "$unbind_file" ] || return 0
    local dev_id
    dev_id=$(basename "$dev_path")
    if echo "$dev_id" > "$unbind_file"; then
        DRIVER_UNBIND_DEVID="$dev_id"
        DRIVER_UNBIND_NAME="$driver_name"
        sleep 0.2
    fi
    return 0
}

# Diagnostic: read registers that xdpe1a2g7b driver uses for "Chip identification" (PMBUS_MFR_ID, PMBUS_MFR_MODEL, PMBUS_VOUT_MODE on both pages).
# Call with bus and addr (e.g. from I2C_BUS, DEVICE_ADDR). Logs values so user can see why probe might fail.
# Driver expects PMBUS_VOUT_MODE (0x20) lower 5 bits = 0x1E (NVIDIA 195mV) on both pages when in VID mode.
diagnose_rebind_id_regs() {
    local bus=$1
    local addr=$2
    [ -z "$bus" ] || [ -z "$addr" ] && return 0
    log_info "--- Pre-rebind identification read (bus $bus $addr) ---"
    local mfr_id mfr_model vout0 vout1
    mfr_id=$(i2c_read "$bus" "$addr" $PMBUS_MFR_ID)
    mfr_model=$(i2c_read "$bus" "$addr" $PMBUS_MFR_MODEL)
    i2c_write "$bus" "$addr" $PMBUS_PAGE 0x00
    vout0=$(i2c_read "$bus" "$addr" $PMBUS_VOUT_MODE)
    i2c_write "$bus" "$addr" $PMBUS_PAGE 0x01
    vout1=$(i2c_read "$bus" "$addr" $PMBUS_VOUT_MODE)
    log_info "  PMBUS_MFR_ID(0x99)=${mfr_id:-<read failed>}  PMBUS_MFR_MODEL(0x9A)=${mfr_model:-<read failed>}"
    log_info "  PMBUS_VOUT_MODE(0x20) page0=${vout0:-<read failed>}  page1=${vout1:-<read failed>}"
    log_info "  (xdpe1a2g7b expects PMBUS_VOUT_MODE low 5 bits = 0x1E on both pages for VID; 0xff or mismatch -> Chip identification failed)"
}

# Rebind the driver if we had unbound it (so device works again under the kernel driver).
# Waits REBIND_DELAY seconds before bind so device can complete reset (avoids "Chip identification failed" on probe).
rebind_driver_if_unbound() {
#return 0; # VV: Skip rebinding for now
    [ -n "$DRIVER_UNBIND_DEVID" ] && [ -n "$DRIVER_UNBIND_NAME" ] || return 0
    local bind_file="/sys/bus/i2c/drivers/$DRIVER_UNBIND_NAME/bind"
    if [ ! -f "$bind_file" ]; then
        DRIVER_UNBIND_DEVID=""
        DRIVER_UNBIND_NAME=""
        return 0
    fi
    local delay=${REBIND_DELAY:-1}
    if [ "$delay" -gt 0 ] 2>/dev/null; then
        log_debug "Waiting ${delay}s for device to be ready after reset before rebind..."
        sleep "$delay"
    fi
    if [ "${REBIND_DEBUG:-0}" -eq 1 ] 2>/dev/null; then
        local bus addr
        bus="${DRIVER_UNBIND_DEVID%-*}"
        addr="0x${DRIVER_UNBIND_DEVID##*-}"
        diagnose_rebind_id_regs "$bus" "$addr"
    fi
    if echo "$DRIVER_UNBIND_DEVID" > "$bind_file"; then
        log_info "Driver $DRIVER_UNBIND_NAME rebound to $DRIVER_UNBIND_DEVID"
    else
        log_warn "Rebind of $DRIVER_UNBIND_NAME to $DRIVER_UNBIND_DEVID failed (device may need more time or power cycle)"
        local bus addr
        bus="${DRIVER_UNBIND_DEVID%-*}"
        addr="0x${DRIVER_UNBIND_DEVID##*-}"
        diagnose_rebind_id_regs "$bus" "$addr"
    fi
    DRIVER_UNBIND_DEVID=""
    DRIVER_UNBIND_NAME=""
    return 0
}

# Save unbound device info to state file (for 'rebind' mode in a separate run).
save_unbind_state() {
    [ -n "$DRIVER_UNBIND_DEVID" ] && [ -n "$DRIVER_UNBIND_NAME" ] || return 1
    local dir
    dir=$(dirname "$UNBIND_STATE_FILE")
    mkdir -p "$dir" 2>/dev/null || return 1
    echo "$DRIVER_UNBIND_DEVID" > "$UNBIND_STATE_FILE" 2>/dev/null || return 1
    echo "$DRIVER_UNBIND_NAME" >> "$UNBIND_STATE_FILE" 2>/dev/null || return 1
    return 0
}

# Load state file and rebind (for 'rebind' mode).
rebind_driver_from_state_file() {
    [ -f "$UNBIND_STATE_FILE" ] || return 1
    DRIVER_UNBIND_DEVID=$(sed -n '1p' "$UNBIND_STATE_FILE" 2>/dev/null)
    DRIVER_UNBIND_NAME=$(sed -n '2p' "$UNBIND_STATE_FILE" 2>/dev/null)
    rm -f "$UNBIND_STATE_FILE" 2>/dev/null
    [ -n "$DRIVER_UNBIND_DEVID" ] && [ -n "$DRIVER_UNBIND_NAME" ] || return 1
    rebind_driver_if_unbound
    return 0
}

# Read device identification (uses block read for MFR_* so output matches 'info')
read_device_id() {
    log_info "Reading device identification..."
    unbind_driver_for_device

    local mfr_id
    mfr_id=$(read_device_info_block $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_ID)
    [ -z "$mfr_id" ] && mfr_id=$(i2c_read $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_ID)
    if [ -z "$mfr_id" ]; then
        log_error "Failed to read Manufacturer ID"
        return 1
    fi
    log_info "Manufacturer ID: $mfr_id"

    local mfr_model
    mfr_model=$(read_device_info_block $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_MODEL)
    [ -z "$mfr_model" ] && mfr_model=$(i2c_read $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_MODEL)
    if [ -z "$mfr_model" ]; then
        log_error "Failed to read Model"
        return 1
    fi
    log_info "Model: $mfr_model"

    local mfr_rev
    mfr_rev=$(read_device_info_block $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_REVISION)
    [ -z "$mfr_rev" ] && mfr_rev=$(i2c_read $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_REVISION)
    if [ -z "$mfr_rev" ]; then
        log_error "Failed to read Revision"
        return 1
    fi
    log_info "Revision: $mfr_rev"

    return 0
}

# Clear any existing faults (SMBus send byte: command only, no data)
clear_faults() {
    log_info "Clearing device faults..."
    i2c_send_byte $I2C_BUS $DEVICE_ADDR $PMBUS_CLEAR_FAULTS || return 1
    sleep 0.1
    return 0
}

# Disable write protection
disable_write_protect() {
    log_info "Disabling write protection..."
    i2c_write $I2C_BUS $DEVICE_ADDR $PMBUS_WRITE_PROTECT 0x00 || return 1
    return 0
}

# Enable write protection
enable_write_protect() {
    log_info "Enabling write protection..."
    i2c_write $I2C_BUS $DEVICE_ADDR $PMBUS_WRITE_PROTECT 0x80 || return 1
    return 0
}

# Read OTP partition size remaining in bytes (AN001 ch.9 / Table 4: 0x10 OTP_PARTITION_SIZE_REMAINING).
# Arg3: partition number pn (default 0). Sequence: BLOCK_WRITE(0xFD, 4, 0, 0, 0, pn), WRITE_BYTE(0xFE, 0x10), wait, BLOCK_READ(0xFD, 5).
# Device returns 5 bytes: length (0x04) then 4 data bytes LE; use r5, drop first byte.
get_otp_partition_size_remaining() {
    local bus=$1
    local addr=$2
    local pn="${3:-0}"
    local pn_byte
    pn_byte=$(printf '0x%02x' $((pn & 0xff)))
    write_dword $bus $addr $MFR_FW_COMMAND_DATA 0x04 0x00 0x00 0x00 $pn_byte || return 1
    i2c_write $bus $addr $MFR_FW_COMMAND $CMD_OTP_PARTITION_SIZE_REMAINING || return 1
    sleep 0.5
    local h
    h=$(read_dword_u32 "$bus" "$addr") || return 1
    echo $((h))
    return 0
}

# Get FW UTC date timestamp (AN001: 0x01 FW_VERSION). WRITE_BYTE(0xFE, 0x01), wait 1ms, BLOCK_READ(0xFD, 5).
# Returns Unix timestamp to stdout (4 bytes LE after length byte); empty on failure.
get_fw_timestamp() {
    local bus=$1
    local addr=$2
    i2c_write $bus $addr $MFR_FW_COMMAND $CMD_FW_VERSION || return 1
    sleep 0.001
    local h
    h=$(read_dword_u32 "$bus" "$addr") || return 1
    echo $((h))
    return 0
}

# Get CRC (AN001 8.1, 8.2: 0x2D GET_CRC). Arg3: HeaderCode (0 = total CRC; non-zero = CRC for that section).
# Sequence: BLOCK_WRITE(0xFD, 4, hc, 0, 0, 0), WRITE_BYTE(0xFE, 0x2D), wait 1ms, BLOCK_READ(0xFD, 5).
# Output: 32-bit CRC as one line 0xXXXXXXXX to stdout. Empty on read failure.
get_crc() {
    local bus=$1
    local addr=$2
    local header_code="${3:-0}"
    local hc_byte
    hc_byte=$(printf '0x%02x' $((header_code & 0xff)))
    write_dword $bus $addr $MFR_FW_COMMAND_DATA 0x04 $hc_byte 0x00 0x00 0x00 || return 1
    i2c_write $bus $addr $MFR_FW_COMMAND $CMD_GET_CRC || return 1
    sleep 0.001
    read_dword_u32 "$bus" "$addr" || return 1
    return 0
}

# Check OTP space availability using 0x10 OTP_PARTITION_SIZE_REMAINING; logs result.
check_otp_space() {
    log_info "Checking OTP space availability (0x10 OTP_PARTITION_SIZE_REMAINING)..."
    local remaining
    remaining=$(get_otp_partition_size_remaining $I2C_BUS $DEVICE_ADDR) || return 1
    log_info "OTP partition size remaining: $remaining (0x$(printf '%04x' $remaining)) bytes"
    if [ "$remaining" -eq 0 ]; then
        log_warn "OTP partition full (0 bytes remaining)"
    fi
    return 0
}

# Invalidate existing OTP data (AN-001 6.2 / 6.2.1).
# invalidate_otp 1 = invalidate all: BLOCK_WRITE(0xFD, 4, 0xfe, 0xfe, 0, 0) then WRITE_BYTE(0xFE, 0x12).
# invalidate_otp 0 <hc> <xv> = invalidate one section: BLOCK_WRITE(0xFD, 4, hc, XVcode, 0, 0) then 0x12 (AN001 6.2).
invalidate_otp() {
    local invalidate_all=${1:-1}
    local hc xv

    if [ $invalidate_all -eq 1 ]; then
        log_info "Invalidating entire OTP configuration (AN-001 6.2.1)..."
    else
        hc=$((${2:-0})); xv=$((${3:-0}))
        log_info "Invalidating OTP section (HC=0x$(printf '%02x' $hc) XV=0x$(printf '%02x' $xv))..."
    fi

    if [ $DRY_RUN -eq 1 ]; then
        if [ $invalidate_all -eq 1 ]; then
            log_verbose "[DRY_RUN] Would write 0xFD (0xfe,0xfe,0,0) then 0xFE 0x12 (OTP_SECTION_INVALIDATE); skip actual write"
        else
            log_verbose "[DRY_RUN] Would write 0xFD (hc=0x$(printf '%02x' $hc), xv=0x$(printf '%02x' $xv), 0, 0) then 0xFE 0x12; skip actual write"
        fi
        return 0
    fi

    # AN-001 6.2 / 6.2.1: BLOCK_WRITE(0xFD, 4, ...) then WRITE_BYTE(0xFE, 0x12). All: 0xfe,0xfe,0,0. One section: hc, XVcode, 0, 0 (LE).
    if [ $invalidate_all -eq 1 ]; then
        write_dword $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND_DATA 0x04 0xfe 0xfe 0x00 0x00 || return 1
        if ! i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_OTP_SECTION_INVALIDATE; then
            log_error "OTP invalidation: failed to send command (0xFE 0x12)"
            return 1
        fi
        sleep 1
    else
        write_dword $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND_DATA 0x04 \
            0x$(printf '%02x' $hc) 0x$(printf '%02x' $xv) 0x00 0x00 || return 1
        if ! i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_OTP_SECTION_INVALIDATE; then
            log_error "OTP section invalidation: failed to send command (0xFE 0x12)"
            return 1
        fi
        sleep 1
    fi

    # MFR_FW_COMMAND (0xFE) is read-only; do not read it for status.
    log_info "OTP invalidation command sent"
    return 0
}

# Full programming only: invalidate OTP sections whose Header Code is not in the parsed config.
# Uses AN001 6.2 per-section invalidate with XV=0x00. DRY_RUN delegates to invalidate_otp (no bus writes).
invalidate_otp_sections_not_in_config() {
    declare -A present
    local f fb
    for f in "$@"; do
        [ ! -f "$f" ] && continue
        fb=$(_od_hex_n 1 "$f")
        [ -z "$fb" ] && continue
        present[$((16#$fb))]=1
    done
    local hc dec
    for hc in "${OTP_SECTION_HC_ALL[@]}"; do
        dec=$((hc))
        [ -n "${present[$dec]}" ] && continue
        log_info "OTP section not in config: invalidating HC=0x$(printf '%02x' $dec) (XV=0x00)"
        invalidate_otp 0 "$dec" 0 || return 1
        echo ""
    done
    return 0
}

# Normalize 32-bit CRC to 0x + 8 lowercase hex digits for string compare.
_normalize_crc32_hex() {
    local x="${1#0x}"
    x=$(echo "$x" | tr '[:upper:]' '[:lower:]')
    printf '0x%08x' $((16#$x))
}

# Append one MSB-first hex DWORD as 4 bytes LE (same as section .bin layout).
_append_le_dword_hex_to_file() {
    local outf="$1" dword="$2"
    local b0 b1 b2 b3
    dword=$(echo "$dword" | tr '[:lower:]' '[:upper:]' | tr -d '\r')
    [[ ${#dword} -eq 8 ]] && [[ "$dword" =~ ^[0-9A-F]{8}$ ]] || return 1
    b0=$((16#${dword:0:2})); b1=$((16#${dword:2:2})); b2=$((16#${dword:4:2})); b3=$((16#${dword:6:2}))
    printf '%b' "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' "$b3" "$b2" "$b1" "$b0")" >> "$outf" || return 1
}

# Run crc32(1) on file; print 0x<first field> (no newline). Expects crc32 to emit hex CRC as first token (see HAS_CRC32).
_crc32_cli_to_hex() {
    local f="$1" val
    [ -n "$HAS_CRC32" ] || return 1
    val=$(crc32 "$f" | awk '{print $1}' | tr -d '\r\n') || return 1
    [ -n "$val" ] || return 1
    printf '0x%s' "$val"
}

# After parse: section_crc_expected for GET_CRC pre-check — HC 0x0B: crc32 on 32-byte extract; else last DWORD LE of .bin.
_finalize_section_crc_expected() {
    local pf="$1" bf="$2"
    local hc_line hcval v tmp sz b0 b1 b2 b3 fb crc_in
    [ -f "$bf" ] && [ -s "$bf" ] || return 0
    [ -f "$pf" ] || return 0
    hcval=""
    hc_line=$(grep -i '^hc=' "$pf" 2>/dev/null | head -n 1 || true)
    if [[ "$hc_line" =~ ^[Hh][Cc]=0[xX]([0-9a-fA-F]+) ]]; then
        hcval=$((16#${BASH_REMATCH[1]}))
    fi
    if [ -z "$hcval" ]; then
        fb=$(_od_hex_n 1 "$bf")
        [ "$fb" = "0b" ] && hcval=11
    fi
    v=""
    if [ "$hcval" = "11" ]; then
        crc_in="${bf%.bin}_crc_input.bin"
        if [ ! -s "$crc_in" ]; then
            log_warn "Partial PMBus (0x0B): missing or empty *_crc_input.bin (built during .txt parse); section_crc_expected not set"
            return 0
        fi
        v=$(_crc32_cli_to_hex "$crc_in")
        if [ -z "$v" ]; then
            log_warn "Partial PMBus (0x0B): crc32 missing, failed, or bad output (install crc32, PATH; checked at startup); section_crc_expected not set"
            return 0
        fi
        log_verbose "Partial PMBus: section_crc_expected from crc32($crc_in)"
    else
        sz=$(wc -c < "$bf" 2>/dev/null | tr -d ' ')
        [ "${sz:-0}" -ge 4 ] || return 0
        set -- $(_od_tail4_u1 "$bf")
        [ $# -ge 4 ] || return 0
        b0=$1 b1=$2 b2=$3 b3=$4
        v=$(printf '0x%08x' $(( b0 + (b1 << 8) + (b2 << 16) + (b3 << 24) )))
    fi
    tmp="${pf}.crcstrip.$$"
    # sed (not grep -v): BusyBox grep can exit 1 when stripping yields "no match", aborting append.
    sed '/^section_crc_expected=/d' "$pf" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$pf" || { rm -f "$tmp"; return 1; }
    echo "section_crc_expected=$v" >> "$pf"
}

# Read section_crc_expected= from .params (after parse: crc32 path for 0x0B, else tail dword).
_read_section_crc_expected_from_params() {
    local pf=$1
    local line v
    [ ! -f "$pf" ] && { echo ""; return 0; }
    line=$(grep '^section_crc_expected=' "$pf" 2>/dev/null | head -n 1) || { echo ""; return 0; }
    v="${line#section_crc_expected=}"
    echo "$(echo "$v" | tr -d '\r\n' | sed 's/[[:space:]]*$//')"
}

# Infineon GUI export: "Configuration Checksum : 0x........" before [Configuration Data]. Used for full-flash skip vs GET_CRC(HC=0).
_read_configuration_checksum_from_txt() {
    local f="$1"
    local line hex
    [ -f "$f" ] || { echo ""; return 0; }
    line=$(grep -iE '^[[:space:]]*configuration[[:space:]]+checksum[[:space:]]*:' "$f" 2>/dev/null | head -n 1) || true
    [ -z "$line" ] && { echo ""; return 0; }
    hex="${line#*:}"
    hex=$(echo "$hex" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/#.*//')
    hex=$(echo "$hex" | tr '[:upper:]' '[:lower:]')
    [[ "$hex" =~ ^0x[0-9a-f]{1,8}$ ]] && echo "$hex" || echo ""
}

# Map AN001 Table 7 header code (first DWORD LSB) to short name and optional page (Loop A=0, B=1).
# 0x04=Config, 0x07=PMBus LoopA, 0x09=PMBus LoopB, 0x0A=Config Partial, 0x0B=Partial PMBus, etc.
section_type_name() {
    local code=$1
    case "$code" in
        4)  echo "Config (0x04)" ;;
        7)  echo "PMBus LoopA / page 0 (0x07)" ;;
        9)  echo "PMBus LoopB / page 1 (0x09)" ;;
        10) echo "Config Partial (0x0A)" ;;
        11) echo "Partial PMBus (0x0B)" ;;
        *)  echo "header 0x$(printf '%02x' "$code")" ;;
    esac
}

# Parse XDPE .txt/.mic config (AN001 format) to single binary; write to output path.
# Optional: [Configuration Data], [End Configuration Data], "// XV0 ..." lines. Data rows: "XXX DWORD0 DWORD1 ..." (3-digit hex + 8-char hex DWORDs). Each DWORD = 4 bytes big-endian.
# Optional third arg: quiet=1 — no per-section logs (use when followed by parse_config_file on the .bin).
parse_txt_config_to_bin() {
    local txt_file="$1"
    local bin_file="$2"
    local quiet="${3:-0}"
    local in_config=1
    local byte_count=0
    local current_section_name=""
    local section_dwords=0
    local section_first_dword=""
    # Build binary in memory once; avoid hundreds of `printf >> file` (slow on slow storage / BusyBox).
    local bin_buf=""

    if [ ! -f "$txt_file" ]; then
        log_error "Config file not found: $txt_file"
        return 1
    fi

    log_section_summary() {
        [[ $quiet -eq 1 ]] && return 0
        if [[ $section_dwords -gt 0 ]]; then
            local type_str=""
            if [[ -n "$section_first_dword" ]]; then
                local code=$((16#${section_first_dword:6:2}))
                type_str=$(section_type_name "$code")
            fi
            local name="${current_section_name:-(section)}"
            log_info "  Section: $name"
            [[ -n "$type_str" ]] && log_info "    Type / programming: $type_str"
            log_info "    Data: $section_dwords DWORDs ($(( section_dwords * 4 )) bytes)"
        fi
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^\[Configuration[[:space:]]Data\] ]]; then
            in_config=1
            if [[ $quiet -ne 1 ]]; then
                log_info "Parsing [Configuration Data] from $txt_file"
                echo ""
            fi
            continue
        fi
        if [[ "$line" =~ ^\[End[[:space:]]Configuration[[:space:]]Data\] ]]; then
            log_section_summary
            break
        fi
        [[ $in_config -eq 0 ]] && continue

        if [[ "$line" =~ ^// ]]; then
            current_section_name="${line#//}"
            current_section_name="${current_section_name#"${current_section_name%%[![:space:]]*}"}"
            current_section_name="${current_section_name%"${current_section_name##*[![:space:]]}"}"
            continue
        fi

        if [[ "$line" =~ ^[0-9A-Fa-f]{3}[[:space:]] ]]; then
            # One tr per row (not per DWORD) — avoids hundreds of subshells on .mic/.txt data blocks.
            local rest
            rest="${line#*[[:space:]]}"
            rest=$(printf '%s' "$rest" | tr '[:lower:]' '[:upper:]' | tr -d '\r')
            local dword
            local row_dwords=0
            local _chunk
            for dword in $rest; do
                [[ -z "$dword" ]] || [[ ${#dword} -ne 8 ]] && continue
                [[ ! "$dword" =~ ^[0-9A-F]{8}$ ]] && continue
                local b0 b1 b2 b3
                [[ "${dword:0:2}" =~ ^[0-9A-F]{2}$ ]] && [[ "${dword:2:2}" =~ ^[0-9A-F]{2}$ ]] && \
                [[ "${dword:4:2}" =~ ^[0-9A-F]{2}$ ]] && [[ "${dword:6:2}" =~ ^[0-9A-F]{2}$ ]] || continue
                [[ -z "$section_first_dword" ]] && section_first_dword="$dword"
                b0=$((16#${dword:0:2})); b1=$((16#${dword:2:2})); b2=$((16#${dword:4:2})); b3=$((16#${dword:6:2}))
                # DWORD in .txt is MSB-first; device/OTP use little-endian — write LSB first (b3 b2 b1 b0)
                printf -v _chunk '\\x%02x\\x%02x\\x%02x\\x%02x' "$b3" "$b2" "$b1" "$b0"
                bin_buf+="$_chunk"
                byte_count=$((byte_count + 4))
                row_dwords=$((row_dwords + 1))
            done
            section_dwords=$((section_dwords + row_dwords))
        fi
    done < "$txt_file"

    log_section_summary
    if [[ $byte_count -eq 0 ]]; then
        log_error "No data rows (XXX DWORD...) found in $txt_file"
        rm -f "$bin_file"
        return 1
    fi
    printf '%b' "$bin_buf" > "$bin_file" || { log_error "Cannot write binary: $bin_file"; return 1; }
    if [[ $quiet -ne 1 ]]; then
        echo ""
        log_info "Total: $byte_count bytes written to binary"
    fi
    return 0
}

# Parse .txt/.mic into one binary file per (sub)section (AN001 5.2).
# (Sub)sections start with a line beginning with "000 " (3-digit hex row offset). Optional: [Configuration Data],
# [End Configuration Data], and "// XV0 ..." comment lines. Writes section_NN_hc_XX.bin (same style as readback), .params, and section_list.
# AN001 partial sections may span multiple "000" rows (e.g. HC 0x0A/0x0B/0x11). We concatenate all DWORDs into one
# logical section file and upload with the combined size.
parse_txt_config_to_section_files() {
    local txt_file="$1"
    local out_dir="$2"
    local in_config=1
    local current_section_name=""
    local section_dwords=0
    local section_first_dword=""
    local section_index=0
    local current_section_bin=""
    local current_section_stem=""
    local -a parsed_section_stems=()
    local section_list_file="$out_dir/section_list"
    local in_partial=0
    local first_partial_dword1=""
    local first_partial_dword3=""
    local partial_crc_input_file=""
    local partial_crc_pending_d3=""

    if [ ! -f "$txt_file" ]; then
        log_error "Config file not found: $txt_file"
        return 1
    fi
    mkdir -p "$out_dir" || { log_error "Cannot create output dir: $out_dir"; return 1; }
    : > "$section_list_file" || { log_error "Cannot create section list"; return 1; }

    log_section_summary() {
        if [[ -n "$current_section_bin" && $section_dwords -gt 0 ]]; then
            local type_str=""
            if [[ -n "$section_first_dword" ]]; then
                local code=$((16#${section_first_dword:6:2}))
                type_str=$(section_type_name "$code")
            fi
            local idx=$((section_index - 1))
            local name="${current_section_name:-Section $idx}"
            log_info "  Section: $name"
            [[ -n "$type_str" ]] && log_info "    Type / programming: $type_str"
            log_info "    Data: $section_dwords DWORDs ($(( section_dwords * 4 )) bytes)"
        fi
    }

    start_section_file() {
        local first_dword="$1"
        [[ -z "$first_dword" ]] || [[ ${#first_dword} -ne 8 ]] || [[ ! "$first_dword" =~ ^[0-9A-Fa-f]{8}$ ]] && {
            log_error "start_section_file: bad first dword '$first_dword'"
            return 1
        }
        first_dword=$(printf '%s' "$first_dword" | tr '[:lower:]' '[:upper:]')
        local hc=$((16#${first_dword:6:2}))
        local stem
        stem=$(printf 'section_%02d_hc_%02x' "$section_index" "$hc")
        current_section_stem="$stem"
        current_section_bin="$out_dir/${stem}.bin"
        : > "$current_section_bin" || return 1
        parsed_section_stems+=("$stem")
        echo "$current_section_bin" >> "$section_list_file"
    }

    # Extract and store section header per AN001 5.3 (1st DWORD → 4 bytes b0..b3) and 5.4 (2nd DWORD → size 2 bytes: sz0 LSB, sz1 MSB).
    write_section_params() {
        local dword1="$1"
        local dword2="$2"
        local dword3="${3:-}"
        [[ -z "$dword1" ]] || [[ ${#dword1} -ne 8 ]] || [[ ! "$dword1" =~ ^[0-9A-F]{8}$ ]] && return 0
        [[ -z "$dword2" ]] || [[ ${#dword2} -ne 8 ]] || [[ ! "$dword2" =~ ^[0-9A-F]{8}$ ]] && return 0
        [[ -z "${current_section_stem:-}" ]] && return 0
        local params_file="$out_dir/${current_section_stem}.params"
        local b0 b1 b2 b3 sz0 sz1
        b0=$((16#${dword1:0:2})); b1=$((16#${dword1:2:2})); b2=$((16#${dword1:4:2})); b3=$((16#${dword1:6:2}))
        # AN001 5.4 size is low 16 bits of DWORD2 (MSB-first token), so use rightmost 4 hex chars: ... sz1 sz0
        sz0=$((16#${dword2:6:2})); sz1=$((16#${dword2:4:2}))
        local size=$(( sz0 + (sz1 << 8) ))
        {
            echo "dword1=$dword1"
            echo "dword2=$dword2"
            if [ -n "$dword3" ] && [[ ${#dword3} -eq 8 ]] && [[ "$dword3" =~ ^[0-9A-Fa-f]{8}$ ]]; then
                dword3=$(echo "$dword3" | tr '[:lower:]' '[:upper:]')
                echo "dword3=$dword3"
            fi
            echo "hc=0x$(printf '%02x' $b3)"
            echo "xv=0x$(printf '%02x' $b2)"
            echo "cmd=0x$(printf '%02x' $b1)"
            echo "loop=0x$(printf '%02x' $b0)"
            echo "sz0=0x$(printf '%02x' $sz0)"
            echo "sz1=0x$(printf '%02x' $sz1)"
            echo "size=$size"
            echo "size_hex=0x$(printf '%04x' $size)"
        } > "$params_file" 2>/dev/null || true
    }

    # Write .params for a section with explicit total size (used for XV0 Partial PMBus combined section).
    write_section_params_with_size() {
        local dword1="$1"
        local total_size=$(( $2 ))
        local dword3="${3:-}"
        [[ -z "$dword1" ]] || [[ ${#dword1} -ne 8 ]] || [[ ! "$dword1" =~ ^[0-9A-F]{8}$ ]] && return 0
        [[ -z "${current_section_stem:-}" ]] && return 0
        local params_file="$out_dir/${current_section_stem}.params"
        local b0 b1 b2 b3 sz0 sz1
        b0=$((16#${dword1:0:2})); b1=$((16#${dword1:2:2})); b2=$((16#${dword1:4:2})); b3=$((16#${dword1:6:2}))
        sz0=$(( total_size & 0xff ))
        sz1=$(( (total_size >> 8) & 0xff ))
        {
            echo "dword1=$dword1"
            echo "dword2=0000$(printf '%02x' $sz1)$(printf '%02x' $sz0)"
            if [ -n "$dword3" ] && [[ ${#dword3} -eq 8 ]] && [[ "$dword3" =~ ^[0-9A-Fa-f]{8}$ ]]; then
                dword3=$(echo "$dword3" | tr '[:lower:]' '[:upper:]')
                echo "dword3=$dword3"
            fi
            echo "hc=0x$(printf '%02x' $b3)"
            echo "xv=0x$(printf '%02x' $b2)"
            echo "cmd=0x$(printf '%02x' $b1)"
            echo "loop=0x$(printf '%02x' $b0)"
            echo "sz0=0x$(printf '%02x' $sz0)"
            echo "sz1=0x$(printf '%02x' $sz1)"
            echo "size=$total_size"
            echo "size_hex=0x$(printf '%04x' $total_size)"
        } > "$params_file" 2>/dev/null || true
    }

    append_dwords_from_line() {
        local rest="${line#* }"
        local dword
        for dword in $rest; do
            dword=$(echo "$dword" | tr '[:lower:]' '[:upper:]' | tr -d '\r')
            [[ -z "$dword" ]] || [[ ${#dword} -ne 8 ]] && continue
            [[ ! "$dword" =~ ^[0-9A-F]{8}$ ]] && continue
            local b0 b1 b2 b3
            [[ "${dword:0:2}" =~ ^[0-9A-F]{2}$ ]] && [[ "${dword:2:2}" =~ ^[0-9A-F]{2}$ ]] && \
            [[ "${dword:4:2}" =~ ^[0-9A-F]{2}$ ]] && [[ "${dword:6:2}" =~ ^[0-9A-F]{2}$ ]] || continue
            [[ -z "$section_first_dword" ]] && section_first_dword="$dword"
            b0=$((16#${dword:0:2})); b1=$((16#${dword:2:2})); b2=$((16#${dword:4:2})); b3=$((16#${dword:6:2}))
            # DWORD in .txt is MSB-first; device/OTP use little-endian — write LSB first (b3 b2 b1 b0)
            printf '%b' "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' "$b3" "$b2" "$b1" "$b0")" >> "$current_section_bin" || return 1
            section_dwords=$((section_dwords + 1))
        done
    }

    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^\[Configuration[[:space:]]Data\] ]]; then
            in_config=1
            log_info "Parsing [Configuration Data] for section-by-section flash from $txt_file"
            echo ""
            continue
        fi
        if [[ "$line" =~ ^\[End[[:space:]]Configuration[[:space:]]Data\] ]]; then
            if [ $in_partial -eq 1 ]; then
                [ -n "$partial_crc_pending_d3" ] && log_warn "Partial section: ended config with no 010 row after last 000 (CRC input may be incomplete)"
                write_section_params_with_size "$first_partial_dword1" $((section_dwords * 4)) "${first_partial_dword3:-}" || true
                in_partial=0
                first_partial_dword3=""
                partial_crc_input_file=""
                partial_crc_pending_d3=""
                section_index=$((section_index + 1))
            fi
            # Single summary for the last section: log_section_summary after the loop (EOF / end marker).
            break
        fi
        [[ $in_config -eq 0 ]] && continue

        # Optional section name (// XV0 Partial PMBus, etc.) — for logging only
        if [[ "$line" =~ ^// ]]; then
            current_section_name="${line#//}"
            current_section_name=$(echo "$current_section_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            continue
        fi

        # (Sub)section start: line beginning with "000 " (AN001 5.2). Extract 1st and 2nd DWORD (5.3, 5.4).
        # Partial sections (AN001 8.3): HC in {0x0A,0x0B,0x11} — multiple "000" rows form one section.
        if [[ "$line" =~ ^000[[:space:]] ]]; then
            local rest="${line#* }"
            local dw=()
            for d in $rest; do
                d=$(echo "$d" | tr '[:lower:]' '[:upper:]' | tr -d '\r')
                [[ ${#d} -eq 8 ]] && [[ "$d" =~ ^[0-9A-F]{8}$ ]] && dw+=("$d")
                [[ ${#dw[@]} -ge 3 ]] && break
            done
            # First DWORD in .txt (MSB-first): chars 0:2=Loop, 2:2=CMD, 4:2=XV, 6:2=HC.
            local is_partial=0
            local is_hc_0b=0
            if [[ ${#dw[@]} -ge 1 ]]; then
                case "${dw[0]:6:2}" in
                    0A|0B|11) is_partial=1 ;;
                esac
                [[ "${dw[0]:6:2}" = "0B" ]] && is_hc_0b=1
            fi

            if [ $is_partial -eq 1 ]; then
                if [ $in_partial -eq 0 ]; then
                    log_section_summary
                    # Partial 000 after a normal section: finalize that section (no intervening normal 000).
                    if [[ -n "$current_section_bin" ]] && [ -f "$current_section_bin" ]; then
                        if [ $section_index -gt 0 ] && [ ${#parsed_section_stems[@]} -ge "$section_index" ]; then
                            _finalize_section_crc_expected "$out_dir/${parsed_section_stems[$((section_index - 1))]}.params" "$out_dir/${parsed_section_stems[$((section_index - 1))]}.bin" || true
                        fi
                    fi
                    start_section_file "${dw[0]}" || return 1
                    section_dwords=0
                    section_first_dword="${dw[0]}"
                    first_partial_dword1="${dw[0]}"
                    first_partial_dword3="${dw[2]:-}"
                    in_partial=1
                    if [ $is_hc_0b -eq 1 ]; then
                        partial_crc_input_file="${current_section_bin%.bin}_crc_input.bin"
                        : > "$partial_crc_input_file" || return 1
                    else
                        partial_crc_input_file=""
                    fi
                    partial_crc_pending_d3=""
                fi
                if [ $is_hc_0b -eq 1 ] && [ ${#dw[@]} -ge 3 ]; then
                    partial_crc_pending_d3="${dw[2]}"
                fi
                append_dwords_from_line
                continue
            fi

            # Normal section: close partial if we were in it, then start this section
            if [ $in_partial -eq 1 ]; then
                [ -n "$partial_crc_pending_d3" ] && log_warn "Partial section: new section started without 010 after last 000 (CRC input may be incomplete)"
                write_section_params_with_size "$first_partial_dword1" $((section_dwords * 4)) "${first_partial_dword3:-}" || true
                in_partial=0
                first_partial_dword3=""
                partial_crc_input_file=""
                partial_crc_pending_d3=""
                section_index=$((section_index + 1))
            fi
            if [ $section_index -gt 0 ] && [ ${#parsed_section_stems[@]} -ge "$section_index" ]; then
                _finalize_section_crc_expected "$out_dir/${parsed_section_stems[$((section_index - 1))]}.params" "$out_dir/${parsed_section_stems[$((section_index - 1))]}.bin" || true
            fi
            log_section_summary
            start_section_file "${dw[0]}" || return 1
            section_dwords=0
            section_first_dword=""
            if [[ ${#dw[@]} -ge 3 ]]; then
                write_section_params "${dw[0]}" "${dw[1]}" "${dw[2]}"
            elif [[ ${#dw[@]} -ge 2 ]]; then
                write_section_params "${dw[0]}" "${dw[1]}"
            fi
            append_dwords_from_line
            section_index=$((section_index + 1))
            continue
        fi

        # Data row: 3 hex digits + space + DWORDs (e.g. "010 38B4D17E") — append to current section
        if [[ "$line" =~ ^[0-9A-Fa-f]{3}[[:space:]] ]] && [[ -n "$current_section_bin" ]]; then
            if [ $in_partial -eq 1 ] && [ -n "${partial_crc_input_file:-}" ]; then
                local row_off d010 rest010
                row_off=$(echo "${line:0:3}" | tr '[:lower:]' '[:upper:]')
                if [ "$row_off" = "010" ] && [ -n "${partial_crc_pending_d3:-}" ]; then
                    rest010="${line#* }"
                    d010=$(echo "$rest010" | awk '{print $1}' | tr '[:lower:]' '[:upper:]' | tr -d '\r')
                    if [[ ${#d010} -eq 8 ]] && [[ "$d010" =~ ^[0-9A-F]{8}$ ]]; then
                        _append_le_dword_hex_to_file "$partial_crc_input_file" "$partial_crc_pending_d3" || return 1
                        _append_le_dword_hex_to_file "$partial_crc_input_file" "$d010" || return 1
                    else
                        log_warn "Partial section: invalid DWORD on 010 row; skipping one CRC input pair"
                    fi
                    partial_crc_pending_d3=""
                fi
            fi
            append_dwords_from_line
        fi
    done < "$txt_file"

    if [ $in_partial -eq 1 ]; then
        [ -n "$partial_crc_pending_d3" ] && log_warn "Partial section: EOF after 000 with no following 010 (CRC input may be incomplete)"
        write_section_params_with_size "$first_partial_dword1" $((section_dwords * 4)) "${first_partial_dword3:-}" || true
        in_partial=0
        first_partial_dword3=""
        partial_crc_input_file=""
        partial_crc_pending_d3=""
        section_index=$((section_index + 1))
    fi
    if [ $section_index -gt 0 ] && [ ${#parsed_section_stems[@]} -ge "$section_index" ]; then
        _finalize_section_crc_expected "$out_dir/${parsed_section_stems[$((section_index - 1))]}.params" "$out_dir/${parsed_section_stems[$((section_index - 1))]}.bin" || true
    fi
    log_section_summary

    if [[ $section_index -eq 0 ]] && [[ $section_dwords -eq 0 ]]; then
        log_error "No (sub)section (line starting with '000 ') found in $txt_file"
        rm -rf "$out_dir"
        return 1
    fi

    echo ""
    log_info "Parsed $section_index section(s); list in $section_list_file"
    return 0
}

# Convert byte array to little-endian DWORDs: each 4-byte group is reversed (LSB first).
# Input: array of 0xNN bytes. Output: same length, with every 4-byte chunk reversed.
# Partial final chunk (1-3 bytes) is also reversed.
bytes_to_little_endian_dwords() {
    local data=("$@")
    local n=${#data[@]}
    local out=()
    local i=0
    while [ $i -lt $n ]; do
        local chunk=()
        local j=0
        while [ $j -lt 4 ] && [ $((i + j)) -lt $n ]; do
            chunk+=("${data[$((i + j))]}")
            j=$((j + 1))
        done
        # reverse chunk
        local k=$((${#chunk[@]} - 1))
        while [ $k -ge 0 ]; do
            out+=("${chunk[$k]}")
            k=$((k - 1))
        done
        i=$((i + 4))
    done
    echo "${out[@]}"
}

# Populate SCPAD_HEX_ADDR once via 0x2e; reuse on subsequent scratchpad ops in the same process.
ensure_scpad_hex_addr() {
    if [ -n "$SCPAD_HEX_ADDR" ]; then
        return 0
    fi
    local scpad_full
    scpad_full=$(get_scratchpad_address $I2C_BUS $DEVICE_ADDR) || true
    local addr
    addr=$(echo "$scpad_full" | head -n1)
    if [ -z "$addr" ]; then
        return 1
    fi
    SCPAD_HEX_ADDR="$addr"
    return 0
}

# Write data to scratchpad memory (AN001 6.3: RPTR + 0xDE). Uses cached SCPAD_HEX_ADDR from 0x2e.
write_to_scratchpad() {
    local data_file=$1

    log_info "Writing configuration to scratchpad..."

    if [ ! -f "$data_file" ]; then
        log_error "Configuration file not found: $data_file"
        return 1
    fi

    local file_size
    file_size=$(wc -c < "$data_file" 2>/dev/null)
    [ -z "$file_size" ] && file_size=0
    log_info "Configuration file size: $file_size bytes"

    if ! ensure_scpad_hex_addr; then
        log_error "Scratchpad address not available (get_scratchpad_address failed). Device may not support 0x2e."
        return 1
    fi

    i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_SCRATCHPAD_WRITE || return 1

    # Config .bin files are little-endian (LSB first per DWORD); send as-is to device.
    local all_bytes
    all_bytes=$(_od_hex_all_spaced "$data_file")
    local data_array=()
    for b in $all_bytes; do data_array+=("0x$b"); done

    local num_dwords=$((${#data_array[@]} / 4))
    local remainder_bytes=$((${#data_array[@]} % 4))
    if [ $remainder_bytes -gt 0 ]; then
        while [ $remainder_bytes -lt 4 ]; do
            data_array+=(0x00)
            remainder_bytes=$((remainder_bytes + 1))
        done
        num_dwords=$((num_dwords + 1))
    fi

    log_info "Using AN001 6.3: RPTR (0xCE) + MFR_REG_WRITE (0xDE), scratchpad addr $SCPAD_HEX_ADDR"
    set_rptr $I2C_BUS $DEVICE_ADDR $((SCPAD_HEX_ADDR)) || return 1
    log_info "Writing $num_dwords DWORD(s) to 0xDE (w6: reg 0xDE + 0x04 + 4 bytes)..."
    local d
    for ((d=0; d<num_dwords; d++)); do
        local i=$((d * 4))
        local b0=${data_array[$i]}
        local b1=${data_array[$((i+1))]}
        local b2=${data_array[$((i+2))]}
        local b3=${data_array[$((i+3))]}
        write_dword $I2C_BUS $DEVICE_ADDR $MFR_REG_WRITE 0x04 $b0 $b1 $b2 $b3 || { log_error "Scratchpad write to 0xDE failed at DWORD $d"; return 1; }
        sleep 0.002
        if [ $((d % 8)) -eq 0 ] || [ $d -eq $((num_dwords - 1)) ]; then
            echo -n "."
        fi
    done
    echo ""
    log_info "Scratchpad write completed"
    return 0
}

# Read back scratchpad (AN001 6.3: RPTR + MFR_REG_READ 0xDF). Uses only data_file name and its byte size:
# output .scpad is exactly that many bytes (DWORD reads from device, then truncate to file size).
read_from_scratchpad() {
    local data_file=$1
    local out_file="${2:-${data_file}.scpad}"

    if [ ! -f "$data_file" ]; then
        log_error "read_from_scratchpad: file not found: $data_file"
        return 1
    fi

    local file_size
    file_size=$(wc -c < "$data_file" | tr -d '[:space:]')
    [ -z "$file_size" ] && file_size=0

    if ! ensure_scpad_hex_addr; then
        log_error "read_from_scratchpad: scratchpad address not available"
        return 1
    fi

    if [ "$file_size" -eq 0 ]; then
        : > "$out_file" || return 1
        log_info "Scratchpad readback: empty $out_file (0 bytes)"
        return 0
    fi

    local num_dwords=$(( (file_size + 3) / 4 ))
    local read_bytes=$((num_dwords * 4))

    log_info "Reading scratchpad $file_size bytes -> $out_file (from $read_bytes device DWORDs)"
    i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_SCRATCHPAD_WRITE || return 1
    set_rptr $I2C_BUS $DEVICE_ADDR $((SCPAD_HEX_ADDR)) || return 1
    local tmp
    tmp=$(mktemp) || return 1
    if ! read_otp_bytes_to_file $I2C_BUS $DEVICE_ADDR $read_bytes "$tmp"; then
        rm -f "$tmp"
        log_error "Scratchpad readback failed"
        return 1
    fi
    head -c "$file_size" "$tmp" > "$out_file" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    log_info "Scratchpad readback saved ($file_size bytes)"
    return 0
}

# Compare source file to .scpad (same size).
verify_scratchpad_readback() {
    local data_file=$1
    local scpad_file="${2:-${data_file}.scpad}"

    if [ ! -f "$scpad_file" ]; then
        log_error "verify_scratchpad_readback: missing $scpad_file"
        return 1
    fi

    if cmp -s "$data_file" "$scpad_file"; then
        log_info "Scratchpad verify OK: $(basename "$data_file") matches readback"
        return 0
    fi
    log_error "Scratchpad mismatch: $(basename "$data_file") differs from readback ($(basename "$scpad_file"))"
    local diff_sample
    diff_sample=$(cmp -l "$data_file" "$scpad_file" 2>/dev/null | head -n 10) || true
    [[ -n "$diff_sample" ]] && log_error "First differing bytes (cmp -l): $diff_sample"
    return 1
}

# Upload data from scratchpad to OTP (AN001 6.4). Error handling per AN001 6.5: check PMBus STATUS_CML (0x7e) after upload; only bit[0] is analyzed.
# Faults on both pages must be cleared first. Then BLOCK_WRITE(0xfd, 4, sz0, sz1, 0, 0), WRITE_BYTE(0xfe, 0x11), wait soak.
# Arg1: section_params_file (path to section_N.params with sz0, sz1). Arg2: optional data_file for single .bin (size used as sz0, sz1 LE).
upload_scratchpad_to_otp() {
    local section_params_file="${1:-}"
    local data_file="${2:-}"

    log_info "Uploading configuration from scratchpad to OTP..."

    log_info "Clearing faults on page 0 and page 1 (AN001 6.4)..."
    i2c_write $I2C_BUS $DEVICE_ADDR $PMBUS_PAGE 0x00 || return 1
    i2c_send_byte $I2C_BUS $DEVICE_ADDR $PMBUS_CLEAR_FAULTS || return 1
    i2c_write $I2C_BUS $DEVICE_ADDR $PMBUS_PAGE 0x01 || return 1
    i2c_send_byte $I2C_BUS $DEVICE_ADDR $PMBUS_CLEAR_FAULTS || return 1

    local p_sz0 p_sz1 p_hc p_xv p_size p_dword1 p_dword2
    if [[ -n "$section_params_file" && -f "$section_params_file" ]]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^dword1=(.*)$ ]] && p_dword1="${BASH_REMATCH[1]}"
            [[ "$line" =~ ^dword2=(.*)$ ]] && p_dword2="${BASH_REMATCH[1]}"
            [[ "$line" =~ ^hc=(.*)$ ]] && p_hc="${BASH_REMATCH[1]}"
            [[ "$line" =~ ^xv=(.*)$ ]] && p_xv="${BASH_REMATCH[1]}"
            [[ "$line" =~ ^size=([0-9]+)$ ]] && p_size="${BASH_REMATCH[1]}"
            [[ "$line" =~ ^sz0=0x([0-9A-Fa-f]+)$ ]] && p_sz0=0x${BASH_REMATCH[1]}
            [[ "$line" =~ ^sz1=0x([0-9A-Fa-f]+)$ ]] && p_sz1=0x${BASH_REMATCH[1]}
        done < "$section_params_file" 2>/dev/null
    fi
    if [[ -z "$p_sz0" || -z "$p_sz1" ]]; then
        if [[ -n "$data_file" && -f "$data_file" ]]; then
            local size
            size=$(wc -c < "$data_file" 2>/dev/null)
            [ -z "$size" ] && size=0
            p_sz0=$(( size & 0xff ))
            p_sz1=$(( (size >> 8) & 0xff ))
        else
            log_error "Upload requires section params file or data file for size"
            return 1
        fi
    fi

    log_info "0xFD: sz0(LSB)=0x$(printf '%02x' $p_sz0) sz1(MSB)=0x$(printf '%02x' $p_sz1)"
    write_dword $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND_DATA 0x04 $p_sz0 $p_sz1 0x00 0x00 || return 1
    i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_OTP_CONFIG_STORE || return 1

    # Soak time per AN001 Table 8 before polling
    local soak_s=2
    log_info "Soak time ${soak_s}s (AN001 Table 8)..."
    sleep $soak_s

    # MFR_FW_COMMAND (0xFE) is read-only; wait fixed time then check STATUS_CML per AN001 6.5. AN001: max wait not more than 3 s.
    local upload_wait_s=3
    log_info "Waiting ${upload_wait_s}s for upload (0xFE read-only, no completion poll)..."

    sleep $upload_wait_s

    # AN001 6.5: only bit[0] of STATUS_CML (d0) is analyzed; if bit 0 is not 0, upload was unsuccessful.
    local status_cml
    status_cml=$(i2c_read $I2C_BUS $DEVICE_ADDR $PMBUS_STATUS_CML 1) || status_cml=""
    if [[ -z "$status_cml" ]]; then
        log_error "Upload wait completed but STATUS_CML read failed or empty"
        return 1
    fi
    local cml_bit0=$((status_cml & 1))
    if [[ $cml_bit0 -eq 0 ]]; then
        log_info "Upload completed (STATUS_CML d0 bit[0]=0, raw=$status_cml)"
        if [[ -n "$section_params_file" && -f "$section_params_file" ]]; then
            [[ -n "$p_dword1" ]] && log_info "  Section 1st DWORD (5.3): $p_dword1  (hc=$p_hc xv=$p_xv)"
            [[ -n "$p_dword2" ]] && log_info "  Section 2nd DWORD (5.4): $p_dword2  (size=$p_size${p_sz0:+ sz0(LSB)=$p_sz0 sz1(MSB)=$p_sz1})"
        fi
        return 0
    fi
    log_error "Upload unsuccessful: STATUS_CML d0 bit[0] is not 0 (AN001 6.5), raw=$status_cml"
    i2c_send_byte $I2C_BUS $DEVICE_ADDR $PMBUS_CLEAR_FAULTS || true
    return 1
}

# Reset device to load new configuration. Uses standard PMBus OPERATION (0x01) off then on.
# If AN001 defines a device-specific reset or "load OTP to active" procedure (e.g. 0xFE command), use that instead.
reset_device() {
    log_info "Resetting device to load new configuration..."

    i2c_write $I2C_BUS $DEVICE_ADDR $PMBUS_OPERATION 0x00 || return 1
    sleep 0.5

    i2c_write $I2C_BUS $DEVICE_ADDR $PMBUS_OPERATION 0x80 || return 1
    sleep 1

    log_info "Device reset completed"
    return 0
}

# Main programming sequence
program_device() {
    local flash_file artifact_dir=""

    log_info "Starting programming sequence for $CONFIG_FILE"
    log_info "Target: I2C bus $I2C_BUS, address $DEVICE_ADDR"

    detect_device || return 1
    read_device_id || return 1
    clear_faults || return 1
    disable_write_protect || return 1
    check_otp_space || return 1

    # Full .txt/.mic only (no -s): skip entire flash if GUI "Configuration Checksum" matches device total CRC (AN001 GET_CRC HC=0).
    if [[ "$CONFIG_FILE" =~ \.(txt|mic)$ ]] && [ -z "$FLASH_SECTION_HC" ]; then
        local file_crc_full dev_crc_full nx_full ex_full
        file_crc_full=$(_read_configuration_checksum_from_txt "$CONFIG_FILE")
        if [ -n "$file_crc_full" ]; then
            dev_crc_full=$(get_crc "$I2C_BUS" "$DEVICE_ADDR" 0) || dev_crc_full=""
            if [ -n "$dev_crc_full" ]; then
                nx_full=$(_normalize_crc32_hex "$dev_crc_full")
                ex_full=$(_normalize_crc32_hex "$file_crc_full")
                if [ "$nx_full" = "$ex_full" ]; then
                    if [ $DRY_RUN -eq 1 ]; then
                        log_info "[DRY_RUN] Configuration Checksum matches device total OTP CRC ($nx_full); would skip full flash."
                    else
                        log_info "Configuration Checksum matches device total OTP CRC ($nx_full); skipping full flash."
                    fi
                    return 0
                fi
                log_verbose "Configuration Checksum $ex_full vs device total CRC $nx_full — mismatch; continuing."
            else
                log_verbose "GET_CRC (total, HC=0) failed or empty; cannot compare Configuration Checksum (continuing)."
            fi
        fi
    fi

    if [ $DRY_RUN -eq 0 ]; then
        if [ -n "$FLASH_SECTION_HC" ]; then
            log_warn "Partial flash (-s): matching OTP section(s) will be invalidated and reprogrammed."
        else
            log_warn "Full config flash: OTP section(s) not listed in the file will be invalidated; others updated or skipped if CRC matches (irreversible)."
        fi
    else
        log_info "DRY_RUN (-n): scratchpad write/readback only; OTP upload and finalize skipped; OTP invalidate only logged."
    fi
    if [ $DRY_RUN -eq 0 ]; then
        if [ "${ASSUME_YES:-0}" -eq 1 ]; then
            log_info "Assuming yes (-y): skipping interactive confirmation before flash."
        else
            local confirm=""
            read -r -p "Continue? (yes/no): " confirm || {
                log_error "Failed to read user input (non-interactive environment?)"
                return 1
            }
            confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
            if [[ ! "$confirm" =~ ^(yes|y)$ ]]; then
                log_info "Programming cancelled by user (entered: '$confirm')"
                return 1
            fi
        fi
    fi

    # .txt/.mic: upload each section individually (AN001 Section 6 - avoid device buffer overrun)
    # .bin: single scratchpad write + upload
    if [[ "$CONFIG_FILE" =~ \.(txt|mic)$ ]]; then
        # Section parse + artifacts + readback (-f): ${CONFIG_FILE%.*}_flash_work
        artifact_dir="${CONFIG_FILE%.*}_flash_work"
        mkdir -p "$artifact_dir" || { log_error "Cannot create section workspace: $artifact_dir"; return 1; }
        if ! parse_txt_config_to_section_files "$CONFIG_FILE" "$artifact_dir"; then
            return 1
        fi
        section_bins=()
        while IFS= read -r p; do
            [[ -n "$p" ]] && section_bins+=("$p")
        done < "$artifact_dir/section_list"
        if [ ${#section_bins[@]} -eq 0 ]; then
            log_error "No sections to flash"
            return 1
        fi

        # -s <hc>: flash only section(s) with this HeaderCode
        if [ -n "$FLASH_SECTION_HC" ]; then
            local requested_hc=$((FLASH_SECTION_HC))
            section_bins_filtered=()
            for f in "${section_bins[@]}"; do
                [ ! -f "$f" ] && continue
                local first_byte
                first_byte=$(_od_hex_n 1 "$f")
                [ -z "$first_byte" ] && continue
                local file_hc=$((16#$first_byte))
                [ "$file_hc" -eq "$requested_hc" ] && section_bins_filtered+=("$f")
            done
            if [ ${#section_bins_filtered[@]} -eq 0 ]; then
                log_info "No section with HeaderCode 0x$(printf '%02x' $requested_hc) found in config; nothing to flash."
                return 0
            fi
            section_bins=("${section_bins_filtered[@]}")
            log_info "Flashing only section(s) with HC=0x$(printf '%02x' $requested_hc) (${#section_bins[@]} section(s))"
        else
            # Full .txt: invalidate only OTP sections whose HC is not in this config (not global wipe).
            invalidate_otp_sections_not_in_config "${section_bins[@]}" || {
                return 1
            }
        fi

        log_info "Uploading ${#section_bins[@]} section(s) one by one (AN001 Section 6)"

        for i in "${!section_bins[@]}"; do
            flash_file="${section_bins[$i]}"
            log_info "--- Section $((i + 1))/${#section_bins[@]} ---"
            section_params_file="${flash_file%.bin}.params"
            local sec_hc_skip exp_crc dev_crc nx ex
            sec_hc_skip=$(_od_hex_n 1 "$flash_file")
            [ -z "$sec_hc_skip" ] && sec_hc_skip=0
            sec_hc_skip=$((16#$sec_hc_skip))
            exp_crc=$(_read_section_crc_expected_from_params "$section_params_file")
            if [ -n "$exp_crc" ]; then
                dev_crc=$(get_crc $I2C_BUS $DEVICE_ADDR $sec_hc_skip) || dev_crc=""
                if [ -n "$dev_crc" ]; then
                    nx=$(_normalize_crc32_hex "$dev_crc")
                    ex=$(_normalize_crc32_hex "$exp_crc")
                    if [ "$nx" = "$ex" ]; then
                        if [ $DRY_RUN -eq 1 ]; then
                            log_info "[DRY_RUN] Would skip section HC=0x$(printf '%02x' $sec_hc_skip): OTP GET_CRC $nx matches config $ex (no upload)."
                        else
                            log_info "Skipping section HC=0x$(printf '%02x' $sec_hc_skip): OTP CRC $nx matches config (no upload)."
                        fi
                        continue
                    else
                        if [ $DRY_RUN -eq 1 ]; then
                            log_info "[DRY_RUN] CRC check: OTP GET_CRC $nx vs config $ex — mismatch; would continue (scratchpad / simulate upload)."
                        else
                            log_info "CRC check: OTP GET_CRC $nx vs config $ex — mismatch; uploading section."
                        fi
                    fi
                else
                    log_warn "GET_CRC failed or empty for HC=0x$(printf '%02x' $sec_hc_skip); cannot compare to config $exp_crc (continuing)."
                fi
            elif [ $DRY_RUN -eq 1 ]; then
                log_info "[DRY_RUN] No section_crc_expected in $(basename "$section_params_file"); CRC pre-check skipped (section still processed)."
            fi
            if [ -n "$FLASH_SECTION_HC" ] && [ $DRY_RUN -eq 0 ]; then
                local hd_hex4 sec_hc sec_xv
                hd_hex4=$(_od_hex_n 4 "$flash_file")
                if [ ${#hd_hex4} -ge 8 ]; then
                    sec_hc=$((16#${hd_hex4:0:2}))
                    sec_xv=$((16#${hd_hex4:2:2}))
                    invalidate_otp 0 $sec_hc $sec_xv || {
                        return 1
                    }
                fi
            fi
            write_to_scratchpad "$flash_file" || {
                return 1
            }
            read_from_scratchpad "$flash_file" || {
                return 1
            }
            verify_scratchpad_readback "$flash_file" || {
                return 1
            }
            if [ $DRY_RUN -eq 0 ]; then
                upload_scratchpad_to_otp "$section_params_file" || {
                    return 1
                }
            fi
            if [ $DRY_RUN -eq 0 ] && [ $i -lt $((${#section_bins[@]} - 1)) ]; then
                log_info "Waiting before next section..."
                sleep 2
            fi
        done
        log_info "Section workspace: $artifact_dir"
    else
        flash_file="$CONFIG_FILE"
        write_to_scratchpad "$flash_file" || return 1
        read_from_scratchpad "$flash_file" || return 1
        verify_scratchpad_readback "$flash_file" || return 1
        if [ $DRY_RUN -eq 0 ]; then
            upload_scratchpad_to_otp "" "$flash_file" || return 1
        fi
    fi

    if [ $DRY_RUN -eq 1 ]; then
        log_info "Skip finalize (-n): upload to OTP, write protect, and reset were skipped"
        return 0
    fi

    enable_write_protect || {
        return 1
    }

    reset_device || {
        return 1
    }

    log_info "Programming completed successfully!"
    return 0
}

# Parse and display configuration file structure (AN001 section-by-section, aligned with readback).
# For .bin: scan by section headers (8-byte header: 4-byte header DWORD LE, 4-byte size DWORD LE). HC=0x00 end, HC=0xff invalid/skip.
# Optional out_dir (second arg): write each section to out_dir/section_NN_hc_XX.bin.
parse_config_file() {
    local config_file=$1
    local out_dir="${2:-}"

    if [ ! -f "$config_file" ]; then
        log_error "File not found: $config_file"
        return 1
    fi

    log_info "Parsing configuration file (AN001 section layout): $config_file"

    local file_size
    file_size=$(wc -c < "$config_file" 2>/dev/null); [ -z "$file_size" ] && file_size=0

    log_info "File size: $file_size bytes"

    # One hexdump of the whole file avoids repeated `dd bs=1 skip=N` (BusyBox dd often discards skip by reading from offset 0 each time → very slow).
    local fullhex
    fullhex=$(hexdump -v -n "$file_size" -e '1/1 "%02x"' "$config_file" 2>/dev/null) || {
        log_error "hexdump failed for $config_file"
        return 1
    }
    [ "$((${#fullhex} / 2))" -lt "$file_size" ] && {
        log_error "hexdump short read for $config_file"
        return 1
    }

    local offset=0
    local idx=0
    local max_sections=64

    while (( offset + 8 <= file_size && idx < max_sections )); do
        local pr_offs
        pr_offs="offset $(printf '0x%04x' $offset)"
        local header_hex size_hex
        header_hex=${fullhex:$((offset * 2)):8}
        size_hex=${fullhex:$((offset * 2 + 8)):8}

        [ -z "$header_hex" ] || [ ${#header_hex} -lt 8 ] || [ ${#size_hex} -lt 8 ] && break

        local h0 h1 s0 s1
        h0=${header_hex:0:2}; h1=${header_hex:2:2}
        s0=${size_hex:0:2}; s1=${size_hex:2:2}
        local hc=$((16#$h0))
        local xv=$((16#$h1))
        local size=$((16#$s0 + (16#$s1 << 8)))

        if [ "$hc" -eq 0 ]; then
            log_info "$pr_offs HC=0x00 size 0x$(printf '%04x' $size) -- end of data"
            break
        fi
        if [ "$size" -le 0 ] || [ "$size" -gt 32768 ]; then
            log_info "$pr_offs HC=0x$(printf '%02x' $hc) size 0x$(printf '%04x' $size) invalid -- stopping"
            break
        fi
        if [ "$hc" -eq 255 ]; then
            log_verbose "$pr_offs: HC=0xff (invalid), skipping ${size}B"
            offset=$((offset + size))
            continue
        fi

        local type_str
        type_str=$(section_type_name $hc)
        log_info "Section $idx: $pr_offs HC=0x$(printf '%02x' $hc) XV=0x$(printf '%02x' $xv) $type_str size $size (0x$(printf '%04x' $size)) bytes"

        if [[ -n "$out_dir" ]]; then
            mkdir -p "$out_dir" 2>/dev/null || true
            local sec_path="$out_dir/section_$(printf '%02d' $idx)_hc_$(printf '%02x' $hc).bin"
            if tail -c +$((offset + 1)) "$config_file" 2>/dev/null | head -c "$size" > "$sec_path"; then
                log_info "  -> $sec_path"
            fi
        fi

        offset=$((offset + size))
        idx=$((idx + 1))
    done

    log_info "Parsed $idx section(s), total ${offset} bytes."
    if [ -n "$out_dir" ]; then
        log_info "Section files written to $out_dir/section_*_hc_*.bin"
    fi
    return 0
}

# Readback: read OTP sections from device to read_NN.bin.
# With -f .txt/.mic: parse config, read each section by header code, save and compare with config.
# Without -f: scan OTP from base, read every section to read_00.bin, read_01.bin, ... (no comparison).
# Requires -b bus -a addr. Optional -o out_dir (default: current dir).
readback_from_device() {
    local txt_file="$CONFIG_FILE"
    local bus="$I2C_BUS"
    local addr="$DEVICE_ADDR"
    local out_dir="${OUTPUT_FILE:-.}"
    local have_config=0
    local config_files_dir=""
    [[ -n "$txt_file" && "$txt_file" =~ \.(txt|mic)$ ]] && have_config=1

    if [ -z "$bus" ] || [ -z "$addr" ]; then
        log_error "Readback requires -b <bus> and -a <addr>"
        return 1
    fi

    if [ $have_config -eq 1 ]; then
        log_info "Readback: parsing $txt_file and reading sections from device (bus $bus addr $addr)"
    else
        log_info "Readback: reading all OTP sections from device (bus $bus addr $addr) -> $out_dir/read_*.bin"
    fi
    echo ""

    unbind_driver_for_device

    # Readback requires I2C/SMBus block write (to set RPTR) and block read (to read OTP). Probe once.
    if ! set_rptr $bus $addr $((OTP_BASE)); then
        log_error "Readback requires I2C block write support (to set register pointer)."
        log_error "Your controller may not support it. Use an I2C adapter with SMBus block transfer, or skip readback."
        return 1
    fi
    if ! read_otp_dword_hex $bus $addr >/dev/null; then
        log_error "Readback requires I2C block read support (to read OTP)."
        log_error "Your controller may not support it. Use an I2C adapter with SMBus block transfer, or skip readback."
        return 1
    fi
    log_info "I2C block transfer probe OK, continuing readback."
    echo ""

    mkdir -p "$out_dir" 2>/dev/null || true

    if [ $have_config -eq 1 ]; then
        # With config: parse .txt, read each section by hc/xv, write to read_NN.bin and compare
        local tmpdir section_bins i section_path read_path
        tmpdir="${txt_file%.*}_flash_work"
        mkdir -p "$tmpdir" || { log_error "Cannot create temp dir: $tmpdir"; return 1; }
        config_files_dir="$tmpdir"
        if ! parse_txt_config_to_section_files "$txt_file" "$tmpdir"; then
            rm -rf "$tmpdir"
            return 1
        fi
        section_bins=()
        while IFS= read -r p; do
            [[ -n "$p" ]] && section_bins+=("$p")
        done < "$tmpdir/section_list"

        for i in "${!section_bins[@]}"; do
            section_path="${section_bins[$i]}"
            # Section bin is LE: first 4 bytes = HC, XV, CMD, Loop (byte0..byte3)
            local hd_hex4
            hd_hex4=$(_od_hex_n 4 "$section_path")
            [ ${#hd_hex4} -lt 8 ] && { log_error "Section file too short: $section_path"; rm -rf "$tmpdir"; return 1; }
            local sec_hc sec_xv
            sec_hc=$((16#${hd_hex4:0:2}))
            sec_xv=$((16#${hd_hex4:2:2}))
            local cfg_size
            cfg_size=$(wc -c < "$section_path" 2>/dev/null); [ -z "$cfg_size" ] && cfg_size=0

            # Partial types (0x0A/0x0B/0x11): concatenate every matching OTP section until HC=0x00. Other HCs: first matching section only.
            read_path="$out_dir/read_$(printf '%02d' $i)_hc_$(printf '%02x' $sec_hc).bin"
            local _concat=0
            readback_otp_multi_section_hc "$sec_hc" && _concat=1
            if [ "$_concat" -eq 1 ]; then
                log_info "Section $i: reading all HC=0x$(printf '%02x' $sec_hc) XV=0x$(printf '%02x' $sec_xv) OTP sections until HC=0x00 -> $read_path"
            else
                log_info "Section $i: reading first OTP section HC=0x$(printf '%02x' $sec_hc) XV=0x$(printf '%02x' $sec_xv) -> $read_path"
            fi
            if ! read_otp_sections_by_hc_until_stop $bus $addr $sec_hc $sec_xv "$read_path" $_concat; then
                rm -rf "$tmpdir"
                return 1
            fi

            local dev_size
            dev_size=$(wc -c < "$read_path" 2>/dev/null); [ -z "$dev_size" ] && dev_size=0
            if [ "$cfg_size" = "$dev_size" ]; then
                if cmp -s "$section_path" "$read_path"; then
                    log_info "  Match: config and device data identical"
                else
                    log_warn "  Diff: config and device data differ (same size)"
                fi
            else
                log_warn "  Size mismatch: config ${cfg_size}B vs device ${dev_size}B"
            fi
        done
        # rm -rf "$tmpdir"
    else
        # No config: scan OTP from base. HC=0x00 = end of data; HC=0xff = invalid (skip). Save rest as read_NN_hc_XX.bin.
        local addr_32=$((OTP_BASE))
        local max_addr=$((OTP_BASE + 32768))
        local idx=0 max_sections=64
        local hd_hex sz_hex h0 h1 h2 h3 s0 s1 s2 s3 size hc

        while (( addr_32 < max_addr && idx < max_sections )); do
            local pr_otp
            pr_otp="OTP offset $(printf '0x%04x' $((addr_32 - OTP_BASE)))"
            set_rptr $bus $addr $addr_32 || return 1
            hd_hex=$(read_otp_dword_hex $bus $addr) || return 1
            sz_hex=$(read_otp_dword_hex $bus $addr) || return 1
            read -r h0 h1 h2 h3 <<< "$hd_hex"
            read -r s0 s1 s2 s3 <<< "$sz_hex"
            size=$(( 16#$s0 + (16#$s1 << 8) ))
            hc=$((16#$h0))
            if [ "$hc" -eq 0 ]; then
                log_info "$pr_otp HC=0x00 size 0x$(printf '%04x' $size) -- stopping scan"
                break
            fi
            if [ "$size" -le 0 ] || [ "$size" -gt 32768 ]; then
                log_info "$pr_otp HC=0x$(printf '%02x' $hc) size 0x$(printf '%04x' $size) invalid -- stopping scan"
                break
            fi
            if [ "$hc" -eq 255 ]; then
                log_verbose "$pr_otp: HC=0xff (invalid), skipping ${size} (0x$(printf '%04x' $size)) bytes"
                addr_32=$((addr_32 + size))
                continue
            fi
            local read_path="$out_dir/read_$(printf '%02d' $idx)_hc_$(printf '%02x' $hc).bin"
            log_info "Section $idx: $pr_otp HC=0x$(printf '%02x' $hc) size 0x$(printf '%04x' $size) -> $read_path"
            : > "$read_path" || return 1
            hex_dword_to_file "$hd_hex" "$read_path"
            hex_dword_to_file "$sz_hex" "$read_path"
            if [ "$size" -gt 8 ]; then
                read_otp_bytes_to_file $bus $addr $((size - 8)) "$read_path" || return 1
            fi
            addr_32=$((addr_32 + size))
            idx=$((idx + 1))
        done
        log_info "Read $idx section(s) from OTP."
    fi

    log_info "Readback complete. Device sections saved under $out_dir/read_*.bin"
    [ -n "$config_files_dir" ] && log_info "Config section files (parsed from -f): $config_files_dir"
    return 0
}

# Read full 32 KB OTP and save to outdir/otp-full.bin. Requires -b bus -a addr. Optional -o outdir (default: .).
readback_all() {
    local bus="$1"
    local addr="$2"
    local out_dir="${3:-.}"

    if [ -z "$bus" ] || [ -z "$addr" ]; then
        log_error "readback-all requires -b <bus> and -a <addr>"
        return 1
    fi

    log_info "Readback all: reading 32 KB from device (bus $bus addr $addr) -> $out_dir/otp-full.bin"
    echo ""

    unbind_driver_for_device

    if ! set_rptr "$bus" "$addr" $((OTP_BASE)); then
        log_error "readback-all requires I2C block write support (to set register pointer)."
        return 1
    fi
    if ! read_otp_dword_hex "$bus" "$addr" >/dev/null; then
        log_error "readback-all requires I2C block read support (to read OTP)."
        return 1
    fi

    mkdir -p "$out_dir" 2>/dev/null || true
    local out_file="$out_dir/otp-full.bin"
    : > "$out_file" || { log_error "Cannot create $out_file"; return 1; }

    if ! set_rptr "$bus" "$addr" $((OTP_BASE)); then
        log_error "Failed to set OTP read pointer"
        return 1
    fi
    if ! read_otp_bytes_to_file "$bus" "$addr" 32768 "$out_file"; then
        log_error "Failed to read OTP data"
        return 1
    fi

    log_info "Saved 32768 bytes to $out_file"
    return 0
}

# Scan I2C bus for Infineon devices
scan_infineon_devices() {
    local bus=$1

    log_info "Scanning I2C bus $bus for Infineon XDPE devices..."
    echo ""

    echo "I2C Bus $bus Device Map:"
    i2cdetect -y $bus
    echo ""

    log_info "Checking Infineon XDPE addresses (0x40-0x6F)..."

    for addr in $(seq 64 111); do
        local hex_addr
        hex_addr=$(printf "0x%02x" $addr)
        local addr_hex
        addr_hex=$(printf '%02x' $addr)

        local scan_out
        scan_out=$(i2cdetect -y $bus $addr $addr)
        # Match cell value (space before addr_hex or UU) to avoid false positive on row label (e.g. "40:" for addr 0x40)
        if echo "$scan_out" | grep -qE " (${addr_hex}|UU)( |$)"; then
            echo -e "${GREEN}Found device at $hex_addr${NC}"

            local mfr_id
            I2C_BUS=$bus DEVICE_ADDR=$hex_addr unbind_driver_for_device
            mfr_id=$(read_device_info_block $bus $hex_addr 0x99)
            [ -z "$mfr_id" ] && mfr_id=$(i2cget -y $bus $hex_addr 0x99)
            rebind_driver_if_unbound
            echo "  PMBUS_MFR_ID: ${mfr_id:-N/A}"
        fi
    done

    return 0
}

# Read PMBus block register (length byte + data); output as string or hex if non-printable.
# Usage: read_device_info_block bus addr reg
read_device_info_block() {
    local bus=$1
    local addr=$2
    local reg=$3
    local block
    block=$(i2cget -y "$bus" "$addr" "$reg" i 32) || return 1
    [ -z "$block" ] && return 1
    local first_byte
    first_byte=$(echo "$block" | awk '{print $1}')
    [ -z "$first_byte" ] && return 1
    local len=$((first_byte))
    [ "$len" -le 0 ] || [ "$len" -gt 31 ] && return 1
    local rest
    rest=$(echo "$block" | awk -v n="$len" '{ for (i=2; i<=n+1 && i<=NF; i++) printf "%s ", $i }')
    [ -z "$rest" ] && return 1
    local str=""
    local hex
    local all_printable=1
    for hex in $rest; do
        local b=$((hex))
        if [ "$b" -ge 32 ] && [ "$b" -le 126 ]; then
            str+=$(printf '%b' "$(printf '\\x%02x' $b)")
        else
            all_printable=0
            str+=$(printf '\\x%02x' $b)
        fi
    done
    if [ "$all_printable" -eq 1 ]; then
        echo "$str"
    else
        # Contains non-printable bytes: show as hex list (rest is already "0xXX 0xYY ...")
        echo "$rest"
    fi
    return 0
}

# Read and display device information
read_device_info() {
    local bus=$1
    local addr=$2

    if [ -z "$bus" ] || [ -z "$addr" ]; then
        log_error "Usage: info mode requires -b <bus> -a <address>"
        return 1
    fi

    if [[ ! $addr == 0x* ]]; then
        addr="0x$addr"
    fi

    # 0xFE/0xFD access (FW timestamp, OTP size) requires device unbound
    I2C_BUS=$bus DEVICE_ADDR=$addr unbind_driver_for_device
    log_info "Reading device information..."
    log_info "Device: Bus $bus, Address $addr"

    local block_regs="0x99 0x9A 0x9B 0x9C 0x9D 0x9E 0xAD"
    local reg_names="PMBUS_MFR_ID PMBUS_MFR_MODEL PMBUS_MFR_REVISION PMBUS_MFR_LOCATION PMBUS_MFR_DATE PMBUS_MFR_SERIAL PMBUS_MFR_DEVICE_ID"
    local names_array=($reg_names)
    local idx=0
    for reg in $block_regs; do
        local name="${names_array[$idx]}"
        local value
        value=$(read_device_info_block "$bus" "$addr" "$reg")
        if [ -n "$value" ]; then
            log_info "  $(printf '%-24s' "$name"): $value"
        else
            value=$(i2cget -y $bus $addr $reg || echo "N/A")
            log_info "  $(printf '%-24s' "$name"): $value"
        fi
        idx=$((idx + 1))
    done

    local value
    value=$(i2cget -y $bus $addr 0x79 w || echo "N/A")
    log_info "  $(printf '%-24s' 'PMBUS_STATUS_WORD'): $value"
    value=$(i2cget -y $bus $addr 0x78 || echo "N/A")
    log_info "  $(printf '%-24s' 'PMBUS_STATUS_BYTE'): $value"
    value=$(i2cget -y $bus $addr 0x01 || echo "N/A")
    log_info "  $(printf '%-24s' 'OPERATION'): $value"
    value=$(i2cget -y $bus $addr 0x10 || echo "N/A")
    log_info "  $(printf '%-24s' 'WRITE_PROTECT'): $value"

    local fw_ts
    fw_ts=$(get_fw_timestamp "$bus" "$addr")
    if [ -n "$fw_ts" ]; then
        local fw_date
        fw_date=$(date -d "@$fw_ts" +"%Y-%m-%d %T" 2>/dev/null) || fw_date="$fw_ts"
        log_info "  $(printf '%-24s' 'FW_TIMESTAMP'): $fw_date ($fw_ts)"
    else
        log_info "  $(printf '%-24s' 'FW_TIMESTAMP'): N/A"
    fi

    # GET_CRC total CRC: AN001 HC=0x00 in BLOCK_WRITE(0xFD, 4, hc, 0, 0, 0).
    local crc_hex
    crc_hex=$(get_crc "$bus" "$addr" 0) || true
    if [ -n "$crc_hex" ]; then
        log_info "  $(printf '%-24s' 'CRC (HC=0x00)'): $crc_hex"
    else
        log_info "  $(printf '%-24s' 'CRC (HC=0x00)'): N/A"
    fi

    local otp_remaining
    otp_remaining=$(get_otp_partition_size_remaining "$bus" "$addr")
    if [ -n "$otp_remaining" ]; then
        log_info "  $(printf '%-24s' 'OTP_REMAINING_SIZE'): $otp_remaining (0x$(printf '%04x' "$otp_remaining")) bytes"
    else
        log_info "  $(printf '%-24s' 'OTP_REMAINING_SIZE'): N/A"
    fi

    return 0
}

# Monitor device telemetry (raw register values only)
monitor_telemetry() {
    local bus=$1
    local addr=$2
    local interval=${3:-1}

    if [ -z "$bus" ] || [ -z "$addr" ]; then
        log_error "Usage: monitor mode requires -b <bus> -a <address>"
        return 1
    fi

    if [[ ! $addr == 0x* ]]; then
        addr="0x$addr"
    fi

    I2C_BUS=$bus DEVICE_ADDR=$addr unbind_driver_for_device
    log_info "Monitoring device telemetry (press any key to exit and rebind driver)"
    log_info "Bus: $bus, Address: $addr, Interval: ${interval}s"
    echo ""

    while true; do
        # clear
        echo "=== Infineon XDPE Device Monitor ==="
        echo "Time: $(date)"
        echo "Bus: $bus, Address: $addr"
        echo ""

        for page in 0 1; do
            echo "--- Page $page ---"
            i2cset -y $bus $addr $PMBUS_PAGE $page

            local vout
            vout=$(i2cget -y $bus $addr $PMBUS_READ_VOUT w || echo "N/A")
            [[ "$vout" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Output Voltage:    $(printf '%5d' $((vout))) ($vout)" || echo "  Output Voltage:    $vout"

            local vin
            vin=$(i2cget -y $bus $addr $PMBUS_READ_VIN w || echo "N/A")
            [[ "$vin" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Input Voltage:     $(printf '%5d' $((vin))) ($vin)" || echo "  Input Voltage:     $vin"

            local iout
            iout=$(i2cget -y $bus $addr $PMBUS_READ_IOUT w || echo "N/A")
            [[ "$iout" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Output Current:    $(printf '%5d' $((iout))) ($iout)" || echo "  Output Current:    $iout"

            local temp
            temp=$(i2cget -y $bus $addr $PMBUS_READ_TEMPERATURE_1 w || echo "N/A")
            [[ "$temp" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Temperature:       $(printf '%5d' $((temp))) ($temp)" || echo "  Temperature:       $temp"

            local pout
            pout=$(i2cget -y $bus $addr $PMBUS_READ_POUT w || echo "N/A")
            [[ "$pout" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Output Power:      $(printf '%5d' $((pout))) ($pout)" || echo "  Output Power:      $pout"

            local pin
            pin=$(i2cget -y $bus $addr $PMBUS_READ_PIN w || echo "N/A")
            [[ "$pin" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Input Power:       $(printf '%5d' $((pin))) ($pin)" || echo "  Input Power:       $pin"

            local status
            status=$(i2cget -y $bus $addr $PMBUS_STATUS_BYTE || echo "N/A")
            [[ "$status" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Status Byte:       $(printf '%5d' $((status))) ($status)" || echo "  Status Byte:       $status"
            echo ""
        done

        echo "Press any key to exit (rebind driver)..."
        read -t $interval -n 1 2>/dev/null && break
    done

    return 0
}

# Dump all accessible registers
dump_registers() {
    local bus=$1
    local addr=$2
    local output_file=${3:-""}

    if [ -z "$bus" ] || [ -z "$addr" ]; then
        log_error "Usage: dump mode requires -b <bus> -a <address>"
        return 1
    fi

    if [[ ! $addr == 0x* ]]; then
        addr="0x$addr"
    fi

    I2C_BUS=$bus DEVICE_ADDR=$addr unbind_driver_for_device
    log_info "Dumping registers from device at bus $bus, address $addr"

    {
        echo "Infineon XDPE Register Dump"
        echo "Date: $(date)"
        echo "Bus: $bus, Address: $addr"
        echo ""
        printf "%-8s %-10s %-6s\n" "Reg" "Value" "ASCII"
        echo "----------------------------------------"

        for reg in $(seq 0 255); do
            local hex_reg
            hex_reg=$(printf "0x%02x" $reg)

            local value
            value=$(i2cget -y $bus $addr $hex_reg)

            if [ $? -eq 0 ] && [ -n "$value" ]; then
                local dec_value=$((value))
                local ascii=""
                if [ $dec_value -ge 32 ] && [ $dec_value -le 126 ]; then
                    ascii=$(printf '%b' "$(printf '\\x%02x' $dec_value)")
                fi
                printf "%-8s %-10s %-6s\n" "$hex_reg" "$value" "$ascii"
            fi
        done
    } | if [ -n "$output_file" ]; then
        tee "$output_file"
        log_info "Register dump saved to: $output_file"
    else
        cat
    fi

    return 0
}

# Compare two configuration files
compare_configs() {
    local file1=$1
    local file2=$2

    if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
        log_error "One or both files not found"
        return 1
    fi

    log_info "Comparing configuration files:"
    echo "  File 1: $file1"
    echo "  File 2: $file2"
    echo ""

    local size1
    local size2
    size1=$(wc -c < "$file1" 2>/dev/null); [ -z "$size1" ] && size1=0
    size2=$(wc -c < "$file2" 2>/dev/null); [ -z "$size2" ] && size2=0

    echo "File Sizes:"
    echo "  File 1: $size1 bytes"
    echo "  File 2: $size2 bytes"

    if [ $size1 -ne $size2 ]; then
        log_warn "File sizes differ!"
    fi
    echo ""

    if [ -n "${HAS_MD5SUM}" ]; then
        local md5_1
        local md5_2
        md5_1=$(md5sum "$file1" | awk '{print $1}')
        md5_2=$(md5sum "$file2" | awk '{print $1}')

        echo "MD5 Checksums:"
        echo "  File 1: $md5_1"
        echo "  File 2: $md5_2"

        if [ "$md5_1" = "$md5_2" ]; then
            log_info "Files are identical (MD5)"
        else
            log_warn "Files differ (MD5)"
        fi
        echo ""
    fi

    echo "Byte Comparison:"
    if cmp -s "$file1" "$file2"; then
        log_info "Files are identical (byte-by-byte)"
    else
        log_warn "Files differ"
        echo ""
        echo "First difference:"
        cmp -l "$file1" "$file2" | head -n 5
    fi

    return 0
}

# Main entry point
main() {
    echo "=========================================="
    echo "Infineon XDPE1x2xx Management Tool"
    echo "=========================================="

    if [ $# -lt 1 ]; then
        # usage
        return 0; # VV: Skip usage for now
    fi

    MODE=$1
    shift

    # Parse command line arguments based on mode
    local OPTIND
    local COMPARE_FILE=""
    local MONITOR_INTERVAL=1
    local OUTPUT_FILE=""

    while getopts "P:b:a:f:c:i:o:s:nyvh" opt; do
        case $opt in
            P)
                case "$OPTARG" in
                    0|no|off|false) USE_I2C_PEC=0 ;;
                    1|yes|on|true) USE_I2C_PEC=1 ;;
                    *)
                        log_error "Invalid -P$OPTARG (use -P0 or -P1)"
                        usage
                        ;;
                esac
                ;;
            b) I2C_BUS=$OPTARG ;;
            a) DEVICE_ADDR=$OPTARG ;;
            f) CONFIG_FILE=$OPTARG ;;
            c) COMPARE_FILE=$OPTARG ;;
            i) MONITOR_INTERVAL=$OPTARG ;;
            o) OUTPUT_FILE=$OPTARG ;;
            s) FLASH_SECTION_HC=$OPTARG ;;
            n) DRY_RUN=1 ;;
            y) ASSUME_YES=1 ;;
            v) VERBOSE=$((VERBOSE + 1)) ;;
            h) usage ;;
            *) usage ;;
        esac
    done

    case "${I2C_PEC:-}" in
        0|no|off|false) USE_I2C_PEC=0 ;;
        1|yes|on|true) USE_I2C_PEC=1 ;;
    esac
    if [ "${USE_I2C_PEC:-1}" -eq 1 ]; then
        I2C_XFER_FLAGS="-f -y"
    else
        I2C_XFER_FLAGS="-y"
        log_info "SMBus PEC disabled (-P0 or I2C_PEC=0)"
    fi

    # Convert device address if needed
    if [ -n "$DEVICE_ADDR" ]; then
        if [[ ! $DEVICE_ADDR == 0x* ]]; then
            DEVICE_ADDR="0x$DEVICE_ADDR"
        fi
    fi

    # Check dependencies
    if ! check_dependencies; then
        log_error "Dependency check failed"
        exit 1
    fi

    # Rebind I2C driver on exit if we unbound it (skip for unbind/rebind modes)
    if [ "$MODE" != "unbind" ] && [ "$MODE" != "rebind" ]; then
        trap 'rebind_driver_if_unbound' EXIT
    fi

    # Execute based on mode
    case "$MODE" in
        flash)
            if [ -z "$I2C_BUS" ] || [ -z "$DEVICE_ADDR" ] || [ -z "$CONFIG_FILE" ]; then
                log_error "Flash mode requires -b <bus> -a <address> -f <file>"
                usage
            fi
            if program_device; then
                exit 0
            else
                log_error "Programming failed!"
                exit 1
            fi
            ;;

        verify)
            if [ -z "$I2C_BUS" ] || [ -z "$DEVICE_ADDR" ]; then
                log_error "Verify mode requires -b <bus> -a <address>"
                usage
            fi
            if ! detect_device; then
                exit 1
            fi
            if ! read_device_id; then
                exit 1
            fi
            log_info "Verify mode: device detected and ID read (AN001: no STORE_CONFIG verification)"
            exit 0
            ;;

        scan)
            if [ -z "$I2C_BUS" ]; then
                log_error "Scan mode requires -b <bus>"
                usage
            fi
            if ! scan_infineon_devices "$I2C_BUS"; then
                exit 1
            fi
            exit 0
            ;;

        info)
            if [ -z "$I2C_BUS" ] || [ -z "$DEVICE_ADDR" ]; then
                log_error "Info mode requires -b <bus> -a <address>"
                usage
            fi
            if ! read_device_info "$I2C_BUS" "$DEVICE_ADDR"; then
                exit 1
            fi
            exit 0
            ;;

        monitor)
            if [ -z "$I2C_BUS" ] || [ -z "$DEVICE_ADDR" ]; then
                log_error "Monitor mode requires -b <bus> -a <address>"
                usage
            fi
            if ! monitor_telemetry "$I2C_BUS" "$DEVICE_ADDR" "$MONITOR_INTERVAL"; then
                exit 1
            fi
            exit 0
            ;;

        dump)
            if [ -z "$I2C_BUS" ] || [ -z "$DEVICE_ADDR" ]; then
                log_error "Dump mode requires -b <bus> -a <address>"
                usage
            fi
            if ! dump_registers "$I2C_BUS" "$DEVICE_ADDR" "$OUTPUT_FILE"; then
                exit 1
            fi
            exit 0
            ;;

        unbind)
            if [ -z "$I2C_BUS" ] || [ -z "$DEVICE_ADDR" ]; then
                log_error "Unbind mode requires -b <bus> -a <address>"
                usage
            fi
            unbind_driver_for_device
            if [ -z "$DRIVER_UNBIND_DEVID" ] || [ -z "$DRIVER_UNBIND_NAME" ]; then
                log_info "No driver bound at $I2C_BUS $DEVICE_ADDR (or unbind not needed)"
                exit 0
            fi
            if save_unbind_state; then
                log_info "Unbound $DRIVER_UNBIND_NAME from $DRIVER_UNBIND_DEVID; run 'rebind' to restore"
            else
                log_error "Failed to save unbind state"
                rebind_driver_if_unbound
                exit 1
            fi
            exit 0
            ;;

        rebind)
            if rebind_driver_from_state_file; then
                log_info "Driver rebound successfully"
                exit 0
            else
                log_error "No saved unbind state (run 'unbind -b <bus> -a <addr>' first) or rebind failed"
                exit 1
            fi
            ;;

        scpad-addr)
            if [ -z "$I2C_BUS" ] || [ -z "$DEVICE_ADDR" ]; then
                log_error "scpad-addr mode requires -b <bus> -a <address>"
                usage
            fi
            unbind_driver_for_device
            get_scpad_addr "$I2C_BUS" "$DEVICE_ADDR"
            exit $?
            ;;

        readback)
            if [ -z "$I2C_BUS" ] || [ -z "$DEVICE_ADDR" ]; then
                log_error "Readback mode requires -b <bus> -a <address>"
                usage
            fi
            if ! detect_device; then
                exit 1
            fi
            if ! readback_from_device; then
                exit 1
            fi
            exit 0
            ;;

        readback-all)
            if [ -z "$I2C_BUS" ] || [ -z "$DEVICE_ADDR" ]; then
                log_error "readback-all requires -b <bus> -a <address>"
                usage
            fi
            if ! readback_all "$I2C_BUS" "$DEVICE_ADDR" "${OUTPUT_FILE:-.}"; then
                exit 1
            fi
            exit 0
            ;;

        parse)
            if [ -z "$CONFIG_FILE" ]; then
                log_error "Parse mode requires -f <file>"
                usage
            fi
            if [[ "$CONFIG_FILE" =~ \.(txt|mic)$ ]]; then
                local out_bin="${OUTPUT_FILE:-${CONFIG_FILE%.*}.bin}"
                if ! parse_txt_config_to_bin "$CONFIG_FILE" "$out_bin" 1; then
                    exit 1
                fi
                log_info "Converted .txt -> $out_bin ($(wc -c < "$out_bin" | tr -d '[:space:]') bytes)"
                if ! parse_config_file "$out_bin" ""; then
                    exit 1
                fi
            else
                if ! parse_config_file "$CONFIG_FILE" "${OUTPUT_FILE:-}"; then
                    exit 1
                fi
            fi
            exit 0
            ;;

        compare)
            if [ -z "$CONFIG_FILE" ] || [ -z "$COMPARE_FILE" ]; then
                log_error "Compare mode requires -f <file1> -c <file2>"
                usage
            fi
            if ! compare_configs "$CONFIG_FILE" "$COMPARE_FILE"; then
                exit 1
            fi
            exit 0
            ;;

        *)
            log_error "Unknown mode: $MODE"
            usage
            ;;
    esac
}

# Run main function
main "$@"
