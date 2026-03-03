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
# Per-command timeout for I2C (i2ctransfer/i2cset/i2cget) to avoid host hang on stuck bus. 0 = no timeout.
I2C_CMD_TIMEOUT=${I2C_CMD_TIMEOUT:-5}
# Honor DEBUG from environment (e.g. export DEBUG=1) so get_scratchpad_address etc. log commands
DEBUG=${DEBUG:-0}
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
MFR_ID=0x99
MFR_MODEL=0x9A
MFR_REVISION=0x9B
MFR_LOCATION=0x9C
MFR_DATE=0x9D
MFR_SERIAL=0x9E
MFR_DEVICE_ID=0xAD
MFR_FW_COMMAND=0xFE
MFR_FW_COMMAND_DATA=0xFD
MFR_SPECIFIC_00=0xD0
MFR_RPTR=0xCE
MFR_REG_WRITE=0xDE
MFR_REG_READ=0xDF
# OTP partition 0 base (AN001 10.1)
OTP_BASE=0x10020000
STATUS_WORD=0x79
STATUS_BYTE=0x78
READ_VIN=0x88
READ_VOUT=0x8B
READ_IOUT=0x8C
READ_TEMPERATURE_1=0x8D
READ_POUT=0x96
READ_PIN=0x97

# Scratchpad programming commands (AN001 Table 4; 0x12 = OTP_SECTION_INVALIDATE in doc examples)
CMD_SCRATCHPAD_WRITE=0x01
CMD_SCRATCHPAD_UPLOAD=0x02
CMD_INVALIDATE_OTP=0x12
CMD_READ_OTP=0x04
CMD_CHECK_OTP_SPACE=0x05
# Retrieve scratchpad register address (supported on some controllers); returns 4 bytes d0,d1,d2,d3 (LE) via 0xFD
CMD_GET_SCRATCHPAD_ADDR=0x2e

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
    readback    Parse .txt config, read each section from device OTP, compare or save to read_NN.bin
    compare     Compare two configuration files

FLASH MODE OPTIONS:
    Required:
        -b <bus>        I2C bus number (e.g., 0, 1, 2)
        -a <addr>       Device I2C address in hex (e.g., 0x40)
        -f <file>       Configuration file path

    Optional:
        -n              Dry run (show commands without executing)
        -v              Verbose: log all executed I2C commands (i2ctransfer, i2cset, i2cget) to stderr
        -t <seconds>    Timeout for operations (default: 30)
        -d              Debug mode (verbose output)
    Environment: I2C_CMD_TIMEOUT (default 5) = seconds per i2c command; 0 = no timeout (avoid host hang: use 5)

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
    -f <file>           Configuration .txt/.mic file (defines sections to read)
    -b <bus>            I2C bus number
    -a <addr>           Device I2C address (hex)
    -o <dir>            Output directory for read_NN.bin files (default: current dir). Each section is compared with config.
    Note: Readback requires I2C/SMBus block write and block read. If your adapter does not support these, use another I2C adapter or skip readback.

COMPARE MODE OPTIONS:
    -f <file1>          First configuration file
    -c <file2>          Second configuration file

EXAMPLES:
    # Flash device (dry run first!)
    $(basename $0) flash -b 2 -a 0x40 -f config.bin -n -d
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

    # Readback: read each section from device OTP, save to read_NN.bin and compare with .txt
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
    if [ $DEBUG -eq 1 ]; then
        echo -e "[DEBUG] $1" >&2
    fi
}

# Log executed I2C command to stderr when -v (verbose) is set
log_verbose() {
    if [ $VERBOSE -eq 1 ]; then
        echo -e "[VERBOSE] $1" >&2
    fi
}

