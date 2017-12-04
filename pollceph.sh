#!/bin/bash
#
# POLLCEPH.sh
#   Polls ceph for 'active&clean' status
#

# Functions
function logit {
# Echoes passed string to LOGFILE and stdout
    echo `$DATE`": $1" 2>&1 | tee -a $2
}

function error_exit {
# Function for exit due to fatal program error
# Accepts 1 argument:
#   string containing descriptive error message
# Copied from - http://linuxcommand.org/wss0150.php
    echo "${PROGNAME}: ${1:-"Unknown Error"} ABORTING..." 1>&2
    exit 1
}

# check for passed arguments
[ $# -ne 3 ] && error_exit "POLLCEPH.sh failed - wrong number of args"
[ -z "$1" ] && error_exit "POLLCEPH.sh failed - empty first arg"
[ -z "$2" ] && error_exit "POLLCEPH.sh failed - empty second arg"
[ -z "$3" ] && error_exit "POLLCEPH.sh failed - empty third arg"

interval=$1
log=$2
mon=$3
DATE='date +%Y/%m/%d:%H:%M:%S'

# update log file with ceph recovery progress
logit "** POLLCEPH started" $log
ssh "root@${mon}" ceph status > /tmp/ceph.status
#pgcount=`grep pgmap /tmp/ceph.status |awk '{print $3}'`
#pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $1}'`
pgcount=`grep pools /tmp/ceph.status |awk '{print $4}'`
pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $2}'`
percent=$((200*$pgclean/$pgcount % 2 + 100*$pgclean/$pgcount))
logit "pgcnt=${pgcount}; pgclean=${pgclean}; percent=${percent}" $log
while [ $pgclean -lt $pgcount ] ; do
    sleep "${interval}"
    ssh "root@${mon}" ceph status > /tmp/ceph.status
#    pgcount=`grep pgmap /tmp/ceph.status |awk '{print $3}'`
#    pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $1}'`
    pgcount=`grep pools /tmp/ceph.status |awk '{print $4}'`
    pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $2}'`
    percent=$((200*$pgclean/$pgcount % 2 + 100*$pgclean/$pgcount))
    logit "pgcnt=${pgcount}; pgclean=${pgclean}; percent=${percent}" $log
done
logit "** Recovery completed - POLLCEPH ending" $log
echo " " | mail -s "POLLCEPH completed" jharriga@redhat.com






