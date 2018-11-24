#!/bin/bash
#
# RUNTEST.sh
#   Executes the COSbench workloads and injects failures at specific
#   time periods
#
#   Disable ceph scrubbing 
#   Start COSbench workload
#   Sleep for 'starttime' minutes
#   Stop OSD device and leave it down for 'failuretime' minutes
#     - poll and record ceph status every 'polltime' minutes
#   Add the OSD back into cluster and wait for 'recoverytime'
#     - poll and record ceph status every 'polltime' minutes
#   Sleep for 'starttime' minutes
#   Stop OSD node NICs and leave them down for 'failuretime' minutes
#     - poll and record ceph status every 'polltime' minutes
#   Add the OSD node NICs back into cluster and wait for 'recoverytime'
#     - poll and record ceph status every 'polltime' minutes
#   Stop COSbench workload
#   Raise recovery default settings accelerate recovery
#   Wait for recovery and record timestamp for ('active&clean')
#   Restore default settings: recovery and scrubbing
#
#   Proposed variable settings: (see vars.shinc)
#     - starttime = 10min
#     - failuretime = 10 min
#     - recoverytime = 60 min
#     - closuretime = 30s
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

#++++++++++++++++++++++++++++
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
host3=`ssh "root@${RGWhostname}" hostname`
updatelog "> RGWhost is ${RGWhostname} : ${host3}" $LOGFILE

# Record cluster capacity stats
var1=`echo; ceph df | head -n 5`
var2=`echo; ceph df | grep rgw.buckets.data`
updatelog "$var1$var2" $LOGFILE
#
# END: Housekeeping
#--------------------------------------

# Disable scrubbing - for all three test phases
ceph osd set noscrub
ceph osd set nodeep-scrub

#++++++++++++++++++++++++++++
#>>> PHASE 1: no failures <<<
#-----------------------------
# Start the COSbench I/O workload

### DEBUG
# sleep 100m &           # DEBUG
# updatelog "Running in DEBUG mode! Comment 'sleep 100m &' and replace with actual I/O workload"
######

### Using PBENCH monitoring tool
# pbench-user-benchmark "Utils/cos.sh ${myPath}/${RUNTESTxml} $LOGFILE" &
# PIDpbench=$!
# updatelog "** pbench-user-benchmark cosbench started as PID: ${PIDpbench}" $LOGFILE
######

### Without PBENCH
Utils/cos.sh ${myPath}/${RUNTESTxml} $LOGFILE &
PID=$!
updatelog "** cosbench started as PID: ${PID}" $LOGFILE

# VERIFY it successfully started
sleep "${sleeptime}"
if ps -p $PID > /dev/null; then
    # match the timing of the other two phases
    t_phase1S="${starttime}${unittime}"            # start duration
    updatelog "START: No Failures - start sleeping ${t_phase1S}" $LOGFILE
    sleep "${t_phase1S}"
    t_phase1F="${failuretime}${unittime}"            # failure duration
    updatelog "FAILURE: No Failures - start sleeping ${t_phase1F}" $LOGFILE
    sleep "${t_phase1F}"
    t_phase1R="${recoverytime}${unittime}"           # recovery duration
    updatelog "RECOVERY: No Failures - start sleeping ${t_phase1R}" $LOGFILE
    sleep "${t_phase1R}"
else
    error_exit "cosbench FAILED"
fi
updatelog "END: No Failures - completed sleeping" $LOGFILE

# Record cluster capacity stats
var1=`echo; ceph df | head -n 5`
var2=`echo; ceph df | grep rgw.buckets.data`
updatelog "$var1$var2" $LOGFILE

# sleep for closuredelay directive in ioWorkload.xml
sleep "${closuretime}"

#++++++++++++++++++++++++++++++++++++++++
#>>> PHASE 2: single osd device failure <<<
#---------------------------------------
# BEGIN the OSD device failure sequence
t_phase2S="${starttime}${unittime}"            # start duration
updatelog "START: OSDdevice - start sleeping ${t_phase2S}" $LOGFILE
sleep "${t_phase2S}"

