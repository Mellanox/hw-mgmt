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

#include <linux/version.h>
#include <linux/acpi.h>
#include <linux/slab.h>
#include <linux/mutex.h>
#include <linux/list.h>
#include <linux/kref.h>
#include <linux/module.h>
#include <linux/i2c.h>
#include <linux/hwmon.h>
#include <linux/hwmon-sysfs.h>
#include <linux/interrupt.h>
#include <linux/workqueue.h>
#include <linux/dmi.h>
#include <linux/string.h>
#include "arch/x86/include/mlnx-common.h"
#include "mlnx-mux-drv.h"
#include "mlnx-common-drv.h"
#include "mlnx-sys-type.h"

#define THREAD_IRQ_SLEEP_SECS	2
#define THREAD_IRQ_SLEEP_MSECS	(THREAD_IRQ_SLEEP_SECS * MSEC_PER_SEC)
#define LED_NUM               7
#define PSU_MODULE_NUM        2
#define FAN_MODULE_NUM        4
#define CPLD_NUM              3
#define RESET_NUM             3
#define WP_REG_NUM            4
#define INIT_REG_NUM          2
#define MUX_NUM               2
#define MUX_CHAN_NUM          8
#define MAX_LED_STATUS       11
#define MAX_LED_NAME_LEN     32
#define LED_IS_OFF           0x00
#define LED_CNTRL_BY_CPLD    0x01
#define LED_RED_STATIC_ON    0x05
#define LED_RED_BLINK_3HZ    0x06
#define LED_RED_BLINK_6HZ    0x07
#define LED_YELLOW_STATIC_ON 0x09
#define LED_YELLOW_BLINK_3HZ 0x0A
#define LED_YELLOW_BLINK_6HZ 0x0B
#define LED_GREEN_STATIC_ON  0x0D
#define LED_GREEN_BLINK_3HZ  0x0E
#define LED_GREEN_BLINK_6HZ  0x0F
#define NOT_USED_LED_OFFSET  0xFE
typedef enum led_color {
	led_nocolor           = 0,
	led_yellow            = 1 << 0,
	led_yellow_blink      = 1 << 1,
	led_green             = 1 << 2,
	led_green_blink       = 1 << 3,
	led_red               = 1 << 4,
	led_blue              = 1 << 5,
	led_red_blink         = 1 << 6,
	led_yellow_blink_fast = 1 << 7,
	led_green_blink_fast  = 1 << 8,
	led_red_blink_fast    = 1 << 9,
	led_cpld_ctrl         = 1 << 10,
	led_all               = 0x7fffffff,
	led_not_exist         = 0xffffffff,
} led_color_t;

typedef enum reset_cause {
	cause_clean             = 0x00,
	cause_long_pb           = 0x01,
	cause_short_pb          = 0x02,
	cause_aux_pwr_off_or_fu = 0x04,
	cause_power_fail        = 0x08,
	cause_sw_rst            = 0x10,
	cause_fw_rst            = 0x20,
	cause_watch_dog         = 0x40,
	cause_thermal_shutdown  = 0x80,
} reset_cause_t;

static inline const char *led_color_code_2string(led_color_t color)
{
	switch (color) {
	case led_nocolor:
		return "none";
	case led_yellow:
		return "yellow";
	case led_green:
		return "green";
	case led_red:
		return "red";
	case led_blue:
		return "blue";
	case led_yellow_blink:
		return "yellow_blink";
	case led_green_blink:
		return "green_blink";
	case led_red_blink:
		return "red_blink";
	case led_yellow_blink_fast:
		return "yellow_blink_fast";
	case led_green_blink_fast:
		return "green_blink_fast";
	case led_red_blink_fast:
		return "red_blink_fast";
	case led_cpld_ctrl:
		return "cpld_control";
	case led_all:
	case led_not_exist:
	default:
		return "not exist";
	}
}

static inline const char *led_color_mask_2string(u32 color_mask, int flag)
{
	switch (color_mask) {
	case LED_IS_OFF:
		return "none";
	case LED_CNTRL_BY_CPLD:
		return "cpld_control";
	case LED_RED_STATIC_ON:
		return "red";
	case LED_RED_BLINK_3HZ:
		return "red_blink";
	case LED_RED_BLINK_6HZ:
		return "red_blink_fast";
	case LED_YELLOW_STATIC_ON:
		return "yellow";
	case LED_YELLOW_BLINK_3HZ:
		return "yellow_blink";
	case LED_YELLOW_BLINK_6HZ:
		return "yellow_blink_fast";
	case LED_GREEN_STATIC_ON:
		if (flag)
			return "blue";
		else
			return "green";
	case LED_GREEN_BLINK_3HZ:
		if (flag)
			return "blue_blink";
		else
			return "green_blink";
	case LED_GREEN_BLINK_6HZ:
		if (flag)
			return "blue_blink_fast";
		else
			return "green_blink_fast";
	default:
		return "not exist";
	}
}

static inline led_color_t led_color_string_2code(const char *buf)
{
	if (!strncmp(buf, "none", strlen("none")))
		return led_nocolor;
	else if (!strncmp(buf, "yellow_blink_fast", strlen("yellow_blink_fast")))
		return led_yellow_blink_fast;
	else if (!strncmp(buf, "green_blink_fast", strlen("green_blink_fast")))
		return led_green_blink_fast;
	else if (!strncmp(buf, "red_blink_fast", strlen("red_blink_fast")))
            return led_red_blink_fast;
	else if (!strncmp(buf, "yellow_blink", strlen("yellow_blink")))
		return led_yellow_blink;
	else if (!strncmp(buf, "green_blink", strlen("green_blink")))
		return led_green_blink;
	else if (!strncmp(buf, "red_blink", strlen("red_blink")))
		return led_red_blink;
	else if (!strncmp(buf, "yellow", strlen("yellow")))
		return led_yellow;
	else if (!strncmp(buf, "green", strlen("green")))
		return led_green;
	else if (!strncmp(buf, "red", strlen("red")))
		return led_red;
	else if (!strncmp(buf, "cpld_control", strlen("cpld_control")))
		return led_cpld_ctrl;
	else if (!strncmp(buf, "blue", strlen("blue")))
		return led_green;
	else if (!strncmp(buf, "blue_blink", strlen("blue_blink")))
		return led_green_blink;
	else if (!strncmp(buf, "blue_blink_fast", strlen("blue_blink_fast")))
		return led_green_blink_fast;
	else
		return led_not_exist;
}

static inline int led_color_string_2mask(const char *buf)
{
	if (!strncmp(buf, "none", strlen("none")))
		return LED_IS_OFF;
	else if (!strncmp(buf, "yellow_blink_fast", strlen("yellow_blink_fast")))
		return LED_YELLOW_BLINK_6HZ;
	else if (!strncmp(buf, "green_blink_fast", strlen("green_blink_fast")))
		return LED_GREEN_BLINK_6HZ;
	else if (!strncmp(buf, "red_blink_fast", strlen("red_blink_fast")))
		return LED_RED_BLINK_6HZ;
	else if (!strncmp(buf, "yellow_blink", strlen("yellow_blink")))
		return LED_YELLOW_BLINK_3HZ;
	else if (!strncmp(buf, "green_blink", strlen("green_blink")))
		return LED_GREEN_BLINK_3HZ;
	else if (!strncmp(buf, "red_blink", strlen("red_blink")))
		return LED_RED_BLINK_3HZ;
	else if (!strncmp(buf, "yellow", strlen("yellow")))
		return LED_YELLOW_STATIC_ON;
	else if (!strncmp(buf, "green", strlen("green")))
		return LED_GREEN_STATIC_ON;
	else if (!strncmp(buf, "red", strlen("red")))
		return LED_RED_STATIC_ON;
	else if (!strncmp(buf, "cpld_control", strlen("cpld_control")))
		return LED_CNTRL_BY_CPLD;
	else if (!strncmp(buf, "blue_blink_fast", strlen("blue_blink_fast")))
		return LED_GREEN_BLINK_6HZ;
	else if (!strncmp(buf, "blue_blink", strlen("blue_blink")))
		return LED_GREEN_BLINK_3HZ;
	else if (!strncmp(buf, "blue", strlen("blue")))
		return LED_GREEN_STATIC_ON;
	else
		return -1;
}

static inline char *reset_cause_code_2string(reset_cause_t cause)
{
	switch (cause) {
	case cause_clean:
		return "clean";
	case cause_long_pb:
		return "long press button";
	case cause_short_pb:
		return "short press button";
	case cause_aux_pwr_off_or_fu:
		return "aux pwr off or field upgr";
	case cause_power_fail:
		return "power fail";
	case cause_sw_rst:
		return "sw reset";
	case cause_fw_rst:
		return "fw reset";
	case cause_watch_dog:
		return "watch dog";
	case cause_thermal_shutdown:
		return "switch brd pwr fail";
	default:
		return "not exist or mixed";
	}
}

typedef enum event_type {
	no_event    = 0,
	psu_event   = 1,
	power_event = 2,
	psu_alarm = 3,
	fan_event   = 4,
} event_type_t;

/**
 * cpld_led_profile (defined per system class) -
 * @offset - offset for led access in CPLD device
 * @mask - mask for led access in CPLD device
 * @base_color - base color code
 * @brightness - default brightness setting (on/off)
 * @name - led name
**/
struct cpld_led_profile {
	u8 offset;
	u8 mask;
	u8 num_capabilities;
	u8 blue_flag;
	const char *capability[MAX_LED_STATUS];
};

struct cpld_leds_profile {
	u8 fan_led_offset;
	u8 psu_led_offset;
	u8 status_led_offset;
	u8 uid_led_offset;
	u8 bp_led_offset;
	struct cpld_led_profile *profile;
};
static struct cpld_leds_profile leds_profile;

struct cpld_led_profile led_default_profile[] = {
	{
		.offset = 0x21,
		.mask = 0xf0,
		.num_capabilities = 8,
		.blue_flag = 0,
		.capability = { "none", "cpld_control", "green_blink_fast",
				"red_blink_fast", "green_blink", "red_blink",
				"green", "red" },
	},
	{
		.offset = 0x21,
		.mask = 0x0f,
		.num_capabilities = 8,
		.blue_flag = 0,
		.capability = { "none", "cpld_control", "green_blink_fast",
				"red_blink_fast", "green_blink", "red_blink",
				"green", "red" },
	},
	{
		.offset = 0x22,
		.mask = 0xf0,
		.num_capabilities = 8,
		.blue_flag = 0,
		.capability = { "none", "cpld_control", "green_blink_fast",
				"red_blink_fast", "green_blink", "red_blink",
				"green", "red" },
	},
	{
		.offset = 0x22,
		.mask = 0x0f,
		.num_capabilities = 8,
		.blue_flag = 0,
		.capability = { "none", "cpld_control", "green_blink_fast",
				"red_blink_fast", "green_blink", "red_blink",
				"green", "red" },
	},
	{
		.offset = 0x20,
		.mask = 0xf0,
		.num_capabilities = 8,
		.blue_flag = 0,
		.capability = { "none", "cpld_control", "green_blink_fast",
				"red_blink_fast", "green_blink", "red_blink",
				"green", "red" },
	},
	{
		.offset = 0x20,
		.mask = 0x0f,
		.num_capabilities = 8,
		.blue_flag = 0,
		.capability = { "none", "cpld_control", "green_blink_fast",
				"red_blink_fast", "green_blink", "red_blink",
				"green", "red" },
	},
};

/* Profile fit the Mellanox systems based on "msn2100" */
struct cpld_led_profile led_msn2100_profile[] = {
	{
		.offset = 0x21,
		.mask = 0xf0,
		.num_capabilities = 8,
		.blue_flag = 0,
		.capability = { "none", "cpld_control", "green_blink_fast",
				"red_blink_fast", "green_blink", "red_blink",
				"green", "red" },
	},
	{
		.offset = 0x23,
		.mask = 0xf0,
		.num_capabilities = 8,
		.blue_flag = 0,
		.capability = { "none", "cpld_control", "green_blink_fast",
				"red_blink_fast", "green_blink", "red_blink",
				"green", "red" },
	},
	{
		.offset = 0x23,
		.mask = 0x0f,
		.num_capabilities = 8,
		.blue_flag = 0,
		.capability = { "none", "cpld_control", "green_blink_fast",
				"red_blink_fast", "green_blink", "red_blink",
				"green", "red" },
	},
	{
		.offset = 0x20,
		.mask = 0xf0,
		.num_capabilities = 8,
		.blue_flag = 0,
		.capability = { "none", "cpld_control", "green_blink_fast",
				"red_blink_fast", "green_blink", "red_blink",
				"green", "red" },
	},
	{
		.offset = 0x24,
		.mask = 0xf0,
		.num_capabilities = 5,
		.blue_flag = 1,
		.capability = { "none", "cpld_control", "blue_blink_fast",
				"blue_blink", "blue" },
	},
};

struct led_params {
	u8 offset;          /* LED offset within CPLD address space */
	u8 access_mask;     /* LED access mask */
	u8 num_led_capability;
	u8 blue_flag;
	const char *capability[MAX_LED_STATUS];
};

struct led_config {
	struct mlnx_bsp_entry entry; /* Entry id */
	struct led_params     params;
	led_color_t           led_cache;
};

struct led_config_params {
	u8 num_led;
	u8 led_alarm_mask;
	struct led_config led[LED_NUM];
};

struct module_params {
 	u8 offset;  /* Offset within CPLD address space */
	u8 bit;     /* Bit access */
};

struct topology_params {
	u8 mux;      /* MUX on which device is connecetd */
	u8 addr;     /* Address where device is located */
};

struct module_psu_config {
	struct mlnx_bsp_entry entry;            /* Entry id */
        struct module_params presence_status;
        struct module_params presence_event;
        struct module_params presence_mask;
        u8 presence_status_cache;
        struct module_params power_status;
        struct module_params power_event;
        struct module_params power_mask;
        u8 power_status_cache;
        struct module_params alarm_status;
        struct module_params alarm_event;
        struct module_params alarm_mask;
        u8 alarm_status_cache;
        struct module_params pwr_off;
        struct topology_params topology;
        struct topology_params eeprom_topology;
	struct i2c_adapter *control_adapter;
	struct i2c_client *control_client;
	struct i2c_adapter *eeprom_adapter;
	struct i2c_client *eeprom_client;
};

struct module_psu_config_params {
	u8 num_psu_modules;
	u8 num_fixed_psu_modules;
	u8 presence_status_cache;
	u8 power_status_cache;
	u8 alarm_status_cache;
	u8 mask;
 	struct module_psu_config module[PSU_MODULE_NUM];
};

struct module_fan_config {
	struct mlnx_bsp_entry entry;            /* Entry id */
        struct module_params presence_status;
        struct module_params presence_event;
        struct module_params presence_mask;
        u8 presence_status_cache;
        struct topology_params eeprom_topology;
	struct i2c_adapter *eeprom_adapter;
	struct i2c_client *eeprom_client;
};

struct module_fan_config_params {
        u8 num_fan_modules;
        u8 presence_status_cache;
        u8 mask;
        struct module_fan_config module[FAN_MODULE_NUM];
};

struct info_params {
	struct mlnx_bsp_entry entry; /* Entry id */
        u8 version_offset;         /* Offset of version within CPLD address space */
};

struct info_config_params {
        u8 num_cpld;
        struct info_params info[CPLD_NUM];
};

