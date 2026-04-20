#!/bin/bash

# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
################################################################################
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions, and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions, and the following disclaimer in the
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
# BMC-side host BIOS recovery flash (when CPU is not available).
# Selects SPI channel via CPLD (spi_chnl_select) then flashes using flashcp.
#
# Origin: OpenBMC meta-nvidia bmc-post-boot-cfg bios-recovery-flash.sh
#
# Prerequisites on BMC:
#   - hw-management provides /var/run/hw-management/system/spi_chnl_select
#   - spidev for host BIOS path (DTS: spidev on the bus behind CPLD mux)
#   - mtd-utils (flashcp)
#
# Usage:
#   hw-management-bmc-bios-recovery-flash.sh <bios_image> [spidev] [channel]
#
# Examples:
#   hw-management-bmc-bios-recovery-flash.sh /tmp/bios.rom
#   hw-management-bmc-bios-recovery-flash.sh /tmp/bios.rom /dev/spidev1.0
#   hw-management-bmc-bios-recovery-flash.sh /tmp/bios.rom /dev/spidev1.0 1
#
# Manual flow:
#   echo 1 > /var/run/hw-management/system/spi_chnl_select
#   flashcp /path/to/bios.rom /dev/spidev1.0
################################################################################

set -e

SPI_CHNL_SELECT="/var/run/hw-management/system/spi_chnl_select"
DEFAULT_SPIDEV="/dev/spidev1.0"
DEFAULT_CHANNEL="1"

usage() {
	echo "Usage: $0 <bios_image> [spidev] [channel]"
	echo "  bios_image  Path to BIOS image to flash"
	echo "  spidev      SPI device (default: $DEFAULT_SPIDEV)"
	echo "  channel     CPLD SPI channel selection 0 or 1 (default: $DEFAULT_CHANNEL)"
	echo ""
	echo "BMC recovery: run on BMC when host CPU is not available."
	exit 1
}

if [ $# -lt 1 ]; then
	usage
fi

IMAGE="$1"
SPIDEV="${2:-$DEFAULT_SPIDEV}"
CHANNEL="${3:-$DEFAULT_CHANNEL}"

if [ ! -f "$IMAGE" ]; then
	echo "Error: BIOS image not found: $IMAGE"
	exit 1
fi

if [ ! -w "$SPI_CHNL_SELECT" ]; then
	echo "Error: Cannot write SPI channel select: $SPI_CHNL_SELECT"
	echo "       (hw-management must be running and expose spi_chnl_select)"
	exit 1
fi

if [ ! -w "$SPIDEV" ]; then
	echo "Error: SPI device not writable: $SPIDEV"
	exit 1
fi

if ! command -v flashcp >/dev/null 2>&1; then
	echo "Error: flashcp not found (install mtd-utils)"
	exit 1
fi

echo "Selecting SPI channel $CHANNEL (host BIOS flash)"
echo "$CHANNEL" > "$SPI_CHNL_SELECT"

echo "Flashing $IMAGE to $SPIDEV"
flashcp -v "$IMAGE" "$SPIDEV"

echo "Done."
