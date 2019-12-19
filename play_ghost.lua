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
local function readNumBE(file,length)
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
local INVALID_STATES = {195, 247, 255}

local screenEmu = 0
local drawScreenEmu = 0
local prevDrawScreenEmu = 0
local prevScrlEmu = 0
local scrlEmu = 0
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

-- Wrapping checks (to make sure ghosts don't draw when they're too far away).
-- These aren't quite sufficient on their own. Screen scrolls set the screen number a bit prematurely,
-- so the logic in update() that fixes it up is necessary.
-- Wrapping is further complicated by the fact that there is no such thing as up, down, left, and right rooms in Mega Man 2;
-- only PREVIOUS and NEXT. The screen and X/Y coordinates are therefore not sufficient to compute the relative inter-screen
-- position of Mega Man and a ghost. We can monitor the scroll values to determine what's really happening.

-- TODO: put the old wrapping check in here!
local function proximityCheck(data)
    return false
end

-- TODO: logic to support vertical scrolls as well.
local function drawScreenCheck(data)
    local x = (data.screen - prevDrawScreenEmu)*256 + data.xPos - prevScrlXEmu
    -- gui.text(5, 30, string.format("scroll: %d", prevScrlXEmu))
    -- gui.text(5, 40, string.format("ghostly x: %d", x))
    -- gui.text(5, 50, string.format("ghostly screen #: %d", data.screen))
    -- gui.text(5, 60, string.format("ghostly actual x: %d", data.xPos))
    if x >= 0 and x < 256 then
        return true
    end
end

local function shouldDraw(data)
    for _, state in ipairs(INVALID_STATES) do
        if gameState==state then return false end
    end
    
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
    -- This is because it uses the wrong prevScrlEmu value.
    -- The solution is to store a table of all the scroll values...is it worth it?
    
    prevScrlXEmu = scrlXEmu
    prevScrlYEmu = scrlYEmu
    screenEmu = memory.readbyte(0x0440)
    prevDrawScreenEmu = drawScreenEmu
    drawScreenEmu = memory.readbyte(0x20)
    prevGameState = gameState
    scrlXEmu = memory.readbyte(0x1F)
    scrlYEmu = memory.readbyte(0x22)
    gameState = memory.readbyte(0x01FE)
    
    local xScrlDraw = prevScrlXEmu
    local yScrlDraw = prevScrlYEmu
    local xPosEmu = memory.readbyte(0x0460)
    local yPosEmu = memory.readbyte(0x04A0)
    
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
    if gameState==SCROLLING and scrollDuration >= 32 and scrollDuration <= 91 then
        if scrlXEmu==0 and scrlYEmu==0 then
            -- assume boss door for now
            screenEmu = screenEmu - 1
        elseif scrlXEmu~=0 and xPosEmu>200 then
            -- scrolling horizontally for sure
            screenEmu = screenEmu - 1
        elseif scrlYEmu~=0 then
            yPosEmu = yPosEmu + scrlYEmu
            if not scrollingUp and yPosEmu>200 then
                screenEmu = screenEmu-1
            end
        end
    end
    
    ghostIndex = emu.framecount() - startFrame
    
    if ghostIndex==ghostLen then
        print("Ghost finished playing on frame "..emu.framecount()..".")
    end
    
    -- gui.text(5,10,string.format("you:   %d:%d; state=%d, scrl=%d",screenEmu,yPosEmu,gameState,scrlYEmu))
    
    local data = readData()
    if not data then return end -- this frame is out of range of the ghost
    
    local xPos = data.xPos
    local yPos = data.yPos
    local screen = data.screen
    
    local offsetX, offsetY, img = anm.update(data)
    
    -- Mega Man not on screen this frame.
    if not offsetX then
        return
    end
    
    -- Unknown animation index! Draw an error squarror.
    if not img then
        local animIndex = offsetX -- First return value from anm.update was actually animIndex.
        local msg = offsetY       -- Second return value from anm.update was actually error message.
        local drawX = math.ceil(AND(xPos + 255 - xScrlDraw, 255)) + screenOffsetX + 8
        local drawY = yPos + screenOffsetY
        -- local drawY = math.ceil(AND(yPos-curScrlY+255,255)) + screenOffsetY
        gui.box(drawX, drawY, drawX + 24, drawY + 24)
        gui.text(drawX + 8, drawY, string.format("%02X", animIndex))
        gui.text(10, 10, msg, "FFFFFF") -- TODO: add a nice queue for dynamic gui.text messages
        print(msg)
        return
    end
    
    
    local drawX    = math.ceil(AND(xPos + 255 - xScrlDraw, 255))    + offsetX + screenOffsetX
    local drawXEmu = math.ceil(AND(xPosEmu + 255 - xScrlDraw, 255)) + offsetX + screenOffsetX
    
    -- gui.text(5,20,string.format("ghost: %d:%d",screen,drawX))
    
    -- Y position wrapping (to make sure drawY is on-screen).
    -- For X I can use cool bitwise stuff (stolen from mm2_minimap.lua), but wrapping by multiples of 240
    -- isn't quite so elegant.
    local drawY = yPos - yScrlDraw
    local drawYEmu = yPosEmu - yScrlDraw
    -- gui.text(0,10,"drawY: "..drawY)
    -- gui.text(0,30,"yScrlDraw: "..yScrlDraw)
    -- gui.text(0,40,"yPos: "..yPos)
    
    -- Need to detect when drawY goes negative. Signed reads aren't appropriate because drawY can be >=128...
    if drawY < 0 then
        drawY = drawY + 240
    end
    -- elseif drawY > 240 then
    --   drawY = drawY - 240
    -- end
    -- gui.text(5,40,"drawY after: "..drawY)
    drawY = drawY + offsetY + screenOffsetY
    drawYEmu = drawYEmu + offsetY + screenOffsetY
    
    -- FIXME: Y position is signed...sort of. When Mega Man jumps off the top of the screen, it goes negative...i.e., Y=255
    -- But, readByteSigned is not a valid choice here, because Y >= 128 can also signify halfway down the screen...what to do???
    
    -- if not shouldDraw(data) then return end 
    
    -- TODO: Put this in shouldDraw, for the love of God.
    -- drawXEmu and drawYEmu are the only things that really need to be passed or split off
    if checkWrap and not shouldDraw(data) then
        if scrlYEmu == 0 then
            -- horizontal transition, large contiguous room, or not scrolling.
            if drawX - drawXEmu ~= (screen*256 + xPos) - (screenEmu*256 + xPosEmu) then
                return
            end
        elseif scrollingUp then
            -- FIXME: there's a 1-frame fuckup in this case. It's because drawY uses the previous frame's scroll value.
            if drawY - drawYEmu ~= (-screen*240 + yPos) - (-screenEmu*240 + yPosEmu) then
                return
            end
        else
            -- scrolling down
            if drawY - drawYEmu ~= (screen*240 + yPos) - (screenEmu*240 + yPosEmu) then
                return
            end
        end
    end
    
    if showGhost then
        if retroMode then
            -- Create a retro-style flicker transparency!
            if emu.framecount() % 3 ~= 0 then       --2 on, 1 off. This creates a pseudo-transparency of 0.67, which is close enough
                gui.image(drawX, drawY, img, 1.0) --to the 0.7 value used below.
            end
        else
            gui.image(drawX, drawY, img, ghostAlpha)
        end
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
