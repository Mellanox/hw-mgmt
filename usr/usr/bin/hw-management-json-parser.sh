#!/bin/sh
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
# BusyBox-Compatible JSON Parser Library
#
# This library provides JSON parsing functions using only AWK and standard
# BusyBox utilities (no jq or Python required).
#
# Upstream name in OpenBMC: switch_json_parser.sh (bmc-post-boot-cfg).
# Packaged as hw-management-json-parser.sh for host hw-management.
#
# Usage:
#   source /usr/bin/hw-management-json-parser.sh
################################################################################

# Function to extract a top-level object block from JSON array by index
# Usage: json_get_array_element <json_file> <index>
# Returns: The complete JSON object at the specified index
# Ignores "{" and "}" inside JSON string values (same rule as json_get_nested_array_element).
json_get_array_element()
{
    local json_file="$1"
    local index="$2"
    awk -v idx="$index" '
    BEGIN {
        block_count = -1
        in_block = 0
        brace_count = 0
        depth = 0
        in_string = 0
        escape = 0
    }

    function update_string_state(c) {
        if (in_string) {
            if (escape) {
                escape = 0
                return
            }
            if (c == "\\") {
                escape = 1
                return
            }
            if (c == "\"") {
                in_string = 0
            }
            return
        }
        if (c == "\"") {
            in_string = 1
        }
    }

    {
        line = $0
        for (i = 1; i <= length(line); i++) {
            c = substr(line, i, 1)
            if (in_string) {
                update_string_state(c)
                continue
            }
            if (c == "\"") {
                in_string = 1
                continue
            }
            if (c == "{") {
                if (depth == 0 && !in_block) {
                    block_count++
                    if (block_count == idx) {
                        in_block = 1
                        brace_count = 0
                    }
                }
                if (in_block) {
                    brace_count++
                }
                depth++
            } else if (c == "}") {
                if (in_block) {
                    brace_count--
                }
                depth--
            }
        }
        if (in_block) {
            print $0
        }
        if (in_block && brace_count == 0 && depth == 0) {
            exit
        }
    }
    ' "$json_file"
}

# Function to extract a nested object from a JSON block by array name and index
# Usage: echo "$json_block" | json_get_nested_array_element <array_name> <index>
# <index> is 0-based (first element is 0). Matches callers: early-i2c-init, devtree, gpio-set, a2d-leakage.
# A new array element is recognized only when "{" appears at brace depth 0 inside the named array
# (nested objects like "config": { ... } do not start a new element). Lines inside the element are
# printed in full and brace-balanced so nested "{" lines are not dropped.
# Returns: The JSON object at the specified index within the named array
json_get_nested_array_element()
{
    local array_name="$1"
    local index="$2"
    awk -v array="$array_name" -v idx="$index" '
    BEGIN {
        in_target_array = 0
        element_count = -1
        in_element = 0
        brace_count = 0
        depth = 0
        in_string = 0
        escape = 0
    }

    function update_string_state(c) {
        if (in_string) {
            if (escape) {
                escape = 0
                return
            }
            if (c == "\\") {
                escape = 1
                return
            }
            if (c == "\"") {
                in_string = 0
            }
            return
        }
        if (c == "\"") {
            in_string = 1
        }
    }

    function count_element_braces(line, from,    i, c) {
        for (i = from; i <= length(line); i++) {
            c = substr(line, i, 1)
            update_string_state(c)
            if (in_string) {
                continue
            }
            if (c == "{") {
                brace_count++
            } else if (c == "}") {
                brace_count--
            }
        }
    }

    function scan_array_depth(line,    i, c) {
        for (i = 1; i <= length(line); i++) {
            c = substr(line, i, 1)
            update_string_state(c)
            if (in_string) {
                continue
            }
            if (c == "{") {
                if (depth == 0) {
                    element_count++
                    if (element_count == idx) {
                        in_element = 1
                        print substr(line, i)
                        brace_count = 0
                        count_element_braces(line, i)
                        if (brace_count == 0) {
                            exit
                        }
                        depth++
                        return
                    }
                }
                depth++
            } else if (c == "}") {
                depth--
            }
        }
    }

    {
        has_array = index($0, "\"" array "\"")
        if (has_array > 0 && index($0, "[") > 0) {
            in_target_array = 1
            next
        }

        if (in_target_array && !in_element && !in_string && depth == 0 && index($0, "]") > 0) {
            in_target_array = 0
            next
        }

        if (in_target_array && !in_element) {
            scan_array_depth($0)
            next
        }

        if (in_element) {
            print $0
            count_element_braces($0, 1)
            if (brace_count == 0) {
                exit
            }
        }
    }
    '
}

