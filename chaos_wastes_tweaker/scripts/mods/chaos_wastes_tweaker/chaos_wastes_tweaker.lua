--[[
chaos_wastes_tweaker — Chaos Wastes ("deus" mode) run modifiers.

Major sections (search by name to jump):
  * Coin economy           — coin_multiplier hook on DeusRunController.on_soft_currency_picked_up,
                             starting_coins via setup_run.
  * Boon counts            — generate_random_power_ups hook intercepts shrine (4) and chest (3) defaults.
  * Disabled boons         — save-and-restore mutation of DeusPowerUpsArray / *ByRarity around the roll.
  * Curses                 — disable_curse_* setting reads, gating MutatorHandler._activate_mutator,
                             DeusMechanism.get_current_node_curse, and node theme/curse fields.
  * Run config overrides   — _setup_run hook (host-only): force_belakor, finale_dominant_god.
  * Pickups & altars       — populate_pickups hook patches deus_weapon_chest / deus_cursed_chest /
                             ammo counts AND injects campaign potions into Pickups.deus_potions
                             with full-group renormalization (see also: DEVELOPMENT.md).
  * Chest-type distribution — get_deus_weapon_chest_type override; "Default" sentinel = 0.
  * Starting boons         — _add_initial_power_ups hook (host-only) grants toggled boons.
  * Banned weapon traits   — apply_weapon_trait_filter / restore_weapon_trait_filter wraps
                             DeusWeaponGeneration calls.
  * Khaine's Fury tweak    — apply_reckless_swings_tweak / revert_reckless_swings_tweak +
                             sync_reckless_swings (forward-declared; called from boon roll).
  * Bomb boon balance      — bomb_boon_cooldown override on drop_item_on_ability_use, mutual
                             exclusivity in generate_random_power_ups via BOMB_BOON_NAMES,
                             Endless-Bombs-consumes-Morgrim hook on apply_pockets_full_of_bombs_buff,
                             RV-no-save-Morgrim hook on ActionChargedProjectileUtility.fire_charged_projectile.
  * Lifecycle              — on_setting_changed re-syncs Khaine's Fury and bomb cooldown;
                             on_disabled reverts both persistent DeusPowerUpTemplates mutations.
]]

local mod = get_mod("ct")

local MOD_VERSION = "0.7.0-alpha"
mod:info("Chaos Wastes Tweaker v%s loaded", MOD_VERSION)
mod:echo("Chaos Wastes Tweaker v" .. MOD_VERSION)

local AdventurePool = mod:dofile("scripts/mods/chaos_wastes_tweaker/_adventure_pool")
-- Call unconditionally so the LEVEL_AVAILABILITY snapshot is captured at mod load,
-- even if the master toggle is off. inject_pool() short-circuits internally when the
-- master is off (only resets to snapshot). Snapshot-at-load means subsequent toggles
-- always reset to clean vanilla state — no race where snapshot is taken after our
-- own previous mutations.
AdventurePool.inject_pool()

local SHRINE_DEFAULT = 4
local CHEST_DEFAULT = 3
local FINALE_GODS = { "nurgle", "tzeentch", "khorne", "slaanesh" }

-- Boons that grant or amplify free bombs/grenades. Used by the bomb-boon mutual-exclusion
-- toggle (one bomb boon per run) and listed in the localization tooltip.
local BOMB_BOON_NAMES = {
    drop_item_on_ability_use = true,
    deus_grenade_multi_throw = true,
}

local granting_starting_coins = false
local all_trait_combos_cache = nil
-- CLARIFY: Forward-declared so the `generate_random_power_ups` hook (call site line 150) and
-- `on_setting_changed` (line 740) can reference sync_reckless_swings before its assignment at line
-- 724. Lua 5.1 locals are not hoisted; without this stub the references would either resolve to a
-- global lookup (and silently no-op until the assignment runs) or crash. See
-- feedback_lua_forward_reference.md (5 prior crashes from this exact bug pattern).
local sync_reckless_swings
local sync_bomb_cooldown

local function is_curse_disabled(curse_name)
    if type(curse_name) ~= "string" or not curse_name:find("^curse_") then
        return false
    end

    local key = "disable_curse_" .. curse_name:gsub("^curse_", "")
    return mod:get(key) == true
end

-- CLARIFY: Vanilla signature is `on_soft_currency_picked_up(self, amount, type)`. The `amount` is
-- args[1] (NOT args[2] — that mistake was the cause of an early-version coin multiplier bug; see
-- "Coin multiplier not working (wrong argument index)" in DEVELOPMENT.md).
mod:hook("DeusRunController", "on_soft_currency_picked_up", function(func, self, ...)
    local args = { ... }
    local raw_amount = args[1]

    if type(raw_amount) == "number" and not granting_starting_coins then
        local multiplier = mod:get("coin_multiplier") or 1
        args[1] = math.max(1, math.floor(raw_amount * multiplier))
    end

    return func(self, unpack(args))
end)

-- CLARIFY: Granting starting coins by re-entering on_soft_currency_picked_up. The
-- `granting_starting_coins` flag suppresses the multiplier hook above so 500 starting coins doesn't
-- get doubled by a 2x multiplier setting. Without the flag, a multiplier > 1 would inflate the gift.
-- POTENTIAL BUG (LOW): the second arg to on_soft_currency_picked_up is `type` (a
-- DeusSoftCurrencySettings.types.{GROUND,MONSTER,...} value). Passing nil means the server-only
-- branch in vanilla treats this as neither GROUND nor MONSTER, so the per-pickup counters are NOT
-- incremented — fine for starting coins, but worth knowing.
mod:hook_safe("DeusRunController", "setup_run", function(self)
    local starting = mod:get("starting_coins")
    if starting and starting > 0 and self.on_soft_currency_picked_up then
        granting_starting_coins = true
        self:on_soft_currency_picked_up(starting)
        granting_starting_coins = false
    end
end)