# Execute i2c command with error handling
i2c_write() {
    local bus=$1
    local addr=$2
    local reg=$3
    shift 3
    local data=("$@")

    if [ $DRY_RUN -eq 1 ]; then
        log_info "[DRY-RUN] i2cset -y $bus $addr $reg ${data[*]}"
        return 0
    fi

    log_debug "i2cset -y $bus $addr $reg ${data[*]}"
    log_verbose "i2cset -y $bus $addr $reg ${data[*]}"
    local rc=0
    if command -v timeout &>/dev/null && [ "$I2C_CMD_TIMEOUT" -gt 0 ] 2>/dev/null; then
        timeout "$I2C_CMD_TIMEOUT" i2cset -y $bus $addr $reg "${data[@]}" 2>/dev/null || rc=$?
    else
        i2cset -y $bus $addr $reg "${data[@]}" 2>/dev/null || rc=$?
    fi
    if [ $rc -ne 0 ]; then
        [ $rc -eq 124 ] && log_error "i2cset timed out after ${I2C_CMD_TIMEOUT}s"
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

    if [ $DRY_RUN -eq 1 ]; then
        if [ "$length" = "1" ]; then
            log_info "[DRY-RUN] i2cget -y $bus $addr $reg"
        else
            log_info "[DRY-RUN] i2cget -y $bus $addr $reg w"
        fi
        echo -n "0xff"
        return 0
    fi

    log_debug "i2cget -y $bus $addr $reg"
    [ "$length" = "1" ] && log_verbose "i2cget -y $bus $addr $reg" || log_verbose "i2cget -y $bus $addr $reg w"
    local result
    if command -v timeout &>/dev/null && [ "$I2C_CMD_TIMEOUT" -gt 0 ] 2>/dev/null; then
        if [ "$length" = "1" ]; then
            result=$(timeout "$I2C_CMD_TIMEOUT" i2cget -y $bus $addr $reg 2>/dev/null)
        else
            result=$(timeout "$I2C_CMD_TIMEOUT" i2cget -y $bus $addr $reg w 2>/dev/null)
        fi
    else
        if [ "$length" = "1" ]; then
            result=$(i2cget -y $bus $addr $reg 2>/dev/null)
        else
            result=$(i2cget -y $bus $addr $reg w 2>/dev/null)
        fi
    fi
    local rc=$?
    if [ $rc -ne 0 ]; then
        [ $rc -eq 124 ] && log_error "i2cget timed out after ${I2C_CMD_TIMEOUT}s"
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

    if [ $DRY_RUN -eq 1 ]; then
        log_info "[DRY-RUN] i2ctransfer -y $bus w1@$addr $reg r${num_bytes}@$addr"
        # Default N hex bytes for dry-run (up to 8)
        echo "00 00 00 00 00 00 00 00" | cut -d' ' -f1-$num_bytes
        return 0
    fi

    log_verbose "i2ctransfer -y $bus w1@$addr $reg r${num_bytes}@$addr"
    local line
    if command -v timeout &>/dev/null && [ "$I2C_CMD_TIMEOUT" -gt 0 ] 2>/dev/null; then
        line=$(timeout "$I2C_CMD_TIMEOUT" i2ctransfer -y $bus "w1@$addr" $reg "r${num_bytes}@$addr" 2>/dev/null)
        local rc=$?
        [ $rc -eq 124 ] && log_error "i2ctransfer (block read) timed out after ${I2C_CMD_TIMEOUT}s"
        [ $rc -ne 0 ] && return 1
    else
        line=$(i2ctransfer -y $bus "w1@$addr" $reg "r${num_bytes}@$addr" 2>/dev/null) || return 1
    fi
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
    if [ $DRY_RUN -eq 1 ]; then
        log_info "[DRY-RUN] No real query; showing default placeholder."
        log_info "Scratchpad register: $MFR_SPECIFIC_00 (dry-run placeholder)"
        echo "$MFR_SPECIFIC_00"
        return 0
    fi
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

    if [ $DRY_RUN -eq 1 ]; then
        log_info "[DRY-RUN] i2ctransfer -y $bus w$((${#data[@]}+1))@$addr $reg ${data[*]}"
        return 0
    fi

    log_debug "i2ctransfer -y $bus w$((${#data[@]}+1))@$addr $reg ${data[*]}"
    log_verbose "i2ctransfer -y $bus w$((${#data[@]}+1))@$addr $reg ${data[*]}"
    local rc=0
    if command -v timeout &>/dev/null && [ "$I2C_CMD_TIMEOUT" -gt 0 ] 2>/dev/null; then
        timeout "$I2C_CMD_TIMEOUT" i2ctransfer -y $bus "w$((${#data[@]}+1))@$addr" $reg "${data[@]}" 2>/dev/null || rc=$?
    else
        i2ctransfer -y $bus "w$((${#data[@]}+1))@$addr" $reg "${data[@]}" 2>/dev/null || rc=$?
    fi
    if [ $rc -ne 0 ]; then
        [ $rc -eq 124 ] && log_error "i2ctransfer timed out after ${I2C_CMD_TIMEOUT}s"
        log_error "Failed to write to device (i2ctransfer)"
        return 1
    fi
    return 0
}

# Fallback for adapters that do not support multi-byte i2ctransfer: write each byte via i2cset to consecutive registers (reg+0, reg+1, ...).
# Note: Many Infineon VRs do not accept single-byte writes to 0xD0; use word-by-word fallback instead.
i2c_block_write_byte_by_byte() {
    local bus=$1
    local addr=$2
    local reg=$3
    shift 3
    local data=("$@")
    local i=0
    local r

    for b in "${data[@]}"; do
        r=$(printf '0x%02x' $((reg + i)))
        if [ $DRY_RUN -eq 1 ]; then
            log_info "[DRY-RUN] i2cset -y $bus $addr $r $b"
        else
            log_verbose "i2cset -y $bus $addr $r $b"
            local rc=0
            if command -v timeout &>/dev/null && [ "$I2C_CMD_TIMEOUT" -gt 0 ] 2>/dev/null; then
                timeout "$I2C_CMD_TIMEOUT" i2cset -y $bus $addr $r $b 2>/dev/null || rc=$?
            else
                i2cset -y $bus $addr $r $b 2>/dev/null || rc=$?
            fi
            if [ $rc -ne 0 ]; then
                [ $rc -eq 124 ] && log_error "i2cset (byte) timed out after ${I2C_CMD_TIMEOUT}s"
                log_error "Failed to write byte at offset $i (reg $r) via i2cset"
                return 1
            fi
        fi
        i=$((i + 1))
        if [ $DRY_RUN -eq 0 ] && [ $((i % 100)) -eq 0 ]; then
            echo -n "."
        fi
    done
    return 0
}

