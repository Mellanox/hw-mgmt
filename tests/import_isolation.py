# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause

"""Import-stub helper shared by pytest and standalone unittest scripts.

Kept out of conftest.py so a script started from a subdirectory can import
it without loading pytest.
"""
import contextlib
import sys


class _SysModuleAbsent:
    """Marker: this name was not in sys.modules before a temporary swap."""


@contextlib.contextmanager
def temporary_sys_modules(replacements):
    """Install import stubs for one load, then put sys.modules back.

    Leaving a MagicMock in sys.modules makes later test files import the
    stub instead of the real module.
    """
    saved = {}
    for name, value in replacements.items():
        saved[name] = sys.modules[name] if name in sys.modules else _SysModuleAbsent
        sys.modules[name] = value
    try:
        yield
    finally:
        for name, old in saved.items():
            if old is _SysModuleAbsent:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = old
