#!/bin/bash

# NOTE: Get GPIO line names from the dtsi

# Inherit Logging libraries
source /etc/default/nvidia_event_logging.sh

# Inherit bmc functions library
source /usr/bin/mc_lib.sh

# Inherit system configuration.
source hw-management-helpers.sh

# Inherit common BMC routines
source /usr/bin/bmc_ready_common.sh

# Inherit functions for setting extra boot args and params
source /usr/bin/bmc_set_extra_params.sh

# Inhert gpio functions
source /usr/bin/switch_gpio_set.sh

# BMC_STBY_READY is set dynamically in bmc_init_sysfs_gpio()

BMC_VPD_EEPROM_I2C_BUS=5
BMC_VPD_EEPROM_I2C_ADDRES=0x51
BMC_VPD_EEPROM_HID_OFFSET=22
BMC_VPD_EEPROM_HID_SIZE=5
BMC_VPD_EEPROM_BOM_SIZE=192
eeprom_file=/sys/devices/platform/soc@14000000/soc@14000000:bus@14c0f000/14c0f600.i2c-bus/i2c-5/5-0051/eeprom

#######################################
# Wait for GP_STBY_PG signal
# ARGUMENTS:
#   arg1 timeout (secs), wait until timeout has elapsed
#   arg2 interval (secs), wait this interval between each check
# RETURN:
#   0 if GP_STBY_PG was asserted (BMC standby is ready) within timeout
#   1 if GP_STBY_PG was not asserted within timeout
wait_bmc_standby_ready()
{
    local timeout=$1
    local interval_secs=$2
    local wait_time=0
    local start_time=$EPOCHSECONDS

    echo "Wait for BMC standby Ready, timeout = $timeout secs..."
    echo "Expecting $BMC_STBY_READY set HIGH"
    while [ 1 ];
    do
	ready_status=`cat $BMC_STBY_READY`

        if [[ $ready_status -eq 1 ]]; then
            echo "BMC standby ready asserted"
            return 0
        fi
        echo "Waiting for BMC standby ready signal, $wait_time"
        wait_time=$((wait_time + interval_secs))
        sleep $interval_secs
        if (( EPOCHSECONDS-start_time > timeout)); then
            echo "[ERROR] BMC standby not ready in $timeout secs"
            return 1
        fi
    done
}

#######################################
# Wait till system folder under /var/run/hw-management is created following a
# udev event to userspace
#######################################
wait_platform_drv()
{
	plat_driver_tiemout_ms=20000
	count=0

	while true; do
		if [ -d $system_path ]; then
			break
		fi

		if [ ${count} -eq ${plat_driver_tiemout_ms} ]; then
			echo "ERROR: timed out waiting for $system_path to become avialable"
			break
		fi

		if (( count % 1000 == 0 )); then
			echo "Waiting for $system_path to become avialable, $count ms passed"
		fi
		sleep 0.1
		count=$((count+100))

	done
}

