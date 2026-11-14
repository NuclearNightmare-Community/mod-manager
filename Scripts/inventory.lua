-- Mod Manager story 3: what is installed, read-only. A pure scan-and-join over a file system it is given, so it runs
-- offline in the unit tests, plus a thin adapter over io and UE4SS's IterateGameDirectories for the game.
--
--   I.scan(fs, paths) -> { rows = { row, ... }, total = <rows before the cap>, warns = { { key, msg }, ... } }
--     fs:    { listDir(path) -> { dirs = { name, ... }, files = { name, ... } } | nil, err,
--              readFile(path, maxBytes) -> text | nil, err,  exists(path) -> boolean }
--     paths: { mods = <ue4ss/Mods>, paks = <Content/Paks>, logicMods = <Content/Paks/LogicMods> }
--   row:     { key, folder | nil, name, version | nil, pakOnly, state = "on" | "off" | "locked", settings, need | nil,
--              build | nil, paks = { file, ... } }
--   I.gameFs(modsDir) -> fs, paths | nil, err   the adapter (game thread; one IterateGameDirectories per call)
--
-- Nothing here writes anything, opens a shell, or builds a path from a name that hasn't passed NAME_RX. Each warning
-- has a key; the caller logs each key once per session.
local J = require("json")
-- Core's id normalizer (nucleus.modid, a pure module; the dependent bootstrap in main.lua puts core's Scripts/ on the
-- path). Distribution story 13 replaced the local copy.
local MID = require(("Nucleus"):lower() .. ".modid")

local I = {}

I.CORE_ID = "nuclearnightmare-community.nucleus"
I.CORE_FOLDER = "Nucleus"
I.SELF_FOLDER = "ModManager"
I.MAX_ROWS = 200
I.MAX_JSON = 65536
I.MAX_MODS_TXT = 262144
I.MAX_TEXT = 64          -- characters: a bound on untrusted input, not a display width
I.MAX_ENTRIES = 4096     -- folders or pak files looked at per directory
I.NAME_RX = "^[A-Za-z0-9_-]+$"
-- UE4SS's own mods (the pinned zip's Mods/ folders) and its shared Lua folder: never rows.
I.BUILTINS = { "BPML_GenericFunctions", "BPModLoaderMod", "CheatManagerEnablerMod", "ConsoleCommandsMod",
    "ConsoleEnablerMod", "Keybinds", "LineTraceMod", "SplitScreenMod", "shared" }
local BUILTIN = {}
for _, n in ipairs(I.BUILTINS) do BUILTIN[n:lower()] = true end
I.LOCKED = { [I.CORE_FOLDER:lower()] = true, [I.SELF_FOLDER:lower()] = true }

-- A name of 1-64 of A-Z a-z 0-9 _ - (folders, pak stems).
function I.validName(n) return type(n) == "string" and #n >= 1 and #n <= I.MAX_TEXT and n:match(I.NAME_RX) ~= nil end

-- A name for a warning key and message: the first 64 bytes, anything outside printable ASCII as "?".
local function shown(n) return (tostring(n):sub(1, 64):gsub("[^\32-\126]", "?")) end

