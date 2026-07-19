local mod = get_mod("enemy_tweaker")

-- _et_champion_warlord.lua — champion/warlord spawn pools + crash guards
--
-- Owns the Stormvermin Champion roaming-elite retune + swap (v0.7.18-dev),
-- the Skaven Warlord monster-pool swap (#324 target = the mod-added
-- et_skaven_warlord breed registered by _et_skaven_warlord_breed.lua, which
-- MUST be dofile'd BEFORE this module — the clone snapshots pristine vanilla
-- champion values before the retune below can touch them), the CONSOLIDATED
-- ConflictDirector.spawn_queued_unit hook both swaps share, and the two
-- off-arena Skarrik crash guards (intro_timer stagger default, BTSpawnAllies
-- missing-spawner-group neutralization).
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd after
-- _et_skaven_warlord_breed, before _et_director_hooks). Consumed via mod._et
-- exports: apply_champion_breed_overrides.

local ET = mod._et
local rt_register = ET.rt_register
local _dbg_alert  = ET.dbg_alert
local _spawn_dbg  = ET.spawn_dbg
local _safe       = ET.safe
local _hook_wrap  = ET.hook_wrap
local _hook_wrap_table = ET.hook_wrap_table

-- ============================================================
-- Roaming Elite Pool: Stormvermin Champion (v0.7.18-dev)
-- ============================================================
-- Toggle-gated, default-OFF, HOST-side: a per-spawn roll can replace a ROAMING
-- skaven elite (skaven_storm_vermin / _with_shield / _commander) with the
-- Stormvermin Champion (skaven_storm_vermin_champion). "Roaming" is gated on
-- spawn_type == "roam" (set by EnemyRecycler at enemy_recycler.lua:585), which
-- excludes horde / paced / event / boss spawns — so the Champion only subs in
-- for the loose wandering elites the user asked for, not horde stormvermin. The
-- swap itself lives INSIDE the shared spawn_queued_unit hook below (VMF drops a
-- 2nd hook on the same Class.method — see the consolidation banner there).
--
-- The Champion is a registered, dynamically-loadable boss breed (same class as
-- the Warlord), so the swap reuses the vanilla networked spawn/loader path
-- exactly like the Warlord monster-pool feature — we never call
-- Managers.package:load ourselves.
--
-- Per-user stat retune (applied to the Champion breed while the feature is ON):
--   * max_health: 260 at Cataclysm (difficulty rank 5 = internal `hardest`),
--     ~1/5 (52) at Recruit (rank 1), linear ramp between; ranks 6-8
--     (Cataclysm 2/3/3+) scaled on above. Vanilla Champion is an 800-HP boss.
--   * AI tuning copied from Skarrik Spinemanglr (skaven_storm_vermin_warlord):
--     ai_strength = 10, ai_toughness = 10 (Champion vanilla is 6 / 3).
--   * Super armor via primary_armor_category = 6 — the chaos-warrior / warlord /
--     exalted-champion tier (breed_chaos_warrior.lua:79).
--
-- SIDE EFFECT (flagged in tooltip + CHANGELOG): mutating the shared Champion
-- breed retunes EVERY Champion on this peer while the toggle is on — including
-- the rare vanilla appearances (weave missions, a few terror-event hordes, the
-- Khorne Champions mutator). Gated behind the toggle + restored on disable, and
-- every peer running et applies the same retune so host/client agree. Peers
-- without et (or toggle off) keep the vanilla 800-HP Champion — pin the setting
-- across the lobby for a consistent session (same caveat as et's other
-- host-side spawn features).
local _CHAMPION_BREED = "skaven_storm_vermin_champion"
local _CHAMPION_ELIGIBLE_ELITES = {
    skaven_storm_vermin             = true,
    skaven_storm_vermin_with_shield = true,
    skaven_storm_vermin_commander   = true,
}
-- index = difficulty_rank: 1 Recruit, 2 Veteran, 3 Champion, 4 Legend,
-- 5 Cataclysm, 6 Cataclysm 2, 7 Cataclysm 3, 8 Cataclysm 3+. 260 @ rank 5 per
-- user spec; 52 (=260/5) @ rank 1; linear between; scaled on above Cataclysm.
local _CHAMPION_ELITE_MAX_HEALTH    = { 52, 104, 156, 208, 260, 340, 420, 500 }
local _CHAMPION_ELITE_AI_STRENGTH   = 10  -- Skarrik (warlord) value; Champion vanilla = 6
local _CHAMPION_ELITE_AI_TOUGHNESS  = 10  -- Skarrik (warlord) value; Champion vanilla = 3
local _CHAMPION_ELITE_PRIMARY_ARMOR = 6   -- super armor (chaos-warrior / warlord tier)

