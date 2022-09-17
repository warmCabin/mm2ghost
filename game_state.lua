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
    gui.text(10, 20, string.format("classic: %02X", state))
    if not state then
        gui.text(10, 60, string.format("Unrecognized game state %02X!", state))
    end
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
    
    gui.text(10, 30, string.format("newpa: %02X [i=%02X]", memory.readbyte(0x0100 + i), i))
    
    return rm2States[memory.readbyte(0x0100 + i)]
    
end


function mod.getGameState()
    if emu.framecount() >= 20 and classic() ~= pauseExitKludge() then
        gui.text(10, 70, "disagreement")
        --emu.pause()
    end
    
    gui.text(10, 80, string.format("SP: %02X", memory.getregister("s")))
    
    return pauseExitKludge()
end

return mod
