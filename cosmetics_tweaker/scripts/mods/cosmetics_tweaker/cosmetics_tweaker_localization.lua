local mod = get_mod("cosmetics_tweaker")
local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")

local loc = {
    cos_encarmine_hat_enabled = {
        en = "Encarmine Helmet",
    },
    cos_encarmine_hat_enabled_tooltip = {
        en = "Adds the custom Encarmine Helmet recolor for Foot Knight. Disabling this keeps the stable item identity registered for peer safety but falls back to the vanilla Laurel Helm appearance.",
    },
    cos_encarmine_hat_name = {
        en = "Encarmine Helmet",
    },
    cos_encarmine_hat_description = {
        en = "A red-and-gold Foot Knight helm with a black plume, created for Tweaker: Cosmetics.",
    },
    cos_gk_purpure_azure_enabled = {
        en = "Grail Knight: Purpure and Azure Set",
    },
    cos_gk_purpure_azure_enabled_tooltip = {
        en = "Adds the matching Couronne de la Lune, Midnight Purpure and Azure, and The Blood-Bloomed Bouclier cosmetics for Grail Knight. The set reuses the original game's models, rigging, physics, and fade behavior.",
    },
    cos_gk_purpure_azure_career_sharing_group = {
        en = "Purpure and Azure Career Availability",
    },
    cos_gk_purpure_azure_share_mercenary = {
        en = "Mercenary",
    },
    cos_gk_purpure_azure_share_mercenary_tooltip = {
        en = "Allow Mercenary to equip the Purpure and Azure set. Grail Knight availability is unchanged.",
    },
    cos_gk_purpure_azure_share_huntsman = {
        en = "Huntsman",
    },
    cos_gk_purpure_azure_share_huntsman_tooltip = {
        en = "Allow Huntsman to equip the Purpure and Azure set. Grail Knight availability is unchanged.",
    },
    cos_gk_purpure_azure_share_foot_knight = {
        en = "Foot Knight",
    },
    cos_gk_purpure_azure_share_foot_knight_tooltip = {
        en = "Allow Foot Knight to equip the Purpure and Azure set. Grail Knight availability is unchanged.",
    },
    cos_gk_purpure_azure_hat_name = {
        en = "Couronne de la Lune",
    },
    cos_gk_purpure_azure_hat_description = {
        en = "Its silvered crest recalls moonrise over Couronne, where Grail Knights keep vigil beneath the Lady's gaze and remember the vows that raised them above mortal knighthood.",
    },
    cos_gk_purpure_azure_skin_name = {
        en = "Midnight Purpure and Azure",
    },
    cos_gk_purpure_azure_skin_description = {
        en = "Once worn by a Bretonnian knight whose ardour burned brighter than good sense. Mortally wounded, he bequeathed his colours to Kruber, declaring the Grail Knight of Ubersreik worthy to bear them.",
    },
    cos_gk_purpure_azure_shield_name = {
        en = "The Blood-Bloomed Bouclier",
    },
    cos_gk_purpure_azure_shield_description = {
        en = "Kruber claims the blazon's four roses commemorate four maidens rescued, its gouttes de sang the blood spilled in their defence. The Ubersreik Five suspect the tale grows taller with every telling, but know better than to question his honesty within earshot.",
    },
    cos_fk_reikland_griffin_enabled = {
        en = "Foot Knight: Reikland Griffin Cape",
    },
    cos_fk_reikland_griffin_enabled_tooltip = {
        en = "Adds a Knights Encarmine outfit variant bearing Reikland's griffin on the cape. The variant reuses the original model, cape physics, material shading, and camera-fade behavior.",
    },
    cos_fk_reikland_griffin_skin_name = {
        en = "Knights Encarmine — Reikland Griffin",
    },
    cos_fk_reikland_griffin_skin_description = {
        en = "The colours of the Knights Encarmine, bearing the griffin of Reikland upon the cape.",
    },
    mod_description = {
        en = "Unlock hats and weapon skins per career on every hero, plus size and grip tweaks for individual weapons.",
    },

    unlock_all_illusions = {
        en = "Unlock All Weapon Illusions",
    },
    unlock_all_illusions_tooltip = {
        en = "Makes every weapon illusion selectable in the illusion browser. Works only in modded realm, and the change lasts for the current session.",
    },
    unlock_all_frames = {
        en = "Unlock All Portrait Frames",
    },
    unlock_all_frames_tooltip = {
        en = "Makes every portrait frame equippable in modded realm, except frames from DLC you do not own. Restart the game after changing this.",
    },
    suppress_la_quest_markers = {
        en = "Hide quest markers",
    },
    suppress_la_quest_markers_tooltip = {
        en = "Hides all of Loremaster's Armoury's on-screen quest waypoints, such as those on the message board and pickups. The quests themselves still progress as normal.",
    },
    suppress_la_notifications = {
        en = "Hide unread-letter notifications",
    },
    suppress_la_notifications_tooltip = {
        en = "Hides the pop-up banner that reminds you of an unread Loremaster's Armoury quest letter. The letter is still waiting for you at the message board.",
    },
    la_killquest_crash_guard = {
        en = "Kill-quest crash guard",
    },
    la_killquest_crash_guard_tooltip = {
        en = "Prevents Loremaster's Armoury from crashing the game when a player who has already left scores a kill. Leave this on unless you have a reason not to.",
    },
    la_disable_okri_challenges = {
        en = "Disable Okri's Challenges",
    },
    la_disable_okri_challenges_tooltip = {
        en = "Hides Loremaster's Armoury's quest line from Okri's challenge book, along with its progress tracking and reminder pop-ups. Because that quest line normally unlocks a few Kruber weapon skins when finished, those skins stay locked while it is hidden. Turn this off and restart the game to bring the quests back.",
    },
    -- v0.9.3.9: la_bridge_enable / la_bridge_enable_tooltip loc keys removed
    -- along with the toggle widget. The bridge is now a built-in feature.

    -- Issue #377 keeps opening manual-only. Issue #48 exposes the normally
    -- hidden magic families through one explicit selection gateway.

    show_magic_family_skins = {
        en = "Show Weavebound and Shyish Illusions",
    },
    show_magic_family_skins_tooltip = {
        en = "Shows Weavebound and Shyish-Infused weapon illusions in customization. Select one, then use Edit Glow to customize that exact weapon and illusion. They stay hidden by default.",
    },

    glow_picker_editor_button = {
        en = "EDIT\nGLOW",
    },

    loremasters_armoury_group = {
        en = "Loremaster's Armory",
    },
    appearance_group = {
        en = "Weapon Visual Tweaks",
    },
    cosmetic_availability_group = {
        en = "Cosmetic Availability",
    },
    es_bastard_sword_thiccc = {
        en = "Bretonian Longsword: Authentic Thiccness",
    },
    es_bastard_sword_thiccc_tooltip = {
        en = "Slims the Bretonian Longsword's blade to 65%% of its normal width so it looks less like a slab. This also applies to the sword in Bretonian Sword and Shield, and it affects every hero who wields it.",
    },
    cos_moonfire_cosmetic_puff = {
        en = "Moonfire Bow: Cosmetic AOE",
    },
    cos_moonfire_cosmetic_puff_tooltip = {
        en = "Adds the small blue moonfire burst to every hit from the Moonfire Bow. It is purely visual and deals no damage.",
    },
    cos_unlock_weapon_poses = {
        en = "Unlock Heroic Weapon Poses",
    },
    cos_unlock_weapon_poses_tooltip = {
        en = "Shows every authored heroic pose for the weapon you are holding on the social wheel in the modded realm. This does not grant or alter official backend ownership. Weapons without their own authored pose icons remain unchanged while compatibility diagnostics are collected.",
    },

    -- v0.9.37-dev: the "Weapon Glow Override" VMF menu loc keys
    -- (glow_override_*, glow_preset_*, glow_advanced_group, glow_mult_*,
    -- glow_color_*, glow_per_channel_*) were removed along with their
    -- widgets. Glow is now driven by the in-context Glow Picker popup
    -- (`_glow_picker.lua`), which uses the `_COLOR_PRESETS` table directly
    -- (keyed `purple_glow`/etc.) and the `glow_per_item` JSON setting — it
    -- never referenced these loc keys.

    ct_es_mace_gk_shield_01_name = {
        en = "Mace & Bretonnian Shield",
    },
    ct_es_mace_gk_shield_01_description = {
        en = "An Empire mace paired with a Bretonnian shield.",
    },

    ct_we_spear_shield_es_01_name = {
        en = "Empire Spear & Shield",
    },
    ct_we_spear_shield_es_01_description = {
        en = "Kruber's standard Empire spear and shield on Kerillian's Handmaiden.",
    },
    ct_we_spear_shield_es_02_name = {
        en = "Empire Spear & Shield (Ornate)",
    },
    ct_we_spear_shield_es_02_description = {
        en = "Kruber's ornate Empire spear and shield on Kerillian's Handmaiden.",
    },
    ct_we_spear_shield_es_03_name = {
        en = "Empire Spear & Shield (Plumed)",
    },
    ct_we_spear_shield_es_03_description = {
        en = "Kruber's plumed Empire spear and shield on Kerillian's Handmaiden.",
    },

    ct_es_deus_we_01_name = {
        en = "Elven Spear & Shield",
    },
    ct_es_deus_we_01_description = {
        en = "Kerillian's standard elven spear and shield on Kruber.",
    },
    ct_es_deus_we_02_name = {
        en = "Elven Spear & Shield (Exotic)",
    },
    ct_es_deus_we_02_description = {
        en = "Kerillian's exotic elven spear and shield on Kruber.",
    },

    tpe_group = {
        en = "Third-Person Equipment",
    },
    tpe_enable = {
        en = "Show Unwielded Weapons on Body",
    },
    tpe_enable_tooltip = {
        en = "Shows the weapons you are not currently holding on your character's body, so your whole loadout is visible at once. Weapon positions may be rough; restart the level after turning it on.",
    },
    tpe_show_self_in_3p = {
        en = "Hide Own Equipment in First Person",
    },
    tpe_show_self_in_3p_tooltip = {
        en = "Hides your own holstered weapons while you are in first-person view, where they would otherwise poke into the camera. Other players still see them normally.",
    },
    tpe_downscale_big_weapons = {
        en = "Holstered Weapon Scale %%",
    },
    tpe_downscale_big_weapons_tooltip = {
        en = "Sets the size of the holstered weapons shown on your body, as a percentage where 100 is full size. Lower it to around 75 to 85 if larger weapons look oversized.",
    },
}

-- Merge auto-generated cosmetic-unlock localization (group titles + per-item
-- humanized labels for ~1272 toggles). See _cosmetic_unlocks.lua.
for k, v in pairs(U.localization) do
    loc[k] = v
end

return loc
