#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# hw-management-dbus-if: abstraction layer for all D-Bus (busctl/dbus-send)
# calls used by hw-mgmt/bmc. Allows swapping OpenBMC/Phosphor backends for
# SONiC BMC or other stacks.
#
# Usage: hw-management-dbus-if.sh <command> [args...]
################################################################################

set -e

CMD="${1:-}"
shift || true

case "$CMD" in
# --- State.Host (powerctrl, helpers) ---
host_state_off)
    busctl set-property xyz.openbmc_project.State.Host /xyz/openbmc_project/state/host0 xyz.openbmc_project.State.Host CurrentHostState s "xyz.openbmc_project.State.Host.HostState.Off"
    ;;
host_state_on)
    busctl set-property xyz.openbmc_project.State.Host /xyz/openbmc_project/state/host0 xyz.openbmc_project.State.Host CurrentHostState s "xyz.openbmc_project.State.Host.HostState.Running"
    ;;
requested_host_transition_on)
    busctl set-property xyz.openbmc_project.State.Host /xyz/openbmc_project/state/host0 xyz.openbmc_project.State.Host RequestedHostTransition s "xyz.openbmc_project.State.Host.Transition.On"
    ;;
requested_host_transition_off)
    busctl set-property xyz.openbmc_project.State.Host /xyz/openbmc_project/state/host0 xyz.openbmc_project.State.Host RequestedHostTransition s "xyz.openbmc_project.State.Host.Transition.Off"
    ;;

# --- Settings / power restore (helpers) ---
power_restore_delay)
    busctl get-property xyz.openbmc_project.Settings /xyz/openbmc_project/control/host0/power_restore_policy xyz.openbmc_project.Control.Power.RestorePolicy PowerRestoreDelay | awk '{print $2}'
    ;;
power_restore_policy)
    busctl get-property xyz.openbmc_project.Settings /xyz/openbmc_project/control/host0/power_restore_policy xyz.openbmc_project.Control.Power.RestorePolicy PowerRestorePolicy | awk '{print $2}' | sed 's/^"//; s/"$//'
    ;;

# --- State.Chassis (bmc_ready) ---
chassis_power_state_on)
    busctl set-property xyz.openbmc_project.State.Chassis /xyz/openbmc_project/state/chassis0 xyz.openbmc_project.State.Chassis CurrentPowerState s xyz.openbmc_project.State.Chassis.PowerState.On
    ;;

# --- Software.Settings (bmc_ready) ---
software_settings_set_write_protect_init)
    # $1 = true|false
    busctl call xyz.openbmc_project.Software.Settings /xyz/openbmc_project/software/System_0 xyz.openbmc_project.Software.Settings SetWriteProtectInit b "${1:-true}"
    ;;

# --- User.Manager (bmc_ready_common) ---
user_manager_get_groups)
    # $1 = username
    busctl get-property xyz.openbmc_project.User.Manager /xyz/openbmc_project/user/${1} xyz.openbmc_project.User.Attributes UserGroups 2>/dev/null || true
    ;;
user_manager_set_groups)
    # $1 = username, $2 $3 $4 = group names (e.g. hostconsole ssh redfish)
    busctl set-property xyz.openbmc_project.User.Manager /xyz/openbmc_project/user/${1} xyz.openbmc_project.User.Attributes UserGroups as 3 "${2:-hostconsole}" "${3:-ssh}" "${4:-redfish}"
    ;;
user_manager_create_user)
    # $1 = name, $2 = groups count, $3 = groups json, $4 = privilege, $5 = enabled (true/false)
    busctl call xyz.openbmc_project.User.Manager /xyz/openbmc_project/user xyz.openbmc_project.User.Manager CreateUser sassb "$1" "${2:-4}" "${3:-{\"ipmi\",\"redfish\",\"ssh\",\"hostconsole\"}}" "${4:-priv-admin}" "${5:-true}"
    ;;

# --- Syslog.Config (i2c-boot-progress) ---
syslog_config_get_address)
    busctl get-property xyz.openbmc_project.Syslog.Config /xyz/openbmc_project/logging/config/remote xyz.openbmc_project.Network.Client Address | awk '{ print $2 }'
    ;;
syslog_config_get_port)
    busctl get-property xyz.openbmc_project.Syslog.Config /xyz/openbmc_project/logging/config/remote xyz.openbmc_project.Network.Client Port | awk '{ print $2 }'
    ;;
