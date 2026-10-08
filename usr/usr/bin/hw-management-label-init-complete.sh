#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause

source hw-management-helpers.sh

LABEL_MAKER_SCRIPT="hw-management-labels-maker.sh"

check_label_progress()
{
	label_progress=`ps -aux | grep "$LABEL_MAKER_SCRIPT" | grep -v grep`
	[ -z "$label_progress" ] && echo 0 || echo 1
}

# Wait for the process to kick in
sleep 20

while [ $(check_label_progress) -eq 1 ];
do
	sleep 2
done

echo 1 > "$config_path"/labels_ready
log_info "Labels data base is ready"

