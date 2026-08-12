-- Adventure-map identity, localization, flow-state safety, and map presentation.
return function(mod, ctx)
    local AdventurePool = ctx.adventure_pool
    local FINALE_GODS = ctx.finale_gods
    local _dbg = ctx.dbg
    local _dump_pickup_spawners_verbose
    local _dump_pickup_system_state
    local apply_graph_snapshot = ctx.apply_graph_snapshot
    local broadcast_graph_snapshot = ctx.broadcast_graph_snapshot
    local effective_setting = ctx.effective_setting
    local is_curse_disabled = ctx.is_curse_disabled
    local adventure_base_from_level_key
    local on_injected_adventure_level

-- Issue #1271: vanilla validates lobby mission identifiers through the strict
-- NetworkLookup.mission_ids metatable. CT registers its own permutations, while
-- stale or foreign custom identifiers are discarded before vanilla indexes them.
-- This is the sole LobbyBrowserConsoleUI._remove_invalid_lobbies hook in ct_dev.
mod:hook("LobbyBrowserConsoleUI", "_remove_invalid_lobbies", function(func, self, lobbies)
    local mission_ids = NetworkLookup and rawget(NetworkLookup, "mission_ids")
    local filtered = AdventurePool.filter_lobbies_with_known_missions(lobbies, mission_ids)
    return func(self, filtered)
end)

if mod._ct_rt_register then
    mod._ct_rt_register("issue1271_lobby_mission_lookup_parity", function()
        return AdventurePool.network_lookup_parity_error()
    end)
end

