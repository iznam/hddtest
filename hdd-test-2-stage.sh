#!/bin/bash

expander=$(sg_map -x | awk '{if ( $6 == 13 ) { print $1 }}')
api_url="http://$SERVER_NAME
"
max_pend=10    # Maximum Pending sectors
max_offunc=10  # Maximum Offline UNC errors
max_revent=10  # Maximim Reallocetedents
max_rsec=3     # Maximim Reallocated sectors (Bad blocks)


export expander
export api_url max_pend max_offunc max_revent max_rsec


if [ -z $expander ]; then
  echo "++++++++++++++++++++++++++++++++++++++++++++++++"
  echo "JBOD is apsent, please connect one to this server"
  echo "++++++++++++++++++++++++++++++++++++++++++++++++"
  exit 1
fi 

#############################===SMART_COLLECT===###############################
smart_test ()
{
smartctl -A -H -i -a $(readlink -f $1) | fgrep -v '===' | awk '
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


###########################===SMART===##################################
smart_chk ()
           
{
eval `smart_test /dev/$block_dev`

wd=$(echo "$model" | grep WDC)
hitachi=$(echo "$model" | grep -i Hitachi)

data=$(echo "MODEL="$model"&SERIAL_NUM="$serial"&POH="$poh"&READ_ERROR_RATE="$read_error"&CURRENT_PEND=""$pend""&REALLOC=""$rsec""&OFFLINE_UNC=""$offunc""&REALL_EVENT=""$revent""&HEALTH="$health"&ATA_ERROR="$ata_err)

if [ ${rsec:-0} -gt $max_rsect -o ${pend:-0} -gt $max_pend -o ${offunc:-0} -gt $max_offunc -o ${revent:-0} -gt $max_revent -o ${health:-0} != "PASSED" -o -n "$ata_err" ] || [ -z $model -a -z $serial ] || [ -n "$wd" -o -n "$hitachi" -a ${read_error:-0} -gt $max_read_err ]; then
        curl -v -g -d "STAGE=1&RESULT=FAILED&REASON=SMART_AFTER_BB_FAILED&$data" "$api_url"
        sg_ses --index="$slot" --set=3:5=1 "$expander"
        exit 0
else
        curl -v -d "STAGE=1&RESULT=VALID&REASON=BB_and_SMART_PASSED&$data" "$api_url" 
        sg_ses --index="$slot" --set=2:1=1 "$expander"
        exit 0
fi 2>/dev/null

}


###########################===BADBLOCKS===##################################

bblock ()
{

eval `smart_test /dev/$block_dev`

bblock_fail="Too many bad blocks, aborting test"
bblock_passed="Pass completed, 0 bad blocks found. (0/0/0 errors)"

data=$(echo "MODEL="$model"&SERIAL_NUM="$serial"&POH="$poh"&READ_ERROR_RATE="$read_error"&CURRENT_PEND=""$pend""&REALLOC=""$rsec""&OFFLINE_UNC=""$offunc""&REALL_EVENT=""$revent""&HEALTH="$health"&ATA_ERROR="$ata_err)

run_badblocks ()
{
           badblocks -wv -b 512 -e 3 -s -t 0x55 -t 0xff  /dev/$block_dev

}

	   run_badblocks $block_dev 2>&1 tee |  while read line;do

case $line in
	$bblock_fail )
	   curl -v -g -d "STAGE=2&RESULT=FAILED&REASON=BBLOCK_FAILED&$data" "$api_url"
 	   sg_ses --index="$slot" --set=3:5=1 "$expander"
           exit 0
        ;;
        $bblock_passed )
	   curl -v -d "RESULT=VALID&$data" "$SERVER"
           smart_chk $block_dev
	   exit 0
        ;;
esac
done
}
#############################===PRE-MAIN===#####################################

test_fn ()
{
	sg_dev=$1
        sleep 10

        block_dev=$(lsscsi -tg | grep -w $sg_dev |awk '{print $4}'|sed 's/\/dev\///')
        sas_addr=$(lsscsi -tg | grep -w $sg_dev | awk '{print $3}'|sed 's/sas://')
        slot=$(sg_ses -p 0xA $expander | grep "$sas_addr" -B 8 | awk '/Element index/{print $3}')	
	
	sg_ses --index="$slot" --set=2:1=0 "$expander"
        sg_ses --index="$slot" --set=3:5=0 "$expander"

        sleep 10 

        bblock $block_dev

}

###########################===LOCK_DRIVE===################################## 
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
export -f lock_fn test_fn
export -f bblock
export -f smart_chk
export -f smart_test

inotifywait -mr -e create /dev/  | while read line; do lock_fn $(echo $line | grep -o -E sg[0-9]+ ) ;done
