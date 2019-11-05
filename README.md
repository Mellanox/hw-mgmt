# Mellanox hardware management reference design

This package supports thermal control and hardware management for Mellanox
switches.

Supported systems:

- MSN2740
- MSN2100
- MSN2410
- MSN2700
- MSN2010
- MQMB7800
- MSN3700
- MSN3800

# Supported Kerenl versions 

- 4.9.xx
- 4.19.xx

# SYSFS attributes:
The thermal control operates over sysfs attributes. These attributes are exposed as symbolic links to /var/run/hw-management folder at system boot time. These folder contains the next structure: /var/run/hw-management config configuration related files. It includes the information about FAN minimum, maximum allowed speed, some default settings, configured delays for different purposes. eeprom eeprom related symbolic links to system, PSU, FAN eeproms. environment environment (voltage, current, etcetera) related symbolic links. led led related symbolic links. power power related symbolic links. system system related (health, reset, etcetera) related symbolic links. thermal thermal related links, including thermal zones related subfolders mlxsw ASIC ambient temperature thermal zone related symbolic links. mlxsw-module1 QSFP module 1 temperature thermal zone related symbolic links. ... ... mlxsw-module64 ... QSFP module 64 temperature thermal zone related symbolic links. watchdog aux auxiliary watchdog related symbolic links. main main watchdog related symbolic links.
Below some of the symbolic links examples:

cooling_cur_state: Current cooling state, exposed by cooling level (1..10)
fan_fault: tachometer fault, 1..max tachometers number
fan_input: tachometer input, 1..max tachometers number
psu1_status: PS unit 1 presence status (1 - present, 0 - removed)
psu2_status: PS unit 2 presence status (1 - present, 0 - removed)
pwm: PWM speed exposed in RPM
temp_asic: ASIC ambient temperature value
temp_fan_amb: FAN side ambient temperature value
temp_port_amb: port side ambient temperature value
temp_port: port temperature value
temp_port_fault: port temperature fault
temp_trip_norm: thermal zone minimum temperature trip
tz_mode: thermal zone mode (enabled or disabled)
tz_temp: thermal zone temperature

# Kernel configuration
Kernel configuration required the next setting (kernel version should be v4.19 or later):

CONFIG_NET_VENDOR_MELLANOX
CONFIG_MELLANOX_PLATFORM
CONFIG_NET_DEVLINK
CONFIG_MAY_USE_DEVLINK
CONFIG_I2C
CONFIG_I2C_BOARDINFO
CONFIG_I2C_CHARDEV
CONFIG_I2C_MUX
CONFIG_I2C_MUX_REG
CONFIG_REGMAP
CONFIG_SYSFS
CONFIG_MLXSW_CORE
CONFIG_MLXSW_CORE_HWMON
CONFIG_MLXSW_CORE_THERMAL
CONFIG_MLXSW_PCI or/and CONFIG_MLXSW_I2C *
CONFIG_MLXSW_SPECTRUM or/and CONFIG_MLXSW_MINIMAL *
CONFIG_I2C_MLXCPLD
CONFIG_LEDS_MLXREG
CONFIG_MLX_PLATFORM
CONFIG_MLXREG_HOTPLUG
CONFIG_THERMAL
CONFIG_THERMAL_HWMON
CONFIG_THERMAL_WRITABLE_TRIPS
CONFIG_THERMAL_DEFAULT_GOV_STEP_WISE=y
CONFIG_THERMAL_GOV_STEP_WISE
CONFIG_PMBUS
CONFIG_SENSORS_PMBUS
CONFIG_HWMON
CONFIG_THERMAL_HWMON
CONFIG_SENSORS_LM75
CONFIG_SENSORS_TMP102
CONFIG_LEDS_MLXREG
CONFIG_LEDS_TRIGGERS
CONFIG_LEDS_TRIGGER_TIMER
CONFIG_NEW_LEDS
CONFIG_LEDS_CLASS
Note In case kernel is configured with CONFIG_MLXSW_PCI and CONFIG_MLXSW_SPECTRUM, mlxsw kernel hwmon and thermal modules will work over PCI bus. In this case mlxsw_i2c and mlxsw_minimal drivers will not be activated. In other case hwmon and thermal modules will work over I2C bus. If user wants to have both PCI and I2C option configured and want enforce thermal control to work over I2C, for example user which wants to be able to switch between workloads running Mellanox legacy SDK code and running Mellanox switch-dev driver, the next steps should be performed:
Create blacklist file with next wo lines, f.e. /etc/modprobe.d/mellanox-sdk-blacklist.conf blacklist mlxsw_spectrum blacklist mlxsw_pci
And then run: update-initramfs -u (in case initramfs is used) For returning back to PCI option:
Remove /etc/modprobe.d/mellanox-sdk-blacklist.conf
And then run: update-initramfs -u (in case initramfs is used)


# Packaging:
The package depends on the next packages:
- init-system-helpers:	helper tools for all init systems
- lsb-base:		Linux Standard Base init script functionality
- udev:			/dev/ and hotplug management daemon
- i2c-tools:		heterogeneous set of I2C tools for Linux

Package contains the folder debian, with the rules for Debian package build.

Location:
https://github.com/Mellanox/hw-mgmt

To get package sources:
git clone https://mellanoxbsp@github.com/Mellanox/hw-mgmt

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
