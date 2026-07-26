-- Engine-free catalog and preset policy for issue #936.
-- The legacy per-career setting IDs remain stable as "Enable All" controls;
-- gameplay mutations are owned exclusively by the leaf IDs below.

local M = {}

M.CAREERS = {
    { master_id = "trn_es_mercenary", parent_id = "rework_es_mercenary_group", leaves = {
        "trn_es_mercenary_paced_strikes",
    } },
    { master_id = "trn_es_huntsman", parent_id = "rework_es_huntsman_group", leaves = {
        "trn_es_huntsman_crit_aura_range",
        "trn_es_huntsman_prowl_reload_speed",
    } },
    { master_id = "trn_es_knight", parent_id = "rework_es_knight_group", leaves = {
        "trn_es_knight_protective_presence",
        "trn_es_knight_have_at_them_range",
        "trn_es_knight_cooldown_on_damage",
        "trn_es_knight_elite_stagger_power_duration",
        "trn_es_knight_push_attack_speed_duration",
        "trn_es_knight_impact_power",
        "trn_es_knight_stagger_cooldown_duration",
    } },
    { master_id = "trn_es_questingknight", parent_id = "rework_es_questingknight_group", leaves = {
        "trn_es_questingknight_instant_kill_threshold",
        "trn_es_questingknight_kill_move_speed_duration",
        "trn_es_questingknight_health_refund",
    } },
    { master_id = "trn_dr_ranger", parent_id = "rework_dr_ranger_group", leaves = {
        "trn_dr_ranger_attack_speed",
        "trn_dr_ranger_exuberance_dr",
        "trn_dr_ranger_free_grenade_duration",
    } },
    { master_id = "trn_dr_ironbreaker", parent_id = "rework_dr_ironbreaker_group", leaves = {
        "trn_dr_ironbreaker_cooldown_on_damage",
        "trn_dr_ironbreaker_gromril_regeneration",
        "trn_dr_ironbreaker_gromril_attack_speed",
    } },
    { master_id = "trn_dr_slayer", parent_id = "rework_dr_slayer_group", leaves = {
        "trn_dr_slayer_dodge_damage_reduction",
    } },
    { master_id = "trn_we_waywatcher", parent_id = "rework_we_waywatcher_group", leaves = {
        "trn_we_waywatcher_headshot_attack_speed",
    } },
    { master_id = "trn_we_maidenguard", parent_id = "rework_we_maidenguard_group", leaves = {
        "trn_we_maidenguard_stamina_aura_range",
        "trn_we_maidenguard_focused_spirit_cooldown",
        "trn_we_maidenguard_push_block_stacks",
        "trn_we_maidenguard_power_on_dodge",
        "trn_we_maidenguard_max_health",
        "trn_we_maidenguard_max_ammo",
    } },
    { master_id = "trn_we_shade", parent_id = "rework_we_shade_group", leaves = {
        "trn_we_shade_infiltrate_duration",
        "trn_we_shade_stealth_parry",
        "trn_we_shade_critical_damage",
    } },
    { master_id = "trn_we_thornsister", parent_id = "rework_we_thornsister_group", leaves = {
        "trn_we_thornsister_team_aura_duration",
        "trn_we_thornsister_thp_funnel",
    } },
    { master_id = "trn_wh_bountyhunter", parent_id = "rework_wh_bountyhunter_group", leaves = {
        "trn_wh_bountyhunter_double_shotted_refund",
        "trn_wh_bountyhunter_job_well_done_stacks",
        "trn_wh_bountyhunter_just_reward_cooldown",
        "trn_wh_bountyhunter_blessed_kill",
    } },
    { master_id = "trn_wh_zealot", parent_id = "rework_wh_zealot_group", leaves = {
        "trn_wh_zealot_melee_power",
    } },
    { master_id = "trn_wh_priest", parent_id = "rework_wh_priest_group", leaves = {
        "trn_wh_priest_prayer_movement_speed",
    } },
    { master_id = "trn_bw_adept", parent_id = "rework_bw_adept_group", leaves = {
        "trn_bw_adept_famished_flames",
        "trn_bw_adept_ignite_damage_reduction",
        "trn_bw_adept_fires_from_ash",
        "trn_bw_adept_burning_vigour",
    } },
    { master_id = "trn_bw_scholar", parent_id = "rework_bw_scholar_group", leaves = {
        "trn_bw_scholar_martial_study",
    } },
    { master_id = "trn_bw_necromancer", parent_id = "rework_bw_necromancer_group", leaves = {
        "trn_bw_necromancer_spell_cast_ranged_power",
        "trn_bw_necromancer_critical_cleave",
        "trn_bw_necromancer_cursed_blood",
    } },
}

M.MASTER_IDS = {}
M.LEAF_IDS = {}
M.LEAVES_BY_MASTER = {}
M.MASTER_BY_LEAF = {}
M.PARENT_BY_MASTER = {}

for _, career in ipairs(M.CAREERS) do
    M.MASTER_IDS[#M.MASTER_IDS + 1] = career.master_id
    M.PARENT_BY_MASTER[career.master_id] = career.parent_id
    M.LEAVES_BY_MASTER[career.master_id] = career.leaves
    for _, leaf_id in ipairs(career.leaves) do
        M.LEAF_IDS[#M.LEAF_IDS + 1] = leaf_id
        M.MASTER_BY_LEAF[leaf_id] = career.master_id
    end
end

local function bool(value) return value and true or false end

function M.is_master(setting_id)
    return M.LEAVES_BY_MASTER[setting_id] ~= nil
end

function M.is_leaf(setting_id)
    return M.MASTER_BY_LEAF[setting_id] ~= nil
end

function M.plan_master(master_id, enabled, current)
    local leaves = M.LEAVES_BY_MASTER[master_id]
    if not leaves then return {} end
    current = current or {}
    local desired = bool(enabled)
    local changes = {}
    for _, leaf_id in ipairs(leaves) do
        if bool(current[leaf_id]) ~= desired then
            changes[#changes + 1] = { id = leaf_id, value = desired }
        end
    end
    if bool(current[master_id]) ~= desired then
        changes[#changes + 1] = { id = master_id, value = desired }
    end
    table.sort(changes, function(a, b) return a.id < b.id end)
    return changes
end

function M.derive_master(master_id, current)
    local leaves = M.LEAVES_BY_MASTER[master_id]
    if not leaves or #leaves == 0 then return false end
    current = current or {}
    for _, leaf_id in ipairs(leaves) do
        if not bool(current[leaf_id]) then return false end
    end
    return true
end

function M.plan_legacy_migration(current)
    current = current or {}
    local state = {}
    for id, value in pairs(current) do state[id] = bool(value) end
    local changes = {}
    for _, master_id in ipairs(M.MASTER_IDS) do
        if state[master_id] and not M.derive_master(master_id, state) then
            for _, change in ipairs(M.plan_master(master_id, true, state)) do
                if change.id ~= master_id then
                    changes[#changes + 1] = change
                    state[change.id] = change.value
                end
            end
        end
    end
    table.sort(changes, function(a, b) return a.id < b.id end)
    return changes
end

return M