local _champion_vanilla_backup   = nil
local _champion_overrides_active = nil    -- nil = untouched, true = applied, false = restored

-- Idempotent: writes only when the toggle state changed since last call. Reads
-- mod:get("champion_in_elite_pool") (falsy when the toggle is off OR the mod is
-- disabled, so on_disabled restores vanilla correctly).
local function _apply_champion_breed_overrides()
    local b = rawget(_G, "Breeds") and Breeds[_CHAMPION_BREED]
    if type(b) ~= "table" then
        _dbg_alert("champion: Breeds[%s] not loaded — deferring override", _CHAMPION_BREED)
        return
    end
    local want = mod:get("champion_in_elite_pool") and true or false
    if want == _champion_overrides_active then return end
    if want then
        if not _champion_vanilla_backup then
            _champion_vanilla_backup = {
                max_health             = b.max_health,
                ai_strength            = b.ai_strength,
                ai_toughness           = b.ai_toughness,
                primary_armor_category = b.primary_armor_category,  -- nil in vanilla
            }
        end
        b.max_health             = _CHAMPION_ELITE_MAX_HEALTH
        b.ai_strength            = _CHAMPION_ELITE_AI_STRENGTH
        b.ai_toughness           = _CHAMPION_ELITE_AI_TOUGHNESS
        b.primary_armor_category = _CHAMPION_ELITE_PRIMARY_ARMOR
        mod:info("[champion] elite-pool overrides applied (260@Cata / AI 10,10 / super-armor)")
    elseif _champion_vanilla_backup then
        b.max_health             = _champion_vanilla_backup.max_health
        b.ai_strength            = _champion_vanilla_backup.ai_strength
        b.ai_toughness           = _champion_vanilla_backup.ai_toughness
        b.primary_armor_category = _champion_vanilla_backup.primary_armor_category
        mod:info("[champion] elite-pool overrides restored to vanilla")
    end
    _champion_overrides_active = want
end

-- Load-time apply so every peer running et reflects its saved toggle at boot
-- (cross-peer health interpretation must match). Idempotent; re-asserted at
-- ConflictDirector.init + the VMF lifecycle callbacks.
_safe("champion_load_apply", _apply_champion_breed_overrides)

