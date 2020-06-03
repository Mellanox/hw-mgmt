# Mellanox Hardware Management package
This package supports thermal control and hardware management for Mellanox switches by using a virtual file system provided by the Linux Kernel called `sysfs`.  

The major advantage of working with sysfs is that it makes HW hierarchy easy to understand and control without having to learn about HW component location and the buses through which they are connected.
For detailed information, see the documentation [here](https://github.com/Mellanox/hw-mgmt/tree/master/Documentation).

##### Table of Contents  
- [Supported systems](#supported_systems)
- [Supported Kernel versions](#supported-kernel-versions)
- [Sysfs attributes](#sysfs-attributes)
- [Kernel configuration](#kernel-configuration)
- [Packaging](#packaging)
- [Installation from local file and de-installation](#installation-from-local-file-and-de-installation)
- [Activation, de-activation and reading status](#activation-de-activation-and-reading-status)

## Supported systems:
- MSN2740
- MSN2100
- MSN2410
- MSN2700
- MSN2010
- MQMB7800
- MSN3700
- MSN3800
- MSN4700
- MSN4600C

## Supported Kernel versions:
- 4.9.xx
- 4.19.xx

## Sysfs attributes:
The thermal control operates over sysfs attributes.
These attributes are exposed as symbolic links to `/var/run/hw-management` folder at system boot time.
This folder contains the next structure:

| Node Path | Purpose |
| :--- | :--- |
| /config | Configuration related files. It includes the information about FAN minimum, maximum allowed speed, some default settings, configured delays for different purposes |
| /eeprom | EEPROM related symbolic links to System, PSU, FAN, CPU |
| /environment | Environment (voltage, current, A2D) related symbolic links |
| /led | LED related symbolic links |
| /power | Power related symbolic links |
| /system | System related (health, reset, CPLD version. etc.) related symbolic links |
| /thermal | Thermal related links, including thermal zones related subfolders.<br>`/mlxsw` - ASIC ambient temperature thermal zone related symbolic links.<br>`/mlxsw-moduleX` - QSFP module `X` temperature thermal zone related symbolic links |
| /watchdog | Standard watchdog sysfs attributes |

**Symbolic links examples:**

To get current cooling state, exposed by cooling level (1..10), run:
```
$ cat /var/run/hw-management/thermal/cooling_cur_state
2
```
To get power supply unit `X` power status, where 1 - good and 0 - unplugged/unfunctional, run: 
```
$ cat /var/run/hw-management/thermal/psu1_pwr_status
0
$ cat /var/run/hw-management/thermal/psu2_pwr_status
1
```
To get the switch module ASIC temperature, in millidegrees Celsius, run:
```
$ cat /var/run/hw-management/thermal/asic
39000
```
Detailed information about all available nodes can be found in the documentation [here](https://github.com/Mellanox/hw-mgmt/tree/master/Documentation).

## Kernel configuration
At a minimum, the following configuration options should be set:
```
CONFIG_NET_VENDOR_MELLANOX=y
CONFIG_MELLANOX_PLATFORM=y
CONFIG_NET_DEVLINK=y
CONFIG_I2C=m
CONFIG_I2C_BOARDINFO=y
CONFIG_I2C_CHARDEV=m
CONFIG_I2C_MUX=m
CONFIG_I2C_MUX_REG=m
CONFIG_I2C_MUX_MLXCPLD=m
CONFIG_REGMAP=y
CONFIG_REGMAP_I2C=m
CONFIG_SYSFS=y
CONFIG_DMI_SYSFS=y
CONFIG_GPIO_SYSFS=y
CONFIG_WATCHDOG_SYSFS=y
CONFIG_IIO_SYSFS_TRIGGER=m
CONFIG_NVMEM_SYSFS=y
CONFIG_MLXSW_CORE=m
CONFIG_MLXSW_CORE_HWMON=m
CONFIG_MLXSW_CORE_THERMAL=m
CONFIG_MLXSW_PCI or/and CONFIG_MLXSW_I2C *=m
CONFIG_MLXSW_SPECTRUM or/and CONFIG_MLXSW_MINIMAL *=m
CONFIG_I2C_MLXCPLD=m
CONFIG_LEDS_MLXREG=m
CONFIG_MLX_PLATFORM=m
CONFIG_MLXREG_HOTPLUG=m
CONFIG_MLXREG_IO=m
CONFIG_MLX_WDT=m
CONFIG_THERMAL=y
CONFIG_THERMAL_HWMON=y
CONFIG_THERMAL_WRITABLE_TRIPS=y
CONFIG_THERMAL_DEFAULT_GOV_STEP_WISE=y
CONFIG_THERMAL_GOV_STEP_WISE=y
CONFIG_PMBUS=m
CONFIG_SENSORS_PMBUS=m
CONFIG_HWMON=y
CONFIG_SENSORS_JC42=m
CONFIG_SENSORS_LM75=m
CONFIG_SENSORS_TMP102=m
CONFIG_LEDS_MLXREG=m
CONFIG_LEDS_TRIGGERS=y
CONFIG_LEDS_TRIGGER_TIMER=m
CONFIG_NEW_LEDS=y
CONFIG_LEDS_CLASS=y
CONFIG_EEPROM_AT24=m
CONFIG_EEPROM_EE1004=m
CONFIG_GPIOLIB=y
CONFIG_GPIO_GENERIC=m
CONFIG_MAX1363=m
CONFIG_SENSORS_TPS53679=m
CONFIG_SENSORS_XDPE122=m
CONFIG_GPIO_ICH=m
CONFIG_LPC_ICH=m
CONFIG_CPU_THERMAL=y
CONFIG_X86_PKG_TEMP_THERMAL=m
CONFIG_SENSORS_CORETEMP=m
CONFIG_IGB=y
CONFIG_IGB_HWMON=y
CONFIG_MFD_CORE=m
CONFIG_INOTIFY_USER=y
```
**Note:**
- Kernel version should be v4.19 or later.
- In case the Kernel is configured with `CONFIG_MLXSW_PCI` and `CONFIG_MLXSW_SPECTRUM`, mlxsw kernel hwmon and thermal modules will work over PCI bus.
- In case the Kernel is configured with `CONFIG_MLXSW_I2C` and `CONFIG_MLXSW_MINIMAL`, mlxsw kernel hwmon and thermal modules will work over I2C bus.
- If both Kernel configuration options options have been specified, work over the PCI bus will be selected by default.<br>`mlxsw_i2c` and `mlxsw_minimal` drivers will not be activated.
<br><br>If the user wants to enforce work over I2C (for example, to be able to switch between workloads running Mellanox legacy SDK code and running Mellanox switch-dev driver), the next steps should be performed:
   1. Create a blacklist file with next two lines. For example:
      ```
      $ vi /etc/modprobe.d/hw-management.conf
      blacklist mlxsw_spectrum
      blacklist mlxsw_pci
      ```
   2. And then run: `update-initramfs -u` (in case initramfs is used)
   3. In order to returning back to PCI option, remove `/etc/modprobe.d/mellanox-sdk-blacklist.conf` file and re-run `update-initramfs -u` (in case initramfs is used).

## Packaging:
The package depends on the next packages:
- init-system-helpers: helper tools for all init systems
- bsdutils/util-linux-ng: system logger in debian or Fedora and RHEL.
- udev:			/dev/ and hotplug management daemon
- i2c-tools:		heterogeneous set of I2C tools for Linux<br>
  `i2c-tools_4.1-1` & `libi2c0_4.1-1` or higher

Package contains the folder Debian, with the rules for Debian package build.
Location: `https://github.com/Mellanox/hw-mgmt`
To get package sources: `git clone https://mellanoxbsp@github.com/Mellanox/hw-mgmt`

**For Debian package build:**
On a debian-based system, install the following programs:
sudo apt-get install devscripts build-essential lintian

- Go into the thermal-control base folder and build the Debian package.
- Run: `debuild -us -uc`
- Find in upper folder the builded `.deb` package (for example `hw-management_1.mlnx.18.12.2018_amd64.deb`).

**For converting .deb package to .rpm package:**
- On a Debian-based system, install the `alien` program: `sudo apt-get install alien`
- `alien --to-rpm hw-management_1.mlnx.18.12.2018_amd64.deb`
- Find `hw-management-1.mlnx.18.12.2018-2.x86_64.rpm`

## Installation from local file and de-installation
1. Copy deb or rpm package to the system, for example to `/tmp`.
2. For deb package:
   * install with: `dpkg -i /tmp/ hw-management_1.mlnx.18.12.2018_amd64.deb`
   * remove with: `dpkg --purge hw-management`
3. For rpm package:
   * install with: `yum localinstall /tmp/hw-management-1.mlnx.18.12.2018-2.x86_64.rpm`
     <br>or `rpm -ivh --force /tmp/hw-management-1.mlnx.18.12.2018-2.x86_64.rpm`
   * remove with: `yum remove hw-management` or `rpm -e hw-management`

## Activation, de-activation and reading status
hw-management can be initialized and de-initialized by systemd service.
The next command could be used in order to configure persistent initialization and de-initialization of hw-management:
- `systemctl enable hw-management`
- `systemctl disable hw-management`

The running status of hw-management unit can be obtained by the following command:
- `systemctl status hw-management`

Logging records of the thermal control written by systemd-journald.service can be queried by the following commands:
- `journalctl --unit=hw-management`
- `journalctl -f -u hw-management`

Once `systemctl enable hw-management` is invoked, the thermal control will be automatically activated after the next and the following system reboots, until `systemctl disable hw-management` is not invoked.

The application could be stopped by the `systemctl stop hw-management` command.


## License

This project is Licensed under the GNU General Public License Version 2.

## Acknowledgments

* Mellanox Low-Level Team.
