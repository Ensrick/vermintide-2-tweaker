local mod = get_mod("wt")
local _cwv_ownership = mod:dofile("scripts/mods/weapon_tweaker/_wt_cwv_ownership")
local _cwv_present = _cwv_ownership.cwv_is_active(get_mod("character_weapon_variants"))
local _cwv_overlap_default = _cwv_present

local data = {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "weapon_availability",
                type = "group",
                sub_widgets = {
            {
                setting_id = "char_kruber",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "kruber_melee_group",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "melee_es_mercenary",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_es_mercenary_es_1h_flail", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_es_1h_mace", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_1h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_2h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_2h_heavy_spear", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_2h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_2h_sword_executioner", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_bastard_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_dual_wield_hammer_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_halberd", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_mace_shield", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_sword_shield", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_sword_shield_breton", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_es_deus_01", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_dr_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_dr_2h_cog_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_dr_2h_pick", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_wh_1h_axe", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_mercenary_wh_1h_falchion", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_mercenary_wh_dual_wield_axe_falchion", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_mercenary_wh_2h_billhook", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_wh_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_wh_dual_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_wh_fencing_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_wh_flail_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_wh_hammer_book", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_1h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_1h_spears_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_dual_wield_daggers", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_dual_wield_sword_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_dual_wield_swords", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_1h_crowbill", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_1h_flail_flaming", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_flame_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_ghost_scythe", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_es_huntsman",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_es_huntsman_es_1h_flail", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_es_1h_mace", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_1h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_2h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_2h_heavy_spear", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_2h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_2h_sword_executioner", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_bastard_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_dual_wield_hammer_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_halberd", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_mace_shield", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_sword_shield", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_deus_01", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_dr_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_dr_2h_cog_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_dr_2h_pick", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_wh_1h_axe", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_huntsman_wh_1h_falchion", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_huntsman_wh_dual_wield_axe_falchion", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_huntsman_wh_2h_billhook", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_wh_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_wh_dual_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_wh_fencing_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_wh_flail_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_wh_hammer_book", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_1h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_1h_spears_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_dual_wield_daggers", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_dual_wield_sword_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_dual_wield_swords", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_1h_crowbill", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_1h_flail_flaming", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_flame_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_ghost_scythe", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_es_knight",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_es_knight_es_1h_flail", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_es_1h_mace", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_1h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_2h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_2h_heavy_spear", type = "checkbox", default_value = _cwv_present },
                                    { setting_id = "unlock_es_knight_es_2h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_2h_sword_executioner", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_bastard_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_dual_wield_hammer_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_halberd", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_mace_shield", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_sword_shield", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_sword_shield_breton", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_es_deus_01", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_dr_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_dr_2h_cog_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_dr_2h_pick", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_wh_1h_axe", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_knight_wh_1h_falchion", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_knight_wh_dual_wield_axe_falchion", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_knight_wh_2h_billhook", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_wh_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_wh_dual_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_wh_fencing_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_wh_flail_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_wh_hammer_book", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_1h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_1h_spears_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_dual_wield_daggers", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_dual_wield_sword_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_dual_wield_swords", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_1h_crowbill", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_1h_flail_flaming", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_flame_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_ghost_scythe", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_es_questingknight",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_es_questingknight_es_1h_flail", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_es_1h_mace", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_questingknight_es_1h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_questingknight_es_2h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_questingknight_es_2h_heavy_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_es_2h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_questingknight_es_2h_sword_executioner", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_questingknight_es_bastard_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_questingknight_es_dual_wield_hammer_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_questingknight_es_halberd", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_es_mace_shield", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_questingknight_es_sword_shield", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_questingknight_es_sword_shield_breton", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_questingknight_es_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_dr_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_dr_2h_cog_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_dr_2h_pick", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_wh_1h_axe", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_questingknight_wh_1h_falchion", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_questingknight_wh_dual_wield_axe_falchion", type = "checkbox", default_value = _cwv_overlap_default },
                                    { setting_id = "unlock_es_questingknight_wh_2h_billhook", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_wh_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_wh_dual_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_wh_fencing_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_wh_flail_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_wh_hammer_book", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_1h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_1h_spears_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_dual_wield_daggers", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_dual_wield_sword_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_dual_wield_swords", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_1h_crowbill", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_1h_flail_flaming", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_flame_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_ghost_scythe", type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                    {
                        setting_id = "kruber_ranged_group",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "ranged_es_mercenary",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_es_mercenary_es_blunderbuss", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_handgun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_es_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_es_repeating_handgun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_dr_drake_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_dr_drakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_dr_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_wh_brace_of_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_wh_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_wh_crossbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_mercenary_wh_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_wh_repeating_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_shortbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_shortbow_hagbane", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_javelin", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_we_life_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_necromancy_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_skullstaff_beam", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_skullstaff_fireball", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_skullstaff_flamethrower", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_skullstaff_geiser", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_mercenary_bw_skullstaff_spear", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "ranged_es_huntsman",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_es_huntsman_es_blunderbuss", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_handgun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_longbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_es_repeating_handgun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_dr_drake_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_dr_drakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_dr_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_wh_brace_of_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_wh_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_wh_crossbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_huntsman_wh_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_wh_repeating_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_shortbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_shortbow_hagbane", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_javelin", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_we_life_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_necromancy_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_skullstaff_beam", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_skullstaff_fireball", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_skullstaff_flamethrower", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_skullstaff_geiser", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_huntsman_bw_skullstaff_spear", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "ranged_es_knight",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_es_knight_es_blunderbuss", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_handgun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_es_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_es_repeating_handgun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_dr_drake_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_dr_drakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_dr_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_wh_brace_of_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_wh_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_wh_crossbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_knight_wh_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_wh_repeating_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_shortbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_shortbow_hagbane", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_javelin", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_we_life_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_necromancy_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_skullstaff_beam", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_skullstaff_fireball", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_skullstaff_flamethrower", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_skullstaff_geiser", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_knight_bw_skullstaff_spear", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "ranged_es_questingknight",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_es_questingknight_es_blunderbuss", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_es_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_es_repeating_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_dr_drake_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_dr_drakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_dr_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_wh_brace_of_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_wh_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_wh_crossbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_es_questingknight_wh_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_wh_repeating_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_shortbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_shortbow_hagbane", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_javelin", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_we_life_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_necromancy_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_skullstaff_beam", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_skullstaff_fireball", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_skullstaff_flamethrower", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_skullstaff_geiser", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_es_questingknight_bw_skullstaff_spear", type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                },
            },
            {
                setting_id = "char_bardin",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "bardin_melee_group",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "melee_dr_ranger",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_dr_ranger_es_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_ranger_dr_1h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_1h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_2h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_2h_cog_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_2h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_2h_pick", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_dual_wield_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_ranger_dr_dual_wield_hammers", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_shield_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_shield_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_wh_1h_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_ranger_we_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_ranger_bw_1h_crowbill", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_dr_ironbreaker",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_dr_ironbreaker_es_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_ironbreaker_dr_1h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_1h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_2h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_2h_cog_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_2h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_2h_pick", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_dual_wield_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_ironbreaker_dr_dual_wield_hammers", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_shield_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_shield_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_wh_1h_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_ironbreaker_we_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_ironbreaker_bw_1h_crowbill", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_dr_slayer",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_dr_slayer_es_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_slayer_dr_1h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_slayer_dr_1h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_slayer_dr_2h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_slayer_dr_2h_cog_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_slayer_dr_2h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_slayer_dr_2h_pick", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_slayer_dr_dual_wield_axes", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_slayer_dr_dual_wield_hammers", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_slayer_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_slayer_dr_shield_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_slayer_wh_1h_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_slayer_we_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_slayer_bw_1h_crowbill", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_dr_engineer",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_dr_engineer_es_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_engineer_dr_1h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_1h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_2h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_2h_cog_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_2h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_2h_pick", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_dual_wield_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_engineer_dr_dual_wield_hammers", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_shield_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_shield_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_wh_1h_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_engineer_we_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_engineer_bw_1h_crowbill", type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                    {
                        setting_id = "bardin_ranged_group",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "ranged_dr_ranger",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_dr_ranger_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_ranger_dr_1h_throwing_axes", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_crossbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_handgun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_rakegun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_steam_pistol", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ranger_dr_deus_01", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "ranged_dr_ironbreaker",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_dr_ironbreaker_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_ironbreaker_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_ironbreaker_dr_crossbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_drake_pistol", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_drakegun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_handgun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_rakegun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_ironbreaker_dr_deus_01", type = "checkbox", default_value = true },
                                },
                            },
                            {
                                setting_id = "ranged_dr_slayer",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_dr_slayer_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_slayer_dr_1h_throwing_axes", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_slayer_dr_crossbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_slayer_dr_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_slayer_dr_rakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_slayer_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_slayer_dr_deus_01", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "ranged_dr_engineer",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_dr_engineer_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_engineer_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_engineer_dr_crossbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_dr_engineer_dr_drake_pistol", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_drakegun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_handgun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_rakegun", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_steam_pistol", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_dr_engineer_dr_deus_01", type = "checkbox", default_value = true },
                                },
                            },
                        },
                    },
                },
            },
            {
                setting_id = "char_kerillian",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "kerillian_melee_group",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "melee_we_waywatcher",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_we_waywatcher_es_1h_flail", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_2h_heavy_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_2h_sword_executioner", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_bastard_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_dual_wield_hammer_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_halberd", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_mace_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_sword_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_sword_shield_breton", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_1h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_2h_cog_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_2h_pick", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_dual_wield_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_dual_wield_hammers", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_1h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_1h_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_1h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_2h_billhook", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_dual_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_dual_wield_axe_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_fencing_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_flail_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_hammer_book", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_hammer_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_we_1h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_we_1h_spears_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_we_1h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_we_2h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_we_2h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_we_dual_wield_daggers", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_we_dual_wield_sword_dagger", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_we_dual_wield_swords", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_we_spear", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_bw_1h_crowbill", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_bw_1h_flail_flaming", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_bw_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_bw_flame_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_bw_ghost_scythe", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_we_maidenguard",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_we_maidenguard_es_1h_flail", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_2h_heavy_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_2h_sword_executioner", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_bastard_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_dual_wield_hammer_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_halberd", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_mace_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_sword_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_sword_shield_breton", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_1h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_2h_cog_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_2h_pick", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_dual_wield_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_dual_wield_hammers", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_1h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_1h_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_1h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_2h_billhook", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_dual_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_dual_wield_axe_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_fencing_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_flail_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_hammer_book", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_hammer_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_we_1h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_1h_spears_shield", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_1h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_2h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_2h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_dual_wield_daggers", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_dual_wield_sword_dagger", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_dual_wield_swords", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_spear", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_bw_1h_crowbill", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_bw_1h_flail_flaming", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_bw_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_bw_flame_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_bw_ghost_scythe", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_we_shade",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_we_shade_es_1h_flail", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_2h_heavy_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_2h_sword_executioner", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_bastard_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_dual_wield_hammer_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_halberd", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_mace_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_sword_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_sword_shield_breton", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_1h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_2h_cog_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_2h_pick", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_dual_wield_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_dual_wield_hammers", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_1h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_1h_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_1h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_2h_billhook", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_dual_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_dual_wield_axe_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_fencing_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_flail_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_hammer_book", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_hammer_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_we_1h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_1h_spears_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_we_1h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_2h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_2h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_dual_wield_daggers", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_dual_wield_sword_dagger", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_dual_wield_swords", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_spear", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_bw_1h_crowbill", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_bw_1h_flail_flaming", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_bw_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_bw_flame_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_bw_ghost_scythe", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_we_thornsister",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_we_thornsister_es_1h_flail", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_2h_heavy_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_2h_sword_executioner", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_bastard_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_dual_wield_hammer_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_halberd", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_mace_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_sword_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_sword_shield_breton", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_1h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_2h_cog_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_2h_pick", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_dual_wield_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_dual_wield_hammers", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_1h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_1h_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_1h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_2h_billhook", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_dual_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_dual_wield_axe_falchion", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_fencing_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_flail_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_hammer_book", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_hammer_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_we_1h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_1h_spears_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_we_1h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_2h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_2h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_dual_wield_daggers", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_dual_wield_sword_dagger", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_dual_wield_swords", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_spear", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_bw_1h_crowbill", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_bw_1h_flail_flaming", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_bw_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_bw_flame_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_bw_ghost_scythe", type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                    {
                        setting_id = "kerillian_ranged_group",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "ranged_we_waywatcher",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_we_waywatcher_es_blunderbuss", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_es_repeating_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_crossbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_drake_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_drakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_rakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_brace_of_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_crossbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_wh_repeating_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_we_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_we_javelin", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_we_longbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_we_shortbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_we_shortbow_hagbane", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_we_deus_01", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_waywatcher_bw_skullstaff_beam", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_bw_skullstaff_fireball", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_bw_skullstaff_flamethrower", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_bw_skullstaff_geiser", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_bw_skullstaff_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_bw_necromancy_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_waywatcher_bw_deus_01", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "ranged_we_maidenguard",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_we_maidenguard_es_blunderbuss", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_es_repeating_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_crossbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_drake_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_drakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_rakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_brace_of_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_crossbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_wh_repeating_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_we_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_we_javelin", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_longbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_shortbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_shortbow_hagbane", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_we_deus_01", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_maidenguard_bw_skullstaff_beam", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_bw_skullstaff_fireball", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_bw_skullstaff_flamethrower", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_bw_skullstaff_geiser", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_bw_skullstaff_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_bw_necromancy_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_maidenguard_bw_deus_01", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "ranged_we_shade",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_we_shade_es_blunderbuss", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_es_repeating_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_crossbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_drake_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_drakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_rakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_brace_of_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_crossbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_wh_repeating_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_we_crossbow_repeater", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_javelin", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_longbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_shortbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_shortbow_hagbane", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_we_deus_01", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_shade_bw_skullstaff_beam", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_bw_skullstaff_fireball", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_bw_skullstaff_flamethrower", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_bw_skullstaff_geiser", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_bw_skullstaff_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_bw_necromancy_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_shade_bw_deus_01", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "ranged_we_thornsister",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_we_thornsister_es_blunderbuss", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_es_repeating_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_crossbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_drake_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_drakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_rakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_brace_of_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_crossbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_wh_repeating_pistols", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_we_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_we_javelin", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_life_staff", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_longbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_shortbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_shortbow_hagbane", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_we_deus_01", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_we_thornsister_bw_skullstaff_beam", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_bw_skullstaff_fireball", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_bw_skullstaff_flamethrower", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_bw_skullstaff_geiser", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_bw_skullstaff_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_bw_necromancy_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_we_thornsister_bw_deus_01", type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                },
            },
            {
                setting_id = "char_saltzpyre",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "saltzpyre_melee_group",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "melee_wh_captain",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_wh_captain_es_1h_flail", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_es_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_2h_heavy_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_halberd", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_bastard_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_2h_sword_executioner", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_dual_wield_hammer_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_mace_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_sword_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_sword_shield_breton", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_dr_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_dr_2h_cog_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_dr_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_dr_2h_pick", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_wh_1h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_wh_1h_falchion", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_wh_1h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_wh_2h_billhook", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_wh_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_wh_2h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_wh_dual_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_wh_dual_wield_axe_falchion", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_wh_fencing_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_we_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_1h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_dual_wield_daggers", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_dual_wield_swords", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_dual_wield_sword_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_1h_spears_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_1h_crowbill", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_flame_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_ghost_scythe", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_wh_bountyhunter",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_wh_bountyhunter_es_1h_flail", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_es_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_2h_heavy_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_halberd", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_bastard_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_2h_sword_executioner", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_dual_wield_hammer_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_mace_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_sword_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_sword_shield_breton", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_dr_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_dr_2h_cog_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_dr_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_dr_2h_pick", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_wh_1h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_wh_1h_falchion", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_wh_1h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_wh_2h_billhook", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_wh_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_wh_2h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_wh_dual_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_wh_dual_wield_axe_falchion", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_wh_fencing_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_we_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_1h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_dual_wield_daggers", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_dual_wield_swords", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_dual_wield_sword_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_1h_spears_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_1h_crowbill", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_flame_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_ghost_scythe", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_wh_zealot",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_wh_zealot_es_1h_flail", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_es_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_2h_heavy_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_halberd", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_bastard_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_2h_sword_executioner", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_dual_wield_hammer_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_mace_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_sword_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_sword_shield_breton", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_dr_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_dr_2h_cog_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_dr_2h_hammer", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_dr_2h_pick", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_dr_shield_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_wh_1h_axe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_1h_falchion", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_1h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_2h_billhook", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_2h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_2h_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_dual_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_dual_wield_axe_falchion", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_fencing_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_we_1h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_1h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_2h_axe", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_2h_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_dual_wield_daggers", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_dual_wield_swords", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_dual_wield_sword_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_1h_spears_shield", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_1h_crowbill", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_1h_mace", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_dagger", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_flame_sword", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_ghost_scythe", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "melee_wh_priest",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_wh_priest_es_1h_flail", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_priest_wh_1h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_priest_wh_2h_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_priest_wh_dual_hammer", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_priest_wh_flail_shield", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_priest_wh_hammer_book", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_priest_wh_hammer_shield", type = "checkbox", default_value = true },
                                },
                            },
                        },
                    },
                    {
                        setting_id = "saltzpyre_ranged_group",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "ranged_wh_captain",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_wh_captain_es_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_blunderbuss", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_es_repeating_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_dr_rakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_dr_drake_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_dr_drakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_dr_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_wh_brace_of_pistols", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_wh_crossbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_wh_crossbow_repeater", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_wh_repeating_pistols", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_wh_deus_01", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_captain_we_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_shortbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_shortbow_hagbane", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_we_javelin", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_skullstaff_beam", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_skullstaff_fireball", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_skullstaff_flamethrower", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_skullstaff_geiser", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_skullstaff_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_necromancy_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_captain_bw_deus_01", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "ranged_wh_bountyhunter",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_wh_bountyhunter_es_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_blunderbuss", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_es_repeating_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_dr_rakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_dr_drake_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_dr_drakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_dr_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_wh_brace_of_pistols", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_wh_crossbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_wh_crossbow_repeater", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_wh_repeating_pistols", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_wh_deus_01", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_bountyhunter_we_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_shortbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_shortbow_hagbane", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_we_javelin", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_skullstaff_beam", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_skullstaff_fireball", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_skullstaff_flamethrower", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_skullstaff_geiser", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_skullstaff_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_necromancy_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_bountyhunter_bw_deus_01", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "ranged_wh_zealot",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_wh_zealot_es_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_blunderbuss", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_es_repeating_handgun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_dr_1h_throwing_axes", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_dr_rakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_dr_drake_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_dr_drakegun", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_dr_steam_pistol", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_dr_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_wh_brace_of_pistols", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_crossbow", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_crossbow_repeater", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_repeating_pistols", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_wh_deus_01", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_wh_zealot_we_crossbow_repeater", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_longbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_shortbow", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_shortbow_hagbane", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_deus_01", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_we_javelin", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_skullstaff_beam", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_skullstaff_fireball", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_skullstaff_flamethrower", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_skullstaff_geiser", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_skullstaff_spear", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_necromancy_staff", type = "checkbox", default_value = false },
                                    { setting_id = "unlock_wh_zealot_bw_deus_01", type = "checkbox", default_value = false },
                                },
                            },
                            -- ranged_wh_priest group intentionally absent — see
                            -- feedback_vt2_no_bows_on_warrior_priest. Priest has zero
                            -- cross-character ranged unlocks; vanilla wh_brace_of_pistols
                            -- is his only ranged option in this mod.
                        },
                    },
                },
            },
            {
                setting_id = "char_sienna",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "sienna_melee_group",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "melee_bw_adept",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_bw_adept_bw_1h_crowbill", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_adept_bw_1h_flail_flaming", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_adept_bw_1h_mace", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_adept_bw_dagger", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_adept_bw_flame_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_adept_bw_ghost_scythe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_adept_bw_sword", type = "checkbox", default_value = true },
                                },
                            },
                            {
                                setting_id = "melee_bw_scholar",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_bw_scholar_bw_1h_crowbill", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_scholar_bw_1h_flail_flaming", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_scholar_bw_1h_mace", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_scholar_bw_dagger", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_scholar_bw_flame_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_scholar_bw_ghost_scythe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_scholar_bw_sword", type = "checkbox", default_value = true },
                                },
                            },
                            {
                                setting_id = "melee_bw_unchained",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_bw_unchained_bw_1h_crowbill", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_unchained_bw_1h_flail_flaming", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_unchained_bw_1h_mace", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_unchained_bw_dagger", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_unchained_bw_flame_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_unchained_bw_ghost_scythe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_unchained_bw_sword", type = "checkbox", default_value = true },
                                },
                            },
                            {
                                setting_id = "melee_bw_necromancer",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_bw_necromancer_bw_1h_crowbill", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_necromancer_bw_1h_flail_flaming", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_necromancer_bw_1h_mace", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_necromancer_bw_dagger", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_necromancer_bw_flame_sword", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_necromancer_bw_ghost_scythe", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_necromancer_bw_sword", type = "checkbox", default_value = true },
                                },
                            },
                        },
                    },
                    {
                        setting_id = "sienna_ranged_group",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "ranged_bw_adept",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_bw_adept_bw_skullstaff_beam", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_adept_bw_skullstaff_fireball", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_adept_bw_skullstaff_flamethrower", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_adept_bw_skullstaff_geiser", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_adept_bw_skullstaff_spear", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_adept_bw_deus_01", type = "checkbox", default_value = true },
                                },
                            },
                            {
                                setting_id = "ranged_bw_scholar",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_bw_scholar_bw_skullstaff_beam", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_scholar_bw_skullstaff_fireball", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_scholar_bw_skullstaff_flamethrower", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_scholar_bw_skullstaff_geiser", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_scholar_bw_skullstaff_spear", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_scholar_bw_deus_01", type = "checkbox", default_value = true },
                                },
                            },
                            {
                                setting_id = "ranged_bw_unchained",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_bw_unchained_bw_skullstaff_beam", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_unchained_bw_skullstaff_fireball", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_unchained_bw_skullstaff_flamethrower", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_unchained_bw_skullstaff_geiser", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_unchained_bw_skullstaff_spear", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_unchained_bw_deus_01", type = "checkbox", default_value = true },
                                },
                            },
                            {
                                setting_id = "ranged_bw_necromancer",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "unlock_bw_necromancer_bw_necromancy_staff", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_necromancer_bw_skullstaff_beam", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_necromancer_bw_skullstaff_fireball", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_necromancer_bw_skullstaff_geiser", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_necromancer_bw_skullstaff_spear", type = "checkbox", default_value = true },
                                    { setting_id = "unlock_bw_necromancer_bw_deus_01", type = "checkbox", default_value = true },
                                },
                            },
                        },
                    },
                },
            },
                },
            },
            -- POTENTIAL BUG (LOW): the following user-facing toggle widgets
            -- are advertised in the localization file but NEVER referenced by
            -- mod:get() in the code:
            --   enable_weapon_unlocks_core
            --   enable_weapon_runtime_guards
            --   enable_weapon_wield_slot_guard
            --   enable_weapon_create_equipment_guard
            --   enable_weapon_career_action_injection
            --   force_bretonnian_shield_unlock
            -- These are leftover localization keys from the legacy monolithic
            -- "Tweaker" mod. Either add widget entries (if these toggles should
            -- still exist) or remove the orphan localization entries.
            -- The legacy `debug` and `enable_weapon_debug_logging` widgets
            -- were retired in v0.12.74-dev. Their values (if set by old
            -- users) are migrated into the new `wt_debug_mode` toggle at
            -- mod load (one-time, guarded by the
            -- `wt_debug_migration_v1` sentinel — see
            -- `weapon_tweaker.lua` `_migrate_legacy_debug_setting`).
            {
                setting_id = "weapon_overrides",
                type = "group",
                -- Leaves sorted A->Z by display label (repo standing sort rule).
                sub_widgets = {
                    { setting_id = "authentic_brace_of_pistols", type = "checkbox", default_value = false },
                    { setting_id = "wt_one_hand_axe_cleave_nerf", type = "checkbox", default_value = false },
                    { setting_id = "wt_cog_hammer_heavy_speed_nerf", type = "checkbox", default_value = false },
                    { setting_id = "wt_dual_axes_cleave", type = "checkbox", default_value = true },
                    { setting_id = "wt_dual_axes_light_crit", type = "checkbox", default_value = true },
                    { setting_id = "wt_greataxe_light_crit", type = "checkbox", default_value = true },
                    { setting_id = "wt_mace_sword_speed_nerf", type = "checkbox", default_value = false },
                    { setting_id = "wt_bolt_staff_primary_overcharge_reduction", type = "checkbox", default_value = false },
                    -- Explicit tooltip: the loc key ends in _tooltip, which VMF does NOT
                    -- auto-resolve (auto path only tries <setting_id>_description).
                    { setting_id = "wt_brett_sword_shield_buff", type = "checkbox", default_value = false, tooltip = "wt_brett_sword_shield_buff_tooltip" },
                    -- Issue #348: revert 6.11.0 Kruber Empire 1h sword push-attack combo.
                    -- Uses the auto-resolved <setting_id>_description loc key for its tooltip.
                    { setting_id = "wt_revert_1h_sword_push_combo", type = "checkbox", default_value = false },
                    { setting_id = "moonfire_aoe_revert", type = "checkbox", default_value = false },
                    { setting_id = "wt_priest_punch_buff", type = "checkbox", default_value = false },
                },
            },