-- ============================================================
-- Holy Hand Grenade spawn rate (CW campaign-map pickup pools)
-- ============================================================
-- v0.7.145-dev: REVERTED. v0.7.143-dev lowered
-- Pickups.grenades.holy_hand_grenade.spawn_weighting 0.8 -> 0.1 to make the
-- CW power-bomb rarer on injected campaign maps. THIS CRASHED THE GAME ON LOAD:
--   error.lua:26: Problem selecting a pickup to spawn,
--   spawn_weighting_total = 0.85, spawn_value = 0.943
-- The spread-pickup sampler rolls random in [0,1) and walks the pool's cumulative
-- spawn_weighting; if the pool's total is < the roll it falls off the end and
-- hard-errors. holy_hand's 0.8 weight is LOAD-BEARING for the grenade pool total
-- (other grenades summed to only ~0.75) -- dropping it to 0.1 made the total 0.85,
-- so any roll in [0.85, 1.0) crashed. This is the same sampler invariant the
-- deus_potions renormalization (search "renormaliz") already guards: a pool's
-- total must stay >= 1.0. Lowering a raw spawn_weighting violates it.
--
-- Restored to vanilla (no mutation) to stop the crash. To actually reduce the
-- rate safely we must PRESERVE the pool total -- either renormalize the whole
-- grenade pool (so holy_hand's SHARE shrinks while the sum stays >= 1.0) inside
-- the populate path, or redistribute holy_hand's removed weight onto the other
-- grenades. Do NOT reintroduce a bare `holy_hand.spawn_weighting = <low>`.

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
adventure_base_from_level_key = function(level_key)
    if type(level_key) ~= "string" or not AdventurePool then return nil end
    for base in pairs(AdventurePool.IS_INJECTED_ADVENTURE_LEVEL) do
        if level_key == base or level_key:find("^" .. base .. "_") then
            return base
        end
    end
    return nil
end

on_injected_adventure_level = function()
    if not LevelHelper then return false end
    -- v0.7.154-dev: MUST be inside an actual Chaos Wastes (deus) expedition. The
    -- adventure maps CW injects into its pool also exist in STOCK Adventure under
    -- the SAME level_id, so gating only on the level name leaked every CW-only
    -- pickup transform into real Adventure -- reported 2026-06-20: tomes/grimoires
    -- missing in Adventure (the tome/grim -> Chest-of-Trials substitution, the
    -- pedestal/collectible -> Pilgrim's Coin conversion, the no_roamers pacing
    -- filter, and force_belakor all gate on this function). Only the deus
    -- mechanism exposes get_deus_run_controller; in Adventure game_mechanism() has
    -- no such method, so this bails and Adventure plays vanilla. (Same idiom as
    -- _current_node_theme / _current_node_curse below.)
    local mechanism = Managers.mechanism and Managers.mechanism.game_mechanism
        and Managers.mechanism:game_mechanism()
    if not (mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()) then
        return false
    end
    local current = LevelHelper:current_level_settings()
    return current and adventure_base_from_level_key(current.level_id) ~= nil
end

-- Exposed for the populate_pickups hook + spawn census (both lexically EARLIER in
-- this file, so a direct reference there resolves to a nil global -- forward-ref
-- gotcha, feedback_lua_forward_reference.md). Reached via mod._ which resolves at
-- CALL time, by which point this assignment has run.
mod._ct_on_injected_adventure_level   = on_injected_adventure_level
mod._ct_adventure_base_from_level_key = adventure_base_from_level_key

-- ============================================================
-- v0.7.200-dev (#156) — CANDIDATE FIX: enable the 'adventure' object set on
-- mod-injected adventure levels under the deus game mode
-- ============================================================
-- HYPOTHESIS (2026-07-01 forensics, pending in-game verification): on
-- magnus_tzeentch_path1 ALL spawner lists were EMPTY at populate and
-- pickup_gizmo_spawned never registered a unit — the gizmos never SPAWNED.
-- Mechanism: GameModeSettings.deus.object_sets = { gm_sp = true }
-- (game_mode_settings_morris.lua:8-10) vs adventure's { adventure = true,
-- gm_sp = true } (game_mode_settings.lua:29-32). GameModeHelper.get_object_sets
-- (game_mode_helper.lua:58-111) only marks a level object set for spawning when
-- the GAME MODE's object_sets table enables it (or it's shadow_lights / flow_ /
-- team_ prefixed). Any adventure-level unit grouped in the 'adventure' object
-- set — plausibly including pickup-spawner gizmos on some level assets (set
-- membership lives in the level binary, unreadable offline; the Holly cemetery
-- HAS spawned chests when injected, so membership varies per asset) — silently
-- never spawns when that level loads under deus.
--
-- FIX SHAPE: get_object_sets returns (object_sets_map, spawned_object_sets_array);
-- the callers use them as:
--   * state_loading.lua:1405  -> spawned_object_sets -> AsyncLevelSpawner (which
--     units actually spawn)  [also the :1438 hero-sublevel call]
--   * state_ingame.lua:753    -> object_sets map (flow/team set bookkeeping)
-- We append "adventure" to the ARRAY (second return) — the map already contains
-- every available set unconditionally, so it needs no mutation. Scoped hard:
--   (1) game_mode_key == "deus",
--   (2) the level KEY currently loading resolves through the mod's STATIC
--       adventure catalog (AdventurePool.MISSION_BY_KEY — deliberately NOT the
--       toggle-gated IS_INJECTED_ADVENTURE_LEVEL, so host and joining clients
--       make the identical decision and spawn identical worlds), and
--   (3) LevelSettings[level_key].level_name matches the level_name argument
--       (guards the hero-sublevel call site and any unrelated concurrent load).
-- Vanilla deus levels have morris-native level_names/keys (no catalog match) and
-- vanilla adventure runs pass game_mode_key == "adventure" — both untouched.
--
-- GameModeHelper is a plain class table (game_mode_helper.lua:3, dot-called at
-- every site — no upvalue captures found) -> table-form hook with nil guard.
-- Dup-check 2026-07-01: no other (GameModeHelper, *) hook in ct_dev.
do
    -- Resolve the injected-adventure base for the level being spawned, or nil.
    -- Returns base_key, level_key on a match.
    local function _ct_injected_base_for_spawn(level_name)
        if not AdventurePool or not AdventurePool.MISSION_BY_KEY then return nil end
        local lth = Managers and Managers.level_transition_handler
        local level_key = lth and lth.get_current_level_keys and lth:get_current_level_keys()
        if type(level_key) ~= "string" then return nil end
        local ls = rawget(_G, "LevelSettings")
        local entry = ls and rawget(ls, level_key)
        if not entry or entry.level_name ~= level_name then return nil end
        for base in pairs(AdventurePool.MISSION_BY_KEY) do
            -- matches "magnus", "magnus_tzeentch_path1" AND dup aliases
            -- ("magnus_dup1_tzeentch_path1") — same shape as adventure_base_from_level_key.
            if level_key == base or level_key:find("^" .. base .. "_") then
                return base, level_key
            end
        end
        return nil
    end

    local _gmh = rawget(_G, "GameModeHelper")
    if _gmh and type(_gmh.get_object_sets) == "function" then
        mod:hook(_gmh, "get_object_sets", function(func, level_name, game_mode_key)
            local object_sets, spawned_object_sets = func(level_name, game_mode_key)
            local skull52_observed = false
            -- #52 diagnostics must observe BOTH the normal-Adventure baseline and
            -- injected Deus. The module scopes itself to dlc_wizards_tower (and
            -- rejects hero sublevels), so unrelated get_object_sets calls stay inert.
            if type(object_sets) == "table" and type(spawned_object_sets) == "table"
                and mod._ct_diag_skull52 and mod._ct_diag_skull52.observe_object_sets
            then
                local ok, observed = pcall(mod._ct_diag_skull52.observe_object_sets, level_name, game_mode_key,
                    object_sets, spawned_object_sets, adventure_base_from_level_key)
                skull52_observed = ok and observed == true
            end

            if game_mode_key == "deus"
                and type(object_sets) == "table"
                and type(spawned_object_sets) == "table"
            then
                -- #156 fix (behavior unchanged): enable the 'adventure' object set on the
                -- injected MAIN adventure level if present and not already spawning.
                if object_sets.adventure and not table.contains(spawned_object_sets, "adventure") then
                    local ok, base, level_key = pcall(_ct_injected_base_for_spawn, level_name)
                    if ok and base then
                        spawned_object_sets[#spawned_object_sets + 1] = "adventure"
                        -- Raw printf: proves the fix engaged even on the logging-OFF host.
                        pcall(printf, "[ct:objset] injected adventure level %s: enabling 'adventure' object set (issue #156)",
                            tostring(level_key))
                    end
                end
            end
            if skull52_observed and mod._ct_diag_skull52.finalize_selection then
                pcall(mod._ct_diag_skull52.finalize_selection, spawned_object_sets)
            end
            return object_sets, spawned_object_sets
        end)
    else
        pcall(printf, "[ct:objset] GameModeHelper.get_object_sets not hookable at load — #156 candidate fix INACTIVE")
    end
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

-- Mod Boon localization overrides (v0.7.30). The 4 ct-injected meta boons reference
-- `display_name_ct_meta_*` and `description_ct_meta_*` localization keys in their
-- DeusPowerUpTemplates entries. Vanilla Localize() returns `<key>` for keys it doesn't
-- know — so the in-game boon UI would show "<display_name_ct_meta_stagger>" unless we
-- intercept and provide the strings. Each `%` is escaped as `%%` because vanilla's
-- UIUtils.format_localized_description re-feeds via string.format (see
-- feedback_vt2_localize_string_format_pipeline.md).
local MOD_BOON_LOC = {
    display_name_ct_meta_stagger = "(Mod Boon) Reactive Bulwark",
    description_ct_meta_stagger  = "+1%% stagger power and +1%% melee cleave per active boon.",
    display_name_ct_meta_crit    = "(Mod Boon) Crit Cascade",
    description_ct_meta_crit     = "+1%% critical strike chance and +5%% critical strike effectiveness per active boon.",
    display_name_ct_meta_health  = "(Mod Boon) Vitality Cascade",
    description_ct_meta_health   = "+1%% max health and +1%% healing received per active boon.",
    display_name_ct_meta_cooldown = "(Mod Boon) Ability Cascade",
    description_ct_meta_cooldown = "+2%% cooldown regen per active boon.",
    display_name_ct_meta_movespeed = "(Mod Boon) Wind Cascade",
    description_ct_meta_movespeed  = "+1%% movement speed per active boon.",
    display_name_ct_meta_ammo      = "(Mod Boon) Quiver Cascade",
    description_ct_meta_ammo       = "+5%% total ammo, +5%% max overheat (Sienna staves, Bardin drakefire), and +5%% Moonfire Bow energy capacity per active boon. May Khaine's quivers and Vaul's forges fill in equal measure.",
    display_name_ct_kill_heal    = "(Mod Boon) Khaine's Communion",
    description_ct_kill_heal     = "Killing an enemy heals you for 1 health.",

    -- v0.7.34 Trait-as-Boon
    display_name_ct_boon_vauls_anvil         = "(Mod Boon) Vaul's Anvil",
    description_ct_boon_vauls_anvil          = "All attacks against you count as blocked while your melee weapon is wielded. Block break disables this for 10 seconds.",
    display_name_ct_boon_manann_tempest      = "(Mod Boon) Manann's Tempest",
    description_ct_boon_manann_tempest       = "Critical strikes trigger a chain lightning that jumps to up to 5 nearby enemies, ignoring armour. Stacks with the trait.",
    display_name_ct_boon_taal_twinned_arrow  = "(Mod Boon) Taal's Twinned Arrow",
    description_ct_boon_taal_twinned_arrow   = "Ranged attacks fire one additional projectile. Stacks with the trait. Has no effect without a ranged weapon.",
    display_name_ct_boon_asuryan_wrath       = "(Mod Boon) Asuryan's Wrath",
    description_ct_boon_asuryan_wrath        = "Melee kills have a 50%% chance to deal the killing blow's damage to a nearby enemy. Stacks with the trait.",
    -- #464 follow-up: trait-as-boon for Anath Raema's Swiftness, always the PERMANENT
    -- variant (independent of the tweak_anath_raema_permanent rework toggle).
    display_name_ct_boon_anath_raema_swiftness = "(Mod Boon) Anath Raema's Swiftness",
    description_ct_boon_anath_raema_swiftness  = "Reload time is halved, permanently, no ammo pickup needed. Stacks with the weapon trait.",

    -- v0.7.33 typo fix: vanilla description for Addaioth's Splendour (deus_ranged_crit_explosion
    -- trait) claims "Every 30 seconds" but the actual cooldown_duration in buff_tweak_data.lua:344
    -- is 10. Vanilla's loc string swapped the cooldown (10) and damage percent (30) when filling
    -- description_values positionally. Override returns a static, correct string.
    description_deus_ranged_crit_explosion_trait = "Every 10 seconds, ranged Critical Hits explode in an area for 30%% of their Damage. Deals damage scaled by Hero Power. Staggers nearby enemies.",
}

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

