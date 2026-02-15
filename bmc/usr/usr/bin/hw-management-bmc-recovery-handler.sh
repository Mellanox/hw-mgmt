#!/bin/bash
#
# BMC I2C Recovery Command Handler (Shell Version)
# Monitors I2C slave EEPROM for commands from CPU and executes recovery actions.
#

# Configuration file path
CONFIG_FILE="/etc/bmc-recovery.conf"

# Default configuration (used if config file not found)
DEFAULT_I2C_BUS=3
DEFAULT_SLAVE_ADDR=0x42

# Temporary log function for early initialization
early_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"
}

# Load configuration from file
if [ -f "$CONFIG_FILE" ]; then
    # Source the configuration file
    . "$CONFIG_FILE"
    early_log "Loaded configuration from $CONFIG_FILE"
else
    early_log "Configuration file not found: $CONFIG_FILE"
    early_log "Using default values: I2C_BUS=$DEFAULT_I2C_BUS, SLAVE_ADDR=$DEFAULT_SLAVE_ADDR"
fi

# Apply defaults if not set in config file
I2C_BUS=${I2C_BUS:-$DEFAULT_I2C_BUS}
SLAVE_ADDR=${SLAVE_ADDR:-$DEFAULT_SLAVE_ADDR}

# Convert address to device tree format (0x42 -> 1042)
ADDR_FULL=$(printf "10%02x" $SLAVE_ADDR)

# Derive device paths from configuration
SLAVE_EEPROM="/sys/bus/i2c/devices/${I2C_BUS}-${ADDR_FULL}/slave-eeprom"
POLL_INTERVAL=${POLL_INTERVAL:-1}     # Poll every 1 second (configurable)

# Command codes
CMD_NONE=0x00
CMD_FACTORY_RESET=0x01
CMD_NETWORK_RESET=0x02
CMD_REBOOT_BMC=0x03
CMD_CLEAR_LOGS=0x04
CMD_RESET_USB_NET=0x05
CMD_ENABLE_SSH=0x06
CMD_RESET_PASSWORD=0x07
CMD_DIAGNOSTIC=0x08
CMD_PING=0xED  # Changed from 0xFF to avoid conflict with erased EEPROM state

# Status codes
STATUS_IDLE=0x00
STATUS_PROCESSING=0x01
STATUS_SUCCESS=0x02
STATUS_ERROR=0x03
STATUS_INVALID_CMD=0x04
STATUS_INVALID_MAGIC=0x05
STATUS_INVALID_CHECKSUM=0x06
STATUS_INVALID_CONFIRM=0x07

# Protocol constants
MAGIC_BYTE=0x5A  # Magic byte for command validation

# Confirmation codes for dangerous commands (parameter byte must match)
CONFIRM_FACTORY_RESET=0xAA
CONFIRM_REBOOT_BMC=0x55
CONFIRM_RESET_PASSWORD=0xCC

# Last command tracking
LAST_CMD=0x00

#
# Logging function (logs to stdout/journal)
#
log_msg() {
    local level=$1
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
}

#
# Read command from I2C slave buffer
#
read_command() {
    if [ ! -f "$SLAVE_EEPROM" ]; then
        return 1
    fi

    # Read first 6 bytes and convert to hex (busybox compatible)
    local data=$(dd if="$SLAVE_EEPROM" bs=1 count=6 2>/dev/null | hexdump -v -e '/1 "%02x"')

    if [ -z "$data" ]; then
        echo "0x00 0x00 0x00 0x00"
        return 0
    fi

    # Extract all fields: cmd, param, magic, checksum
    local cmd="0x${data:0:2}"
    local param="0x${data:2:2}"
    local magic="0x${data:4:2}"
    local checksum="0x${data:6:2}"

    echo "$cmd $param $magic $checksum"
}

