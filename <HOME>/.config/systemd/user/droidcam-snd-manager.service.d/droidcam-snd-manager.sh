#!/bin/bash

function exit_hold () {
	echo $(date +"%T.%3N")" Droidcam-snd-manager: Waiting for SIGTERM from systemd droidcam-snd-manager.service." >> $logfile
	# Endless loop waiting for SIGTERM, keeps the droidcam-snd-manager.service active and makes it possible to view log file even if this script aborted during the config process. Upon SIGTERM the systemd service cleans up these volatile files 
	while true; do read </run/user/$User_ID/droidcam-snd-manager/exit_hold.pipe; done
}

function handle_exit () {
	echo $(date +"%T.%3N")" Driodcam-snd-manager: SIGTERM received. Prepareing for exit. Attempting to execute: pulse: "$pulse_exit_state" ALSA: "$ALSA_mod_exit_state" pulse state: "$pulse_source_state". ALSA state: "$ALSA_snd_aloop_module_state"." >> $logfile
	if [[ "$pulse_exit_state" == "remove" && "$pulse_source_state" == "managed" ]]; then
		if [ $(pactl list sources | grep -A 100 "Owner Module: "$pulse_source_module |  grep --max-count 1  "device.description" | awk '{print $3}')  == "\"DroidCam\"" ]; then
			echo $(date +"%T.%3N")" Driodcam-snd-manager: PulseAudio source Owner Module: "$pulse_source_module" appears to be Droicam, Removing." >> $logfile
			pactl unload-module $pulse_source_module
			if [ $? -eq 0 ]; then
				echo $(date +"%T.%3N")" Driodcam-snd-manager: PulseAudio source removed successfully." >> $logfile
				pulse_source_state="removed"
			else
				echo $(date +"%T.%3N")" Droidcam-snd-manager: PulseAudio source removal failed." >> $logfile
				pulse_source_state="failed"
			fi
		else
			echo $(date +"%T.%3N")" Droidcam-snd-manager: PulseAudio source description does not look like droicam. Not removed." >> logfile
			pulse_source_state="failed"
		fi
	fi
	if [ "$pulse_source_state" == "unmanaged" ]; then
        	echo $(date +"%T.%3N")" Driodcam-snd-manager: PulseAudio source is unmanaged, a failure occured during PulseAudio configuration. Leaving PulseAudio config unchanged." >> $logfile
        fi
	if [[ "$pulse_exit_state" == "keep" && "$pulse_source_state" == "managed" ]]; then
                echo $(date +"%T.%3N")" Driodcam-snd-manager: droidcam.desktop requested to keep PulseAudio config on exit. Leaving PulseAudio config unchanged." >> $logfile
        fi
	if [[ "$ALSA_mod_exit_state" == "remove" && "$ALSA_snd_aloop_module_state" == "managed" ]]; then
		echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA snd-aloop module reported as managed, attempting to remove." >> $logfile
		remove_ALSA_snd_aloop
	fi
	if [[ "$pulse_source_state" == "failed" && "$ALSA_mod_exit_state" == "remove" && "$ALSA_snd_aloop_module_state" == "managed" ]]; then
		echo $(date +"%T.%3N")" Droidcam-snd-manager: PulseAudio source removal failed. ALSA snd-aloop module reports managed, will attempt to remove as requested by Droidcam." >> $logfile
		remove_ALSA_snd_aloop
	fi
	if [ "$ALSA_mod_exit_state" == "keep" ]; then echo $(date +"%T.%3N")" Droidcam-snd-manager: snd_aloop module was already inserted when DroidCam started. Not attempting ALSA snd_loop module removal." >> $logfile; fi
	echo $(date +"%T.%3N")" Droidcam-snd-manager: Exiting." >> $logfile

}

