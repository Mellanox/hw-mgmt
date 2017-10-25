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
  if [ ! -d /bsp/thermal_zone ]; then
      mkdir -p /bsp/thermal_zone/
  fi
  if [ ! -d /bsp/environment ]; then
      mkdir -p /bsp/environment/
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
  if [ ! -d /bsp/leds ]; then
      mkdir -p /bsp/leds/
  fi
  if [ ! -d /bsp/qsfp ]; then
      mkdir -p /bsp/qsfp
  fi
  if [ ! -d /bsp/module ]; then
      mkdir -p /bsp/module
  fi
  if [ "$2" == "board_amb" ] || [ "$2" == "port_amb" ]; then
    ln -sf $3$4/temp1_input /bsp/thermal/$2
    ln -sf $3$4/temp1_max /bsp/thermal/$2_max
    ln -sf $3$4/temp1_max_hyst /bsp/thermal/$2_hyst
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
  if [ "$2" == "a2d" ]; then
    ln -sf $3$4/in_voltage-voltage_scale /bsp/environment/$2_$5_voltage_scale
    for i in {1..12}; do
      if [ -f $3$4/in_voltage"$i"_raw ]; then
        ln -sf $3$4/in_voltage"$i"_raw /bsp/environment/$2_$5_raw_"$i"
      fi
    done
  fi
  if [ "$2" == "voltmon1" ] || [ "$2" == "voltmon2" ]; then
    ln -sf $3$4/in1_input /bsp/environment/$2_in1_input
    ln -sf $3$4/in2_input /bsp/environment/$2_in2_input
    ln -sf $3$4/curr2_input /bsp/environment/$2_curr2_input
    ln -sf $3$4/power2_input /bsp/environment/$2_power2_input
    ln -sf $3$4/in3_input /bsp/environment/$2_in2_input
    ln -sf $3$4/curr3_input /bsp/environment/$2_curr3_input
    ln -sf $3$4/power3_input /bsp/environment/$2_power3_input
  fi
  if [ "$2" == "asic" ]; then
    ln -sf $3$4/temp1_input /bsp/thermal/$2
    ln -sf $3$4/temp1_highest /bsp/thermal/$2_highest
  fi
  if [ "$2" == "fan" ]; then
    # Take time for adding infrastructure
    sleep 3
    for i in {1..12}; do
        if [ -f $3$4/fan"$i"_input ]; then
            ln -sf $3$4/fan"$i"_input /bsp/fan/fan"$i"_speed_get
            ln -sf $3$4/pwm1 /bsp/fan/fan"$i"_speed_set
            ln -sf /bsp/config/fan_min_speed /bsp/fan/fan"$i"_min
            ln -sf /bsp/config/fan_max_speed /bsp/fan/fan"$i"_max
        fi
    done
  fi
  if [ "$2" == "qsfp" ]; then
    # Take time for adding infrastructure
    sleep 5
    for i in {1..64}; do
        if [ -f $3$4/qsfp$i ]; then
            ln -sf $3$4/qsfp$i /bsp/qsfp/qsfp"$i"
            ln -sf $3$4/qsfp"$i"_status /bsp/qsfp/qsfp"$i"_status
        fi
    done
  fi
  if [ "$2" == "eeprom_vpd" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/vpd_info 2>/dev/null
  fi
  if [ "$2" == "eeprom_cpu" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/cpu_info 2>/dev/null
  fi
  if [ "$2" == "eeprom_psu1" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/psu1_info 2>/dev/null
  fi
  if [ "$2" == "eeprom_psu2" ]; then
    ln -sf $3$4/eeprom /bsp/eeprom/psu2_info 2>/dev/null
  fi
  if [ "$2" == "eeprom_fan1" ]; then
    if [ -f $3$4/eeprom ]; then
      ln -sf $3$4/eeprom /bsp/eeprom/fan1_info 2>/dev/null
    fi
  fi
  if [ "$2" == "eeprom_fan2" ]; then
    if [ -f $3$4/eeprom ]; then
      ln -sf $3$4/eeprom /bsp/eeprom/fan2_info 2>/dev/null
    fi
  fi
  if [ "$2" == "eeprom_fan3" ]; then
    if [ -f $3$4/eeprom ]; then
      ln -sf $3$4/eeprom /bsp/eeprom/fan3_info 2>/dev/null
    fi
  fi
  if [ "$2" == "eeprom_fan4" ]; then
    if [ -f $3$4/eeprom ]; then
      ln -sf $3$4/eeprom /bsp/eeprom/fan4_info 2>/dev/null
    fi
  fi
  if [ "$2" == "eeprom_fan5" ]; then
    if [ -f $3$4/eeprom ]; then
      ln -sf $3$4/eeprom /bsp/eeprom/fan5_info 2>/dev/null
    fi
  fi
  if [ "$2" == "eeprom_fan6" ]; then
    if [ -f $3$4/eeprom ]; then
      ln -sf $3$4/eeprom /bsp/eeprom/fan6_info 2>/dev/null
    fi
  fi
  if [ "$2" == "led" ]; then
    name=`echo $5 | cut -d':' -f2`
    color=`echo $5 | cut -d':' -f3`
    ln -sf $3$4/brightness /bsp/leds/led_"$name"_"$color"
    echo timer > $3$4/trigger
    ln -sf $3$4/delay_on  /bsp/leds/led_"$name"_"$color"_delay_on
    ln -sf $3$4/delay_off /bsp/leds/led_"$name"_"$color"_delay_off

    if [ ! -f /bsp/leds/led_"$name"_capability ]; then
      echo none blink ${color} > /bsp/leds/led_"$name"_capability
    else
      capability=`cat /bsp/leds/led_"$name"_capability`
      capability="${capability} ${color}"
      echo $capability > /bsp/leds/led_"$name"_capability
    fi
  fi
  if [ "$2" == "thermal_zone" ]; then
    busfolder=`basename $3$4`
    zonename=`echo $5`
    zonetype=`cat $3$4/type`
    if [ "$zonetype" == "mlxsw" ]; then
      # Disable thermal algorithm
      echo disabled > $3$4/mode
      # Set default fan speed
      echo 6 > $3$4/cdev0/cur_state
      zone=$zonetype
    else
       zone=$zonename-$zonetype
    fi
    mkdir -p /bsp/thermal_zone/$zone
    ln -sf $3$4/mode /bsp/thermal_zone/$zone/mode
    for i in {0..11}; do
      if [ -f $3$4/trip_point_"$i"_temp ]; then
        ln -sf $3$4/trip_point_"$i"_temp /bsp/thermal_zone/$zone/trip_point_$i
      fi
      if [ -d $3$4/cdev"$i" ]; then
        ln -sf $3$4/cdev"$i"/cur_state /bsp/thermal_zone/$zone/cooling"$i"_current_state
      fi
    done
  fi
  if [ "$2" == "cputemp" ]; then
    for i in {1..9}; do
      if [ -f $3$4/temp"$i"_input ]; then
        if [ $i -eq 1 ]; then
           name="pack"
        else
           id=$(($i-1))
           name="core$id"
        fi
        ln -sf $3$4/temp"$i"_input /bsp/thermal/cpu_$name
        ln -sf $3$4/temp"$i"_crit /bsp/thermal/cpu_"$name"_crit
        ln -sf $3$4/temp"$i"_crit_alarm /bsp/thermal/cpu_"$name"_crit_alarm
        ln -sf $3$4/temp"$i"_max /bsp/thermal/cpu_"$name"_max
      fi
    done
  fi
  if [ "$2" == "hotplug" ]; then
    for i in {1..12}; do
	if [ -f $3$4/fan$i ]; then
            ln -sf $3$4/fan$i /bsp/module/fan"$i"_status
        fi
    done
    for i in {1..2}; do
	if [ -f $3$4/psu$i ]; then
            ln -sf $3$4/psu$i /bsp/module/psu"$i"_status
        fi
	if [ -f $3$4/pwr$i ]; then
            ln -sf $3$4/pwr$i /bsp/module/psu"$i"_pwr_status
        fi
    done
  fi
elif [ "$1" == "change" ]; then
    echo "Do nothing on change"
else
  if [ "$2" == "board_amb" ] || [ "$2" == "port_amb" ]; then
    unlink /bsp/thermal/$2
    unlink /bsp/thermal/$2_max
    unlink /bsp/thermal/$2_hyst
  fi
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
  if [ "$2" == "a2d" ]; then
    unlink /bsp/environment/$2_$5_voltage_scale
    for i in {1..12}; do
      if [ -L /bsp/environment/$2_$5_raw_"$i" ]; then
        unlink /bsp/environment/$2_$5_raw_"$i"
      fi
    done
  fi
  if [ "$2" == "voltmon1" ] || [ "$2" == "voltmon2" ]; then
    unlink /bsp/environment/$2_in1_input
    unlink /bsp/environment/$2_in2_input
    unlink /bsp/environment/$2_curr2_input
    unlink /bsp/environment/$2_power2_input
    unlink /bsp/environment/$2_in2_input
    unlink /bsp/environment/$2_curr3_input
    unlink /bsp/environment/$2_power3_input
  fi
  if [ "$2" == "asic" ]; then
    unlink /bsp/thermal/$2
    unlink /bsp/thermal/$2_highest
  fi
  if [ "$2" == "fan" ]; then
    for i in {1..12}; do
	if [ -L /bsp/fan/fan"$i"_speed_get ]; then
            unlink /bsp/fan/fan"$i"_speed_get
        fi
	if [ -L /bsp/fan/fan"$i"_speed_set ]; then
            unlink /bsp/fan/fan"$i"_speed_set
        fi
	if [ -L /bsp/fan/fan"$i"_min ]; then
            unlink /bsp/fan/fan"$i"_min
        fi
	if [ -L /bsp/fan/fan"$i"_max ]; then
            unlink /bsp/fan/fan"$i"_max
        fi
    done
  fi
  if [ "$2" == "qsfp" ]; then
    for i in {1..64}; do
        if [ -L /bsp/qsfp/qsfp$i ]; then
            unlink /bsp/qsfp/qsfp"$i"
        fi
        if [ -L /bsp/qsfp/qsfp"$i"_status ]; then
            unlink /bsp/qsfp/qsfp"$i"_status
        fi
    done
  fi
  if [ "$2" == "eeprom_psu1" ]; then
    unlink /bsp/eeprom/psu1_info
  fi
  if [ "$2" == "eeprom_psu2" ]; then
    unlink /bsp/eeprom/psu2_info
  fi
  if [ "$2" == "eeprom_fan1" ]; then
    unlink /bsp/eeprom/fan2_info
  fi
  if [ "$2" == "eeprom_fan2" ]; then
    unlink /bsp/eeprom/fan2_info
  fi
  if [ "$2" == "eeprom_fan3" ]; then
    unlink /bsp/eeprom/fan3_info
  fi
  if [ "$2" == "eeprom_fan4" ]; then
    unlink /bsp/eeprom/fan4_info
  fi
  if [ "$2" == "eeprom_vpd" ]; then
    unlink /bsp/eeprom/vpd_info
  fi
  if [ "$2" == "eeprom_cpu" ]; then
    unlink /bsp/eeprom/cpu_info
  fi
  if [ "$2" == "led" ]; then
    name=`echo $5 | cut -d':' -f2`
    color=`echo $5 | cut -d':' -f3`
    unlink /bsp/leds/led_"$name"_"$color"
    unlink /bsp/leds/led_"$name"_"$color"_delay_on
    unlink /bsp/leds/led_"$name"_"$color"_delay_off
    if [ -f /bsp/leds/led_"$name"_capability ]; then
    rm -rf /bsp/leds/led_"$name"_capability
    fi
  fi
  if [ "$2" == "thermal_zone" ]; then
    zonefolder=`basename /bsp/thermal_zone/$5*`
    if [ ! -d /bsp/thermal_zone/$zonefolder ]; then
        zonefolder=mlxsw
    fi
    if [ -d /bsp/thermal_zone/$zonefolder ]; then
      unlink /bsp/thermal_zone/$zonefolder/mode
      for i in {0..11}; do
        if [ -L /bsp/thermal_zone/$zonefolder/trip_point_$i ]; then
          unlink /bsp/thermal_zone/$zonfoldere/trip_point_$i
        fi
        if [ -L /bsp/thermal_zone/$zonefolder/cooling"$i"_current_state ]; then
          unlink /bsp/thermal_zone/$zonefolder/cooling"$i"_current_state
        fi
      done
      unlink /bsp/thermal_zone/$zonefolder/*
      rm -rf /bsp/thermal_zone/$zonefolder
    fi
  fi
  if [ "$2" == "cputemp" ]; then
    unlink /bsp/thermal/cpu_pack
    unlink /bsp/thermal/cpu_pack_crit
    unlink /bsp/thermal/cpu_pack_crit_alarm
    unlink /bsp/thermal/cpu_pack_max
    for i in {1..8}; do
      if [ -L /bsp/thermal/cpu_core"$i" ]; then
        unlink /bsp/thermal/cpu_core"$i"
        unlink /bsp/thermal/cpu_core"$i"_crit
        unlink /bsp/thermal/cpu_core"$i"_crit_alarm
        unlink /bsp/thermal/cpu_core"$i"_max
      fi
    done
  fi
  if [ "$2" == "hotplug" ]; then
    for i in {1..12}; do
	if [ -L /bsp/module/fan"$i"_status ]; then
            unlink /bsp/module/fan"$i"_status
        fi
    done
    for i in {1..2}; do
	if [ -L /bsp/module/psu"$i"_status ]; then
            unlink /bsp/module/psu"$i"_status
        fi
	if [ -L /bsp/module/psu"$i"_pwr_status ]; then
            unlink /bsp/module/psu"$i"_pwr_status
        fi
    done
  fi
fi
