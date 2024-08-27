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

VERSION = "0.9.0"

class CONST(object):
    # Patch table string const
    PATCH_TABLE_NAME = "Patch_Status_Table.txt"
    PATCH_TABLE_DELIMITER = "----------------------"
    PATCH_OS_SUBFOLDERS = {"default" : "./linux-{kver}",
                           "sonic" : "./linux-{kver}/sonic",
                           "opt" : "./linux-{kver}/sonic",
                           "cumulus" : "./linux-{kver}/cumulus",
                           "nvos" : "./linux-{kver}/sonic",
                           "dvs" : "./linux-{kver}/sonic"}
    PATCH_NAME = "patch name"
    SUBVERSION = "subversion"
    PATCH_DST = "dst_type"
    PATCH_ACCEPTED = "accepted"
    PATCH_CANDIDATE = "candidate"

    # internal string const
    OS_ALT_PATCH = "os"
    TAKE_PATCH = "take"
    SKIP_PATCH = "skip"
    STATUS = "status"
    FILTER = "filter"
    SRC = "src"
    DST = "dst"

    SERIES_DELIMITER = """\n# Patches updated from hw-mgmt {hw_mgmt_ver}\n"""
    CONFIG_DELIMITER = """\n# New hw-mgmt {hw_mgmt_ver} kernel config flags\n"""
    REFERENCE_CONFIG = "kconfig.txt"
    DIFF_CONFIG = "kconfig.diff"

#############################
# Local const
#############################

