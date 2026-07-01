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

"""Tests for hw-management-pmbus-devices-dump.py"""

import sys
import json
import subprocess
import pytest
from unittest.mock import patch, MagicMock, mock_open
from pathlib import Path

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = (TESTS_DIR / ".." / "..").resolve()
sys.path.insert(0, str(PROJECT_ROOT / "usr" / "usr" / "bin"))

import importlib.util
_spec = importlib.util.spec_from_file_location(
    "pmbus_devices_dump",
    str(PROJECT_ROOT / "usr" / "usr" / "bin" / "hw-management-pmbus-devices-dump.py")
)
pmbus_multi = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pmbus_multi)


VALID_DEVICE = {"BusNumber": "1", "SlaveAddr": "0x40", "NumPages": "1"}


class TestValidateDevice:
    """Tests for validate_device()."""

    def test_valid_device_returns_tuple(self):
        bus, addr, pages = pmbus_multi.validate_device(VALID_DEVICE, 0)
        assert bus == 1
        assert addr == 0x40
        assert pages == 1

    def test_missing_field_raises(self):
        with pytest.raises(ValueError, match="Missing required field"):
            pmbus_multi.validate_device({"BusNumber": "1", "SlaveAddr": "0x40"}, 0)

    def test_invalid_bus_string_raises(self):
        dev = {**VALID_DEVICE, "BusNumber": "not_a_number"}
        with pytest.raises(ValueError, match="Invalid BusNumber"):
            pmbus_multi.validate_device(dev, 0)

    def test_bus_out_of_range_raises(self):
        dev = {**VALID_DEVICE, "BusNumber": "256"}
        with pytest.raises(ValueError, match="BusNumber must be between"):
            pmbus_multi.validate_device(dev, 0)

    def test_bus_negative_raises(self):
        dev = {**VALID_DEVICE, "BusNumber": "-1"}
        with pytest.raises(ValueError, match="BusNumber must be between"):
            pmbus_multi.validate_device(dev, 0)

    def test_invalid_slave_addr_raises(self):
        dev = {**VALID_DEVICE, "SlaveAddr": "not_hex"}
        with pytest.raises(ValueError, match="Invalid SlaveAddr"):
            pmbus_multi.validate_device(dev, 0)

    def test_slave_addr_reserved_low_raises(self):
        dev = {**VALID_DEVICE, "SlaveAddr": "0x07"}
        with pytest.raises(ValueError, match="SlaveAddr must be between"):
            pmbus_multi.validate_device(dev, 0)

    def test_slave_addr_reserved_high_raises(self):
        dev = {**VALID_DEVICE, "SlaveAddr": "0x78"}
        with pytest.raises(ValueError, match="SlaveAddr must be between"):
            pmbus_multi.validate_device(dev, 0)

    def test_slave_addr_decimal_string(self):
        dev = {**VALID_DEVICE, "SlaveAddr": "64"}
        bus, addr, pages = pmbus_multi.validate_device(dev, 0)
        assert addr == 64

    def test_invalid_pages_raises(self):
        dev = {**VALID_DEVICE, "NumPages": "bad"}
        with pytest.raises(ValueError, match="Invalid NumPages"):
            pmbus_multi.validate_device(dev, 0)

    def test_pages_out_of_range_high_raises(self):
        dev = {**VALID_DEVICE, "NumPages": "33"}
        with pytest.raises(ValueError, match="NumPages must be between"):
            pmbus_multi.validate_device(dev, 0)

    def test_pages_out_of_range_low_raises(self):
        dev = {**VALID_DEVICE, "NumPages": "0"}
        with pytest.raises(ValueError, match="NumPages must be between"):
            pmbus_multi.validate_device(dev, 0)

    def test_slave_addr_integer_type(self):
        dev = {**VALID_DEVICE, "SlaveAddr": 0x40}
        bus, addr, pages = pmbus_multi.validate_device(dev, 0)
        assert addr == 0x40


class TestLoadDevicesConfig:
    """Tests for load_devices_config()."""

    def test_array_format(self, tmp_path):
        cfg = tmp_path / "devices.json"
        cfg.write_text(json.dumps([VALID_DEVICE]))
        devices = pmbus_multi.load_devices_config(str(cfg))
        assert len(devices) == 1

    def test_object_with_devices_key(self, tmp_path):
        cfg = tmp_path / "devices.json"
        cfg.write_text(json.dumps({"devices": [VALID_DEVICE]}))
        devices = pmbus_multi.load_devices_config(str(cfg))
        assert len(devices) == 1

    def test_file_not_found_raises(self):
        with pytest.raises(FileNotFoundError):
            pmbus_multi.load_devices_config("/nonexistent/path.json")

    def test_bad_json_raises(self, tmp_path):
        cfg = tmp_path / "bad.json"
        cfg.write_text("{not valid json}")
        with pytest.raises(ValueError, match="Invalid JSON"):
            pmbus_multi.load_devices_config(str(cfg))

    def test_top_level_neither_list_nor_dict_raises(self, tmp_path):
        cfg = tmp_path / "bad.json"
        cfg.write_text('"just a string"')
        with pytest.raises(ValueError):
            pmbus_multi.load_devices_config(str(cfg))

    def test_empty_list_raises(self, tmp_path):
        cfg = tmp_path / "empty.json"
        cfg.write_text("[]")
        with pytest.raises(ValueError, match="No devices"):
            pmbus_multi.load_devices_config(str(cfg))

    def test_devices_not_a_list_raises(self, tmp_path):
        cfg = tmp_path / "bad.json"
        cfg.write_text('{"devices": "not_a_list"}')
        with pytest.raises(ValueError, match="must be an array"):
            pmbus_multi.load_devices_config(str(cfg))

    def test_multiple_devices(self, tmp_path):
        cfg = tmp_path / "devices.json"
        cfg.write_text(json.dumps([VALID_DEVICE, {**VALID_DEVICE, "SlaveAddr": "0x41"}]))
        devices = pmbus_multi.load_devices_config(str(cfg))
        assert len(devices) == 2


class TestDumpDevice:
    """Tests for dump_device()."""

    def _make_result(self, returncode=0, stderr=""):
        m = MagicMock()
        m.returncode = returncode
        m.stderr = stderr
        return m

    def test_success_returns_true(self):
        with patch("subprocess.run", return_value=self._make_result()):
            assert pmbus_multi.dump_device(1, 0x40, 1, "/path/to/script", None) is True

    def test_failure_returns_false(self):
        with patch("subprocess.run", return_value=self._make_result(returncode=1)):
            assert pmbus_multi.dump_device(1, 0x40, 1, "/path/to/script", None) is False

    def test_timeout_returns_false(self):
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd="script", timeout=300)):
            assert pmbus_multi.dump_device(1, 0x40, 1, "/path/to/script", None) is False

    def test_exception_returns_false(self):
        with patch("subprocess.run", side_effect=Exception("unexpected")):
            assert pmbus_multi.dump_device(1, 0x40, 1, "/path/to/script", None) is False

    def test_stderr_is_logged(self, capsys):
        with patch("subprocess.run", return_value=self._make_result(stderr="some warning")):
            pmbus_multi.dump_device(1, 0x40, 1, "/path/to/script", None)
            captured = capsys.readouterr()
            assert "some warning" in captured.err


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
