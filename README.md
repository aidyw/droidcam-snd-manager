# droidcam-snd-manager
A systemd service based approach to management of DroidCam's use of the ALSA snd-aloop kernel module and PulseAudio integration under Gnome

Using DroidCam in Ubuntu can be frustrating. This very useful application uses ALSA as its only mechanism to route sound into the linux OS. Though this is quite understandable it does lead to a rather clunky user experience. Most users of Ubuntu desktop and I'm sure other distros, would like to see DroidCam in PulseAudio; the default sound server. As I'm sure we are all aware, ALSA at the kernel level and PulseAudio in user contexts can often require some gentle persuasion. In particular adding a PulseAudio source to default.pa does not seem to help much. This still requires careful command line intervention. Careful in that the ALSA snd-aloop module must be loaded, then DroidCam must be started first and then a source added to PulseAudio. If it is not done in this order and any of the elements mismatch, the process fails. This is typically what happens if you load snd-aloop at boot time and allow udev to trigger a new sound card device into PulseAudio. The new ‘loopback’ card appears cryptically as a secondary ‘Built-in Audio’ device, with a whole series of configuration options that bear no resemblance to a loopback interface. This is not really PulseAudio's fault. It is only trying to do its best with the information provided by UDEV, which in a default set-up is sparse to say the least. So PulseAudio falls back to its best match and offers us a second ‘Built-in Audio’ device. Making it difficult to tell the difference between the ‘real’ built in audio device and ALSA's loopback module. Furthermore if you load ALSA snd-aloop at boot and then attempt to add DroidCam as a sound source in PulseAudio through its configuration file, the source appears nicely under sources, but uses PulseAudio's default stream specifications which are different to those required by DroidCam. You might ask, “well fix those definitions”. It's not so simple; when the ALSA snd-aloop module is loaded, none of its interfaces have any defined stream specifications, ALSA expects any client, (source or sink in PulseAudio parlance, capture or playback in ALSA parlance), to register its specifications with the ALSA core. Unless DroidCam has already started and done this on the playback channel, PulseAudio has no information about the channel as the stream specifications are blank. Therefore PulseAudio has no other option than to apply its system wide defaults when it registers with the ALSA module and unless you want your entire audio system to be limited to the sample rate and mono specification of DroidCam microphone, well you are stuck. The very fact that PulseAudio has registered with ALSA to use a PCM substream from within the loopback module, ensures that when DroidCam attempts to connect to the ALSA snd-aloop module, it can not use the same PCM sub-stream as that which PulseAudio has already registered onto because very probably the stream specifications don't match. It’s chicken and egg.

This can be overcome quite simply by ensuring that the snd-aloop ALSA modules loads at boot time and then creating the correct PulseAudio source using specific stream specifications to match DroidCam, apriori:
```
load-module module-alsa-source rate=16000 channels=1 source_properties=device.description=DroidCam device=hw:Loopback,1,0
```

While this works, it leaves you with a bloated and confusing PulseAudio set-up. The snd-aloop module appears under configuration as ‘Built-in Audio’ as described above and the Droidcam source sits around as a PulseAudio source even when DroidCam is not running.

This can be improved by setting up some UDEV rules to match the snd-aloop module matched to a PulseAudio profile-set. I have created these and they can be found here:
```
/lib/udev/rules.d/91-pulseaudio-snd-aloop.rules
/usr/share/pulseaudio/alsa-mixer/profile-sets/snd-aloop.conf
```
The profile set only defines 2 sub-channels out of the 8 possible. I felt it was an appropriate set of profile options, without offering an endless list of possible profiles. The profile names reflect the ALSA name convention with the addition of ‘<hw’ or ‘>hw’ to indicate pulse audio ‘source’ or ‘sink’ respectively. The idea being that as ALSA sits underneath PulseAudio the arrow indicates ‘>hw’: sending to the kernel (ALSA) or ‘<hw’: receiving from the kernel (ALSA). 

Use of this hard-coded solution is still not 100% ideal, as if you use the snd-aloop module for other purposes on your system it is not possible to know beforehand which sub-channel DroidCam will register onto when it starts. In fact if an existing ‘capture’ device is already registered with snd-aloop module with different stream properties to DroidCam and without a corresponding ‘playback’ device also registered on the same sub-channel, then all attempts to start Droidcam will fail, as Droidcam finds the free sub-channel ‘playback’ interface but fails to establish the ‘playback’ pcm links complaining about mismatched stream definitions. This is really a shortcoming of DroidCam. IMHO it should try the next free subchannel before failing. 

For me this was all most frustrating. Although I am no stranger to the CLI, when I’m about to start a video chat with friends and family, the last thing I want is a battle with the linux sound system. It can be a real killjoy.
“….ahh hang on I just need to sort out my microphone”. …..Now what was that command!

Therefore I decided to try and fix this. If I had realised just how messy this whole thing was I might have backed off.

What I have pulled together is working well for me, but it does require quite a few file configurations. Personally I found the whole process enlightening. If you dig inside, maybe you will too.

