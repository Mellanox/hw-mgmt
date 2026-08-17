#!/bin/bash

# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
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
################################################################################
# Origin: OpenBMC meta-ast2700 bmc-post-boot-cfg bios-recovery-flash.sh
#
# BMC-side host BIOS recovery flash (host CPU must be powered off).
#
# Prerequisites:
#   - hw-management: /var/run/hw-management/system/*
#   - /dev/spidev0.0, flashrom with linux_spi
#
# Usage:
#   hw-management-bmc-bios-recovery-flash.sh [options] <bios_image>
#
# Options:
#   -d <path>    SPI device (default: /dev/spidev0.0)
#   -c <name>    flashrom chip name (default: MX25U25643G)
#   -s <hz>      SPI clock speed (default: 50000000)
#   -m <sec>     GPIO mux settle time (default: 10)
#   -t <sec>     Host power-off wait timeout (default: 30)
#   -h           Show help
#
# Colors: enabled on TTY; set NO_COLOR=1 to disable.
################################################################################

set -euo pipefail

HW_MGMT="/var/run/hw-management/system"

# Reserved; CPLD channel select not used yet.
SPI_CHNL_SELECT="${HW_MGMT}/spi_chnl_select"

GP_REC="${HW_MGMT}/GP_BMC_REC_SPI_MUX1_SEL"
GP_CS0="${HW_MGMT}/GP_PROD_CS_FLASH0_EN"
GP_CS1="${HW_MGMT}/GP_PROD_CS_FLASH1_EN"

PWR_DOWN="${HW_MGMT}/pwr_down"

DEFAULT_SPIDEV="/dev/spidev0.0"
DEFAULT_FLASH_CHIP="MX25U25643G"
DEFAULT_SPISPEED="50000000"
DEFAULT_MUX_SETTLE_SEC=1
DEFAULT_HOST_PWR_OFF_TIMEOUT=30

GPIO_SETUP_DONE=0

SPIDEV="$DEFAULT_SPIDEV"
FLASH_CHIP="$DEFAULT_FLASH_CHIP"
SPI_SPEED="$DEFAULT_SPISPEED"
MUX_SETTLE_SEC="$DEFAULT_MUX_SETTLE_SEC"
HOST_PWR_OFF_TIMEOUT="$DEFAULT_HOST_PWR_OFF_TIMEOUT"
IMAGE=""

STEP_NUM=0
STEP_TOTAL=7

# Colors (disabled when not a TTY or NO_COLOR is set)
USE_COLOR=0
C_RESET=""
C_BOLD=""
C_DIM=""
C_RED=""
C_GREEN=""
C_YELLOW=""
C_CYAN=""
C_BLUE=""
C_MAGENTA=""

color_init() {
	if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
		USE_COLOR=1
		C_RESET=$'\033[0m'
		C_BOLD=$'\033[1m'
		C_DIM=$'\033[2m'
		C_RED=$'\033[31m'
		C_GREEN=$'\033[32m'
		C_YELLOW=$'\033[33m'
		C_CYAN=$'\033[36m'
		C_BLUE=$'\033[34m'
		C_MAGENTA=$'\033[35m'
	fi
}

usage() {
	cat <<EOF
${C_BOLD}Usage:${C_RESET} $0 [options] <bios_image>

Flash host BIOS from BMC via SPI recovery path (GPIO bank select).

${C_BOLD}Options:${C_RESET}
  ${C_CYAN}-d${C_RESET} <path>    SPI device (default: ${DEFAULT_SPIDEV})
  ${C_CYAN}-c${C_RESET} <name>    flashrom chip name (default: ${DEFAULT_FLASH_CHIP})
  ${C_CYAN}-s${C_RESET} <hz>      SPI clock speed (default: ${DEFAULT_SPISPEED})
  ${C_CYAN}-m${C_RESET} <sec>     GPIO mux settle time (default: ${DEFAULT_MUX_SETTLE_SEC})
  ${C_CYAN}-t${C_RESET} <sec>     Host power-off wait timeout (default: ${DEFAULT_HOST_PWR_OFF_TIMEOUT})
  ${C_CYAN}-h${C_RESET}           Show this help

Host power: uses ${PWR_DOWN} (0=on, 1=off).
EOF
	exit 1
}

