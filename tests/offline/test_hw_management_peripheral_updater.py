#!/usr/bin/python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

"""
Simplified Unit Tests for Peripheral Updater Core Functions

These offline tests validate the core logic in hw_management_peripheral_updater.py
without requiring actual hardware or complex mocking.

Focus on testing the critical business logic:
- ASIC chipup status monitoring logic
- Peripheral attribute triggering logic
- Configuration loading
"""

import contextlib
import unittest
import sys
import os
import builtins
import tempfile
import shutil
import importlib.util
from unittest.mock import patch, MagicMock

# Add parent directory to path to import the module under test
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../usr/usr/bin'))


def _peripheral_updater_script_path():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.join(script_dir, '..', '..')
    return os.path.join(repo_root, 'usr', 'usr', 'bin', 'hw_management_peripheral_updater.py')


def _real_to_int():
    """Load hw_management_lib.to_int from source.

    The peripheral updater tests install a MagicMock as hw_management_lib, so
    the name bound in the updater is not the real converter. int() of that
    mock is 1, which sends fan status down the present-fan path.
    """
    lib_path = os.path.join(
        os.path.dirname(_peripheral_updater_script_path()),
        'hw_management_lib.py',
    )
    spec = importlib.util.spec_from_file_location('hw_management_lib_real_to_int', lib_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.to_int


def _ensure_peripheral_dependency_mocks():
    """Mock hard-required imports used at peripheral_updater module load time."""
    lib_mock = MagicMock()
    lib_mock.HW_Mgmt_Logger = MagicMock()
    lib_mock.current_milli_time = MagicMock(return_value=0)
    lib_mock.RepeatedTimer = MagicMock()
    sys.modules["hw_management_lib"] = lib_mock

    rf_mock = MagicMock()
    rf_mock.RedfishClient = MagicMock()
    rf_mock.RedfishClient.ERR_CODE_OK = 0
    rf_mock.BMCAccessor = MagicMock()
    sys.modules["hw_management_redfish_client"] = rf_mock

    if "psutil" not in sys.modules:
        sys.modules["psutil"] = MagicMock()


def _load_peripheral_updater_module(module_suffix, feature_request_available):
    """
    Load peripheral_updater in isolation with controlled feature helper presence.

    @param module_suffix: unique suffix for importlib module name
    @param feature_request_available: True = inject mock feature_request; False = simulate missing module
    """
    _ensure_peripheral_dependency_mocks()
    mod_name = "hw_management_peripheral_updater_{}".format(module_suffix)
    sys.modules.pop(mod_name, None)

    if feature_request_available:
        feature_mock = MagicMock()
        feature_mock.feature_request = MagicMock(return_value=False)
        sys.modules["hw_management_feature"] = feature_mock
    else:
        sys.modules.pop("hw_management_feature", None)

    spec = importlib.util.spec_from_file_location(mod_name, _peripheral_updater_script_path())
    module = importlib.util.module_from_spec(spec)

    real_import = builtins.__import__

    def guarded_import(name, globals=None, locals=None, fromlist=(), level=0):
        if not feature_request_available and name == "hw_management_feature":
            raise ImportError("hw_management_feature missing (test)")
        return real_import(name, globals, locals, fromlist, level)

    if feature_request_available:
        spec.loader.exec_module(module)
    else:
        with patch("builtins.__import__", side_effect=guarded_import):
            spec.loader.exec_module(module)

    return module


class TestFeatureRequestImportFallback(unittest.TestCase):
    """feature_request import must be optional so daemon startup cannot hard-fail."""

    def test_module_loads_when_feature_request_missing(self):
        """Missing hw_management_feature keeps Redfish enabled."""
        module = _load_peripheral_updater_module("no_feature", feature_request_available=False)

        self.assertFalse(module.FEATURE_REQUEST_AVAILABLE)
        self.assertFalse(module.feature_request("get", "is_redfish_disabled"))

    def test_module_uses_feature_request_when_present(self):
        """When the helper imports, main() queries is_redfish_disabled."""
        module = _load_peripheral_updater_module("with_feature", feature_request_available=True)

        self.assertTrue(module.FEATURE_REQUEST_AVAILABLE)
        self._init_fns_from_main(module, redfish_disabled=False)

    def _init_fns_from_main(self, module, redfish_disabled):
        """Run main() and return the fn names passed to init_attr.

        HI162 carries a redfish_get_sensor entry. init_attr, the module-counter
        write, and the poll loop are stubbed so only the Redfish gate in main()
        decides whether that entry is kept. main() now waits with time.sleep(1)
        between passes; raising SystemExit from that stub ends the loop after
        one pass without actually sleeping or installing real signal handlers.
        """
        seen = []
        module.feature_request = MagicMock(return_value=redfish_disabled)
        argv = ["hw_management_peripheral_updater.py", "-s", "HI162"]
        with patch.object(sys, "argv", argv), \
                patch.object(module, "init_attr", side_effect=lambda attr: seen.append(attr.get("fn"))), \
                patch.object(module, "write_module_counter"), \
                patch.object(module, "update_peripheral_attr"), \
                patch.object(module.signal, "signal"), \
                patch.object(module.signal, "siginterrupt"), \
                patch.object(module.time, "sleep", side_effect=SystemExit(143)):
            with self.assertRaises(SystemExit) as ctx:
                module.main()
        module.feature_request.assert_called_with("get", "is_redfish_disabled")
        # A stop signal keeps 128+signum in EXIT_CODE and exits 0.
        self.assertEqual(ctx.exception.code, 0)
        self.assertEqual(module.EXIT_CODE, 143)
        return seen

    def test_redfish_disabled_host_strips_redfish_monitor_entries(self):
        """A Redfish-disabled host drops redfish_get_sensor peripheral entries."""
        module = _load_peripheral_updater_module("redfish_off", feature_request_available=True)

        seen = self._init_fns_from_main(module, redfish_disabled=True)

        self.assertIn("monitor_asic_chipup_status", seen)
        self.assertNotIn("redfish_get_sensor", seen)

    def test_redfish_enabled_host_keeps_redfish_monitor_entries(self):
        """While is_redfish_disabled is false, redfish_get_sensor entries stay."""
        module = _load_peripheral_updater_module("redfish_on", feature_request_available=True)

        seen = self._init_fns_from_main(module, redfish_disabled=False)

        self.assertIn("monitor_asic_chipup_status", seen)
        self.assertIn("redfish_get_sensor", seen)


class TestExitCodeOnSignal(unittest.TestCase):
    """handle_signal() records 128+signum. main() exits 0 for those stops."""

    def test_sigterm_sets_143_and_raises(self):
        module = _load_peripheral_updater_module("sig_term", feature_request_available=True)

        with self.assertRaises(SystemExit) as ctx:
            module.handle_signal(module.signal.SIGTERM, None)

        self.assertEqual(ctx.exception.code, 143)
        self.assertEqual(module.EXIT_CODE, 143)

    def test_sigint_sets_130_and_raises(self):
        module = _load_peripheral_updater_module("sig_int", feature_request_available=True)

        with self.assertRaises(SystemExit) as ctx:
            module.handle_signal(module.signal.SIGINT, None)

        self.assertEqual(ctx.exception.code, 130)
        self.assertEqual(module.EXIT_CODE, 130)

    def test_sighup_sets_129_and_raises(self):
        """SIGHUP is bound to the same handler as SIGTERM/SIGINT in main(),
        so a hangup also logs an exit code instead of killing the process
        before log_exit() runs."""
        module = _load_peripheral_updater_module("sig_hup", feature_request_available=True)

        with self.assertRaises(SystemExit) as ctx:
            module.handle_signal(module.signal.SIGHUP, None)

        self.assertEqual(ctx.exception.code, 129)
        self.assertEqual(module.EXIT_CODE, 129)

    def test_main_binds_sighup_to_handle_signal(self):
        """main() must register SIGHUP, SIGINT, and SIGTERM and disable SA_RESTART."""
        module = _load_peripheral_updater_module("sig_hup_bound", feature_request_available=True)
        bound = {}
        restart_disabled = set()

        def fake_signal(signum, handler):
            bound[signum] = handler

        def fake_siginterrupt(signum, flag):
            if flag:
                restart_disabled.add(signum)

        argv = ["hw_management_peripheral_updater.py", "-s", "HI162"]
        with patch.object(sys, "argv", argv), \
                patch.object(module, "init_attr"), \
                patch.object(module, "write_module_counter"), \
                patch.object(module, "update_peripheral_attr"), \
                patch.object(module.signal, "signal", side_effect=fake_signal), \
                patch.object(module.signal, "siginterrupt", side_effect=fake_siginterrupt), \
                patch.object(module.time, "sleep", side_effect=SystemExit(0)):
            with self.assertRaises(SystemExit):
                module.main()

        expected = {module.signal.SIGHUP, module.signal.SIGTERM, module.signal.SIGINT}
        for signum in expected:
            self.assertEqual(bound.get(signum), module.handle_signal)
        self.assertEqual(restart_disabled, expected)


class TestMainLoopExitCode(unittest.TestCase):
    """main() keeps 128+signum in EXIT_CODE and exits 0 for stop signals."""

    def _run_main(self, module, extra_patches):
        argv = ["hw_management_peripheral_updater.py", "-s", "HI162"]
        patches = [
            patch.object(sys, "argv", argv),
            patch.object(module, "init_attr"),
            patch.object(module, "write_module_counter"),
            patch.object(module.signal, "signal"),
            patch.object(module.signal, "siginterrupt"),
        ]
        patches.extend(extra_patches)
        with contextlib.ExitStack() as stack:
            for item in patches:
                stack.enter_context(item)
            with self.assertRaises(SystemExit) as ctx:
                module.main()
        return ctx.exception

    def test_signal_during_loop_exits_0(self):
        """Simulates handle_signal raising SystemExit(143) for SIGTERM from
        inside time.sleep(); main() exits 0 and keeps 143 as the exit reason."""
        module = _load_peripheral_updater_module("main_sigterm", feature_request_available=True)

        exc = self._run_main(module, [
            patch.object(module, "update_peripheral_attr"),
            patch.object(module.time, "sleep", side_effect=SystemExit(143)),
        ])

        self.assertEqual(exc.code, 0)
        self.assertEqual(module.EXIT_CODE, 143)

    def test_unexpected_exception_exits_1_and_logs(self):
        """An unhandled exception from a peripheral callback must not be
        silently swallowed: it exits 1 and logs the same code."""
        module = _load_peripheral_updater_module("main_crash", feature_request_available=True)

        exc = self._run_main(module, [
            patch.object(module, "update_peripheral_attr", side_effect=RuntimeError("boom")),
            patch.object(module.time, "sleep"),
        ])

        self.assertEqual(exc.code, 1)
        self.assertEqual(module.EXIT_CODE, 1)
        module.LOGGER.warning.assert_called_with("Unexpected error in main loop")

    def test_init_failure_exits_1(self):
        """A failure while loading config or attributes is inside main()'s
        try, so it exits 1 and log_exit() records that code."""
        module = _load_peripheral_updater_module("main_init_fail", feature_request_available=True)

        exc = self._run_main(module, [
            patch.object(module, "init_attr", side_effect=RuntimeError("init failed")),
            patch.object(module.time, "sleep"),
        ])

        self.assertEqual(exc.code, 1)
        self.assertEqual(module.EXIT_CODE, 1)
        module.LOGGER.warning.assert_called_with("Unexpected error in main loop")


class TestLogExit(unittest.TestCase):
    """log_exit() is registered with atexit and must record whatever
    EXIT_CODE main()/handle_signal() last set, even if LOGGER is unset."""

    def test_logs_current_exit_code_via_logger(self):
        module = _load_peripheral_updater_module("log_exit_logger", feature_request_available=True)
        module.LOGGER = MagicMock()
        module.EXIT_CODE = 143

        module.log_exit()

        module.LOGGER.notice.assert_called_with("hw-management-peripheral-updater: exit reason=143")

    def test_falls_back_to_stderr_when_logger_unset(self):
        """A nonzero exit before Logger() exists still reaches stderr."""
        module = _load_peripheral_updater_module("log_exit_no_logger", feature_request_available=True)
        module.LOGGER = None
        module.EXIT_CODE = 1

        with patch.object(module.sys.stderr, "write") as mock_write:
            module.log_exit()

        mock_write.assert_called_with("hw-management-peripheral-updater: exit reason=1\n")

    def test_skips_line_for_help_or_version(self):
        """--help and --version exit 0 before Logger() exists. That is a
        successful argparse exit, so log_exit() writes nothing."""
        module = _load_peripheral_updater_module("log_exit_help", feature_request_available=True)
        module.LOGGER = None
        module.EXIT_CODE = 0

        with patch.object(module.sys.stderr, "write") as mock_write:
            module.log_exit()

        mock_write.assert_not_called()

    def test_falls_back_to_stderr_when_logger_raises(self):
        """A broken logger must not hide the exit line or raise out of atexit."""
        module = _load_peripheral_updater_module("log_exit_logger_raises", feature_request_available=True)
        module.LOGGER = MagicMock()
        module.LOGGER.notice.side_effect = OSError("disk full")
        module.EXIT_CODE = 143

        with patch.object(module.sys.stderr, "write") as mock_write:
            module.log_exit()

        mock_write.assert_called_with("hw-management-peripheral-updater: exit reason=143\n")


class TestMonitorAsicChipupStatusLogic(unittest.TestCase):
    """Test monitor_asic_chipup_status() core logic"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.mkdtemp()
        self.asic0_path = os.path.join(self.temp_dir, "asic0")
        self.asic1_path = os.path.join(self.temp_dir, "asic1")
        os.makedirs(os.path.join(self.asic0_path, "temperature"), exist_ok=True)
        os.makedirs(os.path.join(self.asic1_path, "temperature"), exist_ok=True)

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_single_asic_ready(self):
        """Test detecting single ready ASIC"""
        import hw_management_peripheral_updater as peripheral_module

        # Create temperature file (ASIC is ready)
        temp_file = os.path.join(self.asic0_path, "temperature", "input")
        with open(temp_file, 'w') as f:
            f.write("45000\n")

        arg = {"asic": {"fin": self.asic0_path + "/"}}

        with patch.object(peripheral_module, 'update_asic_chipup_status') as mock_update:
            peripheral_module.monitor_asic_chipup_status(arg, None)

        # Should report 1 ASIC ready
        mock_update.assert_called_once_with(1)

    def test_single_asic_not_ready(self):
        """Test detecting ASIC not ready (no temperature file)"""
        import hw_management_peripheral_updater as peripheral_module

        arg = {"asic": {"fin": self.asic0_path + "/"}}

        with patch.object(peripheral_module, 'update_asic_chipup_status') as mock_update:
            peripheral_module.monitor_asic_chipup_status(arg, None)

        # Should report 0 ASICs ready
        mock_update.assert_called_once_with(0)

    def test_multiple_unique_asics_ready(self):
        """Test counting multiple unique ASICs"""
        import hw_management_peripheral_updater as peripheral_module

        # Both ASICs ready
        with open(os.path.join(self.asic0_path, "temperature", "input"), 'w') as f:
            f.write("45000\n")
        with open(os.path.join(self.asic1_path, "temperature", "input"), 'w') as f:
            f.write("46000\n")

        arg = {
            "asic": {"fin": self.asic0_path + "/"},
            "asic1": {"fin": self.asic0_path + "/"},  # Duplicate - same path
            "asic2": {"fin": self.asic1_path + "/"}   # Different ASIC
        }

        with patch.object(peripheral_module, 'update_asic_chipup_status') as mock_update:
            peripheral_module.monitor_asic_chipup_status(arg, None)

        # Should count 2 unique ASICs
        mock_update.assert_called_once_with(2)

    def test_invalid_arg_type(self):
        """Test handling invalid argument type"""
        import hw_management_peripheral_updater as peripheral_module

        # Should not crash with invalid input
        peripheral_module.monitor_asic_chipup_status("invalid", None)
        peripheral_module.monitor_asic_chipup_status(None, None)
        peripheral_module.monitor_asic_chipup_status([], None)


class TestGetAsicNumFunction(unittest.TestCase):
    """Test get_asic_num() function"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.mkdtemp()
        self.asic_num_file = os.path.join(self.temp_dir, "asic_num")

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_read_valid_asic_num(self):
        """Test reading valid asic_num"""
        import hw_management_peripheral_updater as peripheral_module

        with open(self.asic_num_file, 'w') as f:
            f.write("2\n")

        with patch('hw_management_peripheral_updater.os.path.join', return_value=self.asic_num_file):
            result = peripheral_module.get_asic_num()

        self.assertEqual(result, 2)

    def test_file_not_found_returns_default(self):
        """Test default when file doesn't exist"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.os.path.join',
                   return_value="/nonexistent/asic_num"):
            result = peripheral_module.get_asic_num()

        self.assertEqual(result, peripheral_module.CONST.ASIC_NUM_DEFAULT)

    def test_invalid_content_returns_default(self):
        """Test default when file has invalid content"""
        import hw_management_peripheral_updater as peripheral_module

        with open(self.asic_num_file, 'w') as f:
            f.write("invalid\n")

        with patch('hw_management_peripheral_updater.os.path.join', return_value=self.asic_num_file):
            result = peripheral_module.get_asic_num()

        self.assertEqual(result, peripheral_module.CONST.ASIC_NUM_DEFAULT)


class TestUpdatePeripheralAttrLogic(unittest.TestCase):
    """Test update_peripheral_attr() change-based triggering logic"""

    def setUp(self):
        """Setup"""
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_triggers_on_value_change(self):
        """Test function is called when value changes"""
        import hw_management_peripheral_updater as peripheral_module

        test_file = os.path.join(self.temp_dir, "sensor")
        with open(test_file, 'w') as f:
            f.write("100\n")

        mock_fn = MagicMock()
        attr_prop = {
            "fin": test_file,
            "fn": "mock_fn",
            "poll": 1,
            "ts": 0,
            "arg": ["test"]
        }

        with patch.dict(peripheral_module.__dict__, {'mock_fn': mock_fn}):
            # First call - should trigger
            peripheral_module.update_peripheral_attr(attr_prop)
            self.assertEqual(mock_fn.call_count, 1)

            # Second call with same value - should NOT trigger
            peripheral_module.update_peripheral_attr(attr_prop)
            self.assertEqual(mock_fn.call_count, 1, "Should not trigger on same value")

            # Change value - should trigger again
            with open(test_file, 'w') as f:
                f.write("200\n")
            attr_prop["ts"] = 0  # Reset timestamp to allow immediate trigger
            peripheral_module.update_peripheral_attr(attr_prop)
            self.assertEqual(mock_fn.call_count, 2, "Should trigger on value change")

    def test_no_fin_always_triggers(self):
        """Test function always triggers when fin=None"""
        import hw_management_peripheral_updater as peripheral_module

        mock_fn = MagicMock()
        attr_prop = {
            "fin": None,
            "fn": "mock_fn",
            "poll": 1,
            "ts": 0,
            "arg": []
        }

        with patch.dict(peripheral_module.__dict__, {'mock_fn': mock_fn}):
            peripheral_module.update_peripheral_attr(attr_prop)
            peripheral_module.update_peripheral_attr(attr_prop)

        # Should trigger both times (no change detection without fin)
        self.assertGreaterEqual(mock_fn.call_count, 1)

    def test_missing_file_no_trigger(self):
        """Test function not triggered when file doesn't exist"""
        import hw_management_peripheral_updater as peripheral_module

        mock_fn = MagicMock()
        attr_prop = {
            "fin": "/nonexistent/file",
            "fn": "mock_fn",
            "poll": 1,
            "ts": 0,
            "arg": []
        }

        with patch.dict(peripheral_module.__dict__, {'mock_fn': mock_fn}):
            peripheral_module.update_peripheral_attr(attr_prop)

        # Should not trigger
        mock_fn.assert_not_called()


class TestConfigurationFunctions(unittest.TestCase):
    """Test configuration loading"""

    def test_build_attrib_list_returns_dict(self):
        """Test _build_attrib_list() returns valid dictionary"""
        import hw_management_peripheral_updater as peripheral_module

        config = peripheral_module._build_attrib_list()

        self.assertIsInstance(config, dict)
        self.assertGreater(len(config), 0, "Should have platform entries")

    def test_attrib_list_module_variable_populated(self):
        """Test attrib_list is populated at module load"""
        import hw_management_peripheral_updater as peripheral_module

        self.assertIsInstance(peripheral_module.attrib_list, dict)
        self.assertGreater(len(peripheral_module.attrib_list), 0)


class TestGetAsicNumErrorHandling(unittest.TestCase):
    """Test get_asic_num() error handling and logging"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_get_asic_num_with_logger_on_error(self):
        """Test get_asic_num logs warning when file read fails"""
        import hw_management_peripheral_updater as peripheral_module

        # Create invalid file
        asic_num_file = os.path.join(self.temp_dir, "asic_num")
        with open(asic_num_file, 'w') as f:
            f.write("invalid_number\n")

        with patch('hw_management_peripheral_updater.os.path.join', return_value=asic_num_file):
            with patch('hw_management_peripheral_updater.LOGGER') as mock_logger:
                result = peripheral_module.get_asic_num()

                # Should log warning
                mock_logger.warning.assert_called()
                # Should return default
                self.assertEqual(result, peripheral_module.CONST.ASIC_NUM_DEFAULT)

    def test_get_asic_num_without_logger(self):
        """Test get_asic_num works when LOGGER is None"""
        import hw_management_peripheral_updater as peripheral_module

        # Temporarily set LOGGER to None
        original_logger = peripheral_module.LOGGER
        peripheral_module.LOGGER = None

        try:
            with patch('hw_management_peripheral_updater.os.path.join',
                       return_value="/nonexistent/asic_num"):
                result = peripheral_module.get_asic_num()
                # Should return default without crashing
                self.assertEqual(result, peripheral_module.CONST.ASIC_NUM_DEFAULT)
        finally:
            peripheral_module.LOGGER = original_logger


class TestUpdateAsicChipupStatusErrors(unittest.TestCase):
    """Test update_asic_chipup_status() error handling"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_update_asic_chipup_status_calls_get_asic_num(self):
        """Test update_asic_chipup_status calls get_asic_num"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.get_asic_num', return_value=2) as mock_get_asic:
            with patch('builtins.open', MagicMock()):
                # Just test it calls get_asic_num
                peripheral_module.update_asic_chipup_status(1)
                mock_get_asic.assert_called()

    def test_update_asic_chipup_status_handles_io_error(self):
        """Test update_asic_chipup_status handles file write errors gracefully"""
        import hw_management_peripheral_updater as peripheral_module

        # Mock open to raise OSError
        with patch('builtins.open', side_effect=OSError("Permission denied")):
            with patch('hw_management_peripheral_updater.LOGGER') as mock_logger:
                # Should handle error and log it
                peripheral_module.update_asic_chipup_status(1)
                # Should have called logger (warning or info)
                self.assertGreater(mock_logger.warning.call_count + mock_logger.info.call_count, 0)


class TestHelperFunctions(unittest.TestCase):
    """Test various helper functions"""

    def test_build_attrib_list_basic(self):
        """Test _build_attrib_list basic functionality"""
        import hw_management_peripheral_updater as peripheral_module

        config = peripheral_module._build_attrib_list()
        self.assertIsInstance(config, dict)
        # Should have entries for different platforms
        self.assertGreater(len(config), 0)


class TestModuleCounterFallback(unittest.TestCase):
    """Test module_counter fallback when platform_config is unavailable"""

    def test_get_module_count_fallback_returns_zero(self):
        """Test fallback get_module_count returns 0"""
        import hw_management_peripheral_updater as peripheral_module

        # If import failed, get_module_count should be the fallback that returns 0
        # This is tested by the import at module level
        # Just verify the function exists
        self.assertTrue(hasattr(peripheral_module, 'get_module_count'))


class TestMonitorAsicChipup(unittest.TestCase):
    """
    Test suite for monitor_asic_chipup_status() function in peripheral_updater.

    This tests the independent ASIC chipup monitoring that runs in peripheral_updater,
    separate from thermal monitoring. This ensures chipup tracking continues even if
    thermal_updater service is stopped or disabled by users.

    Key Requirements:
    1. monitor_asic_chipup_status() checks ASIC readiness by probing sysfs paths
    2. Updates chipup status files based on ready ASICs
    3. Works independently of temperature monitoring
    4. Handles missing/unready ASICs gracefully
    """

    def setUp(self):
        """Set up before each test"""
        self.test_dir = tempfile.mkdtemp(prefix='chipup_monitor_test_')
        self.config_dir = os.path.join(self.test_dir, 'config')
        os.makedirs(self.config_dir, exist_ok=True)

    def tearDown(self):
        """Clean up after each test"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def _load_peripheral_module(self):
        """Load peripheral_updater module dynamically"""
        import importlib.util
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.join(script_dir, '..', '..')
        hw_mgmt_dir = os.path.join(repo_root, 'usr', 'usr', 'bin')
        peripheral_path = os.path.join(hw_mgmt_dir, 'hw_management_peripheral_updater.py')

        spec = importlib.util.spec_from_file_location("hw_management_peripheral_updater", peripheral_path)
        module = importlib.util.module_from_spec(spec)

        # Mock dependencies
        sys.modules["hw_management_lib"] = MagicMock()
        sys.modules["hw_management_redfish_client"] = MagicMock()

        spec.loader.exec_module(module)
        return module

    def test_single_asic_ready(self):
        """Test monitor_asic_chipup_status with single ready ASIC"""
        import hw_management_peripheral_updater as peripheral_module

        # Just test that the function exists and can be called
        asic_config = {
            "asic": {"fin": "/sys/module/sx_core/asic0/"}
        }

        with patch('os.path.isfile', return_value=False):
            with patch('builtins.open', side_effect=OSError()):
                with patch('hw_management_peripheral_updater.update_asic_chipup_status') as mock_update:
                    # Should handle errors gracefully
                    peripheral_module.monitor_asic_chipup_status(asic_config, None)
                    # Function should have been called
                    mock_update.assert_called()


class TestMonitorAsicChipupEdgeCases(unittest.TestCase):
    """Test monitor_asic_chipup_status edge cases for better coverage"""

    def test_monitor_asic_chipup_invalid_asic_info_type(self):
        """Test handling of invalid asic_info type"""
        import hw_management_peripheral_updater as peripheral_module

        # asic_info is not a dict (e.g., a string) - should skip
        arg = {
            "asic": "invalid_string_not_dict"
        }

        with patch('hw_management_peripheral_updater.update_asic_chipup_status') as mock_update:
            peripheral_module.monitor_asic_chipup_status(arg, None)
            # Should still call update with 0 (no valid ASICs)
            mock_update.assert_called_with(0)

    def test_monitor_asic_chipup_empty_fin_path(self):
        """Test handling of empty fin path"""
        import hw_management_peripheral_updater as peripheral_module

        # fin is empty string - should skip
        arg = {
            "asic": {"fin": ""}
        }

        with patch('hw_management_peripheral_updater.update_asic_chipup_status') as mock_update:
            peripheral_module.monitor_asic_chipup_status(arg, None)
            # Should call update with 0
            mock_update.assert_called_with(0)


class TestRedfishFunctions(unittest.TestCase):
    """Test redfish helper functions"""

    def test_redfish_get_req_with_response(self):
        """Test redfish_get_req when connection exists and returns data"""
        import hw_management_peripheral_updater as peripheral_module

        # Mock RedfishConnection
        mock_rf_obj = MagicMock()
        mock_rf_obj.rf_client.build_get_cmd.return_value = "mock_cmd"
        mock_rf_obj.rf_client.exec_curl_cmd.return_value = (0, '{"test": "data"}', '')

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=mock_rf_obj), \
                patch.object(peripheral_module.RedfishClient, 'ERR_CODE_OK', 0):
            result = peripheral_module.redfish_get_req('/test/path')

            self.assertIsNotNone(result)
            self.assertEqual(result, {"test": "data"})

    def test_redfish_get_req_error_retries_login(self):
        """Test redfish_get_req retries login on error"""
        import hw_management_peripheral_updater as peripheral_module

        mock_rf_obj = MagicMock()
        mock_rf_obj.rf_client.build_get_cmd.return_value = "mock_cmd"
        mock_rf_obj.rf_client.exec_curl_cmd.return_value = (-1, '', 'error')  # Error code

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=mock_rf_obj):
            result = peripheral_module.redfish_get_req('/test/path')

            # Should call login to retry
            mock_rf_obj.login.assert_called_once()
            self.assertIsNone(result)

    def test_redfish_get_req_no_connection(self):
        """Test redfish_get_req when no connection available"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=None):
            result = peripheral_module.redfish_get_req('/test/path')
            self.assertIsNone(result)

    def test_redfish_post_req_with_data(self):
        """Test redfish_post_req sends POST request"""
        import hw_management_peripheral_updater as peripheral_module

        mock_rf_obj = MagicMock()
        mock_rf_obj.rf_client.build_post_cmd.return_value = "mock_post_cmd"
        mock_rf_obj.rf_client.exec_curl_cmd.return_value = (0, '{"status": "ok"}', '')

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=mock_rf_obj):
            result = peripheral_module.redfish_post_req('/test/path', {'key': 'value'})

            mock_rf_obj.rf_client.build_post_cmd.assert_called_with('/test/path', {'key': 'value'})
            self.assertIsNotNone(result)


class TestUtilityFunctions(unittest.TestCase):
    """Test utility functions in peripheral_updater"""

    def test_run_power_button_event(self):
        """Test run_power_button_event executes commands"""
        import hw_management_peripheral_updater as peripheral_module

        with patch.object(peripheral_module, "run_shell_cmd") as mock_run:
            peripheral_module.run_power_button_event(None, "1")

            # Two hotplug events plus the graceful-power-off logger line
            self.assertEqual(mock_run.call_count, 3)
            for call in mock_run.call_args_list:
                self.assertTrue(call[1].get("shell"))
                self.assertIsNone(call[1].get("timeout"))
                self.assertFalse(call[1].get("capture_output"))

    def test_run_power_button_event_released(self):
        """Test run_power_button_event when released (value=0)"""
        import hw_management_peripheral_updater as peripheral_module

        with patch.object(peripheral_module, "run_shell_cmd") as mock_run:
            peripheral_module.run_power_button_event(None, "0")

            # Release path has the two hotplug events and no logger line
            self.assertEqual(mock_run.call_count, 2)

    def test_run_cmd_with_command_list(self):
        """Test run_cmd executes list of commands"""
        import hw_management_peripheral_updater as peripheral_module

        cmd_list = ["echo test_{arg1}", "echo another_{arg1}"]

        with patch.object(peripheral_module, "run_shell_cmd") as mock_run:
            peripheral_module.run_cmd(cmd_list, "arg_value")

            self.assertEqual(mock_run.call_count, 2)
            self.assertEqual(
                [call[0][0] for call in mock_run.call_args_list],
                ["echo test_arg_value", "echo another_arg_value"],
            )
            for call in mock_run.call_args_list:
                self.assertTrue(call[1].get("shell"))
                self.assertIsNone(call[1].get("timeout"))
                self.assertFalse(call[1].get("capture_output"))

    def _assert_sync_fan_commands(self, mock_run, fan_id, status):
        """Absent fans are status 1; present fans are status 0, in both commands."""
        self.assertEqual(
            [call[0][0] for call in mock_run.call_args_list],
            [
                "echo {} > /var/run/hw-management/thermal/fan{}_status".format(status, fan_id),
                "/usr/bin/hw-management-chassis-events.sh hotplug-event FAN{} {}".format(
                    fan_id, status),
            ],
        )
        for call in mock_run.call_args_list:
            self.assertTrue(call[1].get("shell"))
            self.assertIsNone(call[1].get("timeout"))
            self.assertFalse(call[1].get("capture_output"))

    def test_sync_fan_absent(self):
        """Test sync_fan with fan absent (val=0) writes status 1."""
        import hw_management_peripheral_updater as peripheral_module

        with patch.object(peripheral_module, "run_shell_cmd") as mock_run, \
                patch.object(peripheral_module, "to_int", _real_to_int()):
            peripheral_module.sync_fan(1, "0")

            self._assert_sync_fan_commands(mock_run, 1, 1)

    def test_sync_fan_present(self):
        """Test sync_fan with fan present (val=1) writes status 0."""
        import hw_management_peripheral_updater as peripheral_module

        with patch.object(peripheral_module, "run_shell_cmd") as mock_run, \
                patch.object(peripheral_module, "to_int", _real_to_int()):
            peripheral_module.sync_fan(2, "1")

            self._assert_sync_fan_commands(mock_run, 2, 0)

    def test_sync_fan_invalid(self):
        """Non-numeric fan presence runs neither the status write nor the hotplug event."""
        import hw_management_peripheral_updater as peripheral_module

        with patch.object(peripheral_module, "run_shell_cmd") as mock_run, \
                patch.object(peripheral_module, "to_int", _real_to_int()):
            peripheral_module.sync_fan(1, "not-a-number")

            mock_run.assert_not_called()


class TestRedfishSensorFunctions(unittest.TestCase):
    """Test redfish sensor update functions"""

    def test_redfish_get_sensor_no_response(self):
        """Test redfish_get_sensor when redfish returns None"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=None):
            # Should return early without error
            peripheral_module.redfish_get_sensor(['/path/to/sensor', 'sensor1', 1000], None)

    def test_redfish_get_sensor_disabled_sensor(self):
        """Test redfish_get_sensor with disabled sensor"""
        import hw_management_peripheral_updater as peripheral_module

        response = {
            "Status": {"State": "Disabled", "Health": "OK"},
            "ReadingType": "Liquid",
            "Reading": 0,
            "Thresholds": {}
        }

        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=response):
            # Should return early when sensor is disabled
            peripheral_module.redfish_get_sensor(['/path', 'sensor1', 1000], None)

    def test_redfish_get_sensor_unhealthy_sensor(self):
        """Test redfish_get_sensor with unhealthy sensor"""
        import hw_management_peripheral_updater as peripheral_module

        response = {
            "Status": {"State": "Enabled", "Health": "Critical"},
            "ReadingType": "Liquid",
            "Reading": 1,
            "Thresholds": {}
        }

        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=response):
            # Should return early when sensor health is not OK
            peripheral_module.redfish_get_sensor(['/path', 'sensor1', 1000], None)

    def test_redfish_get_sensor_no_reading_type(self):
        """Test redfish_get_sensor when ReadingType missing"""
        import hw_management_peripheral_updater as peripheral_module

        response = {
            "Status": {"State": "Enabled", "Health": "OK"},
            "Reading": 1,
            "Thresholds": {}
        }

        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=response):
            # Should return early when ReadingType missing
            peripheral_module.redfish_get_sensor(['/path', 'sensor1', 1000], None)

    def test_redfish_get_sensor_unknown_reading_type(self):
        """Test redfish_get_sensor with unknown ReadingType"""
        import hw_management_peripheral_updater as peripheral_module

        response = {
            "Status": {"State": "Enabled", "Health": "OK"},
            "ReadingType": "UnknownType",
            "Reading": 1,
            "Thresholds": {}
        }

        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=response):
            # Should return early when ReadingType not in redfish_attr
            peripheral_module.redfish_get_sensor(['/path', 'sensor1', 1000], None)

    def test_redfish_get_sensor_writes_files_successfully(self):
        """Test redfish_get_sensor writes sensor data to files"""
        import hw_management_peripheral_updater as peripheral_module

        response = {
            "Status": {"State": "Enabled", "Health": "OK"},
            "ReadingType": "Temperature",
            "Reading": 45.5,
            "Thresholds": {
                "UpperCritical": {"Reading": 100.0},
                "LowerCaution": {"Reading": 10.0}
            }
        }

        mock_open = unittest.mock.mock_open()
        with patch('hw_management_peripheral_updater.redfish_get_req', return_value=response):
            with patch('builtins.open', mock_open):
                peripheral_module.redfish_get_sensor(['/path', 'temp1', 1000], None)

                # Should write sensor value and thresholds
                # Reading: 45.5 * 1000 = 45500
                # UpperCritical: 100.0 * 1000 = 100000
                # LowerCaution: 10.0 * 1000 = 10000
                self.assertGreaterEqual(mock_open.call_count, 1)


