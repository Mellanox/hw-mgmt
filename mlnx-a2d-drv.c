/**
 *
 * Copyright (C) Mellanox Technologies Ltd. 2001-2014.  ALL RIGHTS RESERVED.
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
#include <linux/init.h>
#include <linux/slab.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/mutex.h>
#include <linux/list.h>
#include <linux/kref.h>
#include <linux/hwmon.h>
#include <linux/hwmon-sysfs.h>
#include <linux/i2c.h>
#include <linux/dmi.h>
#include <linux/string.h>
#include "arch/x86/include/mlnx-common.h"
#include "mlnx-sys-type.h"

#define VOLT_SENS_NUM_MAX   13
#define VOLT_SENS_NUM_DFLT  9
#define VOLT_SENS_NUM_SFF   13

#define VOLT_SENS_SW_NUM_MAX        3
#define VOLT_SENS_SW_NUM_DFLT       1
#define VOLT_SENS_SW_NUM_MSN2100    5
#define CURR_SENS_SW_NUM_MSN2100    2
#define VOLT_SENS_SW_NUM_MSN2740    4
#define CURR_SENS_MAIN_NUM_MSN2100  0

#define CURR_SENS_NUM    2
#define MAX_LABEL_LEN   24
#define MAX_READ_SIZE    8

#define A2D_ADDR_WIDTH   0
#define A2D_CFG_SET_REG  0
#define A2D_DATA_REG     1
#define A2D_SETUP_BYTE   0xda
#define A2D_CONFIG_BYTE  0x0f

#define A2D_VCCSA_SEL_REG   0x2b
#define A2D_VCCSA_SEL_MASK  0x60
#define A2D_VCCSA_SEL_SHIFT 0x5

#define A2D_DRV_VERSION        "0.0.1 24/08/2015"
#define A2D_DRV_DESCRIPTION    "Mellanox A2D BSP driver. Build:" " "__DATE__" "__TIME__
MODULE_AUTHOR("Vadim Pasternak (vadimp@mellanox.com)");
MODULE_DESCRIPTION(A2D_DRV_DESCRIPTION);
MODULE_LICENSE("GPL v2");
MODULE_ALIAS("mlnxa2d");

static unsigned short cpld_lpc_base = 0x2500;
static unsigned short wp_vcc_reg_offset = 0x33;
static unsigned short vcc_reg_offset = 0x32;
static unsigned short vcc_reg_bit = 6;

static unsigned short num_main_board_volt_sensors = VOLT_SENS_NUM_DFLT;
static unsigned short num_main_board_curr_sensors = 2;
static unsigned short num_sw_board_volt_sensors = VOLT_SENS_SW_NUM_DFLT;
static unsigned short num_sw_board_curr_sensors = 0;
static unsigned short main_board_read_size = 8;
static unsigned short sw_board_read_size = 7;


static unsigned short mnb_expect_volt[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ 675, 870, 3300, 1800, 1050, 1050, 1350, 5000, 1500, 0, 0, 0, 0 },
	{ 1000, 1000, 675, 1000, 1350, 1800, 3300, 12000, 1350, 1070, 1500,
	  5000, 3300 },
	{ 1000, 1000, 675, 1000, 1350, 1800, 3300, 12000, 1350, 1070, 1500,
	  5000, 3300 },
};

static unsigned short mnb_expect_volt_dev[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ 10, 15, 10, 10, 10, 10, 10, 10, 10, 0, 0, 0, 0 },
	{ 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10 },
	{ 20, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10 },
};

static unsigned short mnb_scale_volt[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ 8, 8, 16, 8, 8, 8, 8, 24, 8, 0, 0, 0, 0 },
	{ 8, 8, 8, 8, 8, 8, 16, 88, 8, 8, 8, 25, 16 },
	{ 8, 8, 8, 8, 8, 8, 16, 88, 8, 8, 8, 25, 16 },
};

static unsigned short mnb_offset_volt[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0 },
	{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1 },
	{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1 },
};

static unsigned short mnb_rail_volt[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ 0, 1, 3, 4, 5, 6, 7, 3, 5, 0, 0, 0, 0 },
	{ 0, 1, 2, 3, 4, 5, 6, 7, 3, 4, 5, 6, 7 },
	{ 0, 1, 2, 3, 4, 5, 6, 7, 3, 4, 5, 6, 7 },
};

static char *mnb_label_volt[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ "ddr3_0.675", "cpu_0.9", "sys", "cpu_1.8", "cpu_pch_1.05",
	  "cpu_1.05", "ddr3_1.35", "usb_5", "lan_1.05", "", "", "", "" },
	{ "soc_core", "soc_vnn", "cpu_0.675v", "1v", "vddq", "1.8v",
	  "sys_3.3v", "12v", "1.35v", "vccsram", "1.5v", "5v", "3.3v_aux" },
	{ "soc_core", "soc_vnn", "cpu_0.675v", "1v", "vddq", "1.8v",
	  "sys_3.3v", "12v", "1.35v", "vccsram", "1.5v", "5v", "3.3v_aux" },
};

static unsigned short mnb_expect_curr[SYS_TYPE][CURR_SENS_NUM] = {
	{ 2, 2 },
	{ 0, 0 },
	{ 0, 0 },
};

static unsigned short mnb_scale_curr[SYS_TYPE][CURR_SENS_NUM] = {
	{ 8, 8 },
	{ 0, 0 },
	{ 0, 0 },
};

static unsigned short mnb_offset_curr[SYS_TYPE][CURR_SENS_NUM] = {
	{ 0, 1 },
	{ 0, 0 },
	{ 0, 0 },
};

static unsigned short mnb_rail_curr[SYS_TYPE][CURR_SENS_NUM] = {
	{ 2, 2 },
	{ 0, 0 },
	{ 0, 0 },
};

static char *mnb_label_curr[SYS_TYPE][CURR_SENS_NUM] = {
	{ "ps2_12_aux", "ps1_12_aux" },
	{ "", "" },
	{ "", "" },
};

static unsigned short swb_expect_volt[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ 1800, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 12000, 12000, 3300,12000, 5000, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 12000, 12000, 3300, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

static unsigned short swb_expect_volt_dev[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 10, 10, 10, 10, 10, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 10, 10, 10, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

static unsigned short swb_scale_volt[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 59, 59, 16, 59, 33, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 59, 59, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

static unsigned short swb_offset_volt[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

static unsigned short swb_rail_volt[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 0, 1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 1, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

static char *swb_label_volt[SYS_TYPE][VOLT_SENS_NUM_MAX] = {
	{ "1.8V_sw_spc", "", "", "", "", "", "", "", "", "", "", "", "" },
	{ "12v_1", "12v_2", "3.3v", "12v_aux", "5v_usb", "", "", "", "", "",
	  "", "", "" },
	{ "12v", "12v_aux", "3.3v_aux", "", "", "", "", "", "", "", "", "", ""
	},
};

static unsigned short swb_expect_curr[SYS_TYPE][CURR_SENS_NUM] = {
	{ 0, 0 },
	{ 0, 0 },
	{ 0, 0 },
};

static unsigned short swb_scale_curr[SYS_TYPE][CURR_SENS_NUM] = {
	{ 0, 0 },
	{ 80, 80 },
	{ 0, 0 },
};

static unsigned short swb_offset_curr[SYS_TYPE][CURR_SENS_NUM] = {
	{ 0, 0 },
	{ 0, 0 },
	{ 0, 0 },
};

static unsigned short swb_rail_curr[SYS_TYPE][CURR_SENS_NUM] = {
	{ 0, 0 },
	{ 5, 6 },
	{ 0, 0 },
};

static char *swb_label_curr[SYS_TYPE][CURR_SENS_NUM] = {
	{ "", "" },
	{ "12v_1_curr", "12v_2_curr" },
	{ "", "" },
};

enum a2d_types {
	a2d_drv,
	a2d_mnb_drv,
	a2d_swb_drv,
};

struct a2d_config {
	u32 expect;
	u8 scale;
	u8 offset;
	u8 rail;
	u8 dev;
	char label[MAX_LABEL_LEN];
};

static struct device *a2d_hwmon_dev;
struct a2d_data {
	struct list_head list;
	struct kref kref;
	__u16 base; /* Low Pin Count (LPC) bus access base address */
	struct device * hwmon_dev;
	const char * name;
	enum a2d_types dev_id;
	struct mutex access_lock;
	unsigned long last_update; /* in jiffies */
	struct a2d_config volt[VOLT_SENS_NUM_MAX];
	struct a2d_config curr[CURR_SENS_NUM];
	u8 read_size;
	enum mlnx_system_types mlnx_system_type;
};

