--[[
    Records a v3 ghost file as you play. See format specs v3.txt for the specifics. Or infer them from my code ;)
    You can provide a path to the desired recording location as an argument (in the Arguments box). If you don't, the script will
    generate a filename based on the time and date by default.
    
    
    TODO: prompt for "This file already exists." (gui.popup)
          Alternatively, MAKE A PROPER FUCKING FILE SELECTOR GUI.
    
    TODO: Can't create new directories?
]]

local bit = require("bit")
local loader = require("load_ghost")
local rshift, band = bit.rshift, bit.band

local function writeNumBE(file, val, length)
    for i = length-1, 0, -1 do
        file:write(string.char(band(rshift(val, i*8), 0xFF))) -- Lua makes binary file I/O such a pain.
        -- file.write( (val>>(i<<3)) & 0xFF ) -- How things could be. How they SHOULD be.
    end
end

local function writeByte(file, val)
    file:write(string.char(val))
end

if not arg then
    print("Command line arguments got lost somehow :(")
    print("Please run this script again.")
    return
end

local baseDir = "ghosts"
--local filename
--[[
if #arg > 0 then
    filename = arg
elseif movie.active() and not taseditor.engaged() then
    filename = movie.getname()
    local idx = filename:find("[/\\\\][^/\\\\]*$") -- last index of a slash or backslash
    filename = filename:sub(idx + 1, path:len())   -- path now equals the filename, e.g. "my_movie.fm2"
else -- TODO: Have record.lua record to the same temp file every time? 
    -- There's a bug with the TASEditor! movie.active() returns true, but movie.getname() returns an empty string.
    if taseditor.engaged() then
        print("WARNING: TASEditor is active. Can't name ghost after movie.")
        print()
    end
    filename = os.date("%Y-%m-%d %H-%M-%S.ghost")
end ]]

--local path = rootPath.."/"..filename
--if path:sub(path:len() - 5, path:len()) ~= ".ghost" then
--    path = path..".ghost"
--end

local VERSION = 3

--local ghost = io.open(path, "wb")
--assert(ghost, "Could not open \""..path.."\"")
local ghost = loader.writeGhost(baseDir)

--print("Writing to \""..path.."\"...")
print("Writing to ghost file...")

ghost:write("mm2g") -- signature
writeNumBE(ghost, VERSION, 2) -- 2-byte version
writeNumBE(ghost, 0, 4) -- 4-byte length. This gets written later.

local gameState = 0
local flipped = true
local prevWeapon = 0
local prevAnimIndex = 0xFF
local prevScreen = -1
local length = 0

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

-- TODO: invalid states??? {PAUSED, DEAD, MENU, READY}
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
    Detects if Mega Man is flipped by scanning OAM for his face sprite.
    There's some sort of flag at 0x0042 that seems to store this data, but I don't trust it.
    This OAM approach fails when Mega Man is:
        - climbing a ladder (and not shooting)
        - in the "splat" frame of his knockback animation
        - teleporting
    This function returns the last known value when Mega Man isn't on scren, which is acceptable
    behavior for all three of these cases.
]]
local function isFlipped()
    
    for addr = 0x200, 0x2FC, 4 do
        local tile = memory.readbyte(addr + 1)
        -- the 4 tiles for Mega Man's facial expressions
        if tile==0x00 or tile==0x20 or tile==0x2E or tile==0x2F then
            local attr = memory.readbyte(addr + 2)
            return AND(attr, 0x40) ~= 0
        end
    end
    
    -- Mega Man's face is not on screen! Default to direction from previous frame.
    return flipped 
end

local function getAnimIndex()

    -- $F9 stores an off-screen flag
    if memory.readbyte(0x00F9)~=0 or not validState(gameState) then
        return 0xFF
    else
        return memory.readbyte(0x0400)
    end 
end

local FLIP_FLAG = 1
local WEAPON_FLAG = 2
local ANIM_FLAG = 4
local SCREEN_FLAG = 8
local HALT_FLAG = 16

local function main()

    length = length + 1
    gameState = memory.readbyte(0x01FE)

    local xPos = memory.readbyte(0x460)
    local yPos = memory.readbyte(0x4A0)
    local vySub = memory.readbyte(0x0660)
    local animIndex = getAnimIndex()
    local weapon = memory.readbyte(0x00A9)
    local screen = memory.readbyte(0x0440)
    flipped = isFlipped()
    
    -- TODO: Is this constant writing bad? Does Lua automatically buffer file I/O?
    writeByte(ghost, xPos)
    writeByte(ghost, yPos)
    
    local flags = 0
    
    if isFlipped() then
        flags = OR(flags, FLIP_FLAG)
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
    
    -- TODO: also do this if lagging.
    -- FIXME: This does not work at all. Actually check if up or down is being pressed.
    if gameState==HEALTH_REFILL or isClimbing() and vySub==0 then
        flags = OR(flags, HALT_FLAG)
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
    
    prevWeapon = weapon
    prevAnimIndex = animIndex
    prevScreen = screen
end
emu.registerafter(main)

-- Gets called when the script is closed/stopped.
local function finalize()
    print("Finishsed recording on frame "..emu.framecount()..".")
    print("Ghost is "..length.." frames long.")
    ghost:seek("set", 0x06) -- Length was unknown until this point. Go back and save it.
    writeNumBE(ghost, length, 4)
    ghost:close()
end
emu.registerexit(finalize)