-- v0.7.65: Miracle of Ulric / Miracle of Isha localization overrides — only
-- applied when the matching tweak toggle is on, so vanilla text stays put when
-- the alternative behaviors are off. Vanilla loc keys live in compiled
-- .strings bundles (deus_blessing_settings.lua:19-26, 47-56); we intercept the
-- Localize hook to substitute when the toggle is host-active.
-- `%%` is required because UIUtils.format_localized_description re-feeds the
-- result through string.format (feedback_vt2_localize_string_format_pipeline.md).
-- v0.7.67: name override removed — vanilla already returns "Miracle of Ulric"
-- for `blessing_of_power_name` (user-confirmed 2026-05-20). Only the
-- description differs, so only the description is overridden.
local MIRACLE_LOC_OVERRIDES = {
    blessing_of_power_desc      = "Grants every hero +50 Power for the rest of the run. The bonus persists through weapon swaps and upgrades at altars.",
    blessing_of_isha_desc_aegis = "Grants every hero -25%% damage taken for the next mission.",
    blessing_of_isha_desc_wounds= "Grants every hero unlimited wounds for the next mission — every knockdown is revivable instead of resulting in instant death after the first down.",
}

-- issue 511: load-time marker for the #133 Manann's Tempest cooldown-note append
-- (the branch lives in the Localize hook below, keyed on
-- description_deus_crit_chain_lightning + tweak_manann_tempest_cooldown). Replaces
-- the io.open self-grep that threw in the VMF sandbox (no `io`). The exact branch
-- text is a source invariant flagged for a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
CT_MANANN_TEMPEST_NOTE_MARKER = "manann_tempest:crit_chain_lightning_cooldown_note_v0.7.232"
mod:hook(_G, "Localize", function(func, key, ...)
    if type(key) == "string" then
        if key == "ct_cot_cost_action" and mod._ct_cot_cost_action_text then
            return mod._ct_cot_cost_action_text()
        end
        local t = ADV_TITLE_OVERRIDES[key]
        if t then return t end
        local d = ADV_DESC_OVERRIDES[key]
        if d then return d end
        local m = MOD_BOON_LOC[key]
        if m then
            -- #133: Manann's Tempest gains an 8-second cooldown ONLY while the
            -- `tweak_manann_tempest_cooldown` tweak is active (the ProcFunctions.chain_lightning
            -- hook ~line 9835 enforces MANANN_TEMPEST_COOLDOWN_S = 8.0). Append the note only
            -- when the tweak is on so the boon text tracks behavior live; with it off the
            -- description stays EXACTLY vanilla. effective_setting is host-synced, so clients
            -- reflect the HOST's toggle. No `%` in the appended line, so no %% escaping needed.
            if key == "description_ct_boon_manann_tempest"
                and effective_setting("tweak_manann_tempest_cooldown") then
                return m .. "\n8 second cooldown."
            end
            return m
        end
        -- #133: the VANILLA Manann's Tempest weapon trait (deus_crit_chain_lightning) also
        -- gains the 8s cooldown when tweak_manann_tempest_cooldown is on - the
        -- ProcFunctions.chain_lightning hook gates BOTH the mod boon AND this trait. The mod-boon
        -- branch above only covers description_ct_boon_manann_tempest; append the same note to the
        -- vanilla trait's advanced_description (weapon_traits_morris.lua:563) so its tooltip tracks
        -- behavior too. Appends to func()'s vanilla string so it stays EXACTLY vanilla with the
        -- tweak off; the vanilla %s target-count placeholder is substituted downstream by
        -- UIUtils.get_trait_description. No `%` in the appended line, so no %% escaping needed.
        if key == "description_deus_crit_chain_lightning"
            and effective_setting("tweak_manann_tempest_cooldown") then
            return func(key, ...) .. "\n8 second cooldown."
        end
        if key == "description_deus_reckless_swings" and reckless_swings_originals then
            return RECKLESS_SWINGS_DESC_OVERRIDE
        end
        if key == "blessing_of_power_desc"
            and effective_setting("tweak_miracle_of_ulric_persistent") then
            return MIRACLE_LOC_OVERRIDES[key]
        end
        if key == "blessing_of_isha_desc" then
            -- v0.7.120 (Issue #54 fix): read the v0.7.81+ mutex setting keys via
            -- effective_setting (host-broadcast on clients) so client's boon
            -- description text reflects the HOST's selected mode, not the client's
            -- stale local toggle. Inline because _get_isha_mode is defined later in
            -- the file and this Localize closure is built before its declaration.
            -- Legacy migration: if the user hasn't been through _migrate_isha_legacy
            -- yet (called via _get_isha_mode), also check the v0.7.65 dropdown key.
            if effective_setting("tweak_miracle_of_isha_aegis") then
                return MIRACLE_LOC_OVERRIDES.blessing_of_isha_desc_aegis
            end
            if effective_setting("tweak_miracle_of_isha_wounds") then
                return MIRACLE_LOC_OVERRIDES.blessing_of_isha_desc_wounds
            end
            -- Legacy dropdown fallback (pre-v0.7.81 saves not yet migrated)
            local legacy = effective_setting("tweak_miracle_of_isha_alternative")
            if legacy == true or legacy == "aegis" then return MIRACLE_LOC_OVERRIDES.blessing_of_isha_desc_aegis end
            if legacy == "wounds" then return MIRACLE_LOC_OVERRIDES.blessing_of_isha_desc_wounds end
        end
    end
    return func(key, ...)
end)

-- ============================================================
-- Level load / mission start -> _ct_level_load_owner.lua (#1159)
-- ============================================================
-- Owns everything ct does between "a Chaos Wastes mission's level begins loading"
-- and "the local player's mission has started": the two vanilla crash guards that
-- only fire in that window (EnemyPackageLoader.setup_startup_enemies forcing
-- random-director resolution for injected adventure + _belakor_path levels, and
-- the MutatorHandler.tweak_pack_spawning_settings strip that keeps no_roamers away
-- from a pack_spawning_settings with no difficulty_overrides), the per-curse
-- Light.set_color palette applied once at GameModeDeus.local_player_game_starts,
-- and the census that reports what the load actually produced -- the two pickup
-- dumps, the [ct:456] book-spawner census and the [ct:136] per-peer mission:start
-- line. The installer sits at the exact line the moved region occupied, so hook
-- registration order across the whole mod is unchanged.
--
-- Three ctx keys, all READ crossings bound BY VALUE: `_dbg` and the two
-- injected-level predicates are `local function` declarations ABOVE this install
-- site that are never reassigned, so a late-binding wrapper would buy nothing and
-- would hand this owner a different function identity for the same gate than the
-- one _ct_curse_lighting_owner and _ct_spawn_eligibility_owner receive.
--
-- The owner returns the two pickup-dump bodies so the entry can fill its OWN
-- forward-declared slots (see the declaration comment near the top of this file):
-- _ct_pickup_population_owner reads them through late-binding wrappers installed
-- ABOVE here, and _ct_regression takes them by value below. The strip list crosses
-- back as the SAME table object so `adventure_pack_compat_strip` inspects the live
-- list. `CT_NO_ROAMERS_DEUS_FIX_MARKER` / `CT_NO_ROAMERS_ARITY_FIX_MARKER` stay _G
-- globals, now set by the owner at this same point in load order.
local _ct_level_load_owner = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_level_load_owner")(mod, {
    dbg = _dbg,
    on_injected_adventure_level = on_injected_adventure_level,
    adventure_base_from_level_key = adventure_base_from_level_key,
})
_dump_pickup_system_state     = _ct_level_load_owner.dump_pickup_system_state
_dump_pickup_spawners_verbose = _ct_level_load_owner.dump_pickup_spawners_verbose
local ADVENTURE_INCOMPATIBLE_PACK_MUTATORS =
    _ct_level_load_owner.adventure_incompatible_pack_mutators

