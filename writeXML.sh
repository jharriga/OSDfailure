#!/bin/bash
# writeXML.sh - creates the COSbench workload files

# Bring in other script files
myPath="${BASH_SOURCE%/*}"
if [[ ! -d "$myPath" ]]; then
    myPath="$PWD" 
fi

# Variables
source "$myPath/vars.shinc"

# Functions
#source "$myPath/Utils/functions.shinc"

echo "Creating COSbench XML workload files from settings in vars.shinc"
# RUNTESTxml
# backup the XML file if it exists
if [ -f "${RUNTESTxml}" ]; then
    mv "${RUNTESTxml}" "${RUNTESTxml}_bak"
    echo "> ${RUNTESTxml} exists - moved to ${RUNTESTxml}_bak"
fi
# copy the Template and make edits
# RTkeys_arr and RTvalues_arr defined in vars.shinc
cp "${RUNTESTtemplate}" "${RUNTESTxml}"

let index=0
for origValue in "${RTkeys_arr[@]}"; do
    newValue="${RTvalues_arr[index]}"
    sed -i "s/${origValue}/${newValue}/g" $RUNTESTxml
    index=$(( $index + 1 ))
done
echo "> created COSbench workload file: ${RUNTESTxml}"

echo "DONE - Validate XML files before proceeding."

# DONE
