########################################################################
# Copyright (c) 2019 Mellanox Technologies. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#######################################################################


#include <stdio.h>
#include <stdlib.h>
#include <sys/io.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "iorw.h"

static int io_open_access(void)
{
    if (iopl(3) < 0) {
        return -1;
    } else {
        return 0;
    }
}

#if DYNAMIC_REGION_FIND
static int io_get_regions(struct iorw_region** regions)
{
    int                 i, fd, reg_num, rc = 1;
    char                buf[512], *tmp;
    char                str[128];
    FILE               *fp;
    unsigned short      start, end;
    struct iorw_region* region;

    /* Check that file exist */
    fd = open(LPC_IO_REGION_FILE, O_RDONLY, 0444);
    if (fd < 0) {
        fprintf(stderr, "Failed to open LPC region info file %s, %s\n", \
                LPC_IO_REGION_FILE, strerror(errno));
        return -1;
    }

    if (read(fd, buf, sizeof(buf)) > 0) {
        /* Find number of IO regions */
        snprintf(str, "IO regions num:");
        tmp = strstr(buf, str);
        if (tmp) {
            tmp += (strlen(str) + 1);
            reg_num = atoi(tmp);
        } else {
            fprintf(stderr, "Failed to find lpc region numbers\n");
            goto fail_parsing;
        }
        *regions = calloc(sizeof(struct iorw_region), reg_num);
        if (!(*regions)) {
            fprintf(stderr, "Failed to allocate io regions data\n");
            goto fail_parsing;
        }
        for (i = 0; i < reg_num; i++) {
            snprintf(str, 128, "IO region%d:", i);
            tmp = strstr(buf, str);
            if (!tmp) {
                fprintf(stderr, "Failed to find %s\n", str);
                goto fail_parsing;
            }
            tmp += strlen(str) + 1;
            start = strtol(tmp, (char**)NULL, 16);
            tmp = strchr(tmp, '-');
            if (!tmp) {
                fprintf(stderr, "Failed to find end of %s\n", str);
                goto fail_parsing;
            }
            tmp += 1;
            end = strtol(tmp, (char**)NULL, 16);
            region = *regions + i;
            region->start = start;
            region->end = end;
        }
        rc = reg_num;
    } else {
        fprintf(stderr, "Failed read %s\n", LPC_IO_REGION_FILE);
    }
    close(fd);
    return rc;

fail_parsing:
    close(fd);
    if (*regions) {
        free(*regions);
    }
    return rc;
}
#endif /* if DYNAMIC_REGION_FIND */

static int io_check_region_range(unsigned short base_adrr, unsigned short offs, unsigned short len)
{
    int i, rc = 0;
    int low_lim, high_lim;

    low_lim = base_adrr + offs;
    high_lim = base_adrr + offs + len;

#if DYNAMIC_REGION_FIND
    for (i = 0; i < lpc_reg_num; i++) {
        if ((low_lim < lpc_regions[i].start) ||
            (high_lim > lpc_regions[i].end)) {
            rc = -1;
        } else {
            return 0;
        }
    }
#else
    for (i = 0; i < LPC_REGION_NUM; i++) {
        if ((low_lim < lpc_regions[i].start) ||
            (high_lim > lpc_regions[i].end)) {
            rc = -1;
        } else {
            return 0;
        }
    }
#endif

    return rc;
}

static void io_read(int addr, int len, unsigned char* data)
{
    int           i;
    unsigned char rem = 0, widx = 0;

    switch (len) {
    case 1:
        *((unsigned char*)data) = inb(addr);
        break;

    case 2:
        *((unsigned short*)data) = inw(addr);
        break;

    case 3:
        *((unsigned short*)data) = inw(addr);
        *((unsigned char*)(data + 2)) = inb(addr + 2);
        break;

    case 4:
        *((unsigned int*)data) = inl(addr);
        break;

    default:
        rem = len % 4;
        widx = len / 4;
        for (i = 0; i < widx; i++) {
            *((unsigned int*)data + i) = inl(addr + i * 4);
        }
        for (i = 0; i < rem; i++) {
            *((unsigned char*)data + widx * 4 + i) = inb(addr + widx * 4 + i);
        }
        break;
    }
}

static void io_write(int addr, int len, unsigned char* data)
{
    int           i;
    unsigned char rem = 0, widx = 0;

    switch (len) {
    case 1:
        outb(*((unsigned char*)data), addr);
        break;

    case 2:
        outw(*((unsigned short*)data), addr);
        break;

    case 3:
        outw(*((unsigned short*)data), addr);
        outb(*((unsigned char*)data + 2), addr + 2);
        break;

    case 4:
        outl(*((unsigned int*)data), addr);
        break;

    default:
        rem = len % 4;
        widx = len / 4;
        for (i = 0; i < widx; i++) {
            outl(*((unsigned int*)data + i), addr + i * 4);
        }
        for (i = 0; i < rem; i++) {
            outb(*((unsigned char*)data + widx * 4 + i), addr + widx * 4 + i);
        }
        break;
    }
}

static int io_store_data(int len, unsigned char* data, char* fname)
{
    int fd;

    fd = open(fname, O_CREAT | O_TRUNC | O_RDWR | O_SYNC, 0666);
    if (fd < 0) {
        fprintf(stderr, "Failed to open file %s, %s\n", fname, strerror(errno));
        return -1;
    }
    write(fd, data, len);
    close(fd);
    return 0;
}

