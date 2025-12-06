# NVIDIA Hardware Management package
This package supports thermal control and hardware management for NVIDIA switches by using a virtual file system provided by the Linux Kernel called `sysfs`.  

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
- MSN24102
- MSN2700
- MSN2700-A1
- MSN27002
- MSN2010
- MQMB7800
- MSN3420
- MSN3510
- MSN3700
- MSN3700C
- MSN3700S
- MSN3750SX
- MSN3800
- MSN38XX
- MSN4410
- MSN4600
- MSN4600C
- MSN46XX
- MSN4700
- MSN47XX
- MSN4800
- MSN5600
- MSN5600d
- MSN5700
- MQM8700
- MQM87XX
- MQM9700
- MQM97XX
- MSB78002
- MSB87XX
- MSX87XX
- SGN2410
- SN2201
- SN4280
- SN5400
- SN5600
- SN5610
- SN5640
- SN5700
- N5100LD
- N5101LD
- N5110LD
- N5112LD
- N5200LD
- N5240LD
- N5300LD
- N5500LD
- N61XX_LD
- Q3200
- Q3400
- Q3401
- Q3450
- Q3451
- XH3000
- E3597
- P4697
- P2317
- P4262
- P4300-A00

## Supported Kernel versions:
- 5.10.103, 5.10.140, 5.10.179, 5.10.218, 5.10.226
- 5.14 all up to 5.14.21
- 6.1.38, 6.1.90, ,6.1.94, 6.1.119, 6.1.123
- 6.12.38, 6.12.41, 6.12.44

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
For Intel/amd64 architecture:
CONFIG_NET_VENDOR_MELLANOX=y
CONFIG_MELLANOX_PLATFORM=y
CONFIG_NET_DEVLINK=y
CONFIG_I2C=y
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
CONFIG_NVME_HWMON=y
CONFIG_MLXSW_CORE=m
CONFIG_MLXSW_CORE_HWMON=y
CONFIG_MLXSW_PCI=m or CONFIG_MLXSW_I2C=m
CONFIG_MLXSW_SPECTRUM=m or CONFIG_MLXSW_MINIMAL=m
CONFIG_I2C_MLXCPLD=m
CONFIG_MLX_PLATFORM=m
CONFIG_NVSW_HOST_L1=m
CONFIG_NVSW_HOST_SPC5=m
CONFIG_NVSW_HOST_SPC6=m
CONFIG_MLXREG_HOTPLUG=m
CONFIG_MLXREG_IO=m
CONFIG_MLX_WDT=m
CONFIG_MLXREG_LC=m
CONFIG_THERMAL=y
CONFIG_THERMAL_HWMON=y
CONFIG_THERMAL_WRITABLE_TRIPS=y
CONFIG_THERMAL_DEFAULT_GOV_STEP_WISE=y
CONFIG_THERMAL_GOV_STEP_WISE=y
CONFIG_PMBUS=m
CONFIG_SENSORS_PMBUS=m
CONFIG_HWMON=y
CONFIG_SENSORS_MLXREG_FAN=m
CONFIG_SENSORS_JC42=m
CONFIG_SENSORS_LM75=m
CONFIG_SENSORS_TMP102=m
CONFIG_SENSORS_TMP421=m
CONFIG_SENSORS_STTS751=m
CONFIG_SENSORS_EMC1403=m
CONFIG_LEDS_MLXREG=m
CONFIG_LEDS_TRIGGERS=y
CONFIG_LEDS_TRIGGER_TIMER=m
CONFIG_NEW_LEDS=y
CONFIG_LEDS_CLASS=y
CONFIG_EEPROM_AT24=m
CONFIG_GPIOLIB=y
CONFIG_GPIO_GENERIC=m
CONFIG_MAX1363=m
CONFIG_SENSORS_TPS53679=m
CONFIG_SENSORS_XDPE122=m
CONFIG_SENSORS_MP2975=m
CONFIG_SENSORS_MP2888=m
CONFIG_SENSORS_MP2891=m
CONFIG_GPIO_ICH=m
CONFIG_LPC_ICH=m
CONFIG_CPU_THERMAL=y
CONFIG_X86_PKG_TEMP_THERMAL=m
CONFIG_SENSORS_CORETEMP=m
CONFIG_INTEL_PCH_THERMAL=m
CONFIG_IGB=m
CONFIG_IGB_HWMON=y
CONFIG_INOTIFY_USER=y
CONFIG_MFD_CORE=y
CONFIG_MFD_INTEL_LPSS_PCI=y
CONFIG_MFD_INTEL_LPSS=y
CONFIG_SERIAL_8250_DW=y
CONFIG_SERIAL_8250_DETECT_IRQ=y
CONFIG_I2C_SMBUS=m
CONFIG_I2C_I801=m
CONFIG_PINCTRL=y
CONFIG_DW_DMAC_PCI=y
CONFIG_TI_ADS1015=m
CONFIG_SENSORS_EMC2305=m
CONFIG_SENSORS_POWR1220=m
CONFIG_PINCTRL_INTEL=y
CONFIG_PINCTRL_CANNONLAKE=m
CONFIG_PINCTRL_DENVERTON=m
CONFIG_NVSW_SN2201=m
CONFIG_OF=y
CONFIG_I2C_MUX_PCA954x=m
CONFIG_I2C_DESIGNWARE_PLATFORM=m
CONFIG_I2C_DESIGNWARE_BAYTRAIL=m
CONFIG_I2C_DESIGNWARE_CORE=m
CONFIG_I2C_DESIGNWARE_PCI=m
CONFIG_GPIO_PCA953X=m
CONFIG_SPI_PXA2XX=m
CONFIG_SECURITY_LOCKDOWN_LSM=y (if kernel version >= v5.4, optional up to user)
CONFIG_SECURITY_LOCKDOWN_LSM_EARLY=y (if kernel version >= v5.4, optional up to user)
CONFIG_LOCK_DOWN_KERNEL_FORCE_CONFIDENTIALITY=y (if kernel version >= v5.4, optional up to user)
CONFIG_THERMAL_NETLINK=y (if kernel version >= v5.10)
CONFIG_SENSORS_XDPE152=m
CONFIG_SENSORS_DRIVETEMP=m
CONFIG_SENSORS_IIO_HWMON=m
CONFIG_SENSORS_LM25066=m
CONFIG_SENSORS_UCD9000=m
CONFIG_SENSORS_UCD9200=m
CONFIG_THERMAL_OF=y
CONFIG_SENSORS_K10TEMP=m
CONFIG_SPI_AMD=m
CONFIG_PINCTRL_AMD=y
CONFIG_EDAC_AMD64=m
CONFIG_HW_RANDOM_AMD=m
CONFIG_AMD_XGBE=m
CONFIG_AMD_XGBE_DCB=y
CONFIG_X86_AMD_PLATFORM_DEVICE=y
CONFIG_CPU_SUP_AMD=y
CONFIG_X86_MCE_AMD=y
CONFIG_USB_NET_DRIVERS=m
CONFIG_USB_USBNET=m
CONFIG_USB_NET_CDCETHER=m
CONFIG_HOTPLUG_PCI_PCIE=n
CONFIG_SENSORS_ISL68137=m

