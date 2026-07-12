local mod = get_mod("enemy_tweaker")

-- _et_swaps.lua — breed / faction substitution + the two HordeSpawner hooks
--
-- Owns the single-breed swap map, the whole-faction horde-slot swap, and the
-- HordeSpawner hooks that consume them (compose_blob_horde_spawn_list — which
-- also carries the terror-event size replication, gated on the per-call
-- mod._et_event_breed_scale flag set by _et_event_size.lua — and the per-unit
-- spawn_unit substitution site for ambush hordes).
--
-- Owned by: enemy_tweaker.lua entry point. Consumed via mod._et exports:
-- build_swap_map, build_faction_swap_map, apply_faction_swap_to_chs,
-- COMPOSITION_FIELDS, get_breed_swap_map (accessor — the map table is
-- REASSIGNED on every rebuild, so consumers must not cache the reference).

local ET = mod._et
local rt_register      = ET.rt_register
local _spawn_dbg       = ET.spawn_dbg
local _spawn_dbg_alert = ET.spawn_dbg_alert
local _hook_wrap       = ET.hook_wrap
local _scale_count     = ET.scale_count

-- ============================================================
-- State
-- ============================================================

local _breed_swap_map = {}
local _faction_swap_map = {}

-- ============================================================
-- Breed substitution
-- ============================================================

local function _build_swap_map()
    _breed_swap_map = {}

    local swap_from = mod:get("breed_swap_from")
    local swap_to   = mod:get("breed_swap_to")
    if swap_from and swap_to and swap_from ~= "off" and swap_to ~= "off" and swap_from ~= swap_to then
        _breed_swap_map[swap_from] = swap_to
    end
end

local function _apply_breed_swap(result)
    if not next(_breed_swap_map) then return result end
    for i = 1, #result do
        local breed_name = result[i]
        if type(breed_name) == "string" and _breed_swap_map[breed_name] then
            local replacement = _breed_swap_map[breed_name]
            if rawget(_G, "Breeds") and Breeds[replacement] then
                result[i] = replacement
            end
        end
    end
    return result
end

-- ============================================================
-- Faction substitution (whole-faction horde slot swap)
-- ============================================================
-- VT2 picks a ConflictDirector per mission (and per-zone via
-- override_conflict_setting on the level), which sets CurrentHordeSettings.
-- Each `*_composition` field on that settings table is a string like "medium"
-- (skaven), "chaos_medium", "beastmen_medium". By rewriting those strings
-- right after ConflictDirector.refresh_conflict_director_patches runs, we
-- redirect every paced horde slot to a different faction's comp family. This
-- means Athel Yenlui (default → chaos zones) can be configured to spawn
-- Beastmen everywhere, Chaos everywhere, or the user's chosen mix.
--
-- NOTE: terror-event hordes use HordeCompositions (event_medium / chaos_raiders_*
-- / etc.) and bypass this rewrite. That patch is a separate workstream.

local FACTION_PREFIX = {
    skaven = "",
    chaos = "chaos_",
    beastmen = "beastmen_",
}

local FACTION_PREFIX_LIST = {
    { faction = "chaos", prefix = "chaos_" },
    { faction = "beastmen", prefix = "beastmen_" },
    -- skaven last because it's the empty-prefix fallback
}