#
# Write status to I2C buffer
#
write_status() {
    local status=$1
    local result=${2:-0}

    if [ ! -f "$SLAVE_EEPROM" ]; then
        return 1
    fi

    # Write to offset 4 (status) and 5 (result)
    # Suppress errors if write fails (CPU might be reading)
    printf "\x$(printf '%02x' $status)\x$(printf '%02x' $result)" 2>/dev/null | \
        dd of="$SLAVE_EEPROM" bs=1 seek=4 count=2 conv=notrunc 2>/dev/null || true
}

#
# Clear command buffer
#
clear_command() {
    if [ ! -f "$SLAVE_EEPROM" ]; then
        return 1
    fi

    # Try to write zeros to first 2 bytes (command and parameter)
    # Note: This may fail due to driver limitations (slave can't write to own EEPROM)
    # That's OK - we rely on LAST_CMD to prevent re-execution
    dd if=/dev/zero of="$SLAVE_EEPROM" bs=1 count=2 conv=notrunc 2>/dev/null || true

    # DO NOT reset LAST_CMD here!
    # We want to keep tracking the last command even if buffer clear fails
    # This prevents re-executing the same command on every poll
}

#
# Recovery action implementations
#

factory_reset() {
    log_msg "WARN" "Executing FACTORY RESET"

    # Set U-Boot environment variable to trigger factory reset on next boot
    if ! fw_setenv openbmconce factory-reset; then
        log_msg "ERROR" "Failed to set factory-reset environment variable"
        return 1
    fi

    log_msg "INFO" "Factory reset scheduled, rebooting..."
    sync
    reboot
    return 0
}

network_reset() {
    local interface=$1
    log_msg "INFO" "Executing NETWORK RESET (interface: $interface)"

    case $interface in
        0)  # All interfaces
            systemctl restart networking 2>/dev/null || \
            systemctl restart network 2>/dev/null
            ;;
        1)  # eth0
            ip link set eth0 down 2>/dev/null
            sleep 1
            ip link set eth0 up 2>/dev/null
            dhclient eth0 2>/dev/null &
            ;;
        2)  # usb0
            ip link set usb0 down 2>/dev/null
            sleep 1
            ip link set usb0 up 2>/dev/null
            ;;
    esac

    log_msg "INFO" "Network reset completed"
    return 0
}

reboot_bmc() {
    log_msg "WARN" "Rebooting BMC in 2 seconds..."
    sleep 2
    reboot
}

clear_logs() {
    local log_type=$1
    log_msg "INFO" "Clearing logs (type: $log_type)"

    case $log_type in
        0)  # All logs
            journalctl --vacuum-time=1s 2>/dev/null
            > /var/log/messages 2>/dev/null
            ;;
        1)  # Journal only
            journalctl --vacuum-time=1s 2>/dev/null
            ;;
        2)  # Syslog only
            > /var/log/messages 2>/dev/null
            ;;
    esac

    log_msg "INFO" "Logs cleared"
    return 0
}

reset_usb_net() {
    log_msg "INFO" "Resetting USB network"

    ip link set usb0 down 2>/dev/null
    sleep 1
    ip link set usb0 up 2>/dev/null
    systemctl restart usb-network 2>/dev/null

    log_msg "INFO" "USB network reset completed"
    return 0
}

enable_ssh() {
    local port=${1:-22}
    log_msg "INFO" "Enabling SSH on port $port"

    systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null
    systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null

    log_msg "INFO" "SSH enabled"
    return 0
}

reset_password() {
    local user_id=$1
    local user="root"

    case $user_id in
        0) user="root" ;;
        1) user="admin" ;;
    esac

    log_msg "WARN" "Resetting password for user: $user"

    # Set default password (customize as needed)
    echo "$user:0penBmc" | chpasswd 2>/dev/null

    log_msg "INFO" "Password reset for $user"
    return 0
}

run_diagnostic() {
    local test_num=$1
    log_msg "INFO" "Running diagnostic test: $test_num"

    case $test_num in
        0)  # Network test
            ip link show > /dev/null 2>&1
            ;;
        1)  # I2C test
            i2cdetect -y 0 > /dev/null 2>&1
            ;;
        2)  # Storage test
            df -h > /dev/null 2>&1
            ;;
    esac

    return 0
}

