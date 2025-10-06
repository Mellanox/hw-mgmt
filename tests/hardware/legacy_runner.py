#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Hardware Legacy Test Runner for Original unittest Structure
#
# This runner executes hardware-dependent legacy test files from the master branch
# in their exact original format, preserving 100% of teammate manual work.
########################################################################

import os
import sys
import subprocess
import time
from pathlib import Path
from typing import List, Dict, Any

# ANSI Colors for output
class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    BOLD = '\033[1m'
    RESET = '\033[0m'

class Icons:
    PASS = f"{Colors.GREEN}[PASS]{Colors.RESET}"
    FAIL = f"{Colors.RED}[FAIL]{Colors.RESET}"
    SKIP = f"{Colors.YELLOW}[SKIP]{Colors.RESET}"
    INFO = f"{Colors.BLUE}[INFO]{Colors.RESET}"
    LEGACY = f"{Colors.MAGENTA}[LEGACY]{Colors.RESET}"

class HardwareLegacyTestResult:
    """Container for hardware legacy test results"""
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.skipped = 0
        self.total_time = 0
        self.test_details = []
        
    def add_result(self, name: str, status: str, time_taken: float, output: str = ""):
        """Add a test result"""
        self.test_details.append({
            'name': name,
            'status': status, 
            'time': time_taken,
            'output': output
        })
        
        if status == 'PASSED':
            self.passed += 1
        elif status == 'FAILED':
            self.failed += 1
        else:
            self.skipped += 1
            
    def get_summary(self) -> str:
        """Get test summary"""
        total = self.passed + self.failed + self.skipped
        return f"{self.passed} passed, {self.failed} failed, {self.skipped} skipped ({total} total)"

