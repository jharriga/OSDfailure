# OSDfailure
Scripts for automation of I/O workload and Ceph failure injection.
Uses COSbench to apply I/O workload and injects OSD node failures.
Optionally uses pbench for monitoring.

For a writeup of how the ceph cluster was installed see:
 https://github.com/ekaynar/Benchmarks/blob/master/ceph-ansible/README.md

NOTE: vars.shinc requires edits. Some variables are undefined and must be set by the user.

FILE INVENTORY:
* vars.shinc - global variables (REQUIRES EDITS BEFORE RUNNING)
* writeXMLs.sh
* prepCluster.sh - creates pools and RGW user
* runtest.sh - main driver script which executes COSbench and injects failures
* XMLtemplates (directory)
  * TMPL_deletewrite.xml
  * TMPL_prepCluster.xml
  * TMPL_hybrid.xml
* Utils (directory)
  * functions.shinc - collection of functions
  * pollceph.sh - script run on MONhostname (polls ceph status)


USAGE:
* Edit 'vars.shinc' for your environment (hostnames; runtime; obj sizes ...)
* run 'writeXMLs.sh'    <-- create COSbench workload files
* run 'prepCluster.sh'    <-- create pools and fill the cluster
* run 'runtest.sh'    <-- run the test and record results
