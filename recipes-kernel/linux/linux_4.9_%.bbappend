FILESEXTRAPATHS_prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://msn.cfg"
SRC_URI += " \
	file://0001-i2c-mlxcpld-add-master-driver-for-mellanox-systems.patch \
	file://0002-mlxsw-Introduce-support-for-I2C-bus.patch \
	file://0003-mlxsw-minimal-Add-I2C-support-for-Mellanox-ASICs.patch \
	file://0004-mlxsw-Fix-mlxsw_i2c_write-return-value.patch \
	file://0005-platform-x86-mlx-platform-Move-module-from-arch-x86.patch \
	file://0006-platform-x86-mlx-platform-Fix-semicolon.cocci-warnin.patch \
	file://0007-platform-x86-mlx-platform-Add-mlxcpld-hotplug-driver.patch \
	file://0008-platform-x86-mlx-platform-mlxcpld-hotplug-driver-sty.patch \
	file://0009-platform-x86-Introduce-support-for-Mellanox-hotplug-.patch \
	file://0010-mlxsw-core-Implement-thermal-zone.patch \
	file://0011-mlxsw-core-backport-work-for-MCIA-and-MFCL-register-.patch \
	file://0012-mlxsw-core-backport-core_hwmon-fixes.patch \
	file://0013-leds-verify-vendor-and-change-license-in-mlxcpld-dri.patch \
	file://0014-i2c-mux-mellanox-add-driver.patch \
	file://0015-i2c-mux-mlxcpld-fix-i2c-mux-selection-caching.patch \
	file://0016-i2c-mux-mlxcpld-remove-unused-including-linux-versio.patch \
	file://0017-hwmon-pmbus-Add-support-for-Intel-VID-protocol-VR13.patch \
	file://0018-hwmon-pmbus-Add-support-for-Texas-Instruments-tps536.patch \
	file://0019-platform-mellanox-Introduce-Mellanox-hardware-platfo.patch \
	file://0020-platform-x86-mlx-platform-modify-hotplug-device-acti.patch \
	file://0021-platform-x86-mlxcpld-hotplug-driver-removing.patch \
	file://0022-leds-add-driver-for-support-Mellanox-regmap-LEDs-for.patch \
	file://0023-mlxsw-core-Implement-QSFP-EEPROM-access-through-sysf.patch \
	file://0024-platform-x86-mlx-platform-add-support-for-new-system.patch \
	file://0025-platform-x86-mlx-platform-add-LED-platform-driver-ac.patch \
	file://0026-i2c-mlxcpld-aligned-structure-after-for-back-porting.patch \
	file://0027-mlxsw-core-disable-setting-temperature-in-hwmon-at-i.patch \
	file://0028-mlxsw-Add-bus-capability-flag.patch \
	file://0029-platform-x86-mlx-platform-add-support-for-new-system.patch \
	file://0030-platform-x86-mlx-platform-align-with-upstream-v15-pa.patch \
	"

