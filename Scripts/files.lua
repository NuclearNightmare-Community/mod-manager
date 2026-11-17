-- Mod Manager story 6: crash-safe writes over the injected file system (inventory.lua's fs, plus writeFile, rename and
-- remove). Pure apart from the fs it is given, so the unit tests drive every failure.
--
--   F.atomicWrite(fs, path, bytes) -> true | nil, err
--       <path>.mm-tmp is written, flushed and closed, read back and compared; <path> is renamed to <path>.mm-bak;
--       the tmp is renamed to <path>; the .mm-bak is removed. Any failure puts the previous file back (the .mm-bak
--       renamed back) and removes the tmp; nothing else is written. (Lua's os.rename fails on Windows when the target
--       exists: docs/mod-manager-research.md 8.3, hence the .mm-bak step.)
--   F.restore(fs, path) -> "restored" | nil        at start: <path> missing and <path>.mm-bak present -> renamed back
--   F.renameAside(fs, from, to) -> true | nil, err  to is removed first when it exists (a stale copy), then from -> to
--
-- Paths are the caller's: absolute, built only from the adapter's mods folder and validated folder names.
local F = {}

F.TMP, F.BAK = ".mm-tmp", ".mm-bak"

local function call(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil, tostring(a) end
    if a == nil or a == false then return nil, tostring(b or "failed") end
    return true
end

function F.atomicWrite(fs, path, bytes)
    if type(bytes) ~= "string" then return nil, "nothing to write" end
    local tmp, bak = path .. F.TMP, path .. F.BAK
    if fs.exists(tmp) then call(fs.remove, tmp) end
    local okW, errW = call(fs.writeFile, tmp, bytes)
    if not okW then call(fs.remove, tmp) return nil, "writing " .. F.base(tmp) .. ": " .. errW end
    local back, errR = fs.readFile(tmp, #bytes + 1)
    if back ~= bytes then
        call(fs.remove, tmp)
        return nil, "reading " .. F.base(tmp) .. " back: " .. (back and "it differs" or tostring(errR))
    end
    local had = fs.exists(path)
    if had then
        if fs.exists(bak) then
            local okS, errS = call(fs.remove, bak) -- a stale .mm-bak beside a live file (a crash after the second rename)
            if not okS then call(fs.remove, tmp) return nil, "removing a stale " .. F.base(bak) .. ": " .. errS end
        end
        local okB, errB = call(fs.rename, path, bak)
        if not okB then call(fs.remove, tmp) return nil, "renaming " .. F.base(path) .. " aside: " .. errB end
    end
    local okT, errT = call(fs.rename, tmp, path)
    if not okT then
        if had then call(fs.rename, bak, path) end
        call(fs.remove, tmp)
        return nil, "renaming " .. F.base(tmp) .. ": " .. errT
    end
    if had then call(fs.remove, bak) end -- the new file is in place; a .mm-bak left here is removed by the next write
    return true
end

function F.restore(fs, path)
    local bak = path .. F.BAK
    if not fs.exists(path) and fs.exists(bak) then
        if call(fs.rename, bak, path) then return "restored" end
    end
    return nil
end

function F.renameAside(fs, from, to)
    if fs.exists(to) then
        local okS, errS = call(fs.remove, to)
        if not okS then return nil, "removing a stale " .. F.base(to) .. ": " .. errS end
    end
    local ok, err = call(fs.rename, from, to)
    if not ok then return nil, "renaming " .. F.base(from) .. ": " .. err end
    return true
end

-- A path's last part, for messages (never the whole path: it can hold the Windows user name).
function F.base(path) return (tostring(path):match("([^\\/]+)$") or "?") end

return F
