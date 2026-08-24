#!/bin/bash
##################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2020-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
#

# hw-management-tc.service ExecStopPost hook.
#
# Records whether hw-management-tc.service's stop was propagated from
# hw-management.service stopping/restarting (PartOf=hw-management.service), as
# opposed to an operator directly stopping only the TC service.
#
# hw-management-tc.service has After=hw-management.service, so on a
# coordinated stop systemd stops TC *before* hw-management.service's own stop
# job even begins (shutdown order is the reverse of startup order). That means
# hw-management.service's ActiveState is still "active" at this point in a
# genuine PartOf= cascade too, so is-active cannot tell the two cases apart.
# A stop/restart job for hw-management.service is queued for the whole
# transaction immediately, though, even while it is blocked waiting on this
# ordering constraint - so check for a pending job instead:
# - job queued for hw-management.service     -> this stop is part of that same
#   transaction (PartOf= cascade); mark it so hw-management-start-post.sh can
#   restore TC on the next start, since PartOf= only propagates stop/restart,
#   never a plain start.
# - no job queued for hw-management.service  -> TC was stopped on its own
#   (operator intent); clear any stale marker so a later, unrelated
#   hw-management restart does not resurrect TC against the operator's wishes.
source hw-management-helpers.sh

if systemctl list-jobs --no-legend hw-management.service 2>/dev/null | grep -q .; then
	touch "$tc_pending_restart_file"
else
	rm -f "$tc_pending_restart_file"
fi
