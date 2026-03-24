#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# BusyBox-Compatible JSON Parser Library
#
# This library provides JSON parsing functions using only AWK and standard
# BusyBox utilities (no jq or Python required).
#
# Upstream name in OpenBMC: switch_json_parser.sh (bmc-post-boot-cfg).
# Packaged as hw-management-bmc-json-parser.sh for SONiC BMC hw-management-bmc.
#
# Usage:
#   source /usr/bin/hw-management-bmc-json-parser.sh
################################################################################

# Function to extract a top-level object block from JSON array by index
# Usage: json_get_array_element <json_file> <index>
# Returns: The complete JSON object at the specified index
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
    }
    {
        # Check if line contains opening brace at top level
        has_open = index($0, "{")
        
        # Check depth BEFORE processing current line
        if (has_open > 0 && depth == 0 && in_block == 0) {
            # This is a top-level opening brace (array element start)
            block_count++
            if (block_count == idx) {
                in_block = 1
                brace_count = 0
            }
        }
        
        # Print line if in target block
        if (in_block) {
            print $0
        }
        
        # Update depth after processing
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c == "{") {
                depth++
                if (in_block) brace_count++
            }
            if (c == "}") {
                if (in_block) brace_count--
                depth--
            }
        }
        
        # Exit when we close the target block
        if (in_block && brace_count == 0 && depth == 0) {
            exit
        }
    }
    ' "$json_file"
}

# Function to extract a nested object from a JSON block by array name and index
# Usage: echo "$json_block" | json_get_nested_array_element <array_name> <index>
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
    }
    {
        # Check if entering target array
        has_array = index($0, "\"" array "\"")
        if (has_array > 0 && index($0, "[") > 0) {
            in_target_array = 1
            next
        }
        
        # Check if exiting array
        if (in_target_array && index($0, "]") > 0 && brace_count == 0) {
            in_target_array = 0
            if (in_element) exit
        }
        
        # Look for array elements (objects starting with {)
        has_open = index($0, "{")
        if (in_target_array && has_open > 0 && !in_element) {
            element_count++
            if (element_count == idx) {
                in_element = 1
                brace_count = 1
                print $0
                next
            }
        }
        
        # Print lines if in target element
        if (in_element && index($0, "{") == 0) {
            print $0
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") brace_count++
                if (c == "}") brace_count--
            }
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
# Note: Must find the value after the *requested* key. The old implementation
# printed the 4th quote-split field, which is always the first string in a
# one-line object (e.g. "chip"), so "direction" and "symlink" were wrong.
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
json_count_nested_array()
{
    local array_name="$1"
    
    awk -v arr="$array_name" '
    BEGIN { in_array = 0; count = 0 }
    $0 ~ "\"" arr "\".*\\[" { in_array = 1; next }
    in_array && /\]/ { in_array = 0 }
    in_array && index($0, "{") > 0 { count++ }
    END { print count }
    '
}

# Function to validate JSON file (basic check)
# Usage: json_validate <json_file>
# Returns: 0 if valid, 1 if invalid
json_validate()
{
    local json_file="$1"
    
    if [[ ! -f "$json_file" ]]; then
        return 1
    fi
    
    # Basic validation - check for matching braces and brackets
    local open_braces=$(grep -o '{' "$json_file" | wc -l)
    local close_braces=$(grep -o '}' "$json_file" | wc -l)
    local open_brackets=$(grep -o '\[' "$json_file" | wc -l)
    local close_brackets=$(grep -o '\]' "$json_file" | wc -l)
    
    if [[ $open_braces -ne $close_braces ]] || [[ $open_brackets -ne $close_brackets ]]; then
        return 1
    fi
    
    return 0
}

# Export functions for use in other scripts
export -f json_get_array_element
export -f json_get_nested_array_element
export -f json_get_string
export -f json_get_number
export -f json_get_bool
export -f json_get_array
export -f json_count_array_elements
export -f json_count_nested_array
export -f json_validate
