-- Unit tests for Scripts/main.lua outside the game: the bootstrap (Nucleus missing or older: only connect's one line),
-- the entry, the click (scan, open, warnings once per session, faults caught), the gear, and that nothing is written.
-- Against a fake core (client.connect, core.ui from test/unit/fakeui.lua, core.log) and stubbed UE4SS globals.
-- Run from the repo root:  texlua test/unit/main_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
local MAIN = ROOT .. "/Scripts/main.lua"
package.path = ROOT .. "/test/unit/?.lua;" .. package.path
local FakeUi = require("fakeui")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. tostring(got) .. ", want " .. tostring(want)) end

-- ---------------------------------------------------------------- fakes
local W
local realOpen, realRename, realRemove, realExecute, realPopen = io.open, os.rename, os.remove, os.execute, io.popen
local realPrint = print

-- A game tree for IterateGameDirectories and the files io.open may read (mods.txt, mod.json).
local R = "C:\\nn\\copy\\NuclearNightmare"
local MODS = R .. "\\Binaries\\Win64\\ue4ss\\Mods"
local function dir(abs, children, files)
    local t = {}
    for k, v in pairs(children or {}) do t[k] = v end
    local f = {}
    for i, n in ipairs(files or {}) do f[i] = { __name = n } end
    return setmetatable(t, { __index = function(_, k)
        if k == "__absolute_path" then return abs end
        if k == "__files" then return f end
    end })
end
local function tree()
    local mods = {}
    for name, files in pairs(W.folders) do mods[name] = dir(MODS .. "\\" .. name, {}, files) end
    return { Game = dir(R, {
        Binaries = dir(R .. "\\Binaries", { Win64 = dir(R .. "\\Binaries\\Win64", { ue4ss = dir(R .. "\\Binaries\\Win64\\ue4ss", { Mods = dir(MODS, mods, { "mods.txt" }) }) }) }),
        Content = dir(R .. "\\Content", { Paks = dir(R .. "\\Content\\Paks", { LogicMods = dir(R .. "\\Content\\Paks\\LogicMods", {}, W.logicMods) }, W.paks) }),
    }) }
end