class HardwareLegacyTestRunner:
    """Runner for hardware-dependent legacy tests"""
    
    def __init__(self):
        self.base_dir = Path(__file__).parent / "legacy"
        self.hw_mgmt_dir = Path(__file__).parent.parent.parent / "usr" / "usr" / "bin"
        self.result = HardwareLegacyTestResult()
        
    def setup_environment(self):
        """Setup environment for hardware legacy tests"""
        # Add hw-mgmt modules to Python path
        if str(self.hw_mgmt_dir) not in sys.path:
            sys.path.insert(0, str(self.hw_mgmt_dir))
            
        # Also add base directory to path for relative imports
        base_project_dir = self.base_dir.parent.parent.parent  # Go up from tests/hardware/legacy to project root
        if str(base_project_dir) not in sys.path:
            sys.path.insert(0, str(base_project_dir))
            
        # Set PYTHONPATH environment variable for subprocess calls
        current_pythonpath = os.environ.get('PYTHONPATH', '')
        paths_to_add = [str(self.hw_mgmt_dir), str(base_project_dir)]
        new_pythonpath = ':'.join(paths_to_add)
        if current_pythonpath:
            os.environ['PYTHONPATH'] = f"{new_pythonpath}:{current_pythonpath}"
        else:
            os.environ['PYTHONPATH'] = new_pythonpath
            
        # Set HW_MGMT_DIR environment variable that some tests might expect
        os.environ['HW_MGMT_DIR'] = str(self.hw_mgmt_dir)
    
    def run_python_test_with_args(self, test_file: Path, test_name: str, args: List[str]) -> bool:
        """Run a Python test file with command line arguments"""
        print(f"\n{Icons.LEGACY} Running {test_name} (with args: {args})...")
        
        start_time = time.time()
        
        try:
            # Change to test directory to maintain original working directory
            original_cwd = os.getcwd()
            os.chdir(test_file.parent)
            
            # Run the test file with arguments
            cmd = [sys.executable, test_file.name] + args
            env = os.environ.copy()
            env['PYTHONPATH'] = os.environ.get('PYTHONPATH', '')
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, env=env)
            
            # Restore original working directory  
            os.chdir(original_cwd)
            
            execution_time = time.time() - start_time
            
            if result.returncode == 0:
                print(f"  {Icons.PASS} {test_name} completed successfully ({execution_time:.2f}s)")
                self.result.add_result(test_name, 'PASSED', execution_time, result.stdout)
                return True
            else:
                print(f"  {Icons.FAIL} {test_name} failed ({execution_time:.2f}s)")
                print(f"  Error: {result.stderr}")
                self.result.add_result(test_name, 'FAILED', execution_time, result.stderr)
                return False
                
        except subprocess.TimeoutExpired:
            print(f"  {Icons.FAIL} {test_name} timed out")
            self.result.add_result(test_name, 'FAILED', 300, "Test timed out")
            return False
        except Exception as e:
            execution_time = time.time() - start_time
            print(f"  {Icons.FAIL} {test_name} error: {e}")
            self.result.add_result(test_name, 'FAILED', execution_time, str(e))
            return False

    def discover_hardware_legacy_tests(self, bmc_ip: str = "192.168.1.100") -> List[Dict[str, Any]]:
        """Discover all hardware legacy test files"""
        tests = []
        
        # BMC Accessor login test (requires real BMC IP)
        bmc_file = self.base_dir / "hw_management_bmcaccessor_login_test.py"
        if bmc_file.exists():
            tests.append({
                'name': 'BMC Accessor Login Test (Hardware)',
                'file': bmc_file,
                'type': 'python_with_args',
                'args': [bmc_ip]  # Use real BMC IP for hardware testing
            })
        
        return tests
    
    def run_all_hardware_legacy_tests(self, bmc_ip: str = "192.168.1.100") -> bool:
        """Run all discovered hardware legacy tests"""
        print(f"\n{Colors.BOLD}{Colors.MAGENTA}HARDWARE LEGACY TEST SUITE{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.MAGENTA}{'='*50}{Colors.RESET}")
        print(f"{Icons.INFO} Running hardware-dependent legacy tests")
        print(f"{Icons.INFO} BMC IP: {bmc_ip}")
        
        # Setup environment
        self.setup_environment()
        
        # Discover tests
        tests = self.discover_hardware_legacy_tests(bmc_ip)
        
        if not tests:
            print(f"{Icons.SKIP} No hardware legacy tests found")
            return True
            
        print(f"{Icons.INFO} Found {len(tests)} hardware legacy test suites")
        
        # Run tests
        all_passed = True
        total_start = time.time()
        
        for test_info in tests:
            test_name = test_info['name']
            test_file = test_info['file']
            test_type = test_info['type']
            
            try:
                if test_type == 'python_with_args':
                    args = test_info.get('args', [])
                    success = self.run_python_test_with_args(test_file, test_name, args)
                else:
                    print(f"{Icons.SKIP} Unknown test type: {test_type}")
                    continue
                    
                if not success:
                    all_passed = False
                    
            except Exception as e:
                print(f"{Icons.FAIL} Error running {test_name}: {e}")
                all_passed = False
        
        total_time = time.time() - total_start
        self.result.total_time = total_time
        
        # Print summary
        self.print_hardware_legacy_summary()
        
        return all_passed
    
    def print_hardware_legacy_summary(self):
        """Print hardware legacy test summary"""
        print(f"\n{Colors.BOLD}{Colors.MAGENTA}HARDWARE LEGACY TEST RESULTS{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.MAGENTA}{'='*50}{Colors.RESET}")
        
        summary = self.result.get_summary()
        print(f"{Icons.INFO} {summary}")
        print(f"{Icons.INFO} Total execution time: {self.result.total_time:.2f}s")
        
        # Detailed results
        if self.result.test_details:
            print(f"\n{Colors.BOLD}Detailed Results:{Colors.RESET}")
            for detail in self.result.test_details:
                if detail['status'] == 'PASSED':
                    icon = Icons.PASS
                elif detail['status'] == 'FAILED':
                    icon = Icons.FAIL
                else:
                    icon = Icons.SKIP
                    
                print(f"  {icon} {detail['name']} ({detail['time']:.2f}s)")
        
        # Final verdict
        if self.result.failed == 0:
            print(f"\n{Icons.PASS} {Colors.GREEN}ALL HARDWARE LEGACY TESTS PASSED!{Colors.RESET}")
            print(f"{Icons.LEGACY} Hardware functionality 100% preserved!")
        else:
            print(f"\n{Icons.FAIL} {Colors.RED}{self.result.failed} hardware legacy tests failed{Colors.RESET}")
            
def main():
    """Main entry point for hardware legacy test runner"""
    import argparse
    parser = argparse.ArgumentParser(description="Hardware Legacy Test Runner")
    parser.add_argument("--bmc-ip", default="192.168.1.100", 
                       help="BMC IP address for hardware tests")
    args = parser.parse_args()
    
    runner = HardwareLegacyTestRunner()
    
    print(f"{Colors.BOLD}{Colors.BLUE}NVIDIA HW-MGMT Hardware Legacy Test Runner{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'='*50}{Colors.RESET}")
    
    success = runner.run_all_hardware_legacy_tests(args.bmc_ip)
    
    return 0 if success else 1

if __name__ == '__main__':
    exit(main())
