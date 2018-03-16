#!/bin/bash

# DISable scrubbing
ceph osd set noscrub
ceph osd set nodeep-scrub

# Apply agressive recovery settings
ceph tell osd.* injectargs '--osd-max-backfills=10' &> /dev/null
ceph tell osd.* injectargs '--osd-recovery-max-active=15' &> /dev/null
ceph tell osd.* injectargs '--osd-recovery-sleep-hdd=0' &> /dev/null
