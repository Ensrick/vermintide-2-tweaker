-- _cwv_greataxe_crit_envelope.lua -- PROTOTYPE finite WT Greataxe crit evidence.
--
-- Pins four raw cells per native/clone role against a single cached baseline.
-- The family owner retains every other graph cell and its unfiltered immediate
-- source-before/precommit proof. This helper never applies/restores/resets WT,
-- writes templates, re-snapshots failed graphs or attests initial origin/body.
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: one manifest load, private captured family-factory dependency.
local M = {}
local QUERY = "_wt_query_greataxe_light_crit"
local FIELD = "additional_critical_strike_chance"
local NAMES = { "light_attack_left", "light_attack_right", "light_attack_up", "light_attack_bopp" }
local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end
local function finite(value)
    return value == nil or (type(value) == "number" and value == value
        and value > -math.huge and value < math.huge)
end
local function shape(value, allowed)
    if not plain(value) then return false end
    for key in next, value do if not allowed[key] then return false end end
    return true
end
local ROOT_FIELDS = { schema = true, installation = true, apply = true, reset = true,
    weapons = true, template_key = true, template = true, actions = true,
    action_one = true, enabled = true, rows = true }
local ROW_FIELDS = { name = true, action = true, present = true, value = true,
    claimed = true, baseline_present = true, baseline_value = true, applied_value = true }
