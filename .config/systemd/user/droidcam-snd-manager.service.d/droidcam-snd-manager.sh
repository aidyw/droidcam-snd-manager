#!/bin/bash

function handle_exit () {
	echo $(date +"%T.%3N")" Driodcam-snd-manager: SIGTERM received. Prepareing for exit. Attempting to execute: pulse: "$pulse_exit_state" ALSA: "$ALSA_mod_exit_state" pulse state: "$pulse_source_state". ALSA state: "$ALSA_snd_aloop_module_state"." >> $logfile
	if [[ "$pulse_exit_state" == "remove" && "$pulse_source_state" == "managed" ]]; then
		if [ $(pactl list sources | grep -A 100 "Owner Module: "$pa_source_module |  grep --max-count 1  "device.description" | awk '{print $3}')  == "\"DroidCam\"" ]; then
			echo $(date +"%T.%3N")" Driodcam-snd-manager: PulseAudio source Owner Module: "$pa_source_module" appears to be Droicam, Removing." >> $logfile
			pactl unload-module $pa_source_module
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
	if [[ "$ALSA_mod_exit_state" == "remove" && "$ALSA_snd_aloop_module_state" == "managed" ]]; then
		echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA snd-aloop module reported as managed, attempting to remove." >> $logfile
		remove_ALSA_snd_aloop
	fi
	if [[ "$pulse_source_state" == "failed" && "$ALSA_mod_exit_state" == "remove" && "$ALSA_snd_aloop_module_state" == "managed" ]]; then
		echo $(date +"%T.%3N")" Droidcam-snd-manager: PulseAudio source removal failed. ALSA snd-aloop module reports managed, will attempt to remove as requested." >> $logfile
		remove_ALSA_snd_aloop
	fi
	if [ "$ALSA_snd_aloop_module_state" == "unmanaged" ]; then echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA snd-aloop module reports state unmanaged. Leaving configuration in place." >> $logfile; fi
	echo $(date +"%T.%3N")" Droidcam-snd-manager: Exiting." >> $logfile

}

