-- Infantry Spear definition/tuning policy.
--
-- Kept engine-free so the exact balance contract can be exercised under the
-- repository's pinned Lua 5.1 test runtime. Runtime registration remains in
-- character_weapon_variants.lua, where DamageProfileTemplates/NetworkLookup
-- are available.
local M = {}

M.ITEM_KEY = "cwv_es_infantry_spear"
M.TEMPLATE_KEY = "cwv_infantry_spear_template"
M.BASE_WEAPON = "we_spear"
M.ITEM_TYPE = "cwv_es_infantry_spear"
M.SKIN_COMBINATION = "cwv_es_infantry_spear_skins"

M.SPEED_MULT = 0.85
M.DAMAGE_MULT = 1.075
M.STAGGER_MULT = 1.15
M.CLEAVE_MULT = 1.15

M.DEFAULT_CAREERS = { "es_mercenary", "es_huntsman", "es_knight" }
M.ALL_CAREERS = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
    "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
    "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
    "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
    "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}

M.SPEAR_SHIELD_SKINS = {
    "es_deus_01_skin_01",
    "es_deus_01_skin_02",
    "es_deus_01_skin_03",
    "es_deus_01_skin_01_runed",
    "es_deus_01_skin_02_runed",
    "es_deus_01_skin_03_runed",
    "es_deus_01_skin_magic",
}

-- ActionUtils.get_action_time_scale starts from action.anim_time_scale or 1,
-- and WeaponUnitExtension divides total/chain times by that result. Scaling
-- only attack-start and sweep actions therefore slows charge thresholds,
-- hit windows, animation playback, and recovery together, while leaving
-- block, ordinary push, wield, and inspect timings untouched.
function M.scaled_attack_time(kind, anim_time_scale)
    if kind ~= "melee_start" and kind ~= "sweep" then
        return anim_time_scale
    end
    return (anim_time_scale or 1) * M.SPEED_MULT
end

function M.default_career_set()
    local result = {}
    for _, career in ipairs(M.DEFAULT_CAREERS) do result[career] = true end
    return result
end

function M.conditional_careers()
    local authored = M.default_career_set()
    local result = {}
    for _, career in ipairs(M.ALL_CAREERS) do
        if not authored[career] then result[#result + 1] = career end
    end
    return result
end

return M
