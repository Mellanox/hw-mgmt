#!/usr/bin/env python3
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# Unit tests for the BMC Redfish login that moved out of hw-management.sh into
# hw-management-bmc-login.sh and its own service.
#
# Verifies: the wait covers an absent usb0 as well as one without an address;
# no login is tried before the BMC serves Redfish; the login is retried;
# start_bmc_login_if_needed works whatever state hw-management.service is in,
# without pulling that unit in; the waits do not hold up boot.

import ast
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.offline

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / "usr" / "usr" / "bin"
HELPERS = BIN / "hw-management-helpers.sh"
LOGIN_SH = BIN / "hw-management-bmc-login.sh"
LOGIN_UNIT = ROOT / "debian" / "hw-management.hw-management-bmc-login.service"
UDEV_RULES = ROOT / "usr" / "lib" / "udev" / "rules.d" / "70-hw-management-bmc.rules"

_HELPER_STUBS = """#!/bin/bash
print_function_call() { echo "TRACE: $3"; }
log_info() { echo "INFO: $*"; }
log_err() { echo "ERR: $*"; }
check_bmc_is_supported() { return "${STUB_BMC_SUPPORTED:-0}"; }
check_host_os_is_redfish_disabled() { return "${STUB_REDFISH_DISABLED:-1}"; }
"""

# Reports the address written to $STUB_ADDR_FILE, and behaves like the real one
# for an absent interface: nothing on stdout, a message on stderr, nonzero.
_IP_STUB = """#!/bin/bash
iface=${!#}
if [ ! -e "${STUB_NET_DIR}/${iface}" ]; then
	echo "Device \\"${iface}\\" does not exist." >&2
	exit 1
fi
addr=$(cat "${STUB_ADDR_FILE}" 2>/dev/null)
[ -n "${addr}" ] || exit 0
echo "2: ${iface}    inet ${addr}/24 brd 10.0.1.255 scope global ${iface}"
"""

# Answers the Redfish probe with the HTTP code written to $STUB_REDFISH_FILE,
# where 000 stands for a BMC that does not answer, and records every URL.
_CURL_STUB = """#!/bin/bash
echo "${!#}" >> "${STUB_PROBES}"
code=$(cat "${STUB_REDFISH_FILE}")
printf '%s' "${code}"
[ "${code}" != "000" ] || exit 7
"""

# Counts the login attempts, with what Redfish was answering at the time, and
# fails as told. The client lives in /usr/bin, so an interpreter started from
# anywhere else needs it on the search path.
_PYTHON_STUB = """#!/bin/bash
echo "attempt redfish=$(cat "${STUB_REDFISH_FILE}")" >> "${STUB_ATTEMPTS}"
[ "${PYTHONPATH}" = "/usr/bin" ] || { echo "PYTHONPATH=${PYTHONPATH}" >&2; exit 2; }
exit "${STUB_LOGIN_RC:-0}"
"""


def _login_env(tmp_path, address="", interface_exists=False, redfish="200"):
    """Install the stubs and a copy of the login script with small budgets."""
    helpers = tmp_path / "helpers.sh"
    helpers.write_text(_HELPER_STUBS)

    binfiles = tmp_path / "bin"
    binfiles.mkdir()
    for name, body in (("ip", _IP_STUB), ("curl", _CURL_STUB), ("python3", _PYTHON_STUB)):
        stub = binfiles / name
        stub.write_text(body)
        stub.chmod(0o755)

    net = tmp_path / "net"
    net.mkdir()
    if interface_exists:
        (net / "usb0").touch()
    (tmp_path / "addr").write_text(address)
    (tmp_path / "redfish").write_text(redfish)
    (tmp_path / "attempts").touch()
    (tmp_path / "probes").touch()

    script = LOGIN_SH.read_text()
    script = script.replace("source /usr/bin/hw-management-helpers.sh", f"source {helpers}")
    script = script.replace("/sys/class/net/", f"{net}/")
    script = script.replace("ADDRESS_TIMEOUT=60", "ADDRESS_TIMEOUT=4")
    script = script.replace("ADDRESS_POLL=2", "ADDRESS_POLL=1")
    script = script.replace("REDFISH_TIMEOUT=300", "REDFISH_TIMEOUT=4")
    script = script.replace("REDFISH_POLL=5", "REDFISH_POLL=1")
    script = script.replace("LOGIN_DELAY=5", "LOGIN_DELAY=0")
    login = tmp_path / "login.sh"
    login.write_text(script)
    login.chmod(0o755)

    env = {
        "PATH": f"{binfiles}:/usr/bin:/bin",
        "STUB_NET_DIR": str(net),
        "STUB_ADDR_FILE": str(tmp_path / "addr"),
        "STUB_ATTEMPTS": str(tmp_path / "attempts"),
        "STUB_REDFISH_FILE": str(tmp_path / "redfish"),
        "STUB_PROBES": str(tmp_path / "probes"),
    }
    return login, env


