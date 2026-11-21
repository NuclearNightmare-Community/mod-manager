-- Unit tests for Scripts/catalog.lua (pure): decode with its caps and type checks, this game's build, the offered
-- version (build, revocation, dependsOn satisfiable recursively, other-build), installed states (update, installed,
-- conflict, available), needsCore, the caps (512 packages, 64 versions, 32 dependsOn), search terms, the four filters,
-- the 120 cap, ages and the Details word wrap. Fixtures: test/unit/fixtures/catalog-*.json (our own made-up payloads).
-- Run from the repo root:  texlua test/unit/catalog_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
package.path = ROOT .. "/Scripts/?.lua;" .. ROOT .. "/test/unit/?.lua;" .. package.path
dofile(ROOT .. "/test/unit/nucleus_pkg.lua")(ROOT)
local Catalog = require("catalog")
local J = require("nucleus.json")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. tostring(got) .. ", want " .. tostring(want)) end
local function read(name)
    local f = assert(io.open(ROOT .. "/test/unit/fixtures/" .. name, "rb"))
    local s = f:read("a")
    f:close()
    return s
end
local function ids(rows) local t = {} for i, r in ipairs(rows) do t[i] = r.id end return table.concat(t, ",") end
local function byId(rows, id) for _, r in ipairs(rows) do if r.id == id then return r end end end
local B = "26601774"
local NN = "nuclearnightmare-community."
local INSTALLED = {
    { folder = "Nucleus", id = NN .. "nucleus", version = "0.25.0" },
    { folder = "ModManager", id = NN .. "mod-manager", version = "0.6.0" },
    { folder = "Older", id = "example.older", version = "0.2.0" },
    { folder = "Taken", id = "example.someone-else", version = "1.0.0" },
    { folder = "Bare", version = "0.1.0" }, -- no id: matched by folder = name
}

