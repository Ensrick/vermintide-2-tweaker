-- Pure display policy for issue #153. This module intentionally owns no hooks
-- and never mutates PassiveAbilitySettings or career gameplay data.
local Policy = {}

local STANDARD_BASE_CRIT = 0.05

local function contains(values, wanted)
    for _, value in ipairs(values or {}) do
        if value == wanted then
            return true
        end
    end
    return false
end

function Policy.entries(career_name, career_settings, passive_ability)
    if career_name ~= "wh_captain" then
        return {}
    end

    local entries = {}
    local buffs = passive_ability and passive_ability.buffs or {}
    if contains(buffs, "victor_witchhunter_headshot_multiplier_increase") then
        entries[#entries + 1] = {
            id = "whc_headshot_multiplier",
            title_key = "gut_hidden_passive_whc_headshot_name",
            description_key = "gut_hidden_passive_whc_headshot_desc",
        }
    end

    local attributes = career_settings and career_settings.attributes or {}
    local crit = tonumber(attributes.base_critical_strike_chance)
    if crit and math.abs((crit - STANDARD_BASE_CRIT) - 0.05) < 0.00001 then
        entries[#entries + 1] = {
            id = "whc_base_crit",
            title_key = "gut_hidden_passive_whc_crit_name",
            description_key = "gut_hidden_passive_whc_crit_desc",
        }
    end

    return entries
end

function Policy.append_description(base_text, heading, entries, localize)
    if type(base_text) ~= "string" or type(localize) ~= "function"
            or type(entries) ~= "table" or #entries == 0 then
        return base_text
    end

    local marker = "\n" .. tostring(heading) .. "\n"
    if string.find(base_text, marker, 1, true) then
        return base_text
    end

    local lines = { base_text, "", tostring(heading) }
    for _, entry in ipairs(entries) do
        lines[#lines + 1] = string.format("%s — %s",
            localize(entry.title_key), localize(entry.description_key))
    end
    return table.concat(lines, "\n")
end

function Policy.inspect(careers, passive_by_name)
    local result = { career_count = 0, catalogued_count = 0, records = {} }
    for _, career in ipairs(careers or {}) do
        local name = career and career.name
        if type(name) == "string" then
            result.career_count = result.career_count + 1
            local passive = passive_by_name and passive_by_name[name]
            local entries = Policy.entries(name, career, passive)
            if #entries > 0 then
                result.catalogued_count = result.catalogued_count + 1
            end
            result.records[#result.records + 1] = {
                name = name,
                buff_count = passive and #(passive.buffs or {}) or 0,
                vanilla_perk_count = passive and #(passive.perks or {}) or 0,
                hidden_count = #entries,
            }
        end
    end
    table.sort(result.records, function(a, b) return a.name < b.name end)
    return result
end

return Policy
