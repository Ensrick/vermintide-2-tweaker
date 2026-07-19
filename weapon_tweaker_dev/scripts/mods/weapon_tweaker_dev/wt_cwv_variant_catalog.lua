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
local GREATAXE_DEFAULT = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
    "wh_captain", "wh_bountyhunter", "wh_zealot",
}
local GREATAXE_ALL = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
    "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
    "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
    "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
    "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}
local GREATAXE_CONDITIONAL = {
    "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
    "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
    "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
    "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}
local DAWI_ONE_HANDED_DEFAULT = { "dr_ranger", "dr_ironbreaker", "dr_slayer" }
local DAWI_SHIELD_DEFAULT = { "dr_ranger", "dr_ironbreaker" }
local DAWI_ONE_HANDED_CONDITIONAL = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
    "dr_engineer",
    "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
    "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
    "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}
local DAWI_SHIELD_CONDITIONAL = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
    "dr_slayer", "dr_engineer",
    "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
    "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
    "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}
local IMPERIAL_CROWBILL_DEFAULT = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
    "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
}
local IMPERIAL_CROWBILL_CONDITIONAL = {
    "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
    "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
    "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}
local DAWI_CROWBILL_DEFAULT = { "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer" }
local DAWI_CROWBILL_CONDITIONAL = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
    "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
    "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
    "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}

return {
    -- #593 follow-up: when CWV owns the Axe+Shield family, WT exposes its
    -- Empire variant to the same standard Saltzpyre receivers that otherwise
    -- receive Bardin's native fallback. `conditional_careers` distinguishes
    -- WT's cross-receiver addition from CWV's four authored Kruber owners so a
    -- CWV disable/hot-reload can remove only WT's contribution.
    { key = "cwv_es_axe_shield", careers = ES_AND_WH_STANDARD, conditional_careers = WH_STANDARD },
    { key = "cwv_es_axe_shield_veteran", careers = ES_AND_WH_STANDARD, conditional_careers = WH_STANDARD },
    -- #620 retired the separate Infantry Spear row. Native
    -- es_2h_heavy_spear owns both Hunter/Infantry Combat Styles and remains in
    -- WT's ordinary per-career availability map.
    { key = "cwv_we_sword_shield", careers = WE },
    { key = "cwv_we_sword_shield_veteran", careers = WE },
    -- #620 retired the standalone 2H Imperial Longsword / Black Guard rows.
    -- Native es_2h_sword owns Longsword Combat Style and their authored looks.
    { key = "cwv_es_longsword_shield", careers = ES },
    { key = "cwv_es_javelin", careers = ES },
    { key = "cwv_wh_javelin", careers = WH },
    -- #661: WT owns Saltzpyre access to these CWV Empire ranged/custom weapons.
    -- If a standard Witch Hunter career can equip one through WT, the effective
    -- template must also receive that career's `action_career_*` row; keeping
    -- them ES-only lets Bounty Hunter wield the item while Locked and Loaded
    -- silently fails.
    { key = "cwv_es_outrider_grenade_launcher", careers = ES_AND_WH_STANDARD,
      default_careers = ES, authored_careers = ES, conditional_careers = WH_STANDARD,
      effective_templates = {
          { name = "outrider_grenade_launcher_template",
            source_template = "dr_deus_01_template_1" },
      } },
    { key = "cwv_es_crossbow", careers = ES },
    { key = "cwv_es_musket", careers = ES },
    { key = "cwv_es_musket_old", careers = ES_AND_WH_STANDARD,
      default_careers = ES, authored_careers = ES, conditional_careers = WH_STANDARD,
      effective_templates = {
          { name = "old_musket_template", source_template = "handgun_template_1" },
          { name = "old_musket_template_melee",
            source_template = "two_handed_heavy_spears_template" },
      } },
    { key = "cwv_dr_priest_greathammer", careers = DR },
    { key = "cwv_es_priest_greathammer", careers = ES },
    { key = "cwv_es_warpriest_hammer", careers = ES },
    { key = "cwv_es_maul", careers = ES },
    -- #597: four authored Kruber owners are default-on. WT exposes every
    -- additional career as an explicit default-off opt-in.
    { key = "cwv_es_greataxe", careers = GREATAXE_ALL,
      default_careers = GREATAXE_DEFAULT,
      authored_careers = ES,
      conditional_careers = GREATAXE_CONDITIONAL },
    { key = "cwv_es_rapier", careers = ES },
    { key = "cwv_es_dual_swords", careers = ES },
    { key = "cwv_es_sword_and_mace", careers = ES },
    { key = "cwv_es_cudgel", careers = ES },
    { key = "cwv_es_shortsword", careers = ES },
    { key = "cwv_es_dual_axes", careers = ES },
    { key = "cwv_wh_dual_axes", careers = WH },
    { key = "cwv_es_dual_maces", careers = ES },
    { key = "cwv_wh_dual_maces", careers = WH },
    -- #602: CWV authors source-backed Bardin defaults. WT deliberately owns
    -- every other career as a default-off choice through the shared schema.
    { key = "cwv_dr_dawi_mace", careers = GREATAXE_ALL,
      default_careers = DAWI_ONE_HANDED_DEFAULT,
      authored_careers = DAWI_ONE_HANDED_DEFAULT,
      conditional_careers = DAWI_ONE_HANDED_CONDITIONAL },
    { key = "cwv_dr_dawi_mace_shield", careers = GREATAXE_ALL,
      default_careers = DAWI_SHIELD_DEFAULT,
      authored_careers = DAWI_SHIELD_DEFAULT,
      conditional_careers = DAWI_SHIELD_CONDITIONAL },
    { key = "cwv_dr_dawi_dual_maces", careers = GREATAXE_ALL,
      default_careers = DAWI_ONE_HANDED_DEFAULT,
      authored_careers = DAWI_ONE_HANDED_DEFAULT,
      conditional_careers = DAWI_ONE_HANDED_CONDITIONAL },
    -- Crowbill family: CWV authors the thematic owner groups; WT owns every
    -- additional receiver as an independent default-off option.
    { key = "cwv_es_imperial_crowbill", careers = GREATAXE_ALL,
      default_careers = IMPERIAL_CROWBILL_DEFAULT,
      authored_careers = IMPERIAL_CROWBILL_DEFAULT,
      conditional_careers = IMPERIAL_CROWBILL_CONDITIONAL },
    { key = "cwv_dr_dawi_crowbill", careers = GREATAXE_ALL,
      default_careers = DAWI_CROWBILL_DEFAULT,
      authored_careers = DAWI_CROWBILL_DEFAULT,
      conditional_careers = DAWI_CROWBILL_CONDITIONAL },
    { key = "cwv_es_dual_warpriest_hammers", careers = ES },
    { key = "cwv_es_warpriest_hammer_shield", careers = ES },
}
