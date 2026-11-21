-- Unit tests for Scripts/status.lua: the session baseline and pending, the build compare, dependency problems, the
-- dependents of a mod, the confirm names, the alert key. Run from the repo root:  texlua test/unit/status_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
package.path = ROOT .. "/Scripts/?.lua;" .. package.path
dofile(ROOT .. "/test/unit/nucleus_pkg.lua")(ROOT) -- nucleus.semver from the Nucleus repo
package.loaded.status = nil -- texlua preloads its own "status" library; ours is Scripts/status.lua
local Status = require("status")
local S = require("strings")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. tostring(got) .. ", want " .. tostring(want)) end
local function fmt(k, ...) return S.fmt(k, "en", ...) end

local CORE = "nuclearnightmare-community.nucleus"
local BASE = "nuclearnightmare-community.mod-manager-base"
local function row(t)
    return { key = t.folder:lower(), folder = t.folder, name = t.name or t.folder, version = t.version, state = t.state or "on",
        id = t.id, deps = t.deps or {}, gameVersion = t.gv, gameBuild = t.gb, paks = {} }
end
local function rows()
    return {
        row{ folder = "Nucleus", version = "0.12.1", state = "locked", id = CORE, gv = "V8.2.3", gb = "26601774" },
        row{ folder = "ModManager", name = "Mod Manager", version = "0.2.0", state = "locked", id = "nuclearnightmare-community.mod-manager",
            deps = { { id = CORE, need = ">=0.12.0" } }, gv = "V8.2.3", gb = "26601774" },
        row{ folder = "ModManagerBase", name = "Mod Manager Base", version = "1.0.0", id = BASE, deps = { { id = CORE, need = ">=0.12.0" } }, gv = "V8.2.3", gb = "26601774" },
        row{ folder = "ModManagerDep", name = "Mod Manager Dep", version = "1.0.0", id = "nuclearnightmare-community.mod-manager-dep",
            deps = { { id = BASE, need = ">=1.0.0" } }, gv = "V8.2.3", gb = "26601774" },
        row{ folder = "ModManagerFixture", version = "9.9.9", state = "off", id = "nuclearnightmare-community.mod-manager-fixture", gv = "V0.0.0", gb = "1",
            deps = { { id = CORE, need = ">=0.1.0" }, { id = "nuclearnightmare-community.mod-manager-missing", need = ">=1.0.0" }, { id = BASE, need = ">=2.0.0" } } },
        row{ folder = "ModManagerBare", state = "off" },
        { key = "modmanagerpak", name = "ModManagerPak", pakOnly = true, state = "on", deps = {}, paks = { "ModManagerPak_P.pak" } },
    }
end
local RUN = { version = "V8.2.3", build = nil }

