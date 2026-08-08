#!/usr/bin/python
# pylint: disable=line-too-long
# pylint: disable=C0103
########################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
"""
ASIC FAN PWM / tacho publisher over PCIe (mlxreg).

Replaces mlxsw_minimal I2C hwmon access for PWM and tachometers by reading /
writing ASIC registers via mlxreg:

  MFCR - PWM/tacho capability (mlxsw_hwmon_fans_init)
  MFSC - PWM duty cycle     (mlxsw_hwmon_pwm_show / pwm_store)
  MFSM - FAN RPM            (mlxsw_hwmon_fan_rpm_show)
  FORE - FAN fault          (mlxsw_hwmon_fan_fault_show)

Published under /var/run/hw-management/thermal/ (not I2C hwmon links):

  pwm1              - regular file (PWM duty 0..255)
  fan{N}_speed_set  - symlink to pwm1 (same as thermal-events)
  fan{N}_speed_get  - regular file (RPM)
  fan{N}_fault      - regular file (0/1)

fan_inversed from config/ is applied the same way as
hw-management-thermal-events.sh (ASIC/hwmon index -> logical fan number).
"""

from __future__ import print_function

import argparse
import logging
import os
import signal
import subprocess
import sys
import time


VERSION = "1.0.0"

HW_MGMT_PATH = "/var/run/hw-management"
THERMAL_PATH = os.path.join(HW_MGMT_PATH, "thermal")
CONFIG_PATH = os.path.join(HW_MGMT_PATH, "config")

POLL_INTERVAL_SEC = 5
MLXREG_TIMEOUT_SEC = 3.0
PWM_INDEX_DEFAULT = 0
PWM_MAX = 255

# Same default as FAN_MAP_DEF in hw-management-thermal-events.sh
FAN_MAP_DEF = list(range(1, 21))


class CONST(object):
    LOG_FILE = "/var/log/hw_management_pwm_control.log"


def setup_logger(verbosity, log_file):
    logger = logging.getLogger("hw_management_pwm_control")
    logger.setLevel(verbosity)
    logger.handlers = []
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    logger.addHandler(sh)
    if log_file:
        try:
            fh = logging.FileHandler(log_file)
            fh.setFormatter(fmt)
            logger.addHandler(fh)
        except OSError:
            pass
    return logger


class MlxregError(Exception):
    """Raised when an mlxreg transaction fails."""


