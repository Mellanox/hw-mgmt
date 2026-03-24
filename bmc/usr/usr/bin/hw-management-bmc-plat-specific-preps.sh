#!/bin/bash

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

################################################################################
# This script performs file system related platform specific changes
# It must run after local filesystems are available and before all normal services
# are started.
# Note: logger service may not be available.
#
# Deploy strategy: use symbolic links from /usr/bin, /lib/udev/rules.d, and
# /etc/modprobe.d into /etc/<HID>/ for static packaged content (scripts, udev
# rules, modprobe). That keeps a single copy on the read-mostly rootfs, avoids
# duplicating file bytes on writable overlays, and reduces boot-time write volume.
# We still *copy* JSON, platform/eeprom/boot-complete conf, and USB0 material that
# operators or this script may rewrite under /etc (symlinks to RO package paths
# would block local edits or fail on read-only /usr).
################################################################################

sku=""

# Detect BMC HID (hidNNN) from device-tree: e.g. directory nvsw_bmc_hid189@31 under .../i2c-bus@f00/
# Searches /proc/device-tree and /sys/firmware/devicetree/base (some images only expose one).
# Optional override: HW_MANAGEMENT_BMC_HID_OVERRIDE=hid189
get_hwid() {
	sku=""
	if [ -n "${HW_MANAGEMENT_BMC_HID_OVERRIDE:-}" ]; then
		case "$HW_MANAGEMENT_BMC_HID_OVERRIDE" in
		hid[0-9]*)
			sku=$HW_MANAGEMENT_BMC_HID_OVERRIDE
			echo "bmc platform specific settings, sku: $sku (from HW_MANAGEMENT_BMC_HID_OVERRIDE)"
			return
			;;
		*)
			echo "plat-specific: HW_MANAGEMENT_BMC_HID_OVERRIDE must look like hid189 (got $HW_MANAGEMENT_BMC_HID_OVERRIDE), trying device-tree" >&2
			;;
		esac
	fi
	local dt line base
	for dt in /proc/device-tree /sys/firmware/devicetree/base; do
		[ -d "$dt" ] || continue
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			base=$(basename "$line")
			if [[ "$base" =~ hid([0-9]+) ]]; then
				sku="hid${BASH_REMATCH[1]}"
				echo "bmc platform specific settings, sku: $sku (device-tree node: $base)"
				return
			fi
		done < <(find "$dt" -type d -name 'nvsw*' 2>/dev/null)
	done
	echo "plat-specific: could not find nvsw* / hidNNN in device-tree (try HW_MANAGEMENT_BMC_HID_OVERRIDE=hidNNN)" >&2
}

