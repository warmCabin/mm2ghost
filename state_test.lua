--[[
    A little something you can run if you're troubleshoooting compatibility with a new hack.
]]

local gs = require("rom_utils")

emu.registerafter(function()
    
    local state = gs.getGameState()
    gui.text(10, 10, string.format("state: %s", gs.getGameState() or "unknown"))
    
    if not state then
        print("Unknown state on frame "..emu.framecount())
        -- emu.pause()
    end
    
end)
