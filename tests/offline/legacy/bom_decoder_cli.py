#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

"""
BOM String Decoder - Command Line Interface

This script decodes BOM (Bill of Materials) strings that contain information about
modules and components on each board.

Usage:
    python3 bom_decoder_cli.py "V0-C*EiRaA0-K*G0EgEgJa-S*GbGbTbTbRgRgJ0J0RgRgRgRg-F*Tb-L*GcNaEi-P*PaPa-O*Tb"
"""

import sys
import argparse
from typing import Dict, List, Tuple, Optional
from enum import Enum


class BoardType(Enum):
    """Board type enumeration"""
    CPU_BOARD = "cpu_board"
    SWITCH_BOARD = "switch_board"
    FAN_BOARD = "fan_board"
    POWER_BOARD = "power_board"
    PLATFORM_BOARD = "platform_board"
    CLOCK_BOARD = "clock_board"
    PORT_BOARD = "port_board"
    DPU_BOARD = "dpu_board"


class ComponentCategory(Enum):
    """Component category enumeration"""
    THERMAL = "thermal"
    REGULATOR = "regulator"
    A2D = "a2d"
    PRESSURE = "pressure"
    EEPROM = "eeprom"
    POWERCONV = "powerconv"
    HOTSWAP = "hotswap"
    GPIO = "gpio"
    NETWORK = "network"
    JITTER = "jitter"
    OSC = "osc"
    FPGA = "fpga"
    EROT = "erot"
    RTC = "rtc"


class Component:
    """Component information"""
    def __init__(self, category: str, type: str, category_char: str, type_char: str, is_populated: bool = True):
        self.category = category
        self.type = type
        self.category_char = category_char  # Original category character
        self.type_char = type_char  # Original type character
        self.is_populated = is_populated


class Board:
    """Board information"""
    def __init__(self, board_type: str, board_number: str, components: List[Component], board_string: str = ""):
        self.board_type = board_type
        self.board_number = board_number
        self.components = components
        self.board_string = board_string  # Original board string from BOM


class BOMData:
    """Complete BOM data"""
    def __init__(self, boards: List[Board]):
        self.boards = boards