--[==[ BIG REBALANCE WIDGETS — ON ICE (bt retired 2026-06-08). The whole br_master
-- menu group is commented out so the inert BR toggles don't appear in the VMF menu.
-- To restore, delete this opener line and the closing long-comment marker below.
            -- ============================================================
            -- Retired Big Rebalance identifiers. This entire block remains
            -- hidden so old settings files retain stable br_* keys; there is
            -- no implementation or registration owner behind these widgets.
            -- ============================================================
            {
                setting_id = "br_master",
                type = "group",
                sub_widgets = {
                    -- Historical master identifier; intentionally inactive.
                    -- that mod and enable its master to make these wt sub-toggles
                    -- functional. A placeholder text widget would be nice here
                    -- but VMF doesn't expose one; leaving the explanation in
                    -- localization (see br_master tooltip on the group).
                    {
                        setting_id = "br_melee",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "br_melee_1h_hammer",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_1h_hammer_dodge_count",         type = "checkbox", default_value = false },
                                    { setting_id = "br_1h_hammer_light_down_speed",    type = "checkbox", default_value = false },
                                    { setting_id = "br_1h_hammer_heavy_gs_profile",    type = "checkbox", default_value = false },
                                    { setting_id = "br_1h_hammer_heavy_range",         type = "checkbox", default_value = false },
                                    { setting_id = "br_1h_hammer_tome_rework",         type = "checkbox", default_value = false },
                                    { setting_id = "br_1h_hammer_wizard_rework",       type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_melee_2h_hammer",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_2h_hammer_emp",     type = "checkbox", default_value = false },
                                    { setting_id = "br_2h_hammer_priest",  type = "checkbox", default_value = false },
                                    { setting_id = "br_cog_rework",        type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_melee_1h_sword",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_1h_sword_template1_range", type = "checkbox", default_value = false },
                                    { setting_id = "br_flaming_sword_rework",     type = "checkbox", default_value = false },
                                    { setting_id = "br_falchion_heavy",           type = "checkbox", default_value = false },
                                    { setting_id = "br_we_1h_sword",              type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_melee_2h_sword",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_exec_sword_speed",  type = "checkbox", default_value = false },
                                    { setting_id = "br_2h_sword_template1", type = "checkbox", default_value = false },
                                    { setting_id = "br_bastard_sword",     type = "checkbox", default_value = false },
                                    { setting_id = "br_we_2h_sword",       type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_melee_polearm",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_2h_spear_emp",         type = "checkbox", default_value = false },
                                    { setting_id = "br_halberd_tb_profiles",  type = "checkbox", default_value = false },
                                    { setting_id = "br_elf_spear_rework",     type = "checkbox", default_value = false },
                                    { setting_id = "br_1h_spearshield_chain", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_melee_dual",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_dw_mace_sword",      type = "checkbox", default_value = false },
                                    { setting_id = "br_1h_dagger_pushstab", type = "checkbox", default_value = false },
                                    { setting_id = "br_dw_sword_dagger",    type = "checkbox", default_value = false },
                                    { setting_id = "br_dw_swords_speed",    type = "checkbox", default_value = false },
                                    { setting_id = "br_dw_daggers",         type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_melee_mace_axe",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_1h_axe",          type = "checkbox", default_value = false },
                                    { setting_id = "br_2h_pick",         type = "checkbox", default_value = false },
                                    { setting_id = "br_2h_axe",          type = "checkbox", default_value = false },
                                    { setting_id = "br_dw_axes",         type = "checkbox", default_value = false },
                                    { setting_id = "br_1h_flail_rework", type = "checkbox", default_value = false },
                                    { setting_id = "br_flaming_flail",   type = "checkbox", default_value = false },
                                    { setting_id = "br_crowbill",        type = "checkbox", default_value = false },
                                    { setting_id = "br_glaive",          type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_melee_shield",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_flail_shield",           type = "checkbox", default_value = false },
                                    { setting_id = "br_axe_shield_crit",        type = "checkbox", default_value = false },
                                    { setting_id = "br_1h_hammer_shield_heavy", type = "checkbox", default_value = false },
                                    { setting_id = "br_sword_shield_emp",       type = "checkbox", default_value = false },
                                    { setting_id = "br_shield_slam_replace",    type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                    {
                        setting_id = "br_ranged",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "br_ranged_bow",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_bow_weapon_type_flag",    type = "checkbox", default_value = false },
                                    { setting_id = "br_bow_ammo_caps",           type = "checkbox", default_value = false },
                                    { setting_id = "br_shortbow_shotgun_rework", type = "checkbox", default_value = false },
                                    { setting_id = "br_longbow_emp_rework",      type = "checkbox", default_value = false },
                                    { setting_id = "br_repeater_xbow_elf",       type = "checkbox", default_value = false },
                                    { setting_id = "br_throwing_axes",           type = "checkbox", default_value = false },
                                    { setting_id = "br_moonbow_rework",          type = "checkbox", default_value = false },
                                    { setting_id = "br_moonbow_cosmetic_puff",   type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_ranged_gun",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_repeater_handgun",        type = "checkbox", default_value = false },
                                    { setting_id = "br_engineer_deus_balanced",  type = "checkbox", default_value = false },
                                    { setting_id = "br_brace_of_pistols_clip",   type = "checkbox", default_value = false },
                                    { setting_id = "br_dr_deus_ammo",            type = "checkbox", default_value = false },
                                    { setting_id = "br_steam_pistol",            type = "checkbox", default_value = false },
                                    { setting_id = "br_grudgeraker_shotgun",     type = "checkbox", default_value = false },
                                    { setting_id = "br_blunderbuss_shotgun",     type = "checkbox", default_value = false },
                                    { setting_id = "br_drakepistol_speed_chains", type = "checkbox", default_value = false },
                                    { setting_id = "br_drakegun_dot_interval",   type = "checkbox", default_value = false },
                                    { setting_id = "br_rakeshot_spread",         type = "checkbox", default_value = false },
                                    { setting_id = "br_handgun_xbow_reload",     type = "checkbox", default_value = false },
                                    { setting_id = "br_repeater_pistol_reload",  type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_ranged_staff",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_staff_magma",         type = "checkbox", default_value = false },
                                    { setting_id = "br_staff_fireball",      type = "checkbox", default_value = false },
                                    { setting_id = "br_staff_conflag_spear", type = "checkbox", default_value = false },
                                    { setting_id = "br_staff_beam_shotgun",  type = "checkbox", default_value = false },
                                    { setting_id = "br_staff_flamethrower",  type = "checkbox", default_value = false },
                                    { setting_id = "br_staff_life_vortex",   type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_ranged_career",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_gk_career_weapon",         type = "checkbox", default_value = false },
                                    { setting_id = "br_engineer_crank_gun",       type = "checkbox", default_value = false },
                                    { setting_id = "br_bardin_survival_ale",      type = "checkbox", default_value = false },
                                    { setting_id = "br_we_ww_trueflight",         type = "checkbox", default_value = false },
                                    { setting_id = "br_sienna_scholar_skullshot", type = "checkbox", default_value = false },
                                    { setting_id = "br_vc_bh_shotgun_profile",    type = "checkbox", default_value = false },
                                    { setting_id = "br_vc_wp_nuke",               type = "checkbox", default_value = false },
                                    { setting_id = "br_slayer_leap_landing",      type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                    {
                        setting_id = "br_dpt",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "br_dpt_blunt",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_dpt_light_blunt_tank",            type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_heavy_blunt_tank",            type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_heavy_blunt_smiter_charged",  type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_burning_blunt",               type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_dpt_slash",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_dpt_light_slash_linesman_finesse", type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_light_slash_smiter",           type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_med_slash_tank_1h",            type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_med_slash_linesman_executioner", type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_heavy_slash_tank",             type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_med_slash_linesman_base",      type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_med_slash_linesman_spear",     type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_heavy_slash_polearm",          type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_axe_linesman",                 type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_med_slash_smiter_2h",          type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_heavy_slash_smiter",           type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_med_spear_smiter_stab",        type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_light_slash_elf",              type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_light_slash_line_dual_med",    type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_med_spear_thorn_skin_etc",     type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_dpt_pointy",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_dpt_light_pointy_smiter",        type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_med_pointy_smiter_flat_1h",  type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id = "br_dpt_ranged",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "br_dpt_staff_fireball_charged",   type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_fireball_explosion",       type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_soul_rip",                 type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_shot_machinegun_shieldbreak", type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_shot_carbine",             type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_crossbow_bolt_repeating",  type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_dr_deus",                  type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_thrown_javelin",           type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_shot_sniper_pistol_dropoff", type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_shot_duckfoot",            type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_geiser",                   type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_drake_pistol",             type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_beam_shot",                type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_fire_spear_3",             type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_arrow_machinegun",         type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_burning_dot_firegrenade",  type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_frag_grenade",             type = "checkbox", default_value = false },
                                    { setting_id = "br_dpt_throwing_axe_hs",          type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                    {
                        setting_id = "br_hooks",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "br_hook_flamethrower_cone", type = "checkbox", default_value = false },
                            { setting_id = "br_hook_beam_aim_toggle",   type = "checkbox", default_value = false },
                            { setting_id = "br_hook_trueflight_start",  type = "checkbox", default_value = false },
                            { setting_id = "br_hook_trueflight_fire",   type = "checkbox", default_value = false },
                            { setting_id = "br_hook_shield_slam",       type = "checkbox", default_value = false },
                        },
                    },
                    {
                        setting_id = "br_wield",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "br_wield_es_2h_heavy_spear",  type = "checkbox", default_value = false },
                            { setting_id = "br_wield_wh_1h_falchion",     type = "checkbox", default_value = false },
                            { setting_id = "br_wield_wh_2h_sword",        type = "checkbox", default_value = false },
                            { setting_id = "br_wield_wh_1h_axe",          type = "checkbox", default_value = false },
                            { setting_id = "br_wield_wh_dw_axe_falchion", type = "checkbox", default_value = false },
                        },
                    },
                    {
                        setting_id = "br_misc",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "br_misc_chaos_raider_special_staggers", type = "checkbox", default_value = false },
                            { setting_id = "br_misc_tank_hit_mass_plague_monk",     type = "checkbox", default_value = false },
                            { setting_id = "br_misc_status_dodge_count",            type = "checkbox", default_value = false },
                            { setting_id = "br_misc_weapons_meta_init",             type = "checkbox", default_value = false },
                        },
                    },
                },
            },
]==]
            -- v0.12.140-dev: enable_dev_anim_picker is now a MASTER TOGGLE — its
            -- picker rows are appended as its `sub_widgets` after the static
            -- tree (below), so VMF reveals the whole picker menu LIVE on toggle (no
            -- restart). See the append block below.
            -- (enable_debug_logging removed v0.12.176-dev — #169)
        },
    },
}

