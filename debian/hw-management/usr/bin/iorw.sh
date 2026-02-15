#!/bin/sh
################################################################################
# Copyright (c) 2022-2023, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# Regmap files in debugfs
REGMAP_REGISTERS=/sys/kernel/debug/regmap/MLNXBF49:00/registers
REGMAP_RANGE=/sys/kernel/debug/regmap/MLNXBF49:00/range

# Operation codes
NO_OP=0
RD_OP=1
WR_OP=2

# Print help message
usage()
{
	echo "$(basename $0) [-r] [-w] [-o <offset>] [-l <length>] [-v <value>] [-f <filename>] [-q] [-h]"
	echo "-r - perform read operation"
	echo "-w - perform write operation"
	echo "-b - base, for compatibility with X86 version, should be at least 0x2500, can be omitted"
	echo "-o - offset, can be omitted, default is 0"
	echo "-l - number of registers to read/write; can be omitted only for read - full dump in this case"
	echo "-v - value for write operation"
	echo "-f - file to store output values"
	echo "-q - quiet, when used with -f option, store output in file without printing to terminal"
	echo "-h - display this help"
	echo
	echo "Note: Hexadecimal values of base, offset, length and value should be prefixed with 0x"
	echo
	echo "Examples:"
	echo "Read all registers"
	echo "   $(basename $0) -r"
	echo "Read all registers starting at offset 0x10"
	echo "   $(basename $0) -r -o 0x10"
	echo "Read 20 registers starting at offset 0x10"
	echo "   $(basename $0) -r -o 0x10 -l 20"
	echo "Write 0x06 at offset 0x10"
	echo "   $(basename $0) -w -o 0x10 -v 0x06 -l 1"
	echo "Write 0x01, 0x02 and 0x03 at offsets 0x10, 0x11 and 0x12"
	echo "   $(basename $0) -w -o 0x10 -v 0x01:0x02:0x03 -l 3"
}

# Get first register in regmap
get_regmap_first_reg()
{
	printf "%d" 0x$(cut -d- -f1 ${REGMAP_RANGE})
}

# Get last register in regmap
get_regmap_last_reg()
{
	printf "%d" 0x$(cut -d- -f2 ${REGMAP_RANGE})
}

# Get number of registers in regmap
get_regmap_size()
{
	local first=$(get_regmap_first_reg)
	local last=$(get_regmap_last_reg)

	printf "%d" $((last-first+1))
}

# Get regmap register size in bytes
get_regmap_reg_size()
{
	local nibbles=$(head -n 1 ${REGMAP_REGISTERS} | cut -d" " -f2 | tr -d "[:space:]" | wc -c)

	printf "%d" $((nibbles/2))
}

# Get maximum possible value of regmap register
get_regmap_max_reg_val()
{
	local bytes=$(get_regmap_reg_size)
	local bits=$((bytes*8))

	# Use left shift to calculate power of 2
	printf "%d" $(((1<<bits)-1))
}

# Check regmap range validity
# @off - offset of first register - decimal
# @len - number of registers - decimal
valid_range()
{
	local off=$1
	local len=$2

	# Get first and last registers in regmap
	local map_first=$(get_regmap_first_reg)
	local map_last=$(get_regmap_last_reg)

	# Get first and last registers in range
	local range_first=${off}
	local range_last=$((off+len-1))

	# Check if range is valid
	if [ ${range_first} -ge ${map_first} ] && [ ${range_last} -le ${map_last} ]; then
		return 0
	fi

	return 1
}

# Check validity of value to be written
# @val - value to be written - decimal or hexadecimal
# Assumptions:
#   1. Hexadecimal value is prefixed with 0x
#   3. Global variable 'max_reg_val' holds maximum register value
valid_write_val()
{
	local val=$1

	# Check that value is a valid number and convert it to decimal
	val=$(printf "%d" ${val} 2>/dev/null)
	if [ $? -ne 0 ]; then
		return 1
	fi

	# Check that value does not exceed the maximum register value
	if [ ${val} -le ${max_reg_val} ]; then
		return 0
	fi

	return 1
}

# Printf wrapper to handle output to file and terminal
# Assumptions:
#   1. Global variable 'file' holds the output file name
#   1. Global variable 'quiet' controls output to terminal
do_print()
{
	if [ ! -z "${file}" ]; then
		if [ ${quiet} -eq 1 ]; then
			printf "$@" >> ${file}
		else
			printf "$@" | tee -a ${file}
		fi
	else
		printf "$@"
	fi
}

# Print register values to file and/or terminal
# @off - offset of first register - decimal
# @len - number of registers - decimal
# Assumptions:
#   1. Global variable 'data' holds register values
#   2. Global variable 'file' holds log file name
#   3. Parameter 'len' matches the number of values in 'data'
#   4. Number of registers in regmap does not exceed 1024
io_print_data()
{
	local off=$1
	local len=$2

	# Remove existing log file
	if [ ! -z "${file}" ] && [ -f "${file}" ]; then
		rm -f ${file}
	fi

	# Handle single register value
	if [ ${len} -eq 1 ]; then
		do_print "IO reg 0x%04x = 0x%02x\n" ${off} 0x${data}
		return
	fi

	# Handle multiple register values
	local i=0
	for val in ${data}; do
		if [ $((i % 16)) -eq 0 ]; then
			if [ ${i} -eq 0 ]; then
				do_print "%04x: %02x " ${off} 0x${val}
			else
				do_print "\n%04x: %02x " ${off} 0x${val}
			fi
		else
			do_print "%02x " 0x${val}
		fi
		off=$((off+1))
		i=$((i+1))
	done
	do_print "\n"
}

