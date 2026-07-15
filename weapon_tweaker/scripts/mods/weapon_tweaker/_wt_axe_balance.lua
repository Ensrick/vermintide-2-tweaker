-- Issues #601/#621/#622/#623: isolated Weapon Tweaks balance policies.
-- Engine-free; optional/late templates are discovered on every bounded apply.
local M = {}

M.GREATAXE_LIGHT_CRIT_SETTING = "wt_greataxe_light_crit"
M.DUAL_AXES_LIGHT_CRIT_SETTING = "wt_dual_axes_light_crit"
M.DUAL_AXES_CLEAVE_SETTING = "wt_dual_axes_cleave"
M.ONE_HAND_AXE_CLEAVE_SETTING = "wt_one_hand_axe_cleave_nerf"
M.COG_HAMMER_HEAVY_SPEED_SETTING = "wt_cog_hammer_heavy_speed_nerf"
M.MACE_SWORD_SPEED_SETTING = "wt_mace_sword_speed_nerf"
M.LIGHT_CRIT_FLOOR = 0.10
M.CLEAVE_MULT = 1.10
M.CLEAVE_NERF_MULT = 0.90
M.SLOW_TIME_MULT = 1.10
M.SLOW_ANIM_MULT = 1 / M.SLOW_TIME_MULT
M.GREATAXE_TEMPLATES = { "two_handed_axes_template_1", "cwv_greataxe_template" }
M.DUAL_AXES_TEMPLATES = { "dual_wield_axes_template_1" }
M.COG_HAMMER_TEMPLATE = "two_handed_cog_hammers_template_1"
M.MACE_SWORD_TEMPLATE = "dual_wield_hammer_sword_template"
M.COG_HAMMER_HEAVY_ACTIONS = {
    "heavy_attack_left", "heavy_attack_right",
    "heavy_attack_left_charged", "heavy_attack_right_charged",
}
M.MACE_SWORD_NERFED_ACTIONS = {
    "light_attack_left_diagonal", -- native light 1
    "light_attack_right",         -- native light 2
    "heavy_attack", "heavy_attack_2",
}

local ONE_HAND_AXE_STATE_MACHINE =
    "units/beings/player/first_person_base/state_machines/melee/1h_axe"
local PROFILE_FIELDS = { "damage_profile", "damage_profile_left", "damage_profile_right" }

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
    return (action.kind == "sweep" or action.kind == "charged_sweep")
        and (type(action.damage_profile) == "string"
        or type(action.damage_profile_left) == "string"
        or type(action.damage_profile_right) == "string")
end

-- Capability/provenance boundary for #621. All three vanilla single-axe
-- templates share this exact first-person contract. Dual Axes also report
-- weapon_type=AXE_1H, so state_machine + absent offhand are required; shield,
-- throwing, and two-handed axes carry different contracts. A WT/CWV clone that
-- preserves the donor's actual combat contract is included automatically.
function M.is_one_hand_axe_template(template)
    return type(template) == "table"
        and template.weapon_type == "AXE_1H"
        and template.buff_type == "MELEE_1H"
        and template.state_machine == ONE_HAND_AXE_STATE_MACHINE
        and template.left_hand_unit == nil
end

local function scale_cleave(value, power_levels, clone, generated_key, multiplier)
    multiplier = multiplier or M.CLEAVE_MULT
    if type(value) == "string" then
        local source = power_levels and power_levels[value]
        if type(source) ~= "table" then return value end
        local key = generated_key .. "_" .. value
        if not power_levels[key] then
            local copy = clone(source)
            if type(copy.attack) == "number" then copy.attack = copy.attack * multiplier end
            if type(copy.impact) == "number" then copy.impact = copy.impact * multiplier end
            power_levels[key] = copy
        end
        return key
    elseif type(value) == "table" then
        if type(value.attack) == "number" then value.attack = value.attack * multiplier end
        if type(value.impact) == "number" then value.impact = value.impact * multiplier end
    end
    return value
end

local function restore_speed(originals)
    for action, original in pairs(originals) do
        action.anim_time_scale = original.had_value and original.value or nil
    end
end