bmc_init_sysfs_gpio()
{
    # Discover GPIO bases dynamically
    ASPEED_BASE=$(gpiochip_base_aspeed)         # AST2600 (208) or AST2700 (216)
    EXPANDER_BASE=$(gpiochip_base_by_ngpio 24)  # PCAL6524

    if [ -z "$ASPEED_BASE" ]; then
        gpio_log "err" "Failed to detect Aspeed GPIO chip base (ngpio=216)"
    else
        echo "Aspeed GPIO base   : $ASPEED_BASE"
    fi

    if [ -z "$EXPANDER_BASE" ]; then
        gpio_log "err" "Failed to detect GPIO expander base (ngpio=24)"
    else
        echo "Expander GPIO base : $EXPANDER_BASE"
    fi

    #
    # ---- PCAL6524 EXPANDER (gpiochip, 24 lines) ----
    #
    if [ -n "$EXPANDER_BASE" ]; then
        GPIO_EROT_RST_IN_L=$((EXPANDER_BASE + 1))
        GPIO_PHY_PG=$((EXPANDER_BASE + 2))
        GPIO_PWR_CYCLE_3V3_MASK_L=$((EXPANDER_BASE + 3))
        GPIO_EROT_BOOT_COMPLETE=$((EXPANDER_BASE + 6))
        GPIO_WP_CTRL_L=$((EXPANDER_BASE + 7))
        GPIO_REC_SPI_MUX_SEL=$((EXPANDER_BASE + 8))
        # GPIO_PHY_RST_L (offset 10) is set in DTS, do not export here
        GPIO_JTAG_BURN_EN_L=$((EXPANDER_BASE + 11))
        GPIO_PWR_BANK_PRESENT_L=$((EXPANDER_BASE + 12))
        GPIO_FLASH0_EN=$((EXPANDER_BASE + 19))
        GPIO_FLASH1_EN=$((EXPANDER_BASE + 21))

        for g in \
            $GPIO_EROT_RST_IN_L \
            $GPIO_PHY_PG \
            $GPIO_PWR_CYCLE_3V3_MASK_L \
            $GPIO_EROT_BOOT_COMPLETE \
            $GPIO_WP_CTRL_L \
            $GPIO_REC_SPI_MUX_SEL \
            $GPIO_JTAG_BURN_EN_L \
            $GPIO_PWR_BANK_PRESENT_L \
            $GPIO_FLASH0_EN \
            $GPIO_FLASH1_EN
        do
            gpio_export "$g"
        done

        gpio_dir "$GPIO_EROT_RST_IN_L" in
        gpio_dir "$GPIO_PHY_PG" in
        gpio_dir "$GPIO_PWR_CYCLE_3V3_MASK_L" out
        gpio_dir "$GPIO_EROT_BOOT_COMPLETE" in
        gpio_dir "$GPIO_WP_CTRL_L" out
        gpio_dir "$GPIO_REC_SPI_MUX_SEL" out
        # GPIO_PHY_RST_L direction is set in DTS
        gpio_dir "$GPIO_JTAG_BURN_EN_L" out
        gpio_dir "$GPIO_PWR_BANK_PRESENT_L" in
        gpio_dir "$GPIO_FLASH0_EN" out
        gpio_dir "$GPIO_FLASH1_EN" out

        gpio_set "$GPIO_PWR_CYCLE_3V3_MASK_L" 1
        gpio_set "$GPIO_REC_SPI_MUX_SEL" 1
        gpio_set "$GPIO_JTAG_BURN_EN_L" 1
        gpio_set "$GPIO_FLASH0_EN" 0
        gpio_set "$GPIO_FLASH1_EN" 0
    fi

    #
    # ---- ASPEED SOC GPIOs ----
    #
    if [ -n "$ASPEED_BASE" ]; then
        # GPIO_UART_TX=$((ASPEED_BASE + 27))      # Not in use
        # GPIO_EP_PERST=$((ASPEED_BASE + 96))     # Not in use
        GPIO_STBY_PG=$((ASPEED_BASE + 34))        # GPIOE2
        GPIO_PWR_CYCLE_1V8=$((ASPEED_BASE + 145)) # GPIOS1
        GPIO_BMC_GPIO_EXP_RESET_L=$((ASPEED_BASE + 144)) # GPIOS0

        # for g in \
        #     $GPIO_UART_TX \
        #     $GPIO_EP_PERST \
        #     $GPIO_STBY_PG \
        #     $GPIO_PWR_CYCLE_1V8 \
        #     $GPIO_PWR_CYCLE_1V8_MASK_L
        # do
        #     gpio_export "$g"
        # done
        for g in \
            $GPIO_STBY_PG \
            $GPIO_PWR_CYCLE_1V8 \
            $GPIO_BMC_GPIO_EXP_RESET_L
        do
            gpio_export "$g"
        done


        # gpio_dir "$GPIO_UART_TX" out
        # gpio_set "$GPIO_UART_TX" 1

        # gpio_dir "$GPIO_EP_PERST" out
        # gpio_set "$GPIO_EP_PERST" 1

        gpio_dir "$GPIO_STBY_PG" in
        gpio_get "$GPIO_STBY_PG"

        # Export BMC_STBY_READY for use by wait_bmc_standby_ready()
        BMC_STBY_READY=/sys/class/gpio/gpio$GPIO_STBY_PG/value

        gpio_dir "$GPIO_PWR_CYCLE_1V8" out
        gpio_set "$GPIO_PWR_CYCLE_1V8" 1

        gpio_dir "$GPIO_BMC_GPIO_EXP_RESET_L" out
        gpio_set "$GPIO_BMC_GPIO_EXP_RESET_L" 1
    fi

    # Create symbolic links. Wait for the system path to become available first.
    wait_platform_drv

    # Expander GPIO symlinks
    if [ -n "$EXPANDER_BASE" ]; then
        check_n_link /sys/class/gpio/gpio$GPIO_EROT_RST_IN_L/value $system_path/GP_EROT_RST_IN_L
        check_n_link /sys/class/gpio/gpio$GPIO_PHY_PG/value $system_path/GP_3V3_BMC_PHY_PG
        check_n_link /sys/class/gpio/gpio$GPIO_PWR_CYCLE_3V3_MASK_L/value $system_path/GP_BMC_PWR_CYCLE_3V3_MASK_L
        check_n_link /sys/class/gpio/gpio$GPIO_EROT_BOOT_COMPLETE/value $system_path/SE_SOC_EROT_BOOT_COMPLETE
        check_n_link /sys/class/gpio/gpio$GPIO_WP_CTRL_L/value $system_path/GP_BMC_WP_CTRL_GPIO_L
        check_n_link /sys/class/gpio/gpio$GPIO_REC_SPI_MUX_SEL/value $system_path/GP_BMC_REC_SPI_MUX1_SEL
        check_n_link /sys/class/gpio/gpio$GPIO_JTAG_BURN_EN_L/value $system_path/GP_JTAG_BMC_CPLD_BURN_EN_L
        check_n_link /sys/class/gpio/gpio$GPIO_PWR_BANK_PRESENT_L/value $system_path/GP_PWR_BANK_PRESENT_L
        check_n_link /sys/class/gpio/gpio$GPIO_FLASH0_EN/value $system_path/GP_PROD_CS_FLASH0_EN
        check_n_link /sys/class/gpio/gpio$GPIO_FLASH1_EN/value $system_path/GP_PROD_CS_FLASH1_EN
    fi

    # Aspeed SOC GPIO symlinks
    if [ -n "$ASPEED_BASE" ]; then
        # check_n_link /sys/class/gpio/gpio$GPIO_UART_TX/value $system_path/BMC_UART_TX
        # check_n_link /sys/class/gpio/gpio$GPIO_EP_PERST/value $system_path/BMC_EP_PERST_EN-O
        check_n_link /sys/class/gpio/gpio$GPIO_STBY_PG/value $system_path/GP_STBY_PG
        check_n_link /sys/class/gpio/gpio$GPIO_PWR_CYCLE_1V8/value $system_path/GP_BMC_PWR_CYCLE_1V8
        check_n_link /sys/class/gpio/gpio$GPIO_BMC_GPIO_EXP_RESET_L/value $system_path/GP_BMC_PWR_CYCLE_1V8_MASK_L
    fi

    echo "GPIO sysfs initialization complete"
}

