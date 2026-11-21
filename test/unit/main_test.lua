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
    -- runs at once here (the game runs it on the next game-thread tick); counted. W.queue (a table): queued instead, run
    -- by drain(), as the game would on its next tick (story 11).
    ExecuteInGameThreadWithDelay = function(ms, fn)
        W.delayed = W.delayed + 1
        if W.queue then W.queue[#W.queue + 1] = fn else fn() end
    end
end
-- The game's next tick: runs what was queued (and what that queues), in order.
local function drain()
    while W.queue and #W.queue > 0 do table.remove(W.queue, 1)() end
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
    for f, j in pairs(opts.mods or {}) do W.folders[f] = { "mod.json" }; W.files[MODS .. "\\" .. f .. "\\mod.json"] = j end -- v2 story 6
    for k, v in pairs(opts.files or {}) do W.files[k] = v or nil end
    for _, m in ipairs({ "nucleus.client", "json", "nucleus.modid", "nucleus.semver", "nucleus.json", "inventory", "strings", "screen", "status", "modstxt", "files", "state", "catalog", "browse" }) do package.loaded[m] = nil end
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
    -- v2 story 4: a core.catalog that is always busy (no job, no scan, nothing logged but one INFO line), so the
    -- earlier stories' tests see what they saw before; o.catalog = false: none; the Browse tests set their own.
    if o.catalog ~= false then core.catalog = o.catalog or { refresh = function() return nil, "busy" end, poll = function() return nil, "unknown job" end,
        stage = function() return nil, "busy" end, unstage = function() return nil, "busy" end } end
    return core
end
-- Story 8: core.restart. o.mode: what mode() answers ("direct" by default; false: nil, "unsupported launch");
-- o.starts: the answers start() gives in turn ({ { true } } by default; { false, why } for nil, why; { "raise" }).
local function fakeRestart(core, o)
    o = o or {}
    local R = { calls = { mode = 0, start = 0 }, starts = o.starts or { { true } } }
    core.restart = {
        mode = function() R.calls.mode = R.calls.mode + 1 if o.mode == false then return nil, "unsupported launch" end return o.mode or "direct" end,
        start = function()
            R.calls.start = R.calls.start + 1
            local a = R.starts[math.min(R.calls.start, #R.starts)]
            if a[1] == "raise" then error("boom start") end
            if a[1] == true then return true end
            return nil, a[2]
        end,
    }
    return R
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
do -- Nucleus present: connect{ mod = "ModManager", need = ">=0.27.0" }, nothing logged before it answers.
    boot()
    eq(#W.connects, 1, "connect called once")
    local c = W.connects[1]
    ok(c.mod == "ModManager" and c.need == ">=0.27.0", "connect{ mod = 'ModManager', need = '>=0.27.0' }", tostring(c.mod) .. " " .. tostring(c.need))
    eq(#W.printed, 0, "nothing printed during main.lua")
    c.onFail("Nucleus 0.20.0 is older than ModManager needs (>=0.27.0). Update Nucleus.")
    eq(#W.printed, 0, "onFail adds no line (connect's is the only one)")
    eq(W.iterations, 0, "onFail scans nothing")
    eq(#W.writes, 0, "onFail writes nothing")
    restore()
end
do -- mod.json and main.lua agree on the need; 0.8.0 (v2 story 6: core.catalog.unstage needs Nucleus 0.27.0).
    local mj = assert(realOpen(ROOT .. "/mod.json", "rb")):read("a")
    ok(mj:find('"version": ">=0.27.0"', 1, true) and mj:find('"id": "nuclearnightmare-community.nucleus"', 1, true), "mod.json dependsOn nuclearnightmare-community.nucleus >=0.27.0")
    ok(mj:find('"version": "0.8.0"', 1, true), "mod.json version 0.8.0")
    local src = assert(realOpen(MAIN, "rb")):read("a")
    ok(src:find('local CORE, NEED, ME = "Nucleus", ">=0.27.0", "ModManager"', 1, true), "main.lua NEED = dependsOn")
end

-- ---------------------------------------------------------------- start
do -- No UI helpers: one ERROR line, no entry.
    boot()
    connect(newCore{ ui = false })
    eq(#lines("^%[ModManager%] ERROR Nucleus's UI helpers lack menu, screen, list, row, image, text, button, checkbox, choice, slider, textbox%. ModManager will not run%.$"), 1, "no core.ui: one ERROR line")
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
    eq(#lines("^%[ModManager%] READY entry=manage need=>=0%.27%.0$"), 1, "one READY line after onReady")
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

-- ---------------------------------------------------------------- story 11: no ui work inside core's hook
-- Core calls onChange / onClick inside a Blueprint hook; an asset load there (the first restart icon loads T_Restart)
-- stalls the engine. The work runs on the next tick (W.queue, drain()); the fake's hookCalls records any ui.* call
-- made while the hook flag is up.
local function hookNames(U) local r = {} for _, c in ipairs(U.hookCalls) do r[#r + 1] = c.name end return table.concat(r, ", ") end

do -- A toggle, queued: nothing on return; after the tick: ': 0', TOGGLE, STATUS, the restart icon.
    local core, U = session()
    W.queue = {}
    local dep = rowOf(U, "Mod Manager Dep")
    local calls, delayed = #U.calls, W.delayed
    U.toggle("r" .. dep .. ".tg")
    eq(W.files[TXT], TXT0, "queued toggle: mods.txt unchanged on return")
    eq(#lines("TOGGLE"), 0, "queued toggle: no TOGGLE on return")
    eq(#U.calls, calls, "queued toggle: no ui call on return")
    eq(W.delayed, delayed + 1, "queued toggle: one ExecuteInGameThreadWithDelay")
    drain()
    local off = TXT0:gsub("ModManagerDep : 1", "ModManagerDep : 0")
    eq(W.files[TXT], off, "after the tick: ': 0'")
    eq(#lines("^%[ModManager%] TOGGLE ModManagerDep off$"), 1, "after the tick: TOGGLE")
    eq(#lines("^%[ModManager%] STATUS ModManagerDep restart | "), 1, "after the tick: STATUS")
    eq(icons(U, rowOf(U, "Mod Manager Dep")), "restart", "after the tick: the restart icon")
    ok(U.byId.quit.visible and U.byId.banner.visible, "after the tick: banner and QUIT GAME")
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    eq(W.files[TXT], off, "back on, queued: nothing written on return")
    drain()
    eq(W.files[TXT], TXT0, "back on after the tick: the start's bytes")
    eq(#U.hookCalls, 0, "no ui call inside the hook", hookNames(U))
    eq(#lines("WARN"), 0, "no WARN")
    restore()
end

do -- The list changed before the tick: nothing written, box n shows its own row.
    local core, U = session()
    W.queue = {}
    local dep = rowOf(U, "Mod Manager Dep")
    U.toggle("r" .. dep .. ".tg")
    W.folders.AaaFirst = {} -- sorts first: every mod row after the fixed two moves down one
    U.open.main = nil; U.entries[1].onClick()
    ok(rowOf(U, "Mod Manager Dep") ~= dep, "Dep moved")
    local other = U.byId["r" .. dep .. ".name"].text
    U.byId["r" .. dep .. ".tg"].checked = false -- as a click would have left it
    drain()
    eq(W.files[TXT], TXT0, "list changed: nothing written")
    eq(#lines("TOGGLE"), 0, "list changed: no TOGGLE")
    eq(U.byId["r" .. dep .. ".tg"].checked, true, "box n = its own row's state (" .. tostring(other) .. ", on)")
    eq(#lines("WARN"), 0, "no WARN")
    restore()
end

do -- The deferred body throws: box back, COULD NOT SAVE THE CHANGE, one WARN.
    local core, U = session()
    W.queue = {}
    local Status = package.loaded.status
    local realIsOn = Status.isOn
    Status.isOn = function() error("boom isOn") end
    local dep = rowOf(U, "Mod Manager Dep")
    U.toggle("r" .. dep .. ".tg")
    drain()
    Status.isOn = realIsOn
    eq(U.byId["r" .. dep .. ".tg"].checked, true, "a throw: the box back")
    ok(U.byId.msg.visible and U.byId.msg.text == "COULD NOT SAVE THE CHANGE", "a throw: COULD NOT SAVE THE CHANGE")
    eq(#lines("^%[ModManager%] WARN the toggle failed: .*boom isOn"), 1, "one WARN 'the toggle failed'")
    eq(#lines("WARN"), 1, "only that WARN")
    eq(W.files[TXT], TXT0, "nothing written")
    restore()
end

do -- No scheduler, or one that raises: the work runs inline (as 0.2.0).
    local core, U = session()
    ExecuteInGameThreadWithDelay = nil
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    eq(W.files[TXT], (TXT0:gsub("ModManagerDep : 1", "ModManagerDep : 0")), "no scheduler: written at once")
    ExecuteInGameThreadWithDelay = function() error("boom scheduler") end
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    eq(W.files[TXT], TXT0, "a raising scheduler: written at once")
    eq(#lines("TOGGLE"), 2, "both toggles logged")
    eq(#lines("WARN"), 0, "no WARN")
    restore()
end

do -- A setting with no scheduler, or one that raises: saved inline.
    local core, U = session()
    U.click("r" .. rowOf(U, "ModManagerFixture") .. ".cfg")
    ok(U.open.configure, "Configure open")
    ExecuteInGameThreadWithDelay = nil
    U.toggle("s1.cb")
    eq(#core.settings.sets, 1, "no scheduler: setFor at once")
    eq(#lines("^%[ModManager%] SET ModManagerFixture flag=true$"), 1, "no scheduler: SET at once")
    ExecuteInGameThreadWithDelay = function() error("boom scheduler") end
    U.toggle("s1.cb")
    eq(#core.settings.sets, 2, "a raising scheduler: setFor at once")
    eq(#lines("^%[ModManager%] SET ModManagerFixture flag=false$"), 1, "a raising scheduler: SET at once")
    eq(#lines("WARN"), 0, "no WARN")
    restore()
end

do -- TURN OFF with no scheduler, or one that raises: written inline.
    for _, sched in ipairs({ "nil", "raises" }) do
        local core, U = session()
        local base = rowOf(U, "Mod Manager Base")
        U.toggle("r" .. base .. ".tg")
        ok(U.open.confirm, sched .. ": the confirm")
        if sched == "nil" then ExecuteInGameThreadWithDelay = nil else ExecuteInGameThreadWithDelay = function() error("boom scheduler") end end
        U.click("confirm.ok")
        eq(W.files[TXT], (TXT0:gsub("ModManagerBase : 1", "ModManagerBase : 0")), sched .. " scheduler: TURN OFF written at once")
        ok(not U.open.confirm, sched .. " scheduler: the confirm closed")
        eq(#lines("^%[ModManager%] TOGGLE ModManagerBase off$"), 1, sched .. " scheduler: TOGGLE")
        eq(#lines("WARN"), 0, sched .. " scheduler: no WARN")
        restore()
    end
end

do -- Settings: queued; Configure changed before the tick; a throw after the save.
    -- (Base declares a setting too, so its Configure has a different key at index 1)
    boot{ files = { [MODS .. "\\ModManagerBase\\mod.json"] = (MJ.ModManagerBase:gsub('}$', ',"settings":{"other":{}}}')) } }
    local core = newCore()
    core.settings.decls.ModManagerBase = { settings = { { key = "other", type = "bool", value = true, default = true, label = "Other", changeable = "anytime" } } }
    connect(core)
    core.ui.entries[1].onClick()
    local U = core.ui
    W.queue = {}
    local fx = rowOf(U, "ModManagerFixture")
    U.click("r" .. fx .. ".cfg")
    eq(U.open.configure, nil, "the gear: queued too")
    drain()
    ok(U.open.configure and U.byId["s1.cb"].visible, "Configure open after the tick")
    U.toggle("s1.cb")
    eq(#core.settings.sets, 0, "queued setting: no setFor on return")
    eq(#lines("SET "), 0, "queued setting: no SET on return")
    drain()
    eq(#lines("^%[ModManager%] SET ModManagerFixture flag=true$"), 1, "after the tick: SET")
    -- Configure changed (another mod's) before the tick: nothing saved, control 1 shows its own entry's value
    U.toggle("s1.cb")
    local q = W.queue -- (the setting's work stays queued while Base's Configure opens at once)
    W.queue = nil; U.byId["r" .. rowOf(U, "Mod Manager Base") .. ".cfg"].onClick(); W.queue = q
    eq(U.byId["s1.cb"].checked, true, "Base's Configure: control 1 is Base's 'other' (true)")
    U.byId["s1.cb"].checked = false -- as if the click had left it so
    drain()
    eq(#core.settings.sets, 1, "Configure changed: no setFor")
    eq(#lines("SET "), 1, "Configure changed: no new SET line")
    eq(U.byId["s1.cb"].checked, true, "Configure changed: control 1 shows its own entry's value")
    -- back on the fixture; describe breaks after the save: the value stands, guard's WARN only
    W.queue = nil; U.byId["r" .. fx .. ".cfg"].onClick(); W.queue = {}
    eq(U.byId["s1.cb"].checked, true, "the fixture's flag still true")
    core.settings.describe = function() return setmetatable({}, { __index = function() error("boom describe") end }) end
    U.toggle("s1.cb")
    drain()
    eq(#lines("^%[ModManager%] SET ModManagerFixture flag=false$"), 1, "saved before the throw")
    eq(#lines("^%[ModManager%] WARN the setting failed: .*boom describe"), 1, "one WARN 'the setting failed'")
    eq(U.byId["s1.cb"].checked, false, "the value kept (not set back)")
    ok(not (U.byId["cfg.msg"].visible and tostring(U.byId["cfg.msg"].text):find("NOT SAVED")), "no NOT SAVED")
    eq(#lines("WARN"), 1, "only that WARN")
    eq(#U.hookCalls, 0, "no ui call inside the hook", hookNames(U))
    restore()
end

do -- A setting's deferred body throws before the save succeeded: the control back, NOT SAVED (error), guard's WARN.
    local core, U = session()
    W.queue = {}
    U.click("r" .. rowOf(U, "ModManagerFixture") .. ".cfg"); drain()
    U.slide("s2.sl", 5)
    core.settings.refuse = "write-failed disk full"
    local realSet = U.text.set
    U.text.set = function() U.text.set = realSet error("boom text") end -- the refusal's message raises once
    drain()
    eq(U.byId["s2.sl"].value, 1, "a throw before the save: the slider back")
    eq(U.byId["cfg.msg"].text, "NOT SAVED (error)", "NOT SAVED (error)")
    eq(#lines("^%[ModManager%] WARN the setting failed: .*boom text"), 1, "one WARN 'the setting failed'")
    restore()
end

do -- TURN OFF: queued; BACK before the tick cancels; a throw sets the box back.
    local core, U = session()
    W.queue = {}
    local base = rowOf(U, "Mod Manager Base")
    U.toggle("r" .. base .. ".tg"); drain()
    ok(U.open.confirm, "the confirm (after the tick)")
    U.click("confirm.ok")
    eq(W.files[TXT], TXT0, "TURN OFF queued: nothing written on return")
    ok(U.open.confirm, "TURN OFF queued: the confirm still open on return")
    drain()
    eq(W.files[TXT], (TXT0:gsub("ModManagerBase : 1", "ModManagerBase : 0")), "TURN OFF after the tick: ': 0'")
    ok(not U.open.confirm, "the confirm closed")
    eq(#U.hookCalls, 0, "no ui call inside the hook", hookNames(U))
    restore()

    core, U = session()
    W.queue = {}
    base = rowOf(U, "Mod Manager Base")
    U.toggle("r" .. base .. ".tg"); drain()
    U.click("confirm.ok")
    U.back("confirm")
    drain()
    eq(W.files[TXT], TXT0, "BACK before the tick: nothing written")
    eq(U.byId["r" .. base .. ".tg"].checked, true, "BACK before the tick: the box on")
    eq(#lines("TOGGLE"), 0, "no TOGGLE")
    restore()

    core, U = session()
    W.queue = {}
    base = rowOf(U, "Mod Manager Base")
    U.toggle("r" .. base .. ".tg"); drain()
    local realClose = U.screen.close
    U.screen.close = function() U.screen.close = realClose error("boom close") end
    U.click("confirm.ok")
    drain()
    eq(U.byId["r" .. base .. ".tg"].checked, true, "TURN OFF throws: the box back on")
    ok(U.byId.msg.visible and U.byId.msg.text == "COULD NOT SAVE THE CHANGE", "TURN OFF throws: COULD NOT SAVE THE CHANGE")
    eq(#lines("^%[ModManager%] WARN TURN OFF failed: .*boom close"), 1, "one WARN 'TURN OFF failed'")
    eq(W.files[TXT], TXT0, "nothing written")
    restore()
end

do -- The guard: every toggle, pick, slide and click with the queue on makes no ui call inside the hook.
    local core, U = session()
    W.queue = {}
    local function step(f) f(); drain() end
    step(function() U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg") end)   -- off: the first restart icon
    step(function() U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg") end)   -- on
    step(function() U.toggle("r" .. rowOf(U, "Mod Manager Base") .. ".tg") end)  -- the confirm
    step(function() U.click("confirm.ok") end)                                    -- TURN OFF
    step(function() U.toggle("r" .. rowOf(U, "Mod Manager Base") .. ".tg") end)  -- back on
    step(function() U.click("r1.cfg") end)                                        -- a gear
    step(function() U.click("r" .. rowOf(U, "ModManagerFixture") .. ".cfg") end)
    step(function() U.toggle("s1.cb") end)
    step(function() U.pick("s3.ch", 3) end)
    step(function() U.slide("s2.sl", 4) end)
    step(function() U.toggle("s4.cb") end)                                        -- a restart setting
    eq(#lines("TOGGLE"), 4, "the toggles ran")
    eq(#lines("SET "), 4, "the settings ran")
    eq(#U.hookCalls, 0, "no ui call inside the hook", hookNames(U))
    eq(#lines("WARN"), 0, "no WARN")
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

-- ---------------------------------------------------------------- Restart now (story 8)
local function restartSession(o)
    boot()
    local core = newCore()
    local R = o ~= false and fakeRestart(core, o) or nil
    connect(core)
    core.ui.entries[1].onClick()
    return core, core.ui, R
end
do -- Nothing pending: RESTART NOW made, hidden; mode asked once per session, logged.
    local core, U, R = restartSession()
    ok(U.byId.restart and U.byId.restart.kind == "button" and U.byId.restart.label == "RESTART NOW", "RESTART NOW made")
    ok(not U.byId.restart.visible, "nothing pending: RESTART NOW hidden")
    eq(#lines("^%[ModManager%] RESTARTMODE direct$"), 1, "RESTARTMODE direct")
    core.ui.open.main = nil
    core.ui.entries[1].onClick()
    eq(R.calls.mode, 1, "mode asked once per session")
    restore()
end
do -- Pending, mode direct: RESTART NOW beside QUIT GAME; a click starts the helper, logs RESTART, quits.
    local core, U, R = restartSession()
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    ok(U.byId.restart.visible and U.byId.quit.visible, "pending: RESTART NOW and QUIT GAME shown")
    U.byId.restart.onClick()
    eq(R.calls.start, 1, "start called once")
    eq(#lines("^%[ModManager%] RESTART mode=direct pending=1$"), 1, "RESTART mode=direct pending=1")
    eq(#W.quits, 1, "QuitGame called once (the QUIT GAME path)")
    ok(W.quits[1] and W.quits[1][1] == "world" and W.quits[1][3] == 0 and W.quits[1][4] == false, "QuitGame(world, pc, 0 (Quit), false)")
    eq(#lines("QUIT pending"), 0, "no QUIT line for a restart")
    eq(#lines("WARN"), 0, "no WARN")
    restore()
end
do -- "already started" (a helper is already waiting): still RESTART and the quit; steam mode is logged as such.
    local core, U, R = restartSession{ mode = "steam", starts = { { false, "already started" } } }
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    U.byId.restart.onClick()
    eq(#lines("^%[ModManager%] RESTART mode=steam pending=1$"), 1, "already started: RESTART mode=steam pending=1")
    eq(#W.quits, 1, "already started: QuitGame called")
    restore()
end
for _, why in ipairs({ "helper missing", "start failed: 5", "unsupported launch", "command line too long", "native part missing" }) do
    -- Any other answer: no quit, the message line, one WARN per reason (a second click adds none).
    local core, U, R = restartSession{ starts = { { false, why } } }
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    U.byId.restart.onClick()
    U.byId.restart.onClick()
    eq(#W.quits, 0, why .. ": no quit")
    eq(#lines("RESTART mode"), 0, why .. ": no RESTART line")
    ok(U.byId.msg.visible and U.byId.msg.text == "CAN'T RESTART: USE QUIT GAME AND START THE GAME AGAIN.", why .. ": the message line", U.byId.msg.text)
    eq(#lines("^%[ModManager%] WARN RESTART NOW could not restart the game %(" .. why:gsub("%p", "%%%0") .. "%); the game keeps running$"), 1, why .. ": one WARN")
    ok(U.byId.restart.visible and U.byId.quit.visible, why .. ": both buttons stay")
    U.byId.quit.onClick()
    eq(#W.quits, 1, why .. ": QUIT GAME still works")
    restore()
end
do -- start() raising: no quit, the message line, one WARN.
    local core, U, R = restartSession{ starts = { { "raise" } } }
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    U.byId.restart.onClick()
    eq(#W.quits, 0, "raise: no quit")
    eq(#lines("^%[ModManager%] WARN RESTART NOW could not restart the game %(.*boom start.*%)"), 1, "raise: one WARN")
    ok(U.byId.msg.visible, "raise: the message line")
    restore()
end
do -- Neither a manifest nor steam_appid.txt (mode nil): RESTART NOW absent while pending, QUIT GAME works (AC 3).
    local core, U, R = restartSession{ mode = false }
    eq(#lines("^%[ModManager%] RESTARTMODE none %(unsupported launch%)$"), 1, "RESTARTMODE none (unsupported launch)")
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    ok(U.byId.quit.visible and U.byId.banner.visible, "pending: QUIT GAME and the banner")
    ok(not U.byId.restart.visible, "mode nil: RESTART NOW absent")
    U.byId.quit.onClick()
    eq(#W.quits, 1, "mode nil: QUIT GAME quits")
    eq(#lines("^%[ModManager%] QUIT pending=1$"), 1, "mode nil: QUIT pending=1")
    eq(R.calls.start, 0, "mode nil: start never called")
    restore()
end
do -- An older core without core.restart: no RESTART NOW, QUIT GAME as before.
    local core, U = restartSession(false)
    eq(#lines("^%[ModManager%] RESTARTMODE none %(Nucleus has no core%.restart%)$"), 1, "no core.restart: RESTARTMODE none")
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    ok(U.byId.quit.visible and not U.byId.restart.visible, "no core.restart: QUIT GAME only")
    restore()
end
do -- mode() raising: treated as none.
    boot()
    local core = newCore()
    core.restart = { mode = function() error("boom mode") end, start = function() return true end }
    connect(core)
    core.ui.entries[1].onClick()
    local U = core.ui
    U.toggle("r" .. rowOf(U, "Mod Manager Dep") .. ".tg")
    ok(not U.byId.restart.visible, "mode raising: RESTART NOW absent")
    eq(#lines("^%[ModManager%] RESTARTMODE none %(.*boom mode"), 1, "mode raising: RESTARTMODE none (...)")
    restore()
end

-- ---------------------------------------------------------------- staged changes (v2 story 3)
-- core.apply: o.status is what status() answers (staged/result/...; a start() that succeeds turns pending or interrupted
-- into waiting); o.start: start()'s answer ({ true } by default, { false, why }, { "raise" }); o.statusRaises.
local TXN = "0123456789abcdef0123456789abcdef"
local function fakeApply(core, o)
    o = o or {}
    local A = { calls = { status = 0, start = 0, ack = 0 }, acked = {}, st = { staged = "none", result = "none", txn = "", reason = "", path = "", attempts = 0, changes = 0 } }
    for k, v in pairs(o.status or {}) do A.st[k] = v end
    core.apply = {
        status = function()
            A.calls.status = A.calls.status + 1
            if o.statusRaises then error("boom status") end
            local c = {} for k, v in pairs(A.st) do c[k] = v end
            return c
        end,
        start = function()
            A.calls.start = A.calls.start + 1
            local a = o.start or { true }
            if a[1] == "raise" then error("boom apply") end
            if a[1] == true then A.st.staged = "waiting" return true end
            return nil, a[2]
        end,
        ack = function(txn)
            A.calls.ack = A.calls.ack + 1
            A.acked[#A.acked + 1] = txn
            if txn ~= A.st.txn then return nil, "txn mismatch" end
            A.st.result = "none"
            return true
        end,
    }
    return A
end
local function applySession(o, restart)
    boot()
    local core = newCore()
    fakeRestart(core, restart)
    local A = o ~= false and fakeApply(core, o) or nil
    connect(core)
    return core, core.ui, A
end
local function reopen(core) core.ui.open.main = nil core.ui.entries[1].onClick() end

do -- A change staged at launch, no helper: start() at onReady; one pending change: QUIT GAME, RESTART NOW, the banner (AC 3).
    local core, U, A = applySession{ status = { staged = "pending", txn = TXN, changes = 2 } }
    eq(A.calls.start, 1, "pending: start() once at onReady")
    eq(#lines("^%[ModManager%] APPLY status staged=pending result=none changes=2 attempts=0$"), 1, "APPLY status line")
    eq(#lines("^%[ModManager%] APPLY start ok$"), 1, "APPLY start ok")
    core.ui.entries[1].onClick()
    ok(U.byId.quit.visible and U.byId.restart.visible and U.byId.banner.visible, "staged: QUIT GAME, RESTART NOW and the banner show")
    eq(#lines("^%[ModManager%] APPLY staged waiting$"), 1, "the status re-read at the open: waiting")
    ok(not U.byId.msg.visible, "no result: no message")
    eq(A.calls.ack, 0, "no result: no ack")
    U.byId.restart.onClick()
    eq(#lines("^%[ModManager%] RESTART mode=direct pending=1$"), 1, "RESTART NOW: pending=1 (the staged change)")
    eq(#W.quits, 1, "RESTART NOW quits")
    eq(#badWrites(), 0, "nothing written outside the allowed paths")
    restore()
end
do -- Interrupted: start() too. waiting (a helper of this session already waits) and applying: no start, still pending.
    local core, U, A = applySession{ status = { staged = "interrupted", txn = TXN, changes = 1 } }
    eq(A.calls.start, 1, "interrupted: start() at onReady")
    restore()
    for _, st in ipairs({ "waiting", "applying" }) do
        core, U, A = applySession{ status = { staged = st, txn = TXN, changes = 1 } }
        eq(A.calls.start, 0, st .. ": no start()")
        core.ui.entries[1].onClick()
        ok(U.byId.quit.visible and U.byId.banner.visible, st .. ": pending (QUIT GAME, the banner)")
        restore()
    end
end
do -- start() refused or raising: logged, the change still counts as pending.
    for _, a in ipairs({ { { false, "helper missing" }, "helper missing" }, { { "raise" }, ".*boom apply" } }) do
        local core, U, A = applySession{ status = { staged = "pending", txn = TXN, changes = 1 }, start = a[1] }
        eq(#lines("^%[ModManager%] APPLY start " .. a[2]), 1, "APPLY start " .. a[2])
        core.ui.entries[1].onClick()
        ok(U.byId.quit.visible and U.byId.banner.visible, a[2] .. ": still pending")
        restore()
    end
end
do -- Nothing staged, no result: no start, nothing pending, no message.
    local core, U, A = applySession{}
    eq(A.calls.start, 0, "none: no start()")
    eq(#lines("^%[ModManager%] APPLY status staged=none result=none changes=0 attempts=0$"), 1, "none: the APPLY status line")
    core.ui.entries[1].onClick()
    ok(not U.byId.quit.visible and not U.byId.restart.visible and not U.byId.banner.visible and not U.byId.msg.visible, "none: no button, banner or message")
    restore()
end
for _, c in ipairs({
    { result = "applied", reason = "", path = "", staged = "none", msg = "THE STAGED CHANGE WAS APPLIED.", line = "APPLY result applied reason=%- path=%- attempts=1$" },
    { result = "failed", reason = "locked", path = "NuclearNightmare\\Content\\Paks\\A_P.pak", staged = "pending",
        msg = "A STAGED CHANGE COULD NOT BE APPLIED (NuclearNightmare\\Content\\Paks\\A_P.pak). IT IS TRIED AGAIN AT THE NEXT RESTART.",
        line = "APPLY result failed reason=locked path=NuclearNightmare\\Content\\Paks\\A_P%.pak attempts=1$" },
    { result = "failed", reason = "game-running", path = "", staged = "pending",
        msg = "A STAGED CHANGE COULD NOT BE APPLIED (game-running). IT IS TRIED AGAIN AT THE NEXT RESTART.", line = "APPLY result failed reason=game%-running path=%- attempts=1$" },
    { result = "discarded", reason = "staged-file-mismatch", path = "x", staged = "none", msg = "A STAGED CHANGE COULD NOT BE APPLIED AND WAS DROPPED.",
        line = "APPLY result discarded reason=staged%-file%-mismatch path=x attempts=1$" },
}) do -- A result: the message line on the first open only, then acked once with its txn (AC 3: the message appears once).
    local core, U, A = applySession{ status = { staged = c.staged, result = c.result, reason = c.reason, path = c.path, txn = TXN, attempts = 1, changes = c.staged == "none" and 0 or 1 } }
    eq(A.calls.ack, 0, c.result .. ": nothing acked before the window opens")
    core.ui.entries[1].onClick()
    ok(U.byId.msg.visible and U.byId.msg.text == c.msg, c.result .. ": the message line", U.byId.msg.text)
    eq(#lines("^%[ModManager%] " .. c.line), 1, c.result .. ": the APPLY result line")
    eq(A.calls.ack, 1, c.result .. ": acked once")
    eq(A.acked[1], TXN, c.result .. ": acked with its txn")
    eq(#lines("^%[ModManager%] APPLY ack ok$"), 1, c.result .. ": APPLY ack ok")
    ok((U.byId.quit.visible and U.byId.banner.visible) == (c.staged ~= "none"), c.result .. ": pending only while staged")
    reopen(core)
    ok(not U.byId.msg.visible, c.result .. ": no message on the next open")
    eq(A.calls.ack, 1, c.result .. ": not acked again")
    eq(#lines("APPLY result"), 1, c.result .. ": one APPLY result line")
    restore()
end
do -- An ack refused (another result came in between): logged; the message still showed once.
    local core, U, A = applySession{ status = { result = "applied", txn = TXN, attempts = 1 } }
    A.st.txn = ("f"):rep(32)
    core.ui.entries[1].onClick()
    eq(#lines("^%[ModManager%] APPLY ack txn mismatch$"), 1, "APPLY ack txn mismatch")
    reopen(core)
    eq(A.calls.ack, 1, "a refused ack is not retried in the session")
    restore()
end
do -- An older core without core.apply: one line, the rest as before.
    local core, U = applySession(false)
    eq(#lines("^%[ModManager%] APPLY none %(Nucleus has no core%.apply%)$"), 1, "no core.apply: APPLY none")
    core.ui.entries[1].onClick()
    ok(not U.byId.quit.visible and not U.byId.msg.visible, "no core.apply: nothing pending, no message")
    eq(#lines("WARN"), 0, "no core.apply: no WARN")
    restore()
end
do -- status() raising: one WARN per reason, nothing pending.
    local core, U, A = applySession{ statusRaises = true }
    core.ui.entries[1].onClick()
    reopen(core)
    eq(#lines("^%[ModManager%] WARN the staged change's status could not be read %(.*boom status.*%)$"), 1, "status raising: one WARN")
    ok(not U.byId.quit.visible, "status raising: nothing pending")
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
    for _, f in ipairs({ "main", "screen", "status", "modstxt", "files", "state", "json", "strings", "catalog", "browse" }) do
        local src = assert(realOpen(ROOT .. "/Scripts/" .. f .. ".lua", "rb")):read("a"):gsub("%-%-[^\n]*", "")
        ok(not src:find("popen") and not src:find("os%.execute") and not src:find("loadfile") and not src:find("[^%w_%.:]load%(")
            and not src:find("os%.rename") and not src:find("os%.remove") and not src:find('"wb"') and not src:find('"w"'),
            f .. ".lua: no shell, no load, no direct file write")
    end
end

-- ---------------------------------------------------------------- v2 story 4: the catalog and Browse
local POLLCAPS = { maxBytes = 9437184, maxDepth = 66, maxValues = 2000000, maxString = 4194304 } -- core.catalog.poll's
local function fixture(name)
    local t = assert(realOpen(ROOT .. "/test/unit/fixtures/" .. name, "rb")):read("a")
    return assert(require("nucleus.json").decode(t, POLLCAPS))
end
local NOW = 1795233548 -- 2026-11-21T03:59:08Z: the ok fixture's index is 3 hours old, its revoked list 21 days
local realTime = os.time
-- A fake core.catalog: refresh() gives jobs 1, 2, ... (or o.refresh(n)'s answer); poll(job) answers o.poll(n, job) for
-- the n-th poll.
local function fakeCatalog(o)
    local F = { refreshes = 0, polls = 0 }
    F.api = {
        refresh = function()
            F.refreshes = F.refreshes + 1
            if o.refresh then return o.refresh(F.refreshes) end
            return F.refreshes
        end,
        poll = function(job) F.polls = F.polls + 1 return o.poll(F.polls, job) end,
        -- v2 story 5: stage(list) answers o.stage(n, list) (a job 101, 102, ... by default)
        stage = function(list) F.stages = (F.stages or 0) + 1 F.staged = list if o.stage then return o.stage(F.stages, list) end return 100 + F.stages end,
        -- v2 story 6: unstage(id, version) answers o.unstage(n, id, version) (a job 201, 202, ... by default)
        unstage = function(id, version, ...)
            assert(select("#", ...) == 0 and type(id) == "string" and type(version) == "string", "unstage(id, version)")
            F.unstages = (F.unstages or 0) + 1 F.unstaged = { id = id, version = version }
            if o.unstage then return o.unstage(F.unstages, id, version) end
            return 200 + F.unstages
        end,
    }
    return F
end
local function done(outcome, payload, message) return function() return "done", { outcome = outcome, message = message or "", payload = payload } end end
-- One game-thread tick: what was queued before it (a poll, a deferred click) runs; what that queues waits.
local function tick() local q = W.queue W.queue = {} for _, f in ipairs(q) do f() end end
-- A session with a fake catalog; W.queue on (nothing scheduled runs until tick). Returns core, U, F.
local function browseSession(o)
    boot()
    if o.footer then W.footer = o.footer end
    W.queue = {}
    os.time = function() return NOW end
    local F = fakeCatalog(o)
    local core = newCore{ catalog = F.api }
    connect(core)
    return core, core.ui, F
end
local function openBrowse(core)
    local U = core.ui
    U.open.main, U.open.browse, U.open.details = nil, nil, nil
    U.order = {}
    U.entries[1].onClick()
    ok(U.click("browse"), "the main window has BROWSE")
    tick()
    return U
end
local function endSession() os.time = realTime restore() end
local function names(U)
    local t = {}
    for n = 1, 200 do
        local el = U.byId["bw.r" .. n]
        if not el then break end
        if el.visible then t[#t + 1] = U.byId["bw.r" .. n .. ".name"].text end
    end
    return table.concat(t, ",")
end

do -- Online: the startup refresh, polled every 250 ms from the game thread, then BROWSE.
    local core, U, F = browseSession{ poll = function(n) if n == 1 then return "running" end return done("ok", fixture("catalog-ok.json"), "index serial 2 verified")() end }
    eq(#lines("^%[ModManager%] CATALOG refresh job=1$"), 1, "online: the startup refresh")
    eq(F.polls, 0, "online: nothing polled inside onReady")
    eq(W.delayed, 1, "online: one poll scheduled")
    tick()
    eq(F.polls, 1, "online: first poll: running")
    eq(#lines("CATALOG done"), 0, "online: not done yet")
    tick()
    eq(#lines("^%[ModManager%] CATALOG done outcome=ok source=network packages=5 index_issued=2026%-11%-21T00:59:08Z$"), 1, "online: CATALOG done")
    eq(#lines("^%[ModManager%] BUILD 26601774 from=index$"), 1, "online: BUILD from the index (no appmanifest)")
    eq(#lines("^%[ModManager%] BROWSE pkg "), 5, "online: one BROWSE pkg line per package")
    eq(#lines("BROWSE pkg nuclearnightmare%-community%.base "), 0, "online: no base line")
    eq(#lines("BROWSE pkg nuclearnightmare%-community%.base%-installer"), 0, "online: no installer line")
    eq(#lines("^%[ModManager%] BROWSE pkg nuclearnightmare%-community%.hud%-clock v=0%.3%.0 cat=ui,qol scope=client state=available core=ok$"), 1, "online: HUD Clock's line")
    eq(#lines("^%[ModManager%] BROWSE pkg nuclearnightmare%-community%.mod%-manager v=0%.4%.0 cat=tools,ui scope=client state=update core=needs$"), 1, "online: Mod Manager (0.2.0 installed, core 0.12.1 < 0.21.0)")
    tick()
    eq(F.polls, 2, "online: the chain stopped at done")
    U = openBrowse(core)
    ok(U.open.browse, "online: Browse opens on top")
    eq(#lines("^%[ModManager%] BROWSE open shown=5 total=5 state=ok$"), 1, "online: BROWSE open")
    eq(#lines("^%[ModManager%] BROWSE filter cat=all show=all scope=all for=game q= shown=5 ids=nuclearnightmare%-community%.hud%-clock,nuclearnightmare%-community%.waypoints,nuclearnightmare%-community%.mod%-manager,nuclearnightmare%-community%.nucleus,nuclearnightmare%-community%.whistle%-mute$"), 1, "online: the filter line, sorted by name")
    eq(names(U), "HUD Clock,Map Waypoints+,Mod Manager,Nucleus (Mod Core),Whistle Emote Mute", "online: the rows")
    eq(U.byId["bw.age"].text, "CATALOG UPDATED 3 HOURS AGO - REVOCATIONS CHECKED 21 DAYS AGO", "online: the age line")
    ok(U.byId["bw.age"].visible and not U.byId["bw.status"].visible, "online: no status line")
    eq(U.byId["bw.count"].text, "5 OF 5 MODS", "online: the count line")
    -- a filter (inside core's hook: nothing done there), then after the hook
    local h0 = #U.hookCalls
    U.pick("bw.cat", 5) -- AUDIO
    eq(#U.hookCalls, h0, "a filter's change does no ui work inside the hook")
    tick()
    eq(#lines("^%[ModManager%] BROWSE filter cat=audio show=all scope=all for=game q= shown=1 ids=nuclearnightmare%-community%.whistle%-mute$"), 1, "CATEGORY audio")
    U.pick("bw.show", 2) -- INSTALLED
    tick()
    eq(#lines("^%[ModManager%] BROWSE filter cat=audio show=installed scope=all for=game q= shown=0 ids=%-$"), 1, "SHOW INSTALLED")
    eq(U.byId["bw.status"].text, "NO MODS MATCH", "no match: the status line says so")
    U.pick("bw.cat", 1); U.pick("bw.show", 3) -- ALL, NOT INSTALLED
    tick()
    eq(#lines("show=not%-installed .* shown=3 ids=nuclearnightmare%-community%.hud%-clock,nuclearnightmare%-community%.waypoints,nuclearnightmare%-community%.whistle%-mute$"), 1, "SHOW NOT INSTALLED")
    U.pick("bw.show", 1); U.pick("bw.for", 2) -- READY TO RUN: not Mod Manager (needs Nucleus 0.21.0)
    tick()
    eq(#lines("show=all scope=all for=ready q= shown=4 "), 1, "FOR READY TO RUN drops a mod that needs a newer Nucleus")
    U.pick("bw.for", 1)
    tick()
    local h1 = #U.hookCalls
    U.typeText("bw.q", "clock")
    eq(#U.hookCalls, h1, "typing does no ui work inside the hook")
    tick()
    eq(#lines("^%[ModManager%] BROWSE filter cat=all show=all scope=all for=game q=clock shown=1 ids=nuclearnightmare%-community%.hud%-clock$"), 1, "search clock")
    eq(names(U), "HUD Clock", "search clock: one row")
    U.commit("bw.q") tick()
    eq(#lines("q=clock shown=1"), 1, "a commit of the same text doesn't filter again")
    -- the needsCore warning on Mod Manager's row
    U.typeText("bw.q", "manage") tick()
    eq(U.byId["bw.r1.w"].image.icon, "warning", "needsCore: the warning icon")
    eq(U.byId["bw.r1.w"].tooltip, "NEEDS NUCLEUS >=0.21.0", "needsCore: its tooltip")
    eq(U.byId["bw.r1.st"].text, "UPDATE AVAILABLE", "state text: update")
    -- Details
    U.click("bw.r1.det")
    tick()
    ok(U.open.details, "DETAILS opens the Details window")
    eq(#lines("^%[ModManager%] DETAILS nuclearnightmare%-community%.mod%-manager lines=1$"), 1, "DETAILS line")
    eq(U.byId["dt.title"].text, "Mod Manager", "Details: the title")
    eq(U.byId["dt.n1"].text, "NEEDS Nucleus (Mod Core) >=0.21.0: MET", "Details: NEEDS met through the catalog's Nucleus")
    eq(U.byId["dt.inst"].text, "INSTALLED 0.2.0", "Details: INSTALLED")
    -- REFRESH: a second job, a second done
    U.back("details")
    U.click("bw.refresh") tick()
    eq(#lines("^%[ModManager%] CATALOG refresh job=2$"), 1, "REFRESH: a second job")
    eq(U.byId["bw.status"].text, "CHECKING CATALOG...", "REFRESH: checking")
    tick()
    eq(#lines("CATALOG done outcome=ok"), 2, "REFRESH: a second done")
    eq(#lines("^%[ModManager%] BROWSE pkg "), 5, "REFRESH: unchanged packages are not logged again")
    eq(#lines("WARN"), 0, "online: no WARN")
    eq(W.async, 0, "never LoopAsync or ExecuteInGameThread")
    endSession()
end

do -- Still running when Browse opens: CHECKING; the list fills in when done arrives; REFRESH meanwhile is busy.
    local release = false
    local core, U, F = browseSession{ poll = function() if not release then return "running" end return done("ok", fixture("catalog-ok.json"))() end }
    tick()
    U = openBrowse(core)
    eq(#lines("^%[ModManager%] BROWSE open shown=0 total=0 state=checking$"), 1, "running: BROWSE open state=checking")
    eq(U.byId["bw.status"].text, "CHECKING CATALOG...", "running: CHECKING CATALOG...")
    U.click("bw.refresh") tick()
    eq(F.refreshes, 1, "busy: no second job")
    eq(#lines("^%[ModManager%] CATALOG refresh busy$"), 1, "busy: logged")
    eq(U.byId["bw.status"].text, "CATALOG BUSY", "busy: CATALOG BUSY")
    release = true
    tick()
    eq(#lines("CATALOG done outcome=ok"), 1, "running: done")
    eq(names(U), "HUD Clock,Map Waypoints+,Mod Manager,Nucleus (Mod Core),Whistle Emote Mute", "running: the open window filled in")
    eq(F.refreshes, 1, "busy: never retried by itself")
    endSession()
end

do -- core's "busy" answer at REFRESH: CATALOG BUSY, no retry.
    local core, U, F = browseSession{ refresh = function(n) if n == 1 then return 1 end return nil, "busy" end, poll = done("ok", fixture("catalog-ok.json")) }
    tick()
    U = openBrowse(core)
    U.click("bw.refresh") tick()
    eq(#lines("^%[ModManager%] CATALOG refresh busy$"), 1, "core busy: logged")
    eq(U.byId["bw.status"].text, "CATALOG BUSY", "core busy: CATALOG BUSY")
    tick() tick()
    eq(F.refreshes, 2, "core busy: not retried")
    endSession()
end

do -- Offline with a verified copy: the same list, OFFLINE: SAVED CATALOG and the copy's ages.
    local core, U = browseSession{ poll = done("ok", fixture("catalog-copy.json")) }
    tick()
    eq(#lines("^%[ModManager%] CATALOG done outcome=ok source=copy packages=5 "), 1, "copy: CATALOG done source=copy")
    U = openBrowse(core)
    eq(#lines("BROWSE open shown=5 total=5 state=copy$"), 1, "copy: state=copy")
    eq(U.byId["bw.age"].text, "OFFLINE: SAVED CATALOG - CATALOG UPDATED 3 HOURS AGO - REVOCATIONS CHECKED 21 DAYS AGO", "copy: OFFLINE and the ages")
    endSession()
end

do -- Offline without a copy: an empty list and the REFRESH hint.
    local core, U = browseSession{ poll = done("error", nil, "no endpoint reachable and no verified copy") }
    tick()
    eq(#lines("^%[ModManager%] CATALOG done outcome=error source=%- packages=0 index_issued=%-$"), 1, "unavailable: CATALOG done")
    U = openBrowse(core)
    eq(#lines("BROWSE open shown=0 total=0 state=unavailable$"), 1, "unavailable: state")
    eq(U.byId["bw.status"].text, "CATALOG UNAVAILABLE. CHECK YOUR CONNECTION AND PRESS REFRESH.", "unavailable: the hint")
    ok(not U.byId["bw.age"].visible, "unavailable: no age line")
    eq(U.byId["bw.count"].text, "0 OF 0 MODS", "unavailable: empty")
    endSession()
end

do -- A rejection: the refusal only, never the copy; logged with its message.
    local core, U = browseSession{ poll = done("bad-signature", nil, "index.json: the signature does not verify") }
    tick()
    eq(#lines("^%[ModManager%] CATALOG message bad%-signature: index%.json: the signature does not verify$"), 1, "refused: logged with the message")
    U = openBrowse(core)
    eq(#lines("BROWSE open shown=0 total=0 state=refused$"), 1, "refused: state")
    eq(U.byId["bw.status"].text, "CATALOG REFUSED (bad-signature)", "refused: the text")
    endSession()
end

do -- Too new: CATALOG NEEDS A NEWER MOD MANAGER.
    local core, U = browseSession{ poll = done("schema-too-new", nil, "update the manager") }
    tick()
    U = openBrowse(core)
    eq(#lines("BROWSE open shown=0 total=0 state=refused$"), 1, "too new: state=refused")
    eq(U.byId["bw.status"].text, "CATALOG NEEDS A NEWER MOD MANAGER", "too new: the text")
    endSession()
end

do -- A payload that won't decode or has the wrong types: CATALOG ERROR, one WARN.
    local core, U = browseSession{ poll = done("ok", fixture("catalog-bad.json")) }
    tick()
    U = openBrowse(core)
    eq(#lines("BROWSE open shown=0 total=0 state=error$"), 1, "bad payload: state=error")
    eq(U.byId["bw.status"].text, "CATALOG ERROR", "bad payload: CATALOG ERROR")
    eq(#lines("^%[ModManager%] WARN the catalog could not be read %(payload: index%.packages must be an array%)"), 1, "bad payload: one WARN")
    eq(#lines("WARN"), 1, "bad payload: only that WARN")
    U.click("bw.refresh") tick() tick()
    eq(#lines("WARN"), 1, "bad payload: still one WARN after a second refresh")
    endSession()
    local core2, U2 = browseSession{ poll = function() return "done", { outcome = "ok", message = "", payloadError = "1:1 unexpected" } end }
    tick()
    U2 = openBrowse(core2)
    eq(U2.byId["bw.status"].text, "CATALOG ERROR", "undecodable payload: CATALOG ERROR")
    eq(#lines("WARN the catalog could not be read"), 1, "undecodable payload: one WARN")
    endSession()
end

do -- Build unknown: no manifest, the footer's version not in game_builds.
    local core, U = browseSession{ footer = "NUCLEAR NIGHTMARE EA V9.9.9", poll = done("ok", fixture("catalog-ok.json")) }
    tick()
    eq(#lines("^%[ModManager%] BUILD %- from=none$"), 1, "build unknown: BUILD - from=none")
    U = openBrowse(core)
    eq(U.byId["bw.status"].text, "GAME BUILD UNKNOWN", "build unknown: the status line")
    eq(#lines("BROWSE open shown=0 total=5 state=ok$"), 1, "build unknown: FOR THIS GAME is empty")
    U.pick("bw.for", 3) tick()
    eq(#lines("for=all q= shown=5 "), 1, "build unknown: ALL BUILDS shows them")
    eq(U.byId["bw.r1.st"].text, "OTHER GAME BUILD", "build unknown: other-build rows")
    endSession()
end

do -- The poll chain stops on "unknown job" and after 10 minutes (error); a refresh that can't start is error.
    local core, U, F = browseSession{ poll = function() return nil, "unknown job" end }
    tick()
    eq(#lines("^%[ModManager%] CATALOG done outcome=error "), 1, "unknown job: done as error")
    tick()
    eq(F.polls, 1, "unknown job: the chain stopped")
    endSession()
    core, U, F = browseSession{ poll = function() return "running" end }
    for _ = 1, 2400 do tick() end
    eq(F.polls, 2400, "10 minutes of polls")
    eq(#lines("^%[ModManager%] CATALOG message error: no answer in 10 minutes$"), 1, "10 minutes: error")
    tick()
    eq(F.polls, 2400, "10 minutes: the chain stopped")
    U = openBrowse(core)
    eq(#lines("BROWSE open shown=0 total=0 state=error$"), 1, "10 minutes: state=error")
    endSession()
    core, U, F = browseSession{ refresh = function() return nil, "native part missing" end, poll = function() return "running" end }
    eq(#lines("^%[ModManager%] CATALOG refresh error native part missing$"), 1, "refresh refused: CATALOG refresh error")
    eq(W.delayed, 0, "refresh refused: nothing polled")
    endSession()
end

do -- Every other nil answer of core.catalog.poll ends the chain as error; a throwing poll too (one WARN).
    for _, why in ipairs({ "bad job", "poll: bad arguments", "bad-signature", "error: unexpected answer" }) do
        local core, U, F = browseSession{ poll = function() return nil, why end }
        tick()
        eq(#lines("^%[ModManager%] CATALOG message error: " .. why:gsub("%p", "%%%0") .. "$"), 1, "poll nil, " .. why .. ": done as error with its reason")
        eq(#lines("^%[ModManager%] CATALOG done outcome=error "), 1, "poll nil, " .. why .. ": one done")
        tick()
        eq(F.polls, 1, "poll nil, " .. why .. ": the chain stopped")
        U = openBrowse(core)
        eq(#lines("BROWSE open shown=0 total=0 state=error$"), 1, "poll nil, " .. why .. ": state=error, not CHECKING")
        endSession()
    end
    local core, U, F = browseSession{ poll = function() error("native gone") end }
    tick()
    eq(#lines("^%[ModManager%] WARN core%.catalog%.poll failed: .*native gone"), 1, "throwing poll: one WARN with the error")
    eq(#lines("^%[ModManager%] CATALOG done outcome=error "), 1, "throwing poll: done as error")
    tick()
    eq(F.polls, 1, "throwing poll: the chain stopped")
    U = openBrowse(core)
    eq(#lines("BROWSE open shown=0 total=0 state=error$"), 1, "throwing poll: state=error")
    U.click("bw.refresh") tick()
    eq(#lines("^%[ModManager%] CATALOG refresh busy$"), 0, "throwing poll: REFRESH is not BUSY afterwards")
    endSession()
end

do -- core answers "busy" to the startup refresh: never CHECKING forever, Browse opens with state=error.
    local core = browseSession{ refresh = function() return nil, "busy" end, poll = function() return "running" end }
    local U = openBrowse(core)
    eq(#lines("^%[ModManager%] CATALOG refresh busy$"), 1, "startup busy: logged")
    eq(#lines("BROWSE open shown=0 total=0 state=error$"), 1, "startup busy: BROWSE open state=error")
    eq(U.byId["bw.status"].text, "CATALOG ERROR", "startup busy: the status line")
    endSession()
end

do -- DETAILS opens the package its row showed at the click, even when a refill ran before the deferred click.
    local core = browseSession{ poll = done("ok", fixture("catalog-ok.json")) }
    tick()
    local U = openBrowse(core)
    local second = U.byId["bw.r2.name"].text
    U.typeText("bw.q", "waypoints") -- the refill is queued first
    U.click("bw.r2.det")             -- row 2 is still Map Waypoints+ at the click
    tick()
    eq(names(U), "Map Waypoints+", "refill before DETAILS: Waypoints is row 1 now")
    eq(second, "Map Waypoints+", "refill before DETAILS: row 2 was Waypoints at the click")
    ok(U.open.details, "refill before DETAILS: Details opens")
    eq(#lines("^%[ModManager%] DETAILS nuclearnightmare%-community%.waypoints lines="), 1, "refill before DETAILS: the clicked package's Details")
    eq(U.byId["dt.title"].text, "Map Waypoints+", "refill before DETAILS: its title")
    U.back("details")
    U.typeText("bw.q", "")
    tick()
    U.typeText("bw.q", "whistle")   -- HUD Clock (row 1) is filtered away before the click runs
    U.click("bw.r1.det")
    tick()
    eq(#lines("^%[ModManager%] DETAILS nuclearnightmare%-community%.hud%-clock "), 0, "a row filtered away before its DETAILS ran: no Details, no line")
    ok(not U.open.details, "a row filtered away: no Details window")
    endSession()
end

do -- No core.catalog: one WARN, no BROWSE button, no refresh.
    boot()
    local core = newCore{ catalog = false }
    connect(core)
    eq(#lines("^%[ModManager%] WARN Nucleus has no core%.catalog: the main window has no BROWSE button$"), 1, "no core.catalog: one WARN")
    core.ui.entries[1].onClick()
    core.ui.open.main = nil
    core.ui.entries[1].onClick()
    eq(core.ui.byId.browse, nil, "no core.catalog: no BROWSE button")
    eq(#lines("WARN"), 1, "no core.catalog: only that WARN")
    eq(#lines("CATALOG"), 0, "no core.catalog: no refresh")
    restore()
end

-- ---------------------------------------------------------------- v2 story 5: INSTALL
local NNC = "nuclearnightmare-community."
-- A session for INSTALL: the startup refresh answers payload (catalog-ok.json unless o.payload), core.restart and
-- core.apply are there, W.queue on. o.stage(n, list) answers core.catalog.stage; o.stagePoll(n, job) the stage job's polls.
local function installSession(o)
    o = o or {}
    boot()
    W.queue = {}
    os.time = function() return NOW end
    local sp = 0
    local F = fakeCatalog{
        stage = o.stage,
        poll = function(_, job)
            if job < 100 then return done("ok", o.payload or fixture("catalog-ok.json"))() end -- refreshes; stage jobs are 101, 102, ...
            sp = sp + 1
            return o.stagePoll(sp, job)
        end,
    }
    local core = newCore{ catalog = F.api }
    fakeRestart(core)
    local A = fakeApply(core, o.apply)
    connect(core)
    tick() -- the refresh's done
    return core, core.ui, F, A
end
local function stageOk(owners, ops)
    return function()
        local list = {}
        for i, id in ipairs(owners) do list[i] = { id = id, version = "1.0.0", name = "N", files = 2, bytes = 10 } end
        return "done", { outcome = "ok", message = "staged", payload = { txn = "0123456789abcdef0123456789abcdef", owners = list, ops = ops or 4 } }
    end
end
local function rowNamed(U, name)
    for n = 1, 200 do
        local el = U.byId["bw.r" .. n .. ".name"]
        if not el then return nil end
        if el.text == name and U.byId["bw.r" .. n].visible then return n end
    end
end

do -- A plain install: HUD Clock (the installed Nucleus 0.12.1 meets >=0.9.0): the confirm, the stage, RESTART NOW.
    local core, U, F, A = installSession{ stagePoll = function(n) if n == 1 then return "running" end return stageOk({ NNC .. "hud-clock" })() end }
    U = openBrowse(core)
    local n = rowNamed(U, "HUD Clock")
    ok(n and U.byId["bw.r" .. n .. ".inst"].visible and U.byId["bw.r" .. n .. ".inst"].label == "INSTALL", "plain: an available row has INSTALL")
    local m = rowNamed(U, "Mod Manager")
    eq(U.byId["bw.r" .. m .. ".inst"].label, "UPDATE", "plain: an update row's slot reads UPDATE (story 6)")    local h0 = #U.hookCalls
    ok(U.click("bw.r" .. n .. ".inst"), "plain: INSTALL clicked")
    eq(#U.hookCalls, h0, "plain: INSTALL does no ui work inside core's hook")
    tick()
    ok(U.open.install, "plain: the confirm window (id install) opens")
    eq(U.byId["in.title"].text, "INSTALL HUD CLOCK 0.3.0?", "plain: the title")
    eq(U.byId["in.also"].visible, false, "plain: no ALSO INSTALLS")
    eq(U.byId["in.l1"].visible, false, "plain: no dependency lines")
    eq(U.byId["in.more"].visible, false, "plain: no AND MORE")
    eq(U.byId["in.size"].text, "DOWNLOAD 1 KB", "plain: the download size")
    local okBtn = U.byId["in.ok"]
    ok(okBtn.kind == "button" and okBtn.label == "INSTALL" and okBtn.visible and okBtn.enabled, "plain: INSTALL is one of core's buttons (focusable: keys and a gamepad reach it and BACK)")
    eq(#lines("^%[ModManager%] INSTALL ask nuclearnightmare%-community%.hud%-clock set=nuclearnightmare%-community%.hud%-clock@0%.3%.0$"), 1, "plain: INSTALL ask")
    eq(F.stages, nil, "plain: nothing staged before the confirm")
    U.click("in.ok")
    tick()
    ok(not U.open.install, "plain: the confirm closes")
    eq(F.stages, 1, "plain: one stage call")
    ok(F.staged and #F.staged == 1 and F.staged[1].id == NNC .. "hud-clock" and F.staged[1].version == "0.3.0", "plain: core.catalog.stage({ { id, version } })")
    eq(#lines("^%[ModManager%] INSTALL stage job=101$"), 1, "plain: INSTALL stage job")
    eq(U.byId["bw.status"].text, "DOWNLOADING HUD CLOCK...", "plain: DOWNLOADING while it runs")
    eq(U.byId["bw.r" .. n .. ".inst"].enabled, false, "plain: INSTALL disabled while it runs")
    U.click("bw.r" .. n .. ".inst")
    tick() -- the first poll: running
    eq(#lines("INSTALL ask"), 1, "plain: a disabled INSTALL asks nothing")
    eq(#lines("INSTALL done"), 0, "plain: not done yet")
    tick() -- done
    eq(#lines("^%[ModManager%] INSTALL done outcome=ok txn=0123456789abcdef0123456789abcdef owners=1 ops=4$"), 1, "plain: INSTALL done")
    eq(A.calls.start, 1, "plain: core.apply.start()")
    eq(#lines("^%[ModManager%] APPLY start ok$"), 1, "plain: APPLY start ok")
    eq(U.byId["bw.status"].text, "HUD CLOCK INSTALLS WHEN THE GAME RESTARTS", "plain: the result message")
    eq(U.byId["bw.r" .. n .. ".st"].text, "PENDING RESTART", "plain: the row reads PENDING RESTART")
    eq(U.byId["bw.r" .. n .. ".inst"].visible, false, "plain: and has no INSTALL")
    ok(U.byId.quit.visible and U.byId.restart.visible, "plain: QUIT GAME and RESTART NOW show (the staged change is pending)")
    eq(U.byId.msg.text, "HUD CLOCK INSTALLS WHEN THE GAME RESTARTS", "plain: the main window's message line too")
    -- Details of a staged row: no INSTALL
    U.click("bw.r" .. n .. ".det") tick()
    eq(U.byId["dt.install"].visible, false, "plain: Details of a staged mod has no INSTALL")
    eq(W.async, 0, "plain: never LoopAsync or ExecuteInGameThread")
    eq(#lines("WARN"), 0, "plain: no WARN")
    endSession()
end

do -- Missing and too-old dependencies: Target needs Alpha (absent) and Nucleus >=0.22.0 (0.12.1 installed).
    local p = fixture("catalog-ok.json")
    local function ver(v, deps) return { version = v, scope = "client", game = { version = "V8.2.3", build = "26601774" }, ue4ss = "x", dependsOn = deps,
        url = "https://github.com/x/y/releases/download/v1/x.zip", sha256 = string.rep("d", 64), size = 3000000, published = "2026-11-20T00:00:00Z" } end
    local function pk(id, name, deps) return { id = id, name = name, kind = "mod", description = name .. " for tests.", categories = { "ui" }, publisher = "P",
        repo = "x/y", license = "MIT", versions = { ver("1.0.0", deps) } } end
    local pk1 = pk("x.alpha", "Alpha", {})
    local pk2 = pk("x.target", "Target", { { id = "x.alpha", version = ">=1.0.0" }, { id = NNC .. "nucleus", version = ">=0.22.0" } })
    local many = {}
    for i = 1, 10 do many[i] = { id = "x.dep" .. i, version = ">=1.0.0" } end
    local pk3 = pk("x.big", "Big", many)
    table.insert(p.index.packages, pk1); table.insert(p.index.packages, pk2); table.insert(p.index.packages, pk3)
    for i = 1, 10 do table.insert(p.index.packages, pk("x.dep" .. i, "Dep" .. i, {})) end
    local core, U, F = installSession{ payload = p, stagePoll = stageOk({ "x.alpha", NNC .. "nucleus", "x.target" }, 9) }
    U = openBrowse(core)
    U.typeText("bw.q", "target") tick()
    U.click("bw.r1.inst") tick()
    eq(U.byId["in.title"].text, "INSTALL TARGET 1.0.0?", "deps: the title")
    eq(U.byId["in.also"].visible, true, "deps: ALSO INSTALLS:")
    eq(U.byId["in.also"].text, "ALSO INSTALLS:", "deps: its text")
    eq(U.byId["in.l1"].text, "ALPHA 1.0.0 (NEW)", "deps: the missing one (NEW)")
    eq(U.byId["in.l2"].text, "NUCLEUS (MOD CORE) 0.22.0 (UPDATE FROM 0.12.1)", "deps: the too-old one (UPDATE FROM)")
    eq(U.byId["in.l3"].visible, false, "deps: two lines")
    eq(U.byId["in.size"].text, "DOWNLOAD 5.7 MB", "deps: the summed index sizes (3000000 + 100 + 3000000 bytes)")
    eq(#lines("^%[ModManager%] INSTALL ask x%.target set=x%.alpha@1%.0%.0,nuclearnightmare%-community%.nucleus@0%.22%.0,x%.target@1%.0%.0$"), 1, "deps: INSTALL ask, dependencies first")
    U.click("in.ok") tick()
    ok(#F.staged == 3 and F.staged[1].id == "x.alpha" and F.staged[2].id == NNC .. "nucleus" and F.staged[2].version == "0.22.0" and F.staged[3].id == "x.target",
        "deps: one stage of three, dependencies first")
    tick()
    eq(#lines("^%[ModManager%] INSTALL done outcome=ok txn=%x+ owners=3 ops=9$"), 1, "deps: done with three owners")
    -- ten dependencies: eight lines, then AND 2 MORE
    U.typeText("bw.q", "big") tick()
    U.click("bw.r1.inst") tick()
    eq(U.byId["in.l8"].text, "DEP8 1.0.0 (NEW)", "many: the eighth line")
    eq(U.byId["in.more"].visible, true, "many: AND MORE shows")
    eq(U.byId["in.more"].text, "AND 2 MORE", "many: AND 2 MORE")
    U.back("install") tick()
    eq(#lines("^%[ModManager%] INSTALL cancel x%.big %(close%)$"), 1, "BACK: cancelled, logged")
    U.click("in.ok") tick()
    eq(F.stages, 1, "BACK: a stale confirm click stages nothing")
    endSession()
end

do -- Refused by the resolver: no confirm, the message, INSTALL refuse.
    local p = fixture("catalog-ok.json")
    local function ver(deps) return { version = "1.0.0", scope = "client", game = { version = "V8.2.3", build = "26601774" }, dependsOn = deps, sha256 = string.rep("e", 64), size = 10 } end
    table.insert(p.index.packages, { id = "x.uses", name = "Uses", kind = "mod", description = "Uses a taken folder.", categories = { "ui" }, versions = { ver({ { id = "x.held", version = ">=1.0.0" } }) } })
    -- ModManagerBase's folder holds nuclearnightmare-community.mod-manager-base; x.held is named ModManagerBase: conflict
    table.insert(p.index.packages, { id = "x.held", name = "ModManagerBase", displayName = "Held", kind = "mod", description = "Held.", categories = { "ui" }, versions = { ver({}) } })
    local many = {}
    for i = 1, 16 do many[i] = { id = "x.d" .. i, version = ">=1.0.0" }; table.insert(p.index.packages, { id = "x.d" .. i, name = "D" .. i, kind = "mod", description = "D.", categories = { "ui" }, versions = { ver({}) } }) end
    table.insert(p.index.packages, { id = "x.huge", name = "Huge", kind = "mod", description = "Needs sixteen.", categories = { "ui" }, versions = { ver(many) } })
    local core, U, F = installSession{ payload = p, stagePoll = stageOk({}) }
    U = openBrowse(core)
    U.typeText("bw.q", "uses") tick()
    U.click("bw.r1.inst") tick()
    ok(not U.open.install, "conflict: no confirm")
    eq(U.byId["bw.status"].text, "CAN'T INSTALL HELD (CONFLICT)", "conflict: the message")
    eq(#lines("^%[ModManager%] INSTALL refuse x%.uses reason=conflict$"), 1, "conflict: INSTALL refuse")
    U.typeText("bw.q", "sixteen") tick()
    U.click("bw.r1.inst") tick()
    eq(U.byId["bw.status"].text, "CAN'T INSTALL HUGE (TOO-MANY)", "too-many: the message")
    eq(#lines("^%[ModManager%] INSTALL refuse x%.huge reason=too%-many$"), 1, "too-many: INSTALL refuse")
    -- unsatisfiable (the resolver's answer; the model offers only satisfiable versions, so it is stubbed here)
    local Cat = package.loaded["catalog"]
    local real = Cat.installSet
    Cat.installSet = function() return nil, "unsatisfiable", { name = "HUD Clock", dep = "Nucleus (Mod Core)", need = ">=9.0.0" } end
    U.typeText("bw.q", "clock") tick()
    U.click("bw.r1.inst") tick()
    Cat.installSet = real
    eq(U.byId["bw.status"].text, "CAN'T INSTALL: HUD CLOCK NEEDS NUCLEUS (MOD CORE) >=9.0.0", "unsatisfiable: the message")
    eq(#lines("^%[ModManager%] INSTALL refuse nuclearnightmare%-community%.hud%-clock reason=unsatisfiable$"), 1, "unsatisfiable: INSTALL refuse")
    eq(F.stages, nil, "resolver refusals: nothing staged")
    endSession()
end

do -- Stage outcomes other than ok: the message, nothing pending, INSTALL again.
    for _, c in ipairs({ { "hash-mismatch", "INSTALL REFUSED (hash-mismatch)" }, { "bad-zip", "INSTALL REFUSED (bad-zip)" },
        { "folder-in-use", "INSTALL REFUSED (folder-in-use)" }, { "error", "INSTALL FAILED" } }) do
        local core, U, F, A = installSession{ stagePoll = function() return "done", { outcome = c[1], message = "why", payload = { failed = NNC .. "hud-clock" } } end }
        U = openBrowse(core)
        local n = rowNamed(U, "HUD Clock")
        U.click("bw.r" .. n .. ".inst") tick()
        U.click("in.ok") tick()
        tick()
        eq(U.byId["bw.status"].text, c[2], c[1] .. ": the message")
        eq(#lines("^%[ModManager%] INSTALL done outcome=" .. c[1]:gsub("%-", "%%-") .. " txn=%- owners=0 ops=%-$"), 1, c[1] .. ": INSTALL done")
        eq(A.calls.start, 0, c[1] .. ": no helper started")
        ok(U.byId["bw.r" .. n .. ".inst"].visible and U.byId["bw.r" .. n .. ".inst"].enabled, c[1] .. ": INSTALL is offered again")
        eq(U.byId.restart.visible, false, c[1] .. ": nothing pending")
        endSession()
    end
    -- refused before a job: busy, applying
    for _, c in ipairs({ { "busy", "CATALOG BUSY" }, { "applying", "INSTALL REFUSED (applying)" }, { "no verified index", "INSTALL REFUSED (no verified index)" } }) do
        local core, U = installSession{ stage = function() return nil, c[1] end, stagePoll = stageOk({}) }
        U = openBrowse(core)
        U.click("bw.r" .. rowNamed(U, "HUD Clock") .. ".inst") tick()
        U.click("in.ok") tick()
        eq(U.byId["bw.status"].text, c[2], "stage nil, " .. c[1] .. ": the message")
        eq(#lines("^%[ModManager%] INSTALL stage job=" .. c[1]:gsub("%-", "%%-") .. "$"), 1, "stage nil, " .. c[1] .. ": logged")
        endSession()
    end
    -- a poll that never finishes: 10 minutes, then INSTALL FAILED
    local core, U, F = installSession{ stagePoll = function() return "running" end }
    U = openBrowse(core)
    U.click("bw.r" .. rowNamed(U, "HUD Clock") .. ".inst") tick()
    U.click("in.ok") tick()
    for _ = 1, 2400 do tick() end
    eq(U.byId["bw.status"].text, "INSTALL FAILED", "poll cap: INSTALL FAILED after 10 minutes")
    eq(#lines("^%[ModManager%] INSTALL done outcome=error "), 1, "poll cap: done as error")
    local before = F.polls
    tick() tick()
    eq(F.polls, before, "poll cap: the chain stopped")
    endSession()
end

do -- A second install before the restart: both pending (core merges them into one staged change).
    local core, U, F, A = installSession{ stagePoll = function(n) if n == 1 then return stageOk({ NNC .. "hud-clock" })() end return stageOk({ NNC .. "whistle-mute" })() end }
    U = openBrowse(core)
    U.click("bw.r" .. rowNamed(U, "HUD Clock") .. ".inst") tick()
    U.click("in.ok") tick() tick()
    U.click("bw.r" .. rowNamed(U, "Whistle Emote Mute") .. ".inst") tick()
    U.click("in.ok") tick() tick()
    eq(U.byId["bw.r" .. rowNamed(U, "HUD Clock") .. ".st"].text, "PENDING RESTART", "merge: the first stays pending")
    eq(U.byId["bw.r" .. rowNamed(U, "Whistle Emote Mute") .. ".st"].text, "PENDING RESTART", "merge: the second pending too")
    eq(#lines("INSTALL done outcome=ok"), 2, "merge: two stages")
    eq(A.calls.start, 2, "merge: the helper asked twice (already started is fine)")
    -- a refresh keeps the marks
    U.click("bw.refresh") tick() tick()
    eq(U.byId["bw.r" .. rowNamed(U, "HUD Clock") .. ".st"].text, "PENDING RESTART", "merge: a refresh keeps PENDING RESTART")
    endSession()
end

do -- APPLY start "already started" counts as fine; core without core.catalog.stage: one WARN, no INSTALL flow.
    local core, U, F, A = installSession{ apply = { start = { false, "already started" } }, stagePoll = stageOk({ NNC .. "hud-clock" }) }
    U = openBrowse(core)
    U.click("bw.r" .. rowNamed(U, "HUD Clock") .. ".inst") tick()
    U.click("in.ok") tick() tick()
    eq(#lines("^%[ModManager%] APPLY start already started$"), 1, "already started: logged")
    eq(U.byId["bw.status"].text, "HUD CLOCK INSTALLS WHEN THE GAME RESTARTS", "already started: still the result message")
    endSession()
    boot()
    local c2 = newCore{ catalog = { refresh = function() return nil, "busy" end, poll = function() return nil, "unknown job" end } }
    connect(c2)
    eq(#lines("^%[ModManager%] WARN Nucleus has no core%.catalog%.stage: Browse has no INSTALL$"), 1, "no stage: one WARN")
    restore()
end

-- ---------------------------------------------------------------- v2 story 6: updates, revocations, uninstall
local A64, B64 = string.rep("a", 64), string.rep("b", 64)
local function modJson(id, v, deps)
    local d = {}
    for i, x in ipairs(deps or {}) do d[i] = '{"id":"' .. x .. '","version":">=0.1.0"}' end
    return '{"id":"' .. id .. '","version":"' .. v .. '","game":{"version":"V8.2.3","build":"26601774"},"dependsOn":[' .. table.concat(d, ",") .. ']}'
end
-- The ok fixture with HUD Clock's versions replaced (o.hud = { { version, sha }, ... }, newest first) and a revoked list
-- (o.revoked, default: HUD Clock 0.3.0 with the index's sha, "crash on map load", disable); o.extra: more packages.
local function revPayload(o)
    o = o or {}
    local p = fixture("catalog-ok.json")
    for _, pk in ipairs(p.index.packages) do
        if pk.id == NNC .. "hud-clock" then
            local base = pk.versions[1]
            pk.versions = {}
            for i, h in ipairs(o.hud or { { "0.3.1", B64 }, { "0.3.0", A64 } }) do
                local v = {}
                for k, x in pairs(base) do v[k] = x end
                v.version, v.sha256 = h[1], h[2]
                pk.versions[i] = v
            end
        end
    end
    for _, pk in ipairs(o.extra or {}) do table.insert(p.index.packages, pk) end
    p.revoked.revoked = o.revoked or { { id = NNC .. "hud-clock", version = "0.3.0", sha256 = A64, reason = "crash on map load", action = "disable" } }
    return p
end
-- A session with HUD Clock (o.hudVersion, default 0.3.0) and Whistle Emote Mute 0.2.1 installed (o.mods adds more),
-- core.restart and core.apply, W.queue on. o.stagePoll(n, job), o.unstagePoll(n, job): the jobs' polls; o.unstage(n,
-- id, version): core.catalog.unstage's answer; o.refreshPoll(n): the n-th refresh's done (default: the payload).
local function revSession(o)
    o = o or {}
    local mods2 = { HudClock = modJson(NNC .. "hud-clock", o.hudVersion or "0.3.0", { NNC .. "nucleus" }), WhistleMute = modJson(NNC .. "whistle-mute", "0.2.1") }
    for k, v in pairs(o.mods or {}) do mods2[k] = v end
    boot{ mods = mods2 }
    W.queue = {}
    os.time = function() return NOW end
    local sp, up, rp = 0, 0, 0
    local payload = o.payload or revPayload()
    local F = fakeCatalog{
        stage = o.stage, unstage = o.unstage,
        poll = function(_, job)
            if job < 100 then
                rp = rp + 1
                if o.refreshPoll then return o.refreshPoll(rp) end
                return done("ok", payload)()
            end
            if job > 200 then up = up + 1 return o.unstagePoll(up, job) end
            sp = sp + 1
            return o.stagePoll(sp, job)
        end,
    }
    local core = newCore{ catalog = F.api }
    fakeRestart(core)
    local A = fakeApply(core, o.apply)
    connect(core)
    tick() -- the refresh's done
    return core, core.ui, F, A
end
local function unstageOk(files, kept)
    return function()
        return "done", { outcome = "ok", message = "staged", payload = { txn = "fedcba9876543210fedcba9876543210",
            owners = { { id = NNC .. "whistle-mute", version = "0.2.1", name = "WhistleMute", files = files or 3, kept = kept or 0 } }, ops = 4 } }
    end
end
local function openMainWin(core)
    local U = core.ui
    U.open.main = nil
    U.entries[1].onClick()
    return U
end
local function mainRow(U, name) return rowOf(U, name) end

do -- Revoked, newer fix: the title-screen notice, REVIEW, LATER stages nothing; the main window's badge and notice line.
    local core, U, F, A = revSession{ stagePoll = function(n) if n == 1 then return "running" end return stageOk({ NNC .. "hud-clock" })() end }
    eq(#lines("^%[ModManager%] REVOKED nuclearnightmare%-community%.hud%-clock v=0%.3%.0 action=disable fix=0%.3%.1$"), 1, "revoked: REVOKED logged with its action and fix")
    local tt, tb = U.byId["tn.text"], U.byId["tn.review"]
    ok(tt and tt.visible and tt.place.host == "menu" and tt.place.corner == "top-right", "notice: a text on core's menu host, top right")
    eq(tt and tt.text, "HUD CLOCK 0.3.0 WAS REVOKED", "notice: one mod's text")
    ok(tb and tb.kind == "button" and tb.visible and tb.label == "REVIEW" and tb.place.host == "menu" and tb.place.corner == "top-right", "notice: REVIEW on the menu host, top right")
    eq(#lines("^%[ModManager%] NOTICE shown n=1$"), 1, "notice: NOTICE shown n=1")
    eq(W.delayed > 0 and #lines("NOTICE removed"), 0, "notice: not removed")
    -- REVIEW from the title screen (inside core's hook: nothing then; the window after it)
    local h0 = #U.hookCalls
    ok(U.click("tn.review"), "notice: REVIEW clicked")
    eq(#U.hookCalls, h0, "notice: REVIEW does no ui work inside core's hook")
    tick()
    ok(U.open.revoked, "REVIEW: the revoked window (id revoked) opens")
    eq(U.byId["rv.title"].text, "REVOKED MODS", "REVIEW: its title")
    eq(U.byId["rv.r1.name"].text, "HUD Clock", "REVIEW: the mod's name")
    eq(U.byId["rv.r1.ver"].text, "0.3.0", "REVIEW: its version")
    eq(U.byId["rv.d1.why"].text, "crash on map load", "REVIEW: its reason")
    local upd, un = U.byId["rv.r1.upd"], U.byId["rv.r1.un"]
    ok(upd.kind == "button" and upd.visible and upd.enabled and upd.label == "UPDATE TO 0.3.1", "REVIEW: UPDATE TO 0.3.1, one of core's buttons (the keys and a gamepad reach it)")
    ok(un.kind == "button" and un.visible and un.enabled and un.label == "UNINSTALL", "REVIEW: UNINSTALL, one of core's buttons")
    eq(#lines("^%[ModManager%] REVIEW open n=1$"), 1, "REVIEW: logged")
    -- LATER (core's BACK, or Escape): nothing staged
    U.back("revoked") tick()
    ok(not U.open.revoked, "LATER: the window closes")
    ok(F.stages == nil and F.unstages == nil, "LATER: nothing staged")
    eq(#lines("^%[ModManager%] REVIEW closed %(close%)$"), 1, "LATER: logged")
    ok(U.byId["tn.text"].visible, "LATER: the notice stays")
    -- the main window: the version cell, the red badge, the notice line
    openMainWin(core)
    local n = mainRow(U, "HudClock")
    eq(U.byId["r" .. n .. ".ver"].text, "0.3.0 → 0.3.1", "main: the version cell shows the update")
    local s4 = U.byId["r" .. n .. ".s4"]
    local found
    for k = 1, 4 do local el = U.byId["r" .. n .. ".s" .. k] if el.image and el.style and el.style.tint then found = el end end
    ok(found and found.image.icon == "warning" and found.style.tint.r == 0.85 and found.style.tint.g == 0.1 and found.style.tint.b == 0.1 and found.style.tint.a == 1,
        "main: the revoked badge is core's warning icon tinted red", s4 and tostring(s4.image))
    eq(found and found.tooltip, "REVOKED: crash on map load", "main: the badge's tooltip")
    eq(U.byId["notice.text"].text, "1 REVOKED - 3 UPDATES AVAILABLE", "main: the notice line")
    ok(U.byId["notice.list"].visible and U.byId["notice.review"].visible and U.byId["notice.updates"].visible, "main: the notice line with REVIEW and UPDATES")
    eq(U.byId["list"].size.h, 1080 - 540 - 80, "main: the list is shorter while the notice line shows")
    -- REVIEW from the main window, then UPDATE TO, then confirm
    U.click("notice.review") tick()
    ok(U.open.revoked, "main REVIEW: the revoked window opens")
    U.click("rv.r1.upd") tick()
    ok(U.open.install, "UPDATE TO: the confirm window (id install) opens")
    eq(U.byId["in.title"].text, "UPDATE HUD CLOCK 0.3.0 → 0.3.1?", "UPDATE: the title")
    eq(U.byId["in.ok"].label, "UPDATE", "UPDATE: its button reads UPDATE")
    eq(U.byId["in.also"].visible, false, "UPDATE: no ALSO INSTALLS")
    eq(U.byId["in.size"].text, "DOWNLOAD 1 KB", "UPDATE: the download size")
    eq(#lines("^%[ModManager%] UPDATE ask nuclearnightmare%-community%.hud%-clock set=nuclearnightmare%-community%.hud%-clock@0%.3%.1$"), 1, "UPDATE ask")
    eq(F.stages, nil, "UPDATE: nothing staged before the confirm")
    U.click("in.ok") tick()
    ok(F.staged and #F.staged == 1 and F.staged[1].version == "0.3.1", "UPDATE: core.catalog.stage({ { hud-clock, 0.3.1 } })")
    eq(#lines("^%[ModManager%] UPDATE stage job=101$"), 1, "UPDATE stage")
    eq(U.byId["rv.msg"].text, "DOWNLOADING HUD CLOCK...", "UPDATE: the revoked window's message while it runs")
    tick() tick()
    eq(#lines("^%[ModManager%] UPDATE done outcome=ok txn=0123456789abcdef0123456789abcdef owners=1 ops=4$"), 1, "UPDATE done")
    eq(A.calls.start, 1, "UPDATE: core.apply.start()")
    eq(U.byId["rv.msg"].text, "HUD CLOCK UPDATES WHEN THE GAME RESTARTS", "UPDATE: the result message")
    eq(#lines("^%[ModManager%] NOTICE removed$"), 1, "UPDATE: the staged owner resolves the notice: NOTICE removed")
    ok(U.byId["tn.text"].removed and U.byId["tn.review"].removed, "UPDATE: the title-screen notice is gone")
    eq(U.byId["rv.r1"].visible, false, "UPDATE: the mod leaves the revoked window")
    eq(U.byId["notice.text"].text, "2 UPDATES AVAILABLE", "UPDATE: the notice line counts the rest")
    eq(U.byId["notice.review"].visible, false, "UPDATE: no REVIEW without a revoked mod")
    ok(U.byId.restart.visible, "UPDATE: RESTART NOW shows")
    n = mainRow(U, "HudClock")
    eq(U.byId["r" .. n .. ".ver"].text, "0.3.0", "UPDATE: a staged row shows no update")
    -- UPDATES: Browse showing UPDATE AVAILABLE; the staged row PENDING RESTART without UPDATE
    U.back("revoked") tick()
    U.click("notice.updates") tick()
    ok(U.open.browse, "UPDATES: Browse opens")
    eq(U.byId["bw.show"].index, 4, "UPDATES: SHOW is UPDATE AVAILABLE")
    eq(#lines("BROWSE filter cat=all show=update "), 1, "UPDATES: the filter logged")
    eq(names(U), "HUD Clock,Mod Manager,Nucleus (Mod Core)", "UPDATES: only the update rows")
    local hn = rowNamed(U, "HUD Clock")
    eq(U.byId["bw.r" .. hn .. ".st"].text, "PENDING RESTART", "UPDATES: the staged row reads PENDING RESTART")
    eq(U.byId["bw.r" .. hn .. ".inst"].visible, false, "UPDATES: and offers no UPDATE")
    ok(U.byId["bw.r" .. hn .. ".w"].style == nil, "UPDATES: and has no red badge")
    endSession()
end

do -- The notice reappears on the next launch (no seen-state); a revoked row in Browse; Details' UPDATE.
    for launch = 1, 2 do
        local core, U = revSession{ stagePoll = stageOk({ NNC .. "hud-clock" }) }
        eq(#lines("^%[ModManager%] NOTICE shown n=1$"), 1, "launch " .. launch .. ": the notice shows again")
        if launch == 2 then
            U = openBrowse(core)
            local n = rowNamed(U, "HUD Clock")
            eq(U.byId["bw.r" .. n .. ".st"].text, "REVOKED", "browse: the state reads REVOKED")
            local w = U.byId["bw.r" .. n .. ".w"]
            ok(w.image and w.image.icon == "warning" and w.style and w.style.tint and w.style.tint.r == 0.85, "browse: core's warning icon tinted red")
            eq(w.tooltip, "REVOKED: crash on map load", "browse: its tooltip")
            eq(U.byId["bw.r" .. n .. ".inst"].label, "UPDATE", "browse: UPDATE in the INSTALL slot")
            ok(U.byId["bw.r" .. n .. ".inst"].visible, "browse: UPDATE shows")
            local m = rowNamed(U, "Map Waypoints+")
            ok(U.byId["bw.r" .. m .. ".w"].style == nil, "browse: other rows' icon untinted")
            U.click("bw.r" .. n .. ".det") tick()
            ok(U.byId["dt.install"].visible and U.byId["dt.install"].label == "UPDATE", "details: UPDATE")
            ok(U.byId["dt.uninstall"].visible and U.byId["dt.uninstall"].label == "UNINSTALL", "details: UNINSTALL for an installed mod")
            U.click("dt.install") tick()
            eq(U.byId["in.title"].text, "UPDATE HUD CLOCK 0.3.0 → 0.3.1?", "details: UPDATE opens the confirm")
            U.back("install") tick()
            eq(#lines("^%[ModManager%] UPDATE cancel nuclearnightmare%-community%.hud%-clock %(close%)$"), 1, "details: BACK cancels, logged")
            ok(U.byId.restart.visible == false or U.byId.restart.visible == nil, "details: BACK staged nothing")
        end
        endSession()
    end
end

do -- Revoked, older fix: UPDATE TO 0.3.1 from 0.4.0 (the only downgrade); revoked, no fix: UNINSTALL only; sha differs.
    local core, U, F = revSession{ hudVersion = "0.4.0", payload = revPayload{ hud = { { "0.4.0", A64 }, { "0.3.1", B64 } },
        revoked = { { id = NNC .. "hud-clock", version = "0.4.0", sha256 = A64, reason = "breaks saves", action = "block" } } },
        stagePoll = stageOk({ NNC .. "hud-clock" }) }
    eq(#lines("REVOKED nuclearnightmare%-community%.hud%-clock v=0%.4%.0 action=block fix=0%.3%.1$"), 1, "older fix: REVOKED fix=0.3.1")
    U.click("tn.review") tick()
    eq(U.byId["rv.r1.upd"].label, "UPDATE TO 0.3.1", "older fix: UPDATE TO 0.3.1")
    U.click("rv.r1.upd") tick()
    eq(U.byId["in.title"].text, "UPDATE HUD CLOCK 0.4.0 → 0.3.1?", "older fix: the confirm")
    U.click("in.ok") tick() tick()
    ok(F.staged and F.staged[1].version == "0.3.1", "older fix: 0.3.1 staged")
    endSession()
    core, U, F = revSession{ payload = revPayload{ hud = { { "0.3.0", A64 } } }, stagePoll = stageOk({}) }
    U.click("tn.review") tick()
    eq(U.byId["rv.r1.upd"].visible, false, "no fix: no UPDATE TO")
    eq(U.byId["rv.r1.un"].visible, true, "no fix: UNINSTALL only")
    eq(#lines("fix=none$"), 1, "no fix: REVOKED fix=none")
    U = openBrowse(core)
    eq(rowNamed(U, "HUD Clock"), nil, "no fix: no version offered for this game (other-build)")
    U.pick("bw.for", 3) tick()
    local hn = rowNamed(U, "HUD Clock")
    eq(U.byId["bw.r" .. hn .. ".st"].text, "REVOKED", "no fix: ALL BUILDS shows it REVOKED")
    eq(U.byId["bw.r" .. hn .. ".inst"].visible, false, "no fix: Browse offers no UPDATE")
    endSession()
    core, U = revSession{ payload = revPayload{ revoked = { { id = NNC .. "hud-clock", version = "0.3.0", sha256 = B64, reason = "x", action = "disable" } } }, stagePoll = stageOk({}) }
    eq(U.byId["tn.text"], nil, "sha differs: no notice")
    eq(#lines("REVOKED nuclear"), 0, "sha differs: not revoked")
    endSession()
    -- two revoked: the plural text
    core, U = revSession{ payload = revPayload{ revoked = { { id = NNC .. "hud-clock", version = "0.3.0", sha256 = A64, reason = "x", action = "disable" },
        { id = NNC .. "whistle-mute", version = "0.2.1", sha256 = A64, reason = "y", action = "block" } } }, stagePoll = stageOk({}) }
    eq(U.byId["tn.text"].text, "2 INSTALLED MODS WERE REVOKED", "several: the plural text")
    eq(#lines("^%[ModManager%] NOTICE shown n=2$"), 1, "several: NOTICE shown n=2")
    endSession()
end

do -- UPDATE refusals: the resolver's and the stage's, with UPDATE texts.
    local core, U = revSession{ stagePoll = function() return "done", { outcome = "downgrade", message = "x", payload = {} } end }
    U = openBrowse(core)
    U.click("bw.r" .. rowNamed(U, "HUD Clock") .. ".inst") tick()
    U.click("in.ok") tick() tick()
    eq(U.byId["bw.status"].text, "UPDATE REFUSED (downgrade)", "update refused: the message")
    eq(#lines("^%[ModManager%] UPDATE done outcome=downgrade "), 1, "update refused: UPDATE done")
    endSession()
    core, U = revSession{ stagePoll = function() return "done", { outcome = "error", message = "x", payload = {} } end }
    U = openBrowse(core)
    U.click("bw.r" .. rowNamed(U, "HUD Clock") .. ".inst") tick()
    U.click("in.ok") tick() tick()
    eq(U.byId["bw.status"].text, "UPDATE FAILED", "update error: UPDATE FAILED")
    endSession()
    core, U = revSession{ stagePoll = stageOk({}) }
    U = openBrowse(core)
    local Cat = package.loaded["catalog"]
    local real = Cat.installSet
    Cat.installSet = function() return nil, "conflict", { name = "HUD Clock" } end
    U.click("bw.r" .. rowNamed(U, "HUD Clock") .. ".inst") tick()
    Cat.installSet = real
    eq(U.byId["bw.status"].text, "CAN'T UPDATE HUD CLOCK (CONFLICT)", "update resolver refusal: the message")
    eq(#lines("^%[ModManager%] UPDATE refuse nuclearnightmare%-community%.hud%-clock reason=conflict$"), 1, "UPDATE refuse logged")
    endSession()
end

do -- UNINSTALL from Details: the confirm, the unstage, PENDING RESTART; Nucleus and the Mod Manager have none.
    local core, U, F, A = revSession{ unstagePoll = function(n) if n == 1 then return "running" end return unstageOk(3, 1)() end, stagePoll = stageOk({}) }
    U = openBrowse(core)
    U.click("bw.r" .. rowNamed(U, "Nucleus (Mod Core)") .. ".det") tick()
    eq(U.byId["dt.uninstall"].visible, false, "Nucleus: no UNINSTALL")
    U.back("details") tick()
    U.click("bw.r" .. rowNamed(U, "Mod Manager") .. ".det") tick()
    eq(U.byId["dt.uninstall"].visible, false, "Mod Manager: no UNINSTALL")
    U.back("details") tick()
    U.click("bw.r" .. rowNamed(U, "Map Waypoints+") .. ".det") tick()
    eq(U.byId["dt.uninstall"].visible, false, "not installed: no UNINSTALL")
    U.back("details") tick()
    local n = rowNamed(U, "Whistle Emote Mute")
    U.click("bw.r" .. n .. ".det") tick()
    ok(U.byId["dt.uninstall"].visible, "installed: UNINSTALL")
    local h0 = #U.hookCalls
    U.click("dt.uninstall")
    eq(#U.hookCalls, h0, "UNINSTALL does no ui work inside core's hook")
    tick()
    ok(U.open.uninstall, "UNINSTALL: the confirm window (id uninstall)")
    eq(U.byId["un.title"].text, "UNINSTALL WHISTLE EMOTE MUTE 0.2.1?", "UNINSTALL: the title")
    eq(U.byId["un.line"].text, "REMOVES ITS FILES AND ITS MODS.TXT LINE", "UNINSTALL: the line")
    ok(U.byId["un.ok"].kind == "button" and U.byId["un.ok"].label == "UNINSTALL" and U.byId["un.ok"].visible, "UNINSTALL: its button (core's: keys and a gamepad reach it and BACK)")
    eq(#lines("^%[ModManager%] UNINSTALL ask nuclearnightmare%-community%.whistle%-mute$"), 1, "UNINSTALL ask")
    eq(F.unstages, nil, "UNINSTALL: nothing before the confirm")
    U.click("un.ok") tick()
    ok(not U.open.uninstall, "UNINSTALL: the confirm closes")
    ok(F.unstaged and F.unstaged.id == NNC .. "whistle-mute" and F.unstaged.version == "0.2.1", "UNINSTALL: core.catalog.unstage(id, version)")
    eq(#lines("^%[ModManager%] UNINSTALL stage job=201$"), 1, "UNINSTALL stage")
    eq(U.byId["dt.uninstall"].enabled, false, "UNINSTALL: disabled while it runs")
    tick()
    eq(#lines("UNINSTALL done"), 0, "UNINSTALL: polled, running")
    tick()
    eq(#lines("^%[ModManager%] UNINSTALL done outcome=ok txn=fedcba9876543210fedcba9876543210 files=3 kept=1$"), 1, "UNINSTALL done")
    eq(A.calls.start, 1, "UNINSTALL: core.apply.start()")
    eq(U.byId["bw.status"].text, "WHISTLE EMOTE MUTE IS REMOVED WHEN THE GAME RESTARTS", "UNINSTALL: the message")
    eq(U.byId["bw.r" .. n .. ".st"].text, "PENDING RESTART", "UNINSTALL: the row reads PENDING RESTART")
    eq(U.byId["dt.uninstall"].visible, false, "UNINSTALL: Details has no UNINSTALL any more")
    ok(U.byId.restart.visible and U.byId.quit.visible, "UNINSTALL: RESTART NOW and QUIT GAME show")
    eq(W.async, 0, "UNINSTALL: never LoopAsync or ExecuteInGameThread")
    eq(#lines("WARN"), 0, "UNINSTALL: no WARN")
    endSession()
end

do -- UNINSTALL: BACK stages nothing; refusals; from the revoked window; the poll cap.
    local core, U, F = revSession{ unstagePoll = unstageOk(), stagePoll = stageOk({}) }
    U = openBrowse(core)
    U.click("bw.r" .. rowNamed(U, "Whistle Emote Mute") .. ".det") tick()
    U.click("dt.uninstall") tick()
    U.back("uninstall") tick()
    eq(#lines("^%[ModManager%] UNINSTALL cancel nuclearnightmare%-community%.whistle%-mute %(close%)$"), 1, "BACK: cancelled, logged")
    U.click("un.ok") tick()
    eq(F.unstages, nil, "BACK: a stale confirm click unstages nothing")
    endSession()
    for _, c in ipairs({ { "not-in-catalog", "UNINSTALL REFUSED (not-in-catalog)" }, { "changed", "UNINSTALL REFUSED (changed)" }, { "error", "UNINSTALL FAILED" } }) do
        local core2, U2, _, A2 = revSession{ unstagePoll = function() return "done", { outcome = c[1], message = "why", payload = {} } end, stagePoll = stageOk({}) }
        U2 = openBrowse(core2)
        local n = rowNamed(U2, "Whistle Emote Mute")
        U2.click("bw.r" .. n .. ".det") tick()
        U2.click("dt.uninstall") tick()
        U2.click("un.ok") tick() tick()
        eq(U2.byId["bw.status"].text, c[2], c[1] .. ": the message")
        eq(#lines("^%[ModManager%] UNINSTALL done outcome=" .. c[1]:gsub("%-", "%%-") .. " txn=%- files=0 kept=0$"), 1, c[1] .. ": UNINSTALL done")
        eq(A2.calls.start, 0, c[1] .. ": no helper")
        ok(U2.byId["dt.uninstall"].visible and U2.byId["dt.uninstall"].enabled, c[1] .. ": UNINSTALL offered again")
        endSession()
    end
    for _, c in ipairs({ { "busy", "CATALOG BUSY" }, { "applying", "UNINSTALL REFUSED (applying)" }, { "interrupted", "UNINSTALL REFUSED (interrupted)" } }) do
        local core2, U2 = revSession{ unstage = function() return nil, c[1] end, unstagePoll = unstageOk(), stagePoll = stageOk({}) }
        U2 = openBrowse(core2)
        U2.click("bw.r" .. rowNamed(U2, "Whistle Emote Mute") .. ".det") tick()
        U2.click("dt.uninstall") tick()
        U2.click("un.ok") tick()
        eq(U2.byId["bw.status"].text, c[2], "unstage nil, " .. c[1] .. ": the message")
        eq(#lines("^%[ModManager%] UNINSTALL stage job=" .. c[1] .. "$"), 1, "unstage nil, " .. c[1] .. ": logged")
        endSession()
    end
    -- from the revoked window: UNINSTALL a revoked mod
    core, U, F = revSession{ unstagePoll = function() return "done", { outcome = "ok", message = "", payload = { txn = TXN,
        owners = { { id = NNC .. "hud-clock", version = "0.3.0", name = "HudClock", files = 2, kept = 0 } }, ops = 3 } } end, stagePoll = stageOk({}) }
    U.click("tn.review") tick()
    U.click("rv.r1.un") tick()
    eq(U.byId["un.title"].text, "UNINSTALL HUD CLOCK 0.3.0?", "revoked window: UNINSTALL opens its confirm")
    U.click("un.ok") tick() tick()
    eq(F.unstaged.version, "0.3.0", "revoked window: the revoked version unstaged")
    eq(U.byId["rv.msg"].text, "HUD CLOCK IS REMOVED WHEN THE GAME RESTARTS", "revoked window: the message")
    eq(#lines("^%[ModManager%] NOTICE removed$"), 1, "revoked window: resolved, NOTICE removed")
    endSession()
    -- a poll that never finishes: 10 minutes, then UNINSTALL FAILED
    core, U, F = revSession{ unstagePoll = function() return "running" end, stagePoll = stageOk({}) }
    U = openBrowse(core)
    U.click("bw.r" .. rowNamed(U, "Whistle Emote Mute") .. ".det") tick()
    U.click("dt.uninstall") tick()
    U.click("un.ok") tick()
    for _ = 1, 2400 do tick() end
    eq(U.byId["bw.status"].text, "UNINSTALL FAILED", "poll cap: UNINSTALL FAILED after 10 minutes")
    endSession()
end

do -- UNINSTALL refused while an installed or staged mod needs it: no confirm, the names capped at 4.
    local ms = {}
    for i = 1, 6 do ms["Needs" .. i] = modJson("x.needs" .. i, "1.0.0", { NNC .. "whistle-mute" }) end
    local core, U, F = revSession{ mods = ms, unstagePoll = unstageOk(), stagePoll = stageOk({}) }
    U = openBrowse(core)
    U.click("bw.r" .. rowNamed(U, "Whistle Emote Mute") .. ".det") tick()
    U.click("dt.uninstall") tick()
    ok(not U.open.uninstall, "needed: no confirm")
    eq(U.byId["bw.status"].text, "CAN'T UNINSTALL WHISTLE EMOTE MUTE: NEEDED BY NEEDS1, NEEDS2, NEEDS3, NEEDS4 AND 2 MORE", "needed: the names, at most 4, then AND 2 MORE")
    eq(#lines("^%[ModManager%] UNINSTALL refuse nuclearnightmare%-community%.whistle%-mute needed%-by=x%.needs%d,x%.needs%d,x%.needs%d,x%.needs%d,x%.needs%d,x%.needs%d$"), 1, "needed: UNINSTALL refuse with the ids")
    eq(F.unstages, nil, "needed: nothing unstaged")
    endSession()
    -- a staged mod that needs it (installed this session)
    local pk = { id = "x.uses", name = "Uses", kind = "mod", description = "Uses the mute.", categories = { "audio" }, versions = { { version = "1.0.0", scope = "client",
        game = { version = "V8.2.3", build = "26601774" }, dependsOn = { { id = NNC .. "whistle-mute", version = ">=0.2.0" } }, sha256 = A64, size = 10 } } }
    core, U, F = revSession{ payload = revPayload{ extra = { pk } }, unstagePoll = unstageOk(), stagePoll = stageOk({ "x.uses" }) }
    U = openBrowse(core)
    U.click("bw.r" .. rowNamed(U, "Uses") .. ".inst") tick()
    U.click("in.ok") tick() tick()
    U.click("bw.r" .. rowNamed(U, "Whistle Emote Mute") .. ".det") tick()
    U.click("dt.uninstall") tick()
    eq(U.byId["bw.status"].text, "CAN'T UNINSTALL WHISTLE EMOTE MUTE: NEEDED BY USES", "needed by a staged mod: refused")
    eq(F.unstages, nil, "needed by a staged mod: nothing unstaged")
    endSession()
end

io.stdout:write(("main_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
