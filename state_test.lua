--[[
    A little something you can run if you're troubleshoooting compatibility with a new hack.
]]

local ru = require("rom_utils")

emu.registerafter(function()
    
    local state = ru.getGameState()
    gui.text(10, 10, string.format("state: %s", state or "unknown"))
    
    if not state then
        print("Unknown state on frame "..emu.framecount())
        -- emu.pause()
    end
    
end)
