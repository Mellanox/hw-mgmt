#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

class RedfishClient:
    ERR_CODE_OK = 0
    def __init__(self):
        pass


class BMCAccessor:
    def __init__(self):
        pass
    def login(self):
        return RedfishClient.ERR_CODE_OK
    @property
    def rf_client(self):
        class Dummy:
            def build_get_cmd(self, path): return None
            def exec_curl_cmd(self, cmd): return (RedfishClient.ERR_CODE_OK, '{}', None)
            def build_post_cmd(self, path, data_dict): return None
        return Dummy()
