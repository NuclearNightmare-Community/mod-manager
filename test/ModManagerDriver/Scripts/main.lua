-- ModManagerDriver: the Mod Manager's test driver (story 3). Installed only by deploy.ps1 -Test, never shipped. Plain
-- UE4SS Lua: it doesn't connect to core (no-core runs without it), and it can't reach the Mod Manager's Lua state, so
-- it judges what is on screen: the entry in the menu's column, the windows (core's WBP_<Core>Screen widgets) and their
-- elements, found by core's tags (a text's ToolTipText, every other kind's CoreTag: "<core>:ModManager:<id>").
-- Clicks, the wheel and screenshots are asked of run.ps1 (or the VM runner) through request.txt / done.txt next to
-- this file; points are desktop pixels from core's geometry natives on its ModActor CDO.
--
-- mods.txt order (deploy.ps1): <Core>, ModManagerDriver, ModManager.
--
-- Scenarios (Scripts/scenario.txt, written by deploy.ps1):
--   screen:   the entry; the main window's rows (ROW lines, need and build read from each row's Configure window);
--             MEASURE of the long name; inert toggle boxes (INERT); Configure on top of the main window, a dimmed
--             gear's Configure, the main window's Close blocked under it; closes; Tower Island and back; the entry
--             again, the same rows (DW-59); END.
--   no-core:  (run.ps1 moves core aside) the menu has no MANAGE MODS entry.
--   old-core: (run.ps1 sets core's installed mod.json to 0.1.0) publishes that version as <core>.version before the
--             Mod Manager connects, as an old core would; the menu has no MANAGE MODS entry.
-- Never keeps a UObject across steps: widgets are found again by tag every time.
local CORE = "Nucleus"      -- core's name: the one place the driver spells it
local MOD = "ModManager"    -- the Mod Manager's connect name (its log tag and its tags' mod part)
local ME = "ModManagerDriver"
local ENTRY_LABEL = "MANAGE MODS"
local scriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)[/\\]")

local function say(fmt, ...) print("[" .. ME .. "] " .. string.format(fmt, ...) .. "\n") end
local function firstLine(e) return (tostring(e):match("^[^\n]*")) end

local SCENARIO = "screen"
do
    local f = io.open(scriptDir .. "\\scenario.txt", "r")
    if f then SCENARIO = (f:read("*a") or ""):match("^%s*([%w%-]+)") or SCENARIO; f:close() end
end
say("SCENARIO %s", SCENARIO)

-- old-core: an old core publishes its own version. The installed core's mod.json says what version to pretend.
if SCENARIO == "old-core" then
    local modsDir = scriptDir:match("^(.*)[/\\][^/\\]+[/\\][Ss]cripts$")
    local f = io.open(modsDir .. "\\" .. CORE .. "\\mod.json", "r")
    local claimed = f and (f:read("*a") or ""):match('"version"%s*:%s*"([^"]+)"')
    if f then f:close() end
    if claimed then
        ModRef:SetSharedVariable(CORE:lower() .. ".version", claimed)
        say("OLDCORE published %s.version=%s (from %s's installed mod.json)", CORE:lower(), claimed, CORE)
    else
        say("FAIL OLDCORE could not read the version from %s's installed mod.json", CORE)
    end
end

local REQ, DONE = scriptDir .. "\\request.txt", scriptDir .. "\\done.txt"
os.remove(REQ); os.remove(DONE)

