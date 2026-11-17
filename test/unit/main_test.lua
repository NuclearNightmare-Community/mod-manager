-- Unit tests for Scripts/main.lua outside the game: the bootstrap (Nucleus missing or older: only connect's one line),
-- the entry, the click (scan, open, warnings once per session, faults caught), the gear; story 6: every row of its I/O
-- matrix offline (the toggle and mods.txt's bytes, the confirm, enabled.txt, a failing write, the .mm-bak restore, the
-- status icons, the Nucleus alert once, Configure's settings, a corrupt state.json, QUIT GAME), and that writes go only to
-- the allowed paths. Against a fake core (client.connect, core.ui from test/unit/fakeui.lua, core.settings, core.log),
-- stubbed UE4SS globals and an in-memory file system behind io.open, os.rename and os.remove.
-- Run from the repo root:  texlua test/unit/main_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
local MAIN = ROOT .. "/Scripts/main.lua"
package.path = ROOT .. "/test/unit/?.lua;" .. package.path
dofile(ROOT .. "/test/unit/nucleus_pkg.lua")(ROOT) -- nucleus.modid and nucleus.semver from the Nucleus repo
local FakeUi = require("fakeui")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. string.format("%q", tostring(got)) .. ", want " .. string.format("%q", tostring(want))) end

-- ---------------------------------------------------------------- fakes
local W
local realOpen, realRename, realRemove, realExecute, realPopen = io.open, os.rename, os.remove, os.execute, io.popen
local realPrint = print

-- A game tree for IterateGameDirectories and the files io.open may read and write.
local R = "C:\\nn\\copy\\NuclearNightmare"
local MODS = R .. "\\Binaries\\Win64\\ue4ss\\Mods"
local TXT = MODS .. "\\mods.txt"
local STATE = MODS .. "\\ModManager\\state.json"
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

-- The paths the Mod Manager may write (story 6): mods.txt, Mods/<F>/enabled.txt(.disabled), its state.json, and their
-- .mm-tmp / .mm-bak.
local function allowed(p)
    local function under(base) return p == base or p == base .. ".mm-tmp" or p == base .. ".mm-bak" end
    if under(TXT) or under(STATE) then return true end
    local f = p:match("^" .. MODS:gsub("%p", "%%%0") .. "\\([A-Za-z0-9_-]+)\\enabled%.txt$") or p:match("^" .. MODS:gsub("%p", "%%%0") .. "\\([A-Za-z0-9_-]+)\\enabled%.txt%.disabled$")
    return f ~= nil
end

local function stubGlobals()
    print = function(s) W.printed[#W.printed + 1] = (tostring(s):gsub("\n$", "")) end
    IterateGameDirectories = function() W.iterations = W.iterations + 1 if W.noTree then error("no tree") end return tree() end
    io.open = function(p, mode)
        W.opens[#W.opens + 1] = { path = p, mode = mode }
        if mode == "wb" then
            W.writes[#W.writes + 1] = p
            if W.failWrite and p:find(W.failWrite) then
                if (W.failWriteSkip or 0) > 0 then W.failWriteSkip = W.failWriteSkip - 1
                else W.failWrite = nil return nil, p .. ": Permission denied" end
            end
            local buf = {}
            return { write = function(self, s) buf[#buf + 1] = s return self end, flush = function(self) return self end,
                close = function() W.files[p] = table.concat(buf) return true end }
        end
        if mode ~= "rb" and mode ~= "r" then W.badModes = W.badModes + 1 return nil, "refused by the test" end
        local c = W.files[p]
        if not c then return nil, p .. ": No such file or directory" end
        local pos = 0
        return { seek = function(_, w, o) if w == "end" then pos = #c return #c end pos = o or 0 return pos end,
            read = function(_, n) if n == "a" or n == "*a" then return c end return c:sub(pos + 1, pos + n) end, close = function() end }
    end
    os.rename = function(a, b)
        W.writes[#W.writes + 1] = a; W.writes[#W.writes + 1] = b
        if W.failRename and a:find(W.failRename) then W.failRename = nil return nil, a .. ": Permission denied" end
        if W.files[a] == nil then return nil, a .. ": No such file or directory" end
        if W.files[b] ~= nil then return nil, b .. ": File exists" end
        W.files[b], W.files[a] = W.files[a], nil
        return true
    end
    os.remove = function(p)
        W.writes[#W.writes + 1] = p
        if W.files[p] == nil then return nil, p .. ": No such file or directory" end
        W.files[p] = nil
        return true
    end
    os.execute = function() W.shell = W.shell + 1 end
    io.popen = function() W.shell = W.shell + 1 end
    -- the menu's tree: WidgetSwitcher_1 -> CanvasPanel_17 -> { a logo, NN_MainFooter }
    local function widget(name, children, text)
        return { IsValid = function() return true end, GetFName = function() return { ToString = function() return name end } end,
            GetChildrenCount = function() if not children then error("not a panel") end return #children end,
            GetChildAt = function(_, i) return children[i + 1] end,
            GetText = function() return { ToString = function() return text() end } end }
    end
    local footer = widget("NN_MainFooter", nil, function() return W.footer end)
    local root = widget("WidgetSwitcher_1", { widget("CanvasPanel_17", { widget("Image_0"), footer }) })
    local menu = { IsValid = function() return true end, IsInViewport = function() return W.menuUp end, WidgetTree = { RootWidget = root } }
    FindAllOf = function(c) if c == "MainMenu_C" then return { menu } end return nil end
    local pc = { IsValid = function() return true end, GetWorld = function() return "world" end }
    StaticFindObject = function(p)
        if p:find("KismetInternationalizationLibrary", 1, true) then
            return { IsValid = function() return true end, GetCurrentLanguage = function() return { ToString = function() return W.lang end } end }
        end
        if p:find("WidgetLayoutLibrary", 1, true) then
            return { IsValid = function() return true end, GetViewportSize = function() return { X = 1280, Y = 720 } end, GetViewportScale = function() return 2 / 3 end }
        end
        if p:find("KismetSystemLibrary", 1, true) then
            return { IsValid = function() return true end, QuitGame = function(_, world, p2, pref, ignore) W.quits[#W.quits + 1] = { world, p2, pref, ignore } end }
        end
        return nil
    end
    FindFirstOf = function(c) W.finds = W.finds + 1 return pc end
    LoopAsync = function() W.async = W.async + 1 end
    ExecuteInGameThread = function() W.async = W.async + 1 end
    -- runs at once here (the game runs it on the next game-thread tick); counted
    ExecuteInGameThreadWithDelay = function(ms, fn) W.delayed = W.delayed + 1 fn() end
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

local MJ = {
    Nucleus = '{"id":"nuclearnightmare-community.nucleus","version":"0.12.1","game":{"version":"V8.2.3","build":"26601774"},"dependsOn":[]}',
    ModManager = '{"id":"nuclearnightmare-community.mod-manager","name":"ModManager","displayName":"Mod Manager","version":"0.2.0","game":{"version":"V8.2.3","build":"26601774"},"dependsOn":[{"id":"nuclearnightmare-community.nucleus","version":">=0.12.0"}]}',
    ModManagerFixture = '{"id":"nuclearnightmare-community.mod-manager-fixture","version":"9.9.9","game":{"version":"V0.0.0","build":"1"},"dependsOn":[{"id":"nuclearnightmare-community.nucleus","version":">=0.1.0"},{"id":"nuclearnightmare-community.mod-manager-missing","version":">=1.0.0"},{"id":"nuclearnightmare-community.mod-manager-base","version":">=2.0.0"}],"settings":{"x":{}}}',
    ModManagerBase = '{"id":"nuclearnightmare-community.mod-manager-base","displayName":"Mod Manager Base","version":"1.0.0","game":{"version":"V8.2.3","build":"26601774"},"dependsOn":[{"id":"nuclearnightmare-community.nucleus","version":">=0.12.0"}]}',
    ModManagerDep = '{"id":"nuclearnightmare-community.mod-manager-dep","displayName":"Mod Manager Dep","version":"1.0.0","game":{"version":"V8.2.3","build":"26601774"},"dependsOn":[{"id":"nuclearnightmare-community.mod-manager-base","version":">=1.0.0"}]}',
}
local TXT0 = "\239\187\191Nucleus : 1\r\nModManager : 1\r\nModManagerFixture : 0\r\nModManagerBase : 1\r\nModManagerDep : 1\r\nKeybinds : 1\r\n"

-- Loads main.lua fresh as UE4SS would, from <MODS>\ModManager\Scripts\main.lua. opts.client = false: no core.
local function boot(opts)
    opts = opts or {}
    W = { printed = {}, connects = {}, opens = {}, writes = {}, badModes = 0, shell = 0, iterations = 0, finds = 0, async = 0, lang = "en",
        quits = {}, delayed = 0, menuUp = true, footer = "NUCLEAR NIGHTMARE EA V8.2.3",
        folders = { Nucleus = { "mod.json" }, ModManager = { "mod.json" }, ModManagerFixture = { "mod.json" }, ModManagerBase = { "mod.json" },
            ModManagerDep = { "mod.json" }, ModManagerBare = {}, Keybinds = {}, shared = {} },
        paks = { "NuclearNightmare-Windows.pak", "ModManagerPak_P.pak" }, logicMods = { "Nucleus.pak" },
        files = { [TXT] = TXT0 } }
    for f, j in pairs(MJ) do W.files[MODS .. "\\" .. f .. "\\mod.json"] = j end
    for k, v in pairs(opts.files or {}) do W.files[k] = v or nil end
    for _, m in ipairs({ "nucleus.client", "json", "nucleus.modid", "nucleus.semver", "inventory", "strings", "screen", "status", "modstxt", "files", "state" }) do package.loaded[m] = nil end
    package.preload["nucleus.client"] = nil
    if opts.client ~= false then
        package.preload["nucleus.client"] = function() return { connect = function(o) W.connects[#W.connects + 1] = o end } end
    end
    stubGlobals()
    local src = "@" .. MODS .. "\\ModManager\\Scripts\\main.lua"
    local text = assert(realOpen(MAIN, "rb")):read("a")
    local chunk = assert(load(text, src))
    package.path = ROOT .. "/Scripts/?.lua;" .. ROOT .. "/test/unit/?.lua;" .. (package.path:gsub("^.-/Scripts/%?%.lua;", ""))
    chunk()
end
local FIXTURE_SETTINGS = {
    { key = "flag", type = "bool", value = false, default = false, label = "Flag", changeable = "anytime" },
    { key = "example", type = "int", value = 1, default = 1, min = 1, max = 9, label = "Example", changeable = "anytime" },
    { key = "mode", type = "enum", value = "one", default = "one", values = { "one", "two", "three" }, label = "Mode", changeable = "anytime" },
    { key = "later", type = "bool", value = false, default = false, label = "Restart flag", changeable = "restart", restart = true, pendingRestart = false },
    { key = "preset", type = "number", label = "Preset value", source = "presets", readOnly = true, changeable = "anytime" },
}
local function newCore(o)
    o = o or {}
    local core = { name = "Nucleus", version = "0.12.1", log = newLog("ModManager"), clock = { micros = function() return 100 end } }
    if o.ui ~= false then core.ui = FakeUi.new() end
    local settings = {}
    for i, e in ipairs(FIXTURE_SETTINGS) do local c = {} for k, v in pairs(e) do c[k] = v end settings[i] = c end
    core.settings = FakeUi.settings({ ModManagerFixture = { settings = settings } })
    return core
end
local function connect(core) W.connects[1].onReady(core) end
local function lines(pat) local r = {} for _, l in ipairs(W.printed) do if l:find(pat) then r[#r + 1] = l end end return r end
local function rowOf(U, name) for n = 1, 64 do local el = U.byId["r" .. n .. ".name"] if el and el.text == name and U.byId["r" .. n].visible then return n end end end
local function icons(U, n)
    local t = {}
    for k = 1, 3 do local el = U.byId["r" .. n .. ".s" .. k] if el.image then t[#t + 1] = el.image.icon end end
    return table.concat(t, ",")
end
local function badWrites() local r = {} for _, p in ipairs(W.writes) do if not allowed(p) then r[#r + 1] = p end end return r end

-- ---------------------------------------------------------------- bootstrap
do -- Nucleus missing: exactly one [ModManager] line, the bootstrap's own.
    boot{ client = false }
    eq(#W.printed, 1, "no core: exactly one line")
    eq(W.printed[1], "[ModManager] Nucleus is not installed. ModManager will not run.", "no core: the line names the cause")
    eq(#W.connects, 0, "no core: no connect")
    restore()
end
do -- Nucleus present: connect{ mod = "ModManager", need = ">=0.12.0" }, nothing logged before it answers.
    boot()
    eq(#W.connects, 1, "connect called once")
    local c = W.connects[1]
    ok(c.mod == "ModManager" and c.need == ">=0.12.0", "connect{ mod = 'ModManager', need = '>=0.12.0' }", tostring(c.mod) .. " " .. tostring(c.need))
    eq(#W.printed, 0, "nothing printed during main.lua")
    c.onFail("Nucleus 0.11.0 is older than ModManager needs (>=0.12.0). Update Nucleus.")
    eq(#W.printed, 0, "onFail adds no line (connect's is the only one)")
    eq(W.iterations, 0, "onFail scans nothing")
    eq(#W.writes, 0, "onFail writes nothing")
    restore()
end
do -- mod.json and main.lua agree on the need; 0.2.0.
    local mj = assert(realOpen(ROOT .. "/mod.json", "rb")):read("a")
    ok(mj:find('"version": ">=0.12.0"', 1, true) and mj:find('"id": "nuclearnightmare-community.nucleus"', 1, true), "mod.json dependsOn nuclearnightmare-community.nucleus >=0.12.0")
    ok(mj:find('"version": "0.2.0"', 1, true), "mod.json version 0.2.0")
    local src = assert(realOpen(MAIN, "rb")):read("a")
    ok(src:find('local CORE, NEED, ME = "Nucleus", ">=0.12.0", "ModManager"', 1, true), "main.lua NEED = dependsOn")
end

-- ---------------------------------------------------------------- start
do -- No UI helpers: one ERROR line, no entry.
    boot()
    connect(newCore{ ui = false })
    eq(#lines("^%[ModManager%] ERROR Nucleus's UI helpers lack menu, screen, list, row, image, text, button, checkbox, choice, slider%. ModManager will not run%.$"), 1, "no core.ui: one ERROR line")
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

do -- The entry, READY, a click, the window, the gear, warnings once, faults once.
    boot()
    local core = newCore()
    local U = core.ui
    connect(core)
    eq(#U.entries, 1, "one menu entry")
    local e = U.entries[1]
    ok(e.id == "manage" and e.style == "options" and e.label.en == "MANAGE MODS" and type(e.onClick) == "function", "entry{ id = 'manage', label = { en = 'MANAGE MODS' }, style = 'options' }")
    eq(#lines("^%[ModManager%] READY entry=manage need=>=0%.12%.0$"), 1, "one READY line after onReady")
    eq(W.iterations, 1, "onReady scans once (the session baseline)")
    eq(U.count("screen.open"), 0, "no window before a click")
    eq(#W.writes, 0, "onReady writes nothing")

    e.onClick()
    eq(W.iterations, 2, "a click reads the game folder once (the running game and the rows)")
    eq(U.count("screen.open"), 1, "and opens the main window")
    eq(#lines("^%[ModManager%] OPEN rows=7 total=7 lang=en game=V8%.2%.3 build=%- us=0$"), 1, "OPEN line: rows, the running game (build unknown on a dev copy)")
    eq(U.byId["r1.name"].text, "Nucleus", "row 1 Nucleus")
    eq(U.byId["r2.name"].text, "Mod Manager", "row 2 Mod Manager")
    eq(U.byId.list.size.w, 1920 - 720, "1280x720 lays out at 1920 layout units")
    eq(#lines("^%[ModManager%] MOD %d "), 7, "each mod's data logged")
    eq(#lines("^%[ModManager%] MOD %d ModManagerFixture | ModManagerFixture | 9%.9%.9 | off | settings=yes | need=>=0%.1%.0 | build=V0%.0%.0 1$"), 1, "the fixture's data line")
    -- STATUS lines, once per row
    eq(#lines("^%[ModManager%] STATUS "), 7, "one STATUS line per row")
    for _, f in ipairs({ "Nucleus", "ModManager", "ModManagerBase", "ModManagerDep", "ModManagerBare", "pak:modmanagerpak" }) do
        eq(#lines("^%[ModManager%] STATUS " .. f:gsub("%p", "%%%0") .. " none | $"), 1, f .. ": STATUS none")
    end
    eq(#lines("^%[ModManager%] STATUS ModManagerFixture build,dep | MADE FOR GAME V0%.0%.0 %(BUILD 1%)%. THIS GAME: V8%.2%.3 %(BUILD %-%)%. / NEEDS nuclearnightmare%-community%.mod%-manager%-missing %(NOT INSTALLED%) / NEEDS Mod Manager Base >=2%.0%.0 %(INSTALLED: 1%.0%.0%)$"), 1, "the fixture: build and dependency")
    local fx = rowOf(U, "ModManagerFixture")
    eq(icons(U, fx), "warning,warning", "the fixture's slot: build, dependency")
    eq(U.byId["r" .. fx .. ".s2"].tooltip, "NEEDS nuclearnightmare-community.mod-manager-missing (NOT INSTALLED)\nNEEDS Mod Manager Base >=2.0.0 (INSTALLED: 1.0.0)", "one dependency icon, two lines")
    eq(#lines("ALERT"), 0, "Nucleus made for this game: no alert")
    ok(not U.byId.quit.visible and not U.byId.banner.visible, "nothing pending: no QUIT GAME, no banner")

    -- A second click: rescans, reopens, logs no data or STATUS line again (unchanged).
    U.open.main = nil
    e.onClick()
    eq(#lines("^%[ModManager%] MOD %d "), 7, "unchanged data is not logged again")
    eq(#lines("^%[ModManager%] STATUS "), 7, "unchanged statuses are not logged again")

    -- A bad mod.json appears: one WARN, however many clicks.
    W.folders.Broken = { "mod.json" }
    W.files[MODS .. "\\Broken\\mod.json"] = "{nope"
    e.onClick(); e.onClick(); e.onClick()
    eq(#lines("^%[ModManager%] WARN Broken/mod%.json is not valid JSON"), 1, "a broken mod.json: one WARN per session")

    -- The gear opens Configure (dimmed or not) and logs it; the fixture's has problem lines and controls.
    U.byId["r1.cfg"].onClick()
    eq(#lines("^%[ModManager%] CONFIGURE 1 Nucleus$"), 1, "Nucleus's dimmed gear opens Configure")
    eq(W.delayed, 1, "Configure is built on the next game-thread tick (outside the click hook)")
    ok(U.byId["cfg.need"].text == "NUCLEUS -" and U.byId["cfg.none"].visible, "Nucleus: NUCLEUS -, NO SETTINGS")
    fx = rowOf(U, "ModManagerFixture")
    U.byId["r" .. fx .. ".cfg"].onClick()
    ok(U.byId["cfg.need"].text == "NUCLEUS >=0.1.0" and U.byId["cfg.build"].text == "GAME BUILD V0.0.0 1", "the fixture's Configure lines")
    ok(U.byId["cfg.p1"].text:find("^MADE FOR GAME V0%.0%.0") and U.byId["cfg.p3"].text == "NEEDS Mod Manager Base >=2.0.0 (INSTALLED: 1.0.0)" and not U.byId["cfg.p4"].visible, "Configure: one line per status problem")

    -- A fault in a click: one WARN with context; the next click still works.
    U.noMenu = true
    e.onClick(); e.onClick()
    eq(#lines("^%[ModManager%] WARN the Mod Manager window failed: nucleus%.ui%.screen%.open: the title%-screen menu is not open"), 1, "a fault: one WARN with context")
    U.noMenu = false
    local opens = U.count("screen.open")
    U.open.main = nil
    e.onClick()
    eq(U.count("screen.open"), opens + 1, "after a fault the next click opens again")
    local realOpenC = U.screen.open
    U.screen.open = function(o) if o.id == "configure" then error("boom configure") end return realOpenC(o) end
    U.byId["r1.cfg"].onClick(); U.byId["r1.cfg"].onClick()
    eq(#lines("^%[ModManager%] WARN Configure failed: .*boom configure"), 1, "a gear fault: one WARN")
    U.screen.open = realOpenC

    eq(#W.writes, 0, "opening, Configure and faults write nothing")
    eq(W.shell, 0, "no shell"); eq(W.badModes, 0, "no other open mode")
    eq(W.async, 0, "never LoopAsync or ExecuteInGameThread")
    eq(#lines("ERROR"), 0, "no ERROR line")
    restore()
end

-- ---------------------------------------------------------------- story 6: on/off
local function session(opts)
    boot(opts)
    local core = newCore()
    connect(core)
    core.ui.entries[1].onClick()
    return core, core.ui
end

do -- Off, no dependents; back on: mods.txt bytes, restart icon, banner, QUIT GAME, state.json.
    local core, U = session()
    local dep = rowOf(U, "Mod Manager Dep")
    ok(U.byId["r" .. dep .. ".tg"].checked and U.byId["r" .. dep .. ".tg"].enabled, "Dep: a live box, on")
    U.toggle("r" .. dep .. ".tg")
    eq(W.files[TXT], TXT0:gsub("ModManagerDep : 1", "ModManagerDep : 0"), "Dep off: ': 0', every other byte kept (BOM, CRLF)")
    eq(#lines("^%[ModManager%] TOGGLE ModManagerDep off$"), 1, "TOGGLE ModManagerDep off")
    eq(U.count("screen.open"), 1, "no confirm (no dependents)")
    dep = rowOf(U, "Mod Manager Dep")
    eq(icons(U, dep), "restart", "Dep: the restart icon")
    eq(U.byId["r" .. dep .. ".s1"].tooltip, "TURNS OFF AFTER A RESTART", "its tooltip")
    ok(U.byId.quit.visible and U.byId.banner.visible, "banner and QUIT GAME shown")
    eq(W.files[STATE], '{"version":1,"off":["ModManagerDep"],"seen":[]}', "state.json: off has Dep")
    eq(#lines("^%[ModManager%] STATUS ModManagerDep restart | TURNS OFF AFTER A RESTART$"), 1, "STATUS line for the change")
    U.toggle("r" .. dep .. ".tg")
    eq(W.files[TXT], TXT0, "back on: mods.txt's bytes equal the session start")
    eq(#lines("^%[ModManager%] TOGGLE ModManagerDep on$"), 1, "TOGGLE ModManagerDep on")
    eq(icons(U, rowOf(U, "Mod Manager Dep")), "", "no restart icon")
    ok(not U.byId.quit.visible and not U.byId.banner.visible, "banner and QUIT GAME hidden")
    eq(W.files[STATE], '{"version":1,"off":[],"seen":[]}', "state.json: removed from off")
    eq(#badWrites(), 0, "writes only to the allowed paths", table.concat(badWrites(), ", "))
    for k in pairs(W.files) do ok(not k:find("%.mm%-tmp$") and not k:find("%.mm%-bak$"), "no leftover " .. k) end
    eq(#lines("WARN"), 0, "no WARN")
    restore()
end

do -- Off with dependents: the confirm; BACK -> still on, nothing written; TURN OFF -> ': 0', Dep's dependency icon.
    local core, U = session()
    local base = rowOf(U, "Mod Manager Base")
    U.toggle("r" .. base .. ".tg")
    ok(U.open.confirm and U.byId["confirm.text"].text == "TURN OFF Mod Manager Base? Mod Manager Dep NEED IT.", "the confirm names Mod Manager Dep", U.byId["confirm.text"] and U.byId["confirm.text"].text)
    eq(#W.writes, 0, "nothing written while it asks")
    U.back("confirm")
    ok(U.byId["r" .. base .. ".tg"].checked == true, "BACK: the box set back on")
    eq(#W.writes, 0, "BACK: nothing written")
    eq(#lines("^%[ModManager%] CONFIRM ModManagerBase cancelled %(close%)$"), 1, "the cancel is logged")
    -- again, then TURN OFF
    U.toggle("r" .. base .. ".tg")
    U.byId["confirm.ok"].onClick()
    ok(not U.open.confirm, "TURN OFF closes the confirm")
    eq(W.files[TXT], TXT0:gsub("ModManagerBase : 1", "ModManagerBase : 0"), "TURN OFF: ': 0'")
    eq(#lines("^%[ModManager%] TOGGLE ModManagerBase off$"), 1, "TOGGLE ModManagerBase off")
    local dep = rowOf(U, "Mod Manager Dep")
    eq(icons(U, dep), "warning", "Dep: the dependency icon")
    eq(U.byId["r" .. dep .. ".s1"].tooltip, "NEEDS Mod Manager Base (TURNED OFF)", "NEEDS ... (TURNED OFF)")
    eq(U.byId["r" .. dep .. ".tg"].checked, true, "Dep stays on: no cascade")
    eq(#lines("CONFIRM ModManagerBase cancelled"), 1, "the TURN OFF close is not a cancel")
    -- a parent closing (the main window) or the menu lost cancels too
    U.open.main = nil; U.entries[1].onClick()
    dep = rowOf(U, "Mod Manager Dep")
    -- Dep has no dependents; turn the fixture's dependency on... use Nucleus-free case: the main window closed under a confirm
    base = rowOf(U, "Mod Manager Base")
    U.toggle("r" .. base .. ".tg") -- back on: no confirm
    eq(W.files[TXT], TXT0, "Base back on")
    U.toggle("r" .. base .. ".tg")
    ok(U.open.confirm, "asks again")
    U.back("main")
    ok(not U.open.confirm and U.byId["r" .. base .. ".tg"].checked == true and W.files[TXT] == TXT0, "the main window closed under it: cancelled, nothing written")
    eq(#lines("CONFIRM ModManagerBase cancelled %(parent%)"), 1, "reason parent")
    eq(#badWrites(), 0, "writes only to the allowed paths")
    eq(#lines("WARN"), 0, "no WARN")
    restore()
end

do -- No line: inserted above Keybinds; enabled.txt renamed on off.
    local core, U = session{ files = { [MODS .. "\\ModManagerBare\\enabled.txt"] = "" } }
    local bare = rowOf(U, "ModManagerBare")
    ok(U.byId["r" .. bare .. ".tg"].checked, "Bare on by its enabled.txt")
    U.toggle("r" .. bare .. ".tg")
    eq(W.files[TXT], TXT0, "off with no line: mods.txt untouched")
    ok(W.files[MODS .. "\\ModManagerBare\\enabled.txt"] == nil and W.files[MODS .. "\\ModManagerBare\\enabled.txt.disabled"] == "", "enabled.txt -> enabled.txt.disabled")
    bare = rowOf(U, "ModManagerBare")
    ok(U.byId["r" .. bare .. ".tg"].checked == false and icons(U, bare) == "restart", "the row off, pending")
    U.toggle("r" .. bare .. ".tg")
    eq(W.files[TXT], TXT0:gsub("Keybinds : 1", "ModManagerBare : 1\r\nKeybinds : 1"), "on with no line: inserted above Keybinds, CRLF")
    ok(W.files[MODS .. "\\ModManagerBare\\enabled.txt.disabled"] == "" and W.files[MODS .. "\\ModManagerBare\\enabled.txt"] == nil, "on never touches enabled.txt")
    eq(icons(U, rowOf(U, "ModManagerBare")), "", "on again: not pending")
    eq(#badWrites(), 0, "writes only to the allowed paths")
    restore()
end

do -- A stale enabled.txt.disabled is removed first.
    local core, U = session{ files = { [MODS .. "\\ModManagerBare\\enabled.txt"] = "new", [MODS .. "\\ModManagerBare\\enabled.txt.disabled"] = "old" } }
    U.toggle("r" .. rowOf(U, "ModManagerBare") .. ".tg")
    eq(W.files[MODS .. "\\ModManagerBare\\enabled.txt.disabled"], "new", "the stale copy replaced")
    restore()
end

do -- Write fails: previous file intact, box set back, COULD NOT SAVE THE CHANGE, one WARN.
    local core, U = session()
    local dep = rowOf(U, "Mod Manager Dep")
    W.failWrite = "mods%.txt%.mm%-tmp$"
    U.toggle("r" .. dep .. ".tg")
    eq(W.files[TXT], TXT0, "tmp write failed: mods.txt intact")
    ok(U.byId["r" .. dep .. ".tg"].checked == true, "the box set back")
    ok(U.byId.msg.visible and U.byId.msg.text == "COULD NOT SAVE THE CHANGE", "the message line")
    eq(#lines("^%[ModManager%] WARN could not turn ModManagerDep off: writing mods%.txt%.mm%-tmp"), 1, "one WARN")
    eq(#lines("TOGGLE"), 0, "no TOGGLE line")
    eq(W.files[STATE], nil, "state.json not written")
    W.failRename = "\\mods%.txt$"
    U.toggle("r" .. dep .. ".tg")
    ok(W.files[TXT] == TXT0 and W.files[TXT .. ".mm-tmp"] == nil and W.files[TXT .. ".mm-bak"] == nil, "rename failed: intact, no leftovers")
    ok(U.byId["r" .. dep .. ".tg"].checked == true, "the box set back again")
    -- the enabled.txt rename failing puts mods.txt back
    W.files[MODS .. "\\ModManagerDep\\enabled.txt"] = ""
    U.open.main = nil; U.entries[1].onClick()
    dep = rowOf(U, "Mod Manager Dep")
    W.failRename = "enabled%.txt$"
    U.toggle("r" .. dep .. ".tg")
    ok(W.files[TXT] == TXT0 and W.files[MODS .. "\\ModManagerDep\\enabled.txt"] == "", "enabled.txt rename failed: mods.txt put back, enabled.txt stays")
    ok(U.byId["r" .. dep .. ".tg"].checked == true, "the box set back")
    -- the rename fails and putting mods.txt back fails too: the WARN says so
    W.failRename = "enabled%.txt$"
    W.failWrite, W.failWriteSkip = "mods%.txt%.mm%-tmp$", 1 -- the toggle's own write passes, the rollback's fails
    U.toggle("r" .. dep .. ".tg")
    eq(#lines("^%[ModManager%] WARN could not turn ModManagerDep off: renaming enabled%.txt: .*; mods%.txt could not be put back %(writing mods%.txt%.mm%-tmp: .*%)$"), 1,
        "rollback failed: the WARN names mods.txt not put back")
    ok(U.byId["r" .. dep .. ".tg"].checked == true and U.byId.msg.text == "COULD NOT SAVE THE CHANGE", "the box set back, the message shown")
    W.files[TXT] = TXT0 -- (the failed rollback left Dep's 0 in place; back to the start for the next step)
    -- the next success clears the message
    U.toggle("r" .. dep .. ".tg")
    ok(not U.byId.msg.visible, "a success clears the message line")
    eq(#badWrites(), 0, "writes only to the allowed paths")
    restore()
end

do -- Crash between renames: mods.txt missing, .mm-bak present at start: restored before the first scan.
    boot{ files = { [TXT] = false, [TXT .. ".mm-bak"] = TXT0, [STATE .. ".mm-bak"] = '{"version":1,"off":["X"],"seen":[]}' } }
    local core = newCore()
    connect(core)
    eq(W.files[TXT], TXT0, "mods.txt restored from its .mm-bak")
    eq(W.files[TXT .. ".mm-bak"], nil, "no .mm-bak left")
    eq(W.files[STATE], '{"version":1,"off":["X"],"seen":[]}', "state.json restored too")
    eq(#lines("^%[ModManager%] RESTORED mods%.txt from mods%.txt%.mm%-bak$"), 1, "logged")
    core.ui.entries[1].onClick()
    eq(core.ui.byId["r" .. rowOf(core.ui, "Mod Manager Dep") .. ".tg"].checked, true, "the scan read the restored file")
    restore()
end

do -- Locked and pak rows: nothing changes, no file changes.
    local core, U = session()
    ok(U.byId["r1.on"].visible and not U.byId["r1.tg"].visible, "Nucleus: the lock, no box")
    local pak = rowOf(U, "ModManagerPak")
    eq(U.byId["r" .. pak .. ".tg"].enabled, false, "the pak row's box disabled")
    eq(U.toggle("r" .. pak .. ".tg"), false, "a click on it does nothing")
    U.toggle("r1.tg") -- hidden: refused by the fake as by core
    eq(#W.writes, 0, "no file changes")
    -- a callback reaching main.lua for a fixed row anyway: set back, nothing written
    U.byId["r" .. pak .. ".tg"].checked = false
    U.byId["r" .. pak .. ".tg"].onChange(U.byId["r" .. pak .. ".tg"].handle, false)
    ok(U.byId["r" .. pak .. ".tg"].checked == true and #W.writes == 0, "a stray callback on a fixed row: back on, nothing written")
    restore()
end

-- ---------------------------------------------------------------- the alert
do -- Nucleus made for another game: the alert once; not again once seen holds the key.
    boot()
    W.files[MODS .. "\\Nucleus\\mod.json"] = MJ.Nucleus:gsub("V8%.2%.3", "V8.1.0"):gsub("26601774", "26000000")
    local core = newCore()
    connect(core)
    W.footer = "NUCLEAR NIGHTMARE EA V8.2.3"
    core.ui.entries[1].onClick()
    eq(#lines("^%[ModManager%] ALERT nucleus%-build$"), 1, "ALERT nucleus-build")
    ok(core.ui.open.alert and core.ui.byId["alert.text"].text == "NUCLEUS 0.12.1 WAS MADE FOR GAME V8.1.0 (BUILD 26000000). THIS GAME IS V8.2.3 (BUILD -). MODS MAY NOT WORK UNTIL NUCLEUS IS UPDATED.", "the alert's text", core.ui.byId["alert.text"] and core.ui.byId["alert.text"].text)
    eq(W.files[STATE], '{"version":1,"off":[],"seen":["nucleus-build 0.12.1 V8.2.3"]}', "the key in seen")
    core.ui.back("alert"); core.ui.open.main = nil
    core.ui.entries[1].onClick()
    eq(#lines("ALERT"), 1, "not again this session")
    restore()
    -- an alert window that can't open: nothing recorded, so the next open shows it
    boot()
    W.files[MODS .. "\\Nucleus\\mod.json"] = MJ.Nucleus:gsub("V8%.2%.3", "V8.1.0"):gsub("26601774", "26000000")
    core = newCore()
    connect(core)
    local realOpenW = core.ui.screen.open
    core.ui.screen.open = function(o) if o.id == "alert" then error("boom alert") end return realOpenW(o) end
    core.ui.entries[1].onClick()
    ok(#lines("ALERT") == 0 and W.files[STATE] == nil, "the alert failed to open: no ALERT line, no key saved")
    core.ui.screen.open = realOpenW
    core.ui.open.main = nil
    core.ui.entries[1].onClick()
    ok(#lines("ALERT nucleus%-build") == 1 and core.ui.open.alert, "the next open shows it")
    restore()
    -- a new session with the same state: no alert
    boot{ files = { [STATE] = '{"version":1,"off":[],"seen":["nucleus-build 0.12.1 V8.2.3"]}' } }
    W.files[MODS .. "\\Nucleus\\mod.json"] = MJ.Nucleus:gsub("V8%.2%.3", "V8.1.0"):gsub("26601774", "26000000")
    core = newCore()
    connect(core)
    core.ui.entries[1].onClick()
    eq(#lines("ALERT"), 0, "seen: no alert in a new session")
    ok(not core.ui.open.alert, "no alert window")
    -- another running version: a new key, the alert again
    W.footer = "NUCLEAR NIGHTMARE EA V8.3.0"
    core.ui.open.main = nil
    core.ui.entries[1].onClick()
    eq(#lines("ALERT"), 1, "another running game: a new key, one alert")
    restore()
end

do -- The running build from Steam's appmanifest two folders above the install folder.
    boot()
    -- the game folder C:\nn\copy\NuclearNightmare: install folder C:\nn\copy, two folders above it C:\ (steamapps)
    W.files["C:\\appmanifest_2909110.acf"] = '"AppState"\n{\n\t"appid"\t\t"2909110"\n\t"buildid"\t\t"26601774"\n}\n'
    local core = newCore()
    connect(core)
    core.ui.entries[1].onClick()
    eq(#lines("OPEN rows=%d+ total=%d+ lang=en game=V8%.2%.3 build=26601774 "), 1, "build read from the manifest")
    eq(#lines("STATUS ModManagerFixture build,dep | MADE FOR GAME V0%.0%.0 %(BUILD 1%)%. THIS GAME: V8%.2%.3 %(BUILD 26601774%)"), 1, "the build compare uses it")
    restore()
    boot()
    W.menuUp = false
    core = newCore()
    connect(core)
    core.ui.entries[1].onClick()
    eq(#lines("OPEN rows=%d+ total=%d+ lang=en game=%- build=%- "), 1, "no live menu: the version unknown")
    eq(#lines("STATUS ModManagerFixture dep | "), 1, "unknown running game: no build icon")
    restore()
end

-- ---------------------------------------------------------------- settings
do -- Configure's controls; SET; a refusal; a raise; a restart setting.
    local core, U = session()
    local fx = rowOf(U, "ModManagerFixture")
    U.byId["r" .. fx .. ".cfg"].onClick()
    ok(U.byId["s1.cb"].visible and U.byId["s2.sl"].visible and U.byId["s3.ch"].visible and U.byId["s4.cb"].visible and U.byId["s5.ro"].visible, "bool, int, enum, restart bool, source")
    eq(U.byId["s5.ro"].text, "SET BY PRESETS", "SET BY PRESETS")
    U.toggle("s1.cb")
    eq(#lines("^%[ModManager%] SET ModManagerFixture flag=true$"), 1, "SET ModManagerFixture flag=true")
    eq(core.settings.sets[1].value, true, "setFor(ModManagerFixture, flag, true)")
    U.pick("s3.ch", 2)
    eq(#lines("^%[ModManager%] SET ModManagerFixture mode=two$"), 1, "SET mode=two")
    U.slide("s2.sl", 7)
    eq(#lines("^%[ModManager%] SET ModManagerFixture example=7$"), 1, "SET example=7")
    -- refused: the control back, NOT SAVED (write-failed), one WARN
    core.settings.refuse = "write-failed disk full"
    U.slide("s2.sl", 3)
    eq(U.byId["s2.sl"].value, 7, "refused: the slider back")
    ok(U.byId["cfg.msg"].visible and U.byId["cfg.msg"].text == "NOT SAVED (write-failed)", "NOT SAVED (write-failed)")
    eq(#lines("^%[ModManager%] WARN SET ModManagerFixture example not saved: write%-failed disk full$"), 1, "one WARN")
    core.settings.raise = "nucleus.settings.setFor: bad value: must be from 1 to 9"
    U.toggle("s1.cb")
    ok(U.byId["s1.cb"].checked == true and U.byId["cfg.msg"].text == "NOT SAVED (error)", "a raise: the box back, NOT SAVED (error)")
    -- the restart setting: its row gets the restart icon, the banner shows
    U.toggle("s4.cb")
    eq(#lines("^%[ModManager%] SET ModManagerFixture later=true$"), 1, "SET later=true")
    ok(not U.byId["cfg.msg"].visible, "a success clears the message")
    fx = rowOf(U, "ModManagerFixture")
    eq(icons(U, fx), "warning,warning,restart", "the fixture: build, dependency, restart")
    eq(U.byId["r" .. fx .. ".s3"].tooltip, "A SETTING APPLIES AFTER A RESTART", "its tooltip")
    ok(U.byId.banner.visible and U.byId.quit.visible, "banner and QUIT GAME")
    ok(U.byId["cfg.p4"].visible and U.byId["cfg.p4"].text == "A SETTING APPLIES AFTER A RESTART", "Configure's problem lines refreshed")
    ok(not U.byId["s4.rs"].dimmed, "the restart mark undimmed")
    -- a later open still sees it pending (describe at the open)
    U.back("configure"); U.open.main = nil; U.entries[1].onClick()
    eq(icons(U, rowOf(U, "ModManagerFixture")), "warning,warning,restart", "pending after reopening")
    eq(#W.writes, 0, "settings never write a file of the Mod Manager's own (only through core.settings)")
    restore()
end

-- ---------------------------------------------------------------- state.json
do -- Corrupt state.json: empty, one WARN; rewritten on the next save.
    local core, U = session{ files = { [STATE] = '{"off":' } }
    eq(#lines("^%[ModManager%] WARN Mods/ModManager/state%.json is not valid"), 1, "corrupt: one WARN")
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    eq(W.files[STATE], '{"version":1,"off":["ModManagerDep"],"seen":[]}', "rewritten on the next save")
    restore()
end
do -- A state.json that can't be saved: one WARN, the toggle stands (mods.txt is the truth).
    local core, U = session()
    W.failWrite = "state%.json%.mm%-tmp$"
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    eq(W.files[TXT], TXT0:gsub("ModManagerDep : 1", "ModManagerDep : 0"), "mods.txt written")
    eq(#lines("^%[ModManager%] WARN Mods/ModManager/state%.json could not be saved"), 1, "one WARN")
    eq(#lines("TOGGLE ModManagerDep off"), 1, "TOGGLE logged")
    restore()
end

-- ---------------------------------------------------------------- Quit
do -- Pending, QUIT GAME: QUIT pending=<n>, QuitGame once with a fresh PlayerController.
    local core, U = session()
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    local finds = W.finds
    U.byId.quit.onClick()
    eq(#lines("^%[ModManager%] QUIT pending=1$"), 1, "QUIT pending=1")
    eq(#W.quits, 1, "QuitGame called once")
    ok(W.quits[1][1] == "world" and W.quits[1][3] == 0 and W.quits[1][4] == false, "QuitGame(world, pc, 0 (Quit), false)")
    ok(W.finds > finds, "the PlayerController found fresh")
    restore()
end
do -- A QuitGame that raises: no QUIT line, one WARN.
    local core, U = session()
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    local realSFO = StaticFindObject
    StaticFindObject = function(p) if p:find("KismetSystemLibrary", 1, true) then return { IsValid = function() return true end, QuitGame = function() error("boom quit") end } end return realSFO(p) end
    U.byId.quit.onClick()
    eq(#lines("QUIT pending"), 0, "a failed quit logs no QUIT line")
    eq(#lines("^%[ModManager%] WARN QUIT GAME failed: .*boom quit"), 1, "one WARN")
    restore()
end

do -- The game folder can't be read: one WARN, an empty list, the window still opens; a toggle can't be saved.
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

do -- The sources: no shell, no load of data; writes only through the adapter's three primitives.
    for _, f in ipairs({ "main", "screen", "status", "modstxt", "files", "state", "json", "strings" }) do
        local src = assert(realOpen(ROOT .. "/Scripts/" .. f .. ".lua", "rb")):read("a"):gsub("%-%-[^\n]*", "")
        ok(not src:find("popen") and not src:find("os%.execute") and not src:find("loadfile") and not src:find("[^%w_%.:]load%(")
            and not src:find("os%.rename") and not src:find("os%.remove") and not src:find('"wb"') and not src:find('"w"'),
            f .. ".lua: no shell, no load, no direct file write")
    end
end

io.stdout:write(("main_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
