#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Download a Linux 6.x release, apply hw-mgmt patches selected by
# recipes-kernel/linux/Patch_Status_Table.txt, and build Debian packages.
#
# Patch selection follows the Kernel-<major.minor> section of the status
# table. --os-type picks the NOS (nvos, opt, cumulus, sonic, dvs). The
# deploy tool reads markers such as os[nvos] and skip[sonic] and, when
# needed, takes the patch from recipes-kernel/linux/linux-<major.minor>/<nos>/.
#

set -euo pipefail

MAKE_ARCH="x86_64"
DEPLOY_ARCH="amd64"
KBUILD_DEBARCH="amd64"
CROSS_COMPILE=""
OS_TYPE="opt"
OS_TYPE_SET=0
ARCH_SET=""
CROSS_COMPILE_SET=0
CONFIG_FILE=""
PATCH_TABLE=""
BMC_PATCH_TABLE=""
THIRD_PARTY_DIR=""
DEPLOY_ARCH_SET=""
THIRD_PARTY_PATCHES=()
THIRD_PARTY_STRIPS=()
TARBALL=""
JOBS=""
FORCE=0
SKIP_BUILD=0
NO_RETRY=0
DRY_RUN=0
DEBUG=0

info() {
    printf '==> %s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage:
  ${0##*/} [options] <build_path> <hw_mgmt_path> <kernel_version>

Download a Linux 6.x tarball, apply the hw-mgmt patches listed for that
version in recipes-kernel/linux/Patch_Status_Table.txt, and build Debian
packages with "make deb-pkg".

The status table decides which patches apply. --os-type selects the NOS.
Patches marked for another NOS are skipped. A patch that the table ties to
one NOS is taken from recipes-kernel/linux/linux-<major.minor>/<nos>/ when
that directory is the one the deploy tool selects.

Options may be placed before or after the three arguments.

Arguments:
  build_path       Work directory (created if missing). Receives the tarball,
                   linux-<version>/, patches/, the build log, and the .deb files.
  hw_mgmt_path     hw-mgmt checkout that contains recipes-kernel/linux/.
  kernel_version   Upstream release, three numeric components, for example
                   6.12.94.

Options:
  -h, --help
  --os-type TYPE, --os_type=TYPE
                   NOS filter. One of: nvos, opt, cumulus, sonic, dvs, none.
                   Default: opt.
                   "none" does not select a NOS (deploy tool default).
  --arch ARCH      x86_64 (default) or arm64.
                   x86_64 uses kconfig section amd64 and KBUILD_DEBARCH=amd64.
                   The compiler is the native gcc unless --cross-compile is set.
                   arm64 uses kconfig section arm64, CROSS_COMPILE
                   aarch64-linux-gnu- unless --cross-compile is set, and
                   KBUILD_DEBARCH=arm64.
                   kernel_build_6_x_arm.sh is the same script with --arch arm64.
  --deploy-arch ARCH
                   Kconfig section written into .config: amd64, arm64, or aspeed.
                   Default follows --arch. kernel_build_6_x_sonic_bmc.sh uses
                   arm64 tools with the aspeed section.
  --cross-compile PREFIX
                   Toolchain prefix, for example aarch64-linux-gnu-.
  --config FILE    Starting .config, copied in before hw-mgmt kconfig flags
                   are merged. If omitted and this file exists, it is used:
                   <parent of build_path>/.config_<major.minor>
  --patch-table FILE
                   Status table. Default: Patch_Status_Table.txt under
                   recipes-kernel/linux/. A basename is looked up in that
                   directory.
  --third-party-patches DIR
                   After the status-table patches, import every *.patch in
                   this directory, one by one, in version-sort order. No
                   status-table filtering.
  --bmc-patch-table FILE
                   After the third-party patches, apply this table. Requires
                   --third-party-patches. kernel_build_6_x_sonic_bmc.sh passes
                   Patch_BMC_Status_Table.txt.
  --tarball FILE   Use this source archive instead of downloading it.
  --jobs N         Parallel jobs for the first build. Default: 3/4 of nproc,
                   at least 1.
  --force          Delete an existing linux-<version> tree and patches/
                   under build_path before starting. The tarball is kept.
  --skip-build     Import patches, then stop before olddefconfig and deb-pkg.
  --no-retry       Do not start a second build after a failure.
  --dry-run        Check arguments, the patch table, and host tools, then exit.
  --debug          Trace shell commands (set -x).

On the first build failure the log is kept and, unless --no-retry is set,
the build is repeated with -j2 and V=1 so the compiler error is readable.

Examples:
  mkdir -p /tmp/kernel-build
  ${0##*/} /tmp/kernel-build /path/to/hw-mgmt 6.12.94 --os_type=nvos

  kernel_build_6_x_arm.sh /tmp/kernel-build /path/to/hw-mgmt 6.12.94 --os_type=nvos

  kernel_build_6_x_sonic_bmc.sh /tmp/kernel-build /path/to/hw-mgmt 6.12.94 \
      --third-party-patches /path/to/sonic-patches

Tools:
  Checked before the kernel is downloaded.
  Always: tar, xz, git, stg (stgit), python3, make, and wget or curl.
  To build .deb packages: the Build-Depends used by Linux 6.12 "make deb-pkg"
  (debhelper, bc, bison, cpio, flex, kmod, rsync, libelf-dev, libssl-dev,
  and the gcc package for the package architecture).
  An arm64 build needs the host libssl-dev and libssl-dev:arm64.
EOF
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# Same Build-Depends Linux 6.12 scripts/package/mkdebian gives dpkg-buildpackage.
# Run it before download so a cross build does not fail an hour later on
# libssl-dev:<target-arch>.
check_kernel_package_deps() {
    local debarch native_arch host_gnu control err
    if [[ -n "$KBUILD_DEBARCH" ]]; then
        debarch=$KBUILD_DEBARCH
    else
        debarch=$(dpkg --print-architecture)
    fi
    need_cmd dpkg-checkbuilddeps
    need_cmd dpkg-architecture
    info "checking packages for ${debarch} kernel .deb"
    host_gnu=$(env -u CC -u CROSS_COMPILE dpkg-architecture -a "$debarch" -q DEB_HOST_GNU_TYPE 2>/dev/null | sed 's/_/-/g')
    [[ -n "$host_gnu" ]] || die "cannot determine the Debian toolchain package for ${debarch}"
    native_arch=$(dpkg --print-architecture)
    control=$(mktemp)
    cat >"$control" <<EOF
Source: linux-upstream
Section: kernel
Priority: optional
Maintainer: kernel build <kernel-build@localhost>
Rules-Requires-Root: no
Build-Depends: debhelper-compat (= 12)
Build-Depends-Arch: bc, bison, cpio, flex,
 gcc-${host_gnu} <!pkg.linux-upstream.nokernelheaders>,
 kmod, libelf-dev:native,
 libssl-dev:native, libssl-dev <!pkg.linux-upstream.nokernelheaders>,
 rsync
Homepage: https://www.kernel.org/

Package: linux-image
Architecture: ${debarch}
Description: kernel package build dependencies
 placeholder
EOF
    if err=$(dpkg-checkbuilddeps -a "$debarch" "$control" 2>&1); then
        rm -f "$control"
        return 0
    fi
    rm -f "$control"
    report_missing_packages "$debarch" "$native_arch" "$err"
}

# dpkg-checkbuilddeps joins unmet dependencies with spaces. One dependency
# can contain spaces of its own: "pkg (= 1)", "pkg [arch]", "pkg <!profile>",
# and "pkg | other". A new dependency starts at the next package name.
split_build_deps() {
    local rest=$1
    local word="" depth=0 ch open close current="" after_or=0
    local -a words=()
    rest=${rest#"${rest%%[![:space:]]*}"}
    rest=${rest%"${rest##*[![:space:]]}"}
    while [[ -n "$rest" ]]; do
        rest=${rest#"${rest%%[![:space:]]*}"}
        [[ -z "$rest" ]] && break
        ch=${rest:0:1}
        word=""
        if [[ "$ch" == '(' || "$ch" == '[' || "$ch" == '<' ]]; then
            # Version relations contain "<" and ">" inside "()", so only the
            # bracket that opened this word closes it.
            open=$ch
            case "$open" in
                '(') close=')' ;;
                '[') close=']' ;;
                '<') close='>' ;;
            esac
            depth=0
            while [[ -n "$rest" ]]; do
                ch=${rest:0:1}
                rest=${rest:1}
                word+="$ch"
                if [[ "$ch" == "$open" ]]; then
                    depth=$((depth + 1))
                elif [[ "$ch" == "$close" ]]; then
                    depth=$((depth - 1))
                    if [[ "$depth" -eq 0 ]]; then
                        break
                    fi
                fi
            done
        else
            while [[ -n "$rest" && "$rest" != [[:space:]]* ]]; do
                word+="${rest:0:1}"
                rest=${rest:1}
            done
        fi
        words+=("$word")
    done

    DEP_TOKENS=()
    for word in "${words[@]}"; do
        if [[ "$word" == "|" ]]; then
            current=${current%"${current##*[![:space:]]}"}
            current+=" | "
            after_or=1
            continue
        fi
        if [[ "$after_or" -eq 1 ]]; then
            current+="$word"
            after_or=0
            continue
        fi
        if [[ -z "$current" ]]; then
            current=$word
            continue
        fi
        case "$word" in
            '('*|'['*|'<'*)
                current+=" $word"
                ;;
            *)
                DEP_TOKENS+=("$current")
                current=$word
                ;;
        esac
    done
    if [[ -n "$current" ]]; then
        DEP_TOKENS+=("$current")
    fi
}

