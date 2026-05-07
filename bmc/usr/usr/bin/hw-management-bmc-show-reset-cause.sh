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
# Print reset-cause attribute names (or raw SCU values) from hw-management
# runtime, mirroring host hw-management.sh reset-cause for reset_* files.
# BusyBox ash: POSIX sh only.
#
# Usage:
#   hw-management-bmc-show-reset-cause.sh              # all sections
#   hw-management-bmc-show-reset-cause.sh bmc          # BMC root reset_* only
#   hw-management-bmc-show-reset-cause.sh host         # host system reset_*
#   hw-management-bmc-show-reset-cause.sh bmc-domain   # .../bmc/domains/reset_*
#   hw-management-bmc-show-reset-cause.sh bmc-raw      # raw_scu* words under bmc/
################################################################################

BMC_DIR="${BMC_DIR:-/var/run/hw-management/bmc}"
BMC_DOMAINS_DIR="${BMC_DOMAINS_DIR:-${BMC_DIR}/domains}"
HOST_SYSTEM_DIR="${HOST_SYSTEM_DIR:-/var/run/hw-management/system}"

usage()
{
	cat <<'EOF'
Usage: hw-management-bmc-show-reset-cause.sh [-h|--help] [SECTION...]

  With no SECTION arguments, prints all sections in order: bmc, host,
  bmc-domain, bmc-raw.

  SECTION is one of:
    bmc          reset_* files directly under the BMC runtime directory
    host         reset_* under the host system path (SONiC switch runtime)
    bmc-domain   reset_* under bmc/domains/
    bmc-raw      raw_scu*_reset_event_log* files under the BMC runtime dir

  Environment overrides:
    BMC_DIR, BMC_DOMAINS_DIR, HOST_SYSTEM_DIR
EOF
}

# Echo basename of each reset_* regular file in $1 whose first line is integer 1.
# $2 is section tag (bmc | host | bmc-domain) for the "no files" diagnostic only.
emit_active_reset_basenames()
{
	dir="$1"
	ctx="${2:-bmc}"
	if [ ! -d "$dir" ]; then
		echo "(directory missing: ${dir})"
		return 0
	fi
	found=0
	seen_any=0
	for f in "${dir}"/reset_*; do
		[ -f "$f" ] || continue
		seen_any=1
		read -r v _ <"$f" || continue
		case "$v" in
		'' | *[!0-9]*) continue ;;
		esac
		if [ "$v" -eq 1 ]; then
			found=1
			basename "$f"
		fi
	done
	if [ "$found" -eq 0 ]; then
		if [ "$seen_any" -eq 0 ]; then
			case "$ctx" in
			host)
				echo "(no reset_* files — host reset-cause attributes not present under this directory)"
				;;
			*)
				echo "(no reset_* files — BMC reset-cause export missing; run hw-management-bmc-get-reset-cause.sh)"
				;;
			esac
		else
			echo "(no reset_* with value 1)"
		fi
	fi
}

section_bmc()
{
	printf '%s\n' "=== bmc (${BMC_DIR}) ==="
	emit_active_reset_basenames "${BMC_DIR}" bmc
}

section_host()
{
	printf '%s\n' "=== host (${HOST_SYSTEM_DIR}) ==="
	emit_active_reset_basenames "${HOST_SYSTEM_DIR}" host
}

section_bmc_domain()
{
	printf '%s\n' "=== bmc-domain (${BMC_DOMAINS_DIR}) ==="
	emit_active_reset_basenames "${BMC_DOMAINS_DIR}" bmc-domain
}

section_bmc_raw()
{
	printf '%s\n' "=== bmc-raw (${BMC_DIR}) ==="
	if [ ! -d "${BMC_DIR}" ]; then
		echo "(directory missing: ${BMC_DIR})"
		return 0
	fi
	found=0
	for f in "${BMC_DIR}"/raw_scu*_reset_event_log*; do
		[ -f "$f" ] || continue
		found=1
		printf '%s: %s\n' "$(basename "$f")" "$(cat "$f" 2>/dev/null)"
	done
	if [ "$found" -eq 0 ]; then
		echo "(no raw_scu*_reset_event_log* files)"
	fi
}

run_section()
{
	case "$1" in
	bmc) section_bmc ;;
	host) section_host ;;
	bmc-domain) section_bmc_domain ;;
	bmc-raw) section_bmc_raw ;;
	*)
		echo "hw-management-bmc-show-reset-cause.sh: unknown section: $1" >&2
		return 1
		;;
	esac
	echo
}

case "${1:-}" in
-h | --help)
	usage
	exit 0
	;;
esac

if [ "$#" -eq 0 ]; then
	run_section bmc && run_section host && run_section bmc-domain && run_section bmc-raw
	exit $?
fi

for arg in "$@"; do
	run_section "$arg" || exit 1
done
exit 0
