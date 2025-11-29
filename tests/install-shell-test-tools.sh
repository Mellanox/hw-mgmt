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
################################################################################
install_kcov() {
    info "Installing kcov..."
    
    # Check if kcov is already installed
    if command -v kcov &> /dev/null; then
        KCOV_VERSION=$(kcov --version 2>&1 | head -1 || echo "unknown")
        info "kcov is already installed: $KCOV_VERSION"
        return 0
    fi
    
    # Try package manager first
    if command -v apt-get &> /dev/null; then
        info "Attempting to install kcov via apt-get..."
        if [[ $INSTALL_USER -eq 0 ]]; then
            sudo apt-get update && sudo apt-get install -y kcov
        else
            warn "Cannot install kcov via apt to user directory. Please install system-wide or manually."
            return 1
        fi
    elif command -v yum &> /dev/null; then
        info "Attempting to install kcov via yum..."
        if [[ $INSTALL_USER -eq 0 ]]; then
            sudo yum install -y kcov
        else
            warn "Cannot install kcov via yum to user directory. Please install system-wide or manually."
            return 1
        fi
    else
        warn "No supported package manager found. Please install kcov manually:"
        warn "  Ubuntu/Debian: sudo apt-get install kcov"
        warn "  RHEL/Fedora:   sudo yum install kcov"
        warn "  From source:   https://github.com/SimonKagstrom/kcov"
        return 1
    fi
    
    # Verify installation
    if command -v kcov &> /dev/null; then
        info "✓ kcov installed successfully: $(kcov --version 2>&1 | head -1)"
        return 0
    else
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

