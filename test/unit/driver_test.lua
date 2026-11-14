-- Load test for the test driver (test/ModManagerDriver/Scripts/main.lua) outside the game: for every scenario it loads,
-- builds its steps, registers one game-thread loop and runs a few ticks against an empty fake world (no player
-- controller yet) without a step throwing. The scenarios themselves only run in game (run.ps1).
-- Run from the repo root:  texlua test/unit/driver_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
local DIR = ROOT .. "/test/ModManagerDriver/Scripts"
local MAIN = DIR .. "/main.lua"

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end

local printed, loops, shared = {}, {}, {}
print = function(s) printed[#printed + 1] = (tostring(s):gsub("\n$", "")) end
local INVALID = { IsValid = function() return false end }
function FindFirstOf() return INVALID end
function FindAllOf() return nil end
function StaticFindObject() return INVALID end
function LoopInGameThreadWithDelay(ms, fn) loops[#loops + 1] = { ms = ms, fn = fn } return #loops end
function CancelDelayedAction() return true end
function LoopAsync() error("driver must not use LoopAsync") end
ModRef = { SetSharedVariable = function(_, k, v) shared[k] = v end, GetSharedVariable = function(_, k) return shared[k] end }

local scenarioFile = DIR .. "/scenario.txt"
for _, sc in ipairs({ "screen", "no-core", "old-core" }) do
    printed, loops = {}, {}
    local f = assert(io.open(scenarioFile, "w")); f:write(sc); f:close()
    local okL, err = pcall(dofile, MAIN)
    ok(okL, sc .. ": loads", err)
    local loaded, scen
    for _, l in ipairs(printed) do
        if l:find("^%[ModManagerDriver%] LOADED %d+ steps$") then loaded = l end
        if l == "[ModManagerDriver] SCENARIO " .. sc then scen = l end
    end
    ok(scen ~= nil, sc .. ": logs its scenario")
    ok(loaded ~= nil and tonumber(loaded:match("(%d+) steps")) >= 1, sc .. ": builds steps", loaded)
    ok(#loops == 1 and loops[1].ms == 250, sc .. ": one 250 ms game-thread loop")
    if loops[1] then
        for _ = 1, 10 do local okT, e = pcall(loops[1].fn); ok(okT, sc .. ": tick runs", e) end
    end
    local threw = false
    for _, l in ipairs(printed) do if l:find("threw") then threw = true end end
    ok(not threw, sc .. ": no step threw")
end
-- old-core reads the claimed version from the installed core's mod.json, two folders up (Mods/Nucleus/mod.json);
-- here there's none, so it says so as a FAIL line instead of publishing anything.
ok(shared["nucleus.version"] == nil, "old-core without a core mod.json publishes nothing")
os.remove(scenarioFile)
-- An unknown scenario ends at once with a FAIL line.
printed, loops = {}, {}
local f = assert(io.open(scenarioFile, "w")); f:write("bogus"); f:close()
dofile(MAIN)
os.remove(scenarioFile)
local ended = false
for _, l in ipairs(printed) do if l:find("END result=FAIL .*unknown%-scenario bogus") then ended = true end end
ok(ended and #loops == 0, "unknown scenario: END FAIL, no loop")

io.stdout:write(("driver_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
