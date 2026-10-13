#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Unit tests for PWM 100% fallback after mlxsw_minimal chipup failure.
################################################################################

import os
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPERS = ROOT / "usr" / "usr" / "bin" / "hw-management-helpers.sh"
HW_MGMT_SH = ROOT / "usr" / "usr" / "bin" / "hw-management.sh"

TC_ASIC_PWM = '{"asic_config": {"1": {"pwm_control": true}}}'
TC_ASIC_PWM_OFF = '{"asic_config": {"1": {"pwm_control": false}}}'


def _write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def _run_pwm_fail_helper(
    tmp_path,
    tc_config=None,
    pwm1=None,
    asic_index="1",
    explicit_dev=None,
    asic_num=None,
    pci_bus_ids=None,
    mst_map=None,
):
    config_dir = tmp_path / "config"
    thermal_dir = tmp_path / "thermal"
    bin_dir = tmp_path / "bin"
    mst_sysfs = tmp_path / "sys_class_mst"
    mst_devdir = tmp_path / "dev_mst"
    config_dir.mkdir(exist_ok=True)
    thermal_dir.mkdir(exist_ok=True)
    bin_dir.mkdir(exist_ok=True)
    mst_sysfs.mkdir(exist_ok=True)
    mst_devdir.mkdir(exist_ok=True)

    if tc_config is not None:
        (config_dir / "tc_config.json").write_text(tc_config)
    if asic_num is not None:
        (config_dir / "asic_num").write_text("{}\n".format(asic_num))
    if pci_bus_ids:
        for idx, bdf in pci_bus_ids.items():
            (config_dir / "asic{}_pci_bus_id".format(idx)).write_text("{}\n".format(bdf))
    if pwm1 is not None:
        (thermal_dir / "pwm1").write_text(str(pwm1))

    if mst_map:
        pci_root = tmp_path / "pci_devs"
        pci_root.mkdir(exist_ok=True)
        for name, bdf in mst_map.items():
            pci_dev = pci_root / bdf
            pci_dev.mkdir(exist_ok=True)
            node = mst_sysfs / name
            node.mkdir()
            (node / "device").symlink_to(pci_dev)
            (mst_devdir / name).write_text("")

    mlxreg_log = tmp_path / "mlxreg.args"
    _write_exec(
        bin_dir / "mlxreg",
        "#!/bin/sh\n"
        "printf '%s\\n' \"$*\" > \"{log}\"\n"
        "exit 0\n".format(log=mlxreg_log),
    )

    if explicit_dev is None and mst_map is None and not pci_bus_ids:
        explicit_dev = tmp_path / "fake_pciconf0"
        explicit_dev.write_text("")

    env = os.environ.copy()
    env["PATH"] = "{}:{}".format(bin_dir, env.get("PATH", ""))
    env["HW_MGMT_MST_SYSFS"] = str(mst_sysfs)
    env["HW_MGMT_MST_DEVDIR"] = str(mst_devdir)

    explicit_arg = '"{}"'.format(explicit_dev) if explicit_dev is not None else '""'
    script = """
source "{helpers}"
log_info() {{ :; }}
log_err() {{ :; }}
config_path="{config}"
thermal_path="{thermal}"
export HW_MGMT_MST_SYSFS="{mst_sysfs}"
export HW_MGMT_MST_DEVDIR="{mst_devdir}"
set_asic_pwm_full_speed_on_chipup_fail "{asic_index}" {explicit_arg}
echo RC:$?
""".format(
        helpers=HELPERS,
        config=config_dir,
        thermal=thermal_dir,
        mst_sysfs=mst_sysfs,
        mst_devdir=mst_devdir,
        asic_index=asic_index,
        explicit_arg=explicit_arg,
    )

    result = subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
        timeout=10,
        env=env,
        cwd=str(tmp_path),
    )
    return result, mlxreg_log, thermal_dir / "pwm1"


def test_chipup_fail_path_passes_failed_asic_index():
    text = HW_MGMT_SH.read_text()
    chipup_case = text[text.index("\tchipup)"): text.index("\tchipdown)")]
    fail_idx = chipup_case.index('log_info "chipup failed for ASIC $asic_index"')
    success_exit = chipup_case.index("exit 0")
    assert success_exit < fail_idx
    assert 'set_asic_pwm_full_speed_on_chipup_fail "$asic_index" "$3"' in chipup_case[fail_idx:]
    assert "set_asic_pwm_full_speed_on_chipup_fail" not in chipup_case[:fail_idx]
    helpers = HELPERS.read_text()
    assert "get_asic_mlxreg_dev()" in helpers
    assert "_hw_mgmt_normalize_asic_index()" in helpers
    assert "asic${asic_index}_pci_bus_id" in helpers
    assert "head -n 1" in helpers
    # First-pciconf0 fallback is gated to a single ASIC.
    assert '[ "$asic_num" -eq 1 ]' in helpers
    assert "pwm_duty_cycle=0xff" in helpers


