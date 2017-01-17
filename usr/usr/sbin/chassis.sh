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
# chassis.sh - chassis management tool
#

modprobe_module()
{
    module=$1
    lsmod | grep -q $module
    if [ $? -ne 0 ]; then
        modprobe $module
    fi
}

rmmod_module()
{
    module=$1
    lsmod | grep -q $module
    if [ $? -eq 0 ]; then
        i=0
        while [ $i -lt 3 ]
        do
            refcntfile=/sys/module/${module}/refcnt
            refcnt=$(cat $refcntfile)
            if [ $refcnt -eq 0 ]; then
                rmmod $module
                if [ $? -eq 0 ]; then
                    break
                fi
            fi
            let "i+=1"
            sleep 1
        done
    fi
}

init()
{
    modprobe_module i2c-mux
    modprobe_module lpci2c
    modprobe_module mlnx-mux-drv
    modprobe_module mlnx-cpld-drv
    modprobe_module mlnx-asic-drv
    modprobe_module mlnx-a2d-drv
    modprobe_module pmbus_core
    modprobe_module pmbus
    modprobe_module ucd9200
    modprobe_module coretemp
    modprobe_module lm75
    modprobe_module at24 io_limit=32
}

deinit()
{
    rmmod_module at24
    rmmod_module lm75
    rmmod_module coretemp
    rmmod_module pmbus
    rmmod_module ucd9200
    rmmod_module pmbus_core
    rmmod_module mlnx-a2d-drv
    rmmod_module mlnx-asic-drv
    rmmod_module mlnx-cpld-drv
    rmmod_module mlnx-mux-drv
    rmmod_module lpci2c
    rmmod_module i2c-mux
}

connect()
{
    if [ ! -d $cpld ]; then
        echo mlnx-cpld-drv 0x60 > /sys/bus/i2c/devices/i2c-2/new_device
    fi
    if [ ! -d $asic ]; then
        echo mlnx-asic-drv 0x48 > /sys/bus/i2c/devices/i2c-2/new_device
    fi
    if [ ! -d $ucd_1 ]; then
        echo ucd9200 0x27 > /sys/bus/i2c/devices/i2c-5/new_device
    fi
    if [ ! -d $ucd_2 ]; then
        echo ucd9200 0x41 > /sys/bus/i2c/devices/i2c-5/new_device
    fi
    if [ ! -d $a2d_1 ]; then
        echo mlnx-a2d-swb-drv 0x6d > /sys/bus/i2c/devices/i2c-5/new_device
    fi
    if [ ! -d $lm75_1 ]; then
        echo lm75 0x4a > /sys/bus/i2c/devices/i2c-7/new_device
    fi
    if [ ! -d $sys_eeprom ]; then
        echo 24c32 0x51 > /sys/bus/i2c/devices/i2c-8/new_device
    fi
    if [ ! -d $a2d_2 ]; then
        echo mlnx-a2d-mnb-drv 0x6d > /sys/bus/i2c/devices/i2c-15/new_device
    fi
    if [ ! -d $cpu_eeprom ]; then
        echo 24c32 0x51 > /sys/bus/i2c/devices/i2c-16/new_device
    fi
    if [ ! -d $lm75_2 ]; then
        echo lm75 0x49 > /sys/bus/i2c/devices/i2c-17/new_device
    fi
}

disconnect()
{
    if [ -d $lm75_2 ]; then
        echo 0x49 > /sys/bus/i2c/devices/i2c-17/delete_device
    fi
    if [ -d $cpu_eeprom ]; then
        echo 0x51 > /sys/bus/i2c/devices/i2c-16/delete_device
    fi
    if [ -d $a2d_2 ]; then
        echo 0x6d > /sys/bus/i2c/devices/i2c-15/delete_device
    fi
    if [ -d $sys_eeprom ]; then
        echo 0x51 > /sys/bus/i2c/devices/i2c-8/delete_device
    fi
    if [ -d $lm75_1 ]; then
        echo 0x4a > /sys/bus/i2c/devices/i2c-7/delete_device
    fi
    if [ -d /sys/bus/i2c/devices/6-006d ]; then
        echo 0x6d > /sys/bus/i2c/devices/i2c-5/delete_device
    fi
    if [ -d $ucd_2 ]; then
        echo 0x41 > /sys/bus/i2c/devices/i2c-5/delete_device
    fi
    if [ -d $ucd_1 ]; then
        echo 0x27 > /sys/bus/i2c/devices/i2c-5/delete_device
    fi
    if [ -d $asic ]; then
        echo 0x48 > /sys/bus/i2c/devices/i2c-2/delete_device
    fi
    if [ -d $cpld ]; then
        echo 0x60 > /sys/bus/i2c/devices/i2c-2/delete_device
    fi
}

