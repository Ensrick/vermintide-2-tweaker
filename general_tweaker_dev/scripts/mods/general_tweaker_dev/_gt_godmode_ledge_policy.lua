local Policy = {}

-- A ledge interception is safe only for the owning local human while Godmode
-- is active and vanilla has positively identified a ledge.  Requiring a
-- recovery position is deliberate: returning false without relocating the
-- player would merely replace ledge hanging with an uncontrolled fall.
function Policy.should_restore(vanilla_is_ledge, godmode_active, is_local_unit, recovery_position)
    return vanilla_is_ledge == true
        and godmode_active == true
        and is_local_unit == true
        and recovery_position ~= nil
end

function Policy.choose_recovery_position(last_onground_position, last_navmesh_position)
    return last_onground_position or last_navmesh_position
end

return Policy
