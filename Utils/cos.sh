#!/bin/bash

# Bring in other script files
myPath="${BASH_SOURCE%/*}"
if [[ ! -d "$myPath" ]]; then
    myPath="$PWD"
fi

# Variables
source "$myPath/../vars.shinc"

# Functions
source "$myPath/../Utils/functions.shinc"

f_name=$1
OUTPUT=$(sh $cosPATH/cli.sh submit $f_name) &&
echo $OUTPUT
jobId=$(echo $OUTPUT |awk '{print $4}') &&
echo "COSbench jobID is: $jobId - Started at `get_time` "

running=1
csv_file="$cosPATH/archive/${jobId}-prepCluster/${jobId}-prepCluster.csv"
while [ $running -eq 1 ]; do
    if [ -f $csv_file ]; then
        grep -q "completed" "$csv_file"
        if [ $? -eq 0 ]; then
            running=0
        else
            echo "ERROR: COSbench job did not complete cleanly"
            exit 1
        fi
    fi
    sleep 10
done

echo "COSbench jobID: $jobId - Completed at `get_time` "