-- ============================================================
-- Vanilla bug fix: NetworkedFlowStateManager._num_states leak
-- ============================================================
-- Fatshark vanilla bug. `NetworkedFlowStateManager.clear_object_state`
-- (networked_flow_state_manager.lua:493) nils `_object_states[unit]` when a
-- unit is destroyed (entity_manager2.lua:390) BUT NEVER DECREMENTS
-- `_num_states`. The counter is monotonic and the run fatals at
-- `_num_states == _max_states (512)` with:
--   "[NetworkedFlowStateManager] Too many object states(512)."
-- Every destroyed unit that ever held a networked flow state permanently
-- leaks its slot.
--
-- Hits hardest in CW runs with our adventure-mission injection + curses:
-- the `cursed_chest_objective_unit` buff is applied to every cursed-chest
-- enemy spawn (deus_generic_terror_events.lua:26 →
-- morris_buff_settings.lua:614 apply_objective_unit) which spawns a
-- `units/hub_elements/objective_unit` carrying a `chest_open_state`
-- networked flow state. Each enemy = 1 permanently-leaked slot. Crash
-- reproduced ~40 min into a Verminious Dreams khorne node with 2 Chests
-- of Trials triggered (crash dump
-- console-2026-05-14-03.23.33-d86fd894-...).
--
-- Fix: count the states being released, subtract from `_num_states` BEFORE
-- delegating to vanilla. Defensive about table shape since this is a
-- private engine field that could change shape in future patches.
mod:hook("NetworkedFlowStateManager", "clear_object_state", function(func, self, unit)
    local unit_states = self._object_states and self._object_states[unit]
    if unit_states and type(unit_states.states) == "table" and type(self._num_states) == "number" then
        local count = 0
        for _ in pairs(unit_states.states) do count = count + 1 end
        if count > 0 then
            self._num_states = math.max(0, self._num_states - count)
        end
    end
    return func(self, unit)
end)