struct reset_params {
	struct mlnx_bsp_entry entry; /* Entry id */
        u8 offset;  /* Offset within CPLD address space */
        u8 bit;     /* Bit access */
};

struct reset_config_params {
        u8 num_reset;
        struct reset_params reset[RESET_NUM];
};

struct mux_params {
        char *mux_driver;
        u8 parent_mux;
	struct cpld_mux_platform_data *platform;
	struct i2c_adapter *adapter;
	struct i2c_client *client;
};

struct mux_config_params {
        u8 num_mux;
        struct mux_params mux[RESET_NUM];
};

struct cpld_data;
typedef int (*exec_entry)(struct cpld_data *cplddata, u8 id, u8 status,
			  u8 extra_status, event_type_t event);

struct exec_table {
        exec_entry  psu_exec_entry;
        exec_entry  fan_exec_entry;
        exec_entry  fan_init_entry;
        exec_entry  fan_exit_entry;
        exec_entry  psu_init_entry;
        exec_entry  psu_exit_entry;
};

struct cpld_data {
	struct list_head                 list;
	struct kref                      kref;
	__u16                            base;        /* Low Pin Count (LPC) bus access base address */
	__u16                            size;        /* Size of mapped address space */
        struct device                   *hwmon_dev;
	struct device                   *cpld_hwmon_dev;
        const char                      *name;
        struct mutex                     access_lock;
        unsigned long                    last_update; /* in jiffies */
        struct led_config_params         cfg_led;
        struct module_fan_config_params  cfg_fan_module;
        struct module_psu_config_params  cfg_psu_module;
        struct info_config_params        cfg_info;
        struct reset_config_params       cfg_reset;
        struct module_params             top_aggregation_status;
        struct module_params             top_aggregation_mask;
        u8                          top_aggregation_cache;
        struct module_params             wp_reg_offset[WP_REG_NUM];
        struct module_params             init_reg_offset[INIT_REG_NUM];
        struct module_params             init_reg_mask[INIT_REG_NUM];
        struct exec_table                exec_tab;
	spinlock_t 		         lock;
	wait_queue_head_t 	         poll_wait;
	u8			         int_occurred;
	int			         int_disable_counter;
	int			         irq;
	struct delayed_work	         dwork;
	u8			         resched_on_exit;
};

/* Container structure */
struct cpld_container {
	struct list_head list;
        struct device            *cpld_hwmon_dev;
        struct mux_config_params  cfg_mux;
    enum mlnx_system_types mlnx_system_type;
};
static struct cpld_container cpld_db;

#define CPLD_DRV_VERSION     "0.0.1 24/08/2015"
#define CPLD_DRV_DESCRIPTION "Mellanox CPLD BSP driver. Build:" " "__DATE__" "__TIME__
MODULE_AUTHOR("Vadim Pasternak (vadimp@mellanox.com)");
MODULE_DESCRIPTION(CPLD_DRV_DESCRIPTION);
MODULE_LICENSE("GPL v2");
MODULE_ALIAS("mlnx-cpld");

static bool led_control = 0;
module_param(led_control, bool, 0);
MODULE_PARM_DESC(led_control, "Handle LED and FAN inside driver, default is NO");
static bool fan_control = 0;
module_param(fan_control, bool, 0);
MODULE_PARM_DESC(fan_control, "Handle LED and FAN inside driver, default is NO");
static bool interrupt_mode = 1;
module_param(interrupt_mode, bool, 0);
MODULE_PARM_DESC(interrupt_mode, "Run driver with interrupt handling, default is YES");

static unsigned short num_led = 6;
module_param(num_led, ushort, 0);
MODULE_PARM_DESC(num_led, "Number of LED, default is 6");
static unsigned short num_fixed_psu_modules = 0;
static unsigned short num_psu_modules = 2;
module_param(num_psu_modules, ushort, 0);
MODULE_PARM_DESC(num_psu_modules, "Number of replacable PSU modules, default is 2");
static unsigned short num_fan_modules = 4;
module_param(num_fan_modules, ushort, 0);
MODULE_PARM_DESC(num_fan_modules, "Number of replacable FAN modules, default is 4");
static unsigned short num_cpld = 3;
module_param(num_cpld, ushort, 0);
MODULE_PARM_DESC(num_cpld, "Number of CPLD, default is 3");
static unsigned short num_reset = 3;
module_param(num_reset, ushort, 0);
MODULE_PARM_DESC(num_reset, "Number of reset signals, default is 3");
static unsigned short num_mux = 2;
module_param(num_mux, ushort, 0);
MODULE_PARM_DESC(num_mux, "Number of mux devices, default is 2");

static int def_led_alarm_color = led_red;
module_param(def_led_alarm_color, int, 0);
MODULE_PARM_DESC(def_led_alarm_color, "Default LED alarm color is led_red");

static unsigned short psu_module_presence_status_offset[PSU_MODULE_NUM] = { 0x58, 0x58 };
module_param_array(psu_module_presence_status_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_presence_status_offset, "Module status offsets vector (default)");
static unsigned short psu_module_presence_event_offset[PSU_MODULE_NUM] = { 0x59, 0x59 };
module_param_array(psu_module_presence_event_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_presence_event_offset, "Module event offsets vector (default)");
static unsigned short psu_module_presence_mask_offset[PSU_MODULE_NUM] = { 0x5a, 0x5a };
module_param_array(psu_module_presence_mask_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_presence_mask_offset, "Module mask offsets vector (default)");
static unsigned short psu_module_power_status_offset[PSU_MODULE_NUM] = { 0x64, 0x64 };
module_param_array(psu_module_power_status_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_power_status_offset, "Module power status offsets vector (default)");
static unsigned short psu_module_power_event_offset[PSU_MODULE_NUM] = { 0x65, 0x65 };
module_param_array(psu_module_power_event_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_power_event_offset, "Module power event offsets vector (default)");
static unsigned short psu_module_power_mask_offset[PSU_MODULE_NUM] = { 0x66, 0x66 };
module_param_array(psu_module_power_mask_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_power_mask_offset, "Module power mask offsets vector (default)");
static unsigned short psu_module_alarm_status_offset[PSU_MODULE_NUM] = { 0x6a, 0x6a };
module_param_array(psu_module_alarm_status_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_alarm_status_offset, "Module alarm status offsets vector (default)");
static unsigned short psu_module_alarm_event_offset[PSU_MODULE_NUM] = { 0x6b, 0x6b };
module_param_array(psu_module_alarm_event_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_alarm_event_offset, "Module alarm event offsets vector (default)");
static unsigned short psu_module_alarm_mask_offset[PSU_MODULE_NUM] = { 0x6c, 0x6c };
module_param_array(psu_module_alarm_mask_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_alarm_mask_offset, "Module alarm status offsets vector (default)");

static unsigned short psu_module_pwr_off_offset[PSU_MODULE_NUM] = { 0x30, 0x30 };
module_param_array(psu_module_pwr_off_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_pwr_off_offset, "Module power off offsets vector (default)");
static unsigned short psu_module_pwr_off_bit[PSU_MODULE_NUM] = { 0, 1 };
module_param_array(psu_module_pwr_off_bit, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_pwr_off_bit, "Module power off bit vector (default)");

static unsigned short psu_module_mux[PSU_MODULE_NUM] = { 10, 10 };
module_param_array(psu_module_mux, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_mux, "PSU module mux vector (default)");
static unsigned short psu_module_addr[PSU_MODULE_NUM] = { 0x59, 0x58 };
module_param_array(psu_module_addr, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_addr, "PSU module address vector (default)");

static unsigned short psu_module_bit[PSU_MODULE_NUM] = { 0, 1 };
module_param_array(psu_module_bit, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_module_bit, "PSU module bit vector (default)");

