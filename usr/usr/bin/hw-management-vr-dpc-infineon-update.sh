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
DEBUG=0
MODE=""

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
MFR_SPECIFIC_00=0xD0
STATUS_WORD=0x79
STATUS_BYTE=0x78
READ_VOUT=0x8B
READ_IOUT=0x8C
READ_TEMPERATURE_1=0x8D
READ_POUT=0x96

# Scratchpad programming commands
CMD_SCRATCHPAD_WRITE=0x01
CMD_SCRATCHPAD_UPLOAD=0x02
CMD_INVALIDATE_OTP=0x03
CMD_READ_OTP=0x04
CMD_CHECK_OTP_SPACE=0x05

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
    parse       Parse configuration file
    compare     Compare two configuration files

FLASH MODE OPTIONS:
    Required:
        -b <bus>        I2C bus number (e.g., 0, 1, 2)
        -a <addr>       Device I2C address in hex (e.g., 0x40)
        -f <file>       Configuration file path

    Optional:
        -n              Dry run (show commands without executing)
        -t <seconds>    Timeout for operations (default: 30)
        -d              Debug mode (verbose output)

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

PARSE MODE OPTIONS:
    -f <file>           Configuration file path

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

    # Parse config file
    $(basename $0) parse -f config.bin

    # Compare configs
    $(basename $0) compare -f old.bin -c new.bin

EOF
    exit 1
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [ $DEBUG -eq 1 ]; then
        echo -e "[DEBUG] $1"
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
        log_debug "DRY-RUN: i2cset -y $bus $addr $reg ${data[*]}"
        return 0
    fi

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

    if [ $DRY_RUN -eq 1 ]; then
        log_debug "DRY-RUN: i2cget -y $bus $addr $reg"
        echo "0xff"
        return 0
    fi

    log_debug "i2cget -y $bus $addr $reg"
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

    echo "$result"
    return 0
}

# Block write for larger data transfers
i2c_block_write() {
    local bus=$1
    local addr=$2
    local reg=$3
    shift 3
    local data=("$@")

    if [ $DRY_RUN -eq 1 ]; then
        log_debug "DRY-RUN: i2ctransfer -y $bus w$((${#data[@]}+1))@$addr $reg ${data[*]}"
        return 0
    fi

    log_debug "i2ctransfer -y $bus w$((${#data[@]}+1))@$addr $reg ${data[*]}"
    if ! i2ctransfer -y $bus "w$((${#data[@]}+1))@$addr" $reg "${data[@]}" 2>/dev/null; then
        log_error "Failed block write to device"
        return 1
    fi
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
        log_info "DRY-RUN: Device detection skipped"
        return 0
    fi

    if ! i2cdetect -y $I2C_BUS $DEVICE_ADDR $DEVICE_ADDR 2>/dev/null | grep -qi "$(printf '%02x' $((DEVICE_ADDR)))"; then
        log_error "Device not detected at address $DEVICE_ADDR on bus $I2C_BUS"
        return 1
    fi

    log_info "Device detected"
    return 0
}

# Read device identification
read_device_id() {
    log_info "Reading device identification..."

    local mfr_id
    mfr_id=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_ID) || return 1
    log_info "Manufacturer ID: $mfr_id"

    local mfr_model
    mfr_model=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_MODEL) || return 1
    log_info "Model: $mfr_model"

    local mfr_rev
    mfr_rev=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_REVISION) || return 1
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

    if [ "$result" != "0x00" ]; then
        log_warn "OTP space may be limited or full"
    else
        log_info "OTP space available"
    fi

    return 0
}

# Invalidate existing OTP data
invalidate_otp() {
    local invalidate_all=${1:-1}

    if [ $invalidate_all -eq 1 ]; then
        log_info "Invalidating entire OTP configuration..."
    else
        log_info "Invalidating specific OTP section..."
    fi

    i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_INVALIDATE_OTP $invalidate_all || return 1
    sleep 1

    local result
    result=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND) || return 1

    if [ "$result" != "0x00" ]; then
        log_error "OTP invalidation failed with code: $result"
        return 1
    fi

    log_info "OTP invalidation completed"
    return 0
}

