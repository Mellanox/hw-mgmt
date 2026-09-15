<!-- SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES -->
<!-- Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved. -->
<!--
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. Neither the names of the copyright holders nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

Alternatively, this software may be distributed under the terms of the
GNU General Public License ("GPL") version 2 as published by the Free
Software Foundation.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
-->

# hw-management devtree BOM JSON

Per-SKU device-tree BOM data can be supplied as a JSON config file instead
of hard-coding a new `case` branch in `hw-management-devtree.sh`.  The JSON
file is parsed by `hw-management-devtree-json-parser.py`, which populates the
`*_alternatives` associative arrays that the rest of `hw-management-devtree.sh`
already uses.

## Components

| Item | Installed path | Role |
|------|----------------|------|
| [hw-management-devtree-json-parser.py](../usr/usr/bin/hw-management-devtree-json-parser.py) | `/usr/bin/hw-management-devtree-json-parser.py` | Reads, validates and prints `<section> <key> <spec>` lines |
| [hw-management-devtree.sh](../usr/usr/bin/hw-management-devtree.sh) | `/usr/bin/hw-management-devtree.sh` | Consumes parser output; populates `*_alternatives` arrays |
| Per-SKU config | `/etc/hw-management-cfg/<SKU>/devtree.json` | One file per SKU; contains all board sections |

## Design

```
  SMBIOS board SKU
       │
       ▼
  devtr_check_supported_system_init_alternatives()
       │
       ├─ case $cpu_type ─► populate comex_alternatives (CPU sensors)
       │
       ├─ /etc/hw-management-cfg/<SKU>/devtree.json exists?
       │       YES ──► devtr_bom_load_from_json()
       │                   │
       │                   ├─ hw-management-devtree-json-parser.py <file>
       │                   │       validates JSON, prints: section key spec
       │                   │
       │                   └─ while read section key spec
       │                           <section>_alternatives["$key"]="$spec"
       │                           (undeclared sections are skipped with a log)
       │               return 0 ◄──────────────────────────────────────────┘
       │
       └─ NO ──► case $board_type (legacy hard-coded alternatives)
```

The JSON path is evaluated **after** the `cpu_type` block so that CPU-side
sensors (comex VRs, DIMMs, etc.) are always initialised regardless of which
loading path is taken.

If the JSON file exists but is invalid the function logs an error and returns
non-zero, which causes `hw-management-devtree.sh` to abort BOM loading for
that SKU.

## JSON format

```json
{
    "<section>": [
        { "key": "<key>", "spec": "<spec>" },
        ...
    ],
    ...
}
```

### Sections

A section name maps 1-to-1 to an `*_alternatives` associative array that is
**already declared** in `hw-management-devtree.sh`.  The runtime arrays are:

| Section name | Bash array | Covers |
|--------------|------------|--------|
| `swb` | `swb_alternatives` | Switch-board VRs, EEPROMs |
| `port` | `port_alternatives` | Port-card VRs |
| `pwr` | `pwr_alternatives` | Power-board converters, temp sensors |
| `platform` | `platform_alternatives` | Main-board EEPROMs, SODIMMs, VRs |
| `comex` | `comex_alternatives` | CPU-complex VRs (usually set by cpu_type) |
| `fan` | `fan_alternatives` | Fan controllers |
| `clk` | `clk_alternatives` | Clock generators |
| `dpu` | `dpu_alternatives` | DPU board devices |
| `board` | `board_alternatives` | Miscellaneous board-level devices |

A section present in the JSON but with no corresponding `declare -A` in
`hw-management-devtree.sh` is silently skipped with a `log_info` message.

### Keys and specs

Each entry has exactly two string fields:

| Field | Constraints | Example |
|-------|-------------|---------|
| `key` | Non-empty; no whitespace | `"mp29816_0"` |
| `spec` | Non-empty; no `\n` or `\r` | `"mp29816 0x61 15 voltmon1"` |

The `spec` value is passed verbatim as the value of `<section>_alternatives["$key"]`
and is later consumed by the I²C device-tree instantiation logic in
`hw-management-devtree.sh`.

