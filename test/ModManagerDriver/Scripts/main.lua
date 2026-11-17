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
--   screen:   the entry; the main window's rows (ROW lines with the toggle, its box, the status icons; the gear, need
--             and build from each row's Configure window: gear=dim when it shows NO SETTINGS, lit when it lists
--             settings; GEARLOOK: the gear drawn that way, judged only when it doesn't hold keyboard focus); one DOWN
--             right after the first open and a focus shot; MEASURE of the long name; CARDFIT (the content inside the
--             card, the list above BACK); story 6: Dep off and on with mods.txt and state.json read back, Base off
--             through the confirm (BACK, then TURN OFF), the restart and dependency icons, the banner and QUIT GAME
--             (CARDFIT2), Nucleus's lock and a pak's disabled box changing nothing (FIXED); the fixture's Configure:
--             its problem lines, its settings' controls, a checkbox click, a choice arrow, a typed slider value, the
--             restart setting, settings.json read back; Configure on top of the main window, a dimmed gear's Configure,
--             the main window's Close blocked under it; closes; Tower Island and back; the entry again, the same rows
--             (DW-59); END; then QUIT GAME, which closes the game.
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
local TEX = { T_CheckboxOn = "on", T_CheckboxOff = "off", T_Lock = "lock", checkbox_ticked = "on", checkbox_unticked = "off" }
local STATUS_TEX = { T_Warning = "warning", T_Restart = "restart" }

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
-- Story 6: the main window's own elements (quit, banner, msg), Configure's, and its settings rows (s<i>.<part>).
local function mainEl(id) local _, c = screenOf("main") return childTagged(c, id) end
local function cfgEl(part) local _, c = screenOf("configure") return childTagged(c, "cfg." .. part) end
local function setRow(i) return childTagged(prop(cfgEl("list"), "VBox"), "s" .. i) end
local function setCell(i, part) return childTagged(prop(setRow(i), "HBox"), "s" .. i .. "." .. part) end
-- The files the Mod Manager writes, read back (relative to ue4ss/Mods; read only).
local MODS_DIR = scriptDir:match("^(.*)[/\\][^/\\]+[/\\][Ss]cripts$") or "."
local STATE_REL = "ModManager\\state.json"
local function readFile(rel)
    local f = io.open(MODS_DIR .. "\\" .. rel, "rb")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