class BOMDecoder:
    """BOM String Decoder"""

    def __init__(self):
        # Board type mapping
        self.board_type_map = {
            "C": "cpu_board",
            "S": "switch_board",
            "F": "fan_board",
            "P": "power_board",
            "L": "platform_board",
            "K": "clock_board",
            "O": "port_board",
            "D": "dpu_board"
        }

        # Component category mapping
        self.category_map = {
            "T": "thermal",
            "R": "regulator",
            "A": "a2d",
            "P": "pressure",
            "E": "eeprom",
            "O": "powerconv",
            "H": "hotswap",
            "G": "gpio",
            "N": "network",
            "J": "jitter",
            "X": "osc",
            "F": "fpga",
            "S": "erot",
            "C": "rtc"
        }

        # Component type mappings
        self.thermal_types = {
            "0": "dummy", "a": "lm75", "b": "tmp102", "c": "adt75",
            "d": "stts751", "e": "tmp75", "f": "tmp421", "g": "lm90",
            "h": "emc1412", "i": "tmp411", "j": "tmp1075", "k": "tmp451"
        }

        self.regulator_types = {
            "0": "dummy", "a": "mp2975", "b": "mp2888", "c": "tps53679",
            "d": "xdpe12284", "e": "152x4", "f": "pmbus", "g": "mp2891",
            "h": "xdpe1a2g7", "i": "mp2855", "j": "mp29816"
        }

        self.a2d_types = {
            "0": "dummy", "a": "max11603", "b": "ads1015"
        }

        self.pwr_conv_types = {
            "0": "dummy", "a": "pmbus", "b": "pmbus", "c": "pmbus",
            "d": "raa228000", "e": "mp29502", "f": "raa228004"
        }

        self.hotswap_types = {
            "0": "dummy", "a": "lm5066", "c": "lm5066i"
        }

        self.eeprom_types = {
            "0": "dummy", "a": "24c02", "c": "24c08", "e": "24c32",
            "g": "24c128", "i": "24c512"
        }

        self.pressure_types = {
            "0": "dummy", "a": "icp201xx", "b": "bmp390", "c": "lps22"
        }

        # Map component categories to their type dictionaries
        self.component_type_maps = {
            "thermal": self.thermal_types,
            "regulator": self.regulator_types,
            "a2d": self.a2d_types,
            "powerconv": self.pwr_conv_types,
            "hotswap": self.hotswap_types,
            "eeprom": self.eeprom_types,
            "pressure": self.pressure_types
        }

    def decode_board_type(self, board_code: str) -> Tuple[str, str]:
        """
        Decode board type and number from 2-character code

        Args:
            board_code: 2-character board code

        Returns:
            Tuple of (board_type, board_number)
        """
        if len(board_code) != 2:
            raise ValueError(f"Board code must be 2 characters, got: {board_code}")

        board_type_char = board_code[0]
        board_number = board_code[1]

        if board_type_char not in self.board_type_map:
            raise ValueError(f"Unknown board type: {board_type_char}")

        return self.board_type_map[board_type_char], board_number

    def decode_component(self, component_code: str) -> Component:
        """
        Decode component from 2-character code

        Args:
            component_code: 2-character component code

        Returns:
            Component object
        """
        if len(component_code) != 2:
            raise ValueError(f"Component code must be 2 characters, got: {component_code}")

        category_char = component_code[0]
        type_char = component_code[1]

        if category_char not in self.category_map:
            raise ValueError(f"Unknown component category: {category_char}")

        category = self.category_map[category_char]
        is_populated = type_char != "0"

        # Get component type
        if category in self.component_type_maps:
            type_map = self.component_type_maps[category]
            if type_char in type_map:
                component_type = type_map[type_char]
            else:
                component_type = f"unknown_{type_char}"
        else:
            # For categories without specific type mapping, use the type character
            component_type = "ND"

        return Component(
            category=category,
            type=component_type,
            category_char=category_char,
            type_char=type_char,
            is_populated=is_populated
        )

    def decode_board_string(self, board_string: str) -> Board:
        """
        Decode a single board string

        Args:
            board_string: Board string to decode

        Returns:
            Board object
        """
        if len(board_string) < 2:
            raise ValueError(f"Board string too short: {board_string}")

        # First 2 characters are board type and number
        board_code = board_string[:2]
        board_type, board_number = self.decode_board_type(board_code)

        # Remaining characters are components (2 characters each)
        components = []
        remaining = board_string[2:]

        if len(remaining) % 2 != 0:
            raise ValueError(f"Invalid board string length: {board_string}")

        for i in range(0, len(remaining), 2):
            component_code = remaining[i:i + 2]
            component = self.decode_component(component_code)
            components.append(component)

        return Board(
            board_type=board_type,
            board_number=board_number,
            components=components,
            board_string=board_string
        )

    def decode_bom_string(self, bom_string: str) -> BOMData:
        """
        Decode complete BOM string

        Args:
            bom_string: Complete BOM string

        Returns:
            BOMData object
        """
        if not bom_string.startswith("V0"):
            raise ValueError("BOM string must start with 'V0'")

        # Remove "V0" prefix
        bom_content = bom_string[2:]

        # Split by "-" to get board strings
        board_strings = bom_content.split("-")

        boards = []
        for board_string in board_strings:
            if board_string.strip():  # Skip empty strings
                board = self.decode_board_string(board_string.strip())
                boards.append(board)

        return BOMData(boards=boards)

    def print_bom_data(self, bom_data: BOMData) -> None:
        """
        Print BOM data in a readable format

        Args:
            bom_data: BOMData object to print
        """
        print("BOM Data:")
        print("=" * 50)

        for i, board in enumerate(bom_data.boards, 1):
            print(f"\nBoard {i}:")
            print(f"  Type: {board.board_type}")
            print(f"  Number: {board.board_number}")
            print(f"  Board String: {board.board_string}")
            print(f"  Components ({len(board.components)}):")

            for j, component in enumerate(board.components, 1):
                status = "Populated" if component.is_populated else "Unpopulated/Removed"
                print(f"    {j}. {component.category} - {component.type} (cat:{component.category_char},type:{component.type_char}) ({status})")

    def analyze_bom_data(self, bom_data: BOMData) -> None:
        """Analyze BOM data and provide statistics"""
        print("\nBOM Analysis:")
        print("=" * 50)

        total_boards = len(bom_data.boards)
        total_components = sum(len(board.components) for board in bom_data.boards)
        populated_components = sum(
            sum(1 for comp in board.components if comp.is_populated)
            for board in bom_data.boards
        )
        unpopulated_components = total_components - populated_components

        print(f"Total Boards: {total_boards}")
        print(f"Total Components: {total_components}")
        print(f"Populated Components: {populated_components}")
        print(f"Unpopulated Components: {unpopulated_components}")

        # Board type statistics
        board_types = {}
        for board in bom_data.boards:
            board_types[board.board_type] = board_types.get(board.board_type, 0) + 1

        print(f"\nBoard Types:")
        for board_type, count in board_types.items():
            print(f"  {board_type}: {count}")

        # Component category statistics
        component_categories = {}
        for board in bom_data.boards:
            for component in board.components:
                component_categories[component.category] = component_categories.get(component.category, 0) + 1

        print(f"\nComponent Categories:")
        for category, count in component_categories.items():
            print(f"  {category}: {count}")

    def get_components_by_category(self, bom_data: BOMData, category: str) -> List[Tuple[Board, Component]]:
        """Get all components of a specific category"""
        components = []
        for board in bom_data.boards:
            for component in board.components:
                if component.category == category:
                    components.append((board, component))
        return components

    def print_detailed_analysis(self, bom_data: BOMData) -> None:
        """Print detailed analysis of BOM data"""
        # Find all thermal components
        print(f"\nThermal Components:")
        thermal_components = self.get_components_by_category(bom_data, "thermal")
        for board, component in thermal_components:
            status = "Populated" if component.is_populated else "Unpopulated"
            print(f"  {board.board_type} {board.board_number}: {component.type} (cat:{component.category_char},type:{component.type_char}) ({status})")

        # Find all unpopulated components
        print(f"\nUnpopulated Components:")
        for board in bom_data.boards:
            unpopulated = [comp for comp in board.components if not comp.is_populated]
            if unpopulated:
                print(f"  {board.board_type} {board.board_number}:")
                for comp in unpopulated:
                    print(f"    - {comp.category}: {comp.type} (cat:{comp.category_char},type:{comp.type_char})")

        # Detailed board information
        print(f"\nDetailed Board Information:")
        for i, board in enumerate(bom_data.boards, 1):
            print(f"\nBoard {i}: {board.board_type} {board.board_number}")
            print(f"  Board String: {board.board_string}")
            print(f"  Components:")
            for j, comp in enumerate(board.components, 1):
                status = "[PASS]" if comp.is_populated else "[FAIL]"
                print(f"    {j}. [{status}] {comp.category}: {comp.type} (cat:{comp.category_char},type:{comp.type_char})")


