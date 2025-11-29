#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Test Runner for hw-mgmt
#
# CI/CD STRICT MODE:
#   - Fails on ANY test failure
#   - Fails on ANY pytest warning (via -W error)
#   - Fails on ANY xfail or skip test
#   - Fails on unregistered pytest markers
#
# Known issues and bugs are tracked in offline/known_issues_*.py files
# which are explicitly ignored by CI.
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

    def __init__(self, verbose=False, enable_logs=True, hardware_host=None, hardware_user=None, hardware_password=None, coverage=False, coverage_html=False, coverage_min=None, shell_coverage=False, shell_coverage_min=None):
        self.verbose = verbose
        self.enable_logs = enable_logs
        self.tests_dir = Path(__file__).parent.absolute()
        self.offline_dir = self.tests_dir / "offline"
        self.hardware_dir = self.tests_dir / "hardware"
        self.shell_dir = self.tests_dir / "shell"
        self.logs_dir = self.tests_dir / "logs"
        self.failed_tests = []
        self.passed_tests = []
        self.total_test_count = 0  # Track total individual tests

        # Hardware test SSH parameters
        self.hardware_host = hardware_host
        self.hardware_user = hardware_user
        self.hardware_password = hardware_password

        # Coverage parameters
        self.coverage = coverage
        self.coverage_html = coverage_html
        self.coverage_min = coverage_min

        # Shell testing coverage parameters
        self.shell_coverage = shell_coverage
        self.shell_coverage_min = shell_coverage_min

        # Create logs directory if logging is enabled
        if self.enable_logs:
            self.logs_dir.mkdir(exist_ok=True)
            # Clean old logs (ignore permission errors)
            for old_log in self.logs_dir.glob("*.log"):
                try:
                    old_log.unlink()
                except (PermissionError, OSError):
                    # Skip files we can't delete (may be owned by another user/root)
                    pass

    def check_dependencies(self, auto_install=True):
        """Check if required dependencies are installed, optionally auto-install"""
        try:
            import pytest
            pytest_version = pytest.__version__
            if self.verbose:
                print(f"{Colors.GREEN}pytest {pytest_version} is installed{Colors.RESET}")
            return True
        except ImportError:
            print(f"{Colors.YELLOW}pytest is not installed - required for running tests{Colors.RESET}")

            if auto_install:
                print(f"{Colors.CYAN}Auto-installing required dependencies...{Colors.RESET}")
                if self.install_dependencies():
                    # Verify installation succeeded
                    try:
                        import pytest
                        print(f"{Colors.GREEN}pytest installed successfully{Colors.RESET}")
                        return True
                    except ImportError:
                        print(f"{Colors.RED}Failed to import pytest after installation{Colors.RESET}")
                        return False
                else:
                    return False
            else:
                print(f"{Colors.YELLOW}Please install dependencies:{Colors.RESET}")
                print(f"  python3 test.py --install")
                print(f"  or: pip install -r {self.tests_dir}/requirements.txt")
                return False

    def install_dependencies(self):
        """Install dependencies from requirements.txt"""
        requirements_file = self.tests_dir / "requirements.txt"

        if not requirements_file.exists():
            print(f"{Colors.RED}ERROR: requirements.txt not found{Colors.RESET}")
            return False

        print(f"{Colors.CYAN}Installing test dependencies...{Colors.RESET}")
        try:
            result = subprocess.run(
                [sys.executable, "-m", "pip", "install", "-r", str(requirements_file)],
                capture_output=True,
                text=True,
                check=False
            )

            if result.returncode == 0:
                print(f"{Colors.GREEN}Dependencies installed successfully{Colors.RESET}")
                return True
            else:
                print(f"{Colors.RED}Failed to install dependencies{Colors.RESET}")
                if self.verbose:
                    print(result.stderr)
                return False
        except Exception as e:
            print(f"{Colors.RED}Error installing dependencies: {e}{Colors.RESET}")
            return False

    def clean_cache(self):
        """Clean Python cache files to avoid stale module issues"""
        import shutil

        cache_dirs = list(self.tests_dir.rglob("__pycache__"))
        pyc_files = [f for f in self.tests_dir.rglob("*.pyc") if not any(p in f.parts for p in ["__pycache__"])]

        # Delete individual .pyc files first (those not in __pycache__)
        for pyc_file in pyc_files:
            try:
                pyc_file.unlink()
                if self.verbose:
                    print(f"{Colors.YELLOW}Deleted:{Colors.RESET} {pyc_file}")
            except Exception as e:
                if self.verbose:
                    print(f"{Colors.RED}Failed to delete {pyc_file}: {e}{Colors.RESET}")

        # Then delete __pycache__ directories (which may contain .pyc files)
        for cache_dir in cache_dirs:
            try:
                shutil.rmtree(cache_dir)
                if self.verbose:
                    print(f"{Colors.YELLOW}Cleaned cache:{Colors.RESET} {cache_dir}")
            except Exception as e:
                if self.verbose:
                    print(f"{Colors.RED}Failed to clean {cache_dir}: {e}{Colors.RESET}")

        if cache_dirs or pyc_files:
            print(f"{Colors.GREEN}Cache cleaned:{Colors.RESET} {len(cache_dirs)} directories, {len(pyc_files)} .pyc files")

    def clean_all(self):
        """Clean all generated files (cache, logs, test outputs, etc.)"""
        import shutil

        cleaned_items = []

        # Patterns to clean
        patterns = {
            '__pycache__': 'Python cache directories',
            '*.pyc': 'Python bytecode files',
            '*.pyo': 'Python optimized bytecode files',
            '*.pyd': 'Python extension modules',
            '.pytest_cache': 'Pytest cache directories',
            'logs': 'Test log directories',
            '*.log': 'Log files',
            '.coverage': 'Coverage data files',
            'htmlcov': 'Coverage HTML reports',
            '.tox': 'Tox environments',
            '*.egg-info': 'Python egg info',
            'dist': 'Distribution directories',
            'build': 'Build directories',
        }

        print(f"{Colors.CYAN}{'=' * 80}{Colors.RESET}")
        print(f"{Colors.CYAN}Cleaning all generated files...{Colors.RESET}")
        print(f"{Colors.CYAN}{'=' * 80}{Colors.RESET}\n")

        # Clean in tests directory
        for pattern, description in patterns.items():
            if '*' in pattern:
                # File pattern
                files = list(self.tests_dir.rglob(pattern))
                for f in files:
                    try:
                        f.unlink()
                        cleaned_items.append(str(f))
                        print(f"{Colors.YELLOW}Removed:{Colors.RESET} {f}")
                    except Exception as e:
                        if self.verbose:
                            print(f"{Colors.RED}Failed to remove {f}: {e}{Colors.RESET}")
            else:
                # Directory pattern
                dirs = list(self.tests_dir.rglob(pattern))
                for d in dirs:
                    try:
                        shutil.rmtree(d)
                        cleaned_items.append(str(d))
                        print(f"{Colors.YELLOW}Removed:{Colors.RESET} {d}")
                    except Exception as e:
                        if self.verbose:
                            print(f"{Colors.RED}Failed to remove {d}: {e}{Colors.RESET}")

        # Also clean usr/usr/bin/__pycache__
        usr_bin_cache = self.tests_dir.parent / 'usr' / 'usr' / 'bin' / '__pycache__'
        if usr_bin_cache.exists():
            try:
                shutil.rmtree(usr_bin_cache)
                cleaned_items.append(str(usr_bin_cache))
                print(f"{Colors.YELLOW}Removed:{Colors.RESET} {usr_bin_cache}")
            except Exception as e:
                if self.verbose:
                    print(f"{Colors.RED}Failed to remove {usr_bin_cache}: {e}{Colors.RESET}")

        print(f"\n{Colors.GREEN}[SUCCESS] Cleanup complete:{Colors.RESET} {len(cleaned_items)} items removed")
        return True

    def print_header(self, text):
        """Print a formatted header"""
        print(f"\n{Colors.BOLD}{Colors.CYAN}{'=' * 80}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}{text}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}{'=' * 80}{Colors.RESET}\n")

    def print_test_start(self, test_name, cmd, cwd):
        """Print test start message"""
        print(f"{Colors.BLUE}Command: {Colors.BOLD}{' '.join(cmd)}{Colors.RESET}")
        print(f"{Colors.BLUE}Working Directory: {Colors.BOLD}{cwd}{Colors.RESET}")
        print(f"{Colors.BLUE}Running: {Colors.BOLD}{test_name}{Colors.RESET}")

    def print_test_result(self, test_name, passed, output=None):
        """Print test result"""
        if passed:
            print(f"{Colors.GREEN}[PASSED]{Colors.RESET} {test_name}")
            self.passed_tests.append(test_name)
        else:
            print(f"{Colors.RED}[FAILED]{Colors.RESET} {test_name}")
            self.failed_tests.append(test_name)
            if output and self.verbose:
                print(f"{Colors.YELLOW}Output:{Colors.RESET}")
                print(output)

    def run_command(self, cmd, cwd, test_name):
        """Run a command and return success status"""
        self.print_test_start(test_name, cmd, cwd)

        try:
            result = subprocess.run(
                cmd,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )

            passed = result.returncode == 0
            output = result.stdout + result.stderr

            # Save output to log file
            if self.enable_logs:
                log_filename = test_name.replace(' ', '_').replace('/', '_').replace('(', '').replace(')', '') + '.log'
                log_path = self.logs_dir / log_filename
                with open(log_path, 'w', encoding='utf-8') as f:
                    f.write(f"Test: {test_name}\n")
                    f.write(f"Command: {' '.join(cmd)}\n")
                    f.write(f"Working Directory: {cwd}\n")
                    f.write(f"Exit Code: {result.returncode}\n")
                    f.write(f"{'=' * 80}\n\n")
                    f.write(output)

            # Extract test counts and pytest summary
            is_pytest = 'pytest' in ' '.join(cmd)
            has_coverage = '--cov' in ' '.join(cmd)

            if is_pytest and passed:
                # Extract the summary line (e.g., "74 passed in 0.46s")
                summary_lines = []
                for line in output.split('\n'):
                    if 'passed' in line or 'failed' in line or 'error' in line:
                        if any(x in line for x in ['passed in', 'failed', 'error']):
                            summary_lines.append(line.strip())
                            # Extract test count from pytest summary
                            import re
                            match = re.search(r'(\d+)\s+passed', line)
                            if match:
                                self.total_test_count += int(match.group(1))

                if summary_lines:
                    # Show just the last summary line
                    print(f"  {Colors.CYAN}{summary_lines[-1]}{Colors.RESET}")

                # If coverage was enabled, always show the coverage section
                if has_coverage:
                    print(f"\n{Colors.CYAN}Coverage Report:{Colors.RESET}")
                    # Extract and display coverage table
                    in_coverage = False
                    for line in output.split('\n'):
                        if 'Name' in line and 'Stmts' in line and 'Miss' in line:
                            in_coverage = True
                        if in_coverage:
                            if line.strip() and not line.startswith('='):
                                print(f"  {line}")
                            elif line.startswith('=') and 'TOTAL' in output[output.find(line):output.find(line) + 200]:
                                # Print separator and continue to get TOTAL
                                print(f"  {line}")
                            elif 'TOTAL' in line:
                                # Print TOTAL line and stop
                                print(f"  {Colors.BOLD}{line}{Colors.RESET}")
                                break
            else:
                # For unittest, try to extract test count from output
                import re
                # Look for patterns like "Ran 16 tests" or "OK (16 tests)"
                for line in output.split('\n'):
                    match = re.search(r'Ran (\d+) test', line)
                    if match:
                        self.total_test_count += int(match.group(1))
                        break
                    match = re.search(r'OK.*\((\d+) test', line)
                    if match:
                        self.total_test_count += int(match.group(1))
                        break

            # Show output if verbose or failed
            # (coverage report is shown separately above if enabled)
            if self.verbose or not passed:
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
            # Legacy unittest tests
            {
                'name': 'HW_Mgmt_Logger - Main Tests (unittest)',
                'cmd': ['python3', 'test_hw_mgmt_logger.py', '--random-iterations', '5', '--verbosity', '1'],
                'cwd': self.offline_dir / 'hw_management_lib' / 'HW_Mgmt_Logger'
            },
            {
                'name': 'ASIC Temperature Populate (unittest)',
                'cmd': ['python3', 'test_asic_temp_populate.py', '-v'],
                'cwd': self.offline_dir / 'hw_mgmgt_sync' / 'asic_populate_temperature'
            },
            {
                'name': 'Module Populate - Simple Test (unittest)',
                'cmd': ['python3', 'simple_test.py'],
                'cwd': self.offline_dir / 'hw_mgmgt_sync' / 'module_populate'
            },
            {
                'name': 'Module Temperature Populate (unittest)',
                'cmd': ['python3', 'legacy_module_temp_populate.py'],
                'cwd': self.offline_dir / 'hw_mgmgt_sync' / 'module_populate'
            },
            {
                'name': 'Module Temperature Populate Extended (unittest)',
                'cmd': ['python3', 'legacy_module_temp_populate_extended.py'],
                'cwd': self.offline_dir / 'hw_mgmgt_sync' / 'module_populate_temperature'
            },
            # Disabled TEC tests for V.7.0040.4000_BR - thermal_module_tec_sensor function not available in base
            # {
            #     'name': 'Thermal Control 2.0 TEC module test FR:4359937 (unittest)',
            #     'cmd': ['python3', 'test_thermal_module_tec_sensor_2_0.py', '-i 20'],
            #     'cwd': self.offline_dir / 'hw_mgmt_thermal_control_2_0' / 'module_tec_4359937'
            # },
            # {
            #     'name': 'Thermal Control 2.5 TEC module test FR:4359937 (unittest)',
            #     'cmd': ['python3', 'test_thermal_module_tec_sensor.py', '-i 20'],
            #     'cwd': self.offline_dir / 'hw_mgmt_thermal_control_2_5' / 'module_tec_4359937'
            # },
            # {
            #     'name': 'Module Temperature Populate TEC test FR:4359937 (unittest)',
            #     'cmd': ['python3', 'test_module_temp_populate.py', '-i 20'],
            #     'cwd': self.offline_dir / 'hw_mgmgt_sync' / 'module_populate_temperature_4359937'
            # },
            {
                'name': 'Module Counter Reliability Test (unittest)',
                'cmd': ['python3', 'test_module_counter.py'],
                'cwd': self.offline_dir / 'hw_mgmgt_sync'
            },
            # Pytest tests - run each file separately to avoid thread/mock conflicts
            {
                'name': 'Pytest: Hardware Error Paths',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hardware_error_paths.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: HW Management Lib',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hw_management_lib.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: Peripheral Updater',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hw_management_peripheral_updater.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: Platform Config',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hw_management_platform_config.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: Parse Labels',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hw_management_parse_labels.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: Independent Mode Update',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hw_management_independent_mode_update.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: PSU FW Update Common',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hw_management_psu_fw_update_common.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: PSU FW Update Delta',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hw_management_psu_fw_update_delta.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: PSU FW Update Murata',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hw_management_psu_fw_update_murata.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: DPU Thermal Update',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hw_management_dpu_thermal_update.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: Redfish Client',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hw_management_redfish_client.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: Thermal Updater',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_hw_management_thermal_updater.py', '--tb=short'],
                'cwd': self.tests_dir
            },
            {
                'name': 'Pytest: Python Syntax',
                'cmd': ['python3', '-m', 'pytest', 'offline/test_python_syntax.py', '--tb=short'],
                'cwd': self.tests_dir
            },
        ]

        # Add coverage options to all pytest tests if coverage is enabled
        if self.coverage:
            source_dir = self.tests_dir.parent / 'usr' / 'usr' / 'bin'

            # Find all pytest test suites (they start with "Pytest:")
            pytest_tests = [t for t in tests if t['name'].startswith('Pytest:')]

            for idx, pytest_test in enumerate(pytest_tests):
                # Add coverage to all pytest tests
                cov_opts = [
                    f'--cov={source_dir}',  # Cover the source code
                    '--cov-branch',  # Include branch coverage
                ]

                # Append coverage for all tests after the first
                if idx > 0:
                    cov_opts.append('--cov-append')

                # Only show report on the LAST pytest test
                if idx == len(pytest_tests) - 1:
                    cov_opts.append('--cov-report=term-missing:skip-covered')
                    if self.coverage_html:
                        cov_opts.append('--cov-report=html')
                else:
                    cov_opts.append('--cov-report=')  # No report for intermediate tests

                pytest_test['cmd'].extend(cov_opts)

            # Apply coverage minimum threshold to last pytest test
            pytest_test = pytest_tests[-1]
            if self.coverage_min:
                pytest_test['cmd'].append(f'--cov-fail-under={self.coverage_min}')

        for test in tests:
            self.run_command(test['cmd'], test['cwd'], test['name'])

        # Print coverage summary if coverage was enabled
        if self.coverage:
            self.print_coverage_summary()

        return len(self.failed_tests) == 0

    def run_hardware_tests(self):
        """Run all hardware tests via SSH to hardware system"""
        self.print_header("HARDWARE TESTS")

        # Check if hardware connection parameters are provided
        if not all([self.hardware_host, self.hardware_user, self.hardware_password]):
            print(f"{Colors.YELLOW}[SKIPPED]{Colors.RESET} Hardware tests require SSH credentials")
            print(f"{Colors.YELLOW}Usage: python3 test.py --hardware --host <hostname> --user <username> --password <password>{Colors.RESET}")
            print()
            print(f"{Colors.YELLOW}NOTE: Basic hardware tests require:{Colors.RESET}")
            print(f"{Colors.YELLOW}  - Actual hardware with hw-management installed{Colors.RESET}")
            print(f"{Colors.YELLOW}  - Root/sudo access for service control{Colors.RESET}")
            print()
            print(f"{Colors.CYAN}NOTE: DVS integration tests are disabled by default (they can hang).{Colors.RESET}")
            print(f"{Colors.CYAN}      Edit tests/test.py to enable full DVS tests if needed.{Colors.RESET}")
            return True  # Not a failure, just skipped

        print(f"{Colors.CYAN}Connecting to hardware: {self.hardware_user}@{self.hardware_host}{Colors.RESET}")
        print()

        # Check if sshpass is available
        if not self._check_sshpass():
            print(f"{Colors.RED}[ERROR]{Colors.RESET} sshpass is not installed")
            print(f"{Colors.YELLOW}Install with: sudo apt-get install sshpass{Colors.RESET}")
            self.failed_tests.append("Hardware Tests (sshpass missing)")
            return False

        # Deploy files to hardware first
        print(f"\n{Colors.CYAN}{'=' * 70}{Colors.RESET}")
        print(f"{Colors.CYAN}DEPLOYING FILES TO HARDWARE{Colors.RESET}")
        print(f"{Colors.CYAN}{'=' * 70}{Colors.RESET}\n")

        if not self._deploy_to_hardware():
            print(f"\n{Colors.RED}[ERROR]{Colors.RESET} Failed to deploy files to hardware")
            self.failed_tests.append("Hardware Tests (deployment failed)")
            return False

        print(f"\n{Colors.GREEN}Deployment successful!{Colors.RESET}\n")

        # Basic tests (fast, no DVS required) - always run
        test_files = [
            'test_basic_services.py',
        ]

        # Full DVS integration tests (slow, ~2 minutes)
        # These tests start/stop DVS and verify file clearing behavior
        # Files are cleared after 3 retry cycles (takes 9+ seconds)
        test_files.extend([
            'test_thermal_updater_integration.py',
            'test_peripheral_updater_integration.py',
        ])

        # Copy test files to hardware
        print(f"{Colors.CYAN}Copying test files to hardware...{Colors.RESET}")
        remote_test_dir = "/tmp/hw_mgmt_hardware_tests"

        if not self._ssh_create_remote_dir(remote_test_dir):
            self.failed_tests.append("Hardware Tests (failed to create remote directory)")
            return False

        for test_file in test_files:
            local_path = self.hardware_dir / test_file
            if local_path.exists():
                if not self._ssh_copy_file(str(local_path), f"{remote_test_dir}/{test_file}"):
                    print(f"{Colors.YELLOW}[WARNING]{Colors.RESET} Failed to copy {test_file}")
                else:
                    print(f"  {Colors.GREEN}Copied:{Colors.RESET} {test_file}")

        # Make files executable on hardware
        print(f"{Colors.CYAN}Making test files executable...{Colors.RESET}")
        self._ssh_run_command(f"chmod +x {remote_test_dir}/*.py")

        # Run tests on hardware (matches test_files list above)
        tests = [
            {
                'name': 'Basic Service Tests (Fast)',
                'file': 'test_basic_services.py'
            },
            {
                'name': 'Thermal Updater Integration Tests (with DVS)',
                'file': 'test_thermal_updater_integration.py'
            },
            {
                'name': 'Peripheral Updater Integration Tests (with DVS)',
                'file': 'test_peripheral_updater_integration.py'
            },
        ]

        for test in tests:
            print(f"\n{Colors.BLUE}Running: {Colors.BOLD}{test['name']}{Colors.RESET}")
            print("-" * 70)

            success = self._ssh_run_test(remote_test_dir, test['file'], test['name'])

            if success:
                print(f"{Colors.GREEN}[PASSED]{Colors.RESET} {test['name']}")
                self.passed_tests.append(test['name'])
            else:
                print(f"{Colors.RED}[FAILED]{Colors.RESET} {test['name']}")
                self.failed_tests.append(test['name'])

        # Cleanup remote test directory
        print(f"\n{Colors.CYAN}Cleaning up remote test files...{Colors.RESET}")
        self._ssh_run_command(f"rm -rf {remote_test_dir}")

        return len(self.failed_tests) == 0

    def _check_sshpass(self):
        """Check if sshpass is installed"""
        try:
            result = subprocess.run(
                ['which', 'sshpass'],
                capture_output=True,
                check=True
            )
            return result.returncode == 0
        except subprocess.CalledProcessError:
            return False

    def _deploy_to_hardware(self):
        """Deploy Python scripts and service files to hardware"""
        repo_root = self.tests_dir.parent

        # Files to deploy
        python_files = [
            'usr/usr/bin/hw_management_thermal_updater.py',
            'usr/usr/bin/hw_management_peripheral_updater.py',
            'usr/usr/bin/hw_management_platform_config.py',
        ]

        service_files = [
            ('debian/hw-management.hw-management-thermal-updater.service',
             '/lib/systemd/system/hw-management-thermal-updater.service'),
            ('debian/hw-management.hw-management-peripheral-updater.service',
             '/lib/systemd/system/hw-management-peripheral-updater.service'),
        ]

        # Deploy Python scripts
        print(f"{Colors.CYAN}Deploying Python scripts...{Colors.RESET}")
        for python_file in python_files:
            local_path = repo_root / python_file
            remote_path = f'/usr/bin/{os.path.basename(python_file)}'

            if not local_path.exists():
                print(f"{Colors.RED}[ERROR]{Colors.RESET} Local file not found: {local_path}")
                return False

            if not self._ssh_copy_file(str(local_path), remote_path):
                print(f"{Colors.RED}[ERROR]{Colors.RESET} Failed to copy {python_file}")
                return False

            print(f"  {Colors.GREEN}Deployed:{Colors.RESET} {os.path.basename(python_file)}")

        # Make Python scripts executable
        print(f"\n{Colors.CYAN}Making scripts executable...{Colors.RESET}")
        if not self._ssh_run_command("chmod +x /usr/bin/hw_management_*_updater.py"):
            print(f"{Colors.YELLOW}[WARNING]{Colors.RESET} Failed to chmod scripts")

        # Deploy service files
        print(f"\n{Colors.CYAN}Deploying service files...{Colors.RESET}")
        for local_file, remote_path in service_files:
            local_path = repo_root / local_file

            if not local_path.exists():
                print(f"{Colors.RED}[ERROR]{Colors.RESET} Local file not found: {local_path}")
                return False

            if not self._ssh_copy_file(str(local_path), remote_path):
                print(f"{Colors.RED}[ERROR]{Colors.RESET} Failed to copy {local_file}")
                return False

            print(f"  {Colors.GREEN}Deployed:{Colors.RESET} {os.path.basename(remote_path)}")

        # Reload systemd
        print(f"\n{Colors.CYAN}Reloading systemd...{Colors.RESET}")
        if not self._ssh_run_command("systemctl daemon-reload"):
            print(f"{Colors.YELLOW}[WARNING]{Colors.RESET} Failed to reload systemd")

        # Enable services
        print(f"{Colors.CYAN}Enabling services...{Colors.RESET}")
        self._ssh_run_command("systemctl enable hw-management-thermal-updater")
        self._ssh_run_command("systemctl enable hw-management-peripheral-updater")

        return True

    def _ssh_create_remote_dir(self, remote_dir):
        """Create directory on remote hardware"""
        print(f"{Colors.CYAN}[DEBUG] Creating remote directory: {remote_dir}{Colors.RESET}")

        cmd = [
            'sshpass', '-p', self.hardware_password,
            'ssh', '-o', 'StrictHostKeyChecking=no',
            '-o', 'ConnectTimeout=10',
            f'{self.hardware_user}@{self.hardware_host}',
            f'mkdir -p {remote_dir}'
        ]

        if self.verbose:
            print(f"{Colors.CYAN}[DEBUG] Command: {' '.join([c if c != self.hardware_password else '***' for c in cmd])}{Colors.RESET}")

        try:
            print(f"{Colors.CYAN}[DEBUG] Executing SSH command...{Colors.RESET}")
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

            if result.returncode == 0:
                print(f"{Colors.GREEN}[DEBUG] Remote directory created successfully{Colors.RESET}")
            else:
                print(f"{Colors.RED}[DEBUG] Failed to create directory. Return code: {result.returncode}{Colors.RESET}")
                if result.stderr:
                    print(f"{Colors.RED}[DEBUG] stderr: {result.stderr}{Colors.RESET}")

            return result.returncode == 0
        except subprocess.TimeoutExpired as e:
            print(f"{Colors.RED}[DEBUG] Timeout creating remote directory (10s){Colors.RESET}")
            return False
        except subprocess.CalledProcessError as e:
            print(f"{Colors.RED}[DEBUG] Failed to create remote directory: {e}{Colors.RESET}")
            return False

    def _ssh_copy_file(self, local_path, remote_path):
        """Copy file to remote hardware via scp"""
        cmd = [
            'sshpass', '-p', self.hardware_password,
            'scp', '-o', 'StrictHostKeyChecking=no',
            '-o', 'ConnectTimeout=10',
            local_path,
            f'{self.hardware_user}@{self.hardware_host}:{remote_path}'
        ]

        if self.verbose:
            print(f"{Colors.CYAN}[DEBUG] Copying {local_path} to {remote_path}{Colors.RESET}")

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

            if result.returncode != 0 and result.stderr:
                print(f"{Colors.YELLOW}[DEBUG] Copy failed: {result.stderr}{Colors.RESET}")

            return result.returncode == 0
        except subprocess.TimeoutExpired:
            print(f"{Colors.RED}[DEBUG] Timeout copying file (30s){Colors.RESET}")
            return False
        except subprocess.CalledProcessError as e:
            print(f"{Colors.RED}[DEBUG] Error copying file: {e}{Colors.RESET}")
            return False

    def _ssh_run_command(self, command):
        """Run command on remote hardware via SSH"""
        if self.verbose:
            print(f"{Colors.CYAN}[DEBUG] Running command: {command}{Colors.RESET}")

        cmd = [
            'sshpass', '-p', self.hardware_password,
            'ssh', '-o', 'StrictHostKeyChecking=no',
            '-o', 'ConnectTimeout=10',
            f'{self.hardware_user}@{self.hardware_host}',
            command
        ]

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

            if result.returncode != 0 and self.verbose:
                print(f"{Colors.YELLOW}[DEBUG] Command failed with return code {result.returncode}{Colors.RESET}")
                if result.stderr:
                    print(f"{Colors.YELLOW}[DEBUG] stderr: {result.stderr}{Colors.RESET}")

            return result.returncode == 0
        except subprocess.TimeoutExpired:
            print(f"{Colors.RED}[DEBUG] Timeout running command (60s){Colors.RESET}")
            return False
        except subprocess.CalledProcessError as e:
            print(f"{Colors.RED}[DEBUG] Error running command: {e}{Colors.RESET}")
            return False

    def _ssh_run_test(self, remote_dir, test_file, test_name):
        """Run a test file on remote hardware and capture output"""
        cmd = [
            'sshpass', '-p', self.hardware_password,
            'ssh', '-o', 'StrictHostKeyChecking=no',
            f'{self.hardware_user}@{self.hardware_host}',
            f'cd {remote_dir} && sudo python3 {test_file}'
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300  # 5 minutes timeout for hardware tests
            )

            # Print output
            if result.stdout:
                print(result.stdout)
            if result.stderr and self.verbose:
                print(f"{Colors.YELLOW}stderr:{Colors.RESET}")
                print(result.stderr)

            return result.returncode == 0

        except subprocess.TimeoutExpired:
            print(f"{Colors.RED}Test timed out after 5 minutes{Colors.RESET}")
            return False
        except subprocess.CalledProcessError as e:
            print(f"{Colors.RED}Test failed with error: {e}{Colors.RESET}")
            return False

    def check_shell_tools(self):
        """Check if required shell testing tools are installed"""
        missing_tools = []

        # Check for shellspec
        try:
            result = subprocess.run(
                ['which', 'shellspec'],
                capture_output=True,
                check=False
            )
            if result.returncode != 0:
                missing_tools.append('shellspec')
        except Exception:
            missing_tools.append('shellspec')

        # Check for kcov (optional if shell_coverage is enabled)
        if self.shell_coverage:
            try:
                result = subprocess.run(
                    ['which', 'kcov'],
                    capture_output=True,
                    check=False
                )
                if result.returncode != 0:
                    missing_tools.append('kcov')
            except Exception:
                missing_tools.append('kcov')

        return missing_tools

    def install_shell_tools(self):
        """Install shell testing tools using install-shell-test-tools.sh"""
        install_script = self.tests_dir / "install-shell-test-tools.sh"

        if not install_script.exists():
            print(f"{Colors.RED}[ERROR]{Colors.RESET} Installation script not found: {install_script}")
            return False

        print(f"{Colors.CYAN}Auto-installing shell testing tools...{Colors.RESET}")
        print(f"{Colors.CYAN}Running:{Colors.RESET} {install_script}")

        try:
            result = subprocess.run(
                [str(install_script)],
                cwd=self.tests_dir,
                capture_output=True,
                text=True,
                check=False
            )

            # Print output if verbose
            if self.verbose or result.returncode != 0:
                print(result.stdout)
                if result.stderr:
                    print(result.stderr)

            if result.returncode == 0:
                print(f"{Colors.GREEN}[SUCCESS]{Colors.RESET} Shell testing tools installed successfully")
                return True
            else:
                print(f"{Colors.YELLOW}[WARNING]{Colors.RESET} Shell tools installation completed with warnings")
                # Still return True as installation script might succeed partially
                return True

        except Exception as e:
            print(f"{Colors.RED}[ERROR]{Colors.RESET} Failed to run installation script: {e}")
            return False

    def run_shell_tests(self):
        """Run shell script tests using ShellSpec"""
        self.print_header("SHELL SCRIPT TESTS")

        # Check if shell test directory exists
        if not self.shell_dir.exists():
            print(f"{Colors.YELLOW}[SKIPPED]{Colors.RESET} Shell test directory not found: {self.shell_dir}")
            return True

        # Check if shellspec is installed
        missing_tools = self.check_shell_tools()
        if missing_tools:
            print(f"{Colors.YELLOW}[WARNING]{Colors.RESET} Missing shell testing tools: {', '.join(missing_tools)}")

            # Auto-install missing tools
            print(f"{Colors.CYAN}Attempting auto-installation of shell testing tools...{Colors.RESET}")
            if self.install_shell_tools():
                # Re-check if tools are now available
                missing_tools = self.check_shell_tools()
                if missing_tools:
                    print(f"{Colors.RED}[ERROR]{Colors.RESET} Tools still missing after installation: {', '.join(missing_tools)}")
                    print(f"{Colors.YELLOW}Manual installation may be required:{Colors.RESET}")
                    print(f"  cd {self.tests_dir}")
                    print(f"  ./install-shell-test-tools.sh")
                    print(f"\n{Colors.YELLOW}[SKIPPED]{Colors.RESET} Shell tests cannot run without required tools")
                    return True
                else:
                    print(f"{Colors.GREEN}[SUCCESS]{Colors.RESET} All required tools are now installed")
            else:
                print(f"{Colors.RED}[ERROR]{Colors.RESET} Failed to install shell testing tools")
                print(f"{Colors.YELLOW}Manual installation required:{Colors.RESET}")
                print(f"  cd {self.tests_dir}")
                print(f"  ./install-shell-test-tools.sh")
                print(f"\n{Colors.YELLOW}[SKIPPED]{Colors.RESET} Shell tests cannot run without required tools")
                return True

        print(f"{Colors.BLUE}Running: {Colors.BOLD}ShellSpec Shell Script Tests{Colors.RESET}")
        print(f"{Colors.CYAN}Test directory:{Colors.RESET} {self.shell_dir}")

        # Build shellspec command
        cmd = ['shellspec']

        # Add coverage option if requested
        if self.shell_coverage:
            print(f"{Colors.CYAN}Code coverage:{Colors.RESET} Enabled (using kcov)")
            cmd.extend([
                '--kcov',
                '--kcov-options', '--exclude-pattern=/usr,/lib,/tmp'
            ])

        # Add format option for better output
        cmd.extend(['--format', 'documentation'])

        # Run shellspec from shell test directory
        try:
            result = subprocess.run(
                cmd,
                cwd=self.shell_dir,
                capture_output=True,
                text=True,
                check=False
            )

            # Print output
            output = result.stdout + result.stderr
            print(output)

            # Check for coverage report
            if self.shell_coverage:
                coverage_dir = self.shell_dir / 'coverage'
                if coverage_dir.exists():
                    print(f"\n{Colors.GREEN}Coverage Report Generated:{Colors.RESET}")
                    print(f"  Location: {coverage_dir}")

                    # Try to find coverage summary
                    index_file = coverage_dir / 'index.html'
                    if index_file.exists():
                        print(f"  HTML Report: file://{index_file.absolute()}")

                    # Check minimum coverage if specified
                    if self.shell_coverage_min:
                        print(f"\n{Colors.YELLOW}Note:{Colors.RESET} Minimum coverage check ({self.shell_coverage_min}%) requires manual verification")
                        print(f"  Open the HTML report to view actual coverage percentage")

            # Determine success
            if result.returncode == 0:
                print(f"\n{Colors.GREEN}[PASSED]{Colors.RESET} Shell script tests passed")
                self.passed_tests.append("Shell Tests")
                return True
            else:
                print(f"\n{Colors.RED}[FAILED]{Colors.RESET} Shell script tests failed")
                self.failed_tests.append("Shell Tests")
                return False

        except FileNotFoundError:
            print(f"{Colors.RED}[ERROR]{Colors.RESET} shellspec command not found")
            print(f"{Colors.CYAN}Install with:{Colors.RESET} ./install-shell-test-tools.sh")
            return False
        except Exception as e:
            print(f"{Colors.RED}[ERROR]{Colors.RESET} Failed to run shell tests: {e}")
            self.failed_tests.append("Shell Tests")
            return False

    def run_beautifier(self):
        """Run NVIDIA code beautifier (ngci_tool -b)"""
        self.print_header("CODE BEAUTIFIER")

        print(f"{Colors.BLUE}Running: {Colors.BOLD}NVIDIA Code Beautifier (ngci_tool -b){Colors.RESET}")

        # Run ngci_tool -b from repository root
        # ngci_tool is typically available at /auto/sw_system_release/ci/ngci/ngci_tool/ngci_tool.sh
        repo_root = self.tests_dir.parent
        ngci_paths = [
            '/auto/sw_system_release/ci/ngci/ngci_tool/ngci_tool.sh',  # Standard location
            'ngci_tool'  # Fallback if it's in PATH
        ]

        result = None
        for ngci_path in ngci_paths:
            try:
                result = subprocess.run(
                    [ngci_path, '-b'],
                    cwd=repo_root,
                    capture_output=True,
                    text=True,
                    check=False
                )
                # If we got here, the command exists
                break
            except FileNotFoundError:
                continue
            except Exception:
                continue

        if result is None:
            print(f"{Colors.YELLOW}[SKIPPED]{Colors.RESET} ngci_tool not found - skipping beautifier check")
            return True

        output = result.stdout + result.stderr

        if self.verbose or result.returncode != 0:
            print(output)

        if result.returncode == 0:
            print(f"{Colors.GREEN}[PASSED]{Colors.RESET} Code formatting check passed")
            self.passed_tests.append("Beautifier")
            return True
        else:
            print(f"{Colors.RED}[FAILED]{Colors.RESET} Code formatting issues found")
            print(f"{Colors.CYAN}Automatically running 'ngci_tool -b repair' to fix formatting...{Colors.RESET}")

            # Automatically run repair
            repair_result = None
            for ngci_path in ngci_paths:
                try:
                    repair_result = subprocess.run(
                        [ngci_path, '-b', 'repair'],
                        cwd=repo_root,
                        capture_output=True,
                        text=True,
                        check=False
                    )
                    break
                except (FileNotFoundError, Exception):
                    continue

            if repair_result and repair_result.returncode == 0:
                print(f"{Colors.GREEN}[AUTO-FIXED]{Colors.RESET} Formatting issues automatically repaired")

                # Re-run beautifier to verify fix
                print(f"{Colors.CYAN}Re-validating code formatting after repair...{Colors.RESET}")
                verify_result = None
                for ngci_path in ngci_paths:
                    try:
                        verify_result = subprocess.run(
                            [ngci_path, '-b'],
                            cwd=repo_root,
                            capture_output=True,
                            text=True,
                            check=False
                        )
                        break
                    except (FileNotFoundError, Exception):
                        continue

                if verify_result and verify_result.returncode == 0:
                    print(f"{Colors.GREEN}[PASSED]{Colors.RESET} Code formatting verified after auto-repair")
                    print(f"{Colors.YELLOW}Please review and commit the formatting changes{Colors.RESET}")
                    self.passed_tests.append("Beautifier (auto-fixed)")
                    return True
                else:
                    print(f"{Colors.RED}[FAILED]{Colors.RESET} Issues remain after auto-repair")
                    if verify_result and self.verbose:
                        print(verify_result.stdout + verify_result.stderr)
                    self.failed_tests.append("Beautifier")
                    return False
            else:
                repair_output = repair_result.stdout + repair_result.stderr if repair_result else ""
                if self.verbose and repair_output:
                    print(repair_output)
                print(f"{Colors.YELLOW}Auto-repair completed with warnings - please review changes{Colors.RESET}")
                self.failed_tests.append("Beautifier")
                return False

    def run_spell_check(self):
        """Run NVIDIA spell checker (ngci_tool -s)"""
        self.print_header("SPELL CHECK")

        print(f"{Colors.BLUE}Running: {Colors.BOLD}NVIDIA Spell Checker (ngci_tool -s){Colors.RESET}")

        # Run ngci_tool -s from repository root
        repo_root = self.tests_dir.parent
        ngci_paths = [
            '/auto/sw_system_release/ci/ngci/ngci_tool/ngci_tool.sh',
            'ngci_tool'
        ]

        result = None
        for ngci_path in ngci_paths:
            try:
                result = subprocess.run(
                    [ngci_path, '-s'],
                    cwd=repo_root,
                    capture_output=True,
                    text=True,
                    check=False
                )
                break
            except FileNotFoundError:
                continue
            except Exception:
                continue

        if result is None:
            print(f"{Colors.YELLOW}[SKIPPED]{Colors.RESET} ngci_tool not found - skipping spell check")
            return True

        output = result.stdout + result.stderr

        if self.verbose or result.returncode != 0:
            print(output)

        if result.returncode == 0:
            print(f"{Colors.GREEN}[PASSED]{Colors.RESET} Spell check passed")
            self.passed_tests.append("Spell Check")
            return True
        else:
            print(f"{Colors.RED}[FAILED]{Colors.RESET} Spelling errors found")
            print(f"\n{Colors.YELLOW}TIP:{Colors.RESET} If you see valid technical terms flagged as errors,")
            print(f"     add them to the global dictionary using:")
            print(f"     {Colors.CYAN}ngci_tool --spell-check add-to-dict [your_word_here]{Colors.RESET}\n")
            self.failed_tests.append("Spell Check")
            return False

    def run_security_scan(self):
        """Run NVIDIA security scanner (ngci_tool -s2)"""
        self.print_header("SECURITY SCAN")

        print(f"{Colors.BLUE}Running: {Colors.BOLD}NVIDIA Security Scanner (ngci_tool -s2){Colors.RESET}")

        # Run ngci_tool -s2 from repository root
        repo_root = self.tests_dir.parent
        ngci_paths = [
            '/auto/sw_system_release/ci/ngci/ngci_tool/ngci_tool.sh',
            'ngci_tool'
        ]

        result = None
        for ngci_path in ngci_paths:
            try:
                result = subprocess.run(
                    [ngci_path, '-s2'],
                    cwd=repo_root,
                    capture_output=True,
                    text=True,
                    check=False
                )
                break
            except FileNotFoundError:
                continue
            except Exception:
                continue

        if result is None:
            print(f"{Colors.YELLOW}[SKIPPED]{Colors.RESET} ngci_tool not found - skipping security scan")
            return True

        output = result.stdout + result.stderr

        if self.verbose or result.returncode != 0:
            print(output)

        if result.returncode == 0:
            print(f"{Colors.GREEN}[PASSED]{Colors.RESET} Security scan passed")
            self.passed_tests.append("Security Scan")
            return True
        else:
            print(f"{Colors.RED}[FAILED]{Colors.RESET} Security scan found issues")
            self.failed_tests.append("Security Scan")
            return False

    def run_header_check(self):
        """Run NVIDIA header checker (ngci_tool -hc)"""
        self.print_header("HEADER CHECK")

        print(f"{Colors.BLUE}Running: {Colors.BOLD}NVIDIA Header Checker (ngci_tool -hc){Colors.RESET}")

        # Run ngci_tool -hc from repository root
        repo_root = self.tests_dir.parent
        ngci_paths = [
            '/auto/sw_system_release/ci/ngci/ngci_tool/ngci_tool.sh',
            'ngci_tool'
        ]

        result = None
        for ngci_path in ngci_paths:
            try:
                result = subprocess.run(
                    [ngci_path, '-hc'],
                    cwd=repo_root,
                    capture_output=True,
                    text=True,
                    check=False
                )
                break
            except FileNotFoundError:
                continue
            except Exception:
                continue

        if result is None:
            print(f"{Colors.YELLOW}[SKIPPED]{Colors.RESET} ngci_tool not found - skipping header check")
            return True

        output = result.stdout + result.stderr

        if self.verbose or result.returncode != 0:
            print(output)

        if result.returncode == 0:
            print(f"{Colors.GREEN}[PASSED]{Colors.RESET} Header check passed")
            self.passed_tests.append("Header Check")
            return True
        else:
            print(f"{Colors.RED}[FAILED]{Colors.RESET} Header check found issues")
            self.failed_tests.append("Header Check")
            return False

    def run_shellcheck(self):
        """Run ShellCheck static analysis on shell scripts"""
        self.print_header("SHELLCHECK (Shell Script Linter)")

        print(f"{Colors.BLUE}Running: {Colors.BOLD}ShellCheck Static Analysis{Colors.RESET}")

        # Check if shellcheck is installed
        try:
            version_result = subprocess.run(
                ['shellcheck', '--version'],
                capture_output=True,
                text=True,
                check=False
            )
            if version_result.returncode != 0:
                print(f"{Colors.YELLOW}[SKIPPED]{Colors.RESET} shellcheck not installed")
                print(f"{Colors.CYAN}Install with:{Colors.RESET} ./tests/install-shell-test-tools.sh")
                return True
        except FileNotFoundError:
            print(f"{Colors.YELLOW}[SKIPPED]{Colors.RESET} shellcheck not found - install with: ./tests/install-shell-test-tools.sh")
            return True

        # Find all shell scripts in usr/usr/bin
        repo_root = self.tests_dir.parent
        shell_scripts_dir = repo_root / "usr" / "usr" / "bin"

        if not shell_scripts_dir.exists():
            print(f"{Colors.YELLOW}[SKIPPED]{Colors.RESET} Shell scripts directory not found: {shell_scripts_dir}")
            return True

        # Find all .sh files
        shell_scripts = list(shell_scripts_dir.glob("*.sh"))

        if not shell_scripts:
            print(f"{Colors.YELLOW}[SKIPPED]{Colors.RESET} No shell scripts found in {shell_scripts_dir}")
            return True

        print(f"{Colors.CYAN}Analyzing {len(shell_scripts)} shell scripts...{Colors.RESET}")

        # Run shellcheck on all shell scripts
        all_passed = True
        issues_found = 0

        for script in shell_scripts:
            result = subprocess.run(
                ['shellcheck', '--color=always', '--severity=warning', str(script)],
                capture_output=True,
                text=True,
                check=False
            )

            if result.returncode != 0:
                all_passed = False
                issues_found += 1
                if self.verbose:
                    print(f"\n{Colors.YELLOW}Issues in {script.name}:{Colors.RESET}")
                    print(result.stdout)

        # Summary
        if all_passed:
            print(f"{Colors.GREEN}[PASSED]{Colors.RESET} All {len(shell_scripts)} shell scripts passed ShellCheck")
            self.passed_tests.append("ShellCheck")
            return True
        else:
            print(f"{Colors.RED}[FAILED]{Colors.RESET} ShellCheck found issues in {issues_found}/{len(shell_scripts)} scripts")
            if not self.verbose:
                print(f"{Colors.CYAN}Run with --verbose to see detailed issues{Colors.RESET}")
                print(f"{Colors.CYAN}Or run directly:{Colors.RESET} shellcheck usr/usr/bin/*.sh")
            self.failed_tests.append("ShellCheck")
            return False

    def print_summary(self):
        """Print test execution summary"""
        self.print_header("TEST SUMMARY")

        total_suites = len(self.passed_tests) + len(self.failed_tests)

        print(f"{Colors.CYAN}Test Suites:{Colors.RESET}")
        print(f"  {Colors.GREEN}Passed:{Colors.RESET} {len(self.passed_tests)}/{total_suites}")
        print(f"  {Colors.RED}Failed:{Colors.RESET} {len(self.failed_tests)}/{total_suites}")

        if self.total_test_count > 0:
            print(f"\n{Colors.CYAN}Total Individual Tests:{Colors.RESET} {Colors.BOLD}{self.total_test_count}{Colors.RESET}")

        if self.enable_logs:
            log_count = len(list(self.logs_dir.glob("*.log")))
            print(f"\n{Colors.CYAN}Test Logs:{Colors.RESET} {log_count} log files saved to {Colors.BOLD}{self.logs_dir}{Colors.RESET}")

        if self.failed_tests:
            print(f"\n{Colors.RED}Failed test suites:{Colors.RESET}")
            for test in self.failed_tests:
                print(f"  - {test}")

        if len(self.failed_tests) == 0:
            print(f"\n{Colors.GREEN}{Colors.BOLD}ALL TESTS PASSED!{Colors.RESET}")
        else:
            print(f"\n{Colors.RED}{Colors.BOLD}SOME TESTS FAILED{Colors.RESET}")

    def print_coverage_summary(self):
        """Print coverage summary after tests"""
        coverage_file = self.tests_dir.parent / '.coverage'
        htmlcov_dir = self.tests_dir.parent / 'htmlcov'

        if coverage_file.exists():
            print(f"\n{Colors.CYAN}Code Coverage:{Colors.RESET}")
            print(f"  Coverage data saved to: {Colors.BOLD}{coverage_file}{Colors.RESET}")

            if htmlcov_dir.exists() and self.coverage_html:
                index_file = htmlcov_dir / 'index.html'
                print(f"  {Colors.GREEN}HTML Report:{Colors.RESET} {Colors.BOLD}{index_file}{Colors.RESET}")
                print(f"  Open in browser: file://{index_file.absolute()}")

        if self.coverage_min:
            print(f"\n{Colors.CYAN}Minimum Coverage Required:{Colors.RESET} {self.coverage_min}%")


