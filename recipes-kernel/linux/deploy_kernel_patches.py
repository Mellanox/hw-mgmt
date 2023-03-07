#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
########################################################################
# Copyright (c) 2022 NVIDIA CORPORATION & AFFILIATES.
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
# ARISING IN A WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

"""
Created on Jan 20, 2023
Author: Oleksandr Shamray <oleksandrs@nvidia.com>
Description: Kernel patch deploy automation tool
"""

#######################################################################
# Global imports
#######################################################################
import os
import sys
import argparse
import re
import pdb

#############################
# Global const
#############################
# pylint: disable=c0301,W0105

VERSION = "0.5.0"

class CONST(object):
    # Patch table string const
    PATCH_TABLE_NAME = "Patch_Status_Table.txt"
    PATCH_TABLE_DELIMITER = "----------------------"
    PATCH_OS_SUBFOLDERS = {"default" : "./linux-{kver}",
                           "sonic" : "./linux-{kver}/sonic",
                           "cumulus" : "./linux-{kver}/cumulus"}
    PATCH_NAME = "patch name"
    SUBVERSION = "subversion"

    # internal string const
    OS_ALT_PATCH = "os"
    TAKE_PATCH = "take"
    SKIP_PATCH = "skip"
    STATUS = "status"
    FILTER = "filter"
    SRC = "src"
    DST = "dst"

    SERIES_DELIMITER = """\n# Patches updated from hw-mgmt {hw_mgmt_ver}\n"""
    CONFIG_DELIMITER = """\n# New (changed) hw-mgmt {hw_mgmt_ver} kernel config flags\n"""
    REFERENCE_CONFIG = "kconfig.txt"
    DIFF_CONFIG = "kconfig.diff"

#############################
# Local const
#############################

PATCH_RULES = {"feature upstream": {CONST.FILTER : "copy_to_accepted_filter"},
               "feature accepted": {CONST.FILTER : "copy_to_candidate_filter"},
               "feature pending":  {CONST.FILTER : "skip_patch_filter"},
               "downstream":       {CONST.FILTER : "copy_to_candidate_filter"},
               "bugfix upstream":  {CONST.FILTER : "copy_to_accepted_ver_filter"},
               "bugfix accepted" : {CONST.FILTER : "copy_to_candidate_filter"},
               "bugfix pending":   {CONST.FILTER : "skip_patch_filter"},
               "rejected":         {CONST.FILTER : "skip_patch_filter"}
              }

# ----------------------------------------------------------------------
def trim_array_str(str_list):
    ret = [elem.strip() for elem in str_list]
    return ret

# ----------------------------------------------------------------------
def get_line_elements(line):
    columns_raw = line.split("|")
    if len(columns_raw) < 3:
        return False\
    # remove empty firsta and last elem
    columns_raw = columns_raw[1:-1]
    columns = trim_array_str(columns_raw)
    return columns

# ----------------------------------------------------------------------
def parse_status(line, patch_name):
    """
    parse patch status.
    Example:
    Feature upstream
        {"status": "Feature upstream", "take" : ["All"], "skip" : ["None"] }
    Feature upstream, skip[cumulus]
        {"status": "Feature upstream", "take" : ["All"], "skip" : ["cumulus"] }
    Rejected, take[sonic]
        {"status": "Rejected", "take" : ["sonic"], "skip" : ["All"] }
    """
    status_dict = {}
    line_arr = line.split(";")
    status = line_arr[0].lower()
    if status not in PATCH_RULES.keys():
        return None
    status_dict = {CONST.STATUS : status}
    status_dict.update(PATCH_RULES[status])
    # parse status line
    if len(line_arr) > 1:
        # parce additional rule per OS
        for rule in line_arr[1:]:
            rule = rule.strip()
            try:
                ret = re.match(r'(\S+)\[(.*)\]', rule)
            except:
                print("Incompatible status {} for {}".format(line, patch_name))
                return None
            status_dict[ret.group(1)] = ret.group(2).split(',')
    return status_dict

