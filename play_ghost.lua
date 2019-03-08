
local bit = require("bit")

--Read number Big-endian
local function readNumBE(file,length)
	assert(length<=8,"Read operation will overflow.")
	local ans = 0
	for i=1,length do
		ans = ans*256 + file:read(1):byte()
	end
	return ans
end

--read byte or crash. I prefer this to littering my code with asserts.
local function readByte(file)
	local str = file:read(1)
	assert(str, "File ended unexpectedly!")
	return str:byte()
end

--arg is the literal string passed in the Arguments box, no space separation.
--It can be null sometimes, even if you type something in. No idea why... You can fix this by
--hitting restart. I give a different error message when this strange bug occurs.
if not arg then
	print("Command line arguments got lost somehow :(")
	print("Please run this script again.")
	return
end

if #arg==0 then
	print("Please specify a filename in the Arguments box.")
	return
end

local path = arg

local ghost = io.open(path,"rb")
assert(ghost, string.format("\nCould not open ghost file \"%s\"",path))

--check for signature
assert(ghost:read(4)=="mm2g", "\nInvalid or corrupt ghost file.")

local version = readNumBE(ghost,2)
assert(version==0, "\nThis ghost was created with a newer version of mm2ghost.\nPlease download the latest version.")

local ghostLen = readNumBE(ghost,4)
local ghostIndex = 0 --keeps track of how many frames have actually been drawn

local screenOffsetX = -14 --offset all drawing by these values.
local screenOffsetY = -11 --If your emulator behaves differently than mine,
                          --you may need to change them.	  
	
local showGhost = true
local startFrame = emu.framecount() + 2 --offset to line up ghost draws with NES draws.
local frameCount = 0
local prevFrameCount = 0

local ghostData = {}

--[[
	Load the contents of the ghost file into memory. Ghost files RLE compress animIndex and weapon data, but this
	data is expanded in RAM. If we're loading savestates, we shouldn't have to scrub backwards to see where the
	animIndex was last changed. It's a space/time tradeoff.
	Maybe I could do some kind of keyframe array or something.
]]
local function init()
	
	local curWeapon = 0
	local curAnimIndex = 0xFF
	
	for i=1,ghostLen do
	
		local data = {}
	
		data.xPos = readByte(ghost)
		data.yPos = readByte(ghost)
		data.scrl = readByte(ghost)
		if version==0 then
			data.animIndex = readByte(ghost)
		end
		local flags = readByte(ghost)
		
		data.flipped = AND(flags,1)~=0
		
		if AND(flags,2)~=0 then
			data.weapon = readByte(ghost)
			curWeapon = data.weapon
		else
			data.weapon = curWeapon
		end
		
		if AND(flags,4)~=0 then
			data.animIndex = readByte(ghost)
			curAnimIndex = data.animIndex
		else
			data.animIndex = data.animIndex or curAnimIndex
		end
		
		ghostData[startFrame+i-1] = data
	
	end
	
end

print(string.format("Loading \"%s\"...",path))
init() --maybe init could be a do block lol
print("Done.")

print(string.format("Playing ghost on frame %d",emu.framecount()))
print(string.format("%d frames of data",ghostLen))
print()
	
--[[
	TODO: config.lua?
		It should contain:
		Ghost directory, so user only specifies the name.
		screen offset X and Y
]]

--[[
	Reads data from a gd image file. Lua and FCEUX have no image manipulation support whatsoever,
	so typically people install the Lua GD library. FCEUX IS capable of drawing images, but only
	in the GD string format--were they trying to get around a licensing issue? Either way, it's
	up to you to find and install a copy of the GD library.
	
	...OR!
	
	You could look up the format specs and make your own damn gd strings. These things are straight ARGB.
	Just an array of bytes that get processed as the color channels for each pixel. No compression,
	no DPI stuff, no aspect ratio, no color spaces, NOTHING. Just alpha, red, green, blue, repeat.
	It's honestly kind of nice. But it's also kind of terrible. It means you have to pass around these
	bulky 2KB strings (yes, they have to be strings) in all your drawing code. I've already taken up 25%
	the size of Rockman 2 with just these pictures of Mega Man! Hopefully your computer doesn't run out
	of memory, and hopefully this code runs fast enough to be fun to use.

	If you're a Windows user and you're as lazy as me, you'll appreciate not needing to run a makefile
	and shove a bunch of random DLLs into your path!
]]
local function readGD(filename)
	local img = io.open(filename,"rb")
	assert(img,string.format("Could not open file %s",filename))
	local str = img:read(99999999)
	assert(not img:read(1), "That's a BIG image. Let's not get carried away, here.")
	img:close()
	return str
