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

ERROR_READ_THERMAL_DATA = 254000

BASE_PATH = "/var/run/hw-management"


def get_asic_count():
    """Function gets ASIC count from "{BASE_PATH}/config/asic_num."""
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
    """Function gets module count from "{BASE_PATH}/config/module_counter."""
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
    """Function checks asic index boundry."""
    asic_count = get_asic_count()
    if asic_count is not False and 0 <= asic_index < asic_count:
        return True
    print(f"asic_index {asic_index} is out of bound 0..ASIC")
    return False


def check_module_index(asic_index, module_index):
    """Function checks module index boundry."""
    module_count = get_module_count()
    if module_count is not False and 1 <= module_index <= module_count:
        return True
    print(f"module_index {module_index}of asic {asic_index} is out of bound 1..n")
    return False


def module_data_set_module_counter(module_counter):
    """Function sets module counter."""
    if module_counter < 0:
        print(f"Error: Could not set module count to {module_counter}")
        return False
    module_count_file = os.path.join(BASE_PATH, "config", "module_counter")
    # Create the files if they don't exist and write the values
    try:
        with open(module_count_file, 'w', encoding="utf-8") as f:
            f.write(str(module_counter))
        return True  # Successfully set thermal data
    except Exception as e:
        print(f"Error setting module counter: {str(e)}")
        return False


def thermal_data_set_asic(asic_index, temperature, warning_threshold, critical_threshold, fault=0):
    """Function sets asic data."""
    if not check_asic_index(asic_index):
        return False

    # Define file paths based on asic_index
    if asic_index == 0:
        temp_crit_file = os.path.join(BASE_PATH, "thermal", "asic_temp_crit")
        temp_input_file = os.path.join(BASE_PATH, "thermal", "asic")
        temp_emergency_file = os.path.join(BASE_PATH, "thermal", "asic_temp_emergency")
        temp_fault_file = os.path.join(BASE_PATH, "thermal", "asic_temp_fault")
    else:
        temp_crit_file = os.path.join(BASE_PATH, "thermal", f"asic{asic_index + 1}_temp_crit")
        temp_input_file = os.path.join(BASE_PATH, "thermal", f"asic{asic_index + 1}")
        temp_emergency_file = os.path.join(BASE_PATH, "thermal", f"asic{asic_index + 1}_temp_emergency")
        temp_fault_file = os.path.join(BASE_PATH, "thermal", f"asic{asic_index + 1}_temp_fault")

    # Create the files if they don't exist and write the values
    try:
        with open(temp_crit_file, 'w', encoding="utf-8") as f:
            f.write(str(critical_threshold))
        with open(temp_input_file, 'w', encoding="utf-8") as f:
            f.write(str(temperature))
        with open(temp_emergency_file, 'w', encoding="utf-8") as f:
            f.write(str(warning_threshold))
        with open(temp_fault_file, 'w', encoding="utf-8") as f:
            f.write(str(fault))
        return True  # Successfully set thermal data
    except Exception as e:
        print(f"Error setting thermal data for ASIC {asic_index}: {str(e)}")
        return False


def thermal_data_set_module(asic_index,
                            module_index,
                            temperature,
                            warning_threshold,
                            critical_threshold,
                            fault=0):
    """Function sets module data."""
    if not check_asic_index(asic_index) or not check_module_index(asic_index, module_index):
        return False

    # Define file paths
    temp_crit_file = os.path.join(BASE_PATH, "thermal", f"module{module_index}_temp_crit")
    temp_input_file = os.path.join(BASE_PATH, "thermal", f"module{module_index}_temp_input")
    temp_emergency_file = os.path.join(BASE_PATH, "thermal", f"module{module_index}_temp_emergency")
    temp_fault_file = os.path.join(BASE_PATH, "thermal", f"module{module_index}_temp_fault")

    # Create the files if they don't exist and write the values
    try:
        with open(temp_crit_file, 'w', encoding="utf-8") as f:
            f.write(str(critical_threshold))
        with open(temp_input_file, 'w', encoding="utf-8") as f:
            f.write(str(temperature))
        with open(temp_emergency_file, 'w', encoding="utf-8") as f:
            f.write(str(warning_threshold))
        with open(temp_fault_file, 'w', encoding="utf-8") as f:
            f.write(str(fault))
        return True  # Successfully set thermal data for the module
    except Exception as e:
        print(f"Error setting thermal data for Module {module_index}: {str(e)}")
        return False


vendor_data_key_replace = {
    "part_number": "PN",
    "manufacturer": "Manufacturer"
}


def vendor_data_set_module(asic_index,
                           module_index,
                           vendor_info=None):
    """Function sets module vendor data."""
    if not check_asic_index(asic_index) or not check_module_index(asic_index, module_index):
        return False

    # Define file paths
    vendor_file = os.path.join(BASE_PATH, "eeprom", f"module{module_index}_data")
    # Create the file if it doesn't exist and write the values
    try:
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
        else:
            if os.path.exists(vendor_file):
                os.remove(vendor_file)
        return True  # Successfully set vendor data for the module
    except Exception as e:
        print(f"Error setting vendor data for Module {module_index}: {str(e)}")
        return False


def thermal_data_clean_asic(asic_index):
    """Function cleans asic data."""
    if not check_asic_index(asic_index):
        return False

    # Define file paths based on asic_index
    if asic_index == 0:
        temp_crit_file = os.path.join(BASE_PATH, "thermal", "asic_temp_crit")
        temp_input_file = os.path.join(BASE_PATH, "thermal", "asic")
        temp_emergency_file = os.path.join(BASE_PATH, "thermal", "asic_temp_emergency")
        temp_fault_file = os.path.join(BASE_PATH, "thermal", "asic_temp_fault")
    else:
        temp_crit_file = os.path.join(BASE_PATH, "thermal", f"asic{asic_index + 1}_temp_crit")
        temp_input_file = os.path.join(BASE_PATH, "thermal", f"asic{asic_index + 1}")
        temp_emergency_file = os.path.join(BASE_PATH, "thermal", f"asic{asic_index + 1}_temp_emergency")
        temp_fault_file = os.path.join(BASE_PATH, "thermal", f"asic{asic_index + 1}_temp_fault")

    # Remove the files if they exist
    try:
        os.remove(temp_crit_file)
        os.remove(temp_input_file)
        os.remove(temp_emergency_file)
        os.remove(temp_fault_file)
        return True  # Successfully cleaned thermal data for the ASIC
    except Exception as e:
        print(f"Error cleaning thermal data for ASIC {asic_index}: {str(e)}")
        return False


def thermal_data_clean_module(asic_index, module_index):
    """Function cleans module data."""
    if not check_asic_index(asic_index) or not check_module_index(asic_index, module_index):
        return False

    # Define file paths
    temp_crit_file = os.path.join(BASE_PATH, "thermal", f"module{module_index}_temp_crit")
    temp_input_file = os.path.join(BASE_PATH, "thermal", f"module{module_index}_temp_input")
    temp_emergency_file = os.path.join(BASE_PATH, "thermal", f"module{module_index}_temp_emergency")
    temp_fault_file = os.path.join(BASE_PATH, "thermal", f"module{module_index}_temp_fault")

    # Remove the files if they exist
    try:
        os.remove(temp_crit_file)
        os.remove(temp_input_file)
        os.remove(temp_emergency_file)
        os.remove(temp_fault_file)
        return True  # Successfully cleaned thermal data for the module
    except Exception as e:
        print(f"Error cleaning thermal data for Module {module_index}: {str(e)}")
        return False


def vendor_data_clear_module(asic_index,
                             module_index):
    """Function cleans module vendor data."""
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
