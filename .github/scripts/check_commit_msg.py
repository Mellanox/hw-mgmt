#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
################################################################################
"""Gate: every commit in a PR must reference a ticket and be signed off.

Accepted ticket tags (case-insensitive), number on the same or next line:
    Bug: 5319246 | Bug#: 5319246 | Ticket#: 123 | FR#: 42 | NVBug: 1 | Issue: 7
    Bug: https://nvbugspro.nvidia.com/bug/5778183
Or, when there is genuinely no ticket, an explicit opt-out with a reason:
    No-Ticket: CI-only change, no bug filed
Required sign-off:
    Signed-off-by: Name <email>
Usage: check_commit_msg.py <base-sha> <head-sha>
"""
import re
import subprocess
import sys

# <label><separator><value>. The separator is mandatory so "Bug123" is rejected: ':', '#', '#:',
# whitespace, or a qualifier (SW/HW/FW/BMC) then ':' as in "Bug SW: 5245926". The value is a number,
# "#number", or a URL whose last path/query element is a number; it may be on the next line.
TICKET_RE = re.compile(
    r"^[ \t]*(?:bug|nvbug|ticket|fr|issue)s?"
    r"(?:[ \t]*#[ \t]*:?|[ \t]*:|[ \t]+(?:sw|hw|fw|bmc)[ \t]*:|[ \t]+)"
    r"[ \t]*\n?[ \t]*"
    r"(?:#?\d+\b|https?://\S*[/=-]\d+/?[ \t]*$)",
    re.IGNORECASE | re.MULTILINE)
NO_TICKET_RE = re.compile(r"^No-Ticket:[ \t]*\S.*$", re.IGNORECASE | re.MULTILINE)
SIGNOFF_RE = re.compile(r"^Signed-off-by:[ \t]+\S.*<[^<>\s]+@[^<>\s]+>[ \t]*$", re.MULTILINE)

HELP = """Every non-merge commit in the PR needs:
  1. A ticket line: Bug|NVBug|Ticket|FR|Issue [#]: <number>
     (number or bug URL, may be on the next line), e.g. "Bug: 5319246".
     If there is genuinely no ticket: "No-Ticket: <reason>".
  2. A sign-off line: Signed-off-by: Name <email>
How to fix:
  - last commit:  git commit --amend -s   (edit the message to add the ticket line)
  - all commits:  git rebase -i <base-branch> --exec 'git commit --amend --no-edit -s'
                  (and edit the messages to add ticket lines)
  Then force-push the branch."""


def main():
    base, head = sys.argv[1:3]
    shas = subprocess.check_output(
        ["git", "rev-list", "--no-merges", f"{base}..{head}"], text=True).split()
    failed = False
    for sha in shas:
        msg = subprocess.check_output(["git", "log", "-1", "--format=%B", sha], text=True)
        subject = msg.splitlines()[0] if msg.strip() else ""
        problems = []
        if not (TICKET_RE.search(msg) or NO_TICKET_RE.search(msg)):
            problems.append("missing ticket reference (e.g. 'Bug: 1234567', 'Ticket#: 123', 'FR#: 42'), "
                            "or 'No-Ticket: <reason>' if there is none")
        if not SIGNOFF_RE.search(msg):
            problems.append("missing 'Signed-off-by: Name <email>' (use git commit -s)")
        if problems:
            failed = True
            print(f"::error::{sha[:10]} {subject}: " + "; ".join(problems))
    if failed:
        print("\n" + HELP)
        print("::notice title=Commit message rules::" + HELP.replace("\n", "%0A"))
        sys.exit(1)
    print(f"Checked {len(shas)} commit(s): OK")


if __name__ == "__main__":
    main()
