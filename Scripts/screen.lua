-- Mod Manager stories 3 and 6: the main window, the Configure window, and story 6's confirm and alert windows, through
-- core.ui only (Nucleus >= 0.12.0: windows, lists, rows, images, checkbox, choice, slider).
--
--   local view = Screen.new(ui, strings)
--   view:openMain(rows, lang, size)   opens (or refreshes) the main window; size = { w, h } in canvas units (the
--                                     viewport's layout size; h is 1080 under the game's UI scale)
--   view:refresh(rows)                puts new data into the open window's rows (after a toggle or a setting)
--   view:setToggle(n, on)             sets row n's checkbox back without a callback
--   view:setPending(count)            the banner and QUIT GAME, shown while count > 0
--   view:setRestartable(on)           story 8: RESTART NOW shows beside QUIT GAME (pending and on); on = core.restart has a mode
--   view:setMessage(text | nil)       the main window's message line
--   view:openConfirm(text)            the confirm window (TURN OFF), on top; view:closeConfirm()
--   view:openAlert(text)              the alert window (BACK only), on top
--   view:openConfigure(n, settings)   the Configure window for row n, on top; settings = describe's list ({} for none)
--   view:fillSettings(settings)       new values into the open Configure window's controls
--   view:setConfigureProblems(lines)  the Configure window's problem lines
--   view:setControl(i, value)         sets setting i's control back without a callback
--   view:setCfgMessage(text | nil)    Configure's message line
-- Callbacks the caller sets (main.lua wraps each in pcall): onGearClick(n), onToggle(n, checked), onConfirm(),
-- onQuit(), onRestart() (story 8), onSetting(i, value); v2 story 4: onBrowse() (set before the first open: the main
-- window then has BROWSE at its top right).
-- v2 story 6: view:setNotice(nRevoked, nUpdates) (the notice line under the title, with REVIEW -> onReview() and
-- UPDATES -> onUpdates()); a row's updateTo shows as "<installed> → <offered>" in its version cell, and its status
-- kind revoked as core's warning icon tinted red (status.lua); view:openRevoked(list) / fillRevoked(list) /
-- closeRevoked() / isRevokedOpen() / setRevokedMessage(text) (the revoked window, id "revoked"; onRevokedUpdate(id),
-- onRevokedUninstall(id)).
--
-- Elements are created once per session and reused on every open: a window's elements stay created across closes and
-- attach again on the next open of the same id (core's screen host). Rows are made as they are first needed; rows above
-- the current count are hidden, never removed. Element ids are index-based, well inside core's 64-character rule.
--
-- A row: toggle | name | version | scope | status (3 icons) | gear.
--   toggle: r<n>.on, an image with core's lock icon (Nucleus and the Mod Manager: ALWAYS ON), and r<n>.tg, core's
--           checkbox (tooltip ON / OFF); a pak-only row or a folder row with a joined pak shows its state in a disabled
--           checkbox (BLUEPRINT MODS CAN'T BE SWITCHED FROM THE GAME YET). Each row has both; the unused one is hidden.
--   name, version: texts with fill 4 and 1, cut with an ellipsis at the column edge.
--   scope: r<n>.sc (story 12), an image with core's scope-<host|client|host-plus|both|unknown> icon for the row's
--          mod.json scope (inventory.lua), tooltip "<name> - <meaning>"; Configure repeats it as its RUNS ON line, which
--          gamepad and keyboard players reach through the gear (images take no focus; tooltips show on hover only).
--   status: r<n>.s1..s3, fixed images filled left to right (build, dependency, restart), the rest empty.
--   gear: an icon-only button, tooltip CONFIGURE, dimmed when the mod declares no settings; it opens Configure.
-- The header mirrors a row (spacer, NAME, VERSION, spacer, three spacers, spacer) in a one-row list of the same width.
--
-- Layout (0.1.1, story 9): the title, the header list and the list stack in the card's top-left corner; core's BACK is
-- in its bottom-left corner. Story 6 adds QUIT GAME, the banner and the message line in the bottom-right corner (shown
-- only while needed), so LIST_RESERVE leaves room for that stack beside BACK. Story 8 adds RESTART NOW to that stack,
-- right above QUIT GAME (bottom to top: QUIT GAME, RESTART NOW, the banner, the message line). The card hugs it: with
-- all four shown at layout height 1080 the card stays inside the viewport (core logs a WARN if it is ever clamped). The Configure window stacks its heading,
-- its detail lines, its problem lines, its settings list (or NO SETTINGS) and its message line in its top-left corner.
local Screen = {}
Screen.__index = Screen

Screen.ICON = 28           -- the toggle, the status icons and the gear, square, canvas units
Screen.HEADER_H = 64       -- the header list's height
-- The Mod Manager's own budget for the main window, in layout units (core's card chrome, BACK's size and its stack gap
-- are core's; the screen scenario's CARDFIT check and check.ps1's card-WARN pattern verify the budget):
--   LIST_RESERVE: taken from the layout height for everything in the card but the list: the card's chrome, the title,
--     the header list, the gaps, and the taller of BACK and story 6's bottom-right stack (QUIT GAME, the banner, the
--     message line). At layout height 1080 the list is 540 high (about 10 rows; more scroll).
--   SIDE_RESERVE: taken from the layout width, so a wider screen only widens the columns.
Screen.LIST_RESERVE = 540
Screen.SIDE_RESERVE = 720
-- A corner stack puts each element its own gap in from the side edge as well as below the previous one (UI-3: tight 8,
-- normal 16). The list follows the header list a tight gap below, so it is nudged right by the difference.
Screen.LIST_NUDGE = 8
Screen.FILL = { name = 4, ver = 1 }
Screen.STATUS_SLOTS = 4      -- v2 story 6: build, dependency, restart, revoked
-- v2 story 6: the notice line under the title (a one-row list: the text, REVIEW, UPDATES), shown only while there is
-- something to say; while it shows, the main list is NOTICE_RESERVE shorter so the card keeps its height.
Screen.NOTICE_H = 64
Screen.NOTICE_RESERVE = 64 + 16
-- v2 story 6: the revoked window (one mod per two list rows: name | version | UPDATE TO | UNINSTALL, then its reason)
Screen.REVOKED_MAX = 32
Screen.REVOKED_REASON = 120  -- characters of a reason shown
Screen.REVOKED_LIST_H = 420
Screen.REVOKED_FILL = { name = 3, ver = 1 }
Screen.RED = { r = 0.85, g = 0.1, b = 0.1, a = 1 } -- the revoked badge's tint
-- Configure: its settings list's height is the layout height less CFG_RESERVE (heading, four detail lines, the message
-- line, BACK, the card's chrome) and PROBLEM_H per problem line shown; at least CFG_LIST_MIN. Story 12's RUNS ON line is
-- the fourth detail line: one more body line, so PROBLEM_H (a body line and its gap) more than the 540 for three.
Screen.CFG_RESERVE = 540 + 46
Screen.PROBLEM_H = 46
Screen.CFG_LIST_MIN = 96
Screen.MAX_PROBLEM_LINES = 8
Screen.MAX_SETTINGS = 64
Screen.SETTING_FILL = { label = 3, control = 2 }
Screen.MAX_TEXT = 256      -- core's text cap (characters); longer texts are cut here, so core never warns
local ICON_OF = { build = "warning", dep = "warning", restart = "restart", revoked = "warning" }
local TINT_OF = { revoked = Screen.RED } -- the rest: the icon as it is (white)
-- Story 12: a row's scope (inventory.lua: host, client, host-plus, both, unknown) -> its strings' key part
-- (scope<Part> is the name, scope<Part>Means the meaning). Anything else reads as unknown.
Screen.SCOPE_KEY = { host = "Host", client = "Client", ["host-plus"] = "HostPlus", both = "Both", unknown = "Unknown" }

function Screen.new(ui, strings)
    return setmetatable({ ui = ui, S = strings, lang = "en", data = {}, made = 0, cells = {}, size = nil,
        main = nil, cfgWin = nil, cfgMade = false, sCells = {}, sMade = 0, pending = 0, message = nil, restartable = false }, Screen)
end

function Screen:str(key) return self.S.get(key, self.lang) end
function Screen:fmt(key, ...)
    if self.S.fmt then return self.S.fmt(key, self.lang, ...) end
    local ok, s = pcall(string.format, self:str(key), ...)
    return ok and s or self:str(key)
end

-- At most n bytes, cut on a UTF-8 boundary.
local function cut(s, n)
    s = tostring(s)
    if #s <= n then return s end
    local i = n
    while i > 0 and (s:byte(i + 1) or 0) >= 0x80 and (s:byte(i + 1) or 0) < 0xC0 do i = i - 1 end
    return s:sub(1, i)
end
Screen.cut = cut
-- Text from a mod.json (label, help, source, values): control characters as spaces, at most n bytes.
function Screen.clean(v, n)
    if type(v) ~= "string" then return "" end
    return cut((v:gsub("[%z\1-\31\127]", " "):gsub("\194[\128-\159]", "  ")), n)
end

-- The toggle's kind for a row: "lock" (Nucleus, the Mod Manager), "fixed" (a pak-only row, or a folder row with a
-- joined pak: shown, never switched), else "box".
function Screen.toggleKind(row)
    if row.state == "locked" then return "lock" end
    if row.pakOnly or (row.paks and #row.paks > 0) then return "fixed" end
    return "box"
end

-- What a row shows: name, version (UNMANAGED for a pak with no folder, - when unknown).
function Screen:versionText(row)
    if row.pakOnly then return self:str("unmanaged") end
    return row.version or self:str("unknown")
end
-- v2 story 6: the version cell: "<installed> → <offered>" when the catalog offers an update (main.lua sets updateTo).
function Screen:versionCell(row)
    local v = self:versionText(row)
    if type(row.updateTo) == "string" and not row.pakOnly then return self:fmt("versionArrow", v, cut(row.updateTo, 64)) end
    return v
end

-- Story 12: a row's scope key (unknown for anything inventory.lua didn't give), its words, its tooltip and its
-- Configure line.
function Screen.scopeOf(row)
    local s = row and row.scope
    if type(s) ~= "string" or not Screen.SCOPE_KEY[s] then s = "unknown" end
    return s
