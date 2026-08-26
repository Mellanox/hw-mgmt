#!/bin/sh

# Usage:
#   max1363_force_alarm.sh <bus> <addr> <channels>
#
# Examples:
#   max1363_force_alarm.sh 12 0x34 all
#   max1363_force_alarm.sh 12 0x34 1,2
#
# WARNING: the CTRL byte (bit7=1) lands in the setup register and changes the
# ADC reference, railing conversions to full scale. Run a2d_leakage_config.sh
# afterwards to restore SetupRegVal and the monitor stream.

BUS="$1"
ADDR="$2"
CHS="$3"

if [ -z "$BUS" ] || [ -z "$ADDR" ] || [ -z "$CHS" ]; then
    echo "Usage: $0 <bus> <i2c_addr> <channels>"
    echo "Channels: 0,1,2,3 | 0 | 1,3 | all"
    exit 1
fi

# Default thresholds (tight window → alarm)
LT_MSB=0x00
LT_UT=0x10
UT_LSB=0x20

# Safe thresholds (won't alarm)
SAFE_LTM=0x00
SAFE_LTUT=0x00
SAFE_UTL=0xFF

CTRL=0xF6   # Reset alarms, 2ksps, INT enable

# Build threshold block per channel
build_ch()
{
    case "$1" in
        alarm)
            echo "$LT_MSB $LT_UT $UT_LSB"
            ;;
        safe)
            echo "$SAFE_LTM $SAFE_LTUT $SAFE_UTL"
            ;;
    esac
}

CH0="safe"
CH1="safe"
CH2="safe"
CH3="safe"

if [ "$CHS" = "all" ]; then
    CH0=alarm; CH1=alarm; CH2=alarm; CH3=alarm
else
    for c in $(echo "$CHS" | tr ',' ' '); do
        case "$c" in
            0) CH0=alarm ;;
            1) CH1=alarm ;;
            2) CH2=alarm ;;
            3) CH3=alarm ;;
            *)
                echo "Invalid channel: $c"
                exit 1
                ;;
        esac
    done
fi

i2ctransfer -f -y "$BUS" w14@"$ADDR" \
  0x01 \
  "$CTRL" \
  $(build_ch "$CH0") \
  $(build_ch "$CH1") \
  $(build_ch "$CH2") \
  $(build_ch "$CH3")

echo "Forced alarm configured"
echo "Bus=$BUS Addr=$ADDR Channels=$CHS"

