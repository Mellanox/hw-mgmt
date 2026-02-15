#!/bin/bash
###########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
# This script is executed by udev rule to bring up USB network interface
# Usage: hw-management-ifupdown.sh <interface>

source /usr/bin/hw-management-helpers.sh

INTERFACE=$1

if [ -z "${INTERFACE}" ]; then
	log_err "Missing interface parameter"
	exit 1
fi

if [ ! -e "/sys/class/net/${INTERFACE}" ]; then
	log_info "Interface ${INTERFACE} is missing"
	exit 0
fi

if [ ! -e /etc/network/interfaces ]; then
	log_info "/etc/network/interfaces is missing"
	exit 0
fi

AUTO=$(ifquery -l 2>/dev/null)
HOTPLUG=$(ifquery -l --allow=hotplug 2>/dev/null)

if ! echo "$AUTO" "$HOTPLUG" | grep -q "${INTERFACE}"; then
	exit 0
fi

# Retry ifup to work around locking conflicts with Debian networking service.
# Since usb0 is the only hotplug interface in the system, running this retry
# loop and blocking UDEV for maximum 8 seconds from processing further events
# for the same device path is an acceptable tradeoff.
MAX_RETRIES=5
RETRY_DELAY=2
for ((i=1; i<=MAX_RETRIES; i++)); do
	if ifup "${INTERFACE}"; then
		log_info "ifup ${INTERFACE} succeeded on attempt $i"
		exit 0
	fi

	if [ "$i" -lt "$MAX_RETRIES" ]; then
		log_info "Attempt $i to ifup ${INTERFACE} failed. Retrying in ${RETRY_DELAY} seconds..."
		sleep "${RETRY_DELAY}"
	fi
done

log_err "Failed to ifup interface ${INTERFACE}"
exit 1
