## What is a Ghost?

A ghost is a playback of your actions that runs along through the level with you. They often pass through things
and interact with invisible obstacles, much like some sort of intangible supernatural entity. They are common in racing games for time trials,
and they serve as an extremely intuitive comparison for speedrunning as well.  
amaurea  was the first person to apply such a concept to speedrunning, in the game Super Mario World. This script is a version
of that idea for Mega Man 2.

A ghost is somewhat like a movie file, but instead of storing inputs to be fed to the emulator, it stores a series of
"savestates" to be drawn to the screen. Each "savestate" is in reality a few bytes of information that I need to properly
draw Mega Man. More details on this format can be found in format specs v4.txt

Note that these aren't intended to be perfect emulations of the game's behavior--in particular, Mega Man's running frame
will often be out of sync. Ghosts are rather intended to provide a "close enough" imitation of a run to help you make
comparisons. If this weren't the case, this could be used as a flicker reduction technique when recording a TAS...
[which actually sounds pretty cool](https://github.com/warmCabin/mm2_flicker_ender)!

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

### Compatibility

This script was developed with Rockman 2, but minimal testing indicates that it is compatible with Mega Man 2. I want to make it fully compatible with both versions, so report bugs no matter what you're playing on!

ROM hacks are hit or miss right now. Hacks with lots of custom programming are likely to confuse these scripts.


## Recording a Ghost

To record a ghost, you're going to need some inputs. I recommend recording a movie, but you can record it live if you prefer.  
If you mess up and decide to load a savestate, the recording script will **not** recognize it. It will record your new actions
after all your old ones, resulting in a complete mess. You should record a movie if you think you will want to use savestates.

To create a recording:
  1. Load a movie (recommended)
  2. Open record_ghost.lua in FCEUX
  3. Click Run
  4. Browse to the location where you want to save your recording  
    4.1 (Alternatively, type the filepath (e.g. "ghosts\test.ghost") in the Arguments box before clicking Run)
  5. Let the emulator run for the entire segment you wish to capture (you can safely use turbo)
  6. Click Stop  
  
  
## Playing a Ghost

Once you've recorded a ghost file, playing it back is easy! You can compare it to a movie, or even play alongside it in
real time, which is a ton of fun.

To play a ghost:
  1. Load a movie for comparison (optional)
  2. Open play_ghost.lua in FCEUX
  3. Click Run
  4. Browse to the ghost you want to play  
    4.1 (Alternatively, type the filepath (e.g. "ghosts\test.ghost") in the Arguments box before clicking Run)
  5. Watch him go!
  
Unlike recording a ghost, playing a ghost is **fully compatible** with savestates. Simply load a state and the ghost will travel through time with you.


## Recording an AVI

To record an AVI:
  1. Run play_ghost.lua with the ghost you wish to record playing.\* Confusing, I know...
  2. Click File -> AVI -> Record AVI...
  3. Specify whatever compression settings and save destination you like 
  4. Let the emulator run for the entire segment you wish to capture (using a movie is highly recommended)
  5. Click File -> AVI -> Stop AVI
  
You **cannot** safely use turbo during this process; the AVI will become garbled.  

\* In some versions of FCEUX, Lua scripts don't get run until the next frame advance (you can tell by looking at the output of the script window).
If this is the case for you, make sure to frame advance at least once, or click Record AVI *before* running the script.


### Hiding a Ghost

I've done my best to make sure ghosts don't draw when they're not supposed to, but the behavior isn't perfect. In particular, ghosts are drawn over the pause screen (which I personally prefer!), and there may be one-frame glitches when scrolling vertically.  
If this behavior bothers you, you can remove it by *hiding* the ghost using TASEditor; mm2ghost provides a TASEditor button labelled "Show/Hide Ghost" for this purpose. When a ghost is hidden, all calulcations are performed as normal, but the ghost is not drawn.  
Simply hide the ghost one frame before the bothersome section, and re-enable it one frame before it behaves correctly again. You may want to write down the relevant frame numbers and then replay the ghost.


## Configuration (config.lua)

config.lua is a Lua source file, which can be opened with your favorite text editor. It allows you to adjust drawing offsets and enable some behaviors such as "retro mode;" these options are summarized in the table below.

|Name         |Description|
|-------------|---|  
|xOffset      |Offset all ghost draws by this many pixels horizontally|  
|yOffset      |Offset all ghost draws by this many pixels veritcally|  
|retro        |Enable "retro mode," an old-school flickery effect, as an alternative to plain transparency|
|checkWrapping|Enable wrapping checks. You may find it useful to disable this for certain zip scenarios.|
|baseDir      |Base directory to open in the file picker|

Make sure to leave the formatting intact! In particular, each value needs an equals sign and there should be a comma after every value except the last.

mm2ghost will resort to a set of defaults if any option is missing, or the file itself is missing or malformed.


## Tips for Capturing a Good Ghost

A good comparison needs a common starting point. I recommend the blank frames that can be seen as each
stage loads, or even the boss intro screen, since the script will sync you up with the frst gameplay frame in that case.  

If you only want to analyze a certain segment, you can pick the first frame of a jump, menu, boss fight, or whatever else you like. I also recommend recording
a bit more than you need, to give other ghosts a chance to catch up. I usually record through the teleport animation after
a boss fight, but that may be a bit excessive for smaller segments.


## Sample Ghosts

I've provided a few sample ghosts for you to enjoy, all based on various TASes.  
* any%\_2021 - Any% TAS from 2021 by Shinryuu
* zipless\_2019 - Zipless TAS from 2019 by me
* bonly\_8robos - Buster only WIP by me

Load the ghost at any time and it will sync up with you as you load each stage.  
Using zips and full items, you could possibly complete some stages faster than the zipless or buster-only ghosts. Give it a try!


## Known Bugs

- Occasional one-frame glitches when scrolling vertically & loading savestates
- Running & climbing animations desync from the proper in-game behavior after screen scrolls
- In the Rockman 2 practice hack, there is a memory leak when you pause exit, which confuses mm2ghost. The workaround is to record your ghosts straight from reset.
