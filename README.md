# OSDfailure
Scripts for automation of I/O workload and Ceph failure injection
Uses COSbench to apply I/O workload; pbench for monitoring and SSH
scripts (dropOSD.bash) to inject failures.

Eventually should be adapted to use ansible playbooks to inject failures

FILE INVENTORY:
* runtest.sh - main driver script which executes COSbench and injects failures
* vars.shinc - global variables
* writeXMLs.sh
* prepare.sh
* XMLtemplates
> TMPL_deletewrite.xml
> TMPL_fillCluster.xml
> TMPL_hybrid.xml
* Utils
> dropOSD.bash - script which is run on OSDhostname (drops an OSD device)
> functions.shinc - collection of functions
> pollceph.sh - script run on MONhostname (polls ceph status)


USAGE:
* Edit 'vars.shinc' for your environment (OSDhostname & MONhostname)
* run 'writeXMLs.sh'  <-- create COSbench workload files
* run 'prepare.sh'    <-- create pools and fill the cluster
* run './runtest.sh'  <-- run the test and record results
