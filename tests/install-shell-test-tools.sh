#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

################################################################################
# Shell Test Tools Installation Script
# 
# This script installs the required tools for shell script testing:
# - kcov: Code coverage for shell scripts
# - shellspec: BDD testing framework
# - shellcheck: Static analysis (optional)
#
# Usage:
#   ./install-shell-test-tools.sh [--user]
#
# Options:
#   --user    Install to user directory (~/.local) instead of system-wide
################################################################################

set -e

INSTALL_USER=0
if [[ "$1" == "--user" ]]; then
    INSTALL_USER=1
fi

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

################################################################################
# Install kcov
# Strategy:
#   1. Package manager (apt/yum) — requires root, fastest
#   2. Build from source — user-local, needs gcc + elfutils-devel
#      cmake is bootstrapped via a portable binary if not present.
#      libcurl-devel is not required: coveralls writer is replaced with a
#      no-op stub and the url-escape function in utils.cc is stubbed inline.
################################################################################
KCOV_VERSION_TAG="v42"
KCOV_SRC_URL="https://github.com/SimonKagstrom/kcov/archive/refs/tags/${KCOV_VERSION_TAG}.tar.gz"
CMAKE_VERSION="3.27.0"
CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh"

_install_cmake_portable() {
    if command -v cmake &>/dev/null || command -v cmake3 &>/dev/null; then
        return 0
    fi
    local prefix="${1:-$HOME/.local}"
    local installer
    installer=$(mktemp /tmp/cmake-install-XXXXXX.sh)
    info "Downloading portable cmake ${CMAKE_VERSION}..."
    if ! curl -fsSL "${CMAKE_URL}" -o "${installer}" 2>/dev/null; then
        warn "Failed to download cmake; kcov build-from-source will be skipped"
        rm -f "${installer}"
        return 1
    fi
    bash "${installer}" --prefix="${prefix}" --skip-license --exclude-subdir >/dev/null 2>&1
    rm -f "${installer}"
    command -v cmake &>/dev/null || PATH="${prefix}/bin:${PATH}"
    command -v cmake &>/dev/null
}

