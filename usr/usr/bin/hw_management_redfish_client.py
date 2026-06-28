########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2021-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
import os
import sys
import base64
import fcntl

# TBD:
# Support token persistency later on and remove RedfishClient.__password


'''
cURL wrapper for Redfish client access (curl -K stdin; secrets off argv).
'''


class RedfishClient:

    DEFAULT_GET_TIMEOUT = 3
    _CFG_LOGIN_PREFIX = '# hw-mgmt-redfish: login\n'
    _CURL_HTTP_TRAILER_RE = re.compile(r'\nHTTP Status Code: (\d+)\Z')

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

    @staticmethod
    def __curl_config_escape_double_quoted_value(val):
        '''Escape content for curl -K \"...\" quoted strings (\\ and ").'''
        if val is None:
            return ''
        if not isinstance(val, str):
            val = os.fspath(val)
        return val.replace('\\', '\\\\').replace('"', '\\"')

    def __curl_redfish_url(self, path_without_scheme):
        return f'https://{self.__svr_ip}{path_without_scheme}'

    def __curl_config_auth_header_line(self):
        return (
            'header = "X-Auth-Token: ' +
            self.__curl_config_escape_double_quoted_value(self.__token) + '"'
        )

    '''
    Build curl stdin config for POST /login (credentials in config only, never argv).
    '''

    def __build_login_cmd(self, password, timeout=DEFAULT_GET_TIMEOUT):
        body = json.dumps({'username': self.__user, 'password': password})
        cred_escape = self.__curl_config_escape_double_quoted_value(body)
        login_url_escape = self.__curl_config_escape_double_quoted_value(
            self.__curl_redfish_url('/login'))
        return '\n'.join([
            self._CFG_LOGIN_PREFIX.rstrip('\n'),
            'insecure',
            f'max-time = {timeout}',
            'header = "Content-Type: application/json"',
            'request = POST',
            f'url = "{login_url_escape}"',
            f'data-raw = "{cred_escape}"',
        ])

    '''
    Build curl stdin config for GET (token off argv).
    '''

    def __build_get_cmd(self, uri, timeout=DEFAULT_GET_TIMEOUT):
        full_url_esc = self.__curl_config_escape_double_quoted_value(
            self.__curl_redfish_url(uri))
        return '\n'.join([
            '# hw-mgmt-redfish: GET',
            'insecure',
            f'max-time = {timeout}',
            'location',
            self.__curl_config_auth_header_line(),
            'request = GET',
            f'url = "{full_url_esc}"',
        ])

    '''
    Build curl stdin config for firmware upload POST (token off argv).
    '''

    def __build_fw_update_cmd(self, fw_image):
        url_esc = self.__curl_config_escape_double_quoted_value(
            self.__curl_redfish_url(RedfishClient.REDFISH_URI_UPDATE_SERVICE))
        up_esc = self.__curl_config_escape_double_quoted_value(fw_image)
        return '\n'.join([
            '# hw-mgmt-redfish: fw-post-upload',
            'insecure',
            self.__curl_config_auth_header_line(),
            'header = "Content-Type: application/octet-stream"',
            'request = POST',
            f'upload-file = "{up_esc}"',
            f'url = "{url_esc}"',
        ])

    '''
    Build curl stdin config for PATCH account password (token off argv).
    '''

    def __build_change_password_cmd(self, new_password):
        url_esc = self.__curl_config_escape_double_quoted_value(
            self.__curl_redfish_url(
                f'{RedfishClient.REDFISH_URI_ACCOUNTS}/{self.__user}'))
        body = json.dumps({'Password': new_password})
        data_esc = self.__curl_config_escape_double_quoted_value(body)
        return '\n'.join([
            '# hw-mgmt-redfish: PATCH account-self',
            'insecure',
            self.__curl_config_auth_header_line(),
            'header = "Content-Type: application/json"',
            'request = PATCH',
            f'url = "{url_esc}"',
            f'data-raw = "{data_esc}"',
        ])

    def _build_change_user_password_cmd(self, user, new_password):
        url_esc = self.__curl_config_escape_double_quoted_value(
            self.__curl_redfish_url(
                f'{RedfishClient.REDFISH_URI_ACCOUNTS}/{user}'))
        body = json.dumps({'Password': new_password})
        data_esc = self.__curl_config_escape_double_quoted_value(body)
        return '\n'.join([
            '# hw-mgmt-redfish: PATCH account-user',
            'insecure',
            self.__curl_config_auth_header_line(),
            'header = "Content-Type: application/json"',
            'request = PATCH',
            f'url = "{url_esc}"',
            f'data-raw = "{data_esc}"',
        ])

    def _build_change_user_password_after_factory_cmd(self, user, user_pwd, new_password):
        user_esc = self.__curl_config_escape_double_quoted_value(
            f'{user}:{user_pwd}')
        url_esc = self.__curl_config_escape_double_quoted_value(
            self.__curl_redfish_url(
                f'{RedfishClient.REDFISH_URI_ACCOUNTS}/{user}'))
        body = json.dumps({'Password': new_password})
        data_esc = self.__curl_config_escape_double_quoted_value(body)
        return '\n'.join([
            '# hw-mgmt-redfish: PATCH account-factory',
            'insecure',
            f'user = "{user_esc}"',
            'header = "Content-Type: application/json"',
            'request = PATCH',
            f'url = "{url_esc}"',
            f'data-raw = "{data_esc}"',
        ])

    def _build_delete_cmd(self, user_to_delete):
        url_esc = self.__curl_config_escape_double_quoted_value(
            self.__curl_redfish_url(
                f'{RedfishClient.REDFISH_URI_ACCOUNTS}/{user_to_delete}'))
        return '\n'.join([
            '# hw-mgmt-redfish: DELETE account',
            'insecure',
            self.__curl_config_auth_header_line(),
            'request = DELETE',
            f'url = "{url_esc}"',
        ])

    '''
    Build curl stdin config for PATCH ForceUpdate (token off argv).
    '''

    def __build_set_force_update_cmd(self, force):
        body = json.dumps({'HttpPushUriOptions': {'ForceUpdate': bool(force)}})
        data_esc = self.__curl_config_escape_double_quoted_value(body)
        url_esc = self.__curl_config_escape_double_quoted_value(
            self.__curl_redfish_url(RedfishClient.REDFISH_URI_UPDATE_SERVICE))
        return '\n'.join([
            '# hw-mgmt-redfish: PATCH force-update',
            'insecure',
            self.__curl_config_auth_header_line(),
            'header = "Content-Type: application/json"',
            'request = PATCH',
            f'url = "{url_esc}"',
            f'data-raw = "{data_esc}"',
        ])

    '''
    Build curl stdin config for generic JSON POST (token off argv).
    '''

    def __build_post_cmd(self, uri, data_dict=None, timeout=DEFAULT_GET_TIMEOUT):
        url_esc = self.__curl_config_escape_double_quoted_value(
            self.__curl_redfish_url(uri))
        lines = [
            '# hw-mgmt-redfish: POST json',
            'insecure',
            f'max-time = {timeout}',
            self.__curl_config_auth_header_line(),
            'header = "Content-Type: application/json"',
            'request = POST',
            f'url = "{url_esc}"',
        ]
        if data_dict is not None:
            data_str = json.dumps(data_dict)
            data_esc = self.__curl_config_escape_double_quoted_value(data_str)
            lines.append(f'data-raw = "{data_esc}"')
        return '\n'.join(lines)

    @staticmethod
    def __redact_json_field_in_curl_config(cfg, field_name):
        '''
        Redact JSON field values in curl -K config (plain or backslash-escaped).
        '''
        key = re.escape(field_name)
        escaped_comma = (
            rf'(\\"{key}\\"\s*:\s*\\")((?:\\.[^"\\]|[^"\\])*)(\\")(?=,)'
        )
        escaped_end = (
            rf'(\\"{key}\\"\s*:\s*\\")((?:\\.[^"\\]|[^"\\])*)(\\")(?=}})'
        )
        plain = rf'("{key}"\s*:\s*")((?:\\.[^"\\]|[^"\\])*)(")'
        redacted, count = re.subn(
            escaped_comma, r'\1******\3', cfg, count=1, flags=re.IGNORECASE)
        if count:
            return redacted
        redacted, count = re.subn(
            escaped_end, r'\1******\3', cfg, count=1, flags=re.IGNORECASE)
        if count:
            return redacted
        return re.sub(plain, r'\1******\3', cfg, count=1, flags=re.IGNORECASE)

    '''
    Redact secrets from curl --config stdin for syslog / debug logs.
    '''

    def __curl_config_for_logging(self, curl_config):

        cfg = curl_config

        for field in ('username', 'password', 'Password'):
            cfg = self.__redact_json_field_in_curl_config(cfg, field)

        cfg = re.sub(
            r'header = "X-Auth-Token:[^"]*"',
            'header = "X-Auth-Token: ******"',
            cfg)

        cfg = re.sub(
            r'user = "[^"]*"',
            'user = "******:******"',
            cfg)

        cfg = re.sub(
            r'/AccountService/Accounts/[^"/\s]+',
            '/AccountService/Accounts/******',
            cfg)

        return cfg

    def __format_curl_command_for_logging(self, curl_config):
        '''
        Log argv plus redacted -K stdin config for copy-paste debugging.
        '''
        redacted_cfg = self.__curl_config_for_logging(curl_config)
        return (
            f'{self.__curl_path} -w "\\nHTTP Status Code: %{{http_code}}" -K - '
            f'<<\'HW_MGMT_CURL_CFG\'\n{redacted_cfg}\nHW_MGMT_CURL_CFG'
        )

    '''
    Obfuscate username and password in curl config (delegates to __curl_config_for_logging).
    '''

    def __obfuscate_user_password(self, curl_config):
        return self.__curl_config_for_logging(curl_config)

    '''
    Obfuscate bearer token in a Redfish login response string (logging helpers/tests).
    '''

    def __obfuscate_token_response(self, response):
        pattern = r'"token": "[^"]*"'
        replacement = '"token": "******"'
        return re.sub(pattern, replacement, response)

    '''
    Obfuscate bearer token passed to cURL (stdin config or legacy argv string).
    '''

    def __obfuscate_auth_token(self, cmd):
        obfuscated = self.__curl_config_for_logging(cmd)
        return re.sub(
            r'X-Auth-Token:\s*[^\s"]+',
            'X-Auth-Token: ******',
            obfuscated)

    '''
    Obfuscate password in curl config (delegates to __curl_config_for_logging).
    '''

    def __obfuscate_password(self, cmd):
        return self.__curl_config_for_logging(cmd)

    def __parse_curl_output(self, curl_output):
        '''
        Split curl -w trailer from body. Trailer must be at end of stdout only.
        '''
        match = RedfishClient._CURL_HTTP_TRAILER_RE.search(curl_output)
        if match:
            return (curl_output[:match.start()], match.group(1))
        return (curl_output, None)

    '''
    Execute cURL command and return the output and error messages
    '''

    def __exec_curl_cmd_internal(self, curl_config):

        task_mon = RedfishClient.REDFISH_URI_TASKS in curl_config
        if not task_mon:
            cmd_str = self.__format_curl_command_for_logging(curl_config)
            print(f'Execute cURL command: {cmd_str}', file=sys.stderr)

        curl_argv = [
            self.__curl_path,
            '-w', '\nHTTP Status Code: %{http_code}',
            '-K', '-',
        ]
        process = subprocess.Popen(
            curl_argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        stdin_bytes = curl_config.encode('utf-8')
        output, error = process.communicate(input=stdin_bytes)
        output_decoded = output.decode('utf-8')
        error_str = error.decode('utf-8')
        ret = process.returncode

        if ret > 0:
            ret = RedfishClient.ERR_CODE_CURL_FAILURE

        output_str, _http = self.__parse_curl_output(output_decoded)
        output_str = output_str.rstrip('\n')

        if ret != 0:
            match = re.search(r'curl: \([0-9]+\) (.*)', error_str)
            if match:
                error_str = match.group(1)

        return (ret, output_str, error_str)

    def __update_token_in_curl_config(self, curl_config):
        if self.__token is None:
            return curl_config
        hdr = (
            'header = "X-Auth-Token: ' +
            self.__curl_config_escape_double_quoted_value(self.__token) + '"')
        return re.sub(
            r'^header = "X-Auth-Token:[^"]*"',
            hdr,
            curl_config,
            count=1,
            flags=re.MULTILINE)

    def __get_http_request_type(self, cmd):
        m = re.search(r'^request = (\w+)', cmd, re.MULTILINE | re.I)
        if m:
            return m.group(1).upper()

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

    def exec_curl_cmd(self, curl_config):
        is_login_cmd = curl_config.startswith(RedfishClient._CFG_LOGIN_PREFIX)

        req_type = self.__get_http_request_type(curl_config)
        is_patch_req = (req_type == 'PATCH')

        # Not login, return
        if (not self.has_login()) and (not is_login_cmd):
            return (RedfishClient.ERR_CODE_NOT_LOGIN, 'Not login', 'Not login')

        ret, output_str, error_str = self.__exec_curl_cmd_internal(curl_config)

        is_empty_response = ((ret == 0) and (len(output_str) == 0))

        # cURL will return 0 and empty string in case of invalid token for
        # GET & POST.
        # Need to re-generate token
        if (is_empty_response and (not is_login_cmd) and (not is_patch_req)):
            self.__token = None
            ret = self.login()
            if ret == RedfishClient.ERR_CODE_OK:
                curl_retry = self.__update_token_in_curl_config(curl_config)
                ret, output_str, error_str = self.__exec_curl_cmd_internal(
                    curl_retry)
            elif ret == RedfishClient.ERR_CODE_BAD_CREDENTIAL:
                self.__token = None
                return (ret, 'Bad credential', 'Bad credential')
            else:
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

        curl_cfg = self.__build_login_cmd(password)
        ret, response, error = self.exec_curl_cmd(curl_cfg)

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

    def build_post_cmd(self, uri, data_dict=None):
        return self.__build_post_cmd(uri, data_dict)


'''
BMCAccessor encapsulates BMC details such as IP address, credential management.
It also acts as wrapper of RedfishClient. For each member function
RedfishClient.redfish_api_func(), there will be a wrapper member function
BMCAccessor.func() implicitly defined.
'''


class BMCAccessor(object):
    CURL_PATH = '/usr/bin/curl'
    BMC_ADMIN_ACCOUNT = 'admin'
    BMC_DEFAULT_PASSWORD = '0penBmc'
    BMC_NOS_ACCOUNT = 'yormnAnb'  # used for communication between NOS and BMC
    # default pwd of the NOS/BMC user, during the flow will be changed to tpm_pwd
    BMC_NOS_ACCOUNT_DEFAULT_PASSWORD = "ABYX12#14artb51"
    BMC_DIR = "/host/bmc"
    BMC_PASS_FILE = "bmc_pass"
    BMC_TPM_HEX_FILE = "hw_mgmt_const.bin"
    # Advisory lock for get_login_password() TPM usage (legacy and modern path).
    # Serializes access when called async from multiple processes / permission levels.
    LOCK_DIR = "/run/lock"
    LOCK_FILE = "hw_management_get_login_password.lock"
    FLOCK_TIMEOUT_SEC = 10
    LEGACY_PLATFORM_PATTERN = r'N5\d{3}_LD'

    def __init__(self):
        # TBD: Token persistency.

        self.rf_client = RedfishClient(BMCAccessor.CURL_PATH,
                                       self.get_ip_addr(),
                                       BMCAccessor.BMC_NOS_ACCOUNT,
                                       self.get_login_password())

    def get_ip_addr(self):
        # Return BMC IP address. get usb0 IP address and replace the last
        # byte with '1'.
        # The assumption is that BMC IP address is always X.X.X.1.
        cmd = "/usr/sbin/ip -o -4 addr list usb0 | awk -F ' *|/' '{print $4}'"
        result = subprocess.run(cmd,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE,
                                shell=True,
                                universal_newlines=True)

        addr = "0.0.0.0"
        if result.returncode == 0:
            if len(result.stdout.strip()):
                addr = result.stdout.strip()
                addr = '.'.join(addr.split('.')[:-1] + ['1'])
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

    def _acquire_lock(self, timeout_sec=None):
        """Acquire advisory lock for TPM usage.
        Returns lock_fd (int). Caller must release with _release_lock(lock_fd).
        Waits up to timeout_sec (default: FLOCK_TIMEOUT_SEC).
        """
        if timeout_sec is None:
            timeout_sec = self.FLOCK_TIMEOUT_SEC

        lock_path = os.path.join(self.LOCK_DIR, self.LOCK_FILE)
        deadline = time.clock_gettime(time.CLOCK_MONOTONIC) + timeout_sec
        while True:
            try:
                lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o666)
            except OSError as e:
                raise Exception(f"Cannot create lock file for TPM access: {e}") from e
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return lock_fd
            except BlockingIOError:
                os.close(lock_fd)
                if time.clock_gettime(time.CLOCK_MONOTONIC) >= deadline:
                    raise Exception(
                        f"Cannot acquire TPM lock within {timeout_sec}s (timeout)"
                    )
                time.sleep(0.2)
            except OSError as e:
                os.close(lock_fd)
                raise Exception(f"Cannot acquire TPM lock: {e}") from e

    def _release_lock(self, lock_fd):
        """Release advisory TPM lock and close fd."""
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except OSError:
            pass
        try:
            os.close(lock_fd)
        except OSError:
            pass

    def _handle_legacy_password(self):
        """Handle legacy password generation for juliet platforms (e.g. N5500_LD)"""
        pass_len = 13
        attempt = 1
        max_attempts = 100
        max_repeat = int(3 + 0.09 * pass_len)
        hex_data = "1300NVOS-BMC-USER-Const"

        lock_fd = self._acquire_lock()
        try:
            return self._handle_legacy_password_impl(
                pass_len, attempt, max_attempts, max_repeat, hex_data)
        finally:
            self._release_lock(lock_fd)

    def _handle_legacy_password_impl(self, pass_len, attempt, max_attempts, max_repeat, hex_data):
        """Implementation of legacy password generation (called with lock held)."""
        os.makedirs(self.BMC_DIR, exist_ok=True)
        cmd = f'echo "{hex_data}" | xxd -r -p >  {self.BMC_DIR}/{self.BMC_TPM_HEX_FILE}'
        try:
            subprocess.run(cmd, shell=True, check=True)
        except subprocess.CalledProcessError as e:
            raise Exception(f"Failed to write hex file: {e}")
        tpm_command = ["tpm2_createprimary", "-C", "o", "-u",
                       f"{self.BMC_DIR}/{self.BMC_TPM_HEX_FILE}", "-G", "aes256cfb"]
        try:
            result = subprocess.run(tpm_command, capture_output=True, check=True, text=True)
        except subprocess.CalledProcessError as e:
            raise Exception(f"Failed to create primary with hex file: {e}")

        while attempt <= max_attempts:
            if attempt > 1:
                const = f"1300NVOS-BMC-USER-Const-{attempt}"
                mess = f"Password did not meet criteria; retrying with const: {const}"
                # print(mess)
                tpm_command = f'echo -n "{const}" | tpm2_createprimary -C o -G aes -u -'
                try:
                    result = subprocess.run(tpm_command, shell=True, capture_output=True, check=True, text=True)
                except subprocess.CalledProcessError as e:
                    print(
                        f"[_handle_legacy_password] tpm2_createprimary "
                        f"(stdin, attempt={attempt}) failed: "
                        f"returncode={e.returncode}",
                        file=sys.stderr)
                    if e.stderr:
                        print(f"[_handle_legacy_password] stderr: {e.stderr.strip()}", file=sys.stderr)
                    raise Exception(f"Failed to create primary with stdin: {e}")

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
            repeating_pattern_check = sum(1 for i in range(pass_len - 1)
                                          if symcipher_value[i] == symcipher_value[i + 1]) <= max_repeat

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

    def get_login_password(self):
        try:
            with open('/sys/devices/virtual/dmi/id/product_name') as f:
                platform_name = f.read().strip()
            if re.match(self.LEGACY_PLATFORM_PATTERN, platform_name.upper()):
                try:
                    return self._handle_legacy_password()
                except Exception as e:
                    raise Exception(f"Failed to generate a valid password for legacy platform: {e}")
            else:
                lock_fd = self._acquire_lock()
                try:
                    const = "1300NVOS-BMC-USER-Const"
                    tpm_command = f'echo -n "{const}" | tpm2_createprimary -C o -G aes -u -'
                    result = subprocess.run(tpm_command, shell=True,
                                            capture_output=True, check=True,
                                            text=True).stdout
                    match = re.search(r"symcipher:\s+([\da-fA-F]+)", result)
                    if not match:
                        raise Exception("Symmetric cipher not found in TPM output")
                    # Extract symcipher and encode to base64
                    return base64.b64encode(bytes.fromhex(match.group(1))).decode("ascii")
                finally:
                    self._release_lock(lock_fd)
        # Lock is always released by inner finally before we get here.
        except subprocess.CalledProcessError as e:
            raise Exception(f"Failed to communicate with TPM: {e}")
        except (FileNotFoundError, PermissionError) as e:
            raise Exception(f"No platform name found: {e}")
        except Exception as e:
            raise Exception(f"Failed to generate a valid password: {e}")

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
