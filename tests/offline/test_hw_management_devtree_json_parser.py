#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#

"""
Tests for hw-management-devtree-json-parser.py

Mirrors the invocation used in hw-management-devtree.sh:

    devtree_json_parser=/usr/bin/hw-management-devtree-json-parser.py

    output=$($devtree_json_parser "$json_file")
    while read -r section key spec; do
        local -n _arr="${section}_alternatives"
        _arr["$key"]="$spec"
        unset -n _arr
    done <<< "$output"

The parser is invoked via subprocess with a JSON file path; its stdout is
parsed line-by-line into <section>_alternatives dicts.  A simplified
devtree.json defined inline in this file (TEST_BOM) is used as the test
input, written to a temporary file by the devtree_json fixture.

To print the populated <section>_alternatives contents, run:
    python3 -m pytest tests/offline/test_hw_management_devtree_json_parser.py::TestParserWithDevtreeJson::test_print_alternatives -v -s
"""

import importlib.util
import json
import subprocess
import sys
import pytest
from pathlib import Path


TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = (TESTS_DIR / ".." / "..").resolve()
PARSER = PROJECT_ROOT / "usr" / "usr" / "bin" / "hw-management-devtree-json-parser.py"

# Import module directly for unit tests (gives coverage without subprocess overhead)
_spec = importlib.util.spec_from_file_location("devtree_json_parser", str(PARSER))
_parser_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_parser_mod)
validate_bom = _parser_mod.validate_bom

# Simplified devtree BOM used as the test input.
# Mirrors the structure of usr/etc/hw-management-cfg/HI195/devtree.json
# with a representative subset of entries for each section.
TEST_BOM = {
    "swb": [
        {"key": "mp29816_0", "spec": "mp29816 0x61 15 voltmon1"},
        {"key": "mp29816_1", "spec": "mp29816 0x62 15 voltmon2"},
        {"key": "xdpe1a2g7_0", "spec": "xdpe1a2g7b 0x61 15 voltmon1"},
        {"key": "24c512_0", "spec": "24c512 0x51 24 swb_info"},
    ],
    "port": [
        {"key": "mp29816_0", "spec": "mp29816 0x68 15 voltmon19"},
        {"key": "xdpe1a2g7_0", "spec": "xdpe1a2g7b 0x68 15 voltmon19"},
    ],
    "pwr": [
        {"key": "raa228004_0", "spec": "raa228004 0x60 6 pdb_pwr_conv1"},
        {"key": "mp29502_0", "spec": "mp29502 0x2e 6 pdb_pwr_conv1"},
        {"key": "tmp451_0", "spec": "tmp451 0x4c 6 pdb_temp1"},
    ],
    "platform": [
        {"key": "24c512_1", "spec": "24c512 0x51 1 vpd_info"},
        {"key": "jc42_0", "spec": "jc42 0x52 10 sodimm_temp1"},
        {"key": "mp2845_0", "spec": "mp2845 0x69 5 comex_voltmon1"},
    ],
}


@pytest.fixture(scope="module")
def devtree_json(tmp_path_factory):
    """Write TEST_BOM to a temporary JSON file and return its path."""
    path = tmp_path_factory.mktemp("devtree") / "devtree.json"
    path.write_text(json.dumps(TEST_BOM, indent=4))
    return path


