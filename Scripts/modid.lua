-- Mod Manager story 3: a local copy of the mod id normalizer (_bmad-output/specs/spec-distribution-v0/mod-ids.md,
-- "Normalizer"), until the shared Lua normalizer of distribution story 13 lands; then this file is swapped for it and
-- its shared test cases. It is the rule exactly, nothing more: the legacy bare "nucleus" lives in inventory.lua.
--
--   M.normalize(id) -> the normalized id | nil, message      never raises
--
-- The rule: lowercase; "github.com/<owner>.<mod>" maps to "<owner>.<mod>"; the stored form is "<owner>.<mod>", the
-- mod part (after the last dot) and the GitHub owner of [a-z0-9-] only; any other host, "www.github.com/", "http://"
-- and a bare id without a namespace are refused; at most 200 characters.
local M = {}

M.MAX = 200
M.PREFIX = "github.com/"
local FORMS = "accepted forms: <owner>.<mod> or github.com/<owner>.<mod>"

function M.normalize(id)
    if type(id) ~= "string" then return nil, "an id must be a string, got " .. type(id) end
    if #id == 0 then return nil, "an id is empty" end
    if #id > M.MAX then return nil, string.format("an id is at most %d characters, got %d", M.MAX, #id) end
    local s = id:lower()
    if s:sub(1, #M.PREFIX) == M.PREFIX then s = s:sub(#M.PREFIX + 1) end
    if s:find("/", 1, true) then
        if s:find("://", 1, true) or s:match("^[^/]*github%.com/") then return nil, "'" .. id .. "' is not an id (" .. FORMS .. ")" end
        return nil, "'" .. id .. "' names another host; only GitHub ids are accepted for now (" .. FORMS .. ")"
    end
    if not s:find(".", 1, true) then return nil, "'" .. id .. "' has no namespace (" .. FORMS .. ")" end
    if not s:match("^[a-z0-9%-]+%.[a-z0-9%-]+$") then return nil, "'" .. id .. "' is not an id (" .. FORMS .. ")" end
    return s
end

return M
