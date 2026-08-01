local mod = get_mod("cosmetics_tweaker")
local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")

-- ---------------------------------------------------------------------------
-- Cosmetic Availability sub-widgets: the auto-generated per-character
-- cosmetic-unlock tree (Character -> Career -> Hats/Skins -> individual
-- checkboxes; see _cosmetic_unlocks.lua) followed by the two "unlock all"
-- toggles as LOOSE options at the bottom of the same category. They only take
-- effect in modded realm, but with this mod installed the player already knows
-- that, so no "(Modded Only)" suffix and no extra nesting.
-- ---------------------------------------------------------------------------
local cosmetic_availability_widgets = {}
for _, w in ipairs(U.widgets) do
    cosmetic_availability_widgets[#cosmetic_availability_widgets + 1] = w
end
-- The two loose "unlock all" toggles sit at the bottom of the tree, ordered
-- A->Z by display label: "Unlock All Portrait Frames" (P) before "Unlock All
-- Weapon Illusions" (W). (Per the standing alphabetize-by-label rule; the big
-- auto-generated Character->Career tree above keeps its deliberate hierarchy.)
cosmetic_availability_widgets[#cosmetic_availability_widgets + 1] = {
    setting_id    = "unlock_all_frames",
    type          = "checkbox",
    default_value = false,
    tooltip       = "unlock_all_frames_tooltip",
}
cosmetic_availability_widgets[#cosmetic_availability_widgets + 1] = {
    setting_id    = "unlock_all_illusions",
    type          = "checkbox",
    default_value = false,
    tooltip       = "unlock_all_illusions_tooltip",
}

-- Top-level groups sorted A->Z by display label, with the large Cosmetic
-- Availability tree deliberately kept LAST so it doesn't push the small option
-- groups down the list:
--   Loremaster's Armory · Third-Person Equipment · Weapon Visual Tweaks ·
--   (then) Cosmetic Availability.
local widgets = {
    -- Loremaster's Armory: every Loremaster's Armoury integration toggle lives
    -- here now, instead of each carrying an "LA:" label prefix. Children A->Z.
    {
        setting_id  = "loremasters_armoury_group",
        type        = "group",
        sub_widgets = {
            -- v0.9.49-dev (issue #186): remove LA's Okri's Challenges entirely --
            -- its "main_quest" line + 12 sub-quests hidden from Okri's book, no
            -- tracking, no completion pop-ups, unread-letter banner silenced.
            -- Default ON (challenges DISABLED). Restart after toggling OFF to
            -- restore. See _la_okri.lua + _la_prefix_embedded.lua.
            {
                setting_id    = "la_disable_okri_challenges",
                type          = "checkbox",
                default_value = true,
                tooltip       = "la_disable_okri_challenges_tooltip",
            },
            -- v0.9.3.1: LA Prefix Patch embedded -- quiet-mode toggles for LA's
            -- quest markers and unread-letter notifications. Default off so LA
            -- behaves as shipped until the user opts in.
            {
                setting_id    = "suppress_la_quest_markers",
                type          = "checkbox",
                default_value = false,
                tooltip       = "suppress_la_quest_markers_tooltip",
            },
            {
                setting_id    = "suppress_la_notifications",
                type          = "checkbox",
                default_value = false,
                tooltip       = "suppress_la_notifications_tooltip",
            },
            -- v0.9.40-dev (issue #137): crash guard for LA's
            -- StatisticsUtil.register_kill hook, which nil-derefs the attacker
            -- player when the killer has LEFT the game. Default ON (fail-safe) --
            -- only an explicit uncheck disables it.
            {
                setting_id    = "la_killquest_crash_guard",
                type          = "checkbox",
                default_value = true,
                tooltip       = "la_killquest_crash_guard_tooltip",
            },
        },
    },

    -- Experimental Third-Person Equipment: spawns extra 3P weapon meshes
    -- attached to the player's body for whichever loadout slot isn't currently
    -- wielded. Inspired by the standalone TPE mod (Workshop 1387440934).
    -- Positions are coarse -- per-item_type, not per-career.
    {
        setting_id  = "tpe_group",
        type        = "group",
        sub_widgets = {
            {
                setting_id    = "tpe_enable",
                type          = "checkbox",
                default_value = false,
                tooltip       = "tpe_enable_tooltip",
            },
            {
                setting_id    = "tpe_show_self_in_3p",
                type          = "checkbox",
                default_value = true,
                tooltip       = "tpe_show_self_in_3p_tooltip",
            },
            {
                setting_id      = "tpe_downscale_big_weapons",
                type            = "numeric",
                default_value   = 100,
                range           = { 25, 100 },
                decimals_number = 0,
                tooltip         = "tpe_downscale_big_weapons_tooltip",
            },
        },
    },

    -- Weapon Visual Tweaks (was "Weapon & Item Appearance").
    {
        setting_id  = "appearance_group",
        type        = "group",
        sub_widgets = {
            {
                setting_id    = "cos_encarmine_hat_enabled",
                type          = "checkbox",
                default_value = true,
                tooltip       = "cos_encarmine_hat_enabled_tooltip",
            },
            {
                setting_id    = "cos_fk_reikland_griffin_enabled",
                type          = "checkbox",
                default_value = true,
                tooltip       = "cos_fk_reikland_griffin_enabled_tooltip",
            },
            {
                setting_id    = "cos_gk_purpure_azure_enabled",
                type          = "checkbox",
                default_value = true,
                tooltip       = "cos_gk_purpure_azure_enabled_tooltip",
            },
            {
                setting_id  = "cos_gk_purpure_azure_career_sharing_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "cos_gk_purpure_azure_share_mercenary",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "cos_gk_purpure_azure_share_mercenary_tooltip",
                    },
                    {
                        setting_id    = "cos_gk_purpure_azure_share_huntsman",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "cos_gk_purpure_azure_share_huntsman_tooltip",
                    },
                    {
                        setting_id    = "cos_gk_purpure_azure_share_foot_knight",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "cos_gk_purpure_azure_share_foot_knight_tooltip",
                    },
                },
            },
            -- v0.9.47-dev: collapsed the redundant "Weapon Model Tweaks" wrapper;
            -- the lone toggles sit directly under this group now.
            {
                setting_id    = "es_bastard_sword_thiccc",
                type          = "checkbox",
                default_value = false,
                tooltip       = "es_bastard_sword_thiccc_tooltip",
            },
            {
                setting_id    = "cos_moonfire_cosmetic_puff",
                type          = "checkbox",
                default_value = false,
                tooltip       = "cos_moonfire_cosmetic_puff_tooltip",
            },
            {
                setting_id    = "cos_unlock_weapon_poses",
                type          = "checkbox",
                default_value = false,
                tooltip       = "cos_unlock_weapon_poses_tooltip",
            },
            {
                setting_id    = "show_magic_family_skins",
                type          = "checkbox",
                default_value = false,
                tooltip       = "show_magic_family_skins_tooltip",
            },
            -- v0.9.37-dev: the VMF "Weapon Glow Override" menu was REMOVED here;
            -- glow is driven by the in-context Glow Picker popup. The single
            -- gateway above reveals normally-hidden magic-family illusions;
            -- global glow override controls remain retired.
        },
    },

    -- Cosmetic Availability (kept LAST): the generated per-character unlock tree
    -- plus the two loose "unlock all" toggles, assembled above.
    {
        setting_id  = "cosmetic_availability_group",
        type        = "group",
        sub_widgets = cosmetic_availability_widgets,
    },
}

