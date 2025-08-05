#!/bin/bash
################################################################################
# Copyright (c) 2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

declare -A leakage_map
# Format: leakage_map[ID]="address:offset"
# 0 = leakage detected
# 1 = leakage not detected
leakage_map[1]="0x20ff:0"
leakage_map[2]="0x20ff:1"
leakage_map[5]="0x20ff:4"
leakage_map[aggr]="0x20fe:0"

function usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -s <id>   Simulate leakage for the given sensor id (unset bit at offset)
  -r <id>   Revert leakage for the given sensor id (set bit at offset)
  -c        Clear all leakages (revert all leakage sensors)
  -h        Show this help message

Valid leakage ids: ${!leakage_map[@]}
EOF
}

function clear_all_leakage () {
    echo "Clearing all leakage"
    for leakage_id in "${!leakage_map[@]}"; do
        unmock_leakage "$leakage_id"
    done
}

function mock_leakage () {
    local leakage_id=$1
    local entry=${leakage_map[$leakage_id]}
    if [[ -z "$entry" ]]; then
        echo "Unknown leakage sensor ID: $leakage_id"
        return 1
    fi
    local address=${entry%%:*}
    local bit_offset=${entry##*:}
    echo "Setting leakage on leakage sensor $leakage_id"
    local curr_val=$(iorw -r -b $address -l 1)
    local mask=$(( ~(1 << $bit_offset) & 0xFF ))
    local new_val=$(( ${curr_val##*= } & mask ))

    hex_val=$(printf "0x%x" "$new_val")
    # echo "iorw -w -b $address -l 1 -v $hex_val"
    iorw -w -b $address -l 1 -v $hex_val
}

function unmock_leakage () {
    local leakage_id=$1
    local entry=${leakage_map[$leakage_id]}
    if [[ -z "$entry" ]]; then
        echo "Unknown leakage sensor ID: $leakage_id"
        return 1
    fi
    local address=${entry%%:*}
    local bit_offset=${entry##*:}
    echo "Unsetting leakage on leakage sensor $leakage_id"
    local curr_val=$(iorw -r -b $address -l 1)
    local mask=$(( 1 << $bit_offset ))
    local new_val=$(( ${curr_val##*= } | mask ))

    hex_val=$(printf "0x%x" "$new_val")
    # echo "iorw -w -b $address -l 1 -v $hex_val"
    iorw -w -b $address -l 1 -v $hex_val
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    while getopts "s:r:ch" opt; do
        case $opt in
            s)
                mock_leakage "$OPTARG"
                ;;
            r)
                unmock_leakage "$OPTARG"
                ;;
            c)
                clear_all_leakage
                ;;
            h)
                usage
                exit 0
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done
}

main "$@"