NOTE: this systemd approach will not work for DroidCam started via CLI, or the ‘droidcam-cli’ client. As It requires the use of Gnome’s systemd methods. Specifically .scope systemd units that are auto-generated whenever a desktop application is launched using its associated .desktop file. Since Gnome embraced systemd, starting any application this way under Gnome creates a systemd .scope unit. These unit files are transitory and last only as long as the application is running. They can be be found under:
```
/run/user/<UID>/systemd/transient/
```
What I found very useful was that just like any other systemd unit these .scope units can be extended by creating a complimentary scope.d drop-in directory under the user specific configs for systemd. Namely under:
```
~/.config/systemd/user/
```
These drop-in directories can be wildcarded and as such even though each time you start DriodCam via Gnome, the scope unit name changes by extending the name with the PID of whatever the .desktop file starts. However using a wildcard drop-in will pull-in the configuration requested when the specific .desktop file is used. I used this technique to ensure that DroidCam’s .desktop also started an associated –user context systemd service, that handles the configuration of the sound system.

The complexity does not unfortunately stop there. The reason being that if you wish to insert a module into the kernel (ALSA’s snd-aloop), this can only be done by ‘root’ and can therefore not be handled by a user context systemd service. In order to overcome this I created a system wide systemd service ‘ALSA-snd-aloop-manager.service’ that listens for requests on named pipes and will insert or remove the ‘snd-aloop’ module on demand.

Note: If you manually insert snd-aloop it is not necessary to use ALSA-snd-aloop-manager.service, the user level systemd service ‘droidcam-snd-manager.service’ will attempt to use the existing module if it finds it. 

To allow the sequencing to take place as required the DroidCam .desktop file must also be modified to call a droidcam.sh script instead of the application directly. This allows the systemd service to negotiate with the .desktop instance its required config details and delays the start of DroidCam while we create the required audio configuration. The systemd --user service then searches for the ALSA module, if not found, inserts it by calling 'ALSA-snd-aloop-manager.service' --system service and then starts up DroidCam. At this point the user context systemd service monitors DroidCam and the ALSA module looking and waiting for the registration of DroidCam onto a PCM sub-stream of the ALSA loopback module. Once this has been established, it then adds a new PulseAudio source on the same subchannel. As DroidCam has already registered with ALSA at this point, PulseAudio will faithfully and automatically define the source using the stream definition given by DroidCam and sound will be up and running.

It should be noted that before starting DroidCam, If ‘droidcam-snd-manager.service’ requested and inserted the snd-aloop module, it attempts to remove any UDEV triggered card that appears automatically in PulseAudio when the snd-aloop module is inserted. As discussed this entry can be confusing without a specific PulseAudio profile-set and in fact is not necessary for functionality. We can still add a PulseAudio source without having PulseAudio attempt to manage the loopback ‘card’. This reduces the potential for misconfiguration both to DroidCam and indeed the ‘real’ Built-In sound card. Also when ‘ALSA-snd-aloop-manager.service’ inserts the snd-aloop module, it is created with only a single PCM sub-stream. This ensures that only DroidCam should attach to the snd-aloop module and we can be much more certain that the systemd service can successfully remove the snd-aloop module it inserted when DroidCam closes, as having only a single PCM channel should prevent other applications from binding to the module.

It is possible to specifically specify the ALSA index number to use for DroidCam or ‘any’ to allow the module to be inserted at the next available index. This is done in the script called by the .desktop file:
```
~/.local/share/applications/droidcam.sh
```

If you would like to give it a try feel free. I have uploaded all the files in the directory structure that I have on my Ubuntu 20.04 LTS system. So you need to place each file onto your system in the same location unless your distro is different. If so, good luck. 

As described we have five elements:

1:
DroidCam .desktop file and droidcam.sh for use by Gnome
User context systemd ‘droidcam-snd-manager.service’ and associated shell script ‘droidcam-snd-manager.sh’ which is located in its drop-in directory.

2:
Drop-in directory ‘gnome-launched-droidcam.desktop-.scope.d’ containing ‘droidcam-snd-manager.conf’

3:
User level systemd service unit ‘droidcam-snd-manager.service’ its drop-in dir and shell script ‘droidcam-snd-manager.sh’

4:
System level systemd service unit ‘ALSA-snd-aloop-manager.service’, its drop-in dir and shell script ‘ALSA-snd-aloop-manager.sh’

5:
Config file additions within /etc/modprobe.d and /etc/module-load.d

I used a modprobe alias for the snd-aloop module, as this ensures that other configuration options used by snd-aloop module by other users (applications) on the system do not change the configurations managed by the ALSA-snd-manager service, as this only calls for the modules alias name.

Having placed all the files in the correct place, with appropriate permissions; that is owned by the user for everything in user context and owned by root for the system level systemd service unit files and script, and with all .sh scripts executable.

We should be able to start the ALSA-snd-aloop-manager service.
```
root@home:systemctl start ALSA-snd-aloop-manager.service
```

If you wish the service to run at boot time:
```
root@home:systemctl enable ALSA-snd-aloop-manager.service
```

logs can be found for both the user level and system level systemd service:
```
/run/user/<UID>/droidcam-snd-manager/log
```
```
/run/ALSA-snd-aloop-manager/log
```

Finally, if you want this solution to fully manage the snd-aloop module and PulseAudio, you must ensure that snd-aloop is not already inserted at boot time or remove it explicitly
```
root@home:modprobe -r snd-aloop
```

Unfortunately there can be 1 and only 1 snd-aloop module loaded at one time. It owns the kernel module name ‘snd_aloop’. It is possible to load more than one instance of the driver, but it must be compiled with a different module name. Having said this, I’m sure that most users don't make full time use of the snd-aloop module. 

Bottom line, this convoluted solution does allow me to simply fire up DroidCam, have a PulseAudio microphone appear automatically and open, for example, meet.google.com and have it instantly establish connections with video and audio, without any restarts of PulseAudio or command line intervention to get the kernel module in place and PulseAudio sorce established.

Enjoy!

