local mod = get_mod("ct")

local MOD_VERSION = "0.3.0-dev"
mod:info("Chaos Wastes Tweaker v%s loaded", MOD_VERSION)
mod:echo("Chaos Wastes Tweaker v" .. MOD_VERSION)

local SHRINE_DEFAULT = 4
local CHEST_DEFAULT = 3
local FINALE_GODS = { "nurgle", "tzeentch", "khorne", "slaanesh" }

local granting_starting_coins = false
local all_trait_combos_cache = nil
local sync_reckless_swings

local function is_curse_disabled(curse_name)
    if type(curse_name) ~= "string" or not curse_name:find("^curse_") then
        return false
    end

    local key = "disable_curse_" .. curse_name:gsub("^curse_", "")
    return mod:get(key) == true
end

mod:hook("DeusRunController", "on_soft_currency_picked_up", function(func, self, ...)
    local args = { ... }
    local raw_amount = args[1]

    if type(raw_amount) == "number" and not granting_starting_coins then
        local multiplier = mod:get("coin_multiplier") or 1
        args[1] = math.max(1, math.floor(raw_amount * multiplier))
    end

    return func(self, unpack(args))
end)

mod:hook_safe("DeusRunController", "setup_run", function(self)
    local starting = mod:get("starting_coins")
    if starting and starting > 0 and self.on_soft_currency_picked_up then
        granting_starting_coins = true
        self:on_soft_currency_picked_up(starting)
        granting_starting_coins = false
    end
end)

