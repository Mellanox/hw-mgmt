#!/bin/bash
###########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
# hw-management-phy-recover.sh [-d|--dump-phy] <port>
# Pulse the CPLD PHY reset for one CPU management port.
# Requires hw-management init: the hw-management service must be active. Its
# start creates the links under /var/run/hw-management/system before it returns.
# ComE / eth0 (HW-pulsed 50 ms): write 0. MGMT / eth1 (not pulsed): write 0, wait 50 ms, write 1.
# Exit codes: 0 reset done, 1 usage, 2 no reset attribute for this port,
# 3 sysfs timeout, bit stuck asserted or interrupted (bit released), 4 hw-management not ready.

source /usr/bin/hw-management-helpers.sh

HW_MGMT="$hw_management_path/system"
DUMP_DIR="/var/log/hw-mgmt-phy-recover"
COME_PULSE=0.05		# HW pulse width after ComE write 0
MGMT_WIDTH=0.05		# SW assert width for non-pulsed (MGMT) bits
READBACK_RETRIES=5	# extra readbacks while the bit is still 0
READBACK_POLL=0.02
PULSE_TIMEOUT=5		# bound hung sysfs I/O
DUMP_TIMEOUT=5		# bound hung ethtool
READY_TIMEOUT=30	# wait for the hw-management service
READY_POLL=0.2
DUMP_KEEP=10		# snapshots kept per port
PULSE_PATH=""

# CPU driver names only. Do not use BMC cpld_phy*.
declare -A PORT_ATTRS=(
	[eth0]="sgmii_phy2_reset"	# ComE (mlx-platform l1_scale_out)
	[eth1]="sgmii_phy_reset"	# MGMT (mlx-platform l1_scale_out)
)
# ComE / S_CPLD_PHY_RESET_L / 0x2517.5: the CPLD makes the 50 ms pulse on write 0.
COME_ATTRS="sgmii_phy2_reset"

usage()
{
	echo "Usage: $(basename "$0") [-d|--dump-phy] <eth0|eth1>" >&2
}

sysfs_write()
{
	timeout "$PULSE_TIMEOUT" sh -c "echo $2 > '$1'" 2>/dev/null
}

sysfs_read()
{
	timeout "$PULSE_TIMEOUT" cat "$1" 2>/dev/null
}

hw_mgmt_active()
{
	systemctl is-active --quiet hw-management
}

wait_hw_mgmt_ready()
{
	local deadline=$((SECONDS + READY_TIMEOUT))

	while [ "$SECONDS" -lt "$deadline" ]; do
		hw_mgmt_active && return 0
		sleep "$READY_POLL"
	done
	log_err "PHY recovery: hw-management not ready (service not active)"
	exit 4
}

resolve_attr()
{
	local port=$1 name

	for name in ${PORT_ATTRS[$port]}; do
		if [ -e "$HW_MGMT/$name" ]; then
			echo "$name"
			return 0
		fi
	done
	log_err "PHY recovery: no reset attribute for $port"
	return 2
}

pulse_type()
{
	local name

	for name in $COME_ATTRS; do
		[ "$name" = "$1" ] && { echo "come"; return; }
	done
	echo "mgmt"
}

dump_phy()
{
	local port=$1 tag=$2 out phydev="/sys/class/net/$port/phydev"

	mkdir -p "$DUMP_DIR" 2>/dev/null || return 0
	out="$DUMP_DIR/$port-$(date +%Y%m%d-%H%M%S)-$$-$tag.txt"
	{
		echo "tag=$tag port=$port"
		if [ -e "$phydev" ]; then
			echo "phy_id=$(cat "$phydev/phy_id" 2>/dev/null)"
			echo "driver=$(readlink "$phydev/driver" 2>/dev/null)"
		else
			echo "phydev absent (get_phy_device failed or not attached)"
		fi
		timeout "$DUMP_TIMEOUT" ethtool "$port" 2>&1
		echo "snapshot complete"	# last write sets the group status
	} 2>/dev/null > "$out" || { log_err "PHY recovery: snapshot $port $tag not saved ($out)"; return 0; }
	log_info "PHY recovery: snapshot $port $tag saved to $out"
	ls -1t "$DUMP_DIR/$port-"*.txt 2>/dev/null | tail -n +$((DUMP_KEEP + 1)) | xargs -r rm -f
}

release()
{
	sysfs_write "$PULSE_PATH" 1
}

interrupted()
{
	trap - EXIT
	if release; then
		log_err "PHY recovery: interrupted, $PULSE_PATH released"
	else
		log_err "PHY recovery: interrupted, release of $PULSE_PATH failed"
	fi
	exit 3
}

do_pulse()
{
	local path=$1 ptype=$2 val="" i

	if ! sysfs_write "$path" 0; then
		log_err "PHY recovery: write to $path failed or timed out"
		return 3
	fi
	if [ "$ptype" = "come" ]; then
		sleep "$COME_PULSE"
	else
		sleep "$MGMT_WIDTH"
		if ! sysfs_write "$path" 1; then
			log_err "PHY recovery: write to $path failed or timed out"
			return 3
		fi
	fi
	for i in $(seq 0 "$READBACK_RETRIES"); do
		if ! val=$(sysfs_read "$path"); then
			log_err "PHY recovery: read of $path failed or timed out"
			return 3
		fi
		[ "$val" = "1" ] && return 0
		sleep "$READBACK_POLL"
	done
	log_err "PHY recovery: $path stuck asserted after release"
	return 3
}

pulse()
{
	local rc

	PULSE_PATH=$1
	trap interrupted INT TERM
	trap release EXIT
	do_pulse "$1" "$2"
	rc=$?
	[ "$rc" -eq 0 ] || release
	trap - EXIT INT TERM
	return "$rc"
}

main()
{
	local dump_opt=0 opt port name path ptype rc

	set -- "${@/--dump-phy/-d}"
	while getopts "d" opt; do
		case $opt in
			d) dump_opt=1 ;;
			*) usage; exit 1 ;;
		esac
	done
	shift $((OPTIND - 1))
	port=$1
	if [ $# -ne 1 ] || [ -z "$port" ] || [ -z "${PORT_ATTRS[$port]+x}" ]; then
		log_err "PHY recovery: unknown port ${port:-(none)}"
		usage
		exit 1
	fi

	wait_hw_mgmt_ready
	name=$(resolve_attr "$port") || exit 2
	path="$HW_MGMT/$name"
	ptype=$(pulse_type "$name")
	[ "$dump_opt" -eq 1 ] && dump_phy "$port" before
	log_info "PHY recovery: pulsing $port via $name ($ptype)"
	pulse "$path" "$ptype"
	rc=$?
	[ "$dump_opt" -eq 1 ] && dump_phy "$port" after
	[ "$rc" -eq 0 ] && log_info "PHY recovery: $port pulse complete ($ptype)"
	exit "$rc"
}

main "$@"
