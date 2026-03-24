#!/bin/bash
################################################################################
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

# Log a message to both console (stderr) and syslog
gpio_log()
{
    local level="$1"
    local msg="$2"
    echo "switch_gpio: [$level] $msg" >&2
    logger -t "switch_gpio" -p "daemon.$level" "$msg"
}

# Find GPIO chip base address by number of GPIO lines
# Returns: base address on stdout, return code 0 on success, 1 on failure
gpiochip_base_by_ngpio()
{
    local ngpio="$1"
    local chip base

    for chip in /sys/class/gpio/gpiochip*; do
        [ -d "$chip" ] || continue
        if [ "$(cat "$chip/ngpio" 2>/dev/null)" = "$ngpio" ]; then
            base=$(cat "$chip/base" 2>/dev/null)
            if [ -n "$base" ]; then
                echo "$base"
                return 0
            fi
        fi
    done

    gpio_log "err" "Failed to find gpiochip with ngpio=$ngpio"
    return 1
}

# Find Aspeed main GPIO chip base (handles different SoC variants)
# AST2600 has 208 lines, AST2700 has 216 lines
gpiochip_base_aspeed()
{
    local base

    # Try AST2600 first (208 lines)
    base=$(gpiochip_base_by_ngpio 208 2>/dev/null)
    if [ -n "$base" ]; then
        echo "$base"
        return 0
    fi

    # Try AST2700 (216 lines)
    base=$(gpiochip_base_by_ngpio 216 2>/dev/null)
    if [ -n "$base" ]; then
        echo "$base"
        return 0
    fi

    gpio_log "err" "Failed to find Aspeed GPIO chip (tried ngpio=208,216)"
    return 1
}

# Export a GPIO if not already exported
gpio_export()
{
    local g="$1"

    if [ -z "$g" ]; then
        gpio_log "warning" "gpio_export called with empty GPIO number"
        return 1
    fi

    if [ ! -d "/sys/class/gpio/gpio$g" ]; then
        if ! echo "$g" > /sys/class/gpio/export 2>/dev/null; then
            gpio_log "warning" "Failed to export GPIO $g"
            return 1
        fi
    fi
    return 0
}

# Set GPIO direction (in/out)
gpio_dir()
{
    local g="$1"
    local dir="$2"

    if [ -z "$g" ] || [ -z "$dir" ]; then
        gpio_log "warning" "gpio_dir called with invalid args: gpio=$g dir=$dir"
        return 1
    fi

    if ! echo "$dir" > "/sys/class/gpio/gpio$g/direction" 2>/dev/null; then
        gpio_log "warning" "Failed to set GPIO $g direction to $dir"
        return 1
    fi
    return 0
}

# Set GPIO value (0/1)
gpio_set()
{
    local g="$1"
    local val="$2"

    if [ -z "$g" ]; then
        gpio_log "warning" "gpio_set called with empty GPIO number"
        return 1
    fi

    if ! echo "$val" > "/sys/class/gpio/gpio$g/value" 2>/dev/null; then
        gpio_log "warning" "Failed to set GPIO $g value to $val"
        return 1
    fi
    return 0
}

# Get GPIO value
gpio_get()
{
    local g="$1"

    if [ -z "$g" ]; then
        gpio_log "warning" "gpio_get called with empty GPIO number"
        return 1
    fi

    cat "/sys/class/gpio/gpio$g/value" 2>/dev/null
}

# Default config (platform copies HI189 file to /etc via plat-specific-preps)
GPIO_PINS_CONFIG="${GPIO_PINS_CONFIG:-/etc/hw-management-bmc-gpio-pins.json}"

# Map logical chip id (JSON "chip") to Linux gpiochip base (stdout).
gpio_base_for_chip_id()
{
	local chip="$1"
	case "$chip" in
	aspeed)
		gpiochip_base_aspeed
		;;
	expander24)
		gpiochip_base_by_ngpio 24
		;;
	*)
		gpio_log "err" "Unknown chip id in GPIO config: $chip"
		return 1
		;;
	esac
}

