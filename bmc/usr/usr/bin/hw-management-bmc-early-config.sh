#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# hw-management-bmc-early-config: copy platform-specific files from /usr/etc/<HID>/
# to their runtime locations in /etc/ and /usr/bin/.
# Runs before kernel modules load so configs and scripts are in place for
# early I2C and other services.
#
# Default HID is HI193. Later: detect HID from BMC system EEPROM.
################################################################################

set -e

# Default platform (hardware ID). Later: parse from BMC system EEPROM.
HID="${HID:-HI193}"

SRC_BASE="/usr/etc/${HID}"
if [ ! -d "$SRC_BASE" ] && [ -d "/etc/${HID}" ]; then
	SRC_BASE="/etc/${HID}"
fi
ETC_DEST="/etc/hw-management-bmc"
BIN_DEST="/usr/bin"

if [ ! -d "$SRC_BASE" ]; then
	echo "hw-management-bmc-early-config: no platform dir /usr/etc/${HID} (or legacy /etc/${HID}), skip." >&2
	exit 0
fi

mkdir -p "$ETC_DEST"

# Config files: copy to /etc/hw-management-bmc/ with standard names
for f in hw-management-a2d-leakage-config.json hw-management-platform.conf; do
	[ -f "$SRC_BASE/$f" ] && cp -f "$SRC_BASE/$f" "$ETC_DEST/${f#hw-management-}"
done

# Early I2C JSON: expected by hw-management-bmc-early-i2c-init at /etc/
EARLY_I2C_JSON="$SRC_BASE/hw-management-bmc-early-i2c-devices.json"
EARLY_I2C_JSON_LEGACY="$SRC_BASE/hw-management-spc6-ast2700-a1-bmc/bmc-early-i2c-devices.json"
if [ -f "$EARLY_I2C_JSON" ]; then
	cp -f "$EARLY_I2C_JSON" /etc/hw-management-bmc-early-i2c-devices.json
elif [ -f "$EARLY_I2C_JSON_LEGACY" ]; then
	cp -f "$EARLY_I2C_JSON_LEGACY" /etc/hw-management-bmc-early-i2c-devices.json
fi

# Platform scripts: copy to /usr/bin so udev and services can run them
shopt -s nullglob
for f in "$SRC_BASE"/*.sh; do
	base=$(basename "$f")
	cp -f "$f" "$BIN_DEST/$base"
	chmod +x "$BIN_DEST/$base"
done
shopt -u nullglob

echo "hw-management-bmc-early-config: applied config for HID=$HID"
