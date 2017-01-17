#
# Copyright (C) 2010-2015, Mellanox Technologies Ltd.  ALL RIGHTS RESERVED.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
#
#

#!/bin/bash
#

### BEGIN INIT INFO
# Provides:          simple thermal control algorithm
# Short-Description: basic thermal control algorithm system for Mellanox TOR systems
#
# Accepts two input parameters:
#     - parameter 1 ($1) - speed setting in percent (default is 60)
#     - parameter 2 ($2) - polling interval in seconds (default is 15)
#
# Notes:
#     - FAN speed shoulf not be set below 60%
#     - Temperature >= 100000 (in milliCelsius) is considered as critical
#     - Temperature <=   6000 (in milliCelsius) is considered as normal
#    -  Temperature above 65000 (in milliCelsius) is considered as maximum, and
#        when this threshold is reached - fan speed should be handled incrementally
#    - Default setting for FAN speed increment/decrement is 5 percent
#    - All FAN are controlled by shared PWM, so setting any FAN will impact others
#
#     fan[1-*]_enable - RW software state for Fan speed control method:
#     0     - no fan speed control (i.e. fan at full speed)
#     1     - manual fan speed control enabled (using pwm[1-*] == fan[1-*]_speed_set)
#     other - automatic fan speed control enabled
#
# Algorithms following the below rules:
# Rule 1: do nothing if there are no fan
# Rule 2: if any fan is missed  - set fan to 100% (if they were not set to 100% before)
# Rule 3: if asic temperature > critical_temp  - set fan to 100% (if they were not set to 100% before)
# Rule 4: if asic temperature > max_temp  - increase fan speed by speed_increment% (but <= 100)
# Rule 5: if temperature went down below temp_back_to_normal - decrease speed by
#              speed_increment percent (but >= speed_normal)
# Rule 6: if all fan are presented, temperature is in valid range, but interrupt counter has been changed
#              from last run -  set all fan to default speed
### END INIT INFO


. /lib/lsb/init-functions

thermal_watch_exit()
{
    if [ -f /var/run/thermal/zone1 ]; then
        rm -rf /var/run/thermal/zone1
    fi

    echo "Application thermal_watch is terminated (PID=$thermal_watch_pid)"
    exit 1
}

# Trap the signals
echo  $SIGTERM $SIGHUP $SIGKILL $SIGABRT $SIGQUIT $SIGINT $SIGTRAP
trap 'thermal_watch_exit' 2 9 15

# Initialization during start up
thermal_watch_pid=$$
if [ -f /var/run/thermal/zone1 ]; then
    zone1=`cat /var/run/thermal/zone1`
    if [ -d /proc/$zone1 ]; then
        echo Thermal is already running
        exit 0
    fi
fi
if [ ! -d /var/run/thermal ]; then
    mkdir -p /var/run/thermal
fi

echo $thermal_watch_pid > /var/run/thermal/zone1
echo "Application thermal_watch is started (PID=$thermal_watch_pid)"

i=0;
max_temp=85000
critical_temp=100000
temp_back_to_normal=75000
num_fan=0
num_fan_drwr=0
num_fan_per_drwr=2
fan_ctrl_enable=2
speed_increment=13    #  5 * 255/100
speed_normal=153      # 60 * 255/100
set_speed_default=153 # 60 * 255/100
prev_irq_counter=0
irq_counter=0
sleep_time_default=15

set_speed=${1:-$set_speed_default}
sleep_time=${2:-$sleep_time_default}
speed_normal=${1:-$set_speed_default}

# Collect number of fan in thermal zone and set them to initial speed
j=1
k=1
for f in /bsp/module/fan*_status; do
   num_fan_drwr=$(($num_fan_drwr+1))
   num_fan=$(($num_fan+$num_fan_per_drwr))
   present_fan=`cat /bsp/module/fan"$j"_status`
   if [ "$present_fan" = "1" ]; then
       echo $set_speed > /bsp/fan/fan"$k"_speed_set
       echo $fan_ctrl_enable > /bsp/fan/fan"$k"_enable
       k=$(($k+1))
       echo $set_speed > /bsp/fan/fan"$k"_speed_set
       echo $fan_ctrl_enable > /bsp/fan/fan"$k"_enable
   fi
   j=$(($j+1))
   k=$(($k+1))
