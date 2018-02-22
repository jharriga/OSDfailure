#!/bin/bash
# resets Ceph settings back to defaults

# Re-enable scrubbing
ceph osd unset noscrub
ceph osd unset nodeep-scrub
# Set recovery settings back to defaults
ceph tell osd.* injectargs '--osd-max-backfills=1' &> /dev/null
ceph tell osd.* injectargs '--osd-recovery-max-active=3' &> /dev/null
ceph tell osd.* injectargs '--osd-recovery-sleep-hdd=0.1' &> /dev/null