# Map device-tree SKU (hidNNN) to packaged platform ID directory (HINNN) under /etc/.
# Package installs e.g. /etc/HI189/ (from bmc/usr/etc/HI189/ in the source tree); at boot we mirror JSON and configs to /etc, scripts to /usr/bin.
deploy_hw_management_bmc_platform_files()
{
	[ -n "$sku" ] || return 0
	case "$sku" in
	hid[0-9]*) ;;
	*) return 0 ;;
	esac
	local HID HID_SRC
	HID=$(echo "$sku" | sed 's/^hid/HI/')
	HID_SRC="/etc/${HID}"
	if [ ! -d "$HID_SRC" ] && [ -d "/usr/etc/${HID}" ]; then
		HID_SRC="/usr/etc/${HID}"
	fi
	if [ ! -d "$HID_SRC" ]; then
		echo "plat-specific: no packaged platform dir /etc/${HID} or /usr/etc/${HID} (sku=$sku), skip deploy"
		return 0
	fi
	echo "plat-specific: deploying from $HID_SRC (symlinks for sh/rules/modprobe; copies for editable /etc content)"
	# Runtime tree must exist before udev RUN handlers and hw-management-bmc-init; regio/hotplug
	# normally fill /var/run/hw-management/system — if those exit non-zero, init still needs the dirs.
	# Do NOT mkdir /var/run/hw-management/config here: hw-management-bmc-ready.sh used to treat an
	# existing config/ dir as "init already ran" and skipped bmc_init_main (GPIO symlinks, A2D leakage).
	mkdir -p /var/run/hw-management/system /var/run/hw-management/thermal \
		/var/run/hw-management/eeprom \
		/var/run/hw-management/leakage 2>/dev/null || true
	shopt -s nullglob
	# Includes e.g. hw-management-bmc-bom.json -> /etc/hw-management-bmc-bom.json for SMBIOS BOM devtree.
	for f in "$HID_SRC"/*.json; do
		cp -f "$f" /etc/
	done
	shopt -u nullglob
	[ -f "$HID_SRC/hw-management-bmc-platform.conf" ] && \
		cp -f "$HID_SRC/hw-management-bmc-platform.conf" /etc/
	if [ -f "$HID_SRC/hw-management-bmc-eeprom.conf" ]; then
		cp -f "$HID_SRC/hw-management-bmc-eeprom.conf" /etc/hw-management-bmc-eeprom.conf
		chmod 0644 /etc/hw-management-bmc-eeprom.conf
		echo "plat-specific: installed /etc/hw-management-bmc-eeprom.conf from $HID_SRC"
	fi
	if [ -f "$HID_SRC/hw-management-bmc-boot-complete.conf" ]; then
		cp -f "$HID_SRC/hw-management-bmc-boot-complete.conf" /etc/hw-management-bmc-boot-complete.conf
		chmod 0644 /etc/hw-management-bmc-boot-complete.conf
		echo "plat-specific: installed /etc/hw-management-bmc-boot-complete.conf from $HID_SRC"
	fi
	if [ -f "$HID_SRC/hw-management-bmc.conf" ]; then
		mkdir -p /etc/modprobe.d
		ln -sfn "$HID_SRC/hw-management-bmc.conf" /etc/modprobe.d/hw-management-bmc.conf
	fi
	shopt -s nullglob
	for f in "$HID_SRC"/*.sh; do
		base=$(basename "$f")
		chmod +x "$f"
		ln -sfn "$f" "/usr/bin/$base"
	done
	shopt -u nullglob
	mkdir -p /lib/udev/rules.d
	shopt -s nullglob
	for f in "$HID_SRC"/*.rules; do
		base=$(basename "$f")
		# Optional MCTP rules: ship under /etc/<HID>/ for manual install only
		[ "$base" = "99-hw-management-bmc-mctp.rules" ] && continue
		ln -sfn "$f" "/lib/udev/rules.d/$base"
	done
	shopt -u nullglob

	# USB0 (CPU ↔ BMC): copy platform network params and render systemd-networkd unit.
	default_usb0_addr="169.254.0.1/16"
	if [ -f "$HID_SRC/hw-management-bmc-network.conf" ]; then
		cp -f "$HID_SRC/hw-management-bmc-network.conf" /etc/hw-management-bmc-usb0.conf
		chmod 0644 /etc/hw-management-bmc-usb0.conf
	fi

	if [ ! -f /usr/etc/systemd/network/00-hw-management-bmc-usb0.network ]; then
		:
	else
		local usb0_addr
		usb0_addr=""
		if [ -f "$HID_SRC/hw-management-bmc-network.conf" ] && [ -f /etc/hw-management-bmc-usb0.conf ]; then
			usb0_addr=$(sed -n 's/^[[:space:]]*USB0_ADDRESS=//p' /etc/hw-management-bmc-usb0.conf | head -1 | tr -d " '\"")
		elif [ ! -f "$HID_SRC/hw-management-bmc-network.conf" ]; then
			# No packaged hw-management-bmc-network.conf: use /etc if valid, else default.
			if [ -f /etc/hw-management-bmc-usb0.conf ]; then
				usb0_addr=$(sed -n 's/^[[:space:]]*USB0_ADDRESS=//p' /etc/hw-management-bmc-usb0.conf | head -1 | tr -d " '\"")
			fi
			if [ -z "$usb0_addr" ] || ! printf '%s' "$usb0_addr" | grep -qE '^[0-9a-fA-F.:/]+/[0-9]+$'; then
				usb0_addr="$default_usb0_addr"
				printf '%s\n' \
					"# Default USB0 (no packaged ${HID_SRC}/hw-management-bmc-network.conf)" \
					"USB0_ADDRESS=${usb0_addr}" >/etc/hw-management-bmc-usb0.conf
				chmod 0644 /etc/hw-management-bmc-usb0.conf
				echo "plat-specific: default USB0_ADDRESS=${usb0_addr} (no packaged hw-management-bmc-network.conf)"
			fi
		fi

		# Validate CIDR without bash [[ =~ ]] (BusyBox ash / POSIX sh friendly).
		if [ -z "$usb0_addr" ] || ! printf '%s' "$usb0_addr" | grep -qE '^[0-9a-fA-F.:/]+/[0-9]+$'; then
			echo "plat-specific: invalid or empty USB0_ADDRESS in /etc/hw-management-bmc-usb0.conf, skip usb0 .network"
		else
			mkdir -p /etc/systemd/network
			sed "s|__USB0_ADDRESS__|${usb0_addr}|g" /usr/etc/systemd/network/00-hw-management-bmc-usb0.network \
				>/etc/systemd/network/00-hw-management-bmc-usb0.network
			chmod 0644 /etc/systemd/network/00-hw-management-bmc-usb0.network
			echo "plat-specific: wrote /etc/systemd/network/00-hw-management-bmc-usb0.network (usb0 ${usb0_addr})"
		fi
	fi
}

get_hwid
deploy_hw_management_bmc_platform_files