end
function Screen:scopeWords(row)
    local part = Screen.SCOPE_KEY[Screen.scopeOf(row)]
    return self:str("scope" .. part), self:str("scope" .. part .. "Means")
end
function Screen:scopeTip(row)
    local name, means = self:scopeWords(row)
    return name .. " - " .. means
end
function Screen:scopeLine(row)
    local name, means = self:scopeWords(row)
    return self:str("scopeLabel") .. ": " .. name .. " - " .. means
end

function Screen.listSize(size, notice)
    return { w = size.w - Screen.SIDE_RESERVE, h = size.h - Screen.LIST_RESERVE - (notice and Screen.NOTICE_RESERVE or 0) }
end

-- The lists' places and sizes for a layout size (story 9). A later call re-creates them with the same ids and
-- places: core updates them in place and keeps their stack order. v2 story 6: the notice line's one-row list first
-- (between the title and the header), and the main list NOTICE_RESERVE shorter while the notice shows.
function Screen:lists(size)
    local ls = Screen.listSize(size, self.noticeShown)
    local ui = self.ui
    self.noticeList = ui.list.create{ id = "notice.list", size = { w = ls.w, h = Screen.NOTICE_H },
        place = { screen = self.main, corner = "top-left", gap = "normal" } }
    self.hdrList = ui.list.create{ id = "hdr.list", size = { w = ls.w, h = Screen.HEADER_H },
        place = { screen = self.main, corner = "top-left", gap = "normal" } }
    self.list = ui.list.create{ id = "list", size = ls,
        place = { screen = self.main, corner = "top-left", gap = "tight", offset = { x = Screen.LIST_NUDGE, y = 0 } } }
    self.size = { w = size.w, h = size.h }
    self.listNotice = self.noticeShown == true
end