def _run_login(login, env, extra=None, timeout=30):
    r = subprocess.run(
        ["bash", str(login)],
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**env, **(extra or {})},
    )
    attempts = Path(env["STUB_ATTEMPTS"]).read_text().count("attempt")
    return r, attempts


def test_absent_usb0_is_waited_for_instead_of_skipped(tmp_path):
    """The BMC owns usb0 and takes it away while it resets, so an absent
    interface is the very case the wait exists for. Exiting on it left the
    platforms without Redfish sensor polling unprovisioned for a whole boot."""
    login, env = _login_env(tmp_path, interface_exists=False)

    # usb0 comes back, with an address, while the wait is running.
    waiter = subprocess.Popen(
        ["bash", "-c", f'sleep 2; touch "{tmp_path}/net/usb0"; echo 10.0.1.2 > "{tmp_path}/addr"']
    )
    try:
        r, attempts = _run_login(login, env)
    finally:
        waiter.wait()

    assert r.returncode == 0, r.stdout + r.stderr
    assert attempts == 1
    assert "logged in to the BMC on attempt 1" in r.stdout


def test_usb0_that_never_appears_is_reported_as_missing(tmp_path):
    """Distinguished from a configured interface without an address, so the log
    says whether the BMC was gone or the ifup never completed."""
    login, env = _login_env(tmp_path, interface_exists=False)
    r, attempts = _run_login(login, env)

    assert r.returncode == 1
    assert attempts == 0
    assert "usb0 did not appear" in r.stdout


def test_usb0_without_an_address_is_reported_as_such(tmp_path):
    login, env = _login_env(tmp_path, interface_exists=True)
    r, attempts = _run_login(login, env)

    assert r.returncode == 1
    assert attempts == 0
    assert "usb0 got no address" in r.stdout


def test_configured_usb0_logs_in_once(tmp_path):
    login, env = _login_env(tmp_path, address="10.0.1.2", interface_exists=True)
    r, attempts = _run_login(login, env)

    assert r.returncode == 0
    assert attempts == 1
    # The address line keeps the name the flow had in hw-management.sh, so the
    # existing greps of the trace log still find it.
    assert "BMC IP address: 10.0.1.2" in r.stdout


def test_login_is_retried_before_giving_up(tmp_path):
    """Redfish answering does not mean every service behind it is ready."""
    login, env = _login_env(tmp_path, address="10.0.1.2", interface_exists=True)
    r, attempts = _run_login(login, env, extra={"STUB_LOGIN_RC": "1"})

    assert r.returncode == 1
    assert attempts == 3
    assert "failed to log in to the BMC after 3 attempts" in r.stdout


def test_login_waits_for_the_bmc_to_serve_redfish(tmp_path):
    """The BMC brings usb0 up early in its boot, long before its web server
    answers. Logging in meanwhile failed every step of the flow with a cURL
    error, and three attempts were spent within 45s of the address appearing."""
    login, env = _login_env(tmp_path, address="10.0.1.2", interface_exists=True, redfish="000")

    flipper = subprocess.Popen(["bash", "-c", f'sleep 2; echo -n 200 > "{tmp_path}/redfish"'])
    try:
        r, _ = _run_login(login, env)
    finally:
        flipper.wait()

    assert r.returncode == 0, r.stdout + r.stderr
    # Not one login was tried before Redfish answered.
    assert (tmp_path / "attempts").read_text().splitlines() == ["attempt redfish=200"]
    assert "Waiting for the BMC Redfish service at 10.0.1.1" in r.stdout
    assert "Redfish service at 10.0.1.1 answered after" in r.stdout