reprobe_asic()
{
    if [ -d $asic ]; then
        echo 0x48 > /sys/bus/i2c/devices/i2c-2/delete_device
    fi
    echo mlnx-asic-drv 0x48 > /sys/bus/i2c/devices/i2c-2/new_device
}

start_therm_control()
{
    local speed="$1"
    local period="$2"

    if [ -f /usr/bin/thermal_watch.sh ]; then
        /usr/bin/thermal_watch.sh $speed $period &
    fi
}

stop_therm_control()
{
    TWPID=`/bin/ps -ef | /bin/grep thermal_watch.sh | /bin/grep -v grep | /usr/bin/awk '{print $2}'`
    if [ -f /proc/$TWPID/exe ]; then
        kill $TWPID
    fi
}

show()
{
    local SHOW="$1"

    case $SHOW in 
        module)
            printf -- "\n%14.14s | %14.14s | %14.14s | %14.14s \n" "Module name" "Presence" "Power"
            printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------"

            local module=$cpld
            local module_psu_array=(1 2)
            for i in ${module_psu_array[*]}
            do
                p1=`echo psu"$i"`
                p2=`cat $module/psu"$i"_status`
		if [ "$p2" = "1" ]; then
			p2='present'
		else
			p2='not present'
		fi
                p3=`cat $module/psu"$i"_pg_status`
		if [ "$p3" = "1" ]; then
			p3='powered'
		else
			p3='not powered'
		fi
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3"
            done

            local module_fan_array=(1 2 3 4)
                p1=`echo fan"$i"`
            for i in ${module_fan_array[*]}
            do
                p1=`echo fan"$i"`
                p2=`cat $module/fan"$i"_status`
		if [ "$p2" = "1" ]; then
			p2='present'
		else
			p2='not present'
		fi
                p3='n/a'
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3"
            done

            printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------"
            ;;
        fan)
            printf -- "\n%14.14s | %14.14s | %14.14s | %14.14s \n" "FAN" "Tacho 1" "Tacho 2"
            printf -- "%14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------"

            local fan_asic=$asic
            local fan_asic_array=(1 2 3 4)
            for i in ${fan_asic_array[*]}
            do
                present=`cat $cpld/fan"$i"_status`
                p1=`echo fan"$i"`
                if [ "$present" = "1" ]; then
                    p2=`cat $fan_asic/fan"$i"_input`
                    p3=`cat $fan_asic/fan"$i"_1_input`
                else
                    p2='not resent'
                    p3='not resent'
                fi
		        printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3"
            done

            local ps1_fan=$psu1_ctrl
            local ps1_fan_array=(1)
            for i in ${ps1_fan_array[*]}
            do
                present=`cat $cpld/psu1_status`
                p1=`echo ps1_fan"$i"`
                if [ "$present" = "1" ]; then
                    p2=`cat $ps1_fan/fan"$i"_input`
                else
                    p2='not resent'
                fi
                p3='n/a'
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3"
            done

            local ps2_fan=$psu2_ctrl
            local ps2_fan_array=(1)
            for i in ${ps2_fan_array[*]}
            do
                present=`cat $cpld/psu2_status`
                p1=`echo ps2_fan"$i"`
                if [ "$present" = "1" ]; then
                    p2=`cat $ps2_fan/fan"$i"_input`
                else
                    p2='not resent'
                fi
                p3='n/a'
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3"
            done

            printf -- "%14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------"
            ;;
        power)
            local power_sum=0
            printf -- "\n%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "Sensor name"  "PowerIn (mW)" "Power (mW)" "Current(mA)" "Voltage(mV)" "Capacity (W)"
            printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------" "-------------" "-------------" "-------------"

            local ps1_pg=`cat $cpld/psu1_pg_status`
            if [ "$ps1_pg" = "1" ]; then
                local mon_ps1=$psu1_ctrl
                local mon_ps1_array=(1)
                for i in ${mon_ps1_array[*]}
                do
                    p1=`echo psu1`
                    p2=`cat $mon_ps1/power1_input`
                    p2=$(($p2/1000))
                    p3=`cat $mon_ps1/power2_input`
                    p3=$(($p3/1000))
                    power_sum=$(($p3+$power_sum))
                    p4=`cat $mon_ps1/curr2_input`
                    p5=`cat $mon_ps1/in3_input`
                    p6='460'
		    printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"
                done
            fi

            local ps2_pg=`cat $cpld/psu2_pg_status`
            if [ "$ps2_pg" = "1" ]; then
                local mon_ps2=$psu2_ctrl
                local mon_ps2_array=(1)
                for i in ${mon_ps2_array[*]}
                do
                    p1=`echo psu2`
                    p2=`cat $mon_ps2/power1_input`
                    p2=$(($p2/1000))
                    p3=`cat $mon_ps2/power2_input`
                    p3=$(($p3/1000))
                    power_sum=$(($p3+$power_sum))
                    p4=`cat $mon_ps2/curr2_input`
                    p5=`cat $mon_ps2/in3_input`
                    p6='460'
		    printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"
                done
            fi

            local a2d_mon1=$a2d_2
            local a2d_mon1_array=(1 2)
            for i in ${a2d_mon1_array[*]}
            do
                p1=`cat $a2d_mon1/curr"$i"_label`
                p2='n/a'
                p4=`cat $a2d_mon1/curr"$i"_input`
                p5=12000
                p3=$(($p4*$p5))
                p3=$(($p3/1000))
                power_sum=$(($p3+$power_sum))
                p6='n/a'
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"
            done
            printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------" "-------------" "-------------" "-------------"
	    printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "Power summary" "             " "$power_sum"
            printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------" "-------------" "-------------" "-------------"
            ;;
        voltage)
            printf -- "\n%14.14s | %14.14s | %14.14s | %14.14s \n" "Sensor name" "Voltage(mV)" "Minimum(mV)" "Maximum(mV)"
            printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------" "-------------"
            local a2d_mon1=$a2d_2
            local a2d_mon1_array=(1 2 3 4 5 6 7 8 9)

            for i in ${a2d_mon1_array[*]}
            do
                p1=`cat $a2d_mon1/in"$i"_label`
                p2=`cat $a2d_mon1/in"$i"_input`
                p3=`cat $a2d_mon1/in"$i"_min`
                p4=`cat $a2d_mon1/in"$i"_max`
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4"
            done

            local a2d_mon2=$a2d_1
            local a2d_mon2_array=(1)
            for i in ${a2d_mon2_array[*]}
            do
                p1=`cat $a2d_mon2/in"$i"_label`
                p2=`cat $a2d_mon2/in"$i"_input`
                p3=`cat $a2d_mon2/in"$i"_min`
                p4=`cat $a2d_mon2/in"$i"_max`
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4"
            done

            local asic_mon1=$ucd_1
            local asic_mon1_array=(1 2 3)
            for i in ${asic_mon1_array[*]}
            do
                p1=`cat $asic_mon1/in"$i"_label`
                p1=`echo asic-mon1-$p1`
                p2=`cat $asic_mon1/in"$i"_input`
                p3=`cat $asic_mon1/in"$i"_min`
                p4=`cat $asic_mon1/in"$i"_max`
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4"
            done

            local asic_mon2=$ucd_2
            local asic_mon2_array=(1 2)
            for i in ${asic_mon2_array[*]}
            do
                p1=`cat $asic_mon2/in"$i"_label`
                p1=`echo asic-mon2-$p1`
                p2=`cat $asic_mon2/in"$i"_input`
                p3=`cat $asic_mon2/in"$i"_min`
                p4=`cat $asic_mon2/in"$i"_max`
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4"
            done

            local ps1_pg=`cat $cpld/psu1_pg_status`
            if [ "$ps1_pg" = "1" ]; then
                local ps1_mon=$psu1_ctrl
                local ps1_array=(3)
                for i in ${ps1_array[*]}
                do
                    p1=`cat $ps1_mon/in"$i"_label`
                    p1=`echo ps1-$p1`
                    p2=`cat $ps1_mon/in"$i"_input`
                    p3=`cat $ps1_mon/in"$i"_min`
                    p4=`cat $ps1_mon/in"$i"_max`
		    printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4"
                done
            fi

            local ps2_pg=`cat $cpld/psu2_pg_status`
            if [ "$ps2_pg" = "1" ]; then
                local ps2_mon=$psu2_ctrl
                local ps2_array=(3)
                for i in ${ps2_array[*]}
                do
                    p1=`cat $ps2_mon/in"$i"_label`
                    p1=`echo ps2-$p1`
                    p2=`cat $ps2_mon/in"$i"_input`
                    p3=`cat $ps2_mon/in"$i"_min`
                    p4=`cat $ps2_mon/in"$i"_max`
	   	    printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4"
                done
            fi

	    printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------" "-------------"
	    printf "\n"
            ;;
        temp)
            printf -- "\n%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "Sensor name" "Temp(mC)" "Temp min(mC)" "Temp max(mC)" "Max hyst(mC)" "Max peak(mC)" "Critical(mC)"
            printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------" "-------------" "-------------" "-------------" "-------------"

            local cpu_core_temp=$core_temp/coretemp.0
            local cpu_core_temp_array=(1 2 3)
            for i in ${cpu_core_temp_array[*]}
            do
                p1=`cat $cpu_core_temp/temp"$i"_label`
                p2=`cat $cpu_core_temp/temp"$i"_input`
                p3='n/a'
                p4=`cat $cpu_core_temp/temp"$i"_max`
                p5='n/a'
                p6='n/a'
                p7='n/a'
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"  "$p7"
            done

            local temp_mon1=$lm75_1
            local temp_mon1_array=(1)
            for i in ${temp_mon1_array[*]}
            do
                p1='port amb temp'
                p2=`cat $temp_mon1/temp"$i"_input`
                p3='n/a'
                p4=`cat $temp_mon1/temp"$i"_max`
                p5=`cat $temp_mon1/temp"$i"_max_hyst`
                p6='n/a'
                p7='n/a'
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"  "$p7"
            done

            local temp_mon2=$lm75_2
            local temp_mon2_array=(1)
            for i in ${temp_mon2_array[*]}
            do
                p1='brd amb temp'
                p2=`cat $temp_mon2/temp"$i"_input`
                p3='n/a'
                p4=`cat $temp_mon2/temp"$i"_max`
                p5=`cat $temp_mon2/temp"$i"_max_hyst`
                p6='n/a'
                p7='n/a'
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"  "$p7"
            done

            local temp_asic=$asic
            local temp_asic_array=(1)
            for i in ${temp_asic_array[*]}
            do
                p1='asic temp'
                p2=`cat $temp_asic/temp"$i"_input`
                p3='n/a'
                p4='n/a'
                p5='n/a'
                p6=`cat $temp_asic/temp"$i"_max`
                p7=`cat $temp_asic/temp"$i"_crit`
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"  "$p7"
            done

            local asic_mon1=$ucd_1
            local asic_mon1_array=(1)
            for i in ${asic_mon1_array[*]}
            do
                p1='ucd1 temp'
                p2=`cat $asic_mon1/temp"$i"_input`
                p3='n/a'
                p4=`cat $asic_mon1/temp"$i"_max`
                p5='n/a'
                p6='n/a'
                p7=`cat $asic_mon1/temp"$i"_crit`
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"  "$p7"
            done

            local asic_mon2=$ucd_2
            local asic_mon2_array=(1)
            for i in ${asic_mon2_array[*]}
            do
                p1='ucd2 temp'
                p2=`cat $asic_mon2/temp"$i"_input`
                p3='n/a'
                p4=`cat $asic_mon2/temp"$i"_max`
                p5='n/a'
                p6='n/a'
                p7=`cat $asic_mon2/temp"$i"_crit`
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"  "$p7"
            done

            present=`cat $cpld/psu1_status`
            if [ "$present" = "1" ]; then
                local mon_ps1=$psu1_ctrl
                local mon_ps1_array=(1)
                for i in ${mon_ps1_array[*]}
                do
                    p1='ps1 temp'
                    p2=`cat $mon_ps1/temp"$i"_input`
                    p3=`cat $mon_ps1/temp"$i"_min`
                    p4=`cat $mon_ps1/temp"$i"_max`
                    p5='n/a'
                    p6='n/a'
                    p7='n/a'
		    printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"  "$p7"
                done
            fi

            present=`cat $cpld/psu2_status`
            if [ "$present" = "1" ]; then
                local mon_ps2=$psu2_ctrl
                local mon_ps2_array=(1)
                for i in ${mon_ps2_array[*]}
                do
                    p1='ps2 temp'
                    p2=`cat $mon_ps2/temp"$i"_input`
                    p3=`cat $mon_ps2/temp"$i"_min`
                    p4=`cat $mon_ps2/temp"$i"_max`
                    p5='n/a'
                    p6='n/a'
                    p7='n/a'
		    printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"  "$p7"
                done
            fi

	    printf -- "%14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------" "-------------" "-------------" "-------------" "-------------"
	    printf "\n"
            ;;
        qsfp)
            printf -- "\n%14.14s | %14.14s | %14.14s | %14.14s \n" "module index" "status" "event" "temperature"
            printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------" "-------------"
            local qsfp=$asic
            local qsfp_array=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32)

            for i in ${qsfp_array[*]}
            do
                p1="$i"
                p2=`cat $qsfp/qsfp"$i"_status`
                p3=`cat $qsfp/qsfp"$i"_event`
                #p4=`cat $qsfp/qsfp"$i"_temp_input`
                p4='n/s yet'
		printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "$p1" "$p2" "$p3" "$p4"
            done
	    printf -- "%14.14s | %14.14s | %14.14s | %14.14s \n" "-------------" "-------------" "-------------" "-------------"
	    printf "\n"
            ;;
        cpld)
            printf -- "\n%14.14s | %14.14s \n" "CPLD name" "Version"
            printf -- "%14.14s | %14.14s \n" "-------------" "-------------"

            local cpld_mgmt=$cpld
            local cpld_mgmt_array=(1 2)
            for i in ${cpld_mgmt_array[*]}
            do
                p1=`echo cpld_mgmt"$i"`
                p2=`cat $cpld_mgmt/cpld"$i"_version`
		printf -- "%14.14s | %14.14s \n" "$p1" "$p2"
            done

            local cpld_port=$asic
            local cpld_port_array=(3)
            for i in ${cpld_port_array[*]}
            do
                p1='cpld_port'
                p2=`cat $cpld_port/cpld"$i"_version`
		printf -- "%14.14s | %14.14s \n" "$p1" "$p2"
            done
            printf -- "%14.14s | %14.14s \n" "-------------" "-------------"
            ;;
        led)
            printf -- "\n%14.14s | %14.14s \n" "LED name" "Color"
            printf -- "%14.14s | %14.14s \n" "-------------" "-------------"

            local cpld_led=$cpld
            local cpld_led_array=(1 2 3 4 5 6)
            for i in ${cpld_led_array[*]}
            do
                p1=`cat $cpld_led/led"$i"_name`
                p2=`cat $cpld_led/led"$i"`
		printf -- "%14.14s | %14.14s \n" "$p1" "$p2"
            done
            printf -- "%14.14s | %14.14s \n" "-------------" "-------------"
            ;;
        eeprom)
            printf -- "\n%20.20s\n" "system VPD"
            hexdump  -C $sys_eeprom/eeprom

            printf -- "\n%20.20s\n" "management"
            hexdump  -C $cpu_eeprom/eeprom
            
            present=`cat $cpld/fan1_status`
            if [ "$present" = "1" ]; then
                printf -- "\n%20.20s\n" "fan1"
                hexdump  -C $fan1_eeprom/eeprom
            fi
            
            present=`cat $cpld/fan2_status`
            if [ "$present" = "1" ]; then
                printf -- "\n%20.20s\n" "fan2"
                hexdump  -C $fan2_eeprom/eeprom
            fi
            
            present=`cat $cpld/fan3_status`
            if [ "$present" = "1" ]; then
                printf -- "\n%20.20s\n" "fan3"
                hexdump  -C $fan3_eeprom/eeprom
            fi
            
            present=`cat $cpld/fan4_status`
            if [ "$present" = "1" ]; then
                printf -- "\n%20.20s\n" "fan4"
                hexdump  -C $fan4_eeprom/eeprom
            fi
            
            present=`cat $cpld/psu1_status`
            if [ "$present" = "1" ]; then
                printf -- "\n%20.20s\n" "ps1"
                hexdump  -C $psu1_eeprom/eeprom
            fi

            present=`cat $cpld/psu2_status`
            if [ "$present" = "1" ]; then
                printf -- "\n%20.20s\n" "ps2"
                hexdump  -C $psu2_eeprom/eeprom
            fi
            ;;
        *)
            echo "Usage: $0 show [module|fan|power|voltage|temp|qsfp|cpld|led|eeprom]"
            exit 1
    esac
}

