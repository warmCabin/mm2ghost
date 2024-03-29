
--[[
    This file handles all the gritty details of animating ghosts. Call mod.update every frame, and check its
    return values to get the image to draw and the offsets to draw it at.
    It also provides public access to the animation tables, the palette table, and the palettize function,
    in case you need them. play_ghost.lua does not use them at all; just mod.update.
]]

local mod = {}

--[[
    Reads data from a gd image file. Lua and FCEUX have no image manipulation support whatsoever*,
    so typically people install the Lua GD library. FCEUX IS capable of drawing images, but only
    in the GD string format, which is an internal format of the GD library--were they trying to get around
    a licensing issue? Either way, it's up to you to find and install a copy of the GD library.
    
    ...OR!
    
    You could look up the format specs and make your own damn gd strings. These things are straight ARGB.
    Just an array of bytes that get processed as the color channels for each pixel. No compression,
    no DPI stuff, no aspect ratio, no color spaces, NOTHING. Just alpha, red, green, blue, repeat.
    It's honestly kind of nice. But it's also kind of terrible. It means you have to pass around these
    bulky 2KB strings (yes, they have to be strings) in all your drawing code. I've already taken up 25%
    the size of Rockman 2 with just these pictures of Mega Man! Hopefully your computer doesn't run out
    of memory, and hopefully this code runs fast enough to be fun to use.

    If you're a Windows user and you're as lazy as me, you'll appreciate not needing to run a makefile
    and shove a bunch of random DLLs into your path!
    
    Each image of Mega Man is stored as a palettized GD string serialized plainly to a file.
    
    see https://libgd.github.io/manuals/2.3.0/files/gd_gd-c.html
    
    * I think FCEUX makes some sort of GD implementation accessible to Lua by default.
      I need to look into that...
]]
local function readGD(filename)
    local img = io.open(filename, "rb")
    assert(img, string.format("Could not open file %s", filename))
    local str = img:read(99999999)
    assert(not img:read(1), "That's a BIG image. Let's not get carried away, here.")
    img:close()
    return str
end
mod.readGD = readGD

--[[
    Sprite mirroring. Returns a horizontally flipped version of the given GD image.
    This function simply iterates through each row and reverses the order of the pixels.
]]
local function flipGD(gdStr)
    
    local width  = gdStr:byte(3)*256 + gdStr:byte(4)
    local height = gdStr:byte(5)*256 + gdStr:byte(6)
    local buff = {}
    local bi = 1038
    
    -- Copy 13-byte header + 1 KB of mostly useless palette data indiscriminately.
    for i = 1, 1037 do
        buff[i] = gdStr:byte(i)
    end
    
    -- Copy each row backwards
    for i = 0, height-1 do    -- Real programmers index their shit by 0, dammit!
        for j = 0, width-1 do -- The math works out so nice!
            buff[bi] = gdStr:byte(1038 + i * width + (width - j - 1))
            bi = bi + 1
        end
    end
    
    -- Dump the bytes into a stupid bulky string and return it.
    return string.char(unpack(buff))
    
end
mod.flipGD = flipGD

-- Load a few images beforehand to prevent duplicates.
local running2 = readGD("mmframes/running2.gd")
local running2Flipped = flipGD(running2)
local runshoot2 = readGD("mmframes/runshoot2.gd")
local runshoot2Flipped = flipGD(runshoot2)
local teleport1 = readGD("mmframes/teleport.gd")
local climb = readGD("mmframes/climb.gd")

