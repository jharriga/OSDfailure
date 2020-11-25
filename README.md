# OSDfailure
Scripts for automation of I/O workload and Ceph failure injection.
Uses COSbench to apply I/O workload and injects OSD node failures, by taking down
network interfaces on OSD nodes.
Optionally uses pbench for monitoring.
Executes these three phases (workstages):
   PHASE 1: no failures
     * Sleep for 'starttime' minutes  <-- baseline client I/O perf stats
   PHASE 2: drop first OSD node ($OSDhostname)
     * Stop OSDhostname NICs and leave them down for 'failuretime' minutes
     - poll and record ceph status every 'polltime' minutes
     * Add the OSDhostname NICs back into cluster and wait for 'recoverytime'
     - poll and record ceph status every 'polltime' minutes
     * Sleep for 'starttime' minutes
   PHASE 3: drop second OSD node ($OSDhostname2)
NOTE: this branch (releasetesting) requires that a pre-filled Ceph cluster already
      be installed and SWIFT user credentials are available

NOTE2: vars.shinc requires edits. Some variables are undefined and must be set by the user

NOTE3: you have to apply executable permissions (chmod 755 *.sh) recursively

FILE INVENTORY:
* vars.shinc - global variables (REQUIRES EDITS BEFORE RUNNING)
* writeXML.sh - creates COSbench workload files
* runtest.sh - main driver script which executes COSbench and injects failures
* XMLtemplates (directory)  <-- set with "RUNTESTtemplate" value (vars.shinc)
  * TMPL_deletewrite.xml
  * TMPL_hybrid.xml
* Utils (directory)
  * cos.sh - submits COSbench workloads (called by runtest.sh)
  * functions.shinc - collection of functions
  * pollceph.sh - polls ceph status (called by runtest.sh)

USAGE:
* Edit 'vars.shinc' for your environment (hostnames; runtime; obj sizes ...)
* Execute 'writeXML.sh'    <-- create COSbench workload files
* Edit COSbench workload file (ioWorkload.xml) <-- add SWIFT user credentials
>> config="username=johndoe:swift;password=EMPTY
* Execute 'runtest.sh'    <-- run the test and record results