# Poll ceph status (in a bkrgd process) 
Utils/pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}" &
PIDpollceph1=$!
# VERIFY it successfully started
sleep "${sleeptime}"
if ! ps -p $PIDpollceph1 > /dev/null; then
    kill $PID
    error_exit "First pollceph.sh FAILED. Killed cosbench: $PID"
fi

# set the remote logfile name
logbase=$(basename $LOGFILE)
logtmp="/tmp/${logbase}"
## Drop the OSDdevice using SSH - blocks for failuretime
t_phase2F="${failuretime}${unittime}"
updatelog "FAILURE: OSDdevice - start sleeping ${t_phase2F}" $LOGFILE
ssh "root@${OSDhostname}" "bash -s" < Utils/dropOSD.bash "${t_phase2F}" "${logtmp}"
# bring the remote logfile back and append to LOGFILE
scp -q "root@${OSDhostname}:${logtmp}" "${logtmp}"
cat "${logtmp}" >> $LOGFILE
rm -f "${logtmp}"

# Let things run for 'recoverytime'
t_phase2R="${recoverytime}${unittime}"
updatelog "RECOVERY: OSDdevice - sleeping ${t_phase2R} to monitor cluster re-patriation" $LOGFILE
sleep "${t_phase2R}"

# Now kill off the POLLCEPH background process
kill $PIDpollceph1
updatelog "END: OSDdevice - Completed. Stopped POLLCEPH bkgrd process" $LOGFILE

# Record cluster capacity stats
var1=`echo; ceph df | head -n 5`
var2=`echo; ceph df | grep rgw.buckets.data`
updatelog "$var1$var2" $LOGFILE

# sleep for closuredelay directive in ioWorkload.xml
sleep "${closuretime}"

# END - OSD device failure sequence
#--------------------------------------

#++++++++++++++++++++++++++++++++++++++++
#>>> PHASE 3: entire osd node failure <<<
######---------------------------------
# The 'OSD node' failure sequence
# scrubbing is already disabled
#
t_phase3S="${starttime}${unittime}"            # start duration
updatelog "START: OSDnode - start sleeping ${t_phase3S}" $LOGFILE
sleep "${t_phase3S}"

# Poll ceph status (in a bkrgd process) 
Utils/pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}" &
PIDpollceph2=$!
# VERIFY it successfully started
sleep "${sleeptime}"
if ! ps -p $PIDpollceph2 > /dev/null; then
    kill $PID
    error_exit "Second pollceph.sh FAILED. Killed cosbench: $PID"
fi

# take the ifaces down - defined in vars.shinc
for iface in ${IFACE_arr[@]}; do
    updatelog "IFDOWN: Taking iface ${iface} *down* on ${OSDhostname}" $LOGFILE
    ssh "root@${OSDhostname}" ifdown "${iface}"
done

# Wait for failuretime
t_phase3F="${failuretime}${unittime}"
updatelog "FAILURE: OSDnode - start sleeping ${t_phase3F}" $LOGFILE
sleep "${t_phase3F}"

# bring the ifaces up - defined in vars.shinc
for iface in ${IFACE_arr[@]}; do
    updatelog "IFUP: Bringing iface ${iface} *up* on ${OSDhostname}" $LOGFILE
    ssh "root@${OSDhostname}" ifup "${iface}"
done

# Forcebly restart the ceph services - to get the OSDs back up/in
# and restart the RGW service on the OSDnode
sleep 2s                           # short pause

if [ `ceph-volume lvm list > /dev/null 2>&1` ]; then
    # deployTYPE="ceph-volume"
    ssh "root@${OSDhostname}" ceph-volume lvm activate-all
else
    # deployTYPE="ceph-disk"
    ssh "root@${OSDhostname}" ceph-disk activate-all
fi

ssh "root@${OSDhostname}" systemctl restart ceph-radosgw@rgw.`hostname -s`.service

