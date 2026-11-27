#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

################################################################################
# Run the hw-mgmt test suite inside a Docker container.
#
# The repository is bind-mounted read-write at its own host path (so tests/logs
# and coverage reports land in your checkout) and the container runs as your
# own uid/gid, so no root-owned files are left behind.
#
# Usage:
#   tests/run-tests.sh [wrapper options] [-- ] [test.py arguments]
#
# Wrapper options:
#   --rebuild      Rebuild the image even if it already exists
#   --build-only   Build the image and exit
#   --bash         Open an interactive bash in the container instead of tests
#   --ngci         Enable the ngci_tool checks (see below)
#   -h, --help     Show this help
#
# With no test.py arguments, runs: --offline --skip-ngci
# (with --ngci: --offline, so the ngci_tool checks run too)
#
# Examples:
#   tests/run-tests.sh
#   tests/run-tests.sh --offline --skip-ngci
#   tests/run-tests.sh --offline -sn --coverage-html
#   tests/run-tests.sh --ngci                # offline tests + ngci_tool checks
#   tests/run-tests.sh --ngci --all -o my-branch
#   tests/run-tests.sh --shell --shellcheck  # ShellSpec + ShellCheck
#   tests/run-tests.sh --bash                # bash prompt in the container
#   tests/run-tests.sh pytest -k thermal     # run any other command
#
# If the first argument is not an option (does not start with "-"), it is run
# as the command itself instead of test.py. Example: "pytest ..." or "bash".
#
# ngci_tool (--ngci):
#   ngci_tool.sh lives on the NFS share and starts its own Docker containers
#   (beautifier, spell check, ...). --ngci therefore mounts:
#     - the ngci directory, read-only, at the path where test.py looks for it
#     - the host Docker socket, so ngci_tool starts its containers on the host
#       (this gives the container control of the host Docker: use on your own
#       workstation or lab host only)
#   The repository is mounted at its host path in all modes, because the host
#   daemon resolves the "-v <repo>:/git-repo" that ngci_tool passes on.
#
# Environment:
#   HW_MGMT_NGCI_DIR      ngci directory on the host (default: the path below).
#                         It is always mounted at the path test.py expects.
#   HW_MGMT_TESTS_IMAGE   Image name (default: hw-mgmt-tests)
#   DOCKER                Container CLI (default: docker; podman also works)
#   DOCKER_EXTRA_ARGS     Extra arguments for "docker run" (word-split)
#   DOCKER_BUILD_ARGS     Extra arguments for "docker build" (word-split)
#   http_proxy, https_proxy, no_proxy (and upper-case variants) are forwarded
#   to the image build.
################################################################################

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="${TESTS_DIR}/docker"
REPO_ROOT="$(dirname "${TESTS_DIR}")"

DOCKER="${DOCKER:-docker}"
IMAGE_NAME="${HW_MGMT_TESTS_IMAGE:-hw-mgmt-tests}"

REBUILD=0
BUILD_ONLY=0
INTERACTIVE=0
NGCI=0

usage() {
    sed -n '/^# Run the hw-mgmt/,/^####/{/^####/d;s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Wrapper options are only recognised before the first other argument, so
# test.py options such as --shell are never swallowed.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild)    REBUILD=1; shift ;;
        --build-only) BUILD_ONLY=1; shift ;;
        --bash)       INTERACTIVE=1; shift ;;
        --ngci)       NGCI=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; break ;;
        *)            break ;;
    esac
done

command -v "${DOCKER}" >/dev/null 2>&1 || die "'${DOCKER}' not found in PATH"

# The tag follows the content of the image inputs, so editing the Dockerfile or
# requirements.txt triggers a rebuild automatically.
IMAGE_HASH="$(cat "${DOCKER_DIR}/Dockerfile" "${TESTS_DIR}/requirements.txt" | sha256sum | cut -c1-12)"
IMAGE="${IMAGE_NAME}:${IMAGE_HASH}"

build_image() {
    local -a build_args=()
    local var
    for var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
        if [[ -n "${!var:-}" ]]; then
            build_args+=(--build-arg "${var}=${!var}")
        fi
    done
    echo "[INFO] Building image ${IMAGE}"
    # shellcheck disable=SC2086
    "${DOCKER}" build \
        "${build_args[@]}" \
        ${DOCKER_BUILD_ARGS:-} \
        -t "${IMAGE}" \
        -t "${IMAGE_NAME}:latest" \
        -f "${DOCKER_DIR}/Dockerfile" \
        "${TESTS_DIR}"
}

if [[ ${REBUILD} -eq 1 ]] || ! "${DOCKER}" image inspect "${IMAGE}" >/dev/null 2>&1; then
    build_image
fi

[[ ${BUILD_ONLY} -eq 1 ]] && exit 0

# Command inside the container.
if [[ ${INTERACTIVE} -eq 1 ]]; then
    CMD=(bash)
elif [[ $# -eq 0 && ${NGCI} -eq 1 ]]; then
    CMD=(python3 "${TESTS_DIR}/test.py" --offline)
elif [[ $# -eq 0 ]]; then
    CMD=(python3 "${TESTS_DIR}/test.py" --offline --skip-ngci)
elif [[ "$1" == -* ]]; then
    CMD=(python3 "${TESTS_DIR}/test.py" "$@")
else
    CMD=("$@")
fi

RUN_ARGS=(
    --rm
    --init
    --user "$(id -u):$(id -g)"
    --volume "${REPO_ROOT}:${REPO_ROOT}"
    --workdir "${TESTS_DIR}"
    # Unprivileged uid has no passwd entry in the image; give it a writable HOME.
    --env HOME=/tmp
    # The checkout is owned by a different (host) user than git expects.
    --env GIT_CONFIG_COUNT=1
    --env GIT_CONFIG_KEY_0=safe.directory
    --env GIT_CONFIG_VALUE_0=${REPO_ROOT}
    --env TERM="${TERM:-xterm}"
)

if [[ ${NGCI} -eq 1 ]]; then
    # test.py only looks for ngci_tool.sh at this fixed path, so a custom host
    # directory is mounted there; any other target would make test.py skip the checks.
    NGCI_MOUNT="/auto/sw_system_release/ci/ngci"
    NGCI_DIR="${HW_MGMT_NGCI_DIR:-${NGCI_MOUNT}}"
    DOCKER_SOCK="${DOCKER_SOCK:-/var/run/docker.sock}"
    [[ -d "${NGCI_DIR}/ngci_tool" ]] || die "ngci directory not found: ${NGCI_DIR} (set HW_MGMT_NGCI_DIR)"
    [[ -S "${DOCKER_SOCK}" ]] || die "Docker socket not found: ${DOCKER_SOCK}"
    RUN_ARGS+=(
        --volume "${NGCI_DIR}:${NGCI_MOUNT}:ro"
        --volume "${DOCKER_SOCK}:/var/run/docker.sock"
        --group-add "$(stat -c %g "${DOCKER_SOCK}")"
    )
fi

# Keep colours and allow Ctrl-C only when attached to a terminal.
if [[ -t 0 && -t 1 ]]; then
    RUN_ARGS+=(--tty --interactive)
elif [[ ${INTERACTIVE} -eq 1 ]]; then
    die "--bash needs a terminal"
fi

echo "[INFO] Running in ${IMAGE}: ${CMD[*]}"
# shellcheck disable=SC2086
exec "${DOCKER}" run "${RUN_ARGS[@]}" ${DOCKER_EXTRA_ARGS:-} "${IMAGE}" "${CMD[@]}"