static unsigned short fan_module_presence_status_offset[FAN_MODULE_NUM] = { 0x88, 0x88, 0x88, 0x88};
module_param_array(fan_module_presence_status_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(fan_module_presence_status_offset, "Module status offsets vector (default)");
static unsigned short fan_module_presence_event_offset[FAN_MODULE_NUM] = { 0x89, 0x89, 0x89, 0x89};
module_param_array(fan_module_presence_event_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(fan_module_presence_event_offset, "Module event offsets vector (default)");
static unsigned short fan_module_presence_mask_offset[FAN_MODULE_NUM] = { 0x8a, 0x8a, 0x8a, 0x8a};
module_param_array(fan_module_presence_mask_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(fan_module_presence_mask_offset, "Module mask offsets vector (default)");
static unsigned short fan_module_bit[FAN_MODULE_NUM] = { 0, 1, 2, 3};
module_param_array(fan_module_bit, ushort, NULL, 0644);
MODULE_PARM_DESC(fan_module_bit, "FAN module bit vector (default)");

static unsigned short version_offset[CPLD_NUM] = { 0, 1, 2 };
module_param_array(version_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(version_offset, "CPLD version vector (default)");

static unsigned short exec_id = 0;
module_param(exec_id, ushort, 0);
MODULE_PARM_DESC(exec_id, "FAN and LED exec Id (default) 0");

static char *fan_eeprom_driver = "24c32";
module_param(fan_eeprom_driver, charp, 0);
MODULE_PARM_DESC(fan_eeprom_driver, "FAN EEPROM driver name (default is eeprom)");
static unsigned short fan_eeprom_mux[FAN_MODULE_NUM] = { 11, 12, 13, 14 };
module_param_array(fan_eeprom_mux, ushort, NULL, 0644);
MODULE_PARM_DESC(fan_eeprom_mux, "FAN EEPROM mux vector (default 11, 12, 13, 14)");
static unsigned short fan_eeprom_addr[FAN_MODULE_NUM] = { 0x50, 0x50, 0x50, 0x50 };
module_param_array(fan_eeprom_addr, ushort, NULL, 0644);
MODULE_PARM_DESC(fan_eeprom_addr, "FAN EEPROM address vector (default 0x50, 0x50, 0x50, 0x50)");

static char *psu_eeprom_driver = "24c02";
module_param(psu_eeprom_driver, charp, 0);
MODULE_PARM_DESC(psu_eeprom_driver, "PSU EEPROM driver name (default is eeprom)");
static char *psu_control_driver = "pmbus";
module_param(psu_control_driver, charp, 0);
MODULE_PARM_DESC(psu_control_driver, "PSU control driver name (default is eeprom)");

static unsigned short psu_mux[PSU_MODULE_NUM] = { 10, 10 };
module_param_array(psu_mux, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_mux, "FAN EEPROM mux vector (default 10, 10)");
static unsigned short psu_control_addr[PSU_MODULE_NUM] = { 0x59, 0x58 };
module_param_array(psu_control_addr, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_control_addr, "PSU EEPROM address vector (default 0x59, 0x58)");
static unsigned short psu_eeprom_addr[PSU_MODULE_NUM] = { 0x51, 0x50 };
module_param_array(psu_eeprom_addr, ushort, NULL, 0644);
MODULE_PARM_DESC(psu_eeprom_addr, "PSU EEPROM address vector (default 0x51, 0x50)");

MODULE_PARM_DESC(mux_driver, "MUX driver name (default is eeprom)");
static char *mux_driver = "cpld_mux_tor";
module_param(mux_driver, charp, 0);
static unsigned short parent_mux[MUX_NUM] = { 1, 1};
module_param_array(parent_mux, ushort, NULL, 0644);
MODULE_PARM_DESC(parent_mux, "BUS/MUX where MUX device is attached (default 1, 1)");
static unsigned short mux_first_num[MUX_NUM] = { 2, 10};
module_param_array(mux_first_num, ushort, NULL, 0644);
MODULE_PARM_DESC(mux_first_num, "The first channel on MUX device (default 2, 9)");
static unsigned short mux_chan_num[MUX_NUM] = { 8, 8};
module_param_array(mux_chan_num, ushort, NULL, 0644);
MODULE_PARM_DESC(mux_chan_num, "Number of channels per MUX device (default 8, 8)");
static unsigned short mux_reg_offset[MUX_NUM] = { 0x25db, 0x25da};
module_param_array(mux_reg_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(mux_reg_offset, "MUX control register offset vector (default 0x25db, 0x25da)");
static unsigned short deselect_on_exit = 1;
module_param(deselect_on_exit, ushort, 0);
MODULE_PARM_DESC(deselect_on_exit, "MUX deselect on exxit (default) 1");
static unsigned short force_chan = 0;
module_param(force_chan, ushort, 0);
MODULE_PARM_DESC(force_chan, "Force MUX start channel id (default) 0");

static unsigned short default_fan_speed = 60;
module_param(default_fan_speed, ushort, 0);
MODULE_PARM_DESC(default_fan_speed, "Deafault FAN speed in percents (default) 60");

static unsigned short cpld_lpc_base = 0x2500;
module_param(cpld_lpc_base, ushort, 0);
MODULE_PARM_DESC(cpld_lpc_base, "CPLD LPC base address (default 0x2500)");
static unsigned short cpld_lpc_size = 0x100;
module_param(cpld_lpc_size, ushort, 0);
MODULE_PARM_DESC(cpld_lpc_size, "CPLD LPC IO size (default 0x100)");

static unsigned short irq_line = DEF_IRQ_LINE;
module_param(irq_line, ushort, 0);
MODULE_PARM_DESC(irq_line, "CPU IRQ line");

static unsigned short num_wp_regs = 4;
module_param(num_wp_regs, ushort, 0);
MODULE_PARM_DESC(num_wp_regs, "Number of write protected registers, default is 4");
static unsigned short wp_reg_offset[WP_REG_NUM] = { 0x2e, 0x31, 0x18, 0x1a };
module_param_array(wp_reg_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(wp_reg_offset, "Write protected register offsets vector (default)");

static unsigned short num_init_regs = 2;
module_param(num_init_regs, ushort, 0);
MODULE_PARM_DESC(num_init_regs, "Number of init registers, default is 2");
static unsigned short init_reg_offset[INIT_REG_NUM] = { 0x2f, 0x33 };
module_param_array(init_reg_offset, ushort, NULL, 0644);
MODULE_PARM_DESC(init_reg_offset, "Init register offsets vector (default)");
static unsigned short init_reg_mask[INIT_REG_NUM] = { 0xbf, 0xbf };
module_param_array(init_reg_mask, ushort, NULL, 0644);
MODULE_PARM_DESC(init_reg_mask, "Init register masks vector (default)");

static unsigned short platform_reset_offset = 0x17;
module_param(platform_reset_offset, ushort, 0);
MODULE_PARM_DESC(platform_reset_offsets, "Platfrom reset register offset, default is 0x19");
static unsigned short platform_reset_bit = 0;
module_param(platform_reset_bit, ushort, 0);
MODULE_PARM_DESC(platform_reset_bit, "Platfrom reset register bit, default is 0x0");

static unsigned short pcie_slot_reset_offset = 0x17;
module_param(pcie_slot_reset_offset, ushort, 0);
MODULE_PARM_DESC(pcie_slot_reset_offsets, "PCIe slot reset register offset, default is 0x19");
static unsigned short pcie_slot_reset_bit = 1;
module_param(pcie_slot_reset_bit, ushort, 0);
MODULE_PARM_DESC(pcie_slot_reset_bit, "PCIe slot reset register bit, default is 0x1");

static unsigned short switch_brd_reset_offset = 0x17;
module_param(switch_brd_reset_offset, ushort, 0);
MODULE_PARM_DESC(switch_brd_reset_offsets, "Switch board reset register offset, default is 0x19");
static unsigned short switch_brd_reset_bit = 2;
module_param(switch_brd_reset_bit, ushort, 0);
MODULE_PARM_DESC(switch_brd_reset_bit, "Switch board reset register bit, default is 0x2");

static unsigned short asic_reset_offset = 0x19;
module_param(asic_reset_offset, ushort, 0);
MODULE_PARM_DESC(asic_reset_offsets, "ASIC reset register offset, default is 0x19");
static unsigned short asic_reset_bit = 3;
module_param(asic_reset_bit, ushort, 0);
MODULE_PARM_DESC(asic_reset_bit, "ASIC reset register bit, default is 0x3");

static unsigned short sys_pwr_cycle_offset = 0x30;
module_param(sys_pwr_cycle_offset, ushort, 0);
MODULE_PARM_DESC(sys_pwr_cycle_offsets, "System power cycle register offset, default is 0x30");
static unsigned short sys_pwr_cycle_bit = 2;
module_param(sys_pwr_cycle_bit, ushort, 0);
MODULE_PARM_DESC(sys_pwr_cycle_bit, "System power cycle register bit, default is 0x2");
static unsigned short sys_reset_cause_offset = 0x1d;
module_param(sys_reset_cause_offset, ushort, 0);
MODULE_PARM_DESC(sys_reset_cause_offset, "System reset cause register offset, default is 0x1d");

static unsigned short top_aggregation_status_offset = 0x3a;
module_param(top_aggregation_status_offset, ushort, 0);
MODULE_PARM_DESC(top_aggregation_status_offset, "top aggregation status register offset (default 0x3a)");
static unsigned short top_aggregation_mask_offset = 0x3b;
module_param(top_aggregation_mask_offset, ushort, 0);
MODULE_PARM_DESC(top_aggregation_mask_offset, "top aggregation mask register offset (default 0x3b)");
static unsigned short top_aggregation_mask = 0x4f;
module_param(top_aggregation_mask, ushort, 0);
MODULE_PARM_DESC(top_aggregation_mask_offset, "top aggregation mask register (default 0x4f)");


int (*mlnx_set_fan_hook)(u8 asic_id, u8 id, u8 speed) = NULL;
EXPORT_SYMBOL(mlnx_set_fan_hook);

static int bus_access_func(struct cpld_data *cplddata,
		           u8                from_range,
		           u8                to_range,
		           u8                rw_flag,
		           u8               *data,
		           u8                lock_flag)
{
        int datalen = to_range - from_range + 1;

        if (lock_flag)
                mutex_lock(&cplddata->access_lock);
        bus_rw(cplddata->base, from_range, datalen, rw_flag, data);
        if (lock_flag)
                mutex_unlock(&cplddata->access_lock);

	return 0;
}

static inline int handle_mask_read_entry_point(struct cpld_data     *cplddata,
                                               struct module_params *status,
                                               struct module_params *mask,
                                               u8                   *status_cache,
                                               u8                   *mask_cache,
                                               u8                    item_num,
                                               event_type_t          event)
{
        u8 err = 0, data = 0, bit_mask, i, j;

        if (*mask_cache == 0)
                return 0;

        /* Mask event */
        bus_access_func(cplddata,
                        mask->offset,
                        mask->offset,
                        0, &data, 0);
        /* Read status */
        bus_access_func(cplddata,
                        status->offset,
                        status->offset,
                        1, &data, 0);

        switch (event) {
        case psu_event:
        case fan_event:
                data = (~(data) & *mask_cache);
                break;
        default:
                data = (data & *mask_cache);
                break;
        }

        bit_mask = (*status_cache) ^ data;
        *status_cache = data;

        if (!bit_mask)
                return err;

        for (i = 0, j = 1; i <= 7; i++) {
                if (bit_mask & j) {
                        switch (event) {
                        case psu_event:
                                err = cplddata->exec_tab.psu_exec_entry(cplddata, i, (bit_mask & data), 0, event);
                                break;
                        case power_event:
                                err = cplddata->exec_tab.psu_exec_entry(cplddata, i, (bit_mask & data), 0, event);
                                break;
                        case fan_event:
                                err = cplddata->exec_tab.fan_exec_entry(cplddata, i, (bit_mask & data), 0, event);
                                break;
                        case psu_alarm:
                        case no_event:
                                break;
                        }
                }
                j = j << 1;
        }

        return err;
}

static inline int handle_clear_unmask_entry_point(struct cpld_data     *cplddata,
                                                  struct module_params *event,
                                                  struct module_params *mask,
                                                  u8 *mask_cache,
                                                  u8 *event_cache)
{
        u8 err = 0, data = 0;

        /* clear event */
        bus_access_func(cplddata,
                        event->offset,
                        event->offset,
                        0, &data, 0);
        /* unmask event */
        bus_access_func(cplddata,
                        mask->offset,
                        mask->offset,
                        0, mask_cache, 0);

        return err;
}

static inline int clear_unmask(struct cpld_data *cplddata,
                               u8                unmask_psu,
                               u8                unmask_fan)
{
        u8 id = 0, event_clear = 0;

        handle_clear_unmask_entry_point(cplddata,
                                        &cplddata->cfg_psu_module.module[id].power_event,
                                        &cplddata->cfg_psu_module.module[id].power_mask,
                                        &unmask_psu, &event_clear);
        handle_clear_unmask_entry_point(cplddata,
                                        &cplddata->cfg_psu_module.module[id].alarm_event,
                                        &cplddata->cfg_psu_module.module[id].alarm_mask,
                                        &unmask_psu, &event_clear);
        handle_clear_unmask_entry_point(cplddata,
                                        &cplddata->cfg_psu_module.module[id].presence_event,
                                        &cplddata->cfg_psu_module.module[id].presence_mask,
                                        &unmask_psu, &event_clear);
        handle_clear_unmask_entry_point(cplddata,
                                        &cplddata->cfg_fan_module.module[id].presence_event,
                                        &cplddata->cfg_fan_module.module[id].presence_mask,
                                        &unmask_fan, &event_clear);

        bus_access_func(cplddata,
                        cplddata->top_aggregation_mask.offset,
                        cplddata->top_aggregation_mask.offset,
                        0, &cplddata->top_aggregation_mask.bit, 1);

        return 0;
}

static inline int mask_read(struct cpld_data *cplddata,
                            u8                mask_psu,
                            u8                mask_fan)
{
        u8 id = 0;
        u8 data = 0, mask_aggregation = 0;

        bus_access_func(cplddata,
                        cplddata->top_aggregation_status.offset,
                        cplddata->top_aggregation_status.offset,
                        1, &data, 1);

        if (cplddata->top_aggregation_cache == data)
                return 1;

        cplddata->top_aggregation_cache = data;

        bus_access_func(cplddata,
                        cplddata->top_aggregation_status.offset,
                        cplddata->top_aggregation_status.offset,
                        0, &mask_aggregation, 1);

        handle_mask_read_entry_point(cplddata,
                                     &cplddata->cfg_psu_module.module[id].power_status,
                                     &cplddata->cfg_psu_module.module[id].power_mask,
                                     &cplddata->cfg_psu_module.power_status_cache,
                                     &cplddata->cfg_psu_module.mask,
                                     cplddata->cfg_psu_module.num_psu_modules,
                                     power_event);
        handle_mask_read_entry_point(cplddata,
                                     &cplddata->cfg_psu_module.module[id].alarm_status,
                                     &cplddata->cfg_psu_module.module[id].alarm_mask,
                                     &cplddata->cfg_psu_module.alarm_status_cache,
                                     &cplddata->cfg_psu_module.mask,
                                     cplddata->cfg_psu_module.num_psu_modules,
                                     psu_alarm);
        handle_mask_read_entry_point(cplddata,
                                     &cplddata->cfg_psu_module.module[id].presence_status,
                                     &cplddata->cfg_psu_module.module[id].presence_mask,
                                     &cplddata->cfg_psu_module.presence_status_cache,
                                     &cplddata->cfg_psu_module.mask,
                                     cplddata->cfg_psu_module.num_psu_modules,
                                     psu_event);
        handle_mask_read_entry_point(cplddata,
                                     &cplddata->cfg_fan_module.module[id].presence_status,
                                     &cplddata->cfg_fan_module.module[id].presence_mask,
                                     &cplddata->cfg_fan_module.presence_status_cache,
                                     &cplddata->cfg_fan_module.mask,
                                     cplddata->cfg_fan_module.num_fan_modules,
                                     fan_event);

        return 0;
}

typedef enum led_attr {
        led_color,
        led_name,
        led_cap,
} led_attr_t;

typedef enum module_attr {
        module_status,
        module_event,
        module_mask,
        module_name,
        module_pwr_off,
        pg_status,
        pg_event,
        pg_mask,
        alarm_status,
        alarm_event,
        alarm_mask,
} module_attr_t;

typedef enum cpld_attr {
        cpld_version,
        cpld_name,
} cpld_attr_t;

typedef enum reset_attr {
        sys_reset_cause,
        sys_pwr_cycle,
        sys_platform,
        sys_pcie_slot,
        sys_switch_brd,
        sys_asic,
} reset_attr_t;

static int cpld_set_led(struct  cpld_data *cplddata,
				int        index,
				int        led_color_mask);

#define SET_LED(c, led_id, color, err)       \
    if (led_control)                         \
        err = cpld_set_led(c, led_id, color)

#define SET_FAN(asic_id, fan_id, speed, err)             \
    if (fan_control && mlnx_set_fan_hook)                \
        err = mlnx_set_fan_hook(asic_id, fan_id, speed);

static int exec_fan_init_profile1(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
        int err = 0;

        /* Set LED for FAN according to presence bit */
        if (status) {
                SET_LED(cplddata, leds_profile.fan_led_offset + id, LED_GREEN_STATIC_ON, err);
                SET_FAN(1, id, default_fan_speed, err);
                cplddata->cfg_led.led[leds_profile.fan_led_offset + id].led_cache = led_green;
        }
        else {
                SET_LED(cplddata, leds_profile.fan_led_offset + id, cplddata->cfg_led.led_alarm_mask, err);
                cplddata->cfg_led.led[leds_profile.fan_led_offset + id].led_cache = def_led_alarm_color;
        }
        return err;
}

static int exec_fan_exit_profile1(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
        int err = 0;

        SET_LED(cplddata, leds_profile.fan_led_offset + id, LED_IS_OFF, err);
        cplddata->cfg_led.led[leds_profile.fan_led_offset + id].led_cache = led_nocolor;
        SET_FAN(1, id, 100, err);

        return err;
}

static int exec_ps_init_profile1(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
        int err = 0;

        /* Set LED for PS and STATUS according to the defined rules */
        if (status) {
		SET_LED(cplddata, leds_profile.psu_led_offset + id, LED_GREEN_STATIC_ON, err);
		cplddata->cfg_led.led[leds_profile.psu_led_offset + id].led_cache = led_green;
                /* Set status LED according to the FAN and PSU statuses */
        	if (extra_status == cplddata->cfg_fan_module.num_fan_modules) {
			SET_LED(cplddata, leds_profile.status_led_offset + id, LED_GREEN_STATIC_ON, err);
			cplddata->cfg_led.led[leds_profile.status_led_offset + id].led_cache = led_green;
        	}
        	else {
			SET_LED(cplddata, leds_profile.status_led_offset + id, cplddata->cfg_led.led_alarm_mask, err);
			cplddata->cfg_led.led[leds_profile.status_led_offset + id].led_cache = def_led_alarm_color;
        	}
        }
        else {
		SET_LED(cplddata, leds_profile.psu_led_offset + id, cplddata->cfg_led.led_alarm_mask, err);
		cplddata->cfg_led.led[leds_profile.psu_led_offset + id].led_cache = def_led_alarm_color;
		SET_LED(cplddata, leds_profile.status_led_offset + id, cplddata->cfg_led.led_alarm_mask, err);
		cplddata->cfg_led.led[leds_profile.status_led_offset + id].led_cache = def_led_alarm_color;
        }
        return err;
}

static int exec_ps_exit_profile1(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
        int err = 0;

	SET_LED(cplddata, leds_profile.psu_led_offset + id, LED_IS_OFF, err);
	cplddata->cfg_led.led[leds_profile.psu_led_offset + id].led_cache = led_nocolor;
	SET_LED(cplddata, leds_profile.status_led_offset + id, LED_IS_OFF, err);
	cplddata->cfg_led.led[leds_profile.status_led_offset + id].led_cache = led_nocolor;

        return err;
}

static int exec_fan_profile1(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
	struct i2c_board_info board_info;
	u8 fan_presence = 1;
	int err = 0, i;

        /* Set LED green for inserted device */
        /* Set FAN speed to default */
        /* Set LED yellow or red for removed device */
        switch (event) {
        case fan_event:
		if (status) {
                        SET_LED(cplddata, leds_profile.fan_led_offset + id, LED_GREEN_STATIC_ON, err);
                        SET_FAN(1, id, default_fan_speed, err);
                        cplddata->cfg_led.led[leds_profile.fan_led_offset + id].led_cache = led_green;

        		if (cplddata->cfg_psu_module.presence_status_cache == cplddata->cfg_psu_module.power_status_cache) {
				for (i = 0; i < cplddata->cfg_fan_module.num_fan_modules; i++) {
					if (!cplddata->cfg_fan_module.module[i].presence_status_cache) {
						fan_presence = 0;
						break;
					}
				}

                		if (fan_presence) {
                                	SET_LED(cplddata, leds_profile.status_led_offset, LED_GREEN_STATIC_ON, err);
                                	cplddata->cfg_led.led[leds_profile.status_led_offset].led_cache = led_green;
                		}
                	}

			if (!(cplddata->cfg_fan_module.module[id].eeprom_adapter =
			      i2c_get_adapter(cplddata->cfg_fan_module.module[id].eeprom_topology.mux))) {
				printk(KERN_INFO "%s: failed to get adapter for mux %d\n",
					__func__, cplddata->cfg_fan_module.module[id].eeprom_topology.mux);
				return -EFAULT;
			}
			memset(&board_info, 0, sizeof(struct i2c_board_info));
			board_info.addr = cplddata->cfg_fan_module.module[id].eeprom_topology.addr;
			memcpy(board_info.type, fan_eeprom_driver, I2C_NAME_SIZE);
			if (!(cplddata->cfg_fan_module.module[id].eeprom_client =
			      i2c_new_device(cplddata->cfg_fan_module.module[id].eeprom_adapter,
					    (struct i2c_board_info const*)&board_info))) {
			        printk(KERN_INFO "%s: failed to create client %s at mux %d at addr 0x%02x\n",
					__func__, fan_eeprom_driver, cplddata->cfg_fan_module.module[id].eeprom_topology.mux,
					cplddata->cfg_fan_module.module[id].eeprom_topology.addr);
			        i2c_put_adapter(cplddata->cfg_fan_module.module[id].eeprom_adapter);
				return -EFAULT;
			}
		}
		else {
                        SET_LED(cplddata, leds_profile.fan_led_offset + id, cplddata->cfg_led.led_alarm_mask, err);
                        cplddata->cfg_led.led[leds_profile.fan_led_offset + id].led_cache = def_led_alarm_color;

                        if (cplddata->cfg_led.led[leds_profile.status_led_offset].led_cache != def_led_alarm_color) {
                                 SET_LED(cplddata, leds_profile.status_led_offset, cplddata->cfg_led.led_alarm_mask, err);
                                 cplddata->cfg_led.led[leds_profile.status_led_offset].led_cache = def_led_alarm_color;
                        }

			if (cplddata->cfg_fan_module.module[id].eeprom_client) {
				i2c_unregister_device(cplddata->cfg_fan_module.module[id].eeprom_client);
				cplddata->cfg_fan_module.module[id].eeprom_client = NULL;
			}
			if (cplddata->cfg_fan_module.module[id].eeprom_adapter) {
				i2c_put_adapter(cplddata->cfg_fan_module.module[id].eeprom_adapter);
				cplddata->cfg_fan_module.module[id].eeprom_adapter = NULL;
			}
		}

                break;
        default:
                return err;
        }

        return err;
}


static int exec_psu_profile1(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
	struct i2c_board_info board_info;
	u8 fan_presence = 1;
	int err = 0, i;

        /* Follow the next rules:
           - 2 PSU presented, both have PG - set LED green;
           - 2 PSU presented, one doesn't have PG - set LED yellow;
           - 1 PSU presented, has PG - set LED green;
           - 1 PSU presented, doesn't PG - system is unavailable;
        */
        if (cplddata->cfg_psu_module.presence_status_cache == cplddata->cfg_psu_module.power_status_cache) {
                if (cplddata->cfg_led.led[leds_profile.psu_led_offset].led_cache != led_green) {
                        SET_LED(cplddata, leds_profile.psu_led_offset, LED_GREEN_STATIC_ON, err);
                        cplddata->cfg_led.led[leds_profile.psu_led_offset].led_cache = led_green;
                }

                for (i = 0; i < cplddata->cfg_fan_module.num_fan_modules; i++) {
                        if (!cplddata->cfg_fan_module.module[i].presence_status_cache) {
                                fan_presence= 0;
                                break;
                        }
                }

                if (fan_presence) {
                        if (cplddata->cfg_led.led[leds_profile.status_led_offset].led_cache != led_green) {
                                SET_LED(cplddata, leds_profile.status_led_offset, LED_GREEN_STATIC_ON, err);
                                cplddata->cfg_led.led[leds_profile.status_led_offset].led_cache = led_green;
                        }
                }
        }
        else {
                if (cplddata->cfg_led.led[leds_profile.psu_led_offset].led_cache != def_led_alarm_color) {
                        SET_LED(cplddata, leds_profile.psu_led_offset, cplddata->cfg_led.led_alarm_mask, err);
                        cplddata->cfg_led.led[leds_profile.psu_led_offset].led_cache = def_led_alarm_color;
                }

                if (cplddata->cfg_led.led[leds_profile.status_led_offset].led_cache != def_led_alarm_color) {
                        SET_LED(cplddata, leds_profile.status_led_offset, cplddata->cfg_led.led_alarm_mask, err);
                        cplddata->cfg_led.led[leds_profile.status_led_offset].led_cache = def_led_alarm_color;
                }
        }

        /*
           Probe PSU control ane eeprom modules on PG on event;
           Remove PSU control ane eeprom modules on PG off event;
        */
        switch (event) {
        case psu_event:
		if (status) {
			if (!(cplddata->cfg_psu_module.module[id].eeprom_adapter =
			      i2c_get_adapter(cplddata->cfg_psu_module.module[id].eeprom_topology.mux))) {
				printk(KERN_INFO "%s: failed to get adapter for mux %d\n",
					__func__, cplddata->cfg_psu_module.module[id].eeprom_topology.mux);
				return -EFAULT;
			}
			memset(&board_info, 0, sizeof(struct i2c_board_info));
			board_info.addr = cplddata->cfg_psu_module.module[id].eeprom_topology.addr;
			memcpy(board_info.type, psu_eeprom_driver, I2C_NAME_SIZE);
			if (!(cplddata->cfg_psu_module.module[id].eeprom_client =
			      i2c_new_device(cplddata->cfg_psu_module.module[id].eeprom_adapter,
					    (struct i2c_board_info const*)&board_info))) {
			        printk(KERN_INFO "%s: failed to create client %s at mux %d at addr 0x%02x\n",
					__func__, psu_eeprom_driver, cplddata->cfg_psu_module.module[id].eeprom_topology.mux,
					cplddata->cfg_psu_module.module[id].eeprom_topology.addr);
			        i2c_put_adapter(cplddata->cfg_psu_module.module[id].eeprom_adapter);
				return -EFAULT;
			}
		}
		else {
			if (cplddata->cfg_psu_module.module[id].eeprom_client) {
				i2c_unregister_device(cplddata->cfg_psu_module.module[id].eeprom_client);
				cplddata->cfg_psu_module.module[id].eeprom_client = NULL;
			}
			if (cplddata->cfg_psu_module.module[id].eeprom_adapter) {
				i2c_put_adapter(cplddata->cfg_psu_module.module[id].eeprom_adapter);
				cplddata->cfg_psu_module.module[id].eeprom_adapter = NULL;
			}
		}

		break;

        case power_event:
		if (status) {
			if (!(cplddata->cfg_psu_module.module[id].control_adapter =
			      i2c_get_adapter(cplddata->cfg_psu_module.module[id].topology.mux))) {
				printk(KERN_INFO "%s: failed to get adapter for mux %d\n",
					__func__, cplddata->cfg_psu_module.module[id].topology.mux);
				return -EFAULT;
			}
			memset(&board_info, 0, sizeof(struct i2c_board_info));
			board_info.addr = cplddata->cfg_psu_module.module[id].topology.addr;
			memcpy(board_info.type, psu_control_driver, I2C_NAME_SIZE);
			if (!(cplddata->cfg_psu_module.module[id].control_client =
			      i2c_new_device(cplddata->cfg_psu_module.module[id].control_adapter,
					    (struct i2c_board_info const*)&board_info))) {
			        printk(KERN_INFO "%s: failed to create client %s at mux %d at addr 0x%02x\n",
					__func__, psu_control_driver, cplddata->cfg_psu_module.module[id].topology.mux,
					cplddata->cfg_psu_module.module[id].topology.addr);
			        i2c_put_adapter(cplddata->cfg_psu_module.module[id].control_adapter);
				return -EFAULT;
			}
		}
		else {
			if (cplddata->cfg_psu_module.module[id].control_client) {
				i2c_unregister_device(cplddata->cfg_psu_module.module[id].control_client);
				cplddata->cfg_psu_module.module[id].control_client = NULL;
			}
			if (cplddata->cfg_psu_module.module[id].control_adapter) {
				i2c_put_adapter(cplddata->cfg_psu_module.module[id].control_adapter);
				cplddata->cfg_psu_module.module[id].control_adapter = NULL;
			}
		}

                break;
        default:
                return err;
        }

        return err;
}

static int exec_psu_profile2(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
        return 0;
}

static int exec_fan_profile2(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
        return 0;
}

static int exec_fan_init_profile2(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
        return 0;
}

static int exec_fan_exit_profile2(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
        return 0;
}

static int exec_ps_init_profile2(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
        return 0;
}

static int exec_ps_exit_profile2(struct cpld_data *cplddata, u8 id, u8 status, u8 extra_status, event_type_t event)
{
        return 0;
}

static struct exec_table exec_table_profile[] = {
        {
                exec_psu_profile1,
                exec_fan_profile1,
                exec_fan_init_profile1,
                exec_fan_exit_profile1,
                exec_ps_init_profile1,
                exec_ps_exit_profile1,
        },
        {
                exec_psu_profile2,
                exec_fan_profile2,
                exec_fan_init_profile2,
                exec_fan_exit_profile2,
                exec_ps_init_profile2,
                exec_ps_exit_profile2,
        },
};

static int cpld_set_led(struct cpld_data *cplddata,
			int               index,
			int               led_color_mask)
{
	struct led_config *led = NULL;
	u8 mask = (u8)led_color_mask;
	u8 val;
	int err;

	led = &cplddata->cfg_led.led[index];

	mask = (led->params.access_mask == 0xf0) ? (u8)led_color_mask : ((u8)led_color_mask << 4);
        err = bus_access_func(cplddata, led->params.offset, led->params.offset,
                              1, &val, 1);

        val = (val & led->params.access_mask) | mask;
        err = bus_access_func(cplddata, led->params.offset, led->params.offset,
                              0, &val, 1);

	return err;
}

static int cpld_get_led(struct   cpld_data *cplddata,
			     int            index,
			     led_color_t    *led_color)
{
	struct led_config *led = NULL;
	u8 val;
	int err;

	led = &cplddata->cfg_led.led[index];

        err = bus_access_func(cplddata, led->params.offset, led->params.offset,
                              1, &val, 1);
        (*led_color) = (val & (~led->params.access_mask));
        if (led->params.access_mask == 0x0f)
                (*led_color) = (*led_color) >> 4;

	return err;
}

static int cpld_get_version(struct cpld_data *cplddata,
			     int          index,
			     char        *version)
{
	int err = 0;
	u8 val;

        err = bus_access_func(cplddata,
                              cplddata->cfg_info.info[index].version_offset,
                              cplddata->cfg_info.info[index].version_offset,
                              1, &val, 1);
        sprintf(version, "%d\n", val);


	return err;
}

static int cpld_get_name(struct cpld_data *cplddata,
			      int          index,
			      char        *name)
{
	int err = 0;

	strncpy(name, cplddata->cfg_led.led[index].entry.name,
		sizeof(cplddata->cfg_led.led[index].entry.name));

	return err;
}

static int cpld_set_name(struct cpld_data *cplddata,
			 int               index,
			 const char       *name)
{
	int err = 0;

	strncpy(cplddata->cfg_led.led[index].entry.name, name,
		sizeof(*name));

	return err;
}

static int psu_get_name(struct cpld_data *cplddata,
			int          index,
			char        *name)
{
	int err = 0;

	strncpy(name, cplddata->cfg_psu_module.module[index].entry.name,
		sizeof(cplddata->cfg_psu_module.module[index].entry.name));

	return err;
}

static int psu_set_name(struct cpld_data *cplddata,
			int               index,
			const char       *name)
{
	int err = 0;

	strncpy(cplddata->cfg_psu_module.module[index].entry.name, name,
		sizeof(*name));

	return err;
}

static int fan_get_name(struct cpld_data *cplddata,
			int          index,
			char        *name)
{
	int err = 0;

	strncpy(name, cplddata->cfg_fan_module.module[index].entry.name,
		sizeof(cplddata->cfg_fan_module.module[index].entry.name));

	return err;
}

static int fan_set_name(struct cpld_data *cplddata,
			int               index,
			const char       *name)
{
	int err = 0;

	strncpy(cplddata->cfg_fan_module.module[index].entry.name, name,
		sizeof(*name));

	return err;
}

static int info_get_name(struct cpld_data *cplddata,
			int          index,
			char        *name)
{
	int err = 0;

	strncpy(name, cplddata->cfg_info.info[index].entry.name,
		sizeof(cplddata->cfg_info.info[index].entry.name));

	return err;
}

static int info_set_name(struct cpld_data *cplddata,
			int               index,
			const char       *name)
{
	int err = 0;

	strncpy(cplddata->cfg_info.info[index].entry.name, name,
		sizeof(*name));

	return err;
}

static int cpld_get_capability(struct cpld_data *cplddata,
			       int               index,
			       char             *capability)
{
	int err = 0, i, off = 0;

	for (i = 0; i < cplddata->cfg_led.led[index].params.num_led_capability - 1; i++) {
		off += sprintf(capability + off, "%s, ",
			       cplddata->cfg_led.led[index].params.capability[i]);
	}
	off = sprintf(capability + off, "%s\n",
		      cplddata->cfg_led.led[index].params.capability[i]);

	return err;
}

static int power_cycle(struct cpld_data *cplddata)
{
        u8 mask = BIT_MASK(sys_pwr_cycle_bit);

        return bus_access_func(cplddata,
                               sys_pwr_cycle_offset,
                               sys_pwr_cycle_offset,
                               0, &mask, 0);
}

static int reset_platform(struct cpld_data *cplddata)
{
        u8 mask = BIT_MASK(platform_reset_bit);

        return bus_access_func(cplddata,
                               platform_reset_offset,
                               platform_reset_offset,
                               0, &mask, 0);
}

static int reset_pcie_slot(struct cpld_data *cplddata)
{
        u8 mask = BIT_MASK(pcie_slot_reset_bit);

        return bus_access_func(cplddata,
                               pcie_slot_reset_offset,
                               pcie_slot_reset_offset,
                               0, &mask, 0);
}

static int reset_switch_brd(struct cpld_data *cplddata)
{
        u8 mask = BIT_MASK(switch_brd_reset_bit);

        return bus_access_func(cplddata,
                               switch_brd_reset_offset,
                               switch_brd_reset_offset,
                               0, &mask, 0);
}

static int reset_asic(struct cpld_data *cplddata)
{
        u8 mask = BIT_MASK(asic_reset_bit);

        return bus_access_func(cplddata,
                               asic_reset_offset,
                               asic_reset_offset,
                               0, &mask, 0);
}

static char* reset_cause(struct cpld_data *cplddata)
{
        u8 cause = 0;
        int err;

        err = bus_access_func(cplddata, sys_reset_cause_offset,
                              sys_reset_cause_offset, 1, &cause, 0);

        return reset_cause_code_2string(cause);
}

static ssize_t show_led(struct device *dev,
			struct device_attribute *devattr,
			char *buf)
{
	struct cpld_data *cplddata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	led_color_t color;
	int err;

	switch (nr) {
	case led_color:
		color = led_color_string_2code(buf);
		err = cpld_get_led(cplddata, index, &color);
		break;
	case led_name:
		err = cpld_get_name(cplddata, index, buf);
		return strlen(buf);
	case led_cap:
		err = cpld_get_capability(cplddata, index, buf);
		return strlen(buf);
	default:
		return -EEXIST;
	}
	return sprintf(buf, "%s\n", led_color_mask_2string(color, cplddata->cfg_led.led[index].params.blue_flag));
}

static ssize_t store_led(struct device *dev,
			 struct device_attribute *devattr,
			 const char *buf, size_t count)
{
	struct cpld_data *cplddata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	int color_mask;
	int err;

	switch (nr) {
	case led_color:
		color_mask = led_color_string_2mask(buf);
		if (color_mask < 0)
			return color_mask;
		err = cpld_set_led(cplddata, index, color_mask);
		break;
	case led_name:
		err = cpld_set_name(cplddata, index, buf);
		break;
	default:
		return -EEXIST;
	}

	return count;
}

static int show_module(struct cpld_data     *cplddata,
		       struct module_params *params,
		       u8                   inv_flag,
		       u8                   *data)
{
	int res = 0;
	u8 mask = BIT_MASK(params->bit);

        res = bus_access_func(cplddata, params->offset, params->offset,
                              1, data, 0);

        if (inv_flag)
                *data = ~(*data);
        res = (*data & mask) >> params->bit;

	return res;
}

static int store_module(struct cpld_data     *cplddata,
		        struct module_params *params,
		        const  char           *buf)
{
	int res = 0;
	u8 data = *buf;

        res = bus_access_func(cplddata, params->offset, params->offset,
                              1, &data, 0) & 0xff;

        change_bit((unsigned long)params->bit, (volatile void *)&data);

        res = bus_access_func(cplddata, params->offset, params->offset,
                              0, &data, 0);

	return res;
}

static ssize_t show_module_psu(struct device *dev,
			       struct device_attribute *devattr,
			       char *buf)
{
	struct cpld_data *cplddata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	int err, res = 0;

	switch (nr) {
	case module_status:
                res = show_module(cplddata,
                		   &cplddata->cfg_psu_module.module[index].presence_status,
                                   1, buf);
		break;
	case module_event:
                res = show_module(cplddata,
                                  &cplddata->cfg_psu_module.module[index].presence_event,
                                  0, buf);
		break;
        case module_mask:
                res = show_module(cplddata,
                                  &cplddata->cfg_psu_module.module[index].presence_mask,
                                  0, buf);
		break;
        case module_pwr_off:
		break;
        case pg_status:
                res = show_module(cplddata,
                                  &cplddata->cfg_psu_module.module[index].power_status,
                                  0, buf);
		break;
        case pg_event:
                res = show_module(cplddata,
                                  &cplddata->cfg_psu_module.module[index].power_event,
                                  0, buf);
		break;
        case pg_mask:
                res = show_module(cplddata,
                                  &cplddata->cfg_psu_module.module[index].power_mask,
                                  0, buf);
		break;
        case alarm_status:
                res = show_module(cplddata,
                                  &cplddata->cfg_psu_module.module[index].alarm_status,
                                  0, buf);
		break;
        case alarm_event:
                res = show_module(cplddata,
                                  &cplddata->cfg_psu_module.module[index].alarm_event,
                                  0, buf);
		break;
        case alarm_mask:
                res = show_module(cplddata,
                                  &cplddata->cfg_psu_module.module[index].alarm_mask,
                                  0, buf);
		break;
        case module_name:
		err = psu_get_name(cplddata, index, buf);
		return strlen(buf);
		break;
	default:
		return -EEXIST;
	}

	return sprintf(buf, "%d\n", res);
}

static ssize_t store_module_psu(struct device *dev,
			        struct device_attribute *devattr,
			        const char *buf, size_t count)
{
	struct cpld_data *cplddata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	int err;

	switch (nr) {
	case module_status:
	case module_event:
		break;
        case module_mask:
                err = store_module(cplddata,
                                   &cplddata->cfg_psu_module.module[index].presence_mask,
                                   buf);
		break;
        case module_pwr_off:
                err = store_module(cplddata,
                                   &cplddata->cfg_psu_module.module[index].pwr_off,
                                   buf);
		break;
        case pg_status:
        case pg_event:
        case pg_mask:
        case alarm_status:
        case alarm_event:
        case alarm_mask:
		break;
        case module_name:
		err = psu_set_name(cplddata, index, buf);
		break;
	default:
		return -EEXIST;
	}

	return count;
}

static ssize_t show_module_fan(struct device *dev,
			       struct device_attribute *devattr,
			       char *buf)
{
	struct cpld_data *cplddata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	int err, res = 0;

	switch (nr) {
	case module_status:
                res = show_module(cplddata,
                                  &cplddata->cfg_fan_module.module[index].presence_status,
                                  1, buf);
		break;
	case module_event:
                res = show_module(cplddata,
                                  &cplddata->cfg_fan_module.module[index].presence_event,
                                  0, buf);
		break;
        case module_mask:
                res = show_module(cplddata,
                                  &cplddata->cfg_fan_module.module[index].presence_mask,
                                  0, buf);
		break;
        case module_pwr_off:
        case pg_status:
        case pg_event:
        case pg_mask:
        case alarm_status:
        case alarm_event:
        case alarm_mask:
		break;
        case module_name:
		err = fan_get_name(cplddata, index, buf);
		return strlen(buf);
		break;
	default:
		return -EEXIST;
	}

	return sprintf(buf, "%d\n", res);
}

static ssize_t store_module_fan(struct device *dev,
			        struct device_attribute *devattr,
			        const char *buf, size_t count)
{
	struct cpld_data *cplddata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	int err;

	switch (nr) {
	case module_status:
	case module_event:
		break;
        case module_mask:
		break;
        case module_pwr_off:
        case pg_status:
        case pg_event:
        case pg_mask:
        case alarm_status:
        case alarm_event:
        case alarm_mask:
		break;
        case module_name:
		err = fan_set_name(cplddata, index, buf);
		break;
	default:
		return -EEXIST;
	}

	return count;
}

static ssize_t show_info(struct device *dev,
			  struct device_attribute *devattr,
			  char *buf)
{
	struct cpld_data *cplddata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	int err, res = 0;

	switch (nr) {
	case cpld_version:
		err = cpld_get_version(cplddata, index, buf);
		return strlen(buf);
		break;
        case cpld_name:
		err = info_get_name(cplddata, index, buf);
		return strlen(buf);
	default:
		return -EEXIST;
	}

	return sprintf(buf, "%d\n", res);
}

static ssize_t store_info(struct device *dev,
			   struct device_attribute *devattr,
			   const char *buf, size_t count)
{
	struct cpld_data *cplddata = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	int err;

	switch (nr) {
	case cpld_version:
		break;
        case cpld_name:
		err = info_set_name(cplddata, index, buf);
		break;
	default:
		return -EEXIST;
	}

	return count;
}

static ssize_t show_reset(struct device *dev,
			  struct device_attribute *devattr,
			  char *buf)
{
	struct cpld_data *cplddata = i2c_get_clientdata(to_i2c_client(dev));
        int nr = to_sensor_dev_attr_2(devattr)->nr;

	switch (nr) {
	case sys_reset_cause:
		return sprintf(buf, "%s\n", reset_cause(cplddata));
	default:
		return -EEXIST;
	}
}

static ssize_t store_reset(struct device *dev,
			   struct device_attribute *devattr,
			   const char *buf, size_t count)
{
	struct cpld_data *cplddata = i2c_get_clientdata(to_i2c_client(dev));
        int nr = to_sensor_dev_attr_2(devattr)->nr;

	switch (nr) {
	case sys_pwr_cycle:
		power_cycle(cplddata);
		break;
        case sys_platform:
		reset_platform(cplddata);
		break;
        case sys_pcie_slot:
		reset_pcie_slot(cplddata);
		break;
        case sys_switch_brd:
		reset_switch_brd(cplddata);
		break;
        case sys_asic:
		reset_asic(cplddata);
		break;
	default:
		return -EEXIST;
	}

	return count;
}

#define SENSOR_DEVICE_ATTR_LED(id)                             \
static SENSOR_DEVICE_ATTR_2(led##id, S_IRUGO | S_IWUSR,        \
        show_led, store_led, led_color, id - 1);               \
static SENSOR_DEVICE_ATTR_2(led##id##_name, S_IRUGO | S_IWUSR, \
        show_led, store_led, led_name, id - 1);                \
static SENSOR_DEVICE_ATTR_2(led##id##_capability, S_IRUGO,     \
        show_led, NULL, led_cap, id - 1);

SENSOR_DEVICE_ATTR_LED(1);
SENSOR_DEVICE_ATTR_LED(2);
SENSOR_DEVICE_ATTR_LED(3);
SENSOR_DEVICE_ATTR_LED(4);
SENSOR_DEVICE_ATTR_LED(5);
SENSOR_DEVICE_ATTR_LED(6);

#define SENSOR_DEVICE_ATTR_PSU_MODULE(id)                              \
static SENSOR_DEVICE_ATTR_2(psu##id##_status, S_IRUGO,                 \
        show_module_psu, NULL, module_status, id - 1);                 \
static SENSOR_DEVICE_ATTR_2(psu##id##_event, S_IRUGO | S_IWUSR,        \
        show_module_psu, store_module_psu, module_event, id - 1);      \
static SENSOR_DEVICE_ATTR_2(psu##id##_mask, S_IRUGO | S_IWUSR,         \
        show_module_psu, store_module_psu, module_mask, id - 1);       \
static SENSOR_DEVICE_ATTR_2(psu##id##_pg_status, S_IRUGO,              \
        show_module_psu, NULL, pg_status, id - 1);                     \
static SENSOR_DEVICE_ATTR_2(psu##id##_pg_event, S_IRUGO | S_IWUSR,     \
        show_module_psu, store_module_psu, pg_event, id - 1);          \
static SENSOR_DEVICE_ATTR_2(psu##id##_pg_mask, S_IRUGO | S_IWUSR,      \
        show_module_psu, store_module_psu, pg_mask, id - 1);           \
static SENSOR_DEVICE_ATTR_2(psu##id##_alarm_status, S_IRUGO,           \
        show_module_psu, NULL, alarm_status, id - 1);                  \
static SENSOR_DEVICE_ATTR_2(psu##id##_alarm_event, S_IRUGO | S_IWUSR,  \
        show_module_psu, store_module_psu, alarm_event, id - 1);       \
static SENSOR_DEVICE_ATTR_2(psu##id##_alarm_mask, S_IRUGO | S_IWUSR,   \
        show_module_psu, store_module_psu, alarm_mask, id - 1);        \
static SENSOR_DEVICE_ATTR_2(psu##id##_name, S_IRUGO | S_IWUSR,         \
        show_module_psu, store_module_psu, module_name, id - 1);       \
static SENSOR_DEVICE_ATTR_2(psu##id##_pwr_off, S_IWUSR,                \
        NULL, store_module_psu, module_pwr_off, id - 1);

SENSOR_DEVICE_ATTR_PSU_MODULE(1);
SENSOR_DEVICE_ATTR_PSU_MODULE(2);

#define SENSOR_DEVICE_ATTR_FAN_MODULE(id)                         \
static SENSOR_DEVICE_ATTR_2(fan##id##_status, S_IRUGO,            \
        show_module_fan, NULL, module_status, id - 1);            \
static SENSOR_DEVICE_ATTR_2(fan##id##_event, S_IRUGO | S_IWUSR,   \
        show_module_fan, store_module_fan, module_event, id - 1); \
static SENSOR_DEVICE_ATTR_2(fan##id##_mask, S_IRUGO | S_IWUSR,    \
        show_module_fan, store_module_fan, module_mask, id - 1);  \
static SENSOR_DEVICE_ATTR_2(fan##id##_name, S_IRUGO | S_IWUSR,    \
        show_module_fan, store_module_fan, module_name, id - 1);

SENSOR_DEVICE_ATTR_FAN_MODULE(1);
SENSOR_DEVICE_ATTR_FAN_MODULE(2);
SENSOR_DEVICE_ATTR_FAN_MODULE(3);
SENSOR_DEVICE_ATTR_FAN_MODULE(4);

#define SENSOR_DEVICE_ATTR_INFO(id)                             \
static SENSOR_DEVICE_ATTR_2(cpld##id##_version, S_IRUGO,        \
        show_info, NULL, cpld_version, id - 1);                 \
static SENSOR_DEVICE_ATTR_2(cpld##id##_name, S_IRUGO | S_IWUSR, \
        show_info, store_info, cpld_name, id - 1);

SENSOR_DEVICE_ATTR_INFO(1);
SENSOR_DEVICE_ATTR_INFO(2);
SENSOR_DEVICE_ATTR_INFO(3);

#define SENSOR_DEVICE_ATTR_RESET(id)                     \
static SENSOR_DEVICE_ATTR_2(reset_cause##id, S_IRUGO,    \
        show_reset, NULL, sys_reset_cause, id - 1);      \
static SENSOR_DEVICE_ATTR_2(sys_pwr_cycle##id, S_IWUSR,  \
        NULL, store_reset, sys_pwr_cycle, id - 1);       \
static SENSOR_DEVICE_ATTR_2(sys_platform##id, S_IWUSR,   \
        NULL, store_reset, sys_platform, id - 1);        \
static SENSOR_DEVICE_ATTR_2(sys_pcie_slot##id, S_IWUSR,  \
        NULL, store_reset, sys_pcie_slot, id - 1);       \
static SENSOR_DEVICE_ATTR_2(sys_switch_brd##id, S_IWUSR, \
        NULL, store_reset, sys_switch_brd, id - 1);      \
static SENSOR_DEVICE_ATTR_2(sys_asic##id, S_IWUSR,       \
        NULL, store_reset, sys_asic, id - 1);

SENSOR_DEVICE_ATTR_RESET(1);

static struct attribute *mlnx_cpld_attributes[] = {
        &sensor_dev_attr_led1.dev_attr.attr,
        &sensor_dev_attr_led1_name.dev_attr.attr,
        &sensor_dev_attr_led1_capability.dev_attr.attr,
        &sensor_dev_attr_led2.dev_attr.attr,
        &sensor_dev_attr_led2_name.dev_attr.attr,
        &sensor_dev_attr_led2_capability.dev_attr.attr,
        &sensor_dev_attr_led3.dev_attr.attr,
        &sensor_dev_attr_led3_name.dev_attr.attr,
        &sensor_dev_attr_led3_capability.dev_attr.attr,
        &sensor_dev_attr_led4.dev_attr.attr,
        &sensor_dev_attr_led4_name.dev_attr.attr,
        &sensor_dev_attr_led4_capability.dev_attr.attr,
        &sensor_dev_attr_led5.dev_attr.attr,
        &sensor_dev_attr_led5_name.dev_attr.attr,
        &sensor_dev_attr_led5_capability.dev_attr.attr,
        &sensor_dev_attr_led6.dev_attr.attr,
        &sensor_dev_attr_led6_name.dev_attr.attr,
        &sensor_dev_attr_led6_capability.dev_attr.attr,
        &sensor_dev_attr_fan1_status.dev_attr.attr,
        &sensor_dev_attr_fan1_event.dev_attr.attr,
        &sensor_dev_attr_fan1_mask.dev_attr.attr,
        &sensor_dev_attr_fan1_name.dev_attr.attr,
        &sensor_dev_attr_fan2_status.dev_attr.attr,
        &sensor_dev_attr_fan2_event.dev_attr.attr,
        &sensor_dev_attr_fan2_mask.dev_attr.attr,
        &sensor_dev_attr_fan2_name.dev_attr.attr,
        &sensor_dev_attr_fan3_status.dev_attr.attr,
        &sensor_dev_attr_fan3_event.dev_attr.attr,
        &sensor_dev_attr_fan3_mask.dev_attr.attr,
        &sensor_dev_attr_fan3_name.dev_attr.attr,
        &sensor_dev_attr_fan4_status.dev_attr.attr,
        &sensor_dev_attr_fan4_event.dev_attr.attr,
        &sensor_dev_attr_fan4_mask.dev_attr.attr,
        &sensor_dev_attr_fan4_name.dev_attr.attr,
        &sensor_dev_attr_psu1_status.dev_attr.attr,
        &sensor_dev_attr_psu1_event.dev_attr.attr,
        &sensor_dev_attr_psu1_mask.dev_attr.attr,
        &sensor_dev_attr_psu1_pg_status.dev_attr.attr,
        &sensor_dev_attr_psu1_pg_event.dev_attr.attr,
        &sensor_dev_attr_psu1_pg_mask.dev_attr.attr,
        &sensor_dev_attr_psu1_alarm_status.dev_attr.attr,
        &sensor_dev_attr_psu1_alarm_event.dev_attr.attr,
        &sensor_dev_attr_psu1_alarm_mask.dev_attr.attr,
        &sensor_dev_attr_psu1_pwr_off.dev_attr.attr,
        &sensor_dev_attr_psu1_name.dev_attr.attr,
        &sensor_dev_attr_psu2_status.dev_attr.attr,
        &sensor_dev_attr_psu2_event.dev_attr.attr,
        &sensor_dev_attr_psu2_mask.dev_attr.attr,
        &sensor_dev_attr_psu2_pwr_off.dev_attr.attr,
        &sensor_dev_attr_psu2_name.dev_attr.attr,
        &sensor_dev_attr_psu2_pg_status.dev_attr.attr,
        &sensor_dev_attr_psu2_pg_event.dev_attr.attr,
        &sensor_dev_attr_psu2_pg_mask.dev_attr.attr,
        &sensor_dev_attr_psu2_alarm_status.dev_attr.attr,
        &sensor_dev_attr_psu2_alarm_event.dev_attr.attr,
        &sensor_dev_attr_psu2_alarm_mask.dev_attr.attr,
        &sensor_dev_attr_cpld1_version.dev_attr.attr,
        &sensor_dev_attr_cpld1_name.dev_attr.attr,
        &sensor_dev_attr_cpld2_version.dev_attr.attr,
        &sensor_dev_attr_cpld2_name.dev_attr.attr,
        &sensor_dev_attr_cpld3_version.dev_attr.attr,
        &sensor_dev_attr_cpld3_name.dev_attr.attr,
        &sensor_dev_attr_reset_cause1.dev_attr.attr,
        &sensor_dev_attr_sys_pwr_cycle1.dev_attr.attr,
        &sensor_dev_attr_sys_platform1.dev_attr.attr,
        &sensor_dev_attr_sys_pcie_slot1.dev_attr.attr,
        &sensor_dev_attr_sys_switch_brd1.dev_attr.attr,
        &sensor_dev_attr_sys_asic1.dev_attr.attr,
        NULL
};

static struct attribute *mlnx_cpld_msn2100_attributes[] = {
        &sensor_dev_attr_led1.dev_attr.attr,
        &sensor_dev_attr_led1_name.dev_attr.attr,
        &sensor_dev_attr_led1_capability.dev_attr.attr,
        &sensor_dev_attr_led2.dev_attr.attr,
        &sensor_dev_attr_led2_name.dev_attr.attr,
        &sensor_dev_attr_led2_capability.dev_attr.attr,
        &sensor_dev_attr_led3.dev_attr.attr,
        &sensor_dev_attr_led3_name.dev_attr.attr,
        &sensor_dev_attr_led3_capability.dev_attr.attr,
        &sensor_dev_attr_led4.dev_attr.attr,
        &sensor_dev_attr_led4_name.dev_attr.attr,
        &sensor_dev_attr_led4_capability.dev_attr.attr,
        &sensor_dev_attr_led5.dev_attr.attr,
        &sensor_dev_attr_led5_name.dev_attr.attr,
        &sensor_dev_attr_led5_capability.dev_attr.attr,
        &sensor_dev_attr_psu1_name.dev_attr.attr,
        &sensor_dev_attr_psu1_pg_status.dev_attr.attr,
        &sensor_dev_attr_psu1_pg_event.dev_attr.attr,
        &sensor_dev_attr_psu1_pg_mask.dev_attr.attr,
        &sensor_dev_attr_psu1_alarm_status.dev_attr.attr,
        &sensor_dev_attr_psu1_alarm_event.dev_attr.attr,
        &sensor_dev_attr_psu1_alarm_mask.dev_attr.attr,
        &sensor_dev_attr_psu2_name.dev_attr.attr,
        &sensor_dev_attr_psu2_pg_status.dev_attr.attr,
        &sensor_dev_attr_psu2_pg_event.dev_attr.attr,
        &sensor_dev_attr_psu2_pg_mask.dev_attr.attr,
        &sensor_dev_attr_psu2_alarm_status.dev_attr.attr,
        &sensor_dev_attr_psu2_alarm_event.dev_attr.attr,
        &sensor_dev_attr_psu2_alarm_mask.dev_attr.attr,
        &sensor_dev_attr_cpld1_version.dev_attr.attr,
        &sensor_dev_attr_cpld1_name.dev_attr.attr,
        &sensor_dev_attr_cpld2_version.dev_attr.attr,
        &sensor_dev_attr_cpld2_name.dev_attr.attr,
        &sensor_dev_attr_reset_cause1.dev_attr.attr,
        &sensor_dev_attr_sys_pwr_cycle1.dev_attr.attr,
        &sensor_dev_attr_sys_platform1.dev_attr.attr,
        &sensor_dev_attr_sys_pcie_slot1.dev_attr.attr,
        &sensor_dev_attr_sys_switch_brd1.dev_attr.attr,
        &sensor_dev_attr_sys_asic1.dev_attr.attr,
        NULL
};

static const struct attribute_group mlnx_cpld_group[] = {
        {.attrs = mlnx_cpld_attributes},
        {.attrs = mlnx_cpld_msn2100_attributes},
        {.attrs = mlnx_cpld_attributes},
};

#define CPLD_CREATE(id) \
	err = device_create_file(cpld_db.cpld_hwmon_dev, &sensor_dev_attr_##id.dev_attr); \
	if (err) \
		goto fail_create_file;

#define CPLD_REMOVE(id) \
	device_remove_file(cpld_db.cpld_hwmon_dev, &sensor_dev_attr_##id.dev_attr);

static inline void led_config_clean(struct cpld_data *cplddata)
{
	int ind;

	for (ind = 0; ind < cplddata->cfg_led.num_led; ind++) {
		switch (ind) {
		case 0:
			CPLD_REMOVE(led1);
			CPLD_REMOVE(led1_name);
			break;
        	case 1:
			CPLD_REMOVE(led2);
			CPLD_REMOVE(led2_name);
			break;
        	case 2:
			CPLD_REMOVE(led3);
			CPLD_REMOVE(led3_name);
			break;
        	case 3:
			CPLD_REMOVE(led4);
			CPLD_REMOVE(led4_name);
			break;
        	case 4:
			CPLD_REMOVE(led5);
			CPLD_REMOVE(led5_name);
			break;
        	case 5:
			CPLD_REMOVE(led6);
			CPLD_REMOVE(led6_name);
			break;
		default:
			break;
		}
	}
}

static int led_config(struct cpld_data *cplddata)
{
	int id, i;
	int err = 0;

	cplddata->cfg_led.num_led = num_led;

	switch (def_led_alarm_color) {
	case led_nocolor:
		cplddata->cfg_led.led_alarm_mask = LED_IS_OFF;
		break;
	case led_yellow:
		cplddata->cfg_led.led_alarm_mask = LED_YELLOW_STATIC_ON;
		break;
	case led_yellow_blink:
		cplddata->cfg_led.led_alarm_mask = LED_YELLOW_BLINK_3HZ;
		break;
	case led_green:
		cplddata->cfg_led.led_alarm_mask = LED_GREEN_STATIC_ON;
		break;
	case led_green_blink:
		cplddata->cfg_led.led_alarm_mask = LED_GREEN_BLINK_3HZ;
		break;
	case led_red:
		cplddata->cfg_led.led_alarm_mask = LED_RED_STATIC_ON;
		break;
	case led_red_blink:
		cplddata->cfg_led.led_alarm_mask = LED_RED_BLINK_3HZ;
		break;
	case led_yellow_blink_fast:
		cplddata->cfg_led.led_alarm_mask = LED_YELLOW_BLINK_6HZ;
		break;
	case led_green_blink_fast:
		cplddata->cfg_led.led_alarm_mask = LED_GREEN_BLINK_6HZ;
		break;
	case led_red_blink_fast:
		cplddata->cfg_led.led_alarm_mask = LED_RED_BLINK_6HZ;
		break;
	case led_cpld_ctrl:
		cplddata->cfg_led.led_alarm_mask = LED_CNTRL_BY_CPLD;
		break;
	case led_blue:
	default:
		cplddata->cfg_led.led_alarm_mask = LED_IS_OFF;
		break;
	}

	for (id = 0; id < cplddata->cfg_led.num_led; id++) {
                memset(&cplddata->cfg_led.led[id], 0, sizeof(struct led_config));
                cplddata->cfg_led.led[id].entry.index = id + 1;
                cplddata->cfg_led.led[id].params.offset = leds_profile.profile[id].offset;
                cplddata->cfg_led.led[id].params.access_mask = leds_profile.profile[id].mask;

		cplddata->cfg_led.led[id].params.num_led_capability =
					leds_profile.profile[id].num_capabilities;
		cplddata->cfg_led.led[id].params.blue_flag = leds_profile.profile[id].blue_flag;
                for (i = 0; i < cplddata->cfg_led.led[id].params.num_led_capability; i++) {
                        cplddata->cfg_led.led[id].params.capability[i] = leds_profile.profile[id].capability[i];
                }

                if (cplddata->cfg_led.led[id].entry.index == (leds_profile.status_led_offset + 1)) {
                	sprintf(cplddata->cfg_led.led[id].entry.name, "%s\n", "status");
                }
                else if (cplddata->cfg_led.led[id].entry.index == leds_profile.uid_led_offset + 1) {
                	sprintf(cplddata->cfg_led.led[id].entry.name, "%s\n", "uid");
                }
                else if (cplddata->cfg_led.led[id].entry.index == leds_profile.bp_led_offset + 1) {
					sprintf(cplddata->cfg_led.led[id].entry.name, "%s\n", "bad_port");
		}
                else if (cplddata->cfg_led.led[id].entry.index > leds_profile.psu_led_offset) {
                	sprintf(cplddata->cfg_led.led[id].entry.name, "%s%d\n", "psu",
                	cplddata->cfg_led.led[id].entry.index - leds_profile.psu_led_offset);
                }
                else if (cplddata->cfg_led.led[id].entry.index > leds_profile.fan_led_offset) {
                	sprintf(cplddata->cfg_led.led[id].entry.name, "%s%d\n", "fan",
                	cplddata->cfg_led.led[id].entry.index - leds_profile.fan_led_offset);
                }

	        switch (id) {
	        case 0:
	        	CPLD_CREATE(led1);
	        	CPLD_CREATE(led1_name);
	        	break;
	        case 1:
	        	CPLD_CREATE(led2);
	        	CPLD_CREATE(led2_name);
	        	break;
	        case 2:
	        	CPLD_CREATE(led3);
	        	CPLD_CREATE(led3_name);
	        	break;
	        case 3:
	        	CPLD_CREATE(led4);
	        	CPLD_CREATE(led4_name);
	        	break;
	        case 4:
	        	CPLD_CREATE(led5);
	        	CPLD_CREATE(led5_name);
	        	break;
	        case 5:
	        	CPLD_CREATE(led6);
			CPLD_CREATE(led6_name);
	        	break;
	        default:
	        	break;
	        }
	}
	return err;

fail_create_file:
	led_config_clean(cplddata);

	return err;
}

static inline void module_psu_config_clean(struct cpld_data *cplddata)
{
}

static int module_psu_config(struct cpld_data *cplddata)
{
	int id;
	int err = 0;

	cplddata->cfg_psu_module.num_psu_modules = num_psu_modules;
	cplddata->cfg_psu_module.num_fixed_psu_modules = num_fixed_psu_modules;

	if (num_fixed_psu_modules) {
		for (id = 0; id < num_fixed_psu_modules; id++) {
                	cplddata->cfg_psu_module.module[id].presence_status.offset = psu_module_presence_status_offset[id];
                	cplddata->cfg_psu_module.module[id].presence_status.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].presence_event.offset = psu_module_presence_event_offset[id];
                	cplddata->cfg_psu_module.module[id].presence_event.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].presence_mask.offset = psu_module_presence_mask_offset[id];
                	cplddata->cfg_psu_module.module[id].presence_mask.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].power_status.offset = psu_module_power_status_offset[id];
                	cplddata->cfg_psu_module.module[id].power_status.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].power_event.offset = psu_module_power_event_offset[id];
                	cplddata->cfg_psu_module.module[id].power_event.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].power_mask.offset = psu_module_power_mask_offset[id];
                	cplddata->cfg_psu_module.module[id].alarm_status.offset = psu_module_alarm_status_offset[id];
                	cplddata->cfg_psu_module.module[id].power_mask.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].alarm_status.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].alarm_event.offset = psu_module_alarm_event_offset[id];
                	cplddata->cfg_psu_module.module[id].alarm_event.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].alarm_mask.offset = psu_module_alarm_mask_offset[id];
                	cplddata->cfg_psu_module.module[id].alarm_mask.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].pwr_off.offset = psu_module_pwr_off_offset[id];
                	cplddata->cfg_psu_module.module[id].pwr_off.bit = psu_module_pwr_off_bit[id];
			sprintf(cplddata->cfg_psu_module.module[id].entry.name, "%s%d\n", "psu", id + 1);

	        	switch (id) {
	        	case 0:
	        		CPLD_CREATE(psu1_status);
	        		CPLD_CREATE(psu1_event);
	        		CPLD_CREATE(psu1_mask);
				CPLD_CREATE(psu1_name);
	        		break;
	        	case 1:
	        		CPLD_CREATE(psu2_status);
	        		CPLD_CREATE(psu2_event);
	        		CPLD_CREATE(psu2_mask);
				CPLD_CREATE(psu2_name);
	        		break;
	        	default:
	        		goto fail_create_file;
	        	}
		}
	} else {
		for (id = 0; id < num_psu_modules; id++) {
                	cplddata->cfg_psu_module.module[id].presence_status.offset = psu_module_presence_status_offset[id];
                	cplddata->cfg_psu_module.module[id].presence_status.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].presence_event.offset = psu_module_presence_event_offset[id];
                	cplddata->cfg_psu_module.module[id].presence_event.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].presence_mask.offset = psu_module_presence_mask_offset[id];
                	cplddata->cfg_psu_module.module[id].presence_mask.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].power_status.offset = psu_module_power_status_offset[id];
                	cplddata->cfg_psu_module.module[id].power_status.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].power_event.offset = psu_module_power_event_offset[id];
                	cplddata->cfg_psu_module.module[id].power_event.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].power_mask.offset = psu_module_power_mask_offset[id];
                	cplddata->cfg_psu_module.module[id].alarm_status.offset = psu_module_alarm_status_offset[id];
                	cplddata->cfg_psu_module.module[id].power_mask.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].alarm_status.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].alarm_event.offset = psu_module_alarm_event_offset[id];
                	cplddata->cfg_psu_module.module[id].alarm_event.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].alarm_mask.offset = psu_module_alarm_mask_offset[id];
                	cplddata->cfg_psu_module.module[id].alarm_mask.bit = psu_module_bit[id];
                	cplddata->cfg_psu_module.module[id].topology.mux = psu_module_mux[id];
                	cplddata->cfg_psu_module.module[id].topology.addr = psu_module_addr[id];
                	cplddata->cfg_psu_module.module[id].pwr_off.offset = psu_module_pwr_off_offset[id];
                	cplddata->cfg_psu_module.module[id].pwr_off.bit = psu_module_pwr_off_bit[id];
			sprintf(cplddata->cfg_psu_module.module[id].entry.name, "%s%d\n", "psu", id + 1);

	        	switch (id) {
	        	case 0:
	        		CPLD_CREATE(psu1_status);
	        		CPLD_CREATE(psu1_event);
	        		CPLD_CREATE(psu1_mask);
				CPLD_CREATE(psu1_name);
	        		break;
	        	case 1:
	        		CPLD_CREATE(psu2_status);
	        		CPLD_CREATE(psu2_event);
	        		CPLD_CREATE(psu2_mask);
				CPLD_CREATE(psu2_name);
	        		break;
	        	default:
	        		goto fail_create_file;
	        	}
		}
	}

	return err;

