#!/bin/sh
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2020-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause

# Description: hw-management generate dump script.
#              This script collecting debug information and pack it in /tmp/hw-mgmt-dump.tar.gz

DUMP_FOLDER="/tmp/hw-mgmt-dump"
HW_MGMT_FOLDER="/var/run/hw-management/"
SSD_LOG_DIR="/var/log/ssd-dump"
board_type=$(cat /sys/devices/virtual/dmi/id/board_name 2>/dev/null || echo "")
REGMAP_FILE="/sys/kernel/debug/regmap/mlxplat/registers"
REGMAP_FILE_ARM64="/sys/kernel/debug/regmap/MLNXBF49:00/registers"
CPLD_IOREG_RANGE=256
dump_process_pid=$$

# Options, in any order:
#   compact    skip the journal and its boot list
#   no-dmesg   do not collect dmesg
MODE=
COLLECT_DMESG="yes"
for arg in "$@"; do
	case "$arg" in
	compact) MODE="compact" ;;
	no-dmesg) COLLECT_DMESG="no" ;;
	esac
done

dump_cmd () {
	cmd=$1
	output_fname=$2
	timeout=$3
	cmd_name=${cmd%% *}

	if [ -x "$(command -v "$cmd_name")" ];
	then
		# ignore shellcheck message SC2016. Arguments should be single-quoted (')
		run_cmd="$cmd 1> \"$DUMP_FOLDER/$output_fname\" 2> \"$DUMP_FOLDER/$output_fname\""
		timeout "$timeout" bash -c "$run_cmd"
	fi
}

# SWB CPLD cartridge identity (CPU). Gated by config/i2c_swb_bus.
# Registers match BMC Swb* offsets: MSB 0x10, rack/topo/tray/slot.
# Mux ownership is assumed already set (CPU); do not touch bmc_to_cpu_ctrl.
dump_cpld_swb_cartridge () {
	i2c_swb_bus_file="${HW_MGMT_FOLDER}/config/i2c_swb_bus"
	out="${DUMP_FOLDER}/cpld_swb_cartridge_dump"

	[ -f "$i2c_swb_bus_file" ] || return 0
	[ -x "$(command -v i2ctransfer)" ] || return 0

	swb_bus=$(cat "$i2c_swb_bus_file")
	case "$swb_bus" in
	''|*[!0-9]*)
		echo "invalid i2c_swb_bus='${swb_bus}'" > "$out"
		return 0
		;;
	esac

	timeout 10 sh -c '
		bus="$1"
		out="$2"
		{
			echo "i2c_swb_bus=${bus} addr=0x31"
			rack_hex=$(i2ctransfer -f -y "$bus" w2@0x31 0x10 0x00 r13)
			echo "rack_id: $rack_hex"
			printf "rack_id_ascii: "
			for tok in $rack_hex; do
				h=${tok#0x}
				c=$(printf "%d" "0x$h" 2>/dev/null) || c=0
				if [ "$c" -ge 32 ] && [ "$c" -le 126 ]; then
					printf "%b" "\\$(printf "%03o" "$c")"
				else
					printf "."
				fi
			done
			printf "\n"
			printf "topology_id: "
			i2ctransfer -f -y "$bus" w2@0x31 0x10 0x10 r1
			printf "tray_id: "
			i2ctransfer -f -y "$bus" w2@0x31 0x10 0x11 r1
			printf "slot_id: "
			i2ctransfer -f -y "$bus" w2@0x31 0x10 0x12 r1
		} > "$out" 2>&1
	' sh "$swb_bus" "$out"
}

rm -rf "$DUMP_FOLDER"
mkdir -p "$DUMP_FOLDER"

arch=$(uname -m)
if [ "$arch" = "aarch64" ]; then
	regmap_plat_path="/sys/kernel/debug/regmap/MLNXBF49:00"
	REGMAP_FILE="${REGMAP_FILE_ARM64}"
	CPLD_IOREG_RANGE=512
else
	regmap_plat_path="/sys/kernel/debug/regmap/mlxplat"
	CPLD_IOREG_RANGE=256
fi

dump_cmd "sensors" "sensors" "20"

# Use find to handle symlinks with special characters (exclude /sys/kernel/)
find /sys/ -path '/sys/kernel' -prune -o -ls > "$DUMP_FOLDER/sysfs_tree" 2>/dev/null || true

