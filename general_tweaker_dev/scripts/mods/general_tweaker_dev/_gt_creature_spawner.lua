local mod = get_mod("gt_dev")

-- _gt_creature_spawner.lua — Creature Spawner
--
-- Ported from Aussiemon's CreatureSpawner (Workshop 1395132559, MIT). Spawn any
-- breed at the crosshair, with a large suite of keep-navigation / boss-init /
-- package-loader crash guards so spawning works in the Keep too. Spawning is
-- host-authoritative (only the host drains the ConflictDirector spawn queue -
-- state_ingame.lua:950-958 runs conflict:update on the server and
-- update_client on clients), so a CLIENT sends a schema-tagged VMF request
-- (`gt_cs_request`) that the host executes; the host acks the result back over
-- `gt_cs_ack` (#693). Schema constant `mod.GT_CS_RPC_SCHEMA` lives in main.
-- Extracted verbatim from the main file (Phase 4); pure reorganization, no
-- behavior change. All identifiers are namespaced `_gt_cs_*` / `gt_cs_*`.
--
-- Coupling with the main file (resolved at call time — this module dofiles
-- AFTER the main chunk):
--   * mod._gt_cs_on_setting_changed / mod._gt_cs_on_game_state_changed —
--     assigned here, CALLED by the main-file on_setting_changed /
--     on_game_state_changed DISPATCHERS (which stay in main per the dispatcher
--     rule). Previously file-local forward-decls in main.
--   * mod._gt_cs_is_in_level — exposed for the gt_cs_is_in_level_prefix_match
--     regression check, which stays in main's /gt_regression_test block.
--
-- Hooks (every one a singleton — whole-mod (Class,method) grep verified disjoint
-- from the rest of gt during the Phase-4 extraction):
--   ConflictDirector.update (keep-spawn strip-down; DISTINCT from the
--     consolidated ConflictDirector.spawn_queued_unit hook that STAYS in main),
--   StateIngame.update, AISystem.update_brains, AIGroupSystem.update,
--   AiBreedSnippets.reward_boss_kill_loot, AiUtils.update_aggro,
--   ProjectileEtherealSkullLocomotionExtension.init, BTEnterHooks.*,
--   BTSpawnAllies.{enter,run,leave,find_spawn_point},
--   Breeds.chaos_exalted_sorcerer_drachenfels.{run_on_spawn,run_on_death},
--   BTConditions.transitioned_one_third_health, BTLootRatFleeAction.*,
--   NavigationGroupManager.a_star_cached_between_positions,
--   LocomotionUtils.pos_on_mesh,
--   GwNavQueries.inside_position_from_outside_position, Unit.create_actor
--     (DISTINCT from Unit.get_data in _gt_hacks.lua — keyed per-method),
--   BTSkulkAroundAction.get_new_skulk_goal,
--   BuffSystem.add_buff, World.spawn_unit, EnemyPackageLoader.request_breed.
-- All hooks are table-form (mod:hook(ClassSymbol, ...)) — the classes are
-- globals resolved at module load (after main), so they bind correctly.

-- ============================================================
-- Creature Spawner (ported from Aussiemon's CreatureSpawner mod,
-- Workshop ID 1395132559, MIT-licensed)
-- ============================================================
-- All gt_cs_* settings, helpers, hooks, and commands live below this header
-- and are namespaced to avoid colliding with the rest of gt. Names match the
-- original mod's structure 1:1 (build_unit_lists / next_spawn_breed /
-- spawn_debug_breed_at_cursor / get_status / position_at_cursor / etc.) so
-- diffing against the upstream source stays easy. Forward-declared at the
-- top of the file: `_gt_cs_on_setting_changed` and
-- `_gt_cs_on_game_state_changed` (the global on_setting_changed /
-- on_game_state_changed callbacks dispatch into them).

-- Unit categories OVERLAY, copied verbatim from CreatureSpawner_data.lua.
-- Issue #454 (v0.2.210-dev): this map is no longer the gate on WHICH breeds
-- are listed - the lists are enumerated from the live `Breeds` table at
-- command time (see _gt_cs_build_unit_lists). Breeds named here keep their
-- upstream-authored category memberships; every other spawnable breed is
-- categorized dynamically from its own fields (boss / special / race).
-- Do not edit curated entries here without mirroring the change back to
-- source if it's a bug-fix worth contributing.
local _gt_cs_unit_category_names = {
    "regular",
    "dummy",
    "misc",
    "special",
    "boss",
    "all",
}

local _gt_cs_unit_categories = {
    beastmen_bestigor = { "regular", "special" },
    beastmen_bestigor_dummy = { "dummy", "misc" },
    beastmen_gor = { "regular" },
    beastmen_gor_dummy = { "dummy", "misc" },
    beastmen_minotaur = { "regular", "boss" },
    beastmen_standard_bearer = { "regular", "special" },
    beastmen_standard_bearer_crater = { "misc" },
    beastmen_ungor = { "regular" },
    beastmen_ungor_dummy = { "dummy", "misc" },
    beastmen_ungor_archer = { "regular" },
    chaos_berzerker = { "regular", "special" },
    chaos_bulwark = { "regular", "special" },
    chaos_corruptor_sorcerer = { "regular", "special" },
    chaos_dummy_exalted_sorcerer_drachenfels = { "dummy", "misc" },
    chaos_dummy_sorcerer = { "dummy", "misc" },
    chaos_dummy_troll = { "dummy", "misc" },
    chaos_exalted_champion_norsca = { "boss" },
    chaos_exalted_champion_warcamp = { "boss" },
    chaos_exalted_sorcerer = { "boss" },
    chaos_exalted_sorcerer_drachenfels = { "boss" },
    chaos_fanatic = { "regular" },
    chaos_greed_pinata = { "misc" },
    chaos_marauder = { "regular" },
    chaos_marauder_tutorial = { "misc" },
    chaos_marauder_with_shield = { "regular" },
    chaos_mutator_sorcerer = { "misc" },
    chaos_plague_sorcerer = { "misc" },
    chaos_plague_wave_spawner = { "misc" },
    chaos_raider = { "regular", "special" },
    chaos_raider_tutorial = { "misc" },
    chaos_skeleton = { "regular", "misc" },
    chaos_spawn = { "regular", "boss" },
    chaos_spawn_exalted_champion_norsca = { "boss" },
    chaos_tentacle = { "misc" },
    chaos_tentacle_sorcerer = { "misc" },
    chaos_troll = { "regular", "boss" },
    chaos_vortex = { "misc" },
    chaos_vortex_sorcerer = { "regular", "special" },
    chaos_warrior = { "regular", "special" },
    chaos_zombie = { "misc" },
    critter_nurgling = { "misc" },
    critter_pig = { "regular" },
    critter_rat = { "regular" },
    curse_mutator_sorcerer = { "misc" },
    ethereal_skeleton_with_hammer = { "misc" },
    ethereal_skeleton_with_shield = { "misc" },
    pet_pig = { "misc" },
    pet_rat = { "misc" },
    pet_skeleton = { "misc" },
    pet_skeleton_armored = { "misc" },
    pet_skeleton_dual_wield = { "misc" },
    pet_skeleton_with_shield = { "misc" },
    shadow_lieutenant = { "misc" },
    shadow_skull = { "misc" },
    shadow_totem = { "misc" },
    skaven_clan_rat = { "regular" },
    skaven_clan_rat_tutorial = { "misc" },
    skaven_clan_rat_with_shield = { "regular" },
    skaven_dummy_clan_rat = { "dummy", "misc" },
    skaven_dummy_slave = { "dummy", "misc" },
    skaven_explosive_loot_rat = { "misc" },
    skaven_grey_seer = { "boss" },
    skaven_gutter_runner = { "regular", "special" },
    skaven_loot_rat = { "regular", "special" },
    skaven_pack_master = { "regular", "special" },
    skaven_plague_monk = { "regular", "special" },
    skaven_poison_wind_globadier = { "regular", "special" },
    skaven_rat_ogre = { "regular", "boss" },
    skaven_ratling_gunner = { "regular", "special" },
    skaven_slave = { "regular" },
    skaven_storm_vermin = { "regular", "special" },
    skaven_storm_vermin_champion = { "misc", "boss" },
    skaven_storm_vermin_commander = { "regular", "special" },
    skaven_storm_vermin_warlord = { "boss" },
    skaven_storm_vermin_with_shield = { "regular", "special" },
    skaven_stormfiend = { "regular", "boss" },
    skaven_stormfiend_boss = { "boss" },
    skaven_stormfiend_demo = { "misc", "boss" },
    skaven_warpfire_thrower = { "regular", "special" },
    tower_homing_skull = { "misc" },
    training_dummy = { "misc" },
}

-- Drachenfels exalted sorcerer is blacklisted from AI activation because its
-- run_on_spawn assumes the dlc_castle boss arena exists (level_analysis nodes,
-- spawner_system ids, etc.). Upstream mirrors this list.
local _gt_cs_ai_blacklist = {
    chaos_exalted_sorcerer_drachenfels = true,
}

