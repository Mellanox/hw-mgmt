#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

source hw-management-helpers.sh
declare -A leakage_map
# Format: leakage_map[ID]="address:offset"
# 0 = leakage detected
# 1 = leakage not detected
leakage_map[1]="0x20ff:0"
leakage_map[2]="0x20ff:1"
leakage_map[3]="0x20ff:2"
leakage_map[4]="0x20ff:3"
leakage_map[5]="0x20ff:4"
leakage_map[aggr]="0x20fe:0"

function usage() {
    cat <<EOF
hw-management-leakage-mock.sh - Hardware Management Leakage Sensor Mock Tool

DESCRIPTION:
    This script allows you to simulate and control leakage sensor states on supported
    NVIDIA switch systems. It manipulates hardware registers to mock leakage detection
    for testing and validation purposes.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -s <id>     Simulate leakage for the given sensor ID
                (unsets the corresponding bit at the register offset)

    -r <id>     Revert/clear leakage for the given sensor ID
                (sets the corresponding bit at the register offset)

    -c          Clear all leakages (revert all leakage sensors to normal state)

    -h          Show this help message and exit

SUPPORTED LEAKAGE SENSOR IDs:
    ${!leakage_map[@]}

EXAMPLES:
    # Simulate leakage on sensor 1
    $0 -s 1

    # Revert leakage on sensor 2
    $0 -r 2

    # Clear all simulated leakages
    $0 -c

    # Show help
    $0 -h

NOTES:
    - This tool only works on supported NVIDIA switch systems (N5-N9 series)
    - Requires iorw utility for hardware register access
    - Leakage state: 0 = leakage detected, 1 = no leakage detected
    - Use with caution as it directly modifies hardware registers

EOF
}

function is_system_supported ()
{
    local nvl_rgx="N[0-9]+_LD"
    pn=$(cat $pn_file)
    if [[ $pn =~ $nvl_rgx ]]; then
        return 0
    fi
    return 1
}

function clear_all_leakage ()
{
    echo "Clearing all leakage"
    for leakage_id in "${!leakage_map[@]}"; do
        unmock_leakage "$leakage_id"
    done
}

function mock_leakage ()
{
    local leakage_id=$1
    local entry=${leakage_map[$leakage_id]}
    if [[ -z "$entry" ]]; then
        echo "Unknown leakage sensor ID: $leakage_id"
        exit 1
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

function unmock_leakage ()
{
    local leakage_id=$1
    local entry=${leakage_map[$leakage_id]}
    if [[ -z "$entry" ]]; then
        echo "Unknown leakage sensor ID: $leakage_id"
        exit 1
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

main()
{
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    if ! is_system_supported; then
        echo "System not supported"
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
