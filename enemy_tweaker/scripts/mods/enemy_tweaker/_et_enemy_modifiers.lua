local mod = get_mod("enemy_tweaker")

-- _et_enemy_modifiers.lua -- #453 read-only modifier feasibility audit.
--
-- This deliberately does not add another ConflictDirector._post_spawn_unit
-- hook: _et_boss_grudge.lua already owns that pair and VMF drops duplicates.
-- A later implementation must consolidate category/rate selection into that
-- owner, then apply only vanilla network-stable templates host-side.

local ET = mod._et
local Core = ET.EnemyModifiersCore
local rt_register = ET.rt_register
local _printf = rawget(_G, "printf") or function() end

local LORD_SET = {}
local breeds_module = require("scripts/mods/enemy_tweaker/enemy_tweaker_breeds")
for i = 1, #breeds_module.LORDS do LORD_SET[breeds_module.LORDS[i]] = true end
LORD_SET[breeds_module.ET_SKAVEN_WARLORD] = true

local function audit()
    local lookup = rawget(_G, "NetworkLookup")
    return Core.audit({
        buff_templates = rawget(_G, "BuffTemplates"),
        network_buffs = lookup and lookup.buff_templates,
        enhancements = rawget(_G, "BreedEnhancements"),
        breeds = rawget(_G, "Breeds"),
        lord_set = LORD_SET,
    })
end

local function print_details(reason)
    local rows, summary = audit()
    pcall(_printf,
        "[et:453] modifier-audit reason=%s modifiers=%d template_missing=%d wire_missing=%d enhancement_missing=%d special=%d boss=%d elite=%d lord=%d behavior_changes=0",
        tostring(reason), summary.modifiers, summary.template_missing,
        summary.wire_missing, summary.enhancement_missing,
        summary.categories.special, summary.categories.boss,
        summary.categories.elite, summary.categories.lord)
    for i = 1, #rows do
        local r = rows[i]
        pcall(_printf,
            "[et:453] %s family=%s enhancement=%s buff=%s template=%s wire=%s enhancement_contains=%s",
            r.id, r.family, r.enhancement, r.buff,
            tostring(r.template_present), tostring(r.wire_symmetric),
            tostring(r.enhancement_has_buff))
    end
    return summary
end

ET.enemy_modifiers_audit = audit
ET.ENEMY_MODIFIER_CATALOG = Core.MODIFIERS

-- One bounded log line at load; detail is explicit to avoid startup log spam.
local _, initial_summary = audit()
pcall(_printf,
    "[et:453] modifier-audit ready modifiers=%d gaps=%d command=/et_modifier_audit behavior_changes=0",
    initial_summary.modifiers,
    initial_summary.template_missing + initial_summary.wire_missing + initial_summary.enhancement_missing)

mod:command("et_modifier_audit", "Write issue #453 enemy-modifier diagnostics to the log", function()
    local summary = print_details("command")
    mod:echo("[et:453] audited %d modifiers; gaps=%d. Details written to the current log.",
        summary.modifiers,
        summary.template_missing + summary.wire_missing + summary.enhancement_missing)
end)

rt_register("issue453_modifier_catalog_wire_ready", function()
    local rows, summary = audit()
    if summary.modifiers ~= 15 or #rows ~= 15 then
        return string.format("modifier count drifted: summary=%d rows=%d", summary.modifiers, #rows)
    end
    local gaps = summary.template_missing + summary.wire_missing + summary.enhancement_missing
    if gaps > 0 then
        return string.format("modifier catalog has %d runtime gaps; run /et_modifier_audit", gaps)
    end
    for _, category in ipairs({ "special", "boss", "elite", "lord" }) do
        if summary.categories[category] < 1 then
            return string.format("no breeds classified for category %s", category)
        end
    end
end)

return { audit = audit, print_details = print_details }
