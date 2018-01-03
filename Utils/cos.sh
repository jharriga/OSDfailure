#!/bin/bash


#cosPath=/root/0.5.2
cosPath=/root/0.4.2.c4
function run1 {
	f_name=$1
	OUTPUT=$(sh $cosPath/cli.sh submit $f_name) &&
	echo $OUTPUT
	jobId=$(echo $OUTPUT |awk '{print $4}') &&
	echo "ugur"
	echo $jobId
	echo "ugur"
#	echo "$cosPath/archive/$jobId-rep.144.obj.4m/$jobId-rep.144.obj.4m.csv"
	exist=1
	while [ $exist -eq 1 ];do
	if grep "completed" $cosPath/archive/$jobId-write/$jobId-write.csv > /dev/null
	then
		exist=0
	fi
	sleep 30
	done
}

run1 $1