/* Container structure */
struct a2d_container {
	struct list_head list;
};
static struct a2d_container a2d_db;

typedef enum volt_attr {
        volt_in,
        volt_min,
        volt_max,
        volt_label,
} volt_attr_t;

typedef enum curr_attr {
        curr_input,
        curr_max,
        curr_label,
} curr_attr_t;

static int bus_access_func(struct a2d_data * a2d_data, u8 from_range,
			   u8 to_range, u8 rw_flag, u8 * data, u8 lock_flag)
{
        int datalen = to_range - from_range + 1;

        if (lock_flag)
                mutex_lock(&a2d_data->access_lock);
        bus_rw(a2d_data->base, from_range, datalen, rw_flag, data);
        if (lock_flag)
                mutex_unlock(&a2d_data->access_lock);

	return 0;
}

static int a2d_get_volt_curr(struct a2d_data      *a2d_data,
				struct i2c_client *client,
				int                index,
				u8                 volt_curr)
{
	u8 val = 0, new_val;
	int res = 0, retries = 1;
	u8 buf[MAX_READ_SIZE];

	/* Remove protection */
	bus_access_func(a2d_data, wp_vcc_reg_offset,
			wp_vcc_reg_offset, 1, &val, 1);
	new_val = (val & ~(1 << vcc_reg_bit));

	if (new_val != val)
		bus_access_func(a2d_data, wp_vcc_reg_offset,
				wp_vcc_reg_offset, 0, &new_val, 1);

	/* Set relevant page */
	bus_access_func(a2d_data, vcc_reg_offset,
			wp_vcc_reg_offset, 1, &val, 1);

	new_val = (val & ~(1 << vcc_reg_bit));
	if (volt_curr)
		new_val |= (a2d_data->volt[index].offset << vcc_reg_bit);
	else
		new_val |= (a2d_data->curr[index].offset << vcc_reg_bit);

	if (new_val != val)
		bus_access_func(a2d_data, vcc_reg_offset,
				vcc_reg_offset, 0, &new_val, 1);

        while (retries > 0) {
                memset(buf, 0, a2d_data->read_size);
                res = i2c_master_recv(client, buf, a2d_data->read_size);
                if (res >= 0) {
	                if (volt_curr)
                                res = buf[a2d_data->volt[index].rail] * a2d_data->volt[index].scale;
	                else
                                res = buf[a2d_data->curr[index].rail] * a2d_data->curr[index].scale;
                        break;
                }
                retries--;
        }

	return res;
}

