-- Issue #601: general Greataxe / Dual Axes identity policies owned by WT.
-- Engine-free; the optional CWV Greataxe template is simply skipped when absent.
local M = {}

M.GREATAXE_LIGHT_CRIT_SETTING = "wt_greataxe_light_crit"
M.DUAL_AXES_LIGHT_CRIT_SETTING = "wt_dual_axes_light_crit"
M.DUAL_AXES_CLEAVE_SETTING = "wt_dual_axes_cleave"
M.LIGHT_CRIT_FLOOR = 0.10
M.CLEAVE_MULT = 1.10
M.GREATAXE_TEMPLATES = { "two_handed_axes_template_1", "cwv_greataxe_template" }
M.DUAL_AXES_TEMPLATES = { "dual_wield_axes_template_1" }

local function each_sub_action(template, fn)
    for _, group in pairs((template and template.actions) or {}) do
        if type(group) == "table" then
            for name, action in pairs(group) do
                if type(action) == "table" then fn(name, action) end
            end
        end
    end
end

local function is_light(name, action)
    return action.kind == "sweep" and type(name) == "string"
        and name:find("light_attack_", 1, true) == 1
end

local function is_direct(action)
    return action.kind == "sweep" and (type(action.damage_profile) == "string"
        or type(action.damage_profile_left) == "string"
        or type(action.damage_profile_right) == "string")
end

local function scale_cleave(value, power_levels, clone, generated_key)
    if type(value) == "string" then
        local source = power_levels and power_levels[value]
        if type(source) ~= "table" then return value end
        local key = generated_key .. "_" .. value
        if not power_levels[key] then
            local copy = clone(source)
            if type(copy.attack) == "number" then copy.attack = copy.attack * M.CLEAVE_MULT end
            if type(copy.impact) == "number" then copy.impact = copy.impact * M.CLEAVE_MULT end
            power_levels[key] = copy
        end
        return key
    elseif type(value) == "table" then
        if type(value.attack) == "number" then value.attack = value.attack * M.CLEAVE_MULT end
        if type(value.impact) == "number" then value.impact = value.impact * M.CLEAVE_MULT end
    end
    return value
end

function M.new()
    local state = {
        greataxe_crit_enabled = false, dual_crit_enabled = false,
        dual_cleave_enabled = false, greataxe_crit_originals = {},
        dual_crit_originals = {}, dual_profile_originals = {}, generated_profiles = {},
    }

    local function apply_crit(self, enabled, weapons, keys, originals, flag)
        enabled = not not enabled
        if not enabled and enabled == self[flag] then return end
        if enabled then
            for _, key in ipairs(keys) do
                each_sub_action(weapons and weapons[key], function(name, action)
                    if is_light(name, action) and not originals[action] then
                        originals[action] = { had_value = action.additional_critical_strike_chance ~= nil,
                            value = action.additional_critical_strike_chance }
                        action.additional_critical_strike_chance = math.max(
                            action.additional_critical_strike_chance or 0, M.LIGHT_CRIT_FLOOR)
                    end
                end)
            end
        else
            for action, original in pairs(originals) do
                action.additional_critical_strike_chance = original.had_value and original.value or nil
            end
            for action in pairs(originals) do originals[action] = nil end
        end
        self[flag] = enabled
    end

    function state:apply_greataxe_crit(enabled, weapons)
        apply_crit(self, enabled, weapons, M.GREATAXE_TEMPLATES,
            self.greataxe_crit_originals, "greataxe_crit_enabled")
    end
    function state:apply_dual_crit(enabled, weapons)
        apply_crit(self, enabled, weapons, M.DUAL_AXES_TEMPLATES,
            self.dual_crit_originals, "dual_crit_enabled")
    end
    function state:_profile(source_name, profiles, power_levels, clone)
        if self.generated_profiles[source_name] then return self.generated_profiles[source_name] end
        local source = profiles and profiles[source_name]
        if type(source) ~= "table" then return source_name end
        local key = "wt_axe_cleave_" .. source_name
        if not profiles[key] then
            local copy = clone(source)
            copy.cleave_distribution = scale_cleave(copy.cleave_distribution, power_levels, clone, key)
            profiles[key] = copy
        end
        self.generated_profiles[source_name] = key
        return key
    end
    function state:apply_dual_cleave(enabled, weapons, profiles, power_levels, clone, register)
        enabled = not not enabled
        if not enabled and enabled == self.dual_cleave_enabled then return end
        if enabled then
            for _, key in ipairs(M.DUAL_AXES_TEMPLATES) do
                each_sub_action(weapons and weapons[key], function(_, action)
                    if is_direct(action) and not self.dual_profile_originals[action] then
                        local originals = {}
                        for _, field in ipairs({ "damage_profile", "damage_profile_left", "damage_profile_right" }) do
                            local source = action[field]
                            if type(source) == "string" then
                                originals[field] = source
                                action[field] = self:_profile(source, profiles, power_levels, clone)
                                if register then register(action[field]) end
                            end
                        end
                        self.dual_profile_originals[action] = originals
                    end
                end)
            end
        else
            for action, originals in pairs(self.dual_profile_originals) do
                for field, source in pairs(originals) do action[field] = source end
            end
            self.dual_profile_originals = {}
        end
        self.dual_cleave_enabled = enabled
    end
    return state
end

return M
