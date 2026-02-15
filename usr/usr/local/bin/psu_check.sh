#!/bin/bash
CONFIG_FILE="/var/run/hw-management/config/hotplug_psus"
PSU_DIR="/var/run/hw-management/eeprom"
DONE_FILE="$PSU_DIR/psu_done"
REQUIRED_COUNT=$(cat "$CONFIG_FILE" | tr -d '[:space:]')
CURRENT_COUNT=$(ls "$PSU_DIR" | grep -o 'psu[0-9]\+' | sort -u | wc -l)
if [ "$CURRENT_COUNT" -eq "$REQUIRED_COUNT" ]; then
	echo "Status: OK ($CURRENT_COUNT/$REQUIRED_COUNT). Ensuring psu_done exists."
	if [ ! -f "$DONE_FILE" ]; then
		touch "$DONE_FILE"
		logger "PSU_CHECK: Created $DONE_FILE"
	fi
else
	echo "Status: MISMATCH ($CURRENT_COUNT/$REQUIRED_COUNT). Removing psu_done."
	if [ -f "$DONE_FILE" ]; then
		rm "$DONE_FILE"
		logger "PSU_CHECK: Removed $DONE_FILE"
	fi
fi
