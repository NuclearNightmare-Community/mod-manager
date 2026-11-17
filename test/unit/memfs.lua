-- An in-memory file system for the unit tests (files_test, state_test, main_test's io stubs): the injected fs of
-- inventory.lua plus files.lua's writeFile, rename and remove, with Windows' rename rule (the target must not exist)
-- and scripted failures: Z.fail[<op>] = <path pattern> makes that op fail once on a matching path (op: writeFile,
-- rename, remove, readFile); Z.corrupt = <path pattern> makes the next readFile of it return other bytes.
local F = {}

function F.new(files)
    local Z = { files = files or {}, log = {}, fail = {} }
    local function failing(op, path)
        local p = Z.fail[op]
        if p and tostring(path):find(p) then Z.fail[op] = nil return true end
        return false
    end
    function Z.exists(path) return Z.files[path] ~= nil end
    function Z.readFile(path, max)
        Z.log[#Z.log + 1] = "read " .. path
        if failing("readFile", path) then return nil, "Permission denied" end
        local t = Z.files[path]
        if t == nil then return nil, path .. ": No such file or directory" end
        if Z.corrupt and path:find(Z.corrupt) then Z.corrupt = nil return t .. "!" end
        if #t > max then return nil, string.format("%d bytes, at most %d", #t, max) end
        return t
    end
    function Z.writeFile(path, bytes)
        Z.log[#Z.log + 1] = "write " .. path
        if failing("writeFile", path) then return nil, "No space left on device" end
        Z.files[path] = bytes
        return true
    end
    function Z.rename(from, to)
        Z.log[#Z.log + 1] = "rename " .. from .. " -> " .. to
        if failing("rename", from) then return nil, "Permission denied" end
        if Z.files[from] == nil then return nil, from .. ": No such file or directory" end
        if Z.files[to] ~= nil then return nil, to .. ": File exists" end
        Z.files[to], Z.files[from] = Z.files[from], nil
        return true
    end
    function Z.remove(path)
        Z.log[#Z.log + 1] = "remove " .. path
        if failing("remove", path) then return nil, "Permission denied" end
        if Z.files[path] == nil then return nil, path .. ": No such file or directory" end
        Z.files[path] = nil
        return true
    end
    function Z.names()
        local t = {}
        for k in pairs(Z.files) do t[#t + 1] = k end
        table.sort(t)
        return table.concat(t, ",")
    end
    return Z
end

return F
