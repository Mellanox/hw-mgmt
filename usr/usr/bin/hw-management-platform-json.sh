#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Apply per-platform hw-management settings from
# /etc/hw-management-cfg/<HID>/platform.json
# (packaged under usr/etc/hw-management-cfg/<HID>/).
# Parsed with hw-management-json-parser.sh (jq).
################################################################################

PLATFORM_JSON_CFG_DIR="hw-management-cfg"
PLATFORM_JSON_FILENAME="platform.json"

platform_json_asic_pci_id=""
platform_json_dpu_pci_id=""
platform_json_dpu_pci_addr=()

PLATFORM_JSON_NUMERIC_VARS=(
	asic_control
	asic_chipup_retry
	asic_num
	cartridge_count
	chipup_delay_default
	chipup_log_size
	chipup_retry_count
	cpld_num
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

PLATFORM_JSON_BOARD_NUMERIC_KEYS=(
	clk_brd_num
	cpu_brd_bus_offset
	dpu_brd_bus_offset
	dpu_num
	pwr_brd_bus_offset
	pwr_brd_hotswap_num
	pwr_brd_num
	pwr_brd_pwr_conv_num
	pwr_brd_temp_sens_num
	swb_brd_bus_offset
	swb_brd_num
	swb_brd_pdb_bus_offset
	swb_brd_vr_num
)

PLATFORM_JSON_BOARD_STRING_KEYS=(
	dpu_board_type
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

	for f in "/etc/${PLATFORM_JSON_CFG_DIR}/${hid}/${PLATFORM_JSON_FILENAME}" \
		"/usr/etc/${PLATFORM_JSON_CFG_DIR}/${hid}/${PLATFORM_JSON_FILENAME}"; do
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

platform_json_valid_number()
{
	[[ "$1" =~ ^[0-9]+$ ]]
}

platform_json_valid_named_bus_name()
{
	[[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

platform_json_valid_i2c_addr()
{
	[[ "$1" =~ ^0x[0-9a-fA-F]{1,2}$ ]]
}

platform_json_valid_pci_id()
{
	[[ "$1" =~ ^[0-9a-fA-F]{4}(\|[0-9a-fA-F]{4})*$ ]]
}

platform_json_valid_pci_bdf()
{
	[[ "$1" =~ ^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$ ]]
}

platform_json_append_shell_array_ref()
{
	local table_name="$1"

	if platform_json_valid_shell_array_name "$table_name"; then
		if eval "[ \${#${table_name}[@]} -gt 0 ]" 2>/dev/null; then
			# shellcheck disable=SC1087,SC2086
			eval "connect_table+=(\"\${${table_name}[@]}\")"
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
			eval "named_busses+=(\"\${${table_name}[@]}\")"
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
	local conn_obj cpu_offset table_name nb_count j nb_name nb_bus add_come

	conn_obj=$(platform_json_extract_object "connection" "$json_file")
	[ -n "$conn_obj" ] || return 0

	table_name=$(printf '%s\n' "$conn_obj" | json_get_string "named_busses_table")
	nb_count=$(printf '%s\n' "$conn_obj" | json_count_nested_array "named_busses")
	[ -z "$nb_count" ] && nb_count=0
	if [ -n "$table_name" ] && [ "$nb_count" -gt 0 ]; then
		log_err "platform JSON: use named_busses_table or named_busses, not both"
		return 1
	fi

	# New platforms use devtree for I2C topology; JSON supplies extras only.
	if [ ! -e "$devtree_file" ]; then
		while read -r table_name; do
			[ -n "$table_name" ] || continue
			platform_json_append_shell_array_ref "$table_name" || return 1
		done < <(printf '%s\n' "$conn_obj" | json_get_array "base_tables")

		cpu_offset=$(printf '%s\n' "$conn_obj" | json_get_number "cpu_board_offset")
		if [ -n "$cpu_offset" ]; then
			if ! platform_json_valid_number "$cpu_offset"; then
				log_err "platform JSON: invalid cpu_board_offset '${cpu_offset}'"
				return 1
			fi
			add_cpu_board_to_connection_table "$cpu_offset" || return 1
		fi

		while read -r table_name; do
			[ -n "$table_name" ] || continue
			platform_json_append_dynamic_shell_array_ref "$table_name" || return 1
		done < <(printf '%s\n' "$conn_obj" | json_get_array "dynamic_tables")

		platform_json_apply_inline_base_connect "$conn_obj" || return 1
		platform_json_apply_inline_dynamic_connect "$conn_obj" || return 1
	fi

	table_name=$(printf '%s\n' "$conn_obj" | json_get_string "named_busses_table")
	if [ -n "$table_name" ]; then
		platform_json_append_named_busses_ref "$table_name" || return 1
	fi

	if [ "$nb_count" -gt 0 ]; then
		j=0
		while [ "$j" -lt "$nb_count" ]; do
			nb_name=$(printf '%s\n' "$conn_obj" | json_get_nested_array_element "named_busses" "$j" | json_get_string "name")
			nb_bus=$(printf '%s\n' "$conn_obj" | json_get_nested_array_element "named_busses" "$j" | json_get_number "bus")
			if [ -z "$nb_name" ] || [ -z "$nb_bus" ]; then
				log_err "platform JSON: incomplete named_busses entry"
				return 1
			fi
			if ! platform_json_valid_named_bus_name "$nb_name"; then
				log_err "platform JSON: invalid named_busses name '${nb_name}'"
				return 1
			fi
			if ! platform_json_valid_number "$nb_bus"; then
				log_err "platform JSON: invalid named_busses bus '${nb_bus}'"
				return 1
			fi
			named_busses+=("$nb_name" "$nb_bus")
			j=$((j + 1))
		done
	fi

	cpu_offset=$(printf '%s\n' "$conn_obj" | json_get_number "add_come_named_busses_offset")
	if [ -n "$cpu_offset" ]; then
		if ! platform_json_valid_number "$cpu_offset"; then
			log_err "platform JSON: invalid add_come_named_busses_offset '${cpu_offset}'"
			return 1
		fi
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
			if ! platform_json_valid_number "$val"; then
				log_err "platform JSON: non-numeric value for ${key}: '${val}'"
				return 1
			fi
			eval "$key=$val" || return 1
			if [ "$key" = "asic_num" ]; then
				platform_json_write_config_key "asic_num" "$val" || return 1
			fi
			if [ "$key" = "cartridge_count" ]; then
				platform_json_write_config_key "cartridge_counter" "$val" || return 1
			fi
			if [ "$key" = "cpld_num" ]; then
				platform_json_write_config_key "cpld_num" "$val" || return 1
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

platform_json_apply_board()
{
	local json_file="$1"
	local board_obj key val

	board_obj=$(platform_json_extract_object "board" "$json_file")
	[ -n "$board_obj" ] || return 0

	for key in "${PLATFORM_JSON_BOARD_NUMERIC_KEYS[@]}"; do
		val=$(printf '%s\n' "$board_obj" | json_get_number "$key")
		if [ -n "$val" ]; then
			if ! platform_json_valid_number "$val"; then
				log_err "platform JSON: non-numeric board.${key}: '${val}'"
				return 1
			fi
			platform_json_write_config_key "$key" "$val" || return 1
		fi
	done

	for key in "${PLATFORM_JSON_BOARD_STRING_KEYS[@]}"; do
		val=$(printf '%s\n' "$board_obj" | json_get_escaped_string "$key")
		if [ -n "$val" ]; then
			if ! platform_json_valid_named_bus_name "$val"; then
				log_err "platform JSON: invalid board.${key}: '${val}'"
				return 1
			fi
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
			if ! platform_json_valid_number "$bus"; then
				log_err "platform JSON: invalid psu${i}_i2c_bus '${bus}'"
				return 1
			fi
			eval "psu${i}_i2c_bus=$bus" || return 1
		fi
		if [ -n "$addr" ]; then
			if ! platform_json_valid_i2c_addr "$addr"; then
				log_err "platform JSON: invalid psu${i}_i2c_addr '${addr}'"
				return 1
			fi
			eval "psu${i}_i2c_addr=\"\$addr\"" || return 1
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
		if ! platform_json_valid_number "$line"; then
			log_err "platform JSON: invalid asic_i2c_buses entry '${line}'"
			return 1
		fi
		buses+=("$line")
	done < <(json_get_array "asic_i2c_buses" < "$json_file")

	if [ ${#buses[@]} -eq 0 ]; then
		log_err "platform JSON: asic_i2c_buses is empty; omit key to keep default"
		return 1
	fi

	asic_i2c_buses=("${buses[@]}")
}

platform_json_apply_pci()
{
	local json_file="$1"
	local pci_obj val line

	platform_json_asic_pci_id=""
	platform_json_dpu_pci_id=""
	platform_json_dpu_pci_addr=()

	pci_obj=$(platform_json_extract_object "pci" "$json_file")
	[ -n "$pci_obj" ] || return 0

	val=$(printf '%s\n' "$pci_obj" | json_get_string "asic_pci_id")
	if [ -n "$val" ]; then
		if ! platform_json_valid_pci_id "$val"; then
			log_err "platform JSON: invalid pci.asic_pci_id '${val}'"
			return 1
		fi
		platform_json_asic_pci_id=$val
	fi

	val=$(printf '%s\n' "$pci_obj" | json_get_string "dpu_pci_id")
	if [ -n "$val" ]; then
		if ! platform_json_valid_pci_id "$val"; then
			log_err "platform JSON: invalid pci.dpu_pci_id '${val}'"
			return 1
		fi
		platform_json_dpu_pci_id=$val
	fi

	while read -r line; do
		[ -n "$line" ] || continue
		if ! platform_json_valid_pci_bdf "$line"; then
			log_err "platform JSON: invalid pci.dpu_pci_addr entry '${line}'"
			return 1
		fi
		platform_json_dpu_pci_addr+=("$line")
	done < <(printf '%s\n' "$pci_obj" | json_get_array "dpu_pci_addr")

	if [ -n "$platform_json_dpu_pci_id" ] && \
	   [ ${#platform_json_dpu_pci_addr[@]} -eq 0 ]; then
		log_err "platform JSON: dpu_pci_id requires non-empty dpu_pci_addr"
		return 1
	fi
	if [ ${#platform_json_dpu_pci_addr[@]} -gt 0 ] && \
	   [ -z "$platform_json_dpu_pci_id" ]; then
		log_err "platform JSON: dpu_pci_addr requires dpu_pci_id"
		return 1
	fi
}

set_asic_pci_id_from_json()
{
	local asic_num i=0 asic_pci

	asic_pci_id=$platform_json_asic_pci_id

	if [ -f "$config_path/asic_num" ]; then
		asic_num=$(< "$config_path/asic_num")
	else
		asic_num=0
		while read -r asic_pci; do
			[ -n "$asic_pci" ] || continue
			asic_num=$((asic_num + 1))
		done < <(lspci -nn | grep -E "$asic_pci_id" | awk '{print $1}')
		echo "$asic_num" > "$config_path/asic_num"
	fi

	while read -r asic_pci; do
		[ -n "$asic_pci" ] || continue
		i=$((i + 1))
		if [ "$i" -gt "$asic_num" ]; then
			break
		fi
		echo "$asic_pci" > "$config_path/asic${i}_pci_bus_id"
	done < <(lspci -nn | grep -E "$asic_pci_id" | awk '{print $1}')
}

set_dpu_pci_id_from_json()
{
	local dpus total_dpu_num idx element dpu_detected_num=0

	dpu_pci_id=$platform_json_dpu_pci_id
	dpus=$(lspci -nn | grep -E "$dpu_pci_id" | awk '{print $1}')
	total_dpu_num=${#platform_json_dpu_pci_addr[@]}

	for ((idx=0; idx<total_dpu_num; idx++)); do
		element="${platform_json_dpu_pci_addr[$idx]}"
		if echo "$dpus" | grep -q -w "$element"; then
			echo "$element" > "$config_path/dpu$((idx+1))_pci_bus_id"
			dpu_detected_num=$((dpu_detected_num + 1))
		else
			echo "" > "$config_path/dpu$((idx+1))_pci_bus_id"
		fi
	done
	echo "$dpu_detected_num" > "$config_path/dpu_detected_num"
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
	# board section is applied in pre_devtr_init() before devtree init
	platform_json_apply_pci "$json_file" || return 1
	platform_json_apply_config_files "$json_file" || return 1
	platform_json_apply_psu_i2c_map "$json_file" || return 1
	platform_json_apply_asic_i2c_buses "$json_file" || return 1
	platform_json_apply_connection "$json_file" || return 1
	platform_json_apply_actions "$json_file" || return 1
	return 0
}
