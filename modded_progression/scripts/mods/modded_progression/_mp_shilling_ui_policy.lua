-- Engine-free policy for issue #578's realm-scoped Silver Shilling UI.

local M = {}

M.OFFICIAL_REVISION = -1

function M.visible_revision(is_modded, local_revision)
    if not is_modded then return M.OFFICIAL_REVISION end
    return tonumber(local_revision) or 0
end

function M.needs_refresh(previous_realm, previous_revision, is_modded, local_revision)
    local visible = M.visible_revision(is_modded, local_revision)
    return previous_realm ~= is_modded or previous_revision ~= visible, visible
end

function M.is_local_shilling(is_modded, currency_code)
    return is_modded == true and currency_code == "SM"
end

return M
