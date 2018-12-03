# Mellanox thermal control and hardware management reference design

This package supports thermal control and hardware management for Mellanox
switches.

Supported systems:

- MSN274* Panther SF
- MSN21* Bulldog    
- MSN24* Spider     
- MSN27*|MSB*|MSX* Neptune, Tarantula, Scorpion, Scorpion2
- MSN201* Boxer                                           
- MQMB7*|MSN37*|MSN34* Jupiter, Jaguar, Anaconda

# Introduction:
Mellanox thermal monitoring is an open source package for better thermal
performance and fan efficiently in Mellanox Spectrum managed products.
The monitoring measure temperature from the ports and ASIC core. It operates
in kernel space and binds PWM control with Linux thermal zone for each
measurement device (ports & core).
The thermal algorithm uses step wise policy which set FANs according to the
thermal trends (high temperature = faster fan; lower temperature = slower fan).

# Description:
The thermal zone binds PWM control and the temperature measure from the
transceivers and from the ASIC (switch ambient). Kernel algorithm uses step
wise policy.It creates the set of thermal zones, where each relevant thermal
sensor is bound to the same PWM control.
For details, please refer to kernel documentation file:
Documentation/thermal/sysfs-api.txt.
Existing kernel thermal framework provides:
Concepts of thermal zones, trip points, cooling devices, thermal instances,
thermal governors:
 - Cooling device is an actual functional unit for cooling down the thermal
   zone: Fan.
 - Thermal instance describes how cooling devices work at certain trip point in
   the thermal zone.
 - Governor handles the thermal instance not thermal devices.
   Step wise governor sets cooling state based on thermal trend (STABLE, RAISING,
   DROPPING, RASING_FULL, DROPPING_FULL). It allows only one step change for
   increasing or decreasing at decision time.
Framework to register thermal zone and cooling devices:
  - Thermal zone devices and cooling devices will work after proper binding.
Performs a routing function of generic cooling devices to generic thermal zones
with the help of very simple thermal management logic.

This package provides additional functionally to the thermal control, which
contains the following polices:
- Setting PWM to full speed if one of PS units is not present (in such case
  thermal monitoring in kernel is set to disabled state until the problem is
  not recovered). Such events will be reported to systemd journaling system. 
- Setting PWM to full speed if one of FAN drawers is not present or one of
  tachometers is broken present (in such case thermal monitoring in kernel is
  set to disabled state until the problem is not recovered). Such events will
  be reported to systemd journaling system.

The ASIC thermal zone is defined with the following trip points:
- State		Temperature value	PWM speed	Action
- Cold:		t < 75 Celsius		20% *		Do nothing
- In range	75 <= t < 85 Celsius	20%-40% *	Keep minimal speed
- Hot:		85 <= t < 105		40%-100% *	Perform hot algorithm
- Hot alarm:	105 <= t < 110 Celsius	100%		Produce warning message
- Critical: 	t >= 110 Celsius	100%		System shutdown

The transceivers thermal zones are defined with the dynamical trip points,
according to the thresholds values read from the transceivers EEPROM data.

- All the above trip points, excepted last one, are defined with 5 Celsius
  hysteresis trip.

* Note:
The above table defines default minimum FAN speed per each thermal zone. This
setting can be reset in case the dynamical minimum speed is changed. The
cooling device bound to the thermal zone operates over the ten cooling logical
levels. The default vector for the cooling levels is defined with the next PWM
per level speeds:
- 20%	20%	30%	40%	50%	60%	70%	80%	90%	100%
- In case system dynamical minimum is changed for example from 20% to 60%, the
  cooling level vector will be dynamically updated as below:
- 60%	60%	60%	60%	60%	60%	70%	80%	90%	100%
- In such way the allowed PWM minimum is limited according to the system
  thermal requirements.

Package contains the following files, used within the workload:
etc
  modprobe.d
    hw-management.conf
  modules-load.d
    hw-management-modules.conf
lib
  systemd
    system
      hw-management.service
  udev
    rules.d
      50-hw-management-events.rules
usr
  bin
    hw-management-chassis-events.sh
    hw-management-led-state-conversion.sh
    hw-management-power-helper.sh
    hw-management.sh
    hw-management-thermal-control.sh
    hw-management-thermal-events.sh

