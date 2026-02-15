#!/bin/bash
# Setup BMC I2C Slave Device for Recovery Interface

# Load configuration
if [ -f /etc/bmc-recovery.conf ]; then
    . /etc/bmc-recovery.conf
else
    echo "ERROR: Configuration file /etc/bmc-recovery.conf not found"
    exit 1
fi

# Use defaults if not set
I2C_BUS=${I2C_BUS:-3}
SLAVE_ADDR=${SLAVE_ADDR:-0x42}

# Convert address to device tree format (0x42 -> 1042)
ADDR_FULL=$(printf "10%02x" $SLAVE_ADDR)

# Check if device already exists
if [ -e "/sys/bus/i2c/devices/${I2C_BUS}-${ADDR_FULL}" ]; then
    echo "I2C slave device already exists on bus ${I2C_BUS}"
    exit 0
fi

# Create I2C slave device
echo "Creating I2C slave device on bus ${I2C_BUS}, address 0x${ADDR_FULL}"
echo "slave-24c02 0x${ADDR_FULL}" > "/sys/bus/i2c/devices/i2c-${I2C_BUS}/new_device" || {
    echo "ERROR: Failed to create I2C slave device"
    exit 1
}

# Verify device was created
if [ -e "/sys/bus/i2c/devices/${I2C_BUS}-${ADDR_FULL}/slave-eeprom" ]; then
    echo "I2C slave device created successfully: /sys/bus/i2c/devices/${I2C_BUS}-${ADDR_FULL}/slave-eeprom"
    exit 0
else
    echo "ERROR: I2C slave device not created on bus ${I2C_BUS}"
    exit 1
fi