-- ---------------------------------------------------------------- decode
do
    local d, why = Catalog.decode(read("catalog-ok.json"))
    ok(d ~= nil, "decode: the ok fixture as text", why)
    eq(d.source, "network", "decode: source")
    eq(d.indexIssued, "2026-11-21T00:59:08Z", "decode: index_issued")
    eq(d.revokedIssued, "2026-10-30T23:11:49Z", "decode: revoked_issued")
    ok(type(d.index.packages) == "table" and #d.index.packages == 7, "decode: the index's packages")
    local t = J.decode(read("catalog-copy.json"), { maxBytes = 9437184, maxDepth = 66, maxValues = 2000000, maxString = 4194304 })
    local d2 = Catalog.decode(t)
    ok(d2 and d2.source == "copy", "decode: a table core.catalog.poll decoded (copy)")
    local d3, why3 = Catalog.decode(read("catalog-bad.json"))
    ok(d3 == nil and why3:find("packages", 1, true), "decode: packages of the wrong type -> nil, why", why3)
    ok(Catalog.decode("{not json") == nil, "decode: undecodable text -> nil")
    ok(Catalog.decode(nil) == nil, "decode: nothing -> nil")
    ok(Catalog.decode(J.decode('{"source":"elsewhere","index_issued":"x","index":{"packages":[]}}')) == nil, "decode: unknown source -> nil")
    ok(Catalog.decode(J.decode('{"source":"network","index_issued":5,"index":{"packages":[]}}')) == nil, "decode: index_issued not a string -> nil")
    ok(Catalog.decode(J.decode('{"source":"network","index_issued":"x","index":[]}')) == nil, "decode: index an array -> nil")
    ok(Catalog.decode(J.decode('{"source":"network","index_issued":"x","index":{"packages":[]},"revoked":5}')) == nil, "decode: revoked a number -> nil")
    ok(Catalog.decode(J.decode('{"source":"network","index_issued":"x","revoked_issued":null,"index":{"packages":[]},"revoked":null}')) ~= nil, "decode: null revoked is fine")
    -- caps: a string over 4096 bytes, nesting deeper than 16
    local long = '{"source":"network","index_issued":"x","index":{"packages":[],"x":"' .. string.rep("a", 4097) .. '"}}'
    ok(Catalog.decode(long) == nil, "decode: a string over maxString -> nil")
    local deep = { source = "network", index_issued = "x", index = { packages = {} } }
    local t4 = deep.index
    for _ = 1, 20 do t4.x = {}; t4 = t4.x end
    local d5, why5 = Catalog.decode(deep)
    ok(d5 == nil and why5:find("deeper", 1, true), "decode: a table nested past maxDepth -> nil", why5)
    eq(Catalog.CAPS.maxBytes, 9437184, "caps: maxBytes"); eq(Catalog.CAPS.maxDepth, 16, "caps: maxDepth")
    eq(Catalog.CAPS.maxValues, 262144, "caps: maxValues"); eq(Catalog.CAPS.maxString, 4096, "caps: maxString")
end

-- ---------------------------------------------------------------- this game's build
do
    local ix = { game_builds = { { version = "V8.2.3", build = B }, { version = "V8.2.2", build = "1" } } }
    local b, from = Catalog.thisBuild(ix, { version = "V8.2.3", build = "123" })
    ok(b == "123" and from == "manifest", "build: the appmanifest first")
    b, from = Catalog.thisBuild(ix, { version = "V8.2.3" })
    ok(b == B and from == "index", "build: the footer version's game_builds entry")
    b, from = Catalog.thisBuild(ix, { version = "V9.0.0" })
    ok(b == nil and from == "none", "build: no entry -> unknown")
    b, from = Catalog.thisBuild({ game_builds = { { version = "V8.2.3", build = "1" }, { version = "V8.2.3", build = "2" } } }, { version = "V8.2.3" })
    ok(b == nil and from == "none", "build: two entries -> unknown")
    b, from = Catalog.thisBuild(ix, {})
    ok(b == nil and from == "none", "build: no footer, no manifest -> unknown")
end

-- ---------------------------------------------------------------- the live-like catalog
local okPayload = assert(Catalog.decode(read("catalog-ok.json")))
do
    local rows, warns, total = Catalog.model(okPayload.index, okPayload.revoked, INSTALLED, "0.25.0", B)
    eq(#warns, 0, "ok: no warnings")
    eq(total, 5, "ok: five mods (base and installer never listed)")
    ok(not byId(rows, NN .. "base") and not byId(rows, NN .. "base-installer"), "ok: no base, no installer")
    eq(byId(rows, NN .. "nucleus").state, "installed", "ok: Nucleus installed (0.25.0 is newer than 0.22.0)")
    eq(byId(rows, NN .. "mod-manager").state, "installed", "ok: Mod Manager installed")
    eq(byId(rows, NN .. "hud-clock").state, "available", "ok: HUD Clock available")
    eq(byId(rows, NN .. "waypoints").name, "Map Waypoints+", "ok: the display name")
    eq(byId(rows, NN .. "whistle-mute").primary, "audio", "ok: the primary category")
    eq(byId(rows, NN .. "hud-clock").coreNeed, ">=0.9.0", "ok: the Nucleus need")
    ok(not byId(rows, NN .. "hud-clock").needsCore, "ok: 0.25.0 meets >=0.9.0")
    local shown, matched = Catalog.filter(rows, { q = "clock" })
    ok(matched == 1 and shown[1].id == NN .. "hud-clock", "ok: 'clock' leaves only HUD Clock", ids(shown))
end

-- ---------------------------------------------------------------- the cases
local cases = assert(Catalog.decode(read("catalog-cases.json")))
local rows, warns, total = Catalog.model(cases.index, cases.revoked, INSTALLED, "0.12.1", B)
do
    local function warned(p) for _, w in ipairs(warns) do if w.msg:find(p, 1, true) then return true end end return false end
    ok(warned("example.noname skipped: no name"), "cases: a package without a name: one WARN")
    ok(warned("example.badver version 1 skipped"), "cases: a bad version: one WARN")
    eq(#warns, 2, "cases: exactly two WARNs")
    ok(byId(rows, "example.badver") and byId(rows, "example.badver").version == "0.1.0", "cases: the good version of that package stays")
    eq(total, 15, "cases: fifteen mods read")
    -- version pick: 0.4.0 another build, 0.2.5 revoked (block), 0.2.0 revoked (id and sha in other case, disable)
    local p = byId(rows, "example.picker")
    ok(p.offered and p.offered.version == "0.3.0" and p.version == "0.3.0", "pick: the newest of this build, not revoked: 0.3.0", p.version)
    -- a revoked entry with another sha256 doesn't revoke
    eq(byId(rows, "example.hud-clock").state, "available", "revocation: another sha256 is not revoked")
    -- unsatisfiable dependency: the next older satisfiable version, else other-build
    eq(byId(rows, "example.unsat").version, "0.1.0", "deps: newest needs an absent mod -> 0.1.0 offered")
    eq(byId(rows, "example.never").state, "other-build", "deps: no satisfiable version -> other-build")
    local o = byId(rows, "example.other")
    ok(o.state == "other-build" and o.version == "0.9.0" and o.offered == nil, "other build: shown with its newest version, never offered")
    eq(byId(rows, "example.older").state, "update", "installed 0.2.0, offered 0.3.0: update")
    eq(byId(rows, "example.taken").state, "conflict", "the folder holds another id: conflict")
    eq(byId(rows, "example.bare").state, "installed", "an installed row without an id matches by folder")
    eq(byId(rows, "example.bare").name, "Bare", "no displayName: the name")
    local n = byId(rows, "example.needy")
    ok(n.state == "available" and n.needsCore and n.coreNeed == ">=1.0.0", "needsCore: offered (the catalog's Nucleus 1.0.0 meets it), core 0.12.1 doesn't")
    eq(byId(rows, "example.chain").state, "available", "deps: satisfiable through an offered version, recursively")
    ok(byId(rows, "example.cyc-a").state == "other-build" and byId(rows, "example.cyc-b").state == "other-build", "deps: a cycle is never satisfiable (and ends)")
end
do -- Nucleus 0.25.0 installed and 1.0.0 offered is an update.
    eq(byId(rows, NN .. "nucleus").state, "update", "Nucleus 0.25.0 installed, 1.0.0 offered: update")
end

-- build unknown: nothing offered
do
    local r2 = Catalog.model(cases.index, cases.revoked, INSTALLED, "0.12.1", nil)
    local all = true
    for _, r in ipairs(r2) do if r.state ~= "other-build" then all = false end end
    ok(all, "build unknown: every package is other-build")
    local _, m1 = Catalog.filter(r2, { ["for"] = "game" })
    local _, m2 = Catalog.filter(r2, { ["for"] = "all" })
    ok(m1 == 0 and m2 == #r2, "build unknown: THIS GAME empty, ALL BUILDS shows them")
end

-- ---------------------------------------------------------------- search and filters
do
    local t = Catalog.terms("  CLOCK  hud ")
    ok(#t == 2 and t[1] == "clock" and t[2] == "hud", "terms: split on spaces, lower case")
    local shown = Catalog.filter(rows, { q = "  CLOCK  hud " })
    eq(ids(shown), "example.hud-clock", "search: both terms in the name or description")
    eq(#Catalog.terms("a b c d e f g h i j"), 8, "terms: at most 8")
    eq(#Catalog.terms(string.rep("x", 100)), 1, "terms: one long term")
    eq(#Catalog.terms(string.rep("x", 100))[1], 64, "terms: the text cut to 64 characters")
    eq(Catalog.terms("\195\132BC")[1], "\195\132bc", "terms: non-ASCII bytes kept as they are")
    eq(#Catalog.filter(rows, { q = "\195\164" }), 0, "search: non-ASCII compared as bytes")
    local function f(x) local s, m = Catalog.filter(rows, x) return ids(s), m end
    local s1 = f({ cat = "audio" })
    eq(s1, "example.chain,example.needy", "CATEGORY audio: any of its categories")
    eq((f({ cat = "qol", ["for"] = "all" })), "example.bare,example.hud-clock,example.older", "CATEGORY qol (any category; ALL BUILDS)")
    eq((f({ show = "installed" })), "example.bare,nuclearnightmare-community.nucleus,example.older", "SHOW INSTALLED: installed and update")
    eq((f({ show = "update" })), "nuclearnightmare-community.nucleus,example.older", "SHOW UPDATE AVAILABLE")
    local na = f({ show = "not-installed" })
    ok(na:find("example.taken", 1, true) and na:find("example.picker", 1, true) and not na:find("example.older", 1, true), "SHOW NOT INSTALLED: available and conflict", na)
    eq((f({ scope = "host" })), "example.tower", "SCOPE host: the offered version's scope")
    eq((f({ scope = "both" })), "example.older", "SCOPE both")
    local game, ready, all = select(2, f({ ["for"] = "game" })), select(2, f({ ["for"] = "ready" })), select(2, f({ ["for"] = "all" }))
    ok(game == 11 and ready == 10 and all == 15, "FOR: THIS GAME (not other-build) 11, READY TO RUN (also not needsCore) 10, ALL BUILDS 15", game .. " " .. ready .. " " .. all)
    -- sorted by display name without case
    local s = Catalog.filter(rows, { ["for"] = "all" })
    local sorted = true
    for i = 2, #s do if s[i - 1].name:lower() > s[i].name:lower() then sorted = false end end
    ok(sorted, "rows sorted by display name without case")
end

-- ---------------------------------------------------------------- caps: 600 packages, 70 versions, 40 dependsOn; 300 shown
do
    local pk = {}
    for i = 1, 600 do
        local vs = {}
        for k = 1, (i == 1 and 70 or 1) do
            local deps = {}
            if i == 2 then for d = 1, 40 do deps[d] = { id = "x.dep" .. d, version = ">=0.0.0" } end end
            vs[k] = { version = "0." .. k .. ".0", game = { build = B }, scope = "client", dependsOn = deps, sha256 = string.rep("a", 64) }
        end
        pk[i] = { id = string.format("x.m%03d", i), name = "M" .. i, kind = "mod", categories = { "ui" }, description = "d", versions = vs }
    end
    local r, w, t = Catalog.model({ packages = pk }, nil, {}, "1.0.0", B)
    eq(t, 512, "cap: 512 packages read")
    local capWarn = false
    for _, x in ipairs(w) do if x.key == "catalog:cap" then capWarn = true end end
    ok(capWarn, "cap: one WARN for the rest")
    eq(byId(r, "x.m001").version, "0.64.0", "cap: 64 versions read (the newest of those)")
    eq(#byId(r, "x.m002").deps, 32, "cap: 32 dependsOn read")
    local shown, matched = Catalog.filter(r, {})
    ok(#shown == 120 and matched == 511, "cap: 120 shown of the matches", #shown .. " " .. matched)
end

-- ---------------------------------------------------------------- ages
do
    local t0 = Catalog.epoch("2026-11-21T00:59:08Z")
    eq(Catalog.epoch("1970-01-01T00:00:00Z"), 0, "epoch: zero")
    eq(Catalog.epoch("2000-03-01T00:00:00Z"), 951868800, "epoch: a leap year")
    eq(Catalog.age("2026-11-21T00:59:08Z", t0 + 3599).key, "justNow", "age: under an hour")
    eq(Catalog.age("2026-11-21T00:59:08Z", t0 - 100).key, "justNow", "age: a future time")
    local a = Catalog.age("2026-11-21T00:59:08Z", t0 + 3 * 3600 + 5)
    ok(a.key == "hoursAgo" and a.n == 3, "age: 3 hours")
    a = Catalog.age("2026-11-21T00:59:08Z", t0 + 47 * 3600)
    ok(a.key == "hoursAgo" and a.n == 47, "age: 47 hours")
    a = Catalog.age("2026-11-21T00:59:08Z", t0 + 48 * 3600)
    ok(a.key == "daysAgo" and a.n == 2, "age: 48 hours is 2 days")
    ok(Catalog.age("yesterday", t0) == nil and Catalog.age(nil, t0) == nil, "age: unreadable -> nil")
end

-- ---------------------------------------------------------------- wrap and clean
do
    local w = Catalog.wrap("one two three four", 10, 5)
    ok(#w == 2 and w[1] == "one two" and w[2] == "three four", "wrap: words by width", table.concat(w, "|"))
    w = Catalog.wrap(string.rep("x", 20), 8, 5)
    ok(#w == 3 and w[1] == string.rep("x", 8) and w[3] == "xxxx", "wrap: a long word is split")
    w = Catalog.wrap(string.rep("word ", 200), 72, 5)
    ok(#w == 5 and w[5]:sub(-3) == "...", "wrap: at most 5 lines, the last ends with ...")
    for _, l in ipairs(w) do ok(utf8.len(l) <= 72, "wrap: at most 72 characters") end
    eq(#Catalog.wrap("", 72, 5), 0, "wrap: nothing")
    eq(Catalog.clean("a\nb\27c", 10), "a b c", "clean: control characters as spaces")
    eq(utf8.len(Catalog.clean(string.rep("\195\164", 300), 256)), 256, "clean: cut to characters")
    eq(Catalog.token("a b\n"), "a?b?", "token: printable ASCII only")
end

io.stdout:write(("catalog_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
