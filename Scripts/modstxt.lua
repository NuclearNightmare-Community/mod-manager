-- Mod Manager story 6: mods.txt as a line model that keeps every byte. Pure: no file access.
--
--   M.parse(text) -> model | nil, err     model = { bom = bool, lines = { { body, eol }, ... } }; at most M.MAX bytes
--   M.nameOf(body, first) -> name | nil    the folder a line names, the way UE4SS reads it (nil: UE4SS skips it)
--   M.set(model, folder, on) -> changed    on: every line of folder gets the value 1, and with no line one
--                                          "<folder> : 1" is inserted above the first Keybinds line (else at the
--                                          end); off: every line gets 0, nothing is inserted
--   M.serialize(model) -> text | nil, err  the bytes again; at most M.MAX bytes
--
-- The UE4SS rule (docs/mod-manager-research.md 3.1; UE4SSProgram.cpp start_mods): a line containing ';' anywhere is
-- skipped, so is a line of 4 characters or fewer; spaces are removed and the name is what stands before the first ':'
-- (exact case). Only the value after a line's last ':' changes (written as " 1" or " 0"); the BOM, every other byte,
-- each line's own ending and the file's trailing newline (or its absence) stay as they were. An inserted line takes the
-- file's newline style (CRLF when the file has one, else LF when it has one, else CRLF).
local M = {}

M.MAX = 262144
local BOM = "\239\187\191"

function M.parse(text)
    if type(text) ~= "string" then return nil, "not text" end
    if #text > M.MAX then return nil, string.format("%d bytes, at most %d", #text, M.MAX) end
    local model = { bom = false, lines = {} }
    if text:sub(1, 3) == BOM then model.bom = true; text = text:sub(4) end
    local pos, n = 1, #text
    while pos <= n do
        local nl = text:find("\n", pos, true)
        if not nl then
            local body, eol = text:sub(pos), ""
            if body:sub(-1) == "\r" then body, eol = body:sub(1, -2), "\r" end -- a lone CR at the end stays a CR
            model.lines[#model.lines + 1] = { body = body, eol = eol }
            break
        end
        local line = text:sub(pos, nl - 1)
        local eol = "\n"
        if line:sub(-1) == "\r" then line = line:sub(1, -2); eol = "\r\n" end
        model.lines[#model.lines + 1] = { body = line, eol = eol }
        pos = nl + 1
    end
    return model
end

-- The name a line gives, or nil when UE4SS skips the line (a ';', 4 characters or fewer, no ':').
function M.nameOf(body)
    if type(body) ~= "string" or body:find(";", 1, true) or #body <= 4 then return nil end
    if not body:find(":", 1, true) then return nil end
    local s = body:gsub(" ", "")
    return s:match("^([^:]*)")
end

local function newlineOf(model)
    local lf = false
    for _, l in ipairs(model.lines) do
        if l.eol == "\r\n" then return "\r\n" end
        if l.eol == "\n" then lf = true end
    end
    return lf and "\n" or "\r\n"
end

local function setValue(body, v)
    local last
    local i = 0
    while true do
        i = body:find(":", i + 1, true)
        if not i then break end
        last = i
    end
    return body:sub(1, last) .. " " .. v
end

function M.set(model, folder, on)
    local v = on and "1" or "0"
    local changed, found = false, false
    for _, l in ipairs(model.lines) do
        if M.nameOf(l.body) == folder then
            found = true
            local nb = setValue(l.body, v)
            if nb ~= l.body then l.body = nb; changed = true end
        end
    end
    if on and not found then
        local nl = newlineOf(model)
        local at
        for i, l in ipairs(model.lines) do
            if M.nameOf(l.body) == "Keybinds" then at = i break end
        end
        local line = { body = folder .. " : 1", eol = nl }
        if at then
            table.insert(model.lines, at, line)
        else
            local last = model.lines[#model.lines]
            if last and last.eol ~= "\n" and last.eol ~= "\r\n" then
                -- No trailing newline: the old last line gets one, the new last line keeps the file's "none".
                last.eol = nl
                line.eol = ""
            end
            model.lines[#model.lines + 1] = line
        end
        changed = true
    end
    return changed
end

function M.serialize(model)
    local parts = { model.bom and BOM or "" }
    for _, l in ipairs(model.lines) do parts[#parts + 1] = l.body; parts[#parts + 1] = l.eol end
    local text = table.concat(parts)
    if #text > M.MAX then return nil, string.format("%d bytes, at most %d", #text, M.MAX) end
    return text
end

return M