return {
    name = "Tweaker: Cosmetics",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = { widgets = widgets },

    custom_gui_textures = {
        textures = {
            "cos_glow_badge",
            "icon_knight_hat_0006_encarmine",
            "icon_cos_gk_purpure_azure_hat",
            "icon_cos_gk_purpure_azure_skin",
            "icon_cos_gk_purpure_azure_shield",
            "icon_cos_empire_mace_shield_primary_01",
            "icon_cos_breton_shield_01",
            "icon_cos_breton_shield_02",
            "icon_cos_breton_shield_03",
            "icon_cos_breton_shield_04",
            "icon_cos_breton_shield_alberic_01",
            "icon_cos_breton_shield_bastonne_01",
            "icon_cos_breton_shield_lothar_01",
            "icon_cos_breton_shield_luidhard_01",
            "icon_cos_breton_shield_reynard_01",
            "icon_cos_breton_shield_rune_glow",
        },
        ui_renderer_injections = {
            { "hero_view", "materials/ui/cos_glow_badge" },
            { "hero_view", "materials/ui/icon_cos_empire_mace_shield_primary_01" },
            { "hero_view", "materials/ui/icon_cos_breton_shield_01" },
            { "hero_view", "materials/ui/icon_cos_breton_shield_02" },
            { "hero_view", "materials/ui/icon_cos_breton_shield_03" },
            { "hero_view", "materials/ui/icon_cos_breton_shield_04" },
            { "hero_view", "materials/ui/icon_cos_breton_shield_alberic_01" },
            { "hero_view", "materials/ui/icon_cos_breton_shield_bastonne_01" },
            { "hero_view", "materials/ui/icon_cos_breton_shield_lothar_01" },
            { "hero_view", "materials/ui/icon_cos_breton_shield_luidhard_01" },
            { "hero_view", "materials/ui/icon_cos_breton_shield_reynard_01" },
            { "hero_view", "materials/ui/icon_cos_breton_shield_rune_glow" },
            { "ingame_ui", "materials/ui/icon_knight_hat_0006_encarmine" },
            { "hero_view", "materials/ui/icon_knight_hat_0006_encarmine" },
            { "loading_view", "materials/ui/icon_knight_hat_0006_encarmine" },
            { "popup_manager", "materials/ui/icon_knight_hat_0006_encarmine" },
            { "ingame_ui", "materials/ui/icon_cos_gk_purpure_azure_hat" },
            { "ingame_ui", "materials/ui/icon_cos_gk_purpure_azure_skin" },
            { "ingame_ui", "materials/ui/icon_cos_gk_purpure_azure_shield" },
            { "hero_view", "materials/ui/icon_cos_gk_purpure_azure_hat" },
            { "hero_view", "materials/ui/icon_cos_gk_purpure_azure_skin" },
            { "hero_view", "materials/ui/icon_cos_gk_purpure_azure_shield" },
            { "loading_view", "materials/ui/icon_cos_gk_purpure_azure_hat" },
            { "loading_view", "materials/ui/icon_cos_gk_purpure_azure_skin" },
            { "loading_view", "materials/ui/icon_cos_gk_purpure_azure_shield" },
            { "popup_manager", "materials/ui/icon_cos_gk_purpure_azure_hat" },
            { "popup_manager", "materials/ui/icon_cos_gk_purpure_azure_skin" },
            { "popup_manager", "materials/ui/icon_cos_gk_purpure_azure_shield" },
        },
    },
}
