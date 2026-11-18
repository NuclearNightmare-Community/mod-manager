-- Load test for the test driver (test/ModManagerDriver/Scripts/main.lua) outside the game: for every scenario it loads,
-- builds its steps, registers one game-thread loop and runs a few ticks against an empty fake world (no player
-- controller yet) without a step throwing. The scenarios themselves only run in game (run.ps1).
-- Run from the repo root:  texlua test/unit/driver_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
local DIR = ROOT .. "/test/ModManagerDriver/Scripts"
local MAIN = DIR .. "/main.lua"

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end

local printed, loops, shared = {}, {}, {}
print = function(s) printed[#printed + 1] = (tostring(s):gsub("\n$", "")) end
local INVALID = { IsValid = function() return false end }
function FindFirstOf() return INVALID end
function FindAllOf() return nil end
function StaticFindObject() return INVALID end
function LoopInGameThreadWithDelay(ms, fn) loops[#loops + 1] = { ms = ms, fn = fn } return #loops end
function CancelDelayedAction() return true end
function LoopAsync() error("driver must not use LoopAsync") end
-- core story 35: the pop-in sampler's creation callback and per-frame chain
local notifies, frames = {}, {}
function NotifyOnNewObject(cls, fn) notifies[#notifies + 1] = { cls = cls, fn = fn } end
function ExecuteInGameThreadAfterFrames(n, fn)
    assert(math.type(n) == "integer" and type(fn) == "function", "ExecuteInGameThreadAfterFrames(integer, function)")
    frames[#frames + 1] = fn
    return #frames
end
local function frame() local q = frames; frames = {}; for _, f in ipairs(q) do f() end end
ModRef = { SetSharedVariable = function(_, k, v) shared[k] = v end, GetSharedVariable = function(_, k) return shared[k] end }

local scenarioFile = DIR .. "/scenario.txt"
for _, sc in ipairs({ "screen", "no-core", "old-core" }) do
    printed, loops, notifies = {}, {}, {}
    local f = assert(io.open(scenarioFile, "w")); f:write(sc); f:close()
    local okL, err = pcall(dofile, MAIN)
    ok(okL, sc .. ": loads", err)
    local loaded, scen
    for _, l in ipairs(printed) do
        if l:find("^%[ModManagerDriver%] LOADED %d+ steps$") then loaded = l end
        if l == "[ModManagerDriver] SCENARIO " .. sc then scen = l end
    end
    ok(scen ~= nil, sc .. ": logs its scenario")
    ok(loaded ~= nil and tonumber(loaded:match("(%d+) steps")) >= 1, sc .. ": builds steps", loaded)
    ok(#loops == 1 and loops[1].ms == 250, sc .. ": one 250 ms game-thread loop")
    if loops[1] then
        for _ = 1, 10 do local okT, e = pcall(loops[1].fn); ok(okT, sc .. ": tick runs", e) end
    end
    local threw = false
    for _, l in ipairs(printed) do if l:find("threw") then threw = true end end
    ok(not threw, sc .. ": no step threw")
    local menuNotifies = 0
    for _, n in ipairs(notifies) do if n.cls == "/Game/Graphics/MainMenu/MainMenu.MainMenu_C" then menuNotifies = menuNotifies + 1 end end
    ok(menuNotifies == (sc == "screen" and 1 or 0), sc .. ": the pop-in sampler's creation callback only in screen", menuNotifies)
end

-- ---------------------------------------------------------------- the pop-in sampler (core story 35) against a fake menu
local function lines(pat) local n = 0 for _, l in ipairs(printed) do if l:find(pat) then n = n + 1 end end return n end
local function fname(s) return { ToString = function() return s end } end
local function newMenuFake(path)
    local m = { alive = true, inVp = true, op = 1, page = 0, kids = {} }
    local function valid(o) return function() return o.alive ~= false end end
    m.IsValid = valid(m)
    function m:IsInViewport() return self.inVp end
    function m:GetRenderOpacity() return self.op end
    m.WidgetTree = { RootWidget = { GetActiveWidgetIndex = function() return m.page end } }
    m.VerticalBox_104 = { op = 1, IsValid = function() return true end }
    function m.VerticalBox_104:GetRenderOpacity() return self.op end
    function m.VerticalBox_104:GetChildrenCount() return #m.kids end
    function m.VerticalBox_104:GetChildAt(i) return m.kids[i + 1] end
    m.Overlay_0 = { vis = 1, IsValid = function() return true end }
    function m.Overlay_0:GetVisibility() return self.vis end
    function m:GetFullName() return "MainMenu_C " .. path end
    for _, nm in ipairs({ "UI_Button_Master", "UI_Button_Master_2", "UI_Button_Master_3" }) do
        m.kids[#m.kids + 1] = { IsValid = function() return true end, GetFName = function() return fname(nm) end,
            ButtonText = { GetText = function() return fname(nm) end } }
    end
    return m
end
local function addEntry(m)
    table.insert(m.kids, 3, { IsValid = function() return true end, GetFName = function() return fname("UI_Button_Master_C_7") end,
        ButtonText = { GetText = function() return fname("MANAGE MODS") end } })
end
local objects = {}
StaticFindObject = function(p) return objects[p] or INVALID end
printed, loops, notifies, frames = {}, {}, {}, {}
local fs = assert(io.open(scenarioFile, "w")); fs:write("screen"); fs:close()
dofile(MAIN)
os.remove(scenarioFile)
local notify = notifies[1] and notifies[1].fn
ok(notify ~= nil, "pop-in: the creation callback is registered")
if notify then
    -- a template and the class default object: ignored
    notify(newMenuFake("/Game/Graphics/MainMenu/MainMenu.Default__MainMenu_C"))
    notify(newMenuFake("/Game/Graphics/MainMenu/MainMenu.MainMenu_C:WidgetTree.x"))
    ok(#frames == 0, "pop-in: templates and the CDO are not sampled", #frames)
    -- a menu gone before it reached the viewport: skipped, no check
    notify(newMenuFake("/Engine/Transient.GI.MainMenu_C_0"))
    frame()
    ok(lines("POPIN skipped MainMenu_C_0: never in the viewport %(menu gone%)") == 1 and lines("NOPOPIN") == 0, "pop-in: a menu gone at once is skipped")
    -- menu1: Overlay_0 collapsed, then the column hidden (core's hold), then the entry in and shown: no pop-in
    local p1 = "/Engine/Transient.GI.MainMenu_C_1"
    local m1 = newMenuFake(p1); objects[p1] = m1
    notify(m1)
    frame(); frame()
    m1.Overlay_0.vis = 0; m1.VerticalBox_104.op = 0
    frame(); frame()
    addEntry(m1)
    frame()
    ok(#frames == 1, "pop-in: hidden column -> still sampling")
    m1.VerticalBox_104.op = 1
    frame()
    ok(#frames == 0 and lines("OK NOPOPIN menu1 ") == 1 and lines("POPIN menu1 frames=6 visible=1 pop=0 ") == 1, "pop-in: menu1 judged with no pop-in", printed[#printed])
    ok(lines("HIDDENFIRST menu1") == 0 and lines("POPIN menu1 .* hidden=3 overlay=3 entry=5 ") == 1, "pop-in: menu1 logs hidden/overlay/entry frames, no HIDDENFIRST check", printed[#printed - 1])
    -- menu2: the column drawn without the entry for two frames, never hidden: FAIL NOPOPIN and FAIL HIDDENFIRST menu2
    local p2 = "/Engine/Transient.GI.MainMenu_C_2"
    local m2 = newMenuFake(p2); objects[p2] = m2
    m2.Overlay_0.vis = 0
    notify(m2)
    frame(); frame()
    addEntry(m2)
    frame()
    ok(lines("FAIL NOPOPIN menu2 .*%(2 of 3 visible frames did, 0 unreadable; entry in a drawn column: true%)") == 1
        and lines("POPIN menu2 frames=3 visible=3 pop=2 firstPop=1 unreadable=0 hidden=nil overlay=1 entry=3 %(entry in%)") == 1, "pop-in: menu2 pop-in counted and failed", printed[#printed - 2])
    ok(lines("FAIL HIDDENFIRST menu2 the column was hidden %(frame nil%) on or before Overlay_0 was first drawn %(frame 1%)") == 1, "pop-in: menu2 never hidden -> HIDDENFIRST fails")
    -- menu3: hidden (another page) until the time-out: the entry never seen in a drawn column -> FAIL; the sampler stops
    local p3 = "/Engine/Transient.GI.MainMenu_C_3"
    local m3 = newMenuFake(p3); objects[p3] = m3
    m3.Overlay_0.vis = 0; m3.page = 2
    notify(m3)
    frame()
    local clock0 = os.clock
    os.clock = function() return clock0() + 25 end
    frame()
    os.clock = clock0
    ok(#frames == 0 and lines("FAIL NOPOPIN menu3 .*entry in a drawn column: false%)") == 1 and lines("POPIN menu3 .*%(time%-out%)") == 1, "pop-in: time-out without the entry drawn fails, chain stopped", printed[#printed])
    -- menu4: core's hide before Overlay_0 is drawn, then the entry: OK NOPOPIN and OK HIDDENFIRST menu4
    local p4 = "/Engine/Transient.GI.MainMenu_C_4"
    local m4 = newMenuFake(p4); objects[p4] = m4
    notify(m4)
    frame()
    m4.VerticalBox_104.op = 0
    frame()
    m4.Overlay_0.vis = 0
    frame()
    addEntry(m4); m4.VerticalBox_104.op = 1
    frame()
    ok(lines("OK NOPOPIN menu4 ") == 1 and lines("OK HIDDENFIRST menu4 the column was hidden %(frame 2%) on or before Overlay_0 was first drawn %(frame 3%)") == 1, "pop-in: menu4 hidden first passes", printed[#printed])
    -- menu5: frames in the viewport with an unreadable column opacity count against it
    local p5 = "/Engine/Transient.GI.MainMenu_C_5"
    local m5 = newMenuFake(p5); objects[p5] = m5
    m5.Overlay_0.vis = 0
    local cop = m5.VerticalBox_104.GetRenderOpacity
    m5.VerticalBox_104.GetRenderOpacity = function() error("unreadable") end
    notify(m5)
    frame(); frame()
    m5.VerticalBox_104.GetRenderOpacity = cop
    addEntry(m5)
    frame()
    ok(lines("FAIL NOPOPIN menu5 .*0 of 1 visible frames did, 2 unreadable") == 1 and lines("POPIN menu5 .*unreadable=2 ") == 1, "pop-in: unreadable frames fail", printed[#printed - 2])
end
StaticFindObject = function() return INVALID end
-- old-core reads the claimed version from the installed core's mod.json, two folders up (Mods/Nucleus/mod.json);
-- here there's none, so it says so as a FAIL line instead of publishing anything.
ok(shared["nucleus.version"] == nil, "old-core without a core mod.json publishes nothing")
os.remove(scenarioFile)
-- An unknown scenario ends at once with a FAIL line.
printed, loops = {}, {}
local f = assert(io.open(scenarioFile, "w")); f:write("bogus"); f:close()
dofile(MAIN)
os.remove(scenarioFile)
local ended = false
for _, l in ipairs(printed) do if l:find("END result=FAIL .*unknown%-scenario bogus") then ended = true end end
ok(ended and #loops == 0, "unknown scenario: END FAIL, no loop")

io.stdout:write(("driver_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
