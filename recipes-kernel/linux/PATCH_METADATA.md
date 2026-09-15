# Kernel patch metadata

Every new or modified patch under `recipes-kernel/linux/` must be a
`git format-patch`-style email with attributable metadata and a
self-contained description.

## Required layout

```text
From <40-character commit ID> Mon Sep 17 00:00:00 2001
From: Author Name <author@example.com>
Date: Tue, 15 Sep 2026 12:00:00 +0300
Subject: [PATCH] subsystem: concise change summary

Describe the problem and the behavior before this change. State what the
patch changes and why that resolves the problem. Include a concrete hardware,
kernel, or userspace impact when one is known.

Upstream-Status: Pending
Signed-off-by: Author Name <author@example.com>
---
 <git format-patch diffstat>

diff --git ...
```

Generate the patch with `git format-patch`; do not construct its author
headers manually. Add `Upstream-Status` to the commit message before
generation, or insert it immediately before the `Signed-off-by` trailer.

The prose body must contain at least 100 non-whitespace characters. This is
only a floor: reviewers should be able to understand what changed, why it was
needed, and its effect without opening an internal ticket.

Private Jira, NVBug, or other internal references may be included for
traceability, but they cannot be the only explanation:

```text
The PSU count field used the mask's highest bit as its shift, so a two-PSU
system reported 2147483648 instead of 2. Use the field's one-based least
significant bit, as required by mlxreg-io.

Tracking: <internal issue URL>
```

When changing the functional diff inside an existing patch, update its commit
message in the same change. The CI checker compares the embedded diff with the
base branch and rejects functional changes whose description is unchanged.

## Local checks

After committing your changes:

```bash
python3 recipes-kernel/linux/check_patch_headers.py \
    --base origin/master --head HEAD
```

To inspect existing debt without failing the command:

```bash
python3 recipes-kernel/linux/check_patch_headers.py --all --warn-only
```

Pull requests run the focused checker automatically. Legacy patches that are
not added or modified by the pull request do not affect its result.
