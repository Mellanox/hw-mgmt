#
# Copyright (C) 2010-2015, Mellanox Technologies Ltd.  ALL RIGHTS RESERVED.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
#
#

#!/bin/bash
#

### BEGIN INIT INFO
# Provides:          start of thermal control algorithm script thermal_watch.sh
# Short-Description: activation of basic thermal control algorithm system for Mellanox TOR systems
### END INIT INFO

. /lib/lsb/init-functions

if [ -f /usr/sbin/thermal_watch.sh ]; then
    /usr/sbin/thermal_watch.sh $1 $2 &
fi