if [ -d "$HW_MGMT_FOLDER" ]; then
	timeout 140 find -L "$HW_MGMT_FOLDER" -maxdepth 4 ! -name '*_info' ! -name '*_eeprom'  ! -name '*.sh' ! -name '*.py' ! -name 'led_*_state' -exec ls -la {} \; -exec cat {} \; > "$DUMP_FOLDER/hw-management_val" 2>/dev/null
	timeout 80 find "$HW_MGMT_FOLDER/eeprom/" -type l -exec ls -la {} \; -exec hexdump -C {} \; > "$DUMP_FOLDER/hw-management_fru_dump" 2> /dev/null
fi

# Journal scope, one file: records of the hw-management units, the kernel log,
# and the syslog tags that hw-management scripts log under. Other services
# (sshd, sudo, pam, audit, ...) are not collected. The tags are read from the
# journal at dump time, the same way as the unit names.

# Writes the journal scope to the dump. Each term is a separate argument to
# journalctl and no shell parses them, so a unit name read from the journal
# cannot run commands. journalctl ORs the matches on each side of a "+".
# _SYSTEMD_UNIT: records the unit wrote. UNIT: systemd's own records about the
# unit (start, failure, stop).
dump_journal_scope()
{
	if [ ! -x "$(command -v journalctl)" ]; then
		return
	fi

	set -- "_TRANSPORT=kernel"
	for unit in $HW_MGMT_UNITS; do
		set -- "$@" "+" "_SYSTEMD_UNIT=$unit" "+" "UNIT=$unit"
	done
	for tag in $HW_MGMT_TAGS; do
		set -- "$@" "+" "SYSLOG_IDENTIFIER=$tag"
	done

	timeout 45 journalctl -o short-precise --no-pager "$@" > "$DUMP_FOLDER/hw-management-system-log" 2>&1
}

if [ -z "$MODE" ] || [ "$MODE" != "compact" ]; then
	# Unit names come from the journal and from the unit files on the system.
	# Only plain unit names are kept, so no shell metacharacter reaches the
	# journal call. The unit files cover a unit that failed before it logged
	# anything. The discovery is time limited; if it fails, the kernel records
	# and the units found in the unit files are still collected. The tagged
	# records need the journal discovery.
	HW_MGMT_UNITS=$( {
		timeout 10 journalctl -F _SYSTEMD_UNIT 2>/dev/null
		timeout 10 journalctl -F UNIT 2>/dev/null
		ls /usr/lib/systemd/system /lib/systemd/system /etc/systemd/system 2>/dev/null
	} | grep -E '^hw-management[A-Za-z0-9@._-]*$' | sort -u)
	# Syslog tags: hw-management scripts and daemons, the cartridge and VR
	# tools. Python daemons log under their file name, so both "-" and "_"
	# separators are matched. Only plain names are kept, as for the units.
	HW_MGMT_TAGS=$(timeout 10 journalctl -F SYSLOG_IDENTIFIER 2>/dev/null \
		| grep -E '^(hw[-_]manage|hw[-_]mgmt|cartridge_flash|vr_)[A-Za-z0-9@._-]*$' | sort -u)
	dump_journal_scope
	dump_cmd "journalctl --list-boots --no-pager" "boot-list" "5"
fi

