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

function updatelog {
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

#
# Get target OSD info before stopping
origOSD=`df |grep ceph- |awk '{print $6}' |cut -d- -f2|sort -h|tail -1`
dev=`df |grep ceph-${origOSD} |awk '{print $1}'`
weight=`ceph osd tree|grep "osd.${origOSD} "|awk '{print $2}'`
journal=`ls -l /var/lib/ceph/osd/ceph-${origOSD}/journal | cut -d\> -f2`

# Issue the OSD stop cmd
if systemctl stop ceph-osd@${origOSD}; then
    updatelog "dropOSD: stopped OSD ${origOSD}" $log
else
    error_exit "dropOSD: failed to stop OSD ${origOSD}"
fi
# Wait for failuretime
sleep "${failtime}"

# ADMIN steps to address dropped OSD event
#   - remove dropped OSD
ceph osd out osd.${origOSD}
ceph osd crush remove osd.${origOSD}
ceph auth del osd.${origOSD}
ceph osd rm osd.${origOSD} ; sleep 5
umount -f /var/lib/ceph/osd/ceph-${origOSD}

#   - create new OSD
newOSD=`ceph osd create ${uuid} ${origOSD}` ; sleep 5
if [[ ! "${newOSD}" ]]; then
    error_exit "dropOSD: Failed to create OSD"
fi
updatelog "dropOSD: created osd.${newOSD}" $log
mkdir /var/lib/ceph/osd/ceph-${newOSD} &> /dev/null
mount -o noatime ${dev} /var/lib/ceph/osd/ceph-${newOSD}
updatelog "dropOSD: removing prior contents of ${dev}" $log
rm -rf /var/lib/ceph/osd/ceph-${newOSD}/*
ceph-osd -i ${newOSD} --mkfs --mkkey --osd-uuid ${uuid} ; sleep 5

#   - add new OSD
ceph auth add osd.${newOSD} mon 'allow *' osd 'allow profile osd' -i /var/lib/ceph/osd/ceph-${newOSD}/keyring
ceph osd crush add ${newOSD} ${weight} host=`hostname -s`

# if original journal was softlink, recreate it
if [[ $journal ]] ; then
    updatelog "dropOSD: setting journal to original softlink" $log
    ceph-osd -i ${newOSD} --flush-journal
    rm -f /var/lib/ceph/osd/ceph-${newOSD}/journal
    ln -s ${journal} /var/lib/ceph/osd/ceph-${osd}/journal
    ceph-osd -i ${newOSD} --mkjournal
fi
chown -R ceph:ceph /var/lib/ceph/osd/ceph-${newOSD}

# Start the new OSD
systemctl start ceph-osd@${newOSD}
if [[ `systemctl status ceph-osd@${newOSD} |grep Active:|grep running` ]] ; then
    updatelog "dropOSD: started new OSD ${newOSD}" $log
else
    error_exit "ceph-osd@${newOSD}.service failed to start"
fi
# END


