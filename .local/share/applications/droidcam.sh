#"/bin/bash

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


# PULSE_ACTION_ON_EXIT:
# Choose 'pa_remove' to strip out the droidcam microphone source from pulseaudio when droidcam exits.
# Choose 'pa_keep' to retain the droidcam microphone source within pulseaudio when droidcam exits.

# ALSA_INDEX:
# Define ALSA index for snd-aloop module (0 - 31) or "any" to take next available index. Note if droidcam-snd-manager.service does not find the snd-aloop module, it will request insertion by ALSA-snd-aloop-manager.service
# If ALSA-snd-aloop-manager.service successfully inserts the snd-aloop module, then droidcam-snd-manager.service will request its removal on droidcam exit.
PULSE_ACTION_ON_EXIT="pa_remove"
ALSA_INDEX="any"

User_ID=$1


logfile=/run/user/$User_ID/droidcam-snd-manager/log

pipe_timeout=10



if [ ! -d "/run/user/$User_ID/droidcam-snd-manager" ]; then mkdir /run/user/$User_ID/droidcam-snd-manager 2>/dev/null; fi

# Create named pipe to communicate with userspace droidcam-monitor.service
echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Creating droidcam_app_ctrl.pipe named pipe." >> $logfile
if [ ! -p "/run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe" ]; then mkfifo /run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe; fi
if [ ! -p "/run/user/$User_ID/droidcam-snd-manager/droidcam_man_ctrl.pipe" ]; then mkfifo /run/user/$User_ID/droidcam-snd-manager/droidcam_man_ctrl.pipe; fi
if [ ! -f "/run/user/$User_ID/droidcam-snd-manager/log" ]; then touch /run/user/$User_ID/droidcam-snd-manager/log; fi

echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Starting droidcam application configuration." >> $logfile
echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Waiting for PULSE 'config' request on droidcam_app_ctrl.pipe." >> $logfile
read -t $pipe_timeout <>/run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe
if [ "$REPLY" == "PULSE" ]; then
	echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Received request for PulseAudio config on droidcam_app_ctrl.pipe: " $REPLY >> $logfile
else
	echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Timed out waiting for droidcam-monitor.service. Starting droidcam application." >> $logfile
        /usr/local/bin/droidcam &
        exit
fi


echo $(date +"%T.%3N")" Gnome-droidcam-desktop: sending pulseaudio config: "$PULSE_ACTION_ON_EXIT" on droidcam_app_ctrl.pipe." >> $logfile
( echo $PULSE_ACTION_ON_EXIT > /run/user/$User_ID/droidcam-snd-manager/droidcam_man_ctrl.pipe ) & timeout_child $pipe_timeout

echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Waiting for ALSA 'config' request on droidcam_app_ctrl.pipe." >> $logfile
read -t $pipe_timeout <>/run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe
if [ "$REPLY" == "ALSA" ]; then 
	echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Received on droidcam_app_ctrl.pipe: " $REPLY >> $logfile
else
	echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Timed out waiting for droidcam-monitor.service. Starting droidcam application." >> $logfile
        /usr/local/bin/droidcam &
        exit
fi


echo $(date +"%T.%3N")" Gnome-droidcam-desktop: sending ALSA index confg: "$ALSA_INDEX" on droidcam_app_ctrl.pipe." >> $logfile
( echo $ALSA_INDEX > /run/user/$User_ID/droidcam-snd-manager/droidcam_man_ctrl.pipe ) & timeout_child $pipe_timeout


echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Waiting for 'start' command on droidcam_app_ctrl.pipe." >> $logfile
read -t $pipe_timeout <>/run/user/$User_ID/droidcam-snd-manager/droidcam_app_ctrl.pipe
if [ "$REPLY" != "" ]; then echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Received command: " $REPLY >> $logfile; fi
if [ "$REPLY" == "" ]; then
	echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Timed out waiting for 'start' command." >> $logfile
fi


echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Starting droidcam" >> $logfile
/usr/local/bin/droidcam &
droidcam_PID=$!
echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Sending Droidcam PID: "$droidcam_PID" to droidcam-snd-manager" >> $logfile
( echo $droidcam_PID > /run/user/$User_ID/droidcam-snd-manager/droidcam_man_ctrl.pipe ) & timeout_child $pipe_timeout
