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
--   screen:   the entry; the main window's rows (ROW lines with the toggle, its box, the status icons, story 12's scope
--             icon and its tooltip; the gear, need, build and the RUNS ON line (CFGSCOPE) from each row's Configure window: gear=dim when it shows NO SETTINGS, lit when it lists
--             settings; GEARLOOK: the gear drawn that way, judged only when it doesn't hold keyboard focus); one DOWN
--             right after the first open and a focus shot; story 11: the first toggle before any Configure (cold
--             T_Restart): DOWN to Dep's checkbox (TGFIRSTFOCUS), ENTER, Dep off with the restart icon within 10 s
--             (TGFIRST); core story 42: CIPROBE (core's CommonInput calls work), the chip stays on Dep's focused
--             checkbox after that ENTER (CHIP enter1, box off, shot mm-chip-enter-off) and after a second ENTER
--             (CHIP enter2, box on, shot mm-chip-enter-on), a third ENTER turns it off again; a mouse click back on
--             within 10 s (TGFIRSTCLICK), the IconBack hidden after it (CHIP backoff); MEASURE of the long name;
--             CARDFIT (the content inside the card, the list above BACK); story 6: Dep off and on with mods.txt and state.json read back, Base off
--             through the confirm (BACK, then TURN OFF), the restart and dependency icons, the banner and QUIT GAME
--             (CARDFIT2), Nucleus's lock and a pak's disabled box changing nothing (FIXED); the fixture's Configure:
--             its problem lines, its settings' controls, a checkbox click, a choice arrow, a typed slider value, the
--             restart setting, settings.json read back; Configure on top of the main window, a dimmed gear's Configure,
--             the main window's Close blocked under it; closes; Tower Island and back three times (core story 35:
--             every menu sampled each frame for pop-in, NOPOPIN menu1..4, HIDDENFIRST menu2..4; a menu<k>-return shot once
--             its entry is in);
--             the entry again, the same rows (DW-59); END; then QUIT GAME, which closes the game.
--   restart:  story 8, two sessions (VM only; the runner lets the game relaunch itself once). Session 1 (no
--             restart-facts.txt next to this file): ModManagerRestart loaded; its row on, nothing pending, no RESTART NOW;
--             its box clicked off: the restart icon, the banner, QUIT GAME and RESTART NOW (right above QUIT GAME);
--             core.restart (core's own module, required here: this driver doesn't connect) mode() is "direct", start()
--             is true, a second start() is nil, "already started"; the facts saved to restart-facts.txt; then a real
--             click on RESTART NOW (the Mod Manager's start() gets "already started", the first helper relaunches the
--             game). No END line in session 1 unless a check failed before the click (END result=FAIL, no click).
--             Session 2 (the facts file there): the facts logged and judged; ModManagerRestart not loaded; its row
--             off with nothing pending (no banner, QUIT GAME or RESTART NOW), mods.txt ': 0'; the box clicked back on
--             (pending again, both buttons shown); END; then QUIT GAME.
--   apply:    Mod Manager v2 story 3, four sessions (VM only; the runner follows the game across exits: -RepeatUntilEnd),
--             counted in apply-session.txt next to this file. Plan A (ModManagerApplyA) is staged by deploy.ps1; core's
--             own nucleus.apply in this state reads the status and starts the helper (never acks: the Mod Manager does).
--             Session 1: the Mod Manager started the helper at onReady (status waiting), no result yet, A not loaded;
--             the window shows the banner, QUIT GAME and RESTART NOW; a real click on RESTART NOW (the helper applies
--             A, then relaunches the game). Session 2: A loaded, the result applied; opening the window lets the Mod
--             Manager show and ack it; "stage B" (pending), start() true (waiting), then "kill". Session 3: A and B
--             loaded, the result applied; "stage C", "lock <A's Scripts\main.lua>" (a write open of it fails), start()
--             true (waiting), then "close" (WM_CLOSE, as Alt+F4). Session 4: the result failed, reason locked, that
--             path, attempts 1; A's files byte-identical to the copy deploy.ps1 put in Scripts\apply-expect\; none of
--             C's files; C not loaded and not in mods.txt; C still staged; the window shows the buttons; END (no QUIT
--             GAME: the runner ends at END and stops the waiting helper before closing the game).
--   browse:   Mod Manager v2 story 4 (VM, the live catalog): waits for the startup refresh's "[ModManager] CATALOG done"
--             (read back from UE4SS.log), opens Manage Mods (ROW <name> | <version> per installed row), BROWSE (BWOPEN,
--             BWLIST, shot browse), DOWN and four RIGHTs: CATEGORY AUDIO (BWCAT), DOWN and RIGHT: SHOW INSTALLED (BWSHOW),
--             BACK and BROWSE again: the filters reset (BWRESET), a click on the search box, "type clock", ENTER: only
--             HUD Clock (BWSEARCH), DETAILS on row 1 (BWDETAILS, shot details), its BACK, REFRESH and a second CATALOG
--             done (BWDONE); END. check.ps1 judges the Mod Manager's CATALOG, BUILD and BROWSE lines.
--   install:  Mod Manager v2 story 5, two sessions (VM, the live catalog; -RepeatUntilEnd), counted in
--             install-session.txt next to this file; deploy.ps1 made sure HudClock isn't installed. Session 1: the
--             startup refresh's CATALOG done; Manage Mods, BROWSE, the search box, "type clock", ENTER: one row, HUD
--             Clock, NOT INSTALLED, with INSTALL (INROW, INSTATE, INBUTTON); INSTALL: the confirm reads INSTALL HUD CLOCK
--             0.3.0?, no ALSO INSTALLS, DOWNLOAD 9 KB (INTITLE, INNOALSO, INSIZE, INOK; shot install-confirm); its
--             INSTALL; "[ModManager] INSTALL done" read back from UE4SS.log: ok, core's helper waiting, the row PENDING
--             RESTART without INSTALL, the message (INDONE, INWAIT, INPENDING, INNOBUTTON, INMSG; shot install-pending);
--             BACK, QUIT GAME and RESTART NOW shown (INRESTART), a real click on RESTART NOW (the helper applies the
--             change, then relaunches the game). Session 2: "[HudClock]" in UE4SS.log, nothing staged, mods.txt's
--             HudClock line above Keybinds, Mods/HudClock/mod.json 0.3.0 (INAPPLIED, INLOADED, INMODSTXT, INJSON);
--             BROWSE, "clock": HUD Clock INSTALLED without INSTALL (INROW2, ININSTALLED, INNOBUTTON2; shot
--             install-installed); END.
--   update:   Mod Manager v2 story 6, two sessions (VM, a fixture catalog served in the VM; -RepeatUntilEnd), counted
--             in update-session.txt next to this file; deploy.ps1 installed core's test main.dll, HUD Clock 0.3.0
--             (revoked in the fixture catalog) and WhistleMute. Session 1: the startup refresh's CATALOG done; the
--             title-screen notice reads HUD CLOCK 0.3.0 WAS REVOKED (UPNOTICE, shot update-notice); its REVIEW: the
--             revoked window (UPRV*), UPDATE TO 0.3.1, the confirm UPDATE HUD CLOCK 0.3.0 -> 0.3.1? (UPTITLE), UPDATE,
--             "UPDATE done", NOTICE removed (UPDONE1, UPREMOVED); its BACK, MANAGE MODS: the notice line reads 1 UPDATES
--             AVAILABLE (UPLINE, UPARROW); UPDATES: Browse, HUD Clock PENDING RESTART, the Nucleus row's UPDATE and its
--             confirm (UPPENDING, UPCORETITLE, UPDONE2); BACK, BROWSE, "type whistle", WhistleMute's DETAILS, UNINSTALL
--             and its confirm (UPUNTITLE, UPUNLINE, UPUNDONE, UPWAIT); BACK twice, RESTART NOW. Session 2: core 0.27.1
--             and HUD Clock 0.3.1 run, the file only 0.3.0 had and WhistleMute's files and mods.txt line are gone, no
--             title notice (UP* checks), UPOLD (the helper's renamed copy: reported only), the HUD Clock row; END.
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
-- Story 12: the scope icon's texture -> the scope it shows (read from the texture, which focus doesn't change).
local SCOPE_TEX = { T_ScopeHost = "host", T_ScopeClient = "client", T_ScopeHostPlus = "host-plus", T_ScopeBoth = "both",
    T_ScopeUnknown = "unknown" }

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
-- Core story 39 (0.15.4): the focus chip on a row control (a core button widget: its Btn). of(w) -> on, what: on when
-- Btn's Normal brush is an instance of M_NN_CinematicSelection in the chip's base colour (core's theme, read in this
-- state; core 0.15.5, story 41: light blue #6dd5ed, its linear value theme.game.focusChipColor) and Btn's render scale is above 1 (the chip reaches past the icon; Content is scaled back, < 1).
local CHIP = {}
function CHIP.base()
    local b = { r = 0.1529, g = 0.6654, b = 0.8469 } -- core 0.15.5's theme.game.focusChipColors.CinematicBaseColor (#6dd5ed, linear)
    local okT, th = pcall(require, CORE:lower() .. ".ui.theme")
    if okT and type(th) == "table" and th.game and th.game.focusChipColors then b = th.game.focusChipColors.CinematicBaseColor end
    return b
end
function CHIP.of(w)
    local base = CHIP.base()
    local b = prop(w, "Btn")
    local mi = try(function() return b.WidgetStyle.Normal.ResourceObject end)
    local cls, par = cname(mi), (v(mi) and try(function() return mi.Parent:GetFName():ToString() end)) or "?"
    local c = v(mi) and try(function() return mi:K2_GetVectorParameterValue(FName("CinematicBaseColor")) end)
    local cr, cg, cb = try(function() return c.R end), try(function() return c.G end), try(function() return c.B end)
    local sb = try(function() return b.RenderTransform.Scale.X end)
    local sc = try(function() return prop(w, "Content").RenderTransform.Scale.X end)
    local near = function(x, y) return type(x) == "number" and math.abs(x - y) < 0.002 end
    local on = cls == "MaterialInstanceDynamic" and par == "M_NN_CinematicSelection"
        and near(cr, base.r) and near(cg, base.g) and near(cb, base.b)
        and type(sb) == "number" and sb > 1.01 and type(sc) == "number" and sc < 0.99
    return on, string.format("%s parent %s base %s,%s,%s scale %s content %s", cls, par, tostring(cr), tostring(cg), tostring(cb), tostring(sb), tostring(sc))
end
function CHIP.hasFocus(w) local b = prop(w, "Btn") return b ~= nil and try(function() return b:HasKeyboardFocus() end) == true end
-- Core story 42 (0.17.1): the dark box behind a chipped checkbox's icon (core's button widget's IconBack). back(w) ->
-- ok, what: ok when IconBack is shown (HitTestInvisible, 3) in core's theme.game.focusChipBack (read in this state;
-- core 0.17.1: the panel's dark, linear 0.0052, 0.0070, 0.0091) and not in the chip's colour, and the Icon itself is
-- not drawn in the chip's ink (theme.game.focusChipInk: the ink tinted the tick before 0.17.1).
function CHIP.back(w)
    local want = { r = 0.0052, g = 0.0070, b = 0.0091, a = 1 } -- core 0.17.1's theme.game.focusChipBack
    local ink = { r = 0.0052, g = 0.0070, b = 0.0091 } -- core 0.15.5's theme.game.focusChipInk
    local okT, th = pcall(require, CORE:lower() .. ".ui.theme")
    if okT and type(th) == "table" and th.game and th.game.focusChipBack then want = th.game.focusChipBack end
    if okT and type(th) == "table" and th.game and th.game.focusChipInk then ink = th.game.focusChipInk end
    local ic = prop(w, "Icon")
    local icc = v(ic) and try(function() return ic.ColorAndOpacity end)
    local ir, ig, ibl, ia = try(function() return icc.R end), try(function() return icc.G end), try(function() return icc.B end), try(function() return icc.A end)
    local chip = CHIP.base()
    local ib = prop(w, "IconBack")
    local vis = v(ib) and try(function() return ib:GetVisibility() end)
    local c = v(ib) and try(function() return ib.ColorAndOpacity end)
    local cr, cg, cb, ca = try(function() return c.R end), try(function() return c.G end), try(function() return c.B end), try(function() return c.A end)
    local near = function(x, y) return type(x) == "number" and math.abs(x - y) < 0.002 end
    local ok = vis == 3 and near(cr, want.r) and near(cg, want.g) and near(cb, want.b) and near(ca, want.a)
        and not (near(cr, chip.r) and near(cg, chip.g) and near(cb, chip.b))
        and type(ir) == "number" and not (near(ir, ink.r) and near(ig, ink.g) and near(ibl, ink.b))
    return ok, string.format("IconBack %s visibility %s colour %s,%s,%s,%s; icon %s,%s,%s,%s", tostring(v(ib)), tostring(vis), tostring(cr), tostring(cg), tostring(cb), tostring(ca),
        tostring(ir), tostring(ig), tostring(ibl), tostring(ia))
end
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
-- (how many of r<n>.s1..s3 show a texture, and which: warning | restart), the status images' tooltips, story 12's
-- scope (r<n>.sc's texture: host | client | host-plus | both | unknown, else the texture's name) and its tooltip, and
-- its rectangle.
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
    local scImg = prop(cell(n, "sc"), "Img")
    local scTex = texOf(scImg)
    local scope = SCOPE_TEX[scTex] or scTex
    local stip = tipOf(scImg) or ""
    return { n = n, name = textOf(cell(n, "name")) or "?", ver = textOf(cell(n, "ver")) or "?", toggle = toggle, box = box, scope = scope, stip = stip,
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
    for i, r in ipairs(rows) do t[i] = string.format("%s|%s|%s|%s|%d|%s|%s|%s", r.name, r.ver, r.toggle, r.box, r.status, r.icons, r.scope, r.stip) end
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

-- ---------------------------------------------------------------- core story 35: the per-frame pop-in sampler
-- On each new MainMenu_C (its own NotifyOnNewObject; only the path is kept, nothing is called in the callback) a chain
-- of ExecuteInGameThreadAfterFrames(1) samples the menu every frame for at most 20 s, re-found with StaticFindObject
-- each time. A pop-in frame: the menu in the viewport, its opacity > 0.01, switcher page 0, Overlay_0 drawn and the
-- column's opacity > 0.01 while the column has no MANAGE MODS entry (what was painted the frame before); a frame in
-- the viewport without the entry where one of those can't be read is unreadable and counts against the menu. Per menu
-- it records the first frame the column's opacity is below 0.01 (core's hide), the first frame Overlay_0 is drawn and
-- the first frame with the entry. Once the entry is in a drawn column (or at the time-out): POPIN menu<k> ..., the
-- NOPOPIN menu<k> check (the entry seen in a drawn column, no pop-in frame, no unreadable one) and, for the returns
-- (menu2..), HIDDENFIRST menu<k> (the column hidden on or before the first frame Overlay_0 was drawn; menu1's entry can
-- come from entry() before any hide, so it is logged only). k counts menus that reached the viewport.
local MENU_PKG = "/Game/Graphics/MainMenu/MainMenu"
local MENU_CLASS = MENU_PKG .. ".MainMenu_C"
local POP = { n = 0, judged = {} }
local function opacityOf(w) local o = v(w) and try(function() return w:GetRenderOpacity() end) return type(o) == "number" and o or nil end
local function drawnVis(x) return x ~= VIS_COLLAPSED and x ~= VIS_HIDDEN end
local function sampleStart(path)
    local s = { path = path, k = nil, frames = 0, pop = 0, seen = 0, unread = 0, t0 = os.clock() }
    local function judge(why)
        if not s.k then say("POPIN skipped %s: never in the viewport (%s)", s.path:match("[^.]+$") or "?", why) return end
        local inDrawn = why == "entry in"
        say("POPIN menu%d frames=%d visible=%d pop=%d firstPop=%s unreadable=%d hidden=%s overlay=%s entry=%s (%s)", s.k, s.frames, s.seen, s.pop,
            tostring(s.firstPop), s.unread, tostring(s.firstHidden), tostring(s.firstOverlay), tostring(s.entryFrame), why)
        check(inDrawn and s.pop == 0 and s.unread == 0,
            "NOPOPIN menu%d no frame drew the column without the %s entry (%d of %d visible frames did, %d unreadable; entry in a drawn column: %s)",
            s.k, ENTRY_LABEL, s.pop, s.seen, s.unread, tostring(inDrawn))
        if s.k >= 2 then
            check(s.firstHidden ~= nil and s.firstOverlay ~= nil and s.firstHidden <= s.firstOverlay,
                "HIDDENFIRST menu%d the column was hidden (frame %s) on or before Overlay_0 was first drawn (frame %s)", s.k, tostring(s.firstHidden), tostring(s.firstOverlay))
        end
        POP.judged[s.k] = true
    end
    local sample
    sample = function()
        local okS, err = pcall(function()
            s.frames = s.frames + 1
            local mm = StaticFindObject(s.path)
            if not v(mm) then judge("menu gone") return end
            local inVp = try(function() return mm:IsInViewport() end)
            local page = try(function() return mm.WidgetTree.RootWidget:GetActiveWidgetIndex() end)
            local vb = column(mm)
            local mOp, cOp, ovVis = opacityOf(mm), opacityOf(vb), visOf(prop(mm, "Overlay_0"))
            if cOp and cOp < 0.01 and not s.firstHidden then s.firstHidden = s.frames end
            if ovVis ~= -1 and drawnVis(ovVis) and not s.firstOverlay then s.firstOverlay = s.frames end
            if inVp == true and not s.k then POP.n = POP.n + 1; s.k = POP.n end
            local has = entryOf(mm) ~= nil
            if has and not s.entryFrame then s.entryFrame = s.frames end
            if inVp == true then
                if type(page) ~= "number" or not mOp or not cOp or ovVis == -1 then
                    if not has then s.unread = s.unread + 1 end
                elseif mOp > 0.01 and page == 0 and drawnVis(ovVis) and cOp > 0.01 then
                    s.seen = s.seen + 1
                    if has then judge("entry in") return end
                    s.pop = s.pop + 1; s.firstPop = s.firstPop or s.frames
                end
            end
            if os.clock() - s.t0 > 20 then judge("time-out") return end
            ExecuteInGameThreadAfterFrames(1, sample)
        end)
        if not okS then check(false, "POPIN sampler for %s: %s", s.path:match("[^.]+$") or "?", firstLine(err)) end
    end
    local okA, errA = pcall(ExecuteInGameThreadAfterFrames, 1, sample)
    if not okA then check(false, "POPIN can't sample per frame: %s", firstLine(errA)) end
end
if SCENARIO == "screen" then
    local okN, errN = pcall(NotifyOnNewObject, MENU_CLASS, function(obj)
        local okP, path = pcall(function() return (obj:GetFullName():gsub("^%S+ ", "")) end)
        if okP and type(path) == "string" and not path:find("Default__", 1, true) and path:sub(1, #MENU_PKG + 1) ~= MENU_PKG .. "." then
            sampleStart(path)
        end
        return false
    end)
    if not okN then say("FAIL POPIN NotifyOnNewObject(%s): %s", MENU_CLASS, firstLine(errN)) end
end
local function popJudged(k) return function() return POP.judged[k] == true end end

-- ---------------------------------------------------------------- requests and steps
local seq = 0
local function request(cmd)
    seq = seq + 1
    local mine, line = seq, seq .. " " .. cmd
    -- The runner may hold the request file open for a moment: a failed open is retried on each wait tick.
    local written = false
    local function write()
        local f = io.open(REQ, "w")
        if f then f:write(line); f:close(); written = true end
    end
    write()
    return function()
        if not written then write() return false end
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
                scope = cfgText("scope"), -- story 12: the RUNS ON line
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
    waitFor("menu1 pop-in judged", popJudged(1), 30)
    settle(3)
    entryChecks("menu1")
    shot("mm-menu")

    -- (story 6 helpers, used from the first toggle on)
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

    -- 2. The rows, each one's Configure data, the long name's measure, a screenshot.
    openMain("first")
    -- Core story 39 (0.15.4): the window was opened by a mouse click on the entry, so the input mode is the mouse's: no
    -- control shows the focus chip (CHIP open), shot mm-chip-open. CHIP.of(w): whether a row control's Btn shows the
    -- chip (its Normal brush an instance of the selection material in the chip's base colour, its render scale above
    -- 1: the chip reaches past the icon) and what it shows.
    step("chip: open", function()
        local onAny, focused = nil, "none"
        for n = 1, 256 do
            if not rowW(n) then break end
            for _, part in ipairs({ "tg", "cfg" }) do
                local w = cell(n, part)
                if w and CHIP.of(w) then onAny = "r" .. n .. "." .. part end
                if w and CHIP.hasFocus(w) then focused = "r" .. n .. "." .. part end
            end
        end
        check(focused ~= "none" and onAny == nil, "CHIP open after a mouse click on the entry: focus on %s, no focus chip (%s)", focused, tostring(onAny))
    end)
    shot("mm-chip-open")
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
    -- 2a. Core story 39 (0.15.4): the focus chip. Focus is on row 2's gear (after the DOWN above): DOWN moves it to Base's
    -- gear (row 3, same column), RIGHT does nothing (the gear is the row's last control; a key at a line end), LEFT moves
    -- it to Base's checkbox: the checkbox shows the chip (its Btn's Normal brush is an instance of the selection material
    -- in the chip's base colour, its render scale above 1), the gear doesn't; RIGHT: the reverse. A shot after each.
    -- Then LEFT back to the first column, so the first toggle's DOWN keys below land on Dep's checkbox.
    do
        local chipOf, hasFocusOf = CHIP.of, CHIP.hasFocus
        local function chipKey(key, label)
            step("chip: " .. key .. " " .. label, function()
                say("KEY %s (%s)", key, label)
                return request("key " .. key), 30, "key " .. key
            end)
            settle(1)
        end
        local function chipCheck(name, on, off)
            step("chip: " .. name, function()
                local r = rowNamed(BASE)
                local n = r and r.n
                local wOn, wOff = n and cell(n, on), n and cell(n, off)
                local chipA, whatA = chipOf(wOn)
                local chipB, whatB = chipOf(wOff)
                check(n ~= nil and hasFocusOf(wOn) and chipA and not chipB,
                    "CHIP %s Base's row %s: the focused %s shows the focus chip (%s), the %s doesn't (%s)", name, tostring(n), on, whatA, off, whatB)
            end)
        end
        chipKey("DOWN", "to Base's gear")
        chipKey("RIGHT", "at the line's end: stays on Base's gear")
        chipKey("LEFT", "to Base's checkbox")
        chipCheck("tg", "tg", "cfg")
        shot("mm-chip-tg")
        chipKey("RIGHT", "to Base's gear")
        chipCheck("cfg", "cfg", "tg")
        shot("mm-chip-cfg")
        chipKey("LEFT", "back to the first column")
    end
    -- 2b. Story 11: the first toggle of the session, before any Configure (none may draw a restart mark first), so core's
    -- T_Restart texture is still cold when the toggle draws the first restart icon. In 0.2.0 that load ran inside the
    -- checkbox's click hook and froze the game (hand test 2026-11-17). Keyboard: DOWN until Dep's checkbox holds the
    -- focus, ENTER (TGFIRST within 10 s of the key); then a mouse click turns it back on (TGFIRSTCLICK within 10 s).
    -- A freeze means no further line and no END: the run fails.
    local function depTg() local d = rowNamed(DEP) return d and cell(d.n, "tg") end
    local function hasFocus(w) local b = prop(w, "Btn") return b ~= nil and try(function() return b:HasKeyboardFocus() end) == true end
    local function focusRow()
        for n = 1, 256 do
            if not rowW(n) then break end
            if hasFocus(cell(n, "tg")) or hasFocus(cell(n, "cfg")) then return n end
        end
        return nil
    end
    step("first: cold", function()
        R.txtFirst = readFile("mods.txt")
        local cold = true
        for _, r in ipairs(readRows()) do if r.icons:find("restart", 1, true) then cold = false end end
        check(cold and R.txtFirst ~= nil and R.txtFirst:find("ModManagerDep : 1", 1, true) ~= nil,
            "TGFIRSTCOLD no Configure opened yet, no restart icon shown, Dep on in mods.txt")
    end)
    local function toDep(tries)
        step("first: focus " .. tries, function()
            local d = rowNamed(DEP)
            local at = focusRow()
            if hasFocus(depTg()) or not d or not at or at >= d.n or tries > 10 then return end
            say("KEY DOWN (row %d to Dep's row %d)", at, d.n)
            local done = request("key DOWN")
            nested(function() settle(1) toDep(tries + 1) end)
            return done, 30, "key DOWN"
        end)
    end
    toDep(1)
    step("first: focus", function()
        local d = rowNamed(DEP)
        check(d ~= nil and hasFocus(depTg()), "TGFIRSTFOCUS Dep's checkbox (row %s) holds the keyboard focus (focus on row %s)", tostring(d and d.n), tostring(focusRow()))
    end)
    step("first: ENTER", function()
        say("KEY ENTER on Dep's checkbox (the first toggle)")
        R.firstAt = os.clock()
        return request("key ENTER"), 30, "key ENTER"
    end)
    fileWait("first toggle: Dep off in mods.txt", "mods.txt", function(t) return t:find("ModManagerDep : 0", 1, true) ~= nil end)
    waitFor("first toggle: the restart icon", function() local d = rowNamed(DEP) return d ~= nil and d.icons == "restart" and pendingShown() end, 5)
    step("first: judged", function()
        local sec = os.clock() - (R.firstAt or 0)
        local t = readFile("mods.txt")
        local d = rowNamed(DEP)
        check(sec <= 10 and t ~= nil and R.txtFirst ~= nil and t == (R.txtFirst:gsub("ModManagerDep : 1", "ModManagerDep : 0")) and d ~= nil and d.toggle == "off"
            and d.icons == "restart" and pendingShown(),
            "TGFIRST ENTER on Dep's checkbox: ': 0', box %s, icons %s, banner and QUIT GAME %s, %.1f s after the key (at most 10)",
            tostring(d and d.toggle), tostring(d and d.icons), tostring(pendingShown()), sec)
    end)
    -- 2c. Core story 42 (0.17.1): ENTER keeps the focus chip on Dep's checkbox, and the box reads as it does unfocused
    -- (its icon in its own colours over core's dark IconBack, the chip as the ring around it: CHIP.back, and the shots). CHIP enter1: focus, chip, box off; ENTER turns it
    -- on (mods.txt back to the session start's): CHIP enter2: focus, chip, box on; ENTER turns it off again, so the
    -- mouse click below finds it as before.
    local function chipEnter(name, want)
        step("chip: " .. name, function()
            local d = rowNamed(DEP)
            local w = depTg()
            local on, what = CHIP.of(w)
            local back, bwhat = CHIP.back(w)
            check(d ~= nil and CHIP.hasFocus(w) and on and back and d.toggle == want,
                "CHIP %s Dep's checkbox (row %s): focus %s, the focus chip (%s), dark inside (%s), box %s (want %s)", name, tostring(d and d.n),
                tostring(CHIP.hasFocus(w)), what, bwhat, tostring(d and d.toggle), want)
        end)
    end
    local function enterDep(label)
        step("chip: ENTER " .. label, function()
            say("KEY ENTER on Dep's checkbox (%s)", label)
            return request("key ENTER"), 30, "key ENTER"
        end)
    end
    -- CIPROBE: the CommonInput chain core's gamepad check relies on works under UE4SS (the native class found,
    -- GetLocalPlayerSubsystem(the local player controller, class) a valid subsystem, GetCurrentInputType a Lua number:
    -- 0 under the VM's keyboard input) and its simulated-click flag reads.
    step("chip: CommonInput probe", function()
        local cls = StaticFindObject("/Script/CommonInput.CommonInputSubsystem")
        local p = pc()
        local sub = v(cls) and v(p) and try(function()
            return StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary"):GetLocalPlayerSubsystem(p, cls)
        end) or nil
        local t = v(sub) and try(function() return sub:GetCurrentInputType() end)
        local sim = v(sub) and try(function() return sub.bIsGamepadSimulatedClick end)
        check(v(cls) and v(sub) and type(t) == "number" and type(sim) == "boolean", "CIPROBE class %s subsystem %s type %s (%s) simulated %s",
            tostring(v(cls)), tostring(v(sub)), tostring(t), type(t), tostring(sim))
    end)
    settle(1)
    chipEnter("enter1", "off")
    shot("mm-chip-enter-off")
    enterDep("back on")
    fileWait("chip: Dep on in mods.txt", "mods.txt", function(t) return t == R.txtFirst end)
    waitFor("chip: Dep's box on", function() local d = rowNamed(DEP) return d ~= nil and d.toggle == "on" and d.icons == "-" end, 5)
    settle(1)
    chipEnter("enter2", "on")
    shot("mm-chip-enter-on")
    enterDep("off again")
    fileWait("chip: Dep off in mods.txt", "mods.txt", function(t) return t:find("ModManagerDep : 0", 1, true) ~= nil end)
    waitFor("chip: Dep's box off", function() local d = rowNamed(DEP) return d ~= nil and d.toggle == "off" and d.icons == "restart" and pendingShown() end, 5)
    step("first: click start", function() R.firstClickAt = os.clock() end)
    clickOn("Dep's checkbox (back on)", depTg)
    fileWait("first toggle: mods.txt back", "mods.txt", function(t) return t == R.txtFirst end)
    waitFor("first toggle: no icon", function() local d = rowNamed(DEP) return d ~= nil and d.icons == "-" and d.toggle == "on" and pendingHidden() end, 5)
    step("first: click judged", function()
        local sec = os.clock() - (R.firstClickAt or 0)
        local d = rowNamed(DEP)
        check(sec <= 10 and readFile("mods.txt") == R.txtFirst and d ~= nil and d.toggle == "on" and d.icons == "-" and pendingHidden(),
            "TGFIRSTCLICK a mouse click turns Dep back on: mods.txt as at the start, box %s, icons %s, banner hidden %s, %.1f s after the click (at most 10)",
            tostring(d and d.toggle), tostring(d and d.icons), tostring(pendingHidden()), sec)
    end)
    -- Core story 42: after that mouse click (mouse mode, no chip) Dep's checkbox hides its IconBack again (Collapsed, 1).
    step("chip: back off", function()
        local ib = prop(depTg(), "IconBack")
        local vis = v(ib) and try(function() return ib:GetVisibility() end)
        check(vis == 1, "CHIP backoff Dep's checkbox after the mouse click: IconBack %s visibility %s (want 1, Collapsed)", tostring(v(ib)), tostring(vis))
    end)
    step("cursor away again", function() return request("move 5 5"), 30, "cursor away" end)
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
                    -- story 12: Configure's RUNS ON line repeats the row's scope words (the tooltip) for the gamepad
                    local runs = d and d.scope or "?"
                    check(runs == "RUNS ON: " .. r.stip, "CFGSCOPE %d %s: Configure's line %q is RUNS ON: and the row's tooltip %q", r.n, r.name, runs, r.stip)
                    say("ROW %s | %s | toggle=%s | box=%s | gear=%s | status=%d | icons=%s | need=%s | build=%s | scope=%s | stip=%s | runs=%s", r.name, r.ver, r.toggle, r.box, gear, r.status, r.icons, need, build,
                        r.scope, r.stip, runs)
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
        -- (the first toggle, off and back on, left state.json with nothing off)
        local st = readFile(STATE_REL)
        check(pendingHidden() and (st == nil or st == '{"version":1,"off":[],"seen":[]}'), "TGSTART nothing pending: no banner, no QUIT GAME, nothing off in state.json (%s)", tostring(st))
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
    waitFor("menu2 pop-in judged", popJudged(2), 30)
    shot("menu2-return") -- the returned menu with its entry in, before anything else in this phase
    settle(3)
    step("menu2: entry back", function() check(entryOf(menu()) ~= nil, "ENTRYUP2 the entry is back after the match") end)
    entryChecks("menu2")
    -- Core story 35: two more round trips, each return sampled for pop-in (NOPOPIN menu3, menu4).
    for k = 3, 4 do
        local match, back = "match" .. (k - 1), "menu" .. k
        travel(match, MATCH_MAP, "listen")
        waitWorld(match, "SmallMap", 150)
        settle(6)
        travel(back, MENU_MAP, "")
        waitWorld(back, "NewMainMenu", 150)
        waitFor(back .. " with the entry", function() return menu() ~= nil and entryOf(menu()) ~= nil end, 60)
        waitFor(back .. " pop-in judged", popJudged(k), 30)
        shot(back .. "-return")
        settle(3)
        step(back .. ": entry back", function() check(entryOf(menu()) ~= nil, "ENTRYUP%d the entry is back after the match", k) end)
        entryChecks(back)
    end
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

-- ---------------------------------------------------------------- restart (story 8): two sessions around RESTART NOW
local function buildRestart()
    local RSNAME = "ModManagerRestart"
    local LOADED_KEY = "modmanagerrestart.loaded"
    local FACTS = scriptDir .. "\\restart-facts.txt"
    local RS = {}
    local function rowNamed(name) for _, r in ipairs(readRows()) do if r.name == name then return r end end end
    local function nOf() local r = rowNamed(RSNAME) return r and r.n end
    local function clickBox()
        step("view " .. RSNAME, function() local n = nOf() if n then nested(function() intoView(n) end) end end)
        clickOn(RSNAME .. "'s tg", function() local n = nOf() return n and cell(n, "tg") end)
    end
    local function txtHas(s) return function() local t = readFile("mods.txt") return t ~= nil and t:find(s, 1, true) ~= nil end end
    local function pendingShown() return shownW(mainEl("banner")) and shownW(mainEl("quit")) and shownW(mainEl("restart")) end
    local function noneShown() return not shownW(mainEl("banner")) and not shownW(mainEl("quit")) and not shownW(mainEl("restart")) end
    local facts
    do
        local f = io.open(FACTS, "r")
        if f then
            facts = {}
            for line in (f:read("a") or ""):gmatch("[^\r\n]+") do
                local k, val = line:match("^(%w+)=(.*)$")
                if k then facts[k] = val end
            end
            f:close()
        end
    end
    say("RESTART session %d", facts and 2 or 1)

    local function menuUp(phase)
        waitWorld(phase, "NewMainMenu", 120)
        pastStartup()
        waitFor("the entry", function() return menu() ~= nil and entryOf(menu()) ~= nil end, 60)
        settle(3)
    end

    if not facts then
        -- ---- session 1
        menuUp("menu1")
        step("restart: fixture loaded", function()
            check(ModRef:GetSharedVariable(LOADED_KEY) == true, "RSLOADED1 %s loaded in session 1", RSNAME)
        end)
        openMain("first")
        step("restart: begin", function()
            local r = rowNamed(RSNAME)
            check(r ~= nil and r.toggle == "on" and r.box == "live" and r.icons == "-", "RSROW1 %s: a live box, on, no icon (%s, %s, %s)",
                RSNAME, tostring(r and r.toggle), tostring(r and r.box), tostring(r and r.icons))
            check(noneShown(), "RSHIDDEN nothing pending: no banner, QUIT GAME or RESTART NOW")
            local t = readFile("mods.txt")
            check(t ~= nil and t:find(RSNAME .. " : 1", 1, true) ~= nil, "RSTXT0 mods.txt has '%s : 1'", RSNAME)
        end)
        clickBox()
        waitFor(RSNAME .. " off in mods.txt", txtHas(RSNAME .. " : 0"), 10)
        settle(1.5)
        step("restart: pending", function()
            local r = rowNamed(RSNAME)
            check(r ~= nil and r.toggle == "off" and r.icons == "restart", "RSOFF %s: box off, the restart icon (%s, %s)", RSNAME, tostring(r and r.toggle), tostring(r and r.icons))
            check(pendingShown(), "RSSHOWN changes pending: the banner, QUIT GAME and RESTART NOW are shown")
            local q, rr = absR(mainEl("quit")), absR(mainEl("restart"))
            local sc = scale()
            check(q ~= nil and rr ~= nil and rr.b <= q.t + 1 and (q.t - rr.b) / sc <= 24 and rr.r > q.l and rr.l < q.r,
                "RSPLACE RESTART NOW sits right above QUIT GAME in the bottom-right stack (%s over %s)", rs(rr), rs(q))
        end)
        step("cursor away", function() return request("move 5 5"), 30, "cursor away" end)
        shot("mm-restart-pending")
        step("restart: core.restart twice", function()
            local mods = scriptDir:match("^(.*)[/\\][^/\\]+[/\\][Ss]cripts$") or "."
            local add = mods .. "\\" .. CORE .. "\\Scripts\\?.lua"
            if not package.path:find(add, 1, true) then package.path = package.path .. ";" .. add end
            local okM, RM = pcall(require, CORE:lower() .. ".restart")
            if not check(okM and type(RM) == "table", "RSMODULE %s.restart loads in the driver's state (%s)", CORE:lower(), okM and type(RM) or firstLine(RM)) then return end
            local m, mw = RM.mode()
            local a1, w1 = RM.start()
            local a2, w2 = RM.start()
            RS.mode, RS.s1, RS.s2 = tostring(m), tostring(a1) .. (w1 and (" " .. tostring(w1)) or ""), tostring(a2) .. (w2 and (" " .. tostring(w2)) or "")
            check(m == "direct", "RSMODE core.restart.mode() is direct on the dev copy (%s, %s)", tostring(m), tostring(mw))
            check(a1 == true, "RSSTART1 the first core.restart.start() is true (%s)", RS.s1)
            check(a2 == nil and w2 == "already started", "RSSTART2 the second is nil, \"already started\" (%s)", RS.s2)
        end)
        step("restart: save the facts", function()
            local text = string.format("mode=%s\nstart1=%s\nstart2=%s\nchecks=%d\nfailures=%d\n", RS.mode or "?", RS.s1 or "?", RS.s2 or "?", S.checks, S.failures)
            local f = io.open(FACTS, "w")
            if f then f:write(text); f:close() end
            local g = io.open(FACTS, "r")
            local back = g and g:read("a")
            if g then g:close() end
            check(back == text, "RSFACTS session 1's facts saved to restart-facts.txt")
        end)
        step("restart: click", function()
            if S.failures > 0 then
                say("RESTART not clicked: %d check(s) failed in session 1", S.failures)
                finish() -- END result=FAIL; the runner stops the game and the waiting helper
                return
            end
            local r = absR(mainEl("restart"))
            if not check(r ~= nil, "RSPOINT RESTART NOW has a point to click") then finish() return end
            local x, y = center(r)
            say("CLICK RESTART NOW at (%d,%d)", x, y)
            request(string.format("click %d %d", x, y))
            -- The game closes; this session ends here without an END line.
            return after(120), 130, "the game to close after RESTART NOW"
        end)
        step("restart: still running", function() check(false, "RSQUIT the game did not close within 120 s of the RESTART NOW click") end)
        return
    end

    -- ---- session 2
    step("restart: session 1's facts", function()
        say("FACTS mode=%s start1=%s start2=%s checks=%s failures=%s", tostring(facts.mode), tostring(facts.start1), tostring(facts.start2), tostring(facts.checks), tostring(facts.failures))
        check(facts.mode == "direct" and facts.start1 == "true" and facts.start2 == "nil already started" and facts.failures == "0" and (tonumber(facts.checks) or 0) > 0,
            "RSFACTS2 session 1: mode direct, start() true then nil \"already started\", no failed check")
    end)
    menuUp("menu1")
    step("restart: not loaded", function()
        check(ModRef:GetSharedVariable(LOADED_KEY) == nil, "RSNOTLOADED %s did not load in the relaunched game", RSNAME)
    end)
    openMain("relaunched")
    step("restart: row off", function()
        local r = rowNamed(RSNAME)
        check(r ~= nil and r.toggle == "off" and r.box == "live" and r.icons == "-", "RSROW2 %s: box off, no icon (%s, %s, %s)",
            RSNAME, tostring(r and r.toggle), tostring(r and r.box), tostring(r and r.icons))
        check(noneShown(), "RSNOPENDING nothing pending after the restart: no banner, QUIT GAME or RESTART NOW")
        local t = readFile("mods.txt")
        check(t ~= nil and t:find(RSNAME .. " : 0", 1, true) ~= nil, "RSTXT2 mods.txt has '%s : 0'", RSNAME)
    end)
    shot("mm-restart-relaunched")
    clickBox()
    waitFor(RSNAME .. " back on in mods.txt", txtHas(RSNAME .. " : 1"), 10)
    settle(1.5)
    step("restart: back on", function()
        check(pendingShown(), "RSSHOWN2 turned back on: the banner, QUIT GAME and RESTART NOW are shown again")
    end)
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

-- ---------------------------------------------------------------- apply (Mod Manager v2 story 3): four sessions
local function buildApply()
    local A, B, C = MOD .. "ApplyA", MOD .. "ApplyB", MOD .. "ApplyC"
    local LOCK_REL = "NuclearNightmare\\Binaries\\Win64\\ue4ss\\Mods\\" .. A .. "\\Scripts\\main.lua" -- relative to the game folder
    local A_FILES = { "mod.json", "Scripts\\main.lua" }
    local SESSION = scriptDir .. "\\apply-session.txt"
    local n = 1
    do
        local f = io.open(SESSION, "r")
        if f then n = (tonumber((f:read("a") or ""):match("%d+")) or 0) + 1; f:close() end
        local g = io.open(SESSION, "w")
        if g then g:write(tostring(n)); g:close() end
    end
    say("APPLY session %d", n)
    -- Core's own nucleus.apply in this state (as the restart scenario's nucleus.restart): the natives are core's.
    local function core()
        local mods = scriptDir:match("^(.*)[/\\][^/\\]+[/\\][Ss]cripts$") or "."
        local add = mods .. "\\" .. CORE .. "\\Scripts\\?.lua"
        if not package.path:find(add, 1, true) then package.path = package.path .. ";" .. add end
        local okM, M = pcall(require, CORE:lower() .. ".apply")
        if okM and type(M) == "table" then return M end
        return nil, okM and type(M) or firstLine(M)
    end
    local function st()
        local M, why = core()
        if not M then return nil, "no " .. CORE:lower() .. ".apply: " .. tostring(why) end
        return M.status()
    end
    local function show(s, why)
        if not s then return "nil, " .. tostring(why) end
        return string.format("staged=%s result=%s reason=%s path=%s attempts=%s changes=%s", tostring(s.staged), tostring(s.result),
            tostring(s.reason), tostring(s.path), tostring(s.attempts), tostring(s.changes))
    end
    local function loaded(m) return ModRef:GetSharedVariable(m:lower() .. ".loaded") == true end
    local function pendingShown() return shownW(mainEl("banner")) and shownW(mainEl("quit")) and shownW(mainEl("restart")) end
    local function startWaiting(id)
        step("apply: start the helper", function()
            local s, why = st()
            check(s ~= nil and s.staged == "pending", "APSTAGED%d the staged change is pending (%s)", id, show(s, why))
            local M = core()
            local r, rwhy
            if M then r, rwhy = M.start() end
            check(r == true, "APSTART%d core.apply.start() is true (%s, %s)", id, tostring(r), tostring(rwhy))
            s, why = st()
            check(s ~= nil and s.staged == "waiting", "APWAIT%d the helper waits (%s)", id, show(s, why))
        end)
    end
    -- Asks the runner to end this session ("kill" or "close"); a session with a failed check ends the run instead.
    local function endSession(how, label)
        step("apply: " .. how, function()
            if S.failures > 0 then
                say("APPLY not ended by %s: %d check(s) failed in session %d", how, S.failures, n)
                finish()
                return
            end
            say("%s requested", label)
            request(how)
            return after(60), 70, "the game to exit after " .. how
        end)
        step("apply: still running", function() check(false, "APEXIT the game did not exit within 60 s of %s", how) end)
    end
    local function menuUp(phase)
        waitWorld(phase, "NewMainMenu", 120)
        pastStartup()
        waitFor("the entry", function() return menu() ~= nil and entryOf(menu()) ~= nil end, 60)
        settle(3)
    end

    menuUp("menu" .. n)
    if n == 1 then
        waitFor("the apply helper waiting", function() local s = st() return s ~= nil and s.staged == "waiting" end, 30)
        step("apply: session 1", function()
            local s, why = st()
            check(s ~= nil and s.staged == "waiting", "APWAIT1 the Mod Manager started the helper at launch: staged is waiting (%s)", show(s, why))
            check(s ~= nil and s.result == "none" and (s.changes or 0) > 0, "APRESULT1 no result yet, plan A staged (%s)", show(s, why))
            check(not loaded(A), "APNOTLOADED1 %s is not loaded yet", A)
        end)
        openMain("first")
        step("apply: pending", function()
            check(pendingShown(), "APSHOWN1 the staged change is pending: the banner, QUIT GAME and RESTART NOW are shown")
        end)
        step("cursor away", function() return request("move 5 5"), 30, "cursor away" end)
        shot("mm-apply-pending")
        step("apply: click RESTART NOW", function()
            if S.failures > 0 then
                say("RESTART not clicked: %d check(s) failed in session 1", S.failures)
                finish()
                return
            end
            local r = absR(mainEl("restart"))
            if not check(r ~= nil, "APPOINT RESTART NOW has a point to click") then finish() return end
            local x, y = center(r)
            say("CLICK RESTART NOW at (%d,%d)", x, y)
            request(string.format("click %d %d", x, y))
            -- The game closes, the helper applies A and starts the game again; this session ends without an END line.
            return after(120), 130, "the game to close after RESTART NOW"
        end)
        step("apply: still running", function() check(false, "APQUIT the game did not close within 120 s of the RESTART NOW click") end)
    elseif n == 2 then
        step("apply: session 2", function()
            check(loaded(A), "APLOADED2 %s loaded: plan A was applied before the relaunch", A)
            local s, why = st()
            check(s ~= nil and s.result == "applied" and s.staged == "none", "APRESULT2 the result is applied, nothing staged (%s)", show(s, why))
        end)
        openMain("session 2")
        waitFor("the Mod Manager acks the result", function() local s = st() return s ~= nil and s.result == "none" end, 10)
        step("apply: acked", function()
            local s, why = st()
            check(s ~= nil and s.result == "none", "APACKED2 the Mod Manager acked the result when its window opened (%s)", show(s, why))
        end)
        shot("mm-apply-applied")
        step("apply: stage B", function() return request("stage B"), 60, "stage B" end)
        startWaiting(2)
        endSession("kill", "KILL")
    elseif n == 3 then
        step("apply: session 3", function()
            check(loaded(A) and loaded(B), "APLOADED3 %s and %s loaded: plan B was applied after the kill", A, B)
            local s, why = st()
            check(s ~= nil and s.result == "applied" and s.staged == "none", "APRESULT3 the result is applied, nothing staged (%s)", show(s, why))
        end)
        step("apply: stage C", function() return request("stage C"), 60, "stage C" end)
        step("apply: lock", function() return request("lock " .. LOCK_REL), 30, "lock" end)
        step("apply: locked", function()
            local f = io.open(MODS_DIR .. "\\" .. A .. "\\Scripts\\main.lua", "r+b")
            if f then f:close() end
            check(f == nil, "APLOCK3 %s's Scripts\\main.lua can't be opened for writing (the runner holds it)", A)
        end)
        startWaiting(3)
        endSession("close", "CLOSE")
    else
        step("apply: session 4", function()
            local s, why = st()
            check(s ~= nil and s.result == "failed" and s.reason == "locked" and s.path == LOCK_REL and s.attempts == 1,
                "APRESULT4 the result is failed, locked, %s, attempt 1 (%s)", LOCK_REL, show(s, why))
            check(s ~= nil and s.staged ~= "none", "APPENDING4 plan C is still staged (%s)", show(s, why))
            local same, what = true, {}
            for _, rel in ipairs(A_FILES) do
                local got, want = readFile(A .. "\\" .. rel), readFile(ME .. "\\Scripts\\apply-expect\\" .. A .. "\\" .. rel)
                if got == nil or want == nil or got ~= want then same = false; what[#what + 1] = rel .. (got == nil and " missing" or (want == nil and " (no expected copy)" or " differs")) end
            end
            check(same, "APSAME4 %s's files are byte-identical to the fixture's after the rollback (%s)", A, #what > 0 and table.concat(what, ", ") or "all same")
            local cf = {}
            for _, rel in ipairs(A_FILES) do if readFile(C .. "\\" .. rel) ~= nil then cf[#cf + 1] = rel end end
            check(#cf == 0, "APNOC4 none of %s's files exist (%s)", C, #cf > 0 and table.concat(cf, ", ") or "none")
            local t = readFile("mods.txt")
            check(not loaded(C) and t ~= nil and not t:find(C, 1, true), "APNOTLOADED4 %s not loaded and not in mods.txt", C)
        end)
        openMain("session 4")
        step("apply: still pending", function()
            check(pendingShown(), "APSHOWN4 plan C is still pending: the banner, QUIT GAME and RESTART NOW are shown")
        end)
        step("cursor away", function() return request("move 5 5"), 30, "cursor away" end)
        shot("mm-apply-failed")
        -- END only: the runner ends at END, stops the helper waiting to try plan C again, then closes the game.
        step("apply: end", function() finish() end)
    end
end

-- ---------------------------------------------------------------- browse (Mod Manager v2 story 4; VM, live catalog)
-- The Mod Manager's own log lines (CATALOG done) are read back from UE4SS.log next to Mods (the menu spike's way); the
-- Browse window's elements are found by their tags like the main window's.
local LOG_FILE = MODS_DIR .. "\\..\\UE4SS.log"
local function logCount(plain)
    local f = io.open(LOG_FILE, "rb")
    if not f then return nil end
    local s = f:read("a") or ""
    f:close()
    local n, i = 0, 1
    while true do
        local a, b = s:find(plain, i, true)
        if not a then break end
        n, i = n + 1, b + 1
    end
    return n
end
local DONE_LINE = "[" .. MOD .. "] CATALOG done "
local function bwEl(id) local _, c = screenOf("browse") return childTagged(c, id) end
local function bwFilter(k, id) return childTagged(prop(childTagged(prop(bwEl("bw.flist"), "VBox"), "bw.f" .. k), "HBox"), id) end
local function bwRow(n) return childTagged(prop(bwEl("bw.list"), "VBox"), "bw.r" .. n) end
local function bwCell(n, part) return childTagged(prop(bwRow(n), "HBox"), "bw.r" .. n .. "." .. part) end
local function choiceText(w) return try(function() return w.Value:GetText():ToString() end) end
-- The names of the Browse list's visible package rows, in order.
local function bwNames()
    local t = {}
    for n = 1, 130 do
        local r = bwRow(n)
        if not r then break end
        if shownW(r) then t[#t + 1] = textOf(bwCell(n, "name")) or "?" end
    end
    return t
end

local function buildBrowse()
    local function waitDone(k, label)
        step("wait CATALOG done " .. label, function()
            local t0 = os.clock()
            return function()
                local n = logCount(DONE_LINE)
                if n == nil then return os.clock() - t0 > 20 end -- the log can't be read: go on after 20 s
                return n >= k
            end, 150, "CATALOG done " .. label
        end)
        step("CATALOG done " .. label, function()
            local n = logCount(DONE_LINE)
            check(n == nil or n >= k, "BWDONE %s %d CATALOG done line(s) (want %d)", label, n or -1, k)
        end)
    end
    local function key(k)
        step("key " .. k, function() say("KEY %s", k) return request("key " .. k), 30, "key " .. k end)
        settle(1)
    end
    local function openBrowse(label)
        clickOn("BROWSE " .. label, function() return mainEl("browse") end)
        waitFor("Browse " .. label, function() return screenOf("browse") ~= nil and bwEl("bw.title") ~= nil end, 15)
        settle(2)
    end

    -- 1. The menu, the startup refresh's done.
    waitWorld("menu1", "NewMainMenu", 120)
    pastStartup()
    waitFor("the entry", function() return menu() ~= nil and entryOf(menu()) ~= nil end, 60)
    settle(2)
    waitDone(1, "startup")
    -- 2. Manage Mods (the installed rows, ROW lines), then BROWSE.
    openMain("first")
    step("rows", function()
        local rows = readRows()
        check(#rows >= 3, "BWROWS %d installed rows", #rows)
        for _, r in ipairs(rows) do say("ROW %s | %s", r.name, r.ver) end
    end)
    openBrowse("first")
    step("browse opened", function()
        check(textOf(bwEl("bw.title")) == "BROWSE MODS", "BWOPEN the BROWSE MODS window (title %s)", tostring(textOf(bwEl("bw.title"))))
        local names = bwNames()
        check(#names >= 5, "BWLIST %d package rows (at least the five for this build): %s", #names, table.concat(names, ", "))
        say("BROWSE rows %s", table.concat(names, " | "))
        say("BROWSE age %s", tostring(textOf(bwEl("bw.age"))))
        say("BROWSE count %s", tostring(textOf(bwEl("bw.count"))))
    end)
    step("cursor away", function() return request("move 5 5"), 30, "cursor away" end)
    settle(1)
    shot("browse")
    -- 3. CATEGORY to AUDIO with keys (focus opens on the search box; DOWN to CATEGORY, RIGHT steps it), then SHOW to
    -- INSTALLED (DOWN, RIGHT).
    key("DOWN")
    for _ = 1, 4 do key("RIGHT") end
    step("category audio", function()
        local t = choiceText(bwFilter(2, "bw.cat"))
        check(t == "AUDIO", "BWCAT CATEGORY reads %s after DOWN and four RIGHTs (want AUDIO)", tostring(t))
    end)
    key("DOWN")
    key("RIGHT")
    step("show installed", function()
        local t = choiceText(bwFilter(3, "bw.show"))
        check(t == "INSTALLED", "BWSHOW SHOW reads %s after DOWN and RIGHT (want INSTALLED)", tostring(t))
    end)
    -- 4. Reset: BACK, then BROWSE again (filters reset on open); the search box clicked, "clock" typed, ENTER.
    clickOn("Browse's BACK", function() return closeOf("browse") end)
    waitFor("Browse closed", function() return screenOf("browse") == nil end, 10)
    openBrowse("again")
    step("reset", function()
        local c, s = choiceText(bwFilter(2, "bw.cat")), choiceText(bwFilter(3, "bw.show"))
        check(c == "ALL" and s == "ALL", "BWRESET the filters are reset on open (CATEGORY %s, SHOW %s)", tostring(c), tostring(s))
    end)
    clickOn("the search box", function() return bwFilter(1, "bw.q") end)
    step("type clock", function() return request("type clock"), 30, "type clock" end)
    settle(2)
    key("ENTER")
    settle(1)
    step("search clock", function()
        local names = bwNames()
        check(#names == 1 and names[1] == "HUD Clock", "BWSEARCH 'clock' leaves one row: %s", table.concat(names, ", "))
    end)
    -- 5. DETAILS on the first row, a screenshot, BACK.
    clickOn("DETAILS 1", function() return bwCell(1, "det") end)
    waitFor("Details", function() return screenOf("details") ~= nil end, 10)
    settle(2)
    step("details", function()
        local _, c = screenOf("details")
        local t = textOf(childTagged(c, "dt.title"))
        check(t == "HUD Clock", "BWDETAILS the Details window shows %s", tostring(t))
    end)
    step("cursor away (details)", function() return request("move 5 5"), 30, "cursor away" end)
    settle(1)
    shot("details")
    clickOn("Details' BACK", function() return closeOf("details") end)
    waitFor("Details closed", function() return screenOf("details") == nil and screenOf("browse") ~= nil end, 10)
    -- 6. REFRESH: a second done.
    clickOn("REFRESH", function() return bwEl("bw.refresh") end)
    waitDone(2, "after REFRESH")
    settle(2)
    step("browse: end", function() finish() end)
end

-- ---------------------------------------------------------------- install (Mod Manager v2 story 5; VM, live catalog)
-- Two sessions, counted in install-session.txt next to this file. Session 1: INSTALL on HUD Clock (its confirm, the
-- stage, RESTART NOW); session 2: HUD Clock applied by core's helper, loaded, and listed INSTALLED.
local function bwDesc(n, part) return childTagged(prop(childTagged(prop(bwEl("bw.list"), "VBox"), "bw.d" .. n), "HBox"), "bw.r" .. n .. "." .. part) end
local function buildInstall()
    local HC_NAME, HC_TAG = "HUD Clock", "[HudClock]"
    local SESSION = scriptDir .. "\\install-session.txt"
    local n = 1
    do
        local f = io.open(SESSION, "r")
        if f then n = (tonumber((f:read("a") or ""):match("%d+")) or 0) + 1; f:close() end
        local g = io.open(SESSION, "w")
        if g then g:write(tostring(n)); g:close() end
    end
    say("INSTALL session %d", n)
    local function applyStatus()
        local mods = scriptDir:match("^(.*)[/\\][^/\\]+[/\\][Ss]cripts$") or "."
        local add = mods .. "\\" .. CORE .. "\\Scripts\\?.lua"
        if not package.path:find(add, 1, true) then package.path = package.path .. ";" .. add end
        local okM, M = pcall(require, CORE:lower() .. ".apply")
        if not (okM and type(M) == "table") then return nil, "no " .. CORE:lower() .. ".apply" end
        return M.status()
    end
    local function show(s, why)
        if not s then return "nil, " .. tostring(why) end
        return string.format("staged=%s result=%s reason=%s attempts=%s changes=%s", tostring(s.staged), tostring(s.result), tostring(s.reason), tostring(s.attempts), tostring(s.changes))
    end
    local function waitLog(plain, label, sec)
        step("wait " .. label, function()
            return function() local k = logCount(plain) return k ~= nil and k >= 1 end, sec, label
        end)
    end
    local function search(text)
        clickOn("the search box", function() return bwFilter(1, "bw.q") end)
        step("type " .. text, function() return request("type " .. text), 30, "type " .. text end)
        settle(2)
        step("key ENTER", function() return request("key ENTER"), 30, "key ENTER" end)
        settle(1)
    end
    local function openBrowse(label)
        clickOn("BROWSE " .. label, function() return mainEl("browse") end)
        waitFor("Browse " .. label, function() return screenOf("browse") ~= nil and bwEl("bw.title") ~= nil end, 15)
        settle(2)
    end

    waitWorld("menu" .. n, "NewMainMenu", 120)
    pastStartup()
    waitFor("the entry", function() return menu() ~= nil and entryOf(menu()) ~= nil end, 60)
    settle(2)
    step("wait CATALOG done", function() return function() local k = logCount(DONE_LINE) return k ~= nil and k >= 1 end, 150, "CATALOG done" end)
    if n == 1 then
        openMain("first")
        openBrowse("first")
        search("clock")
        step("install: the row", function()
            local names = bwNames()
            check(#names == 1 and names[1] == HC_NAME, "INROW 'clock' leaves %s (%s)", HC_NAME, table.concat(names, ", "))
            check(textOf(bwCell(1, "st")) == "NOT INSTALLED", "INSTATE %s reads NOT INSTALLED (%s)", HC_NAME, tostring(textOf(bwCell(1, "st"))))
            check(shownW(bwDesc(1, "inst")), "INBUTTON %s's row shows INSTALL", HC_NAME)
        end)
        clickOn("INSTALL", function() return bwDesc(1, "inst") end)
        waitFor("the install confirm", function() return screenOf("install") ~= nil end, 15)
        settle(2)
        step("install: the confirm", function()
            local _, c = screenOf("install")
            local title = textOf(childTagged(c, "in.title"))
            check(title == "INSTALL HUD CLOCK 0.3.0?", "INTITLE the confirm reads %s", tostring(title))
            check(not shownW(childTagged(c, "in.also")), "INNOALSO no ALSO INSTALLS (the installed Nucleus meets HUD Clock's need)")
            local size = textOf(childTagged(c, "in.size"))
            check(size == "DOWNLOAD 9 KB", "INSIZE the confirm reads %s (8620 bytes)", tostring(size))
            check(shownW(childTagged(c, "in.ok")), "INOK the confirm shows INSTALL")
        end)
        step("cursor away", function() return request("move 5 5"), 30, "cursor away" end)
        settle(1)
        shot("install-confirm")
        clickOn("the confirm's INSTALL", function() local _, c = screenOf("install") return childTagged(c, "in.ok") end)
        waitLog("[" .. MOD .. "] INSTALL done ", "INSTALL done", 300)
        settle(2)
        step("install: done", function()
            check((logCount("[" .. MOD .. "] INSTALL done outcome=ok ") or 0) == 1, "INDONE the stage ended ok")
            local s, why = applyStatus()
            check(s ~= nil and s.staged == "waiting", "INWAIT core's helper waits for the game to exit (%s)", show(s, why))
            check(textOf(bwCell(1, "st")) == "PENDING RESTART", "INPENDING the row reads PENDING RESTART (%s)", tostring(textOf(bwCell(1, "st"))))
            check(not shownW(bwDesc(1, "inst")), "INNOBUTTON no INSTALL on a staged row")
            local msg = textOf(bwEl("bw.status"))
            check(msg == "HUD CLOCK INSTALLS WHEN THE GAME RESTARTS", "INMSG the message reads %s", tostring(msg))
        end)
        step("cursor away", function() return request("move 5 5"), 30, "cursor away" end)
        settle(1)
        shot("install-pending")
        clickOn("Browse's BACK", function() return closeOf("browse") end)
        waitFor("Browse closed", function() return screenOf("browse") == nil end, 10)
        step("install: RESTART NOW shown", function()
            check(shownW(mainEl("quit")) and shownW(mainEl("restart")), "INRESTART QUIT GAME and RESTART NOW are shown")
        end)
        step("install: click RESTART NOW", function()
            if S.failures > 0 then
                say("RESTART not clicked: %d check(s) failed in session 1", S.failures)
                finish()
                return
            end
            local r = absR(mainEl("restart"))
            if not check(r ~= nil, "INPOINT RESTART NOW has a point to click") then finish() return end
            local x, y = center(r)
            say("CLICK RESTART NOW at (%d,%d)", x, y)
            request(string.format("click %d %d", x, y))
            -- The game closes, core's helper applies the staged change and starts the game again: no END line here.
            return after(120), 130, "the game to close after RESTART NOW"
        end)
        step("install: still running", function() check(false, "INQUIT the game did not close within 120 s of the RESTART NOW click") end)
    else
        waitLog(HC_TAG, "HUD Clock's log line", 60)
        step("install: session 2", function()
            local s, why = applyStatus()
            check(s ~= nil and (s.result == "applied" or s.result == "none") and s.staged == "none", "INAPPLIED nothing staged any more (%s)", show(s, why))
            check((logCount(HC_TAG) or 0) >= 1, "INLOADED %s logs: HUD Clock runs", HC_TAG)
            local t = readFile("mods.txt") or ""
            local ih, ik = t:find("HudClock : 1", 1, true), t:find("Keybinds : 1", 1, true)
            check(ih ~= nil and ik ~= nil and ih < ik, "INMODSTXT mods.txt has HudClock : 1 above Keybinds : 1")
            local j = readFile("HudClock\\mod.json") or ""
            check(j:find('"version": "0.3.0"', 1, true) ~= nil or j:find('"version":"0.3.0"', 1, true) ~= nil, "INJSON Mods/HudClock/mod.json is 0.3.0")
        end)
        openMain("session 2")
        openBrowse("session 2")
        search("clock")
        step("install: installed", function()
            local names = bwNames()
            check(#names == 1 and names[1] == HC_NAME, "INROW2 'clock' leaves %s (%s)", HC_NAME, table.concat(names, ", "))
            check(textOf(bwCell(1, "st")) == "INSTALLED", "ININSTALLED %s reads INSTALLED (%s)", HC_NAME, tostring(textOf(bwCell(1, "st"))))
            check(not shownW(bwDesc(1, "inst")), "INNOBUTTON2 no INSTALL on an installed row")
        end)
        step("cursor away", function() return request("move 5 5"), 30, "cursor away" end)
        settle(1)
        shot("install-installed")
        step("install: end", function() finish() end)
    end
end

-- ---------------------------------------------------------------- update (Mod Manager v2 story 6; VM, fixture catalog)
-- Two sessions, counted in update-session.txt next to this file. Session 1: the title-screen notice, REVIEW, UPDATE TO
-- 0.3.1 and its confirm; MANAGE MODS: the notice line, UPDATES, the Nucleus update; BROWSE, WhistleMute's Details,
-- UNINSTALL and its confirm; RESTART NOW. Session 2: what core's helper applied.
-- A core element on the title-screen menu host (page 0 of the menu's root WidgetSwitcher), searched a few levels down.
local function menuHostEl(id)
    local page = try(function() return prop(menu(), "WidgetSwitcher_1"):GetChildAt(0) end)
    if not v(page) then return nil end
    local want = TAG .. id
    local function walk(w, depth)
        if not v(w) or depth > 4 then return nil end
        if ctag(w) == want then return w end
        local n = try(function() return w:GetChildrenCount() end) or 0
        for i = 0, n - 1 do
            local f = walk(try(function() return w:GetChildAt(i) end), depth + 1)
            if f then return f end
        end
        return nil
    end
    return walk(page, 0)
end
local function rvRow(k) local _, c = screenOf("revoked") return childTagged(prop(childTagged(c, "rv.list"), "VBox"), "rv.r" .. k) end
local function rvEl(k, part) return childTagged(prop(rvRow(k), "HBox"), "rv.r" .. k .. "." .. part) end
local function winEl(win, id) local _, c = screenOf(win) return childTagged(c, id) end
local function noticeEl(id) return childTagged(prop(childTagged(prop(mainEl("notice.list"), "VBox"), "notice"), "HBox"), id) end
-- The Browse row (1-based) whose name reads name, or nil.
local function bwRowNamed(name)
    for n = 1, 130 do
        local r = bwRow(n)
        if not r then break end
        if shownW(r) and textOf(bwCell(n, "name")) == name then return n end
    end
    return nil
end
local function buildUpdate()
    local HC, NU, WM = "HUD Clock", "Nucleus (Mod Core)", "Whistle Emote Mute"
    local SESSION = scriptDir .. "\\update-session.txt"
    local n = 1
    do
        local f = io.open(SESSION, "r")
        if f then n = (tonumber((f:read("a") or ""):match("%d+")) or 0) + 1; f:close() end
        local g = io.open(SESSION, "w")
        if g then g:write(tostring(n)); g:close() end
    end
    say("UPDATE session %d", n)
    local function applyStatus()
        local add = MODS_DIR .. "\\" .. CORE .. "\\Scripts\\?.lua"
        if not package.path:find(add, 1, true) then package.path = package.path .. ";" .. add end
        local okM, M = pcall(require, CORE:lower() .. ".apply")
        if not (okM and type(M) == "table") then return nil, "no " .. CORE:lower() .. ".apply" end
        return M.status()
    end
    local function waitLogN(plain, k0, label, sec)
        step("wait " .. label, function() return function() local k = logCount(plain) return k ~= nil and k >= k0 end, sec, label end)
    end
    local function away() step("cursor away", function() return request("move 5 5"), 30, "cursor away" end) settle(1) end
    local function closeWin(id)
        step("close " .. id, function()
            if not screenOf(id) then return end
            local r = absR(closeOf(id))
            if not check(r ~= nil, "POINT %s's BACK has a point to click", id) then return end
            local x, y = center(r)
            say("CLICK %s BACK at (%d,%d)", id, x, y)
            return request(string.format("click %d %d", x, y)), 40, "close " .. id
        end)
        settle(1.5)
    end
    local function search(text)
        clickOn("the search box", function() return bwFilter(1, "bw.q") end)
        step("type " .. text, function() return request("type " .. text), 30, "type " .. text end)
        settle(2)
        step("key ENTER", function() return request("key ENTER"), 30, "key ENTER" end)
        settle(1)
    end
    local UPD_DONE = "[" .. MOD .. "] UPDATE done "
    -- The core version the fixture catalog offers (deploy.ps1 made it one patch above core's build): its index.json (the
    -- package entry: its id followed by its name, unlike a dependsOn entry).
    local CORE_NEW = (readFile(ME .. "\\fixture\\index.json") or ""):match('"id":%s*"nuclearnightmare%-community%.' .. CORE:lower() .. '",%s*"name".-"versions":%s*%[%s*{%s*"version":%s*"([^"]+)"') or "?"
    local ARROW = "\u{2192}"

    waitWorld("menu" .. n, "NewMainMenu", 120)
    pastStartup()
    waitFor("the entry", function() return menu() ~= nil and entryOf(menu()) ~= nil end, 60)
    settle(2)
    step("wait CATALOG done", function() return function() local k = logCount(DONE_LINE) return k ~= nil and k >= 1 end, 150, "CATALOG done" end)
    settle(2)
    if n == 1 then
        -- 1. the title-screen notice
        waitFor("the title notice", function() return menuHostEl("tn.text") ~= nil end, 20)
        step("update: title notice", function()
            local t = textOf(menuHostEl("tn.text"))
            check(t == "HUD CLOCK 0.3.0 WAS REVOKED", "UPNOTICE the title screen reads %s", tostring(t))
            check(shownW(menuHostEl("tn.review")), "UPREVIEWBTN the title screen shows REVIEW")
            check((logCount("[" .. MOD .. "] NOTICE shown n=1") or 0) == 1, "UPNOTICELOG NOTICE shown n=1 logged once")
        end)
        away()
        shot("update-notice")
        -- 2. REVIEW, UPDATE TO 0.3.1, the confirm
        clickOn("the title notice's REVIEW", function() return menuHostEl("tn.review") end)
        waitFor("the revoked window", function() return screenOf("revoked") ~= nil and rvEl(1, "upd") ~= nil end, 15)
        settle(2)
        step("update: revoked window", function()
            check(textOf(rvEl(1, "name")) == HC, "UPRVNAME the revoked window's row is %s (%s)", HC, tostring(textOf(rvEl(1, "name"))))
            check(shownW(rvEl(1, "upd")) and shownW(rvEl(1, "un")), "UPRVBUTTONS UPDATE TO and UNINSTALL are shown")
            check(not shownW(rvRow(2)), "UPRVONE one revoked row")
        end)
        away()
        shot("update-revoked")
        clickOn("UPDATE TO", function() return rvEl(1, "upd") end)
        waitFor("the update confirm", function() return screenOf("install") ~= nil end, 15)
        settle(2)
        step("update: the confirm", function()
            local t = textOf(winEl("install", "in.title"))
            check(t == "UPDATE HUD CLOCK 0.3.0 " .. ARROW .. " 0.3.1?", "UPTITLE the confirm reads %s", tostring(t))
            check(not shownW(winEl("install", "in.also")), "UPNOALSO no ALSO INSTALLS")
            check(shownW(winEl("install", "in.ok")), "UPOK the confirm shows UPDATE")
        end)
        away()
        shot("update-confirm")
        clickOn("the confirm's UPDATE", function() return winEl("install", "in.ok") end)
        waitLogN(UPD_DONE, 1, "UPDATE done (HUD Clock)", 300)
        settle(2)
        -- 3. the notice goes; MANAGE MODS: the notice line
        step("update: HUD Clock staged", function()
            check((logCount(UPD_DONE .. "outcome=ok ") or 0) == 1, "UPDONE1 the HUD Clock update staged ok")
            check((logCount("[" .. MOD .. "] NOTICE removed") or 0) == 1, "UPREMOVED NOTICE removed")
            check(not shownW(menuHostEl("tn.text")), "UPNONOTICE the title notice is gone")
        end)
        closeWin("revoked")
        openMain("update")
        step("update: notice line", function()
            local t = textOf(noticeEl("notice.text"))
            check(t == "1 UPDATES AVAILABLE", "UPLINE the notice line reads %s", tostring(t))
            check(shownW(noticeEl("notice.updates")) and not shownW(noticeEl("notice.review")), "UPLINEBTN UPDATES shown, REVIEW not")
            local arrow = false
            for _, r in ipairs(readRows()) do
                say("ROW %s | %s | %s", r.name, r.ver, r.icons)
                if r.ver:find(ARROW, 1, true) then arrow = true end
            end
            check(arrow, "UPARROW a row's version cell reads <installed> -> <offered>")
        end)
        away()
        shot("update-main")
        -- 4. UPDATES, the Nucleus update
        clickOn("UPDATES", function() return noticeEl("notice.updates") end)
        waitFor("Browse (updates)", function() return screenOf("browse") ~= nil and bwEl("bw.title") ~= nil end, 15)
        settle(3)
        step("update: Browse updates", function()
            say("BWROWS %s", table.concat(bwNames(), ", "))
            local h = bwRowNamed(HC)
            check(h ~= nil and textOf(bwCell(h, "st")) == "PENDING RESTART", "UPPENDING %s reads PENDING RESTART (%s)", HC, h and tostring(textOf(bwCell(h, "st"))) or "no row")
            check(h ~= nil and not shownW(bwDesc(h, "inst")), "UPPENDBTN no UPDATE on the staged row")
            local c = bwRowNamed(NU)
            check(c ~= nil and shownW(bwDesc(c, "inst")), "UPCOREROW %s shows UPDATE", NU)
        end)
        clickOn("Nucleus UPDATE", function() local c = bwRowNamed(NU) return c and bwDesc(c, "inst") end)
        waitFor("the Nucleus update confirm", function() return screenOf("install") ~= nil end, 15)
        settle(2)
        step("update: the Nucleus confirm", function()
            local t = textOf(winEl("install", "in.title")) or ""
            check(t:find("UPDATE NUCLEUS (MOD CORE) ", 1, true) == 1 and t:find(ARROW .. " " .. CORE_NEW .. "?", 1, true) ~= nil, "UPCORETITLE the confirm reads %s", t)
        end)
        clickOn("the Nucleus confirm's UPDATE", function() return winEl("install", "in.ok") end)
        waitLogN(UPD_DONE, 2, "UPDATE done (Nucleus)", 300)
        settle(2)
        step("update: Nucleus staged", function()
            check((logCount(UPD_DONE .. "outcome=ok ") or 0) == 2, "UPDONE2 the Nucleus update staged ok")
        end)
        closeWin("browse")
        -- 5. BROWSE, WhistleMute's Details, UNINSTALL
        clickOn("BROWSE", function() return mainEl("browse") end)
        waitFor("Browse", function() return screenOf("browse") ~= nil and bwEl("bw.title") ~= nil end, 15)
        settle(2)
        search("whistle")
        step("update: WhistleMute row", function()
            check(bwRowNamed(WM) ~= nil, "UPWMROW 'whistle' shows %s (%s)", WM, table.concat(bwNames(), ", "))
        end)
        clickOn("DETAILS " .. WM, function() local r = bwRowNamed(WM) return r and bwCell(r, "det") end)
        waitFor("Details", function() return screenOf("details") ~= nil and winEl("details", "dt.uninstall") ~= nil end, 15)
        settle(2)
        step("update: Details", function()
            check(shownW(winEl("details", "dt.uninstall")), "UPDTUN Details shows UNINSTALL")
        end)
        clickOn("UNINSTALL", function() return winEl("details", "dt.uninstall") end)
        waitFor("the uninstall confirm", function() return screenOf("uninstall") ~= nil end, 15)
        settle(2)
        step("update: the uninstall confirm", function()
            local t = textOf(winEl("uninstall", "un.title"))
            check(t == "UNINSTALL WHISTLE EMOTE MUTE 0.2.1?", "UPUNTITLE the confirm reads %s", tostring(t))
            local l = textOf(winEl("uninstall", "un.line"))
            check(l == "REMOVES ITS FILES AND ITS MODS.TXT LINE", "UPUNLINE the confirm's line reads %s", tostring(l))
        end)
        away()
        shot("update-uninstall")
        clickOn("the confirm's UNINSTALL", function() return winEl("uninstall", "un.ok") end)
        waitLogN("[" .. MOD .. "] UNINSTALL done ", 1, "UNINSTALL done", 300)
        settle(2)
        step("update: all staged", function()
            check((logCount("[" .. MOD .. "] UNINSTALL done outcome=ok ") or 0) == 1, "UPUNDONE the uninstall staged ok")
            local s, why = applyStatus()
            check(s ~= nil and s.staged == "waiting", "UPWAIT core's helper waits for the game to exit (%s)", s and tostring(s.staged) or tostring(why))
        end)
        away()
        shot("update-staged")
        closeWin("details")
        closeWin("browse")
        step("update: RESTART NOW shown", function()
            check(shownW(mainEl("restart")), "UPRESTART RESTART NOW is shown")
        end)
        step("update: click RESTART NOW", function()
            if S.failures > 0 then
                say("RESTART not clicked: %d check(s) failed in session 1", S.failures)
                finish()
                return
            end
            local r = absR(mainEl("restart"))
            if not check(r ~= nil, "UPPOINT RESTART NOW has a point to click") then finish() return end
            local x, y = center(r)
            say("CLICK RESTART NOW at (%d,%d)", x, y)
            request(string.format("click %d %d", x, y))
            return after(120), 130, "the game to close after RESTART NOW"
        end)
        step("update: still running", function() check(false, "UPQUIT the game did not close within 120 s of the RESTART NOW click") end)
    else
        waitLogN("[HudClock]", 1, "HUD Clock's log line", 60)
        step("update: session 2", function()
            local s, why = applyStatus()
            check(s ~= nil and s.staged == "none", "UPAPPLIED nothing staged any more (%s)", s and string.format("staged=%s result=%s reason=%s", tostring(s.staged), tostring(s.result), tostring(s.reason)) or tostring(why))
            -- The fixture's core is the normal build with its mod.json version patched (READY reports the version built
            -- into its files): its mod.json, a READY line, and no test main.dll (check.ps1: no catalog-test.json read).
            local cj = readFile(CORE .. "\\mod.json") or ""
            check(cj:find('"version"%s*:%s*"' .. CORE_NEW:gsub("%.", "%%.") .. '"') ~= nil and (logCount("[" .. CORE .. "] READY version=") or 0) >= 1,
                "UPCORE %s %s installed and running", CORE, CORE_NEW)
            check((logCount("[HudClock]") or 0) >= 1, "UPLOADED [HudClock] logs: HUD Clock runs")
            local j = readFile("HudClock\\mod.json") or ""
            check(j:find('"version"%s*:%s*"0%.3%.1"') ~= nil, "UPJSON Mods/HudClock/mod.json is 0.3.1")
            check(readFile("HudClock\\Scripts\\old-0.3.0.txt") == nil, "UPOLDFILE the file only 0.3.0 had is gone")
            check(readFile("WhistleMute\\mod.json") == nil and readFile("WhistleMute\\Scripts\\main.lua") == nil, "UPWMGONE WhistleMute's files are gone")
            local t = readFile("mods.txt") or ""
            check(not t:find("WhistleMute", 1, true), "UPWMLINE mods.txt has no WhistleMute line")
            local ih, ik = t:find("HudClock : 1", 1, true), t:find("Keybinds : 1", 1, true)
            check(ih ~= nil and ik ~= nil and ih < ik, "UPMODSTXT mods.txt keeps HudClock : 1 above Keybinds : 1")
            check(not shownW(menuHostEl("tn.text")), "UPNONOTICE2 no title notice")
            -- The helper renamed its running copy to bin\<Core>Restart.<txn>.old (core's self-update); only a later
            -- helper start deletes it (none starts while nothing is staged), so this is reported, not required.
            local r = readFile("..\\" .. CORE .. "Data\\apply-result.txt") or ""
            local txn = r:match("txn\t(%x+)")
            local state = "unknown"
            if txn then state = readFile(CORE .. "\\bin\\" .. CORE .. "Restart." .. txn .. ".old") ~= nil and "present" or "absent" end
            say("UPOLD %s txn=%s", state, tostring(txn))
        end)
        openMain("session 2")
        step("update: rows", function()
            local hc
            for _, r in ipairs(readRows()) do
                say("ROW %s | %s | %s", r.name, r.ver, r.icons)
                if r.name == HC then hc = r end
            end
            check(hc ~= nil and hc.ver == "0.3.1", "UPROW2 %s's row reads 0.3.1 (%s)", HC, hc and hc.ver or "no row")
        end)
        away()
        shot("update-session2")
        step("update: end", function() finish() end)
    end
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

local build = ({ screen = buildScreen, restart = buildRestart, apply = buildApply, browse = buildBrowse, install = buildInstall, update = buildUpdate, ["no-core"] = buildNoEntry, ["old-core"] = buildNoEntry })[SCENARIO]
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