do -- the matrix: healthy rows none; the fixture build + dependency (two lines); a pak none
    local r = rows()
    local b = Status.baseline(r)
    local st = Status.compute(r, { baseline = b, running = RUN, settingsPending = {}, fmt = fmt })
    for _, k in ipairs({ "nucleus", "modmanager", "modmanagerbase", "modmanagerdep", "modmanagerbare", "modmanagerpak" }) do
        eq(#st[k].kinds, 0, k .. ": no icon")
        eq(Status.logText(st[k]), "none | ", k .. ": the log text")
    end
    local f = st.modmanagerfixture
    eq(table.concat(f.kinds, ","), "build,dep", "fixture: build, then dependency")
    eq(f.tips.build, "MADE FOR GAME V0.0.0 (BUILD 1). THIS GAME: V8.2.3 (BUILD -).", "build tooltip: both games, build unknown as -")
    eq(f.tips.dep, "NEEDS nuclearnightmare-community.mod-manager-missing (NOT INSTALLED)\nNEEDS Mod Manager Base >=2.0.0 (INSTALLED: 1.0.0)", "one dependency icon, two lines")
    eq(#f.lines, 3, "three problem lines")
    eq(Status.logText(f), "build,dep | MADE FOR GAME V0.0.0 (BUILD 1). THIS GAME: V8.2.3 (BUILD -). / NEEDS nuclearnightmare-community.mod-manager-missing (NOT INSTALLED) / NEEDS Mod Manager Base >=2.0.0 (INSTALLED: 1.0.0)", "the STATUS text")
end
do -- the build compare: build when both known, else version; unknown on either side: none
    local r = rows()
    local function kinds(running, gv, gb)
        r[1].gameVersion, r[1].gameBuild = gv, gb
        local st = Status.compute(r, { baseline = {}, running = running, fmt = fmt })
        return table.concat(st.nucleus.kinds, ",")
    end
    eq(kinds({ version = "V8.2.3", build = "26601774" }, "V8.2.3", "26601774"), "", "same build: none")
    eq(kinds({ version = "V9.0.0", build = "26601774" }, "V8.2.3", "26601774"), "", "the build decides when both are known")
    eq(kinds({ version = "V8.2.3", build = "27000000" }, "V8.2.3", "26601774"), "build", "another build: the icon")
    eq(kinds({ version = "V9.0.0" }, "V8.2.3", "26601774"), "build", "running build unknown: the version decides")
    eq(kinds({ version = nil, build = nil }, "V8.2.3", "26601774"), "", "the running game unknown: none")
    eq(kinds({ version = "V9.0.0" }, nil, nil), "", "the mod's game unknown: none")
    eq(kinds({ build = "1" }, "V8.2.3", nil), "", "mod has a version only, game a build only: none")
end
do -- pending: on/off differs from the session baseline; a setting's restart
    local r = rows()
    local b = Status.baseline(r)
    r[4].state = "off" -- Dep turned off this session
    r[6].state = "on"  -- Bare turned on
    local st = Status.compute(r, { baseline = b, running = RUN, settingsPending = { modmanagerbase = true }, fmt = fmt })
    eq(st.modmanagerdep.pending, "off", "Dep: pending off")
    eq(st.modmanagerdep.tips.restart, "TURNS OFF AFTER A RESTART", "its tooltip")
    eq(table.concat(st.modmanagerdep.kinds, ","), "restart", "restart only")
    eq(st.modmanagerbare.tips.restart, "TURNS ON AFTER A RESTART", "Bare: turns on")
    eq(st.modmanagerbase.tips.restart, "A SETTING APPLIES AFTER A RESTART", "a setting pending")
    r[4].state = "on"
    st = Status.compute(r, { baseline = b, running = RUN, fmt = fmt })
    ok(st.modmanagerdep.pending == nil and #st.modmanagerdep.kinds == 0, "back on: not pending")
    -- turned off and a setting pending: both lines in one icon
    r[4].state = "off"
    st = Status.compute(r, { baseline = b, running = RUN, settingsPending = { modmanagerdep = true }, fmt = fmt })
    eq(st.modmanagerdep.tips.restart, "TURNS OFF AFTER A RESTART\nA SETTING APPLIES AFTER A RESTART", "both restart lines")
    -- a row first seen later becomes part of the baseline as it is
    local later = row{ folder = "Later", state = "on" }
    r[#r + 1] = later
    Status.baseline(r, b)
    eq(b.later, true, "a new row: its state is its baseline")
    eq(b.modmanagerdep, true, "existing baselines unchanged")
end
do -- dependencies: turned off, unknown version, legacy alias handled upstream (inventory.depId)
    local r = rows()
    r[3].state = "off"
    local st = Status.compute(r, { baseline = {}, running = RUN, fmt = fmt })
    eq(st.modmanagerdep.tips.dep, "NEEDS Mod Manager Base (TURNED OFF)", "the needed mod off: TURNED OFF")
    r[3].state = "on"; r[3].version = nil
    st = Status.compute(r, { baseline = {}, running = RUN, fmt = fmt })
    eq(st.modmanagerdep.tips.dep, "NEEDS Mod Manager Base >=1.0.0 (INSTALLED: -)", "unknown version: a problem")
    r[3].version = "1.0.0"
    r[4].deps = { { id = BASE } }
    st = Status.compute(r, { baseline = {}, running = RUN, fmt = fmt })
    eq(#st.modmanagerdep.kinds, 0, "no need given: installed and on is enough")
    r[4].deps = { { id = r[4].id, need = ">=9.0.0" } }
    st = Status.compute(r, { baseline = {}, running = RUN, fmt = fmt })
    eq(#st.modmanagerdep.kinds, 0, "a mod depending on itself: ignored")
    -- a long tooltip is cut at 512 bytes
    local many = {}
    for i = 1, 40 do many[i] = { id = "owner.missing-mod-" .. i } end
    r[4].deps = many
    st = Status.compute(r, { baseline = {}, running = RUN, fmt = fmt })
    ok(#st.modmanagerdep.tips.dep <= 512 and #st.modmanagerdep.lines == 40, "tooltip at most 512 bytes; every line kept for Configure")
end
do -- dependents and the confirm names
    local r = rows()
    local d = Status.dependents(r, r[3])
    eq(table.concat(d, ","), "Mod Manager Dep", "Base: Dep needs it (the fixture is off)")
    r[5].state = "on"
    eq(table.concat(Status.dependents(r, r[3]), ","), "Mod Manager Dep,ModManagerFixture", "an on fixture counts too")
    eq(#Status.dependents(r, r[6]), 0, "Bare (no id): none")
    local core = Status.dependents(r, r[1])
    ok(#core >= 3, "Nucleus: many (locked ModManager counts as on)")
    eq(Status.confirmNames({ "A" }, fmt), "A", "one name")
    eq(Status.confirmNames({ "A", "B", "C", "D", "E" }, fmt), "A, B, C, D, E", "five names")
    eq(Status.confirmNames({ "A", "B", "C", "D", "E", "F", "G" }, fmt), "A, B, C, D, E AND 2 MORE", "then AND n MORE")
    eq(S.fmt("confirm", "en", "Mod Manager Base", Status.confirmNames({ "Mod Manager Dep" }, fmt)), "TURN OFF Mod Manager Base? Mod Manager Dep NEED IT.", "the confirm text")
end
do -- the alert key
    local n = rows()[1]
    eq(Status.alertKey(n, { version = "V9.0.0" }), "nucleus-build 0.12.1 V9.0.0", "version when the build is unknown")
    eq(Status.alertKey(n, { version = "V9.0.0", build = "27000000" }), "nucleus-build 0.12.1 27000000", "the build when known")
    n.version = "0.1\1"
    eq(Status.alertKey(n, {}), "nucleus-build 0.1? -", "printable ASCII only")
end
eq(Status.cut("ab\226\130\172cd", 4), "ab", "cut never splits a character")
eq(Status.cut("abc", 5), "abc", "short: unchanged")

do -- v2 story 6: a revoked installed version is the kind revoked, last, with its reason; it only flags.
    local rs = rows()
    rs[3].revoked = { reason = "crash on map load" }
    rs[4].revoked = { reason = "" }
    local st = Status.compute(rs, { baseline = Status.baseline(rs), running = { version = "V8.2.3", build = "26601774" }, fmt = fmt })
    local s3 = st[rs[3].key]
    eq(table.concat(s3.kinds, ","), "revoked", "revoked: the kind")
    eq(s3.tips.revoked, "REVOKED: crash on map load", "revoked: its tooltip")
    eq(s3.lines[#s3.lines], "REVOKED: crash on map load", "revoked: a problem line")
    eq(st[rs[4].key].tips.revoked, "REVOKED: NO REASON GIVEN", "revoked: no reason")
    eq(s3.pending, nil, "revoked: nothing pending (only flagged)")
    eq(rs[3].state, "on", "revoked: the row stays on")
end

io.stdout:write(("status_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
