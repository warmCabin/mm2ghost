--[[

	Records a v2 ghost file as you play. See format specs v2.txt for the specifics. Or infer them from my code ;)
	You can provide a path to the desired recording location as an argument (in the Arguments box). If you don't, the script will
	generate a filename based on the time and date by default.
	
	
	TODO: prompt for "This file already exists." (gui.popup)
		  Alternatively, MAKE A PROPER FUCKING FILE SELECTOR GUI.
	
	TODO: Can't create new directories?

]]

local bit = require("bit")
local rshift,band = bit.rshift, bit.band

local function writeNumBE(file,val,len)
	for i=len-1,0,-1 do
		file:write(string.char(band(rshift(val,i*8),0xFF))) --Lua makes binary file I/O such a pain.
		--file.write( (val>>(i<<3)) & 0xFF ) --how things could be. How they SHOULD be.
	end
end

if not arg then
	print("Command line arguments got lost somehow :(")
	print("Please run this script again.")
	return
end

local path

if #arg > 0 then --TODO: Fuck arg! There's a built in gui library!
	path = arg
elseif movie.active() and not taseditor.engaged() then
	path = movie.getname()
	local idx = string.find(path,"[/\\\\][^/\\\\]*$") --last index of a slash or backslash
	path = path:sub(idx+1,path:len())                 --path now equals the filename, e.g. "my_movie.fm2"
	path = "ghosts/"..path..".ghost"
else --TODO: Have record.lua record to the same temp file every time? 
	--There's a bug with the TASEditor! movie.active() returns true, but movie.getname() returns an empty string.
	if taseditor.engaged() then
		print("WARNING: TASEditor is active. Can't name ghost after movie.")
		print()
	end
	path = os.date("ghosts/%Y-%m-%d %H-%M-%S.ghost")
end 

local ghost = io.open(path,"wb")
assert(ghost,"Could not open \""..path.."\"")

print("Writing to \""..path.."\"...")
ghost:write("mm2g\0\2\0\0\0\0") --signature + 2 byte version + 4 byte length. Length will be written later.

local gameState = 0
local flipped = true
local prevWeapon = 0
local prevAnimIndex = 0xFF
local prevScreen = -1
local len = 0 --I guess this is a Lua keyword. Oh well!

local PLAYING = 178
local BOSS_RUSH = 100
local LAGGING = 149
local LAGGING2 = 171 --???
local HEALTH_REFILL = 119
local PAUSED = 128
local DEAD = 156 --also scrolling/waiting
local MENU = 197
local READY = 82
local BOSS_KILL = 143
local DOUBLE_DEATH = 134 --It's a different gamestate somehow!!

local validStates = {PLAYING, BOSS_RUSH, LAGGING, HEALTH_REFILL, MENU, BOSS_KILL, LAGGING2, DOUBLE_DEATH}

local function validState()
	gameState = memory.readbyte(0x01FE)
	for _,state in ipairs(validStates) do
		if state==gameState then return true end
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
	
	for addr=0x200,0x2FC,4 do
		local tile = memory.readbyte(addr+1)
		if tile==0x00 or tile==0x20 or tile==0x2E or tile==0x2F then --4 tiles for Mega Man's face expressions
			local attr = memory.readbyte(addr+2)
			return AND(attr,0x40) ~= 0
		end
	end
	
	return flipped --Mega Man's face is not on screen! Default to direction from previous frame.
	
end

local function main()

	len = len + 1

	local xPos = memory.readbyte(0x460)
	local yPos = memory.readbyte(0x4A0)
	local animIndex = memory.readbyte(0x0400)
	local weapon = memory.readbyte(0x00A9)
	local screen = memory.readbyte(0x0440)
	flipped = isFlipped()
	
	ghost:write(string.char(xPos))
	ghost:write(string.char(yPos))
	
	if not validState() then
		animIndex = 0xFF
	end
	
	local flags = 0
	
	if isFlipped() then
		flags = OR(flags,1)
	end
	
	if weapon ~= prevWeapon then
		flags = OR(flags,2) --buff[#buff+1] = weapon
		print(string.format("Switched to weapon %d",weapon))
	end
	
	if animIndex ~= prevAnimIndex then
		flags = OR(flags,4)
	end
	
	if screen ~= prevScreen then
		flags = OR(flags,8)
	end
	
	ghost:write(string.char(flags))
	
	--It kills me, but we have to make these checks twice. Maybe I could write a little buffer or something.
	--ghost:write(string.char(unpack(buff)))
	if weapon ~= prevWeapon then
		ghost:write(string.char(weapon))
	end
	
	if animIndex ~= prevAnimIndex then
		ghost:write(string.char(animIndex))
	end
	
	if screen ~= prevScreen then
		ghost:write(string.char(screen))
	end
	
	prevWeapon = weapon
	prevAnimIndex = animIndex
	prevScreen = screen

end
emu.registerafter(main)

--Gets called when the script is closed/stopped.
local function cleanup()

	print("Finishsed recording on frame "..emu.framecount()..".")
	print("Ghost is "..len.." frames long.")
	ghost:seek("set",0x06) --Length was unknown until this point. Go back and save it.
	writeNumBE(ghost,len,4)
	ghost:close()

end
emu.registerexit(cleanup)
