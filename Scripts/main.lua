-- Mod Manager (spec-mod-manager-v1, story 3): a MANAGE MODS entry in the title-screen menu that opens a full-screen
-- window listing every installed mod, read-only: toggle box | name | version | status | gear. The toggle box shows
-- on, off or a lock and does nothing yet; the gear opens a Configure window with the mod's details. Nothing is
-- written anywhere (writes start in story 6).
-- Runs on Nucleus (core) through the dependent bootstrap (core's api-contract.md) and uses only core's public API
-- (connect, core.ui, core.log). Holds no UObject between calls: element handles, plain tables and strings only.
local CORE, NEED, ME = "Nucleus", ">=0.12.0", "ModManager"
local ENTRY = "manage"
local MAX_WARN_KEYS = 64     -- distinct warnings logged per session; then one line says the rest are dropped
local MAX_LOGGED_ROWS = 512  -- distinct mods whose data is logged per session

local source = debug.getinfo(1, "S").source:gsub("^@", "")
local scriptDir = source:match("^(.*)[/\\]") or "."

-- ---------------------------------------------------------------- the dependent bootstrap (core's api-contract.md)
local mods = source:match("^(.*)[/\\][^/\\]+[/\\][Ss]cripts[/\\]") or "."
package.path = scriptDir .. "/?.lua;" .. package.path .. ";" .. mods .. "/" .. CORE .. "/Scripts/?.lua"
local ok, client = pcall(require, CORE:lower() .. ".client")
if not ok then print(("[%s] %s is not installed. %s will not run.\n"):format(ME, CORE, ME)) return end

local S = require("strings")
local Inv = require("inventory")
local Screen = require("screen")

-- The viewport's size in layout units (the game scales UI by the shortest side, 1080 -> 1.0, so the height is 1080
-- and a wider screen only widens the columns). 1920x1080 when it can't be read.
local function layoutSize()
    local okS, w, h = pcall(function()
        local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local pc = FindFirstOf("PlayerController")
        if not (wll and wll:IsValid() and pc and pc:IsValid()) then return nil end
        local vp, sc = wll:GetViewportSize(pc), wll:GetViewportScale(pc)
        if type(sc) ~= "number" or sc <= 0 then return nil end
        return vp.X / sc, vp.Y / sc
    end)
    local function sane(v, lo, hi) return type(v) == "number" and v == v and v >= lo and v <= hi end
    if okS and sane(w, 640, 8192) and sane(h, 480, 4096) then
        return { w = math.floor(math.max(1280, math.min(4096, w))), h = math.floor(math.max(720, math.min(4096, h))) }
    end
    return { w = 1920, h = 1080 }
end

local function start(core)
    local log = core.log
    local ui = type(core.ui) == "table" and core.ui or nil
    local need = { "menu", "screen", "list", "row", "image", "text", "button" }
    local missing = {}
    for _, k in ipairs(need) do if not (ui and type(ui[k]) == "table") then missing[#missing + 1] = k end end
    if #missing > 0 then
        log.error("%s's UI helpers lack %s. %s will not run.", CORE, table.concat(missing, ", "), ME)
        return
    end

    -- Each warning once per session (by key), at most MAX_WARN_KEYS of them.
    local warned, nWarned = {}, 0
    local function warnOnce(key, fmt, ...)
        if warned[key] then return end
        if nWarned >= MAX_WARN_KEYS then
            if not warned["#more"] then warned["#more"] = true; log.warn("more than %d different warnings; the rest are not logged", MAX_WARN_KEYS) end
            return
        end
        warned[key], nWarned = true, nWarned + 1
        log.warn(fmt, ...)
    end
    -- A callback's fault: logged once per place, with context; the screen stays usable.
    local function guard(what, fn, ...)
        local okG, err = pcall(fn, ...)
        if not okG then warnOnce("fault:" .. what, "%s failed: %s", what, tostring(err):match("^[^\n]*")) end
        return okG
    end

    local view = Screen.new(ui, S)
    local logged, nLogged = {}, 0
    local function logRows(rows)
        for i, r in ipairs(rows) do
            local line = string.format("%s | %s | %s | %s | settings=%s | need=%s | build=%s", r.folder or ("pak:" .. r.key), r.name,
                view:versionText(r), r.state, r.settings and "yes" or "no", r.need or "-", r.build or "-")
            if logged[r.key] ~= line and (logged[r.key] or nLogged < MAX_LOGGED_ROWS) then
                if not logged[r.key] then nLogged = nLogged + 1 end
                logged[r.key] = line
                log.info("MOD %d %s", i, line)
            end
        end
    end

    local function openMain()
        local micros = type(core.clock) == "table" and core.clock.micros or nil
        local t0 = micros and micros()
        local lang = S.language()
        local result
        local fs, paths = Inv.gameFs(mods)
        if fs then
            result = Inv.scan(fs, paths)
        else
            warnOnce("fs", "the game folder could not be read (%s); the list is empty", tostring(paths))
            result = { rows = {}, total = 0, warns = {} }
        end
        for _, w in ipairs(result.warns) do warnOnce(w.key, "%s", w.msg) end
        view.lang = lang -- this open's language for the MOD lines too (UNMANAGED)
        logRows(result.rows)
        view:openMain(result.rows, lang, layoutSize())
        log.info("OPEN rows=%d total=%d lang=%s%s", #result.rows, result.total, lang, t0 and string.format(" us=%d", micros() - t0) or "")
    end
    view.onGearClick = function(n)
        guard("Configure", function()
            local r = view.data[n]
            if view:openConfigure(n) then log.info("CONFIGURE %d %s", n, r and (r.folder or ("pak:" .. r.key)) or "?") end
        end)
    end

    local okE, err = pcall(ui.menu.entry, { id = ENTRY, label = S.byLanguage("manage"), style = "options",
        onClick = function() guard("the Mod Manager window", openMain) end })
    if not okE then
        log.error("could not add the menu entry: %s. %s will not run.", tostring(err):match("^[^\n]*"), ME)
        return
    end
    log.info("READY entry=%s need=%s", ENTRY, NEED)
end

client.connect{
    mod = ME, need = NEED,
    onReady = function(core)
        local okR, err = pcall(start, core)
        if not okR then print(("[%s] ERROR start failed: %s\n"):format(ME, tostring(err))) end
    end,
    -- connect has already logged the one line naming the cause (exactly one [ModManager] line). Nothing to add.
    onFail = function() end,
}
