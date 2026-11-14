-- Mod Manager story 3: every string the player sees, per language, and the picker. The rule is core's
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
