#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Download a Linux 6.x release, apply hw-mgmt patches selected by
# recipes-kernel/linux/Patch_Status_Table.txt, and build Debian packages.
# kernel_build_7_x.sh sources this file. $0 stays the 7.x name, which
# selects kernel.org v7.x and a Kernel-7.* status-table section.
#
# Patch selection follows the Kernel-<major.minor> section of the status
# table. --os-type picks the NOS (nvos, opt, cumulus, sonic, dvs). The
# deploy tool reads markers such as os[nvos] and skip[sonic] and, when
# needed, takes the patch from recipes-kernel/linux/linux-<major.minor>/<nos>/.
# An ARM (--arch arm64) point-release overlay at
# linux-<major.minor>/<nos>/arm/<kver>/ overwrites linux-<major.minor>/<patch>.
# x86 keeps linux-<major.minor>/<nos>/ only.
#

set -euo pipefail

# The 7.x entry points source this file, so $0 remains kernel_build_7*.
# Inside the build container $0 is this file; the entry name is passed in
# KERNEL_BUILD_ENTRY so the series and example version stay the same.
KERNEL_BUILD_ENTRY="${KERNEL_BUILD_ENTRY:-${0##*/}}"
case "$KERNEL_BUILD_ENTRY" in
    kernel_build_7*)
        KERNEL_SERIES=7
        EXAMPLE_VER=7.0.1
        ;;
    *)
        KERNEL_SERIES=6
        EXAMPLE_VER=6.12.94
        ;;
esac
SERIES_NOTE="Patches and kconfig are read from recipes-kernel/linux/linux-<major.minor>/ and kconfig_<major>_<minor>.txt. A ${KERNEL_SERIES}.x build needs a Kernel-${KERNEL_SERIES}.* section in the status table."

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
DEPLOY_SRC=""
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

Download a Linux ${KERNEL_SERIES}.x tarball, apply the hw-mgmt patches listed
for that version in recipes-kernel/linux/Patch_Status_Table.txt, and build
Debian packages with "make deb-pkg".

${SERIES_NOTE}

The status table decides which patches apply. --os-type selects the NOS.
Patches marked for another NOS are skipped. A patch that the table ties to
one NOS is taken from recipes-kernel/linux/linux-<major.minor>/<nos>/ when
that directory is the one the deploy tool selects (x86 and all-arch).
An ARM (--arch arm64) point-release overlay at
linux-<major.minor>/<nos>/arm/<kver>/ overwrites linux-<major.minor>/<patch>
when that file exists. amd64 does not look under <arch>/<kver>/.
Status marker kver[6.12.94] documents the overlay.

Options may be placed before or after the three arguments.

