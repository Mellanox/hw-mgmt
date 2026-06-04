#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Apply per-platform hw-management settings from /etc/<HID>/hw-management-platform.json
# (packaged under usr/etc/<HID>/). Parsed with hw-management-json-parser.sh.
################################################################################

PLATFORM_JSON_FILENAME="hw-management-platform.json"

PLATFORM_JSON_NUMERIC_VARS=(
	asic_control
	asic_chipup_retry
	cartridge_count
	chipup_delay_default
	chipup_log_size
	chipup_retry_count
	device_connect_retry
	dpu_count
	dummy_psus_supported
	erot_count
	fan_speed_tolerance
	health_events_count
	hotplug_fans
	hotplug_linecards
	hotplug_pdbs
	hotplug_psus
	hotplug_pwrs
	i2c_bus_def_off_eeprom_cpu
	i2c_comex_mon_bus_default
	leakage_count
	leakage_rope_count
	max_tachos
	mcu_count
	minimal_unsupported
	psu_count
	pwr_events_count
	vrot_count
)

PLATFORM_JSON_STRING_VARS=(
	lm_sensors_config
	lm_sensors_config_lc
	lm_sensors_labels
	mctp_addr
	mctp_bus
	thermal_control_config
)

PLATFORM_JSON_CONFIG_KEYS=(
	asic_control
	core1_temp_id
	cpld_num
	cpld_port
	cx_default_i2c_bus
	default_i2c_freq
	fan_dir_eeprom
	fan_drwr_num
	fan_front_max_speed
	fan_front_min_speed
	fan_inversed
	fan_max_speed
	fan_min_speed
	fan_rear_max_speed
	fan_rear_min_speed
	fixed_fans_system
	global_wp_timeout
	global_wp_wait_step
	jtag_bridge_offset
	jtag_ro_reg
	jtag_rw_reg
	max_tachos
	psu_eeprom_type
	psu_fan_max
	psu_fan_min
	reset_attr_num
	system_flow_capability
)

PLATFORM_JSON_ACTIONS=(
	get_i2c_bus_frequency_default
)

PLATFORM_JSON_SYSTEM_KEYS=(
	bmc
	cooling
	fan_replaceable
	power_source
	power_supply
	power_supply_replaceable
	security
	ssd
	tpm
	type
)

source_hw_platform_json_parser()
{
	if [ -f /usr/bin/hw-management-json-parser.sh ]; then
		# shellcheck source=/dev/null
		. /usr/bin/hw-management-json-parser.sh
		return 0
	fi
	return 1
}

find_platform_json_config()
{
	local hid="$1"
	local f

	[ -n "$hid" ] || return 1
	[ "$hid" != "Unknown" ] || return 1
	case "$hid" in
	HI[0-9]*) ;;
	*) return 1 ;;
	esac

	for f in "/etc/${hid}/${PLATFORM_JSON_FILENAME}" \
		"/usr/etc/${hid}/${PLATFORM_JSON_FILENAME}"; do
		if [ -f "$f" ]; then
			echo "$f"
			return 0
		fi
	done
	return 1
}