# Write data to scratchpad memory
write_to_scratchpad() {
    local data_file=$1

    log_info "Writing configuration to scratchpad..."

    if [ ! -f "$data_file" ]; then
        log_error "Configuration file not found: $data_file"
        return 1
    fi

    local file_size
    file_size=$(stat -f %z "$data_file" 2>/dev/null || stat -c %s "$data_file" 2>/dev/null)
    log_info "Configuration file size: $file_size bytes"

    # Skip file processing in dry-run mode
    if [ $DRY_RUN -eq 1 ]; then
        log_info "DRY-RUN: Skipping scratchpad write (would write $file_size bytes)"
        return 0
    fi

    local block_size=32
    local blocks=$((file_size / block_size))
    local remainder=$((file_size % block_size))

    log_info "Writing $blocks blocks + $remainder bytes..."

    local offset=0
    for ((i=0; i<blocks; i++)); do
        local data_bytes
        data_bytes=$(od -An -tx1 -N$block_size -j$offset "$data_file" | tr -s ' ' | sed 's/^ //')

        local data_array=($data_bytes)

        log_debug "Writing block $i at offset $offset"
        i2c_block_write $I2C_BUS $DEVICE_ADDR $MFR_SPECIFIC_00 "${data_array[@]}" || return 1

        offset=$((offset + block_size))
        sleep 0.01

        if [ $((i % 10)) -eq 0 ]; then
            echo -n "."
        fi
    done

    if [ $remainder -gt 0 ]; then
        local data_bytes
        data_bytes=$(od -An -tx1 -N$remainder -j$offset "$data_file" | tr -s ' ' | sed 's/^ //')
        local data_array=($data_bytes)

        log_debug "Writing final $remainder bytes"
        i2c_block_write $I2C_BUS $DEVICE_ADDR $MFR_SPECIFIC_00 "${data_array[@]}" || return 1
    fi

    echo ""
    log_info "Scratchpad write completed"
    return 0
}

# Upload data from scratchpad to OTP
upload_scratchpad_to_otp() {
    log_info "Uploading configuration from scratchpad to OTP..."

    i2c_write $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND $CMD_SCRATCHPAD_UPLOAD || return 1

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
    sleep 0.5

    local result
    result=$(i2c_read $I2C_BUS $DEVICE_ADDR $MFR_FW_COMMAND) || return 1

    if [ "$result" = "0x00" ]; then
        log_info "Verification passed"
        return 0
    else
        log_error "Verification failed with code: $result"
        return 1
    fi
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

    log_warn "This will erase existing configuration!"
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

        # Only invalidate OTP in non-dry-run mode
        invalidate_otp 1 || return 1
    else
        log_info "DRY-RUN: Skipping OTP invalidation"
    fi
    echo ""

    write_to_scratchpad "$CONFIG_FILE" || return 1
    echo ""

    if [ $DRY_RUN -eq 0 ]; then
        upload_scratchpad_to_otp || return 1
    else
        log_info "DRY-RUN: Skipping scratchpad upload to OTP"
    fi
    echo ""

    if [ $DRY_RUN -eq 0 ]; then
        verify_programming || return 1
    else
        log_info "DRY-RUN: Skipping verification"
    fi
    echo ""

    if [ $DRY_RUN -eq 0 ]; then
        enable_write_protect || return 1
    else
        log_info "DRY-RUN: Skipping write protection enable"
    fi
    echo ""

    if [ $DRY_RUN -eq 0 ]; then
        reset_device || return 1
    else
        log_info "DRY-RUN: Skipping device reset"
    fi
    echo ""

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
    file_size=$(stat -f %z "$config_file" 2>/dev/null || stat -c %s "$config_file" 2>/dev/null)

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

    log_info "Checking common Infineon addresses (0x40-0x4F)..."

    for addr in $(seq 64 79); do
        local hex_addr
        hex_addr=$(printf "0x%02x" $addr)

        if i2cdetect -y $bus $addr $addr 2>/dev/null | grep -qi "$(printf '%02x' $addr)"; then
            echo -e "${GREEN}Found device at $hex_addr${NC}"

            if command -v i2cget &> /dev/null; then
                local mfr_id
                mfr_id=$(i2cget -y $bus $hex_addr 0x99 2>/dev/null || echo "N/A")
                echo "  MFR_ID: $mfr_id"
            fi
        fi
    done

    return 0
}

