/**
 *
 * Copyright (C) Mellanox Technologies Ltd. 2001-2015.  ALL RIGHTS RESERVED.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
 *
 */

#include <linux/module.h>
#include <linux/version.h>
#include <linux/types.h>
#include <linux/acpi.h>
#include <linux/slab.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/device.h>
#include <linux/platform_device.h>
#include <linux/mod_devicetable.h>
#include <linux/dmi.h>
#include <linux/capability.h>
#include <linux/mutex.h>
#include <linux/hwmon.h>
#include <linux/hwmon-sysfs.h>
#include <linux/i2c.h>
#include <linux/leds.h>
#include <asm/uaccess.h>
#include <asm/io.h>
#include <linux/thermal.h>
#include "mlnx-common-drv.h"
#include "mlx_sx/kernel_user.h"
#include "device.h"

#define TEMP_POLLING_INTERVAL (30 * 1000) /* interval between two temperature checks is 30 seconds */
#define TEMP_PASSIVE_INTERVAL (30 * 1000) /* interval to wait between polls when performing passive cooling is 30 seconds */
#define MAX_PWM_DUTY_CYCLE    255
#define PWM_DUTY_CYCLE_STEP    10

#define ASIC_GROUP_NUM             4
#define FAN_NUM                   12
#define TACH_PWM_MAP              16
#define FAN_TACH_NUM               4
#define QSFP_MODULE_NUM           64
#define FAN_ATTR_NUM               5
#define TEMP_ATTR_NUM              4
#define CPLD_ATTR_NUM              1
#define QSFP_ATTR_NUM              6
#define QSFP_DATA_VALID_TIME       (120 * 1000) /* 120 seconds */
#define ENTRY_DATA_VALID_TIME      (3 * 1000)   /* 3 seconds */
#define QSFP_PAGE_NUM              5
#define QSFP_SUB_PAGE_NUM          3
#define QSFP_PAGE_SIZE           128
#define QSFP_SUB_PAGE_SIZE        48
#define QSFP_LAST_SUB_PAGE_SIZE   32

enum fan_contol_mode {
	FAN_CTRL_KERNEL,
	FAN_CTRL_US_LEGACY,
	FAN_CTRL_US_PRIVATE,
};

typedef enum qsfp_module_status {
    qsfp_good            = 0x00,
    qsfp_no_eeprrom      = 0x01, /* No response from module's EEPROM. */
    qsfp_not_supported   = 0x02, /* Module type not supported by the device. */
    qsfp_not_connected   = 0x03, /* No module present indication.*/
    qsfp_type_invalid    = 0x04, /* if the module is not qsfp or sfp bus.*/
    qsfp_not_accessiable = 0x05, /* Not accessable module */
    qsfp_i2c_error       = 0x09, /* Error occurred while trying to access the module's EEPROM using i2c */
    qsfp_disable         = 0x10, /*  module is disabled by disable command */
} qsfp_module_status_t;

static inline const char *qsfp_status_2string(qsfp_module_status_t status)
{
    switch (status) {
        case qsfp_good:
            return "good";
        case qsfp_no_eeprrom:
            return "no_eeprrom";
        case qsfp_not_connected:
            return "not_connected";
        case qsfp_type_invalid:
            return "type_invalid";
        case qsfp_not_accessiable:
            return "not_accessiable";
        case qsfp_i2c_error:
            return "i2c_error";
        case qsfp_disable:
            return "disable";
        default:
            return "not exist";
    }
}

typedef enum temp_module_attr {
        temp_input,
        temp_min,
        temp_max,
        temp_crit,
        temp_conf,
} temp_module_attr_t;

typedef enum fan_module_attr {
        fan_power,
        fan_speed_tacho0,
        fan_speed_tacho1,
        fan_speed_tacho2,
        fan_speed_tacho3,
        fan_speed_min,
        fan_speed_max,
        fan_enable,
        fan_conf,
} fan_module_attr_t;

typedef enum qsfp_module_attr {
        qsfp_status,
        qsfp_event,
        qsfp_temp_input,
        qsfp_temp_min,
        qsfp_temp_max,
        qsfp_temp_crit,
} qsfp_module_attr_t;

typedef enum cpld_attr {
        cpld_version,
} cpld_attr_t;

struct fan_config {
	struct mlnx_bsp_entry entry;  /* Entry id */
        u8 num_tachos;                /* Tachometers' number */
	u8 tacho_id[FAN_TACH_NUM];    /* Fan tachometer index */
	u8 pwm_id;                    /* PWM tachometer index */
	u16 speed[FAN_TACH_NUM];      /* Fan speed (Round Per Minute) calculated based on the time measurement between n */
                                      /* fan pulses. Note that in order for the RPM to be correct, the n value should */
                                      /* correspond to the number of tachometer pulses per rotation measured by the tachometer */
	u16 speed_min[FAN_TACH_NUM];  /* Fan speed minimum (Round Per Minute) */
	u16 speed_max[FAN_TACH_NUM];  /* Fan speed maximum (Round Per Minute) */
	u8 enable[FAN_TACH_NUM];      /* Software enable state */
	u8 pwm_duty_cycle;            /* Controls the duty cycle of the PWM. Value range from 0..255 */
};

struct temp_config {
	struct mlnx_bsp_entry entry; /* Entry id */
        u8 sensor_index;             /* Sensors index to access */
        u32 temperature;             /* Temperature reading from the sensor. Reading in 0.125 Celsius degrees */
        u8 mte;                      /* Enables measuring the max temperature on a sensor */
        u8 mtr;                      /* Clears the value of the max temperature register */
        u32 max_temperature;         /* The highest measured temperature from the sensor */
        u8 tee;                      /* Temperature Event Enable */
        u32 temperature_threshold;   /* Generate event if sensor temperature measurement is above the threshold and events enabled */
};

struct qsfp_config {
	struct mlnx_bsp_entry entry; /* Entry id */
        u8 module_index;             /* QSFP modules index to access */
        u8 lock;                     /* Lock bit. Setting this bit will lock the access to the specific cable */
        u8 status;                   /* module status (GOOD, NO_EEPROM_MODULES, MODULE_NOT_CONNECTED, I2C_ERROR, MODULE_DISABLED) */
};

struct cpld_config {
	struct mlnx_bsp_entry entry; /* Entry id */
        u8 index;                    /* CPLD index to access */
        u32 version;                 /* CPLD version */
};

struct temp_config_params {
        u8 num_sensors;
	u8 sensor_active;                /* Indicates number of connected temprature sensors */
        struct temp_config *sensor;
};

struct fan_config_params {
        struct mlnx_bsp_entry entry;   /* Entry id */
        u8 num_fan;
	u8 pwm_frequency;               /* Controls the frequency of the PWM signal */
	u16 pwm_active;                 /* Indicates which of the PWM control is active (bit per PWM) */
	u16 tacho_active;               /* Indicates which of the tachometer is active (bit per tachometer) */
	u8 num_cooling_levels;          /* pwm trip levels number */
	u16 *cooling_levels;            /* pwm trip levels */
	s16 cooling_cur_level;          /* pwm current level */
        struct fan_config *fan;
};

struct qsfp_config_params {
        struct mlnx_bsp_entry entry;   /* Entry id */
        u8 num_modules;
        u32 presence_bitmap[8];
        unsigned long presence_bitmap_valid;
        struct qsfp_config *module;
        struct bin_attribute *eeprom;
        struct bin_attribute **eeprom_attr_list;
};

struct cpld_config_params {
        u8 num_cpld;
        struct cpld_config *cpld;
};

#define LED_OFF_COLOR		0x0000
#define LED_INFINITY_COLOR	0xffff
#define LED_TYPE_UID		1
#define LED_TYPE_PORT		2
struct port_led_pdata {
	struct led_classdev cdev;
	struct switchdev_if *devif;
	const char *name;
	int index;
	u8 led_type;
	spinlock_t lock;
};

#define cdev_to_priv(c)		container_of(c, struct port_led_pdata, cdev)

struct port_led_params {
	struct platform_device *pdev;
	struct switchdev_if *devif;
	int num_led_instances;
	struct port_led_pdata *led;
};

enum ports_capabilty {
	none_drv,
	asic_drv_32_ports,
	asic_drv_64_ports,
	asic_drv_54_ports,
	asic_drv_36_ports,
	asic_drv_16_ports,
	asic_drv_56_ports,
};

enum chips {
	any_chip,
	switchx2,
	spectrum,
};

struct switchdev_if {
        struct mutex access_lock;
        u8 dev_id;
        int (*REG_MFSC)(struct sx_dev *dev, struct ku_access_mfsc_reg *reg_data);
        int (*REG_MFSM)(struct sx_dev *dev, struct ku_access_mfsm_reg *reg_data);
        int (*REG_MTMP)(struct sx_dev *dev, struct ku_access_mtmp_reg *reg_data);
        int (*REG_MTCAP)(struct sx_dev *dev, struct ku_access_mtcap_reg *reg_data);
        int (*REG_MCIA)(struct sx_dev *dev, struct ku_access_mcia_reg *reg_data);
        int (*REG_PMPC)(struct sx_dev *dev, struct ku_access_pmpc_reg *reg_data);
        int (*REG_MSCI)(struct sx_dev *dev, struct ku_access_msci_reg *reg_data);
        int (*REG_MJTAG)(struct sx_dev *dev, struct ku_access_mjtag_reg *reg_data);
        int (*REG_PMAOS)(struct sx_dev *dev, struct ku_access_pmaos_reg *reg_data);
        int (*REG_MFCR)(struct sx_dev *dev, struct ku_access_mfcr_reg *reg_data);
        int (*REG_MGIR)(struct sx_dev *dev, struct ku_access_mgir_reg *reg_data);
        int (*REG_MLCR)(struct sx_dev *dev, struct ku_access_mlcr_reg *reg_data);
        int (*REG_PMLP)(struct sx_dev *dev, struct ku_access_pmlp_reg *reg_data);
        void *(*DEV_CONTEXT)(void);
};

struct asic_data {
	struct list_head               list;
	struct kref                    kref;
        struct i2c_client             *client;
        enum ports_capabilty           port_cap;
        enum chips                     kind;
        struct device                 *hwmon_dev;
        const char                    *name;
        struct mutex                   access_lock;
        struct temp_config_params      temp_config;
        struct fan_config_params       fan_config;
        struct cpld_config_params      cpld_config;
        struct qsfp_config_params      qsfp_config;
	struct port_led_params	       led_config;
        struct attribute_group         group[ASIC_GROUP_NUM];
        const struct attribute_group  *groups[ASIC_GROUP_NUM + 1];
        u8                             asic_id;
        struct switchdev_if            switchdevif;
	struct thermal_cooling_device *tcdev;
	struct thermal_zone_device    *tzdev;
};

#define ASIC_DRV_VERSION "0.0.1 24/08/2015"
#define ASIC_DRV_DESCRIPTION "Mellanox ASIC BSP driver. Build:" " "__DATE__" "__TIME__
MODULE_AUTHOR("Vadim Pasternak (vadimp@mellanox.com)");
MODULE_DESCRIPTION(ASIC_DRV_DESCRIPTION);
MODULE_LICENSE("GPL v2");
MODULE_ALIAS("mlnx-asic");
 
static unsigned short num_cpld = 3;
module_param(num_cpld, ushort, 0);
MODULE_PARM_DESC(num_cpld, "Number of CPLD, default is 3");
static unsigned short num_tachos = 2;
module_param(num_tachos, ushort, 0);
MODULE_PARM_DESC(num_tachos, "Number of tachometers per fan, default is 2");
static unsigned short tacho_flat = 1;
module_param(tacho_flat, ushort, 0);
MODULE_PARM_DESC(tacho_flat, "Each tachometer is presented as fan, default is 1");
static unsigned short speed_min = 10500;
module_param(speed_min, ushort, 0);
MODULE_PARM_DESC(speed, "fan minimum speed (round per minute), default is 10500 RPM");
static unsigned short speed_max = 21000;
module_param(speed_max, ushort, 0);
MODULE_PARM_DESC(speed_max, "fan maximum speed (round per minute), default is 21000 (100 percent)");
static unsigned short pwm_duty_cycle = 153;
module_param(pwm_duty_cycle, ushort, 0);
MODULE_PARM_DESC(pwm_duty_cycle, "Duty cycle of the PWM, value range from 0..255, default is 153");
static unsigned short asic_dev_id = 255;
module_param(asic_dev_id, ushort, 0);
MODULE_PARM_DESC(asic_dev_id, "ASIC device Id, default is 255");
static unsigned short mte = 1;
module_param(mte, ushort, 0);
MODULE_PARM_DESC(mte, "Enable measuring the max temperature, default is enable (1)");
static unsigned short mtr = 0;
module_param(mtr, ushort, 0);
MODULE_PARM_DESC(mte, "Clear the value of the max temperature, default is not clear (0)");
static unsigned short tee = 0;
module_param(tee, ushort, 0);
MODULE_PARM_DESC(tee, "Enable temperature event, default is not disable (0)");
static unsigned short temp_threshold = 80;
module_param(temp_threshold, ushort, 0);
MODULE_PARM_DESC(temp_threshold, "Temprature threshold, default is 80");
static unsigned short qsfp_map[QSFP_MODULE_NUM] = { 64, 65, 66, 67, 68, 69, 70, 71,
                                                    72, 73, 74, 75, 76, 77, 78, 79,
                                                    80, 81, 82, 83, 84, 85, 86, 87,
                                                    88, 89, 90, 91, 92, 93, 94, 95 };
