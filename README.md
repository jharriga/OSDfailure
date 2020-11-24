# OSDfailure
Scripts for automation of I/O workload and Ceph failure injection.
Uses COSbench to apply I/O workload and injects OSD node failures, by taking down
network interfaces on OSD nodes.
Optionally uses pbench for monitoring.
NOTE: this branch (releasetesting) requires that a pre-filled Ceph cluster already
      be installed and SWIFT user credentials are available

NOTE2: vars.shinc requires edits. Some variables are undefined and must be set by the user

NOTE3: you have to apply executable permissions (chmod 755 *.sh) recursively

FILE INVENTORY:
* vars.shinc - global variables (REQUIRES EDITS BEFORE RUNNING)
* writeXML.sh - creates COSbench workload files
* runtest.sh - main driver script which executes COSbench and injects failures
* XMLtemplates (directory)
  * TMPL_deletewrite.xml
  * TMPL_prepCluster.xml
  * TMPL_hybrid.xml
* Utils (directory)
  * cos.sh - submits COSbench workloads (called by runtest.sh)
  * functions.shinc - collection of functions
  * pollceph.sh - polls ceph status (called by runtest.sh)

USAGE:
* Edit 'vars.shinc' for your environment (hostnames; runtime; obj sizes ...)
* Execute 'writeXML.sh'    <-- create COSbench workload files
* Edit COSbench workload files (*.xml) <-- add SWIFT user credentials
* Execute 'runtest.sh'    <-- run the test and record results