Arguments:
  build_path       Work directory (created if missing). Receives the tarball,
                   linux-<version>/, patches/, the build log, and the .deb files.
  hw_mgmt_path     hw-mgmt checkout that contains recipes-kernel/linux/.
  kernel_version   Upstream release, three numeric components, for example
                   ${EXAMPLE_VER}. Must be Linux ${KERNEL_SERIES}.x.

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
                   kernel_build_${KERNEL_SERIES}_x_arm.sh is the same script with --arch arm64.
  --deploy-arch ARCH
                   Kconfig section written into .config: amd64, arm64, or aspeed.
                   Default follows --arch. kernel_build_${KERNEL_SERIES}_x_sonic_bmc.sh
                   uses arm64 tools with the aspeed section.
  --cross-compile PREFIX
                   Toolchain prefix, for example aarch64-linux-gnu-.
  --config FILE    Starting .config, copied in before hw-mgmt kconfig flags
                   are merged. If omitted and this file exists, it is used:
                   <parent of build_path>/.config_<major.minor>
                   If that file is missing, the closest older .config_X.Y is
                   used: same major first (.config_7.2 for 7.3), then an older
                   major (.config_6.12). kconfig_<major>_<minor>.txt is resolved
                   the same way. A missing kconfig is mapped in a per-build
                   folder under build_path, not in the shared hw-mgmt tree.
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
                   --third-party-patches. kernel_build_${KERNEL_SERIES}_x_sonic_bmc.sh
                   passes Patch_BMC_Status_Table.txt.
  --tarball FILE   Use this source archive instead of downloading it.
                   If omitted, linux-<version>.tar.xz is fetched from kernel.org.
                   Linus releases are named linux-<major.minor>.tar.xz (no .0/.1).
                   When the point-release archive is missing, the script tries
                   linux-<major.minor>.0.tar.xz then linux-<major.minor>.tar.xz,
                   locally under build_path first, then cdn.kernel.org and
                   mirrors.edge.kernel.org. The archive is unpacked in a
                   temporary directory, then moved to linux-<version>/. A
                   sibling linux-<major.minor>/ tree in build_path is not
                   overwritten. The unpacked Makefile VERSION/PATCHLEVEL/SUBLEVEL
                   must match the requested major.minor. A Linus X.Y (SUBLEVEL 0)
                   archive may stand in for X.Y.Z; a different series cannot.
  --jobs N         Parallel jobs for the first build. Default: 3/4 of nproc,
                   at least 1.
  --force          Delete an existing linux-<version> tree, patches/, and
                   deploy-src/ under build_path before starting. The tarball
                   and any sibling linux-<major.minor>/ tree are kept.
  --skip-build     Import patches, then stop before olddefconfig and deb-pkg.
  --no-retry       Do not start a second build after a failure.
  --dry-run        Check arguments, the patch table, and the container tools, then exit.
  --debug          Trace shell commands (set -x).

On the first build failure the log is kept and, unless --no-retry is set,
the build is repeated with -j2 and V=1 so the compiler error is readable.

Examples:
  mkdir -p /tmp/kernel-build
  ${0##*/} /tmp/kernel-build /path/to/hw-mgmt ${EXAMPLE_VER} --os_type=nvos

  kernel_build_${KERNEL_SERIES}_x_arm.sh /tmp/kernel-build /path/to/hw-mgmt ${EXAMPLE_VER} --os_type=nvos

  kernel_build_${KERNEL_SERIES}_x_sonic_bmc.sh /tmp/kernel-build /path/to/hw-mgmt ${EXAMPLE_VER} \
      --third-party-patches /path/to/sonic-patches

Docker:
  The build always runs in a container that has every tool listed below
  (see Dockerfile next to this script). The host needs only docker. The
  image is built on first use and reused afterwards. build_path,
  hw_mgmt_path and any path given in an option are mounted at the same
  absolute path inside the container, and files are created with your
  uid/gid.
  Environment:
    KERNEL_BUILD_IMAGE=NAME    Use this image and do not build the Dockerfile.
    KERNEL_BUILD_BASE_IMAGE=N  Base image for the Dockerfile
                               (default debian:bookworm).
    KERNEL_BUILD_DOCKER_ARGS   Extra arguments for "docker run".

Tools:
  All of them are installed by the Dockerfile. tar, xz, git, stg (stgit),
  python3, make, wget or curl, and gcc (or the --cross-compile gcc) are
  checked in the container before the kernel is downloaded.
  The packages for "make deb-pkg" (the Build-Depends of Linux 6.12
  scripts/package/mkdebian, used for ${KERNEL_SERIES}.x too) are debhelper, bc,
  bison, cpio, flex, kmod, rsync, libelf-dev, libssl-dev, and the gcc package
  for the package architecture. An arm64 build also needs libssl-dev:arm64.
  A custom KERNEL_BUILD_IMAGE must provide all of them.
EOF
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
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
    local url=$1 dest=$2 tmp
    tmp="${dest}.part"
    rm -f "$tmp"
    if command -v wget >/dev/null 2>&1; then
        wget -O "$tmp" "$url" || { rm -f "$tmp"; return 1; }
    elif command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
    else
        die "wget or curl is required to download $url"
    fi
    mv "$tmp" "$dest"
}

