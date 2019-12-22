require("iuplua")

local mod = {}

local function fixup(filename)
    if filename:sub(filename:len() - 5) ~= ".ghost" then
        filename = filename..".ghost"
    end
    return filename
end

local function concat(baseDir, filepath)
    filepath = fixup(filepath)
    local endChar = baseDir:sub(baseDir:len())
    if endChar=='/' or endChar=='\\' then
        return baseDir..filepath
    else
        return baseDir.."/"..filepath
    end
end

function mod.readGhostString(baseDir, filepath)
    local file = io.open(concat(baseDir, filepath), "rb") or io.open(filepath, "rb")
    assert(file, string.format("\nCould not open ghost file \"%s\"", filepath))
    return file
end

function mod.writeGhostString(baseDir, filepath)
    local file = io.open(concat(baseDir, filepath), "wb") or io.open(filepath, "wb")
    assert(file, string.format("\nCould not open ghost file \"%s\"", filepath))
    return file
end

--function mod.pickGhost(baseDir, operation)
  -- maybe  
--end

-- TODO: maybe have all these return the strings instead of file pointers
function mod.readGhost(baseDir)

    local filedlg = iup.filedlg{
      dialogtype = "OPEN",
      filter = "*.ghost",
      filterinfo = "Ghost files (*.ghost)",
      directory = baseDir
    }

    filedlg:popup(iup.CENTER, iup.CENTER)

    local status = tonumber(filedlg.status)
    local file
  
    if status ~= -1 then
        local filename = filedlg.value
        -- print(string.format("status=%d, filename=%s", status, filename))
        print(string.format("Opening \"%s\"...", filename))
        file = io.open(filename, "rb")
        assert(file, string.format("\nCould not open ghost file \"%s\"", filename))
    end
  
    filedlg:destroy()
    return file -- will be nil if user picked no file
    
end

function mod.writeGhost(baseDir)

    local filedlg = iup.filedlg{
      dialogtype = "SAVE",
      filter = "*.ghost",
      filterinfo = "Ghost files (*.ghost)",
      directory = baseDir
    }

    filedlg:popup(iup.CENTER, iup.CENTER)

    local status = tonumber(filedlg.status)
    local file
  
    if status ~= -1 then
        local filename = fixup(filedlg.value)
        print(string.format("Opening \"%s\"...", filename))
        file = io.open(filename, "wb")
        assert(file, string.format("\nCould not open ghost file \"%s\"", filename))
    end
  
    filedlg:destroy()
    return file -- will be nil if user picked no file
  
end

-- mod.writeGhost("./ghosts")

return mod