help()
{
    echo Enter $0 help for help
}

set()
{
    local SET="$1"

    case $SET in
        led)
            echo $3 >  $cpld/led"$2"
            ;;
        fan)
            echo $3 >  $asic/pwm"$2"
            ;;
        *)
            echo "Usage: $0 set [led <id> <color>|fan <id> <speed>]"
            exit 1
    esac
}

reset()
{
    local RESET="$1"

    case $RESET in
        asic)
                echo 1 > $cpld/sys_asic1
            ;;
        pcie_slot)
                echo 1 > $cpld/sys_pcie_slot
            ;;
        platform)
                echo 1 > $cpld/sys_platform1
            ;;
        switch_brd)
                echo 1 > $cpld/sys_switch_brd1
            ;;
        *)
            echo "Usage: $0 reset asic|pcie_slot|platform|switch_brd"
            exit 1
    esac
}

reset_cause()
{
        cat $cpld/reset_cause1
}

power_action()
{
    local POWER_ACTION="$1"

    case $POWER_ACTION in 
        psu1_off)
                echo 1 > $cpld/psu1_pwr_off
            ;;
        psu2_off)
                echo 1 > $cpld/psu2_pwr_off
            ;;
        main_pwr_shtdwn)
                echo 1 > $cpld/psu1_pwr_off
                echo 2 > $cpld/psu1_pwr_off
            ;;
        power_cycle)
                echo 1 > $cpld/sys_pwr_cycle1
            ;;
        *)
            echo "Usage: $0 psu1_off|psu2_off|main_pwr_shtdwn|power_cycle"
            exit 1
    esac
}