get_snd_aloop_index () {
	ALSA_snd_aloop_index=$(cat /proc/asound/modules | grep -w snd_aloop | awk '{print $1}')
if [ "$ALSA_snd_aloop_index" != "" ]; then	
	echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA reports snd_aloop module at index: "$ALSA_snd_aloop_index >> $logfile
else
	echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA reports no snd_aloop module.">> $logfile
	ALSA_snd_aloop_index="not_available"
fi
}


function remove_ALSA_snd_aloop () {
	echo $(date +"%T.%3N")" Droidcam-snd-manager: requesting ALSA-snd-aloop module state." >> $logfile
	( echo "state" > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout
        read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
        if [ "$REPLY" == "inserted" ]; then
        	echo $(date +"%T.%3N")" Droidcam-snd-manager: requesting ALSA-snd-aloop module index." >> $logfile
                ( echo "index" > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout
                read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
                if [ "$REPLY" == "$ALSA_snd_aloop_index" ]; then
                	echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA module state and index match those configured initially. Requesting ALSA-snd-aloop module removal." >> $logfile
                        ( echo "remove" > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout
                        read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
                        if [ "$REPLY" == "index" ]; then
                        	( echo $droidcam_snd_aloop_index > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout
                                read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
                                if [ "$REPLY" == "0" ]; then
                                	echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA module successfully removed." >> $logfile
					LSA_snd_aloop_module_state="removed"
                                else
                                        echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA module removal failed or timeout." >> $logfile
                                fi
                    	else
                        	echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for ALSA-snd-aloop-manager." >> $logfile
                      	fi

          	else
                	if [ "$REPLY" != "" ]; then
                        	echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA module index does not match that expected by droidcam-snd-manager." >> $logfile
                      	else
                            	echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for response from ALSA-snd-aloop-manager." >> $logfile
                       	fi
             	fi
 	else
       		if [ "$REPLY" == "free" ]; then
                	echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA-snd-aloop-manager reports snd-aloop  module is not loaded." >> $logfile
              	else
                       	echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for response from ALSA-snd-aloop-manager." >> $logfile
                fi
     	fi
	if [ "$ALSA_snd_aloop_module_state" != "removed" ]; then ALSA_snd_aloop_module_state="failed"; fi
}

function timeout_child () {
    #trap -- "" SIGTERM
    child=$!
    timeout=$1
    (
            sleep $timeout
	    if [ $( ps -o pid= -o comm= --ppid $$ | grep -o $child ) ]; then 
		    kill -9 $child
	    fi
    ) &
    wait $child > /dev/null 2>&1
}

function start_droidcam_get_ALSA_data () {
	echo $(date +"%T.%3N")" Droidcam-snd-manager: Starting DroidCam and attempting to obtain ALSA information." >> $logfile
	( echo 'start' > /run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout
        read -t $pipe_timeout <>/run/user/$User_ID/droidcam-snd-manager/droidcam_man_ctrl.pipe
        if [ "$REPLY" != "" ]; then
	        echo $(date +"%T.%3N")" Droidcam-snd-manager: Droidcam Application reports its PID as: "$REPLY >> $logfile
                droidcam_PID=$REPLY
	else
        	echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for PID from DroidCam. Maybe it did not start successfully." >> $logfile
        fi
        ( until [ $(ls -l /proc/$droidcam_PID/fd 2>/dev/null | grep -c /dev/snd) -gt 0 ]; do :;done ) & timeout_child $pipe_timeout
        if [ $(ls -l /proc/$droidcam_PID/fd 2>/dev/null | grep -c /dev/snd) -gt 0 ]; then
        	droidcam_ALSA_pcm=$(ls -l /proc/$droidcam_PID/fd/ | grep /dev/snd/ | awk '{print $NF}' | sed -n -e 's/^.*D//p' | grep -o ^[0-1])
                echo $(date +"%T.%3N")" Droidcam-snd-manager: DroidCam registered with snd_aloop module on PCM channel: "$droidcam_ALSA_pcm >> $logfile
                if [ "$droidcam_ALSA_pcm" == "1" ];then
                	pulse_ALSA_pcm="0"
                else
                	pulse_ALSA_pcm="1"
                fi
	else
        	echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for DroidCam to register with snd_aloop module." >> $logfile
                echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA state unknown. Making no attempt to manage PulseAudio" >> $logfile
                ( echo 'start' > /run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout
                exit_hold
     	fi
        for sub_ch in {0..7..1}; do
        	if [ $(cat /proc/asound/card${ALSA_snd_aloop_index}/pcm${droidcam_ALSA_pcm}p/sub${sub_ch}/status 2>/dev/null | grep owner_pid | awk '{print $3}' | grep -c $droidcam_PID) -gt 0 ]; then
                	echo $(date +"%T.%3N")" Droidcam-snd-manager: Found Droidcam on sub-channel: "$sub_ch >> $logfile
                	droidcam_sub_ch=$sub_ch
                	ALSA_pcm_stream_state="registered"
              	fi
      	done
        if [ "$droidcam_sub_ch" == "unknown" ]; then
        	echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA snd_aloop sub-channel unknown. Making no attempt to manage PulseAudio" >> $logfile
                ( echo 'start' > /run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout
                exit_hold
     	fi
}


trap handle_exit EXIT


pipe_timeout="1"
droidcam_snd_aloop_index="31"
droidcam_pcm_reg_delay="1"
droidcam_ALSA_pcm="unknown"
droidcam_sub_ch="unknown"
droidcam_PID="unknown"
User_ID=$UID
ALSA_snd_aloop_module_state="unknown"
ALSA_pcm_stream_state="unknown"
ALSA_snd_aloop_index="unknown"
pulse_source_state="unknown"
pulse_ALSA_pcm=""
pulse_source_module="unknown"
pulse_exit_state="unknown"
ALSA_mod_exit_state="unknown"


logfile=/run/user/$User_ID/droidcam-snd-manager/log

# Creation of volatule run time directory and named pipes is done from this script and the droidcam.sh (desktop) script to ensure no data is lost. As we have potential for a 'race'.
if [ ! -d "/run/user/$User_ID/droidcam-snd-manager" ]; then mkdir /run/user/$User_ID/droidcam-snd-manager 2>/dev/null; fi

# Using a single pipe to efficiently hold the service through blocking on a 'read' at the end of the script.
echo $(date +"%T.%3N")" Droidcam-snd-manager: Creating 'exit_hold.pipe' named pipe." >> $logfile
mkfifo /run/user/$User_ID/droidcam-snd-manager/exit_hold.pipe
mkfifo /run/user/$User_ID/droidcam-snd-manager/pa_event.pipe
# Create named pipes to communicate with droidcam.desktop script.
# The pipes are opened RW (<>) to allow timeouts with read. Otherwise the pipe blocks until the sender supplies data and read timeout never happens.. 
# The writes are done in a subshell with a timeout to kill the PID of the subshell. This ensures writes dont block if the receiver does not consume. 
# The pipes are uni-directional.
# The exit_hold pipe is used simply to stop the script exiting without consuming any CPU cycles whilst it waits for a SIGTERM from systemd droidcam-monitor.service
echo $(date +"%T.%3N")" Droidcam-snd-manager: Creating named-pipes between app and monitor." >> $logfile
if [ ! -p "/run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe" ]; then mkfifo /run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe; fi
if [ ! -p "/run/user/$User_ID/droidcam-snd-manager/droidcam_man_ctrl.pipe" ]; then mkfifo /run/user/$User_ID/droidcam-snd-manager/droidcam_man_ctrl.pipe; fi
if [ ! -f "/run/user/$User_ID/droidcam-snd-manager/log" ]; then touch /run/user/$User_ID/droidcam-snd-manager/log; fi

echo $(date +"%T.%3N")" Droidcam-snd-manager: Starting droidcam-snd-manager on behalf of UID: "$User_ID >> $logfile

echo $(date +"%T.%3N")" Droidcam-snd-manager: Sending 'config' request on droidcam_app_ctrl.pipe" >> $logfile
( echo 'PULSE' > /run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout


echo $(date +"%T.%3N")" Droidcam-snd-manager: Waiting for pulseaudio configuration from droidcam.desktop." >> $logfile

read -t $pipe_timeout <>/run/user/$User_ID/droidcam-snd-manager/droidcam_man_ctrl.pipe
if [ "$REPLY" != "" ]; then echo $(date +"%T.%3N")" Droidcam-snd-manager: Received data on droidcam_man_ctrl.pipe: " $REPLY >> $logfile; fi


case $REPLY in
	"pa_keep")
		pulse_exit_state="keep"
		echo $(date +"%T.%3N")" Droidcam-snd-manager: Will keep pulseaudio source we attempt to create on exit." >> $logfile
	;;
	"pa_remove")
		pulse_exit_state="remove"
		echo $(date +"%T.%3N")" Droidcam-snd-manager: Will attempt to remove pulseaudio source on exit." >> $logfile
	;;
	*)
                echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for config from desktop. Exiting" >> $logfile
		exit_hold
	;;
esac

( echo 'ALSA' > /run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout


echo $(date +"%T.%3N")" Droidcam-snd-manager: Waiting for ALSA snd-aloop index configuration from droidcam.desktop." >> $logfile
read -t $pipe_timeout <>/run/user/$User_ID/droidcam-snd-manager/droidcam_man_ctrl.pipe
if [ "$REPLY" != "" ]; then echo $(date +"%T.%3N")" Droidcam-snd-manager: Received data on droidcam_man_ctrl.pipe: " $REPLY >> $logfile; fi


case $REPLY in
        [0-9]|[1-2][0-9]|3[0-1]|"any")
                droidcam_snd_aloop_index=$REPLY
                echo $(date +"%T.%3N")" Droidcam-snd-manager: Received ALSA index: "$REPLY" from droidcam.desktop." >> $logfile
        ;;
        *)
                echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for ALSA index config from desktop. Will default to 31" >> $logfile
                exit_hold
        ;;
esac


if [ ! -p "/run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe" ]
then
        echo $(date +"%T.%3N")" Droidcam-snd-manager: Can't find ALSA-snd-aloop_cmd.pipe. Is ALSA-snd-aloop-manager.service running?." >> $logfile
	echo $(date +"%T.%3N")" Droidcam-snd-manager: Attempting to find snd-aloop moduel interface index." >> $logfile
	get_snd_aloop_index
	if [ "$ALSA_snd_aloop_index" != "not_available" ]; then
		echo $(date +"%T.%3N")" Droidcam-snd-manager: Will proceed with ALSA module configuration 'unmanaged'." >> $logfile
		ALSA_snd_aloop_module_state="unmanaged"
	else
		echo $(date +"%T.%3N")" Droidcam-snd-manager: Can not find ALSA snd_aloop module. Starting droidcam without attempting any further configuration." >> $logfile
        	( echo 'start' > /run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout
		exit_hold
	fi
fi

if [ "$ALSA_snd_aloop_module_state" != "unmanaged" ]; then

	echo $(date +"%T.%3N")" Droidcam-snd-manager: requesting ALSA-snd-aloop module state." >> $logfile
	( echo "state" > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout

	read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
	if [ "$REPLY" != "" ]; then echo $(date +"%T.%3N")" Droidcam-snd-manager: 'state' response from ALSA-snd-aloop-manager: "$REPLY >> $logfile; fi

	case $REPLY in
		"free")
			echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA-snd-aloop-manager reports snd-aloop module is free. Requesting insertion." >> $logfile
			echo $(date +"%T.%3N")" Droidcam-snd-manager: Starting 'pactl subscribe' to monitor for UDEV triggered card." >> $logfile
			( pactl subscribe > /run/user/$User_ID/droidcam-snd-manager/pa_event.pipe ) &
			pa_sub_PID=$!
			( while true; do read -t $pipe_timeout </run/user/$User_ID/droidcam-snd-manager/pa_event.pipe; if [[ "$REPLY" =~ "'new' on card" ]]; then echo $REPLY > /run/user/$User_ID/droidcam-snd-manager/pa_card; break;fi;done ) &
			pa_new_card_PID=$!
			( echo "insert" > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout
			read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
			if [ "$REPLY" == "index" ]; then
				echo $(date +"%T.%3N")" Droidcam-snd-manager: Sending ALSA index: "$droidcam_snd_aloop_index" to ALSA-snd-aloop-manager." >> $logfile
                		( echo $droidcam_snd_aloop_index > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout
				read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
				if [ "$REPLY" == "" ]; then
                        		echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed-out waiting for ALSA-snd-aloop-manager, module insertion." >> $logfile
					echo $(date +"%T.%3N")" Droidcam-snd-manager: Reporting ALSA as 'failed'" >> $logfile
					ALSA_snd_aloop_module_state="failed"
                		fi
                		if [ "$REPLY" == "0" ]; then
                			echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA-snd-aloop-manager reports snd-aloop module is inserted." >> $logfile
					wait $pa_new_card_PID
					kill $pa_sub_PID
					read </run/user/$User_ID/droidcam-snd-manager/pa_card
					udev_pa_card=$(echo $REPLY | awk '{print $5}')
					if [ "$udev_pa_card" != "" ]; then
						udev_pa_module="$(pactl list cards | grep -A 100 $udev_pa_card | grep -A 10 "alsa_card.platform-snd_aloop.0" | grep --max-count 1  "Owner Module" | awk '{print $3}')"
						if [ "$udev_pa_module" != "" ]; then
							echo $(date +"%T.%3N")" Droidcam-snd-manager: Attempting to remove UDEV triggered pulse audio card: "$udev_pa_card" Owner Module: "$udev_pa_module >> $logfile
							pactl unload-module $udev_pa_module
						else 
							echo $(date +"%T.%3N")" Droidcam-snd-manager: PulseAudio config does not list Card: "$udev_pa_card" as type (platform-snd_aloop). Skipping card removal" >> $logfile
						fi
					else
						echo $(date +"%T.%3N")" Droidcam-snd-manager: Did not detect a UDEV triggered card addition. Skipping removal" >> $logfile
					fi
					echo $(date +"%T.%3N")" Droidcam-snd-manager: Requesting ALSA snd-aloop module index." >> $logfile
                			( echo "index" > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout
                        		read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
                        		if [[ "$REPLY" != "-1" || "$REPLY" != "" ]]; then
						echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA snd-aloop module index reported as: "$REPLY >> $logfile
						ALSA_snd_aloop_index=$REPLY
						echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA snd-aloop module state 'managed'." >> $logfile
						ALSA_snd_aloop_module_state="managed"
						ALSA_mod_exit_state="remove"
					else
						echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for ALSA-snd-loop-manager service. ALSA snd-aloop module state 'unmanaged'" >> $logfile
						ALSA_snd_aloop_module_state="unmanaged"
						ALSA_mod_exit_state="keep"
					fi
				fi
               		 	if [ "$REPLY" == "-1" ]; then
                			echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA-snd-aloop-manager reports snd-aloop failure to insert module." >> $logfile
                        		echo $(date +"%T.%3N")" Droidcam-snd-manager: Reporting ALSA as 'failed'" >> $logfile
					ALSA_snd_aloop_module_state="failed"
                		fi
			else
				echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for index request from ALSA-snd-aloop-manager. Starting droidcam without sound." >> $logfile
				( echo 'start' > /run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout
			fi
		;;
		"inserted")
			echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA-snd-aloop-manager reports snd-aloop module is inserted. Requesting index." >> $logfile
			( echo "index" > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout
        		read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
			if [ "$REPLY" != "" ]; then 
				echo $(date +"%T.%3N")" Droidcam-snd-manager: 'index' response from ALSA-snd-aloop-manager: "$REPLY >> $logfile
				if [ "$REPLY" == "$droidcam_snd_aloop_index" ]; then
					echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA-snd-aloop-manager reports snd-aloop module already inserted using index:"$REPLY". This is the correct index but it already existed." >> $logfile
				else
					echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA-snd-aloop-manager reports snd-aloop module using index:"$REPLY" this is different to that requested by droidcam-desktop." >> $logfile
				fi
				echo $(date +"%T.%3N")" Droidcam-snd-manager: Reporting ALSA as 'unmanaged'." >> $logfile
				ALSA_snd_aloop_index=$REPLY
				ALSA_snd_aloop_module_state="unmanaged"
			fi
			if [ "$REPLY" == "" ]; then
                       		echo $(date +"%T.%3N")" Droidcam-snd-manager: 'index' response from ALSA-snd-aloop-manager timed out." >> $logfile
				echo $(date +"%T.%3N")" Droidcam-snd-manager: Reporting ALSA as 'failed'" >> $logfile
				ALSA_snd_aloop_module_state="failed"
                	fi
		;;
		*)
			echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for ALSA-snd-aloop-manager." >> $logfile
			ALSA_snd_aloop_module_state="failed"
		;;
	esac
fi


case $ALSA_snd_aloop_module_state in
	"managed")
		start_droidcam_get_ALSA_data
	;;
	"unmanaged")
		echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA snd_aloop module's current state will be maintained on exit." >> $logfile
		ALSA_mod_exit_state="keep"
		start_droidcam_get_ALSA_data
	;;
	*)
		echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA state unknown or failed. Starting Droidcam Application. No further configuration cen be attempted." >> $logfile
		( echo 'start' > /run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout
		exit_hold
	;;
esac



case $ALSA_pcm_stream_state in
	"registered")
		if [ $(pactl list sources | grep -A 100 "Description: DroidCam" |  grep --max-count 1  "device.description" | awk '{print $3}')  == "\"DroidCam\"" ]; then
			echo $(date +"%T.%3N")" Droidcam-snd-manager: PulseAudio microphone source already exists. If snd-aloop module is still using the same index since last time DroidCam was used this source probably still works. Skipping PulseAudio source creation" >> $logfile
			pulse_source_module=$(pactl list sources | grep -A 10 "Description: DroidCam" |  grep --max-count 1  "Owner Module:" | awk '{print $3}')
			echo $(date +"%T.%3N")" Droidcam-snd-manager: PulseAudio source 'DroidCam' detected with Owner Module: "$pulse_source_module >> $logfile
			pulse_source_state="managed"
			exit_hold
		fi
		echo $(date +"%T.%3N")" Droidcam-snd-manager: Creating PulseAudio microphone source." >> $logfile
		#pulse_source_module=$(pactl load-module module-alsa-source rate=16000 channels=1 source_properties=device.description=DroidCam device=hw:Loopback,1,0;)
		pulse_source_module=$(pactl load-module module-alsa-source source_properties=device.description=DroidCam device=hw:${ALSA_snd_aloop_index},${pulse_ALSA_pcm},${droidcam_sub_ch};)
		echo $(date +"%T.%3N")" Droidcam-snd-manager: PulseAudio source created. Module: "$pulse_source_module >> $logfile
	if [ $? -eq 0 ]; then
		echo $(date +"%T.%3N")" Droidcam-snd-manager: PulseAudio microphone source created successfully." >> $logfile
		pulse_source_state="managed"

	else
		echo $(date +"%T.%3N")" Droidcam-snd-manager: Creating PulseAudio microphone source failed." >> $logfile
		pulse_source_state="unmanaged"
	fi
	;;
	"failed")
		echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA pcm stream failed to establish where expected. Leaving PulseAudio configuration unchanged on exit." >> $logfile
		pulse_source_state="unmanaged"
	;;
	*)
		echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA pcm stream state unknown. Leaving PulseAudio configuration unchanged on exit." >> $logfile
		pulse_source_state="unmanaged"
	;;
esac


exit_hold


