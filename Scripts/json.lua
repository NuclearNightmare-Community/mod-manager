-- Mod Manager story 3: a strict, bounded JSON reader for mod.json (RFC 8259). Data is never run as code: no load,
-- no loadfile. The caps are those of core's planned pkg/json.lua (Mod Manager story 5), so story 6 can swap this file
-- for core's reader: input 65,536 bytes, depth 16, 4,096 values in all, strings 1,024 bytes after unescaping.
--
--   J.decode(text) -> value, objects     on success; objects maps every decoded object table to its keys in order
--                  -> nil, "<line>:<col> <reason>"   on any error; never raises
--   J.null                               the value of a JSON null (so nil always means an error)
--   J.isObject(objects, t) -> boolean    t was a JSON object (an array is a plain sequence)
--
--   J.encodeString(s) -> a JSON string literal (story 6: the state file's writer)
--   J.encodeState(off, seen) -> '{"version":1,"off":[...],"seen":[...]}'   exactly the shape of Mods/ModManager/state.json
--
-- Errors: duplicate keys, trailing commas, comments, NaN/Infinity, leading zeros, control characters in strings, lone
-- surrogates, invalid UTF-8, anything after the value. A UTF-8 byte order mark at the start is skipped.
local J = {}

J.MAX_BYTES = 65536
J.MAX_DEPTH = 16
J.MAX_VALUES = 4096
J.MAX_STRING = 1024

J.null = setmetatable({}, { __tostring = function() return "null" end, __newindex = function() error("json.null is read-only", 2) end })

function J.isObject(objects, t) return type(t) == "table" and type(objects) == "table" and objects[t] ~= nil end

local byte, sub, find, char = string.byte, string.sub, string.find, string.char

local ESC = { [34] = '"', [92] = "\\", [47] = "/", [98] = "\b", [102] = "\f", [110] = "\n", [114] = "\r", [116] = "\t" }

local function utf8char(cp)
    if cp < 0x80 then return char(cp) end
    if cp < 0x800 then return char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)) end
    if cp < 0x10000 then return char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)) end
    return char(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
end

-- Strict UTF-8: no overlong forms, no surrogates, nothing above U+10FFFF. Returns the byte offset of the first bad
-- byte, or nil when the whole text is valid.
local function badUtf8(s)
    local i, n = 1, #s
    while i <= n do
        local c = byte(s, i)
        if c < 0x80 then
            i = i + 1
        else
            local len, min
            if c >= 0xC2 and c <= 0xDF then len, min = 2, 0x80
            elseif c >= 0xE0 and c <= 0xEF then len, min = 3, 0x800
            elseif c >= 0xF0 and c <= 0xF4 then len, min = 4, 0x10000
            else return i end
            if i + len - 1 > n then return i end
            local cp = c & (0xFF >> (len + 1))
            for k = 1, len - 1 do
                local d = byte(s, i + k)
                if d < 0x80 or d > 0xBF then return i end
                cp = (cp << 6) | (d & 0x3F)
            end
            if cp < min or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then return i end
            i = i + len
        end
    end
    return nil
end

local function where(s, pos)
    local line, col = 1, 1
    local i = 1
    while i < pos and i <= #s do
        if byte(s, i) == 10 then line, col = line + 1, 1 else col = col + 1 end
        i = i + 1
    end
    return line .. ":" .. col
end

-- The parser state for one decode: s (text), pos, values (count), objects (key orders).
local P = {}
P.__index = P

function P:fail(msg, pos) error({ json = where(self.s, pos or self.pos) .. " " .. msg }, 0) end

function P:ws()
    local _, e = find(self.s, "^[ \t\r\n]*", self.pos)
    self.pos = e + 1
end

function P:count()
    self.values = self.values + 1
    if self.values > J.MAX_VALUES then self:fail("too many values (at most " .. J.MAX_VALUES .. ")") end
end

function P:string()
    local s, start = self.s, self.pos
    local pos = start + 1 -- after the opening quote
    local parts, n, size = {}, 0, 0
    while true do
        local c = byte(s, pos)
        if c == nil then self:fail("unterminated string", start) end
        if c == 34 then break end
        local piece
        if c == 92 then
            local e = byte(s, pos + 1)
            if e == 117 then
                local hex = sub(s, pos + 2, pos + 5)
                if not hex:match("^%x%x%x%x$") then self:fail("bad \\u escape", pos) end
                local cp = tonumber(hex, 16)
                local used = 6
                if cp >= 0xD800 and cp <= 0xDBFF then
                    local lo = sub(s, pos + 6, pos + 11)
                    local lhex = lo:match("^\\u(%x%x%x%x)$")
                    local l = lhex and tonumber(lhex, 16)
                    if not l or l < 0xDC00 or l > 0xDFFF then self:fail("lone surrogate in \\u escape", pos) end
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (l - 0xDC00)
                    used = 12
                elseif cp >= 0xDC00 and cp <= 0xDFFF then
                    self:fail("lone surrogate in \\u escape", pos)
                end
                piece = utf8char(cp)
                pos = pos + used
            else
                piece = e and ESC[e]
                if not piece then self:fail("bad escape", pos) end
                pos = pos + 2
            end
        elseif c < 0x20 then
            self:fail("control character in string", pos)
        else
            local _, e = find(s, '^[^"\\%z\1-\31]+', pos)
            piece = sub(s, pos, e)
            pos = e + 1
        end
        size = size + #piece
        if size > J.MAX_STRING then self:fail("string longer than " .. J.MAX_STRING .. " bytes", start) end
        n = n + 1
        parts[n] = piece
    end
    self.pos = pos + 1
    return table.concat(parts)
end

function P:number()
    local s, start = self.s, self.pos
    -- The strict grammar: -?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?
    local int, frac, exp = s:match("^(-?%d*)(%.?%d*)([eE]?[-+]?%d*)", start)
    if not int then self:fail("bad number") end
    local digits = int:gsub("^-", "")
    if #digits == 0 or (#digits > 1 and digits:sub(1, 1) == "0") then self:fail("bad number (leading zero)") end
    if frac ~= "" and not frac:match("^%.%d+$") then self:fail("bad number (fraction)") end
    if exp ~= "" and not exp:match("^[eE][-+]?%d+$") then self:fail("bad number (exponent)") end
    local whole = int .. frac .. exp
    self.pos = start + #whole
    local v
    if frac == "" and exp == "" then v = math.tointeger(tonumber(whole)) end
    if v == nil then v = tonumber(whole) end
    if v == nil or v ~= v or v == math.huge or v == -math.huge then self:fail("number out of range", start) end
    return v
end

function P:value(depth)
    self:ws()
    local s, pos = self.s, self.pos
    local c = byte(s, pos)
    if c == nil then self:fail("unexpected end of input") end
    self:count()
    if c == 123 then -- {
        if depth >= J.MAX_DEPTH then self:fail("nested deeper than " .. J.MAX_DEPTH) end
        local t, keys, seen = {}, {}, {}
        self.objects[t] = keys
        self.pos = pos + 1
        self:ws()
        if byte(s, self.pos) == 125 then self.pos = self.pos + 1 return t end
        while true do
            self:ws()
            if byte(s, self.pos) ~= 34 then self:fail("expected a string key") end
            local kpos = self.pos
            local k = self:string()
            if seen[k] then self:fail("duplicate key", kpos) end
            seen[k] = true
            self:ws()
            if byte(s, self.pos) ~= 58 then self:fail("expected ':'") end
            self.pos = self.pos + 1
            local v = self:value(depth + 1)
            t[k] = v
            keys[#keys + 1] = k
            self:ws()
            local d = byte(s, self.pos)
            if d == 44 then
                self.pos = self.pos + 1
                self:ws()
                if byte(s, self.pos) == 125 then self:fail("trailing comma") end
            elseif d == 125 then
                self.pos = self.pos + 1
                return t
            else
                self:fail("expected ',' or '}'")
            end
        end
    elseif c == 91 then -- [
        if depth >= J.MAX_DEPTH then self:fail("nested deeper than " .. J.MAX_DEPTH) end
        local t, n = {}, 0
        self.pos = pos + 1
        self:ws()
        if byte(s, self.pos) == 93 then self.pos = self.pos + 1 return t end
        while true do
            local v = self:value(depth + 1)
            n = n + 1
            t[n] = v
            self:ws()
            local d = byte(s, self.pos)
            if d == 44 then
                self.pos = self.pos + 1
                self:ws()
                if byte(s, self.pos) == 93 then self:fail("trailing comma") end
            elseif d == 93 then
                self.pos = self.pos + 1
                return t
            else
                self:fail("expected ',' or ']'")
            end
        end
    elseif c == 34 then
        return self:string()
    elseif c == 45 or (c >= 48 and c <= 57) then
        return self:number()
    elseif sub(s, pos, pos + 3) == "true" then
        self.pos = pos + 4 return true
    elseif sub(s, pos, pos + 4) == "false" then
        self.pos = pos + 5 return false
    elseif sub(s, pos, pos + 3) == "null" then
        self.pos = pos + 4 return J.null
    end
    self:fail("unexpected character")
end

function J.decode(text)
    if type(text) ~= "string" then return nil, "1:1 not text (" .. type(text) .. ")" end
    if #text > J.MAX_BYTES then return nil, "1:1 longer than " .. J.MAX_BYTES .. " bytes" end
    local s = text
    if sub(s, 1, 3) == "\239\187\191" then s = sub(s, 4) end
    local bad = badUtf8(s)
    if bad then return nil, where(s, bad) .. " invalid UTF-8" end
    local p = setmetatable({ s = s, pos = 1, values = 0, objects = {} }, P)
    local ok, v = pcall(function()
        local val = p:value(0)
        p:ws()
        if p.pos <= #s then p:fail("unexpected text after the value") end
        return val
    end)
    if ok then return v, p.objects end
    if type(v) == "table" and v.json then return nil, v.json end
    return nil, "1:1 internal error: " .. tostring(v) -- never expected; still returned, not raised
end

-- ---------------------------------------------------------------- the state file's encoder (story 6)

local ENC = { ['"'] = '\\"', ["\\"] = "\\\\" }
function J.encodeString(v)
    local s = tostring(v):gsub('[%c"\\]', function(c) return ENC[c] or string.format("\\u%04x", c:byte()) end)
    return '"' .. s .. '"'
end

local function stringArray(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = J.encodeString(v) end
    return "[" .. table.concat(out, ",") .. "]"
end

function J.encodeState(off, seen)
    return '{"version":1,"off":' .. stringArray(off) .. ',"seen":' .. stringArray(seen) .. "}"
end

return J
