#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
# pylint: disable=W0718
# pylint: disable=R0913:
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
"""Module providing functions for setting asic and module thermal data."""
import os

BASE_PATH = "/var/run/hw-management"


def get_asic_count():
    """
    @summary: Function gets ASIC count from "{BASE_PATH}/config/asic_num."
    @return: ASIC count if successful, False otherwise.
    """
    asic_count_file = os.path.join(BASE_PATH, "config", "asic_num")
    if os.path.exists(asic_count_file):
        try:
            with open(asic_count_file, 'r', encoding="utf-8") as f:
                return int(f.read())
        except Exception as e:
            print(f"Error reading asic count: {str(e)}")
            return False
    else:
        print(f"Error: Could not read ASIC count from {asic_count_file}")
        return False


def get_module_count():
    """
    @summary: Function gets module count from "{BASE_PATH}/config/module_counter."
    @return: Module count if successful, False otherwise.
    """
    module_count_file = os.path.join(BASE_PATH, "config", "module_counter")
    if os.path.exists(module_count_file):
        try:
            with open(module_count_file, 'r', encoding="utf-8") as f:
                return int(f.read())
        except Exception as e:
            print(f"Error reading module count: {str(e)}")
            return False
    else:
        print(f"Error: Could not read module count from {module_count_file}")
        return False


def check_asic_index(asic_index):
    """
    @summary: Function checks asic index boundary.
    @param asic_index: ASIC index.
    @return: True if asic index is valid, False otherwise.
    """
    asic_count = get_asic_count()
    if asic_count is not False and 0 <= asic_index < asic_count:
        return True
    print(f"asic_index {asic_index} is out of bound 0..ASIC")
    return False


def check_module_index(asic_index, module_index):
    """
    @summary: Function checks module index boundary.
    @param asic_index: ASIC index.
    @param module_index: Module index.
    @return: True if module index is valid, False otherwise.
    """
    module_count = get_module_count()
    if module_count is not False and 1 <= module_index <= module_count:
        return True
    print(f"module_index {module_index} of asic {asic_index} is out of bound 1..n")
    return False


def module_data_set_module_counter(module_counter):
    """
    @summary: Function sets module counter.
    @param module_counter: Module counter.
    @return: True if module counter is set successfully, False otherwise.
    """
    if module_counter < 0:
        print(f"Error: Could not set module count to {module_counter}")
        return False
    module_count_file = os.path.join(BASE_PATH, "config", "module_counter")
    # Create the files if they don't exist and write the values
    try:
        with open(module_count_file, 'w', encoding="utf-8") as f:
            f.write(str(module_counter))
        return True  # Successfully set module counter
    except Exception as e:
        print(f"Error setting module counter: {str(e)}")
        return False


def write_file_data(file_paths_value_dict):
    """
    @summary: Writes thermal data to the relevant files. Files/value passed as dictionary.
    @param file_paths_value_dict: Dictionary of file names and values.
    @return: True if all writes are successful, False otherwise.
    """
    try:
        for fname, value in file_paths_value_dict.items():
            f_name_full = os.path.join(BASE_PATH, "thermal", fname)
            if value is not None:
                with open(f_name_full, 'w', encoding="utf-8") as f:
                    f.write("{}\n".format(value))
    except Exception as e:
        print(f"Error writing thermal data: {str(e)}")
        return False
    return True


def remove_file_list(file_list):
    """
    @summary: Clears thermal data from the relevant files.
    @param file_list: List of file names.
    @return: True if all clears are successful, False otherwise.
    """
    try:
        for file in file_list:
            f_name_full = os.path.join(BASE_PATH, "thermal", file)
            if os.path.exists(f_name_full):
                os.remove(f_name_full)
        return True
    except Exception as e:
        print(f"Error removing files: {file_list} {str(e)}")
        return False


def thermal_data_set_asic(asic_index, temperature, warning_threshold, critical_threshold, fault=0):
    """
    @summary: Function sets asic data.
    @param asic_index: ASIC index.
    @param temperature: Temperature.
    @param warning_threshold: Warning threshold.
    @param critical_threshold: Critical threshold.
    @param fault: Fault.
    @return: True if all sets are successful, False otherwise.
    """
    if not check_asic_index(asic_index):
        return False

    file_paths_value_dict = {}
    # Define file paths based on asic_index
    if asic_index == 0:
        file_paths_value_dict.update({
            "asic_temp_crit": critical_threshold,
            "asic": temperature,
            "asic_temp_emergency": warning_threshold,
            "asic_temp_fault": fault
        })

    file_paths_value_dict.update({
        f"asic{asic_index + 1}_temp_crit": critical_threshold,
        f"asic{asic_index + 1}": temperature,
        f"asic{asic_index + 1}_temp_emergency": warning_threshold,
        f"asic{asic_index + 1}_temp_fault": fault
    })

    return write_file_data(file_paths_value_dict)


