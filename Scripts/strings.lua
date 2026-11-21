-- Mod Manager story 3 (story 6 adds its strings, story 8 RESTART NOW's): every string the player sees, per language, and the picker. The rule is core's
-- (mods/Nucleus/lua/pkg/ui/strings.lua): the game's language tag exactly, then its prefix before "-", then English,
-- all without regard to case. A language table may leave keys out; those come from English. English is required and
-- upper case, like the game's own labels (the menu column's buttons have no case transform).
-- The language is read from KismetInternationalizationLibrary:GetCurrentLanguage.
local S = {}

-- language -> key -> string. Add a language as one more table.
S.TABLES = {
    en = {
        manage = "MANAGE MODS",       -- the title-screen menu entry
        title = "MOD MANAGER",        -- the main window's title
        name = "NAME",                -- header
        version = "VERSION",          -- header, and the Configure window's version line
        on = "ON",                    -- the toggle box's tooltips
        off = "OFF",
        alwaysOn = "ALWAYS ON",
        configure = "CONFIGURE",      -- the gear's tooltip
        nucleus = "NUCLEUS",          -- the Configure window's lines
        gameBuild = "GAME BUILD",
        unmanaged = "UNMANAGED",      -- the version of a pak with no mod folder
        unknown = "-",                -- a missing, wrong-typed or unreadable value
        -- story 6: the toggle, the status slot, the confirm and alert windows, Quit, Configure's settings
        pakFixed = "BLUEPRINT MODS CAN'T BE SWITCHED FROM THE GAME YET", -- a pak's disabled box
        madeFor = "MADE FOR GAME %s (BUILD %s). THIS GAME: %s (BUILD %s).", -- the build icon's tooltip
        needsMissing = "NEEDS %s (NOT INSTALLED)",   -- the dependency icon's lines
        needsOff = "NEEDS %s (TURNED OFF)",
        needsVersion = "NEEDS %s %s (INSTALLED: %s)",
        turnsOn = "TURNS ON AFTER A RESTART",        -- the restart icon's lines
        turnsOff = "TURNS OFF AFTER A RESTART",
        settingRestart = "A SETTING APPLIES AFTER A RESTART",
        confirm = "TURN OFF %s? %s NEED IT.",        -- the confirm window
        andMore = "%s AND %d MORE",
        turnOff = "TURN OFF",
        couldNotSave = "COULD NOT SAVE THE CHANGE",  -- the main window's message line
        banner = "CHANGES APPLY AFTER A RESTART.",   -- while a change is pending
        quit = "QUIT GAME",
        -- story 8: Restart now (shown beside QUIT GAME when the game can be started again the way it was launched)
        restart = "RESTART NOW",
        cantRestart = "CAN'T RESTART: USE QUIT GAME AND START THE GAME AGAIN.", -- the message line when the helper can't start
        -- v2 story 3: the result of the last staged change (the message line, on the first open after it)
        applied = "THE STAGED CHANGE WAS APPLIED.",
        applyFailed = "A STAGED CHANGE COULD NOT BE APPLIED (%s). IT IS TRIED AGAIN AT THE NEXT RESTART.",
        applyDropped = "A STAGED CHANGE COULD NOT BE APPLIED AND WAS DROPPED.",
        alert = "NUCLEUS %s WAS MADE FOR GAME %s. THIS GAME IS %s. MODS MAY NOT WORK UNTIL NUCLEUS IS UPDATED.",
        gameAt = "%s (BUILD %s)",                    -- a game in the alert
        appliesAfterRestart = "APPLIES AFTER A RESTART", -- a restart setting's mark
        lobbyOnly = "CAN ONLY BE CHANGED IN A LOBBY",
        setBy = "SET BY %s",                         -- a setting with a source
        notSaved = "NOT SAVED (%s)",                 -- Configure's message line
        noSettings = "NO SETTINGS",
        -- story 12: where a mod runs (mod.json scope): the scope icon's tooltip is "<name> - <meaning>", and Configure's
        -- line is "RUNS ON: <name> - <meaning>"
        scopeLabel = "RUNS ON",
        scopeHost = "HOST ONLY",
        scopeHostMeans = "ONLY THE HOST NEEDS IT; PLAYERS WHO JOIN DON'T",
        scopeClient = "JUST YOU",
        scopeClientMeans = "WORKS ON ITS OWN, WHETHER YOU HOST OR JOIN",
        scopeHostPlus = "HOST, PLAYERS OPTIONAL",
        scopeHostPlusMeans = "THE HOST NEEDS IT; PLAYERS WHO HAVE IT GET MORE",
        scopeBoth = "HOST AND PLAYERS",
        scopeBothMeans = "THE HOST AND EVERY PLAYER NEED IT",
        scopeUnknown = "UNKNOWN",
        scopeUnknownMeans = "THIS MOD DOESN'T SAY WHERE IT RUNS",
        -- v2 story 4: Browse (the catalog's mods for this game build) and its Details window
        browse = "BROWSE",                           -- the main window's button
        browseTitle = "BROWSE MODS",
        search = "SEARCH",                           -- the filter rows' labels
        searchHint = "TYPE TO SEARCH",
        searchTip = "WORDS IN THE NAME OR DESCRIPTION",
        category = "CATEGORY",                       -- a filter's label and a header
        show = "SHOW",
        scopeFilter = "SCOPE",
        forFilter = "FOR",
        all = "ALL",                                 -- CATEGORY and SCOPE: every one
        showAll = "ALL", showInstalled = "INSTALLED", showNotInstalled = "NOT INSTALLED", showUpdate = "UPDATE AVAILABLE",
        forGame = "THIS GAME", forReady = "READY TO RUN", forAll = "ALL BUILDS",
        stateHeader = "STATE",
        stInstalled = "INSTALLED", stUpdate = "UPDATE AVAILABLE", stConflict = "FOLDER IN USE", stAvailable = "NOT INSTALLED",
        stOtherBuild = "OTHER GAME BUILD",
        needsCore = "NEEDS NUCLEUS %s",              -- the warning icon's tooltip
        details = "DETAILS",
        refresh = "REFRESH",
        catalogUpdated = "CATALOG UPDATED %s",
        revocationsChecked = "REVOCATIONS CHECKED %s",
        justNow = "JUST NOW", hoursAgo = "%d HOURS AGO", daysAgo = "%d DAYS AGO",
        offline = "OFFLINE: SAVED CATALOG",
        checking = "CHECKING CATALOG...",
        unavailable = "CATALOG UNAVAILABLE. CHECK YOUR CONNECTION AND PRESS REFRESH.",
        refused = "CATALOG REFUSED (%s)",
        tooNew = "CATALOG NEEDS A NEWER MOD MANAGER",
        catalogError = "CATALOG ERROR",
        busy = "CATALOG BUSY",
        buildUnknown = "GAME BUILD UNKNOWN",
        noMatch = "NO MODS MATCH",
        count = "%d OF %d MODS",
        capped = "SHOWING THE FIRST %d",
        categoriesLine = "CATEGORIES: %s",           -- the Details window
        forGameLine = "FOR GAME %s (%s)",
        needLine = "NEEDS %s %s: %s",
        needsNothing = "NEEDS NOTHING ELSE",
        andMoreNeeds = "AND %d MORE",
        met = "MET", notMet = "NOT MET",
        installedLine = "INSTALLED %s", no = "NO",
        publisherLine = "PUBLISHER %s",
        licenseLine = "LICENSE %s",
        -- the 14 categories (spec-mod-manager-v2/categories.md), cat.<id>
        ["cat.gameplay"] = "GAMEPLAY", ["cat.content"] = "CONTENT", ["cat.visuals"] = "VISUALS", ["cat.audio"] = "AUDIO",
        ["cat.ui"] = "USER INTERFACE", ["cat.qol"] = "QUALITY OF LIFE", ["cat.tools"] = "UTILITIES & TOOLS",
        ["cat.library"] = "LIBRARIES & FRAMEWORKS", ["cat.performance"] = "PERFORMANCE & OPTIMIZATION",
        ["cat.multiplayer"] = "MULTIPLAYER & NETWORKING", ["cat.localization"] = "LOCALIZATION", ["cat.overhaul"] = "OVERHAULS",
        ["cat.bug-fixes"] = "BUG FIXES", ["cat.maps"] = "MAPS",
    },
}

local KIL = "/Script/Engine.Default__KismetInternationalizationLibrary"

-- The game's current language tag ("en", "zh-Hans", ...), or "en" when it can't be read. A class default object
-- (a hash hit, never a scan).
function S.language()
    local ok, lang = pcall(function()
        local kil = StaticFindObject(KIL)
        if kil == nil or not kil:IsValid() then return nil end
        local v = kil:GetCurrentLanguage()
        if type(v) == "string" then return v end
        return v:ToString()
    end)
    if ok and type(lang) == "string" and lang ~= "" and #lang <= 32 then return lang end
    return "en"
end

-- The key of tables matching tag without regard to case, or nil.
local function find(tables, tag)
    if tables[tag] then return tag end
    local lt = tag:lower()
    for k in pairs(tables) do
        if type(k) == "string" and k:lower() == lt then return k end
    end
    return nil
end

-- The language key to use for lang: the exact tag, then its prefix before "-", then "en".
function S.pick(lang, tables)
    tables = tables or S.TABLES
    if type(lang) ~= "string" or lang == "" then return "en" end
    local k = find(tables, lang)
    if k then return k end
    local prefix = lang:match("^([^-]+)%-")
    if prefix then
        k = find(tables, prefix)
        if k then return k end
    end
    return "en"
end

-- The string for key in lang (English when the language has no such key).
function S.get(key, lang, tables)
    tables = tables or S.TABLES
    local t = tables[S.pick(lang, tables)]
    local v = t and t[key]
    if type(v) == "string" then return v end
    return tables.en[key]
end

-- A string with %s/%d filled in: S.fmt(key, lang, ...). The values must already be sanitized and capped (the callers'
-- rule); a template that doesn't take them gives the bare template rather than raising.
function S.fmt(key, lang, ...)
    local t = S.get(key, lang) or key
    local ok, s = pcall(string.format, t, ...)
    return ok and s or t
end

-- A per-language table { en = ..., <lang> = ... } of one key, for core calls that pick the language themselves
-- (the menu entry's label).
function S.byLanguage(key, tables)
    tables = tables or S.TABLES
    local out = {}
    for lang, t in pairs(tables) do
        if type(t[key]) == "string" then out[lang] = t[key] end
    end
    return out
end

return S