get_cpu_type()
{
	cpu_pn=$(grep -m1 "CPU part" /proc/cpuinfo | awk '{print $4}')
	cpu_pn=`echo $cpu_pn | cut -c 3- | tr a-z A-Z`
	cpu_pn=0x$cpu_pn
	cpu_type=$cpu_pn
	echo $cpu_type > $config_path/cpu_type
}

get_system_hw_id()
{
        offset=$BMC_VPD_EEPROM_HID_OFFSET
        num_bytes=$BMC_VPD_EEPROM_HID_SIZE
        raw_data=$(dd if="$eeprom_file" bs=1 skip="$offset" count="$num_bytes" 2>/dev/null)

	echo $raw_data > "$config_path"/hid
	echo "System hardware Id is $raw_data"

}

get_system_hw_bom()
{

        num_bytes=$BMC_VPD_EEPROM_BOM_SIZE
        offset=$(dd if="$eeprom_file" bs=1 count=128 2>/dev/null | strings -a -n 3 -t d  | awk 'match($2, /V[0-9]-/) { print $1 + RSTART - 1; exit }')
        bom=""

	hid=$(cat $config_path/hid)
	case "$hid" in	HI189|HI190|HI191|HI192|HI193|HI183)
		raw_data=$(dd if="$eeprom_file" bs=1 skip="$offset" count="$num_bytes" 2>/dev/null | tr -d '\0')

		IFS=$'\xff' read -r -a data_array <<< "$raw_data"
		for item_data in "${data_array[@]}"; do
			IFS=$' ' read -r -a item_array <<< "$item_data"
			bom=$bom$item_array
		done
		echo $bom > "$config_path"/bom
		echo "System hardware BOM record is $bom"
		;;
	*)
		;;
	esac
}