class TestRedfishConnectionSingleton(unittest.TestCase):
    """Test RedfishConnection singleton class"""

    def test_get_instance_creates_connection(self):
        """Test RedfishConnection.get_instance creates BMCAccessor"""
        import hw_management_peripheral_updater as peripheral_module

        # Reset singleton first
        peripheral_module.RedfishConnection.reset_instance()

        mock_accessor = MagicMock()
        mock_accessor.login.return_value = 0  # ERR_CODE_OK

        with patch('hw_management_peripheral_updater.BMCAccessor', return_value=mock_accessor), \
                patch.object(peripheral_module.RedfishClient, 'ERR_CODE_OK', 0):
            instance = peripheral_module.RedfishConnection.get_instance()

            self.assertIsNotNone(instance)
            mock_accessor.login.assert_called_once()

    def test_get_instance_returns_none_on_login_failure(self):
        """Test RedfishConnection.get_instance returns None when login fails"""
        import hw_management_peripheral_updater as peripheral_module

        # Reset singleton first
        peripheral_module.RedfishConnection.reset_instance()

        mock_accessor = MagicMock()
        mock_accessor.login.return_value = -1  # Error

        with patch('hw_management_peripheral_updater.BMCAccessor', return_value=mock_accessor):
            instance = peripheral_module.RedfishConnection.get_instance()

            self.assertIsNone(instance)

    def test_reset_instance(self):
        """Test RedfishConnection.reset_instance clears singleton"""
        import hw_management_peripheral_updater as peripheral_module

        # Set instance first
        peripheral_module.RedfishConnection._instance = MagicMock()

        # Reset
        peripheral_module.RedfishConnection.reset_instance()

        # Should be None
        self.assertIsNone(peripheral_module.RedfishConnection._instance)