# Extract a top-level JSON object by key from a file (multi-line safe).
# Matches only keys at brace depth 1 (root object), not string values.
platform_json_extract_object()
{
	local key="$1"
	local json_file="$2"
	awk -v k="$key" '
	BEGIN {
		buf = ""
		in_string = 0
		escape = 0
		depth = 0
	}
	{ buf = buf $0 "\n" }
	END {
		i = 1
		n = length(buf)
		while (i <= n) {
			c = substr(buf, i, 1)
			if (in_string) {
				if (escape) {
					escape = 0
				} else if (c == "\\") {
					escape = 1
				} else if (c == "\"") {
					in_string = 0
				}
				i++
				continue
			}
			if (c == "\"") {
				key_start = i + 1
				i++
				while (i <= n) {
					c = substr(buf, i, 1)
					if (c == "\\") {
						i += 2
						continue
					}
					if (c == "\"") {
						break
					}
					i++
				}
				if (i > n) {
					exit
				}
				key_name = substr(buf, key_start, i - key_start)
				i++
				while (i <= n && substr(buf, i, 1) ~ /[[:space:]]/) {
					i++
				}
				if (depth == 1 && key_name == k && substr(buf, i, 1) == ":") {
					i++
					while (i <= n && substr(buf, i, 1) ~ /[[:space:]]/) {
						i++
					}
					if (substr(buf, i, 1) == "{") {
						start = i
						obj_depth = 1
						in_obj_string = 0
						obj_escape = 0
						i++
						while (i <= n && obj_depth > 0) {
							c = substr(buf, i, 1)
							if (in_obj_string) {
								if (obj_escape) {
									obj_escape = 0
								} else if (c == "\\") {
									obj_escape = 1
								} else if (c == "\"") {
									in_obj_string = 0
								}
								i++
								continue
							}
							if (c == "\"") {
								in_obj_string = 1
								i++
								continue
							}
							if (c == "{") {
								obj_depth++
							} else if (c == "}") {
								obj_depth--
							}
							i++
						}
						if (obj_depth == 0) {
							print substr(buf, start, i - start)
							exit
						}
					}
				}
				continue
			}
			if (c == "{") {
				depth++
			} else if (c == "}") {
				depth--
			}
			i++
		}
	}
	' "$json_file"
}

# Return 0 when a top-level JSON array key is present in the file.
platform_json_has_top_level_array()
{
	local key="$1"
	local json_file="$2"
	awk -v k="$key" '
	BEGIN { buf = ""; in_string = 0; escape = 0; depth = 0 }
	{ buf = buf $0 "\n" }
	END {
		i = 1
		n = length(buf)
		while (i <= n) {
			c = substr(buf, i, 1)
			if (in_string) {
				if (escape) {
					escape = 0
				} else if (c == "\\") {
					escape = 1
				} else if (c == "\"") {
					in_string = 0
				}
				i++
				continue
			}
			if (c == "\"") {
				key_start = i + 1
				i++
				while (i <= n) {
					c = substr(buf, i, 1)
					if (c == "\\") {
						i += 2
						continue
					}
					if (c == "\"") {
						break
					}
					i++
				}
				if (i > n) {
					exit 1
				}
				key_name = substr(buf, key_start, i - key_start)
				i++
				while (i <= n && substr(buf, i, 1) ~ /[[:space:]]/) {
					i++
				}
				if (depth == 1 && key_name == k && substr(buf, i, 1) == ":") {
					i++
					while (i <= n && substr(buf, i, 1) ~ /[[:space:]]/) {
						i++
					}
					if (substr(buf, i, 1) == "[") {
						exit 0
					}
				}
				continue
			}
			if (c == "{") {
				depth++
			} else if (c == "}") {
				depth--
			}
			i++
		}
		exit 1
	}
	' "$json_file"
}

platform_json_action_allowed()
{
	local name="$1"
	local key

	for key in "${PLATFORM_JSON_ACTIONS[@]}"; do
		[ "$key" = "$name" ] && return 0
	done
	return 1
}

platform_json_valid_shell_array_name()
{
	[[ "$1" =~ ^[a-z][a-z0-9_]+$ ]]
}

platform_json_write_config_key()
{
	local key="$1"
	local val="$2"

	if ! echo "$val" > "$config_path/$key"; then
		log_err "platform JSON: failed to write config/${key}"
		return 1
	fi
}

platform_json_append_shell_array_ref()
{
	local table_name="$1"

	if platform_json_valid_shell_array_name "$table_name"; then
		if eval "[ \${#${table_name}[@]} -gt 0 ]" 2>/dev/null; then
			# shellcheck disable=SC1087,SC2086
			connect_table+=($(eval "echo \${${table_name}[@]}"))
			return 0
		fi
	fi
	log_err "platform JSON: unknown or empty connect table '${table_name}'"
	return 1
}

