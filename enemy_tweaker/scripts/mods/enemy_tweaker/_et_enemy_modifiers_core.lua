-- _et_enemy_modifiers_core.lua -- pure issue #453 catalog/census policy.

local M = {}

-- Thirteen standard BossGrudgeMarks plus the two requested event modifiers.
-- `regeneratig` is the vanilla template's shipped spelling; do not correct it.
M.MODIFIERS = {
    { id = "warping", enhancement = "warping", buff = "grudge_mark_warping", family = "grudge", requires = { "nav", "position", "side" } },
    { id = "intangible", enhancement = "intangible", buff = "grudge_mark_intangible", family = "grudge", requires = { "nav", "position", "side" } },
    { id = "unstaggerable", enhancement = "unstaggerable", buff = "grudge_mark_unstaggerable", family = "grudge", requires = { "blackboard" } },
    { id = "raging", enhancement = "raging", buff = "grudge_mark_raging", family = "grudge" },
    { id = "vampiric", enhancement = "vampiric", buff = "grudge_mark_vampiric", family = "grudge", requires = { "health" } },
    { id = "ranged_immune", enhancement = "ranged_immune", buff = "grudge_mark_ranged_immune", family = "grudge" },
    { id = "periodic_shield", enhancement = "periodic_shield", buff = "grudge_mark_periodic_shield", family = "grudge" },
    { id = "crippling", enhancement = "crippling", buff = "grudge_mark_crippling_blow", family = "grudge" },
    { id = "crushing", enhancement = "crushing", buff = "grudge_mark_crushing_blow", family = "grudge", requires = { "blackboard" } },
    { id = "regenerating", enhancement = "regenerating", buff = "grudge_mark_regeneratig", family = "grudge", requires = { "health" } },
    { id = "periodic_curse", enhancement = "periodic_curse", buff = "grudge_mark_periodic_curse_aura", family = "grudge", requires = { "position", "side" } },
    { id = "commander", enhancement = "commander", buff = "grudge_mark_commander", family = "grudge", requires = { "blackboard", "race" } },
    { id = "frenzy", enhancement = "frenzy", buff = "grudge_mark_frenzy", family = "grudge", requires = { "health" } },
    { id = "repulse", enhancement = "shockwave", buff = "grudge_mark_shockwave_attacks", family = "geheimnisnacht", requires = { "position", "go_id" } },
    { id = "delvings_berserk", enhancement = "termite_base", buff = "grudge_mark_termite_boss_raging", family = "devious_delvings", requires = { "health" } },
}

local FUNCTION_FIELDS = {
    apply_buff_func = true, buff_func = true, remove_buff_func = true,
    reapply_buff_func = true, update_func = true,
}

local function wire_symmetric(lookup, name)
    local id = type(lookup) == "table" and rawget(lookup, name) or nil
    return type(id) == "number" and rawget(lookup, id) == name or false
end