## Annotated example

The example below shows the structure used for a typical platform with a
switch board, port card, power board, and main-board components.

```json
{
    "swb": [
        { "key": "mp29816_0",    "spec": "mp29816 0x61 15 voltmon1"  },
        { "key": "mp29816_1",    "spec": "mp29816 0x62 15 voltmon2"  },
        { "key": "xdpe1a2g7_0", "spec": "xdpe1a2g7b 0x61 15 voltmon1" },
        { "key": "24c512_0",    "spec": "24c512 0x51 24 swb_info"    }
    ],
    "port": [
        { "key": "mp29816_0",    "spec": "mp29816 0x68 15 voltmon19"    },
        { "key": "xdpe1a2g7_0", "spec": "xdpe1a2g7b 0x68 15 voltmon19" }
    ],
    "pwr": [
        { "key": "raa228004_0", "spec": "raa228004 0x60 6 pdb_pwr_conv1" },
        { "key": "mp29502_0",   "spec": "mp29502 0x2e 6 pdb_pwr_conv1"  },
        { "key": "tmp451_0",    "spec": "tmp451 0x4c 6 pdb_temp1"       }
    ],
    "platform": [
        { "key": "24c512_1",  "spec": "24c512 0x51 1 vpd_info"        },
        { "key": "jc42_0",    "spec": "jc42 0x52 10 somdimm_temp1"    },
        { "key": "mp2845_0",  "spec": "mp2845 0x69 5 comex_voltmon1"  }
    ]
}
```

## Adding a new platform

1. **Identify the SKU string** reported by SMBIOS (field used as `$sku` in
   `hw-management-devtree.sh`, typically the board product name, e.g. `HI195`).

2. **Create the config directory and JSON file**:
   ```
   usr/etc/hw-management-cfg/<SKU>/devtree.json
   ```

3. **Populate the JSON** with one entry per I²C device alternative, grouping
   them under the appropriate section (`swb`, `port`, `pwr`, `platform`, etc.).

4. **No changes to `hw-management-devtree.sh` are required** — the JSON loader
   runs automatically for any SKU whose `devtree.json` exists.

5. **If a brand-new section name is needed** (not in the table above), declare
   the corresponding `declare -A <section>_alternatives` in
   `hw-management-devtree.sh` and add it to the `devtr_check_supported_system_init_alternatives`
   selection logic.

## Validation rules enforced by the parser

The parser exits non-zero and prints a message to stderr if any of the
following conditions are violated:

| Rule | Reason |
|------|--------|
| Top-level value must be a JSON object | bash loop expects `section key spec` triples |
| Each section value must be a JSON array | structural requirement |
| Each array element must be a JSON object | structural requirement |
| `key` and `spec` fields must be present and non-empty strings | required for device instantiation |
| Section name must not contain whitespace | a space would shift `read -r` fields |
| `key` must not contain whitespace | a space in the key shifts bash `read -r` fields, corrupting the alternatives array |
| `spec` must not contain `\n` or `\r` | a newline causes `print()` to emit two physical lines; bash `read -r` then misparses the second fragment as an independent entry |

## Running the tests

The offline test suite for the parser lives in
`tests/offline/test_hw_management_devtree_json_parser.py`.

```bash
# Run all parser tests
python3 -m pytest tests/offline/test_hw_management_devtree_json_parser.py -v

# Print the populated *_alternatives dicts from the inline TEST_BOM
python3 -m pytest tests/offline/test_hw_management_devtree_json_parser.py::TestParserWithDevtreeJson::test_print_alternatives -v -s
```

The test file defines an inline `TEST_BOM` dictionary that mirrors the JSON
format above.  The `devtree_json` pytest fixture writes this dict to a
temporary file, which is then passed to the parser subprocess exactly as
`hw-management-devtree.sh` does at runtime.

Two test classes are provided:

| Class | What it covers |
|-------|---------------|
| `TestParserWithDevtreeJson` | Happy-path: exit code, section/key presence, spec values, line format |
| `TestParserErrorHandling` | Error paths: missing file, bad JSON, wrong types, whitespace in key/section, newline in spec |
