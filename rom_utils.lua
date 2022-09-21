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
    Other Rockman2 BM notes:
      - Something's up with teleporting out of boss rooms. Neither BM nor vanilla uses $F9 there.
          Mega Man stops when he hits the top of the screen in vanilla, but keeps looping in BM. Wtf?
          In both versions, Mega Man is killed with an LSR $0420. This is why he disappears.
      - Ghost disappears in vertical scroll situations.
]]
local bmStates = {
    [0xA9] = "playing", -- CHANGED
    -- [100] = "playing", -- Boss rush?
    [0x8C] = "lagging", -- CHANGED
    [0xA2] = "lagging", -- CHANGED
    -- [93] = "lagging", -- Boss rush? Do we care?
    -- [999] = "refill", -- Not aplicable beceause it doesn't freeze you.
    [0x77] = "paused", -- CHANGED
    [0x93] = "scrolling", -- CHANGED
    -- Why
    [0x5B] = "get equipped",
    [0xFD] = "get equipped",
    [0x02] = "get equipped",
    [0xEA] = "get equipped",
    [0xBA] = "get equipped",
    [0x68] = "get equipped",
    [0x6E] = "get equipped",
    [0x7E] = "get equipped",
    [0x8A] = "get equipped",
    [0x8F] = "get equipped",
    [0x94] = "get equipped",
    [0xCD] = "get equipped",
    [0xE5] = "get equipped",
    [0x03] = "get equipped",
    [0x30] = "get equipped",
    [0x38] = "get equipped",
    [0x78] = "get equipped",
    
    [0x52] = "ready", -- Unchanged
    [0x86] = "boss kill", -- CHANGED
    -- [134] = "spike death", -- Should both of these just be "dying"?
    [0x92] = "enemy death", -- Figure out
    [0x41] = "wily kill",
    [0xC3] = "loading", -- Unchanged
    [0xF7] = "loading", -- Unchanged
    [0xFF] = "loading", -- Unchanged
    [0x78] = "stage select", -- Unchanged
    --[0x4E] = "get equipped",
    [0x67] = "teleporting in", -- Unchanged
}

local bmPalOverrides = {
    [4]  = {"P0F", "P38", "P2B"}, -- Flame Candle
    [5]  = {"P0F", "P34", "P07"}, -- Snake Buster
    [8]  = {"P0F", "P24", "P08"}, -- Gemini Time
    [10] = {"P0F", "P2C", "P11"}, -- Item 2 (same as Buster palette)
}

--[[
    Gets gamestate from the stack.
    
    "gameState" is actually the low byte of whatever return address happens to be on top of the stack. There's no convenient game state
    variable that says "We are in a level" or "We are in a menu," so this really is the easiest way to track it. It's equivalent to setting
    a bunch of callbacks on a bunch of addresses, more or less.
]]
local function classic()
    local state = memory.readbyte(0x01FE)
    return rm2States[state]
end

--[[
    Kludge for the pause-exit bug.
    The obvious and natural way to do add a pause-exit feature to Rockman 2 is to simply have the menu code JMP to the level select screen.
    Unfortunately, this leaves 13 extra bytes on the stack, which confuses mm2ghost and can cause crashes if done enough times.
    For this kludge, we iterate backwards in steps of 13 until we find a non-pause menu address. But what if we're ACTUALLY paused?
    Well, there are some reliable values 13 bytes down the stack that we can use to detect that.
]]
local function pauseExitKludge()
    local sp = memory.getregister("s")
    local i = 0xFE
    
    while memory.readbyte(0x0100 + i) == 0x80 do
        i = i - 13
    end

    return rm2States[memory.readbyte(0x0100 + i)]
end

-- Need to figure out a better check here. Presumably based on scroll flags?
-- I'm not sure what the $C251 or $C259 return addresses are, but they seem to appear once you get Gemini Time.
local function rm2Bm()
    local topOfStack = memory.readword(0x01FE)
    local state = 0
    if topOfStack == 0xC259 or topOfStack == 0xC251 then
        state = memory.readbyte(0x01FC)
    else
        state = memory.readbyte(0x01FE)
    end
    
    return bmStates[state]
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

local hashTable = {
    ["770d55a19ae91dcaa9560d6aa7321737"] = {
        name = "vanilla Rockman 2",
        gameState = classic
    },
    ["0527a0ee512f69e08b8db6dc97964632"] = {
        name = "vanilla Mega Man 2",
        gameState = classic
    },
    ["a4b6728bd51fe9b8913525267c209f32"] = {
        name = "Rockman 2: Basic Master v1.2",
        gameState = rm2Bm,
        overrides = bmPalOverrides
    },
}

local romData = hashTable[rom.gethash("md5")]
if romData then
    print(string.format("You are playing %s.", romData.name))
    mod.getGameState = romData.gameState
    mod.paletteOverrides = romData.overrides
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