For arm64 architecture:
CONFIG_NET_VENDOR_MELLANOX=y
CONFIG_MELLANOX_PLATFORM=y
CONFIG_I2C_MLXCPLD=m
CONFIG_MLX_PLATFORM=m
CONFIG_MLXREG_HOTPLUG=m
CONFIG_MLXREG_IO=m
CONFIG_MLX_WDT=m
CONFIG_MLXBF_GIGE=m
CONFIG_I2C_MLXBF=m
CONFIG_GPIO_MLXBF3=m
CONFIG_MLXBF_TMFIFO=m
CONFIG_MLXBF_BOOTCTL=m
CONFIG_MLXBF_PMC=m
CONFIG_MLXBF_PTM=m
CONFIG_MMC_SDHCI_OF_DWCMSHC=m
CONFIG_VFIO_PLATFORM=m
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
CONFIG_NVME_HWMON=y
CONFIG_MLXSW_CORE=m
CONFIG_MLXSW_CORE_HWMON=y
CONFIG_MLXSW_PCI=m or CONFIG_MLXSW_I2C=m
CONFIG_MLXSW_SPECTRUM=m or CONFIG_MLXSW_MINIMAL=m
CONFIG_THERMAL_STATISTICS=n 
CONFIG_THERMAL=y
CONFIG_THERMAL_HWMON=y
CONFIG_THERMAL_WRITABLE_TRIPS=y
CONFIG_THERMAL_DEFAULT_GOV_STEP_WISE=y
CONFIG_THERMAL_GOV_STEP_WISE=y
CONFIG_PMBUS=m
CONFIG_SENSORS_PMBUS=m
CONFIG_HWMON=y
CONFIG_SENSORS_MLXREG_FAN=m
CONFIG_SENSORS_JC42=m
CONFIG_SENSORS_LM75=m
CONFIG_SENSORS_TMP102=m
CONFIG_SENSORS_TMP421=m
CONFIG_SENSORS_STTS751=m
CONFIG_LEDS_MLXREG=m
CONFIG_LEDS_TRIGGERS=y
CONFIG_LEDS_TRIGGER_TIMER=m
CONFIG_NEW_LEDS=y
CONFIG_LEDS_CLASS=y
CONFIG_EEPROM_AT24=m
CONFIG_GPIOLIB=y
CONFIG_GPIO_GENERIC=m
CONFIG_MAX1363=m
CONFIG_SENSORS_TPS53679=m
CONFIG_SENSORS_XDPE122=m
CONFIG_SENSORS_MP2975=m
CONFIG_SENSORS_MP2888=m
CONFIG_SENSORS_MP2891=m
CONFIG_SENSORS_MP2855=m
CONFIG_IGB=m
CONFIG_IGB_HWMON=y
CONFIG_INOTIFY_USER=y
CONFIG_MFD_CORE=y
CONFIG_I2C_SMBUS=m
CONFIG_TI_ADS1015=m
CONFIG_SENSORS_EMC2305=m
CONFIG_SENSORS_POWR1220=m
CONFIG_OF=y
CONFIG_I2C_MUX_PCA954x=m
CONFIG_GPIO_PCA953X=m
CONFIG_THERMAL_NETLINK=y
CONFIG_SENSORS_XDPE152=m
CONFIG_SENSORS_DRIVETEMP=m
CONFIG_SENSORS_IIO_HWMON=m
CONFIG_SENSORS_LM25066=m
CONFIG_SENSORS_UCD9000=m
CONFIG_SENSORS_UCD9200=m
CONFIG_FUSE_FS=m
CONFIG_SENSORS_ARM_SCMI=m
CONFIG_HOTPLUG_PCI_PCIE=n

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
To get package sources: `git clone https://github.com/Mellanox/hw-mgmt`

