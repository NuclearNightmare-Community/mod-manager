-- Unit tests for Scripts/files.lua over an in-memory fs (test/unit/memfs.lua): the atomic write's steps, every failure
-- leaving the previous file, the .mm-bak restore, renaming aside. Run from the repo root:  texlua test/unit/files_test.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]unit[/\\][^/\\]+$") or "."
package.path = ROOT .. "/Scripts/?.lua;" .. ROOT .. "/test/unit/?.lua;" .. package.path
local Files = require("files")
local MemFs = require("memfs")

local passed, failed = 0, 0
local function ok(cond, name, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL " .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") .. "\n") end
end
local function eq(got, want, name) ok(got == want, name, "got " .. tostring(got) .. ", want " .. tostring(want)) end

local P = "C:\\g\\Mods\\mods.txt"

do -- the happy path: tmp written and read back, target aside, tmp in place, bak removed
    local fs = MemFs.new{ [P] = "old" }
    local okW, err = Files.atomicWrite(fs, P, "new")
    ok(okW, "written", err)
    eq(fs.files[P], "new", "the new bytes")
    eq(fs.names(), P, "no .mm-tmp or .mm-bak left")
    eq(table.concat(fs.log, " | "), "write " .. P .. ".mm-tmp | read " .. P .. ".mm-tmp | rename " .. P .. " -> " .. P .. ".mm-bak | rename " .. P .. ".mm-tmp -> " .. P .. " | remove " .. P .. ".mm-bak",
        "the order: write tmp, read back, target aside, tmp in place, bak removed")
end
do -- a new file (no target yet): no bak step
    local fs = MemFs.new{}
    ok(Files.atomicWrite(fs, P, "x"), "a new file")
    eq(fs.names(), P, "just the file")
end
do -- every failure keeps the previous file and leaves nothing else
    for _, case in ipairs({
        { op = "writeFile", pat = "mm%-tmp$", why = "writing" },
        { op = "readFile", pat = "mm%-tmp$", why = "reading" },
        { op = "rename", pat = "mods%.txt$", why = "aside" },
        { op = "rename", pat = "mm%-tmp$", why = "renaming" },
    }) do
        local fs = MemFs.new{ [P] = "old" }
        fs.fail[case.op] = case.pat
        local okW, err = Files.atomicWrite(fs, P, "new")
        ok(not okW and tostring(err):find(case.why), case.op .. " " .. case.pat .. ": refused with a reason", err)
        eq(fs.files[P], "old", case.op .. " " .. case.pat .. ": the previous file intact")
        eq(fs.names(), P, case.op .. " " .. case.pat .. ": nothing else left")
        ok(not tostring(err):find("C:\\", 1, true), case.op .. ": the reason names no full path")
    end
    local fs = MemFs.new{ [P] = "old" }
    fs.corrupt = "mm%-tmp$"
    local okW, err = Files.atomicWrite(fs, P, "new")
    ok(not okW and err:find("differs") and fs.files[P] == "old" and fs.names() == P, "read back differs: refused, previous file intact")
end
do -- stale leftovers: an old .mm-tmp is replaced, a stale .mm-bak beside a live file is removed first
    local fs = MemFs.new{ [P] = "old", [P .. ".mm-tmp"] = "junk", [P .. ".mm-bak"] = "older" }
    ok(Files.atomicWrite(fs, P, "new"), "with stale leftovers")
    ok(fs.files[P] == "new" and fs.names() == P, "the leftovers gone")
    fs = MemFs.new{ [P] = "old", [P .. ".mm-bak"] = "older" }
    fs.fail.remove = "mm%-bak$"
    local okW = Files.atomicWrite(fs, P, "new")
    ok(not okW and fs.files[P] == "old" and fs.files[P .. ".mm-tmp"] == nil, "a stale bak that can't go: refused, previous intact")
end
do -- the bak's removal failing after the swap: the write stands (the next write clears the bak)
    local fs = MemFs.new{ [P] = "old" }
    fs.fail.remove = "mm%-bak$"
    ok(Files.atomicWrite(fs, P, "new") and fs.files[P] == "new" and fs.files[P .. ".mm-bak"] == "old", "the new file in place; a bak left")
    ok(Files.atomicWrite(fs, P, "newer") and fs.names() == P, "the next write clears it")
end
do -- restore: a write cut short between its renames
    local fs = MemFs.new{ [P .. ".mm-bak"] = "old", [P .. ".mm-tmp"] = "new" }
    eq(Files.restore(fs, P), "restored", "missing target with a .mm-bak: restored")
    eq(fs.files[P], "old", "the previous bytes back")
    fs = MemFs.new{ [P] = "cur", [P .. ".mm-bak"] = "old" }
    eq(Files.restore(fs, P), nil, "target present: nothing restored")
    eq(fs.files[P], "cur", "the live file untouched")
    eq(Files.restore(MemFs.new{}, P), nil, "neither: nothing")
end
do -- renameAside
    local E = "C:\\g\\Mods\\X\\enabled.txt"
    local fs = MemFs.new{ [E] = "", [E .. ".disabled"] = "stale" }
    ok(Files.renameAside(fs, E, E .. ".disabled"), "renamed aside")
    ok(fs.files[E] == nil and fs.files[E .. ".disabled"] == "", "the stale copy replaced")
    fs = MemFs.new{ [E] = "" }
    fs.fail.rename = "enabled%.txt$"
    local okR, err = Files.renameAside(fs, E, E .. ".disabled")
    ok(not okR and err:find("renaming enabled.txt", 1, true) and fs.files[E] == "", "a failed rename: refused, the file stays")
end
eq(Files.base("C:\\Users\\me\\x\\state.json"), "state.json", "base: the last part only")

io.stdout:write(("files_test: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
