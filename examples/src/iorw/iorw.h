/*
 * Copyright (c) 2019 Mellanox Technologies. All rights reserved.
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
