#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

source hw-management-helpers.sh
declare -A leakage_map
# Format: leakage_map[ID]="address:offset"
#
# Leakage register semantics:
#   0 = leakage asserted/detected
#   1 = leakage cleared/not detected
#
# 0x20ff[4:0] - Individual leakage sensor simulation.
# 0x20fe[0]   - Aggregated leakage indication.
# 0x20fe[1]   - Tray_Leak_L / Small_Leak_L output to the RJ45 leakage connector.
leakage_map[1]="0x20ff:0"
leakage_map[2]="0x20ff:1"
leakage_map[3]="0x20ff:2"
leakage_map[4]="0x20ff:3"
leakage_map[5]="0x20ff:4"
leakage_map[aggr]="0x20fe:0"
# RJ45/LSC path (Tray_Leak_L / Small_Leak_L)
leakage_map[rj45]="0x20fe:1"

function usage() {
    cat <<EOF
hw-management-leakage-mock.sh - Hardware Management Leakage Sensor Mock Tool

DESCRIPTION:
    This script allows you to simulate and control leakage sensor states on
    supported NVIDIA switch systems. It manipulates hardware registers to mock
    leakage detection for testing and validation purposes.

    The "rj45" target controls the active-low Tray_Leak_L signal driven through
    the RJ45 leakage connector.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -s <id>     Simulate leakage for the given sensor or output ID
                (unsets the corresponding register bit)

    -r <id>     Revert/clear leakage for the given sensor or output ID
                (sets the corresponding register bit)

    -c          Clear all simulated leakages and outputs

    -h          Show this help message and exit

SUPPORTED LEAKAGE IDs:
    ${!leakage_map[@]}

EXAMPLES:
    # Simulate leakage on sensor 1
    $0 -s 1

    # Revert leakage on sensor 2
    $0 -r 2

    # Assert the aggregate leakage indication
    $0 -s aggr

    # Assert Tray_Leak_L on the RJ45 leakage connector
    $0 -s rj45

    # Revert Tray_Leak_L on the RJ45 leakage connector
    $0 -r rj45

    # Simulate sensor 1 across the sensor, aggregate, and RJ45 paths
    $0 -s 1 -s aggr -s rj45

    # Clear all simulated leakages and outputs
    $0 -c

    # Show help
    $0 -h

NOTES:
    - This tool only works on supported NVIDIA switch systems (N5-N9 series).
    - The iorw utility and sufficient privileges are required.
    - Leakage state: 0 = leakage detected, 1 = no leakage detected.
    - RJ45 state: 0 = Tray_Leak_L asserted, 1 = Tray_Leak_L deasserted.
    - The BMC-side RJ45 connector must be enabled separately, for example
      through the platform's leak_rj45_en configuration.
    - Use with caution because this tool directly modifies hardware registers.

EOF
}

function is_system_supported ()
{
    local nvl_rgx="N[0-9]+_LD"
    local pn

    pn=$(cat "$pn_file")
    if [[ $pn =~ $nvl_rgx ]]; then
        return 0
    fi
    return 1
}

function clear_all_leakage ()
{
    local leakage_id

    echo "Clearing all simulated leakage states and outputs"
    for leakage_id in "${!leakage_map[@]}"; do
        unmock_leakage "$leakage_id"
    done
}

function mock_leakage ()
{
    local leakage_id=$1
    local entry=${leakage_map[$leakage_id]}
    local address
    local bit_offset
    local curr_val
    local mask
    local new_val
    local hex_val

    if [[ -z "$entry" ]]; then
        echo "Unknown leakage sensor or output ID: $leakage_id"
        exit 1
    fi

    address=${entry%%:*}
    bit_offset=${entry##*:}

    echo "Setting leakage on $leakage_id"

    curr_val=$(iorw -r -b "$address" -l 1)
    mask=$(( ~(1 << bit_offset) & 0xFF ))
    new_val=$(( ${curr_val##*= } & mask ))
    hex_val=$(printf "0x%x" "$new_val")

    # echo "iorw -w -b $address -l 1 -v $hex_val"
    iorw -w -b "$address" -l 1 -v "$hex_val"
}

function unmock_leakage ()
{
    local leakage_id=$1
    local entry=${leakage_map[$leakage_id]}
    local address
    local bit_offset
    local curr_val
    local mask
    local new_val
    local hex_val

    if [[ -z "$entry" ]]; then
        echo "Unknown leakage sensor or output ID: $leakage_id"
        exit 1
    fi

    address=${entry%%:*}
    bit_offset=${entry##*:}

    echo "Unsetting leakage on $leakage_id"

    curr_val=$(iorw -r -b "$address" -l 1)
    mask=$(( 1 << bit_offset ))
    new_val=$(( ${curr_val##*= } | mask ))
    hex_val=$(printf "0x%x" "$new_val")

    # echo "iorw -w -b $address -l 1 -v $hex_val"
    iorw -w -b "$address" -l 1 -v "$hex_val"
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