function remove_ALSA_snd_aloop () {
	echo $(date +"%T.%3N")" Droidcam-snd-manager: requesting ALSA-snd-aloop module state." >> $logfile
	( echo "state" > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout
        read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
        if [ "$REPLY" == "inserted" ]; then
        	echo $(date +"%T.%3N")" Droidcam-snd-manager: requesting ALSA-snd-aloop module index." >> $logfile
                ( echo "index" > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout
                read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
                if [ "$REPLY" == "$droidcam_snd_aloop_index" ]; then
                	echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA module state and index seem to match droidcam config. Requesting ALSA-snd-aloop module removal." >> $logfile
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




trap handle_exit EXIT


logfile=/run/ALSA-snd-aloop-manager/log

pipe_timeout="1"
droidcam_snd_aloop_index="31"
droidcam_pcm_reg_delay="1"
ALSA_snd_aloop_module_state="unknown"
ALSA_pcm_stream_state="unknown";
pulse_source_state="unknown"
pulse_exit_state="unknown"
ALSA_mod_exit_state="unknown"

echo $(date +"%T.%3N")" Droidcam-snd-manager: Starting droidcam-snd-manager." >> $logfile
if [ ! -d "/run/user/$UID/droidcam-snd-manager" ]; then mkdir /run/user/$UID/droidcam-snd-manager; fi

# Using a single pipe to efficiently hold the service through blocking on a 'read' at the end of the script.
echo $(date +"%T.%3N")" Droidcam-snd-manager: Creating 'exit_hold.pipe' named pipe." >> $logfile
mkfifo /run/user/$UID/droidcam-snd-manager/exit_hold.pipe
mkfifo /run/user/$UID/droidcam-snd-manager/pa_event.pipe
# Create named pipes to communicate with droidcam.desktop script.
# This is done from this script and the droidcam.sh (desktop) script to ensure no data is lost. As we have potential for a 'race'.
# The pipes are opened RW (<>) to allow timeouts with read. Otherwise the pipe blocks until the sender supplies data and read timeout never happens.. 
# The writes are done in a subshell with a timeout to kill the PID of the subshell. This ensures writes dont block if the receiver does not consume. 
# The pipes are uni-directional.
# The exit_hold pipe is used simply to stop the script exiting without consuming any CPU cycles whilst it waits for a handshake from systemd droidcam-monitor.service
echo $(date +"%T.%3N")" Droidcam-snd-manager: Creating named-pipes between app and monitor." >> $logfile
if [ ! -p "/run/user/$1/droidcam-snd-manager/droidcam_app_ctrl.pipe" ]; then mkfifo /run/user/$1/droidcam-snd-manager/droidcam_app_ctrl.pipe; fi
if [ ! -p "/run/user/$1/droidcam-snd-manager/droidcam_mon_ctrl.pipe" ]; then mkfifo /run/user/$1/droidcam-snd-manager/droidcam_mon_ctrl.pipe; fi

echo $(date +"%T.%3N")" Droidcam-snd-manager: Sending 'config' request on droidcam_app_ctrl.pipe" >> $logfile
( echo 'pulse' > /run/user/$1/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout


echo $(date +"%T.%3N")" Droidcam-snd-manager: Waiting for pulseaudio configuration from droidcam.desktop." >> $logfile

read -t $pipe_timeout <>/run/user/$1/droidcam-snd-manager/droidcam_mon_ctrl.pipe
if [ "$REPLY" != "" ]; then echo $(date +"%T.%3N")" Droidcam-snd-manager: Received data on droidcam_mon_ctrl.pipe: " $REPLY >> $logfile; fi


case $REPLY in
	"pa_keep")
		pulse_exit_state="keep"
		echo $(date +"%T.%3N")" Droidcam-snd-manager: Will keep snd-aloop module and pulseaudio source on exit." >> $logfile
	;;
	"pa_remove")
		pulse_exit_state="remove"
		echo $(date +"%T.%3N")" Droidcam-snd-manager: Will remove snd-aloop module and pulseaudio source on exit." >> $logfile
	;;
	*)
                echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for config from desktop. Exiting" >> $logfile
		exit
	;;
esac

( echo 'ALSA' > /run/user/$1/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout


echo $(date +"%T.%3N")" Droidcam-snd-manager: Waiting for ALSA snd-aloop index configuration from droidcam.desktop." >> $logfile
read -t $pipe_timeout <>/run/user/$1/droidcam-snd-manager/droidcam_mon_ctrl.pipe
if [ "$REPLY" != "" ]; then echo $(date +"%T.%3N")" Droidcam-snd-manager: Received data on droidcam_mon_ctrl.pipe: " $REPLY >> $logfile; fi


case $REPLY in
        [0-9]|[1-2][0-9]|"30"|"31")
                droidcam_snd_aloop_index=$REPLY
                echo $(date +"%T.%3N")" Droidcam-snd-manager: Received ALSA index: "$REPLY" from droidcam.desktop." >> $logfile
        ;;
        *)
                echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for ALSA index config from desktop. Will default to 31" >> $logfile
                exit
        ;;
esac


if [ ! -p "/run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe" ]
then
        echo $(date +"%T.%3N")" Droidcam-snd-manager: Can't find ALSA-snd-aloop_cmd.pipe. Is ALSA-snd-aloop-manager.service running?." >> $logfile
        echo $(date +"%T.%3N")" Droidcam-snd-manager: Starting droidcam without attempting sound configuration." >> $logfile
	( echo 'start' > /run/user/$UID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout
        exit
fi


echo $(date +"%T.%3N")" Droidcam-snd-manager: requesting ALSA-snd-aloop module state." >> $logfile
( echo "state" > /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe ) & timeout_child $pipe_timeout

read -t $pipe_timeout <>/run/ALSA-snd-aloop-manager/snd-aloop_response.pipe
if [ "$REPLY" != "" ]; then echo $(date +"%T.%3N")" Droidcam-snd-manager: 'state' response from ALSA-snd-aloop-manager: "$REPLY >> $logfile; fi

case $REPLY in
	"free")
		echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA-snd-aloop-manager reports snd-aloop module is free. Requesting insertion." >> $logfile
		echo $(date +"%T.%3N")" Droidcam-snd-manager: Starting 'pactl subscribe' to monitor for UDEV triggered card." >> $logfile
		( pactl subscribe > /run/user/$UID/droidcam-snd-manager/pa_event.pipe ) &
		pa_sub_PID=$!
		( while true; do read -t $pipe_timeout </run/user/$UID/droidcam-snd-manager/pa_event.pipe; if [[ "$REPLY" =~ "'new' on card" ]]; then echo $REPLY > /run/user/$UID/droidcam-snd-manager/pa_card; break;fi;done ) &
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
				read </run/user/$UID/droidcam-snd-manager/pa_card
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
				echo $(date +"%T.%3N")" Droidcam-snd-manager: Reporting ALSA as 'managed'" >> $logfile
                		ALSA_snd_aloop_module_state="managed"
				ALSA_mod_exit_state="remove"
			fi
                	if [ "$REPLY" == "-1" ]; then
                		echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA-snd-aloop-manager reports snd-aloop failure to insert module." >> $logfile
                        	echo $(date +"%T.%3N")" Droidcam-snd-manager: Reporting ALSA as 'failed'" >> $logfile
				ALSA_snd_aloop_module_state="failed"
                	fi
		else
			echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for index request from ALSA-snd-aloop-manager. Starting droidcam without sound." >> $logfile
			( echo 'start' > /run/user/$UID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout
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
				echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA-snd-aloop-manager reports snd-aloop module using index:"$REPLY" this is different to that required by droidcam-manager." >> $logfile
			fi
			echo $(date +"%T.%3N")" Droidcam-snd-manager: Reporting ALSA as 'unmanaged'." >> $logfile
			ALSA_snd_aloop_module_state="unmanaged"
		fi
		if [ "$REPLY" == "" ]; then
                        echo $(date +"%T.%3N")" Droidcam-snd-manager: 'index' response from ALSA-snd-aloop-manager timed out." >> $logfile
			echo $(date +"%T.%3N")" Droidcam-snd-manager: Reporting ALSA as 'failed'" >> $logfile
			ALSA_snd_aloop_module_state="failed"
                        break;
                fi
	;;
	*)
		echo $(date +"%T.%3N")" Droidcam-snd-manager: Timed out waiting for ALSA-snd-aloop-manager." >> $logfile
	;;
