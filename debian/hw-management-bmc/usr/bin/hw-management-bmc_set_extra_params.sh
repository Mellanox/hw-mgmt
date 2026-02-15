#!/bin/bash

################################################################################
# BMC Extra Boot Parameters Script
# Purpose: Set extra U-Boot command line and boot arguments
# Usage: Source this script and call set_extrabootargs_and_bootcmdline()
################################################################################

BOOTCMD_DEFAULT="bootm 20100000"

################################################################################
# Function: get_fw_env_var
# Description: Get value of firmware environment variable
# Input: Variable name
# Output: Variable value (or empty string if not set)
################################################################################
get_fw_env_var() {
    local var_name="$1"
    fw_printenv -n "$var_name" 2>/dev/null || echo ""
}

################################################################################
# Function: set_extrabootargs_and_bootcmdline
# Description: Set new boot arguments and boot command line
#              Only updates if values differ from current settings
# Input:
#     Parameter 1 - extra command line (optional)
#     Parameter 2 - extra boot arguments (optional)
# Returns:
#     0 if changes were made (reboot needed)
#     1 if no changes were needed
# Example:
#     set_extrabootargs_and_bootcmdline "i2c dev 4; i2c md 0x51 0x00.2 0x100" "blacklist=mp2995"
################################################################################
set_extrabootargs_and_bootcmdline() {
    local CMD_LINE="$1"
    local BOOT_ARGS="$2"
    local changes_made=0

    # Get current values from firmware environment
    local CURRENT_CMDLINE=$(get_fw_env_var "extra_cmdline")
    local CURRENT_BOOTARGS=$(get_fw_env_var "extra_bootargs")

    echo "Checking boot parameters..."
    echo "  Current extra_cmdline:  ${CURRENT_CMDLINE:-<empty>}"
    echo "  New extra_cmdline:      ${CMD_LINE:-<empty>}"
    echo "  Current extra_bootargs: ${CURRENT_BOOTARGS:-<empty>}"
    echo "  New extra_bootargs:     ${BOOT_ARGS:-<empty>}"

    # Check if both parameters match current values
    local cmdline_match=0
    local bootargs_match=0
    local bootcmd_needs_update=0

    # Compare extra_cmdline
    if [ "$CURRENT_CMDLINE" = "$CMD_LINE" ]; then
        cmdline_match=1
        echo "  extra_cmdline already matches, skipping"
    fi

    # Compare extra_bootargs
    if [ "$CURRENT_BOOTARGS" = "$BOOT_ARGS" ]; then
        bootargs_match=1
        echo "  extra_bootargs already matches, skipping"
    fi

    # If both match, check if we still need to update bootcmd
    if [ $cmdline_match -eq 1 ] && [ $bootargs_match -eq 1 ]; then
        # Check if bootcmd is correctly set
        local CURRENT_BOOTCMD=$(get_fw_env_var "bootcmd")

        # Check if bootcmd has the expected format
        if [ -n "$CMD_LINE" ]; then
            # Should have "run extra_cmdline"
            if echo "$CURRENT_BOOTCMD" | grep -q "run extra_cmdline.*extra_bootargs"; then
                echo "All boot parameters already set correctly, no changes needed"
                return 1  # No changes needed
            else
                echo "Boot parameters match but bootcmd needs update"
                bootcmd_needs_update=1
            fi
        else
            # Should NOT have "run extra_cmdline"
            if echo "$CURRENT_BOOTCMD" | grep -q "extra_bootargs" && ! echo "$CURRENT_BOOTCMD" | grep -q "run extra_cmdline"; then
                echo "All boot parameters already set correctly, no changes needed"
                return 1  # No changes needed
            else
                echo "Boot parameters match but bootcmd needs update"
                bootcmd_needs_update=1
            fi
        fi
    fi

    # Get original bootcmd (only if we need it)
    local BOOTCMD_ORIGIN=$(fw_printenv -n bootcmd 2>/dev/null)

    # If bootcmd contains our modifications, extract the original command
    if echo "$BOOTCMD_ORIGIN" | grep -q "extra_cmdline\|extra_bootargs"; then
        # Extract the last command (after the last semicolon)
        BOOTCMD_ORIGIN=$(echo "$BOOTCMD_ORIGIN" | sed 's/.*; \([^;]*\)$/\1/')
        echo "Extracted original boot command: $BOOTCMD_ORIGIN"
    fi

    # If still empty or invalid, use default
    if [ -z "$BOOTCMD_ORIGIN" ]; then
        BOOTCMD_ORIGIN="$BOOTCMD_DEFAULT"
        echo "Using default boot command: $BOOTCMD_ORIGIN"
    else
        echo "Using existing boot command: $BOOTCMD_ORIGIN"
    fi

    echo "Setting extra boot parameters..."

    # Set extra_cmdline only if different
    if [ $cmdline_match -eq 0 ]; then
        if [ -n "$CMD_LINE" ]; then
            echo "Setting extra_cmdline: $CMD_LINE"
            if ! fw_setenv extra_cmdline "$CMD_LINE"; then
                echo "ERROR: Failed to set extra_cmdline"
                return 1
            fi
            changes_made=1
        else
            echo "Clearing extra_cmdline (empty)"
            if ! fw_setenv extra_cmdline ""; then
                echo "WARNING: Failed to clear extra_cmdline"
            fi
            changes_made=1
        fi
    fi

    # Set extra_bootargs only if different
    if [ $bootargs_match -eq 0 ]; then
        if [ -n "$BOOT_ARGS" ]; then
            echo "Setting extra_bootargs: $BOOT_ARGS"
            if ! fw_setenv extra_bootargs "$BOOT_ARGS"; then
                echo "ERROR: Failed to set extra_bootargs"
                return 1
            fi
            changes_made=1
        else
            echo "Clearing extra_bootargs (empty)"
            if ! fw_setenv extra_bootargs ""; then
                echo "WARNING: Failed to clear extra_bootargs"
            fi
            changes_made=1
        fi
    fi

    # Set bootcmd if needed
    if [ $bootcmd_needs_update -eq 1 ] || [ $cmdline_match -eq 0 ] || [ $bootargs_match -eq 0 ]; then
        # Construct new bootcmd - conditionally include "run extra_cmdline" only if CMD_LINE is not empty
        local new_bootcmd
        if [ -n "$CMD_LINE" ]; then
            # Include run extra_cmdline
            new_bootcmd="run extra_cmdline; setenv bootargs \"\${bootargs} \${extra_bootargs}\"; $BOOTCMD_ORIGIN"
        else
            # Skip run extra_cmdline if empty
            new_bootcmd="setenv bootargs \"\${bootargs} \${extra_bootargs}\"; $BOOTCMD_ORIGIN"
        fi

        echo "Setting bootcmd: $new_bootcmd"
        if ! fw_setenv bootcmd "$new_bootcmd"; then
            echo "ERROR: Failed to set bootcmd"
            return 1
        fi
        changes_made=1
    fi

    if [ $changes_made -eq 1 ]; then
        echo "Boot parameters updated successfully"
        echo "  extra_cmdline: ${CMD_LINE:-<empty>}"
        echo "  extra_bootargs: ${BOOT_ARGS:-<empty>}"
        echo "  boot command: $BOOTCMD_ORIGIN"
        return 0  # Changes made, reboot needed
    else
        echo "No changes were needed"
        return 1  # No changes
    fi
}