static int a2d_get_volt_label(struct a2d_data *a2d_data,
			      int index,
			      char *label)
{
	return sprintf(label, "%s\n", a2d_data->volt[index].label);
}

static int a2d_set_volt_label(struct a2d_data *a2d_data,
			      int index,
			      const char *label)
{
	memcpy(a2d_data->volt[index].label, label, strlen(a2d_data->volt[index].label));

	return 0;
}

static ssize_t show_volt(struct device *dev,
			 struct device_attribute *devattr,
			 char *buf)
{
	struct i2c_client *client = to_i2c_client(dev);
	struct a2d_data *data = i2c_get_clientdata(client);
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	int res = 0;

	switch (nr) {
	case volt_in:
		res = a2d_get_volt_curr(data, client, index, 1);
		break;
	case volt_min:
		res = data->volt[index].expect -
			((data->volt[index].expect * data->volt[index].dev) / 100);
		break;
	case volt_max:
		res = data->volt[index].expect +
			((data->volt[index].expect * data->volt[index].dev) / 100);
		break;
	case volt_label:
		return a2d_get_volt_label(data, index, buf);
		break;
	default:
		return -EEXIST;
	}

	return sprintf(buf, "%d\n", res);
}

static ssize_t store_volt(struct device *dev,
			  struct device_attribute *devattr,
			  const char *buf, size_t count)
{
	struct a2d_data *data = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	int err;

	switch (nr) {
	case volt_min:
	case volt_max:
		break;
	case volt_label:
		err = a2d_set_volt_label(data, index, buf);
		break;
	default:
		return -EEXIST;
	}

	return count;
}

static int a2d_get_curr_label(struct a2d_data *a2d_data,
			        int index,
			        char *label)
{
	return sprintf(label, "%s\n", a2d_data->curr[index].label);
}

static int a2d_set_curr_label(struct a2d_data *a2d_data,
			       int index,
			       const char *label)
{
	memcpy(a2d_data->curr[index].label, label,
		strlen(a2d_data->curr[index].label));

	return 0;
}

static ssize_t show_curr(struct device *dev,
			    struct device_attribute *devattr,
			    char *buf)
{
	struct i2c_client *client = to_i2c_client(dev);
	struct a2d_data *data = i2c_get_clientdata(client);
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	int res = 0;

	switch (nr) {
	case curr_input:
		res = a2d_get_volt_curr(data, client, index, 0);
		break;
	case curr_max:
		res = data->curr[index].expect * 1000;
		break;
	case curr_label:
		return a2d_get_curr_label(data, index, buf);
		break;
	default:
		return -EEXIST;
	}

	return sprintf(buf, "%d\n", res);
}

