#!/usr/bin/env python3
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Unit tests for chipup I2C trace lifecycle and SPC1 PWM fallback.
################################################################################

import os
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPERS = ROOT / "usr" / "usr" / "bin" / "hw-management-helpers.sh"
HW_MGMT_SH = ROOT / "usr" / "usr" / "bin" / "hw-management.sh"


def _write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def _make_tracefs(root):
    events = root / "events" / "i2c"
    events.mkdir(parents=True)
    (events / "enable").write_text("0\n")
    (events / "filter").write_text("")
    (root / "trace").write_text("")
    (root / "buffer_size_kb").write_text("0\n")
    (root / "instances").mkdir()
    return root


def _run_bash(script, tmp_path, timeout=10, extra_env=None):
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    result = subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
        cwd=str(tmp_path),
    )
    return result


def _spc1_paths(tmp_path, board="VMOD0001", product="MSN2700", reset_attrs=None):
    board_file = tmp_path / "board_name"
    pn_file = tmp_path / "product_name"
    system_dir = tmp_path / "system"
    hwmon_root = tmp_path / "mlxreg_hwmon"
    vendor_file = tmp_path / "chassis_vendor"
    config_dir = tmp_path / "config"
    board_file.write_text("{}\n".format(board))
    pn_file.write_text("{}\n".format(product))
    vendor_file.write_text("Other\n")
    system_dir.mkdir(exist_ok=True)
    hwmon_root.mkdir(exist_ok=True)
    config_dir.mkdir(exist_ok=True)
    if reset_attrs:
        for name, value in reset_attrs.items():
            (system_dir / name).write_text("{}\n".format(value))
    return board_file, pn_file, system_dir, hwmon_root, vendor_file, config_dir


def _helpers_preamble(tmp_path, board="VMOD0001", product="MSN2700", reset_attrs=None):
    board_file, pn_file, system_dir, hwmon_root, vendor_file, config_dir = _spc1_paths(
        tmp_path, board=board, product=product, reset_attrs=reset_attrs
    )
    return """
source "{helpers}"
log_info() {{ :; }}
log_err() {{ :; }}
board_type_file="{board}"
pn_file="{pn}"
system_path="{system}"
config_path="{config}"
export HW_MGMT_MLXREG_IO_HWMON="{hwmon}"
export HW_MGMT_CHASSIS_VENDOR_FILE="{vendor}"
""".format(
        helpers=HELPERS,
        board=board_file,
        pn=pn_file,
        system=system_dir,
        config=config_dir,
        hwmon=hwmon_root,
        vendor=vendor_file,
    )


def _run_pwm_fail_helper(
    tmp_path,
    asic_index="1",
    explicit_dev=None,
    asic_num=None,
    pci_bus_ids=None,
    mst_map=None,
    board="VMOD0001",
    product="MSN2700",
    reset_attrs=None,
):
    if reset_attrs is None:
        reset_attrs = {"reset_from_comex": "1"}

    preamble = _helpers_preamble(
        tmp_path, board=board, product=product, reset_attrs=reset_attrs
    )
    config_dir = tmp_path / "config"
    thermal_dir = tmp_path / "thermal"
    bin_dir = tmp_path / "bin"
    mst_sysfs = tmp_path / "sys_class_mst"
    mst_devdir = tmp_path / "dev_mst"
    thermal_dir.mkdir(exist_ok=True)
    bin_dir.mkdir(exist_ok=True)
    mst_sysfs.mkdir(exist_ok=True)
    mst_devdir.mkdir(exist_ok=True)

    if asic_num is not None:
        (config_dir / "asic_num").write_text("{}\n".format(asic_num))
    if pci_bus_ids:
        for idx, bdf in pci_bus_ids.items():
            (config_dir / "asic{}_pci_bus_id".format(idx)).write_text("{}\n".format(bdf))

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
    script = preamble + """
export HW_MGMT_MST_SYSFS="{mst_sysfs}"
export HW_MGMT_MST_DEVDIR="{mst_devdir}"
set_asic_pwm_full_speed_on_chipup_fail "{asic_index}" {explicit_arg}
echo RC:$?
""".format(
        mst_sysfs=mst_sysfs,
        mst_devdir=mst_devdir,
        asic_index=asic_index,
        explicit_arg=explicit_arg,
    )

    result = _run_bash(script, tmp_path, extra_env=env)
    return result, mlxreg_log


