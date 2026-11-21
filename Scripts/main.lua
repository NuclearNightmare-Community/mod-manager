-- Mod Manager (spec-mod-manager-v1, stories 3 and 6): a MANAGE MODS entry in the title-screen menu that opens a
-- full-screen window listing every installed mod: toggle | name | version | scope | status icons | gear.
-- Story 6: the toggle turns a mod on or off for the next start (mods.txt, and a folder's enabled.txt, written at once
-- and atomically); the status slot shows another game build, dependency problems and changes pending a restart; turning
-- off a mod others need asks first; Nucleus made for another game build shows one alert; the gear's Configure window
-- changes settings through core.settings; QUIT GAME shows while changes are pending, and story 8's RESTART NOW beside it
-- when core.restart can start the game again the way it was launched (core's relaunch helper, then the same QuitGame).
-- The Mod Manager's own state is
-- Mods/ModManager/state.json. It writes only mods.txt, Mods/<Folder>/enabled.txt(.disabled) and its state.json (with
-- their .mm-tmp/.mm-bak), never a pak, and settings only through core.settings.
-- Runs on Nucleus (core) through the dependent bootstrap (core's api-contract.md) and uses only core's public API
-- (connect, core.ui, core.settings, core.restart, core.apply, core.catalog, core.log) and core's pure modules nucleus.modid,
-- nucleus.semver and nucleus.json. Holds no UObject between calls: element handles, plain tables and strings only.
-- v2 story 4: BROWSE (main window, top right) opens the Browse window: every mod the verified catalog offers for this
-- game build. The catalog is refreshed once at onReady and when the player presses REFRESH, through core.catalog
-- (core's native part fetches and verifies it); the job is polled from the game thread every 250 ms
-- (ExecuteInGameThreadWithDelay, chained), one job at a time, never on a timer. The Mod Manager reads no catalog file
-- and fetches nothing itself.
-- v2 story 5: INSTALL on an available Browse row (and in Details) works out the install set (catalog.lua installSet:
-- the mod and every dependency missing or too old), asks in a confirm window, then stages it through
-- core.catalog.stage (core downloads, verifies and opens the zips; nothing from Lua becomes a path), polls that job like a
-- refresh, starts core's apply helper (core.apply.start) and shows RESTART NOW. The Mod Manager writes no install file.
local CORE, NEED, ME = "Nucleus", ">=0.26.0", "ModManager"
local ENTRY = "manage"
local MAX_WARN_KEYS = 64     -- distinct warnings logged per session; then one line says the rest are dropped
local MAX_LOGGED_ROWS = 512  -- distinct mods whose data is logged per session
local APPMANIFEST = "appmanifest_2909110.acf" -- Steam's record of the installed build (docs/mod-manager-research.md 8.6)
local MAX_MANIFEST = 65536
local POLL_MS = 250          -- v2 story 4: the catalog job's poll interval
local MAX_POLLS = 2400       -- 10 minutes of polls: then the refresh counts as error
local MAX_LOGGED_PKGS = 512  -- distinct packages whose BROWSE pkg line is logged per session
local MAX_IDS_LOG = 2000     -- bytes of ids on a BROWSE filter line
local MAX_SET_LOG = 1000     -- v2 story 5: bytes of id@version pairs on an INSTALL ask line

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
local Catalog = require("catalog")
local Browse = require("browse")

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

-- A widget named name under w (panels and switchers by GetChildAt), depth and count bounded; nil when not found.
local FOOTER = "NN_MainFooter"
local MAX_WALK = 400
local function findWidget(w, name, depth, seen)
    local okV, valid = pcall(function() return w ~= nil and w:IsValid() end)
    if not (okV and valid) then return nil end
    seen.n = seen.n + 1
    if seen.n > MAX_WALK then return nil end
    local okN, nm = pcall(function() return w:GetFName():ToString() end)
    if okN and nm == name then return w end
    if depth <= 0 then return nil end
    local okC, n = pcall(function() return w:GetChildrenCount() end)
    if not okC or type(n) ~= "number" then return nil end
    for i = 0, math.min(n, 64) - 1 do
        local okA, c = pcall(function() return w:GetChildAt(i) end)
        local found = okA and findWidget(c, name, depth - 1, seen) or nil
        if found then return found end
    end
    return nil
end

-- The running game: version from the live title-screen menu's footer ("NUCLEAR NIGHTMARE EA V8.2.3": its last token
-- that starts with V and a digit), build from Steam's appmanifest two folders above the game's install folder (read
-- only; missing on a dev copy: unknown). Either is nil when unknown. Found fresh on every call; no UObject is kept.
local function runningGame(fs, paths)
    local version
    pcall(function()
        for _, m in ipairs(FindAllOf("MainMenu_C") or {}) do
            if m:IsValid() and m:IsInViewport() then
                -- a widget-tree child, neither a reflected property nor reachable through GetWidgetFromName (not
                -- reflected on this game): found by name in a bounded walk from the tree's root (CanvasPanel_17 holds it)
                local t = findWidget(m.WidgetTree.RootWidget, FOOTER, 4, { n = 0 })
                local s = t and t:GetText():ToString() -- no footer in this menu: try the next one
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
    local need = { "menu", "screen", "list", "row", "image", "text", "button", "checkbox", "choice", "slider", "textbox" }
    local missing = {}
    for _, k in ipairs(need) do if not (ui and type(ui[k]) == "table") then missing[#missing + 1] = k end end
    if #missing > 0 then
        log.error("%s's UI helpers lack %s. %s will not run.", CORE, table.concat(missing, ", "), ME)
        return
    end
    local settingsApi = type(core.settings) == "table" and core.settings or nil
    -- Story 8: core.restart (Nucleus 0.20.0). Missing, or a mode of nil: no RESTART NOW, QUIT GAME as before.
    local restartApi = type(core.restart) == "table" and type(core.restart.mode) == "function" and type(core.restart.start) == "function" and core.restart or nil
    -- v2 story 3: core.apply (Nucleus 0.24.0): a change staged for the next exit, applied by core's helper.
    local applyApi = type(core.apply) == "table" and type(core.apply.status) == "function" and type(core.apply.start) == "function"
        and type(core.apply.ack) == "function" and core.apply or nil
    -- v2 story 4: core.catalog (Nucleus 0.23.0). Missing: no BROWSE button (one WARN).
    local catalogApi = type(core.catalog) == "table" and type(core.catalog.refresh) == "function" and type(core.catalog.poll) == "function"
        and core.catalog or nil

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
        statusLogged = {}, nStatusLogged = 0, restartMode = nil, restartAsked = false,
        applyStaged = "none", applyResult = nil, applyShown = false }
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
    -- v2 story 3: the staged change's status (core.apply.status), or nil when it can't be read (one WARN per reason).
    local function applyStatus()
        if not applyApi then return nil end
        local okS, st, why = pcall(applyApi.status)
        if okS and type(st) == "table" then return st end
        local reason = Screen.clean(tostring(okS and why or st), 64)
        warnOnce("apply-status:" .. reason, "the staged change's status could not be read (%s)", reason)
        return nil
    end
    -- At onReady: the status once; a change staged but with no helper waiting (pending), or an apply cut short
    -- (interrupted), gets core's helper now, so the change reaches the disk however the game exits. A result is kept for
    -- the first open of the window.
    do
        local st = applyStatus()
        if st then
            session.applyStaged = st.staged
            if st.result ~= "none" then session.applyResult = st end
            log.info("APPLY status staged=%s result=%s changes=%s attempts=%s", st.staged, st.result, tostring(st.changes), tostring(st.attempts))
            if st.staged == "pending" or st.staged == "interrupted" then
                local okA, r, why = pcall(applyApi.start)
                log.info("APPLY start %s", (okA and r == true) and "ok" or Screen.clean(tostring(okA and why or r), 64))
            end
        elseif not applyApi then
            log.info("APPLY none (%s has no core.apply)", CORE)
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
        -- v2 story 3: a staged change (pending, waiting for the exit, applying or cut short) is one more pending change:
        -- the banner, QUIT GAME and RESTART NOW show for it.
        if session.applyStaged ~= "none" then pending = pending + 1 end
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
                view:openAlert(text) -- first: a key is recorded only for an alert that was shown
                log.info("ALERT nucleus-build")
                State.addSeen(session.state, key)
                if fs then saveState(fs, paths) end
                return
            end
        end
    end

    -- The data the main window shows: a scan, the restart marks of the settings, the statuses.
    local function loadRows(withSettings, fs0, paths0)
        local st = applyStatus()
        if st then
            if st.staged ~= session.applyStaged then log.info("APPLY staged %s", st.staged) end
            session.applyStaged = st.staged
        end
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
        -- Story 8: whether this game can be started again the way it was launched (asked once per session: the exe and
        -- its folder don't change while it runs).
        if not session.restartAsked then
            session.restartAsked = true
            if restartApi then
                local okM, m, why = pcall(restartApi.mode)
                session.restartMode = okM and (m == "steam" or m == "direct") and m or nil
                log.info("RESTARTMODE %s", session.restartMode or ("none (" .. Screen.clean(tostring(okM and why or m), 64) .. ")"))
            else
                log.info("RESTARTMODE none (%s has no core.restart)", CORE)
            end
        end
        view:setRestartable(session.restartMode ~= nil)
        view:setPending(session.pending)
        log.info("OPEN rows=%d total=%d lang=%s game=%s build=%s%s", #result.rows, result.total, lang, session.running.version or "-",
            session.running.build or "-", t0 and string.format(" us=%d", micros() - t0) or "")
        -- v2 story 3: the last staged change's result, on the first open of the session: the message line, then acked
        -- (core forgets it), so it shows once.
        local res = session.applyResult
        if res and not session.applyShown then
            session.applyShown = true
            local path = Screen.clean(res.path ~= "" and res.path or (res.reason ~= "" and res.reason or "-"), 128)
            local text = res.result == "applied" and fmt("applied") or res.result == "failed" and fmt("applyFailed", path) or fmt("applyDropped")
            view:setMessage(text)
            log.info("APPLY result %s reason=%s path=%s attempts=%s", res.result, Screen.clean(res.reason ~= "" and res.reason or "-", 64),
                Screen.clean(res.path ~= "" and res.path or "-", 128), tostring(res.attempts))
            local okK, r, why = pcall(applyApi.ack, res.txn)
            log.info("APPLY ack %s", (okK and r == true) and "ok" or Screen.clean(tostring(okK and why or r), 64))
        end
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
                if changed then -- put mods.txt back as it was
                    local okB, errB = Files.atomicWrite(fs, txt, old)
                    if not okB then return nil, errR .. "; mods.txt could not be put back (" .. tostring(errB) .. ")" end
                end
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
    -- Work a core callback starts runs on the game thread about 10 ms later, after the hook that called it returned. The callbacks
    -- (a checkbox's or control's onChange, a button's onClick) arrive inside core's Blueprint hook, and any ui.* work
    -- there may load an asset for the first time: the first restart icon of a session loads T_Restart, the first
    -- Configure a control kind's widget class. An asset load inside a hook stalls the engine ("Loading is stuck", VM
    -- run 2026-11-17; the first toggle froze the game, hand test 2026-11-17). So a callback only records what was
    -- clicked and calls soon; the deferred work re-checks that it still applies. With no scheduler (or one that
    -- refuses) the work runs at once. onFail runs (guarded) when fn faulted, after guard's one WARN.
    local function soon(what, fn, onFail)
        local function run()
            if not guard(what, fn) and onFail then pcall(onFail) end
        end
        if type(ExecuteInGameThreadWithDelay) == "function" and pcall(ExecuteInGameThreadWithDelay, 10, run) then return end
        run()
    end

    view.onToggle = function(n, checked)
        local r0 = view.data[n]
        local key = r0 and r0.key
        soon("the toggle", function()
            local row = view.data[n]
            if not row or row.key ~= key then -- the list changed in between: nothing written, box n shows its own row
                if row then pcall(view.setToggle, view, n, row.state ~= "off") end
                return
            end
            onToggle(n, checked)
        end, function()
            pcall(view.setToggle, view, n, not checked)
            pcall(view.setMessage, view, fmt("couldNotSave"))
        end)
    end
    view.onConfirm = function()
        local c0 = confirm
        local c
        soon("TURN OFF", function()
            if confirm ~= c0 then return end -- cancelled (BACK) or another confirm since the click: nothing written
            c = confirm
            confirm = nil
            view:closeConfirm()
            if not c then return end
            local row = view.data[c.n]
            if row and row.key == c.key then applyToggle(c.n, row, false) end
        end, function()
            if not c then return end
            pcall(view.setToggle, view, c.n, true)
            pcall(view.setMessage, view, fmt("couldNotSave"))
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

    -- ---------------------------------------------------------------- Quit and Restart now
    local function quitGame()
        local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local pc = FindFirstOf("PlayerController") -- fresh; nothing kept
        if not (ksl and ksl:IsValid() and pc and pc:IsValid()) then error("no KismetSystemLibrary or PlayerController") end
        ksl:QuitGame(pc:GetWorld(), pc, 0, false)
    end
    view.onQuit = function()
        guard("QUIT GAME", function()
            quitGame()
            log.info("QUIT pending=%d", session.pending) -- only once QuitGame returned
        end)
    end
    -- Story 8: core starts its relaunch helper (it waits for this game to exit, then starts it again the way it was
    -- launched), then the same QuitGame as QUIT GAME. "already started": a helper is already waiting, so quitting still
    -- restarts. Any other answer: the game keeps running, the message line says so, one WARN per reason.
    view.onRestart = function()
        soon("RESTART NOW", function()
            if not (restartApi and session.restartMode) then return end -- (the button is hidden then)
            local okS, res, why = pcall(restartApi.start)
            if okS and (res == true or why == "already started") then
                log.info("RESTART mode=%s pending=%d", session.restartMode, session.pending)
                quitGame()
                return
            end
            local reason = Screen.clean(tostring(okS and why or res), 64)
            warnOnce("restart:" .. reason, "RESTART NOW could not restart the game (%s); the game keeps running", reason)
            view:setMessage(fmt("cantRestart"))
        end)
    end

    -- ---------------------------------------------------------------- Configure and settings
    local cfgFolder, cfgKey
    -- The gear's click arrives inside the button's click hook: Configure is built through soon (above), after it returned.
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
    -- A control's change arrives inside its hook too: saved and redrawn through soon. Nothing is saved if Configure
    -- shows another mod by then, or setting i is another key.
    view.onSetting = function(i, value)
        local e0 = view.settings and view.settings[i]
        local key0, cfg0 = e0 and e0.key, cfgKey
        local e, saved
        soon("the setting", function()
            e = view.settings and view.settings[i]
            if not e then return end
            if cfgKey ~= cfg0 or e.key ~= key0 then -- Configure changed in between: control i shows its own entry
                pcall(view.setControl, view, i, e.value)
                return
            end
            if not (cfgFolder and settingsApi) then return end
            local okC, res, reason = pcall(settingsApi.setFor, cfgFolder, e.key, value)
            saved = okC and res == true
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
        end, function()
            if saved or not e then return end -- saved: guard's WARN only (the value stands)
            pcall(view.setControl, view, i, e.value)
            pcall(view.setCfgMessage, view, fmt("notSaved", "error"))
        end)
    end

    -- ---------------------------------------------------------------- v2 story 4: the catalog and Browse
    local browse = Browse.new(ui, S)
    -- cat.state: "checking" (a job runs) | "ok" | "copy" | "unavailable" | "refused" | "error" | "none" (no core.catalog)
    local cat = { job = nil, polls = 0, state = catalogApi and "checking" or "none", outcome = nil, decoded = nil, rows = {},
        build = nil, loggedBuild = nil }
    local pkgLogged, nPkgLogged = {}, 0

    -- The model again from the verified catalog: this game's build (the footer and the appmanifest, read fresh), the
    -- installed mods (a scan), core's version. Logs BUILD when the build changed and one BROWSE pkg line per package
    -- whose line changed (at most MAX_LOGGED_PKGS packages).
    local function buildModel()
        local d = cat.decoded
        if not d then cat.rows = {} return end
        local fs, paths = gameFs()
        session.running = runningGame(fs, paths)
        local build, from = Catalog.thisBuild(d.index, session.running)
        cat.build = build
        local b = (build or "-") .. " from=" .. from
        if cat.loggedBuild ~= b then cat.loggedBuild = b; log.info("BUILD %s", b) end
        local installed = fs and scan(fs, paths).rows or {}
        local rows, warns = Catalog.model(d.index, d.revoked, installed, type(core.version) == "string" and core.version or nil, build)
        for _, w in ipairs(warns) do warnOnce(w.key, "%s", w.msg) end
        cat.rows = rows
        for _, r in ipairs(rows) do
            local line = string.format("%s v=%s cat=%s scope=%s state=%s core=%s", r.id, Catalog.token(r.version),
                #r.categories > 0 and table.concat(r.categories, ",") or "-", r.scope, r.state, r.needsCore and "needs" or "ok")
            if pkgLogged[r.id] ~= line and (pkgLogged[r.id] or nPkgLogged < MAX_LOGGED_PKGS) then
                if not pkgLogged[r.id] then nPkgLogged = nPkgLogged + 1 end
                pkgLogged[r.id] = line
                log.info("BROWSE pkg %s", line)
            end
        end
    end
    local function browseData()
        local d = cat.decoded
        return { rows = cat.rows, total = #cat.rows, state = cat.state, outcome = cat.outcome, buildKnown = cat.build ~= nil,
            indexIssued = d and d.indexIssued, revokedIssued = d and d.revokedIssued, now = os.time() }
    end
    local function stateLog()
        local st = cat.state
        if st == "none" then return "error" end
        return st
    end

    -- A finished refresh (or a poll chain that gave up: error).
    local function finish(res)
        cat.job = nil
        local outcome = Catalog.token(type(res.outcome) == "string" and res.outcome or "error")
        local message = Catalog.clean(type(res.message) == "string" and res.message or "", 200)
        cat.outcome, cat.decoded = outcome, nil
        if outcome == "ok" then
            local d, why = Catalog.decode(res.payload)
            if d then
                cat.decoded = d
                cat.state = d.source == "copy" and "copy" or "ok"
            else
                cat.state = "error"
                warnOnce("catalog-payload", "the catalog could not be read (%s); Browse shows CATALOG ERROR", Catalog.clean(tostring(why), 200))
            end
        elseif outcome == "error" and message:find("no endpoint reachable", 1, true) then
            cat.state = "unavailable"
        elseif outcome == "error" then
            cat.state = "error"
        else
            cat.state = "refused" -- a rejection: never the saved copy (bad signed content may be an attack)
        end
        if outcome ~= "ok" then log.info("CATALOG message %s: %s", outcome, message ~= "" and message or "-") end
        buildModel()
        local d = cat.decoded
        log.info("CATALOG done outcome=%s source=%s packages=%d index_issued=%s", outcome, d and d.source or "-", #cat.rows,
            d and Catalog.token(d.indexIssued) or "-")
        if browse:isOpen() then browse:update(browseData()) end
    end

    local pollOnce
    local function pollLater()
        if type(ExecuteInGameThreadWithDelay) == "function" and pcall(ExecuteInGameThreadWithDelay, POLL_MS, pollOnce) then return end
        finish({ outcome = "error", message = "the game thread can't be scheduled" })
    end
    pollOnce = function()
        guard("the catalog poll", function()
            local job = cat.job
            if not job then return end
            cat.polls = cat.polls + 1
            local okP, st, res = pcall(catalogApi.poll, job)
            if not okP then
                warnOnce("catalog-poll", "core.catalog.poll failed: %s", Catalog.clean(tostring(st), 200))
                finish({ outcome = "error", message = "poll failed" })
                return
            end
            if st == "done" and type(res) == "table" then finish(res) return end
            -- nil, <reason> (unknown job, bad job, a call failure, an unexpected answer): the job is over, as error
            if st == nil then finish({ outcome = "error", message = Catalog.clean(tostring(res), 200) }) return end
            if cat.polls >= MAX_POLLS then finish({ outcome = "error", message = "no answer in 10 minutes" }) return end
            pollLater()
        end)
    end

    -- A refresh: at onReady and on REFRESH. One job at a time: a second ask, or core's "busy", shows CATALOG BUSY and is
    -- never retried by itself.
    local function startRefresh()
        if not catalogApi then return end
        if cat.job then
            log.info("CATALOG refresh busy")
            browse:setMessage(fmt("busy"))
            return
        end
        local okR, job, why = pcall(catalogApi.refresh)
        if okR and math.type(job) == "integer" then
            cat.job, cat.polls, cat.state = job, 0, "checking"
            log.info("CATALOG refresh job=%d", job)
            if browse:isOpen() then browse:update(browseData()) end
            pollLater()
        elseif okR and why == "busy" then
            log.info("CATALOG refresh busy")
            if cat.state == "checking" then cat.state = "error" end -- nothing of ours runs: no CHECKING forever
            if browse:isOpen() then browse:update(browseData()) end
            browse:setMessage(fmt("busy"))
        else
            local reason = Catalog.clean(tostring(okR and why or job), 64)
            log.info("CATALOG refresh error %s", reason)
            cat.state, cat.outcome, cat.decoded, cat.rows = "error", "error", nil, {}
            if browse:isOpen() then browse:update(browseData()) end
        end
    end

    local function openBrowse()
        buildModel() -- the installed mods and the build as they are now (the menu's footer is up)
        browse:open(browseData(), view.lang, layoutSize())
        log.info("BROWSE open shown=%d total=%d state=%s", browse.matched, #cat.rows, stateLog())
    end
    browse.defer = function(what, fn) soon(what, fn) end
    browse.onRefresh = function() startRefresh() end
    browse.onFiltered = function(f, _, matched, all)
        local ids, bytes = {}, 0
        for _, r in ipairs(all or {}) do
            if bytes + #r.id + 1 > MAX_IDS_LOG then ids[#ids + 1] = "..." break end
            ids[#ids + 1] = r.id
            bytes = bytes + #r.id + 1
        end
        log.info("BROWSE filter cat=%s show=%s scope=%s for=%s q=%s shown=%d ids=%s", f.cat or "all", f.show or "all", f.scope or "all",
            f["for"] or "game", table.concat(Catalog.terms(f.q), " "), matched, #ids > 0 and table.concat(ids, ",") or "-")
    end
    browse.onDetails = function(id)
        local lines, r = browse:openDetailsFor(id)
        if lines and r then log.info("DETAILS %s lines=%d", r.id, lines) end
    end

    -- ---------------------------------------------------------------- v2 story 5: INSTALL
    -- ins.ask: { id, name, set } while the confirm window asks; ins.job: the stage job while it runs; ins.staged: the ids
    -- this session staged ({ [id] = true }), shown PENDING RESTART.
    local ins = { ask = nil, job = nil, polls = 0, name = nil, staged = {} }
    local stageApi = catalogApi and type(catalogApi.stage) == "function" and catalogApi.stage or nil
    local function upper(s) return (Catalog.clean(s or "", 64):upper()) end
    local function say(text)
        browse:setMessage(text)
        view:setMessage(text)
    end
    local function setLog(set)
        local parts, bytes = {}, 0
        for _, e in ipairs(set) do
            local p = e.id .. "@" .. Catalog.token(e.version)
            if bytes + #p + 1 > MAX_SET_LOG then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = p
            bytes = bytes + #p + 1
        end
        return table.concat(parts, ",")
    end

    -- A finished stage (or a poll chain that gave up: error).
    local function installDone(res)
        ins.job = nil
        browse:setInstalling(false)
        local outcome = Catalog.token(type(res.outcome) == "string" and res.outcome or "error")
        local p = type(res.payload) == "table" and res.payload or {}
        local owners = type(p.owners) == "table" and p.owners or {}
        log.info("INSTALL done outcome=%s txn=%s owners=%d ops=%s", outcome, Catalog.token(p.txn), #owners, math.type(p.ops) == "integer" and tostring(p.ops) or "-")
        if outcome ~= "ok" then
            if type(res.message) == "string" and res.message ~= "" then log.info("INSTALL message %s: %s", outcome, Catalog.clean(res.message, 200)) end
            say(outcome == "error" and fmt("installFailed") or fmt("installRefused", outcome))
            return
        end
        for _, o in ipairs(owners) do
            local id = type(o) == "table" and type(o.id) == "string" and o.id or nil
            if id then ins.staged[id] = true end
        end
        -- core's apply helper waits for this game to exit ("already started": one waits already)
        if applyApi then
            local okA, r, why = pcall(applyApi.start)
            local started = okA and r == true
            log.info("APPLY start %s", started and "ok" or Screen.clean(tostring(okA and why or r), 64))
        else
            log.info("APPLY start none (%s has no core.apply)", CORE)
        end
        -- the status again, so the pending count (QUIT GAME, RESTART NOW) includes this change
        if view.built then refresh() else
            local st = applyStatus()
            if st then session.applyStaged = st.staged end
        end
        browse:setPending(ins.staged)
        say(fmt("installsOnRestart", ins.name or "-"))
    end

    local installPoll
    local function installLater()
        if type(ExecuteInGameThreadWithDelay) == "function" and pcall(ExecuteInGameThreadWithDelay, POLL_MS, installPoll) then return end
        installDone({ outcome = "error", message = "the game thread can't be scheduled" })
    end
    installPoll = function()
        local okG = guard("the install poll", function()
            local job = ins.job
            if not job then return end
            ins.polls = ins.polls + 1
            local okP, st, res = pcall(catalogApi.poll, job)
            if not okP then
                warnOnce("install-poll", "core.catalog.poll failed: %s", Catalog.clean(tostring(st), 200))
                installDone({ outcome = "error", message = "poll failed" })
                return
            end
            if st == "done" and type(res) == "table" then installDone(res) return end
            if st == nil then installDone({ outcome = "error", message = Catalog.clean(tostring(res), 200) }) return end
            if ins.polls >= MAX_POLLS then installDone({ outcome = "error", message = "no answer in 10 minutes" }) return end
            installLater()
        end)
        if not okG and ins.job then pcall(installDone, { outcome = "error", message = "the poll faulted" }) end
    end

    -- INSTALL on a row or in Details (after core's hook): the install set, then the confirm window, or why not.
    browse.onInstall = function(id)
        if ins.job or not stageApi then return end
        if not browse:installShown(id) then return end -- staged meanwhile, or the catalog changed
        local set, why, info = Catalog.installSet(cat.rows, id)
        if not set then
            log.info("INSTALL refuse %s reason=%s", id, Catalog.token(why))
            info = info or {}
            if why == "unsatisfiable" and info.dep then
                say(fmt("cantInstallNeeds", upper(info.name), upper(info.dep), Catalog.clean(info.need or "", 64)))
            else
                say(fmt("cantInstall", upper(info.name or id), upper(why)))
            end
            return
        end
        local target = set[#set]
        local also, bytes = {}, 0
        for i, e in ipairs(set) do
            bytes = bytes + (e.size or 0)
            if i < #set then
                also[#also + 1] = e.flag == "update" and fmt("alsoUpdate", upper(e.name), Catalog.clean(e.version, 64), Catalog.clean(e.from or "-", 64))
                    or fmt("alsoNew", upper(e.name), Catalog.clean(e.version, 64))
            end
        end
        local more = #also > Browse.INSTALL_LINES and #also - Browse.INSTALL_LINES or nil
        while #also > Browse.INSTALL_LINES do table.remove(also) end
        local size = Catalog.sizeText(bytes)
        ins.ask = { id = id, name = upper(target.name), set = set }
        log.info("INSTALL ask %s set=%s", id, setLog(set))
        browse:openInstall{ title = fmt("installTitle", upper(target.name), Catalog.clean(target.version, 64)), also = also, more = more,
            size = fmt("downloadSize", fmt(size.key, size.n)) }
    end
    -- The confirm window's INSTALL (after core's hook): the stage job, polled from the game thread.
    browse.onInstallConfirm = function()
        local a = ins.ask
        if not a then return end
        ins.ask = nil
        browse:closeInstall()
        if ins.job or not stageApi then return end
        local list = {}
        for _, e in ipairs(a.set) do list[#list + 1] = { id = e.id, version = e.version } end
        local okS, job, why = pcall(stageApi, list)
        if okS and math.type(job) == "integer" then
            ins.job, ins.polls, ins.name = job, 0, a.name
            log.info("INSTALL stage job=%d", job)
            browse:setInstalling(true)
            say(fmt("downloading", a.name))
            installLater()
            return
        end
        local reason = Catalog.clean(tostring(okS and why or job), 64)
        log.info("INSTALL stage job=%s", reason ~= "" and reason or "-")
        if okS and why == "busy" then say(fmt("busy"))
        elseif not okS or reason:find("^error") then say(fmt("installFailed"))
        else say(fmt("installRefused", reason)) end
    end
    -- Any other close of the confirm window (BACK, Escape, a parent closed): nothing is staged.
    local okIW, errIW = pcall(ui.screen.watch, function(_, info)
        if type(info) == "table" and info.id == "install" and info.event ~= "opened" and ins.ask then
            local a = ins.ask
            ins.ask = nil
            log.info("INSTALL cancel %s (%s)", a.id, tostring(info.reason or info.event))
        end
    end)
    if not okIW then warnOnce("watch-install", "the install window can't be watched: %s", tostring(errIW):match("^[^\n]*")) end
    if catalogApi and not stageApi then warnOnce("no-stage", "%s has no core.catalog.stage: Browse has no INSTALL", CORE) end
    if catalogApi then
        view.onBrowse = function() soon("Browse", openBrowse) end
        startRefresh()
    else
        warnOnce("no-catalog", "%s has no core.catalog: the main window has no BROWSE button", CORE)
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
