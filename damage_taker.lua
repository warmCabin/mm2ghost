local bit = require("bit")
local rshift, band = bit.rshift, bit.band

local mod = {}

local function shouldTakeDamage()
    local x = memory.readbyte(0x0460)
    return band(memory.readbyte(0x27), 4) ~= 0
    -- return emu.framecount() % 300 == 0
    -- return x == 0x84
end

local function luaPush(value)
    local sp = memory.getregister("s")
    
    memory.writebyte(0x0100 + sp, value)
    memory.setregister("s", sp - 1)
end

local function luaJsr(address)
    local pc = memory.getregister("pc") - 1 -- need to offset by current pc instruction length...?
    
    -- 1 minus where it should go, little endian
    luaPush(rshift(pc, 8))
    luaPush(band(pc, 0xFF))
    memory.setregister("pc", address)
    -- debugger.hitbreakpoint()
    
end

-- A lot of weirdness happens when you call this from a registerexec.
local function takeDamage(amount)
    -- print(emu.framecount().." - took damage")
    luaJsr(0xD32F) -- seem to need to offset this by the length of the current pc instruction...?
        
    local health = memory.readbyte(0x06C0)
    local newHealth = math.max(health - 8, 0)
    memory.writebyte(0x06C0, math.max(health - 8, 0))
        
    if newHealth == 0 then
        memory.writebyte(0x2C, 0)
        memory.setregister("pc", 0xC10B) -- Death routine
    end
end

function mod.takeDamage(amount)
    local action = memory.readbyte(0x2C)
    local gameState = memory.readbyte(0x01FE)
    local iFrames = memory.readbyte(0x4B)
    local health = memory.readbyte(0x06C0)
    
    if gameState ~= 0xB2 or iFrames ~= 0 or health == 0 then
        return false
    end
    
    takeDamage(amount)
    return true
end

return mod
