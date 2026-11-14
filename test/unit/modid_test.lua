-- Unit tests for Scripts/modid.lua: the local copy of the mod id normalizer, on the cases
-- _bmad-output/specs/spec-distribution-v0/mod-ids.md gives. Swapped for the shared cases with the shared normalizer
-- (distribution story 13). Run from the repo root:  texlua test/unit/modid_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
package.path = ROOT .. "/Scripts/?.lua;" .. package.path
local M = require("modid")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function norm(id, want, name)
    local okP, got, err = pcall(M.normalize, id)
    ok(okP and got == want, name, tostring(got) .. " / " .. tostring(err))
end
local function refused(id, part, name)
    local okP, got, err = pcall(M.normalize, id)
    ok(okP and got == nil and type(err) == "string" and (not part or err:find(part, 1, true) ~= nil), "refused: " .. name, tostring(got) .. " / " .. tostring(err))
end

-- mod-ids.md "Id format": the stored form, the GitHub long form, case.
norm("nuclearnightmare-community.waypoints", "nuclearnightmare-community.waypoints", "<owner>.<mod>")
norm("github.com/NuclearNightmare-Community.waypoints", "nuclearnightmare-community.waypoints", "github.com/<owner>.<mod> -> <owner>.<mod>")
norm("NuclearNightmare-Community.Nucleus", "nuclearnightmare-community.nucleus", "lowercased")
norm("GitHub.com/NuclearNightmare-Community.nucleus", "nuclearnightmare-community.nucleus", "the prefix in any case")
norm("nuclearnightmare-community.base-installer", "nuclearnightmare-community.base-installer", "a hyphen in the mod part")
norm("a.b", "a.b", "the shortest id")
-- refused
refused("gitlab.com/alice.waypoints", "another host", "another host (refused for now)")
refused("gitlab.com/group/sub.waypoints", "another host", "a subgroup on another host")
refused("www.github.com/NuclearNightmare-Community.waypoints", "accepted forms", "www.github.com/")
refused("http://github.com/NuclearNightmare-Community.waypoints", "accepted forms", "http://")
refused("https://github.com/NuclearNightmare-Community.waypoints", "accepted forms", "https://")
refused("nucleus", "no namespace", "a bare id (the legacy alias is inventory.lua's, not the normalizer's)")
refused("Nucleus", "no namespace", "a bare id in any case")
refused("other.nucleus.x", "not an id", "a dot in a GitHub owner")
refused("owner.mod_name", "not an id", "an underscore in the mod part")
refused("owner.", "not an id", "an empty mod part")
refused(".mod", "not an id", "an empty owner")
refused(" owner.mod", "not an id", "a leading space")
refused("owner.mod ", "not an id", "a trailing space")
refused("github.com/", "no namespace", "the prefix alone")
refused("", "empty", "empty")
refused(string.rep("a", 100) .. "." .. string.rep("b", 100), "at most 200", "201 characters")
norm(string.rep("a", 100) .. "." .. string.rep("b", 99), string.rep("a", 100) .. "." .. string.rep("b", 99), "200 characters")
for _, x in ipairs({ 1, true, {}, false }) do refused(x, "must be a string", "a " .. type(x)) end
do local okP, got = pcall(M.normalize) ok(okP and got == nil, "nil: refused, never raises") end

io.stdout:write(("modid_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