# Function to extract a simple string value by key from JSON
# Usage: echo "$json" | json_get_string <key>
# Returns: The string value (without quotes)
# Use only for tokens without embedded quotes (hex address, AttributeName, etc.).
# For "action", "description", or any value that may contain \" use
# json_get_escaped_string instead.
json_get_string()
{
    local key="$1"
    awk -v k="$key" '
    {
        p = "\"" k "\""
        i = index($0, p)
        if (i == 0) next
        j = i + length(p)
        while (j <= length($0) && substr($0, j, 1) ~ /[[:space:]]/) j++
        if (substr($0, j, 1) != ":") next
        j++
        while (j <= length($0) && substr($0, j, 1) ~ /[[:space:]]/) j++
        if (substr($0, j, 1) != "\"") next
        j++
        start = j
        while (j <= length($0) && substr($0, j, 1) != "\"") j++
        if (j > start) print substr($0, start, j - start)
        exit
    }'
}

# Function to extract a JSON string value with backslash escapes (multi-line safe)
# Usage: echo "$json" | json_get_escaped_string <key>
json_get_escaped_string()
{
	local key="$1"
	awk -v k="$key" '
	BEGIN { buf = "" }
	{ buf = buf $0 }
	END {
		p = "\"" k "\""
		i = index(buf, p)
		if (i == 0) exit
		j = i + length(p)
		while (j <= length(buf) && substr(buf, j, 1) ~ /[[:space:]]/) j++
		if (substr(buf, j, 1) != ":") exit
		j++
		while (j <= length(buf) && substr(buf, j, 1) ~ /[[:space:]]/) j++
		if (substr(buf, j, 1) != "\"") exit
		j++
		out = ""
		while (j <= length(buf)) {
			c = substr(buf, j, 1)
			if (c == "\\" && j < length(buf)) {
				n = substr(buf, j + 1, 1)
				if (n == "n") { out = out "\n"; j += 2; continue }
				if (n == "t") { out = out "\t"; j += 2; continue }
				if (n == "r") { out = out "\r"; j += 2; continue }
				out = out n
				j += 2
				continue
			}
			if (c == "\"") break
			out = out c
			j++
		}
		print out
	}'
}

# Function to extract a numeric value by key from JSON
# Usage: echo "$json" | json_get_number <key>
# Returns: The numeric value (integer or decimal). Reads full stdin (multi-line safe).
# Note: The old implementation split on : , and took the *first* integer field on
# any line containing the key — wrong when another number (e.g. NumChnl, Scale)
# appeared before "Bus" on the same logical object.
json_get_number()
{
	local key="$1"
	awk -v k="$key" '
	BEGIN { buf = "" }
	{ buf = buf $0 }
	END {
		p = "\"" k "\""
		i = index(buf, p)
		if (i == 0) exit
		j = i + length(p)
		while (j <= length(buf) && substr(buf, j, 1) ~ /[[:space:]]/) j++
		if (substr(buf, j, 1) != ":") exit
		j++
		while (j <= length(buf) && substr(buf, j, 1) ~ /[[:space:]]/) j++
		if (j > length(buf)) exit
		start = j
		if (substr(buf, j, 1) == "-") j++
		while (j <= length(buf) && substr(buf, j, 1) ~ /[0-9]/) j++
		if (substr(buf, j, 1) == ".") {
			j++
			while (j <= length(buf) && substr(buf, j, 1) ~ /[0-9]/) j++
		}
		if (j > start) print substr(buf, start, j - start)
	}'
}

# Function to extract a JSON boolean or string that looks like a boolean
# Usage: echo "$json" | json_get_bool <key>
# Prints: true, false, or a quoted string value (e.g. true from "true"); empty if absent/invalid.
# RFC 8259 booleans are lowercase true/false without quotes — json_get_string cannot read those.
json_get_bool()
{
	local key="$1"
	awk -v k="$key" '
	BEGIN { buf = "" }
	{ buf = buf $0 }
	END {
		p = "\"" k "\""
		i = index(buf, p)
		if (i == 0) exit 2
		j = i + length(p)
		while (j <= length(buf) && substr(buf, j, 1) ~ /[[:space:]]/) j++
		if (substr(buf, j, 1) != ":") exit 2
		j++
		while (j <= length(buf) && substr(buf, j, 1) ~ /[[:space:]]/) j++
		if (j > length(buf)) exit 2
		rest = substr(buf, j)
		if (match(rest, /^true([^a-zA-Z0-9_]|$)/)) { print "true"; exit 0 }
		if (match(rest, /^false([^a-zA-Z0-9_]|$)/)) { print "false"; exit 0 }
		if (substr(buf, j, 1) == "\"") {
			j++
			start = j
			while (j <= length(buf) && substr(buf, j, 1) != "\"") j++
			if (j > start) {
				print substr(buf, start, j - start)
				exit 0
			}
		}
		exit 2
	}'
}

