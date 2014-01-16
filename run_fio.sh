#!/bin/bash

while getopts "d:o:t:q:b:h" arg
 do
  case $arg in
   d ) disk=$OPTARG ;;
   o ) operation=$OPTARG ;;
   t ) time=$OPTARG ;;
   q ) qd=$OPTARG ;;
   b ) block=$OPTARG ;;
   h ) echo "
Usage: $0 [OPTIONS]
-d [disk name, e.g. sda] 
-o [operation type, seq. read/write, random read/write, default random read] 
-t [test duration, default 300 seconds] 
-q [queue depth, default 1] 
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
-o [operation type, seq. read/write, random read/write, default random read] 
-t [test duration, default 300 seconds] 
-q [queue depth, default 1] 
-b [block size in kB, default 8kB]
-h [help]"
echo " " 
exit 1
}    

[ -n "$disk" ] || message "ERROR: Please set name of hard drive: -d "
[ -n "$operation" ] || $operation=randread
[ -n "$time" ] || $time=300
[ -n "$qd" ] || $qd=1
[ -n "$block" ] || $block=8k

#one_drive ()

echo "
[fio_test]
blocksize=$block
filename=$disk
rw=$operation
direct=1
buffered=0
ioengine=libaio
iodepth=$qd
runtime=$time" > work_file.dat


#one_drive $block $disk $operation $qd $time

fio work_file.dat > res_${disk/\/dev\//}.dat

rm work_file.dat
