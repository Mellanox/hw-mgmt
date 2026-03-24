#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Copy OpenBMC files into bmc/ with hw-management prefix when the filename
# does not already contain "hw-management". Destinations under bmc/ (repo root = hw-mgmt).
set -e
OPENBMC="${OPENBMC:-/hdd/build/vadimp/develop-new/openbmc}"
S="$OPENBMC/meta-nvidia/meta-switch"
A="$S/meta-ast2700/meta-spc6-ast2700-a1/recipes-nvidia/bmc-post-boot-cfg/files"
HM="$S/recipes-nvidia/health-monitor/files"
BP="$S/recipes-nvidia/bmc-post-boot-cfg/files"
BD="$(dirname "$0")"   # bmc/
NIC="$S/meta-ast2700/recipes-nvidia/nvidia-internal-network-config/files"

# Add hw-management- prefix unless the filename already starts with hw-management
add_prefix() {
	local base="$1"
	if [[ "$base" == hw-management* ]]; then
		echo "$base"
	else
		echo "hw-management-$base"
	fi
}

# BMC SONiC package uses hw-management-bmc-* for scripts that overlap CPU naming.
openbmc_script_dest() {
	local base="$1"
	case "$base" in
		i2c-slave-config.sh) echo hw-management-bmc-i2c-slave-config.sh ;;
		bmc_ready_common.sh) echo hw-management-bmc-ready-common.sh ;;
		bmc-plat-specific-preps.sh) echo hw-management-bmc-plat-specific-preps.sh ;;
		bmc_set_extra_params.sh) echo hw-management-bmc-set-extra-params.sh ;;
		hw-management.sh) echo hw-management-bmc.sh ;;
		hw-management-devtree-check.sh) echo hw-management-bmc-devtree-check.sh ;;
		hw-management-devtree.sh) echo hw-management-bmc-devtree.sh ;;
		hw-management-helpers.sh) echo hw-management-bmc-helpers.sh ;;
		*) add_prefix "$base" ;;
	esac
}

# systemd units -> bmc/usr/lib/systemd/system/ (with prefix)
for f in "$HM/bmc-health-monitor.service" "$HM/bmc-reset-cause-logger.service"; do
	dest=$(add_prefix "$(basename "$f")")
	cp "$f" "$BD/usr/lib/systemd/system/$dest"
done
for f in "$BP/bmc-boot-complete.service" "$BP/bmc-early-i2c-init.service" "$BP/bmc-i2c-slave-setup.service" "$BP/bmc-plat-specific-preps.service" "$BP/bmc-recovery-handler.service"; do
	dest=$(add_prefix "$(basename "$f")")
	cp "$f" "$BD/usr/lib/systemd/system/$dest"
done
# bmc-svn-update.service removed (Microsoft doesn't need spc6-svn-check)

# systemd-networkd: common template under usr/etc/systemd/network (Address filled at boot from platform conf)
mkdir -p "$BD/usr/etc/systemd/network"
if [ -f "$NIC/00-bmc-usb0.network" ]; then
	sed 's/^Address=.*/Address=__USB0_ADDRESS__/' "$NIC/00-bmc-usb0.network" \
		>"$BD/usr/etc/systemd/network/00-hw-management-bmc-usb0.network"
else
	echo "copy-from-openbmc: skip usb0 network (missing $NIC/00-bmc-usb0.network)" >&2
fi

# udev rules: ship with platform under usr/etc/HI189 (copied to /lib/udev/rules.d at boot)
cp "$A/71-hw-management-events.rules" "$BD/usr/etc/HI189/71-hw-management-bmc-events.rules"

# Platform HI189 (add prefix for config files)
cp "$A/a2d_leakage_config.json" "$BD/usr/etc/HI189/hw-management-bmc-a2d-leakage-config.json"
cp "$A/platform_config" "$BD/usr/etc/HI189/hw-management-bmc-platform.conf"
cp "$A/spc6-bmc.conf" "$BD/usr/etc/HI189/hw-management-bmc.conf"
cp -a "$A/spc6-ast2700-a1-bmc" "$BD/usr/etc/HI189/$(add_prefix 'spc6-ast2700-a1-bmc')"

# Scripts -> bmc/usr/usr/bin/
for f in "$HM/bmc-health-monitor.sh" "$HM/bmc-reset-cause-logger.sh"; do
	dest=$(add_prefix "$(basename "$f")")
	cp "$f" "$BD/usr/usr/bin/$dest"
	chmod +x "$BD/usr/usr/bin/$dest"
done
for f in "$BP/bmc-early-i2c-init.sh" "$BP/bmc-i2c-slave-setup.sh" "$BP/bmc-recovery-handler.sh"; do
	dest=$(add_prefix "$(basename "$f")")
	cp "$f" "$BD/usr/usr/bin/$dest"
	chmod +x "$BD/usr/usr/bin/$dest"
done
# Note: OpenBMC i2c-boot-progress.sh is not copied; SONiC BMC uses hw-management-bmc-boot-complete.sh in-tree.
for f in "$A/bmc_ready_common.sh" "$A/bmc-plat-specific-preps.sh" "$A/bmc_set_extra_params.sh" "$A/i2c-slave-config.sh"; do
	dest=$(openbmc_script_dest "$(basename "$f")")
	cp "$f" "$BD/usr/usr/bin/$dest"
	chmod +x "$BD/usr/usr/bin/$dest"
done
# Platform-specific scripts -> etc/HI189 (not usr/bin)
f="$A/spc6-ast2700-a1-bmc_ready.sh"
dest=$(add_prefix "$(basename "$f")")
cp "$f" "$BD/usr/etc/HI189/$dest"
chmod +x "$BD/usr/etc/HI189/$dest"
cp "$A/spc6-ast2700-a1-hw-management-events.sh" "$BD/usr/etc/HI189/hw-management-bmc-events.sh"
chmod +x "$BD/usr/etc/HI189/hw-management-bmc-events.sh"
# Removed (Microsoft doesn't need): ast2700-a1-spc6-switch-erots-info.sh, spc6-svn-check.sh
cp "$A/switch_json_parser.sh" "$BD/usr/usr/bin/hw-management-bmc-json-parser.sh"
chmod +x "$BD/usr/usr/bin/hw-management-bmc-json-parser.sh"
cp "$A/hw-management-helpers-common.sh" "$BD/usr/usr/bin/hw-management-bmc-helpers-common.sh"
chmod +x "$BD/usr/usr/bin/hw-management-bmc-helpers-common.sh"
# Scripts that already have hw-management in name
for f in "$A/hw-management.sh" "$A/hw-management-devtree-check.sh" "$A/hw-management-devtree.sh" "$A/hw-management-helpers.sh"; do
	dest=$(openbmc_script_dest "$(basename "$f")")
	cp "$f" "$BD/usr/usr/bin/$dest"
	chmod +x "$BD/usr/usr/bin/$dest"
done
# (spc6-ast2700-a1-hw-management-events.sh copied to etc/HI189/hw-management-bmc-events.sh above)

echo "Copy done. Align systemd ExecStart* in bmc/usr/lib/systemd/system/hw-management-*.service if upstream names differ (e.g. hw-management-bmc-boot-complete.sh, hw-management-bmc-ready-common.sh)."
