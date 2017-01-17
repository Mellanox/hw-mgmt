/**
 * 
 * Copyright (C) 2010-2015, Mellanox Technologies Ltd.  ALL RIGHTS RESERVED.
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
#include <linux/init.h>
#include <linux/slab.h>
#include <linux/device.h>
#include <linux/i2c.h>
#include <linux/i2c-mux.h>
#include <asm/io.h>
#include <linux/platform_device.h>

#include "mlnx-mux-drv.h"

#define MUX_DRV_DESCRIPTION    "Mellanox MUX BSP driver. Build:" " "__DATE__" "__TIME__
#define MUX_DRV_VERSION        "0.0.1 20/08/2014"

static int dbg_lvl = CPLD_MUX_DFLT_DBG_LVL;
module_param(dbg_lvl, int, 0644);

struct cpld_mux_common_data* cpld_mux_comm_data = NULL;

static const struct mux_desc muxes[] = {
	[cpld_mux_tor] = {
		.nchans = CPLD_MUX_MAX_NCHANS,
		.muxtype = lpc_access,
	},
	[cpld_mux_mgmt] = {
		.nchans = CPLD_MUX_MAX_NCHANS,
		.muxtype = lpc_access,
	},
	[cpld_mux_mgmt_ext] = {
        .nchans = CPLD_MUX_EXT_MAX_NCHANS,
        .muxtype = lpc_access,
    },
	[cpld_mux_module] = {
		.nchans = CPLD_MUX_MAX_NCHANS,
		.muxtype = i2c_access,
	},
};

static const struct i2c_device_id cpld_mux_id[] = {
	{ "cpld_mux_tor", cpld_mux_tor },
	{ "cpld_mux_mgmt", cpld_mux_mgmt },
	{ "cpld_mux_mgmt_ext", cpld_mux_mgmt_ext },
	{ "cpld_mux_module", cpld_mux_module },
	{ }
};
MODULE_DEVICE_TABLE(i2c, cpld_mux_id);

/* Write to mux register. Don't use i2c_transfer()/i2c_smbus_xfer()
   for this as they will try to lock adapter a second time */
static int cpld_mux_reg_write(struct i2c_adapter *adap,
			     struct i2c_client *client, u8 val, enum mux_type muxtype)
{
	int ret = -ENODEV;
    struct cpld_mux_platform_data *pdata = dev_get_platdata(&client->dev);

    if (muxtype == lpc_access) {
        outb(val, pdata->addr); // Addr = CPLD base + offset
        CPLD_MUX_LOG_DBG(4, &client->dev, "LPC Write reg 0x%x val %d\n", pdata->addr, val);
        ret = 1;
    }
    else if (muxtype == i2c_access) {
        if (adap->algo->master_xfer) {
            struct i2c_msg msg;
            u8 msgbuf[] = {pdata->sel_reg_addr, val};

            msg.addr = pdata->addr;
            msg.flags = 0;
            msg.len = 2;
            msg.buf = msgbuf;
            ret = adap->algo->master_xfer(adap, &msg, 1);
        } else {
            CPLD_MUX_LOG_ERROR(&client->dev,
                    "SMBus isn't supported on this adapter\n");
        }
    }
    else
        CPLD_MUX_LOG_ERROR(&client->dev, "Incorrect muxtype %d\n", muxtype);

	return ret;
}

static int cpld_mux_select_chan(struct i2c_adapter *adap,
			       void *client, u32 chan)
{
	struct cpld_mux *data = i2c_get_clientdata(client);
	const struct mux_desc *mux = &muxes[data->type];
	u8 regval;
	int ret = 0;
    struct i2c_client* cl = (struct i2c_client*)client;
    struct cpld_mux_platform_data *pdata = dev_get_platdata(&cl->dev);

    switch(data->type) {
    case cpld_mux_tor:
        regval = pdata->first_channel + chan;
        break;
    case cpld_mux_mgmt:
    case cpld_mux_mgmt_ext:
    case cpld_mux_module:
        regval = chan + 1;
        break;
    default:
        return -ENXIO;
        break;
    }

    CPLD_MUX_LOG_DBG(3, &cl->dev, "%s client %s, type %d, select channel val %d, 1st chan %d, leg %d\n", \
                     cl->dev.kobj.name, cl->name, data->type, regval, pdata->first_channel, chan);
	/* Only select the channel if its different from the last channel */
	if (data->last_chan != regval) {
		ret = cpld_mux_reg_write(adap, client, regval, mux->muxtype);
		data->last_chan = regval;
	}

	return ret;
}

static int cpld_mux_deselect_mux(struct i2c_adapter *adap,
				void *client, u32 chan)
{
	struct cpld_mux *data = i2c_get_clientdata(client);
    const struct mux_desc *mux = &muxes[data->type];

    if (dbg_lvl >= 2){
        //struct i2c_client* cl = (struct i2c_client*)client;
        //struct cpld_mux_platform_data *pdata = dev_get_platdata(&cl->dev);
        CPLD_MUX_LOG_DBG(3, &cl->dev, "%s client %s, type %d, deselect channel, 1st chan %d, leg %d, \n", \
                         cl->dev.kobj.name, cl->name, data->type, pdata->first_channel, chan);
    }

	/* Deselect active channel */
	data->last_chan = 0;
	return cpld_mux_reg_write(adap, client, data->last_chan, mux->muxtype);
}

