#!/bin/bash

PLAT_KEXEC_NOTIFY=/var/run/hw-management/system/kexec_activated

if [ "$1" = "kexec" ] && [ -f ${PLAT_KEXEC_NOTIFY} ]; then
        echo 1 > ${PLAT_KEXEC_NOTIFY}
fi