-- ============================================================
-- Monster Pool: Skaven Warlord (v0.7.12-dev; retargeted #324 v0.7.27-dev)
-- ============================================================
-- Toggle-gated, default-OFF, HOST-side: when a boss terror event would spawn a
-- standard monster, a per-spawn roll can replace it with the mod-added
-- "Skaven Warlord" breed (et_skaven_warlord — the unused champion-recolour of
-- Skarrik's model with vanilla 800-HP champion boss stats; see
-- _et_skaven_warlord_breed.lua). v0.7.12-v0.7.26 swapped in literal Skarrik
-- (skaven_storm_vermin_warlord); #324 retargets the swap to the new breed and
-- renames the feature — the chance-slider semantics are unchanged. Monsters
-- spawn via ConflictDirector boss terror events -> ConflictDirector:spawn_one ->
-- spawn_queued_unit (conflict_director.lua:1732) — a DIFFERENT path than the
-- horde breed-swap (HordeSpawner), so this needs its own hook.
--
-- CRASH-SAFE PACKAGE LOAD: we substitute the breed TABLE only and let VANILLA
-- spawn_queued_unit run its own load — it calls enemy_package_loader:request_breed
-- (conflict_director.lua:1740). For the MOD-ADDED breed that request resolves
-- through EnemyPackageLoaderSettings.alias_to_breed (enemy_package_loader.lua:189
-- `breed_name = ALIAS_TO_BREED[breed_name] or breed_name`; alias registered at
-- breed registration) to skaven_storm_vermin_champion — a registered
-- dynamically-loadable 'level_specific' breed
-- (enemy_package_loader_settings.lua:42) whose package contains our clone's
-- base_unit. The spawn queue still blocks on is_breed_loaded_on_all_peers
-- (conflict_director.lua:1847), which alias-resolves the same way
-- (enemy_package_loader.lua:955). We NEVER call Managers.package:load ourselves
-- (the raw-unit-path call is what async-crashed et at the v0.7.10 banner
-- force-load). RESIDUAL RISK: on a level whose bundle lacks the champion
-- package, vanilla's async load could still fail — default off + host-must-test
-- (see tooltip).
--
-- chaos_troll_chief is DELIBERATELY excluded — it's the Festering Ground scripted
-- finale boss; swapping it would break that mission's scripted event.
--
-- _WARLORD_BREED (literal Skarrik) is kept for the two shipped off-arena crash
-- guards below — both are breed-conditional on skaven_storm_vermin_warlord
-- (the intro_timer wrap lives ON that breed's own stagger_modifier_function;
-- the BTSpawnAllies guard gates on blackboard.breed.name), so they keep
-- protecting Skarrik spawns from OTHER sources (vanilla Skittergate flows,
-- SpawnTweaks-style mods). The NEW breed needs NEITHER guard: its champion
-- base has no stagger_modifier_function (breed_skaven_storm_vermin_champion.lua,
-- full read) and its behaviour tree has no BTSpawnAllies node
-- (skaven_storm_vermin_champion_behavior.lua:5-133).
local _WARLORD_BREED = "skaven_storm_vermin_warlord"
local _WARLORD_ELIGIBLE_MONSTERS = {
    skaven_rat_ogre   = true,
    skaven_stormfiend = true,
    chaos_spawn       = true,
    chaos_troll       = true,
    beastmen_minotaur = true,
}

-- ============================================================
-- CONSOLIDATED spawn_queued_unit hook (SINGLE hook per Class.method — VMF drops
-- duplicates). Two independent breed substitutions share this body:
--   1. Warlord monster-pool swap (v0.7.12-dev) — eligible MONSTER -> Skarrik.
--   2. Champion roaming-elite swap (v0.7.18-dev) — roaming ELITE -> Champion.
-- They gate on disjoint (breed, spawn_type) conditions, so at most one fires per
-- spawn. Singleton-invariant marker: _et_spawn_queued_unit_consolidated.
-- ============================================================
_hook_wrap("ConflictDirector", "spawn_queued_unit", "spawn_queued_unit_swaps",
        function(func, self, breed, boxed_spawn_pos, boxed_spawn_rot, spawn_category,
                 spawn_animation, spawn_type, optional_data, group_data, unit_data)
    -- 1. Skaven Warlord monster-pool swap (#324: target is the mod-added
    -- et_skaven_warlord breed, no longer literal Skarrik). Fast early-out:
    -- one mod:get when off. mod._et_warlord2_breed_name is set only after
    -- _et_skaven_warlord_breed.lua completed registration — if registration
    -- failed the swap stays inert (no fallback to Skarrik by design).
    local wl2 = mod._et_warlord2_breed_name
    if mod:get("warlord_in_monster_pool")
            and wl2
            and type(breed) == "table"
            and _WARLORD_ELIGIBLE_MONSTERS[breed.name]
            and not (optional_data and optional_data.et_boss_balance_no_pool_swap)
            and rawget(_G, "Breeds") and Breeds[wl2] then
        -- Host-only: spawn_queued_unit/request_breed are server-authoritative.
        -- Substituting on the host means the warlord replicates to clients
        -- normally (engine network-synced loader + is_breed_loaded_on_all_peers
        -- gate). Managers.player.is_server is a boolean field (player_manager.lua:41).
        -- CLIENT REQUIREMENT: every peer must have enemy_tweaker installed —
        -- the mod-added breed's NetworkLookup entries only exist on et peers
        -- (see the constraint banner in _et_skaven_warlord_breed.lua).
        local pm = Managers and Managers.player
        if pm and pm.is_server then
            local chance = mod:get("warlord_monster_chance") or 0
            if chance > 0 and math.random() * 100 <= chance then
                local original = breed.name
                breed = Breeds[wl2]
                _spawn_dbg("warlord", "monster %s -> Skaven Warlord (%s, chance=%d)", tostring(original), wl2, chance)
            end
        end
    end

    -- 2. Champion roaming-elite swap. Roaming spawns only (spawn_type == "roam",
    -- set by EnemyRecycler at enemy_recycler.lua:585) so horde / event / boss
    -- stormvermin are never touched. Host-only (server-authoritative spawn); the
    -- Champion is a registered loadable breed so vanilla replicates it normally.
    -- breed is re-checked here (the warlord block above may have reassigned it,
    -- but a monster breed is never in the elite set, so the two never collide).
    if mod:get("champion_in_elite_pool")
            and spawn_type == "roam"
            and type(breed) == "table"
            and _CHAMPION_ELIGIBLE_ELITES[breed.name]
            and rawget(_G, "Breeds") and Breeds[_CHAMPION_BREED] then
        local pm = Managers and Managers.player
        if pm and pm.is_server then
            local chance = mod:get("champion_elite_chance") or 0
            if chance > 0 and math.random() * 100 <= chance then
                local original = breed.name
                breed = Breeds[_CHAMPION_BREED]
                _spawn_dbg("champion", "roaming elite %s -> Stormvermin Champion (chance=%d)", tostring(original), chance)
            end
        end
    end

    return func(self, breed, boxed_spawn_pos, boxed_spawn_rot, spawn_category,
                spawn_animation, spawn_type, optional_data, group_data, unit_data)
end)

-- v0.7.14-dev: husk / open-pool warlord `intro_timer` crash guard.
-- `breed.stagger_modifier_function` (breed_skaven_storm_vermin_warlord.lua:170)
-- does an UNGUARDED `t < blackboard.intro_timer`. `intro_timer` is set only by the
-- HOST's run_on_spawn (ai_breed_snippets.lua:626, on_storm_vermin_champion_spawn);
-- the CLIENT/husk path (run_on_husk_spawn) sets no timer fields, so a peer
-- resolving stagger on a husk warlord hits `t < nil` and crashes
-- (do_stagger_calculation, damage_utils.lua:775). Every OTHER vanilla reader of
-- intro_timer guards it (e.g. bt_conditions.lua:87 `blackboard.intro_timer and …`),
-- so nil is a state vanilla already tolerates — this one callback is the oversight.
-- Wrap the breed's data-field callback (a PLAIN function, NOT a VMF class hook, so
-- no hook-collision) to default `intro_timer = 0` ("intro already over" — correct
-- for an open-pool spawn that has no intro sequence) before vanilla runs. Idempotent
-- via the `_et_intro_timer_guarded` flag; install is unconditional because it only
-- acts when intro_timer is nil, which never happens on the scripted-arena host
-- spawn. Reported 2026-06-20 (Skarrik Spinemangler crash, GUID f2818b56).
do
    local wb = rawget(_G, "Breeds") and Breeds[_WARLORD_BREED]
    if wb and type(wb.stagger_modifier_function) == "function" and not wb._et_intro_timer_guarded then
        local _vanilla_stagger_mod = wb.stagger_modifier_function
        wb.stagger_modifier_function = function(stagger_type, duration, length, hit_zone_name, blackboard, ...)
            if blackboard and blackboard.unit and blackboard.intro_timer == nil then
                blackboard.intro_timer = 0  -- intro already elapsed -> normal stagger behavior
            end
            return _vanilla_stagger_mod(stagger_type, duration, length, hit_zone_name, blackboard, ...)
        end
        wb._et_intro_timer_guarded = true
        mod:info("[warlord] intro_timer stagger guard installed on %s", _WARLORD_BREED)
    end
