#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
# pylint: disable=W0718
# pylint: disable=R0913
########################################################################
# Copyright (c) 2023 NVIDIA CORPORATION & AFFILIATES.
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
"""Module providing functions for setting dpu's CPU/DDR/DISK NVME thermal data."""
import os

ERROR_READ_THERMAL_DATA = 254000

BASE_PATH = "/var/run/hw-management"

def get_dpu_count():
    """
    @summary: Function gets DPU count from "{BASE_PATH}/config/dpu_num.
    @return: # of dpus:in case of succesful read, 
             -1       :if path does not exist, or cannot be read
    """
    dpu_count_file = os.path.join(BASE_PATH, "config", "dpu_num")
    if os.path.exists(dpu_count_file):
        try:
            with open(dpu_count_file, 'r', encoding="utf-8") as f:
                return int(f.read())
        except Exception as e:
            print(f"Error reading DPU count: {str(e)}")
            return -1
    else:
        print(f"Error: Could not read DPU count from {dpu_count_file}")
        return -1

def check_dpu_index(dpu_index):
    """
    @summary: Function checks dpu index boundary.
    @param dpu_index: the index of the dpu , should be 1- dpu_count
    @return: False:if # of dpu in system is unreadable or 
                   dpu index is out of range (1-dpu_count), 
             True :otherwise
    """
    dpu_count = get_dpu_count()

    if dpu_count is -1:
        return False

    if 0 < dpu_index <= dpu_count:
        return True

    print(f"dpu_index {dpu_index} is out of bound 1..DPU count")
    return False

def remove_file_safe(file_path):
    """
    @summary: Function Safely removes a file if it exists.
    @param file_path: file path to remove
    @return: void
    """
    if os.path.exists(file_path):
        try:
            os.remove(file_path)
        except Exception as e:
            print(f"file path didn't exist {str(file_path)}: {str(e)}")

def create_path_safe(path):
    """
    @summary: Function Safely create a path if it doesn't exist.
    @param path:  path to create
    @return: True :if path already exist or if created correctly, 
             False:creation of path failed.
    """
    if os.path.exists(path) is False:
        try:
            os.mkdir(path)
        except Exception as e:
            print(f"Path can't be created {str(path)}: {str(e)}")
            return False

    return True

def thermal_data_dpu_cpu_core_set(dpu_index, temperature, warning_threshold=None, critical_temperature=None, fault=0):
    """
    @summary: Function sets dpu's cpu core thermal data
    @param dpu_index:  dpu index 
    @param temperature:  tempreture input   
    @param warning_threshold:  tempreture warning threshold input
    @param critical_temperature:  critical temperature threshold input
    @param fault: fault input   
    @return: False:in case dpu_index is out of bound or 
                   path to dpu{x} does not exist or cannot be created or 
                   or input files cannot be created under the path or they cannot be updated.
             True: otherwise - writing to input files is succesful
    """
    if not check_dpu_index(dpu_index):
        return False

    file_path = os.path.join(BASE_PATH,  f"dpu{dpu_index}")
    file_path_status = create_path_safe(file_path)
    if file_path_status is False:
        return False

    file_path = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal")
    file_path_status = create_path_safe(file_path)
    if file_path_status is False:
        return False

    # Define file paths based on dpu_index
    temp_input_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/cpu_pack")
    temp_fault_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/cpu_pack_fault")
    if warning_threshold is not None:
        temp_warning_threshold_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/cpu_pack_max")
    if critical_temperature is not None:
        temp_critical_temperature_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/cpu_pack_crit")

    # Create the files if they don't exist and write the values
    try:
        with open(temp_input_file, 'w', encoding="utf-8") as f:
            f.write(str(temperature))
        with open(temp_fault_file, 'w', encoding="utf-8") as f:
            f.write(str(fault))
        if warning_threshold is not None:
            with open(temp_warning_threshold_file, 'w', encoding="utf-8") as f:
                f.write(str(warning_threshold))
        if critical_temperature is not None:
            with open(temp_critical_temperature_file, 'w', encoding="utf-8") as f:
                f.write(str(critical_temperature))
        return True  # Successfully set thermal data
    except Exception as e:
        print(f"Error setting thermal data for DPU CPU {dpu_index}: {str(e)}")
        return False

