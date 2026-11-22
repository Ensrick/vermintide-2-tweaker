local mod = get_mod("gt_dev")

-- _gt_engine_guards.lua - the one owner of gt_dev's always-on engine guards
-- (WP-GT-05, audit finding A6-F03).
--
-- These hooks change engine behaviour for the whole game, not just gt_dev:
-- with gt_dev loaded a missing unit package in ANY mod became an invisible
-- unit instead of a crash, and nothing recorded that it happened. Every guard
-- now (1) counts each firing in mod._gt_guard_counts[name], (2) logs its first
-- firing as `[gt:guard] <name> fired detail=<detail>` (engine printf), and
-- (3) passes straight through to the original when the switch is off, so the
-- rig can test other mods with the guards off. Default stays ON (GT-D4).
--
--   name                  hook                                            fires when
--   world_spawn_unit      World.spawn_unit                                the unit is not loadable
--   unit_get_data         Unit.get_data                                   unit is nil
--   unit_create_actor     Unit.create_actor                               in the keep and id == -1
--   request_breed_limits  EnemyPackageLoader.request_breed                caller did not pass ignore_breed_limits
--   update_aggro          AiUtils.update_aggro                            blackboard.aggro_list is nil
--   bt_health_nil         eight BTConditions health conditions            health field is nil
--   fog_volume            VolumetricsFlowCallbacks.unregister_fog_volume  unit is dead
--   whereabouts_no_pos    PlayerWhereaboutsExtension.update               unit has no position
--   round_start_no_pos    RoundStartedSystem._players_left_start_area     a tracked unit has no position
--   commander_no_pos      AICommanderExtension._update_units              commander has no position
--   utility_inputs        Utility.get_action_utility (stays in _gt_bot_fixes.lua, reads mod._gt_guards_on)
--
-- The hot hook bodies read the file-local `enabled`, never mod:get.
-- Loaded once from general_tweaker_dev.lua.

local enabled = mod:get("gt_engine_guards_enabled") ~= false
mod._gt_guard_counts = {}

function mod._gt_guard_fired(name, detail)
    local counts = mod._gt_guard_counts
    local count = (counts[name] or 0) + 1
    counts[name] = count
    if count == 1 then
        pcall(printf, "[gt:guard] %s fired detail=%s", tostring(name), tostring(detail))
    end
end

function mod._gt_guards_on()
    return enabled
end

function mod.gt_set_engine_guards(value)
    enabled = value and true or false
    mod:set("gt_engine_guards_enabled", enabled)
    pcall(printf, "[gt:guard] switch enabled=%s", tostring(enabled))
end