-- ============================================================
-- Hardening: NetworkedFlowStateManager 512-cap OVERFLOW guard (host)
-- ============================================================
-- The clear_object_state hook above fixes the vanilla _num_states LEAK
-- (destroyed units never decrementing the counter). But the crash can ALSO
-- recur WITHOUT a leak, and it did: v0.7.211-dev host crash on
-- dlc_termite_3_tzeentch_path1 (Devious Delvings / Tzeentch), Chest of
-- Trials active, enemy_tweaker caps raised. Crash dump
-- console-2026-07-03-18.41.50-d6dbb15d.
--
-- Mechanism: a Chest of Trials terror event applies the
-- `cursed_chest_objective_unit` buff to EVERY non-special trash spawn
-- (deus_generic_terror_events.lua:26 cursed_chest_enemy_spawned_func), and
-- each buff (morris_buff_settings.lua:614 apply_objective_unit) spawns a
-- `units/hub_elements/objective_unit` carrying a `chest_open_state`
-- networked flow state. entity_manager2.lua:390 clears the state on unit
-- DESTROY, but under raised enemy caps the fight holds 512+ live
-- objective_units AT ONCE (and mark_for_deletion lags actual destroy), so
-- the states are genuinely live -- the leak fix can't reclaim them. Vanilla
-- flow_cb_create_state fatals on the assert at
-- networked_flow_state_manager.lua:381:
--   "[NetworkedFlowStateManager] Too many object states(512)."
--
-- Guard (host-authoritative create path): intercept create. Near the cap,
-- first reclaim slots held by units that are already DEAD but whose destroy
-- has not yet fired clear_object_state (mark_for_deletion lag / any residual
-- leak vector). If STILL full after reclaim, SKIP the create -- return the
-- vanilla "declined to create" shape (nothing), which the flow callback
-- already tolerates (flow_callbacks.lua:1292 `if created then`). A trash-mob
-- objective marker without its networked chest_open_state is a cosmetic
-- degradation on that one unit; a host crash ends the whole team's run.
-- The full-table sweep only runs when _num_states is within 1 of the cap,
-- so normal play (which never approaches 511) pays zero cost.
CT_FLOWSTATE_CAP_GUARD_MARKER = "networked_flow_state_cap_guard:reclaim_dead_then_skip_v0.7.213"
mod:hook("NetworkedFlowStateManager", "flow_cb_create_state", function(func, self, unit, state_name, ...)
    local num = self._num_states
    local max = self._max_states
    if type(num) == "number" and type(max) == "number" and num >= max - 1 then
        -- Reclaim slots from units that are already dead (destroy lag / leak).
        local states = self._object_states
        if type(states) == "table" then
            local dead, reclaimed = nil, 0
            for u, unit_states in pairs(states) do
                if not (Unit and Unit.alive and Unit.alive(u)) then
                    local c = 0
                    if type(unit_states) == "table" and type(unit_states.states) == "table" then
                        for _ in pairs(unit_states.states) do c = c + 1 end
                    end
                    dead = dead or {}
                    dead[#dead + 1] = u
                    reclaimed = reclaimed + c
                end
            end
            if dead then
                for i = 1, #dead do states[dead[i]] = nil end
                if reclaimed > 0 and type(self._num_states) == "number" then
                    self._num_states = math.max(0, self._num_states - reclaimed)
                end
            end
        end
        -- Still full after reclaim? Decline the create instead of fatalling.
        if type(self._num_states) == "number" and self._num_states >= max then
            if not mod._ct_flowstate_cap_warned then
                mod._ct_flowstate_cap_warned = true
                pcall(printf,
                    "[ct:flowcap] NetworkedFlowStateManager at cap (%s/%s); declining create state=%s to avoid host crash (further skips silent this session)",
                    tostring(self._num_states), tostring(max), tostring(state_name))
            end
            return
        end
    end
    return func(self, unit, state_name, ...)
end)

local _ct_curse_lighting_owner = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_curse_lighting_owner")({
    mod = mod,
    on_injected_adventure_level = on_injected_adventure_level,
    adventure_base_from_level_key = adventure_base_from_level_key,
    get_managers = function() return Managers end,
    get_level_helper = function() return LevelHelper end,
    get_shading_environment = function() return ShadingEnvironment end,
    make_vector3 = function(...) return Vector3(...) end,
    printf = printf,
})
local _current_node_is_belakor =
    _ct_curse_lighting_owner.current_node_is_belakor
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
    if not graph_data then
        _dbg("[DeusMapScene.on_enter] no graph_data; passing through")
        return func(self, graph_data, ...)
    end
    -- v0.7.64 late-arrival apply: if the host's graph snapshot arrived AFTER the
    -- client's `deus_populate_graph` ran (RPC ordering race during setup_run),
    -- this is the natural re-apply site — the map UI is the only visible consumer
    -- the user complained about. Phase-A's in-place mutation makes downstream
    -- `_path_graph` reads see the synced values too, so we don't need a third
    -- application site for in-mission tooltip / curse-name reads.
    if ctx.host_graph_snapshot() then
        local applied = apply_graph_snapshot(graph_data)
        if applied > 0 then
            _dbg("[ct_graph] applied host snapshot to %d nodes (DeusMapScene.on_enter)", applied)
        end
    end
    local saved = {}
    local seen, rewritten, skipped = 0, 0, 0
    for key, node in pairs(graph_data) do
        if type(node) == "table" and type(node.level) == "string" then
            seen = seen + 1
            local base_key = adventure_base_from_level_key(node.level)
            if base_key then
                local mission = AdventurePool and AdventurePool.MISSION_BY_KEY and AdventurePool.MISSION_BY_KEY[base_key]
                local icon = mission and mission.icon or "mountain"  -- fallback
                local cw_base = "pat_" .. icon
                saved[key] = { level = node.level, base_level = node.base_level }
                local suffix = node.level:match("(_[a-z]+_path%d+)$") or "_wastes_path1"
                local new_level = cw_base .. suffix
                _dbg("[DeusMapScene.on_enter]   rewrite %s: %s -> %s (theme=%s curse=%s)",
                    tostring(key), node.level, new_level, tostring(node.theme), tostring(node.curse))
                node.level = new_level
                node.base_level = cw_base
                rewritten = rewritten + 1
            else
                if node.level:match("^pat_") or node.level:match("^sig_") or node.level:match("^arena_") or node.level:match("^shop_") then
                    -- vanilla CW level, no rewrite needed
                else
                    skipped = skipped + 1
                    _dbg("[DeusMapScene.on_enter]   SKIP %s level=%s (no adventure base match — UI will use SHRINE_NODE_UNIT and curse halo won't show)",
                        tostring(key), node.level)
                end
            end
            -- #68 DIAGNOSTIC ([ct:mapnode68]): log the 3D node model each graph node
            -- resolves to. Vanilla deus_map_scene.lua:182-192 selects the node unit purely
            -- from the prefix of node.level before the first '_':
            --   sig_ -> SIG, pat_ -> TRAVEL, arena_ -> ARENA, key=="start" -> START,
            --   everything else -> SHRINE (altar/shrine mesh, no curse halo).
            -- Native CW Belakor-path variant keys (bell_belakor_path1, magnus_belakor_path1,
            -- cemetery_belakor_path1, ...) have an unrecognized prefix and are NOT matched by
            -- adventure_base_from_level_key, so the rewrite above skips them -> SHRINE. printf
            -- so it is visible with mod-logging OFF (_dbg routes to mod:debug, unseen).
            -- node.level here is POST-rewrite (the exact value spawn_graph_units consumes).
            do
                local lvl = node.level
                local model
                if key == "start" then
                    model = "START"
                else
                    local us = lvl:find("_")
                    local prefix = us and lvl:sub(1, us - 1) or lvl
                    model = (prefix == "sig" and "SIG") or (prefix == "pat" and "TRAVEL")
                        or (prefix == "arena" and "ARENA") or "SHRINE"
                end
                pcall(printf, "[ct:mapnode68] key=%s node_type=%s level=%s base_level=%s theme=%s curse=%s -> model=%s%s",
                    tostring(key), tostring(node.node_type), tostring(lvl),
                    tostring(node.base_level), tostring(node.theme), tostring(node.curse),
                    model, base_key and " (ct-rewritten to TRAVEL)" or "")
            end
        end
    end
    _dbg("[DeusMapScene.on_enter] seen=%d rewritten=%d skipped_non_vanilla_non_adventure=%d",
        seen, rewritten, skipped)

    local result = { func(self, graph_data, ...) }

    for key, original in pairs(saved) do
        if graph_data[key] then
            graph_data[key].level = original.level
            graph_data[key].base_level = original.base_level
        end
    end
    -- v0.7.107-dev nil-hole audit: DeusMapScene.on_enter (deus_map_scene.lua:453)
    -- returns nothing — the body assigns to `self.*` fields and ends. No multi-return
    -- to preserve, no nil-hole risk. Left as-is per audit.
    return unpack(result) -- unpack-safe: no multi-return, body assigns self.* fields
