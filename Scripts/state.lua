-- Mod Manager story 6: the Mod Manager's own state, Mods/ModManager/state.json:
--   {"version":1,"off":[<folders the player turned off here>],"seen":[<alert keys already shown>]}
-- At most 16,384 bytes, 200 off and 32 seen (the oldest dropped). Read once per session with the local json.lua; a
-- missing file is the empty state; a corrupt one is the empty state with one warning, and is rewritten on the next
-- save. Only the Mod Manager reads it in story 6 (the installer learns it in story 7). Written through files.lua's
-- atomic write.
--
--   St.empty() -> state
--   St.decode(text) -> state | nil, err           entries that aren't valid are dropped
--   St.encode(state) -> text | nil, err
--   St.load(fs, path) -> state, warning | nil       never raises
--   St.save(fs, path, state) -> true | nil, err
--   St.setOff(state, folder, off)                    adds (at the end) or removes a folder
--   St.addSeen(state, key)  St.hasSeen(state, key)
local J = require("json")
local Files = require("files")

local St = {}
St.MAX_BYTES = 16384
St.MAX_OFF = 200
St.MAX_SEEN = 32
St.MAX_KEY = 128
local FOLDER = "^[A-Za-z0-9_-]+$"

function St.empty() return { off = {}, seen = {} } end

local function validFolder(v) return type(v) == "string" and #v >= 1 and #v <= 64 and v:match(FOLDER) ~= nil end
local function validKey(v) return type(v) == "string" and #v >= 1 and #v <= St.MAX_KEY and not v:find("[^\32-\126]") end

local function capped(list, max)
    while #list > max do table.remove(list, 1) end -- the oldest first
    return list
end

function St.decode(text)
    if type(text) ~= "string" then return nil, "not text" end
    if #text > St.MAX_BYTES then return nil, string.format("%d bytes, at most %d", #text, St.MAX_BYTES) end
    local v, objects = J.decode(text)
    if v == nil then return nil, objects end
    if not J.isObject(objects, v) then return nil, "not a JSON object" end
    if v.version ~= 1 then return nil, "version is not 1" end
    local st = St.empty()
    local seenF, seenK = {}, {}
    if type(v.off) == "table" and not J.isObject(objects, v.off) then
        for _, f in ipairs(v.off) do
            if validFolder(f) and not seenF[f:lower()] then seenF[f:lower()] = true; st.off[#st.off + 1] = f end
        end
    elseif v.off ~= nil then return nil, "off is not a list" end
    if type(v.seen) == "table" and not J.isObject(objects, v.seen) then
        for _, k in ipairs(v.seen) do
            if validKey(k) and not seenK[k] then seenK[k] = true; st.seen[#st.seen + 1] = k end
        end
    elseif v.seen ~= nil then return nil, "seen is not a list" end
    capped(st.off, St.MAX_OFF)
    capped(st.seen, St.MAX_SEEN)
    return st
end

function St.encode(st)
    local off, seen = {}, {}
    for _, f in ipairs(st.off or {}) do if validFolder(f) then off[#off + 1] = f end end
    for _, k in ipairs(st.seen or {}) do if validKey(k) then seen[#seen + 1] = k end end
    capped(off, St.MAX_OFF)
    capped(seen, St.MAX_SEEN)
    local text = J.encodeState(off, seen)
    if #text > St.MAX_BYTES then return nil, string.format("%d bytes, at most %d", #text, St.MAX_BYTES) end
    return text
end

function St.load(fs, path)
    local okE, exists = pcall(fs.exists, path)
    if not okE or not exists then return St.empty() end
    local okR, text, err = pcall(fs.readFile, path, St.MAX_BYTES)
    if not okR then return St.empty(), "could not be read (" .. tostring(text) .. ")" end
    if not text then return St.empty(), "could not be read (" .. tostring(err) .. ")" end
    local st, why = St.decode(text)
    if not st then return St.empty(), "is not valid (" .. tostring(why) .. ")" end
    return st
end

function St.save(fs, path, st)
    local text, err = St.encode(st)
    if not text then return nil, err end
    return Files.atomicWrite(fs, path, text)
end

function St.setOff(st, folder, off)
    for i = #st.off, 1, -1 do
        if st.off[i]:lower() == folder:lower() then table.remove(st.off, i) end
    end
    if off then st.off[#st.off + 1] = folder; capped(st.off, St.MAX_OFF) end
end

function St.hasSeen(st, key)
    for _, k in ipairs(st.seen) do if k == key then return true end end
    return false
end

function St.addSeen(st, key)
    if not validKey(key) or St.hasSeen(st, key) then return end
    st.seen[#st.seen + 1] = key
    capped(st.seen, St.MAX_SEEN)
end

return St
