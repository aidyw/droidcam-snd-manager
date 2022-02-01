#"/bin/bash

timeout_child () {
    trap -- "" SIGTERM
    child=$!
    timeout=$1
    (
            sleep $timeout
            kill -9 $child
    ) &
    wait $child
}


# Choose 'pa_remove' to strip out the droidcam microphone source from pulseaudio and remove the ALSA snd-aloop module when droidcam exits.
# Choose 'pa_keep' to retain the droidcam microphone source within pulseaudio and retain the ALSA snd-aloop module when droidcam exits.
PULSE_ACTION_ON_EXIT="pa_remove"
ALSA_INDEX=15


logfile=/run/ALSA-snd-aloop-manager/log

pipe_wrt_timeout=3


echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Starting droidcam application configuration." >> $logfile
if [ ! -d "/run/user/$1/droidcam-snd-manager" ]; then mkdir /run/user/$1/droidcam-snd-manager; fi

# Create named pipe to communicate with userspace droidcam-monitor.service
echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Creating droidcam_app_ctrl.pipe named pipe." >> $logfile
if [ ! -p "/run/user/$1/droidcam-snd-manager/droidcam_app_ctrl.pipe" ]; then mkfifo /run/user/$1/droidcam-snd-manager/droidcam_app_ctrl.pipe; fi
if [ ! -p "/run/user/$1/droidcam-snd-manager/droidcam_mon_ctrl.pipe" ]; then mkfifo /run/user/$1/droidcam-snd-manager/droidcam_mon_ctrl.pipe; fi

echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Waiting for pulseaudio 'config' request on droidcam_app_ctrl.pipe." >> $logfile
while [ "$REPLY" != "pulse" ]; do
        read -t 2 <>/run/user/$1/droidcam-snd-manager/droidcam_app_ctrl.pipe
	if [ "$REPLY" != "" ]; then echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Received on droidcam_app_ctrl.pipe: " $REPLY >> $logfile; fi
	if [ "$REPLY" == "" ]; then
		echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Timed out waiting for droidcam-monitor.service. Starting droidcam application." >> $logfile
                /usr/local/bin/droidcam &
                exit
        fi
done


echo $(date +"%T.%3N")" Gnome-droidcam-desktop: sending pulseaudio config: "$PULSE_ACTION_ON_EXIT" on droidcam_app_ctrl.pipe." >> $logfile
( echo $PULSE_ACTION_ON_EXIT > /run/user/$1/droidcam-snd-manager/droidcam_mon_ctrl.pipe ) & timeout_child $pipe_wrt_timeout

echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Waiting for ALSA index 'config' request on droidcam_app_ctrl.pipe." >> $logfile
while [ "$REPLY" != "ALSA" ]; do
        read -t 2 <>/run/user/$1/droidcam-snd-manager/droidcam_app_ctrl.pipe
        if [ "$REPLY" != "" ]; then echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Received on droidcam_app_ctrl.pipe: " $REPLY >> $logfile; fi
        if [ "$REPLY" == "" ]; then
                echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Timed out waiting for droidcam-monitor.service. Starting droidcam application." >> $logfile
                /usr/local/bin/droidcam &
                exit
        fi
done


echo $(date +"%T.%3N")" Gnome-droidcam-desktop: sending ALSA index confg: "$ALSA_INDEX" on droidcam_app_ctrl.pipe." >> $logfile
( echo $ALSA_INDEX > /run/user/$1/droidcam-snd-manager/droidcam_mon_ctrl.pipe ) & timeout_child $pipe_wrt_timeout


echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Waiting for 'start' command on droidcam_app_ctrl.pipe." >> $logfile
until [[ "$REPLY" == "start" || "$REPLY" == "" ]]; do
        read -t 2 <>/run/user/$1/droidcam-snd-manager/droidcam_app_ctrl.pipe
        if [ "$REPLY" != "" ]; then echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Received command: " $REPLY >> $logfile; fi
	if [ "$REPLY" == "" ]; then
                echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Timed out waiting for 'start' command." >> $logfile
        fi
done


echo $(date +"%T.%3N")" Gnome-droidcam-desktop: Starting droidcam" >> $logfile
/usr/local/bin/droidcam &
