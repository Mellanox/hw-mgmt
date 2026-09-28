#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause
#
# Unit tests for hw_management_os_api: SONiC detection, the os_api_get()
# dispatcher and the CLI used by the shell helpers.

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = TESTS_DIR.parent.parent
HW_MGMT_BIN = PROJECT_ROOT / "usr" / "usr" / "bin"
if str(HW_MGMT_BIN) not in sys.path:
    sys.path.insert(0, str(HW_MGMT_BIN))

import hw_management_os_api as os_api  # noqa: E402

pytestmark = pytest.mark.offline


def _sonic_host(manifest_exists, show_on_path):
    """Patch the filesystem and PATH lookups that is_sonic_os() relies on."""
    return (
        patch.object(os_api.os.path, "isfile", return_value=manifest_exists),
        patch.object(os_api.shutil, "which",
                     return_value="/usr/local/bin/show" if show_on_path else None),
    )


class TestIsSonicOs:
    """is_sonic_os(): manifest file AND the 'show' executable are required."""

    @pytest.mark.parametrize("manifest_exists, show_on_path, expected", [
        (True, True, True),
        (True, False, False),
        (False, True, False),
        (False, False, False),
    ])
    def test_detection_matrix(self, manifest_exists, show_on_path, expected):
        isfile, which = _sonic_host(manifest_exists, show_on_path)
        with isfile, which:
            assert os_api.is_sonic_os() is expected

    def test_checks_sonic_manifest_path(self):
        isfile, which = _sonic_host(False, True)
        with isfile as isfile_mock, which:
            os_api.is_sonic_os()
        isfile_mock.assert_called_once_with(os_api.SONIC_VERSION_FILE)

    def test_show_lookup_skipped_without_manifest(self):
        isfile, which = _sonic_host(False, True)
        with isfile, which as which_mock:
            os_api.is_sonic_os()
        which_mock.assert_not_called()


class TestOsApiGet:
    """os_api_get() dispatches by name and follows is_sonic_os()."""

    @pytest.mark.parametrize("api_name", ["is_usb0_managed_by_nos", "is_redfish_disabled"])
    @pytest.mark.parametrize("sonic", [True, False])
    def test_checks_follow_sonic_detection(self, api_name, sonic):
        with patch.object(os_api, "is_sonic_os", return_value=sonic):
            assert os_api.os_api_get(api_name) is sonic

    def test_extra_args_are_ignored_by_checks(self):
        with patch.object(os_api, "is_sonic_os", return_value=True):
            assert os_api.os_api_get("is_usb0_managed_by_nos", "aaa", "bbb") is True

    def test_unknown_api_raises(self):
        with pytest.raises(ValueError, match="Unknown OS API"):
            os_api.os_api_get("no_such_check")

    def test_api_table_exposes_expected_checks(self):
        assert set(os_api.OS_API) == {"is_usb0_managed_by_nos", "is_redfish_disabled"}


class TestCli:
    """main(): prints True/False and returns a shell-friendly exit code."""

    @pytest.mark.parametrize("api_name", ["is_usb0_managed_by_nos", "is_redfish_disabled"])
    @pytest.mark.parametrize("sonic, exit_code, printed", [
        (True, 0, "True"),
        (False, 1, "False"),
    ])
    def test_exit_code_and_output(self, api_name, sonic, exit_code, printed, capsys):
        with patch.object(sys, "argv", ["hw_management_os_api.py", api_name]), \
                patch.object(os_api, "is_sonic_os", return_value=sonic):
            assert os_api.main() == exit_code
        assert capsys.readouterr().out.strip() == printed

    def test_extra_cli_args_are_accepted(self, capsys):
        argv = ["hw_management_os_api.py", "is_usb0_managed_by_nos", "aaa", "bbb"]
        with patch.object(sys, "argv", argv), \
                patch.object(os_api, "is_sonic_os", return_value=True):
            assert os_api.main() == 0
        assert capsys.readouterr().out.strip() == "True"

    def test_unknown_check_is_rejected_by_argparse(self):
        with patch.object(sys, "argv", ["hw_management_os_api.py", "bogus"]):
            with pytest.raises(SystemExit) as exc:
                os_api.main()
        assert exc.value.code == 2
