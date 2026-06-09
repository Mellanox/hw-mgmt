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
# ADS1015: read config / conversion registers via i2ctransfer (debug).
# Register map: TI SBAS173 (pointer 0x00 conversion, 0x01 config).
################################################################################

# Usage:
#   hw-management-bmc-ads1015-read-status.sh <bus> <addr> [channel]
# Examples:
#   hw-management-bmc-ads1015-read-status.sh 12 0x49
#   hw-management-bmc-ads1015-read-status.sh 12 0x49 2

BUS="$1"
ADDR="$2"
CHANNEL="$3"

# Legacy MUX high bytes (same as hw-management-bmc-a2d-leakage-config.sh).
# Default cfg low 0x83 (comparator disabled, continuous) — override with third arg.
ADS1015_CFG_LO=0x83
ADS1015_CH_OFFSET_1=0xc2
ADS1015_CH_OFFSET_2=0xd2
ADS1015_CH_OFFSET_3=0xe2
ADS1015_CH_OFFSET_4=0xf2

usage() {
    echo "Usage: $0 <bus> <i2c_addr> [channel]"
    echo "  channel: 1-4 optional — program MUX then read conversion"
    exit 1
}

if [ -z "$BUS" ] || [ -z "$ADDR" ]; then
    usage
fi

if [ -n "$CHANNEL" ]; then
    case "$CHANNEL" in
    1) CH_OFF=$ADS1015_CH_OFFSET_1 ;;
    2) CH_OFF=$ADS1015_CH_OFFSET_2 ;;
    3) CH_OFF=$ADS1015_CH_OFFSET_3 ;;
    4) CH_OFF=$ADS1015_CH_OFFSET_4 ;;
    *) echo "Invalid channel: $CHANNEL (use 1-4)"; exit 1 ;;
    esac
    if ! i2ctransfer -f -y "$BUS" w3@"$ADDR" 0x01 "$CH_OFF" "$ADS1015_CFG_LO" >/dev/null 2>&1; then
        echo "Failed to select ADS1015 channel $CHANNEL"
        exit 1
    fi
    sleep 0.1
fi

CFG_DATA=$(i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x01 r2 2>/dev/null) || true
CONV_DATA=$(i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x00 r2 2>/dev/null) || true

CFG_B0=$(echo "$CFG_DATA" | awk '{print $1}')
CFG_B1=$(echo "$CFG_DATA" | awk '{print $2}')
CONV_B0=$(echo "$CONV_DATA" | awk '{print $1}')
CONV_B1=$(echo "$CONV_DATA" | awk '{print $2}')

if [ -z "$CFG_B0" ] || [ -z "$CFG_B1" ]; then
    echo "Failed to read ADS1015 config register (pointer 0x01)"
    exit 1
fi

if [ -z "$CONV_B0" ] || [ -z "$CONV_B1" ]; then
    echo "Failed to read ADS1015 conversion register (pointer 0x00)"
    exit 1
fi

CFG_HI=$((${CFG_B0}))
CFG_LO=$((${CFG_B1}))
CONV_HI=$((${CONV_B0}))
CONV_LO=$((${CONV_B1}))
CFG=$(( (CFG_HI << 8) | CFG_LO ))
CONV=$(( (CONV_HI << 8) | CONV_LO ))
CONV_RAW=$CONV
# Sign-extend 16-bit two's complement for voltage display only.
[ "$CONV" -ge 32768 ] && CONV=$((CONV - 65536))

# Default ±4.096 V, single-ended — same scaling as leakage reader.
VOLTS=$(awk -v v="$CONV" 'BEGIN { printf "%.6f", (v / 16) * 0.002 }')

OS=$(( (CFG >> 15) & 1 ))
MUX=$(( (CFG >> 12) & 7 ))
PGA=$(( (CFG >> 9) & 7 ))
MODE=$(( (CFG >> 8) & 1 ))
DR=$(( (CFG >> 5) & 7 ))
COMP_MODE=$(( (CFG >> 4) & 1 ))
COMP_POL=$(( (CFG >> 3) & 1 ))
COMP_LAT=$(( (CFG >> 2) & 1 ))
COMP_QUE=$(( CFG & 3 ))

echo "I2C bus       : $BUS"
echo "I2C address   : $ADDR"
[ -n "$CHANNEL" ] && echo "Channel select: $CHANNEL (config high byte 0x$(printf '%02x' "$CH_OFF"))"
echo ""
echo "Config register (0x01): 0x$(printf '%04x' "$CFG")  bytes $CFG_B0 $CFG_B1"
echo "  OS (bit 15)       : $OS  (1 = idle / not converting)"
echo "  MUX [14:12]       : $MUX"
echo "  PGA [11:9]        : $PGA"
echo "  MODE (bit 8)      : $MODE  (0=continuous, 1=single-shot)"
echo "  DR [7:5]          : $DR"
echo "  COMP_MODE (bit 4) : $COMP_MODE"
echo "  COMP_POL (bit 3)  : $COMP_POL"
echo "  COMP_LAT (bit 2)  : $COMP_LAT"
echo "  COMP_QUE [1:0]    : $COMP_QUE"
echo ""
echo "Conversion register (0x00): 0x$(printf '%04x' "$CONV_RAW")  bytes $CONV_B0 $CONV_B1"
echo "  Raw ADC code      : $CONV_RAW"
echo "  Voltage (approx)  : ${VOLTS} V  ((code/16)*0.002, ±4.096 V assumption)"
