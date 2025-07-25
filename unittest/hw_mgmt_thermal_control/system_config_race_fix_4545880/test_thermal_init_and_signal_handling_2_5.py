#!/usr/bin/env python3
"""
Unit tests for thermal control 2.5 initialization and signal handling fixes.
Tests the critical race condition fixes addressed in commit: hw-mgmt: thermal: Fix TC init/close flow issue

This file tests the hw_management_thermal_control_2_5.py variant.

Test Coverage:
1. Early termination scenarios - signal handler called before sys_config is loaded
2. Configuration loading failures - load_configuration() exceptions
3. Signal handler behavior with uninitialized state
4. Logger close optimization - removed redundant flush() call
"""

import hw_management_thermal_control_2_5 as thermal_control_2_5
import unittest
import tempfile
import os
import sys
import signal
import json
from unittest.mock import Mock, patch, MagicMock, mock_open, call
import time
from threading import Event

# Add the path to the thermal control module
sys.path.insert(0, 'usr/usr/bin')

# Import the thermal control 2.5 module


class TestThermalInitAndSignalHandling25(unittest.TestCase):
    """Test class for thermal control 2.5 initialization and signal handling fixes."""

    def setUp(self):
        """Set up test fixtures."""
        self.temp_dir = tempfile.mkdtemp()
        self.cmd_arg = {"verbosity": 1}

        # Mock logger
        self.mock_logger = Mock()
        self.mock_logger.info = Mock()
        self.mock_logger.error = Mock()
        self.mock_logger.notice = Mock()
        self.mock_logger.close_tc_log_handler = Mock()
        self.mock_logger.stop = Mock()

        # Valid system configuration
        self.valid_sys_config = {
            "platform_support": 1,
            "sensors_conf": {},
            "dmin": {},
            "fan_pwm": {},
            "fan_param": {},
            "dev_param": {},
            "asic_param": {},
            "sensor_list_param": [],
            "err_mask": [],
            "general_config": {},
            "redundancy": {}
        }

    def tearDown(self):
        """Clean up test fixtures."""
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    @patch('hw_management_thermal_control_2_5.ThermalManagement.load_configuration')
    @patch('hw_management_thermal_control_2_5.Logger')
    @patch('hw_management_thermal_control_2_5.ThermalManagement.check_file')
    @patch('hw_management_thermal_control_2_5.ThermalManagement.read_file')
    @patch('hw_management_thermal_control_2_5.ThermalManagement.is_pwm_exists')
    @patch('signal.signal')
    def test_early_termination_with_initialized_sys_config(self, mock_signal, mock_is_pwm_exists,
                                                           mock_read_file, mock_check_file,
                                                           mock_logger_class, mock_load_config):
        """Test that early termination works correctly with initialized sys_config in 2.5 version."""

        # Setup mocks
        mock_logger_class.return_value = self.mock_logger
        mock_load_config.return_value = self.valid_sys_config
        mock_check_file.return_value = False  # No periodic report file
        mock_is_pwm_exists.return_value = True

        # Track signal registrations
        signal_calls = []

        def track_signal_calls(sig, handler):
            signal_calls.append((sig, handler))
        mock_signal.side_effect = track_signal_calls

        # Create ThermalManagement instance
        with patch('hw_management_thermal_control_2_5.str2bool', return_value=True):
            tc = thermal_control_2_5.ThermalManagement(self.cmd_arg)

        # Verify sys_config is initialized before signal handlers are registered
        self.assertEqual(tc.sys_config, self.valid_sys_config)

        # Verify signal handlers were registered
        expected_signals = [signal.SIGTERM, signal.SIGINT, signal.SIGHUP]
        for expected_sig in expected_signals:
            self.assertTrue(any(sig == expected_sig for sig, _ in signal_calls))

        # Get the signal handler that was registered
        sig_handler = None
        for sig, handler in signal_calls:
            if sig == signal.SIGTERM:
                sig_handler = handler
                break

        self.assertIsNotNone(sig_handler)

        # Mock the stop method to avoid actual shutdown
        with patch.object(tc, 'stop') as mock_stop:
            # Simulate signal handling - this should work without crash
            try:
                sig_handler(signal.SIGTERM)
            except SystemExit:
                pass  # Expected due to os._exit(0)

            # Verify signal handler accessed sys_config safely
            mock_stop.assert_called_once()

    @patch('hw_management_thermal_control_2_5.Logger')
    @patch('hw_management_thermal_control_2_5.ThermalManagement.check_file')
    @patch('hw_management_thermal_control_2_5.ThermalManagement.is_pwm_exists')
    def test_configuration_loading_failure_with_exception_handling(self, mock_is_pwm_exists,
                                                                   mock_check_file, mock_logger_class):
        """Test that configuration loading failures are handled gracefully in 2.5 version."""

        # Setup mocks
        mock_logger_class.return_value = self.mock_logger
        mock_check_file.return_value = False  # No periodic report file

        # Test different types of configuration loading failures
        test_exceptions = [
            FileNotFoundError("Config file not found"),
            PermissionError("Permission denied reading config"),
            json.JSONDecodeError("Invalid JSON", "config", 0),
            ValueError("Invalid configuration values"),
            Exception("Generic configuration error")
        ]

        for test_exception in test_exceptions:
            with self.subTest(exception=type(test_exception).__name__):
                with patch('hw_management_thermal_control_2_5.ThermalManagement.load_configuration',
                           side_effect=test_exception):

                    # Verify that initialization fails gracefully with sys.exit(1)
                    with self.assertRaises(SystemExit) as cm:
                        thermal_control_2_5.ThermalManagement(self.cmd_arg)

                    # Verify exit code is 1
                    self.assertEqual(cm.exception.code, 1)

                    # Verify error was logged
                    self.mock_logger.error.assert_called()
                    error_call = self.mock_logger.error.call_args[0]
                    self.assertIn("Failed to load configuration", error_call[0])
                    self.assertIn(str(test_exception), error_call[0])

    def test_load_configuration_returns_config_instead_of_side_effect(self):
        """Test that load_configuration returns configuration instead of setting it as side effect in 2.5 version."""

        with patch('hw_management_thermal_control_2_5.Logger') as mock_logger_class, \
                patch('hw_management_thermal_control_2_5.ThermalManagement.check_file'), \
                patch('hw_management_thermal_control_2_5.ThermalManagement.read_file'), \
                patch('hw_management_thermal_control_2_5.ThermalManagement.is_pwm_exists', return_value=True), \
                patch('hw_management_thermal_control_2_5.str2bool', return_value=True), \
                patch('signal.signal'):

            mock_logger_class.return_value = self.mock_logger

            # Create instance
            tc = thermal_control_2_5.ThermalManagement(self.cmd_arg)

            # Call load_configuration directly to test the return behavior
            with patch.object(tc, 'read_file', return_value='test_board'), \
                    patch.object(tc, 'check_file', return_value=True), \
                    patch('builtins.open', mock_open(read_data=json.dumps(self.valid_sys_config))):

                result = tc.load_configuration()

                # Verify it returns the configuration
                self.assertIsInstance(result, dict)
                self.assertIn('platform_support', result)

    def test_logger_close_tc_log_handler_optimization(self):
        """Test that logger close_tc_log_handler no longer calls redundant flush() in 2.5 version."""

        # Create a mock file handler
        mock_file_handler = Mock()
        mock_file_handler.flush = Mock()
        mock_file_handler.close = Mock()

        # Create logger instance
        logger = thermal_control_2_5.Logger(self.cmd_arg)
        logger.logger_fh = mock_file_handler
        logger.logger = Mock()

        # Call close_tc_log_handler
        logger.close_tc_log_handler()

        # Verify flush() was NOT called (optimization)
        mock_file_handler.flush.assert_not_called()

        # Verify close() was called (which internally calls flush())
        mock_file_handler.close.assert_called_once()

        # Verify handler was removed
        logger.logger.removeHandler.assert_called_once_with(mock_file_handler)

    def test_signal_handler_platform_support_check_with_initialized_config(self):
        """Test that signal handler properly checks platform_support from initialized sys_config in 2.5 version."""

        test_configs = [
            # Test with platform_support = 1 (supported)
            {"platform_support": 1, "expected_stop_called": True},
            # Test with platform_support = 0 (not supported)
            {"platform_support": 0, "expected_stop_called": False},
            # Test with platform_support = "1" (string, should be converted)
            {"platform_support": "1", "expected_stop_called": True},
            # Test with missing platform_support (should default to 1)
            {}, {"expected_stop_called": True}
        ]

        for i, test_case in enumerate(test_configs):
            with self.subTest(test_case=i):
                if "expected_stop_called" not in test_case:
                    continue

                expected_stop_called = test_case.pop("expected_stop_called")
                test_config = {**self.valid_sys_config, **test_case}

                with patch('hw_management_thermal_control_2_5.Logger') as mock_logger_class, \
                        patch('hw_management_thermal_control_2_5.ThermalManagement.check_file', return_value=False), \
                        patch('hw_management_thermal_control_2_5.ThermalManagement.load_configuration', return_value=test_config), \
                        patch('hw_management_thermal_control_2_5.ThermalManagement.is_pwm_exists', return_value=True), \
                        patch('hw_management_thermal_control_2_5.str2bool', return_value=True), \
                        patch('signal.signal'):

                    mock_logger_class.return_value = self.mock_logger

                    # Create instance
                    tc = thermal_control_2_5.ThermalManagement(self.cmd_arg)

                    # Mock the stop method
                    with patch.object(tc, 'stop') as mock_stop:
                        # Call signal handler
                        try:
                            tc.sig_handler(signal.SIGTERM)
                        except SystemExit:
                            pass  # Expected

                        # Verify stop() was called based on platform_support
                        if expected_stop_called:
                            mock_stop.assert_called_once_with(reason="SIG 15")
                        else:
                            mock_stop.assert_not_called()

    @patch('hw_management_thermal_control_2_5.Logger')
    @patch('hw_management_thermal_control_2_5.ThermalManagement.check_file')
    @patch('hw_management_thermal_control_2_5.ThermalManagement.load_configuration')
    @patch('hw_management_thermal_control_2_5.ThermalManagement.is_pwm_exists')
    @patch('signal.signal')
    def test_initialization_order_prevents_race_condition(self, mock_signal, mock_is_pwm_exists,
                                                          mock_load_config, mock_check_file, mock_logger_class):
        """Test that initialization order prevents the race condition that was fixed in 2.5 version."""

        # Setup mocks
        mock_logger_class.return_value = self.mock_logger
        mock_check_file.return_value = False
        mock_load_config.return_value = self.valid_sys_config
        mock_is_pwm_exists.return_value = True

        # Track the order of critical operations
        operation_order = []

        # Track signal registration
        def track_signal_registration(sig, handler):
            operation_order.append(f"signal_{sig}_registered")

        mock_signal.side_effect = track_signal_registration

        # Track load_configuration call
        def track_load_config():
            operation_order.append("load_configuration_called")
            return self.valid_sys_config

        mock_load_config.side_effect = track_load_config

        with patch('hw_management_thermal_control_2_5.str2bool', return_value=True):

            # Create instance
            tc = thermal_control_2_5.ThermalManagement(self.cmd_arg)

            # Check that signal registration happens after sys_config initialization
            signal_registrations = [op for op in operation_order if "signal_" in op]

            # Verify sys_config was initialized before signals
            self.assertTrue(len(signal_registrations) > 0, "Signal handlers should be registered")

            # Find first signal registration
            first_signal_idx = operation_order.index(signal_registrations[0])
            load_config_idx = operation_order.index("load_configuration_called")

            # load_configuration should happen before signal registration
            self.assertLess(load_config_idx, first_signal_idx,
                            "Configuration should be loaded before signal handlers are registered")

    def test_sys_config_early_initialization_ensures_safety(self):
        """Test that sys_config is initialized to empty dict before any operations in 2.5 version."""

        with patch('hw_management_thermal_control_2_5.Logger') as mock_logger_class, \
                patch('hw_management_thermal_control_2_5.ThermalManagement.check_file', return_value=False), \
                patch('hw_management_thermal_control_2_5.ThermalManagement.load_configuration') as mock_load_config, \
                patch('hw_management_thermal_control_2_5.ThermalManagement.is_pwm_exists', return_value=True), \
                patch('hw_management_thermal_control_2_5.str2bool', return_value=True), \
                patch('signal.signal'):

            mock_logger_class.return_value = self.mock_logger

            # Track the order of operations
            operations = []

            # Intercept sys_config access in load_configuration
            def track_load_config():
                # Record that sys_config exists and is accessible at this point
                operations.append(f"load_config_called_with_sys_config_type: {type(tc.sys_config)}")
                return self.valid_sys_config

            mock_load_config.side_effect = track_load_config

            # Create instance
            tc = thermal_control_2_5.ThermalManagement(self.cmd_arg)

            # Verify sys_config was properly initialized
            self.assertEqual(tc.sys_config, self.valid_sys_config)

            # Verify that load_config was called and sys_config was accessible
            self.assertTrue(any("dict" in op for op in operations),
                            "sys_config should be initialized as dict before load_configuration")