def thermal_data_dpu_ddr_set(dpu_index, temperature, warning_threshold=None, critical_temperature=None, fault=0):
    """
    @summary: Function sets dpu's ddr thermal data.
    @param dpu_index:  dpu index 
    @param temperature:  tempreture input   
    @param warning_threshold:  tempreture warning threshold input
    @param critical_temperature:  critical temperature threshold input
    @param fault: fault input   
    @return: False:in case dpu_index is out of bound or 
                   path to dpu{x} does not exist or cannot be created or 
                   or input files cannot be created under the path or they cannot be updated.
             True: otherwise - writing to input files is succesful
    """
    if not check_dpu_index(dpu_index):
        return False

    file_path = os.path.join(BASE_PATH,  f"dpu{dpu_index}")
    file_path_status = create_path_safe(file_path)
    if file_path_status is False:
        return False

    file_path = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal")
    file_path_status = create_path_safe(file_path)
    if file_path_status is False:
        return False

    # Define file paths based on dpu_index
    temp_input_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/sodimm_temp_input")
    temp_fault_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/sodimm_temp_fault")
    if warning_threshold is not None:
        temp_warning_threshold_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/sodimm_temp_max")
    if critical_temperature is not None:
        temp_critical_temperature_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/sodimm_temp_crit")

    # Create the files if they don't exist and write the values
    try:
        with open(temp_input_file, 'w', encoding="utf-8") as f:
            f.write(str(temperature))
        with open(temp_fault_file, 'w', encoding="utf-8") as f:
            f.write(str(fault))
        if warning_threshold is not None:
            with open(temp_warning_threshold_file, 'w', encoding="utf-8") as f:
                f.write(str(warning_threshold))
        if critical_temperature is not None:
            with open(temp_critical_temperature_file, 'w', encoding="utf-8") as f:
                f.write(str(critical_temperature))
        return True  # Successfully set thermal data
    except Exception as e:
        print(f"Error setting thermal data for DPU DDR {dpu_index}: {str(e)}")
        return False

def thermal_data_dpu_drive_set(dpu_index, temperature, warning_threshold=None, critical_temperature=None, fault=0):
    """
    @summary: Function sets dpu's drive NVME thermal data.
    @param dpu_index:  dpu index 
    @param temperature:  tempreture input   
    @param warning_threshold:  tempreture warning threshold input
    @param critical_temperature:  critical temperature threshold input
    @param fault: fault input   
    @return: False:in case dpu_index is out of bound or 
                   path to dpu{x} does not exist or cannot be created or 
                   or input files cannot be created under the path or they cannot be updated.
             True: otherwise - writing to input files is succesful
    """
    if not check_dpu_index(dpu_index):
        return False

    file_path = os.path.join(BASE_PATH,  f"dpu{dpu_index}")
    file_path_status = create_path_safe(file_path)
    if file_path_status is False:
        return False

    file_path = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal")
    file_path_status = create_path_safe(file_path)
    if file_path_status is False:
        return False

    # Define file paths based on dpu_index
    temp_input_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/drivetemp")
    temp_fault_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/drivetemp_fault")
    if warning_threshold is not None:
        temp_warning_threshold_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/drivetemp_max")
    if critical_temperature is not None:
        temp_critical_temperature_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/drivetemp_crit")

    # Create the files if they don't exist and write the values
    try:
        with open(temp_input_file, 'w', encoding="utf-8") as f:
            f.write(str(temperature))
        with open(temp_fault_file, 'w', encoding="utf-8") as f:
            f.write(str(fault))
        if warning_threshold is not None:
            with open(temp_warning_threshold_file, 'w', encoding="utf-8") as f:
                f.write(str(warning_threshold))
        if critical_temperature is not None:
            with open(temp_critical_temperature_file, 'w', encoding="utf-8") as f:
                f.write(str(critical_temperature))
        return True  # Successfully set thermal data
    except Exception as e:
        print(f"Error setting thermal data for DPU drive {dpu_index}: {str(e)}")
        return False