fail_create_file:
	module_psu_config_clean(cplddata);

	return err;
}

static inline void module_fan_config_clean(struct cpld_data *cplddata)
{
}

static int module_fan_config(struct cpld_data *cplddata)
{
	int id;
	int err = 0;

	cplddata->cfg_fan_module.num_fan_modules = num_fan_modules;
	for (id = 0; id < num_fan_modules; id++) {
                cplddata->cfg_fan_module.module[id].presence_status.offset = fan_module_presence_status_offset[id];
                cplddata->cfg_fan_module.module[id].presence_status.bit = fan_module_bit[id];
                cplddata->cfg_fan_module.module[id].presence_event.offset = fan_module_presence_event_offset[id];
                cplddata->cfg_fan_module.module[id].presence_event.bit = fan_module_bit[id];
                cplddata->cfg_fan_module.module[id].presence_mask.offset = fan_module_presence_mask_offset[id];
                cplddata->cfg_fan_module.module[id].presence_mask.bit = fan_module_bit[id];
		sprintf(cplddata->cfg_fan_module.module[id].entry.name, "%s%d\n", "fan", id + 1);

	        switch (id) {
	        case 0:
	        	CPLD_CREATE(fan1_status);
	        	CPLD_CREATE(fan1_event);
	        	CPLD_CREATE(fan1_mask);
			CPLD_CREATE(fan1_name);
	        	break;
	        case 1:
	        	CPLD_CREATE(fan2_status);
	        	CPLD_CREATE(fan2_event);
	        	CPLD_CREATE(fan2_mask);
			CPLD_CREATE(fan2_name);
	        	break;
	        case 2:
	        	CPLD_CREATE(fan3_status);
	        	CPLD_CREATE(fan3_event);
	        	CPLD_CREATE(fan3_mask);
			CPLD_CREATE(fan3_name);
	        	break;
	        case 3:
	        	CPLD_CREATE(fan4_status);
	        	CPLD_CREATE(fan4_event);
	        	CPLD_CREATE(fan4_mask);
			CPLD_CREATE(fan4_name);
	        	break;
	        default:
	        	goto fail_create_file;
	        }
	}

	return err;

fail_create_file:
	module_fan_config_clean(cplddata);

	return err;
}