# ----------------------------------------------------------------------
def load_patch_table(path, k_version):
    patch_table_filename = os.path.join(path, CONST.PATCH_TABLE_NAME)

    print("Loading patch table {} kver:{}".format(patch_table_filename, k_version))

    if not os.path.isfile(patch_table_filename):
        print("Err: file {} not found".format(patch_table_filename))
        return None

    # opening the file
    patch_table_file = open(patch_table_filename, "r")
    # reading the data from the file
    patch_table_data = patch_table_file.read()
    # splitting the file data into lines
    patch_table_lines = patch_table_data.splitlines()
    patch_table_file.close()

    # Extract patch table for specified kernel version
    kversion_line = "Kernel-{}".format(k_version)
    table_ofset = 0
    for table_ofset, line in enumerate(patch_table_lines):
        if line == kversion_line:
            break

    # if kernel version not found
    if table_ofset >= len(patch_table_lines)-5:
        print ("Err: kernel version {} not found in {}".format(k_version, patch_table_filename))
        return None

    table = []
    delimiter_count = 0
    column_names = None
    for idx, line in enumerate(patch_table_lines[table_ofset:]):
        if CONST.PATCH_TABLE_DELIMITER in line:
            delimiter_count += 1
            if delimiter_count >= 3:
                print ("Err: too much leading delimers line #{}: {}".format(table_ofset + idx, line))
                return None
            elif table:
                break
            continue

        # line without delimiter but header still not found
        if delimiter_count > 0:
            if not column_names:
                column_names = get_line_elements(line)
                if not column_names:
                    print ("Err: parsing table header line #{}: {}".format(table_ofset + idx, line))
                    return None
                delimiter_count = 0
                continue
            elif column_names:
                line_arr = get_line_elements(line)
                if len(line_arr) != len(column_names):
                    print ("Err: patch table wrong format linex #{}: {}".format(table_ofset + idx, line))
                    return None
                else:
                    table_line = dict(zip(column_names, line_arr))
                    patch_status_line = table_line[CONST.STATUS]
                    patch_status = parse_status(patch_status_line, table_line[CONST.PATCH_NAME])
                    if not patch_status:
                        print ("Err: can't parse patch {} status {}".format(table_line[CONST.PATCH_NAME],
                                                                            patch_status_line))
                        return None
                    table_line[CONST.STATUS] = patch_status
                    table.append(table_line)

    return table

# ----------------------------------------------------------------------
def copy_to_accepted_filter(patch, accepted_folder, candidate_folder, kver):
    if patch[CONST.SUBVERSION]:
        patch_kver_lst = patch[CONST.SUBVERSION].split('.')
        target_kver_lst = kver.split('.')
        if len(patch_kver_lst) != 3:
            print("Err: patch {} subversion {} not in x.xx.xxx format".format(patch[CONST.PATCH_NAME], patch[CONST.SUBVERSION]))
            return None
        if int(patch_kver_lst[2]) > int(target_kver_lst[2]):
            return accepted_folder
        return None

    return accepted_folder

# ----------------------------------------------------------------------
def copy_to_candidate_filter(patch, accepted_folder, candidate_folder, kver):
    if patch[CONST.SUBVERSION]:
        patch_kver_lst = patch[CONST.SUBVERSION].split('.')
        target_kver_lst = kver.split('.')
        if len(patch_kver_lst) != 3:
            print("Err: patch {} subversion {} not in x.xx.xxx format".format(patch[CONST.PATCH_NAME], patch[CONST.SUBVERSION]))
            return None
        if int(patch_kver_lst[2]) > int(target_kver_lst[2]):
            return candidate_folder
        return None
    return candidate_folder

# ----------------------------------------------------------------------
def copy_to_accepted_ver_filter(patch, accepted_folder, candidate_folder, kver):
    patch_kver_lst = patch[CONST.SUBVERSION].split('.')
    target_kver_lst = kver.split('.')
    if len(patch_kver_lst) != 3:
        print("Err: patch {} subversion {} not in x.xx.xxx format".format(patch[CONST.PATCH_NAME], patch[CONST.SUBVERSION]))
        return None
    if int(patch_kver_lst[2]) > int(target_kver_lst[2]):
        return accepted_folder
    return None

# ----------------------------------------------------------------------
def copy_to_candidate_ver_filter(patch, accepted_folder, candidate_folder, kver):
    patch_kver_lst = patch[CONST.SUBVERSION].split('.')
    target_kver_lst = kver.split('.')
    if len(patch_kver_lst) != 3:
        print("Err: patch {} subversion \"{}\" not in x.xx.xxx format".format(patch[CONST.PATCH_NAME], patch[CONST.SUBVERSION]))
        return None
    if patch_kver_lst[2] > target_kver_lst[2]:
        return candidate_folder
    return None

# ----------------------------------------------------------------------
def skip_patch_filter(patch, accepted_folder, candidate_folder, kver):
    return None

