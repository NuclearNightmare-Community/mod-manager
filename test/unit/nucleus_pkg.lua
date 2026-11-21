-- Lets the unit tests require core's pure modules (nucleus.modid) from the Nucleus repo, as the game loads them from
-- Mods/Nucleus/Scripts/nucleus/. test.ps1 puts <Nucleus>/lua/pkg on the Lua path (LUA_PATH "<pkg>/?.lua;;", -Nucleus);
-- run alone, a test falls back to the Nucleus checkout beside this repo (mods/Nucleus). Usage, after ROOT is known:
--   dofile(ROOT .. "/test/unit/nucleus_pkg.lua")(ROOT)
return function(root)
    -- core's own folder first (LUA_PATH from test.ps1, then the sibling checkout): the Mod Manager's Scripts/json.lua must
    -- never stand in for nucleus.json
    local path = (os.getenv("LUA_PATH") or ""):gsub(";;", ";") .. ";" .. root .. "/../Nucleus/lua/pkg/?.lua;" .. package.path
    table.insert(package.searchers, 2, function(name)
        local rest = name:match("^nucleus%.([%w_]+)$")
        if not rest then return nil end
        local file, err = package.searchpath(rest, path)
        if not file then return "\n\t(nucleus_pkg)" .. err end
        return assert(loadfile(file)), file
    end)
end
