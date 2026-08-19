#!/usr/bin/env python3
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Ensure usr/usr/bin is on sys.path before offline test modules import
# hw_management_redfish_client (beautify requires top-level imports).
########################################################################

import os
import sys

sys.path.insert(
    0,
    os.path.join(os.path.dirname(__file__), '..', '..', 'usr', 'usr', 'bin')
)
