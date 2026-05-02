local mod = get_mod("ct")

local MOD_VERSION = "0.3.4-dev"
mod:info("Chaos Wastes Tweaker v%s loaded", MOD_VERSION)
mod:echo("Chaos Wastes Tweaker v" .. MOD_VERSION)

local SHRINE_DEFAULT = 4
local CHEST_DEFAULT = 3
local FINALE_GODS = { "nurgle", "tzeentch", "khorne", "slaanesh" }

local granting_starting_coins = false
local all_trait_combos_cache = nil
-- CLARIFY: Forward-declared so the `generate_random_power_ups` hook (call site line 150) and
-- `on_setting_changed` (line 740) can reference sync_reckless_swings before its assignment at line
-- 724. Lua 5.1 locals are not hoisted; without this stub the references would either resolve to a
-- global lookup (and silently no-op until the assignment runs) or crash. See
-- feedback_lua_forward_reference.md (5 prior crashes from this exact bug pattern).
local sync_reckless_swings

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

    if DeusPowerUpsArray then
        -- CLARIFY: Iterate backwards so table.remove indices stay stable. The saved `index` is the
        -- pre-removal slot, which is the correct insertion point for restoration in reverse order.
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
-- Starting Boons
-- ============================================================

-- CLARIFY: Starting-boons hook. Vanilla `_add_initial_power_ups` adds talent power-ups + event
-- boons after run setup. We append toggled starting boons after that runs (hook_safe = post-call).
-- The host runs this for every peer; clients only run it for their own peer (the `peer_id !=
-- own_peer_id` early-out). Without that guard, clients would each try to grant boons to all 4
-- players, causing duplication or RPC spam.
-- QUESTION: The hook signature drops the 5th arg `initial_talents_for_career` (vanilla has 5
-- positional args). hook_safe ignores extra args so this is fine, but a future maintainer adding a
-- new arg might be confused.
-- POTENTIAL BUG (LOW): `mod:echo` fires on every player-add (incl. bots/late-join), spamming chat
-- with "Granted N starting boon(s)." Once per run would be cleaner.
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

    -- CLARIFY: Re-fetching existing power-ups inside the hook (rather than capturing pre-call) is
    -- correct: the original func has already added talent + event boons by the time this fires
    -- (hook_safe = post-call). table.clone with skip_metatable keeps the array shape without
    -- copying any inherited methods.
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

-- CLARIFY: Description override fires only while the tweak is active (gate on
-- reckless_swings_originals being non-nil). The vanilla description includes literal "50%" / "3
-- damage" baked text that description_values can't fix on its own (the format string is in the
-- localized text, not the values table).
-- Note: single % here is fine because Localize returns the string as-is, not via string.format.
local RECKLESS_SWINGS_DESC_OVERRIDE = "While above 25% Health, gain 25% Power but take 1 damage on each melee hit."

mod:hook(_G, "Localize", function(func, key, ...)
    if key == "description_deus_reckless_swings" and reckless_swings_originals then
        return RECKLESS_SWINGS_DESC_OVERRIDE
    end
    return func(key, ...)
end)

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