done

while [ ${i} -eq 0 ]
do
    # Rule 1: do nothing if there are no fan
    # Rule 2: if any fan is missed  - set fan to 100% (if they were not set to 100% before)
    # Rule 3: if asic temperature > critical_temp  - set fan to 100% (if they were not set to 100% before)
    # Rule 4: if asic temperature > max_temp  - increase fan speed by speed_increment% (but <= 100)
    # Rule 5: if temperature went down below temp_back_to_normal - decrease speed by speed_increment percent (but >= speed_normal)
    # Rule 6: if all fan are presented, temperature is in valid range, but interrupt counter has been changed from last run -
    #         set all fan to default speed

    /bin/sleep $sleep_time

    # Collect current chassis interrupt counter - possible some has been in/out after last loop
    irq_counter_core1=`cat /proc/interrupts | /bin/grep 'chassis' | awk '{print $2}'`
    irq_counter_core2=`cat /proc/interrupts | /bin/grep 'chassis' | awk '{print $3}'`
    if [ ${irq_counter_core1:-null} = null ]; then
        irq_counter_core1=0
    fi
    if [ ${irq_counter_core2:-null} = null ]; then
        irq_counter_core2=0
    fi
    irq_counter=$(($irq_counter_core1+$irq_counter_core2))
    present_fan=0
    asic_temp=0

    # Collect current number of presented fan
    j=1
    while [ $j -le $num_fan_drwr ]; do
        arr[$j]=`cat /bsp/module/fan"$j"_status`
        present_fan=$((${arr[$j]}+$present_fan))
        j=$(($j+1))
    done

    # Rule 1
    if [ "$present_fan" = "0" ]; then
        continue
    fi

    temp=`cat /bsp/thermal/asic`
    asic_temp=$((asic_temp+$temp))
    if [ $present_fan -lt $num_fan_drwr ] || [ $asic_temp -gt $critical_temp ]; then
        # Rule 2 & 3
        if [ "$set_speed" -eq 100 ]; then
            continue
        fi

        j=1
        while [ $j -le $num_fan ]; do
            if [ "${arr[$j]}" = "1" ]; then
                echo 100 > /bsp/fan/fan"$j"_speed_set
            fi
            j=$(($j+1))
        done
        set_speed=100
        continue
    fi

    if [ $asic_temp -ge $max_temp ]; then
        # Rule 4
        set_speed=$(($set_speed + $speed_increment))
        set_speed=$(($set_speed % 100))
        j=1
        while [ $j -le $num_fan ]; do
            if [ "${arr[$j]}" = "1" ]; then
                echo 100 > /bsp/fan/fan"$j"_speed_set
                break
            fi
            j=$(($j+1))
        done
        set_speed=100
    else
        if [ $asic_temp -le $temp_back_to_normal ] && [ $set_speed -gt $speed_normal ]; then
            # Rule 5
            set_speed=$(($set_speed - $speed_increment))
            if [ $set_speed -lt $speed_normal ]; then
                set_speed=$speed_normal
            fi
            j=1
            while [ $j -le $num_fan ]; do
                if [ "${arr[$j]}" = "1" ]; then
                    echo $set_speed > /bsp/fan/fan"$j"_speed_set
                    break
                fi
                j=$(($j+1))
            done
        elif [ $irq_counter -ne $prev_irq_counter ]; then
            # Rule 6
            set_speed=$speed_normal
            j=1
            while [ $j -le $num_fan ]; do
                if [ "${arr[$j]}" = "1" ]; then
                    echo $set_speed > /bsp/fan/fan"$j"_speed_set
                    break
                fi
                j=$(($j+1))
            done
        fi
    fi
    prev_irq_counter=$irq_counter
done