end

--[[
	Sprite mirroring. Returns a flipped version of the given GD image.
	This function simply iterates through each row and reverses the order of the pixels.
	It has to do this in 4-byte tuples, which gets a little confusing.
]]
local function flipGD(gdStr)
	
	local width  = gdStr:byte(3)*256 + gdStr:byte(4)
	local height = gdStr:byte(5)*256 + gdStr:byte(6)
	local buff = {}
	local bi = 12
	
	for i=1,11 do --copy the header over indiscriminately
		buff[i] = gdStr:byte(i)
	end
	
	for i=0,height-1 do    --real programmers index their shit by 0, dammit!
		for j=0,width-1 do --The math works out so nice!
			buff[bi]   = gdStr:byte(12 + i*width*4 + (width-j-1)*4) 
			buff[bi+1] = gdStr:byte(12 + i*width*4 + (width-j-1)*4 + 1)
			buff[bi+2] = gdStr:byte(12 + i*width*4 + (width-j-1)*4 + 2)
			buff[bi+3] = gdStr:byte(12 + i*width*4 + (width-j-1)*4 + 3)
			bi = bi + 4 --table.insert is O(N). This isn't!
		end
	end
	
	--Dump the bytes into a stupid bulky string and return it.
	return string.char(unpack(buff))
	
end

--Load a few images beforehand to prevent duplicate loading.
local running2 = readGD("mmframes/running2.gd")
local running2Flipped = flipGD(running2)
local runshoot2 = readGD("mmframes/runshoot2.gd")
local runshoot2Flipped = flipGD(runshoot2)
local teleport1 = readGD("mmframes/teleport.gd")
local climb = readGD("mmframes/climb.gd")

--[[
	Maps the animation indexes to image files.
	These correspond to 0x400 in RAM, and are stored as the 4th byte of every tuple in a ghost file.
	format: gd image, x offset, y offset, duration. Duration of 0 or nil means forever, i.e. a non-looping animation.
]]
local anim = {}
anim[0x00] = {{readGD("mmframes/standing.gd"),0,0,91}, {readGD("mmframes/blinking.gd"),4,0,9}}
anim[0x01] = {{readGD("mmframes/standnshoot.gd"),4,0}}
anim[0x03] = {{readGD("mmframes/standnthrow.gd"),4,0}} 
anim[0x04] = {{readGD("mmframes/tiptoe.gd"),4,0}}
anim[0x05] = anim[0x01]
anim[0x07] = anim[0x03]
anim[0x08] = {{readGD("mmframes/running.gd"),0,2,7},  {running2,5,0,7},  {readGD("mmframes/running3.gd"),1,2,7}, {running2,5,0,7}}
anim[0x09] = {{readGD("mmframes/runshoot.gd"),0,2,7}, {runshoot2,5,0,7}, {readGD("mmframes/runshoot3.gd"),1,2,7}, {runshoot2,5,0,7}}
anim[0x0B] = anim[0x03]
anim[0x0C] = {{readGD("mmframes/falling.gd"),0,0}}
anim[0x0D] = {{readGD("mmframes/fallnshoot.gd"),1,0}}
anim[0x0F] = {{readGD("mmframes/fallnthrow.gd"),2,0}}
anim[0x10] = anim[0x04]
anim[0x11] = anim[0x01]
anim[0x13] = anim[0x03]
anim[0x14] = anim[0x00]
anim[0x15] = {{anim[0x09][1][1],anim[0x09][1][2],anim[0x09][1][3],2}, {anim[0x01][1][1],anim[0x01][1][2],anim[0x01][1][3],0}} --anim[0x01] --anim[0x09]
anim[0x17] = {{readGD("mmframes/standnthrow.gd"),4,0}}
anim[0x18] = {{readGD("mmframes/knockback.gd"),2,0}}
anim[0x1A] = {{teleport1,10,-8,3}, {readGD("mmframes/teleport2.gd"),4,-3,3}, {readGD("mmframes/teleport3.gd"),4,13,3}, {teleport1,10,-8,0}}
anim[0x1B] = {{climb,7,0,9},{flipGD(climb),7,0,9}}
anim[0x1C] = {{readGD("mmframes/climbnshoot.gd"),-1,0}}
anim[0x1E] = {{readGD("mmframes/climbnthrow.gd"),-1,0}}
anim[0x1F] = {{readGD("mmframes/ass.gd"),7,0}}
anim[0x20] = anim[0x1C]
anim[0x22] = anim[0x1E]
anim[0x26] = {anim[0x1A][1], anim[0x1A][3], anim[0x1A][2], anim[0x1A][4]}