# Let things run for 'recoverytime'
t_phase3R="${recoverytime}${unittime}"
updatelog "RECOVERY: OSDnode - sleeping ${t_phase3R} to monitor cluster re-patriation" $LOGFILE
sleep "${t_phase3R}"

updatelog "END: OSDnode - Completed waiting." $LOGFILE

# Record cluster capacity stats
var1=`echo; ceph df | head -n 5`
var2=`echo; ceph df | grep rgw.buckets.data`
updatelog "$var1$var2" $LOGFILE

# sleep for closuredelay directive in ioWorkload.xml
sleep "${closuretime}"

# Wait for cos job OR pbench to complete
while ps -p $PID > /dev/null; do
    updatelog "Waiting for workload to complete" $LOGFILE
    sleep 1m
done
updatelog "COSbench process completed" $LOGFILE

##################################
# END of I/O workload and monitoring
# However we want a stable cluster so wait for recovery to complete
# NOTE: two ceph vars can be modified to make recovery ops more aggressive (presumably faster)
#   See - http://lists.ceph.com/pipermail/ceph-users-ceph.com/2015-June/001895.html
updatelog "** Cluster idle. Cleanup START: Waiting for cleanPGs == totalPGs" $LOGFILE
updatelog "** Setting aggressive recovery values" $LOGFILE
ceph tell osd.* injectargs '--osd-max-backfills=10' &> /dev/null
ceph tell osd.* injectargs '--osd-recovery-max-active=15' &> /dev/null
ceph tell osd.* injectargs '--osd-recovery-sleep-hdd=0' &> /dev/null

# Poll ceph status (in a blocking foregrd process) 
Utils/pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}"

# Cluster is recovered. cleanPGs == totalPGs.
# Re-enable scrubbing
ceph osd unset noscrub
ceph osd unset nodeep-scrub
# Set recovery settings back to defaults
ceph tell osd.* injectargs '--osd-max-backfills=1' &> /dev/null
ceph tell osd.* injectargs '--osd-recovery-max-active=3' &> /dev/null
ceph tell osd.* injectargs '--osd-recovery-sleep-hdd=0.1' &> /dev/null

# Call pollceph one final time, expecting HEALTH_OK and immediate return
sleep "${sleeptime}"
Utils/pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}"

# Record cluster capacity stats
var1=`echo; ceph df | head -n 5`
var2=`echo; ceph df | grep rgw.buckets.data`
updatelog "$var1$var2" $LOGFILE

# update logfile with completion timestamp and end email notifications
updatelog "** Cleanup END: Recovery complete" $LOGFILE
# Rename LOGFILE (vars.shinc)
# prepend w/$jobId from cos.sh script (sent via $TMPfile)
updatelog "Renaming LOGFILE with COSbench jobId prefix" $LOGFILE
jobId=$(cat "${TMPfile}")
echo "JOBID: ${jobId}"
LOGFINAL="${RESULTSDIR}/${jobId}_${PROGNAME}_${ts}.log"
echo "LOGFINAL: ${LOGFINAL}"
mv $LOGFILE $LOGFINAL
rm $TMPfile                         # cleanup

#echo " " | mail -s "ceph recovery complete" <email addresses>

### if running w/PBENCH - copy results
# Copy the LOGFILE, PBENCH and COSbench results to /var/www/html/pub
# Cresults=`ls -tr $cosPATH/archive | tail -n 1`
# Dpath="/var/www/html/pub/$Cresults.$ts"
# mkdir $Dpath
# cp -r $cosPATH/archive/$Cresults $Dpath/.
# Presults=`ls -tr /var/lib/pbench-agent | grep pbench-user-benchmark | tail -n 1`
# cp -r /var/lib/pbench-agent/$Presults $Dpath/.
#
# updatelog "FINALIZING: Pbench and COSbench results copied to $Dpath" $LOGFILE
#
# copy LOGFILE to results dir
# cp $LOGFILE $Dpath/.
######

# END