def test_bmc_that_never_serves_redfish_costs_no_login_attempt(tmp_path):
    """Each failed flow tries passwords that are wrong for the account, which a
    BMC that is half up could count towards locking it."""
    login, env = _login_env(tmp_path, address="10.0.1.2", interface_exists=True, redfish="000")
    r, attempts = _run_login(login, env)

    assert r.returncode == 1
    assert attempts == 0
    assert "Redfish service at 10.0.1.1 did not answer" in r.stdout
    # The service root of the BMC, at X.X.X.1, on both schemes the client uses.
    probes = set((tmp_path / "probes").read_text().split())
    assert probes == {"http://10.0.1.1/redfish/v1", "https://10.0.1.1/redfish/v1"}


@pytest.mark.parametrize("code, ready", [
    ("200", True),
    # A BMC that protects the service root is up all the same.
    ("401", True),
    # bmcweb up, but the BMC behind it is not.
    ("503", False),
])
def test_what_counts_as_redfish_answering(code, ready, tmp_path):
    login, env = _login_env(tmp_path, address="10.0.1.2", interface_exists=True, redfish=code)
    r, attempts = _run_login(login, env)

    assert (r.returncode == 0) == ready, r.stdout
    assert attempts == (1 if ready else 0)


def test_platform_without_a_bmc_does_not_wait(tmp_path):
    login, env = _login_env(tmp_path, interface_exists=False)
    r, attempts = _run_login(login, env, extra={"STUB_BMC_SUPPORTED": "1"}, timeout=3)

    assert r.returncode == 0
    assert attempts == 0
    assert "not applicable" in r.stdout


