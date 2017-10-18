#!/bin/bash

########################################################################
# Copyright (c) 2017 Mellanox Technologies.
# Copyright (c) 2017 Vadim Pasternak <vadimp@mellanox.com>
#
# Licensed under the GNU General Public License Version 2
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# echo $1 and $2 and $3 and $4 and $5 >> /root/msg.txt
if [ "$1" == "add" ]; then
  if [ ! -d /bsp/thermal ]; then
      mkdir -p /bsp/thermal/
  fi
  if [ ! -d /bsp/power ]; then
      mkdir -p /bsp/power
  fi
  if [ ! -d /bsp/fan ]; then
      mkdir -p /bsp/fan/
  fi
  if [ ! -d /bsp/eeprom ]; then
      mkdir -p /bsp/eeprom/
  fi
  if [ "$2" == "psu1" ] || [ "$2" == "psu2" ]; then
    ln -sf $5$3/temp1_input /bsp/thermal/$2
    ln -sf $5$3/temp1_max /bsp/thermal/$2_max
    ln -sf $5$3/temp1_max_alarm /bsp/thermal/$2_alarm
    ln -sf $5$3/in1_input /bsp/power/$2_volt_in
    ln -sf $5$3/in2_input /bsp/power/$2_volt
    ln -sf $5$3/power1_input /bsp/power/$2_power_in
    ln -sf $5$3/power2_input /bsp/power/$2_power
    ln -sf $5$3/curr1_input /bsp/power/$2_curr_in
    ln -sf $5$3/curr2_input /bsp/power/$2_curr
    ln -sf $5$3/fan1_input /bsp/fan/$2_fan_input
    #FAN speed set
    busdir=`echo $5$3 |xargs dirname |xargs dirname`
    busfolder=`basename $busdir`
    bus="${busfolder:0:${#busfolder}-5}"
    if [ "$2" == "psu1" ]; then
      i2cset -f -y $bus 0x59 0x3b 0x3c 0x00 0xbc i
    else
      i2cset -f -y $bus 0x58 0x3b 0x3c 0x00 0x90 i
    fi
  fi
  if [ "$2" == "eeprom_vpd" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/vpd_info 2>/dev/null
  fi
  if [ "$2" == "eeprom_cpu" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/cpu_info 2>/dev/null
  fi
  if [ "$2" == "eeprom_psu1" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/psu1_eeprom 2>/dev/null
  fi
  if [ "$2" == "eeprom_psu2" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/psu2_eeprom 2>/dev/null
  fi
  if [ "$2" == "eeprom_fan1" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/fan1_eeprom 2>/dev/null
  fi
  if [ "$2" == "eeprom_fan2" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/fan2_eeprom 2>/dev/null
  fi
  if [ "$2" == "eeprom_fan3" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/fan3_eeprom 2>/dev/null
  fi
  if [ "$2" == "eeprom_fan4" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/fan4_eeprom 2>/dev/null
  fi
else
  if [ "$2" == "psu1" ] || [ "$2" == "psu2" ]; then
    unlink /bsp/thermal/$2
    unlink /bsp/thermal/$2_max
    unlink /bsp/thermal/$2_alarm
    unlink /bsp/power/$2_volt_in
    unlink /bsp/power/$2_volt
    unlink /bsp/power/$2_power_in
    unlink /bsp/power/$2_power
    unlink /bsp/power/$2_curr_in
    unlink /bsp/power/$2_curr
    unlink /bsp/fan/$2_fan_input
  fi
  if [ "$2" == "eeprom_psu1" ]; then
    unlink /bsp/eeprom/psu1_eeprom
  fi
  if [ "$2" == "eeprom_psu2" ]; then
    unlink /bsp/eeprom/psu2_eeprom
  fi
  if [ "$2" == "eeprom_fan1" ]; then
    unlink /bsp/eeprom/fan2_eeprom
  fi
  if [ "$2" == "eeprom_fan2" ]; then
    unlink /bsp/eeprom/fan2_eeprom
  fi
  if [ "$2" == "eeprom_fan3" ]; then
    unlink /bsp/eeprom/fan3_eeprom
  fi
  if [ "$2" == "eeprom_fan4" ]; then
    unlink /bsp/eeprom/fan4_eeprom
  fi
fi