parse_args() {
	local opt

	OPTIND=1
	while getopts ":d:c:s:m:t:h" opt; do
		case "$opt" in
		d) SPIDEV="$OPTARG" ;;
		c) FLASH_CHIP="$OPTARG" ;;
		s) SPI_SPEED="$OPTARG" ;;
		m) MUX_SETTLE_SEC="$OPTARG" ;;
		t) HOST_PWR_OFF_TIMEOUT="$OPTARG" ;;
		h) usage ;;
		\?) die "Unknown option: -${OPTARG} (use -h for help)" ;;
		:) die "Option -${OPTARG} requires an argument" ;;
		esac
	done
	shift $((OPTIND - 1))

	if [ $# -lt 1 ]; then
		usage
	fi
	if [ $# -gt 1 ]; then
		die "Unexpected extra arguments: $*"
	fi

	IMAGE="$1"
}

print_rule() {
	printf '%s\n' "${C_DIM}------------------------------------------------------------------------${C_RESET}"
}

print_banner() {
	echo ""
	printf '%s\n' "${C_BOLD}${C_CYAN}  BIOS Recovery Flash (BMC SPI)${C_RESET}"
	print_rule
}

print_config() {
	log_kv "Image" "$IMAGE"
	log_kv "SPI device" "$SPIDEV"
	log_kv "Flash chip" "$FLASH_CHIP"
	log_kv "SPI speed" "${SPI_SPEED} Hz"
	log_kv "Mux settle" "${MUX_SETTLE_SEC} s"
	log_kv "Power-off timeout" "${HOST_PWR_OFF_TIMEOUT} s"
	print_rule
}

log_step() {
	STEP_NUM=$((STEP_NUM + 1))
	echo ""
	printf '%s\n' \
		"${C_BOLD}${C_BLUE}[${STEP_NUM}/${STEP_TOTAL}]${C_RESET} ${C_BOLD}$*${C_RESET}"
}

log_info() {
	printf '  %s %s\n' "${C_DIM}>>${C_RESET}" "$*"
}

log_kv() {
	local key="$1"
	local value="$2"
	printf '  %s %-18s %s%s%s\n' \
		"${C_DIM}>>${C_RESET}" "${key}:" "${C_CYAN}${value}${C_RESET}"
}

log_ok() {
	printf '  %s %s%s%s\n' \
		"${C_GREEN}[OK]${C_RESET}" "${C_GREEN}" "$*" "${C_RESET}"
}

log_warn() {
	printf '  %s %s%s%s\n' \
		"${C_YELLOW}[!!]${C_RESET}" "${C_YELLOW}" "$*" "${C_RESET}"
}

log_fail() {
	printf '%s %s%s%s\n' \
		"${C_RED}[FAIL]${C_RESET}" "${C_BOLD}${C_RED}" "$*" "${C_RESET}" >&2
}

log_cmd() {
	printf '  %s %s\n' "${C_MAGENTA}\$${C_RESET}" "${C_DIM}$*${C_RESET}"
}

log_gpio() {
	local name="$1"
	local value="$2"
	printf '  %s %-28s %s%s%s\n' \
		"${C_DIM}>>${C_RESET}" "${name}:" "${C_YELLOW}${value}${C_RESET}"
}

die() {
	echo "" >&2
	log_fail "$*"
	echo "" >&2
	exit 1
}

print_done() {
	echo ""
	print_rule
	printf '%s\n' "${C_BOLD}${C_GREEN}  BIOS recovery flash completed successfully${C_RESET}"
	print_rule
	echo ""
}

require_file() {
	local path="$1"
	local desc="$2"
	if [ ! -e "$path" ]; then
		die "${desc} not found: ${path}"
	fi
	if [ ! -w "$path" ] && [ ! -r "$path" ]; then
		die "${desc} not accessible: ${path}"
	fi
}

write_gpio() {
	local path="$1"
	local value="$2"
	local name="$3"
	require_file "$path" "$name"
	echo "$value" > "$path"
	log_gpio "$name" "$(cat "$path")"
}

# Return 0 if host power is on, 1 if off.
host_power_is_on() {
	local pwr_down_val

	if [ ! -r "$PWR_DOWN" ]; then
		die "Cannot read host power state: ${PWR_DOWN}"
	fi

	pwr_down_val=$(cat "$PWR_DOWN")
	# pwr_down=0 -> host on, pwr_down=1 -> host off
	[ "$pwr_down_val" = "0" ]
}

host_power_off() {
	if [ ! -w "$PWR_DOWN" ]; then
		return 1
	fi
	echo 1 > "$PWR_DOWN"
	return 0
}

wait_host_power_off() {
	local timeout="$1"
	local remaining="$timeout"

	log_info "Waiting for host power off (timeout ${timeout}s)"

	while [ "$remaining" -gt 0 ]; do
		if ! host_power_is_on; then
			echo ""
			log_ok "pwr_down=$(cat "$PWR_DOWN") (host off)"
			return 0
		fi
		printf '\r  %s power off countdown: %s%2d%s s remaining   ' \
			"${C_YELLOW}[..]${C_RESET}" \
			"${C_BOLD}${C_YELLOW}" "$remaining" "${C_RESET}"
		sleep 1
		remaining=$((remaining - 1))
	done
	echo ""
	log_fail "power off countdown timed out"
	return 1
}

ensure_host_powered_off() {
	log_step "Check host power state"

	log_kv "pwr_down" "$(cat "$PWR_DOWN") (0=on, 1=off)"

	if host_power_is_on; then
		log_warn "Host is powered on; requesting power off"
		host_power_off || die "Cannot write ${PWR_DOWN}"
		wait_host_power_off "$HOST_PWR_OFF_TIMEOUT" ||
			die "Host still powered on after ${HOST_PWR_OFF_TIMEOUT}s"
	else
		log_ok "Host is already powered off"
	fi
}

# ---------------------------------------------------------------------------
# Inactive flash bank selection (wiki: 0x252d bit5, 0x2535 bit4).
# Temporarily always bank1 until CPLD/active-image read is validated.
# ---------------------------------------------------------------------------
get_inactive_flash_bank() {
	# local active_byte active_bit

	# Read active flash from CPLD page 0x25 offset 0x2d (bit 5):
	#   0x0e -> flash 0 active,  0x2e -> flash 1 active
	# active_byte=$(i2ctransfer -f -y 14 w2@0x31 0x25 0x2d r1 2>/dev/null || echo "")
	# active_bit=$((active_byte & 0x20))
	# if [ "$active_bit" -eq 0 ]; then
	#	echo 1
	# else
	#	echo 0
	# fi

	echo 1
}

select_spi_bank() {
	local bank="$1"

	log_step "Select SPI flash bank ${bank}"
	log_kv "Bank" "${bank} (GPIO CS routing)"

	case "$bank" in
	0)
		write_gpio "$GP_REC" 1 "GP_BMC_REC_SPI_MUX1_SEL"
		write_gpio "$GP_CS0" 1 "GP_PROD_CS_FLASH0_EN"
		write_gpio "$GP_CS1" 0 "GP_PROD_CS_FLASH1_EN"
		;;
	1)
		write_gpio "$GP_REC" 1 "GP_BMC_REC_SPI_MUX1_SEL"
		write_gpio "$GP_CS0" 0 "GP_PROD_CS_FLASH0_EN"
		write_gpio "$GP_CS1" 1 "GP_PROD_CS_FLASH1_EN"
		;;
	*)
		die "Invalid flash bank: ${bank} (expected 0 or 1)"
		;;
	esac

	GPIO_SETUP_DONE=1

	if [ "$MUX_SETTLE_SEC" -gt 0 ]; then
		log_info "Mux settle delay ${MUX_SETTLE_SEC}s ..."
		sleep "$MUX_SETTLE_SEC"
		log_ok "Mux settle complete"
	fi
}

