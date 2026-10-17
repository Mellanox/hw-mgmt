#!/bin/sh
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2020-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

# Thermal control launcher: read tc_version from tc_config.json and exec the
# matching Python binary.  "exec" replaces this shell process so Python becomes
# the systemd MAINPID directly — no sh wrapper, no ExecStop needed.
#
# tc_config.json is written by hw-management.sh (set_config_data) before
# hw-management.service becomes active, so the file is always present when
# this launcher is called (hw-management-tc.service has After=hw-management.service).
# Defaults to v2.0 when the file is absent or tc_version is unrecognised.

tc_cfg=/var/run/hw-management/config/tc_config.json

tc_ver=$(grep -o '"tc_version"[[:space:]]*:[[:space:]]*"[^"]*"' "$tc_cfg" 2>/dev/null \
         | head -n1 | cut -d'"' -f4)

case $tc_ver in
    2.5|2.5.*)
        exec /usr/bin/hw_management_thermal_control_2_5.py
        ;;
    *)
        exec /usr/bin/hw_management_thermal_control.py
        ;;
esac
