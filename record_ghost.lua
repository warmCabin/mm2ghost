
--[[
	Animation index is at 0x400.
	00 - standing still
	01 - stand n' shoot
	03 - stand n' throw
	04 - tiptoe 1
	05 - stand n' shoot
	08 - running
	09 - run n' shoot
	0B - also stand n' throw?
	0C - falling
	0D - jump n' shoot (Most weapons)
	0F - jump n' throw (Items, Metal Blade, Time Stopper)
	10 - tiptoe 2
	11 - tiptoe n' shoot
	13 - also stand n' throw????
	14 - running? or not??
	15 - run n' shoot, animate to stand n' shoot (why?)
	17 - also stand n' throw?????????????
	18 - knockback
	1A - teleport in
	1B - ladder climb
	1C - climb n' shoot
	1E - climb n' throw
	1F - ladder top (ass)
	20 - ass n' shoot?
	26 - teleport out
	
	0x0042 seems to indicate facing, in an abstract gameplay sort of way.
	40 = right, 0 = left.
]]

--[[

	Each frame in a ghost file is 5 bytes:
	xPos yPos xScrl animIndex flags
	
	flags:
	7654 3210
	---- --WF
	|||| ||||
    |||| |||+- Flipped: Whether Mega Man's sprite is flipped (facing right). Updates every frame.
	|||| ||+-- Weapon: Set when the currently equipped weapon changes. When this bit is 1,
	|||| ||    the following byte will be the index of the new weapon, on the range [0,12].
	++++-++--- Unused. Set to 0.
			   
	TODO: Should animIndex be an extra flag/byte? It doesn't change THAT often.
	
	If multiple "extra byte" bits are active, their corresponding extra bytes will appear in order from least to most
	significant bit. i.e., Weapon, then Animation.

]]

local bit = require("bit")
local rshift,band = bit.rshift, bit.band

local function writeNumBE(file,val,len)
	for i=len-1,0,-1 do
		file:write(string.char(band(rshift(val,i*8),0xFF)))
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
ghost:write("mm2g\0\1\0\0\0\0") --signature + 2 byte version + 4 byte length. Length will be written later.

local gameState = 0
local flipped = true
local prevWeapon = 0
local prevAnimIndex = 0xFF
local len = 0

PLAYING = 178
BOSS_RUSH = 100
LAGGING = 149
LAGGING2 = 171 --???
HEALTH_REFILL = 119
PAUSED = 128
DEAD = 156 --also scrolling/waiting
MENU = 197
READY = 82
BOSS_KILL = 143
DOUBLE_DEATH = 134 --it's a different gamestate somehow!!

local function validState()
	gameState = memory.readbyte(0x01FE)
	return gameState==PLAYING or gameState==BOSS_RUSH or gameState==LAGGING or gameState==HEALTH_REFILL or gameState==MENU or gameState==BOSS_KILL or gameState==LAGGING2 or gameState==DOUBLE_DEATH
end

--[[
	Detects if Mega Man is flipped by scanning OAM for his face sprite.
	There's some sort of flag at 0x0042 that seems to store this data...but I don't trust it.
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
	local scrlX = memory.readbyte(0x001F)
	local scrlY = memory.readbyte(0x0022)
	local animIndex = memory.readbyte(0x0400)
	local weapon = memory.readbyte(0x00A9)
	flipped = isFlipped()
	
	ghost:write(string.char(xPos))
	ghost:write(string.char(yPos))
	ghost:write(string.char(scrlX))
	
	if not validState() then
		animIndex = 0xFF
	end
	
	local flags = 0
	
	if isFlipped() then --00 20 2E 2F
		flags = OR(flags,1)
	end
	
	if weapon ~= prevWeapon then
		flags = OR(flags,2)
	end
	
	if animIndex ~= prevAnimIndex then
		flags = OR(flags,4)
	end
	
	ghost:write(string.char(flags))
	
	--It kills me, but we have to make these checks twice. Maybe I could write a little buffer or something.
	if weapon ~= prevWeapon then
		ghost:write(string.char(weapon))
		print(string.format("Switched to weapon %d",weapon))
	end
	
	if animIndex ~= prevAnimIndex then
		ghost:write(string.char(animIndex))
	end
	
	prevWeapon = weapon
	prevAnimIndex = animIndex

end
emu.registerafter(main)

local function cleanup()

	print("Finishsed recording on frame "..emu.framecount()..".")
	print("Ghost is "..len.." frames long.")
	ghost:seek("set",0x06)
	writeNumBE(ghost,len,4)
	ghost:close()

end
emu.registerexit(cleanup)

