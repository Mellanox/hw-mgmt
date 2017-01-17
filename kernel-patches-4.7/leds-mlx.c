/*
 * drivers/leds/leds-mlx.c
 * Copyright (c) 2016 Mellanox Technologies. All rights reserved.
 * Copyright (c) 2016 Vadim Pasternak <vadimp@mellanox.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the names of the copyright holders nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * Alternatively, this software may be distributed under the terms of the
 * GNU General Public License ("GPL") version 2 as published by the Free
 * Software Foundation.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <linux/version.h>
#include <linux/acpi.h>
#include <linux/slab.h>
#include <linux/module.h>
#include <linux/device.h>
#include <linux/platform_device.h>
#include <linux/mod_devicetable.h>
#include <linux/dmi.h>
#include <linux/hwmon.h>
#include <linux/hwmon-sysfs.h>
#include <linux/leds.h>

#define BUS_ACCESS_BASE     0x2500 /* LPC bus access */

/* Color codes for leds */
#define LED_IS_OFF            0x00
#define LED_RED_STATIC_ON     0x05
#define LED_RED_BLINK_HALF    0x06
#define LED_GREEN_STATIC_ON   0x0D
#define LED_GREEN_BLINK_HALF  0x0E

/**
 * cpld_led_param -
 * @offset - offset for led access in CPLD device
 * @mask - mask for led access in CPLD device
 * @base_color - base color code for led
**/
struct cpld_led_param {
	u8 offset;
	u8 mask;
	u8 base_color;
};

/**
 * cpld_led_priv -
 * @led - led class device pointer
 * @param - led CPLD access parameters
**/
struct cpld_led_priv {
	struct led_classdev cdev;
	struct cpld_led_param param;
};
#define cdev_to_priv(c)		container_of(c, struct cpld_led_priv, cdev)

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
	u8 base_color;
	enum led_brightness brightness;
	const char *name;
};

/**
 * cpld_led_pdata -
 * @pdev - platform device pointer
 * @led - led class device pointer
 * @trigger - trigger class device pointer
 * @profile - system configuration profile
 * @num_led_instances - number of system triggers
 * @lock - device access lock
**/
struct cpld_led_pdata {
	struct platform_device *pdev;
	struct cpld_led_priv *pled;
	struct cpld_led_profile *profile;
	int num_led_instances;
	spinlock_t lock;
};
static struct cpld_led_pdata *cpld_led;

/* Default profile fit the next Mellanox systems:
 * "msx6710", "msx6720", "msb7700", "msn2700", "msx1410",
 * "msn2410", "msb7800", "msn2740"
 */
struct cpld_led_profile led_default_profile[] = {
	{
		0x21, 0xf0, LED_GREEN_STATIC_ON, LED_FULL, "fan1:green",
	},
	{
		0x21, 0xf0, LED_RED_STATIC_ON, LED_OFF, "fan1:red",
	},
	{
		0x21, 0x0f, LED_GREEN_STATIC_ON, LED_FULL, "fan2:green",
	},
	{
		0x21, 0x0f, LED_RED_STATIC_ON, LED_OFF, "fan2:red",
	},
	{
		0x22, 0xf0, LED_GREEN_STATIC_ON, LED_FULL, "fan3:green",
	},
	{
		0x22, 0xf0, LED_RED_STATIC_ON, LED_OFF, "fan3:red",
	},
	{
		0x22, 0x0f, LED_GREEN_STATIC_ON, LED_FULL, "fan4:green",
	},
	{
		0x22, 0x0f, LED_RED_STATIC_ON, LED_OFF, "fan4:red",
	},
	{
		0x20, 0x0f, LED_GREEN_STATIC_ON, LED_FULL, "psu:green",
	},
	{
		0x20, 0x0f, LED_RED_STATIC_ON, LED_OFF, "psu:red",
	},
	{
		0x20, 0xf0, LED_GREEN_STATIC_ON, LED_FULL, "status:green",
	},
	{
		0x20, 0xf0, LED_RED_STATIC_ON, LED_OFF, "status:red",
	},
};

