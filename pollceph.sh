#!/bin/bash
#
# POLLCEPH.sh
#   Polls ceph and logs stats until cleanPGS == totPGs
#

# Bring in other script files
myPath="${BASH_SOURCE%/*}"
if [[ ! -d "$myPath" ]]; then
    myPath="$PWD"
fi

# Variables
source "$myPath/vars.shinc"

# Functions
source "$myPath/functions.shinc"

# check for passed arguments
[ $# -ne 3 ] && error_exit "POLLCEPH.sh failed - wrong number of args"
[ -z "$1" ] && error_exit "POLLCEPH.sh failed - empty first arg"
[ -z "$2" ] && error_exit "POLLCEPH.sh failed - empty second arg"
[ -z "$3" ] && error_exit "POLLCEPH.sh failed - empty third arg"

interval=$1          # how long to sleep between polling
log=$2               # the logfile to write to
mon=$3               # the MON to run 'ceph status' cmd on
DATE='date +%Y/%m/%d:%H:%M:%S'

# update log file with ceph recovery progress
updatelog "** POLLCEPH started" $log
ssh "root@${mon}" ceph status > /tmp/ceph.status

#until grep HEALTH_OK /tmp/ceph.status; do
# since scrubbing has been disabled, cluster reports HEALTH_WARN status
while grep HEALTH_WARN /tmp/ceph.status; do
    totPG_cnt=`grep -o '[0-9]\{1,\} pools, [0-9]\{1,\} pgs' /tmp/ceph.status | \
      awk '{print $3}'`
    cleanPG_cnt=`grep -o '[0-9]\{1,\} active+clean' /tmp/ceph.status | \
      awk '{print $1}'`
    # Test that all PGs are clean - if so exit the while loop
    if [ "$cleanPG_cnt" -eq "$totPG_cnt" ]; then
        break;
    fi
    uncleanPG_cnt=`grep -o '[0-9]\{1,\} pgs unclean' /tmp/ceph.status | \
      awk '{print $1}'`
    updatelog "Total PGs ${totPG_cnt} : unclean PGs ${uncleanPG_cnt}" $log
    sleep "${interval}"
    ssh "root@${mon}" ceph status > /tmp/ceph.status
done

updatelog "** Recovery completed: POLLCEPH ending" $log
echo " " | mail -s "POLLCEPH completed" jharriga@redhat.com ekaynar@redhat.com