- /lib/systemd/system/hw-management.service
-	system entries for thermal control activation and de-activation.
- /lib/udev/rules.d/50-hw-management-events.rules
-	udev rules defining the triggers on which events should be handled.
	When trigger is matched, rule data is to be passed to the event handler
	(see below file /usr/bin/hw-management-events.sh).
- /usr/bin/hw-management-control.sh
	contains thermal algorithm implementation.
- /usr/bin/hw-management-chassis-events.sh
  /usr/bin/hw-management-thermal-events.sh
-	handles udev triggers, according to the received data, it creates or
	destroys symbolic links to sysfs entries. It allows to create system
	independent entries and it allows thermal controls to work over this
	system independent model.
	Raises signal to hw-management-control in case of fast temperature
	decreasing. It could happen in case one or few very hot port cables
	have been removed.
	Sets PS units internal FAN speed to default value when unit is
	connected to power source.
- /usr/bin/hw-management.sh
-	performs initialization and de-initialization, detects the system type,
	connects thermal drivers according to the system topology, activates
	and deactivates thermal algorithm.
- hw-management-led-state-conversion.sh
  hw-management-power-helper.sh
-	helper scripts
- hw-management.conf
  hw-management-modules.conf
-	configuration for kernel modules loading.

# SYSFS attributes:
- The thermal control operates over sysfs attributes. These attributes are
  exposed as symbolic links to /var/run/hw-management folder at system boot
  time. These folder contains the next structure:
/var/run/hw-management
  config
    configuration related symbolic links
  eeprom
    eeprom related symbolic links
  environment
    environment (voltage, current, etcetera) related symbolic links
  led
    led related symbolic links
  power
    power related symbolic links
  system
    system related (health, reset, etcetera) related symbolic links
  thermal
    thermal related links
    mlxsw
      ASIC ambient temperature thermal zone related symbolic links
    mlxsw-module1
      QSFP module 1 temperature thermal zone related symbolic links
    ...
      ...
    mlxsw-module64
      QSFP module 64 temperature thermal zone related symbolic links

Below some of the symbolic links examples:
- cooling_cur_state:	Current cooling state, exposed by cooling level (1..10)
- fan<i>_fault:		tachometer fault, <i> 1..max tachometers number
- fan<i>_input:		tachometer input, <i> 1..max tachometers number
- psu1_status:		PS unit 1 presence status (1 - present, 0 - removed)
- psu2_status:		PS unit 2 presence status (1 - present, 0 - removed)
- pwm:			PWM speed exposed in RPM
- temp_asic:		ASIC ambient temperature value
- temp_fan_amb:		FAN side ambient temperature value
- temp_port_amb:	port side ambient temperature value
- temp_port:		port temperature value
- temp_port_fault:	port temperature fault
- temp_trip_norm:	thermal zone minimum temperature trip
- tz_mode:		thermal zone mode (enabled or disabled)
- tz_temp:		thermal zone temperature

# Kernel configuration
Kernel configuration required the next setting (kernel version should be v4.19
or later):
- CONFIG_NET_VENDOR_MELLANOX
- CONFIG_MELLANOX_PLATFORM
- CONFIG_NET_DEVLINK
- CONFIG_MAY_USE_DEVLINK
- CONFIG_I2C
- CONFIG_I2C_BOARDINFO
- CONFIG_I2C_CHARDEV
- CONFIG_I2C_MUX
- CONFIG_I2C_MUX_REG
- CONFIG_REGMAP
- CONFIG_SYSFS
- CONFIG_MLXSW_CORE
- CONFIG_MLXSW_CORE_HWMON
- CONFIG_MLXSW_CORE_THERMAL
- CONFIG_MLXSW_PCI or/and CONFIG_MLXSW_I2C *
- CONFIG_MLXSW_SPECTRUM or/and CONFIG_MLXSW_MINIMAL *
- CONFIG_I2C_MLXCPLD
- CONFIG_LEDS_MLXREG
- CONFIG_MLX_PLATFORM
- CONFIG_MLXREG_HOTPLUG
- CONFIG_THERMAL
- CONFIG_THERMAL_HWMON
- CONFIG_THERMAL_WRITABLE_TRIPS
- CONFIG_THERMAL_DEFAULT_GOV_STEP_WISE=y
- CONFIG_THERMAL_GOV_STEP_WISE
- CONFIG_PMBUS
- CONFIG_SENSORS_PMBUS
- CONFIG_HWMON
- CONFIG_THERMAL_HWMON
- CONFIG_SENSORS_LM75
- CONFIG_SENSORS_TMP102
- CONFIG_LEDS_MLXREG
- CONFIG_LEDS_TRIGGERS
- CONFIG_LEDS_TRIGGER_TIMER
- CONFIG_NEW_LEDS
- CONFIG_LEDS_CLASS

