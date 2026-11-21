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
    alwaysOn = "ALWAYS ON", configure = "CONFIGURE", nucleus = "NUCLEUS", gameBuild = "GAME BUILD", unmanaged = "UNMANAGED", unknown = "-",
    -- story 6
    pakFixed = "BLUEPRINT MODS CAN'T BE SWITCHED FROM THE GAME YET",
    madeFor = "MADE FOR GAME %s (BUILD %s). THIS GAME: %s (BUILD %s).",
    needsMissing = "NEEDS %s (NOT INSTALLED)", needsOff = "NEEDS %s (TURNED OFF)", needsVersion = "NEEDS %s %s (INSTALLED: %s)",
    turnsOn = "TURNS ON AFTER A RESTART", turnsOff = "TURNS OFF AFTER A RESTART", settingRestart = "A SETTING APPLIES AFTER A RESTART",
    confirm = "TURN OFF %s? %s NEED IT.", andMore = "%s AND %d MORE", turnOff = "TURN OFF",
    couldNotSave = "COULD NOT SAVE THE CHANGE", banner = "CHANGES APPLY AFTER A RESTART.", quit = "QUIT GAME",
    alert = "NUCLEUS %s WAS MADE FOR GAME %s. THIS GAME IS %s. MODS MAY NOT WORK UNTIL NUCLEUS IS UPDATED.",
    gameAt = "%s (BUILD %s)", appliesAfterRestart = "APPLIES AFTER A RESTART", lobbyOnly = "CAN ONLY BE CHANGED IN A LOBBY",
    setBy = "SET BY %s", notSaved = "NOT SAVED (%s)", noSettings = "NO SETTINGS",
    -- story 8
    restart = "RESTART NOW", cantRestart = "CAN'T RESTART: USE QUIT GAME AND START THE GAME AGAIN.",
    -- v2 story 3
    applied = "THE STAGED CHANGE WAS APPLIED.",
    applyFailed = "A STAGED CHANGE COULD NOT BE APPLIED (%s). IT IS TRIED AGAIN AT THE NEXT RESTART.",
    applyDropped = "A STAGED CHANGE COULD NOT BE APPLIED AND WAS DROPPED.",
    -- story 12
    scopeLabel = "RUNS ON",
    scopeHost = "HOST ONLY", scopeHostMeans = "ONLY THE HOST NEEDS IT; PLAYERS WHO JOIN DON'T",
    scopeClient = "JUST YOU", scopeClientMeans = "WORKS ON ITS OWN, WHETHER YOU HOST OR JOIN",
    scopeHostPlus = "HOST, PLAYERS OPTIONAL", scopeHostPlusMeans = "THE HOST NEEDS IT; PLAYERS WHO HAVE IT GET MORE",
    scopeBoth = "HOST AND PLAYERS", scopeBothMeans = "THE HOST AND EVERY PLAYER NEED IT",
    scopeUnknown = "UNKNOWN", scopeUnknownMeans = "THIS MOD DOESN'T SAY WHERE IT RUNS",
    -- v2 story 4: Browse and Details
    browse = "BROWSE", browseTitle = "BROWSE MODS", search = "SEARCH", searchHint = "TYPE TO SEARCH",
    searchTip = "WORDS IN THE NAME OR DESCRIPTION", category = "CATEGORY", show = "SHOW", scopeFilter = "RUNS ON", forFilter = "FOR",
    all = "ALL", showAll = "ALL", showInstalled = "INSTALLED", showNotInstalled = "NOT INSTALLED", showUpdate = "UPDATE AVAILABLE",
    forGame = "THIS GAME", forReady = "READY TO RUN", forAll = "ALL BUILDS", stateHeader = "STATE",
    stInstalled = "INSTALLED", stUpdate = "UPDATE AVAILABLE", stConflict = "FOLDER IN USE", stAvailable = "NOT INSTALLED",
    stOtherBuild = "OTHER GAME BUILD", needsCore = "NEEDS NUCLEUS %s", details = "DETAILS", refresh = "REFRESH",
    catalogUpdated = "CATALOG UPDATED %s", revocationsChecked = "REVOCATIONS CHECKED %s",
    justNow = "JUST NOW", hoursAgo = "%d HOURS AGO", daysAgo = "%d DAYS AGO", offline = "OFFLINE: SAVED CATALOG",
    checking = "CHECKING CATALOG...", unavailable = "CATALOG UNAVAILABLE. CHECK YOUR CONNECTION AND PRESS REFRESH.",
    refused = "CATALOG REFUSED (%s)", tooNew = "CATALOG NEEDS A NEWER MOD MANAGER", catalogError = "CATALOG ERROR",
    busy = "CATALOG BUSY", buildUnknown = "GAME BUILD UNKNOWN", noMatch = "NO MODS MATCH", count = "%d OF %d MODS",
    capped = "SHOWING THE FIRST %d", categoriesLine = "CATEGORIES: %s", forGameLine = "FOR GAME %s (%s)",
    needLine = "NEEDS %s %s: %s", needsNothing = "NEEDS NOTHING ELSE", andMoreNeeds = "AND %d MORE", met = "MET", notMet = "NOT MET",
    installedLine = "INSTALLED %s", no = "NO", publisherLine = "PUBLISHER %s", licenseLine = "LICENSE %s",
    ["cat.gameplay"] = "GAMEPLAY", ["cat.content"] = "CONTENT", ["cat.visuals"] = "VISUALS", ["cat.audio"] = "AUDIO",
    ["cat.ui"] = "USER INTERFACE", ["cat.qol"] = "QUALITY OF LIFE", ["cat.tools"] = "UTILITIES & TOOLS",
    ["cat.library"] = "LIBRARIES & FRAMEWORKS", ["cat.performance"] = "PERFORMANCE & OPTIMIZATION",
    ["cat.multiplayer"] = "MULTIPLAYER & NETWORKING", ["cat.localization"] = "LOCALIZATION", ["cat.overhaul"] = "OVERHAULS",
    ["cat.bug-fixes"] = "BUG FIXES", ["cat.maps"] = "MAPS" }
for k, v in pairs(want) do eq(S.TABLES.en[k], v, "en." .. k) end
for k, v in pairs(S.TABLES.en) do
    ok(want[k] ~= nil, "en." .. k .. " is a string the spec names")
    local words = v:gsub("%%[sd]", "")
    eq(words:upper(), words, "en." .. k .. " is upper case (apart from its %s/%d)")
    local _, n = v:gsub("%%", "")
    local _, m = v:gsub("%%[sd]", "")
    eq(n, m, "en." .. k .. ": only %s and %d")
end
-- fmt: filled in; a template without the values gives the bare template rather than raising
eq(S.fmt("needsOff", "en", "Mod Manager Base"), "NEEDS Mod Manager Base (TURNED OFF)", "fmt: filled")
eq(S.fmt("andMore", "en", "A, B", 2), "A, B AND 2 MORE", "fmt: %d")
eq(S.fmt("needsOff", "en"), "NEEDS %s (TURNED OFF)", "fmt: a missing value gives the template")
eq(S.fmt("confirm", "en", "100%", "x"), "TURN OFF 100%? x NEED IT.", "fmt: a % in a value is text")

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
