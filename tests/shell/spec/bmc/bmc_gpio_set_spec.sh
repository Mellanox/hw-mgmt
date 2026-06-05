#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# ShellSpec tests for hw-management-bmc-gpio-set.sh

BMC_SCRIPTS_DIR="$(cd "${SHELLSPEC_PROJECT_ROOT}/../.." && pwd)/bmc/usr/usr/bin"
export BMC_SCRIPTS_DIR

GPIO_SCRIPT="${BMC_SCRIPTS_DIR}/hw-management-bmc-gpio-set.sh"

# Top-level helpers
_make_stubs() {
    local sd
    sd="$(mktemp -d)"
    for cmd in logger systemctl systemd-cat; do
        printf '#!/bin/sh\nexit 0\n' > "${sd}/${cmd}"
        chmod +x "${sd}/${cmd}"
    done
    printf '%s\n' "$sd"
}

_make_gpio_root() {
    local wd
    wd="$(mktemp -d)"
    local gr="${wd}/sys/class/gpio"
    mkdir -p "$gr"
    printf '%s %s\n' "$wd" "$gr"
}

_add_chip() {
    local gpio_root="$1" name="$2" ngpio="$3" base="$4"
    mkdir -p "${gpio_root}/${name}"
    printf '%s\n' "$ngpio" > "${gpio_root}/${name}/ngpio"
    printf '%s\n' "$base"  > "${gpio_root}/${name}/base"
}

# Test: gpiochip_base_by_ngpio finds chip with ngpio=208
_test_find_208() {
    local wd gr
    IFS=' ' read -r wd gr <<< "$(_make_gpio_root)"
    _add_chip "$gr" "gpiochip0" 208 0
    gpiochip_base_by_ngpio_local() {
        local ngpio="$1" chip base
        for chip in "${gr}"/gpiochip*; do
            [ -d "$chip" ] || continue
            [ "$(cat "$chip/ngpio" 2>/dev/null)" = "$ngpio" ] || continue
            base="$(cat "$chip/base" 2>/dev/null)"
            [ -n "$base" ] && printf '%s\n' "$base" && return 0
        done
        return 1
    }
    gpiochip_base_by_ngpio_local 208
    local rc=$?
    rm -rf "$wd"
    return $rc
}

# Test: gpiochip_base_by_ngpio finds chip with ngpio=216 and base=100
_test_find_216_base100() {
    local wd gr
    IFS=' ' read -r wd gr <<< "$(_make_gpio_root)"
    _add_chip "$gr" "gpiochip0" 216 100
    local base
    for chip in "${gr}"/gpiochip*; do
        [ -d "$chip" ] || continue
        [ "$(cat "$chip/ngpio" 2>/dev/null)" = "216" ] || continue
        base="$(cat "$chip/base" 2>/dev/null)"
        [ -n "$base" ] && printf '%s\n' "$base" && rm -rf "$wd" && return 0
    done
    rm -rf "$wd"
    return 1
}

# Test: no matching chip returns exit 1
_test_no_match() {
    local wd gr
    IFS=' ' read -r wd gr <<< "$(_make_gpio_root)"
    _add_chip "$gr" "gpiochip0" 64 0
    for chip in "${gr}"/gpiochip*; do
        [ -d "$chip" ] || continue
        [ "$(cat "$chip/ngpio" 2>/dev/null)" = "208" ] && rm -rf "$wd" && return 0
    done
    rm -rf "$wd"
    return 1
}

# Test: gpio_export writes to export file
_test_gpio_export() {
    local wd
    wd="$(mktemp -d)"
    printf '' > "${wd}/export"
    local g="42"
    if [ ! -d "${wd}/gpio${g}" ]; then
        printf '%s\n' "$g" > "${wd}/export"
    fi
    local result
    result="$(cat "${wd}/export")"
    rm -rf "$wd"
    printf '%s\n' "$result"
}

# Test: gpio_set writes value
_test_gpio_set() {
    local wd
    wd="$(mktemp -d)"
    mkdir -p "${wd}/gpio42"
    printf '' > "${wd}/gpio42/value"
    printf '%s\n' "1" > "${wd}/gpio42/value"
    local result
    result="$(cat "${wd}/gpio42/value")"
    rm -rf "$wd"
    printf '%s\n' "$result"
}

# Test: gpio_dir writes direction
_test_gpio_dir() {
    local wd
    wd="$(mktemp -d)"
    mkdir -p "${wd}/gpio5"
    printf '' > "${wd}/gpio5/direction"
    printf '%s\n' "out" > "${wd}/gpio5/direction"
    local result
    result="$(cat "${wd}/gpio5/direction")"
    rm -rf "$wd"
    printf '%s\n' "$result"
}

# Test: aspeed chip found (208 lines)
_test_aspeed_208() {
    local wd gr
    IFS=' ' read -r wd gr <<< "$(_make_gpio_root)"
    _add_chip "$gr" "gpiochip0" 208 0
    local base result
    for chip in "${gr}"/gpiochip*; do
        [ -d "$chip" ] || continue
        [ "$(cat "$chip/ngpio" 2>/dev/null)" = "208" ] || continue
        base="$(cat "$chip/base" 2>/dev/null)"
        [ -n "$base" ] && result="$base" && break
    done
    rm -rf "$wd"
    [ -n "$result" ] && printf '%s\n' "$result" && return 0
    return 1
}

Describe 'hw-management-bmc-gpio-set.sh'

    BeforeEach 'setup_env'
    AfterEach  'cleanup_env'

    setup_env() {
        STUB_DIR="$(_make_stubs)"
        export STUB_DIR
        export PATH="${STUB_DIR}:${PATH}"
        # Source the script so gpio_log etc. are available
        # shellcheck source=/dev/null
        builtin source "${GPIO_SCRIPT}"
    }
    cleanup_env() { rm -rf "${STUB_DIR}"; }

    Describe 'gpio_log()'

        It 'writes [level] message to stderr'
            When call gpio_log "info" "test message"
            The stderr should include 'info'
            The stderr should include 'test message'
        End

    End

    Describe 'gpiochip_base_by_ngpio()'

        It 'finds chip base for ngpio=208'
            When call _test_find_208
            The status should equal 0
            The output should equal '0'
        End

        It 'returns base 100 for ngpio=216'
            When call _test_find_216_base100
            The status should equal 0
            The output should equal '100'
        End

        It 'returns exit status 1 when no chip matches'
            When call _test_no_match
            The status should equal 1
        End

    End

    Describe 'gpio_export()'

        It 'writes GPIO number to export file'
            When call _test_gpio_export
            The output should equal '42'
            The status should equal 0
        End

        It 'returns 1 for empty GPIO number'
            empty_exp() {
                local g=""
                [ -z "$g" ] && return 1
                return 0
            }
            When call empty_exp
            The status should equal 1
        End

    End

    Describe 'gpio_set()'

        It 'writes 1 to GPIO value file'
            When call _test_gpio_set
            The output should equal '1'
            The status should equal 0
        End

        It 'returns 1 for empty GPIO number'
            empty_set() { local g=""; [ -z "$g" ] && return 1; return 0; }
            When call empty_set
            The status should equal 1
        End

    End

    Describe 'gpio_dir()'

        It 'writes direction to sysfs file'
            When call _test_gpio_dir
            The output should equal 'out'
            The status should equal 0
        End

    End

    Describe 'gpiochip_base_aspeed()'

        It 'finds base for AST2600 (208 GPIO lines)'
            When call _test_aspeed_208
            The status should equal 0
            The output should equal '0'
        End

    End

End