static inline void info_config_clean(struct cpld_data *cplddata)
{
}

static int info_config(struct cpld_data *cplddata)
{
	int id;
	int err = 0;

	cplddata->cfg_info.num_cpld = num_cpld;
	for (id = 0; id < num_cpld; id++) {
		cplddata->cfg_info.info[id].version_offset = version_offset[id];
                sprintf(cplddata->cfg_info.info[id].entry.name, "%s%d\n", "cpld", id + 1);

	        switch (id) {
	        case 0:
	        	CPLD_CREATE(cpld1_version);
			CPLD_CREATE(cpld1_name);
	        	break;
	        case 1:
	        	CPLD_CREATE(cpld2_version);
			CPLD_CREATE(cpld2_name);
	        	break;
	        case 2:
	        	CPLD_CREATE(cpld3_version);
			CPLD_CREATE(cpld3_name);
	        	break;
	        default:
	        	goto fail_create_file;
	        }
	}

	return err;

fail_create_file:
	info_config_clean(cplddata);

	return err;
}


static inline void reset_config_clean(struct cpld_data *cplddata)
{
}

static int reset_config(struct cpld_data *cplddata)
{
	int id;
	int err = 0;

	cplddata->cfg_reset.num_reset = num_reset;
	for (id = 0; id < num_reset; id++) {

	        switch (id) {
	        case 0:
	        default:
	        	goto fail_create_file;
	        }
	}

	return err;

fail_create_file:
	reset_config_clean(cplddata);

	return err;
}