function M.bind(resolve_mod)
    -- Capture resolver by value, late-query only these two IDs. Known-provider
    -- replacement is not adoption; absent providers authorize no changed value.
    local bound = {}
    local function tuple(proof, mod, query)
        local ok, value = pcall(query, proof.weapons, proof.key, proof.template)
        if not ok or not shape(value, ROOT_FIELDS)
                or rawget(value, "schema") ~= "wt.greataxe_light_crit.v1"
                or type(rawget(value, "installation")) ~= "function"
                or not rawequal(rawget(value, "apply"), rawget(mod, "_wt_apply_axe_balance"))
                or not rawequal(rawget(value, "reset"), rawget(mod, "_wt_reset_axe_balance_baselines"))
                or type(rawget(value, "apply")) ~= "function" or type(rawget(value, "reset")) ~= "function"
                or not rawequal(rawget(value, "weapons"), proof.weapons)
                or rawget(value, "template_key") ~= proof.key
                or not rawequal(rawget(value, "template"), proof.template)
                or not rawequal(rawget(value, "actions"), proof.actions)
                or not rawequal(rawget(value, "action_one"), proof.one)
                or type(rawget(value, "enabled")) ~= "boolean" then return nil end
        local rows = rawget(value, "rows")
        if not plain(rows) then return nil end
        local count = 0
        for key in next, rows do
            count = count + 1
            if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 4 then return nil end
        end
        if count ~= 4 then return nil end
        for i = 1, 4 do
            local row, action = rawget(rows, i), proof.rows[i].action
            if not shape(row, ROW_FIELDS) or rawget(row, "name") ~= NAMES[i]
                    or not rawequal(rawget(row, "action"), action)
                    or type(rawget(row, "present")) ~= "boolean"
                    or rawget(row, "present") ~= (rawget(row, "value") ~= nil)
                    or not finite(rawget(row, "value"))
                    or not rawequal(rawget(row, "value"), rawget(action, FIELD))
                    or type(rawget(row, "claimed")) ~= "boolean" then return nil end
            if rawget(row, "claimed") then
                local baseline = rawget(row, "baseline_value")
                if rawget(value, "enabled") ~= true or not finite(baseline)
                        or type(rawget(row, "baseline_present")) ~= "boolean"
                        or rawget(row, "baseline_present") ~= (baseline ~= nil)
                        or not rawequal(rawget(row, "applied_value"), math.max(baseline or 0, 0.10))
                        or not rawequal(rawget(row, "value"), rawget(row, "applied_value")) then return nil end
            elseif rawget(row, "baseline_present") ~= nil or rawget(row, "baseline_value") ~= nil
                    or rawget(row, "applied_value") ~= nil then return nil end
        end
        return value
    end
    local function producers(proof)
        local result = {}
        if type(resolve_mod) ~= "function" then return result end
        for _, id in ipairs({ "wt", "wt_dev" }) do
            local ok, mod = pcall(resolve_mod, id)
            if ok and type(mod) == "table" then
                local query, old = rawget(mod, QUERY), bound[id]
                if old and (not rawequal(old.mod, mod) or not rawequal(old.query, query)) then return nil end
                if type(query) == "function" then
                    local value = tuple(proof, mod, query)
                    if not value then return nil end
                    if old and (not rawequal(old.installation, rawget(value, "installation"))
                            or not rawequal(old.apply, rawget(value, "apply"))
                            or not rawequal(old.reset, rawget(value, "reset"))) then return nil end
                    if not old then
                        bound[id] = { mod = mod, query = query, installation = rawget(value, "installation"),
                            apply = rawget(value, "apply"), reset = rawget(value, "reset") }
                    end
                    result[#result + 1] = value
                elseif query ~= nil then return nil end
            end
        end
        return result
    end
    local function roots(proof, registered)
        if not rawequal(getmetatable(proof.weapons), proof.weapons_meta)
                or not rawequal(getmetatable(proof.template), proof.template_meta)
                or not rawequal(rawget(proof.template, "actions"), proof.actions)
                or not rawequal(getmetatable(proof.actions), proof.actions_meta)
                or not rawequal(rawget(proof.actions, "action_one"), proof.one)
                or not rawequal(getmetatable(proof.one), proof.one_meta)
                or (registered and not rawequal(rawget(proof.weapons, proof.key), proof.template)) then return false end
        for i = 1, 4 do
            local row = proof.rows[i]
            if not rawequal(rawget(proof.one, NAMES[i]), row.action)
                    or not rawequal(getmetatable(row.action), row.meta)
                    or rawget(row.action, "kind") ~= "sweep" then return false end
        end
        return true
    end
    local function valid(proof, registered)
        if not proof or not roots(proof, registered) then return false end
        local current = {}
        if registered then
            current = producers(proof)
        end
        if not current then return false end
        for i = 1, 4 do
            local baseline, claimed = proof.rows[i].baseline, false
            for j = 1, #current do
                local row = current[j].rows[i]
                if row.claimed then
                    if row.baseline_present ~= proof.rows[i].baseline_present
                            or not rawequal(row.baseline_value, baseline) then return false end
                    claimed = true
                end
            end
            local expected = claimed and math.max(baseline or 0, 0.10) or baseline
            if not rawequal(rawget(proof.rows[i].action, FIELD), expected) then return false end
        end
        return roots(proof, registered)
    end
    local function capture(template, weapons, key, registered)
        if type(template) ~= "table" or type(weapons) ~= "table"
                or (key ~= "two_handed_axes_template_1" and key ~= "cwv_greataxe_template") then return nil end
        local actions = rawget(template, "actions")
        local one = type(actions) == "table" and rawget(actions, "action_one")
        if type(one) ~= "table" then return nil end
        local proof = { template = template, template_meta = getmetatable(template),
            weapons = weapons, weapons_meta = getmetatable(weapons), key = key,
            actions = actions, actions_meta = getmetatable(actions), one = one,
            one_meta = getmetatable(one), rows = {} }
        for i = 1, 4 do
            local action = rawget(one, NAMES[i])
            if type(action) ~= "table" or rawget(action, "kind") ~= "sweep"
                    or not finite(rawget(action, FIELD)) then return nil end
            local value = rawget(action, FIELD)
            proof.rows[i] = { action = action, meta = getmetatable(action),
                baseline = value, baseline_present = value ~= nil }
        end
        local current = {}
        if registered then
            current = producers(proof)
        end
        if not current then return nil end
        for i = 1, 4 do
            local found, baseline, present = false
            for j = 1, #current do
                local row = current[j].rows[i]
                if row.claimed then
                    if found and (row.baseline_present ~= present or not rawequal(row.baseline_value, baseline)) then return nil end
                    found, baseline, present = true, row.baseline_value, row.baseline_present
                end
            end
            if found then proof.rows[i].baseline, proof.rows[i].baseline_present = baseline, present end
        end
        return valid(proof, registered) and proof or nil
    end
    return {
        capture = capture,
        intact = valid,
        include = function(proof, target, key)
            if key == FIELD then
                for i = 1, 4 do if rawequal(target, proof.rows[i].action) then return false end end
            end
            return true
        end,
    }
end
return M