################################################################################
# Function: clear_extrabootargs_and_bootcmdline
# Description: Clear extra boot parameters and restore default bootcmd
# Returns:
#     0 if changes were made
#     1 if no changes were needed
################################################################################
clear_extrabootargs_and_bootcmdline() {
    echo "Clearing extra boot parameters..."

    # Check if already cleared
    local CURRENT_CMDLINE=$(get_fw_env_var "extra_cmdline")
    local CURRENT_BOOTARGS=$(get_fw_env_var "extra_bootargs")
    local CURRENT_BOOTCMD=$(get_fw_env_var "bootcmd")

    if [ -z "$CURRENT_CMDLINE" ] && [ -z "$CURRENT_BOOTARGS" ] && ! echo "$CURRENT_BOOTCMD" | grep -q "extra_"; then
        echo "Extra boot parameters already cleared, no changes needed"
        return 1
    fi

    # Get original bootcmd
    local BOOTCMD_ORIGIN=$(fw_printenv -n bootcmd 2>/dev/null)

    # If bootcmd contains our modifications, extract the original command
    if echo "$BOOTCMD_ORIGIN" | grep -q "extra_cmdline\|extra_bootargs"; then
        BOOTCMD_ORIGIN=$(echo "$BOOTCMD_ORIGIN" | sed 's/.*; \([^;]*\)$/\1/')
        echo "Extracted original boot command: $BOOTCMD_ORIGIN"
    fi

    # If still empty, use default
    if [ -z "$BOOTCMD_ORIGIN" ]; then
        BOOTCMD_ORIGIN="$BOOTCMD_DEFAULT"
    fi

    # Clear extra variables
    fw_setenv extra_cmdline ""
    fw_setenv extra_bootargs ""

    echo "Restoring original bootcmd: $BOOTCMD_ORIGIN"
    if ! fw_setenv bootcmd "$BOOTCMD_ORIGIN"; then
        echo "ERROR: Failed to restore bootcmd"
        return 1
    fi

    echo "Extra boot parameters cleared"
    return 0  # Changes made
}

################################################################################
# Function: show_boot_config
# Description: Display current boot configuration
################################################################################
show_boot_config() {
    echo "Current boot configuration:"
    echo "  bootcmd:        $(get_fw_env_var bootcmd)"
    echo "  bootargs:       $(get_fw_env_var bootargs)"
    echo "  extra_cmdline:  $(get_fw_env_var extra_cmdline)"
    echo "  extra_bootargs: $(get_fw_env_var extra_bootargs)"
}

################################################################################
# Function: reboot_bmc
# Description: Reboot BMC to apply new boot arguments and boot command line
################################################################################
reboot_bmc() {
    echo "Rebooting BMC to apply changes..."
    sync
    sleep 2
    reboot
}

# If script is executed directly (not sourced), show usage
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Usage: source this script and call functions:"
    echo ""
    echo "  set_extrabootargs_and_bootcmdline <cmdline> <bootargs>"
    echo "  clear_extrabootargs_and_bootcmdline"
    echo "  show_boot_config"
    echo ""
    echo "Example:"
    echo "  source bmc_set_extra_params.sh"
    echo "  if set_extrabootargs_and_bootcmdline \"i2c dev 4\" \"blacklist=mp2995\"; then"
    echo "      reboot_bmc"
    echo "  fi"
fi
