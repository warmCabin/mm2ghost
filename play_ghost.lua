--[[
    Plays back a ghost file relative to the frame you click Run.
    You can load a savestate and the ghost will travel through time with you; it's all based
    on the frame count.
    You must specify which ghost file to run in the Arguments box.
    
    This script proivdes a button in TASEditor labelled "Show/Hide Ghost." When a ghost is hidden,
    all calculations are still carried out, but it is not drawn. The primary intended use of this
    button is for cleaning up AVI recordings.
]]

local bit = require("bit")
local anm = require("animation")
local cfg = {}

-- janky Lua try/catch
if not pcall(function()
    cfg = require("config")
end) then
    print("Error loading configuration file! Reverting to default settings.")
    print("Are all the values separated by commas?")
    print()
end

-- the defaults, all wrapped up in Lua meta-magic
setmetatable(cfg, {__index = {
    xOffset = -14,
    yOffset = -11,
    retro = false,
    checkWrapping = true
}})

-- Read number Big-endian
local function readNumBE(file, length)
    assert(length <= 8, "Read operation will overflow.")
    local ans = 0
    for i = 1, length do
        ans = ans*256 + file:read(1):byte()
    end
    return ans
end

-- Read byte or crash. I prefer this to littering my code with asserts.
local function readByte(file)
    local str = file:read(1)
    assert(str, "File ended unexpectedly!")
    return str:byte()
end

-- arg is the literal string passed in the Arguments box, no space separation. (TODO: argparse?)
-- It can be null sometimes, even if you type something in. No idea why... You can fix this by
-- hitting restart. I give a different error message when this strange bug occurs.
if not arg then
    print("Command line arguments got lost somehow :(")
    print("Please run this script again.")
    return
end

if #arg==0 then
    print("Please specify a filename in the Arguments box.")
    return
end

local path = arg

local ghost = io.open(path, "rb")
assert(ghost, string.format("\nCould not open ghost file \"%s\"", path))

-- check for signature
assert(ghost:read(4)=="mm2g", "\nInvalid or corrupt ghost file (missing signature).")

local version = readNumBE(ghost, 2)
assert(version <= 3, "\nThis ghost was created with a newer version of mm2ghost.\nPlease download the latest version from https://github.com/warmCabin/mm2ghost/releases")

local ghostLen = readNumBE(ghost, 4)
local ghostIndex = 0 -- keeps track of how many frames have actually been drawn

local screenOffsetX = cfg.xOffset -- Offset all drawing by these values.
local screenOffsetY = cfg.yOffset -- If your emulator behaves differently than mine,
                                  -- you may need to change them in the config file.
    
local showGhost = true
local retroMode = cfg.retro
local checkWrap = cfg.checkWrapping
local startFrame = emu.framecount() + 2 -- offset to line up ghost draws with NES draws
local frameCount = 0
local prevFrameCount = 0
local ghostAlpha = 0.7 -- Could go in config!

local FLIP_FLAG = 1
local WEAPON_FLAG = 2
local ANIM_FLAG = 4
local SCREEN_FLAG = 8
local HALT_FLAG = 16

if version < 2 then
    print("This ghost does not contain screen information. Screen wrapping enabled.")
    checkWrap = false
end

local ghostData = {}

