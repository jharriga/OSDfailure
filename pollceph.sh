#!/bin/bash
#
# POLLCEPH.sh
#   Polls ceph for 'active&clean' status
#

# Bring in other script files
myPath="${BASH_SOURCE%/*}"
if [[ ! -d "$myPath" ]]; then
    myPath="$PWD"
fi

# Functions
source "$myPath/functions.shinc"

# check arguments
[ $# -ne 2 ] && error_exit "POLLCEPH.sh failed - wrong number of args"
[ -z "$1" ] && error_exit "POLLCEPH.sh failed - empty first arg"
[ -z "$2" ] && error_exit "POLLCEPH.sh failed - empty second arg"

#pollinterval=$1

# update log file with ceph recovery progress
updatelog "** POLLCEPH started"
ceph status > /tmp/ceph.status
pgcount=`grep pgmap /tmp/ceph.status |awk '{print $3}'`
pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $1}'`
updatelog "pgcnt=${pgcount}; pgclean=${pgclean}; percent=${percent}"
while [ $pgcount -ne $pgclean ] ; do
    sleep "${pollinterval}"
    ceph status > /tmp/ceph.status
    pgcount=`grep pgmap /tmp/ceph.status |awk '{print $3}'`
    pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $1}'`
    percent=$((200*$pgclean/$pgcount % 2 + 100*$pgclean/$pgcount))
    updatelog "pgcnt=${pgcount}; pgclean=${pgclean}; percent=${percent}"
done
updatelog "** Recovery completed - POLLCEPH ending"
echo " " | mail -s "POLLCEPH completed" ekaynar@redhat.com jharriga@redhat.com


