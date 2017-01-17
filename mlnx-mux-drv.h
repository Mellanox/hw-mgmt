/*
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

#ifndef __MLNX_CPLD_MUX_DRV_H__
#define __MLNX_CPLD_MUX_DRV_H__

#define CPLD_MUX_DEVICE_NAME    "cpld_mux"

#define CPLD_MUX_MAX_NCHANS     8
#define CPLD_MUX_EXT_MAX_NCHANS 24

/* Platform data for the CPLD I2C multiplexers */

/* Per channel initialisation data:
 * @adap_id: bus number for the adapter. 0 = don't care
 * @deselect_on_exit: set this entry to 1, if your H/W needs deselection
 *                    of this channel after transaction.
 *
 */
struct cpld_mux_platform_mode {
	int		adap_id;
	unsigned int deselect_on_exit;
};

/* Per mux/switch data, used with i2c_register_board_info */
struct cpld_mux_platform_data {
	struct cpld_mux_platform_mode *modes;
	int num_modes;
    int id;
    int sel_reg_addr;
    int first_channel;
    unsigned short addr;
    struct kobject* mux_kobj;
    struct list_head dev_list;
};

struct cpld_mux_common_data {
    struct list_head head_list;
};

/*
 * 4 cpld_mux types:
 * cpld_mux_tor         - LPC access; 8 channels/legs; select/deselect  - channel=first defined channel(2/10) + channel/leg
 * cpld_mux_mgmt        - LPC access; 8 channels/legs; select/deselect  - channel=1 + channel/leg
 * cpld_mux_mgmt_ext    - LPC access; 24 channels/legs; select/deselect - channel=1 + channel/leg
 * cpld_mux_module      - I2C access; 8 channels/legs; select/deselect  - channel=1 + channel/leg
 */
enum cpld_mux_type {
	cpld_mux_tor,
	cpld_mux_mgmt,
	cpld_mux_mgmt_ext,
	cpld_mux_module,
};

enum mux_type {
    lpc_access,
    i2c_access,
};

struct cpld_mux {
	enum cpld_mux_type type;
	struct i2c_adapter *virt_adaps[CPLD_MUX_EXT_MAX_NCHANS];
	u8 last_chan;		/* last register value */
};

struct mux_desc {
	u8 nchans;
	enum mux_type muxtype;
};

#define CPLD_MUX_DBG_MAX_LVL      4
#define CPLD_MUX_DFLT_DBG_LVL     1
#define CPLD_MUX_LOG_ERROR(dev, format, args...) {\
    if (dev) {dev_err(dev, "[ERR] " format, ## args);} \
    else {printk(KERN_ERR "[ERR] " format, ## args);}}
#ifdef  CPLD_MUX_DEBUG
#define CPLD_MUX_LOG_DBG(level, dev, format, args...) {\
    if (dbg_lvl > 0 &&  dbg_lvl >= level) \
        {if (dev) {dev_info(dev, "[dbg] " format, ## args);} \
        else {printk("cpld_mux [dbg] " format, ## args);}}}
#else
#define CPLD_MUX_LOG_DBG(level, format, args...)
#endif

#endif /* __MLNX_CPLD_MUX_DRV_H__ */
