-- Mod Manager (spec-mod-manager-v1, stories 3 and 6): a MANAGE MODS entry in the title-screen menu that opens a
-- full-screen window listing every installed mod: toggle | name | version | status icons | gear.
-- Story 6: the toggle turns a mod on or off for the next start (mods.txt, and a folder's enabled.txt, written at once
-- and atomically); the status slot shows another game build, dependency problems and changes pending a restart; turning
-- off a mod others need asks first; Nucleus made for another game build shows one alert; the gear's Configure window
-- changes settings through core.settings; QUIT GAME shows while changes are pending. The Mod Manager's own state is
-- Mods/ModManager/state.json. It writes only mods.txt, Mods/<Folder>/enabled.txt(.disabled) and its state.json (with
-- their .mm-tmp/.mm-bak), never a pak, and settings only through core.settings.
-- Runs on Nucleus (core) through the dependent bootstrap (core's api-contract.md) and uses only core's public API
-- (connect, core.ui, core.settings, core.log) and core's pure modules nucleus.modid and nucleus.semver. Holds no
-- UObject between calls: element handles, plain tables and strings only.
local CORE, NEED, ME = "Nucleus", ">=0.12.0", "ModManager"
local ENTRY = "manage"
local MAX_WARN_KEYS = 64     -- distinct warnings logged per session; then one line says the rest are dropped
local MAX_LOGGED_ROWS = 512  -- distinct mods whose data is logged per session
local APPMANIFEST = "appmanifest_2909110.acf" -- Steam's record of the installed build (docs/mod-manager-research.md 8.6)
local MAX_MANIFEST = 65536

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
local Status = require("status")
local Mt = require("modstxt")
local Files = require("files")
local State = require("state")

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

local function parentOf(p) return type(p) == "string" and p:match("^(.*)[/\\][^/\\]+$") or nil end

-- The running game: version from the live title-screen menu's footer ("NUCLEAR NIGHTMARE EA V8.2.3": its last token
-- that starts with V and a digit), build from Steam's appmanifest two folders above the game's install folder (read
-- only; missing on a dev copy: unknown). Either is nil when unknown. Found fresh on every call; no UObject is kept.
local function runningGame(fs, paths)
    local version
    pcall(function()
        for _, m in ipairs(FindAllOf("MainMenu_C") or {}) do
            if m:IsValid() and m:IsInViewport() then
                -- a widget-tree child, not a reflected property: found by name
                local t = m:GetWidgetFromName(FName("NN_MainFooter"))
                local s = t:GetText():ToString()
                if type(s) == "string" and #s <= 256 then
                    for tok in s:gmatch("%S+") do if tok:match("^V%d") then version = tok end end
                end
                if version then break end
            end
        end
    end)
    if version then version = version:gsub("[^%w%.%-_]", ""):sub(1, 32) end
    if version == "" then version = nil end
    local build
    local install = paths and parentOf(paths.game)
    local steamapps = parentOf(parentOf(install))
    if fs and steamapps then
        local okR, text = pcall(fs.readFile, steamapps .. "\\" .. APPMANIFEST, MAX_MANIFEST)
        if okR and type(text) == "string" then
            local b = text:match('"buildid"%s+"(%d+)"')
            if b and #b <= 20 then build = b end
        end
    end
    return { version = version, build = build }
end

-- A setting's value for the log: true/false, a number, or the text (control characters as spaces, at most 64 bytes).
local function valueLog(v)
    if type(v) == "boolean" then return tostring(v) end
    if math.type(v) == "integer" then return tostring(v) end
    if type(v) == "number" then return string.format("%.10g", v) end
    return Screen.clean(tostring(v), 64)
end