static ssize_t store_curr(struct device *dev,
			     struct device_attribute *devattr,
			     const char *buf, size_t count)
{
	struct a2d_data *data = i2c_get_clientdata(to_i2c_client(dev));
	int index = to_sensor_dev_attr_2(devattr)->index;
        int nr = to_sensor_dev_attr_2(devattr)->nr;
	int err;

	switch (nr) {
	case curr_input:
	case curr_max:
		break;
	case curr_label:
		err = a2d_set_curr_label(data, index, buf);
		break;
	default:
		return -EEXIST;
	}

	return count;
}

#define SENSOR_DEVICE_ATTR_VOLT(id)                            \
static SENSOR_DEVICE_ATTR_2(in##id##_input, S_IRUGO,           \
        show_volt, NULL, volt_in, id - 1);                     \
static SENSOR_DEVICE_ATTR_2(in##id##_min, S_IRUGO | S_IWUSR,   \
        show_volt, store_volt, volt_min, id - 1);              \
static SENSOR_DEVICE_ATTR_2(in##id##_max, S_IRUGO | S_IWUSR,   \
        show_volt, store_volt, volt_max, id - 1);              \
static SENSOR_DEVICE_ATTR_2(in##id##_label, S_IRUGO | S_IWUSR, \
        show_volt, store_volt, volt_label, id - 1);

SENSOR_DEVICE_ATTR_VOLT(1);
SENSOR_DEVICE_ATTR_VOLT(2);
SENSOR_DEVICE_ATTR_VOLT(3);
SENSOR_DEVICE_ATTR_VOLT(4);
SENSOR_DEVICE_ATTR_VOLT(5);
SENSOR_DEVICE_ATTR_VOLT(6);
SENSOR_DEVICE_ATTR_VOLT(7);
SENSOR_DEVICE_ATTR_VOLT(8);
SENSOR_DEVICE_ATTR_VOLT(9);
SENSOR_DEVICE_ATTR_VOLT(10);
SENSOR_DEVICE_ATTR_VOLT(11);
SENSOR_DEVICE_ATTR_VOLT(12);
SENSOR_DEVICE_ATTR_VOLT(13);

#define SENSOR_DEVICE_ATTR_CURR(id)                                \
static SENSOR_DEVICE_ATTR_2(curr##id##_input, S_IRUGO,           \
        show_curr, NULL, curr_input, id - 1);                   \
static SENSOR_DEVICE_ATTR_2(curr##id##_max, S_IRUGO | S_IWUSR,   \
        show_curr, store_curr, curr_max, id - 1);              \
static SENSOR_DEVICE_ATTR_2(curr##id##_label, S_IRUGO | S_IWUSR, \
        show_curr, store_curr, curr_label, id - 1);

SENSOR_DEVICE_ATTR_CURR(1);
SENSOR_DEVICE_ATTR_CURR(2);

static struct attribute *mlnx_mnb_a2d_attributes[] = {
        &sensor_dev_attr_in1_input.dev_attr.attr,
        &sensor_dev_attr_in1_min.dev_attr.attr,
        &sensor_dev_attr_in1_max.dev_attr.attr,
        &sensor_dev_attr_in1_label.dev_attr.attr,
        &sensor_dev_attr_in2_input.dev_attr.attr,
        &sensor_dev_attr_in2_min.dev_attr.attr,
        &sensor_dev_attr_in2_max.dev_attr.attr,
        &sensor_dev_attr_in2_label.dev_attr.attr,
        &sensor_dev_attr_in3_input.dev_attr.attr,
        &sensor_dev_attr_in3_min.dev_attr.attr,
        &sensor_dev_attr_in3_max.dev_attr.attr,
        &sensor_dev_attr_in3_label.dev_attr.attr,
        &sensor_dev_attr_in4_input.dev_attr.attr,
        &sensor_dev_attr_in4_min.dev_attr.attr,
        &sensor_dev_attr_in4_max.dev_attr.attr,
        &sensor_dev_attr_in4_label.dev_attr.attr,
        &sensor_dev_attr_in5_input.dev_attr.attr,
        &sensor_dev_attr_in5_min.dev_attr.attr,
        &sensor_dev_attr_in5_max.dev_attr.attr,
        &sensor_dev_attr_in5_label.dev_attr.attr,
        &sensor_dev_attr_in6_input.dev_attr.attr,
        &sensor_dev_attr_in6_min.dev_attr.attr,
        &sensor_dev_attr_in6_max.dev_attr.attr,
        &sensor_dev_attr_in6_label.dev_attr.attr,
        &sensor_dev_attr_in7_input.dev_attr.attr,
        &sensor_dev_attr_in7_min.dev_attr.attr,
        &sensor_dev_attr_in7_max.dev_attr.attr,
        &sensor_dev_attr_in7_label.dev_attr.attr,
        &sensor_dev_attr_in8_input.dev_attr.attr,
        &sensor_dev_attr_in8_min.dev_attr.attr,
        &sensor_dev_attr_in8_max.dev_attr.attr,
        &sensor_dev_attr_in8_label.dev_attr.attr,
        &sensor_dev_attr_in9_input.dev_attr.attr,
        &sensor_dev_attr_in9_min.dev_attr.attr,
        &sensor_dev_attr_in9_max.dev_attr.attr,
        &sensor_dev_attr_in9_label.dev_attr.attr,
        &sensor_dev_attr_curr1_input.dev_attr.attr,
        &sensor_dev_attr_curr1_max.dev_attr.attr,
        &sensor_dev_attr_curr1_label.dev_attr.attr,
        &sensor_dev_attr_curr2_input.dev_attr.attr,
        &sensor_dev_attr_curr2_max.dev_attr.attr,
        &sensor_dev_attr_curr2_label.dev_attr.attr,
        NULL
};

