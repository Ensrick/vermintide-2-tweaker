--[[
_et_skaven_warlord_breed.lua — "Skaven Warlord" boss breed registration (#324).

Clones a new boss breed (`et_skaven_warlord`) from PRISTINE vanilla
`skaven_storm_vermin_champion` (breed_skaven_storm_vermin_champion.lua) and
walks the ENTIRE enemy_tweaker/DEVELOPMENT.md "Breed-adding checklist"
(threat_values upvalue, StatisticsDefinitions per-breed seeds,
PerformanceManager coverage, NetworkLookup forward+reverse, BreedActions
clone) plus every additional boot-time `pairs(Breeds)` snapshot found in the
2026-07-04 source audit (Dismemberments, SKAVEN race set, BreedHitZonesLookup,
EnemyPackageLoaderSettings alias, NetworkLookup.damage_sources,
UISettings.breed_textures) — each patch cites the decompiled file:line it
neutralizes.

WHY the champion as source: the issue (#324) asks for the "unused Skaven
Warlord model". `units/beings/enemies/skaven_stormvermin_champion/
chr_skaven_stormvermin_champion` (breed_skaven_storm_vermin_champion.lua:12)
is a colour-variant of Skarrik's warlord model that only the rarely-seen
Champion boss uses; the clone keeps that base_unit and the champion's vanilla
800-HP boss stat block (max_health {300,350,400,500,800,800,800,800},
breed_skaven_storm_vermin_champion.lua:88-97).

LOAD ORDER CONTRACT: enemy_tweaker.lua dofiles THIS file BEFORE the Champion
elite-pool retune's load-time apply (`_safe("champion_load_apply", ...)`), so
Breeds[skaven_storm_vermin_champion] is guaranteed pristine when we deep-copy
— even when the user's `champion_in_elite_pool` toggle is saved ON. The
retune also only ever REASSIGNS the four tuned fields (max_health /
ai_strength / ai_toughness / primary_armor_category) with new values and
restores from a backup of the ORIGINAL references, so it can never mutate the
tables our deep copy captured. A signature check below alerts if this
ordering ever regresses.

EAGER-REGISTRATION DOCTRINE (DEVELOPMENT.md "Lessons"): VMF-disabled mods
still execute module-level code, so everything here is a direct table write
that is safe (crash-free) even when et is disabled. The single mod:hook in
this file (_G.Localize) is display-only; if et is disabled the hook doesn't
fire and grudge names render as raw keys — degraded text, never a crash.

Open-world / behaviour-tree safety (verified, no guards needed):
  * The champion behaviour tree (breed.behavior = "storm_vermin_champion",
    skaven_storm_vermin_champion_behavior.lua:5-133) contains NO BTSpawnAllies
    node and NO spawner-group reference — unlike Skarrik's tree
    (skaven_storm_vermin_warlord_behavior.lua:57-59, `warlord_spawners`),
    which needed et's v0.7.16 off-arena guard.
  * The champion breed has NO `stagger_modifier_function`
    (breed_skaven_storm_vermin_champion.lua, full read) — Skarrik's
    unguarded `t < blackboard.intro_timer` crash (v0.7.14 guard) does not
    exist on this breed.
  * run_on_spawn (ai_breed_snippets.lua:587-644) guards its only
    level-specific lookup (`generic_ai_node_units.warlord_go_to`,
    :630-632 `if node_units then`); trickle reinforcements (:687-703) use the
    global HordeCompositions key "stronghold_boss_trickle" via
    horde_spawner:execute_event_horde — level-agnostic. The et Champion
    elite-pool swap (v0.7.18-dev) has shipped these exact snippets spawning
    open-world with no crash class reported.
  * Known vanilla cosmetic quirk carried over: run_on_death drops 2 boss loot
    dice at a HARDCODED Stormdorf position (ai_breed_snippets.lua:766 →
    drop_loot :1358-1385, `Vector3(166.5, -46, 38)`) when the game mode has
    boss loot. Cosmetic only (dice land off-site); same behaviour as et's
    shipped Champion swap.

NETWORK / UNMODDED-CLIENT CONSTRAINT: the breed name is appended to
NetworkLookup.breeds and NetworkLookup.damage_sources (both carry a strict
__index metatable, network_lookup.lua:2360-2367). Registration is a single
deterministic append at mod load, so every peer RUNNING enemy_tweaker agrees
on the index. A client WITHOUT enemy_tweaker cannot resolve the index when
the breed spawns/deals damage and will hard-error — every peer in the lobby
must have enemy_tweaker installed (enabled or not; module-level registration
runs either way) before the host spawns this breed.
]]

local mod = get_mod("enemy_tweaker")
local B = require("scripts/mods/enemy_tweaker/enemy_tweaker_breeds")
local ET = mod._et
local NLLib = ET.NetworkLookupLib

local BREED_NAME   = B.ET_SKAVEN_WARLORD          -- "et_skaven_warlord"
local SOURCE_BREED = "skaven_storm_vermin_champion"

-- Log-only diagnostics: engine printf (lands in console-*.log even with VMF
-- mod logging OFF — PROJECT_STANDARDS § 3.6 / memory printf-not-modinfo).
local function _wl_log(fmt, ...)
    if not pcall(printf, "[et:warlord2] " .. fmt, ...) then
        pcall(printf, "[et:warlord2] (log format error: %s)", tostring(fmt))
    end
end

-- Validate (or append) both wire identities through the same strict helper on
-- first load and hot reload.  A published breed is not proof that a newly
-- created VMF mod object has revalidated the current NetworkLookup tables.
local function _register_wire_identity()
    local nl = rawget(_G, "NetworkLookup")
    if type(nl) ~= "table" then
        _wl_log("ALERT: NetworkLookup unavailable — breed NOT network-registered")
        return false
    end
    local _, breeds_inserted, breeds_reason =
        NLLib.register_named(nl, "breeds", BREED_NAME)
    if not breeds_inserted and breeds_reason ~= "already_registered" then
        _wl_log("ALERT: NetworkLookup.breeds registration failed (%s) — breed NOT registered",
            tostring(breeds_reason))
        return false
    end
    local _, damage_inserted, damage_reason =
        NLLib.register_named(nl, "damage_sources", BREED_NAME)
    if not damage_inserted and damage_reason ~= "already_registered" then
        _wl_log("ALERT: NetworkLookup.damage_sources registration failed (%s) — breed NOT registered",
            tostring(damage_reason))
        return false
    end
    return true
end

-- ============================================================
-- Registration (eager, idempotent, pcall-bracketed per step)
-- ============================================================
local function _register()
    mod._et_warlord2_breed_name = nil
    mod._et_warlord2_ready = false
    local Breeds_t = rawget(_G, "Breeds")
    local BreedActions_t = rawget(_G, "BreedActions")
    if type(Breeds_t) ~= "table" or type(BreedActions_t) ~= "table" then
        _wl_log("Breeds/BreedActions not loaded — registration skipped")
        return false
    end
    if Breeds_t[BREED_NAME] then
        if not _register_wire_identity() then return false end
        mod._et_warlord2_breed_name = BREED_NAME
        mod._et_warlord2_ready = true
        _wl_log("breed %s revalidated on hot reload", BREED_NAME)
        return true
    end
    local src = Breeds_t[SOURCE_BREED]
    if type(src) ~= "table" then
        _wl_log("source breed %s missing — registration skipped", SOURCE_BREED)
        return false
    end

    -- Pristine-source signature check (see LOAD ORDER CONTRACT above).
    -- Vanilla champion max_health[8] == 800 (breed_skaven_storm_vermin_champion.lua:88-97);
    -- the elite retune replaces the whole table with a 52..500 ramp.
    if type(src.max_health) ~= "table" or src.max_health[8] ~= 800 then
        _wl_log("ALERT: champion source looks retuned (max_health[8]=%s) — load-order regression; clone proceeds but stats may be non-vanilla",
            tostring(type(src.max_health) == "table" and src.max_health[8]))
    end

    -- 1. Deep-copy the breed (foundation/scripts/util/table.lua:31-48
    -- table.clone recurses subtables; functions — run_on_spawn/death/update,
    -- infighting etc. — copy by reference, which is exactly what we want).
    local ok, breed = pcall(table.clone, src)
    if not ok or type(breed) ~= "table" then
        _wl_log("ALERT: table.clone(%s) failed: %s — breed NOT registered", SOURCE_BREED, tostring(breed))
        return false
    end
    -- Fields vanilla's boot post-processing stamps per-name (breeds.lua:305-307)
    -- come out of the copy holding the CHAMPION's values — overwrite the name.
    breed.name = BREED_NAME
    -- BossHealthUI renders an unmarked boss as
    -- Localize(breed.display_name or breed_name) (boss_health_ui.lua:303 + :174);
    -- key served by the _G.Localize hook below.
    breed.display_name = B.ET_SKAVEN_WARLORD_NAME_KEY
    -- NOTE: Breeds[BREED_NAME] is assigned LAST (end of this function), after
    -- every side-table seed succeeded — the breed's presence in Breeds is the
    -- go/no-go signal both for et's own monster-pool swap and for ct_dev's
    -- cursed-chest trial guard, so a partial registration must never leave a
    -- spawnable-but-unseeded breed behind.

    -- 2. BreedActions clone (DEVELOPMENT.md checklist step 5). The behaviour
    -- tree itself bakes the CHAMPION's action tables at boot
    -- (skaven_storm_vermin_champion_behavior.lua:3 `local ACTIONS =
    -- BreedActions.skaven_storm_vermin_champion`), so combat runs on champion
    -- data either way; this entry serves every generic
    -- `BreedActions[breed.name]` reader, and SET_BREED_DIFFICULTY
    -- (breeds.lua:194-226) walks pairs(BreedActions) at difficulty-set time
    -- (post-mod-load), so the clone gets its difficulty bake too.
    if BreedActions_t[SOURCE_BREED] and not BreedActions_t[BREED_NAME] then
        local a_ok, actions = pcall(table.clone, BreedActions_t[SOURCE_BREED])
        if a_ok and type(actions) == "table" then
            BreedActions_t[BREED_NAME] = actions
        else
            _wl_log("ALERT: BreedActions clone failed: %s", tostring(actions))
        end
    end

    -- 3. threat_values upvalue (checklist step 1). conflict_director.lua
    -- builds `local threat_values` ONCE at game-boot from pairs(Breeds)
    -- (~:2297); a missing entry crashes calculate_threat_value with
    -- `nil * amount` (live line 2479). set_threat_value ignores `self` and
    -- writes the file-local upvalue directly — callable statically.
    local CD = rawget(_G, "ConflictDirector")
    if CD and CD.set_threat_value then
        CD.set_threat_value(nil, BREED_NAME, breed.threat_value or 0)
        mod._et_warlord2_threat_seeded = true
    else
        _wl_log("ALERT: ConflictDirector.set_threat_value unavailable — threat value NOT seeded")
    end

    -- 4. StatisticsDefinitions per-breed seeds (checklist step 2). Vanilla
    -- loop is statistics_definitions.lua:615-657 and runs at file load only.
    -- Every emitted entry carries `name` (incl. persistent + per-difficulty
    -- children) per DEVELOPMENT.md: _init_backend_stat's leaf marker is
    -- `definition.name` (statistics_database.lua:102 live); the repo
    -- decompile is stale on this.
    -- NOT seeded (verified gated): weapon_kills_per_breed DLC snapshots
    -- (statistics_definitions_lake.lua:21 / _cog.lua:79) — their only
    -- increment sites are gated on fixed vanilla breed lists
    -- (achievement_templates_lake.lua:103 table.contains(boss_breeds,...),
    -- achievement_templates_cog.lua:1040 table.contains(elite_special_breeds,...)),
    -- so our breed early-returns before the stat write.
    local sd = rawget(_G, "StatisticsDefinitions")
    local player = sd and sd.player
    if player and player.kills_per_breed then
        player.kills_per_breed[BREED_NAME] = {
            sync_on_hot_join = true, value = 0, name = BREED_NAME,
        }
        player.kills_per_breed_persistent[BREED_NAME] = {
            source = "player_data", value = 0, name = BREED_NAME,
            database_name = "kills_per_breed_persistent_" .. BREED_NAME,
        }
        player.kill_assists_per_breed[BREED_NAME] = { value = 0, name = BREED_NAME }
        player.damage_dealt_per_breed[BREED_NAME] = { value = 0, name = BREED_NAME }
        -- kills_per_race: race "skaven" already seeded at boot
        -- (statistics_definitions.lua:637-642 guard) — nothing to add.
        player.kills_per_breed_difficulty[BREED_NAME] = {}
        player.kill_assists_per_breed_difficulty[BREED_NAME] = {}
        local diffs = rawget(_G, "DifficultySettings")
        if diffs then
            for difficulty_name in pairs(diffs) do
                player.kills_per_breed_difficulty[BREED_NAME][difficulty_name] = {
                    value = 0, name = BREED_NAME .. "_" .. difficulty_name,
                }
                player.kill_assists_per_breed_difficulty[BREED_NAME][difficulty_name] = {
                    value = 0, name = BREED_NAME .. "_" .. difficulty_name,
                }
            end
        end
    else
        _wl_log("ALERT: StatisticsDefinitions.player unavailable — per-breed stats NOT seeded")
    end

    -- 5. PerformanceManager (checklist step 3). VERIFIED: _activated_per_breed
    -- is rebuilt from pairs(Breeds) inside PerformanceManager.init at LEVEL
    -- START (performance_manager.lua:84-88), which always runs AFTER mod load
    -- — so a breed registered here is picked up by every future mission's
    -- rebuild with no hook at all (a VMF hook would also violate the
    -- disabled-mod doctrine: DEVELOPMENT.md "Hooks are conditional, direct
    -- method calls aren't"). Belt: seed any ALREADY-LIVE manager instance
    -- (hot-reload / mid-mission registration edge).
    local mgrs = rawget(_G, "Managers")
    local perf = mgrs and mgrs.state and mgrs.state.performance
    if perf and type(perf._activated_per_breed) == "table" then
        perf._activated_per_breed[BREED_NAME] = perf._activated_per_breed[BREED_NAME] or 0
    end

    -- 6. NetworkLookup.breeds forward + reverse (checklist step 4) AND
    -- NetworkLookup.damage_sources: both are boot snapshots
    -- (network_lookup.lua:267 create_lookup from pairs(Breeds); :326
    -- table.append(damage_sources, NetworkLookup.breeds)) with a strict
    -- __index metatable (:2360-2367). The entry-owned shared helper performs a
    -- complete raw dense/pair preflight before either idempotence or append.
    -- damage_sources matters because AI melee damage uses the breed NAME as
    -- damage_source (ai_utils.lua:266) and add_damage_network resolves
    -- NetworkLookup.damage_sources[damage_source] (damage_utils.lua:1839).
    -- [unverified] headroom of the damage_source_id network type above the
    -- vanilla count (network_constants.lua:62 asserts only at boot); one
    -- appended entry is assumed within budget.
    if not _register_wire_identity() then return false end

    -- 7. EnemyPackageLoaderSettings alias: the vanilla mechanism for "breed X
    -- loads breed Y's package" (enemy_package_loader_settings.lua:188-199,
    -- e.g. skaven_storm_vermin_commander -> skaven_storm_vermin).
    -- request_breed / is_breed_processed / is_breed_loaded_on_all_peers all
    -- resolve through ALIAS_TO_BREED first (enemy_package_loader.lua:189,
    -- :263, :955) — the loader captures the TABLE as an upvalue at boot
    -- (:11), so mutating its CONTENTS here is seen at call time. Result:
    -- spawning et_skaven_warlord loads the champion's own package
    -- (resource_packages/breeds/skaven_storm_vermin_champion — it is a
    -- registered dynamically-loadable 'level_specific' breed,
    -- enemy_package_loader_settings.lua:42) over the vanilla networked
    -- loader, exactly like the old Skarrik swap. We never call
    -- Managers.package:load ourselves.
    local epls = rawget(_G, "EnemyPackageLoaderSettings")
    if epls and type(epls.alias_to_breed) == "table" then
        epls.alias_to_breed[BREED_NAME] = SOURCE_BREED
        local bta = epls.breed_to_aliases
        if type(bta) == "table" then
            bta[SOURCE_BREED] = bta[SOURCE_BREED] or {}
            local aliases = bta[SOURCE_BREED]
            local present = false
            for i = 1, #aliases do
                if aliases[i] == BREED_NAME then present = true break end
            end
            if not present then aliases[#aliases + 1] = BREED_NAME end
        end
    else
        _wl_log("ALERT: EnemyPackageLoaderSettings unavailable — package alias NOT registered")
    end

    -- 8. Dismemberments: boot loop hit_reactions_template_compiler.lua:174-189
    -- seeds Dismemberments[breed_name]; the consumer indexes it UNGUARDED on
    -- dismember (generic_hit_reaction_extension.lua:544-545
    -- `Dismemberments[breed_data.name][hit_zone]`) — a missing entry is a
    -- hit-time crash. Identical hit_zones -> share the champion's table.
    local dis = rawget(_G, "Dismemberments")
    if dis and dis[SOURCE_BREED] and not dis[BREED_NAME] then
        dis[BREED_NAME] = dis[SOURCE_BREED]
    end

    -- 9. SKAVEN race set (breeds.lua:329-345 boot loop) — faction membership
    -- checks read the global set.
    local skaven_set = rawget(_G, "SKAVEN")
    if type(skaven_set) == "table" then
        skaven_set[BREED_NAME] = true
    end

    -- 10. BreedHitZonesLookup mirror (breeds.lua:24/112; runtime writer
    -- damage_utils.lua:1725 keys it by breed name). The deep copy already
    -- carries hit_zones_lookup baked at boot (breeds.lua:115); mirror the
    -- global entry for parity with vanilla state.
    local bhzl = rawget(_G, "BreedHitZonesLookup")
    if type(bhzl) == "table" and not bhzl[BREED_NAME] and breed.hit_zones_lookup then
        bhzl[BREED_NAME] = breed.hit_zones_lookup
    end

    -- 11. Boss health-bar portrait: UISettings.breed_textures (ui_settings.lua:291;
    -- boss_health_ui.lua:6 captures the TABLE at boot, contents read per call
    -- :162). Reuse Skarrik's warlord portrait (ui_settings.lua:358) — the
    -- shipped Skarrik monster-pool swap has rendered it cross-level since
    -- v0.7.12-dev.
    local uis = rawget(_G, "UISettings")
    if uis and type(uis.breed_textures) == "table" then
        uis.breed_textures[BREED_NAME] = "unit_frame_portrait_enemy_warlord"
    end

    -- 12. Grudge-marked names (#324 Part 3). Consumer:
    -- TerrorEventUtils.get_grudge_marked_name (terror_event_utils.lua:59-78)
    -- reads GrudgeMarkedNames[breed_name] at CALL time (global field read,
    -- no upvalue capture of the inner lists), so a mod-added key IS honoured;
    -- without one it would fall back to GrudgeMarkedNames[breed.race]
    -- ("skaven", grudge_mark_settings.lua:313). UNmarked spawns never touch
    -- this table: boss_health_ui.lua:279 only calls the grudge path when the
    -- ai-system attribute `grudge_marked` was set by
    -- apply_breed_enhancements (terror_event_utils.lua:84); otherwise it
    -- renders breed.display_name (:303).
    local gmn = rawget(_G, "GrudgeMarkedNames")
    if type(gmn) == "table" and not gmn[BREED_NAME] then
        local list = {}
        for i = 1, #B.WARLORD_GRUDGE_NAMES do
            list[i] = B.WARLORD_GRUDGE_NAMES[i].key
        end
        gmn[BREED_NAME] = list
    elseif type(gmn) ~= "table" then
        _wl_log("ALERT: GrudgeMarkedNames unavailable — grudge names NOT registered")
    end

    -- FINAL step: publish the breed. Everything above succeeded (or logged
    -- an ALERT for a degraded-but-safe gap); only now does the breed become
    -- visible to spawn paths and to ct_dev's trial guard.
    Breeds_t[BREED_NAME] = breed

    mod._et_warlord2_breed_name = BREED_NAME
    mod._et_warlord2_ready = true
    _wl_log("breed %s registered (clone of %s; boss, race=skaven, 800 HP champion stat block)",
        BREED_NAME, SOURCE_BREED)
    return true
end

-- pcall-bracketed: an unexpected mid-registration error must leave the game
-- clean (breed unpublished -> et swap and ct trial stay inert) instead of
-- failing the whole mod load. Side-table entries written before the error
-- (network indices, alias, stats) are inert without the breed.
local _reg_ok, _reg_err = pcall(_register)
if not _reg_ok then
    _wl_log("ALERT: registration errored: %s — Skaven Warlord unavailable this session", tostring(_reg_err))
end

-- ============================================================
-- Vanilla-visible localization (#324 Parts 1+3)
-- ============================================================
-- et's ONLY _G.Localize hook (duplicate-hook pre-flight 2026-07-04: grep of
-- enemy_tweaker/ found no other `mod:hook(_G, "Localize", ...)` — VMF drops a
-- second hook on the same (table, method) pair). Serves the breed display
-- name (boss_health_ui.lua:174 Localize on the unmarked title) and the 12
-- grudge names (terror_event_utils.lua:75 Localize(name_list[index])).
-- Marker for /et_regression_test: _et_warlord2_localize_hooked.
do
    local STRINGS = {
        [B.ET_SKAVEN_WARLORD_NAME_KEY] = "Skaven Warlord",
    }
    for i = 1, #B.WARLORD_GRUDGE_NAMES do
        local entry = B.WARLORD_GRUDGE_NAMES[i]
        STRINGS[entry.key] = entry.en
    end
    mod._et_warlord2_loc_strings = STRINGS

    mod:hook(_G, "Localize", function(func, key, ...)
        local s = STRINGS[key]
        if s then
            return s
        end
        return func(key, ...)
    end)
    mod._et_warlord2_localize_hooked = true
end

-- ============================================================
-- #324 diagnostics: "runs in place, no combat AI" spawn probe
-- ============================================================
-- July report: a spawned Skaven Warlord stands or runs in place with no combat
-- AI. The breed publishes healthy-looking structure, so this bounded probe logs
-- what the live AI actually selected. Per instrumented spawn it emits ONE
-- [et:324] line at spawn, +5s, and +15s (max 4 spawns per session = max 12
-- rows), capturing:
--   * breed.behavior + whether the brain's tree is the tree the AI system
--     serves for that name (AIBrain:init binds self._bt =
--     ai_system:behavior_tree(tree_name), ai_brain.lua:70-72),
--   * the running BT leaf, walked exactly like vanilla's debug-unit dump
--     (extension._brain._bt:root() + current_running_child(blackboard) loop,
--     ai_system.lua:952-957) plus AISimpleExtension.current_action_name
--     (ai_simple_extension.lua:408),
--   * blackboard.target_unit (+aliveness), confirmed_player_sighting
--     (perception result consumed at ai_system.lua:884-887), is_passive, and
--     the spawn/spawning_finished flags (BTSpawningAction only clears
--     blackboard.spawn in leave, bt_spawning_action.lua:74-80 — a stuck spawn
--     node is the classic "runs in place" shape),
--   * nav/locomotion: navigation_extension._enabled + is_following_path()
--     (ai_navigation_extension.lua:218-220, 380-381),
--     locomotion_extension:current_velocity() (ai_locomotion_extension.lua:374),
--     and distance moved from the spawn position.
-- Host-side only by construction: the observe callback is dispatched from the
-- singleton ConflictDirector._post_spawn_unit seam owned by _et_boss_grudge.lua
-- (conflict_director.lua spawns are server-authoritative), which covers all
-- three spawn paths (Creature Spawner, monster-pool swap, ct chest trial).
-- The +5s/+15s samples ride the single mod.update owner in _et_lifecycle.lua
-- via ET.warlord_diag_update.
do
    local DIAG_OFFSETS = { 5, 15 }   -- seconds after the spawn-time sample
    local DIAG_MAX_UNITS = 4
    local _tracked = {}              -- [i] = { unit=, t0=, spawn_pos=Vector3Box, next=1 }
    local _units_instrumented = 0
    local _cap_logged = false

    local function _diag_log(fmt, ...)
        if not pcall(printf, "[et:324] " .. fmt, ...) then
            pcall(printf, "[et:324] (log format error: %s)", tostring(fmt))
        end
    end

    local function _fmt_unit(u)
        if u == nil then return "nil" end
        local alive = Unit.alive(u)
        return string.format("%s(alive=%s)", tostring(u), tostring(alive))
    end

    local function _snapshot(entry, label)
        local unit = entry.unit
        if not Unit.alive(unit) then
            _diag_log("%s unit no longer alive (died/despawned) — sampling stops", label)
            return false
        end
        local bb = rawget(_G, "BLACKBOARDS") and BLACKBOARDS[unit]
        local ext = ScriptUnit.has_extension(unit, "ai_system")
        if not bb or not ext then
            _diag_log("%s blackboard=%s ai_extension=%s — AI never attached",
                label, tostring(bb ~= nil), tostring(ext ~= nil))
            return true
        end
        local breed = bb.breed
        local behavior = breed and breed.behavior or "nil"
        local brain = ext._brain
        local bt = brain and brain._bt
        local tree_match = "no_brain"
        local entity_mgr = Managers.state and Managers.state.entity
        local ai_system = entity_mgr and entity_mgr:system("ai_system")
        if bt and ai_system and ai_system.behavior_tree then
            local t_ok, expected = pcall(ai_system.behavior_tree, ai_system, behavior)
            tree_match = tostring(t_ok and expected == bt)
        end
        local leaf_name = "unknown"
        if bt then
            local w_ok, name = pcall(function()
                local leaf = bt:root()
                while leaf and leaf.current_running_child and leaf:current_running_child(bb) do
                    leaf = leaf:current_running_child(bb)
                end
                return leaf and leaf:id() or "none"
            end)
            if w_ok then leaf_name = tostring(name) end
        end
        local a_ok, action = pcall(ext.current_action_name, ext)
        local nav = bb.navigation_extension
        local nav_enabled, nav_following = "nil", "nil"
        if nav then
            nav_enabled = tostring(nav._enabled)
            local n_ok, following = pcall(nav.is_following_path, nav)
            nav_following = tostring(n_ok and following)
        end
        local speed = -1
        local loco = bb.locomotion_extension
        if loco then
            local v_ok, vel = pcall(loco.current_velocity, loco)
            if v_ok and vel then speed = Vector3.length(vel) end
        end
        local moved = -1
        local p_ok, pos = pcall(Unit.local_position, unit, 0)
        if p_ok and pos and entry.spawn_pos then
            moved = Vector3.distance(pos, entry.spawn_pos:unbox())
        end
        _diag_log("%s behavior=%s tree_match=%s leaf=%s action=%s target=%s sighting=%s passive=%s spawnflag=%s spawn_done=%s nav_enabled=%s nav_following=%s speed=%.2f moved=%.2f",
            label, tostring(behavior), tree_match, leaf_name,
            tostring(a_ok and action), _fmt_unit(bb.target_unit),
            tostring(bb.confirmed_player_sighting), tostring(bb.is_passive),
            tostring(bb.spawn), tostring(bb.spawning_finished),
            nav_enabled, nav_following, speed, moved)
        return true
    end

    -- Dispatched from the _post_spawn_unit seam in _et_boss_grudge.lua (that
    -- module checks type()=="function" at call time, so load order is safe).
    ET.observe_warlord_diag_spawn = function(ai_unit, breed)
        if not breed or breed.name ~= BREED_NAME then return end
        if _units_instrumented >= DIAG_MAX_UNITS then
            if not _cap_logged then
                _cap_logged = true
                _diag_log("instrumentation cap reached (%d spawns) — later spawns not sampled", DIAG_MAX_UNITS)
            end
            return
        end
        _units_instrumented = _units_instrumented + 1
        local entry = { unit = ai_unit, t0 = os.clock(), next = 1 }
        local p_ok, pos = pcall(Unit.local_position, ai_unit, 0)
        if p_ok and pos then entry.spawn_pos = Vector3Box(pos) end
        local n = _units_instrumented
        pcall(_snapshot, entry, string.format("spawn#%d t=+0s", n))
        entry.label_n = n
        _tracked[#_tracked + 1] = entry
    end

    ET.warlord_diag_update = function()
        for i = #_tracked, 1, -1 do
            local entry = _tracked[i]
            local due = entry.t0 + DIAG_OFFSETS[entry.next]
            if os.clock() >= due then
                local ok, keep = pcall(_snapshot, entry,
                    string.format("spawn#%d t=+%ds", entry.label_n, DIAG_OFFSETS[entry.next]))
                entry.next = entry.next + 1
                if not ok or keep == false or entry.next > #DIAG_OFFSETS then
                    table.remove(_tracked, i)
                end
            end
        end
    end

    ET.rt_register("issue324_warlord_diag_armed", function()
        if not mod._et_warlord2_ready then
            return "et_skaven_warlord breed not registered — diagnostic has no subject"
        end
        if type(ET.observe_warlord_diag_spawn) ~= "function" then
            return "spawn observer missing"
        end
        if type(ET.warlord_diag_update) ~= "function" then
            return "timed-sample update driver missing"
        end
        local breed = rawget(_G, "Breeds") and Breeds[BREED_NAME]
        if not breed or breed.behavior ~= "storm_vermin_champion" then
            return "breed behavior drifted from storm_vermin_champion"
        end
    end)

    if mod._et_warlord2_ready then
        _diag_log("diagnostic armed: %s spawns sampled at +0/+5/+15s (cap %d per session)",
            BREED_NAME, DIAG_MAX_UNITS)
    else
        _diag_log("diagnostic loaded but breed registration failed — nothing to sample this session")
    end
end
