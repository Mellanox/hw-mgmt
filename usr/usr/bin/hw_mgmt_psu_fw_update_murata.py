#!/usr/bin/python
########################################################################
# Copyright (c) 2021 NVIDIA CORPORATION & AFFILIATES.
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

'''
Created on June 15, 2021

Author: Mykola Kostenok <c_mykolak@nvidia.com>
Version: 0.1

Description:
Murata PSU FW update tool.

'''

import sys, time, argparse
from textwrap import wrap

import hw_mgmt_psu_fw_update_common as hw_mgmt_pmbus

ps_status_addr = 0xE0
upgrade_status_addr = 0xFA
bootloader_status_addr = 0xFB


def read_murata_secondary_revision(i2c_bus, i2c_addr):
    hw_mgmt_pmbus.pmbus_page(i2c_bus, i2c_addr, 1)
    ret = hw_mgmt_pmbus.pmbus_read_block(i2c_bus, i2c_addr, 0x9b)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        hw_mgmt_pmbus.pmbus_page(i2c_bus, i2c_addr, 0)
        ascii_str = ''.join(chr(int(i, 16)) for i in ret.split())[1:]
        print(ascii_str)
        return ascii_str


def power_supply_reset(i2c_bus, i2c_addr):
    data = [0xf8, 0xaf]
    hw_mgmt_pmbus.pmbus_write_nopec(i2c_bus, i2c_addr, data)


def end_of_file(i2c_bus, i2c_addr):
    data = [0xfa, 0x44, 0x01, 0x00]
    data.extend([0] * 32)
    data.extend([0x00, 0xc1])
    hw_mgmt_pmbus.pmbus_write_nopec(i2c_bus, i2c_addr, data)


def check_power_supply_status(i2c_bus, i2c_addr):
    ret = hw_mgmt_pmbus.pmbus_read(i2c_bus, i2c_addr, ps_status_addr, 3)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        # print("check_power_supply_status: {}".format(ret))
        ps_status = [int(i, 16) for i in ret.split()]
        bootoader_mode = ps_status[1] & 1 << 2
        bootload_complette = ps_status[1] & 1 << 1
        power_down = ps_status[1] & 1 << 0
        print("bootoader_mode:{0}, bootload_complette:{1}, power_down:{2}".format(bootoader_mode, bootload_complette, power_down))


upgrade_status_dict = {
    0x18: "POLL_STATUS_FAILED",
    0x33: "POLL_STATUS_POWERDOWN",
    0x55: "POLL_STATUS_BUSY",
    0x81: "POLL_STATUS_SUCCSESS",
    0xaa: "POLL_STATUS_NOTACTIVE",
    # This indicates checksum check error in the payload in the packet that was just received.
    0x16: "POLL_STATUS_DATA_ERROR",
    # Data not recognized.
    0x10: "POLL_STATUS_INVALID_RECORD_TYPE"
    }


def poll_upgrade_status(i2c_bus, i2c_addr):
    ret = hw_mgmt_pmbus.pmbus_read(i2c_bus, i2c_addr, upgrade_status_addr, 1)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        upgrade_status = upgrade_status_dict.get(int(ret, 16), "POLL_STATUS_UNDEFINED")
        # print(upgrade_status)
        return upgrade_status


def test_poll_upgrade_status(i2c_bus, i2c_addr):
    retry = 0
    while True:
        upgrade_status = poll_upgrade_status(i2c_bus, i2c_addr)
        if (upgrade_status != "POLL_STATUS_BUSY") or (retry > 3):
            break
        time.sleep(0.3)
        retry += 1

    if (upgrade_status != "POLL_STATUS_SUCCSESS"):
        print("PSU FW upgrade failed.")
        exit(1)


bootloader_status_dict = {
    0: "BOOTLOADER_STATUS_NONE",
    1 << 0: "B0OTLOADING_PRIMARY",
    1 << 1: "BO0TLOADING_FLOATING",
    1 << 2: "BO0TLOADING_SECONDARY",
    1 << 3: "B0OTLOADING_PRIMARY_COMPLETED",
    1 << 4: "BO0TLOADING_FLOATING_COMPLETED",
    1 << 5: "BO0TLOADING_SECONDARY_COMPLETED",
    1 << 6: "RESET_PRIMARY_COMPLETED",
    1 << 7: "RESET_FLOATING_COMPLETED",
    }


def bootloader_status(i2c_bus, i2c_addr):
    ret = hw_mgmt_pmbus.pmbus_read(i2c_bus, i2c_addr, bootloader_status_addr, 1)
    if ret != '' and len(ret) > 3 and ret[:2] == '0x':
        bootloader_status = bootloader_status_dict.get(int(ret, 16))
        print(bootloader_status)
        return bootloader_status


def two_complement_checksum(data):
    return (-(sum(c for c in data) % 256) & 0xFF)


def upgrade_data_command(i2c_bus, i2c_addr, data):
    send_data = [0xfa, 0x44, 0x0, 0x0 ]
    send_data.extend(data)
    res_chksum = two_complement_checksum(send_data)
    send_data.extend([0x0, res_chksum])
    # print(send_data)
    hw_mgmt_pmbus.pmbus_write_nopec(i2c_bus, i2c_addr, send_data)


def burn_fw_file(i2c_bus, i2c_addr, fw_filename):
    data_flag = 0
    with open(fw_filename) as fp:
        for line in fp:
            if "[data]" in line:
                data_flag = 1
                continue
            if "[checksum]" in line:
                data_flag = 0
            if data_flag == 1:
                data = line.split("=")[1:]
                data_str = data[0].rstrip("\n")
                data_arr = [int(i, 16) for i in wrap(data_str, 2)]
                # print(data_str)
                # print(data_arr)
                upgrade_data_command(i2c_bus, i2c_addr, data_arr)
                test_poll_upgrade_status(i2c_bus, i2c_addr)


