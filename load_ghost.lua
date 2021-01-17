require("iuplua")

local mod = {}

function mod.fixup(filename)
    if filename:sub(-6) ~= ".ghost" then
        filename = filename..".ghost"
    end
    return filename
end

local function concat(baseDir, filepath)
    filepath = mod.fixup(filepath)
    local endChar = baseDir:sub(baseDir:len())
    if endChar=='/' or endChar=='\\' then
        return baseDir..filepath
    else
        return baseDir.."/"..filepath
    end
end

function mod.readGhost(baseDir)

    local filedlg = iup.filedlg{
      dialogtype = "OPEN",
      filter = "*.ghost",
      filterinfo = "Ghost files (*.ghost)",
      directory = baseDir
    }

    filedlg:popup(iup.CENTER, iup.CENTER)

    local status = tonumber(filedlg.status)
    local filepath
  
    if status ~= -1 then
        filepath = filedlg.value
    end
    
    filedlg:destroy()
    
    -- will be nil if user cancelled out
    return filepath
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
    local filepath
  
    if status ~= -1 then
        filepath = mod.fixup(filedlg.value)
    end
    
    filedlg:destroy()
    
    -- will be nil if user cancelled out
    return filepath
end

return mod
