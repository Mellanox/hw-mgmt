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
#   SCU0 0x050 (Reset Event Log Set 0) - SRST# / EXTRST# for power-channel
#   SCU0 0x060 (Reset Event Log Set 2) - ABR / WDTA bit 31
#   SCU0 0x070 (Reset Event Log Set 3) + SCU1 0x080 (Set 4) - WDT evidence
#   SCU1 0x050 (Set 1) - domain detail (also eMMC/MSI via SCU0 0x050).
#   AST2700 SCU base uses +0x2000 window (e.g. 0x12c02050, 0x14c02080).
#
# U-Boot env / kernel cmdline names (per SCU register; snap_bootargs tokens):
#   reset_cause_scu0_0 -> SCU0 0x050
#   reset_cause_scu0_1 -> SCU0 0x060
#   reset_cause_scu0_2 -> SCU0 0x070
#   reset_cause_scu1_0 -> SCU1 0x050
#   reset_cause_scu1_3 -> SCU1 0x080
#
# Source priority per word: fw_printenv, then /proc/cmdline, then devmem.
#
# SONiC BMC primary cause (exactly one 1 under OUT_DIR) - v3:
#   reset_pwr_cycle | reset_soft_reboot | reset_unknown
#   pwr_like = SRST|EXTRST; warm_evidence = WDT (0x070/0x080) | ABR (0x060 bit31)
#   pwr_cycle   = pwr_like && !warm_evidence
#   soft_reboot = warm_evidence && !SRST   (EXTRST+WDT without SRST is soft)
#   unknown     = (SRST && warm_evidence) || (!pwr_like && !warm_evidence)
#   Note: SRST (bit0), not EXTRST (bit1), distinguishes soft_reboot vs unknown
#   when warm evidence is present. No-WDT/EXTRST-clear is unknown, not soft.
# Hardware / domain-detail flags under OUT_DIR/domains/.
# After export: W1C-clear only bits from the exported snapshot (SCU0 0x050
# SRST|EXTRST that were set, SCU0 0x060 ABR if set, exported WDT words;
# skip SCU1 0x050). Avoids wiping newer live MMIO on stale env re-run.
# CLEAR_SCU_RESET_LOG=1 default.
################################################################################

OUT_DIR="${OUT_DIR:-/var/run/hw-management/bmc}"
DOMAINS_DIR="${DOMAINS_DIR:-${OUT_DIR}/domains}"
SCU0_LOG0_ADDR="${SCU0_LOG0_ADDR:-0x12c02050}"
SCU0_LOG1_ADDR="${SCU0_LOG1_ADDR:-0x12c02060}"
SCU0_LOG2_ADDR="${SCU0_LOG2_ADDR:-0x12c02070}"
SCU1_LOG0_ADDR="${SCU1_LOG0_ADDR:-0x14c02050}"
SCU1_LOG3_ADDR="${SCU1_LOG3_ADDR:-0x14c02080}"
ENV_SCU0_LOG0="${ENV_SCU0_LOG0:-reset_cause_scu0_0}"
ENV_SCU0_LOG1="${ENV_SCU0_LOG1:-reset_cause_scu0_1}"
ENV_SCU0_LOG2="${ENV_SCU0_LOG2:-reset_cause_scu0_2}"
ENV_SCU1_LOG0="${ENV_SCU1_LOG0:-reset_cause_scu1_0}"
ENV_SCU1_LOG3="${ENV_SCU1_LOG3:-reset_cause_scu1_3}"
# Set to 0 to skip MMIO write-1-to-clear after export (offline tests / debug).
CLEAR_SCU_RESET_LOG="${CLEAR_SCU_RESET_LOG:-1}"

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

# AST2700 reset-event logs are write-1-to-clear (RUWT/RW1C).
# $2 must be a 0x... hex word (passed through to devmem; no signed $(( ))).
write_devmem_val() {
	addr="$1"
	hex="$2"
	case "${hex}" in
	0x* | 0X*) ;;
	*)
		return 1
		;;
	esac
	if command -v devmem >/dev/null 2>&1; then
		devmem "${addr}" 32 "${hex}" >/dev/null 2>&1 && return 0
	fi
	if command -v busybox >/dev/null 2>&1; then
		busybox devmem "${addr}" 32 "${hex}" >/dev/null 2>&1 && return 0
	fi
	return 1
}

