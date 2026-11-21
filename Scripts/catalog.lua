-- Mod Manager v2 story 4 (Browse): the verified catalog as package rows. Pure: no UE call, no file, no HTTP, no crypto.
-- The catalog comes only from core.catalog.poll's payload (core's native part fetched and verified it); nothing in it
-- ever becomes a path, a command or code: its text goes only into UI texts and log lines, cleaned and cut here.
--
--   Catalog.decode(payload) -> { source, base, indexIssued, revokedIssued, index, revoked } | nil, why
--       payload: the refresh's JSON text, or the table core.catalog.poll decoded from it. Text is decoded with
--       nucleus.json under CAPS; a table is held to the same caps. A payload that won't decode, or whose fields have
--       the wrong type, is nil, why (the caller treats it as error and logs one WARN).
--   Catalog.thisBuild(index, running) -> build | nil, "manifest" | "index" | "none"
--       running = { version, build } (main.lua's runningGame). The appmanifest build when known; else the index's
--       game_builds entry whose version equals the footer version, when exactly one matches; else unknown.
--   Catalog.model(index, revoked, installedRows, coreVersion, build) -> rows, warns, total
--       One row per kind "mod" package (base and installer are never listed), at most MAX_PACKAGES read; warns =
--       { { key, msg }, ... } (one per malformed package or version, skipped). row = { id, name, folder, description,
--       categories = { id, ... }, primary, offered = <version entry | nil>, shown = <offered, else the newest>,
--       version, scope, state = "update" | "installed" | "conflict" | "available" | "other-build", needsCore,
--       coreNeed, installedVersion, publisher, license, gameVersion, gameBuild, deps = { { id, need, name, met } } }
--   Catalog.filter(rows, f) -> shown, matched, all
--       f = { cat = <id|nil>, show = "all" | "installed" | "not-installed" | "update", scope = <scope|nil>,
--             ["for"] = "game" | "ready" | "all", q = <text> }; shown sorted by name without case, at most MAX_SHOWN;
--       matched is how many matched before the cut; all is every match, in the same order.
--   Catalog.terms(q) -> { term, ... }   the text cut to 64 characters, split on spaces, at most 8 terms, ASCII lower
--   Catalog.age(iso, nowUtc) -> { key, n } | nil   key "justNow" | "hoursAgo" | "daysAgo" (strings.lua), n the count
--   Catalog.wrap(text, width, maxLines) -> { line, ... }   words wrapped by character count; a word longer than width is
--       split; text past maxLines ends the last line with "..."
--   v2 story 5:
--   Catalog.installSet(rows, targetId) -> set | nil, reason, info
--       What INSTALL stages for a package of Catalog.model's rows: its offered version, after every dependency the
--       installed version doesn't satisfy (semver.satisfies), checked recursively (depth MAX_DEPTH, a visited set).
--       set = { { id, version, name, size, flag = "new" | "update", from = <installed version | nil> }, ... },
--       dependencies first, the target last. reason: "unsatisfiable" (no offered version meets a need, or the target
--       has none), "conflict" (the folder of the target or a dependency holds another id), "downgrade" (only a version
--       lower than the installed one is offered), "too-many" (more than MAX_SET). info = { name = <the package that
--       needs it>, dep = <the dependency's name>, need = <the need> } (dep and need for unsatisfiable and downgrade).
--   Catalog.sizeText(bytes) -> { key = "sizeKB" | "sizeMB", n }   the download size: KB (rounded up) under 1 MB, else
--       MB with one decimal (n a string, "1.5"; strings.lua)
local CORE = "Nucleus"
local J = require(CORE:lower() .. ".json")
local SV = require(CORE:lower() .. ".semver")
local MID = require(CORE:lower() .. ".modid")

local Catalog = {}

Catalog.CAPS = { maxBytes = 9437184, maxDepth = 16, maxValues = 262144, maxString = 4096 }
Catalog.MAX_PACKAGES = 512
Catalog.MAX_VERSIONS = 64
Catalog.MAX_DEPS = 32
Catalog.MAX_SHOWN = 120
Catalog.MAX_DEPTH = 8          -- dependsOn checked recursively to this depth
Catalog.MAX_QUERY = 64         -- characters of the search text
Catalog.MAX_TERMS = 8
Catalog.MAX_NAME = 64
Catalog.MAX_DESCRIPTION = 256     -- a row's displayed copy
Catalog.MAX_DESCRIPTION_KEPT = 360 -- what Details and search see (a valid description is at most 280)
Catalog.MAX_FIELD = 64         -- a version, a scope, a publisher, a license, a game version or build, in the UI
Catalog.CORE_ID = "nuclearnightmare-community.nucleus"
Catalog.MAX_SET = 16           -- v2 story 5: core.catalog.stage takes at most 16 pairs
-- The fixed category list (spec-mod-manager-v2/categories.md), in its order; strings.lua has cat.<id> for each.
Catalog.CATEGORIES = { "gameplay", "content", "visuals", "audio", "ui", "qol", "tools", "library", "performance",
    "multiplayer", "localization", "overhaul", "bug-fixes", "maps" }
Catalog.SCOPES = { "client", "host", "host-plus", "both" }
local CATEGORY, SCOPE = {}, {}
for _, c in ipairs(Catalog.CATEGORIES) do CATEGORY[c] = true end
for _, s in ipairs(Catalog.SCOPES) do SCOPE[s] = true end

-- ---------------------------------------------------------------- text
-- At most n bytes, cut on a UTF-8 boundary.
local function cutBytes(s, n)
    if #s <= n then return s end
    local i = n
    while i > 0 and (s:byte(i + 1) or 0) >= 0x80 and (s:byte(i + 1) or 0) < 0xC0 do i = i - 1 end
    return s:sub(1, i)
end
-- At most n characters (UTF-8); bytes when s isn't valid UTF-8.
local function cutChars(s, n)
    local okL, len = pcall(utf8.len, s)
    if not (okL and len) then return cutBytes(s, n) end
    if len <= n then return s end
    return s:sub(1, utf8.offset(s, n + 1) - 1)
end
Catalog.cutChars = cutChars
-- Catalog text for the UI and the log: control characters (C0, DEL, C1) as spaces, at most n characters.
local function clean(v, n)
    if type(v) ~= "string" then return "" end
    return cutChars((v:gsub("[%z\1-\31\127]", " "):gsub("\194[\128-\159]", " ")), n)
end
Catalog.clean = clean
-- An id or a short token for a log line: only printable ASCII without spaces, at most 64 bytes.
local function token(v)
    if type(v) ~= "string" then return "-" end
    local s = v:gsub("[^\33-\126]", "?"):sub(1, 64)
    return s ~= "" and s or "-"
end
Catalog.token = token
local function lowerAscii(s) return (s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)) end

-- ---------------------------------------------------------------- decode
local function isNull(v) return v == nil or v == J.null end

-- A decoded table held to CAPS: depth, values and string bytes. Returns nil or why.
local function overCaps(v)
    local values = 0
    local function walk(x, depth)
        values = values + 1
        if values > Catalog.CAPS.maxValues then return "more than " .. Catalog.CAPS.maxValues .. " values" end
        local t = type(x)
        if t == "string" then
            if #x > Catalog.CAPS.maxString then return "a string over " .. Catalog.CAPS.maxString .. " bytes" end
        elseif t == "table" and x ~= J.null then
            if depth >= Catalog.CAPS.maxDepth then return "nested deeper than " .. Catalog.CAPS.maxDepth end
            for k, e in pairs(x) do
                if type(k) == "string" and #k > Catalog.CAPS.maxString then return "a key over " .. Catalog.CAPS.maxString .. " bytes" end
                local why = walk(e, depth + 1)
                if why then return why end
            end
        end
        return nil
    end
    return walk(v, 0)
end

function Catalog.decode(payload)
    local p = payload
    if type(p) == "string" then
        local v, err = J.decode(p, Catalog.CAPS)
        if v == nil then return nil, "payload: " .. tostring(err) end
        p = v
    elseif type(p) == "table" then
        local why = overCaps(p)
        if why then return nil, "payload: " .. why end
    else
        return nil, "payload: no catalog (" .. type(p) .. ")"
    end
    if type(p) ~= "table" or J.isArray(p) then return nil, "payload: not an object" end
    if p.source ~= "network" and p.source ~= "copy" then return nil, "payload: source must be network or copy" end
    if type(p.index_issued) ~= "string" then return nil, "payload: index_issued must be a string" end
    if not isNull(p.revoked_issued) and type(p.revoked_issued) ~= "string" then return nil, "payload: revoked_issued must be a string or null" end
    local ix = p.index
    if type(ix) ~= "table" or ix == J.null or J.isArray(ix) then return nil, "payload: index must be an object" end
    if type(ix.packages) ~= "table" or ix.packages == J.null then return nil, "payload: index.packages must be an array" end
    if not isNull(ix.game_builds) and type(ix.game_builds) ~= "table" then return nil, "payload: index.game_builds must be an array" end
    local rv = p.revoked
    if not isNull(rv) then
        if type(rv) ~= "table" or J.isArray(rv) then return nil, "payload: revoked must be an object or null" end
        if not isNull(rv.revoked) and type(rv.revoked) ~= "table" then return nil, "payload: revoked.revoked must be an array" end
    else rv = nil end
    return { source = p.source, base = type(p.base) == "string" and p.base or nil, indexIssued = p.index_issued,
        revokedIssued = type(p.revoked_issued) == "string" and p.revoked_issued or nil, index = ix, revoked = rv }
end

-- ---------------------------------------------------------------- this game's build
function Catalog.thisBuild(index, running)
    running = running or {}
    if type(running.build) == "string" and running.build ~= "" then return running.build, "manifest" end
    if type(running.version) == "string" and type(index) == "table" and type(index.game_builds) == "table" and index.game_builds ~= J.null then
        local hit, n = nil, 0
        for i, g in ipairs(index.game_builds) do
            if i > Catalog.MAX_VERSIONS then break end
            if type(g) == "table" and g.version == running.version and type(g.build) == "string" and g.build:match("^%d+$") and #g.build <= 20 then
                hit, n = g.build, n + 1
            end
        end
        if n == 1 then return hit, "index" end
    end
    return nil, "none"
end

-- ---------------------------------------------------------------- the model
local function str(v) return type(v) == "string" and v or nil end

-- One version entry -> { version, build, gameVersion, scope, deps, sha256 } | nil, why.
local function readVersion(v)
    if type(v) ~= "table" or J.isArray(v) then return nil, "not an object" end
    if not SV.parse(v.version) then return nil, "version is not X.Y.Z" end
    if type(v.game) ~= "table" or type(v.game.build) ~= "string" then return nil, "game.build is missing" end
    local scope = str(v.scope)
    if scope ~= nil and not SCOPE[scope] then scope = nil end
    local deps = {}
    if not isNull(v.dependsOn) then
        if type(v.dependsOn) ~= "table" then return nil, "dependsOn is not an array" end
        for i, d in ipairs(v.dependsOn) do
            if i > Catalog.MAX_DEPS then break end
            if type(d) ~= "table" then return nil, "a dependsOn entry is not an object" end
            local id = MID.normalize(d.id)
            if not id then return nil, "a dependsOn id doesn't normalize" end
            if type(d.version) ~= "string" then return nil, "a dependsOn version is not a string" end
            deps[#deps + 1] = { id = id, need = d.version }
        end
    end
    return { version = v.version, build = v.game.build, gameVersion = str(v.game.version), scope = scope, deps = deps,
        sha256 = str(v.sha256), size = (math.type(v.size) == "integer" and v.size >= 0) and v.size or nil }
end

-- Revocation: id (normalized), version and sha256 (without case), whatever the action.
local function revokedSet(revoked)
    local set = {}
    local list = type(revoked) == "table" and revoked.revoked
    if type(list) ~= "table" or list == J.null then return set end
    for i, e in ipairs(list) do
        if i > 4096 then break end
        if type(e) == "table" then
            local id = MID.normalize(e.id)
            if id and type(e.version) == "string" and type(e.sha256) == "string" then
                set[id .. "\0" .. e.version .. "\0" .. e.sha256:lower()] = true
            end
        end
    end
    return set
end

function Catalog.model(index, revoked, installedRows, coreVersion, build)
    local warns, rows, byId = {}, {}, {}
    local function warn(key, fmt, ...) warns[#warns + 1] = { key = key, msg = string.format(fmt, ...) } end
    local rset = revokedSet(revoked)
    local pkgs = type(index) == "table" and index.packages or {}
    if type(pkgs) ~= "table" or pkgs == J.null then pkgs = {} end
    local total = 0
    for i, p in ipairs(pkgs) do
        if i > Catalog.MAX_PACKAGES then
            warn("catalog:cap", "the catalog lists more than %d packages; the rest are not read", Catalog.MAX_PACKAGES)
            break
        end
        local id = type(p) == "table" and MID.normalize(p.id) or nil
        local where = "package " .. i .. (id and (" " .. id) or "")
        if type(p) ~= "table" or not id then warn("catalog:pkg:" .. i, "catalog %s skipped: no valid id", where)
        elseif p.kind ~= "mod" then -- base and installer (and any later kind) are never listed
        elseif byId[id] then warn("catalog:dup:" .. id, "catalog %s skipped: the id is listed twice", where)
        elseif type(p.name) ~= "string" or p.name == "" then warn("catalog:pkg:" .. id, "catalog %s skipped: no name", where)
        elseif type(p.versions) ~= "table" or p.versions == J.null then warn("catalog:pkg:" .. id, "catalog %s skipped: no versions", where)
        else
            local versions = {}
            for k, v in ipairs(p.versions) do
                if k > Catalog.MAX_VERSIONS then break end
                local e, why = readVersion(v)
                if e then
                    e.revoked = e.sha256 ~= nil and rset[id .. "\0" .. e.version .. "\0" .. e.sha256:lower()] == true
                    versions[#versions + 1] = e
                else
                    warn("catalog:ver:" .. id .. ":" .. k, "catalog %s version %d skipped: %s", id, k, why)
                end
            end
            if #versions == 0 then
                warn("catalog:pkg:" .. id, "catalog %s skipped: no readable version", id)
            else
                table.sort(versions, function(a, b) return (SV.compare(a.version, b.version) or 0) > 0 end)
                local cats = {}
                if type(p.categories) == "table" and p.categories ~= J.null then
                    for _, c in ipairs(p.categories) do
                        if CATEGORY[c] and #cats < 3 then cats[#cats + 1] = c end
                    end
                end
                local name = clean(str(p.displayName) or p.name, Catalog.MAX_NAME)
                if name:match("^%s*$") then name = clean(p.name, Catalog.MAX_NAME) end
                total = total + 1
                local row = { id = id, name = name, folder = p.name, description = clean(str(p.description) or "", Catalog.MAX_DESCRIPTION_KEPT),
                    categories = cats, primary = cats[1], versions = versions, publisher = clean(str(p.publisher) or "", Catalog.MAX_FIELD),
                    license = clean(str(p.license) or "", Catalog.MAX_FIELD) }
                byId[id] = row
                rows[#rows + 1] = row
            end
        end
    end

    -- Installed versions by id (folder rows; a row without an id matches a package by folder = name, without case).
    local installedById, folders = {}, {}
    for _, r in ipairs(installedRows or {}) do
        if type(r) == "table" and type(r.folder) == "string" then
            folders[r.folder:lower()] = r
            if type(r.id) == "string" then installedById[MID.normalize(r.id) or r.id] = r end
        end
    end
    local function installedOf(row)
        local r = installedById[row.id]
        if r then return r end
        r = folders[row.folder:lower()]
        if r and r.id == nil then return r end
        return nil
    end

    -- The offered version of a package for this build: the newest one of this build, not revoked, with every
    -- dependsOn satisfiable (recursively, to MAX_DEPTH, a visited set against cycles). Results computed without
    -- running into the depth limit or a cycle are kept.
    local memo = {}
    local offered
    local function depMet(d, depth, visiting)
        local dep = byId[d.id]
        local inst = dep and installedOf(dep) or installedById[d.id]
        if inst and type(inst.version) == "string" and SV.satisfies(inst.version, d.need) then return true, false end
        if not dep then return false, false end
        local o, cut = offered(dep, depth + 1, visiting)
        return o ~= nil and SV.satisfies(o.version, d.need), cut
    end
    offered = function(row, depth, visiting)
        if memo[row.id] ~= nil then return memo[row.id] or nil, false end
        if build == nil then return nil, false end
        if depth > Catalog.MAX_DEPTH or visiting[row.id] then return nil, true end
        visiting[row.id] = true
        local pick, cut = nil, false
        for _, v in ipairs(row.versions) do
            if v.build == build and not v.revoked then
                local all = true
                for _, d in ipairs(v.deps) do
                    local met, c = depMet(d, depth, visiting)
                    cut = cut or c
                    if not met then all = false break end
                end
                if all then pick = v break end
            end
        end
        visiting[row.id] = nil
        if not cut then memo[row.id] = pick or false end
        return pick, cut
    end

    for _, row in ipairs(rows) do
        local o = offered(row, 0, {})
        row.offered = o
        row.shown = o or row.versions[1]
        local v = row.shown
        row.version = v.version
        row.scope = v.scope or "unknown"
        row.gameVersion, row.gameBuild = v.gameVersion, v.build
        local inst = installedOf(row)
        row.installedVersion = inst and (type(inst.version) == "string" and inst.version or "") or nil
        if not o then row.state = "other-build"
        elseif inst then
            local c = SV.parse(inst.version) and SV.compare(inst.version, o.version) or nil
            row.state = (c ~= nil and c < 0) and "update" or "installed"
        else
            local f = folders[row.folder:lower()]
            row.state = (f and f.id ~= nil and f.id ~= row.id) and "conflict" or "available"
        end
        row.needsCore, row.coreNeed = false, nil
        row.deps = {}
        for _, d in ipairs(v.deps) do
            local dep = byId[d.id]
            local met = depMet(d, 0, {})
            row.deps[#row.deps + 1] = { id = d.id, need = clean(d.need, Catalog.MAX_FIELD), met = met, name = dep and dep.name or nil }
            if d.id == Catalog.CORE_ID and o then
                row.coreNeed = clean(d.need, Catalog.MAX_FIELD)
                if not (type(coreVersion) == "string" and SV.satisfies(coreVersion, d.need)) then row.needsCore = true end
            end
        end
    end
    for _, row in ipairs(rows) do row.versions = nil end -- only the shown version is kept
    return rows, warns, total
end

-- ---------------------------------------------------------------- v2 story 5: the install set
function Catalog.installSet(rows, targetId)
    local byId = {}
    for _, r in ipairs(rows or {}) do if type(r) == "table" and type(r.id) == "string" then byId[r.id] = r end end
    local target = byId[targetId]
    local function nameOf(id) local r = byId[id] return r and r.name ~= "" and r.name or token(id) end
    if not target or not target.offered then return nil, "unsatisfiable", { name = nameOf(targetId) } end
    if target.state == "conflict" then return nil, "conflict", { name = target.name } end
    local function installed(r)
        local v = r and r.installedVersion
        return type(v) == "string" and v ~= "" and v or nil
    end
    local ti = installed(target)
    if ti and (SV.compare(target.offered.version, ti) or 0) < 0 then return nil, "downgrade", { name = target.name } end
    local set, chosen, visiting = {}, {}, {}
    local metByInstalled = {} -- { by, dep, need }: needs the installed version met; re-checked if that dep is chosen later
    local fail
    local function add(r)
        local inst = installed(r)
        local e = { id = r.id, version = r.offered.version, name = r.name, size = r.offered.size,
            flag = r.installedVersion ~= nil and "update" or "new", from = r.installedVersion ~= nil and (inst or "-") or nil }
        set[#set + 1] = e
        chosen[r.id] = e
    end
    local function visit(r, depth)
        if depth > Catalog.MAX_DEPTH then fail = { "unsatisfiable", { name = r.name } } return end
        visiting[r.id] = true
        for _, d in ipairs(r.offered.deps or {}) do
            local dep = byId[d.id]
            local inst = installed(dep)
            if inst and SV.satisfies(inst, d.need) then -- the installed version will do (unless a later need updates it)
                metByInstalled[#metByInstalled + 1] = { by = r.name, dep = d.id, need = d.need }
            elseif chosen[d.id] then
                if not SV.satisfies(chosen[d.id].version, d.need) then fail = { "unsatisfiable", { name = r.name, dep = nameOf(d.id), need = d.need } } end
            elseif visiting[d.id] then -- a cycle: the version being chosen must meet this need too
                if not (dep.offered and SV.satisfies(dep.offered.version, d.need)) then fail = { "unsatisfiable", { name = r.name, dep = nameOf(d.id), need = d.need } } end
            elseif not dep then
                -- not in the catalog: only an installed copy (outside it) can meet the need; model's met says whether it does
                local met = false
                for _, x in ipairs(r.deps or {}) do if x.id == d.id and x.met then met = true end end
                if not met then fail = { "unsatisfiable", { name = r.name, dep = nameOf(d.id), need = d.need } } end
            elseif dep.state == "conflict" then
                fail = { "conflict", { name = dep.name, dep = dep.name, need = d.need } }
            else
                local o = dep.offered
                local lower = inst and o and (SV.compare(o.version, inst) or 0) < 0
                if lower then fail = { "downgrade", { name = r.name, dep = dep.name, need = d.need } }
                elseif not (o and SV.satisfies(o.version, d.need)) then fail = { "unsatisfiable", { name = r.name, dep = dep.name, need = d.need } }
                else
                    visit(dep, depth + 1)
                    if not fail then add(dep) end
                end
            end
            if fail then break end
        end
        visiting[r.id] = nil
    end
    visit(target, 0)
    if fail then return nil, fail[1], fail[2] end
    add(target)
    for _, m in ipairs(metByInstalled) do
        local c = chosen[m.dep]
        if c and not SV.satisfies(c.version, m.need) then return nil, "unsatisfiable", { name = m.by, dep = nameOf(m.dep), need = m.need } end
    end
    if #set > Catalog.MAX_SET then return nil, "too-many", { name = target.name } end
    return set
end

function Catalog.sizeText(bytes)
    bytes = (math.type(bytes) == "integer" and bytes > 0) and bytes or 0
    if bytes < 1024 * 1024 then return { key = "sizeKB", n = math.max(1, (bytes + 1023) // 1024) } end
    return { key = "sizeMB", n = string.format("%.1f", bytes / (1024 * 1024)) }
end

-- ---------------------------------------------------------------- search and filters
function Catalog.terms(q)
    if type(q) ~= "string" then return {} end
    q = cutChars(q, Catalog.MAX_QUERY)
    local out = {}
    for t in q:gmatch("[^ ]+") do
        if #out >= Catalog.MAX_TERMS then break end
        out[#out + 1] = lowerAscii(t)
    end
    return out
end

local SHOW = {
    all = function() return true end,
    installed = function(st) return st == "installed" or st == "update" end,
    ["not-installed"] = function(st) return st == "available" or st == "conflict" end,
    update = function(st) return st == "update" end,
}
Catalog.SHOW = { "all", "installed", "not-installed", "update" }
Catalog.FOR = { "game", "ready", "all" }

function Catalog.filter(rows, f)
    f = f or {}
    local terms = Catalog.terms(f.q or "")
    local show = SHOW[f.show or "all"] or SHOW.all
    local forWhat = f["for"] or "game"
    local hits = {}
    for _, r in ipairs(rows or {}) do
        local keep = show(r.state)
        if keep and f.cat then
            local any = false
            for _, c in ipairs(r.categories) do if c == f.cat then any = true end end
            keep = any
        end
        if keep and f.scope then keep = r.scope == f.scope end
        if keep and forWhat ~= "all" then
            keep = r.state ~= "other-build"
            if keep and forWhat == "ready" then keep = not r.needsCore end
        end
        if keep and #terms > 0 then
            local hay = lowerAscii(r.name) .. "\n" .. lowerAscii(r.description)
            for _, t in ipairs(terms) do
                if not hay:find(t, 1, true) then keep = false break end
            end
        end
        if keep then hits[#hits + 1] = r end
    end
    table.sort(hits, function(a, b)
        local la, lb = lowerAscii(a.name), lowerAscii(b.name)
        if la ~= lb then return la < lb end
        return a.id < b.id
    end)
    local shown = {}
    for k = 1, math.min(#hits, Catalog.MAX_SHOWN) do shown[k] = hits[k] end
    return shown, #hits, hits
end

-- ---------------------------------------------------------------- ages
-- Days since 1970-01-01 for a civil date (Howard Hinnant's days_from_civil).
local function daysFromCivil(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = (y >= 0 and y or y - 399) // 400
    local yoe = y - era * 400
    local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
    local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468
end
-- "YYYY-MM-DDTHH:MM:SS[.fff]Z" -> seconds since the epoch (UTC), or nil.
function Catalog.epoch(iso)
    if type(iso) ~= "string" or #iso > 40 then return nil end
    local y, mo, d, h, mi, s = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)%.?%d*Z$")
    if not y then return nil end
    y, mo, d, h, mi, s = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)
    if mo < 1 or mo > 12 or d < 1 or d > 31 or h > 23 or mi > 59 or s > 60 then return nil end
    return daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s
end
function Catalog.age(iso, nowUtc)
    local t = Catalog.epoch(iso)
    if not t or type(nowUtc) ~= "number" then return nil end
    local d = nowUtc - t
    if d < 3600 then return { key = "justNow", n = 0 } end -- a future time too
    if d < 48 * 3600 then return { key = "hoursAgo", n = math.floor(d / 3600) } end
    return { key = "daysAgo", n = math.floor(d / 86400) }
end

-- ---------------------------------------------------------------- word wrap (the Details window)
local function chars(s)
    local okL, n = pcall(utf8.len, s)
    if okL and n then
        local out = {}
        for _, c in utf8.codes(s) do out[#out + 1] = utf8.char(c) end
        return out
    end
    local out = {}
    for i = 1, #s do out[i] = s:sub(i, i) end
    return out
end
function Catalog.wrap(text, width, maxLines)
    local lines = {}
    local words = {}
    for w in (type(text) == "string" and text or ""):gmatch("%S+") do words[#words + 1] = w end
    local cur, curLen = {}, 0
    local more = false
    local function push()
        if #lines >= maxLines then more = true return end
        lines[#lines + 1] = table.concat(cur)
        cur, curLen = {}, 0
    end
    for _, w in ipairs(words) do
        local cs = chars(w)
        while #cs > width do -- a word longer than a line: split it
            if curLen > 0 then push() end
            if more then break end
            cur, curLen = { table.concat(cs, "", 1, width) }, width
            push()
            if more then break end
            cs = { table.unpack(cs, width + 1) }
        end
        if more then break end
        if #cs > 0 then
            local need = (curLen > 0 and 1 or 0) + #cs
            if curLen + need > width then push() end
            if more then break end
            if curLen > 0 then cur[#cur + 1] = " "; curLen = curLen + 1 end
            cur[#cur + 1] = table.concat(cs)
            curLen = curLen + #cs
        end
    end
    if not more and curLen > 0 then push() end
    if more and #lines > 0 then
        local last = chars(lines[#lines])
        while #last > width - 3 do table.remove(last) end
        lines[#lines] = table.concat(last) .. "..."
    end
    return lines
end

return Catalog
