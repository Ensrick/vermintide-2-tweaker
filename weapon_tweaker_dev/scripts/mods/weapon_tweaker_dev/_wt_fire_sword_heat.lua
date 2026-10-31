-- #942 direct Fire Sword policy. No engine globals, settings writes or RPC.
local M = {}
M.TEMPLATE = "flaming_sword_template_1"
M.ENABLED = "wt_fire_sword_heat"
M.ARMOR = "wt_fire_sword_heat_armor"
M.CLEAVE = "wt_fire_sword_heat_cleave_percent"
M.DAMAGE = "wt_fire_sword_heat_damage_percent"
M.THRESHOLD = "wt_fire_sword_heat_armor_threshold"
local FIELDS = { "damage_profile", "damage_profile_right", "damage_profile_target" }

local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
M.finite = finite

function M.config(read)
    local ok, enabled, armor, cleave, damage, threshold = pcall(function()
        return read(M.ENABLED), read(M.ARMOR), read(M.CLEAVE),
            read(M.DAMAGE), read(M.THRESHOLD)
    end)
    if not ok then return nil, "setting-reader-failed" end
    if enabled ~= nil and type(enabled) ~= "boolean"
            or armor ~= nil and type(armor) ~= "boolean" then
        return nil, "setting-boolean-invalid"
    end
    if cleave == nil then cleave = 2 end
    if damage == nil then damage = 1 end
    if threshold == nil then threshold = 25 end
    -- These are validation bounds, not a request for new slider limits. The
    -- eventual UI must use the exact same finite bounded contract.
    if not finite(cleave) or cleave < 0 or cleave > 10
            or not finite(damage) or damage < 0 or damage > 10
            or not finite(threshold) or threshold < 0 or threshold > 100 then
        return nil, "setting-number-invalid"
    end
    return { enabled = enabled == true, armor = armor == true,
        cleave = cleave / 100, damage = damage / 100, threshold = threshold }
end

-- One getter invocation serves both contracts. The scalar API still returns
-- exactly one value; diagnostic status never grants gameplay authorization.
local function read_heat(unit, extension, alive)
    local status = "no-unit"
    local ok, value, _, maximum = pcall(function()
        if unit == nil then return end
        status = "not-alive"
        if alive(unit) ~= true then return end
        status = "extension-missing"
        local oc = extension(unit, "overcharge_system")
        if not oc or type(oc.current_overcharge_status) ~= "function" then return end
        status = "sampled"
        return oc:current_overcharge_status()
    end)
    if not ok then return 0, nil, nil, "reader-error" end
    if not finite(value) then return 0, nil, finite(maximum) and maximum or nil,
        status == "sampled" and "value-invalid" or status end
    if not finite(maximum) or maximum <= 0 then
        return 0, value, finite(maximum) and maximum or nil, "maximum-invalid"
    end
    return math.max(0, math.min(value, maximum)), value, maximum, "ok"
end

function M.heat(unit, extension, alive)
    local amount = read_heat(unit, extension, alive)
    return amount
end

function M.sample_heat(unit, extension, alive)
    return read_heat(unit, extension, alive)
end

local function direct(profile)
    return type(profile) == "table" and profile.is_dot ~= true
        and profile.no_damage ~= true
        and (profile.charge_value == "light_attack" or profile.charge_value == "heavy_attack")
end

-- Every target may override the root armor table. Alter attack[2] only where
-- it is exactly zero; retain positive stabs, impact and other categories.
local function armor_copy(profile, clone, armor_reference)
    if profile.charge_value ~= "light_attack" then return nil end
    local result, changed = clone(profile), false
    local function row(target, inherited)
        local armor = target.armor_modifier or inherited
        if type(armor) == "table" and type(armor.attack) == "table"
                and armor.attack[2] == 0 then
            local replacement = clone(armor)
            replacement.attack[2] = armor_reference.attack[2]
            target.armor_modifier = replacement
            changed = true
        end
    end
    row(result)
    if type(result.default_target) == "table" then row(result.default_target, profile.armor_modifier) end
    for _, target in pairs(result.targets or {}) do
        if type(target) == "table" then row(target, profile.armor_modifier) end
    end
    return changed and result or nil
end