# kernel.org ships Linus X.Y as linux-X.Y.tar.xz, not linux-X.Y.0.tar.xz.
tarball_archive_names() {
    printf '%s\n' "linux-${KERNEL_VER}.tar.xz"
    if [[ "${KERNEL_VER##*.}" != "0" ]]; then
        printf '%s\n' "linux-${KERNEL_BASE}.0.tar.xz"
    fi
    printf '%s\n' "linux-${KERNEL_BASE}.tar.xz"
}

tarball_mirror_bases() {
    printf '%s\n' \
        "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_SERIES}.x" \
        "https://mirrors.edge.kernel.org/pub/linux/kernel/v${KERNEL_SERIES}.x"
}

unique_lines() {
    awk 'NF && !seen[$0]++'
}

local_tarball_exists() {
    local name dest
    while IFS= read -r name; do
        dest="$BUILD_PATH/$name"
        if [[ -f "$dest" ]] && xz -t "$dest" >/dev/null 2>&1; then
            return 0
        fi
    done < <(tarball_archive_names | unique_lines)
    return 1
}

# Prefer a usable local archive, then download the first kernel.org name that exists.
resolve_kernel_tarball() {
    local name dest url mirror used_fallback=0

    if [[ -n "$TARBALL" ]]; then
        ARCHIVE_NAME=$(basename "$TARBALL")
        return 0
    fi

    while IFS= read -r name; do
        dest="$BUILD_PATH/$name"
        if [[ -f "$dest" ]] && xz -t "$dest"; then
            if [[ "$name" != "linux-${KERNEL_VER}.tar.xz" ]]; then
                warn "linux-${KERNEL_VER}.tar.xz not present; using local $dest"
            else
                info "using existing $dest"
            fi
            TARBALL=$dest
            ARCHIVE_NAME=$name
            return 0
        fi
        if [[ -f "$dest" ]]; then
            warn "removing corrupt $dest"
            rm -f "$dest"
        fi
    done < <(tarball_archive_names | unique_lines)

    while IFS= read -r name; do
        dest="$BUILD_PATH/$name"
        [[ "$name" == "linux-${KERNEL_VER}.tar.xz" ]] || used_fallback=1
        while IFS= read -r mirror; do
            url="${mirror}/${name}"
            info "downloading $url"
            if download "$url" "$dest" && xz -t "$dest"; then
                if [[ "$used_fallback" -eq 1 ]]; then
                    warn "linux-${KERNEL_VER}.tar.xz not on kernel.org; using $name"
                fi
                TARBALL=$dest
                ARCHIVE_NAME=$name
                return 0
            fi
            rm -f "$dest"
        done < <(tarball_mirror_bases)
    done < <(tarball_archive_names | unique_lines)

    die "failed to download linux-${KERNEL_VER}.tar.xz (also tried linux-${KERNEL_BASE}.tar.xz)"
}

# Auto-fetched names are linux-X.Y.Z, linux-X.Y.0, or linux-X.Y.
# --tarball may use another filename; the unpacked Makefile is still checked.
check_archive_filename() {
    local name allowed
    name=$(basename "$TARBALL")
    while IFS= read -r allowed; do
        if [[ "$name" == "$allowed" ]]; then
            return 0
        fi
    done < <(tarball_archive_names | unique_lines)
    if [[ "$USER_TARBALL" -eq 1 ]]; then
        warn "tarball name $name is not linux-${KERNEL_VER}.tar.xz; checking the unpacked Makefile"
        return 0
    fi
    die "unexpected archive name $name for kernel ${KERNEL_VER}"
}

makefile_field() {
    local makefile=$1 field=$2
    awk -F '[[:space:]]*=[[:space:]]*' -v field="$field" '
        $1 == field { gsub(/[[:space:]]/, "", $2); print $2; exit }
    ' "$makefile"
}

