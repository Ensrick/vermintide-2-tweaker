return function(H, repo_root)
    local core_path = repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_health_multiplier_core.lua"
    local Core = assert(loadfile(core_path))()

    local et_dir = repo_root .. "/enemy_tweaker/scripts/mods/enemy_tweaker"
    local breeds_module_name = "scripts/mods/enemy_tweaker/enemy_tweaker_breeds"
    local Breeds = assert(loadfile(et_dir .. "/enemy_tweaker_breeds.lua"))()

    -- Execute a real shipped module with the breeds require pre-loaded and a
    -- minimal get_mod stub (data file assigns fields on the mod table and
    -- eagerly localizes only the root description).
    local function load_real_module(path)
        local saved_get_mod = rawget(_G, "get_mod")
        local saved_module = package.loaded[breeds_module_name]
        package.loaded[breeds_module_name] = Breeds
        _G.get_mod = function()
            return { localize = function(_, key) return key end }
        end
        local ok, result = pcall(function()
            return assert(loadfile(path))()
        end)
        _G.get_mod = saved_get_mod
        package.loaded[breeds_module_name] = saved_module
        assert(ok, tostring(result))
        return result
    end

    -- Collect every occurrence of setting_id in the widget tree along with
    -- the setting_ids of its ancestor groups.
    local function collect_occurrences(widgets, target_id, ancestors, found)
        for _, widget in ipairs(widgets) do
            if widget.setting_id == target_id then
                local chain = {}
                for _, ancestor in ipairs(ancestors) do
                    chain[ancestor] = true
                end
                found[#found + 1] = { widget = widget, ancestors = chain }
            end
            if type(widget.sub_widgets) == "table" then
                ancestors[#ancestors + 1] = widget.setting_id
                collect_occurrences(widget.sub_widgets, target_id, ancestors, found)
                ancestors[#ancestors] = nil
            end
        end
        return found
    end

    H.test("Enemy Tweaker widget tree parents health multipliers under Enemy Stats (#369)", function()
        local tree = load_real_module(et_dir .. "/enemy_tweaker_data.lua")
        local widgets = tree.options.widgets

        local stats_groups = collect_occurrences(widgets, "enemy_stats_group", {}, {})
        H.equal(#stats_groups, 1, "enemy_stats_group must appear exactly once")
        H.equal(next(stats_groups[1].ancestors), nil, "enemy_stats_group must be top-level")
        H.equal(stats_groups[1].widget.type, "group")

        for _, difficulty in ipairs(Breeds.DIFFICULTIES) do
            local id = Breeds.setting_key(difficulty.key, "health_multiplier")
            local found = collect_occurrences(widgets, id, {}, {})
            H.equal(#found, 1, id .. " must appear exactly once")
            local occurrence = found[1]
            H.truthy(occurrence.ancestors["enemy_stats_group"],
                id .. " must sit under enemy_stats_group")
            H.truthy(occurrence.ancestors["enemy_stats_health_group"],
                id .. " must sit under enemy_stats_health_group")
            H.equal(occurrence.ancestors["special_spawns_group"], nil,
                id .. " must no longer sit under special_spawns_group")

            local widget = occurrence.widget
            H.equal(widget.type, "numeric")
            H.deep_equal(widget.range, { 0.1, 5.0 })
            H.equal(widget.default_value, 1.0)
            H.equal(widget.decimals_number, 1)
        end
    end)

    H.test("Enemy Tweaker localization covers the Enemy Stats rows (#369)", function()
        local loc = load_real_module(et_dir .. "/enemy_tweaker_localization.lua")
        H.truthy(loc.enemy_stats_group and loc.enemy_stats_group.en ~= "",
            "enemy_stats_group loc row missing")
        H.truthy(loc.enemy_stats_health_group and loc.enemy_stats_health_group.en ~= "",
            "enemy_stats_health_group loc row missing")
        for _, difficulty in ipairs(Breeds.DIFFICULTIES) do
            local id = Breeds.setting_key(difficulty.key, "health_multiplier")
            H.truthy(loc[id] and loc[id].en ~= "", id .. " loc row missing")
            H.truthy(loc[id .. "_tooltip"] and loc[id .. "_tooltip"].en ~= "",
                id .. " tooltip loc row missing")
        end
    end)

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("Enemy Tweaker health multiplier clamps invalid values", function()
        H.equal(Core.sanitize_multiplier(nil), 1)
        H.equal(Core.sanitize_multiplier("2.5"), 2.5)
        H.equal(Core.sanitize_multiplier(-4), 0.1)
        H.equal(Core.sanitize_multiplier(99), 5.0)
        H.equal(Core.sanitize_multiplier(0 / 0), 1)
    end)

    H.test("Enemy Tweaker health multiplier targets hostile AI but not pets", function()
        H.truthy(Core.is_hostile_breed({ race = "skaven", boss = true }))
        H.truthy(Core.is_hostile_breed({ race = "undead", unit_template = "ai_unit" }))
        H.equal(Core.is_hostile_breed({ race = "undead", pet_skeleton_type = "tank" }), false)
        H.equal(Core.is_hostile_breed({ race = "undead", unit_template = "ai_unit_pet_skeleton" }), false)
        H.equal(Core.is_hostile_breed({ race = "critter" }), false)
        H.equal(Core.is_hostile_breed({ race = "hero" }), false)
    end)

    H.test("Enemy Tweaker live rescale preserves damage percentage", function()
        H.equal(Core.scaled_max_health(100, 2), 200)
        H.equal(Core.rescaled_damage(100, 25, 200), 50)
        H.equal(Core.rescaled_damage(90, 30, 100), 33.25)
        H.equal(Core.rescaled_damage(100, 120, 50), 50)
    end)

    H.test("Enemy Tweaker health scaling uses one host-authoritative extension hook", function()
        local runtime = read(repo_root .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_health_multiplier.lua")
        local _, hooks = runtime:gsub('mod:hook%("GenericHealthExtension", "init"', "")
        H.equal(hooks, 1)
        H.truthy(runtime:find("Managers.player.is_server", 1, true))
        H.truthy(runtime:find("set_server_damage_taken", 1, true))
        H.equal(runtime:find("Breeds[", 1, true), nil)
    end)
end
