## What is a Ghost?

A ghost is a playback of your actions that runs along through the level with you. They often pass through things
and interact with invisible obstacles, much like, well, a ghost. They are common in racing games for time trials,
and they serve as an extremely intuitive comparison for speedrunning as well.  
amaurea  was the first person to apply such a concept to speedrunning, in the game Super Mario World. This script is a version
of that idea for Mega Man 2.

A ghost is somewhat like a movie file, but instead of storing inputs to be fed to the emulator, it stores a series of
"savestates" to be drawn to the screen. Each "savestate" is in reality a few bytes of information that I need to properly
draw Mega Man. More details on this format can be found in format specs v1.txt

Note that these aren't intended to be perfect emulations of the game's behavior--in particular, Mega Man's running frame
will often be out of sync. Ghosts are rather intended to provide a "close enough" imitation of a run to help you make
comparisons. If this weren't the case, this could be used as a flicker reduction technique when recording a TAS...
which actually sounds pretty cool!

- [amaurea's original scripts for SMW](http://tasvideos.org/forum/viewtopic.php?p=219824&highlight=#219824)
- [rodamaral's repo which implements SMW ghosts + other useful TAS stuff](https://github.com/rodamaral/smw-tas)  

## Examples

Here are a few interesting TAS comparisons I've made in the past.

[![Visan's Ride](https://img.youtube.com/vi/G_akznDrVV0/0.jpg)](https://www.youtube.com/watch?v=G_akznDrVV0)  
https://www.youtube.com/watch?v=G_akznDrVV0  
[![Metal w/ Time Stopper](https://img.youtube.com/vi/cRRRI7LMytE/0.jpg)](https://www.youtube.com/watch?v=cRRRI7LMytE)  
https://www.youtube.com/watch?v=cRRRI7LMytE  
[![Air Man Any%](https://img.youtube.com/vi/cdNYJuG7OBc/0.jpg)](https://www.youtube.com/watch?v=cdNYJuG7OBc)  
https://www.youtube.com/watch?v=cdNYJuG7OBc  

## Running this Script

To run this script, you will need two things:
- [FCEUX](http://www.fceux.com/web/home.html), the emulator this script is written for
- A Rockman 2 or Mega Man 2 ROM, which I'll assume you obtained by digging around in your copy of Mega Man Legacy Collection 😏

You can open and run your Rockman ROM with Ctrl+O.  
You can run the lua files by clicking File -> Lua -> New Lua Script Window... and then clicking Browse.

This script was developed with Rockman 2, but minimal testing indicates that it is fully compatible with Mega Man 2. I want to make it fully compatible with both versions, so report bugs no matter what you're playing on!


## Recording a Ghost

To record a ghost, you're going to need some inputs. I recommend recording a movie, but you can record it live if you prefer.  
If you mess up and decide to load a savestate, the recording script will **not** recognize it. It will record your new actions
after all your old ones, resulting in a complete mess. You should record a movie if you think you will want to use savestates.

To create a recording:
  1. Load a movie (recommended)
  2. Open record_ghost.lua in FCEUX
  3. Type the filepath to record to in the argument box (e.g. "ghosts\test.ghost")
  4. Click "Run"
  5. Let the emulator run for the entire segment you wish to capture (you can safely use turbo)
  6. Click "Stop"  
  
  
## Playing a Ghost

Once you've recorded a ghost file, playing it back is easy! You can compare it to a movie, or even play alongside it in
real time, which is a ton of fun.

To play a ghost:
  1. Load a movie for comparison (optional)
  2. Open play_ghost.lua in FCEUX
  3. Type the filepath to read from in the argument box (e.g. "ghosts\test.ghost")
  4. Click "Run"
  5. Watch him go!
  
Unlike recording a ghost, playing a ghost is **fully compatible** with savestates. Simply load a state and the ghost will travel through time with you.


## Recording an AVI

To record an AVI:
  1. Run play_ghost.lua with the ghost you wish to record playing. Confusing, I know...
  2. Frame advance at least once. Due to a bug in FCEUX, you *must* do this.\*
  3. Click File -> AVI -> Record AVI...
  4. Specify whatever compression settings and save destination you like 
  5. Let the emulator run for the entire segment you wish to capture (using a movie is highly recommended)
  6. Click File -> AVI -> Stop AVI
  
You **cannot** safely use turbo during this process; the AVI will become garbled.

\*Lua scripts don't get run until the next frame advance. I believe FCEUX closes all other file pointers or something when you start recording an AVI, but I genuinely have no idea. This is a bug that I am aware of and cannot fix, at least not without forking FCEUX and digging into what is probably a really boring section of its code...  
Alternatively, you can click Record AVI *before* running the script.


### Hiding a Ghost

I've done my best to make sure ghosts don't draw when they're not supposed to, but the behavior isn't perfect. In particular, ghosts are drawn over the pause and menu screens, and there may be one-frame glitches when scrolling vertically.  
If this behavior bothers you, you can remove it by *hiding* the ghost using TASEditor; mm2ghost provides a TASEditor button labelled "Show/Hide Ghost" for this purpose. When a ghost is hidden, all calulcations are performed as normal, but the ghost is not drawn.  
Simply hide the ghost one frame before the bothersome section, and re-enable it one frame before it behaves correctly again. You may want to write down the relevant frame numbers and then replay the ghost.

I personally like to let my ghosts run across the pause screen; I hide them whenever the screen fades to black.


## Tips for Capturing a Good Ghost

A good comparison needs a common starting point. I recommend choosing the [one frame of garbage](https://cdn.discordapp.com/attachments/404188813359972352/552398101973958686/Rockman_2_-_Dr._Wily_no_Nazo_Japan-132.png) that can be seen as each
stage loads (just frame advance during the black loading screen and you'll find it). You can also pick the first frame of a jump, menu, boss fight, or whatever else you like. I also recommend recording
a bit more than you need, to give other ghosts a chance to catch up. I usually record through the teleport animation after
a boss fight, but that may be a bit excessive for smaller segments.


## Sample Ghosts

I've provided a few sample ghosts for you to enjoy. They are all stages from various TASes. The Any% TAS from 2010 was done by
shinryuu, aglasscage, finalfighter, and pirohiko. The Buster Only (bonly) and Zipless categories are from WIPs by me.  
Each ghost starts at the [one frame of garbage](https://cdn.discordapp.com/attachments/404188813359972352/552398101973958686/Rockman_2_-_Dr._Wily_no_Nazo_Japan-132.png) at the beginning of its respective stage. Again, just frame advance during the black loading
screen and you'll find it.  
Using zips and full items, you could possibly complete some stages faster than the zipless or buster-only ghosts. Give it a try!


## Known Bugs

- Occasional one-frame glitches when scrolling vertically
- Running & climbing animations desync
- Ghosts may have an incorrect X position for 1 frame when loading savestates
- Ghosts will jitter when above the screen border (negative Y position) while you are scrolling. What an edge case!