module_param_array(qsfp_map, ushort, NULL, 0644);
MODULE_PARM_DESC(qsfp_map, "Module status offsets vector (default)");
static unsigned short qsfp_eeprom_i2c_addr = 0x50;
module_param(qsfp_eeprom_i2c_addr, ushort, 0);
MODULE_PARM_DESC(qsfp_eeprom_i2c_addr, "I2C address of qsfp module eeprom, default is 0x50");
static unsigned short auto_thermal_control = 0;
module_param(auto_thermal_control, ushort, 0);
MODULE_PARM_DESC(auto_thermal_control, "Automatic thermal control is enable, default is no");
static unsigned short port_led_control = 0;
module_param(port_led_control, ushort, 0);
MODULE_PARM_DESC(port_led_control, "Port led control is enable, default is no");

int mlxsw_local_port_mapping[] = {
	0x2d, 0x2f, 0x2a, 0x2b, 0x26, 0x28, 0x23, 0x25, 0x01, 0x21, 0x05, 0x03,
	0x08, 0x06, 0x0b, 0x0a, 0x0f, 0x0d, 0x1d, 0x1f, 0x19, 0x1b, 0x15, 0x17,
	0x12, 0x14, 0x30, 0x10, 0x34, 0x32, 0x37, 0x35, 0x3b, 0x39, 0x3f, 0x3d,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00
};

#define REG_QUERY (1)
#define REG_WRITE (2)
#define SET_REG_TEMPLATE(reg_data, regid, method, devif) \
        reg_data.op_tlv.type = 1;                        \
        reg_data.op_tlv.length = 4;                      \
        reg_data.op_tlv.dr = 0;                          \
        reg_data.op_tlv.status = 0;                      \
        reg_data.op_tlv.register_id = regid;             \
        reg_data.op_tlv.r = 0;                           \
        reg_data.op_tlv.method = method;                 \
        reg_data.op_tlv.op_class = 1;                    \
        reg_data.op_tlv.tid = 0;                         \
	reg_data.dev_id = devif->dev_id;

#define REG_ACCESS(devif, REGID, reg_data, err)                                     \
	mutex_lock(&devif->access_lock);                                            \
	err = devif->REG_##REGID((struct sx_dev *)devif->DEV_CONTEXT(), &reg_data); \
	mutex_unlock(&devif->access_lock);                                          \
	if (err)                                                                    \
		return err;

#define ENTRY_DATA_VALID(entry, refresh)                                       \
	if (time_before(jiffies, entry.last_updated + refresh) && entry.valid) \
		return 0;

static int fan_get_power(struct switchdev_if *devif, struct fan_config *fan, u8 cache_drop)
{
	int err = 0;
	u8 method = REG_QUERY;
	struct ku_access_mfsc_reg reg_data;

	if (!cache_drop)
		ENTRY_DATA_VALID(fan->entry, ENTRY_DATA_VALID_TIME);

	if (!devif->REG_MFSC || !devif->DEV_CONTEXT)
		return err;

	memset(&reg_data, 0, sizeof(struct ku_access_mfsc_reg));
	SET_REG_TEMPLATE(reg_data, MFSC_REG_ID, method, devif);
        reg_data.mfsc_reg.pwm = fan->pwm_id; /* Will affect all FANs */

        REG_ACCESS(devif, MFSC, reg_data, err);

        fan->entry.last_updated = jiffies;
        fan->entry.valid = 1;
	fan->pwm_duty_cycle = (reg_data.mfsc_reg.pwm_duty_cycle);

	return err;
}

static int fan_set_power(struct switchdev_if *devif, struct fan_config *fan)
{
	int err = 0;
	u8 method = REG_WRITE;
	struct ku_access_mfsc_reg reg_data;

	if (!devif->REG_MFSC || !devif->DEV_CONTEXT)
		return err;

	memset(&reg_data, 0, sizeof(struct ku_access_mfsc_reg));
	SET_REG_TEMPLATE(reg_data, MFSC_REG_ID, method, devif);
        reg_data.mfsc_reg.pwm = fan->pwm_id; /* Will affect all FANs */
	reg_data.mfsc_reg.pwm_duty_cycle = fan->pwm_duty_cycle;

        REG_ACCESS(devif, MFSC, reg_data, err);

	return err;
}

static int fan_get_speed(struct switchdev_if *devif, struct fan_config *fan, char *buf, int tacho_id)
{
	int err = 0;
	u8 method = REG_QUERY;
	struct ku_access_mfsm_reg reg_data;

	ENTRY_DATA_VALID(fan->entry, ENTRY_DATA_VALID_TIME);

	if (!devif->REG_MFSM || !devif->DEV_CONTEXT)
		return ENODEV;

	memset(&reg_data, 0, sizeof(struct ku_access_mfsm_reg));
	SET_REG_TEMPLATE(reg_data, MFSM_REG_ID, method, devif);
        reg_data.mfsm_reg.tacho = fan->tacho_id[tacho_id];

        REG_ACCESS(devif, MFSM, reg_data, err);
        fan->entry.last_updated = jiffies;
        fan->entry.valid = 1;

	fan->speed[tacho_id] = reg_data.mfsm_reg.rpm;

	return err;
}

static int fan_set_enable(struct asic_data *asicdata, int index, u8 enable)
{
	struct fan_config *fan;
	int err = 0;

	fan = &asicdata->fan_config.fan[index];

	switch (enable) {
		case FAN_CTRL_KERNEL:
			fan->pwm_duty_cycle = pwm_duty_cycle;
			err =  fan_set_power(&asicdata->switchdevif, fan);
			if (err)
				return err;

			if (auto_thermal_control) {
				asicdata->fan_config.cooling_cur_level = 0;
				asicdata->tzdev->polling_delay = TEMP_POLLING_INTERVAL;
				asicdata->tzdev->passive_delay = TEMP_PASSIVE_INTERVAL;
				thermal_zone_device_update(asicdata->tzdev);
				pr_notice("kernel mode fan control ON\n");
			}
			break;
		case FAN_CTRL_US_LEGACY:
		case FAN_CTRL_US_PRIVATE:
			if (auto_thermal_control) {
				asicdata->tzdev->polling_delay = 0;
				asicdata->tzdev->passive_delay = 0;
				thermal_zone_device_update(asicdata->tzdev);
				pr_notice("kernel mode fan control OFF\n");
			}
			break;
		default:
			fan->pwm_duty_cycle = MAX_PWM_DUTY_CYCLE;
			err =  fan_set_power(&asicdata->switchdevif, fan);
			if (err)
				return err;

			if (auto_thermal_control) {
				asicdata->tzdev->polling_delay = 0;
				asicdata->tzdev->passive_delay = 0;
				thermal_zone_device_update(asicdata->tzdev);
				pr_notice("kernel mode fan control OFF\n");
			}
			break;

	}
	return err;
}

static int fan_get_config(struct switchdev_if *devif, struct fan_config_params *fan_config)
{
	int err = 0;
	u8 method = REG_QUERY;
	struct ku_access_mfcr_reg reg_data;

	ENTRY_DATA_VALID(fan_config->entry, ENTRY_DATA_VALID_TIME);

	if (!devif->REG_MFCR || !devif->DEV_CONTEXT)
		return ENODEV;

	memset(&reg_data, 0, sizeof(struct ku_access_mfcr_reg));
	SET_REG_TEMPLATE(reg_data, MFCR_REG_ID, method, devif);

        REG_ACCESS(devif, MFCR, reg_data, err);
        fan_config->entry.last_updated = jiffies;
        fan_config->entry.valid = 1;

	fan_config->pwm_frequency = reg_data.mfcr_reg.pwm_frequency;
	fan_config->pwm_active = reg_data.mfcr_reg.pwm_active;
	fan_config->tacho_active = reg_data.mfcr_reg.tacho_active;

	return err;
}

static int temp_get(struct switchdev_if *devif, struct temp_config *temp, u8 id, u8 cache_drop)
{
	int err = 0;
	u8 method = REG_QUERY;
	struct ku_access_mtmp_reg reg_data;

	if (!cache_drop)
		ENTRY_DATA_VALID(temp->entry, ENTRY_DATA_VALID_TIME);

	if (!devif->REG_MTMP || !devif->DEV_CONTEXT)
		return ENODEV;

	memset(&reg_data, 0, sizeof(struct ku_access_mtmp_reg));
	SET_REG_TEMPLATE(reg_data, MTMP_REG_ID, method, devif);
	reg_data.mtmp_reg.sensor_index = temp->sensor_index + id; /* Sensors index to access */

        REG_ACCESS(devif, MTMP, reg_data, err);
        temp->entry.last_updated = jiffies;
        temp->entry.valid = 1;
        /* For temp->temperature < 0 consider to set:
           temp->temperature = 0xffff + ((s16)temp->temperature) + 1;
        */
	temp->temperature = reg_data.mtmp_reg.temperature * 100; /* temp1_input */
	temp->max_temperature = reg_data.mtmp_reg.max_temperature * 100; /* temp1_max */
	temp->temperature_threshold = reg_data.mtmp_reg.temperature_threshold * 100; /* temp1_crit */
	/* temp->temp1_min_hyst = reg_data.temperature_threshold_lo; Not implemented */
	/* temp->temp1_max_hyst = reg_data.temperature_threshold_hi; Not implemented */

        return err;
}

static int temp_get_config(struct switchdev_if *devif, struct temp_config_params *temp_config)
{
	int err = 0;
	u8 method = REG_QUERY;
	struct ku_access_mtcap_reg reg_data;

	if (!devif->REG_MTCAP || !devif->DEV_CONTEXT)
		return ENODEV;

	memset(&reg_data, 0, sizeof(struct ku_access_mtcap_reg));
	SET_REG_TEMPLATE(reg_data, MTCAP_REG_ID, method, devif);

        REG_ACCESS(devif, MTCAP, reg_data, err);

	temp_config->sensor_active = reg_data.mtcap_reg.sensor_count;

	return err;
}

static int qsfp_get(struct switchdev_if *devif, struct qsfp_config *qsfp)
{
	int err = 0;
	u8 method = REG_QUERY;
	struct ku_access_mcia_reg reg_data;

	ENTRY_DATA_VALID(qsfp->entry, ENTRY_DATA_VALID_TIME);

	if (!devif->REG_MCIA || !devif->DEV_CONTEXT)
		return ENODEV;

	memset(&reg_data, 0, sizeof(struct ku_access_mcia_reg));
	SET_REG_TEMPLATE(reg_data, MCIA_REG_ID, method, devif);
        reg_data.mcia_reg.i2c_device_address = qsfp_eeprom_i2c_addr;
        reg_data.mcia_reg.device_address = 0;
        reg_data.mcia_reg.module = qsfp->module_index;
        reg_data.mcia_reg.l = qsfp->lock;
        reg_data.mcia_reg.page_number = 0;
        reg_data.mcia_reg.size = QSFP_SUB_PAGE_SIZE;

        REG_ACCESS(devif, MCIA, reg_data, err);
        qsfp->entry.last_updated = jiffies;
        qsfp->entry.valid = 1;

	qsfp->status = reg_data.mcia_reg.status;

	return err;
}

static int qsfp_get_eeprom(struct switchdev_if *devif, struct qsfp_config *qsfp,
				char *buf, loff_t off, size_t count)
{
	int err = 0, res = 0, i, j, k, size, page = 0, subpage = 0, page_off = 0, subpage_off = 0;
	u8 method = REG_QUERY;
	struct ku_access_mcia_reg reg_data;
	u32 tbuf[12];
	u32 *rbuf;
	u8  page_number[QSFP_PAGE_NUM] = { 0xa0, 0x00, 0x01, 0x02, 0x03 }; /* ftp://ftp.seagate.com/sff/SFF-8436.PDF */
	u16  page_shift[QSFP_PAGE_NUM + 1] = { 0x00, 0x80, 0x80, 0x80, 0x80, 0x00 };
	u16 sub_page_size[QSFP_SUB_PAGE_NUM] = { QSFP_SUB_PAGE_SIZE, QSFP_SUB_PAGE_SIZE, QSFP_LAST_SUB_PAGE_SIZE};
	u16 copysize;

	if (!devif->REG_MCIA || !devif->DEV_CONTEXT)
		return ENODEV;

	memset(&reg_data, 0, sizeof(struct ku_access_mcia_reg));
	SET_REG_TEMPLATE(reg_data, MCIA_REG_ID, method, devif);
        reg_data.mcia_reg.i2c_device_address = qsfp_eeprom_i2c_addr;
        reg_data.mcia_reg.device_address = 0;
        reg_data.mcia_reg.module = qsfp->module_index;
        reg_data.mcia_reg.l = qsfp->lock;

	/* Map offset to correct page number, subpage number and device internal offset */
	page = off / QSFP_PAGE_SIZE;
	page_off = off % QSFP_PAGE_SIZE;
	subpage = page_off / QSFP_SUB_PAGE_SIZE;
	subpage_off = page_off % QSFP_SUB_PAGE_SIZE;
	reg_data.mcia_reg.device_address = subpage_off + page_shift[page];

	for (i = page; i < QSFP_PAGE_NUM; i++) {
		for (j = subpage; j < QSFP_SUB_PAGE_NUM; j++) {
        		reg_data.mcia_reg.page_number = page_number[i];
        		if (j == subpage)
        			reg_data.mcia_reg.size = sub_page_size[j] - subpage_off;
        		else
        			reg_data.mcia_reg.size = sub_page_size[j];

			REG_ACCESS(devif, MCIA, reg_data, err);

			if (reg_data.mcia_reg.status)
				return err;

			rbuf = &reg_data.mcia_reg.dword_0;
			size = ((reg_data.mcia_reg.size % 4) == 0) ? (reg_data.mcia_reg.size / 4) :
				(reg_data.mcia_reg.size / 4) + 1;
			for (k = 0; k < size; k++, rbuf++) {
				tbuf[k] = ntohl(*rbuf);
			}

			if (count > reg_data.mcia_reg.size)
				copysize = reg_data.mcia_reg.size;
			else 
				copysize = count;

			memcpy(buf, tbuf, copysize);

			buf += copysize;
			off += copysize;
			count -= copysize;
			res += copysize;
			reg_data.mcia_reg.device_address += copysize;

			if (count <= 0)
				return res;
		}
		reg_data.mcia_reg.device_address = page_shift[i + 1];
	}

	return res;
}

