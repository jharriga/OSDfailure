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

echo -n "> OSDhost is ${OSDhostname} : "; ssh "root@${OSDhostname}" hostname
echo -n "> MONhost is ${MONhostname} : "; ssh "root@${MONhostname}" hostname

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

# Poll ceph status (in a bkrgd process) 
./pollceph.sh "${pollinterval}" "${LOGFILE}" "${MONhostname}" &
PIDpollceph1=$!
# VERIFY it successfully started
sleep 1s
if ! ps -p $PIDpollceph1 > /dev/null; then
    error_exit "First pollceph.sh FAILED."
fi

#---------------------------------------
# BEGIN the OSD device failure sequence
# invoke OSD device failure with ansible
##ansible-playbook "${PLAYBOOKosddevfail}"

## For now use SSH
ssh "root@${OSDhostname}" "bash -s" < dropOSD.bash "${failuretime}" "${LOGFILE}"

# Let things run for 'recoverytime'

updatelog "BEGIN: OSDevice - sleeping ${recoverytime} to monitor cluster re-patriation" $LOGFILE
sleep "${recoverytime}"

# Now kill off the POLLCEPH background process
kill $PIDpollceph1
updatelog "END: OSDevice - Completed. Stopped POLLCEPH bkgrd process" $LOGFILE
# END - OSD device failure sequence
#--------------------------------------

######---------------------------------
# The 'OSD node' failure sequence
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

updatelog "BEGIN: OSDnode - halting" $LOGFILE
reboottime="+${failuretime%?}"
ssh "root@${OSDhostname}" shutdown -h "${reboottime}"
updatelog "OSDhostname ${OSDhostname} halted. Rebooting in ${reboottime} min" $LOGFILE

# Wait for failuretime
sleep "${failuretime}"

# OSDnode should be rebooting....

# Let things run for 'recoverytime'
updatelog "OSDnode: sleeping ${recoverytime} to monitor cluster re-patriation" $LOGFILE
sleep "${recoverytime}"

# Now kill off the background processes: POLLceph and PBENCH-COSbench
kill $PIDpollceph2
kill $PIDpbench
updatelog "END: OSDnode - Completed waiting and stopped bkgrd processes" $LOGFILE
#####-----------------------

##################################
# END of I/O workload and monitoring
# However we want a stable cluster so wait for recovery to complete
updatelog "** Cleanup START: Waiting for all active+clean pgs" $LOGFILE
ssh "root@${MONhostname}" ceph status > /tmp/ceph.status
#pgcount=`grep pgmap /tmp/ceph.status |awk '{print $3}'`
#pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $1}'`
pgcount=`grep pool /tmp/ceph.status |awk '{print $4}'`
pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $2}'`
updatelog "pgcnt=${pgcount}; pgclean=${pgclean}" $LOGFILE
while [ $pgclean -lt $pgcount ] ; do
    sleep 1m
    ssh "root@${MONhostname}" ceph status > /tmp/ceph.status
    #pgcount=`grep pgmap /tmp/ceph.status |awk '{print $3}'`
    #pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $1}'`
    pgcount=`grep pools /tmp/ceph.status |awk '{print $4}'`
    pgclean=`grep ' active+clean$' /tmp/ceph.status |awk '{print $2}'`
    updatelog "pgcnt=${pgcount}; pgclean=${pgclean}" $LOGFILE
done
updatelog "** Cleanup END: Recovery complete" $LOGFILE
echo " " | mail -s "ceph recovery complete" jharriga@redhat.com