set_chassis_powerstate_on()
{
    busctl set-property xyz.openbmc_project.State.Chassis /xyz/openbmc_project/state/chassis0 xyz.openbmc_project.State.Chassis CurrentPowerState s xyz.openbmc_project.State.Chassis.PowerState.On
}

bmc_to_cpu_tmp()
{
	# Swicth UART to CPU.
	echo 2 > $BMC_TO_CPU_UART
	echo "Switch console to the host CPU"
	# Power on CPU power domain through CPLD.
	echo 0 > $BMC_CPU_PWR_ON
	echo "Power on the host CPU"
	set_chassis_powerstate_on
	set_host_powerstate_on
	# Temporary: Set CPU as a master of I2C tree and signal control.
	echo 0 > $BMC_TO_CPU_CTRL
}

bmc_to_cpu()
{
	# Swicth UART to CPU.
	echo 2 > $BMC_TO_CPU_UART
	echo "Switch console to the host CPU"
	# Power on CPU power domain through CPLD.
	echo 0 > $BMC_CPU_PWR_ON
	echo "Power on the host CPU"
	set_chassis_powerstate_on
	set_host_powerstate_on
}

#######################################
# Run pre init and/or post init hook scripts supplied by the NOS.
# This function allows providing workarounds for issues discovered in the field
# until an updated firmware version is released.
#
# ARGUMENTS:
#   pre / post
# RETURN:
#   None
run_hook() {
	# hook file is a symbolic link to /home/yormnAnb/hw-management-bmc-fixup.sh
	local hook_file="/usr/local/bin/hw-management-bmc-fixup.sh"

	if [ -f "$hook_file" ]; then

		if [ ! -x "$hook_file" ]; then
			logger -t "bmc_ready_hook" -p daemon.info "File '$hook_file' is not executable. Changing permissions."
			chmod +x "$hook_file"
		fi

		# Provide indication to nos about last executed fixup script
		cp "$hook_file" /var/run/hw-management/config/last-executed-fixup.sh
		"$hook_file" $1

		local retval=$?
		# Update status file in order to provide indication to nos
		echo $retval > "/var/run/hw-management/config/fixup-status-$1"
		if [ $retval -eq 0 ]; then
			logger -t "bmc_ready_hook" -p daemon.info "File '$hook_file' was executed successfully with parameter: $1."
		else
			logger -t "bmc_ready_hook" -p daemon.err "Execution of '$hook_file' with parameter $1 failed with return value $retval."
		fi
	else
		logger -t "bmc_ready_hook" -p daemon.info "No hook file, $1 init hooks are not performed."
	fi
}

