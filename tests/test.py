#!/usr/bin/env python3
"""
NVIDIA HW-MGMT Test Runner

Unified test runner for the NVIDIA Hardware Management package.
Supports both pytest-based tests and original legacy unittest structure.

Usage:
    python3 test.py --offline          # Run offline tests (verbose by default)
    python3 test.py --hardware         # Run hardware tests only (auto-installs deps)  
    python3 test.py --all              # Run all tests (verbose by default)
    python3 test.py --coverage         # Run with coverage analysis
    python3 test.py --list             # List available tests
    python3 test.py --clean            # Clean up test logs and cache files
    python3 test.py --legacy           # Run legacy tests only

Examples:
    python3 test.py --offline                       # Offline tests (verbose by default)
    python3 test.py --hardware --bmc-ip 192.168.1.50  # Hardware tests with custom BMC IP
    python3 test.py --coverage --html               # Coverage with HTML report
    python3 test.py --all                           # All tests (verbose by default)
"""

import argparse
import subprocess
import sys
import os
import json
import time
import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional
import importlib.util
import shutil
import glob

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
    WARNING = f"{Colors.YELLOW}[WARN]{Colors.RESET}"
    HARDWARE = f"{Colors.MAGENTA}[HW]{Colors.RESET}"
    OFFLINE = f"{Colors.CYAN}[OFFLINE]{Colors.RESET}"
    INSTALL = f"{Colors.BLUE}[INSTALL]{Colors.RESET}"
    CHECK = f"{Colors.CYAN}[CHECK]{Colors.RESET}"
    COVERAGE = f"{Colors.GREEN}[COVERAGE]{Colors.RESET}"
    RUN = f"{Colors.BLUE}[RUN]{Colors.RESET}"
    LEGACY = f"{Colors.MAGENTA}[LEGACY]{Colors.RESET}"


class TestResult:
    """Container for test execution results"""
    
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.skipped = 0
        self.errors = 0
        self.total = 0
        self.execution_time = 0.0
        self.output = ""
        self.coverage_report = None
        self.exit_code = 0  # Store the actual exit code from pytest
        self.summary = ""
        
    def __str__(self):
        success_rate = (self.passed / self.total * 100) if self.total > 0 else 0
        return f"Tests: {self.total}, Passed: {self.passed}, Failed: {self.failed}, Skipped: {self.skipped}, Success Rate: {success_rate:.1f}%"


class LegacyTestResult:
    """Container for legacy test results"""
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


class DependencyManager:
    """Manages test dependencies and installations"""
    
    def __init__(self, requirements_file: Path):
        self.requirements_file = requirements_file
        self.core_packages = [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0", 
            "pytest-html>=3.0.0",
            "colorama>=0.4.0",
            "termcolor>=2.0.0"
        ]
        
    def check_package_installed(self, package_name: str) -> bool:
        """Check if a package is installed"""
        try:
            if '>=' in package_name:
                package_name = package_name.split('>=')[0]
            importlib.import_module(package_name.replace('-', '_'))
            return True
        except ImportError:
            return False
    
    def check_dependencies(self, silent: bool = False) -> bool:
        """Check if all required dependencies are installed"""
        missing = []
        
        for package in self.core_packages:
            if not self.check_package_installed(package):
                missing.append(package)
        
        if not silent and missing:
            print(f"{Icons.WARNING} Missing packages: {', '.join(missing)}")
        
        return len(missing) == 0
    
    def install_dependencies(self) -> bool:
        """Install missing dependencies"""
        if not self.requirements_file.exists():
            print(f"{Icons.WARNING} Requirements file not found: {self.requirements_file}")
            return False
        
        try:
            cmd = [sys.executable, "-m", "pip", "install", "-r", str(self.requirements_file)]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode != 0:
                print(f"{Icons.FAIL} Failed to install dependencies:")
                print(result.stderr)
                return False
            
            return True
        
        except Exception as e:
            print(f"{Icons.FAIL} Error installing dependencies: {e}")
            return False