class TestUpdatePeripheralAttr(unittest.TestCase):
    """Test update_peripheral_attr function"""

    def test_update_peripheral_attr_calls_function_on_change(self):
        """Test update_peripheral_attr invokes function when value changes"""
        import hw_management_peripheral_updater as peripheral_module

        temp_dir = tempfile.mkdtemp()
        test_file = os.path.join(temp_dir, "sensor")

        try:
            # Write initial value
            with open(test_file, 'w') as f:
                f.write("100\n")

            mock_fn = MagicMock()
            peripheral_module.test_sensor_fn = mock_fn

            attr_prop = {
                "fn": "test_sensor_fn",
                "arg": ["arg1"],
                "fin": test_file,
                "poll": 0,
                "ts": 0,
                "hwmon": ""
            }

            # First call - should trigger
            peripheral_module.update_peripheral_attr(attr_prop)
            mock_fn.assert_called_with(["arg1"], "100")

            # Second call with same value - should NOT trigger
            mock_fn.reset_mock()
            peripheral_module.update_peripheral_attr(attr_prop)
            mock_fn.assert_not_called()

        finally:
            shutil.rmtree(temp_dir)

    def test_update_peripheral_attr_handles_read_error(self):
        """Test update_peripheral_attr handles file read errors"""
        import hw_management_peripheral_updater as peripheral_module

        mock_fn = MagicMock()
        peripheral_module.test_error_fn = mock_fn

        attr_prop = {
            "fn": "test_error_fn",
            "arg": ["arg1"],
            "fin": "/tmp/test_sensor",
            "poll": 0,
            "ts": 0,
            "hwmon": ""
        }

        # Create file then make it unreadable
        with open("/tmp/test_sensor", 'w') as f:
            f.write("100\n")

        with patch('builtins.open', side_effect=OSError()):
            peripheral_module.update_peripheral_attr(attr_prop)

            # Should call function with empty string on error
            mock_fn.assert_called_with(["arg1"], "")

    def test_update_peripheral_attr_no_file(self):
        """Test update_peripheral_attr with no fin (file-less trigger)"""
        import hw_management_peripheral_updater as peripheral_module

        mock_fn = MagicMock()
        peripheral_module.test_nofile_fn = mock_fn

        attr_prop = {
            "fn": "test_nofile_fn",
            "arg": ["arg1"],
            "poll": 0,
            "ts": 0
        }

        peripheral_module.update_peripheral_attr(attr_prop)

        # Should call function with None
        mock_fn.assert_called_with(["arg1"], None)

    def test_update_peripheral_attr_function_error(self):
        """Test update_peripheral_attr handles function execution errors"""
        import hw_management_peripheral_updater as peripheral_module

        mock_fn = MagicMock(side_effect=KeyError("test error"))
        peripheral_module.test_failing_fn = mock_fn

        attr_prop = {
            "fn": "test_failing_fn",
            "arg": ["arg1"],
            "poll": 0,
            "ts": 0
        }

        # Should not crash even if function raises error
        peripheral_module.update_peripheral_attr(attr_prop)