--[[
	left-facing versions of all the sprites.
	Note that Rockman 2 stores left-facing graphics, and flips them to face right...
	Since all the offsets are different for flipped images, it made the most sense to
	recreate the entire table. There's a lot of redundant data here, I know...
	I suppose I could put in flip offsets for each anim entry. Y offsets are the same for both.
]]
local flip = {}
flip[0x00] = {{flipGD(anim[0x00][1][1]),5,0,91}, {flipGD(anim[0x00][2][1]),5,0,9}}
flip[0x01] = {{flipGD(anim[0x01][1][1]),-5,0}}
flip[0x03] = {{flipGD(anim[0x03][1][1]),-1,0}}
flip[0x04] = {{flipGD(anim[0x04][1][1]),6,0}}
flip[0x05] = flip[0x01]
flip[0x07] = flip[0x03]
flip[0x08] = {{flipGD(anim[0x08][1][1]),4,2,7}, {running2Flipped,9,0,7}, {flipGD(anim[0x08][3][1]),8,2,7}, {running2Flipped,9,0,7}}
flip[0x09] = {{flipGD(anim[0x09][1][1]),-1,2,7}, {runshoot2Flipped,-1,0,7}, {flipGD(anim[0x09][3][1]),-1,2,7}, {runshoot2Flipped,-1,0,7}}
flip[0x0B] = flip[0x03]
flip[0x0C] = {{flipGD(anim[0x0C][1][1]),2,0}}
flip[0x0D] = {{flipGD(anim[0x0D][1][1]),-1,0}}
flip[0x0F] = {{flipGD(anim[0x0F][1][1]),0,0}}
flip[0x10] = flip[0x04]
flip[0x11] = flip[0x01]
flip[0x13] = flip[0x03]
flip[0x14] = flip[0x00]
flip[0x15] = flip[0x01] --flip[0x09]
flip[0x17] = flip[0x03]
flip[0x18] = {{flipGD(anim[0x18][1][1]),2,0}}
flip[0x1A] = anim[0x1A]
flip[0x1B] = anim[0x1B]
flip[0x1C] = {{flipGD(anim[0x1C][1][1]),7,0}}
flip[0x1E] = {{flipGD(anim[0x1E][1][1]),7,0}}
flip[0x1F] = {{flipGD(anim[0x1F][1][1]),7,0}}
flip[0x20] = flip[0x1C]
flip[0x22] = flip[0x1E]
flip[0x26] = anim[0x26]

local palettes = {} --outline, undies, body
palettes[0]  = {{r=0,g=0,b=0},{r=0,g=112,b=236},{r=0,g=232,b=216}}     --P
palettes[1]  = {{r=0,g=0,b=0},{r=228,g=0,b=88},{r=240,g=188,b=60}}     --H
palettes[2]  = {{r=0,g=0,b=0},{r=0,g=112,b=236},{r=252,g=252,b=252}}   --A
palettes[3]  = {{r=0,g=0,b=0},{r=0,g=148,b=0},{r=252,g=252,b=252}}     --W
palettes[4]  = {{r=0,g=0,b=0},{r=0,g=112,b=236},{r=252,g=252,b=252}}   --B
palettes[5]  = {{r=0,g=0,b=0},{r=252,g=116,b=180},{r=252,g=196,b=252}} --Q
palettes[6]  = {{r=0,g=0,b=0},{r=188,g=0,b=188},{r=252,g=196,b=252}}   --F
palettes[7]  = {{r=0,g=0,b=0},{r=136,g=112,b=0},{r=252,g=216,b=168}}   --M
palettes[8]  = {{r=0,g=0,b=0},{r=252,g=116,b=96},{r=252,g=252,b=252}}  --C
palettes[9]  = {{r=0,g=0,b=0},{r=216,g=40,b=0},{r=252,g=252,b=252}}    --1
palettes[10] = palettes[9]                                             --2
palettes[11] = palettes[9]                                             --3