local function apply_action_speed(enabled, template, action_names, originals)
    restore_speed(originals)
    if not enabled or type(template) ~= "table" then return end
    local actions = template.actions and template.actions.action_one
    if type(actions) ~= "table" then return end
    for _, name in ipairs(action_names) do
        local action = actions[name]
        if type(action) == "table" then
            if not originals[action] then
                originals[action] = {
                    had_value = action.anim_time_scale ~= nil,
                    value = action.anim_time_scale,
                }
            end
            local original = originals[action]
            action.anim_time_scale = (original.value or 1) * M.SLOW_ANIM_MULT
        end
    end
end

function M.new()
    local state = {
        greataxe_crit_enabled = false, dual_crit_enabled = false,
        dual_cleave_enabled = false, greataxe_crit_originals = {},
        dual_crit_originals = {}, dual_profile_originals = {}, generated_profiles = {},
        one_hand_profile_originals = setmetatable({}, { __mode = "k" }),
        one_hand_generated_profiles = {},
        cog_speed_originals = setmetatable({}, { __mode = "k" }),
        mace_sword_speed_originals = setmetatable({}, { __mode = "k" }),
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
            copy.cleave_distribution = scale_cleave(
                copy.cleave_distribution, power_levels, clone, key, M.CLEAVE_MULT)
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
                        for _, field in ipairs(PROFILE_FIELDS) do
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

    function state:_one_hand_profile(source_name, profiles, power_levels, clone)
        local cached = self.one_hand_generated_profiles[source_name]
        if cached then return cached end
        local source = profiles and profiles[source_name]
        if type(source) ~= "table" then return source_name end
        local key = "wt_1h_axe_cleave_90_" .. source_name
        if not profiles[key] then
            local copy = clone(source)
            copy.cleave_distribution = scale_cleave(
                copy.cleave_distribution, power_levels, clone, key, M.CLEAVE_NERF_MULT)
            profiles[key] = copy
        end
        self.one_hand_generated_profiles[source_name] = key
        return key
    end

    function state:apply_one_hand_axe_cleave(enabled, weapons, profiles, power_levels,
            clone, register, fallback_map, parity_allowed)
        enabled = not not enabled
        local targets, source_names, source_seen = {}, {}, {}
        local template_keys = {}
        for key, template in pairs(weapons or {}) do
            if type(key) == "string" and M.is_one_hand_axe_template(template) then
                template_keys[#template_keys + 1] = key
            end
        end
        table.sort(template_keys)

        for _, key in ipairs(template_keys) do
            each_sub_action(weapons[key], function(_, action)
                if not is_direct(action) then return end
                local originals = self.one_hand_profile_originals[action]
                if not originals then
                    originals = {}
                    for _, field in ipairs(PROFILE_FIELDS) do
                        if type(action[field]) == "string" then originals[field] = action[field] end
                    end
                    self.one_hand_profile_originals[action] = originals
                end
                targets[#targets + 1] = { action = action, originals = originals }
                for _, source in pairs(originals) do
                    if not source_seen[source] then
                        source_seen[source] = true
                        source_names[#source_names + 1] = source
                    end
                end
            end)
        end

        -- NetworkLookup append order must not depend on pairs() traversal.
        -- Prepare/register every profile even while the default-off toggle is
        -- disabled, so two WT peers cannot diverge merely because their local
        -- preference differs.
        table.sort(source_names)
        for _, source in ipairs(source_names) do
            local generated = self:_one_hand_profile(source, profiles, power_levels, clone)
            if generated ~= source then
                if fallback_map then fallback_map[generated] = source end
                if register then register(generated) end
            end
        end

        local apply_custom = enabled and parity_allowed == true
        for _, target in ipairs(targets) do
            for field, source in pairs(target.originals) do
                target.action[field] = apply_custom
                    and self:_one_hand_profile(source, profiles, power_levels, clone)
                    or source
            end
        end
        self.one_hand_cleave_enabled = apply_custom
        return #template_keys, #targets
    end

    function state:apply_cog_heavy_speed(enabled, weapons)
        apply_action_speed(enabled, weapons and weapons[M.COG_HAMMER_TEMPLATE],
            M.COG_HAMMER_HEAVY_ACTIONS, self.cog_speed_originals)
        self.cog_heavy_speed_enabled = not not enabled
    end

    function state:apply_mace_sword_speed(enabled, weapons)
        apply_action_speed(enabled, weapons and weapons[M.MACE_SWORD_TEMPLATE],
            M.MACE_SWORD_NERFED_ACTIONS, self.mace_sword_speed_originals)
        self.mace_sword_speed_enabled = not not enabled
    end
    return state
end

return M