#######################################
# Execute required steps before asserting BMC_READY signal
#
# ARGUMENTS:
#   None
# RETURN:
#   None
# EXIT:
#   0 BMC_READY has been asserted
#   1 BMC_READY not asserted, due to failure in ready sequence
bmc_ready_sequence()
{
	wait_bmc_standby_ready 10 1

	# Obtain CPU type.
	get_cpu_type
	# Obtain system hardware Id from system EEPROM.
	# NOTE: 24c512 0x51 is now created by bmc-early-i2c-init.service
	get_system_hw_id
	# Obtain system hardware BOM record.
	get_system_hw_bom

	# NOTE: I2C devices are now created by bmc-early-i2c-init.service

	# Configure A2D devices.
	a2d_leakage_config.sh

	check_rw_filesystems
	rc=$?
	if [[ $rc -ne 0 ]]; then
		if [ "$cpu_start_policy" == "1" ]; then
			bmc_to_cpu_tmp
		fi
		echo "[ERROR] Filesystem mount check failure"
		run_hook post
		exit 1
	fi

	check_rofs
	rc=$?
	if [[ $rc -ne 0 ]]; then
		if [ "$cpu_start_policy" == "1" ]; then
			bmc_to_cpu_tmp
		fi
		echo "[ERROR] BMC booted in ROFS, Read-Only mode"
		run_hook post
		exit 1
	fi

	# Assert BMC READY - review the below function.
	#set_bmc_ready $HIGH
	phosphor_log "bmc_ready.sh completed" $sevNot
	return 0
}

bmc_init_main()
(
	# Note: in case run_hook pre contains code for u-boot command line or boot arguments
	#       modification - it should call the following sequence:
	#         source /usr/bin/bmc_set_extra_params.sh
	#         if set_extrabootargs_and_bootcmdline()
	#             reboot_bmc()
	#         fi
	# Example 1: Set both command line and boot arguments
	# if set_extrabootargs_and_bootcmdline \
	#     "i2c dev 4; i2c probe 0x51; i2c md 0x51 0x00.2 0x100" \
	#     "blacklist=mp2995"; then
	#     echo "Boot parameters changed, rebooting..."
	#     reboot_bmc
	# else
	#     echo "No reboot needed, boot parameters already correct"
	# fi
	# Example 2: Set only command line
	# set_extrabootargs_and_bootcmdline \
	#    "i2c dev 4; i2c probe 0x51" \
	#    ""
	# Example 3: Set only boot arguments
	# set_extrabootargs_and_bootcmdline \
	#    "" \
	#    "blacklist=mp2995 debug"
	# Example 4: Clear everything
	# clear_extrabootargs_and_bootcmdline
	# Example 5: Show current configuration
	# show_boot_config

	run_hook pre

	bmc_init_sysfs_gpio
	bmc_init_eth

	bmc_init_bootargs

	# Save CPU power state.
	CPU_OFF_CMD=$(< $BMC_CPU_PWR_ON)
	CPU_OFF_BUT=$(< $BMC_CPU_PWR_ON_BUT)
	CPU_OFF=$((CPU_OFF_CMD|CPU_OFF_BUT))

	if [ "${CPU_OFF}" = "1" ]; then
		echo 1 > $BMC_TO_CPU_CTRL
	fi

	cpu_start_policy=$(check_power_restore_policy)

	bmc_ready_sequence
	rc=$?
	if [[ $rc -ne 0 ]]; then
		echo "[ERROR] BMC init flow failure"
	fi
	
	create_nosbmc_user
	if [ "$cpu_start_policy" == "1" ]; then
		bmc_to_cpu

		# Temporary: connect mux devices only if CPU initially was powered off.
		# Otherwise - assumption this is BMC only reboot flow and mux devices
		# initialization is skipped to avoid conflicts with CPU telemetry.
		if [ "${CPU_OFF}" = "1" ]; then
			hw-management.sh start
		fi

		# Temporary: Set CPU as a master of I2C tree and signal control.
		sleep 5
		echo 0 > $BMC_TO_CPU_CTRL
	else
		hw-management.sh start
	fi

	# Enable write protect.
	echo "Enabling write protect."
	busctl call xyz.openbmc_project.Software.Settings /xyz/openbmc_project/software/System_0 xyz.openbmc_project.Software.Settings SetWriteProtectInit b true

	echo "Disabling write protect for bringup."
	sleep 1
	echo 1 > /run/hw-management/system/GP_BMC_WP_CTRL_GPIO_L

	run_hook post

)

## Main
if [ ! -d "$config_path" ]; then
	mkdir -p "$config_path"
	bmc_init_main
else
	echo "BMC is up and running - skip init sequence."
fi
