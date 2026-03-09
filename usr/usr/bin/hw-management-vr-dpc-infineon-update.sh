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
TIMEOUT=30
VERBOSE=0
MODE=""

# When the kernel driver (e.g. xdpe1a2g7b) is bound, raw i2cget/i2cset cannot access the device.
# We unbind the driver for verify/flash and rebind on exit.
DRIVER_UNBIND_DEVID=""
DRIVER_UNBIND_NAME=""
# State file for unbind/rebind modes (so rebind can run in a separate invocation)
UNBIND_STATE_FILE="/var/run/hw-management/vr_dpc_infineon_unbound"
# Scratchpad (0xD0) accepts only a multi-byte block write; the I2C adapter must support i2ctransfer block writes.

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
    parse       Parse configuration file (or convert .txt/.mic to .bin with -o)
    readback    Read OTP sections from device to read_NN.bin; with -f .txt compare to config
    compare     Compare two configuration files

FLASH MODE OPTIONS:
    Required:
        -b <bus>        I2C bus number (e.g., 0, 1, 2)
        -a <addr>       Device I2C address in hex (e.g., 0x40)
        -f <file>       Configuration file path

    Optional:
        -s              Skip finalize: write to scratchpad only, do not upload to OTP or reset
        -v              Verbose: repeat for more (-v = verbose, -vv = debug)
        -t <seconds>    Timeout for operations (default: 30)

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
    -f <file>           Configuration file path (.bin = analyze; .txt/.mic = convert to binary)
    -o <file>           Output .bin path when converting .txt/.mic (default: input name with .bin extension)

READBACK MODE OPTIONS:
    -b <bus>            I2C bus number (required)
    -a <addr>           Device I2C address in hex (required)
    -f <file>           Optional: .txt/.mic config; if given, read sections by header code and compare with config
    -o <dir>            Output directory for read_NN.bin files (default: current dir). Without -f, all OTP sections are dumped in order.
    Note: Readback requires I2C/SMBus block write and block read. If your adapter does not support these, use another I2C adapter or skip readback.

COMPARE MODE OPTIONS:
    -f <file1>          First configuration file
    -c <file2>          Second configuration file

EXAMPLES:
    # Flash device (-s = scratchpad only, no OTP upload)
    $(basename $0) flash -b 2 -a 0x40 -f config.bin -s
    $(basename $0) flash -b 2 -a 0x40 -f config.bin

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

# Send single byte (command only, no data) — e.g. PMBUS_CLEAR_FAULTS per SMBus "send byte".
i2c_send_byte() {
    local bus=$1
    local addr=$2
    local reg=$3
    log_debug "i2ctransfer -y $bus w1@$addr $reg"
    if ! i2ctransfer -y $bus "w1@$addr" $reg 2>/dev/null; then
        log_error "Failed to send byte to device"
        return 1
    fi
    return 0
}

# Execute i2c command with error handling
i2c_write() {
    local bus=$1
    local addr=$2
    local reg=$3
    shift 3
    local data=("$@")

    log_debug "i2cset -y $bus $addr $reg ${data[*]}"
    if ! i2cset -y $bus $addr $reg "${data[@]}" 2>/dev/null; then
        log_error "Failed to write to device"
        return 1
    fi
    return 0
}

i2c_read() {
    local bus=$1
    local addr=$2
    local reg=$3
    local length=${4:-1}

    log_debug "i2cget -y $bus $addr $reg"
    [ "$length" = "1" ] && log_verbose "i2cget -y $bus $addr $reg" || log_verbose "i2cget -y $bus $addr $reg w"
    local result
    if [ "$length" = "1" ]; then
        result=$(i2cget -y $bus $addr $reg 2>/dev/null)
    else
        result=$(i2cget -y $bus $addr $reg w 2>/dev/null)
    fi

    if [ $? -ne 0 ]; then
        log_error "Failed to read from device"
        return 1
    fi

    echo -n "$result"
    return 0
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
    local bus=$1
    local addr=$2
    local reg=$3
    local num_bytes=${4:-4}

    log_verbose "i2ctransfer -y $bus w1@$addr $reg r${num_bytes}@$addr"
    local line
    line=$(i2ctransfer -y $bus "w1@$addr" $reg "r${num_bytes}@$addr" 2>/dev/null) || return 1
    echo "$line" | sed 's/0x//g'
    return 0
}

