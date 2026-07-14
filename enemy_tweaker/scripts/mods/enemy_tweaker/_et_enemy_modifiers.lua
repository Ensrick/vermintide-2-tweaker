local mod = get_mod("enemy_tweaker")

-- _et_enemy_modifiers.lua -- #453 read-only modifier feasibility audit.
--
-- This deliberately does not add another ConflictDirector._post_spawn_unit
-- hook: _et_boss_grudge.lua already owns that pair and VMF drops duplicates.
-- That owner calls the read-only observer below. No modifier is applied.

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
        functions = rawget(_G, "BuffFunctionTemplates")
            and rawget(_G, "BuffFunctionTemplates").functions,
        enhancements = rawget(_G, "BreedEnhancements"),
        breeds = rawget(_G, "Breeds"),
        lord_set = LORD_SET,
    })
end

local function print_details(reason)
    local rows, summary = audit()
    pcall(_printf,
        "[et:453] modifier-audit reason=%s modifiers=%d template_missing=%d wire_missing=%d enhancement_missing=%d child_missing=%d child_wire_missing=%d function_missing=%d special=%d boss=%d elite=%d lord=%d behavior_changes=0",
        tostring(reason), summary.modifiers, summary.template_missing,
        summary.wire_missing, summary.enhancement_missing,
        summary.dependency_missing, summary.dependency_wire_missing,
        summary.function_missing,
        summary.categories.special, summary.categories.boss,
        summary.categories.elite, summary.categories.lord)
    for i = 1, #rows do
        local r = rows[i]
        pcall(_printf,
            "[et:453] %s family=%s enhancement=%s buff=%s template=%s wire=%s enhancement_contains=%s chain_templates=%d chain_functions=%d chain_gaps=%d capped=%s",
            r.id, r.family, r.enhancement, r.buff,
            tostring(r.template_present), tostring(r.wire_symmetric),
            tostring(r.enhancement_has_buff), r.chain.templates, r.chain.functions,
            r.chain.template_missing + r.chain.wire_missing + r.chain.function_missing,
            tostring(r.chain.capped))
    end
    return summary
end

ET.enemy_modifiers_audit = audit
ET.ENEMY_MODIFIER_CATALOG = Core.MODIFIERS

local OBSERVE_PER_CATEGORY = 2
local _observed_breeds = {}
local _observed_categories = { special = 0, elite = 0, boss = 0, lord = 0 }

local function _has_extension(unit, name)
    local api = rawget(_G, "ScriptUnit")
    if not api or type(api.has_extension) ~= "function" then return false end
    local ok, ext = pcall(api.has_extension, unit, name)
    return ok and ext ~= nil
end

-- Natural-spawn, mutation-free prerequisite census. It samples at most two
-- distinct breeds per requested category and never calls add_buff/set_attribute.
local function observe_spawn(ai_unit, breed, optional_data)
    local name = type(breed) == "table" and breed.name or nil
    local category = name and Core.classify_breed(name, breed, LORD_SET) or nil
    if not category or _observed_breeds[name]
        or _observed_categories[category] >= OBSERVE_PER_CATEGORY then return end

    _observed_breeds[name] = true
    _observed_categories[category] = _observed_categories[category] + 1

    local blackboards = rawget(_G, "BLACKBOARDS")
    local blackboard = type(blackboards) == "table" and blackboards[ai_unit] or nil
    local positions = rawget(_G, "POSITION_LOOKUP")
    local managers = rawget(_G, "Managers")
    local state = managers and managers.state
    local side = state and state.side and state.side.side_by_unit
        and state.side.side_by_unit[ai_unit] or nil
    local go_id
    local storage = state and state.unit_storage
    if storage and type(storage.go_id) == "function" then
        local ok, value = pcall(storage.go_id, storage, ai_unit)
        if ok then go_id = value end
    end
    local capabilities = {
        buff = _has_extension(ai_unit, "buff_system"),
        health = _has_extension(ai_unit, "health_system"),
        blackboard = type(blackboard) == "table",
        nav = type(blackboard) == "table" and blackboard.nav_world ~= nil,
        position = type(positions) == "table" and positions[ai_unit] ~= nil,
        side = side ~= nil,
        race = type(breed.race) == "string",
        go_id = type(go_id) == "number" and go_id > 0,
    }
    local banned_by_breed = rawget(_G, "BreedEnhancementBannedBreeds")
    local banned = type(banned_by_breed) == "table" and banned_by_breed[name] or nil
    local plan = Core.runtime_plan(name, capabilities, banned)
    local sample = {}
    for i = 1, math.min(5, #plan.eligible) do sample[i] = plan.eligible[i] end
    local existing = type(optional_data) == "table"
        and type(optional_data.enhancements) == "table" and #optional_data.enhancements or 0
    pcall(_printf,
        "[et:453] live category=%s breed=%s sample=%d/%d eligible=%d eligible_sample=%s rejected_banned=%d rejected_buff=%d rejected_prereq=%d buff=%s health=%s blackboard=%s nav=%s position=%s side=%s race=%s go_id=%s existing_enhancements=%d mutation=0",
        category, name, _observed_categories[category], OBSERVE_PER_CATEGORY,
        #plan.eligible, #sample > 0 and table.concat(sample, ",") or "none",
        plan.rejected.banned, plan.rejected.buff, plan.rejected.prerequisite,
        tostring(capabilities.buff), tostring(capabilities.health),
        tostring(capabilities.blackboard), tostring(capabilities.nav),
        tostring(capabilities.position), tostring(capabilities.side),
        tostring(capabilities.race), tostring(capabilities.go_id), existing)
end

ET.observe_enemy_modifier_spawn = observe_spawn

-- One bounded log line at load; detail is explicit to avoid startup log spam.
local _, initial_summary = audit()
pcall(_printf,
    "[et:453] modifier-audit ready modifiers=%d gaps=%d command=/et_modifier_audit behavior_changes=0",
    initial_summary.modifiers,
    initial_summary.template_missing + initial_summary.wire_missing
        + initial_summary.enhancement_missing + initial_summary.dependency_missing
        + initial_summary.dependency_wire_missing + initial_summary.function_missing)

mod:command("et_modifier_audit", "Write issue #453 enemy-modifier diagnostics to the log", function()
    local summary = print_details("command")
    mod:echo("[et:453] audited %d modifiers; gaps=%d. Details written to the current log.",
        summary.modifiers,
        summary.template_missing + summary.wire_missing + summary.enhancement_missing
            + summary.dependency_missing + summary.dependency_wire_missing
            + summary.function_missing)
end)

rt_register("issue453_modifier_catalog_wire_ready", function()
    local rows, summary = audit()
    if summary.modifiers ~= 15 or #rows ~= 15 then
        return string.format("modifier count drifted: summary=%d rows=%d", summary.modifiers, #rows)
    end
    local gaps = summary.template_missing + summary.wire_missing + summary.enhancement_missing
        + summary.dependency_missing + summary.dependency_wire_missing
        + summary.function_missing
    if gaps > 0 then
        return string.format("modifier catalog has %d runtime gaps; run /et_modifier_audit", gaps)
    end
    for _, category in ipairs({ "special", "boss", "elite", "lord" }) do
        if summary.categories[category] < 1 then
            return string.format("no breeds classified for category %s", category)
        end
    end
end)

rt_register("issue453_live_prerequisite_probe_bounded", function()
    if OBSERVE_PER_CATEGORY ~= 2 then return "per-category sample cap drifted" end
    if type(ET.observe_enemy_modifier_spawn) ~= "function" then
        return "natural-spawn prerequisite observer missing"
    end
end)

return { audit = audit, print_details = print_details }
