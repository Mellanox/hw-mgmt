/*
 * SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
 * Copyright (c) 2019-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
#include "ev_hndl.h"

static void ev_hndl_help(const char *prog_name)
{
    printf("%s [-t <sec>] [-h]\n", prog_name);
    printf("t - wait number of seconds for events.\n");
    printf("h - this help\n");
}

static inline int ev_hndl_check_file_exist(char *fname)
{
    struct stat tmp;

    return (stat(fname, &tmp) == 0);
}

static int ev_hndl_read_config_file(char *fname)
{
    int   fd, rc = -1;
    char  buff[5];
    char *tmp;

    if (!ev_hndl_check_file_exist(fname)) {
        return -1;
    }

    fd = open(fname, O_RDONLY, 0444);
    if (fd < 0) {
        syslog(LOG_ERR, "Failed to open file %s, %s",
               fname, strerror(errno));
        return -1;
    }
    if (read(fd, buff, 4) < 0) {
        syslog(LOG_ERR, "Failed to read file %s, %s",
               fname, strerror(errno));
    } else {
        rc = strtol(buff, &tmp, 0);
    }

    close(fd);
    return rc;
}

/*
 * Success return number of read bytes, failure: -1
 * Passed val is -1 in case of failure or empty file.
 */
static int ev_hndl_read_event_file(struct ev_hndl_ev_info *ev_info, int *val)
{
    int   fd, rc;
    char  buff[5];
    char *tmp;

    *val = -1;
    fd = open(ev_info->fname, O_RDONLY, 0444);
    if (fd < 0) {
        syslog(LOG_ERR, "Failed to open file %s, %s",
               ev_info->fname, strerror(errno));
        return -1;
    }
    rc = read(fd, buff, 4);
    close(fd);

    /* 0 is valid rc, nothing still written to event file */
    if (rc < 0) {
        syslog(LOG_ERR, "Failed to read file %s, %s",
               ev_info->fname, strerror(errno));
    } else if (rc > 0) {
        errno = 0;
        *val = strtol(buff, &tmp, 0);
        if (((errno == ERANGE) && ((*val == LONG_MAX) || (*val == LONG_MIN)))
            || ((errno != 0) && (*val == 0))) {
            rc = -1;
            *val = -1;
        }
    } else { /* rc == 0 */
        *val = -1;
    }

    return rc;
}

static int ev_hndl_check_ev_num(struct ev_hndl_priv_data *data)
{
    char fname[FPATH_MAX_LEN];
    int  rc, ev_num = 0;

    sprintf(fname, "%s/%s", CONFIG_PATH, PSU_NUM_FILE);
    rc = ev_hndl_read_config_file(fname);
    if (rc > 0) {
        data->psu_num = rc;
        ev_num += rc;
    }

    sprintf(fname, "%s/%s", CONFIG_PATH, PWR_NUM_FILE);
    rc = ev_hndl_read_config_file(fname);
    if (rc > 0) {
        data->pwr_num = rc;
        ev_num += rc;
    }

    sprintf(fname, "%s/%s", CONFIG_PATH, FAN_NUM_FILE);
    rc = ev_hndl_read_config_file(fname);
    if (rc > 0) {
        data->fan_num = rc;
        ev_num += rc;
    }

    return ev_num;
}

static int ev_hndl_add_event(struct ev_hndl_priv_data *data, char *name, int idx, int ev_idx)
{
    int                     wd;
    char                    fname[FPATH_MAX_LEN];
    struct ev_hndl_ev_info *ev_info;

    sprintf(fname, "%s/%s%d", EVENTS_PATH, name, idx);
    if (!ev_hndl_check_file_exist(fname)) {
        syslog(LOG_ERR, "File %s doesn't exist.", fname);
        return -1;
    }

    wd = inotify_add_watch(data->ifd, fname, IN_CLOSE_WRITE);
    if (wd < 0) {
        syslog(LOG_ERR, "Failed to add file %s to watch, %s",
               fname, strerror(errno));
        return -1;
    } else {
        ev_info = data->ev_info + ev_idx;
        ev_info->wd = wd;
        sprintf(ev_info->name, "%s%d", name, idx);
        strncpy(ev_info->fname, fname, FPATH_MAX_LEN - 1);
        return 0;
    }
}