def main():
    """Main function with command line interface"""
    parser = argparse.ArgumentParser(
        description="Decode BOM (Bill of Materials) strings",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 bom_decoder_cli.py "V0-C*EiRaA0-K*G0EgEgJa-S*GbGbTbTbRgRgJ0J0RgRgRgRg-F*Tb-L*GcNaEi-P*PaPa-O*Tb"
  python3 bom_decoder_cli.py "V0C1TaAaR0-S2TbRcEa"
        """
    )

    parser.add_argument(
        "bom_string",
        help="BOM string to decode (must start with V0)"
    )

    parser.add_argument(
        "--detailed", "-d",
        action="store_true",
        help="Show detailed analysis including thermal components and unpopulated components"
    )

    parser.add_argument(
        "--analysis-only", "-a",
        action="store_true",
        help="Show only analysis, skip detailed board listing"
    )

    args = parser.parse_args()

    decoder = BOMDecoder()

    try:
        # Decode the BOM string
        bom_data = decoder.decode_bom_string(args.bom_string)

        if not args.analysis_only:
            # Print the decoded data
            decoder.print_bom_data(bom_data)

        # Always show analysis
        decoder.analyze_bom_data(bom_data)

        if args.detailed:
            decoder.print_detailed_analysis(bom_data)

    except ValueError as e:
        print(f"Error decoding BOM string: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