# Function to extract array elements (strings) from a JSON array
# Usage: echo "$json" | json_get_array <array_name>
# Returns: Array elements, one per line
json_get_array()
{
    local array_name="$1"
    awk -v arr="$array_name" '
    BEGIN { in_array = 0 }
    $0 ~ "\"" arr "\".*\\[" { in_array = 1; next }
    in_array && /\]/ { exit }
    in_array && /"/ {
        gsub(/^[ \t]*"/, "")
        gsub(/"[ \t,]*$/, "")
        print
    }
    '
}

# Function to count top-level elements in a JSON array
# Usage: json_count_array_elements <json_file>
# Returns: Number of top-level elements
# Note: Do not use grep on lines starting with "{" — nested Device objects also start
# lines with "{" and would inflate the count (e.g. 6 instead of 2).
json_count_array_elements()
{
	local json_file="$1"
	local idx=0
	local block
	while block=$(json_get_array_element "$json_file" "$idx"); [ -n "$block" ]; do
		idx=$((idx + 1))
	done
	echo "$idx"
}

# Function to count elements in a named array within a JSON block
# Usage: echo "$json_block" | json_count_nested_array <array_name>
# Returns: Number of elements in the named array
# Counts only top-level "{" openings at brace depth 0 inside the array (same rule as
# json_get_nested_array_element). Ignores "{" inside JSON string values.
json_count_nested_array()
{
    local array_name="$1"
    awk -v array="$array_name" '
    BEGIN {
        in_target_array = 0
        count = 0
        depth = 0
        in_string = 0
        escape = 0
    }
    {
        has_array = index($0, "\"" array "\"")
        if (has_array > 0 && index($0, "[") > 0) {
            in_target_array = 1
            next
        }

        if (in_target_array && !in_string && depth == 0 && index($0, "]") > 0) {
            in_target_array = 0
            next
        }

        if (!in_target_array) {
            next
        }

        line = $0
        for (i = 1; i <= length(line); i++) {
            c = substr(line, i, 1)
            if (in_string) {
                if (escape) {
                    escape = 0
                    continue
                }
                if (c == "\\") {
                    escape = 1
                    continue
                }
                if (c == "\"") {
                    in_string = 0
                }
                continue
            }
            if (c == "\"") {
                in_string = 1
                continue
            }
            if (c == "{") {
                if (depth == 0) {
                    count++
                }
                depth++
            } else if (c == "}") {
                depth--
            }
        }
    }
    END { print count }
    '
}

# Function to validate JSON file (basic check)
# Usage: json_validate <json_file>
# Returns: 0 if valid, 1 if invalid
json_validate()
{
    local json_file="$1"
    if [ ! -f "$json_file" ]; then
        return 1
    fi

    # Brace/bracket balance outside JSON string values (grep would count { inside strings).
    awk '
    BEGIN { depth_brace = 0; depth_bracket = 0; in_string = 0; escape = 0; ok = 1 }
    {
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (in_string) {
                if (escape) {
                    escape = 0
                    continue
                }
                if (c == "\\") {
                    escape = 1
                    continue
                }
                if (c == "\"") {
                    in_string = 0
                }
                continue
            }
            if (c == "\"") {
                in_string = 1
                continue
            }
            if (c == "{") {
                depth_brace++
            } else if (c == "}") {
                depth_brace--
                if (depth_brace < 0) {
                    ok = 0
                }
            } else if (c == "[") {
                depth_bracket++
            } else if (c == "]") {
                depth_bracket--
                if (depth_bracket < 0) {
                    ok = 0
                }
            }
        }
    }
    END {
        if (depth_brace != 0 || depth_bracket != 0) {
            ok = 0
        }
        exit ok ? 0 : 1
    }
    ' "$json_file"
}

# BusyBox ash has no export -f; load with ". /usr/bin/hw-management-json-parser.sh".
if [ -n "${BASH_VERSION:-}" ]; then
	export -f json_get_array_element
	export -f json_get_nested_array_element
	export -f json_get_string
	export -f json_get_escaped_string
	export -f json_get_number
	export -f json_get_bool
	export -f json_get_array
	export -f json_count_array_elements
	export -f json_count_nested_array
	export -f json_validate
fi