static int ev_hndl_init(struct ev_hndl_priv_data *data)
{
    int ev_num, fd, i, rc, ev_idx = 0;

    ev_num = ev_hndl_check_ev_num(data);
    if (!ev_num) {
        syslog(LOG_ERR, "No hotplug events on system. Exit.");
        return -1;
    }

    fd = inotify_init();
    if (fd < 0) {
        syslog(LOG_ERR, "Failed to init inotify.");
        return -1;
    }
    data->ifd = fd;

    data->ev_info = calloc(ev_num, sizeof(struct ev_hndl_ev_info));
    if (!data->ev_info) {
        syslog(LOG_ERR, "Failed allocate ev_info, %s",
               strerror(errno));
        goto fail;
    }

    /* Add PSU hotplug events */
    for (i = 1; i <= data->psu_num; i++) {
        rc = ev_hndl_add_event(data, "psu", i, ev_idx);
        if (rc == 0) {
            ev_idx++;
        }
    }

    /* Add PWR cable hotplug events */
    for (i = 1; i <= data->pwr_num; i++) {
        rc = ev_hndl_add_event(data, "pwr", i, ev_idx);
        if (rc == 0) {
            ev_idx++;
        }
    }

    /* Add FAN hotplug events */
    for (i = 1; i <= data->fan_num; i++) {
        rc = ev_hndl_add_event(data, "fan", i, ev_idx);
        if (rc == 0) {
            ev_idx++;
        }
    }
    /* TBD Check if not equal, fail / continue */

    if (!ev_idx) {
        syslog(LOG_ERR, "No event was added.");
        goto fail;
    } else {
        data->ev_num = ev_idx;
        return 0;
    }

fail:
    close(data->ifd);
    return -1;
}

static void ev_hndl_close(struct ev_hndl_priv_data *data)
{
    int                     i;
    struct ev_hndl_ev_info *ev_info;

    for (i = 0; i < data->ev_num; i++) {
        ev_info = data->ev_info + i;
        inotify_rm_watch(data->ifd, ev_info->wd);
    }
    free(data->ev_info);

    close(data->ifd);
}

static struct ev_hndl_ev_info* ev_hndl_find_ev(struct ev_hndl_priv_data *data, int wd)
{
    int                     i;
    struct ev_hndl_ev_info *ev_info;

    for (i = 0; i < data->ev_num; i++) {
        ev_info = data->ev_info + i;
        if (ev_info->wd == wd) {
            return ev_info;
        }
    }

    return NULL;
}

/*
 * This is example of event handler: just report to system log.
 * Could be replaced to more useful handler function.
 */
static int ev_hndl_ev_handler(struct ev_hndl_priv_data *data, struct ev_hndl_ev_info *ev_info)
{
    int rc, event;

    rc = ev_hndl_read_event_file(ev_info, &event);

    if (rc < 0) {
        syslog(LOG_ERR, "Failed to read file %s, %s",
               ev_info->fname, strerror(errno));
    } else if (event >= 0) {
        syslog(LOG_NOTICE, "Received event: %s %s", ev_info->name,
               (event == EVENT_OUT ? "out" : "in"));
    }

    return rc;
}

static int ev_hndl_process_events(struct ev_hndl_priv_data *data, int ev_cnt, struct inotify_event *events)
{
    int                     i, rc = 0;
    struct inotify_event   *curr_ev;
    struct ev_hndl_ev_info *ev_info;

    for (i = 0; i < ev_cnt; i++) {
        curr_ev = events + i;
        ev_info = ev_hndl_find_ev(data, curr_ev->wd);
        if (!ev_info) {
            /* Should not happen. */
            syslog(LOG_ERR, "Failed to find registered event for wd %d, %s",
                   curr_ev->wd, strerror(errno));
            continue;
        }
        /* TBD Process other events or fail */
        rc = ev_hndl_ev_handler(data, ev_info);
    }

    return rc;
}

