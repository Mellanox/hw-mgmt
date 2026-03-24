#!/bin/sh

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
################################################################################
# MAX1363: read status / ADC bytes via i2ctransfer (debug).
# Origin: OpenBMC meta-nvidia bmc-post-boot-cfg max1363_read_status.sh
################################################################################

# Usage:
#   hw-management-bmc-max1363-read-status.sh <bus> <addr>
# Example:
#   hw-management-bmc-max1363-read-status.sh 12 0x34

BUS="$1"
ADDR="$2"

if [ -z "$BUS" ] || [ -z "$ADDR" ]; then
    echo "Usage: $0 <bus> <i2c_addr>"
    exit 1
fi

DATA=$(i2ctransfer -f -y "$BUS" r2@"$ADDR")

B0=$(echo "$DATA" | awk '{print $1}')
B1=$(echo "$DATA" | awk '{print $2}')

STATUS=$((B0))
VALUE=$(( (B0 & 0x0F) << 8 | B1 ))

echo "I2C bus     : $BUS"
echo "I2C address : $ADDR"
echo "Raw bytes   : $B0 $B1"
echo "ADC value   : $VALUE"
echo "Status:"

[ $((STATUS & 0x80)) -ne 0 ] && echo "  Alarm active"
[ $((STATUS & 0x40)) -ne 0 ] && echo "  Channel 3 alarm"
[ $((STATUS & 0x20)) -ne 0 ] && echo "  Channel 2 alarm"
[ $((STATUS & 0x10)) -ne 0 ] && echo "  Channel 1 alarm"
[ $((STATUS & 0x08)) -ne 0 ] && echo "  Channel 0 alarm"