[ -f /var/log/tc_log ] && cp /var/log/tc_* "$DUMP_FOLDER/" 2>/dev/null || true
[ -f /var/log/hw_management_sync_log ] && cp /var/log/hw_management_sync_log* "$DUMP_FOLDER/" 2>/dev/null || true
[ -f /var/log/chipup_i2c_trace_log ] && cp /var/log/chipup_i2c_trace_* "$DUMP_FOLDER/" 2>/dev/null || true
[ -f /var/log/udev_events.log ] && cp -a /var/log/udev* "$DUMP_FOLDER/" 2>/dev/null || true
[ -f /var/log/hw-mgmt.trace.log ] && cp -a /var/log/hw-mgmt.trace* "$DUMP_FOLDER/" 2>/dev/null || true
[ -f /var/log/hw_mgmt_cpldreg.log ] && cp /var/log/hw_mgmt_cpldreg.log "$DUMP_FOLDER/" 2>/dev/null || true
[ -f /var/log/hw-management-thermal-updater.log ] && cp /var/log/hw-management-thermal-updater.log* "$DUMP_FOLDER/" 2>/dev/null || true
[ -f /var/log/hw-management-peripheral-updater.log ] && cp /var/log/hw-management-peripheral-updater.log* "$DUMP_FOLDER/" 2>/dev/null || true
[ -f /var/log/hw-mgmt-i2c-trace.log ] && cp /var/log/hw-mgmt-i2c-trace.log* "$DUMP_FOLDER/" 2>/dev/null || true
uname -a > "$DUMP_FOLDER/sys_version"
mkdir "$DUMP_FOLDER/bin/"
cp /usr/bin/hw?management* "$DUMP_FOLDER/bin/" 2>/dev/null || true
cp /usr/local/bin/hw?management* "$DUMP_FOLDER/bin/" 2>/dev/null || true

cat /etc/os-release >> "$DUMP_FOLDER/sys_version"
cat /proc/interrupts > "$DUMP_FOLDER/interrupts"
case $board_type in
VMOD0014)
	if [ -f "/sys/kernel/debug/regmap/2-0041/registers" ]; then
		cat /sys/kernel/debug/regmap/2-0041/registers > "$DUMP_FOLDER/registers"
	fi
	if [ -f "/sys/kernel/debug/regmap/2-0041/access" ]; then
		cat /sys/kernel/debug/regmap/2-0041/access > "$DUMP_FOLDER/access"
	fi
	;;
*)
	if [ -f "${regmap_plat_path}/registers" ]; then
		cat "${regmap_plat_path}/registers" > "$DUMP_FOLDER/registers"
	fi

	if [ -f "${regmap_plat_path}/access" ]; then
		cat "${regmap_plat_path}/access" > "$DUMP_FOLDER/access"
	fi
	;;
esac

dump_cmd "iorw -b 0x2500 -r -l${CPLD_IOREG_RANGE}" "cpld_reg_direct_dump" "5"
# The kernel log of the current boot. The hw-management-system-log file has it too,
# for all boots, but it is not always there (compact mode, no journalctl), so dmesg
# is collected unless the no-dmesg option is given.
if [ "$COLLECT_DMESG" = "yes" ]; then
	dump_cmd "dmesg" "dmesg" "10"
fi
dump_cmd "dmidecode" "dmidecode" "5"
dump_cmd "lsmod" "lsmod" "3"
dump_cmd "lspci -vvv" "lspci" "5"
dump_cmd "top -SHb -n 1 | tail -n +8 | sort -nrk 11" "top" "5"
dump_cmd "iio_info" "iio_info" "5"
dump_cmd "cat ${REGMAP_FILE} 2>/dev/null" "cpld_dump" "5"
dump_cmd "dpkg -l | grep hw-management" "hw-management_version" "5"
dump_cmd "systemctl status hw-management* --no-pager" "hw-management_svc_status" "5"
dump_cmd "ip addr" "ip_addr" "5"
dump_cmd "sx_sdk --version" "sx_sdk_ver" "5"
dump_cpld_swb_cartridge

# SSD vendor dump. Recreate $SSD_LOG_DIR; copy as ssd-dump/,
# then remove $SSD_LOG_DIR (Python --no-tar; no nested gzip).
# Extra logic is in hw-management-ssd-dump-collect.sh (dump_cmd).
# 380 = up to 120 s waiting for a standalone SSD dump to finish
# (this dump has priority, so the helper waits instead of
# giving up) + 25 for reusing that dump and failing + 195+5 for
# the collect that then has to happen + 25 to copy or unpack.
# The helper bounds each of those itself, so reaching this
# timeout means it was wedged, not merely slow.
dump_cmd "hw-management-ssd-dump-collect.sh $DUMP_FOLDER $SSD_LOG_DIR" \
	"ssd-dump-collect.log" "380"

# Kill all the leftout child processes before creating the dump archive
pkill -P "$dump_process_pid" 2>/dev/null || true

tar -cf /tmp/hw-mgmt-dump.tar.gz -I 'gzip -9' -C "$DUMP_FOLDER" .
rm -rf "$DUMP_FOLDER"