clear_scu_reset_logs() {
	# W1C only bits present in the *exported* snapshot (primary-relevant masks).
	# Do not blanket-clear 0x3 / 0xffffffff: a re-run that classified from stale
	# fw_printenv|/proc/cmdline must not wipe newer live MMIO events that were
	# never exported. Writing 0 is a no-op for W1C.
	#   SCU0 0x050: exported & (SRST|EXTRST)
	#   SCU0 0x060: ABR bit31 only if exported abr was set
	#   SCU0 0x070 / SCU1 0x080: exported WDT words as-is
	#   SCU1 0x050: skipped
	_c_fail=0
	_m050="$(printf '0x%08x' "$((scu0_log0 & 3))")"
	write_devmem_val "${SCU0_LOG0_ADDR}" "${_m050}" || _c_fail=1
	if [ "$(((scu0_log1 >> 31) & 1))" -eq 1 ]; then
		write_devmem_val "${SCU0_LOG1_ADDR}" 0x80000000 || _c_fail=1
	fi
	# Use already-formatted raw files (avoids signed 32-bit printf issues).
	_m070="$(cat "${OUT_DIR}/raw_scu0_reset_event_log2" 2>/dev/null || echo 0x0)"
	_m080="$(cat "${OUT_DIR}/raw_scu1_reset_event_log3" 2>/dev/null || echo 0x0)"
	write_devmem_val "${SCU0_LOG2_ADDR}" "${_m070}" || _c_fail=1
	write_devmem_val "${SCU1_LOG3_ADDR}" "${_m080}" || _c_fail=1
	if [ "${_c_fail}" -ne 0 ]; then
		echo "warning: failed to W1C-clear one or more SCU reset-event logs" >&2
	fi
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
		# Strip through first '=' only (not -F= / $2) so values may contain '='.
		raw="$(awk -v RS=' ' -v n="${name}" '$0 ~ ("^" n "=") { sub(/^[^=]*=/, ""); print; exit }' /proc/cmdline 2>/dev/null || true)"
	fi
	[ -n "${raw}" ] || return 1
	normalize_hex "${raw}" || return 1
	eval "${outvar}=\$val"
	return 0
}

set_primary_reset_file() {
	_name="$1"
	_value="$2"
	_dest="${OUT_DIR}/reset_${_name}"
	_tmp="${_dest}.tmp.$$"
	echo "${_value}" >"${_tmp}" || return 1
	mv -f "${_tmp}" "${_dest}"
}

set_domain_reset_file() {
	echo "$2" >"${DOMAINS_DIR}/reset_$1"
}

# Pre-v2 primary flags at bmc/ root (hardware detail now under domains/). v3 primaries are
# replaced atomically above, not removed here. Belt for apt upgrade from pre-v2 exporter.
remove_v1_primary_reset_files() {
	for legacy in power_on watchdog software cpu security_watchdog2 others; do
		rm -f "${OUT_DIR}/reset_${legacy}"
	done
}

# Write all v3 primary flags first (atomic per file), then drop stale v1 root flags.
publish_primary_reset_cause() {
	set_primary_reset_file pwr_cycle "${pwr_cycle}" || return 1
	set_primary_reset_file soft_reboot "${soft_reboot}" || return 1
	set_primary_reset_file unknown "${unknown}" || return 1
	remove_v1_primary_reset_files
	return 0
}

# Per-register: U-Boot env, then /proc/cmdline, then devmem.
scu0_log0_ok=0
scu0_log1_ok=0
scu0_log2_ok=0
scu1_log0_ok=0
scu1_log3_ok=0

if command -v fw_printenv >/dev/null 2>&1; then
	if read_env_val "${ENV_SCU0_LOG0}" scu0_log0; then
		scu0_log0_ok=1
	fi
	if read_env_val "${ENV_SCU0_LOG1}" scu0_log1; then
		scu0_log1_ok=1
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
if [ "${scu0_log1_ok}" -ne 1 ] && read_cmdline_val "${ENV_SCU0_LOG1}" scu0_log1; then
	scu0_log1_ok=1
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

if [ "${scu0_log0_ok}" -ne 1 ] && read_devmem_val "${SCU0_LOG0_ADDR}" scu0_log0; then
	scu0_log0_ok=1
fi
if [ "${scu0_log1_ok}" -ne 1 ] && read_devmem_val "${SCU0_LOG1_ADDR}" scu0_log1; then
	scu0_log1_ok=1
fi
if [ "${scu0_log2_ok}" -ne 1 ] && read_devmem_val "${SCU0_LOG2_ADDR}" scu0_log2; then
	scu0_log2_ok=1
