--[[
    Plays back a ghost file relative to the frame you click Run.
    You can load a savestate and the ghost will travel through time with you; it's all based
    on the frame count.
    You must specify which ghost file to run in the Arguments box.
    
    This script proivdes a button in TASEditor labelled "Show/Hide Ghost." When a ghost is hidden,
    all calculations are still carried out, but it is not drawn. The primary intended use of this
    button is for cleaning up AVI recordings.
    
    Idea: make a control panel GUI that lets you load different ghosts and change the starting offset
]]

local bit = require("bit")
local anm = require("animation")
local loader = require("load_ghost")
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
    checkWrapping = true,
    baseDir = "./ghosts"
}})

local function assert(condition, message)
    if not condition then
        error("\n\n==============================\n"..tostring(message).."\n==============================\n")
    end
end

-- Read number Big-endian
local function readNumBE(file, length)
    assert(length <= 8, "Read operation will overflow.")
    local ans = 0
    for i = 1, length do
        local chr = file:read(1)
        assert(chr, "File ended unexpectedly!")
        ans = ans*256 + chr:byte()
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
-- It can be nil sometimes, even if you type something in. No idea why. It really does get lost somewhere!
-- You can fix this by hitting Restart.
assert(arg, "Command line arguments got lost somehow :(\nPlease run this script again.")

local path

if #arg > 0 then
    path = loader.fixup(arg)
else
    path = loader.readGhost(cfg.baseDir)
    if not path then
        print("No file selected.")
        return
    end
end

local ghost = io.open(path, "rb")
assert(ghost, string.format("\nCould not open ghost file \"%s\"", path))

-- check for signature
assert(ghost:read(4)=="mm2g", "\nInvalid or corrupt ghost file (missing signature).")

-- Version 3 is acceptable because version 4 only adds things to the spec.
local version = readNumBE(ghost, 2)
assert(version <= 4, "\nThis ghost was created with a newer version of mm2ghost.\nPlease download the latest version from https://github.com/warmCabin/mm2ghost/releases")
assert(version >= 3, "\nThis ghost was made with an older version of mm2ghost and is no longer supported.")

local ghostLen = readNumBE(ghost, 4)

assert(ghostLen > 0, "Ghost data is invalid. Did record_ghost.lua terminate properly?")

local screenOffsetX = cfg.xOffset -- Offset all drawing by these values.
local screenOffsetY = cfg.yOffset -- If your emulator behaves differently than mine,
                                  -- you may need to change them in the config file.
    
local showGhost = true
local retroMode = cfg.retro
local checkWrap = cfg.checkWrapping
local startFrame = emu.framecount() + 2 -- offset to line up ghost draws with NES draws
local frameCount = 0
local prevFrameCount = 0
local ghostAlpha = 0.7 -- Could go in config! FCEUX only does 0%, 50%, or 100% anyway. Janky.

local MIRRORED_FLAG = 1
local WEAPON_FLAG = 2
local ANIM_FLAG = 4
local SCREEN_FLAG = 8
local FREEZE_FLAG = 16
local BEGIN_STAGE_FLAG = 32
local HIDE_FLAG = 64

local ghostData = {}

--[[
    Load the contents of the ghost file into memory. Ghost files RLE compress animIndex and weapon data, but this
    data is expanded in RAM. If we're loading savestates, we shouldn't have to scrub backwards to see where the
    animIndex was last changed. It's a space/time tradeoff.

    Maybe I could do some kind of keyframe array or something. Apparetly Braid did that.
    Perhaps a nifty data metatable could be used to some effect as well.

    This function parses v3 and v4 ghost files.
]]
local function init()
    
    -- These "cur" values are used to un-RLE the ghost data.
    local curWeapon = 0
    local curAnimIndex = 0xFF
    local curScreen
    local curStage = memory.readbyte(0x2A)
    
    local dataIndex = 0
    
    for i = 1, ghostLen do
    
        local data = {}
    
        data.xPos = readByte(ghost)
        data.yPos = readByte(ghost)
        
        local flags = readByte(ghost)
        
        if AND(flags, MIRRORED_FLAG) ~= 0 then
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
            data.animIndex = curAnimIndex
        end
        
        if AND(flags, SCREEN_FLAG) ~= 0 then
            data.screen = readByte(ghost)
            curScreen = data.screen
        else
            data.screen = curScreen
        end
        
        if AND(flags, FREEZE_FLAG) ~= 0 then
            data.halt = true
        end
        
        if AND(flags, BEGIN_STAGE_FLAG) ~= 0 then
             -- Overwrites what data was already there for the stage.
             -- Revisiting stages isn't really a use case for this script.
            data.stage = readByte(ghost)
            curStage = data.stage
            dataIndex = 0
            if not ghostData[curStage] then
                ghostData[curStage] = {}
            end
        else
            data.stage = curStage
        end
        
        if AND(flags, HIDE_FLAG) ~= 0 then
            local duration = readNumBE(ghost, 2)
            dataIndex = dataIndex + duration
        end
        
        if not ghostData[curStage] then
            ghostData[curStage] = {}
            -- something something why wasn't the flag set
        end
        
        ghostData[curStage][dataIndex] = data
        dataIndex = dataIndex + 1
    end    
end

print(string.format("Loading \"%s\"...", path))
init()
print("Done.")

