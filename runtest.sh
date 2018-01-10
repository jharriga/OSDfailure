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
#   Proposed variable settings: (see vars.shinc)
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
source "$myPath/Utils/functions.shinc"

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

#>>> PHASE 1: no failures <<<
# Start the COSbench I/O workload
pbench-user-benchmark "./cos.sh ${RUNTESTxml}" &
#sleep 100m &           ## DEBUG
#updatelog "Running in DEBUG mode! Comment 'sleep 100m &' and replace with actual I/O workload"

PIDpbench=$!
updatelog "** pbench-user-benchmark cosbench started as PID: ${PIDpbench}" $LOGFILE
# VERIFY it successfully started
sleep "${sleeptime}"
if ps -p $PIDpbench > /dev/null; then
    tmp_str="${phasetime}${unittime}"
    updatelog "BEGIN: No Failures - start sleeping ${tmp_str}" $LOGFILE
    sleep "${tmp_str}" 
else
    error_exit "pbench-user-benchmark cosbench FAILED"
fi
updatelog "END: No Failures - completed sleeping" $LOGFILE

#>>> PHASE 2: single osd device failure <<<
#---------------------------------------
# BEGIN the OSD device failure sequence
#   could invoke OSD device failure with ansible
##ansible-playbook "${PLAYBOOKosddevfail}"

# Disable scrubbing - per RHCS ADMIN Guide
ceph osd set noscrub
ceph osd set nodeep-scrub

# Poll ceph status (in a bkrgd process) 
./pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}" &
PIDpollceph1=$!
# VERIFY it successfully started
sleep "${sleeptime}"
if ! ps -p $PIDpollceph1 > /dev/null; then
    error_exit "First pollceph.sh FAILED."
fi

# set the remote logfile name
logbase=$(basename $LOGFILE)
logtmp="/tmp/${logbase}"
## Drop the OSDdevice using SSH - blocks for failuretime
ssh "root@${OSDhostname}" "bash -s" < Utils/dropOSD.bash "${failuretime}" "${logtmp}"
# bring the remote logfile back and append to LOGFILE
scp -q "root@${OSDhostname}:${logtmp}" "${logtmp}"
cat "${logtmp}" >> $LOGFILE
rm -f "${logtmp}"

# Let things run for 'recoverytime'
tmp_str="${recoverytime}${unittime}"
updatelog "BEGIN: OSDdevice - sleeping ${tmp_str} to monitor cluster re-patriation" $LOGFILE
sleep "${tmp_str}"

# Now kill off the POLLCEPH background process
kill $PIDpollceph1
updatelog "END: OSDdevice - Completed. Stopped POLLCEPH bkgrd process" $LOGFILE
# END - OSD device failure sequence
#--------------------------------------

#>>> PHASE 3: entire osd node failure <<<
######---------------------------------
# The 'OSD node' failure sequence
# scrubbing is already disabled
#
# Poll ceph status (in a bkrgd process) 
./pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}" &
PIDpollceph2=$!
# VERIFY it successfully started
sleep "${sleeptime}"
if ! ps -p $PIDpollceph2 > /dev/null; then
    error_exit "Second pollceph.sh FAILED."
fi

# take the ifaces down - defined in vars.shinc
for iface in ${IFACE_arr[@]}; do
    updatelog "IFDOWN: Taking iface ${iface} *down* on ${OSDhostname}" $LOGFILE
    ssh "root@${OSDhostname}" ifdown "${iface}"
done

# shutdown the OSDhost and set for delayed reboot
#updatelog "BEGIN: OSDnode - halting" $LOGFILE
#reboottime="+${failuretime%?}"
#ssh "root@${OSDhostname}" halt
#updatelog "OSDhostname ${OSDhostname} halted. Rebooting in ${reboottime} min" $LOGFILE
#updatelog "OSDhostname ${OSDhostname} halted. Power reset in ${failuretime}" $LOGFILE

# Wait for failuretime
tmp_str="${failuretime}${unittime}"
sleep "${tmp_str}"

# Reboot OSDnode
#ipmitool -I lanplus -U quads -P 459769 -H mgmt-${OSDhostname}.rdu.openstack.engineering.redhat.com power reset
#updatelog "OSDhostname ${OSDhostname} ipmi power reset. Rebooting..." $LOGFILE

# bring the ifaces up - defined in vars.shinc
for iface in ${IFACE_arr[@]}; do
    updatelog "IFUP: Bringing iface ${iface} *up* on ${OSDhostname}" $LOGFILE
    ssh "root@${OSDhostname}" ifup "${iface}"
done

# Let things run for 'recoverytime'
tmp_str="${recoverytime}${unittime}"
updatelog "OSDnode: sleeping ${tmp_str} to monitor cluster re-patriation" $LOGFILE
sleep "${tmp_str}"

# Now kill off the background processes: POLLceph and PBENCH-COSbench (I/O workload)
kill $PIDpollceph2
kill $PIDpbench
updatelog "END: OSDnode - Completed waiting and stopped bkgrd processes" $LOGFILE
#####-----------------------

mv /var/lib/pbench-agent/pbench-user-benchmark* /var/www/html/pub/run.$ts
updatelog "END: Pbench dir moved to /var/www/html/pub/run.$ts" $LOGFILE

##################################
# END of I/O workload and monitoring
# However we want a stable cluster so wait for recovery to complete
# NOTE: two ceph vars can be modified to make recovery ops more aggressive (presumably faster)
#   See - http://lists.ceph.com/pipermail/ceph-users-ceph.com/2015-June/001895.html
updatelog "** Cluster idle. Cleanup START: Waiting for cleanPGs == totalPGs" $LOGFILE

# Poll ceph status (in a blocking foregrd process) 
./pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}"

# Cluster is recovered. cleanPGs == totalPGs.
# Re-enable scrubbing
ceph osd unset noscrub
ceph osd unset nodeep-scrub

# Call pollceph one final time, expecting HEALTH_OK and immediate return
sleep "${sleeptime}"
./pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}"

# update logfile with completion timestamp and end email notifications
updatelog "** Cleanup END: Recovery complete" $LOGFILE
echo " " | mail -s "ceph recovery complete" jharriga@redhat.com ekaynar@redhat.com

# END