microtype_dict = {
    "MICROTYPE_PRIMARY": 0x50,
    "MICROTYPE_SECONDARY": 0x53,
    "MICROTYPE_FLOATING": 0x46,
    }


def enter_bootload_mode(i2c_bus, i2c_addr):
    data = [0xfa, 0x42]
    data.extend([microtype_dict["MICROTYPE_SECONDARY"]])
    data.extend([0x44, 0x41, 0x54, 0x50])
    hw_mgmt_pmbus.pmbus_write(i2c_bus, i2c_addr, data)


bootloader_i2c_addr = 0x60


def murata_update(i2c_bus, i2c_addr, continue_update, fw_filename):

    # If coninue_update skip entering to boot_mode.
    if(continue_update != True):
        # 1. Read current firmware revision using command the READ_MFG_FW_REVISION.
        read_murata_secondary_revision(i2c_bus, i2c_addr)

        check_power_supply_status(i2c_bus, i2c_addr)

        # 2. Send the ENTER_BOOTLOAD_MODE command during Normal Operation.
        enter_bootload_mode(i2c_bus, i2c_addr)

        # 3. When the command is received.
            # a. The Power supply will enter a power down state, shutting down main power conversion.
                # i. Power Supply will respond POWER_DOWN.
            # b. Upon successful power down, the power supply enters Bootload Mode.
            # c. The power supply will change the PMBus address to 0x60 and erase the targeted microcontroller.
                # i. Power Supply will respond BUSY during the erase the process.
            # d. Wait for host to initiate data transfer.
                # i. Power Supply will respond SUCCESS while waiting for data.

        # 4. Wait typically for 1 second to allow the Power Supply to enter Bootload Mode.
        time.sleep(1)

    # 5. Send the POLL_UPGRADE_STATUS command for successful entry into Bootload Mode.
        # 5a. Send the Host POWER_DOWN, BUSY or SUCCESS.

        if poll_upgrade_status(i2c_bus, bootloader_i2c_addr) != "POLL_STATUS_SUCCSESS":
            print("failed to enter boot mode");
            exit(1)

    # 6. Send the PAGE command to get the microcontroller ready for the data dump.
    hw_mgmt_pmbus.pmbus_page_nopec(i2c_bus, bootloader_i2c_addr, 0x01)

    # 7. For each line in the app file.
    burn_fw_file(i2c_bus, bootloader_i2c_addr, fw_filename)

    # 8. Send the END_OF_FILE command to the Power Supply.
    end_of_file(i2c_bus, bootloader_i2c_addr)

    # 9. Wait typically for 1 second to allow the Power Supply to enter Bootload Mode.
    time.sleep(1)

    # 10. Send the POLL_UPGRADE_STATUS command for a successful transaction.
        # 10a. The target microcontroller will do a soft reset and conducts a checksum test of the upgraded firmware.
        # 10b. If the checksum test passes, the target microcontroller will leave BOOTLOAD Mode and will respond NOT_ACTIVE.
        # 10c. If the checksum test fails, the target microcontroller remains in BOOTLOAD Mode and will response
        #     SUCCESS. The SUCCESS response refers to successfully entering BOOTLOAD Mode. (Read Section: What to
        #     do if IN-SYSTEM PROGRAMMING fails).

    if poll_upgrade_status(i2c_bus, bootloader_i2c_addr) == "POLL_STATUS_NOTACTIVE":
        print("checksum test passes, the target microcontroller will leave BOOTLOAD Mode");
    else:
        print("checksum test fails, the target microcontroller remains in BOOTLOAD Mode");
        exit(1)

    # 11. Repeat steps 1-9 to upgrade remaining microcontrollers.
    # Now we updating only secondary, so nothing todo here.
    # 12. Upgrading is complete, send the POWER_SUPPLY_RESET command.
    power_supply_reset(i2c_bus, bootloader_i2c_addr)
        # 12a. The Power Supply will send all microcontrollers a soft reset command. This will allow all the
        #    microcontrollers to restart together.
        # 12b. The Power Supply will leave Bootload Mode and change its PMBus address back to the address for Normal Operation.
        # 12c. After restart, the power supply will begin to deliver power again.
    time.sleep(2)
    # 13. To confirm the Power Supply is running upgraded firmware, send the READ_MFG_FW_REVISION command.
    read_murata_secondary_revision(i2c_bus, i2c_addr)


def main(argv):
    parser = argparse.ArgumentParser()
    required = parser.add_argument_group('required arguments')
    required.add_argument('-i', "--input_file", required=True)
    required.add_argument('-b', "--i2c_bus", type=int, default=0, required=True)
    required.add_argument('-a', "--i2c_addr", type=lambda x: int(x, 0), default=0, required=True)
    args = parser.parse_args()

    print('Input args "', args.input_file, args.i2c_bus, args.i2c_addr)
    # read_mfr_id(i2c_bus, i2c_adr)
    # read_mfr_model(i2c_bus, i2c_adr)
    # read_mfr_revision(i2c_bus, i2c_adr)
    # read_murata_secondary_revision(i2c_bus, i2c_adr)
    # check_power_supply_status(i2c_bus, i2c_adr)
    # poll_upgrade_status(i2c_bus, i2c_adr)
    # bootloader_status(i2c_bus, i2c_adr)
    # burn_fw_file(i2c_bus, i2c_addr)

    murata_update(args.i2c_bus, args.i2c_addr, False, args.input_file)


if __name__ == "__main__":
    main(sys.argv[1:])