local function texOf(img) return try(function() local o = img.Brush.ResourceObject if v(o) then return fname(o) end return "none" end) or "?" end
local function shownW(w) local s = visOf(w) return v(w) and s ~= VIS_COLLAPSED and s ~= VIS_HIDDEN end
local function tipOf(w) return try(function() return w.ToolTipText:ToString() end) end
local function near4(c, want) return c ~= nil and math.abs(c.R - want[1]) < 0.01 and math.abs(c.G - want[2]) < 0.01 and math.abs(c.B - want[3]) < 0.01 and math.abs(c.A - want[4]) < 0.01 end
-- One row as drawn (story 6): name, version, toggle (on | off | lock: the lock image r<n>.on when it is shown, else
-- the checkbox r<n>.tg's texture), box (live | fixed: the checkbox's opacity, dimmed when disabled | none for the
-- lock), gear (the look: lit | dim, or focus when it holds keyboard focus; ROW's gear comes from Configure), status
-- (how many of r<n>.s1..s3 show a texture, and which: warning | restart), the status images' tooltips, and its
-- rectangle.
local function readRow(n)
    local r = rowW(n)
    if not r or visOf(r) == VIS_COLLAPSED or visOf(r) == VIS_HIDDEN then return nil end
    local toggle, box = "?", "none"
    local lock, tg = cell(n, "on"), cell(n, "tg")
    if shownW(lock) then
        local tex = texOf(prop(lock, "Img"))
        toggle = TEX[tex] or tex
    elseif shownW(tg) then
        local tex = texOf(prop(tg, "Icon"))
        toggle = TEX[tex] or tex
        local op = try(function() return tg:GetRenderOpacity() end) or 1
        box = op < 0.9 and "fixed" or "live"
    end
    local icon = prop(cell(n, "cfg"), "Icon")
    local tint = try(function() return icon.ColorAndOpacity end)
    -- Core 0.12.1+ draws a focused dimmed button like its undimmed self, so a gear holding keyboard focus reads "focus"
    -- (only GEARLOOK uses the look; ROW's gear is what Configure offers).
    local btn = prop(cell(n, "cfg"), "Btn")
    local focused = btn ~= nil and try(function() return btn:HasKeyboardFocus() end) == true
    local icons, tips = {}, {}
    for k = 1, 3 do
        local img = prop(cell(n, "s" .. k), "Img")
        local kind = STATUS_TEX[texOf(img)]
        if kind then icons[#icons + 1] = kind; tips[#tips + 1] = tipOf(img) or "" end
    end
    return { n = n, name = textOf(cell(n, "name")) or "?", ver = textOf(cell(n, "ver")) or "?", toggle = toggle, box = box,
        gear = focused and "focus" or (near4(tint, DIM) and "dim" or (tint and "lit" or "?")), status = #icons, icons = #icons > 0 and table.concat(icons, ",") or "-",
        tips = tips, rect = absR(r) }
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
    -- (no gear: ROW takes it from Configure, GEARLOOK and CFGDIM judge its look; keyboard focus changes how it is drawn)
    for i, r in ipairs(rows) do t[i] = string.format("%s|%s|%s|%s|%d|%s", r.name, r.ver, r.toggle, r.box, r.status, r.icons) end
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
-- A real click at a fraction (fx, fy) of the widget's rectangle (a slider's number box: its right part), then 1.5 s.
local function clickAt(label, finder, fx, fy)
    step("click " .. label, function()
        local r = absR(finder())
        if not check(r ~= nil, "POINT %s has a point to click", label) then return end
        local x, y = math.floor(r.l + (r.r - r.l) * fx + 0.5), math.floor(r.t + (r.b - r.t) * fy + 0.5)
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
local finish -- the runner's (below); the last screen step calls it before QUIT GAME

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
-- read it into R.cfg[n] (gear: dim when it shows NO SETTINGS, lit when it lists settings, else ?); it stays open.
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
        if n then
            R.cfg[n] = screenOf("configure") and { title = cfgText("title"), ver = cfgText("ver"), need = cfgText("need"), build = cfgText("build"),
                gear = shownW(cfgEl("none")) and "dim" or (shownW(cfgEl("list")) and "lit" or "?") } or nil
        end
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
    -- One DOWN with the keyboard right after the first open, while the window's focus is still on its first line (row
    -- 1's gear; later the gear clicks move it), then a shot of the focus: row 2's gear, which core 0.12.2 shows as a
    -- band across the whole row. The shot is not judged, FOCUS only says where the keyboard focus is.
    step("focus: cursor away", function() return request("move 5 5"), 30, "cursor away" end)
    step("focus: DOWN", function()
        say("KEY DOWN")
        return request("key DOWN"), 30, "key DOWN"
    end)
    settle(1)
    step("focus: where", function()
        local at = "none"
        for n = 1, 256 do
            if not rowW(n) then break end
            local b = prop(cell(n, "cfg"), "Btn")
            if b and try(function() return b:HasKeyboardFocus() end) == true then at = "r" .. n .. ".cfg" break end
        end
        if at == "none" then
            local b = prop(closeOf("main"), "Btn")
            if b and try(function() return b:HasKeyboardFocus() end) == true then at = "BACK" end
        end
        say("FOCUS after DOWN: %s", at)
    end)
    shot("mm-focus")
    step("rows", function()
        R.rows = readRows()
        R.sig = sig(R.rows)
        check(#R.rows >= 8, "ROWS %d visible rows (at least the 8 the scenario installs)", #R.rows)
        nested(function()
            for _, r in ipairs(R.rows) do
                -- the gear's look read just before its own click (focus has moved since readRows)
                step("gear " .. r.n, function()
                    local again = readRow(r.n)
                    r.look = again and again.gear or "?"
                end)
                configureOf(function() return r.n end, r.name)
                step("ROW " .. r.n, function()
                    local d = R.cfg[r.n]
                    local need = d and d.need and d.need:match("^NUCLEUS (.*)$") or "?"
                    local build = d and d.build and d.build:match("^GAME BUILD (.*)$") or "?"
                    check(d ~= nil and d.title == r.name and d.ver == "VERSION " .. r.ver, "CFGDATA %d heading %s, %s", r.n, tostring(d and d.title), tostring(d and d.ver))
                    local gear = d and d.gear or "?"
                    say("ROW %s | %s | toggle=%s | box=%s | gear=%s | status=%d | icons=%s | need=%s | build=%s", r.name, r.ver, r.toggle, r.box, gear, r.status, r.icons, need, build)
                    -- the look, judged only on a gear without keyboard focus (focus draws a dimmed gear lit)
                    if r.look == "focus" then say("GEARLOOK %d skipped (focused)", r.n)
                    else check(gear ~= "?" and r.look == gear, "GEARLOOK %d %s looks %s (offers %s)", r.n, r.name, tostring(r.look), gear) end
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
    -- CARDFIT (0.1.1): the title, the header list and the list lie inside the main window's card (its Canvas, the
    -- card's inner area) within 1 unit, and BACK's top is at or below the list's bottom (no overlap). Core logs a WARN
    -- when the content is larger than the card may be; check.ps1 fails on it by name.
    step("card fit", function()
        local sc = scale()
        local _, c = screenOf("main")
        local cr = absR(c)
        local rects, okIn = {}, cr ~= nil
        for _, id in ipairs({ "title", "hdr.list", "list" }) do
            local r = absR(childTagged(c, id))
            rects[id] = r
            local inside = r ~= nil and cr ~= nil and (cr.l - r.l) / sc <= 1 and (cr.t - r.t) / sc <= 1 and (r.r - cr.r) / sc <= 1 and (r.b - cr.b) / sc <= 1
            if not inside then okIn = false end
        end
        local br, lr = absR(closeOf("main")), rects.list
        local clear = br ~= nil and lr ~= nil and br.t >= lr.b - 0.5
        say("CARDFIT canvas=%s title=%s header=%s list=%s back=%s scale=%.3f", rs(cr), rs(rects.title), rs(rects["hdr.list"]), rs(lr), rs(br), sc)
        local function u(a, b) return (a and b) and (a - b) / sc or -1 end
        check(okIn and clear, "CARDFIT the title, header and list are inside the card (%s) and the list ends %.1f units above BACK's top",
            tostring(okIn), u(br and br.t, lr and lr.b))
    end)
    settle(1)
    shot("mm-main")

    -- 3. Story 6: on/off. Dep off and on (mods.txt read back after each: the value, then the session start's bytes);
    -- Base off through the confirm (BACK first: nothing written; then TURN OFF); the restart and dependency icons, the
    -- banner and QUIT GAME, state.json; then Nucleus's lock and a pak row's disabled box change nothing.
    local function rowNamed(name) for _, r in ipairs(readRows()) do if r.name == name then return r end end end
    local function nOf(name) return function() local r = rowNamed(name) return r and r.n end end
    local function viewRow(nOfF, label)
        step("view " .. label, function() local n = nOfF() if n then nested(function() intoView(n) end) end end)
    end
    local function clickBox(name, part)
        viewRow(nOf(name), name .. "'s " .. part)
        clickOn(name .. "'s " .. part, function() local n = nOf(name)() return n and cell(n, part) end)
    end
    local function fileWait(what, rel, pred, sec)
        waitFor(what, function() local t = readFile(rel) return t ~= nil and pred(t) end, sec or 10)
    end
    local function pendingShown() return shownW(mainEl("banner")) and shownW(mainEl("quit")) end
    local function pendingHidden() return not shownW(mainEl("banner")) and not shownW(mainEl("quit")) end
    local BASE, DEP = "Mod Manager Base", "Mod Manager Dep"
    step("toggle: begin", function()
        for _, r in ipairs(R.rows or {}) do
            if r.name == "ModManagerFixture" then R.fixture = r.n end
            if r.name == CORE then R.nucleus = r.n end
            if r.name == "ModManagerPak" then R.pak = r.n end
        end
        check(R.fixture ~= nil and R.nucleus ~= nil and R.pak ~= nil, "TGROWS the fixture's, Nucleus's and the pak's rows found")
        R.txt0 = readFile("mods.txt")
        check(R.txt0 ~= nil and R.txt0:find("ModManagerBase : 1", 1, true) ~= nil and R.txt0:find("ModManagerDep : 1", 1, true) ~= nil,
            "TXT0 mods.txt read at the session start: Base and Dep on")
        local b, d = rowNamed(BASE), rowNamed(DEP)
        check(b ~= nil and d ~= nil and b.toggle == "on" and b.box == "live" and d.toggle == "on" and d.box == "live",
            "TGLIVE Base and Dep show a live box, on (%s/%s, %s/%s)", tostring(b and b.toggle), tostring(b and b.box), tostring(d and d.toggle), tostring(d and d.box))
        check(pendingHidden() and readFile(STATE_REL) == nil, "TGSTART nothing pending: no banner, no QUIT GAME, no state.json yet")
        say("TOGGLE begin")
    end)
    -- Dep off: no dependents, so no confirm.
    clickBox(DEP, "tg")
    fileWait("Dep off in mods.txt", "mods.txt", function(t) return t:find("ModManagerDep : 0", 1, true) ~= nil end)
    settle(1)
    step("dep off", function()
        local t = readFile("mods.txt")
        check(t ~= nil and t == (R.txt0:gsub("ModManagerDep : 1", "ModManagerDep : 0")), "TGDEPOFF mods.txt: Dep's value is 0, every other byte as at the start")
        check(screenOf("confirm") == nil, "TGNOCONFIRM no confirm for a mod nothing needs")
        local d = rowNamed(DEP)
        check(d ~= nil and d.toggle == "off" and d.icons == "restart" and d.tips[1] == "TURNS OFF AFTER A RESTART",
            "TGDEPICON Dep: box off, the restart icon (%s, %s, %s)", tostring(d and d.toggle), tostring(d and d.icons), tostring(d and d.tips[1]))
        check(pendingShown(), "PENDINGUI the banner and QUIT GAME are shown")
        local st = readFile(STATE_REL)
        check(st == '{"version":1,"off":["ModManagerDep"],"seen":[]}', "STATEOFF state.json lists Dep (%s)", tostring(st))
    end)
    -- CARDFIT2: with the bottom-right stack shown, the card still holds everything (core logs a WARN when clamped).
    step("card fit pending", function()
        local sc = scale()
        local _, c = screenOf("main")
        local cr = absR(c)
        local ok2 = cr ~= nil
        for _, id in ipairs({ "title", "hdr.list", "list", "quit", "banner" }) do
            local r = absR(childTagged(c, id))
            if not (r and cr and (cr.l - r.l) / sc <= 1 and (cr.t - r.t) / sc <= 1 and (r.r - cr.r) / sc <= 1 and (r.b - cr.b) / sc <= 1) then ok2 = false end
        end
        local qr, lr = absR(childTagged(c, "banner")), absR(childTagged(c, "list"))
        check(ok2 and qr ~= nil and lr ~= nil and qr.t >= lr.b - 0.5, "CARDFIT2 with changes pending, the banner and QUIT GAME sit inside the card, below the list")
    end)
    step("cursor away", function() return request("move 5 5"), 30, "cursor away" end)
    shot("mm-pending")
    clickBox(DEP, "tg")
    fileWait("mods.txt back", "mods.txt", function(t) return t == R.txt0 end)
    settle(1)
    step("dep on", function()
        check(readFile("mods.txt") == R.txt0, "TGDEPON mods.txt's bytes equal the session start's")
        local d = rowNamed(DEP)
        check(d ~= nil and d.toggle == "on" and d.icons == "-", "TGDEPON2 Dep: box on, no icon (%s, %s)", tostring(d and d.toggle), tostring(d and d.icons))
        check(pendingHidden(), "PENDINGOFF the banner and QUIT GAME are hidden again")
        check(readFile(STATE_REL) == '{"version":1,"off":[],"seen":[]}', "STATEON state.json: Dep removed (%s)", tostring(readFile(STATE_REL)))
    end)
    -- Base: Dep needs it, so the confirm asks; BACK cancels.
    clickBox(BASE, "tg")
    waitFor("the confirm", function() return screenOf("confirm") ~= nil end, 10)
    settle(1)
    step("confirm", function()
        local _, c = screenOf("confirm")
        local text = textOf(childTagged(c, "confirm.text"))
        check(text == "TURN OFF Mod Manager Base? Mod Manager Dep NEED IT.", "CONFIRMTEXT %s", tostring(text))
        check(readFile("mods.txt") == R.txt0, "CONFIRMWAIT nothing written while it asks")
    end)
    shot("mm-confirm")
    clickOn("the confirm's BACK", function() return closeOf("confirm") end)
    waitFor("the confirm closed", function() return screenOf("confirm") == nil end, 10)
    settle(1)
    step("confirm back", function()
        local b = rowNamed(BASE)
        check(b ~= nil and b.toggle == "on" and readFile("mods.txt") == R.txt0, "CONFIRMBACK BACK: Base still on, nothing written (%s)", tostring(b and b.toggle))
    end)
    clickBox(BASE, "tg")
    waitFor("the confirm again", function() return screenOf("confirm") ~= nil end, 10)
    settle(1)
    clickOn("TURN OFF", function() local _, c = screenOf("confirm") return childTagged(c, "confirm.ok") end)
    fileWait("Base off in mods.txt", "mods.txt", function(t) return t:find("ModManagerBase : 0", 1, true) ~= nil end)
    settle(1)
    step("base off", function()
        check(screenOf("confirm") == nil, "CONFIRMCLOSED TURN OFF closed the confirm")
        check(readFile("mods.txt") == (R.txt0:gsub("ModManagerBase : 1", "ModManagerBase : 0")), "CONFIRMOFF mods.txt: Base's value is 0, every other byte as at the start")
        local b, d = rowNamed(BASE), rowNamed(DEP)
        check(b ~= nil and b.toggle == "off" and b.icons == "restart", "TGBASEICON Base: off, the restart icon (%s)", tostring(b and b.icons))
        check(d ~= nil and d.toggle == "on" and d.icons == "warning" and d.tips[1] == "NEEDS Mod Manager Base (TURNED OFF)",
            "DEPICON Dep: still on, the dependency icon NEEDS Mod Manager Base (TURNED OFF) (%s, %s)", tostring(d and d.icons), tostring(d and d.tips[1]))
        check(pendingShown(), "PENDINGUI2 the banner and QUIT GAME are shown")
        check(readFile(STATE_REL) == '{"version":1,"off":["ModManagerBase"],"seen":[]}', "STATEBASE state.json lists exactly Base (%s)", tostring(readFile(STATE_REL)))
    end)
    -- Fixed rows: Nucleus's lock and a pak row's disabled box change nothing, write nothing, log nothing.
    step("fixed: begin", function()
        R.before = sig(readRows())
        R.txtB = readFile("mods.txt")
        local p = rowNamed("ModManagerPak")
        check(p ~= nil and p.toggle == "on" and p.box == "fixed", "PAKFIXED the pak row shows its state in a disabled box (%s/%s)", tostring(p and p.toggle), tostring(p and p.box))
        say("FIXED begin")
    end)
    clickBox(CORE, "on")
    clickBox("ModManagerPak", "tg")
    settle(1)
    step("fixed: end", function()
        say("FIXED end")
        local now = sig(readRows())
        check(now == R.before and readFile("mods.txt") == R.txtB and screenOf("configure") == nil and screenOf("confirm") == nil and visOf(screenOf("main")) == VIS_VISIBLE,
            "FIXEDINERT the lock and the pak's box changed nothing (rows the same: %s, mods.txt the same, main window on top)", tostring(now == R.before))
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
    -- Story 6: the fixture's Configure lists its status problems, then one row per declared setting with its control.
    -- (Base is off by now, so the base line reads TURNED OFF.)
    step("configure: problems", function()
        local p1, p2, p3, p4 = cfgText("p1"), cfgText("p2"), cfgText("p3"), cfgText("p4")
        check(p1 == "MADE FOR GAME V0.0.0 (BUILD 1). THIS GAME: V8.2.3 (BUILD -)." and p2 == "NEEDS nuclearnightmare-community.mod-manager-missing (NOT INSTALLED)"
            and p3 == "NEEDS Mod Manager Base (TURNED OFF)" and not shownW(cfgEl("p4")),
            "CFGPROBLEMS %s / %s / %s (4th shown: %s)", tostring(p1), tostring(p2), tostring(p3), tostring(shownW(cfgEl("p4"))))
        R.set = {}
        for i = 1, 64 do
            if not setRow(i) then break end
            local label = textOf(setCell(i, "lbl"))
            if label then R.set[label] = i end
        end
        local function kind(label)
            local i = R.set[label]
            if not i then return "missing" end
            local out = {}
            for _, k in ipairs({ "cb", "ch", "sl", "ro" }) do if shownW(setCell(i, k)) then out[#out + 1] = k end end
            return table.concat(out, ",")
        end
        local kinds = string.format("Example=%s Flag=%s Ratio=%s Mode=%s Restart flag=%s Preset value=%s Free number=%s", kind("Example"), kind("Flag"),
            kind("Ratio"), kind("Mode"), kind("Restart flag"), kind("Preset value"), kind("Free number"))
        say("SETTINGS %s", kinds)
        check(kinds == "Example=sl Flag=cb Ratio=sl Mode=ch Restart flag=cb Preset value=ro Free number=ro", "SETKINDS a slider, a checkbox, a slider, a choice, a checkbox, two texts")
        local pre, free = R.set["Preset value"], R.set["Free number"]
        check(pre ~= nil and textOf(setCell(pre, "ro")) == "SET BY PRESETS", "SETBY the source setting reads %s", tostring(pre and textOf(setCell(pre, "ro"))))
        check(free ~= nil and textOf(setCell(free, "ro")) == "5", "SETRO the int without bounds shows its value (%s)", tostring(free and textOf(setCell(free, "ro"))))
        local rs = R.set["Restart flag"] and prop(setCell(R.set["Restart flag"], "rs"), "Img")
        check(rs ~= nil and STATUS_TEX[texOf(rs)] == "restart" and tipOf(rs) == "APPLIES AFTER A RESTART", "SETMARK the restart setting's mark (%s, %s)", tostring(rs and texOf(rs)), tostring(rs and tipOf(rs)))
    end)
    shot("mm-configure")
    local function setOf(label) return function() return R.set and R.set[label] end end
    local function settingsHas(pat) return function(t) return t:find(pat) ~= nil end end
    local SETTINGS_REL = "ModManagerFixture\\settings.json"
    clickOn("the Flag checkbox", function() local i = setOf("Flag")() return i and setCell(i, "cb") end)
    fileWait("flag in settings.json", SETTINGS_REL, settingsHas('"flag"%s*:%s*true'))
    clickOn("Mode's next arrow", function() local i = setOf("Mode")() return i and prop(setCell(i, "ch"), "Next") end)
    fileWait("mode in settings.json", SETTINGS_REL, settingsHas('"mode"%s*:%s*"two"'))
    clickAt("Example's number box", function() local i = setOf("Example")() return i and prop(setCell(i, "sl"), "Box") end, 0.85, 0.5)
    step("type 7", function() return request("type 7"), 30, "type 7" end)
    settle(0.8)
    step("Enter", function() return request("key ENTER"), 30, "Enter" end)
    fileWait("example in settings.json", SETTINGS_REL, settingsHas('"example"%s*:%s*7[^%d%.]'))
    clickOn("the Restart flag checkbox", function() local i = setOf("Restart flag")() return i and setCell(i, "cb") end)
    fileWait("later in settings.json", SETTINGS_REL, settingsHas('"later"%s*:%s*true'))
    settle(1)
    step("settings: saved", function()
        local t = readFile(SETTINGS_REL) or ""
        say("SETTINGSJSON %s", (t:gsub("[\r\n]", " ")))
        check(t:find('"flag"%s*:%s*true') and t:find('"mode"%s*:%s*"two"') and t:find('"example"%s*:%s*7[^%d%.]') and t:find('"later"%s*:%s*true'),
            "SETFILE settings.json holds flag=true, mode=two, example=7, later=true")
        local f = R.fixture and readRow(R.fixture)
        check(f ~= nil and f.icons == "warning,warning,restart" and f.tips[3] == "A SETTING APPLIES AFTER A RESTART",
            "RESTARTICON the restart setting adds the restart icon to the fixture's row (%s, %s)", tostring(f and f.icons), tostring(f and f.tips[3]))
        check(cfgText("p4") == "A SETTING APPLIES AFTER A RESTART", "CFGRESTART Configure lists it (%s)", tostring(cfgText("p4")))
        local mark = R.set["Restart flag"] and prop(setCell(R.set["Restart flag"], "rs"), "Img")
        check(not shownW(cfgEl("msg")), "SETNOMSG no NOT SAVED line")
        say("SETMARK after %s", tostring(mark and texOf(mark)))
    end)
    step("cursor away", function() return request("move 5 5"), 30, "cursor away" end)
    shot("mm-settings")
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
    -- backdrop, changes nothing. Its Close (core 0.12.0: BACK in the bottom-left of the main window's card): a click
    -- there lands on Configure's backdrop (or, were the cards alike, on Configure's own BACK); had it reached the main
    -- window's BACK, both windows would close (a Close closes the windows above too). So the main window must still be
    -- open after it, whether or not Configure is still open.
    clickOn("Nucleus's gear under Configure", function() return R.nucleus and cell(R.nucleus, "cfg") end)
    settle(1)
    step("blocked gear", function()
        check(screenOf("configure") ~= nil and cfgText("title") == "ModManagerFixture" and screenOf("main") ~= nil,
            "BLOCKEDGEAR a click on the main window's gear under Configure changed nothing (Configure still shows %s)", tostring(cfgText("title")))
    end)
    clickOn("the main window's Close under Configure", function() return closeOf("main") end)
    settle(1)
    step("blocked", function()
        local cfgOpen = screenOf("configure") ~= nil
        local mainVis = visOf(screenOf("main"))
        check(screenOf("main") ~= nil and mainVis == (cfgOpen and VIS_HTI or VIS_VISIBLE),
            "BLOCKED the main window's Close did not act under Configure: the main window is still open (visibility %s; Configure open=%s)", tostring(mainVis), tostring(cfgOpen))
    end)
    -- 6. Configure's Close (if the click above didn't already), then the main window's Close: the menu with the entry.
    step("configure: close if open", function()
        if screenOf("configure") then nested(function() closeConfigure("before the main window's") end) end
    end)
    step("configure: closed again", function()
        check(screenOf("configure") == nil and visOf(screenOf("main")) == VIS_VISIBLE, "CFGCLOSE2 Configure closed; the main window takes input again")
        R.sig2 = sig(readRows()) -- the rows before the match (story 6: Base off, the fixture's restart setting pending)
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
        local same = sig(rows) == R.sig2
        check(same, "SAME the window after the match lists the same %d rows, with their states and icons (%d now)", R.rows and #R.rows or -1, #rows)
        if not same then say("SAME before: %s", (tostring(R.sig2):gsub("\n", " / "))) say("SAME now: %s", (sig(rows):gsub("\n", " / "))) end
        check(shownW(mainEl("banner")) and shownW(mainEl("quit")), "QUITUI changes pending after the match: the banner and QUIT GAME are shown")
        check(textOf(mainEl("banner")) == "CHANGES APPLY AFTER A RESTART.", "BANNER reads %s", tostring(textOf(mainEl("banner"))))
    end)
    shot("mm-reopen")
    -- 10. END, then QUIT GAME: the game closes itself (run.ps1 waits for that; check.ps1 wants [ModManager] QUIT after
    -- END result=PASS and no crash). Nothing runs after this step.
    step("end and quit", function()
        local r = absR(mainEl("quit"))
        check(r ~= nil, "QUITPOINT QUIT GAME has a point to click")
        local pass = S.failures == 0
        finish()
        if pass and r then
            local x, y = center(r)
            say("CLICK QUIT GAME at (%d,%d)", x, y)
            request(string.format("click %d %d", x, y))
        end
    end)
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
finish = function()
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
