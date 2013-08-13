#!/bin/bash

#########################################################################################
# inotifywait (endless loop) ---> lock_fn (sgX) ---> test_fn (sgX) ---> main (sdX) ---- #
#                                                                                     | #
#             -----------------<---------------------------------------------------<--- #
#             |                               |                                         #
#             |                               |                                         #
#           main_wd_hitachi (sdX)       main_generic (sdX)                              #
#             |                               |                                         #
#           [smart_test (sdX)]          [smart_test (sdX)]                              #
#             |                               |                                         #
#            end                             end                                        #
#########################################################################################


expander=$(sg_map -x | awk '{if ( $6 == 13 ) { print $1 }}')
SERVER=

export expander

if [ -z $expander ]; then
  echo "++++++++++++++++++++++++++++++++++++++++++++++++"
  echo "JBOD is apsent, please connect one to this server"
  echo "++++++++++++++++++++++++++++++++++++++++++++++++"
  exit 1
fi 

#############################===LIFGH_DOWN===###############################
light_down_slot ()
{


light_off ()
{
   sg_ses --index="$slot" --set=2:1=0 "$expander"
   sg_ses --index="$slot" --set=3:5=0 "$expander"
}

check_enclosure ()
{
if [ $( sg_ses -p 0x2 "$expander" | grep "Hot spare" -B 2 |grep "Not installed" -c) -eq 24 ]; then
     #echo "ENCLOSURE IS EMPTY"
     for i in `seq 0 23`;do sg_ses --index="$i" --set=2:1=0 "$expander" 2>/dev/null ; sg_ses --index="$i" --set=3:5=0 "$expander" 2>/dev/null
     done     
     dmesg -c
     sleep 10
   fi
}

export -f light_off
export -f check_enclosure

while :; do
  sg_ses -p 0x2 "$expander" | grep "Hot spare" -B 2 |grep "Not installed" -B 1 | awk '/Element/{print $2}' | while read slot
   do 
      light_off $slot
      check_enclosure
   sleep 1
   done
done
}	

light_down_slot &  

#############################===SMART_TEST===###############################
smart_test ()                                                                                 # collects SMART arttributes and writes them in var
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

#############################===ERASE===#####################################

erase ()                                                                                       # erase partition table
 
{
fdisk /dev/$1 <<EOF
o
w
EOF
 
sectors=$(($(fdisk -s /dev/$1)-102400)) 
 
dd if=/dev/zero of=/dev/$1 bs=1M count=100
dd if=/dev/zero of=/dev/$1 bs=1k seek=$sectors count=102400
}

#############################===MAIN===#####################################
main ()                                                                                       # check drive for SMART attributes and highligh it
                                                                                              # as FAILED or VALID
{
eval `smart_test /dev/$1` 

data=$(echo "MODEL="$model"&SERIAL_NUM="$serial"&POH="$poh"&READ_ERROR_RATE="$read_error"&CURRENT_PEND=""$pend""&REALLOC=""$rsec""&OFFLINE_UNC=""$offunc""&REALL_EVENT=""$revent""&HEALTH="$health"&ATA_ERROR="$ata_err)

if [ $rsec -gt 4 -o $pend -gt 10 -o $offunc -gt 10 -o $revent -gt 10 -o  $health != "PASSED" -o -n "$ata_err" ] || [ -z $model -a -z $serial ]; then
   #echo  "This drive is broken"
   sleep 3
      curl -v -d "RESULT=FAILED&$data" $SERVER 
        sg_ses --index="$slot" --set=3:5=1 "$expander"
         exit 1
else
   curl -v -d "RESULT=VALID&$data" $SERVER 
   sg_ses --index="$slot" --set=2:1=1 "$expander"
    exit 0
fi 2>/dev/null

}

#############################===PRE-MAIN===#####################################

test_fn ()
{
sg_dev=$1

sleep 15

block_dev=$(sg_map -x | awk '/'$sg_dev'/{print $NF}' | sed 's/\/dev\///')                     # device block name, e.g. /dev/sdb
 sas_addr=$(cat /sys/class/scsi_generic/"$sg_dev"/device/sas_address)                         # SAS address of the device
   slot=$(sg_ses -p 0xA $expander | grep "$sas_addr" -B 8 | awk '/Element index/{print $3}')  # which slot is in the BP

sleep 15                                                                                      # waiting for error messages in dmesg

error_msg=$(dmesg | grep $block_dev | grep -i error)                                          # if device has errors at start

  eval `smart_test /dev/$1`
 
  data=$(echo "MODEL="$model"&SERIAL_NUM="$serial"&POH="$poh"&READ_ERROR_RATE="$read_error"&CURRENT_PEND=""$pend""&REALLOC=""$rsec""&OFFLINE_UNC=""$offunc""&REALL_EVENT=""$revent""&HEALTH="$health"&ATA_ERROR="$ata_err) 
   
if [ -z "$block_dev" ]; then 			                                              # check if block name is not empty and device doesn't have errors
    curl -v -d "RESULT=FAILED&"$data"&REASON=NO_BLOCK_DEV" $SERVER 
     sg_ses --index="$slot" --set=3:5=1 "$expander"
      exit 1
elif [ -n "$error_msg" ]; then                                                                # looking for errors in dmesg
    curl -v -d "RESULT=FAILED&"$data"&REASON=ERRORS_IN_DMESG" $SERVER 
     sg_ses --index="$slot" --set=3:5=1 "$expander"
      exit 1
else
    main $block_dev                                                                           # starts main test, it means that device has block name, and doesn't have 
                                                                                              #errors
fi

}


lock_fn ()                                                                                    #func blocks the device name (/dev/sgX) to avoid multiply operations 
                                                                                              #with one device
{
(
   [ -n "$1" ] || exit 0
   flock -n /dev/$1 -c "test_fn $1"                                                           # $1 — is an SG device of new drive, e.g. sg1
   sleep 5
) &
}

#############################===START_HERE===##############################
export -f test_fn
export -f main
export -f lock_fn
export -f smart_test
export -f erase

inotifywait -mr -e create /dev/  | while read line; do lock_fn $(echo $line | grep -o -E sg[0-9]+ ) ;done 


