local mod = get_mod("gt_dev")
local Managers = Managers
local NetworkUnit = NetworkUnit
local Unit = Unit
local Actor = Actor
local ScriptUnit = ScriptUnit
local printf = printf

-- Issue #332: Max Ragdolls is a local visual preference, but vanilla adds only
-- authoritative AI units to UnitSpawner's death-watch
-- (death_reactions.lua:386-411).  The separate husk update ends after ~3 s and
-- never pushes the client corpse there (:507-522), so a client's local
-- RagdollSettings cannot retain anything.  When the host prunes its game
-- object, vanilla unconditionally destroys the matching client husk in
-- UnitSpawner.destroy_game_object_unit (unit_spawner.lua:492-507).
--
-- Snapshot that already-dead AI husk as a LOCAL visual corpse immediately
-- before either authoritative teardown route: game-object destruction, or the
-- BreedFreezer client RPC that parks/reuses common trash units.  The original
-- network unit still takes the full vanilla path.  The static clone has no
-- extensions, collision, game object, or NetworkUnit identity and lives in a
-- bounded client FIFO.  The oldest clone is queued through UnitSpawner's
-- normal deletion path when the local cap is exceeded.  This sends no RPC and
-- cannot affect the host or another peer.

local _GT332_DIAG_CAP = 8

local function _gt332_requested_cap(value)
    local count = tonumber(value) or 24
    count = math.floor(count + 0.5)
    return math.max(1, math.min(count, 300))
end

local function _gt332_should_capture(is_server, is_dead_ai, requested_cap,
        is_network_unit, matching_go_id, is_frozen, network_live,
        game_mode_ended)
    if is_server or not is_dead_ai then
        return false
    end
    if not is_network_unit or not matching_go_id or is_frozen then
        return false
    end
    if not network_live or game_mode_ended then
        return false
    end

    return _gt332_requested_cap(requested_cap) >= 1
end

mod._gt332_requested_cap = _gt332_requested_cap
mod._gt332_should_capture = _gt332_should_capture

local function _gt332_network_live()
    local state = Managers and Managers.state
    local network = state and state.network
    return network and network.game and network:game() and true or false
end

local function _gt332_game_mode_ended()
    local state = Managers and Managers.state
    local game_mode = state and state.game_mode
    return game_mode and game_mode.is_game_mode_ended
        and game_mode:is_game_mode_ended() and true or false
end

local function _gt332_diag_retained(self, count, cap, route)
    if mod._gt332_diag_spawner ~= self then
        mod._gt332_diag_spawner = self
        mod._gt332_diag_count = 0
        mod._gt332_diag_first = false
        mod._gt332_diag_cap = nil
    end

    local should_print = not mod._gt332_diag_first
        or count >= cap and mod._gt332_diag_cap ~= cap
    if not should_print or mod._gt332_diag_count >= _GT332_DIAG_CAP then
        return
    end

    mod._gt332_diag_first = true
    if count >= cap then
        mod._gt332_diag_cap = cap
    end
    mod._gt332_diag_count = mod._gt332_diag_count + 1
    printf("[MOD][gt_dev][INFO][gt:332] retained client-local corpse count=%d cap=%d route=%s sample=%d/%d",
        count, cap, tostring(route), mod._gt332_diag_count, _GT332_DIAG_CAP)
end

local function _gt332_make_visual_only(unit)
    -- Once detached from its game object, the corpse must be presentation-only:
    -- a later local weapon sweep cannot be allowed to hit a unit with no go_id.
    -- Freeze the settled pose and remove every physical actor from collision.
    Unit.disable_animation_state_machine(unit)
    for i = 1, Unit.num_actors(unit) do
        local actor = Unit.actor(unit, i)
        if actor and Actor.is_physical(actor) then
            Actor.set_kinematic(actor, true)
            Actor.set_collision_enabled(actor, false)
        end
    end
end

local _gt332_retained_by_spawner = setmetatable({}, { __mode = "k" })

local function _gt332_compact_alive(list)
    local write = 1
    for read = 1, #list do
        local unit = list[read]
        if unit and Unit.alive(unit) then
            list[write] = unit
            write = write + 1
        end
    end
    for i = write, #list do
        list[i] = nil
    end
end

local function _gt332_reconcile(spawner, cap)
    local list = _gt332_retained_by_spawner[spawner]
    if not list then
        return 0
    end

    _gt332_compact_alive(list)
    while #list > cap do
        local unit = table.remove(list, 1)
        if unit and Unit.alive(unit) then
            spawner:mark_for_deletion(unit)
        end
    end
    return #list
