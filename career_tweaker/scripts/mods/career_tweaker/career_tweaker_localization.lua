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
    balance_stagger_thp_rework_description             = { en = "Reworks the Heal-on-Stagger talents: doubles the per-stagger THP base value (light/medium/heavy stagger now heal 0.5 / 2 / 4 THP per target, was 0.25 / 1 / 2) but caps the per-swing target count at 3 instead of 5. A perfect heavy-stagger swing across 3 enemies tops out at 12 THP; a typical medium-stagger swing across 3 caps at 6 THP. Trades the vanilla horde-feast for a smaller-but-richer payout that better rewards individual stagger quality." },
    balance_thp_breed_normalize                        = { en = "All careers: Normalize THP-on-kill across enemy types" },
    balance_thp_breed_normalize_description            = { en = "Compresses the THP-on-kill amount around a fixed pivot using a power law (output = 10 × (vanilla / 10)^0.5). Affects every Heal-on-Kill source: weapon traits, Bloodlust talents, Warrior Priest aftershock. Sample mappings: slave 1 → ~3, clanrat 2 → ~4, gor 3 → ~5, stormvermin 8 → ~9, bestigor 15 → ~12, chaos warrior 30 → ~17, monster 50 → ~22. Killing trash actually heals you for something; killing monsters no longer fully tops you off." },
}