platform_json_append_named_busses_ref()
{
	local table_name="$1"

	if platform_json_valid_shell_array_name "$table_name"; then
		if eval "[ \${#${table_name}[@]} -gt 0 ]" 2>/dev/null; then
			# shellcheck disable=SC1087,SC2086
			named_busses+=($(eval "echo \${${table_name}[@]}"))
			return 0
		fi
	fi
	log_err "platform JSON: unknown or empty named busses table '${table_name}'"
	return 1
}

platform_json_append_dynamic_shell_array_ref()
{
	local table_name="$1"

	if platform_json_valid_shell_array_name "$table_name"; then
		if eval "[ \${#${table_name}[@]} -gt 0 ]" 2>/dev/null; then
			# shellcheck disable=SC1087,SC2086
			eval "add_i2c_dynamic_bus_dev_connection_table \"\${${table_name}[@]}\"" || return 1
			return 0
		fi
	fi
	log_err "platform JSON: unknown or empty dynamic connect table '${table_name}'"
	return 1
}

platform_json_apply_inline_base_connect()
{
	local conn_obj="$1"
	local i block chip addr bus

	i=0
	while block=$(printf '%s\n' "$conn_obj" | json_get_nested_array_element "base_connect" "$i"); [ -n "$block" ]; do
		chip=$(printf '%s\n' "$block" | json_get_string "chip")
		addr=$(printf '%s\n' "$block" | json_get_string "addr")
		bus=$(printf '%s\n' "$block" | json_get_number "bus")
		if [ -n "$chip" ] && [ -n "$addr" ] && [ -n "$bus" ]; then
			connect_table+=("$chip" "$addr" "$bus")
		else
			log_err "platform JSON: incomplete base_connect entry"
			return 1
		fi
		i=$((i + 1))
	done
}

platform_json_apply_inline_dynamic_connect()
{
	local conn_obj="$1"
	local i block chip addr bus name

	i=0
	while block=$(printf '%s\n' "$conn_obj" | json_get_nested_array_element "dynamic_connect" "$i"); [ -n "$block" ]; do
		chip=$(printf '%s\n' "$block" | json_get_string "chip")
		addr=$(printf '%s\n' "$block" | json_get_string "addr")
		bus=$(printf '%s\n' "$block" | json_get_number "bus")
		name=$(printf '%s\n' "$block" | json_get_string "name")
		if [ -n "$chip" ] && [ -n "$addr" ] && [ -n "$bus" ] && [ -n "$name" ]; then
			add_i2c_dynamic_bus_dev_connection_table "$chip" "$addr" "$bus" "$name" || return 1
		else
			log_err "platform JSON: incomplete dynamic_connect entry"
			return 1
		fi
		i=$((i + 1))
	done
}

