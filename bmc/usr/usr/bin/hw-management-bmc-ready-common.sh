#!/bin/bash
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

bmc_init_bootargs()
{
       # Standalone BMC system, no system EEPROM.
	if [ ! -d /sys/class/net/eth1 ]; then
		fw_setenv bootargs "console=ttyS12,115200n8 root=/dev/ram rw earlycon"
	fi

	bootargs=$(fw_printenv bootargs)
	#if echo ${bootargs} | grep -q "ttyS2" && echo ${bootargs} | grep -q "46:44:8a:c8:7f:bf"; then
	#	return
	#fi
	if echo ${bootargs} | grep -q "46:44:8a:c8:7f:bf"; then
		return
	fi

	fw_setenv bootargs "console=ttyS12,115200n8 root=/dev/ram rw earlycon g_ether.host_addr=46:44:8a:c8:7f:bf g_ether.dev_addr=46:44:8a:c8:7f:bd"
}

# Removes ipmi permissions from a user (OpenBMC D-Bus user manager; not used on SONiC BMC).
remove_ipmitools_permissions()
{
    echo "Skipping ipmi permission change (no D-Bus user manager)"
    return 0
}

create_nosbmc_user()
{
    echo "Skipping nosbmc user setup (no D-Bus user manager)"
    return 0
}
