#!/bin/bash

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

get_snd_aloop_index () {
	module_index=$(aplay -l | grep -e '^card' | awk '{ print $2, $3 }' | grep -m 1 -e 'Loopback$' | awk '{ print $1 }' | sed 's/://g')
if [ "$module_index" != "" ]; then	
	echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: aplay -l reports 'Loopback' device at index: "$module_index >> $logfile
else
	echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: aplay -l reports no 'Loopback' device found.">> $logfile
fi
}

logfile=/run/ALSA-snd-aloop-manager/log

pipe_TIMEOUT_default="1"


if [ ! -d "/run/ALSA-snd-aloop-manager" ]; then 
	mkdir /run/ALSA-snd-aloop-manager
	touch /run/ALSA-snd-aloop-manager/log
	chmod a+rwx /run/ALSA-snd-aloop-manager/log
	truncate -s 0 /run/ALSA-snd-aloop-manager/log
fi;


echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: starting." >> $logfile

echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Creating named pipes." >> $logfile

mkfifo -m 0666 /run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe
mkfifo -m 0666 /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe



while true; do
	echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: waiting for command." >> $logfile
	read cmd</run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe
	echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Processing cmd: "$cmd >> $logfile
	case $cmd in
		"state")
			get_snd_aloop_index
			if [ "$module_index" != "" ]; then
				echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Module appears to be inserted. Reporting 'inserted'." >> $logfile
                        	( echo "inserted" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
			else
				echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Module appears to be free. Reporting 'free'." >> $logfile
                                ( echo "free" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
			fi
		;;
		"index")
                        get_snd_aloop_index
                        if [ "$module_index" != "" ]; then
                                ( echo $module_index > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
                        else
                                ( echo "-1" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
                        fi
                ;;
		"insert")
			echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Requesting ALSA index." >> $logfile
        		( echo "index" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
			read -t $pipe_TIMEOUT_default <>/run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe
			if [[ "$REPLY" == [0-9] || "$REPLY" == [1-2][0-9] || "$REPLY" == "30" || "$REPLY" == "31" ]]; then 
				echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Received index data: "$REPLY >> $logfile
				get_snd_aloop_index
				if [ "$module_index" != "" ]; then
                                	echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Module already inserted" >> $logfile
                                	( echo "-1" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
                        	else
                                	echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Attempting to insert module" >> $logfile
                                	echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: using params: index="$REPLY" pcm_substreams=1" >> $logfile
                                	modprobe ALSA-snd-aloop-manager index=$REPLY pcm_substreams=1 
                                	if [ $? -eq 0 ]; then
                                        	echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Inserted successfully" >> $logfile
                                        	( echo "0" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
                                	else
                                        	echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Module failed to insert." >> $logfile
                                        	( echo "-1" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
                                	fi
                        	fi

			else
				echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Timed out waiting for index data or index:"$REPLY" out-of-range." >> $logfile
			fi
		;;
		"remove")
			echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Requesting ALSA index." >> $logfile
			( echo "index" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
			read -t $pipe_TIMEOUT_default <>/run/ALSA-snd-aloop-manager/snd-aloop_cmd.pipe
                        if [[ "$REPLY" == [0-9] || "$REPLY" == [1-2][0-9] || "$REPLY" == "30" || "$REPLY" == "31" ]]; then
				echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Received index data: "$REPLY >> $logfile
                                get_snd_aloop_index
				if [ "$module_index" != "$REPLY" ]; then
                                        echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Module does not exist at requested index:"$REPLY". Request aborted." >> $logfile
                                        ( echo "-1" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
                                else
					echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Module found at index: "$REPLY". Attempting removal." >> $logfile
					modprobe -r ALSA-snd-aloop-manager
					if [ $? -eq 0 ]; then
                                                echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Removed successfully" >> $logfile
                                                ( echo "0" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
                                        else
                                                echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Module removal failed." >> $logfile
                                                ( echo "-1" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
                                        fi
				fi
			fi
		;;
		*)
			echo $(date +"%T.%3N")" ALSA-snd-aloop-manager: Unknown command: "$cmd >> $logfile
			( echo "-1" > /run/ALSA-snd-aloop-manager/snd-aloop_response.pipe ) & timeout_child $pipe_TIMEOUT_default
		;;
	esac

done