platform_json_apply_connection()
{
	local json_file="$1"
	local conn_obj skip_devtree cpu_offset table_name i nb_count j nb_name nb_bus add_come

	conn_obj=$(platform_json_extract_object "connection" "$json_file")
	[ -n "$conn_obj" ] || return 0

	skip_devtree=$(printf '%s\n' "$conn_obj" | json_get_bool "skip_if_devtree_exists")
	if [ "$skip_devtree" = "true" ] && [ -e "$devtree_file" ]; then
		return 0
	fi

	while read -r table_name; do
		[ -n "$table_name" ] || continue
		platform_json_append_shell_array_ref "$table_name" || return 1
	done < <(printf '%s\n' "$conn_obj" | json_get_array "base_tables")

	cpu_offset=$(printf '%s\n' "$conn_obj" | json_get_number "cpu_board_offset")
	if [ -n "$cpu_offset" ]; then
		add_cpu_board_to_connection_table "$cpu_offset" || return 1
	fi

	while read -r table_name; do
		[ -n "$table_name" ] || continue
		platform_json_append_dynamic_shell_array_ref "$table_name" || return 1
	done < <(printf '%s\n' "$conn_obj" | json_get_array "dynamic_tables")

	platform_json_apply_inline_base_connect "$conn_obj" || return 1
	platform_json_apply_inline_dynamic_connect "$conn_obj" || return 1

	table_name=$(printf '%s\n' "$conn_obj" | json_get_string "named_busses_table")
	if [ -n "$table_name" ]; then
		platform_json_append_named_busses_ref "$table_name" || return 1
	fi

	nb_count=$(printf '%s\n' "$conn_obj" | json_count_nested_array "named_busses")
	if [ -n "$nb_count" ] && [ "$nb_count" -gt 0 ]; then
		j=0
		while [ "$j" -lt "$nb_count" ]; do
			nb_name=$(printf '%s\n' "$conn_obj" | json_get_nested_array_element "named_busses" "$j" | json_get_string "name")
			nb_bus=$(printf '%s\n' "$conn_obj" | json_get_nested_array_element "named_busses" "$j" | json_get_number "bus")
			if [ -n "$nb_name" ] && [ -n "$nb_bus" ]; then
				named_busses+=("$nb_name" "$nb_bus")
			fi
			j=$((j + 1))
		done
	fi

	cpu_offset=$(printf '%s\n' "$conn_obj" | json_get_number "add_come_named_busses_offset")
	if [ -n "$cpu_offset" ]; then
		add_come_named_busses "$cpu_offset" || return 1
	else
		add_come=$(printf '%s\n' "$conn_obj" | json_get_bool "add_come_named_busses")
		if [ "$add_come" = "true" ]; then
			add_come_named_busses || return 1
		fi
	fi

	if [ ${#named_busses[@]} -gt 0 ]; then
		if ! echo -n "${named_busses[@]}" > "$config_path/named_busses"; then
			log_err "platform JSON: failed to write config/named_busses"
			return 1
		fi
	fi
}

platform_json_validate_system_value()
{
	local key="$1"
	local val="$2"

	case "$key" in
	bmc)
		case "$val" in
		yes|no) return 0 ;;
		esac
		;;
	cooling)
		case "$val" in
		liquid|air|hybrid) return 0 ;;
		esac
		;;
	power_supply)
		case "$val" in
		AC|DC) return 0 ;;
		esac
		;;
	power_source)
		case "$val" in
		busbar|replaceable_unit) return 0 ;;
		esac
		;;
	power_supply_replaceable|fan_replaceable|tpm)
		case "$val" in
		yes|no|na) return 0 ;;
		esac
		;;
	ssd)
		case "$val" in
		sata|nvme) return 0 ;;
		esac
		;;
	security)
		case "$val" in
		PQC) return 0 ;;
		esac
		;;
	type)
		case "$val" in
		Ethernet|IB|NvLink) return 0 ;;
		esac
		;;
	esac
	log_err "platform JSON: invalid system.${key} value '${val}'"
	return 1
}

platform_json_apply_system()
{
	local json_file="$1"
	local sys_obj key val

	sys_obj=$(platform_json_extract_object "system" "$json_file")
	[ -n "$sys_obj" ] || return 0

	for key in "${PLATFORM_JSON_SYSTEM_KEYS[@]}"; do
		val=$(printf '%s\n' "$sys_obj" | json_get_string "$key")
		[ -n "$val" ] || continue
		platform_json_validate_system_value "$key" "$val" || return 1
		platform_json_write_config_key "$key" "$val" || return 1
	done
}

platform_json_apply_variables()
{
	local json_file="$1"
	local var_obj key val

	var_obj=$(platform_json_extract_object "variables" "$json_file")
	[ -n "$var_obj" ] || return 0

	for key in "${PLATFORM_JSON_NUMERIC_VARS[@]}"; do
		val=$(printf '%s\n' "$var_obj" | json_get_number "$key")
		if [ -n "$val" ]; then
			eval "$key=$val" || return 1
			if [ "$key" = "cartridge_count" ]; then
				platform_json_write_config_key "cartridge_counter" "$val" || return 1
			fi
		fi
	done

	for key in "${PLATFORM_JSON_STRING_VARS[@]}"; do
		val=$(printf '%s\n' "$var_obj" | json_get_escaped_string "$key")
		if [ -n "$val" ]; then
			eval "$key=\"\$val\"" || return 1
		fi
	done
}

