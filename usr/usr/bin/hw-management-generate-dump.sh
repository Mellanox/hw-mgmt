#!/bin/sh
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2020-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# Description: hw-management generate dump script.
#              This script collecting debug information and pack it in /tmp/hw-mgmt-dump.tar.gz

DUMP_FOLDER="/tmp/hw-mgmt-dump"
HW_MGMT_FOLDER="/var/run/hw-management/"
board_type=$(cat /sys/devices/virtual/dmi/id/board_name 2>/dev/null || echo "")
REGMAP_FILE="/sys/kernel/debug/regmap/mlxplat/registers"
REGMAP_FILE_ARM64="/sys/kernel/debug/regmap/MLNXBF49:00/registers"
CPLD_IOREG_RANGE=256
dump_process_pid=$$

MODE=$1

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

if [ -z "$MODE" ] || [ "$MODE" != "compact" ]; then
	dump_cmd "journalctl -o short-precise --no-pager" "journalctl" "45"
	dump_cmd "sx_sdk --version" "sx_sdk_ver" "10"
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
dump_cmd "dmesg" "dmesg" "10"
dump_cmd "dmidecode" "dmidecode" "5"
dump_cmd "lsmod" "lsmod" "3"
dump_cmd "lspci -vvv" "lspci" "5"
dump_cmd "top -SHb -n 1 | tail -n +8 | sort -nrk 11" "top" "5"
dump_cmd "iio_info" "iio_info" "5"
dump_cmd "cat ${REGMAP_FILE} 2>/dev/null" "cpld_dump" "5"
dump_cmd "dpkg -l | grep hw-management" "hw-management_version" "5"
dump_cmd "systemctl status hw-management* --no-pager" "hw-management_svc_status" "5"
dump_cmd "ip addr" "ip_addr" "5"
dump_cpld_swb_cartridge

# Kill all the leftout child processes before creating the dump archive
pkill -P "$dump_process_pid" 2>/dev/null || true

tar -cf /tmp/hw-mgmt-dump.tar.gz -I 'gzip -9' -C "$DUMP_FOLDER" .
rm -rf "$DUMP_FOLDER"
