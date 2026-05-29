#!/bin/sh

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
#    notice, this list, and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
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
# SUBSTITUTE GOODS OR SERVICES; LOSS OF DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
################################################################################
# Export BMC reset cause into hw-management style files.
# BusyBox ash (/bin/sh): POSIX sh + C-style 0x arithmetic and bitwise ops; no bashisms.
#
# AST2700 primary source:
#   SCU1 0x050 (Reset Event Log Set 1) + SCU1 0x080 (Reset Event Log Set 4)
#   and SCU0 0x070 as additional watchdog evidence.
#   SCU0 0x050 is also read for eMMC/MSI reset logs.
#   AST2700 SCU base uses +0x2000 window (e.g. 0x12c02050, 0x14c02080).
#
# U-Boot env / kernel cmdline names (per SCU register; snap_bootargs tokens):
#   reset_cause_scu0_0 -> SCU0 0x050
#   reset_cause_scu0_2 -> SCU0 0x070
#   reset_cause_scu1_0 -> SCU1 0x050
#   reset_cause_scu1_3 -> SCU1 0x080
#
# Source priority per word: fw_printenv, then /proc/cmdline, then devmem.
#
# Domain-detail flags (ahb, caliptra, emmc, espi, external, msi, soc, spi, usb)
# go under OUT_DIR/domains/. reset_power_on, watchdog, software, cpu,
# security_watchdog2, and others stay in OUT_DIR.
################################################################################

OUT_DIR="${OUT_DIR:-/var/run/hw-management/bmc}"
DOMAINS_DIR="${DOMAINS_DIR:-${OUT_DIR}/domains}"
SCU0_LOG2_ADDR="${SCU0_LOG2_ADDR:-0x12c02070}"
SCU0_LOG0_ADDR="${SCU0_LOG0_ADDR:-0x12c02050}"
SCU1_LOG0_ADDR="${SCU1_LOG0_ADDR:-0x14c02050}"
SCU1_LOG3_ADDR="${SCU1_LOG3_ADDR:-0x14c02080}"
ENV_SCU0_LOG0="${ENV_SCU0_LOG0:-reset_cause_scu0_0}"
ENV_SCU0_LOG2="${ENV_SCU0_LOG2:-reset_cause_scu0_2}"
ENV_SCU1_LOG0="${ENV_SCU1_LOG0:-reset_cause_scu1_0}"
ENV_SCU1_LOG3="${ENV_SCU1_LOG3:-reset_cause_scu1_3}"

umask 022
mkdir -p "${OUT_DIR}"
mkdir -p "${DOMAINS_DIR}"

normalize_hex() {
	in="$1"
	case "${in}" in
	0x* | 0X*) hex="${in}" ;;
	*) hex="0x${in}" ;;
	esac
	digits="${hex#0x}"
	digits="${digits#0X}"
	case "${digits}" in
	'' | *[!0-9A-Fa-f]*)
		return 1
		;;
	esac
	val=$((${hex}))
	return 0
}

read_devmem_val() {
	addr="$1"
	outvar="$2"
	raw="$(devmem "${addr}" 32 2>/dev/null || busybox devmem "${addr}" 32 2>/dev/null || true)"
	[ -n "${raw}" ] || return 1
	normalize_hex "${raw}" || return 1
	eval "${outvar}=\$val"
	return 0
}

read_env_val() {
	envname="$1"
	outvar="$2"
	raw="$(fw_printenv -n "${envname}" 2>/dev/null || true)"
	[ -n "${raw}" ] || return 1
	normalize_hex "${raw}" || return 1
	eval "${outvar}=\$val"
	return 0
}

read_cmdline_val() {
	name="$1"
	outvar="$2"
	raw=""

	if [ -r /proc/cmdline ]; then
		raw="$(awk -v RS=' ' -F= -v n="${name}" '$1 == n { print $2; exit }' /proc/cmdline 2>/dev/null || true)"
	fi
	[ -n "${raw}" ] || return 1
	normalize_hex "${raw}" || return 1
	eval "${outvar}=\$val"
	return 0
}

set_reset_file() {
	name="$1"
	value="$2"
	case "${name}" in
	ahb|caliptra|emmc|espi|external|msi|soc|spi|usb)
		echo "${value}" >"${DOMAINS_DIR}/reset_${name}"
		;;
	*)
		echo "${value}" >"${OUT_DIR}/reset_${name}"
		;;
	esac
}

# Per-register: U-Boot env, then /proc/cmdline, then devmem.
scu0_log2_ok=0
scu0_log0_ok=0
scu1_log0_ok=0
scu1_log3_ok=0

if command -v fw_printenv >/dev/null 2>&1; then
	if read_env_val "${ENV_SCU0_LOG0}" scu0_log0; then
		scu0_log0_ok=1
	fi
	if read_env_val "${ENV_SCU0_LOG2}" scu0_log2; then
		scu0_log2_ok=1
	fi
	if read_env_val "${ENV_SCU1_LOG0}" scu1_log0; then
		scu1_log0_ok=1
	fi
	if read_env_val "${ENV_SCU1_LOG3}" scu1_log3; then
		scu1_log3_ok=1
	fi
fi

if [ "${scu0_log0_ok}" -ne 1 ] && read_cmdline_val "${ENV_SCU0_LOG0}" scu0_log0; then
	scu0_log0_ok=1