local function start(core)
    local log = core.log
    local ui = type(core.ui) == "table" and core.ui or nil
    local need = { "menu", "screen", "list", "row", "image", "text", "button", "checkbox", "choice", "slider" }
    local missing = {}
    for _, k in ipairs(need) do if not (ui and type(ui[k]) == "table") then missing[#missing + 1] = k end end
    if #missing > 0 then
        log.error("%s's UI helpers lack %s. %s will not run.", CORE, table.concat(missing, ", "), ME)
        return
    end
    local settingsApi = type(core.settings) == "table" and core.settings or nil

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
    local function fmt(key, ...) return S.fmt(key, view.lang, ...) end
    local session = { baseline = nil, state = State.empty(), settingsPending = {}, running = {}, status = {}, pending = 0,
        statusLogged = {}, nStatusLogged = 0 }
    local confirm -- { n, key } while the confirm window asks

    local function statePath(paths) return paths.mods .. "\\" .. Inv.SELF_FOLDER .. "\\state.json" end
    local function modsTxtPath(paths) return paths.mods .. "\\mods.txt" end

    local function gameFs()
        local fs, paths = Inv.gameFs(mods)
        if not fs then warnOnce("fs", "the game folder could not be read (%s); the list is empty", tostring(paths)) return nil end
        return fs, paths
    end
    local function scan(fs, paths)
        if not fs then fs, paths = gameFs() end
        if not fs then return { rows = {}, total = 0, warns = {} } end
        local result = Inv.scan(fs, paths)
        for _, w in ipairs(result.warns) do warnOnce(w.key, "%s", w.msg) end
        session.baseline = Status.baseline(result.rows, session.baseline)
        return result, fs, paths
    end

    -- At onReady: a write cut short between its renames is put back, then the first scan is the session's baseline
    -- (what UE4SS started), and the own state is read once.
    do
        local fs, paths = gameFs()
        if fs then
            for _, p in ipairs({ modsTxtPath(paths), statePath(paths) }) do
                local okR, done = pcall(Files.restore, fs, p)
                if okR and done then log.info("RESTORED %s from %s", Files.base(p), Files.base(p .. Files.BAK)) end
            end
            scan(fs, paths)
            local st, why = State.load(fs, statePath(paths))
            session.state = st
            if why then warnOnce("state", "Mods/%s/state.json %s; starting from an empty state (rewritten on the next save)", Inv.SELF_FOLDER, why) end
        end
    end
    local function saveState(fs, paths)
        local okS, err = State.save(fs, statePath(paths), session.state)
        if not okS then warnOnce("state-save:" .. tostring(err), "Mods/%s/state.json could not be saved: %s", Inv.SELF_FOLDER, tostring(err)) end
        return okS
    end

    -- Whether any of a mod's settings waits for a restart (core.settings.describe).
    local function describe(folder)
        if not settingsApi then return nil end
        local okD, d, err = pcall(settingsApi.describe, folder)
        if not okD then warnOnce("describe:" .. folder, "the settings of %s could not be read: %s", folder, tostring(d):match("^[^\n]*")) return nil end
        if type(d) ~= "table" or type(d.settings) ~= "table" then
            if err and not tostring(err):match("^no%-settings") then warnOnce("describe:" .. folder, "the settings of %s could not be read: %s", folder, tostring(err)) end
            return nil
        end
        local list = {}
        for i, e in ipairs(d.settings) do
            if i > Screen.MAX_SETTINGS then break end
            if type(e) == "table" and type(e.key) == "string" then list[#list + 1] = e end
        end
        return list
    end
    local function anyPending(list)
        for _, e in ipairs(list or {}) do if e.pendingRestart then return true end end
        return false
    end

    -- Statuses for the current rows: icons, tooltips and lines on each row (row.st), the pending count, and one
    -- STATUS line per row whenever its status changes.
    local function computeStatus(rows)
        local st = Status.compute(rows, { baseline = session.baseline, running = session.running,
            settingsPending = session.settingsPending, fmt = fmt })
        local pending = 0
        for _, r in ipairs(rows) do
            r.st = st[r.key]
            if r.st.pending then pending = pending + 1 end
            local text = Status.logText(r.st)
            local id = r.folder or ("pak:" .. r.key)
            if session.statusLogged[r.key] ~= text and (session.statusLogged[r.key] or session.nStatusLogged < MAX_LOGGED_ROWS) then
                if not session.statusLogged[r.key] then session.nStatusLogged = session.nStatusLogged + 1 end
                session.statusLogged[r.key] = text
                log.info("STATUS %s %s", id, text)
            end
        end
        session.pending = pending
        return pending
    end

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

    -- Nucleus made for another game build: one alert, once per key ever (state "seen").
    local function maybeAlert(rows, fs, paths)
        for _, r in ipairs(rows) do
            if r.folder and r.key == Inv.CORE_FOLDER:lower() then
                local isBuild = false
                for _, k in ipairs(r.st and r.st.kinds or {}) do if k == "build" then isBuild = true end end
                if not isBuild then return end
                local key = Status.alertKey(r, session.running)
                if State.hasSeen(session.state, key) then return end
                local function at(v, b) return fmt("gameAt", Screen.clean(v or "-", 64), Screen.clean(b or "-", 64)) end
                local text = fmt("alert", Screen.clean(r.version or "-", 64), at(r.gameVersion, r.gameBuild), at(session.running.version, session.running.build))
                State.addSeen(session.state, key)
                if fs then saveState(fs, paths) end
                view:openAlert(text)
                log.info("ALERT nucleus-build")
                return
            end
        end
    end

    -- The data the main window shows: a scan, the restart marks of the settings, the statuses.
    local function loadRows(withSettings, fs0, paths0)
        local result, fs, paths = scan(fs0, paths0)
        if withSettings then
            for _, r in ipairs(result.rows) do
                if r.folder and r.settings then session.settingsPending[r.key] = anyPending(describe(r.folder)) or nil end
            end
        end
        computeStatus(result.rows)
        return result, fs, paths
    end

    local function openMain()
        local micros = type(core.clock) == "table" and core.clock.micros or nil
        local t0 = micros and micros()
        local lang = S.language()
        view.lang = lang -- this open's language for the MOD and STATUS lines too
        local fs0, paths0 = gameFs()
        session.running = runningGame(fs0, paths0)
        local result, fs, paths = loadRows(true, fs0, paths0)
        logRows(result.rows)
        view.message = nil
        view:openMain(result.rows, lang, layoutSize())
        view:setPending(session.pending)
        log.info("OPEN rows=%d total=%d lang=%s game=%s build=%s%s", #result.rows, result.total, lang, session.running.version or "-",
            session.running.build or "-", t0 and string.format(" us=%d", micros() - t0) or "")
        maybeAlert(result.rows, fs, paths)
    end

    -- After a write or a setting: rescan, refresh the rows and statuses in place.
    local function refresh()
        local result = loadRows(false)
        view:refresh(result.rows)
        view:setPending(session.pending)
        return result
    end

    -- ---------------------------------------------------------------- on/off
    -- Writes row's new state: mods.txt (every line of the folder to 1 or 0; on with no line: one inserted above
    -- Keybinds), and off: enabled.txt renamed to enabled.txt.disabled. true | nil, err; on a failure nothing stays
    -- written.
    local function writeToggle(fs, paths, row, on)
        if not Inv.validName(row.folder) then return nil, "not a mod folder" end
        local txt = modsTxtPath(paths)
        local old, err = fs.readFile(txt, Mt.MAX)
        if not old then return nil, "reading mods.txt: " .. tostring(err) end
        local model, perr = Mt.parse(old)
        if not model then return nil, "mods.txt: " .. tostring(perr) end
        local changed = Mt.set(model, row.folder, on)
        local new, serr = Mt.serialize(model)
        if not new then return nil, "mods.txt: " .. tostring(serr) end
        if changed then
            local okW, errW = Files.atomicWrite(fs, txt, new)
            if not okW then return nil, errW end
        end
        if not on and row.enabledTxt then
            local e = paths.mods .. "\\" .. row.folder .. "\\enabled.txt"
            local okR, errR = Files.renameAside(fs, e, e .. ".disabled")
            if not okR then
                if changed then Files.atomicWrite(fs, txt, old) end -- put mods.txt back as it was
                return nil, errR
            end
        end
        return true
    end

    local function failToggle(n, row, on, why)
        pcall(view.setToggle, view, n, not on)
        warnOnce("toggle:" .. tostring(row and row.folder) .. ":" .. tostring(why), "could not turn %s %s: %s", tostring(row and row.folder), on and "on" or "off", tostring(why))
        view:setMessage(fmt("couldNotSave"))
    end

    local function applyToggle(n, row, on)
        local fs, paths = gameFs()
        if not fs then failToggle(n, row, on, "the game folder could not be read") return end
        local okW, err = writeToggle(fs, paths, row, on)
        if not okW then failToggle(n, row, on, err) return end
        State.setOff(session.state, row.folder, not on)
        saveState(fs, paths)
        view:setMessage(nil)
        log.info("TOGGLE %s %s", row.folder, on and "on" or "off")
        refresh()
    end

    local function onToggle(n, checked)
        local row = view.data[n]
        if not row or Screen.toggleKind(row) ~= "box" then
            if row then view:setToggle(n, row.state ~= "off") end
            return
        end
        if checked == Status.isOn(row) then return end
        if not checked then
            local deps = Status.dependents(view.data, row)
            if #deps > 0 then
                confirm = { n = n, key = row.key }
                view:openConfirm(fmt("confirm", Screen.clean(row.name, 64), Status.confirmNames(deps, fmt)))
                log.info("CONFIRM %s needed by %d", row.folder, #deps)
                return
            end
        end
        applyToggle(n, row, checked)
    end
    view.onToggle = function(n, checked)
        local okT = guard("the toggle", onToggle, n, checked)
        if not okT then
            pcall(view.setToggle, view, n, not checked)
            pcall(view.setMessage, view, fmt("couldNotSave"))
        end
    end
    view.onConfirm = function()
        guard("TURN OFF", function()
            local c = confirm
            confirm = nil
            view:closeConfirm()
            if not c then return end
            local row = view.data[c.n]
            if row and row.key == c.key then applyToggle(c.n, row, false) end
        end)
    end
    -- Any other close of the confirm window (BACK, Escape, a parent closed, the menu lost): the box goes back, nothing
    -- is written.
    local okW, errW = pcall(ui.screen.watch, function(_, info)
        if type(info) == "table" and info.id == "confirm" and info.event ~= "opened" and confirm then
            local c = confirm
            confirm = nil
            local row = view.data[c.n]
            pcall(view.setToggle, view, c.n, true)
            log.info("CONFIRM %s cancelled (%s)", row and row.folder or "?", tostring(info.reason or info.event))
        end
    end)
    if not okW then warnOnce("watch", "the confirm window can't be watched: %s", tostring(errW):match("^[^\n]*")) end

    -- ---------------------------------------------------------------- Quit
    view.onQuit = function()
        guard("QUIT GAME", function()
            log.info("QUIT pending=%d", session.pending)
            local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
            local pc = FindFirstOf("PlayerController") -- fresh; nothing kept
            if not (ksl and ksl:IsValid() and pc and pc:IsValid()) then error("no KismetSystemLibrary or PlayerController") end
            ksl:QuitGame(pc:GetWorld(), pc, 0, false)
        end)
    end

    -- ---------------------------------------------------------------- Configure and settings
    local cfgFolder, cfgKey
    -- The gear's click arrives inside the button's click hook. Configure may create a control kind for the first time
    -- (core loads its widget class then), and an asset load inside a hook stalls the engine ("Loading is stuck",
    -- VM run 2026-11-17): so the window is built on the next game-thread tick, outside the hook.
    local function soon(what, fn)
        if type(ExecuteInGameThreadWithDelay) == "function" and pcall(ExecuteInGameThreadWithDelay, 10, function() guard(what, fn) end) then return end
        guard(what, fn)
    end
    view.onGearClick = function(n)
        local r0 = view.data[n]
        local key = r0 and r0.key
        soon("Configure", function()
            local r = view.data[n]
            if not r or r.key ~= key then return end -- the list changed in between: nothing opens
            local list = (r.folder and r.settings) and describe(r.folder) or {}
            cfgFolder, cfgKey = r.folder, r.key
            if view:openConfigure(n, list or {}) then log.info("CONFIGURE %d %s", n, r.folder or ("pak:" .. r.key)) end
        end)
    end
    view.onSetting = function(i, value)
        guard("the setting", function()
            local e = view.settings and view.settings[i]
            if not (e and cfgFolder and settingsApi) then return end
            local okC, res, reason = pcall(settingsApi.setFor, cfgFolder, e.key, value)
            if okC and res == true then
                log.info("SET %s %s=%s", cfgFolder, e.key, valueLog(value))
                local list = describe(cfgFolder) or {}
                session.settingsPending[cfgKey] = anyPending(list) or nil
                view:fillSettings(list)
                view:setCfgMessage(nil)
                refresh()
                local n = view.cfgRow
                local row = n and view.data[n]
                if row and row.key == cfgKey then view:setConfigureProblems(row.st and row.st.lines or {}) end
            else
                local why = okC and tostring(reason) or tostring(res)
                local code = okC and (why:match("^([%w%-]+)") or "refused") or "error"
                pcall(view.setControl, view, i, e.value)
                view:setCfgMessage(fmt("notSaved", code))
                warnOnce("set:" .. cfgFolder .. ":" .. e.key .. ":" .. code, "SET %s %s not saved: %s", cfgFolder, e.key, why:match("^[^\n]*"))
            end
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