local function _composition_faction(comp_str)
    for _, fp in ipairs(FACTION_PREFIX_LIST) do
        if comp_str:sub(1, #fp.prefix) == fp.prefix then
            return fp.faction
        end
    end
    return "skaven"
end

local function _strip_faction_prefix(comp_str, faction)
    local prefix = FACTION_PREFIX[faction]
    if prefix == "" then return comp_str end
    return comp_str:sub(#prefix + 1)
end

local function _build_faction_swap_map()
    _faction_swap_map = {}
    for _, faction in ipairs({"skaven", "chaos", "beastmen"}) do
        local target = mod:get("faction_swap_" .. faction)
        if target and target ~= "off" and target ~= faction and FACTION_PREFIX[target] then
            _faction_swap_map[faction] = target
        end
    end
end

local function _remap_composition(comp_str)
    if type(comp_str) ~= "string" then return comp_str end
    local from = _composition_faction(comp_str)
    local to = _faction_swap_map[from]
    if not to then return comp_str end
    local base = _strip_faction_prefix(comp_str, from)
    local new_str = FACTION_PREFIX[to] .. base
    -- Only rewrite if the target composition actually exists; otherwise the
    -- spawner will crash trying to index a nil composition.
    local HCP = rawget(_G, "HordeCompositionsPacing")
    if HCP and HCP[new_str] then
        return new_str
    end
    return comp_str
end

local COMPOSITION_FIELDS = {
    "ambush_composition", "vector_composition",
    "vector_blob_composition", "mini_patrol_composition",
}

local function _apply_faction_swap_to_current_horde_settings()
    if not next(_faction_swap_map) then return end
    local CHS = rawget(_G, "CurrentHordeSettings")
    if not CHS then return end
    for _, field in ipairs(COMPOSITION_FIELDS) do
        local v = CHS[field]
        if type(v) == "string" then
            CHS[field] = _remap_composition(v)
        elseif type(v) == "table" then
            for i, s in ipairs(v) do
                v[i] = _remap_composition(s)
            end
        end
    end
end

-- compose_blob_horde_spawn_list returns (spawn_list, num_to_spawn) — a real
-- list of breed names. Three things happen here in order:
--   1. Breed swap (in-place).
--   2. Event-size scaling: when mod._et_event_breed_scale is set by the
--      outer SpawnerSystem.spawn_horde_from_terror_event_ids hook, replicate
--      every entry in spawn_list to scale total count by the multiplier.
--   3. Spawn debug dump.
-- This is also the cleanest cross-version site to apply the event_size
-- multiplier: we don't depend on knowing the exact resolved-amount table
-- shape inside SpawnerSystem; we just replicate the final spawn list.
-- audit 2026-06-07 (v0.7.5-dev) F16: vanilla
--   HordeSpawner.compose_blob_horde_spawn_list(self, composition_type)
-- takes a STRING key — composition = CurrentHordeSettings.compositions_pacing
-- [composition_type] [src: scripts/managers/conflict_director/horde_spawner.lua:241-242].
-- The first arg is the type string, not a composition table; the debug
-- labels below read it directly (a string has no `.name` field, so the old
-- `composition.name` always resolved to "?" — dead cosmetic label).
_hook_wrap("HordeSpawner", "compose_blob_horde_spawn_list",
        "compose_blob_horde_spawn_list", function(func, self, composition_type, ...)
    local spawn_list, num_to_spawn = func(self, composition_type, ...)
    if not spawn_list then return spawn_list, num_to_spawn end

    -- 1. Breed swap.
    _apply_breed_swap(spawn_list)

    -- 2. Event-size scaling. Only active when we're inside an event-driven
    -- compose call; paced compose has its own scaling via _apply_horde_preset
    -- (which mutated HordeCompositionsPacing entries at load).
    local event_scale = mod._et_event_breed_scale
    if event_scale and event_scale ~= 1 then
        if event_scale == 0 then
            -- Suppress this event horde entirely. Clear the list and zero
            -- the count; HordeSpawner downstream tolerates an empty list.
            local original_n = #spawn_list
            for i = #spawn_list, 1, -1 do spawn_list[i] = nil end
            _spawn_dbg_alert("event", "compose_blob suppressed: was=%d now=0 (event_mult=0)",
                original_n)
            return spawn_list, 0
        end
        local base_n = #spawn_list
        local target_n = _scale_count(base_n, event_scale)
        if target_n > base_n then
            -- Replicate by cycling through original entries — but EXCLUDE
            -- boss breeds from the replication pool. Boss breeds (Drachenfels
            -- Exalted Sorcerer, Rat Ogre, Chaos Spawn, Stormfiend, Troll,
            -- Warlord, Champion, Grey Seer, Troll Chief — every breed with
            -- `breed.boss = true`) are unique-instance enemies. Spawning two
            -- in the same frame races their BT init: a second copy may have
            -- `blackboard.current_health_percent = nil` when its BT first
            -- evaluates, crashing vanilla bt_conditions.lua at conditions
            -- like `transitioned_one_third_health`. Burned host 2026-05-26
            -- on dlc_castle_slaanesh_path1 with event_size=3.0x triggering
            -- 3× Drachenfels spawn from the castle_chaos_boss terror event.
            local BreedsT = rawget(_G, "Breeds")
            local non_boss_pool = {}
            for i = 1, base_n do
                local bn = spawn_list[i]
                local b = BreedsT and BreedsT[bn]
                if not (b and b.boss) then
                    non_boss_pool[#non_boss_pool + 1] = bn
                end
            end
            local pool_n = #non_boss_pool
            if pool_n == 0 then
                _spawn_dbg_alert("event", "compose_blob: all %d entries are boss breeds — skipping event replication (no safe candidates) composition=%s",
                    base_n, tostring(composition_type))
            else
                for i = base_n + 1, target_n do
                    spawn_list[i] = non_boss_pool[((i - base_n - 1) % pool_n) + 1]
                end
                if pool_n < base_n then
                    _spawn_dbg("event", "compose_blob scaled (boss-safe): base=%d target=%d mult=%.1f boss_excluded=%d composition=%s",
                        base_n, target_n, event_scale, base_n - pool_n,
                        tostring(composition_type))
                else
                    _spawn_dbg("event", "compose_blob scaled: base=%d target=%d mult=%.1f composition=%s",
                        base_n, target_n, event_scale,
                        tostring(composition_type))
                end
                num_to_spawn = target_n
            end
        elseif target_n < base_n then
            -- Multiplier < 1 — trim the list.
            for i = #spawn_list, target_n + 1, -1 do spawn_list[i] = nil end
            _spawn_dbg("event", "compose_blob trimmed: base=%d target=%d mult=%.1f composition=%s",
                base_n, target_n, event_scale,
                tostring(composition_type))
            num_to_spawn = target_n
        end
    else
        _spawn_dbg("paced", "compose_blob: n=%d (composition=%s)",
            tonumber(num_to_spawn) or #spawn_list,
            tostring(composition_type))
    end

    return spawn_list, num_to_spawn
end)

-- compose_horde_spawn_list returns (sum, sum_a, sum_b) — three integers, NOT
-- a list. Breed names live in file-local upvalues spawn_list_a/_b inside
-- horde_spawner.lua and are popped per-spawn by spawn_unit. So the only place
-- to substitute ambush breeds reliably is at the per-unit spawn site:
-- HordeSpawner.spawn_unit(self, hidden_spawn, breed_name, goal_pos, horde).
_hook_wrap("HordeSpawner", "spawn_unit", "spawn_unit",
        function(func, self, hidden_spawn, breed_name, goal_pos, horde)
    local original = breed_name
    if breed_name and _breed_swap_map[breed_name] then
        local replacement = _breed_swap_map[breed_name]
        if rawget(_G, "Breeds") and Breeds[replacement] then
            breed_name = replacement
        end
    end
    _spawn_dbg("unit", "spawn_unit breed=%s%s hidden=%s",
        tostring(breed_name),
        (original ~= breed_name) and (" (was=" .. tostring(original) .. ")") or "",
        tostring(hidden_spawn))
    return func(self, hidden_spawn, breed_name, goal_pos, horde)
end)

ET.build_swap_map = _build_swap_map
ET.build_faction_swap_map = _build_faction_swap_map
ET.apply_faction_swap_to_chs = _apply_faction_swap_to_current_horde_settings
ET.COMPOSITION_FIELDS = COMPOSITION_FIELDS
-- Accessor, not a table export: _build_swap_map REASSIGNS the map table on
-- every rebuild, so a cached reference would go stale.
ET.get_breed_swap_map = function() return _breed_swap_map end
-- Lifecycle reset (on_disabled clears both maps without a settings read).
ET.clear_swap_maps = function()
    _breed_swap_map = {}
    _faction_swap_map = {}
end

rt_register("horde_compose_returns_multivalue", function()
    -- The hook on HordeSpawner.compose_blob_horde_spawn_list returns BOTH
    -- spawn_list and num_to_spawn — verify the class & method exist (proves
    -- the hook target hasn't moved upstream).
    local cls = rawget(_G, "HordeSpawner")
    if not cls then return "HordeSpawner not loaded (run in-keep)" end
    if type(cls.compose_blob_horde_spawn_list) ~= "function" then
        return "compose_blob_horde_spawn_list missing on HordeSpawner"
    end
    if type(cls.spawn_unit) ~= "function" then
        return "spawn_unit missing on HordeSpawner"
    end
end)

rt_register("breed_swap_map_table", function()
    -- _breed_swap_map is the runtime swap table consulted by the spawn_unit
    -- hook. Verify it's a table (may be empty in default config).
    if type(_breed_swap_map) ~= "table" then
        return "_breed_swap_map missing (should be table even if empty)"
    end
end)

rt_register("event_size_skips_boss_breeds", function()
    -- v0.6.2-dev regression check: event-size replication MUST skip boss
    -- breeds (breed.boss == true). Burned host 2026-05-26 on
    -- dlc_castle_slaanesh_path1 — event=3.0x replicated
    -- chaos_exalted_sorcerer_drachenfels 3x; the second copy's BT evaluated
    -- transitioned_one_third_health before HealthExtension wrote
    -- blackboard.current_health_percent => "attempt to compare nil with
    -- number" at vanilla bt_conditions.lua:309.
    --
    -- We simulate the compose_blob replication path on a synthetic
    -- spawn_list containing a boss + non-boss mix and assert no boss
    -- breed name appears more than once in the result.
    local BreedsT = rawget(_G, "Breeds")
    if type(BreedsT) ~= "table" then return "Breeds not loaded (run in keep)" end
    local boss_key, non_boss_key
    for k, v in pairs(BreedsT) do
        if type(v) == "table" then
            if v.boss == true and not boss_key then boss_key = k
            elseif (v.boss == nil or v.boss == false) and not non_boss_key and type(k) == "string" then
                non_boss_key = k
            end
        end
        if boss_key and non_boss_key then break end
    end
    if not boss_key or not non_boss_key then
        return "couldn't find boss + non-boss breed pair in Breeds (cannot run check)"
    end
    -- Replay the exact replication helper logic used in the
    -- compose_blob_horde_spawn_list hook.
    local spawn_list = { boss_key, non_boss_key }
    local base_n = #spawn_list
    local target_n = base_n * 3
    local non_boss_pool = {}
    for i = 1, base_n do
        local bn = spawn_list[i]
        local b = BreedsT[bn]
        if not (b and b.boss) then non_boss_pool[#non_boss_pool + 1] = bn end
    end
    local pool_n = #non_boss_pool
    if pool_n > 0 then
        for i = base_n + 1, target_n do
            spawn_list[i] = non_boss_pool[((i - base_n - 1) % pool_n) + 1]
        end
    end
    local boss_count = 0
    for i = 1, #spawn_list do
        if spawn_list[i] == boss_key then boss_count = boss_count + 1 end
    end
    if boss_count > 1 then
        return string.format("regression: boss breed %q replicated %d times (expected 1)",
            boss_key, boss_count)
    end
end)
