
local bit = require("bit")
local anm = require("animation")

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
assert(ghost:read(4)=="mm2g", "\nInvalid or corrupt ghost file (missing signature).")

local version = readNumBE(ghost,2)
assert(version<=1, "\nThis ghost was created with a newer version of mm2ghost.\nPlease download the latest version.")

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
	Perhaps a nifty data metatable could be used to some effect as well.
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
		
		if AND(flags,4)~=0 and version>0 then
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

local skip = true
local prevScrlGhost = 0
local scrlGhost = 0
local prevScrlEmu = 0
local scrlEmu = 0
local prevScrlYEmu = 0
local scrlYEmu = 0
local weapon = 0

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
	
	if fc > startFrame then
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
	scrlYEmu = memory.readbyte(0x0022)
	
	local xScrlDraw = prevScrlEmu
	local yScrlDraw = prevScrlYEmu
	local xPosEmu = memory.readbyte(0x460)
	local yPosEmu = memory.readbyte(0x4A0)
	
	--Hack to line up ghost draws with NES draws.
	--[[if skip then
		skip = false
		return
	end]]
	
	--ghostIndex = ghostIndex + 1 
	ghostIndex = emu.framecount() - startFrame
	
	if ghostIndex==ghostLen then
		print("Ghost finished playing on frame "..emu.framecount()..".")
	end
	
	local data = readData()
	if not data then return end --this frame is out of range of the ghost
	
	local xPos = data.xPos
	local yPos = data.yPos
	scrlGhost = data.scrl
	local xScrl = prevScrlGhost
	
	local offsetX, offsetY, img = anm.update(data)
	
	if not offsetX then --Mega Man not on screen this frame.
		return
	end
	
	local scrlOffsetX = xScrlDraw - xScrl
	
	if not img then --unknown animation index! Draw an error squarror.
		local animIndex = offsetX
		local msg = offsetY
		local drawX = math.ceil(AND(xPos-scrlOffsetX+255-xScrl,255)) + screenOffsetX + 8
		local drawY = yPos + screenOffsetY
		--local drawY = math.ceil(AND(yPos-curScrlY+255,255)) + screenOffsetY
		gui.box(drawX,drawY,drawX+24,drawY+24)
		gui.text(drawX+8,drawY,string.format("%02X",animIndex))
		gui.text(10,10,msg,"FFFFFF") --TODO: add a nice queue for dynamic gui.text messages
		print(msg)
		--emu.pause()
		return
	end
	
	local drawX    = math.ceil(AND(xPos-scrlOffsetX+255-xScrl,255)) + offsetX + screenOffsetX
	local drawXEmu = math.ceil(AND(xPosEmu+255-xScrlDraw,255)) + offsetX + screenOffsetX
	
	--Y position wrapping.
	--For X I can use cool bitwise shit (stolen from mm2_minimap.lua), but wrapping by multiples of 240
	--isn't quite so elegant.
	local drawY = yPos - yScrlDraw
	--gui.text(0,10,"drawY: "..drawY)
	--gui.text(0,30,"yScrlDraw: "..yScrlDraw)
	--gui.text(0,40,"yPos: "..yPos)
	if drawY<0 then
		drawY = drawY + 240
	end
	--elseif drawY > 240 then
	--	drawY = drawY - 240
	--end
	--gui.text(0,20,"drawY after: "..drawY)
	drawY = drawY + offsetY + screenOffsetY
	--FIXME: Y position is signed...sort of. When Mega Man jumps off the top of the screen, it goes negative...i.e., Y=255
	--But, readByteSigned is not a valid choice here, because Y >= 128 can also signify halfway down the screen...what to do???
	
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

emu.registerexit(function()
	print("Ghosts...")
	print("...don't...")
	print("...DIE!")
	ghost:close() --they do get closed, though!
end)
