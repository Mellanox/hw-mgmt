/*
 * SPDX-FileCopyrightText: Copyright (c) 2019-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
 * SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
 */

#ifndef __EV_HNDL_H__
#define __EV_HNDL_H__

#define HW_MGMT_PATH "/var/run/hw-management/"
#define CONFIG_PATH  HW_MGMT_PATH "config/"
#define EVENTS_PATH  HW_MGMT_PATH "events/"
#define PSU_NUM_FILE "hotplug_psus"
#define PWR_NUM_FILE "hotplug_pwrs"
#define FAN_NUM_FILE "hotplug_fans"

#define EVENT_IN  1
#define EVENT_OUT 0

#define EV_NAME_MAX_LEN 16
#define FPATH_MAX_LEN   256

struct ev_hndl_ev_info {
    int  wd;
    char fname[FPATH_MAX_LEN];
    char name[EV_NAME_MAX_LEN];
};

struct ev_hndl_priv_data {
    int                     ifd;
    struct ev_hndl_ev_info *ev_info;
    int                     psu_num;
    int                     pwr_num;
    int                     fan_num;
    int                     ev_num;
    long                    to;
};

#endif