local function stubGlobals()
    print = function(s) W.printed[#W.printed + 1] = (tostring(s):gsub("\n$", "")) end
    IterateGameDirectories = function() W.iterations = W.iterations + 1 if W.noTree then error("no tree") end return tree() end
    io.open = function(p, mode)
        W.opens[#W.opens + 1] = { path = p, mode = mode }
        if mode ~= "rb" and mode ~= "r" then W.writes = W.writes + 1 return nil, "refused by the test" end
        local c = W.files[p]
        if not c then return nil, p .. ": No such file or directory" end
        local pos = 0
        return { seek = function(_, w, o) if w == "end" then pos = #c return #c end pos = o or 0 return pos end,
            read = function(_, n) if n == "a" or n == "*a" then return c end return c:sub(pos + 1, pos + n) end, close = function() end }
    end
    os.rename = function() W.writes = W.writes + 1 end
    os.remove = function() W.writes = W.writes + 1 end
    os.execute = function() W.writes = W.writes + 1 end
    io.popen = function() W.writes = W.writes + 1 end
    StaticFindObject = function(p)
        if p:find("KismetInternationalizationLibrary", 1, true) then
            return { IsValid = function() return true end, GetCurrentLanguage = function() return { ToString = function() return W.lang end } end }
        end
        if p:find("WidgetLayoutLibrary", 1, true) then
            return { IsValid = function() return true end, GetViewportSize = function() return { X = 1280, Y = 720 } end, GetViewportScale = function() return 2 / 3 end }
        end
        return nil
    end
    FindFirstOf = function(c) W.finds = W.finds + 1 return { IsValid = function() return true end } end
    LoopAsync = function() W.async = W.async + 1 end
    ExecuteInGameThread = function() W.async = W.async + 1 end
end
local function restore()
    print, io.open, os.rename, os.remove, os.execute, io.popen = realPrint, realOpen, realRename, realRemove, realExecute, realPopen
end

local function newLog(tag)
    local L = { debugEnabled = false }
    local function emit(level, fmt, ...) W.printed[#W.printed + 1] = "[" .. tag .. "] " .. level .. string.format(fmt, ...) end
    function L.info(f, ...) emit("", f, ...) end
    function L.warn(f, ...) emit("WARN ", f, ...) end
    function L.error(f, ...) emit("ERROR ", f, ...) end
    function L.debug(f, ...) if L.debugEnabled then emit("DEBUG ", f, ...) end end
    return L
end

-- Loads main.lua fresh as UE4SS would, from <MODS>\ModManager\Scripts\main.lua. opts.client = false: no core.
local function boot(opts)
    opts = opts or {}
    W = { printed = {}, connects = {}, opens = {}, writes = 0, iterations = 0, finds = 0, async = 0, lang = "en",
        folders = { Nucleus = { "mod.json" }, ModManager = { "mod.json" }, ModManagerFixture = { "mod.json" }, Keybinds = {}, shared = {} },
        paks = { "NuclearNightmare-Windows.pak", "ModManagerPak_P.pak" }, logicMods = { "Nucleus.pak" },
        files = {
            [MODS .. "\\mods.txt"] = "Nucleus : 1\r\nModManager : 1\r\nModManagerFixture : 0\r\nKeybinds : 1\r\n",
            [MODS .. "\\Nucleus\\mod.json"] = '{"id":"nucleus","version":"0.8.0","game":{"version":"V8.2.3","build":"26601774"},"dependsOn":[]}',
            [MODS .. "\\ModManager\\mod.json"] = '{"name":"ModManager","displayName":"Mod Manager","version":"0.1.0","dependsOn":[{"id":"nuclearnightmare-community.nucleus","version":">=0.8.0"}]}',
            [MODS .. "\\ModManagerFixture\\mod.json"] = '{"version":"9.9.9","game":{"version":"V0.0.0","build":"1"},"dependsOn":[{"id":"nuclearnightmare-community.nucleus","version":">=0.1.0"}],"settings":{"x":{}}}',
        } }
    for _, m in ipairs({ "nucleus.client", "json", "modid", "inventory", "strings", "screen" }) do package.loaded[m] = nil end
    package.preload["nucleus.client"] = nil
    if opts.client ~= false then
        package.preload["nucleus.client"] = function() return { connect = function(o) W.connects[#W.connects + 1] = o end } end
    end
    stubGlobals()
    local chunk = assert(loadfile(MAIN))
    -- UE4SS runs main.lua by its absolute path; debug.getinfo sees that as the source.
    local src = "@" .. MODS .. "\\ModManager\\Scripts\\main.lua"
    local text = assert(realOpen(MAIN, "rb")):read("a")
    chunk = assert(load(text, src))
    -- The script's own folder (in the fake game) has no files: the repo's Scripts stand in for it.
    package.path = ROOT .. "/Scripts/?.lua;" .. ROOT .. "/test/unit/?.lua;" .. (package.path:gsub("^.-/Scripts/%?%.lua;", ""))
    chunk()
end
local function newCore(o)
    o = o or {}
    local core = { name = "Nucleus", version = "0.8.0", log = newLog("ModManager"), clock = { micros = function() return 100 end } }
    if o.ui ~= false then core.ui = FakeUi.new() end
    return core
end
local function connect(core) W.connects[1].onReady(core) end
local function lines(pat) local r = {} for _, l in ipairs(W.printed) do if l:find(pat) then r[#r + 1] = l end end return r end

-- ---------------------------------------------------------------- bootstrap
do -- Nucleus missing: exactly one [ModManager] line, the bootstrap's own.
    boot{ client = false }
    eq(#W.printed, 1, "no core: exactly one line")
    eq(W.printed[1], "[ModManager] Nucleus is not installed. ModManager will not run.", "no core: the line names the cause")
    eq(#W.connects, 0, "no core: no connect")
    restore()
end
do -- Nucleus present: connect{ mod = "ModManager", need = ">=0.8.0" }, nothing logged before it answers.
    boot()
    eq(#W.connects, 1, "connect called once")
    local c = W.connects[1]
    ok(c.mod == "ModManager" and c.need == ">=0.8.0", "connect{ mod = 'ModManager', need = '>=0.8.0' }", tostring(c.mod) .. " " .. tostring(c.need))
    eq(#W.printed, 0, "nothing printed during main.lua")
    -- older than 0.8.0: connect logs its one line and calls onFail, which adds nothing
    c.onFail("Nucleus 0.7.0 is older than ModManager needs (>=0.8.0). Update Nucleus.")
    eq(#W.printed, 0, "onFail adds no line (connect's is the only one)")
    eq(W.iterations, 0, "onFail scans nothing")
    restore()
end
do -- mod.json and main.lua agree on the need.
    local mj = assert(realOpen(ROOT .. "/mod.json", "rb")):read("a")
    ok(mj:find('"version": ">=0.8.0"', 1, true) and mj:find('"id": "nuclearnightmare-community.nucleus"', 1, true), "mod.json dependsOn nuclearnightmare-community.nucleus >=0.8.0")
    local src = assert(realOpen(MAIN, "rb")):read("a")
    ok(src:find('local CORE, NEED, ME = "Nucleus", ">=0.8.0", "ModManager"', 1, true), "main.lua NEED = dependsOn")
end

-- ---------------------------------------------------------------- start
do -- No UI helpers: one ERROR line, no entry.
    boot()
    connect(newCore{ ui = false })
    eq(#lines("^%[ModManager%] ERROR Nucleus's UI helpers lack menu, screen, list, row, image, text, button%. ModManager will not run%.$"), 1, "no core.ui: one ERROR line")
    eq(#lines("READY"), 0, "no core.ui: no READY")
    restore()
end
do -- The entry fails: one ERROR line, no READY.
    boot()
    local core = newCore()
    core.ui.failEntry = true
    connect(core)
    eq(#lines("ERROR could not add the menu entry: nucleus%.ui%.menu%.entry: boom%. ModManager will not run%."), 1, "entry fails: one ERROR line")
    eq(#lines("READY"), 0, "entry fails: no READY")
    restore()
end

do -- The entry, READY, a click, the window, the gear, warnings once, faults once, nothing written.
    boot()
    local core = newCore()
    local U = core.ui
    connect(core)
    eq(#U.entries, 1, "one menu entry")
    local e = U.entries[1]
    ok(e.id == "manage" and e.style == "options" and e.label.en == "MANAGE MODS" and type(e.onClick) == "function", "entry{ id = 'manage', label = { en = 'MANAGE MODS' }, style = 'options' }")
    eq(#lines("^%[ModManager%] READY entry=manage need=>=0%.8%.0$"), 1, "one READY line after onReady")
    eq(W.iterations, 0, "nothing scanned before a click")
    eq(U.count("screen.open"), 0, "no window before a click")

    e.onClick()
    eq(W.iterations, 1, "a click scans once")
    eq(U.count("screen.open"), 1, "and opens the main window")
    eq(#lines("^%[ModManager%] OPEN rows=4 total=4 lang=en us=0$"), 1, "OPEN line: Nucleus, Mod Manager, the fixture, the pak")
    eq(U.byId["r1.name"].text, "Nucleus", "row 1 Nucleus")
    eq(U.byId["r2.name"].text, "Mod Manager", "row 2 Mod Manager")
    eq(U.byId.list.size.w, 1920 - 2 * 360, "1280x720 lays out at 1920 layout units")
    eq(#lines("^%[ModManager%] MOD %d "), 4, "each mod's data logged")
    eq(#lines("^%[ModManager%] MOD 3 ModManagerFixture | ModManagerFixture | 9%.9%.9 | off | settings=yes | need=>=0%.1%.0 | build=V0%.0%.0 1$"), 1, "the fixture's data line")
    eq(#lines("^%[ModManager%] MOD 4 pak:modmanagerpak | ModManagerPak | UNMANAGED | on | settings=no | need=%- | build=%-$"), 1, "the pak's data line")

    -- A second click: rescans, reopens, logs no data line again (unchanged).
    U.open.main = nil
    e.onClick()
    eq(W.iterations, 2, "a second click rescans")
    eq(#lines("^%[ModManager%] MOD %d "), 4, "unchanged data is not logged again")

    -- A mod's data changes: its line is logged once more, the others are not.
    W.files[MODS .. "\\ModManagerFixture\\mod.json"] = W.files[MODS .. "\\ModManagerFixture\\mod.json"]:gsub("9%.9%.9", "9.9.10")
    e.onClick()
    eq(#lines("^%[ModManager%] MOD %d "), 5, "changed data: one more line")
    eq(#lines("^%[ModManager%] MOD 3 ModManagerFixture | ModManagerFixture | 9%.9%.10 | off | "), 1, "the fixture's new data line")
    e.onClick()
    eq(#lines("^%[ModManager%] MOD %d "), 5, "the changed data is not logged again")

    -- A bad mod.json appears: one WARN, however many clicks.
    W.folders.Broken = { "mod.json" }
    W.files[MODS .. "\\Broken\\mod.json"] = "{nope"
    e.onClick(); e.onClick(); e.onClick()
    eq(#lines("^%[ModManager%] WARN Broken/mod%.json is not valid JSON"), 1, "a broken mod.json: one WARN per session")
    eq(U.byId["r3.name"].text, "Broken", "the broken one is a row (by folder name)")

    -- The gear opens Configure (dimmed or not) and logs it.
    U.byId["r1.cfg"].onClick()
    eq(#lines("^%[ModManager%] CONFIGURE 1 Nucleus$"), 1, "Nucleus's dimmed gear opens Configure")
    ok(U.byId["cfg.need"].text == "NUCLEUS -", "Nucleus: NUCLEUS -")
    U.byId["r4.cfg"].onClick()
    ok(U.byId["cfg.need"].text == "NUCLEUS >=0.1.0" and U.byId["cfg.build"].text == "GAME BUILD V0.0.0 1", "the fixture's Configure lines")

    -- A fault in a click: one WARN with context; the next click still works.
    U.noMenu = true
    e.onClick(); e.onClick()
    eq(#lines("^%[ModManager%] WARN the Mod Manager window failed: nucleus%.ui%.screen%.open: the title%-screen menu is not open"), 1, "a fault: one WARN with context")
    U.noMenu = false
    local opens = U.count("screen.open")
    e.onClick()
    eq(U.count("screen.open"), opens + 1, "after a fault the next click opens again")
    U.failOn = "cfg.title"
    -- a fresh view would create cfg.* ; this one already has them, so make a gear fault instead
    U.failOn = nil
    local realOpenC = U.screen.open
    U.screen.open = function(o) if o.id == "configure" then error("boom configure") end return realOpenC(o) end
    U.byId["r1.cfg"].onClick(); U.byId["r1.cfg"].onClick()
    eq(#lines("^%[ModManager%] WARN Configure failed: .*boom configure"), 1, "a gear fault: one WARN")
    U.screen.open = realOpenC

    -- Nothing is written, ever; no shell; no async thread.
    eq(W.writes, 0, "no write, rename, remove, execute or popen")
    for _, o in ipairs(W.opens) do ok(o.mode == "rb", "io.open read-only: " .. o.path) end
    eq(W.async, 0, "never LoopAsync or ExecuteInGameThread")
    eq(#lines("ERROR"), 0, "no ERROR line")
    restore()
end

do -- The game folder can't be read: one WARN, an empty list, the window still opens.
    boot()
    local core = newCore()
    connect(core)
    W.noTree = true
    core.ui.entries[1].onClick()
    core.ui.open.main = nil
    core.ui.entries[1].onClick()
    eq(#lines("^%[ModManager%] WARN the game folder could not be read %(IterateGameDirectories failed: .*%); the list is empty$"), 1, "no tree: one WARN")
    eq(core.ui.count("screen.open"), 2, "no tree: the window still opens")
    eq(#lines("OPEN rows=0 total=0"), 2, "no tree: empty")
    restore()
end

do -- Many distinct warnings: at most 64 lines plus one saying the rest are dropped.
    boot()
    local core = newCore()
    connect(core)
    for i = 1, 80 do
        local n = string.format("Bad%02d", i)
        W.folders[n] = { "mod.json" }
        W.files[MODS .. "\\" .. n .. "\\mod.json"] = "["
    end
    core.ui.entries[1].onClick()
    eq(#lines("^%[ModManager%] WARN Bad%d+/mod%.json"), 64, "64 warnings")
    eq(#lines("^%[ModManager%] WARN more than 64 different warnings"), 1, "then one line")
    restore()
end

do -- German: the entry label table carries every language; the window follows the game's language.
    boot()
    local core = newCore()
    connect(core)
    W.lang = "de-AT"
    core.ui.entries[1].onClick()
    eq(#lines("OPEN rows=%d+ total=%d+ lang=de%-AT"), 1, "the language read at the click")
    eq(core.ui.byId.title.text, "MOD MANAGER", "no de table shipped: English")
    restore()
end

io.stdout:write(("main_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
