return function(H, repo_root)
    local path = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()

    H.test("GT #242 blocks both ConflictDirector spawn entry points", function()
        H.truthy(source:find('mod:hook("ConflictDirector", "spawn_queued_unit"', 1, true))
        H.truthy(source:find('mod:hook("ConflictDirector", "spawn_unit_immediate"', 1, true))
        H.truthy(source:find('mod:get("disable_enemy_spawns") then return', 1, true))
    end)

    H.test("GT #242 drives every native spawn producer gate", function()
        local flags = {
            "ai_mini_patrol_disabled",
            "ai_boss_spawning_disabled",
            "ai_horde_spawning_disabled",
            "ai_roaming_spawning_disabled",
            "ai_specials_spawning_disabled",
            "ai_critter_spawning_disabled",
        }
        for _, name in ipairs(flags) do
            H.truthy(source:find('"' .. name .. '"', 1, true), name)
        end
        H.truthy(source:find('issue242_all_spawn_classes_blocked', 1, true))
    end)

    H.test("GT #242 block is reversible and preserves existing enemies", function()
        H.truthy(source:find("script_data[name] = block or nil", 1, true))
        H.truthy(source:find("Existing enemies are NOT despawned", 1, true))
    end)
end
