local mod = get_mod("enemy_tweaker")

-- #451 source-backed, bounded feasibility diagnostics. No spawn mutation.
local ET = mod._et
local Core = ET.BossIdeasCore
local CAP, captures = 2, 0

local BLOCKERS = {
    chosen_shield = "clone regular Chaos Warrior AI; validate shield inventory and shield event vocabulary",
    chosen_greataxe = "first prototype: regular Chaos Warrior AI plus boss model/inventory contract",
    stormfiend_ratlings = "strip Deathrattler mount and intro state before portable use",
    skaven_warlock = "replace Rasknitt mount and named-spawner dependencies",
    chaos_sorcerer = "replace Halescourge arena teleport/spawner queries",
    troll_chieftain = "strip oil sockets, objective writes, phase spawners, and arena flow events",
}

local function _risk(id)
    local actions = rawget(_G, "BreedActions") or {}
    if id == "stormfiend_ratlings" then
        local row = actions.skaven_stormfiend_boss
        return row and (row.mount_unit ~= nil or row.dual_shoot_intro ~= nil) or false
    elseif id == "skaven_warlock" then
        local row = actions.skaven_grey_seer
        return row and (row.mount_unit ~= nil or row.spawn_allies ~= nil) or false
    elseif id == "chaos_sorcerer" then
        local row = actions.chaos_exalted_sorcerer
        return row and (row.spawn_boss_vortex ~= nil or row.defensive_mode ~= nil
            or row.intro_idle ~= nil) or false
    elseif id == "troll_chieftain" then
        local downed = actions.chaos_troll_chief and actions.chaos_troll_chief.downed
        return downed and (downed.downed_chunk_events ~= nil
            or downed.upped_chunk_events ~= nil) or false
    end
    return false
end

local function _resident(unit_name)
    local app = rawget(_G, "Application")
    if not app or type(app.can_get) ~= "function" then return false end
    local ok, value = pcall(app.can_get, "unit", unit_name)
    return ok and value and true or false
end

local function _audit()
    local lookup = rawget(_G, "NetworkLookup")
    local result = Core.inspect({
        breeds = rawget(_G, "Breeds"),
        actions = rawget(_G, "BreedActions"),
        behaviors = rawget(_G, "BreedBehaviors"),
        inventories = rawget(_G, "InventoryConfigurations"),
        breed_lookup = lookup and lookup.breeds,
        unit_resident = _resident,
    })
    result.arena_risks = 0
    for _, row in ipairs(result.rows) do
        row.risk_present = _risk(row.id) and true or false
        row.blocker = BLOCKERS[row.id]
        if row.risk_present then result.arena_risks = result.arena_risks + 1 end
    end
    return result
end

local function _print_audit(reason)
    if captures >= CAP then return end
    captures = captures + 1
    local result = _audit()
    pcall(printf, "[et:451] audit=%d/%d reason=%s candidates=%d missing_breeds=%d structure_ready=%d resident_models=%d arena_risks=%d behavior_changes=0",
        captures, CAP, tostring(reason), #result.rows, result.missing_breeds,
        result.structure_ready, result.resident_models, result.arena_risks)
    for _, row in ipairs(result.rows) do
        pcall(printf, "[et:451] id=%s status=%s source=%s model=%s actions=%s behavior=%s inventory=%s wire=%s source_resident=%s model_resident=%s risk=%s blocker=%s",
            row.id, row.status, tostring(row.source_present), tostring(row.model_present),
            tostring(row.actions_present), tostring(row.behavior_present),
            tostring(row.inventory_present), tostring(row.wire_present),
            tostring(row.source_resident), tostring(row.model_resident),
            tostring(row.risk_present), row.blocker)
    end
    return result
end

ET.BOSS_IDEA_CANDIDATES = Core.CANDIDATES
ET.boss_ideas_audit = _audit

_print_audit("mod_load")

mod:command("et_boss_idea_audit", "Recheck boss prototype assets (#451)", function()
    local result = _print_audit("command")
    if result then
        mod:echo("[et:451] %d/6 structural contracts, %d/6 models resident; details in log",
            result.structure_ready, result.resident_models)
    else
        mod:echo("[et:451] audit capture limit reached; use the existing log rows")
    end
end)

ET.rt_register("issue451_boss_ideas_safely_decomposed", function()
    local result = _audit()
    if #result.rows ~= 6 then
        return string.format("candidate count drifted: got %d, expected 6", #result.rows)
    end
    if result.missing_breeds > 0 then
        return string.format("%d source/model breed keys missing", result.missing_breeds)
    end
    if result.structure_ready ~= 6 then
        return string.format("only %d/6 source contracts structurally ready", result.structure_ready)
    end
    if result.arena_risks < 4 then
        return string.format("only %d/4 arena-coupling markers remain; source re-audit required",
            result.arena_risks)
    end
end)
