#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only or BSD-3-Clause
#
# Unit tests for ASIC PWM via mlxreg: chipup-fail fallback, chipdown
# set_asic_pwm_speed_safe(), and sxcore remove ordering.

import os
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPERS = ROOT / "usr" / "usr" / "bin" / "hw-management-helpers.sh"
HW_MGMT_SH = ROOT / "usr" / "usr" / "bin" / "hw-management.sh"
THERMAL_EVENTS = ROOT / "usr" / "usr" / "bin" / "hw-management-thermal-events.sh"

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
    pwm=None,
    cooling_name=None,
    mlxreg_rc=0,
    call=None,
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
    if cooling_name is not None:
        (config_dir / "cooling_name").write_text("{}\n".format(cooling_name))

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
        "exit {rc}\n".format(log=mlxreg_log, rc=int(mlxreg_rc)),
    )

    if (
        explicit_dev is None and
        mst_map is None and
        not pci_bus_ids and
        call != "set_asic_pwm_speed_safe"
    ):
        explicit_dev = tmp_path / "fake_pciconf0"
        explicit_dev.write_text("")

    env = os.environ.copy()
    env["PATH"] = "{}:{}".format(bin_dir, env.get("PATH", ""))
    env["HW_MGMT_MST_SYSFS"] = str(mst_sysfs)
    env["HW_MGMT_MST_DEVDIR"] = str(mst_devdir)

    explicit_arg = '"{}"'.format(explicit_dev) if explicit_dev is not None else '""'
    if call == "set_asic_pwm_speed_safe":
        helper_call = 'set_asic_pwm_speed_safe "{}" "{}"'.format(
            asic_index, "255" if pwm is None else pwm
        )
    elif pwm is None:
        helper_call = 'set_asic_pwm_full_speed_on_chipup_fail "{}" {}'.format(
            asic_index, explicit_arg
        )
    else:
        helper_call = 'write_pwm_mlxreg "{}" "{}" {}'.format(
            asic_index, pwm, explicit_arg
        )
    script = """
source "{helpers}"
log_info() {{ :; }}
log_err() {{ :; }}
config_path="{config}"
thermal_path="{thermal}"
export HW_MGMT_MST_SYSFS="{mst_sysfs}"
export HW_MGMT_MST_DEVDIR="{mst_devdir}"
{helper_call}
echo RC:$?
""".format(
        helpers=HELPERS,
        config=config_dir,
        thermal=thermal_dir,
        mst_sysfs=mst_sysfs,
        mst_devdir=mst_devdir,
        helper_call=helper_call,
    )

    result = subprocess.run(
        ["bash", "-c", script],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
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
    assert "write_pwm_mlxreg()" in helpers
    assert "set_asic_pwm_speed_safe()" in helpers
    assert "is_spc1_system()" not in helpers
    assert "is_spc1_warm_reboot()" not in helpers
    speed_safe = helpers[helpers.index("set_asic_pwm_speed_safe()"):]
    speed_safe = speed_safe[: speed_safe.index("set_asic_pwm_full_speed_on_chipup_fail()")]
    assert '[ "$cooling_name" == "mlxsw" ]' in speed_safe
    assert "PWM sysfs is missing; ASIC PWM control is not configured." in speed_safe
    assert 'write_pwm_mlxreg "$1" 0xff "$explicit_dev"' in helpers
    assert "if is_spc1_warm_reboot; then" not in chipup_case[fail_idx:]
    assert "_hw_mgmt_normalize_asic_index()" in helpers
    assert "asic${asic_index}_pci_bus_id" in helpers
    assert "head -n 1" in helpers
    # First-pciconf0 fallback is gated to a single ASIC.
    assert '[ "$asic_num" -eq 1 ]' in helpers
    assert 'pwm_duty_cycle="$pwm_hex"' in helpers
    write_pwm = helpers[helpers.index("write_pwm_mlxreg()"):]
    write_pwm = write_pwm[: write_pwm.index("set_asic_pwm_speed_safe()")]
    assert "\tyes |" not in write_pwm
    assert "printf 'y\\ny\\ny\\n' |" in write_pwm


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


def test_write_pwm_mlxreg_decimal_duty_cycle(tmp_path):
    result, mlxreg_log, pwm1 = _run_pwm_fail_helper(
        tmp_path,
        pwm="128",
    )
    assert result.returncode == 0, result.stderr
    assert "RC:0" in result.stdout
    assert not pwm1.exists()
    args = mlxreg_log.read_text()
    assert "--reg_name MFSC" in args
    assert "--indexes pwm=0x0" in args
    assert "pwm_duty_cycle=0x80" in args


def test_write_pwm_mlxreg_hex_duty_cycle(tmp_path):
    result, mlxreg_log, _pwm1 = _run_pwm_fail_helper(
        tmp_path,
        pwm="0xff",
    )
    assert result.returncode == 0, result.stderr
    assert "RC:0" in result.stdout
    args = mlxreg_log.read_text()
    assert "pwm_duty_cycle=0xff" in args


def test_write_pwm_mlxreg_rejects_out_of_range(tmp_path):
    result, mlxreg_log, _pwm1 = _run_pwm_fail_helper(
        tmp_path,
        pwm="256",
    )
    assert result.returncode == 0
    assert "RC:1" in result.stdout
    assert not mlxreg_log.exists()


def test_write_pwm_mlxreg_rejects_invalid_value(tmp_path):
    result, mlxreg_log, _pwm1 = _run_pwm_fail_helper(
        tmp_path,
        pwm="abc",
    )
    assert result.returncode == 0
    assert "RC:1" in result.stdout
    assert not mlxreg_log.exists()


def _asic_pwm_env():
    return dict(
        call="set_asic_pwm_speed_safe",
        cooling_name="mlxsw",
        asic_index="1",
        explicit_dev=None,
        asic_num=1,
        pci_bus_ids={1: "03:00.0"},
        mst_map={"mt_asic1_pciconf0": "0000:03:00.0"},
    )


def test_chipdown_calls_set_asic_pwm_speed_safe():
    """do_chip_up_down action 0 must use mlxreg helper, not sysfs pwm1."""
    text = HW_MGMT_SH.read_text()
    down = text[text.index("do_chip_up_down()"):]
    action0 = down[down.index("case $action in"): down.index("\t1)")]
    assert 'set_asic_pwm_speed_safe "$asic_index" 255' in action0
    assert "echo  255 > $pwm_link" not in action0
    assert "Set PWM to maximum speed prior fan driver removing." not in action0


def test_sxcore_remove_sets_asic_ready_before_chipdown():
    text = THERMAL_EVENTS.read_text()
    block = text[text.rindex('if [ "$2" == "sxcore" ]; then'):]
    block = block[: block.index("if [ \"$2\" == \"dpu\" ]; then")]
    ready_idx = block.index('set_asic_ready "$4/$5" 0')
    chipdown_idx = block.index('/usr/bin/hw-management.sh chipdown 0 "$4/$5"')
    assert ready_idx < chipdown_idx


def test_set_asic_pwm_speed_safe_mlxsw_uses_mlxreg(tmp_path):
    result, mlxreg_log, pwm1 = _run_pwm_fail_helper(
        tmp_path,
        pwm="255",
        **_asic_pwm_env()
    )
    assert result.returncode == 0, result.stderr
    assert "RC:0" in result.stdout
    assert not pwm1.exists()
    args = mlxreg_log.read_text()
    assert "--reg_name MFSC" in args
    assert "--indexes pwm=0x0" in args
    assert "pwm_duty_cycle=0xff" in args
    assert "mt_asic1_pciconf0" in args


def test_set_asic_pwm_speed_safe_skips_cpld(tmp_path):
    result, mlxreg_log, pwm1 = _run_pwm_fail_helper(
        tmp_path,
        call="set_asic_pwm_speed_safe",
        cooling_name="mlxreg_fan",
        pwm="255",
        pwm1="128",
        asic_num=1,
        pci_bus_ids={1: "03:00.0"},
        mst_map={"mt_asic1_pciconf0": "0000:03:00.0"},
        explicit_dev=None,
    )
    assert result.returncode == 0, result.stderr
    assert "RC:0" in result.stdout
    assert pwm1.read_text().strip() == "128"
    assert not mlxreg_log.exists()


def test_set_asic_pwm_speed_safe_skips_missing_cooling_name(tmp_path):
    result, mlxreg_log, pwm1 = _run_pwm_fail_helper(
        tmp_path,
        call="set_asic_pwm_speed_safe",
        pwm="255",
        pwm1="128",
        asic_num=1,
        pci_bus_ids={1: "03:00.0"},
        mst_map={"mt_asic1_pciconf0": "0000:03:00.0"},
        explicit_dev=None,
    )
    assert result.returncode == 0, result.stderr
    assert "RC:0" in result.stdout
    assert pwm1.read_text().strip() == "128"
    assert not mlxreg_log.exists()


def test_set_asic_pwm_speed_safe_sysfs_fallback_when_mlxreg_fails(tmp_path):
    result, mlxreg_log, pwm1 = _run_pwm_fail_helper(
        tmp_path,
        pwm="255",
        pwm1="128",
        mlxreg_rc=1,
        **_asic_pwm_env()
    )
    assert result.returncode == 0, result.stderr
    assert "RC:0" in result.stdout
    assert mlxreg_log.exists()
    assert pwm1.read_text().strip() == "255"


def test_set_asic_pwm_speed_safe_mlxreg_fail_without_pwm1(tmp_path):
    result, mlxreg_log, pwm1 = _run_pwm_fail_helper(
        tmp_path,
        pwm="255",
        mlxreg_rc=1,
        **_asic_pwm_env()
    )
    assert result.returncode == 0, result.stderr
    assert "RC:1" in result.stdout
    assert mlxreg_log.exists()
    assert not pwm1.exists()