-- Dev tooling widget trees (appended after the static widget tree).
--
-- v0.12.140-dev: the 3P Anim-Set Chooser is now a MASTER-TOGGLE → sub_widgets
-- surface (reference_vmf_native_master_toggle_submenu). build_widget_tree() returns
-- an ARRAY of per-Kruber-port group widgets (never nil); we nest that array as the
-- `sub_widgets` of an `enable_dev_anim_picker` checkbox so VMF's per-frame
-- visibility loop (vmf_options_view.lua:4461-4463) reveals/hides the entire picker
-- menu LIVE when the box is toggled — no game restart. The children are built
-- unconditionally at boot (Kruber-only lightweight build, no ~11 MB leak) so
-- they're present in the tree for VMF to reveal. An empty sub_widgets array is
-- tolerated on a checkbox (only type="group" rejects zero children), but we guard
-- anyway: attach sub_widgets only when non-empty, else fall back to a bare checkbox.
local _wt_dev_anim_picker_data = mod:dofile("scripts/mods/weapon_tweaker/wt_dev_anim_picker")
local _wt_dev_hold_pose_data   = mod:dofile("scripts/mods/weapon_tweaker/wt_dev_hold_pose")
local _anim_rows = _wt_dev_anim_picker_data.build_widget_tree()  -- array (may be empty, never nil)

