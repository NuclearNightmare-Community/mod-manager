-- Unit tests for Scripts/screen.lua against a fake core.ui (test/unit/fakeui.lua): the windows' elements, ids, icon
-- keys, dimmed, tooltips, overflow, the header's mirror of a row, reuse on a second open, hiding rows past the count,
-- the 200-row list, and the Configure window. Run from the repo root:  texlua test/unit/screen_test.lua
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
        state = t.state or "off", settings = t.settings or false, need = t.need, build = t.build, paks = {} }
    return r
end
local ROWS = {
    row{ folder = "Nucleus", name = "Nucleus", version = "0.8.0", state = "locked", build = "V8.2.3 26601774" },
    row{ folder = "ModManager", name = "Mod Manager", version = "0.1.0", state = "locked", need = ">=0.8.0", build = "V8.2.3 26601774" },
    row{ folder = "ModManagerFixture", name = "ModManagerFixture", version = "9.9.9", state = "off", settings = true, need = ">=0.1.0", build = "V0.0.0 1" },
    row{ folder = "ModManagerDriver", name = "ModManagerDriver", state = "on" },
    row{ name = "ModManagerPak", pakOnly = true, state = "on" },
}

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
    -- header: spacer | NAME (fill 4) | VERSION (fill 1) | empty status (fill 1) | spacer
    local hon, hname, hver, hst, hcfg = U.byId["hdr.on"], U.byId["hdr.name"], U.byId["hdr.ver"], U.byId["hdr.st"], U.byId["hdr.cfg"]
    ok(hon.kind == "image" and hon.image == nil and hon.size == Screen.ICON and hon.place.fill == nil, "header: a spacer of the toggle box's size, no fill")
    ok(hname.text == "NAME" and hname.place.fill == 4 and hver.text == "VERSION" and hver.place.fill == 1 and hst.text == "" and hst.place.fill == 1, "header: NAME 4, VERSION 1, empty 1")
    ok(hcfg.kind == "image" and hcfg.image == nil and hcfg.size == Screen.ICON, "header: a spacer of the gear's size")
    eq(U.byId.hdr.place.list, U.byId["hdr.list"].handle, "the header row is in the header list")
    -- the order of the header's cells is the order of a row's
    local order = {}
    for _, c in ipairs(U.calls) do local o = c.args[1] if type(o) == "table" and o.place and o.place.row == U.byId.hdr.handle then order[#order + 1] = o.id end end
    eq(table.concat(order, ","), "hdr.on,hdr.name,hdr.ver,hdr.st,hdr.cfg", "header cells in a row's order")
    order = {}
    for _, c in ipairs(U.calls) do local o = c.args[1] if type(o) == "table" and o.place and o.place.row == U.byId.r1.handle and c.name:match("create") then order[#order + 1] = o.id end end
    eq(table.concat(order, ","), "r1.on,r1.name,r1.ver,r1.st,r1.cfg", "row cells: toggle box, name, version, status, gear")
    -- rows
    for n, r in ipairs(ROWS) do
        local p = "r" .. n
        ok(U.byId[p] and U.byId[p].place.list == l.handle and U.byId[p].visible, p .. " in the list, shown")
        eq(U.byId[p .. ".name"].text, r.name, p .. " name")
        eq(U.byId[p .. ".name"].style.overflow, "ellipsis", p .. " name cut with an ellipsis")
        eq(U.byId[p .. ".name"].place.fill, 4, p .. " name fill 4")
        eq(U.byId[p .. ".ver"].style.overflow, "ellipsis", p .. " version cut with an ellipsis")
        eq(U.byId[p .. ".ver"].place.fill, 1, p .. " version fill 1")
        ok(U.byId[p .. ".st"].text == "" and U.byId[p .. ".st"].place.fill == 1, p .. " status: empty, fill 1")
        local on = U.byId[p .. ".on"]
        ok(on.kind == "image" and on.size == Screen.ICON and on.place.fill == nil, p .. " toggle box: an image, fixed size, no fill (inert)")
        local gear = U.byId[p .. ".cfg"]
        ok(gear.kind == "button" and gear.icon.icon == "gear" and gear.iconSize == Screen.ICON and gear.label == nil and type(gear.onClick) == "function", p .. " gear: icon-only, the toggle box's size")
        eq(gear.tooltip, "CONFIGURE", p .. " gear tooltip")
        eq(gear.dimmed, not r.settings, p .. " gear dimmed without settings")
    end
    local function icon(n) return U.byId["r" .. n .. ".on"].image.icon end
    ok(icon(1) == "lock" and icon(2) == "lock" and icon(3) == "checkbox-off" and icon(4) == "checkbox-on" and icon(5) == "checkbox-on", "toggle icons: lock, lock, off, on, on")
    ok(U.byId["r1.on"].tooltip == "ALWAYS ON" and U.byId["r3.on"].tooltip == "OFF" and U.byId["r4.on"].tooltip == "ON", "toggle tooltips")
    ok(U.byId["r1.ver"].text == "0.8.0" and U.byId["r4.ver"].text == "-" and U.byId["r5.ver"].text == "UNMANAGED", "versions: as read, - unknown, UNMANAGED for a pak")
    ok(U.count("text.create") >= 1 and U.byId["r6"] == nil, "no row beyond the data")

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
    eq(#U.since(before, "text.set") - 3, 0, "the same data: only the three localized labels set (core makes those no-ops)")

    -- Fewer mods: rows past the count are hidden, not removed; more again: shown with new data.
    before = #U.calls
    v:openMain({ ROWS[1], ROWS[3] }, "en", SIZE)
    ok(U.byId.r1.visible and U.byId.r2.visible and not U.byId.r3.visible and not U.byId.r4.visible and not U.byId.r5.visible, "two mods: rows 3-5 hidden")
    eq(U.byId["r2.name"].text, "ModManagerFixture", "row 2 now shows the fixture")
    ok(U.byId["r2.on"].image.icon == "checkbox-off" and U.byId["r2.on"].tooltip == "OFF", "row 2's toggle follows")
    eq(U.byId["r2.cfg"].dimmed, false, "row 2's gear lit (its button re-created with the same id)")
    eq(U.byId["r2.cfg"].updates, 1, "the gear updated once")
    v:openMain(ROWS, "en", SIZE)
    ok(U.byId.r5.visible and U.byId["r5.ver"].text == "UNMANAGED", "five mods again: row 5 shown")
    eq(U.count("row.setVisible"), 6, "setVisible only on a change (3 hidden, 3 shown)")
end

do -- The Configure window: heading and three lines; created once; Close is core's.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    v:openMain(ROWS, "en", SIZE)
    local w = v:openConfigure(3)
    eq(w.id, "configure", "the Configure window's id")
    ok(U.byId["cfg.title"].text == "ModManagerFixture" and U.byId["cfg.title"].place.screen == w, "heading: the shown name")
    eq(U.byId["cfg.ver"].text, "VERSION 9.9.9", "VERSION line")
    eq(U.byId["cfg.need"].text, "NUCLEUS >=0.1.0", "NUCLEUS line")
    eq(U.byId["cfg.build"].text, "GAME BUILD V0.0.0 1", "GAME BUILD line")
    local creates = U.count("text.create")
    v:openConfigure(1)
    eq(U.count("text.create"), creates, "a second Configure creates nothing")
    ok(U.byId["cfg.title"].text == "Nucleus" and U.byId["cfg.need"].text == "NUCLEUS -" and U.byId["cfg.build"].text == "GAME BUILD V8.2.3 26601774", "Nucleus: NUCLEUS -")
    v:openConfigure(5)
    ok(U.byId["cfg.ver"].text == "VERSION UNMANAGED" and U.byId["cfg.need"].text == "NUCLEUS -" and U.byId["cfg.build"].text == "GAME BUILD -", "a pak-only mod: UNMANAGED, -, -")
    eq(v:openConfigure(99), nil, "no such row: nothing opens")
    -- a dimmed gear opens Configure like a lit one
    local opened = 0
    v.onGearClick = function(n) opened = n end
    U.byId["r1.cfg"].onClick()
    eq(opened, 1, "the dimmed gear's onClick reaches Configure's opener")
    v.onGearClick = nil
    U.byId["r3.cfg"].onClick()
    eq(U.byId["cfg.title"].text, "ModManagerFixture", "without a hook the gear opens Configure itself")
    -- nothing else is clickable: no onClick anywhere but the gears
    for id, el in pairs(U.byId) do
        if el.onClick then ok(id:match("^r%d+%.cfg$") ~= nil, "only gears are clickable: " .. id) end
    end
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
    ok(U.byId["r1.cfg"].tooltip == "KONFIGURIEREN" and U.byId["r4.on"].tooltip == "AN", "de: tooltips in German")
    v:openMain(ROWS, "en", SIZE)
    ok(U.byId.title.text == "MOD MANAGER" and U.byId["r1.cfg"].tooltip == "CONFIGURE" and U.byId["r4.on"].tooltip == "ON", "back to English on the next open")
    v:openMain(ROWS, "en", { w = 2580, h = 1080 })
    eq(U.byId.list.size.w, 2580 - Screen.SIDE_RESERVE, "a wider screen: a wider list")
    eq(U.byId["hdr.list"].size.w, U.byId.list.size.w, "the header follows")
end

-- The ids of the elements placed in a window's corner, in the order of their first create.
local function cornerOrder(U, win)
    local out, seen = {}, {}
    for _, c in ipairs(U.calls) do
        local o = c.args[1]
        if c.name:match("%.create$") and type(o) == "table" and type(o.place) == "table" and o.place.screen == win and not seen[o.id] then
            seen[o.id] = true
            out[#out + 1] = o.id
        end
    end
    return table.concat(out, ",")
end
local function isCorner(el, gap)
    local p = el.place
    return p.corner == "top-left" and p.absolute == nil and p.offset == nil and p.gap == gap
end

do -- 0.1.1 layout: the card's top-left corner stack, no fixed offsets; the list height from the Mod Manager's reserve.
    local U = FakeUi.new()
    local v = Screen.new(U, S)
    local w = v:openMain(ROWS, "en", SIZE)
    local t, hl, l = U.byId.title, U.byId["hdr.list"], U.byId.list
    ok(t.place.corner == "top-left" and t.place.absolute == nil and t.place.offset == nil, "title: top-left corner of the window")
    ok(isCorner(hl, "normal"), "header list: top-left corner, a normal gap after the title")
    ok(isCorner(l, "tight"), "list: top-left corner, a tight gap after the header list")
    ok(hl.place.screen == w and l.place.screen == w, "both lists on the main window")
    eq(cornerOrder(U, w), "title,hdr.list,list", "the corner stack's creation order: title, header list, list")
    eq(hl.size.h, Screen.HEADER_H, "header list height")
    eq(l.size.h, 1080 - Screen.LIST_RESERVE, "list height: the layout height less the reserve")
    ok(l.size.h <= 1080 - Screen.LIST_RESERVE and l.size.h >= 32, "list height: at most 1080 less the reserve, and a valid list size")
    -- The budget's headroom against core 0.12.0's clamp at layout height 1080 (968), with generous estimates of what the
    -- Mod Manager doesn't own (title about 60, BACK about 60 with its inset, gaps 16 + 8 + 16 + 16): at least 60 under.
    ok(16 + 60 + 16 + Screen.HEADER_H + 8 + l.size.h + 16 + 16 + 60 <= 968 - 60, "the estimated hug stays at least 60 units under the clamp")
    ok(Screen.SIDE_RESERVE > 0 and Screen.LIST_RESERVE > 0, "the reserves are positive")
    -- 1280x720 and 1920x1080 share the layout size 1920x1080 (and so does the fallback): the same sizes.
    local U2 = FakeUi.new()
    Screen.new(U2, S):openMain(ROWS, "en", { w = 1920, h = 1080 })
    ok(U2.byId.list.size.w == l.size.w and U2.byId.list.size.h == l.size.h, "720p and 1080p: the same list size")
    -- Reopen with another layout size (3440x1440 -> 2580x1080): both lists re-sized, same ids, same places, same order.
    local before = #U.calls
    U.open.main = nil
    v:openMain(ROWS, "en", { w = 2580, h = 1080 })
    local creates = {}
    for _, c in ipairs(U.since(before)) do if c.name:match("%.create$") then creates[#creates + 1] = c.args[1].id end end
    eq(table.concat(creates, ","), "hdr.list,list", "a new size re-creates only the two lists, with the same ids")
    eq(l.size.w, 2580 - Screen.SIDE_RESERVE, "wider layout: a wider list")
    eq(hl.size.w, l.size.w, "wider layout: the header list follows")
    eq(l.size.h, 1080 - Screen.LIST_RESERVE, "wider layout: the same height")
    ok(isCorner(hl, "normal") and isCorner(l, "tight"), "wider layout: the same corner places")
    eq(cornerOrder(U, w), "title,hdr.list,list", "wider layout: the same stack order")
    -- The same size again: nothing re-created.
    before = #U.calls
    v:openMain(ROWS, "en", { w = 2580, h = 1080 })
    eq(#U.since(before, "list.create"), 0, "the same size: no list re-created")
    -- Configure: heading, then VERSION, NUCLEUS, GAME BUILD in the card's top-left corner stack, no offsets.
    local cw = v:openConfigure(1)
    eq(cornerOrder(U, cw), "cfg.title,cfg.ver,cfg.need,cfg.build", "Configure's corner stack: heading, VERSION, NUCLEUS, GAME BUILD")
    ok(U.byId["cfg.title"].place.corner == "top-left" and U.byId["cfg.title"].place.absolute == nil, "Configure heading: top-left corner")
    ok(isCorner(U.byId["cfg.ver"], "normal") and isCorner(U.byId["cfg.need"], "tight") and isCorner(U.byId["cfg.build"], "tight"), "Configure lines: top-left corner, normal then tight gaps")
    for _, el in pairs(U.byId) do
        if el.place and el.place.screen then ok(el.place.absolute == nil, "no absolute place: " .. el.id) end
    end
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

io.stdout:write(("screen_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
