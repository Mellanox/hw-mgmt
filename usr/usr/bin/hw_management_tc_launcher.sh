#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2020-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

# Thermal control launcher. Read tc_version from tc_config.json and exec the
# matching Python binary, so that binary is the systemd MAINPID.
#
# tc_config.json is written by hw-management.sh before hw-management.service
# becomes active. hw-management-tc.service has After=hw-management.service,
# so the file is present on the first start. A missing or unrecognised
# tc_version selects v2.0.
#
# The unit Description carries the thermal control version as major.minor:
# "Thermal control service (ver 2.5) of Nvidia systems" when tc_version is 2.5
# (or 2.5.*), and "(ver 2.0)" for anything else. Only the Description line is
# edited, never ExecStart. daemon-reload runs only when the value changes.
#
# hw-management-start-post.sh calls this script with --describe after
# tc_config.json is written. That updates the description without starting
# thermal control, so the version is visible while the unit is still inactive.
# A normal start (no arguments) refreshes the description and then execs the
# binary.

describe_only=0
if [ "$1" = "--describe" ]; then
	describe_only=1
fi

tc_cfg=/var/run/hw-management/config/tc_config.json

tc_ver=$(grep -o '"tc_version"[[:space:]]*:[[:space:]]*"[^"]*"' "$tc_cfg" 2>/dev/null \
	| head -n1 | cut -d'"' -f4)

case $tc_ver in
	2.5|2.5.*)
		tc_ver_label=2.5
		tc_bin=/usr/bin/hw_management_thermal_control_2_5.py
		;;
	*)
		tc_ver_label=2.0
		tc_bin=/usr/bin/hw_management_thermal_control.py
		;;
esac

desc="Thermal control service (ver $tc_ver_label) of Nvidia systems"
unit_path=$(systemctl show -p FragmentPath hw-management-tc.service 2>/dev/null | cut -d= -f2-)
if [ -n "$unit_path" ] && [ -f "$unit_path" ] &&
   ! grep -qxF "Description=$desc" "$unit_path"; then
	sed -i "s/^Description=.*/Description=$desc/" "$unit_path"
	systemctl daemon-reload
fi

if [ "$describe_only" -eq 1 ]; then
	exit 0
fi

logger -t hw-management-tc "Starting $tc_bin"
exec "$tc_bin"
