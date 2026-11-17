-- Unit tests for Scripts/modstxt.lua: the UE4SS line rule, flips that change only the value bytes (CRLF, LF, BOM, no
-- trailing newline), the Keybinds insertion, the size cap. Run from the repo root:  texlua test/unit/modstxt_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
package.path = ROOT .. "/Scripts/?.lua;" .. package.path
local M = require("modstxt")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. string.format("%q", tostring(got)) .. ", want " .. string.format("%q", tostring(want))) end

local function flip(text, folder, on)
    local m = assert(M.parse(text))
    local changed = M.set(m, folder, on)
    return assert(M.serialize(m)), changed
end

-- the UE4SS rule
eq(M.nameOf("Foo : 1"), "Foo", "name before the first ':', spaces removed")
eq(M.nameOf(" F o o:1"), "Foo", "spaces anywhere removed")
eq(M.nameOf("Foo : 1 ; on"), nil, "a ';' anywhere: skipped")
eq(M.nameOf("A:1"), nil, "4 characters or fewer: skipped")
eq(M.nameOf("Abc:1"), "Abc", "5 characters: read")
eq(M.nameOf("FooBar"), nil, "no ':': skipped")
eq(M.nameOf("foo : 1"), "foo", "exact case kept")

do -- CRLF + BOM: only the value bytes change; round trip back to the same bytes
    local t = "\239\187\191Nucleus : 1\r\nModManagerDep : 1\r\nKeybinds : 1\r\n"
    local off, ch = flip(t, "ModManagerDep", false)
    eq(off, "\239\187\191Nucleus : 1\r\nModManagerDep : 0\r\nKeybinds : 1\r\n", "CRLF+BOM: off flips the value only")
    ok(ch, "off: changed")
    local on = flip(off, "ModManagerDep", true)
    eq(on, t, "back on: the session start's bytes")
    local same, ch2 = flip(t, "ModManagerDep", true)
    ok(same == t and not ch2, "on when already on: nothing changes")
end
do -- LF, no trailing newline, odd spacing: every line of the folder; other bytes kept
    local t = "ModManagerDep:1\nOther : 1\nModManagerDep  :  1\nModManagerDep : 1 ; comment\nKeybinds : 1"
    local off = flip(t, "ModManagerDep", false)
    eq(off, "ModManagerDep: 0\nOther : 1\nModManagerDep  : 0\nModManagerDep : 1 ; comment\nKeybinds : 1", "every matching line flipped; ';' lines untouched; no trailing newline kept")
    eq(flip("Foo : x : 1\n", "Foo", false), "Foo : x : 0\n", "only after the last ':'")
    eq(flip("Foo : 10\n", "Foo", false), "Foo : 0\n", "the whole value replaced")
end
do -- off with no line: nothing inserted
    local t = "Nucleus : 1\r\nKeybinds : 1\r\n"
    local same, ch = flip(t, "ModManagerBare", false)
    ok(same == t and not ch, "off, no line: none inserted, no change")
end
do -- on with no line: inserted above the first Keybinds line, in the file's newline style
    eq(flip("Nucleus : 1\r\nKeybinds : 1\r\nKeybinds : 1\r\n", "ModManagerBare", true),
        "Nucleus : 1\r\nModManagerBare : 1\r\nKeybinds : 1\r\nKeybinds : 1\r\n", "CRLF: above the first Keybinds")
    eq(flip("Nucleus : 1\nKeybinds : 1\n", "Bare", true), "Nucleus : 1\nBare : 1\nKeybinds : 1\n", "LF: LF")
    eq(flip("; Keybinds : 1\nNucleus : 1\n", "Bare", true), "; Keybinds : 1\nNucleus : 1\nBare : 1\n", "no real Keybinds line: at the end")
    eq(flip("Nucleus : 1", "Bare", true), "Nucleus : 1\r\nBare : 1", "no newline at all: CRLF between, still none at the end")
    eq(flip("Nucleus : 1\r", "Bare", true), "Nucleus : 1\r\nBare : 1", "a lone CR at the end becomes the line's ending")
    eq(flip("", "Bare", true), "Bare : 1\r\n", "an empty file: one line")
    eq(flip("\239\187\191", "Bare", true), "\239\187\191Bare : 1\r\n", "a BOM only: kept")
    eq(flip("\239\187\191Keybinds : 1\n", "Bare", true), "\239\187\191Bare : 1\nKeybinds : 1\n", "BOM kept, Keybinds on the first line found")
end
do -- the cap
    local big = string.rep("x", M.MAX + 1)
    local m, err = M.parse(big)
    ok(m == nil and err:find("at most"), "over 262,144 bytes: refused")
    local fit = string.rep("A", M.MAX - 20) .. "\nFoo : 1\n" -- 262,132 bytes; inserting a line pushes it over
    local mm = assert(M.parse(fit))
    M.set(mm, "Barbazquux", true)
    local s, e = M.serialize(mm)
    ok(s == nil and e:find("at most"), "a result over the cap: refused")
    ok(M.parse(nil) == nil, "not text: refused")
end

io.stdout:write(("modstxt_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
