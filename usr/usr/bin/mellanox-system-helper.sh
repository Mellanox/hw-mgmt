#!/bin/bash

if echo "$0" | grep -q "/cpld" ; then
	if [ "$1" == "mgmt" ]; then
		ver=`/usr/sbin/iorw -b 0x2500 -r -l1 | awk '{print $5}'`
	elif [ "$1" == "brd" ]; then
		ver=`/usr/sbin/iorw -b 0x2501 -r -l1 | awk '{print $5}'`
	elif [ "$1" == "port" ]; then
		ver=0
		if [ -f /dev/mst/mt52100_pciconf0 ]; then
			ver=`sudo /usr/bin/mlxreg -d /dev/mst/mt52100_pciconf0 --get --reg_id 0x902A --reg_len 16 | tail -n4 | head -n1 | awk '{print $3}'`
		fi
	fi
	echo $(($ver))
	exit 0
fi

if echo "$0" | grep -q "/pwr_consum" ; then
	/usr/sbin/iorw -b 0x2533 -w -l1 -v0xbf
	regval=`/usr/sbin/iorw -b 0x2532 -r -l1 | awk '{print $5}'`

	if [ "$1" == "psu1" ]; then
		regnew=`echo $(($regval | 0x40))`
	elif [ "$1" == "psu2" ]; then
		regnew=`echo $(($regval & 0xbf))`
	fi

	/usr/sbin/iorw -b 0x2532 -w -l1 -v$regnew
	iioreg=`cat /bsp/environment/a2d_iio\:device1_raw_1`
	echo $(($iioreg * 80 * 12))
	exit 0
fi

if echo "$0" | grep -q "/pwr_sys" ; then
	if [ "$1" == "psu1" ]; then
		iioreg_vin=`cat /bsp/environment/a2d_iio\:device0_raw_1`
		iioreg_iin=`cat /bsp/environment/a2d_iio\:device0_raw_6`
	elif [ "$1" == "psu2" ]; then
		iioreg_vin=`cat /bsp/environment/a2d_iio\:device0_raw_2`
		iioreg_iin=`cat /bsp/environment/a2d_iio\:device0_raw_7`
	fi

	echo $(($iioreg_vin * $iioreg_iin * 59 * 80))
	exit 0
fi

