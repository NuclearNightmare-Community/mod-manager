-- Unit tests for Scripts/inventory.lua: every row of story 3's I/O matrix against a fake file system, mods.txt the way
-- UE4SS reads it, the join of folders and paks, the order, the 200 cap, the warnings, and the game adapter over a stubbed
-- IterateGameDirectories and io (read-only). Run from the repo root:  texlua test/unit/inventory_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
package.path = ROOT .. "/Scripts/?.lua;" .. package.path
dofile(ROOT .. "/test/unit/nucleus_pkg.lua")(ROOT) -- nucleus.modid from the Nucleus repo
local I = require("inventory")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. tostring(got) .. ", want " .. tostring(want)) end

-- ---------------------------------------------------------------- a fake file system
local MODS, PAKS, LM = "G\\Mods", "G\\Paks", "G\\Paks\\LogicMods"
local PATHS = { mods = MODS, paks = PAKS, logicMods = LM }
local function newFs()
    local F = { files = {}, dirs = { [MODS] = true, [PAKS] = true, [LM] = true }, reads = {}, calls = 0 }
    function F.listDir(path)
        F.calls = F.calls + 1
        if not F.dirs[path] then return nil, "no such folder" end
        local out = { dirs = {}, files = {} }
        for p in pairs(F.dirs) do
            local parent, name = p:match("^(.*)\\([^\\]+)$")
            if parent == path then out.dirs[#out.dirs + 1] = name end
        end
        for p in pairs(F.files) do
            local parent, name = p:match("^(.*)\\([^\\]+)$")
            if parent == path then out.files[#out.files + 1] = name end
        end
        return out
    end
    function F.readFile(path, max)
        F.reads[#F.reads + 1] = path
        local t = F.files[path]
        if t == nil then return nil, "cannot open" end
        if t == false then return nil, "Permission denied" end
        if #t > max then return nil, string.format("%d bytes, at most %d", #t, max) end
        return t
    end
    function F.exists(path) return F.files[path] ~= nil end
    function F.folder(name, manifest, extra)
        F.dirs[MODS .. "\\" .. name] = true
        if manifest then F.files[MODS .. "\\" .. name .. "\\mod.json"] = manifest end
        for k, v in pairs(extra or {}) do F.files[MODS .. "\\" .. name .. "\\" .. k] = v end
    end
    function F.pak(name) F.files[PAKS .. "\\" .. name] = "pak" end
    function F.lm(name) F.files[LM .. "\\" .. name] = "pak" end
    function F.modsTxt(text) F.files[MODS .. "\\mods.txt"] = text end
    return F
end
local function manifest(t)
    -- A tiny JSON writer for the fixtures (strings, numbers, booleans, arrays, objects with keys in sorted order).
    local function enc(v)
        if type(v) == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
        if type(v) ~= "table" then return tostring(v) end
        if v[1] ~= nil or next(v) == nil and getmetatable(v) == "array" then
            local p = {} for i, x in ipairs(v) do p[i] = enc(x) end return "[" .. table.concat(p, ",") .. "]"
        end
        local keys = {} for k in pairs(v) do keys[#keys + 1] = k end table.sort(keys)
        local p = {} for i, k in ipairs(keys) do p[i] = enc(k) .. ":" .. enc(v[k]) end return "{" .. table.concat(p, ",") .. "}"
    end
    return enc(t)
end
local function rowOf(res, key) for i, r in ipairs(res.rows) do if r.key == key:lower() then return r, i end end end
local function warnsLike(res, pat) local n = 0 for _, w in ipairs(res.warns) do if w.msg:find(pat) then n = n + 1 end end return n end
local function names(res) local t = {} for i, r in ipairs(res.rows) do t[i] = r.name end return table.concat(t, ",") end

local STOCK_TXT = "; comment\r\nCheatManagerEnablerMod : 1\r\nBPModLoaderMod : 1\r\nKeybinds : 1\r\n"
local function stockFs()
    local F = newFs()
    for _, b in ipairs(I.BUILTINS) do F.folder(b, nil, { ["enabled.txt"] = "" }) end
    F.pak("NuclearNightmare-Windows.pak"); F.pak("NuclearNightmare-Windows.utoc"); F.pak("NuclearNightmare-Windows.ucas")
    F.pak("pakchunk1-Windows.pak"); F.pak("global.utoc"); F.pak("NuclearNightmare-Windows.sig")
    F.modsTxt(STOCK_TXT)
    return F
end

-- ---------------------------------------------------------------- the matrix
do -- Managed mod: Nucleus, a fixture off, the Mod Manager, displayName, Long, Bare, enabled.txt, pak-only, built-ins.
    local F = stockFs()
    F.folder("Nucleus", manifest{ id = "nuclearnightmare-community.nucleus", name = "Nucleus", version = "0.8.0", game = { version = "V8.2.3", build = "26601774" }, dependsOn = setmetatable({}, { __metatable = "array" }) })
    F.lm("Nucleus.pak")
    F.folder("ModManager", manifest{ id = "nuclearnightmare-community.mod-manager", name = "ModManager", displayName = "Mod Manager", version = "0.1.0",
        game = { version = "V8.2.3", build = "26601774" }, dependsOn = { { id = "nuclearnightmare-community.nucleus", version = ">=0.8.0" } } })
    F.folder("ModManagerFixture", manifest{ name = "ModManagerFixture", version = "9.9.9", game = { version = "V0.0.0", build = "1" },
        dependsOn = { { id = "nuclearnightmare-community.nucleus", version = ">=0.1.0" } }, settings = { example = { type = "int", default = 1 } } })
    local long = "ModManagerLong " .. string.rep("W", 49)
    F.folder("ModManagerLong", manifest{ name = "ModManagerLong", displayName = long, version = "1.0.0", dependsOn = { { id = "nuclearnightmare-community.nucleus", version = ">=0.2.0" } } })
    F.folder("ModManagerBare")
    F.dirs[MODS .. "\\ModManagerBare\\Scripts"] = true
    F.folder("ModManagerDriver", nil, { ["Scripts\\main.lua"] = "-- driver" })
    F.folder("Enabled", manifest{ version = "2.0.0" }, { ["enabled.txt"] = "" })
    F.pak("ModManagerPak_P.pak"); F.pak("ModManagerPakOff_P.pak.disabled")
    F.modsTxt("Nucleus : 1\r\nModManagerDriver : 1\r\nModManager : 1\r\nModManagerFixture : 0\r\nEnabled : 0\r\n" .. STOCK_TXT)
    local res = I.scan(F, PATHS)
    eq(names(res), "Nucleus,Mod Manager,Enabled,ModManagerBare,ModManagerDriver,ModManagerFixture," .. long .. ",ModManagerPak,ModManagerPakOff",
        "rows: Nucleus, Mod Manager, then by shown name; no built-in, shared or base pak")
    eq(res.total, 9, "total")
    eq(#res.warns, 0, "no warnings", res.warns[1] and res.warns[1].msg)
    local n = rowOf(res, "Nucleus")
    ok(n.state == "locked" and n.version == "0.8.0" and n.settings == false and n.need == nil and n.build == "V8.2.3 26601774" and not n.pakOnly,
        "Nucleus: lock, 0.8.0, no settings, need -, its game build")
    eq(table.concat(n.paks, ","), "Nucleus.pak", "Nucleus: LogicMods/Nucleus.pak joins its row (no extra pak row)")
    local mm, i = rowOf(res, "ModManager")
    ok(mm.state == "locked" and mm.name == "Mod Manager" and i == 2 and mm.need == ">=0.8.0", "ModManager: 'Mod Manager', second, lock")
    local fx = rowOf(res, "ModManagerFixture")
    ok(fx.state == "off" and fx.version == "9.9.9" and fx.settings == true and fx.need == ">=0.1.0" and fx.build == "V0.0.0 1",
        "Fixture: off, 9.9.9, settings, NUCLEUS >=0.1.0, GAME BUILD V0.0.0 1")
    local lg = rowOf(res, "ModManagerLong")
    ok(lg.name == long and #lg.name == 64 and lg.need == ">=0.2.0", "Long: the 64-character name in full, its need")
    local bare = rowOf(res, "ModManagerBare")
    ok(bare.state == "off" and bare.version == nil and bare.settings == false and bare.need == nil and bare.build == nil, "Bare: off, all -")
    local drv = rowOf(res, "ModManagerDriver")
    ok(drv.state == "on" and drv.version == nil, "Driver: no mod.json, on from mods.txt")
    eq(rowOf(res, "Enabled").state, "on", "enabled.txt with ': 0': on")
    local pk, pkOff = rowOf(res, "ModManagerPak"), rowOf(res, "ModManagerPakOff")
    ok(pk.pakOnly and pk.state == "on" and pk.folder == nil and pk.settings == false and pk.version == nil, "pak-only on: UNMANAGED row, on, gear dimmed")
    ok(pkOff.pakOnly and pkOff.state == "off", "pak-only .disabled: off")
    ok(not rowOf(res, "shared") and not rowOf(res, "Keybinds") and not rowOf(res, "NuclearNightmare-Windows") and not rowOf(res, "pakchunk1-Windows") and not rowOf(res, "global"),
        "built-ins, shared, the base pak, pakchunk, .utoc/.ucas: absent")
    -- Read-only: only reads, through the fs it is given.
    for _, p in ipairs(F.reads) do ok(p:match("mod%.json$") or p:match("mods%.txt$"), "reads only mod.json and mods.txt: " .. p) end
end

do -- Pak joins: a folder plus both paks, case-insensitive; a pak-only row on when any pak is enabled.
    local F = stockFs()
    F.folder("Both", manifest{ version = "1.0.0" })
    F.pak("Both_P.pak"); F.lm("both.pak.disabled")
    F.pak("Split_P.pak.disabled"); F.lm("Split.pak")
    F.lm("Logic.pak.disabled")
    F.pak("NoSuffix.pak")
    F.folder("Lower", '{"version":"1.0.0"}'); F.pak("Lower_p.pak")
    F.lm("Weird_P.pak")
    local res = I.scan(F, PATHS)
    eq(#rowOf(res, "Both").paks, 2, "a folder's _P.pak and LogicMods pak join it (any case)")
    ok(not rowOf(res, "Both").pakOnly and rowOf(res, "Both").state == "off", "a folder row's state comes from mods.txt, not its paks")
    ok(rowOf(res, "Split").pakOnly and rowOf(res, "Split").state == "on" and #rowOf(res, "Split").paks == 2, "pak-only: one row for both paks, on when one is .pak")
    eq(rowOf(res, "Logic").state, "off", "a LogicMods .pak.disabled alone: off")
    ok(rowOf(res, "NoSuffix") ~= nil, "a base pak without _P: named after its file")
    ok(rowOf(res, "Lower_p") == nil and table.concat(rowOf(res, "Lower").paks, ",") == "Lower_p.pak", "a base pak's _p (any case) joins its folder")
    ok(rowOf(res, "Weird_P") ~= nil, "LogicMods keeps _P in the name (only Paks drops it)")
end

do -- LogicMods subfolders (BPModLoaderMod loads their paks too); built-in and shared stems are never rows.
    local F = stockFs()
    F.folder("Joined", manifest{ version = "1.0.0" })
    F.dirs[LM .. "\\Sub"] = true
    F.files[LM .. "\\Sub\\Deep.pak"] = "pak"
    F.files[LM .. "\\Sub\\Joined.pak.disabled"] = "pak"
    F.files[LM .. "\\Sub\\notes.txt"] = "x"
    F.dirs[LM .. "\\bad dir"] = true
    F.files[LM .. "\\bad dir\\Hidden.pak"] = "pak"
    F.pak("Keybinds_P.pak"); F.lm("BPModLoaderMod.pak"); F.lm("shared.pak"); F.pak("BPML_GenericFunctions_P.pak.disabled")
    local res = I.scan(F, PATHS)
    local deep = rowOf(res, "Deep")
    ok(deep and deep.pakOnly and deep.state == "on", "a pak in a LogicMods subfolder is a row (on)")
    eq(table.concat(rowOf(res, "Joined").paks, ","), "Joined.pak.disabled", "a subfolder pak joins its folder's row")
    ok(rowOf(res, "Hidden") == nil and warnsLike(res, "^LogicMods folder 'bad dir' is not a mod name") == 1, "a subfolder that isn't a mod name: skipped, one WARN")
    ok(rowOf(res, "Keybinds") == nil and rowOf(res, "BPModLoaderMod") == nil and rowOf(res, "shared") == nil and rowOf(res, "BPML_GenericFunctions") == nil,
        "paks named like a built-in or shared: no row")
    eq(names(res), "Deep,Joined", "only Deep and Joined")
end

do -- displayName: a bad one is ignored with one WARN per folder, then name, then the folder name.
    local cases = {
        { 5, "a number" }, { string.rep("x", 65), "65 characters" }, { " Lead", "a leading space" }, { "Trail ", "a trailing space" },
        { "a\nb", "a newline" }, { "a\tb", "a tab" }, { "a\7b", "U+0007" }, { "a\194\133b", "U+0085 (C1)" }, { "\194\159", "U+009F (C1)" }, { "", "empty" },
    }
    for _, c in ipairs(cases) do
        local F = stockFs()
        F.folder("WithName", manifest{ displayName = c[1], name = "TheName", version = "1.0.0" })
        F.folder("NoName", manifest{ displayName = c[1], version = "1.0.0" })
        local res = I.scan(F, PATHS)
        eq(rowOf(res, "WithName").name, "TheName", "bad displayName (" .. c[2] .. "): name shown")
        eq(rowOf(res, "NoName").name, "NoName", "bad displayName (" .. c[2] .. "): else the folder name")
        eq(warnsLike(res, "displayName is ignored"), 2, "bad displayName (" .. c[2] .. "): one WARN per folder")
        eq(rowOf(res, "WithName").version, "1.0.0", "bad displayName (" .. c[2] .. "): the rest still read")
    end
    local F = stockFs()
    F.folder("Uni", manifest{ displayName = "Caf\195\169 " .. string.rep("\228\184\173", 59) })
    eq(rowOf(I.scan(F, PATHS), "Uni").name, "Caf\195\169 " .. string.rep("\228\184\173", 59), "a 64-character UTF-8 displayName (more bytes) is fine")
end

do -- Nucleus id forms in dependsOn.
    local forms = {
        { "github.com/NuclearNightmare-Community.nucleus", ">=0.3.0" }, { "NuclearNightmare-Community.Nucleus", ">=0.3.0" },
        { "nucleus", nil }, { "Nucleus", nil }, -- the bare id is no longer core (distribution story 13)
        { "www.github.com/NuclearNightmare-Community.nucleus", nil }, { "other.nucleus", nil }, { 7, nil },
    }
    for _, f in ipairs(forms) do
        local F = stockFs()
        F.folder("Dep", manifest{ version = "1.0.0", dependsOn = { { id = "someone.else", version = ">=9.0.0" }, { id = f[1], version = ">=0.3.0" } } })
        local res = I.scan(F, PATHS)
        eq(rowOf(res, "Dep").need, f[2], "dependsOn id " .. tostring(f[1]))
    end
    local F = stockFs()
    F.folder("Dep", manifest{ dependsOn = { { id = "nuclearnightmare-community.nucleus", version = 3 } } })
    local res = I.scan(F, PATHS)
    ok(rowOf(res, "Dep").need == nil and warnsLike(res, "wrong%-typed values %(dependsOn version%)") == 1, "a wrong-typed need: - and one WARN")
end

do -- Bad mod.json: too big, invalid, a non-object, wrong field types; one WARN per folder per scan.
    local F = stockFs()
    F.folder("Big", '{"version":"1.0.0","pad":"' .. string.rep("x", 1000) .. '"}' .. string.rep(" ", 65536))
    F.folder("Invalid", '{"version": "1.0.0",}')
    F.folder("Array", '["version"]')
    F.folder("Types", manifest{ name = 5, version = 2, game = "V8", dependsOn = { id = "nuclearnightmare-community.nucleus" }, settings = { 1, 2 } })
    F.folder("Locked", nil); F.files[MODS .. "\\Locked\\mod.json"] = false
    local res = I.scan(F, PATHS)
    for _, k in ipairs({ "Big", "Invalid", "Array", "Types", "Locked" }) do
        local r = rowOf(res, k)
        ok(r and r.name == k and r.version == nil and r.settings == false and r.need == nil and r.build == nil, "bad mod.json " .. k .. ": folder name, all -")
    end
    eq(warnsLike(res, "^Big/mod%.json could not be read"), 1, "too big: one WARN")
    eq(warnsLike(res, "^Invalid/mod%.json is not valid JSON %(1:21 trailing comma%)"), 1, "invalid: one WARN with the position")
    eq(warnsLike(res, "^Array/mod%.json is not a JSON object"), 1, "a non-object: one WARN")
    eq(warnsLike(res, "^Types/mod%.json has wrong%-typed values %(name, version, game, dependsOn, settings%)"), 1, "wrong types: one WARN naming them")
    eq(warnsLike(res, "^Locked/mod%.json could not be read %(Permission denied%)"), 1, "unreadable: one WARN")
    eq(#res.warns, 5, "five folders, five WARNs")
    local again = I.scan(F, PATHS)
    eq(#again.warns, 5, "a rescan reports the same keys again (main.lua logs each key once per session)")
    ok(again.warns[1].key == res.warns[1].key, "warning keys are stable across scans")
    -- an empty settings object: dimmed; a version over 64 characters: cut to 64; a control character: -
    F = stockFs()
    F.folder("Empty", manifest{ settings = {}, version = string.rep("1", 70) })
    F.folder("Ctl", manifest{ version = "1.0\n.0" })
    res = I.scan(F, PATHS)
    ok(rowOf(res, "Empty").settings == false and #rowOf(res, "Empty").version == 64, "an empty settings object: no settings; a 70-character version: 64")
    eq(rowOf(res, "Ctl").version, nil, "a version with a control character: -")
end

do -- Bad names: folders and paks that aren't mod names are absent, one WARN per name.
    local F = stockFs()
    F.folder("bad name!"); F.folder(string.rep("a", 65)); F.folder("Good")
    F.pak("x y_P.pak"); F.lm("bad.name.pak"); F.pak(string.rep("b", 65) .. "_P.pak")
    local res = I.scan(F, PATHS)
    eq(names(res), "Good", "only the good name is a row")
    eq(warnsLike(res, "is not a mod name"), 5, "one WARN per bad name")
    ok(warnsLike(res, "^folder 'bad name!'") == 1 and warnsLike(res, "^pak 'x y_P%.pak'") == 1, "the WARN names it")
    F.folder("bad\1\2")
    res = I.scan(F, PATHS)
    eq(warnsLike(res, "folder 'bad%?%?'"), 1, "a control character in a name is shown as ?")
end

do -- Many mods: 250 folders give 200 rows and one WARN.
    local F = stockFs()
    for i = 1, 250 do F.folder(string.format("Mod%03d", i)) end
    F.folder("Nucleus"); F.folder("ModManager")
    local res = I.scan(F, PATHS)
    eq(#res.rows, 200, "200 rows")
    eq(res.total, 252, "total counts every mod")
    eq(warnsLike(res, "252 mods are installed; the list shows the first 200"), 1, "one WARN")
    ok(res.rows[1].key == "nucleus" and res.rows[2].key == "modmanager" and res.rows[3].name == "Mod001" and res.rows[200].name == "Mod198", "the first 200 in order")
end

do -- Order: case-insensitive by shown name; ties by key.
    local F = stockFs()
    F.folder("b", manifest{ displayName = "alpha" }); F.folder("A", manifest{ displayName = "Beta" }); F.folder("c", manifest{ displayName = "ALPHA" })
    F.folder("ModManager"); F.folder("Nucleus")
    eq(names(I.scan(F, PATHS)), "Nucleus,ModManager,alpha,ALPHA,Beta", "Nucleus, ModManager (no displayName), then case-insensitive")
end

do -- No folders at all, missing paths, unlistable folders.
    local F = newFs()
    local res = I.scan(F, { mods = MODS })
    eq(#res.rows, 0, "an empty install: no rows")
    res = I.scan(F, { mods = "G\\Nope", paks = PAKS })
    ok(#res.rows == 0 and warnsLike(res, "Mods folder could not be listed") == 1, "a Mods folder that can't be listed: one WARN, no rows")
end

-- ---------------------------------------------------------------- mods.txt, the way UE4SS reads it
do
    local on = I.parseModsTxt("\239\187\191A : 1\r\nBbb:1\nC : 0\nD : 1 ; comment\n; E : 1\nF:1\nG : 10\nH :1x\n I  :  1 \nJ : 0\nJ : 1\nK\nL : 1 : 0\n")
    ok(on.A and on.Bbb, "on lines, with and without spaces, BOM skipped")
    ok(not on.C, "': 0' is off")
    ok(not on.D, "a ';' anywhere skips the line")
    ok(not on.F, "a line of 4 characters or fewer is skipped ('F:1')")
    ok(on.G and on.H, "a value that starts with 1 is on")
    ok(on.I, "spaces removed before matching")
    ok(on.J, "a later on line counts")
    ok(not on.K, "no ':' is no line")
    ok(not on.L, "the value is after the last ':'")
    ok(next(I.parseModsTxt(nil)) == nil and next(I.parseModsTxt("")) == nil, "nothing: no on lines")
    local F = stockFs()
    F.folder("Odd")
    F.files[MODS .. "\\mods.txt"] = false
    local res = I.scan(F, PATHS)
    ok(rowOf(res, "Odd").state == "off" and warnsLike(res, "^mods%.txt could not be read") == 1, "unreadable mods.txt: off, one WARN")
    F.files[MODS .. "\\mods.txt"] = string.rep("x", I.MAX_MODS_TXT + 1)
    res = I.scan(F, PATHS)
    eq(warnsLike(res, "^mods%.txt could not be read %(262145 bytes"), 1, "a huge mods.txt is not read")
end

-- ---------------------------------------------------------------- the text rules
do
    eq(I.displayText("Mod Manager"), "Mod Manager", "displayText: a plain name")
    eq((I.displayText("\255")), nil, "displayText: invalid UTF-8")
    eq(I.dataText(26601774), "26601774", "dataText: an integer build")
    eq(I.dataText(1.5), nil, "dataText: a float is wrong-typed")
    eq(I.dataText(""), nil, "dataText: empty")
    eq(I.dataText("1.0\194\133"), nil, "dataText: a C1 control character")
    eq(I.dataText("1.0\194\160"), "1.0\194\160", "dataText: U+00A0 is not a control character")
    eq(I.dataText(string.rep("\228\184\173", 70)), string.rep("\228\184\173", 64), "dataText: 64 characters, not bytes")
    ok(I.validName("A-b_9") and not I.validName("a.b") and not I.validName("") and not I.validName(string.rep("a", 65)) and I.validName(string.rep("a", 64)), "validName")
end

-- ---------------------------------------------------------------- the game adapter (IterateGameDirectories + io)
do
    local function dir(abs, children, files)
        local t = {}
        for k, v in pairs(children or {}) do t[k] = v end
        local f = {}
        for i, n in ipairs(files or {}) do f[i] = { __name = n, __absolute_path = abs .. "\\" .. n } end
        return setmetatable(t, { __index = function(_, k)
            if k == "__absolute_path" then return abs end
            if k == "__name" then return abs:match("[^\\]+$") end
            if k == "__files" then return f end
        end })
    end
    local R = "C:\\nn\\copy\\NuclearNightmare"
    local mods = dir(R .. "\\Binaries\\Win64\\ue4ss\\Mods", {
        Nucleus = dir(R .. "\\Binaries\\Win64\\ue4ss\\Mods\\Nucleus", {}, { "mod.json" }),
        Keybinds = dir(R .. "\\Binaries\\Win64\\ue4ss\\Mods\\Keybinds"),
    }, { "mods.txt" })
    local tree = { Game = dir(R, {
        Binaries = dir(R .. "\\Binaries", { Win64 = dir(R .. "\\Binaries\\Win64", { ue4ss = dir(R .. "\\Binaries\\Win64\\ue4ss", { Mods = mods }) }) }),
        Content = dir(R .. "\\Content", { Paks = dir(R .. "\\Content\\Paks", { LogicMods = dir(R .. "\\Content\\Paks\\LogicMods", {}, { "Nucleus.pak" }) },
            { "NuclearNightmare-Windows.pak", "X_P.pak" }) }),
    }) }
    IterateGameDirectories = function() return tree end
    local opened = {}
    local realOpen = io.open
    local content = { [R .. "\\Binaries\\Win64\\ue4ss\\Mods\\Nucleus\\mod.json"] = '{"version":"0.8.0"}', [R .. "\\Binaries\\Win64\\ue4ss\\Mods\\mods.txt"] = "Nucleus : 1\n" }
    io.open = function(p, mode)
        opened[#opened + 1] = mode
        local c = content[p]
        if not c then return nil, p .. ": No such file or directory" end
        local pos = 0
        return { seek = function(_, w, o) if w == "end" then pos = #c return #c end pos = o or 0 return pos end,
            read = function(_, n) return c:sub(pos + 1, pos + n) end, close = function() end }
    end
    local fs, paths = I.gameFs("C:/nn/copy/NuclearNightmare/Binaries/Win64/ue4ss/Mods")
    ok(fs ~= nil and paths.paks == R .. "\\Content\\Paks" and paths.logicMods == R .. "\\Content\\Paks\\LogicMods", "adapter: Paks and LogicMods from the tree", tostring(paths))
    local res = I.scan(fs, paths)
    eq(names(res), "Nucleus,X", "adapter: folders from the tree (built-ins out), paks joined, a pak-only row")
    eq(rowOf(res, "Nucleus").version, "0.8.0", "adapter: mod.json read through io")
    local fs2, paths2 = I.gameFs("Mods") -- a relative script path: the tree's ue4ss/Mods instead
    ok(fs2 and paths2.mods == R .. "\\Binaries\\Win64\\ue4ss\\Mods" and #I.scan(fs2, paths2).rows == 2, "adapter: a path not under the game folder falls back to ue4ss/Mods")
    for _, m in ipairs(opened) do eq(m, "rb", "adapter: io.open only for reading") end
    IterateGameDirectories = function() error("boom") end
    local f3, why = I.gameFs("x")
    ok(f3 == nil and tostring(why):find("IterateGameDirectories failed", 1, true), "adapter: a failing IterateGameDirectories is an error, not a raise")
    IterateGameDirectories = function() return {} end
    ok(I.gameFs("x") == nil, "adapter: no Game folder")
    -- The adapter's own bounds: a mods.txt over its cap is refused from its size, unread, and a folder with more
    -- entries than MAX_ENTRIES is cut, with one WARN.
    local MD = R .. "\\Binaries\\Win64\\ue4ss\\Mods"
    local many = {}
    for i = 1, 5000 do local n = string.format("M%04d", i) many[n] = dir(MD .. "\\" .. n) end
    tree.Game.Binaries.Win64.ue4ss.Mods = dir(MD, many, { "mods.txt" })
    IterateGameDirectories = function() return tree end
    content[MD .. "\\mods.txt"] = string.rep("x", I.MAX_MODS_TXT + 1)
    local wrapped = io.open
    local reads = 0
    io.open = function(p, mode)
        local f, e = wrapped(p, mode)
        if f then local r = f.read f.read = function(...) reads = reads + 1 return r(...) end end
        return f, e
    end
    local fsBig, pathsBig = I.gameFs("C:/nn/copy/NuclearNightmare/Binaries/Win64/ue4ss/Mods")
    local text, err = fsBig.readFile(pathsBig.mods .. "\\mods.txt", I.MAX_MODS_TXT)
    ok(text == nil and tostring(err):find("262145 bytes", 1, true) and reads == 0, "adapter: a mods.txt over the cap is refused unread", tostring(err))
    eq(#fsBig.listDir(pathsBig.mods).dirs, I.MAX_ENTRIES + 1, "adapter: listing stops one past MAX_ENTRIES")
    local resBig = I.scan(fsBig, pathsBig)
    eq(warnsLike(resBig, "^the Mods folder has %d+ entries"), 1, "adapter: too many folders: one WARN")
    eq(resBig.total, I.MAX_ENTRIES + 2, "adapter: at most MAX_ENTRIES folders looked at (+ the X and Nucleus pak rows)")
    eq(warnsLike(resBig, "^mods%.txt could not be read %(262145 bytes"), 1, "adapter: the big mods.txt's WARN comes through the adapter")
    io.open = realOpen
    IterateGameDirectories = nil
    local src = assert(realOpen(ROOT .. "/Scripts/inventory.lua", "rb")):read("a"):gsub("%-%-[^\n]*", "")
    ok(not src:find("popen") and not src:find("os%.execute") and not src:find("os%.rename") and not src:find("os%.remove") and not src:find('"w') and not src:find('"a"'),
        "inventory.lua: no popen, execute, rename, remove or write mode")
end

io.stdout:write(("inventory_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
