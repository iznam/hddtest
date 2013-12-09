#!/bin/bash

per=$1
dev=$2

temp_run ()
{
time=0
while [ $time -lt $per ]
	do
	hddtemp /dev/"$dev" >> temp_res/"$dev".dat
	time=$(( $time + 30 ))
	sleep 30
	done
}

temp_run $per $dev &
