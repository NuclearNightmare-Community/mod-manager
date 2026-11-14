-- Unit tests for Scripts/strings.lua: the tables and the picker (core's rule: exact tag, then the prefix before "-",
-- then en, case-insensitive). Run from the repo root:  texlua test/unit/strings_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
package.path = ROOT .. "/Scripts/?.lua;" .. package.path
local S = require("strings")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. tostring(got) .. ", want " .. tostring(want)) end

-- English: every string the spec names, upper case.
local want = { manage = "MANAGE MODS", title = "MOD MANAGER", name = "NAME", version = "VERSION", on = "ON", off = "OFF",
    alwaysOn = "ALWAYS ON", configure = "CONFIGURE", nucleus = "NUCLEUS", gameBuild = "GAME BUILD", unmanaged = "UNMANAGED", unknown = "-" }
for k, v in pairs(want) do eq(S.TABLES.en[k], v, "en." .. k) end
for k, v in pairs(S.TABLES.en) do
    ok(want[k] ~= nil, "en." .. k .. " is a string the spec names")
    eq(v:upper(), v, "en." .. k .. " is upper case")
end

-- The picker, with a test table set (a de table present, no zh).
local T = { en = { name = "NAME", title = "MOD MANAGER" }, de = { name = "NAME-DE" }, ["zh-Hant"] = { name = "NAME-ZHT" } }
eq(S.pick("de", T), "de", "de: exact")
eq(S.get("name", "de", T), "NAME-DE", "de: German")
eq(S.get("title", "de", T), "MOD MANAGER", "de: a key German lacks comes from English")
eq(S.pick("de-AT", T), "de", "de-AT: the prefix")
eq(S.pick("DE", T), "de", "DE: case-insensitive")
eq(S.pick("zh-Hans", T), "en", "zh-Hans with no zh table: English")
eq(S.get("name", "zh-Hans", T), "NAME", "zh-Hans: English string")
eq(S.pick("zh-hant", T), "zh-Hant", "zh-hant: the exact tag in any case")
eq(S.pick("fr", T), "en", "unknown: English")
eq(S.pick("", T), "en", "empty: English")
eq(S.pick(nil, T), "en", "nil: English")
eq(S.pick(3, T), "en", "a number: English")
eq(S.get("manage", "xx"), "MANAGE MODS", "the shipped tables: English for an unknown language")
do
    local b = S.byLanguage("name", T)
    ok(b.en == "NAME" and b.de == "NAME-DE" and b["zh-Hant"] == "NAME-ZHT", "byLanguage: one key across languages")
    local m = S.byLanguage("manage")
    ok(m.en == "MANAGE MODS", "byLanguage: the entry label has en")
end

-- The language read from the game (stubbed CDO).
do
    local cdo = { lang = "de", IsValid = function() return true end }
    function cdo:GetCurrentLanguage() if self.lang == "boom" then error("x") end return { ToString = function() return self.lang end } end
    StaticFindObject = function(p) return p:find("KismetInternationalizationLibrary", 1, true) and cdo or nil end
    eq(S.language(), "de", "language: GetCurrentLanguage's FString")
    cdo.lang = "boom"; eq(S.language(), "en", "language: a failing call reads as en")
    cdo.lang = ""; eq(S.language(), "en", "language: empty reads as en")
    StaticFindObject = function() return nil end
    eq(S.language(), "en", "language: no CDO reads as en")
    StaticFindObject = nil
    eq(S.language(), "en", "language: no UE4SS at all reads as en")
end

io.stdout:write(("strings_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
