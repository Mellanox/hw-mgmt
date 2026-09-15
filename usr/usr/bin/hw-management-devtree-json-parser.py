#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
################################################################################
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
################################################################################

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
