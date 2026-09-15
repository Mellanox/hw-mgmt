#!/bin/bash

# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
################################################################################
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# Setup BMC I2C Slave Device for Recovery Interface

# Load configuration
RECOVERY_CONF="${HW_MANAGEMENT_BMC_RECOVERY_CONF:-/etc/hw-management-bmc-recovery.conf}"
if [ -f "$RECOVERY_CONF" ]; then
    # shellcheck source=/dev/null
    source "$RECOVERY_CONF"
else
    echo "ERROR: Configuration file $RECOVERY_CONF not found"
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
