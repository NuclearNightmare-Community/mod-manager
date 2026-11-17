-- Mod Manager story 6: what each row's status slot shows, and who depends on whom. Pure: rows from inventory.lua, the
-- running game, the session baseline and the settings' restart marks in; icons, tooltips and lines out.
--
--   Status.isOn(row) -> boolean                    on or locked
--   Status.baseline(rows[, into]) -> { [key] = on } each folder row's on/off at the first scan (what UE4SS started);
--                                                   rows first seen later are added as they are
--   Status.compute(rows, ctx) -> { [key] = st }     ctx = { baseline, running = { version, build }, settingsPending =
--                                                   { [key] = true }, fmt = function(key, ...) -> string }
--     st = { kinds = { "build" | "dep" | "restart", ... } (in that order), tips = { build =, dep =, restart = },
--            lines = { <every problem line, in order> }, pending = "on" | "off" | "setting" | nil }
--   Status.dependents(rows, row) -> { name, ... }   other folder rows that are on and list row's id in dependsOn
--   Status.confirmNames(names, fmt) -> text          at most 5 names, then "AND <n> MORE"
--   Status.alertKey(nucleusRow, running) -> key
--   Status.cut(s, max) -> s                          at most max bytes, on a UTF-8 boundary
--
-- Pak-only rows never get an icon. Nothing here turns anything off: the slot flags, it never acts.
local Status = {}

local CORE_FOLDER = "Nucleus"
local SV = require(CORE_FOLDER:lower() .. ".semver") -- core's pure semver module (nucleus.semver), as modid in inventory.lua

Status.MAX_TIP = 512     -- core's tooltip cap (bytes)
Status.MAX_SHOWN = 64    -- an id or a version inside a text (bytes)
Status.MAX_CONFIRM_NAMES = 5

function Status.cut(s, max)
    s = tostring(s)
    if #s <= max then return s end
    local i = max
    -- back off continuation bytes so the cut never splits a character
    while i > 0 and (s:byte(i + 1) or 0) >= 0x80 and (s:byte(i + 1) or 0) < 0xC0 do i = i - 1 end
    return s:sub(1, i)
end

-- A value inside a text: control characters as spaces, at most MAX_SHOWN bytes.
local function shown(v) return Status.cut((tostring(v):gsub("[%z\1-\31\127]", " ")), Status.MAX_SHOWN) end

function Status.isOn(row) return row.state ~= "off" end

function Status.baseline(rows, into)
    local b = into or {}
    for _, r in ipairs(rows) do
        if r.folder and b[r.key] == nil then b[r.key] = Status.isOn(r) end
    end
    return b
end

local function buildTip(row, running, fmt)
    local rv, rb = running and running.version, running and running.build
    local mv, mb = row.gameVersion, row.gameBuild
    local differs
    if mb and rb then differs = mb ~= rb
    elseif mv and rv then differs = mv ~= rv
    else return nil end
    if not differs then return nil end
    return fmt("madeFor", shown(mv or "-"), shown(mb or "-"), shown(rv or "-"), shown(rb or "-"))
end

local function byIdOf(rows)
    local byId = {}
    for _, r in ipairs(rows) do
        if r.folder and r.id and not byId[r.id] then byId[r.id] = r end
    end
    return byId
end

local function depLines(row, byId, fmt)
    local out = {}
    for _, d in ipairs(row.deps or {}) do
        if d.id ~= row.id then
            local t = byId[d.id]
            if not t then
                out[#out + 1] = fmt("needsMissing", shown(d.id))
            elseif not Status.isOn(t) then
                out[#out + 1] = fmt("needsOff", shown(t.name))
            elseif d.need and not (t.version and SV.check(t.version, d.need)) then
                out[#out + 1] = fmt("needsVersion", shown(t.name), shown(d.need), shown(t.version or "-"))
            end
        end
    end
    return out
end

local function tip(lines) return Status.cut(table.concat(lines, "\n"), Status.MAX_TIP) end

function Status.compute(rows, ctx)
    local fmt = ctx.fmt
    local byId = byIdOf(rows)
    local out = {}
    for _, row in ipairs(rows) do
        local st = { kinds = {}, tips = {}, lines = {} }
        if row.folder then
            local b = buildTip(row, ctx.running, fmt)
            if b then
                st.kinds[#st.kinds + 1] = "build"; st.tips.build = tip({ b }); st.lines[#st.lines + 1] = b
            end
            local d = depLines(row, byId, fmt)
            if #d > 0 then
                st.kinds[#st.kinds + 1] = "dep"; st.tips.dep = tip(d)
                for _, l in ipairs(d) do st.lines[#st.lines + 1] = l end
            end
            local r = {}
            local base = ctx.baseline and ctx.baseline[row.key]
            if base ~= nil and base ~= Status.isOn(row) then
                st.pending = Status.isOn(row) and "on" or "off"
                r[#r + 1] = fmt(st.pending == "on" and "turnsOn" or "turnsOff")
            end
            if ctx.settingsPending and ctx.settingsPending[row.key] then
                st.pending = st.pending or "setting"
                r[#r + 1] = fmt("settingRestart")
            end
            if #r > 0 then
                st.kinds[#st.kinds + 1] = "restart"; st.tips.restart = tip(r)
                for _, l in ipairs(r) do st.lines[#st.lines + 1] = l end
            end
        end
        out[row.key] = st
    end
    return out
end

-- The one-line log form: "<build,dep,restart | none> | <lines joined with ' / '>".
function Status.logText(st)
    local kinds = #st.kinds > 0 and table.concat(st.kinds, ",") or "none"
    return kinds .. " | " .. table.concat(st.lines, " / ")
end

function Status.dependents(rows, row)
    local names = {}
    if not row.id then return names end
    for _, r in ipairs(rows) do
        if r ~= row and r.folder and Status.isOn(r) then
            for _, d in ipairs(r.deps or {}) do
                if d.id == row.id then names[#names + 1] = r.name break end
            end
        end
    end
    return names
end

function Status.confirmNames(names, fmt)
    local shownNames = {}
    for i = 1, math.min(#names, Status.MAX_CONFIRM_NAMES) do shownNames[i] = shown(names[i]) end
    local text = table.concat(shownNames, ", ")
    if #names > Status.MAX_CONFIRM_NAMES then text = fmt("andMore", text, #names - Status.MAX_CONFIRM_NAMES) end
    return text
end

function Status.alertKey(nucleusRow, running)
    local r = running and (running.build or running.version) or "-"
    local key = "nucleus-build " .. tostring(nucleusRow.version or "-") .. " " .. tostring(r)
    return Status.cut((key:gsub("[^\32-\126]", "?")), 128)
end

return Status