# Initialize sysfs GPIOs from /etc/hw-management-bmc-gpio-pins.json (JSON).
# Expects hw-management-bmc-json-parser.sh; uses check_n_link, system_path, wait_platform_drv from caller (ready-common + helpers).
# Sets global BMC_STBY_READY when "bmc_stby_ready" is present in JSON.
bmc_init_sysfs_gpio()
{
	local ASPEED_BASE EXPANDER_BASE pin_count i pin_json chip off dir sym val base abs_gpio
	local bmc_stby_chip bmc_stby_off sb stby_gpio

	if [ ! -f "$GPIO_PINS_CONFIG" ]; then
		gpio_log "warning" "GPIO pins config missing: $GPIO_PINS_CONFIG (skip sysfs GPIO init)"
		return 0
	fi
	if [ ! -f /usr/bin/hw-management-bmc-json-parser.sh ]; then
		gpio_log "err" "hw-management-bmc-json-parser.sh not found; cannot parse $GPIO_PINS_CONFIG"
		return 1
	fi
	# shellcheck source=/dev/null
	source /usr/bin/hw-management-bmc-json-parser.sh

	if ! json_validate "$GPIO_PINS_CONFIG"; then
		gpio_log "err" "Invalid JSON: $GPIO_PINS_CONFIG"
		return 1
	fi

	ASPEED_BASE=$(gpiochip_base_aspeed 2>/dev/null || true)
	EXPANDER_BASE=$(gpiochip_base_by_ngpio 24 2>/dev/null || true)

	if [ -n "$ASPEED_BASE" ]; then
		echo "Aspeed GPIO base   : $ASPEED_BASE"
	else
		gpio_log "err" "Failed to detect Aspeed GPIO chip base (ngpio 208/216)"
	fi
	if [ -n "$EXPANDER_BASE" ]; then
		echo "Expander GPIO base : $EXPANDER_BASE"
	else
		gpio_log "err" "Failed to detect GPIO expander base (ngpio=24)"
	fi

	pin_count=$(cat "$GPIO_PINS_CONFIG" | json_count_nested_array "pins")
	i=0
	while [ "$i" -lt "$pin_count" ]; do
		pin_json=$(cat "$GPIO_PINS_CONFIG" | json_get_nested_array_element "pins" "$i")
		if [ -z "$pin_json" ]; then
			gpio_log "warning" "Empty pins[$i], skip"
			i=$((i + 1))
			continue
		fi
		chip=$(echo "$pin_json" | json_get_string "chip")
		off=$(echo "$pin_json" | json_get_number "offset")
		dir=$(echo "$pin_json" | json_get_string "direction")
		sym=$(echo "$pin_json" | json_get_string "symlink" 2>/dev/null) || sym=""
		val=$(echo "$pin_json" | json_get_number "value" 2>/dev/null) || val=""

		if [ -z "$chip" ] || [ -z "$off" ] || [ -z "$dir" ]; then
			gpio_log "warning" "pins[$i] missing chip/offset/direction, skip"
			i=$((i + 1))
			continue
		fi

		base=$(gpio_base_for_chip_id "$chip") || {
			i=$((i + 1))
			continue
		}
		abs_gpio=$((base + off))

		gpio_export "$abs_gpio" || true
		gpio_dir "$abs_gpio" "$dir" || true
		if [ "$dir" = "out" ] && [ -n "$val" ]; then
			gpio_set "$abs_gpio" "$val" || true
		fi

		i=$((i + 1))
	done

	# Standby-ready sysfs path for wait_bmc_standby_ready() in hw-management-bmc-ready.sh
	bmc_stby_chip=$(sed -n '/"bmc_stby_ready"/,/^[\t ]*}/p' "$GPIO_PINS_CONFIG" | sed -n 's/.*"chip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
	bmc_stby_off=$(sed -n '/"bmc_stby_ready"/,/^[\t ]*}/p' "$GPIO_PINS_CONFIG" | sed -n 's/.*"offset"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
	if [ -n "$bmc_stby_chip" ] && [ -n "$bmc_stby_off" ]; then
		sb=$(gpio_base_for_chip_id "$bmc_stby_chip") || sb=""
		if [ -n "$sb" ]; then
			stby_gpio=$((sb + bmc_stby_off))
			BMC_STBY_READY=/sys/class/gpio/gpio${stby_gpio}/value
			gpio_get "$stby_gpio"
		fi
	fi

	if type wait_platform_drv >/dev/null 2>&1; then
		wait_platform_drv
	else
		gpio_log "warning" "wait_platform_drv not defined; skipping wait for system_path"
	fi

	if [ -z "${system_path:-}" ]; then
		gpio_log "warning" "system_path unset; skipping GPIO symlinks under /var/run/hw-management"
		echo "GPIO sysfs initialization complete (no symlinks)"
		return 0
	fi

	i=0
	while [ "$i" -lt "$pin_count" ]; do
		pin_json=$(cat "$GPIO_PINS_CONFIG" | json_get_nested_array_element "pins" "$i")
		chip=$(echo "$pin_json" | json_get_string "chip")
		off=$(echo "$pin_json" | json_get_number "offset")
		sym=$(echo "$pin_json" | json_get_string "symlink" 2>/dev/null) || sym=""
		if [ -n "$sym" ] && [ -n "$chip" ] && [ -n "$off" ]; then
			base=$(gpio_base_for_chip_id "$chip") || {
				i=$((i + 1))
				continue
			}
			abs_gpio=$((base + off))
			check_n_link "/sys/class/gpio/gpio${abs_gpio}/value" "${system_path}/${sym}"
		fi
		i=$((i + 1))
	done

	echo "GPIO sysfs initialization complete"
}