--[[
    Maps the animation indexes to image files. Each index is a table containing one or more frames of animation.
    The indexes correspond to 0x400 in RAM, and are stored RLE compressed in ghost files.
    frame format: gd image, x offset, y offset, duration. Duration of 0 or nil means forever, i.e. a non-looping animation.
    See animIndex.txt for a concise list of what each index represents.
]]
local anim = {}
anim[0x00] = {{readGD("mmframes/standing.gd"), 0, 0, 91}, {readGD("mmframes/blinking.gd"), 4, 0, 9}} -- TODO: 90/10!?
anim[0x01] = {{readGD("mmframes/standnshoot.gd"), 4, 0}}
anim[0x03] = {{readGD("mmframes/standnthrow.gd"), 4, 0}} 
anim[0x04] = {{readGD("mmframes/tiptoe.gd"), 4, 0}}
anim[0x05] = anim[0x01]
anim[0x07] = anim[0x03]
anim[0x08] = {{readGD("mmframes/running.gd"), 0, 2, 7},  {running2, 5, 0, 7},  {readGD("mmframes/running3.gd"), 1, 2, 7}, {running2, 5, 0, 7}}
anim[0x09] = {{readGD("mmframes/runshoot.gd"), 0, 2, 7}, {runshoot2, 5, 0, 7}, {readGD("mmframes/runshoot3.gd"), 1, 2, 7}, {runshoot2, 5, 0, 7}}
anim[0x0B] = anim[0x03]
anim[0x0C] = {{readGD("mmframes/falling.gd"), 0, 0}}
anim[0x0D] = {{readGD("mmframes/fallnshoot.gd"), 1, 0}}
anim[0x0F] = {{readGD("mmframes/fallnthrow.gd"), 2, 0}}
anim[0x10] = anim[0x04]
anim[0x11] = anim[0x01]
anim[0x13] = anim[0x03]
anim[0x14] = anim[0x00]
anim[0x15] = {{anim[0x09][1][1], anim[0x09][1][2], anim[0x09][1][3], 2}, {anim[0x01][1][1], anim[0x01][1][2], anim[0x01][1][3], 0}} -- anim[0x01] -- anim[0x09]
anim[0x17] = {{readGD("mmframes/standnthrow.gd"), 4, 0}}
anim[0x18] = {{readGD("mmframes/knockback.gd"), 2, 0}}
anim[0x19] = anim[0x08]
anim[0x1A] = {{teleport1, 10, -8, 3}, {readGD("mmframes/teleport2.gd"), 4, -3, 3}, {readGD("mmframes/teleport3.gd"), 4, 13, 3}, {teleport1, 10, -8, 0}}
anim[0x1B] = {{climb, 7, 0, 9}, {flipGD(climb), 7, 0, 9}}
anim[0x1C] = {{readGD("mmframes/climbnshoot.gd"), -1, 0}}
anim[0x1E] = {{readGD("mmframes/climbnthrow.gd"), -1, 0}}
anim[0x1F] = {{readGD("mmframes/ass.gd"), 7, 0}}
anim[0x20] = anim[0x1C]
anim[0x22] = anim[0x1E]
anim[0x26] = {anim[0x1A][1], anim[0x1A][3], anim[0x1A][2], anim[0x1A][4]}

mod.anim = anim

--[[
    left-facing versions of all the sprites.
    Note that Rockman 2 actually stores left-facing graphics, and flips them to face right.
    Since all the offsets are different for flipped images, it made the most sense to
    recreate the entire table. There's a lot of redundant data here, I know...
    I suppose I could put in flip offsets for each anim entry. Y offsets are the same for both.
]]
local flip = {}
flip[0x00] = {{flipGD(anim[0x00][1][1]), 5, 0, 91}, {flipGD(anim[0x00][2][1]), 5, 0, 9}}
flip[0x01] = {{flipGD(anim[0x01][1][1]), -5, 0}}
flip[0x03] = {{flipGD(anim[0x03][1][1]), -1, 0}}
flip[0x04] = {{flipGD(anim[0x04][1][1]), 6, 0}}
flip[0x05] = flip[0x01]
flip[0x07] = flip[0x03]
flip[0x08] = {{flipGD(anim[0x08][1][1]), 4, 2, 7}, {running2Flipped, 9, 0, 7}, {flipGD(anim[0x08][3][1]), 8, 2, 7}, {running2Flipped, 9, 0, 7}}
flip[0x09] = {{flipGD(anim[0x09][1][1]), -1, 2, 7}, {runshoot2Flipped, -1, 0, 7}, {flipGD(anim[0x09][3][1]), -1, 2, 7}, {runshoot2Flipped, -1, 0, 7}}
flip[0x0B] = flip[0x03]
flip[0x0C] = {{flipGD(anim[0x0C][1][1]), 2, 0}}
flip[0x0D] = {{flipGD(anim[0x0D][1][1]), -1, 0}}
flip[0x0F] = {{flipGD(anim[0x0F][1][1]), 0, 0}}
flip[0x10] = flip[0x04]
flip[0x11] = flip[0x01]
flip[0x13] = flip[0x03]
flip[0x14] = flip[0x00]
flip[0x15] = flip[0x01] -- flip[0x09] (???)
flip[0x17] = flip[0x03]
flip[0x18] = {{flipGD(anim[0x18][1][1]), 2, 0}}
flip[0x19] = flip[0x08]
flip[0x1A] = anim[0x1A]
flip[0x1B] = {{flipGD(climb), 7, 0, 9}, {climb, 7, 0, 9}}
flip[0x1C] = {{flipGD(anim[0x1C][1][1]), 7, 0}}
flip[0x1E] = {{flipGD(anim[0x1E][1][1]), 7, 0}}
flip[0x1F] = {{flipGD(anim[0x1F][1][1]), 7, 0}}
flip[0x20] = flip[0x1C]
flip[0x22] = flip[0x1E]
flip[0x26] = anim[0x26]

mod.flip = flip

--[[
Alternative approach: automatically setup each flip entry like so,
then manually set the X offset:
for k,v in pairs(anim) do
    flip[k] = {flipGD(anim[k][1]), 0, anim[k][3], anim[k][4]}
end 
flip[0x00][2] = ...
flip[0x01][2] = ...
...
]]

