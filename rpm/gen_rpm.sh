#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2022-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause



# Find the list of files

# Find version
RPM_VERSION=`grep "hw-management" ../debian/changelog | cut -d "(" -f2 | cut -d ")" -f1`

# Build RPM
rpmbuild -ba --define="version ${RPM_VERSION}" hw-management.spec
