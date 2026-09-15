#!/usr/bin/env python3
"""Validate metadata and descriptions in changed kernel patch files."""

import argparse
import dataclasses
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable, List, Optional, Sequence, Tuple


PATCH_ROOT = Path("recipes-kernel/linux")
MIN_BODY_CHARS = 100
MIN_SUBJECT_CHARS = 20
INTERNAL_REFERENCES = (
    "jirasw.nvidia.com",
    "nvbugs/",
    "nvbugs.nvidia.com",
)
TRAILER_RE = re.compile(
    r"^(?:Signed-off-by|Reviewed-by|Acked-by|Tested-by|Reported-by|"
    r"Suggested-by|Co-developed-by|Cc|Link|Closes|Fixes|BugLink|"
    r"Upstream-Status):\s*",
    re.IGNORECASE,
)
MBOX_FROM_RE = re.compile(
    r"^From [0-9a-f]{40} Mon Sep 17 00:00:00 2001$", re.IGNORECASE
)
AUTHOR_RE = re.compile(r"^From:\s+.+\s+<[^<>@\s]+@[^<>\s]+>\s*$")
DATE_RE = re.compile(r"^Date:\s+\S.+$")
SIGNOFF_RE = re.compile(
    r"^Signed-off-by:\s+.+\s+<[^<>@\s]+@[^<>\s]+>\s*$", re.IGNORECASE
)
STATUS_RE = re.compile(r"^Upstream-Status:\s+\S.+$", re.IGNORECASE)
PATCH_PREFIX_RE = re.compile(r"^\s*\[(?:PATCH|RFC)(?:[^\]]*)\]\s*", re.IGNORECASE)
REVERT_RE = re.compile(r"\bThis reverts commit [0-9a-f]{7,40}\b", re.IGNORECASE)
BACKPORT_RE = re.compile(
    r"\[\s*Upstream commit [0-9a-f]{12,40}\s*\]", re.IGNORECASE
)


@dataclasses.dataclass(frozen=True)
class ParsedPatch:
    text: str
    lines: Tuple[str, ...]
    subject: str
    body: str
    body_lines: Tuple[str, ...]
    functional_payload: Tuple[str, ...]
    has_mbox_from: bool
    has_author: bool
    has_date: bool
    has_signoff: bool
    has_upstream_status: bool
    has_separator: bool
    has_diff: bool


@dataclasses.dataclass(frozen=True)
class Finding:
    path: str
    message: str


def _subject(lines: Sequence[str]) -> Tuple[str, Optional[int], int]:
    for index, line in enumerate(lines):
        if not line.startswith("Subject:"):
            continue
        parts = [line.partition(":")[2].strip()]
        end = index + 1
        while end < len(lines) and lines[end].startswith((" ", "\t")):
            parts.append(lines[end].strip())
            end += 1
        return " ".join(part for part in parts if part), index, end
    return "", None, 0


def _body(
    lines: Sequence[str], subject_index: Optional[int], subject_end: int
) -> Tuple[Tuple[str, ...], bool]:
    if subject_index is None:
        return (), False

    separator_index = None
    for index in range(subject_end, len(lines)):
        if lines[index] == "---":
            separator_index = index
            break
        if lines[index].startswith("diff --git "):
            break

    body_end = separator_index if separator_index is not None else len(lines)
    prose = []
    for line in lines[subject_end:body_end]:
        stripped = line.strip()
        if not stripped or TRAILER_RE.match(stripped):
            continue
        prose.append(stripped)
    return tuple(prose), separator_index is not None


def _functional_payload(lines: Sequence[str]) -> Tuple[str, ...]:
    payload: List[str] = []
    in_diff = False
    in_hunk = False

    for line in lines:
        if line.startswith("diff --git "):
            in_diff = True
            in_hunk = False
            payload.append(line)
            continue
        if line.startswith("diff -Nur "):
            fields = line.split()
            if len(fields) >= 4:
                in_diff = True
                in_hunk = False
                payload.append("diff --git {} {}".format(fields[-2], fields[-1]))
            continue
        if not in_diff:
            continue
        if line.startswith(("new file mode ", "deleted file mode ", "rename from ",
                            "rename to ", "Binary files ")):
            payload.append(line)
            continue
        if line.startswith("@@"):
            in_hunk = True
            continue
        if in_hunk and line.startswith(("+", "-")):
            payload.append(line)

    return tuple(payload)


def parse_patch(text: str) -> ParsedPatch:
    lines = tuple(text.splitlines())
    subject, subject_index, subject_end = _subject(lines)
    body_lines, has_separator = _body(lines, subject_index, subject_end)
    message_end = len(lines)
    for index in range(subject_end, len(lines)):
        if lines[index] == "---" or lines[index].startswith("diff --git "):
            message_end = index
            break
    message_lines = lines[subject_end:message_end]

    return ParsedPatch(
        text=text,
        lines=lines,
        subject=subject,
        body="\n".join(body_lines),
        body_lines=body_lines,
        functional_payload=_functional_payload(lines),
        has_mbox_from=any(MBOX_FROM_RE.match(line) for line in lines),
        has_author=any(AUTHOR_RE.match(line) for line in lines),
        has_date=any(DATE_RE.match(line) for line in lines),
        has_signoff=any(SIGNOFF_RE.match(line) for line in message_lines),
        has_upstream_status=any(STATUS_RE.match(line) for line in message_lines),
        has_separator=has_separator,
        has_diff=any(line.startswith("diff --git ") for line in lines),
    )