static struct attribute *mlnx_swb_a2d_attributes[] = {
        &sensor_dev_attr_in1_input.dev_attr.attr,
        &sensor_dev_attr_in1_min.dev_attr.attr,
        &sensor_dev_attr_in1_max.dev_attr.attr,
        &sensor_dev_attr_in1_label.dev_attr.attr,
        NULL
};

static struct attribute *mlnx_mnb_sff_a2d_attributes[] = {
        &sensor_dev_attr_in1_input.dev_attr.attr,
        &sensor_dev_attr_in1_min.dev_attr.attr,
        &sensor_dev_attr_in1_max.dev_attr.attr,
        &sensor_dev_attr_in1_label.dev_attr.attr,
        &sensor_dev_attr_in2_input.dev_attr.attr,
        &sensor_dev_attr_in2_min.dev_attr.attr,
        &sensor_dev_attr_in2_max.dev_attr.attr,
        &sensor_dev_attr_in2_label.dev_attr.attr,
        &sensor_dev_attr_in3_input.dev_attr.attr,
        &sensor_dev_attr_in3_min.dev_attr.attr,
        &sensor_dev_attr_in3_max.dev_attr.attr,
        &sensor_dev_attr_in3_label.dev_attr.attr,
        &sensor_dev_attr_in4_input.dev_attr.attr,
        &sensor_dev_attr_in4_min.dev_attr.attr,
        &sensor_dev_attr_in4_max.dev_attr.attr,
        &sensor_dev_attr_in4_label.dev_attr.attr,
        &sensor_dev_attr_in5_input.dev_attr.attr,
        &sensor_dev_attr_in5_min.dev_attr.attr,
        &sensor_dev_attr_in5_max.dev_attr.attr,
        &sensor_dev_attr_in5_label.dev_attr.attr,
        &sensor_dev_attr_in6_input.dev_attr.attr,
        &sensor_dev_attr_in6_min.dev_attr.attr,
        &sensor_dev_attr_in6_max.dev_attr.attr,
        &sensor_dev_attr_in6_label.dev_attr.attr,
        &sensor_dev_attr_in7_input.dev_attr.attr,
        &sensor_dev_attr_in7_min.dev_attr.attr,
        &sensor_dev_attr_in7_max.dev_attr.attr,
        &sensor_dev_attr_in7_label.dev_attr.attr,
        &sensor_dev_attr_in8_input.dev_attr.attr,
        &sensor_dev_attr_in8_min.dev_attr.attr,
        &sensor_dev_attr_in8_max.dev_attr.attr,
        &sensor_dev_attr_in8_label.dev_attr.attr,
        &sensor_dev_attr_in9_input.dev_attr.attr,
        &sensor_dev_attr_in9_min.dev_attr.attr,
        &sensor_dev_attr_in9_max.dev_attr.attr,
        &sensor_dev_attr_in9_label.dev_attr.attr,
        &sensor_dev_attr_in10_input.dev_attr.attr,
        &sensor_dev_attr_in10_min.dev_attr.attr,
        &sensor_dev_attr_in10_max.dev_attr.attr,
        &sensor_dev_attr_in10_label.dev_attr.attr,
        &sensor_dev_attr_in11_input.dev_attr.attr,
        &sensor_dev_attr_in11_min.dev_attr.attr,
        &sensor_dev_attr_in11_max.dev_attr.attr,
        &sensor_dev_attr_in11_label.dev_attr.attr,
        &sensor_dev_attr_in12_input.dev_attr.attr,
        &sensor_dev_attr_in12_min.dev_attr.attr,
        &sensor_dev_attr_in12_max.dev_attr.attr,
        &sensor_dev_attr_in12_label.dev_attr.attr,
        &sensor_dev_attr_in13_input.dev_attr.attr,
        &sensor_dev_attr_in13_min.dev_attr.attr,
        &sensor_dev_attr_in13_max.dev_attr.attr,
        &sensor_dev_attr_in13_label.dev_attr.attr,
        NULL
};

