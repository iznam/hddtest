#!/bin/bash

while getopts "n:d:o:t:q:b:h" arg
do
	case $arg in
	n ) name=$OPTARG ;;
	d ) disk=$OPTARG ;;
	o ) operation=$OPTARG ;;
	b ) block=$OPTARG ;;
	h ) echo "
Usage: $0 [OPTIONS]
-d [disk name, e.g. /dev/sda]
-o [operation type, read/write, randread/randwrite, randrw]
-n [name of test]
-b [block size in kB, default 8kB]
-h [help]"
	exit 0 ;;
	? ) echo "No argument value for option $OPTARG" ;;
	esac
done
shift $OPTIND


message()
{
echo " "
echo $1
echo " "
echo "Usage: $0 [OPTIONS]
-d [disk name, e.g. /dev/sda]
-o [operation type, read/write, randread/randwrite, randrw]
-n [name of test]
-b [block size in kB, default 8kB]
-h [help]"
echo " "
exit 1
}

	[ -n "$disk" ] || message "Please set name of hard drive: -d "
	[ -n "$operation" ] || $operation=randread
	[ -n "$block" ] || $block=8k
	[ -n "$name" ] || message "Please set name of the test"

run_load ()
{
echo "
[fio_test]
blocksize=$block
filename=$disk
rw=$operation
direct=1
buffered=0
ioengine=libaio
iodepth=$qd
numjobs=$njobs
thread
norandommap
group_reporting
loops=2" > /tmp/work_file.dat

fio /tmp/work_file.dat
}

if test -d $name-$operation-res
	then
	echo "
Folder $name-$operation-res exists. Please rename the folder or give another test name.
"
	exit 1
fi

mkdir $name-$operation-res

		qd=32
                njobs=1
                run_load > $name-$operation-res/"$operation"-"$name"-"$qd"QD-"$njobs"thr.res
                rm /tmp/work_file.dat

		qd=128
		njobs=1
		run_load > $name-$operation-res/"$operation"-"$name"-"$qd"QD-"$njobs"thr.res
		rm /tmp/work_file.dat
	
		qd=64
                njobs=2
                run_load > $name-$operation-res/"$operation"-"$name"-"$qd"QD-"$njobs"thr.res
                rm /tmp/work_file.dat

		qd=32
		njobs=4
		run_load > $name-$operation-res/"$operation"-"$name"-"$qd"QD-"$njobs"thr.res
		rm /tmp/work_file.dat

		qd=16
		njobs=8
		run_load > $name-$operation-res/"$operation"-"$name"-"$qd"QD-"$njobs"thr.res
		rm /tmp/work_file.dat

		qd=8
		njobs=16
		run_load > $name-$operation-res/"$operation"-"$name"-"$qd"QD-"$njobs"thr.res
		rm /tmp/work_file.dat
		
		qd=4
                njobs=32
                run_load > $name-$operation-res/"$operation"-"$name"-"$qd"QD-"$njobs"thr.res
                rm /tmp/work_file.dat
