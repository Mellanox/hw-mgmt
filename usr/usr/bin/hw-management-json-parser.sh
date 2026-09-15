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
# JSON Parser Library (host CPU)
#
# Uses jq (available on host CPU images). BMC-side scripts continue to use
# hw-management-bmc-json-parser.sh until jq is present there as well.
#
# Upstream name in OpenBMC: switch_json_parser.sh (bmc-post-boot-cfg).
# Packaged as hw-management-json-parser.sh for host hw-management.
#
# Usage:
#   source /usr/bin/hw-management-json-parser.sh
################################################################################

_json_parser_require_jq()
{
	if ! command -v jq >/dev/null 2>&1; then
		echo "hw-management-json-parser: jq is required but not installed" >&2
		return 1
	fi
}

# Function to extract a top-level object block from JSON array by index
# Usage: json_get_array_element <json_file> <index>
# Returns: The complete JSON object at the specified index
json_get_array_element()
{
	local json_file="$1"
	local index="$2"

	_json_parser_require_jq || return 1
	jq -c --argjson idx "$index" '.[$idx] // empty' "$json_file"
}

# Function to extract a nested object from a JSON block by array name and index
# Usage: echo "$json_block" | json_get_nested_array_element <array_name> <index>
# <index> is 0-based (first element is 0).
# Returns: The JSON object at the specified index within the named array
json_get_nested_array_element()
{
	local array_name="$1"
	local index="$2"

	_json_parser_require_jq || return 1
	jq -c --arg a "$array_name" --argjson idx "$index" '.[$a][$idx] // empty'
}

# Function to extract a simple string value by key from JSON
# Usage: echo "$json" | json_get_string <key>
# Returns: The string value (without quotes)
json_get_string()
{
	local key="$1"

	_json_parser_require_jq || return 1
	jq -r --arg k "$key" '(.[$k] // empty) | if type == "string" then . else empty end'
}

# Function to extract a JSON string value with backslash escapes (multi-line safe)
# Usage: echo "$json" | json_get_escaped_string <key>
json_get_escaped_string()
{
	local key="$1"

	_json_parser_require_jq || return 1
	jq -r --arg k "$key" '(.[$k] // empty) | if type == "string" then . else empty end'
}

# Function to extract a numeric value by key from JSON
# Usage: echo "$json" | json_get_number <key>
# Returns: The numeric value (integer or decimal)
json_get_number()
{
	local key="$1"

	_json_parser_require_jq || return 1
	jq -r --arg k "$key" '
		(.[$k] // empty) |
		if type == "number" then tostring
		elif type == "string" and test("^-?[0-9]+(\\.[0-9]+)?$") then .
		else empty end
	'
}

# Function to extract a JSON boolean or string that looks like a boolean
# Usage: echo "$json" | json_get_bool <key>
# Prints: true, false, or a quoted string value; empty if absent/invalid.
# Returns: 2 when absent or invalid (matches legacy awk parser contract).
json_get_bool()
{
	local key="$1"
	local val

	_json_parser_require_jq || return 2
	val=$(jq -r --arg k "$key" '
		(.[$k] // empty) |
		if type == "boolean" then tostring
		elif type == "string" then .
		else empty end
	' 2>/dev/null) || return 2
	if [ -z "$val" ]; then
		return 2
	fi
	printf '%s\n' "$val"
}

# Function to extract array elements from a JSON array
# Usage: echo "$json" | json_get_array <array_name>
# Returns: Array elements, one per line
json_get_array()
{
	local array_name="$1"

	_json_parser_require_jq || return 1
	jq -r --arg a "$array_name" '
		(.[$a] // []) |
		if type != "array" then empty else .[] end |
		if type == "string" then .
		elif type == "number" then tostring
		elif type == "boolean" then tostring
		else empty end
	'
}

# Function to count top-level elements in a JSON array
# Usage: json_count_array_elements <json_file>
# Returns: Number of top-level elements
json_count_array_elements()
{
	local json_file="$1"

	_json_parser_require_jq || return 1
	jq -r 'if type == "array" then length else 0 end' "$json_file"
}

# Function to count elements in a named array within a JSON block
# Usage: echo "$json_block" | json_count_nested_array <array_name>
# Returns: Number of elements in the named array
json_count_nested_array()
{
	local array_name="$1"

	_json_parser_require_jq || return 1
	jq -r --arg a "$array_name" '
		(.[$a] // []) |
		if type == "array" then length else 0 end
	'
}

# Function to validate JSON file
# Usage: json_validate <json_file>
# Returns: 0 if valid, 1 if invalid
json_validate()
{
	local json_file="$1"

	_json_parser_require_jq || return 1
	[ -f "$json_file" ] || return 1
	jq empty "$json_file" >/dev/null 2>&1
}

# BusyBox ash has no export -f; load with ". /usr/bin/hw-management-json-parser.sh".
if [ -n "${BASH_VERSION:-}" ]; then
	export -f _json_parser_require_jq
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
