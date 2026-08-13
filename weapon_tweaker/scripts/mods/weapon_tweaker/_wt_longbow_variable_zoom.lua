-- _wt_longbow_variable_zoom.lua
--
-- Restores the Empire Longbow's authored variable-zoom control for the exact
-- cross-career set in issue #316. Vanilla still owns base aim, the camera,
-- thresholds, and native Huntsman cycling; this adapter only supplies the
-- missing owner-local capability decision after ActionAim's normal update.

local M = {}

local TARGET_ITEM = "es_longbow"
local TARGET_TEMPLATE = "longbow_empire_template"
local SUPPORTED_CAREERS = {
    es_mercenary = true,
    es_knight = true,
    es_questingknight = true,
    wh_captain = true,
    wh_bountyhunter = true,
    wh_zealot = true,
}
local target_actions = setmetatable({}, { __mode = "k" })

local function _aim_action(template)
    return template
        and template.actions
        and template.actions.action_two
        and template.actions.action_two.default
end

local function _extension(unit, name, env)
    if env and env.get_extension then
        return env.get_extension(unit, name)
    end
    local script_unit = rawget(_G, "ScriptUnit")
    if not script_unit or type(script_unit.has_extension) ~= "function" then
        return nil
    end
    return script_unit.has_extension(unit, name)
end

local function _career_name(owner_unit, env)
    if env and env.get_career_name then
        return env.get_career_name(owner_unit)
    end
    local career = _extension(owner_unit, "career_system", env)
    if career and type(career.career_name) == "function" then
        local ok, name = pcall(career.career_name, career)
        if ok then return name end
    end
    local inventory = _extension(owner_unit, "inventory_system", env)
    return inventory and inventory._career_name or nil
end

function M.register_template(template)
    local action = _aim_action(template)
    if type(action) ~= "table"
            or action.kind ~= "aim"
            or type(action.buffed_zoom_thresholds) ~= "table"
            or #action.buffed_zoom_thresholds < 2 then
        return false
    end
    target_actions[action] = true
    return true
end

function M.register_templates(weapons)
    local template = weapons and rawget(weapons, TARGET_TEMPLATE)
    M.registered_count = M.register_template(template) and 1 or 0
    return M.registered_count
end

function M.is_registered(action)
    return target_actions[action] == true
end

function M.is_supported_item_career(item_name, career_name)
    return item_name == TARGET_ITEM and SUPPORTED_CAREERS[career_name] == true
end

function M.post_update(action_aim, env)
    local action = action_aim and action_aim.current_action
    if not M.is_registered(action) then return "not_target_action" end

    local career_name = _career_name(action_aim.owner_unit, env)
    if not M.is_supported_item_career(action_aim.item_name, career_name) then
        return "not_supported_item_career"
    end

    local buff = action_aim.buff_extension
        or _extension(action_aim.owner_unit, "buff_system", env)
    if not buff or type(buff.has_buff_perk) ~= "function" then
        return "extensions_unavailable"
    end
    local perk_ok, has_native_perk = pcall(
        buff.has_buff_perk, buff, "increased_zoom")
    if not perk_ok then
        return "extensions_unavailable"
    end
    if has_native_perk then
        return "native_perk"
    end
    if action_aim.zoom_condition_function
            and not action_aim.zoom_condition_function() then
        return "inactive"
    end

    local status = _extension(action_aim.owner_unit, "status_system", env)
    local input = _extension(action_aim.owner_unit, "input_system", env)
    if not status or not input
            or type(status.is_zooming) ~= "function"
            or type(status.switch_variable_zoom) ~= "function"
            or type(input.get) ~= "function" then
        return "extensions_unavailable"
    end
    if not status:is_zooming() or not input:get("action_three") then
        return "inactive"
    end

    status:switch_variable_zoom(action.buffed_zoom_thresholds)
    return "switched"
end

function M.install(mod, weapons, post_update_observer)
    M.register_templates(weapons)
    mod:hook_safe("ActionAim", "client_owner_post_update", function(self, dt, t)
        local ok, outcome = pcall(M.post_update, self)
        if not ok then outcome = "observer_error" end
        local observer = post_update_observer or mod._wt316_post_update_observer
        if observer then
            pcall(observer, self, dt, t, outcome)
        end
    end)
    return M
end

M.target_item = TARGET_ITEM
M.target_template = TARGET_TEMPLATE
M.supported_careers = SUPPORTED_CAREERS

return M
