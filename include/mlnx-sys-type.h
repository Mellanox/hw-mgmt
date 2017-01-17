/**
 *
 * Copyright (C) Mellanox Technologies Ltd. 2001-2016.  ALL RIGHTS RESERVED.
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

#define SYS_TYPE     2

enum mlnx_system_types
{
    mlnx_dflt_sys_type,
    msn2100_sys_type,
};

const char* mlnx_product_names[] = {
    "DFLT",
    "MSN2100",
    NULL
};

static inline int mlnx_check_system_type(void)
{
    const char* product_name, * mlnx_product_name;
    enum mlnx_system_types mlnx_system_type = mlnx_dflt_sys_type;
    int idx = 1;

    mlnx_product_name = mlnx_product_names[idx];
    product_name = dmi_get_system_info(DMI_PRODUCT_NAME);
    if (product_name) {
        while (mlnx_product_name) {
            if (strstr(product_name, mlnx_product_name)) {
                mlnx_system_type = idx;
                break;
            }
            else {
                mlnx_product_name = mlnx_product_names[++idx];
            }
        }
    }
    return mlnx_system_type;
}