# ----------------------------------------------------------------------
def filter_patch_list(patch_list, src_folder, accepted_folder, candidate_folder, kver, nos=None):
    kver_major = ".".join(kver.split('.')[0:2])

    for patch in patch_list:
        patch_status = patch[CONST.STATUS]
        os_folder = CONST.PATCH_OS_SUBFOLDERS["default"]
        take_list = patch_status.get(CONST.TAKE_PATCH, [])
        skip_list = patch_status.get(CONST.SKIP_PATCH, [])
        os_list = patch_status.get(CONST.OS_ALT_PATCH, [])
        patch_src_folder = src_folder + os_folder.format(kver=kver_major)
        patch[CONST.SRC] = "{}/{}".format(patch_src_folder, patch[CONST.PATCH_NAME])

        filter_name = patch_status[CONST.FILTER]
        filter_fn = globals()[filter_name]
        dst_folder = filter_fn(patch, accepted_folder, candidate_folder, kver)

        if nos in take_list or "ALL" in take_list:
            if not dst_folder:
                dst_folder = candidate_folder

        if nos in os_list:
            os_folder = CONST.PATCH_OS_SUBFOLDERS[nos]

        if nos in skip_list or "ALL" in skip_list or dst_folder == None:
            continue

        patch[CONST.DST] = "{}/{}".format(dst_folder, patch[CONST.PATCH_NAME])

# ----------------------------------------------------------------------
def os_cmd(cmd):
    return os.system(cmd)

# ----------------------------------------------------------------------
def print_patch_all(patch_list):
    for patch_ent in patch_list:
        print ("{} -> {}".format(patch_ent.get(CONST.SRC, "None"), patch_ent.get(CONST.DST, "None")))

# ----------------------------------------------------------------------
def process_patch_list(patch_list):
    files_copyed = 0
    for patch in patch_list:
        if CONST.DST in patch.keys():
            src_path = patch[CONST.SRC]
            dst_path = patch[CONST.DST]
            if not os_cmd('cp {} {}'.format(src_path, dst_path)):
                files_copyed += 1
    print ("Copyed {} files".format(files_copyed))
    return True

# ----------------------------------------------------------------------
def update_series(patch_list, series_path, hw_mgmt_ver=""):
    # Load seried file
    if not os.path.isfile(series_path):
        print ("Err. Series file {} missing.".format(series_path))
        return 1
    siries_file = open(series_path, "r")
    siries_file_lines = siries_file.readlines()
    siries_file_lines = trim_array_str(siries_file_lines)
    siries_file.close()
    new_patch_list = []

    for patch in patch_list:
        if CONST.DST not in patch.keys():
            continue

        patch_name = patch[CONST.PATCH_NAME]
        if patch_name not in siries_file_lines:
            print("Add to sieries {}".format(patch_name))
            new_patch_list.append(patch_name)

    if new_patch_list:
        print ("Updating series {}".format(series_path))
        siries_file = open(series_path, "a")
        siries_file.write('{}\n'.format(CONST.SERIES_DELIMITER.format(hw_mgmt_ver=hw_mgmt_ver)))
        siries_file.write('\n'.join(new_patch_list))
        siries_file.close()
        print ("Updated")
    else:
        print ("No need to update series")

    return 0

# ----------------------------------------------------------------------
def  process_config(src_root, dst_cfg):
    # Load seried file

    if not os.path.isfile(dst_cfg):
        print ("Err. Config file {} missing.".format(dst_cfg))
        return False
    src_config_file = open(dst_cfg, "r")
    src_config_file_lines = src_config_file.readlines()
    src_config_file.close()
    src_config_file_lines = trim_array_str(src_config_file_lines)

    # Load seried file
    ref_cfg = "{}/{}".format(src_root, CONST.REFERENCE_CONFIG)

    if not os.path.isfile(ref_cfg):
        print ("Err. Config file {} missing.".format(ref_cfg))
        return False
    ref_config_file = open(ref_cfg, "r")
    ref_config_file_lines = ref_config_file.readlines()
    ref_config_file.close()
    ref_config_file_lines = trim_array_str(ref_config_file_lines)

    dst_config_lines = []
    for ref_config in ref_config_file_lines:
        if ref_config not in src_config_file_lines:
            print ("Missing config: {}".format(ref_config))
            dst_config_lines.append(ref_config)
    return dst_config_lines


# ----------------------------------------------------------------------
def get_hw_mgmt_ver():
    tool_path = os.path.dirname(os.path.abspath(__file__))
    changelog_path = "{}/../../debian/changelog".format(tool_path)
    changelog_file = open(changelog_path, "r")
    changelog_ver_line = changelog_file.readline().strip('\n')
    version_res = re.match(r'.*\(1.mlnx.(.*)\)', changelog_ver_line)
    if version_res:
        ver = version_res.group(1)
    return ver

