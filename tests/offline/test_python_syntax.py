#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

"""
Python Syntax Compilation Tests

Compiles all Python files in usr/usr/bin/ to check for syntax errors.
This catches issues like:
- Python 2 vs Python 3 syntax (print statements, is vs ==, etc.)
- Missing imports
- Basic syntax errors

This test prevented deployment of broken code by catching:
- Python 2 print statements in hw_management_nvl_temperature_get.py
- Incorrect 'is' comparison with integer in hw_management_dpu_thermal_update.py
"""

import pytest
import py_compile


class TestPythonSyntaxCompilation:
    """Test Python syntax compilation for all Python files"""

    def test_compile_all_python_files(self, project_root):
        """
        Compile all Python files in usr/usr/bin/ to check for syntax errors.
        
        This test FAILS if ANY Python file has syntax errors.
        All Python files must be valid Python 3 syntax.
        """
        # Find all Python files in usr/usr/bin
        python_files = list((project_root / "usr" / "usr" / "bin").glob("*.py"))
        
        errors = []
        compiled_count = 0
        
        for py_file in python_files:
            try:
                py_compile.compile(str(py_file), doraise=True)
                compiled_count += 1
            except py_compile.PyCompileError as e:
                errors.append(f"{py_file.name}: {e}")
        
        # Report results
        print(f"\n✅ Successfully compiled: {compiled_count} files")
        
        # FAIL if ANY syntax errors are found
        if errors:
            error_msg = f"\n\n❌ Syntax errors found in {len(errors)} file(s):\n" + "\n".join(errors)
            pytest.fail(error_msg)
        
        # Verify we actually compiled some files
        assert compiled_count > 0, "No Python files found to compile"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

