#!/bin/bash
# dropOSD.bash   script to drop an OSD device

# FUNCTIONS
function error_exit {
# Function for exit due to fatal program error
# Accepts 1 argument:
#   string containing descriptive error message
# Copied from - http://linuxcommand.org/wss0150.php
    echo "${PROGNAME}: ${1:-"Unknown Error"} ABORTING..." 1>&2
    exit 1
}

function logit {
# Echoes passed string to LOGFILE and stdout
    logfn=$2

    echo `$DATE`": $1" 2>&1 | tee -a $logfn
}

# Name of the program being run
PROGNAME=$(basename $0)
uuid=`uuidgen`
DATE='date +%Y/%m/%d:%H:%M:%S'

# check for passed arguments
[ $# -ne 2 ] && error_exit "dropOSD failed - wrong number of args"
[ -z "$1" ] && error_exit "dropOSD failed - empty first arg"
[ -z "$2" ] && error_exit "dropOSD failed - empty second arg"

# Get the passed vars
failtime=$1
log=$2
touch $log           # start the logfile

#--------------------------------------------------------------
# Get target OSD info before stopping
osdID=`df |grep ceph- |awk '{print $6}' |cut -d- -f2|sort -h|tail -1`
osdPART=`df |grep ceph-${osdID} |awk '{print $1}'`
osdDEV=`ceph-disk list |grep "\bosd.$osdID\b" | awk '{print $1}'|tr -d '[0-9]'`
logit "osdID= $osdID   osdDEV= $osdDEV  osdPART= $osdPART" $log

# Determine if cluster is Bluestore or Filestore
ostore=`ceph osd metadata $osdID | grep osd_objectstore | awk '{print $2}'`
case "$ostore" in
    *filestore*) 
        osdTYPE="filestore"
        FSjournal=`ls -l /var/lib/ceph/osd/ceph-${osdID}/journal | cut -d\> -f2`
        FSweight=`ceph osd tree | grep "osd.${osdID} "|awk '{print $3}'`
        logit "FSjournal= $FSjournal   FSweight= $FSweight" $log
        prepareCMD="ceph-disk prepare --filestore --osd-id $osdID $osdDEV $FSjournal"
        ;;
    *bluestore*)
        osdTYPE="bluestore"
        BSdb=`ceph-disk list |grep "\bosd.$osdID\b" | awk '{print substr($11, 1, length($11) - 1)}'`
        BSwal=`ceph-disk list |grep "\bosd.$osdID\b" | awk '{print $13}'`
        logit "BSdb= $BSdb   BSwal= $BSwal" $log
        prepareCMD="ceph-disk prepare --bluestore --osd-id $osdID --block.db $BSdb --block.wal $BSwal $osdDEV"
        ;;
    *)
        error_exit "dropOSD: Cluster metadata check failed."
        ;;
esac

logit "Cluster type is: $osdTYPE" $log

# Issue the OSD stop cmd
if systemctl stop ceph-osd@${osdID}; then
    logit "dropOSD: stopped OSD ${osdID}" $log
else
    error_exit "dropOSD: failed to stop OSD ${osdID}"
fi
# Wait for failuretime
sleep "${failtime}"

# ADMIN steps to address dropped OSD device event
#   - remove dropped OSD and prepare for re-use
logit "Removing dropped OSD and preparing for re-use" $log
ceph osd out osd.$osdID                         # mark the OSD out
umount -f /var/lib/ceph/osd/ceph-$osdID         # unmount it
ceph-disk zap $osdDEV                           # zap it - removes partitions
ceph osd destroy $osdID --yes-i-really-mean-it  # destroy so ID can be re-used

#   - create new OSD, based on $osdTYPE
logit "Issuing prepare command: $prepareCMD" $log
eval $prepareCMD
# now activate
ceph-disk activate $osdPART
logit "dropOSD: prepared and activated new OSD" $log

# Start the new OSD
systemctl start ceph-osd@${osdID}
if [[ `systemctl status ceph-osd@${osdID} |grep Active:|grep running` ]] ; then
    logit "dropOSD: started new OSD ${osdID}" $log
else
    error_exit "ceph-osd@${osdID}.service failed to start"
fi

# END
