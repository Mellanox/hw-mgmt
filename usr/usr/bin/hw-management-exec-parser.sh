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
# Parse per-platform hw-management-exec.json and install BusyBox-style helpers:
#   /usr/bin/hw-management-exec                - dispatcher (not under /var/run; noexec-safe)
#   /var/run/hw-management/exec.d/<name>     - symlink -> hw-management-exec
#   /var/run/hw-management/exec.d/<name>.env - variables and action body
#
# Config (first match wins):
#   1. /etc/<HID>/hw-management-exec.json - per-platform override
#   2. /etc/hw-management-exec/*.json - shared file whose "hids" array contains <HID>
################################################################################

EXEC_DISPATCHER="/usr/bin/hw-management-exec"
EXEC_LINK_DIR="/var/run/hw-management/exec.d"
LOG_TAG="hw-management-exec-parser"

log_info()
{
	if command -v logger >/dev/null 2>&1; then
		logger -t "$LOG_TAG" -p daemon.info "$@"
	fi
}

log_err()
{
	if command -v logger >/dev/null 2>&1; then
		logger -t "$LOG_TAG" -p daemon.err "$@"
	fi
}

# shellcheck source=/dev/null
source_hw_json_parser()
{
	if [ -f /usr/bin/hw-management-json-parser.sh ]; then
		# shellcheck source=/dev/null
		. /usr/bin/hw-management-json-parser.sh
		return 0
	fi
	return 1
}

get_system_hid()
{
	if [ -n "${HID:-}" ]; then
		echo "$HID"
		return 0
	fi
	if [ -f /var/run/hw-management/config/hid ]; then
		cat /var/run/hw-management/config/hid
		return 0
	fi
	if [ -f /sys/devices/virtual/dmi/id/product_sku ]; then
		cat /sys/devices/virtual/dmi/id/product_sku
		return 0
	fi
	echo ""
}

config_lists_hid()
{
	local hid="$1"
	local config="$2"
	awk -v hid="$hid" '
	BEGIN { in_hids = 0; found = 0 }
	$0 ~ "\"hids\"" && index($0, "[") > 0 { in_hids = 1 }
	in_hids && index($0, "\"" hid "\"") > 0 { found = 1 }
	in_hids && index($0, "]") > 0 { in_hids = 0 }
	END { exit found ? 0 : 1 }
	' "$config"
}