def test_chipup_dis_returns_so_caller_can_stop_trace():
    text = HW_MGMT_SH.read_text()
    fn = text[text.index("do_chip_up_down()"): text.index("do_chip_down()")]
    disable_idx = fn.index('"$disable" -gt 0')
    disable_block = fn[disable_idx: fn.index("chipup_delay=", disable_idx)]
    assert "return 0" in disable_block
    assert not any(line.strip() == "exit 0" for line in disable_block.splitlines())


def test_chipup_case_installs_trace_exit_cleanup():
    text = HW_MGMT_SH.read_text()
    chipup_case = text[text.index("\tchipup)"): text.index("\tchipdown)")]
    assert "trap 'stop_chipup_i2c_trace' EXIT" in chipup_case
    assert "rotate_chipup_i2c_trace_log" in chipup_case
    assert 'start_chipup_i2c_trace "$asic_index"' in chipup_case
    assert chipup_case.index("trap 'stop_chipup_i2c_trace' EXIT") < \
        chipup_case.index('start_chipup_i2c_trace "$asic_index"')
    assert chipup_case.count("stop_chipup_i2c_trace") >= 3
    assert 'set_asic_pwm_full_speed_on_chipup_fail "$asic_index" "$3"' in chipup_case


def test_lock_trap_stops_chipup_trace():
    helpers = HELPERS.read_text()
    lock = helpers[helpers.index("lock_service_state_change()"):
                   helpers.index("unlock_service_state_change()")]
    assert "stop_chipup_i2c_trace" in lock


def test_trace_instance_name_includes_pid():
    helpers = HELPERS.read_text()
    assert "hwmgmt_chipup_${asic_index}_${BASHPID}" in helpers
    assert 'CHIPUP_TRACE_DIR="$KERN_TRACE_FS"' not in helpers


def test_skip_tracing_does_not_clobber_top_level_ftrace(tmp_path):
    """No dedicated instance (no events/i2c under it): leave top-level alone."""
    tracefs = _make_tracefs(tmp_path / "tracefs")
    (tracefs / "events" / "i2c" / "enable").write_text("0\n")
    (tracefs / "events" / "i2c" / "filter").write_text("adapter_nr==9\n")
    (tracefs / "buffer_size_kb").write_text("42\n")
    (tracefs / "trace").write_text("KEEPME\n")
    script = """
source "{helpers}"
KERN_TRACE_FS="{tracefs}"
start_chipup_i2c_trace 0
echo DIR:$CHIPUP_TRACE_DIR
echo ENABLE:$(cat "$KERN_TRACE_FS/events/i2c/enable")
echo FILTER:$(cat "$KERN_TRACE_FS/events/i2c/filter")
echo BUF:$(cat "$KERN_TRACE_FS/buffer_size_kb")
echo TRACE:$(cat "$KERN_TRACE_FS/trace")
""".format(helpers=HELPERS, tracefs=tracefs)
    result = _run_bash(script, tmp_path)
    assert result.returncode == 0, result.stderr
    assert "DIR:" in result.stdout
    assert result.stdout.split("DIR:")[1].splitlines()[0] == ""
    assert "ENABLE:0" in result.stdout
    assert "FILTER:adapter_nr==9" in result.stdout
    assert "BUF:42" in result.stdout
    assert "TRACE:KEEPME" in result.stdout
    leftover = list((tracefs / "instances").glob("hwmgmt_chipup_*"))
    assert leftover == []


def test_exit_while_locked_disables_and_removes_trace(tmp_path):
    tracefs = _make_tracefs(tmp_path / "tracefs")
    lockfile = tmp_path / "chassis.lock"
    script = """
source "{helpers}"
log_info() {{ :; }}
KERN_TRACE_FS="{tracefs}"
LOCKFILE="{lockfile}"
pid=$BASHPID
inst="$KERN_TRACE_FS/instances/hwmgmt_chipup_0_$pid"
mkdir -p "$inst/events/i2c"
echo 0 > "$inst/events/i2c/enable"
echo 0 > "$inst/events/i2c/filter"
: > "$inst/trace"
: > "$inst/buffer_size_kb"
start_chipup_i2c_trace 0
echo DIR:$CHIPUP_TRACE_DIR
echo ENABLE_BEFORE:$(cat "$inst/events/i2c/enable")
lock_service_state_change
exit 0
""".format(helpers=HELPERS, tracefs=tracefs, lockfile=lockfile)
    result = _run_bash(script, tmp_path)
    assert result.returncode == 0, result.stderr
    # Instance path is printed before exit; enable must be cleared by EXIT trap.
    enable_files = list(tracefs.glob("instances/hwmgmt_chipup_0_*/events/i2c/enable"))
    assert enable_files, result.stdout
    assert enable_files[0].read_text().strip() == "0"
    assert "ENABLE_BEFORE:1" in result.stdout