--[[
    Load the contents of the ghost file into memory. Ghost files RLE compress animIndex and weapon data, but this
    data is expanded in RAM. If we're loading savestates, we shouldn't have to scrub backwards to see where the
    animIndex was last changed. It's a space/time tradeoff.
    Maybe I could do some kind of keyframe array or something.
    Perhaps a nifty data metatable could be used to some effect as well.
    
    This function can properly parse v0-v3 ghost files. Anything below v2 is considered deprcated, because this
    function is already getting pretty messy!
]]
local function init()
    
    -- These "cur" values are used to un-RLE the ghost data.
    local curWeapon = 0
    local curAnimIndex = 0xFF
    local curScreen
    
    for i = 1, ghostLen do
    
        local data = {}
    
        data.xPos = readByte(ghost)
        data.yPos = readByte(ghost)
        
        if version <= 1 then
            -- X scroll was uselessly stored in versions 0 and 1; read and discard it
            readByte(ghost)
        end
        
        if version == 0 then
            -- animIndex was stored for every frame in version 0
            data.animIndex = readByte(ghost)
        end
        
        local flags = readByte(ghost)
        
        if AND(flags, FLIP_FLAG) ~= 0 then
            data.flipped = true
        end
        
        if AND(flags, WEAPON_FLAG) ~= 0 then
            data.weapon = readByte(ghost)
            curWeapon = data.weapon
        else
            data.weapon = curWeapon
        end
        
        if AND(flags, ANIM_FLAG) ~= 0 then
            data.animIndex = readByte(ghost)
            curAnimIndex = data.animIndex
        else
            -- default to curAnimIndex if data.animIndex isn't present, which it won't be in v2+
            data.animIndex = data.animIndex or curAnimIndex
        end
        
        if AND(flags, SCREEN_FLAG) ~= 0 then
            data.screen = readByte(ghost)
            curScreen = data.screen
        else
            --curScreen will always remain nil in versions before 2
            data.screen = curScreen
        end
        
        if AND(flags, HALT_FLAG) ~= 0 then
            data.halt = true
        end
        
        ghostData[startFrame + i - 1] = data
    end    
end

print(string.format("Loading \"%s\"...", path))
init()
print("Done.")

print(string.format("Playing ghost on frame %d", emu.framecount()))
print(string.format("%d frames of data", ghostLen))
print()
    
--[[
    TODO: config.lua should contain:
        [ ] Ghost directory, so user only specifies the name.
        [O] screen offset X and Y
        [O] "retro" (flickery) mode
        [O] Enable wrapping
]]

local SCROLLING = 156
local INVALID_STATES = {195, 247, 255, 78, 120}

local xPosEmu
local yPosEmu
local screenEmu = 0
local drawScreenEmu = 0
local prevDrawScreenEmu = 0
local prevScrlXEmu = 0
local scrlXEmu = 0
local prevScrlYEmu = 0
local scrlYEmu = 0
local prevGameState = 0
local gameState = 0
local scrollStartFrame = 0
local scrollingUp = false
local weapon = 0
local prevSelect = false

--[[
    This function is simple enough that it seems like it should be inline.
    BUT! I have plans to make an online mode that reads straight from the file
    and doesn't support savestates, like it used to. Just in case memory usage
    gets out of hand. That behavior will be handled in this function.
]]
local function readData()
    
    local fc = emu.framecount()
    if fc < startFrame or fc >= startFrame+ghostLen then
        return nil
    end
    
    if fc > startFrame then
        prevScrlGhost = ghostData[fc-1].scrl
    end
    ghostData[fc].screen = ghostData[fc].screen or memory.readbyte(0x0440)
    return ghostData[fc]
    
end

-- Determines the screen X coordinate from the given world coordinate, based on the current scroll value.
-- Cool bitwise stuff stolen from mm2_minimap.lua!
local function getScreenX(xPos)
    return math.ceil(AND(xPos + 255 - prevScrlXEmu, 255))
end

-- Determines the screen Y coordinate from the given world coordinate, based on the current scroll value.
-- Wrapping by multiples of 240 isn't quite so elegant!
local function getScreenY(yPos)
    local y = yPos - prevScrlYEmu
    
    -- Y position is signed...sort of. When Mega Man jumps off the top of the screen, it goes negative...i.e., Y=255
    -- But, readByteSigned is not a valid choice here, because Y >= 128 can also signify halfway down the screen...what to do???
    if y < 0 then
        y = y + 240
    end
    -- elseif drawY > 240 then
    --   drawY = drawY - 240
    -- end
    
    return y
end

--[[
    Wrapping checks (to make sure ghosts don't draw when they're too far away).
    These aren't quite sufficient on their own. Screen scrolls set the screen number a bit prematurely,
    so the logic in update() that fixes it up is necessary.
    Wrapping is further complicated by the fact that there is no such thing as up, down, left, and right rooms in Mega Man 2;
    only PREVIOUS and NEXT. The screen and X/Y coordinates are therefore not sufficient to compute the relative inter-screen
    position of Mega Man and a ghost. We can monitor the scroll values to determine what's really happening.
]]