platform_json_apply_config_files()
{
	local json_file="$1"
	local cfg_obj key val

	cfg_obj=$(platform_json_extract_object "config" "$json_file")
	[ -n "$cfg_obj" ] || return 0

	for key in "${PLATFORM_JSON_CONFIG_KEYS[@]}"; do
		val=$(printf '%s\n' "$cfg_obj" | json_get_escaped_string "$key")
		if [ -z "$val" ]; then
			val=$(printf '%s\n' "$cfg_obj" | json_get_number "$key")
		fi
		if [ -n "$val" ]; then
			platform_json_write_config_key "$key" "$val" || return 1
		fi
	done
}

platform_json_apply_psu_i2c_map()
{
	local json_file="$1"
	local psu_obj i bus addr

	psu_obj=$(platform_json_extract_object "psu_i2c" "$json_file")
	[ -n "$psu_obj" ] || return 0

	for i in 1 2 3 4 5 6 7 8; do
		bus=$(printf '%s\n' "$psu_obj" | json_get_number "psu${i}_i2c_bus")
		addr=$(printf '%s\n' "$psu_obj" | json_get_string "psu${i}_i2c_addr")
		if [ -n "$bus" ]; then
			case "$bus" in
			*[!0-9]*)
				log_err "platform JSON: invalid psu${i}_i2c_bus '${bus}'"
				return 1
				;;
			esac
			eval "psu${i}_i2c_bus=$bus" || return 1
		fi
		if [ -n "$addr" ]; then
			case "$addr" in
			0x[0-9a-fA-F]*)
				eval "psu${i}_i2c_addr=\"\$addr\"" || return 1
				;;
			*)
				log_err "platform JSON: invalid psu${i}_i2c_addr '${addr}'"
				return 1
				;;
			esac
		fi
	done
}

platform_json_apply_asic_i2c_buses()
{
	local json_file="$1"
	local buses=()

	platform_json_has_top_level_array "asic_i2c_buses" "$json_file" || return 0

	while read -r line; do
		[ -n "$line" ] || continue
		buses+=("$line")
	done < <(json_get_array "asic_i2c_buses" < "$json_file")

	if [ ${#buses[@]} -eq 0 ]; then
		log_err "platform JSON: asic_i2c_buses is empty; omit key to keep default"
		return 1
	fi

	asic_i2c_buses=("${buses[@]}")
}

platform_json_apply_actions()
{
	local json_file="$1"
	local action

	while read -r action; do
		[ -n "$action" ] || continue
		if ! platform_json_action_allowed "$action"; then
			log_err "platform JSON: unsupported action '${action}'"
			return 1
		fi
		if ! "$action"; then
			log_err "platform JSON: action '${action}' failed"
			return 1
		fi
	done < <(json_get_array "actions" < "$json_file")
}

platform_json_apply_config()
{
	local json_file="$1"

	if ! source_hw_platform_json_parser; then
		log_err "platform JSON parser not found, cannot apply ${json_file}"
		return 1
	fi

	if ! json_validate "$json_file"; then
		log_err "platform JSON invalid: ${json_file}"
		return 1
	fi

	platform_json_apply_system "$json_file" || return 1
	platform_json_apply_variables "$json_file" || return 1
	platform_json_apply_config_files "$json_file" || return 1
	platform_json_apply_psu_i2c_map "$json_file" || return 1
	platform_json_apply_asic_i2c_buses "$json_file" || return 1
	platform_json_apply_connection "$json_file" || return 1
	platform_json_apply_actions "$json_file" || return 1
	return 0
}
