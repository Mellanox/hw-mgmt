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

# Removes ipmi permissions from a user.
remove_ipmitools_permissions()
{
    USER_NAME=$1
    user_groups=$(/usr/bin/hw-management-dbus-if.sh user_manager_get_groups "${USER_NAME}")
    if [[ "$user_groups" == *"ipmi"* ]]; then
        echo "Remove ipmi permissions from user ${USER_NAME}"
        /usr/bin/hw-management-dbus-if.sh user_manager_set_groups "${USER_NAME}" "hostconsole" "ssh" "redfish"
        user_groups=$(/usr/bin/hw-management-dbus-if.sh user_manager_get_groups "${USER_NAME}")
        if [[ "$user_groups" == *"ipmi"* ]]; then
            echo "Failed to remove ipmitool permissions from ${USER_NAME}, permissions are $user_groups"
            return 1
        fi
        return  0
    else
        echo "${USER_NAME} doesn't have ipmi permissions"
        return 0
    fi
}

create_nosbmc_user()
{
   USER_NAME="yormnAnb"
   NEW_PASSWORD="ABYX12#14artb51"
   CHANNEL=1
   user_groups=$(/usr/bin/hw-management-dbus-if.sh user_manager_get_groups "${USER_NAME}" 2>/dev/null)
   if [ $? -eq 0 ] && [ -n "$user_groups" ]; then
     echo "${USER_NAME} already exists"
	 # User alreay exists, remove ipmi permissions if have.
     if remove_ipmitools_permissions ${USER_NAME}; then
	    return 0
	 else
	    return 1
	 fi
   else
     echo "Creating user ${USER_NAME}"
	 # Create user with ipmi permissions, so we can use ipmitools to change password, then will remove ipmi permissions.
     /usr/bin/hw-management-dbus-if.sh user_manager_create_user "$USER_NAME" 4 '{"ipmi","redfish","ssh","hostconsole"}' "priv-admin" true
	 sleep 2
     # Verify user creation.
     USER_ID=$(ipmitool user list $CHANNEL | awk -v user="$USER_NAME" '$2 == user {print $1}')
     if [ -z "$USER_ID" ]; then
       echo "Error: Failed to create user '$USER_NAME'."
       return 1
	 fi
     echo "User '$USER_NAME' created successfully with User ID: $USER_ID"
     # Change the password for the new user
     ipmitool user set password $USER_ID $NEW_PASSWORD
     if [ $? -eq 0 ]; then
       echo "Password for user '$USER_NAME' (ID: $USER_ID) changed successfully."
       if remove_ipmitools_permissions ${USER_NAME}; then
	      return 0
	   else
	      return 1
	   fi
     else
       echo "Error: Failed to change password for user '$USER_NAME'."
       return 2
     fi
   fi
}
