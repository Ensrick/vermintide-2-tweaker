return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_weapon_trait_generation.lua"
    local entry_path = root .. "chaos_wastes_tweaker_dev.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local function with_globals(deus_weapons, weapon_traits, body)
        local old_deus = rawget(_G, "DeusWeapons")
        local old_traits = rawget(_G, "WeaponTraits")
        local old_random = math.random
        _G.DeusWeapons = deus_weapons
        _G.WeaponTraits = weapon_traits
        math.random = function() return 1 end
        local ok, err = pcall(body)
        _G.DeusWeapons = old_deus
        _G.WeaponTraits = old_traits
        math.random = old_random
        if not ok then error(err, 0) end
    end

    local function fixture(settings)
        local hooks, order, checks, warnings, debug_rows = {}, {}, {}, {}, {}
        local mod = {
            _ct_umbrella_policy = {},
        }
        function mod._ct_umbrella_policy.banned(master, leaf)
            return master == true or leaf == true
        end
        function mod._ct_umbrella_policy.filter_traits(master, traits, predicate)
            local result, removed = {}, 0
            for _, trait in ipairs(traits or {}) do
                if master or predicate(trait) then
                    removed = removed + 1
                else
                    result[#result + 1] = trait
                end
            end
            return result, removed
        end
        function mod:hook(class_name, method_name, callback)
            H.equal(class_name, "DeusWeaponGeneration")
            H.equal(hooks[method_name], nil, "duplicate hook " .. method_name)
            hooks[method_name] = callback
            order[#order + 1] = method_name
        end
        function mod:warning(...)
            warnings[#warnings + 1] = { ... }
        end

        local function install(current_settings)
            local owner = assert(loadfile(module_path))()
            return owner({
                mod = mod,
                effective_setting = function(id)
                    return current_settings[id]
                end,
                dbg = function(...)
                    debug_rows[#debug_rows + 1] = { ... }
                end,
                rt_register = function(name, check)
                    checks[#checks + 1] = { name = name, check = check }
                end,
            })
        end

        return mod, hooks, order, checks, warnings, debug_rows, install
    end

    local function weapon_fixture()
        return {
            melee = {
                trait_table_name = "deus_melee",
                baked_trait_combinations = {
                    { "melee_increase_damage_on_block" },
                    { "armor_breaker" },
                },
            },
            ranged = {
                trait_table_name = "deus_ranged_heat",
                baked_trait_combinations = {
                    { "ranged_reduce_cooldown_on_crit" },
                    { "ranged_consecutive_hits_increase_power" },
                },
            },
        }, {
            combinations = {
                deus_melee = {
                    { "melee_increase_damage_on_block" },
                    { "armor_breaker" },
                },
                deus_ranged = {
                    { "ranged_reduce_cooldown_on_crit" },
                    { "ranged_consecutive_hits_increase_power" },
                },
            },
        }
    end

    H.test("CT weapon trait owner replaces the original block at one boundary", function()
        local entry = read(entry_path)
        local owner = read(module_path)
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_weapon_trait_generation"), 1)
        H.equal(count_plain(entry, 'mod:hook("DeusWeaponGeneration"'), 0)
        H.equal(count_plain(owner, 'mod:hook("DeusWeaponGeneration"'), 4)
        H.equal(count_plain(owner,
            '_rt_register("tier_by_rarity_class_union_ranged"'), 1)
        H.equal(count_plain(entry, "local all_trait_combos_cache"), 0)
        H.equal(count_plain(entry,
            "mod._ct_reset_weapon_trait_generation_caches()"), 1)

        local install_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_weapon_trait_generation",
            1, true))
        local force_belakor_at = assert(entry:find(
            "Upstream override for `force_belakor`", install_at, true))
        H.truthy(install_at < force_belakor_at)
    end)

    H.test("CT weapon trait owner installs exact hook and check order once", function()
        local settings = {}
        local mod, hooks, order, checks, _, _, install = fixture(settings)
        H.equal(install(settings), true)
        H.deep_equal(order, {
            "generate_weapon",
            "generate_weapon_for_slot",
            "generate_item_from_item_key",
            "upgrade_item",
        })
        H.equal(#checks, 1)
        H.equal(checks[1].name, "tier_by_rarity_class_union_ranged")

        local replacement = { any_trait_any_weapon = true }
        H.equal(install(replacement), false)
        H.equal(#order, 4)
        H.equal(#checks, 1)
        H.equal(type(mod._ct_get_trait_class_pools), "function")
        H.equal(type(mod._ct_strip_banned_traits_from_result), "function")
        H.equal(type(mod._ct_reset_weapon_trait_generation_caches), "function")
        H.equal(type(hooks.generate_weapon), "function")
    end)

    H.test("CT weapon trait hooks preserve nilable vanilla arity", function()
        local deus, traits = weapon_fixture()
        with_globals(deus, traits, function()
            local settings = {}
            local _, hooks, _, _, _, _, install = fixture(settings)
            install(settings)
            local seen
            local result = hooks.generate_item_from_item_key(function(...)
                seen = { n = select("#", ...), ... }
                return { deus_item_key = "ranged", traits = { "native" } }
            end, "ranged", "difficulty", "progress", "common", nil, "tail")
            H.equal(seen.n, 6)
            H.equal(seen[1], "ranged")
            H.equal(seen[2], "difficulty")
            H.equal(seen[3], "progress")
            H.equal(seen[4], "common")
            H.equal(seen[5], nil)
            H.equal(seen[6], "tail")
            H.deep_equal(result.traits, { "native" })
        end)
    end)

    H.test("CT weapon trait filter restores exact tables after vanilla raises", function()
        local deus, traits = weapon_fixture()
        with_globals(deus, traits, function()
            local settings = { any_trait_any_weapon = true }
            local _, hooks, _, _, warnings, debug_rows, install = fixture(settings)
            install(settings)
            local original = deus.melee.baked_trait_combinations
            local ok = pcall(hooks.generate_weapon_for_slot, function()
                H.truthy(deus.melee.baked_trait_combinations ~= original,
                    "filter must be active only inside vanilla generation")
                error("slot failure")
            end, "difficulty", "progress", "rare", nil)
            H.equal(ok, false)
            H.equal(deus.melee.baked_trait_combinations, original)
            H.equal(#debug_rows, 1)
            H.equal(#warnings, 0)

            ok = pcall(hooks.generate_weapon, function()
                error("weapon failure")
            end, "difficulty", "progress", "rare", nil)
            H.equal(ok, false)
            H.equal(deus.melee.baked_trait_combinations, original)
            H.equal(#warnings, 1)
        end)
    end)

    H.test("CT weapon trait tiering and final ban strip preserve policy", function()
        local deus, traits = weapon_fixture()
        with_globals(deus, traits, function()
            local settings = { tweak_trait_tier_by_rarity = true }
            local mod, hooks, _, checks, _, _, install = fixture(settings)
            install(settings)
            local common = hooks.generate_weapon(function()
                return { deus_item_key = "ranged", traits = { "native" } }
            end, "difficulty", "progress", "common")
            H.deep_equal(common.traits, { "ranged_reduce_cooldown_on_crit" })

            local plentiful = hooks.generate_weapon(function()
                return { deus_item_key = "ranged", traits = { "native" } }
            end, "difficulty", "progress", "plentiful")
            H.deep_equal(plentiful.traits, { "native" })

            settings.ban_trait_native = true
            H.deep_equal(mod._ct_strip_banned_traits_from_result({
                traits = { "native", "kept" },
            }).traits, { "kept" })
            H.equal(checks[1].check(), nil)
        end)
    end)

    H.test("CT weapon trait cache reset rebuilds both live catalogues", function()
        local deus, traits = weapon_fixture()
        with_globals(deus, traits, function()
            local settings = { any_trait_any_weapon = true }
            local mod, hooks, _, _, _, _, install = fixture(settings)
            install(settings)
            local first = mod._ct_get_trait_class_pools()
            H.truthy(first.melee.armor_breaker)
            traits.combinations.deus_melee = { { "home_run" } }
            H.equal(mod._ct_get_trait_class_pools(), first)
            mod._ct_reset_weapon_trait_generation_caches()
            local rebuilt = mod._ct_get_trait_class_pools()
            H.truthy(rebuilt.melee.home_run)
            H.equal(rebuilt.melee.armor_breaker, nil)

            _G.WeaponTraits = nil
            mod._ct_reset_weapon_trait_generation_caches()
            local observed
            hooks.generate_weapon(function()
                observed = #deus.melee.baked_trait_combinations
                return { deus_item_key = "melee", traits = {} }
            end, "difficulty", "progress", "rare")
            H.equal(observed, 4)
            deus.extra = {
                trait_table_name = "deus_melee",
                baked_trait_combinations = { { "home_run" } },
            }
            hooks.generate_weapon(function()
                observed = #deus.melee.baked_trait_combinations
                return { deus_item_key = "melee", traits = {} }
            end, "difficulty", "progress", "rare")
            H.equal(observed, 4, "global union must stay cached until reset")
            mod._ct_reset_weapon_trait_generation_caches()
            hooks.generate_weapon(function()
                observed = #deus.melee.baked_trait_combinations
                return { deus_item_key = "melee", traits = {} }
            end, "difficulty", "progress", "rare")
            H.equal(observed, 5)
        end)
    end)
end