def test_sysfs_pwm_used_when_pwm1_exists(tmp_path):
    result, mlxreg_log, pwm1 = _run_pwm_fail_helper(
        tmp_path,
        tc_config=TC_ASIC_PWM,
        pwm1="128",
    )
    assert result.returncode == 0
    assert "RC:0" in result.stdout
    assert pwm1.read_text().strip() == "255"
    assert not mlxreg_log.exists()


def test_mlxreg_used_when_asic_pwm_and_no_pwm1(tmp_path):
    result, mlxreg_log, pwm1 = _run_pwm_fail_helper(
        tmp_path,
        tc_config=TC_ASIC_PWM,
    )
    assert result.returncode == 0
    assert "RC:0" in result.stdout
    assert not pwm1.exists()
    args = mlxreg_log.read_text()
    assert "--reg_name MFSC" in args
    assert "pwm_duty_cycle=0xff" in args
    assert "--indexes pwm=0x0" in args


def test_no_mlxreg_when_pwm_control_disabled(tmp_path):
    result, mlxreg_log, _pwm1 = _run_pwm_fail_helper(
        tmp_path,
        tc_config=TC_ASIC_PWM_OFF,
    )
    assert result.returncode == 0
    assert "RC:1" in result.stdout
    assert not mlxreg_log.exists()


def test_mlxreg_targets_failed_asic_on_multi_asic(tmp_path):
    """Chipup of ASIC 2 must program that ASIC's mst node, not the first pciconf0."""
    result, mlxreg_log, _pwm1 = _run_pwm_fail_helper(
        tmp_path,
        tc_config=TC_ASIC_PWM,
        asic_index="2",
        explicit_dev=None,
        asic_num=2,
        pci_bus_ids={1: "03:00.0", 2: "05:00.0"},
        mst_map={
            "mt_asic1_pciconf0": "0000:03:00.0",
            "mt_asic2_pciconf0": "0000:05:00.0",
        },
    )
    assert result.returncode == 0, result.stderr
    assert "RC:0" in result.stdout
    args = mlxreg_log.read_text()
    assert "mt_asic2_pciconf0" in args
    assert "mt_asic1_pciconf0" not in args


def test_mlxreg_uses_pci_bdf_when_mst_sysfs_missing(tmp_path):
    result, mlxreg_log, _pwm1 = _run_pwm_fail_helper(
        tmp_path,
        tc_config=TC_ASIC_PWM,
        asic_index="2",
        explicit_dev=None,
        asic_num=2,
        pci_bus_ids={1: "03:00.0", 2: "05:00.0"},
    )
    assert result.returncode == 0, result.stderr
    assert "RC:0" in result.stdout
    args = mlxreg_log.read_text()
    assert "-d 05:00.0" in args
    assert "03:00.0" not in args


def test_multi_asic_without_pci_id_does_not_pick_first_pciconf(tmp_path):
    result, mlxreg_log, _pwm1 = _run_pwm_fail_helper(
        tmp_path,
        tc_config=TC_ASIC_PWM,
        asic_index="2",
        explicit_dev=None,
        asic_num=2,
        mst_map={"mt_asic1_pciconf0": "0000:03:00.0"},
    )
    assert result.returncode == 0
    assert "RC:1" in result.stdout
    assert not mlxreg_log.exists()


def test_index_zero_uses_asic1_pci_id(tmp_path):
    """sxcore calls chipup 0; config files are asic1_pci_bus_id."""
    result, mlxreg_log, _pwm1 = _run_pwm_fail_helper(
        tmp_path,
        tc_config=TC_ASIC_PWM,
        asic_index="0",
        explicit_dev=None,
        asic_num=1,
        pci_bus_ids={1: "03:00.0"},
        mst_map={"mt_asic1_pciconf0": "0000:03:00.0"},
    )
    assert result.returncode == 0, result.stderr
    assert "RC:0" in result.stdout
    args = mlxreg_log.read_text()
    assert "mt_asic1_pciconf0" in args


def test_sxcore_pci_path_with_index_zero_selects_matching_asic(tmp_path):
    """chipup 0 /sys/.../0000:05:00.0 must program that ASIC, not asic1."""
    pci_path = tmp_path / "sys" / "devices" / "0000:05:00.0"
    pci_path.mkdir(parents=True)
    result, mlxreg_log, _pwm1 = _run_pwm_fail_helper(
        tmp_path,
        tc_config=TC_ASIC_PWM,
        asic_index="0",
        explicit_dev=pci_path,
        asic_num=2,
        pci_bus_ids={1: "03:00.0", 2: "05:00.0"},
        mst_map={
            "mt_asic1_pciconf0": "0000:03:00.0",
            "mt_asic2_pciconf0": "0000:05:00.0",
        },
    )
    assert result.returncode == 0, result.stderr
    assert "RC:0" in result.stdout
    args = mlxreg_log.read_text()
    assert "mt_asic2_pciconf0" in args
    assert "mt_asic1_pciconf0" not in args
