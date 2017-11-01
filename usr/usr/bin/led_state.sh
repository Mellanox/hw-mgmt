#!/bin/bash
#set -x

PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

tmp=$0
LED_STATE=none
FNAME=$(basename "$tmp")
DNAME=$(dirname "$tmp")
LED_NAME=`echo $FNAME | cut -d_ -f1-2`
FNAMES=(`ls "$DNAME"/"$LED_NAME"*`)

check_led_blink()
{
	val1=`cat "$DNAME"/"$LED_NAME"_"$COLOR"_delay_on`
	val2=`cat "$DNAME"/"$LED_NAME"_"$COLOR"_delay_off`
	val3=`cat "$DNAME"/"$LED_NAME"_"$COLOR"`
	if [ "${val1}" != "0" ] && [ "${val2}" != "0" ] && [ "${val3}" != "0" ] ; then
		LED_STATE="$COLOR"_blink
		return 1
	fi
	return 0		
}

for CURR_FILE in "${FNAMES[@]}"
do
	if echo "$CURR_FILE" | (grep -q '_state\|_capability') ; then
		continue
	fi
	COLOR=`echo $CURR_FILE | cut -d_ -f3`
	if [ -z "${COLOR}" ] ; then
		continue
	fi
	if echo "$CURR_FILE" | grep -q "_delay" ; then	
		check_led_blink $COLOR
		if [ $? -eq 1 ]; then
			break;
		fi
	fi
	if [ "${CURR_FILE}" == "$DNAME"/"${LED_NAME}_${COLOR}" ] ; then 
		val1=`cat "$DNAME"/"$LED_NAME"_"$COLOR"`
		if [ "${val1}" != "0" ]; then
			check_led_blink $COLOR
			if [ $? -eq 1 ]; then
				break;
			else
				LED_STATE="$COLOR"
				break;
			fi
		fi
	fi
done

echo ${LED_STATE} > "$DNAME"/"$LED_NAME"
exit 0

