--[[
    Records a v4 ghost file as you play. See format specs v4.txt for the specifics. Or infer them from my code ;)
    You can provide a path to the desired recording location as an argument (in the Arguments box). If you don't, 
    a file picker will pop up.
    
    TODO: Can't create new directories?
]]

local bit = require("bit")
local loader = require("load_ghost")
local rshift, band = bit.rshift, bit.band
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

-- TODO: A util file that encapsulates file IO and this bootleg asserter.
local function assert(condition, message)
    if not condition then
        error("\n\n==============================\n"..tostring(message).."\n==============================\n")
    end
end

local function writeNumBE(file, val, length)
    -- TODO: overflow checks.
    for i = length-1, 0, -1 do
        file:write(string.char(band(rshift(val, i*8), 0xFF))) -- Lua makes binary file I/O such a pain.
        -- file.write( (val>>(i<<3)) & 0xFF ) -- How things could be. How they SHOULD be.
    end
end

local function writeByte(file, val)
    file:write(string.char(val))
end

assert(arg, "Command line arguments got lost somehow :(\nPlease run this script again.")

local VERSION = 4

local path

if #arg > 0 then
    path = loader.fixup(arg)
else
    path = loader.writeGhost(cfg.baseDir)
    if not path then
        print("No file selected.")
        return
    end
end

local ghost = io.open(path, "wb")
assert(ghost, "Could not open \""..path.."\"")

print("Writing to \""..path.."\"...")

ghost:write("mm2g") -- signature
writeNumBE(ghost, VERSION, 2) -- 2-byte version
writeNumBE(ghost, 0, 4) -- 4-byte length. This gets written later.

local prevGameState
local gameState = 0
local flipped = true
local prevWeapon = 0
local animIndex = 0
local prevAnimIndex = 0xFF
local vySub = 0
local prevScreen = -1
local length = 0
local stageNum
local prevStageNum
local hidden = false
local hideLength

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

-- TODO: invalid states??? {PAUSED, DEAD, MENU, READY}
-- TODO: This is atually a return address, so find a better way to check gamestate.
local validStates = {PLAYING, BOSS_RUSH, LAGGING, HEALTH_REFILL, MENU, BOSS_KILL, LAGGING2, DOUBLE_DEATH, DOUBLE_DEATH2, WILY_KILL, LAGGING3}
local freezeStates = {HEALTH_REFILL, LAGGING, LAGGING2, LAGGING3}
local climbAnims  = {0x1B, 0x1C, 0x1E}

local function validState(gameState)
    for _, state in ipairs(validStates) do
        if state==gameState then return true end
    end
    return false
end

local function isClimbing()
    for _, anim in ipairs(climbAnims) do
        if anim==animIndex then return true end
    end
    return false
end

--[[
    Previously, this function scanned OAM for Mega Man's face sprite and checked if it was flipped, like an idiot.
    I cited this as my reason: "There's some sort of flag at 0x42 that seems to store this data, but I don't trust it."
    
    As it turns out, 0x42 is Mega Man's VELOCITY direction, so it would be inconsistent with the way he was facing
    when taking damage or facing backwards on a moving platform.
    0x0420 stores the actual facing direction, and it is trustworthy.
]]
local function isFlipped()
    return AND(memory.readbyte(0x0420), 0x40) ~= 0
end


local function isFrozen()
    for _, state in ipairs(freezeStates) do
        if gameState==state then return true end
    end
    
    return isClimbing() and not (joypad.get(1).up or joypad.get(1).down)
end

local function getAnimIndex()

    -- $F9 stores an off-screen flag
    if memory.readbyte(0xF9)~=0 or not validState(gameState) then
        return 0xFF
    else
        return memory.readbyte(0x0400)
    end 
end

-- TODO: This doesn't seem to pick up on death.
local function shouldHide()
    return not validState(gameState) and gameState ~= READY
end

local MIRRORED_FLAG = 1
local WEAPON_FLAG = 2
local ANIM_FLAG = 4
local SCREEN_FLAG = 8
local FREEZE_FLAG = 16
local BEGIN_STAGE_FLAG = 32
local HIDE_FLAG = 64

local function main()

    prevGameState = gameState
    gameState = memory.readbyte(0x01FE)

    if hidden then
        if not shouldHide() then
            print(string.format("Hidden for %d frames.", hideLength))
            hidden = false
            writeNumBE(ghost, hideLength, 2)
        else
            hideLength = hideLength + 1
            -- This corresponds to 18 minutes of waiting on a menu screen. No reason to acutally support that...
            assert(hideLength < 65536, "Are you still playing???")
            return
        end
    end

    length = length + 1
    animIndex = getAnimIndex()
    stageNum = memory.readbyte(0x2A)

    local xPos = memory.readbyte(0x0460)
    local yPos = memory.readbyte(0x04A0)
          vySub = memory.readbyte(0x0660)
    local weapon = memory.readbyte(0xA9)
    local screen = memory.readbyte(0x0440)
    flipped = isFlipped()
    
    -- TODO: Is this constant writing bad? Does Lua automatically buffer file I/O?
    writeByte(ghost, xPos)
    writeByte(ghost, yPos)
    
    local flags = 0
    
    if isFlipped() then
        flags = OR(flags, MIRRORED_FLAG)
    end
    
    if weapon ~= prevWeapon then
        flags = OR(flags, WEAPON_FLAG) --buff[#buff + 1] = weapon
        print(string.format("Switched to weapon %d", weapon))
    end
    
    if animIndex ~= prevAnimIndex then
        flags = OR(flags, ANIM_FLAG)
    end
    
    if screen ~= prevScreen then
        flags = OR(flags, SCREEN_FLAG)
    end
    
    if isFrozen() then
        flags = OR(flags, FREEZE_FLAG)
    end
    
    if prevGameState == LOADING and gameState == READY and prevStageNum ~= stageNum then
        -- Stage number is only recorded when a stage load event is detected, so we can have a "floating ghost"
        -- with no stage num, not synced to the loading lag.
        -- prevStage should probably reset when we see any menu screen.
        prevStageNum = stageNum
        flags = OR(flags, BEGIN_STAGE_FLAG)
        print(string.format("Loaded stage %d", stageNum))
    end
    
    if shouldHide() and not hidden then
        print("Hiding ghost.")
        hidden = true
        hideLength = 0
        flags = OR(flags, HIDE_FLAG)
    end
    
    writeByte(ghost, flags)
    
    -- It kills me, but we have to make these checks twice. Maybe I could write a little buffer or something.
    -- ghost:write(string.char(unpack(buff)))
    -- for _, v in ipairs(buff) do writeByte(v) end
    if weapon ~= prevWeapon then
        writeByte(ghost, weapon)
    end
    
    if animIndex ~= prevAnimIndex then
        writeByte(ghost, animIndex)
    end
    
    if screen ~= prevScreen then
        writeByte(ghost, screen)
    end
    
    if AND(flags, BEGIN_STAGE_FLAG) ~= 0 then
        writeByte(ghost, stageNum)
    end
    
    prevWeapon = weapon
    prevAnimIndex = animIndex
    prevScreen = screen
end
emu.registerafter(main)

-- Gets called when the script is closed/stopped.
local function finalize()
    print("Finishsed recording on frame "..emu.framecount()..".")
    print("Ghost is "..length.." frames long.")
    if hidden then
        -- Script was stopped before the ghost became unhidden.
        writeNumBE(ghost, 0, 2)
    end
    -- Length was unknown until this point. Go back and save it.
    ghost:seek("set", 0x06)
    writeNumBE(ghost, length, 4)
    ghost:close()
end
emu.registerexit(finalize)
