local mod = {}

local rm2States = {
    [0xB2] = "playing",
    [0x64] = "playing", -- Boss rush? Do we care?
    [0x95] = "lagging",
    [0xAB] = "lagging",
    [0x5D] = "lagging", -- Boss rush? Do we care?
    [0x77] = "refill",
    [0x80] = "paused",
    [0x9C] = "scrolling", -- Also bottomless pit death. Awkward. Could call it "waiting".
    [0XC5] = "game over",
    [0x52] = "ready",
    [0x8F] = "boss kill",
    [0x86] = "spike death", -- Should both of these just be "dying"?
    [0x92] = "enemy death",
    [0x41] = "wily kill", -- Merge with boss kill?
    [0xC3] = "loading",
    [0xF7] = "loading",
    [0xFF] = "loading",
    [0x78] = "stage select",
    [0x4E] = "get equipped",
    [0x67] = "teleporting in",
    -- Extra states that only appear with the pause exit kludge.
    -- These might not belong in this table.
    [0xC9] = "paused", 
    [0x7D] = "paused",
    [0x93] = "paused",
}

--[[
    Gets gamestate from the stack.
    
    "gameState" is actually the low byte of whatever return address happens to be on top of the stack. There's no convenient game state
    variable that says "We are in a level" or "We are in a menu," so this really is the easiest way to track it. It's equivalent to setting
    a bunch of callbacks on a bunch of addresses, more or less.
]]
local function classic()
    local state = memory.readbyte(0x01F1)
    return rm2States[state]
end

--[[
    Kludge for the pause-exit bug.
    The obvious and natural way to do add a pause-exit feature to Rockman 2 is to simply have the menu code JMP to the level select screen.
    Unfortunately, this leaves 13 extra bytes on the stack, which confuses mm2ghost and can cause crashes if done enough times.
    For this kludge, we iterate backwards in steps of 13 until we find a non-pause menu address. But what if we're ACTUALLY paused?
    Well, there are some reliable values 13 frames down the stack that we can use to detect that.
]]
local function pauseExitKludge()
    local sp = memory.getregister("s")
    local i = 0xFE
    
    while memory.readbyte(0x0100 + i) == 0x80 do
        i = i - 13
    end

    return rm2States[memory.readbyte(0x0100 + i)]
end

local function getBaseRom()
    -- A random byte from the wait_for_next_frame routine,
    -- which happens to be the low byte of the read_controllers routine address.
    -- This is the first byte in bank F that diverges between Rockman 2 and Mega Man 2.
    local sentinel = memory.readbyte(0xC093)
    
    if sentinel == 0xD4 then
        return "rm2"
    elseif sentinel == 0xD7 then
        return "mm2"
    end
end

local hash = rom.gethash("md5")

if hash == "770d55a19ae91dcaa9560d6aa7321737" then
    print("You are playing vanilla Rockman 2.")
    mod.getGameState = classic
elseif hash == "0527a0ee512f69e08b8db6dc97964632" then
    print("You are playing vanilla Mega Man 2.")
    mod.getGameState = classic
else
    local base = getBaseRom()
    if base == "rm2" then
        print("You are playing a Rockman 2 hack.")
        mod.getGameState = pauseExitKludge
    elseif base == "mm2" then
        print("You are playing a Mega Man 2 hack.")
        mod.getGameState = classic
    else
        print("Unrecognized base ROM! Your safety cannot be guaranteed.")
        mod.getGameState = classic
    end
end

return mod
