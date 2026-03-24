#!/bin/bash
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
