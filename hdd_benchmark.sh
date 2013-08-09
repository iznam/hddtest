#!/bin/bash

######################################
# One test takes 14 hours:           #
# 8 hours for FIO, 10 hours for Orion# 
######################################

while getopts "d:f:h" arg
 do
  case $arg in
   d ) disk=$OPTARG ;;
   h ) echo "
Usage: $0 -d [disk name, e.g. sda] -h [help]
     -d name of the drive [/dev/$hd] 
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

################################===TESTS===################################
model=$(smartctl -i /dev/$disk | awk '/Device Model/{print $3 "_" $4}')

model_info()
{
echo " " > results/$model
  echo -e "=================S.M.A.R.T. information:=================" '\n' >> results/$model
   smartctl -i /dev/$disk  >> results/$model
    hddtemp /dev/$disk | awk '{print "Temperature, idle mode = " $4}' >> results/$model
     echo " " >> results/$model
      echo " " >> results/$model
       cat /proc/partitions | awk '/$model/{print $4 " = " $3 " byte"}' >> results/$model
      echo " " >> results/$model
}

################################===CHECK DRIVE TYPE===################################
device=$(mdadm -Q /dev/$disk | grep raid -c)
raid_drive=$(mdadm --detail /dev/$disk | awk '/active sync/{print $7}' | awk 'NR == 1')

if [ $device -eq 1 ]; then
  qd=16
  duration=14400
  model=$(smartctl -i $raid_drive | awk '/Device Model/{print $3 "_" $4}')_RAID10
  cp run-orion-raid run-orion
  echo " "
  echo "        This is a RAID, QD=$qd, test takes 18 hours"
  echo "=================$model test results================="
else
  duration=3600
  qd=1
  cp run-orion-drive run-orion
  echo " " 
  echo "        This is a single drive, QD=$qd, test takes 3 hours"
  model_info
fi
################################===CHECK TEST REPEAT===################################

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
   rm -rf ~/orion/$model
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
################################===FIO==################################

echo "
[readtest]
blocksize=4k
filename=/dev/$disk
rw=randread
direct=1
buffered=0
ioengine=libaio
iodepth=$qd
runtime=$duration" > read_fio_$model
echo "
[writetest]
blocksize=4k
filename=/dev/$disk
rw=randwrite
direct=1
buffered=0
ioengine=libaio
iodepth=$qd
runtime=$duration" > write_fio_$model

fio read_fio_$model > tmp_read.txt
fio write_fio_$model > tmp_write.txt

echo -e "=================FIO test results=================" '\n' >> results/$model
echo " " >> results/$model

echo "Random Read, 4kB:" >> results/$model
cat tmp_read.txt | grep iops | awk -F"iops=" '{print $2}' | awk '{print "IOps=" $1}' >> results/$model
        value_time_r=$(cat tmp_read.txt | grep clat | awk -F"avg=" '{print $2}' | awk '{print $1}' | sed 's/.$//')
        sec_r=$(cat tmp_read.txt | grep clat | awk -F"clat " '{print $2}'| awk '{print $1}' | sed 's/.$//');
echo "Latency=" $value_time_r $sec_r >> results/$model
echo "------------------------------------------" >> results/$model

echo "Random Write, 4kB:" >> results/$model
cat tmp_write.txt | grep iops | awk -F"iops=" '{print $2}' | awk '{print "IOps=" $1}' >> results/$model 
        value_time_w=$(cat tmp_write.txt | grep clat | awk -F"avg=" '{print $2}' | awk '{print $1}' | sed 's/.$//')
        sec_w=$(cat tmp_write.txt | grep clat | awk -F"clat " '{print $2}'| awk '{print $1}' | sed 's/.$//');
echo "Latency=" $value_time_w $sec_w >> results/$model

echo "------------------------------------------" >> results/$model
rm tmp_read.txt tmp_write.txt read_fio_$model write_fio_$model
################################===ORION==################################

echo -e "=================ORION test results=================" '\n' >> results/$model
cp xprofile_for_HDD.x $model.x
echo "/dev/$disk" > $model.lun

if [ -e ~/orion/$model ]
  then
 rm -rf ~/orion/$model
 echo  "~/orion/$model has been removed"
fi

storage-test $model
rm $model.*


orion_output()
{

orion_pwd=/home/rnd/orion

echo "Random Read, 8kB" >> $model.txt
for dirt in W0*C*-B008; do
 find $orion_pwd/$model/iops/$dirt -type d | while read dirt; do
  awk '/Small Columns/{printf "\n" "Threads:" $3}' $dirt/*summary.txt
   awk '/IOPS/{printf "\t" $3 " "}'  $dirt/*summary.txt
    awk '/Latency/{printf "\t" $3 }' $dirt/*summary.txt 
  done
 echo " "
done >> $model.txt

echo "------------------------------------------"  >> $model.txt
echo "Random write, 8kB" >> $model.txt
for dirt in W1*C*-B008; do
 find $orion_pwd/$model/iops/$dirt -type d | while read dirt; do
  awk '/Small Columns/{printf "\n" "Threads:" $3}' $dirt/*summary.txt
   awk '/IOPS/{printf "\t" $3 " "}'  $dirt/*summary.txt
    awk '/Latency/{printf "\t" $3 }' $dirt/*summary.txt 
  done
 echo " "
done >> $model.txt

echo "------------------------------------------"  >> $model.txt
echo "Sequential Read, 8kB:" >> $model.txt
echo " "
cat $orion_pwd/$model/mbps/W000-S008-C01-B008/*_summary.txt | awk '/MBPS/{print $3}'  >> $model.txt

echo "Sequential Write, 8kB:"  >> $model.txt
echo " " 
cat $orion_pwd/$model/mbps/W100-S008-C01-B008/*_summary.txt | awk '/MBPS/{print $3}'   >> $model.txt
echo " "

sed 's/=/= /g' $model.txt >> results/$model
rm $model.txt
}

orion_output

echo "------------------------------------------" >> results/$model

smartctl -A /dev/$disk >> results/$model
smartctl -l error /dev/$disk >> results/$model

rm run-orion
################################===THE END===################################



