# droidcam-snd-manager
A systemd service based approach to management of DroidCam's use of the ALSA snd-aloop kernel module and PulseAudio integration under Gnome

Using DroidCam in Ubuntu can be frustrating. This very useful application uses ALSA as its only mechanism to route sound into the linux OS. Though this is quite understandable it does lead to a rather clunky user experience. Most users of Ubuntu desktop and I'm sure other distros, would like to see DroidCam in PulseAudio; the default sound server. As I'm sure we are all aware, ALSA at the kernel level and PulseAudio in user contexts can often require some gentle persuasion. In particular adding a PulseAudio source to default.pa does not seem to help much. This still requires careful command line intervention. Careful in that the ALSA snd-aloop module must be loaded, then DroidCam must be started first and then a source added to PulseAudio. If it is not done in this order and any of the elements mismatch, the process fails. This is typically what happens if you load snd-aloop at boot time and allow udev to trigger a new sound card device into PulseAudio. The new ‘loopback’ card appears cryptically as a secondary ‘Built-in Audio’ device, with a whole series of configuration options that bear no resemblance to a loopback interface. This is not really PulseAudio's fault. It is only trying to do its best with the information provided by UDEV, which is sparse to say the least. If there were a card ‘profile’ that PulseAudio could use to associate with the loopback device it might look neater and make more sense, but alas, this does not exist (yet) and would be difficult to deal with as the specifics of the loopback module configuration can not easily be communicated through UDEV into PulseAudio. So PulseAudio falls back to its best match and offers us a second ‘Built-in Audio’ device. Making it difficult to tell the difference between the ‘real’ built in audio device and ALSA loopback module. Yuck! Furthermore if you load ALSA snd-aloop at boot and then attempt to add DroidCam as a sound source in PulseAudio through its configuration file, the source appears nicely under sources, but uses totally different stream specifications to those required by DroidCam. You might ask, “well fix those definitions”. It's not so simple. Not only are these definitions un-matched with DroidCam’s requirements, the very fact that PulseAudio has registered with ALSA to use a PCM substream from within the loopback module, ensures that when DroidCam attempts to connect to the ALSA snd-aloop module, it can not use the same PCM sub-stream as that which PulseAudio has already registered onto. It’s chicken and egg.

For me this was most frustrating. Although I am no stranger to the CLI, when I’m about to start a video chat with friends and family, the last thing I want is a battle with the linux sound system. It can be a real kill joy.
“….ahh hang on I just need to sort out my microphone”. …..Now what was that command!

Therefore I decided to try and fix this. If I had realised just how messy this whole thing was I might have backed off.

What I have pulled together is working well for me, but it does require quite a few file configurations. Personally I found the whole process enlightening. Maybe you will too.

NOTE: this setup will not work for DroidCam started via CLI, or the ‘droidcam-cli’ client. It requires that use of Gnome’s systemd methods. Specifically .scope systemd units that are auto-generated whenever a desktop application is launched using its associated .desktop file. Since Gnome embraced systemd, starting any application this way under Gnome creates a systemd .scope unit. These unit files are transitory and last only as long as the application is running and can be found under:

/run/user/<UID>/systemd/transient/
What I found very useful was that just like any other systemd unit these .scope units can be extended by creating a complimentary scope.d drop-in directory under the user specific configs for systemd. Namely under:

~/.config/systemd/user/

These drop-in directories can be wildcarded and as such even though each time you start DriodCam via Gnome, the scope unit name changes, it will still match any wildcard definition that the user has defined and will pull-in the configuration requested. I used this technique to ensure that starting DroidCam also started an associated –user context systemd service, that handles the configuration of the sound system…. Well PulseAudio at least.

The complexity does not unfortunately stop there. The reason being that if you wish to insert a module into the kernel (ALSA’s snd-aloop), this can only be done by ‘root’ and can therefore not be handled by a user context systemd service. In order to overcome this I created a system wide systemd service that listens for requests on named pipes and will configure the ‘snd-aloop’ module on demand.

To allow the sequencing to take  place as required the DroidCam .desktop file must also be modified to call a droidcam.sh script instead of the application directly. This is necessary as we must delay the start of DroidCam while we create the required audio configuration. This script communicates with the user context systemd service, which takes the required config info from the Gnome .desktop system and holds off starting DriodCam, only when the module is loaded does systemd allow the DroidCam application to start. DroidCam then searches for the ALSA module, hopefully finds it and starts up. At this point the user context systemd service monitors the ALSA module looking and waiting for the registration of DroidCam onto a PCM sub-stream of the ALSA loopback module. Once this has been established, it then adds a new PulseAudio source which will faithfully allow DroidCam sound into the sound server and we are up and running.

It should be noted that before starting DroidCam, I have the systemd service remove the UDEV triggered card that appears automatically in PulseAudio when the snd-aloop module is inserted. It is confusing and in fact not necessary. We can still add a PulseAudio source without having PulseAudio attempt to manage the loopback ‘card’. This reduces the potential for misconfiguration both to DroidCam and indeed the ‘real’ Built-In sound card. Also when inserting the snd-aloop module, it is created with only a single PCM sub-stream. This ensures that DroidCam always appears in the same place. It can not establish onto a PCM substream that is different to the we establish as a PulseAudio source. You might ask, “why don't you identify it correctly”. The answer… “It’s not possible”, as ALSA does not enumerate the information about the device which is attached to a particular PCM sub-stream. 

If you would like to give it a try feel free. I have uploaded my scripts in the directory structure that I have on my Ubuntu 20.04 LTS system. 

As described we have four elements:

DroidCam .desktop file and droidcam.sh for use by Gnome
User context systemd droidcam-snd-manager.service and associated shell script located in its drop-in directory.
Drop-in directory service unit and .config for gnome-launched-droidcam.desktop-.scope.d
System level systemd ALSA-snd-aloop-manager.service, its drop-in dir and shell script
Config file additions within /etc/modprobe.d and /etc/module-load.d

I used a modprobe alias for the snd-aloop module, as this ensures that other configuration options used by snd-aloop module by other users (applications) on the system do not change the configurations managed by the ALSA-snd-manager service.

Having placed all the files in the correct place, with appropriate permissions; that is owned by the user for everything in user context and owned by root for the system level systemd service and with all .sh scripts executable. We should be able to enable the ALSA-snd-aloop-manager service.

root@home:systemctl enable ALSA-snd-aloop-manager.service

Finally, if you have any other application using snd-aloop module, you must modprobe -r snd-aloop before you can expect this all to work.
Unfortunately there can be 1 and only 1 snd-aloop module loaded at one time. Trying to simply strip it out or change its config might not be possible. Anything using it will block it, preventing its removal and config changes require re-insertion. As I mentioned, trying to interrogate ALSA or DroidCam about which PCM sub-stream it decided to attach to is not possible.

Having said this, I’m sure that most users don't make full time use of the snd-aloop module. 
Bottom line, this convoluted solution does allow me to simply fire up DroidCam, have a PulseAudio microphone appear automatically and open, for example, meet.google.com and have it instantly establish connections with video and audio, without any restarts or command line intervention.