_build_kcov_from_source() {
    local prefix="${1:-$HOME/.local}"
    local build_dir
    build_dir=$(mktemp -d /tmp/kcov-build-XXXXXX)

    info "Downloading kcov source ${KCOV_VERSION_TAG}..."
    if ! curl -fsSL "${KCOV_SRC_URL}" -o "${build_dir}/kcov.tar.gz" 2>/dev/null; then
        warn "Failed to download kcov source"
        rm -rf "${build_dir}"
        return 1
    fi

    tar xf "${build_dir}/kcov.tar.gz" -C "${build_dir}" --strip-components=1

    # Stub libcurl dependency: replace coveralls writer with no-op and
    # forward-declare the three curl functions used in utils.cc.
    if [[ -f "${build_dir}/src/writers/dummy-coveralls-writer.cc" ]]; then
        cp "${build_dir}/src/writers/dummy-coveralls-writer.cc" \
           "${build_dir}/src/writers/coveralls-writer.cc"
    fi
    if grep -q '<curl/curl.h>' "${build_dir}/src/utils.cc" 2>/dev/null; then
        sed -i 's|#include <curl/curl.h>|// curl stubbed\ntypedef void CURL;\nextern "C" { CURL *curl_easy_init(void); char *curl_easy_escape(CURL*,const char*,int); void curl_easy_cleanup(CURL*); }|' \
            "${build_dir}/src/utils.cc"
    fi

    # Create a minimal stub implementation so the linker is satisfied
    cat > "${build_dir}/src/utils_curl_stub.cc" << 'STUB'
#include <cstdlib>
#include <cstring>
#include <cstdio>
typedef void CURL;
extern "C" {
    CURL *curl_easy_init(void) { return (void*)1; }
    char *curl_easy_escape(CURL *, const char *s, int) {
        char *o = (char*)malloc(strlen(s)*3+1); char *d = o;
        for (const char *p = s; *p; ++p) {
            if ((*p>='A'&&*p<='Z')||(*p>='a'&&*p<='z')||(*p>='0'&&*p<='9')
                ||*p=='-'||*p=='_'||*p=='.'||*p=='~') *d++=*p;
            else { sprintf(d,"%%%02X",(unsigned char)*p); d+=3; }
        }
        *d=0; return o;
    }
    void curl_easy_cleanup(CURL *) {}
}
STUB

    # Inject stub into CMakeLists so it gets compiled in
    sed -i '/utils\.cc/a\    utils_curl_stub.cc' "${build_dir}/src/CMakeLists.txt" 2>/dev/null || true

    local cmake_bin
    cmake_bin=$(command -v cmake3 || command -v cmake)
    mkdir -p "${build_dir}/build"
    info "Configuring kcov..."
    if ! "${cmake_bin}" "${build_dir}" \
            -B "${build_dir}/build" \
            -DCMAKE_INSTALL_PREFIX="${prefix}" \
            -DCMAKE_BUILD_TYPE=Release \
            -DSPECIFY_RPATH=OFF \
            >/dev/null 2>&1; then
        warn "kcov cmake configuration failed"
        rm -rf "${build_dir}"
        return 1
    fi

    info "Building kcov (this may take a few minutes)..."
    local cpus
    cpus=$(nproc 2>/dev/null || echo 2)
    if ! make -C "${build_dir}/build" -j"${cpus}" kcov >/dev/null 2>&1; then
        warn "kcov build failed"
        rm -rf "${build_dir}"
        return 1
    fi

    make -C "${build_dir}/build" install >/dev/null 2>&1
    rm -rf "${build_dir}"

    if command -v kcov &>/dev/null || [[ -x "${prefix}/bin/kcov" ]]; then
        export PATH="${prefix}/bin:${PATH}"
        info "✓ kcov built and installed from source"
        return 0
    fi
    return 1
}

install_kcov() {
    info "Installing kcov..."

    # Already present?
    if command -v kcov &>/dev/null; then
        info "kcov is already installed: $(kcov --version 2>&1 | head -1)"
        return 0
    fi

    local prefix
    if [[ $INSTALL_USER -eq 0 ]]; then
        prefix="/usr/local"
    else
        prefix="$HOME/.local"
    fi

    # 1. Package manager
    if [[ $INSTALL_USER -eq 0 ]]; then
        if command -v apt-get &>/dev/null; then
            info "Attempting apt-get install kcov..."
            sudo apt-get update -qq && sudo apt-get install -y -qq kcov && return 0
        elif command -v yum &>/dev/null; then
            info "Attempting yum install kcov..."
            sudo yum install -y kcov && return 0
        fi
    fi

    # 2. Build from source
    info "Package manager install not available; building from source..."
    _install_cmake_portable "${prefix}" || true
    if ! _build_kcov_from_source "${prefix}"; then
        warn "kcov build from source failed. Shell coverage will be unavailable."
        warn "To install manually: https://github.com/SimonKagstrom/kcov"
        return 1
    fi

    # Verify
    if command -v kcov &>/dev/null || [[ -x "${prefix}/bin/kcov" ]]; then
        info "✓ kcov installed successfully: $(kcov --version 2>&1 | head -1)"
        return 0
    fi
    error "Failed to install kcov"
    return 1
    fi
}

