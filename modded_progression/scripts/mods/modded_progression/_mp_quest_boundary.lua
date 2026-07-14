-- Pure realm router for Modded Progression's quest read/refresh surface.
-- Engine-free so official pass-through and zero-backend modded behavior can be
-- proved under the repository's Lua 5.1 test harness.
local M = {}

function M.surface(is_modded, local_daily, vanilla_get)
    if not is_modded then return vanilla_get() end
    return {
        daily = local_daily(),
        weekly = {},
        event = {},
    }
end

function M.refresh(is_modded, ensure_local, updated_cb, vanilla_update)
    if not is_modded then return vanilla_update(updated_cb) end
    ensure_local()
    if updated_cb then updated_cb() end
    return nil
end

return M