ssize_t show_channel(struct device *dev, struct device_attribute *attr, char *buf)
{
    ssize_t rc;
    struct i2c_client *client;
    struct cpld_mux_platform_data* pdata;
    struct cpld_mux *data;

    pdata = dev_get_platdata(dev);
    client = container_of(dev, struct i2c_client, dev);
    data = i2c_get_clientdata(client);
    rc = sprintf(buf, "CPLD_MUX 0x%x last selected channel: %d\n", \
                     pdata->id, data->last_chan);

    return rc+1;
}

ssize_t store_channel(struct device *dev, struct device_attribute *attr, const char *buf, size_t cnt)
{
    int rc;
    u32 chan, prev_chan;
    struct i2c_client *client;
    struct i2c_adapter *adap;
    struct cpld_mux_platform_data* pdata;
    struct cpld_mux *data;

    pdata = dev_get_platdata(dev);
    client = container_of(dev, struct i2c_client, dev);
    if (!buf || cnt == 1) {
        CPLD_MUX_LOG_ERROR(&client->dev, "Incorrect empty str input\n");
        return cnt;
    }
    data = i2c_get_clientdata(client);
    adap = to_i2c_adapter(&(client->dev));

    prev_chan = data->last_chan;
    chan = (u32)simple_strtol(buf, NULL, 10);
    rc = cpld_mux_select_chan(adap, client, chan);
    if (rc < 0) {
        CPLD_MUX_LOG_DBG(1, &client->dev, "0x%x change channel %d failed\n", \
                         pdata->id, chan);
    }
    else {
        CPLD_MUX_LOG_DBG(1, &client->dev, "0x%x last selected channel changed from %d to %d\n", \
                         pdata->id, prev_chan, chan);
    }

    return cnt;
}

static DEVICE_ATTR(channel, 0644, show_channel, store_channel);

static struct attribute *cpld_mux_attrs[] = {
    &dev_attr_channel.attr,
	NULL
};

static struct attribute_group cpld_mux_attr_grp = {
    .attrs = cpld_mux_attrs
};

int cpld_mux_sysfs_device_create(struct device* dev)
{
    struct cpld_mux_platform_data* pdata = dev_get_platdata(dev);

	if (sysfs_create_group(&(dev->kobj), &cpld_mux_attr_grp)) {
        CPLD_MUX_LOG_ERROR(dev, "Failed to create sysfs cpld_mux group\n");
        pdata->mux_kobj = NULL;
		return -EACCES;
    }
    pdata->mux_kobj = &(dev->kobj);

    return 0;
}

void cpld_mux_sysfs_device_delete(struct cpld_mux_platform_data *pdata)
{
    if (pdata->mux_kobj)
        sysfs_remove_group(pdata->mux_kobj, &cpld_mux_attr_grp);

    pdata->mux_kobj = NULL;
}

/*
 * I2C init/probing/exit functions
 */