static int qsfp_get_event(struct switchdev_if *devif, struct qsfp_config_params *qsfp_config)
{
	int err = 0, i;
	u8 method = REG_QUERY;
	struct ku_access_pmpc_reg reg_data;

	ENTRY_DATA_VALID(qsfp_config->entry, ENTRY_DATA_VALID_TIME);

	if (!devif->REG_PMPC || !devif->DEV_CONTEXT)
		return ENODEV;

	memset(&reg_data, 0, sizeof(struct ku_access_pmpc_reg));
	SET_REG_TEMPLATE(reg_data, PMPC_REG_ID, method, devif);

        REG_ACCESS(devif, PMPC, reg_data, err);
        qsfp_config->entry.last_updated = jiffies;
        qsfp_config->entry.valid = 1;

	for (i = 0; i < 8; i++)
		qsfp_config->presence_bitmap[7 - i] = reg_data.pmpc_reg.module_state_updated_bitmap[i];

	return err;
}

static int qsfp_set_event(struct switchdev_if *devif, u32 *bitmap)
{
	int err = 0;
	u8 method = REG_WRITE;
	struct ku_access_pmpc_reg reg_data;

	if (!devif->REG_PMPC || !devif->DEV_CONTEXT)
		return ENODEV;

	memset(&reg_data, 0, sizeof(struct ku_access_pmpc_reg));
	SET_REG_TEMPLATE(reg_data, PMPC_REG_ID, method, devif);

	memcpy(reg_data.pmpc_reg.module_state_updated_bitmap, bitmap,
		sizeof(reg_data.pmpc_reg.module_state_updated_bitmap[0] * 8));

        REG_ACCESS(devif, PMPC, reg_data, err);

	return err;
}

#define MSCI_REG_ID 0x902A /* Missed defenition */
static int cpld_get(struct switchdev_if *devif, struct cpld_config *cpld)
{
	int err = 0;
	u8 method = REG_QUERY;
	struct ku_access_msci_reg reg_data;

	if (!devif->REG_MSCI || !devif->DEV_CONTEXT)
		return err;

	memset(&reg_data, 0, sizeof(struct ku_access_msci_reg));
	SET_REG_TEMPLATE(reg_data, MSCI_REG_ID, method, devif);
        reg_data.msci_reg.index = cpld->index;

        REG_ACCESS(devif, MSCI, reg_data, err);
        cpld->entry.last_updated = jiffies;
        cpld->entry.valid = 1;

	cpld->version = reg_data.msci_reg.version;

	return err;
}

static int mgir_get(struct switchdev_if *devif, u16 *device_id)
{
	int err = 0;
	u8 method = REG_QUERY;
	struct ku_access_mgir_reg reg_data;

	if (!devif->REG_MGIR || !devif->DEV_CONTEXT)
		return err;

	memset(&reg_data, 0, sizeof(struct ku_access_mgir_reg));
	SET_REG_TEMPLATE(reg_data, MGIR_REG_ID, method, devif);

        REG_ACCESS(devif, MGIR, reg_data, err);

        *device_id = reg_data.mgir_reg.hw_info.device_id;

	return err;
}

static int pmlp_get(struct switchdev_if *devif, u8 local_port, u8 *width)
{
	int err = 0;
	u8 method = REG_QUERY;
	struct ku_access_pmlp_reg reg_data;

	if (!devif->REG_PMLP || !devif->DEV_CONTEXT)
		return err;

	memset(&reg_data, 0, sizeof(struct ku_access_mgir_reg));
	SET_REG_TEMPLATE(reg_data, PMLP_REG_ID, method, devif);
        reg_data.pmlp_reg.local_port = local_port;

        REG_ACCESS(devif, PMLP, reg_data, err);

	*width = reg_data.pmlp_reg.width;

	return err;
}

static ssize_t store_temp(struct device *dev,
			  struct device_attribute *devattr,
			  const char *buf,
			  size_t count)
{
	struct asic_data *asicdata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	struct temp_config *temp = NULL;

	temp = &asicdata->temp_config.sensor[index];
	if (!temp)
		return -EEXIST;

        switch (nr) {
        case temp_min:
                break;
        default:
                return -EEXIST;
        }

	return count;
}

static ssize_t show_temp(struct device *dev,
			 struct device_attribute *devattr,
			 char *buf)
{
	struct asic_data *asicdata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	struct temp_config *temp = NULL;
	int err = 0, res = 0;

	temp = &asicdata->temp_config.sensor[index];
	if (!temp)
		return -EEXIST;

        switch (nr) {
        case temp_input:
	        err = temp_get(&asicdata->switchdevif, temp, 0, 0);
		if (err)
			return -EEXIST;
	        res = temp->temperature;
                break;
        case temp_min:
                break;
        case temp_max:
	        err = temp_get(&asicdata->switchdevif, temp, 0, 0);
		if (err)
			return -EEXIST;
	        res = temp->max_temperature;
                break;
        case temp_crit:
	        err = temp_get(&asicdata->switchdevif, temp, 0, 0);
		if (err)
			return -EEXIST;
	        res = temp->temperature_threshold;
                break;
        case temp_conf:
		if (!temp_get_config(&asicdata->switchdevif, &asicdata->temp_config))
		        res = asicdata->temp_config.sensor_active;
		else
		        goto req_err;
		break;
        default:
                return -EEXIST;
        }

	return sprintf(buf, "%d\n", res);

req_err:
	if (err != ENODEV)
		return err;
	else
		return sprintf(buf, "%d\n", res);
}

static ssize_t store_fan(struct device *dev,
			 struct device_attribute *devattr,
			 const char *buf,
			 size_t count)
{
	struct asic_data *asicdata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	struct fan_config *fan = NULL;
	int err;

	fan = &asicdata->fan_config.fan[index];
	if (!fan)
		return -EEXIST;

	switch (nr) {
	case fan_power:
		fan->pwm_duty_cycle = simple_strtoul(buf, NULL, 10);
		if (fan->pwm_duty_cycle < pwm_duty_cycle)
			fan->pwm_duty_cycle = pwm_duty_cycle;
		err = fan_set_power(&asicdata->switchdevif, fan);
		break;
	case fan_speed_min:
		fan->speed_min[0] = simple_strtoul(buf, NULL, 10);
		break;
	case fan_speed_max:
		fan->speed_max[0] = simple_strtoul(buf, NULL, 10);
		break;
	case fan_enable:
		fan->enable[0] = simple_strtoul(buf, NULL, 10);
		err = fan_set_enable(asicdata, index, fan->enable[0]);
		if (err)
			return -EEXIST;
		break;
	default:
		return -EEXIST;
	}
 
	return count;
}

static ssize_t show_fan(struct device *dev,
			struct device_attribute *devattr,
			char *buf)
{
	struct asic_data *asicdata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	struct fan_config *fan = NULL;
	int err = 0, res = 0;

	fan = &asicdata->fan_config.fan[index];
	if (!fan)
		return -EEXIST;

	switch (nr) {
        case fan_power:
		err = fan_get_power(&asicdata->switchdevif, fan, 0);
		if (err)
			return -EEXIST;
		res = fan->pwm_duty_cycle;
		break;
        case fan_speed_tacho0:
		if (!fan_get_speed(&asicdata->switchdevif, fan, buf, 0))
		        res = fan->speed[0];
		else
		        goto req_err;
		break;
        case fan_speed_tacho1:
		err = fan_get_speed(&asicdata->switchdevif, fan, buf, 1);
		if (err)
			return -EEXIST;
		res = fan->speed[1];
		break;
        case fan_speed_tacho2:
		err = fan_get_speed(&asicdata->switchdevif, fan, buf, 2);
		if (err)
			return -EEXIST;
		res = fan->speed[2];
		break;
        case fan_speed_tacho3:
		err = fan_get_speed(&asicdata->switchdevif, fan, buf, 3);
		if (err)
			return -EEXIST;
		res = fan->speed[3];
		break;
        case fan_speed_min:
		res = fan->speed_min[0];
		break;
	case fan_speed_max:
		res = fan->speed_max[0];
		break;
	case fan_enable:
		res = fan->enable[0];
		break;
	case fan_conf:
		if (!fan_get_config(&asicdata->switchdevif, &asicdata->fan_config))
		        res = asicdata->fan_config.tacho_active;
		else
		        goto req_err;
		break;
	default:
		return -EEXIST;
	}
 
	return sprintf(buf, "%d\n", res);

req_err:
	if (err != ENODEV)
		return err;
	else
		return sprintf(buf, "%d\n", res);
}


static ssize_t show_qsfp(struct device *dev,
			 struct device_attribute *devattr,
			 char *buf)
{
	struct asic_data *asicdata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	struct qsfp_config *qsfp = NULL;
	struct temp_config *temp = NULL;
	u8 val;
	int res = 0;

	qsfp = &asicdata->qsfp_config.module[index];
	if (!qsfp)
		return -EEXIST;

	temp = &asicdata->temp_config.sensor[0];
	if (!temp)
		return -EEXIST;

	switch (nr) {
	case qsfp_status:
		res = qsfp_get(&asicdata->switchdevif, qsfp);
		if (res)
			return sprintf(buf, "%s\n", "request error");
		else
			return sprintf(buf, "%s\n", qsfp_status_2string(qsfp->status));

	case qsfp_event:
		res = qsfp_get_event(&asicdata->switchdevif, &asicdata->qsfp_config);
		if (res) {
			return sprintf(buf, "%s\n", "request error");
		}
		val = (asicdata->qsfp_config.presence_bitmap[(index / 32)] &
			(BIT_MASK(index % 32))) >> (index % 32);
		return sprintf(buf, "%d\n", val);

	case qsfp_temp_input:
	        res = temp_get(&asicdata->switchdevif, temp, qsfp_map[index], 0);
		if (res) {
			return sprintf(buf, "%s\n", "request error");
		}
	        res = temp->temperature;
                break;

        case qsfp_temp_min:
                break;

        case qsfp_temp_max:
	        res = temp_get(&asicdata->switchdevif, temp, qsfp_map[index], 0);
		if (res) {
			return sprintf(buf, "%s\n", "request error");
		}
	        res = temp->max_temperature;
                break;

        case qsfp_temp_crit:
	        res = temp_get(&asicdata->switchdevif, temp, qsfp_map[index], 0);
		if (res) {
			return sprintf(buf, "%s\n", "request error");
		}
	        res = temp->temperature_threshold;
                break;
	default:
		return -EEXIST;
	}

	return sprintf(buf, "%d\n", res);
}

static ssize_t store_qsfp(struct device *dev,
			  struct device_attribute *devattr,
			  const char *buf,
			  size_t count)
{
	struct asic_data *asicdata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	struct qsfp_config *qsfp = NULL;
	struct temp_config *temp = NULL;
	u32 presence_bitmap[8];
	u32 setmask = ~BIT_MASK(index % 32);
	u32 defmask = 0xffffffff;
	int err, i;

	qsfp = &asicdata->qsfp_config.module[index];
	if (!qsfp)
		return -EEXIST;

	temp = &asicdata->temp_config.sensor[index];
	if (!temp)
		return -EEXIST;

        switch (nr) {
        case qsfp_temp_min:
                break;
	case qsfp_event:
		for (i = 0; i < 8; i++) {
			presence_bitmap[7 - i] = ((index / 32) == i) ? setmask : defmask;
		}
		err = qsfp_set_event(&asicdata->switchdevif, presence_bitmap);
		if (err)
			return -EEXIST;
                break;
        default:
                return -EEXIST;
        }

	return count;
}
static ssize_t show_cpld(struct device *dev,
			 struct device_attribute *devattr,
			 char *buf)
{
	struct asic_data *asicdata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	struct cpld_config *cpld = NULL;
	int res = 0;

	cpld = &asicdata->cpld_config.cpld[index];
	if (!cpld)
		return -EEXIST;

	switch (nr) {
	case cpld_version:
		res = cpld_get(&asicdata->switchdevif, cpld);
		if (res)
			return sprintf(buf, "%s\n", "request error");
		else
			return sprintf(buf, "%d\n", cpld->version);
	default:
		return -EEXIST;
	}

	return sprintf(buf, "%d\n", res);
}