def _prose_chars(lines: Iterable[str]) -> int:
    return sum(len(re.sub(r"\s+", "", line)) for line in lines)


def validate_patch(
    path: str, current_text: str, base_text: Optional[str] = None
) -> List[Finding]:
    patch = parse_patch(current_text)
    findings: List[Finding] = []

    def add(message: str) -> None:
        findings.append(Finding(path, message))

    if not patch.has_mbox_from:
        add("missing canonical 'From <40-hex commit> Mon Sep 17 ...' mbox header")
    if not patch.has_author:
        add("missing attributable 'From: Name <email>' header")
    if not patch.has_date:
        add("missing Date header")
    if not patch.subject:
        add("missing Subject header")
    else:
        subject = PATCH_PREFIX_RE.sub("", patch.subject).strip()
        if len(subject) < MIN_SUBJECT_CHARS:
            add(
                "Subject is too short to identify the change "
                "(minimum {} characters excluding the PATCH prefix)".format(
                    MIN_SUBJECT_CHARS
                )
            )
    if not patch.has_signoff:
        add("missing 'Signed-off-by: Name <email>' trailer")
    if not patch.has_upstream_status:
        add("missing Upstream-Status trailer")
    if not patch.has_separator:
        add("missing '---' separator between commit message and diffstat")
    if not patch.has_diff:
        add("missing 'diff --git' payload")

    prose_chars = _prose_chars(patch.body_lines)
    is_revert = bool(REVERT_RE.search(patch.body))
    is_attributed_backport = bool(BACKPORT_RE.search(patch.body))
    minimum_body_chars = 60 if is_revert or is_attributed_backport else MIN_BODY_CHARS
    if prose_chars < minimum_body_chars:
        add(
            "commit-message body is too thin: {} non-whitespace prose characters; "
            "describe what changed, why it was needed, and its impact (minimum {})".format(
                prose_chars, minimum_body_chars
            )
        )

    internal_lines = [
        line
        for line in patch.body_lines
        if any(reference in line.lower() for reference in INTERNAL_REFERENCES)
    ]
    if internal_lines:
        public_lines = [line for line in patch.body_lines if line not in internal_lines]
        if _prose_chars(public_lines) < minimum_body_chars:
            add(
                "internal issue references may supplement, but cannot replace, "
                "a self-contained public explanation"
            )

    if base_text is not None:
        base = parse_patch(base_text)
        if (
            patch.functional_payload != base.functional_payload
            and patch.body.strip() == base.body.strip()
        ):
            add(
                "functional patch payload changed but its commit-message body did not; "
                "update the description to explain the new behavior"
            )

    return findings


def _git(*args: str) -> str:
    result = subprocess.run(
        ("git",) + args,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "git command failed")
    return result.stdout


def _changed_patches(base: str, head: str) -> List[Tuple[str, str, Optional[str]]]:
    output = _git(
        "diff",
        "--name-status",
        "--find-renames",
        "{}...{}".format(base, head),
        "--",
        str(PATCH_ROOT),
    )
    changed = []
    for line in output.splitlines():
        fields = line.split("\t")
        status = fields[0]
        if status.startswith("R") and len(fields) == 3:
            old_path, path = fields[1], fields[2]
        elif status[:1] in ("A", "M") and len(fields) == 2:
            old_path = None if status.startswith("A") else fields[1]
            path = fields[1]
        else:
            continue
        if path.endswith(".patch"):
            changed.append((status, path, old_path))
    return changed


def _ref_file(ref: str, path: Optional[str]) -> Optional[str]:
    if path is None:
        return None
    try:
        return _git("show", "{}:{}".format(ref, path))
    except RuntimeError:
        return None


def _all_patches() -> List[Tuple[str, str, Optional[str]]]:
    return [
        ("A", path.as_posix(), None)
        for path in sorted(PATCH_ROOT.rglob("*.patch"))
        if path.is_file()
    ]


def _emit(finding: Finding) -> None:
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print(
            "::error file={}::{}".format(
                finding.path,
                finding.message.replace("%", "%25").replace("\r", "%0D").replace(
                    "\n", "%0A"
                ),
            )
        )
    else:
        print("{}: {}".format(finding.path, finding.message))


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate metadata and descriptions in kernel patch files."
    )
    parser.add_argument("--base", help="base commit/ref for changed-file comparison")
    parser.add_argument("--head", default="HEAD", help="head commit/ref")
    parser.add_argument(
        "--all", action="store_true", help="audit every kernel patch in the worktree"
    )
    parser.add_argument(
        "--warn-only",
        action="store_true",
        help="report findings without returning a failing exit status",
    )
    args = parser.parse_args(argv)

    if args.all:
        candidates = _all_patches()
    elif args.base:
        candidates = _changed_patches(args.base, args.head)
    else:
        parser.error("provide --base for changed files or --all for a corpus audit")

    findings: List[Finding] = []
    for _status, path, old_path in candidates:
        if args.all:
            current = Path(path).read_text(encoding="utf-8", errors="replace")
            base_text = None
        else:
            current = _ref_file(args.head, path)
            if current is None:
                findings.append(Finding(path, "cannot read patch content from head ref"))
                continue
            base_text = _ref_file(args.base, old_path)
        findings.extend(validate_patch(path, current, base_text))

    for finding in findings:
        _emit(finding)

    print(
        "Checked {} patch file(s): {} finding(s).".format(
            len(candidates), len(findings)
        )
    )
    return 0 if not findings or args.warn_only else 1


if __name__ == "__main__":
    sys.exit(main())
