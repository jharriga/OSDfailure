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
# Determine cluster deployTYPE (ceph-disk OR ceph-volume)
#diskSTR=`ceph-disk list`
if [ `ceph-volume lvm list > /dev/null 2>&1` ]; then
    deployTYPE="ceph-volume"
else
    deployTYPE="ceph-disk"
fi

# Get target OSD info before stopping
osdID=`df |grep ceph- |awk '{print $6}' |cut -d- -f2|sort -h|tail -1`
osdPART=`df |grep ceph-${osdID} |awk '{print $1}'`

# Determine if cluster is Bluestore or Filestore
ostore=`ceph osd metadata $osdID | grep osd_objectstore | awk '{print $2}'`
logit "ostore= $ostore   osdID= $osdID   osdPART= $osdPART" $log
case "$ostore" in
    *filestore*) 
        osdTYPE="filestore"
        FSjournal=`ls -l /var/lib/ceph/osd/ceph-${osdID}/journal | cut -d\> -f2`
        FSweight=`ceph osd tree | grep "osd.${osdID} "|awk '{print $3}'`
        logit "deployTYPE= $deployTYPE   FSjournal= $FSjournal   FSweight= $FSweight" $log
        if [[ $deployTYPE = *"disk"* ]]; then
            osdDEV=`ceph-disk list |grep "\bosd.$osdID\b" | awk '{print $1}'|tr -d '[0-9]'`
            zapCMD="ceph-disk zap $osdDEV"
            prepareCMD="ceph-disk prepare --filestore --osd-id $osdID $osdDEV $FSjournal"
            activateCMD="ceph-disk activate $osdPART"
        elif [[ $deployTYPE = *"volume"* ]]; then
            osdDEV=`ceph-volume lvm list |grep -A2 "\bosd.$osdID\b" | awk '{getline; getline; print $2}' | grep -oP "/dev/\K.*"`
            zapCMD="ceph-volume lvm zap $osdDEV"
            prepareCMD="ceph-volume lvm prepare --filestore --osd-id $osdID --data $osdDEV --journal $FSjournal"
            activateCMD="ceph-volume lvm activate --filestore --all"
        else
            error_exit "dropOSD: deployTYPE value invalid"
        fi
        ;;
    *bluestore*)
        osdTYPE="bluestore"
        if [[ $deployTYPE = *"disk"* ]]; then
            BSdb=`ceph-disk list |grep "\bosd.$osdID\b" | awk '{print substr($11, 1, length($11) - 1)}'`
            BSwal=`ceph-disk list |grep "\bosd.$osdID\b" | awk '{print $13}'`
            logit "deployTYPE= $deployTYPE   BSdb= $BSdb   BSwal= $BSwal" $log
            osdDEV=`ceph-disk list |grep "\bosd.$osdID\b" | awk '{print $1}'|tr -d '[0-9]'`
            zapCMD="ceph-disk zap $osdDEV"
            prepareCMD="ceph-disk prepare --bluestore --osd-id $osdID --block.db $BSdb --block.wal $BSwal $osdDEV"
            activateCMD="ceph-disk activate $osdPART"
        elif [[ $deployTYPE = *"volume"* ]]; then
##################
## how to get BSdb and BSwal using ceph-volume??
##################
            osdDEV=`ceph-volume lvm list |grep -A2 "\bosd.$osdID\b" | awk '{getline; getline; print $2}' | grep -oP "/dev/\K.*"`
            zapCMD="ceph-volume lvm zap $osdDEV"
            prepareCMD="ceph-volume lvm prepare --bluestore --osd-id $osdID --block.db $BSdb --block.wal $BSwal $osdDEV"
            activateCMD="ceph-volume lvm activate --bluestore --all"
        else
            error_exit "dropOSD: deployTYPE value invalid"
        fi
        ;;
    *)
        error_exit "dropOSD: Cluster metadata check CASE Statement failed."
        ;;
esac

logit "Cluster type is: $osdTYPE   osdDEV= $osdDEV" $log

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
if [[ $deployTYPE = *"disk"* ]]; then
    umount -f /var/lib/ceph/osd/ceph-$osdID         # unmount it
fi
logit "Issuing zap command: $zapCMD" $log
eval $zapCMD
ceph osd destroy $osdID --yes-i-really-mean-it  # destroy so ID can be re-used

#   - create new OSD, based on $osdTYPE
logit "Issuing prepare command: $prepareCMD" $log
eval $prepareCMD
# now activate
logit "Issuing activate command: $activateCMD" $log
eval $activateCMD
logit "dropOSD: prepared and activated new OSD" $log

# Start the new OSD
systemctl start ceph-osd@${osdID}
if [[ `systemctl status ceph-osd@${osdID} |grep Active:|grep running` ]] ; then
    logit "dropOSD: successfully started new OSD ${osdID}" $log
else
    error_exit "ceph-osd@${osdID}.service failed to start"
fi

# END