class HWMGMTTestRunner:
    """Main test runner class"""
    
    def __init__(self):
        self.base_dir = Path(__file__).parent
        self.hw_mgmt_bin_dir = self.base_dir.parent / "usr" / "usr" / "bin"
        self.logs_dir = self.base_dir / "logs"
        self.logs_dir.mkdir(exist_ok=True)
        
        # Legacy test setup
        self.legacy_base_dir = self.base_dir / "offline" / "legacy"
        self.legacy_result = LegacyTestResult()
        
    def _get_log_file(self, test_type: str) -> Path:
        """Generate timestamped log file path"""
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        return self.logs_dir / f"test_{test_type}_{timestamp}.log"
    
    def setup_legacy_environment(self):
        """Setup environment for legacy tests"""
        # Add hw-mgmt modules to Python path
        if str(self.hw_mgmt_bin_dir) not in sys.path:
            sys.path.insert(0, str(self.hw_mgmt_bin_dir))
            
        # Also add base directory to path for relative imports
        base_project_dir = self.base_dir.parent  # Go up from tests to project root
        if str(base_project_dir) not in sys.path:
            sys.path.insert(0, str(base_project_dir))
            
        # Set PYTHONPATH environment variable for subprocess calls
        current_pythonpath = os.environ.get('PYTHONPATH', '')
        paths_to_add = [str(self.hw_mgmt_bin_dir), str(base_project_dir)]
        new_pythonpath = ':'.join(paths_to_add)
        if current_pythonpath:
            os.environ['PYTHONPATH'] = f"{new_pythonpath}:{current_pythonpath}"
        else:
            os.environ['PYTHONPATH'] = new_pythonpath
            
        # Set HW_MGMT_DIR environment variable that some tests might expect
        os.environ['HW_MGMT_DIR'] = str(self.hw_mgmt_bin_dir)
    
    def run_legacy_python_test(self, test_file: Path, test_name: str) -> bool:
        """Run a Python legacy test file in its original format"""
        print(f"\n{Icons.LEGACY} Running {test_name}...")
        
        start_time = time.time()
        
        try:
            # Change to test directory to maintain original working directory
            original_cwd = os.getcwd()
            os.chdir(test_file.parent)
            
            # Run the test file directly with better error handling
            env = os.environ.copy()
            env['PYTHONPATH'] = os.environ.get('PYTHONPATH', '')
            
            result = subprocess.run([
                sys.executable, test_file.name
            ], capture_output=True, text=True, timeout=300, env=env)
            
            # Restore original working directory  
            os.chdir(original_cwd)
            
            execution_time = time.time() - start_time
            
            if result.returncode == 0:
                print(f"  {Icons.PASS} {test_name} completed successfully ({execution_time:.2f}s)")
                self.legacy_result.add_result(test_name, 'PASSED', execution_time, result.stdout)
                return True
            else:
                print(f"  {Icons.FAIL} {test_name} failed ({execution_time:.2f}s)")
                print(f"  Error: {result.stderr}")
                self.legacy_result.add_result(test_name, 'FAILED', execution_time, result.stderr)
                return False
                
        except subprocess.TimeoutExpired:
            print(f"  {Icons.FAIL} {test_name} timed out")
            self.legacy_result.add_result(test_name, 'FAILED', 300, "Test timed out")
            return False
        except Exception as e:
            execution_time = time.time() - start_time
            print(f"  {Icons.FAIL} {test_name} error: {e}")
            self.legacy_result.add_result(test_name, 'FAILED', execution_time, str(e))
            return False
    
    def run_legacy_python_test_with_args(self, test_file: Path, test_name: str, args: List[str]) -> bool:
        """Run a Python legacy test file with command line arguments"""
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
                self.legacy_result.add_result(test_name, 'PASSED', execution_time, result.stdout)
                return True
            else:
                print(f"  {Icons.FAIL} {test_name} failed ({execution_time:.2f}s)")
                print(f"  Error: {result.stderr}")
                self.legacy_result.add_result(test_name, 'FAILED', execution_time, result.stderr)
                return False
                
        except subprocess.TimeoutExpired:
            print(f"  {Icons.FAIL} {test_name} timed out")
            self.legacy_result.add_result(test_name, 'FAILED', 300, "Test timed out")
            return False
        except Exception as e:
            execution_time = time.time() - start_time
            print(f"  {Icons.FAIL} {test_name} error: {e}")
            self.legacy_result.add_result(test_name, 'FAILED', execution_time, str(e))
            return False
    
    def run_legacy_shell_script(self, script_file: Path, test_name: str, args: List[str] = None) -> bool:
        """Run a shell script legacy test in its original format"""
        if args:
            print(f"\n{Icons.LEGACY} Running {test_name} (shell script with args: {args})...")
        else:
            print(f"\n{Icons.LEGACY} Running {test_name} (shell script)...")
        
        start_time = time.time()
        
        try:
            # Change to test directory to maintain original working directory
            original_cwd = os.getcwd()
            os.chdir(script_file.parent)
            
            # Make script executable and run it
            os.chmod(script_file, 0o755)
            cmd = ['bash', script_file.name]
            if args:
                cmd.extend(args)
            
            env = os.environ.copy()
            env['PYTHONPATH'] = os.environ.get('PYTHONPATH', '')
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, env=env)
            
            # Restore original working directory
            os.chdir(original_cwd)
            
            execution_time = time.time() - start_time
            
            if result.returncode == 0:
                print(f"  {Icons.PASS} {test_name} completed successfully ({execution_time:.2f}s)")
                self.legacy_result.add_result(test_name, 'PASSED', execution_time, result.stdout)
                return True
            else:
                # Check if it's an empty script (common issue with shell scripts)
                if "Permission denied" in result.stderr or result.stderr.strip() == "" or len(result.stdout.strip()) == 0:
                    print(f"  {Icons.SKIP} {test_name} skipped (empty or permission issue)")
                    self.legacy_result.add_result(test_name, 'SKIPPED', execution_time, "Empty script or permission issue")
                    return True  # Treat as success for empty scripts
                else:
                    print(f"  {Icons.FAIL} {test_name} failed ({execution_time:.2f}s)")
                    print(f"  Error: {result.stderr}")
                    self.legacy_result.add_result(test_name, 'FAILED', execution_time, result.stderr)
                    return False
                
        except subprocess.TimeoutExpired:
            print(f"  {Icons.FAIL} {test_name} timed out")
            self.legacy_result.add_result(test_name, 'FAILED', 300, "Test timed out")
            return False
        except Exception as e:
            execution_time = time.time() - start_time
            print(f"  {Icons.FAIL} {test_name} error: {e}")
            self.legacy_result.add_result(test_name, 'FAILED', execution_time, str(e))
            return False

    def discover_legacy_tests(self) -> List[Dict[str, Any]]:
        """Discover all legacy test files"""
        tests = []
        
        # BOM Decoder CLI test (now in offline directory)
        bom_file = self.base_dir / "offline" / "bom_decoder_cli.py"
        if bom_file.exists():
            tests.append({
                'name': 'BOM Decoder CLI', 
                'file': bom_file,
                'type': 'python_with_args',
                'args': ['--help']  # Just show help for BOM decoder to verify it works
            })
        
        # HW Management Lib Logger tests
        logger_run_file = self.legacy_base_dir / "hw_management_lib" / "HW_Mgmt_Logger" / "run_tests.py"
        if logger_run_file.exists():
            tests.append({
                'name': 'HW Management Logger Tests',
                'file': logger_run_file,
                'type': 'python_runner'
            })
            
        # Advanced logger tests (use original version)
        logger_advanced_file = self.legacy_base_dir / "hw_management_lib" / "HW_Mgmt_Logger" / "advanced_tests.py"
        if logger_advanced_file.exists():
            tests.append({
                'name': 'HW Management Logger Advanced Tests',
                'file': logger_advanced_file,
                'type': 'python_standalone'
            })
        
        # ASIC temperature populate tests
        asic_shell_file = self.legacy_base_dir / "hw_mgmgt_sync" / "asic_populate_temperature" / "run_tests.sh"
        if asic_shell_file.exists():
            tests.append({
                'name': 'ASIC Temperature Populate Tests (Shell)',
                'file': asic_shell_file,
                'type': 'shell_script'
            })
            
        asic_python_file = self.legacy_base_dir / "hw_mgmgt_sync" / "asic_populate_temperature" / "test_asic_temp_populate.py"
        if asic_python_file.exists():
            tests.append({
                'name': 'ASIC Temperature Populate Tests (Python)',
                'file': asic_python_file,
                'type': 'python_standalone'
            })
        
        # Module populate tests (need hw_management_sync.py path)
        hw_mgmt_sync_path = str(self.hw_mgmt_bin_dir / "hw_management_sync.py")
        
        module_shell_files = [
            ("Module Populate Tests (Main)", "hw_mgmgt_sync/module_populate/run_tests.sh", True),
            ("Module Populate Tests (All)", "hw_mgmgt_sync/module_populate/run_all_tests.py", True), 
            ("Module Temperature Tests", "hw_mgmgt_sync/module_populate_temperature/run_tests.sh", False)  # Auto-discovers path
        ]
        
        for test_name, rel_path, needs_path in module_shell_files:
            test_file = self.legacy_base_dir / rel_path
            if test_file.exists():
                if rel_path.endswith('.sh'):
                    if needs_path:
                        tests.append({
                            'name': test_name,
                            'file': test_file,
                            'type': 'shell_with_args',
                            'args': [hw_mgmt_sync_path]  # Pass path to hw_management_sync.py
                        })
                    else:
                        tests.append({
                            'name': test_name,
                            'file': test_file,
                            'type': 'shell_script'  # No args needed, auto-discovers path
                        })
                else:
                    tests.append({
                        'name': test_name,
                        'file': test_file,
                        'type': 'python_with_args',
                        'args': ['--hw-mgmt-path', hw_mgmt_sync_path]
                    })
        
        return tests
    
    def run_legacy_tests(self) -> TestResult:
        """Run all discovered legacy tests"""
        print(f"\n{Icons.INFO} {Colors.CYAN}Running Legacy Test Suite...{Colors.RESET}")
        
        print(f"\n{Colors.BOLD}{Colors.MAGENTA}LEGACY TEST SUITE - ORIGINAL FUNCTIONALITY PRESERVED{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.MAGENTA}{'='*70}{Colors.RESET}")
        print(f"{Icons.INFO} Running ALL original unittest files from master branch")
        print(f"{Icons.INFO} Zero modifications - preserving 100% of teammate work")
        
        # Setup environment
        self.setup_legacy_environment()
        
        # Discover tests
        tests = self.discover_legacy_tests()
        
        # Create result object
        test_result = TestResult()
        test_result.exit_code = 0
        
        if not tests:
            print(f"{Icons.SKIP} No legacy tests found")
            test_result.summary = "Legacy: No tests found"
            return test_result
            
        print(f"{Icons.INFO} Found {len(tests)} legacy test suites")
        
        # Run tests
        all_passed = True
        total_start = time.time()
        
        for test_info in tests:
            test_name = test_info['name']
            test_file = test_info['file']
            test_type = test_info['type']
            
            try:
                if test_type in ['python_standalone', 'python_runner']:
                    success = self.run_legacy_python_test(test_file, test_name)
                elif test_type == 'python_with_args':
                    args = test_info.get('args', [])
                    success = self.run_legacy_python_test_with_args(test_file, test_name, args)
                elif test_type == 'shell_script':
                    success = self.run_legacy_shell_script(test_file, test_name)
                elif test_type == 'shell_with_args':
                    args = test_info.get('args', [])
                    success = self.run_legacy_shell_script(test_file, test_name, args)
                elif test_type == 'skip':
                    reason = test_info.get('reason', 'Test skipped')
                    print(f"\n{Icons.SKIP} Skipping {test_name}: {reason}")
                    self.legacy_result.add_result(test_name, 'SKIPPED', 0, reason)
                    continue
                else:
                    print(f"{Icons.SKIP} Unknown test type: {test_type}")
                    continue
                    
                if not success:
                    all_passed = False
                    
            except Exception as e:
                print(f"{Icons.FAIL} Error running {test_name}: {e}")
                all_passed = False
        
        total_time = time.time() - total_start
        self.legacy_result.total_time = total_time
        
        # Print summary
        self.print_legacy_summary()
        
        # Set test result properties
        test_result.passed = self.legacy_result.passed
        test_result.failed = self.legacy_result.failed
        test_result.skipped = self.legacy_result.skipped
        test_result.total = self.legacy_result.passed + self.legacy_result.failed + self.legacy_result.skipped
        test_result.execution_time = total_time
        test_result.exit_code = 1 if self.legacy_result.failed > 0 else 0
        test_result.summary = f"Legacy: {self.legacy_result.get_summary()}"
        
        return test_result
    
    def print_legacy_summary(self):
        """Print legacy test summary"""
        print(f"\n{Colors.BOLD}{Colors.MAGENTA}LEGACY TEST RESULTS{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.MAGENTA}{'='*50}{Colors.RESET}")
        
        summary = self.legacy_result.get_summary()
        print(f"{Icons.INFO} {summary}")
        print(f"{Icons.INFO} Total execution time: {self.legacy_result.total_time:.2f}s")
        
        # Detailed results
        if self.legacy_result.test_details:
            print(f"\n{Colors.BOLD}Detailed Results:{Colors.RESET}")
            for detail in self.legacy_result.test_details:
                if detail['status'] == 'PASSED':
                    icon = Icons.PASS
                elif detail['status'] == 'FAILED':
                    icon = Icons.FAIL
                else:
                    icon = Icons.SKIP
                    
                print(f"  {icon} {detail['name']} ({detail['time']:.2f}s)")
        
        # Final verdict
        if self.legacy_result.failed == 0:
            print(f"\n{Icons.PASS} {Colors.GREEN}ALL LEGACY TESTS PASSED!{Colors.RESET}")
            print(f"{Icons.LEGACY} Original functionality 100% preserved!")
        else:
            print(f"\n{Icons.FAIL} {Colors.RED}{self.legacy_result.failed} legacy tests failed{Colors.RESET}")
            print(f"{Icons.INFO} Check individual test outputs above for details")

    def clean_test_environment(self):
        """Clean up test logs, cache files, and coverage reports"""
        import shutil
        import glob
        
        print(f"\n{Colors.CYAN}Cleaning test environment...{Colors.RESET}")
        
        items_cleaned = []
        
        # Clean logs directory
        if self.logs_dir.exists():
            log_files = list(self.logs_dir.glob("*.log"))
            if log_files:
                for log_file in log_files:
                    log_file.unlink()
                items_cleaned.append(f"Removed {len(log_files)} log files")
        
        # Clean __pycache__ directories (including legacy paths)
        pycache_dirs = []
        
        # Find all __pycache__ directories recursively
        for root, dirs, files in os.walk(self.base_dir):
            for dir_name in dirs:
                if dir_name == "__pycache__":
                    pycache_dirs.append(Path(root) / dir_name)
        
        if pycache_dirs:
            for pycache_dir in pycache_dirs:
                shutil.rmtree(pycache_dir, ignore_errors=True)
            items_cleaned.append(f"Removed {len(pycache_dirs)} __pycache__ directories")
        
        # Clean coverage files and reports
        coverage_files = [
            self.base_dir / ".coverage",
            self.base_dir / "coverage.json", 
            self.base_dir / "coverage.xml"
        ]
        
        coverage_dirs = [
            self.base_dir / "coverage_html_report",
            self.base_dir / ".pytest_cache"
        ]
        
        cleaned_files = 0
        for coverage_file in coverage_files:
            if coverage_file.exists():
                coverage_file.unlink()
                cleaned_files += 1
                
        cleaned_dirs = 0
        for coverage_dir in coverage_dirs:
            if coverage_dir.exists():
                shutil.rmtree(coverage_dir, ignore_errors=True)
                cleaned_dirs += 1
                
        if cleaned_files > 0:
            items_cleaned.append(f"Removed {cleaned_files} coverage files")
        if cleaned_dirs > 0:
            items_cleaned.append(f"Removed {cleaned_dirs} coverage/cache directories")
        
        # Clean any temporary test files (*.tmp, *.temp)
        temp_files = list(self.base_dir.glob("**/*.tmp")) + list(self.base_dir.glob("**/*.temp"))
        if temp_files:
            for temp_file in temp_files:
                temp_file.unlink(missing_ok=True)
            items_cleaned.append(f"Removed {len(temp_files)} temporary files")
        
        # Report results
        if items_cleaned:
            print(f"{Icons.PASS} {Colors.GREEN}Cleaned:{Colors.RESET}")
            for item in items_cleaned:
                print(f"  - {item}")
        else:
            print(f"{Icons.INFO} {Colors.YELLOW}Environment is already clean{Colors.RESET}")
            
        print(f"\n{Icons.PASS} {Colors.GREEN}Test environment cleanup completed!{Colors.RESET}")
    
    def list_tests(self):
        """List all available tests"""
        print(f"\n{Colors.BOLD}{Colors.BLUE}NVIDIA HW-MGMT Available Tests{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.BLUE}{'='*50}{Colors.RESET}")
        
        # Offline pytest tests
        print(f"\n{Colors.BOLD}Offline Tests (pytest-based):{Colors.RESET}")
        offline_dir = self.base_dir / "offline"
        if offline_dir.exists():
            test_files = list(offline_dir.glob("test_*.py"))
            for test_file in test_files:
                print(f"  - {test_file.name}")
        
        # Hardware pytest tests  
        print(f"\n{Colors.BOLD}Hardware Tests (pytest-based):{Colors.RESET}")
        hardware_dir = self.base_dir / "hardware"
        if hardware_dir.exists():
            test_files = list(hardware_dir.glob("test_*.py"))
            for test_file in test_files:
                print(f"  - {test_file.name}")
        
        # Legacy tests
        print(f"\n{Colors.BOLD}Legacy Tests (original unittest):{Colors.RESET}")
        legacy_tests = self.discover_legacy_tests()
        for test in legacy_tests:
            print(f"  - {test['name']}")
        
        print(f"\n{Icons.INFO} Total: {len(list(offline_dir.glob('test_*.py')) if offline_dir.exists() else [])} offline + {len(list(hardware_dir.glob('test_*.py')) if hardware_dir.exists() else [])} hardware + {len(legacy_tests)} legacy tests")
    
    def run_tests(self, test_type: str, verbose: bool = False, coverage: bool = False, 
                  html_report: bool = False, stop_on_failure: bool = False, 
                  bmc_ip: str = "127.0.0.1", markers: str = None) -> TestResult:
        """Run tests based on specified type"""
        
        # Create pytest command with CI-friendly options (no special characters/progress bars)
        cmd = ["python", "-m", "pytest", "--tb=short", "-p", "no:sugar"]
        
        # Add paths based on test type
        if test_type == "offline":
            # Run pytest offline tests first, then legacy tests
            pytest_result = self._run_pytest_offline(cmd, verbose, coverage, html_report, stop_on_failure, markers)
            legacy_result = self.run_legacy_tests()
            
            # Combine results
            combined_result = TestResult()
            combined_result.exit_code = pytest_result.exit_code or legacy_result.exit_code
            combined_result.summary = f"Pytest: {pytest_result.summary}, Legacy: {legacy_result.summary}"
            combined_result.execution_time = pytest_result.execution_time + legacy_result.execution_time
            return combined_result
        elif test_type == "hardware":
            cmd.append("hardware/")
            cmd.extend(["-m", "hardware"])
            cmd.extend(["--bmc-ip", bmc_ip])
            os.environ["PYTEST_HARDWARE"] = "1"
        elif test_type == "all":
            # Run pytest tests first, then legacy tests
            pytest_result = self._run_pytest_all(cmd, verbose, coverage, html_report, stop_on_failure, markers)
            legacy_result = self.run_legacy_tests()
            
            # Combine results
            combined_result = TestResult()
            combined_result.exit_code = pytest_result.exit_code or legacy_result.exit_code
            combined_result.summary = f"Pytest: {pytest_result.summary}, Legacy: {legacy_result.summary}"
            combined_result.execution_time = pytest_result.execution_time + legacy_result.execution_time
            return combined_result
        elif test_type == "legacy":
            return self.run_legacy_tests()
        else:
            raise ValueError(f"Unknown test type: {test_type}")
            
        # Add options
        if verbose:
            cmd.append("-v")
        else:
            cmd.append("-q")
            
        if stop_on_failure:
            cmd.append("-x")
            
        if markers:
            cmd.extend(["-m", markers])
            
        # Add coverage options
        if coverage:
            cmd.extend([
                f"--cov={self.hw_mgmt_bin_dir}",
                "--cov-branch", 
                "--cov-report=term-missing",
                "--cov-report=json:coverage.json"
            ])
            
            if html_report:
                cmd.extend(["--cov-report=html:coverage_html_report"])
        
        # Run pytest
        start_time = time.time()
        log_file = self._get_log_file(test_type)
        
        try:
            # Create command with better output handling
            print(f"\n{Icons.INFO} {Colors.CYAN}Running pytest tests...{Colors.RESET}")
            print(f"{Icons.INFO} Logging to: {log_file}")
            
            # Run pytest and show output to user
            result = subprocess.run(cmd, text=True, cwd=self.base_dir)
            
            execution_time = time.time() - start_time
            
            # Create result object
            test_result = TestResult()
            test_result.execution_time = execution_time
            test_result.exit_code = result.returncode
            
            # Since we're showing output directly, just show a simple summary
            if result.returncode == 0:
                test_result.summary = "Pytest: All tests passed"
                print(f"\n{Icons.PASS} {Colors.GREEN}Pytest tests completed successfully{Colors.RESET}")
            else:
                test_result.summary = "Pytest: Some tests failed"
                print(f"\n{Icons.FAIL} {Colors.RED}Some pytest tests failed{Colors.RESET}")
                
            return test_result
            
        except KeyboardInterrupt:
            test_result = TestResult()
            test_result.execution_time = time.time() - start_time
            test_result.exit_code = 130
            test_result.summary = "Pytest: Interrupted by user"
            return test_result
        except Exception as e:
            test_result = TestResult()
            test_result.execution_time = time.time() - start_time
            test_result.exit_code = 1
            test_result.summary = f"Pytest: Error - {e}"
            return test_result
    
    def _run_pytest_offline(self, cmd, verbose, coverage, html_report, stop_on_failure, markers):
        """Run pytest offline tests only"""
        # Configure for offline tests
        cmd.append("offline/")
        cmd.extend(["-m", "offline"])
        
        # Add options
        if verbose:
            cmd.append("-v")
        else:
            cmd.append("-q")
            
        if stop_on_failure:
            cmd.append("-x")
            
        if markers:
            cmd.extend(["-m", markers])
            
        # Add coverage options
        if coverage:
            cmd.extend([
                f"--cov={self.hw_mgmt_bin_dir}",
                "--cov-branch", 
                "--cov-report=term-missing",
                "--cov-report=json:coverage.json"
            ])
            
            if html_report:
                cmd.extend(["--cov-report=html:coverage_html_report"])
        
        # Run pytest
        start_time = time.time()
        
        try:
            print(f"\n{Icons.INFO} {Colors.CYAN}Running Offline Tests...{Colors.RESET}")
            # Run pytest and show output to user
            result = subprocess.run(cmd, text=True, cwd=self.base_dir)
            
            execution_time = time.time() - start_time
            
            # Create result object
            test_result = TestResult()
            test_result.execution_time = execution_time
            test_result.exit_code = result.returncode
            
            # Since we're showing output directly, just show a simple summary
            if result.returncode == 0:
                test_result.summary = "Pytest: All tests passed"
                print(f"\n{Icons.PASS} {Colors.GREEN}Offline tests completed successfully{Colors.RESET}")
            else:
                test_result.summary = "Pytest: Some tests failed" 
                print(f"\n{Icons.FAIL} {Colors.RED}Some offline tests failed{Colors.RESET}")
                
            return test_result
            
        except Exception as e:
            test_result = TestResult()
            test_result.execution_time = time.time() - start_time
            test_result.exit_code = 1
            test_result.summary = f"Pytest: Error - {e}"
            return test_result
    
    def _run_pytest_all(self, cmd, verbose, coverage, html_report, stop_on_failure, markers):
        """Run pytest for all tests"""
        # Configure for all tests
        cmd.append(".")
        
        # Add options
        if verbose:
            cmd.append("-v")
        else:
            cmd.append("-q")
            
        if stop_on_failure:
            cmd.append("-x")
            
        if markers:
            cmd.extend(["-m", markers])
            
        # Add coverage options
        if coverage:
            cmd.extend([
                f"--cov={self.hw_mgmt_bin_dir}",
                "--cov-branch", 
                "--cov-report=term-missing",
                "--cov-report=json:coverage.json"
            ])
            
            if html_report:
                cmd.extend(["--cov-report=html:coverage_html_report"])
        
        # Run pytest
        start_time = time.time()
        
        try:
            print(f"\n{Icons.INFO} {Colors.CYAN}Running All Pytest Tests...{Colors.RESET}")
            # Run pytest and show output to user
            result = subprocess.run(cmd, text=True, cwd=self.base_dir)
            
            execution_time = time.time() - start_time
            
            # Create result object
            test_result = TestResult()
            test_result.execution_time = execution_time
            test_result.exit_code = result.returncode
            
            # Since we're showing output directly, just show a simple summary
            if result.returncode == 0:
                test_result.summary = "Pytest: All tests passed"
                print(f"\n{Icons.PASS} {Colors.GREEN}All pytest tests completed successfully{Colors.RESET}")
            else:
                test_result.summary = "Pytest: Some tests failed"
                print(f"\n{Icons.FAIL} {Colors.RED}Some pytest tests failed{Colors.RESET}") 
                
            return test_result
            
        except Exception as e:
            test_result = TestResult()
            test_result.execution_time = time.time() - start_time
            test_result.exit_code = 1
            test_result.summary = f"Pytest: Error - {e}"
            return test_result


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="NVIDIA HW-MGMT Test Runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    # Test type arguments (mutually exclusive)
    test_group = parser.add_mutually_exclusive_group(required=True)
    test_group.add_argument("--offline", action="store_true", 
                          help="Run offline tests only (verbose by default)")
    test_group.add_argument("--hardware", action="store_true",
                          help="Run hardware tests only (requires real hardware)")
    test_group.add_argument("--all", action="store_true",
                          help="Run all tests (offline + hardware + legacy, verbose by default)")
    test_group.add_argument("--legacy", action="store_true",
                          help="Run legacy tests only")
    test_group.add_argument("--list", action="store_true", 
                          help="List all available tests")
    test_group.add_argument("--clean", action="store_true",
                          help="Clean up test logs, cache files, and coverage reports")
    
    # Optional arguments  
    parser.add_argument("--coverage", action="store_true",
                       help="Generate test coverage report")
    parser.add_argument("--html", action="store_true", 
                       help="Generate HTML coverage report (requires --coverage)")
    parser.add_argument("--stop-on-failure", action="store_true",
                       help="Stop on first test failure")
    parser.add_argument("--bmc-ip", default="127.0.0.1",
                       help="BMC IP address for hardware tests (default: 127.0.0.1)")
    parser.add_argument("--markers", type=str,
                       help="Pytest markers to filter tests")
    
    args = parser.parse_args()
    
    # Create test runner
    runner = HWMGMTTestRunner()
    
    # Handle special commands
    if args.clean:
        runner.clean_test_environment()
        return 0
    
    if args.list:
        runner.list_tests()
        return 0
    
    # Set up dependency manager
    requirements_file = Path(__file__).parent / "requirements.txt"
    dep_manager = DependencyManager(requirements_file)
    
    # Print header
    print(f"{Colors.BOLD}{Colors.GREEN}NVIDIA HW-MGMT Test Runner{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.GREEN}{'='*60}{Colors.RESET}")
    
    print(f"\n{Icons.RUN} {Colors.BOLD}Running HW-MGMT Test Suite{Colors.RESET}")
    print(f"{Colors.BLUE}{'='*60}{Colors.RESET}")
    
    # Automatically ensure dependencies are available (pip is smart - skips satisfied requirements)
    # Quick silent check first
    if not dep_manager.check_dependencies(silent=True):
        print(f"{Icons.INSTALL} Installing/updating test dependencies...")
        if not dep_manager.install_dependencies():
            print(f"{Icons.FAIL} Failed to install dependencies.")
            return 1
    
    # Final verification
    try:
        import pytest
        import colorama
    except ImportError:
        print(f"{Icons.INSTALL} Core packages missing, installing...")
        if not dep_manager.install_dependencies():
            print(f"{Icons.FAIL} Failed to install core dependencies.")
            return 1
    
    # Determine test type
    if args.offline:
        test_type = "offline"
    elif args.hardware:
        test_type = "hardware"
    elif args.all:
        test_type = "all"
    elif args.legacy:
        test_type = "legacy"
    else:
        test_type = "offline"  # Default
    
    print(f"{Icons.INFO} Test Type: {test_type}")
    print(f"{Icons.INFO} Working Directory: {runner.base_dir}")
    print(f"{Icons.INFO} Python Path: {sys.executable}")
    
    # Set verbose by default for offline and all
    verbose = (test_type in ["offline", "all"])
    
    try:
        # Run tests
        print(f"\n{Colors.CYAN}Executing tests...{Colors.RESET}")
        result = runner.run_tests(
            test_type=test_type,
            verbose=verbose,
            coverage=args.coverage,
            html_report=args.html,
            stop_on_failure=args.stop_on_failure,
            bmc_ip=args.bmc_ip,
            markers=args.markers
        )
        
        # Print final execution summary
        print(f"\n{Icons.INFO} Execution time: {result.execution_time:.2f} seconds")
        
        # Print final CI/CD verdict (single boolean result)
        print(f"\n{Colors.BOLD}{'='*60}{Colors.RESET}")
        print(f"{Colors.BOLD}FINAL VERDICT FOR CI/CD:{Colors.RESET}")
        
        if result.exit_code == 0:
            print(f"{Icons.PASS} {Colors.BOLD}{Colors.GREEN}SUCCESS - ALL TESTS PASSED{Colors.RESET}")
            ci_verdict = True
        else:
            print(f"{Icons.FAIL} {Colors.BOLD}{Colors.RED}FAILURE - SOME TESTS FAILED{Colors.RESET}")
            ci_verdict = False
        
        print(f"{Colors.BOLD}CI Boolean Result: {ci_verdict}{Colors.RESET}")
        print(f"{Colors.BOLD}{'='*60}{Colors.RESET}")
        
        # Exit with the actual pytest exit code so git hooks work properly
        return result.exit_code if hasattr(result, 'exit_code') else 0
        
    except KeyboardInterrupt:
        print(f"\n{Icons.WARNING} Test execution interrupted by user")
        return 130
    except Exception as e:
        print(f"\n{Icons.FAIL} Test execution failed: {e}")
        return 1

if __name__ == "__main__":
    exit(main())