def test_stop_is_idempotent_and_clears_enable(tmp_path):
    tracefs = _make_tracefs(tmp_path / "tracefs")
    script = """
source "{helpers}"
KERN_TRACE_FS="{tracefs}"
pid=$BASHPID
inst="$KERN_TRACE_FS/instances/hwmgmt_chipup_0_$pid"
mkdir -p "$inst/events/i2c"
echo 0 > "$inst/events/i2c/enable"
: > "$inst/events/i2c/filter"
: > "$inst/trace"
: > "$inst/buffer_size_kb"
start_chipup_i2c_trace 0
echo ENABLE1:$(cat "$inst/events/i2c/enable")
stop_chipup_i2c_trace
echo ENABLE2:$(cat "$inst/events/i2c/enable")
stop_chipup_i2c_trace
echo EMPTY:$CHIPUP_TRACE_DIR
echo RC:$?
""".format(helpers=HELPERS, tracefs=tracefs)
    result = _run_bash(script, tmp_path)
    assert result.returncode == 0, result.stderr
    assert "ENABLE1:1" in result.stdout
    assert "ENABLE2:0" in result.stdout
    empty_line = result.stdout.split("EMPTY:")[1].splitlines()[0]
    assert empty_line == ""
    assert "RC:0" in result.stdout


def test_concurrent_chipup_uses_distinct_instances(tmp_path):
    tracefs = _make_tracefs(tmp_path / "tracefs")
    out1 = tmp_path / "p1.inst"
    out2 = tmp_path / "p2.inst"
    script = """
source "{helpers}"
start_one() {{
    local out="$1"
    KERN_TRACE_FS="{tracefs}"
    pid=$BASHPID
    inst="$KERN_TRACE_FS/instances/hwmgmt_chipup_0_$pid"
    mkdir -p "$inst/events/i2c"
    echo 0 > "$inst/events/i2c/enable"
    : > "$inst/events/i2c/filter"
    : > "$inst/trace"
    : > "$inst/buffer_size_kb"
    start_chipup_i2c_trace 0
    printf '%s\\n' "$CHIPUP_I2C_TRACE_INSTANCE" > "$out"
    sleep 0.2
    stop_chipup_i2c_trace
}}
start_one "{out1}" &
start_one "{out2}" &
wait
""".format(helpers=HELPERS, tracefs=tracefs, out1=out1, out2=out2)
    result = _run_bash(script, tmp_path)
    assert result.returncode == 0, result.stderr
    inst1 = out1.read_text().strip()
    inst2 = out2.read_text().strip()
    assert inst1
    assert inst2
    assert inst1 != inst2
    assert "hwmgmt_chipup_0_" in inst1
    assert "hwmgmt_chipup_0_" in inst2


def test_save_chipup_trace_serializes_to_shared_log(tmp_path):
    tracefs = _make_tracefs(tmp_path / "tracefs")
    log_file = tmp_path / "chipup_i2c_trace_log"
    lock_file = tmp_path / "chipup-trace.lock"
    script = """
source "{helpers}"
KERN_TRACE_FS="{tracefs}"
export HW_MGMT_CHIPUP_TRACE_LOG="{log}"
export HW_MGMT_CHIPUP_TRACE_LOCK="{lock}"
pid=$BASHPID
inst="$KERN_TRACE_FS/instances/hwmgmt_chipup_0_$pid"
mkdir -p "$inst/events/i2c"
echo 0 > "$inst/events/i2c/enable"
: > "$inst/events/i2c/filter"
echo 'i2c_write sample' > "$inst/trace"
: > "$inst/buffer_size_kb"
start_chipup_i2c_trace 0
echo 'i2c_write sample' > "$CHIPUP_TRACE_DIR/trace"
save_chipup_i2c_trace 1
stop_chipup_i2c_trace
""".format(helpers=HELPERS, tracefs=tracefs, log=log_file, lock=lock_file)
    result = _run_bash(script, tmp_path)
    assert result.returncode == 0, result.stderr
    text = log_file.read_text()
    assert "chipup attempt 1 pid:" in text
    assert "i2c_write sample" in text


