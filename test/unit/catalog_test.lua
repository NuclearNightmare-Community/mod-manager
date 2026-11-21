-- Unit tests for Scripts/catalog.lua (pure): decode with its caps and type checks, this game's build, the offered
-- version (build, revocation, dependsOn satisfiable recursively, other-build), installed states (update, installed,
-- conflict, available), needsCore, the caps (512 packages, 64 versions, 32 dependsOn), search terms, the four filters,
-- the 120 cap, ages and the Details word wrap; v2 story 5: the install set (dependencies first, new and update, conflict,
-- downgrade, unsatisfiable, too-many, cycles, depth) and the download size. Fixtures: test/unit/fixtures/catalog-*.json (our own made-up payloads).
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

do -- A full-length description (280 characters): Details and search see all of it; only a row's copy is cut to 256.
    local desc = string.rep("a", 269) .. " zebrafinch" -- the word ends at character 280
    eq(#desc, 280, "the description is 280 characters")
    local vs = { { version = "1.0.0", scope = "client", game = { version = "V1", build = B }, dependsOn = {} } }
    local r = Catalog.model({ packages = { { id = "x.long", name = "Long", kind = "mod", categories = { "ui" }, description = desc, versions = vs } } }, nil, {}, "1.0.0", B)
    eq(r[1].description, desc, "the model keeps the whole 280-character description")
    eq(ids((Catalog.filter(r, { q = "zebrafinch" }))), "x.long", "search finds a word past character 256")
    eq(#Catalog.wrap(r[1].description, 72, 5), 4, "Details wraps all 280 characters")
    local big = Catalog.model({ packages = { { id = "x.big", name = "Big", kind = "mod", categories = { "ui" }, description = string.rep("b", 400), versions = vs } } }, nil, {}, "1.0.0", B)
    eq(#big[1].description, Catalog.MAX_DESCRIPTION_KEPT, "an over-long description is kept to 360 characters")
end

-- ---------------------------------------------------------------- v2 story 5: the install set
do
    local function V(v, deps, size, build)
        return { version = v, scope = "client", game = { version = "V8.2.3", build = build or B }, dependsOn = deps or {}, sha256 = string.rep("c", 64), size = size or 1000 }
    end
    local function P(id, name, versions) return { id = id, name = name, kind = "mod", categories = { "ui" }, description = name .. ".", versions = versions } end
    local function D(id, need) return { id = id, version = need } end
    local CORE = NN .. "nucleus"
    local index = { packages = {
        P(CORE, "Nucleus", { V("0.30.0", {}, 700000), V("0.25.0", {}, 690000) }),
        P(NN .. "hud-clock", "HudClock", { V("0.3.0", { D(CORE, ">=0.9.0") }, 8620) }),
        P("x.alpha", "Alpha", { V("1.0.0", {}, 2048) }),
        P("x.target", "Target", { V("2.0.0", { D("x.alpha", ">=1.0.0"), D(CORE, ">=0.30.0") }, 4096) }),
        P("x.deep", "Deep", { V("1.0.0", { D("x.target", ">=2.0.0") }, 10) }),
        P("x.taken", "Taken", { V("1.0.0", {}, 10) }),
        P("x.usestaken", "UsesTaken", { V("1.0.0", { D("x.taken", ">=1.0.0") }, 10) }),
        P("x.newer", "Newer", { V("1.0.0", {}, 10) }),
        P("x.cyc-a", "CycA", { V("1.0.0", { D("x.cyc-b", ">=1.0.0") }, 10) }),
        P("x.cyc-b", "CycB", { V("1.0.0", { D("x.cyc-a", ">=1.0.0") }, 10) }),
        P("x.offsite", "Offsite", { V("1.0.0", { D("x.notlisted", ">=1.0.0") }, 10) }),
    } }
    -- 17 mods in a chain: x.c1 needs x.c2 ... x.c17 (more than 16 in one set), and a chain past depth 8
    for i = 1, 17 do
        index.packages[#index.packages + 1] = P("x.c" .. i, "C" .. i, { V("1.0.0", i < 17 and { D("x.c" .. (i + 1), ">=1.0.0") } or {}, 10) })
    end
    local inst = {
        { folder = "Nucleus", id = CORE, version = "0.25.0" },
        { folder = "Taken", id = "someone.else", version = "1.0.0" },
        { folder = "Newer", id = "x.newer", version = "2.0.0" },
        { folder = "NotListed", id = "x.notlisted", version = "1.2.0" },
    }
    local rows = Catalog.model(index, nil, inst, "0.25.0", B)
    local function setStr(set) local t = {} for i, e in ipairs(set) do t[i] = e.id .. "@" .. e.version .. ":" .. e.flag .. (e.from and ("<" .. e.from) or "") end return table.concat(t, ",") end

    local set, why = Catalog.installSet(rows, NN .. "hud-clock")
    eq(set and setStr(set), NN .. "hud-clock@0.3.0:new", "installSet: plain: the installed Nucleus meets >=0.9.0, only the target")
    eq(set and set[1].size, 8620, "installSet: the index size is kept")
    set, why = Catalog.installSet(rows, "x.target")
    eq(set and setStr(set), "x.alpha@1.0.0:new," .. CORE .. "@0.30.0:update<0.25.0,x.target@2.0.0:new", "installSet: a missing and a too-old dependency, dependencies first", why)
    eq(set and set[2].name, "Nucleus", "installSet: the dependency's name")
    set = Catalog.installSet(rows, "x.deep")
    eq(set and setStr(set), "x.alpha@1.0.0:new," .. CORE .. "@0.30.0:update<0.25.0,x.target@2.0.0:new,x.deep@1.0.0:new", "installSet: recursive")
    local s2, why2, info = Catalog.installSet(rows, "x.usestaken")
    ok(s2 == nil and why2 == "conflict" and info.name == "Taken", "installSet: a dependency's folder in use: conflict", why2)
    s2, why2, info = Catalog.installSet(rows, "x.taken")
    ok(s2 == nil and why2 == "conflict", "installSet: the target's own folder in use: conflict", why2)
    s2, why2, info = Catalog.installSet(rows, "x.newer")
    ok(s2 == nil and why2 == "downgrade" and info.name == "Newer", "installSet: the target installed newer than offered: downgrade", why2)
    local dg = { { id = "x.w", name = "W", state = "available", offered = { version = "1.0.0", deps = { { id = "x.n", need = ">=3.0.0" } } } },
        { id = "x.n", name = "N", state = "installed", installedVersion = "2.0.0", offered = { version = "1.0.0", deps = {} } } }
    s2, why2, info = Catalog.installSet(dg, "x.w")
    ok(s2 == nil and why2 == "downgrade" and info.name == "W" and info.dep == "N" and info.need == ">=3.0.0", "installSet: a dependency offered only below its installed version: downgrade", why2)
    s2, why2 = Catalog.installSet(rows, "x.c1")
    ok(s2 == nil and (why2 == "too-many" or why2 == "unsatisfiable"), "installSet: a 17-mod chain is refused", why2)
    s2, why2 = Catalog.installSet(rows, "x.offsite")
    eq(s2 and setStr(s2), "x.offsite@1.0.0:new", "installSet: a dependency outside the catalog, installed and met, is skipped", why2)
    s2, why2, info = Catalog.installSet(rows, "nobody.nothing")
    ok(s2 == nil and why2 == "unsatisfiable", "installSet: an unknown id: unsatisfiable", why2)
    -- the model only offers satisfiable versions; installSet still checks, on rows it is handed
    local fake = { { id = "x.t", name = "T", state = "available", offered = { version = "1.0.0", deps = { { id = "x.d", need = ">=3.0.0" } } }, deps = { { id = "x.d", need = ">=3.0.0", met = false } } },
        { id = "x.d", name = "D", state = "available", offered = { version = "2.0.0", deps = {} } } }
    s2, why2, info = Catalog.installSet(fake, "x.t")
    ok(s2 == nil and why2 == "unsatisfiable" and info.name == "T" and info.dep == "D" and info.need == ">=3.0.0", "installSet: no offered version meets the need: unsatisfiable, naming both", why2)
    fake[2].offered = nil
    s2, why2 = Catalog.installSet(fake, "x.t")
    eq(why2, "unsatisfiable", "installSet: a dependency with no offered version: unsatisfiable")
    -- a cycle in rows handed in: ends, and the version being chosen must meet the need
    local cyc = { { id = "x.a", name = "A", state = "available", offered = { version = "1.0.0", deps = { { id = "x.b", need = ">=1.0.0" } } } },
        { id = "x.b", name = "B", state = "available", offered = { version = "1.0.0", deps = { { id = "x.a", need = ">=1.0.0" } } } } }
    s2 = Catalog.installSet(cyc, "x.a")
    eq(s2 and setStr(s2), "x.b@1.0.0:new,x.a@1.0.0:new", "installSet: a cycle ends (visited set), each once")
    -- more than 16: a target with 16 dependencies
    local many = { { id = "x.top", name = "Top", state = "available", offered = { version = "1.0.0", deps = {} } } }
    for i = 1, 16 do
        many[#many + 1] = { id = "x.d" .. i, name = "D" .. i, state = "available", offered = { version = "1.0.0", deps = {} } }
        many[1].offered.deps[i] = { id = "x.d" .. i, need = ">=1.0.0" }
    end
    s2, why2 = Catalog.installSet(many, "x.top")
    eq(why2, "too-many", "installSet: 17 in one set: too-many")
    table.remove(many[1].offered.deps)
    s2 = Catalog.installSet(many, "x.top")
    eq(s2 and #s2, 16, "installSet: 16 in one set is fine")
    -- a need met by the installed version, broken by an update another dependency asks for: unsatisfiable
    do
        local SVm = require("nucleus.semver")
        local real = SVm.satisfies
        -- caret semantics for this case (the shipped semver reads ^ as a minimum): ^0.2.0 means >=0.2.0 and <0.3.0
        SVm.satisfies = function(have, need)
            local base = type(need) == "string" and need:match("^%^(%d+%.%d+%.%d+)$")
            if base then
                return real(have, ">=" .. base) and have:match("^%d+%.%d+%.") == base:match("^%d+%.%d+%.")
            end
            return real(have, need)
        end
        local rows2 = { { id = "x.t", name = "T", state = "available", offered = { version = "1.0.0", deps = {
                { id = "x.lib", need = "^0.2.0" }, { id = "x.b", need = ">=1.0.0" } } } },
            { id = "x.lib", name = "Lib", state = "installed", installedVersion = "0.2.5", offered = { version = "0.3.0", deps = {} } },
            { id = "x.b", name = "B", state = "available", offered = { version = "1.0.0", deps = { { id = "x.lib", need = ">=0.3.0" } } } } }
        local s3, why3, info3 = Catalog.installSet(rows2, "x.t")
        SVm.satisfies = real
        ok(s3 == nil and why3 == "unsatisfiable" and info3.name == "T" and info3.dep == "Lib" and info3.need == "^0.2.0",
            "installSet: a need the installed version met, broken by an update another dependency needs: unsatisfiable, naming it", why3)
    end
    -- depth: a chain of 10
    local chain = {}
    for i = 1, 10 do chain[i] = { id = "x.k" .. i, name = "K" .. i, state = "available", offered = { version = "1.0.0", deps = i < 10 and { { id = "x.k" .. (i + 1), need = ">=1.0.0" } } or {} } } end
    s2, why2 = Catalog.installSet(chain, "x.k1")
    eq(why2, "unsatisfiable", "installSet: deeper than 8: unsatisfiable")
    -- sizes
    local z = Catalog.sizeText(8620)
    ok(z.key == "sizeKB" and z.n == 9, "sizeText: 8620 bytes is 9 KB (rounded up)")
    z = Catalog.sizeText(1572864)
    ok(z.key == "sizeMB" and z.n == "1.5", "sizeText: 1.5 MB")
    z = Catalog.sizeText(0)
    ok(z.key == "sizeKB" and z.n == 1, "sizeText: nothing known reads 1 KB")
end

-- ---------------------------------------------------------------- v2 story 6: revocations, updates, uninstall
do
    local SHA_A, SHA_B, SHA_C = string.rep("a", 64), string.rep("b", 64), string.rep("c", 64)
    local function ver(v, sha, deps) return { version = v, scope = "client", game = { version = "V8.2.3", build = B }, dependsOn = deps or {}, sha256 = sha, size = 100 } end
    local function pkg(id, name, versions) return { id = id, name = name, kind = "mod", description = name .. ".", categories = { "ui" }, versions = versions } end
    local index = { packages = {
        pkg(NN .. "nucleus", "Nucleus", { ver("0.27.0", SHA_A) }),
        pkg(NN .. "mod-manager", "ModManager", { ver("0.8.0", SHA_A) }),
        pkg("x.newer", "NewerFix", { ver("0.3.1", SHA_A), ver("0.3.0", SHA_B) }),              -- 0.3.0 revoked, 0.3.1 offered
        pkg("x.older", "OlderFix", { ver("0.4.0", SHA_B), ver("0.3.1", SHA_A) }),              -- 0.4.0 revoked, 0.3.1 offered
        pkg("x.nofix", "NoFix", { ver("1.0.0", SHA_B) }),                                      -- 1.0.0 revoked, nothing else
        pkg("x.shadiff", "ShaDiff", { ver("1.0.0", SHA_A) }),                                  -- revoked entry with another sha
        pkg("x.gone", "Gone", { ver("2.0.0", SHA_A) }),                                        -- installed 1.0.0 no longer listed
        pkg("x.upd", "Upd", { ver("2.0.0", SHA_A, { { id = NN .. "nucleus", version = ">=0.27.0" } }) }),
    } }
    local revoked = { revoked = {
        { id = "X.Newer", version = "0.3.0", sha256 = SHA_B:upper(), reason = "crash on map load", action = "disable" },
        { id = "x.older", version = "0.4.0", sha256 = SHA_B, reason = "breaks saves", action = "block" },
        { id = "x.nofix", version = "1.0.0", sha256 = SHA_B, reason = "", action = "block" },
        { id = "x.shadiff", version = "1.0.0", sha256 = SHA_C, reason = "other build", action = "disable" },
        { id = "x.gone", version = "1.0.0", sha256 = SHA_C, reason = "pulled", action = "disable" },
    } }
    local installed = {
        { folder = "Nucleus", id = NN .. "nucleus", version = "0.26.0", deps = {} },
        { folder = "ModManager", id = NN .. "mod-manager", version = "0.8.0", deps = {} },
        { folder = "NewerFix", id = "x.newer", version = "0.3.0", deps = {} },
        { folder = "OlderFix", id = "x.older", version = "0.4.0", deps = {} },
        { folder = "NoFix", id = "x.nofix", version = "1.0.0", deps = {} },
        { folder = "ShaDiff", id = "x.shadiff", version = "1.0.0", deps = {} },
        { folder = "Gone", id = "x.gone", version = "1.0.0", deps = {} },
        { folder = "Upd", id = "x.upd", version = "1.0.0", deps = { { id = NN .. "nucleus", need = ">=0.20.0" } } },
    }
    local rows = Catalog.model(index, revoked, installed, "0.26.0", B)
    local r = byId(rows, "x.newer")
    ok(r.revoked and r.revoked.reason == "crash on map load" and r.revoked.action == "disable" and r.revoked.fix == "0.3.1", "revoked, newer fix: flagged with its reason, action and fix (id and sha without case)")
    eq(r.state, "update", "revoked, newer fix: still state update")
    eq(Catalog.action(r), "update", "revoked, newer fix: UPDATE")
    r = byId(rows, "x.older")
    ok(r.revoked and r.revoked.fix == "0.3.1" and r.revoked.action == "block", "revoked, older fix: the fix is the offered (older) version")
    eq(Catalog.action(r), "update", "revoked, older fix: UPDATE (UPDATE TO 0.3.1)")
    local set, why = Catalog.installSet(rows, "x.older")
    ok(set and #set == 1 and set[1].version == "0.3.1" and set[1].flag == "update" and set[1].from == "0.4.0", "installSet: a downgrade away from a revoked version is allowed", why)
    r = byId(rows, "x.nofix")
    ok(r.revoked and r.revoked.fix == nil, "revoked, no fix: no fix")
    eq(Catalog.action(r), nil, "revoked, no fix: no UPDATE")
    ok(Catalog.canUninstall(r), "revoked, no fix: UNINSTALL")
    eq(byId(rows, "x.shadiff").revoked, nil, "revoked entry's sha differs from the index's: not revoked")
    r = byId(rows, "x.gone")
    ok(r.revoked and r.revoked.reason == "pulled" and r.revoked.fix == "2.0.0", "the index no longer lists the installed version: revoked (any sha)")
    -- a non-revoked downgrade stays refused
    local dg = Catalog.model({ packages = { pkg("x.d", "D", { ver("1.0.0", SHA_A) }) } }, nil, { { folder = "D", id = "x.d", version = "2.0.0" } }, "0.26.0", B)
    local s2, w2 = Catalog.installSet(dg, "x.d")
    ok(s2 == nil and w2 == "downgrade", "installSet: a non-revoked downgrade is refused", w2)
    eq(Catalog.action(byId(dg, "x.d")), nil, "a newer installed (not revoked) version offers nothing")
    -- an update target with a too-old dependency: one set, the dependency first
    set = Catalog.installSet(rows, "x.upd")
    ok(set and #set == 2 and set[1].id == NN .. "nucleus" and set[1].flag == "update" and set[1].from == "0.26.0" and set[2].id == "x.upd" and set[2].from == "1.0.0",
        "installSet: an update whose new version needs a newer Nucleus: ALSO INSTALLS NUCLEUS (UPDATE FROM 0.26.0)")
    -- action, pending, uninstall
    local pend = { ["x.newer"] = true }
    eq(Catalog.action(byId(rows, "x.newer"), pend), nil, "pending: no UPDATE")
    eq(Catalog.canUninstall(byId(rows, "x.newer"), pend), false, "pending: no UNINSTALL")
    eq(Catalog.canUninstall(byId(rows, NN .. "nucleus")), false, "Nucleus: no UNINSTALL")
    eq(Catalog.canUninstall(byId(rows, NN .. "mod-manager")), false, "Mod Manager: no UNINSTALL")
    -- revokedInstalled: sorted by name, staged ones resolved
    local list = Catalog.revokedInstalled(rows)
    local names = {}
    for i, e in ipairs(list) do names[i] = e.name .. "@" .. e.version .. ":" .. (e.fix or "none") end
    eq(table.concat(names, ","), "Gone@1.0.0:2.0.0,NewerFix@0.3.0:0.3.1,NoFix@1.0.0:none,OlderFix@0.4.0:0.3.1", "revokedInstalled: every revoked installed version, by name")
    eq(#Catalog.revokedInstalled(rows, { ["x.gone"] = true, ["x.nofix"] = true }), 2, "revokedInstalled: a staged owner counts as resolved")
    -- not installed: never flagged
    local rows2 = Catalog.model(index, revoked, {}, "0.26.0", B)
    eq(#Catalog.revokedInstalled(rows2), 0, "revoked versions that aren't installed are not flagged")
    eq(byId(rows2, "x.newer").offered.version, "0.3.1", "the offered version skips the revoked one")
    -- a package the index dropped entirely: an orphan, revoked by id and version (any sha), no Browse row, no fix
    local orphRev = { revoked = { { id = "X.Dropped", version = "1.0.0", sha256 = SHA_A, reason = "pulled", action = "block" },
        { id = "x.dropped2", version = "9.9.9", sha256 = SHA_A, reason = "other version", action = "block" } } }
    local rows3, _, _, orphans = Catalog.model(index, orphRev, { { folder = "Dropped", id = "x.dropped", version = "1.0.0", name = "Dropped Mod" },
        { folder = "Dropped2", id = "x.dropped2", version = "1.0.0" }, { folder = "NewerFix", id = "x.newer", version = "0.3.0" } }, "0.26.0", B)
    eq(byId(rows3, "x.dropped"), nil, "orphan: no Browse row")
    ok(#orphans == 1 and orphans[1].id == "x.dropped" and orphans[1].name == "Dropped Mod" and orphans[1].installedVersion == "1.0.0"
        and orphans[1].revoked.reason == "pulled" and orphans[1].revoked.action == "block" and orphans[1].revoked.fix == nil,
        "orphan: an installed version of a dropped package, revoked by id (without case) and version")
    local all3 = {}
    for _, x in ipairs(rows3) do all3[#all3 + 1] = x end
    for _, x in ipairs(orphans) do all3[#all3 + 1] = x end
    local l3 = Catalog.revokedInstalled(all3)
    ok(#l3 == 1 and l3[1].id == "x.dropped" and l3[1].fix == nil, "orphan: in revokedInstalled, no fix")
    ok(Catalog.canUninstall(orphans[1]), "orphan: UNINSTALL")
    eq(Catalog.action(orphans[1]), nil, "orphan: no UPDATE")
end
do -- dependents: installed rows and staged owners whose dependsOn names the id (normalized)
    local rows = {
        { folder = "A", id = "x.a", name = "Alpha", deps = {} },
        { folder = "B", id = "x.b", name = "Bravo", deps = { { id = "X.A", need = ">=1.0.0" } } },
        { folder = "C", id = "x.c", name = "Charlie", deps = { { id = "x.a" } } },
        { folder = "D", id = "x.d", name = "Delta", deps = { { id = "x.z" } } },
        { key = "pak", name = "PakOnly", deps = { { id = "x.a" } } }, -- not a folder row
    }
    local names, ids2 = Catalog.dependents(rows, {}, "x.a")
    eq(table.concat(names, ","), "Bravo,Charlie", "dependents: installed rows that need it")
    eq(table.concat(ids2, ","), "x.b,x.c", "dependents: their ids")
    names = Catalog.dependents(rows, { ["x.e"] = { name = "Echo", deps = { { id = "x.a", need = ">=1.0.0" } } } }, "x.a")
    eq(table.concat(names, ","), "Bravo,Charlie,Echo", "dependents: a staged owner that needs it too")
    names = Catalog.dependents(rows, { ["x.b"] = { name = "Bravo", deps = {}, removal = true } }, "x.a")
    eq(table.concat(names, ","), "Charlie", "dependents: an owner staged for removal needs nothing")
    eq(#Catalog.dependents(rows, {}, "x.d"), 0, "dependents: nobody needs it")
end

io.stdout:write(("catalog_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
