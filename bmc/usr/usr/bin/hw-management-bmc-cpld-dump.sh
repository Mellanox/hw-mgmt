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
#    documentation and/or materials provided with the distribution.
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
# SUBSTITUTE GOODS OR SERVICES; LOSS OF DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
################################################################################
# CPLD register dump for SONiC BMC. Merged from OpenBMC meta-switch:
#   recipes-phosphor/dump/files/cpld_dump.sh
#   recipes-phosphor/dump/files/dump_utils.sh (take_cpld_dump_internal, take_cpld_dump)
# Platform bus: HW_MANAGEMENT_BMC_PLATFORM_CONF or /etc/hw-management-bmc-platform.conf
################################################################################

export LOG_TAG="hw-management-bmc-cpld-dump"
# shellcheck source=/dev/null
source /usr/bin/hw-management-bmc-helpers-common.sh

help()
{
	echo "Usage: hw-management-bmc-cpld-dump.sh [-h] -p <file_path> -i <dump_id>"
	echo ""
	echo "Options:"
	echo "          -h  shows this help"
	echo "          -p  (required) path to put compressed dump to"
	echo "          -i  file dump id, default $ARG_DUMP_ID"
}

initialize()
{
	F_NAME_TEMPLATE="obmcdump_${ARG_DUMP_ID}_${EPOCHTIME}"
	TMP_DIR_PATH="${TMP_DIR}/${F_NAME_TEMPLATE}"
	OUTPUT_ARCHIVE_PATH="${TMP_DIR}/${F_NAME_TEMPLATE}.tar.xz"

	mkdir -p "$ARG_DUMP_PATH"
	if [ $? -ne 0 ]; then
		log_message err "Failed to create destination directory $ARG_DUMP_PATH"
		exit 1
	fi
	log_message info "Created dest dir $ARG_DUMP_PATH"

	mkdir -p "$TMP_DIR_PATH"
	if [ $? -ne 0 ]; then
		log_message err "Failed to create temp work directory $TMP_DIR_PATH"
		exit 1
	fi
	log_message info "Created tmp work dir $TMP_DIR_PATH"
}

cleanup()
{
	local res_ret=0

	if [ -e "$TMP_DIR_PATH" ]; then
		rm -rf "$TMP_DIR_PATH"
		if [ $? -ne 0 ]; then
			log_message err "Cannot remove $TMP_DIR_PATH"
			res_ret=1
		fi
	fi

	if [ -e "$OUTPUT_ARCHIVE_PATH" ]; then
		rm -f "$OUTPUT_ARCHIVE_PATH"
		if [ $? -ne 0 ]; then
			log_message err "Cannot remove $OUTPUT_ARCHIVE_PATH"
			res_ret=1
		fi
	fi

	return "$res_ret"
}

# Hex grid dump to stdout (archive content; not sent to syslog).
take_cpld_dump_internal()
{
	echo -n "Offset "
	for col in {0..15}; do
		printf "%02x " "$col"
	done
	echo

	if [ -f "$PLATFORM_CONFIG_FILE" ]; then
		# shellcheck source=/dev/null
		source "$PLATFORM_CONFIG_FILE"
	else
		CPLD_I2C_BUS=5
	fi

	for ((row = 0; row <= 240; row += 16)); do
		printf "0x%02x:  " "$row"

		for ((col = 0; col < 16; col++)); do
			offset=$((row + col))
			hex_offset=$(printf "%02x" "$offset")

			raw_output=$(i2ctransfer -f -y "$CPLD_I2C_BUS" w2@0x31 0x25 "0x${hex_offset}" r1 2>/dev/null)
			byte=$(echo "$raw_output" | awk 'match($0, /0x[0-9a-fA-F]{2}/) {print substr($0, RSTART+2, 2)}')

			if [[ $byte =~ ^[0-9a-fA-F]{2}$ ]]; then
				printf "%02x " "0x$byte" | tr '[:upper:]' '[:lower:]'
			elif [[ $byte == "ER" ]]; then
				printf "ER "
			elif [[ $byte == "NA" ]]; then
				printf "NA "
			else
				printf '%s' '-- '
			fi
		done
		echo
	done
}

# output_path: destination directory or file; OpenBMC "add_copy_file" is not supported here.
take_cpld_dump()
{
	local output_path=$1

	log_message info "Starting CPLD data collection..."

	local tmp_log
	tmp_log=$(mktemp /tmp/cpld_dump.XXXXXX.log)
	local _my_script="${BASH_SOURCE[0]}"

	if [ "1${output_path}" = "1add_copy_file" ]; then
		log_message err "output mode add_copy_file is not supported (Phosphor dump integration only)"
		rm -f "$tmp_log"
		return 1
	fi

	if ! timeout 20s bash -c ". $(printf '%q' "$_my_script"); take_cpld_dump_internal" >"$tmp_log" 2>&1; then
		log_message warning "CPLD dump command timed out or returned non-zero (partial data may be in temp file)"
	fi

	if [ -d "$output_path" ]; then
		cp -f "$tmp_log" "${output_path}/cpld_dump.log"
	else
		cp -f "$tmp_log" "$output_path"
	fi

	rm -f "$tmp_log"
	log_message info "CPLD data collection completed"
}

run_dump_main()
{
	take_cpld_dump "$TMP_DIR_PATH"

	tar -Jcf "$OUTPUT_ARCHIVE_PATH" -C "$(dirname "$TMP_DIR_PATH")" \
		"$(basename "$TMP_DIR_PATH")"

	if [ $? -ne 0 ]; then
		log_message err "Compression $OUTPUT_ARCHIVE_PATH failed"
		return 1
	fi

	cp "$OUTPUT_ARCHIVE_PATH" "$ARG_DUMP_PATH"
	if [ $? -ne 0 ]; then
		log_message err "Failed to copy $OUTPUT_ARCHIVE_PATH to $ARG_DUMP_PATH"
		return 1
	fi

	return 0
}

# When sourced (e.g. timeout bash -c '. thisscript; take_cpld_dump_internal'), run CLI below only if executed as the main program.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
	return 0
fi

TMP_DIR="/tmp"
EPOCHTIME=$(date +"%s")
F_NAME_TEMPLATE=""
TMP_DIR_PATH=""
OUTPUT_ARCHIVE_PATH=""

ARG_DUMP_ID="00000000"
ARG_DUMP_PATH=""

WRONG_OPT=0

while getopts ":hDp:i:" option; do
	case $option in
	h)
		help
		exit 0
		;;
	p)
		ARG_DUMP_PATH=$OPTARG
		;;
	i)
		ARG_DUMP_ID=$OPTARG
		;;
	\?)
		log_message err "Invalid option: -$OPTARG"
		help
		exit 1
		;;
	:)
		log_message err "Missing option argument for -$OPTARG"
		exit 1
		;;
	*)
		log_message err "Unimplemented option: -$OPTARG"
		exit 1
		;;
	esac
done

if [ "$OPTIND" -eq 1 ]; then
	log_message err "No options were passed"
	WRONG_OPT=1
fi

if [ -z "$ARG_DUMP_PATH" ]; then
	log_message err "argument -p is required"
	WRONG_OPT=1
fi

if [ "$WRONG_OPT" -ne 0 ]; then
	help
	exit 1
fi

initialize
if [ $? -ne 0 ]; then
	log_message err "Init failed"
	exit 1
fi

run_dump_main
if [ $? -ne 0 ]; then
	log_message err "Dump failed"
	cleanup
	exit 1
fi

cleanup
if [ $? -ne 0 ]; then
	log_message err "Cleanup failed"
	exit 1
fi

exit 0
