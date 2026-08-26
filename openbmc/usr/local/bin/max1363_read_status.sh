#!/bin/sh

# Usage:
#   max1363_read_status.sh <bus> <addr>
# Example:
#   max1363_read_status.sh 12 0x34

BUS="$1"
ADDR="$2"

if [ -z "$BUS" ] || [ -z "$ADDR" ]; then
    echo "Usage: $0 <bus> <i2c_addr>"
    exit 1
fi

DATA=$(i2ctransfer -f -y "$BUS" r2@"$ADDR")

B0=$(echo "$DATA" | awk '{print $1}')
B1=$(echo "$DATA" | awk '{print $2}')

STATUS=$((B0))
VALUE=$(( (B0 & 0x0F) << 8 | B1 ))

echo "I2C bus     : $BUS"
echo "I2C address : $ADDR"
echo "Raw bytes   : $B0 $B1"
echo "ADC value   : $VALUE"
echo "Status:"

[ $((STATUS & 0x80)) -ne 0 ] && echo "  Alarm active"
[ $((STATUS & 0x40)) -ne 0 ] && echo "  Channel 3 alarm"
[ $((STATUS & 0x20)) -ne 0 ] && echo "  Channel 2 alarm"
[ $((STATUS & 0x10)) -ne 0 ] && echo "  Channel 1 alarm"
[ $((STATUS & 0x08)) -ne 0 ] && echo "  Channel 0 alarm"


