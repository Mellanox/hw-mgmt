#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# hw-management-bmc-early-config: copy platform-specific files from /etc/<HID>/
# to their runtime locations in /etc/ and /usr/bin/.
# Runs before kernel modules load so configs and scripts are in place for
# early I2C and other services.
#
# Shell scripts: use symlinks into $SRC_BASE (same as plat-specific-preps) so we
# do not duplicate bytes or overwrite links with copies. JSON: some under
# /etc/hw-management-bmc/; A2D leakage uses /etc/hw-management-bmc-a2d-leakage-config.json
# (same style as /etc/hw-management-bmc-early-i2c-devices.json).
#
# Default HID is HI189. Later: detect HID from BMC system EEPROM.
################################################################################

set -e

# Default platform (hardware ID). Later: parse from BMC system EEPROM.
HID="${HID:-HI189}"

SRC_BASE="/etc/${HID}"
if [ ! -d "$SRC_BASE" ] && [ -d "/usr/etc/${HID}" ]; then
	SRC_BASE="/usr/etc/${HID}"
fi
ETC_DEST="/etc/hw-management-bmc"
BIN_DEST="/usr/bin"

if [ ! -d "$SRC_BASE" ]; then
	echo "hw-management-bmc-early-config: no platform dir /etc/${HID} (or legacy /usr/etc/${HID}), skip." >&2
	exit 0
fi

mkdir -p "$ETC_DEST"

# A2D leakage JSON: single runtime path (matches hw-management-bmc-a2d-leakage-config.sh)
if [ -f "$SRC_BASE/hw-management-bmc-a2d-leakage-config.json" ]; then
	cp -f "$SRC_BASE/hw-management-bmc-a2d-leakage-config.json" /etc/hw-management-bmc-a2d-leakage-config.json
fi
# Platform shell config: use /etc/hw-management-bmc-platform.conf only (plat-specific-preps copies from HI189).

# Early I2C JSON: expected by hw-management-bmc-early-i2c-init at /etc/
EARLY_I2C_JSON="$SRC_BASE/hw-management-bmc-early-i2c-devices.json"
EARLY_I2C_JSON_LEGACY="$SRC_BASE/hw-management-spc6-ast2700-a1-bmc/bmc-early-i2c-devices.json"
if [ -f "$EARLY_I2C_JSON" ]; then
	cp -f "$EARLY_I2C_JSON" /etc/hw-management-bmc-early-i2c-devices.json
elif [ -f "$EARLY_I2C_JSON_LEGACY" ]; then
	cp -f "$EARLY_I2C_JSON_LEGACY" /etc/hw-management-bmc-early-i2c-devices.json
fi

# Platform scripts: symlink into /usr/bin (single copy under /etc/<HID>/)
shopt -s nullglob
for f in "$SRC_BASE"/*.sh; do
	base=$(basename "$f")
	chmod +x "$f"
	ln -sfn "$f" "$BIN_DEST/$base"
done
shopt -u nullglob

echo "hw-management-bmc-early-config: applied config for HID=$HID"
