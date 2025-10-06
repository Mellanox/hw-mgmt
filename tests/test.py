#!/usr/bin/env python3
"""
NVIDIA HW-MGMT Test Runner

Modern, cross-platform test runner for the NVIDIA Hardware Management package.
Replaces shell scripts with a unified Python interface.

Usage:
    python3 test.py --offline          # Run offline tests (verbose by default)
    python3 test.py --hardware         # Run hardware tests only (auto-installs deps)  
    python3 test.py --all              # Run all tests (verbose by default)
    python3 test.py --coverage         # Run with coverage analysis
    python3 test.py --list             # List available tests
    python3 test.py --clean            # Clean up test logs and cache files

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

# ANSI Colors for beautiful output
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
    PASS = f"{Colors.GREEN}✅{Colors.RESET}"
    FAIL = f"{Colors.RED}❌{Colors.RESET}"
    SKIP = f"{Colors.YELLOW}⏭️{Colors.RESET}"
    INFO = f"{Colors.BLUE}ℹ️{Colors.RESET}"
    WARNING = f"{Colors.YELLOW}⚠️{Colors.RESET}"
    HARDWARE = f"{Colors.MAGENTA}🖥️{Colors.RESET}"
    OFFLINE = f"{Colors.CYAN}💻{Colors.RESET}"
    INSTALL = f"{Colors.BLUE}📦{Colors.RESET}"
    CHECK = f"{Colors.CYAN}🔍{Colors.RESET}"
    COVERAGE = f"{Colors.GREEN}📊{Colors.RESET}"
    ROCKET = f"{Colors.BLUE}🚀{Colors.RESET}"


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
        
    def __str__(self):
        success_rate = (self.passed / self.total * 100) if self.total > 0 else 0
        return f"Tests: {self.total}, Passed: {self.passed}, Failed: {self.failed}, Skipped: {self.skipped}, Success Rate: {success_rate:.1f}%"


class DependencyManager:
    """Manages test dependencies and installations"""
    
    def __init__(self, requirements_file: Path):
        self.requirements_file = requirements_file
        self.core_packages = [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0", 
            "pytest-xdist>=3.0.0",
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
            
    def install_requirements(self, force: bool = False) -> bool:
        """Install requirements from requirements.txt"""
        if not self.requirements_file.exists():
            print(f"{Icons.WARNING} requirements.txt not found, installing core packages only")
            return self._install_core_packages()
            
        print(f"{Icons.INSTALL} Installing test dependencies from {self.requirements_file.name}...")
        
        try:
            cmd = [sys.executable, "-m", "pip", "install", "-r", str(self.requirements_file)]
            if force:
                cmd.append("--force-reinstall")
                
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            
            if result.returncode == 0:
                print(f"{Icons.PASS} Dependencies installed successfully")
                return True
            else:
                print(f"{Icons.FAIL} Failed to install dependencies: {result.stderr}")
                return self._install_core_packages()
                
        except subprocess.TimeoutExpired:
            print(f"{Icons.FAIL} Dependency installation timed out")
            return False
        except Exception as e:
            print(f"{Icons.FAIL} Error installing dependencies: {e}")
            return self._install_core_packages()
            
    def _install_core_packages(self) -> bool:
        """Install core packages individually"""
        print(f"{Icons.INFO} Installing core packages individually...")
        
        success = True
        for package in self.core_packages:
            try:
                result = subprocess.run(
                    [sys.executable, "-m", "pip", "install", package],
                    capture_output=True, text=True, timeout=60
                )
                if result.returncode == 0:
                    print(f"  {Icons.PASS} {package}")
                else:
                    print(f"  {Icons.FAIL} {package}: {result.stderr.strip()}")
                    success = False
            except Exception as e:
                print(f"  {Icons.FAIL} {package}: {e}")
                success = False
                
        return success
        
    def check_all_dependencies(self) -> Dict[str, bool]:
        """Check status of all dependencies"""
        status = {}
        
        # Check pytest
        status['pytest'] = self.check_package_installed('pytest')
        status['pytest-cov'] = self.check_package_installed('pytest_cov')
        status['pytest-xdist'] = self.check_package_installed('xdist')
        status['pytest-html'] = self.check_package_installed('pytest_html')
        status['colorama'] = self.check_package_installed('colorama')
        
        return status


class HWMgmtTestRunner:
    """Main test runner for HW-MGMT test suite"""
    
    def __init__(self):
        self.base_dir = Path(__file__).parent
        self.hw_mgmt_root = self.base_dir.parent
        self.hw_mgmt_bin_dir = self.hw_mgmt_root / "usr" / "usr" / "bin"
        self.requirements_file = self.base_dir / "requirements.txt"
        self.dependency_manager = DependencyManager(self.requirements_file)
        
        # Setup logging directory
        self.logs_dir = self.base_dir / "logs"
        self.logs_dir.mkdir(exist_ok=True)
        
        # Setup Python path
        self._setup_python_path()
        
    def _get_log_file(self, test_type: str) -> Path:
        """Generate timestamped log file path for test execution"""
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        log_filename = f"test_{test_type}_{timestamp}.log"
        return self.logs_dir / log_filename
        
    def _setup_python_path(self):
        """Ensure hw-mgmt modules are in Python path"""
        paths_to_add = [
            str(self.hw_mgmt_bin_dir),
            str(self.base_dir),
            str(self.base_dir / "offline"),
            str(self.base_dir / "hardware"),
            str(self.base_dir / "integration"),
            str(self.base_dir / "tools")
        ]
        
        for path in paths_to_add:
            if path not in sys.path:
                sys.path.insert(0, path)
                
        # Set PYTHONPATH environment variable
        current_pythonpath = os.environ.get('PYTHONPATH', '')
        new_pythonpath = ':'.join(paths_to_add)
        if current_pythonpath:
            os.environ['PYTHONPATH'] = f"{new_pythonpath}:{current_pythonpath}"
        else:
            os.environ['PYTHONPATH'] = new_pythonpath
            
    def install_dependencies(self, force: bool = False) -> bool:
        """Install test dependencies"""
        return self.dependency_manager.install_requirements(force)
        
    def check_dependencies(self, silent: bool = False) -> bool:
        """Check if all dependencies are available"""
        if not silent:
            print(f"{Icons.CHECK} Checking dependencies...")
        
        status = self.dependency_manager.check_all_dependencies()
        all_good = all(status.values())
        
        if all_good:
            if not silent:
                print(f"{Icons.PASS} All dependencies are available")
        else:
            if not silent:
                print(f"{Icons.WARNING} Missing dependencies:")
                for pkg, installed in status.items():
                    icon = Icons.PASS if installed else Icons.FAIL
                    print(f"  {icon} {pkg}")
                
        return all_good
        
    def list_tests(self) -> Dict[str, Any]:
        """List all available tests"""
        print(f"\n{Colors.BOLD}{Colors.BLUE}📋 Available Test Suites{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.BLUE}{'='*50}{Colors.RESET}")
        
        # Discover tests using pytest
        try:
            result = subprocess.run([
                sys.executable, "-m", "pytest", 
                "--collect-only", "-q", "--tb=no"
            ], capture_output=True, text=True, cwd=self.base_dir)
            
            if result.returncode == 0:
                lines = result.stdout.split('\n')
                test_files = [line for line in lines if '::' not in line and line.strip().endswith('.py')]
                
                offline_tests = [f for f in test_files if 'offline/' in f]
                hardware_tests = [f for f in test_files if 'hardware/' in f]
                integration_tests = [f for f in test_files if 'integration/' in f]
                
                print(f"\n{Icons.OFFLINE} {Colors.BOLD}Offline Tests (No Hardware Required):{Colors.RESET}")
                for test in offline_tests:
                    print(f"   • {test.strip()}")
                    
                print(f"\n{Icons.HARDWARE} {Colors.BOLD}Hardware Tests (Requires Real Hardware):{Colors.RESET}")
                for test in hardware_tests:
                    print(f"   • {test.strip()}")
                    
                if integration_tests:
                    print(f"\n{Colors.YELLOW}🔗{Colors.RESET} {Colors.BOLD}Integration Tests:{Colors.RESET}")
                    for test in integration_tests:
                        print(f"   • {test.strip()}")
                        
                return {
                    'offline': len(offline_tests),
                    'hardware': len(hardware_tests), 
                    'integration': len(integration_tests),
                    'total': len(test_files)
                }
            else:
                print(f"{Icons.FAIL} Failed to discover tests: {result.stderr}")
                return {}
                
        except Exception as e:
            print(f"{Icons.FAIL} Error discovering tests: {e}")
            return {}
            
    def clean_test_environment(self):
        """Clean up test logs, cache files, and coverage reports"""
        import shutil
        import glob
        
        print(f"\n{Colors.CYAN}🧹 Cleaning test environment...{Colors.RESET}")
        
        items_cleaned = []
        
        # Clean logs directory
        if self.logs_dir.exists():
            log_files = list(self.logs_dir.glob("*.log"))
            if log_files:
                for log_file in log_files:
                    log_file.unlink()
                items_cleaned.append(f"Removed {len(log_files)} log files")
        
        # Clean __pycache__ directories
        pycache_dirs = list(self.base_dir.glob("**/__pycache__"))
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
                print(f"  • {item}")
        else:
            print(f"{Icons.INFO} {Colors.YELLOW}Environment is already clean{Colors.RESET}")
            
        print(f"\n{Icons.PASS} {Colors.GREEN}Test environment cleanup completed!{Colors.RESET}")
            
    def run_tests(self, 
                 test_type: str = "all", 
                 verbose: bool = False,
                 coverage: bool = False,
                 html_report: bool = False,
                 bmc_ip: str = "192.168.1.100",
                 stop_on_failure: bool = False,
                 markers: Optional[str] = None) -> TestResult:
        """Run tests with specified options"""
        
        start_time = time.time()
        
        # Build pytest command
        cmd = [sys.executable, "-m", "pytest"]
        
        # Add paths based on test type
        if test_type == "offline":
            cmd.append("offline/")
            cmd.extend(["-m", "offline"])
        elif test_type == "hardware":
            cmd.append("hardware/")
            cmd.extend(["-m", "hardware"])
            cmd.extend(["--bmc-ip", bmc_ip])
            os.environ["PYTEST_HARDWARE"] = "1"
        elif test_type == "integration":
            cmd.append("integration/")
            cmd.extend(["-m", "integration"])
        elif test_type == "all":
            cmd.append(".")
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
                "--cov-report=term-missing"
            ])
            
            if html_report:
                cmd.extend(["--cov-report=html:coverage_html_report"])
                
        # Add other useful options
        cmd.extend([
            "--tb=short",
            "--color=yes",
            "--strict-markers",
            "--strict-config",
            "-W", "error"  # Treat warnings as errors
        ])
        
        # Print command info
        print(f"\n{Icons.ROCKET} {Colors.BOLD}Running HW-MGMT Test Suite{Colors.RESET}")
        print(f"{Colors.BLUE}{'='*60}{Colors.RESET}")
        print(f"{Icons.INFO} Test Type: {test_type}")
        print(f"{Icons.INFO} Working Directory: {self.base_dir}")
        if test_type == "hardware":
            print(f"{Icons.INFO} BMC IP: {bmc_ip}")
        print(f"{Icons.INFO} Python Path: {sys.executable}")
        
        # Run tests
        try:
            log_file = self._get_log_file(test_type)
            print(f"\n{Colors.CYAN}🔬 Executing tests...{Colors.RESET}")
            print(f"{Icons.INFO} Logging to: {log_file}")
            
            # Run pytest and capture output for logging while showing in real-time
            with open(log_file, 'w') as f:
                # Write command and environment info to log
                f.write(f"Test execution started at: {datetime.datetime.now()}\n")
                f.write(f"Command: {' '.join(cmd)}\n")
                f.write(f"Working directory: {self.base_dir}\n")
                f.write(f"Test type: {test_type}\n")
                if test_type == "hardware":
                    f.write(f"BMC IP: {bmc_ip}\n")
                f.write("="*80 + "\n\n")
                f.flush()
                
                # Run the actual test command with real-time output
                process = subprocess.Popen(
                    cmd,
                    cwd=self.base_dir,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    universal_newlines=True
                )
                
                # Stream output to both console and log file
                for line in process.stdout:
                    print(line, end='')  # Real-time console output
                    f.write(line)        # Log file output
                    f.flush()
                
                process.wait()
                result_returncode = process.returncode
                
                f.write(f"\n\nTest execution completed at: {datetime.datetime.now()}\n")
                f.write(f"Exit code: {result_returncode}\n")
            
            execution_time = time.time() - start_time
            
            # Parse results (simplified - pytest exit codes)
            test_result = TestResult()
            test_result.execution_time = execution_time
            test_result.exit_code = result_returncode  # Store the actual exit code
            
            if result_returncode == 0:
                print(f"\n{Icons.PASS} {Colors.GREEN}All tests completed successfully!{Colors.RESET}")
            elif result_returncode == 1:
                print(f"\n{Icons.FAIL} {Colors.RED}Some tests failed{Colors.RESET}")
            elif result_returncode == 2:
                print(f"\n{Icons.FAIL} {Colors.RED}Test execution was interrupted{Colors.RESET}")
            elif result_returncode == 3:
                print(f"\n{Icons.FAIL} {Colors.RED}Internal error occurred{Colors.RESET}")
            elif result_returncode == 4:
                print(f"\n{Icons.WARNING} {Colors.YELLOW}Pytest usage error{Colors.RESET}")
            elif result_returncode == 5:
                print(f"\n{Icons.WARNING} {Colors.YELLOW}No tests were collected{Colors.RESET}")
                
            # Show reports
            if coverage and html_report:
                coverage_file = self.base_dir / "coverage_html_report" / "index.html"
                if coverage_file.exists():
                    print(f"{Icons.COVERAGE} Coverage report: {coverage_file}")
                    
            print(f"\n{Icons.INFO} Execution time: {execution_time:.2f} seconds")
            
            return test_result
            
        except KeyboardInterrupt:
            print(f"\n{Icons.WARNING} Test execution interrupted by user")
            test_result = TestResult()
            test_result.execution_time = time.time() - start_time
            test_result.exit_code = 130  # Standard exit code for SIGINT
            return test_result
        except Exception as e:
            print(f"\n{Icons.FAIL} Error running tests: {e}")
            test_result = TestResult()
            test_result.execution_time = time.time() - start_time
            test_result.exit_code = 1  # Generic error exit code
            return test_result


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="NVIDIA HW-MGMT Test Runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    # Test selection
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--offline", action="store_true", 
                      help="Run offline tests only (no hardware required, verbose by default)")
    group.add_argument("--hardware", action="store_true",
                      help="Run hardware tests only (requires real hardware)")
    group.add_argument("--integration", action="store_true",
                      help="Run integration tests only") 
    group.add_argument("--all", action="store_true",
                      help="Run all tests (verbose by default)")
    group.add_argument("--list", action="store_true",
                      help="List available tests without running them")
    group.add_argument("--clean", action="store_true",
                      help="Clean up test logs, cache files, and coverage reports")
    
    # Test options
    parser.add_argument("-v", "--verbose", action="store_true",
                       help="Verbose output")
    parser.add_argument("-x", "--stop-on-failure", action="store_true",
                       help="Stop on first failure")
    parser.add_argument("--markers", type=str,
                       help="Run tests with specific markers (e.g., 'slow' or 'not slow')")
    
    # Coverage options
    parser.add_argument("--coverage", action="store_true",
                       help="Run with coverage analysis")
    parser.add_argument("--html", action="store_true",
                       help="Generate HTML coverage report (requires --coverage)")
    
    # Hardware options
    parser.add_argument("--bmc-ip", type=str, default="192.168.1.100",
                       help="BMC IP address for hardware tests (default: 192.168.1.100)")
    
    # Dependency options  
    parser.add_argument("--force-install", action="store_true", 
                       help="Force reinstall all dependencies")
    
    args = parser.parse_args()
    
    # Initialize test runner
    runner = HWMgmtTestRunner()
    
    # Print banner
    print(f"{Colors.BOLD}{Colors.GREEN}🚀 NVIDIA HW-MGMT Test Runner{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.GREEN}{'='*60}{Colors.RESET}")
    
    # Handle clean command
    if args.clean:
        runner.clean_test_environment()
        return 0
        
    # Handle list command
    if args.list:
        runner.list_tests()
        return 0
        
    # Automatically ensure dependencies are available (pip is smart - skips satisfied requirements)
    # Quick silent check first
    if not runner.check_dependencies(silent=True):
        print(f"{Icons.INSTALL} Installing/updating test dependencies...")
        if not runner.install_dependencies():
            print(f"{Icons.FAIL} Failed to install dependencies.")
            return 1
    
    # Final verification
    try:
        import pytest
        import colorama
    except ImportError:
        print(f"{Icons.INSTALL} Core packages missing, installing...")
        if not runner.install_dependencies():
            print(f"{Icons.FAIL} Failed to install core dependencies.")
            return 1
    
    # Determine test type
    if args.offline:
        test_type = "offline"
    elif args.hardware:
        test_type = "hardware"
    elif args.integration:
        test_type = "integration"
    elif args.all:
        test_type = "all"
    else:
        test_type = "all"  # Default
        
    # Run tests
    try:
        # Default to verbose mode for offline and all tests (better development experience)
        verbose_mode = args.verbose or (test_type in ["offline", "all"])
        
        result = runner.run_tests(
            test_type=test_type,
            verbose=verbose_mode,
            coverage=args.coverage,
            html_report=args.html,
            bmc_ip=args.bmc_ip,
            stop_on_failure=args.stop_on_failure,
            markers=args.markers
        )
        
        # Exit with the actual pytest exit code so git hooks work properly
        return result.exit_code if hasattr(result, 'exit_code') else 0
        
    except KeyboardInterrupt:
        print(f"\n{Icons.WARNING} Interrupted by user")
        return 130
    except Exception as e:
        print(f"\n{Icons.FAIL} Unexpected error: {e}")
        return 1


if __name__ == "__main__":
    exit(main())