# Fallback: write 2 bytes at a time to reg using SMBus word write (i2cset ... reg value w).
# Device must accept word writes to scratchpad and append; same reg used for each word.
i2c_block_write_word_by_word() {
    local bus=$1
    local addr=$2
    local reg=$3
    shift 3
    local data=("$@")
    local n=${#data[@]}
    local i=0
    local word_val

    while [ $i -lt $n ]; do
        local b0 b1
        b0=${data[$i]}
        if [ $((i + 1)) -lt $n ]; then
            b1=${data[$((i+1))]}
        else
            b1=0x00
        fi
        word_val=$(( (b1 << 8) | (b0 & 0xff) ))
        word_val=$((word_val & 0xFFFF))
        if [ $DRY_RUN -eq 1 ]; then
            log_info "[DRY-RUN] i2cset -y $bus $addr $reg $word_val w"
        else
            log_verbose "i2cset -y $bus $addr $reg $word_val w"
            local rc=0
            if command -v timeout &>/dev/null && [ "$I2C_CMD_TIMEOUT" -gt 0 ] 2>/dev/null; then
                timeout "$I2C_CMD_TIMEOUT" i2cset -y $bus $addr $reg $word_val w 2>/dev/null || rc=$?
            else
                i2cset -y $bus $addr $reg $word_val w 2>/dev/null || rc=$?
            fi
            if [ $rc -ne 0 ]; then
                [ $rc -eq 124 ] && log_error "i2cset (word) timed out after ${I2C_CMD_TIMEOUT}s"
                log_error "Failed to write word at offset $i (reg $reg) via i2cset w"
                return 1
            fi
        fi
        i=$((i + 2))
        if [ $DRY_RUN -eq 0 ] && ( [ $((i % 64)) -eq 0 ] || [ $i -ge $n ] ); then
            echo -n "."
        fi
    done
    return 0
}

# Read one DWORD (4 bytes) from MFR_REG_READ; RPTR must be set and auto-increments.
# Uses i2ctransfer (w1 reg, r4) only. Outputs space-separated hex bytes (no 0x), e.g. "00 00 00 04".
read_otp_dword_hex() {
    local bus=$1
    local addr=$2
    if [ $DRY_RUN -eq 1 ]; then
        log_info "[DRY-RUN] i2ctransfer -y $bus w1@$addr $MFR_REG_READ r4@$addr"
        echo "00 00 00 00"
        return 0
    fi
    log_verbose "i2ctransfer -y $bus w1@$addr $MFR_REG_READ r4@$addr"
    local line
    if command -v timeout &>/dev/null; then
        line=$(timeout 3 i2ctransfer -y $bus w1@$addr $MFR_REG_READ r4@$addr 2>/dev/null) || return 1
    else
        line=$(i2ctransfer -y $bus w1@$addr $MFR_REG_READ r4@$addr 2>/dev/null) || return 1
    fi
    # i2ctransfer read output is hex bytes; normalize to space-separated without 0x
    echo "$line" | sed 's/0x//g'
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

# Find section by header_code and xvcode in OTP, read full section to out_file. AN001 10.1.
# Returns 0 on success. OTP base 0x10020000; section layout: 4B header (byte0=hc, byte1=xv), 4B size (LE), then data.
read_otp_section() {
    local bus=$1
    local addr=$2
    local header_code=$3
    local xvcode=$4
    local out_file=$5
    local addr_32=$((OTP_BASE))
    local max_addr=$((OTP_BASE + 32768))
    local max_iters=512
    local iters=0

    : > "$out_file" || return 1

    while (( addr_32 < max_addr && iters < max_iters )); do
        iters=$((iters + 1))
        set_rptr $bus $addr $addr_32 || return 1
        local hd_hex sz_hex
        hd_hex=$(read_otp_dword_hex $bus $addr) || return 1
        sz_hex=$(read_otp_dword_hex $bus $addr) || return 1
        local h0 h1 h2 h3 s0 s1 s2 s3
        read -r h0 h1 h2 h3 <<< "$hd_hex"
        read -r s0 s1 s2 s3 <<< "$sz_hex"
        local size=$(( 16#$s0 + (16#$s1 << 8) + (16#$s2 << 16) + (16#$s3 << 24) ))
        local hc=$((16#$h0))
        local xv=$((16#$h1))
        # Unprogrammed OTP often reads as 0xff; cap size to avoid overflow or huge skip
        if [ "$size" -gt 32768 ]; then
            size=8
        fi
        if [ "$hc" -eq "$header_code" ] && [ "$xv" -eq "$xvcode" ]; then
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
        log_error "Section hc=$header_code xv=$xvcode not found (max iterations reached)"
    else
        log_error "Section hc=$header_code xv=$xvcode not found in OTP"
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

# Check if required tools are installed
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

    log_debug "All dependencies satisfied"
    return 0
}

# Detect device on I2C bus
detect_device() {
    log_info "Detecting device at address $DEVICE_ADDR on bus $I2C_BUS..."

    if [ $DRY_RUN -eq 1 ]; then
        log_info "[DRY-RUN] i2cdetect -y $I2C_BUS $DEVICE_ADDR $DEVICE_ADDR"
        return 0
    fi

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
# return 0; # VV: Skip unbinding for now
    [ -n "$I2C_BUS" ] && [ -n "$DEVICE_ADDR" ] || return 0
    if [ $DRY_RUN -eq 1 ]; then
        log_info "[DRY-RUN] (unbind driver: echo <bus>-<addr> > /sys/bus/i2c/drivers/<driver>/unbind)"
        return 0
    fi
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

# Rebind the driver if we had unbound it (so device works again under the kernel driver).
rebind_driver_if_unbound() {
#return 0; # VV: Skip rebinding for now
    [ -n "$DRIVER_UNBIND_DEVID" ] && [ -n "$DRIVER_UNBIND_NAME" ] || return 0
    local bind_file="/sys/bus/i2c/drivers/$DRIVER_UNBIND_NAME/bind"
    if [ -f "$bind_file" ]; then
        echo "$DRIVER_UNBIND_DEVID" > "$bind_file" 2>/dev/null
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
    mfr_id=$(read_device_info_block $I2C_BUS $DEVICE_ADDR $MFR_ID 2>/dev/null)
    [ -z "$mfr_id" ] && mfr_id=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_ID 2>/dev/null)
    if [ -z "$mfr_id" ]; then
        log_error "Failed to read Manufacturer ID"
        return 1
    fi
    log_info "Manufacturer ID: $mfr_id"

    local mfr_model
    mfr_model=$(read_device_info_block $I2C_BUS $DEVICE_ADDR $MFR_MODEL 2>/dev/null)
    [ -z "$mfr_model" ] && mfr_model=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_MODEL 2>/dev/null)
    if [ -z "$mfr_model" ]; then
        log_error "Failed to read Model"
        return 1
    fi
    log_info "Model: $mfr_model"

    local mfr_rev
    mfr_rev=$(read_device_info_block $I2C_BUS $DEVICE_ADDR $MFR_REVISION 2>/dev/null)
    [ -z "$mfr_rev" ] && mfr_rev=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_REVISION 2>/dev/null)
    if [ -z "$mfr_rev" ]; then
        log_error "Failed to read Revision"
        return 1
    fi
    log_info "Revision: $mfr_rev"

    return 0
}

# Clear any existing faults
clear_faults() {
    log_info "Clearing device faults..."
    i2c_write $I2C_BUS $DEVICE_ADDR $PMBUS_CLEAR_FAULTS || return 1
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

# Check OTP space availability
check_otp_space() {
    log_info "Checking OTP space availability..."

    i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_CHECK_OTP_SPACE || return 1
    sleep 0.5

    local result
    result=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND) || return 1

    log_debug "OTP space check result: $result"

    # 0x00 = success; 0xff = idle/no status clear (e.g. XDPE1A2G7B) – treat as OK
    if [ "$result" = "0x00" ] || [ "$result" = "0xff" ]; then
        log_info "OTP space available"
    else
        log_warn "OTP space may be limited or full (status: $result)"
    fi

    return 0
}

# Invalidate existing OTP data. Per AN001: set 0xFD (param), then 0xFE (command). Use i2ctransfer for 0xFD, i2cset for 0xFE.
invalidate_otp() {
    local invalidate_all=${1:-1}

    if [ $invalidate_all -eq 1 ]; then
        log_info "Invalidating entire OTP configuration..."
    else
        log_info "Invalidating specific OTP section..."
    fi

    # AN001: BLOCK_WRITE(0xFD, 4, 0xfe, 0xfe, 0, 0) then WRITE_BYTE(0xFE, invalidation_cmd). 0xfe,0xfe = all sections.
    if [ $invalidate_all -eq 1 ]; then
        # 1) Set MFR_FW_COMMAND_DATA (0xFD) to 0xfe 0xfe 0x00 0x00 (invalidate all)
        local fd_ok=0
        if write_dword $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND_DATA 0xfe 0xfe 0x00 0x00 2>/dev/null; then
            fd_ok=1
        else
            # Fallback: four single-byte writes to 0xFD
            log_info "Trying 4x single-byte write to 0xFD..."
            if ( i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND_DATA 0xfe 2>/dev/null && \
                 i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND_DATA 0xfe 2>/dev/null && \
                 i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND_DATA 0x00 2>/dev/null && \
                 i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND_DATA 0x00 2>/dev/null ); then
                fd_ok=1
            fi
        fi
        if [ $fd_ok -eq 0 ]; then
            log_warn "Could not write to 0xFD (adapter may not support multi-byte or 0xFD). Trying command-only invalidation (0xFE)..."
        fi
        # 2) Send invalidation command (single byte to 0xFE)
        if ! i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_INVALIDATE_OTP; then
            log_error "OTP invalidation: failed to send command (0xFE)"
            return 1
        fi
    else
        log_error "OTP section invalidation (specific section) requires setting 0xFD with section; use invalidate all or adapter with i2ctransfer"
        return 1
    fi
    sleep 1

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

# Parse XDPE .txt/.mic config (AN001 format) to binary; write to output path.
# Format: [Configuration Data] then rows "XXX DWORD0 DWORD1 DWORD2 DWORD3" (3-digit hex offset + 8-char hex DWORDs).
# Each DWORD written as 4 bytes big-endian. Logs section name, type/page, and data count. Returns 0 on success.
parse_txt_config_to_bin() {
    local txt_file="$1"
    local bin_file="$2"
    local in_section=0
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
        if [[ -n "$current_section_name" && $section_dwords -gt 0 ]]; then
            local type_str=""
            if [[ -n "$section_first_dword" ]]; then
                local code=$((16#${section_first_dword:6:2}))
                type_str=$(section_type_name "$code")
            fi
            log_info "  Section: $current_section_name"
            [[ -n "$type_str" ]] && log_info "    Type / programming: $type_str"
            log_info "    Data: $section_dwords DWORDs ($(( section_dwords * 4 )) bytes)"
        fi
    }

    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^\[Configuration[[:space:]]Data\] ]]; then
            in_section=1
            log_info "Parsing [Configuration Data] from $txt_file"
            echo ""
            continue
        fi
        if [[ "$line" =~ ^\[End[[:space:]]Configuration[[:space:]]Data\] ]]; then
            log_section_summary
            break
        fi
        [[ $in_section -eq 0 ]] && continue

        # Section header lines (//XV0 Config, //XV0 PMBus LoopA User, etc.)
        if [[ "$line" =~ ^// ]]; then
            log_section_summary
            current_section_name="${line#//}"
            current_section_name=$(echo "$current_section_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            section_dwords=0
            section_first_dword=""
            continue
        fi

        # Data row: 3 hex digits then one or more 8-char hex DWORDs
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
                printf '%b' "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' "$b0" "$b1" "$b2" "$b3")" >> "$bin_file" || return 1
                byte_count=$((byte_count + 4))
                row_dwords=$((row_dwords + 1))
            done
            section_dwords=$((section_dwords + row_dwords))
        fi
    done < "$txt_file"

    if [[ $in_section -eq 0 ]]; then
        log_error "No [Configuration Data] section found in $txt_file"
        rm -f "$bin_file"
        return 1
    fi

    echo ""
    log_info "Total: $byte_count bytes written to binary"
    return 0
}

# Parse .txt/.mic into one binary file per section (AN001). Writes section_0.bin, section_1.bin, ...
# into out_dir and writes the list of paths to out_dir/section_list (one per line).
# Returns 0 on success. Use for section-by-section flash to avoid device buffer overrun.
parse_txt_config_to_section_files() {
    local txt_file="$1"
    local out_dir="$2"
    local in_section=0
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
        if [[ -n "$current_section_name" && $section_dwords -gt 0 ]]; then
            local type_str=""
            if [[ -n "$section_first_dword" ]]; then
                local code=$((16#${section_first_dword:6:2}))
                type_str=$(section_type_name "$code")
            fi
            log_info "  Section: $current_section_name"
            [[ -n "$type_str" ]] && log_info "    Type / programming: $type_str"
            log_info "    Data: $section_dwords DWORDs ($(( section_dwords * 4 )) bytes)"
        fi
    }

    start_section_file() {
        current_section_bin="$out_dir/section_${section_index}.bin"
        : > "$current_section_bin" || return 1
        echo "$current_section_bin" >> "$section_list_file"
    }

    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^\[Configuration[[:space:]]Data\] ]]; then
            in_section=1
            log_info "Parsing [Configuration Data] for section-by-section flash from $txt_file"
            echo ""
            continue
        fi
        if [[ "$line" =~ ^\[End[[:space:]]Configuration[[:space:]]Data\] ]]; then
            log_section_summary
            break
        fi
        [[ $in_section -eq 0 ]] && continue

        if [[ "$line" =~ ^// ]]; then
            log_section_summary
            current_section_name="${line#//}"
            current_section_name=$(echo "$current_section_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            section_dwords=0
            section_first_dword=""
            start_section_file || return 1
            section_index=$((section_index + 1))
            continue
        fi

        if [[ "$line" =~ ^[0-9A-Fa-f]{3}[[:space:]] ]]; then
            [[ -z "$current_section_bin" ]] && continue
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
                printf '%b' "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' "$b0" "$b1" "$b2" "$b3")" >> "$current_section_bin" || return 1
                section_dwords=$((section_dwords + 1))
            done
        fi
    done < "$txt_file"

    if [[ $in_section -eq 0 ]]; then
        log_error "No [Configuration Data] section found in $txt_file"
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

# Write data to scratchpad memory (AN001 6.3: RPTR + 0xDE when 4-byte addr available; else legacy reg write).
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

    # Get scratchpad info: line1 = reg (d0), line2 = 4-byte address LE (e.g. 0x2005e000)
    local scpad_full
    scpad_full=$(get_scratchpad_address $I2C_BUS $DEVICE_ADDR 2>/dev/null) || true
    local scpad_reg
    scpad_reg=$(echo "$scpad_full" | head -n1)
    local scpad_addr_hex
    scpad_addr_hex=$(echo "$scpad_full" | sed -n '2p')
    [ -z "$scpad_reg" ] && scpad_reg=$MFR_SPECIFIC_00

    # Put device in scratchpad-write mode (required before writing to scratchpad)
    i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_SCRATCHPAD_WRITE || return 1

    # Read file and convert to little-endian DWORDs
    local all_bytes
    all_bytes=$(od -An -tx1 "$data_file" | tr -s ' ' | sed 's/^ //')
    local data_array=()
    for b in $all_bytes; do data_array+=("0x$b"); done
    data_array=( $(bytes_to_little_endian_dwords "${data_array[@]}") )

    local num_dwords=$((${#data_array[@]} / 4))
    local remainder_bytes=$((${#data_array[@]} % 4))
    if [ $remainder_bytes -gt 0 ]; then
        while [ $remainder_bytes -lt 4 ]; do
            data_array+=(0x00)
            remainder_bytes=$((remainder_bytes + 1))
        done
        num_dwords=$((num_dwords + 1))
    fi

    # AN001 6.3: BLOCK_WRITE(PMB_Addr, RPTR, 4, scpad0..3) then BLOCK_WRITE(PMB_Addr, 0xDE, 4, DWORD...)
    if [ -n "$scpad_addr_hex" ]; then
        log_info "Using AN001 6.3: RPTR (0xCE) + MFR_REG_WRITE (0xDE), scratchpad addr $scpad_addr_hex"
        if [ $DRY_RUN -eq 1 ]; then
            log_info "[DRY-RUN] set_rptr $I2C_BUS $DEVICE_ADDR $scpad_addr_hex"
        else
            set_rptr $I2C_BUS $DEVICE_ADDR $((scpad_addr_hex)) || return 1
        fi
        log_info "Writing $num_dwords DWORD(s) to 0xDE (w6: reg 0xDE + 0x04 + 4 bytes)..."
        local d
        for ((d=0; d<num_dwords; d++)); do
            local i=$((d * 4))
            local b0=${data_array[$i]}
            local b1=${data_array[$((i+1))]}
            local b2=${data_array[$((i+2))]}
            local b3=${data_array[$((i+3))]}
            if [ $DRY_RUN -eq 1 ]; then
                log_info "[DRY-RUN] write_dword ... 0xDE 0x04 $b0 $b1 $b2 $b3"
            elif ! write_dword $I2C_BUS $DEVICE_ADDR $MFR_REG_WRITE 0x04 $b0 $b1 $b2 $b3; then
                log_error "Scratchpad write to 0xDE failed at DWORD $d"
                return 1
            fi
            sleep 0.002
            if [ $((d % 8)) -eq 0 ] || [ $d -eq $((num_dwords - 1)) ]; then
                echo -n "."
            fi
        done
        echo ""
        log_info "Scratchpad write completed"
        return 0
    fi

    # Legacy path: no 4-byte address (device did not report via 0x2e); write to scpad reg (0xD0 or d0)
    log_info "Using scratchpad register: $scpad_reg (legacy; no 4-byte addr from device)"
    log_info "Writing $num_dwords DWORD(s) (${#data_array[@]} bytes) via write_dword..."

    local use_word_fallback=0
    local d
    for ((d=0; d<num_dwords; d++)); do
        local i=$((d * 4))
        local b0=${data_array[$i]}
        local b1=${data_array[$((i+1))]}
        local b2=${data_array[$((i+2))]}
        local b3=${data_array[$((i+3))]}
        if [ $DRY_RUN -eq 1 ]; then
            write_dword $I2C_BUS $DEVICE_ADDR $scpad_reg 0x04 $b0 $b1 $b2 $b3 || true
        elif ! write_dword $I2C_BUS $DEVICE_ADDR $scpad_reg 0x04 $b0 $b1 $b2 $b3; then
            if [ $d -eq 0 ]; then
                log_warn "DWORD write failed (adapter may not support 5-byte transfer). Trying word-by-word (SMBus) write..."
                use_word_fallback=1
            else
                return 1
            fi
            break
        fi
        sleep 0.002
        if [ $((d % 8)) -eq 0 ] || [ $d -eq $((num_dwords - 1)) ]; then
            echo -n "."
        fi
    done

    if [ $use_word_fallback -eq 1 ]; then
        log_info "Writing $file_size bytes word-by-word (SMBus) to $scpad_reg..."
        if [ $DRY_RUN -eq 1 ]; then
            i2c_block_write_word_by_word $I2C_BUS $DEVICE_ADDR $scpad_reg "${data_array[@]}" || true
        elif ! i2c_block_write_word_by_word $I2C_BUS $DEVICE_ADDR $scpad_reg "${data_array[@]}"; then
            log_error "Word-by-word scratchpad write failed"
            log_error "Adapter must support at least 5-byte i2ctransfer (reg+4) or SMBus word write to $scpad_reg."
            return 1
        fi
    fi

    echo ""
    log_info "Scratchpad write completed"
    return 0
}

# Upload data from scratchpad to OTP
upload_scratchpad_to_otp() {
    log_info "Uploading configuration from scratchpad to OTP..."

    i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_SCRATCHPAD_UPLOAD || return 1

    [ $DRY_RUN -eq 1 ] && return 0

    log_info "Upload initiated, waiting for completion..."

    local elapsed=0
    local max_wait=$TIMEOUT

    while [ $elapsed -lt $max_wait ]; do
        sleep 1
        elapsed=$((elapsed + 1))

        local result
        result=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND) || continue

        if [ "$result" = "0x00" ]; then
            log_info "Upload completed successfully"
            return 0
        fi

        echo -n "."
    done

    echo ""
    log_error "Upload timeout after $TIMEOUT seconds"
    return 1
}

# Verify programmed data
verify_programming() {
    log_info "Verifying programmed configuration..."

    i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_READ_OTP || return 1

    [ $DRY_RUN -eq 1 ] && return 0

    local elapsed=0
    local max_wait=${TIMEOUT:-30}
    local result=""

    while [ $elapsed -lt $max_wait ]; do
        sleep 1
        elapsed=$((elapsed + 1))
        result=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND) || continue
        if [ "$result" = "0x00" ]; then
            log_info "Verification passed"
            return 0
        fi
        # Some parts (e.g. XDPE1A2G7B) leave 0xFE at 0xff when idle; treat as success
        if [ "$result" = "0xff" ]; then
            log_info "Verification passed (device status 0xff - idle/no status clear)"
            return 0
        fi
    done

    log_error "Verification failed with code: $result (expected 0x00 or 0xff after ${max_wait}s)"
    return 1
}

# Reset device to load new configuration
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
    if [ $DRY_RUN -eq 0 ]; then
        # Interactive confirmation with input validation
        local confirm=""
        read -r -p "Continue? (yes/no): " confirm || {
            log_error "Failed to read user input (non-interactive environment?)"
            return 1
        }

        # Accept multiple variations of yes
        confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$confirm" =~ ^(yes|y)$ ]]; then
            log_info "Programming cancelled by user (entered: '$confirm')"
            return 1
        fi
    fi
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
            upload_scratchpad_to_otp || {
                rm -rf "$config_bin_temp"
                return 1
            }
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
        upload_scratchpad_to_otp || return 1
        echo ""
    fi

    verify_programming || {
        [[ -n "$config_bin_temp" ]] && rm -rf "$config_bin_temp"
        return 1
    }
    echo ""

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

    if [ $DRY_RUN -eq 1 ]; then
        log_info "DRY-RUN: Programming sequence completed (no actual writes performed)"
    else
        log_info "Programming completed successfully!"
    fi
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

    if command -v md5sum &> /dev/null; then
        local md5
        md5=$(md5sum "$config_file" | awk '{print $1}')
        echo "  MD5 checksum: $md5"
    fi

    if command -v sha256sum &> /dev/null; then
        local sha256
        sha256=$(sha256sum "$config_file" | awk '{print $1}')
        echo "  SHA256 checksum: $sha256"
    fi

    return 0
}

# Readback: parse .txt config, read each section from device OTP, save to read_NN.bin and/or compare with config.
# Requires -f .txt/.mic -b bus -a addr. Optional -o out_dir (default: current dir).
# XVcode 0 used for .txt. Compares each section with config and reports match/diff.
readback_from_device() {
    local txt_file="$CONFIG_FILE"
    local bus="$I2C_BUS"
    local addr="$DEVICE_ADDR"
    local out_dir="${OUTPUT_FILE:-.}"
    local tmpdir section_bins i hc section_path read_path

    if [[ ! "$txt_file" =~ \.(txt|mic)$ ]]; then
        log_error "Readback requires a .txt or .mic configuration file (-f)"
        return 1
    fi

    log_info "Readback: parsing $txt_file and reading sections from device (bus $bus addr $addr)"
    echo ""

    unbind_driver_for_device

    # Readback requires I2C/SMBus block write (to set RPTR) and block read (to read OTP). Probe once.
    if [ $DRY_RUN -eq 0 ]; then
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
    fi

    tmpdir=$(mktemp -d) || { log_error "Cannot create temp dir"; return 1; }

    if ! parse_txt_config_to_section_files "$txt_file" "$tmpdir"; then
        rm -rf "$tmpdir"
        return 1
    fi

    section_bins=()
    while IFS= read -r p; do
        [[ -n "$p" ]] && section_bins+=("$p")
    done < "$tmpdir/section_list"

    mkdir -p "$out_dir" 2>/dev/null || true

    for i in "${!section_bins[@]}"; do
        section_path="${section_bins[$i]}"
        read_path="$out_dir/read_$(printf '%02d' $i).bin"
        # Header code = LSB of first DWORD in section (4th byte in our big-endian file)
        hc=$(od -An -tx1 -N4 "$section_path" 2>/dev/null | tr -d ' \n')
        hc=$((16#${hc:6:2}))
        log_info "Section $i: reading from OTP (header 0x$(printf '%02x' $hc)) -> $read_path"
        if [ $DRY_RUN -eq 1 ]; then
            log_info "DRY-RUN: Would read section and write to $read_path"
        else
            if ! read_otp_section $bus $addr $hc 0 "$read_path"; then
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
        fi
        echo ""
    done

    rm -rf "$tmpdir"
    log_info "Readback complete. Device sections saved under $out_dir/read_*.bin"
    return 0
}

# Scan I2C bus for Infineon devices
scan_infineon_devices() {
    local bus=$1

    log_info "Scanning I2C bus $bus for Infineon XDPE devices..."
    echo ""

    if ! command -v i2cdetect &> /dev/null; then
        log_error "i2cdetect not found. Install i2c-tools package."
        return 1
    fi

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

            if command -v i2cget &> /dev/null; then
                local mfr_id
                # Unbind driver briefly so we can read MFR_ID (device may show as UU when bound)
                I2C_BUS=$bus DEVICE_ADDR=$hex_addr unbind_driver_for_device
                mfr_id=$(read_device_info_block $bus $hex_addr 0x99 2>/dev/null)
                [ -z "$mfr_id" ] && mfr_id=$(i2cget -y $bus $hex_addr 0x99 2>/dev/null)
                rebind_driver_if_unbound
                echo "  MFR_ID: ${mfr_id:-N/A}"
            fi
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

    I2C_BUS=$bus DEVICE_ADDR=$addr unbind_driver_for_device
    log_info "Reading device information..."
    echo ""
    echo "Device: Bus $bus, Address $addr"
    echo ""

    local block_regs="0x99 0x9A 0x9B 0x9C 0x9D 0x9E 0xAD"
    local reg_names="MFR_ID MFR_MODEL MFR_REVISION MFR_LOCATION MFR_DATE MFR_SERIAL MFR_DEVICE_ID"
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
    printf "  %-20s (%-6s): %s\n" "STATUS_WORD" "0x79" "$value"
    value=$(i2cget -y $bus $addr 0x78 2>/dev/null || echo "N/A")
    printf "  %-20s (%-6s): %s\n" "STATUS_BYTE" "0x78" "$value"
    value=$(i2cget -y $bus $addr 0x01 2>/dev/null || echo "N/A")
    printf "  %-20s (%-6s): %s\n" "OPERATION" "0x01" "$value"
    value=$(i2cget -y $bus $addr 0x10 2>/dev/null || echo "N/A")
    printf "  %-20s (%-6s): %s\n" "WRITE_PROTECT" "0x10" "$value"

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
            vout=$(i2cget -y $bus $addr $READ_VOUT w 2>/dev/null || echo "N/A")
            [[ "$vout" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Output Voltage:    $(printf '%5d' $((vout))) ($vout)" || echo "  Output Voltage:    $vout"

            local vin
            vin=$(i2cget -y $bus $addr $READ_VIN w 2>/dev/null || echo "N/A")
            [[ "$vin" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Input Voltage:     $(printf '%5d' $((vin))) ($vin)" || echo "  Input Voltage:     $vin"

            local iout
            iout=$(i2cget -y $bus $addr $READ_IOUT w 2>/dev/null || echo "N/A")
            [[ "$iout" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Output Current:    $(printf '%5d' $((iout))) ($iout)" || echo "  Output Current:    $iout"

            local temp
            temp=$(i2cget -y $bus $addr $READ_TEMPERATURE_1 w 2>/dev/null || echo "N/A")
            [[ "$temp" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Temperature:       $(printf '%5d' $((temp))) ($temp)" || echo "  Temperature:       $temp"

            local pout
            pout=$(i2cget -y $bus $addr $READ_POUT w 2>/dev/null || echo "N/A")
            [[ "$pout" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Output Power:      $(printf '%5d' $((pout))) ($pout)" || echo "  Output Power:      $pout"

            local pin
            pin=$(i2cget -y $bus $addr $READ_PIN w 2>/dev/null || echo "N/A")
            [[ "$pin" =~ ^0x[0-9a-fA-F]+$ ]] && echo "  Input Power:       $(printf '%5d' $((pin))) ($pin)" || echo "  Input Power:       $pin"

            local status
            status=$(i2cget -y $bus $addr $STATUS_BYTE 2>/dev/null || echo "N/A")
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

    if command -v md5sum &> /dev/null; then
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

    if command -v cmp &> /dev/null; then
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

    while getopts "b:a:f:c:i:o:t:nvdh" opt; do
        case $opt in
            b) I2C_BUS=$OPTARG ;;
            a) DEVICE_ADDR=$OPTARG ;;
            f) CONFIG_FILE=$OPTARG ;;
            c) COMPARE_FILE=$OPTARG ;;
            i) MONITOR_INTERVAL=$OPTARG ;;
            o) OUTPUT_FILE=$OPTARG ;;
            t) TIMEOUT=$OPTARG ;;
            n) DRY_RUN=1 ;;
            v) VERBOSE=1 ;;
            d) DEBUG=1 ;;
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
            if ! verify_programming; then
                exit 1
            fi
            log_info "Verification completed"
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
            if [ -z "$CONFIG_FILE" ] || [ -z "$I2C_BUS" ] || [ -z "$DEVICE_ADDR" ]; then
                log_error "Readback mode requires -f <config.txt> -b <bus> -a <address>"
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