mod:command("gt_guards", "Engine guards: show state and counts; /gt_guards on|off switches them", function(arg)
    if arg == "on" then mod.gt_set_engine_guards(true) elseif arg == "off" then mod.gt_set_engine_guards(false) end
    local names, parts = {}, {}
    for name in pairs(mod._gt_guard_counts) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do parts[#parts + 1] = name .. "=" .. tostring(mod._gt_guard_counts[name]) end
    mod:echo("[gt:guard] enabled=%s counts: %s", tostring(enabled), #parts > 0 and table.concat(parts, " ") or "none")
end)

-- ----------------------------------------------------------------------------
-- From _gt_creature_spawner.lua
-- ----------------------------------------------------------------------------

-- Missing-unit guard — when a breed references a unit path that isn't in
-- any loaded package, fall back to `units/hub_elements/empty` so the
-- engine doesn't fatally fail spawn_unit. Same fallback unit upstream uses.
mod:hook(World, "spawn_unit", function(func, self, unit_name, ...)
    if not enabled then return func(self, unit_name, ...) end
    if Application.can_get("unit", unit_name) then
        return func(self, unit_name, ...)
    else
        mod._gt_guard_fired("world_spawn_unit", unit_name)
        return func(self, "units/hub_elements/empty", ...)
    end
end)

-- Prevent keep navigation crash — Unit.create_actor with id=-1 in the keep
-- crashes the engine actor allocator. Block only that exact case. The keep
-- test lives in the spawner, which loads later: resolve it at call time.
mod:hook(Unit, "create_actor", function(func, self, id, ...)
    if not enabled then return func(self, id, ...) end
    if not (mod._gt_cs_is_in_keep and mod._gt_cs_is_in_keep()) or id ~= -1 then
        return func(self, id, ...)
    end
    mod._gt_guard_fired("unit_create_actor", id)
end)

-- Force EnemyPackageLoader to ignore breed limits — the limit is what
-- normally prevents debug spawns from loading the right packages on demand.
if EnemyPackageLoader then
    mod:hook(EnemyPackageLoader, "request_breed", function(func, self, breed_name, ignore_breed_limits, ...)
        if not enabled then return func(self, breed_name, ignore_breed_limits, ...) end
        if ignore_breed_limits ~= true then mod._gt_guard_fired("request_breed_limits", breed_name) end
        return func(self, breed_name, true, ...)
    end)
end

-- Defensive aggro init — keep table guaranteed-present so update_aggro
-- doesn't index nil when an enemy spawns with no aggro_list yet.
if AiUtils then
    mod:hook(AiUtils, "update_aggro", function(func, unit, blackboard, breed, t, dt, ...)
        if not enabled then return func(unit, blackboard, breed, t, dt, ...) end
        if not blackboard.aggro_list then
            mod._gt_guard_fired("update_aggro", breed and breed.name)
            blackboard.aggro_list = {}
        end
        return func(unit, blackboard, breed, t, dt, ...)
    end)
end

-- Issue #59 secondary fix: defensive nil-guard for BTConditions.at_*_health.
-- Bias every condition that bare-compares blackboard.current_health_percent
-- against a number toward FALSE (boss has not yet hit the threshold) if the
-- field is nil; same for `less_than_one_health` (blackboard.current_health).
-- Closes a first-tick race on any boss BT between breed:run_on_spawn and the
-- first AISystem update_blackboard_health tick. Per-(breed, condition) printf
-- dedupe: BT conditions tick continuously.
local _gt_bt_health_nil_seen = {}
local function _gt_bt_health_pct_nil_guard(cond_name)
    return function(func, blackboard)
        if not enabled then return func(blackboard) end
        if blackboard and blackboard.current_health_percent == nil then
            local breed = blackboard.breed
            local bname = (breed and breed.name) or "<no-breed>"
            local key = bname .. "|" .. cond_name
            mod._gt_guard_fired("bt_health_nil", key)
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
        if not enabled then return func(blackboard) end
        if blackboard and blackboard.current_health == nil then
            local breed = blackboard.breed
            local bname = (breed and breed.name) or "<no-breed>"
            local key = bname .. "|" .. cond_name
            mod._gt_guard_fired("bt_health_nil", key)
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
    -- risk vs the spawner's transitioned_one_third_health hook (different method).
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

-- ----------------------------------------------------------------------------
-- From _gt_hacks.lua (Group F, Janoti "Hacks" port)
-- ----------------------------------------------------------------------------
-- Well-known places where vanilla code occasionally dereferences a unit that's
-- mid-cleanup, producing [Engine Error] spam or a silent fatal in long
-- sessions. Pure no-op-if-unit-dead pre-guards; the original runs normally
-- when the unit is alive.

if VolumetricsFlowCallbacks and VolumetricsFlowCallbacks.unregister_fog_volume then
    mod:hook(VolumetricsFlowCallbacks, "unregister_fog_volume", function(func, params, ...)
        if not enabled then return func(params, ...) end
        if not (params and params.unit and Unit.alive(params.unit)) then
            mod._gt_guard_fired("fog_volume", params and params.unit)
            return
        end
        return func(params, ...)
    end)
end

mod:hook(Unit, "get_data", function(func, unit, ...)
    if not enabled then return func(unit, ...) end
    if not unit then
        mod._gt_guard_fired("unit_get_data", (...))
        return
    end
    return func(unit, ...)
end)

-- AI-takeover despawn race (GUID 955c4549-7b10-4ecb-a0ce-06c1d37f9bbc, v0.2.114-dev):
-- _ai_swap_human_to_bot calls player:despawn(), which pulls the unit out of
-- POSITION_LOOKUP. PlayerWhereaboutsExtension.update can still tick once before
-- its teardown completes; vanilla does `local pos = POSITION_LOOKUP[unit]`
-- (player_whereabouts_extension.lua:67) then feeds pos to _get_closest_positions
-- -> GwNavQueries.triangle_from_position (decompile :214, runtime :200), whose
-- arg #2 is userdata-required -> hard engine crash on nil. A positionless unit
-- has nothing to track this frame, so skip the whole update. One class covers
-- local + husk + bot player units. `...` preserves input/dt/context/t.
mod:hook("PlayerWhereaboutsExtension", "update", function(func, self, unit, ...)
    if not enabled then return func(self, unit, ...) end
    if not (unit and Unit.alive(unit) and POSITION_LOOKUP[unit]) then
        mod._gt_guard_fired("whereabouts_no_pos", unit)
        return
    end
    return func(self, unit, ...)
end)

-- Same AI-takeover despawn race, SECOND site (GUID 6fac3e46-84ce-458d-b70f-fb87bf3ad940,
-- v0.2.115-dev): RoundStartedSystem._players_left_start_area reads
-- `pos = POSITION_LOOKUP[unit]` (round_started_system.lua:117) then
-- `Level.is_point_inside_volume(level, volume_name, pos)` (:119) with no nil-guard.
-- If ANY tracked unit lacks a position this frame, bail (return false = "round not
-- started yet"); the despawned unit drops out of self._units within a tick.
mod:hook("RoundStartedSystem", "_players_left_start_area", function(func, self)
    if not enabled then return func(self) end
    for unit in pairs(self._units or {}) do
        if not POSITION_LOOKUP[unit] then
            mod._gt_guard_fired("round_start_no_pos", unit)
            return false
        end
    end
    return func(self)
end)

-- ----------------------------------------------------------------------------
-- From general_tweaker_dev.lua: AI Commander crash guard (host)
-- ----------------------------------------------------------------------------
-- CRITICAL host crash (2026-06-19): a CLIENT using AI Takeover hard-crashed the
-- host with `ai_commander_extension.lua: bad argument #1 to '__add' (userdata
-- expected, got nil)`. AICommanderExtension._update_units reads
-- `local commander_unit_pos = POSITION_LOOKUP[self._unit]` and later adds a
-- Vector3 to it; vanilla guards the CONTROLLED unit's position but not the
-- commander's own. AI Takeover despawns/recreates a player unit mid-frame, so a
-- commander can be left without a POSITION_LOOKUP entry for a tick. Skip the
-- tick until the commander has a position again. Host-side (only the server
-- ticks AI extensions).
if rawget(_G, "AICommanderExtension") then
    mod:hook("AICommanderExtension", "_update_units", function(func, self, dt, t)
        if not enabled then return func(self, dt, t) end
        if not POSITION_LOOKUP[self._unit] then
            mod._gt_guard_fired("commander_no_pos", self._unit)
            return
        end
        return func(self, dt, t)
    end)
end
