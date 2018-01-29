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
while [ $running ]; do
    if [ -f $csv_file ]; then
        if grep "completed" $csv_file > /dev/null; then
            running=0
        else
            echo "ERROR: COSbench job did not complete cleanly"
            exit 1
        fi
    fi
    sleep 30
done

echo "COSbench jobID: $jobId - Completed at `get_time` "