static void io_print_data(int addr, int len, unsigned char* data)
{
    int            i;
    unsigned short reg = addr;

    if (len == 1) {
        printf("IO reg 0x%04x = 0x%02x\n", addr, (unsigned int)*data);
    } else {
        for (i = 0; i < len; i++, reg++, data++) {
            if (!(i % 16)) {
                printf("\n0x%04x:\t%02x ", reg, *data);
            } else {
                printf("%02x ", *data);
            }
        }
        printf("\n");
    }
}

static void io_help(void)
{
    printf("iorw -r/w [-b <base_addr>] [-o <offset>] [-l <len>] [-v <value>] [-f <filename>] [-F] [-q] [-h]\n");
    printf("r - read or w -write option should be provided\n");
    printf("b - base_addr, can be omitted, default: 0x%x", IO_DFLT_BASE_ADDR);
    printf("o - offset, can be omitted, default: 0\n");
    printf("l - length, can be omitted only in read - full dump in this case\n");
    printf("v - value for write operation\n");
    printf("f - file to store output values\n");
    printf("F - force, don't check region ranges\n");
    printf("q - quiet, can be used only with f option, store in file without print\n");
    printf("h - this help\n");
}

int main(int argc, char *argv[])
{
    int            i, addr, opt, rc = 0;
    unsigned short offs = 0, base_addr = IO_DFLT_BASE_ADDR;
    unsigned short len = LPC_CPLD_IO_LEN;
    char           io_opt = 0, val_opt = 0, f_opt = 0, force = 0, quiet = 0;
    char         * tmp;
    unsigned char* data = NULL;
    unsigned long  val;
    char           fname[128];

    if (argc < 2) {
        fprintf(stderr, "Incorrect number of parameters, should be at least 2\n");
        io_help();
        exit(-1);
    }

    while ((opt = getopt(argc, argv, "o:b:l:v:f:rwFqh")) != -1) {
        switch (opt) {
        case 'o':
            offs = strtod(optarg, &tmp);
            break;

        case 'b':
            base_addr = strtod(optarg, &tmp);
            break;

        case 'l':
            len = strtod(optarg, &tmp);
            break;

        case 'v':
            val = strtod(optarg, &tmp);
            val_opt = 1;
            break;

        case 'r':
            io_opt = IO_READ;
            break;

        case 'w':
            io_opt = IO_WRITE;
            break;

        case 'h':
            io_help();
            break;

        case 'F':
            force = 1;
            break;

        case 'q':
            quiet = 1;
            break;

        case 'f':
            strncpy(fname, optarg, 127);
            fname[127] = '\0';
            f_opt = 1;
            break;

        default:
            fprintf(stderr, "Incorrect option input %c\n", opt);
            io_help();
            exit(-1);
            break;
        }
    }

    if (!io_opt) {
        fprintf(stderr, "Read/write option is not specified\n");
        io_help();
        exit(-1);
    }

#if DYNAMIC_REGION_FIND
    lpc_reg_num = io_get_regions(&lpc_regions);
    if (lpc_reg_num <= 0) {
        fprintf(stderr, "Failed to find io regions\n");
        rc = -1;
        goto fail;
    } else {
        for (i = 0; i < lpc_reg_num; i++) {
            printf("Found LPC region %d: start 0x%x - end 0x%x\n", \
                   i, lpc_regions[i].start, lpc_regions[i].end);
        }
    }
#endif

    if (!force) {
        if (offs >= LPC_CPLD_IO_LEN) {
            fprintf(stderr, "Incorrect offset %d, should be <= %d\n", \
                    offs, LPC_CPLD_IO_LEN);
            rc = -1;
            goto fail;
        }
        if (io_check_region_range(base_addr, offs, len)) {
            fprintf(stderr, "Incorrect region range: base = 0x%x, offs = 0x%x, len = 0x%x\n", \
                    base_addr, offs, len);
            rc = -1;
            goto fail;
        }
    }

    if (io_open_access()) {
        fprintf(stderr, "Failed to change I/O level, %s\n", strerror(errno));
        rc = -1;
        goto fail;
    }

    addr = base_addr + offs;

    if (io_opt == IO_READ) {
        data = calloc(sizeof(char), len);
        if (data) {
            io_read(addr, len, data);
            if (f_opt) {
                if (!quiet) {
                    io_print_data(addr, len, data);
                }
                rc = io_store_data(len, data, fname);
                if (rc) {
                    fprintf(stderr, "Data wasn't stored in file %s\n", fname);
                }
            } else {
                io_print_data(addr, len, data);
            }
        } else {
            fprintf(stderr, "Failed allocate buffer for read\n");
            rc = -1;
        }
        free(data);
    } else if (io_opt == IO_WRITE) {
        if (val_opt < 0) {
            fprintf(stderr, "Value should be provided for write operation\n");
            io_help();
            rc = -1;
            goto fail;
        }
        io_write(addr, len, (unsigned char*)(&val));
    } else {
        fprintf(stderr, "Read or Write operation not defined.\n");
        io_help();
        rc = -1;
        goto fail;
    }

    if (rc) {
        fprintf(stderr, "IO operation failed\n");
    }

fail:
#if DYNAMIC_REGION_FIND
    if (lpc_regions) {
        free(lpc_regions);
    }
#endif
    exit(rc);
}