syslog_config_enable)
    # $1 = on|off, optional $2 = port, $3 = address
    if [[ "${1:-}" == "on" ]]; then
        busctl set-property xyz.openbmc_project.Syslog.Config /xyz/openbmc_project/logging/config/remote xyz.openbmc_project.Logging.RsyslogClient Enabled b true
        busctl set-property xyz.openbmc_project.Syslog.Config /xyz/openbmc_project/logging/config/remote xyz.openbmc_project.Logging.RsyslogClient Severity s "xyz.openbmc_project.Logging.RsyslogClient.SeverityType.All"
        busctl set-property xyz.openbmc_project.Syslog.Config /xyz/openbmc_project/logging/config/remote xyz.openbmc_project.Network.Client Port q "${2:-6514}"
        busctl set-property xyz.openbmc_project.Syslog.Config /xyz/openbmc_project/logging/config/remote xyz.openbmc_project.Network.Client Address s "${3:-192.168.31.2}"
    else
        busctl set-property xyz.openbmc_project.Syslog.Config /xyz/openbmc_project/logging/config/remote xyz.openbmc_project.Logging.RsyslogClient Enabled b false
        busctl set-property xyz.openbmc_project.Syslog.Config /xyz/openbmc_project/logging/config/remote xyz.openbmc_project.Network.Client Port q 0
        busctl set-property xyz.openbmc_project.Syslog.Config /xyz/openbmc_project/logging/config/remote xyz.openbmc_project.Network.Client Address s ""
    fi
    ;;

# --- Logging.Create (i2c-boot-progress, various) ---
logging_create_resource_corrected)
    # $1 = message_args (e.g. "BMC Flash,Data Corruption")
    busctl call xyz.openbmc_project.Logging /xyz/openbmc_project/logging xyz.openbmc_project.Logging.Create Create ssa{ss} \
        ResourceEvent.1.0.ResourceErrorsCorrected xyz.openbmc_project.Logging.Entry.Level.Informational 2 \
        REDFISH_MESSAGE_ID ResourceEvent.1.0.ResourceErrorsCorrected \
        REDFISH_MESSAGE_ARGS "${1:-}"
    ;;
logging_create_resource_detected)
    # $1 = message_args, $2 = resolution (optional)
    busctl call xyz.openbmc_project.Logging /xyz/openbmc_project/logging xyz.openbmc_project.Logging.Create Create ssa{ss} \
        ResourceEvent.1.0.ResourceErrorsDetected xyz.openbmc_project.Logging.Entry.Level.Critical 3 \
        REDFISH_MESSAGE_ID ResourceEvent.1.0.ResourceErrorsDetected \
        REDFISH_MESSAGE_ARGS "${1:-}" \
        xyz.openbmc_project.Logging.Entry.Resolution "${2:-If problem persists, try restarting BMC}"
    ;;
logging_create_reboot_reason)
    # $1 = reason string
    busctl call xyz.openbmc_project.Logging /xyz/openbmc_project/logging xyz.openbmc_project.Logging.Create Create ssa{ss} \
        OpenBMC.0.4.BMCRebootReason xyz.openbmc_project.Logging.Entry.Level.Informational 2 \
        REDFISH_MESSAGE_ID OpenBMC.0.4.BMCRebootReason \
        REDFISH_MESSAGE_ARGS "$1"
    ;;
logging_create_resource_warning)
    # $1 = message_id, $2 = message_args
    busctl call xyz.openbmc_project.Logging /xyz/openbmc_project/logging xyz.openbmc_project.Logging.Create Create ssa{ss} \
        ResourceEvent.1.0.ResourceStatusChangedWarning xyz.openbmc_project.Logging.Entry.Level.Informational 2 \
        REDFISH_MESSAGE_ID "${1:-ResourceEvent.1.0.ResourceStatusChangedWarning}" \
        REDFISH_MESSAGE_ARGS "${2:-}"
    ;;

# --- Software.BMC.Inventory factory reset (i2c-boot-progress) ---
factory_reset)
    dbus-send --system --print-reply --dest=xyz.openbmc_project.Software.BMC.Inventory /xyz/openbmc_project/software/bmc xyz.openbmc_project.Common.FactoryReset.Reset
    ;;

# --- Service status (i2c-boot-progress uses systemctl for Dump.Manager etc.; no busctl) ---
*)
    echo "Usage: $0 <command> [args...]" >&2
    echo "  host_state_off | host_state_on | requested_host_transition_on | requested_host_transition_off" >&2
    echo "  power_restore_delay | power_restore_policy" >&2
    echo "  chassis_power_state_on | software_settings_set_write_protect_init [true|false]" >&2
    echo "  user_manager_get_groups <username> | user_manager_set_groups <user> [g1 g2 g3] | user_manager_create_user <name> [cnt] [groups] [priv] [enabled]" >&2
    echo "  syslog_config_get_address | syslog_config_get_port | syslog_config_enable on|off [port] [addr]" >&2
    echo "  logging_create_resource_corrected <args> | logging_create_resource_detected <args> [resolution]" >&2
    echo "  logging_create_reboot_reason <reason> | logging_create_resource_warning [msg_id] <args>" >&2
    echo "  factory_reset" >&2
    exit 1
    ;;
esac
