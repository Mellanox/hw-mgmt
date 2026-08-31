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
# ADS7924: force ULR/LLR window so selected channels assert alarm (debug).
# Register sequence aligned with hw-management-bmc-a2d-leakage-config.sh.
################################################################################

# Usage:
#   hw-management-bmc-ads7924-force-alarm.sh <bus> <addr> <channels>
#
# Examples:
#   hw-management-bmc-ads7924-force-alarm.sh 12 0x48 all
#   hw-management-bmc-ads7924-force-alarm.sh 12 0x48 0,2

BUS="$1"
ADDR="$2"
CHS="$3"

# Narrow ULR/LLR window → alarm; wide window → safe.
ALARM_UL=0x10
ALARM_LL=0x0f
SAFE_UL=0xff
SAFE_LL=0x00

# Defaults from hw-management-bmc-a2d-leakage-config.sh (raw I2C path).
INT_B=0xe0
SLP_B=0x00
ACQ_B=0x00
PWR_B=0x00
AWAKE_B=0x80
MODE_B=0xcc

usage() {
    echo "Usage: $0 <bus> <i2c_addr> <channels>"
    echo "Channels: 0,1,2,3 | 0 | 1,3 | all"
    exit 1
}

if [ -z "$BUS" ] || [ -z "$ADDR" ] || [ -z "$CHS" ]; then
    usage
fi

build_ch() {
    case "$1" in
    alarm) echo "$ALARM_UL $ALARM_LL" ;;
    safe) echo "$SAFE_UL $SAFE_LL" ;;
    esac
}

CH0="safe"
CH1="safe"
CH2="safe"
CH3="safe"

if [ "$CHS" = "all" ]; then
    CH0=alarm
    CH1=alarm
    CH2=alarm
    CH3=alarm
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

set -- $(build_ch "$CH0")
ul0=$1
ll0=$2
set -- $(build_ch "$CH1")
ul1=$1
ll1=$2
set -- $(build_ch "$CH2")
ul2=$1
ll2=$2
set -- $(build_ch "$CH3")
ul3=$1
ll3=$2

aen=0
ch=0
while [ "$ch" -lt 4 ]; do
    eval mode=\$CH${ch}
    if [ "$mode" = "alarm" ]; then
        aen=$((aen | (1 << ch)))
    fi
    ch=$((ch + 1))
done

# Software reset, IDLE, thresholds, INT block, alarm enable, AWAKE + auto-scan.
if ! i2ctransfer -f -y "$BUS" w2@"$ADDR" 0x16 0xaa >/dev/null 2>&1; then
    echo "ADS7924 soft reset failed (continuing)"
fi
sleep 0.05

if ! i2ctransfer -f -y "$BUS" w2@"$ADDR" 0x00 0x00 >/dev/null 2>&1; then
    echo "ADS7924 IDLE mode write failed"
    exit 1
fi

if ! i2ctransfer -f -y "$BUS" w9@"$ADDR" 0x8a \
    "$ul0" "$ll0" "$ul1" "$ll1" "$ul2" "$ll2" "$ul3" "$ll3" >/dev/null 2>&1; then
    echo "ADS7924 ULR/LLR burst write failed"
    exit 1
fi

if ! i2ctransfer -f -y "$BUS" w5@"$ADDR" 0x92 "$INT_B" "$SLP_B" "$ACQ_B" "$PWR_B" >/dev/null 2>&1; then
    echo "ADS7924 INT/SLP/ACQ/PWR write failed"
    exit 1
fi

if ! i2ctransfer -f -y "$BUS" w2@"$ADDR" 0x01 "$aen" >/dev/null 2>&1; then
    echo "ADS7924 INTCNTRL (alarm enable) write failed"
    exit 1
fi

# Clear any stale alarm interrupt before starting the scan (read INTCONFIG 0x12).
i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x12 r1 >/dev/null 2>&1 || true

if ! i2ctransfer -f -y "$BUS" w2@"$ADDR" 0x00 "$AWAKE_B" >/dev/null 2>&1; then
    echo "ADS7924 AWAKE mode write failed"
    exit 1
fi
sleep 0.002
if ! i2ctransfer -f -y "$BUS" w2@"$ADDR" 0x00 "$MODE_B" >/dev/null 2>&1; then
    echo "ADS7924 MODE write failed"
    exit 1
fi

echo "Forced alarm configured"
echo "Bus=$BUS Addr=$ADDR Channels=$CHS AlarmEnable=0x$(printf '%02x' "$aen")"