static int ev_hndl_check_events_init_state(struct ev_hndl_priv_data *data)
{
    struct ev_hndl_ev_info *ev_info;
    int                     i, rc;

    for (i = 0; i < data->ev_num; i++) {
        ev_info = data->ev_info + i;
        rc = ev_hndl_ev_handler(data, ev_info);
        if (rc < 0) {
            break;
        }
    }

    return rc;
}

static int ev_hndl_wait_event(struct ev_hndl_priv_data *data)
{
    struct inotify_event *events;
    struct pollfd         pfd;
    int                   ev_cnt, len, max_len, rc = 0, run = 1;

    events = calloc(data->ev_num, sizeof(struct inotify_event));
    if (!events) {
        syslog(LOG_ERR, "Failed allocate events data, %s",
               strerror(errno));
        return -1;
    }
    max_len = data->ev_num * sizeof(struct inotify_event);

    do {
        /* poll is used just for timeout support.
         *  Wait directly on read if timeout isn't required. */
        pfd.fd = data->ifd;
        pfd.events = POLLIN;
        rc = poll(&pfd, 1, data->to);
        if (rc < 0) {
            syslog(LOG_ERR, "Failed poll, %s",
                   strerror(errno));
            goto fail;
        }
        if ((rc == 0) && (data->to != -1)) {
            syslog(LOG_NOTICE, "No events received, exit by timeout %ld (sec).\n",
                   data->to / 1000);
            goto fail;
        }
        if (pfd.revents != POLLIN) {
            syslog(LOG_ERR, "Unexpected event %d", pfd.revents);
            continue;
        }

        len = read(data->ifd, events, max_len);
        ev_cnt = len / sizeof(struct inotify_event);
        rc = ev_hndl_process_events(data, ev_cnt, events);
        if (rc < 0) {
            syslog(LOG_ERR, "Failed to process events.");
            run = 0;
        }
    } while (run);

fail:
    free(events);
    return rc;
}

int main(int argc, char *argv[])
{
    char                     *prog_name;
    struct ev_hndl_priv_data *ev_hndl_data;
    char                     *tmp;
    int                       opt, to = -1;
    int                       rc = 0;

    prog_name = argv[0];
    openlog(prog_name, LOG_CONS | LOG_PID | LOG_NDELAY, LOG_USER);

    while ((opt = getopt(argc, argv, "t:s:oh")) != -1) {
        switch (opt) {
        case 't':
            to = strtol(optarg, &tmp, 0);
            break;

        case 'h':
            ev_hndl_help(prog_name);
            exit(0);

        default:
            syslog(LOG_ERR, "Incorrect option input %c\n", opt);
            ev_hndl_help(prog_name);
            exit(-1);
        }
    }

    ev_hndl_data = calloc(1, sizeof(struct ev_hndl_priv_data));
    if (!ev_hndl_data) {
        syslog(LOG_ERR, "Failed allocate ev_hndl data, %s",
               strerror(errno));
        exit(-1);
    }

    if (to > 0) {
        ev_hndl_data->to = to * 1000;
    } else {
        ev_hndl_data->to = -1;
    }

    rc = ev_hndl_init(ev_hndl_data);
    if (rc < 0) {
        syslog(LOG_ERR, "Failed init.\n");
        goto fail_init;
    }

    syslog(LOG_NOTICE, "Check events initial state.");
    rc = ev_hndl_check_events_init_state(ev_hndl_data);
    if (rc < 0) {
        syslog(LOG_ERR, "Failed check event initial state.\n");
        goto fail_init_check;
    }

    syslog(LOG_NOTICE, "Starting wait for events.");

    rc = ev_hndl_wait_event(ev_hndl_data);

fail_init_check:
    ev_hndl_close(ev_hndl_data);
    syslog(LOG_NOTICE, "Event handling finished.");
    closelog();

fail_init:
    if (ev_hndl_data) {
        free(ev_hndl_data);
    }

    exit(rc);
}
