# OSDfailure
Scripts for automation of I/O workload and Ceph failure injection
Uses COSbench to apply I/O workload; pbench for monitoring and SSH
scripts (dropOSD.bash) to inject failures.

Eventually should be adapted to use ansible playbooks to inject failures

FILE INVENTORY:
* dropOSD.bash - script which is run on OSDhostname (drops and OSD device)
* functions.shinc - collection of functions
* pollceph.sh - script run on MONhostname (polls ceph status)
* runtest.sh - main driver script which executes COSbench and injects failures
* vars.shinc - global variables

USAGE:
* Edit 'vars.shinc' for your environment (OSDhostname & MONhostname)
* run './runtest.sh'
