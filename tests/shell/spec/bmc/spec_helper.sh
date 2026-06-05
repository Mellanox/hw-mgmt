#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# Shared setup for BMC ShellSpec tests.

# Absolute path to the bmc shell scripts in the repo.
BMC_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)/bmc/usr/usr/bin"
export BMC_SCRIPTS_DIR

# Create a stubs directory for hardware commands that should be no-ops offline.
# Called from BeforeAll / BeforeEach in each spec file.
setup_bmc_stubs() {
    BMC_STUBS_DIR="$(mktemp -d)"
    export BMC_STUBS_DIR

    for cmd in logger systemctl systemd-cat systemd-analyze \
               i2ctransfer i2cset i2cget i2cdetect \
               gpioset gpioget fw_printenv fw_setenv \
               devmem ethtool mdio networkctl udhcpc modprobe hexdump; do
        printf '#!/bin/sh\nexit 0\n' > "${BMC_STUBS_DIR}/${cmd}"
        chmod +x "${BMC_STUBS_DIR}/${cmd}"
    done

    export PATH="${BMC_STUBS_DIR}:${PATH}"
}

teardown_bmc_stubs() {
    [ -n "${BMC_STUBS_DIR}" ] && rm -rf "${BMC_STUBS_DIR}"
}

# Source a BMC script, redirecting /usr/bin/ references to the repo.
source_bmc() {
    local script="${BMC_SCRIPTS_DIR}/${1}"
    # Override source built-in so scripts that source /usr/bin/hw-management-bmc-*
    # are redirected to the repo copy.
    source() {
        local f="${1/#\/usr\/bin\//${BMC_SCRIPTS_DIR}/}"
        shift
        builtin source "${f}" "$@"
    }
    # shellcheck disable=SC1090
    builtin source "${script}"
}