static int cpld_mux_probe(struct i2c_client *client,
			 const struct i2c_device_id *id)
{
	struct i2c_adapter *adap = to_i2c_adapter(client->dev.parent);
	struct cpld_mux_platform_data *pdata = dev_get_platdata(&client->dev);
	int num, force;
	struct cpld_mux *data;
	int ret = -ENODEV;

	CPLD_MUX_LOG_DBG(2, &client->dev, "client %s probe\n", client->name);
	if (!i2c_check_functionality(adap, I2C_FUNC_SMBUS_BYTE))
		goto err;

	data = kzalloc(sizeof(struct cpld_mux), GFP_KERNEL);
	if (!data) {
		ret = -ENOMEM;
		goto err;
	}

	i2c_set_clientdata(client, data);

	data->type = id->driver_data;
	data->last_chan = 0;		   /* force the first selection */

	/* Only in cpld_mux_tor first_channel can be different.
	 * In other cpld_mux types channel numbering begin from 1 */
	/*if (data->type != cpld_mux_tor)
	    pdata->first_channel = 1;*/

	/* Now create an adapter for each channel */
	for (num = 0; num < muxes[data->type].nchans; num++) {
	    CPLD_MUX_LOG_DBG(3, &adap->dev,"%s name %s nr=%d num=%d (%d)", __FUNCTION__,
	            adap->name, adap->nr, num, pdata->num_modes);
		force = 0;			  /* dynamic adap number */
		// class = 0;			  /* no class by default */
		if (pdata) {
			if (num < pdata->num_modes) {
				/* force static number */
				/* force = pdata->modes[num].adap_id; */
				force = pdata->first_channel + num;
				// class = pdata->modes[num].class;
			} else
				/* discard unconfigured channels */
				break;
		}

		data->virt_adaps[num] =
			i2c_add_mux_adapter(adap, &client->dev, client,
				force, num, 0, cpld_mux_select_chan,
				(pdata && pdata->modes[num].deselect_on_exit)
					? cpld_mux_deselect_mux : NULL);

		if (data->virt_adaps[num] == NULL) {
			ret = -ENODEV;
			CPLD_MUX_LOG_ERROR(&client->dev,
				"failed to register multiplexed adapter"
				" %d as bus %d\n", num, force);
			goto virt_reg_failed;
		}
        else {
            CPLD_MUX_LOG_DBG(2, &client->dev, "Added i2c addapter, num %d, deselect %s, force %d, name %s, parent name %s\n", \
                             num, (pdata && pdata->modes[num].deselect_on_exit) ? "yes" : "no", \
                             force, data->virt_adaps[num]->name, adap->name);
        }
	}
    if (cpld_mux_sysfs_device_create(&(client->dev))) {
        ret = -ENODEV;
        CPLD_MUX_LOG_ERROR(&client->dev, "failed create sysfs for cpld_mux_%x\n", pdata->id);
        goto virt_reg_failed;
    }
    else {
        //list_add(&(pdata->dev_list), &(cpld_mux_comm_data->head_list));
    }

	CPLD_MUX_LOG_DBG(1, &client->dev, "Registered %d multiplexed busses for %s, id 0x%x\n", num, client->name, pdata->id);

	return 0;

virt_reg_failed:
	for (num--; num >= 0; num--)
		i2c_del_mux_adapter(data->virt_adaps[num]);
	kfree(data);
err:
    kfree(pdata);
	return ret;
}

static int cpld_mux_remove(struct i2c_client *client)
{
	struct cpld_mux *data = i2c_get_clientdata(client);
	const struct mux_desc *mux = &muxes[data->type];
	struct cpld_mux_platform_data *pdata = dev_get_platdata(&client->dev);
	int num;

	CPLD_MUX_LOG_DBG(2, &client->dev, "client %s remove\n", client->name);
	for (num = 0; num < mux->nchans; ++num) {
		if (data->virt_adaps[num]) {
		    CPLD_MUX_LOG_DBG(2, &client->dev, "%s chan %d, adapter %s\n", __FUNCTION__, num, data->virt_adaps[num]->name);
			i2c_del_mux_adapter(data->virt_adaps[num]);
			data->virt_adaps[num] = NULL;
		}
	}
	CPLD_MUX_LOG_DBG(1, &client->dev, "Unregistered %d multiplexed busses for %s, id 0x%x\n", num, client->name, pdata->id);
	cpld_mux_sysfs_device_delete(pdata);

	if (!list_empty(&cpld_mux_comm_data->head_list)) {
		//list_del_rcu(&pdata->dev_list);
		kfree(pdata);
	}

	kfree(data);

	return 0;
}

static struct i2c_driver cpld_mux_driver = {
	.driver		= {
		.name	= "mlnx-mux-drv",
		.owner	= THIS_MODULE,
	},
	.probe		= cpld_mux_probe,
	.remove		= cpld_mux_remove,
	.id_table	= cpld_mux_id,
};

static int __init cpld_mux_init(void)
{
    int rc;

    cpld_mux_comm_data = kzalloc(sizeof(struct cpld_mux_common_data), GFP_KERNEL);
    if (!cpld_mux_comm_data) {
        CPLD_MUX_LOG_ERROR(NULL, "Alloc cpld_mux_common_data failed\n");
        return -ENOMEM;
    }

    INIT_LIST_HEAD(&(cpld_mux_comm_data->head_list));

	rc = i2c_add_driver(&cpld_mux_driver);
    if (rc) {
        CPLD_MUX_LOG_ERROR(NULL, "Add %s i2c driver failed (%d)\n", CPLD_MUX_DEVICE_NAME, rc);
        kfree(cpld_mux_comm_data);
        return rc;
    }

    printk(KERN_INFO "%s Version %s\n", MUX_DRV_DESCRIPTION, MUX_DRV_VERSION);

    return rc;
}

static void __exit cpld_mux_exit(void)
{
    struct cpld_mux_platform_data* curr, *next;

    list_for_each_entry_safe(curr, next, &(cpld_mux_comm_data->head_list), dev_list) {
        cpld_mux_sysfs_device_delete(curr);
    }

    kfree(cpld_mux_comm_data);
	i2c_del_driver(&cpld_mux_driver);
}

module_init(cpld_mux_init);
module_exit(cpld_mux_exit);

MODULE_AUTHOR("Mellanox Technologies (Michael Shych)");
MODULE_DESCRIPTION(MUX_DRV_DESCRIPTION);
MODULE_VERSION(MUX_DRV_VERSION);
MODULE_LICENSE("GPL v2");

MODULE_PARM_DESC(dbg_lvl, " debug level, 0-4, 0 - disabled, 1 - default");