static int topology_config_clean(struct cpld_data *cplddata)
{
	int err = 0;

	return err;
}

static int topology_config(struct cpld_data *cplddata)
{
	int id;
	int err = 0;

	for (id = 0; id < num_wp_regs; id++) {
		cplddata->wp_reg_offset[id].offset = wp_reg_offset[id];
	}

	for (id = 0; id < num_init_regs; id++) {
		cplddata->init_reg_offset[id].offset = init_reg_offset[id];
		cplddata->init_reg_offset[id].bit = init_reg_mask[id];
	}

	cplddata->top_aggregation_status.offset = top_aggregation_status_offset;
	cplddata->top_aggregation_mask.offset = top_aggregation_mask_offset;
	cplddata->top_aggregation_mask.bit = top_aggregation_mask;

	for (id = 0; id < cplddata->cfg_fan_module.num_fan_modules; id++) {
		cplddata->cfg_fan_module.module[id].eeprom_topology.mux = fan_eeprom_mux[id];
		cplddata->cfg_fan_module.module[id].eeprom_topology.addr = fan_eeprom_addr[id];
	}

	for (id = 0; id < cplddata->cfg_psu_module.num_psu_modules; id++) {
		cplddata->cfg_psu_module.module[id].eeprom_topology.mux = psu_mux[id];
		cplddata->cfg_psu_module.module[id].eeprom_topology.addr = psu_eeprom_addr[id];
		cplddata->cfg_psu_module.module[id].topology.mux = psu_mux[id];
		cplddata->cfg_psu_module.module[id].topology.addr = psu_control_addr[id];
	}

	return err;
}