-- A text a player sees (displayName's rule, mod-ids.md "Names"): a string of 1-64 characters (UTF-8), no control
-- characters, no leading or trailing space. Returns it, or nil and why.
function I.displayText(v)
    if type(v) ~= "string" then return nil, "not a string" end
    local n = utf8.len(v)
    if not n then return nil, "not UTF-8" end
    if n < 1 or n > I.MAX_TEXT then return nil, "not 1-64 characters" end
    if v:find("[%z\1-\31\127]") or v:find("\194[\128-\159]") then return nil, "has a control character" end -- C0, DEL, C1
    if v:find("^%s") or v:find("%s$") then return nil, "has a leading or trailing space" end
    return v
end

-- A value shown as data (version, need, build): a string (or an integer, for a build number), no control characters,
-- capped at 64 characters. nil when it's missing or wrong-typed.
function I.dataText(v)
    if math.type(v) == "integer" then v = tostring(v) end
    if type(v) ~= "string" or v == "" then return nil end
    if v:find("[%z\1-\31\127]") then return nil end
    local n = utf8.len(v)
    if not n or v:find("\194[\128-\159]") then return nil end -- not UTF-8, or a C1 control character
    if n > I.MAX_TEXT then v = v:sub(1, utf8.offset(v, I.MAX_TEXT + 1) - 1) end
    return v
end

-- The normalized id (mod-ids.md "Normalizer"), or nil.
local function coreIdOf(id)
    return (MID.normalize(id))
end

-- mods.txt, the way UE4SS reads it (docs/mod-manager-research.md 3.1): a line with ';' anywhere is skipped, so is a
-- line of 4 characters or fewer; spaces are removed and the line split at ':'; on when the value starts with '1'.
-- Returns the set of names with an "on" line.
function I.parseModsTxt(text)
    local on = {}
    if type(text) ~= "string" then return on end
    if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        if not line:find(";", 1, true) and #line > 4 then
            line = line:gsub(" ", "")
            local name = line:match("^([^:]*)")
            local value = line:match(":([^:]*)$")
            if name and value and value:sub(1, 1) == "1" then on[name] = true end
        end
    end
    return on
end

local function join(a, b) return a .. "\\" .. b end

-- Reads Mods/<folder>/mod.json. Returns the row's fields from it, plus warnings.
local function readManifest(fs, modsDir, folder, warn)
    local out = {}
    local path = join(join(modsDir, folder), "mod.json")
    if not fs.exists(path) then return out end
    local text, err = fs.readFile(path, I.MAX_JSON)
    if not text then
        warn("json:" .. folder, string.format("%s/mod.json could not be read (%s); its values show as -", folder, shown(err)))
        return out
    end
    local m, objects = J.decode(text)
    if m == nil then
        warn("json:" .. folder, string.format("%s/mod.json is not valid JSON (%s); its values show as -", folder, shown(objects)))
        return out
    end
    if not J.isObject(objects, m) then
        warn("json:" .. folder, string.format("%s/mod.json is not a JSON object; its values show as -", folder))
        return out
    end
    local wrong = {}
    -- Name: displayName, else name, else the folder.
    if m.displayName ~= nil then
        local d, why = I.displayText(m.displayName)
        if d then out.name = d else warn("displayName:" .. folder, string.format("%s/mod.json displayName is ignored (%s)", folder, why)) end
    end
    if m.name ~= nil then
        local n = I.displayText(m.name)
        if n then out.fallbackName = n else wrong[#wrong + 1] = "name" end
    end
    if m.version ~= nil then
        out.version = type(m.version) == "string" and I.dataText(m.version) or nil
        if not out.version then wrong[#wrong + 1] = "version" end
    end
    if m.game ~= nil then
        if J.isObject(objects, m.game) then
            local parts = {}
            local gv, gb = I.dataText(m.game.version), I.dataText(m.game.build)
            if m.game.version ~= nil and not gv then wrong[#wrong + 1] = "game.version" end
            if m.game.build ~= nil and not gb then wrong[#wrong + 1] = "game.build" end
            parts[#parts + 1] = gv
            parts[#parts + 1] = gb
            if #parts > 0 then out.build = I.dataText(table.concat(parts, " ")) end
        else
            wrong[#wrong + 1] = "game"
        end
    end
    if m.dependsOn ~= nil then
        if type(m.dependsOn) == "table" and not J.isObject(objects, m.dependsOn) then
            for _, d in ipairs(m.dependsOn) do
                if J.isObject(objects, d) and coreIdOf(d.id) == I.CORE_ID then
                    out.need = type(d.version) == "string" and I.dataText(d.version) or nil
                    if not out.need then wrong[#wrong + 1] = "dependsOn version" end
                    break
                end
            end
        else
            wrong[#wrong + 1] = "dependsOn"
        end
    end
    if m.settings ~= nil then
        if J.isObject(objects, m.settings) then out.settings = #objects[m.settings] > 0
        else wrong[#wrong + 1] = "settings" end
    end
    if #wrong > 0 then
        warn("json:" .. folder, string.format("%s/mod.json has wrong-typed values (%s); they show as -", folder, table.concat(wrong, ", ")))
    end
    return out
end

local function listOf(fs, path, what, warn)
    if not path then return { dirs = {}, files = {} } end
    local l, err = fs.listDir(path)
    if type(l) ~= "table" then
        warn("list:" .. what, string.format("the %s folder could not be listed (%s)", what, shown(err)))
        return { dirs = {}, files = {} }
    end
    return { dirs = l.dirs or {}, files = l.files or {} }
end

-- Splits a pak file name into its stem and whether it is enabled: "X.pak" -> "X", true; "X.pak.disabled" -> "X",
-- false; anything else -> nil.
local function pakParts(f)
    local lower = f:lower()
    if lower:sub(-4) == ".pak" then return f:sub(1, -5), true end
    if lower:sub(-13) == ".pak.disabled" then return f:sub(1, -14), false end
    return nil
end
local function ignoredBasePak(lower)
    return lower:sub(1, #"nuclearnightmare-windows.") == "nuclearnightmare-windows." or lower:sub(1, 8) == "pakchunk"
end

local function capped(list, what, warn)
    if #list > I.MAX_ENTRIES then
        warn("entries:" .. what, string.format("the %s folder has %d entries; only the first %d are looked at", what, #list, I.MAX_ENTRIES))
        local out = {}
        for i = 1, I.MAX_ENTRIES do out[i] = list[i] end
        return out
    end
    return list
end

function I.scan(fs, paths)
    local warns, warned = {}, {}
    local function warn(key, msg)
        if warned[key] then return end
        warned[key] = true
        warns[#warns + 1] = { key = key, msg = msg }
    end
    local modsDir = paths.mods
    local rows, byKey = {}, {}

    -- mods.txt: which names have an "on" line.
    local onLines = {}
    if modsDir and fs.exists(join(modsDir, "mods.txt")) then
        local text, err = fs.readFile(join(modsDir, "mods.txt"), I.MAX_MODS_TXT)
        if text then onLines = I.parseModsTxt(text)
        else warn("modstxt", string.format("mods.txt could not be read (%s); mods without enabled.txt show as off", shown(err))) end
    end

    -- Folders.
    local dirs = capped(listOf(fs, modsDir, "Mods", warn).dirs, "Mods", warn)
    table.sort(dirs)
    for _, folder in ipairs(dirs) do
        local lower = type(folder) == "string" and folder:lower() or nil
        if not I.validName(folder) then
            warn("name:" .. shown(folder), string.format("folder '%s' is not a mod name (1-64 of A-Z a-z 0-9 _ -); not listed", shown(folder)))
        elseif not BUILTIN[lower] and not byKey[lower] then
            local m = readManifest(fs, modsDir, folder, warn)
            local state
            if I.LOCKED[lower] then state = "locked"
            elseif fs.exists(join(join(modsDir, folder), "enabled.txt")) or onLines[folder] then state = "on"
            else state = "off" end
            local row = { key = lower, folder = folder, name = m.name or m.fallbackName or folder, version = m.version,
                pakOnly = false, state = state, settings = m.settings == true, need = m.need, build = m.build, paks = {} }
            rows[#rows + 1] = row
            byKey[lower] = row
        end
    end

    -- Paks: <F>_P.pak[.disabled] in Paks and <F>.pak[.disabled] in LogicMods (and in its subfolders, which
    -- BPModLoaderMod loads too) join the row of folder <F>; a pak with no folder is a pak-only row, named after its file
    -- (without _P), on when any of its paks is enabled. A pak named like a UE4SS built-in or shared is never a row.
    local function addPaks(listed, what, base)
        local files = capped(listed, what, warn)
        table.sort(files)
        for _, f in ipairs(files) do
            if type(f) == "string" then
                local stem, enabled = pakParts(f)
                if stem and not (base and ignoredBasePak(f:lower())) then
                    if base then stem = stem:gsub("_[Pp]$", "") end -- any case, as the engine reads _P.pak
                    if not I.validName(stem) then
                        warn("name:" .. shown(f), string.format("pak '%s' is not a mod name (1-64 of A-Z a-z 0-9 _ -); not listed", shown(f)))
                    elseif not BUILTIN[stem:lower()] then
                        local key = stem:lower()
                        local row = byKey[key]
                        if not row then
                            row = { key = key, folder = nil, name = stem, version = nil, pakOnly = true, state = "off",
                                settings = false, paks = {} }
                            rows[#rows + 1] = row
                            byKey[key] = row
                        end
                        row.paks[#row.paks + 1] = f
                        if row.pakOnly and enabled then row.state = "on" end
                    end
                end
            end
        end
    end
    addPaks(listOf(fs, paths.paks, "Paks", warn).files, "Paks", true)
    local lm = listOf(fs, paths.logicMods, "LogicMods", warn)
    addPaks(lm.files, "LogicMods", false)
    local subs = capped(lm.dirs, "LogicMods folders", warn)
    table.sort(subs)
    for _, d in ipairs(subs) do
        if not I.validName(d) then
            warn("name:" .. shown(d), string.format("LogicMods folder '%s' is not a mod name (1-64 of A-Z a-z 0-9 _ -); its paks are not listed", shown(d)))
        else
            addPaks(listOf(fs, join(paths.logicMods, d), "LogicMods/" .. d, warn).files, "LogicMods/" .. d, false)
        end
    end

    -- Order: Nucleus, then the Mod Manager, then the rest by shown name, ignoring case.
    local function rank(r)
        if r.folder and r.key == I.CORE_FOLDER:lower() then return 0 end
        if r.folder and r.key == I.SELF_FOLDER:lower() then return 1 end
        return 2
    end
    table.sort(rows, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        local na, nb = a.name:lower(), b.name:lower()
        if na ~= nb then return na < nb end
        return a.key < b.key
    end)

    local total = #rows
    if total > I.MAX_ROWS then
        for i = total, I.MAX_ROWS + 1, -1 do rows[i] = nil end
        warn("cap", string.format("%d mods are installed; the list shows the first %d", total, I.MAX_ROWS))
    end
    return { rows = rows, total = total, warns = warns }
end

-- ---------------------------------------------------------------- the adapter (game thread)

local function norm(p) return (p:gsub("/", "\\"):gsub("\\+$", ""):lower()) end

-- A file system over io (read-only) and one IterateGameDirectories() tree. modsDir is ue4ss/Mods from the script's
-- own path. Returns fs, paths, or nil and why.
function I.gameFs(modsDir)
    local okD, dirs = pcall(IterateGameDirectories)
    if not okD or type(dirs) ~= "table" then return nil, "IterateGameDirectories failed: " .. tostring(dirs) end
    local game = dirs.Game
    if type(game) ~= "table" then return nil, "IterateGameDirectories has no Game folder" end
    local function abs(node) local ok, p = pcall(function() return node.__absolute_path end) return ok and type(p) == "string" and p or nil end
    local gameAbs = abs(game)
    if not gameAbs then return nil, "the Game folder has no path" end
    local paksNode = type(game.Content) == "table" and game.Content.Paks or nil
    local paks = type(paksNode) == "table" and abs(paksNode) or nil
    local lmNode = type(paksNode) == "table" and paksNode.LogicMods or nil
    local logicMods = type(lmNode) == "table" and abs(lmNode) or nil

    local function child(node, name)
        local c = node[name]
        if type(c) == "table" then return c end
        local ln = name:lower()
        for k, v in pairs(node) do
            if type(k) == "string" and type(v) == "table" and k:lower() == ln then return v end
        end
        return nil
    end
    -- The tree node for an absolute path under the Game folder, or nil.
    local function nodeOf(path)
        local p, g = norm(path), norm(gameAbs)
        if p == g then return game end
        if p:sub(1, #g + 1) ~= g .. "\\" then return nil end
        local node = game
        for part in p:sub(#g + 2):gmatch("[^\\]+") do
            node = child(node, part)
            if not node then return nil end
        end
        return node
    end

    -- The script's own path names the Mods folder; if it isn't under the Game folder as the tree spells it (a relative
    -- or differently written path), use the tree's ue4ss/Mods instead.
    -- Either way the tree's own spelling of the path is used from here on.
    local modsNode = type(modsDir) == "string" and nodeOf(modsDir) or nil
    if not modsNode then
        modsNode = game
        for _, part in ipairs({ "Binaries", "Win64", "ue4ss", "Mods" }) do modsNode = modsNode and child(modsNode, part) or nil end
    end
    modsDir = modsNode and abs(modsNode) or modsDir

    local fs = {}
    function fs.listDir(path)
        local node = nodeOf(path)
        if not node then return nil, "not found under the game folder" end
        local ok, res = pcall(function()
            local out = { dirs = {}, files = {} }
            for k, v in pairs(node) do
                if type(k) == "string" and type(v) == "table" then
                    out.dirs[#out.dirs + 1] = k
                    if #out.dirs > I.MAX_ENTRIES then break end
                end
            end
            local files = node.__files
            if type(files) == "table" then
                for _, f in pairs(files) do
                    local n = type(f) == "table" and f.__name or nil
                    if type(n) == "string" then out.files[#out.files + 1] = n end
                    if #out.files > I.MAX_ENTRIES then break end
                end
            end
            return out
        end)
        if ok then return res end
        return nil, tostring(res)
    end
    function fs.readFile(path, maxBytes)
        local f, err = io.open(path, "rb")
        if not f then return nil, err end
        local ok, res, why = pcall(function()
            local size = f:seek("end")
            if not size then return nil, "size unknown" end
            if size > maxBytes then return nil, string.format("%d bytes, at most %d", size, maxBytes) end
            f:seek("set", 0)
            return f:read(size) or ""
        end)
        f:close()
        if not ok then return nil, tostring(res) end
        return res, why
    end
    function fs.exists(path)
        local f = io.open(path, "rb")
        if f then f:close() return true end
        return false
    end
    return fs, { mods = modsDir, paks = paks, logicMods = logicMods }
end

return I