end

mod._gt332_reconcile_client_corpses = function()
    local state = Managers and Managers.state
    local spawner = state and state.unit_spawner
    if not spawner or spawner.is_server then
        return 0
    end
    return _gt332_reconcile(spawner,
        _gt332_requested_cap(mod:get("gt_more_corpses_count")))
end

local function _gt332_dead_ai_husk(unit)
    local health_extension = unit and ScriptUnit.has_extension(unit, "health_system")
    local breed = unit and Unit.get_data(unit, "breed")
    return health_extension and health_extension.is_alive
        and not health_extension:is_alive() and breed and not breed.is_player
        and true or false
end

local function _gt332_capture(spawner, source_unit, go_id, route)
    if not source_unit or not Unit.alive(source_unit) then
        return false
    end

    local unit_storage = spawner.unit_storage
    local is_network_unit = NetworkUnit.is_network_unit(source_unit)
    local matching_go_id = is_network_unit and unit_storage:go_id(source_unit) == go_id
    local is_frozen = Unit.is_frozen(source_unit)
    local cap = _gt332_requested_cap(mod:get("gt_more_corpses_count"))

    if not _gt332_should_capture(spawner.is_server,
            _gt332_dead_ai_husk(source_unit), cap, is_network_unit,
            matching_go_id, is_frozen, _gt332_network_live(),
            _gt332_game_mode_ended()) then
        return false
    end

    local unit_name = Unit.get_data(source_unit, "unit_name")
    if type(unit_name) ~= "string" or unit_name == "" then
        return false
    end

    local clone = spawner:spawn_local_unit(unit_name,
        Unit.world_position(source_unit, 0), Unit.world_rotation(source_unit, 0))
    Unit.copy_scene_graph_local_from(clone, source_unit)
    _gt332_make_visual_only(clone)

    local list = _gt332_retained_by_spawner[spawner]
    if not list then
        list = {}
        _gt332_retained_by_spawner[spawner] = list
    end
    list[#list + 1] = clone
    local retained_count = _gt332_reconcile(spawner, cap)
    _gt332_diag_retained(spawner, retained_count, cap, route)
    return true
end

-- Duplicate-hook pre-flight (2026-07-19): repo-wide gt_dev grep found no other
-- UnitSpawner.destroy_game_object_unit hook.  Keep this the singleton owner.
mod:hook("UnitSpawner", "destroy_game_object_unit", function(func, self, go_id, owner_id)
    local unit_storage = self.unit_storage
    local unit = unit_storage and unit_storage:unit(go_id)
    _gt332_capture(self, unit, go_id, "destroy")
    return func(self, go_id, owner_id)
end) -- hook-test: issue332_client_ragdoll_retention

-- Common trash breeds are pooled, not destroyed.  Snapshot each dead client
-- husk BEFORE vanilla copies the template pose, hides it, and parks it at the
-- freezer coordinates (breed_freezer.lua:323-378).  The RPC and every original
-- unit still pass through unchanged.
mod:hook("BreedFreezer", "rpc_breed_freeze_units", function(func, self, channel_id, unit_go_ids)
    if not self.is_server and _gt332_network_live() and not _gt332_game_mode_ended() then
        local state = Managers and Managers.state
        local spawner = state and state.unit_spawner
        local unit_storage = state and state.unit_storage
        if spawner and unit_storage and type(unit_go_ids) == "table" then
            for i = 1, #unit_go_ids do
                local go_id = unit_go_ids[i]
                _gt332_capture(spawner, unit_storage:unit(go_id), go_id, "freeze")
            end
        end
    end
    return func(self, channel_id, unit_go_ids)
end) -- hook-test: issue332_client_ragdoll_retention

if type(mod._gt_rt_register) == "function" then
    mod._gt_rt_register("issue332_client_ragdoll_retention", function()
        -- Runner contract: nil == PASS, a reason string == FAIL (issue #1153).
        -- The prior body returned the conjunction itself, so a healthy gate
        -- scored "FAIL -- true" and a broken one scored "FAIL -- false" with no
        -- indication of which clause gave way.
        if not mod._gt332_should_capture(false, true, 24,
                true, true, false, true, false) then
            return "client dead-AI husk capture refused on the eligible client case"
        end
        if mod._gt332_should_capture(true, true, 24,
                true, true, false, true, false) then
            return "capture gate opened on the server (host must take the vanilla path)"
        end
        if mod._gt332_should_capture(false, false, 24,
                true, true, false, true, false) then
            return "capture gate opened for a live (non-dead-AI) unit"
        end
    end)
end
