#!/bin/sh
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2020-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# Description: hw-management watchdog actions script.
#              It uses direct access to CPLD watchdog mechanism. 
#              1. Start watchdog to provided timeout or default timeout.
#              2. Stop watchdog.
#              3. Check if previous reset was caused by watchdog.
#              4. Check watchdog timeleft.

CPLD_LPC_BASE=0x2500
CPLD_LPC_CPBLT_REG=0xf9
CPLD_LPC_RESET_CAUSE_REG=0x1d
CPLD_LPC_WD2_TMR_REG=0xcd
CPLD_LPC_WD2_ACT_REG=0xcf
CPLD_LPC_WD_CPBLT_BIT=6
CPLD_LPC_WD_RESET_CAUSE_BIT=6
CPLD_LPC_WD_RESET=1
WD3_DFLT_TO=600
WD_TYPE3_MAX_TO=65535

wd_max_to=
wd_act_reg=
wd_tmr_reg=
wd_tleft_reg=
wd_tmr_reg_len=
wd_to=

action=$1
param_num=$#

usage()
{
	echo "Usage: $(basename "$0") start [timeout] | stop | tleft | check_reset | help"
        echo "start - start watchdog"
	echo "        timeout is optional. Default value will be used in case if it's omitted"
        echo "        timeout provided in seconds"
        echo "stop - stop watchdog"
        echo "tleft - check watchdog timeout left"
        echo "check_reset - check if previous reset was caused by watchdog"
	echo "        Prints only in case of watchdog reset"
        echo "help -this help"
}

check_watchdog_type()
{
	reg=$((CPLD_LPC_BASE+CPLD_LPC_CPBLT_REG))
	wd_cpblt=$(iorw -r -b $reg -l 1 | awk '{print $5}')
	wd_cpblt=$((wd_cpblt>>=CPLD_LPC_WD_CPBLT_BIT))
	wd_cpblt=$((wd_cpblt&=1))

	if [ $wd_cpblt -eq 0 ]; then
		wd_type=3
		wd_to=$WD3_DFLT_TO
		wd_max_to=$WD_TYPE3_MAX_TO
		wd_act_reg=$CPLD_LPC_WD2_ACT_REG
		wd_tmr_reg=$CPLD_LPC_WD2_TMR_REG
		wd_tleft_reg=$CPLD_LPC_WD2_TMR_REG
		wd_tmr_reg_len=2
	else
		board=$(cat /sys/devices/virtual/dmi/id/board_name)
		case $board in
			VMOD0001|VMOD0003)
				wd_type=1
				;;
			*)
				wd_type=2
				;;
		esac
		echo "Watchdog type ${wd_type} isn't supported by this script."
		exit 1
	fi
}

check_watchdog_timeout()
{
	if [ $param_num -ge 2 ]; then
		wd_to=$2
	fi
	if [ $wd_to -gt $wd_max_to ]; then
		echo "Error: Watchdog timeout ${wd_to} exceeds max timeout ${wd_max_to}"
		exit 1
	fi
}

start_watchdog()
{
	reg=$((CPLD_LPC_BASE+wd_tmr_reg))
	iorw -w -b $reg -v $wd_to -l $wd_tmr_reg_len
	reg=$((CPLD_LPC_BASE+wd_act_reg))
	val=$CPLD_LPC_WD_RESET
	iorw -w -b $reg -v $val -l 1
	echo "Watchdog is started, timeout ${wd_to} sec."
}

stop_watchdog()
{
	reg=$((CPLD_LPC_BASE+wd_act_reg))
	iorw -w -b $reg -v 0 -l 1
	reg=$((CPLD_LPC_BASE+wd_tmr_reg))
	iorw -w -b $reg -v 0 -l 1
	reg=$((reg+1))
	iorw -w -b $reg -v 0 -l 1
	echo "Watchdog is stopped"
}

time_left()
{
	reg=$((CPLD_LPC_BASE+wd_tleft_reg))
	val=$(iorw -r -b $reg -l 2 | awk '{print $3 $2}')
	val=$(printf "0x%s" ${val})
	printf "Watchdog timeleft: %d sec.\n" ${val}
}

check_reset()
{
	reg=$((CPLD_LPC_BASE+CPLD_LPC_RESET_CAUSE_REG))
	val=$(iorw -r -b $reg -l 1 | awk '{print $5}')
	val=$((val>>=CPLD_LPC_WD_RESET_CAUSE_BIT))
	val=$((val&=1))
	if [ $val -eq 1 ]; then
		echo "Watchdog was caused reset in previous boot"
	fi
}

check_watchdog_type

case $action in
	start)
		check_watchdog_timeout "$@"
		start_watchdog
		;;
	stop)
		stop_watchdog
		;;
	tleft)
		time_left
		;;
	check_reset)
		check_reset
		;;
	help)
		usage
		;;
	*)
		usage
		exit 1
		;;
esac

exit 0