local _gt_cs_hub_levels = {
    inn_level = true,
    inn_level_skulls = true,
    inn_level_celebrate = true,
    inn_level_halloween = true,
    inn_level_sonnstill = true,
}

-- The same lookup tables the upstream mod populates from `unit_categories`
-- at boot. Keys are the dropdown option values (regular_units / dummy_units /
-- etc.); values are the breed-name arrays we cycle through.
local _gt_cs_unit_lists = {
    regular_units = {},
    dummy_units   = {},
    misc_units    = {},
    special_units = {},
    boss_units    = {},
    all_units     = {},
}

-- Indexed list of every grudge-mark sub-toggle. Matches upstream so the
-- TerrorEventUtils.generate_enhanced_breed_from_set call sees the same keys
-- vanilla recognises.
local _gt_cs_grudge_keys = {
    "warping",
    "intangible",
    "unstaggerable",
    "raging",
    "vampiric",
    "ranged_immune",
    "periodic_shield",
    "crippling",
    "crushing",
    "regenerating",
    "periodic_curse",
    "commander",
    "frenzy",
}

-- Set-form lookup for validating grudge keys arriving over the client
-- request channel (#693) — never feed unvetted wire strings into
-- TerrorEventUtils.
local _gt_cs_grudge_key_set = {}
for _, key in ipairs(_gt_cs_grudge_keys) do
    _gt_cs_grudge_key_set[key] = true
end

-- Runtime selection state. `_gt_cs_breed_name_index` mirrors upstream's
-- `mod.breed_name_index`; tracks the active position in the currently-selected
-- unit list. `_gt_cs_buff_cap_limit_exceeded` mirrors upstream's same-named
-- flag — flipped by the BuffSystem.add_buff hook below so grudge-mark random
-- modifier additions back off when the server-controlled buff id table is
-- near capacity.
local _gt_cs_breed_name_index = 1
local _gt_cs_buff_cap_limit_exceeded = false

-- Track every unit we've actually spawned this session. ConflictDirector's
-- `destroy_all_units` is the host-wide despawn used by upstream too; we
-- forward to it on the "destroy" hotkey rather than maintain a private list,
-- so behaviour matches upstream's `handle_despawn_units` 1:1.

-- Issue #454: a breed is listed iff the debug-spawn path can actually spawn
-- it. ConflictDirector._spawn_unit reads breed.base_unit / breed.opt_base_unit
-- and breed.unit_template unconditionally (conflict_director.lua:1906-1908 -
-- a nil base_unit is an immediate index crash), and the AI extension resolves
-- the behavior tree from breed.behavior / breed.horde_behavior
-- (ai_simple_extension.lua:106). Player-hero and Versus dark-pact breeds
-- never appear here at all - they live in the separate PlayerBreeds table
-- (breed_players.lua:5, breed_players_vs.lua:305-311), while everything in
-- Breeds is stamped `is_ai = true` (breeds.lua:305-307).
local function _gt_cs_is_spawnable(breed)
    return type(breed) == "table"
        and (breed.base_unit or breed.opt_base_unit) ~= nil
        and breed.unit_template ~= nil
        and (breed.behavior or breed.horde_behavior) ~= nil
end

-- Category fallback for breeds NOT in the curated overlay: derive from the
-- breed's own fields. `boss` / `special` are the vanilla per-breed flags
-- (e.g. breed_chaos_troll_chief.lua `boss = true`,
-- breed_chaos_tether_sorcerer.lua `special = true` - both missing from the
-- old hardcoded map); `race = "dummy"` marks the training dummy
-- (breed_training_dummy.lua:43). Everything else lists as a regular enemy.
local function _gt_cs_dynamic_categories(breed)
    if breed.boss then return { "boss" } end
    if breed.special then return { "special" } end
    if breed.race == "dummy" then return { "dummy", "misc" } end
    return { "regular" }
end

local function _gt_cs_build_unit_lists()
    -- Populate the per-category arrays from the LIVE Breeds table (#454).
    -- Every spawnable breed is listed: curated breeds keep their upstream
    -- category memberships, unknown breeds (DLC additions, enemy_tweaker's
    -- et_* clones, any other mod's Breeds[...] registrations) are slotted by
    -- _gt_cs_dynamic_categories. Rebuilt lazily at command/menu time, NOT at
    -- file scope: mods register breeds at their own module load and mod load
    -- order is user-defined, so a boot-time snapshot goes stale - the same
    -- class as the ConflictDirector threat_values upvalue documented in
    -- enemy_tweaker/ENGINE_SURFACE.md "every table that snapshots
    -- pairs(Breeds) at boot". The walk is ~100 entries at keypress frequency.
    for _, list_name in ipairs(_gt_cs_unit_category_names) do
        _gt_cs_unit_lists[list_name .. "_units"] = {}
    end
    if not Breeds then return _gt_cs_unit_lists end
    for breed_name, breed in pairs(Breeds) do
        if _gt_cs_is_spawnable(breed) then
            local categories = _gt_cs_unit_categories[breed_name]
                or _gt_cs_dynamic_categories(breed)
            for _, cat in ipairs(categories) do
                local list = _gt_cs_unit_lists[cat .. "_units"]
                if list then list[#list + 1] = breed_name end
            end
            local all = _gt_cs_unit_lists["all_units"]
            all[#all + 1] = breed_name
        end
    end
    for _, list_name in ipairs(_gt_cs_unit_category_names) do
        local list = _gt_cs_unit_lists[list_name .. "_units"]
        if list then
            table.sort(list, function(a, b) return a < b end)
        end
    end
    return _gt_cs_unit_lists
end
-- Exposed for the gt_cs_breed_list_dynamic regression check in main (which
-- injects a probe breed into Breeds, rebuilds, and asserts it is listed).
mod._gt_cs_rebuild_unit_lists = _gt_cs_build_unit_lists

-- Issue #454 regression marker - if a future refactor reverts the live-table
-- enumeration, the main-file rt check gt_cs_breed_list_dynamic fails.
GT_CS_DYNAMIC_BREED_LIST_MARKER_v0_2_210 = "gt-cs-dynamic-breed-list-i454"

local function _gt_cs_active_list()
    -- Lazy rebuild on every access (#454) - callers are all user-driven
    -- (next/prev cycle, dropdown change, game-state change), never per-frame.
    _gt_cs_build_unit_lists()
    local key = mod:get("gt_cs_unit_list") or "regular_units"
    local list = _gt_cs_unit_lists[key] or _gt_cs_unit_lists.regular_units
    -- Re-locate the current selection in the fresh list so cycling continues
    -- from the same breed even when a late-registered breed shifted indices.
    local selected = mod:get("gt_cs_selected_unit")
    if selected and selected ~= "" then
        for i = 1, #list do
            if list[i] == selected then
                _gt_cs_breed_name_index = i
                break
            end
        end
    end
    if _gt_cs_breed_name_index > #list then _gt_cs_breed_name_index = #list end
    if _gt_cs_breed_name_index < 1 then _gt_cs_breed_name_index = 1 end
    return list
end

local function _gt_cs_is_in_keep()
    if Managers and Managers.state and Managers.state.game_mode then
        local level_key = Managers.state.game_mode:level_key()
        return level_key and _gt_cs_hub_levels[level_key]
    end
    return false
end

-- Matches exact name OR `<level_name>_<suffix>` so CW path-variant levels
-- (e.g. `dlc_castle_slaanesh_path1` / `dlc_castle_chaos_path2`) count as
-- "in dlc_castle" for the Drachenfels BT hooks below. The physical arena
-- is the same in every CW variant — same level_analysis nodes, same boss
-- spawn pattern — so the arena-aware hooks (run_on_spawn, level_analysis
-- skips, transitioned_one_third_health) must apply identically.
--
-- Issue #59 (2026-05-26): exact-match `level_key == level_name` returned
-- false in CW dlc_castle_<theme>_path1, so the transitioned_one_third_health
-- hook short-circuited to TRUE there. That forced the boss BT into its
-- "final offense phase" branch before the phase-init had populated
-- `blackboard.current_health_percent`, and the child condition
-- `at_one_fifth_health` (bt_conditions.lua:309) crashed reading nil. Host
-- dropped mid-CW-mission. Prefix-match fixes both the false-negative gate
-- AND the false-positive at_one_fifth_health crash that resulted from it.
local function _gt_cs_is_in_level(level_name)
    if not (Managers and Managers.state and Managers.state.game_mode) then
        return false
    end
    local level_key = Managers.state.game_mode:level_key()
    if not level_key then return false end
    if level_key == level_name then return true end
    -- Prefix-with-underscore boundary so "dlc_castle" matches
    -- "dlc_castle_slaanesh_path1" but NOT a hypothetical "dlc_castled_*"
    -- with a different word stem.
    local prefix = level_name .. "_"
    return string.sub(level_key, 1, #prefix) == prefix
end
-- Exposed so the gt_cs_is_in_level_prefix_match regression check (which stays
-- in the main file) can resolve this helper at call time after this module
-- dofiles. Internal CS hooks keep using the file-local for speed.
mod._gt_cs_is_in_level = _gt_cs_is_in_level

-- Returns (is_host_ready, conflict_director, is_client_ready) — extends
-- upstream's `mod:get_status` shape for issue 693. The spawn primitives only
-- run on the host (the client's ConflictDirector never drains its spawn
-- queue), so the first return keeps the pre-693 host-gate semantics and every
-- old `if not is_ready then return end` caller behaves identically. The NEW
-- third return is true when the game is ready but this peer is a client, so
-- callers can route to the client->host request channel below instead of
-- silently swallowing the press (the pre-693 bug: a client got NO feedback
-- and NO spawn). conflict_director is now returned for clients too — breed
-- cycling only touches the local `_debug_breed` field, which is safe and
-- meaningful on any peer.
local function _gt_cs_get_status(suppress_messages)
    local player_manager = Managers.player
    if not player_manager then
        if not suppress_messages then
            mod:echo("[Spawn]: Please wait. The game is not yet ready.")
        end
        return false
    end
    local conflict_director = Managers.state and Managers.state.conflict
    if not conflict_director then
        if not suppress_messages then
            mod:echo("[Spawn]: Please wait. The game is not yet ready.")
        end
        return false
    end
    if player_manager.is_server then
        return true, conflict_director
    end
    return false, conflict_director, true
end

-- Recursive table copy (deepcopy). Same implementation upstream uses
-- before patching `debug_spawn_optional_data` so we don't mutate the
-- shared `Breeds[breed_name]` table.
local function _gt_cs_deepcopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for k, v in next, orig, nil do
                copy[_gt_cs_deepcopy(k, copies)] = _gt_cs_deepcopy(v, copies)
            end
            setmetatable(copy, _gt_cs_deepcopy(getmetatable(orig), copies))
        end
    else
        copy = orig
    end
    return copy
end

-- Raycast from the camera through the crosshair and return the first
-- non-self hit position. Mirrors upstream's `position_at_cursor` —
-- filter_ray_horde_spawn is the same collision filter the vanilla horde
-- spawner uses, so the result is always a valid spawn ground point.
local function _gt_cs_position_at_cursor(local_player)
    local viewport_name = local_player.viewport_name
    local camera_position = Managers.state.camera:camera_position(viewport_name)
    local camera_rotation = Managers.state.camera:camera_rotation(viewport_name)
    local camera_direction = Quaternion.forward(camera_rotation)
    local range = 500
    local world = Managers.world:world("level_world")
    local physics_world = World.get_data(world, "physics_world")
    local new_position
    local result = PhysicsWorld.immediate_raycast(
        physics_world,
        camera_position,
        camera_direction,
        range,
        "all",
        "collision_filter",
        "filter_ray_horde_spawn")
    if result then
        for i = 1, #result, 1 do
            local hit = result[i]
            local hit_actor = hit[4]
            local hit_unit = Actor.unit(hit_actor)
            local ray_hit_self = local_player.player_unit and (hit_unit == local_player.player_unit)
            if not ray_hit_self then
                new_position = hit[1]
                break
            end
        end
    end
    return new_position or camera_position
end

-- Cycle helpers — both wrap around the active list and skip breeds that
-- are no longer in `Breeds` (rare, mostly happens when a DLC isn't owned
-- or the breed was renamed). Matches upstream's next_spawn_breed /
-- previous_spawn_breed exactly.
local function _gt_cs_next_spawn_breed()
    local conflict_director = Managers.state.conflict
    if not conflict_director then return end
    conflict_director._show_switch_breed = 1
    local list = _gt_cs_active_list()
    if #list == 0 then return end
    local entry_index = _gt_cs_breed_name_index
    repeat
        _gt_cs_breed_name_index = _gt_cs_breed_name_index + 1
        if _gt_cs_breed_name_index > #list then
            _gt_cs_breed_name_index = 1
        end
        conflict_director._debug_breed = list[_gt_cs_breed_name_index] or "skaven_dummy_slave"
        if Breeds[conflict_director._debug_breed] then break end
    until _gt_cs_breed_name_index == entry_index
    if _gt_cs_breed_name_index == entry_index then
        mod:echo("[Spawn]: No units from the selected list are available right now.")
    else
        mod:set("gt_cs_selected_unit", conflict_director._debug_breed, false)
    end
end

local function _gt_cs_previous_spawn_breed()
    local conflict_director = Managers.state.conflict
    if not conflict_director then return end
    conflict_director._show_switch_breed = 1
    local list = _gt_cs_active_list()
    if #list == 0 then return end
    local entry_index = _gt_cs_breed_name_index
    repeat
        _gt_cs_breed_name_index = _gt_cs_breed_name_index - 1
        if _gt_cs_breed_name_index < 1 then
            _gt_cs_breed_name_index = #list
        end
        conflict_director._debug_breed = list[_gt_cs_breed_name_index] or "skaven_dummy_slave"
        if Breeds[conflict_director._debug_breed] then break end
    until _gt_cs_breed_name_index == entry_index
    if _gt_cs_breed_name_index == entry_index then
        mod:echo("[Spawn]: No units from the selected list are available right now.")
    else
        mod:set("gt_cs_selected_unit", conflict_director._debug_breed, false)
    end
end

-- Build the grudge-mark spec from THIS peer's own settings. Shared by the
-- host's local spawn path and the client request path (#693), so the player
-- who pressed the key is the one whose grudge configuration applies.
-- Returns nil | { mode = "RANDOM", count = n } | { mode = "MANUAL", keys = {...} }.
local function _gt_cs_resolve_grudge_spec()
    local grudge_mark_setting = mod:get("gt_cs_grudge")
    if grudge_mark_setting == "RANDOM" then
        return { mode = "RANDOM", count = mod:get("gt_cs_grudge_random_modifier_count") or 1 }
    elseif grudge_mark_setting == "MANUAL" then
        local keys = {}
        for _, key in ipairs(_gt_cs_grudge_keys) do
            if mod:get("gt_cs_grudge_" .. key) then
                keys[#keys + 1] = key
            end
        end
        return { mode = "MANUAL", keys = keys }
    end
    return nil
end

-- HOST-ONLY spawn executor, split out of the old spawn_debug_breed_at_cursor
-- body (#693) so it serves BOTH the host's own hotkey/command path and a
-- client's request RPC. Behavior is 1:1 with the pre-split body; the only
-- change is that the player-facing lines are RETURNED (in emit order) instead
-- of echoed, so the RPC path can relay them to the requesting client.
-- Returns (ok, messages_array).
local function _gt_cs_execute_spawn(conflict_director, breed_name, final_position, final_rotation, grudge_spec)
    local messages = {}
    local ai_warning_set = false
    breed_name = breed_name or ""
    if _gt_cs_ai_blacklist[breed_name] then
        if _gt_cs_is_in_keep() then
            mod:set("gt_cs_keep_ai", false)
        else
            mod:set("gt_cs_mission_ai", false)
        end
        ai_warning_set = true
    end

    local breed = Breeds and _gt_cs_deepcopy(rawget(Breeds, breed_name))
    local ok = false
    if breed then
        breed.debug_spawn_optional_data = breed.debug_spawn_optional_data or {}
        breed.debug_spawn_optional_data.ignore_breed_limits = true
        breed.debug_spawn_optional_data.enhancements = nil

        if grudge_spec then
            if not _gt_cs_buff_cap_limit_exceeded then
                if grudge_spec.mode == "RANDOM" then
                    local num_enhancements = grudge_spec.count or 1
                    if TerrorEventUtils and TerrorEventUtils.add_enhancements_to_spawn_data then
                        breed.debug_spawn_optional_data = TerrorEventUtils.add_enhancements_to_spawn_data(
                            breed.debug_spawn_optional_data, num_enhancements, breed_name)
                    end
                elseif grudge_spec.mode == "MANUAL" then
                    local enhancement_list = {}
                    for _, key in ipairs(grudge_spec.keys or {}) do
                        if _gt_cs_grudge_key_set[key] then
                            enhancement_list[key] = true
                        end
                    end
                    if TerrorEventUtils and TerrorEventUtils.generate_enhanced_breed_from_set then
                        breed.debug_spawn_optional_data.enhancements =
                            TerrorEventUtils.generate_enhanced_breed_from_set(enhancement_list)
                    end
                end

                local grudgeString = ""
                local applied = breed.debug_spawn_optional_data.enhancements or {}
                for _, value in pairs(applied) do
                    local label = type(value) == "table" and tostring(value[1]) or tostring(value)
                    if grudgeString == "" then
                        grudgeString = label
                    else
                        grudgeString = grudgeString .. ", " .. label
                    end
                end
                if grudgeString ~= "" then
                    messages[#messages + 1] = "Applying " .. grudgeString .. " modifiers..."
                end
            else
                messages[#messages + 1] = "Too many active grudge-mark modifiers!"
            end
        end

        conflict_director:spawn_queued_unit(breed, Vector3Box(final_position), QuaternionBox(final_rotation),
            breed.debug_spawn_category or "debug_spawn", nil, nil, breed.debug_spawn_optional_data)
        messages[#messages + 1] = "[Spawn]: Created " .. tostring(breed_name) .. "."
        ok = true
    else
        messages[#messages + 1] = "[Spawn]: " .. tostring(breed_name) .. " is not available."
    end

    if ai_warning_set then
        messages[#messages + 1] = "[WARNING]: Enabling " .. breed_name .. " AI will likely cause crashes!"
    end
    return ok, messages
end

-- Spawn the currently-selected breed at the crosshair raycast. 1:1 with
-- upstream's `spawn_debug_breed_at_cursor` (position/rotation math unchanged);
-- the spawn body itself lives in _gt_cs_execute_spawn above (#693).
local function _gt_cs_spawn_at_cursor()
    local conflict_director = Managers.state.conflict
    if not conflict_director then return end
    local local_player = Managers.player:local_player()
    if not local_player then return end

    local final_rotation
    local final_position = _gt_cs_position_at_cursor(local_player)
    local local_player_unit = local_player.player_unit
    if Unit.alive(local_player_unit) then
        final_rotation = Quaternion.multiply(Unit.local_rotation(local_player_unit, 0), Quaternion(Vector3(0, 0, 1), math.pi))
    else
        final_rotation = Quaternion(0, 0, 0, 0)
    end

    local breed_name = conflict_director._debug_breed or ""
    local _, messages = _gt_cs_execute_spawn(conflict_director, breed_name,
        final_position, final_rotation, _gt_cs_resolve_grudge_spec())
    for i = 1, #messages do
        mod:echo(messages[i])
    end
end

-- ============================================================
-- Client -> host request channel (#693)
-- ============================================================
-- Enemy spawning is host-authoritative: only the server drains the
-- ConflictDirector spawn queue (state_ingame.lua:950-958 runs
-- `conflict:update` on the host and `update_client` on clients;
-- `spawn_queued_unit` only enqueues, conflict_director.lua:1732-1791), so a
-- client-side spawn call queues into a queue that never drains. A client
-- therefore REQUESTS the action and the host performs it - the same shape as
-- the shipped `gt_level_control` / `gt_respawn_request` channels in
-- _gt_level_control.lua.
--
-- WIRE SAFETY (issue 278/371 class - why this can NEVER crash a vanilla
-- peer): `mod:network_send` rides the VANILLA `rpc_mod_user_data` RPC
-- (ModManager.network_send, mod_manager.lua:595-605). The receiving side
-- (mod_manager.lua:607-621) dispatches only into a callback the peer itself
-- registered for the port; a peer without VMF/gt registered nothing, so the
-- payload is dropped inside vanilla code. No modded NetworkLookup key, no
-- custom vanilla RPC. When the HOST lacks the mod the request degrades
-- silently on the wire (VMF only delivers to handshaken VMF peers) and the
-- client-side message below tells the player the host must run the mod.
local _GT_CS_RPC = "gt_cs_request"   -- client -> host: (schema, verb, breed, px, py, pz, dx, dy, dz, grudge)
local _GT_CS_ACK_RPC = "gt_cs_ack"   -- host -> requesting client: (schema, message)

-- Resolve the host's real peer id (VMF_RECIPES section 3: the literal
-- "server" recipient is silently dropped, and Managers.state.network has no
-- direct server_peer_id field - it lives on .network_client/.network_server).
local function _gt_cs_host_peer_id()
    if Managers.mechanism and Managers.mechanism.server_peer_id then
        local host = Managers.mechanism:server_peer_id()
        if host then return host end
    end
    local nm = Managers.state and Managers.state.network
    return nm and ((nm.network_client and nm.network_client.server_peer_id)
        or (nm.network_server and nm.network_server.server_peer_id)) or nil
end

-- Fixed-arity send so no positional arg is ever nil on the wire. Pings VMF
-- first (VMF_RECIPES section 3a: host bot churn can drop the host from
-- `_vmf_users`; the "run it again" hint in the caller message covers the
-- async pong window, same as _gt_level_control).
local function _gt_cs_client_send(verb, breed_name, px, py, pz, dx, dy, dz, grudge_str)
    local vmf = get_mod("VMF")
    if vmf and vmf.ping_vmf_users then pcall(vmf.ping_vmf_users) end
    local host = _gt_cs_host_peer_id()
    if not host then
        mod:echo("[Spawn]: Couldn't resolve the host peer.")
        return false
    end
    pcall(function()
        mod:network_send(_GT_CS_RPC, host, mod.GT_CS_RPC_SCHEMA, verb,
            breed_name, px, py, pz, dx, dy, dz, grudge_str)
    end)
    return true
end

-- CLIENT: request a spawn of `breed_name` (nil = currently-selected breed) at
-- this client's own crosshair, facing this client. Position and facing are
-- computed locally (the raycast + camera are per-peer) and shipped as plain
-- numbers; the host rebuilds the rotation via Quaternion.look, the vanilla
-- direction->rotation path (conflict_director.lua:3394).
local function _gt_cs_client_request_spawn(breed_name)
    local local_player = Managers.player and Managers.player:local_player()
    if not local_player then return end
    local conflict_director = Managers.state and Managers.state.conflict
    breed_name = breed_name
        or (conflict_director and conflict_director._debug_breed)
        or mod:get("gt_cs_selected_unit") or ""
    if breed_name == "" then
        mod:echo("[Spawn]: No creature selected. Cycle with the next/previous keys first.")
        return
    end
    local position = _gt_cs_position_at_cursor(local_player)
    -- The host-local path faces the spawn toward the spawner by flipping the
    -- player's rotation 180 degrees; the flipped FORWARD is what we ship.
    local direction
    local player_unit = local_player.player_unit
    if Unit.alive(player_unit) then
        direction = -Quaternion.forward(Unit.local_rotation(player_unit, 0))
    else
        direction = Vector3(0, 1, 0)
    end
    local grudge_str = ""
    local spec = _gt_cs_resolve_grudge_spec()
    if spec and spec.mode == "RANDOM" then
        grudge_str = "RANDOM:" .. tostring(spec.count or 1)
    elseif spec and spec.mode == "MANUAL" then
        grudge_str = "MANUAL:" .. table.concat(spec.keys or {}, ",")
    end
    if _gt_cs_client_send("spawn", breed_name, position.x, position.y, position.z,
            direction.x, direction.y, direction.z, grudge_str) then
        mod:echo("[Spawn]: Requested " .. tostring(breed_name)
            .. " from the host (needs this mod on the host; run it again if nothing happens).")
    end
end

-- Wire-format decode of the client's grudge configuration; mirrors the
-- encode in _gt_cs_client_request_spawn. Unknown/garbled input decodes to
-- nil (= no grudge marks), never an error.
local function _gt_cs_parse_grudge_str(grudge_str)
    local rand_count = string.match(grudge_str, "^RANDOM:(%d+)$")
    if rand_count then
        return { mode = "RANDOM", count = tonumber(rand_count) }
    end
    local manual_csv = string.match(grudge_str, "^MANUAL:(.*)$")
    if manual_csv then
        local keys = {}
        for key in string.gmatch(manual_csv, "[^,]+") do
            keys[#keys + 1] = key
        end
        return { mode = "MANUAL", keys = keys }
    end
    return nil
end

-- HOST: relay the result line(s) back to the requesting client so they get
-- the same feedback the host would see. Capped well under the 500-char RPC
-- payload limit (VMF_RECIPES section 4).
local function _gt_cs_ack(peer_id, message)
    message = tostring(message or "")
    if #message > 300 then message = string.sub(message, 1, 300) end
    pcall(function()
        mod:network_send(_GT_CS_ACK_RPC, peer_id, mod.GT_CS_RPC_SCHEMA, message)
    end)
end

-- HOST receiver: a client's spawn/destroy request. Schema-gated per
-- VMF_RECIPES section 10; every wire value is re-validated here (breed must
-- exist AND be spawnable on the host, numbers via tonumber, grudge keys
-- against the closed key set) - the client is a hint source, never trusted.
mod:network_register(_GT_CS_RPC, function(sender_peer_id, schema, verb, breed_name, px, py, pz, dx, dy, dz, grudge_str)
    if sender_peer_id == nil or schema ~= mod.GT_CS_RPC_SCHEMA then
        -- Engine printf, not mod:info: a schema mismatch means a peer on an
        -- incompatible gt_dev build was silently dropped - visible with
        -- mod-logging OFF.
        if rawget(_G, "printf") then
            printf("[gt_cs:693] %s schema mismatch from peer=%s: got v%s, expect v%s. Dropping.",
                _GT_CS_RPC, tostring(sender_peer_id), tostring(schema), tostring(mod.GT_CS_RPC_SCHEMA))
        end
        return
    end
    local pm = Managers.player
    if not (pm and pm.is_server) then return end
    local conflict_director = Managers.state and Managers.state.conflict
    if not conflict_director then return end
    verb = tostring(verb)
    if verb == "destroy" then
        conflict_director:destroy_all_units()
        _gt_cs_buff_cap_limit_exceeded = false
        if rawget(_G, "printf") then
            printf("[gt_cs:693] client destroy request from=%s executed", tostring(sender_peer_id))
        end
        _gt_cs_ack(sender_peer_id, "Removed all enemies (host).")
        return
    end
    if verb ~= "spawn" then return end
    breed_name = tostring(breed_name or "")
    px, py, pz = tonumber(px), tonumber(py), tonumber(pz)
    dx, dy, dz = tonumber(dx), tonumber(dy), tonumber(dz)
    if not (px and py and pz) then return end
    local breed = Breeds and rawget(Breeds, breed_name)
    if not (breed and _gt_cs_is_spawnable(breed)) then
        _gt_cs_ack(sender_peer_id, tostring(breed_name) .. " is not available on the host.")
        return
    end
    local direction = Vector3(dx or 0, dy or 1, dz or 0)
    if Vector3.length(direction) < 0.01 then
        direction = Vector3(0, 1, 0)
    end
    local rotation = Quaternion.look(direction, Vector3.up())
    local grudge_spec = _gt_cs_parse_grudge_str(tostring(grudge_str or ""))
    local ok, messages = _gt_cs_execute_spawn(conflict_director, breed_name,
        Vector3(px, py, pz), rotation, grudge_spec)
    if rawget(_G, "printf") then
        printf("[gt_cs:693] client spawn request from=%s breed=%s ok=%s",
            tostring(sender_peer_id), breed_name, tostring(ok))
    end
    _gt_cs_ack(sender_peer_id, table.concat(messages, " "))
end)

-- CLIENT receiver: the host's acknowledgement. Only the current host's acks
-- are accepted (mirrors the AI-takeover result gate).
mod:network_register(_GT_CS_ACK_RPC, function(sender_peer_id, schema, message)
    if schema ~= mod.GT_CS_RPC_SCHEMA or type(message) ~= "string" then return end
    if sender_peer_id ~= _gt_cs_host_peer_id() then return end
    mod:echo("[Spawn]: " .. message)
end)

-- Load-time wiring flag + regression marker for /gt_regression_test (#693).
-- Runtime-checkable only - no io/source self-grep in the retail sandbox.
GT_CS_CLIENT_REQUEST_MARKER_v0_2_246 = "gt-cs-client-spawn-request-i693"
mod._gt693_cs_client_request_wired = true

-- ----- COMMAND/HOTKEY HANDLERS (all bound to mod.* so VMF function_call
-- ----- keybinds can find them) -------------------------------------------

mod.gt_cs_spawn = function()
    local is_ready, conflict_director, is_client = _gt_cs_get_status()
    if is_ready then
        _gt_cs_spawn_at_cursor()
    elseif is_client then
        -- #693: spawning is host-authoritative - request it from the host.
        _gt_cs_client_request_spawn(nil)
    end
end

-- Breed cycling / save slots / the selection report only touch LOCAL state
-- (`conflict_director._debug_breed` + this peer's own gt_cs_* settings), so
-- since #693 they run on clients too - a client must be able to pick the
-- breed its spawn request names.
mod.gt_cs_next = function()
    local is_ready, conflict_director, is_client = _gt_cs_get_status()
    if not (is_ready or is_client) then return end
    _gt_cs_next_spawn_breed()
    mod:echo("[Spawn]: >> " .. tostring(conflict_director._debug_breed) .. ".")
end

mod.gt_cs_prev = function()
    local is_ready, conflict_director, is_client = _gt_cs_get_status()
    if not (is_ready or is_client) then return end
    _gt_cs_previous_spawn_breed()
    mod:echo("[Spawn]: >> " .. tostring(conflict_director._debug_breed) .. ".")
end

mod.gt_cs_destroy = function()
    local is_ready, conflict_director, is_client = _gt_cs_get_status()
    if is_ready then
        conflict_director:destroy_all_units()
        _gt_cs_buff_cap_limit_exceeded = false
        mod:echo("[Spawn]: Removed all enemies.")
    elseif is_client then
        -- #693: destroy_all_units is host-side - request it from the host.
        if _gt_cs_client_send("destroy", "", 0, 0, 0, 0, 1, 0, "") then
            mod:echo("[Spawn]: Destroy requested from the host (needs this mod on the host; run it again if nothing happens).")
        end
    end
end

local function _gt_cs_spawn_from_slot(slot_setting_id)
    local is_ready, conflict_director, is_client = _gt_cs_get_status()
    if not (is_ready or is_client) then return end
    local saved_breed = mod:get(slot_setting_id)
    if not saved_breed or saved_breed == "" then
        mod:echo("[Spawn]: Save slot is empty.")
        return
    end
    if is_client then
        -- #693: name the saved breed directly in the host request.
        _gt_cs_client_request_spawn(saved_breed)
        return
    end
    local original = conflict_director._debug_breed
    conflict_director._debug_breed = saved_breed
    _gt_cs_spawn_at_cursor()
    conflict_director._debug_breed = original
end

mod.gt_cs_spawn_slot_1 = function() _gt_cs_spawn_from_slot("gt_cs_saved_unit_one") end
mod.gt_cs_spawn_slot_2 = function() _gt_cs_spawn_from_slot("gt_cs_saved_unit_two") end
mod.gt_cs_spawn_slot_3 = function() _gt_cs_spawn_from_slot("gt_cs_saved_unit_three") end

-- /savecreature <1-3> — saves currently-selected breed to a slot.
-- Accepts numeric or word form ("one"/"two"/"three") to match upstream.
local function _gt_cs_handle_save_unit_slot(...)
    local is_ready, conflict_director, is_client = _gt_cs_get_status()
    if not (is_ready or is_client) then return end
    local args = { ... }
    local slot = ""
    for _, value in ipairs(args) do
        if type(value) == "string" then
            slot = (slot == "" and value) or (slot .. " " .. value)
        elseif type(value) == "table" then
            for _, v in ipairs(value) do
                if type(v) == "string" then
                    slot = (slot == "" and v) or (slot .. " " .. v)
                end
            end
        end
    end
    local breed = conflict_director._debug_breed
    if slot == "1" or slot == "one" then
        mod:set("gt_cs_saved_unit_one", breed, false)
        mod:echo("[Spawn]: Saved " .. tostring(breed) .. " to slot one.")
    elseif slot == "2" or slot == "two" then
        mod:set("gt_cs_saved_unit_two", breed, false)
        mod:echo("[Spawn]: Saved " .. tostring(breed) .. " to slot two.")
    elseif slot == "3" or slot == "three" then
        mod:set("gt_cs_saved_unit_three", breed, false)
        mod:echo("[Spawn]: Saved " .. tostring(breed) .. " to slot three.")
    else
        mod:echo("[Spawn]: Unrecognized save slot. Please use numbers 1-3.")
    end
end

local function _gt_cs_handle_unit_slots_report()
    local is_ready, conflict_director, is_client = _gt_cs_get_status()
    if not (is_ready or is_client) then return end
    mod:echo("Selected unit: " .. tostring(conflict_director._debug_breed or "None"))
    mod:echo("Saved unit slot one: "   .. tostring(mod:get("gt_cs_saved_unit_one")   or "None"))
    mod:echo("Saved unit slot two: "   .. tostring(mod:get("gt_cs_saved_unit_two")   or "None"))
    mod:echo("Saved unit slot three: " .. tostring(mod:get("gt_cs_saved_unit_three") or "None"))
end

-- ----- HOOKS (defensive crashes + AI gating) ----------------------------
-- Hook list mirrors upstream 1:1, with two differences:
--   (a) Where upstream reads `mod:get("cs_*")` we read `mod:get("gt_cs_*")`.
--   (b) Hooks are guarded with `if Class then` so the mod doesn't crash
--       at load when a class hasn't been loaded yet (gt loads earlier in
--       the boot sequence than CreatureSpawner does).

-- Allow unit spawns in the Keep — strip down ConflictDirector.update so the
-- minimal pieces needed for spawn_queued_unit run, without engaging full
-- AI tracking / specials pacing.
if ConflictDirector then
    mod:hook(ConflictDirector, "update", function(func, self, dt, t, ...)
        if not _gt_cs_is_in_keep() then return func(self, dt, t, ...) end
        if not self.horde_spawner and HordeSpawner then
            self.horde_spawner = HordeSpawner:new(self._world, {})
        end
        if not self.specials_pacing and SpecialsPacing then
            self.specials_pacing = SpecialsPacing:new(self.nav_world)
            self.specials_pacing:enable(false)
        end
        self.level_settings = self.level_settings or {}
        self._time = t
        self:update_spawn_queue(t)
    end)
end

-- prop_joe's fix for keep-spawn breed freeze optimisation. Without flipping
-- this flag in the keep, the engine treats spawned units as if they aren't
-- in the active level and silently drops them from update.
if StateIngame then
    mod:hook_safe(StateIngame, "update", function(...)
        script_data.disable_breed_freeze_opt = _gt_cs_is_in_keep()
    end)
end

-- Two-toggle AI gate (mission vs. keep) — short-circuits the AI brain
-- update when the relevant checkbox is off. Same pattern upstream uses.
--
-- Freeze AI (#303, dev-only) is MERGED here, not a second hook: VMF drops a
-- second mod:hook on the same (Class, method). When mod._gt_freeze_ai_active is
-- set (host-only, dev stream — see _gt_freeze_ai.lua), the whole brain tick is
-- skipped for every alive AI unit, so no enemy evaluates its behaviour tree
-- (ai_system.lua:882 `bt:root():evaluate`) — no new attack, target, or nav goal.
-- Newly-spawned enemies inherit the same freeze the instant their brain would
-- tick. Takes precedence over the creature-spawner mission/keep toggles; when
-- freeze is off the original two-toggle behaviour is untouched.
if AISystem then
    mod:hook(AISystem, "update_brains", function(func, ...)
        if mod._gt_freeze_ai_active then
            return
        end
        if not _gt_cs_is_in_keep() then
            return (mod:get("gt_cs_mission_ai") ~= false) and func(...)
        else
            return mod:get("gt_cs_keep_ai") and func(...)
        end
    end)
end

-- Lupo fix: zero out AI groups while mission AI is off so the engine
-- doesn't try to spawn AI ambush waves we explicitly disabled.
if AIGroupSystem then
    mod:hook(AIGroupSystem, "update", function(func, self, ...)
        if mod:get("gt_cs_mission_ai") == false and self.groups_to_initialize then
            for _, group in pairs(self.groups_to_initialize) do
                if group.members_n > 0 or group.num_spawned_members > 0 then
                    group.members_n = 0
                    group.num_spawned_members = 0
                end
            end
        end
        return func(self, ...)
    end)
end

-- Prevent boss loot die exception on despawn. POSITION_LOOKUP[unit] can be
-- nil during teardown; pcall keeps the engine alive past the read.
if AiBreedSnippets then
    mod:hook(AiBreedSnippets, "reward_boss_kill_loot", function(func, unit, ...)
        local position = POSITION_LOOKUP[unit]
        return pcall(function() return position.z end) and func(unit, ...)
    end)
end

-- Defensive aggro init — keep table guaranteed-present so update_aggro
-- doesn't index nil when an enemy spawns with no aggro_list yet.
if AiUtils then
    mod:hook(AiUtils, "update_aggro", function(func, unit, blackboard, breed, t, dt, ...)
        if not blackboard.aggro_list then
            blackboard.aggro_list = {}
        end
        return func(unit, blackboard, breed, t, dt, ...)
    end)
end

-- Sofia homing skull summon — provide a fallback `sofia_unit_pos` when the
-- skull is spawned outside a Sofia encounter (i.e. directly from this mod).
if ProjectileEtherealSkullLocomotionExtension then
    mod:hook(ProjectileEtherealSkullLocomotionExtension, "init", function(func, self, extension_init_context, unit, ...)
        local bb = BLACKBOARDS[unit]
        if bb and bb.optional_spawn_data and not bb.optional_spawn_data.sofia_unit_pos then
            local local_player = Managers.player and Managers.player:local_player()
            if not local_player then
                bb.optional_spawn_data.sofia_unit_pos = Vector3Box(Vector3.zero())
            else
                bb.optional_spawn_data.sofia_unit_pos = Vector3Box((_gt_cs_position_at_cursor(local_player) or Vector3.zero()))
            end
        end
        return func(self, extension_init_context, unit, ...)
    end)
end

-- Spinemanglr defensive summon — requires spawn_allies_positions, which
-- isn't populated outside of his arena. Drop the call early when not set.
if BTEnterHooks then
    mod:hook(BTEnterHooks, "warlord_defensive_on_enter", function(func, unit, blackboard, ...)
        return blackboard.spawn_allies_positions and func(unit, blackboard, ...)
    end)
end

-- BTSpawnAllies — the five-hook crash chain documented in upstream.
-- Together they: prevent enter without a call_position, drop run/leave/
-- find_spawn_point calls in the keep, and short-circuit any of them on a
-- nil-ish blackboard so the action either no-ops or returns "done".
if BTSpawnAllies then
    mod:hook(BTSpawnAllies, "enter", function(func, self, unit, blackboard, ...)
        if not _gt_cs_is_in_keep() and (blackboard.has_call_position or blackboard.override_spawn_allies_call_position) then
            return func(self, unit, blackboard, ...)
        end
        local action = self._tree_node and self._tree_node.action_data
        local find_spawn_points = action and action.find_spawn_points
        if find_spawn_points then
            local data = { end_time = math.huge }
            blackboard.spawning_allies = blackboard.spawning_allies or data
            local call_position = BTSpawnAllies.find_spawn_point(unit, blackboard, action, data)
            if call_position then
                return func(self, unit, blackboard, ...)
            else
                blackboard.spawning_allies = nil
            end
        else
            return func(self, unit, blackboard, ...)
        end
    end)

    mod:hook(BTSpawnAllies, "run", function(func, self, unit, blackboard, ...)
        return (not _gt_cs_is_in_keep() and blackboard.spawning_allies and func(self, unit, blackboard, ...)) or "done"
    end)

    mod:hook(BTSpawnAllies, "leave", function(func, self, unit, blackboard, ...)
        return (not _gt_cs_is_in_keep() and blackboard.action and func(self, unit, blackboard, ...))
    end)

    mod:hook(BTSpawnAllies, "find_spawn_point", function(func, unit, blackboard, action, data, override_spawn_group, ...)
        return (not _gt_cs_is_in_keep() and func(unit, blackboard, action, data, override_spawn_group, ...))
    end)
end

-- Drachenfels exalted sorcerer boss init — upstream's Lupo-authored
-- replacement of `run_on_spawn` that builds the full blackboard spell
-- state machine for the sorcerer fight. Verbatim port; the function is
-- intentionally long because it mirrors the vanilla boss init line-for-line
-- but skips the level_analysis nodes that only exist in dlc_castle. With
-- this hook in place the sorcerer can be spawned anywhere without
-- crashing the boss arena setup.
if Breeds and Breeds.chaos_exalted_sorcerer_drachenfels then
    mod:hook(Breeds.chaos_exalted_sorcerer_drachenfels, "run_on_spawn", function(func, unit, blackboard, ...)
        if _gt_cs_is_in_level("dlc_castle") then return func(unit, blackboard, ...) end
        local t = Managers.time:time("game")
        local breed = blackboard.breed
        blackboard.next_move_check = 0
        blackboard.max_vortex_units = breed.max_vortex_units
        blackboard.done_casting_timer = 0
        blackboard.spawned_allies_wave = 0
        blackboard.recent_attacker_timer = 0
        blackboard.recent_melee_attacker_timer = 0
        blackboard.health_extension = ScriptUnit.extension(unit, "health_system")
        blackboard.num_portals_alive = 0
        blackboard.tentacle_portal_units = {}
        blackboard.ring_total_cooldown = 20
        blackboard.charge_total_cooldown = 20
        blackboard.teleport_total_cooldown = 10
        blackboard.ring_cooldown = 0
        blackboard.charge_cooldown = 0
        blackboard.ring_summonings_finished = 0
        blackboard.teleport_cooldown = 0
        blackboard.ready_to_summon = true
        blackboard.surrounding_players = 0
        blackboard.aggro_list = {}
        blackboard.ring_pulse_rate = 0
        blackboard.defensive_phase_duration = 0
        blackboard.defensive_phase_max_duration = 60
        blackboard.no_kill_achievement = true
        blackboard.spell_count = 0
        local physics_world = World.get_data(blackboard.world, "physics_world")
        local spells = {}
        local spells_lookup = {}
        local function add_spell(s) spells[#spells + 1] = s; spells_lookup[s.name] = s end
        local s = {
            name = "plague_wave",
            plague_wave_timer = t + 10,
            physics_world = physics_world,
            target_starting_pos = Vector3Box(),
            plague_wave_rot = QuaternionBox(),
            search_func = BTChaosExaltedSorcererSkulkAction.update_plague_wave,
        }
        blackboard.plague_wave_data = s; add_spell(s)
        s = { range = 40, magic_missile = true, magic_missile_speed = 20,
            true_flight_template_name = "sorcerer_magic_missile",
            projectile_unit_name = "units/weapons/projectile/magic_missile/magic_missile",
            name = "magic_missile", launch_angle = 0.7,
            search_func = BTChaosExaltedSorcererSkulkAction.update_cast_missile,
            throw_pos = Vector3Box(), target_direction = Vector3Box() }
        blackboard.magic_missile_data = s; add_spell(s)
        s = { range = 40, magic_missile = true, magic_missile_speed = 15,
            true_flight_template_name = "sorcerer_strike_missile",
            projectile_unit_name = "units/weapons/projectile/strike_missile/strike_missile",
            name = "sorcerer_strike_missile",
            explosion_template_name = "chaos_strike_missile_impact",
            launch_angle = 1.25,
            search_func = BTChaosExaltedSorcererSkulkAction.update_cast_missile,
            throw_pos = Vector3Box(), target_direction = Vector3Box() }
        blackboard.sorcerer_strike_missile_data = s; add_spell(s)
        s = { range = 40, name = "magic_missile_ground", magic_missile = true,
            magic_missile_speed = 10, target_ground = true,
            projectile_unit_name = "units/weapons/projectile/strike_missile_drachenfels/strike_missile_drachenfels",
            true_flight_template_name = "sorcerer_magic_missile_ground",
            explosion_template_name = "chaos_drachenfels_strike_missile_impact",
            search_func = BTChaosExaltedSorcererSkulkAction.update_cast_missile,
            throw_pos = Vector3Box(), target_direction = Vector3Box() }
        blackboard.magic_missile_ground_data = s; add_spell(s)
        s = { name = "missile_barrage", magic_missile = true, magic_missile_speed = 20, range = 40,
            search_func = BTChaosExaltedSorcererSkulkAction.update_cast_missile,
            throw_pos = Vector3Box(), target_direction = Vector3Box() }
        blackboard.missile_barrage_data = s; add_spell(s)
        s = { range = 40, name = "seeking_bomb_missile", magic_missile = true, magic_missile_speed = 2.5,
            true_flight_template_name = "sorcerer_slow_bomb_missile",
            projectile_unit_name = "units/weapons/projectile/insect_swarm_missile_drachenfels/insect_swarm_missile_drachenfels_01",
            explosion_template_name = "chaos_slow_bomb_missile_new", life_time = 15,
            search_func = BTChaosExaltedSorcererSkulkAction.update_cast_missile,
            throw_pos = Vector3Box(), target_direction = Vector3Box(),
            projectile_size = { 3, 3, 3 } }
        blackboard.seeking_bomb_missile_data = s; add_spell(s)
        s = { name = "dummy", search_func = BTChaosExaltedSorcererSkulkAction.update_dummy }
        blackboard.dummy_data = s; add_spell(s)
        blackboard.phase = "offensive"
        blackboard.in_boss_arena = false
        blackboard.valid_teleport_pos_func = function() return true end
        local side = Managers.state.side:get_side_from_name("heroes")
        local player_units = side.PLAYER_AND_BOT_UNITS
        for _, player_unit in pairs(player_units) do
            local health_ext = ScriptUnit.extension(player_unit, "health_system")
            health_ext.is_invincible = true
        end
        blackboard.spells = spells
        blackboard.spells_lookup = spells_lookup
        local audio_system_ext = Managers.state.entity:system("audio_system")
        if breed.teleport_sound_event then
            audio_system_ext:play_audio_unit_event(breed.teleport_sound_event, unit)
        end
        local conflict_director = Managers.state.conflict
        conflict_director:add_unit_to_bosses(unit)
        blackboard.is_valid_target_func = GenericStatusExtension.is_lord_target
    end)

    mod:hook(Breeds.chaos_exalted_sorcerer_drachenfels, "run_on_death", function(func, unit, blackboard, ...)
        if _gt_cs_is_in_level("dlc_castle") then return func(unit, blackboard, ...) end
        local conflict_director = Managers.state.conflict
        local position = Unit.world_position(unit, 0)
        conflict_director:remove_unit_from_bosses(unit)
        local audio_system = Managers.state.entity:system("audio_system")
        audio_system:play_audio_unit_event("Play_sorcerer_boss_fly_stop", unit)
        local t = Managers.time:time("game")
        Managers.state.conflict.specials_pacing:delay_spawning(t, 120, 20, true)
        if blackboard.is_angry then
            conflict_director:add_angry_boss(-1)
        end
        AiBreedSnippets.drop_loot_dice(4, position, true)
    end)
end

-- Drachenfels phase-transition condition. OUTSIDE dlc_castle force TRUE so a
-- Creature-Spawner-spawned Nurgloth skips its arena-specific defensive phase and
-- stays offensive (the missing arena nodes would otherwise soft-lock it). INSIDE
-- dlc_castle (the real Nurgloth arena, incl. CW dlc_castle_* variants) defer to
-- vanilla so the real boss fight runs its three defensive/offensive cycles.
--
-- 2026-07-06 (issue 275): the old body
--     return (_gt_cs_is_in_level("dlc_castle") and func(...)) or true
-- COLLAPSED to constant-true everywhere. In the real arena, when vanilla
-- correctly returned false (boss had not yet passed the one-third-health
-- transition), `(true and false) or true` still yielded true, forcing Nurgloth's
-- BT into its "final offense phase" (chaos_exalted_sorcerer_drachenfels_behavior
-- .lua:239) at full health with the intro's 0.65 min-health gate never lowered -
-- breaking the real boss fight, always. Probe evidence (2026-07-06 author log):
--   [et:275] HOOK sorcerer_drachenfels_go_offensive_intense | hp_pct=1.000 ...
--            two_thirds_done=nil one_third_done=nil
-- The decision now lives in the pure, regression-tested helper below (explicit
-- branching; vanilla's return is passed through unaltered, multi-return safe).
function mod._gt_cs_one_third_wrapper(in_arena, ...)
    if in_arena then
        return ...
    end
    return true
end
if BTConditions then
    mod:hook(BTConditions, "transitioned_one_third_health", function(func, ...)
        return mod._gt_cs_one_third_wrapper(_gt_cs_is_in_level("dlc_castle"), func(...))
    end)
end

-- ----------------------------------------------------------------------------
-- Issue #59 secondary fix: defensive nil-guard for BTConditions.at_*_health
-- ----------------------------------------------------------------------------
-- The level-prefix-match fix above (and the `_gt_cs_is_in_level` underscore-
-- boundary match at the top of this file) closes the original Drachenfels crash
-- by sending CW dlc_castle_*_path1 variants down the vanilla run_on_spawn path,
-- which correctly initializes blackboard.current_health_percent before any BT
-- tick reads it. This block is the BELT-AND-SUSPENDERS guard the issue calls
-- out: bias every condition that bare-compares blackboard.current_health_percent
-- against a number toward FALSE (boss has not yet hit the threshold) if the
-- field is nil. Same logic for `less_than_one_health` which reads
-- blackboard.current_health. Closes a hypothetical first-tick race on ANY boss
-- BT (not just Drachenfels) where the BT evaluates a health condition between
-- breed:run_on_spawn and the first AISystem update_blackboard_health tick.
--
-- Per-(breed, condition) printf dedupe -- BT conditions tick continuously, so
-- unfiltered output would spam. One line per save tells us in-game whether the
-- race is actually firing and on which boss, without flooding the console.
local _gt_bt_health_nil_seen = {}
local function _gt_bt_health_pct_nil_guard(cond_name)
    return function(func, blackboard)
        if blackboard and blackboard.current_health_percent == nil then
            local breed = blackboard.breed
            local bname = (breed and breed.name) or "<no-breed>"
            local key = bname .. "|" .. cond_name
            if not _gt_bt_health_nil_seen[key] and rawget(_G, "printf") then
                _gt_bt_health_nil_seen[key] = true
                printf("[gt_bt:#59] nil-guard suppressed %s on breed=%s (current_health_percent uninitialized -- first-tick race)",
                    cond_name, bname)
            end
            return false
        end
        return func(blackboard)
    end
end
local function _gt_bt_health_raw_nil_guard(cond_name)
    return function(func, blackboard)
        if blackboard and blackboard.current_health == nil then
            local breed = blackboard.breed
            local bname = (breed and breed.name) or "<no-breed>"
            local key = bname .. "|" .. cond_name
            if not _gt_bt_health_nil_seen[key] and rawget(_G, "printf") then
                _gt_bt_health_nil_seen[key] = true
                printf("[gt_bt:#59] nil-guard suppressed %s on breed=%s (current_health uninitialized -- first-tick race)",
                    cond_name, bname)
            end
            return false
        end
        return func(blackboard)
    end
end
if BTConditions then
    -- Each (BTConditions, <method>) pair is a distinct hook target -- no dup
    -- risk vs the transitioned_one_third_health hook above (different method).
    mod:hook(BTConditions, "at_half_health",                _gt_bt_health_pct_nil_guard("at_half_health"))
    mod:hook(BTConditions, "at_one_third_health",           _gt_bt_health_pct_nil_guard("at_one_third_health"))
    mod:hook(BTConditions, "at_two_thirds_health",          _gt_bt_health_pct_nil_guard("at_two_thirds_health"))
    mod:hook(BTConditions, "at_one_fifth_health",           _gt_bt_health_pct_nil_guard("at_one_fifth_health"))
    mod:hook(BTConditions, "at_three_fifths_health",        _gt_bt_health_pct_nil_guard("at_three_fifths_health"))
    mod:hook(BTConditions, "can_transition_half_health",    _gt_bt_health_pct_nil_guard("can_transition_half_health"))
    mod:hook(BTConditions, "can_transition_one_third_health", _gt_bt_health_pct_nil_guard("can_transition_one_third_health"))
    mod:hook(BTConditions, "less_than_one_health",          _gt_bt_health_raw_nil_guard("less_than_one_health"))
end

-- Issue #59 regression marker -- if a future refactor drops these guards the
-- main-file rt check `bt_health_conditions_nilguarded_marker_present` fails.
GT_BT_HEALTH_NILGUARD_MARKER_v0_2_149 = "gt-bt-health-conditions-nilguarded-i59"

-- Keep-navigation crash suite. All of these short-circuit when in the
-- keep level (no real navmesh for AI to path on). Matches upstream 1:1.
if BTLootRatFleeAction then
    mod:hook(BTLootRatFleeAction, "enter", function(func, ...) return (not _gt_cs_is_in_keep() and func(...)) or false end)
    mod:hook(BTLootRatFleeAction, "run",   function(func, ...) return (not _gt_cs_is_in_keep() and func(...)) or "running" end)
    mod:hook(BTLootRatFleeAction, "leave", function(func, ...) return (not _gt_cs_is_in_keep() and func(...)) or false end)
end
if NavigationGroupManager then
    mod:hook(NavigationGroupManager, "a_star_cached_between_positions", function(func, ...)
        return (not _gt_cs_is_in_keep() and func(...)) or false
    end)
end
if LocomotionUtils then
    mod:hook(LocomotionUtils, "pos_on_mesh", function(func, ...)
        return (not _gt_cs_is_in_keep() and func(...)) or nil
    end)
end
if GwNavQueries then
    mod:hook(GwNavQueries, "inside_position_from_outside_position", function(func, ...)
        return (not _gt_cs_is_in_keep() and func(...)) or nil
    end)
end

-- Prevent keep navigation crash — Unit.create_actor with id=-1 in the keep
-- crashes the engine actor allocator. Block only that exact case.
mod:hook(Unit, "create_actor", function(func, self, id, ...)
    if not _gt_cs_is_in_keep() or id ~= -1 then
        return func(self, id, ...)
    end
end)

if BTSkulkAroundAction then
    mod:hook(BTSkulkAroundAction, "get_new_skulk_goal", function(func, self, unit, blackboard, ...)
        if not _gt_cs_is_in_keep() then return func(self, unit, blackboard, ...) end
        local player = Managers.player:local_player()
        local player_unit = player and player.player_unit
        return player_unit and Unit.local_position(player_unit, 0) or Vector3(0, 0, 0)
    end)
end

-- Server-controlled buff cap detector. NetworkConstants caps the number of
-- buff ids the host can broadcast; once we're close to it, flip the flag
-- so grudge-mark random modifiers stop adding to the bucket. Matches
-- upstream behaviour 1:1.
if BuffSystem and NetworkConstants and NetworkConstants.server_controlled_buff_id then
    mod:hook(BuffSystem, "add_buff", function(func, self, ...)
        local return_val = func(self, ...)
        if (self.next_server_buff_id or 0) * 10 >= NetworkConstants.server_controlled_buff_id.max * 5 then
            _gt_cs_buff_cap_limit_exceeded = true
        else
            _gt_cs_buff_cap_limit_exceeded = false
        end
        return return_val
    end)
end

-- Missing-unit guard — when a breed references a unit path that isn't in
-- any loaded package, fall back to `units/hub_elements/empty` so the
-- engine doesn't fatally fail spawn_unit. Same fallback unit upstream uses.
mod:hook(World, "spawn_unit", function(func, self, unit_name, ...)
    if Application.can_get("unit", unit_name) then
        return func(self, unit_name, ...)
    else
        return func(self, "units/hub_elements/empty", ...)
    end
end)

-- Force EnemyPackageLoader to ignore breed limits — the limit is what
-- normally prevents debug spawns from loading the right packages on demand.
if EnemyPackageLoader then
    mod:hook(EnemyPackageLoader, "request_breed", function(func, self, breed_name, ignore_breed_limits, ...)
        return func(self, breed_name, true, ...)
    end)
end

-- Command registration (gt-prefixed to namespace away from upstream's
-- bare `spawn_unit` / `save_unit` / `selected_units` names).
mod:command("spawncreature",  "Spawn the currently-selected creature at the cursor",                function() mod.gt_cs_spawn() end)
mod:command("nextcreature",   "Cycle to the next creature in the active list",                     function() mod.gt_cs_next() end)
mod:command("prevcreature",   "Cycle to the previous creature in the active list",                 function() mod.gt_cs_prev() end)
mod:command("destroycreatures", "Destroy every currently-spawned creature (a client asks the host)", function() mod.gt_cs_destroy() end)
mod:command("savecreature",   "Save current creature to a slot (1-3)",                             function(...) _gt_cs_handle_save_unit_slot(...) end)
mod:command("selectedcreatures", "Report current selection and the three save slots",            function() _gt_cs_handle_unit_slots_report() end)

-- Dispatch callbacks consumed by the main-file on_setting_changed /
-- on_game_state_changed DISPATCHERS (which stay in main per the dispatcher
-- rule). Exposed as mod._gt_cs_* fields so the main dispatchers resolve them
-- at call time — this module dofiles AFTER the main chunk, so by the time
-- either dispatcher fires at runtime both fields are set.
-- #693: both callbacks now run on clients too (`is_ready or is_client`) -
-- they only mutate the LOCAL selection (`conflict_director._debug_breed` +
-- this peer's own settings), which the client request channel reads.
mod._gt_cs_on_setting_changed = function(setting_id)
    if setting_id == "gt_cs_unit_list" then
        local is_ready, conflict_director, is_client = _gt_cs_get_status()
        if not (is_ready or is_client) then return end
        local list = _gt_cs_active_list()
        _gt_cs_breed_name_index = 1
        conflict_director._debug_breed = list[1] or "skaven_dummy_slave"
        mod:set("gt_cs_selected_unit", conflict_director._debug_breed, false)
        mod:echo("[Spawn]: >> " .. tostring(conflict_director._debug_breed) .. ".")
    elseif setting_id == "gt_cs_selected_unit" then
        local is_ready, conflict_director, is_client = _gt_cs_get_status()
        if not (is_ready or is_client) then return end
        conflict_director._debug_breed = mod:get("gt_cs_selected_unit")
        mod:echo("[Spawn]: >> " .. tostring(conflict_director._debug_breed) .. ".")
    end
end

mod._gt_cs_on_game_state_changed = function(status, state_name)
    local is_ready, conflict_director, is_client = _gt_cs_get_status(true)
    if not (is_ready or is_client) then return end
    if not mod:get("gt_cs_selected_unit") or mod:get("gt_cs_selected_unit") == "" then
        local list = _gt_cs_active_list()
        conflict_director._debug_breed = list[1] or "skaven_dummy_slave"
        mod:set("gt_cs_selected_unit", conflict_director._debug_breed, false)
    else
        conflict_director._debug_breed = mod:get("gt_cs_selected_unit")
    end
    _gt_cs_buff_cap_limit_exceeded = false
end

-- Issue #454: NO boot-time _gt_cs_build_unit_lists() call here (upstream
-- CreatureSpawner builds once at mod load). The lists are rebuilt lazily in
-- _gt_cs_active_list() so breeds registered AFTER this module loads (DLC
-- late registration, enemy_tweaker's et_* clones, other mods) are included.

-- ============================================================
-- /gt_regression_test checks (#693)
-- ============================================================
-- Mirrors the gt_lobby/gt_ai/gt_draw schema checks: the `gt_cs_request` +
-- `gt_cs_ack` sender and receiver both read mod.GT_CS_RPC_SCHEMA; if it goes
-- missing the receiver gate compares against nil and would accept anything.
mod._gt_rt_register("gt_cs_rpc_schema_present", function()
    if type(mod.GT_CS_RPC_SCHEMA) ~= "number" then
        return "mod.GT_CS_RPC_SCHEMA not defined as number"
    end
    if mod.GT_CS_RPC_SCHEMA < 1 then
        return "mod.GT_CS_RPC_SCHEMA < 1"
    end
end)

-- Issue 693: the client->host request channel (both network events + the
-- client request helpers) must be wired at load. Runtime-only flag check -
-- io is nil in the VMF sandbox, so no source self-grep.
mod._gt_rt_register("gt693_cs_client_request_wired", function()
    if mod._gt693_cs_client_request_wired ~= true then
        return "creature-spawner client request channel not wired (issue 693: _gt_creature_spawner.lua)"
    end
    if GT_CS_CLIENT_REQUEST_MARKER_v0_2_246 ~= "gt-cs-client-spawn-request-i693" then
        return "client-request marker absent - was the issue-693 fix reverted?"
    end
end)
