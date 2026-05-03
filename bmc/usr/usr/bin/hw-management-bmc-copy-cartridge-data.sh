#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
#
# hw-mgmt-bmc-copy-cartridge-data.sh
#
# Reads cartridge identity from the leftmost cartridge FRU (EEPROM over I2C by
# default), then programs the switch-board CPLD so the switch ASIC side sees
# rack id, topology id, switch tray id, and slot index in the expected register
# bank. Rack id byte count comes from JSON CartridgeRackIdSize (default 13 when
# missing or invalid); EEPROM read, CPLD write length, and readback all use it.
#
# Configuration is optional. If /etc/hw-mgmt-bmc-copy-cartridge-data.json is
# absent, hw_mgmt_bmc_copy_cartridge_data() returns immediately (no error).
# Override the path at runtime with HW_MGMT_BMC_CARTRIDGE_CFG if needed.
#
# JSON fields mirror the former shell constants; see the packaged
# hw-mgmt-bmc-copy-cartridge-data.json for names and example values.
# PhysicalAccess: "I2C" runs the EEPROM path below; "USB" reserves UsbPort for
# a future implementation once hardware exposes cartridge data over USB.
#
# Intended use: source this file from bmc_ready (or similar) and call
#   hw_mgmt_bmc_copy_cartridge_data
# When the JSON config file is present, /usr/bin/switch_json_parser.sh must exist
# on the image (same requirement as other hw-mgmt BMC JSON consumers).

HW_MGMT_BMC_CARTRIDGE_CFG="${HW_MGMT_BMC_CARTRIDGE_CFG:-/etc/hw-mgmt-bmc-copy-cartridge-data.json}"