def _login_guard(sku, login_is_active, tmp_path):
    """Run start_bmc_login_if_needed against a stubbed systemctl. Any call other
    than the two expected ones - above all a start of hw-management.service -
    shows up as UNEXPECTED."""
    driver = tmp_path / "guard-driver.sh"
    driver.write_text(f"""#!/bin/bash
source {HELPERS}
vm_sku={sku}
log_info() {{ :; }}
print_function_call() {{ :; }}
systemctl() {{
    case "$*" in
        "is-active --quiet hw-management-bmc-login.service") return {0 if login_is_active else 1} ;;
        "start --no-block hw-management-bmc-login.service") echo STARTED ;;
        *) echo "UNEXPECTED: $*" ;;
    esac
}}
start_bmc_login_if_needed
""")
    r = subprocess.run(["bash", str(driver)], capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    assert "UNEXPECTED" not in r.stdout, r.stdout
    return "STARTED" in r.stdout


def test_login_is_started_whatever_state_the_parent_unit_is_in(tmp_path):
    """A start after "systemctl stop hw-management.service" initializes the
    hardware while leaving that unit inactive. Gating on it there would lose the
    BMC account setup that hw-management.sh used to perform itself; the guard
    therefore does not look at the unit at all, which the stubbed systemctl
    enforces by reporting any other call as UNEXPECTED."""
    assert _login_guard("HI183", False, tmp_path)


def test_running_login_is_not_started_a_second_time(tmp_path):
    assert not _login_guard("HI183", True, tmp_path)


def test_platform_without_a_bmc_starts_no_login(tmp_path):
    assert not _login_guard("HI100", False, tmp_path)


def test_hw_management_is_never_pulled_in_by_the_login():
    """Requires= would start the whole hardware initialization whenever the unit
    is started on its own: from the usb0 service after a BMC reset, or from
    hw-management-start-post.sh on a start that systemd did not drive."""
    unit = LOGIN_UNIT.read_text()
    helpers = HELPERS.read_text()
    guard = helpers[helpers.index("start_bmc_login_if_needed()"):]

    assert "Requires=hw-management.service" not in unit
    assert "After=hw-management.service" in unit
    assert "PartOf=hw-management.service" in unit
    assert "hw-management.service" not in guard[:guard.index("}")]
    assert "--no-block" in guard


def test_login_is_ordered_after_the_interface_and_reached_from_both_paths():
    """Ordering only on the interface unit, which UDEV activates: pulling it in
    would start it where the interface never shows up and its BindsTo= on the
    device would fail it."""
    unit = LOGIN_UNIT.read_text()
    hw_unit = (ROOT / "debian" / "hw-management.hw-management.service").read_text()
    start_post = (BIN / "hw-management-start-post.sh").read_text()

    assert "After=hw-management-ifupdown@usb0.service" in unit
    assert "Wants=hw-management-ifupdown@usb0.service" not in unit
    assert "Wants=hw-management-bmc-login.service" in hw_unit
    assert "start_bmc_login_if_needed" in start_post


def test_interface_handled_late_replaces_a_login_that_is_already_running():
    """A login started at boot waits on deadlines of its own. When usb0 shows up
    near the end of the address wait, or the BMC resets while the login waits
    for Redfish, a start from that event finds the login running and leaves it
    to run out. Only a restart gives the interface a login with fresh budgets,
    and only the interface unit knows when the interface has been handled."""
    ifupdown_unit = (ROOT / "debian" / "hw-management-ifupdown@.service").read_text()
    rules = UDEV_RULES.read_text()

    post = re.findall(r"^ExecStartPost=(.*)$", ifupdown_unit, re.MULTILINE)
    assert post == ["-/bin/systemctl --no-block restart hw-management-bmc-login.service"]
    # Post, not a second ExecStart: it must run only once the interface has
    # been handled, not after ifup has failed.
    assert ifupdown_unit.index("ExecStart=") < ifupdown_unit.index("ExecStartPost=")
    # A start from the device event as well would be the one that does nothing
    # while a login runs.
    wants = rules[rules.index("ENV{SYSTEMD_WANTS}"):]
    assert "hw-management-bmc-login" not in wants


def test_interface_script_succeeds_when_the_interface_was_handled():
    """ExecStartPost= runs only once ExecStart= succeeded, so the restart
    follows the exit status of the interface script: 0 once ifup succeeded or
    the NOS that owns usb0 configures it, 1 once every ifup attempt failed and
    there is nothing to log in on."""
    ifupdown = (BIN / "hw-management-ifupdown.sh").read_text()

    success = ifupdown[ifupdown.index("succeeded on attempt"):]
    assert re.match(r"[^\n]*\n\s*exit 0\n", success)
    nos = ifupdown[ifupdown.index("check_host_usb0_managed_by_nos; then"):]
    assert re.match(r"[^\n]*\n[^\n]*\n\s*exit 0\n", nos)
    assert ifupdown.rstrip().endswith("exit 1")


def test_login_left_hw_management_sh():
    """It raced the configuration of usb0 from there: 15s of waiting, started
    well before the interface unit, which runs after the networking service."""
    hw_management = (BIN / "hw-management.sh").read_text()

    assert "check_system_bmc_redfish_login" not in hw_management
    assert "BMCAccessor" not in hw_management


def _setting(text, name):
    return int(re.search(rf"^{name}=(\d+)$", text, re.MULTILINE).group(1))


# What the client runs without a deadline of its own: tpm2_createprimary has no
# timeout, and runs up to 100 times for a legacy password, and the PATCH that
# sets the password of the NOS account has no max-time.
TPM_GENERATION_ALLOWANCE = 10
INTERPRETER_ALLOWANCE = 2


def _client_class(tree, name):
    return next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == name)


def _client_method(tree, cls, name):
    return next(n for n in _client_class(tree, cls).body
                if isinstance(n, ast.FunctionDef) and n.name == name)


def _client_constant(tree, cls, name):
    return next(ast.literal_eval(n.value) for n in _client_class(tree, cls).body
                if isinstance(n, ast.Assign) and any(getattr(t, "id", None) == name for t in n.targets))


def _calls(node, name):
    return sum(1 for n in ast.walk(node)
               if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == name)