end

-- v0.7.16-dev: open-pool warlord BTSpawnAllies "lacking spawners" crash guard.
-- The Warlord BT runs a `BTSpawnAllies` node (`spawn_allies`,
-- skaven_storm_vermin_warlord_behavior.lua:57-59) that calls
-- ALLIES into the `warlord_spawners` spawner group to summon reinforcements.
-- That group only exists in the Warlord's home arena (Stormdorf). On any other
-- level — here a CW-injected dlc_termite_2 mission — the group is absent, so the
-- node's spawn-point lookup raises a HARD fassert:
--   bt_spawn_allies_action.lua:184
--   `fassert(spawners_raw, "Level %s is lacking spawners of spawner group %s,
--    this is necessary to use BTSpawnAllies behaviour in breed %s", …)`
-- reached from BTSpawnAllies.enter:39 -> BTSpawnAllies.find_spawn_point:178
-- (`spawner_system._id_lookup[spawn_group]` is nil). Reported 2026-06-20
-- (Skarrik Spinemangler crash, GUID e87eacaa). This is the SECOND out-of-arena
-- Warlord crash (1st = the intro_timer stagger guard above, v0.7.14).
--
-- `find_spawn_point` is a PLAIN function on the BTSpawnAllies table (a static
-- method called as `BTSpawnAllies.find_spawn_point(unit, …)`, not `self:` —
-- bt_spawn_allies_action.lua:175), so we wrap the table entry directly: NOT a
-- VMF class hook, so no duplicate-hook concern (grep-verified: enemy_tweaker has
-- no `mod:hook` on BTSpawnAllies / find_spawn_point). LOWEST BLAST RADIUS: the
-- wrap only diverts from vanilla when BOTH (a) the BT's breed is the Warlord
-- (`blackboard.breed.name == _WARLORD_BREED`) AND (b) `warlord_spawners` is
-- genuinely missing from the LIVE spawner system (`_id_lookup[spawn_group] == nil`,
-- the exact table+key vanilla asserts on). Every other breed's BTSpawnAllies, and
-- the Warlord IN ITS HOME ARENA (where `warlord_spawners` IS registered, so the
-- lookup is non-nil), fall straight through to vanilla untouched.
--
-- Neutralization: instead of asserting, end the spawn-allies node cleanly. We
-- populate the minimal `data` fields the surrounding `BTSpawnAllies.enter` still
-- touches after our return (`data.call_position` — a Vector3Box that enter:45
-- `:store()`s into when `override_spawn_allies_call_position` is set, which the
-- Warlord's `warlord_defensive_on_enter` hook always sets; and `data.spawn_forward`),
-- then NIL `blackboard.spawning_allies` so `BTSpawnAllies.run` returns "done" on
-- its first tick (run:381 `if not data then return "done"`) BEFORE `_spawn` runs.
-- That skips `_spawn`'s `data.spawners` deref entirely (we have no real spawners
-- to give it — a fake/empty spawners list would `#spawners`-modulo-crash _spawn at
-- :340), so the Warlord simply does its call-allies wind-up and gets no
-- reinforcements off-arena. We return the Warlord's own position as the
-- call_position. Wrapped in pcall via _hook_wrap; any inner error falls through to
-- vanilla (which, off-arena, would re-assert — but we only reach vanilla if our
-- gate didn't match, i.e. the group exists). Idempotent install; install is
-- unconditional because the gate is per-call.
local _BTSpawnAllies = rawget(_G, "BTSpawnAllies")
if _BTSpawnAllies and type(_BTSpawnAllies.find_spawn_point) == "function" then
_hook_wrap_table(_BTSpawnAllies, "find_spawn_point",
        "warlord_spawn_allies_no_group",
        function(func, unit, blackboard, action, data, override_spawn_group)
    if blackboard and blackboard.breed and blackboard.breed.name == _WARLORD_BREED then
        local spawn_group = override_spawn_group or (action and action.optional_go_to_spawn)
            or (action and action.spawn_group)
        local ent = Managers and Managers.state and Managers.state.entity
        local spawner_system = ent and ent:system("spawner_system")
        local group_present = spawner_system and spawn_group
            and spawner_system._id_lookup and spawner_system._id_lookup[spawn_group]
        -- Only divert when the group is genuinely absent (off home arena) AND
        -- vanilla has no fallback-spawner escape hatch for this action.
        if not group_present and not (action and action.use_fallback_spawners) then
            local self_pos = (rawget(_G, "POSITION_LOOKUP") and POSITION_LOOKUP[unit])
                or (unit and Unit.alive(unit) and Unit.world_position(unit, 0))
            if self_pos and data then
                local fwd = Quaternion.forward(Unit.local_rotation(unit, 0))
                data.spawn_forward = Vector3Box(fwd)
                data.call_position = Vector3Box(self_pos)
                -- Ending the node before _spawn: no spawners are dereferenced.
                blackboard.spawning_allies = nil
                _spawn_dbg("warlord", "off-arena Skarrik: spawner group '%s' absent -> neutralizing BTSpawnAllies (no reinforcements)",
                    tostring(spawn_group))
                return self_pos
            end
        end
    end
    return func(unit, blackboard, action, data, override_spawn_group)
end)
    mod:info("[warlord] BTSpawnAllies off-arena spawner-group guard installed")
end

ET.apply_champion_breed_overrides = _apply_champion_breed_overrides

rt_register("warlord_monster_swap_hook", function()
    -- Verifies the monster->Skaven Warlord substitution hook target + the
    -- #324 swap target. The swap must point at the MOD-ADDED breed
    -- (et_skaven_warlord), not literal Skarrik (retargeted v0.7.27-dev).
    if type(rawget(_G, "ConflictDirector")) ~= "table"
            or type(ConflictDirector.spawn_queued_unit) ~= "function" then
        return "ConflictDirector.spawn_queued_unit missing — warlord monster-swap hook target absent"
    end
    if mod._et_warlord2_breed_name ~= "et_skaven_warlord" then
        return "mod._et_warlord2_breed_name is not 'et_skaven_warlord' — #324 swap retarget missing/failed"
    end
    if not (rawget(_G, "Breeds") and Breeds.et_skaven_warlord) then
        return "Breeds.et_skaven_warlord missing — Skaven Warlord breed not registered"
    end
end)

rt_register("skaven_warlord_breed_checklist", function()
    -- #324: full DEVELOPMENT.md breed-adding checklist verification for
    -- et_skaven_warlord (side-tables seeded, network identity, package alias,
    -- grudge names, vanilla-visible localization, pristine clone stats).
    local name = "et_skaven_warlord"
    local BreedsT = rawget(_G, "Breeds")
    local b = BreedsT and BreedsT[name]
    if type(b) ~= "table" then return "breed not in Breeds" end
    if b.name ~= name then return "breed.name not overwritten (still " .. tostring(b.name) .. ")" end
    if b.boss ~= true or b.race ~= "skaven" then return "breed lost boss/race fields" end
    if type(b.max_health) ~= "table" or b.max_health[8] ~= 800 then
        return "clone max_health[8] ~= 800 — champion elite retune leaked into the clone"
    end
    if b.base_unit ~= "units/beings/enemies/skaven_stormvermin_champion/chr_skaven_stormvermin_champion" then
        return "clone base_unit is not the champion recolour unit"
    end
    if not mod._et_warlord2_threat_seeded then return "threat_values not seeded (CD.set_threat_value)" end
    local sd = rawget(_G, "StatisticsDefinitions")
    local pl = sd and sd.player
    if not (pl and pl.damage_dealt_per_breed and pl.damage_dealt_per_breed[name]
            and pl.kills_per_breed and pl.kills_per_breed[name]
            and pl.kills_per_breed_persistent and pl.kills_per_breed_persistent[name]
            and pl.kill_assists_per_breed and pl.kill_assists_per_breed[name]
            and pl.kills_per_breed_difficulty and pl.kills_per_breed_difficulty[name]) then
        return "StatisticsDefinitions per-breed seeds incomplete"
    end
    if pl.kills_per_breed_persistent[name].name ~= name then
        return "kills_per_breed_persistent entry missing `name` leaf marker"
    end
    local nl = rawget(_G, "NetworkLookup")
    if not (nl and nl.breeds and rawget(nl.breeds, name)) then
        return "NetworkLookup.breeds missing forward/reverse entry"
    end
    if not (nl.damage_sources and rawget(nl.damage_sources, name)) then
        return "NetworkLookup.damage_sources missing entry (AI melee damage_source = breed name)"
    end
    local epls = rawget(_G, "EnemyPackageLoaderSettings")
    if not (epls and epls.alias_to_breed
            and epls.alias_to_breed[name] == "skaven_storm_vermin_champion") then
        return "EnemyPackageLoaderSettings.alias_to_breed missing — spawn would request a nonexistent package"
    end
    if not (rawget(_G, "BreedActions") and BreedActions[name]) then
        return "BreedActions clone missing"
    end
    local dis = rawget(_G, "Dismemberments")
    if not (dis and dis[name]) then
        return "Dismemberments entry missing — unguarded index at generic_hit_reaction_extension.lua:544 would crash"
    end
    local gmn = rawget(_G, "GrudgeMarkedNames")
    local glist = gmn and gmn[name]
    if type(glist) ~= "table" or #glist < 10 then
        return "GrudgeMarkedNames[et_skaven_warlord] missing or short (" .. tostring(glist and #glist) .. ")"
    end
    if not mod._et_warlord2_localize_hooked then
        return "_G.Localize hook not installed — grudge names / display name unresolvable by vanilla"
    end
    local strings = mod._et_warlord2_loc_strings
    if not (type(strings) == "table" and strings[glist[1]] and strings["et_skaven_warlord_name"]) then
        return "warlord loc strings table incomplete (display name / first grudge key)"
    end
end)

rt_register("warlord_spawn_allies_guard", function()
    -- v0.7.16-dev: verifies the off-arena BTSpawnAllies guard's hook target +
    -- the spawner_system lookup field it inspects still exist.
    if type(rawget(_G, "BTSpawnAllies")) ~= "table"
            or type(BTSpawnAllies.find_spawn_point) ~= "function" then
        return "BTSpawnAllies.find_spawn_point missing — warlord spawn-allies guard target absent"
    end
end)

rt_register("champion_elite_swap_consolidated", function()
    -- v0.7.18-dev: the Champion roaming-elite swap SHARES the spawn_queued_unit
    -- hook with the Warlord swap (single-hook-per-Class.method invariant). Verify
    -- the shared hook target, the Champion breed, the eligibility table, and the
    -- breed-override apply function are all present.
    if type(rawget(_G, "ConflictDirector")) ~= "table"
            or type(ConflictDirector.spawn_queued_unit) ~= "function" then
        return "ConflictDirector.spawn_queued_unit missing — consolidated swap hook target absent"
    end
    if not (rawget(_G, "Breeds") and Breeds[_CHAMPION_BREED]) then
        return "Breeds.skaven_storm_vermin_champion missing — Champion breed not registered"
    end
    if type(_CHAMPION_ELIGIBLE_ELITES) ~= "table" or not _CHAMPION_ELIGIBLE_ELITES.skaven_storm_vermin then
        return "_CHAMPION_ELIGIBLE_ELITES table missing or empty"
    end
    if type(_apply_champion_breed_overrides) ~= "function" then
        return "_apply_champion_breed_overrides missing"
    end
end)