local MENU_MAP = "/Game/Maps/NewMainMenu"
local MATCH_MAP = "/Game/Maps/SmallLoweIsland/SmallMap"
local W = "WBP_" .. CORE
local TEXT_S, SCREEN_S = W .. "Text_C", W .. "Screen_C"
local TAG = CORE:lower() .. ":" .. MOD .. ":"
local ACTOR_CDO = "/Game/Mods/" .. CORE .. "/ModActor.Default__ModActor_C"
local TEMPLATE = { UI_Button_Master = true, UI_Button_Master_1 = true, UI_Button_Master_6 = true, UI_Button_Master_2 = true, UI_Button_Master_3 = true }
local DIM = { 0.36, 0.41, 0.43, 0.55 } -- core's dimmed colour (the game's disabled text colour)
local VIS_VISIBLE, VIS_COLLAPSED, VIS_HIDDEN, VIS_HTI = 0, 1, 2, 3
local TEX = { T_CheckboxOn = "on", T_CheckboxOff = "off", T_Lock = "lock" }

local S = { failures = 0, checks = 0 }

-- ---------------------------------------------------------------- helpers
local function v(o)
    if o == nil then return false end
    local ok, y = pcall(function() return o:IsValid() end)
    return ok and y == true
end
local function try(fn) local ok, r = pcall(fn) if ok then return r end return nil end
local function fname(w) if not v(w) then return "?" end return try(function() return w:GetFName():ToString() end) or "?" end
local function cname(w) if not v(w) then return "?" end return try(function() return w:GetClass():GetFName():ToString() end) or "?" end
local function prop(o, k) if not v(o) then return nil end local p = try(function() return o[k] end) return v(p) and p or nil end
local function check(cond, fmt, ...)
    S.checks = S.checks + 1
    if not cond then S.failures = S.failures + 1 end
    say("%s " .. fmt, cond and "OK" or "FAIL", ...)
    return cond
end
local function GS() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end
local function WLL() return StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary") end
local function pc() return FindFirstOf("PlayerController") end
local function worldName() local p = pc() return v(p) and (try(function() return p:GetWorld():GetFullName() end) or "") or "" end
local function liveAll(short)
    local out = {}
    for _, w in ipairs(FindAllOf(short) or {}) do
        if v(w) and try(function() return w:IsInViewport() end) then out[#out + 1] = w end
    end
    return out
end
local function liveOf(short) return liveAll(short)[1] end
local function menu() return liveOf("MainMenu_C") end
local function visOf(w) return v(w) and (try(function() return w:GetVisibility() end) or -1) or -1 end
local function scale() local mm = menu() return mm and (try(function() return WLL():GetViewportScale(mm) end) or 1) or 1 end
-- Screen rectangle in desktop pixels from Slate's cached geometry (core's natives), or nil.
local function absR(w)
    local cdo = StaticFindObject(ACTOR_CDO)
    if not (v(cdo) and v(w)) then return nil end
    local ok, r = pcall(function()
        local a, b = cdo[CORE .. "_AbsTopLeft"](cdo, w), cdo[CORE .. "_AbsBottomRight"](cdo, w)
        return { l = a.X, t = a.Y, r = b.X, b = b.Y }
    end)
    if ok and r and r.r > r.l and r.b > r.t then return r end
    return nil
end
local function center(r) return math.floor((r.l + r.r) / 2 + 0.5), math.floor((r.t + r.b) / 2 + 0.5) end
local function rs(r) return r and string.format("(%.0f,%.0f)-(%.0f,%.0f)", r.l, r.t, r.r, r.b) or "?" end