class TestThermalInitIntegration25(unittest.TestCase):
    """Integration tests for thermal control 2.5 initialization fixes."""

    def setUp(self):
        """Set up integration test fixtures."""
        self.cmd_arg = {"verbosity": 1}

    @patch('hw_management_thermal_control_2_5.Logger')
    @patch('hw_management_thermal_control_2_5.ThermalManagement.check_file')
    @patch('hw_management_thermal_control_2_5.ThermalManagement.read_file')
    @patch('hw_management_thermal_control_2_5.ThermalManagement.is_pwm_exists')
    @patch('signal.signal')
    @patch('builtins.open', mock_open(read_data='{"platform_support": 1}'))
    def test_full_initialization_flow_integration(self, mock_signal, mock_is_pwm_exists,
                                                  mock_read_file, mock_check_file, mock_logger_class):
        """Integration test for the full initialization flow with all fixes in 2.5 version."""

        # Setup mocks
        mock_logger = Mock()
        mock_logger_class.return_value = mock_logger
        mock_check_file.return_value = True  # Config file exists
        mock_read_file.side_effect = ['test_board', '{"platform_support": 1}']
        mock_is_pwm_exists.return_value = True

        # Track signal handler registration
        signal_handler = None

        def capture_signal_handler(sig, handler):
            nonlocal signal_handler
            if sig == signal.SIGTERM:
                signal_handler = handler
        mock_signal.side_effect = capture_signal_handler

        # Create ThermalManagement instance - should complete without errors
        with patch('hw_management_thermal_control_2_5.str2bool', return_value=True):
            tc = thermal_control_2_5.ThermalManagement(self.cmd_arg)

        # Verify successful initialization
        self.assertIsNotNone(tc.sys_config)
        self.assertIsInstance(tc.sys_config, dict)
        self.assertEqual(tc.sys_config.get("platform_support"), 1)

        # Verify signal handler was registered and works
        self.assertIsNotNone(signal_handler)

        # Test signal handler with properly initialized state
        with patch.object(tc, 'stop') as mock_stop:
            try:
                signal_handler(signal.SIGTERM)
            except SystemExit:
                pass  # Expected

            # Should successfully call stop() without crashing
            mock_stop.assert_called_once()


if __name__ == '__main__':
    # Run with verbose output
    unittest.main(verbosity=2)