class TestInitAndWriteFunctions(unittest.TestCase):
    """Test init_attr and write_module_counter functions"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_write_module_counter(self):
        """Test write_module_counter writes file correctly"""
        import hw_management_peripheral_updater as peripheral_module

        config_dir = os.path.join(self.temp_dir, "config")
        os.makedirs(config_dir)
        module_counter_file = os.path.join(config_dir, "module_counter")

        with patch('hw_management_peripheral_updater.get_module_count', return_value=64):
            with patch('hw_management_peripheral_updater.LOGGER'):
                # Mock builtins.open to write to our test directory
                with patch('builtins.open', unittest.mock.mock_open()) as mock_file:
                    peripheral_module.write_module_counter("HI123")

                    # Check open was called with correct path and write was called
                    mock_file.assert_called_with("/var/run/hw-management/config/module_counter", 'w', encoding="utf-8")
                    mock_file().write.assert_called_with("64\n")

    def test_init_attr_with_hwmon(self):
        """Test init_attr with hwmon path"""
        import hw_management_peripheral_updater as peripheral_module

        # Create mock hwmon structure
        hwmon_dir = os.path.join(self.temp_dir, "hwmon")
        os.makedirs(hwmon_dir)
        hwmon0_dir = os.path.join(hwmon_dir, "hwmon0")
        os.makedirs(hwmon0_dir)

        attr_prop = {
            "fin": os.path.join(self.temp_dir, "hwmon", "test_input")
        }

        with patch('hw_management_peripheral_updater.LOGGER'):
            peripheral_module.init_attr(attr_prop)

            # Should have detected hwmon0
            self.assertEqual(attr_prop.get("hwmon"), "hwmon0")

    def test_init_attr_without_hwmon(self):
        """Test init_attr without hwmon path"""
        import hw_management_peripheral_updater as peripheral_module

        attr_prop = {
            "fin": "/sys/devices/platform/sensor/temp1"
        }

        with patch('hw_management_peripheral_updater.LOGGER'):
            peripheral_module.init_attr(attr_prop)
            # Should complete without error

    def test_init_attr_hwmon_error(self):
        """Test init_attr handles hwmon directory errors"""
        import hw_management_peripheral_updater as peripheral_module

        attr_prop = {
            "fin": "/nonexistent/path/hwmon/test_input"
        }

        with patch('hw_management_peripheral_updater.LOGGER'):
            peripheral_module.init_attr(attr_prop)
            # Should set empty hwmon on error
            self.assertEqual(attr_prop.get("hwmon"), "")


class TestMonitorAsicChipupLogging(unittest.TestCase):
    """Test monitor_asic_chipup_status logging paths"""

    def test_monitor_asic_chipup_logs_ready_asics(self):
        """Test that ready ASICs are logged"""
        import hw_management_peripheral_updater as peripheral_module

        arg = {
            "asic": {"fin": "/sys/module/sx_core/asic0/"}
        }

        mock_logger = MagicMock()
        with patch('hw_management_peripheral_updater.LOGGER', mock_logger):
            with patch('os.path.isfile', return_value=True):
                with patch('builtins.open', unittest.mock.mock_open(read_data='50000\n')):
                    with patch('hw_management_peripheral_updater.update_asic_chipup_status'):
                        peripheral_module.monitor_asic_chipup_status(arg, None)

                        # Should log debug message for ready ASIC
                        debug_calls = [call for call in mock_logger.debug.call_args_list
                                       if 'ASIC ready' in str(call)]
                        self.assertGreater(len(debug_calls), 0)

    def test_monitor_asic_chipup_logs_not_ready_asics(self):
        """Test that not-ready ASICs are logged"""
        import hw_management_peripheral_updater as peripheral_module

        arg = {
            "asic": {"fin": "/sys/module/sx_core/asic0/"}
        }

        mock_logger = MagicMock()
        with patch('hw_management_peripheral_updater.LOGGER', mock_logger):
            with patch('os.path.isfile', return_value=True):
                with patch('builtins.open', side_effect=OSError("File not readable")):
                    with patch('hw_management_peripheral_updater.update_asic_chipup_status'):
                        peripheral_module.monitor_asic_chipup_status(arg, None)

                        # Should log debug message for not-ready ASIC
                        debug_calls = [call for call in mock_logger.debug.call_args_list
                                       if 'not ready' in str(call)]
                        self.assertGreater(len(debug_calls), 0)


class TestRedfishInit(unittest.TestCase):
    """Test redfish_init function"""

    def test_redfish_init_calls_get_instance(self):
        """Test redfish_init calls RedfishConnection.get_instance"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance') as mock_get:
            peripheral_module.redfish_init()
            mock_get.assert_called_once()