#
# Validate checksum (XOR of cmd, param, magic)
#
validate_checksum() {
    local cmd=$1
    local param=$2
    local magic=$3
    local checksum=$4

    # Calculate expected checksum (XOR)
    local expected=$((cmd ^ param ^ magic))

    if [ $checksum -eq $expected ]; then
        return 0  # Valid
    else
        return 1  # Invalid
    fi
}

#
# Execute command with safety validation
#
execute_command() {
    local cmd=$1
    local param=$2
    local magic=$3
    local checksum=$4

    # Check for command clear (0x00) - reset tracking
    if [ "$cmd" = "0x00" ]; then
        if [ $LAST_CMD -ne 0 ] 2>/dev/null; then
            # Command was cleared by CPU, ready for next command
            log_msg "DEBUG" "Command buffer cleared by CPU, ready for next command"
            LAST_CMD=0
        fi
        return  # CMD_NONE - silently ignore
    fi

    # Skip erased EEPROM state (0xFF)
    if [ "$cmd" = "0xff" ] || [ "$cmd" = "0xFF" ]; then
        return  # Erased EEPROM state - silently ignore
    fi

    # Convert hex to decimal
    cmd=$((cmd))
    param=$((param))
    magic=$((magic))
    checksum=$((checksum))

    # SAFETY CHECK 1: Validate magic byte
    if [ $magic -ne $((MAGIC_BYTE)) ]; then
        log_msg "WARN" "Invalid magic byte: $(printf '0x%02X' $magic), expected $(printf '0x%02X' $((MAGIC_BYTE))) - rejecting command"
        write_status $STATUS_INVALID_MAGIC 0xFF
        return
    fi

    # SAFETY CHECK 2: Validate checksum
    if ! validate_checksum $cmd $param $magic $checksum; then
        local expected=$((cmd ^ param ^ magic))
        log_msg "WARN" "Invalid checksum: $(printf '0x%02X' $checksum), expected $(printf '0x%02X' $expected) - rejecting command"
        write_status $STATUS_INVALID_CHECKSUM 0xFF
        return
    fi

    # Avoid re-executing same command
    if [ $cmd -eq $LAST_CMD ] 2>/dev/null && [ $cmd -ne 0 ] 2>/dev/null; then
        return  # Same command as last time, already processed
    fi

    LAST_CMD=$cmd

    log_msg "INFO" "Received valid command: $(printf '0x%02X' $cmd), parameter: $(printf '0x%02X' $param)"

    # SAFETY CHECK 3: Validate confirmation codes for dangerous commands
    case $cmd in
        1)  # CMD_FACTORY_RESET
            if [ $param -ne $((CONFIRM_FACTORY_RESET)) ]; then
                log_msg "ERROR" "Factory reset requires confirmation parameter $(printf '0x%02X' $((CONFIRM_FACTORY_RESET))), got $(printf '0x%02X' $param)"
                write_status $STATUS_INVALID_CONFIRM 0x01
                return
            fi
            ;;
        3)  # CMD_REBOOT_BMC
            if [ $param -ne $((CONFIRM_REBOOT_BMC)) ]; then
                log_msg "ERROR" "BMC reboot requires confirmation parameter $(printf '0x%02X' $((CONFIRM_REBOOT_BMC))), got $(printf '0x%02X' $param)"
                write_status $STATUS_INVALID_CONFIRM 0x03
                return
            fi
            ;;
        7)  # CMD_RESET_PASSWORD
            if [ $param -ne $((CONFIRM_RESET_PASSWORD)) ]; then
                log_msg "ERROR" "Password reset requires confirmation parameter $(printf '0x%02X' $((CONFIRM_RESET_PASSWORD))), got $(printf '0x%02X' $param)"
                write_status $STATUS_INVALID_CONFIRM 0x07
                return
            fi
            ;;
    esac

    case $cmd in
        237)  # CMD_PING (0xED)
            log_msg "INFO" "PING command - responding with SUCCESS"
            write_status $STATUS_SUCCESS 0xAA
            sleep 0.5
            clear_command
            ;;

        1)  # CMD_FACTORY_RESET
            write_status $STATUS_PROCESSING
            if factory_reset; then
                write_status $STATUS_SUCCESS
            else
                write_status $STATUS_ERROR
            fi
            clear_command
            ;;

        2)  # CMD_NETWORK_RESET
            write_status $STATUS_PROCESSING
            if network_reset $param; then
                write_status $STATUS_SUCCESS
            else
                write_status $STATUS_ERROR
            fi
            clear_command
            ;;

        3)  # CMD_REBOOT_BMC
            write_status $STATUS_PROCESSING
            sleep 0.5
            clear_command
            reboot_bmc
            ;;

        4)  # CMD_CLEAR_LOGS
            write_status $STATUS_PROCESSING
            if clear_logs $param; then
                write_status $STATUS_SUCCESS
            else
                write_status $STATUS_ERROR
            fi
            clear_command
            ;;

        5)  # CMD_RESET_USB_NET
            write_status $STATUS_PROCESSING
            if reset_usb_net; then
                write_status $STATUS_SUCCESS
            else
                write_status $STATUS_ERROR
            fi
            clear_command
            ;;

        6)  # CMD_ENABLE_SSH
            write_status $STATUS_PROCESSING
            if enable_ssh $param; then
                write_status $STATUS_SUCCESS
            else
                write_status $STATUS_ERROR
            fi
            clear_command
            ;;

        7)  # CMD_RESET_PASSWORD
            write_status $STATUS_PROCESSING
            if reset_password $param; then
                write_status $STATUS_SUCCESS
            else
                write_status $STATUS_ERROR
            fi
            clear_command
            ;;

        8)  # CMD_DIAGNOSTIC
            write_status $STATUS_PROCESSING
            if run_diagnostic $param; then
                write_status $STATUS_SUCCESS
            else
                write_status $STATUS_ERROR
            fi
            clear_command
            ;;

        *)
            log_msg "ERROR" "Unknown command: $(printf '0x%02X' $cmd)"
            write_status $STATUS_INVALID_CMD
            clear_command
            ;;
    esac
}

