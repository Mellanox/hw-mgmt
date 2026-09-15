#!/usr/bin/env python3

"""Tests for the kernel patch metadata and description checker."""

import importlib.util
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
CHECKER_PATH = ROOT / "recipes-kernel" / "linux" / "check_patch_headers.py"
SPEC = importlib.util.spec_from_file_location("check_patch_headers", CHECKER_PATH)
CHECKER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHECKER
SPEC.loader.exec_module(CHECKER)


GOOD_BODY = (
    "The controller previously returned a shifted field value because the "
    "descriptor used the mask's most significant bit as its offset. Set the "
    "offset to the field's one-based least significant bit so userspace reads "
    "the encoded hardware value correctly."
)


def make_patch(
    body=GOOD_BODY,
    subject="platform: correct multi-bit register field decoding",
    added_line="new_value();",
):
    return f"""\
From 0123456789abcdef0123456789abcdef01234567 Mon Sep 17 00:00:00 2001
From: Patch Author <author@example.com>
Date: Tue, 15 Sep 2026 12:00:00 +0300
Subject: [PATCH] {subject}

{body}

Upstream-Status: Pending
Signed-off-by: Patch Author <author@example.com>
---
 drivers/example.c | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)

diff --git a/drivers/example.c b/drivers/example.c
index 1111111..2222222 100644
--- a/drivers/example.c
+++ b/drivers/example.c
@@ -1 +1 @@
-old_value();
+{added_line}
--
2.34.1
"""


def messages(text, base=None):
    return [
        finding.message
        for finding in CHECKER.validate_patch("example.patch", text, base)
    ]


def test_accepts_canonical_patch():
    assert messages(make_patch()) == []


def test_accepts_multiline_subject():
    patch = make_patch().replace(
        "Subject: [PATCH] platform: correct multi-bit register field decoding",
        "Subject: [PATCH] platform: correct multi-bit register field\n decoding",
    )
    assert messages(patch) == []


@pytest.mark.parametrize(
    ("fragment", "expected"),
    [
        (
            "From 0123456789abcdef0123456789abcdef01234567 "
            "Mon Sep 17 00:00:00 2001\n",
            "missing canonical",
        ),
        ("From: Patch Author <author@example.com>\n", "missing attributable"),
        ("Date: Tue, 15 Sep 2026 12:00:00 +0300\n", "missing Date"),
        (
            "Signed-off-by: Patch Author <author@example.com>\n",
            "missing 'Signed-off-by",
        ),
        ("Upstream-Status: Pending\n", "missing Upstream-Status"),
    ],
)
def test_rejects_missing_required_metadata(fragment, expected):
    assert any(expected in message for message in messages(make_patch().replace(fragment, "")))


def test_rejects_missing_subject():
    patch = make_patch().replace(
        "Subject: [PATCH] platform: correct multi-bit register field decoding\n", ""
    )
    assert "missing Subject header" in messages(patch)


def test_rejects_status_outside_commit_message():
    patch = make_patch().replace("Upstream-Status: Pending\n", "")
    patch = "Upstream-Status: Pending\n\n" + patch
    assert "missing Upstream-Status trailer" in messages(patch)


def test_rejects_short_subject():
    assert any(
        "Subject is too short" in message
        for message in messages(make_patch(subject="fix field"))
    )


def test_rejects_empty_or_generic_body():
    assert any(
        "body is too thin" in message for message in messages(make_patch(body="Fix it."))
    )


def test_allows_short_standard_revert_body():
    body = "This reverts commit abcdef0123456789 because it breaks device probe."
    assert messages(make_patch(body=body, subject="Revert broken controller initialization")) == []


def test_allows_attributed_stable_backport_body():
    body = (
        "[ Upstream commit abcdef0123456789 ]\n\n"
        "Backport the controller reset correction to this stable kernel series."
    )
    assert messages(make_patch(body=body)) == []


def test_rejects_internal_ticket_as_only_rationale():
    body = (
        "Fixes JIRA https://jirasw.nvidia.com/browse/HWMGMT-12345. "
        "See the internal report for reproduction details and expected behavior."
    )
    result = messages(make_patch(body=body))
    assert any("internal issue references" in message for message in result)


def test_allows_internal_ticket_after_public_explanation():
    body = (
        GOOD_BODY
        + "\n\nTracking: https://jirasw.nvidia.com/browse/HWMGMT-12345"
    )
    assert messages(make_patch(body=body)) == []


def test_rejects_description_stripping():
    result = messages(make_patch(body="Increase the supported limit."), make_patch())
    assert any("body is too thin" in message for message in result)


def test_allows_description_only_improvement():
    updated = make_patch(body=GOOD_BODY + " This also documents the observed failure.")
    assert messages(updated, make_patch()) == []


def test_treats_legacy_diff_framing_as_the_same_payload():
    legacy = make_patch().replace(
        "diff --git a/drivers/example.c b/drivers/example.c",
        "diff -Nur a/drivers/example.c b/drivers/example.c",
    )
    assert messages(make_patch(), legacy) == []


def test_rejects_functional_change_without_description_update():
    updated = make_patch(added_line="different_new_value();")
    result = messages(updated, make_patch())
    assert any("functional patch payload changed" in message for message in result)


def test_allows_functional_change_with_description_update():
    updated = make_patch(
        body=GOOD_BODY + " The revised call also restores state after reset.",
        added_line="different_new_value();",
    )
    assert messages(updated, make_patch()) == []


def test_rejects_missing_patch_boundaries():
    patch = make_patch().replace("---\n drivers/example.c", " drivers/example.c")
    patch = patch.replace("diff --git ", "diff ")
    result = messages(patch)
    assert "missing '---' separator between commit message and diffstat" in result
    assert "missing 'diff --git' payload" in result
