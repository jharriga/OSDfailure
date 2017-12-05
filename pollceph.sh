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
#pgcount=`grep pools /tmp/ceph.status |awk '{print $4}'`
#pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $2}'`
#percent=$((200*$pgclean/$pgcount % 2 + 100*$pgclean/$pgcount))
#updatelog "pgcnt=${pgcount}; pgclean=${pgclean}; percent=${percent}" $log
#while [ $pgclean -lt $pgcount ] ; do
until grep HEALTH_OK /tmp/ceph.status; do
    cleanPG_cnt=`grep -o '[0-9]\{1,\} active+clean' /tmp/ceph.status`
    totPG_cnt=`grep pools /tmp/ceph.status |awk '{print $4}'`
    uncleanPG_cnt=`grep -o '[0-9]\{1,\} pgs unclean' /tmp/ceph.status |awk '{print $1}'`
    updatelog "Total PGs ${totPG_cnt} : unclean PGs ${uncleanPG_cnt}" $log
    sleep "${interval}"
    ssh "root@${mon}" ceph status > /tmp/ceph.status
#    pgcount=`grep pgmap /tmp/ceph.status |awk '{print $3}'`
#    pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $1}'`
#    pgcount=`grep pools /tmp/ceph.status |awk '{print $4}'`
#    pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $2}'`
#    percent=$((200*$pgclean/$pgcount % 2 + 100*$pgclean/$pgcount))
#    updatelog "pgcnt=${pgcount}; pgclean=${pgclean}; percent=${percent}" $log
done
updatelog "** Recovery completed: HEALTH_OK - POLLCEPH ending" $log
echo " " | mail -s "POLLCEPH completed: HEALTH_OK" jharriga@redhat.com ekaynar@redhat.com