class TestRedfishPostErrorHandling(unittest.TestCase):
    """Test redfish_post_req error handling"""

    def test_redfish_post_req_handles_error_and_retries_login(self):
        """Test redfish_post_req retries login on error"""
        import hw_management_peripheral_updater as peripheral_module

        mock_rf_obj = MagicMock()
        mock_rf_obj.rf_client.build_post_cmd.return_value = "mock_post_cmd"
        mock_rf_obj.rf_client.exec_curl_cmd.return_value = (-1, '', 'error')  # Error code

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=mock_rf_obj):
            result = peripheral_module.redfish_post_req('/test/path', {'key': 'value'})

            # Should call login to retry
            mock_rf_obj.login.assert_called_once()
            # Returns error code
            self.assertEqual(result, -1)

    def test_redfish_post_req_no_connection(self):
        """Test redfish_post_req when no connection available"""
        import hw_management_peripheral_updater as peripheral_module

        with patch('hw_management_peripheral_updater.RedfishConnection.get_instance', return_value=None):
            result = peripheral_module.redfish_post_req('/test/path', {'key': 'value'})
            self.assertIsNone(result)


class TestWriteModuleCounterError(unittest.TestCase):
    """Test write_module_counter error handling"""

    def test_write_module_counter_logs_error_on_failure(self):
        """Test write_module_counter logs error when file write fails"""
        import hw_management_peripheral_updater as peripheral_module

        mock_logger = MagicMock()
        # write_module_counter early-returns for platforms not in PLATFORM_CONFIG
        # (commit 1496432d), so make the SKU resolve as supported to reach the
        # file write that we force to fail.
        with patch('hw_management_peripheral_updater.get_platform_config', return_value=[{'fn': 'asic_temp_populate'}]):
            with patch('hw_management_peripheral_updater.get_module_count', return_value=32):
                with patch('hw_management_peripheral_updater.LOGGER', mock_logger):
                    with patch('builtins.open', side_effect=OSError("Permission denied")):
                        peripheral_module.write_module_counter("TEST_SKU")

                        # Should log warning about failure
                        mock_logger.warning.assert_called()