* Note
In case kernel is configured with CONFIG_MLXSW_PCI and CONFIG_MLXSW_SPECTRUM,
mlxsw kernel hwmon and thermal modules will work over PCI bus. In this case
mlxsw_i2c and mlxsw_minimal drivers will not be activated. In other case hwmon
and thermal modules will work over I2C bus.
If user wants to have both PCI and I2C option configured and want enforce
thermal control to work over I2C, for example user which wants to be able to
switch between workloads running Mellanox legacy SDK code and running Mellanox
switch-dev driver, the next steps should be performed:
- Create blacklist file with next wo lines, f.e.
  /etc/modprobe.d/mellanox-sdk-blacklist.conf
  blacklist mlxsw_spectrum
  blacklist mlxsw_pci
- And then run:
  update-initramfs -u (in case initramfs is used)
For returning back to PCI option:
- Remove /etc/modprobe.d/mellanox-sdk-blacklist.conf
- And then run:
  update-initramfs -u (in case initramfs is used)

# Packaging:
The package depends on the next packages:
- init-system-helpers:	helper tools for all init systems
- lsb-base:		Linux Standard Base init script functionality
- udev:			/dev/ and hotplug management daemon
- i2c-tools:		heterogeneous set of I2C tools for Linux

Package contains the folder debian, with the rules for Debian package build.

Location:
https://github.com/MellanoxBSP/thermal-control

To get package sources:
git clone https://github.com/MellanoxBSP/thermal-control.git

For Debian package build:
On a debian-based system, install the following programs:
sudo apt-get install devscripts build-essential lintian

- Go into thermal-control base folder and build Debian package.
- Run:
  debuild -us -uc
- Find in upper folder f.e. hw-management_1.mlnx.18.12.2018_amd64.deb

For converting deb package to rpm package:
On a debian-based system, install the following program:
sudo apt-get install alien

- alien --to-rpm hw-management_1.mlnx.18.12.2018_amd64.deb
- Find hw-management-1.mlnx.18.12.2018-2.x86_64.rpm

## Installation from local file and de-installation
Copy deb or rpm package to the system, for example to /tmp.

For deb package install with:
dpkg -i /tmp/ hw-management_1.mlnx.18.12.2018_amd64.deb
remove with:
dpkg --purge hw-management

For rpm install with:
- yum localinstall /tmp/hw-management-1.mlnx.18.12.2018-2.x86_64.rpm
  or
- rpm -ivh /tmp/hw-management-1.mlnx.18.12.2018-2.x86_64.rpm
  remove with:
- yum remove hw-management
  or
- rpm -e hw-management


## Activation, de-activation and reading status
hw-management can be initialized and de-initialized by systemd service.
The next command could be used in order to configure persistent initialization
and de-initialization of hw-management:
- systemctl enable hw-management
- systemctl disable hw-management
- Running status of hw-management unit can be obtained by the following
  command:
- systemctl status hw-management
- Logging records of the thermal control written by systemd-journald.service
  can be queried by the following commands:
- journalctl --unit=hw-management
- journalctl -f -u hw-management
- Once "systemctl enable hw-management" is invoked, the thermal control will
  be automatically activated after the next and the following system reboots,
  until "systemctl disable hw-management" is not invoked.
  Application could be stopped by the following commands:
- systemctl stop hw-management.service

## Authors

* **Michael Shych** <michaelsh@mellanox.com>
* **Mykola Kostenok** <c_mykolak@mellanox.com>
* **Ohad Oz** <ohado@mellanox.com>
* **Oleksandr Shamray** <oleksandrs@mellanox.com>
* **Vadim Pasternak** <vadimp@mellanox.com>

## License

This project is Licensed under the GNU General Public License Version 2.

## Acknowledgments

* Mellanox Low-Level Team.
