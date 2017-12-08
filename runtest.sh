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
updatelog "${PROGNAME} - Created logfile: $LOGFILE" $LOGFILE

# Verify that the OSDnode & MONnode are reachable via ansible
##ansible all -m ping -i '${OSDhostname},'
host1=`ssh "root@${OSDhostname}" hostname`
updatelog "> OSDhost is ${OSDhostname} : ${host1}" $LOGFILE
host2=`ssh "root@${MONhostname}" hostname`
updatelog "> MONhost is ${MONhostname} : ${host2}" $LOGFILE

#
# END: Housekeeping
#--------------------------------------

# Start the COSbench workload
#pbench-user-benchmark cosbench "${XMLworkload}" & #### MODIFY to match Ugur's cmdline
sleep 100m &           ## DEBUG
PIDpbench=$!
updatelog "** pbench-user-benchmark cosbench started as PID: ${PIDpbench}" $LOGFILE
# VERIFY it successfully started
sleep 5s
if ps -p $PIDpbench > /dev/null; then
    updatelog "BEGIN: No Failures - start sleeping ${jobtime}" $LOGFILE
    sleep "${jobtime}" 
else
    error_exit "pbench-user-benchmark cosbench FAILED"
fi
updatelog "END: No Failures - completed sleeping" $LOGFILE

#---------------------------------------
# BEGIN the OSD device failure sequence
#   could invoke OSD device failure with ansible
##ansible-playbook "${PLAYBOOKosddevfail}"

# set the remote logfile name
logbase=$(basename $LOGFILE)
logtmp="/tmp/${logbase}"
## Drop the OSDdevice using SSH
ssh "root@${OSDhostname}" "bash -s" < dropOSD.bash "${failuretime}" "${logtmp}"
# bring the remote logfile back and append to LOGFILE
scp -q "root@${OSDhostname}:${logtmp}" "${logtmp}"
cat "${logtmp}" >> $LOGFILE
rm -f "${logtmp}"

# Disable scrubbing - per RHCS ADMIN Guide
ceph osd set noscrub
ceph osd set nodeep-scrub

# Poll ceph status (in a bkrgd process) 
./pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}" &
PIDpollceph1=$!
# VERIFY it successfully started
sleep 1s
if ! ps -p $PIDpollceph1 > /dev/null; then
    error_exit "First pollceph.sh FAILED."
fi

# Let things run for 'recoverytime'
updatelog "BEGIN: OSDdevice - sleeping ${recoverytime} to monitor cluster re-patriation" $LOGFILE
sleep "${recoverytime}"

# Now kill off the POLLCEPH background process
kill $PIDpollceph1
updatelog "END: OSDdevice - Completed. Stopped POLLCEPH bkgrd process" $LOGFILE
# END - OSD device failure sequence
#--------------------------------------

######---------------------------------
# The 'OSD node' failure sequence
# scrubbing is already disabled
#
# Poll ceph status (in a bkrgd process) 
./pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}" &
PIDpollceph2=$!
# VERIFY it successfully started
sleep 1s
if ! ps -p $PIDpollceph2 > /dev/null; then
    error_exit "Second pollceph.sh FAILED."
fi
# invoke OSD node failure with ansible
##ansible-playbook "${PLAYBOOKosdnodefail}"

# take the ifaces down  (40Gb NICs are ens3f1 and ens3f0)
updatelog "IFDOWN: Taking ifaces down on ${OSDhostname}" $LOGFILE
ssh "root@${OSDhostname}" ifdown ens3f0
ssh "root@${OSDhostname}" ifdown ens3f1

# shutdown the OSDhost and set for delayed reboot
#updatelog "BEGIN: OSDnode - halting" $LOGFILE
#reboottime="+${failuretime%?}"
#ssh "root@${OSDhostname}" halt
#updatelog "OSDhostname ${OSDhostname} halted. Rebooting in ${reboottime} min" $LOGFILE
#updatelog "OSDhostname ${OSDhostname} halted. Power reset in ${failuretime}" $LOGFILE

# Wait for failuretime
sleep "${failuretime}"

# Reboot OSDnode
#ipmitool -I lanplus -U quads -P 459769 -H mgmt-${OSDhostname}.rdu.openstack.engineering.redhat.com power reset
#updatelog "OSDhostname ${OSDhostname} ipmi power reset. Rebooting..." $LOGFILE

# bring the ifaces up  (40Gb NICs are ens3f1 and ens3f0)
updatelog "IFUP: Bringing ifaces up on ${OSDhostname}" $LOGFILE
ssh "root@${OSDhostname}" ifup ens3f0
ssh "root@${OSDhostname}" ifup ens3f1

# Let things run for 'recoverytime'
updatelog "OSDnode: sleeping ${recoverytime} to monitor cluster re-patriation" $LOGFILE
sleep "${recoverytime}"

# Now kill off the background processes: POLLceph and PBENCH-COSbench (I/O workload)
kill $PIDpollceph2
kill $PIDpbench
updatelog "END: OSDnode - Completed waiting and stopped bkgrd processes" $LOGFILE
#####-----------------------

##################################
# END of I/O workload and monitoring
# However we want a stable cluster so wait for recovery to complete
updatelog "** Cluster idle. Cleanup START: Waiting for cleanPGs == totalPGs" $LOGFILE

# Poll ceph status (in a blocking foregrd process) 
./pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}"

# Cluster is recovered. cleanPGs == totalPGs.
# Re-enable scrubbing
ceph osd unset noscrub
ceph osd unset nodeep-scrub

# Call pollceph one final time, expecting HEALTH_OK and immediate return
sleep 1
./pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}"

# update logfile with completion timestamp and end email notifications
updatelog "** Cleanup END: Recovery complete" $LOGFILE
echo " " | mail -s "ceph recovery complete" jharriga@redhat.com ekaynar@redhat.com

# END
