#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# This script obtains/rotates the BMC password and logs in over Redfish, which
# also provisions the NOS account on the BMC. It is started by
# hw-management-bmc-login.service, after hw-management has initialized the
# system and after usb0 - the network to the BMC - has been brought up.
#
# It used to run as check_system_bmc_redfish_login during hw-management start,
# where it raced the configuration of usb0: it allowed 15s for an address to
# appear, while usb0 is brought up only once the networking service is done,
# which takes longer. The login was then skipped for the whole boot, and on
# platforms that do not poll a BMC sensor nothing logs in afterwards.
# Usage: hw-management-bmc-login.sh

source /usr/bin/hw-management-helpers.sh

# Name used in the trace log, where this flow was reported from hw-management.sh
# before it moved here.
TRACE_FN="bmc_redfish_login"
# The network to the BMC. The login derives the address of the BMC from the
# address of this interface.
BMC_INTERFACE=usb0
# Budget for waiting on that address. Ordering of the service covers the usual
# case, and whenever hw-management-ifupdown@usb0.service has handled the
# interface it restarts this service, so a late interface gets a run of its own.
# This only has to cover the address appearing shortly after that, as when the
# NOS owns usb0 and configures it itself.
ADDRESS_TIMEOUT=60
ADDRESS_POLL=2
# Budget for the BMC to start serving Redfish once usb0 is configured. The BMC
# brings the interface up early in its own boot, minutes before its web server
# answers, and a login against it meanwhile fails at every step of its flow.
REDFISH_TIMEOUT=300
REDFISH_POLL=5
# Per probe. Above the 3s the client allows a request, so a web server that is
# still slow to answer its first requests is seen as up rather than as down.
REDFISH_PROBE_TIMEOUT=10
# Once Redfish answers, a login may still meet a service on the BMC that is not
# quite ready.
LOGIN_RETRIES=3
LOGIN_DELAY=5
# The Redfish client lives in /usr/bin, which is not on the module search path
# of an interpreter started from elsewhere.
REDFISH_CLIENT_DIR=/usr/bin

# Print the IPv4 address of the BMC network, empty while it has none.
bmc_interface_address()
{
	ip -o -4 addr show "${BMC_INTERFACE}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1
}

# Wait for the BMC network to carry an address. The interface itself may be
# missing as well, as it is exposed by the BMC and disappears while that one
# resets, which "ip addr show" reports the same way as an interface without an
# address. Returns 1 when the budget runs out, as there is nothing to log in to
# without an address.
wait_for_bmc_interface()
{
	local deadline=$((SECONDS + ADDRESS_TIMEOUT))
	local address

	while :; do
		address=$(bmc_interface_address)
		print_function_call "$0" "${TRACE_FN}" "BMC IP address: ${address}"
		if [ -n "${address}" ]; then
			return 0
		fi

		if [ "${SECONDS}" -ge "${deadline}" ]; then
			if [ ! -e "/sys/class/net/${BMC_INTERFACE}" ]; then
				log_err "BMC login: ${BMC_INTERFACE} did not appear in ${ADDRESS_TIMEOUT}s"
			else
				log_err "BMC login: ${BMC_INTERFACE} got no address in ${ADDRESS_TIMEOUT}s"
			fi
			return 1
		fi
		sleep "${ADDRESS_POLL}"
	done
}

# Print the address of the BMC, derived from the address of usb0 the same way
# the client does it in get_ip_addr(): the BMC is always X.X.X.1.
bmc_address()
{
	local address

	address=$(bmc_interface_address)
	[ -n "${address}" ] || return 1
	echo "${address%.*}.1"
}

# Succeed once the Redfish service root of the BMC answers. It is served
# without authentication, so probing it costs no login attempt, which a BMC that
# is half up could count towards locking the account. Any answer short of a
# server error counts, so a BMC that does protect the root is still seen as up.
# The client prefers HTTP and falls back to HTTPS, so either one counts as well.
bmc_redfish_answers()
{
	local bmc=$1
	local scheme code

	for scheme in http https; do
		code=$(curl -k -s -o /dev/null -w '%{http_code}' \
			--max-time "${REDFISH_PROBE_TIMEOUT}" "${scheme}://${bmc}/redfish/v1" 2>/dev/null)
		case "${code}" in
		[234]??)
			return 0
			;;
		esac
	done
	return 1
}

# Wait for the BMC to serve Redfish. The address is derived again on every
# probe, as the BMC can go away once more while this waits. Returns 1 when the
# budget runs out.
wait_for_bmc_redfish()
{
	local start=$SECONDS
	local deadline=$((SECONDS + REDFISH_TIMEOUT))
	local waiting=0
	local bmc

	while :; do
		bmc=$(bmc_address)
		if [ -n "${bmc}" ] && bmc_redfish_answers "${bmc}"; then
			log_info "BMC login: Redfish service at ${bmc} answered after $((SECONDS - start))s"
			return 0
		fi

		if [ "${waiting}" -eq 0 ]; then
			print_function_call "$0" "${TRACE_FN}" "Waiting for the BMC Redfish service at ${bmc}"
			waiting=1
		fi
		if [ "${SECONDS}" -ge "${deadline}" ]; then
			log_err "BMC login: Redfish service at ${bmc:-the BMC} did not answer in ${REDFISH_TIMEOUT}s"
			return 1
		fi
		sleep "${REDFISH_POLL}"
	done
}

# Log in over Redfish. login() reports its own flow and returns a code, which
# the interpreter has to turn into an exit status for the retry loop.
bmc_login()
{
	PYTHONPATH="${REDFISH_CLIENT_DIR}" python3 -c "
import sys
from hw_management_redfish_client import BMCAccessor, RedfishClient
ret = BMCAccessor().login()
print(ret)
sys.exit(0 if ret == RedfishClient.ERR_CODE_OK else 1)
"
}

print_function_call "$0" "${TRACE_FN}" "Checking BMC Redfish login started"

# is_redfish_disabled is a temporary stand-in (Bug 5272044) and currently always
# returns false, so this login runs on every NOS that has a BMC.
if ! check_bmc_is_supported || check_host_os_is_redfish_disabled; then
	print_function_call "$0" "${TRACE_FN}" "BMC Redfish login not applicable"
	exit 0
fi

wait_for_bmc_interface || exit 1
wait_for_bmc_redfish || exit 1

for ((i=1; i<=LOGIN_RETRIES; i++)); do
	print_function_call "$0" "${TRACE_FN}" "Logging in to BMC, attempt ${i}"
	if bmc_login; then
		log_info "BMC login: logged in to the BMC on attempt ${i}"
		print_function_call "$0" "${TRACE_FN}" "BMC Redfish login check completed"
		exit 0
	fi

	log_err "BMC login: attempt ${i} failed"
	if [ "${i}" -lt "${LOGIN_RETRIES}" ]; then
		sleep "${LOGIN_DELAY}"
	fi
done

log_err "BMC login: failed to log in to the BMC after ${LOGIN_RETRIES} attempts"
print_function_call "$0" "${TRACE_FN}" "BMC Redfish login check failed"
exit 1