def thermal_data_set_module(asic_index,
                            module_index,
                            temperature,
                            warning_threshold,
                            critical_threshold,
                            fault=0):
    """
    @summary: Function sets module data.
    @param asic_index: ASIC index.
    @param module_index: Module index.
    @param temperature: Temperature.
    @param warning_threshold: Warning threshold.
    @param critical_threshold: Critical threshold.
    @param fault: Fault.
    @return: True if all sets are successful, False otherwise.
    """
    if not check_asic_index(asic_index) or not check_module_index(asic_index, module_index):
        return False

    file_paths_value_dict = {
        f"module{module_index}_temp_crit": critical_threshold,
        f"module{module_index}_temp_input": temperature,
        f"module{module_index}_temp_emergency": warning_threshold,
        f"module{module_index}_temp_fault": fault
    }

    return write_file_data(file_paths_value_dict)


vendor_data_key_replace = {
    "part_number": "PN",
    "manufacturer": "Manufacturer"
}


def vendor_data_set_module(asic_index,
                           module_index,
                           vendor_info=None):
    """
    @summary: Function sets module vendor data.
    @param asic_index: ASIC index.
    @param module_index: Module index.
    @param vendor_info: Vendor information.
    @return: True if all sets are successful, False otherwise.
    """
    if not check_asic_index(asic_index) or not check_module_index(asic_index, module_index):
        return False

    vendor_file = os.path.join(BASE_PATH, "eeprom", f"module{module_index}_data")
    # Create the file if it doesn't exist and write the values
    try:
        # if vendor_info is set - create vendor data file
        if vendor_info:
            vendor_data = []
            for key, value in vendor_info.items():
                # make key case agnostic
                key_lower = key.lower()
                # if key is not in vendor_data_key_replace, use the original key
                key_value = key if key_lower not in vendor_data_key_replace else vendor_data_key_replace[key_lower]
                # format key and value for output format
                str_value = f"{key_value:<25}: {value}"
                vendor_data.append(str_value)
            with open(vendor_file, 'w', encoding="utf-8") as f:
                f.write("\n".join(vendor_data) + "\n")
        # if vendor_info is not set - remove vendor data file
        else:
            if os.path.exists(vendor_file):
                os.remove(vendor_file)
        return True  # Successfully set vendor data for the module
    except Exception as e:
        print(f"Error setting vendor data for Module {module_index}: {str(e)}")
        return False


def thermal_data_clean_asic(asic_index):
    """
    @summary: Function cleans asic data.
    @param asic_index: ASIC index.
    @return: True if all cleans are successful, False otherwise.
    """
    if not check_asic_index(asic_index):
        return False

    file_paths_value_list = [
        f"asic{asic_index + 1}_temp_crit",
        f"asic{asic_index + 1}",
        f"asic{asic_index + 1}_temp_emergency",
        f"asic{asic_index + 1}_temp_fault"
    ]

    # For ASIC 0, also remove "asic_*" files
    if asic_index == 0:
        file_paths_value_list.extend([
            "asic_temp_crit",
            "asic",
            "asic_temp_emergency",
            "asic_temp_fault"
        ])

    return remove_file_list(file_paths_value_list)


def thermal_data_clean_module(asic_index, module_index):
    """
    @summary: Function cleans module data.
    @param asic_index: ASIC index.
    @param module_index: Module index.
    @return: True if all cleans are successful, False otherwise.
    """
    if not check_asic_index(asic_index) or not check_module_index(asic_index, module_index):
        return False

    file_paths_value_list = [
        f"module{module_index}_temp_crit",
        f"module{module_index}_temp_input",
        f"module{module_index}_temp_emergency",
        f"module{module_index}_temp_fault"
    ]

    return remove_file_list(file_paths_value_list)


def vendor_data_clear_module(asic_index,
                             module_index):
    """
    @summary: Function cleans module vendor data.
    @param asic_index: ASIC index.
    @param module_index: Module index.
    @return: True if all cleans are successful, False otherwise.
    """
    if not check_asic_index(asic_index) or not check_module_index(asic_index, module_index):
        return False

    # Define file paths
    vendor_file = os.path.join(BASE_PATH, "eeprom", f"module{module_index}_data")
    # Remove the files if they exist
    try:
        if os.path.exists(vendor_file):
            os.remove(vendor_file)
        return True  # Successfully cleaned vendor data for the module
    except Exception as e:
        print(f"Error cleaning vendor data for Module {module_index}: {str(e)}")
        return False