static ssize_t qsfp_eeprom_bin_read(struct file *filp, struct kobject *kobj,
                                    struct bin_attribute *attr,
                                    char *buf, loff_t off, size_t count)
{
	struct asic_data *asicdata = dev_get_drvdata(container_of(kobj, struct device, kobj));
	struct qsfp_config *module = (struct qsfp_config *)attr->private;

	if (off > asicdata->qsfp_config.eeprom[module->module_index].size)
		return -ESPIPE;
	if (off == asicdata->qsfp_config.eeprom[module->module_index].size)
		return 0;
	if ((off + count) > asicdata->qsfp_config.eeprom[module->module_index].size)
		count = asicdata->qsfp_config.eeprom[module->module_index].size - off;

        return qsfp_get_eeprom(&asicdata->switchdevif, module, buf, off, count);
}

/* Attributes */
#define SENSOR_DEVICE_ATTR_TEMP(id)                            \
static SENSOR_DEVICE_ATTR_2(temp##id##_input, S_IRUGO,         \
        show_temp, NULL, temp_input, id - 1);                  \
static SENSOR_DEVICE_ATTR_2(temp##id##_min, S_IRUGO | S_IWUSR, \
        show_temp, store_temp, temp_min, id - 1);              \
static SENSOR_DEVICE_ATTR_2(temp##id##_max, S_IRUGO,           \
        show_temp, NULL, temp_max, id - 1);                    \
static SENSOR_DEVICE_ATTR_2(temp##id##_crit, S_IRUGO,          \
        show_temp, NULL, temp_crit, id - 1)

SENSOR_DEVICE_ATTR_TEMP(1);
SENSOR_DEVICE_ATTR_TEMP(2);
SENSOR_DEVICE_ATTR_TEMP(3);
SENSOR_DEVICE_ATTR_TEMP(4);
SENSOR_DEVICE_ATTR_TEMP(5);
SENSOR_DEVICE_ATTR_TEMP(6);
SENSOR_DEVICE_ATTR_TEMP(7);
SENSOR_DEVICE_ATTR_TEMP(8);
SENSOR_DEVICE_ATTR_TEMP(9);
SENSOR_DEVICE_ATTR_TEMP(10);
SENSOR_DEVICE_ATTR_TEMP(11);
SENSOR_DEVICE_ATTR_TEMP(12);
SENSOR_DEVICE_ATTR_TEMP(13);
SENSOR_DEVICE_ATTR_TEMP(14);
SENSOR_DEVICE_ATTR_TEMP(15);
SENSOR_DEVICE_ATTR_TEMP(16);
SENSOR_DEVICE_ATTR_TEMP(17);
SENSOR_DEVICE_ATTR_TEMP(18);
SENSOR_DEVICE_ATTR_TEMP(19);
SENSOR_DEVICE_ATTR_TEMP(20);
SENSOR_DEVICE_ATTR_TEMP(21);
SENSOR_DEVICE_ATTR_TEMP(22);
SENSOR_DEVICE_ATTR_TEMP(23);
SENSOR_DEVICE_ATTR_TEMP(24);
SENSOR_DEVICE_ATTR_TEMP(25);
SENSOR_DEVICE_ATTR_TEMP(26);
SENSOR_DEVICE_ATTR_TEMP(27);
SENSOR_DEVICE_ATTR_TEMP(28);
SENSOR_DEVICE_ATTR_TEMP(29);
SENSOR_DEVICE_ATTR_TEMP(30);
SENSOR_DEVICE_ATTR_TEMP(31);
SENSOR_DEVICE_ATTR_TEMP(32);
SENSOR_DEVICE_ATTR_TEMP(33);
SENSOR_DEVICE_ATTR_TEMP(34);
SENSOR_DEVICE_ATTR_TEMP(35);
SENSOR_DEVICE_ATTR_TEMP(36);
SENSOR_DEVICE_ATTR_TEMP(37);
SENSOR_DEVICE_ATTR_TEMP(38);
SENSOR_DEVICE_ATTR_TEMP(39);
SENSOR_DEVICE_ATTR_TEMP(40);
SENSOR_DEVICE_ATTR_TEMP(41);
SENSOR_DEVICE_ATTR_TEMP(42);
SENSOR_DEVICE_ATTR_TEMP(43);
SENSOR_DEVICE_ATTR_TEMP(44);
SENSOR_DEVICE_ATTR_TEMP(45);
SENSOR_DEVICE_ATTR_TEMP(46);
SENSOR_DEVICE_ATTR_TEMP(47);
SENSOR_DEVICE_ATTR_TEMP(48);
SENSOR_DEVICE_ATTR_TEMP(49);
SENSOR_DEVICE_ATTR_TEMP(50);
SENSOR_DEVICE_ATTR_TEMP(51);
SENSOR_DEVICE_ATTR_TEMP(52);
SENSOR_DEVICE_ATTR_TEMP(53);
SENSOR_DEVICE_ATTR_TEMP(54);
SENSOR_DEVICE_ATTR_TEMP(55);
SENSOR_DEVICE_ATTR_TEMP(56);
SENSOR_DEVICE_ATTR_TEMP(57);
SENSOR_DEVICE_ATTR_TEMP(58);
SENSOR_DEVICE_ATTR_TEMP(59);
SENSOR_DEVICE_ATTR_TEMP(60);
SENSOR_DEVICE_ATTR_TEMP(61);
SENSOR_DEVICE_ATTR_TEMP(62);
SENSOR_DEVICE_ATTR_TEMP(63);
SENSOR_DEVICE_ATTR_TEMP(64);
SENSOR_DEVICE_ATTR_TEMP(65);

#define SENSOR_DEVICE_ATTR_FAN(id)                               \
static SENSOR_DEVICE_ATTR_2(pwm##id, S_IRUGO | S_IWUSR,          \
        show_fan, store_fan, fan_power, id - 1);                 \
static SENSOR_DEVICE_ATTR_2(fan##id##_input, S_IRUGO,            \
        show_fan, NULL, fan_speed_tacho0, id - 1);               \
static SENSOR_DEVICE_ATTR_2(fan##id##_min, S_IRUGO | S_IWUSR,    \
        show_fan, store_fan, fan_speed_min, id - 1);             \
static SENSOR_DEVICE_ATTR_2(fan##id##_max, S_IRUGO | S_IWUSR,    \
        show_fan, store_fan, fan_speed_max, id - 1);             \
static SENSOR_DEVICE_ATTR_2(fan##id##_enable, S_IRUGO | S_IWUSR, \
        show_fan, store_fan, fan_enable, id - 1);

SENSOR_DEVICE_ATTR_FAN(1);
SENSOR_DEVICE_ATTR_FAN(2);
SENSOR_DEVICE_ATTR_FAN(3);
SENSOR_DEVICE_ATTR_FAN(4);
SENSOR_DEVICE_ATTR_FAN(5);
SENSOR_DEVICE_ATTR_FAN(6);
SENSOR_DEVICE_ATTR_FAN(7);
SENSOR_DEVICE_ATTR_FAN(8);
SENSOR_DEVICE_ATTR_FAN(9);
SENSOR_DEVICE_ATTR_FAN(10);

#define SENSOR_DEVICE_ATTR_CPLD(id)                      \
static SENSOR_DEVICE_ATTR_2(cpld##id##_version, S_IRUGO, \
        show_cpld, NULL, cpld_version, id - 1);

SENSOR_DEVICE_ATTR_CPLD(1);
SENSOR_DEVICE_ATTR_CPLD(2);
SENSOR_DEVICE_ATTR_CPLD(3);

#define SENSOR_DEVICE_ATTR_QSFP(id)                                 \
static SENSOR_DEVICE_ATTR_2(qsfp##id##_status, S_IRUGO,             \
        show_qsfp, NULL, qsfp_status, id - 1);                      \
static SENSOR_DEVICE_ATTR_2(qsfp##id##_event, S_IRUGO | S_IWUSR,    \
        show_qsfp, store_qsfp, qsfp_event, id - 1);                 \
static SENSOR_DEVICE_ATTR_2(qsfp##id##_temp_input, S_IRUGO,         \
        show_qsfp, NULL, qsfp_temp_input, id - 1);                  \
static SENSOR_DEVICE_ATTR_2(qsfp##id##_temp_min, S_IRUGO | S_IWUSR, \
        show_qsfp, store_qsfp, qsfp_temp_min, id - 1);              \
static SENSOR_DEVICE_ATTR_2(qsfp##id##_temp_max, S_IRUGO,           \
        show_qsfp, NULL, qsfp_temp_max, id - 1);                    \
static SENSOR_DEVICE_ATTR_2(qsfp##id##_temp_crit, S_IRUGO,          \
        show_qsfp, NULL, qsfp_temp_crit, id - 1)

SENSOR_DEVICE_ATTR_QSFP(1);
SENSOR_DEVICE_ATTR_QSFP(2);
SENSOR_DEVICE_ATTR_QSFP(3);
SENSOR_DEVICE_ATTR_QSFP(4);
SENSOR_DEVICE_ATTR_QSFP(5);
SENSOR_DEVICE_ATTR_QSFP(6);
SENSOR_DEVICE_ATTR_QSFP(7);
SENSOR_DEVICE_ATTR_QSFP(8);
SENSOR_DEVICE_ATTR_QSFP(9);
SENSOR_DEVICE_ATTR_QSFP(10);
SENSOR_DEVICE_ATTR_QSFP(11);
SENSOR_DEVICE_ATTR_QSFP(12);
SENSOR_DEVICE_ATTR_QSFP(13);
SENSOR_DEVICE_ATTR_QSFP(14);
SENSOR_DEVICE_ATTR_QSFP(15);
SENSOR_DEVICE_ATTR_QSFP(16);
SENSOR_DEVICE_ATTR_QSFP(17);
SENSOR_DEVICE_ATTR_QSFP(18);
SENSOR_DEVICE_ATTR_QSFP(19);
SENSOR_DEVICE_ATTR_QSFP(20);
SENSOR_DEVICE_ATTR_QSFP(21);
SENSOR_DEVICE_ATTR_QSFP(22);
SENSOR_DEVICE_ATTR_QSFP(23);
SENSOR_DEVICE_ATTR_QSFP(24);
SENSOR_DEVICE_ATTR_QSFP(25);
SENSOR_DEVICE_ATTR_QSFP(26);
SENSOR_DEVICE_ATTR_QSFP(27);
SENSOR_DEVICE_ATTR_QSFP(28);
SENSOR_DEVICE_ATTR_QSFP(29);
SENSOR_DEVICE_ATTR_QSFP(30);
SENSOR_DEVICE_ATTR_QSFP(31);
SENSOR_DEVICE_ATTR_QSFP(32);
SENSOR_DEVICE_ATTR_QSFP(33);
SENSOR_DEVICE_ATTR_QSFP(34);
SENSOR_DEVICE_ATTR_QSFP(35);
SENSOR_DEVICE_ATTR_QSFP(36);
SENSOR_DEVICE_ATTR_QSFP(37);
SENSOR_DEVICE_ATTR_QSFP(38);
SENSOR_DEVICE_ATTR_QSFP(39);
SENSOR_DEVICE_ATTR_QSFP(40);
SENSOR_DEVICE_ATTR_QSFP(41);
SENSOR_DEVICE_ATTR_QSFP(42);
SENSOR_DEVICE_ATTR_QSFP(43);
SENSOR_DEVICE_ATTR_QSFP(44);
SENSOR_DEVICE_ATTR_QSFP(45);
SENSOR_DEVICE_ATTR_QSFP(46);
SENSOR_DEVICE_ATTR_QSFP(47);
SENSOR_DEVICE_ATTR_QSFP(48);
SENSOR_DEVICE_ATTR_QSFP(49);
SENSOR_DEVICE_ATTR_QSFP(50);
SENSOR_DEVICE_ATTR_QSFP(51);
SENSOR_DEVICE_ATTR_QSFP(52);
SENSOR_DEVICE_ATTR_QSFP(53);
SENSOR_DEVICE_ATTR_QSFP(54);
SENSOR_DEVICE_ATTR_QSFP(55);
SENSOR_DEVICE_ATTR_QSFP(56);
SENSOR_DEVICE_ATTR_QSFP(57);
SENSOR_DEVICE_ATTR_QSFP(58);
SENSOR_DEVICE_ATTR_QSFP(59);
SENSOR_DEVICE_ATTR_QSFP(60);
SENSOR_DEVICE_ATTR_QSFP(61);
SENSOR_DEVICE_ATTR_QSFP(62);
SENSOR_DEVICE_ATTR_QSFP(63);
SENSOR_DEVICE_ATTR_QSFP(64);

