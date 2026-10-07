/*
 * SPDX-FileCopyrightText: Copyright (c) 2020-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
 * SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
 */

#ifndef __IORW_H__
#define __IORW_H__

#define IO_WRITE          1
#define IO_READ           2
#define IO_DFLT_BASE_ADDR 0x2500     /* LPC_CPLD_BASE_ADRR */
#define LPC_CPLD_IO_LEN   0x100

struct iorw_region {
    unsigned short start;
    unsigned short end;
};

#define LPC_REGION_NUM         2
#define LPC_CPLD_I2C_BASE_ADRR 0x2000
#define LPC_CPLD_BASE_ADRR     0x2500

struct iorw_region lpc_regions[LPC_REGION_NUM] = {
    {
        .start = LPC_CPLD_I2C_BASE_ADRR,
        .end = LPC_CPLD_I2C_BASE_ADRR + LPC_CPLD_IO_LEN
    },
    {
        .start = LPC_CPLD_BASE_ADRR,
        .end = LPC_CPLD_BASE_ADRR + LPC_CPLD_IO_LEN
    }
};

#endif
