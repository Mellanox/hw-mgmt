#!/bin/sh

# ADS7924: force the window comparator so selected channels assert the alarm
# (debug). Register map: TI SBAS482.
#
# Usage:
#   ads7924_force_alarm.sh <bus> <addr> <channels>
#
# Examples:
#   ads7924_force_alarm.sh 49 0x48 all
#   ads7924_force_alarm.sh 49 0x48 0,1

BUS="$1"
ADDR="$2"
CHS="$3"

if [ -z "$BUS" ] || [ -z "$ADDR" ] || [ -z "$CHS" ]; then
    echo "Usage: $0 <bus> <i2c_addr> <channels>"
    echo "Channels: 0,1,2,3 | 0 | 1,3 | all"
    exit 1
fi

# Inverted window (ULR < LLR) forces an alarm for any conversion result.
ALARM_UL=0x00
ALARM_LL=0xff

# Wide-open window never alarms.
SAFE_UL=0xff
SAFE_LL=0x00

INTCONFIG=0xe0   # active-low, level, ICNT=7 (same as leakage config default)
AWAKE=0x80       # MODECNTRL AWAKE
MODE=0xcc        # MODECNTRL Auto-Scan (MODE field in MODECNTRL bits[7:2])

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

# Upper/lower limit byte for a channel mode.
ul_byte()
{
    case "$1" in
        alarm) printf '%s' "$ALARM_UL" ;;
        safe)  printf '%s' "$SAFE_UL" ;;
    esac
}
ll_byte()
{
    case "$1" in
        alarm) printf '%s' "$ALARM_LL" ;;
        safe)  printf '%s' "$SAFE_LL" ;;
    esac
}

# Fail-fast I2C write: a failed programming transfer aborts so a partial config
# never reaches the "Forced alarm configured" success message.
xfer()
{
    if ! i2ctransfer -f -y "$BUS" "$@" >/dev/null 2>&1; then
        echo "ADS7924 I2C transfer failed: $* (bus $BUS addr $ADDR)" >&2
        exit 1
    fi
}

# IDLE before reprogramming the window.
xfer w2@"$ADDR" 0x00 0x00
sleep 0.02

# ULR/LLR burst (auto-increment pointer 0x8a): ULR0 LLR0 .. ULR3 LLR3.
xfer w9@"$ADDR" 0x8a \
    "$(ul_byte "$CH0")" "$(ll_byte "$CH0")" \
    "$(ul_byte "$CH1")" "$(ll_byte "$CH1")" \
    "$(ul_byte "$CH2")" "$(ll_byte "$CH2")" \
    "$(ul_byte "$CH3")" "$(ll_byte "$CH3")"

# INTCONFIG, enable all alarms, then AWAKE + run mode.
xfer w2@"$ADDR" 0x12 "$INTCONFIG"
xfer w2@"$ADDR" 0x01 0x0f
# Clear any stale alarm interrupt before starting the scan (read INTCONFIG 0x12).
i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x12 r1 >/dev/null 2>&1 || true
xfer w2@"$ADDR" 0x00 "$AWAKE"
sleep 0.002
xfer w2@"$ADDR" 0x00 "$MODE"

echo "Forced alarm configured"
echo "Bus=$BUS Addr=$ADDR Channels=$CHS"