# Normalize JSON string numbers: trim whitespace; accept 0xNN or plain decimal.
_cartridge_json_to_int()
{
	local v="$1"
	v="${v#"${v%%[![:space:]]*}"}"
	v="${v%"${v##*[![:space:]]}"}"
	if [[ -z "$v" ]]; then
		echo 0
		return
	fi
	if [[ "$v" =~ ^0[xX] ]]; then
		echo $((v))
	else
		echo $((10#0${v}))
	fi
}

# Populate globals from JSON using BusyBox-friendly parsers in switch_json_parser.sh.
_cartridge_load_cfg()
{
	local cfg="$1"

	if [ ! -f "$cfg" ]; then
		return 1
	fi

	if [ ! -f /usr/bin/switch_json_parser.sh ]; then
		echo "Cartridge config: /usr/bin/switch_json_parser.sh not found (json_get_string/json_get_number unavailable)" >&2
		return 1
	fi
	# shellcheck source=/dev/null
	source /usr/bin/switch_json_parser.sh

	PHYSICAL_ACCESS=$(json_get_string PhysicalAccess < "$cfg")
	PHYSICAL_ACCESS=$(echo "$PHYSICAL_ACCESS" | tr '[:lower:]' '[:upper:]')
	USB_PORT=$(json_get_string UsbPort < "$cfg")

	# Static EEPROM layout hints (some reserved for topology-specific paths).
	CARTRIDGE_BLOC_REV_OFFSET=$(_cartridge_json_to_int "$(json_get_string CartridgeBlocRevOffset < "$cfg")")
	CARTRIDGE_SLOT_INDEX_OFFSET=$(_cartridge_json_to_int "$(json_get_string CartridgeSlotIndexOffset < "$cfg")")
	CARTRIDGE_SWITCH_TRAY_ID_OFFSET=$(_cartridge_json_to_int "$(json_get_string CartridgeSwitchTrayIdOffset < "$cfg")")
	CARTRIDGE_TOPOLOGY_ID_OFFSET=$(_cartridge_json_to_int "$(json_get_string CartridgeTopologyIdOffset < "$cfg")")
	CARTRIDGE_TOPOLOGY_ID_18_1RU_VAL=$(_cartridge_json_to_int "$(json_get_string CartridgeTopologyId18_1ruVal < "$cfg")")
	CARTRIDGE_TOPOLOGY_ID_9_2RU_VAL=$(_cartridge_json_to_int "$(json_get_string CartridgeTopologyId9_2ruVal < "$cfg")")
	CARTRIDGE_RACK_ID_18_1RU_OFFSET=$(_cartridge_json_to_int "$(json_get_string CartridgeRackId18_1ruOffset < "$cfg")")
	CARTRIDGE_RACK_ID_9_2RU_OFFSET=$(_cartridge_json_to_int "$(json_get_string CartridgeRackId9_2ruOffset < "$cfg")")
	CARTRIDGE_RACK_ID_SIZE=$(json_get_number CartridgeRackIdSize < "$cfg")
	CARTRIDGE_RACK_ID_SIZE="${CARTRIDGE_RACK_ID_SIZE//[[:space:]]/}"
	if [[ ! "$CARTRIDGE_RACK_ID_SIZE" =~ ^[0-9]+$ ]] || ((CARTRIDGE_RACK_ID_SIZE < 1 || CARTRIDGE_RACK_ID_SIZE > 64)); then
		CARTRIDGE_RACK_ID_SIZE=13
	else
		CARTRIDGE_RACK_ID_SIZE=$((10#0$CARTRIDGE_RACK_ID_SIZE))
	fi
	CARTRIDGE_1_I2C_BUS=$(json_get_number Cartridge1I2cBus < "$cfg")
	CARTRIDGE_2_I2C_BUS=$(json_get_number Cartridge2I2cBus < "$cfg")
	CARTRIDGE_I2C_ADDRESS=$(_cartridge_json_to_int "$(json_get_string CartridgeI2cAddress < "$cfg")")

	# Which cartridge supplies data and which CPLD LSB window to use (cartridge 1 vs 2).
	local pbus plsb
	pbus=$(json_get_number PrimaryCartridgeI2cBus < "$cfg")
	[ -n "$pbus" ] || pbus=$CARTRIDGE_1_I2C_BUS
	PRIMARY_CARTRIDGE_I2C_BUS=$pbus
	plsb=$(json_get_string PrimaryCartridgeSwbLsbOffset < "$cfg")
	[ -n "$plsb" ] || plsb=$(json_get_string SwbCartridge1LsbOffset < "$cfg")
	PRIMARY_CARTRIDGE_SWB_LSB_OFFSET=$(_cartridge_json_to_int "$plsb")

	# Switch-board CPLD: MSB bank + per-cartridge LSB offsets within that bank.
	SWB_CARTRIDGE_MSB_OFFSET=$(_cartridge_json_to_int "$(json_get_string SwbCartridgeMsbOffset < "$cfg")")
	SWB_CARTRIDGE_1_LSB_OFFSET=$(_cartridge_json_to_int "$(json_get_string SwbCartridge1LsbOffset < "$cfg")")
	SWB_CARTRIDGE_2_LSB_OFFSET=$(_cartridge_json_to_int "$(json_get_string SwbCartridge2LsbOffset < "$cfg")")
	SWB_CARTRIDGE_RACK_ID_OFFSET=$(_cartridge_json_to_int "$(json_get_string SwbCartridgeRackIdOffset < "$cfg")")
	SWB_TOPOLOGY_ID_OFFSET=$(_cartridge_json_to_int "$(json_get_string SwbTopologyIdOffset < "$cfg")")
	SWB_SWITCH_TRAY_ID_OFFSET=$(_cartridge_json_to_int "$(json_get_string SwbSwitchTrayIdOffset < "$cfg")")
	SWB_SLOT_INDEX_OFFSET=$(_cartridge_json_to_int "$(json_get_string SwbSlotIndexOffset < "$cfg")")
	SWB_I2C_BUS=$(json_get_number SwbI2cBus < "$cfg")
	SWB_I2C_ADDRESS=$(_cartridge_json_to_int "$(json_get_string SwbI2cAddress < "$cfg")")

	return 0
}

# Walk FRU board area to locate the start of the board serial number (rack id source; width from CartridgeRackIdSize).
# Args: cartridge I2C bus. Requires CARTRIDGE_I2C_ADDRESS. Sets CARTRIDGE_SN_OFFSET on success.
# Return: 0 on success, 1 on I2C/parse failure (CARTRIDGE_SN_OFFSET must not be used).
find_cartridge_sn_offset()
{
	local cartridge_bus="$1"
	local pn_len_off=3
	local pn_name_mask=0x3f
	local shift=2
	local pn_len pn_off pn_name_off pn_start sn_off

	if [[ -z "$cartridge_bus" ]]; then
		echo "find_cartridge_sn_offset: missing I2C bus" >&2
		return 1
	fi
	if ! pn_len=$(i2ctransfer -f -y "$cartridge_bus" w1@"$CARTRIDGE_I2C_ADDRESS" $pn_len_off r1); then
		echo "find_cartridge_sn_offset: PN length i2ctransfer failed (bus=$cartridge_bus)" >&2
		return 1
	fi
	if [[ -z "$pn_len" ]]; then
		echo "find_cartridge_sn_offset: empty PN length read" >&2
		return 1
	fi
	pn_off=$((pn_len * 8))
	pn_off=$((pn_off + 13))
	if ! pn_name_off=$(i2ctransfer -f -y "$cartridge_bus" w1@"$CARTRIDGE_I2C_ADDRESS" $pn_off r1); then
		echo "find_cartridge_sn_offset: PN name offset i2ctransfer failed (bus=$cartridge_bus off=$pn_off)" >&2
		return 1
	fi
	if [[ -z "$pn_name_off" ]]; then
		echo "find_cartridge_sn_offset: empty PN name offset read" >&2
		return 1
	fi
	pn_start=$((pn_name_off & pn_name_mask))
	sn_off=$((pn_off + pn_start + shift))
	CARTRIDGE_SN_OFFSET=$sn_off
	return 0
}

# Parse FRU common header and chassis info area; print EEPROM byte offset of chassis custom info payload to stdout.
# Return: 0 on success, 1 on I2C/parse failure (no offset printed).
find_cartridge_chassis_custom_info_offset()
{
	local bus="$1"
	local addr="$2"
	local header chassis_offset_mult chassis_offset chassis_header offset
	local type_length length custom_type_length

	if [[ -z "$bus" || -z "$addr" ]]; then
		echo "find_cartridge_chassis_custom_info_offset: missing bus or address" >&2
		return 1
	fi
	if ! header=$(i2ctransfer -f -y "$bus" w1@"$addr" 0x00 r8); then
		echo "find_cartridge_chassis_custom_info_offset: FRU header i2ctransfer failed (bus=$bus)" >&2
		return 1
	fi
	if [[ -z "$header" ]]; then
		echo "find_cartridge_chassis_custom_info_offset: empty FRU header read" >&2
		return 1
	fi
	chassis_offset_mult=$(echo "$header" | awk '{print $3}')
	if [[ -z "$chassis_offset_mult" ]]; then
		echo "find_cartridge_chassis_custom_info_offset: could not parse chassis area offset from header" >&2
		return 1
	fi
	chassis_offset=$((chassis_offset_mult * 8))

	if ! chassis_header=$(i2ctransfer -f -y "$bus" w1@"$addr" $chassis_offset r3); then
		echo "find_cartridge_chassis_custom_info_offset: chassis header i2ctransfer failed (bus=$bus off=$chassis_offset)" >&2
		return 1
	fi
	if [[ -z "$chassis_header" ]]; then
		echo "find_cartridge_chassis_custom_info_offset: empty chassis header read" >&2
		return 1
	fi
	offset=$((chassis_offset + 3))

	# Skip chassis part number and chassis serial (type/length encoded fields).
	for _ in 1 2; do
		if ! type_length=$(i2ctransfer -f -y "$bus" w1@"$addr" $offset r1); then
			echo "find_cartridge_chassis_custom_info_offset: type/length read failed at offset $offset" >&2
			return 1
		fi
		if [[ -z "$type_length" ]]; then
			echo "find_cartridge_chassis_custom_info_offset: empty type/length at offset $offset" >&2
			return 1
		fi
		length=$((type_length & 0x3F))
		offset=$((offset + 1 + length))
	done

	if ! custom_type_length=$(i2ctransfer -f -y "$bus" w1@"$addr" $offset r1); then
		echo "find_cartridge_chassis_custom_info_offset: custom field type/length i2ctransfer failed at offset $offset" >&2
		return 1
	fi
	if [[ -z "$custom_type_length" ]]; then
		echo "find_cartridge_chassis_custom_info_offset: empty custom type/length at offset $offset" >&2
		return 1
	fi
	# Payload starts after the type/length byte; custom field length is (custom_type_length & 0x3F).
	offset=$((offset + 1))

	echo "$offset"
	return 0
}

# Read cartridge at bus $1 / CARTRIDGE_I2C_ADDRESS; write into CPLD at SWB_* using LSB base $2.
update_cartridge_data()
{
	local bus=$1
	local lsb=$2
	local rc offset custom_info_offset rack_id topology_id switch_tray_id slot_index regval
	local rack_sz pad_len wr_bytes reg_payload i rack_pad

	i2cget -f -y "$bus" "$CARTRIDGE_I2C_ADDRESS" > /dev/null 2>&1
	rc=$?
	if [[ $rc -ne 0 ]]; then
		echo "No cartridge EEPROM found at bus $bus address $CARTRIDGE_I2C_ADDRESS"
		return 1
	fi

	if ! find_cartridge_sn_offset "$bus"; then
		return 1
	fi
	offset=$CARTRIDGE_SN_OFFSET

	# GBCDB-style bytes in chassis custom info: slot index, tray id, topology follow custom header.
	if ! custom_info_offset=$(find_cartridge_chassis_custom_info_offset "$bus" "$CARTRIDGE_I2C_ADDRESS"); then
		return 1
	fi
	CARTRIDGE_SLOT_INDEX_OFFSET=$(($custom_info_offset + 2))
	CARTRIDGE_SWITCH_TRAY_ID_OFFSET=$(($custom_info_offset + 3))
	CARTRIDGE_TOPOLOGY_ID_OFFSET=$(($custom_info_offset + 4))

	rack_sz=$CARTRIDGE_RACK_ID_SIZE
	if [[ ! "$rack_sz" =~ ^[0-9]+$ ]] || ((rack_sz < 1 || rack_sz > 64)); then
		echo "Cartridge: invalid CARTRIDGE_RACK_ID_SIZE (${rack_sz:-empty}); reload JSON config" >&2
		return 1
	fi

	if ! rack_id=$(i2ctransfer -f -y "$bus" w1@"$CARTRIDGE_I2C_ADDRESS" $offset r"$rack_sz"); then
		echo "Cartridge: rack id i2ctransfer failed (bus=$bus off=$offset len=$rack_sz)" >&2
		return 1
	fi
	if [[ -z "$rack_id" ]]; then
		echo "Cartridge: empty rack id read (bus=$bus off=$offset)" >&2
		return 1
	fi
	if ! topology_id=$(i2ctransfer -f -y "$bus" w1@"$CARTRIDGE_I2C_ADDRESS" $CARTRIDGE_TOPOLOGY_ID_OFFSET r1); then
		echo "Cartridge: topology id i2ctransfer failed (bus=$bus off=$CARTRIDGE_TOPOLOGY_ID_OFFSET)" >&2
		return 1
	fi
	if [[ -z "$topology_id" ]]; then
		echo "Cartridge: empty topology id read" >&2
		return 1
	fi
	if ! switch_tray_id=$(i2ctransfer -f -y "$bus" w1@"$CARTRIDGE_I2C_ADDRESS" $CARTRIDGE_SWITCH_TRAY_ID_OFFSET r1); then
		echo "Cartridge: switch tray id i2ctransfer failed (bus=$bus off=$CARTRIDGE_SWITCH_TRAY_ID_OFFSET)" >&2
		return 1
	fi
	if [[ -z "$switch_tray_id" ]]; then
		echo "Cartridge: empty switch tray id read" >&2
		return 1
	fi
	if ! slot_index=$(i2ctransfer -f -y "$bus" w1@"$CARTRIDGE_I2C_ADDRESS" $CARTRIDGE_SLOT_INDEX_OFFSET r1); then
		echo "Cartridge: slot index i2ctransfer failed (bus=$bus off=$CARTRIDGE_SLOT_INDEX_OFFSET)" >&2
		return 1
	fi
	if [[ -z "$slot_index" ]]; then
		echo "Cartridge: empty slot index read" >&2
		return 1
	fi

	# Program CPLD and verify each write (i2ctransfer returns hex token strings).
	offset=$(($lsb + SWB_SWITCH_TRAY_ID_OFFSET))
	i2ctransfer -f -y "$SWB_I2C_BUS" w3@"$SWB_I2C_ADDRESS" "$SWB_CARTRIDGE_MSB_OFFSET" "$offset" "$switch_tray_id"
	regval=$(i2ctransfer -f -y "$SWB_I2C_BUS" w2@"$SWB_I2C_ADDRESS" "$SWB_CARTRIDGE_MSB_OFFSET" "$offset" r1)
	if [ "$regval" != "$switch_tray_id" ]; then
		echo "Cartridge: bus $bus address $CARTRIDGE_I2C_ADDRESS: Switch tray Id $regval - $switch_tray_id not pushed"
		return 1
	fi

	offset=$(($lsb + SWB_SLOT_INDEX_OFFSET))
	i2ctransfer -f -y "$SWB_I2C_BUS" w3@"$SWB_I2C_ADDRESS" "$SWB_CARTRIDGE_MSB_OFFSET" $offset "$slot_index"
	regval=$(i2ctransfer -f -y "$SWB_I2C_BUS" w2@"$SWB_I2C_ADDRESS" "$SWB_CARTRIDGE_MSB_OFFSET" $offset r1)
	if [ "$regval" != "$slot_index" ]; then
		echo "Cartridge: bus $bus address $CARTRIDGE_I2C_ADDRESS: Slot index $regval - $slot_index not pushed"
		return 1
	fi

	offset=$(($lsb + SWB_TOPOLOGY_ID_OFFSET))
	i2ctransfer -f -y "$SWB_I2C_BUS" w3@"$SWB_I2C_ADDRESS" "$SWB_CARTRIDGE_MSB_OFFSET" "$offset" "$topology_id"
	regval=$(i2ctransfer -f -y "$SWB_I2C_BUS" w2@"$SWB_I2C_ADDRESS" "$SWB_CARTRIDGE_MSB_OFFSET" "$offset" r1)
	if [ "$regval" != "$topology_id" ]; then
		echo "Cartridge: bus $bus address $CARTRIDGE_I2C_ADDRESS: Topology id $regval - $topology_id not pushed"
		return 1
	fi

	offset=$(($lsb + SWB_CARTRIDGE_RACK_ID_OFFSET))
	# CPLD transaction: 2-byte register address + rack_id. When total is under 16 bytes,
	# pad with 0x00 to match legacy fixed-width CPLD blocks (e.g. 13-byte rack + 1 pad).
	reg_payload=$((2 + rack_sz))
	pad_len=0
	if ((reg_payload < 16)); then
		pad_len=$((16 - reg_payload))
	fi
	wr_bytes=$((reg_payload + pad_len))
	rack_pad=
	for ((i = 0; i < pad_len; i++)); do
		rack_pad="$rack_pad 0x00"
	done
	if ! i2ctransfer -f -y "$SWB_I2C_BUS" "w${wr_bytes}@${SWB_I2C_ADDRESS}" "$SWB_CARTRIDGE_MSB_OFFSET" "$offset" $rack_id $rack_pad; then
		echo "Cartridge: CPLD rack id write failed (bus=$SWB_I2C_BUS len=$wr_bytes)" >&2
		return 1
	fi
	if ! regval=$(i2ctransfer -f -y "$SWB_I2C_BUS" w2@"$SWB_I2C_ADDRESS" "$SWB_CARTRIDGE_MSB_OFFSET" "$offset" r"$rack_sz"); then
		echo "Cartridge: CPLD rack id readback failed (off=$offset len=$rack_sz)" >&2
		return 1
	fi
	if [ "$regval" != "$rack_id" ]; then
		echo "Cartridge: bus $bus address $CARTRIDGE_I2C_ADDRESS: Rack Id $regval - $rack_id not pushed"
		return 1
	fi

	return 0
}

# Public entry: no-op if JSON missing; USB path is a deliberate stub until HW is defined.
hw_mgmt_bmc_copy_cartridge_data()
{
	if [ ! -f "$HW_MGMT_BMC_CARTRIDGE_CFG" ]; then
		return 0
	fi

	if ! _cartridge_load_cfg "$HW_MGMT_BMC_CARTRIDGE_CFG"; then
		return 1
	fi

	case "$PHYSICAL_ACCESS" in
	USB)
		echo "Cartridge data copy: PhysicalAccess=USB (UsbPort=${USB_PORT:-n/a}) — not implemented pending HW alignment"
		return 0
		;;
	I2C|"")
		;;
	*)
		echo "Cartridge data copy: unknown PhysicalAccess '$PHYSICAL_ACCESS', skipping"
		return 0
		;;
	esac

	update_cartridge_data "$PRIMARY_CARTRIDGE_I2C_BUS" "$PRIMARY_CARTRIDGE_SWB_LSB_OFFSET"
}