static struct attribute *mlnx_swb_msn2100_a2d_attributes[] = {
        &sensor_dev_attr_in1_input.dev_attr.attr,
        &sensor_dev_attr_in1_min.dev_attr.attr,
        &sensor_dev_attr_in1_max.dev_attr.attr,
        &sensor_dev_attr_in1_label.dev_attr.attr,
        &sensor_dev_attr_in2_input.dev_attr.attr,
        &sensor_dev_attr_in2_min.dev_attr.attr,
        &sensor_dev_attr_in2_max.dev_attr.attr,
        &sensor_dev_attr_in2_label.dev_attr.attr,
        &sensor_dev_attr_in3_input.dev_attr.attr,
        &sensor_dev_attr_in3_min.dev_attr.attr,
        &sensor_dev_attr_in3_max.dev_attr.attr,
        &sensor_dev_attr_in3_label.dev_attr.attr,
        &sensor_dev_attr_in4_input.dev_attr.attr,
        &sensor_dev_attr_in4_min.dev_attr.attr,
        &sensor_dev_attr_in4_max.dev_attr.attr,
        &sensor_dev_attr_in4_label.dev_attr.attr,
        &sensor_dev_attr_in5_input.dev_attr.attr,
        &sensor_dev_attr_in5_min.dev_attr.attr,
        &sensor_dev_attr_in5_max.dev_attr.attr,
        &sensor_dev_attr_in5_label.dev_attr.attr,
        &sensor_dev_attr_curr1_input.dev_attr.attr,
        &sensor_dev_attr_curr1_max.dev_attr.attr,
        &sensor_dev_attr_curr1_label.dev_attr.attr,
        &sensor_dev_attr_curr2_input.dev_attr.attr,
        &sensor_dev_attr_curr2_max.dev_attr.attr,
        &sensor_dev_attr_curr2_label.dev_attr.attr,
        NULL
};

static struct attribute *mlnx_swb_msn2740_a2d_attributes[] = {
        &sensor_dev_attr_in1_input.dev_attr.attr,
        &sensor_dev_attr_in1_min.dev_attr.attr,
        &sensor_dev_attr_in1_max.dev_attr.attr,
        &sensor_dev_attr_in1_label.dev_attr.attr,
        &sensor_dev_attr_in2_input.dev_attr.attr,
        &sensor_dev_attr_in2_min.dev_attr.attr,
        &sensor_dev_attr_in2_max.dev_attr.attr,
        &sensor_dev_attr_in2_label.dev_attr.attr,
        &sensor_dev_attr_in3_input.dev_attr.attr,
        &sensor_dev_attr_in3_min.dev_attr.attr,
        &sensor_dev_attr_in3_max.dev_attr.attr,
        &sensor_dev_attr_in3_label.dev_attr.attr,
        NULL
};

static const struct attribute_group mlnx_mnb_a2d_group[SYS_TYPE] = {
	{.attrs = mlnx_mnb_a2d_attributes},
	{.attrs = mlnx_mnb_sff_a2d_attributes},
	{.attrs = mlnx_mnb_sff_a2d_attributes},
};

static const struct attribute_group mlnx_swb_a2d_group[SYS_TYPE] = {
	{.attrs = mlnx_swb_a2d_attributes},
	{.attrs = mlnx_swb_msn2100_a2d_attributes},
	{.attrs = mlnx_swb_msn2740_a2d_attributes},
};

