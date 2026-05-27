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
# ADS7924: read mode, interrupt/alarm, and channel data via i2ctransfer (debug).
# Register map: TI SBAS482 (same layout as hw-management-bmc-a2d-leakage-config.sh).
################################################################################

# Usage:
#   hw-management-bmc-ads7924-read-status.sh <bus> <addr> [scale]
# Example:
#   hw-management-bmc-ads7924-read-status.sh 12 0x48
#   hw-management-bmc-ads7924-read-status.sh 12 0x48 0.000244140625

BUS="$1"
ADDR="$2"
SCALE="${3:-0.000244140625}"

usage() {
    echo "Usage: $0 <bus> <i2c_addr> [scale]"
    echo "  scale: volts per LSB (default 0.000244140625)"
    exit 1
}

if [ -z "$BUS" ] || [ -z "$ADDR" ]; then
    usage
fi

MODE_DATA=$(i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x00 r1 2>/dev/null) || true
INT_DATA=$(i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x01 r1 2>/dev/null) || true
# Auto-increment from DATA0_U (0x02): pointer 0x82, read 8 bytes (4 channels × 2).
CHAN_DATA=$(i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x82 r8 2>/dev/null) || true

MODE_B=$(echo "$MODE_DATA" | awk '{print $1}')
INT_B=$(echo "$INT_DATA" | awk '{print $1}')

if [ -z "$MODE_B" ]; then
    echo "Failed to read ADS7924 MODECNTRL (0x00)"
    exit 1
fi
if [ -z "$INT_B" ]; then
    echo "Failed to read ADS7924 INTCNTRL (0x01)"
    exit 1
fi

MODE=$((${MODE_B}))
INT=$((${INT_B}))

MODE_FIELD=$(( (MODE >> 2) & 0x3f ))
SEL=$(( MODE & 3 ))
AEN=$(( INT & 15 ))
ALRM=$(( (INT >> 4) & 15 ))

echo "I2C bus     : $BUS"
echo "I2C address : $ADDR"
echo "Scale       : $SCALE V/LSB"
echo ""
printf 'MODECNTRL (0x00): 0x%02x\n' "$MODE"
echo "  MODE [7:2]  : $MODE_FIELD"
echo "  SEL [1:0]   : $SEL"
echo ""
printf 'INTCNTRL (0x01): 0x%02x\n' "$INT"
echo "  Alarm status (ALRM_ST3..0, bits 7:4):"
i=0
while [ "$i" -lt 4 ]; do
    bit=$(( (ALRM >> i) & 1 ))
    if [ "$bit" -ne 0 ]; then
        echo "    Channel $i alarm active"
    fi
    i=$((i + 1))
done
if [ "$ALRM" -eq 0 ]; then
    echo "    (none)"
fi
echo "  Alarm enable (AEN3..0, bits 3:0): $(printf '0x%x' "$AEN")"
echo ""
echo "Channel data (DATAx_U/L, pointer 0x82 + INC):"

if [ -z "$CHAN_DATA" ]; then
    echo "  (read failed)"
    exit 0
fi

# shellcheck disable=SC2086
set -- $CHAN_DATA
ch=0
while [ "$ch" -lt 4 ]; do
    case $ch in
    0) b_hi=$1; b_lo=$2 ;;
    1) b_hi=$3; b_lo=$4 ;;
    2) b_hi=$5; b_lo=$6 ;;
    3) b_hi=$7; b_lo=$8 ;;
    esac
    if [ -z "$b_hi" ] || [ -z "$b_lo" ]; then
        echo "  Channel $ch: (missing bytes)"
        ch=$((ch + 1))
        continue
    fi
    hi=$((${b_hi}))
    lo=$((${b_lo}))
    raw=$(( (hi << 8) | lo ))
    raw12=$(( raw >> 4 ))
    volts=$(awk -v r="$raw12" -v s="$SCALE" 'BEGIN { printf "%.10f", r * s }')
    echo "  Channel $ch: raw=0x$(printf '%03x' "$raw12")  ${volts} V  ($b_hi $b_lo)"
    ch=$((ch + 1))
done
