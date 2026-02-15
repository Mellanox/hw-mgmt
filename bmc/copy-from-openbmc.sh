#!/bin/bash
# Copy OpenBMC files into bmc/ with hw-management prefix when the filename
# does not already contain "hw-management". Destinations under bmc/ (repo root = hw-mgmt).
set -e
OPENBMC="${OPENBMC:-/hdd/build/vadimp/develop-new/openbmc}"
S="$OPENBMC/meta-nvidia/meta-switch"
A="$S/meta-ast2700/meta-spc6-ast2700-a1/recipes-nvidia/bmc-post-boot-cfg/files"
HM="$S/recipes-nvidia/health-monitor/files"
BP="$S/recipes-nvidia/bmc-post-boot-cfg/files"
BD="$(dirname "$0")"   # bmc/

# Add hw-management- prefix unless the filename already starts with hw-management
add_prefix() {
	local base="$1"
	if [[ "$base" == hw-management* ]]; then
		echo "$base"
	else
		echo "hw-management-$base"
	fi
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

# udev (already has hw-management in name)
cp "$A/71-hw-management-events.rules" "$BD/usr/lib/udev/rules.d/"

# Platform HI193 (add prefix for config files)
cp "$A/a2d_leakage_config.json" "$BD/usr/etc/HI193/$(add_prefix 'a2d_leakage_config.json')"
cp "$A/platform_config" "$BD/usr/etc/HI193/$(add_prefix 'platform_config')"
cp "$A/spc6-bmc.conf" "$BD/usr/etc/HI193/$(add_prefix 'spc6-bmc.conf')"
cp -a "$A/spc6-ast2700-a1-bmc" "$BD/usr/etc/HI193/$(add_prefix 'spc6-ast2700-a1-bmc')"

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
for f in "$A/bmc_ready_common.sh" "$A/bmc-plat-specific-preps.sh" "$A/bmc_set_extra_params.sh" "$A/i2c-boot-progress.sh" "$A/i2c-slave-config.sh"; do
	dest=$(add_prefix "$(basename "$f")")
	cp "$f" "$BD/usr/usr/bin/$dest"
	chmod +x "$BD/usr/usr/bin/$dest"
done
# Platform-specific scripts -> etc/HI193 (not usr/bin)
for f in "$A/spc6-ast2700-a1-bmc_ready.sh" "$A/spc6-ast2700-a1-hw-management-events.sh"; do
	dest=$(add_prefix "$(basename "$f")")
	cp "$f" "$BD/usr/etc/HI193/$dest"
	chmod +x "$BD/usr/etc/HI193/$dest"
done
# Removed (Microsoft doesn't need): ast2700-a1-spc6-switch-erots-info.sh, spc6-svn-check.sh
# Scripts that already have hw-management in name
for f in "$A/hw-management.sh" "$A/hw-management-devtree-check.sh" "$A/hw-management-devtree.sh" "$A/hw-management-helpers.sh"; do
	cp "$f" "$BD/usr/usr/bin/$(basename "$f")"
	chmod +x "$BD/usr/usr/bin/$(basename "$f")"
done
# (spc6-ast2700-a1-hw-management-events.sh copied to etc/HI193 above)

echo "Copy done. Update .service files ExecStart paths to hw-management-* script names."
echo "Run: sed -i 's|/usr/bin/bmc-|/usr/bin/hw-management-bmc-|g; s|/usr/bin/bmc_|/usr/bin/hw-management-bmc_|g; s|/usr/bin/i2c-boot-progress|/usr/bin/hw-management-i2c-boot-progress|g; s|bmc_ready\.sh|hw-management-bmc_ready_common.sh|g' bmc/usr/lib/systemd/system/hw-management-*.service"
# bmc-boot-complete has ExecStartPre=bmc_ready.sh and ExecStart=i2c-boot-progress.sh - adjust as needed