**For Debian package build:**
On a debian-based system, install the following programs:
sudo apt-get install devscripts build-essential lintian

- Go into the thermal-control base folder and build the Debian package.
- Run: `debuild -us -uc -b`
- To build for ARM64 architecture, run `debuild -us -uc -b -aarm64`
- To build without lm_sensor dependecy (for Sonic-based OS) run 'debuild --set-envvar=LM_DEPENDS=0 -us -uc -b'
or 'export LM_DEPENDS=0 && dpkg-buildpackage -us -uc -b'
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
hw-management package from release 7.0010.1300 contains 2 separate services:
one-shot hw-management and hw-management-tc thermal control service. hw-management-tc 
is new service starting from 7.0010.1300. In older version TC was part of hw-management service.

If you had TC disabled in previouse release (by commeting out TC activation in hw-management.sh)
Please reffer to the below in order to disable TC using systemctl command 

hw-management services can be initialized and de-initialized by systemd commands.          
The next command could be used in order to configure persistent initialization and 
de-initialization of hw-management service:
- `systemctl enable hw-management`                                               
- `systemctl disable hw-management` 

The next command could be used in order to configure persistent initialization and de-initialization of 
thermal control hw-management-tc service:
- `systemctl enable hw-management-tc`                                               
- `systemctl disable hw-management-tc`                                             
                                                                                 
The running status of hw-management units can be obtained by the following command:
- `systemctl status hw-management`
- `systemctl status hw-management-tc`

Logging records of the thermal control written by systemd-journald.service can be queried by the following commands:
- `journalctl --unit=hw-management`
- `journalctl -f -u hw-management`

Once `systemctl enable hw-management` is invoked, the thermal control will be automatically activated after the next and the following system reboots, until `systemctl disable hw-management` is not invoked.

The application could be stopped by the `systemctl stop hw-management` command.


## License

This project is Licensed under the GNU General Public License Version 2.

## Acknowledgments

* NVIDIA Low-Level Team.