def thermal_data_dpu_cpu_core_clear(dpu_index):

    """
    @summary: Function cleans dpu's cpu core thermal data.
    @param dpu_index: the index of the dpu , should be 1- dpu_count
    @return: False:if # of dpu in system is unreadable or 
                   dpu index is out of range (1-dpu_count),or
                   the erase of any of the relevant files failed
             True :otherwise
    """
    if not check_dpu_index(dpu_index):
        return False

    # Define file paths
    temp_input_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/cpu_pack")
    temp_warning_threshold_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/cpu_pack_max")
    temp_critical_temperature_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/cpu_pack_crit")
    temp_fault_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/cpu_pack_fault")
    # Remove the files if they exist
    try:
        remove_file_safe(temp_input_file)
        remove_file_safe(temp_fault_file)
        remove_file_safe(temp_warning_threshold_file)
        remove_file_safe(temp_critical_temperature_file)
        return True  # Successfully cleaned thermal data for the module
    except Exception as e:
        print(f"Error cleaning thermal data for DPU CPU {dpu_index}: {str(e)}")
        return False

def thermal_data_dpu_ddr_clear(dpu_index):
    """
    @summary: Function cleans dpu's ddr thermal data.
    @param dpu_index: the index of the dpu , should be 1- dpu_count
    @return: False:if # of dpu in system is unreadable or 
                   dpu index is out of range (1-dpu_count),or
                   the erase of any of the relevant files failed
             True :otherwise
    """
    if not check_dpu_index(dpu_index):
        return False

    # Define file paths
    temp_input_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/sodimm_temp_input")
    temp_warning_threshold_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/sodimm_temp_max")
    temp_critical_temperature_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/sodimm_temp_crit")
    temp_fault_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/sodimm_temp_fault")
    # Remove the files if they exist
    try:
        remove_file_safe(temp_input_file)
        remove_file_safe(temp_fault_file)
        remove_file_safe(temp_warning_threshold_file)
        remove_file_safe(temp_critical_temperature_file)
        return True  # Successfully cleaned thermal data for the module
    except Exception as e:
        print(f"Error cleaning thermal data for DPU DDR {dpu_index}: {str(e)}")
        return False

def thermal_data_dpu_drive_clear(dpu_index):
    """
    @summary: Function cleans dpu's drive NVME thermal data.
    @param dpu_index: the index of the dpu , should be 1- dpu_count
    @return: False:if # of dpu in system is unreadable or 
                   dpu index is out of range (1-dpu_count),or
                   the erase of any of the relevant files failed
             True :otherwise
    """
    if not check_dpu_index(dpu_index):
        return False

    # Define file paths
    temp_input_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/drivetemp")
    temp_warning_threshold_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/drivetemp_max")
    temp_critical_temperature_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/drivetemp_crit")
    temp_fault_file = os.path.join(BASE_PATH,  f"dpu{dpu_index}","thermal/drivetemp_fault")
    # Remove the files if they exist
    try:
        remove_file_safe(temp_input_file)
        remove_file_safe(temp_fault_file)
        remove_file_safe(temp_warning_threshold_file)
        remove_file_safe(temp_critical_temperature_file)
        return True  # Successfully cleaned thermal data for the module
    except Exception as e:
        print(f"Error cleaning thermal data for DPU drive {dpu_index}: {str(e)}")
        return False

#def main():
#    """Function main."""
#    dpu_count = get_dpu_count()
#    print(f"DPU count {dpu_count}")
#    thermal_data_dpu_cpu_core_set(3, 21, warning_threshold = 71, critical_temperature = 81, fault = 0)
#    thermal_data_dpu_ddr_set(3, 22, warning_threshold = 72, critical_temperature = 82, fault = 0)
#    thermal_data_dpu_drive_set(3, 23, warning_threshold = 73, critical_temperature = 83, fault = 0)
#
#    thermal_data_dpu_cpu_core_set(2, 21, warning_threshold = 71, critical_temperature = 81, fault = 0)
#    thermal_data_dpu_ddr_set(2, 22, warning_threshold = 72, critical_temperature = 82, fault = 0)
#    thermal_data_dpu_drive_set(2, 23, warning_threshold = 73, critical_temperature = 83, fault = 0)
#
#    thermal_data_dpu_cpu_core_clear(2)
#    thermal_data_dpu_ddr_clear(2)
#    thermal_data_dpu_drive_clear(2)
#
#    thermal_data_dpu_cpu_core_clear(3)
#    thermal_data_dpu_ddr_clear(3)
#    thermal_data_dpu_drive_clear(3)
#if __name__ == "__main__":
#    main()
