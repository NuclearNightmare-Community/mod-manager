-- Unit tests for Scripts/browse.lua against a fake core.ui (test/unit/fakeui.lua): the Browse window's elements (the
-- filter rows: a textbox and four choices, one control per row; the age and status lines; the header; two list rows per
-- package; REFRESH and the count line), lazy rows hidden past the count and never removed, the 120 cap and its count
-- line, filters reset on every open, the status texts per state, and the Details window (wrapped description, the fact
-- lines, the NEEDS lines, nothing clickable).
-- Run from the repo root:  texlua test/unit/browse_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
package.path = ROOT .. "/Scripts/?.lua;" .. ROOT .. "/test/unit/?.lua;" .. package.path
dofile(ROOT .. "/test/unit/nucleus_pkg.lua")(ROOT)
local Browse = require("browse")
local Catalog = require("catalog")
local S = require("strings")
local FakeUi = require("fakeui")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. tostring(got) .. ", want " .. tostring(want)) end

local SIZE = { w = 1920, h = 1080 }
local B = "26601774"
local function pkg(i, o)
    o = o or {}
    return { id = o.id or string.format("x.m%03d", i), name = o.name or ("Mod " .. string.format("%03d", i)), kind = "mod",
        displayName = o.displayName, description = o.description or "A mod.", categories = o.categories or { "ui" },
        publisher = "Pub", license = "MIT",
        versions = o.versions or { { version = "0.1.0", game = { version = "V8.2.3", build = B }, scope = o.scope or "client",
            dependsOn = o.deps or {}, sha256 = string.rep("a", 64) } } }
end
local function data(rows, o)
    o = o or {}
    return { rows = rows, total = #rows, state = o.state or "ok", outcome = o.outcome, buildKnown = o.buildKnown ~= false,
        indexIssued = "2026-11-21T00:59:08Z", revokedIssued = o.revokedIssued, now = Catalog.epoch("2026-11-21T00:59:08Z") + 7200 }
end
local function visibleRows(U)
    local n = 0
    for k = 1, 400 do
        local r = U.byId["bw.r" .. k]
        if not r then break end
        if r.visible then n = n + 1 end
    end
    return n
end

