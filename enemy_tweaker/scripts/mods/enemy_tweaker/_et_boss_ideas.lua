local mod = get_mod("enemy_tweaker")

-- _et_boss_ideas.lua -- #451 source-backed feasibility diagnostics
--
-- The requested boss concepts reuse lord assets whose vanilla breeds are tied
-- to scripted arenas.  This module deliberately does not place those breeds in
-- the ordinary monster pool.  It records the runtime structures that a safe,
-- portable implementation must replace, and prints a bounded one-shot audit to
-- the engine log (visible even when VMF logging is disabled).

local ET = mod._et
local rt_register = ET.rt_register

local CANDIDATES = {
    {
        id = "chosen_shield",
        source_breed = "chaos_raider",
        model_breed = "chaos_exalted_champion_warcamp",
        status = "prototype_required",
        blocker = "needs a new regular-AI breed plus compatible shield/sword inventory; do not reuse Bodvarr AI",
    },
    {
        id = "chosen_greataxe",
        source_breed = "chaos_raider",
        model_breed = "chaos_exalted_champion_warcamp",
        status = "prototype_required",
        blocker = "needs a new regular-AI breed and a model/inventory compatibility probe; do not reuse Bodvarr AI",
    },
    {
        id = "stormfiend_ratlings",
        source_breed = "skaven_stormfiend_boss",
        status = "arena_coupled",
        blocker = "Deathrattler behavior owns mount and intro states; clone assets onto portable monster AI",
        risk = function()
            local actions = rawget(_G, "BreedActions")
            local a = actions and actions.skaven_stormfiend_boss
            return a and (a.mount_unit ~= nil or a.dual_shoot_intro ~= nil)
        end,
    },
    {
        id = "skaven_warlock",
        source_breed = "skaven_grey_seer",
        status = "arena_coupled",
        blocker = "Rasknitt behavior owns mount and scripted-spawner states; a portable behavior tree is required",
        risk = function()
            local actions = rawget(_G, "BreedActions")
            local a = actions and actions.skaven_grey_seer
            return a and (a.mount_unit ~= nil or a.spawn_allies ~= nil)
        end,
    },
    {
        id = "chaos_sorcerer",
        source_breed = "chaos_exalted_sorcerer",
        status = "arena_coupled",
        blocker = "Halescourge actions query named arena spawners; a portable teleport/spawn policy is required",
        risk = function()
            local actions = rawget(_G, "BreedActions")
            local a = actions and actions.chaos_exalted_sorcerer
            return a and (a.spawn_boss_vortex ~= nil or a.defensive_mode ~= nil or a.intro_idle ~= nil)
        end,
    },
    {
        id = "troll_chieftain",
        source_breed = "chaos_troll_chief",
        status = "arena_coupled",
        blocker = "phase events spawn oil sockets/sorcerers, disable objectives, and fire arena flow events; strip them in a cloned action set",
        risk = function()
            local actions = rawget(_G, "BreedActions")
            local downed = actions and actions.chaos_troll_chief and actions.chaos_troll_chief.downed
            return downed and (downed.downed_chunk_events ~= nil or downed.upped_chunk_events ~= nil)
        end,
    },
}

local function audit()
    local breeds = rawget(_G, "Breeds")
    local rows = {}
    local missing = 0
    local risk_confirmed = 0

    for i = 1, #CANDIDATES do
        local c = CANDIDATES[i]
        local source_present = breeds and breeds[c.source_breed] ~= nil or false
        local model_present = not c.model_breed or breeds and breeds[c.model_breed] ~= nil or false
        local risk_present = c.risk and c.risk() and true or false

        if not source_present or not model_present then
            missing = missing + 1
        end
        if risk_present then
            risk_confirmed = risk_confirmed + 1
        end

        rows[#rows + 1] = {
            id = c.id,
            status = c.status,
            source_present = source_present,
            model_present = model_present,
            risk_present = risk_present,
            blocker = c.blocker,
        }
    end

    return rows, missing, risk_confirmed
end

local function print_audit(reason)
    local rows, missing, risk_confirmed = audit()
    pcall(printf, "[et:451] boss-ideas audit reason=%s candidates=%d missing=%d arena_risks_confirmed=%d behavior_changes=0",
        tostring(reason), #rows, missing, risk_confirmed)
    for i = 1, #rows do
        local row = rows[i]
        pcall(printf, "[et:451] %s status=%s source=%s model=%s risk=%s blocker=%s",
            row.id, row.status, tostring(row.source_present), tostring(row.model_present),
            tostring(row.risk_present), row.blocker)
    end
end

ET.BOSS_IDEA_CANDIDATES = CANDIDATES
ET.boss_ideas_audit = audit

-- Automatic, bounded diagnostics: seven log-only lines once per mod load.
print_audit("mod_load")

rt_register("issue451_boss_ideas_safely_decomposed", function()
    local rows, missing, risk_confirmed = audit()
    if #rows ~= 6 then
        return string.format("candidate count drifted: got %d, expected 6", #rows)
    end
    if missing > 0 then
        return string.format("%d source/model breed keys missing", missing)
    end
    -- Four vanilla lord breeds are intentionally rejected as portable inputs.
    -- If their risky action shapes disappear after a game update, re-audit the
    -- source before changing this threshold or enabling a spawn path.
    if risk_confirmed < 4 then
        return string.format("only %d/4 arena-coupling markers remain; source re-audit required", risk_confirmed)
    end
end)
