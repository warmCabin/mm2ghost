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
local dmg = require("damage_taker")
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

-- arg is the literal string passed in the Arguments box, no space separation. (TODO: argparse?)
-- It can be nil sometimes, even if you type something in. No idea why. It really does get lost somewhere!
-- You can fix this by hitting Restart.
assert(arg, "Command line arguments got lost somehow :(\nPlease run this script again.")

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
local STAGE_FLAG = 32

print(string.format("Initiating cosmic clone on frame %d", emu.framecount()))

local SCROLLING = 156
local PLAYING = 178
local BOSS_RUSH = 100
local LAGGING = 149
local LAGGING2 = 171 -- ???
local LAGGING3 = 93  -- lagging during boss rush????
local HEALTH_REFILL = 119
local PAUSED = 128
local DEAD = 156 -- also scrolling/waiting
local MENU = 197
local READY = 82
local BOSS_KILL = 143
local DOUBLE_DEATH = 134 -- It's a different gamestate somehow!!
local DOUBLE_DEATH2 = 146 -- ???
local WILY_KILL = 65 -- basically BOSS_KILL
local LOADING = 255

local validStates = {PLAYING, BOSS_RUSH, LAGGING, HEALTH_REFILL, BOSS_KILL, LAGGING2, DOUBLE_DEATH, DOUBLE_DEATH2, WILY_KILL, LAGGING3}
local INVALID_STATES = {195, 247, 255, 78, 120, 197}

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
local prevGameState = 0
local gameState = 0
local scrollStartFrame = 0
local scrollingUp = false
local weapon = 0
local iFrames = 0
local cosmicOffset = 90

local cloneData = {}

local function readData()
    if gameState == PAUSED or gameState == HEALTH_REFILL then
        -- Shift everything ahead by 1 frame
        for i = emu.framecount(), emu.framecount() - cosmicOffset, -1 do
            cloneData[i] = cloneData[i - 1]
        end
        -- Show the ghost frozen in place if this is a health refill. Otherwise hide it.
        if gameState == HEALTH_REFILL then
            local data = cloneData[emu.framecount() - cosmicOffset + 1]
            data.halt = true
            return cloneData[emu.framecount() - cosmicOffset + 1]
        else
            return nil
        end
    else
        return cloneData[emu.framecount() - cosmicOffset]
    end
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

local function collides(x1, y1, w1, h1, x2, y2, w2, h2)
    return x1 < x2 + w2 
        and x1 + w1 > x2
        and y1 < y2 + h2
        and y1 + h1 > y2
end

local function validState(gameState)
    for _, state in ipairs(validStates) do
        if state==gameState then return true end
    end
    return false
end

--[[
    Will most likely scrap all of this as I work on the multighost update.
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
    
    -- Add current frame's data to cosmic queue
    if validState(gameState) and memory.readbyte(0xF9) == 0 then
        local packet = {}
        packet.animIndex = memory.readbyte(0x0400)
        packet.flipped = AND(memory.readbyte(0x0420), 0x40) ~= 0
        packet.weapon = memory.readbyte(0xA9)
        packet.xPos = xPosEmu
        packet.yPos = yPosEmu
        packet.screen = screenEmu
        cloneData[emu.framecount()] = packet
    end
    
    -- Remove clone data we no longer need.
    -- Lua, you BETTER have garbage collection.
    cloneData[emu.framecount() - cosmicOffset - 1] = nil
    
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
    
    local data = readData()
    if not data then return end -- The clone is watching and waiting.
    
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
    local drawY    = getScreenY(yPos)    + offsetY + screenOffsetY
    local drawYEmu = getScreenY(yPosEmu) + offsetY + screenOffsetY
    
    if collides(drawX, drawY, 12, 16, drawXEmu, drawYEmu, 12, 16) then
        if dmg.takeDamage(8) and memory.readbyte(0x06C0) ~= 0 then
            -- Set facing direction to the opposite of the ghost, just like in-game enemies.
            -- "Flipped" in this script is inverted from what the game considers "flipped,"
            -- because I hadn't reverse engineered the sprite flags yet. Tech debt!
            local flags = memory.readbyte(0x0420)
            flags = AND(flags, 0xBF)
            if not data.flipped then
                flags = OR(flags, 0x40)
            end
            memory.writebyte(0x0420, flags)
        end
    end
    
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
