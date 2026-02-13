#!/bin/bash

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

# I2C Configuration
I2C_BUS=${I2C_BUS:-2}            # Default I2C bus number
I2C_SLAVE_ADDR=${I2C_SLAVE_ADDR:-0x33} # Default CPLD I2C slave address

# =====================================================================
# Default legacy values
# =====================================================================
OP=""
BASE_ADDR=$((0x2500))
OFFSET=0
LEN=""
VAL=""
FILE=""
FORCE=0
QUIET=0

usage() {
    echo "Usage: $0 -r|-w [-b <base_addr>] [-o <offset>] [-l <len>] [-v <value>] [-f <filename>] [-F] [-q] [-h]"
    echo "Options:"
    echo "  -r          Read operation"
    echo "  -w          Write operation"
    echo "  -b <addr>   Base address, default: 0x2500"
    echo "  -o <offset> Offset, default: 0"
    echo "  -l <len>    Length in bytes (default for read: 256)"
    echo "  -v <value>  Value(s) for write operation (e.g., 0xAA or '0xAA 0xBB')"
    echo "  -f <file>   File to store raw binary output"
    echo "  -F          Force, don't check region ranges"
    echo "  -q          Quiet, can be used only with -f option, store in file without print"
    echo "  -h          Print this help message"
}

# Parse command line arguments
while getopts "rwb:o:l:v:f:Fqh" opt; do
    case $opt in
        r) OP="read" ;;
        w) OP="write" ;;
        b) BASE_ADDR=$(($OPTARG)) ;;
        o) OFFSET=$(($OPTARG)) ;;
        l) LEN=$(($OPTARG)) ;;
        v) VAL=$OPTARG ;;
        f) FILE=$OPTARG ;;
        F) FORCE=1 ;;
        q) QUIET=1 ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

# =====================================================================
# Input Validation
# =====================================================================
if [ -z "$OP" ]; then
    echo "Error: Read (-r) or Write (-w) option must be provided."
    usage
    exit 1
fi

if [ "$OP" == "write" ] && [ -z "$LEN" ]; then
    echo "Error: Length (-l) must be provided for write operations."
    exit 1
fi

if [ "$OP" == "write" ] && [ -z "$VAL" ]; then
    echo "Error: Value (-v) must be provided for write operations."
    exit 1
fi

if [ $QUIET -eq 1 ] && [ -z "$FILE" ]; then
    echo "Error: Quiet (-q) can only be used with the file (-f) option."
    exit 1
fi

# =====================================================================
# Address Calculation
# =====================================================================
TARGET_ADDR=$((BASE_ADDR + OFFSET))

# Dummy range check logic
MAX_ADDR=$((0xFFFF))
if [ $FORCE -eq 0 ]; then
    if [ $TARGET_ADDR -lt 0 ] || [ $TARGET_ADDR -gt $MAX_ADDR ]; then
        echo "Error: Target address out of range. Use -F to force."
        exit 1
    fi
fi

# Convert 16-bit address to high and low bytes for i2ctransfer
ADDR_H=$(printf "0x%02x" $(((TARGET_ADDR >> 8) & 0xFF)))
ADDR_L=$(printf "0x%02x" $((TARGET_ADDR & 0xFF)))

# =====================================================================
# Output Formatter (For multi-byte human-readable terminal output)
# =====================================================================
format_output() {
    local RAW_BYTES=($1)
    local CURR_ADDR=$2
    local COUNT=0
    local LINE_STR=""

    for BYTE in "${RAW_BYTES[@]}"; do
        local CLEAN_BYTE=${BYTE#0x}

        if [ $COUNT -eq 0 ]; then
            LINE_STR=$(printf "0x%04x:" $CURR_ADDR)
        fi

        LINE_STR="${LINE_STR} ${CLEAN_BYTE}"

        COUNT=$((COUNT + 1))
        CURR_ADDR=$((CURR_ADDR + 1))

        if [ $COUNT -eq 16 ]; then
            echo "$LINE_STR"
            COUNT=0
        fi
    done

    if [ $COUNT -ne 0 ]; then
        echo "$LINE_STR"
    fi
}

# =====================================================================
# I2C Execution
# =====================================================================
if [ "$OP" == "read" ]; then
    if [ -z "$LEN" ]; then
        LEN=256
    fi

    RESULT=$(i2ctransfer -y "$I2C_BUS" w2@"$I2C_SLAVE_ADDR" "$ADDR_H" "$ADDR_L" r"$LEN")
    STATUS=$?

    if [ $STATUS -ne 0 ]; then
        # Send errors to stderr so they don't corrupt binary dumps
        echo "I2C Read Failed: $RESULT" >&2
        exit 1
    fi

    # --- RAW BINARY FILE WRITING (If -f is used) ---
    if [ -n "$FILE" ]; then
        for BYTE in $RESULT; do
            printf "\\x${BYTE#0x}"
        done > "$FILE"
    fi

    # --- STDOUT LOGIC (Terminal vs Redirect/Pipe) ---
    if [ $QUIET -eq 0 ]; then
        if [ "$LEN" -eq 1 ]; then
            # Special formatting for single-byte read
            printf "IO reg 0x%04x = 0x%02x\n" $TARGET_ADDR "$RESULT"
        else
            # Standard hexdump formatting for multi-byte read
            FINAL_OUTPUT=$(format_output "$RESULT" $TARGET_ADDR)
            echo "$FINAL_OUTPUT"
        fi
    fi
elif [ "$OP" == "write" ]; then
    TOTAL_WRITE_LEN=$((2 + LEN))

    # Convert the input value to space-separated bytes for i2ctransfer
    FORMATTED_VALS=""
    
    if [[ "$VAL" == *" "* ]]; then
        # Handle explicitly passed space-separated bytes (e.g., "0x58 0x02")
        FORMATTED_VALS="$VAL"
    else
        # Handle legacy single-integer callers (e.g., 600 or 0x0258)
        # Bash $(()) evaluates both decimal and hex strings to integers automatically
        NUM_VAL=$(($VAL))
        
        # Extract bytes in Big-Endian order (MSB first)
        for (( i=0; i<LEN; i++ )); do
            # Calculate shift amount to grab the most significant byte first
            SHIFT=$(( 8 * (LEN - 1 - i) ))
            BYTE=$(( (NUM_VAL >> SHIFT) & 0xFF ))
            
            # Append cleanly without a leading space on the first item
            if [ -z "$FORMATTED_VALS" ]; then
                FORMATTED_VALS="$(printf "0x%02x" $BYTE)"
            else
                FORMATTED_VALS="$FORMATTED_VALS $(printf "0x%02x" $BYTE)"
            fi
        done
    fi

    # Execute with the properly formatted byte string
    RESULT=$(i2ctransfer -y "$I2C_BUS" w"${TOTAL_WRITE_LEN}"@"$I2C_SLAVE_ADDR" "$ADDR_H" "$ADDR_L" $FORMATTED_VALS 2>&1)
    STATUS=$?

    if [ $STATUS -ne 0 ]; then
        echo "I2C Write Failed: $RESULT" >&2
        exit 1
    fi
fi