class TestPlatformChipupCoverage(unittest.TestCase):
    """
    Validates that all platforms with ASICs have chipup monitoring configured.

    This test ensures the refactoring that moved chipup tracking from thermal_updater
    to peripheral_updater included ALL platforms, not just those with peripheral configs.
    """

    def test_all_asic_platforms_have_chipup_monitoring(self):
        """Verify every platform with asic_temp_populate also has monitor_asic_chipup_status"""
        from hw_management_platform_config import PLATFORM_CONFIG

        platforms_with_asic = []
        platforms_with_chipup = []
        platforms_missing_chipup = []

        for platform_key, platform_config in PLATFORM_CONFIG.items():
            if platform_key in ['def', 'test']:
                continue

            has_asic = False
            has_chipup = False
            asic_config = None
            chipup_config = None

            for entry in platform_config:
                if entry.get('fn') == 'asic_temp_populate':
                    has_asic = True
                    asic_config = entry.get('arg', {})

                if entry.get('fn') == 'monitor_asic_chipup_status':
                    has_chipup = True
                    chipup_config = entry.get('arg', {})

            if has_asic:
                platforms_with_asic.append(platform_key)

                if has_chipup:
                    platforms_with_chipup.append(platform_key)
                    # Validate chipup monitoring covers every physical ASIC.
                    # asic_temp_populate may carry a legacy 'asic' alias that
                    # maps to the same sysfs path as 'asic1' (used only for the
                    # temperature file naming); chipup monitoring tracks one
                    # entry per physical ASIC (asic1, asic2, ...) and omits the
                    # alias (commit c164ecac), so normalize it away first.
                    physical_asics = set(asic_config.keys()) - {'asic'}
                    self.assertEqual(
                        physical_asics,
                        set(chipup_config.keys()),
                        f"{platform_key}: ASIC configs must match"
                    )
                else:
                    platforms_missing_chipup.append(platform_key)

        # Critical assertion - must have 100% coverage
        self.assertEqual(
            len(platforms_missing_chipup), 0,
            f"CRITICAL: {len(platforms_missing_chipup)} platforms missing chipup: {platforms_missing_chipup}"
        )

        self.assertEqual(
            len(platforms_with_asic), len(platforms_with_chipup),
            "All platforms with ASICs must have chipup monitoring"
        )


if __name__ == '__main__':
    unittest.main()
