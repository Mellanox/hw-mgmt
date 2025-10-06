#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2024-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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

# test_bmcaccessor_login
from hw_management_redfish_client import BMCAccessor, RedfishClient
import unittest
import json
import socket
import time
import os
import argparse
import sys
import subprocess
import pytest

# Mark all tests in this module as hardware
pytestmark = pytest.mark.hardware

# Path configured in conftest.py - no need for manual sys.path manipulation


class TestBMCAccessorLogin(unittest.TestCase):
    bmc_ip_arg = None

    def setUp(self):
        self.root = "root"
        self.root_default_pwd = "0penBmc"
        self.root_pwd = "ABYX12#14artb"
        self.bmc_accessor = BMCAccessor()
        self.tpm_pwd = self.bmc_accessor.get_login_password()
        self.default_user_pwd = self.bmc_accessor.BMC_ACCOUNT_DEFAULT_PASSWORD
        self.default_admin_pwd = self.bmc_accessor.BMC_DEFAULT_PASSWORD
        # self.bmc_ip = self.bmc_accessor.BMC_INTERNAL_IP_ADDR
        self.rf_client = self.bmc_accessor.rf_client
        if TestBMCAccessorLogin.bmc_ip_arg:
            self.bmc_ip = TestBMCAccessorLogin.bmc_ip_arg
        else:
            self.bmc_ip = self.bmc_accessor.BMC_INTERNAL_IP_ADDR

    def custom_sleep_with_ping(self, seconds):
        server = self.bmc_ip
        print(f'sleeping/pinging for {seconds} seconds')
        start_time = time.time()

        while time.time() - start_time < seconds:
            response = subprocess.run(['ping', '-c', '1', server], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if response.returncode == 0:
                # print(f"Ping to {server} successful.")
                pass
            else:
                # print(f"Ping to {server} failed.")
                pass
            time.sleep(1)

        print(f"{seconds} seconds have passed.")

    def ping_until_reachable_with_timeout(self):
        timeout_minutes = 1
        start_time = time.time()
        timeout_seconds = timeout_minutes * 60

        print(f'ping_until_reachable_with_timeout: {timeout_seconds} seconds')

        while True:
            response = subprocess.run(['ping', '-c', '1', self.bmc_ip], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if response.returncode == 0:
                print(f"Server {self.bmc_ip} is reachable. Exiting...")
                return RedfishClient.ERR_CODE_OK
            else:
                # print(f"Server {self.bmc_ip} is unreachable. Continuing to ping...")
                pass

            if time.time() - start_time > timeout_seconds:
                print(f"Timeout of {timeout_minutes} minutes reached. Exiting...")
                return RedfishClient.ERR_CODE_TIMEOUT

            time.sleep(1)

    def ping_until_unreachable_with_timeout(self):
        start_time = time.time()
        timeout_minutes = 1
        timeout_seconds = timeout_minutes * 60

        print(f'ping_until_unreachable_with_timeout: {timeout_seconds} seconds')

        while True:
            response = subprocess.run(['ping', '-c', '1', self.bmc_ip], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if response.returncode != 0:
                print(f"Server {self.bmc_ip} is unreachable. Exiting...")
                return RedfishClient.ERR_CODE_OK
            else:
                # print(f"Server {self.bmc_ip} is reachable. Continuing to ping...")
                pass

            if time.time() - start_time > timeout_seconds:
                print(f"Timeout of {timeout_minutes} minutes reached. Exiting...")
                return RedfishClient.ERR_CODE_TIMEOUT

            time.sleep(1)

    def wait_for_bmc_ready(self):
        start_time = time.time()
        timeout = 300  # seconds
        interval = 2  # seconds

        print(f'wait_for_bmc_ready...')
        cmd = self.rf_client.build_get_cmd(RedfishClient.REDFISH_URI_UPDATE_SERVICE)
        while time.time() - start_time < timeout:
            try:
                print(f"cmd: {cmd}")
                ret, output, error = self.rf_client.exec_curl_cmd(cmd)
                if ret != 0:
                    print(f"Not Ready yet: {ret}")
                    continue
                response = json.loads(output)
                status = response.get("Status", {})
                if status.get("State") == "Enabled":
                    print("BMC is ready!")
                    return True
                print("BMC not ready yet. Retrying...")

            except Exception as e:
                print(f"An error occurred: {e}")
            time.sleep(interval)
        print("Timeout reached. BMC is not ready.")
        return False

    def reset_defaults(self):
        # curl -k -u root:ABYX12#14artb -H 'Content-Type:application/json' -X POST -d '{"ResetToDefaultsType": "ResetAll"}' https://10.0.1.1/redfish/v1/Managers/BMC_0/Actions/Oem/NvidiaManager.ResetToDefaults
        cmd = self.rf_client.build_post_cmd("/redfish/v1/Managers/BMC_0/Actions/Oem/NvidiaManager.ResetToDefaults", {
            "ResetToDefaultsType": "ResetAll"
        })
        print(f'cmd: {cmd}')
        (ret, out, err) = self.rf_client.exec_curl_cmd(cmd)
        # print(f'ret: {ret}')
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "Root login should succeed")

    def delete_user(self, user):
        cmd = self.rf_client._build_delete_cmd(user)
        print(f'cmd: {cmd}')
        (ret, out, err) = self.rf_client.exec_curl_cmd(cmd)
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "delete account should succeed")

        # print(ret)
        # print(out)

    def patch_user(self, user, pwd, new_pwd):
        # cmd = ("/usr/bin/curl -k -u root:0penBmc " '-H "Content-Type: application/json" -X PATCH ' "https://10.0.1.1/redfish/v1/AccountService/Accounts/root " '-d \'{"Password" : "ABYX12#14artb"}\'')
        cmd = self.rf_client._build_change_user_password_after_factory_cmd(user, pwd, new_pwd)
        print(f'cmd: {cmd}')
        # self.custom_sleep_with_ping(5)

        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True, text=True)
        stdout, stderr = process.communicate()
        # self.custom_sleep_with_ping(5)
        # print(f'try once again...')
        # print(f'{cmd}')
        # process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True, text=True)
        # stdout, stderr = process.communicate()
        # print(stdout)
        # print(stderr)
        if process.returncode == 0:
            ret = RedfishClient.ERR_CODE_OK
        else:
            ret = RedfishClient.ERR_CODE_GENERIC_ERROR

        return ret

    def simulate_factory_of_old_bmc(self):
        # there are several cases here: we would like to simulate factory where after it we have only admin and root,
        # however on the new bmc we have also yormnAnb account
        # cases:
        # flow1: new bmc, after factory, root with 0penbmc pwd, yormnAnb exists
        # target: after factory, root with ABYX12#14artb, admin with 0penBmc, yormnAnb not exists
        # steps:
        # fail to login with root and ABYX12#14artb
        # patch root

        # run factory
        # patch root
        # login with root
        # delete anyway yormAnb
        # ready
        # flow2: new bmc, boot2, root with ABYX12#14artb, yormnAnb exists
        # target: after factory, root with ABYX12#14artb, admin with 0penBmc, yormnAnb not exists
        # steps
        # login with root and ABYX12#14artb

        # run factory
        # patch root
        # login with root
        # delete anyway yormAnb
        # ready
        # flow3: old bmc, after factory, root with 0penbmc pwd
        # target: after factory, root with ABYX12#14artb, admin with 0penBmc, yormnAnb not exists
        # steps
        # fail to login with root and ABYX12#14artb
        # patch root

        # run factory
        # patch root
        # login with root
        # delete anyway yormAnb
        # ready
        # flow4: old bmc, boot2, root with ABYX12#14artb
        # target: after factory, root with ABYX12#14artb, admin with 0penBmc, yormnAnb not exists
        # steps
        # login root with ABYX12#14artb

        # run factory
        # patch root
        # login with root
        # delete anyway yormAnb
        # ready
        print(f'Login as root:{self.root_pwd}')
        self.rf_client.update_credentials(self.root, self.root_pwd)
        ret = self.rf_client.login()
        if (ret != RedfishClient.ERR_CODE_OK):
            print(f'failed to login with root:{self.root_pwd}, patch root')
            # print(f'patch root (should be sent more than once ...)')
            ret = self.patch_user("root", self.root_default_pwd, self.root_pwd)
            self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "root should be patched successfully]")

        print(f'Login as root')
        self.rf_client.update_credentials(self.root, self.root_pwd)
        ret = self.rf_client.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "Root login should succeed")

        print(f'perform factory RF')
        self.reset_defaults()
        # self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "Root login should succeed")

        self.ping_until_unreachable_with_timeout()
        time.sleep(50)
        response = subprocess.run(['ifup', 'usb0'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        self.ping_until_reachable_with_timeout()
        self.custom_sleep_with_ping(25)

        print(f'patch root')
        ret = self.patch_user("root", self.root_default_pwd, self.root_pwd)
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "root should be patched successfully]")

        print(f'Login as root')
        self.rf_client.update_credentials(self.root, self.root_pwd)
        ret = self.rf_client.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "Root login should succeed")

        self.wait_for_bmc_ready()

        # self.rf_client.update_credentials(self.root, self.root_pwd)
        # ret = self.rf_client.login()
        get_cmd = self.rf_client.build_get_cmd(RedfishClient.REDFISH_URI_ACCOUNTS)
        print(f'cmd: {get_cmd}')
        ret, response, error = self.rf_client.exec_curl_cmd(get_cmd)
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "get accounts should succeed")

        # print(f'ret:{ret}')
        # print(f'response:{response}')

        accounts = json.loads(response)
        num_of_account = accounts.get("Members@odata.count")
        self.assertEqual(num_of_account, 3, "since it is new bmc, should exist admin root and yormnAnb accounts")

        print(f'Remove yormnAnb')
        self.delete_user(self.bmc_accessor.BMC_ACCOUNT)

        self.rf_client.update_credentials(self.root, self.root_pwd)
        ret = self.rf_client.login()
        get_cmd = self.rf_client.build_get_cmd(RedfishClient.REDFISH_URI_ACCOUNTS)
        print(f'cmd: {get_cmd}')
        ret, response, error = self.rf_client.exec_curl_cmd(get_cmd)
        # print(f'ret:{ret}')
        # print(f'response:{response}')
        accounts = json.loads(response)
        num_of_account = accounts.get("Members@odata.count")
        self.assertEqual(num_of_account, 2, "should exist admin and root accounts only")

        print(f'done with simulating factory with old bmc ( BMC without yormnAnb account)')

    def simulate_factory_of_new_bmc(self):
        print(f'Login as root:{self.root_pwd}')
        self.rf_client.update_credentials(self.root, self.root_pwd)
        ret = self.rf_client.login()
        if (ret != RedfishClient.ERR_CODE_OK):
            print(f'failed to login with root:{self.root_pwd}, patch root')
            ret = self.patch_user("root", self.root_default_pwd, self.root_pwd)
            self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "root should be patched successfully]")

        print(f'Login as root')
        self.rf_client.update_credentials(self.root, self.root_pwd)
        ret = self.rf_client.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "Root login should succeed")

        print(f'perform factory redfish')
        self.reset_defaults()

        self.ping_until_unreachable_with_timeout()
        time.sleep(50)
        response = subprocess.run(['ifup', 'usb0'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        self.ping_until_reachable_with_timeout()
        self.custom_sleep_with_ping(25)

        print(f'patch root')
        ret = self.patch_user("root", self.root_default_pwd, self.root_pwd)
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "root should be patched successfully]")

        print(f'Login as root')
        self.rf_client.update_credentials(self.root, self.root_pwd)
        ret = self.rf_client.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "Root login should succeed")

        self.wait_for_bmc_ready()

        get_cmd = self.rf_client.build_get_cmd(RedfishClient.REDFISH_URI_ACCOUNTS)
        print(f'cmd: {get_cmd}')
        ret, response, error = self.rf_client.exec_curl_cmd(get_cmd)
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "get accounts should succeed")
        accounts = json.loads(response)
        num_of_account = accounts.get("Members@odata.count")
        self.assertEqual(num_of_account, 3, "since it is new bmc, should exist admin root and yormnAnb accounts")

    def test_simulate_factory_of_old_bmc(self):
        print(f'-- test_simulate_factory_of_old_bmc')
        self.simulate_factory_of_old_bmc()

        self.rf_client.update_credentials(self.root, self.root_pwd)
        ret = self.rf_client.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "failed login with root")

        get_cmd = self.rf_client.build_get_cmd(RedfishClient.REDFISH_URI_ACCOUNTS)
        print(f'get_cmd:{get_cmd}')
        ret, response, error = self.rf_client.exec_curl_cmd(get_cmd)
        # print(f'get accounts {response}')
        accounts = json.loads(response)
        num_of_account = accounts.get("Members@odata.count")
        self.assertEqual(num_of_account, 2, "should exist only admin and root accounts")

        self.rf_client.update_credentials(self.bmc_accessor.BMC_ADMIN_ACCOUNT, self.bmc_accessor.BMC_DEFAULT_PASSWORD)
        ret = self.rf_client.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "failed login with admin")

        get_cmd = self.rf_client.build_get_cmd(RedfishClient.REDFISH_URI_ACCOUNTS)
        print(f'get_cmd:{get_cmd}')
        ret, response, error = self.rf_client.exec_curl_cmd(get_cmd)
        # print(f'get accounts {response}')
        accounts = json.loads(response)
        num_of_account = accounts.get("Members@odata.count")
        self.assertEqual(num_of_account, 2, "should exist only admin and root accounts")

        self.rf_client.update_credentials(self.bmc_accessor.BMC_ACCOUNT, self.bmc_accessor.BMC_ACCOUNT_DEFAULT_PASSWORD)
        ret = self.rf_client.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_BAD_CREDENTIAL, "user yormnAnb should not exist and should fail login with user")

        # user_exists = False

        # for account in accounts.get("Members", []):
        #     if "yormnAnb" in account["@odata.id"]:
        #         user_yorm_exists = True

        # self.assertTrue(user_yorm_exists, "yormnAnb user should be created")

    def test_simulate_factory_of_new_bmc(self):
        print(f'-- test_simulate_factory_of_new_bmc')
        self.simulate_factory_of_new_bmc()

        self.rf_client.update_credentials(self.root, self.root_pwd)
        ret = self.rf_client.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "failed login with root")

        get_cmd = self.rf_client.build_get_cmd(RedfishClient.REDFISH_URI_ACCOUNTS)
        print(f'get_cmd:{get_cmd}')
        ret, response, error = self.rf_client.exec_curl_cmd(get_cmd)
        # print(f'get accounts {response}')
        accounts = json.loads(response)
        num_of_account = accounts.get("Members@odata.count")
        self.assertEqual(num_of_account, 3, "should exist admin root and yormnAnb accounts")

        self.rf_client.update_credentials(self.bmc_accessor.BMC_ADMIN_ACCOUNT, self.bmc_accessor.BMC_DEFAULT_PASSWORD)
        ret = self.rf_client.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "failed login with admin")

        get_cmd = self.rf_client.build_get_cmd(RedfishClient.REDFISH_URI_ACCOUNTS)
        print(f'get_cmd:{get_cmd}')
        ret, response, error = self.rf_client.exec_curl_cmd(get_cmd)
        # print(f'get accounts {response}')
        accounts = json.loads(response)
        num_of_account = accounts.get("Members@odata.count")
        self.assertEqual(num_of_account, 3, "should exist admin root and yormnAnb accounts")

        self.rf_client.update_credentials(self.bmc_accessor.BMC_ACCOUNT, self.bmc_accessor.BMC_ACCOUNT_DEFAULT_PASSWORD)
        ret = self.rf_client.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "user yormnAnb should exist")

    def test_flow1_factory_old_bmc(self):
        print(f'-- test_flow1_factory_old_bmc')
        self.simulate_factory_of_old_bmc()
        # print(f'boot1 flow with old BMC')
        # Step 4: Run BMCAccessor login flow
        self.rf_client.update_credentials(self.bmc_accessor.BMC_ACCOUNT, self.tpm_pwd)
        ret = self.bmc_accessor.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "login should succeed")

        # Step 5: Verify results
        get_cmd = self.rf_client.build_get_cmd(RedfishClient.REDFISH_URI_ACCOUNTS)
        print(f'get_cmd:{get_cmd}')
        ret, response, error = self.rf_client.exec_curl_cmd(get_cmd)
        # print(f'ret:{ret}')
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "get accounts should succeed")
        # print(f'response:{response}')
        accounts = json.loads(response)
        num_of_account = accounts.get("Members@odata.count")
        self.assertEqual(num_of_account, 3, "should exist only admin root and yormnAnb accounts")

        # Verify yormnAnb user login
        print(f'boot2 flow')
        self.rf_client.update_credentials(self.bmc_accessor.BMC_ACCOUNT, self.tpm_pwd)
        ret = self.bmc_accessor.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "Login as yormnAnb should succeed")

    def test_flow2_factory_new_bmc(self):
        print(f'-- test_flow2_factory_new_bmc')
        self.simulate_factory_of_new_bmc()
        # print(f'boot1 flow with new BMC, bmc_user exists with default pwd')

        # try bmc account with tpm pwd
        self.rf_client.update_credentials(self.bmc_accessor.BMC_ACCOUNT, self.tpm_pwd)
        ret = self.bmc_accessor.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "BMCAccessor login should succeed")

        # Step 5: Verify results
        get_cmd = self.rf_client.build_get_cmd(RedfishClient.REDFISH_URI_ACCOUNTS)
        print(f'get_cmd:{get_cmd}')
        ret, response, error = self.rf_client.exec_curl_cmd(get_cmd)
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, f"Fetching accounts failed: {error}")

        # Verify yormnAnb user login
        print(f'boot2 flow')
        self.rf_client.update_credentials(self.bmc_accessor.BMC_ACCOUNT, self.tpm_pwd)
        ret = self.bmc_accessor.login()
        self.assertEqual(ret, RedfishClient.ERR_CODE_OK, "Login as yormnAnb should succeed")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Run BMC accessor tests.")
    parser.add_argument("bmc_ip", help="The IP address of the BMC.")
    args = parser.parse_args()
    TestBMCAccessorLogin.bmc_ip_arg = args.bmc_ip

    suite = unittest.TestSuite()
    suite.addTests([
        TestBMCAccessorLogin('test_simulate_factory_of_old_bmc'),
        TestBMCAccessorLogin('test_simulate_factory_of_new_bmc'),
        TestBMCAccessorLogin('test_flow1_factory_old_bmc'),
        TestBMCAccessorLogin('test_flow2_factory_new_bmc'),
    ])
    runner = unittest.TextTestRunner()
    runner.run(suite)
    # unittest.main()