# ----------------------------------------------------------------------
class RawTextArgumentDefaultsHelpFormatter(
        argparse.ArgumentDefaultsHelpFormatter,
        argparse.RawTextHelpFormatter
    ):
    """
        @summary:
            Formatter class for pretty print ArgumentParser help
    """
    pass

# ----------------------------------------------------------------------
if __name__ == '__main__':
    CMD_PARSER = argparse.ArgumentParser(formatter_class=RawTextArgumentDefaultsHelpFormatter, description="hw-management thermal control")
    CMD_PARSER.add_argument("--version", action="version", version="%(prog)s ver:{}".format(VERSION))
    CMD_PARSER.add_argument("--kernel_version",
                            dest="k_version",
                            help="Kernel version: 5.10.43/5.10.103/any other",
                            required=True)
    CMD_PARSER.add_argument("-s", "--src_folder",
                            dest="src_folder",
                            help="Src folder with hw-management kernel patches: /tmp/hw-management/recipes-kernel/linux/",
                            default=True)
    CMD_PARSER.add_argument("--dst_accepted_folder",
                            dest="dst_accepted_folder",
                            help="Dst folder with accepted patches",
                            default=None,
                            required=False)
    CMD_PARSER.add_argument("--dst_candidate_folder",
                            dest="dst_candidate_folder",
                            help="Dst folder with candidate patches",
                            required=False)
    CMD_PARSER.add_argument("--series_file",
                            dest="series_file",
                            help="Update series file located by passed path.\n"
                            "In case this argument is missing - skip series update\n"
                            "All added patches will be added at the end of series",
                            default=None,
                            required=False)
    CMD_PARSER.add_argument("--config_file",
                            dest="config_file",
                            help="Will create diff list of missing kernel CONFIG\n"
                            "In case this argument is missing - skip series update",
                            default=None,
                            required=False)
    CMD_PARSER.add_argument("--os_type",
                            dest="os_type",
                            help="Special integration type.\n"
                            "In case this argument is missing - don't apply special integration rule\n",
                            default="None",
                            choices=["None", "sonic", "cumulus"],
                            required=False)
    CMD_PARSER.add_argument("--verbose",
                            dest="verbose",
                            help="Verbose output",
                            default=False,
                            required=False)

    hw_mgmt_ver = get_hw_mgmt_ver()
    args = vars(CMD_PARSER.parse_args())
    src_folder = args["src_folder"]
    accepted_folder = args["dst_accepted_folder"]
    candidate_folder = args["dst_candidate_folder"]
    k_version = args["k_version"]

    kver_arr = k_version.split(".")
    if len(kver_arr) < 3:
        print ("Err: wrong kernel version {}. Should be specified in format XX.XX.XX".format(k_version))
        sys.exit(1)
    k_version_major = ".".join(kver_arr[0:2])

    patch_table = None
    config_diff = None
    if candidate_folder:
        print ("-> Process patches")

        patch_table = load_patch_table(src_folder, k_version_major)
        if not patch_table:
            print ("Can't load patch table from folder {}".format(src_folder))
            sys.exit(1)

        if not accepted_folder:
            accepted_folder = candidate_folder
            print ("Accepted folder not specified.\nAll patches will be copied to: {}".format(candidate_folder))
        filter_patch_list(patch_table,
                          src_folder,
                          accepted_folder,
                          candidate_folder,
                          k_version,
                          args["os_type"])

        if args["verbose"]:
            print_patch_all(patch_table)

        print ("-> Copy patches")
        res = process_patch_list(patch_table)
        if res:
            sys.exit(1)
        print ("-> Copy patches done")

        if args["series_file"]:
            print ("-> Process series")
            res = update_series(patch_table, args["series_file"], hw_mgmt_ver)
            if res:
                sys.exit(1)
            print ("-> Update series done")

    config_file_name = args["config_file"]
    if config_file_name:
        print ("-> Processing config {}".format(args["config_file"]))
        config_diff = process_config(src_folder, args["config_file"])

        if config_diff:
            config_file = open(config_file_name, "a")
            config_file.write(CONST.CONFIG_DELIMITER.format(hw_mgmt_ver=hw_mgmt_ver))
            config_file.write('\n'.join(config_diff))
            config_file.close()
            print ("-> Update config done")
        else:
            print ("-> No need to update config")

    sys.exit(0)
