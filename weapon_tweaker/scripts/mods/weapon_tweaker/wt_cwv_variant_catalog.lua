-- WT-owned availability metadata for CWV definition entries (#368).
-- Runtime application still positively identifies ItemMasterList entries by
-- entry.cwv_variant == true; this bounded catalog exists so VMF can build the
-- settings tree before CWV registers its deferred ItemMasterList clones.
local ES = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }
local WH = { "wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest" }
local WH_STANDARD = { "wh_captain", "wh_bountyhunter", "wh_zealot" }
local ES_AND_WH_STANDARD = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
    "wh_captain", "wh_bountyhunter", "wh_zealot",
}
local DR = { "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer" }
local WE = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" }

return {
    -- #593 follow-up: when CWV owns the Axe+Shield family, WT exposes its
    -- Empire variant to the same standard Saltzpyre receivers that otherwise
    -- receive Bardin's native fallback. `conditional_careers` distinguishes
    -- WT's cross-receiver addition from CWV's four authored Kruber owners so a
    -- CWV disable/hot-reload can remove only WT's contribution.
    { key = "cwv_es_axe_shield", careers = ES_AND_WH_STANDARD, conditional_careers = WH_STANDARD },
    { key = "cwv_es_axe_shield_veteran", careers = ES_AND_WH_STANDARD, conditional_careers = WH_STANDARD },
    { key = "cwv_we_sword_shield", careers = WE },
    { key = "cwv_we_sword_shield_veteran", careers = WE },
    { key = "cwv_es_longsword", careers = ES },
    { key = "cwv_es_longsword_blackguard", careers = ES },
    { key = "cwv_es_longsword_shield", careers = ES },
    { key = "cwv_es_javelin", careers = ES },
    { key = "cwv_wh_javelin", careers = WH },
    { key = "cwv_es_outrider_grenade_launcher", careers = ES },
    { key = "cwv_es_crossbow", careers = ES },
    { key = "cwv_es_musket", careers = ES },
    { key = "cwv_es_musket_old", careers = ES },
    { key = "cwv_dr_priest_greathammer", careers = DR },
    { key = "cwv_es_priest_greathammer", careers = ES },
    { key = "cwv_es_warpriest_hammer", careers = ES },
    { key = "cwv_es_maul", careers = ES },
    { key = "cwv_es_poleaxe", careers = ES },
    { key = "cwv_es_rapier", careers = ES },
    { key = "cwv_es_dual_swords", careers = ES },
    { key = "cwv_es_sword_and_mace", careers = ES },
    { key = "cwv_es_cudgel", careers = ES },
    { key = "cwv_es_shortsword", careers = ES },
    { key = "cwv_es_dual_axes", careers = ES },
    { key = "cwv_wh_dual_axes", careers = WH },
    { key = "cwv_es_dual_maces", careers = ES },
    { key = "cwv_wh_dual_maces", careers = WH },
    { key = "cwv_es_dual_warpriest_hammers", careers = ES },
    { key = "cwv_es_warpriest_hammer_shield", careers = ES },
}