# Architecture and Multi-Arch of a real package, or of the package that
# provides a virtual one such as debhelper-compat. Empty when apt has neither.
lookup_pkg_arch() {
    local name=$1 provider meta=""
    PKG_MULTI=""
    PKG_ARCH=""
    meta=$(apt-cache show "$name" 2>/dev/null | awk '
        /^$/ { exit }
        /^Multi-Arch:/ { ma = $2 }
        /^Architecture:/ { ar = $2 }
        END { if (ar != "" || ma != "") printf "%s\t%s\n", ma, ar }
    ' || true)
    if [[ -z "$meta" ]]; then
        provider=$(apt-cache showpkg "$name" 2>/dev/null | awk '
            /^Reverse Provides:/ { found = 1; next }
            found && $1 ~ /^[a-z0-9][a-z0-9+.-]*$/ { print $1; exit }
        ' || true)
        if [[ -n "$provider" ]]; then
            meta=$(apt-cache show "$provider" 2>/dev/null | awk '
                /^$/ { exit }
                /^Multi-Arch:/ { ma = $2 }
                /^Architecture:/ { ar = $2 }
                END { if (ar != "" || ma != "") printf "%s\t%s\n", ma, ar }
            ' || true)
        fi
    fi
    if [[ -n "$meta" ]]; then
        PKG_MULTI=${meta%%$'\t'*}
        PKG_ARCH=${meta#*$'\t'}
    fi
}

quote_apt_atom() {
    local atom=$1
    case "$atom" in
        *' '*|*'('*|*')'*|*"'"*)
            atom=${atom//\'/\'\\\'\'}
            printf "'%s'" "$atom"
            ;;
        *)
            printf '%s' "$atom"
            ;;
    esac
}

report_missing_packages() {
    local debarch=$1 native_arch=$2 err=$3
    local unmet dep alt name relation spec multi arch need_foreign=0
    local rel_re='^([^[:space:]]+)[[:space:]]+(\([^)]*\))'
    local -a install=()
    printf 'error: packages required to build the %s kernel .deb are not installed.\n' "$debarch" >&2
    printf '%s\n' "$err" >&2
    if [[ "$err" =~ Unmet\ build\ dependencies:\ (.*) ]]; then
        unmet=${BASH_REMATCH[1]}
    else
        exit 1
    fi
    split_build_deps "$unmet"
    for dep in "${DEP_TOKENS[@]}"; do
        # An alternative list is "pkg | other". The first one is enough.
        alt=${dep%% | *}
        alt=${alt#"${alt%%[![:space:]]*}"}
        alt=${alt%"${alt##*[![:space:]]}"}
        [[ -z "$alt" ]] && continue
        # rel_re is a variable so the ")" in the version pattern does not end [[ ]].
        if [[ "$alt" =~ $rel_re ]]; then
            name=${BASH_REMATCH[1]}
            relation=${BASH_REMATCH[2]}
        else
            name=${alt%%[[:space:]]*}
            relation=""
        fi
        [[ -z "$name" ]] && continue
        if [[ "$name" == *:native ]]; then
            name=${name%:native}
        elif [[ "$name" != *:* ]]; then
            lookup_pkg_arch "$name"
            multi=$PKG_MULTI
            arch=$PKG_ARCH
            if [[ "$debarch" != "$native_arch" && "$multi" != "foreign" && "$arch" != "all" ]]; then
                name="${name}:${debarch}"
                need_foreign=1
            fi
        fi
        spec=$name
        if [[ -n "$relation" ]]; then
            spec="$name $relation"
        fi
        install+=("$(quote_apt_atom "$spec")")
    done
    if [[ "${#install[@]}" -eq 0 ]]; then
        exit 1
    fi
    printf '\n' >&2
    if [[ "$need_foreign" -eq 1 ]] && ! dpkg --print-foreign-architectures | grep -qx "$debarch"; then
        printf 'sudo dpkg --add-architecture %s\n' "$debarch" >&2
    fi
    # archive.ubuntu.com lists foreign architectures in Release but does not
    # publish their indexes (404). Those packages are on ports.ubuntu.com.
    if [[ "$need_foreign" -eq 1 ]] && grep -Rqs 'archive.ubuntu.com' /etc/apt/sources.list /etc/apt/sources.list.d && ! grep -Rqs 'ports.ubuntu.com' /etc/apt/sources.list /etc/apt/sources.list.d; then
        local codename=""
        if [[ -r /etc/os-release ]]; then
            codename=$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")
        fi
        if [[ -n "$codename" ]]; then
            printf 'archive.ubuntu.com has no %s package indexes. Add Ubuntu ports, then install:\n' "$debarch" >&2
            printf 'sudo tee /etc/apt/sources.list.d/ubuntu-ports-%s.list >/dev/null <<'\''EOF'\''\n' "$debarch" >&2
            printf 'deb [arch=%s] http://ports.ubuntu.com/ubuntu-ports %s main universe restricted multiverse\n' "$debarch" "$codename" >&2
            printf 'deb [arch=%s] http://ports.ubuntu.com/ubuntu-ports %s-updates main universe restricted multiverse\n' "$debarch" "$codename" >&2
            printf 'deb [arch=%s] http://ports.ubuntu.com/ubuntu-ports %s-security main universe restricted multiverse\n' "$debarch" "$codename" >&2
            printf 'EOF\n' >&2
        fi
    fi
    printf 'sudo apt-get update\n' >&2
    printf 'sudo apt-get install %s\n' "${install[*]}" >&2
    exit 1
}

abspath_existing() {
    local path=$1
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    elif [[ -e "$path" ]]; then
        local dir base
        dir=$(dirname "$path")
        base=$(basename "$path")
        printf '%s/%s\n' "$(cd "$dir" && pwd)" "$base"
    else
        die "path not found: $path"
    fi
}

download() {
    local url=$1 dest=$2
    if command -v wget >/dev/null 2>&1; then
        wget -c -O "$dest" "$url"
    elif command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 -C - -o "$dest" "$url"
    else
        die "wget or curl is required to download $url"
    fi
}

require_series_patches() {
    local series=$1 patch_dir=$2
    local line name count=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%%#*}
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        [[ -z "$line" ]] && continue
        name=${line%%[[:space:]]*}
        if [[ ! -f "$patch_dir/$name" ]]; then
            die "patch listed in the series was not copied: $name"
        fi
        count=$((count + 1))
    done <"$series"
    if [[ "$count" -eq 0 ]]; then
        die "no patches selected for kernel ${KERNEL_VER} os ${OS_TYPE}; check Patch_Status_Table.txt"
    fi
    info "series contains ${count} patches"
}

resolve_patch_table() {
    local table=$1
    if [[ "$table" != /* ]]; then
        if [[ -f "$table" ]]; then
            table=$(abspath_existing "$table")
        elif [[ -f "$LINUX_RECIPES/$table" ]]; then
            table="$LINUX_RECIPES/$table"
        else
            die "patch table not found: $table"
        fi
    fi
    [[ -f "$table" ]] || die "patch table not found: $table"
    if ! grep -qx "Kernel-${KERNEL_BASE}" "$table"; then
        die "no Kernel-${KERNEL_BASE} section in $table"
    fi
    printf '%s\n' "$table"
}

list_third_party_patches() {
    local dir=$1 patch
    THIRD_PARTY_PATCHES=()
    THIRD_PARTY_STRIPS=()
    while IFS= read -r patch; do
        [[ -n "$patch" ]] || continue
        [[ -f "$dir/$patch" ]] || die "third-party patch not found: $dir/$patch"
        THIRD_PARTY_PATCHES+=("$patch")
        THIRD_PARTY_STRIPS+=(1)
    done < <(find "$dir" -maxdepth 1 -type f -name '*.patch' -printf '%f\n' | LC_ALL=C sort -V)
    if [[ "${#THIRD_PARTY_PATCHES[@]}" -eq 0 ]]; then
        die "no *.patch files in $dir"
    fi
}

run_deploy() {
    local table=$1 series=$2
    info "selecting patches from $(basename "$table")"
    python3 "$DEPLOY" \
        --kernel_version "$KERNEL_VER" \
        --patch_table "$table" \
        --dst_candidate_folder "$PATCH_DIR/" \
        --series_file "$series" \
        --config_file "$SRC_DIR/.config" \
        --os_type "$OS_TYPE" \
        --arch "$DEPLOY_ARCH" \
        --verbose 1
}

import_series() {
    local series=$1
    info "importing $(basename "$series")"
    (
        cd "$SRC_DIR"
        stg import -s "$series"
    )
}

import_third_party_patches() {
    local dir=$1 i name strip
    info "importing ${#THIRD_PARTY_PATCHES[@]} third-party patches from $dir"
    for i in "${!THIRD_PARTY_PATCHES[@]}"; do
        name=${THIRD_PARTY_PATCHES[$i]}
        strip=${THIRD_PARTY_STRIPS[$i]}
        info "third-party: $name"
        (
            cd "$SRC_DIR"
            stg import -p "$strip" "$dir/$name"
        )
    done
}

prepare_git_tree() {
    # Caller is already in the extracted kernel tree.
    # make deb-pkg packs the source archive from this commit, so Makefile,
    # scripts/, kernel/, and the rest of the extracted tree have to be in it.
    # stg import applies with git apply --index, which also refuses to edit
    # a file that is not in the index.
    # This repo is the extracted kernel, not the hw-mgmt checkout.
    git init -q
    git config commit.gpgsign false
    if ! git config user.email >/dev/null 2>&1; then
        git config user.name "hw-mgmt kernel build"
        git config user.email "hw-mgmt@localhost"
    fi
    # No -f: kernel .gitignore must keep defconfig output (include/config)
    # out of this commit. git add -A still honors .gitignore.
    git add -A
    git commit -qm "Check in the kernel source tree"
    stg init
}

# Caller must disable errexit around this function. Toggling set -e inside a
# function that runs under "if" does not stick, and a failing pipeline would
# otherwise abort before its status can be returned.
run_make() {
    local logfile=$1
    shift
    local -a pipe_status=()
    make -C "$SRC_DIR" ARCH="$MAKE_ARCH" "$@" 2>&1 | tee "$logfile"
    pipe_status=("${PIPESTATUS[@]}")
    if [[ "${pipe_status[0]}" -ne 0 ]]; then
        return "${pipe_status[0]}"
    fi
    return "${pipe_status[1]}"
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --os-type|--os_type)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            OS_TYPE=$2
            OS_TYPE_SET=1
            shift 2
            ;;
        --os-type=*|--os_type=*)
            OS_TYPE=${1#*=}
            OS_TYPE_SET=1
            shift
            ;;
        --arch)
            [[ $# -ge 2 ]] || die "--arch requires a value"
            ARCH_SET=$2
            shift 2
            ;;
        --arch=*)
            ARCH_SET=${1#*=}
            shift
            ;;
        --cross-compile)
            [[ $# -ge 2 ]] || die "--cross-compile requires a value"
            CROSS_COMPILE=$2
            CROSS_COMPILE_SET=1
            shift 2
            ;;
        --cross-compile=*)
            CROSS_COMPILE=${1#*=}
            CROSS_COMPILE_SET=1
            shift
            ;;
        --config)
            [[ $# -ge 2 ]] || die "--config requires a value"
            CONFIG_FILE=$2
            shift 2
            ;;
        --config=*)
            CONFIG_FILE=${1#*=}
            shift
            ;;
        --patch-table|--patch_table)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            PATCH_TABLE=$2
            shift 2
            ;;
        --patch-table=*|--patch_table=*)
            PATCH_TABLE=${1#*=}
            shift
            ;;
        --bmc-patch-table|--bmc_patch_table)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            BMC_PATCH_TABLE=$2
            shift 2
            ;;
        --bmc-patch-table=*|--bmc_patch_table=*)
            BMC_PATCH_TABLE=${1#*=}
            shift
            ;;
        --third-party-patches|--third_party_patches)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            THIRD_PARTY_DIR=$2
            shift 2
            ;;
        --third-party-patches=*|--third_party_patches=*)
            THIRD_PARTY_DIR=${1#*=}
            shift
            ;;
        --deploy-arch|--deploy_arch)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            DEPLOY_ARCH_SET=$2
            shift 2
            ;;
        --deploy-arch=*|--deploy_arch=*)
            DEPLOY_ARCH_SET=${1#*=}
            shift
            ;;
        --tarball)
            [[ $# -ge 2 ]] || die "--tarball requires a value"
            TARBALL=$2
            shift 2
            ;;
        --tarball=*)
            TARBALL=${1#*=}
            shift
            ;;
        --jobs)
            [[ $# -ge 2 ]] || die "--jobs requires a value"
            JOBS=$2
            shift 2
            ;;
        --jobs=*)
            JOBS=${1#*=}
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --no-retry)
            NO_RETRY=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --)
            shift
            POSITIONAL+=("$@")
            break
            ;;
        -*)
            die "unknown option: $1 (try --help)"
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [[ "${#POSITIONAL[@]}" -ne 3 ]]; then
    printf 'error: expected <build_path> <hw_mgmt_path> <kernel_version>\n' >&2
    printf 'try: %s --help\n' "$0" >&2
    exit 2
fi

BUILD_PATH=${POSITIONAL[0]}
HW_MGMT_PATH=${POSITIONAL[1]}
KERNEL_VER=${POSITIONAL[2]}

if [[ "$DEBUG" -eq 1 ]]; then
    set -x
fi

if [[ ! "$KERNEL_VER" =~ ^6\.[0-9]+\.[0-9]+$ ]]; then
    die "kernel version must look like 6.12.94 (this script downloads from kernel.org v6.x)"
fi
KERNEL_BASE=${KERNEL_VER%.*}

OS_TYPE=${OS_TYPE,,}
case "$OS_TYPE" in
    nvos|opt|cumulus|sonic|dvs) ;;
    none) OS_TYPE="None" ;;
    *) die "unsupported os type: $OS_TYPE (expected nvos, opt, cumulus, sonic, dvs, or none)" ;;
esac

if [[ -n "$ARCH_SET" ]]; then
    case "${ARCH_SET,,}" in
        x86_64|amd64|x86)
            MAKE_ARCH="x86_64"
            DEPLOY_ARCH="amd64"
            # Package architecture follows the kernel, not the build machine.
            # An arm64 host cross-building x86 must check amd64 packages.
            KBUILD_DEBARCH="amd64"
            ;;
        arm64|aarch64|arm)
            MAKE_ARCH="arm64"
            DEPLOY_ARCH="arm64"
            KBUILD_DEBARCH="arm64"
            if [[ "$CROSS_COMPILE_SET" -eq 0 ]]; then
                CROSS_COMPILE="aarch64-linux-gnu-"
            fi
            ;;
        *)
            die "unsupported arch: $ARCH_SET (expected x86_64 or arm64)"
            ;;
    esac
fi

if [[ -n "$DEPLOY_ARCH_SET" ]]; then
    case "${DEPLOY_ARCH_SET,,}" in
        amd64|arm64|aspeed)
            DEPLOY_ARCH=${DEPLOY_ARCH_SET,,}
            ;;
        *)
            die "unsupported kconfig arch: $DEPLOY_ARCH_SET (expected amd64, arm64, or aspeed)"
            ;;
    esac
fi

if [[ -n "$JOBS" && ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
    die "--jobs must be a positive integer"
fi
if [[ -z "$JOBS" ]]; then
    need_cmd nproc
    JOBS=$(( $(nproc) * 3 / 4 ))
    if [[ "$JOBS" -lt 1 ]]; then
        JOBS=1
    fi
fi

[[ -d "$HW_MGMT_PATH" ]] || die "hw-mgmt path not found: $HW_MGMT_PATH"
HW_MGMT_PATH=$(abspath_existing "$HW_MGMT_PATH")
LINUX_RECIPES="$HW_MGMT_PATH/recipes-kernel/linux"
DEPLOY="$LINUX_RECIPES/deploy_kernel_patches.py"
[[ -f "$DEPLOY" ]] || die "deploy tool not found: $DEPLOY"

if [[ -z "$PATCH_TABLE" ]]; then
    PATCH_TABLE="$LINUX_RECIPES/Patch_Status_Table.txt"
fi
PATCH_TABLE=$(resolve_patch_table "$PATCH_TABLE")
if [[ -n "$BMC_PATCH_TABLE" ]]; then
    if [[ -z "$THIRD_PARTY_DIR" ]]; then
        die "--bmc-patch-table requires --third-party-patches"
    fi
    BMC_PATCH_TABLE=$(resolve_patch_table "$BMC_PATCH_TABLE")
fi
if [[ -n "$THIRD_PARTY_DIR" ]]; then
    [[ -d "$THIRD_PARTY_DIR" ]] || die "third-party patch folder not found: $THIRD_PARTY_DIR"
    THIRD_PARTY_DIR=$(abspath_existing "$THIRD_PARTY_DIR")
    list_third_party_patches "$THIRD_PARTY_DIR"
fi

if [[ -n "$CONFIG_FILE" ]]; then
    [[ -f "$CONFIG_FILE" ]] || die "config not found: $CONFIG_FILE"
    CONFIG_FILE=$(abspath_existing "$CONFIG_FILE")
fi
if [[ -n "$TARBALL" ]]; then
    [[ -f "$TARBALL" ]] || die "tarball not found: $TARBALL"
    TARBALL=$(abspath_existing "$TARBALL")
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$BUILD_PATH" || die "cannot create build path: $BUILD_PATH"
fi
if [[ -d "$BUILD_PATH" ]]; then
    BUILD_PATH=$(abspath_existing "$BUILD_PATH")
else
    parent=$(dirname "$BUILD_PATH")
    base=$(basename "$BUILD_PATH")
    if [[ -d "$parent" ]]; then
        BUILD_PATH="$(cd "$parent" && pwd)/$base"
    fi
fi

SRC_DIR="$BUILD_PATH/linux-${KERNEL_VER}"
PATCH_DIR="$BUILD_PATH/patches"
SERIES_FILE="$PATCH_DIR/series"
DEFAULT_CONFIG="$(dirname "$BUILD_PATH")/.config_${KERNEL_BASE}"

case "$BUILD_PATH/" in
    "$HW_MGMT_PATH"/*)
        warn "build path is inside the hw-mgmt tree; kernel sources will be untracked files there"
        ;;
esac

need_cmd tar
need_cmd xz
need_cmd git
need_cmd stg
need_cmd python3
need_cmd make
if [[ -z "$TARBALL" && ! -f "$BUILD_PATH/linux-${KERNEL_VER}.tar.xz" ]]; then
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        die "wget or curl is required to download the kernel"
    fi
fi
if [[ "$SKIP_BUILD" -eq 0 ]]; then
    if [[ -n "$CROSS_COMPILE" ]]; then
        need_cmd "${CROSS_COMPILE}gcc"
    else
        need_cmd gcc
    fi
    check_kernel_package_deps
fi

info "build path:  $BUILD_PATH"
info "hw-mgmt:     $HW_MGMT_PATH"
info "kernel:      $KERNEL_VER (patch table Kernel-${KERNEL_BASE})"
if [[ "$OS_TYPE_SET" -eq 1 ]]; then
    info "os type:     $OS_TYPE"
else
    info "os type:     $OS_TYPE (default; pass --os-type to select another NOS)"
fi
info "arch:        make ARCH=$MAKE_ARCH, kconfig $DEPLOY_ARCH, deb $KBUILD_DEBARCH"
if [[ -n "$CROSS_COMPILE" ]]; then
    info "cross:       ${CROSS_COMPILE}gcc"
fi
if [[ -n "$CONFIG_FILE" ]]; then
    info "base config: $CONFIG_FILE"
elif [[ -f "$DEFAULT_CONFIG" ]]; then
    info "base config: $DEFAULT_CONFIG"
else
    info "base config: defconfig (no $DEFAULT_CONFIG)"
fi
info "patch table: $PATCH_TABLE"
if [[ -n "$THIRD_PARTY_DIR" ]]; then
    info "third-party: $THIRD_PARTY_DIR (${#THIRD_PARTY_PATCHES[@]} patches, filename order)"
fi
if [[ -n "$BMC_PATCH_TABLE" ]]; then
    info "bmc table:   $BMC_PATCH_TABLE"
fi
info "jobs:        $JOBS"

if [[ "$DRY_RUN" -eq 1 ]]; then
    info "dry-run: not downloading, patching, or building"
    exit 0
fi

if [[ -d "$SRC_DIR" || -d "$PATCH_DIR" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
        info "removing existing $SRC_DIR and $PATCH_DIR"
        rm -rf "$SRC_DIR" "$PATCH_DIR"
    else
        die "output already exists under $BUILD_PATH (pass --force to replace linux-${KERNEL_VER} and patches/)"
    fi
fi

ARCHIVE_NAME="linux-${KERNEL_VER}.tar.xz"
USER_TARBALL=0
if [[ -n "$TARBALL" ]]; then
    USER_TARBALL=1
fi
if [[ -z "$TARBALL" ]]; then
    TARBALL="$BUILD_PATH/$ARCHIVE_NAME"
fi
if [[ -f "$TARBALL" ]] && ! xz -t "$TARBALL"; then
    if [[ "$USER_TARBALL" -eq 1 ]]; then
        die "tarball failed xz check: $TARBALL"
    fi
    warn "removing corrupt $TARBALL"
    rm -f "$TARBALL"
fi
if [[ ! -f "$TARBALL" ]]; then
    url="https://cdn.kernel.org/pub/linux/kernel/v6.x/${ARCHIVE_NAME}"
    info "downloading $url"
    if ! download "$url" "$TARBALL"; then
        rm -f "$TARBALL"
        die "failed to download $url"
    fi
else
    info "using existing $TARBALL"
fi
info "checking $TARBALL"
if ! xz -t "$TARBALL"; then
    if [[ "$USER_TARBALL" -eq 0 ]]; then
        rm -f "$TARBALL"
    fi
    die "tarball failed xz check: $TARBALL"
fi
info "extracting $TARBALL"
tar -xf "$TARBALL" -C "$BUILD_PATH"
[[ -d "$SRC_DIR" ]] || die "archive did not contain $SRC_DIR"

mkdir -p "$PATCH_DIR"
: >"$SERIES_FILE"

info "generating ${MAKE_ARCH} defconfig"
make -C "$SRC_DIR" ARCH="$MAKE_ARCH" defconfig >/dev/null
(
    cd "$SRC_DIR"
    prepare_git_tree
)

if [[ -n "$CONFIG_FILE" ]]; then
    info "copying $CONFIG_FILE onto .config"
    cp "$CONFIG_FILE" "$SRC_DIR/.config"
elif [[ -f "$DEFAULT_CONFIG" ]]; then
    info "copying $DEFAULT_CONFIG onto .config"
    cp "$DEFAULT_CONFIG" "$SRC_DIR/.config"
fi

run_deploy "$PATCH_TABLE" "$SERIES_FILE"
require_series_patches "$SERIES_FILE" "$PATCH_DIR"
import_series "$SERIES_FILE"

if [[ -n "$THIRD_PARTY_DIR" ]]; then
    import_third_party_patches "$THIRD_PARTY_DIR"
fi

if [[ -n "$BMC_PATCH_TABLE" ]]; then
    BMC_SERIES_FILE="$PATCH_DIR/series-bmc"
    : >"$BMC_SERIES_FILE"
    run_deploy "$BMC_PATCH_TABLE" "$BMC_SERIES_FILE"
    require_series_patches "$BMC_SERIES_FILE" "$PATCH_DIR"
    import_series "$BMC_SERIES_FILE"
fi

if [[ "$SKIP_BUILD" -eq 1 ]]; then
    info "patches imported; skipping build (--skip-build)"
    exit 0
fi

export ARCH="$MAKE_ARCH"
export CROSS_COMPILE
if [[ -n "$KBUILD_DEBARCH" ]]; then
    export KBUILD_DEBARCH
else
    unset KBUILD_DEBARCH
fi

info "resolving .config (olddefconfig)"
make -C "$SRC_DIR" ARCH="$MAKE_ARCH" olddefconfig

BUILD_LOG="$BUILD_PATH/kernel-build.log"
info "building packages (-j$JOBS); log: $BUILD_LOG"
set +e
run_make "$BUILD_LOG" deb-pkg -j"$JOBS"
build_rc=$?
set -e

if [[ "$build_rc" -ne 0 && "$NO_RETRY" -eq 0 ]]; then
    RETRY_LOG="$BUILD_PATH/kernel-build-retry.log"
    warn "kernel build failed (rc=$build_rc). Log: $BUILD_LOG"
    info "restarting with -j2 V=1 so the error is not interleaved; log: $RETRY_LOG"
    set +e
    run_make "$RETRY_LOG" deb-pkg -j2 V=1
    build_rc=$?
    set -e
fi

if [[ "$build_rc" -ne 0 ]]; then
    printf 'error: kernel build failed (rc=%s)\n' "$build_rc" >&2
    exit "$build_rc"
fi

info "packages are in $BUILD_PATH"
exit 0