#
# Main loop
#
main() {
    log_msg "INFO" "============================================================"
    log_msg "INFO" "BMC I2C Recovery Handler Starting (Shell Version)"
    log_msg "INFO" "I2C Bus: $I2C_BUS"
    log_msg "INFO" "Slave Address: $(printf '0x%02X' $SLAVE_ADDR)"
    log_msg "INFO" "EEPROM Device: $SLAVE_EEPROM"
    log_msg "INFO" "============================================================"

    # Check if slave device exists
    if [ ! -f "$SLAVE_EEPROM" ]; then
        log_msg "ERROR" "Slave EEPROM device not found: $SLAVE_EEPROM"
        log_msg "ERROR" "Possible causes:"
        log_msg "ERROR" "1. Device tree not configured correctly"
        log_msg "ERROR" "2. i2c-slave-eeprom module not loaded"
        log_msg "ERROR" "3. Wrong I2C bus or address"
        exit 1
    fi

    # Clear the EEPROM buffer on startup to avoid processing stale/garbage data
    log_msg "INFO" "Clearing I2C EEPROM buffer..."
    dd if=/dev/zero of="$SLAVE_EEPROM" bs=1 count=6 conv=notrunc 2>/dev/null || {
        log_msg "WARN" "Could not clear EEPROM buffer, continuing anyway..."
    }

    log_msg "INFO" "Handler initialized, waiting for commands..."

    # Main loop
    while true; do
        # Read command (4 values: cmd, param, magic, checksum)
        read cmd param magic checksum <<< $(read_command)

        # Always call execute_command (it handles 0x00 internally for LAST_CMD reset)
        execute_command $cmd $param $magic $checksum

        sleep $POLL_INTERVAL
    done
}

# Handle signals
trap 'log_msg "INFO" "Received interrupt, shutting down..."; exit 0' INT TERM

# Run main loop
main