static char *qsfp_eeprom_names[] = {
        "qsfp1_eeprom",
        "qsfp2_eeprom",
        "qsfp3_eeprom",
        "qsfp4_eeprom",
        "qsfp5_eeprom",
        "qsfp6_eeprom",
        "qsfp7_eeprom",
        "qsfp8_eeprom",
        "qsfp9_eeprom",
        "qsfp10_eeprom",
        "qsfp11_eeprom",
        "qsfp12_eeprom",
        "qsfp13_eeprom",
        "qsfp14_eeprom",
        "qsfp15_eeprom",
        "qsfp16_eeprom",
        "qsfp17_eeprom",
        "qsfp18_eeprom",
        "qsfp19_eeprom",
        "qsfp20_eeprom",
        "qsfp21_eeprom",
        "qsfp22_eeprom",
        "qsfp23_eeprom",
        "qsfp24_eeprom",
        "qsfp25_eeprom",
        "qsfp26_eeprom",
        "qsfp27_eeprom",
        "qsfp28_eeprom",
        "qsfp29_eeprom",
        "qsfp30_eeprom",
        "qsfp31_eeprom",
        "qsfp32_eeprom",
        "qsfp33_eeprom",
        "qsfp34_eeprom",
        "qsfp35_eeprom",
        "qsfp36_eeprom",
        "qsfp37_eeprom",
        "qsfp38_eeprom",
        "qsfp39_eeprom",
        "qsfp40_eeprom",
        "qsfp41_eeprom",
        "qsfp42_eeprom",
        "qsfp43_eeprom",
        "qsfp44_eeprom",
        "qsfp45_eeprom",
        "qsfp46_eeprom",
        "qsfp47_eeprom",
        "qsfp48_eeprom",
        "qsfp49_eeprom",
        "qsfp50_eeprom",
        "qsfp51_eeprom",
        "qsfp52_eeprom",
        "qsfp53_eeprom",
        "qsfp54_eeprom",
        "qsfp55_eeprom",
        "qsfp56_eeprom",
        "qsfp57_eeprom",
        "qsfp58_eeprom",
        "qsfp59_eeprom",
        "qsfp60_eeprom",
        "qsfp61_eeprom",
        "qsfp62_eeprom",
        "qsfp63_eeprom",
        "qsfp64_eeprom",
};

#define TEMP_ATTRS(id)                                   \
        &sensor_dev_attr_temp##id##_input.dev_attr.attr, \
        &sensor_dev_attr_temp##id##_min.dev_attr.attr,   \
        &sensor_dev_attr_temp##id##_max.dev_attr.attr,   \
        &sensor_dev_attr_temp##id##_crit.dev_attr.attr,

#define FAN_ATTRS(id)                                   \
        &sensor_dev_attr_pwm##id.dev_attr.attr,         \
        &sensor_dev_attr_fan##id##_input.dev_attr.attr, \
        &sensor_dev_attr_fan##id##_min.dev_attr.attr,   \
        &sensor_dev_attr_fan##id##_max.dev_attr.attr,   \
        &sensor_dev_attr_fan##id##_enable.dev_attr.attr,

#define CPLD_ATTRS(id)                                     \
        &sensor_dev_attr_cpld##id##_version.dev_attr.attr,

#define QSFP_ATTRS(id)                                        \
        &sensor_dev_attr_qsfp##id##_status.dev_attr.attr,     \
        &sensor_dev_attr_qsfp##id##_event.dev_attr.attr,      \
        &sensor_dev_attr_qsfp##id##_temp_input.dev_attr.attr, \
        &sensor_dev_attr_qsfp##id##_temp_min.dev_attr.attr,   \
        &sensor_dev_attr_qsfp##id##_temp_max.dev_attr.attr,   \
        &sensor_dev_attr_qsfp##id##_temp_crit.dev_attr.attr,

static struct attribute *temp_attributes[] = {
        TEMP_ATTRS(1)
        TEMP_ATTRS(2)
        TEMP_ATTRS(3)
        TEMP_ATTRS(4)
        TEMP_ATTRS(5)
        TEMP_ATTRS(6)
        TEMP_ATTRS(7)
        TEMP_ATTRS(8)
        TEMP_ATTRS(9)
        TEMP_ATTRS(10)
        TEMP_ATTRS(11)
        TEMP_ATTRS(12)
        TEMP_ATTRS(13)
        TEMP_ATTRS(14)
        TEMP_ATTRS(15)
        TEMP_ATTRS(16)
        TEMP_ATTRS(17)
        TEMP_ATTRS(18)
        TEMP_ATTRS(19)
        TEMP_ATTRS(20)
        TEMP_ATTRS(21)
        TEMP_ATTRS(22)
        TEMP_ATTRS(23)
        TEMP_ATTRS(24)
        TEMP_ATTRS(25)
        TEMP_ATTRS(26)
        TEMP_ATTRS(27)
        TEMP_ATTRS(28)
        TEMP_ATTRS(29)
        TEMP_ATTRS(30)
        TEMP_ATTRS(31)
        TEMP_ATTRS(32)
        TEMP_ATTRS(33)
        TEMP_ATTRS(34)
        TEMP_ATTRS(35)
        TEMP_ATTRS(36)
        TEMP_ATTRS(37)
        TEMP_ATTRS(38)
        TEMP_ATTRS(39)
        TEMP_ATTRS(40)
        TEMP_ATTRS(41)
        TEMP_ATTRS(42)
        TEMP_ATTRS(43)
        TEMP_ATTRS(44)
        TEMP_ATTRS(45)
        TEMP_ATTRS(46)
        TEMP_ATTRS(47)
        TEMP_ATTRS(48)
        TEMP_ATTRS(49)
        TEMP_ATTRS(50)
        TEMP_ATTRS(51)
        TEMP_ATTRS(52)
        TEMP_ATTRS(53)
        TEMP_ATTRS(54)
        TEMP_ATTRS(55)
        TEMP_ATTRS(56)
        TEMP_ATTRS(57)
        TEMP_ATTRS(58)
        TEMP_ATTRS(59)
        TEMP_ATTRS(60)
        TEMP_ATTRS(61)
        TEMP_ATTRS(62)
        TEMP_ATTRS(63)
        TEMP_ATTRS(64)
        TEMP_ATTRS(65)
        NULL
};

static struct attribute *fan_attributes[] = {
        FAN_ATTRS(1)
        FAN_ATTRS(2)
        FAN_ATTRS(3)
        FAN_ATTRS(4)
        FAN_ATTRS(5)
        FAN_ATTRS(6)
        FAN_ATTRS(7)
        FAN_ATTRS(8)
        FAN_ATTRS(9)
        FAN_ATTRS(10)
        NULL
};

static struct attribute *cpld_attributes[] = {
        CPLD_ATTRS(1)
        CPLD_ATTRS(2)
        CPLD_ATTRS(3)
        NULL
};

static struct attribute *qsfp_attributes[] = {
        QSFP_ATTRS(1)
        QSFP_ATTRS(2)
        QSFP_ATTRS(3)
        QSFP_ATTRS(4)
        QSFP_ATTRS(5)
        QSFP_ATTRS(6)
        QSFP_ATTRS(7)
        QSFP_ATTRS(8)
        QSFP_ATTRS(9)
        QSFP_ATTRS(10)
        QSFP_ATTRS(11)
        QSFP_ATTRS(12)
        QSFP_ATTRS(13)
        QSFP_ATTRS(14)
        QSFP_ATTRS(15)
        QSFP_ATTRS(16)
        QSFP_ATTRS(17)
        QSFP_ATTRS(18)
        QSFP_ATTRS(19)
        QSFP_ATTRS(20)
        QSFP_ATTRS(21)
        QSFP_ATTRS(22)
        QSFP_ATTRS(23)
        QSFP_ATTRS(24)
        QSFP_ATTRS(25)
        QSFP_ATTRS(26)
        QSFP_ATTRS(27)
        QSFP_ATTRS(28)
        QSFP_ATTRS(29)
        QSFP_ATTRS(30)
        QSFP_ATTRS(31)
        QSFP_ATTRS(32)
        QSFP_ATTRS(33)
        QSFP_ATTRS(34)
        QSFP_ATTRS(35)
        QSFP_ATTRS(36)
        QSFP_ATTRS(37)
        QSFP_ATTRS(38)
        QSFP_ATTRS(39)
        QSFP_ATTRS(40)
        QSFP_ATTRS(41)
        QSFP_ATTRS(42)
        QSFP_ATTRS(43)
        QSFP_ATTRS(44)
        QSFP_ATTRS(45)
        QSFP_ATTRS(46)
        QSFP_ATTRS(47)
        QSFP_ATTRS(48)
        QSFP_ATTRS(49)
        QSFP_ATTRS(50)
        QSFP_ATTRS(51)
        QSFP_ATTRS(52)
        QSFP_ATTRS(53)
        QSFP_ATTRS(54)
        QSFP_ATTRS(55)
        QSFP_ATTRS(56)
        QSFP_ATTRS(57)
        QSFP_ATTRS(58)
        QSFP_ATTRS(59)
        QSFP_ATTRS(60)
        QSFP_ATTRS(61)
        QSFP_ATTRS(62)
        QSFP_ATTRS(63)
        QSFP_ATTRS(64)
        NULL
};

/* Device attributes */
#define TEMP_DEV_ATTRS(id)                          \
        &sensor_dev_attr_temp##id##_input.dev_attr, \
        &sensor_dev_attr_temp##id##_min.dev_attr,   \
        &sensor_dev_attr_temp##id##_max.dev_attr,   \
        &sensor_dev_attr_temp##id##_crit.dev_attr,

#define FAN_DEV_ATTRS(id)                          \
        &sensor_dev_attr_pwm##id.dev_attr,         \
        &sensor_dev_attr_fan##id##_input.dev_attr, \
        &sensor_dev_attr_fan##id##_min.dev_attr,   \
        &sensor_dev_attr_fan##id##_max.dev_attr,   \
        &sensor_dev_attr_fan##id##_enable.dev_attr,

#define QSFP_DEV_ATTRS(id)                               \
        &sensor_dev_attr_qsfp##id##_status.dev_attr,     \
        &sensor_dev_attr_qsfp##id##_event.dev_attr,      \
        &sensor_dev_attr_qsfp##id##_temp_input.dev_attr, \
        &sensor_dev_attr_qsfp##id##_temp_max.dev_attr,   \
        &sensor_dev_attr_qsfp##id##_temp_crit.dev_attr,

#define CPLD_DEV_ATTRS(id)                            \
        &sensor_dev_attr_cpld##id##_version.dev_attr,

struct device_attribute *asic_dev_temp_attributes[] = {
        TEMP_DEV_ATTRS(1)
        TEMP_DEV_ATTRS(2)
        TEMP_DEV_ATTRS(3)
        TEMP_DEV_ATTRS(4)
        TEMP_DEV_ATTRS(5)
        TEMP_DEV_ATTRS(6)
        TEMP_DEV_ATTRS(7)
        TEMP_DEV_ATTRS(8)
        TEMP_DEV_ATTRS(9)
        TEMP_DEV_ATTRS(10)
        TEMP_DEV_ATTRS(11)
        TEMP_DEV_ATTRS(12)
        TEMP_DEV_ATTRS(13)
        TEMP_DEV_ATTRS(14)
        TEMP_DEV_ATTRS(15)
        TEMP_DEV_ATTRS(16)
        TEMP_DEV_ATTRS(17)
        TEMP_DEV_ATTRS(18)
        TEMP_DEV_ATTRS(19)
        TEMP_DEV_ATTRS(20)
        TEMP_DEV_ATTRS(21)
        TEMP_DEV_ATTRS(22)
        TEMP_DEV_ATTRS(23)
        TEMP_DEV_ATTRS(24)
        TEMP_DEV_ATTRS(25)
        TEMP_DEV_ATTRS(26)
        TEMP_DEV_ATTRS(27)
        TEMP_DEV_ATTRS(28)
        TEMP_DEV_ATTRS(29)
        TEMP_DEV_ATTRS(30)
        TEMP_DEV_ATTRS(31)
        TEMP_DEV_ATTRS(32)
        TEMP_DEV_ATTRS(33)
        TEMP_DEV_ATTRS(34)
        TEMP_DEV_ATTRS(35)
        TEMP_DEV_ATTRS(36)
        TEMP_DEV_ATTRS(37)
        TEMP_DEV_ATTRS(38)
        TEMP_DEV_ATTRS(39)
        TEMP_DEV_ATTRS(40)
        TEMP_DEV_ATTRS(41)
        TEMP_DEV_ATTRS(42)
        TEMP_DEV_ATTRS(43)
        TEMP_DEV_ATTRS(44)
        TEMP_DEV_ATTRS(45)
        TEMP_DEV_ATTRS(46)
        TEMP_DEV_ATTRS(47)
        TEMP_DEV_ATTRS(48)
        TEMP_DEV_ATTRS(49)
        TEMP_DEV_ATTRS(50)
        TEMP_DEV_ATTRS(51)
        TEMP_DEV_ATTRS(52)
        TEMP_DEV_ATTRS(53)
        TEMP_DEV_ATTRS(54)
        TEMP_DEV_ATTRS(55)
        TEMP_DEV_ATTRS(56)
        TEMP_DEV_ATTRS(57)
        TEMP_DEV_ATTRS(58)
        TEMP_DEV_ATTRS(59)
        TEMP_DEV_ATTRS(60)
        TEMP_DEV_ATTRS(61)
        TEMP_DEV_ATTRS(62)
        TEMP_DEV_ATTRS(63)
        TEMP_DEV_ATTRS(64)
        TEMP_DEV_ATTRS(65)
        NULL
};

