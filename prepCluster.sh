#!/bin/bash
# PREPCLUSTER.sh

#------------------------
# BEGIN FUNCTIONS
function delete_pools {
  for pl in ${pool_list[@]}; do
      if [ $pl != "rbd" ]; then
          ceph osd pool delete $pl $pl --yes-i-really-really-mean-it
      fi
  done

  sleep 5
  #ceph osd crush rule rm default.rgw.buckets.data
}

function create_pools {
  if [ "$1" == "rep" ]; then
      cmdtail="replicated"
  elif [ "$1" == "ec" ]; then
      cmdtail="erasure myprofile"
      ceph osd erasure-code-profile rm myprofile
      ceph osd erasure-code-profile set myprofile k=$k m=$m \
        crush-failure-domain=osd
  else
      echo "unknown value for REPLICATION in create_pools"; exit
  fi

  for pl in ${pool_list[@]}; do
      if [ $pl == "default.rgw.buckets.data" ]; then
          ceph osd pool create $pl $pg_data $cmd_tail
      elif [ $pl == "default.rgw.buckets.index" ]; then
          ceph osd pool create $pl $pg_index replicated
      else
          ceph osd pool create $pl $pg replicated
    fi
  done

  # enable RGW on the pools
  for pool in $(rados lspools); do
      ceph osd pool application enable $pool rgw
  done
}

# END FUNCTIONS
#------------------------

echo "$PROGNAME: Running with these values:"
echo "r=$REPLICATION k=$k m=$m pgdata=$pg_data pgindex=$pg_index \
      pg=$pg f=$fast_read"

echo "Stopping RGWs"
ansible -m shell -a 'systemctl stop ceph-radosgw@rgw.`hostname -s`.service' all

echo "Removing existing/old pools"
delete_pools

echo "Creating new pools"
create_pools $REPLICATION

echo "sleeping for a while..."; sleep 400

echo "Starting RGWs"
ansible -m shell -a 'systemctl start ceph-radosgw@rgw.`hostname -s`.service' all

echo "Creating User - which generates a new Password"
ssh $rgw 'radosgw-admin user create --uid=johndoe --display-name="John Doe" --email=john@example.com' &&
ssh $rgw 'radosgw-admin subuser create --uid=johndoe --subuser=johndoe:swift --access=full' 

# edit the Password into the XML workload files
echo "inserting new password into XML files $PREPARExml, $RUNTESTxml"
key=$(ssh $rgw 'radosgw-admin user info --uid=johndoe | grep secret_key' | tail -1 | awk '{print $2}' | sed 's/"//g')
sed  -i "s/password=.*;/password=$key;/g" "${PREPARExml}"
sed  -i "s/password=.*;/password=$key;/g" "${RUNTESTxml}"

echo "$PROGNAME: Done"	

# DONE