-- Stored as NES palette indexes so ghost colors will match your settings.
local palettes = {} -- outline, body, undies
palettes[0]  = {"P0F", "P2C", "P11"} -- P
palettes[1]  = {"P0F", "P28", "P15"} -- H
palettes[2]  = {"P0F", "P30", "P11"} -- A
palettes[3]  = {"P0F", "P30", "P19"} -- W
palettes[4]  = {"P0F", "P30", "P00"} -- B
palettes[5]  = {"P0F", "P34", "P25"} -- Q
palettes[6]  = {"P0F", "P34", "P14"} -- F
palettes[7]  = {"P0F", "P37", "P18"} -- M
palettes[8]  = {"P0F", "P30", "P26"} -- C
palettes[9]  = {"P0F", "P30", "P16"} -- 1
palettes[10] = palettes[9]           -- 2
palettes[11] = palettes[9]           -- 3

mod.palettes = palettes

local function setPalette(gdPal, index, r, g, b, a)
    index = (index - 1) * 4 + 1
    
    gdPal[index]     = r
    gdPal[index + 1] = g
    gdPal[index + 2] = b
    gdPal[index + 3] = 0xFF - a -- GD seems to have alpha backwards.
end

--[[
    Convert a blue & cyan Mega Man image to the appropriate weapon palette.
    This is accomplished by splicing the appropriate colors into the first
    five entires of the GD palette. The remaining 251 are left intact...
    
    The FCEUX docs claim this palettized mode is not supported. Someone had better update that!
    
    TODO: PRECOMP OR CACHE THESE!!! This processes 2KB of data 60 times a second!!
]]
local function palettize(gdStr, pIndex)

    local pal = palettes[pIndex]
    if not pal then
        -- TODO: Make an on-screen queue or something. No more hardcoded coordinates.
        gui.text(10, 20, "Unknown weapon "..pIndex)
        gui.text(10, 30, "Are you hacking...?")
        return gdStr
    end
    
    -- Set up GD palette. We only care about the first 5 colors, but 256 colors are in there, lurking...
    local paletteBytes = {}
    setPalette(paletteBytes, 1, gui.parsecolor(pal[3])) -- blue undies
    setPalette(paletteBytes, 2, gui.parsecolor(pal[2])) -- cyan body
    setPalette(paletteBytes, 3, gui.parsecolor(pal[1])) -- black outline
    setPalette(paletteBytes, 4, gui.parsecolor("P38"))  -- skin color
    setPalette(paletteBytes, 5, gui.parsecolor("P20"))  -- white eyes
    
    local paletteStr = string.char(unpack(paletteBytes))
    
    -- Splice the bytes into a stupid bulky string and return it.
    return gdStr:sub(1, 13)
        ..paletteStr
        ..gdStr:sub(34)

end
mod.palettize = palettize

local animFrame = 1
local animTimer = -1
local animIndex = 0
local prevAnimIndex = 0

--[[
    Updates the animation state (timer, etc.) and returns:
        if the animation index is normal:
            offset X, offset Y, image to be drawn.
        if the animation index is 0xFF (nothing to draw):
            nil
        if the animation index is unknown:
            animation index, error message
    
]]
function mod.update(data)
    
    -- TODO: Skip the validation? This runs at 60 Hz, after all.
    assert(type(data)=="table" and data.animIndex, "animation.update must be called with frame data table")
    
    animIndex = data.animIndex
    local animTable
    local weapon = data.weapon
        
    --gui.text(10,10,string.format("%02X",animIndex))
    --gui.text(10,20,string.format("%02X: %02X, %02X",data.screen,data.xPos,data.yPos))
    
    if data.flipped then
        -- right facing
        animTable = anim
    else
        -- left facing
        animTable = flip
    end
    
    -- Nothing to draw!
    if animIndex == 0xFF then
        return {noDraw=true}
    end
    
    -- Special case: we need to preserve the animation frame between regular running, and running+shooting (indexes 8 and 9)
    if animIndex ~= prevAnimIndex then
        if (animIndex==0x08 and prevAnimIndex==0x09) or (animIndex==0x09 and prevAnimIndex==0x08) then
            -- Mega Man still running. Preserve frame when switching between these indexes.
        else
            animFrame = 1
            if animTable[animIndex] then
                animTimer = animTable[animIndex][animFrame][4]
            else
                animTimer = -1
            end
        end
    end
    
    -- Unknwon animation index. Return the index and an error message to be handled by the main update code.
    if not animTable[animIndex] then
        return {
            animIndex = animIndex,
            errorMessage = string.format("Unknown animation index %02X! (%sflipped)", animIndex, (animTable==flip) and "" or "not ")
        }
    end
    
    -- Does this copy the whole string over?
    local img = palettize(animTable[animIndex][animFrame][1], weapon)
    
    local offsetX = animTable[animIndex][animFrame][2]
    local offsetY = animTable[animIndex][animFrame][3]
    
    -- Update animation timer
    local duration = animTable[animIndex][animFrame][4]
    if duration and duration > 0 then
        if not data.halt then
            animTimer = animTimer - 1
        end
    else
        animTimer = -1
    end
    
    if animTimer==0 then
        animFrame = animFrame % #animTable[animIndex] + 1
        animTimer = animTable[animIndex][animFrame][4]
    end
    
    prevAnimIndex = animIndex
    
    -- return values from before the update
    return {
        offsetX = offsetX,
        offsetY = offsetY,
        image = img
    }
    
end

return mod
