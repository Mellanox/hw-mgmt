#!/bin/sh

# ADS7924: read mode / alarm / data / window registers via i2ctransfer (debug).
# Register map: TI SBAS482.
#
# Usage:
#   ads7924_read_status.sh <bus> <addr>
# Example:
#   ads7924_read_status.sh 49 0x48

BUS="$1"
ADDR="$2"

if [ -z "$BUS" ] || [ -z "$ADDR" ]; then
    echo "Usage: $0 <bus> <i2c_addr>"
    exit 1
fi

# Single-byte registers.
MODE=$(i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x00 r1 2>/dev/null)
INTCNTRL=$(i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x01 r1 2>/dev/null)
INTCONFIG=$(i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x12 r1 2>/dev/null)

# Burst reads with auto-increment (pointer bit 7): DATA0_U.. (0x82) and ULR0.. (0x8a).
DATA=$(i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x82 r8 2>/dev/null)
LIMITS=$(i2ctransfer -f -y "$BUS" w1@"$ADDR" 0x8a r8 2>/dev/null)

if [ -z "$MODE" ] || [ -z "$INTCNTRL" ] || [ -z "$DATA" ]; then
    echo "Failed to read ADS7924 registers on bus $BUS addr $ADDR"
    exit 1
fi

M=$((MODE))
IC=$((INTCNTRL))
ICFG=$((INTCONFIG))

echo "I2C bus       : $BUS"
echo "I2C address   : $ADDR"
echo ""
echo "MODECNTRL (0x00) : $MODE"
echo "  MODE [7:2]     : $(( (M >> 2) & 0x3f ))  (0x0c=Auto-Scan, 0x0e=Auto-Scan+Sleep)"
echo "  SEL  [1:0]     : $(( M & 0x03 ))"
echo ""
echo "INTCNTRL (0x01)  : $INTCNTRL"
echo "  Alarm flags [7:4] (AF3..AF0):"
[ $((IC & 0x80)) -ne 0 ] && echo "    Channel 3 alarm"
[ $((IC & 0x40)) -ne 0 ] && echo "    Channel 2 alarm"
[ $((IC & 0x20)) -ne 0 ] && echo "    Channel 1 alarm"
[ $((IC & 0x10)) -ne 0 ] && echo "    Channel 0 alarm"
echo "  Alarm enable [3:0] : 0x$(printf '%x' $((IC & 0x0f)))"
echo ""
echo "INTCONFIG (0x12) : ${INTCONFIG:-n/a}"
if [ -n "$INTCONFIG" ]; then
    echo "  ICNT [7:5]     : $(( (ICFG >> 5) & 0x07 ))  (alarms before INT)"
    echo "  INTPOL (bit 1) : $(( (ICFG >> 1) & 1 ))  (0=active low)"
    echo "  INTTRIG (bit 0): $(( ICFG & 1 ))  (0=level, 1=edge)"
fi
echo ""

# DATAx burst must be 8 bytes (4 channels x U/L); a short read would decode garbage.
set -- $DATA
if [ $# -ne 8 ]; then
    echo "Short ADS7924 DATA burst ($# bytes, expected 8) on bus $BUS addr $ADDR"
    exit 1
fi

# 12-bit conversion codes: DATAx_U carries data[11:4], DATAx_L carries data[3:0] in bits 7:4.
CH=0
for pair in "1 2" "3 4" "5 6" "7 8"; do
    U=$(echo "$DATA" | awk -v i="${pair% *}" '{print $i}')
    L=$(echo "$DATA" | awk -v i="${pair#* }" '{print $i}')
    CODE=$(( (U << 4) | (L >> 4) ))
    echo "  DATA ch$CH (0x0$((2 + CH * 2))) : U=$U L=$L  code=$CODE"
    CH=$((CH + 1))
done
echo ""

# ULR/LLR window burst is also 8 bytes; skip decoding a short/failed read.
set -- $LIMITS
if [ $# -eq 8 ]; then
    CH=0
    for pair in "1 2" "3 4" "5 6" "7 8"; do
        UL=$(echo "$LIMITS" | awk -v i="${pair% *}" '{print $i}')
        LL=$(echo "$LIMITS" | awk -v i="${pair#* }" '{print $i}')
        echo "  Window ch$CH : ULR=$UL LLR=$LL"
        CH=$((CH + 1))
    done
fi
