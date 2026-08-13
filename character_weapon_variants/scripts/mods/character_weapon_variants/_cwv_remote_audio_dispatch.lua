-- _cwv_remote_audio_dispatch.lua -- executable pre-RPC animation dispatch.
--
-- WeaponUnitExtension._play_3p_anim owns both the local third-person event and
-- vanilla's rpc_anim_event_variable_float send.  Cross-character remaps must
-- therefore substitute the receiver-native event before delegating to vanilla.
-- Keep this boundary engine-free so the in-mod regression suite and offline
-- Lua tests execute the same delegation decision as the live hook (#398).

local M = {}

function M.invoke(func, self, event_3p, event, owner_unit, looping_event,
        anim_time_scale, local_body_unit, before_resolve, resolve_target,
        lookup_target, on_applied, on_declined)
    if local_body_unit == nil or owner_unit ~= local_body_unit then
        return func(self, event_3p, event, owner_unit, looping_event,
            anim_time_scale)
    end

    if before_resolve then
        before_resolve(event_3p)
    end
    local target = resolve_target and resolve_target(event_3p) or nil
    if not target then
        return func(self, event_3p, event, owner_unit, looping_event,
            anim_time_scale)
    end

    local target_id = lookup_target and lookup_target(target) or nil
    if target_id == nil then
        if on_declined then
            on_declined(event_3p, target)
        end
        return func(self, event_3p, event, owner_unit, looping_event,
            anim_time_scale)
    end

    if on_applied then
        on_applied(event_3p, target, target_id)
    end
    return func(self, target, event, owner_unit, looping_event,
        anim_time_scale)
end

return M