# Reject an unrelated tree renamed to linux-<requested>/. Linus X.Y (SUBLEVEL 0)
# is the only allowed stand-in for requested X.Y.Z.
check_extracted_kernel_release() {
    local dir=$1
    local top makefile major minor sub extra found req_major req_minor req_sub
    top=$(basename "$dir")
    makefile="$dir/Makefile"
    if [[ ! -f "$makefile" ]]; then
        printf 'error: archive has no Makefile in %s\n' "$top" >&2
        return 1
    fi
    case "$top" in
        "linux-${KERNEL_VER}"|"linux-${KERNEL_BASE}"|"linux-${KERNEL_BASE}.0") ;;
        *)
            printf 'error: archive unpacked as %s; expected linux-%s or linux-%s[.0]\n' \
                "$top" "$KERNEL_VER" "$KERNEL_BASE" >&2
            return 1
            ;;
    esac
    major=$(makefile_field "$makefile" VERSION)
    minor=$(makefile_field "$makefile" PATCHLEVEL)
    sub=$(makefile_field "$makefile" SUBLEVEL)
    extra=$(makefile_field "$makefile" EXTRAVERSION)
    if [[ -z "$major" || -z "$minor" || -z "$sub" ]]; then
        printf 'error: cannot read VERSION/PATCHLEVEL/SUBLEVEL from %s\n' "$makefile" >&2
        return 1
    fi
    found="${major}.${minor}.${sub}"
    req_major=${KERNEL_BASE%.*}
    req_minor=${KERNEL_BASE#*.}
    req_sub=${KERNEL_VER##*.}
    if [[ -n "$extra" ]]; then
        printf 'error: archive is Linux %s%s, requested released %s\n' "$found" "$extra" "$KERNEL_VER" >&2
        return 1
    fi
    if [[ "$major" != "$req_major" || "$minor" != "$req_minor" ]]; then
        printf 'error: archive is Linux %s, requested %s\n' "$found" "$KERNEL_VER" >&2
        return 1
    fi
    if [[ "$sub" == "$req_sub" ]]; then
        info "archive release $found matches ${KERNEL_VER}"
        return 0
    fi
    if [[ "$sub" == "0" && "$req_sub" != "0" ]]; then
        warn "archive is Linux ${found} (Linus ${major}.${minor}); requested ${KERNEL_VER}"
        return 0
    fi
    printf 'error: archive is Linux %s, requested %s\n' "$found" "$KERNEL_VER" >&2
    return 1
}

# Unpack into a fresh directory, then rename to linux-<version>/.
# Direct extract into BUILD_PATH would overwrite a sibling linux-X.Y/ tree
# (Linus archives unpack as linux-X.Y/, while SRC_DIR is linux-X.Y.Z/).
extract_kernel_tarball() {
    local unpack extracted path nullglob_was_off=0
    local -a tops=()
    info "extracting $TARBALL"
    unpack=$(mktemp -d "$BUILD_PATH/unpack.XXXXXX") || die "cannot create unpack directory"
    if ! tar -xf "$TARBALL" -C "$unpack"; then
        rm -rf "$unpack"
        die "failed to extract $TARBALL"
    fi
    shopt -q nullglob || nullglob_was_off=1
    shopt -s nullglob
    for path in "$unpack"/*; do
        tops+=("$path")
    done
    if [[ "$nullglob_was_off" -eq 1 ]]; then
        shopt -u nullglob
    fi
    if [[ ${#tops[@]} -ne 1 || ! -d "${tops[0]}" ]]; then
        rm -rf "$unpack"
        die "archive did not contain a single source directory"
    fi
    extracted=${tops[0]}
    if ! check_extracted_kernel_release "$extracted"; then
        rm -rf "$unpack"
        die "archive release does not match requested kernel ${KERNEL_VER}"
    fi
    if [[ -e "$SRC_DIR" ]]; then
        rm -rf "$unpack"
        die "output already exists: $SRC_DIR (pass --force to replace linux-${KERNEL_VER} and patches/)"
    fi
    if [[ "$(basename "$extracted")" != "linux-${KERNEL_VER}" ]]; then
        info "archive unpacked as $(basename "$extracted"); moving to linux-${KERNEL_VER}"
    fi
    if ! mv "$extracted" "$SRC_DIR"; then
        rm -rf "$unpack"
        die "failed to move $(basename "$extracted") to $SRC_DIR"
    fi
    rm -rf "$unpack"
}

# <parent>/.config_7.3, then .config_7.2 .. .config_7.0, then older majors.
resolve_default_config() {
    local parent major minor i candidate f bn maj min
    local best="" best_maj=-1 best_min=-1
    parent=$(dirname "$BUILD_PATH")
    major=${KERNEL_BASE%.*}
    minor=${KERNEL_BASE#*.}
    DEFAULT_CONFIG="$parent/.config_${KERNEL_BASE}"
    [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 0
    for ((i=minor; i>=0; i--)); do
        candidate="$parent/.config_${major}.${i}"
        if [[ -f "$candidate" ]]; then
            if [[ "$i" -ne "$minor" ]]; then
                warn "no .config_${KERNEL_BASE}; using closest $candidate"
            fi
            DEFAULT_CONFIG=$candidate
            return 0
        fi
    done
    local nullglob_was_off=0
    shopt -q nullglob || nullglob_was_off=1
    shopt -s nullglob
    for f in "$parent"/.config_*.*; do
        bn=$(basename "$f")
        if [[ "$bn" =~ ^\.config_([0-9]+)\.([0-9]+)$ ]]; then
            maj=${BASH_REMATCH[1]}
            min=${BASH_REMATCH[2]}
            if (( maj > major || (maj == major && min >= minor) )); then
                continue
            fi
            if (( maj > best_maj || (maj == best_maj && min > best_min) )); then
                best=$f
                best_maj=$maj
                best_min=$min
            fi
        fi
    done
    if [[ "$nullglob_was_off" -eq 1 ]]; then
        shopt -u nullglob
    fi
    if [[ -n "$best" ]]; then
        warn "no .config_${KERNEL_BASE}; using closest $best"
        DEFAULT_CONFIG=$best
    fi
}

# Newest kconfig_X_Y.txt with version < requested. Same major wins (7.2 over 6.12).
find_closest_kconfig() {
    local want_major=$1 want_minor=$2
    local path name major minor
    local -a same=() other=()
    [[ -d "$LINUX_RECIPES" ]] || return 1
    for path in "$LINUX_RECIPES"/kconfig_*.txt; do
        [[ -f "$path" ]] || continue
        name=$(basename "$path")
        if [[ "$name" =~ ^kconfig_([0-9]+)_([0-9]+)\.txt$ ]]; then
            major=${BASH_REMATCH[1]}
            minor=${BASH_REMATCH[2]}
            if (( major > want_major || (major == want_major && minor >= want_minor) )); then
                continue
            fi
            if (( major == want_major )); then
                same+=("${major}.${minor} ${path}")
            else
                other+=("${major}.${minor} ${path}")
            fi
        fi
    done
    if [[ ${#same[@]} -gt 0 ]]; then
        printf '%s\n' "${same[@]}" | sort -V | tail -1 | awk '{print $2}'
        return 0
    fi
    if [[ ${#other[@]} -gt 0 ]]; then
        printf '%s\n' "${other[@]}" | sort -V | tail -1 | awk '{print $2}'
        return 0
    fi
    return 1
}

# Older deploy.py only opens kconfig_<major>_<minor>.txt. Map the closest
# file under build_path/deploy-src so concurrent builds do not write or
# delete kconfig in the shared hw-mgmt checkout.
prepare_deploy_src() {
    local major minor exact closest path name
    major=${KERNEL_BASE%.*}
    minor=${KERNEL_BASE#*.}
    exact="$LINUX_RECIPES/kconfig_${major}_${minor}.txt"
    DEPLOY_SRC="$LINUX_RECIPES"
    if [[ -f "$exact" ]]; then
        return 0
    fi
    closest=$(find_closest_kconfig "$major" "$minor" || true)
    if [[ -z "$closest" || ! -f "$closest" ]]; then
        warn "no $(basename "$exact") and no older kconfig_*.txt; deploy will not merge flags"
        return 0
    fi
    DEPLOY_SRC="$BUILD_PATH/deploy-src"
    rm -rf "$DEPLOY_SRC"
    mkdir -p "$DEPLOY_SRC"
    for path in "$LINUX_RECIPES"/*; do
        name=$(basename "$path")
        ln -s "$path" "$DEPLOY_SRC/$name"
    done
    ln -s "$closest" "$DEPLOY_SRC/kconfig_${major}_${minor}.txt"
    warn "no $(basename "$exact"); deploy src uses closest $(basename "$closest")"
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
    local table=$1 series=$2 src_folder
    # Older deploy.py does src_folder + "./linux-<version>"; a path without
    # a trailing slash becomes deploy-src./linux-<version> and copies nothing.
    src_folder="${DEPLOY_SRC:-$LINUX_RECIPES}"
    src_folder="${src_folder%/}/"
    info "selecting patches from $(basename "$table")"
    python3 "$DEPLOY" \
        --kernel_version "$KERNEL_VER" \
        --src_folder "$src_folder" \
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

# ---------------------------------------------------------------------------
# Docker build environment
#
# The script re-runs itself in a container built from the Dockerfile next to
# it, so the host needs only docker. The arguments are rebuilt from the
# parsed (and absolute) values, and every path is mounted at the same path
# inside the container.
# ---------------------------------------------------------------------------
KERNEL_BUILD_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MOUNT_PATHS=()
MOUNT_MODES=()

require_docker() {
    command -v docker >/dev/null 2>&1 || die "docker is required to build the kernel (not found in PATH)"
    docker info >/dev/null 2>&1 || die "cannot talk to the docker daemon"
}

# add_mount PATH MODE (ro|rw). Same path inside the container.
# Docker rejects two mounts with the same destination, so a path asked for
# twice (for example build_path that is the checkout itself) is mounted
# once, and it is writable when any of the uses needs it.
add_mount() {
    local path=$1 mode=$2 i
    [[ -e "$path" ]] || return 0
    for i in "${!MOUNT_PATHS[@]}"; do
        if [[ "${MOUNT_PATHS[$i]}" == "$path" ]]; then
            [[ "$mode" == "rw" ]] && MOUNT_MODES[i]=rw
            return 0
        fi
    done
    MOUNT_PATHS+=("$path")
    MOUNT_MODES+=("$mode")
}

# Build the image on first use. The tag follows the Dockerfile content and the
# base image, so editing the Dockerfile rebuilds it.
docker_prepare_image() {
    local dockerfile="$KERNEL_BUILD_SCRIPT_DIR/Dockerfile" base sum
    if [[ -n "${KERNEL_BUILD_IMAGE:-}" ]]; then
        DOCKER_IMAGE=$KERNEL_BUILD_IMAGE
        return 0
    fi
    [[ -f "$dockerfile" ]] || die "Dockerfile not found: $dockerfile"
    base=${KERNEL_BUILD_BASE_IMAGE:-debian:bookworm}
    sum=$({ cat "$dockerfile"; printf '%s\n' "$base"; } | cksum | awk '{print $1}')
    DOCKER_IMAGE="hw-mgmt-kernel-build:${sum}"
    if docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
        info "docker image: $DOCKER_IMAGE"
        return 0
    fi
    info "building docker image $DOCKER_IMAGE (first run only)"
    # The Dockerfile is sent on stdin: no build context is needed.
    docker build --build-arg "BASE_IMAGE=$base" -t "$DOCKER_IMAGE" - <"$dockerfile" \
        || die "docker build failed"
}

run_in_docker() {
    local -a args=() run=() extra=()
    local user_name host_name var gid i

    docker_prepare_image

    args+=("$BUILD_PATH" "$HW_MGMT_PATH" "$KERNEL_VER")
    if [[ "$OS_TYPE_SET" -eq 1 ]]; then
        args+=(--os-type "${OS_TYPE,,}")
    fi
    [[ -n "$ARCH_SET" ]] && args+=(--arch "$ARCH_SET")
    [[ "$CROSS_COMPILE_SET" -eq 1 ]] && args+=(--cross-compile "$CROSS_COMPILE")
    [[ -n "$DEPLOY_ARCH_SET" ]] && args+=(--deploy-arch "$DEPLOY_ARCH_SET")
    if [[ -n "$CONFIG_FILE" ]]; then
        args+=(--config "$CONFIG_FILE")
    elif [[ -f "$DEFAULT_CONFIG" ]]; then
        # The container does not see the parent of build_path.
        args+=(--config "$DEFAULT_CONFIG")
    fi
    args+=(--patch-table "$PATCH_TABLE")
    [[ -n "$BMC_PATCH_TABLE" ]] && args+=(--bmc-patch-table "$BMC_PATCH_TABLE")
    [[ -n "$THIRD_PARTY_DIR" ]] && args+=(--third-party-patches "$THIRD_PARTY_DIR")
    [[ -n "$TARBALL" ]] && args+=(--tarball "$TARBALL")
    args+=(--jobs "$JOBS")
    [[ "$FORCE" -eq 1 ]] && args+=(--force)
    [[ "$SKIP_BUILD" -eq 1 ]] && args+=(--skip-build)
    [[ "$NO_RETRY" -eq 1 ]] && args+=(--no-retry)
    [[ "$DRY_RUN" -eq 1 ]] && args+=(--dry-run)
    [[ "$DEBUG" -eq 1 ]] && args+=(--debug)

    MOUNT_PATHS=()
    MOUNT_MODES=()
    add_mount "$KERNEL_BUILD_SCRIPT_DIR" ro
    add_mount "$HW_MGMT_PATH" ro
    add_mount "$BUILD_PATH" rw
    add_mount "$PATCH_TABLE" ro
    [[ -n "$BMC_PATCH_TABLE" ]] && add_mount "$BMC_PATCH_TABLE" ro
    [[ -n "$THIRD_PARTY_DIR" ]] && add_mount "$THIRD_PARTY_DIR" ro
    [[ -n "$TARBALL" ]] && add_mount "$TARBALL" ro
    [[ -n "$CONFIG_FILE" ]] && add_mount "$CONFIG_FILE" ro
    [[ -z "$CONFIG_FILE" && -f "$DEFAULT_CONFIG" ]] && add_mount "$DEFAULT_CONFIG" ro

    user_name=$(id -un 2>/dev/null || id -u)
    host_name=$(hostname 2>/dev/null || echo localhost)
    run=(docker run --rm --init
        --user "$(id -u):$(id -g)"
        -e HOME=/tmp
        -e KERNEL_BUILD_IN_DOCKER=1
        -e "KERNEL_BUILD_ENTRY=$KERNEL_BUILD_ENTRY"
        # The uid has no passwd entry in the container; the kernel build
        # (mkcompile_h, mkdebian) would otherwise fail to name the builder.
        -e "KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-$user_name}"
        -e "KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-$host_name}")
    for var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
        [[ -n "${!var:-}" ]] && run+=(-e "$var=${!var}")
    done
    # --user keeps only the primary group. A shared checkout or an existing
    # build directory may be reachable through a secondary group, so pass
    # those on as well; the container then sees what the caller sees.
    for gid in $(id -G); do
        [[ "$gid" == "$(id -g)" ]] && continue
        run+=(--group-add "$gid")
    done
    [[ -t 0 ]] && run+=(-i)
    [[ -t 1 ]] && run+=(-t)
    for i in "${!MOUNT_PATHS[@]}"; do
        run+=(-v "${MOUNT_PATHS[$i]}:${MOUNT_PATHS[$i]}:${MOUNT_MODES[$i]}")
    done
    if [[ -d "$BUILD_PATH" ]]; then
        run+=(-w "$BUILD_PATH")
    fi
    if [[ -n "${KERNEL_BUILD_DOCKER_ARGS:-}" ]]; then
        # shellcheck disable=SC2206
        extra=($KERNEL_BUILD_DOCKER_ARGS)
        run+=("${extra[@]}")
    fi
    run+=("$DOCKER_IMAGE" bash "$KERNEL_BUILD_SCRIPT_DIR/kernel_build_6_x.sh" "${args[@]}")

    info "running in docker ($DOCKER_IMAGE)"
    exec "${run[@]}"
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

if [[ ! "$KERNEL_VER" =~ ^${KERNEL_SERIES}\.[0-9]+\.[0-9]+$ ]]; then
    die "kernel version must look like ${EXAMPLE_VER} (this script downloads from kernel.org v${KERNEL_SERIES}.x)"
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
resolve_default_config

case "$BUILD_PATH/" in
    "$HW_MGMT_PATH"/*)
        warn "build path is inside the hw-mgmt tree; kernel sources will be untracked files there"
        ;;
esac

# KERNEL_BUILD_IN_DOCKER is set by run_in_docker for the run inside the container.
if [[ "${KERNEL_BUILD_IN_DOCKER:-0}" != "1" ]]; then
    require_docker
    run_in_docker
fi

need_cmd tar
need_cmd xz
need_cmd git
need_cmd stg
need_cmd python3
need_cmd make
if [[ -z "$TARBALL" ]] && ! local_tarball_exists; then
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
fi

info "build path:  $BUILD_PATH"
info "hw-mgmt:     $HW_MGMT_PATH"
info "kernel:      $KERNEL_VER (patch table Kernel-${KERNEL_BASE}, kernel.org v${KERNEL_SERIES}.x)"
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
if [[ -n "$TARBALL" ]]; then
    info "tarball:     $TARBALL"
else
    info "tarball try: $(tarball_archive_names | unique_lines | awk 'NR>1{printf ", "} {printf "%s", $0}')"
fi
kconfig_exact="$LINUX_RECIPES/kconfig_${KERNEL_BASE%.*}_${KERNEL_BASE#*.}.txt"
if [[ -f "$kconfig_exact" ]]; then
    info "kconfig:     $kconfig_exact"
else
    kconfig_closest=$(find_closest_kconfig "${KERNEL_BASE%.*}" "${KERNEL_BASE#*.}" || true)
    if [[ -n "$kconfig_closest" ]]; then
        info "kconfig:     missing $(basename "$kconfig_exact"), closest $kconfig_closest"
    else
        info "kconfig:     missing $(basename "$kconfig_exact") (no older kconfig_*.txt)"
    fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    info "dry-run: not downloading, patching, or building"
    exit 0
fi

if [[ -d "$SRC_DIR" || -d "$PATCH_DIR" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
        info "removing existing $SRC_DIR and $PATCH_DIR"
        rm -rf "$SRC_DIR" "$PATCH_DIR" "$BUILD_PATH/deploy-src"
    else
        die "output already exists under $BUILD_PATH (pass --force to replace linux-${KERNEL_VER} and patches/)"
    fi
fi

USER_TARBALL=0
if [[ -n "$TARBALL" ]]; then
    USER_TARBALL=1
fi
resolve_kernel_tarball
check_archive_filename
info "checking $TARBALL"
if ! xz -t "$TARBALL"; then
    if [[ "$USER_TARBALL" -eq 0 ]]; then
        rm -f "$TARBALL"
    fi
    die "tarball failed xz check: $TARBALL"
fi
extract_kernel_tarball

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

prepare_deploy_src
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
