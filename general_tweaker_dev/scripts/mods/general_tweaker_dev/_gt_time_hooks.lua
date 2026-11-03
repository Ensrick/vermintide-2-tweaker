-- _gt_time_hooks.lua - singleton dispatch for selective world freeze.
--
-- Movement runs only in the native entity update phases. The existing spawner
-- owns StateIngame.update; its shared wrapper below preserves transition values
-- and nil holes. These four additional targets had no prior General owner.
-- Owned by: general_tweaker_dev.lua manifest, after _gt_time_control.lua.
local mod = get_mod("gt_dev")
local outer_dt = assert(mod._gt_time_outer_dt)
local entity_phase = assert(mod._gt_time_entity_phase)
local before_join = assert(mod._gt_time_before_hotjoin)
local after_join = assert(mod._gt_time_after_hotjoin)

local function after_result(after, ...)
    after()
    return ...
end
mod._gt_time_state_update = function(func, state, dt, after, ...)
    return after_result(after, func(state, outer_dt(state, "update", dt), ...))
end

-- StateIngame.pre_update/post_update feed outer gameplay managers epsilon while
-- the world/game timer is held; main/UI clocks remain at normal speed.
mod:hook("StateIngame", "pre_update", function(func, self, dt, ...)
    return func(self, outer_dt(self, "pre_update", dt), ...)
end)
mod:hook("StateIngame", "post_update", function(func, self, dt, ...)
    return func(self, outer_dt(self, "post_update", dt), ...)
end)
mod:hook("EntitySystem", "system_update", function(func, self, phase, dt, ...)
    if entity_phase(self, phase, dt) then return end
    return func(self, phase, dt, ...)
end)

-- Native hot_join_sync removes the peer from ignored_peers at its end. Release
-- the solo-only freeze BEFORE admission, then replay host-selected speed AFTER
-- native synchronization. Never block native peer admission or its return shape.
local function after_join_result(...)
    after_join()
    return ...
end
mod:hook("GameNetworkManager", "hot_join_sync", function(func, self, ...)
    before_join()
    return after_join_result(func(self, ...))
end)

mod._gt_time_hooks_armed = true

mod.on_unload = function()
    if mod._gt_time_disable then mod._gt_time_disable("mod_unload") end
end