static void cpld_reschedule_work(struct cpld_data *dev, unsigned long delay)
{
	/* If work is already scheduled then subsequent schedules will not
	   change the scheduled time that's why it should be canceled first.
	*/
	cancel_delayed_work(&dev->dwork);
	schedule_delayed_work(&dev->dwork, delay);
}

static void cpld_work_handler(struct work_struct *work)
{
	unsigned long flags;
	struct cpld_data *dev = container_of(work, struct cpld_data, dwork.work);
	unsigned long delay;
	u8  unmask_psu = 0x3,  unmask_fan = 0xf;

	if (mask_read(dev, unmask_psu, unmask_fan) == 0)
		clear_unmask(dev, unmask_psu, unmask_fan);

	spin_lock_irqsave(&dev->lock, flags);
	if (dev->int_disable_counter > 0) {
		dev->int_disable_counter--;
		enable_irq(dev->irq);
	}

	//if (resched_on_exit) {
		delay = msecs_to_jiffies(THREAD_IRQ_SLEEP_MSECS);
		delay = round_jiffies_relative(delay);
		cpld_reschedule_work(dev, 0);
	//}

	spin_unlock_irqrestore(&dev->lock, flags);

	return;
}

static irqreturn_t cpld_irq_handler(int irq, void *dev_ptr)
{
	struct cpld_data *dev = (struct cpld_data *)dev_ptr;
	unsigned long flags;

	disable_irq_nosync(dev->irq);
	spin_lock_irqsave(&dev->lock, flags);
	dev->int_disable_counter++;

	cpld_reschedule_work(dev, 0);

	spin_unlock_irqrestore(&dev->lock, flags);

	return IRQ_HANDLED;
}

static const unsigned short normal_i2c[] = { 0x60, I2C_CLIENT_END };
static int cpld_probe(struct i2c_client *client, const struct i2c_device_id *devid)
{
        struct cpld_data *data;
        u8 buf, psu_presence_power_status = 1, fan_presence_status = 0;
	struct i2c_board_info board_info;
	int id, err = 0;

	data = kzalloc(sizeof(struct cpld_data), GFP_KERNEL);
	if (!data) {
		err = -ENOMEM;
		goto exit;
	}
	i2c_set_clientdata(client, data);

    /* Register sysfs hooks */
	err = sysfs_create_group(&client->dev.kobj, &mlnx_cpld_group[cpld_db.mlnx_system_type]);
	if (err)
		goto fail_create_group;

    /* Create MUX topolgy */
	memcpy(&data->exec_tab, &exec_table_profile[exec_id], sizeof(struct exec_table));

	INIT_DELAYED_WORK(&data->dwork, cpld_work_handler);
	init_waitqueue_head(&data->poll_wait);
	data->int_occurred = 0;
	data->resched_on_exit = 1;
	data->irq = irq_line;
	spin_lock_init(&data->lock);
	if (irq_line) {
		err = request_irq(data->irq, cpld_irq_handler, IRQF_SHARED,
				  "chassis", data);
		if (err) {
			printk(KERN_INFO "Error on request_irq %d\n", irq_line);
			err = -EINVAL;
			goto fail_request_irq;
		}
	}

	mutex_init(&data->access_lock);
	INIT_LIST_HEAD(&data->list);
	list_add(&data->list, &cpld_db.list);
	kref_init(&data->kref);

	data->base = cpld_lpc_base;
	data->size = cpld_lpc_size;


        data->hwmon_dev = hwmon_device_register(&client->dev);
        if (!data->hwmon_dev) {
                err = -ENODEV;
                goto fail_register_hwmon_device;
        }
        printk(KERN_INFO "Registred mlnx_cpld_contol driver at bus=%d addr=%x\n",
              client->adapter->nr, client->addr);

        err = led_config(data);
        err = (err == 0) ? module_fan_config(data) : err;
        err = (err == 0) ? module_psu_config(data) : err;
        err = (err == 0) ? info_config(data) : err;
        err = (err == 0) ? reset_config(data) : err;
        err = (err == 0) ? topology_config(data) : err;
        if (err)
                goto fail_register_hwmon_device;

        /* Remove protection for protected registers */
	buf = 0;
	for (id = 0; id < num_wp_regs; id++) {
        	bus_access_func(data,
                        	data->wp_reg_offset[id].offset,
                        	data->wp_reg_offset[id].offset,
                        	0, &buf, 1);
	}

        /* Set initializaton registers */
	for (id = 0; id < num_init_regs; id++) {
        	bus_access_func(data,
                        	data->init_reg_offset[id].offset,
                        	data->init_reg_offset[id].offset,
                        	0, &data->init_reg_offset[id].bit, 1);
	}

        /* Connect drivers for FAN, which are present.
           Set LED for FAN according to presence bit.
           Set FAN to default speed.
        */
	for (id = 0; id < data->cfg_fan_module.num_fan_modules; id++) {
		data->cfg_fan_module.module[id].presence_status_cache = 0;
        	bus_access_func(data,
                        	data->cfg_fan_module.module[id].presence_status.offset,
                        	data->cfg_fan_module.module[id].presence_status.offset,
                        	1, &data->cfg_fan_module.module[id].presence_status_cache, 1);
        	data->cfg_fan_module.module[id].presence_status_cache = (~data->cfg_fan_module.module[id].presence_status_cache & 0xff);
        	data->cfg_fan_module.module[id].presence_status_cache &=
        	        	(1 << data->cfg_fan_module.module[id].presence_mask.bit);

        	if (data->cfg_fan_module.module[id].presence_status_cache) {
			fan_presence_status++;
                        /* Set LED for FAN according to presence bit */
                        err = data->exec_tab.fan_init_entry(data, id, 1, 0, no_event);
                        SET_FAN(1, id, default_fan_speed, err);
                        data->cfg_led.led[leds_profile.fan_led_offset + id].led_cache = led_green;

			/* Connect FAN EEPROM drivers */
			if (!(data->cfg_fan_module.module[id].eeprom_adapter =
			      i2c_get_adapter(data->cfg_fan_module.module[id].eeprom_topology.mux))) {
				printk(KERN_INFO "%s: failed to get adapter for mux %d\n",
					__func__, data->cfg_fan_module.module[id].eeprom_topology.mux);
				err = -EFAULT;
				goto fail_connect_fan_eeprom;
			}
			memset(&board_info, 0, sizeof(struct i2c_board_info));
			board_info.addr = data->cfg_fan_module.module[id].eeprom_topology.addr;
			memcpy(board_info.type, fan_eeprom_driver, I2C_NAME_SIZE);
			if (!(data->cfg_fan_module.module[id].eeprom_client =
			      i2c_new_device(data->cfg_fan_module.module[id].eeprom_adapter,
					    (struct i2c_board_info const*)&board_info))) {
			        printk(KERN_INFO "%s: failed to create client %s at mux %d at addr 0x%02x\n",
					__func__, fan_eeprom_driver, data->cfg_fan_module.module[id].eeprom_topology.mux,
					data->cfg_fan_module.module[id].eeprom_topology.addr);
			        i2c_put_adapter(data->cfg_fan_module.module[id].eeprom_adapter);
				err = -EFAULT;
				goto fail_connect_fan_eeprom;
			}
        	}
        	else {
                        err = data->exec_tab.fan_init_entry(data, id, 0, 0, no_event);
                        data->cfg_led.led[leds_profile.fan_led_offset + id].led_cache = def_led_alarm_color;
        	}
	}

        /* Connect drivers for PSU, which are present */
	for (id = 0; id < data->cfg_psu_module.num_psu_modules; id++) {
		data->cfg_psu_module.module[id].presence_status_cache = 0;
		data->cfg_psu_module.module[id].power_status_cache = 0;

        	bus_access_func(data,
                        	data->cfg_psu_module.module[id].presence_status.offset,
                        	data->cfg_psu_module.module[id].presence_status.offset,
                        	1, &data->cfg_psu_module.module[id].presence_status_cache, 1);
        	data->cfg_psu_module.module[id].presence_status_cache = (~data->cfg_psu_module.module[id].presence_status_cache & 0xff);
        	data->cfg_psu_module.module[id].presence_status_cache &=
        	        	(1 << data->cfg_psu_module.module[id].presence_mask.bit);
        	bus_access_func(data,
                        	data->cfg_psu_module.module[id].power_status.offset,
                        	data->cfg_psu_module.module[id].power_status.offset,
                        	1, &data->cfg_psu_module.module[id].power_status_cache, 1);
        	data->cfg_psu_module.module[id].power_status_cache = (data->cfg_psu_module.module[id].power_status_cache &
                        	BIT_MASK(data->cfg_psu_module.module[id].power_mask.bit));
        	data->cfg_psu_module.module[id].power_status_cache &=
        	        	(1 << data->cfg_psu_module.module[id].power_mask.bit);
        	psu_presence_power_status &= (data->cfg_psu_module.module[id].presence_status_cache ==
        					data->cfg_psu_module.module[id].power_status_cache);

        	if (data->cfg_psu_module.module[id].presence_status_cache) {
			/* Connect PSU EEPROM drivers */
			if (!(data->cfg_psu_module.module[id].eeprom_adapter =
			      i2c_get_adapter(data->cfg_psu_module.module[id].eeprom_topology.mux))) {
				printk(KERN_INFO "%s: failed to get adapter for mux %d\n",
					__func__, data->cfg_psu_module.module[id].eeprom_topology.mux);
				err = -EFAULT;
				goto fail_connect_psu_eeprom;
			}
			memset(&board_info, 0, sizeof(struct i2c_board_info));
			board_info.addr = data->cfg_psu_module.module[id].eeprom_topology.addr;
			memcpy(board_info.type, psu_eeprom_driver, I2C_NAME_SIZE);
			if (!(data->cfg_psu_module.module[id].eeprom_client =
			      i2c_new_device(data->cfg_psu_module.module[id].eeprom_adapter,
					    (struct i2c_board_info const*)&board_info))) {
			        printk(KERN_INFO "%s: failed to create client %s at mux %d at addr 0x%02x\n",
					__func__, psu_eeprom_driver, data->cfg_psu_module.module[id].eeprom_topology.mux,
					data->cfg_psu_module.module[id].eeprom_topology.addr);
			        i2c_put_adapter(data->cfg_psu_module.module[id].eeprom_adapter);
				err = -EFAULT;
				goto fail_connect_psu_eeprom;
			}
        	}

        	if (data->cfg_psu_module.module[id].power_status_cache) {
			/* Connect PSU controller drivers */
			if (!(data->cfg_psu_module.module[id].control_adapter =
			      i2c_get_adapter(data->cfg_psu_module.module[id].topology.mux))) {
				printk(KERN_INFO "%s: failed to get adapter for mux %d\n",
					__func__, data->cfg_psu_module.module[id].topology.mux);
				err = -EFAULT;
				goto fail_connect_psu_controller;
			}
			memset(&board_info, 0, sizeof(struct i2c_board_info));
			board_info.addr = data->cfg_psu_module.module[id].topology.addr;
			memcpy(board_info.type, psu_control_driver, I2C_NAME_SIZE);
			if (!(data->cfg_psu_module.module[id].control_client =
			      i2c_new_device(data->cfg_psu_module.module[id].control_adapter,
					    (struct i2c_board_info const*)&board_info))) {
			        printk(KERN_INFO "%s: failed to create client %s at mux %d at addr 0x%02x\n",
					__func__, psu_eeprom_driver, data->cfg_psu_module.module[id].eeprom_topology.mux,
					data->cfg_psu_module.module[id].topology.addr);
			        i2c_put_adapter(data->cfg_psu_module.module[id].control_adapter);
				err = -EFAULT;
				goto fail_connect_psu_controller;
			}
        	}
	}

        /* Set LED for PS according to presence and power good bit */
        data->exec_tab.psu_init_entry(data, 0, psu_presence_power_status, fan_presence_status, no_event);

        /* Read statuses and save results in cache */
        bus_access_func(data,
                        data->top_aggregation_status.offset,
                        data->top_aggregation_status.offset,
                        1, &data->top_aggregation_cache, 1);
        bus_access_func(data,
                        data->cfg_psu_module.module[0].presence_status.offset,
                        data->cfg_psu_module.module[0].presence_status.offset,
                        1, &data->cfg_psu_module.presence_status_cache, 1);
        bus_access_func(data,
                        data->cfg_psu_module.module[0].power_status.offset,
                        data->cfg_psu_module.module[0].power_status.offset,
                        1, &data->cfg_psu_module.power_status_cache, 1);
        bus_access_func(data,
                        data->cfg_psu_module.module[0].alarm_status.offset,
                        data->cfg_psu_module.module[0].alarm_status.offset,
                        1, &data->cfg_psu_module.alarm_status_cache, 1);
        bus_access_func(data,
                        data->cfg_fan_module.module[0].presence_status.offset,
                        data->cfg_fan_module.module[0].presence_status.offset,
                        1, &data->cfg_fan_module.presence_status_cache, 1);

        /* Clear all event registers and unmask all mask registers */
	data->cfg_psu_module.mask = 0;
	for (id = 0; id < data->cfg_psu_module.num_psu_modules; id++) {
        	data->cfg_psu_module.mask |= BIT_MASK(psu_module_bit[id]);
        	data->cfg_psu_module.module[id].presence_status_cache = (~data->cfg_psu_module.presence_status_cache) & BIT_MASK(psu_module_bit[id]);
        	data->cfg_psu_module.module[id].power_status_cache = data->cfg_psu_module.power_status_cache & BIT_MASK(psu_module_bit[id]);
        	data->cfg_psu_module.module[id].alarm_status_cache = (~data->cfg_psu_module.alarm_status_cache) & BIT_MASK(psu_module_bit[id]);
	}
        data->cfg_psu_module.presence_status_cache = (~data->cfg_psu_module.presence_status_cache) & data->cfg_psu_module.mask;
        data->cfg_psu_module.power_status_cache = data->cfg_psu_module.power_status_cache & data->cfg_psu_module.mask;
        data->cfg_psu_module.alarm_status_cache = (~data->cfg_psu_module.module[id].alarm_status_cache) & data->cfg_psu_module.mask;

	data->cfg_fan_module.mask = 0;
	for (id = 0; id < data->cfg_fan_module.num_fan_modules; id++) {
        	data->cfg_fan_module.mask |= BIT_MASK(fan_module_bit[id]);
        	data->cfg_fan_module.module[id].presence_status_cache = (~data->cfg_fan_module.presence_status_cache) & BIT_MASK(fan_module_bit[id]);
	}
        data->cfg_fan_module.presence_status_cache = (~data->cfg_fan_module.presence_status_cache) & data->cfg_fan_module.mask;

        clear_unmask(data, data->cfg_psu_module.mask, data->cfg_fan_module.mask);

	return 0;

fail_connect_psu_controller:
fail_connect_psu_eeprom:
fail_connect_fan_eeprom:
fail_register_hwmon_device:

	if (!list_empty(&cpld_db.list)) {
		list_del_rcu(&data->list);
	}
	mutex_destroy(&data->access_lock);
	if (irq_line)
		free_irq(data->irq, data);
fail_request_irq:

	sysfs_remove_group(&client->dev.kobj, &mlnx_cpld_group[cpld_db.mlnx_system_type]);
fail_create_group:
	kfree(data);
	return err;
exit:
	return err;
}

