# Copyright (c) 2019-2024 NVIDIA CORPORATION & AFFILIATES.
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#############################################################################
# Nvidia
#
# Module contains an implementation of RedFish client which provides
# firmware upgrade and sensor retrieval functionality
#
#############################################################################

import subprocess
import json
import time
import re
import shlex
import os

# TBD:
# Support token persistency later on and remove RedfishClient.__password


'''
cURL wrapper for Redfish client access
'''


class RedfishClient:

    DEFAULT_GET_TIMEOUT = 3

    # Redfish URIs
    REDFISH_URI_FW_INVENTORY = '/redfish/v1/UpdateService/FirmwareInventory'
    REDFISH_URI_TASKS = '/redfish/v1/TaskService/Tasks'
    REDFISH_URI_UPDATE_SERVICE = '/redfish/v1/UpdateService'
    REDFISH_URI_ACCOUNTS = '/redfish/v1/AccountService/Accounts'

    # Error code definitions
    ERR_CODE_OK = 0
    ERR_CODE_BAD_CREDENTIAL = -1
    ERR_CODE_INVALID_JSON_FORMAT = -2
    ERR_CODE_UNEXPECTED_RESPONSE = -3
    ERR_CODE_CURL_FAILURE = -4
    ERR_CODE_NOT_LOGIN = -5
    ERR_CODE_TIMEOUT = -6
    ERR_CODE_IDENTICAL_IMAGE = -7
    ERR_CODE_GENERIC_ERROR = -8

    '''
    Constructor
    '''
    def __init__(self, curl_path, ip_addr, user, password):
        self.__curl_path = curl_path
        self.__svr_ip = ip_addr
        self.__user = user
        self.__password = password
        self.__token = None

    def get_token(self):
        return self.__token

    def update_credentials(self, user, password=None):
        self.__user = user
        self.__token = None
        self.__password = password

    '''
    Build the POST command to get bearer token
    '''
    def __build_login_cmd(self, password, timeout=DEFAULT_GET_TIMEOUT):
        cmd = f'{self.__curl_path} -m {timeout} -k ' \
            f'-H "Content-Type: application/json" ' \
            f'-X POST https://{self.__svr_ip}/login ' \
            f'-d \'{{"username" : "{self.__user}", "password" : "{password}"}}\''
        return cmd

    '''
    Build the GET command
    '''
    def __build_get_cmd(self, uri, timeout=DEFAULT_GET_TIMEOUT):
        cmd = f'{self.__curl_path} -m {timeout} -k ' \
            f'-H "X-Auth-Token: {self.__token}" --request GET ' \
            f'--location https://{self.__svr_ip}{uri}'
        return cmd

    '''
    Build the POST command to do firmware update
    '''
    def __build_fw_update_cmd(self, fw_image):
        cmd = f'{self.__curl_path} -k -H "X-Auth-Token: {self.__token}" ' \
            f'-H "Content-Type: application/octet-stream" -X POST ' \
            f'https://{self.__svr_ip}' \
            f'{RedfishClient.REDFISH_URI_UPDATE_SERVICE} -T {fw_image}'
        return cmd

    '''
    Build the PATCH command to change login password
    '''
    def __build_change_password_cmd(self, new_password):
        cmd = f'{self.__curl_path} -k -H "X-Auth-Token: {self.__token}" ' \
            f'-H "Content-Type: application/json" -X PATCH ' \
            f'https://{self.__svr_ip}' \
            f'{RedfishClient.REDFISH_URI_ACCOUNTS}/{self.__user} ' \
            f'-d \'{{"Password" : "{new_password}"}}\''
        return cmd

    def _build_change_user_password_cmd(self, user, new_password):
        cmd = f'{self.__curl_path} -k -H "X-Auth-Token: {self.__token}" ' \
            f'-H "Content-Type: application/json" -X PATCH ' \
            f'https://{self.__svr_ip}' \
            f'{RedfishClient.REDFISH_URI_ACCOUNTS}/{user} ' \
            f'-d \'{{"Password" : "{new_password}"}}\''  # Change password for the specific user
        return cmd

    def _build_change_user_password_after_factory_cmd(self, user, user_pwd, new_password):
        cmd = f'{self.__curl_path} -k -u {user}:{user_pwd} ' \
            f'-H "Content-Type: application/json" -X PATCH ' \
            f'https://{self.__svr_ip}' \
            f'{RedfishClient.REDFISH_URI_ACCOUNTS}/{user} ' \
            f'-d \'{{"Password" : "{new_password}"}}\''  # Change password for the specific user
        return cmd

    def _build_delete_cmd(self, user_to_delete):
        # curl -k -H "X-Auth-Token: $bmc_token" -X DELETE https://${bmc}/redfish/v1/AccountService/Accounts/admin_user
        cmd = f'{self.__curl_path} -k -H "X-Auth-Token: {self.__token}" ' \
            f'-X DELETE ' \
            f'https://{self.__svr_ip}' \
            f'{RedfishClient.REDFISH_URI_ACCOUNTS}/{user_to_delete} '
        return cmd

    '''
    Build the PATCH command to set 'ForceUpdate' attribute
    '''
    def __build_set_force_update_cmd(self, force):
        value = 'true' if force else 'false'
        cmd = f'{self.__curl_path} -k -H "X-Auth-Token: {self.__token}" ' \
            f'-X PATCH -d \'{{"HttpPushUriOptions":{{"ForceUpdate":{value}}}}}\' ' \
            f'https://{self.__svr_ip}' \
            f'{RedfishClient.REDFISH_URI_UPDATE_SERVICE}'
        return cmd

    '''
    Build generic POST command
    '''
    def __build_post_cmd(self, uri, data_dict, timeout=DEFAULT_GET_TIMEOUT):
        data_str = json.dumps(data_dict)
        cmd = f'{self.__curl_path} -m {timeout} -k -H "X-Auth-Token: {self.__token}" ' \
            f'-H "Content-Type: application/json" ' \
            f'-X POST https://{self.__svr_ip}{uri} ' \
            f'-d \'{data_str}\''
        return cmd

    '''
    Obfuscate username and password while asking for bearer token
    '''
    def __obfuscate_user_password(self, cmd):
        pattern = r'"username" : "[^"]*", "password" : "[^"]*"'
        replacement = '"username" : "******", "password" : "******"'
        obfuscation_cmd = re.sub(pattern, replacement, cmd)
        return obfuscation_cmd

    '''
    Obfuscate bearer token in the response string
    '''
    def __obfuscate_token_response(self, response):
        # Credential obfuscation
        pattern = r'"token": "[^"]*"'
        replacement = '"token": "******"'
        obfuscation_response = re.sub(pattern,
                                      replacement,
                                      response)
        return obfuscation_response

    '''
    Obfuscate bearer token passed to cURL
    '''
    def __obfuscate_auth_token(self, cmd):
        pattern = r'X-Auth-Token: [^"]+'
        replacement = 'X-Auth-Token: ******'

        obfuscation_cmd = re.sub(pattern, replacement, cmd)
        return obfuscation_cmd

    '''
    Obfuscate password while aksing for password change
    '''
    def __obfuscate_password(self, cmd):
        pattern = r'"Password" : "[^"]*"'
        replacement = '"Password" : "******"'
        obfuscation_cmd = re.sub(pattern, replacement, cmd)

        return obfuscation_cmd

    '''
    Execute cURL command and return the output and error messages
    '''
    def __exec_curl_cmd_internal(self, cmd):

        # Will not print task monitor to syslog
        task_mon = (RedfishClient.REDFISH_URI_TASKS in cmd)
        login_cmd = ('/login ' in cmd)
        password_change = (RedfishClient.REDFISH_URI_ACCOUNTS in cmd)

        # Credential obfuscation
        if login_cmd:
            obfuscation_cmd = self.__obfuscate_user_password(cmd)
        else:
            obfuscation_cmd = self.__obfuscate_auth_token(cmd)

        if password_change:
            obfuscation_cmd = self.__obfuscate_password(obfuscation_cmd)

        process = subprocess.Popen(shlex.split(cmd),
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        output, error = process.communicate()
        output_str = output.decode('utf-8')
        error_str = error.decode('utf-8')
        ret = process.returncode
        # print ("Curl send:{}\n".format(cmd))
        # print ("Curl rcv: err:{}\nout:{}".format(error_str, output_str))

        if (ret > 0):
            ret = RedfishClient.ERR_CODE_CURL_FAILURE

        if (ret == 0):  # cURL retuns ok
            if login_cmd:
                obfuscation_output_str = \
                    self.__obfuscate_token_response(output_str)
            else:
                obfuscation_output_str = output_str

        else:  # cURL returns error
            # Extract cURL command failure reason
            match = re.search(r'curl: \([0-9]+\) (.*)', error_str)
            if match:
                error_str = match.group(1)

        return (ret, output_str, error_str)

    def __get_http_request_type(self, cmd):

        patterns = (r'-X[ \t]+([A-Z]+)', r'--request[ \t]+([A-Z]+)')

        for pattern in patterns:
            match = re.search(pattern, cmd)
            if match:
                return match.group(1)

        return None

    '''
    Wrapper function to execute the given cURL command which can deal with
    invalid bearer token case.
    '''
    def exec_curl_cmd(self, cmd):
        is_login_cmd = ('/login ' in cmd)

        req_type = self.__get_http_request_type(cmd)
        is_patch_req = (req_type == 'PATCH')

        # Not login, return
        if (not self.has_login()) and (not is_login_cmd):
            return (RedfishClient.ERR_CODE_NOT_LOGIN, 'Not login', 'Not login')

        ret, output_str, error_str = self.__exec_curl_cmd_internal(cmd)

        is_empty_response = ((ret == 0) and (len(output_str) == 0))

        # cURL will return 0 and empty string in case of invalid token for
        # GET & POST.
        # Need to re-generate token
        if (is_empty_response and (not is_login_cmd) and (not is_patch_req)):
            # print(f'need to regenerate token..')
            self.__token = None
            ret = self.login()
            if ret == RedfishClient.ERR_CODE_OK:
                ret, output_str, error_str = self.__exec_curl_cmd_internal(cmd)
            elif ret == RedfishClient.ERR_CODE_BAD_CREDENTIAL:
                # Login fails, invalidate token.
                self.__token = None
                return (ret, 'Bad credential', 'Bad credential')
            else:
                # Login fails, invalidate token.
                self.__token = None
                return (ret, 'Login failure', 'Login failure')

        return (ret, output_str, error_str)

    '''
    Check if already login
    '''
    def has_login(self):
        return self.__token is not None

    '''
    Login Redfish server and get bearer token
    '''
    def login(self, password=None):
        if self.has_login():
            return RedfishClient.ERR_CODE_OK

        if not password:
            password = self.__password

        cmd = self.__build_login_cmd(password)
        # print(f'cmd:{cmd}')
        ret, response, error = self.exec_curl_cmd(cmd)

        if (ret != 0):  # cURL execution error
            ret = RedfishClient.ERR_CODE_CURL_FAILURE
        else:
            # Note that 'curl' returns 0 and empty response
            # in case of invalid user/password
            if len(response) == 0:
                msg = 'Incorrect username or password\n'
                ret = RedfishClient.ERR_CODE_BAD_CREDENTIAL
            else:
                try:
                    json_response = json.loads(response)
                    if 'error' in json_response:
                        msg = json_response['error']['message']
                        ret = RedfishClient.ERR_CODE_GENERIC_ERROR
                    elif 'token' in json_response:
                        token = json_response['token']
                        if token is not None:
                            ret = RedfishClient.ERR_CODE_OK
                            self.__token = token
                            self.__password = password
                        else:
                            msg = 'Empty "token" field found\n'
                            ret = RedfishClient.ERR_CODE_UNEXPECTED_RESPONSE
                    else:
                        msg = 'No "token" field found\n'
                        ret = RedfishClient.ERR_CODE_UNEXPECTED_RESPONSE
                except Exception as e:
                    msg = 'Invalid json format\n'
                    ret = RedfishClient.ERR_CODE_INVALID_JSON_FORMAT

        return ret

    def build_get_cmd(self, uri):
        return self.__build_get_cmd(uri)

    def build_post_cmd(self, uri, data_dict):
        return self.__build_post_cmd(uri, data_dict)


'''
BMCAccessor encapsulates BMC details such as IP address, credential management.
It also acts as wrapper of RedfishClient. For each memmber function
RedfishClient.redfish_api_func(), there will be a wrapper member function
BMCAccessor.func() implicitly defined.
'''


class BMCAccessor(object):
    CURL_PATH = '/usr/bin/curl'
    BMC_INTERNAL_IP_ADDR = '10.0.1.1'
    BMC_ADMIN_ACCOUNT = 'admin'
    BMC_DEFAULT_PASSWORD = '0penBmc'
    BMC_NOS_ACCOUNT = 'yormnAnb'  # used for communication between NOS and BMC
    BMC_NOS_ACCOUNT_DEFAULT_PASSWORD = "ABYX12#14artb51"  # default pwd of the NOS/BMC user, during the flow will be changed to tpm_pwd
    BMC_DIR = "/host/bmc"
    BMC_PASS_FILE = "bmc_pass"
    BMC_TPM_HEX_FILE = "hw_mgmt_const.bin"

    def __init__(self):
        # TBD: Token persistency.

        self.rf_client = RedfishClient(BMCAccessor.CURL_PATH,
                                       self.get_ip_addr(),
                                       BMCAccessor.BMC_NOS_ACCOUNT,
                                       self.get_login_password())

    def get_ip_addr(self):
        redis_cmd = '/usr/bin/sonic-db-cli ' \
                    'CONFIG_DB hget "DEVICE_METADATA|localhost" bmc_addr'
        result = subprocess.run(redis_cmd,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE,
                                shell=True,
                                universal_newlines=True)

        addr = self.BMC_INTERNAL_IP_ADDR
        if result.returncode == 0:
            if len(result.stdout.strip()):
                addr = result.stdout.strip()
        return addr

    def __getattr__(self, name):
        fname = f'redfish_api_{name}'

        if hasattr(self.rf_client, fname):
            api_func = getattr(self.rf_client, fname)
            if callable(api_func):
                def redfish_api_wrapper(*args, **kwargs):
                    ret, data = api_func(*args, **kwargs)
                    if ret == RedfishClient.ERR_CODE_BAD_CREDENTIAL:
                        # Trigger credential restore flow
                        restored = self.restore_tpm_credential()
                        if restored:
                            # Execute again
                            ret, data = api_func(*args, **kwargs)
                        else:
                            return (RedfishClient.ERR_CODE_BAD_CREDENTIAL, data)
                    return (ret, data)

                return redfish_api_wrapper

        err_msg = f"'{self.__class__.__name__}' object has no attribute '{name}'"
        raise AttributeError(err_msg)

    def get_login_password(self):
        try:
            pass_len = 13
            attempt = 1
            max_attempts = 100
            max_repeat = int(3 + 0.09 * pass_len)
            hex_data = "1300NVOS-BMC-USER-Const"
            os.makedirs(self.BMC_DIR, exist_ok=True)
            cmd = f'echo "{hex_data}" | xxd -r -p >  {self.BMC_DIR}/{self.BMC_TPM_HEX_FILE}'
            subprocess.run(cmd, shell=True, check=True)

            tpm_command = ["tpm2_createprimary", "-C", "o", "-u", f"{self.BMC_DIR}/{self.BMC_TPM_HEX_FILE}", "-G", "aes256cfb"]
            result = subprocess.run(tpm_command, capture_output=True, check=True, text=True)

            while attempt <= max_attempts:
                if attempt > 1:
                    const = f"1300NVOS-BMC-USER-Const-{attempt}"
                    mess = f"Password did not meet criteria; retrying with const: {const}"
                    # print(mess)
                    tpm_command = f'echo -n "{const}" | tpm2_createprimary -C o -G aes -u -'
                    result = subprocess.run(tpm_command, shell=True, capture_output=True, check=True, text=True)

                symcipher_pattern = r"symcipher:\s+([\da-fA-F]+)"
                symcipher_match = re.search(symcipher_pattern, result.stdout)

                if not symcipher_match:
                    raise Exception("Symmetric cipher not found in TPM output")

                # BMC dictates a password of 13 characters. Random from TPM is used with an append of A!
                symcipher_part = symcipher_match.group(1)[:pass_len - 2]
                if symcipher_part.isdigit():
                    symcipher_value = symcipher_part[:pass_len - 3] + 'vA!'
                elif symcipher_part.isalpha() and symcipher_part.islower():
                    symcipher_value = symcipher_part[:pass_len - 3] + '9A!'
                else:
                    symcipher_value = symcipher_part + 'A!'
                if len(symcipher_value) != pass_len:
                    raise Exception("Bad cipher length from TPM output")

                # check for monotonic
                monotonic_check = True
                for i in range(len(symcipher_value) - 3):
                    seq = symcipher_value[i:i + 4]
                    increments = [ord(seq[j + 1]) - ord(seq[j]) for j in range(3)]
                    if increments == [1, 1, 1] or increments == [-1, -1, -1]:
                        monotonic_check = False
                        break

                variety_check = len(set(symcipher_value)) >= 5
                repeating_pattern_check = sum(1 for i in range(pass_len - 1) if symcipher_value[i] == symcipher_value[i + 1]) <= max_repeat

                # check for consecutive_pairs
                count = 0
                for i in range(11):
                    val1 = symcipher_value[i]
                    val2 = symcipher_value[i + 1]
                    if val2 == "v" or val1 == "v":
                        continue
                    if abs(int(val2, 16) - int(val1, 16)) == 1:
                        count += 1
                consecutive_pair_check = count <= 4

                if consecutive_pair_check and variety_check and repeating_pattern_check and monotonic_check:
                    os.remove(f"{self.BMC_DIR}/{self.BMC_TPM_HEX_FILE}")
                    return symcipher_value
                else:
                    attempt += 1

            raise Exception("Failed to generate a valid password after maximum retries.")

        except subprocess.CalledProcessError as e:
            # print(f"Error executing TPM command: {e}")
            raise Exception("Failed to communicate with TPM")

        except Exception as e:
            # print(f"Error: {e}")
            raise

    def create_user(self, user, password):
        cmd = self.rf_client.build_post_cmd(RedfishClient.REDFISH_URI_ACCOUNTS, {
            "UserName": user,
            "Password": password,
            "RoleId": "Administrator"
        })

        # print(f'cmd:{cmd}')
        ret, output, error = self.rf_client.exec_curl_cmd(cmd)
        return ret

    def reset_user_password(self, user, password):
        if not self.rf_client.has_login():
            return RedfishClient.ERR_CODE_NOT_LOGIN

        cmd = self.rf_client._build_change_user_password_cmd(user, password)
        # print(f'cmd:{cmd}')
        ret, output_str, error_str = self.rf_client.exec_curl_cmd(cmd)
        return ret

    def try_rf_login(self, user, password):
        self.rf_client.update_credentials(user, password)
        ret = self.rf_client.login()
        return ret

    def login(self, password=None):
        print("Login to BMC")
        cp = []
        try:
            cp.append("A")  # try with BMC_NOS_ACCOUNT and TPM password")
            ret = self.try_rf_login(BMCAccessor.BMC_NOS_ACCOUNT, self.get_login_password())
            if ret == RedfishClient.ERR_CODE_OK:
                cp.append("Z1")
                return ret

            cp.append("B")  # try with BMC_NOS_ACCOUNT and bmc account default password")
            ret = self.try_rf_login(BMCAccessor.BMC_NOS_ACCOUNT, BMCAccessor.BMC_NOS_ACCOUNT_DEFAULT_PASSWORD)
            if ret == RedfishClient.ERR_CODE_OK:
                cp.append("Z2")
                ret = self.reset_user_password(BMCAccessor.BMC_NOS_ACCOUNT, self.get_login_password())
                if ret == RedfishClient.ERR_CODE_OK:
                    cp.append("Z2")
                else:
                    cp.append("Z'1")
                return ret

            cp.append("C")  # login as admin and tpm pwd")
            ret = self.try_rf_login(BMCAccessor.BMC_ADMIN_ACCOUNT, self.get_login_password())
            if ret != RedfishClient.ERR_CODE_OK:
                cp.append("C1")  # login as admin and default pwd")
                ret = self.try_rf_login(BMCAccessor.BMC_ADMIN_ACCOUNT, BMCAccessor.BMC_DEFAULT_PASSWORD)
                if ret != RedfishClient.ERR_CODE_OK:
                    cp.append("Z'2")
                    return ret

            cp.append("D")  # add BMC_NOS_ACCOUNT with tpm pwd")
            self.rf_client.update_credentials(BMCAccessor.BMC_ADMIN_ACCOUNT, BMCAccessor.BMC_DEFAULT_PASSWORD)
            ret = self.rf_client.login()

            ret = self.create_user(BMCAccessor.BMC_NOS_ACCOUNT, self.get_login_password())
            if ret == RedfishClient.ERR_CODE_OK:
                ret = self.try_rf_login(BMCAccessor.BMC_NOS_ACCOUNT, self.get_login_password())
                if ret == RedfishClient.ERR_CODE_OK:
                    cp.append("Z3")
                    return ret
                else:
                    cp.append("Z'3")
                    return ret
            else:
                cp.append("Z'4")
                return ret
        finally:
            if any("'" in item for item in cp):
                print(f"-- BMC Login Fail, Flow: {'->'.join(cp)}")
            else:
                print(f"-- BMC Login Pass, Flow: {'->'.join(cp)}")
