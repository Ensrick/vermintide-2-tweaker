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
still execute module-level code, so this module submits one declarative spec to
the #1413 registrar at load. The registrar publishes nothing until every
mandatory surface and both wire axes pass. The single mod:hook in this file
(_G.Localize) is display-only; if et is disabled the hook doesn't fire and
grudge names render as raw keys — degraded text, never a crash.

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
local Registrar = ET.CustomBreedRegistrar

local BREED_NAME   = B.ET_SKAVEN_WARLORD          -- "et_skaven_warlord"
local SOURCE_BREED = "skaven_storm_vermin_champion"

-- Log-only diagnostics: engine printf (lands in console-*.log even with VMF
-- mod logging OFF — PROJECT_STANDARDS § 3.6 / memory printf-not-modinfo).
local function _wl_log(fmt, ...)
    if not pcall(printf, "[et:warlord2] " .. fmt, ...) then
        pcall(printf, "[et:warlord2] (log format error: %s)", tostring(fmt))
    end
end

-- Build empty mod-local presentation targets before registration. Every
-- display/grudge string is then published by the transaction (new VMF mod
-- objects need these ephemeral rows republished on hot reload).
local STRINGS = {}
mod._et_warlord2_loc_strings = STRINGS

local grudge_names = {}
local presentation_rows = {
    { target = STRINGS, key = B.ET_SKAVEN_WARLORD_NAME_KEY,
        value = "Skaven Warlord", ephemeral = true },
}
for i = 1, #B.WARLORD_GRUDGE_NAMES do
    local entry = B.WARLORD_GRUDGE_NAMES[i]
    grudge_names[i] = entry.key
    presentation_rows[#presentation_rows + 1] = {
        target = STRINGS, key = entry.key, value = entry.en, ephemeral = true,
    }
end
presentation_rows[#presentation_rows + 1] = {
    target = rawget(rawget(_G, "UISettings") or {}, "breed_textures"),
    key = BREED_NAME, value = "unit_frame_portrait_enemy_warlord",
}
presentation_rows[#presentation_rows + 1] = {
    target = rawget(_G, "GrudgeMarkedNames"),
    key = BREED_NAME, value = grudge_names,
}

mod._et_warlord2_breed_name = nil
mod._et_warlord2_ready = false
mod._et_warlord2_threat_seeded = false

local registration_ok, registration_reason = Registrar.register({
    owner = "enemy_tweaker.skaven_warlord",
    name = BREED_NAME,
    source_breed = SOURCE_BREED,
    race = "skaven",
    fingerprint = "et-custom-breed:v3:skaven-warlord:champion-pristine",
    configure = function(breed)
        breed.display_name = B.ET_SKAVEN_WARLORD_NAME_KEY
    end,
    validate_breed = function(breed)
        if breed.display_name ~= B.ET_SKAVEN_WARLORD_NAME_KEY then
            return nil, "display_name_mismatch"
        end
        if type(breed.max_health) ~= "table" or breed.max_health[8] ~= 800 then
            return nil, "champion_source_signature_mismatch"
        end
        return true
    end,
    presentations = presentation_rows,
    readiness = {
        { target = mod, key = "_et_warlord2_threat_seeded", value = true },
        { target = mod, key = "_et_warlord2_breed_name", value = BREED_NAME },
        { target = mod, key = "_et_warlord2_ready", value = true },
    },
})
if registration_ok then
    _wl_log("breed %s %s through atomic registrar (source=%s)",
        BREED_NAME, tostring(registration_reason), SOURCE_BREED)
else
    _wl_log("ALERT: registration rejected (%s) — Skaven Warlord unavailable this session",
        tostring(registration_reason))
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
