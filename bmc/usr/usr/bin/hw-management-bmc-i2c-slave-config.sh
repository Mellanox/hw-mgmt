#!/bin/bash
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

# configuration
# read-only EEPROM on i2c bus 3 with slave id 0x4f. 0x1000 is the address
# range of the i2c slave backend subsystem. Hence the final address is 0x104f
I2C_SLAVE_TYPE_RO=slave-24c512ro
I2C_BUS_RO=3
I2C_RO_SLAVE_ADDRESS=4f

# BMC Control functions like factory reset, reboot are under slave address 0x45 on bus 3
I2C_RW_SLAVE_TYPE=slave-24c02
I2C_BUS_RW=3
I2C_RW_SLAVE_ADDRESS=45

# sys bus
I2C_NEW_DEV_PATH=/sys/bus/i2c/devices/i2c-$I2C_BUS_RO/new_device
I2C_SLAVE_FILE=/sys/bus/i2c/devices/i2c-$I2C_BUS_RO/$I2C_BUS_RO-10$I2C_RO_SLAVE_ADDRESS/name
I2C_SLAVE_MEM_FILE=/sys/bus/i2c/devices/$I2C_BUS_RO-10$I2C_RO_SLAVE_ADDRESS/slave-eeprom
I2C_NEW_DEV_PATH_CONTROL=/sys/bus/i2c/devices/i2c-$I2C_BUS_RW/new_device
I2C_SLAVE_FILE_CONTROL=/sys/bus/i2c/devices/i2c-$I2C_BUS_RW/$I2C_BUS_RW-10$I2C_RW_SLAVE_ADDRESS/name
I2C_SLAVE_MEM_FILE_CONTROL=/sys/bus/i2c/devices/$I2C_BUS_RW-10$I2C_RW_SLAVE_ADDRESS/slave-eeprom

