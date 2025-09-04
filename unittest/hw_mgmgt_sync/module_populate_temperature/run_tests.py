#!/usr/bin/env python3
"""
Test runner for module_temp_populate unit tests

This script provides a simple way to run all tests for the module_temp_populate function
with proper error handling and detailed output.
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path

def find_hw_mgmt_path():
    """Find the path to hw_management_sync.py"""
    # Start from current script location
    current_dir = Path(__file__).parent.absolute()
    
    # Look for hw_management_sync.py in usr/usr/bin relative to project root
    project_root = current_dir.parent.parent.parent
    hw_mgmt_file = project_root / "usr" / "usr" / "bin" / "hw_management_sync.py"
    
    if hw_mgmt_file.exists():
        return str(hw_mgmt_file)
    
    # Alternative search - look for it in the current working directory tree
    cwd = Path.cwd()
    for parent in [cwd] + list(cwd.parents):
        potential_path = parent / "usr" / "usr" / "bin" / "hw_management_sync.py"
        if potential_path.exists():
            return str(potential_path)
    
    return None

def run_tests(test_file=None, verbose=False, hw_mgmt_path=None):
    """Run the test suite"""
    current_dir = Path(__file__).parent.absolute()
    
    if test_file is None:
        test_file = current_dir / "test_module_temp_populate.py"
    
    if not test_file.exists():
        print(f"❌ Test file not found: {test_file}")
        return False
    
    if hw_mgmt_path is None:
        hw_mgmt_path = find_hw_mgmt_path()
    
    if hw_mgmt_path is None:
        print("❌ Could not find hw_management_sync.py")
        print("Please specify the path using --hw-mgmt-path option")
        return False
    
    if not Path(hw_mgmt_path).exists():
        print(f"❌ hw_management_sync.py not found at: {hw_mgmt_path}")
        return False
    
    print("=" * 80)
    print("🚀 MODULE_TEMP_POPULATE TEST RUNNER")
    print("=" * 80)
    print(f"📁 Test file: {test_file}")
    print(f"📁 hw_management_sync.py: {hw_mgmt_path}")
    print(f"🐍 Python: {sys.executable}")
    print("=" * 80)
    
    # Prepare command
    cmd = [
        sys.executable,
        str(test_file)
    ]
    
    if verbose:
        cmd.extend(['-v'])
    
    # Set environment
    env = os.environ.copy()
    env['PYTHONPATH'] = str(current_dir.parent.parent.parent / "usr" / "usr" / "bin")
    
    try:
        # Run tests
        result = subprocess.run(
            cmd,
            cwd=str(current_dir),
            env=env
        )
        
        print("=" * 80)
        if result.returncode == 0:
            print("✅ All tests passed!")
        else:
            print("❌ Some tests failed!")
        print("=" * 80)
        
        return result.returncode == 0
        
    except Exception as e:
        print(f"❌ Error running tests: {e}")
        return False

def main():
    """Main function with command line argument parsing"""
    parser = argparse.ArgumentParser(
        description='Run module_temp_populate unit tests',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run all tests with auto-detection of hw_management_sync.py
  python3 run_tests.py
  
  # Run tests with verbose output
  python3 run_tests.py --verbose
  
  # Run tests with specific hw_management_sync.py path
  python3 run_tests.py --hw-mgmt-path /path/to/hw_management_sync.py
  
  # Run specific test file
  python3 run_tests.py --test-file test_module_temp_populate.py
        """
    )
    
    parser.add_argument(
        '--test-file',
        type=Path,
        help='Path to test file (default: test_module_temp_populate.py)'
    )
    
    parser.add_argument(
        '--hw-mgmt-path',
        type=str,
        help='Path to hw_management_sync.py file'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Enable verbose test output'
    )
    
    parser.add_argument(
        '--list-tests',
        action='store_true',
        help='List available test methods'
    )
    
    args = parser.parse_args()
    
    if args.list_tests:
        print("Available test methods:")
        print("- test_normal_condition_all_files_present")
        print("- test_input_read_error_default_values")
        print("- test_other_attributes_read_error")
        print("- test_error_handling_no_crash")
        print("- test_random_module_configuration")
        print("- test_sdk_temp2degree_function")
        print("- test_module_count_argument_validation")
        print("- test_sw_control_mode_ignored")
        return
    
    success = run_tests(
        test_file=args.test_file,
        verbose=args.verbose,
        hw_mgmt_path=args.hw_mgmt_path
    )
    
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()
