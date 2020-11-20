# OSDfailure
Scripts for automation of I/O workload and Ceph failure injection.
Uses COSbench to apply I/O workload and injects OSD node failures.
Optionally uses pbench for monitoring.

For a writeup of how the ceph cluster was installed see:
 https://github.com/ekaynar/Benchmarks/blob/master/ceph-ansible/README.md

NOTE: vars.shinc requires edits. Some variables are undefined and must be set by the user.

FILE INVENTORY:
* vars.shinc - global variables (REQUIRES EDITS BEFORE RUNNING)
* writeXMLs.sh - creates COSbench workload files
* prepCluster.sh - creates pools and RGW user, then pre-fills the cluster
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
* run 'writeXMLs.sh'    <-- create COSbench workload files
* run 'prepCluster.sh'    <-- create pools and fill the cluster
* run 'runtest.sh'    <-- run the test and record results
