# OSDfailure
Scripts for automation of I/O workload and Ceph failure injection.
Uses COSbench to apply I/O workload; pbench for monitoring and SSH
scripts (dropOSD.bash) to inject failures.

Could be adapted to use ansible playbooks to inject failures

FILE INVENTORY:
* vars.shinc - global variables
* writeXMLs.sh
* prepCluster.sh
* runtest.sh - main driver script which executes COSbench and injects failures
* XMLtemplates (directory)
  * TMPL_deletewrite.xml
  * TMPL_prepCluster.xml
  * TMPL_hybrid.xml
* Utils (directory)
  * dropOSD.bash - script which is run on OSDhostname (drops an OSD device)
  * functions.shinc - collection of functions
  * pollceph.sh - script run on MONhostname (polls ceph status)


USAGE:
* Edit 'vars.shinc' for your environment (hostnames; runtime; obj sizes ...)
* run 'writeXMLs.sh'    <-- create COSbench workload files
* run 'prepCluster.sh'    <-- create pools and fill the cluster
* run 'runtest.sh'    <-- run the test and record results
