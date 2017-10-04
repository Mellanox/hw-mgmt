#!/bin/bash

if [ "$1" == "cpld" ]; then
	if [ "$2" == "mgmt" ]; then
		/usr/sbin/iorw -b 0x2500 -r -l1 | awk '{print $5}'
	elif [ "$2" == "brd" ]; then
		/usr/sbin/iorw -b 0x2501 -r -l1 | awk '{print $5}'
	elif [ "$2" == "brd" ]; then
		sudo /usr/bin/mlxreg -d /dev/mst/mt52100_pciconf0 --get --reg_id 0x902A --reg_len 16 | tail -n4 | head -n1 | awk '{print $3}'
	fi
fi

if [ "$1" == "system" ]; then
	if [ "$2" == "mgmt" ]; then
		/usr/sbin/iorw -b 0x2500 -r -l1 | awk '{print $5}'
	elif [ "$2" == "brd" ]; then
		/usr/sbin/iorw -b 0x2501 -r -l1 | awk '{print $5}'
	elif [ "$2" == "brd" ]; then
		sudo /usr/bin/mlxreg -d /dev/mst/mt52100_pciconf0 --get --reg_id 0x902A --reg_len 16 | tail -n4 | head -n1 | awk '{print $3}'
	fi
fi
