#!/bin/bash

#
# Copyright 2019 Cumulus Networks, Inc.
# All rights reserved.
#

#
# This script is used to check if the mlx-hw-management package can be
# loaded on the mellanox switch.
#

#
# Get the platform detect string; The second part of the string
# is platform name

MYPLATFORM=""
SUDO=''
PDETECT="/usr/bin/platform-detect"

#
# Are we running as root or sudo
#
if ((EUID != 0)); then
    SUDO='sudo'
fi

if [ -f $PDETECT ]; then
    MYPLATFORM=$($SUDO platform-detect)
        if [[ $MYPLATFORM == "" ]]; then
            echo "platform name is empty"
            exit 1
        fi
else
    echo "Unable to detect platform; Bailing out"
    exit 2
fi

platformname=$($SUDO platform-detect| awk -F"," '{print $2}')

#
# Check if the platform detect string platform name has an _
#
match1=''
if [[ $platformname == *[_]* ]]
then
    match1="$(echo "$platformname"| awk -F'_' '{print $2}')"
else
    match1=$platformname
fi

#
# Get the dmidecode output
#
match2=''
prodname=$($SUDO dmidecode -t1 |
    awk -F' ' '/Product Name: /{gsub(/"/,""); print $3}')
if [[ $prodname == *[-]* ]]
then
    match2="$(echo "$prodname"| awk -F"-" '{print $1}')"
else
    match2="$prodname"
fi

#
#
#
shopt -s nocasematch
case "$match1" in
    "$match2" )
        echo "The System DMI information is correctly programmed. "
        echo "It is safe to install Cumulus Linux 4.x ";;
    *)
        echo "System DMI information is not programmed correctly."
        echo "Contact support. Do not attempt to install Cumulus Linux 4.x ";;
esac
