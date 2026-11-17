-- Unit tests for Scripts/state.lua and json.lua's state encoder: the exact shape, the caps (oldest dropped), invalid
-- entries dropped, missing and corrupt files, the atomic save. Run from the repo root:  texlua test/unit/state_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
package.path = ROOT .. "/Scripts/?.lua;" .. ROOT .. "/test/unit/?.lua;" .. package.path
local St = require("state")
local J = require("json")
local MemFs = require("memfs")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. tostring(got) .. ", want " .. tostring(want)) end

local P = "C:\\g\\Mods\\ModManager\\state.json"

-- the encoder: exactly the shape
eq(J.encodeState({}, {}), '{"version":1,"off":[],"seen":[]}', "empty state")
eq(J.encodeState({ "A", "B" }, { "nucleus-build 0.12.1 V9.0.0" }), '{"version":1,"off":["A","B"],"seen":["nucleus-build 0.12.1 V9.0.0"]}', "folders and keys")
eq(J.encodeString('a"b\\c\n'), '"a\\"b\\\\c\\u000a"', "escapes")
do local v = J.decode(J.encodeString("x\1\127\"\\")) ok(v == "x\1\127\"\\", "the escapes decode back") end

do -- decode
    local st = St.decode('{"version":1,"off":["ModManagerDep","bad name!","ModManagerDep",3],"seen":["k1","",' .. '"' .. string.rep("k", 129) .. '"]}')
    ok(st and table.concat(st.off, ",") == "ModManagerDep" and table.concat(st.seen, ",") == "k1", "invalid and duplicate entries dropped")
    ok(St.decode('{"version":2,"off":[],"seen":[]}') == nil, "another version: refused")
    ok(St.decode('{"off":') == nil, "corrupt: refused")
    ok(St.decode('[1]') == nil, "not an object: refused")
    ok(St.decode('{"version":1,"off":{}}') == nil, "off not a list: refused")
    ok(St.decode('{"version":1}') ~= nil, "no lists: empty lists")
    ok(St.decode(string.rep(" ", St.MAX_BYTES + 1)) == nil, "over 16,384 bytes: refused")
end
do -- caps: 200 off, 32 seen, the oldest dropped
    local st = St.empty()
    for i = 1, 205 do St.setOff(st, "M" .. i, true) end
    eq(#st.off, 200, "200 off")
    eq(st.off[1], "M6", "the oldest dropped")
    for i = 1, 40 do St.addSeen(st, "k" .. i) end
    eq(#st.seen, 32, "32 seen")
    eq(st.seen[1], "k9", "the oldest key dropped")
    ok(St.hasSeen(st, "k40") and not St.hasSeen(st, "k1"), "hasSeen")
    St.setOff(st, "m200", false)
    ok(not table.concat(st.off, ","):find("M200,", 1, true) and st.off[#st.off] == "M205", "removed by folder, any case")
    St.setOff(st, "M205", true)
    eq(st.off[#st.off], "M205", "turned off again: once, at the end")
    local n = 0 for _, f in ipairs(st.off) do if f == "M205" then n = n + 1 end end
    eq(n, 1, "no duplicate")
    local text = assert(St.encode(st))
    ok(#text <= St.MAX_BYTES, "200 off and 32 seen fit in 16,384 bytes")
    local back = St.decode(text)
    ok(back and #back.off == #st.off and #back.seen == 32, "round trip")
    St.addSeen(st, "bad\1key"); St.addSeen(st, "")
    ok(not St.hasSeen(st, "bad\1key"), "a key with a control character is not kept")
end
do -- load: missing, valid, corrupt, unreadable; save: atomic
    local fs = MemFs.new{}
    local st, why = St.load(fs, P)
    ok(#st.off == 0 and #st.seen == 0 and why == nil, "missing: empty, no warning")
    fs.files[P] = '{"off":'
    st, why = St.load(fs, P)
    ok(#st.off == 0 and why and why:find("not valid"), "corrupt: empty, one warning")
    St.setOff(st, "ModManagerDep", true)
    ok(St.save(fs, P, st), "saved over the corrupt file")
    eq(fs.files[P], '{"version":1,"off":["ModManagerDep"],"seen":[]}', "rewritten in the exact shape")
    eq(fs.names(), P, "no .mm-tmp or .mm-bak left")
    st = St.load(fs, P)
    eq(st.off[1], "ModManagerDep", "read back")
    fs.fail.readFile = "state"
    st, why = St.load(fs, P)
    ok(#st.off == 0 and why:find("could not be read"), "unreadable: empty, one warning")
    fs.fail.writeFile = "mm%-tmp"
    local okS, err = St.save(fs, P, St.empty())
    ok(not okS and err and fs.files[P] == '{"version":1,"off":["ModManagerDep"],"seen":[]}', "a failed save: the previous file intact")
end

io.stdout:write(("state_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
