return {
    mod_name = {
        en = "Tweaker: Careers",
    },
    mod_description = {
        en = "Swap talents and abilities between careers, and toggle talent reworks.",
    },
    -- ============================================================
    -- Career swapping
    -- ============================================================
    career_swapping_group                   = { en = "Career Ability & Talent Swapping" },
    talent_swap_dr_ironbreaker              = { en = "Ironbreaker" },
    talent_swap_dr_slayer                   = { en = "Slayer" },
    talent_swap_dr_ranger                   = { en = "Ranger" },
    talent_swap_dr_engineer                 = { en = "Engineer" },
    talent_swap_es_huntsman                 = { en = "Huntsman" },
    talent_swap_es_knight                   = { en = "Foot Knight" },
    talent_swap_es_mercenary                = { en = "Mercenary" },
    talent_swap_es_questingknight           = { en = "Grail Knight" },
    talent_swap_we_shade                    = { en = "Shade" },
    talent_swap_we_maidenguard              = { en = "Handmaiden" },
    talent_swap_we_waywatcher               = { en = "Waystalker" },
    talent_swap_we_thornsister              = { en = "Sister of the Thorn" },
    talent_swap_wh_zealot                   = { en = "Zealot" },
    talent_swap_wh_bountyhunter             = { en = "Bounty Hunter" },
    talent_swap_wh_captain                  = { en = "Witch Hunter Captain" },
    talent_swap_wh_priest                   = { en = "Warrior Priest" },
    talent_swap_bw_scholar                  = { en = "Battle Wizard" },
    talent_swap_bw_adept                    = { en = "Pyromancer" },
    talent_swap_bw_unchained                = { en = "Unchained" },
    talent_swap_bw_necromancer              = { en = "Necromancer" },
    -- Dropdown options for every talent-swap widget (resolved by VMF as
    -- localization keys; without these the UI shows `<<None (default)>>` etc.)
    talent_swap_option_none                 = { en = "None (default)" },
    talent_swap_option_dr_ironbreaker       = { en = "Ironbreaker (Bardin)" },
    talent_swap_option_dr_slayer            = { en = "Slayer (Bardin)" },
    talent_swap_option_dr_ranger            = { en = "Ranger (Bardin)" },
    talent_swap_option_dr_engineer          = { en = "Engineer (Bardin)" },
    talent_swap_option_es_huntsman          = { en = "Huntsman (Markus)" },
    talent_swap_option_es_knight            = { en = "Foot Knight (Markus)" },
    talent_swap_option_es_mercenary         = { en = "Mercenary (Markus)" },
    talent_swap_option_es_questingknight    = { en = "Grail Knight (Markus)" },
    talent_swap_option_we_shade             = { en = "Shade (Kerillian)" },
    talent_swap_option_we_maidenguard       = { en = "Handmaiden (Kerillian)" },
    talent_swap_option_we_waywatcher        = { en = "Waystalker (Kerillian)" },
    talent_swap_option_we_thornsister       = { en = "Sister of the Thorn (Kerillian)" },
    talent_swap_option_wh_zealot            = { en = "Zealot (Victor)" },
    talent_swap_option_wh_bountyhunter      = { en = "Bounty Hunter (Victor)" },
    talent_swap_option_wh_captain           = { en = "Witch Hunter Captain (Victor)" },
    talent_swap_option_wh_priest            = { en = "Warrior Priest (Victor)" },
    talent_swap_option_bw_scholar           = { en = "Battle Wizard (Sienna)" },
    talent_swap_option_bw_adept             = { en = "Pyromancer (Sienna)" },
    talent_swap_option_bw_unchained         = { en = "Unchained (Sienna)" },
    talent_swap_option_bw_necromancer       = { en = "Necromancer (Sienna)" },
    -- ============================================================
    -- Talent Reworks — group headers and items (all "Rework: …" prefixed)
    -- ============================================================
    talent_reworks_group                    = { en = "Talent Reworks" },

    -- General (cross-career)
    rework_general_group                    = { en = "General" },
    rework_general_stagger_thp                          = { en = "Rework: Stagger THP" },
    rework_general_stagger_thp_description              = { en = "Reworks the Heal-on-Stagger talents: +50% per-stagger THP base value (light/medium/heavy stagger now heal 0.375 / 1.5 / 3 THP per target, was 0.25 / 1 / 2) but caps the per-swing target count at 3 instead of 5. A perfect heavy-stagger swing across 3 enemies tops out at 9 THP; a typical medium-stagger swing across 3 caps at 4.5 THP. Trades the vanilla horde-feast for a smaller-but-richer payout that better rewards individual stagger quality without ballooning into OP territory." },
    rework_general_thp_kill_minimum                     = { en = "Rework: Minimum THP-on-kill" },
    rework_general_thp_kill_minimum_description         = { en = "Clamps every breed's THP-on-kill payout to a minimum of 1.5, lifting skaven slaves (vanilla 1) up to the same payout as the other hordes (beastmen ungor and chaos fanatics, already 1.5). Affects every Heal-on-Kill source: weapon traits, Bloodlust talents, Warrior Priest aftershock. Roamers, elites, specials, and monsters are untouched (vanilla values already exceed the floor)." },

    -- Bardin
    rework_dr_group                         = { en = "Rework: Bardin" },
    rework_dr_ranger_group                  = { en = "Rework: Ranger Veteran" },
    rework_dr_ranger_attack_speed_5_to_10              = { en = "Rework: +5% Attack Speed talent → +10%" },
    rework_dr_ranger_attack_speed_5_to_10_description  = { en = "Doubles Ranger Veteran's row-2 flat +5% Attack Speed talent (`bardin_ranger_attack_speed`) to +10%. Career-specific buff template — patching it doesn't affect any other career's stat talents. The in-game talent tooltip is rewritten in-place so the displayed percent matches the new value." },

    -- Kruber (Markus)
    rework_es_group                         = { en = "Rework: Kruber" },
    rework_es_mercenary_group               = { en = "Rework: Mercenary" },
    rework_es_mercenary_hellborgs_tutelage              = { en = "Rework: Hellborg's Tutelage" },
    rework_es_mercenary_hellborgs_tutelage_description  = { en = "Hellborg's Tutelage no longer disables random Critical Strikes. Instead, your random Critical Strike chance is reduced by 10% while the talent is selected. The guaranteed crit every 5 hits still procs as normal, so you keep the rhythm of the talent but can still benefit from natural crit-chance stacking (weapon traits, properties, bench buffs). The in-game talent description updates while this toggle is on." },

    -- Kerillian
    rework_we_group                         = { en = "Rework: Kerillian" },
    rework_we_maidenguard_group             = { en = "Rework: Handmaiden" },
    rework_we_maidenguard_crit_chance_5_to_10              = { en = "Rework: +5% Crit Chance talent → +10%" },
    rework_we_maidenguard_crit_chance_5_to_10_description  = { en = "Doubles Handmaiden's row-2 flat +5% Critical Strike Chance talent (`kerillian_maidenguard_crit_chance`) to +10%. Career-specific buff template — patching it doesn't affect any other career's stat talents. The in-game talent tooltip is rewritten in-place so the displayed percent matches the new value." },

    -- Saltzpyre (Victor)
    rework_wh_group                         = { en = "Rework: Saltzpyre" },
    rework_wh_zealot_group                  = { en = "Rework: Zealot" },
    rework_wh_zealot_smite_random_crits                 = { en = "Rework: Smite — Allow random crits" },
    rework_wh_zealot_smite_random_crits_description     = { en = "Smite (Zealot's crit-every-5-hits talent) normally disables all natural random crits. This removes that restriction so you can still get lucky crits between the guaranteed ones. (Zealot only — see Hellborg's Tutelage under Kruber > Mercenary for the Mercenary equivalent, which trades a 10% crit-chance reduction for keeping random crits enabled.)" },
    rework_wh_zealot_power_5_to_10                      = { en = "Rework: +5% Power talent → +10%" },
    rework_wh_zealot_power_5_to_10_description          = { en = "Doubles Zealot's row-1 flat +5% Power talent (`victor_zealot_power`) to +10%. Career-specific buff template — patching it doesn't affect any other career's stat talents. The in-game talent tooltip is rewritten in-place so the displayed percent matches the new value." },
    rework_wh_bountyhunter_group            = { en = "Rework: Bounty Hunter" },
    rework_wh_bountyhunter_double_shotted_80              = { en = "Rework: Double-Shotted — 80% refund on headshot" },
    rework_wh_bountyhunter_double_shotted_80_description  = { en = "Vanilla Double-Shotted refunds 60% of Locked And Loaded's cooldown when the active-ability shot headshots a target. With this rework on, the refund is raised to 80%. The talent's in-game tooltip is patched in-place so the displayed percent matches the new value." },
    rework_wh_captain_group                 = { en = "Rework: Witch Hunter Captain" },
    rework_wh_captain_parry_window                      = { en = "Rework: Extended parry window" },
    rework_wh_captain_parry_window_description          = { en = "Doubles the parry timing window from 0.5s to 1.0s when enabled. Makes the Witch Hunter Captain's parry-crit talent easier to use." },
}
