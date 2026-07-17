-- Pure consumer for CWV's optional Combat Style template-name contract.
--
-- WT owns cross-character third-person remap selection, but CWV owns style
-- identity and donor-template selection.  Keep that knowledge on the provider:
-- this adapter accepts only a registered template name and otherwise preserves
-- the native ItemMasterList template.  It performs no style inference.
local M = {}

function M.resolve(item_data, cwv, weapons, owner_unit, slot_name)
    local fallback = type(item_data) == "table" and item_data.template or nil
    if type(cwv) ~= "table" then return fallback end

    if type(cwv.is_enabled) == "function" then
        local ok, enabled = pcall(cwv.is_enabled, cwv)
        if not ok or enabled ~= true then return fallback end
    end

    local resolver = cwv.get_effective_combat_style_template_name
    if type(resolver) ~= "function" then return fallback end

    local backend_id = item_data and (item_data.backend_id or item_data.ItemId)
    local ok, template_name = pcall(resolver, item_data, backend_id, owner_unit, slot_name)
    if not ok or type(template_name) ~= "string" or template_name == "" then
        return fallback
    end
    if type(weapons) ~= "table" or rawget(weapons, template_name) == nil then
        return fallback
    end
    return template_name
end

return M