-- v2 story 6: the notice line's row (once): its text, REVIEW (the revoked window) and UPDATES (Browse showing UPDATE
-- AVAILABLE), all hidden until setNotice has something to say.
function Screen:buildNotice()
    local ui = self.ui
    local row = ui.row.create{ id = "notice", place = { list = self.noticeList } }
    self.noticeText = ui.text.create{ id = "notice.text", text = "", place = { row = row, fill = 4 }, style = { font = "body", overflow = "ellipsis" } }
    self.reviewSpec = { id = "notice.review", label = self:str("review"), place = { row = row },
        onClick = function() if self.onReview then self.onReview() end end }
    self.reviewBtn = ui.button.create(self.reviewSpec)
    self.updatesSpec = { id = "notice.updates", label = self:str("updates"), place = { row = row },
        onClick = function() if self.onUpdates then self.onUpdates() end end }
    self.updatesBtn = ui.button.create(self.updatesSpec)
    ui.list.setVisible(self.noticeList, false)
    ui.button.setVisible(self.reviewBtn, false)
    ui.button.setVisible(self.updatesBtn, false)
    self.noticeShown, self.noticeState = false, { text = "", review = false, updates = false }
end

-- The notice line: "<n> REVOKED" and/or "<m> UPDATES AVAILABLE", REVIEW with revoked mods, UPDATES with updates; hidden
-- when both are 0. Only what changed is set; the main list is resized when the line appears or goes.
function Screen:setNotice(nRevoked, nUpdates)
    self.notice = { revoked = nRevoked or 0, updates = nUpdates or 0 }
    if not self.built then return end
    local ui = self.ui
    local parts = {}
    if self.notice.revoked > 0 then parts[#parts + 1] = self:fmt("nRevoked", self.notice.revoked) end
    if self.notice.updates > 0 then parts[#parts + 1] = self:fmt("nUpdates", self.notice.updates) end
    local text = table.concat(parts, " - ")
    local st = self.noticeState
    if text ~= "" and st.text ~= text then ui.text.set(self.noticeText, cut(text, Screen.MAX_TEXT)); st.text = text end
    for _, k in ipairs({ "review", "updates" }) do
        local spec = k == "review" and self.reviewSpec or self.updatesSpec
        if spec.label ~= self:str(k) then spec.label = self:str(k); ui.button.create(spec) end
    end
    local rv, up = self.notice.revoked > 0, self.notice.updates > 0
    if st.review ~= rv then ui.button.setVisible(self.reviewBtn, rv); st.review = rv end
    if st.updates ~= up then ui.button.setVisible(self.updatesBtn, up); st.updates = up end
    local show = text ~= ""
    if self.noticeShown ~= show then
        self.noticeShown = show
        ui.list.setVisible(self.noticeList, show)
        if self.size then self:lists(self.size) end
    end
end

-- The title, the header, the two lists, and the bottom-right stack (QUIT GAME, the banner, the message line; hidden
-- until needed): once, on the first open.
function Screen:build(size)
    local ui = self.ui
    self.title = ui.text.create{ id = "title", text = self:str("title"),
        place = { screen = self.main, corner = "top-left" }, style = { font = "title" } }
    -- v2 story 4: BROWSE, top right beside the title, only when the caller set onBrowse (core.catalog exists)
    if self.onBrowse then
        self.browseSpec = { id = "browse", label = self:str("browse"), place = { screen = self.main, corner = "top-right" },
            onClick = function() if self.onBrowse then self.onBrowse() end end }
        self.browseBtn = ui.button.create(self.browseSpec)
    end
    self:lists(size)
    self:buildNotice()
    local hdr = ui.row.create{ id = "hdr", place = { list = self.hdrList } }
    ui.image.create{ id = "hdr.on", place = { row = hdr }, size = Screen.ICON }
    self.hdrName = ui.text.create{ id = "hdr.name", text = self:str("name"), place = { row = hdr, fill = Screen.FILL.name }, style = { font = "body", overflow = "ellipsis" } }
    self.hdrVer = ui.text.create{ id = "hdr.ver", text = self:str("version"), place = { row = hdr, fill = Screen.FILL.ver }, style = { font = "body", overflow = "ellipsis" } }
    ui.image.create{ id = "hdr.sc", place = { row = hdr }, size = Screen.ICON } -- story 12: above the scope column
    for k = 1, Screen.STATUS_SLOTS do ui.image.create{ id = "hdr.s" .. k, place = { row = hdr }, size = Screen.ICON } end
    ui.image.create{ id = "hdr.cfg", place = { row = hdr }, size = Screen.ICON }
    local function br() return { screen = self.main, corner = "bottom-right", gap = "normal" } end
    self.quitSpec = { id = "quit", label = self:str("quit"), place = br(), onClick = function() if self.onQuit then self.onQuit() end end }
    self.quitBtn = ui.button.create(self.quitSpec)
    ui.button.setVisible(self.quitBtn, false)
    -- story 8: RESTART NOW, right above QUIT GAME in the same stack
    self.restartSpec = { id = "restart", label = self:str("restart"), place = br(), onClick = function() if self.onRestart then self.onRestart() end end }
    self.restartBtn = ui.button.create(self.restartSpec)
    ui.button.setVisible(self.restartBtn, false)
    self.banner = ui.text.create{ id = "banner", text = self:str("banner"), place = br(), style = { font = "body" } }
    ui.text.setVisible(self.banner, false)
    self.msg = ui.text.create{ id = "msg", text = "", place = br(), style = { font = "body" } }
    ui.text.setVisible(self.msg, false)
    self.shown = { quit = false, restart = false, banner = false, msg = false }
end

-- Row n's elements (made once).
function Screen:makeRow(n)
    local ui = self.ui
    local p = "r" .. n
    local row = ui.row.create{ id = p, place = { list = self.list } }
    local c = { row = row, visible = true, name = "", ver = "", kind = "box", checked = false, enabled = true,
        onVisible = false, tgVisible = true, icons = {}, dimmed = true }
    c.on = ui.image.create{ id = p .. ".on", place = { row = row }, image = { icon = "lock" }, size = Screen.ICON, tooltip = self:str("alwaysOn") }
    ui.image.setVisible(c.on, false)
    c.tgTip = self:str("off")
    c.tg = ui.checkbox.create{ id = p .. ".tg", checked = false, size = Screen.ICON, tooltip = c.tgTip, place = { row = row },
        onChange = function(_, checked) self:onToggleClick(n, checked) end }
    c.nameH = ui.text.create{ id = p .. ".name", text = "", place = { row = row, fill = Screen.FILL.name }, style = { font = "body", overflow = "ellipsis" } }
    c.verH = ui.text.create{ id = p .. ".ver", text = "", place = { row = row, fill = Screen.FILL.ver }, style = { font = "body", overflow = "ellipsis" } }
    -- story 12: where the mod runs, from the data (fill sets it again only when it changes)
    local d = self.data[n]
    c.scope, c.scopeTip = Screen.scopeOf(d), self:scopeTip(d)
    c.sc = ui.image.create{ id = p .. ".sc", place = { row = row }, image = { icon = "scope-" .. c.scope }, size = Screen.ICON,
        tooltip = c.scopeTip }
    c.st, c.stId = {}, {}
    for k = 1, Screen.STATUS_SLOTS do
        c.stId[k] = p .. ".s" .. k
        c.st[k] = ui.image.create{ id = c.stId[k], place = { row = row }, size = Screen.ICON }
        c.icons[k] = { icon = nil, tip = nil, tint = nil }
    end
    c.cfgSpec = { id = p .. ".cfg", place = { row = row }, icon = { icon = "gear" }, iconSize = Screen.ICON, dimmed = true,
        tooltip = self:str("configure"), onClick = function() self:onGear(n) end }
    c.cfg = ui.button.create(c.cfgSpec)
    c.cfgTip = c.cfgSpec.tooltip
    self.cells[n] = c
    self.made = n
end

-- The gear's click: the caller (main.lua) wraps it in pcall through onGearClick.
function Screen:onGear(n)
    if self.onGearClick then self.onGearClick(n) else self:openConfigure(n, {}) end
end
-- A real click on a row's checkbox (core has already flipped it).
function Screen:onToggleClick(n, checked)
    local c = self.cells[n]
    if c then c.checked = checked end
    if self.onToggle then self.onToggle(n, checked) end
end

-- Row n's toggle: the lock, or the checkbox (live or fixed), showing on/off.
function Screen:fillToggle(c, r)
    local ui = self.ui
    local kind = Screen.toggleKind(r)
    local on = r.state ~= "off"
    local lock = kind == "lock"
    if c.onVisible ~= lock then ui.image.setVisible(c.on, lock); c.onVisible = lock end
    if c.tgVisible ~= not lock then ui.checkbox.setVisible(c.tg, not lock); c.tgVisible = not lock end
    local tip = self:str("alwaysOn")
    if c.lockTip ~= tip then ui.image.setTooltip(c.on, tip); c.lockTip = tip end
    if not lock then
        if c.checked ~= on then ui.checkbox.set(c.tg, on); c.checked = on end
        local enabled = kind == "box"
        if c.enabled ~= enabled then ui.checkbox.setEnabled(c.tg, enabled); c.enabled = enabled end
        local tgTip = enabled and self:str(on and "on" or "off") or self:str("pakFixed")
        if c.tgTip ~= tgTip then ui.checkbox.setTooltip(c.tg, tgTip); c.tgTip = tgTip end
    end
    c.kind = kind
end

-- Row n's status icons: build, dependency, restart, filled left to right; the rest empty.
function Screen:fillStatus(c, r)
    local ui = self.ui
    local st = r.st or { kinds = {}, tips = {} }
    for k = 1, Screen.STATUS_SLOTS do
        local kind = st.kinds and st.kinds[k]
        local icon = kind and ICON_OF[kind] or nil
        local tip = kind and st.tips and st.tips[kind] or nil
        if tip == "" then tip = nil end
        local cur = c.icons[k]
        local tint = kind and TINT_OF[kind] or nil
        if cur.tint ~= tint then
            -- v2 story 6: a tint is a style, set by creating the image again with its id (core updates it in place)
            ui.image.create{ id = c.stId[k], place = { row = c.row }, size = Screen.ICON, image = icon and { icon = icon } or nil,
                style = tint and { tint = tint } or nil, tooltip = tip }
            cur.tint = tint -- the icon and tooltip below too, so a cleared icon is cleared everywhere
        end
        if cur.icon ~= icon then
            ui.image.set(c.st[k], { image = icon and { icon = icon } or false })
            cur.icon = icon
        end
        if cur.tip ~= tip then
            ui.image.setTooltip(c.st[k], tip)
            cur.tip = tip
        end
    end
end

-- Puts the current data into rows 1..#data and hides the rest. Only what changed is set.
function Screen:fill()
    local ui = self.ui
    for n = self.made + 1, #self.data do self:makeRow(n) end
    if self.hdrName then ui.text.set(self.hdrName, self:str("name")); ui.text.set(self.hdrVer, self:str("version")) end
    if self.title then ui.text.set(self.title, self:str("title")) end
    if self.banner then ui.text.set(self.banner, self:str("banner")) end
    if self.quitSpec and self.quitSpec.label ~= self:str("quit") then
        self.quitSpec.label = self:str("quit")
        ui.button.create(self.quitSpec) -- the same id: core applies the new label
    end
    if self.browseSpec and self.browseSpec.label ~= self:str("browse") then
        self.browseSpec.label = self:str("browse")
        ui.button.create(self.browseSpec)
    end
    if self.restartSpec and self.restartSpec.label ~= self:str("restart") then
        self.restartSpec.label = self:str("restart")
        ui.button.create(self.restartSpec)
    end
    for n = 1, self.made do
        local c, r = self.cells[n], self.data[n]
        if r then
            self:fillToggle(c, r)
            if c.name ~= r.name then ui.text.set(c.nameH, r.name); c.name = r.name end
            local v = self:versionCell(r)
            if c.ver ~= v then ui.text.set(c.verH, v); c.ver = v end
            local sc, scTip = Screen.scopeOf(r), self:scopeTip(r)
            if c.scope ~= sc then ui.image.set(c.sc, { image = { icon = "scope-" .. sc } }); c.scope = sc end
            if c.scopeTip ~= scTip then ui.image.setTooltip(c.sc, scTip); c.scopeTip = scTip end
            self:fillStatus(c, r)
            local dim = not r.settings
            local cfgTip = self:str("configure")
            if c.dimmed ~= dim or c.cfgTip ~= cfgTip then
                c.cfgSpec.dimmed, c.cfgSpec.tooltip = dim, cfgTip
                ui.button.create(c.cfgSpec) -- the same id: core applies the new dimmed state and tooltip
                c.dimmed, c.cfgTip = dim, cfgTip
            end
            if not c.visible then ui.row.setVisible(c.row, true); c.visible = true end
        elseif c.visible then
            ui.row.setVisible(c.row, false)
            c.visible = false
        end
    end
end

function Screen:openMain(rows, lang, size)
    self.data = rows or {}
    self.lang = lang or "en"
    local ui = self.ui
    if not self.built then
        -- Marked built only once build succeeds: a failure partway leaves the next open to build again (the same
        -- ids update what was already made).
        self.main = ui.screen.open{ id = "main" }
        self:build(size)
        self.built = true
        self:fill()
        self:applyFooter()
        if self.notice then self:setNotice(self.notice.revoked, self.notice.updates) end
        return self.main
    end
    if size and (not self.size or self.size.w ~= size.w or self.size.h ~= size.h) then self:lists(size) end
    self:fill()
    self:applyFooter()
    if self.notice then self:setNotice(self.notice.revoked, self.notice.updates) end
    return ui.screen.open{ id = "main" }
end

-- New data into the open main window (no screen.open).
function Screen:refresh(rows)
    self.data = rows or self.data
    if self.built then self:fill(); self:applyFooter() end
end

function Screen:setToggle(n, on)
    local c = self.cells[n]
    if not c then return end
    self.ui.checkbox.set(c.tg, on == true)
    c.checked = on == true
end

-- The bottom-right stack: QUIT GAME and the banner while something is pending, RESTART NOW with them while the game
-- can be restarted (story 8), the message line while it has text.
function Screen:applyFooter()
    if not self.built then return end
    local ui = self.ui
    local pend = (self.pending or 0) > 0
    if self.shown.quit ~= pend then ui.button.setVisible(self.quitBtn, pend); self.shown.quit = pend end
    local rs = pend and self.restartable == true
    if self.restartBtn and self.shown.restart ~= rs then ui.button.setVisible(self.restartBtn, rs); self.shown.restart = rs end
    if self.shown.banner ~= pend then ui.text.setVisible(self.banner, pend); self.shown.banner = pend end
    local m = self.message
    if m and self.msgText ~= m then ui.text.set(self.msg, m); self.msgText = m end
    if self.shown.msg ~= (m ~= nil) then ui.text.setVisible(self.msg, m ~= nil); self.shown.msg = m ~= nil end
end
function Screen:setPending(count) self.pending = count or 0; self:applyFooter() end
function Screen:setRestartable(on) self.restartable = on == true; self:applyFooter() end
function Screen:setMessage(text) self.message = text and cut(text, Screen.MAX_TEXT) or nil; self:applyFooter() end

-- ---------------------------------------------------------------- the confirm and alert windows

function Screen:openConfirm(text)
    local ui = self.ui
    text = cut(text, Screen.MAX_TEXT)
    self.confirmWin = ui.screen.open{ id = "confirm" }
    if not self.confirmMade then
        local function at() return { screen = self.confirmWin, corner = "top-left", gap = "normal" } end
        self.confirmText = ui.text.create{ id = "confirm.text", text = text, place = at(), style = { font = "body" } }
        self.confirmSpec = { id = "confirm.ok", label = self:str("turnOff"), place = at(),
            onClick = function() if self.onConfirm then self.onConfirm() end end }
        self.confirmBtn = ui.button.create(self.confirmSpec)
        self.confirmMade = true
    else
        ui.text.set(self.confirmText, text)
        if self.confirmSpec.label ~= self:str("turnOff") then
            self.confirmSpec.label = self:str("turnOff")
            ui.button.create(self.confirmSpec)
        end
    end
    return self.confirmWin
end
function Screen:closeConfirm()
    if self.confirmWin and self.ui.screen.isOpen(self.confirmWin) then self.ui.screen.close(self.confirmWin) end
end

function Screen:openAlert(text)
    local ui = self.ui
    text = cut(text, Screen.MAX_TEXT)
    self.alertWin = ui.screen.open{ id = "alert" }
    if not self.alertText then
        self.alertText = ui.text.create{ id = "alert.text", text = text,
            place = { screen = self.alertWin, corner = "top-left", gap = "normal" }, style = { font = "body" } }
    else
        ui.text.set(self.alertText, text)
    end
    return self.alertWin
end

-- ---------------------------------------------------------------- v2 story 6: the revoked window
-- Window id "revoked", on top (over the main window or straight over the title-screen menu). Its title, the message
-- line (hidden until set), then a list: per revoked mod two rows, rv.r<k> (name | version | UPDATE TO <v> | UNINSTALL)
-- and rv.d<k> (the reason, at most REVOKED_REASON characters, in the small font). Core's BACK is LATER. Every button is
-- one of core's (focusable: the keys and a gamepad move between them and BACK). list = Catalog.revokedInstalled's
-- entries; UPDATE TO shows only with a fix. Clicks give the mod's id at the click: onRevokedUpdate(id),
-- onRevokedUninstall(id).
function Screen:buildRevoked()
    local ui = self.ui
    local win = self.revWin
    local function at(gap) return { screen = win, corner = "top-left", gap = gap or "normal" } end
    local size = self.size or { w = 1920, h = 1080 }
    local rv = { rows = {}, made = 0 }
    rv.title = ui.text.create{ id = "rv.title", text = self:str("revokedTitle"), place = at(), style = { font = "title" } }
    rv.msg = ui.text.create{ id = "rv.msg", text = "", place = at(), style = { font = "body" } }
    ui.text.setVisible(rv.msg, false)
    rv.msgShown, rv.msgText = false, ""
    rv.list = ui.list.create{ id = "rv.list", size = { w = size.w - Screen.SIDE_RESERVE, h = math.min(Screen.REVOKED_LIST_H, size.h - Screen.LIST_RESERVE) }, place = at() }
    self.rv = rv
end

function Screen:makeRevokedRow(k)
    local ui = self.ui
    local rv = self.rv
    local p, d = "rv.r" .. k, "rv.d" .. k
    local c = { visible = true, name = "", ver = "", why = "", updLabel = nil, updShown = true }
    c.row = ui.row.create{ id = p, place = { list = rv.list } }
    c.nameH = ui.text.create{ id = p .. ".name", text = "", place = { row = c.row, fill = Screen.REVOKED_FILL.name }, style = { font = "body", overflow = "ellipsis" } }
    c.verH = ui.text.create{ id = p .. ".ver", text = "", place = { row = c.row, fill = Screen.REVOKED_FILL.ver }, style = { font = "body", overflow = "ellipsis" } }
    c.updSpec = { id = p .. ".upd", label = self:str("update"), place = { row = c.row }, onClick = function()
        local e = self.revList and self.revList[k]
        if e and self.onRevokedUpdate then self.onRevokedUpdate(e.id) end
    end }
    c.upd = ui.button.create(c.updSpec)
    c.unSpec = { id = p .. ".un", label = self:str("uninstall"), place = { row = c.row }, onClick = function()
        local e = self.revList and self.revList[k]
        if e and self.onRevokedUninstall then self.onRevokedUninstall(e.id) end
    end }
    c.un = ui.button.create(c.unSpec)
    c.drow = ui.row.create{ id = d, place = { list = rv.list } }
    c.whyH = ui.text.create{ id = d .. ".why", text = "", place = { row = c.drow, fill = 1 }, style = { font = "small", overflow = "ellipsis" } }
    rv.rows[k] = c
    rv.made = k
    return c
end

-- New entries into the revoked window's rows (only what changed); rows past the count hidden.
function Screen:fillRevoked(list)
    local ui = self.ui
    local rv = self.rv
    if not rv then return end
    self.revList = {}
    for i = 1, math.min(#(list or {}), Screen.REVOKED_MAX) do self.revList[i] = list[i] end
    for k = rv.made + 1, #self.revList do self:makeRevokedRow(k) end
    for k = 1, rv.made do
        local c, e = rv.rows[k], self.revList[k]
        if e then
            local name = cut(Screen.clean(e.name, 64), 64)
            if c.name ~= name then ui.text.set(c.nameH, name ~= "" and name or "-"); c.name = name end
            local ver = Screen.clean(e.version or "-", 64)
            if c.ver ~= ver then ui.text.set(c.verH, ver); c.ver = ver end
            local reason = type(e.reason) == "string" and e.reason ~= "" and e.reason or self:str("noReason")
            local okL, len = pcall(utf8.len, reason)
            if okL and len and len > Screen.REVOKED_REASON then reason = reason:sub(1, utf8.offset(reason, Screen.REVOKED_REASON + 1) - 1)
            elseif not (okL and len) then reason = cut(reason, Screen.REVOKED_REASON) end
            if c.why ~= reason then ui.text.set(c.whyH, reason); c.why = reason end
            local fix = type(e.fix) == "string" and e.fix or nil
            local label = fix and self:fmt("updateTo", Screen.clean(fix, 64)) or nil
            if label and c.updSpec.label ~= label then c.updSpec.label = label; ui.button.create(c.updSpec) end
            if c.updShown ~= (fix ~= nil) then ui.button.setVisible(c.upd, fix ~= nil); c.updShown = fix ~= nil end
            if c.unSpec.label ~= self:str("uninstall") then c.unSpec.label = self:str("uninstall"); ui.button.create(c.unSpec) end
            if not c.visible then ui.row.setVisible(c.row, true); ui.row.setVisible(c.drow, true); c.visible = true end
        elseif c.visible then
            ui.row.setVisible(c.row, false); ui.row.setVisible(c.drow, false)
            c.visible = false
        end
    end
end

function Screen:openRevoked(list)
    local ui = self.ui
    self.revWin = ui.screen.open{ id = "revoked" }
    if not self.rv then self:buildRevoked() else ui.text.set(self.rv.title, self:str("revokedTitle")) end
    self:setRevokedMessage(nil)
    self:fillRevoked(list)
    return self.revWin
end
function Screen:isRevokedOpen() return self.revWin ~= nil and self.ui.screen.isOpen(self.revWin) == true end
function Screen:closeRevoked()
    if self:isRevokedOpen() then self.ui.screen.close(self.revWin) end
end
function Screen:setRevokedMessage(text)
    local rv = self.rv
    if not rv then return end
    local ui = self.ui
    if text then
        text = cut(text, Screen.MAX_TEXT)
        if rv.msgText ~= text then ui.text.set(rv.msg, text); rv.msgText = text end
    end
    if rv.msgShown ~= (text ~= nil) then ui.text.setVisible(rv.msg, text ~= nil); rv.msgShown = text ~= nil end
end

-- ---------------------------------------------------------------- Configure

-- The Configure window's detail lines for a row: heading, VERSION, NUCLEUS, GAME BUILD, RUNS ON (story 12).
function Screen:configureLines(row)
    local unknown = self:str("unknown")
    return {
        title = row.name,
        ver = self:str("version") .. " " .. self:versionText(row),
        need = self:str("nucleus") .. " " .. (row.need or unknown),
        build = self:str("gameBuild") .. " " .. (row.build or unknown),
        scope = self:scopeLine(row),
    }
end

function Screen:cfgListSize(nProblems)
    local size = self.size or { w = 1920, h = 1080 }
    local h = size.h - Screen.CFG_RESERVE - Screen.PROBLEM_H * (nProblems or 0)
    return { w = size.w - Screen.SIDE_RESERVE, h = math.max(Screen.CFG_LIST_MIN, h) }
end

-- Configure's elements, once: heading, VERSION, NUCLEUS, GAME BUILD, RUNS ON, the problem lines, NO SETTINGS, the settings
-- list and the message line, in that corner-stack order (all hidden that have nothing to show).
function Screen:buildConfigure(l)
    local ui = self.ui
    local function at() return { screen = self.cfgWin, corner = "top-left", gap = "normal" } end
    local cfg = { problems = {}, problemText = {}, problemShown = {} }
    cfg.title = ui.text.create{ id = "cfg.title", text = l.title, place = at(), style = { font = "title" } }
    cfg.ver = ui.text.create{ id = "cfg.ver", text = l.ver, place = at(), style = { font = "body" } }
    cfg.need = ui.text.create{ id = "cfg.need", text = l.need, place = at(), style = { font = "body" } }
    cfg.build = ui.text.create{ id = "cfg.build", text = l.build, place = at(), style = { font = "body" } }
    cfg.scope = ui.text.create{ id = "cfg.scope", text = l.scope, place = at(), style = { font = "body" } }
    for k = 1, Screen.MAX_PROBLEM_LINES do
        cfg.problems[k] = ui.text.create{ id = "cfg.p" .. k, text = "", place = at(), style = { font = "body" } }
        ui.text.setVisible(cfg.problems[k], false)
        cfg.problemText[k], cfg.problemShown[k] = "", false
    end
    cfg.none = ui.text.create{ id = "cfg.none", text = self:str("noSettings"), place = at(), style = { font = "body" } }
    cfg.noneShown = true
    cfg.listSize = self:cfgListSize(0)
    cfg.list = ui.list.create{ id = "cfg.list", size = cfg.listSize, place = at() }
    cfg.listShown = true
    cfg.msg = ui.text.create{ id = "cfg.msg", text = "", place = at(), style = { font = "body" } }
    ui.text.setVisible(cfg.msg, false)
    cfg.msgShown, cfg.msgText = false, ""
    self.cfg = cfg
end

function Screen:setConfigureProblems(lines)
    local cfg = self.cfg
    if not cfg then return end
    local ui = self.ui
    local n = math.min(#(lines or {}), Screen.MAX_PROBLEM_LINES)
    for k = 1, Screen.MAX_PROBLEM_LINES do
        local t = k <= n and cut(lines[k], Screen.MAX_TEXT) or nil
        if t and cfg.problemText[k] ~= t then ui.text.set(cfg.problems[k], t); cfg.problemText[k] = t end
        if cfg.problemShown[k] ~= (t ~= nil) then ui.text.setVisible(cfg.problems[k], t ~= nil); cfg.problemShown[k] = t ~= nil end
    end
    local size = self:cfgListSize(n)
    if cfg.listSize.w ~= size.w or cfg.listSize.h ~= size.h then
        cfg.listSize = size
        cfg.list = ui.list.create{ id = "cfg.list", size = size, place = { screen = self.cfgWin, corner = "top-left", gap = "normal" } }
    end
end

function Screen:setCfgMessage(text)
    local cfg = self.cfg
    if not cfg then return end
    local ui = self.ui
    if text then
        text = cut(text, Screen.MAX_TEXT)
        if cfg.msgText ~= text then ui.text.set(cfg.msg, text); cfg.msgText = text end
    end
    if cfg.msgShown ~= (text ~= nil) then ui.text.setVisible(cfg.msg, text ~= nil); cfg.msgShown = text ~= nil end
end

-- What control a declared setting gets: "cb" (bool), "ch" (enum), "sl" (bounded int/number), else "ro" (a text: the
-- value, or SET BY <SOURCE>); every readOnly setting is "ro". Returns kind, and for a slider its step.
function Screen.controlOf(e)
    if e.readOnly then return "ro" end
    if e.type == "bool" then return "cb" end
    if e.type == "enum" and type(e.values) == "table" and #e.values >= 1 and #e.values <= 64 then return "ch" end
    if (e.type == "int" or e.type == "number") and type(e.min) == "number" and type(e.max) == "number" and e.min < e.max then
        local step = type(e.step) == "number" and e.step > 0 and e.step or (e.type == "int" and 1 or (e.max - e.min) / 100)
        if (e.max - e.min) / step <= 10000 + 1e-9 then return "sl", step end
    end
    return "ro"
end

-- A setting's value as text (a read-only control).
function Screen:valueText(e)
    if e.source then return self:fmt("setBy", Screen.clean(e.source, 32):upper()) end
    local v = e.value
    if v == nil then return self:str("unknown") end
    if type(v) == "boolean" then return self:str(v and "on" or "off") end
    if math.type(v) == "integer" then return tostring(v) end
    if type(v) == "number" then return string.format("%.10g", v) end
    return Screen.clean(v, 64)
end

local CONTROL_KINDS = { "cb", "ch", "sl", "ro" }

-- Setting row i (made once).
function Screen:makeSettingRow(i)
    local ui = self.ui
    local p = "s" .. i
    local sc = { row = ui.row.create{ id = p, place = { list = self.cfg.list } }, visible = true, controls = {}, shown = {} }
    sc.lbl = ui.text.create{ id = p .. ".lbl", text = "", place = { row = sc.row, fill = Screen.SETTING_FILL.label }, style = { font = "body", overflow = "ellipsis" } }
    sc.lblText = ""
    self.sCells[i] = sc
    self.sMade = i
    -- Every control kind now, hidden, in the row's order (a row only appends): label, the four controls, the restart
    -- mark. fillSettings shows the one the setting needs and updates it with the same id.
    local place = { row = sc.row, fill = Screen.SETTING_FILL.control }
    local function nop() end
    sc.controls.cb = ui.checkbox.create{ id = p .. ".cb", checked = false, size = Screen.ICON, place = place, onChange = nop }
    sc.controls.ch = ui.choice.create{ id = p .. ".ch", options = { "-" }, place = place, onChange = nop }
    sc.controls.sl = ui.slider.create{ id = p .. ".sl", min = 0, max = 1, step = 1, place = place, onChange = nop }
    sc.controls.ro = ui.text.create{ id = p .. ".ro", text = "", place = place, style = { font = "body", overflow = "ellipsis" } }
    for _, k in ipairs({ "cb", "ch", "sl", "ro" }) do
        ui[({ cb = "checkbox", ch = "choice", sl = "slider", ro = "text" })[k]].setVisible(sc.controls[k], false)
        sc.shown[k] = false
    end
    sc.rs = ui.image.create{ id = p .. ".rs", place = { row = sc.row }, size = Screen.ICON }
    return sc
end

-- The control element for setting i of kind k, updated with its id (core updates it in place).
function Screen:control(i, k, e, step)
    local ui = self.ui
    local sc = self.sCells[i]
    local p = "s" .. i
    local place = { row = sc.row, fill = Screen.SETTING_FILL.control }
    local lobby = e.changeable == "lobby"
    local tip = lobby and self:str("lobbyOnly") or nil
    local h
    if k == "cb" then
        h = ui.checkbox.create{ id = p .. ".cb", checked = e.value == true, size = Screen.ICON, place = place, enabled = not lobby,
            tooltip = tip, onChange = function(_, checked) self:onSettingChange(i, checked) end }
    elseif k == "ch" then
        local opts, sel = {}, 1
        for j, v in ipairs(e.values) do
            local o = Screen.clean(v, 64)
            opts[j] = o ~= "" and o or "-"
            if v == e.value then sel = j end
        end
        h = ui.choice.create{ id = p .. ".ch", options = opts, selected = sel, place = place, enabled = not lobby, tooltip = tip,
            onChange = function(_, index) self:onSettingChange(i, e.values[index]) end }
    elseif k == "sl" then
        local function inRange(v) return type(v) == "number" and v == v and v >= e.min and v <= e.max end
        h = ui.slider.create{ id = p .. ".sl", min = e.min, max = e.max, step = step,
            value = inRange(e.value) and e.value or nil, defaultValue = inRange(e.default) and e.default or nil,
            place = place, enabled = not lobby, tooltip = tip,
            onChange = function(_, value)
                if value == nil then value = e.default end -- Default: the declared default
                if e.type == "int" and type(value) == "number" then value = math.tointeger(value) or value end
                self:onSettingChange(i, value)
            end }
    else
        h = ui.text.create{ id = p .. ".ro", text = self:valueText(e), place = place, style = { font = "body", overflow = "ellipsis" } }
        ui.text.setTooltip(h, tip)
    end
    sc.controls[k] = h
    return h
end

function Screen:onSettingChange(i, value)
    if self.onSetting then self.onSetting(i, value) end
end

local VIS = { cb = "checkbox", ch = "choice", sl = "slider", ro = "text" }

-- New values into the Configure window's settings list: one row per declared setting (at most 64), rows beyond the
-- count hidden, NO SETTINGS when there are none.
function Screen:fillSettings(settings)
    local ui = self.ui
    local cfg = self.cfg
    if not cfg then return end
    settings = settings or {}
    local count = math.min(#settings, Screen.MAX_SETTINGS)
    self.settings = settings
    local none = count == 0
    if cfg.noneShown ~= none then ui.text.setVisible(cfg.none, none); cfg.noneShown = none end
    if none then ui.text.set(cfg.none, self:str("noSettings")) end
    if cfg.listShown ~= not none then ui.list.setVisible(cfg.list, not none); cfg.listShown = not none end
    for i = 1, count do
        local e = settings[i]
        local sc = self.sCells[i] or self:makeSettingRow(i)
        local label = Screen.clean(e.label, 64)
        if label:match("^%s*$") then label = Screen.clean(e.key, 64) end
        if sc.lblText ~= label then ui.text.set(sc.lbl, label); sc.lblText = label end
        local help = Screen.clean(e.help, 256)
        if help:match("^%s*$") then help = nil end
        if sc.help ~= help then ui.text.setTooltip(sc.lbl, help); sc.help = help end
        local k, step = Screen.controlOf(e)
        sc.kind, sc.entry = k, e
        self:control(i, k, e, step)
        for _, other in ipairs(CONTROL_KINDS) do
            local want = other == k
            local h = sc.controls[other]
            if h and sc.shown[other] ~= want then ui[VIS[other]].setVisible(h, want); sc.shown[other] = want end
        end
        -- the restart mark, last in the row: the restart icon for a restart setting (dimmed until its change is
        -- pending), an empty spacer otherwise, so the controls line up
        local rsIcon = e.restart and "restart" or nil
        if sc.rsIcon ~= rsIcon or sc.rsDim ~= (not e.pendingRestart) then
            ui.image.set(sc.rs, { image = rsIcon and { icon = rsIcon } or false, dimmed = not e.pendingRestart })
            sc.rsIcon, sc.rsDim = rsIcon, not e.pendingRestart
        end
        local rsTip = e.restart and self:str("appliesAfterRestart") or nil
        if sc.rsTip ~= rsTip then ui.image.setTooltip(sc.rs, rsTip); sc.rsTip = rsTip end
        if not sc.visible then ui.row.setVisible(sc.row, true); sc.visible = true end
    end
    for i = count + 1, self.sMade do
        local sc = self.sCells[i]
        if sc.visible then ui.row.setVisible(sc.row, false); sc.visible = false end
    end
end

-- Setting i's control back to value, without a callback (a refused or failed set).
function Screen:setControl(i, value)
    local sc = self.sCells[i]
    if not sc or not sc.entry then return end
    local ui, e = self.ui, sc.entry
    local h = sc.controls[sc.kind]
    if sc.kind == "cb" then ui.checkbox.set(h, value == true)
    elseif sc.kind == "ch" then
        for j, v in ipairs(e.values) do if v == value then ui.choice.set(h, j) end end
    elseif sc.kind == "sl" then
        if type(value) == "number" and value >= e.min and value <= e.max then ui.slider.set(h, value) else ui.slider.set(h, nil) end
    end
end

function Screen:openConfigure(n, settings)
    local row = self.data[n]
    if not row then return nil end
    local ui = self.ui
    local l = self:configureLines(row)
    self.cfgRow = n
    if self.cfgMade then
        ui.text.set(self.cfg.title, l.title)
        ui.text.set(self.cfg.ver, l.ver)
        ui.text.set(self.cfg.need, l.need)
        ui.text.set(self.cfg.build, l.build)
        ui.text.set(self.cfg.scope, l.scope)
        self.cfgWin = ui.screen.open{ id = "configure" }
    else
        self.cfgWin = ui.screen.open{ id = "configure" }
        self:buildConfigure(l)
        self.cfgMade = true
    end
    self:setCfgMessage(nil)
    self:setConfigureProblems(row.st and row.st.lines or {})
    self:fillSettings(settings or {})
    return self.cfgWin
end

return Screen