find_exec_config()
{
	local hid="$1"
	local f d
	for f in "/etc/${hid}/hw-management-exec.json" "/usr/etc/${hid}/hw-management-exec.json"; do
		if [ -f "$f" ]; then
			echo "$f"
			return 0
		fi
	done
	for d in /etc/hw-management-exec /usr/etc/hw-management-exec; do
		[ -d "$d" ] || continue
		for f in "$d"/*.json; do
			[ -f "$f" ] || continue
			if config_lists_hid "$hid" "$f"; then
				echo "$f"
				return 0
			fi
		done
	done
	return 1
}

json_get_attr_name()
{
	local block="$1"
	local name
	name=$(printf '%s\n' "$block" | json_get_string "AttributeName")
	if [ -n "$name" ]; then
		echo "$name"
		return 0
	fi
	printf '%s\n' "$block" | json_get_string "attribute_name"
}

sanitize_attr_name()
{
	printf '%s' "$1" | tr -cd 'a-zA-Z0-9_-'
}

sanitize_i2c_hex_value()
{
	local v
	v=$(printf '%s' "$1" | tr -cd '0-9a-fA-Fx')
	[ -n "$v" ] || return 1
	printf '%s' "$v"
}

sanitize_bus_number()
{
	local v
	v=$(printf '%s' "$1" | tr -cd '0-9')
	[ -n "$v" ] || return 1
	printf '%s' "$v"
}

sanitize_comment_text()
{
	printf '%s' "$1" | tr -cd 'a-zA-Z0-9 _.,/-'
}

install_exec_dispatcher()
{
	if [ ! -x "$EXEC_DISPATCHER" ]; then
		log_err "dispatcher missing or not executable: ${EXEC_DISPATCHER}"
		return 1
	fi
	return 0
}

create_exec_attribute()
{
	local attr_json="$1"
	local default_bus="$2"
	local attr_name safe_name bus address offset size mask retry action description
	local frag_path link_path
	attr_name=$(json_get_attr_name "$attr_json")
	safe_name=$(sanitize_attr_name "$attr_name")
	if [ -z "$safe_name" ]; then
		log_err "skip entry: missing or invalid AttributeName"
		return 1
	fi

	address=$(printf '%s\n' "$attr_json" | json_get_string "address")
	offset=$(printf '%s\n' "$attr_json" | json_get_string "offset")
	size=$(printf '%s\n' "$attr_json" | json_get_number "size")
	mask=$(printf '%s\n' "$attr_json" | json_get_string "mask")
	[ -z "$mask" ] && mask=$(printf '%s\n' "$attr_json" | json_get_string "Mask")

	bus=$(printf '%s\n' "$attr_json" | json_get_number "bus")
	if [ -z "$bus" ] && [ -n "$default_bus" ]; then
		if [ -n "$address" ] || [ -n "$offset" ] || [ -n "$mask" ]; then
			bus="$default_bus"
		fi
	fi
	if [ -n "$bus" ]; then
		bus=$(sanitize_bus_number "$bus") || bus=""
		if [ -z "$bus" ]; then
			log_err "skip ${safe_name}: invalid bus"
			return 1
		fi
	fi
	retry=$(printf '%s\n' "$attr_json" | json_get_number "retry")
	action=$(printf '%s\n' "$attr_json" | json_get_escaped_string "action")
	description=$(printf '%s\n' "$attr_json" | json_get_escaped_string "description")

	if [ -n "$address" ]; then
		address=$(sanitize_i2c_hex_value "$address") || address=""
		if [ -z "$address" ]; then
			log_err "skip ${safe_name}: invalid address"
			return 1
		fi
	fi
	if [ -n "$offset" ]; then
		offset=$(sanitize_i2c_hex_value "$offset") || offset=""
		if [ -z "$offset" ]; then
			log_err "skip ${safe_name}: invalid offset"
			return 1
		fi
	fi
	if [ -n "$mask" ]; then
		mask=$(sanitize_i2c_hex_value "$mask") || mask=""
		if [ -z "$mask" ]; then
			log_err "skip ${safe_name}: invalid mask"
			return 1
		fi
	fi
	if [ -n "$size" ]; then
		size=$(sanitize_bus_number "$size") || size=""
		if [ -z "$size" ]; then
			log_err "skip ${safe_name}: invalid size"
			return 1
		fi
	fi
	if [ -n "$retry" ]; then
		retry=$(sanitize_bus_number "$retry") || retry=""
		if [ -z "$retry" ]; then
			log_err "skip ${safe_name}: invalid retry"
			return 1
		fi
	fi
	if [ -n "$description" ]; then
		description=$(sanitize_comment_text "$description")
	fi

	if [ -z "$action" ]; then
		log_err "skip ${safe_name}: missing action"
		return 1
	fi

	frag_path="${EXEC_LINK_DIR}/${safe_name}.env"
	link_path="${EXEC_LINK_DIR}/${safe_name}"
	{
		printf '%s\n' "# Attribute: ${safe_name}"
		if [ -n "$description" ]; then
			printf '%s\n' "# ${description}"
		fi
		[ -n "$bus" ] && printf 'bus=%s\n' "$bus"
		[ -n "$address" ] && printf 'address=%s\n' "$address"
		[ -n "$offset" ] && printf 'offset=%s\n' "$offset"
		[ -n "$size" ] && printf 'size=%s\n' "$size"
		[ -n "$mask" ] && printf 'mask=%s\n' "$mask"
		[ -n "$retry" ] && printf 'retry=%s\n' "$retry"
		printf '%s\n' "$action"
	} > "$frag_path"
	ln -sf "$EXEC_DISPATCHER" "$link_path"
	log_info "created exec attribute ${safe_name}"
	return 0
}

cleanup_exec_tree()
{
	# Legacy: dispatcher was copied here; /var/run is often mounted noexec.
	rm -f /var/run/hw-management/exec
	rm -f "${EXEC_LINK_DIR}/"*.env
	find "$EXEC_LINK_DIR" -maxdepth 1 -type l -delete 2>/dev/null
}

main()
{
	local hid config_file default_bus i attr_json created
	if ! source_hw_json_parser; then
		log_err "JSON parser not found, skip exec attributes"
		exit 0
	fi

	hid=$(get_system_hid)
	if [ -z "$hid" ] || [ "$hid" = "Unknown" ]; then
		exit 0
	fi

	if ! config_file=$(find_exec_config "$hid"); then
		exit 0
	fi

	if ! json_validate "$config_file"; then
		log_err "invalid JSON: $config_file"
		exit 0
	fi

	if [ ! -d /var/run/hw-management ]; then
		log_info "/var/run/hw-management missing, skip exec attributes"
		exit 0
	fi

	cleanup_exec_tree
	mkdir -p "$EXEC_LINK_DIR"
	if ! install_exec_dispatcher; then
		exit 0
	fi

	default_bus=$(json_get_number "bus" < "$config_file")
	if [ -n "$default_bus" ]; then
		default_bus=$(sanitize_bus_number "$default_bus") || default_bus=""
	fi

	created=0
	i=0
	while attr_json=$(json_get_nested_array_element "attributes" "$i" < "$config_file"); [ -n "$attr_json" ]; do
		if create_exec_attribute "$attr_json" "$default_bus"; then
			created=$((created + 1))
		fi
		i=$((i + 1))
	done

	if [ "$created" -eq 0 ]; then
		cleanup_exec_tree
		exit 0
	fi

	log_info "HID=${hid} config=${config_file} exec attributes=${created}"
}

main "$@"
