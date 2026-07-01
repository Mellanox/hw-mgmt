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

"""Tests for hw_management_sonic_check.py"""

import sys
import os
import pytest
from unittest.mock import patch
from pathlib import Path

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = (TESTS_DIR / ".." / "..").resolve()
sys.path.insert(0, str(PROJECT_ROOT / "usr" / "usr" / "bin"))

import hw_management_sonic_check as sonic_check


class TestIsSonicOs:
    """Tests for is_sonic_os()."""

    def test_returns_true_when_file_exists(self):
        with patch.object(sonic_check.os.path, 'isfile', return_value=True):
            assert sonic_check.is_sonic_os() is True

    def test_returns_false_when_file_missing(self):
        with patch.object(sonic_check.os.path, 'isfile', return_value=False):
            assert sonic_check.is_sonic_os() is False

    def test_checks_the_right_path(self):
        with patch.object(sonic_check.os.path, 'isfile') as mock_isfile:
            mock_isfile.return_value = True
            sonic_check.is_sonic_os()
            mock_isfile.assert_called_once_with(sonic_check.SONIC_VERSION_FILE)

    def test_sonic_version_file_constant(self):
        assert sonic_check.SONIC_VERSION_FILE == "/etc/sonic/sonic_version.yml"


class TestMain:
    """Tests for main()."""

    def test_returns_0_when_sonic(self, capsys):
        with patch.object(sonic_check.os.path, 'isfile', return_value=True):
            rc = sonic_check.main()
            assert rc == 0

    def test_returns_1_when_not_sonic(self, capsys):
        with patch.object(sonic_check.os.path, 'isfile', return_value=False):
            rc = sonic_check.main()
            assert rc == 1

    def test_prints_true_when_sonic(self, capsys):
        with patch.object(sonic_check.os.path, 'isfile', return_value=True):
            sonic_check.main()
            captured = capsys.readouterr()
            assert "True" in captured.out

    def test_prints_false_when_not_sonic(self, capsys):
        with patch.object(sonic_check.os.path, 'isfile', return_value=False):
            sonic_check.main()
            captured = capsys.readouterr()
            assert "False" in captured.out


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
