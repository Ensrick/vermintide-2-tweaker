return {
    mod_name = {
        en = "Tweaker: Careers",
    },
    mod_description = {
        en = "Swap talents and abilities between careers, and toggle talent balance changes.",
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
    -- ============================================================
    -- Talent Balance Changes
    -- ============================================================
    talent_balance_group                    = { en = "Talent Balance Changes" },
    -- Balance mod toggles
    balance_zealot_merc_allow_random_crits             = { en = "Zealot/Merc: Allow random crits with guaranteed crit talent" },
    balance_zealot_merc_allow_random_crits_description = { en = "The 'crit every 5 hits' talent on Zealot and Mercenary normally disables all natural random crits. This removes that restriction so you can still get lucky crits between the guaranteed ones." },
    balance_whc_parry_extended_window                  = { en = "WHC: Parry crit talent doubles parry window" },
    balance_whc_parry_extended_window_description      = { en = "Doubles the parry timing window from 0.5s to 1.0s when enabled. Makes the Witch Hunter Captain's parry-crit talent easier to use." },
    balance_stagger_thp_rework                         = { en = "All careers: Stagger THP Rework" },
    balance_stagger_thp_rework_description             = { en = "Reworks the Heal-on-Stagger talents: +50% per-stagger THP base value (light/medium/heavy stagger now heal 0.375 / 1.5 / 3 THP per target, was 0.25 / 1 / 2) but caps the per-swing target count at 3 instead of 5. A perfect heavy-stagger swing across 3 enemies tops out at 9 THP; a typical medium-stagger swing across 3 caps at 4.5 THP. Trades the vanilla horde-feast for a smaller-but-richer payout that better rewards individual stagger quality without ballooning into OP territory." },
    balance_thp_kill_minimum                           = { en = "All careers: Minimum THP-on-kill" },
    balance_thp_kill_minimum_description               = { en = "Clamps every breed's THP-on-kill payout to a minimum of 1, so trash kills (slaves, hordelings — vanilla 0..1) always feel rewarding. Affects every Heal-on-Kill source: weapon traits, Bloodlust talents, Warrior Priest aftershock. Elites, specials, and monsters are untouched (their vanilla values already exceed the floor)." },
}