struct device_attribute *asic_dev_fan_attributes[] = {
        FAN_DEV_ATTRS(1)
        FAN_DEV_ATTRS(2)
        FAN_DEV_ATTRS(3)
        FAN_DEV_ATTRS(4)
        FAN_DEV_ATTRS(5)
        FAN_DEV_ATTRS(6)
        FAN_DEV_ATTRS(7)
        FAN_DEV_ATTRS(8)
        FAN_DEV_ATTRS(9)
        FAN_DEV_ATTRS(10)
        NULL
};

struct device_attribute *asic_dev_cpld_attributes[] = {
        CPLD_DEV_ATTRS(1)
        CPLD_DEV_ATTRS(2)
        CPLD_DEV_ATTRS(3)
        NULL
};

struct device_attribute *asic_dev_qsfp_attributes[] = {
        QSFP_DEV_ATTRS(1)
        QSFP_DEV_ATTRS(2)
        QSFP_DEV_ATTRS(3)
        QSFP_DEV_ATTRS(4)
        QSFP_DEV_ATTRS(5)
        QSFP_DEV_ATTRS(6)
        QSFP_DEV_ATTRS(7)
        QSFP_DEV_ATTRS(8)
        QSFP_DEV_ATTRS(9)
        QSFP_DEV_ATTRS(10)
        QSFP_DEV_ATTRS(11)
        QSFP_DEV_ATTRS(12)
        QSFP_DEV_ATTRS(13)
        QSFP_DEV_ATTRS(14)
        QSFP_DEV_ATTRS(15)
        QSFP_DEV_ATTRS(16)
        QSFP_DEV_ATTRS(17)
        QSFP_DEV_ATTRS(18)
        QSFP_DEV_ATTRS(19)
        QSFP_DEV_ATTRS(20)
        QSFP_DEV_ATTRS(21)
        QSFP_DEV_ATTRS(22)
        QSFP_DEV_ATTRS(23)
        QSFP_DEV_ATTRS(24)
        QSFP_DEV_ATTRS(25)
        QSFP_DEV_ATTRS(26)
        QSFP_DEV_ATTRS(27)
        QSFP_DEV_ATTRS(28)
        QSFP_DEV_ATTRS(29)
        QSFP_DEV_ATTRS(30)
        QSFP_DEV_ATTRS(31)
        QSFP_DEV_ATTRS(32)
        QSFP_DEV_ATTRS(33)
        QSFP_DEV_ATTRS(34)
        QSFP_DEV_ATTRS(35)
        QSFP_DEV_ATTRS(36)
        QSFP_DEV_ATTRS(37)
        QSFP_DEV_ATTRS(38)
        QSFP_DEV_ATTRS(39)
        QSFP_DEV_ATTRS(40)
        QSFP_DEV_ATTRS(41)
        QSFP_DEV_ATTRS(42)
        QSFP_DEV_ATTRS(43)
        QSFP_DEV_ATTRS(44)
        QSFP_DEV_ATTRS(45)
        QSFP_DEV_ATTRS(46)
        QSFP_DEV_ATTRS(47)
        QSFP_DEV_ATTRS(48)
        QSFP_DEV_ATTRS(49)
        QSFP_DEV_ATTRS(50)
        QSFP_DEV_ATTRS(51)
        QSFP_DEV_ATTRS(52)
        QSFP_DEV_ATTRS(53)
        QSFP_DEV_ATTRS(54)
        QSFP_DEV_ATTRS(55)
        QSFP_DEV_ATTRS(56)
        QSFP_DEV_ATTRS(57)
        QSFP_DEV_ATTRS(58)
        QSFP_DEV_ATTRS(59)
        QSFP_DEV_ATTRS(60)
        QSFP_DEV_ATTRS(61)
        QSFP_DEV_ATTRS(62)
        QSFP_DEV_ATTRS(63)
        QSFP_DEV_ATTRS(64)
        NULL
};

#define DEVICE_ATTR_FAN_CREATE(hwmon, id) {                                               \
	int i = id, j;                                                                    \
	err = device_create_file(hwmon, asic_dev_fan_attributes[i++]);                    \
	err = (err == 0) ? device_create_file(hwmon, asic_dev_fan_attributes[i++]) : err; \
	err = (err == 0) ? device_create_file(hwmon, asic_dev_fan_attributes[i++]) : err; \
	err = (err == 0) ? device_create_file(hwmon, asic_dev_fan_attributes[i++]) : err; \
	err = (err == 0) ? device_create_file(hwmon, asic_dev_fan_attributes[i++]) : err; \
	if (err) {                                                                        \
		for (j = i - 1; j >= id; j--)                                             \
			device_remove_file(hwmon, asic_dev_fan_attributes[j]);            \
		goto fail_create_file; }}

#define DEVICE_ATTR_FAN_REMOVE(hwmon, id) {                      \
	int i = id;                                              \
        device_remove_file(hwmon, asic_dev_fan_attributes[i++]); \
        device_remove_file(hwmon, asic_dev_fan_attributes[i++]); \
        device_remove_file(hwmon, asic_dev_fan_attributes[i++]); \
        device_remove_file(hwmon, asic_dev_fan_attributes[i++]); \
        device_remove_file(hwmon, asic_dev_fan_attributes[i]); }

#define DEVICE_ATTR_QSFP_CREATE(asicdata, client, id) {                                                  \
	int i = id, j;                                                                                   \
	err = device_create_file(asicdata->hwmon_dev, asic_dev_qsfp_attributes[i++]);                    \
	err = (err == 0) ? device_create_file(asicdata->hwmon_dev, asic_dev_qsfp_attributes[i++]) : err; \
	err = (err == 0) ? device_create_file(asicdata->hwmon_dev, asic_dev_qsfp_attributes[i++]) : err; \
	err = (err == 0) ? device_create_file(asicdata->hwmon_dev, asic_dev_qsfp_attributes[i++]) : err; \
	err = (err == 0) ? device_create_file(asicdata->hwmon_dev, asic_dev_qsfp_attributes[i]) : err;   \
	if (err) {                                                                                       \
		for (j = i - 1; j >= id; j--)                                                            \
			device_remove_file(asicdata->hwmon_dev, asic_dev_qsfp_attributes[j]);            \
		goto fail_create_file; }}

#define DEVICE_ATTR_QSFP_REMOVE(asicdata, client, id) {                         \
	int i = id;                                                             \
        device_remove_file(asicdata->hwmon_dev, asic_dev_qsfp_attributes[i++]); \
        device_remove_file(asicdata->hwmon_dev, asic_dev_qsfp_attributes[i++]); \
        device_remove_file(asicdata->hwmon_dev, asic_dev_qsfp_attributes[i++]); \
        device_remove_file(asicdata->hwmon_dev, asic_dev_qsfp_attributes[i++]); \
        device_remove_file(asicdata->hwmon_dev, asic_dev_qsfp_attributes[i]); }

#define DEVICE_ATTR_TEMP_CREATE(hwmon, id) {                                               \
	int i = id, j;                                                                     \
	err = device_create_file(hwmon, asic_dev_temp_attributes[i++]);                    \
	err = (err == 0) ? device_create_file(hwmon, asic_dev_temp_attributes[i++]) : err; \
	err = (err == 0) ? device_create_file(hwmon, asic_dev_temp_attributes[i++]) : err; \
	err = (err == 0) ? device_create_file(hwmon, asic_dev_temp_attributes[i]) : err;   \
	if (err) {                                                                         \
		for (j = i - 1; j >= id; j--)                                              \
			device_remove_file(hwmon, asic_dev_temp_attributes[j]);            \
		goto fail_create_file; }}

#define DEVICE_ATTR_TEMP_REMOVE(hwmon, id) {                      \
	int i = id;                                               \
        device_remove_file(hwmon, asic_dev_temp_attributes[i++]); \
        device_remove_file(hwmon, asic_dev_temp_attributes[i++]); \
        device_remove_file(hwmon, asic_dev_temp_attributes[i++]); \
        device_remove_file(hwmon, asic_dev_temp_attributes[i]); }

#define DEVICE_ATTR_CPLD_CREATE(hwmon, id)                             \
	err = device_create_file(hwmon, asic_dev_cpld_attributes[id]); \
	if (err)                                                       \
		goto fail_create_file;

#define DEVICE_ATTR_CPLD_REMOVE(hwmon, id)                       \
        device_remove_file(hwmon, asic_dev_cpld_attributes[id]);

static int fan_config(struct device *dev, struct asic_data *asicdata)
{
	int err = 0, id, i, j = 0, k = 0;
        u8 tacho_num;
        u8 tacho_map[FAN_NUM];
        u8 pwm_id = 0;

        if (tacho_flat)
                tacho_num = 1;
        else
                tacho_num = num_tachos;

        /* Get mapping and available numbers for tachometers and pwm. */
        err = fan_get_config(&asicdata->switchdevif, &asicdata->fan_config);

	for (i = TACH_PWM_MAP - 1; i >= 0; i--) {
		if (asicdata->fan_config.tacho_active & BIT(i)) {
			asicdata->fan_config.num_fan++;
			tacho_map[j++] = i;
		}
		if (asicdata->fan_config.pwm_active & BIT(i)) {
			pwm_id = i;
		}
	}

	asicdata->fan_config.fan = devm_kzalloc(dev, asicdata->fan_config.num_fan *
                                                        sizeof(*asicdata->fan_config.fan), GFP_KERNEL);
	if (!asicdata->fan_config.fan) {
		return -ENOMEM;
	}

        asicdata->fan_config.num_cooling_levels = ((MAX_PWM_DUTY_CYCLE - pwm_duty_cycle) % PWM_DUTY_CYCLE_STEP) ?
                                                        (MAX_PWM_DUTY_CYCLE - pwm_duty_cycle) / PWM_DUTY_CYCLE_STEP + 2 :
                                                        (MAX_PWM_DUTY_CYCLE - pwm_duty_cycle) / PWM_DUTY_CYCLE_STEP + 1;
        asicdata->fan_config.cooling_levels = devm_kzalloc(dev, asicdata->fan_config.num_cooling_levels *
                                                                sizeof(*asicdata->fan_config.cooling_levels), GFP_KERNEL);
	if (!asicdata->fan_config.cooling_levels) {
		kfree(asicdata->fan_config.fan);
		return -ENOMEM;
	}

	for (id = 0; id < asicdata->fan_config.num_cooling_levels; id++) {
		asicdata->fan_config.cooling_levels[id] = pwm_duty_cycle + id * PWM_DUTY_CYCLE_STEP;
	}
	if (asicdata->fan_config.cooling_levels[id - 1] > MAX_PWM_DUTY_CYCLE) {
		asicdata->fan_config.cooling_levels[id - 1] = MAX_PWM_DUTY_CYCLE;
	}
        asicdata->fan_config.cooling_cur_level = 0;

        for (id = 0; id < asicdata->fan_config.num_fan; id++) {
		sprintf(asicdata->fan_config.fan[id].entry.name, "%s%d", "fan", id + 1);
                asicdata->fan_config.fan[id].entry.index = id + 1;
                asicdata->fan_config.fan[id].pwm_id = pwm_id;
                asicdata->fan_config.fan[id].pwm_duty_cycle = pwm_duty_cycle;
                asicdata->fan_config.fan[id].num_tachos = tacho_num;
                for (j = 0; j < tacho_num; j++) {
                        asicdata->fan_config.fan[id].tacho_id[j] = tacho_map[k++];
                        asicdata->fan_config.fan[id].speed[j] = speed_min;
                        asicdata->fan_config.fan[id].speed_min[j] = speed_min;
                        asicdata->fan_config.fan[id].speed_max[j] = speed_max;
                        asicdata->fan_config.fan[id].enable[j] = 0;
                }
        }

	return err;
}

static int qsfp_config(struct device *dev, struct asic_data *asicdata, struct i2c_client *client)
{
	int id, err = 0;

	asicdata->qsfp_config.module = devm_kzalloc(dev, asicdata->qsfp_config.num_modules *
                                                        sizeof(*asicdata->qsfp_config.module), GFP_KERNEL);
	if (!asicdata->qsfp_config.module) {
		return -ENOMEM;
	}
	asicdata->qsfp_config.eeprom = devm_kzalloc(dev, asicdata->qsfp_config.num_modules *
                                                        sizeof(*asicdata->qsfp_config.eeprom), GFP_KERNEL);
	if (!asicdata->qsfp_config.eeprom) {
		kfree(asicdata->qsfp_config.module);
		return -ENOMEM;
	}
	asicdata->qsfp_config.eeprom_attr_list = devm_kzalloc(dev, (asicdata->qsfp_config.num_modules + 1) *
								sizeof(asicdata->qsfp_config.eeprom), GFP_KERNEL);
	if (!asicdata->qsfp_config.eeprom_attr_list) {
		kfree(asicdata->qsfp_config.eeprom);
		kfree(asicdata->qsfp_config.module);
		return -ENOMEM;
	}

        for (id = 0; id < asicdata->qsfp_config.num_modules; id++) {
		sprintf(asicdata->qsfp_config.module[id].entry.name, "%s%d", "qsfp", id + 1);
		asicdata->qsfp_config.module[id].entry.index = id;
                asicdata->qsfp_config.module[id].module_index = id;
                asicdata->qsfp_config.module[id].lock = 0;
                asicdata->qsfp_config.module[id].status = 0;
        }

	return err;
}

