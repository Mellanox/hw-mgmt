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
# MAX1363: force threshold window so selected channels assert alarm (debug).
# Origin: OpenBMC meta-nvidia bmc-post-boot-cfg max1363_force_alarm.sh
################################################################################

# Usage:
#   hw-management-bmc-max1363-force-alarm.sh <bus> <addr> <channels>
#
# Examples:
#   hw-management-bmc-max1363-force-alarm.sh 12 0x34 all
#   hw-management-bmc-max1363-force-alarm.sh 12 0x34 1,2

BUS="$1"
ADDR="$2"
CHS="$3"

if [ -z "$BUS" ] || [ -z "$ADDR" ] || [ -z "$CHS" ]; then
    echo "Usage: $0 <bus> <i2c_addr> <channels>"
    echo "Channels: 0,1,2,3 | 0 | 1,3 | all"
    exit 1
fi

# Default thresholds (tight window → alarm)
LT_MSB=0x00
LT_UT=0x10
UT_LSB=0x20

# Safe thresholds (won't alarm)
SAFE_LTM=0x00
SAFE_LTUT=0x00
SAFE_UTL=0xFF

CTRL=0xF6   # Reset alarms, 2ksps, INT enable

# Build threshold block per channel
build_ch()
{
    case "$1" in
        alarm)
            echo "$LT_MSB $LT_UT $UT_LSB"
            ;;
        safe)
            echo "$SAFE_LTM $SAFE_LTUT $SAFE_UTL"
            ;;
    esac
}

CH0="safe"
CH1="safe"
CH2="safe"
CH3="safe"

if [ "$CHS" = "all" ]; then
    CH0=alarm; CH1=alarm; CH2=alarm; CH3=alarm
else
    for c in $(echo "$CHS" | tr ',' ' '); do
        case "$c" in
            0) CH0=alarm ;;
            1) CH1=alarm ;;
            2) CH2=alarm ;;
            3) CH3=alarm ;;
            *)
                echo "Invalid channel: $c"
                exit 1
                ;;
        esac
    done
fi

i2ctransfer -f -y "$BUS" w14@"$ADDR" \
  0x01 \
  "$CTRL" \
  $(build_ch "$CH0") \
  $(build_ch "$CH1") \
  $(build_ch "$CH2") \
  $(build_ch "$CH3")

echo "Forced alarm configured"
echo "Bus=$BUS Addr=$ADDR Channels=$CHS"