restore_spi_mux_default() {
	log_step "Restore REC SPI mux default"

	if [ -w "$GP_REC" ]; then
		echo 0 > "$GP_REC"
		log_gpio "GP_BMC_REC_SPI_MUX1_SEL" "$(cat "$GP_REC")"
	else
		log_warn "GP_BMC_REC_SPI_MUX1_SEL not writable; skip"
	fi
	GPIO_SETUP_DONE=0
}

# ---------------------------------------------------------------------------
# Switch active BIOS bank for next boot (wiki: set bit6 in 0x2535 -> 0x47).
# Disabled until validated on this platform.
# ---------------------------------------------------------------------------
switch_active_flash_bank() {
	:
	# local safe

	# log_step "Switch active BIOS bank for next boot"
	# safe=$(i2ctransfer -f -y 14 w2@0x31 0x25 0x35 r1)
	# log_info "SAFE_BIOS before: 0x$(printf '%02x' "$safe")"
	# i2ctransfer -f -y 14 w3@0x31 0x25 0x35 0x47
	# safe=$(i2ctransfer -f -y 14 w2@0x31 0x25 0x35 r1)
	# log_info "SAFE_BIOS after:  0x$(printf '%02x' "$safe")"
	# log_ok "bios_image_invert requested"
}

cleanup() {
	if [ "$GPIO_SETUP_DONE" -eq 1 ]; then
		echo 0 > "$GP_REC" 2>/dev/null || true
	fi
}

