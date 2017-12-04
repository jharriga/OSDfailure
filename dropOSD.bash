#!/bin/sh

# Bring in other script files
myPath="${BASH_SOURCE%/*}"
if [[ ! -d "$myPath" ]]; then
    myPath="$PWD"
fi

# Functions
source "$myPath/functions.shinc"

#
# Get target OSD info before stopping
origOSD=`df |grep ceph- |awk '{print $6}' |cut -d- -f2|sort -h|tail -1`
dev=`df |grep ceph-${origOSD} |awk '{print $1}'`
weight=`ceph osd tree|grep "osd.${origOSD} "|awk '{print $2}'`
journal=`ls -l /var/lib/ceph/osd/ceph-${origOSD}/journal | cut -d\> -f2`

# Issue the OSD stop cmd
if systemctl stop ceph-osd@${origOSD}; then
    updatelog "** stopped OSD ${origOSD}"
else
    error_exit "failed to stop OSD ${origOSD}"
fi
# Wait for failuretime
sleep "${failuretime}"
# Perform ADMIN steps to address dropped OSD event
newOSD=$(restore_OSD "${origOSD}" "${dev}" "${weight}" "${journal}")
if [[ ! $newOSD ]]; then
  error_exit "function restore_OSD did not return valid osd"
fi
# Start the new OSD
systemctl start ceph-osd@${newOSD}
if [[ `systemctl status ceph-osd@${newOSD} |grep Active:|grep running` ]] ; then
  updatelog "** started new OSD ${newOSD}"
else
  error_exit "ceph-osd@${newOSD}.service failed to start"
fi
# END