esac


case $ALSA_snd_aloop_module_state in
	"managed")
		ALSA_pcm_stream_state="unknown"
        	inotifywait --timeout $droidcam_pcm_reg_delay --event open /proc/asound/card$droidcam_snd_aloop_index/pcm0p/info 2>&1 | while read event
        	do
                	trigger="0"
                	case $event in
                        	"Setting up watches.")
                                	echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA PCM watches being created " >> $logfile
                        	;;
                        	"Watches established.")
                                	echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA PCM watches established. Starting Droidcam Application" >> $logfile
                                	( echo 'start' > /run/user/$UID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout
                        	;;
                        	*)
                                	echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA PCM watch triggered: " >> $logfile
                                	trigger="1"
                        	;;
                	esac
                	if [  "$trigger" = 1 ]; then
                        break
                	fi
        	done
        	if [ $(cat /proc/asound/card$droidcam_snd_aloop_index/pcm0p/info 2>/dev/null | grep -c "subdevices_avail: 0" ) -gt 0 ]; then
                	echo $(date +"%T.%3N")" Droidcam-snd-manager: Droidcam registered with ASLA snd-aloop module." >> $logfile
                	ALSA_pcm_stream_state="registered";
        	else
                	ALSA_pcm_stream_state="failed";
        	fi
	;;
	"unmanaged")
		echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA state unmanaged. Starting Droidcam Application sound may be controlled by other. No attempt to manage PulseAudio" >> $logfile
        	( echo 'start' > /run/user/$UID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout
	;;
	*)
		echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA state unknown or failed. Starting Droidcam Application probably without sound." >> $logfile
        	( echo 'start' > /run/user/$UID/droidcam-snd-manager/droidcam_app_ctrl.pipe ) & timeout_child $pipe_timeout
	;;
esac



case $ALSA_pcm_stream_state in
	"registered")
		echo $(date +"%T.%3N")" Droidcam-snd-manager: Creating PulseAudio microphone source." >> $logfile
		pa_source_module=$(pactl load-module module-alsa-source source_properties=device.description=DroidCam device=hw:Loopback,1,0;)
		echo $(date +"%T.%3N")" Droidcam-snd-manager: PulseAudio source created. Index: "$pa_source_module >> $logfile
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
		pulse_exit_state="keep"
		pulse_source_state="unmanaged"
	;;
	*)
		echo $(date +"%T.%3N")" Droidcam-snd-manager: ALSA pcm stream state unknown. Leaving PulseAudio configuration unchanged on exit." >> $logfile
		pulse_exit_state="keep"
		pulse_source_state="unmanaged"
	;;
esac

echo $(date +"%T.%3N")" Droidcam-snd-manager: Waiting for SIGTERM from systemd droidcam-monitor.service." >> $logfile

# Endless loop waiting for SIGTERM
while true; do read </run/user/$UID/droidcam-snd-manager/exit_hold.pipe; done



