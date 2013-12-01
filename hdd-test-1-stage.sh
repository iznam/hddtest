#!/bin/bash  

set -e

	expander=$(sg_map -x | awk '{if ( $6 == 13 ) { print $1 }}')
	api_url="http://$SERVER_NAME"

	max_pend=10    # Maximum Pending sectors
	max_offunc=10  # Maximum Offline UNC errors
	max_revent=10  # Maximim Realloceted events
	max_rsect=3     # Maximim Reallocated sectors (Bad blocks)
	max_read_err=2 # Maximum Rear Raw errors (for WD and Hitachi only)

	export expander
	export api_url max_pend max_offunc max_revent max_rsect

if [ -z $expander ]; then
	echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
	echo "JBOD is not connected, please connect the JBOD to this server"
	echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
	exit 1
fi 

#############################===LIFGH_DOWN===###############################

light_down_slot ()
{

while :; 
	do
 	 if [ $(sg_ses -p 0x2 "$expander" | grep "Hot spare" -B 1 | grep "status: OK" -c) -eq 0 ] 
    	 then
	  	for i in `seq 0 23`
          do 
		sg_ses --index="$i" --set=2:1=0 "$expander" 2>/dev/null 
		sg_ses --index="$i" --set=3:5=0 "$expander" 2>/dev/null
    	  done     
     		dmesg -c 1>/dev/null
 	 fi
       		sleep 10
	done
}
	export -f light_down_slot

	light_down_slot &

#############################===SMART_TEST===###############################
smart_test ()
{
timeout 10 smartctl -A -H -i -a $(readlink -f $1) | fgrep -v '===' | awk '
/Device Model/{ model=$3$4 }
/Power_On_Hours/{ poh=$10 }
/Serial [Nn]umber:/ { serial=$3 }
/Raw_Read_Error_Rate/{ read_error=$10}
/Reported_Uncorrect/ { runc=$10 }
/Current_Pending_Sector/ { pend=$10 }
/Offline_Uncorrectable/ { offunc=$10 }
/Reallocated_Sector_Ct/ { rsec=$10 }
/Reallocated_Event_Count/ { revent=$10 }
/SMART overall-health/ { health=$6 }
/ATA Error/{ ata_err=$4 }
END {
   print  "serial=" serial "; model=" model ";  poh=" poh "; runc=" runc "; pend=" pend "; offunc=" offunc ";" 
   print "read_error=" read_error "; ata_err=" ata_err "; rsec=" rsec "; revent=" revent "; health=\"" health "\";"
}' | sed 's/,//g' 2>/dev/null

}


#############################===ERASE===#####################################
 
erase ()                                                                       
{
	timeout 10 fdisk /dev/$block_dev <<EOF
o
w
EOF

	sectors=$(($(fdisk -s /dev/$block_dev)-102400))
 
	timeout 15 dd if=/dev/zero of=/dev/$block_dev bs=1M count=100
	timeout 15 dd if=/dev/zero of=/dev/$block_dev bs=1k seek=$sectors count=102400

}


#############################===MAIN(SMART CHECK)===#####################################

main ()
     
{
	eval `smart_test /dev/$block_dev` 

	wd=$(echo "$model" | grep WDC)
	hitachi=$(echo "$model" | grep -i Hitachi)


	data=$(echo "MODEL="$model"&SERIAL_NUM="$serial"&POH="$poh"&READ_ERROR_RATE="$read_error"&CURRENT_PEND=""$pend""&REALLOC=""$rsec""&OFFLINE_UNC=""$offunc""&REALL_EVENT=""$revent""&HEALTH="$health"&ATA_ERROR="$ata_err)

	if [ ${rsec:-0} -gt $max_rsect -o ${pend:-0} -gt $max_pend -o ${offunc:-0} -gt $max_offunc -o ${revent:-0} -gt $max_revent \
	-o ${health:-0} != "PASSED" -o -n "$ata_err" ] || [ -z $model -a -z $serial ] || [ -n "$wd" -o -n "$hitachi" -a ${read_error:-0} -gt $max_read_err ]
	then

		curl -v -g -d "STAGE=1&RESULT=FAILED&REASON=SMART_FAILED&$data" "$api_url"
		sg_ses --index="$slot" --set=3:5=1 "$expander"
        	erase $block_dev > /dev/null 2>&1
        	exit 0
	else
        	sg_ses --index="$slot" --set=2:1=1 "$expander"
     	exit 0
	fi 2>/dev/null

}
#############################===PRE-MAIN===#####################################

test_fn ()
{
	sg_dev=$1
	sleep 10

	block_dev=$(lsscsi -tg | grep -w $sg_dev |awk '{print $4}'|sed 's/\/dev\///')
	sas_addr=$(lsscsi -tg | grep -w $sg_dev | awk '{print $3}'|sed 's/sas://')
   	slot=$(sg_ses -p 0xA $expander | grep "$sas_addr" -B 8 | awk '/Element index/{print $3}')

	sleep 10

	error_msg=$(dmesg | grep $block_dev | grep -i error)

  	eval `smart_test /dev/$1`

  	data=$(echo "MODEL="$model"&SERIAL_NUM="$serial"&POH="$poh"&READ_ERROR_RATE="$read_error"&CURRENT_PEND=""$pend""&REALLOC=""$rsec""&OFFLINE_UNC=""$offunc""&REALL_EVENT=""$revent""&HEALTH="$health"&ATA_ERROR="$ata_err) 
   
	if [ -z "$block_dev" ]; then
    		curl -v -g -d "STAGE=1&RESULT=FAILED&REASON=NO_BLOCK_DEV&$data" "$api_url"
		sg_ses --index="$slot" --set=3:5=1 "$expander"
      		exit 0
	elif [ -n "$error_msg" ]; then
    		curl -v -g -d "STAGE=1&RESULT=FAILED&REASON=ERR_IN_DMESG&$data" "$api_url"
     		sg_ses --index="$slot" --set=3:5=1 "$expander"
      		erase $block_dev
       		exit 0
	else
    		main $block_dev
	fi

}


lock_fn ()
{
(
	[ -n "$1" ] || exit 0
	flock -n /dev/$1 -c "test_fn $1"
   	sleep 5
) &
}

#############################===START_HERE===##############################
	export SHELL
	export -f test_fn
	export -f main
	export -f lock_fn
	export -f smart_test
	export -f erase

	inotifywait -mr -e create /dev/  | while read line; do lock_fn $(echo $line | grep -o -E sg[0-9]+ ) ;done