-- Follow the bounded child-buff graph used by these native templates and prove
-- every named callback exists. This catches a much deeper retail drift than a
-- top-level BuffTemplates/NetworkLookup presence check.
function M.inspect_chain(root_name, env)
    env = env or {}
    local queue, seen = { root_name }, {}
    local result = { templates = 0, template_missing = 0, wire_missing = 0,
        functions = 0, function_missing = 0, capped = false }
    local qi = 1
    while qi <= #queue and result.templates < 32 do
        local name = queue[qi]
        qi = qi + 1
        if not seen[name] then
            seen[name] = true
            result.templates = result.templates + 1
            local template = type(env.buff_templates) == "table" and env.buff_templates[name] or nil
            if type(template) ~= "table" then
                result.template_missing = result.template_missing + 1
            else
                if not wire_symmetric(env.network_buffs, name) then
                    result.wire_missing = result.wire_missing + 1
                end
                local buffs = template.buffs
                if type(buffs) == "table" then
                    for i = 1, #buffs do
                        local row = buffs[i]
                        if type(row) == "table" then
                            for key, value in pairs(row) do
                                if FUNCTION_FIELDS[key] and type(value) == "string" then
                                    result.functions = result.functions + 1
                                    if type(env.functions) ~= "table" or type(env.functions[value]) ~= "function" then
                                        result.function_missing = result.function_missing + 1
                                    end
                                elseif type(key) == "string" and key:find("buff_to_add", 1, true)
                                    and type(value) == "string" and not seen[value] then
                                    queue[#queue + 1] = value
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    result.capped = qi <= #queue
    return result
end

function M.runtime_plan(breed_name, capabilities, banned)
    capabilities = capabilities or {}
    banned = banned or {}
    local eligible, rejected = {}, { banned = 0, buff = 0, prerequisite = 0 }
    for i = 1, #M.MODIFIERS do
        local cfg = M.MODIFIERS[i]
        if banned[cfg.enhancement] then
            rejected.banned = rejected.banned + 1
        elseif not capabilities.buff then
            rejected.buff = rejected.buff + 1
        else
            local ready = true
            for j = 1, #(cfg.requires or {}) do
                if not capabilities[cfg.requires[j]] then ready = false break end
            end
            if ready then eligible[#eligible + 1] = cfg.id
            else rejected.prerequisite = rejected.prerequisite + 1 end
        end
    end
    return { breed = breed_name, eligible = eligible, rejected = rejected }
end

local function list_has(list, value)
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

function M.classify_breed(name, breed, lord_set)
    if type(breed) ~= "table" then return nil end
    if type(lord_set) == "table" and lord_set[name] then return "lord" end
    if breed.boss == true then return "boss" end
    if breed.special == true then return "special" end
    if breed.elite == true then return "elite" end
    return nil
end

function M.audit(env)
    env = env or {}
    local rows = {}
    local missing = 0
    local wire_missing = 0
    local enhancement_missing = 0
    local dependency_missing = 0
    local dependency_wire_missing = 0
    local function_missing = 0

    for i = 1, #M.MODIFIERS do
        local cfg = M.MODIFIERS[i]
        local template = type(env.buff_templates) == "table" and env.buff_templates[cfg.buff] or nil
        local symmetric = wire_symmetric(env.network_buffs, cfg.buff)
        local enhancement = type(env.enhancements) == "table" and env.enhancements[cfg.enhancement] or nil
        local enhancement_has_buff = list_has(enhancement, cfg.buff)
        local chain = M.inspect_chain(cfg.buff, env)

        if template == nil then missing = missing + 1 end
        if not symmetric then wire_missing = wire_missing + 1 end
        if not enhancement_has_buff then enhancement_missing = enhancement_missing + 1 end
        dependency_missing = dependency_missing + math.max(0, chain.template_missing - (template == nil and 1 or 0))
        dependency_wire_missing = dependency_wire_missing
            + math.max(0, chain.wire_missing - (symmetric and 0 or 1))
        function_missing = function_missing + chain.function_missing
        rows[#rows + 1] = {
            id = cfg.id,
            family = cfg.family,
            enhancement = cfg.enhancement,
            buff = cfg.buff,
            template_present = template ~= nil,
            wire_symmetric = symmetric,
            enhancement_has_buff = enhancement_has_buff,
            chain = chain,
        }
    end

    local categories = { special = 0, boss = 0, elite = 0, lord = 0 }
    if type(env.breeds) == "table" then
        for name, breed in pairs(env.breeds) do
            local category = M.classify_breed(name, breed, env.lord_set)
            if category then categories[category] = categories[category] + 1 end
        end
    end

    return rows, {
        modifiers = #M.MODIFIERS,
        template_missing = missing,
        wire_missing = wire_missing,
        enhancement_missing = enhancement_missing,
        dependency_missing = dependency_missing,
        dependency_wire_missing = dependency_wire_missing,
        function_missing = function_missing,
        categories = categories,
    }
end

return M