PATCH_RULES = {"feature upstream": {CONST.FILTER : "copy_to_accepted_filter"},
               "feature accepted": {CONST.FILTER : "copy_to_accepted_filter"},
               "feature pending":  {CONST.FILTER : "copy_to_accepted_filter"},
               "downstream":       {CONST.FILTER : "copy_to_candidate_filter"},
               "downstream accepted": {CONST.FILTER : "copy_to_accepted_filter"},
               "bugfix upstream":  {CONST.FILTER : "copy_to_accepted_filter"},
               "bugfix accepted" : {CONST.FILTER : "copy_to_accepted_filter"},
               "bugfix pending":   {CONST.FILTER : "copy_to_accepted_filter"},
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
        print("Err: kernel version {} not found in {}".format(k_version, patch_table_filename))
        return None

    table = []
    delimiter_count = 0
    column_names = None
    for idx, line in enumerate(patch_table_lines[table_ofset:]):
        if CONST.PATCH_TABLE_DELIMITER in line:
            delimiter_count += 1
            if delimiter_count >= 3:
                print("Err: too much leading delimers line #{}: {}".format(table_ofset + idx, line))
                return None
            elif table:
                break
            continue

        # line without delimiter but header still not found
        if delimiter_count > 0:
            if not column_names:
                column_names = get_line_elements(line)
                if not column_names:
                    print("Err: parsing table header line #{}: {}".format(table_ofset + idx, line))
                    return None
                delimiter_count = 0
                continue
            elif column_names:
                line_arr = get_line_elements(line)
                if len(line_arr) != len(column_names):
                    print("Err: patch table wrong format linex #{}: {}".format(table_ofset + idx, line))
                    return None
                table_line = dict(zip(column_names, line_arr))
                patch_status_line = table_line[CONST.STATUS]
                patch_status = parse_status(patch_status_line, table_line[CONST.PATCH_NAME])
                if not patch_status:
                    print("Err: can't parse patch {} status {}".format(table_line[CONST.PATCH_NAME],
                                                                       patch_status_line))
                    return None
                table_line[CONST.STATUS] = patch_status
                table_line[CONST.PATCH_DST] = None
                table.append(table_line)

    return table

# ----------------------------------------------------------------------
def copy_to_accepted_filter(patch, accepted_folder, candidate_folder, kver):
    ret = accepted_folder
    if patch[CONST.SUBVERSION]:
        patch_kver_lst = patch[CONST.SUBVERSION].split('.')
        target_kver_lst = kver.split('.')
        if len(patch_kver_lst) != 3:
            print("Err: patch {} subversion {} not in x.xx.xxx format".format(patch[CONST.PATCH_NAME], patch[CONST.SUBVERSION]))
            ret = None
        elif int(patch_kver_lst[2]) <= int(target_kver_lst[2]):
            ret = None
    patch[CONST.PATCH_DST] = CONST.PATCH_ACCEPTED
    return ret

# ----------------------------------------------------------------------
def copy_to_candidate_filter(patch, accepted_folder, candidate_folder, kver):
    ret = candidate_folder
    if patch[CONST.SUBVERSION]:
        patch_kver_lst = patch[CONST.SUBVERSION].split('.')
        target_kver_lst = kver.split('.')
        if len(patch_kver_lst) != 3:
            print("Err: patch {} subversion {} not in x.xx.xxx format".format(patch[CONST.PATCH_NAME], patch[CONST.SUBVERSION]))
            ret = None
        elif int(patch_kver_lst[2]) <= int(target_kver_lst[2]):
            ret = None
    patch[CONST.PATCH_DST] = CONST.PATCH_CANDIDATE
    return ret

# ----------------------------------------------------------------------
def copy_to_accepted_ver_filter(patch, accepted_folder, candidate_folder, kver):
    ret = None
    patch_kver_lst = patch[CONST.SUBVERSION].split('.')
    target_kver_lst = kver.split('.')
    if len(patch_kver_lst) != 3:
        print("Err: patch {} subversion {} not in x.xx.xxx format".format(patch[CONST.PATCH_NAME], patch[CONST.SUBVERSION]))
    elif int(patch_kver_lst[2]) > int(target_kver_lst[2]):
        ret = accepted_folder
    patch[CONST.PATCH_DST] = CONST.PATCH_ACCEPTED
    return ret

# ----------------------------------------------------------------------
def copy_to_candidate_ver_filter(patch, accepted_folder, candidate_folder, kver):
    ret = None
    patch_kver_lst = patch[CONST.SUBVERSION].split('.')
    target_kver_lst = kver.split('.')
    if len(patch_kver_lst) != 3:
        print("Err: patch {} subversion \"{}\" not in x.xx.xxx format".format(patch[CONST.PATCH_NAME], patch[CONST.SUBVERSION]))
    elif patch_kver_lst[2] > target_kver_lst[2]:
        ret = candidate_folder
    patch[CONST.PATCH_DST] = CONST.PATCH_CANDIDATE
    return ret

# ----------------------------------------------------------------------
def skip_patch_filter(patch, accepted_folder, candidate_folder, kver):
    patch[CONST.PATCH_DST] = CONST.PATCH_CANDIDATE
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

        filter_name = patch_status[CONST.FILTER]
        filter_fn = globals()[filter_name]
        dst_folder = filter_fn(patch, accepted_folder, candidate_folder, kver)

        take_strong = nos in take_list or nos in os_list
        skip_strong = nos in skip_list
        if (take_strong and skip_strong) or ("ALL" in take_list and "ALL" in skip_list) or "ALL" in os_list:
            print("ERR: Conflict in patch status options\n{} : {}".format(patch[CONST.PATCH_NAME], patch[CONST.STATUS]))
            sys.exit(1)

        if skip_strong:
            continue
        elif take_strong:
            if not dst_folder:
                dst_folder = candidate_folder
            if nos in os_list:
                os_folder = CONST.PATCH_OS_SUBFOLDERS[nos]
        elif "ALL" in take_list:
            if not dst_folder:
                dst_folder = candidate_folder
        elif "ALL" in skip_list or dst_folder == None:
            continue

        patch_src_folder = src_folder + os_folder.format(kver=kver_major)
        patch[CONST.SRC] = "{}/{}".format(patch_src_folder, patch[CONST.PATCH_NAME])
        patch[CONST.DST] = "{}/{}".format(dst_folder, patch[CONST.PATCH_NAME])

# ----------------------------------------------------------------------
def os_cmd(cmd):
    return os.system(cmd)

# ----------------------------------------------------------------------
def print_patch_all(patch_list):
    for patch_ent in patch_list:
        print("{} -> {}".format(patch_ent.get(CONST.SRC, "None"), patch_ent.get(CONST.DST, "Skip")))

# ----------------------------------------------------------------------
def process_patch_list(patch_list):
    files_copyed = 0
    for patch in patch_list:
        if CONST.DST in patch.keys():
            src_path = patch[CONST.SRC]
            dst_path = patch[CONST.DST]
            if not os_cmd('cp {} {}'.format(src_path, dst_path)):
                files_copyed += 1
    print("Copyed {} files".format(files_copyed))
    return True

# ----------------------------------------------------------------------
def update_series(patch_list, series_path, delimiter="", dst_type=None):
    # Load seried file
    if not os.path.isfile(series_path):
        print("Err. Series file {} missing.".format(series_path))
        return 1
    siries_file = open(series_path, "r")
    siries_file_lines = siries_file.readlines()
    siries_file_lines = trim_array_str(siries_file_lines)
    siries_file.close()
    new_patch_list = []

    for patch in patch_list:
        if CONST.DST not in patch.keys():
            continue
        # Add patches only from specific dst
        if dst_type and patch[CONST.PATCH_DST] != dst_type:
            continue
        patch_name = patch[CONST.PATCH_NAME]
        if patch_name not in siries_file_lines:
            print("Add to sieries {}".format(patch_name))
            new_patch_list.append(patch_name)

    if new_patch_list:
        print("Updating series {}".format(series_path))
        siries_file = open(series_path, "a")
        siries_file.write('{}\n'.format(delimiter))
        siries_file.write('\n'.join(new_patch_list))
        siries_file.close()
        print("Updated")
    else:
        print("No need to update series")

    return 0

# ----------------------------------------------------------------------
def parse_config_line(config_option_line):
    option = None
    status = None
    if "=" in config_option_line:
        option_res = re.match(r'^(\S+)=(\S+)', config_option_line)
        if option_res:
            option = option_res.group(1)
            status = option_res.group(2)
    elif "is not set" in config_option_line:
        option_res = re.match(r'#\s*(\S+) is not set', config_option_line)
        if option_res:
            option = option_res.group(1)
            status = None
    if option:
        return option, status

    return None, None

# ----------------------------------------------------------------------
def produce_config_line(option, status):
    if status == None:
        config_option_line = "# {} is not set".format(option)
    else:
        config_option_line = "{}={}".format(option, status)

    return config_option_line

# ----------------------------------------------------------------------
def load_config_to_dict(config_path, section):

    if not os.path.isfile(config_path):
        print("Err. File {} missing.".format(config_path))
        return False
    config_file = open(config_path, "r")
    config_file_lines = config_file.readlines()
    config_file.close()
    config_file_lines = trim_array_str(config_file_lines)

    config_dict = {}
    curr_section = None
    for line in config_file_lines:
        re_section = re.match(r'.*\[([a-z0-9:]+)\]', line)
        if re_section:
            curr_section = re_section.group(1)
            continue
        if curr_section == section:
            option, status = parse_config_line(line)
            if option:
                config_dict[option] = status
    return config_dict

# ----------------------------------------------------------------------
def process_config(ref_cfg_filename, dst_cfg, delimiter="", arch="amd64", sub_type=""):
    # Load src config file
    ref_config = load_config_to_dict(ref_cfg_filename, "{}:{}".format(arch, sub_type))
    if not ref_config:
        print("Info. Not found config for [{}:{}] in ref config file {}".format(arch, sub_type, ref_cfg_filename))
    else:
        print("Trget [{}:{}]".format(arch, sub_type))
    if os.path.isfile(dst_cfg):
        src_config_file = open(dst_cfg, "r")
        src_config_file_lines = src_config_file.readlines()
        src_config_file.close()
        src_config_file_lines = trim_array_str(src_config_file_lines)
    else:
        print("Warn. Missing config file {}. It will be creted.".format(dst_cfg))
        src_config_file_lines = []

    dst_config_lines = []
    ref_config_keys = ref_config.keys()

    for conf_line in src_config_file_lines:
        option, _ = parse_config_line(conf_line)
        if option and option in ref_config_keys:
            conf_line_new = produce_config_line(option, ref_config[option])
            if conf_line_new != conf_line:
                print("Change config: \"{}\" -> \"{}\"".format(conf_line, conf_line_new))
            ref_config.pop(option)
            ref_config_keys = ref_config.keys()
        else:
            conf_line_new = conf_line

        dst_config_lines.append(conf_line_new)

    if ref_config:
        dst_config_lines.append(delimiter)

    for key, val in ref_config.items():
        conf_line_new = produce_config_line(key, val)
        print("Add config:    \"{}\"".format(conf_line_new))
        dst_config_lines.append(conf_line_new)

    return dst_config_lines

def get_tool_path():
    tool_path = os.path.dirname(os.path.abspath(__file__))
    return tool_path + "/"

# ----------------------------------------------------------------------
def get_hw_mgmt_ver():
    ver = ""
    tool_path = get_tool_path()
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
    CMD_PARSER.add_argument("--version", action="version", version="{}".format(VERSION))
    CMD_PARSER.add_argument("--kernel_version",
                            dest="k_version",
                            help="Kernel version: 5.10.43/5.10.103/any other",
                            required=True)
    CMD_PARSER.add_argument("-s", "--src_folder",
                            dest="src_folder",
                            help=argparse.SUPPRESS,
                            default=None,
                            required=False)
    CMD_PARSER.add_argument("--dst_accepted_folder",
                            dest="dst_accepted_folder",
                            help="Dst folder with accepted patches.\n"
                            "If not specified - all patches will be copied to candidate folder",
                            default=None,
                            required=False)
    CMD_PARSER.add_argument("--dst_candidate_folder",
                            dest="dst_candidate_folder",
                            help="Dst folder with candidate patches",
                            required=True)
    CMD_PARSER.add_argument("--series_file",
                            dest="series_file",
                            help="Update series file located by passed path.\n"
                            "In case this argument is missing - skip series update\n"
                            "All added patches will be added to the end of series",
                            required=True)
    CMD_PARSER.add_argument("--config_file",
                            dest="config_file",
                            help="Will update kernel CONFIG with the all flags.\n"
                            "In case of using together with --config_file_downstream argument - will be copied\n"
                            "only CONFIG_(s) marked as upstream",
                            required=False)
    CMD_PARSER.add_argument("--config_file_downstream",
                            dest="config_file_downstream",
                            help="Will update kernel CONFIG with the flags related only to  downstream configuration.\n"
                            "In case this argument is missing - all CONFIG_* options will be passed\n"
                            "to file specified in --config_file argument\n"
                            "This argument can be used only together with --config_file",
                            required=False)
    CMD_PARSER.add_argument("--os_type",
                            dest="os_type",
                            help="Special integration type.\n"
                            "In case this argument is missing - don't apply special integration rule\n",
                            default="None",
                            choices=["None", "sonic", "opt", "cumulus", "nvos", "dvs"],
                            required=False)
    CMD_PARSER.add_argument("--arch",
                            dest="arch",
                            help="Arch type...",
                            default="amd64",
                            choices=["amd64", "arm64"],
                            required=False)
    CMD_PARSER.add_argument("--verbose",
                            dest="verbose",
                            help="Verbose output",
                            default=False,
                            required=False)

    hw_mgmt_ver = get_hw_mgmt_ver()
    args = vars(CMD_PARSER.parse_args())
    src_folder = args["src_folder"]
    if not src_folder:
        src_folder = get_tool_path()

    accepted_folder = args["dst_accepted_folder"]
    candidate_folder = args["dst_candidate_folder"]
    k_version = args["k_version"]

    kver_arr = k_version.split(".")
    if len(kver_arr) < 3:
        print("Err: wrong kernel version {}. Should be specified in format XX.XX.XX".format(k_version))
        sys.exit(1)
    k_version_major = ".".join(kver_arr[0:2])

    patch_table = None
    config_diff = None

    print("-> Process patches")
    patch_table = load_patch_table(src_folder, k_version_major)
    if not patch_table:
        print("Can't load patch table from folder {}".format(src_folder))
        sys.exit(1)

    if not accepted_folder:
        print("Accepted folder not specified.\nAll patches will be copied to: {}".format(candidate_folder))
        filter_patch_list(patch_table,
                          src_folder,
                          candidate_folder,
                          candidate_folder,
                          k_version,
                          args["os_type"])
    else:
        filter_patch_list(patch_table,
                          src_folder,
                          accepted_folder,
                          candidate_folder,
                          k_version,
                          args["os_type"])

    if args["verbose"]:
        print_patch_all(patch_table)

    print("-> Copy patches")
    res = process_patch_list(patch_table)
    if not res:
        print("-> Copy patches error")
        sys.exit(1)
    print("-> Copy patches done")

    if args["series_file"]:
        print("-> Process series")
        delimiter_line = CONST.SERIES_DELIMITER.format(hw_mgmt_ver=hw_mgmt_ver)
        res = update_series(patch_table,
                            args["series_file"],
                            delimiter_line,
                            dst_type=None)
        if res:
            sys.exit(1)
        print("-> Update series done")

    config_file_name = args["config_file"]
    if config_file_name:
        print("-> Processing upstream config {}".format(args["config_file"]))
        delimiter_line = CONST.CONFIG_DELIMITER.format(hw_mgmt_ver=hw_mgmt_ver)
        src_cfg_filename = "{}/kconfig_{}.txt".format(src_folder, "_".join(kver_arr[0:2]))
        config_res = process_config(src_cfg_filename, config_file_name, delimiter_line, arch=args["arch"], sub_type="upstream")

        if config_res:
            config_file = open(config_file_name, "w")
            config_file.write('\n'.join(config_res))
            config_file.close()

        if args["config_file_downstream"]:
            config_file_name = args["config_file_downstream"]

        print("-> Processing downstream config {}".format(config_file_name))
        delimiter_line = CONST.CONFIG_DELIMITER.format(hw_mgmt_ver=hw_mgmt_ver)
        config_res = process_config(src_cfg_filename, config_file_name, delimiter_line, arch=args["arch"], sub_type="downstream")

        if config_res:
            config_file = open(config_file_name, "w")
            config_file.write('\n'.join(config_res))
            config_file.close()
        print("-> Update config done")
    sys.exit(0)