end)

-- ============================================================
-- Journey-graph shaping -> _ct_campaign_graph_owner.lua (#1159)
-- ============================================================
-- Owns every ct change to the GENERATED Chaos Wastes journey graph: the exact
-- cursed-mission count and the disable_dominant_god rotation, the
-- disabled-curse pool filter (and its restore) wrapped around the generator
-- call, the replace_shrines_with_missions SHOP -> TRAVEL base-graph conversion,
-- the #145/#146 Citadel finale/approach god rewrite on the finished graph, and
-- the three read-only divergence probes those seams carry (#145 host-only
-- resolved-god census, #56 Citadel curse, #136 all-node).
--
-- dofile'd HERE, at the exact point the block used to execute - after the
-- DeusMapScene.on_enter map-scene hook above, before the per-career weapon
-- override recovery below - so the single `deus_populate_graph` hook registers
-- in its original load order and the two CT_CITADEL145_* marker globals land at
-- the same point in the script body.
--
-- The graph-snapshot RPC transport STAYS in this file (chunked send/receive,
-- _ct_host_graph_snapshot, apply_host_graph_snapshot_to_live_run, and the
-- DeusMapScene.on_enter late-arrival apply above). The owner only CALLS the
-- host broadcast and the client apply, so both are handed over as ctx values.
-- Every ctx entry below is assigned exactly once, strictly above this line, and
-- never replaced afterwards, so the module binds the identical object the
-- inline code called - no late-binding accessor is needed here.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_campaign_graph_owner")(mod, {
    dbg                      = _dbg,
    effective_setting        = effective_setting,
    is_curse_disabled        = is_curse_disabled,
    finale_gods              = FINALE_GODS,
    apply_graph_snapshot     = apply_graph_snapshot,
    broadcast_graph_snapshot = broadcast_graph_snapshot,
})


    return {
        adventure_incompatible_pack_mutators = ADVENTURE_INCOMPATIBLE_PACK_MUTATORS,
        dump_pickup_spawners_verbose = _dump_pickup_spawners_verbose,
        dump_pickup_system_state = _dump_pickup_system_state,
        on_injected_adventure_level = on_injected_adventure_level,
    }
end