fi
if [ "${scu1_log0_ok}" -ne 1 ] && read_devmem_val "${SCU1_LOG0_ADDR}" scu1_log0; then
	scu1_log0_ok=1
fi
if [ "${scu1_log3_ok}" -ne 1 ] && read_devmem_val "${SCU1_LOG3_ADDR}" scu1_log3; then
	scu1_log3_ok=1
fi

if [ "${scu0_log0_ok}" -ne 1 ] || [ "${scu0_log1_ok}" -ne 1 ] || [ "${scu0_log2_ok}" -ne 1 ] || [ "${scu1_log0_ok}" -ne 1 ] || [ "${scu1_log3_ok}" -ne 1 ]; then
	echo "cannot get complete reset causes from env/cmdline/devmem (SCU0_LOG0, SCU0_LOG1, SCU0_LOG2, SCU1_LOG0, SCU1_LOG3)" >&2
	exit 1
fi

# Store raw SCU reset-log words.
echo "$(printf '0x%08x' "${scu0_log0}")" >"${OUT_DIR}/raw_scu0_reset_event_log0"
echo "$(printf '0x%08x' "${scu0_log1}")" >"${OUT_DIR}/raw_scu0_reset_event_log1"
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

# SCU0 0x060 bit 31: ABR / WDTA (Alternate Boot Recovery) reset log.
abr=$(((scu0_log1 >> 31) & 1))

# Diagnostic: no PWRST/WDT/CPU/WDT2/ABR hardware bits (domains only).
others=$((!(power_on | watchdog | software | cpu | security_watchdog2 | abr)))

# Primary SONiC cause v3 (OpenBMC-aligned; requires uncleared SCU logs).
# Inputs:
#   scu0_srst_bit0   - SCU0 0x050 bit 0 (SRST#)
#   scu0_extrst_bit1 - SCU0 0x050 bit 1 (EXTRST#)
#   any_wdt_log      - SCU0 0x070 or SCU1 0x080 non-zero
#   abr              - SCU0 0x060 bit 31 (ABR/WDTA)
#   warm_evidence    - any_wdt_log or abr
# Branches:
#   pwr_cycle   - (SRST|EXTRST) and no warm evidence
#   soft_reboot - warm evidence and no SRST
#   unknown     - SRST+warm sticky/mixed, or neither power-like nor warm
any_wdt_log=0
if [ "${scu0_log2}" -ne 0 ] || [ "${scu1_log3}" -ne 0 ]; then
	any_wdt_log=1
fi
warm_evidence=0
if [ "${any_wdt_log}" -eq 1 ] || [ "${abr}" -eq 1 ]; then
	warm_evidence=1
fi
scu0_srst_bit0=$((scu0_log0 & 1))
scu0_extrst_bit1=$(((scu0_log0 >> 1) & 1))
pwr_like=0
if [ "${scu0_srst_bit0}" -eq 1 ] || [ "${scu0_extrst_bit1}" -eq 1 ]; then
	pwr_like=1
fi

pwr_cycle=0
soft_reboot=0
unknown=0

if [ "${pwr_like}" -eq 1 ] && [ "${warm_evidence}" -eq 0 ]; then
	pwr_cycle=1
elif [ "${warm_evidence}" -eq 1 ] && [ "${scu0_srst_bit0}" -eq 0 ]; then
	soft_reboot=1
elif [ "${scu0_srst_bit0}" -eq 1 ] && [ "${warm_evidence}" -eq 1 ]; then
	unknown=1
else
	unknown=1
fi

publish_primary_reset_cause || exit 1
# Invariant: exactly one primary flag is 1 (pwr_cycle | soft_reboot | unknown).

set_domain_reset_file power_on "${power_on}"
set_domain_reset_file external "${external}"
set_domain_reset_file watchdog "${watchdog}"
set_domain_reset_file software "${software}"
set_domain_reset_file cpu "${cpu}"
set_domain_reset_file soc "${soc}"
set_domain_reset_file ahb "${ahb}"
set_domain_reset_file caliptra "${caliptra}"
set_domain_reset_file usb "${usb}"
set_domain_reset_file spi "${spi}"
set_domain_reset_file espi "${espi}"
set_domain_reset_file emmc "${emmc}"
set_domain_reset_file msi "${msi}"
set_domain_reset_file security_watchdog2 "${security_watchdog2}"
set_domain_reset_file abr "${abr}"
set_domain_reset_file others "${others}"

if [ "${CLEAR_SCU_RESET_LOG}" != "0" ]; then
	clear_scu_reset_logs
fi

exit 0