static int temp_config(struct device *dev, struct asic_data *asicdata)
{
	int err = 0, id;

        /* Get number of active sensors. */
        err = temp_get_config(&asicdata->switchdevif, &asicdata->temp_config);
        asicdata->temp_config.num_sensors = asicdata->temp_config.sensor_active;

	asicdata->temp_config.sensor = devm_kzalloc(dev, asicdata->temp_config.num_sensors *
						sizeof(*asicdata->temp_config.sensor), GFP_KERNEL);
	if (!asicdata->temp_config.sensor) {
		return -ENOMEM;
	}

        for (id = 0; id < asicdata->temp_config.num_sensors; id++) {
		asicdata->temp_config.sensor[id].entry.index = id;
		sprintf(asicdata->temp_config.sensor[id].entry.name, "%s%d", "temp", id + 1);
		asicdata->temp_config.sensor[id].sensor_index = id,
		asicdata->temp_config.sensor[id].temperature = 0,
		asicdata->temp_config.sensor[id].mte = mte;
		asicdata->temp_config.sensor[id].mtr = mtr;
		asicdata->temp_config.sensor[id].max_temperature = 0;
		asicdata->temp_config.sensor[id].tee = tee;
		asicdata->temp_config.sensor[id].temperature_threshold = temp_threshold;
        }

	return err;
}

static int cpld_config(struct device *dev, struct asic_data *asicdata)
{
	int err = 0, id;

        asicdata->cpld_config.num_cpld = num_cpld;
	asicdata->cpld_config.cpld = devm_kzalloc(dev, asicdata->cpld_config.num_cpld *
						sizeof(*asicdata->cpld_config.cpld), GFP_KERNEL);
	if (!asicdata->cpld_config.cpld) {
		return -ENOMEM;
	}

        for (id = 0; id < num_cpld; id++) {
		asicdata->cpld_config.cpld[id].entry.index = id;
		sprintf(asicdata->cpld_config.cpld[id].entry.name, "%s%d", "cpld", id + 1);
                asicdata->cpld_config.cpld[id].index = id;
        }
	return err;
}

static int _mlxsw_port_led_brightness(struct led_classdev *led,
				      enum led_brightness value)
{
	struct port_led_pdata *pled = cdev_to_priv(led);
	struct switchdev_if *devif = pled->devif;
	struct ku_mlcr_reg mlcr_reg;
	u8 method = REG_WRITE;
	struct ku_access_mlcr_reg reg_data;
	int err = 0;

	if (!devif->REG_MLCR || !devif->DEV_CONTEXT)
		return err;

	memset(&reg_data, 0, sizeof(struct ku_access_mlcr_reg));
	SET_REG_TEMPLATE(reg_data, MLCR_REG_ID, method, devif);
	mlcr_reg.led_type = pled->led_type;
	if (pled->index)
		reg_data.mlcr_reg.local_port =
			mlxsw_local_port_mapping[pled->index - 1];
	else
		reg_data.mlcr_reg.local_port = 0;

	if (value)
		mlcr_reg.beacon_duration = LED_INFINITY_COLOR;
	else
		mlcr_reg.beacon_duration = LED_OFF_COLOR;

        REG_ACCESS(devif, MLCR, reg_data, err);

	return err;
}

static void mlxsw_port_led_brightness(struct led_classdev *led,
				      enum led_brightness value)
{
	_mlxsw_port_led_brightness(led, value);
}

static int mlxsw_port_led_blink_set(struct led_classdev *led,
				    unsigned long *delay_on,
				    unsigned long *delay_off)
{
	return -EINVAL;
}


static struct platform_driver asic_led_driver = {
	.driver = {
		.name	= "asic-port-led",
	},
};

static void port_led_remove(struct asic_data *asicdata)
{
	int i;

	for (i = 0; i < asicdata->led_config.num_led_instances; i++)
		led_classdev_unregister(&asicdata->led_config.led[i].cdev);
	platform_driver_unregister(&asic_led_driver);
	platform_device_del(asicdata->led_config.pdev);
	platform_device_put(asicdata->led_config.pdev);
}


static int port_led_config(struct asic_data *asicdata)
{
	struct platform_device *pdev;
	int name_sz;
	char *name;
	char tmp_name[20];
	u8 led_type;
	int i, j = 0;
	u8 width = 0;
	int err = 0;

	asicdata->led_config.num_led_instances = 1;
	for (i = 1; i <= QSFP_MODULE_NUM; i++) {
		err = pmlp_get(&asicdata->switchdevif, i, &width);
		if (err)
			goto exit;

		switch (width) {
		case 1:
			mlxsw_local_port_mapping[j++] = i;
			mlxsw_local_port_mapping[j++] = i + 1;
			mlxsw_local_port_mapping[j++] = i + 2;
			mlxsw_local_port_mapping[j++] = i + 3;
			asicdata->led_config.num_led_instances += 4;
			break;
		case 2:
			mlxsw_local_port_mapping[j++] = i;
			mlxsw_local_port_mapping[j++] = i + 1;
			asicdata->led_config.num_led_instances += 2;
			break;
		case 4:
			mlxsw_local_port_mapping[j++] = i;
			asicdata->led_config.num_led_instances++;
			break;
		default:
			break;
		}
	}

	pdev = platform_device_alloc(asic_led_driver.driver.name, 0);
	if (!pdev) {
		err = -ENOMEM;
		pr_err("Device allocation failed\n");
		goto exit;
	}
	err = platform_device_add(pdev);
	if (err)
		goto exit_device_put;
	err = platform_driver_register(&asic_led_driver);
	if (err)
		goto exit_device_del;

	asicdata->led_config.led = devm_kzalloc(&pdev->dev,
					sizeof(struct port_led_pdata) *
					asicdata->led_config.num_led_instances,
					GFP_KERNEL);
	if (!asicdata->led_config.led)
		return -ENOMEM;

	platform_set_drvdata(pdev, asicdata->led_config.led);
	asicdata->led_config.pdev = pdev;

	for (i = 0; i < asicdata->led_config.num_led_instances; i++) {
		memset(tmp_name, 0, 20);
		if (i) {
			sprintf(tmp_name, "mlxsw:port%d:orange", i);
			name_sz = strlen(tmp_name);
			led_type = LED_TYPE_PORT;
		} else {
			sprintf(tmp_name, "mlxsw:uid:blue");
			name_sz = strlen(tmp_name);
			led_type = LED_TYPE_UID;
		}

		name = devm_kzalloc(&pdev->dev, name_sz, GFP_KERNEL);
		memcpy(name, tmp_name, name_sz);
		asicdata->led_config.led[i].cdev.name = name;
		asicdata->led_config.led[i].cdev.brightness = 1;
		asicdata->led_config.led[i].cdev.max_brightness = 1;
		asicdata->led_config.led[i].cdev.brightness_set =
						mlxsw_port_led_brightness;
		asicdata->led_config.led[i].cdev.blink_set =
						mlxsw_port_led_blink_set;
		asicdata->led_config.led[i].cdev.flags =
						LED_CORE_SUSPENDRESUME;
		asicdata->led_config.led[i].devif = &asicdata->switchdevif;
		asicdata->led_config.led[i].index = i;
		asicdata->led_config.led[i].led_type = led_type;

		err = /*devm_*/led_classdev_register(&pdev->dev,
					&asicdata->led_config.led[i].cdev);
		if (err)
			goto fail_init;
	}

	return err;

fail_init:
	platform_driver_unregister(&asic_led_driver);
exit_device_del:
	platform_device_del(pdev);
exit_device_put:
	platform_device_put(pdev);
exit:
	return err;
}

static int cz_get_max_state(struct thermal_cooling_device *tcdev,
				  unsigned long *state)
{
        struct asic_data *asicdata = (struct asic_data *)tcdev->devdata;

	*state = asicdata->fan_config.num_cooling_levels;

	return 0;
}

static int cz_get_cur_state(struct thermal_cooling_device *tcdev,
				  unsigned long *state)
{
        struct asic_data *asicdata = (struct asic_data *)tcdev->devdata;

	struct fan_config *fan;
	int err;

	fan = &asicdata->fan_config.fan[0];
	err = fan_get_power(&asicdata->switchdevif, fan, 1);
	if (err)
		return err;

	if (fan->pwm_duty_cycle ==
		asicdata->fan_config.cooling_levels[asicdata->fan_config.cooling_cur_level]) {
		*state = asicdata->fan_config.cooling_cur_level;
	}
	else {
		*state = asicdata->fan_config.cooling_cur_level =
                                                        ((fan->pwm_duty_cycle - pwm_duty_cycle) % PWM_DUTY_CYCLE_STEP) ?
                                                        (fan->pwm_duty_cycle - pwm_duty_cycle) / PWM_DUTY_CYCLE_STEP + 1 :
                                                        (fan->pwm_duty_cycle - pwm_duty_cycle) / PWM_DUTY_CYCLE_STEP;
	}

	return 0;
}

static int cz_set_cur_state(struct thermal_cooling_device *tcdev,
				  unsigned long state)
{
        struct asic_data *asicdata = (struct asic_data *)tcdev->devdata;
	struct fan_config *fan;
	int err;

	asicdata->fan_config.cooling_cur_level = (state >= asicdata->fan_config.num_cooling_levels - 1) ?
						asicdata->fan_config.num_cooling_levels - 1 : state;

	fan = &asicdata->fan_config.fan[0];
	fan->pwm_duty_cycle = asicdata->fan_config.cooling_levels[asicdata->fan_config.cooling_cur_level];
	err = fan_set_power(&asicdata->switchdevif, fan);
	if (err)
		return err;

	return 0;
}

static int tz_get_temp(struct thermal_zone_device *tzdev, /* int from 4.3 */ unsigned long *temperature)
{
        struct asic_data *asicdata = (struct asic_data *)tzdev->devdata;
	struct temp_config *temp = NULL;
	int err;

	temp = &asicdata->temp_config.sensor[0];
        err = temp_get(&asicdata->switchdevif, temp, 0, 1);
	if (err)
		return err;

        *temperature = temp->temperature;

        return 0;
}

static int tz_get_trip_type(struct thermal_zone_device *tzdev,
				int trip, enum thermal_trip_type *type)
{
        struct asic_data *asicdata = (struct asic_data *)tzdev->devdata;

        if (trip > asicdata->fan_config.num_cooling_levels) {
		dev_err(asicdata->hwmon_dev, "Invalid trip point %d\n", trip);
		return -EINVAL;
	}

	*type = THERMAL_TRIP_PASSIVE;

	return 0;
}

static int tz_get_trip_temp(struct thermal_zone_device *tzdev,
				int trip, unsigned long *temperature /* int from 4.3 */)
{
        struct asic_data *asicdata = (struct asic_data *)tzdev->devdata;

        if (trip > asicdata->fan_config.num_cooling_levels) {
		dev_err(asicdata->hwmon_dev, "Invalid trip point %d\n", trip);
		return -EINVAL;
	}

	*temperature = asicdata->temp_config.sensor[0].temperature_threshold;

	return 0;
}

static const struct thermal_cooling_device_ops asic_cool_ops = {
        .get_max_state = cz_get_max_state,
        .get_cur_state = cz_get_cur_state,
        .set_cur_state = cz_set_cur_state,
};

static struct thermal_zone_device_ops asic_thermal_ops = {
	.get_temp = tz_get_temp,
	.get_trip_type = tz_get_trip_type,
	.get_trip_temp = tz_get_trip_temp,
};