-- CLARIFY: Vanilla signature is `(seed, count, existing_power_ups, difficulty, run_progress, ...)`.
-- Rather than hard-coding count = args[2] (which would be brittle to future signature drift), the
-- code scans args for the first integer in [1,10] and assumes that's the count. `seed` is normally a
-- 32-bit hash > 10 so it won't collide.
-- QUESTION: Why detect by value range instead of just args[2]? If FatShark ever wraps this, the
-- scan also finds the count, but a non-default count outside [1,10] would silently be missed.
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

        -- CLARIFY: Only override when the original count matches a known default (4 = shrine, 3 =
        -- chest). This avoids hijacking other call sites that pass arbitrary counts (e.g., quest
        -- rewards, Belakor temple). If FatShark changes the defaults this silently no-ops.
        if original == SHRINE_DEFAULT then
            custom_count = mod:get("shrine_boon_count")
        elseif original == CHEST_DEFAULT then
            custom_count = mod:get("chest_boon_count")
        end

        if custom_count and custom_count ~= original then
            args[count_index] = custom_count
        end
    end

    -- CLARIFY: Disabled-boon enforcement uses the "remove-then-restore" pattern: temporarily mutate
    -- the global pool, run the original sampler, then restore. This is safer than wrapping the
    -- sampler because vanilla's `generate_random_power_up` directly reads DeusPowerUpsArray /
    -- DeusPowerUpsArrayByRarity for both random and rarity-filtered selection.
    -- POTENTIAL BUG (LOW): If `func()` raises an error, restore code below never runs and disabled
    -- boons stay removed for the rest of the session. Consider wrapping in pcall for safety.
    local removed_main = {}
    local removed_rarity = {}

    -- Bomb-boon exclusivity: if the toggle is on AND the player already owns any bomb boon, also
    -- strip the rest from the pool for this roll. existing_power_ups is positionally args[3] in the
    -- vanilla signature (seed, count, existing_power_ups, ...).
    local exclude_bomb_boons = false
    if mod:get("bomb_boon_exclusive") then
        local existing = args[3]
        if type(existing) == "table" then
            for _, pu in ipairs(existing) do
                if pu and pu.name and BOMB_BOON_NAMES[pu.name] then
                    exclude_bomb_boons = true
                    break
                end
            end
        end
    end

    if DeusPowerUpsArray then
        -- CLARIFY: Iterate backwards so table.remove indices stay stable. The saved `index` is the
        -- pre-removal slot, which is the correct insertion point for restoration in reverse order.
        for i = #DeusPowerUpsArray, 1, -1 do
            local boon = DeusPowerUpsArray[i]
            local name = boon and boon.name
            local key = name and ("disable_boon_" .. name)
            if (key and mod:get(key)) or (exclude_bomb_boons and name and BOMB_BOON_NAMES[name]) then
                table.remove(DeusPowerUpsArray, i)
                removed_main[#removed_main + 1] = { index = i, boon = boon }
            end
        end
        if DeusPowerUpsArrayByRarity then
            for rarity, arr in pairs(DeusPowerUpsArrayByRarity) do
                removed_rarity[rarity] = {}
                for i = #arr, 1, -1 do
                    local boon = arr[i]
                    local name = boon and boon.name
                    local key = name and ("disable_boon_" .. name)
                    if (key and mod:get(key)) or (exclude_bomb_boons and name and BOMB_BOON_NAMES[name]) then
                        table.remove(arr, i)
                        removed_rarity[rarity][#removed_rarity[rarity] + 1] = { index = i, boon = boon }
                    end
                end
            end
        end
    end

    local new_seed, new_power_ups = func(unpack(args))

    -- CLARIFY: Restore in reverse order of removal so that re-inserting at the saved indices
    -- reconstructs the original array exactly. `removed_main` was appended in descending-i order,
    -- so iterating it in reverse means we reinsert from the lowest index first.
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

    -- CLARIFY: Re-applies the Khaine's Fury (deus_reckless_swings) tweak after every boon-roll. The
    -- engine may rebuild boon templates between rolls; this defensive call ensures the modified
    -- description and damage values stay in effect. on_setting_changed also calls this when the
    -- toggle flips.
    sync_reckless_swings()
    sync_bomb_cooldown()

    return new_seed, new_power_ups
end)

-- CLARIFY: Workaround for a vanilla VT2 layout bug. When a shrine/cursed-chest only spawns ONE
-- widget on the arc, vanilla code computes the offset via `cos(angle) * radius` where `angle = 0/0`
-- (NaN from division-by-zero in degenerate single-element arc). The widget then renders at NaN
-- screen position and is invisible. Replacing NaN with 0 centers the single widget. NaN is detected
-- via `x ~= x` (the only value that isn't equal to itself in IEEE 754).
-- QUESTION: Why only fix the 1-widget case? If the issue can also occur for 0 or N>1 widgets, this
-- silently fails to repair them. May be intentional — maybe FatShark's layout only divides by zero
-- when count == 1.
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

-- CLARIFY: Save-and-restore pattern for disabled curses. When transitioning into a node, vanilla
-- reads node.curse to spawn the curse mutator. We blank node.curse for the duration of the
-- transition so the mutator doesn't activate, then restore the original value so other code paths
-- (UI tooltips, save state, network sync) still see the canonical curse.
-- POTENTIAL BUG (LOW): If the wrapped `func` errors, restoration is skipped and node.curse stays
-- nil for the rest of the run. Same pattern repeats in start_next_round and _enable_hover.
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

    -- CLARIFY: Forcing theme="wastes" prevents the curse-themed visuals/lighting from loading even
    -- though node.curse is suppressed. Without this, the engine could still load curse aesthetic
    -- assets keyed off node.theme (e.g., "tzeentch", "khorne") and produce mismatched visuals.
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

-- CLARIFY: Suppresses the curse-themed hover preview on the map for nodes whose curse is disabled.
-- Sets theme=nil so the hover view shows the default "wastes" preview instead of (e.g.) the
-- Tzeentch-themed curse preview, accurately reflecting that the player won't experience the curse.
-- POTENTIAL BUG (LOW): Inconsistent return semantics — the disabled-curse path returns nothing
-- (implicit nil), the normal path returns whatever func returns. If a future caller relies on the
-- return value, the disabled path silently differs.
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

-- CLARIFY: Custom altar distribution for chests. Vanilla `get_deus_weapon_chest_type` lazily builds
-- self._deus_weapon_chest_distribution from the level's deus_weapon_chest_distribution table on
-- first call per node, then pops one entry per call. We intercept the FIRST call (when distribution
-- is empty), build our own custom distribution if any altar setting is non-zero, write it to
-- self._deus_weapon_chest_distribution, pop one entry, and return it. Subsequent calls find a
-- non-empty distribution and we fall through to vanilla which pops the rest.
-- The custom distribution overrides the entire chest contents — types left at 0 simply don't appear.
-- Filter unknown rarities out of get_own_weapon_pool_excludes. Vanilla
-- `DeusRunController.get_weapon_pool` (line 2130-2134) iterates pool_excludes
-- as the source of truth and does `weapon_pool[pool_rarity][...] = nil`, but
-- weapon_pool only contains the vanilla rarities (plentiful/common/exotic/unique).
-- If a sibling mod (e.g. Peregrinaje) wrote a custom rarity like "modded" to
-- pool_excludes and is no longer active, the `weapon_pool["modded"]` lookup is
-- nil and the indexing crashes with "attempt to index a nil value" inside chest
-- generation (deus_chest_extension.lua:_generate_stored_weapon).
-- We strip non-standard rarities from the returned table so vanilla doesn't trip.
local _VANILLA_RARITIES = { plentiful = true, common = true, exotic = true, unique = true }
mod:hook("DeusRunController", "get_own_weapon_pool_excludes", function(func, self, ...)
    local excludes = func(self, ...)
    if type(excludes) ~= "table" then return excludes end
    for rarity in pairs(excludes) do
        if not _VANILLA_RARITIES[rarity] then
            mod:info("[weapon-pool] stripped unknown rarity '%s' from pool_excludes", tostring(rarity))
            excludes[rarity] = nil
        end
    end
    return excludes
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
                -- CLARIFY: Seeding the shuffle with the node's level_seed ensures deterministic
                -- altar order across host/clients on the same node. Falls back to seed=0 if any
                -- intermediate is nil (defensive — shouldn't normally happen since this hook only
                -- fires inside an active run).
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

-- CLARIFY: Builds the union of all trait-combinations across all CW weapons, deduplicated. Used
-- when "Any Trait on Any Weapon" is enabled — every weapon gets the FULL pool of trait combos
-- instead of its baked subset. The dedupe key uses "\0" as separator since trait names can't
-- contain null bytes; this avoids ambiguity (e.g. `{"a","bc"}` vs `{"ab","c"}`).
-- POTENTIAL BUG (LOW): The cache is never invalidated. If DeusWeapons is mutated after first call
-- (e.g. by another mod), stale combos persist. Acceptable since DeusWeapons is normally static.
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

-- CLARIFY: Trait filter has three behaviors based on the `any_trait_any_weapon` toggle and the
-- ban list. The base pool is either the weapon's vanilla trait combos or the global expanded pool.
-- Then any combo containing a banned trait is removed from `filtered`.
-- The new_value selection logic:
--   - filtered partially shrunk (some bans hit, some left): use filtered
--   - filtered emptied (every combo had a ban): keep `base` so the weapon isn't unrollable —
--     a fully-banned weapon would crash the upgrade UI when no traits can be picked
--   - filtered unchanged but `expanded_pool` differs from original: use base (= expanded_pool)
--   - filtered unchanged and base==original: skip (no patch needed)
-- POTENTIAL BUG (LOW): When `filtered` is empty, falling back to `base` means banned traits CAN
-- still appear on that weapon. This is a reasonable graceful-degradation choice but the UI tooltip
-- doesn't tell the user.
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

-- CLARIFY: Three trait-filter wrap points cover the three vanilla call sites that read
-- baked_trait_combinations: initial weapon roll, slot-specific roll (Belakor temple?), and altar
-- upgrade. Same save/restore pattern as the boon hooks above.
-- POTENTIAL BUG (LOW): Same as boon-removal — if `func()` errors, restore is skipped and DeusWeapons
-- stays mutated. pcall would harden this.
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

-- CLARIFY: Host-only run-config overrides. `is_server` gating ensures clients don't try to override
-- values the host has already authoritatively set. The host's overridden values then propagate to
-- clients via the engine's normal RPC path (rpc_deus_setup_run). This means these settings are
-- HOST-driven: only the lobby host's mod settings affect the run.
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

-- CLARIFY: Patches LevelSettings[level].pickup_settings to control the COUNT of altars/cursed
-- chests/arena ammo crates spawned per mission. This works alongside `get_deus_weapon_chest_type`
-- which controls the TYPE distribution within each chest. Net effect:
--   - altar_total > 0: spawn this many altars total (types determined by chest_*_count proportions)
--   - cursed_count != 1: override cursed-chest count (vanilla = 1)
--   - arena_ammo != 2: override arena ammo box count (vanilla = 2)
--   - potions_on: inject campaign damage/speed/CDR potions into Pickups.deus_potions for this mission
-- All settings save/restore around `func()` so vanilla values are preserved between runs.
-- POTENTIAL BUG (LOW): Same `func` error → state leak issue as boon/trait hooks. If `func()` raises,
-- pickup_settings stays mutated AND added_potions clones leak in Pickups.deus_potions.
--
-- Per-level counter for tome/grim → Chest of Trials conversions. Declared here (not
-- where the conversion hook below uses it) because Lua 5.1 closures bind locals
-- lexically AT CREATION TIME — placing the `local` after the hook would make the
-- earlier reference resolve to a global (per feedback_lua_forward_reference.md).
-- Reset is performed at the top of THIS hook (consolidated to avoid the VMF
-- "Attempting to rehook active hook" warning for populate_pickups).
local _chest_conversions_this_level = 0
mod:hook("PickupSystem", "populate_pickups", function(func, self, ...)
    _chest_conversions_this_level = 0
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

    -- CLARIFY: "custom" gates determine which fields to mutate. The defaults (1 cursed chest, 2
    -- arena ammo) are the vanilla values; if the user's setting matches vanilla, we skip mutation
    -- to keep pickup_settings pristine.
    local altar_custom = altar_total > 0
    local cursed_custom = cursed_count ~= 1
    local ammo_custom = arena_ammo ~= 2

    if not altar_custom and not cursed_custom and not ammo_custom and not potions_on then
        return func(self, ...)
    end

    -- CLARIFY: Detect arena (finale) vs normal levels. Arena levels have no `deus_weapon_chest` key
    -- but DO have `ammo`; normal levels have `deus_weapon_chest` and `deus_cursed_chest`. The
    -- detection lets one hook handle both level types correctly.
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

                -- CLARIFY: Only push to `saved` if at least one field was mutated, so the restore
                -- loop below is a no-op for unchanged entries.
                if entry.deus_weapon_chest ~= nil or entry.deus_cursed_chest ~= nil or entry.ammo ~= nil then
                    saved[#saved + 1] = entry
                end
            end
        end
    end

    local added_potions = {}
    -- Saved spawn_weightings keyed by pickup_name. We renormalize the entire deus_potions
    -- group below so the inserted campaign potions are actually reachable by the sampler;
    -- both the inserts AND the originals get restored after vanilla populate_pickups runs.
    local saved_weights = {}
    if potions_on and Pickups and Pickups.deus_potions and Pickups.potions then
        -- Step 1: insert campaign potion clones using their NATIVE Pickups.potions weight
        -- (so each entry contributes ~0.33 to the running total). We'll renormalize after.
        for _, name in ipairs({ "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }) do
            if Pickups.potions[name] and not Pickups.deus_potions[name] then
                local clone = table.clone(Pickups.potions[name])
                Pickups.deus_potions[name] = clone
                added_potions[#added_potions + 1] = name
            end
        end

        -- Step 2: renormalize ALL entries in Pickups.deus_potions so they sum to 1.0.
        -- Without this, the sampler in pickup_system.lua _spawn_spread_pickups picks
        -- random[0,1) and breaks on first cumulative >= random — entries past
        -- cumulative 1.0 are unreachable. CW potions were already normalized to sum
        -- ~1.0 at engine startup; adding 3 campaign entries pushed the total to ~1.375
        -- and made some entries (depending on `pairs` iteration order, which is
        -- unspecified in Lua 5.1) silently never spawn.
        local total = 0
        for name, settings in pairs(Pickups.deus_potions) do
            if settings and settings.spawn_weighting then
                saved_weights[name] = settings.spawn_weighting
                total = total + settings.spawn_weighting
            end
        end
        if total > 0 then
            for name, settings in pairs(Pickups.deus_potions) do
                if saved_weights[name] then
                    settings.spawn_weighting = saved_weights[name] / total
                end
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

    -- Restore CW potion weights to their pre-renormalization values, then drop the
    -- inserted campaign clones. Order matters: restore first so we don't briefly leave
    -- weights in an inconsistent state if anything else reads Pickups.deus_potions.
    for name, original in pairs(saved_weights) do
        local entry = Pickups.deus_potions[name]
        if entry then entry.spawn_weighting = original end
    end
    for _, name in ipairs(added_potions) do
        Pickups.deus_potions[name] = nil
    end

    return unpack(results)
end)

-- ============================================================
-- Tome / Grimoire → Chest of Trials substitution
-- ============================================================

-- CLARIFY: Adventure levels injected into the CW map pool (see _adventure_pool.lua) have
-- tome/grimoire pickup_spawner units baked into the level bundle. On an injected adventure
-- level we want those positions to spawn a Chest of Trials (deus_cursed_chest) instead.
--
-- Vanilla PickupSystem._spawn_guaranteed_pickup (pickup_system.lua:821-844) iterates AllPickups
-- and filters via _can_spawn, which reads Unit.get_data(spawner, pickup_name). Tome spawners
-- have only `tome = true` set; grimoire spawners only `grimoire = true`. We detect those flags
-- and short-circuit to spawn deus_cursed_chest directly.
--
-- Gated on IS_INJECTED_ADVENTURE_LEVEL[base_level_name] so vanilla CW levels (no tomes/grims)
-- and stock adventure runs (when CW pool injection is off) are completely unaffected.

-- Reverse-match a permutation or duplicate-alias key back to its injected adventure base.
-- Returns the base key (e.g. "bell") if level_key matches an injected adventure, else nil.
-- Handles three formats:
--   "bell"                       (raw base)
--   "bell_khorne_path1"          (per-theme permutation)
--   "bell_dup1_khorne_path1"     (duplicate-alias permutation)
local function adventure_base_from_level_key(level_key)
    if type(level_key) ~= "string" or not AdventurePool then return nil end
    for base in pairs(AdventurePool.IS_INJECTED_ADVENTURE_LEVEL) do
        if level_key == base or level_key:find("^" .. base .. "_") then
            return base
        end
    end
    return nil
end

local function on_injected_adventure_level()
    if not LevelHelper then return false end
    local current = LevelHelper:current_level_settings()
    return current and adventure_base_from_level_key(current.level_id) ~= nil
end

-- Lookup table: <adv_base_key>_title → display name. Used to satisfy the CW map UI
-- which constructs the title localization key ad-hoc at deus_map_ui_v2.lua:593 as
-- `Localize(level .. "_title")`, ignoring LevelSettings[<perm>].display_name entirely.
-- Without this hook the map shows "<elven_ruins_title>" / "<bell_title>" etc.
-- We also intercept `_desc` for the same reason (line 594).
local ADV_TITLE_OVERRIDES = {}
local ADV_DESC_OVERRIDES = {}
do
    local function add(key, title, desc)
        ADV_TITLE_OVERRIDES[key .. "_title"] = title
        ADV_DESC_OVERRIDES[key .. "_desc"] = desc
    end
    for _, m in ipairs(AdventurePool.ADVENTURE_MISSIONS) do
        -- title shown on the node icon hover; desc shown below it.
        add(m.key, m.name, m.name)
    end
end

-- Consolidated _G.Localize hook. VMF warns "Attempting to rehook active hook" if the
-- same target is hooked twice — only the second binding survives and shadows the first.
-- Two purposes live here:
--   1. Adventure-mission titles/descriptions used by deus_map_ui_v2.lua:593's
--      ad-hoc `Localize(level .. "_title")` lookup. Without this, injected
--      adventure nodes render as "<elven_ruins_title>" on Olesya's map.
--   2. Khaine's Fury (deus_reckless_swings) description override when the user has
--      `tweak_reckless_swings` enabled. Vanilla format string is "While above 50% …";
--      we substitute "25% / 1 damage" verbatim. Percent signs MUST be `%%` because
--      UIUtils.format_localized_description (ui_utils.lua:69) re-feeds the result
--      through string.format with description_values — a bare `%` becomes
--      "[Invalid String Format]". See feedback_vt2_localize_string_format_pipeline.md.
local RECKLESS_SWINGS_DESC_OVERRIDE = "While above 25%% Health, gain 25%% Power but take 1 damage on each melee hit."

mod:hook(_G, "Localize", function(func, key, ...)
    if type(key) == "string" then
        local t = ADV_TITLE_OVERRIDES[key]
        if t then return t end
        local d = ADV_DESC_OVERRIDES[key]
        if d then return d end
        if key == "description_deus_reckless_swings" and reckless_swings_originals then
            return RECKLESS_SWINGS_DESC_OVERRIDE
        end
    end
    return func(key, ...)
end)

-- DeusMechanism.uses_random_directors returns false (deus_mechanism.lua:909) so
-- EnemyPackageLoader._random_director_list stays nil for the entire CW run. Vanilla
-- CW levels' baked spawn_zone data have explicit `roaming_set` directors (no "random"
-- choice), so they never hit the nil dereference at
-- main_path_spawning_generator.lua:314 (`random_director_list[index].name`). Adventure
-- level spawn zones, however, were authored for AdventureMechanism (which returns
-- true) and DO have zone strings with "random" as one of the slash-separated
-- choices. When `process_conflict_directors_zones` picks "random" for any zone, the
-- subsequent generate_great_cycles crash fires.
--
-- Fix: force `use_random_directors = true` on the EnemyPackageLoader.setup_startup_enemies
-- call for any injected adventure level (matching by permutation base). This causes
-- _resolve_breed_packages (line 750) to populate _random_director_list, which the
-- spawn_zone generator then reads safely.
mod:hook("EnemyPackageLoader", "setup_startup_enemies", function(func, self, level_key, level_seed, failed_locked_functions, use_random_directors, conflict_director_name, difficulty, difficulty_tweak)
    if adventure_base_from_level_key(level_key) then
        use_random_directors = true
    end
    return func(self, level_key, level_seed, failed_locked_functions, use_random_directors, conflict_director_name, difficulty, difficulty_tweak)
end)

-- ============================================================
-- Curse light tinting on injected adventure levels
-- ============================================================
-- Vanilla GameModeDeus.local_player_game_starts (game_mode_deus.lua:358-378)
-- iterates `Level.units(current_level)` and applies `DeusThemeSettings[theme].light_probe_tint`
-- to lights inside reflection_probe units. For vanilla CW that's enough — the level
-- bundle's sky shader and atmosphere are theme-specific too, so the tint reinforces
-- the existing visual.
--
-- Adventure level bundles have only the native atmosphere baked in (no per-god sky).
-- So when our injected `<adv>_<theme>_path1` permutation loads under a curse, the
-- engine applies the reflection-probe tint but the sky/atmosphere remains adventure-
-- vanilla. Result: cursed adventure missions look too "normal".
--
-- Partial mitigation: hook_safe the same function and apply the theme color to
-- EVERY light in the level (not just reflection probes), plus the camera backlight.
-- This makes the curse colour shift more pronounced even on adventure geometry.
-- It can't bring back the baked sky/particles, but it makes "this node is cursed"
-- visually obvious.
-- Saturated tint colors per curse theme, since the vanilla DeusThemeSettings
-- `light_probe_tint` values are extremely close to white (e.g. slaanesh is
-- {0.76, 0.76, 1.00} which is barely visible). Without a baked themed sky to
-- back them up (adventure levels have none), the subtle tint just looks like
-- "slight color cast". These curated values produce a clearly visible mood.
local _CURSE_LIGHT_TINT = {
    khorne   = { 1.00, 0.40, 0.40 },  -- saturated red
    nurgle   = { 0.50, 1.00, 0.50 },  -- saturated green
    tzeentch = { 0.50, 0.55, 1.00 },  -- saturated blue
    slaanesh = { 1.00, 0.55, 0.80 },  -- pink/magenta
    belakor  = { 0.60, 0.40, 0.80 },  -- purple
}

mod:hook_safe("GameModeDeus", "local_player_game_starts", function(self, player, loading_context)
    if not on_injected_adventure_level() then return end
    local run_controller = self._deus_run_controller
    if not run_controller then return end
    local current_node = run_controller:get_current_node()
    if not current_node then return end
    local theme = current_node.theme
    if not theme or theme == "wastes" then
        mod:info("[curse-tint] theme=%s (no curse); skipping", tostring(theme))
        return
    end
    local tint = _CURSE_LIGHT_TINT[theme]
    if not tint then
        mod:warning("[curse-tint] no tint mapping for theme=%s", tostring(theme))
        return
    end

    local world = self._world
    local level = LevelHelper:current_level(world)
    if not level then return end

    local r, g, b = tint[1], tint[2], tint[3]
    -- DELIBERATE: don't tint the camera backlight (that was glowing the
    -- first-person hands which the user didn't want). Tint only world lights.
    local units = Level.units(level)
    local lights_tinted = 0
    for j = 1, #units do
        local level_unit = units[j]
        if Unit.alive(level_unit) then
            local num_lights = Unit.num_lights(level_unit)
            if num_lights and num_lights > 0 then
                for i = 1, num_lights do
                    local light = Unit.light(level_unit, i - 1)  -- 0-indexed per vanilla
                    if light then
                        Light.set_color(light, Vector3(r, g, b))
                        lights_tinted = lights_tinted + 1
                    end
                end
            end
        end
    end
    mod:info("[curse-tint] level=%s theme=%s tint=%.2f,%.2f,%.2f lights=%d",
        tostring(current_node.level), tostring(theme), r, g, b, lights_tinted)
end)

-- ============================================================
-- Replace shrines with missions (SHOP -> TRAVEL conversion)
-- ============================================================
-- When `replace_shrines_with_missions` is enabled, every SHOP node in the base
-- journey graph is converted to a TRAVEL node BEFORE deus_populate_graph picks
-- levels for it. Effect: the boon-picker shrines on Olesya's map become regular
-- mission slots that roll from the TRAVEL pool (vanilla CW missions plus any
-- enabled adventure missions). Players play more missions and lose the free
-- between-mission boon picks.
--
-- Implementation: hook deus_populate_graph and clone-then-mutate the base_graph
-- before passing to the original. We shallow-clone individual SHOP nodes (not
-- the whole graph) so we don't waste memory copying TRAVEL/SIGNATURE/ARENA nodes
-- — and crucially DON'T mutate the source baked-graph table, which is shared
-- across calls. Setting `label = 0` on the converted node skips the
-- shuffled_levels_for_labels deterministic lookup and forces a random pick from
-- LEVEL_AVAILABILITY.TRAVEL (which is what we want — random TRAVEL roll).
-- Map node icon swap for adventure levels. Vanilla `spawn_graph_units` in
-- deus_map_scene.lua:182-192 picks the node's 3D model by string-prefix on
-- `node.level`:  "sig_*" → SIG, "pat_*" → TRAVEL, "arena_*" → ARENA, else SHRINE.
-- Adventure mission keys (e.g. `bell_khorne_path1`, `farmlands_khorne_path1`)
-- don't match any prefix, so they fall to SHRINE. Hook DeusMapScene.on_enter
-- (the public method that calls spawn_graph_units at line 466): walk the
-- graph_data, prefix each adventure node's `level` with the CW-icon basename
-- that matches the mission's `icon` field, call vanilla, then restore.
-- This routes adventure nodes to TRAVEL_NODE_UNIT and feeds the flow event's
-- `data.level` lookup a CW basename it recognizes (pat_tower for towers,
-- pat_mountain for mountain missions, etc.) so the per-mission icon variant
-- on the 3D node mesh matches our `icon` field. Adventure base_level is also
-- rewritten so the flow event's `data.level` (set from node.base_level on the
-- spawned unit) sees the icon-matching base too.
mod:hook("DeusMapScene", "on_enter", function(func, self, graph_data, ...)
    if not graph_data then return func(self, graph_data, ...) end
    local saved = {}
    for key, node in pairs(graph_data) do
        if type(node) == "table" and type(node.level) == "string" then
            local base_key = adventure_base_from_level_key(node.level)
            if base_key then
                local mission = AdventurePool and AdventurePool.MISSION_BY_KEY and AdventurePool.MISSION_BY_KEY[base_key]
                local icon = mission and mission.icon or "mountain"  -- fallback
                local cw_base = "pat_" .. icon
                -- Try matching SIGNATURE prefix if it's that pool type — sig_<icon>
                -- exists for some CW themes but not all; pat_ is the safer default.
                saved[key] = { level = node.level, base_level = node.base_level }
                local suffix = node.level:match("(_[a-z]+_path%d+)$") or "_wastes_path1"
                node.level = cw_base .. suffix
                node.base_level = cw_base
            end
        end
    end

    local result = { func(self, graph_data, ...) }

    for key, original in pairs(saved) do
        if graph_data[key] then
            graph_data[key].level = original.level
            graph_data[key].base_level = original.base_level
        end
    end
    return unpack(result)
end)

-- Filter curse pool by user's disable_curse_* settings BEFORE the graph generator
-- runs spread_curse → assign_random_curse. The vanilla picker reads
-- `config.AVAILABLE_CURSES[node_type][god]` and picks at random. If we strip
-- disabled curses from that array, a node hot-spotted to god X will roll a
-- DIFFERENT enabled curse of X instead of being nil-curse'd by our downstream
-- _transition_next_node hook.
-- Edge case: if user disabled ALL curses of god X, leaving the array empty would
-- crash assign_random_curse (`curses[random(1, 0)]` → nil indexing). We keep the
-- original list in that case so the picker has something to pick; the existing
-- runtime curse-disable hooks (_activate_mutator, get_current_node_curse,
-- _transition_next_node, start_next_round, _enable_hover) then null out the
-- still-disabled curse — net effect: theme stays as the god, curse vanishes.
-- Returns the save-list so the caller can restore originals after func() runs.
local function filter_available_curses(config)
    local saved = {}
    if not config or not config.AVAILABLE_CURSES then return saved end
    for node_type, god_table in pairs(config.AVAILABLE_CURSES) do
        if type(god_table) == "table" then
            for god, curse_list in pairs(god_table) do
                if type(curse_list) == "table" and #curse_list > 0 then
                    local filtered = {}
                    for _, curse in ipairs(curse_list) do
                        local key = "disable_curse_" .. curse:gsub("^curse_", "")
                        if not mod:get(key) then
                            filtered[#filtered + 1] = curse
                        end
                    end
                    if #filtered > 0 and #filtered < #curse_list then
                        saved[#saved + 1] = { tbl = god_table, key = god, original = curse_list }
                        god_table[god] = filtered
                    end
                    -- If #filtered == 0 (all disabled), leave original in place; the
                    -- runtime is_curse_disabled hooks will null the picked curse anyway.
                end
            end
        end
    end
    return saved
end

local function restore_available_curses(saved)
    for i = #saved, 1, -1 do
        local entry = saved[i]
        entry.tbl[entry.key] = entry.original
    end
end

mod:hook(_G, "deus_populate_graph", function(func, base_graph, seed, config, dominant_god, with_belakor)
    -- Override the curse hotspot count if the user has set `cursed_mission_count`.
    -- Vanilla `spread_curse` (deus_populate_graph.lua:681) does:
    --   hot_spot_count = random(CURSES_HOT_SPOTS_MIN_COUNT, CURSES_HOT_SPOTS_MAX_COUNT)
    --   for each cluster: pick a center node, curse it, AND spread curse to nodes
    --   within `CURSES_HOT_SPOT_MAX_RANGE` (so each cluster typically curses 1-3 nodes).
    -- For the user's setting to give an EXACT count of cursed missions, we both:
    --   1. Force MIN = MAX = N (deterministic cluster count)
    --   2. Set MIN_RANGE = MAX_RANGE = 0 (each cluster curses only its center, no spread)
    -- Net: exactly N cursed nodes (or fewer if the map has < N curseable nodes; the
    -- spreader stops early when it runs out of candidates).
    local saved_min, saved_max, saved_range_min, saved_range_max
    local override_curse_count = mod:get("cursed_mission_count")
    if config and override_curse_count and override_curse_count > 0 then
        saved_min = config.CURSES_HOT_SPOTS_MIN_COUNT
        saved_max = config.CURSES_HOT_SPOTS_MAX_COUNT
        saved_range_min = config.CURSES_HOT_SPOT_MIN_RANGE
        saved_range_max = config.CURSES_HOT_SPOT_MAX_RANGE
        config.CURSES_HOT_SPOTS_MIN_COUNT = override_curse_count
        config.CURSES_HOT_SPOTS_MAX_COUNT = override_curse_count
        config.CURSES_HOT_SPOT_MIN_RANGE = 0
        config.CURSES_HOT_SPOT_MAX_RANGE = 0
    end

    -- Filter the curse pool so disabled curses get re-rolled within their god
    -- rather than just removed (per user spec).
    local saved_curses = filter_available_curses(config)

    local function restore_curse_count()
        if saved_min then config.CURSES_HOT_SPOTS_MIN_COUNT = saved_min end
        if saved_max then config.CURSES_HOT_SPOTS_MAX_COUNT = saved_max end
        if saved_range_min then config.CURSES_HOT_SPOT_MIN_RANGE = saved_range_min end
        if saved_range_max then config.CURSES_HOT_SPOT_MAX_RANGE = saved_range_max end
        restore_available_curses(saved_curses)
    end

    if not mod:get("replace_shrines_with_missions") then
        local result = { func(base_graph, seed, config, dominant_god, with_belakor) }
        restore_curse_count()
        return unpack(result)
    end

    local mutated = {}
    local converted = 0
    for node_key, node in pairs(base_graph) do
        if type(node) == "table" and node.type == "SHOP" then
            local copy = table.clone(node)
            copy.type = "TRAVEL"
            copy.label = 0
            mutated[node_key] = copy
            converted = converted + 1
        else
            mutated[node_key] = node
        end
    end

    if converted > 0 then
        mod:info("deus_populate_graph: converted %d SHOP node(s) to TRAVEL", converted)
    end

    local result = { func(mutated, seed, config, dominant_god, with_belakor) }
    restore_curse_count()
    return unpack(result)
end)

-- ============================================================
-- Per-career weapon override recovery (fixes CW bot ghost-scythe crash)
-- ============================================================
--
-- Crash: `Unit not found wpn_bw_ghost_scythe_01_3p` (Necromancer base mesh) when a
-- Sienna Unchained bot spawns with the ghost scythe (the scythe can_wield all four
-- Sienna careers; non-Necromancer careers use `_fire` mesh variants via
-- `ItemMasterList.bw_ghost_scythe.right_hand_unit_override`).
--
-- Vanilla flow:
--   simple_inventory_extension.add_equipment passes `self._career_name` to
--   gear_utils.create_equipment, which calls
--   `BackendUtils.get_item_units(item_data, nil, nil, career_name)`. The override
--   block at `backend_utils.lua:159-162` is gated on `career_name`, so when it
--   arrives nil, the BASE `right_hand_unit` survives — and `gear_utils.lua:189`
--   derives the 3P path as `weapon_unit_name .. "_3p"` (base 3P), which isn't
--   in the bot's preloaded packages → `world.spawn_unit` fatal.
--
-- Why career_name arrives nil: observed in weapon_tweaker v0.12.23/v0.12.24 — the
-- hook chain between simple_inventory and the unwrapped gear_utils drops the arg
-- (multiple modded create_equipment hooks chain via varargs, and one of them
-- occasionally loses the trailing args). weapon_tweaker fixed this for users with
-- that mod loaded; users who only have chaos_wastes_tweaker need the same fix here.
--
-- Fix (two layers):
--   1. If career_name is nil at hook entry, recover it from the 3P unit's
--      `inventory_system._career_name` (set in `SimpleInventoryExtension.init`
--      before extensions_ready fires).
--   2. If item_data has a per-career override AND we have career_name, pre-resolve
--      `item_units` ourselves and pass via override_item_units. Vanilla
--      gear_utils uses `override_item_units or get_item_units(...)`, so our
--      pre-resolved table is used verbatim and the broken chain pass-through is
--      sidestepped entirely.
--
-- Originally landed in weapon_tweaker v0.12.23-25; cross-ported here so the fix
-- works for users running ct without wt. Both mods can host the hook safely
-- (VMF chains them and the operation is idempotent — if the upstream hook
-- already pre-resolved override_item_units, our `override_item_units == nil`
-- guard skips the re-resolve).
mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    if career_name == nil and unit_3p and ScriptUnit and ScriptUnit.has_extension
            and ScriptUnit.has_extension(unit_3p, "inventory_system") then
        local inv = ScriptUnit.extension(unit_3p, "inventory_system")
        career_name = inv and inv._career_name or nil
    end

    if override_item_units == nil and item_data and career_name and BackendUtils
            and BackendUtils.get_item_units
            and ((item_data.right_hand_unit_override and item_data.right_hand_unit_override[career_name])
              or (item_data.left_hand_unit_override and item_data.left_hand_unit_override[career_name])) then
        local ok_resolve, resolved = pcall(BackendUtils.get_item_units, item_data, item_data.backend_id, nil, career_name)
        if ok_resolve and type(resolved) == "table" then
            override_item_units = resolved
        end
    end

    return func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
end)

-- `_chest_conversions_this_level` is declared earlier in this file (search for
-- the populate_pickups hook) and reset there at the top of every populate.
-- That placement is required because Lua 5.1 binds closure locals at creation
-- time, and consolidating populate_pickups hooks into one avoids the VMF
-- "Attempting to rehook active hook" warning.

-- Hook on PickupSystem._spawn_pickup — the lowest-level spawn function that ALL
-- paths route through (public spawn_pickup, spawn_pickup_async, buff_spawn_pickup,
-- _spawn_guaranteed_pickup, _spawn_spread_pickups). Used for two purposes:
--
-- 1. Substitute loot_die → deus_soft_currency on injected adventure levels.
--    The Bogenhafen loot-die system has no CW analogue. Catches:
--      a. Guaranteed spawners with loot_die data (also covered by our explicit
--         hook on _spawn_guaranteed_pickup above, but doesn't hurt to double-up).
--      b. Flow-event spawned loot dice (level-script-driven bonus dice drops).
--      c. Boss kill loot if the game_mode somehow returned "loot_die" (vanilla
--         GameModeDeus.get_boss_loot_pickup returns "deus_soft_currency" already
--         for our deus-mode adventure levels, but defensive).
--
-- 2. Disable physics collision on CW altars/chests so they don't block player
--    pathing at adventure spawner positions (designed for ammo/healing, not for
--    a multi-meter-wide blocking prop). `Actor.set_collision_enabled(false)`
--    removes the character-controller block; interaction raycasts still hit the
--    visible mesh, so E-to-open still works.
local _CW_BLOCKING_PICKUP_NAMES = {
    deus_weapon_chest = true,
    deus_cursed_chest = true,
    deus_02 = true,  -- alternate chest variant some CW level pickup_settings reference
}

mod:hook("PickupSystem", "_spawn_pickup", function(func, self, settings, pickup_name, position, rotation, flag, spawn_type, ...)
    if on_injected_adventure_level() and pickup_name == "loot_die" then
        pickup_name = "deus_soft_currency"
        settings = (AllPickups and AllPickups.deus_soft_currency) or settings
    end

    local unit, extra = func(self, settings, pickup_name, position, rotation, flag, spawn_type, ...)
    if on_injected_adventure_level() and _CW_BLOCKING_PICKUP_NAMES[pickup_name]
            and unit and Unit.alive(unit) then
        -- v0.6.31 revision: v0.6.28's `set_scene_query_enabled(false)` made the chest
        -- walk-through BUT broke interaction — DeusCursedChestExtension uses a sphere
        -- overlap with `filter_overlap_interaction` (generic_unit_interactor_extension.lua:254)
        -- which depends on scene_query. So we keep scene_query enabled and instead
        -- reclassify the actor's collision filter to `filter_trigger` (the vanilla
        -- "non-blocking interactable" filter — see ai_utils.lua:521 for the canonical
        -- pattern). The player_mover sweep ignores `filter_trigger` actors; raycast
        -- overlaps still hit them.
        -- Stingray `Unit.actor` is 1-indexed (see ai_inventory_extension.lua:434).
        local num_actors = (Unit.num_actors and Unit.num_actors(unit)) or 0
        local disabled = 0
        for i = 1, num_actors do
            local actor = Unit.actor(unit, i)
            if actor then
                if Actor.set_collision_filter then Actor.set_collision_filter(actor, "filter_trigger") end
                if Actor.set_collision_enabled then Actor.set_collision_enabled(actor, false) end
                disabled = disabled + 1
            end
        end
        mod:info("[no-block] %s: %d/%d actors set to filter_trigger + collision disabled", pickup_name, disabled, num_actors)
    end
    return unit, extra
end)

mod:hook("PickupSystem", "_spawn_guaranteed_pickup", function(func, self, spawner_unit, spawn_type)
    if not on_injected_adventure_level() then
        return func(self, spawner_unit, spawn_type)
    end

    -- loot_die spawners on Bogenhafen (Brugrodder '68 bottle, etc.) are guaranteed
    -- side-objective collectibles. We have no CW equivalent system — convert these
    -- positions to deus_soft_currency (Pilgrim's Coin) so the spawner still gives
    -- something useful instead of dropping a collectible the run can't interact with.
    if Unit.get_data(spawner_unit, "loot_die") then
        local settings = AllPickups and AllPickups.deus_soft_currency
        if settings then
            local position = Unit.local_position(spawner_unit, 0)
            local rotation = Unit.local_rotation(spawner_unit, 0)
            return self:_spawn_pickup(settings, "deus_soft_currency", position, rotation, false, spawn_type)
        end
        return func(self, spawner_unit, spawn_type)
    end

    local is_tome = Unit.get_data(spawner_unit, "tome")
    local is_grim = Unit.get_data(spawner_unit, "grimoire")
    if not is_tome and not is_grim then
        return func(self, spawner_unit, spawn_type)
    end

    -- Respect the user's `cursed_chest_count` setting. Once we've converted
    -- that many book locations, skip the remaining ones (no pickup spawns —
    -- the empty book pedestal isn't visible since adventure flow units only
    -- materialize after spawn). Default is 1 chest per mission.
    local cap = mod:get("cursed_chest_count") or 1
    if _chest_conversions_this_level >= cap then
        return  -- skip; leave the spawner alone
    end

    local pickup_name = "deus_cursed_chest"
    local settings = AllPickups and AllPickups[pickup_name]
    if not settings then
        -- AllPickups not yet built (extremely unlikely at populate time, but defensive).
        return func(self, spawner_unit, spawn_type)
    end

    local position = Unit.local_position(spawner_unit, 0)
    local rotation = Unit.local_rotation(spawner_unit, 0)
    local spawned_unit = self:_spawn_pickup(settings, pickup_name, position, rotation, false, spawn_type)
    _chest_conversions_this_level = _chest_conversions_this_level + 1
    return spawned_unit
end)

-- Grant CW-pickup eligibility on adventure-level spawners that have analogous
-- adventure tags. Vanilla `PickupSystem._can_spawn` returns
-- `Unit.get_data(spawner, pickup_name) or Managers.mechanism:can_spawn_pickup(spawner, pickup_name)`.
-- For adventure spawners, neither path matches CW pickup types — they're tagged
-- `potions`/`painting_scrap`/`ammo`/etc., not `deus_potion`/`deus_cursed_chest`. So
-- our deus pickup counts in pickup_settings.primary result in "spawn debt" warnings
-- (engine wanted N, found 0 eligible spawners).
--
-- Mapping (only fires on injected adventure levels):
--   * potion spawners       → deus_potions   (any pickup in Pickups.deus_potions)
--   * painting_scrap spots  → deus_soft_currency (Pilgrim's Coin)
--   * non-claimed primaries → deus_weapon_chest (altars compete with ammo/healing
--                              for remaining primary spawn slots)
mod:hook("PickupSystem", "_can_spawn", function(func, self, spawner_unit, pickup_name)
    local ok = func(self, spawner_unit, pickup_name)
    if ok then return ok end

    if not on_injected_adventure_level() then return ok end

    -- Reserved for the tome/grim → Chest of Trials conversion (see
    -- _spawn_guaranteed_pickup hook below). Never let any CW pickup hijack
    -- these book spots.
    if Unit.get_data(spawner_unit, "tome") or Unit.get_data(spawner_unit, "grimoire") then
        return false
    end

    -- Triggered event spawners (lamp_oil barrels for wagon-escape, explosive_barrel
    -- for body-burn objectives, training_dummy_bob spawners, etc.) MUST stay
    -- exclusive to their tagged pickup type. The vanilla `_can_spawn` checks
    -- `Unit.get_data(spawner, pickup_name)` — only e.g. `lamp_oil = true` returns
    -- true. But `_spawn_guaranteed_pickup` iterates ALL pickup names, and our
    -- CW-type fallback below would otherwise add `healing_draught`, `strength_potion`,
    -- etc. to the candidate list, so a triggered barrel-spawner could roll a potion
    -- and break the scripted event. v0.6.32 burned this: barrels for "burn the bodies"
    -- type events sometimes appeared as potions.
    -- Same risk for guaranteed_spawn spawners (already filtered for tome/grim
    -- above) and specified spawners.
    if Unit.get_data(spawner_unit, "guaranteed_spawn") then
        return false
    end
    local triggered_spawn_id = Unit.get_data(spawner_unit, "triggered_spawn_id")
    if triggered_spawn_id and triggered_spawn_id ~= "" then
        return false
    end

    -- CW pickups accept any non-tome/grim, non-event primary spawner. They
    -- compete with vanilla ammo/healing/grenades for unclaimed slots: ammo
    -- iterates first (vanilla `_can_spawn` returns true on ammo-tagged spawners
    -- before our hook runs), so ammo claims its 5 tagged spawners; same for
    -- healing and grenades. CW types then claim remaining primary slots up to
    -- their requested counts (deus_potions = 30, deus_soft_currency = 30, etc.).
    -- Adventure levels typically have ~30 primary spawners; expect spawn_debt
    -- warnings for the surplus, which is harmless.
    if Pickups and Pickups.deus_potions and Pickups.deus_potions[pickup_name] then
        return true
    end
    if pickup_name == "deus_soft_currency" then
        return true
    end
    if pickup_name == "deus_weapon_chest" then
        return true
    end

    return false
end)

-- ============================================================
-- Respawn / Revive on Chest of Trials Completion
-- ============================================================

-- CLARIFY: STATES.OPEN = 3 in deus_cursed_chest_extension.lua. State transitions to OPEN at line
-- 174 of that file ONLY on the server, and ONLY when the curse encounter's terror event has ended
-- successfully. Hot-join clients enter HOTJOIN_OPEN (= 4) instead, so they do not trigger here.
local CURSED_CHEST_STATE_OPEN = 3
-- CLARIFY: DifficultyMapping["normal"] = "recruit" (difficulty_settings.lua:424). The string the
-- engine uses internally is "normal"; "recruit" is only the display name.
local DIFFICULTY_RECRUIT = "normal"
-- CLARIFY: peer_id -> true marker, set by the chest hook for any player whose health_state was
-- "dead" at the moment the chest opened. Consumed by the sync_health_state hook (THP override)
-- and the _respawn_player hook (wounded). Cleared in _respawn_player so a future Chest of Trials
-- in the same run can re-mark the same peer.
local pending_chest_respawn = {}

mod:hook_safe("DeusCursedChestExtension", "_set_state", function(self, state)
    if state ~= CURSED_CHEST_STATE_OPEN then
        return
    end
    if not mod:get("respawn_on_chest_complete") then
        return
    end
    if not Managers.player or not Managers.player.is_server then
        return
    end

    local game_mode = Managers.state and Managers.state.game_mode
    if not game_mode then
        return
    end

    local side = Managers.state.side and Managers.state.side:get_side_from_name("heroes")
    local party = side and side.party
    local occupied_slots = party and party.occupied_slots

    if occupied_slots then
        for i = 1, #occupied_slots do
            local status = occupied_slots[i]
            local data = status.game_mode_data
            local peer_id = status.peer_id
            local local_player_id = status.local_player_id

            if peer_id and local_player_id then
                local player = Managers.player:player(peer_id, local_player_id)
                local unit = player and player.player_unit

                -- CLARIFY: Revive any knocked-down player who isn't being held by a disabler.
                -- is_disabled_by_pact_sworn (generic_status_extension.lua:2154) returns true for
                -- pack-master / hook / tentacle / chaos-spawn / vortex / corruptor / pounce —
                -- skipping those avoids yanking someone out of an in-progress disabler interaction
                -- (which would desync the disabler's animation and is unrecoverable). The engine's
                -- own revive can_interact (interactions.lua:181-191) uses an equivalent check.
                -- set_revived_network alone is sufficient: PlayerUnitHealthExtension.update sees
                -- state="knocked_down" + is_revived() and runs _revive(), which clears
                -- knocked_down, sets wounded(reason="revived"), and restores percent-on-revive
                -- health + 50% THP from difficulty settings (player_unit_health_extension.lua:273).
                if unit and Unit.alive(unit) then
                    local status_ext = ScriptUnit.has_extension(unit, "status_system")
                    if status_ext and status_ext.is_knocked_down and status_ext:is_knocked_down()
                        and not (status_ext.is_disabled_by_pact_sworn and status_ext:is_disabled_by_pact_sworn())
                    then
                        StatusUtils.set_revived_network(unit, true, nil)
                    end
                end

                -- CLARIFY: Mark dead-state players for the post-respawn THP/wounded overrides.
                -- This is captured at chest-open time, not at spawn time, so we know exactly which
                -- respawns came from this feature (vs. the standard 30s timer respawn that may
                -- have completed earlier in the same level).
                if data and data.health_state == "dead" then
                    pending_chest_respawn[peer_id] = true
                end
            end
        end
    end

    if game_mode.force_respawn_dead_players then
        game_mode:force_respawn_dead_players()
    end
end)

-- CLARIFY: THP override on the dead-respawn path. sync_health_state reads
-- status.game_mode_data.temporary_health_percentage (player_unit_health_extension.lua:111), which
-- the engine sets from difficulty.respawn.temporary_health_percentage at respawn_handler.lua:358
-- (0 on Recruit/Veteran/Champion, 0.25 on Legend). Mutating to 0.5 just before sync reads it
-- means the spawn applies 50% of max-health THP without us touching the network game object
-- ourselves. The is_dead-at-chest-open guard means this only fires for our feature's respawns.
mod:hook("PlayerUnitHealthExtension", "sync_health_state", function(func, self)
    local player = self.player
    local peer_id = player and player.network_id and player:network_id()

    if peer_id and pending_chest_respawn[peer_id] then
        local status = Managers.party:get_player_status(peer_id, player:local_player_id())
        if status and status.game_mode_data and status.game_mode_data.health_state == "respawning" then
            status.game_mode_data.temporary_health_percentage = 0.5
        end
    end

    func(self)
end)

-- CLARIFY: Apply wounded (1 wound) on dead-respawn above Recruit. Mirrors the engine's own
-- post-revive wound at player_unit_health_extension.lua:277 — same reason string ("revived"),
-- which is one of the four valid entries in NetworkLookup.set_wounded_reasons. Recruit is skipped
-- because it has 5 max wounds and no real wounded mechanic in player perception. The flag is
-- cleared here so a subsequent dead-respawn (different chest, same run) re-arms via the chest
-- hook above instead of double-applying.
mod:hook_safe("RespawnHandler", "_respawn_player", function(self, player, profile_index, career_index, respawn_unit, ...)
    local peer_id = player and player.network_id and player:network_id()
    if not peer_id or not pending_chest_respawn[peer_id] then
        return
    end
    pending_chest_respawn[peer_id] = nil

    if Managers.state.difficulty:get_difficulty() == DIFFICULTY_RECRUIT then
        return
    end

    local unit = player.player_unit
    if not unit or not Unit.alive(unit) then
        return
    end

    local t = Managers.time:time("game")
    StatusUtils.set_wounded_network(unit, true, "revived", t)
end)

-- ============================================================
-- Starting Boons
-- ============================================================

-- Starting-boons hook. Vanilla `_add_initial_power_ups` adds talent power-ups + event
-- boons after run setup; we append toggled starting boons after that (hook_safe = post-call).
--
-- HOST-ONLY: the server processes the hook for every peer in the lobby and uses the
-- HOST's `start_boon_*` settings — so every player gets the same starting boons,
-- whatever the host picked. Clients early-out unconditionally and never apply their
-- own start_boon settings (and never duplicate the host's grant either, which was
-- the old bug). The server's `run_state:set_player_power_ups(peer_id, ...)` call
-- syncs the granted boons to the target peer via the shared-state networking layer.
-- QUESTION: The hook signature drops the 5th arg `initial_talents_for_career` (vanilla has 5
-- positional args). hook_safe ignores extra args so this is fine, but a future maintainer adding a
-- new arg might be confused.
-- POTENTIAL BUG (LOW): `mod:echo` fires on every player-add (incl. bots/late-join), spamming chat
-- with "Granted N starting boon(s)." Once per run would be cleaner.
mod:hook_safe("DeusRunController", "_add_initial_power_ups", function(self, peer_id, local_player_id, profile_index, career_index)
    local run_state = self._run_state
    if not run_state or not run_state:is_server() then return end  -- host-only
    if not DeusPowerUpsArray or not DeusPowerUpUtils then return end

    local extra = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and mod:get("start_boon_" .. name) then
            extra[#extra + 1] = DeusPowerUpUtils.generate_specific_power_up(name, entry.rarity)
        end
    end

    if #extra == 0 then return end

    -- CLARIFY: Re-fetching existing power-ups inside the hook (rather than capturing pre-call) is
    -- correct: the original func has already added talent + event boons by the time this fires
    -- (hook_safe = post-call). table.clone with skip_metatable keeps the array shape without
    -- copying any inherited methods.
    local skip_metatable = true
    local existing = run_state:get_player_power_ups(peer_id, local_player_id, profile_index, career_index)
    local new_power_ups = table.clone(existing, skip_metatable)
    table.append(new_power_ups, extra)
    run_state:set_player_power_ups(peer_id, local_player_id, profile_index, career_index, new_power_ups)

    -- Resolve the player's character + career for the chat message. SPProfiles maps
    -- profile_index → profile (Kruber/Bardin/Kerillian/Sienna/Saltzpyre) and
    -- profile.careers maps career_index → career (es_mercenary, dr_slayer, etc.).
    -- Both use localization keys for display; Localize() resolves them to the
    -- player-facing names.
    local profile = rawget(_G, "SPProfiles") and SPProfiles[profile_index]
    local character = profile and profile.display_name and Localize(profile.display_name) or "?"
    local career = profile and profile.careers and profile.careers[career_index]
    local career_name = career and career.display_name and Localize(career.display_name) or "?"
    -- Player slot in the party: peer_id + local_player_id. Use party-slot index if
    -- available so users can quickly identify which on-screen panel got the boons.
    local slot_label = ""
    local party_manager = Managers.party
    if party_manager and party_manager.get_status_from_unique_id then
        local status = party_manager:get_status_from_unique_id(peer_id, local_player_id)
        if status and status.party_id and status.slot_id then
            slot_label = string.format(" [P%d:S%d]", status.party_id, status.slot_id)
        end
    end

    mod:echo(string.format("Granted %d starting boon(s) to %s (%s)%s",
        #extra, character, career_name, slot_label))
end)

-- ============================================================
-- Modified Boons
-- ============================================================

-- CLARIFY: `reckless_swings_originals` doubles as a "tweak active" flag. Non-nil = tweak applied.
-- This avoids double-apply (which would save the already-modified values as "originals" and lose
-- the real originals).
local reckless_swings_originals = nil

-- CLARIFY: Khaine's Fury (internal name `deus_reckless_swings`) softening:
--   vanilla:  health threshold 0.50, self-damage 3 per melee hit
--   tweaked:  health threshold 0.25, self-damage 1 per melee hit
-- Patches THREE places: the on-buff template (governs gameplay), description_values[1] (the % shown
-- in tooltip's "above X% Health"), and description_values[3] (the damage shown). The `Localize`
-- hook below also overrides the description text since its formatting may not refer to
-- description_values directly.
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

    -- POTENTIAL BUG (LOW): Hard-codes index [1] for buffs and [1]/[3] for description_values. If
    -- FatShark reorders these arrays in a patch, we silently mutate the wrong fields. A more
    -- defensive version would search by buff_to_add or description key.
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

-- CLARIFY: Mirrors apply_reckless_swings_tweak. Note the early-out when DeusPowerUpTemplates is
-- gone (e.g. user left Chaos Wastes) — we still clear the originals flag so the next entry can
-- re-apply cleanly. This is the only path that nils the flag without doing the actual restore.
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

-- CLARIFY: Description override for Khaine's Fury lives in the consolidated _G.Localize
-- hook above (search for ADV_TITLE_OVERRIDES). Centralized to avoid the VMF
-- "Attempting to rehook active hook [Localize]" warning when two hooks compete for the
-- same target. The `reckless_swings_originals` gate ensures the override only fires
-- while the tweak is active.

-- CLARIFY: Assignment to the forward-declared `sync_reckless_swings`. From here on, references at
-- the top of the file (in generate_random_power_ups hook) and the on_setting_changed callback
-- below resolve to this function.
sync_reckless_swings = function()
    if mod:get("tweak_reckless_swings") then
        apply_reckless_swings_tweak()
    else
        revert_reckless_swings_tweak()
    end
end

-- CLARIFY: Apply once at mod load. If the user has the toggle on AND DeusPowerUpTemplates is
-- already loaded (e.g. they enter the Keep, hot-reload doesn't apply since chaos_wastes_tweaker is
-- restart-only per CLAUDE.md), this immediately patches. Outside CW, DeusPowerUpTemplates is nil
-- and the apply silently no-ops; the generate_random_power_ups hook re-runs sync on first roll.
sync_reckless_swings()

-- ============================================================
-- Bomb Boon Cooldown Tweak
-- ============================================================
-- The `drop_item_on_ability_use` boon (rally flag / Morgrim's / Endless Bombs) reads its per-item
-- cooldowns from `buff_template.buffs[1].cooldown_durations` at proc time
-- (morris_buff_settings.lua:2830). Mutating that table in place lets us uniformly override the
-- vanilla 180/180/120 with a single configurable value. Mirrors the reckless_swings save-and-
-- restore pattern: the mutation persists across hook calls within a session, so on_disabled has
-- to revert it.

local bomb_cooldown_originals = nil

local function apply_bomb_cooldown_tweak()
    if bomb_cooldown_originals then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.drop_item_on_ability_use
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local durations = buff_entry and buff_entry.cooldown_durations
    if not durations then
        mod:info("[bomb-cooldown] DeusPowerUpTemplates.drop_item_on_ability_use not loaded yet; will retry on next boon roll")
        return
    end

    local override = mod:get("bomb_boon_cooldown")
    if not override or override <= 0 then
        mod:info("[bomb-cooldown] override=%s (no change)", tostring(override))
        return
    end

    bomb_cooldown_originals = {}
    local before = {}
    for k, v in pairs(durations) do
        before[#before + 1] = string.format("%s=%d", k, v)
        bomb_cooldown_originals[k] = v
        durations[k] = override
    end
    mod:info("[bomb-cooldown] override=%d applied. Was: %s", override, table.concat(before, ", "))
end

local function revert_bomb_cooldown_tweak()
    if not bomb_cooldown_originals then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.drop_item_on_ability_use
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local durations = buff_entry and buff_entry.cooldown_durations
    if durations then
        for k, v in pairs(bomb_cooldown_originals) do
            durations[k] = v
        end
    end
    bomb_cooldown_originals = nil
end

sync_bomb_cooldown = function()
    -- Always revert first so a setting change from one positive value to another re-applies the
    -- new value (rather than silently no-op'ing because originals are already saved).
    revert_bomb_cooldown_tweak()
    local override = mod:get("bomb_boon_cooldown")
    if override and override > 0 then
        apply_bomb_cooldown_tweak()
    end
end

sync_bomb_cooldown()

-- ============================================================
-- Endless Bombs Consumes Morgrim's
-- ============================================================
-- Vanilla `apply_pockets_full_of_bombs_buff` calls `inventory_extension:drop_level_event_item`
-- when the player is wielding slot_level_event, which spawns the held item back as a pickup on the
-- ground. With this toggle the saved Morgrim's Bomb is destroyed instead of dropped — same end
-- state as if the potion had eaten it.
-- CLARIFY: hook target is `BuffFunctionTemplates.functions` (the merged table built by
-- buff_function_templates.lua:5568 via DLCUtils.merge), NOT `BuffFunctionTemplates` directly. The
-- table-form mod:hook resolves the function value at registration time, so the guard prevents
-- a nil-table crash if the buff system somehow isn't loaded yet.
if BuffFunctionTemplates and BuffFunctionTemplates.functions then
    mod:hook(BuffFunctionTemplates.functions, "apply_pockets_full_of_bombs_buff", function(func, unit, buff, params)
        if not mod:get("endless_bombs_consumes_morgrim") then
            return func(unit, buff, params)
        end

        local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
        if inventory_extension then
            local slot_data = inventory_extension:get_slot_data("slot_level_event")
            local item_data = slot_data and slot_data.item_data
            if item_data and item_data.name == "holy_hand_grenade" then
                -- destroy_slot is what drop_level_event_item calls at its end; we skip the in-between
                -- pickup-spawn so the bomb isn't recoverable.
                inventory_extension:destroy_slot("slot_level_event")
            end
        end

        return func(unit, buff, params)
    end)
end

-- ============================================================
-- Block Ranger Veteran from Saving Morgrim's
-- ============================================================
-- The `bardin_ranger_passive_consumeable_dupe_grenade` passive applies `not_consume_grenade` as a
-- proc stat_buff with proc_chance=0.1. When ActionChargedProjectileUtility.fire_charged_projectile
-- throws a grenade, it queries `apply_buffs_to_value(0, "not_consume_grenade")` to roll the proc
-- (action_charged_projectile.lua:83). We monkey-patch the buff_extension instance for the duration
-- of the call so the proc returns false specifically when the grenade is a Morgrim's Bomb. Other
-- grenades (frag, fire, conflagration) continue to roll normally.
mod:hook("ActionChargedProjectileUtility", "fire_charged_projectile", function(func, projectile_context, ...)
    if not mod:get("rv_no_save_morgrim")
        or not projectile_context
        or projectile_context.item_name ~= "holy_hand_grenade"
        or not projectile_context.is_grenade
        or projectile_context.grenade_thrown
    then
        return func(projectile_context, ...)
    end

    local buff_ext = projectile_context.buff_extension
    if not buff_ext then
        return func(projectile_context, ...)
    end

    -- rawget so we know whether the instance had a pre-existing override (vs. inheriting via
    -- __index from the class). On restore we either reinstate the override or clear our shim.
    local had_instance_override = rawget(buff_ext, "apply_buffs_to_value") ~= nil
    local original = buff_ext.apply_buffs_to_value
    buff_ext.apply_buffs_to_value = function(self, value, stat_buff_name, ...)
        if stat_buff_name == "not_consume_grenade" then
            return value, false
        end
        return original(self, value, stat_buff_name, ...)
    end

    local ok, a, b = pcall(func, projectile_context, ...)

    if had_instance_override then
        buff_ext.apply_buffs_to_value = original
    else
        buff_ext.apply_buffs_to_value = nil
    end

    if not ok then
        error(a, 0)
    end
    return a, b
end)

-- Pool-affecting settings: master toggle, per-CW-scenario toggles, and per-adventure
-- toggles. Re-run inject_pool() on any of these so changes take effect without a
-- restart. The engine reads LEVEL_AVAILABILITY at run setup (DeusMechanism._setup_run)
-- — changes only affect the NEXT expedition, not a CW run already underway.
local function is_pool_setting(setting_id)
    if setting_id == "inject_adventure_maps" then return true end
    if type(setting_id) ~= "string" then return false end
    return setting_id:find("^enable_adventure_") ~= nil
        or setting_id:find("^enable_cw_") ~= nil
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "tweak_reckless_swings" then
        sync_reckless_swings()
    elseif setting_id == "bomb_boon_cooldown" then
        sync_bomb_cooldown()
    elseif is_pool_setting(setting_id) then
        -- inject_pool() is idempotent: takes a one-time snapshot, resets to it on
        -- every call, then applies current toggle state. Master-off branch inside
        -- skips inject and leaves the pool at vanilla.
        AdventurePool.inject_pool()
    end
end

-- Clean disable: revert the persistent DeusPowerUpTemplates mutations (Khaine's Fury and bomb-boon
-- cooldowns) so toggling the mod off via VMF doesn't leave them in a tweaked state until restart.
-- All other mutations in this mod are scoped (save-and-restore inside hooks).
mod.on_disabled = function()
    revert_reckless_swings_tweak()
    revert_bomb_cooldown_tweak()
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

mod:command("dump_traits", "Dump every CW weapon trait that can roll, with localized display name and description", function(filter)
    if not DeusWeapons then
        mod:echo("DeusWeapons not loaded.")
        return
    end
    local WT = rawget(_G, "WeaponTraits")
    if not WT or not WT.traits then
        mod:echo("WeaponTraits.traits not loaded.")
        return
    end

    local rollable = {}
    for _, data in pairs(DeusWeapons) do
        local baked = data.baked_trait_combinations
        if baked then
            for _, combo in ipairs(baked) do
                for _, trait_name in ipairs(combo) do
                    rollable[trait_name] = true
                end
            end
        end
    end

    local sorted = {}
    for name in pairs(rollable) do
        if not filter or name:find(filter, 1, true) then
            sorted[#sorted + 1] = name
        end
    end
    table.sort(sorted)

    local function resolve(key)
        if not key then return "" end
        local raw = Localize(key)
        if raw and raw ~= "<" .. key .. ">" then
            return raw
        end
        return ""
    end

    mod:info("[DUMP:traits] === %d rollable CW traits ===", #sorted)
    mod:info("[DUMP:traits] trait_name\tdisplay_name_key\tdisplay_text\tdesc_key\tdesc_text")
    for _, name in ipairs(sorted) do
        local td = WT.traits[name]
        local dn_key = td and td.display_name or ""
        local desc_key = td and td.advanced_description or ""
        mod:info("[DUMP:traits] %s\t%s\t%s\t%s\t%s",
            name, dn_key, resolve(dn_key), desc_key, resolve(desc_key))
    end
    mod:echo(string.format("dump_traits: %d traits dumped to log.", #sorted))
end)

-- Resolves the canonical in-game display name for every adventure level AND every
-- vanilla CW scenario in the catalog. Emits tab-separated rows to the log
-- (`[DUMP:adv_names]`) for paste-back into _adventure_pool.lua. The level's
-- `display_name` is a loc key that Localize() resolves to the English string. Works
-- in the keep or the CW hub — no need to be in a mission.
mod:command("dump_adventure_names", "Resolve in-game names for every adventure level + CW scenario", function()
    if not LevelSettings then
        mod:echo("LevelSettings not loaded.")
        return
    end

    local function resolve(key)
        if not key or key == "" then return "" end
        local raw = Localize(key)
        if raw and raw ~= "<" .. key .. ">" then return raw end
        return ""
    end

    mod:info("[DUMP:adv_names] === ADVENTURE MISSIONS ===")
    mod:info("[DUMP:adv_names] level_key\tdisplay_text\tdlc_name\tact\tlevel_bundle_path")
    for _, entry in ipairs(AdventurePool.ADVENTURE_MISSIONS) do
        local lvl = entry.key
        local v = rawget(LevelSettings, lvl)
        local dn_key = v and v.display_name or ""
        local level_name = v and v.level_name or ""
        local dlc_name = v and v.dlc_name or "(base)"
        local act = v and v.act or ""
        mod:info("[DUMP:adv_names] %s\t%s\t%s\t%s\t%s", lvl, resolve(dn_key), dlc_name, act, level_name)
    end

    mod:info("[DUMP:adv_names] === CW SCENARIOS ===")
    mod:info("[DUMP:adv_names] cw_key\ttitle_key\tdisplay_text\tbase_level_name")
    for _, scen in ipairs(AdventurePool.CW_SCENARIOS) do
        local dls = rawget(DEUS_LEVEL_SETTINGS or {}, scen.key)
        -- CW levels' user-facing title is `<level_key>_title` per level_settings_morris.lua:112
        local title_key = scen.key .. "_title"
        local base = dls and dls.base_level_name or scen.key
        mod:info("[DUMP:adv_names] %s\t%s\t%s\t%s", scen.key, title_key, resolve(title_key), base)
    end

    local total = #AdventurePool.ADVENTURE_MISSIONS + #AdventurePool.CW_SCENARIOS
    mod:echo(string.format("dump_adventure_names: %d entries dumped to log (%d adventures + %d CW).",
        total, #AdventurePool.ADVENTURE_MISSIONS, #AdventurePool.CW_SCENARIOS))
end)

mod:command("pool_status", "Dump current CW map-pool state (TRAVEL/SIGNATURE keys per journey)", function()
    AdventurePool.dump_pool_state()
end)

-- Manual re-run of pool injection. Useful for debugging: if you toggle settings in VMF
-- and want to see them take effect without restarting the game, run this from the keep
-- BEFORE entering a CW run. The engine reads LEVEL_AVAILABILITY at run setup
-- (DeusMechanism._setup_run); changes only take effect for the NEXT run, not the current one.
mod:command("force_inject_pool", "Re-run adventure pool injection now", function()
    if not mod:get("inject_adventure_maps") then
        mod:echo("inject_adventure_maps is OFF — enable it first.")
        return
    end
    local n = AdventurePool.inject_pool()
    mod:echo("inject_pool ran: " .. tostring(n) .. " adventures injected (check log for details).")
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
