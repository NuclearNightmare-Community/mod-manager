-- A fake core.ui for the unit tests (screen_test, main_test): records every call and keeps each element's state, with
-- core's id rule (1-64 of A-Z a-z 0-9 _ . -, unique per mod across kinds; the same kind's id again updates it).
-- Story 6: checkbox, choice and slider (a real click: U.toggle / U.pick / U.slide, which change the state and call
-- onChange as core does; set never calls back), image.set with false, screen.watch/top/close with reasons
-- (U.back(id) is BACK or Escape), list.setVisible, and a fake core.settings (F.settings).
local F = {}

function F.new()
    local U = { calls = {}, els = {}, byId = {}, windows = {}, open = {}, entries = {}, watchers = {}, order = {} }
    local function rec(name, ...) U.calls[#U.calls + 1] = { name = name, args = table.pack(...) } end
    local function handle(kind, id)
        return setmetatable({}, { __index = { id = id }, __newindex = function() error("read-only") end, __metatable = kind .. " handle" })
    end
    local function create(kind, opts)
        assert(type(opts) == "table", kind .. ".create: expected a table")
        local id = opts.id
        assert(type(id) == "string" and #id >= 1 and #id <= 64 and id:match("^[%w_%.%-]+$"), kind .. ".create: bad id " .. tostring(id))
        if U.failOn and U.failOn == id then error("nucleus.ui." .. kind .. ".create: boom", 0) end
        if opts.tooltip ~= nil then
            assert(type(opts.tooltip) == "string" and #opts.tooltip >= 1 and #opts.tooltip <= 512, kind .. ".create: bad tooltip")
        end
        local el = U.byId[id]
        if el then
            assert(el.kind == kind, kind .. ".create: id '" .. id .. "' is already a " .. el.kind)
            el.updates = el.updates + 1
        else
            el = { kind = kind, id = id, visible = true, updates = 0, enabled = true }
            el.handle = handle(kind, id)
            U.byId[id] = el
            U.els[el.handle] = el
        end
        for k, v in pairs(opts) do el[k] = v end
        if opts.enabled == nil and (kind == "checkbox" or kind == "choice" or kind == "slider" or kind == "button") then el.enabled = true end
        if kind == "text" then
            assert(opts.text == nil or #tostring(opts.text) <= 256, "text.create: over 256 characters (core would WARN)")
        end
        rec(kind .. ".create", opts)
        return el.handle
    end
    local function elOf(h) local el = U.els[h] assert(el, "not a handle") return el end
    local function tip(t) assert(t == nil or (type(t) == "string" and #t >= 1 and #t <= 512), "bad tooltip") return t end
    local function vis(kind) return function(h, v) rec(kind .. ".setVisible", h, v) assert(type(v) == "boolean") elOf(h).visible = v end end
    U.text = {
        create = function(o) return create("text", o) end,
        set = function(h, t) rec("text.set", h, t) assert(#tostring(t) <= 256, "text.set: over 256 characters") elOf(h).text = t end,
        setVisible = vis("text"),
        setTooltip = function(h, t) rec("text.setTooltip", h, t) elOf(h).tooltip = tip(t) end,
    }
    U.image = {
        create = function(o) return create("image", o) end,
        set = function(h, c) rec("image.set", h, c) local el = elOf(h) assert(next(c) ~= nil, "image.set: empty")
            for k, v in pairs(c) do if v == false then el[k] = nil else el[k] = v end end end,
        setTooltip = function(h, t) rec("image.setTooltip", h, t) elOf(h).tooltip = tip(t) end,
        setVisible = vis("image"),
    }
    U.button = {
        create = function(o) return create("button", o) end,
        setVisible = vis("button"),
        setLabel = function(h, l) rec("button.setLabel", h, l) elOf(h).label = l end,
    }
    U.checkbox = {
        create = function(o) assert(type(o.onChange) == "function", "checkbox: onChange") return create("checkbox", o) end,
        set = function(h, c) rec("checkbox.set", h, c) assert(type(c) == "boolean") elOf(h).checked = c end,
        get = function(h) return elOf(h).checked == true end,
        setEnabled = function(h, e) rec("checkbox.setEnabled", h, e) elOf(h).enabled = e end,
        setTooltip = function(h, t) rec("checkbox.setTooltip", h, t) elOf(h).tooltip = tip(t) end,
        setVisible = vis("checkbox"),
    }
    U.choice = {
        create = function(o)
            assert(type(o.options) == "table" and #o.options >= 1 and #o.options <= 64, "choice: options")
            for _, s in ipairs(o.options) do assert(type(s) == "string" and #s >= 1 and #s <= 64, "choice: option") end
            local h = create("choice", o)
            local el = elOf(h)
            el.index = o.selected or 1
            return h
        end,
        set = function(h, i) rec("choice.set", h, i) elOf(h).index = i end,
        get = function(h) local el = elOf(h) return el.index, el.options[el.index] end,
        setEnabled = function(h, e) rec("choice.setEnabled", h, e) elOf(h).enabled = e end,
        setTooltip = function(h, t) rec("choice.setTooltip", h, t) elOf(h).tooltip = tip(t) end,
        setVisible = vis("choice"),
    }
    U.slider = {
        create = function(o)
            assert(type(o.min) == "number" and type(o.max) == "number" and o.min < o.max and o.step > 0, "slider: range")
            assert((o.max - o.min) / o.step <= 10000 + 1e-9, "slider: over 10,000 steps")
            assert(o.value == nil or (o.value >= o.min and o.value <= o.max), "slider: value out of range")
            return create("slider", o)
        end,
        set = function(h, v) rec("slider.set", h, v) elOf(h).value = v end,
        get = function(h) return elOf(h).value end,
        setEnabled = function(h, e) rec("slider.setEnabled", h, e) elOf(h).enabled = e end,
        setTooltip = function(h, t) rec("slider.setTooltip", h, t) elOf(h).tooltip = tip(t) end,
        setVisible = vis("slider"),
    }
    U.row = { create = function(o) return create("row", o) end, setVisible = vis("row") }
    U.list = { create = function(o) return create("list", o) end, setVisible = vis("list") }
    local function dispatch(info) for _, w in ipairs(U.watchers) do w(U.windows[info.id], info) end end
    local function closeOne(id, reason)
        U.open[id] = nil
        for i = #U.order, 1, -1 do if U.order[i] == id then table.remove(U.order, i) end end
        dispatch({ event = "closed", id = id, reason = reason })
    end
    local function closeWith(id, reason)
        local idx
        for i, o in ipairs(U.order) do if o == id then idx = i end end
        if not idx then return end
        for i = #U.order, idx + 1, -1 do closeOne(U.order[i], "parent") end
        closeOne(id, reason)
    end
    U.screen = {
        open = function(o)
            rec("screen.open", o)
            if U.noMenu then error("nucleus.ui.screen.open: the title-screen menu is not open (windows open only over it)", 0) end
            local w = U.windows[o.id]
            if not w then w = handle("window", o.id) U.windows[o.id] = w end
            if not U.open[o.id] then
                U.open[o.id] = true
                U.order[#U.order + 1] = o.id
                dispatch({ event = "opened", id = o.id, reason = "screen.open" })
            end
            return w
        end,
        close = function(w) rec("screen.close", w) closeWith(w.id, "api") end,
        isOpen = function(w) return U.open[w.id] == true end,
        top = function() local id = U.order[#U.order] return id and U.windows[id] or nil end,
        watch = function(fn) rec("screen.watch", fn) U.watchers[#U.watchers + 1] = fn return #U.watchers end,
    }
    U.menu = {
        entry = function(o)
            rec("menu.entry", o)
            if U.failEntry then error("nucleus.ui.menu.entry: boom", 0) end
            U.entries[#U.entries + 1] = o
            return handle("entry", o.id)
        end,
    }
    -- A player's input: BACK (or Escape) on a window; a click on a checkbox; an arrow of a choice; a slider's commit.
    function U.back(id) closeWith(id, "close") end
    function U.lose() for i = #U.order, 1, -1 do closeOne(U.order[i], "lost") end end
    function U.toggle(id)
        local el = U.byId[id]
        assert(el and el.kind == "checkbox", "no checkbox " .. id)
        if not el.enabled or not el.visible then return false end
        el.checked = not el.checked
        el.onChange(el.handle, el.checked)
        return true
    end
    function U.pick(id, index)
        local el = U.byId[id]
        assert(el and el.kind == "choice", "no choice " .. id)
        if not el.enabled or index == el.index then return false end
        el.index = index
        el.onChange(el.handle, index, el.options[index])
        return true
    end
    function U.slide(id, value)
        local el = U.byId[id]
        assert(el and el.kind == "slider", "no slider " .. id)
        if not el.enabled or value == el.value then return false end
        el.value = value
        el.onChange(el.handle, value)
        return true
    end
    function U.count(name) local n = 0 for _, c in ipairs(U.calls) do if c.name == name then n = n + 1 end end return n end
    function U.since(i, name) local r = {} for k = i + 1, #U.calls do if not name or U.calls[k].name == name then r[#r + 1] = U.calls[k] end end return r end
    return U
end

-- A fake core.settings over declarations (folder -> { settings = { entries } }), with setFor's refusals scripted:
-- Z.refuse = "write-failed disk full" makes the next setFor return false, that; Z.raise = "msg" makes it raise.
function F.settings(decls)
    local Z = { decls = decls or {}, sets = {}, describes = 0 }
    local function find(folder, key)
        local d = Z.decls[folder]
        if not d then return nil end
        for _, e in ipairs(d.settings) do if e.key == key then return e end end
    end
    function Z.describe(folder)
        Z.describes = Z.describes + 1
        local d = Z.decls[folder]
        if not d then return nil, "unknown-mod " .. tostring(folder) end
        local out = { settings = {} }
        for i, e in ipairs(d.settings) do
            local c = {}
            for k, v in pairs(e) do c[k] = v end
            out.settings[i] = c
        end
        return out
    end
    function Z.setFor(folder, key, value)
        Z.sets[#Z.sets + 1] = { folder = folder, key = key, value = value }
        if Z.raise then local m = Z.raise; Z.raise = nil; error(m, 0) end
        if Z.refuse then local r = Z.refuse; Z.refuse = nil; return false, r end
        local e = find(folder, key)
        if not e then error("nucleus.settings.setFor: unknown key " .. tostring(key), 0) end
        if e.restart then
            e.saved = value
            e.pendingRestart = value ~= e.value
        else
            e.value = value
        end
        return true
    end
    return Z
end

return F
