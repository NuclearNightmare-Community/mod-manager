-- Mod Manager v2 story 4: the Browse window (every mod the verified catalog offers for this game build, with search,
-- four filters and the catalog's age) and its Details window, through core.ui only (Nucleus >= 0.25.0: textbox).
--
--   local b = Browse.new(ui, strings)
--   b:open(data, lang, size)      opens Browse on top (filters and search reset); data below; size as screen.lua's
--   b:update(data)                new catalog data into the open window (a refresh that finished while it is open)
--   b:setMessage(text | nil)      the status line's message (CATALOG BUSY) until the next update or open
--   b:isOpen() -> boolean
--   b:openDetails(n) -> lines | nil   the Details window for shown row n, on top; lines = its description lines
--   b.filters -> { cat, show, scope, for, q }   the current filter (Catalog.filter's f)
--   b.shown, b.matched            the rows shown now (at most Catalog.MAX_SHOWN) and how many matched
-- data = { rows = Catalog.model's rows, total, state = "checking" | "ok" | "copy" | "unavailable" | "refused" |
--          "error" | "none", outcome, buildKnown, indexIssued, revokedIssued, now = <UTC seconds> }
-- Callbacks the caller sets: onFiltered(filters, shown, matched, all) after every fill (open, a filter, a search change,
-- an update), onRefresh() (REFRESH), onDetails(n) (a row's DETAILS; default: openDetails), defer(what, fn) (core calls
-- a control's onChange and a button's onClick inside its Blueprint hook, where no ui work may run: the caller runs fn
-- after the hook returned; default: at once).
--
-- Layout: the title, the filter list (five one-control rows: SEARCH, CATEGORY, SHOW, SCOPE, FOR, so the keys and the
-- gamepad reach each control: Up / Down between rows, Left / Right step a choice), the age line, the status line, the
-- header list and the list stack in the card's top-left corner; REFRESH and the count line in its bottom-right; BACK is
-- core's. Each package is two list rows: name | category | version | scope icon | state | warning | DETAILS, then its
-- description in the small font. Rows are made as first needed and hidden past the count, never removed. The Details
-- window stacks its texts (nothing clickable but BACK).
local Screen = require("screen")
local Catalog = require("catalog")

local Browse = {}
Browse.__index = Browse

Browse.ICON = Screen.ICON
Browse.FILTER_ROWS = 5
Browse.FILTER_H = 236        -- the filter list's height (five rows)
Browse.HEADER_H = 56
-- Taken from the layout height for everything but the list (title, filter list, age and status lines, header, gaps,
-- BACK and the bottom-right stack, the card's chrome): at 1080 the list is 280 high and scrolls.
Browse.RESERVE = 800
Browse.LIST_MIN = 160
Browse.FILL = { name = 4, cat = 2, ver = 1, st = 2 }
Browse.FILTER_FILL = { label = 1, control = 3 }
Browse.SEARCH_W = 480
Browse.DESC_LINES, Browse.DESC_WIDTH = 5, 72
Browse.DEP_LINES = 4
Browse.DETAILS_ICON = { game = "/Game/HexTree/Textures/T_Question.T_Question" } -- allow-listed by core (UI-10)
local STATE_KEY = { update = "stUpdate", installed = "stInstalled", conflict = "stConflict", available = "stAvailable",
    ["other-build"] = "stOtherBuild" }
local SHOW_KEY = { "showAll", "showInstalled", "showNotInstalled", "showUpdate" }
local FOR_KEY = { "forGame", "forReady", "forAll" }

function Browse.new(ui, strings)
    return setmetatable({ ui = ui, S = strings, lang = "en", made = 0, cells = {}, data = { rows = {}, state = "none" },
        shown = {}, matched = 0, filters = { show = "all", ["for"] = "game", q = "" }, message = nil }, Browse)
end

function Browse:str(key) return self.S.get(key, self.lang) end
function Browse:fmt(key, ...)
    local ok, s = pcall(string.format, self:str(key), ...)
    return ok and s or self:str(key)
end
local cut = Screen.cut
local function later(self, what, fn)
    if self.defer then self.defer(what, fn) else fn() end
end

-- The options of each filter (labels in the current language).
function Browse:catOptions()
    local o = { self:str("all") }
    for _, c in ipairs(Catalog.CATEGORIES) do o[#o + 1] = self:str("cat." .. c) end
    return o
end
function Browse:showOptions() local o = {} for i, k in ipairs(SHOW_KEY) do o[i] = self:str(k) end return o end
function Browse:scopeOptions()
    local o = { self:str("all") }
    for _, s in ipairs(Catalog.SCOPES) do o[#o + 1] = self:str("scope" .. Screen.SCOPE_KEY[s]) end
    return o
end
function Browse:forOptions() local o = {} for i, k in ipairs(FOR_KEY) do o[i] = self:str(k) end return o end

function Browse.listSize(size)
    size = size or { w = 1920, h = 1080 }
    return { w = size.w - Screen.SIDE_RESERVE, h = math.max(Browse.LIST_MIN, size.h - Browse.RESERVE) }
end

-- ---------------------------------------------------------------- the window, once
function Browse:build(size)
    local ui = self.ui
    local win = self.win
    local function tl(gap) return { screen = win, corner = "top-left", gap = gap or "normal" } end
    local ls = Browse.listSize(size)
    self.size = { w = size.w, h = size.h }
    self.title = ui.text.create{ id = "bw.title", text = self:str("browseTitle"), place = tl(), style = { font = "title" } }
    self.flist = ui.list.create{ id = "bw.flist", size = { w = ls.w, h = Browse.FILTER_H }, place = tl() }
    local function frow(k, label)
        local r = ui.row.create{ id = "bw.f" .. k, place = { list = self.flist } }
        local t = ui.text.create{ id = "bw.f" .. k .. ".l", text = label, place = { row = r, fill = Browse.FILTER_FILL.label }, style = { font = "body", overflow = "ellipsis" } }
        return r, t
    end
    local place = function(r) return { row = r, fill = Browse.FILTER_FILL.control } end
    local r1
    r1, self.qLabel = frow(1, self:str("search"))
    self.q = ui.textbox.create{ id = "bw.q", text = "", hint = self:str("searchHint"), width = Browse.SEARCH_W, maxChars = Catalog.MAX_QUERY,
        place = place(r1), tooltip = self:str("searchTip"),
        onChange = function(_, text) self:onSearch(text) end, onCommit = function(_, text) self:onSearch(text) end }
    local r2
    r2, self.catLabel = frow(2, self:str("category"))
    self.cat = ui.choice.create{ id = "bw.cat", options = self:catOptions(), selected = 1, place = place(r2),
        onChange = function(_, i) self:onChoice("cat", i) end }
    local r3
    r3, self.showLabel = frow(3, self:str("show"))
    self.show = ui.choice.create{ id = "bw.show", options = self:showOptions(), selected = 1, place = place(r3),
        onChange = function(_, i) self:onChoice("show", i) end }
    local r4
    r4, self.scopeLabel = frow(4, self:str("scopeFilter"))
    self.scope = ui.choice.create{ id = "bw.scope", options = self:scopeOptions(), selected = 1, place = place(r4),
        onChange = function(_, i) self:onChoice("scope", i) end }
    local r5
    r5, self.forLabel = frow(5, self:str("forFilter"))
    self.forC = ui.choice.create{ id = "bw.for", options = self:forOptions(), selected = 1, place = place(r5),
        onChange = function(_, i) self:onChoice("for", i) end }
    self.age = ui.text.create{ id = "bw.age", text = "", place = tl(), style = { font = "small" } }
    ui.text.setVisible(self.age, false)
    self.status = ui.text.create{ id = "bw.status", text = "", place = tl(), style = { font = "body" } }
    ui.text.setVisible(self.status, false)
    self.shownEl = { age = false, status = false }
    self.texts = { age = "", status = "" }
    self.hlist = ui.list.create{ id = "bw.hlist", size = { w = ls.w, h = Browse.HEADER_H }, place = tl() }
    local hdr = ui.row.create{ id = "bw.hdr", place = { list = self.hlist } }
    self.hName = ui.text.create{ id = "bw.h.name", text = self:str("name"), place = { row = hdr, fill = Browse.FILL.name }, style = { font = "body", overflow = "ellipsis" } }
    self.hCat = ui.text.create{ id = "bw.h.cat", text = self:str("category"), place = { row = hdr, fill = Browse.FILL.cat }, style = { font = "body", overflow = "ellipsis" } }
    self.hVer = ui.text.create{ id = "bw.h.ver", text = self:str("version"), place = { row = hdr, fill = Browse.FILL.ver }, style = { font = "body", overflow = "ellipsis" } }
    ui.image.create{ id = "bw.h.sc", place = { row = hdr }, size = Browse.ICON }
    self.hSt = ui.text.create{ id = "bw.h.st", text = self:str("stateHeader"), place = { row = hdr, fill = Browse.FILL.st }, style = { font = "body", overflow = "ellipsis" } }
    ui.image.create{ id = "bw.h.w", place = { row = hdr }, size = Browse.ICON }
    ui.image.create{ id = "bw.h.det", place = { row = hdr }, size = Browse.ICON }
    self.listSz = ls
    self.list = ui.list.create{ id = "bw.list", size = ls, place = tl("tight") }
    local function br() return { screen = win, corner = "bottom-right", gap = "normal" } end
    self.refreshSpec = { id = "bw.refresh", label = self:str("refresh"), place = br(),
        onClick = function() later(self, "REFRESH", function() if self.onRefresh then self.onRefresh() end end) end }
    self.refreshBtn = ui.button.create(self.refreshSpec)
    self.count = ui.text.create{ id = "bw.count", text = "", place = br(), style = { font = "body" } }
    self.countText = ""
end

-- Row n's elements (two list rows, made once).
function Browse:makeRow(n)
    local ui = self.ui
    local p = "bw.r" .. n
    local row = ui.row.create{ id = p, place = { list = self.list } }
    local c = { row = row, visible = true, name = "", cat = "", ver = "", st = "", scope = "unknown", scopeTip = "", warn = false, warnTip = nil, desc = "" }
    local function txt(part, fill) return ui.text.create{ id = p .. "." .. part, text = "", place = { row = row, fill = fill }, style = { font = "body", overflow = "ellipsis" } } end
    c.nameH = txt("name", Browse.FILL.name)
    c.catH = txt("cat", Browse.FILL.cat)
    c.verH = txt("ver", Browse.FILL.ver)
    c.scopeTip = self:scopeTip("unknown")
    c.sc = ui.image.create{ id = p .. ".sc", place = { row = row }, image = { icon = "scope-unknown" }, size = Browse.ICON, tooltip = c.scopeTip }
    c.stH = txt("st", Browse.FILL.st)
    c.w = ui.image.create{ id = p .. ".w", place = { row = row }, size = Browse.ICON }
    c.det = ui.button.create{ id = p .. ".det", place = { row = row }, icon = Browse.DETAILS_ICON, iconSize = Browse.ICON,
        tooltip = self:str("details"), onClick = function() later(self, "DETAILS", function() self:onDetailsClick(n) end) end }
    local d = "bw.d" .. n
    c.drow = ui.row.create{ id = d, place = { list = self.list } }
    c.descH = ui.text.create{ id = d .. ".text", text = "", place = { row = c.drow, fill = 1 }, style = { font = "small", overflow = "ellipsis" } }
    self.cells[n] = c
    self.made = n
    return c
end

-- screen.lua's scope words and RUNS ON line (they need only str).
Browse.scopeWords, Browse.scopeLine = Screen.scopeWords, Screen.scopeLine
function Browse:scopeTip(scope)
    local part = Screen.SCOPE_KEY[scope] or "Unknown"
    return self:str("scope" .. part) .. " - " .. self:str("scope" .. part .. "Means")
end

-- ---------------------------------------------------------------- filling
local function ageText(self, iso, now)
    local a = Catalog.age(iso, now)
    if not a then return self:str("unknown") end
    if a.key == "justNow" then return self:str("justNow") end
    return self:fmt(a.key, a.n)
end

-- The status line for the current data: nil when there is nothing to say.
function Browse:statusText()
    if self.message then return self.message end
    local d = self.data
    local st = d.state
    if st == "checking" then return self:str("checking") end
    if st == "unavailable" then return self:str("unavailable") end
    if st == "refused" then
        if d.outcome == "schema-too-new" then return self:str("tooNew") end
        return self:fmt("refused", Catalog.token(d.outcome))
    end
    if st == "error" then return self:str("catalogError") end
    if st == "ok" or st == "copy" then
        if not d.buildKnown then return self:str("buildUnknown") end
        if self.matched == 0 then return self:str("noMatch") end
        return nil
    end
    return self:str("catalogError") -- none: no refresh has run (core.catalog missing)
end

function Browse:ageLine()
    local d = self.data
    if d.state ~= "ok" and d.state ~= "copy" then return nil end
    local s = self:fmt("catalogUpdated", ageText(self, d.indexIssued, d.now)) .. " - " .. self:fmt("revocationsChecked", ageText(self, d.revokedIssued, d.now))
    if d.state == "copy" then s = self:str("offline") .. " - " .. s end
    return s
end

local function setLine(self, key, el, text)
    local ui = self.ui
    if text and self.texts[key] ~= text then ui.text.set(el, cut(text, Screen.MAX_TEXT)); self.texts[key] = text end
    local want = text ~= nil
    if self.shownEl[key] ~= want then ui.text.setVisible(el, want); self.shownEl[key] = want end
end

function Browse:fill()
    local ui = self.ui
    local rows = (self.data.state == "ok" or self.data.state == "copy") and self.data.rows or {}
    local all
    self.shown, self.matched, all = Catalog.filter(rows, self.filters)
    for n = self.made + 1, #self.shown do self:makeRow(n) end
    for n = 1, self.made do
        local c, r = self.cells[n], self.shown[n]
        if r then
            local cat = r.primary and self:str("cat." .. r.primary) or self:str("unknown")
            local st = self:str(STATE_KEY[r.state] or "stAvailable")
            if c.name ~= r.name then ui.text.set(c.nameH, r.name ~= "" and r.name or "-"); c.name = r.name end
            if c.cat ~= cat then ui.text.set(c.catH, cat); c.cat = cat end
            local ver = Catalog.clean(r.version, Catalog.MAX_FIELD)
            if c.ver ~= ver then ui.text.set(c.verH, ver); c.ver = ver end
            local sc = Screen.SCOPE_KEY[r.scope] and r.scope or "unknown"
            if c.scope ~= sc then ui.image.set(c.sc, { image = { icon = "scope-" .. sc } }); c.scope = sc end
            local tip = self:scopeTip(sc)
            if c.scopeTip ~= tip then ui.image.setTooltip(c.sc, tip); c.scopeTip = tip end
            if c.st ~= st then ui.text.set(c.stH, st); c.st = st end
            local warn = r.needsCore == true
            if c.warn ~= warn then ui.image.set(c.w, { image = warn and { icon = "warning" } or false }); c.warn = warn end
            local wtip = warn and self:fmt("needsCore", r.coreNeed or self:str("unknown")) or nil
            if c.warnTip ~= wtip then ui.image.setTooltip(c.w, wtip); c.warnTip = wtip end
            local desc = cut(r.description, Catalog.MAX_DESCRIPTION)
            if c.desc ~= desc then ui.text.set(c.descH, desc); c.desc = desc end
            if not c.visible then ui.row.setVisible(c.row, true); ui.row.setVisible(c.drow, true); c.visible = true end
        elseif c.visible then
            ui.row.setVisible(c.row, false); ui.row.setVisible(c.drow, false)
            c.visible = false
        end
    end
    setLine(self, "age", self.age, self:ageLine())
    setLine(self, "status", self.status, self:statusText())
    local count = self:fmt("count", self.matched, #rows)
    if self.matched > #self.shown then count = count .. " - " .. self:fmt("capped", Catalog.MAX_SHOWN) end
    if self.countText ~= count then ui.text.set(self.count, count); self.countText = count end
    if self.onFiltered then self.onFiltered(self.filters, self.shown, self.matched, all) end
end

-- ---------------------------------------------------------------- input
-- A choice's change (inside core's hook): recorded now, filled after the hook.
local FILTER_VALUE = {
    cat = function(i) return Catalog.CATEGORIES[i - 1] end,
    show = function(i) return Catalog.SHOW[i] or "all" end,
    scope = function(i) return Catalog.SCOPES[i - 1] end,
    ["for"] = function(i) return Catalog.FOR[i] or "game" end,
}
-- One fill after the hook for any number of changes before it.
local function refill(self, what)
    if self.fillPending then return end
    self.fillPending = true
    later(self, what, function()
        self.fillPending = false
        if self:isOpen() then self:fill() end
    end)
end
function Browse:onChoice(which, i)
    self.filters[which] = FILTER_VALUE[which](i)
    refill(self, "the filter")
end
function Browse:onSearch(text)
    text = type(text) == "string" and text or ""
    if text == self.filters.q then return end
    self.filters.q = text
    refill(self, "the search")
end
function Browse:onDetailsClick(n)
    if self.onDetails then self.onDetails(n) else self:openDetails(n) end
end

-- ---------------------------------------------------------------- open, update
function Browse:resetFilters()
    local ui = self.ui
    self.filters = { cat = nil, show = "all", scope = nil, ["for"] = "game", q = "" }
    ui.choice.set(self.cat, 1); ui.choice.set(self.show, 1); ui.choice.set(self.scope, 1); ui.choice.set(self.forC, 1)
    ui.textbox.set(self.q, "")
end

function Browse:open(data, lang, size)
    local ui = self.ui
    self.lang = lang or "en"
    self.data = data or self.data
    self.message = nil
    self.win = ui.screen.open{ id = "browse" }
    if not self.built then
        self:build(size or { w = 1920, h = 1080 })
        self.built = true
    else
        if size and (self.size.w ~= size.w or self.size.h ~= size.h) then
            local ls = Browse.listSize(size)
            self.size = { w = size.w, h = size.h }
            local function tl(gap) return { screen = self.win, corner = "top-left", gap = gap or "normal" } end
            self.flist = ui.list.create{ id = "bw.flist", size = { w = ls.w, h = Browse.FILTER_H }, place = tl() }
            self.hlist = ui.list.create{ id = "bw.hlist", size = { w = ls.w, h = Browse.HEADER_H }, place = tl() }
            self.list = ui.list.create{ id = "bw.list", size = ls, place = tl("tight") }
            self.listSz = ls
        end
        self:relabel()
    end
    self:resetFilters()
    self:fill()
    return self.win
end

-- The labels again in the current language (a later open; only what changed).
function Browse:relabel()
    local ui = self.ui
    ui.text.set(self.title, self:str("browseTitle"))
    ui.text.set(self.qLabel, self:str("search")); ui.text.set(self.catLabel, self:str("category"))
    ui.text.set(self.showLabel, self:str("show")); ui.text.set(self.scopeLabel, self:str("scopeFilter")); ui.text.set(self.forLabel, self:str("forFilter"))
    ui.text.set(self.hName, self:str("name")); ui.text.set(self.hCat, self:str("category")); ui.text.set(self.hVer, self:str("version")); ui.text.set(self.hSt, self:str("stateHeader"))
    if self.refreshSpec.label ~= self:str("refresh") then
        self.refreshSpec.label = self:str("refresh")
        ui.button.create(self.refreshSpec)
    end
end

function Browse:isOpen() return self.win ~= nil and self.ui.screen.isOpen(self.win) == true end

function Browse:update(data)
    self.data = data or self.data
    self.message = nil
    if self.built and self:isOpen() then self:fill() end
end

function Browse:setMessage(text)
    self.message = text and cut(text, Screen.MAX_TEXT) or nil
    if self.built and self:isOpen() then setLine(self, "status", self.status, self:statusText()) end
end

-- ---------------------------------------------------------------- Details
-- What the Details window shows for a row: the title, the description lines (wrapped here: core has no wrap yet),
-- and the fact lines.
function Browse:detailsLines(r)
    local l = { title = r.name ~= "" and r.name or Catalog.token(r.id) }
    l.desc = Catalog.wrap(r.description, Browse.DESC_WIDTH, Browse.DESC_LINES)
    local cats = {}
    for _, c in ipairs(r.categories or {}) do cats[#cats + 1] = self:str("cat." .. c) end
    l.cats = self:fmt("categoriesLine", #cats > 0 and table.concat(cats, ", ") or self:str("unknown"))
    l.ver = self:str("version") .. " " .. Catalog.clean(r.version, Catalog.MAX_FIELD)
    l.runs = self:scopeLine({ scope = r.scope }) -- screen.lua's RUNS ON line
    l.game = self:fmt("forGameLine", Catalog.clean(r.gameVersion or self:str("unknown"), Catalog.MAX_FIELD), Catalog.clean(r.gameBuild or self:str("unknown"), Catalog.MAX_FIELD))
    l.deps = {}
    local deps = r.deps or {}
    if #deps == 0 then l.deps[1] = self:str("needsNothing") end
    for i, d in ipairs(deps) do
        if i == Browse.DEP_LINES and #deps > Browse.DEP_LINES then
            l.deps[i] = self:fmt("andMoreNeeds", #deps - Browse.DEP_LINES + 1)
            break
        end
        l.deps[i] = self:fmt("needLine", d.name or Catalog.token(d.id), d.need, self:str(d.met and "met" or "notMet"))
    end
    l.inst = self:fmt("installedLine", r.installedVersion and Catalog.clean(r.installedVersion ~= "" and r.installedVersion or self:str("unknown"), Catalog.MAX_FIELD) or self:str("no"))
    l.pub = self:fmt("publisherLine", r.publisher ~= "" and r.publisher or self:str("unknown"))
    l.lic = self:fmt("licenseLine", r.license ~= "" and r.license or self:str("unknown"))
    return l
end

-- The Details window for shown row n (on top of Browse). Returns its description lines' count, or nil.
function Browse:openDetails(n)
    local r = self.shown[n]
    if not r then return nil end
    local ui = self.ui
    local l = self:detailsLines(r)
    self.detWin = ui.screen.open{ id = "details" }
    local dt = self.dt
    if not dt then
        dt = { desc = {}, deps = {}, descShown = {}, depShown = {} }
        local function at(gap) return { screen = self.detWin, corner = "top-left", gap = gap or "tight" } end
        local function body(id, font) return ui.text.create{ id = id, text = "", place = at(), style = { font = font or "body" } } end
        dt.title = ui.text.create{ id = "dt.title", text = "", place = at("normal"), style = { font = "title" } }
        for k = 1, Browse.DESC_LINES do dt.desc[k] = body("dt.l" .. k, "small"); dt.descShown[k] = true end
        dt.cats, dt.ver, dt.runs, dt.game = body("dt.cats"), body("dt.ver"), body("dt.runs"), body("dt.game")
        for k = 1, Browse.DEP_LINES do dt.deps[k] = body("dt.n" .. k); dt.depShown[k] = true end
        dt.inst, dt.pub, dt.lic = body("dt.inst"), body("dt.pub"), body("dt.lic")
        self.dt = dt
    end
    ui.text.set(dt.title, cut(l.title, Screen.MAX_TEXT))
    for k = 1, Browse.DESC_LINES do
        local t = l.desc[k]
        if t then ui.text.set(dt.desc[k], t) end
        if dt.descShown[k] ~= (t ~= nil) then ui.text.setVisible(dt.desc[k], t ~= nil); dt.descShown[k] = t ~= nil end
    end
    ui.text.set(dt.cats, cut(l.cats, Screen.MAX_TEXT)); ui.text.set(dt.ver, cut(l.ver, Screen.MAX_TEXT))
    ui.text.set(dt.runs, cut(l.runs, Screen.MAX_TEXT)); ui.text.set(dt.game, cut(l.game, Screen.MAX_TEXT))
    for k = 1, Browse.DEP_LINES do
        local t = l.deps[k]
        if t then ui.text.set(dt.deps[k], cut(t, Screen.MAX_TEXT)) end
        if dt.depShown[k] ~= (t ~= nil) then ui.text.setVisible(dt.deps[k], t ~= nil); dt.depShown[k] = t ~= nil end
    end
    ui.text.set(dt.inst, cut(l.inst, Screen.MAX_TEXT)); ui.text.set(dt.pub, cut(l.pub, Screen.MAX_TEXT)); ui.text.set(dt.lic, cut(l.lic, Screen.MAX_TEXT))
    return #l.desc
end

return Browse