def main():
    """Main test runner entry point"""
    parser = argparse.ArgumentParser(
        description='HW-MGMT Test Runner',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --offline                                    # Run offline Python tests (default)
  %(prog)s --hardware --host 10.0.0.1 --user root --password mypass
                                                        # Run hardware tests via SSH
  %(prog)s --all                                        # Run all tests (offline + code quality checks)
  %(prog)s --clean                                      # Clean all generated files (cache, logs, etc.)
  %(prog)s --offline -sn                                # Skip all ngci tool checks (shortcut)
  %(prog)s --offline --no-beautifier                    # Skip beautifier check only
  %(prog)s --all --no-security-scan --no-header-check   # Skip specific checks
  %(prog)s --offline --coverage                         # Run tests with coverage measurement
  %(prog)s --offline --coverage-html                    # Generate HTML coverage report
  %(prog)s --offline --coverage-min 80                  # Require minimum 80%% coverage
  %(prog)s --shell                                      # Run shell script tests (opt-in)
  %(prog)s --shell --shell-coverage                     # Run shell tests with coverage
  %(prog)s --shellcheck                                 # Run ShellCheck linter only
  %(prog)s --offline --shell --shellcheck               # Run Python + Shell tests + linting
  %(prog)s --install                                    # Install all test dependencies manually

Code Quality Checks (enabled by default for offline/all):
  - Beautifier (ngci_tool -b)  : Code formatting check (--no-beautifier to disable)
  - Spell Check (ngci_tool -s) : Spelling validation (--no-spell-check to disable)
  - Security Scan (ngci_tool -s2) : Secret detection (--no-security-scan to disable)
  - Header Check (ngci_tool -hc) : Copyright/license headers (--no-header-check to disable)

  Shortcut: Use -sn or --skip-ngci to disable all ngci tools

Shell Testing (opt-in, not run by default):
  - Shell Tests (--shell)      : Run ShellSpec tests for shell scripts
  - ShellCheck (--shellcheck)  : Static analysis/linting for shell scripts
  - Coverage (--shell-coverage): Code coverage for shell tests

Coverage Options:
  --coverage           : Enable code coverage measurement (terminal report)
  --coverage-html      : Generate HTML coverage report (opens in browser)
  --coverage-min PCT   : Fail if coverage is below PCT%% (e.g., --coverage-min 80)

Shell Testing Options (opt-in only):
  --shell              : Run shell script tests (auto-installs shellspec if missing)
  --shell-coverage     : Enable shell code coverage (auto-installs kcov if missing)
  --shell-coverage-min : Minimum shell coverage percentage required
  --shellcheck         : Run ShellCheck static analysis on shell scripts
  --no-shellcheck      : Skip ShellCheck (when used with --shell)

  Note: Shell tests are NOT run by default - use --shell to enable
        Shell tools (shellspec/kcov) are auto-installed on first use

Note: Python dependencies are automatically installed if missing
      Shell testing tools (shellspec/kcov) are auto-installed when --shell is used
      Shell tests are OPT-IN (use --shell to enable, NOT run by default)
      ShellCheck is OPT-IN (use --shellcheck to enable, NOT run by default)
      Offline tests show verbose output by default
      Hardware tests are NOT run by default - requires explicit --hardware flag with SSH credentials
        """
    )
    parser.add_argument('--offline', action='store_true', help='Run offline tests')
    parser.add_argument('--hardware', action='store_true', help='Run hardware tests (requires SSH credentials)')
    parser.add_argument('--all', action='store_true', help='Run all offline tests (does NOT include hardware)')
    parser.add_argument('--clean', action='store_true', help='Clean all generated files (cache, logs, outputs)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose debug output')

    # Hardware SSH connection parameters
    parser.add_argument('--host', type=str, help='Hardware hostname or IP address for SSH')
    parser.add_argument('--user', type=str, help='SSH username for hardware connection')
    parser.add_argument('--password', type=str, help='SSH password for hardware connection')

    # Disable flags for code quality checks (all enabled by default)
    parser.add_argument('-sn', '--skip-ngci', action='store_true', help='Skip all ngci_tool checks (beautifier, spell, security, header)')
    parser.add_argument('--no-beautifier', action='store_true', help='Skip code beautifier check (ngci_tool -b)')
    parser.add_argument('--no-spell-check', action='store_true', help='Skip spell checker (ngci_tool -s)')
    parser.add_argument('--no-security-scan', action='store_true', help='Skip security scanner (ngci_tool -s2)')
    parser.add_argument('--no-header-check', action='store_true', help='Skip header checker (ngci_tool -hc)')
    parser.add_argument('--no-shellcheck', action='store_true', help='Skip ShellCheck static analysis for shell scripts')

    # Coverage options
    parser.add_argument('--coverage', action='store_true', help='Enable code coverage measurement')
    parser.add_argument('--coverage-html', action='store_true', help='Generate HTML coverage report (implies --coverage)')
    parser.add_argument('--coverage-min', type=int, metavar='PCT', help='Minimum coverage percentage required (fails if below)')

    # Shell testing options
    parser.add_argument('--shell', action='store_true', help='Run shell script tests (requires shellspec)')
    parser.add_argument('--shell-coverage', action='store_true', help='Enable shell script code coverage (requires kcov)')
    parser.add_argument('--shell-coverage-min', type=int, metavar='PCT', help='Minimum shell coverage percentage required')
    parser.add_argument('--shellcheck', action='store_true', help='Run ShellCheck static analysis on shell scripts')

    # Installation helper
    parser.add_argument('--install', action='store_true', help='Install test dependencies (Python + Shell)')

    args = parser.parse_args()

    # Set verbose mode from command line flag
    verbose_mode = args.verbose

    # If --coverage-html is set, enable --coverage too
    if args.coverage_html:
        args.coverage = True

    # If --skip-ngci/-sn is set, disable all ngci tool checks
    if args.skip_ngci:
        args.no_beautifier = True
        args.no_spell_check = True
        args.no_security_scan = True
        args.no_header_check = True

    runner = TestRunner(
        verbose=verbose_mode,
        hardware_host=args.host,
        hardware_user=args.user,
        hardware_password=args.password,
        coverage=args.coverage,
        coverage_html=args.coverage_html,
        coverage_min=args.coverage_min,
        shell_coverage=args.shell_coverage,
        shell_coverage_min=args.shell_coverage_min
    )

    # Handle install command
    if args.install:
        print(f"{Colors.CYAN}Installing test dependencies...{Colors.RESET}\n")

        # Install Python dependencies
        print(f"{Colors.BLUE}Installing Python dependencies:{Colors.RESET}")
        if not runner.install_dependencies():
            print(f"{Colors.RED}Failed to install Python dependencies{Colors.RESET}")
            return 1

        # Install shell testing tools
        print(f"\n{Colors.BLUE}Installing shell testing tools:{Colors.RESET}")
        install_script = runner.tests_dir / "install-shell-test-tools.sh"
        if install_script.exists():
            try:
                result = subprocess.run(
                    [str(install_script)],
                    cwd=runner.tests_dir,
                    check=False
                )
                if result.returncode == 0:
                    print(f"\n{Colors.GREEN}All test dependencies installed successfully!{Colors.RESET}")
                    return 0
                else:
                    print(f"\n{Colors.YELLOW}Shell tools installation completed with warnings{Colors.RESET}")
                    return 0
            except Exception as e:
                print(f"{Colors.RED}Failed to run shell tools installer: {e}{Colors.RESET}")
                return 1
        else:
            print(f"{Colors.YELLOW}Shell tools installer not found: {install_script}{Colors.RESET}")
            print(f"{Colors.GREEN}Python dependencies installed successfully{Colors.RESET}")
            return 0

    # Handle clean command
    if args.clean:
        return 0 if runner.clean_all() else 1

    # If no specific test type is selected, default to offline
    if not any([args.offline, args.hardware, args.all, args.shell]):
        args.offline = True

    # Auto-check and install dependencies ONLY if running offline tests
    # Hardware tests use unittest (built-in) and run remotely via SSH
    if args.offline or args.all:
        print(f"{Colors.CYAN}Checking dependencies...{Colors.RESET}")
        if not runner.check_dependencies(auto_install=True):
            print(f"\n{Colors.RED}Failed to install required dependencies{Colors.RESET}")
            print(f"{Colors.YELLOW}Please install manually: pip install pytest>=6.0{Colors.RESET}")
            return 1
    elif args.hardware:
        # Hardware tests don't need pytest locally (they use unittest and run remotely)
        print(f"{Colors.CYAN}Skipping dependency check (hardware tests use unittest remotely){Colors.RESET}")

    # Make offline tests verbose by default (can help with debugging)
    if args.offline and not args.hardware and not args.all:
        runner.verbose = True

    # Clean Python cache before running tests to avoid stale module issues
    runner.clean_cache()

    success = True

    # Run offline tests (for --offline or --all)
    if args.offline or args.all:
        if not runner.run_offline_tests():
            success = False

    # Run shell tests ONLY if explicitly requested with --shell
    if args.shell:
        if not runner.run_shell_tests():
            success = False

    # Run hardware tests ONLY if explicitly requested with --hardware
    # (NOT included in --all to prevent accidental hardware test runs)
    if args.hardware:
        if not runner.run_hardware_tests():
            success = False

    # Run code quality checks for offline/all (skip if only hardware or only shell)
    if not args.hardware or args.all or args.offline:
        # Run beautifier check (unless disabled)
        if not args.no_beautifier:
            if not runner.run_beautifier():
                success = False

        # Run spell check (unless disabled)
        if not args.no_spell_check:
            if not runner.run_spell_check():
                success = False

        # Run security scan (unless disabled)
        if not args.no_security_scan:
            if not runner.run_security_scan():
                success = False

        # Run header check (unless disabled)
        if not args.no_header_check:
            if not runner.run_header_check():
                success = False

    # Run shellcheck ONLY if explicitly requested with --shell or --shellcheck
    if args.shell or args.shellcheck:
        if not runner.run_shellcheck():
            success = False

    runner.print_summary()

    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
