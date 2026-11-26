#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# Unit tests for HW_Mgmt_Logger.sanitize_msg(): sensitive values (passwords,
# logins, tokens, ids, hashes, keys) must be masked before a message reaches
# the log file or syslog, while ordinary hardware messages stay unchanged.

import logging
import re
import sys
import time
from pathlib import Path

import pytest

TESTS_DIR = Path(__file__).parent
PROJECT_ROOT = TESTS_DIR.parent.parent
HW_MGMT_BIN = PROJECT_ROOT / "usr" / "usr" / "bin"
if str(HW_MGMT_BIN) not in sys.path:
    sys.path.insert(0, str(HW_MGMT_BIN))

from hw_management_lib import HW_Mgmt_Logger  # noqa: E402

pytestmark = pytest.mark.offline

R = HW_Mgmt_Logger.LOG_REDACTED


@pytest.mark.parametrize("msg, expected", [
    ("login=bob password=Secret123 ok", f"login={R} password={R} ok"),
    ("user: root, passwd: 'my secret pass'", f"user: {R}, passwd: {R}"),
    ("PASSWORD=abc", f"PASSWORD={R}"),
    ("db_password=abc token_id=77 api_key=AKIA123", f"db_password={R} token_id={R} api_key={R}"),
    ("user_id=42 session_id=abcd1234, uid=0", f"user_id={R} session_id={R}, uid={R}"),
    ("serial_number=MT2145X01234 hash=deadbeef", f"serial_number={R} hash={R}"),
    ("curl --password hunter2 --user admin http://host", f"curl --password {R} --user {R} http://host"),
    ("Authorization: Bearer eyJhbGciOi.abc.def", f"Authorization: {R}"),
    ("Header Bearer abcdefghijkl1234", f"Header Bearer {R}"),
    ("fetch https://bob:pw123@example.com/path", f"fetch https://{R}@example.com/path"),
    ("sha256 " + "ab" * 32 + " done", f"sha256 {R} done"),
    ("-----BEGIN RSA PRIVATE KEY-----\nMIIEvQ\n-----END RSA PRIVATE KEY-----\nafter",
     f"{R}\nafter"),
])
def test_sensitive_data_masked(msg, expected):
    assert HW_Mgmt_Logger.sanitize_msg(msg) == expected


@pytest.mark.parametrize("msg, expected", [
    # option value in quotes with spaces
    ('--password "two words" next', f'--password {R} next'),
    ("--password 'two words' next", f"--password {R} next"),
    ('--user "john doe" --password "a b c"', f'--user {R} --password {R}'),
    # escaped quote inside quoted value
    (r'password="abc\"Secret123" next', f'password={R} next'),
    (r"password='abc\'Secret123' next", f"password={R} next"),
    (r'--password "abc\"Secret 123" next', f'--password {R} next'),
    (r'{"password": "abc\"Secret123", "ok": 1}', f'{{"password": {R}, "ok": 1}}'),
    # escaped backslash right before the closing quote
    (r'password="abc\\" next', f'password={R} next'),
    # quoted value with spaces in key=value form
    ('token="two words" next', f'token={R} next'),
    # unterminated quote: mask to the end of the message
    ('password="abc Secret123', f'password={R}'),
    ('--password "abc Secret123', f'--password {R}'),
    ('password="abc\\', f'password={R}'),
])
def test_quoted_values_fully_masked(msg, expected):
    out = HW_Mgmt_Logger.sanitize_msg(msg)
    assert out == expected
    assert "Secret123" not in out
    assert "words" not in out


@pytest.mark.parametrize("msg", [
    "fan1 speed: 5000 rpm, psu1 status: ok, inside=3, passed 3 tests",
    "Starting hw-management-sync",
    "Error: authority=x",
    "Total CPU time: utime=1.20s, stime=0.30s",
    "  TID 12      | utime=0.100s | stime=0.200s",
    "short hex deadbeef is kept",
    "",
])
def test_ordinary_messages_unchanged(msg):
    assert HW_Mgmt_Logger.sanitize_msg(msg) == msg


@pytest.mark.parametrize("msg", [
    "a_" * 24 + "!",                       # was exponential with a repeated \w+ prefix
    "a_" * 10000 + "!",
    "a." * 10000 + "!",
    "a-" * 10000 + "!",
    "a+" * 10000,                           # scheme-like text without "://"
    "password_" * 2000,                     # many key starts without "=" or ":"
    "password=" * 2000,
    "x" * 20000,
    "a" * 20000 + "g",                      # long hex-like run
    "--password " * 2000,
    'password="' + "\\" * 20000,            # unterminated quote with backslashes
    '"' * 20000,
    "password" + " " * 20000 + "x",
    "Bearer " + "a" * 20000,
    "-----BEGIN PRIVATE KEY-----" * 700,
    "/var/log/" + "dir_name/" * 2000,       # path-like text
])
def test_long_nonmatching_input_is_fast(msg):
    start = time.monotonic()
    HW_Mgmt_Logger.sanitize_msg(msg)
    assert time.monotonic() - start < 2.0


@pytest.mark.parametrize("msg, expected", [
    ("db_password=abc", f"db_password={R}"),
    ("my.app-token_id: 7", f"my.app-token_id: {R}"),
    ("a_b_c_d_password=abc", f"a_b_c_d_password={R}"),
    ("xpassword=abc", "xpassword=abc"),     # sensitive word glued to letters is not a key
    ("passed=3", "passed=3"),
])
def test_key_prefix_and_suffix_matching(msg, expected):
    assert HW_Mgmt_Logger.sanitize_msg(msg) == expected


def test_none_passthrough():
    assert HW_Mgmt_Logger.sanitize_msg(None) is None


def test_logger_masks_file_output(tmp_path):
    log_file = tmp_path / "test.log"
    logger = HW_Mgmt_Logger("test", str(log_file), HW_Mgmt_Logger.DEBUG, None)
    try:
        logger.info("login=bob password=Secret123 ok")
        logger.error(None)
        for handler in logger.logger.handlers:
            handler.flush()
    finally:
        logger.stop()
    content = log_file.read_text()
    assert f"login={R} password={R} ok" in content
    assert "Secret123" not in content
    assert "bob" not in content


def test_logger_masks_quoted_values_in_file(tmp_path):
    log_file = tmp_path / "test.log"
    logger = HW_Mgmt_Logger("test", str(log_file), HW_Mgmt_Logger.DEBUG, None)
    try:
        logger.info('run --password "two words" x')
        logger.info(r'password="abc\"Secret123" y')
        for handler in logger.logger.handlers:
            handler.flush()
    finally:
        logger.stop()
    content = log_file.read_text()
    assert "words" not in content
    assert "Secret123" not in content
    assert f"run --password {R} x" in content
    assert f"password={R} y" in content


class _ListHandler(logging.Handler):
    def __init__(self):
        super().__init__()
        self.messages = []

    def emit(self, record):
        self.messages.append(record.getMessage())


def test_repeat_collapse_uses_masked_text():
    logger = HW_Mgmt_Logger("test", None, HW_Mgmt_Logger.DEBUG, None)
    handler = _ListHandler()
    logger.logger.addHandler(handler)
    try:
        logger.info("token=abc123 failed", id="tok", log_repeat=1)
        logger.info("token=abc123 failed", id="tok", log_repeat=1)
        logger.info("", id="tok", log_repeat=1)  # finalize message comes from the hash
    finally:
        logger.stop()
    assert len(handler.messages) == 2
    assert all("abc123" not in m for m in handler.messages)
    assert re.search(rf"token={re.escape(R)} failed \(repeat=2", handler.messages[1])