# Read and display device information
read_device_info() {
    local bus=$1
    local addr=$2

    log_info "Reading device information..."
    echo ""

    if [ -z "$bus" ] || [ -z "$addr" ]; then
        log_error "Usage: info mode requires -b <bus> -a <address>"
        return 1
    fi

    if [[ ! $addr == 0x* ]]; then
        addr="0x$addr"
    fi

    echo "Device: Bus $bus, Address $addr"
    echo ""

    local registers=(
        "0x99:MFR_ID"
        "0x9A:MFR_MODEL"
        "0x9B:MFR_REVISION"
        "0x9C:MFR_LOCATION"
        "0x9D:MFR_DATE"
        "0x9E:MFR_SERIAL"
        "0xAD:MFR_DEVICE_ID"
        "0x79:STATUS_WORD"
        "0x78:STATUS_BYTE"
        "0x01:OPERATION"
        "0x10:WRITE_PROTECT"
    )

    echo "Register Values:"
    for reg_info in "${registers[@]}"; do
        local reg="${reg_info%%:*}"
        local name="${reg_info##*:}"

        local value
        value=$(i2cget -y $bus $addr $reg 2>/dev/null || echo "N/A")

        printf "  %-20s (%-6s): %s\n" "$name" "$reg" "$value"
    done

    return 0
}

# Monitor device telemetry
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

    log_info "Monitoring device telemetry (Ctrl+C to stop)"
    log_info "Bus: $bus, Address: $addr, Interval: ${interval}s"
    echo ""

    while true; do
        clear
        echo "=== Infineon XDPE Device Monitor ==="
        echo "Time: $(date)"
        echo "Bus: $bus, Address: $addr"
        echo ""

        local vout
        vout=$(i2cget -y $bus $addr $READ_VOUT w 2>/dev/null || echo "N/A")
        echo "Output Voltage:    $vout"

        local iout
        iout=$(i2cget -y $bus $addr $READ_IOUT w 2>/dev/null || echo "N/A")
        echo "Output Current:    $iout"

        local temp
        temp=$(i2cget -y $bus $addr $READ_TEMPERATURE_1 w 2>/dev/null || echo "N/A")
        echo "Temperature:       $temp"

        local pout
        pout=$(i2cget -y $bus $addr $READ_POUT w 2>/dev/null || echo "N/A")
        echo "Output Power:      $pout"

        local status
        status=$(i2cget -y $bus $addr $STATUS_BYTE 2>/dev/null || echo "N/A")
        echo "Status Byte:       $status"

        sleep $interval
    done
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

    log_info "Dumping registers from device at bus $bus, address $addr"

    local output=""
    output+="Infineon XDPE Register Dump\n"
    output+="Date: $(date)\n"
    output+="Bus: $bus, Address: $addr\n"
    output+="\n"
    output+="Reg    Value  ASCII\n"
    output+="--------------------\n"

    for reg in $(seq 0 255); do
        local hex_reg
        hex_reg=$(printf "0x%02x" $reg)

        local value
        value=$(i2cget -y $bus $addr $hex_reg 2>/dev/null)

        if [ $? -eq 0 ] && [ "$value" != "" ]; then
            local dec_value=$((value))
            local ascii=""
            if [ $dec_value -ge 32 ] && [ $dec_value -le 126 ]; then
                ascii=$(printf "\\x$(printf '%02x' $dec_value)")
            fi

            output+="$(printf '%s    %s     %s\n' "$hex_reg" "$value" "$ascii")"
        fi
    done

    if [ -n "$output_file" ]; then
        echo -e "$output" > "$output_file"
        log_info "Register dump saved to: $output_file"
    else
        echo -e "$output"
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
    size1=$(stat -f %z "$file1" 2>/dev/null || stat -c %s "$file1" 2>/dev/null)
    size2=$(stat -f %z "$file2" 2>/dev/null || stat -c %s "$file2" 2>/dev/null)

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
        usage
    fi

    MODE=$1
    shift

    # Parse command line arguments based on mode
    local OPTIND
    local COMPARE_FILE=""
    local MONITOR_INTERVAL=1
    local OUTPUT_FILE=""

    while getopts "b:a:f:c:i:o:t:ndh" opt; do
        case $opt in
            b) I2C_BUS=$OPTARG ;;
            a) DEVICE_ADDR=$OPTARG ;;
            f) CONFIG_FILE=$OPTARG ;;
            c) COMPARE_FILE=$OPTARG ;;
            i) MONITOR_INTERVAL=$OPTARG ;;
            o) OUTPUT_FILE=$OPTARG ;;
            t) TIMEOUT=$OPTARG ;;
            n) DRY_RUN=1 ;;
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

        parse)
            if [ -z "$CONFIG_FILE" ]; then
                log_error "Parse mode requires -f <file>"
                usage
            fi
            if ! parse_config_file "$CONFIG_FILE"; then
                exit 1
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
