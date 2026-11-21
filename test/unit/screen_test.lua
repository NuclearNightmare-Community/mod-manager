-- Unit tests for Scripts/screen.lua against a fake core.ui (test/unit/fakeui.lua): the windows' elements, ids, icon
-- keys, dimmed, tooltips, overflow, the header's mirror of a row, reuse on a second open, hiding rows past the count,
-- the 200-row list, the Configure window; story 6: the lock and the checkbox, the status icons, QUIT GAME, the banner
-- and the message line, the confirm and alert windows, Configure's problem lines and settings controls.
-- Run from the repo root:  texlua test/unit/screen_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
package.path = ROOT .. "/Scripts/?.lua;" .. ROOT .. "/test/unit/?.lua;" .. package.path
local Screen = require("screen")
local S = require("strings")
local FakeUi = require("fakeui")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. tostring(got) .. ", want " .. tostring(want)) end

local SIZE = { w = 1920, h = 1080 }
local function row(t)
    local r = { key = (t.folder or t.name):lower(), folder = t.folder, name = t.name, version = t.version, pakOnly = t.pakOnly or false,
        state = t.state or "off", settings = t.settings or false, need = t.need, build = t.build, paks = t.paks or {}, st = t.st,
        scope = t.scope }
    return r
end
local ROWS = {
    row{ folder = "Nucleus", name = "Nucleus", version = "0.8.0", state = "locked", build = "V8.2.3 26601774", paks = { "Nucleus.pak" }, scope = "client" },
    row{ folder = "ModManager", name = "Mod Manager", version = "0.1.0", state = "locked", need = ">=0.8.0", build = "V8.2.3 26601774", scope = "client" },
    row{ folder = "ModManagerFixture", name = "ModManagerFixture", version = "9.9.9", state = "off", settings = true, need = ">=0.1.0", build = "V0.0.0 1", scope = "host" },
    row{ folder = "ModManagerDriver", name = "ModManagerDriver", state = "on" },
    row{ name = "ModManagerPak", pakOnly = true, state = "on", paks = { "ModManagerPak_P.pak" }, scope = "unknown" },
}
-- Story 12: each row's expected scope icon key.
local SCOPES = { "client", "client", "host", "unknown", "unknown" }