static int cpld_detect(struct i2c_client *new_client,
                       struct i2c_board_info *info)
{
	strlcpy(info->type, "mlnx-cpld-drv", I2C_NAME_SIZE);
	return 0;
}

static int cpld_remove(struct i2c_client *client)
{
        struct cpld_data *data = i2c_get_clientdata(client);
        int id, flush, err = 0;

        /* Disonnect drivers for PSU */
	for (id = 0; id < data->cfg_psu_module.num_psu_modules; id++) {
		if (data->cfg_psu_module.module[id].control_client)
			i2c_unregister_device(data->cfg_psu_module.module[id].control_client);
		if (data->cfg_psu_module.module[id].control_adapter)
			i2c_put_adapter(data->cfg_psu_module.module[id].control_adapter);

		if (data->cfg_psu_module.module[id].eeprom_client)
			i2c_unregister_device(data->cfg_psu_module.module[id].eeprom_client);
		if (data->cfg_psu_module.module[id].eeprom_adapter)
			i2c_put_adapter(data->cfg_psu_module.module[id].eeprom_adapter);
	}
	err = data->exec_tab.psu_exit_entry(data, 0, 0, 0, no_event);

        /* Disonnect drivers for FAN */
	for (id = 0; id < data->cfg_fan_module.num_fan_modules; id++) {
		if (data->cfg_fan_module.module[id].eeprom_client)
			i2c_unregister_device(data->cfg_fan_module.module[id].eeprom_client);
		if (data->cfg_fan_module.module[id].eeprom_adapter)
			i2c_put_adapter(data->cfg_fan_module.module[id].eeprom_adapter);

		err = data->exec_tab.fan_exit_entry(data, id, 0, 0, no_event);
	}

        topology_config_clean(data);
        reset_config_clean(data);
        info_config_clean(data);
        module_psu_config_clean(data);
        module_fan_config_clean(data);
        led_config_clean(data);

        hwmon_device_unregister(data->hwmon_dev);

	if (irq_line)
		free_irq(data->irq, data);
	flush = cancel_delayed_work_sync(&data->dwork);
	if (flush)
		flush_scheduled_work();

	sysfs_remove_group(&client->dev.kobj, &mlnx_cpld_group[cpld_db.mlnx_system_type]);

	if (!list_empty(&cpld_db.list)) {
		list_del_rcu(&data->list);
	}
	mutex_destroy(&data->access_lock);

	if(data)
	    kfree(data);

	return 0;
}

static const struct i2c_device_id cpld_id[] = {
        { "mlnx-cpld-drv", 0 },
        { "mlnx-cpld-drv-unmng", 0 },
        { }
};
MODULE_DEVICE_TABLE(i2c, cpld_id);

static struct i2c_driver mlnx_cpld_drv = {
        .class          = I2C_CLASS_HWMON,
        .driver = {
                .name   = "mlnx-cpld-drv",
        },
        .probe          = cpld_probe,
        .remove         = cpld_remove,
        .id_table       = cpld_id,
        .detect         = cpld_detect,
};

static int __init mlnx_cpld_init(void)
{
	struct i2c_board_info board_info;
	struct cpld_mux_platform_mode modes[MUX_CHAN_NUM];
	int err = 0, i, id;
	int mlnx_system_type;

	cpld_db.cpld_hwmon_dev = hwmon_device_register(NULL);

	if (!(cpld_db.cpld_hwmon_dev)) {
		err = -ENODEV;
		cpld_db.cpld_hwmon_dev = NULL;
		printk(KERN_ERR "cpld: hwmon registration failed (%d)\n", err);
		return err;
	}

	mlnx_system_type = mlnx_check_system_type();
	switch (mlnx_system_type) {
	case msn2100_sys_type:
		cpld_db.mlnx_system_type = msn2100_sys_type;
		num_psu_modules = 0;
		num_fixed_psu_modules = 2;
		num_fan_modules = 0;
		num_cpld = 2;
		num_reset = 3;
		num_mux = 2;
		leds_profile.profile = led_msn2100_profile;
		num_led = ARRAY_SIZE(led_msn2100_profile);
		leds_profile.fan_led_offset = 0;
		leds_profile.psu_led_offset = 1;
		leds_profile.status_led_offset = 3;
		leds_profile.uid_led_offset = 4;
		leds_profile.bp_led_offset = NOT_USED_LED_OFFSET;
		irq_line = 0;
		mux_driver =  "cpld_mux_mgmt";

		for (i = 0; i < num_fixed_psu_modules; i++)
			psu_module_alarm_status_offset[i] =
					psu_module_power_event_offset[i];
		break;

	case msn2740_sys_type:
		cpld_db.mlnx_system_type = msn2740_sys_type;
		num_psu_modules = 2;
		num_fixed_psu_modules = 0;
		num_fan_modules = 4;
		num_cpld = 2;
		num_reset = 3;
		num_mux = 2;
		leds_profile.profile = led_default_profile;
		num_led = ARRAY_SIZE(led_default_profile);
		leds_profile.fan_led_offset = 0;
		leds_profile.psu_led_offset = 4;
		leds_profile.status_led_offset = 5;
		leds_profile.uid_led_offset = NOT_USED_LED_OFFSET;
		leds_profile.bp_led_offset = NOT_USED_LED_OFFSET;
		leds_profile.uid_led_offset = NOT_USED_LED_OFFSET;
		irq_line = DEF_IRQ_LINE;
		psu_module_mux[0] = 4;
		psu_module_mux[1] = 4;
		psu_mux[0] = 4;
		psu_mux[1] = 4;
		mux_driver =  "cpld_mux_mgmt";
		break;

	case mlnx_dflt_sys_type:
	default:
		cpld_db.mlnx_system_type = mlnx_dflt_sys_type;
		num_psu_modules = 2;
		num_fixed_psu_modules = 0;
		num_fan_modules = 4;
		num_cpld = 3;
		num_reset = 3;
		num_mux = 2;
		leds_profile.profile = led_default_profile;
		num_led = ARRAY_SIZE(led_default_profile);
		leds_profile.fan_led_offset = 0;
		leds_profile.psu_led_offset = 4;
		leds_profile.status_led_offset = 5;
		leds_profile.bp_led_offset = NOT_USED_LED_OFFSET;
		leds_profile.uid_led_offset = NOT_USED_LED_OFFSET;
		irq_line = DEF_IRQ_LINE;
		mux_driver =  "cpld_mux_tor";
		break;
	}

	INIT_LIST_HEAD(&cpld_db.list);
	i2c_add_driver(&mlnx_cpld_drv);

	cpld_db.cfg_mux.num_mux = num_mux;
	memset(modes, 0, sizeof(struct cpld_mux_platform_mode) * MUX_CHAN_NUM);
        for (i = 0; i < MUX_CHAN_NUM; i++) {
        	modes[i].deselect_on_exit = deselect_on_exit;
        	modes[i].adap_id = force_chan;
        }
	for (id = 0; id < num_mux; id++) {
        	memset(&cpld_db.cfg_mux.mux[id], 0, sizeof(struct mux_params));
        	memset(&board_info, 0, sizeof(struct i2c_board_info));

        	if (!(cpld_db.cfg_mux.mux[id].platform = kzalloc(sizeof(struct cpld_mux_platform_data), GFP_KERNEL))) {
			err = -ENOMEM;
			goto fail_no_memory;
		}
        	cpld_db.cfg_mux.mux[id].mux_driver = mux_driver;
        	cpld_db.cfg_mux.mux[id].platform->modes = modes;
        	cpld_db.cfg_mux.mux[id].platform->num_modes = mux_chan_num[id];
        	cpld_db.cfg_mux.mux[id].platform->id = mux_reg_offset[id];
        	cpld_db.cfg_mux.mux[id].platform->sel_reg_addr = mux_reg_offset[id];
        	cpld_db.cfg_mux.mux[id].platform->first_channel = mux_first_num[id];
        	cpld_db.cfg_mux.mux[id].platform->addr = mux_reg_offset[id];
        	cpld_db.cfg_mux.mux[id].parent_mux = parent_mux[id];
		if (!(cpld_db.cfg_mux.mux[id].adapter =
			i2c_get_adapter(cpld_db.cfg_mux.mux[id].parent_mux))) {
				printk(KERN_INFO "%s: failed to get adapter for mux %d\n",
					__func__, cpld_db.cfg_mux.mux[id].parent_mux);
			err = -EFAULT;
			goto fail_request_mux;
		}

		memset(&board_info, 0, sizeof(struct i2c_board_info));
		board_info.platform_data = cpld_db.cfg_mux.mux[id].platform;
		board_info.flags = I2C_CLIENT_TEN;
		board_info.addr = cpld_db.cfg_mux.mux[id].platform->addr & 0xff;
		memcpy(board_info.type, mux_driver, I2C_NAME_SIZE);

		if (!(cpld_db.cfg_mux.mux[id].client =
			i2c_new_device(cpld_db.cfg_mux.mux[id].adapter,
					    (struct i2c_board_info const*)&board_info))) {
			printk(KERN_INFO "%s: failed to create client %s at mux %d at addr 0x%02x\n",
				__func__, mux_driver, cpld_db.cfg_mux.mux[id].parent_mux,
				board_info.addr);
			i2c_put_adapter(cpld_db.cfg_mux.mux[id].adapter);
			err = -EFAULT;
			goto fail_request_mux;
		}
	}

	printk(KERN_INFO "%s Version %s\n", CPLD_DRV_DESCRIPTION, CPLD_DRV_VERSION);

	return err;

fail_request_mux:
	id = num_mux;
	for (i = id - 1; i >= 0; i--) {
		i2c_unregister_device(cpld_db.cfg_mux.mux[i].client);
		i2c_put_adapter(cpld_db.cfg_mux.mux[i].adapter);
	}
fail_no_memory:
	i2c_del_driver(&mlnx_cpld_drv);
	hwmon_device_unregister(cpld_db.cpld_hwmon_dev);

	return err;
}

static void __exit mlnx_cpld_exit(void)
{
	struct cpld_data *data, *next;
	int id;

	for (id = cpld_db.cfg_mux.num_mux - 1; id >= 0; id--) {
		i2c_unregister_device(cpld_db.cfg_mux.mux[id].client);
		i2c_put_adapter(cpld_db.cfg_mux.mux[id].adapter);
	}

	i2c_del_driver(&mlnx_cpld_drv);

	list_for_each_entry_safe(data, next, &cpld_db.list, list) {
		if (!list_empty(&cpld_db.list)) {
			mutex_destroy(&data->access_lock);
			list_del_rcu(&data->list);
			kfree(data);
		}
	}

	hwmon_device_unregister(cpld_db.cpld_hwmon_dev);
}

module_init(mlnx_cpld_init);
module_exit(mlnx_cpld_exit);