-- Wrapping check based on proximity of ghost to Mega Man.
-- It checks if the difference in SCREEN coordinates between the two Mega Men is equal to the difference in WORLD coordinates.
local function proximityCheck(data)

    local drawX    = getScreenX(data.xPos)
    local drawXEmu = getScreenX(xPosEmu)
    local drawY    = getScreenY(data.yPos)
    local drawYEmu = getScreenY(yPosEmu)

    if scrlYEmu == 0 then
        -- horizontal transition, large contiguous room, or not scrolling.
        if drawX - drawXEmu ~= (data.screen*256 + data.xPos) - (screenEmu*256 + xPosEmu) then
            return false
        end
    elseif scrollingUp then
        -- FIXME: there's a 1-frame fuckup in this case. It's because drawY uses the previous frame's scroll value. Maybe use prevScreenEmu?
        if drawY - drawYEmu ~= (-data.screen*240 + data.yPos) - (-screenEmu*240 + yPosEmu) then
            return false
        end
    else
        -- scrolling down
        if drawY - drawYEmu ~= (data.screen*240 + data.yPos) - (screenEmu*240 + yPosEmu) then
            return false
        end
    end
    
    return true
end

-- TODO: logic to support vertical scrolls as well. Should be very similar to proximityCheck.
local function drawScreenCheck(data)
    local x = (data.screen - prevDrawScreenEmu)*256 + data.xPos - prevScrlXEmu
    -- gui.text(5, 30, string.format("scroll: %d", prevScrlXEmu))
    -- gui.text(5, 40, string.format("ghostly x: %d", x))
    -- gui.text(5, 50, string.format("ghostly screen #: %d", data.screen))
    -- gui.text(5, 60, string.format("ghostly actual x: %d", data.xPos))
    if x > 0 and x < 256 then
        return true
    end
end

local function shouldDraw(data)
    for _, state in ipairs(INVALID_STATES) do
        if gameState==state then return false end
    end
    
    if not showGhost then return false end
    
    if not checkWrap then return true end
    
    return proximityCheck(data) or drawScreenCheck(data)
end

