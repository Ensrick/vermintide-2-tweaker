-- Issue #659: bounded, observation-only Raise Dead trace for the keep.
--
-- Log #940 falsified the original hub-ban hypothesis: both passive lifecycle
-- hooks ran for the local human, but `_pets_forbidden_in_level` was nil before
-- and after. The same log shows the career-skill weapon being wielded four
-- times and no pet reaching the existing ConflictDirector queue probe. Vanilla
-- has one conditional boundary before PassiveAbilityNecromancerCharges.spawn_pet:
-- ActionCareerBWNecromancerRaiseDeadTargeting.finish enters the spawn branch
-- only for a valid nav target, the interrupt reason `new_interupting_action`,
-- and sub-action `spawn_summon_area`.
--
-- These four hooks observe that exact activation -> target -> passive -> server
-- chain. They mutate no game state, run only for a local human in a hub, and
-- have independent per-phase caps so a held targeting action cannot spam logs.
-- luacheck: globals Managers printf

local mod = get_mod("gt_dev")
local core = mod:dofile(
    "scripts/mods/general_tweaker_dev/_gt_necro_keep_trace_core")
local trace = core.new()

mod._gt_necro_keep_trace_core = core
mod._gt_necro_keep_trace_state = trace

local function _safe_call(fn)
    local ok, value = pcall(fn)
    return ok and value or nil
end


local function _in_hub()
    local manager = Managers and Managers.level_transition_handler
    return manager and manager.in_hub_level
        and _safe_call(function() return manager:in_hub_level() end) == true
end


local function _owner_player(owner_unit)
    local manager = Managers and Managers.player
    if not manager or not owner_unit then
        return nil
    end

    if manager.owner then
        local player = _safe_call(function() return manager:owner(owner_unit) end)
        if player then
            return player
        end
    end

    if manager.unit_owner then
        return _safe_call(function() return manager:unit_owner(owner_unit) end)
    end

    return nil
end


local function _should_trace_player(player)
    return core.should_trace(
        _in_hub(),
        player and player.local_player,
        player and player.bot_player)
end


local function _take(phase)
    local allowed, count = core.take(trace, phase)
    return allowed, count, core.LIMITS[phase]
end


local function _emit(phase, format, ...)
    local allowed, count, limit = _take(phase)
    if not allowed or not rawget(_G, "printf") then
        return
    end

    pcall(printf, "[gt:659] phase=%s sample=%d/%d " .. format,
        phase, count, limit, ...)
end


-- Duplicate-hook preflight: no other gt module owns this method.
mod:hook("ActionCareerBWNecromancerRaiseDeadTargeting", "_get_projectile_position",
    function (func, self, ...)
        local good_target, target_position = func(self, ...)
        local player = _owner_player(self and self._owner_unit)

        if _should_trace_player(player) then
            _emit("target", "good=%s position=%s nav_world=%s",
                tostring(good_target == true), tostring(target_position ~= nil),
                tostring(Managers.state and Managers.state.entity
                    and Managers.state.entity:system("ai_system") ~= nil))
        end

        return good_target, target_position
    end)


-- Post-observation is sufficient: vanilla does not mutate `_valid`, `reason`,
-- or `data`; it only destroys the decal and optionally enters the spawn branch.
mod:hook_safe("ActionCareerBWNecromancerRaiseDeadTargeting", "finish",
    function (self, reason, data)
        local player = _owner_player(self and self._owner_unit)
        if not _should_trace_player(player) then
            return
        end

        local sub_action = data and data.new_sub_action
        _emit("finish", "valid=%s reason=%s sub_action=%s decision=%s",
            tostring(self._valid == true), tostring(reason), tostring(sub_action),
            core.classify_finish(self._valid, reason, sub_action))
    end)


-- If finish says `spawn-branch`, this record proves whether the passive was
-- actually called and whether it queued work on the authoritative host.
mod:hook_safe("PassiveAbilityNecromancerCharges", "spawn_pet",
    function (self, template_name, breed_name, position, position_mode)
        if not _should_trace_player(self and self._player) then
            return
        end

        _emit("spawn_pet",
            "server=%s forbidden=%s template=%s breed=%s position=%s mode=%s queue=%d",
            tostring(self._is_server == true),
            tostring(self._pets_forbidden_in_level),
            tostring(template_name), tostring(breed_name),
            tostring(position ~= nil), tostring(position_mode),
            type(self._spawn_queue) == "table" and #self._spawn_queue or -1)
    end)


-- The return value is the nav/spawn verdict. Preserve vanilla's single return
-- exactly; this wrapper is diagnostic and never substitutes a position.
mod:hook("PassiveAbilityNecromancerCharges", "_spawn_pet_server",
    function (func, self, breed_name, position, position_mode, template_name)
        local success = func(self, breed_name, position, position_mode, template_name)

        if _should_trace_player(self and self._player) then
            _emit("spawn_server",
                "success=%s breed=%s position=%s mode=%s commander=%s nav_world=%s queued=%s",
                tostring(success == true), tostring(breed_name),
                tostring(position ~= nil), tostring(position_mode),
                tostring(self._commander_extension ~= nil),
                tostring(self._nav_world ~= nil),
                tostring(self._num_queued_pets))
        end

        return success
    end)


GT_NECRO_KEEP_TRACE_MARKER_659 = "gt-necro-activation-target-passive-server-trace"

if type(mod._gt_rt_register) == "function" then
    mod._gt_rt_register("issue659_necromancer_keep_trace_armed", function()
        local ok = GT_NECRO_KEEP_TRACE_MARKER_659
                == "gt-necro-activation-target-passive-server-trace"
            and type(mod._gt_necro_keep_trace_core) == "table"
            and type(mod._gt_necro_keep_trace_state) == "table"
            and core.LIMITS.target == 4
            and core.LIMITS.finish == 4
            and core.LIMITS.spawn_pet == 8
            and core.LIMITS.spawn_server == 8

        return ok, ok and "bounded activation-to-server trace wired"
            or "issue #659 trace wiring incomplete"
    end)
end

return core