# Read regmap register range
# @off - offset of the first register - decimal
# @len - number of registers to read  - decimal
# Assumptions:
#   1. Global variable 'data' holds register values
io_read()
{
	local off=$1
	local len=$2

	data=$(tail -n +$((off+1)) ${REGMAP_REGISTERS} | head -n ${len} | cut -d" " -f2)
	io_print_data ${off} ${len}
}

# Write regmap register range
# @off  - offset of the first register - decimal
# @data - list of colon separated values to be written
# @len  - number of registers to write - decimal
# Assumptions:
#   1. Hexadecimal values in 'data' are prefixed with 0x
io_write()
{
	local off=$1
	local data=$2
	local len=$3

	# Check that 'len' parameter matches the number of registers in 'data'
	local data_len=$(echo ${data} | awk -F: '{print NF}')
	if [ ${len} -ne ${data_len} ]; then
		echo "Invalid write data, doesn't match write length"
		return 1
	fi

	# Split data into individual register values
	local values=$(echo ${data} | awk -F: '{for (i=0; ++i <= NF;) print $i}')

	# Iterate over register values and perform regmap write
	for val in ${values}; do
		if ! valid_write_val ${val}; then
			echo "Invalid write value:" ${val}
			return 1
		else
			printf "%x %x" ${off} ${val} > ${REGMAP_REGISTERS}
		fi
		off=$((off+1))
	done
}

###################################
#      Execution starts here      #
###################################

# Check regmap file availability
if [ ! -f ${REGMAP_REGISTERS} ] || [ ! -f ${REGMAP_RANGE} ]; then
	echo "Register map file is missing"
	exit 1
fi

# Set default values
offset=$(get_regmap_first_reg)
max_reg_val=$(get_regmap_max_reg_val)
io_op=${NO_OP}
quiet=0
file=
value=
length=
base=
default_x86_base=0x2500
offset_cmdline=0

# Parse command line parameters
while getopts "b:f:l:o:v:rwqh" arg; do
	case "${arg}" in
		b)
			base=${OPTARG}
			;;
		f)
			file=${OPTARG}
			;;
		l)
			length=${OPTARG}
			;;
		o)
			offset=${OPTARG}
			offset_cmdline=1
			;;
		v)
			value=${OPTARG}
			;;
		r)
			io_op=${RD_OP}
			;;
		w)
			io_op=${WR_OP}
			;;
		q)
			quiet=1
			;;
		h)
			usage
			exit 0
			;;
		*)
			echo "Error: invalid argument ${arg}"
			usage
			exit 1
			;;
	esac
done
shift $((OPTIND-1))

# Either read or write option should be specified
if [ "${io_op}" -eq "${NO_OP}" ]; then
	echo "Error: read/write option not specified"
	usage
	exit 1
fi

# Value for write option should be specified
if [ "${io_op}" -eq "${WR_OP}" ] && [ -z "${value}" ]; then
	echo "Error: write value not specified"
	usage
	exit 1
fi

# Length for write option should be specified
if [ "${io_op}" -eq "${WR_OP}" ] && [ -z "${length}" ]; then
	echo "Error: write length not specified"
	usage
	exit 1
fi

# Base parameter is supported for compatibility with X86 version.
# It should be at least 0x2500 (LPC base address on X86 platforms).
# On ARM plaforms it is converted to offset from X86 LPC base address.
# Both base and offset can be specified on the command line only if base=0x2500
if [ -n "${base}" ]; then
	base=$(printf "%d" ${base} 2>/dev/null)
	default_x86_base=$(printf "%d" ${default_x86_base} 2>/dev/null)

	if [ ${base} -lt ${default_x86_base} ]; then
		printf "Invalid base, should be at least 0x%x\n" ${default_x86_base}
		exit 1
	fi
	if [ ${offset_cmdline} -eq 1 ] && [ ${base} -ne ${default_x86_base} ]; then
		printf "Invalid combination of base and offset, base should be 0x%x\n" ${default_x86_base}
		exit 1
	fi

	if [ ${base} -gt ${default_x86_base} ]; then
		offset=$((base-default_x86_base))
	fi
fi

# Check offset parameter validity
offset=$(printf "%d" ${offset} 2>/dev/null)
if [ $? -ne 0 ]; then
	printf "Error: invalid offset 0x%x\n" ${offset}
	exit 1
fi

# Set default length for read, if not specified
if [ -z "${length}" ]; then
	length=$(get_regmap_size)
	if [ ${offset} -gt 0 ] && [ ${offset} -lt ${length} ]; then
		length=$((length-offset))
	fi
fi

# Check length parameter validity
length=$(printf "%d" ${length} 2>/dev/null)
if [ $? -ne 0 ]; then
	printf "Error: invalid length %d" ${length}
	exit 1
fi

# Check range validity
if ! valid_range ${offset} ${length}; then
	printf "Error: invalid range: start=0x%x length=%d\n" ${offset} ${length}
	exit 1
fi

# Perform read or write
if [ "${io_op}" -eq ${RD_OP} ]; then
	io_read $offset $length
else
	io_write $offset $value $length
fi

exit $?
