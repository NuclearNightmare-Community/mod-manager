-- Mod Manager story 3: the main window and the Configure window, through core.ui only (Nucleus >= 0.8.0 for core.ui; the mod needs 0.12.0).
--
--   local view = Screen.new(ui, strings)
--   view:openMain(rows, lang, size)   opens (or refreshes) the main window with inventory rows; size = { w, h } in
--                                     canvas units (the viewport's layout size; h is 1080 under the game's UI scale)
--   view:openConfigure(n)             opens the Configure window for row n of the last openMain, on top
--
-- Elements are created once per session and reused on every open: a window's elements stay created across closes
-- and attach again on the next open of the same id (core's screen host). Rows are made as they are first needed;
-- rows above the current count are hidden, never removed. Element ids are index-based (r<n>.on, r<n>.name, r<n>.ver,
-- r<n>.st, r<n>.cfg), well inside core's 64-character rule.
--
-- A row: toggle box | name | version | status | gear.
--   toggle box: an image (core icon checkbox-on, checkbox-off, or lock for Nucleus and the Mod Manager), so it is
--               inert: a click does nothing (story 6 makes it the toggle). Tooltip ON / OFF / ALWAYS ON.
--   name, version: texts with fill 4 and 1, cut with an ellipsis at the column edge (core's overflow = "ellipsis").
--   status: an empty text with fill 1, reserved for story 6's icons.
--   gear: an icon-only button, the toggle box's size, tooltip CONFIGURE, dimmed when the mod declares no settings;
--         clickable either way: it opens the Configure window (read-only details, core's Close its only control).
-- The header mirrors a row (spacer, NAME, VERSION, empty status, spacer) in a one-row list of the same width and
-- style, so its labels line up with the columns.
local Screen = {}
Screen.__index = Screen

Screen.ICON = 28           -- the toggle box and the gear, square, canvas units
-- Left and right of the title and the lists, in canvas units: fixed, so a wider screen only widens the columns (at
-- 1280x720 and 1920x1080 the lists are 1200 wide; at 3440x1440, 1860).
Screen.MARGIN = 360
Screen.TITLE_Y = 28
Screen.HEADER_Y = 100
Screen.HEADER_H = 64
Screen.LIST_GAP = 8        -- between the header and the list
Screen.BOTTOM = 48
Screen.FILL = { name = 4, ver = 1, st = 1 }
Screen.CFG_X, Screen.CFG_Y, Screen.CFG_STEP = Screen.MARGIN, 120, 50

function Screen.new(ui, strings)
    return setmetatable({ ui = ui, S = strings, lang = "en", data = {}, made = 0, cells = {}, size = nil,
        main = nil, cfgWin = nil, cfgMade = false }, Screen)
end

function Screen:str(key) return self.S.get(key, self.lang) end

-- The toggle box's icon and tooltip for a row's state.
local TOGGLE = { on = { "checkbox-on", "on" }, off = { "checkbox-off", "off" }, locked = { "lock", "alwaysOn" } }
function Screen.toggleOf(state) return TOGGLE[state] or TOGGLE.off end

-- What a row shows: name, version (UNMANAGED for a pak with no folder, - when unknown).
function Screen:versionText(row)
    if row.pakOnly then return self:str("unmanaged") end
    return row.version or self:str("unknown")
end

local function listSize(size)
    local w = size.w - 2 * Screen.MARGIN
    local h = size.h - Screen.HEADER_Y - Screen.HEADER_H - Screen.LIST_GAP - Screen.BOTTOM
    return { w = w, h = h }
end

-- The lists' places and sizes for a layout size.
function Screen:lists(size)
    local ls = listSize(size)
    local ui = self.ui
    self.hdrList = ui.list.create{ id = "hdr.list", size = { w = ls.w, h = Screen.HEADER_H },
        place = { screen = self.main, absolute = { anchor = "top-left", x = Screen.MARGIN, y = Screen.HEADER_Y } } }
    self.list = ui.list.create{ id = "list", size = ls,
        place = { screen = self.main, absolute = { anchor = "top-left", x = Screen.MARGIN, y = Screen.HEADER_Y + Screen.HEADER_H + Screen.LIST_GAP } } }
    self.size = { w = size.w, h = size.h }
end

-- The title, the header and the two lists: once, on the first open.
function Screen:build(size)
    local ui = self.ui
    self.title = ui.text.create{ id = "title", text = self:str("title"),
        place = { screen = self.main, absolute = { anchor = "top-left", x = Screen.MARGIN, y = Screen.TITLE_Y } }, style = { font = "title" } }
    self:lists(size)
    local hdr = ui.row.create{ id = "hdr", place = { list = self.hdrList } }
    ui.image.create{ id = "hdr.on", place = { row = hdr }, size = Screen.ICON }
    self.hdrName = ui.text.create{ id = "hdr.name", text = self:str("name"), place = { row = hdr, fill = Screen.FILL.name }, style = { font = "body", overflow = "ellipsis" } }
    self.hdrVer = ui.text.create{ id = "hdr.ver", text = self:str("version"), place = { row = hdr, fill = Screen.FILL.ver }, style = { font = "body", overflow = "ellipsis" } }
    ui.text.create{ id = "hdr.st", text = "", place = { row = hdr, fill = Screen.FILL.st }, style = { font = "body" } }
    ui.image.create{ id = "hdr.cfg", place = { row = hdr }, size = Screen.ICON }
end

-- Row n's elements (made once).
function Screen:makeRow(n)
    local ui = self.ui
    local p = "r" .. n
    local row = ui.row.create{ id = p, place = { list = self.list } }
    local tog = Screen.toggleOf("off")
    local c = { row = row, toggle = tog[1], tipText = self:str(tog[2]), dimmed = true, name = "", ver = "" }
    c.on = ui.image.create{ id = p .. ".on", place = { row = row }, image = { icon = tog[1] }, size = Screen.ICON, tooltip = self:str(tog[2]) }
    c.nameH = ui.text.create{ id = p .. ".name", text = "", place = { row = row, fill = Screen.FILL.name }, style = { font = "body", overflow = "ellipsis" } }
    c.verH = ui.text.create{ id = p .. ".ver", text = "", place = { row = row, fill = Screen.FILL.ver }, style = { font = "body", overflow = "ellipsis" } }
    c.st = ui.text.create{ id = p .. ".st", text = "", place = { row = row, fill = Screen.FILL.st }, style = { font = "body" } }
    c.cfgSpec = { id = p .. ".cfg", place = { row = row }, icon = { icon = "gear" }, iconSize = Screen.ICON, dimmed = true,
        tooltip = self:str("configure"), onClick = function() self:onGear(n) end }
    c.cfg = ui.button.create(c.cfgSpec)
    c.cfgTip = c.cfgSpec.tooltip
    c.visible = true
    self.cells[n] = c
    self.made = n
end

-- The gear's click: the caller (main.lua) wraps it in pcall through onGearClick.
function Screen:onGear(n)
    if self.onGearClick then self.onGearClick(n) else self:openConfigure(n) end
end

-- Puts the current data into rows 1..#data and hides the rest. Only what changed is set.
function Screen:fill()
    local ui = self.ui
    for n = self.made + 1, #self.data do self:makeRow(n) end
    if self.hdrName then ui.text.set(self.hdrName, self:str("name")); ui.text.set(self.hdrVer, self:str("version")) end
    if self.title then ui.text.set(self.title, self:str("title")) end
    for n = 1, self.made do
        local c, r = self.cells[n], self.data[n]
        if r then
            local tog = Screen.toggleOf(r.state)
            if c.toggle ~= tog[1] then ui.image.set(c.on, { image = { icon = tog[1] } }); c.toggle = tog[1] end
            local tip = self:str(tog[2])
            if c.tipText ~= tip then ui.image.setTooltip(c.on, tip); c.tipText = tip end
            if c.name ~= r.name then ui.text.set(c.nameH, r.name); c.name = r.name end
            local v = self:versionText(r)
            if c.ver ~= v then ui.text.set(c.verH, v); c.ver = v end
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
        return self.main
    end
    if size and (not self.size or self.size.w ~= size.w or self.size.h ~= size.h) then self:lists(size) end
    self:fill()
    return ui.screen.open{ id = "main" }
end

-- The Configure window's lines for a row: heading, VERSION, NUCLEUS, GAME BUILD.
function Screen:configureLines(row)
    local unknown = self:str("unknown")
    return {
        title = row.name,
        ver = self:str("version") .. " " .. self:versionText(row),
        need = self:str("nucleus") .. " " .. (row.need or unknown),
        build = self:str("gameBuild") .. " " .. (row.build or unknown),
    }
end

function Screen:openConfigure(n)
    local row = self.data[n]
    if not row then return nil end
    local ui = self.ui
    local l = self:configureLines(row)
    if self.cfgMade then
        ui.text.set(self.cfg.title, l.title)
        ui.text.set(self.cfg.ver, l.ver)
        ui.text.set(self.cfg.need, l.need)
        ui.text.set(self.cfg.build, l.build)
        self.cfgWin = ui.screen.open{ id = "configure" }
        return self.cfgWin
    end
    self.cfgWin = ui.screen.open{ id = "configure" }
    local function at(i) return { screen = self.cfgWin, absolute = { anchor = "top-left", x = Screen.CFG_X, y = Screen.CFG_Y + (i - 1) * Screen.CFG_STEP } } end
    self.cfg = {
        title = ui.text.create{ id = "cfg.title", text = l.title, place = { screen = self.cfgWin, absolute = { anchor = "top-left", x = Screen.CFG_X, y = Screen.TITLE_Y } }, style = { font = "title" } },
        ver = ui.text.create{ id = "cfg.ver", text = l.ver, place = at(1), style = { font = "body" } },
        need = ui.text.create{ id = "cfg.need", text = l.need, place = at(2), style = { font = "body" } },
        build = ui.text.create{ id = "cfg.build", text = l.build, place = at(3), style = { font = "body" } },
    }
    self.cfgMade = true
    return self.cfgWin
end

return Screen
