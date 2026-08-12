-- Issue #1271: injected adventure permutations must be registered in both
-- LevelSettings-derived network lookups, and unknown lobby metadata must be
-- filtered without touching the strict NetworkLookup metatable.
return function(H, repo_root)
    local source = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_adventure_pool.lua"

    local old_get_mod = get_mod
    get_mod = function()
        return setmetatable({}, { __index = function() return function() end end })
    end
    local ok, pool = pcall(function()
        return assert(loadfile(source))()
    end)
    get_mod = old_get_mod
    assert(ok, "failed to load _adventure_pool.lua offline: " .. tostring(pool))

    H.test("CT #1271 registers injected missions in both network lookups", function()
        local strict = function(name)
            return setmetatable({ "vanilla", vanilla = 1 }, {
                __index = function(_, key) error(name .. " strict lookup: " .. tostring(key)) end,
            })
        end
        NetworkLookup = {
            level_keys = strict("level_keys"),
            mission_ids = strict("mission_ids"),
        }
        local added = pool.register_network_lookup_key("forest_ambush_khorne_path1")
        H.equal(added, 2)
        H.equal(rawget(NetworkLookup.level_keys, "forest_ambush_khorne_path1"), 2)
        H.equal(rawget(NetworkLookup.mission_ids, "forest_ambush_khorne_path1"), 2)
        H.equal(pool.register_network_lookup_key("forest_ambush_khorne_path1"), 0)
        NetworkLookup = nil
    end)

    H.test("CT #1271 filters unknown lobby missions without strict lookup", function()
        local strict_ids = setmetatable({ "known", known = 1 }, {
            __index = function(_, key) error("strict mission_ids access: " .. tostring(key)) end,
        })
        local known = { id = "a", mission_id = "known" }
        local foreign = { id = "b", mission_id = "foreign_custom" }
        local stale = { id = "c", selected_mission_id = "stale_custom", mission_id = "known" }
        local input = { known, foreign, stale }
        local filtered = pool.filter_lobbies_with_known_missions(input, strict_ids)
        H.equal(#filtered, 1)
        H.equal(filtered[1], known)
        H.equal(#input, 3)
    end)
end