fi
if [ "${scu0_log2_ok}" -ne 1 ] && read_cmdline_val "${ENV_SCU0_LOG2}" scu0_log2; then
	scu0_log2_ok=1
fi
if [ "${scu1_log0_ok}" -ne 1 ] && read_cmdline_val "${ENV_SCU1_LOG0}" scu1_log0; then
	scu1_log0_ok=1
fi
if [ "${scu1_log3_ok}" -ne 1 ] && read_cmdline_val "${ENV_SCU1_LOG3}" scu1_log3; then
	scu1_log3_ok=1
fi

if [ "${scu0_log2_ok}" -ne 1 ] && read_devmem_val "${SCU0_LOG2_ADDR}" scu0_log2; then
	scu0_log2_ok=1
fi
if [ "${scu0_log0_ok}" -ne 1 ] && read_devmem_val "${SCU0_LOG0_ADDR}" scu0_log0; then
	scu0_log0_ok=1
fi
if [ "${scu1_log0_ok}" -ne 1 ] && read_devmem_val "${SCU1_LOG0_ADDR}" scu1_log0; then
	scu1_log0_ok=1
fi
if [ "${scu1_log3_ok}" -ne 1 ] && read_devmem_val "${SCU1_LOG3_ADDR}" scu1_log3; then
	scu1_log3_ok=1
fi

if [ "${scu0_log2_ok}" -ne 1 ] || [ "${scu0_log0_ok}" -ne 1 ] || [ "${scu1_log0_ok}" -ne 1 ] || [ "${scu1_log3_ok}" -ne 1 ]; then
	echo "cannot get complete reset causes from env/cmdline/devmem (SCU0_LOG2, SCU0_LOG0, SCU1_LOG0, SCU1_LOG3)" >&2
	exit 1
fi

# Store raw SCU reset-log words.
echo "$(printf '0x%08x' "${scu0_log0}")" >"${OUT_DIR}/raw_scu0_reset_event_log0"
echo "$(printf '0x%08x' "${scu0_log2}")" >"${OUT_DIR}/raw_scu0_reset_event_log2"
echo "$(printf '0x%08x' "${scu1_log0}")" >"${OUT_DIR}/raw_scu1_reset_event_log0"
echo "$(printf '0x%08x' "${scu1_log3}")" >"${OUT_DIR}/raw_scu1_reset_event_log3"

# AST2700 semantic mapping.
# Combine SCU1/SCU0 PWRST indications for power_on.
power_on=$((((scu1_log0 >> 11) & 1) | ((scu0_log0 >> 11) & 1)))
external=$((((scu1_log0 >> 1) & 1) | (scu1_log0 & 1) | ((scu0_log0 >> 1) & 1) | (scu0_log0 & 1)))
cpu=$(((scu1_log0 >> 12) & 1))
soc=$((((scu1_log0 >> 13) & 1) | ((scu0_log0 >> 13) & 1)))
ahb=$((((scu1_log0 >> 14) & 1) | ((scu0_log0 >> 14) & 1)))
caliptra=$(((scu1_log0 >> 16) & 1))
# USB reset evidence from SCU1 USB2D/USB2C/UHCI and SCU0 USB bus/VHUB/UHCI logs.
scu0_usb_mask=$((0x001F0000))
usb=$((((scu1_log0 >> 22) & 1) | ((scu1_log0 >> 20) & 1) | ((scu1_log0 >> 18) & 1) | ((scu0_log0 & scu0_usb_mask) != 0)))
spi=$((((scu1_log0 >> 27) & 1) | ((scu1_log0 >> 26) & 1) | ((scu1_log0 >> 25) & 1)))
espi=$((((scu1_log0 >> 29) & 1) | ((scu1_log0 >> 28) & 1) | ((scu1_log0 >> 5) & 1) | ((scu1_log0 >> 4) & 1)))
emmc=$(((scu0_log0 >> 31) & 1))
msi=$(((scu0_log0 >> 30) & 1))

# SCU1 0x080: each nibble is WDTx {SW,SOC,ARM,FULL}.
soft_wdt_mask=$((0x88888888))
non_soft_wdt_mask=$((0x77777777))
software=$(((scu1_log3 & soft_wdt_mask) != 0))
watchdog=$((((scu1_log3 & non_soft_wdt_mask) != 0) | (scu0_log2 != 0)))

# WDT2 group at bits [11:8] in SCU1 0x080.
security_watchdog2=$((((scu1_log3 >> 8) & 0xF) != 0))

# reset_others = 1 only when none of the dedicated (non-domain) reset causes is set.
# Domain-detail flags live under OUT_DIR/domains/ and are excluded from this mask.
others=$((!(power_on | watchdog | software | cpu | security_watchdog2)))

set_reset_file power_on "${power_on}"
set_reset_file external "${external}"
set_reset_file watchdog "${watchdog}"
set_reset_file software "${software}"
set_reset_file cpu "${cpu}"
set_reset_file soc "${soc}"
set_reset_file ahb "${ahb}"
set_reset_file caliptra "${caliptra}"
set_reset_file usb "${usb}"
set_reset_file spi "${spi}"
set_reset_file espi "${espi}"
set_reset_file emmc "${emmc}"
set_reset_file msi "${msi}"
set_reset_file security_watchdog2 "${security_watchdog2}"
set_reset_file others "${others}"

exit 0