################################################################################
# Install shellspec
################################################################################
install_shellspec() {
    info "Installing shellspec..."
    
    # Check if shellspec is already installed
    if command -v shellspec &> /dev/null; then
        SHELLSPEC_VERSION=$(shellspec --version 2>&1 | head -1 || echo "unknown")
        info "shellspec is already installed: $SHELLSPEC_VERSION"
        return 0
    fi
    
    # Determine installation directory
    if [[ $INSTALL_USER -eq 1 ]]; then
        INSTALL_DIR="$HOME/.local"
    else
        INSTALL_DIR="/usr/local"
    fi
    
    # Download and install shellspec
    info "Installing shellspec to $INSTALL_DIR..."
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Clone shellspec repository
    git clone --depth 1 https://github.com/shellspec/shellspec.git
    cd shellspec
    
    # Install (non-interactive with --yes flag)
    if [[ $INSTALL_USER -eq 1 ]]; then
        ./install.sh --yes --prefix "$INSTALL_DIR"
        
        # Add to PATH if not already there
        if [[ ":$PATH:" != *":$INSTALL_DIR/bin:"* ]]; then
            warn "Please add $INSTALL_DIR/bin to your PATH:"
            warn "  echo 'export PATH=\"$INSTALL_DIR/bin:\$PATH\"' >> ~/.bashrc"
        fi
    else
        sudo ./install.sh --yes --prefix "$INSTALL_DIR"
    fi
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
    
    # Verify installation
    if command -v shellspec &> /dev/null; then
        info "✓ shellspec installed successfully: $(shellspec --version 2>&1 | head -1)"
        return 0
    else
        error "Failed to install shellspec"
        return 1
    fi
}

################################################################################
# Install shellcheck
################################################################################
install_shellcheck() {
    info "Installing shellcheck (optional)..."
    
    # Check if shellcheck is already installed
    if command -v shellcheck &> /dev/null; then
        SHELLCHECK_VERSION=$(shellcheck --version | grep "^version:" || echo "unknown")
        info "shellcheck is already installed: $SHELLCHECK_VERSION"
        return 0
    fi
    
    # Try package manager
    if command -v apt-get &> /dev/null; then
        info "Attempting to install shellcheck via apt-get..."
        if [[ $INSTALL_USER -eq 0 ]]; then
            sudo apt-get install -y shellcheck || warn "Failed to install shellcheck via apt"
        fi
    elif command -v yum &> /dev/null; then
        info "Attempting to install shellcheck via yum..."
        if [[ $INSTALL_USER -eq 0 ]]; then
            sudo yum install -y shellcheck || warn "Failed to install shellcheck via yum"
        fi
    fi
    
    # Verify installation
    if command -v shellcheck &> /dev/null; then
        info "✓ shellcheck installed successfully: $(shellcheck --version | grep "^version:")"
        return 0
    else
        warn "shellcheck not installed (optional)"
        return 1
    fi
}

################################################################################
# Main
################################################################################
main() {
    info "========================================="
    info "Shell Test Tools Installation"
    info "========================================="
    
    if [[ $INSTALL_USER -eq 1 ]]; then
        info "Installation mode: USER (~/.local)"
    else
        info "Installation mode: SYSTEM (/usr/local)"
    fi
    
    echo ""
    
    # Install tools
    KCOV_OK=0
    SHELLSPEC_OK=0
    SHELLCHECK_OK=0
    
    install_kcov && KCOV_OK=1
    echo ""
    
    install_shellspec && SHELLSPEC_OK=1
    echo ""
    
    install_shellcheck && SHELLCHECK_OK=1
    echo ""
    
    # Summary
    info "========================================="
    info "Installation Summary"
    info "========================================="
    
    if [[ $KCOV_OK -eq 1 ]]; then
        info "✓ kcov:      INSTALLED"
    else
        error "✗ kcov:      FAILED"
    fi
    
    if [[ $SHELLSPEC_OK -eq 1 ]]; then
        info "✓ shellspec: INSTALLED"
    else
        error "✗ shellspec: FAILED"
    fi
    
    if [[ $SHELLCHECK_OK -eq 1 ]]; then
        info "✓ shellcheck: INSTALLED"
    else
        warn "✗ shellcheck: NOT INSTALLED (optional)"
    fi
    
    echo ""
    
    if [[ $KCOV_OK -eq 1 && $SHELLSPEC_OK -eq 1 ]]; then
        info "✓ Shell testing tools are ready!"
        info "  Run: ./test.py --shell"
        return 0
    else
        error "Some required tools failed to install"
        error "Please install manually and try again"
        return 1
    fi
}

main "$@"

