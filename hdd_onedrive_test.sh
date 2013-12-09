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

################################===CHECK TEST FOR PREV. RESULTS===################################

model=$(smartctl -i $disk | awk '/Device Model/{print $3 "_" $4}')
dir=results

if [ -d $dir ]
	then
	echo
else
	mkdir $dir
fi


if [ -e $dir/$model ]; then
	echo -e "
   This drive you have already tested! Let's test another one.
   Would you like to test the drive \033[1m$model\033[0m again?
   !!!WARNING!!! If you choose \"Yes\" then data from previous tests of $model will be ERASED!!! ---> Y/N?"
	while :
	 do
	   read -s -n 1 answ
	 case "$answ" in
	   [yY]) rm $dir/$model
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
	touch $dir/$model

################################===TESTS===################################
	echo " " > $dir/$model
	echo " " >> $dir/$model
	echo -e "=================S.M.A.R.T. information before test=================" '\n' >> $dir/$model
	smartctl -iA $disk  >> $dir/$model
	echo " " >> $dir/$model

	rand_qd=1
	seq_qd=1
	duration=1800
	tmp_dir="work_files"

if [ -d $tmp_dir ]
	then
	rm -r $tmp_dir
	mkdir $tmp_dir
else
        mkdir $tmp_dir
fi

echo "
[readtest]
blocksize=8k
filename=$disk
rw=randread
direct=1
buffered=0
ioengine=libaio
iodepth=$rand_qd
runtime=$duration" > $tmp_dir/"rread_"$model
echo "
[writetest]
blocksize=8k
filename=$disk
rw=randwrite
direct=1
buffered=0
ioengine=libaio
iodepth=$rand_qd
runtime=$duration" > $tmp_dir/"rwrite_"$model

echo "
[readtest]
blocksize=8k
filename=$disk
rw=read
direct=1
buffered=0
ioengine=libaio
iodepth=$seq_qd
runtime=$duration" > $tmp_dir/"read_"$model
echo "
[writetest]
blocksize=8k
filename=$disk
rw=write
direct=1
buffered=0
ioengine=libaio
iodepth=$seq_qd
runtime=$duration" > $tmp_dir/"write_"$model

	fio $tmp_dir/rread_$model > $tmp_dir/tmp_rread.txt
	fio $tmp_dir/rwrite_$model > $tmp_dir/tmp_rwrite.txt
	fio $tmp_dir/read_$model > $tmp_dir/tmp_read.txt
	fio $tmp_dir/write_$model > $tmp_dir/tmp_write.txt

	echo " " >> $dir/$model
	echo -e "=================FIO test $dir=================" '\n' >> $dir/$model
	echo " " >> $dir/$model

	echo "Random Read, 8kB:" >> $dir/$model
	cat $tmp_dir/tmp_rread.txt | grep iops | awk -F"iops=" '{print $2}' | awk '{print "IOps=" $1}' >> $dir/$model
	value_time_r=$(cat $tmp_dir/tmp_rread.txt | awk -F"avg=" '/clat/{print $2 $1}'|sed 's/,.*clat//;s/:.*//') 
	echo "Latency=" $value_time_r >> $dir/$model
	echo "--------------------------------------------------" >> $dir/$model

	echo "Random Write, 8kB:" >> $dir/$model
	cat $tmp_dir/tmp_rwrite.txt | grep iops | awk -F"iops=" '{print $2}' | awk '{print "IOps=" $1}' >> $dir/$model 
	value_time_w=$(cat $tmp_dir/tmp_rwrite.txt | awk -F"avg=" '/clat/{print $2 $1}'|sed 's/,.*clat//;s/:.*//') 
	echo "Latency=" $value_time_w >> $dir/$model
	echo "--------------------------------------------------" >> $dir/$model

	echo "Seq. Read, 8kB, bandwidth:" >> $dir/$model
	cat $tmp_dir/tmp_read.txt | grep -w read| awk -F"bw=" '{print $2}'|sed 's/,.*//;/^$/d' >> $dir/$model
	echo "--------------------------------------------------" >> $dir/$model

	echo "Seq. Write, 8kB, bandwidth:" >> $dir/$model
	cat $tmp_dir/tmp_write.txt | grep -w write| awk -F"bw=" '{print $2}'|sed 's/,.*//;/^$/d' >> $dir/$model 

	echo "--------------------------------------------------" >> $dir/$model
#	rm -r $tmp_dir 

	echo -e "=================S.M.A.R.T. information after test=================" '\n' >> $dir/$model
	smartctl -A $disk >> $dir/$model
