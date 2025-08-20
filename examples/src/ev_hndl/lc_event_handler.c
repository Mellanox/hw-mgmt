/*
 * SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
 * Copyright (c) 2001-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
 *
 * This software product is a proprietary product of Mellanox Technologies, Ltd.
 * (the "Company") and all right, title, and interest in and to the software product,
 * including all associated intellectual property rights, are and shall
 * remain exclusively with the Company.
 *
 * This software product is governed by the End User License Agreement
 * provided with the software product.
 *
 *  Sysfs event handle example.
 */
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <sys/inotify.h>
#include <sys/poll.h>
#include <sys/stat.h>
#include <unistd.h>


#define EVENT_SIZE (sizeof(struct inotify_event))
#define EVENT_NUM  128
#define BUF_LEN    (EVENT_SIZE * EVENT_NUM)
#define POWER_ON   1
/*#define LC1_VERIFIED_PATH "/var/run/hw-management/events/lc1_verified" */

int main(int argc, char *argv[])
{
    char   events_buffer[BUF_LEN];
    char * event_filepath;
    int    wd, ifd, len, i = 0;
    char   event_val;
    FILE * fd;

    if (argc != 2) {
        printf("Invalid argument number %d. Pass event filepath as argument.\n", argc);
    }
    event_filepath = argv[1];
    ifd = inotify_init();
    wd = inotify_add_watch(ifd, event_filepath, IN_CLOSE_WRITE);
    if (wd < 0) {
        printf("Failed to add file %s to watch, %s \n",
               event_filepath, strerror(errno));
        return -1;
    } else {
        while (1) {
            len = read(ifd, &events_buffer, BUF_LEN);
            i = 0;
            while (i < len) {
                struct inotify_event *event = (struct inotify_event *)&events_buffer[i];
                if (wd == event->wd) {
                    if (event->mask & IN_CLOSE_WRITE) {
                        fd = fopen(event_filepath, "r");
                        event_val = (char)fgetc(fd);
                        printf("event: %s %c.\n", event_filepath, event_val);
                        /* Do some event based action. For lc{n}_verifiled: */
                        /* Validation line card type, max power consumption, CPLD version, VPD, INI blob. */
                        /* Validate VPD /var/run/hw-management/lc1/eeprom/vpd. */
                        /* Validate INI /var/run/hw-management/lc1/eeprom/ini. */
                        /* Check /var/run/hw-management/lc1/system/max_power is enough power. */
                        /* Continue init flow - power on line card. */
                    }
                }
                i += EVENT_SIZE + event->len;
            }
        }
    }
    return (0);
}