asic=/sys/bus/i2c/devices/2-0048
cpld=/sys/bus/i2c/devices/2-0060
ucd_1=/sys/bus/i2c/devices/5-0027
ucd_2=/sys/bus/i2c/devices/5-0041
a2d_1=/sys/bus/i2c/devices/5-006d
lm75_1=/sys/bus/i2c/devices/7-004a
sys_eeprom=/sys/bus/i2c/devices/8-0051
psu1_eeprom=/sys/bus/i2c/devices/10-0051
psu2_eeprom=/sys/bus/i2c/devices/10-0050
psu1_ctrl=/sys/bus/i2c/devices/10-0059
psu2_ctrl=/sys/bus/i2c/devices/10-0058
fan1_eeprom=/sys/bus/i2c/devices/11-0050
fan2_eeprom=/sys/bus/i2c/devices/12-0050
fan3_eeprom=/sys/bus/i2c/devices/13-0050
fan4_eeprom=/sys/bus/i2c/devices/14-0050
a2d_2=/sys/bus/i2c/devices/15-006d
cpu_eeprom=/sys/bus/i2c/devices/16-0051
lm75_2=/sys/bus/i2c/devices/17-0049
core_temp=/sys/devices/platform
case "$1" in
    help)
        echo "start                 - install all kernel modules and connect devices to drivers"
        echo "stop                  - uninstall all kernel modules and disconnect devices from drivers"
        echo "restart               - uninstall, disconnect, install, connect"
        echo "init                  - install all kernel modules"
        echo "deinit                - uninstall all kernel modules"
        echo "connect               - connect devices to drivers"
        echo "disconnect            - disconnect devices from drivers"
        echo "reprobe_asic          - reconnect asic driver"
        echo "start_therm_control   - start thermal control script"
        echo "                        optional parameters: <default fan speed> <polling interval>"
        echo "stop_therm_control    - stop thermal control script"
        echo "show"
        echo "   - no parameters    - show all available info"
        echo "   - module           - all modules"
        echo "   - fan              - fan speed"
        echo "   - power            - power, current, voltage from all sensors"
        echo "   - voltage          - voltage from all sensors"
        echo "   - temp             - temperature from all sensors"
        echo "   - qsfp             - qsfp info"
        echo "   - cpld             - cpld versions"
        echo "   - led              - led colors"
        echo "   - eeprom           - dump EEPROM info"
        echo "set"
        echo "   - fan <id> <speed> - fan speed, speed in percent (set fan1 30)"
        echo "   - led <id> <color> - led color (set led1 green",
        echo "                        where color: <red|green|red_blink|gree_blink>"
        echo "reset"
        echo "   - asic             - reset ASIC"
        echo "   - pcie_slot        - reset PCIe slot"
        echo "   - platform         - reset platform (ASIC, PCIe, CPLD, etc)"
        echo "   - switch_brd       - reset switch board"
        echo "reset_cause           - show last reset cause"
        echo "power_action"
        echo "   - psu1_off         - power off PSU1"
        echo "   - psu2_off         - power off PSU2"
        echo "   - main_pwr_shtdwn  - shutdawn main  power"
        echo "   - power_cycle      - perform system power cycle"
        cat <<END
