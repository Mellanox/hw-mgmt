#!/usr/bin/env python3
"""Gate: every commit in a PR must reference a ticket and be signed off.

Accepted ticket tags (case-insensitive), number on the same or next line:
    Bug: 5319246 | Bug#: 5319246 | Ticket#: 123 | FR#: 42 | NVBug: 1 | Issue: 7
Required sign-off:
    Signed-off-by: Name <email>
Usage: check_commit_msg.py <base-sha> <head-sha>
"""
import re
import subprocess
import sys

TICKET_RE = re.compile(r"^[ \t]*(?:bug|nvbug|ticket|fr|issue)[ \t]*#?[ \t]*:?[ \t]*\n?[ \t]*#?\d+",
                       re.IGNORECASE | re.MULTILINE)
SIGNOFF_RE = re.compile(r"^Signed-off-by:[ \t]+\S.*<[^<>\s]+@[^<>\s]+>[ \t]*$", re.MULTILINE)


def main():
    base, head = sys.argv[1:3]
    shas = subprocess.check_output(
        ["git", "rev-list", "--no-merges", f"{base}..{head}"], text=True).split()
    failed = False
    for sha in shas:
        msg = subprocess.check_output(["git", "log", "-1", "--format=%B", sha], text=True)
        subject = msg.splitlines()[0] if msg.strip() else ""
        problems = []
        if not TICKET_RE.search(msg):
            problems.append("missing ticket reference (e.g. 'Bug: 1234567', 'Ticket#: 123', 'FR#: 42')")
        if not SIGNOFF_RE.search(msg):
            problems.append("missing 'Signed-off-by: Name <email>' (use git commit -s)")
        if problems:
            failed = True
            print(f"::error::{sha[:10]} {subject}: " + "; ".join(problems))
    if failed:
        sys.exit(1)
    print(f"Checked {len(shas)} commit(s): OK")


if __name__ == "__main__":
    main()
