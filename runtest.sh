#!/bin/bash
#
# RUNTEST.sh
#   Executes the COSbench workloads and injects failures at specific
#   time periods
#
#   Ensure the testpool is available and 50% full
#   Start COSbench workload and sleep for 'jobtime' minutes
#   Stop OSD device and leave it down for 'failuretime' minutes
#     - poll and record ceph status every 'polltime' minutes
#   Add the OSD back into cluster and wait for 'recoverytime'
#     - poll and record ceph status every 'polltime' minutes
#   Stop OSD node and leave it down for 'failuretime' minutes
#     - poll and record ceph status every 'polltime' minutes
#   Add the OSD node back into cluster and wait for 'recoverytime'
#     - poll and record ceph status every 'polltime' minutes
#   Stop COSbench workload
#   Delete the testpool to accelerate recovery
#   Wait for recovery and record timestamp for ('active&clean')
#
#   Proposed variable settings:
#     - jobtime = 60 min
#     - failuretime = 10 min
#     - recoverytime = 60 min
#     - polltime = 1 min
#####################################################################

# Bring in other script files
myPath="${BASH_SOURCE%/*}"
if [[ ! -d "$myPath" ]]; then
    myPath="$PWD" 
fi

# Variables
source "$myPath/vars.shinc"

# Functions
source "$myPath/functions.shinc"

#--------------------------------------
# Housekeeping
#
# Check dependencies are met
chk_dependencies

# Create log file - named in vars.shinc
if [ ! -d $RESULTSDIR ]; then
  mkdir -p $RESULTSDIR || \
    error_exit "$LINENO: Unable to create RESULTSDIR."
fi
touch $LOGFILE || error_exit "$LINENO: Unable to create LOGFILE."
updatelog "${PROGNAME} - Created logfile: $LOGFILE"

# Verify that the OSDnode is reachable via ansible
ansible all -m ping -i '${OSDhostname},'

#
# END: Housekeeping
#--------------------------------------

# Start the COSbench workload
pbench-user-benchmark cosbench "${XMLworkload}" & #### MODIFY to match Ugur's cmdline
PIDpbench=$!
updatelog "** pbench-user-benchmark cosbench started as PID: ${PIDpbench}" 
# VERIFY it successfully started
sleep 5s
if ps -p $PIDpbench > /dev/null; then
    updatelog "SLEEPING ${jobtime} for non-failure cosbench"
    sleep "${jobtime}" 
else
    error_exit "pbench-user-benchmark cosbench FAILED"
fi
updatelog "COMPLETED sleeping for non-failure cosbench"

# Poll ceph status (in a bkrgd process) 
./pollceph.sh "${pollinterval}" "${LOGFILE}" &
PIDpollceph1=$!
# VERIFY it successfully started
sleep 1s
if ! ps -p $PIDpollceph1 > /dev/null; then
    error_exit "First pollceph.sh FAILED"
fi

#---------------------------------------
# BEGIN the OSD device failure sequence
# invoke OSD device failure with ansible
ansible-playbook "${PLAYBOOKosddevfail}"

#######################
# TURN THIS INTO ANSIBLE PLAYBOOK
# Get target OSD info before stopping
origOSD=`df |grep ceph- |awk '{print $6}' |cut -d- -f2|sort -h|tail -1`
dev=`df |grep ceph-${origOSD} |awk '{print $1}'`
weight=`ceph osd tree|grep "osd.${origOSD} "|awk '{print $2}'`
journal=`ls -l /var/lib/ceph/osd/ceph-${origOSD}/journal | cut -d\> -f2`

# START>>>> ANSIBLE PLAYBOOK---
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
# END<<<< ANSIBLE PLAYBOOK---

# Let things run for 'recoverytime'
updatelog "OSDevice: sleeping ${recoverytime} to monitor cluster re-patriation activity"
sleep "${recoverytime}"

# Now kill off the POLLCEPH background process
kill $PIDpollceph1
updatelog "Waited for ${recoverytime} and stopped POLLCEPH bkgrd process"
# END - OSD device failure sequence
#--------------------------------------

######---------------------------------
# The 'OSD node' failure sequence
#
# Poll ceph status (in a bkrgd process) 
./pollceph.sh "${pollinterval}" "${LOGFILE}" &
PIDpollceph2=$!
# VERIFY it successfully started
sleep 1s
if ! ps -p $PIDpollceph2 > /dev/null; then
    error_exit "Second pollceph.sh FAILED"
fi
# invoke OSD node failure with ansible
ansible-playbook "${PLAYBOOKosdnodefail}"

# Let things run for 'recoverytime'
updatelog "OSDnode: sleeping ${recoverytime} to monitor cluster re-patriation activity"
sleep "${recoverytime}"

# Now kill off the background processes: POLLceph and PBENCH-COSbench
kill $PIDpollceph2
kill $PIDpbench
updatelog "Waited for ${recoverytime} and stopped bkgrd processes"
#####-----------------------

##################################
# END of I/O workload and monitoring
# However we want a stable cluster so wait for recovery to complete
updatelog "** START: Waiting for all active+clean pgs" 
ceph status > /tmp/ceph.status
pgcount=`grep pgmap /tmp/ceph.status |awk '{print $3}'`
pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $1}'`
while [ $pgcount -ne $pgclean ] ; do
  sleep 1m
  ceph status > /tmp/ceph.status
  pgcount=`grep pgmap /tmp/ceph.status |awk '{print $3}'`
  pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $1}'`
done
updatelog "** END: Recovery complete"
echo " " | mail -s "ceph recovery complete" ekaynar@redhat.com jharriga@redhat.com



