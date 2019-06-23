--[[
	This is actually a Lua soruce file. All it does is return this nifty little table.
	Make sure that each item except the last is followed by a comma, i.e., they're comma-separated.
	Write comments with double dash or the dash-bracket syntax seen in this file.
]]
return {

	xOffset = -14, --Offset all ghost draws by this amount. These are provided to account for
	yOffset = -11, --subtle and arcane differences in emulator environments.
	retro = false, --Old-school flickery mode!
	checkWrapping = true --disable this to make ghosts wrap when they get too far ahead.
						 --Might be useful for, e.g., the zips at the beginning of Crash.

}