print(string.format("Playing ghost on frame %d", emu.framecount()))
print(string.format("%d frames of data", ghostLen))
print()

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
local stageEmu = 0
local prevLoadedStage = -1
local prevGameState = 0
local gameState = 0
local scrollStartFrame = 0
local scrollingUp = false
local weapon = 0
local iFrames = 0

--[[
    This function is simple enough that it seems like it should be inline.
    BUT! I have plans to make an online mode that reads straight from the file
    and doesn't support savestates, like it used to. Just in case memory usage
    gets out of hand. That behavior will be handled in this function.
]]
local function readData()
    
    if not ghostData[stageEmu] then
        return nil
    end
    
    -- TODO: a startFrame for each stage, for ease of panning
    local i = emu.framecount() - startFrame
    local data = ghostData[stageEmu][i]
    
    if not data then
        -- This frame is out of range for the current stage.
        return nil
    end
    
    if ghostData[stageEmu][i - 1] then
        prevScrlGhost = ghostData[stageEmu][i - 1].scrl
    end
    
    return data
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
    -- 0xF9 (the off-screen flag, as seen in record_ghost.getAnimIndex()) could help.
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
        return drawX - drawXEmu == (data.screen*256 + data.xPos) - (screenEmu*256 + xPosEmu)
    elseif scrollingUp then
        -- FIXME: there's a 1-frame fuckup in this case. It's because drawY uses the previous frame's scroll value. Maybe use prevScreenEmu?
        return drawY - drawYEmu == (-data.screen*240 + data.yPos) - (-screenEmu*240 + yPosEmu)
    else
        -- scrolling down
        return drawY - drawYEmu == (data.screen*240 + data.yPos) - (screenEmu*240 + yPosEmu)
    end
end

-- Wrapping check based on the currently visible screen.
-- Mega Man's position gets out of sync with the visible screen during elaborate zipping maneuvers.
-- This check allows ghosts to appear on the visible screen even when the player is physically many screens ahead.
local function drawScreenCheck(data)
    
    if scrlYEmu == 0 then
        -- horizontal transition, large contiguous room, or not scrolling.
        local x = (data.screen - prevDrawScreenEmu)*256 + data.xPos - prevScrlXEmu
        -- gui.text(5, 30, string.format("scroll: %d", prevScrlXEmu))
        -- gui.text(5, 40, string.format("ghostly x: %d", x))
        -- gui.text(5, 50, string.format("ghostly screen #: %d", data.screen))
        -- gui.text(5, 60, string.format("ghostly actual x: %d", data.xPos))
        return x > 0 and x < 256
    else
      return false
    end
    --[[elseif scrollingUp then
        local y = (prevDrawScreenEmu - data.screen + 1)*240 + data.yPos - prevScrlYEmu
        gui.text(5, 30, string.format("scroll: %d", prevScrlYEmu))
        gui.text(5, 40, string.format("ghostly y: %d", y))
        gui.text(5, 50, string.format("ghostly screen #: %d", data.screen))
        gui.text(5, 60, string.format("ghostly actual y: %d", data.yPos))
        return y > 0 and y < 240
    else
        -- scrolling down
        local y = (data.screen - prevDrawScreenEmu)*240 + data.yPos - prevScrlYEmu
        gui.text(5, 30, string.format("scroll: %d", prevScrlYEmu))
        gui.text(5, 40, string.format("ghostly y: %d", y))
        gui.text(5, 50, string.format("ghostly screen #: %d", data.screen))
        gui.text(5, 60, string.format("ghostly actual y: %d", data.yPos))
        return y > 0 and y < 240
    end]]
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
    iFrames = memory.readbyte(0x4B)
    stageEmu = memory.readbyte(0x2A)
    
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
    --   screenEmu = scrollFixup()
    -- FIXME: This fails when scrolling backwards. Simply invert scrollingUp once you figure out how to detect that.
    
    -- Bottomless pit death shares the scrolling game state. But the iFrames variable is reused as a respawning flag,
    -- so it can be used to distinguish between bottomless pits and scrolling.
    -- There's an edge case, however: if your i-frames reach 1 on the exact frame you start to scroll,
    -- this check will not properly set the screen number.
    -- Standard enemy deaths are not a concern.
    if gameState == SCROLLING and iFrames ~= 1 and scrollDuration >= 32 and scrollDuration <= 91 then
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
    
    -- TODO: game state constants
    
    -- Check if new stage was loaded, based on game state.
    -- Also need to check whether we're loading the same stage as previously, which would indicate a death,
    -- and means the ghost data should NOT be realigned (Certain speedrun strats involve taking an intentional death).
    if prevGameState == 255 and gameState == 82 and prevLoadedStage ~= stageEmu then        
        prevLoadedStage = stageEmu
        print(string.format("[%d] Loaded stage %d", emu.framecount(), stageEmu))
        if not ghostData[stageEmu] then print("...but no one came.") end
        startFrame = frameCount + 1
    end
    
    local data = readData()
    if not data then return end -- this frame is out of range of the ghost. Possibly put this check in shouldDraw.
    
    local anmData = anm.update(data)
    
    -- Mega Man not on screen this frame
    if anmData.noDraw then return end
    
    local xPos = data.xPos
    local yPos = data.yPos
    local screen = data.screen
    
    if not shouldDraw(data) then return end
    
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
        if emu.framecount() % 3 ~= 0 then       --2 on, 1 off. This creates a pseudo-transparency of 0.67, which is close enough
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