trap cleanup EXIT

flashrom_prog() {
	echo "linux_spi:dev=${SPIDEV},spispeed=${SPI_SPEED}"
}

verify_image_file() {
	log_step "Verify BIOS image file"

	if [ ! -f "$IMAGE" ]; then
		die "BIOS image not found: ${IMAGE}"
	fi

	log_ok "Image: ${IMAGE} ($(stat -c '%s' "$IMAGE") bytes)"
}

run_flashrom() {
	local action="$1"
	local action_flag="$2"
	local prog

	prog=$(flashrom_prog)

	log_cmd "flashrom -p ${prog} -c ${FLASH_CHIP} ${action_flag} ${IMAGE} --progress"
	echo ""
	flashrom -p "$prog" -c "$FLASH_CHIP" "$action_flag" "$IMAGE" --progress
	echo ""
	log_ok "flashrom ${action} completed"
}

run_flashrom_write() {
	log_step "Flash BIOS image"
	log_kv "Device" "$SPIDEV"
	log_kv "Chip" "$FLASH_CHIP"
	log_kv "Speed" "${SPI_SPEED} Hz"
	run_flashrom "write" "-w"
}

verify_flash_contents() {
	log_step "Verify flash contents"
	log_kv "Reference" "$IMAGE"
	run_flashrom "verify" "-v"
}

preflight() {
	log_step "Preflight checks"

	if ! command -v flashrom >/dev/null 2>&1; then
		die "flashrom not found"
	fi

	require_file "$PWR_DOWN" "pwr_down"
	require_file "$GP_REC" "GP_BMC_REC_SPI_MUX1_SEL"
	require_file "$GP_CS0" "GP_PROD_CS_FLASH0_EN"
	require_file "$GP_CS1" "GP_PROD_CS_FLASH1_EN"

	if [ ! -c "$SPIDEV" ]; then
		die "SPI device not accessible: ${SPIDEV}"
	fi

	log_ok "GPIO, pwr_down, and SPI paths present"
}

main() {
	local bank

	color_init
	parse_args "$@"

	print_banner
	print_config

	preflight
	ensure_host_powered_off

	bank=$(get_inactive_flash_bank)
	select_spi_bank "$bank"
	verify_image_file
	run_flashrom_write
	verify_flash_contents
	restore_spi_mux_default
	switch_active_flash_bank

	trap - EXIT
	print_done
}

main "$@"