class MlxregClient(object):
    """
    Thin wrapper around the mlxreg CLI.

    Register access mirrors mlxsw/core_hwmon.c:
      MFCR / MFSC / MFSM / FORE
    """

    def __init__(self, device, logger, timeout=MLXREG_TIMEOUT_SEC):
        self.device = device
        self.log = logger
        self.timeout = timeout

    @staticmethod
    def _terminate_proc(proc, timeout=1.0):
        if not proc:
            return
        try:
            proc.terminate()
            proc.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, OSError, ProcessLookupError):
            try:
                proc.kill()
                proc.wait(timeout=timeout)
            except (OSError, ProcessLookupError, subprocess.TimeoutExpired):
                pass

    def _parse_fields(self, stdout):
        """
        Parse mlxreg table output into {field_name: int_value}.
        Expected lines: 'field_name | 0x....'
        """
        fields = {}
        if not stdout:
            return fields
        for line in stdout.decode("utf-8", errors="replace").splitlines():
            if "|" not in line:
                continue
            name, _, data = line.partition("|")
            name = name.strip().lower()
            data = data.strip()
            if not name or name.startswith("field name") or set(name) <= set("="):
                continue
            try:
                fields[name] = int(data, 0)
            except ValueError:
                continue
        return fields

    def get(self, reg_name, indexes=None):
        cmd = ["mlxreg", "-d", self.device, "--reg_name", reg_name, "--get"]
        if indexes:
            cmd.extend(["--indexes", indexes])
        proc = None
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            stdout, stderr = proc.communicate(timeout=self.timeout)
            if proc.returncode not in (0, None) and not stdout:
                raise MlxregError("mlxreg get {} failed: {}".format(
                    reg_name, stderr.decode("utf-8", errors="replace").strip()))
            return self._parse_fields(stdout)
        except (OSError, subprocess.SubprocessError, subprocess.TimeoutExpired) as exc:
            raise MlxregError("mlxreg get {} error: {}".format(reg_name, exc))
        finally:
            self._terminate_proc(proc)

    def set(self, reg_name, indexes, set_expr):
        """
        Write register. Uses `yes` on stdin to auto-confirm mlxreg prompt,
        same pattern as hw_management_thermal_control.write_pwm_mlxreg().
        """
        cmd = ["mlxreg", "-d", self.device, "--reg_name", reg_name,
               "--indexes", indexes, "--set", set_expr]
        yes_proc = None
        mlxreg_proc = None
        try:
            yes_proc = subprocess.Popen(["yes"], stdout=subprocess.PIPE)
            mlxreg_proc = subprocess.Popen(
                cmd,
                stdin=yes_proc.stdout,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            yes_proc.stdout.close()
            stdout, stderr = mlxreg_proc.communicate(timeout=self.timeout)
            if mlxreg_proc.returncode not in (0, None):
                raise MlxregError("mlxreg set {} failed: {}".format(
                    reg_name, stderr.decode("utf-8", errors="replace").strip()))
            return self._parse_fields(stdout)
        except (OSError, subprocess.SubprocessError, subprocess.TimeoutExpired) as exc:
            raise MlxregError("mlxreg set {} error: {}".format(reg_name, exc))
        finally:
            self._terminate_proc(yes_proc)
            self._terminate_proc(mlxreg_proc)


class PwmControl(object):
    """
    FAN PWM/tacho control and publisher.

    a) fans_init()     - MFCR capability probe
    b) fan_rpm_get()   - MFSM
       fan_pwm_get()   - MFSC
       fan_pwm_set()   - MFSC
       fan_fault_get() - FORE
    c) poll loop       - publish to hw-management thermal tree
    """

    def __init__(self, mlxreg, logger, thermal_path=THERMAL_PATH, config_path=CONFIG_PATH,
                 poll_interval=POLL_INTERVAL_SEC):
        self.mlxreg = mlxreg
        self.log = logger
        self.thermal_path = thermal_path
        self.config_path = config_path
        self.poll_interval = poll_interval
        self.exit = False

        self.pwm_index = PWM_INDEX_DEFAULT
        self.pwm_active_mask = 0
        self.tacho_active_mask = 0
        # ASIC/hwmon tacho indexes that are present (type_index used by MFSM/FORE)
        self.tacho_indexes = []
        # Map ASIC/hwmon index (1-based position among active, like fanN_input)
        # to logical fan number used in thermal/fan{N}_*
        self.fan_map = list(FAN_MAP_DEF)
        self.last_pwm_written = None

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _read_config_file(self, name, default=None):
        path = os.path.join(self.config_path, name)
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read().strip()
        except OSError:
            return default

    def _load_fan_map(self):
        raw = self._read_config_file("fan_inversed")
        if not raw:
            self.fan_map = list(FAN_MAP_DEF)
            return
        try:
            self.fan_map = [int(x) for x in raw.split()]
        except ValueError:
            self.log.warning("Invalid fan_inversed '%s', using identity map", raw)
            self.fan_map = list(FAN_MAP_DEF)
        self.log.info("fan_inversed map: %s", self.fan_map)

    def _logical_fan(self, hwmon_idx):
        """
        Map 1-based hwmon/ASIC sequential fan index to logical fan number.
        Same rule as thermal-events.sh:
          j=${fan_map[i-1]}; link fan$i_input -> fan$j_speed_get
        """
        if hwmon_idx < 1 or hwmon_idx > len(self.fan_map):
            return hwmon_idx
        return self.fan_map[hwmon_idx - 1]

    def _ensure_regular_file(self, path, initial="0"):
        """Replace symlink (or missing node) with a regular file."""
        if os.path.islink(path) or os.path.exists(path):
            try:
                if os.path.islink(path) or not os.path.isfile(path):
                    os.unlink(path)
                elif os.path.isfile(path):
                    return
            except OSError as exc:
                self.log.warning("Cannot replace %s: %s", path, exc)
                return
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write("{}\n".format(initial))
        except OSError as exc:
            self.log.warning("Cannot create %s: %s", path, exc)

    def _ensure_symlink(self, link_path, target):
        """
        Ensure link_path is a symlink to target (relative name preferred).
        Replaces an existing file or wrong symlink.
        """
        try:
            if os.path.islink(link_path):
                if os.readlink(link_path) == target:
                    return
                os.unlink(link_path)
            elif os.path.exists(link_path):
                os.unlink(link_path)
            os.symlink(target, link_path)
        except OSError as exc:
            self.log.warning("Cannot link %s -> %s: %s", link_path, target, exc)

    def _write_file(self, path, value):
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write("{}\n".format(value))
            return True
        except OSError as exc:
            self.log.warning("Write %s failed: %s", path, exc)
            return False

    def _read_int_file(self, path, default=None):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return int(f.read().strip())
        except (OSError, ValueError):
            return default

    @staticmethod
    def _bits_set(mask, max_bits=16):
        return [i for i in range(max_bits) if mask & (1 << i)]

    # ------------------------------------------------------------------
    # a) MFCR init - mlxsw_hwmon_fans_init()
    # ------------------------------------------------------------------
    def fans_init(self):
        """
        Probe PWM/tacho capability via MFCR.

        Equivalent of mlxsw_hwmon_fans_init():
          - pwm_active bitmask  -> which PWM indexes exist
          - tacho_active bitmask -> which tacho indexes exist

        On Spectrum1 (Panther) typical values:
          pwm_active=0x1, tacho_active=0x1fe (tachos 1..8)
        """
        fields = self.mlxreg.get("MFCR")
        pwm_active = fields.get("pwm_active", 0)
        tacho_lo = fields.get("tacho_active", 0)
        tacho_hi = fields.get("tacho_active_msb", 0)
        # 10-bit low + 6-bit high, as exposed by mlxreg on SPC1
        tacho_active = (tacho_lo & 0x3FF) | ((tacho_hi & 0x3F) << 10)

        self.pwm_active_mask = pwm_active
        self.tacho_active_mask = tacho_active
        self.tacho_indexes = self._bits_set(tacho_active)

        pwm_indexes = self._bits_set(pwm_active)
        if pwm_indexes:
            self.pwm_index = pwm_indexes[0]
        else:
            self.pwm_index = PWM_INDEX_DEFAULT
            self.log.warning("MFCR pwm_active=0, assuming pwm index %d", self.pwm_index)

        if not self.tacho_indexes:
            # Fallback for platforms where MFCR read is incomplete
            self.tacho_indexes = list(range(1, 9))
            self.log.warning("MFCR tacho_active=0, assuming tachos 1..8")

        self.log.info(
            "MFCR: pwm_active=0x%x tacho_active=0x%x -> pwm=%d tachos=%s",
            self.pwm_active_mask, self.tacho_active_mask,
            self.pwm_index, self.tacho_indexes,
        )
        return True

    # ------------------------------------------------------------------
    # b) Register accessors
    # ------------------------------------------------------------------
    def fan_rpm_get(self, tacho_index):
        """
        Read FAN RPM via MFSM.
        Equivalent of mlxsw_hwmon_fan_rpm_show().
        @param tacho_index: ASIC tacho index (as in MFCR bitmask / MFSM index)
        @return: rpm (int) or None on error
        """
        try:
            fields = self.mlxreg.get("MFSM", indexes="tacho={}".format(tacho_index))
            return fields.get("rpm")
        except MlxregError as exc:
            self.log.warning("fan_rpm_get(%s) failed: %s", tacho_index, exc)
            return None

    def fan_pwm_get(self, pwm_index=None):
        """
        Read PWM duty cycle via MFSC (0..255).
        Equivalent of mlxsw_hwmon_pwm_show().
        """
        if pwm_index is None:
            pwm_index = self.pwm_index
        try:
            fields = self.mlxreg.get("MFSC", indexes="pwm={}".format(pwm_index))
            # Prefer pwm_duty_cycle; do not match bare 'pwm' index field.
            if "pwm_duty_cycle" in fields:
                return fields["pwm_duty_cycle"]
            return None
        except MlxregError as exc:
            self.log.warning("fan_pwm_get(%s) failed: %s", pwm_index, exc)
            return None

    def fan_pwm_set(self, duty, pwm_index=None):
        """
        Write PWM duty cycle via MFSC (0..255).
        Equivalent of mlxsw_hwmon_pwm_store().
        Used by thermal control when PWM must be updated.
        """
        if pwm_index is None:
            pwm_index = self.pwm_index
        try:
            duty = int(duty)
        except (TypeError, ValueError):
            return False
        if duty < 0 or duty > PWM_MAX:
            self.log.warning("fan_pwm_set: duty %s out of range 0..%d", duty, PWM_MAX)
            return False
        try:
            self.mlxreg.set(
                "MFSC",
                indexes="pwm={}".format(pwm_index),
                set_expr="pwm_duty_cycle={}".format(hex(duty)),
            )
            self.last_pwm_written = duty
            self.log.info("fan_pwm_set: pwm=%d duty=0x%x (%d)", pwm_index, duty, duty)
            return True
        except MlxregError as exc:
            self.log.warning("fan_pwm_set(%s) failed: %s", duty, exc)
            return False

    def fan_fault_get(self, tacho_index):
        """
        Read FAN fault via FORE.
        Equivalent of mlxsw_hwmon_fan_fault_show():
          fault = under_limit bit OR over_limit bit for the tacho index.
        @return: 0/1 or None on error
        """
        try:
            fields = self.mlxreg.get("FORE")
            under = fields.get("fan_under_limit", 0)
            under_hi = fields.get("fan_under_limit_msb", 0)
            over = fields.get("fan_over_limit", 0)
            over_hi = fields.get("fan_over_limit_msb", 0)
            under_mask = (under & 0x3FF) | ((under_hi & 0x3F) << 10)
            over_mask = (over & 0x3FF) | ((over_hi & 0x3F) << 10)
            bit = 1 << tacho_index
            return 1 if (under_mask | over_mask) & bit else 0
        except MlxregError as exc:
            self.log.warning("fan_fault_get(%s) failed: %s", tacho_index, exc)
            return None

    # ------------------------------------------------------------------
    # Thermal tree publish
    # ------------------------------------------------------------------
    def prepare_thermal_files(self):
        """
        Create thermal nodes without mlxsw_minimal I2C hwmon:
          pwm1, fan*_speed_get, fan*_fault as regular files;
          fan*_speed_set as symlink to pwm1 (same as thermal-events).
        """
        os.makedirs(self.thermal_path, exist_ok=True)
        os.makedirs(self.config_path, exist_ok=True)

        self._ensure_regular_file(os.path.join(self.thermal_path, "pwm1"), "255")

        # Sequential hwmon numbering 1..N for active tachos (same as mlxsw)
        for hwmon_idx, _asic_idx in enumerate(self.tacho_indexes, start=1):
            logical = self._logical_fan(hwmon_idx)
            self._ensure_regular_file(
                os.path.join(self.thermal_path, "fan{}_speed_get".format(logical)), "0")
            self._ensure_regular_file(
                os.path.join(self.thermal_path, "fan{}_fault".format(logical)), "0")
            # Same alias as thermal-events: fan*_speed_set -> pwm1
            self._ensure_symlink(
                os.path.join(self.thermal_path, "fan{}_speed_set".format(logical)),
                "pwm1")

        self._write_file(os.path.join(self.config_path, "max_tachos"),
                         len(self.tacho_indexes))
        self.log.info("Prepared thermal files for %d tachos", len(self.tacho_indexes))

    def _apply_pwm_from_thermal(self):
        """
        If TC (or user) wrote a new value to thermal/pwm1 (or via a
        fan*_speed_set symlink), push it to MFSC. Scale is 0..255.
        """
        pwm_path = os.path.join(self.thermal_path, "pwm1")
        duty = self._read_int_file(pwm_path)
        if duty is None:
            return
        if self.last_pwm_written is not None and duty == self.last_pwm_written:
            return
        self.fan_pwm_set(duty)

    def publish_once(self):
        """One poll iteration: apply pending PWM, then refresh RPM/fault/PWM."""
        self._apply_pwm_from_thermal()

        # Publish PWM readback to pwm1; fan*_speed_set follows via symlink
        duty = self.fan_pwm_get()
        if duty is not None:
            self._write_file(os.path.join(self.thermal_path, "pwm1"), duty)
            self.last_pwm_written = duty

        # Publish RPM + fault per tacho
        for hwmon_idx, asic_idx in enumerate(self.tacho_indexes, start=1):
            logical = self._logical_fan(hwmon_idx)
            rpm = self.fan_rpm_get(asic_idx)
            if rpm is not None:
                self._write_file(
                    os.path.join(self.thermal_path, "fan{}_speed_get".format(logical)),
                    rpm)
            fault = self.fan_fault_get(asic_idx)
            if fault is not None:
                self._write_file(
                    os.path.join(self.thermal_path, "fan{}_fault".format(logical)),
                    fault)

    # ------------------------------------------------------------------
    # c) Main loop
    # ------------------------------------------------------------------
    def request_exit(self, *_args):
        self.log.info("Exit requested")
        self.exit = True

    def run(self):
        self._load_fan_map()
        self.fans_init()
        self.prepare_thermal_files()

        # Seed last_pwm from ASIC so we do not immediately rewrite default
        duty = self.fan_pwm_get()
        if duty is not None:
            self.last_pwm_written = duty
            self._write_file(os.path.join(self.thermal_path, "pwm1"), duty)

        self.log.info("Entering poll loop (interval=%ss)", self.poll_interval)
        while not self.exit:
            try:
                self.publish_once()
            except Exception as exc:  # pylint: disable=broad-except
                self.log.error("poll error: %s", exc)
            # Sleep in small steps so SIGTERM is handled promptly
            for _ in range(int(self.poll_interval * 10)):
                if self.exit:
                    break
                time.sleep(0.1)
        self.log.info("Stopped")


def find_mst_device():
    """Locate /dev/mst/*_pciconf0, same heuristic as thermal_control."""
    try:
        result = subprocess.run(
            ["find", "/dev/mst", "-name", "*pciconf0"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        for line in result.stdout.splitlines():
            line = line.strip()
            if line and os.path.exists(line):
                return line
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def main():
    parser = argparse.ArgumentParser(description="HW Management PWM control (mlxreg/PCIe)")
    parser.add_argument("--version", action="version", version="%(prog)s ver:{}".format(VERSION))
    parser.add_argument("-d", "--device", dest="device",
                        help="MST device path (default: auto-detect /dev/mst/*pciconf0)")
    parser.add_argument("-i", "--interval", dest="interval", type=int,
                        default=POLL_INTERVAL_SEC, help="Poll interval seconds")
    parser.add_argument("-l", "--log_file", dest="log_file", default=CONST.LOG_FILE)
    parser.add_argument("-v", "--verbosity", dest="verbosity", type=int, default=logging.INFO)
    parser.add_argument("--once", action="store_true",
                        help="Run a single publish cycle and exit (debug)")
    args = parser.parse_args()

    logger = setup_logger(args.verbosity, args.log_file)

    device = args.device or find_mst_device()
    if not device:
        logger.error("No MST pciconf device found under /dev/mst")
        return 1
    if not os.path.exists(device):
        logger.error("MST device does not exist: %s", device)
        return 1
    logger.info("Using MST device %s", device)

    client = MlxregClient(device, logger)
    ctrl = PwmControl(client, logger, poll_interval=args.interval)

    signal.signal(signal.SIGTERM, ctrl.request_exit)
    signal.signal(signal.SIGINT, ctrl.request_exit)

    if args.once:
        ctrl._load_fan_map()
        ctrl.fans_init()
        ctrl.prepare_thermal_files()
        ctrl.publish_once()
        return 0

    ctrl.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
