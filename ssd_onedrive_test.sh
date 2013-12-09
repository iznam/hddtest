#!/bin/bash


while getopts "d:h" arg
 do
  case $arg in
   d ) disk=$OPTARG ;;
   h ) echo "
Usage: $0 -d [disk name, e.g. sda] -h [help]
     -d name of the drive [sdX, mdX] 
     -h this help"
    exit 0 ;;
   ? ) echo "No argument value for option $OPTARG" ;;
  esac
 done
shift $OPTIND



message()
{
echo 
"Usage: $0 -d [disk name, e.g. sda] -h [help]
     -d name of the drive [/dev/$hd] 
     -h this help"
echo " " 
exit 1
}    

[ -n "$disk" ] || message "Please set name of hard drive: -d "

################################===CHECK TEST REPEAT===################################
model=$(smartctl -i /dev/$disk | awk '/Device Model/{print $3 "_" $4}')

if [ -e *fio_$model* -o -e tmp_* ]; then
   rm *fio_$model tmp_*
fi

if [ -e results/$model ]; then
   echo -e "
   This drive you have already tested! Let's test another one.
   Would you like to test the drive \033[1m$model\033[0m again?
   !!!WARNING!!! If you choose \"Yes\" then data from previous tests of $model will be ERASED!!! ---> Y/N?"
 while :; do
   read -s -n 1 answ
   case "$answ" in
   [yY]) rm results/$model
   break
   ;;
   [nN]) exit 0
   ;;
   *) echo "
   Wrong answer! Just say \"yes [yY]\" or \"no [nN]\" "
   esac
 done  
fi  

echo "
   Test of the $model has been started"
touch results/$model

################################===TESTS===################################

echo " " > results/$model
echo " " >> results/$model
  echo -e "=================S.M.A.R.T. information before test=================" '\n' >> results/$model
   smartctl -iA /dev/$disk  >> results/$model
     echo " " >> results/$model


################################===FIO==################################

rand_qd=32
seq_qd=1
duration=1800

echo "
[readtest]
blocksize=8k
filename=/dev/$disk
rw=randread
direct=1
buffered=0
ioengine=libaio
iodepth=$rand_qd
runtime=$duration" > rread_$model
echo "
[writetest]
blocksize=8k
filename=/dev/$disk
rw=randwrite
direct=1
buffered=0
ioengine=libaio
iodepth=$rand_qd
runtime=$duration" > rwrite_$model

echo "
[readtest]
blocksize=8k
filename=/dev/$disk
rw=read
direct=1
buffered=0
ioengine=libaio
iodepth=$seq_qd
runtime=$duration" > read_$model
echo "
[writetest]
blocksize=8k
filename=/dev/$disk
rw=write
direct=1
buffered=0
ioengine=libaio
iodepth=$seq_qd
runtime=$duration" > write_$model

fio rread_$model > tmp_rread.txt
fio rwrite_$model > tmp_rwrite.txt
fio read_$model > tmp_read.txt
fio write_$model > tmp_write.txt

echo " " >> results/$model
echo -e "=================FIO test results=================" '\n' >> results/$model
echo " " >> results/$model

echo "Random Read, 8kB:" >> results/$model
cat tmp_rread.txt | grep iops | awk -F"iops=" '{print $2}' | awk '{print "IOps=" $1}' >> results/$model
	value_time_r=$(cat tmp_rread.txt | awk -F"avg=" '/clat/{print $2 $1}'|sed 's/,.*clat//;s/:.*//') 
echo "Latency=" $value_time_r >> results/$model
echo "--------------------------------------------------" >> results/$model

echo "Random Write, 8kB:" >> results/$model
cat tmp_rwrite.txt | grep iops | awk -F"iops=" '{print $2}' | awk '{print "IOps=" $1}' >> results/$model 
	value_time_w=$(cat tmp_rwrite.txt | awk -F"avg=" '/clat/{print $2 $1}'|sed 's/,.*clat//;s/:.*//') 
echo "Latency=" $value_time_w >> results/$model
echo "--------------------------------------------------" >> results/$model

echo "Seq. Read, 8kB, bandwidth:" >> results/$model
cat tmp_read.txt | grep -w read| awk -F"bw=" '{print $2}'|sed 's/,.*//;/^$/d' >> results/$model
echo "--------------------------------------------------" >> results/$model

echo "Seq. Write, 8kB, bandwidth:" >> results/$model
cat tmp_write.txt | grep -w write| awk -F"bw=" '{print $2}'|sed 's/,.*//;/^$/d' >> results/$model 

echo "--------------------------------------------------" >> results/$model
rm tmp_rread.txt tmp_rwrite.txt rread_$model rwrite_$model tmp_read.txt tmp_write.txt read_$model write_$model

echo -e "=================S.M.A.R.T. information after test=================" '\n' >> results/$model
smartctl -A /dev/$disk >> results/$model
