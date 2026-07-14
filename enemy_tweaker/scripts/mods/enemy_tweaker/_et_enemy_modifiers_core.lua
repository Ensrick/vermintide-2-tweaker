-- _et_enemy_modifiers_core.lua -- pure issue #453 catalog/census policy.

local M = {}

-- Thirteen standard BossGrudgeMarks plus the two requested event modifiers.
-- `regeneratig` is the vanilla template's shipped spelling; do not correct it.
M.MODIFIERS = {
    { id = "warping", enhancement = "warping", buff = "grudge_mark_warping", family = "grudge" },
    { id = "intangible", enhancement = "intangible", buff = "grudge_mark_intangible", family = "grudge" },
    { id = "unstaggerable", enhancement = "unstaggerable", buff = "grudge_mark_unstaggerable", family = "grudge" },
    { id = "raging", enhancement = "raging", buff = "grudge_mark_raging", family = "grudge" },
    { id = "vampiric", enhancement = "vampiric", buff = "grudge_mark_vampiric", family = "grudge" },
    { id = "ranged_immune", enhancement = "ranged_immune", buff = "grudge_mark_ranged_immune", family = "grudge" },
    { id = "periodic_shield", enhancement = "periodic_shield", buff = "grudge_mark_periodic_shield", family = "grudge" },
    { id = "crippling", enhancement = "crippling", buff = "grudge_mark_crippling_blow", family = "grudge" },
    { id = "crushing", enhancement = "crushing", buff = "grudge_mark_crushing_blow", family = "grudge" },
    { id = "regenerating", enhancement = "regenerating", buff = "grudge_mark_regeneratig", family = "grudge" },
    { id = "periodic_curse", enhancement = "periodic_curse", buff = "grudge_mark_periodic_curse_aura", family = "grudge" },
    { id = "commander", enhancement = "commander", buff = "grudge_mark_commander", family = "grudge" },
    { id = "frenzy", enhancement = "frenzy", buff = "grudge_mark_frenzy", family = "grudge" },
    { id = "repulse", enhancement = "shockwave", buff = "grudge_mark_shockwave_attacks", family = "geheimnisnacht" },
    { id = "delvings_berserk", enhancement = "termite_base", buff = "grudge_mark_termite_boss_raging", family = "devious_delvings" },
}

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

    for i = 1, #M.MODIFIERS do
        local cfg = M.MODIFIERS[i]
        local template = type(env.buff_templates) == "table" and env.buff_templates[cfg.buff] or nil
        local lookup = type(env.network_buffs) == "table" and rawget(env.network_buffs, cfg.buff) or nil
        local symmetric = type(lookup) == "number"
            and rawget(env.network_buffs, lookup) == cfg.buff or false
        local enhancement = type(env.enhancements) == "table" and env.enhancements[cfg.enhancement] or nil
        local enhancement_has_buff = list_has(enhancement, cfg.buff)

        if template == nil then missing = missing + 1 end
        if not symmetric then wire_missing = wire_missing + 1 end
        if not enhancement_has_buff then enhancement_missing = enhancement_missing + 1 end
        rows[#rows + 1] = {
            id = cfg.id,
            family = cfg.family,
            enhancement = cfg.enhancement,
            buff = cfg.buff,
            template_present = template ~= nil,
            wire_symmetric = symmetric,
            enhancement_has_buff = enhancement_has_buff,
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
        categories = categories,
    }
end

return M
