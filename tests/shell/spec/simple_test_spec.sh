#!/bin/bash
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

################################################################################
# ShellSpec simple test - verify shell testing infrastructure works
#
# This is a minimal test to verify shellspec is working correctly
################################################################################

Describe 'Shell testing infrastructure'
    It 'can run basic assertions'
        When call echo "hello world"
        The output should equal "hello world"
        The status should be success
    End
    
    It 'can test variables'
        TEST_VAR="test value"
        The variable TEST_VAR should equal "test value"
    End
    
    It 'can test files'
        temp_file=$(mktemp)
        echo "test content" > "$temp_file"
        The path "$temp_file" should be exist
        The contents of file "$temp_file" should include "test content"
        rm -f "$temp_file"
    End
    
    It 'can test return codes'
        When call bash -c "exit 0"
        The status should equal 0
    End
    
    It 'can test string matching'
        When call echo "test123"
        The output should start with "test"
        The output should end with "123"
    End
End

