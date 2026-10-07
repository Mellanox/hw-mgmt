#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2023-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

PLAT_KEXEC_NOTIFY=/var/run/hw-management/system/kexec_activated

if [ "$1" = "kexec" ] && [ -f ${PLAT_KEXEC_NOTIFY} ]; then
        echo 0 > ${PLAT_KEXEC_NOTIFY}
fi