def _login_attempt_budget():
    """Worst case of one BMCAccessor().login(). Every request and every password
    derivation in the flow is counted, whichever branch of it they are on, which
    bounds the path any single run takes."""
    tree = ast.parse((BIN / "hw_management_redfish_client.py").read_text())
    flow = _client_method(tree, "BMCAccessor", "login")
    constructor = _client_method(tree, "BMCAccessor", "__init__")
    exec_curl = _client_method(tree, "RedfishClient", "exec_curl_cmd")

    timeout = _client_constant(tree, "RedfishClient", "DEFAULT_GET_TIMEOUT")
    # A request that cannot connect is sent again on the other scheme.
    fallback = any(isinstance(n, ast.Attribute) and "alt_scheme" in n.attr for n in ast.walk(exec_curl))
    request = timeout * (2 if fallback else 1)

    logins = _calls(flow, "try_rf_login") + _calls(flow, "login")
    # An empty reply to the POST logs in again and resends it, on one scheme.
    posts = _calls(flow, "create_user")
    post = request + request + timeout
    # Allowed as long as a request that has a deadline.
    patches = _calls(flow, "reset_user_password")
    derivations = _calls(flow, "get_login_password") + _calls(constructor, "get_login_password")
    derivation = _client_constant(tree, "BMCAccessor", "FLOCK_TIMEOUT_SEC") + TPM_GENERATION_ALLOWANCE

    # A-B-C-C1, the admin login of D and the login as the account D created.
    assert logins >= 6 and posts >= 1 and patches >= 1 and derivations >= 2
    return (logins * request + posts * post + patches * request +
            derivations * derivation + INTERPRETER_ALLOWANCE)


def test_waiting_for_the_bmc_does_not_hold_up_boot():
    """multi-user.target orders itself after the units it wants, so a oneshot
    would hold it for as long as the BMC takes to boot."""
    unit = LOGIN_UNIT.read_text()
    script = LOGIN_SH.read_text()

    assert "Type=oneshot" not in unit
    assert "Type=simple" in unit
    assert "TimeoutStartSec=" not in unit
    # The limit has to cover both waits, the overshoot of the last Redfish
    # probe on both schemes and the login retries, each of which may run the
    # whole flow of the client.
    budget = (
        _setting(script, "ADDRESS_TIMEOUT") + _setting(script, "ADDRESS_POLL") +
        _setting(script, "REDFISH_TIMEOUT") + _setting(script, "REDFISH_POLL") +
        2 * _setting(script, "REDFISH_PROBE_TIMEOUT") +
        _setting(script, "LOGIN_RETRIES") * _login_attempt_budget() +
        (_setting(script, "LOGIN_RETRIES") - 1) * _setting(script, "LOGIN_DELAY")
    )
    assert _setting(unit, "RuntimeMaxSec") > budget


def _spec_section(spec, name):
    m = re.search(
        rf"^%{name}\n(.*?)(?=^%(?:post|preun|postun|description|install|files)\n|\Z)",
        spec, re.DOTALL | re.MULTILINE)
    assert m, f"%{name} missing from the spec"
    return m.group(1)


def _code(text):
    return re.sub(r"(^|\s)#.*$", "", text, flags=re.MULTILINE)


def _programs_run_by_helpers(scripts):
    """Programs of this package that the helper functions the scripts call run
    in turn, following helpers that call other helpers."""
    helpers = HELPERS.read_text()
    defined = set(re.findall(r"^([a-z_]+)\(\)", helpers, re.MULTILINE))
    pending = [w for s in scripts for w in re.findall(r"\b[a-z_]+\b", _code(s.read_text()))]
    seen, programs = set(), set()
    while pending:
        name = pending.pop()
        if name not in defined or name in seen:
            continue
        seen.add(name)
        body = re.search(rf"^{name}\(\)\s*\{{(.*?)^\}}", helpers, re.DOTALL | re.MULTILINE).group(1)
        body = _code(body)
        programs |= {p for p in re.findall(r"/usr/bin/([\w.-]+)", body) if (BIN / p).exists()}
        pending += re.findall(r"\b[a-z_]+\b", body)
    return programs


