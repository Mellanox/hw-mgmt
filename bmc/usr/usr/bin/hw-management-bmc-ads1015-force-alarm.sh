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
# ADS1015: force comparator window so selected MUX channels assert ALERT (debug).
# Threshold / MUX bytes match hw-management-bmc-a2d-leakage-config.sh example JSON.
################################################################################

# Usage:
#   hw-management-bmc-ads1015-force-alarm.sh <bus> <addr> <channels>
#
# Examples:
#   hw-management-bmc-ads1015-force-alarm.sh 12 0x49 all
#   hw-management-bmc-ads1015-force-alarm.sh 12 0x49 0,1

BUS="$1"
ADDR="$2"
CHS="$3"

# Config register low byte: window comparator + latched ALERT (see CfgRegVal 0xc4 0x94).
CFG_LO=0x94

# Tight window → alarm (example LoThreshRegVal / HiThreshRegVal).
ALARM_LO_MSB=0x38
ALARM_LO_LSB=0x40
ALARM_HI_MSB=0x7f
ALARM_HI_LSB=0xf0

# Wide window → no alarm (12-bit comparator value in bits 15:4; 0x7ff0 = max).
# Do not use 0xffff — interpreted as signed 12-bit that is −1 and asserts ALERT.
SAFE_LO_MSB=0x00
SAFE_LO_LSB=0x00
SAFE_HI_MSB=0x7f
SAFE_HI_LSB=0xf0

usage() {
    echo "Usage: $0 <bus> <i2c_addr> <channels>"
    echo "Channels: 0,1,2,3 | 0 | 1,3 | all"
    exit 1
}

if [ -z "$BUS" ] || [ -z "$ADDR" ] || [ -z "$CHS" ]; then
    usage
fi

# MUX high byte per channel (same as hw-management-bmc-a2d-leakage-read.sh).
ads1015_mux_byte() {
    case "$1" in
    0) printf '%s' 0xc2 ;;
    1) printf '%s' 0xd2 ;;
    2) printf '%s' 0xe2 ;;
    3) printf '%s' 0xf2 ;;
    *) return 1 ;;
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

program_channel() {
    local ch="$1"
    local mode="$2"
    local mux lo_msb lo_lsb hi_msb hi_lsb

    mux=$(ads1015_mux_byte "$ch") || return 1
    case "$mode" in
    alarm)
        lo_msb=$ALARM_LO_MSB
        lo_lsb=$ALARM_LO_LSB
        hi_msb=$ALARM_HI_MSB
        hi_lsb=$ALARM_HI_LSB
        ;;
    safe)
        lo_msb=$SAFE_LO_MSB
        lo_lsb=$SAFE_LO_LSB
        hi_msb=$SAFE_HI_MSB
        hi_lsb=$SAFE_HI_LSB
        ;;
    *)
        return 1
        ;;
    esac

    if ! i2ctransfer -f -y "$BUS" w3@"$ADDR" 0x01 "$mux" "$CFG_LO" >/dev/null 2>&1; then
        echo "Failed to write ADS1015 config for channel $ch"
        return 1
    fi
    if ! i2ctransfer -f -y "$BUS" w3@"$ADDR" 0x02 "$lo_msb" "$lo_lsb" >/dev/null 2>&1; then
        echo "Failed to write ADS1015 low threshold for channel $ch"
        return 1
    fi
    if ! i2ctransfer -f -y "$BUS" w3@"$ADDR" 0x03 "$hi_msb" "$hi_lsb" >/dev/null 2>&1; then
        echo "Failed to write ADS1015 high threshold for channel $ch"
        return 1
    fi
    return 0
}

ch=0
while [ "$ch" -lt 4 ]; do
    eval mode=\$CH${ch}
    if ! program_channel "$ch" "$mode"; then
        exit 1
    fi
    ch=$((ch + 1))
done

echo "Forced alarm configured"
echo "Bus=$BUS Addr=$ADDR Channels=$CHS"
echo "Note: ADS1015 MUX is per-channel; last programmed MUX (channel 3) remains selected."
