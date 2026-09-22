# Kernel patch review standard

These rules apply to `recipes-kernel/linux/**` only. Everything here was derived by
measuring the 912 `.patch` files already in this tree, so the conformance rates below
are facts about this repository, not aspirations.

## What this tree is

`recipes-kernel/linux/linux-<ver>/` holds the kernel patch queue for a given kernel
version. `deploy_kernel_patches.py` reads `Patch_Status_Table.txt` (host) or
`Patch_BMC_Status_Table.txt` (BMC), and applies only the patches that have a row there.
**A patch file with no table row is silently skipped and never reaches a build.** That
failure is invisible — no error, no warning, just a driver that quietly is not there.
Treat a missing registration as the most serious finding you can make in this directory.

## Canonical patch anatomy

```
From <40-hex-sha> Mon Sep 17 00:00:00 2001      <- 900/912 conform
From: Display Name <local@domain>               <- 909/909 parse as Name <email>
Date: Tue, 15 Jul 2025 12:16:27 -0700           <- 908/908 are RFC2822
Subject: [PATCH] subsys: short imperative summary
  (optional RFC822 continuation lines, indented)
(optional MIME-Version / Content-Type / Content-Transfer-Encoding)
(optional X-NVConfidentiality: public)
                                                <- exactly one blank line
Body prose explaining WHY.
                                                <- blank line
Signed-off-by: Name <email>                     <- trailers, always above the ---
Reviewed-by: ...
(cherry picked from commit <40-hex-sha>)
---                                             <- exactly three hyphens
 diffstat
diff --git a/... b/...                          <- or GNU `diff -Nur`, or bare unified
```

Field order is **From → Date → Subject**, without exception: all 908 files carrying all three agree and no
permutation exists, so a
deviation is a hand-edited header, not a style choice. The fix is always to regenerate
with `git format-patch` rather than to patch the header by hand.

Three diff dialects are legitimate here — `git format-patch` output (906 files), GNU
`diff -Nur` (5), and a bare unified diff with timestamps (1). Do not object to a patch
for using the second or third; they apply fine.

## Description quality — the rule that actually matters

Judge the body against one question: **can a reviewer who did not write this patch tell
what problem it solves?**

Reject: empty bodies, bodies under ~8 words, bodies that only rephrase the Subject,
boilerplate ("fix bug", "update driver", "cosmetic changes"), and unresolved
TMP/TODO/WIP markers.

Do not confuse brevity with inadequacy. A one-line fix with a complete two-sentence
explanation is good. A twenty-line body that never states the symptom is not.

### The cherry-pick exemption — apply this before anything else

Roughly half this tree is verbatim upstream commits. The body belongs to the upstream
author and **rewriting it is wrong** — it would destroy the correspondence with the
upstream commit and make future rebases harder to verify.

If the patch carries any of `(cherry picked from commit <sha>)`, `commit <sha> upstream`,
`upstream commit <sha>`, `Upstream-Status: Backport [<sha>]`, or a `Link:` to
lore.kernel.org — do not comment on its prose at all. Check only that the provenance
marker and the table's commit id are present and well formed.

### The stricter downstream rule

Patches whose table status starts with `Downstream` are the ones this team owns forever.
Nobody upstream will ever document them. Their commit message must carry:

- the observed failure or missing capability (the symptom, concretely)
- the hardware it affects — a named system, board, ASIC or SKU (SN4800, SPC6, AST2700,
  QM3200, DPU...)
- why it is carried downstream rather than sent upstream

Missing hardware context is the most frequent and most expensive gap in this tree. Raise
it as a specific question about the missing detail, not as a generic "add more detail".

## Rebases and refreshes

A *modified* patch is riskier than a new one. When a kernel minor bump drops hunks that
have landed in the new base, the diff looks identical to someone deleting a fix on
purpose. Require the PR description to itemise, per patch, what was dropped, what was
kept, and what was reworked — and to say explicitly when a hunk disappeared because the
base now carries it.

Commit `9054e572` is the standard to hold contributors to: it names each rebased patch,
states which hunks the new base absorbed, and calls out the one real behavioural change.

## Status table grammar

Fixed-width, pipe-delimited, parsed positionally by `deploy_kernel_patches.py`:

```
|<filename>  |<12-hex upstream id>|<status;modifiers>|<subversion>|<notes>|
```

Base statuses: `Feature upstream`, `Feature accepted`, `Feature pending`,
`Bugfix upstream`, `Bugfix accepted`, `Bugfix pending`, `Downstream`,
`Downstream accepted`, `Rejected`.

Modifiers are semicolon-separated; the only legal keys are `os[...]`, `take[...]`,
`skip[...]`, over the OS values `sonic`, `opt`, `cumulus`, `nvos`, `dvs`, `ALL`.

The parser matches these **literally**. `take[ sonic ]`, `skip[SONIC]` or `takes[sonic]`
are not rejected — they are silently ignored, and the patch then ships to an OS that was
meant to exclude it. Treat any deviation inside the brackets as a high-severity finding.

`Feature upstream` and `Bugfix upstream` rows should carry a commit id (97% do).
`Downstream` rows should not claim one.

## Calibration — what not to flag

This tree has real, accepted history that a naive reading would object to. Do not raise:

- a non-NVIDIA author; most of these patches are upstream work and the original
  attribution is required
- the `NNNN-N-` sub-numbering (`0064-1-`, `0064-2-`) used for a related series
- duplicate 4-digit prefixes across different `linux-X.Y/` directories
- patches under `sonic/`, `opt/`, `cumulus/`, `nvos/`, `dvs/` being near-copies of a
  root-level patch — that is how per-OS variants are expressed
- `patchwork/*.patch.txt` files, which are staging notes, not deployable patches
- the very large patches (`0001-mctp-...` is 451 KB); size is not a defect here

When in doubt on prose, comment rather than object. When in doubt on a missing table row
or a malformed `take[]`/`skip[]` modifier, object — those break builds silently.
