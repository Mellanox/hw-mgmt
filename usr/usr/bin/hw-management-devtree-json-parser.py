#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# hw-management devtree BOM JSON parser
#
# Reads and validates a devtree BOM JSON file, then prints every entry across
# all sections as:
#   <section> <key> <spec>
# one per line, for consumption by hw-management-devtree.sh.
#
# Usage: hw-management-devtree-json-parser.py <json_file>
#
# The JSON file is expected to have the structure:
#   {
#       "<section>": [
#           { "key": "<key>", "spec": "<spec>" },
#           ...
#       ],
#       ...
#   }
#
# All sections present in the JSON file are output; no predefined list is used.
# Each section name must correspond to a declared <section>_alternatives
# associative array in hw-management-devtree.sh, e.g.: swb, port, pwr, platform,
# comex, fan, clk, dpu, etc.
#
# Any new section can be added to the JSON, provided a matching
# <section>_alternatives array is declared in hw-management-devtree.sh.

import json
import sys


def validate_bom(data):
    """
    Validate the structure of the BOM JSON.
    Raises ValueError with a descriptive message on any structural problem.
    """
    if not isinstance(data, dict):
        raise ValueError("top-level value must be a JSON object")

    for section, entries in data.items():
        if any(c.isspace() for c in section):
            raise ValueError(
                f"section name '{section}' must not contain whitespace"
            )
        if not isinstance(entries, list):
            raise ValueError(
                f"section '{section}': expected an array, got {type(entries).__name__}"
            )
        for idx, entry in enumerate(entries):
            if not isinstance(entry, dict):
                raise ValueError(
                    f"section '{section}' entry {idx}: expected an object, "
                    f"got {type(entry).__name__}"
                )
            for field in ("key", "spec"):
                if field not in entry:
                    raise ValueError(
                        f"section '{section}' entry {idx}: missing required field '{field}'"
                    )
                if not isinstance(entry[field], str) or not entry[field].strip():
                    raise ValueError(
                        f"section '{section}' entry {idx}: "
                        f"'{field}' must be a non-empty string"
                    )
            if any(c.isspace() for c in entry["key"]):
                raise ValueError(
                    f"section '{section}' entry {idx}: "
                    f"'key' must not contain whitespace"
                )
            if any(c in "\n\r" for c in entry["spec"]):
                raise ValueError(
                    f"section '{section}' entry {idx}: "
                    f"'spec' must not contain newlines"
                )


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <json_file>", file=sys.stderr)
        sys.exit(1)

    json_file = sys.argv[1]

    try:
        with open(json_file) as f:
            data = json.load(f)
    except OSError as e:
        print(f"Error: cannot read '{json_file}': {e}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: JSON syntax error in '{json_file}': {e}", file=sys.stderr)
        sys.exit(1)

    try:
        validate_bom(data)
    except ValueError as e:
        print(f"Error: invalid BOM JSON '{json_file}': {e}", file=sys.stderr)
        sys.exit(1)

    for section, entries in data.items():
        for entry in entries:
            print(f"{section} {entry['key']} {entry['spec']}")


if __name__ == "__main__":
    main()