static int a2d_config(struct a2d_data *a2d_data)
{
	int id;
	int err = 0;

	memset(&a2d_data->volt, 0, sizeof(struct a2d_config) * VOLT_SENS_NUM_MAX);
	memset(&a2d_data->curr, 0, sizeof(struct a2d_config) * CURR_SENS_NUM);

	switch (a2d_data->dev_id) {
	case a2d_drv:
	case a2d_mnb_drv:
		for (id = 0; id < num_main_board_volt_sensors; id++) {
			a2d_data->volt[id].expect = mnb_expect_volt[a2d_data->mlnx_system_type][id];
			a2d_data->volt[id].dev = mnb_expect_volt_dev[a2d_data->mlnx_system_type][id];
			a2d_data->volt[id].scale = mnb_scale_volt[a2d_data->mlnx_system_type][id];
			a2d_data->volt[id].offset = mnb_offset_volt[a2d_data->mlnx_system_type][id];
			a2d_data->volt[id].rail = mnb_rail_volt[a2d_data->mlnx_system_type][id];
			memcpy(a2d_data->volt[id].label, mnb_label_volt[a2d_data->mlnx_system_type][id], MAX_LABEL_LEN);
		}

		for (id = 0; id < num_main_board_curr_sensors; id++) {
			a2d_data->curr[id].expect = mnb_expect_curr[a2d_data->mlnx_system_type][id];
			a2d_data->curr[id].scale = mnb_scale_curr[a2d_data->mlnx_system_type][id];
			a2d_data->curr[id].offset = mnb_offset_curr[a2d_data->mlnx_system_type][id];
			a2d_data->curr[id].rail = mnb_rail_curr[a2d_data->mlnx_system_type][id];
			memcpy(a2d_data->curr[id].label, mnb_label_curr[a2d_data->mlnx_system_type][id], MAX_LABEL_LEN);
		}
		break;

	case a2d_swb_drv:
		for (id = 0; id < num_sw_board_volt_sensors; id++) {
			a2d_data->volt[id].expect = swb_expect_volt[a2d_data->mlnx_system_type][id];
			a2d_data->volt[id].dev = swb_expect_volt_dev[a2d_data->mlnx_system_type][id];
			a2d_data->volt[id].scale = swb_scale_volt[a2d_data->mlnx_system_type][id];
			a2d_data->volt[id].offset = swb_offset_volt[a2d_data->mlnx_system_type][id];
			a2d_data->volt[id].rail = swb_rail_volt[a2d_data->mlnx_system_type][id];
			memcpy(a2d_data->volt[id].label, swb_label_volt[a2d_data->mlnx_system_type][id], MAX_LABEL_LEN);
		}

		for (id = 0; id < num_sw_board_curr_sensors; id++) {
			a2d_data->curr[id].expect = swb_expect_curr[a2d_data->mlnx_system_type][id];
			a2d_data->curr[id].scale = swb_scale_curr[a2d_data->mlnx_system_type][id];
			a2d_data->curr[id].offset = swb_offset_curr[a2d_data->mlnx_system_type][id];
			a2d_data->curr[id].rail = swb_rail_curr[a2d_data->mlnx_system_type][id];
			memcpy(a2d_data->curr[id].label, swb_label_curr[a2d_data->mlnx_system_type][id], MAX_LABEL_LEN);
		}
		break;

	default:
	    break;
	}

	a2d_data->base = cpld_lpc_base;

	return err;
}

static const struct i2c_device_id a2d_id[] = {
    { "mlnxa2d", a2d_drv },
    { "mlnxa2dmnb", a2d_mnb_drv },
    { "mlnxa2dswb", a2d_swb_drv },
    { }
};
MODULE_DEVICE_TABLE(i2c, a2d_id);

