local mod = get_mod("ct")

local MOD_VERSION = "0.2.0-dev"
mod:info("Chaos Wastes Tweaker v%s loaded", MOD_VERSION)
mod:echo("Chaos Wastes Tweaker v" .. MOD_VERSION)

local SHRINE_DEFAULT = 4
local CHEST_DEFAULT = 3
local FINALE_GODS = { "nurgle", "tzeentch", "khorne", "slaanesh" }

local granting_starting_coins = false
local all_trait_combos_cache = nil

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

    return func(unpack(args))
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
        local upgrade = mod:get("chest_upgrade_count")
        local swap_melee = mod:get("chest_swap_melee_count")
        local swap_ranged = mod:get("chest_swap_ranged_count")
        local power_up = mod:get("chest_power_up_count")

        local is_custom = upgrade ~= 1 or swap_melee ~= 1 or swap_ranged ~= 1 or power_up ~= 2
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

    local altar_total = (mod:get("chest_upgrade_count") or 1)
        + (mod:get("chest_swap_melee_count") or 1)
        + (mod:get("chest_swap_ranged_count") or 1)
        + (mod:get("chest_power_up_count") or 2)
    local cursed_count = mod:get("cursed_chest_count") or 1
    local arena_ammo = mod:get("arena_ammo_count") or 2
    local potions_on = mod:get("enable_campaign_potions")

    local altar_custom = altar_total ~= 5
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
        for _, name in ipairs({ "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }) do
            if Pickups.potions[name] and not Pickups.deus_potions[name] then
                Pickups.deus_potions[name] = Pickups.potions[name]
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
