#!/bin/bash
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2018-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

tmp=$0
LED_STATE=none
FNAME=$(basename "$tmp")
DNAME=$(dirname "$tmp")
LED_NAME=$(echo "$FNAME" | cut -d_ -f1-2)
FNAMES=($(ls "$DNAME"/"$LED_NAME"*))

check_led_blink()
{
	if [ -e "$DNAME"/"$LED_NAME"_"$COLOR"_delay_on ]; then
		val1=$(< "$DNAME"/"$LED_NAME"_"$COLOR"_delay_on)
	else
		val1=0
	fi
	if [ -e "$DNAME"/"$LED_NAME"_"$COLOR"_delay_off ]; then
		val2=$(< "$DNAME"/"$LED_NAME"_"$COLOR"_delay_off)
	else
		val2=0
	fi
	if [ -e "$DNAME"/"$LED_NAME"_"$COLOR" ]; then
		val3=$(< "$DNAME"/"$LED_NAME"_"$COLOR")
	else
		val3=0
	fi
	if [ "${val1}" != "0" ] && [ "${val2}" != "0" ] && [ "${val3}" != "0" ] ; then
		LED_STATE="$COLOR"_blink
		return 1
	fi
	return 0
}

for CURR_FILE in "${FNAMES[@]}"
do
	if echo "$CURR_FILE" | (grep -q '_state\|_capability') ; then
		continue
	fi
	COLOR=$(echo "$CURR_FILE" | cut -d_ -f3)
	if [ -z "${COLOR}" ] ; then
		continue
	fi
	if echo "$CURR_FILE" | grep -q "_delay" ; then
		check_led_blink "$COLOR"
		if [ $? -eq 1 ]; then
			break;
		fi
	fi
	if [ "${CURR_FILE}" == "$DNAME"/"${LED_NAME}_${COLOR}" ] ; then
		if [ -e "$DNAME"/"$LED_NAME"_"$COLOR" ]; then 
			val1=$(< "$DNAME"/"$LED_NAME"_"$COLOR")
		else
			val1=0
		fi
		if [ "${val1}" != "0" ]; then
			check_led_blink "$COLOR"
			if [ $? -eq 1 ]; then
				break;
			else
				LED_STATE="$COLOR"
				break;
			fi
		fi
	fi
done

echo "${LED_STATE}" > "$DNAME"/"$LED_NAME"
exit 0