-- A core widget's tag: a text's ToolTipText, every other kind's CoreTag.
local function ctag(w)
    local k = cname(w)
    if k == TEXT_S then return try(function() return w.ToolTipText:ToString() end) end
    if k:sub(1, #W) == W then return try(function() return w.CoreTag:ToString() end) end
    return nil
end
local function childTagged(container, id)
    if not v(container) then return nil end
    local want = TAG .. id
    local n = try(function() return container:GetChildrenCount() end) or 0
    for i = 0, n - 1 do
        local c = try(function() return container:GetChildAt(i) end)
        if v(c) and ctag(c) == want then return c end
    end
    return nil
end
local function textOf(w) return try(function() return w.Text:GetText():ToString() end) end

-- The Mod Manager's windows: a live WBP_<Core>Screen tagged "#screen:<id>", and its canvas.
local function screenOf(id)
    for _, s in ipairs(liveAll(SCREEN_S)) do
        if ctag(s) == TAG .. "#screen:" .. id then return s, prop(s, "Canvas") end
    end
    return nil
end
local function closeOf(id)
    local _, canvas = screenOf(id)
    return childTagged(canvas, "#close:" .. id)
end
local function mainList() local _, c = screenOf("main") return childTagged(c, "list") end
local function rowW(n) return childTagged(prop(mainList(), "VBox"), "r" .. n) end
local function cell(n, part) return childTagged(prop(rowW(n), "HBox"), "r" .. n .. "." .. part) end
local function headerCell(part)
    local _, c = screenOf("main")
    local hl = childTagged(c, "hdr.list")
    return childTagged(prop(childTagged(prop(hl, "VBox"), "hdr"), "HBox"), "hdr." .. part)
end
local function cfgText(part) local _, c = screenOf("configure") return textOf(childTagged(c, "cfg." .. part)) end

local function near4(c, want) return c ~= nil and math.abs(c.R - want[1]) < 0.01 and math.abs(c.G - want[2]) < 0.01 and math.abs(c.B - want[3]) < 0.01 and math.abs(c.A - want[4]) < 0.01 end
-- One row as drawn: name, version, toggle (on | off | lock), gear (lit | dim), status (its icon count: the slot is an
-- empty text in story 3), and its rectangle.
local function readRow(n)
    local r = rowW(n)
    if not r or visOf(r) == VIS_COLLAPSED or visOf(r) == VIS_HIDDEN then return nil end
    local img = prop(cell(n, "on"), "Img")
    local tex = try(function() local o = img.Brush.ResourceObject if v(o) then return fname(o) end return "none" end) or "?"
    local icon = prop(cell(n, "cfg"), "Icon")
    local tint = try(function() return icon.ColorAndOpacity end)
    local st = cell(n, "st")
    local status = 0
    if cname(st) == TEXT_S then status = ((textOf(st) or "") ~= "") and 1 or 0
    else status = try(function() return st:GetChildrenCount() end) or -1 end
    return { n = n, name = textOf(cell(n, "name")) or "?", ver = textOf(cell(n, "ver")) or "?", toggle = TEX[tex] or tex,
        gear = near4(tint, DIM) and "dim" or (tint and "lit" or "?"), status = status, rect = absR(r) }
end
local function readRows()
    local rows = {}
    for n = 1, 256 do
        if not rowW(n) then break end
        local r = readRow(n)
        if r then rows[#rows + 1] = r end
    end
    return rows
end
local function sig(rows)
    local t = {}
    for i, r in ipairs(rows) do t[i] = string.format("%s|%s|%s|%s|%d", r.name, r.ver, r.toggle, r.gear, r.status) end
    return table.concat(t, "\n")
end

-- The entry: the column's child that isn't one of the template's buttons and reads MANAGE MODS.
local function column(mm) return prop(mm, "VerticalBox_104") end
local function buttonText(w) return try(function() return w.ButtonText:GetText():ToString() end) end
local function entryOf(mm)
    local vb = column(mm)
    local n = vb and (try(function() return vb:GetChildrenCount() end) or 0) or 0
    for i = 0, n - 1 do
        local c = try(function() return vb:GetChildAt(i) end)
        if v(c) and not TEMPLATE[fname(c)] and buttonText(c) == ENTRY_LABEL then return c, i end
    end
    return nil
end

-- ---------------------------------------------------------------- requests and steps
local seq = 0
local function request(cmd)
    seq = seq + 1
    local f = io.open(REQ, "w"); f:write(seq .. " " .. cmd); f:close()
    local mine = seq
    return function()
        local d = io.open(DONE, "r")
        if not d then return false end
        local s = d:read("*a"); d:close()
        return tonumber(s) == mine
    end
end
local function after(sec) local t = os.clock() + sec return function() return os.clock() >= t end end

-- The steps run one at a time on the game-thread loop (never in a coroutine: UE4SS calls no UFunction from one). A step
-- returns nothing, or a predicate to wait for (with a time limit; running out logs one FAIL TIMEOUT line). A running
-- step can add steps right after itself (nested), for parts that depend on what it read (one group per row).
local steps = {}
local idx = 0
local target -- where step() appends: the scenario's list, or a nested group being built
local function step(name, fn) local t = target or steps; t[#t + 1] = { name = name, fn = fn } end
local function nested(build)
    local saved = target
    target = {}
    build()
    local list = target
    target = saved
    for k, s in ipairs(list) do table.insert(steps, idx + k, s) end
end
local function waitFor(what, pred, sec) step("wait " .. what, function() return pred, sec, what end) end
local function settle(sec) step("settle", function() return after(sec), sec + 5, "settle" end) end
-- A real click at the centre of the widget finder() returns (re-found when the step runs), then 1.5 s.
local function clickOn(label, finder)
    step("click " .. label, function()
        local r = absR(finder())
        if not check(r ~= nil, "POINT %s has a point to click", label) then return end
        local x, y = center(r)
        say("CLICK %s at (%d,%d)", label, x, y)
        return request(string.format("click %d %d", x, y)), 40, "click " .. label
    end)
    settle(1.5)
end
local function shot(label) step("shot " .. label, function() return request("shot " .. label), 30, "screenshot " .. label end) end

local function travel(phase, map, options)
    step(phase .. ": travel", function()
        say("TRAVEL %s OpenLevel %s%s", phase, map, options ~= "" and ("?" .. options) or "")
        GS():OpenLevel(pc(), FName(map), true, options)
        return after(3), 8, "travel start"
    end)
end
local function waitWorld(phase, part, sec)
    step(phase .. ": world", function()
        return function()
            if worldName():find(part, 1, true) then say("WORLD %s %s", phase, worldName():match("/Game/[^ ]+") or "?") return true end
            return false
        end, sec, phase .. " world " .. part
    end)
end

-- The press-any-key screen takes keys only once it is up: wait for it, a moment, then Enter, again every 15 s until a
-- MainMenu_C exists (the menu spike's way; one early Enter was lost in the VM).
local function pastStartup()
    waitFor("startup screen", function() return liveOf("UI_Startup_C") ~= nil or menu() ~= nil end, 60)
    settle(2)
    step("startup Enter", function()
        if menu() then return end
        say("STARTUP Enter (1)")
        local done, deadline, tries = request("key ENTER"), os.clock() + 15, 1
        return function()
            if menu() then return true end
            if os.clock() > deadline and done() and tries < 4 then
                tries, deadline = tries + 1, os.clock() + 15
                say("STARTUP Enter (%d)", tries)
                done = request("key ENTER")
            end
            return false
        end, 75, "menu after Enter"
    end)
end

-- ---------------------------------------------------------------- the screen scenario
local R = { cfg = {} } -- what earlier steps read, for later ones

local function entryChecks(phase)
    step(phase .. ": entry", function()
        local mm = menu()
        local e, i = entryOf(mm)
        if not check(e ~= nil, "ENTRY %s the column has a %s entry", phase, ENTRY_LABEL) then return end
        local vb = column(mm)
        local above = try(function() return vb:GetChildAt(i - 1) end)
        local below = try(function() return vb:GetChildAt(i + 1) end)
        say("ENTRY %s text=%s above=%s below=%s", phase, tostring(buttonText(e)), tostring(buttonText(above)), tostring(buttonText(below)))
        check(fname(above) == "UI_Button_Master_2" and fname(below) == "UI_Button_Master_3",
            "ENTRYPOS %s between OPTIONS (%s) and QUIT (%s)", phase, fname(above), fname(below))
        local opt = prop(mm, "UI_Button_Master_2")
        local es, os_ = prop(e, "Style"), prop(opt, "Style")
        local function font(b) return try(function() local f = b.ButtonText.Font return fname(f.FontObject) .. "/" .. tostring(f.Size) end) end
        check(es ~= nil and fname(es) == fname(os_) and font(e) == font(opt), "ENTRYLOOK %s style %s / %s font %s / %s (the options style)",
            phase, fname(es), fname(os_), tostring(font(e)), tostring(font(opt)))
    end)
end

local function openMain(phase)
    clickOn("entry " .. phase, function() return (entryOf(menu())) end)
    step("open " .. phase, function()
        return function() return screenOf("main") ~= nil and rowW(1) ~= nil end, 20, "main window " .. phase
    end)
    settle(2) -- textures and layout settle (core applies a missed texture on its next 500 ms tick)
    step("opened " .. phase, function()
        local _, c = screenOf("main")
        check(c ~= nil and rowW(1) ~= nil, "OPEN %s the MOD MANAGER window opened from the entry", phase)
        check(textOf(childTagged(c, "title")) == "MOD MANAGER", "TITLE %s the window's title reads MOD MANAGER (%s)", phase, tostring(textOf(childTagged(c, "title"))))
    end)
end

-- Scrolls the list until row n is inside it (the wheel over the list), at most 10 times.
local function intoView(n, tries)
    tries = tries or 1
    step("view row " .. n, function()
        local rr, lr = absR(rowW(n)), absR(mainList())
        if rr and lr and rr.t >= lr.t - 1 and rr.b <= lr.b + 1 then return end
        if not lr or tries > 10 then check(false, "VIEW row %d can't be scrolled into the list (%s in %s)", n, rs(rr), rs(lr)) return end
        local x, y = center(lr)
        local done = request(string.format("wheel %d %d %d", x, y, (rr and rr.b > lr.b) and -3 or 3))
        nested(function() settle(1) intoView(n, tries + 1) end)
        return done, 30, "wheel"
    end)
end

-- A row's Configure window (nOf: a function giving the row's index when the steps run): open it with the gear and
-- read it into R.cfg[n]; it stays open.
local function configureOf(nOf, label)
    step("view " .. label, function()
        local n = nOf()
        if not check(n ~= nil, "CFGROW %s has a row", label) then return end
        nested(function() intoView(n) end)
    end)
    clickOn("gear " .. label, function() local n = nOf() return n and cell(n, "cfg") end)
    waitFor("Configure for " .. label, function() return screenOf("configure") ~= nil and cfgText("title") ~= nil end, 10)
    settle(0.5)
    step("read Configure " .. label, function()
        local n = nOf()
        if n then R.cfg[n] = screenOf("configure") and { title = cfgText("title"), ver = cfgText("ver"), need = cfgText("need"), build = cfgText("build") } or nil end
    end)
end
local function closeConfigure(label)
    clickOn("Configure's Close " .. label, function() return closeOf("configure") end)
    waitFor("Configure closed " .. label, function() return screenOf("configure") == nil end, 10)
end

local function buildScreen()
    -- 1. The menu and the entry.
    waitWorld("menu1", "NewMainMenu", 120)
    pastStartup()
    waitFor("the entry", function() return menu() ~= nil and entryOf(menu()) ~= nil end, 60)
    settle(3)
    entryChecks("menu1")
    shot("mm-menu")

    -- 2. The rows, each one's Configure data, the long name's measure, a screenshot.
    openMain("first")
    step("rows", function()
        R.rows = readRows()
        R.sig = sig(R.rows)
        check(#R.rows >= 8, "ROWS %d visible rows (at least the 8 the scenario installs)", #R.rows)
        nested(function()
            for _, r in ipairs(R.rows) do
                configureOf(function() return r.n end, r.name)
                step("ROW " .. r.n, function()
                    local d = R.cfg[r.n]
                    local need = d and d.need and d.need:match("^NUCLEUS (.*)$") or "?"
                    local build = d and d.build and d.build:match("^GAME BUILD (.*)$") or "?"
                    check(d ~= nil and d.title == r.name and d.ver == "VERSION " .. r.ver, "CFGDATA %d heading %s, %s", r.n, tostring(d and d.title), tostring(d and d.ver))
                    say("ROW %s | %s | toggle=%s | gear=%s | status=%d | need=%s | build=%s", r.name, r.ver, r.toggle, r.gear, r.status, need, build)
                end)
                closeConfigure(r.name)
            end
        end)
    end)
    -- MEASURE: the long name is cut inside its column, and the header's NAME lines up with the rows' names.
    step("measure", function()
        local long
        for _, r in ipairs(R.rows or {}) do if r.name:sub(1, 14) == "ModManagerLong" then long = r end end
        if not check(long ~= nil, "LONG the ModManagerLong row is listed") then return end
        local sc = scale()
        local nameW, verW, hdrW = cell(long.n, "name"), cell(long.n, "ver"), headerCell("name")
        pcall(function() nameW.Text:ForceLayoutPrepass() end)
        local nr, vr, hr = absR(nameW), absR(verW), absR(hdrW)
        local desired = try(function() return nameW.Text:GetDesiredSize().X end) or -1
        local function u(x) return x and x / sc or -1 end
        local width = nr and (nr.r - nr.l) / sc or -1
        say("MEASURE name width=%.1f desired=%.1f right=%.1f verLeft=%.1f headerLeft=%.1f rowLeft=%.1f",
            width, desired, u(nr and nr.r), u(vr and vr.l), u(hr and hr.l), u(nr and nr.l))
        check(desired > width and width > 0, "MEASURECUT the long name's desired width %.1f is over its column's %.1f (cut with an ellipsis)", desired, width)
        check(nr ~= nil and vr ~= nil and nr.r <= vr.l + 0.5, "MEASUREEDGE the name's right edge %s is left of the version column %s (desktop px)", rs(nr), rs(vr))
        check(nr ~= nil and hr ~= nil and math.abs(nr.l - hr.l) / sc <= 1, "MEASUREALIGN the header's NAME starts within 1 unit of the row's name (%s vs %s)", rs(hr), rs(nr))
        return request("move 5 5"), 30, "cursor away" -- for the screenshot
    end)
    settle(1)
    shot("mm-main")

    -- 3. The toggle boxes are inert: a click on a box and on Nucleus's lock changes nothing, writes nothing, logs nothing.
    step("inert: begin", function()
        for _, r in ipairs(R.rows or {}) do
            if r.name == "ModManagerFixture" then R.fixture = r.n end
            if r.name == CORE then R.nucleus = r.n end
        end
        check(R.fixture ~= nil and R.nucleus ~= nil, "INERTROWS the fixture's and Nucleus's rows found")
        R.before = sig(readRows())
        say("INERT begin")
    end)
    -- Each row into the list's view first (step 2 may have scrolled it), as the Configure steps do.
    local function viewRow(nOf, label)
        step("view " .. label, function() local n = nOf() if n then nested(function() intoView(n) end) end end)
    end
    viewRow(function() return R.fixture end, "the fixture's toggle box")
    clickOn("the fixture's toggle box", function() return R.fixture and cell(R.fixture, "on") end)
    viewRow(function() return R.nucleus end, "Nucleus's lock")
    clickOn("Nucleus's lock", function() return R.nucleus and cell(R.nucleus, "on") end)
    settle(1)
    step("inert: end", function()
        say("INERT end")
        local now = sig(readRows())
        check(now == R.before and screenOf("configure") == nil and screenOf("main") ~= nil and visOf(screenOf("main")) == VIS_VISIBLE,
            "INERT the toggle boxes changed nothing on screen (rows the same: %s, no Configure, main window on top)", tostring(now == R.before))
    end)

    -- 4. Configure on top of the main window; Close; a dimmed gear opens Configure too.
    local function fixture() return R.fixture end
    local function nucleus() return R.nucleus end
    configureOf(fixture, "fixture")
    step("configure: on top", function()
        local d = R.cfg[R.fixture or 0]
        local mainS, cfgS = screenOf("main"), screenOf("configure")
        check(cfgS ~= nil and visOf(cfgS) == VIS_VISIBLE and visOf(mainS) == VIS_HTI, "CFGTOP Configure on top (Visible), the main window below takes no input (%s, %s)", tostring(visOf(cfgS)), tostring(visOf(mainS)))
        check(d ~= nil and d.title == "ModManagerFixture" and d.ver == "VERSION 9.9.9" and d.need == "NUCLEUS >=0.1.0" and d.build == "GAME BUILD V0.0.0 1",
            "CFGFIXTURE heading %s | %s | %s | %s", tostring(d and d.title), tostring(d and d.ver), tostring(d and d.need), tostring(d and d.build))
    end)
    shot("mm-configure")
    closeConfigure("fixture")
    step("configure: closed", function()
        check(screenOf("configure") == nil and visOf(screenOf("main")) == VIS_VISIBLE, "CFGCLOSE Configure's Close closed it; the main window takes input again")
        local row = R.nucleus and readRow(R.nucleus)
        check(row ~= nil and row.gear == "dim", "CFGDIM Nucleus's gear is dimmed (%s)", row and row.gear or "?")
        R.cfg[R.nucleus or 0] = nil
    end)
    configureOf(nucleus, "Nucleus (dimmed gear)")
    step("configure: dimmed", function()
        local d = R.cfg[R.nucleus or 0]
        check(d ~= nil and d.title == CORE and d.need == "NUCLEUS -", "CFGDIMOPEN the dimmed gear opened Configure like a lit one (%s, %s)", tostring(d and d.title), tostring(d and d.need))
    end)
    closeConfigure("Nucleus")
    configureOf(fixture, "fixture again")
    -- 5. The main window under Configure takes no input. Its gears: a click on Nucleus's gear, under Configure's
    -- backdrop, changes nothing. Its Close: core puts every window's Close at the same top-right spot, so Configure's
    -- own Close covers it and a click there can only reach Configure's; had it reached the main window's Close, both
    -- windows would close (a Close closes the windows above too). So the main window must still be open after it.
    clickOn("Nucleus's gear under Configure", function() return R.nucleus and cell(R.nucleus, "cfg") end)
    settle(1)
    step("blocked gear", function()
        check(screenOf("configure") ~= nil and cfgText("title") == "ModManagerFixture" and screenOf("main") ~= nil,
            "BLOCKEDGEAR a click on the main window's gear under Configure changed nothing (Configure still shows %s)", tostring(cfgText("title")))
    end)
    clickOn("the main window's Close under Configure", function() return closeOf("main") end)
    settle(1)
    step("blocked", function()
        check(screenOf("main") ~= nil and visOf(screenOf("main")) == VIS_VISIBLE,
            "BLOCKED the main window's Close did not act under Configure: the main window is still open (the click reached the top window's own Close: Configure open=%s)", tostring(screenOf("configure") ~= nil))
    end)
    -- 6. Configure's Close (if the click above didn't already), then the main window's Close: the menu with the entry.
    step("configure: close if open", function()
        if screenOf("configure") then nested(function() closeConfigure("before the main window's") end) end
    end)
    step("configure: closed again", function()
        check(screenOf("configure") == nil and visOf(screenOf("main")) == VIS_VISIBLE, "CFGCLOSE2 Configure closed; the main window takes input again")
    end)
    clickOn("the main window's Close", function() return closeOf("main") end)
    waitFor("main window closed", function() return screenOf("main") == nil end, 10)
    settle(1)
    step("menu back", function()
        check(screenOf("main") == nil, "CLOSEMAIN the main window closed")
        local mm = menu()
        check(mm ~= nil and entryOf(mm) ~= nil and #liveAll(SCREEN_S) == 0, "MENUBACK the menu is shown with the entry, no window left")
    end)

    -- 7.-9. Tower Island and back; the entry again opens the same rows (DW-59: the open from a click after a match).
    travel("match", MATCH_MAP, "listen")
    waitWorld("match", "SmallMap", 150)
    settle(6)
    travel("menu2", MENU_MAP, "")
    waitWorld("menu2", "NewMainMenu", 150)
    waitFor("menu2 with the entry", function() return menu() ~= nil and entryOf(menu()) ~= nil end, 60)
    settle(3)
    step("menu2: entry back", function() check(entryOf(menu()) ~= nil, "ENTRYUP2 the entry is back after the match") end)
    entryChecks("menu2")
    openMain("after the match")
    step("same rows", function()
        local rows = readRows()
        local same = sig(rows) == R.sig
        check(same, "SAME the window after the match lists the same %d rows (%d now)", R.rows and #R.rows or -1, #rows)
        if not same then say("SAME before: %s", tostring(R.sig):gsub("\n", " / ")) say("SAME now: %s", (sig(rows):gsub("\n", " / "))) end
    end)
    shot("mm-reopen")
    clickOn("the main window's Close (end)", function() return closeOf("main") end)
    waitFor("main window closed at the end", function() return screenOf("main") == nil end, 10)
    step("closed at the end", function() check(screenOf("main") == nil, "CLOSEEND the main window closed") end)
end

-- ---------------------------------------------------------------- no-core and old-core: no entry
local function buildNoEntry()
    waitWorld("menu1", "NewMainMenu", 120)
    pastStartup()
    step("menu1: up", function() check(menu() ~= nil, "STARTUP the title-screen menu is up") end)
    step("menu1: no entry", function()
        local seen, untilT = false, os.clock() + 15
        return function()
            if entryOf(menu()) then seen = true end
            if os.clock() < untilT then return false end
            check(not seen, "NOENTRY no %s entry in the menu for 15 s", ENTRY_LABEL)
            return true
        end, 25, "watch for an entry"
    end)
end

-- ---------------------------------------------------------------- runner (game thread, every 250 ms)
local waiting, busy, finished = nil, false, false
local function finish()
    finished = true
    say("END result=%s checks=%d failures=%d", (S.failures == 0 and S.checks > 0) and "PASS" or "FAIL", S.checks, S.failures)
end
local function tick()
    if busy or finished then return end
    busy = true
    local ok, err = pcall(function()
        if waiting then
            if not waiting.pred() then
                if os.clock() <= waiting.deadline then return end
                check(false, "TIMEOUT %s", waiting.what)
            end
            waiting = nil
        end
        idx = idx + 1
        local s = steps[idx]
        if not s then finish() return end
        local pred, timeout, what = s.fn()
        if pred then waiting = { pred = pred, deadline = os.clock() + (timeout or 10), what = what or s.name } end
    end)
    if not ok then
        check(false, "STEP '%s' threw: %s", steps[idx] and steps[idx].name or "?", firstLine(err))
        waiting = nil
    end
    busy = false
end

local build = ({ screen = buildScreen, ["no-core"] = buildNoEntry, ["old-core"] = buildNoEntry })[SCENARIO]
if not build then
    say("END result=FAIL checks=0 failures=1 reason=unknown-scenario %s", SCENARIO)
    return
end
build()
-- A game-thread loop (never LoopAsync + ExecuteInGameThread: the pinned UE4SS can lose those callbacks).
local runner
local okL, res = pcall(LoopInGameThreadWithDelay, 250, function()
    tick()
    if finished and runner then pcall(CancelDelayedAction, runner); runner = nil end
end)
if okL then runner = res else say("END result=FAIL checks=0 failures=1 reason=loop %s", tostring(res)) end
say("LOADED %d steps", #steps)
