#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2020-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

# Description: hw-management pre execution script.
#              Checks if service is already running. Just in case, it should
#              be done internally by systemd.
#              Check if by some reason /var/run/hw-management exist.
#              If yes, remove it.
#              Waits in loop until hw-management service can be started.
#              Report start of hw-management service to console and logger.

source hw-management-helpers.sh
[ -f "$board_type_file" ] && board_type=$(< $board_type_file) || board_type="Unknown"
[ -f "$sku_file" ] && product_sku=$(< $sku_file) || product_sku="Unknown"

if systemctl is-active --quiet hw-management; then
        echo "Error: HW management service is already active."
        logger -t hw-management -p daemon.error "HW management service is already active."
        exit 1
fi

if [ -d /var/run/hw-management ]; then
	rm -fr /var/run/hw-management
fi

#TEMPORARY hw-management mockup values for simx
if check_simx && [ "$product_sku" == "HI180" ]; then
	echo "N6100_LD emulation, exiting"
	exit 0
fi

#TEMPORARY hw-management mockup values for simx
if check_simx && [ "$product_sku" == "HI181" ]; then
	echo "SN5810_LD emulation, exiting"
	exit 0
fi

#TEMPORARY hw-management mockup values for simx
if check_simx && [ "$product_sku" == "HI183" ]; then
	echo "SN6810_LD emulation, exiting"
	exit 0
fi

#TEMPORARY hw-management mockup values for simx
if check_simx && [ "$product_sku" == "HI185" ]; then
	echo "N6300_LD emulation, exiting"
	exit 0
fi

#TEMPORARY hw-management mockup values for simx
if check_simx && [ "$product_sku" == "HI187" ]; then
	echo "SN6800_LD emulation, exiting"
	exit 0
fi

#TEMPORARY hw-management mockup values for simx
if check_simx && [ "$product_sku" == "HI193" ]; then
	echo "SN6600_LD emulation, exiting"
	exit 0
fi
	
#TEMPORARY hw-management mockup values for simx
if check_simx && [ "$product_sku" == "HI194" ]; then
	echo "N7200_LD emulation, exiting"
	exit 0
fi

#TEMPORARY hw-management mockup values for simx
if check_simx && [ "$product_sku" == "HI199" ]; then
	echo "N7300_LD emulation, exiting"
	exit 0
fi

#TEMPORARY hw-management mockup values for simx
if check_simx && [ "$product_sku" == "HI200" ]; then
	echo "N7400_LD emulation, exiting"
	exit 0
fi

#TEMPORARY hw-management mockup values for simx
if check_simx && [ "$product_sku" == "HI201" ]; then
	echo "N8100_LD emulation, exiting"
	exit 0
fi

#TEMPORARY hw-management mockup values for simx
if check_simx && [ "$product_sku" == "HI203" ]; then
	echo "SN7600_LD emulation, exiting"
	exit 0
fi

case $board_type in
VMOD0014)
	if [ ! -d /sys/devices/pci0000:00/0000:00:1f.0/NVSN2201:00/mlxreg-hotplug/hwmon ]; then
		timeout 180 bash -c 'until [ -d /sys/devices/pci0000:00/0000:00:1f.0/NVSN2201:00/mlxreg-hotplug/hwmon ]; do sleep 0.2; done'
	fi
	;;
*)
	arch=$(uname -m)
	if [ "$arch" = "aarch64" ]; then
		plat_path=/sys/devices/platform/MLNXBF49:00
	else
		plat_path=/sys/devices/platform/mlxplat
	fi
	if [ -d ${plat_path}/mlxreg-hotplug ]; then
		if [ ! -d ${plat_path}/mlxreg-hotplug/hwmon ]; then
			export plat_path
			timeout 180 bash -c 'until [ -d ${plat_path}/mlxreg-hotplug/hwmon ]; do sleep 0.2; done'
		fi
	elif [ ! -d ${plat_path}/mlxreg-io/hwmon ]; then
		export plat_path
		timeout 180 bash -c 'until [ -d ${plat_path}/mlxreg-io/hwmon ]; do sleep 0.2; done'
	fi
	;;
esac
echo "Start Chassis HW management service."
logger -t hw-management -p daemon.notice "Start Chassis HW management service."