END
        ;;
    start)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        init
        connect
        ;;
    stop)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        disconnect
        deinit
        ;;
    restart)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        disconnect
        deinit
        init
        connect
        ;;
    init)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        init
        ;;
    deinit)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        deinit
        ;;
    connect)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        connect
        ;;
    disconnect)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        disconnect
        ;;
    reprobe_asic)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        echo 0x48 > /sys/bus/i2c/devices/i2c-2/delete_device
        echo mlnx-asic-drv 0x48 > /sys/bus/i2c/devices/i2c-2/new_device
        ;;
    start_therm_control)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        thermal_watch.sh $2 $3 &
        ;;
    stop_therm_control)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        killall -9 thermal_watch.sh
        ;;
    show)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi

        if [ -z "$2" ]; then
            show module
            show fan
            show power
            show voltage
            show temp
            show qsfp
            show cpld
            show led
            show eeprom
        else
            show $2
        fi
        ;;
    set)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        if [ $# -ne 4 ]; then
            help
        else
            set $2 $3 $4
        fi
        ;;
    reset)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi

        if [ -z "$2" ]; then
            help
        else
            reset $2
        fi
        ;;
    reset_cause)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi
        reset_cause
        ;;
    power_action)
        if [ `id -u` -ne 0 ]; then
            echo "You must be root to do that"
            exit 1
        fi

        if [ -z "$2" ]; then
            help
        else
            power_action $2
        fi
        ;;
    *)
        echo "Usage:"
        echo "start                - install all kernel modules and connect devices to drivers"
        echo "stop                 - uninstall all kernel modules and disconnect devices from drivers"
        echo "restart              - uninstall, disconnect, install, connect"
        echo "init                 - install all kernel modules"
        echo "deinit               - uninstall all kernel modules"
        echo "connect              - connect devices to drivers"
        echo "disconnect           - disconnect devices from drivers"
        echo "reprobe_asic         - reconnect asic driver"
        echo "start_therm_control  - start thermal control script"
        echo "                       optional parameters: <default fan speed> <polling interval>"
        echo "stop_therm_control   - stop thermal control script"
        echo "show"
        echo "   - no parameters   - show all available info"
        echo "   - module          - all modules"
        echo "   - fan             - fan speed"
        echo "   - power           - power, current, voltage from all sensors"
        echo "   - voltage         - voltage from all sensors"
        echo "   - temp            - temperature from all sensors"
        echo "   - qsfp            - qsfp info"
        echo "   - cpld            - cpld versions"
        echo "   - led             - led colors"
        echo "   - eeprom          - dump EEPROM info"
        echo "set"
        echo "   - fan <id> <speed> - fan speed, speed in percent (set fan1 30)"
        echo "   - led <id> <color> - led color"
        echo "reset"
        echo "   - asic            - reset ASIC"
        echo "   - pcie_slot       - reset PCIe slot"
        echo "   - platform        - reset platform (ASIC, PCIe, CPLD, etc)"
        echo "   - switch_brd      - reset switch board"
        echo "reset_cause          - show last reset cause"
        echo "power_action"
        echo "   - psu1_off        - power off PSU1"
        echo "   - psu2_off        - power off PSU2"
        echo "   - main_pwr_shtdwn - shutdawn main  power"
        echo "   - power_cycle     - perform system power cycle"

        RETVAL=1
        ;;
esac
exit $RETVAL