def test_is_spc1_system_by_vmod_and_product(tmp_path):
    script = _helpers_preamble(tmp_path, board="VMOD0001", product="x") + """
is_spc1_system; echo VMOD:$?
board_type_file="{tmp}/board2"
echo VMOD0010 > "$board_type_file"
pn_file="{tmp}/pn2"
echo MSN27002 > "$pn_file"
is_spc1_system; echo PROD:$?
echo UNKNOWN > "$board_type_file"
echo OTHER > "$pn_file"
is_spc1_system; echo NO:$?
""".format(tmp=tmp_path)
    # board2/pn2 created in-script; preamble already sourced.
    (tmp_path / "board2").write_text("VMOD0010\n")
    (tmp_path / "pn2").write_text("MSN27002\n")
    result = _run_bash(script, tmp_path)
    assert result.returncode == 0, result.stderr
    assert "VMOD:0" in result.stdout
    assert "PROD:0" in result.stdout
    assert "NO:1" in result.stdout


def test_spc1_warm_reboot_comex_and_platform(tmp_path):
    script = _helpers_preamble(
        tmp_path, reset_attrs={"reset_from_comex": "1"}
    ) + """
is_spc1_warm_reboot; echo COMEX:$?
echo 0 > "$system_path/reset_from_comex"
echo 1 > "$system_path/reset_platform"
is_spc1_warm_reboot; echo PLAT:$?
"""
    result = _run_bash(script, tmp_path)
    assert result.returncode == 0, result.stderr
    assert "COMEX:0" in result.stdout
    assert "PLAT:0" in result.stdout


def test_spc1_cold_reset_skips_pwm_fallback(tmp_path):
    result, mlxreg_log = _run_pwm_fail_helper(
        tmp_path,
        reset_attrs={"reset_aux_pwr_or_ref": "1", "reset_from_comex": "1"},
    )
    assert result.returncode == 0, result.stderr
    assert "RC:1" in result.stdout
    assert not mlxreg_log.exists()


def test_non_spc1_skips_pwm_fallback(tmp_path):
    result, mlxreg_log = _run_pwm_fail_helper(
        tmp_path,
        board="VMOD0010",
        product="MSN3700",
        reset_attrs={"reset_from_comex": "1"},
    )
    assert result.returncode == 0, result.stderr
    assert "RC:1" in result.stdout
    assert not mlxreg_log.exists()


def test_normalize_zero_and_one_based_indexes(tmp_path):
    script = _helpers_preamble(tmp_path) + """
echo ZERO:$(_hw_mgmt_normalize_asic_index 0)
echo EMPTY:$(_hw_mgmt_normalize_asic_index "")
echo TWO:$(_hw_mgmt_normalize_asic_index 2)
"""
    result = _run_bash(script, tmp_path)
    assert result.returncode == 0, result.stderr
    assert "ZERO:1" in result.stdout
    assert "EMPTY:1" in result.stdout
    assert "TWO:2" in result.stdout


def test_malformed_pci_is_treated_as_explicit_mst_path(tmp_path):
    script = _helpers_preamble(tmp_path) + """
get_asic_mlxreg_dev 0 "not-a-pci"
echo RC:$?
"""
    result = _run_bash(script, tmp_path)
    assert result.returncode == 0, result.stderr
    assert "not-a-pci" in result.stdout
    assert "RC:0" in result.stdout


def test_absent_pci_on_multi_asic_does_not_pick_first_pciconf(tmp_path):
    result, mlxreg_log = _run_pwm_fail_helper(
        tmp_path,
        asic_index="2",
        explicit_dev=None,
        asic_num=2,
        mst_map={"mt_asic1_pciconf0": "0000:03:00.0"},
    )
    assert result.returncode == 0, result.stderr
    assert "RC:1" in result.stdout
    assert not mlxreg_log.exists()


def test_index_zero_uses_asic1_pci_id(tmp_path):
    result, mlxreg_log = _run_pwm_fail_helper(
        tmp_path,
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


def test_one_based_index_targets_asic2(tmp_path):
    result, mlxreg_log = _run_pwm_fail_helper(
        tmp_path,
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


def test_sxcore_pci_path_with_index_zero_selects_matching_asic(tmp_path):
    pci_path = tmp_path / "sys" / "devices" / "0000:05:00.0"
    pci_path.mkdir(parents=True)
    result, mlxreg_log = _run_pwm_fail_helper(
        tmp_path,
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


def test_mlxreg_uses_pci_bdf_when_mst_sysfs_missing(tmp_path):
    result, mlxreg_log = _run_pwm_fail_helper(
        tmp_path,
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


def test_warm_reboot_programs_mfsc(tmp_path):
    result, mlxreg_log = _run_pwm_fail_helper(tmp_path)
    assert result.returncode == 0, result.stderr
    assert "RC:0" in result.stdout
    args = mlxreg_log.read_text()
    assert "--reg_name MFSC" in args
    assert "pwm_duty_cycle=0xff" in args
    assert "--indexes pwm=0x0" in args