function M.new(weapons, profiles, clone, register, fallbacks, armor_reference)
    assert(type(weapons) == "table" and type(profiles) == "table", "#942 registries missing")
    assert(type(clone) == "function" and type(register) == "function", "#942 clone/register missing")
    assert(type(fallbacks) == "table", "#942 fallback registry missing")
    assert(type(armor_reference) == "table" and type(armor_reference.attack) == "table"
        and finite(armor_reference.attack[2]) and armor_reference.attack[2] > 0,
        "#942 resolved native armor reference missing")
    local state = { rows = {}, owned = {}, actions = {}, clones = {}, profiles = profiles,
        labels = {}, action_labels = {} }
    local function remember(map, value, name)
        if type(value) ~= "table" or type(name) ~= "string" then return end
        local previous = map[value]
        map[value] = previous == nil and name or previous == name and name or "ambiguous"
    end
    remember(state.labels, rawget(profiles, "burning_dot"), "burning_dot")
    local template = rawget(weapons, M.TEMPLATE)
    local sources, action_rows = {}, {}
    for group_name, group in pairs(type(template) == "table" and template.actions or {}) do
        if type(group) == "table" then
            for action_name, action in pairs(group) do
                if type(group_name) == "string" and type(action_name) == "string" then
                    remember(state.action_labels, action, group_name .. "." .. action_name)
                end
                if type(action) == "table" then
                    local aoe = rawget(action, "damage_profile_aoe")
                    if type(aoe) == "string" then remember(state.labels, rawget(profiles, aoe), aoe) end
                end
                if type(action) == "table" and (action.kind == "sweep"
                        or action.kind == "charged_sweep" or action.kind == "shield_slam") then
                    for _, field in ipairs(FIELDS) do
                        local source = rawget(action, field)
                        if type(source) == "string" and direct(rawget(profiles, source)) then
                            sources[source] = true
                            remember(state.labels, rawget(profiles, source), source)
                            action_rows[#action_rows + 1] = { action = action, field = field, source = source }
                        end
                    end
                end
            end
        end
    end
    local sorted = {}
    for source in pairs(sources) do sorted[#sorted + 1] = source end
    table.sort(sorted)
    -- Registration is unconditionally sorted and never depends on toggles or
    -- heat. Markers are immutable source semantics, not live numeric settings.
    local pending = {}
    for _, source in ipairs(sorted) do
        local profile = profiles[source]
        local normal = clone(profile)
        normal._wt942_direct_source = source
        local normal_key = "wt942_direct_" .. source
        local armored = armor_copy(profile, clone, armor_reference)
        local armored_key = armored and "wt942_armored_" .. source or nil
        if armored then armored._wt942_direct_source = source; armored._wt942_armor = true end
        state.clones[source] = { normal = normal_key, armored = armored_key }
        pending[normal_key] = { profile = normal, source = source, armored = false }
        if armored_key then pending[armored_key] = { profile = armored, source = source, armored = true } end
    end
    sorted = {}
    for key in pairs(pending) do sorted[#sorted + 1] = key end
    table.sort(sorted)
    for _, key in ipairs(sorted) do
        assert(rawget(profiles, key) == nil, "#942 duplicate owner profile: " .. key)
        local data = pending[key]
        profiles[key], fallbacks[key] = data.profile, data.source
        state.owned[data.profile] = data
        remember(state.labels, data.profile, key)
        register(key)
    end
    for _, row in ipairs(action_rows) do
        row.key = state.clones[row.source].normal
        state.rows[#state.rows + 1] = row
        state.actions[row.action] = true
    end

    function state:project(enabled)
        local count = 0
        for _, row in ipairs(self.rows) do
            local live = row.action[row.field]
            -- Do not overwrite another owner's later action rewrite. A live
            -- template replacement needs an explicit bounded recapture lane.
            if live == row.source or live == row.key then
                row.action[row.field] = enabled == true and row.key or row.source
                count = count + 1
            end
        end
        return count
    end

    function state:prepare(action, heat, config, init_data)
        if not self.actions[action] then return action, nil end
        if init_data and init_data.action_hand == "left" then
            local native = {}
            for key, value in pairs(action) do native[key] = value end
            for _, row in ipairs(self.rows) do
                if row.action == action and action[row.field] == row.key then
                    native[row.field] = row.source
                end
            end
            return native, nil
        end
        if not config or config.enabled ~= true or heat <= 0 then
            return action, nil
        end
        local copy, selected = {}, {}
        for key, value in pairs(action) do copy[key] = value end
        for _, row in ipairs(self.rows) do
            if row.action == action and action[row.field] == row.key then
                local choice = self.clones[row.source]
                copy[row.field] = config.armor and heat > config.threshold
                    and choice.armored or choice.normal
                selected[profiles[copy[row.field]]] = true
            end
        end
        if next(selected) == nil then return action, nil end
        return copy, { heat = heat, config = config, selected = selected }
    end

    function state:source_profile(profile)
        local row = self.owned[profile]
        return row and profiles[row.source], row
    end

    function state:damage_profile(profile, heat, config, active)
        local original, row = self:source_profile(profile)
        if not row then return profile end
        if not active or heat <= 0 then return original end
        local choice = self.clones[row.source]
        return profiles[config.armor and heat > config.threshold and choice.armored or choice.normal]
    end
    return state
end

return M