do -- First open: the window, the title, the header, the lists, one row per mod.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    local w = v:openMain(ROWS, "en", SIZE)
    eq(w.id, "main", "the main window's id")
    eq(U.count("screen.open"), 1, "one screen.open")
    eq(U.calls[1].name, "screen.open", "the window opens first (its handle places the elements)")
    eq(U.calls[1].args[1].close, nil, "core's Close (close not turned off)")
    local t = U.byId.title
    ok(t and t.text == "MOD MANAGER" and t.style.font == "title" and t.place.screen == w, "title MOD MANAGER on the window")
    local hl, l = U.byId["hdr.list"], U.byId.list
    ok(hl.size.w == l.size.w and hl.style == nil and l.style == nil, "header list and list: same width and style")
    eq(l.size.w, 1920 - Screen.SIDE_RESERVE, "list width: the layout width less the side reserve")
    -- header: spacer | NAME (fill 4) | VERSION (fill 1) | three status spacers | spacer
    local hon, hname, hver, hcfg = U.byId["hdr.on"], U.byId["hdr.name"], U.byId["hdr.ver"], U.byId["hdr.cfg"]
    ok(hon.kind == "image" and hon.image == nil and hon.size == Screen.ICON and hon.place.fill == nil, "header: a spacer of the toggle box's size, no fill")
    ok(hname.text == "NAME" and hname.place.fill == 4 and hver.text == "VERSION" and hver.place.fill == 1, "header: NAME 4, VERSION 1")
    for k = 1, 3 do
        local h = U.byId["hdr.s" .. k]
        ok(h and h.kind == "image" and h.image == nil and h.size == Screen.ICON and h.place.fill == nil, "header: status spacer " .. k)
    end
    eq(U.byId["hdr.st"], nil, "story 3's empty status text is gone")
    ok(hcfg.kind == "image" and hcfg.image == nil and hcfg.size == Screen.ICON, "header: a spacer of the gear's size")
    eq(U.byId.hdr.place.list, U.byId["hdr.list"].handle, "the header row is in the header list")
    local order = {}
    for _, c in ipairs(U.calls) do local o = c.args[1] if type(o) == "table" and o.place and o.place.row == U.byId.hdr.handle then order[#order + 1] = o.id end end
    eq(table.concat(order, ","), "hdr.on,hdr.name,hdr.ver,hdr.sc,hdr.s1,hdr.s2,hdr.s3,hdr.cfg", "header cells in a row's order")
    local hsc = U.byId["hdr.sc"]
    ok(hsc.kind == "image" and hsc.image == nil and hsc.size == Screen.ICON and hsc.place.fill == nil and hsc.tooltip == nil, "story 12 header: a spacer above the scope column")
    order = {}
    for _, c in ipairs(U.calls) do local o = c.args[1] if type(o) == "table" and o.place and o.place.row == U.byId.r1.handle and c.name:match("create") then order[#order + 1] = o.id end end
    eq(table.concat(order, ","), "r1.on,r1.tg,r1.name,r1.ver,r1.sc,r1.s1,r1.s2,r1.s3,r1.cfg", "row cells: lock, checkbox, name, version, scope, three status icons, gear")
    for n, r in ipairs(ROWS) do
        local p = "r" .. n
        ok(U.byId[p] and U.byId[p].place.list == l.handle and U.byId[p].visible, p .. " in the list, shown")
        eq(U.byId[p .. ".name"].text, r.name, p .. " name")
        eq(U.byId[p .. ".name"].style.overflow, "ellipsis", p .. " name cut with an ellipsis")
        eq(U.byId[p .. ".name"].place.fill, 4, p .. " name fill 4")
        eq(U.byId[p .. ".ver"].style.overflow, "ellipsis", p .. " version cut with an ellipsis")
        eq(U.byId[p .. ".ver"].place.fill, 1, p .. " version fill 1")
        for k = 1, 3 do
            local si = U.byId[p .. ".s" .. k]
            ok(si.kind == "image" and si.size == Screen.ICON and si.place.fill == nil and si.image == nil and si.tooltip == nil, p .. " status " .. k .. ": an empty fixed image")
        end
        -- story 12: the scope icon, from the data, with its words as the tooltip
        local sc = U.byId[p .. ".sc"]
        ok(sc.kind == "image" and sc.size == Screen.ICON and sc.place.fill == nil and sc.image and sc.image.icon == "scope-" .. SCOPES[n], p .. " scope: scope-" .. SCOPES[n], sc.image and sc.image.icon)
        ok(sc.dimmed == nil and sc.visible ~= false, p .. " scope: shown, never dimmed")
        local on, tg = U.byId[p .. ".on"], U.byId[p .. ".tg"]
        ok(on.kind == "image" and on.size == Screen.ICON and on.place.fill == nil and on.image.icon == "lock", p .. " lock: an image, fixed size, no fill")
        ok(tg.kind == "checkbox" and tg.size == Screen.ICON and tg.place.fill == nil and type(tg.onChange) == "function", p .. " toggle: core's checkbox, fixed size")
        eq(on.visible ~= tg.visible, true, p .. " one of lock and checkbox shown, the other hidden")
        local gear = U.byId[p .. ".cfg"]
        ok(gear.kind == "button" and gear.icon.icon == "gear" and gear.iconSize == Screen.ICON and gear.label == nil and type(gear.onClick) == "function", p .. " gear: icon-only, the toggle box's size")
        eq(gear.tooltip, "CONFIGURE", p .. " gear tooltip")
        eq(gear.dimmed, not r.settings, p .. " gear dimmed without settings")
    end
    eq(U.byId["r1.sc"].tooltip, "JUST YOU - WORKS ON ITS OWN, WHETHER YOU HOST OR JOIN", "story 12: client's tooltip (the locked Nucleus row)")
    eq(U.byId["r2.sc"].tooltip, "JUST YOU - WORKS ON ITS OWN, WHETHER YOU HOST OR JOIN", "story 12: the locked Mod Manager row: client")
    eq(U.byId["r3.sc"].tooltip, "HOST ONLY - ONLY THE HOST NEEDS IT; PLAYERS WHO JOIN DON'T", "story 12: host's tooltip")
    eq(U.byId["r4.sc"].tooltip, "UNKNOWN - THIS MOD DOESN'T SAY WHERE IT RUNS", "story 12: no scope in the data: unknown")
    eq(U.byId["r5.sc"].tooltip, "UNKNOWN - THIS MOD DOESN'T SAY WHERE IT RUNS", "story 12: a pak row: unknown")
    local function lock(n) return U.byId["r" .. n .. ".on"].visible end
    local function tg(n) return U.byId["r" .. n .. ".tg"] end
    ok(lock(1) and lock(2) and not lock(3) and not lock(4) and not lock(5), "the lock on Nucleus and the Mod Manager only (Nucleus's pak too)")
    ok(tg(3).checked == false and tg(3).enabled and tg(4).checked == true and tg(4).enabled, "live checkboxes: off, on")
    ok(tg(5).checked == true and tg(5).enabled == false and tg(5).visible, "a pak row: its state in a disabled checkbox")
    ok(U.byId["r1.on"].tooltip == "ALWAYS ON" and tg(3).tooltip == "OFF" and tg(4).tooltip == "ON", "toggle tooltips")
    eq(tg(5).tooltip, "BLUEPRINT MODS CAN'T BE SWITCHED FROM THE GAME YET", "a pak row's tooltip")
    ok(U.byId["r1.ver"].text == "0.8.0" and U.byId["r4.ver"].text == "-" and U.byId["r5.ver"].text == "UNMANAGED", "versions: as read, - unknown, UNMANAGED for a pak")
    ok(U.byId["r6"] == nil, "no row beyond the data")
    -- the bottom-right stack, hidden while nothing is pending
    ok(U.byId.quit.kind == "button" and U.byId.quit.label == "QUIT GAME" and not U.byId.quit.visible, "QUIT GAME made, hidden")
    ok(U.byId.restart.kind == "button" and U.byId.restart.label == "RESTART NOW" and not U.byId.restart.visible, "story 8: RESTART NOW made, hidden")
    ok(U.byId.banner.text == "CHANGES APPLY AFTER A RESTART." and not U.byId.banner.visible and not U.byId.msg.visible, "banner and message hidden")

    -- Second open: same elements, nothing created again, the window opened again.
    local before = #U.calls
    local made = 0
    for _ in pairs(U.byId) do made = made + 1 end
    U.open.main = nil
    local w2 = v:openMain(ROWS, "en", SIZE)
    eq(w2, w, "the same window handle")
    local creates = 0
    for _, c in ipairs(U.since(before)) do if c.name:match("%.create$") then creates = creates + 1 end end
    eq(creates, 0, "a second open with the same data creates nothing")
    local n2 = 0
    for _ in pairs(U.byId) do n2 = n2 + 1 end
    eq(n2, made, "no new element")
    eq(#U.since(before, "screen.open"), 1, "it opens the window")
    eq(#U.since(before, "text.set") - 4, 0, "the same data: only the four localized labels set (core makes those no-ops)")
    eq(#U.since(before, "checkbox.set") + #U.since(before, "image.set") + #U.since(before, "image.setTooltip"), 0, "the same data: no toggle or status call")

    -- Fewer mods: rows past the count are hidden, not removed; more again: shown with new data.
    before = #U.calls
    v:openMain({ ROWS[1], ROWS[3] }, "en", SIZE)
    ok(U.byId.r1.visible and U.byId.r2.visible and not U.byId.r3.visible and not U.byId.r4.visible and not U.byId.r5.visible, "two mods: rows 3-5 hidden")
    eq(U.byId["r2.name"].text, "ModManagerFixture", "row 2 now shows the fixture")
    ok(U.byId["r2.tg"].checked == false and U.byId["r2.tg"].tooltip == "OFF" and not U.byId["r2.on"].visible and U.byId["r2.tg"].visible, "row 2's toggle follows (lock hidden, checkbox shown)")
    eq(U.byId["r2.cfg"].dimmed, false, "row 2's gear lit (its button re-created with the same id)")
    eq(U.byId["r2.cfg"].updates, 1, "the gear updated once")
    v:openMain(ROWS, "en", SIZE)
    ok(U.byId.r5.visible and U.byId["r5.ver"].text == "UNMANAGED", "five mods again: row 5 shown")
    eq(U.count("row.setVisible"), 6, "setVisible only on a change (3 hidden, 3 shown)")
end

do -- Story 6: status icons, tooltips, refresh in place, pending, the message line.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    local rows = {
        row{ folder = "A", name = "A", state = "on", st = { kinds = { "build", "dep", "restart" }, tips = { build = "B1", dep = "D1\nD2", restart = "R1" } } },
        row{ folder = "B", name = "B", state = "on", st = { kinds = { "dep" }, tips = { dep = "D" } } },
        row{ folder = "C", name = "C", state = "off", st = { kinds = { "restart" }, tips = { restart = "TURNS OFF AFTER A RESTART" } } },
        row{ name = "P", pakOnly = true, state = "off", paks = { "P_P.pak.disabled" }, st = { kinds = {}, tips = {} } },
    }
    v:openMain(rows, "en", SIZE)
    local function icons(n)
        local t = {}
        for k = 1, 3 do local el = U.byId["r" .. n .. ".s" .. k] t[k] = (el.image and el.image.icon or "-") .. ":" .. tostring(el.tooltip) end
        return table.concat(t, " ")
    end
    eq(icons(1), "warning:B1 warning:D1\nD2 restart:R1", "build, dependency, restart, left to right")
    eq(icons(2), "warning:D -:nil -:nil", "a dependency icon first, the rest empty")
    eq(icons(3), "restart:TURNS OFF AFTER A RESTART -:nil -:nil", "restart only")
    eq(icons(4), "-:nil -:nil -:nil", "a pak-only row: none")
    ok(U.byId["r4.tg"].enabled == false and U.byId["r4.tg"].checked == false, "pak row off: a disabled empty box")
    -- refresh in place: icons change, cleared ones lose image and tooltip, no screen.open
    local opens = U.count("screen.open")
    rows[1].st = { kinds = { "restart" }, tips = { restart = "R2" } }
    rows[3].state = "on"; rows[3].st = { kinds = {}, tips = {} }
    v:refresh(rows)
    eq(U.count("screen.open"), opens, "refresh opens nothing")
    eq(icons(1), "restart:R2 -:nil -:nil", "row 1 after refresh: restart only")
    eq(icons(3), "-:nil -:nil -:nil", "row 3 after refresh: none")
    ok(U.byId["r3.tg"].checked == true and U.byId["r3.tg"].tooltip == "ON", "row 3's box follows the files")
    -- pending: QUIT GAME and the banner; the message line
    v:setPending(2)
    ok(U.byId.quit.visible and U.byId.banner.visible, "pending: QUIT GAME and the banner shown")
    -- story 8: RESTART NOW only while pending and restartable
    ok(not U.byId.restart.visible, "pending, not restartable (the default): RESTART NOW hidden")
    v:setRestartable(true)
    ok(U.byId.restart.visible and U.byId.quit.visible, "pending and restartable: RESTART NOW beside QUIT GAME")
    v:setPending(0)
    ok(not U.byId.restart.visible and not U.byId.quit.visible, "restartable, nothing pending: both hidden")
    v:setPending(2)
    ok(U.byId.restart.visible, "pending again: RESTART NOW back")
    v:setRestartable(false)
    ok(not U.byId.restart.visible and U.byId.quit.visible, "not restartable: RESTART NOW hidden, QUIT GAME stays")
    v:setRestartable(true)
    v:setMessage("COULD NOT SAVE THE CHANGE")
    ok(U.byId.msg.visible and U.byId.msg.text == "COULD NOT SAVE THE CHANGE", "the message line")
    v:setPending(0); v:setMessage(nil)
    ok(not U.byId.quit.visible and not U.byId.restart.visible and not U.byId.banner.visible and not U.byId.msg.visible, "nothing pending: all hidden")
    local qc = 0
    v.onQuit = function() qc = qc + 1 end
    U.byId.quit.onClick()
    eq(qc, 1, "QUIT GAME calls onQuit")
    local rc = 0
    v.onRestart = function() rc = rc + 1 end
    U.byId.restart.onClick()
    eq(rc, 1, "RESTART NOW calls onRestart")
    eq(qc, 1, "RESTART NOW doesn't call onQuit itself")
    -- a checkbox click reaches onToggle with the new state; setToggle sets it back without a callback
    local got
    v.onToggle = function(n, c) got = n .. ":" .. tostring(c) end
    U.toggle("r2.tg")
    eq(got, "2:false", "a click on row 2's box: onToggle(2, false)")
    got = nil
    v:setToggle(2, true)
    ok(got == nil and U.byId["r2.tg"].checked == true, "setToggle: back on, no callback")
    eq(U.toggle("r4.tg"), false, "a pak row's disabled box takes no click")
end

do -- Story 6: the confirm and alert windows.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    v:openMain(ROWS, "en", SIZE)
    local cw = v:openConfirm("TURN OFF X? Y NEED IT.")
    eq(cw.id, "confirm", "the confirm window's id")
    ok(U.byId["confirm.text"].text == "TURN OFF X? Y NEED IT." and U.byId["confirm.ok"].label == "TURN OFF", "its text and TURN OFF")
    ok(U.byId["confirm.text"].place.screen == cw and U.byId["confirm.ok"].place.screen == cw, "both on the confirm window")
    local n = 0
    v.onConfirm = function() n = n + 1 end
    U.byId["confirm.ok"].onClick()
    eq(n, 1, "TURN OFF calls onConfirm")
    v:closeConfirm()
    ok(not U.open.confirm, "closeConfirm closes it")
    local creates = U.count("text.create")
    v:openConfirm(string.rep("x", 300))
    eq(U.count("text.create"), creates, "a second confirm creates nothing")
    eq(#U.byId["confirm.text"].text, 256, "a long text is cut at 256 (core never warns)")
    local aw = v:openAlert("NUCLEUS 1 WAS MADE FOR GAME V1. THIS GAME IS V2. MODS MAY NOT WORK UNTIL NUCLEUS IS UPDATED.")
    ok(aw.id == "alert" and U.byId["alert.text"].text:find("^NUCLEUS 1 WAS MADE") ~= nil, "the alert window and its text")
end

do -- The Configure window: heading and three lines; created once; Close is core's.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    v:openMain(ROWS, "en", SIZE)
    local w = v:openConfigure(3, {})
    eq(w.id, "configure", "the Configure window's id")
    ok(U.byId["cfg.title"].text == "ModManagerFixture" and U.byId["cfg.title"].place.screen == w, "heading: the shown name")
    eq(U.byId["cfg.ver"].text, "VERSION 9.9.9", "VERSION line")
    eq(U.byId["cfg.need"].text, "NUCLEUS >=0.1.0", "NUCLEUS line")
    eq(U.byId["cfg.build"].text, "GAME BUILD V0.0.0 1", "GAME BUILD line")
    eq(U.byId["cfg.scope"].text, "RUNS ON: HOST ONLY - ONLY THE HOST NEEDS IT; PLAYERS WHO JOIN DON'T", "story 12: RUNS ON line")
    ok(U.byId["cfg.none"].visible and U.byId["cfg.none"].text == "NO SETTINGS" and not U.byId["cfg.list"].visible, "no settings: NO SETTINGS, the list hidden")
    local creates = U.count("text.create")
    v:openConfigure(1, {})
    eq(U.count("text.create"), creates, "a second Configure creates nothing")
    ok(U.byId["cfg.title"].text == "Nucleus" and U.byId["cfg.need"].text == "NUCLEUS -" and U.byId["cfg.build"].text == "GAME BUILD V8.2.3 26601774", "Nucleus: NUCLEUS -")
    eq(U.byId["cfg.scope"].text, "RUNS ON: JUST YOU - WORKS ON ITS OWN, WHETHER YOU HOST OR JOIN", "story 12: Nucleus's RUNS ON line (client)")
    v:openConfigure(5, {})
    ok(U.byId["cfg.ver"].text == "VERSION UNMANAGED" and U.byId["cfg.need"].text == "NUCLEUS -" and U.byId["cfg.build"].text == "GAME BUILD -", "a pak-only mod: UNMANAGED, -, -")
    eq(U.byId["cfg.scope"].text, "RUNS ON: UNKNOWN - THIS MOD DOESN'T SAY WHERE IT RUNS", "story 12: a pak-only mod's RUNS ON line")
    eq(v:openConfigure(99, {}), nil, "no such row: nothing opens")
    local opened = 0
    v.onGearClick = function(k) opened = k end
    U.byId["r1.cfg"].onClick()
    eq(opened, 1, "the dimmed gear's onClick reaches Configure's opener")
    v.onGearClick = nil
    U.byId["r3.cfg"].onClick()
    eq(U.byId["cfg.title"].text, "ModManagerFixture", "without a hook the gear opens Configure itself")
    -- clickable buttons: the gears, QUIT GAME and RESTART NOW (the toggles are checkboxes)
    for id, el in pairs(U.byId) do
        if el.onClick then ok(id:match("^r%d+%.cfg$") ~= nil or id == "quit" or id == "restart", "only gears, QUIT GAME and RESTART NOW are buttons: " .. id) end
    end
end

do -- Story 6: Configure's problem lines and settings controls.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    local fx = row{ folder = "ModManagerFixture", name = "ModManagerFixture", version = "9.9.9", settings = true,
        st = { kinds = { "build", "dep" }, lines = { "MADE FOR GAME V0.0.0 (BUILD 1). THIS GAME: V8.2.3 (BUILD -).", "NEEDS a.b (NOT INSTALLED)", "NEEDS Mod Manager Base >=2.0.0 (INSTALLED: 1.0.0)" } } }
    v:openMain({ fx }, "en", SIZE)
    local SET = {
        { key = "flag", type = "bool", value = false, default = false, label = "Flag", help = "A test\nswitch.", changeable = "anytime" },
        { key = "example", type = "int", value = 1, default = 1, min = 1, max = 9, label = "Example", changeable = "anytime" },
        { key = "ratio", type = "number", value = 0.5, default = 0.5, min = 0, max = 1, step = 0.1, label = "Ratio", changeable = "anytime" },
        { key = "mode", type = "enum", value = "two", default = "one", values = { "one", "two", "three" }, label = "Mode", changeable = "anytime" },
        { key = "later", type = "bool", value = false, default = false, label = "Restart flag", changeable = "restart", restart = true, pendingRestart = false },
        { key = "preset", type = "number", label = "Preset value", source = "presets", readOnly = true, changeable = "anytime" },
        { key = "free", type = "int", value = 5, default = 5, label = "", changeable = "anytime" },
        { key = "lob", type = "bool", value = true, default = true, label = "Lobby\1thing", changeable = "lobby" },
        { key = "many", type = "int", value = 0, default = 0, min = 0, max = 20001, label = "Many", changeable = "anytime" },
    }
    local w = v:openConfigure(1, SET)
    for k = 1, 3 do ok(U.byId["cfg.p" .. k].visible and U.byId["cfg.p" .. k].text == fx.st.lines[k], "problem line " .. k) end
    ok(not U.byId["cfg.p4"].visible, "unused problem lines hidden")
    eq(U.byId["cfg.list"].size.h, 1080 - Screen.CFG_RESERVE - 3 * Screen.PROBLEM_H, "the settings list leaves room for the problem lines")
    eq(U.byId["cfg.list"].size.w, 1920 - Screen.SIDE_RESERVE, "the settings list as wide as the main list")
    ok(U.byId["cfg.list"].visible and not U.byId["cfg.none"].visible, "settings: the list, no NO SETTINGS")
    eq(U.byId["cfg.list"].place.screen, w, "the list on the Configure window")
    local function shown(i)
        local out = {}
        for _, k in ipairs({ "cb", "ch", "sl", "ro" }) do if U.byId["s" .. i .. "." .. k].visible then out[#out + 1] = k end end
        return table.concat(out, ",")
    end
    eq(shown(1), "cb", "bool: a checkbox"); eq(U.byId["s1.cb"].checked, false, "bool: its value")
    eq(U.byId["s1.lbl"].text, "Flag", "label"); eq(U.byId["s1.lbl"].tooltip, "A test switch.", "help as the label's tooltip (control characters as spaces)")
    eq(U.byId["s1.lbl"].place.fill, 3, "label fill 3"); eq(U.byId["s1.cb"].place.fill, 2, "control fill 2")
    eq(shown(2), "sl", "int 1-9: a slider")
    ok(U.byId["s2.sl"].min == 1 and U.byId["s2.sl"].max == 9 and U.byId["s2.sl"].step == 1 and U.byId["s2.sl"].value == 1 and U.byId["s2.sl"].defaultValue == 1, "int slider: range, step 1, value, default")
    eq(shown(3), "sl", "number 0-1 step 0.1: a slider"); eq(U.byId["s3.sl"].step, 0.1, "its declared step")
    eq(shown(4), "ch", "enum: a choice")
    ok(table.concat(U.byId["s4.ch"].options, ",") == "one,two,three" and U.byId["s4.ch"].index == 2, "choice: the values, the current one selected")
    local rs5 = U.byId["s5.rs"]
    ok(rs5.image and rs5.image.icon == "restart" and rs5.tooltip == "APPLIES AFTER A RESTART" and rs5.dimmed == true, "restart setting: the restart mark (dimmed until pending)")
    ok(U.byId["s1.rs"].image == nil and U.byId["s1.rs"].tooltip == nil, "other settings: an empty spacer")
    eq(shown(6), "ro", "source: a text"); eq(U.byId["s6.ro"].text, "SET BY PRESETS", "SET BY PRESETS")
    eq(shown(7), "ro", "int without bounds: a text"); eq(U.byId["s7.ro"].text, "5", "its value")
    eq(U.byId["s7.lbl"].text, "free", "an empty label shows the key")
    eq(shown(8), "cb", "lobby bool: a checkbox")
    ok(U.byId["s8.cb"].enabled == false and U.byId["s8.cb"].tooltip == "CAN ONLY BE CHANGED IN A LOBBY", "lobby: disabled, its tooltip")
    eq(U.byId["s8.lbl"].text, "Lobby thing", "a control character in a label is a space")
    eq(shown(9), "ro", "over 10,000 steps: a text")
    -- callbacks: index and value; Default on a slider is the declared default
    local got = {}
    v.onSetting = function(i, val) got[#got + 1] = i .. "=" .. tostring(val) end
    U.toggle("s1.cb"); U.pick("s4.ch", 3); U.slide("s2.sl", 7); U.slide("s3.sl", nil)
    U.slide("s2.sl", 7.0)
    eq(table.concat(got, " "), "1=true 4=three 2=7 3=0.5", "onSetting: bool, enum (the value, not the shown text), int, Default -> the declared default")
    ok(math.type(tonumber(got[3]:match("=(.*)"))) == "integer", "an int slider's value is an integer")
    eq(U.toggle("s8.cb"), false, "a lobby setting takes no click")
    -- setControl puts a control back without a callback
    got = {}
    v:setControl(1, false); v:setControl(4, "two"); v:setControl(2, 1)
    ok(#got == 0 and U.byId["s1.cb"].checked == false and U.byId["s4.ch"].index == 2 and U.byId["s2.sl"].value == 1, "setControl: back, no callback")
    -- the message line; new values with a pending restart: the mark undimmed
    v:setCfgMessage("NOT SAVED (write-failed)")
    ok(U.byId["cfg.msg"].visible and U.byId["cfg.msg"].text == "NOT SAVED (write-failed)", "Configure's message line")
    SET[5].pendingRestart = true; SET[5].saved = true
    v:fillSettings(SET)
    ok(not U.byId["s5.rs"].dimmed, "a pending restart setting: its mark undimmed")
    v:setConfigureProblems({ "A SETTING APPLIES AFTER A RESTART" })
    ok(U.byId["cfg.p1"].text == "A SETTING APPLIES AFTER A RESTART" and not U.byId["cfg.p2"].visible, "problem lines refreshed")
    eq(U.byId["cfg.list"].size.h, 1080 - Screen.CFG_RESERVE - Screen.PROBLEM_H, "the list grows back")
    -- another mod with fewer settings: rows past the count hidden; a mod with none: NO SETTINGS
    v:openConfigure(1, { SET[2] })
    ok(U.byId.s1.visible and not U.byId.s2.visible and not U.byId.s9.visible, "one setting: rows 2-9 hidden")
    ok(shown(1) == "sl" and not U.byId["cfg.msg"].visible, "row 1 now a slider; the message cleared on open")
    v:openConfigure(1, {})
    ok(U.byId["cfg.none"].visible and not U.byId["cfg.list"].visible, "none: NO SETTINGS")
    -- at most 64 settings, 8 problem lines
    local many, lines = {}, {}
    for i = 1, 70 do many[i] = { key = "k" .. i, type = "bool", value = false, label = "K" .. i, changeable = "anytime" } end
    for i = 1, 12 do lines[i] = "L" .. i end
    fx.st.lines = lines
    v:openConfigure(1, many)
    ok(U.byId.s64 ~= nil and U.byId.s65 == nil, "at most 64 setting rows")
    ok(U.byId["cfg.p8"].visible and U.byId["cfg.p9"] == nil, "at most 8 problem lines")
    ok(U.byId["cfg.list"].size.h >= Screen.CFG_LIST_MIN, "the list never below its minimum")
end

do -- 200 rows: made once, ids within core's rule.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    local many = {}
    for i = 1, 200 do many[i] = row{ folder = "Mod" .. i, name = "Mod" .. i } end
    v:openMain(many, "en", SIZE)
    eq(v.made, 200, "200 rows made")
    ok(U.byId["r200.cfg"] ~= nil and #"r200.name" <= 64, "the last row's ids")
    v:openMain({ many[1] }, "en", SIZE)
    eq(v.made, 200, "rows stay made")
    ok(U.byId.r1.visible and not U.byId.r2.visible and not U.byId.r200.visible, "one mod: 199 rows hidden")
end

do -- Language: German strings when a de table exists; the layout size changes the lists' width.
    local U = FakeUi.new()
    local T = { en = S.TABLES.en, de = { title = "MOD-VERWALTUNG", name = "NAME-DE", configure = "KONFIGURIEREN", on = "AN" } }
    local Sx = { get = function(k, l) return S.get(k, l, T) end }
    local v = Screen.new(U, Sx)
    v:openMain(ROWS, "de", SIZE)
    ok(U.byId.title.text == "MOD-VERWALTUNG" and U.byId["hdr.name"].text == "NAME-DE" and U.byId["hdr.ver"].text == "VERSION", "de: German where it has a string, else English")
    ok(U.byId["r1.cfg"].tooltip == "KONFIGURIEREN" and U.byId["r4.tg"].tooltip == "AN", "de: tooltips in German")
    v:openMain(ROWS, "en", SIZE)
    ok(U.byId.title.text == "MOD MANAGER" and U.byId["r1.cfg"].tooltip == "CONFIGURE" and U.byId["r4.tg"].tooltip == "ON", "back to English on the next open")
    v:openMain(ROWS, "en", { w = 2580, h = 1080 })
    eq(U.byId.list.size.w, 2580 - Screen.SIDE_RESERVE, "a wider screen: a wider list")
    eq(U.byId["hdr.list"].size.w, U.byId.list.size.w, "the header follows")
end

-- The ids of the elements placed in a window's corner, in the order of their first create.
local function cornerOrder(U, win, corner)
    local out, seen = {}, {}
    for _, c in ipairs(U.calls) do
        local o = c.args[1]
        if c.name:match("%.create$") and type(o) == "table" and type(o.place) == "table" and o.place.screen == win and not seen[o.id]
            and (o.place.corner or "top-left") == (corner or "top-left") then
            seen[o.id] = true
            out[#out + 1] = o.id
        end
    end
    return table.concat(out, ",")
end
local function isCorner(el, gap, nudge)
    local p = el.place
    local off = p.offset
    local offOk = (nudge == nil and off == nil) or (nudge ~= nil and type(off) == "table" and off.x == nudge and off.y == 0)
    return p.corner == "top-left" and p.absolute == nil and p.gap == gap and offOk
end

do -- 0.1.1 layout: the card's top-left corner stack, no fixed offsets; the list height from the Mod Manager's reserve.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    local w = v:openMain(ROWS, "en", SIZE)
    local t, hl, l = U.byId.title, U.byId["hdr.list"], U.byId.list
    ok(t.place.corner == "top-left" and t.place.absolute == nil and t.place.offset == nil, "title: top-left corner of the window")
    ok(isCorner(hl, "normal"), "header list: top-left corner, a normal gap after the title")
    ok(isCorner(l, "tight", Screen.LIST_NUDGE), "list: top-left corner, a tight gap after the header list, nudged right")
    eq(8 + l.place.offset.x, 16, "the list's left edge is the header list's (tight gap + nudge = normal gap)")
    ok(hl.place.screen == w and l.place.screen == w, "both lists on the main window")
    eq(cornerOrder(U, w), "title,hdr.list,list", "the corner stack's creation order: title, header list, list")
    eq(cornerOrder(U, w, "bottom-right"), "quit,restart,banner,msg", "story 6: QUIT GAME, (story 8) RESTART NOW right after it, the banner and the message line in the bottom-right corner")
    eq(hl.size.h, Screen.HEADER_H, "header list height")
    eq(l.size.h, 1080 - Screen.LIST_RESERVE, "list height: the layout height less the reserve")
    ok(l.size.h <= 1080 - Screen.LIST_RESERVE and l.size.h >= 32, "list height: at most 1080 less the reserve, and a valid list size")
    -- The budget's headroom against core 0.12.0's clamp at layout height 1080 (968), with generous estimates of what the
    -- Mod Manager doesn't own (title about 60, gaps 16 + 8 + 16 + 16) and the taller bottom stack (story 6's QUIT GAME,
    -- banner and message line, about 50 + 16 + 40 + 16 + 40 with its inset 16; story 8's RESTART NOW, 16 + 50 more).
    -- Measured in the VM (story 9's CARDFIT at 1280x720): a button is about 44 high and a text line about 30, so the real
    -- hug is lower still. Pending, the usual state (no message line): at least 40 under; with the message line too:
    -- under the clamp.
    local top = 16 + 60 + 16 + Screen.HEADER_H + 8 + l.size.h + 16
    ok(top + 16 + 50 + 16 + 50 + 16 + 40 <= 968 - 40, "pending, both buttons and the banner: the estimated hug stays at least 40 units under the clamp")
    ok(top + 16 + 50 + 16 + 50 + 16 + 40 + 16 + 40 <= 968, "with the message line as well: the estimated hug stays under the clamp")
    ok(Screen.SIDE_RESERVE > 0 and Screen.LIST_RESERVE > 0, "the reserves are positive")
    local U2 = FakeUi.new()
    Screen.new(U2, S):openMain(ROWS, "en", { w = 1920, h = 1080 })
    ok(U2.byId.list.size.w == l.size.w and U2.byId.list.size.h == l.size.h, "720p and 1080p: the same list size")
    local before = #U.calls
    U.open.main = nil
    v:openMain(ROWS, "en", { w = 2580, h = 1080 })
    local creates = {}
    for _, c in ipairs(U.since(before)) do if c.name:match("%.create$") then creates[#creates + 1] = c.args[1].id end end
    eq(table.concat(creates, ","), "hdr.list,list", "a new size re-creates only the two lists, with the same ids")
    eq(l.size.w, 2580 - Screen.SIDE_RESERVE, "wider layout: a wider list")
    eq(hl.size.w, l.size.w, "wider layout: the header list follows")
    eq(l.size.h, 1080 - Screen.LIST_RESERVE, "wider layout: the same height")
    ok(isCorner(hl, "normal") and isCorner(l, "tight", Screen.LIST_NUDGE), "wider layout: the same corner places")
    eq(cornerOrder(U, w), "title,hdr.list,list", "wider layout: the same stack order")
    before = #U.calls
    v:openMain(ROWS, "en", { w = 2580, h = 1080 })
    eq(#U.since(before, "list.create"), 0, "the same size: no list re-created")
    -- Configure: heading, VERSION, NUCLEUS, GAME BUILD, the problem lines, NO SETTINGS, the list, the message line.
    local cw = v:openConfigure(1, {})
    local probs = {}
    for k = 1, Screen.MAX_PROBLEM_LINES do probs[k] = "cfg.p" .. k end
    eq(cornerOrder(U, cw), "cfg.title,cfg.ver,cfg.need,cfg.build,cfg.scope," .. table.concat(probs, ",") .. ",cfg.none,cfg.list,cfg.msg",
        "Configure's corner stack in order")
    ok(isCorner(U.byId["cfg.title"], "normal") and isCorner(U.byId["cfg.ver"], "normal") and isCorner(U.byId["cfg.need"], "normal") and isCorner(U.byId["cfg.build"], "normal")
        and isCorner(U.byId["cfg.scope"], "normal")
        and isCorner(U.byId["cfg.list"], "normal") and isCorner(U.byId["cfg.msg"], "normal"),
        "Configure's elements: top-left corner, one gap (one left edge), no offset")
    -- the Configure budget at 1080 with three problem lines: heading 60, 4 + 3 lines of 30 with gaps 16 (story 12's RUNS ON
    -- is the fourth detail line), the list, the message 30 + 16, BACK 60 with gaps 16 + 16, the card's inset 16: under the
    -- clamp (968).
    ok(16 + 60 + 7 * 46 + 16 + (1080 - Screen.CFG_RESERVE - 3 * Screen.PROBLEM_H) + 46 + 16 + 16 + 60 <= 968, "Configure's estimated hug under the clamp")
    for _, el in pairs(U.byId) do
        if el.place and el.place.screen then ok(el.place.absolute == nil, "no absolute place: " .. el.id) end
    end
end

do -- Story 12: the scope icon follows the data; anything outside the vocabulary reads as unknown; only changes are set.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    local rows = {
        row{ folder = "A", name = "A", scope = "host-plus" },
        row{ folder = "B", name = "B", scope = "both" },
        row{ folder = "C", name = "C", scope = "all" },
        row{ folder = "D", name = "D", scope = "Host" },
        row{ folder = "E", name = "E", scope = 5 },
    }
    v:openMain(rows, "en", SIZE)
    local function icon(n) local el = U.byId["r" .. n .. ".sc"] return el.image and el.image.icon end
    eq(icon(1), "scope-host-plus", "host-plus: its icon")
    eq(U.byId["r1.sc"].tooltip, "HOST, PLAYERS OPTIONAL - THE HOST NEEDS IT; PLAYERS WHO HAVE IT GET MORE", "host-plus: its words")
    eq(icon(2), "scope-both", "both: its icon")
    eq(U.byId["r2.sc"].tooltip, "HOST AND PLAYERS - THE HOST AND EVERY PLAYER NEED IT", "both: its words")
    ok(icon(3) == "scope-unknown" and icon(4) == "scope-unknown" and icon(5) == "scope-unknown", "all, Host, 5 in the data: unknown")
    for n = 3, 5 do ok(not tostring(U.byId["r" .. n .. ".sc"].tooltip):find("all") and not tostring(U.byId["r" .. n .. ".sc"].tooltip):find("Host"), "r" .. n .. ": the raw value is never shown") end
    v:openConfigure(4, {})
    eq(U.byId["cfg.scope"].text, "RUNS ON: UNKNOWN - THIS MOD DOESN'T SAY WHERE IT RUNS", "Configure: Host reads as unknown")
    v:openConfigure(1, {})
    eq(U.byId["cfg.scope"].text, "RUNS ON: HOST, PLAYERS OPTIONAL - THE HOST NEEDS IT; PLAYERS WHO HAVE IT GET MORE", "Configure: a second open sets the new row's line")
    -- refresh: a changed scope sets the image and the tooltip of that row only
    local before = #U.calls
    rows[1] = row{ folder = "A", name = "A", scope = "client" }
    v:refresh(rows)
    eq(icon(1), "scope-client", "refresh: the new icon")
    eq(U.byId["r1.sc"].tooltip, "JUST YOU - WORKS ON ITS OWN, WHETHER YOU HOST OR JOIN", "refresh: the new words")
    local sets = 0
    for _, c in ipairs(U.since(before)) do if (c.name == "image.set" or c.name == "image.setTooltip") then sets = sets + 1 end end
    eq(sets, 2, "refresh: one image.set and one setTooltip, on the changed row only")
    -- a new row made later (more mods): its icon from the data at once
    rows[6] = row{ folder = "F", name = "F", scope = "host" }
    v:refresh(rows)
    eq(icon(6), "scope-host", "a row made on refresh: its icon from the data")
end

do -- A create inside build raises once: the next open builds again and works.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    U.failOn = "hdr.name"
    local okO = pcall(v.openMain, v, ROWS, "en", SIZE)
    ok(not okO, "build failing partway raises out of openMain")
    U.failOn = nil
    local okO2, err = pcall(v.openMain, v, ROWS, "en", SIZE)
    ok(okO2, "the next open works", err)
    ok(U.byId["hdr.name"] ~= nil and U.byId.list ~= nil and U.byId["r5.cfg"] ~= nil and U.byId["r1.name"].text == "Nucleus", "the next open built the header, list and rows")
    local creates = U.count("text.create")
    v:openMain(ROWS, "en", SIZE)
    eq(U.count("text.create"), creates, "and the open after it creates nothing")
end

do -- A failing core call raises out of openMain (main.lua's guard catches it).
    local U = FakeUi.new()
    U.noMenu = true
    local v = Screen.new(U, S)
    local okO, err = pcall(v.openMain, v, ROWS, "en", SIZE)
    ok(not okO and tostring(err):find("menu is not open", 1, true), "screen.open refused: an error for the caller")
end

do -- v2 story 4: BROWSE at the main window's top right, only when onBrowse is set; its click calls onBrowse.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    v:openMain(ROWS, "en", SIZE)
    eq(U.byId.browse, nil, "no onBrowse: no BROWSE")
    local U2 = FakeUi.new()
    local v2 = Screen.new(U2, S)
    local clicks = 0
    v2.onBrowse = function() clicks = clicks + 1 end
    local w = v2:openMain(ROWS, "en", SIZE)
    local b = U2.byId.browse
    ok(b and b.kind == "button" and b.label == "BROWSE" and b.place.screen == w and b.place.corner == "top-right", "BROWSE: a button at the top right")
    U2.click("browse")
    eq(clicks, 1, "BROWSE calls onBrowse")
    v2:openMain(ROWS, "en", SIZE)
    eq(U2.byId.browse.updates, 0, "BROWSE: made once, the label unchanged")
end

do -- toggleKind and controlOf (pure).
    eq(Screen.toggleKind({ state = "locked", paks = { "x" } }), "lock", "locked: the lock")
    eq(Screen.toggleKind({ state = "on", pakOnly = true, paks = { "x" } }), "fixed", "pak-only: fixed")
    eq(Screen.toggleKind({ state = "on", folder = "F", paks = { "F_P.pak" } }), "fixed", "folder with a joined pak: fixed")
    eq(Screen.toggleKind({ state = "off", folder = "F", paks = {} }), "box", "folder: a box")
    eq((Screen.controlOf({ type = "int", min = 0, max = 10000 })), "sl", "10,000 steps: a slider")
    eq((Screen.controlOf({ type = "int", min = 0, max = 10001 })), "ro", "10,001 steps: a text")
    eq(select(2, Screen.controlOf({ type = "number", min = 0, max = 2 })), 0.02, "number without step: (max-min)/100")
    eq((Screen.controlOf({ type = "number", min = 1, max = 1 })), "ro", "min = max: a text")
    eq((Screen.controlOf({ type = "enum", values = {} })), "ro", "enum without values: a text")
    eq((Screen.controlOf({ type = "bool", readOnly = true })), "ro", "readOnly: a text")
    eq(Screen.clean("a\tb" .. string.rep("x", 100), 10), "a bx" .. string.rep("x", 6), "clean: controls as spaces, cut")
    eq(Screen.cut("ab\226\130\172", 4), "ab", "cut on a UTF-8 boundary")
end

io.stdout:write(("screen_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
