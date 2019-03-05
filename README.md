## What is a Ghost?

A ghost is a playback of your actions that runs along through the level with you. They often pass through things
and interact with invisible obstacles, much like, well, a ghost. They are common in racing games for time trials,
and they serve as an extremely intuitive comparison for speedrunning as well.  
amaurea  was the first person to apply such a concept to speedrunning, in the game Super Mario World. This script is a version
of that idea for Mega Man 2.

A ghost is somewhat like a movie file, but instead of storing inputs to be fed to the emulator, it stores a series of
"savestates" to be drawn to the screen. Each "savestate" is in reality a few bytes of information that I need to properly
draw Mega Man. More details on this format can be found in format spects v0.txt

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
  
Unlike recording a ghost, playing a ghost is fully compatible with savestates. Simply load a state and the ghost will travel through time with you.


## Recording an AVI

To record an AVI:
  1. Click File -> AVI -> Record AVI...
  2. Specify whatever compression settings and save destination you like
  3. Run play_ghost.lua with the ghost you wish to record playing. Confusing, I know...
  
You **MUST** click Record AVI **BEFORE** you run the Lua script. Due to a known bug, play_ghost.lua cannot read any files if you initiate
AVI recording while it is running. I think FCEUX closes all other file pointers or something, but I genuinely have no idea.

If the screen wrap bug bothers you, you can edit it out using TASEditor. It's a tedious process, but doable.  
play_ghost.lua provides a manual button in the TASEditor interface labelled "Show/Hide Ghost". When clicked, it toggles the current
ghost's visibility. Hidden ghosts advance their position and animation state, but are not drawn to the screen. I created this feature
solely for this tedious task!  
As the ghost plays, record the frame numbers where Mega Man leaves and re-enters the screen. Then, when playing back the ghost
and recording an AVI, click the "Show/Hide Ghost" button in TASEditor one frame BEFORE all the numbers you recorded. For example,
if Mega Man disappeared on frame 100, reappeared on frame 150, and disappeared again on frame 248, you'd click Show/Hide Ghost on
frames 99, 149, and 247.  
This is a lame workaround, and I know it. I'm working on fixing the screen wrap behavior; I may add programmatic support to the process
above if screen wrapping cannot be fixed.  


## Tips for Capturing a Good Ghost

A good comparison needs a common starting point. I recommend choosing the 1 frame of garbage that can be seen as each
stage loads. You can also pick the first frame of a jump, menu, boss fight, or whatever else you like. I also recommend recording
a bit more than you need, to give other ghosts a chance to catch up. I usually record through the teleport animation after
a boss fight, but that may be a bit excessive for smaller segments.


## Sample Ghosts

I've provided a few sample ghosts for you to enjoy. They are all stages from various TASes. The Any% TAS from 2010 was done by
shinryuu, aglasscage, finalfighter, and pirohiko. The Buster Only (bonly) and Zipless categories are from WIPs by me.  
Each ghost starts at the one frame of garbage at the beginning of its respective stage. Just frame advance during the black loading
screen and you'll see what I mean!  
Using zips and full items, you could possibly complete some stages faster than the zipless or buster-only ghosts. Give it a try!


## Known Bugs

- Mega Man wraps around when he gets too far ahead or behind
- Running & climbing animations desync
- Ghosts may have an incorrect X position for 1 frame when loading savestates