static const unsigned short normal_i2c[] = { 0x48, I2C_CLIENT_END };
static int asic_probe(struct i2c_client *client, const struct i2c_device_id *devid)
{
        struct asic_data *asicdata;
        struct device *dev = &client->dev;
	u16 device_id = 0;
        int err, i;

	asicdata = devm_kzalloc(dev, sizeof(struct asic_data), GFP_KERNEL);
	if (!asicdata) {
		err = -ENOMEM;
		goto exit_no_memory;
	}
	i2c_set_clientdata(client, asicdata);

	INIT_LIST_HEAD(&asicdata->list);

        /* Register with asic registers access interface */
	memset(&asicdata->switchdevif, 0, sizeof(struct switchdev_if));
	asicdata->switchdevif.DEV_CONTEXT = __symbol_get("sx_get_dev_context");
        if (IS_ERR(asicdata->switchdevif.DEV_CONTEXT)) {
                err = PTR_ERR(asicdata->switchdevif.DEV_CONTEXT);
                goto exit_remove;
        }
	asicdata->switchdevif.REG_MFSC = __symbol_get("sx_ACCESS_REG_MFSC");
	asicdata->switchdevif.REG_MFSM = __symbol_get("sx_ACCESS_REG_MFSM");
	asicdata->switchdevif.REG_MTMP = __symbol_get("sx_ACCESS_REG_MTMP");
	asicdata->switchdevif.REG_MTCAP = __symbol_get("sx_ACCESS_REG_MTCAP");
	asicdata->switchdevif.REG_MCIA = __symbol_get("sx_ACCESS_REG_MCIA");
	asicdata->switchdevif.REG_PMPC = __symbol_get("sx_ACCESS_REG_PMPC");
	asicdata->switchdevif.REG_MSCI = __symbol_get("sx_ACCESS_REG_MSCI");
	asicdata->switchdevif.REG_MJTAG = __symbol_get("sx_ACCESS_REG_MJTAG");
	asicdata->switchdevif.REG_PMAOS = __symbol_get("sx_ACCESS_REG_PMAOS");
	asicdata->switchdevif.REG_MFCR = __symbol_get("sx_ACCESS_REG_MFCR");
	asicdata->switchdevif.REG_MGIR = __symbol_get("sx_ACCESS_REG_MGIR");
	asicdata->switchdevif.REG_MLCR = __symbol_get("sx_ACCESS_REG_MLCR");
	asicdata->switchdevif.REG_PMLP = __symbol_get("sx_ACCESS_REG_PMLP");

	asicdata->switchdevif.dev_id = asic_dev_id;
	mutex_init(&asicdata->switchdevif.access_lock);

	kref_init(&asicdata->kref);

        /* Set asic id and register sysfs hooks */
	asicdata->port_cap = devid->driver_data;
	switch (devid->driver_data) {
	case asic_drv_32_ports:
	default:
		asicdata->asic_id = asic_drv_32_ports;
		asicdata->qsfp_config.num_modules = 32;
		break;
	case asic_drv_64_ports:
		asicdata->asic_id = asic_drv_64_ports;
		asicdata->qsfp_config.num_modules = 64;
		break;
	case asic_drv_54_ports:
		asicdata->asic_id = asic_drv_54_ports;
		asicdata->qsfp_config.num_modules = 54;
		break;
	case asic_drv_36_ports:
		asicdata->asic_id = asic_drv_36_ports;
		asicdata->qsfp_config.num_modules = 36;
		break;
	case asic_drv_16_ports:
		asicdata->asic_id = asic_drv_16_ports;
		asicdata->qsfp_config.num_modules = 16;
		break;
	case asic_drv_56_ports:
		asicdata->asic_id = asic_drv_56_ports;
		asicdata->qsfp_config.num_modules = 56;
		break;
	}

        /* Configure sysfs infrastructure */
        err = fan_config(dev, asicdata);
        err = (err == 0) ? temp_config(dev, asicdata) : err;
        err = (err == 0) ? qsfp_config(dev, asicdata, client) : err;
        err = (err == 0) ? cpld_config(dev, asicdata) : err;
        if (err)
                goto exit_no_memory;

        asicdata->group[0].attrs = devm_kzalloc(dev, ((asicdata->temp_config.num_sensors + 1) * TEMP_ATTR_NUM) *
                                                sizeof(struct attribute *), GFP_KERNEL);
        if (!(asicdata->group[0].attrs)) {
                err = -ENOMEM;
                goto exit_no_memory;
        }
        asicdata->group[1].attrs = devm_kzalloc(dev, ((asicdata->fan_config.num_fan + 1) * FAN_ATTR_NUM) *
                                                sizeof(struct attribute *), GFP_KERNEL);
        if (!(asicdata->group[1].attrs)) {
                err = -ENOMEM;
                goto exit_no_memory;
        }
        asicdata->group[2].attrs = devm_kzalloc(dev, ((asicdata->cpld_config.num_cpld + 1) *  CPLD_ATTR_NUM) *
                                                sizeof(struct attribute *), GFP_KERNEL);
        if (!(asicdata->group[2].attrs)) {
                err = -ENOMEM;
                goto exit_no_memory;
        }
        asicdata->group[3].attrs = devm_kzalloc(dev, ((asicdata->qsfp_config.num_modules + 1) * QSFP_ATTR_NUM) *
                                                sizeof(struct attribute *), GFP_KERNEL);
        if (!(asicdata->group[3].attrs)) {
                err = -ENOMEM;
                goto exit_no_memory;
        }

        memcpy(asicdata->group[0].attrs, temp_attributes,
                (asicdata->temp_config.num_sensors * TEMP_ATTR_NUM) * sizeof(struct attribute *));
        memcpy(asicdata->group[1].attrs, fan_attributes,
                (asicdata->fan_config.num_fan * FAN_ATTR_NUM) * sizeof(struct attribute *));
        memcpy(asicdata->group[2].attrs, cpld_attributes,
                (asicdata->cpld_config.num_cpld *  CPLD_ATTR_NUM) * sizeof(struct attribute *));
        memcpy(asicdata->group[3].attrs, qsfp_attributes,
                (asicdata->qsfp_config.num_modules * QSFP_ATTR_NUM) * sizeof(struct attribute *));

	for (i = 0; i < asicdata->qsfp_config.num_modules; i++) {
		sysfs_bin_attr_init(&asicdata->qsfp_config.eeprom[i]);
		asicdata->qsfp_config.eeprom[i].attr.name = qsfp_eeprom_names[i];/* from kernel 3.18:
										devm_kasprintf(GFP_KERNEL, "qsfp%d_eeprom", i + 1)*/
		asicdata->qsfp_config.eeprom[i].attr.mode = S_IRUGO;
		asicdata->qsfp_config.eeprom[i].read = qsfp_eeprom_bin_read;
		asicdata->qsfp_config.eeprom[i].size = QSFP_PAGE_NUM * QSFP_PAGE_SIZE;
		asicdata->qsfp_config.eeprom[i].private = (void *)&asicdata->qsfp_config.module[i];
                asicdata->qsfp_config.eeprom_attr_list[i] = &asicdata->qsfp_config.eeprom[i];
	}
	asicdata->group[3].bin_attrs = asicdata->qsfp_config.eeprom_attr_list;
	for (i = 0; i < ASIC_GROUP_NUM; i++)
		asicdata->groups[i] = &asicdata->group[i];
	asicdata->groups[ASIC_GROUP_NUM] = NULL;

        asicdata->hwmon_dev = devm_hwmon_device_register_with_groups(&client->dev,
                                                                        "spectrum",
                                                                        asicdata,
                                                                        asicdata->groups);
        if (IS_ERR(asicdata->hwmon_dev)) {
                err = PTR_ERR(asicdata->hwmon_dev);
                goto exit_no_memory;
        }

        err = mgir_get(&asicdata->switchdevif, &device_id);
        if (err)
                goto exit_no_memory;
        switch(device_id) {
        case 0xcb84:
                asicdata->kind = spectrum;
                asicdata->name = "spectrum";
                break;
        case 0xC738:
                asicdata->kind = switchx2;
                asicdata->name = "switchx2";
                break;
        default:
                asicdata->kind = any_chip;
                break;
        }

	if (auto_thermal_control) {
		asicdata->tcdev = thermal_cooling_device_register("switchdev-cooling", asicdata,
									&asic_cool_ops);
		if (PTR_ERR_OR_ZERO(asicdata->tcdev)) {
			err = PTR_ERR(asicdata->tcdev);
			goto exit_no_memory;
		}
		asicdata->tzdev = thermal_zone_device_register("switchdev-thermal",
								asicdata->fan_config.num_cooling_levels, 0,
								asicdata, &asic_thermal_ops, NULL,
								TEMP_PASSIVE_INTERVAL, TEMP_POLLING_INTERVAL);
		if (PTR_ERR_OR_ZERO(asicdata->tzdev)) {
			err = PTR_ERR(asicdata->tzdev);
			goto exit_remove_cooling;
		}
		err = thermal_zone_bind_cooling_device(asicdata->tzdev, 0, asicdata->tcdev,
							THERMAL_NO_LIMIT, THERMAL_NO_LIMIT
							/* from 4.2. ,THERMAL_WEIGHT_DEFAULT*/);
        	if (err)
			goto exit_remove_thermal;
	}

	if (port_led_control) {
		err = port_led_config(asicdata);
		if (err)
			goto exit_remove_thermal_bind;
	}

	return 0;

exit_remove_thermal_bind:
	if (auto_thermal_control)
		thermal_zone_unbind_cooling_device(asicdata->tzdev, 0, asicdata->tcdev);
exit_remove_thermal:
	if (auto_thermal_control)
		thermal_zone_device_unregister(asicdata->tzdev);
exit_remove_cooling:
	if (auto_thermal_control)
		thermal_cooling_device_unregister(asicdata->tcdev);
exit_no_memory:
	if (asicdata->switchdevif.REG_MFSC) __symbol_put("sx_ACCESS_REG_MFSC");
	if (asicdata->switchdevif.REG_MFSM) __symbol_put("sx_ACCESS_REG_MFSM");
	if (asicdata->switchdevif.REG_MTMP) __symbol_put("sx_ACCESS_REG_MTMP");
	if (asicdata->switchdevif.REG_MTCAP) __symbol_put("sx_ACCESS_REG_MTCAP");
	if (asicdata->switchdevif.REG_MCIA) __symbol_put("sx_ACCESS_REG_MCIA");
	if (asicdata->switchdevif.REG_PMPC) __symbol_put("sx_ACCESS_REG_PMPC");
	if (asicdata->switchdevif.REG_MSCI) __symbol_put("sx_ACCESS_REG_MSCI");
	if (asicdata->switchdevif.REG_MJTAG) __symbol_put("sx_ACCESS_REG_MJTAG");
	if (asicdata->switchdevif.REG_PMAOS) __symbol_put("sx_ACCESS_REG_PMAOS");
	if (asicdata->switchdevif.REG_MFCR) __symbol_put("sx_ACCESS_REG_MFCR");
	if (asicdata->switchdevif.REG_MGIR) __symbol_put("sx_ACCESS_REG_MGIR");
	if (asicdata->switchdevif.REG_MLCR) __symbol_put("sx_ACCESS_REG_MLCR");
	if (asicdata->switchdevif.REG_PMLP) __symbol_put("sx_ACCESS_REG_PMLP");
	if (asicdata->switchdevif.DEV_CONTEXT) __symbol_put("sx_get_dev_context");
	mutex_destroy(&asicdata->switchdevif.access_lock);
exit_remove:
	return err;
}

static int asic_remove(struct i2c_client *client)
{
        struct asic_data *asicdata = i2c_get_clientdata(client);

	if (port_led_control)
		port_led_remove(asicdata);

	if (auto_thermal_control) {
		thermal_zone_unbind_cooling_device(asicdata->tzdev, 0, asicdata->tcdev);
		thermal_zone_device_unregister(asicdata->tzdev);
		thermal_cooling_device_unregister(asicdata->tcdev);
	}
	if (asicdata->switchdevif.REG_MFSC) __symbol_put("sx_ACCESS_REG_MFSC");
	if (asicdata->switchdevif.REG_MFSM) __symbol_put("sx_ACCESS_REG_MFSM");
	if (asicdata->switchdevif.REG_MTMP) __symbol_put("sx_ACCESS_REG_MTMP");
	if (asicdata->switchdevif.REG_MTCAP) __symbol_put("sx_ACCESS_REG_MTCAP");
	if (asicdata->switchdevif.REG_MCIA) __symbol_put("sx_ACCESS_REG_MCIA");
	if (asicdata->switchdevif.REG_PMPC) __symbol_put("sx_ACCESS_REG_PMPC");
	if (asicdata->switchdevif.REG_MSCI) __symbol_put("sx_ACCESS_REG_MSCI");
	if (asicdata->switchdevif.REG_MJTAG) __symbol_put("sx_ACCESS_REG_MJTAG");
	if (asicdata->switchdevif.REG_PMAOS) __symbol_put("sx_ACCESS_REG_PMAOS");
	if (asicdata->switchdevif.REG_MFCR) __symbol_put("sx_ACCESS_REG_MFCR");
	if (asicdata->switchdevif.REG_MGIR) __symbol_put("sx_ACCESS_REG_MGIR");
	if (asicdata->switchdevif.REG_MLCR) __symbol_put("sx_ACCESS_REG_MLCR");
	if (asicdata->switchdevif.REG_PMLP) __symbol_put("sx_ACCESS_REG_PMLP");
	if (asicdata->switchdevif.DEV_CONTEXT) __symbol_put("sx_get_dev_context");
	mutex_destroy(&asicdata->switchdevif.access_lock);

	return 0;
}

static const struct i2c_device_id asic_id[] = {
        { "mlnx-asic-drv", asic_drv_32_ports },
        { "mlnx-asic-drv-64", asic_drv_64_ports },
        { "mlnx-asic-drv-54", asic_drv_54_ports },
        { "mlnx-asic-drv-36", asic_drv_36_ports },
        { "mlnx-asic-drv-16", asic_drv_16_ports },
        { "mlnx-asic-drv-56", asic_drv_56_ports },
        { }
};
MODULE_DEVICE_TABLE(i2c, asic_id);

static struct i2c_driver mlnx_asic_drv = {
        .class          = I2C_CLASS_HWMON,
        .driver = {
                .name   = "mlnx-asic-drv",
        },
        .probe          = asic_probe,
        .remove         = asic_remove,
        .id_table       = asic_id,
};

static int __init mlnx_asic_drv_init(void)
{
	int err;

	err = i2c_add_driver(&mlnx_asic_drv);

	printk(KERN_INFO "%s Version %s\n", ASIC_DRV_DESCRIPTION, ASIC_DRV_VERSION);

	return err;
}

static void __exit mlnx_asic_drv_fini(void)
{
	i2c_del_driver(&mlnx_asic_drv);
}

module_init(mlnx_asic_drv_init);
module_exit(mlnx_asic_drv_fini);
    