static int a2d_probe(struct i2c_client *client, const struct i2c_device_id *devid)
{
	int err = 0;
	struct a2d_data *data;
	const char buf1 = A2D_SETUP_BYTE;
	const char buf2 = A2D_CONFIG_BYTE;
	int mlnx_system_type;

	data = kzalloc(sizeof(struct a2d_data), GFP_KERNEL);
	if (!data) {
		err = -ENOMEM;
		goto exit;
	}
	i2c_set_clientdata(client, data);

	/* Check MLNX system type */
	mlnx_system_type = mlnx_check_system_type();
	switch (mlnx_system_type) {
	case msn2100_sys_type:
		data->mlnx_system_type = msn2100_sys_type;
		num_main_board_volt_sensors = VOLT_SENS_NUM_SFF;
		num_sw_board_volt_sensors = VOLT_SENS_SW_NUM_MSN2100;
		num_sw_board_curr_sensors = CURR_SENS_SW_NUM_MSN2100;
		num_main_board_curr_sensors = CURR_SENS_MAIN_NUM_MSN2100;
		break;

	case msn2740_sys_type:
		data->mlnx_system_type = msn2740_sys_type;
		num_main_board_volt_sensors = VOLT_SENS_NUM_SFF;
		num_sw_board_volt_sensors = VOLT_SENS_SW_NUM_MSN2740;
		break;

	case mlnx_dflt_sys_type:
	default:
		data->mlnx_system_type = mlnx_dflt_sys_type;
		num_main_board_volt_sensors = VOLT_SENS_NUM_DFLT;
		num_sw_board_volt_sensors = VOLT_SENS_SW_NUM_DFLT;
		break;
	}

	/* Register sysfs hooks */
	switch (devid->driver_data) {
	case a2d_drv:
	case a2d_mnb_drv:
        err = sysfs_create_group(&client->dev.kobj, &mlnx_mnb_a2d_group[data->mlnx_system_type]);
        if (err)
                goto exit_free;
        data->read_size = main_board_read_size;
		break;
	case a2d_swb_drv:
        err = sysfs_create_group(&client->dev.kobj, &mlnx_swb_a2d_group[data->mlnx_system_type]);
        if (err)
                goto exit_free;
        data->read_size = sw_board_read_size;
		break;
	default:
		break;
	}

	data->dev_id = devid->driver_data;
	data->hwmon_dev = hwmon_device_register(&client->dev);
#if defined(__i386__) || defined(__x86_64__)
	if (IS_ERR(data->hwmon_dev)) {
		err = PTR_ERR(data->hwmon_dev);
#else
		if (!data->hwmon_dev) {
			err = -ENODEV;
#endif
		goto exit_remove;
	}

	mutex_init(&data->access_lock);
	INIT_LIST_HEAD(&data->list);
	kref_init(&data->kref);
	a2d_config(data);
	list_add(&data->list, &a2d_db.list);

	err = i2c_master_send(client, &buf1, 1);
	err = i2c_master_send(client, &buf2, 1);

	printk(KERN_INFO "Registred mlnx_a2d driver at bus=%d addr=%x\n",
	       client->adapter->nr, client->addr);

	return 0;
exit_remove:
	switch (devid->driver_data) {
	case a2d_drv:
	case a2d_mnb_drv:
		sysfs_remove_group(&client->dev.kobj, &mlnx_mnb_a2d_group[data->mlnx_system_type]);
		break;
	case a2d_swb_drv:
		sysfs_remove_group(&client->dev.kobj, &mlnx_swb_a2d_group[data->mlnx_system_type]);
		break;
	}
exit_free:
	kfree(data);
exit:
	return err;
}

static int a2d_remove(struct i2c_client *client)
{
	struct a2d_data *data = i2c_get_clientdata(client);

	hwmon_device_unregister(data->hwmon_dev);
	switch (data->dev_id) {
	case a2d_drv:
	case a2d_mnb_drv:
		sysfs_remove_group(&client->dev.kobj, &mlnx_mnb_a2d_group[data->mlnx_system_type]);
		break;
	case a2d_swb_drv:
		sysfs_remove_group(&client->dev.kobj, &mlnx_swb_a2d_group[data->mlnx_system_type]);
		break;
	default:
		break;
	}

	if (!list_empty(&a2d_db.list)) {
		list_del_rcu(&data->list);
	}
	mutex_destroy(&data->access_lock);

	if(data)
		kfree(data);

    return 0;
}

static struct i2c_driver mlnx_a2d_drv = {
    .class          = I2C_CLASS_HWMON,
    .driver = {
            .name   = "mlnxa2d",
    },
    .probe          = a2d_probe,
    .remove         = a2d_remove,
    .id_table       = a2d_id,
};

static int __init mlnx_a2d_init(void)
{
	int err = 0;

	a2d_hwmon_dev = hwmon_device_register(NULL);
#if defined(__i386__) || defined(__x86_64__)
	if (IS_ERR(a2d_hwmon_dev)) {
		err = PTR_ERR(a2d_hwmon_dev);
#else
	if (!(a2d_hwmon_dev)) {
		err = -ENODEV;
#endif
		a2d_hwmon_dev = NULL;
		printk(KERN_ERR "a2d: hwmon registration failed (%d)\n", err);
		return err;
	}

	printk(KERN_INFO "%s Version %s\n", A2D_DRV_DESCRIPTION, A2D_DRV_VERSION);

	INIT_LIST_HEAD(&a2d_db.list);
	i2c_add_driver(&mlnx_a2d_drv);

	return err;
}

static void __exit mlnx_a2d_exit(void)
{
	struct a2d_data *data, *next;

	i2c_del_driver(&mlnx_a2d_drv);

	list_for_each_entry_safe(data, next, &a2d_db.list, list) {
		if (!list_empty(&a2d_db.list)) {
			mutex_destroy(&data->access_lock);
			list_del_rcu(&data->list);
			kfree(data);
		}
	}

	hwmon_device_unregister(a2d_hwmon_dev);
}

module_init(mlnx_a2d_init);
module_exit(mlnx_a2d_exit);