do -- The window and its elements.
    local U = FakeUi.new()
    local b = Browse.new(U, S)
    local filtered = {}
    b.onFiltered = function(f, shown, matched) filtered[#filtered + 1] = { f = f, n = #shown, matched = matched } end
    local rows = Catalog.model({ packages = { pkg(1, { displayName = "Zeta", description = "Last one." }), pkg(2, { displayName = "alpha", scope = "host", categories = { "audio", "qol" } }) } }, nil, {}, "1.0.0", B)
    local w = b:open(data(rows), "en", SIZE)
    eq(w.id, "browse", "the window's id")
    eq(U.byId["bw.title"].text, "BROWSE MODS", "the title")
    eq(U.byId["bw.title"].style.font, "title", "the title's font")
    -- five filter rows, one control each (keys and the gamepad reach every control)
    local kinds = { "textbox", "choice", "choice", "choice", "choice" }
    local ids = { "bw.q", "bw.cat", "bw.show", "bw.scope", "bw.for" }
    for k = 1, 5 do
        local r = U.byId["bw.f" .. k]
        ok(r and r.kind == "row" and r.place.list == U.byId["bw.flist"].handle, "filter row " .. k .. " in the filter list")
        local c = U.byId[ids[k]]
        ok(c.kind == kinds[k] and c.place.row == r.handle, "filter row " .. k .. ": " .. ids[k])
        ok(U.byId["bw.f" .. k .. ".l"].kind == "text", "filter row " .. k .. ": its label")
    end
    eq(U.byId["bw.f1.l"].text, "SEARCH", "SEARCH label")
    eq(#U.byId["bw.cat"].options, 15, "CATEGORY: ALL and the 14 categories")
    eq(U.byId["bw.cat"].options[1], "ALL", "CATEGORY: ALL first")
    eq(U.byId["bw.cat"].options[5], "AUDIO", "CATEGORY: the categories.md order")
    eq(U.byId["bw.cat"].options[15], "MAPS", "CATEGORY: MAPS last")
    eq(table.concat(U.byId["bw.show"].options, "|"), "ALL|INSTALLED|NOT INSTALLED|UPDATE AVAILABLE", "SHOW options")
    eq(table.concat(U.byId["bw.scope"].options, "|"), "ALL|JUST YOU|HOST ONLY|HOST, PLAYERS OPTIONAL|HOST AND PLAYERS", "SCOPE options")
    eq(table.concat(U.byId["bw.for"].options, "|"), "THIS GAME|READY TO RUN|ALL BUILDS", "FOR options")
    eq(U.byId["bw.q"].maxChars, 64, "search: at most 64 characters")
    ok(U.byId["bw.q"].width >= 64 and U.byId["bw.q"].width <= 1024, "search: a width core takes")
    -- header and rows
    eq(U.byId["bw.h.name"].text, "NAME", "header NAME")
    eq(U.byId["bw.h.st"].text, "STATE", "header STATE")
    eq(visibleRows(U), 2, "two packages")
    eq(U.byId["bw.r1.name"].text, "alpha", "sorted by name without case")
    eq(U.byId["bw.r1.cat"].text, "AUDIO", "the primary category's label")
    eq(U.byId["bw.r1.ver"].text, "0.1.0", "the offered version")
    eq(U.byId["bw.r1.sc"].image.icon, "scope-host", "the scope icon")
    eq(U.byId["bw.r1.sc"].tooltip, "HOST ONLY - ONLY THE HOST NEEDS IT; PLAYERS WHO JOIN DON'T", "the scope tooltip")
    eq(U.byId["bw.r1.st"].text, "NOT INSTALLED", "the state")
    eq(U.byId["bw.r1.w"].image, nil, "no warning when the Nucleus need is met")
    local det = U.byId["bw.r1.det"]
    ok(det.kind == "button" and det.icon.game and det.tooltip == "DETAILS", "the DETAILS icon button")
    local d1 = U.byId["bw.d1"]
    ok(d1.kind == "row" and d1.place.list == U.byId["bw.list"].handle, "row two: the description row in the same list")
    local dt = U.byId["bw.d1.text"]
    ok(dt.style.font == "small" and dt.style.overflow == "ellipsis" and dt.text == "A mod.", "row two: the description, small, ellipsis")
    eq(U.byId["bw.age"].text, "CATALOG UPDATED 2 HOURS AGO - REVOCATIONS CHECKED -", "the age line")
    ok(not U.byId["bw.status"].visible, "nothing to say: no status line")
    eq(U.byId["bw.count"].text, "2 OF 2 MODS", "the count line")
    ok(U.byId["bw.refresh"].kind == "button" and U.byId["bw.refresh"].place.corner == "bottom-right", "REFRESH bottom-right")
    eq(U.byId["bw.refresh"].label, "REFRESH", "REFRESH label")
    eq(#filtered, 1, "open: one filtered callback")
    -- list order: r1, d1, r2, d2 (two children per package)
    local order = {}
    for _, c in ipairs(U.calls) do if c.name == "row.create" and c.args[1].place.list == U.byId["bw.list"].handle then order[#order + 1] = c.args[1].id end end
    eq(table.concat(order, ","), "bw.r1,bw.d1,bw.r2,bw.d2", "two list rows per package, in order")

    -- a filter change with no defer runs at once; reset on the next open
    U.pick("bw.scope", 3) -- HOST ONLY
    eq(visibleRows(U), 1, "SCOPE host: one row")
    ok(U.byId["bw.r2"].visible == false and U.byId["bw.d2"].visible == false, "rows past the count hidden (both)")
    U.typeText("bw.q", "zeta")
    eq(U.byId["bw.status"].text, "NO MODS MATCH", "no match")
    U.back("browse")
    local before = U.count("row.create")
    b:open(data(rows), "en", SIZE)
    eq(U.byId["bw.scope"].index, 1, "open: SCOPE reset")
    eq(U.byId["bw.q"].text, "", "open: search reset")
    eq(visibleRows(U), 2, "open: both rows again")
    eq(U.count("row.create"), before, "open: rows reused, none made or removed")
    eq(U.count("screen.close"), 0, "nothing closed by the view itself")
end

do -- The status line per state, the copy label, a message.
    local U = FakeUi.new()
    local b = Browse.new(U, S)
    b:open(data({}, { state = "checking" }), "en", SIZE)
    eq(U.byId["bw.status"].text, "CHECKING CATALOG...", "checking")
    ok(not U.byId["bw.age"].visible, "checking: no age line")
    b:update(data({}, { state = "unavailable" }))
    eq(U.byId["bw.status"].text, "CATALOG UNAVAILABLE. CHECK YOUR CONNECTION AND PRESS REFRESH.", "unavailable")
    b:update(data({}, { state = "refused", outcome = "serial-rollback" }))
    eq(U.byId["bw.status"].text, "CATALOG REFUSED (serial-rollback)", "refused")
    b:update(data({}, { state = "refused", outcome = "schema-too-new" }))
    eq(U.byId["bw.status"].text, "CATALOG NEEDS A NEWER MOD MANAGER", "too new")
    b:update(data({}, { state = "error" }))
    eq(U.byId["bw.status"].text, "CATALOG ERROR", "error")
    b:update(data({}, { state = "ok", buildKnown = false }))
    eq(U.byId["bw.status"].text, "GAME BUILD UNKNOWN", "build unknown")
    b:update(data({}, { state = "copy", revokedIssued = "2026-11-01T00:00:00Z" }))
    eq(U.byId["bw.age"].text, "OFFLINE: SAVED CATALOG - CATALOG UPDATED 2 HOURS AGO - REVOCATIONS CHECKED 20 DAYS AGO", "copy: OFFLINE")
    b:setMessage("CATALOG BUSY")
    eq(U.byId["bw.status"].text, "CATALOG BUSY", "a message on the status line")
    b:update(data({}, { state = "ok" }))
    eq(U.byId["bw.status"].text, "NO MODS MATCH", "an update clears the message")
end

do -- 300 packages: the first 120 shown, the count line says so; rows made lazily, never removed.
    local U = FakeUi.new()
    local b = Browse.new(U, S)
    local pk = {}
    for i = 1, 300 do pk[i] = pkg(i) end
    local rows = Catalog.model({ packages = pk }, nil, {}, "1.0.0", B)
    local seen
    b.onFiltered = function(_, shown, matched, all) seen = { #shown, matched, #all } end
    b:open(data(rows), "en", SIZE)
    eq(visibleRows(U), 120, "over cap: 120 rows")
    eq(U.byId["bw.r121"], nil, "over cap: no 121st row made")
    eq(U.byId["bw.count"].text, "300 OF 300 MODS - SHOWING THE FIRST 120", "over cap: the count line")
    ok(seen[1] == 120 and seen[2] == 300 and seen[3] == 300, "over cap: the callback gets every match")
    U.typeText("bw.q", "mod 001")
    eq(visibleRows(U), 1, "a search: one row")
    eq(U.byId["bw.r120"].visible, false, "the other rows hidden, kept")
end

do -- Details: the wrapped description, the facts, the NEEDS lines; nothing clickable.
    local U = FakeUi.new()
    local b = Browse.new(U, S)
    local long = string.rep("lorem ipsum dolor ", 30)
    local deps = {}
    for d = 1, 6 do deps[d] = { id = "x.dep" .. d, version = ">=1.0.0" } end
    local p = pkg(1, { displayName = "Deep", description = long:sub(1, 250), categories = { "tools", "ui" }, deps = deps })
    local p2 = pkg(2, { displayName = "Short", description = "Short one." })
    local rows = Catalog.model({ packages = { p, p2 } }, nil, { { folder = "Mod 002", version = "0.0.9" } }, "1.0.0", B)
    b:open(data(rows), "en", SIZE)
    U.pick("bw.for", 3) -- ALL BUILDS: Deep's needs are not met, so it is other-build
    local buttons = U.count("button.create")
    eq(b:openDetails(1), 4, "Details: 250 characters wrap into 4 lines of at most 72")
    ok(U.open.details, "Details window open")
    eq(U.byId["dt.title"].text, "Deep", "Details: the title")
    eq(U.byId["dt.title"].style.font, "title", "Details: the title font")
    for k = 1, 4 do ok(U.byId["dt.l" .. k].visible and utf8.len(U.byId["dt.l" .. k].text) <= 72, "Details: line " .. k) end
    eq(U.byId["dt.l5"].visible, false, "Details: line 5 hidden")
    eq(U.byId["dt.cats"].text, "CATEGORIES: UTILITIES & TOOLS, USER INTERFACE", "Details: all categories")
    eq(U.byId["dt.ver"].text, "VERSION 0.1.0", "Details: the version")
    eq(U.byId["dt.runs"].text, "RUNS ON: JUST YOU - WORKS ON ITS OWN, WHETHER YOU HOST OR JOIN", "Details: screen.lua's RUNS ON line")
    eq(U.byId["dt.game"].text, "FOR GAME V8.2.3 (26601774)", "Details: FOR GAME")
    eq(U.byId["dt.n1"].text, "NEEDS x.dep1 >=1.0.0: NOT MET", "Details: a need, NOT MET")
    eq(U.byId["dt.n4"].text, "AND 3 MORE", "Details: at most 4 NEEDS lines")
    eq(U.byId["dt.inst"].text, "INSTALLED NO", "Details: INSTALLED NO")
    eq(U.byId["dt.pub"].text, "PUBLISHER Pub", "Details: PUBLISHER")
    eq(U.byId["dt.lic"].text, "LICENSE MIT", "Details: LICENSE")
    eq(U.count("button.create"), buttons, "Details: no button (BACK is core's)")
    -- Deep is other-build (its needs are not met): ALL BUILDS shows it; Short is installed by folder
    U.back("details")
    eq(b:openDetails(2) ~= nil, true, "Details again for another row")
    eq(U.byId["dt.title"].text, "Short", "Details: the same elements, new text")
    eq(U.byId["dt.l2"].visible, false, "Details: fewer lines hide the rest")
    eq(U.byId["dt.n1"].text, "NEEDS NOTHING ELSE", "Details: no dependency")
    ok(U.byId["dt.n2"].visible == false, "Details: other NEEDS lines hidden")
    eq(U.byId["dt.inst"].text, "INSTALLED 0.0.9", "Details: INSTALLED <version>")
    eq(b:openDetails(9), nil, "Details: no row 9")
end

do -- Deferred input: the caller's defer runs fills after the hook; several changes, one fill.
    local U = FakeUi.new()
    local b = Browse.new(U, S)
    local queue, fills = {}, 0
    b.defer = function(_, fn) queue[#queue + 1] = fn end
    b.onFiltered = function() fills = fills + 1 end
    b:open(data(Catalog.model({ packages = { pkg(1) } }, nil, {}, "1.0.0", B)), "en", SIZE)
    eq(fills, 1, "open fills once")
    U.pick("bw.cat", 2); U.pick("bw.show", 2); U.typeText("bw.q", "x")
    eq(#U.hookCalls, 0, "no ui call inside the hooks")
    eq(#queue, 1, "one deferred fill for three changes")
    queue[1]()
    eq(fills, 2, "then one fill")
    eq(b.filters.cat, "gameplay", "the filter recorded: CATEGORY")
    eq(b.filters.show, "installed", "the filter recorded: SHOW")
    eq(b.filters.q, "x", "the filter recorded: search")
    local refreshed = 0
    b.onRefresh = function() refreshed = refreshed + 1 end
    U.click("bw.refresh")
    eq(refreshed, 0, "REFRESH: nothing inside the hook")
    queue[2]()
    eq(refreshed, 1, "REFRESH after the hook")
end

io.stdout:write(("browse_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