def test_rpm_packages_everything_the_bmc_login_runs():
    """The spec lists its files one by one, where debian/rules copies whole
    directories, so a script the login needs is missing from the RPM unless it
    is added there by name - as the Redfish client was, which left the login
    that hw-management.sh ran failing on its import."""
    spec = (ROOT / "rpm" / "hw-management.spec").read_text()
    install = _spec_section(spec, "install")
    files = _spec_section(spec, "files")
    ifup_sh = BIN / "hw-management-ifupdown.sh"

    needed = {
        "usr/usr/bin/hw-management-bmc-login.sh": "/usr/bin/hw-management-bmc-login.sh",
        "usr/usr/bin/hw-management-helpers.sh": "/usr/bin/hw-management-helpers.sh",
        "usr/usr/bin/hw_management_redfish_client.py": "/usr/bin/hw_management_redfish_client.py",
        "usr/usr/bin/hw-management-ifupdown.sh": "/usr/bin/hw-management-ifupdown.sh",
        "usr/lib/udev/rules.d/70-hw-management-bmc.rules": "/lib/udev/rules.d/70-hw-management-bmc.rules",
        "debian/hw-management.hw-management-bmc-login.service":
            "/lib/systemd/system/hw-management-bmc-login.service",
        "debian/hw-management-ifupdown@.service": "/lib/systemd/system/hw-management-ifupdown@.service",
    }
    for program in _programs_run_by_helpers([LOGIN_SH, ifup_sh]):
        needed[f"usr/usr/bin/{program}"] = f"/usr/bin/{program}"

    for source, target in sorted(needed.items()):
        assert (ROOT / source).is_file(), source
        assert re.search(
            rf"^install -m 0\d+ {re.escape(source)} \$RPM_BUILD_ROOT{re.escape(target)}$",
            install, re.MULTILINE), f"{source} is not installed"
        assert f'"{target}"' in files, f"{target} is not in %files"


def test_rpm_enables_the_login_without_starting_it():
    """As in debian/rules: hw-management.service pulls the login in, and a start
    or restart from the package would only cut short a login that is waiting.
    Disabling is left to %systemd_preun, which does it only on erase, as the
    %preun of the old package runs after the %post of the new one on upgrade.
    The interface unit is activated by the device alone."""
    spec = (ROOT / "rpm" / "hw-management.spec").read_text()
    post = _code(_spec_section(spec, "post"))
    preun = _code(_spec_section(spec, "preun"))
    postun = _code(_spec_section(spec, "postun"))

    assert re.search(r"^systemctl enable %\{name\}-bmc-login\.service$", post, re.MULTILINE)
    assert not re.search(r"(start|restart)\S* .*bmc-login", post)
    assert re.findall(r"^.*bmc-login.*$", preun, re.MULTILINE) == ["%systemd_preun %{name}-bmc-login.service"]
    assert re.findall(r"^.*bmc-login.*$", postun, re.MULTILINE) == ["%systemd_postun %{name}-bmc-login.service"]
    assert "ifupdown" not in post + preun + postun


def test_rpm_requires_the_tools_the_login_runs():
    """AutoReq is off, so the spec has to name them. Without the TPM tools no
    password can be derived, without xxd not on legacy platforms either, and
    without curl nothing reaches the BMC: the package would install and every
    login would fail before it could provision the account."""
    spec = (ROOT / "rpm" / "hw-management.spec").read_text()
    required = set(re.findall(r"^Requires:\s*(\S+)", spec[:spec.index("\n%post\n")], re.MULTILINE))
    client = _code((BIN / "hw_management_redfish_client.py").read_text())

    tools = {re.search(r"CURL_PATH = '([^']+)'", client).group(1)}
    tools |= {f"/usr/bin/{t}" for t in ("tpm2_createprimary", "xxd") if re.search(rf"\b{t}\b", client)}
    assert len(tools) == 3
    assert tools <= required
    # Some distributions have no plain "python", and the client is Python 3.
    assert "python3" in required
    assert re.search(r"\bpython3 -c\b", _code(LOGIN_SH.read_text()))