local _picker_checkbox = {
    setting_id    = "enable_dev_anim_picker",
    type          = "checkbox",
    default_value = false,
    tooltip       = "enable_dev_anim_picker_tooltip",
}
if _anim_rows and #_anim_rows > 0 then
    _picker_checkbox.sub_widgets = _anim_rows
end
data.options.widgets[#data.options.widgets + 1] = _picker_checkbox

-- Hold-pose dev tree is untouched — it still returns ONE top-level group widget
-- (or nil when its dynamic catalog is empty); nil-check before appending.
local _hp_tree = _wt_dev_hold_pose_data.build_widget_tree()
if _hp_tree then data.options.widgets[#data.options.widgets + 1] = _hp_tree end

-- #368: VMF builds this file before CWV performs its deferred in-keep clone
-- registration, so the menu uses WT's bounded definition catalog. The runtime
-- writer still enumerates ItemMasterList and only touches positive
-- `cwv_variant == true` entries. Persisted values override these defaults.
if _cwv_present then
    local catalog = mod:dofile("scripts/mods/weapon_tweaker/wt_cwv_variant_catalog")
    local policy = mod:dofile("scripts/mods/weapon_tweaker/_wt_cwv_availability_policy")
    local rows = policy.build_widgets(catalog)
    if #rows > 0 then
        data.options.widgets[1].sub_widgets[#data.options.widgets[1].sub_widgets + 1] = {
            setting_id = "cwv_variant_availability",
            type = "group",
            sub_widgets = rows,
        }
    end
end

-- ---------------------------------------------------------------------------
-- Weapon Availability: normalize row order (#179, #408).
-- ---------------------------------------------------------------------------
-- Reorder every per-career `melee_<career>` / `ranged_<career>` leaf group's
-- `unlock_<career>_<weapon>` checkboxes by their player-facing English label.
-- Resolve that label from the raw localization DATA published before VMF menu
-- registration (#197 / LOCALIZATION_STANDARD section 12), never via
-- `mod:localize`, and strip every leading dev-status tag so `[working] Kruber:
-- Halberd` sorts under K. The setting id is the deterministic tie-break/fallback.
--
-- Mixed leaf groups are handled too: only unlock rows are gathered/sorted and
-- written back into their original unlock-row slots, so an unrelated child can
-- no longer make the old `all_unlock` guard silently skip the entire group
-- (#408). Scoped strictly to the `weapon_availability` subtree; setting_ids and
-- default values are unchanged, so persisted settings are unaffected.
local function _availability_display_sort_key(setting_id)
    local raw = mod._wt_loc_raw
    local entry = type(raw) == "table" and raw[setting_id]
    local label = type(entry) == "table" and entry.en
    if type(label) ~= "string" or label == "" then return setting_id end
    while true do
        local clean, n = label:gsub("^%s*%b[]%s*", "", 1)
        label = clean
        if n == 0 then break end
    end
    return string.lower(label) .. "\0" .. setting_id
end

local _availability_rows_sorted = 0

local function _sort_availability_rows(node)
    if type(node) ~= "table" then return end
    local sid = node.setting_id
    if type(sid) == "string" and type(node.sub_widgets) == "table" then
        local career = sid:match("^melee_(.+)$") or sid:match("^ranged_(.+)$")
        if career then
            local prefix = "unlock_" .. career .. "_"
            local unlock_rows = {}
            local unlock_slots = {}
            for i, w in ipairs(node.sub_widgets) do
                local wsid = type(w) == "table" and w.setting_id
                if type(wsid) == "string" and wsid:sub(1, #prefix) == prefix then
                    unlock_rows[#unlock_rows + 1] = w
                    unlock_slots[#unlock_slots + 1] = i
                end
            end
            if #unlock_rows > 1 then
                table.sort(unlock_rows, function(a, b)
                    return _availability_display_sort_key(a.setting_id)
                        < _availability_display_sort_key(b.setting_id)
                end)
                for i, slot in ipairs(unlock_slots) do
                    node.sub_widgets[slot] = unlock_rows[i]
                end
                _availability_rows_sorted = _availability_rows_sorted + #unlock_rows
            end
        end
    end
    if type(node.sub_widgets) == "table" then
        for _, child in ipairs(node.sub_widgets) do
            _sort_availability_rows(child)
        end
    end
end

for _, top in ipairs(data.options.widgets) do
    if type(top) == "table" and top.setting_id == "weapon_availability" then
        _sort_availability_rows(top)
    end
end

if not mod._wt408_availability_sort_logged then
    mod._wt408_availability_sort_logged = true
    printf("[wt:408] applied: sorted %d Weapon Availability rows by tag-stripped display name",
        _availability_rows_sorted)
end

-- #593: menu ownership must match runtime ownership. VMF freezes this tree at
-- load, so remove the Bardin fallback rows when active CWV will supply the
-- Empire variants. Saved fallback values are untouched and return next load
-- when CWV is absent/disabled.
if _cwv_present then
    local hidden = {
        unlock_es_mercenary_dr_shield_axe = true,
        unlock_es_huntsman_dr_shield_axe = true,
        unlock_es_knight_dr_shield_axe = true,
        unlock_es_questingknight_dr_shield_axe = true,
        unlock_wh_captain_dr_shield_axe = true,
        unlock_wh_bountyhunter_dr_shield_axe = true,
        unlock_wh_zealot_dr_shield_axe = true,
        -- #597: the CWV Greataxe is the canonical Kruber/Saltzpyre family.
        -- Keep persisted native values, but do not render duplicate Bardin
        -- fallback rows while the CWV provider is active.
        unlock_es_mercenary_dr_2h_axe = true,
        unlock_es_huntsman_dr_2h_axe = true,
        unlock_es_knight_dr_2h_axe = true,
        unlock_es_questingknight_dr_2h_axe = true,
        unlock_wh_captain_dr_2h_axe = true,
        unlock_wh_bountyhunter_dr_2h_axe = true,
        unlock_wh_zealot_dr_2h_axe = true,
    }
    local function strip(nodes)
        if type(nodes) ~= "table" then return end
        for i = #nodes, 1, -1 do
            local node = nodes[i]
            if type(node) == "table" and hidden[node.setting_id] then
                table.remove(nodes, i)
            elseif type(node) == "table" then
                strip(node.sub_widgets)
            end
        end
    end
    strip(data.options.widgets)
end

return data