/* Profile fit the Mellanox systems based on "msn2100" */
struct cpld_led_profile led_msn2100_profile[] = {
	{
		0x21, 0xf0, LED_GREEN_STATIC_ON, LED_FULL, "fan:green",
	},
	{
		0x21, 0xf0, LED_RED_STATIC_ON, LED_OFF, "fan:red",
	},
	{
		0x23, 0xf0, LED_GREEN_STATIC_ON, LED_FULL, "psu1:green",
	},
	{
		0x23, 0xf0, LED_RED_STATIC_ON, LED_OFF, "psu1:red",
	},
	{
		0x23, 0x0f, LED_GREEN_STATIC_ON, LED_FULL, "psu2:green",
	},
	{
		0x23, 0x0f, LED_RED_STATIC_ON, LED_OFF, "psu2:red",
	},
	{
		0x20, 0xf0, LED_GREEN_STATIC_ON, LED_FULL, "status:green",
	},
	{
		0x20, 0xf0, LED_RED_STATIC_ON, LED_OFF, "status:red",
	},
	{
		0x24, 0xf0, LED_GREEN_STATIC_ON, LED_OFF,  "uid:blue",
	},
};

static int __init mlx_dmi_msn2100_matched(const struct dmi_system_id *dmi)
{
	if (cpld_led) {
		cpld_led->profile = led_msn2100_profile;
		cpld_led->num_led_instances = ARRAY_SIZE(led_msn2100_profile);
	}
	return 1;
};

static const struct dmi_system_id mlx_dmi_table[] __initconst = {
	{
		.callback = mlx_dmi_msn2100_matched,
		.matches = {
			DMI_MATCH(DMI_PRODUCT_NAME, "MSN2100-CB2F"),
			DMI_MATCH(DMI_BOARD_VENDOR, "Mellanox Technologies"),
		},
	},
	{
		.callback = mlx_dmi_msn2100_matched,
		.matches = {
			DMI_MATCH(DMI_PRODUCT_NAME, "MSN2100-CB2R"),
			DMI_MATCH(DMI_BOARD_VENDOR, "Mellanox Technologies"),
		},
	},
	{
		.callback = mlx_dmi_msn2100_matched,
		.matches = {
			DMI_MATCH(DMI_PRODUCT_NAME, "MSN2100-CB2F0"),
			DMI_MATCH(DMI_BOARD_VENDOR, "Mellanox Technologies"),
		},
	},
	{
		.callback = mlx_dmi_msn2100_matched,
		.matches = {
			DMI_MATCH(DMI_PRODUCT_NAME, "MSN2100-CB2FE"),
			DMI_MATCH(DMI_BOARD_VENDOR, "Mellanox Technologies"),
		},
	},
};

#define LPC_RBUF(data, len, addr) {			\
	int i, nbyte, ndword;				\
	nbyte = len % 4;				\
	ndword = len / 4;				\
	for (i = 0; i < ndword; i++)			\
		outl(*((u32 *)data + i), addr + i*4);	\
	ndword *= 4;					\
	addr += ndword;					\
	data += ndword;					\
	for (i = 0; i < nbyte; i++)			\
		outb(*((u8 *)data + i), addr + i); }	\

#define LPC_WBUF(data, len, addr) {			\
	int i, nbyte, ndword;				\
	nbyte = len % 4;				\
	ndword = len / 4;				\
	for (i = 0; i < ndword; i++)			\
		*((u32 *)data + i) = inl(addr + i*4);	\
	ndword *= 4;					\
	addr += ndword;					\
	data += ndword;					\
	for (i = 0; i < nbyte; i++)			\
		*((u8 *)data + i) = inb(addr + i); }	\

static void bus_access_func(u16 base, u8 offset, int datalen, u8 rw_flag,
			    u8 *data)
{
	u32 addr = base + offset;

	if (rw_flag == 0) {
		switch (datalen) {
		case 4:
			outl(*((u32 *)data), addr);
			break;
		case 3:
			outw(*((u16 *)data), addr);
			outb(*((u8 *)data + 2), addr + 2);
			break;
		case 2:
			outw(*((u16 *)data), addr);
			break;
		case 1:
			outb(*((u8 *)data), addr);
			break;
		default:
			LPC_RBUF(data, datalen, addr);
			break;
		}
	} else {
		switch (datalen) {
		case 4:
			*((u32 *)data) = inl(addr);
			break;
		case 3:
			*((u16 *)data) = inw(addr);
			*((u8 *)(data + 2)) = inb(addr+2);
			break;
		case 2:
			*((u16 *)data) = inw(addr);
			break;
		case 1:
			*((u8 *)data) = inb(addr);
			break;
		default:
			LPC_WBUF(data, datalen, addr);
			break;
		}
	}
}

static void cpld_led_store_hw(u8 mask, u8 off, u8 vset)
{
	u8 tmask, val;

	spin_lock(&cpld_led->lock);
	tmask = (mask == 0xf0) ? vset : (vset << 4);
	bus_access_func(BUS_ACCESS_BASE, off, 1, 1, &val);
	val = (val & mask) | tmask;
	bus_access_func(BUS_ACCESS_BASE, off, 1, 0, &val);
	spin_unlock(&cpld_led->lock);
}