--[[
    In preparation for the multighost update:
        - much of this should stay in a general update function
        - much of this can go in an individual ghost update function. Might be tricky with all these pesky local variables.
        - can specify multiple ghosts by separating paths w/ semicolon
]]
local function update()

    -- It seems scroll is use-then-set, while position is set-then-use, if that makes sense.
    -- It's necessary to use the previous frame's scroll value to make things line up properly.
    
    -- FIXME: when panning backwards in TASEditor, the ghost is screwy.
    -- This is because it uses the wrong prevScrlXEmu value.
    -- The solution is to store a table of all the scroll values...is it worth it?
    
    xPosEmu = memory.readbyte(0x0460)
    yPosEmu = memory.readbyte(0x04A0)
    prevScrlXEmu = scrlXEmu
    prevScrlYEmu = scrlYEmu
    screenEmu = memory.readbyte(0x0440)
    prevDrawScreenEmu = drawScreenEmu
    drawScreenEmu = memory.readbyte(0x20)
    prevGameState = gameState
    scrlXEmu = memory.readbyte(0x1F)
    scrlYEmu = memory.readbyte(0x22)
    gameState = memory.readbyte(0x01FE)  
    
    if gameState==SCROLLING and prevGameState~=SCROLLING then
        scrollStartFrame = emu.framecount()
    end
    
    local scrollDuration = emu.framecount() - scrollStartFrame
    scrollingUp = scrlYEmu < prevScrlYEmu
    
    -- gui.text(5,30,string.format("%s (%d)",scrollingUp and "up scroll" or "down scroll",scrollDuration))
    
    -- Hacky fixup for screen number. Screen transitions set it a bit prematurely.
    -- Boss doors behave slightly differently than regular horizontal scrolls, because of course they do.
    -- Regular horizontal scrolls increment the screen number as soon as the scroll commences.
    -- Boss door scrolls increment the screen number as soon as the door begins to open, which is
    -- about 1 second before the actual scroll commences.
    -- However, in both cases, this occurs after exactly 33 frames of waiting, so that's what I check for.
    -- Downwards scrolling needs a similar fixup, but upwards does not.
    
    -- TODO: split this out for sure. Can set the global screenEmu or return updated value.
    if gameState==SCROLLING and scrollDuration >= 32 and scrollDuration <= 91 then
        if scrlXEmu==0 and scrlYEmu==0 then
            -- assume boss door for now
            screenEmu = screenEmu - 1
        elseif scrlXEmu ~= 0 and xPosEmu > 200 then
            -- scrolling horizontally for sure
            screenEmu = screenEmu - 1
        elseif scrlYEmu ~= 0 then
            yPosEmu = yPosEmu + scrlYEmu
            if not scrollingUp and yPosEmu > 200 then
                screenEmu = screenEmu - 1
            end
        end
    end
    
    ghostIndex = emu.framecount() - startFrame
    
    if ghostIndex==ghostLen then
        print("Ghost finished playing on frame "..emu.framecount()..".")
    end
    
    -- gui.text(5,10,string.format("you:   %d:%d; state=%d, scrl=%d",screenEmu,yPosEmu,gameState,scrlYEmu))
    
    local data = readData()
    if not data then return end -- this frame is out of range of the ghost. Possibly put this check in shouldDraw
    
    if not shouldDraw(data) then return end
    
    local xPos = data.xPos
    local yPos = data.yPos
    local screen = data.screen
    
    local anmData = anm.update(data)
    
    -- Mega Man not on screen this frame.
    if anmData.noDraw then
        return
    end 
    
    -- Unknown animation index! Draw an error squarror.
    if not anmData.image then
        local animIndex = anmData.animIndex
        local message = anmData.errorMessage
        local drawX = getScreenX(xPos) + screenOffsetX + 8
        local drawY = getScreenY(yPos) + screenOffsetY
        
        gui.box(drawX, drawY, drawX + 24, drawY + 24)
        gui.text(drawX + 8, drawY, string.format("%02X", animIndex))
        gui.text(10, 10, message, "FFFFFF") -- TODO: add a nice queue for dynamic gui.text messages
        print(message)
        return
    end
    
    local image = anmData.image
    local offsetX = anmData.offsetX
    local offsetY = anmData.offsetY
    
    local drawX    = getScreenX(xPos)    + offsetX + screenOffsetX
    local drawXEmu = getScreenX(xPosEmu) + offsetX + screenOffsetX
    
    -- gui.text(5,20,string.format("ghost: %d:%d",screen,drawX))
    
    local drawY    = getScreenY(yPos)    + offsetY + screenOffsetY
    local drawYEmu = getScreenY(yPosEmu) + offsetY + screenOffsetY
    -- gui.text(0,10,"drawY: "..drawY)
    -- gui.text(0,30,"yScrlDraw: "..yScrlDraw)
    -- gui.text(0,40,"yPos: "..yPos)
 
    -- gui.text(5,40,"drawY after: "..drawY)
    
    if retroMode then
        -- Create a retro-style flicker transparency!
        if emu.framecount() % 3 ~= 0 then     --2 on, 1 off. This creates a pseudo-transparency of 0.67, which is close enough
            gui.image(drawX, drawY, image, 1.0) --to the 0.7 value used below.
        end
    else
        gui.image(drawX, drawY, image, ghostAlpha)
    end

end

local function main()
    prevFrameCount = frameCount
    frameCount = emu.framecount()
    
    if frameCount ~= prevFrameCount then
        update()
    end
end
gui.register(main)

local function hideButton()
    showGhost = not showGhost
end
taseditor.registermanual(hideButton, "Show/Hide Ghost")

emu.registerexit(function()
    print("Ghosts...")
    print("...don't...")
    print("...DIE!")
    ghost:close() -- They do get closed, though!
end)