--[[
	Convert a blue & cyan Mega Man image to the appropriate weapon palette.
	The GD string format used by FCEUX actually has a paletteized mode...but FCEUX
	doesn't support it for whatever asinine reason.
	Remind me to actually verify that, though...
	
	This code checks for the specific RGB values in the Mega Man images I use.
	Actually, it only checks for the specific G values!
	Run this on other images for unpredictable results!
]]
local function paletteize(gdStr,pIndex)

	local pal = palettes[pIndex]
	if not pal then
		gui.text(10,20,"Unknown weapon "..pIndex)
		gui.text(10,30,"Are you hacking...?")
		return gdStr
	end
	
	local width  = gdStr:byte(3)*256 + gdStr:byte(4)
	local height = gdStr:byte(5)*256 + gdStr:byte(6)
	local buff = {}
	local bi = 12
	
	for i=1,11 do --copy the header over indiscriminately
		buff[i] = gdStr:byte(i)
	end
	
	for i=0,height-1 do
		for j=0,width-1 do
			local a = gdStr:byte(12 + i*width*4 + j*4)
			local r = gdStr:byte(12 + i*width*4 + j*4 + 1)
			local g = gdStr:byte(12 + i*width*4 + j*4 + 2)
			local b = gdStr:byte(12 + i*width*4 + j*4 + 3)
			buff[bi] = a
			if g==112 then --blue undies
				buff[bi+1] = pal[2].r
				buff[bi+2] = pal[2].g
				buff[bi+3] = pal[2].b
			elseif g==232 then --cyan body
				buff[bi+1] = pal[3].r
				buff[bi+2] = pal[3].g
				buff[bi+3] = pal[3].b
			elseif g==0 then --outline
				buff[bi+1] = pal[1].r
				buff[bi+2] = pal[1].g
				buff[bi+3] = pal[1].b
			else
				buff[bi+1] = r
				buff[bi+2] = g
				buff[bi+3] = b
			end
			
			bi = bi + 4 --table.insert is O(N). This isn't!
		end
	end
	
	--Dump the bytes into a stupid bulky string and return it.
	return string.char(unpack(buff))

end

--[[
for k,v in pairs(anim) do
	flip[k] = {flipGD(anim[k][1]),0,anim[k][3],anim[k][4]}
	flip[k][2] = 
end ]]

local skip = true
local prevScrlGhost = 0
local scrlGhost = 0
local prevScrlEmu = 0
local scrlEmu = 0
local prevScrlYEmu = 0
local scrlYEmu = 0
local weapon = 0

local animFrame = 1
local animTimer = -1
local animIndex = 0
local prevAnimIndex = 0
local animChangeCount = 0

--[[
	This function is simple enough that it seems like it should be inline.
	BUT! I have plans to make an online mode that reads straight from the file
	and doesn't support savestates, like it used to. Just in case memory usage
	gets out of hand. That behavior will be handled in this function.
]]
local function readData()
	
	local fc = emu.framecount()
	if fc < startFrame or fc >= startFrame+ghostLen then
		return nil
	end
	
	if fc-1 >= startFrame then
		prevScrlGhost = ghostData[fc-1].scrl
	end
	return ghostData[fc]
	
end

