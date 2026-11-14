-- Unit tests for Scripts/json.lua: the strict bounded reader (its caps match core's planned pkg/json.lua, Mod Manager
-- story 5). Run from the repo root with any standalone Lua 5.3 or 5.4:  texlua test/unit/json_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
package.path = ROOT .. "/Scripts/?.lua;" .. package.path
local J = require("json")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. tostring(got) .. ", want " .. tostring(want)) end
local function bad(text, wantPart, name)
    local okP, v, err = pcall(J.decode, text)
    ok(okP and v == nil and type(err) == "string" and err:match("^%d+:%d+ ") ~= nil and (not wantPart or err:find(wantPart, 1, true) ~= nil),
        "refused: " .. name, tostring(okP) .. " " .. tostring(v) .. " " .. tostring(err))
end

-- ---------------------------------------------------------------- values
do
    local v, objs = J.decode('{"a": 1, "b": [true, false, null], "c": "x", "d": -0.5e2, "e": {}}')
    ok(type(v) == "table" and J.isObject(objs, v), "an object decodes to a table, marked as an object")
    eq(v.a, 1, "integer"); eq(math.type(v.a), "integer", "an integer stays an integer")
    ok(v.b[1] == true and v.b[2] == false and v.b[3] == J.null and #v.b == 3, "array of true, false, null (null is J.null)")
    ok(not J.isObject(objs, v.b), "an array is not an object")
    eq(v.c, "x", "string"); eq(v.d, -50.0, "number with fraction and exponent")
    ok(J.isObject(objs, v.e) and #objs[v.e] == 0, "empty object, no keys")
    eq(table.concat(objs[v], ","), "a,b,c,d,e", "key order kept")
end
eq(J.decode("3"), 3, "a bare number")
eq(J.decode('"x"'), "x", "a bare string")
eq(J.decode("null"), J.null, "null is J.null, never nil")
eq(J.decode(" \t\r\n true \n"), true, "whitespace around")
eq(J.decode("\239\187\191{}") ~= nil, true, "a UTF-8 BOM is skipped")
eq(J.decode('"\\"\\\\\\/\\b\\f\\n\\r\\t"'), '"\\/\b\f\n\r\t', "every simple escape")
eq(J.decode('"\\u00e9\\u4e2d"'), "\195\169\228\184\173", "\\u escapes to UTF-8")
eq(J.decode('"\\ud83d\\ude00"'), "\240\159\152\128", "a surrogate pair")
eq(J.decode('"caf\195\169"'), "caf\195\169", "raw UTF-8 kept")
eq(J.decode("0"), 0, "zero"); eq(J.decode("-0"), 0, "minus zero"); eq(J.decode("1E3"), 1000.0, "capital exponent")
eq(J.decode("12345678901234"), 12345678901234, "a large integer")

-- ---------------------------------------------------------------- refusals (always nil, "<line>:<col> <reason>")
bad('{"a":1,"a":2}', "duplicate key", "duplicate keys")
bad('{"a":1,}', "trailing comma", "trailing comma in an object")
bad("[1,2,]", "trailing comma", "trailing comma in an array")
bad('{"a":1} // c', "after the value", "a comment after the value")
bad('/* c */ {}', "unexpected character", "a comment before")
bad("NaN", "unexpected character", "NaN"); bad("Infinity", "unexpected character", "Infinity"); bad("-Infinity", "bad number", "-Infinity")
bad("1e999", "out of range", "a number that overflows")
bad("01", "leading zero", "a leading zero"); bad("1.", "fraction", "a bare dot"); bad("1e", "exponent", "a bare exponent"); bad(".5", "unexpected character", "no integer part")
bad("+1", "unexpected character", "a plus sign")
bad('"a\nb"', "control character", "a raw newline in a string")
bad('"\\x"', "bad escape", "an unknown escape")
bad('"\\u12"', "bad \\u", "a short \\u escape")
bad('"\\ud83d"', "lone surrogate", "a lone high surrogate")
bad('"\\ude00"', "lone surrogate", "a lone low surrogate")
bad('"\\ud83d\\u0041"', "lone surrogate", "a high surrogate without its low half")
bad('"abc', "unterminated", "an unterminated string")
bad("{'a':1}", "string key", "a single-quoted key")
bad("{a:1}", "string key", "a bare key")
bad('{"a" 1}', "expected ':'", "a missing colon")
bad("[1 2]", "expected ','", "a missing comma")
bad("", "end of input", "empty input")
bad("   ", "end of input", "only whitespace")
bad("{} {}", "after the value", "two values")
bad("tru", "unexpected character", "a cut literal")
bad('"\255"', "invalid UTF-8", "an invalid byte")
bad('"\192\128"', "invalid UTF-8", "an overlong form")
bad('"\237\160\128"', "invalid UTF-8", "an encoded surrogate")
do -- the error position is the line and column of the problem
    local _, err = J.decode('{\n  "a": 1,\n  "a": 2\n}')
    ok(err ~= nil and err:match("^3:3 "), "duplicate key position 3:3", err)
end
do -- never raises, whatever it gets
    for _, x in ipairs({ 1, true, {}, function() end }) do
        local okP, v, err = pcall(J.decode, x)
        ok(okP and v == nil and type(err) == "string", "not text: " .. type(x), err)
    end
end

-- ---------------------------------------------------------------- caps
do
    local s = string.rep(" ", J.MAX_BYTES - 2) .. "{}"
    ok(J.decode(s) ~= nil, "exactly 65,536 bytes: read")
    bad(s .. " ", "longer than 65536", "65,537 bytes")
    local deep = string.rep("[", 16) .. string.rep("]", 16)
    ok(J.decode(deep) ~= nil, "depth 16: read")
    bad(string.rep("[", 17) .. string.rep("]", 17), "nested deeper than 16", "depth 17")
    bad(string.rep('{"a":', 40) .. "1" .. string.rep("}", 40), "nested deeper", "depth 40 objects")
    local function arr(n) local t = {} for i = 1, n do t[i] = "0" end return "[" .. table.concat(t, ",") .. "]" end
    ok(J.decode(arr(4095)) ~= nil, "4,096 values (an array of 4,095 and the array): read")
    bad(arr(4096), "too many values", "4,097 values")
    ok(J.decode('"' .. string.rep("a", 1024) .. '"') ~= nil, "a 1,024-byte string: read")
    bad('"' .. string.rep("a", 1025) .. '"', "longer than 1024", "a 1,025-byte string")
    bad('"' .. string.rep("\\u00e9", 513) .. '"', "longer than 1024", "1,026 bytes after unescaping")
    ok(J.decode('{"' .. string.rep("k", 1024) .. '":1}') ~= nil, "a 1,024-byte key: read")
end

-- ---------------------------------------------------------------- data is never run
do
    local realLoad, realLoadfile, realDofile = load, loadfile, dofile
    local used = 0
    load = function(...) used = used + 1 return realLoad(...) end
    loadfile = function(...) used = used + 1 return realLoadfile(...) end
    dofile = function(...) used = used + 1 return realDofile(...) end
    J.decode('{"a": "os.exit(1)", "b": [1, 2, {"c": null}]}')
    J.decode("{bad")
    load, loadfile, dofile = realLoad, realLoadfile, realDofile
    eq(used, 0, "decode never calls load, loadfile or dofile")
    local src = assert(io.open(ROOT .. "/Scripts/json.lua", "rb")):read("a"):gsub("%-%-[^\n]*", "")
    ok(not src:find("%f[%w]load%s*%(") and not src:find("loadfile") and not src:find("dofile"), "json.lua has no load/loadfile/dofile call")
end

-- A real mod.json: Clock's shape.
do
    local v, objs = J.decode([[{
  "id": "nuclearnightmare-community.clock", "name": "Clock", "version": "0.1.0", "scope": "client",
  "game": { "version": "V8.2.3", "build": "26601774" },
  "dependsOn": [ { "id": "nuclearnightmare-community.nucleus", "version": ">=0.2.0" } ],
  "settings": { "updateEvery": { "type": "int", "default": 1, "min": 1, "max": 60, "label": "Update every N game minutes" } }
}]])
    ok(v and v.game.build == "26601774" and v.dependsOn[1].version == ">=0.2.0" and J.isObject(objs, v.settings), "Clock's mod.json")
end

io.stdout:write(("json_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
