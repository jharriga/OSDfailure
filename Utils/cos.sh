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
while [ $running -eq 1 ]; do
    run_path="$cosPATH/archive/$jobId-*"
    if [ -d $run_path ]; then
        running=0
    else
        sleep 10
    fi
done

echo "COSbench jobID: $jobId - Completed at `get_time` "