static void cpld_led_brightness(struct led_classdev *led,
				enum led_brightness value)
{
	struct cpld_led_priv *pled = cdev_to_priv(led);

	switch (value) {
	case LED_FULL:
	case LED_HALF:
	default:
		cpld_led_store_hw(pled->param.mask, pled->param.offset,
			     pled->param.base_color);
		break;
	case LED_OFF:
		cpld_led_store_hw(pled->param.mask, pled->param.offset,
			     LED_IS_OFF);
		break;
	}
}

static int cpld_led_blink(struct led_classdev *led, unsigned long *delay_on,
			  unsigned long *delay_off)
{
	struct cpld_led_priv *pled = cdev_to_priv(led);

	/* SW blinking is not supported.
	 * HW supports two types of blinking: full (6KHz) and half (3KHz).
	 * Defaul value is 3KHz, which is set for blink request.
	 */
	cpld_led_store_hw(pled->param.mask, pled->param.offset,
		     pled->param.base_color + 1);

	return 0;
}

static int cpld_led_config(struct device *dev, struct cpld_led_pdata *cpld)
{
	int err = 0, i;

	cpld->pled = devm_kzalloc(dev, sizeof(struct cpld_led_priv) *
				  cpld->num_led_instances, GFP_KERNEL);
	if (!cpld->pled)
		return -ENOMEM;

	for (i = 0; i < cpld->num_led_instances; i++) {
		cpld->pled[i].cdev.name = cpld->profile[i].name;
		cpld->pled[i].cdev.brightness = cpld->profile[i].brightness;
		cpld->pled[i].cdev.max_brightness = 1;
		cpld->pled[i].cdev.brightness_set = cpld_led_brightness;
		cpld->pled[i].cdev.blink_set = cpld_led_blink;
		cpld->pled[i].cdev.flags = LED_CORE_SUSPENDRESUME;
		err = devm_led_classdev_register(dev, &cpld->pled[i].cdev);
		if (err) {
			devm_kfree(dev, cpld->pled);
			return err;
		}

		cpld->pled[i].param.offset = cpld_led->profile[i].offset;
		cpld->pled[i].param.mask = cpld_led->profile[i].mask;
		cpld->pled[i].param.base_color =
					cpld_led->profile[i].base_color;
		switch (cpld_led->profile[i].brightness) {
		case LED_HALF:
		case LED_FULL:
			cpld_led_brightness(&cpld->pled[i].cdev,
					cpld_led->profile[i].brightness);
			break;
		default:
			break;
		}
	}

	return err;
}

static struct platform_driver cpld_led_driver = {
	.driver = {
		.name	= "mlxcpld",
	},
};

static int __init cpld_led_init(void)
{
	struct platform_device *pdev;
	struct device *dev;
	int err = 0;

	pdev = platform_device_alloc(cpld_led_driver.driver.name, 0);
	if (!pdev) {
		err = -ENOMEM;
		pr_err("Device allocation failed\n");
		goto exit;
	}
	err = platform_device_add(pdev);
	if (err)
		goto exit_device_put;
	err = platform_driver_register(&cpld_led_driver);
	if (err)
		goto exit_device_del;

	dev = &pdev->dev;
	cpld_led = devm_kzalloc(dev, sizeof(*cpld_led), GFP_KERNEL);
	if (!cpld_led)
		goto fail_init;
	cpld_led->pdev = pdev;

	if (!dmi_check_system(mlx_dmi_table)) {
		cpld_led->profile = led_default_profile;
		cpld_led->num_led_instances = ARRAY_SIZE(led_default_profile);
	}
	spin_lock_init(&cpld_led->lock);
	platform_set_drvdata(pdev, cpld_led);

	if (cpld_led_config(dev, cpld_led))
		goto fail_init;

	return err;

fail_init:
	platform_driver_unregister(&cpld_led_driver);
exit_device_del:
	platform_device_del(pdev);
exit_device_put:
	platform_device_put(pdev);
exit:
	return err;
}

static void __exit cpld_led_exit(void)
{
	platform_driver_unregister(&cpld_led_driver);
	platform_device_del(cpld_led->pdev);
	platform_device_put(cpld_led->pdev);
}

module_init(cpld_led_init);
module_exit(cpld_led_exit);

MODULE_AUTHOR("Vadim Pasternak (vadimp@mellanox.com)");
MODULE_DESCRIPTION("Mellanox board LED driver");
MODULE_LICENSE("GPL v2");
MODULE_ALIAS("platform:leds-mlx");
