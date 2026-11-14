-- A fake core.ui for the unit tests (screen_test, main_test): records every call and keeps each element's state, with
-- core's id rule (1-64 of A-Z a-z 0-9 _ . -, unique per mod across kinds; the same kind's id again updates it).
local F = {}

function F.new()
    local U = { calls = {}, els = {}, byId = {}, windows = {}, open = {}, entries = {} }
    local function rec(name, ...) U.calls[#U.calls + 1] = { name = name, args = table.pack(...) } end
    local function handle(kind, id)
        return setmetatable({}, { __index = { id = id }, __newindex = function() error("read-only") end, __metatable = kind .. " handle" })
    end
    local function create(kind, opts)
        assert(type(opts) == "table", kind .. ".create: expected a table")
        local id = opts.id
        assert(type(id) == "string" and #id >= 1 and #id <= 64 and id:match("^[%w_%.%-]+$"), kind .. ".create: bad id " .. tostring(id))
        if U.failOn and U.failOn == id then error("nucleus.ui." .. kind .. ".create: boom", 0) end
        local el = U.byId[id]
        if el then
            assert(el.kind == kind, kind .. ".create: id '" .. id .. "' is already a " .. el.kind)
            el.updates = el.updates + 1
        else
            el = { kind = kind, id = id, visible = true, updates = 0 }
            el.handle = handle(kind, id)
            U.byId[id] = el
            U.els[el.handle] = el
        end
        for k, v in pairs(opts) do el[k] = v end
        rec(kind .. ".create", opts)
        return el.handle
    end
    local function elOf(h) local el = U.els[h] assert(el, "not a handle") return el end
    U.text = {
        create = function(o) return create("text", o) end,
        set = function(h, t) rec("text.set", h, t) elOf(h).text = t end,
        setVisible = function(h, v) rec("text.setVisible", h, v) elOf(h).visible = v end,
        setTooltip = function(h, t) rec("text.setTooltip", h, t) elOf(h).tooltip = t end,
    }
    U.image = {
        create = function(o) return create("image", o) end,
        set = function(h, c) rec("image.set", h, c) local el = elOf(h) for k, v in pairs(c) do el[k] = v end end,
        setTooltip = function(h, t) rec("image.setTooltip", h, t) elOf(h).tooltip = t end,
        setVisible = function(h, v) rec("image.setVisible", h, v) elOf(h).visible = v end,
    }
    U.button = {
        create = function(o) return create("button", o) end,
        setVisible = function(h, v) rec("button.setVisible", h, v) elOf(h).visible = v end,
    }
    U.row = {
        create = function(o) return create("row", o) end,
        setVisible = function(h, v) rec("row.setVisible", h, v) elOf(h).visible = v end,
    }
    U.list = { create = function(o) return create("list", o) end }
    U.screen = {
        open = function(o)
            rec("screen.open", o)
            if U.noMenu then error("nucleus.ui.screen.open: the title-screen menu is not open (windows open only over it)", 0) end
            local w = U.windows[o.id]
            if not w then w = handle("window", o.id) U.windows[o.id] = w end
            U.open[o.id] = true
            return w
        end,
        close = function(w) rec("screen.close", w) U.open[w.id] = nil end,
        isOpen = function(w) return U.open[w.id] == true end,
    }
    U.menu = {
        entry = function(o)
            rec("menu.entry", o)
            if U.failEntry then error("nucleus.ui.menu.entry: boom", 0) end
            U.entries[#U.entries + 1] = o
            return handle("entry", o.id)
        end,
    }
    function U.count(name) local n = 0 for _, c in ipairs(U.calls) do if c.name == name then n = n + 1 end end return n end
    function U.since(i, name) local r = {} for k = i + 1, #U.calls do if not name or U.calls[k].name == name then r[#r + 1] = U.calls[k] end end return r end
    return U
end

return F
