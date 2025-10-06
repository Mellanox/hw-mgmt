#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Test Runner for hw-mgmt
########################################################################

import sys
import os
import argparse
import subprocess
from pathlib import Path


class Colors:
    """ANSI color codes for terminal output"""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    RESET = '\033[0m'


class TestRunner:
    """Test runner for hw-mgmt test suite"""
    
    def __init__(self, verbose=False):
        self.verbose = verbose
        self.tests_dir = Path(__file__).parent.absolute()
        self.offline_dir = self.tests_dir / "offline"
        self.hardware_dir = self.tests_dir / "hardware"
        self.failed_tests = []
        self.passed_tests = []
        
    def print_header(self, text):
        """Print a formatted header"""
        print(f"\n{Colors.BOLD}{Colors.CYAN}{'=' * 80}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}{text}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}{'=' * 80}{Colors.RESET}\n")
    
    def print_test_start(self, test_name):
        """Print test start message"""
        print(f"{Colors.BLUE}Running: {Colors.BOLD}{test_name}{Colors.RESET}")
    
    def print_test_result(self, test_name, passed, output=None):
        """Print test result"""
        if passed:
            print(f"{Colors.GREEN}✓ PASSED:{Colors.RESET} {test_name}")
            self.passed_tests.append(test_name)
        else:
            print(f"{Colors.RED}✗ FAILED:{Colors.RESET} {test_name}")
            self.failed_tests.append(test_name)
            if output and self.verbose:
                print(f"{Colors.YELLOW}Output:{Colors.RESET}")
                print(output)
    
    def run_command(self, cmd, cwd, test_name):
        """Run a command and return success status"""
        self.print_test_start(test_name)
        
        try:
            result = subprocess.run(
                cmd,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )
            
            passed = result.returncode == 0
            
            if self.verbose or not passed:
                output = result.stdout + result.stderr
                self.print_test_result(test_name, passed, output)
            else:
                self.print_test_result(test_name, passed)
            
            return passed
            
        except subprocess.TimeoutExpired:
            self.print_test_result(test_name, False, "Test timed out after 5 minutes")
            return False
        except Exception as e:
            self.print_test_result(test_name, False, f"Exception: {str(e)}")
            return False
    
    def run_offline_tests(self):
        """Run all offline tests"""
        self.print_header("OFFLINE TESTS")
        
        tests = [
            {
                'name': 'HW_Mgmt_Logger - Main Tests',
                'cmd': ['python3', 'test_hw_mgmt_logger.py', '--random-iterations', '5', '--verbosity', '1'],
                'cwd': self.offline_dir / 'hw_management_lib' / 'HW_Mgmt_Logger'
            },
            {
                'name': 'HW_Mgmt_Logger - Advanced Tests',
                'cmd': ['python3', 'advanced_tests.py', '-v'],
                'cwd': self.offline_dir / 'hw_management_lib' / 'HW_Mgmt_Logger'
            },
            {
                'name': 'ASIC Temperature Populate',
                'cmd': ['python3', 'test_asic_temp_populate.py', '-v'],
                'cwd': self.offline_dir / 'hw_mgmgt_sync' / 'asic_populate_temperature'
            },
            {
                'name': 'Module Populate - Simple Test',
                'cmd': ['python3', 'simple_test.py'],
                'cwd': self.offline_dir / 'hw_mgmgt_sync' / 'module_populate'
            },
            {
                'name': 'Module Temperature Populate',
                'cmd': ['python3', 'test_module_temp_populate.py'],
                'cwd': self.offline_dir / 'hw_mgmgt_sync' / 'module_populate'
            },
            {
                'name': 'Module Temperature Populate (Extended)',
                'cmd': ['python3', 'test_module_temp_populate.py'],
                'cwd': self.offline_dir / 'hw_mgmgt_sync' / 'module_populate_temperature'
            },
        ]
        
        for test in tests:
            self.run_command(test['cmd'], test['cwd'], test['name'])
        
        return len(self.failed_tests) == 0
    
    def run_hardware_tests(self):
        """Run all hardware tests"""
        self.print_header("HARDWARE TESTS")
        
        tests = [
            {
                'name': 'BMC Accessor Login Test',
                'cmd': ['python3', 'hw_management_bmcaccessor_login_test.py'],
                'cwd': self.hardware_dir
            },
        ]
        
        for test in tests:
            if test['cwd'].exists():
                self.run_command(test['cmd'], test['cwd'], test['name'])
            else:
                print(f"{Colors.YELLOW}⚠ SKIPPED:{Colors.RESET} {test['name']} (requires hardware)")
        
        return len(self.failed_tests) == 0
    
    def print_summary(self):
        """Print test execution summary"""
        self.print_header("TEST SUMMARY")
        
        total = len(self.passed_tests) + len(self.failed_tests)
        
        print(f"{Colors.GREEN}✓ Passed:{Colors.RESET} {len(self.passed_tests)}/{total}")
        print(f"{Colors.RED}✗ Failed:{Colors.RESET} {len(self.failed_tests)}/{total}")
        
        if self.failed_tests:
            print(f"\n{Colors.RED}Failed tests:{Colors.RESET}")
            for test in self.failed_tests:
                print(f"  - {test}")
        
        if len(self.failed_tests) == 0:
            print(f"\n{Colors.GREEN}{Colors.BOLD}ALL TESTS PASSED!{Colors.RESET}")
        else:
            print(f"\n{Colors.RED}{Colors.BOLD}SOME TESTS FAILED{Colors.RESET}")


def main():
    """Main test runner entry point"""
    parser = argparse.ArgumentParser(
        description='HW-MGMT Test Runner',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --offline          # Run offline tests only
  %(prog)s --hardware         # Run hardware tests only
  %(prog)s --all              # Run all tests
  %(prog)s --offline -v       # Run offline tests with verbose output
        """
    )
    parser.add_argument('--offline', action='store_true', help='Run offline tests')
    parser.add_argument('--hardware', action='store_true', help='Run hardware tests')
    parser.add_argument('--all', action='store_true', help='Run all tests')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')
    
    args = parser.parse_args()
    
    # If no specific test type is selected, default to offline
    if not any([args.offline, args.hardware, args.all]):
        args.offline = True
    
    runner = TestRunner(verbose=args.verbose)
    
    success = True
    
    if args.offline or args.all:
        if not runner.run_offline_tests():
            success = False
    
    if args.hardware or args.all:
        if not runner.run_hardware_tests():
            success = False
    
    runner.print_summary()
    
    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())