mod:hook("DeusPowerUpUtils", "generate_random_power_ups", function(func, ...)
    local args = { ... }

    local count_index
    for index, value in ipairs(args) do
        if type(value) == "number" and value >= 1 and value <= 10 then
            count_index = index
            break
        end
    end

    if count_index then
        local original = args[count_index]
        local custom_count

        if original == SHRINE_DEFAULT then
            custom_count = mod:get("shrine_boon_count")
        elseif original == CHEST_DEFAULT then
            custom_count = mod:get("chest_boon_count")
        end

        if custom_count and custom_count ~= original then
            args[count_index] = custom_count
        end
    end

    local removed_main = {}
    local removed_rarity = {}

    if DeusPowerUpsArray then
        for i = #DeusPowerUpsArray, 1, -1 do
            local boon = DeusPowerUpsArray[i]
            local key = boon and boon.name and ("disable_boon_" .. boon.name)
            if key and mod:get(key) then
                table.remove(DeusPowerUpsArray, i)
                removed_main[#removed_main + 1] = { index = i, boon = boon }
            end
        end
        if DeusPowerUpsArrayByRarity then
            for rarity, arr in pairs(DeusPowerUpsArrayByRarity) do
                removed_rarity[rarity] = {}
                for i = #arr, 1, -1 do
                    local boon = arr[i]
                    local key = boon and boon.name and ("disable_boon_" .. boon.name)
                    if key and mod:get(key) then
                        table.remove(arr, i)
                        removed_rarity[rarity][#removed_rarity[rarity] + 1] = { index = i, boon = boon }
                    end
                end
            end
        end
    end

    local new_seed, new_power_ups = func(unpack(args))

    for i = #removed_main, 1, -1 do
        local e = removed_main[i]
        table.insert(DeusPowerUpsArray, e.index, e.boon)
    end
    for rarity, removed in pairs(removed_rarity) do
        local arr = DeusPowerUpsArrayByRarity[rarity]
        for i = #removed, 1, -1 do
            local e = removed[i]
            table.insert(arr, e.index, e.boon)
        end
    end

    sync_reckless_swings()

    return new_seed, new_power_ups
end)

local function fix_arc_nan(widgets)
    if not widgets or #widgets ~= 1 then
        return
    end

    local widget = widgets[1]
    if widget and widget.offset then
        if widget.offset[1] ~= widget.offset[1] then
            widget.offset[1] = 0
        end
        if widget.offset[2] ~= widget.offset[2] then
            widget.offset[2] = 0
        end
    end
end

mod:hook_safe("DeusShopView", "_create_ui_elements", function(self)
    fix_arc_nan(self._shop_item_widgets)
end)

mod:hook_safe("DeusCursedChestView", "create_ui_elements", function(self)
    fix_arc_nan(self._power_up_widgets)
end)

mod:hook("MutatorHandler", "_activate_mutator", function(func, self, name, ...)
    if is_curse_disabled(name) then
        return
    end
    return func(self, name, ...)
end)

mod:hook("DeusMechanism", "get_current_node_curse", function(func, self, ...)
    local curse = func(self, ...)
    if is_curse_disabled(curse) then
        return nil
    end
    return curse
end)

mod:hook("DeusMechanism", "_transition_next_node", function(func, self, next_node_key, ...)
    local run_controller = self._deus_run_controller
    local graph_data = run_controller and run_controller:get_graph_data()
    local node = graph_data and graph_data[next_node_key]
    local saved_curse = node and node.curse

    if saved_curse and is_curse_disabled(saved_curse) then
        node.curse = nil
    end

    local results = { func(self, next_node_key, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        node.curse = saved_curse
    end

    return unpack(results)
end)

mod:hook("DeusMechanism", "start_next_round", function(func, self, ...)
    local run_controller = self._deus_run_controller
    local current_node = run_controller and run_controller:get_current_node()
    local saved_curse = current_node and current_node.curse
    local saved_theme = current_node and current_node.theme

    if saved_curse and is_curse_disabled(saved_curse) then
        current_node.curse = nil
        current_node.theme = "wastes"
    end

    local results = { func(self, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        current_node.curse = saved_curse
        current_node.theme = saved_theme
    end

    return unpack(results)
end)

mod:hook("DeusMapDecisionView", "_enable_hover", function(func, self, node_key, ...)
    local graph_data = self._deus_run_controller and self._deus_run_controller:get_graph_data()
    local node = graph_data and graph_data[node_key]

    if node and is_curse_disabled(node.curse) then
        local saved_theme = node.theme
        node.theme = nil
        func(self, node_key, ...)
        node.theme = saved_theme
        return
    end

    return func(self, node_key, ...)
end)

mod:hook("DeusRunController", "get_deus_weapon_chest_type", function(func, self)
    local distribution = self._deus_weapon_chest_distribution

    if (not distribution or #distribution == 0) and DEUS_CHEST_TYPES then
        local upgrade = mod:get("chest_upgrade_count") or 0
        local swap_melee = mod:get("chest_swap_melee_count") or 0
        local swap_ranged = mod:get("chest_swap_ranged_count") or 0
        local power_up = mod:get("chest_power_up_count") or 0

        local is_custom = upgrade > 0 or swap_melee > 0 or swap_ranged > 0 or power_up > 0
        if is_custom then
            local new_distribution = {}
            for _ = 1, upgrade do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.upgrade end
            for _ = 1, swap_melee do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.swap_melee end
            for _ = 1, swap_ranged do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.swap_ranged end
            for _ = 1, power_up do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.power_up end

            if #new_distribution > 0 then
                local run_state = self._run_state
                local node_key = run_state and run_state:get_current_node_key()
                local graph = self:_get_graph_data()
                local node = graph and node_key and graph[node_key]
                local seed = node and HashUtils and HashUtils.fnv32_hash(node.level_seed) or 0
                table.shuffle(new_distribution, seed)

                self._deus_weapon_chest_distribution = new_distribution
                local chest_type = new_distribution[#new_distribution]
                new_distribution[#new_distribution] = nil
                return chest_type
            end
        end
    end

    return func(self)
end)

local function get_all_trait_combos()
    if all_trait_combos_cache then
        return all_trait_combos_cache
    end
    if not DeusWeapons then
        return nil
    end

    local combos = {}
    local seen = {}
    for _, data in pairs(DeusWeapons) do
        local baked = data.baked_trait_combinations
        if baked then
            for _, combo in ipairs(baked) do
                local key = table.concat(combo, "\0")
                if not seen[key] then
                    seen[key] = true
                    combos[#combos + 1] = combo
                end
            end
        end
    end

    all_trait_combos_cache = combos
    return combos
end

local function apply_weapon_trait_filter()
    if not DeusWeapons then
        return {}
    end

    local any_trait = mod:get("any_trait_any_weapon")
    local expanded_pool = any_trait and get_all_trait_combos()
    local saved = {}

    for item_key, data in pairs(DeusWeapons) do
        local original = data.baked_trait_combinations
        local base = expanded_pool or original
        if base then
            local filtered = {}
            for _, combo in ipairs(base) do
                local keep = true
                for _, trait in ipairs(combo) do
                    if mod:get("ban_trait_" .. trait) then
                        keep = false
                        break
                    end
                end
                if keep then
                    filtered[#filtered + 1] = combo
                end
            end

            local new_value
            if #filtered < #base and #filtered > 0 then
                new_value = filtered
            elseif #filtered == 0 then
                new_value = base
            elseif base ~= original then
                new_value = base
            end

            if new_value and new_value ~= original then
                saved[item_key] = original
                data.baked_trait_combinations = new_value
            end
        end
    end

    return saved
end

local function restore_weapon_trait_filter(saved)
    if not DeusWeapons then
        return
    end

    for item_key, original in pairs(saved) do
        DeusWeapons[item_key].baked_trait_combinations = original
    end
end

mod:hook("DeusWeaponGeneration", "generate_weapon", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

mod:hook("DeusWeaponGeneration", "generate_weapon_for_slot", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

mod:hook("DeusWeaponGeneration", "upgrade_item", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

mod:hook("DeusMechanism", "_setup_run", function(func, self, run_id, run_seed, is_server, server_peer_id, difficulty, journey_name, dominant_god, with_belakor, mutators, boons)
    if is_server then
        if mod:get("force_belakor") then
            with_belakor = true
        end

        local god_index = mod:get("finale_dominant_god")
        if god_index and god_index > 0 then
            local god = FINALE_GODS[god_index]
            if god then
                dominant_god = god
            end
        end
    end

    return func(self, run_id, run_seed, is_server, server_peer_id, difficulty, journey_name, dominant_god, with_belakor, mutators, boons)
end)

mod:hook("PickupSystem", "populate_pickups", function(func, self, ...)
    if not LevelHelper then
        return func(self, ...)
    end

    local altar_total = (mod:get("chest_upgrade_count") or 0)
        + (mod:get("chest_swap_melee_count") or 0)
        + (mod:get("chest_swap_ranged_count") or 0)
        + (mod:get("chest_power_up_count") or 0)
    local cursed_count = mod:get("cursed_chest_count") or 1
    local arena_ammo = mod:get("arena_ammo_count") or 2
    local potions_on = mod:get("enable_campaign_potions")

    local altar_custom = altar_total > 0
    local cursed_custom = cursed_count ~= 1
    local ammo_custom = arena_ammo ~= 2

    if not altar_custom and not cursed_custom and not ammo_custom and not potions_on then
        return func(self, ...)
    end

    local saved = {}
    local current = LevelHelper:current_level_settings()
    local pickup_settings = current and current.pickup_settings
    if pickup_settings then
        for _, difficulty_data in pairs(pickup_settings) do
            if type(difficulty_data) == "table" and difficulty_data.primary then
                local primary = difficulty_data.primary
                local is_arena = primary.deus_weapon_chest == nil
                local entry = { tbl = primary }

                if not is_arena then
                    if altar_custom and primary.deus_weapon_chest ~= nil then
                        entry.deus_weapon_chest = primary.deus_weapon_chest
                        primary.deus_weapon_chest = altar_total
                    end
                    if cursed_custom and primary.deus_cursed_chest ~= nil then
                        entry.deus_cursed_chest = primary.deus_cursed_chest
                        primary.deus_cursed_chest = cursed_count
                    end
                elseif ammo_custom and primary.ammo ~= nil then
                    entry.ammo = primary.ammo
                    primary.ammo = arena_ammo
                end

                if entry.deus_weapon_chest ~= nil or entry.deus_cursed_chest ~= nil or entry.ammo ~= nil then
                    saved[#saved + 1] = entry
                end
            end
        end
    end

    local added_potions = {}
    if potions_on and Pickups and Pickups.deus_potions and Pickups.potions then
        -- Pick a representative weight from existing CW potions. Engine-startup normalization in
        -- pickups.lua sums spawn_weightings within each group separately, so a Pickups.potions
        -- entry's weight (~0.33) doesn't fit into Pickups.deus_potions (~0.125 per entry). Sharing
        -- the reference made the random sampler skip campaign potions in practice.
        local sample_weight
        for _, settings in pairs(Pickups.deus_potions) do
            if settings and settings.spawn_weighting then
                sample_weight = settings.spawn_weighting
                break
            end
        end
        for _, name in ipairs({ "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }) do
            if Pickups.potions[name] and not Pickups.deus_potions[name] then
                local clone = table.clone(Pickups.potions[name])
                if sample_weight then
                    clone.spawn_weighting = sample_weight
                end
                Pickups.deus_potions[name] = clone
                added_potions[#added_potions + 1] = name
            end
        end
    end

    local results = { func(self, ...) }

    for _, entry in ipairs(saved) do
        local primary = entry.tbl
        if entry.deus_weapon_chest ~= nil then primary.deus_weapon_chest = entry.deus_weapon_chest end
        if entry.deus_cursed_chest ~= nil then primary.deus_cursed_chest = entry.deus_cursed_chest end
        if entry.ammo ~= nil then primary.ammo = entry.ammo end
    end

    for _, name in ipairs(added_potions) do
        Pickups.deus_potions[name] = nil
    end

    return unpack(results)
end)

-- ============================================================
-- Starting Boons
-- ============================================================

mod:hook_safe("DeusRunController", "_add_initial_power_ups", function(self, peer_id, local_player_id, profile_index, career_index)
    local run_state = self._run_state
    local own_peer_id = run_state and run_state:get_own_peer_id()

    if not run_state:is_server() and peer_id ~= own_peer_id then return end
    if not DeusPowerUpsArray or not DeusPowerUpUtils then return end

    local extra = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and mod:get("start_boon_" .. name) then
            extra[#extra + 1] = DeusPowerUpUtils.generate_specific_power_up(name, entry.rarity)
        end
    end

    if #extra == 0 then return end

    local skip_metatable = true
    local existing = run_state:get_player_power_ups(peer_id, local_player_id, profile_index, career_index)
    local new_power_ups = table.clone(existing, skip_metatable)
    table.append(new_power_ups, extra)
    run_state:set_player_power_ups(peer_id, local_player_id, profile_index, career_index, new_power_ups)
    mod:echo(string.format("Granted %d starting boon(s).", #extra))
end)

-- ============================================================
-- Modified Boons
-- ============================================================

local reckless_swings_originals = nil

local function apply_reckless_swings_tweak()
    if reckless_swings_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local buff_tpls = rawget(_G, "DeusPowerUpBuffTemplates")
    if not power_up or not power_up.deus_reckless_swings then
        return
    end

    local tpl = power_up.deus_reckless_swings
    local buff_entry = buff_tpls and buff_tpls.deus_reckless_swings_buff

    reckless_swings_originals = {
        health_threshold = tpl.buff_template.buffs[1].health_threshold,
        desc_1_value = tpl.description_values[1].value,
        desc_3_value = tpl.description_values[3].value,
        buff_damage = buff_entry and buff_entry.buffs[1].damage_to_deal,
    }

    tpl.buff_template.buffs[1].health_threshold = 0.25
    tpl.description_values[1].value = 0.25
    tpl.description_values[3].value = 1

    if buff_entry then
        buff_entry.buffs[1].damage_to_deal = 1
    end
end

local function revert_reckless_swings_tweak()
    if not reckless_swings_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local buff_tpls = rawget(_G, "DeusPowerUpBuffTemplates")
    if not power_up or not power_up.deus_reckless_swings then
        reckless_swings_originals = nil
        return
    end

    local tpl = power_up.deus_reckless_swings
    local buff_entry = buff_tpls and buff_tpls.deus_reckless_swings_buff

    tpl.buff_template.buffs[1].health_threshold = reckless_swings_originals.health_threshold
    tpl.description_values[1].value = reckless_swings_originals.desc_1_value
    tpl.description_values[3].value = reckless_swings_originals.desc_3_value

    if buff_entry and reckless_swings_originals.buff_damage then
        buff_entry.buffs[1].damage_to_deal = reckless_swings_originals.buff_damage
    end

    reckless_swings_originals = nil
end

local RECKLESS_SWINGS_DESC_OVERRIDE = "While above 25% Health, gain 25% Power but take 1 damage on each melee hit."

mod:hook(_G, "Localize", function(func, key, ...)
    if key == "description_deus_reckless_swings" and reckless_swings_originals then
        return RECKLESS_SWINGS_DESC_OVERRIDE
    end
    return func(key, ...)
end)

sync_reckless_swings = function()
    if mod:get("tweak_reckless_swings") then
        apply_reckless_swings_tweak()
    else
        revert_reckless_swings_tweak()
    end
end

sync_reckless_swings()

mod.on_setting_changed = function(setting_id)
    if setting_id == "tweak_reckless_swings" then
        sync_reckless_swings()
    end
end

-- ============================================================
-- Debug commands
-- ============================================================

mod:command("dump_spawners", "Dump pickup spawner counts and pickup_settings for the current level", function()
    if not LevelHelper then
        mod:echo("LevelHelper not available.")
        return
    end

    local current = LevelHelper:current_level_settings()
    if not current then
        mod:echo("No level settings found.")
        return
    end

    mod:echo("=== Level: " .. tostring(current.display_name or current.level_id or "?") .. " ===")

    local pickup_settings = current.pickup_settings
    if pickup_settings then
        for diff_key, diff_data in pairs(pickup_settings) do
            if type(diff_data) == "table" and diff_data.primary then
                local p = diff_data.primary
                local line = string.format("  [%s] weapon_chest=%s cursed_chest=%s ammo=%s",
                    tostring(diff_key),
                    tostring(p.deus_weapon_chest or "nil"),
                    tostring(p.deus_cursed_chest or "nil"),
                    tostring(p.ammo or "nil"))
                mod:echo(line)
                mod:info(line)

                for k, v in pairs(p) do
                    if k ~= "deus_weapon_chest" and k ~= "deus_cursed_chest" and k ~= "ammo" then
                        local detail = string.format("    %s = %s", tostring(k), tostring(v))
                        mod:info(detail)
                    end
                end
            end
        end
    else
        mod:echo("  No pickup_settings found.")
    end

    if Managers.state and Managers.state.entity then
        local spawner_count = 0
        local entity_manager = Managers.state.entity
        local system = entity_manager:system("pickup_system")
        if system and system._pickup_spawners then
            for _ in pairs(system._pickup_spawners) do
                spawner_count = spawner_count + 1
            end
            mod:echo("  Physical pickup spawners: " .. spawner_count)
        elseif system and system._spawner_units then
            for _ in pairs(system._spawner_units) do
                spawner_count = spawner_count + 1
            end
            mod:echo("  Physical spawner units: " .. spawner_count)
        else
            mod:echo("  Could not count spawners (unknown fields). Check log.")
            if system then
                for k, v in pairs(system) do
                    mod:info("  pickup_system.%s = %s (%s)", tostring(k), tostring(v), type(v))
                end
            end
        end
    end

    mod:echo("Done. Full details in log.")
end)

mod:command("dump_boon_loc", "Dump resolved display names and descriptions for all boons", function()
    if not DeusPowerUpTemplates or not DeusPowerUpsArray then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local sorted_keys = {}
    for key in pairs(DeusPowerUpTemplates) do
        sorted_keys[#sorted_keys + 1] = key
    end
    table.sort(sorted_keys)

    local count = 0
    for _, key in ipairs(sorted_keys) do
        local tpl = DeusPowerUpTemplates[key]
        local display_key = tpl.display_name
        local desc_key = tpl.advanced_description

        local display_text = ""
        if display_key then
            local raw = Localize(display_key)
            if raw ~= "<" .. display_key .. ">" then
                display_text = raw
            end
        end

        local desc_text = ""
        if desc_key then
            local raw = Localize(desc_key)
            if raw ~= "<" .. desc_key .. ">" then
                desc_text = raw
            end
        end

        mod:info("[DUMP:boon_loc] %s\t%s\t%s", key, display_text, desc_text)
        count = count + 1
    end

    mod:echo(string.format("dump_boon_loc: %d boons dumped to log. Check console log for tab-separated output.", count))
end)

mod:command("dump_boons", "Deep dump of all DeusPowerUpTemplates + buff data to log", function(filter)
    if not DeusPowerUpTemplates then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local function dump_table(tbl, prefix, lines, depth)
        if depth > 6 then
            lines[#lines + 1] = prefix .. "... (max depth)"
            return
        end
        local keys = {}
        for k in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = tbl[k]
            local key_str = prefix .. tostring(k)
            if type(v) == "table" then
                lines[#lines + 1] = key_str .. " = {"
                dump_table(v, prefix .. "  ", lines, depth + 1)
                lines[#lines + 1] = prefix .. "}"
            elseif type(v) == "function" then
                lines[#lines + 1] = key_str .. " = [function]"
            else
                lines[#lines + 1] = key_str .. " = " .. tostring(v) .. "  (" .. type(v) .. ")"
            end
        end
    end

    local function lookup_buff(name)
        if not name then return nil end
        local sources = {
            { rawget(_G, "DeusPowerUpBuffTemplates"), "DeusPowerUpBuffTemplates" },
            { rawget(_G, "BuffTemplates"), "BuffTemplates" },
            { rawget(_G, "NetworkedBuffTemplates"), "NetworkedBuffTemplates" },
        }
        for _, src in ipairs(sources) do
            if src[1] and src[1][name] then
                return src[1][name], src[2]
            end
        end
        return nil, nil
    end

    local sorted_keys = {}
    for key in pairs(DeusPowerUpTemplates) do
        if not filter or key:find(filter, 1, true) then
            sorted_keys[#sorted_keys + 1] = key
        end
    end
    table.sort(sorted_keys)

    local count = 0
    for _, key in ipairs(sorted_keys) do
        local tpl = DeusPowerUpTemplates[key]
        local lines = {}
        lines[#lines + 1] = "========== " .. key .. " =========="

        lines[#lines + 1] = "--- PowerUp Template ---"
        dump_table(tpl, "  ", lines, 0)

        local buff_name = tpl.buff_template_name or tpl.buff_name
        if buff_name then
            local buff_tpl, source = lookup_buff(buff_name)
            if buff_tpl then
                lines[#lines + 1] = "--- Buff Template: " .. buff_name .. " (from " .. source .. ") ---"
                dump_table(buff_tpl, "  ", lines, 0)
            else
                lines[#lines + 1] = "--- Buff Template: " .. buff_name .. " NOT FOUND in any buff table ---"
            end
        end

        for _, line in ipairs(lines) do
            mod:info("[DUMP:boon_deep] %s", line)
        end
        count = count + 1
    end

    mod:echo(string.format("dump_boons: %d boons dumped to log%s", count,
        filter and (" matching '" .. filter .. "'") or ""))
end)

mod:command("dump_buffs", "Deep dump of all buff templates referenced by boons", function(filter)
    if not DeusPowerUpTemplates then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local function dump_table(tbl, prefix, lines, depth)
        if depth > 6 then
            lines[#lines + 1] = prefix .. "... (max depth)"
            return
        end
        local keys = {}
        for k in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = tbl[k]
            local key_str = prefix .. tostring(k)
            if type(v) == "table" then
                lines[#lines + 1] = key_str .. " = {"
                dump_table(v, prefix .. "  ", lines, depth + 1)
                lines[#lines + 1] = prefix .. "}"
            elseif type(v) == "function" then
                lines[#lines + 1] = key_str .. " = [function]"
            else
                lines[#lines + 1] = key_str .. " = " .. tostring(v) .. "  (" .. type(v) .. ")"
            end
        end
    end

    local buff_sources = {}
    local src_names = { "BuffTemplates", "NetworkedBuffTemplates", "DeusPowerUpBuffTemplates", "DeusBuffTemplates" }
    for _, name in ipairs(src_names) do
        local tbl = rawget(_G, name)
        if tbl then buff_sources[name] = tbl end
    end

    local function lookup_buff(name)
        for src_name, src_tbl in pairs(buff_sources) do
            if src_tbl[name] then return src_tbl[name], src_name end
        end
        return nil, nil
    end

    local refs = {}
    local function collect_refs(tbl, depth)
        if depth > 6 or type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(v) == "string" and (k == "buff_to_add" or k == "buff_to_add_revived"
                or k == "cooldown_buff" or k == "full_heal_buff" or k == "removal_buff") then
                refs[v] = true
            elseif type(v) == "table" then
                if k == "buff_to_add" or k == "buff_to_add_revived" then
                    for _, name in pairs(v) do
                        if type(name) == "string" then refs[name] = true end
                    end
                else
                    collect_refs(v, depth + 1)
                end
            end
        end
    end

    for _, tpl in pairs(DeusPowerUpTemplates) do
        collect_refs(tpl, 0)
    end

    local sorted = {}
    for name in pairs(refs) do
        if not filter or name:find(filter, 1, true) then
            sorted[#sorted + 1] = name
        end
    end
    table.sort(sorted)

    local count = 0
    for _, name in ipairs(sorted) do
        local lines = {}
        local buff_tpl, source = lookup_buff(name)
        if buff_tpl then
            lines[#lines + 1] = "========== " .. name .. " (from " .. source .. ") =========="
            dump_table(buff_tpl, "  ", lines, 0)
            count = count + 1
        else
            lines[#lines + 1] = "========== " .. name .. " NOT FOUND =========="
        end
        for _, line in ipairs(lines) do
            mod:info("[DUMP:buff_deep] %s", line)
        end
    end

    mod:echo(string.format("dump_buffs: %d/%d referenced buffs found%s", count, #sorted,
        filter and (" matching '" .. filter .. "'") or ""))
end)

mod:command("dump_mutators", "Dump all mutator templates to log", function(filter)
    local src = rawget(_G, "MutatorTemplates")
    if not src then
        mod:echo("MutatorTemplates not loaded.")
        return
    end

    local entries = {}
    for key, tpl in pairs(src) do
        if not filter or key:find(filter, 1, true) then
            entries[#entries + 1] = key
        end
    end
    table.sort(entries)

    for _, key in ipairs(entries) do
        local tpl = src[key]
        local line = string.format("%-40s display=%s",
            key, tostring(tpl.display_name or tpl.name or "?"))
        mod:echo(line)
        mod:info("[DUMP:mutators] %s", line)
    end

    mod:echo(string.format("dump_mutators: %d templates", #entries))
end)

mod:command("cw_status", "Show Chaos Wastes Tweaker state", function()
    mod:echo("Chaos Wastes Tweaker v" .. MOD_VERSION)
    mod:echo("  Altars: upgrade=" .. tostring(mod:get("chest_upgrade_count") or 0)
        .. " melee_swap=" .. tostring(mod:get("chest_swap_melee_count") or 0)
        .. " ranged_swap=" .. tostring(mod:get("chest_swap_ranged_count") or 0)
        .. " boon=" .. tostring(mod:get("chest_power_up_count") or 0)
        .. " (0=vanilla)")
    mod:echo("  Chests of Trials: " .. tostring(mod:get("cursed_chest_count") or 1))
    mod:echo("  Arena ammo: " .. tostring(mod:get("arena_ammo_count") or 2))
    mod:echo("  Campaign potions: " .. tostring(mod:get("enable_campaign_potions") or false))
end)