def run_parser(json_file):
    """
    Invoke the parser the same way hw-management-devtree.sh does:
        output=$($devtree_json_parser "$json_file")
    Returns (stdout, stderr, returncode).
    """
    result = subprocess.run(
        [sys.executable, str(PARSER), str(json_file)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.decode(), result.stderr.decode(), result.returncode


def parse_into_alternatives(output):
    """
    Mirror the bash while-read loop in devtr_bom_load_from_json():
        while read -r section key spec; do
            _arr["$key"]="$spec"
        done
    Returns a dict of dicts: { section: { key: spec, ... }, ... }
    """
    alternatives = {}
    for line in output.splitlines():
        parts = line.split(None, 2)
        if len(parts) != 3:
            continue
        section, key, spec = parts
        alternatives.setdefault(section, {})[key] = spec
    return alternatives


class TestParserWithDevtreeJson:
    """Tests using the inline TEST_BOM devtree.json as input."""

    @pytest.fixture(autouse=True)
    def check_parser(self):
        if not PARSER.exists():
            pytest.skip(f"Parser not found: {PARSER}")

    def test_parser_exits_zero(self, devtree_json):
        """Parser must exit 0 on a valid JSON file."""
        _, _, rc = run_parser(devtree_json)
        assert rc == 0

    def test_output_matches_json_sections(self, devtree_json):
        """All sections present in the JSON must appear in the parser output."""
        stdout, _, rc = run_parser(devtree_json)
        assert rc == 0
        alternatives = parse_into_alternatives(stdout)
        for section in TEST_BOM:
            assert section in alternatives, f"Section '{section}' missing from parser output"

    def test_all_keys_present(self, devtree_json):
        """Every key defined in TEST_BOM must appear in the parsed alternatives."""
        stdout, _, _ = run_parser(devtree_json)
        alternatives = parse_into_alternatives(stdout)
        for section, entries in TEST_BOM.items():
            for entry in entries:
                key = entry["key"]
                assert key in alternatives.get(section, {}), (
                    f"Key '{key}' missing from {section}_alternatives"
                )

    def test_spec_values_match(self, devtree_json):
        """The spec value for every key must match TEST_BOM exactly."""
        stdout, _, _ = run_parser(devtree_json)
        alternatives = parse_into_alternatives(stdout)
        for section, entries in TEST_BOM.items():
            for entry in entries:
                key, expected_spec = entry["key"], entry["spec"]
                actual_spec = alternatives.get(section, {}).get(key)
                assert actual_spec == expected_spec, (
                    f"{section}['{key}']: expected '{expected_spec}', got '{actual_spec}'"
                )

    def test_output_line_format(self, devtree_json):
        """Every output line must have exactly three whitespace-separated fields."""
        stdout, _, rc = run_parser(devtree_json)
        assert rc == 0
        for line in stdout.splitlines():
            parts = line.split(None, 2)
            assert len(parts) == 3, f"Unexpected line format: {line!r}"

    def test_expected_sections_present(self, devtree_json):
        """TEST_BOM must produce swb, port, pwr and platform alternatives."""
        stdout, _, rc = run_parser(devtree_json)
        assert rc == 0
        alternatives = parse_into_alternatives(stdout)
        for section in ("swb", "port", "pwr", "platform"):
            assert section in alternatives, f"Expected section '{section}' not found"

    def test_print_alternatives(self, devtree_json):
        """Print the contents of each <section>_alternatives dict."""
        stdout, _, rc = run_parser(devtree_json)
        assert rc == 0
        alternatives = parse_into_alternatives(stdout)
        for section, entries in sorted(alternatives.items()):
            print(f"\n{section}_alternatives:")
            for key, spec in sorted(entries.items()):
                print(f"  [{key}] = {spec}")


class TestParserErrorHandling:
    """Tests that the parser rejects invalid inputs."""

    @pytest.fixture(autouse=True)
    def check_parser(self):
        if not PARSER.exists():
            pytest.skip(f"Parser not found: {PARSER}")

    def test_missing_file(self, tmp_path):
        """Parser must exit non-zero when the file does not exist."""
        _, _, rc = run_parser(tmp_path / "nonexistent.json")
        assert rc != 0

    def test_syntax_error(self, tmp_path):
        """Parser must exit non-zero on malformed JSON."""
        bad = tmp_path / "bad.json"
        bad.write_text("{ not valid json }")
        _, _, rc = run_parser(bad)
        assert rc != 0

    def test_wrong_top_level_type(self, tmp_path):
        """Parser must exit non-zero when top-level value is not an object."""
        bad = tmp_path / "bad.json"
        bad.write_text('["not", "an", "object"]')
        _, _, rc = run_parser(bad)
        assert rc != 0

    def test_section_not_a_list(self, tmp_path):
        """Parser must exit non-zero when a section value is not an array."""
        bad = tmp_path / "bad.json"
        bad.write_text('{"swb": "should be a list"}')
        _, _, rc = run_parser(bad)
        assert rc != 0

    def test_entry_missing_key_field(self, tmp_path):
        """Parser must exit non-zero when an entry is missing the 'key' field."""
        bad = tmp_path / "bad.json"
        bad.write_text('{"swb": [{"spec": "mp29816 0x61 15 voltmon1"}]}')
        _, _, rc = run_parser(bad)
        assert rc != 0

    def test_entry_missing_spec_field(self, tmp_path):
        """Parser must exit non-zero when an entry is missing the 'spec' field."""
        bad = tmp_path / "bad.json"
        bad.write_text('{"swb": [{"key": "mp29816_0"}]}')
        _, _, rc = run_parser(bad)
        assert rc != 0

    def test_no_arguments(self):
        """Parser must exit non-zero when called with no arguments."""
        result = subprocess.run(
            [sys.executable, str(PARSER)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert result.returncode != 0

    def test_error_output_goes_to_stderr(self, tmp_path):
        """Error messages must be printed to stderr, not stdout."""
        bad = tmp_path / "bad.json"
        bad.write_text("{ invalid }")
        stdout, stderr, rc = run_parser(bad)
        assert rc != 0
        assert stdout == ""
        assert stderr != ""

    def test_key_with_embedded_whitespace_rejected(self, tmp_path):
        """Parser must exit non-zero when a key contains embedded whitespace.
        A space in the key shifts bash read -r fields: key='mp29816', spec='extra ...'
        instead of the correct key='mp29816 extra'."""
        bad = tmp_path / "bad.json"
        bad.write_text('{"swb": [{"key": "mp29816 extra", "spec": "mp29816 0x61 15 voltmon1"}]}')
        _, _, rc = run_parser(bad)
        assert rc != 0

    def test_section_name_with_whitespace_rejected(self, tmp_path):
        """Parser must exit non-zero when a section name contains whitespace.
        A space in a section name shifts bash read -r fields: section='my',
        key='section', losing the real key and spec entirely."""
        bad = tmp_path / "bad.json"
        bad.write_text('{"my section": [{"key": "mp29816_0", "spec": "mp29816 0x61 15 voltmon1"}]}')
        _, _, rc = run_parser(bad)
        assert rc != 0

    def test_spec_with_embedded_newline_rejected(self, tmp_path):
        """Parser must exit non-zero when spec contains an embedded newline.
        A newline in spec causes print() to emit two physical lines; bash
        read -r then misparses the second fragment as an independent entry,
        e.g. section='0x61', key='15', spec='voltmon1', silently corrupting
        the alternatives array.
        json.dumps() is used to produce a valid JSON encoding of the newline
        (\n escape) so that json.load() successfully decodes it and passes
        the string with the embedded newline to validate_bom()."""
        bad = tmp_path / "bad.json"
        payload = json.dumps({"swb": [{"key": "mp29816_0", "spec": "mp29816\n0x61 15 voltmon1"}]})
        bad.write_text(payload)
        _, _, rc = run_parser(bad)
        assert rc != 0


class TestValidateBomDirect:
    """Direct unit tests for validate_bom() — no subprocess, so coverage is tracked."""

    def test_valid_bom_does_not_raise(self):
        validate_bom({"swb": [{"key": "dev0", "spec": "mp29816 0x61 15 voltmon1"}]})

    def test_non_dict_raises(self):
        with pytest.raises(ValueError, match="must be a JSON object"):
            validate_bom(["not", "a", "dict"])

    def test_section_not_list_raises(self):
        with pytest.raises(ValueError, match="expected an array"):
            validate_bom({"swb": "should be list"})

    def test_entry_not_dict_raises(self):
        with pytest.raises(ValueError, match="expected an object"):
            validate_bom({"swb": ["not a dict"]})

    def test_missing_key_field_raises(self):
        with pytest.raises(ValueError, match="missing required field 'key'"):
            validate_bom({"swb": [{"spec": "mp29816 0x61 15 voltmon1"}]})

    def test_missing_spec_field_raises(self):
        with pytest.raises(ValueError, match="missing required field 'spec'"):
            validate_bom({"swb": [{"key": "dev0"}]})

    def test_key_with_whitespace_raises(self):
        with pytest.raises(ValueError, match="must not contain whitespace"):
            validate_bom({"swb": [{"key": "dev 0", "spec": "mp29816 0x61 15 voltmon1"}]})

    def test_section_name_with_whitespace_raises(self):
        with pytest.raises(ValueError, match="must not contain whitespace"):
            validate_bom({"my section": [{"key": "dev0", "spec": "mp29816 0x61 15 voltmon1"}]})

    def test_spec_with_newline_raises(self):
        with pytest.raises(ValueError, match="must not contain newlines"):
            validate_bom({"swb": [{"key": "dev0", "spec": "mp29816\n0x61 15 voltmon1"}]})

    def test_spec_with_carriage_return_raises(self):
        with pytest.raises(ValueError, match="must not contain newlines"):
            validate_bom({"swb": [{"key": "dev0", "spec": "mp29816\r0x61"}]})

    def test_empty_key_raises(self):
        with pytest.raises(ValueError):
            validate_bom({"swb": [{"key": "", "spec": "mp29816 0x61 15 voltmon1"}]})

    def test_empty_spec_raises(self):
        with pytest.raises(ValueError):
            validate_bom({"swb": [{"key": "dev0", "spec": ""}]})

    def test_multiple_sections_valid(self):
        validate_bom({
            "swb": [{"key": "dev0", "spec": "mp29816 0x61 15 voltmon1"}],
            "port": [{"key": "dev1", "spec": "mp2975 0x68 15 voltmon19"}],
        })

    def test_empty_section_list_is_valid(self):
        validate_bom({"swb": []})


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