local function update()

	--It seems scroll is use-then-set, while position is set-then-use, if that makes sense.
	--It's necessary to use the previous frame's scroll value to make things line up properly.
	--FIXME: when panning backwards in TASEditor, the ghost is fucky.
	--This is because it uses the wrong prevScrlEmu value.
	--The solution is to store a table of all the scroll values.....is it worth it?
	
	--prevScrlGhost = scrlGhost
	prevScrlEmu = scrlEmu
	prevScrlYEmu = scrlYEmu
	prevAnimIndex = animIndex
	scrlEmu = memory.readbyte(0x001F)
	scrlYEmu = memory.readbyte(0x0022)--memory.readbyte(0x0022)
	
	local xScrlDraw = prevScrlEmu
	local yScrlDraw = prevScrlYEmu
	local xPosEmu = memory.readbyte(0x460)
	local yPosEmu = memory.readbyte(0x4A0)
	
	--Hack to line up ghost draws with NES draws.
	--[[if skip then
		skip = false
		return
	end]]
	
	ghostIndex = emu.framecount() - startFrame
	
	if ghostIndex==ghostLen then
		print("Ghost finished playing on frame "..emu.framecount()..".")
		--ghost:close()
		--return gui.register() --Ghost is done playing. Unregister our callback and return.
	end
	
	--ghostIndex = ghostIndex + 1 
	
	local data = readData()
	if not data then return end --this frame is out of range of the ghost
	
	local xPos = data.xPos
	local yPos = data.yPos
	scrlGhost = data.scrl
	local xScrl = prevScrlGhost
	animIndex = data.animIndex
	local animTable
	
	--Try to restore this functionality.
	--Do I reall need to, though?
	--[[if AND(flags,2) ~= 0 then
		weapon = ghost:read(1):byte()
		print(string.format("Switched to weapon %d",weapon))
	end ]]
		
	--gui.text(10,10,string.format("%02X",animIndex))
	
	if data.flipped then --right facing
		animTable = anim
	else                 --left facing
		animTable = flip
	end
	
	if animIndex==0xFF then --Nothing to draw!
		return
	end
	
	if animIndex ~= prevAnimIndex then
		if (animIndex==0x08 and prevAnimIndex==0x09) or (animIndex==0x09 and prevAnimIndex==0x08) then
			--Mega Man still running. Preserve frame when switching between these indexes.
		else
			animFrame = 1
			if animTable[animIndex] then
				animTimer = animTable[animIndex][animFrame][4]
			else
				animTimer = -1
			end
		end
	end
	
	local scrlOffsetX = xScrlDraw - xScrl
	
	if not animTable[animIndex] then
		local drawX = math.ceil(AND(xPos-scrlOffsetX+255-xScrl,255)) + screenOffsetX + 8
		local drawY = yPos + screenOffsetY
		--local drawY = math.ceil(AND(yPos-curScrlY+255,255)) + screenOffsetY
		gui.box(drawX,drawY,drawX+24,drawY+24)
		gui.text(drawX+8,drawY,string.format("%02X",animIndex))
		local msg = string.format("Unknown animation index %02X! (%sflipped)", animIndex, (animTable==flip) and "" or "not ")
		gui.text(10,10,msg,"FFFFFF")
		print(msg)
		--emu.pause()
		return
	end
	
	local img = animTable[animIndex][animFrame][1] --does this copy the whole string over?
	if weapon ~= 0 then --TODO: PRECOMP THESE!!! This processes 2KB of data 60 times a second!!
		img = paletteize(img,weapon)
	end
	
	local offsetX = animTable[animIndex][animFrame][2]
	local offsetY = animTable[animIndex][animFrame][3]
	local drawX    = math.ceil(AND(xPos-scrlOffsetX+255-xScrl,255)) + offsetX + screenOffsetX
	local drawXEmu = math.ceil(AND(xPosEmu+255-xScrlDraw,255)) + offsetX + screenOffsetX
	
	--Y position wrapping.
	--For X I can use cool bitwise shit (stolen from mm2_minimap.lua), but wrapping by multiples of 240
	--isn't quite so elegant.
	local drawY = yPos - yScrlDraw
	if drawY<0 then
		drawY = drawY + 240
	end
	--elseif drawY > 240 then
	--	drawY = drawY - 240
	--end
	drawY = drawY + offsetY + screenOffsetY
	
	local duration = animTable[animIndex][animFrame][4]
	if duration and duration>0 then
		animTimer = animTimer - 1
	else
		animTimer = -1
	end
	
	if animTimer==0 then
		animFrame = animFrame % #animTable[animIndex] + 1
		animTimer = animTable[animIndex][animFrame][4]
	end
	
	--[[
	--simple check for screen wrap behavior. It doesn't work at all.
	--At each screen border, Mega Man's world position wraps around to 0 but he is still further
	--to the right than any ghosts on the previous screen. And that's just for horizontal scrolling!
	--With vertical scrolling, the next screen could be above OR below you, so it's hard to detect a proper wrap.
	--I need to store screen numbers in the ghost file.
	if curXPos>xPos and drawXCur<drawX then
		gui.text(10,10,"You're killing it!")
		return
	end ]]
	
	if showGhost then gui.image(drawX,drawY,img,0.7) end
	
	--retro style
	--[[if emu.framecount()%2==0 then
		gui.image(drawX,drawY,img,1.0)
	end--]]

end

local function main()
	
	prevFrameCount = frameCount
	frameCount = emu.framecount()
	
	if frameCount ~= prevFrameCount then
		update()
	end
	
end
gui.register(main)

local function hideButton()
	showGhost = not showGhost
end
taseditor.registermanual(hideButton,"Show/Hide Ghost")
