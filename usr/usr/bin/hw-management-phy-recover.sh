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
# Sequence: write 0, wait 120 ms, then write 1 unless the CPLD released the bit
# by itself (HW-pulsed bits).
# Exit codes: 0 reset done, 1 bad arguments, 2 no reset attribute for this port,
# 3 reset failed (sysfs error or timeout, bit stuck at 0, or interrupted),
# 4 hw-management not ready.

source /usr/bin/hw-management-helpers.sh

HW_MGMT="$hw_management_path/system"
ASSERT_WIDTH=0.12	# reset assert width, longer than the longest CPLD pulse (100 ms)
READBACK_RETRIES=5	# extra readbacks while the bit is still 0
READBACK_POLL=0.02
SYSFS_TIMEOUT=5		# bound hung sysfs I/O
DUMP_TIMEOUT=5		# bound hung ethtool
READY_TIMEOUT=30	# wait for the hw-management service
READY_POLL=0.2
RESET_PATH=""		# for the trap handlers, which take no arguments

EXIT_RESET_DONE=0
EXIT_BAD_ARGUMENTS=1
EXIT_NO_RESET_ATTRIBUTE=2	# nothing was written
EXIT_RESET_FAILED=3		# sysfs error or timeout, bit stuck at 0, or interrupted
EXIT_HW_MGMT_NOT_READY=4	# nothing was written

RESET_ASSERTED=0	# the PHY is held in reset
RESET_RELEASED=1	# normal state

# CPU driver names only. Do not use BMC cpld_phy*.
declare -A PORT_ATTRS=(
	[eth0]="sgmii_phy2_reset"
	[eth1]="sgmii_phy_reset"
)

usage()
{
	echo "Usage: $(basename "$0") [-d|--dump-phy] <eth0|eth1>" >&2
}

sysfs_write()
{
	timeout "$SYSFS_TIMEOUT" sh -c "echo $2 > '$1'" 2>/dev/null
}

sysfs_read()
{
	timeout "$SYSFS_TIMEOUT" cat "$1" 2>/dev/null
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
	exit "$EXIT_HW_MGMT_NOT_READY"
}

resolve_attr()
{
	local port=$1 name=${PORT_ATTRS[$port]}

	if [ -e "$HW_MGMT/$name" ]; then
		echo "$name"
		return "$EXIT_RESET_DONE"
	fi
	log_err "PHY recovery: no reset attribute for $port"
	return "$EXIT_NO_RESET_ATTRIBUTE"
}

# One line per snapshot: the PHY id, the driver and the link state. It goes to
# /var/log/hw-mgmt.trace.log through the helpers trace function.
snapshot_phy()
{
	local port=$1 tag=$2 phydev="/sys/class/net/$port/phydev" id=absent drv=absent link

	if [ -e "$phydev" ]; then
		id=$(cat "$phydev/phy_id" 2>/dev/null)
		drv=$(basename "$(readlink "$phydev/driver" 2>/dev/null)")
	fi
	link=$(timeout "$DUMP_TIMEOUT" ethtool "$port" 2>/dev/null | awk -F': ' '/Link detected/ {print $2}')
	if type print_function_call >/dev/null 2>&1; then
		print_function_call "$0" "phy_snapshot" "port=$port tag=$tag phy_id=$id driver=${drv:-unknown} link=${link:-unknown}" 2>/dev/null
	else
		log_info "PHY recovery: snapshot port=$port tag=$tag phy_id=$id driver=${drv:-unknown} link=${link:-unknown}"
	fi
}

release()
{
	sysfs_write "$RESET_PATH" "$RESET_RELEASED"
}

# INT or TERM during the sequence: release the bit, then report a failed reset.
interrupted()
{
	trap - EXIT
	if release; then
		log_err "PHY recovery: interrupted, $RESET_PATH released"
	else
		log_err "PHY recovery: interrupted, release of $RESET_PATH failed"
	fi
	exit "$EXIT_RESET_FAILED"
}

# The same attribute is a CPLD-pulsed bit on one board and a level bit on
# another (N51XX_LD: eth0 pulsed, eth1 level; N6100_LD: the opposite). One
# logic serves all: write 0, wait, read back. A pulsed bit is back at 1 and
# is done. A level bit is still 0: write 1 to release it.
write_bit()
{
	sysfs_write "$1" "$2" && return "$EXIT_RESET_DONE"
	log_err "PHY recovery: write to $1 failed or timed out"
	return "$EXIT_RESET_FAILED"
}

read_bit()
{
	local val

	val=$(sysfs_read "$1") && echo "$val" && return "$EXIT_RESET_DONE"
	log_err "PHY recovery: read of $1 failed or timed out"
	return "$EXIT_RESET_FAILED"
}

reset_bit()
{
	local path=$1 val i

	write_bit "$path" "$RESET_ASSERTED" || return "$EXIT_RESET_FAILED"
	sleep "$ASSERT_WIDTH"
	val=$(read_bit "$path") || return "$EXIT_RESET_FAILED"
	if [ "$val" = "$RESET_ASSERTED" ]; then	# level bit: the CPLD keeps it asserted until we release it
		write_bit "$path" "$RESET_RELEASED" || return "$EXIT_RESET_FAILED"
	fi
	for i in $(seq 0 "$READBACK_RETRIES"); do	# confirm the release, a slow CPLD may need a few reads
		val=$(read_bit "$path") || return "$EXIT_RESET_FAILED"
		if [ "$val" = "$RESET_RELEASED" ]; then
			return "$EXIT_RESET_DONE"
		fi
		sleep "$READBACK_POLL"
	done
	log_err "PHY recovery: $path stuck asserted after release"
	return "$EXIT_RESET_FAILED"
}

# Run the reset sequence with the bit guarded: a kill or any other exit
# releases the bit, so the PHY never stays in reset.
guarded_reset()
{
	local rc

	RESET_PATH=$1
	trap interrupted INT TERM
	trap release EXIT
	reset_bit "$1"
	rc=$?
	[ "$rc" -eq "$EXIT_RESET_DONE" ] || release	# best effort after a failure
	trap - EXIT INT TERM
	return "$rc"
}

main()
{
	local dump_opt=0 opt port name path rc

	set -- "${@/--dump-phy/-d}"
	while getopts "d" opt; do
		case $opt in
			d) dump_opt=1 ;;
			*) usage; exit "$EXIT_BAD_ARGUMENTS" ;;
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
	name=$(resolve_attr "$port") || exit "$EXIT_NO_RESET_ATTRIBUTE"
	path="$HW_MGMT/$name"
	[ "$dump_opt" -eq 1 ] && snapshot_phy "$port" before
	log_info "PHY recovery: resetting $port via $name"
	guarded_reset "$path"
	rc=$?
	[ "$dump_opt" -eq 1 ] && snapshot_phy "$port" after
	[ "$rc" -eq "$EXIT_RESET_DONE" ] && log_info "PHY recovery: $port reset done"
	exit "$rc"
}

main "$@"
