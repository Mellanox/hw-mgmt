#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# hw-management-early-config: copy platform-specific files from /etc/<HID>/
# to their runtime locations in /etc/ and /usr/bin/.
# Runs before kernel modules load so configs and scripts are in place for
# early I2C and other services.
#
# Default HID is HI193. Later: detect HID from BMC system EEPROM.
################################################################################

set -e

# Default platform (hardware ID). Later: parse from BMC system EEPROM.
HID="${HID:-HI193}"

SRC_BASE="/etc/${HID}"
ETC_DEST="/etc/hw-management-bmc"
BIN_DEST="/usr/bin"

if [ ! -d "$SRC_BASE" ]; then
	echo "hw-management-early-config: no platform dir $SRC_BASE, skip." >&2
	exit 0
fi

mkdir -p "$ETC_DEST"

# Config files: copy to /etc/hw-management-bmc/ with standard names
for f in hw-management-a2d_leakage_config.json hw-management-platform_config hw-management-spc6-bmc.conf; do
	[ -f "$SRC_BASE/$f" ] && cp -f "$SRC_BASE/$f" "$ETC_DEST/${f#hw-management-}"
done

# bmc-early-i2c-devices.json: expected by hw-management-bmc-early-i2c-init at /etc/
EARLY_I2C_JSON="$SRC_BASE/hw-management-spc6-ast2700-a1-bmc/bmc-early-i2c-devices.json"
if [ -f "$EARLY_I2C_JSON" ]; then
	cp -f "$EARLY_I2C_JSON" /etc/bmc-early-i2c-devices.json
fi

# Platform scripts: copy to /usr/bin so udev and services can run them
for f in hw-management-spc6-ast2700-a1-bmc_ready.sh hw-management-spc6-ast2700-a1-hw-management-events.sh; do
	[ -f "$SRC_BASE/$f" ] && cp -f "$SRC_BASE/$f" "$BIN_DEST/$f" && chmod +x "$BIN_DEST/$f"
done

echo "hw-management-early-config: applied config for HID=$HID"
