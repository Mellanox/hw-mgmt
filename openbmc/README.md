<!-- SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES -->

# `openbmc/` — OpenBMC payload root

Files consumed by the OpenBMC build. OpenBMC fetches this repository at a pinned tag and
installs from this tree, so hw-management content is not duplicated in the OpenBMC repository.

## Layout

Paths under `openbmc/` mirror the target root filesystem one-to-one:

| repo path | target path |
|---|---|
| `openbmc/usr/bin/` | `/usr/bin/` |
| `openbmc/usr/local/bin/` | `/usr/local/bin/` |

No name rewriting. A file lands at the path its position here implies. This differs from `bmc/`,
which is the SONiC BMC payload and prefixes every file with `hw-management-bmc-`.

## Relationship to the other payload roots

| root | consumer | packaging |
|---|---|---|
| `usr/` | host / CPU | `debian/rules`, `rpm/` |
| `bmc/` | SONiC BMC | `debian/rules` (`hw-management-bmc`) |
| `openbmc/` | OpenBMC | OpenBMC's own bitbake recipe; no Debian package |

`openbmc/` is not referenced by `debian/rules` or by the `git archive` invocations in
`.github/workflows/build-release.yml`, so it does not affect the host or SONiC BMC artifacts.

## Contract with the OpenBMC recipe

The OpenBMC recipe installs from explicit paths, not globs. Adding a file here does not ship it;
the recipe must also install it. Removing or renaming a file here breaks any OpenBMC build that
pins a tag containing the change, so treat this tree as a published interface.

The OpenBMC side pins a tag of this repository. Anything added here is only reachable to OpenBMC
once a tag containing it exists.

## Scope

Board and device logic that is independent of the operating system. Enumeration data that depends
on the OpenBMC kernel (bus numbers, device addresses), OpenBMC service configuration
(entity-manager, bmcweb, pldm), udev ordering, device trees and kernel configuration stay in the
OpenBMC repository.