# Retrieve scratchpad register address for controllers that support CMD_GET_SCRATCHPAD_ADDR (0x2e).
# Sequence: BLOCK_WRITE(0xFD, 4, 2,0,0,0), WRITE_BYTE(0xFE, 0x2e), wait ~500us, BLOCK_READ(0xFD, 5).
# The value we use for scratchpad writes is d0 (first byte of the 5-byte response) — it is taken
# from the device only, not hardcoded. Some devices return 0x04; in standard PMBus 0x04 is
# PMBUS_PHASE — the controller may use vendor-specific meaning for scratchpad at this index.
#   d0 = byte from device (used as reg for write_dword); d1..d4 = 4-byte addr LE (e.g. 0x2005e000).
# If response has 0xff in d0 or d1..d4 all 0xff, treat as invalid and return empty (use default 0xD0).
get_scratchpad_address() {
    local bus=$1
    local addr=$2

    # BLOCK_WRITE(PMB_Addr, 0xfd, 4, 2, 0, 0, 0)
    write_dword $bus $addr $MFR_FW_COMMAND_DATA 0x04 0x02 0x00 0x00 0x00 || return 1
    # WRITE_BYTE(0xfe, 0x2e)
    i2c_write $bus $addr $MFR_FW_COMMAND $CMD_GET_SCRATCHPAD_ADDR || return 1
    sleep 0.001
    # BLOCK_READ(0xfd, 5) -> d0, d1, d2, d3, d4
    local d0 d1 d2 d3 d4
    local line
    line=$(i2c_block_read $bus $addr $MFR_FW_COMMAND_DATA 5) || return 1
    read -r d0 d1 d2 d3 d4 <<< "$line"
    log_debug "BLOCK_READ(0xfd,5) response: 0x${d0} 0x${d1} 0x${d2} 0x${d3} 0x${d4}"
    # 4-byte address (d1..d4) little-endian: e.g. 00 e0 05 20 -> 0x2005e000
    log_debug "4-byte addr (d1..d4) LE: 0x$(printf '%02x%02x%02x%02x' $((16#$d4)) $((16#$d3)) $((16#$d2)) $((16#$d1)))"
    [ -z "$d0" ] && return 1
    # Reject 0xff (unprogrammed) or d1..d4 all 0xff (stale/no valid address)
    [ "$d0" = "ff" ] && return 1
    [ "$d1" = "ff" ] && [ "$d2" = "ff" ] && [ "$d3" = "ff" ] && [ "$d4" = "ff" ] && return 1
    # Output: line1 = 8-bit register (d0); line2 = 4-byte addr LE (d1..d4) for scpad-addr display
    printf '0x%02x\n' $((16#$d0))
    printf '0x%08x\n' $(( 16#$d1 + (16#$d2 << 8) + (16#$d3 << 16) + (16#$d4 << 24) ))
    return 0
}

# Run get_scratchpad_address and print result (for manual use via 'scpad-addr' mode).
# Usage: get_scpad_addr <bus> <addr>
get_scpad_addr() {
    local bus=$1
    local addr=$2
    local result
    log_info "Querying scratchpad address (CMD_GET_SCRATCHPAD_ADDR 0x2e)..."
    local full
    full=$(get_scratchpad_address "$bus" "$addr") || true
    result=$(echo "$full" | head -n1)
    if [ -n "$result" ]; then
        local addr4
        addr4=$(echo "$full" | sed -n '2p')
        [ -n "$addr4" ] && log_info "Scratchpad: PMBus reg $result (for writes), 4-byte addr: $addr4" || log_info "Scratchpad: PMBus reg $result (for writes)"
        echo "$result"
        return 0
    else
        log_warn "Controller did not return scratchpad address; default is MFR_SPECIFIC_00 (0xD0)"
        echo "$MFR_SPECIFIC_00"
        return 1
    fi
}

# Multi-byte write: reg + data via i2ctransfer only (no SMBus block / i2cset block).
i2c_block_write() {
    local bus=$1
    local addr=$2
    local reg=$3
    shift 3
    local data=("$@")

    log_debug "i2ctransfer -y $bus w$((${#data[@]}+1))@$addr $reg ${data[*]}"
    log_verbose "i2ctransfer -y $bus w$((${#data[@]}+1))@$addr $reg ${data[*]}"
    if ! i2ctransfer -y $bus "w$((${#data[@]}+1))@$addr" $reg "${data[@]}" 2>/dev/null; then
        log_error "Failed to write to device (i2ctransfer)"
        return 1
    fi
    return 0
}

# Read one DWORD (4 bytes) from MFR_REG_READ; RPTR must be set and auto-increments.
# Device returns 5 bytes: length (0x04) then 4 data bytes. Use r5, then output only the 4 data bytes.
read_otp_dword_hex() {
    local bus=$1
    local addr=$2
    log_verbose "i2ctransfer -y $bus w1@$addr $MFR_REG_READ r5@$addr"
    local line
    line=$(i2ctransfer -y $bus w1@$addr $MFR_REG_READ r5@$addr 2>/dev/null) || return 1
    # Normalize: strip 0x, then drop first byte (length 0x04), output 4 data bytes
    line=$(echo "$line" | sed 's/0x//g')
    local _d0 _d1 _d2 _d3 _d4
    read -r _d0 _d1 _d2 _d3 _d4 <<< "$line"
    line="$_d1 $_d2 $_d3 $_d4"
    log_verbose "read DWORD: $line"
    echo "$line"
}

# Append 4 hex bytes (as from read_otp_dword_hex) as binary to file.
hex_dword_to_file() {
    local hex="$1"
    local file="$2"
    local b0 b1 b2 b3
    read -r b0 b1 b2 b3 <<< "$hex"
    printf '%b' "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' $((16#$b0)) $((16#$b1)) $((16#$b2)) $((16#$b3)))" >> "$file"
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

# Find section by full 4-byte header (Loop, CMD, XVcode, HeaderCode) in OTP, read full section to out_file. AN001 10.1.
# Returns 0 on success. OTP base 0x10020000; section layout: 4B header (LE: byte0=HC, byte1=XV, byte2=CMD, byte3=Loop), 4B size (LE), then data.
# All four fields must match; pass as decimal or hex (e.g. 0x0B 0x00 0x21 0x00).
read_otp_section() {
    local bus=$1
    local addr=$2
    local header_code=$(( $3 ))
    local xvcode=$(( $4 ))
    local cmd=$(( ${5:-0} ))
    local loop=$(( ${6:-0} ))
    local out_file=$7
    local addr_32=$((OTP_BASE))
    local max_addr=$((OTP_BASE + 32768))
    local max_iters=512
    local iters=0

    : > "$out_file" || return 1

    log_verbose "Searching for the section Loop=0x$(printf '%02x' $loop) CMD=0x$(printf '%02x' $cmd) XV=0x$(printf '%02x' $xvcode) HC=0x$(printf '%02x' $header_code)..."

    while (( addr_32 < max_addr && iters < max_iters )); do
        iters=$((iters + 1))
        set_rptr $bus $addr $addr_32 || return 1
        local hd_hex sz_hex
        hd_hex=$(read_otp_dword_hex $bus $addr) || return 1
        sz_hex=$(read_otp_dword_hex $bus $addr) || return 1
        local h0 h1 h2 h3 s0 s1 s2 s3
        read -r h0 h1 h2 h3 <<< "$hd_hex"
        read -r s0 s1 s2 s3 <<< "$sz_hex"
        # Section size is 2 bytes LE (sz0 LSB, sz1 MSB) per AN001; e.g. 58 01 -> 0x0158
        local size=$(( 16#$s0 + (16#$s1 << 8) ))
        local hc=$((16#$h0))
        local xv=$((16#$h1))
        local dev_cmd=$((16#$h2))
        local dev_loop=$((16#$h3))
        # Unprogrammed OTP often reads as 0xff; cap size to avoid overflow or huge skip
        if [ "$size" -gt 32768 ]; then
            size=8
        fi
        log_verbose "OTP offset $(printf '%03x' $(( addr_32 - OTP_BASE ))) found a section HC=0x$(printf '%02x' $hc) Loop=0x$(printf '%02x' $dev_loop) CMD=0x$(printf '%02x' $dev_cmd) of size 0x$(printf '%04x' $size)"
        if [ "$hc" -eq "$header_code" ] && [ "$xv" -eq "$xvcode" ] && [ "$dev_cmd" -eq "$cmd" ] && [ "$dev_loop" -eq "$loop" ]; then
            hex_dword_to_file "$hd_hex" "$out_file"
            hex_dword_to_file "$sz_hex" "$out_file"
            if [ $size -gt 8 ]; then
                read_otp_bytes_to_file $bus $addr $((size - 8)) "$out_file" || return 1
            fi
            return 0
        fi
        if [ $size -le 0 ]; then
            log_error "Invalid OTP section size 0 at 0x$(printf '%x' $addr_32)"
            return 1
        fi
        addr_32=$((addr_32 + size))
    done
    if [ $iters -ge $max_iters ]; then
        log_error "Section Loop=$loop CMD=$cmd XV=$xvcode HC=$header_code not found (max iterations reached)"
    else
        log_error "Section Loop=$loop CMD=$cmd XV=$xvcode HC=$header_code not found in OTP"
    fi
    return 1
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
    for cmd in i2cdetect i2cget i2cset i2ctransfer; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        log_error "Please install i2c-tools package"
        return 1
    fi

    HAS_MD5SUM=""
    HAS_SHA256SUM=""
    HAS_CMP=""
    command -v md5sum &> /dev/null && HAS_MD5SUM=1
    command -v sha256sum &> /dev/null && HAS_SHA256SUM=1
    command -v cmp &> /dev/null && HAS_CMP=1

    log_debug "All dependencies satisfied"
    return 0
}

# Detect device on I2C bus
detect_device() {
    log_info "Detecting device at address $DEVICE_ADDR on bus $I2C_BUS..."

    local i2c_out
    i2c_out=$(i2cdetect -y $I2C_BUS $DEVICE_ADDR $DEVICE_ADDR 2>/dev/null)
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
    if echo "$dev_id" > "$unbind_file" 2>/dev/null; then
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
    mfr_id=$(i2c_read "$bus" "$addr" $PMBUS_MFR_ID 2>/dev/null)
    mfr_model=$(i2c_read "$bus" "$addr" $PMBUS_MFR_MODEL 2>/dev/null)
    i2c_write "$bus" "$addr" $PMBUS_PAGE 0x00 2>/dev/null
    vout0=$(i2c_read "$bus" "$addr" $PMBUS_VOUT_MODE 2>/dev/null)
    i2c_write "$bus" "$addr" $PMBUS_PAGE 0x01 2>/dev/null
    vout1=$(i2c_read "$bus" "$addr" $PMBUS_VOUT_MODE 2>/dev/null)
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
        log_info "Waiting ${delay}s for device to be ready after reset before rebind..."
        sleep "$delay"
    fi
    if [ "${REBIND_DEBUG:-0}" -eq 1 ] 2>/dev/null; then
        local bus addr
        bus="${DRIVER_UNBIND_DEVID%-*}"
        addr="0x${DRIVER_UNBIND_DEVID##*-}"
        diagnose_rebind_id_regs "$bus" "$addr"
    fi
    if echo "$DRIVER_UNBIND_DEVID" > "$bind_file" 2>/dev/null; then
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
    mfr_id=$(read_device_info_block $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_ID 2>/dev/null)
    [ -z "$mfr_id" ] && mfr_id=$(i2c_read $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_ID 2>/dev/null)
    if [ -z "$mfr_id" ]; then
        log_error "Failed to read Manufacturer ID"
        return 1
    fi
    log_info "Manufacturer ID: $mfr_id"

    local mfr_model
    mfr_model=$(read_device_info_block $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_MODEL 2>/dev/null)
    [ -z "$mfr_model" ] && mfr_model=$(i2c_read $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_MODEL 2>/dev/null)
    if [ -z "$mfr_model" ]; then
        log_error "Failed to read Model"
        return 1
    fi
    log_info "Model: $mfr_model"

    local mfr_rev
    mfr_rev=$(read_device_info_block $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_REVISION 2>/dev/null)
    [ -z "$mfr_rev" ] && mfr_rev=$(i2c_read $I2C_BUS $DEVICE_ADDR $PMBUS_MFR_REVISION 2>/dev/null)
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

# Read OTP partition size remaining in bytes (AN001 Table 4: 0x10 OTP_PARTITION_SIZE_REMAINING).
# WRITE_BYTE(0xFE, 0x10), wait, BLOCK_READ(0xFD, 5). Device returns 5 bytes: length (0x04) then 4 data bytes LE; use r5, drop first byte.
get_otp_partition_size_remaining() {
    local bus=$1
    local addr=$2
    i2c_write $bus $addr $MFR_FW_COMMAND $CMD_OTP_PARTITION_SIZE_REMAINING || return 1
    sleep 0.5
    local line
    line=$(i2c_block_read $bus $addr $MFR_FW_COMMAND_DATA 5) || return 1
    line=$(echo "$line" | sed 's/0x//g')
    local d0 d1 d2 d3 d4
    read -r d0 d1 d2 d3 d4 <<< "$line"
    echo $(( 16#$d1 + (16#$d2 << 8) + (16#$d3 << 16) + (16#$d4 << 24) ))
    return 0
}

# Get FW UTC date timestamp (AN001: 0x01 FW_VERSION). WRITE_BYTE(0xFE, 0x01), wait 1ms, BLOCK_READ(0xFD, 5).
# Returns Unix timestamp to stdout (4 bytes LE after length byte); empty on failure.
get_fw_timestamp() {
    local bus=$1
    local addr=$2
    i2c_write $bus $addr $MFR_FW_COMMAND $CMD_FW_VERSION 2>/dev/null || return 1
    sleep 0.001
    local line
    line=$(i2c_block_read $bus $addr $MFR_FW_COMMAND_DATA 5 2>/dev/null) || return 1
    line=$(echo "$line" | sed 's/0x//g')
    local d0 d1 d2 d3 d4
    read -r d0 d1 d2 d3 d4 <<< "$line"
    echo $(( 16#$d1 + (16#$d2 << 8) + (16#$d3 << 16) + (16#$d4 << 24) ))
    return 0
}

# Get CRC (AN001: 0x2D GET_CRC). WRITE_BYTE(0xFE, 0x2D), wait 1ms, BLOCK_READ(0xFD, 5). Used as workaround between get_fw_timestamp and get_otp_partition_size_remaining on some HW.
get_crc() {
    local bus=$1
    local addr=$2
    i2c_write $bus $addr $MFR_FW_COMMAND $CMD_GET_CRC 2>/dev/null || return 1
    sleep 0.001
    i2c_block_read $bus $addr $MFR_FW_COMMAND_DATA 5 >/dev/null 2>/dev/null || true
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

# Invalidate existing OTP data (AN-001 6.2.1 "Reprogram entire configuration file").
# BLOCK_WRITE(0xFD, 4, 0xfe, 0xfe, 0, 0) then WRITE_BYTE(0xFE, 0x12 OTP_SECTION_INVALIDATE), wait 1s soak.
invalidate_otp() {
    local invalidate_all=${1:-1}

    if [ $invalidate_all -eq 1 ]; then
        log_info "Invalidating entire OTP configuration (AN-001 6.2.1)..."
    else
        log_info "Invalidating specific OTP section..."
    fi

    # AN-001 6.2.1: BLOCK_WRITE(0xFD, 4, 0xfe, 0xfe, 0, 0) then WRITE_BYTE(0xFE, 0x12). 0xfe,0xfe = all hc and XVcode.
    if [ $invalidate_all -eq 1 ]; then
        write_dword $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND_DATA 0x04 0xfe 0xfe 0x00 0x00 || return 1
        if ! i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_OTP_SECTION_INVALIDATE; then
            log_error "OTP invalidation: failed to send command (0xFE 0x12)"
            return 1
        fi
        # 3) wait soak time — 1s is enough per AN-001 6.2.1
        sleep 1
    else
        log_error "OTP section invalidation (specific section) requires setting 0xFD with section; use invalidate all or adapter with i2ctransfer"
        return 1
    fi

    local result
    result=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND) || return 1

    # 0x00 = success; 0xff = idle (e.g. XDPE1A2G7B)
    if [ "$result" != "0x00" ] && [ "$result" != "0xff" ]; then
        log_error "OTP invalidation failed with code: $result"
        return 1
    fi

    log_info "OTP invalidation completed"
    return 0
}

# Map AN001 Table 7 header code (first DWORD LSB) to short name and optional page (Loop A=0, B=1).
# 0x04=Config, 0x07=PMBus LoopA, 0x09=PMBus LoopB, 0x0B=Partial PMBus, etc.
section_type_name() {
    local code=$1
    case "$code" in
        4)  echo "Config (0x04)" ;;
        7)  echo "PMBus LoopA / page 0 (0x07)" ;;
        9)  echo "PMBus LoopB / page 1 (0x09)" ;;
        11) echo "Partial PMBus (0x0B)" ;;
        *)  echo "header 0x$(printf '%02x' "$code")" ;;
    esac
}

# Parse XDPE .txt/.mic config (AN001 format) to single binary; write to output path.
# Optional: [Configuration Data], [End Configuration Data], "// XV0 ..." lines. Data rows: "XXX DWORD0 DWORD1 ..." (3-digit hex + 8-char hex DWORDs). Each DWORD = 4 bytes big-endian.
parse_txt_config_to_bin() {
    local txt_file="$1"
    local bin_file="$2"
    local in_config=1
    local byte_count=0
    local current_section_name=""
    local section_dwords=0
    local section_first_dword=""

    if [ ! -f "$txt_file" ]; then
        log_error "Config file not found: $txt_file"
        return 1
    fi

    : > "$bin_file" || { log_error "Cannot create temp binary: $bin_file"; return 1; }

    log_section_summary() {
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

    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^\[Configuration[[:space:]]Data\] ]]; then
            in_config=1
            log_info "Parsing [Configuration Data] from $txt_file"
            echo ""
            continue
        fi
        if [[ "$line" =~ ^\[End[[:space:]]Configuration[[:space:]]Data\] ]]; then
            log_section_summary
            break
        fi
        [[ $in_config -eq 0 ]] && continue

        if [[ "$line" =~ ^// ]]; then
            current_section_name="${line#//}"
            current_section_name=$(echo "$current_section_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            continue
        fi

        if [[ "$line" =~ ^[0-9A-Fa-f]{3}[[:space:]] ]]; then
            local rest="${line#* }"
            local dword
            local row_dwords=0
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
                printf '%b' "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' "$b3" "$b2" "$b1" "$b0")" >> "$bin_file" || return 1
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
    echo ""
    log_info "Total: $byte_count bytes written to binary"
    return 0
}

# Parse .txt/.mic into one binary file per (sub)section (AN001 5.2).
# (Sub)sections start with a line beginning with "000 " (3-digit hex row offset). Optional: [Configuration Data],
# [End Configuration Data], and "// XV0 ..." comment lines. Writes section_0.bin, section_1.bin, ... and section_list.
parse_txt_config_to_section_files() {
    local txt_file="$1"
    local out_dir="$2"
    local in_config=1
    local current_section_name=""
    local section_dwords=0
    local section_first_dword=""
    local section_index=0
    local current_section_bin=""
    local section_list_file="$out_dir/section_list"

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
        current_section_bin="$out_dir/section_${section_index}.bin"
        : > "$current_section_bin" || return 1
        echo "$current_section_bin" >> "$section_list_file"
    }

    # Extract and store section header per AN001 5.3 (1st DWORD → 4 bytes b0..b3) and 5.4 (2nd DWORD → size 2 bytes: sz0 LSB, sz1 MSB).
    write_section_params() {
        local dword1="$1"
        local dword2="$2"
        [[ -z "$dword1" ]] || [[ ${#dword1} -ne 8 ]] || [[ ! "$dword1" =~ ^[0-9A-F]{8}$ ]] && return 0
        [[ -z "$dword2" ]] || [[ ${#dword2} -ne 8 ]] || [[ ! "$dword2" =~ ^[0-9A-F]{8}$ ]] && return 0
        local params_file="$out_dir/section_${section_index}.params"
        local b0 b1 b2 b3 sz0 sz1
        b0=$((16#${dword1:0:2})); b1=$((16#${dword1:2:2})); b2=$((16#${dword1:4:2})); b3=$((16#${dword1:6:2}))
        sz0=$((16#${dword2:0:2})); sz1=$((16#${dword2:2:2}))
        local size=$(( sz0 + (sz1 << 8) ))
        {
            echo "dword1=$dword1"
            echo "dword2=$dword2"
            echo "b0=0x$(printf '%02x' $b0) b1=0x$(printf '%02x' $b1) b2=0x$(printf '%02x' $b2) b3=0x$(printf '%02x' $b3)"
            echo "hc=0x$(printf '%02x' $b3) xv=0x$(printf '%02x' $b1)"
            echo "sz0=0x$(printf '%02x' $sz0)"
            echo "sz1=0x$(printf '%02x' $sz1)"
            echo "size=$size"
            echo "size_hex=0x$(printf '%04x' $size)"
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
            log_section_summary
            break
        fi
        [[ $in_config -eq 0 ]] && continue

        # Optional section name (// XV0 Partial PMBus, etc.) — for logging only
        if [[ "$line" =~ ^// ]]; then
            current_section_name="${line#//}"
            current_section_name=$(echo "$current_section_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            continue
        fi

        # (Sub)section start: line beginning with "000 " (AN001 5.2). Extract 1st and 2nd DWORD (5.3, 5.4) for params.
        if [[ "$line" =~ ^000[[:space:]] ]]; then
            log_section_summary
            start_section_file || return 1
            section_dwords=0
            section_first_dword=""
            local rest="${line#* }"
            local first_two=()
            for d in $rest; do
                d=$(echo "$d" | tr '[:lower:]' '[:upper:]' | tr -d '\r')
                [[ ${#d} -eq 8 ]] && [[ "$d" =~ ^[0-9A-F]{8}$ ]] && first_two+=("$d")
                [[ ${#first_two[@]} -ge 2 ]] && break
            done
            [[ ${#first_two[@]} -ge 2 ]] && write_section_params "${first_two[0]}" "${first_two[1]}"
            append_dwords_from_line
            section_index=$((section_index + 1))
            continue
        fi

        # Data row: 3 hex digits + space + DWORDs (e.g. "010 38B4D17E") — append to current section
        if [[ "$line" =~ ^[0-9A-Fa-f]{3}[[:space:]] ]] && [[ -n "$current_section_bin" ]]; then
            append_dwords_from_line
        fi
    done < "$txt_file"

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

# Write data to scratchpad memory (AN001 6.3: RPTR + 0xDE). Requires 4-byte scratchpad address from get_scratchpad_address (0x2e).
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

    local scpad_full
    scpad_full=$(get_scratchpad_address $I2C_BUS $DEVICE_ADDR 2>/dev/null) || true
    local scpad_addr_hex
    scpad_addr_hex=$(echo "$scpad_full" | sed -n '2p')
    if [ -z "$scpad_addr_hex" ]; then
        log_error "Scratchpad address not available (get_scratchpad_address failed). Device may not support 0x2e."
        return 1
    fi

    i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_SCRATCHPAD_WRITE || return 1

    # Config .bin files are little-endian (LSB first per DWORD); send as-is to device.
    local all_bytes
    all_bytes=$(od -An -tx1 "$data_file" | tr -s ' ' | sed 's/^ //')
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

    log_info "Using AN001 6.3: RPTR (0xCE) + MFR_REG_WRITE (0xDE), scratchpad addr $scpad_addr_hex"
    set_rptr $I2C_BUS $DEVICE_ADDR $((scpad_addr_hex)) || return 1
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

# Upload data from scratchpad to OTP (AN001 6.4).
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

    log_info "Waiting for upload completion..."

    local elapsed=0
    local max_wait=$TIMEOUT

    while [ $elapsed -lt $max_wait ]; do
        sleep 1
        elapsed=$((elapsed + 1))

        local result
        result=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND) || continue

        if [ "$result" = "0x00" ]; then
            log_info "Upload completed successfully"
            if [[ -n "$section_params_file" && -f "$section_params_file" ]]; then
                [[ -n "$p_dword1" ]] && log_info "  Section 1st DWORD (5.3): $p_dword1  (hc=$p_hc xv=$p_xv)"
                [[ -n "$p_dword2" ]] && log_info "  Section 2nd DWORD (5.4): $p_dword2  (size=$p_size${p_sz0:+ sz0(LSB)=$p_sz0 sz1(MSB)=$p_sz1})"
            fi
            return 0
        fi
        if [ "$result" = "0xff" ]; then
            log_info "Upload completed (device status 0xff - idle/done)"
            if [[ -n "$section_params_file" && -f "$section_params_file" ]]; then
                [[ -n "$p_dword1" ]] && log_info "  Section 1st DWORD (5.3): $p_dword1  (hc=$p_hc xv=$p_xv)"
                [[ -n "$p_dword2" ]] && log_info "  Section 2nd DWORD (5.4): $p_dword2  (size=$p_size${p_sz0:+ sz0(LSB)=$p_sz0 sz1(MSB)=$p_sz1})"
            fi
            return 0
        fi

        echo -n "."
    done

    echo ""
    log_error "Upload timeout after $max_wait seconds"
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
    local flash_file config_bin_temp=""

    log_info "Starting programming sequence for $CONFIG_FILE"
    log_info "Target: I2C bus $I2C_BUS, address $DEVICE_ADDR"
    echo ""

    detect_device || return 1
    echo ""

    read_device_id || return 1
    echo ""

    clear_faults || return 1
    echo ""

    disable_write_protect || return 1
    echo ""

    check_otp_space || return 1
    echo ""

    log_warn "This will invalidate current OTP and program the new configuration (irreversible; effectively overwrites active config)."
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
    # AN-001 6.2.1: invalidate all existing OTP data before reprogramming entire config (avoids old sections affecting CRC)
    invalidate_otp 1 || return 1
    echo ""

    # .txt/.mic: upload each section individually (AN001 Section 6 - avoid device buffer overrun)
    # .bin: single scratchpad write + upload
    if [[ "$CONFIG_FILE" =~ \.(txt|mic)$ ]]; then
        config_bin_temp=$(mktemp -d) || { log_error "Cannot create temp dir"; return 1; }
        if ! parse_txt_config_to_section_files "$CONFIG_FILE" "$config_bin_temp"; then
            rm -rf "$config_bin_temp"
            return 1
        fi
        section_bins=()
        while IFS= read -r p; do
            [[ -n "$p" ]] && section_bins+=("$p")
        done < "$config_bin_temp/section_list"
        if [ ${#section_bins[@]} -eq 0 ]; then
            log_error "No sections to flash"
            rm -rf "$config_bin_temp"
            return 1
        fi
        log_info "Uploading ${#section_bins[@]} section(s) one by one (AN001 Section 6)"
        echo ""

        for i in "${!section_bins[@]}"; do
            flash_file="${section_bins[$i]}"
            log_info "--- Section $((i + 1))/${#section_bins[@]} ---"
            write_to_scratchpad "$flash_file" || {
                rm -rf "$config_bin_temp"
                return 1
            }
            echo ""
            section_params_file="${flash_file%.bin}.params"
            if [ $DRY_RUN -eq 0 ]; then
                upload_scratchpad_to_otp "$section_params_file" || {
                    rm -rf "$config_bin_temp"
                    return 1
                }
            fi
            if [ $DRY_RUN -eq 0 ] && [ $i -lt $((${#section_bins[@]} - 1)) ]; then
                log_info "Waiting before next section..."
                sleep 2
            fi
            echo ""
        done
    else
        flash_file="$CONFIG_FILE"
        write_to_scratchpad "$flash_file" || return 1
        echo ""
        if [ $DRY_RUN -eq 0 ]; then
            upload_scratchpad_to_otp "" "$flash_file" || return 1
        fi
        echo ""
    fi

    if [ $DRY_RUN -eq 1 ]; then
        log_info "Skip finalize (-s): upload to OTP, write protect, and reset were skipped"
        [[ -n "$config_bin_temp" ]] && rm -rf "$config_bin_temp"
        return 0
    fi

    enable_write_protect || {
        [[ -n "$config_bin_temp" ]] && rm -rf "$config_bin_temp"
        return 1
    }
    echo ""

    reset_device || {
        [[ -n "$config_bin_temp" ]] && rm -rf "$config_bin_temp"
        return 1
    }
    echo ""

    [[ -n "$config_bin_temp" ]] && rm -rf "$config_bin_temp"

    log_info "Programming completed successfully!"
    return 0
}

# Parse and display configuration file structure
parse_config_file() {
    local config_file=$1

    if [ ! -f "$config_file" ]; then
        log_error "File not found: $config_file"
        return 1
    fi

    log_info "Analyzing configuration file: $config_file"
    echo ""

    local file_size
    file_size=$(wc -c < "$config_file" 2>/dev/null); [ -z "$file_size" ] && file_size=0

    echo "File Information:"
    echo "  Size: $file_size bytes"
    echo "  Path: $config_file"
    echo ""

    echo "File Header (first 64 bytes):"
    hexdump -C -n 64 "$config_file"
    echo ""

    echo "Configuration Sections:"

    local header
    header=$(od -An -tx1 -N16 "$config_file" | tr -d ' \n')

    echo "  Header signature: 0x$header"

    if [ -n "${HAS_MD5SUM}" ]; then
        local md5
        md5=$(md5sum "$config_file" | awk '{print $1}')
        echo "  MD5 checksum: $md5"
    fi

    if [ -n "${HAS_SHA256SUM}" ]; then
        local sha256
        sha256=$(sha256sum "$config_file" | awk '{print $1}')
        echo "  SHA256 checksum: $sha256"
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
    if ! set_rptr $bus $addr $((OTP_BASE)) 2>/dev/null; then
        log_error "Readback requires I2C block write support (to set register pointer)."
        log_error "Your controller may not support it. Use an I2C adapter with SMBus block transfer, or skip readback."
        return 1
    fi
    if ! read_otp_dword_hex $bus $addr >/dev/null 2>&1; then
        log_error "Readback requires I2C block read support (to read OTP)."
        log_error "Your controller may not support it. Use an I2C adapter with SMBus block transfer, or skip readback."
        return 1
    fi
    log_info "I2C block transfer probe OK, continuing readback."
    echo ""

    mkdir -p "$out_dir" 2>/dev/null || true

    if [ $have_config -eq 1 ]; then
        # With config: parse .txt, read each section by hc/xv, write to read_NN.bin and compare
        local tmpdir section_bins i hc section_path read_path
        # tmpdir=$(mktemp -d) || { log_error "Cannot create temp dir"; return 1; }
	tmpdir="/tmp/dpc-config/" ; mkdir -p $tmpdir || { log_error "Cannot create temp dir"; return 1; }
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
            hd_hex4=$(od -An -tx1 -N4 "$section_path" 2>/dev/null | tr -d ' \n')
            [ ${#hd_hex4} -lt 8 ] && { log_error "Section file too short: $section_path"; rm -rf "$tmpdir"; return 1; }
            local sec_hc sec_xv sec_cmd sec_loop
            sec_hc=$((16#${hd_hex4:0:2}))
            sec_xv=$((16#${hd_hex4:2:2}))
            sec_cmd=$((16#${hd_hex4:4:2}))
            sec_loop=$((16#${hd_hex4:6:2}))
            read_path="$out_dir/read_$(printf '%02d' $i)_hc_$(printf '%02x' $sec_hc)_loop_$(printf '%02x' $sec_loop)_cmd_$(printf '%02x' $sec_cmd).bin"
            log_info "Section $i: reading from OTP (Loop=0x$(printf '%02x' $sec_loop) CMD=0x$(printf '%02x' $sec_cmd) XV=0x$(printf '%02x' $sec_xv) HC=0x$(printf '%02x' $sec_hc)) -> $read_path"
            if ! read_otp_section $bus $addr $sec_hc $sec_xv $sec_cmd $sec_loop "$read_path"; then
                rm -rf "$tmpdir"
                return 1
            fi
            local cfg_size dev_size
            cfg_size=$(wc -c < "$section_path" 2>/dev/null); [ -z "$cfg_size" ] && cfg_size=0
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
            echo ""
        done
        # rm -rf "$tmpdir"
    else
        # No config: scan OTP from base. HC=0x00 = end of data; HC=0xff = invalid (skip). Save rest as read_NN_hc_XX.bin.
        local addr_32=$((OTP_BASE))
        local max_addr=$((OTP_BASE + 32768))
        local idx=0 max_sections=64
        local hd_hex sz_hex h0 h1 h2 h3 s0 s1 s2 s3 size hc

        while (( addr_32 < max_addr && idx < max_sections )); do
            set_rptr $bus $addr $addr_32 || return 1
            hd_hex=$(read_otp_dword_hex $bus $addr) || return 1
            sz_hex=$(read_otp_dword_hex $bus $addr) || return 1
            read -r h0 h1 h2 h3 <<< "$hd_hex"
            read -r s0 s1 s2 s3 <<< "$sz_hex"
            size=$(( 16#$s0 + (16#$s1 << 8) ))
            hc=$((16#$h0))
            if [ "$hc" -eq 0 ]; then
                log_info "OTP offset 0x$(printf '%x' $(( addr_32 - OTP_BASE ))) HC=0x00 size 0x$(printf '%04x' $size) -- stopping scan"
                break
            fi
            if [ "$size" -le 0 ] || [ "$size" -gt 32768 ]; then
                log_info "OTP offset 0x$(printf '%x' $(( addr_32 - OTP_BASE ))) HC=0x$(printf '%02x' $hc) size 0x$(printf '%04x' $size) invalid -- stopping scan"
                break
            fi
            if [ "$hc" -eq 255 ]; then
                log_verbose "OTP offset 0x$(printf '%x' $(( addr_32 - OTP_BASE ))): HC=0xff (invalid), skipping"
                addr_32=$((addr_32 + size))
                continue
            fi
            local read_path="$out_dir/read_$(printf '%02d' $idx)_hc_$(printf '%02x' $hc).bin"
            log_info "Section $idx: OTP offset 0x$(printf '%x' $(( addr_32 - OTP_BASE ))) HC=0x$(printf '%02x' $hc) size 0x$(printf '%04x' $size) -> $read_path"
            : > "$read_path" || return 1
            hex_dword_to_file "$hd_hex" "$read_path"
            hex_dword_to_file "$sz_hex" "$read_path"
            if [ "$size" -gt 8 ]; then
                read_otp_bytes_to_file $bus $addr $((size - 8)) "$read_path" || return 1
            fi
            addr_32=$((addr_32 + size))
            idx=$((idx + 1))
            echo ""
        done
        log_info "Read $idx section(s) from OTP."
    fi

    log_info "Readback complete. Device sections saved under $out_dir/read_*.bin"
    [ -n "$config_files_dir" ] && log_info "Config section files (parsed from -f): $config_files_dir"
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
        scan_out=$(i2cdetect -y $bus $addr $addr 2>/dev/null)
        # Match cell value (space before addr_hex or UU) to avoid false positive on row label (e.g. "40:" for addr 0x40)
        if echo "$scan_out" | grep -qE " (${addr_hex}|UU)( |$)"; then
            echo -e "${GREEN}Found device at $hex_addr${NC}"

            local mfr_id
            I2C_BUS=$bus DEVICE_ADDR=$hex_addr unbind_driver_for_device
            mfr_id=$(read_device_info_block $bus $hex_addr 0x99 2>/dev/null)
            [ -z "$mfr_id" ] && mfr_id=$(i2cget -y $bus $hex_addr 0x99 2>/dev/null)
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
    block=$(i2cget -y "$bus" "$addr" "$reg" i 32 2>/dev/null) || return 1
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
    echo ""
    echo "Device: Bus $bus, Address $addr"
    echo ""

    local block_regs="0x99 0x9A 0x9B 0x9C 0x9D 0x9E 0xAD"
    local reg_names="PMBUS_MFR_ID PMBUS_MFR_MODEL PMBUS_MFR_REVISION PMBUS_MFR_LOCATION PMBUS_MFR_DATE PMBUS_MFR_SERIAL PMBUS_MFR_DEVICE_ID"
    local names_array=($reg_names)
    local idx=0
    for reg in $block_regs; do
        local name="${names_array[$idx]}"
        local value
        value=$(read_device_info_block "$bus" "$addr" "$reg" 2>/dev/null)
        if [ -n "$value" ]; then
            printf "  %-20s (%-6s): %s\n" "$name" "$reg" "$value"
        else
            value=$(i2cget -y $bus $addr $reg 2>/dev/null || echo "N/A")
            printf "  %-20s (%-6s): %s\n" "$name" "$reg" "$value"
        fi
        idx=$((idx + 1))
    done

    local value
    value=$(i2cget -y $bus $addr 0x79 w 2>/dev/null || echo "N/A")
    printf "  %-20s (%-6s): %s\n" "PMBUS_STATUS_WORD" "0x79" "$value"
    value=$(i2cget -y $bus $addr 0x78 2>/dev/null || echo "N/A")
    printf "  %-20s (%-6s): %s\n" "PMBUS_STATUS_BYTE" "0x78" "$value"
    value=$(i2cget -y $bus $addr 0x01 2>/dev/null || echo "N/A")
    printf "  %-20s (%-6s): %s\n" "OPERATION" "0x01" "$value"
    value=$(i2cget -y $bus $addr 0x10 2>/dev/null || echo "N/A")
    printf "  %-20s (%-6s): %s\n" "WRITE_PROTECT" "0x10" "$value"

    local fw_ts
    fw_ts=$(get_fw_timestamp "$bus" "$addr" 2>/dev/null)
    if [ -n "$fw_ts" ]; then
        local fw_date
        fw_date=$(date -d "@$fw_ts" +"%Y-%m-%d %T" 2>/dev/null) || fw_date="$fw_ts"
        printf "  %-20s (0xFE 0x01): %s (%s)\n" "FW_TIMESTAMP" "$fw_date" "$fw_ts"
    else
        printf "  %-20s (0xFE 0x01): %s\n" "FW_TIMESTAMP" "N/A"
    fi

    get_crc "$bus" "$addr" 2>/dev/null || true

    local otp_remaining
    otp_remaining=$(get_otp_partition_size_remaining "$bus" "$addr" 2>/dev/null)
    if [ -n "$otp_remaining" ]; then
        printf "  %-20s (0xFE 0x10): %s (0x%04x) bytes\n" "OTP_REMAINING_SIZE" "$otp_remaining" "$otp_remaining"
    else
        printf "  %-20s (0xFE 0x10): %s\n" "OTP_REMAINING_SIZE" "N/A"
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
            i2cset -y $bus $addr $PMBUS_PAGE $page 2>/dev/null

            local vout
            vout=$(i2cget -y $bus $addr $PMBUS_READ_VOUT w 2>/dev/null || echo "N/A")
            [[ "$vout" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Output Voltage:    $(printf '%5d' $((vout))) ($vout)" || echo "  Output Voltage:    $vout"

            local vin
            vin=$(i2cget -y $bus $addr $PMBUS_READ_VIN w 2>/dev/null || echo "N/A")
            [[ "$vin" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Input Voltage:     $(printf '%5d' $((vin))) ($vin)" || echo "  Input Voltage:     $vin"

            local iout
            iout=$(i2cget -y $bus $addr $PMBUS_READ_IOUT w 2>/dev/null || echo "N/A")
            [[ "$iout" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Output Current:    $(printf '%5d' $((iout))) ($iout)" || echo "  Output Current:    $iout"

            local temp
            temp=$(i2cget -y $bus $addr $PMBUS_READ_TEMPERATURE_1 w 2>/dev/null || echo "N/A")
            [[ "$temp" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Temperature:       $(printf '%5d' $((temp))) ($temp)" || echo "  Temperature:       $temp"

            local pout
            pout=$(i2cget -y $bus $addr $PMBUS_READ_POUT w 2>/dev/null || echo "N/A")
            [[ "$pout" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Output Power:      $(printf '%5d' $((pout))) ($pout)" || echo "  Output Power:      $pout"

            local pin
            pin=$(i2cget -y $bus $addr $PMBUS_READ_PIN w 2>/dev/null || echo "N/A")
            [[ "$pin" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Input Power:       $(printf '%5d' $((pin))) ($pin)" || echo "  Input Power:       $pin"

            local status
            status=$(i2cget -y $bus $addr $PMBUS_STATUS_BYTE 2>/dev/null || echo "N/A")
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
            value=$(i2cget -y $bus $addr $hex_reg 2>/dev/null)

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

    if [ -n "${HAS_CMP}" ]; then
        echo "Byte Comparison:"
        if cmp -s "$file1" "$file2"; then
            log_info "Files are identical (byte-by-byte)"
        else
            log_warn "Files differ"
            echo ""
            echo "First difference:"
            cmp -l "$file1" "$file2" | head -5
        fi
    fi

    return 0
}

# Main entry point
main() {
    echo "=========================================="
    echo "Infineon XDPE1x2xx Management Tool"
    echo "=========================================="
    echo ""

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

    while getopts "b:a:f:c:i:o:t:svh" opt; do
        case $opt in
            b) I2C_BUS=$OPTARG ;;
            a) DEVICE_ADDR=$OPTARG ;;
            f) CONFIG_FILE=$OPTARG ;;
            c) COMPARE_FILE=$OPTARG ;;
            i) MONITOR_INTERVAL=$OPTARG ;;
            o) OUTPUT_FILE=$OPTARG ;;
            t) TIMEOUT=$OPTARG ;;
            s) DRY_RUN=1 ;;
            v) VERBOSE=$((VERBOSE + 1)) ;;
            h) usage ;;
            *) usage ;;
        esac
    done

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

        parse)
            if [ -z "$CONFIG_FILE" ]; then
                log_error "Parse mode requires -f <file>"
                usage
            fi
            if [[ "$CONFIG_FILE" =~ \.(txt|mic)$ ]]; then
                local out_bin="${OUTPUT_FILE:-${CONFIG_FILE%.*}.bin}"
                if ! parse_txt_config_to_bin "$CONFIG_FILE" "$out_bin"; then
                    exit 1
                fi
                log_info "Binary saved to $out_bin"
            else
                if ! parse_config_file "$CONFIG_FILE"; then
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
