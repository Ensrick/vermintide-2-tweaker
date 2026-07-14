<!-- GENERATED — do not edit; run tools/gen-name-map/gen-name-map.ps1 -->
# Authoritative Name Map (key -> in-game display name)

**Generated:** 2026-07-13 &nbsp;|&nbsp; **Entries:** 3975

> This file is REGENERATED from ground truth (vanilla decompile + each mod's own
> definition tables). **Grep this instead of trusting the legacy hand-maintained**
> **catalogs** (ITEM_LIST.md / WEAPON_CATALOG.md / CHARACTER_COSMETIC_CATALOG.md /
> _cos_probe.txt). Regenerate: `tools/gen-name-map/gen-name-map.ps1 -GenDate <date>`.

Display-name provenance: **literal** = mod hard-coded the English string;
**mod_loc** = resolved via the mod's `_localization.lua`; **runtime_dump** = from
`dumps/boon_loc_dump.txt`; **game_dump** = from the in-game name dump (gt_dev
`gt_auto_name_dump`, emitted to the console log on keep entry). Entries marked
**(unresolved)** have NO trustworthy English source (vanilla strings live in undumped
.package bundles) — they are listed honestly with their loc key, never fabricated.

**Name dump:** none found — vanilla strings stay unresolved (run gt_dev's `/gt_dump_names` in-game, or let `gt_auto_name_dump` fire on keep entry, then regenerate).

## source: character_weapon_variants

### kind: cwv_skin_only (1 entries, 0 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `cwv_es_longsword_nordland` | Nordland Claymore | cwv_imperial_longsword |  | literal |

### kind: cwv_variant (28 entries, 0 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `cwv_dr_priest_greathammer` | Sigmarite Greathammer | wh_2h_hammer | dr_ranger, dr_ironbreaker, dr_slayer, dr_engineer | literal |
| `cwv_es_axe_shield` | Axe and Shield | cwv_es_axe_shield | es_mercenary, es_huntsman, es_knight | literal |
| `cwv_es_axe_shield_veteran` | Imperial Axe and Shield | cwv_es_axe_shield | es_mercenary, es_huntsman, es_knight | literal |
| `cwv_es_crossbow` | Crossbow | cwv_es_crossbow |  | literal |
| `cwv_es_cudgel` | Cudgel | es_1h_mace |  | literal |
| `cwv_es_dual_axes` | Dual Axes | cwv_es_dual_axes |  | literal |
| `cwv_es_dual_maces` | Dual Maces | cwv_es_dual_maces |  | literal |
| `cwv_es_dual_swords` | Imperial Dual Swords | cwv_es_dual_swords |  | literal |
| `cwv_es_dual_warpriest_hammers` | Dual Warrior-Priest Hammers | cwv_es_dual_warpriest_hammers |  | literal |
| `cwv_es_javelin` | Tuskgor Javelin | we_javelin |  | literal |
| `cwv_es_longsword` | Recruit Longsword | cwv_imperial_longsword |  | literal |
| `cwv_es_longsword_blackguard` | Black Guard Blade | cwv_imperial_longsword |  | literal |
| `cwv_es_longsword_shield` | Imperial Longsword and Shield | cwv_es_longsword_shield |  | literal |
| `cwv_es_maul` | Maul | cwv_es_maul |  | literal |
| `cwv_es_musket_old` | Old Musket | cwv_es_musket_old |  | literal |
| `cwv_es_outrider_grenade_launcher` | Outrider Grenade Launcher | cwv_es_outrider_grenade_launcher |  | literal |
| `cwv_es_poleaxe` | Poleaxe | cwv_es_poleaxe |  | literal |
| `cwv_es_priest_greathammer` | Sigmarite Greathammer | cwv_es_priest_greathammer |  | literal |
| `cwv_es_rapier` | Rapier | cwv_es_rapier |  | literal |
| `cwv_es_shortsword` | Shortsword | bw_dagger |  | literal |
| `cwv_es_sword_and_mace` | Sword and Mace | cwv_es_sword_and_mace |  | literal |
| `cwv_es_warpriest_hammer` | Warrior-Priest Hammer | cwv_es_warpriest_hammer |  | literal |
| `cwv_es_warpriest_hammer_shield` | Warrior-Priest Hammer and Shield | cwv_es_warpriest_hammer_shield |  | literal |
| `cwv_we_sword_shield` | Sword and Shield | es_sword_shield | we_waywatcher, we_maidenguard, we_shade, we_thornsister | literal |
| `cwv_we_sword_shield_veteran` | Elven Sword and Shield | es_sword_shield | we_waywatcher, we_maidenguard, we_shade, we_thornsister | literal |
| `cwv_wh_dual_axes` | Dual Axes | cwv_wh_dual_axes |  | literal |
| `cwv_wh_dual_maces` | Dual Maces | cwv_wh_dual_maces |  | literal |
| `cwv_wh_javelin` | Tuskgor Javelin | we_javelin |  | literal |

## source: cosmetics_tweaker

### kind: custom_illusion (4 entries, 0 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `ct_es_heavy_spear_deus_01` | Spear & Shield Spear | weapon_skin | es_mercenary, es_knight, es_huntsman, es_questingknight | literal |
| `ct_es_heavy_spear_deus_02` | Spear & Shield Spear (Ornate) | weapon_skin | es_mercenary, es_knight, es_huntsman, es_questingknight | literal |
| `ct_es_heavy_spear_deus_03` | Spear & Shield Spear (Plumed) | weapon_skin | es_mercenary, es_knight, es_huntsman, es_questingknight | literal |
| `ct_es_mace_gk_shield_01` | Mace & Bretonnian Shield | weapon_skin | es_mercenary, es_knight, es_huntsman, es_questingknight | literal |

## source: vanilla

### kind: bardin_engineer_career_skill_weapon (2 entries, 2 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `bardin_engineer_career_skill_weapon` | _(unresolved: )_ | bardin_engineer_career_skill_weapon |  | unresolved |
| `bardin_engineer_career_skill_weapon_vs` | _(unresolved: )_ | bardin_engineer_career_skill_weapon |  | unresolved |

### kind: bardin_engineer_career_skill_weapon_heavy (2 entries, 2 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `bardin_engineer_career_skill_weapon_heavy` | _(unresolved: )_ | bardin_engineer_career_skill_weapon_heavy |  | unresolved |
| `bardin_engineer_career_skill_weapon_heavy_vs` | _(unresolved: )_ | bardin_engineer_career_skill_weapon_heavy |  | unresolved |

### kind: breed (101 entries, 101 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `beastmen_bestigor` | _(unresolved: beastmen_bestigor)_ | breed |  | unresolved |
| `beastmen_bestigor_dummy` | _(unresolved: beastmen_bestigor_dummy)_ | breed |  | unresolved |
| `beastmen_gor` | _(unresolved: beastmen_gor)_ | breed |  | unresolved |
| `beastmen_gor_dummy` | _(unresolved: beastmen_gor_dummy)_ | breed |  | unresolved |
| `beastmen_minotaur` | _(unresolved: beastmen_minotaur)_ | breed |  | unresolved |
| `beastmen_standard_bearer` | _(unresolved: beastmen_standard_bearer)_ | breed |  | unresolved |
| `beastmen_standard_bearer_crater` | _(unresolved: beastmen_standard_bearer_crater)_ | breed |  | unresolved |
| `beastmen_ungor` | _(unresolved: beastmen_ungor)_ | breed |  | unresolved |
| `beastmen_ungor_archer` | _(unresolved: beastmen_ungor_archer)_ | breed |  | unresolved |
| `beastmen_ungor_dummy` | _(unresolved: beastmen_ungor_dummy)_ | breed |  | unresolved |
| `chaos_berzerker` | _(unresolved: chaos_berzerker)_ | breed |  | unresolved |
| `chaos_bulwark` | _(unresolved: chaos_bulwark)_ | breed |  | unresolved |
| `chaos_corruptor_sorcerer` | _(unresolved: chaos_corruptor_sorcerer)_ | breed |  | unresolved |
| `chaos_dummy_exalted_sorcerer_drachenfels` | _(unresolved: chaos_dummy_exalted_sorcerer_drachenfels)_ | breed |  | unresolved |
| `chaos_dummy_sorcerer` | _(unresolved: chaos_dummy_sorcerer)_ | breed |  | unresolved |
| `chaos_dummy_troll` | _(unresolved: chaos_dummy_troll)_ | breed |  | unresolved |
| `chaos_exalted_champion_norsca` | _(unresolved: chaos_exalted_champion_norsca)_ | breed |  | unresolved |
| `chaos_exalted_champion_warcamp` | _(unresolved: chaos_exalted_champion_warcamp)_ | breed |  | unresolved |
| `chaos_exalted_sorcerer` | _(unresolved: chaos_exalted_sorcerer)_ | breed |  | unresolved |
| `chaos_exalted_sorcerer_drachenfels` | _(unresolved: chaos_exalted_sorcerer_drachenfels)_ | breed |  | unresolved |
| `chaos_fanatic` | _(unresolved: chaos_fanatic)_ | breed |  | unresolved |
| `chaos_greed_pinata` | _(unresolved: chaos_greed_pinata)_ | breed |  | unresolved |
| `chaos_marauder` | _(unresolved: chaos_marauder)_ | breed |  | unresolved |
| `chaos_marauder_tutorial` | _(unresolved: chaos_marauder_tutorial)_ | breed |  | unresolved |
| `chaos_marauder_with_shield` | _(unresolved: chaos_marauder_with_shield)_ | breed |  | unresolved |
| `chaos_mutator_sorcerer` | _(unresolved: chaos_mutator_sorcerer)_ | breed |  | unresolved |
| `chaos_plague_wave_spawner` | _(unresolved: chaos_plague_wave_spawner)_ | breed |  | unresolved |
| `chaos_raider` | _(unresolved: chaos_raider)_ | breed |  | unresolved |
| `chaos_raider_tutorial` | _(unresolved: chaos_raider_tutorial)_ | breed |  | unresolved |
| `chaos_skeleton` | _(unresolved: chaos_skeleton)_ | breed |  | unresolved |
| `chaos_spawn` | _(unresolved: chaos_spawn)_ | breed |  | unresolved |
| `chaos_spawn_exalted_champion_norsca` | _(unresolved: chaos_spawn_exalted_champion_norsca)_ | breed |  | unresolved |
| `chaos_tentacle` | _(unresolved: chaos_tentacle)_ | breed |  | unresolved |
| `chaos_tether_sorcerer` | _(unresolved: chaos_tether_sorcerer)_ | breed |  | unresolved |
| `chaos_troll` | _(unresolved: chaos_troll)_ | breed |  | unresolved |
| `chaos_troll_chief` | _(unresolved: chaos_troll_chief)_ | breed |  | unresolved |
| `chaos_vortex` | _(unresolved: chaos_vortex)_ | breed |  | unresolved |
| `chaos_vortex_sorcerer` | _(unresolved: chaos_vortex_sorcerer)_ | breed |  | unresolved |
| `chaos_warrior` | _(unresolved: chaos_warrior)_ | breed |  | unresolved |
| `chaos_zombie` | _(unresolved: chaos_zombie)_ | breed |  | unresolved |
| `critter_nurgling` | _(unresolved: critter_nurgling)_ | breed |  | unresolved |
| `critter_pig` | _(unresolved: critter_pig)_ | breed |  | unresolved |
| `critter_rat` | _(unresolved: critter_rat)_ | breed |  | unresolved |
| `curse_mutator_sorcerer` | _(unresolved: curse_mutator_sorcerer)_ | breed |  | unresolved |
| `ethereal_skeleton_with_hammer` | _(unresolved: ethereal_skeleton_with_hammer)_ | breed |  | unresolved |
| `ethereal_skeleton_with_shield` | _(unresolved: ethereal_skeleton_with_shield)_ | breed |  | unresolved |
| `hero_bw_adept` | _(unresolved: hero_bw_adept)_ | breed |  | unresolved |
| `hero_bw_scholar` | _(unresolved: hero_bw_scholar)_ | breed |  | unresolved |
| `hero_bw_unchained` | _(unresolved: hero_bw_unchained)_ | breed |  | unresolved |
| `hero_dr_ironbreaker` | _(unresolved: hero_dr_ironbreaker)_ | breed |  | unresolved |
| `hero_dr_ranger` | _(unresolved: hero_dr_ranger)_ | breed |  | unresolved |
| `hero_dr_slayer` | _(unresolved: hero_dr_slayer)_ | breed |  | unresolved |
| `hero_es_huntsman` | _(unresolved: hero_es_huntsman)_ | breed |  | unresolved |
| `hero_es_knight` | _(unresolved: hero_es_knight)_ | breed |  | unresolved |
| `hero_es_mercenary` | _(unresolved: hero_es_mercenary)_ | breed |  | unresolved |
| `hero_we_maidenguard` | _(unresolved: hero_we_maidenguard)_ | breed |  | unresolved |
| `hero_we_shade` | _(unresolved: hero_we_shade)_ | breed |  | unresolved |
| `hero_we_waywatcher` | _(unresolved: hero_we_waywatcher)_ | breed |  | unresolved |
| `hero_wh_bountyhunter` | _(unresolved: hero_wh_bountyhunter)_ | breed |  | unresolved |
| `hero_wh_captain` | _(unresolved: hero_wh_captain)_ | breed |  | unresolved |
| `hero_wh_zealot` | _(unresolved: hero_wh_zealot)_ | breed |  | unresolved |
| `pet_skeleton` | _(unresolved: pet_skeleton)_ | breed |  | unresolved |
| `pet_skeleton_armored` | _(unresolved: pet_skeleton_armored)_ | breed |  | unresolved |
| `pet_skeleton_dual_wield` | _(unresolved: pet_skeleton_dual_wield)_ | breed |  | unresolved |
| `pet_skeleton_with_shield` | _(unresolved: pet_skeleton_with_shield)_ | breed |  | unresolved |
| `shadow_lieutenant` | _(unresolved: shadow_lieutenant)_ | breed |  | unresolved |
| `shadow_skull` | _(unresolved: shadow_skull)_ | breed |  | unresolved |
| `shadow_totem` | _(unresolved: shadow_totem)_ | breed |  | unresolved |
| `skaven_clan_rat` | _(unresolved: skaven_clan_rat)_ | breed |  | unresolved |
| `skaven_clan_rat_tutorial` | _(unresolved: skaven_clan_rat_tutorial)_ | breed |  | unresolved |
| `skaven_clan_rat_with_shield` | _(unresolved: skaven_clan_rat_with_shield)_ | breed |  | unresolved |
| `skaven_dummy_clan_rat` | _(unresolved: skaven_dummy_clan_rat)_ | breed |  | unresolved |
| `skaven_dummy_slave` | _(unresolved: skaven_dummy_slave)_ | breed |  | unresolved |
| `skaven_explosive_loot_rat` | _(unresolved: skaven_explosive_loot_rat)_ | breed |  | unresolved |
| `skaven_grey_seer` | _(unresolved: skaven_grey_seer)_ | breed |  | unresolved |
| `skaven_gutter_runner` | _(unresolved: skaven_gutter_runner)_ | breed |  | unresolved |
| `skaven_loot_rat` | _(unresolved: skaven_loot_rat)_ | breed |  | unresolved |
| `skaven_pack_master` | _(unresolved: skaven_pack_master)_ | breed |  | unresolved |
| `skaven_plague_monk` | _(unresolved: skaven_plague_monk)_ | breed |  | unresolved |
| `skaven_poison_wind_globadier` | _(unresolved: skaven_poison_wind_globadier)_ | breed |  | unresolved |
| `skaven_rat_ogre` | _(unresolved: skaven_rat_ogre)_ | breed |  | unresolved |
| `skaven_ratling_gunner` | _(unresolved: skaven_ratling_gunner)_ | breed |  | unresolved |
| `skaven_slave` | _(unresolved: skaven_slave)_ | breed |  | unresolved |
| `skaven_storm_vermin` | _(unresolved: skaven_storm_vermin)_ | breed |  | unresolved |
| `skaven_storm_vermin_champion` | _(unresolved: skaven_storm_vermin_champion)_ | breed |  | unresolved |
| `skaven_storm_vermin_commander` | _(unresolved: skaven_storm_vermin_commander)_ | breed |  | unresolved |
| `skaven_storm_vermin_warlord` | _(unresolved: skaven_storm_vermin_warlord)_ | breed |  | unresolved |
| `skaven_storm_vermin_with_shield` | _(unresolved: skaven_storm_vermin_with_shield)_ | breed |  | unresolved |
| `skaven_stormfiend` | _(unresolved: skaven_stormfiend)_ | breed |  | unresolved |
| `skaven_stormfiend_boss` | _(unresolved: skaven_stormfiend_boss)_ | breed |  | unresolved |
| `skaven_stormfiend_demo` | _(unresolved: skaven_stormfiend_demo)_ | breed |  | unresolved |
| `skaven_warpfire_thrower` | _(unresolved: skaven_warpfire_thrower)_ | breed |  | unresolved |
| `tower_homing_skull` | _(unresolved: tower_homing_skull)_ | breed |  | unresolved |
| `training_dummy` | _(unresolved: dummy_description)_ | breed |  | unresolved |
| `vs_chaos_troll` | _(unresolved: vs_chaos_troll)_ | breed |  | unresolved |
| `vs_gutter_runner` | _(unresolved: vs_gutter_runner)_ | breed |  | unresolved |
| `vs_packmaster` | _(unresolved: vs_packmaster)_ | breed |  | unresolved |
| `vs_poison_wind_globadier` | _(unresolved: vs_poison_wind_globadier)_ | breed |  | unresolved |
| `vs_rat_ogre` | _(unresolved: vs_rat_ogre)_ | breed |  | unresolved |
| `vs_ratling_gunner` | _(unresolved: vs_ratling_gunner)_ | breed |  | unresolved |
| `vs_warpfire_thrower` | _(unresolved: vs_warpfire_thrower)_ | breed |  | unresolved |

### kind: bundle (52 entries, 52 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `adept_bundle_0001` | _(unresolved: display_name_adept_bundle_0001)_ | bundle |  | unresolved |
| `adept_bundle_0002` | _(unresolved: display_name_adept_bundle_0002)_ | bundle |  | unresolved |
| `bountyhunter_bundle_0001` | _(unresolved: bounty_hunter_bundle_01)_ | bundle |  | unresolved |
| `bountyhunter_bundle_0002` | _(unresolved: display_name_bountyhunter_bundle_0002)_ | bundle |  | unresolved |
| `cosmetic_bundle_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | bundle |  | unresolved |
| `engineer_bundle_0001` | _(unresolved: display_name_engineer_bundle_0001)_ _(dlc:cog)_ | bundle |  | unresolved |
| `fall_collection_2021_bundle` | _(unresolved: display_name_five_career_bundle_0002)_ | bundle |  | unresolved |
| `five_career_bundle_0001` | _(unresolved: five_career_bundle_0001)_ | bundle |  | unresolved |
| `five_career_bundle_0004` | _(unresolved: display_name_five_career_bundle_0004)_ | bundle |  | unresolved |
| `five_career_bundle_0005` | _(unresolved: display_name_five_career_bundle_0005)_ | bundle |  | unresolved |
| `five_career_bundle_0006` | _(unresolved: display_name_five_career_bundle_0006)_ | bundle |  | unresolved |
| `five_career_bundle_0007` | _(unresolved: display_name_five_career_bundle_0007)_ | bundle |  | unresolved |
| `five_career_bundle_0008` | _(unresolved: display_name_five_career_bundle_0008)_ | bundle |  | unresolved |
| `huntsman_bundle_0001` | _(unresolved: display_name_huntsman_bundle_0001)_ | bundle |  | unresolved |
| `huntsman_bundle_0002` | _(unresolved: display_name_huntsman_bundle_0002)_ | bundle |  | unresolved |
| `ironbreaker_bundle_0001` | _(unresolved: ironbreaker_bundle_01)_ | bundle |  | unresolved |
| `ironbreaker_bundle_0002` | _(unresolved: display_name_ironbreaker_bundle_0002)_ | bundle |  | unresolved |
| `knight_bundle_0002` | _(unresolved: display_name_knight_bundle_0002)_ | bundle |  | unresolved |
| `maidenguard_bundle_0001` | _(unresolved: display_name_maidenguard_bundle_0001)_ | bundle |  | unresolved |
| `maidenguard_bundle_0002` | _(unresolved: display_name_maidenguard_bundle_0002)_ | bundle |  | unresolved |
| `maidenguard_bundle_0003` | _(unresolved: display_name_maidenguard_bundle_0003)_ | bundle |  | unresolved |
| `mercenary_bundle_0001` | _(unresolved: mercenary_bundle_01)_ | bundle |  | unresolved |
| `mercenary_bundle_0002` | _(unresolved: display_name_mercenary_bundle_0002)_ | bundle |  | unresolved |
| `priest_bundle_0001` | _(unresolved: display_name_priest_bundle_0001)_ _(dlc:bless)_ | bundle |  | unresolved |
| `q1_collection_bundle` | _(unresolved: display_name_q1_collection_bundle)_ | bundle |  | unresolved |
| `q1_footknight_bundle` | _(unresolved: display_name_q1_footknight_bundle)_ | bundle |  | unresolved |
| `q1_ranger_bundle` | _(unresolved: display_name_q1_ranger_bundle)_ | bundle |  | unresolved |
| `q1_unchained_bundle` | _(unresolved: display_name_q1_unchained_bundle)_ | bundle |  | unresolved |
| `q1_waywatcher_bundle` | _(unresolved: display_name_q1_waywatcher_bundle)_ | bundle |  | unresolved |
| `q1_wh_captain_bundle` | _(unresolved: display_name_q1_wh_captain_bundle)_ | bundle |  | unresolved |
| `q2_2023_hat_collection` | _(unresolved: display_name_q2_2023_hat_collection)_ | bundle |  | unresolved |
| `questing_knight_bundle_0001` | _(unresolved: display_name_questing_knight_bundle_0001)_ _(dlc:lake)_ | bundle |  | unresolved |
| `ranger_bundle_0002` | _(unresolved: display_name_ranger_bundle_0002)_ | bundle |  | unresolved |
| `scholar_bundle_0001` | _(unresolved: pyromancer_bundle_01)_ | bundle |  | unresolved |
| `scholar_bundle_0002` | _(unresolved: display_name_scholar_bundle_0002)_ | bundle |  | unresolved |
| `scholar_bundle_0003` | _(unresolved: display_name_scholar_bundle_0003)_ | bundle |  | unresolved |
| `shade_bundle_0001` | _(unresolved: shade_bundle_01)_ | bundle |  | unresolved |
| `shade_bundle_0002` | _(unresolved: display_name_shade_bundle_0002)_ | bundle |  | unresolved |
| `skaven_globadier_skin_1001_bundle` | _(unresolved: display_name_skaven_wind_globadier_skin_1001)_ | cosmetic_bundle | vs_poison_wind_globadier | unresolved |
| `skaven_gutter_runner_skin_1001_bundle` | _(unresolved: display_name_skaven_gutter_runner_skin_1001)_ | cosmetic_bundle | vs_gutter_runner | unresolved |
| `skaven_packmaster_skin_1001_bundle` | _(unresolved: display_name_skaven_pack_master_skin_1001)_ | cosmetic_bundle | vs_packmaster | unresolved |
| `skaven_ratling_gunner_skin_1001_bundle` | _(unresolved: display_name_skaven_ratling_gunner_skin_1001)_ | cosmetic_bundle | vs_ratling_gunner | unresolved |
| `skaven_skins_bundle_0001` | _(unresolved: display_name_skaven_skins_bundle_0001)_ | bundle |  | unresolved |
| `skaven_warpfire_thrower_skin_1001_bundle` | _(unresolved: display_name_skaven_warpfire_thrower_skin_1001)_ | cosmetic_bundle | vs_warpfire_thrower | unresolved |
| `slayer_bundle_0001` | _(unresolved: display_name_slayer_bundle_0001)_ | bundle |  | unresolved |
| `slayer_bundle_0002` | _(unresolved: display_name_slayer_bundle_0002)_ | bundle |  | unresolved |
| `test_bundle_1016` | _(unresolved: shade_bundle_01)_ | bundle |  | unresolved |
| `unchained_bundle_0002` | _(unresolved: display_name_unchained_bundle_0002)_ | bundle |  | unresolved |
| `waywatcher_bundle_0001` | _(unresolved: display_name_waywatcher_bundle_0001)_ | bundle |  | unresolved |
| `witchhunter_bundle_0001` | _(unresolved: display_name_witchhunter_bundle_0001)_ | bundle |  | unresolved |
| `zealot_bundle_0001` | _(unresolved: display_name_zealot_bundle_0001)_ | bundle |  | unresolved |
| `zealot_bundle_0002` | _(unresolved: display_name_zealot_bundle_0002)_ | bundle |  | unresolved |

### kind: career (21 entries, 21 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `bw_adept` | _(unresolved: bw_adept)_ | career |  | unresolved |
| `bw_necromancer` | _(unresolved: bw_necromancer)_ _(dlc:shovel)_ | career |  | unresolved |
| `bw_scholar` | _(unresolved: bw_scholar)_ | career |  | unresolved |
| `bw_unchained` | _(unresolved: bw_unchained)_ | career |  | unresolved |
| `dr_engineer` | _(unresolved: dr_engineer)_ _(dlc:cog)_ | career |  | unresolved |
| `dr_ironbreaker` | _(unresolved: dr_ironbreaker)_ | career |  | unresolved |
| `dr_ranger` | _(unresolved: dr_ranger)_ | career |  | unresolved |
| `dr_slayer` | _(unresolved: dr_slayer)_ | career |  | unresolved |
| `empire_soldier_tutorial` | _(unresolved: empire_soldier)_ | career |  | unresolved |
| `es_huntsman` | _(unresolved: es_huntsman)_ | career |  | unresolved |
| `es_knight` | _(unresolved: es_knight)_ | career |  | unresolved |
| `es_mercenary` | _(unresolved: es_mercenary)_ | career |  | unresolved |
| `es_questingknight` | _(unresolved: es_questingknight)_ _(dlc:lake)_ | career |  | unresolved |
| `we_maidenguard` | _(unresolved: we_maidenguard)_ | career |  | unresolved |
| `we_shade` | _(unresolved: we_shade)_ | career |  | unresolved |
| `we_thornsister` | _(unresolved: we_thornsister)_ _(dlc:woods)_ | career |  | unresolved |
| `we_waywatcher` | _(unresolved: we_waywatcher)_ | career |  | unresolved |
| `wh_bountyhunter` | _(unresolved: wh_bountyhunter)_ | career |  | unresolved |
| `wh_captain` | _(unresolved: wh_captain)_ | career |  | unresolved |
| `wh_priest` | _(unresolved: wh_priest)_ _(dlc:bless)_ | career |  | unresolved |
| `wh_zealot` | _(unresolved: wh_zealot)_ | career |  | unresolved |

### kind: chips (21 entries, 21 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `shilling_bag_1` | _(unresolved: shilling_bag_1_name)_ | chips |  | unresolved |
| `shilling_bag_10` | _(unresolved: shilling_bag_10_name)_ | chips |  | unresolved |
| `shilling_bag_100` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_25` | _(unresolved: shilling_bag_25_name)_ | chips |  | unresolved |
| `shilling_bag_5` | _(unresolved: shilling_bag_5_name)_ | chips |  | unresolved |
| `shilling_bag_50` | _(unresolved: shilling_bag_50_name)_ | chips |  | unresolved |
| `shilling_bag_base` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_bless` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_bless_upgrade` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_bogenhafen` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_cog` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_cog_upgrade` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_collectors` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_holly` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_lake` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_lake_upgrade` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_scorpion` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_shovel` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_shovel_upgrade` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_woods` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |
| `shilling_bag_woods_upgrade` | _(unresolved: shilling_bag_100_name)_ | chips |  | unresolved |

### kind: crafting_material (11 entries, 11 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `crafting_material_act_1` | _(unresolved: crafting_material_act_1_title)_ | crafting_material |  | unresolved |
| `crafting_material_act_2` | _(unresolved: crafting_material_act_2_title)_ | crafting_material |  | unresolved |
| `crafting_material_act_3` | _(unresolved: crafting_material_act_3_title)_ | crafting_material |  | unresolved |
| `crafting_material_dust_1` | _(unresolved: crafting_material_dust_1_title)_ | crafting_material |  | unresolved |
| `crafting_material_dust_2` | _(unresolved: crafting_material_dust_2_title)_ | crafting_material |  | unresolved |
| `crafting_material_dust_3` | _(unresolved: crafting_material_dust_3_title)_ | crafting_material |  | unresolved |
| `crafting_material_dust_4` | _(unresolved: crafting_material_dust_4_title)_ | crafting_material |  | unresolved |
| `crafting_material_jewellery` | _(unresolved: crafting_material_jewellery_title)_ | crafting_material |  | unresolved |
| `crafting_material_scrap` | _(unresolved: crafting_material_scrap_title)_ | crafting_material |  | unresolved |
| `crafting_material_weapon` | _(unresolved: crafting_material_weapon_title)_ | crafting_material |  | unresolved |
| `crafting_material_weapon_skin_tool` | _(unresolved: crafting_material_weapon_skin_tool_title)_ | crafting_material |  | unresolved |

### kind: deed (206 entries, 206 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `collectors_deed_0001` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `collectors_deed_0002` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `collectors_deed_0003` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0001` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0002` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0003` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0004` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0005` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0006` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0007` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0008` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0009` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0010` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0011` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0012` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0013` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0014` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0015` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0016` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0017` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0018` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0019` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0020` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0021` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0022` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0023` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0024` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0025` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0026` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0027` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0028` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0029` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0030` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0031` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0032` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0033` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0034` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0035` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0036` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0037` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0038` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0039` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_0040` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1001` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1002` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1003` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1004` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1005` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1006` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1007` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1008` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1009` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1010` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1011` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1012` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1013` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1014` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1015` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1016` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1017` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1018` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1019` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1020` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1021` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1022` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1023` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1024` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1025` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1026` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1027` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1028` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1029` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1030` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1031` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1032` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1033` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1034` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1035` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1036` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1037` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1038` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1039` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_1040` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2001` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2002` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2003` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2004` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2005` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2006` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2007` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2008` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2009` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2010` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2011` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2012` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2013` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2014` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2015` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2016` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2017` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2018` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2019` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2020` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2021` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2022` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2023` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2024` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2025` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2026` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2027` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2028` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2029` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2030` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2031` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2032` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2033` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2034` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2035` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2036` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2037` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2038` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2039` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2040` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2041` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_2042` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3001` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3002` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3003` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3004` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3005` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3006` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3007` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3008` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3009` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3010` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3011` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3012` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3013` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3014` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3015` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3016` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3017` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3018` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3019` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3020` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3021` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3022` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3023` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3024` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3025` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3026` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3027` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3028` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3029` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3030` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3031` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3032` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3033` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3034` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3035` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3036` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3037` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3038` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3039` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_3040` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4001` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4002` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4003` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4004` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4005` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4006` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4007` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4008` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4009` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4010` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4011` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4012` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4013` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4014` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4015` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4016` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4017` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4018` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4019` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4020` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4021` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4022` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4023` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4024` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4025` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4026` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4027` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4028` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4029` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4030` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4031` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4032` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4033` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4034` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4035` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4036` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4037` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4038` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4039` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |
| `deed_4040` | _(unresolved: display_name_deed_generic)_ | deed |  | unresolved |

### kind: frame (220 entries, 220 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `frame_0000` | _(unresolved: frame_0000_name)_ | frame |  | unresolved |
| `frame_0001` | _(unresolved: frame_0001_name)_ | frame |  | unresolved |
| `frame_0002` | _(unresolved: frame_0002_name)_ | frame |  | unresolved |
| `frame_0003` | _(unresolved: frame_0003_name)_ | frame |  | unresolved |
| `frame_0004` | _(unresolved: frame_0004_name)_ | frame |  | unresolved |
| `frame_0005` | _(unresolved: frame_0005_name)_ | frame |  | unresolved |
| `frame_0006` | _(unresolved: frame_0006_name)_ | frame |  | unresolved |
| `frame_0007` | _(unresolved: frame_0007_name)_ | frame |  | unresolved |
| `frame_0008` | _(unresolved: frame_0008_name)_ | frame |  | unresolved |
| `frame_0009` | _(unresolved: frame_0009_name)_ | frame |  | unresolved |
| `frame_0010` | _(unresolved: frame_0010_name)_ | frame |  | unresolved |
| `frame_0011` | _(unresolved: frame_0011_name)_ | frame |  | unresolved |
| `frame_0012` | _(unresolved: frame_0012_name)_ | frame |  | unresolved |
| `frame_0013` | _(unresolved: frame_0013_name)_ | frame |  | unresolved |
| `frame_0014` | _(unresolved: frame_0014_name)_ | frame |  | unresolved |
| `frame_0015` | _(unresolved: frame_0015_name)_ | frame |  | unresolved |
| `frame_0016` | _(unresolved: frame_0016_name)_ | frame |  | unresolved |
| `frame_0017` | _(unresolved: frame_0017_name)_ | frame |  | unresolved |
| `frame_0018` | _(unresolved: frame_0018_name)_ | frame |  | unresolved |
| `frame_0019` | _(unresolved: frame_0019_name)_ | frame |  | unresolved |
| `frame_0020` | _(unresolved: frame_0020_name)_ | frame |  | unresolved |
| `frame_0021` | _(unresolved: frame_0021_name)_ | frame |  | unresolved |
| `frame_0022` | _(unresolved: frame_0022_name)_ | frame |  | unresolved |
| `frame_0023` | _(unresolved: frame_0023_name)_ | frame |  | unresolved |
| `frame_0024` | _(unresolved: frame_0024_name)_ | frame |  | unresolved |
| `frame_0025` | _(unresolved: frame_0025_name)_ | frame |  | unresolved |
| `frame_0026` | _(unresolved: frame_0026_name)_ | frame |  | unresolved |
| `frame_0027` | _(unresolved: frame_0027_name)_ | frame |  | unresolved |
| `frame_0028` | _(unresolved: frame_0028_name)_ | frame |  | unresolved |
| `frame_0029` | _(unresolved: frame_0029_name)_ | frame |  | unresolved |
| `frame_0030` | _(unresolved: frame_0030_name)_ | frame |  | unresolved |
| `frame_0031` | _(unresolved: frame_0031_name)_ | frame |  | unresolved |
| `frame_0032` | _(unresolved: frame_0032_name)_ | frame |  | unresolved |
| `frame_0033` | _(unresolved: frame_0033_name)_ | frame |  | unresolved |
| `frame_0034` | _(unresolved: frame_0034_name)_ | frame |  | unresolved |
| `frame_0035` | _(unresolved: frame_0035_name)_ | frame |  | unresolved |
| `frame_0036` | _(unresolved: frame_0036_name)_ | frame |  | unresolved |
| `frame_0037` | _(unresolved: frame_0037_name)_ | frame |  | unresolved |
| `frame_0038` | _(unresolved: frame_0038_name)_ | frame |  | unresolved |
| `frame_0039` | _(unresolved: frame_0039_name)_ | frame |  | unresolved |
| `frame_0040` | _(unresolved: frame_0040_name)_ | frame |  | unresolved |
| `frame_0041` | _(unresolved: frame_0041_name)_ | frame |  | unresolved |
| `frame_0042` | _(unresolved: frame_0042_name)_ | frame |  | unresolved |
| `frame_0043` | _(unresolved: frame_0043_name)_ | frame |  | unresolved |
| `frame_0044` | _(unresolved: frame_0044_name)_ | frame |  | unresolved |
| `frame_0045` | _(unresolved: frame_0045_name)_ | frame |  | unresolved |
| `frame_0046` | _(unresolved: frame_0046_name)_ | frame |  | unresolved |
| `frame_0047` | _(unresolved: frame_0047_name)_ | frame |  | unresolved |
| `frame_0048` | _(unresolved: frame_0048_name)_ | frame |  | unresolved |
| `frame_0049` | _(unresolved: frame_0049_name)_ | frame |  | unresolved |
| `frame_0050` | _(unresolved: frame_0050_name)_ | frame |  | unresolved |
| `frame_0051` | _(unresolved: frame_0051_name)_ | frame |  | unresolved |
| `frame_0052` | _(unresolved: frame_0052_name)_ | frame |  | unresolved |
| `frame_0053` | _(unresolved: frame_0053_name)_ | frame |  | unresolved |
| `frame_0054` | _(unresolved: frame_0054_name)_ | frame |  | unresolved |
| `frame_0055` | _(unresolved: frame_0055_name)_ | frame |  | unresolved |
| `frame_0056` | _(unresolved: frame_0056_name)_ | frame |  | unresolved |
| `frame_0057` | _(unresolved: frame_0057_name)_ | frame |  | unresolved |
| `frame_0058` | _(unresolved: frame_0058_name)_ | frame |  | unresolved |
| `frame_0059` | _(unresolved: frame_0059_name)_ | frame |  | unresolved |
| `frame_0060` | _(unresolved: frame_0060_name)_ | frame |  | unresolved |
| `frame_0061` | _(unresolved: frame_0061_name)_ | frame |  | unresolved |
| `frame_0062` | _(unresolved: frame_0062_name)_ | frame |  | unresolved |
| `frame_0063` | _(unresolved: frame_0063_name)_ | frame |  | unresolved |
| `frame_0064` | _(unresolved: frame_0064_name)_ | frame |  | unresolved |
| `frame_0065` | _(unresolved: frame_0065_name)_ | frame |  | unresolved |
| `frame_0066` | _(unresolved: frame_0066_name)_ | frame |  | unresolved |
| `frame_0067` | _(unresolved: frame_0067_name)_ | frame |  | unresolved |
| `frame_0068` | _(unresolved: frame_0068_name)_ | frame |  | unresolved |
| `frame_0069` | _(unresolved: frame_0069_name)_ | frame |  | unresolved |
| `frame_0070` | _(unresolved: frame_0070_name)_ | frame |  | unresolved |
| `frame_0071` | _(unresolved: frame_0071_name)_ | frame |  | unresolved |
| `frame_0072` | _(unresolved: frame_0072_name)_ | frame |  | unresolved |
| `frame_0073` | _(unresolved: frame_0073_name)_ | frame |  | unresolved |
| `frame_0074` | _(unresolved: frame_0074_name)_ | frame |  | unresolved |
| `frame_0075` | _(unresolved: frame_0075_name)_ | frame |  | unresolved |
| `frame_0076` | _(unresolved: frame_0076_name)_ | frame |  | unresolved |
| `frame_0077` | _(unresolved: frame_0077_name)_ | frame |  | unresolved |
| `frame_0078` | _(unresolved: frame_0078_name)_ | frame |  | unresolved |
| `frame_0079` | _(unresolved: frame_0079_name)_ | frame |  | unresolved |
| `frame_0080` | _(unresolved: frame_0080_name)_ | frame |  | unresolved |
| `frame_0081` | _(unresolved: frame_0081_name)_ | frame |  | unresolved |
| `frame_0084` | _(unresolved: frame_0084_name)_ | frame |  | unresolved |
| `frame_0085` | _(unresolved: frame_0085_name)_ | frame |  | unresolved |
| `frame_0086` | _(unresolved: frame_0086_name)_ | frame |  | unresolved |
| `frame_0087` | _(unresolved: frame_0087_name)_ | frame |  | unresolved |
| `frame_0089` | _(unresolved: frame_0089_name)_ | frame |  | unresolved |
| `frame_0090` | _(unresolved: frame_0090_name)_ | frame |  | unresolved |
| `frame_0091` | _(unresolved: frame_0091_name)_ | frame |  | unresolved |
| `frame_0094` | _(unresolved: frame_0094_name)_ | frame |  | unresolved |
| `frame_0095` | _(unresolved: frame_0095_name)_ | frame |  | unresolved |
| `frame_0096` | _(unresolved: frame_0096_name)_ | frame |  | unresolved |
| `frame_0097` | _(unresolved: frame_0097_name)_ _(dlc:lake_upgrade)_ | frame |  | unresolved |
| `frame_0098` | _(unresolved: frame_0098_name)_ _(dlc:lake_upgrade)_ | frame |  | unresolved |
| `frame_0099` | _(unresolved: frame_0099_name)_ _(dlc:cog_upgrade)_ | frame |  | unresolved |
| `frame_0100` | _(unresolved: frame_0100_name)_ _(dlc:cog_upgrade)_ | frame |  | unresolved |
| `frame_0101` | _(unresolved: frame_0101_name)_ _(dlc:cog_upgrade)_ | frame |  | unresolved |
| `frame_0102` | _(unresolved: frame_0102_name)_ _(dlc:woods)_ | frame |  | unresolved |
| `frame_0103` | _(unresolved: frame_0103_name)_ _(dlc:woods)_ | frame |  | unresolved |
| `frame_0104` | _(unresolved: frame_0104_name)_ _(dlc:woods)_ | frame |  | unresolved |
| `frame_0105` | _(unresolved: frame_0105_name)_ | frame |  | unresolved |
| `frame_0106` | _(unresolved: frame_0106_name)_ | frame |  | unresolved |
| `frame_0107` | _(unresolved: frame_0107_name)_ _(dlc:bless)_ | frame |  | unresolved |
| `frame_0108` | _(unresolved: frame_0108_name)_ _(dlc:bless)_ | frame |  | unresolved |
| `frame_0109` | _(unresolved: frame_0109_name)_ _(dlc:bless)_ | frame |  | unresolved |
| `frame_0110` | _(unresolved: frame_0110_name)_ | frame |  | unresolved |
| `frame_0111` | _(unresolved: frame_0111_name)_ | frame |  | unresolved |
| `frame_apology_2025` | _(unresolved: portrait_frame_apology_name)_ | frame |  | unresolved |
| `frame_bear` | _(unresolved: frame_0088_name)_ | frame |  | unresolved |
| `frame_beta_2024` | _(unresolved: frame_beta_2024_name)_ | frame |  | unresolved |
| `frame_bogenhafen_01` | _(unresolved: frame_bogenhafen_01_name)_ | frame |  | unresolved |
| `frame_bogenhafen_02` | _(unresolved: frame_bogenhafen_02_name)_ | frame |  | unresolved |
| `frame_bogenhafen_03` | _(unresolved: frame_bogenhafen_03_name)_ | frame |  | unresolved |
| `frame_bogenhafen_04` | _(unresolved: frame_bogenhafen_04_name)_ | frame |  | unresolved |
| `frame_celebration_01` | _(unresolved: frame_celebration_01_name)_ | frame |  | unresolved |
| `frame_celebration_02` | _(unresolved: frame_celebration_02_name)_ | frame |  | unresolved |
| `frame_celebration_03` | _(unresolved: frame_celebration_03_name)_ | frame |  | unresolved |
| `frame_celebration_05` | _(unresolved: frame_celebration_05_name)_ | frame |  | unresolved |
| `frame_celebration_06` | _(unresolved: frame_celebration_06_name)_ | frame |  | unresolved |
| `frame_celebration_07` | _(unresolved: frame_celebration_07_name)_ | frame |  | unresolved |
| `frame_celebration_08` | _(unresolved: frame_celebration_08_name)_ | frame |  | unresolved |
| `frame_collectors_edition` | _(unresolved: frame_collectors_edition_name)_ | frame |  | unresolved |
| `frame_collectors_edition_preorder` | _(unresolved: frame_collectors_edition_preorder_name)_ | frame |  | unresolved |
| `frame_community_01` | _(unresolved: frame_community_01_name)_ | frame |  | unresolved |
| `frame_dev` | _(unresolved: frame_dev_name)_ | frame |  | unresolved |
| `frame_divine` | _(unresolved: frame_dlc_reikwald_river_name)_ | frame |  | unresolved |
| `frame_drachenfels_01` | _(unresolved: frame_drachenfels_01_name)_ | frame |  | unresolved |
| `frame_drachenfels_02` | _(unresolved: frame_drachenfels_02_name)_ | frame |  | unresolved |
| `frame_drachenfels_03` | _(unresolved: frame_drachenfels_03_name)_ | frame |  | unresolved |
| `frame_drachenfels_04` | _(unresolved: frame_drachenfels_04_name)_ | frame |  | unresolved |
| `frame_drachenfels_05` | _(unresolved: frame_drachenfels_05_name)_ | frame |  | unresolved |
| `frame_dwarf_fest` | _(unresolved: frame_dwarf_fest_name)_ | frame |  | unresolved |
| `frame_geheimnisnacht_01` | _(unresolved: frame_geheimnisnacht_01_name)_ | frame |  | unresolved |
| `frame_geheimnisnacht_02` | _(unresolved: frame_geheimnisnacht_02_name)_ | frame |  | unresolved |
| `frame_geheimnisnacht_03` | _(unresolved: frame_geheimnisnacht_03_name)_ | frame |  | unresolved |
| `frame_geheimnisnacht_04` | _(unresolved: frame_0112_name)_ | frame |  | unresolved |
| `frame_geheimnisnacht_05` | _(unresolved: frame_0113_name)_ | frame |  | unresolved |
| `frame_geheimnisnacht_2024` | _(unresolved: portrait_frame_geheimnisnacht_2024_name)_ | frame |  | unresolved |
| `frame_geheimnisnacht_2025` | _(unresolved: frame_geheimnisnacht_2025_name)_ | frame |  | unresolved |
| `frame_geheimnisnacht_2026` | _(unresolved: frame_geheimnisnacht_2026_name)_ | frame |  | unresolved |
| `frame_globadier_01` | _(unresolved: frame_versus_portrait_globadier_01_name)_ | frame |  | unresolved |
| `frame_globadier_02` | _(unresolved: frame_versus_portrait_globadier_02_name)_ | frame |  | unresolved |
| `frame_gotwf_01` | _(unresolved: frame_gotwf_name)_ | frame |  | unresolved |
| `frame_gotwf_2024` | _(unresolved: frame_gotwf_2024_name)_ | frame |  | unresolved |
| `frame_gotwf_2025` | _(unresolved: frame_gotwf_2025_name)_ | frame |  | unresolved |
| `frame_gotwf_2026` | _(unresolved: frame_gotwf_2026_name)_ | frame |  | unresolved |
| `frame_gutter_runner_01` | _(unresolved: frame_versus_portrait_gutter_runner_01_name)_ | frame |  | unresolved |
| `frame_gutter_runner_02` | _(unresolved: frame_versus_portrait_gutter_runner_02_name)_ | frame |  | unresolved |
| `frame_holly_01` | _(unresolved: frame_holly_01_name)_ | frame |  | unresolved |
| `frame_holly_02` | _(unresolved: frame_holly_02_name)_ | frame |  | unresolved |
| `frame_holly_03` | _(unresolved: frame_holly_03_name)_ | frame |  | unresolved |
| `frame_holly_04` | _(unresolved: frame_holly_04_name)_ | frame |  | unresolved |
| `frame_karak_01` | _(unresolved: frame_karak_01_name)_ | frame |  | unresolved |
| `frame_karak_02` | _(unresolved: frame_karak_02_name)_ | frame |  | unresolved |
| `frame_karak_03` | _(unresolved: frame_karak_03_name)_ | frame |  | unresolved |
| `frame_karak_04` | _(unresolved: frame_karak_04_name)_ | frame |  | unresolved |
| `frame_karak_05` | _(unresolved: frame_karak_05_name)_ | frame |  | unresolved |
| `frame_mondstille_01` | _(unresolved: frame_mondstille_01_name)_ | frame |  | unresolved |
| `frame_mondstille_02` | _(unresolved: frame_mondstille_02_name)_ | frame |  | unresolved |
| `frame_mondstille_03` | _(unresolved: frame_mondstille_03_name)_ | frame |  | unresolved |
| `frame_necromancer_01` | _(unresolved: frame_necromancer_03_name)_ | frame |  | unresolved |
| `frame_necromancer_02` | _(unresolved: frame_necromancer_01_name)_ | frame |  | unresolved |
| `frame_necromancer_03` | _(unresolved: frame_necromancer_02_name)_ | frame |  | unresolved |
| `frame_packmaster_01` | _(unresolved: frame_versus_portrait_packmaster_01_name)_ | frame |  | unresolved |
| `frame_packmaster_02` | _(unresolved: frame_versus_portrait_packmaster_02_name)_ | frame |  | unresolved |
| `frame_rat_ogre_01` | _(unresolved: frame_rat_ogre_01_name)_ | frame |  | unresolved |
| `frame_rat_ogre_02` | _(unresolved: frame_rat_ogre_02_name)_ | frame |  | unresolved |
| `frame_ratling_gunner_01` | _(unresolved: frame_versus_portrait_ratling_gunner_01_name)_ | frame |  | unresolved |
| `frame_ratling_gunner_02` | _(unresolved: frame_versus_portrait_ratling_gunner_02_name)_ | frame |  | unresolved |
| `frame_scorpion_complete_all_helmgart_level_achievements_cataclysm` | _(unresolved: frame_scorpion_complete_all_helmgart_level_achievements_cataclysm_name)_ | frame |  | unresolved |
| `frame_scorpion_complete_all_helmgart_levels_cataclysm` | _(unresolved: frame_scorpion_complete_all_helmgart_levels_cataclysm_name)_ | frame |  | unresolved |
| `frame_scorpion_complete_bogenhafen_cataclysm` | _(unresolved: frame_scorpion_complete_bogenhafen_cataclysm_name)_ | frame |  | unresolved |
| `frame_scorpion_complete_crater_cataclysm` | _(unresolved: frame_scorpion_complete_crater_cataclysm_name)_ | frame |  | unresolved |
| `frame_scorpion_complete_crater_champion` | _(unresolved: frame_scorpion_complete_crater_champion_name)_ | frame |  | unresolved |
| `frame_scorpion_complete_crater_legend` | _(unresolved: frame_scorpion_complete_crater_legend_name)_ | frame |  | unresolved |
| `frame_scorpion_complete_crater_recruit` | _(unresolved: frame_scorpion_complete_crater_recruit_name)_ | frame |  | unresolved |
| `frame_scorpion_complete_crater_veteran` | _(unresolved: frame_scorpion_complete_crater_veteran_name)_ | frame |  | unresolved |
| `frame_scorpion_complete_plaza_cataclysm` | _(unresolved: frame_scorpion_complete_plaza_cataclysm_name)_ | frame |  | unresolved |
| `frame_scorpion_season_1_beasts` | _(unresolved: frame_scorpion_season_1_beasts_name)_ | frame |  | unresolved |
| `frame_scorpion_season_1_cataclysm_1` | _(unresolved: frame_scorpion_season_1_cataclysm_1_name)_ | frame |  | unresolved |
| `frame_scorpion_season_1_cataclysm_2` | _(unresolved: frame_scorpion_season_1_cataclysm_2_name)_ | frame |  | unresolved |
| `frame_scorpion_season_1_cataclysm_3` | _(unresolved: frame_scorpion_season_1_cataclysm_3_name)_ | frame |  | unresolved |
| `frame_scorpion_season_1_death` | _(unresolved: frame_scorpion_season_1_death_name)_ | frame |  | unresolved |
| `frame_scorpion_season_1_fire` | _(unresolved: frame_scorpion_season_1_fire_name)_ | frame |  | unresolved |
| `frame_scorpion_season_1_heavens` | _(unresolved: frame_scorpion_season_1_heavens_name)_ | frame |  | unresolved |
| `frame_scorpion_season_1_life` | _(unresolved: frame_scorpion_season_1_life_name)_ | frame |  | unresolved |
| `frame_scorpion_season_1_light` | _(unresolved: frame_scorpion_season_1_light_name)_ | frame |  | unresolved |
| `frame_scorpion_season_1_metal` | _(unresolved: frame_scorpion_season_1_metal_name)_ | frame |  | unresolved |
| `frame_scorpion_season_1_shadow` | _(unresolved: frame_scorpion_season_1_shadow_name)_ | frame |  | unresolved |
| `frame_season_03_quickplay` | _(unresolved: portrait_frame_season_03_quickplay_name)_ | frame |  | unresolved |
| `frame_season_03_tier_1` | _(unresolved: portrait_frame_season_03_tier_1_name)_ | frame |  | unresolved |
| `frame_season_03_tier_2` | _(unresolved: portrait_frame_season_03_tier_2_name)_ | frame |  | unresolved |
| `frame_season_03_tier_3` | _(unresolved: portrait_frame_season_03_tier_3_name)_ | frame |  | unresolved |
| `frame_season_04_quickplay` | _(unresolved: portrait_frame_season_04_quickplay_name)_ | frame |  | unresolved |
| `frame_season_04_tier_1` | _(unresolved: portrait_frame_season_04_tier_1_name)_ | frame |  | unresolved |
| `frame_season_04_tier_2` | _(unresolved: portrait_frame_season_04_tier_2_name)_ | frame |  | unresolved |
| `frame_season_04_tier_3` | _(unresolved: portrait_frame_season_04_tier_3_name)_ | frame |  | unresolved |
| `frame_season_04_tier_4` | _(unresolved: portrait_frame_season_04_tier_4_name)_ | frame |  | unresolved |
| `frame_skulls` | _(unresolved: frame_skulls_name)_ | frame |  | unresolved |
| `frame_skulls_2021` | _(unresolved: portrait_frame_skulls_2021_name)_ | frame |  | unresolved |
| `frame_skulls_2022` | _(unresolved: portrait_frame_skulls_2022_name)_ | frame |  | unresolved |
| `frame_skulls_2023` | _(unresolved: portrait_frame_skulls_2023_name)_ | frame |  | unresolved |
| `frame_skulls_2024` | _(unresolved: portrait_frame_skulls_2024_name)_ | frame |  | unresolved |
| `frame_skulls_2025` | _(unresolved: frame_skulls_2025_name)_ | frame |  | unresolved |
| `frame_skulls_2026` | _(unresolved: frame_skulls_2026_name)_ | frame |  | unresolved |
| `frame_streamer` | _(unresolved: frame_streamer_name)_ | frame |  | unresolved |
| `frame_summer` | _(unresolved: frame_summer_name)_ | frame |  | unresolved |
| `frame_termite_01` | _(unresolved: frame_termite_01_name)_ | frame |  | unresolved |
| `frame_termite_02` | _(unresolved: frame_termite_02_name)_ | frame |  | unresolved |
| `frame_termite_03` | _(unresolved: frame_termite_03_name)_ | frame |  | unresolved |
| `frame_troll_01` | _(unresolved: frame_versus_portrait_troll_01_name)_ | frame |  | unresolved |
| `frame_troll_02` | _(unresolved: frame_versus_portrait_troll_02_name)_ | frame |  | unresolved |
| `frame_tyot_creator` | _(unresolved: frame_divine_creator_name)_ | frame |  | unresolved |
| `frame_versus_01` | _(unresolved: frame_versus_portrait_01_name)_ | frame |  | unresolved |
| `frame_versus_02` | _(unresolved: frame_versus_portrait_02_name)_ | frame |  | unresolved |
| `frame_warpfire_thrower_01` | _(unresolved: frame_versus_portrait_warpfire_thrower_01_name)_ | frame |  | unresolved |
| `frame_warpfire_thrower_02` | _(unresolved: frame_versus_portrait_warpfire_thrower_02_name)_ | frame |  | unresolved |
| `frame_wizards_tower_01` | _(unresolved: frame_wizards_tower_01_name)_ | frame |  | unresolved |
| `frame_wizards_trail_01` | _(unresolved: frame_wizards_trail_01_name)_ | frame |  | unresolved |
| `frame_year_of_the_rat` | _(unresolved: frame_rat_name)_ | frame |  | unresolved |

### kind: grenade (6 entries, 6 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `grenade_engineer` | _(unresolved: )_ | grenade |  | unresolved |
| `grenade_fire_01` | _(unresolved: )_ | grenade |  | unresolved |
| `grenade_fire_02` | _(unresolved: )_ | grenade |  | unresolved |
| `grenade_frag_01` | _(unresolved: )_ | grenade |  | unresolved |
| `grenade_frag_02` | _(unresolved: )_ | grenade |  | unresolved |
| `shadow_flare` | _(unresolved: )_ | grenade |  | unresolved |

### kind: hat (307 entries, 307 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `adept_hat_0000` | _(unresolved: display_name_adept_hat_0000)_ | hat | bw_adept | unresolved |
| `adept_hat_0001` | _(unresolved: display_name_adept_hat_0001)_ | hat | bw_adept | unresolved |
| `adept_hat_0002` | _(unresolved: display_name_adept_hat_0002)_ | hat | bw_adept | unresolved |
| `adept_hat_0003` | _(unresolved: display_name_adept_hat_0003)_ | hat | bw_adept | unresolved |
| `adept_hat_0004` | _(unresolved: display_name_adept_hat_0004)_ | hat | bw_adept | unresolved |
| `adept_hat_0005` | _(unresolved: display_name_adept_hat_0005)_ _(dlc:bogenhafen)_ | hat | bw_adept | unresolved |
| `adept_hat_0006` | _(unresolved: display_name_adept_hat_0006)_ | hat | bw_adept | unresolved |
| `adept_hat_0007` | _(unresolved: display_name_adept_hat_0007)_ | hat | bw_adept | unresolved |
| `adept_hat_0008` | _(unresolved: display_name_adept_hat_0008)_ | hat | bw_adept | unresolved |
| `adept_hat_0009` | _(unresolved: display_name_adept_hat_0009)_ | hat | bw_adept | unresolved |
| `adept_hat_0010` | _(unresolved: display_name_adept_hat_0010)_ | hat | bw_adept | unresolved |
| `adept_hat_1001` | _(unresolved: display_name_adept_hat_1001)_ | hat | bw_adept | unresolved |
| `adept_hat_1002` | _(unresolved: display_name_adept_hat_1002)_ | hat | bw_adept | unresolved |
| `adept_hat_1003` | _(unresolved: display_name_adept_hat_1003)_ | hat | bw_adept | unresolved |
| `adept_hat_1005` | _(unresolved: display_name_adept_hat_1005)_ | hat | bw_adept | unresolved |
| `adept_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | hat | bw_adept, bw_scholar, bw_unchained | unresolved |
| `bountyhunter_hat_0000` | _(unresolved: display_name_bountyhunter_hat_0000)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_0001` | _(unresolved: display_name_bountyhunter_hat_0001)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_0002` | _(unresolved: display_name_bountyhunter_hat_0002)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_0003` | _(unresolved: display_name_bountyhunter_hat_0003)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_0004` | _(unresolved: display_name_bountyhunter_hat_0004)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_0005` | _(unresolved: display_name_bountyhunter_hat_0005)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_0006` | _(unresolved: display_name_bountyhunter_hat_0006)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_0007` | _(unresolved: display_name_bountyhunter_hat_0007)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_0008` | _(unresolved: display_name_bountyhunter_hat_0008)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_0009` | _(unresolved: display_name_bountyhunter_hat_0009)_ _(dlc:bogenhafen)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_1001` | _(unresolved: display_name_bountyhunter_hat_1001)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_1002` | _(unresolved: display_name_bountyhunter_hat_1002)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_1004` | _(unresolved: display_name_bountyhunter_hat_1004)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_1005` | _(unresolved: display_name_bountyhunter_hat_1005)_ | hat | wh_bountyhunter | unresolved |
| `bountyhunter_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | hat | wh_bountyhunter, wh_captain | unresolved |
| `bw_gate_0000` | _(unresolved: display_name_bw_gate_0001)_ | hat | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_gate_0001` | _(unresolved: display_name_bw_gate_0001)_ | hat | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_gate_0006` | _(unresolved: display_name_bw_gate_0006)_ | hat | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_gate_0007` | _(unresolved: display_name_bw_gate_0007)_ | hat | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_gate_0008` | _(unresolved: display_name_bw_gate_0008)_ | hat | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_necromancer_hat_0000` | _(unresolved: bw_necromancer_hat_0000)_ _(dlc:shovel)_ | hat | bw_necromancer | unresolved |
| `bw_necromancer_hat_0001` | _(unresolved: bw_necromancer_hat_0001)_ _(dlc:shovel_upgrade)_ | hat | bw_necromancer | unresolved |
| `bw_necromancer_hat_0002` | _(unresolved: bw_necromancer_hat_0002)_ _(dlc:shovel_upgrade)_ | hat | bw_necromancer | unresolved |
| `bw_necromancer_hat_0003` | _(unresolved: bw_necromancer_hat_0003)_ _(dlc:shovel_upgrade)_ | hat | bw_necromancer | unresolved |
| `bw_necromancer_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | hat | bw_necromancer | unresolved |
| `dr_helmet_0000` | _(unresolved: display_name_dr_helmet_0001)_ | hat | dr_ironbreaker, dr_ranger | unresolved |
| `dr_helmet_0001` | _(unresolved: display_name_dr_helmet_0001)_ | hat | dr_ironbreaker, dr_ranger | unresolved |
| `dr_helmet_0002` | _(unresolved: display_name_dr_helmet_0002)_ | hat | dr_ironbreaker, dr_ranger | unresolved |
| `dr_helmet_0003` | _(unresolved: display_name_dr_helmet_0003)_ | hat | dr_ironbreaker, dr_ranger | unresolved |
| `dr_helmet_0005` | _(unresolved: display_name_dr_helmet_0005)_ | hat | dr_ironbreaker, dr_ranger | unresolved |
| `dr_helmet_0008` | _(unresolved: display_name_dr_helmet_0008)_ | hat | dr_ironbreaker, dr_ranger | unresolved |
| `dr_helmet_0011` | _(unresolved: display_name_dr_helmet_0011)_ | hat | dr_ironbreaker, dr_ranger | unresolved |
| `dr_slayer_hair_0002` | _(unresolved: dr_slayer_hair_0002)_ | hat | dr_slayer | unresolved |
| `engineer_hat_0000` | _(unresolved: display_name_engineer_hat_0000)_ _(dlc:cog)_ | hat | dr_engineer | unresolved |
| `engineer_hat_0001` | _(unresolved: display_name_engineer_hat_0001)_ _(dlc:cog)_ | hat | dr_engineer | unresolved |
| `engineer_hat_1001` | _(unresolved: display_name_engineer_hat_1001)_ _(dlc:cog)_ | hat | dr_engineer | unresolved |
| `engineer_hat_1002` | _(unresolved: display_name_engineer_hat_1002)_ _(dlc:cog)_ | hat | dr_engineer | unresolved |
| `es_hat_0000` | _(unresolved: display_name_es_hat_0001)_ | hat | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_hat_0001` | _(unresolved: display_name_es_hat_0001)_ | hat | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_hat_0002` | _(unresolved: display_name_es_hat_0002)_ | hat | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_hat_0003` | _(unresolved: display_name_es_hat_0003)_ | hat | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_helmet_0003` | _(unresolved: display_name_es_helmet_0003)_ | hat | es_huntsman, es_knight, es_mercenary | unresolved |
| `huntsman_hat_0000` | _(unresolved: display_name_huntsman_hat_0000)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_0001` | _(unresolved: display_name_huntsman_hat_0001)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_0002` | _(unresolved: display_name_huntsman_hat_0002)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_0003` | _(unresolved: display_name_huntsman_hat_0003)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_0004` | _(unresolved: display_name_huntsman_hat_0004)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_0005` | _(unresolved: display_name_huntsman_hat_0005)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_0006` | _(unresolved: display_name_huntsman_hat_0006)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_0007` | _(unresolved: display_name_huntsman_hat_0007)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_0008` | _(unresolved: display_name_huntsman_hat_0008)_ _(dlc:bogenhafen)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_0009` | _(unresolved: display_name_huntsman_hat_0009)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_1001` | _(unresolved: display_name_huntsman_hat_1001)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_1002` | _(unresolved: display_name_huntsman_hat_1002)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_1003` | _(unresolved: display_name_huntsman_hat_1003)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_1005` | _(unresolved: display_name_huntsman_hat_1005)_ | hat | es_huntsman | unresolved |
| `huntsman_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | hat | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `ironbreaker_hat_0000` | _(unresolved: display_name_ironbreaker_hat_0000)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0001` | _(unresolved: display_name_ironbreaker_hat_0001)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0002` | _(unresolved: display_name_ironbreaker_hat_0002)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0003` | _(unresolved: display_name_ironbreaker_hat_0003)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0004` | _(unresolved: display_name_ironbreaker_hat_0004)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0005` | _(unresolved: display_name_ironbreaker_hat_0005)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0006` | _(unresolved: display_name_ironbreaker_hat_0006)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0007` | _(unresolved: display_name_ironbreaker_hat_0007)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0008` | _(unresolved: display_name_ironbreaker_hat_0008)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0009` | _(unresolved: display_name_ironbreaker_hat_0009)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0010` | _(unresolved: display_name_ironbreaker_hat_0010)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0011` | _(unresolved: display_name_ironbreaker_hat_0011)_ _(dlc:bogenhafen)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0012` | _(unresolved: display_name_ironbreaker_hat_0012)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_0013` | _(unresolved: display_name_ironbreaker_hat_0013)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_1001` | _(unresolved: display_name_ironbreaker_hat_1001)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_1002` | _(unresolved: display_name_ironbreaker_hat_1002)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_1004` | _(unresolved: display_name_ironbreaker_hat_1004)_ | hat | dr_ironbreaker | unresolved |
| `ironbreaker_hat_1005` | _(unresolved: display_name_ironbreaker_hat_1005)_ | hat | dr_ironbreaker | unresolved |
| `knight_hat_0000` | _(unresolved: display_name_knight_hat_0000)_ | hat | es_knight | unresolved |
| `knight_hat_0001` | _(unresolved: display_name_knight_hat_0001)_ | hat | es_knight | unresolved |
| `knight_hat_0002` | _(unresolved: display_name_knight_hat_0002)_ | hat | es_knight | unresolved |
| `knight_hat_0003` | _(unresolved: display_name_knight_hat_0003)_ | hat | es_knight | unresolved |
| `knight_hat_0004` | _(unresolved: display_name_knight_hat_0004)_ | hat | es_knight | unresolved |
| `knight_hat_0005` | _(unresolved: display_name_knight_hat_0005)_ | hat | es_knight | unresolved |
| `knight_hat_0006` | _(unresolved: display_name_knight_hat_0006)_ | hat | es_knight | unresolved |
| `knight_hat_0007` | _(unresolved: display_name_knight_hat_0007)_ _(dlc:bogenhafen)_ | hat | es_knight | unresolved |
| `knight_hat_0008` | _(unresolved: display_name_knight_hat_0008)_ | hat | es_knight | unresolved |
| `knight_hat_0009` | _(unresolved: display_name_knight_hat_0009)_ | hat | es_knight | unresolved |
| `knight_hat_0010` | _(unresolved: display_name_knight_hat_0010)_ | hat | es_knight | unresolved |
| `knight_hat_0011` | _(unresolved: display_name_knight_hat_0011)_ | hat | es_knight | unresolved |
| `knight_hat_1001` | _(unresolved: display_name_knight_hat_1001)_ | hat | es_knight | unresolved |
| `knight_hat_1002` | _(unresolved: display_name_knight_hat_1002)_ | hat | es_knight | unresolved |
| `knight_hat_1003` | _(unresolved: display_name_knight_hat_1003)_ | hat | es_knight | unresolved |
| `maidenguard_hat_0000` | _(unresolved: display_name_maidenguard_hat_0000)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_0001` | _(unresolved: display_name_maidenguard_hat_0001)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_0002` | _(unresolved: display_name_maidenguard_hat_0002)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_0003` | _(unresolved: display_name_maidenguard_hat_0003)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_0004` | _(unresolved: display_name_maidenguard_hat_0004)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_0005` | _(unresolved: display_name_maidenguard_hat_0005)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_0006` | _(unresolved: display_name_maidenguard_hat_0006)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_0007` | _(unresolved: display_name_maidenguard_hat_0007)_ _(dlc:bogenhafen)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_0008` | _(unresolved: display_name_maidenguard_hat_0008)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_0009` | _(unresolved: display_name_maidenguard_hat_0009)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_0010` | _(unresolved: display_name_maidenguard_hat_0010)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_1001` | _(unresolved: display_name_maidenguard_hat_1001)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_1002` | _(unresolved: display_name_maidenguard_hat_1002)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_1004` | _(unresolved: display_name_maidenguard_hat_1004)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_1005` | _(unresolved: display_name_maidenguard_hat_1005)_ | hat | we_maidenguard | unresolved |
| `maidenguard_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | hat | we_maidenguard | unresolved |
| `mercenary_hat_0000` | _(unresolved: display_name_mercenary_hat_0000)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_0001` | _(unresolved: display_name_mercenary_hat_0001)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_0002` | _(unresolved: display_name_mercenary_hat_0002)_ _(dlc:bogenhafen)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_0003` | _(unresolved: display_name_mercenary_hat_0003)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_0004` | _(unresolved: display_name_mercenary_hat_0004)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_0005` | _(unresolved: display_name_mercenary_hat_0005)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_0006` | _(unresolved: display_name_mercenary_hat_0006)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_0007` | _(unresolved: display_name_mercenary_hat_0007)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_0008` | _(unresolved: display_name_mercenary_hat_0008)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_0009` | _(unresolved: display_name_mercenary_hat_0009)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_1001` | _(unresolved: display_name_mercenary_hat_1001)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_1002` | _(unresolved: display_name_mercenary_hat_1002)_ | hat | es_mercenary | unresolved |
| `mercenary_hat_1003` | _(unresolved: display_name_mercenary_hat_1003)_ | hat | es_mercenary | unresolved |
| `priest_hat_0000` | _(unresolved: display_name_priest_hat_0000)_ _(dlc:bless)_ | hat | wh_priest | unresolved |
| `priest_hat_0001` | _(unresolved: display_name_priest_hat_0001)_ | hat | wh_priest | unresolved |
| `priest_hat_0002` | _(unresolved: display_name_priest_hat_0002)_ | hat | wh_priest | unresolved |
| `priest_hat_0003` | _(unresolved: display_name_priest_hat_0003)_ | hat | wh_priest | unresolved |
| `priest_hat_0004` | _(unresolved: display_name_priest_hat_0004)_ | hat | wh_priest | unresolved |
| `priest_hat_1001` | _(unresolved: display_name_priest_hat_1001_2023_q1)_ _(dlc:bless)_ | hat | wh_priest | unresolved |
| `questing_knight_hat_0000` | _(unresolved: display_name_questing_knight_hat_0000)_ _(dlc:lake)_ | hat | es_questingknight | unresolved |
| `questing_knight_hat_0001` | _(unresolved: display_name_questing_knight_hat_0001)_ _(dlc:lake_upgrade)_ | hat | es_questingknight | unresolved |
| `questing_knight_hat_0003` | _(unresolved: display_name_questing_knight_hat_0003)_ _(dlc:lake_upgrade)_ | hat | es_questingknight | unresolved |
| `questing_knight_hat_1001` | _(unresolved: display_name_questing_knight_hat_1001)_ _(dlc:lake)_ | hat | es_questingknight | unresolved |
| `ranger_hat_0000` | _(unresolved: display_name_ranger_hat_0000)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0001` | _(unresolved: display_name_ranger_hat_0001)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0002` | _(unresolved: display_name_ranger_hat_0002)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0003` | _(unresolved: display_name_ranger_hat_0003)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0004` | _(unresolved: display_name_ranger_hat_0004)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0005` | _(unresolved: display_name_ranger_hat_0005)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0006` | _(unresolved: display_name_ranger_hat_0006)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0007` | _(unresolved: display_name_ranger_hat_0007)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0008` | _(unresolved: display_name_ranger_hat_0008)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0009` | _(unresolved: display_name_ranger_hat_0009)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0010` | _(unresolved: display_name_ranger_hat_0010)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0011` | _(unresolved: display_name_ranger_hat_0011)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0012` | _(unresolved: display_name_ranger_hat_0012)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0013` | _(unresolved: display_name_ranger_hat_0013)_ _(dlc:bogenhafen)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0014` | _(unresolved: display_name_ranger_hat_0014)_ | hat | dr_ranger | unresolved |
| `ranger_hat_0015` | _(unresolved: display_name_ranger_hat_0015)_ | hat | dr_ranger | unresolved |
| `ranger_hat_1001` | _(unresolved: display_name_ranger_hat_1001)_ | hat | dr_ranger | unresolved |
| `ranger_hat_1005` | _(unresolved: display_name_ranger_hat_1005)_ | hat | dr_ranger | unresolved |
| `ranger_hat_1006` | _(unresolved: display_name_ranger_hat_1006)_ | hat | dr_ranger | unresolved |
| `ranger_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | hat | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `scholar_hat_0000` | _(unresolved: display_name_scholar_hat_0000)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0001` | _(unresolved: display_name_scholar_hat_0001)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0002` | _(unresolved: display_name_scholar_hat_0002)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0003` | _(unresolved: display_name_scholar_hat_0003)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0004` | _(unresolved: display_name_scholar_hat_0004)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0005` | _(unresolved: display_name_scholar_hat_0005)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0006` | _(unresolved: display_name_scholar_hat_0006)_ _(dlc:bogenhafen)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0007` | _(unresolved: display_name_scholar_hat_0007)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0008` | _(unresolved: display_name_scholar_hat_0008)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0009` | _(unresolved: display_name_scholar_hat_0009)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0010` | _(unresolved: display_name_scholar_hat_0010)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0011` | _(unresolved: display_name_scholar_hat_0011)_ | hat | bw_scholar | unresolved |
| `scholar_hat_0012` | _(unresolved: display_name_scholar_hat_0012)_ | hat | bw_scholar | unresolved |
| `scholar_hat_1001` | _(unresolved: display_name_scholar_hat_1001)_ | hat | bw_scholar | unresolved |
| `scholar_hat_1002` | _(unresolved: display_name_scholar_hat_1002)_ | hat | bw_scholar | unresolved |
| `scholar_hat_1003` | _(unresolved: display_name_scholar_hat_1003)_ | hat | bw_scholar | unresolved |
| `scholar_hat_1004` | _(unresolved: display_name_scholar_hat_1004)_ | hat | bw_scholar | unresolved |
| `shade_hat_0000` | _(unresolved: display_name_shade_hat_0000)_ | hat | we_shade | unresolved |
| `shade_hat_0001` | _(unresolved: display_name_shade_hat_0001)_ | hat | we_shade | unresolved |
| `shade_hat_0002` | _(unresolved: display_name_shade_hat_0002)_ | hat | we_shade | unresolved |
| `shade_hat_0003` | _(unresolved: display_name_shade_hat_0003)_ | hat | we_shade | unresolved |
| `shade_hat_0004` | _(unresolved: display_name_shade_hat_0004)_ | hat | we_shade | unresolved |
| `shade_hat_0005` | _(unresolved: display_name_shade_hat_0005)_ | hat | we_shade | unresolved |
| `shade_hat_0006` | _(unresolved: display_name_shade_hat_0006)_ | hat | we_shade | unresolved |
| `shade_hat_0007` | _(unresolved: display_name_shade_hat_0007)_ | hat | we_shade | unresolved |
| `shade_hat_0008` | _(unresolved: display_name_shade_hat_0008)_ _(dlc:bogenhafen)_ | hat | we_shade | unresolved |
| `shade_hat_0009` | _(unresolved: display_name_shade_hat_0009)_ | hat | we_shade | unresolved |
| `shade_hat_0010` | _(unresolved: display_name_shade_hat_0010)_ | hat | we_shade | unresolved |
| `shade_hat_1001` | _(unresolved: display_name_shade_hat_1001)_ | hat | we_shade | unresolved |
| `shade_hat_1002` | _(unresolved: display_name_shade_hat_1002)_ | hat | we_shade | unresolved |
| `shade_hat_1003` | _(unresolved: display_name_shade_hat_1003)_ | hat | we_shade | unresolved |
| `shade_hat_1004` | _(unresolved: display_name_shade_hat_1004)_ | hat | we_shade | unresolved |
| `shade_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | hat | we_shade | unresolved |
| `slayer_hat_0000` | _(unresolved: display_name_slayer_hat_0000)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0001` | _(unresolved: display_name_slayer_hat_0001)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0002` | _(unresolved: display_name_slayer_hat_0002)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0003` | _(unresolved: display_name_slayer_hat_0003)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0004` | _(unresolved: display_name_slayer_hat_0004)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0005` | _(unresolved: display_name_slayer_hat_0005)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0006` | _(unresolved: display_name_slayer_hat_0006)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0007` | _(unresolved: display_name_slayer_hat_0007)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0008` | _(unresolved: display_name_slayer_hat_0008)_ _(dlc:bogenhafen)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0009` | _(unresolved: display_name_slayer_hat_0009)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0010` | _(unresolved: display_name_slayer_hat_0010)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0011` | _(unresolved: display_name_slayer_hat_0011)_ | hat | dr_slayer | unresolved |
| `slayer_hat_0012` | _(unresolved: display_name_slayer_hat_0012)_ | hat | dr_slayer | unresolved |
| `slayer_hat_1001` | _(unresolved: display_name_slayer_hat_1001)_ | hat | dr_slayer | unresolved |
| `slayer_hat_1002` | _(unresolved: display_name_slayer_hat_1002)_ | hat | dr_slayer | unresolved |
| `slayer_hat_1005` | _(unresolved: display_name_slayer_hat_1005)_ | hat | dr_slayer | unresolved |
| `slayer_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | hat | dr_slayer | unresolved |
| `test_item_1001` | _(unresolved: test_item_1001)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1002` | _(unresolved: test_item_1002)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1003` | _(unresolved: test_item_1003)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1004` | _(unresolved: test_item_1004)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1005` | _(unresolved: test_item_1005)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1006` | _(unresolved: test_item_1006)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1007` | _(unresolved: test_item_1007)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1008` | _(unresolved: test_item_1008)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1009` | _(unresolved: test_item_1009)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1010` | _(unresolved: test_item_1010)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1011` | _(unresolved: test_item_1011)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1012` | _(unresolved: test_item_1012)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1013` | _(unresolved: test_item_1013)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1014` | _(unresolved: test_item_1014)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1015` | _(unresolved: test_item_1015)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1017` | _(unresolved: test_item_1017)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `test_item_1018` | _(unresolved: test_item_1018)_ | hat | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `thornsister_hat_0000` | _(unresolved: display_name_thornsister_hat_0000)_ _(dlc:woods)_ | hat | we_thornsister | unresolved |
| `thornsister_hat_0001` | _(unresolved: display_name_thornsister_hat_0001)_ _(dlc:woods)_ | hat | we_thornsister | unresolved |
| `thornsister_hat_0002` | _(unresolved: display_name_thornsister_hat_0002)_ _(dlc:woods)_ | hat | we_thornsister | unresolved |
| `thornsister_hat_0003` | _(unresolved: display_name_thornsister_hat_0003)_ _(dlc:woods)_ | hat | we_thornsister | unresolved |
| `thornsister_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | hat | we_thornsister | unresolved |
| `unchained_hat_0000` | _(unresolved: display_name_unchained_hat_0000)_ | hat | bw_unchained | unresolved |
| `unchained_hat_0001` | _(unresolved: display_name_unchained_hat_0001)_ _(dlc:bogenhafen)_ | hat | bw_unchained | unresolved |
| `unchained_hat_0002` | _(unresolved: display_name_unchained_hat_0002)_ | hat | bw_unchained | unresolved |
| `unchained_hat_0003` | _(unresolved: display_name_unchained_hat_0003)_ | hat | bw_unchained | unresolved |
| `unchained_hat_0004` | _(unresolved: display_name_unchained_hat_0004)_ | hat | bw_unchained | unresolved |
| `unchained_hat_0005` | _(unresolved: display_name_unchained_hat_0005)_ | hat | bw_unchained | unresolved |
| `unchained_hat_0006` | _(unresolved: display_name_unchained_hat_0006)_ | hat | bw_unchained | unresolved |
| `unchained_hat_0007` | _(unresolved: display_name_unchained_hat_0007)_ | hat | bw_unchained | unresolved |
| `unchained_hat_0008` | _(unresolved: display_name_unchained_hat_0008)_ | hat | bw_unchained | unresolved |
| `unchained_hat_0009` | _(unresolved: display_name_unchained_hat_0009)_ | hat | bw_unchained | unresolved |
| `unchained_hat_1001` | _(unresolved: display_name_unchained_hat_1001)_ | hat | bw_unchained | unresolved |
| `unchained_hat_1003` | _(unresolved: display_name_unchained_hat_1003)_ | hat | bw_unchained | unresolved |
| `unchained_hat_1004` | _(unresolved: display_name_unchained_hat_1004)_ | hat | bw_unchained | unresolved |
| `waywatcher_hat_0000` | _(unresolved: display_name_waywatcher_hat_0000)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_0001` | _(unresolved: display_name_waywatcher_hat_0001)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_0002` | _(unresolved: display_name_waywatcher_hat_0002)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_0003` | _(unresolved: display_name_waywatcher_hat_0003)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_0004` | _(unresolved: display_name_waywatcher_hat_0004)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_0005` | _(unresolved: display_name_waywatcher_hat_0005)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_0006` | _(unresolved: display_name_waywatcher_hat_0006)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_0007` | _(unresolved: display_name_waywatcher_hat_0007)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_0008` | _(unresolved: display_name_waywatcher_hat_0008)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_0009` | _(unresolved: display_name_waywatcher_hat_0009)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_0010` | _(unresolved: display_name_waywatcher_hat_0010)_ _(dlc:bogenhafen)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_0011` | _(unresolved: display_name_waywatcher_hat_0011)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_1001` | _(unresolved: display_name_waywatcher_hat_1001)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_1004` | _(unresolved: display_name_waywatcher_hat_1004)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_1005` | _(unresolved: display_name_waywatcher_hat_1005)_ | hat | we_waywatcher | unresolved |
| `waywatcher_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | hat | we_waywatcher | unresolved |
| `wh_hat_0000` | _(unresolved: display_name_wh_hat_0001)_ | hat | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_hat_0001` | _(unresolved: display_name_wh_hat_0001)_ | hat | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_hat_0003` | _(unresolved: display_name_wh_hat_0003)_ | hat | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_hat_0007` | _(unresolved: display_name_wh_hat_0007)_ | hat | wh_zealot | unresolved |
| `wh_hat_0008` | _(unresolved: display_name_wh_hat_0008)_ | hat | wh_bountyhunter | unresolved |
| `wh_hat_0009` | _(unresolved: display_name_wh_hat_0008)_ | hat | wh_bountyhunter | unresolved |
| `witchhunter_hat_0000` | _(unresolved: display_name_witchhunter_hat_0000)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_0001` | _(unresolved: display_name_witchhunter_hat_0001)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_0002` | _(unresolved: display_name_witchhunter_hat_0002)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_0003` | _(unresolved: display_name_witchhunter_hat_0003)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_0004` | _(unresolved: display_name_witchhunter_hat_0004)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_0005` | _(unresolved: display_name_witchhunter_hat_0005)_ _(dlc:bogenhafen)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_0006` | _(unresolved: display_name_witchhunter_hat_0006)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_0007` | _(unresolved: display_name_witchhunter_hat_0007)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_0008` | _(unresolved: display_name_witchhunter_hat_0008)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_0009` | _(unresolved: display_name_witchhunter_hat_0009)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_0010` | _(unresolved: display_name_witchhunter_hat_0010)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_1001` | _(unresolved: display_name_witchhunter_hat_1001)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_1003` | _(unresolved: display_name_witchhunter_hat_1003)_ | hat | wh_captain | unresolved |
| `witchhunter_hat_1004` | _(unresolved: display_name_witchhunter_hat_1004)_ | hat | wh_captain | unresolved |
| `ww_hood_0000` | _(unresolved: display_name_ww_hood_0001)_ | hat | we_maidenguard, we_waywatcher | unresolved |
| `ww_hood_0001` | _(unresolved: display_name_ww_hood_0001)_ | hat | we_maidenguard, we_waywatcher | unresolved |
| `ww_hood_0002` | _(unresolved: display_name_ww_hood_0002)_ | hat | we_maidenguard, we_waywatcher | unresolved |
| `ww_hood_0004` | _(unresolved: display_name_ww_hood_0004)_ | hat | we_maidenguard, we_waywatcher | unresolved |
| `zealot_hat_0000` | _(unresolved: display_name_zealot_hat_0000)_ | hat | wh_zealot | unresolved |
| `zealot_hat_0001` | _(unresolved: display_name_zealot_hat_0001)_ | hat | wh_zealot | unresolved |
| `zealot_hat_0002` | _(unresolved: display_name_zealot_hat_0002)_ | hat | wh_zealot | unresolved |
| `zealot_hat_0003` | _(unresolved: display_name_zealot_hat_0003)_ | hat | wh_zealot | unresolved |
| `zealot_hat_0004` | _(unresolved: display_name_zealot_hat_0004)_ | hat | wh_zealot | unresolved |
| `zealot_hat_0005` | _(unresolved: display_name_zealot_hat_0005)_ | hat | wh_zealot | unresolved |
| `zealot_hat_0006` | _(unresolved: display_name_zealot_hat_0006)_ | hat | wh_zealot | unresolved |
| `zealot_hat_0007` | _(unresolved: display_name_zealot_hat_0007)_ | hat | wh_zealot | unresolved |
| `zealot_hat_0008` | _(unresolved: display_name_zealot_hat_0008)_ _(dlc:bogenhafen)_ | hat | wh_zealot | unresolved |
| `zealot_hat_0009` | _(unresolved: display_name_zealot_hat_0009)_ | hat | wh_zealot | unresolved |
| `zealot_hat_0010` | _(unresolved: display_name_zealot_hat_0010)_ | hat | wh_zealot | unresolved |
| `zealot_hat_0011` | _(unresolved: display_name_zealot_hat_0011)_ | hat | wh_zealot | unresolved |
| `zealot_hat_1001` | _(unresolved: display_name_zealot_hat_1001)_ | hat | wh_zealot | unresolved |
| `zealot_hat_1002` | _(unresolved: display_name_zealot_hat_1002)_ | hat | wh_zealot | unresolved |
| `zealot_hat_1003` | _(unresolved: display_name_zealot_hat_1003)_ | hat | wh_zealot | unresolved |
| `zealot_hat_1007` | _(unresolved: display_name_zealot_hat_1007)_ | hat | wh_zealot | unresolved |
| `zealot_hat_1010` | _(unresolved: display_name_huntsman_hat_1006)_ | hat | wh_zealot | unresolved |

### kind: healthkit (25 entries, 25 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `beer_barrel` | _(unresolved: )_ | inventory_item |  | unresolved |
| `door_stick` | _(unresolved: )_ | inventory_item |  | unresolved |
| `dwarf_beer_barrel` | _(unresolved: )_ | inventory_item |  | unresolved |
| `dwarf_explosive_barrel` | _(unresolved: )_ | explosive_inventory_item |  | unresolved |
| `explosive_barrel` | _(unresolved: )_ | explosive_inventory_item |  | unresolved |
| `explosive_barrel_objective` | _(unresolved: )_ | explosive_inventory_item |  | unresolved |
| `grain_sack` | _(unresolved: )_ | inventory_item |  | unresolved |
| `healthkit_first_aid_kit_01` | _(unresolved: )_ | healthkit |  | unresolved |
| `lamp_oil` | _(unresolved: )_ | inventory_item |  | unresolved |
| `magic_barrel` | _(unresolved: )_ | inventory_item |  | unresolved |
| `mutator_torch` | _(unresolved: )_ | inventory_item |  | unresolved |
| `potion_healing_draught_01` | _(unresolved: )_ | healthkit |  | unresolved |
| `shadow_torch` | _(unresolved: )_ | inventory_item |  | unresolved |
| `torch` | _(unresolved: )_ | inventory_item |  | unresolved |
| `training_dummy_armored_bob` | _(unresolved: )_ | inventory_item |  | unresolved |
| `training_dummy_bob` | _(unresolved: )_ | inventory_item |  | unresolved |
| `whale_oil_barrel` | _(unresolved: )_ | explosive_inventory_item |  | unresolved |
| `wizards_barrel` | _(unresolved: )_ | inventory_item |  | unresolved |
| `wpn_cannon_ball_01` | _(unresolved: )_ | inventory_item |  | unresolved |
| `wpn_gargoyle_head` | _(unresolved: )_ | inventory_item |  | unresolved |
| `wpn_magic_crystal` | _(unresolved: )_ | inventory_item |  | unresolved |
| `wpn_shadow_gargoyle_head` | _(unresolved: )_ | inventory_item |  | unresolved |
| `wpn_side_objective_tome_01` | _(unresolved: )_ | healthkit |  | unresolved |
| `wpn_trail_cog` | _(unresolved: )_ | inventory_item |  | unresolved |
| `wpn_waystone_piece` | _(unresolved: )_ | inventory_item |  | unresolved |

### kind: item (9 entries, 9 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `bardin_ranger_career_skill_weapon` | _(unresolved: )_ |  |  | unresolved |
| `bw_necromancer_career_skill_weapon` | _(unresolved: )_ |  |  | unresolved |
| `kerillian_waywatcher_career_skill_weapon` | _(unresolved: )_ |  |  | unresolved |
| `kerillian_waywatcher_career_skill_weapon_piercing_shot` | _(unresolved: )_ |  |  | unresolved |
| `sienna_scholar_career_skill_weapon` | _(unresolved: )_ |  |  | unresolved |
| `victor_bountyhunter_career_skill_weapon` | _(unresolved: )_ |  |  | unresolved |
| `victor_bountyhunter_career_skill_weapon_vs` | _(unresolved: )_ |  |  | unresolved |
| `we_thornsister_career_skill_weapon` | _(unresolved: )_ |  |  | unresolved |
| `wh_priest_career_skill_weapon` | _(unresolved: )_ |  |  | unresolved |

### kind: loot_chest (35 entries, 35 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `bogenhafen_chest` | _(unresolved: display_name_bogenhafen_chest)_ | loot_chest |  | unresolved |
| `deed_chest` | _(unresolved: display_name_deed_chest_02)_ | loot_chest |  | unresolved |
| `level_chest` | _(unresolved: display_name_loot_level_chest_greater)_ | loot_chest |  | unresolved |
| `level_chest_02` | _(unresolved: display_name_loot_level_chest_01)_ | loot_chest |  | unresolved |
| `level_chest_lesser` | _(unresolved: display_name_loot_level_chest_01)_ | loot_chest |  | unresolved |
| `loot_chest_01_01` | _(unresolved: display_name_loot_chest_normal_01)_ | loot_chest |  | unresolved |
| `loot_chest_01_02` | _(unresolved: display_name_loot_chest_normal_02)_ | loot_chest |  | unresolved |
| `loot_chest_01_03` | _(unresolved: display_name_loot_chest_normal_03)_ | loot_chest |  | unresolved |
| `loot_chest_01_04` | _(unresolved: display_name_loot_chest_normal_04)_ | loot_chest |  | unresolved |
| `loot_chest_01_05` | _(unresolved: display_name_loot_chest_normal_05)_ | loot_chest |  | unresolved |
| `loot_chest_01_06` | _(unresolved: display_name_loot_chest_normal_06)_ | loot_chest |  | unresolved |
| `loot_chest_02_01` | _(unresolved: display_name_loot_chest_hard_01)_ | loot_chest |  | unresolved |
| `loot_chest_02_02` | _(unresolved: display_name_loot_chest_hard_02)_ | loot_chest |  | unresolved |
| `loot_chest_02_03` | _(unresolved: display_name_loot_chest_hard_03)_ | loot_chest |  | unresolved |
| `loot_chest_02_04` | _(unresolved: display_name_loot_chest_hard_04)_ | loot_chest |  | unresolved |
| `loot_chest_02_05` | _(unresolved: display_name_loot_chest_hard_05)_ | loot_chest |  | unresolved |
| `loot_chest_02_06` | _(unresolved: display_name_loot_chest_hard_06)_ | loot_chest |  | unresolved |
| `loot_chest_03_01` | _(unresolved: display_name_loot_chest_nightmare_01)_ | loot_chest |  | unresolved |
| `loot_chest_03_02` | _(unresolved: display_name_loot_chest_nightmare_02)_ | loot_chest |  | unresolved |
| `loot_chest_03_03` | _(unresolved: display_name_loot_chest_nightmare_03)_ | loot_chest |  | unresolved |
| `loot_chest_03_04` | _(unresolved: display_name_loot_chest_nightmare_04)_ | loot_chest |  | unresolved |
| `loot_chest_03_05` | _(unresolved: display_name_loot_chest_nightmare_05)_ | loot_chest |  | unresolved |
| `loot_chest_03_06` | _(unresolved: display_name_loot_chest_nightmare_06)_ | loot_chest |  | unresolved |
| `loot_chest_04_01` | _(unresolved: display_name_loot_chest_cataclysm_01)_ | loot_chest |  | unresolved |
| `loot_chest_04_02` | _(unresolved: display_name_loot_chest_cataclysm_02)_ | loot_chest |  | unresolved |
| `loot_chest_04_03` | _(unresolved: display_name_loot_chest_cataclysm_03)_ | loot_chest |  | unresolved |
| `loot_chest_04_04` | _(unresolved: display_name_loot_chest_cataclysm_04)_ | loot_chest |  | unresolved |
| `loot_chest_04_05` | _(unresolved: display_name_loot_chest_cataclysm_05)_ | loot_chest |  | unresolved |
| `loot_chest_04_06` | _(unresolved: display_name_loot_chest_cataclysm_06)_ | loot_chest |  | unresolved |
| `loot_chest_05_01` | _(unresolved: display_name_loot_chest_extended_difficulty_01_01)_ | loot_chest |  | unresolved |
| `loot_chest_05_02` | _(unresolved: display_name_loot_chest_extended_difficulty_01_02)_ | loot_chest |  | unresolved |
| `loot_chest_05_03` | _(unresolved: display_name_loot_chest_extended_difficulty_01_03)_ | loot_chest |  | unresolved |
| `loot_chest_05_04` | _(unresolved: display_name_loot_chest_extended_difficulty_01_04)_ | loot_chest |  | unresolved |
| `loot_chest_05_05` | _(unresolved: display_name_loot_chest_extended_difficulty_01_05)_ | loot_chest |  | unresolved |
| `loot_chest_05_06` | _(unresolved: display_name_loot_chest_extended_difficulty_01_06)_ | loot_chest |  | unresolved |

### kind: potion (8 entries, 8 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `bw_necromancer_career_utility_weapon` | _(unresolved: )_ |  | bw_necromancer | unresolved |
| `potion_cooldown_reduction_01` | _(unresolved: )_ | potion |  | unresolved |
| `potion_damage_boost_01` | _(unresolved: )_ | potion |  | unresolved |
| `potion_speed_boost_01` | _(unresolved: )_ | potion |  | unresolved |
| `wpn_bardin_survival_ale` | _(unresolved: )_ | potion |  | unresolved |
| `wpn_beer_bottle` | _(unresolved: )_ | potion |  | unresolved |
| `wpn_geheimnisnacht_2021_side_objective` | _(unresolved: )_ | potion |  | unresolved |
| `wpn_grimoire_01` | _(unresolved: )_ | potion |  | unresolved |

### kind: skin (210 entries, 210 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `chaos_troll_skin_0000` | _(unresolved: chaos_troll_skin_0000)_ | skin | vs_chaos_troll | unresolved |
| `skaven_gutter_runner_skin_0000` | _(unresolved: skaven_gutter_runner_skin_0000)_ | skin | vs_gutter_runner | unresolved |
| `skaven_gutter_runner_skin_0000_ektrik_01` | _(unresolved: skaven_gutter_runner_skin_0000_ektrik_01_name)_ | skin | vs_gutter_runner | unresolved |
| `skaven_gutter_runner_skin_0000_kreepus_01` | _(unresolved: skaven_gutter_runner_skin_0000_kreepus_01_name)_ | skin | vs_gutter_runner | unresolved |
| `skaven_gutter_runner_skin_0000_krizzor_01` | _(unresolved: skaven_gutter_runner_skin_0000_krizzor_01_name)_ | skin | vs_gutter_runner | unresolved |
| `skaven_gutter_runner_skin_1001` | _(unresolved: display_name_skaven_gutter_runner_skin_1001)_ | skin | vs_gutter_runner | unresolved |
| `skaven_pack_master_skin_0000` | _(unresolved: skaven_packmaster_skin_0000)_ | skin | vs_packmaster | unresolved |
| `skaven_pack_master_skin_0000_ektrik_01` | _(unresolved: skaven_packmaster_skin_0000_ektrik_01_name)_ | skin | vs_packmaster | unresolved |
| `skaven_pack_master_skin_0000_kreepus_01` | _(unresolved: skaven_packmaster_skin_0000_kreepus_01_name)_ | skin | vs_packmaster | unresolved |
| `skaven_pack_master_skin_0000_krizzor_01` | _(unresolved: skaven_packmaster_skin_0000_krizzor_01_name)_ | skin | vs_packmaster | unresolved |
| `skaven_pack_master_skin_1001` | _(unresolved: display_name_skaven_pack_master_skin_1001)_ | skin | vs_packmaster | unresolved |
| `skaven_rat_ogre_skin_0000` | _(unresolved: skaven_rat_ogre_skin_0000)_ | skin | vs_rat_ogre | unresolved |
| `skaven_ratling_gunner_skin_0000` | _(unresolved: skaven_ratling_gunner_skin_0000)_ | skin | vs_ratling_gunner | unresolved |
| `skaven_ratling_gunner_skin_0000_ektrik_01` | _(unresolved: skaven_ratling_gunner_skin_0000_ektrik_01_name)_ | skin | vs_ratling_gunner | unresolved |
| `skaven_ratling_gunner_skin_0000_kreepus_01` | _(unresolved: skaven_ratling_gunner_skin_0000_kreepus_01_name)_ | skin | vs_ratling_gunner | unresolved |
| `skaven_ratling_gunner_skin_0000_krizzor_01` | _(unresolved: skaven_ratling_gunner_skin_0000_krizzor_01_name)_ | skin | vs_ratling_gunner | unresolved |
| `skaven_ratling_gunner_skin_1001` | _(unresolved: display_name_skaven_ratling_gunner_skin_1001)_ | skin | vs_ratling_gunner | unresolved |
| `skaven_warpfire_thrower_skin_0000` | _(unresolved: skaven_warpfire_thrower_skin_0000)_ | skin | vs_warpfire_thrower | unresolved |
| `skaven_warpfire_thrower_skin_0000_ektrik_01` | _(unresolved: skaven_warpfire_thrower_skin_0000_ektrik_01_name)_ | skin | vs_warpfire_thrower | unresolved |
| `skaven_warpfire_thrower_skin_0000_kreepus_01` | _(unresolved: skaven_warpfire_thrower_skin_0000_kreepus_01_name)_ | skin | vs_warpfire_thrower | unresolved |
| `skaven_warpfire_thrower_skin_0000_krizzor_01` | _(unresolved: skaven_warpfire_thrower_skin_0000_krizzor_01_name)_ | skin | vs_warpfire_thrower | unresolved |
| `skaven_warpfire_thrower_skin_1001` | _(unresolved: display_name_skaven_warpfire_thrower_skin_1001)_ | skin | vs_warpfire_thrower | unresolved |
| `skaven_wind_globadier_skin_0000` | _(unresolved: skaven_wind_globadier_skin_0000)_ | skin | vs_poison_wind_globadier | unresolved |
| `skaven_wind_globadier_skin_0000_ektrik_01` | _(unresolved: skaven_wind_globadier_skin_0000_ektrik_01_name)_ | skin | vs_poison_wind_globadier | unresolved |
| `skaven_wind_globadier_skin_0000_kreepus_01` | _(unresolved: skaven_wind_globadier_skin_0000_kreepus_01_name)_ | skin | vs_poison_wind_globadier | unresolved |
| `skaven_wind_globadier_skin_0000_krizzor_01` | _(unresolved: skaven_wind_globadier_skin_0000_krizzor_01_name)_ | skin | vs_poison_wind_globadier | unresolved |
| `skaven_wind_globadier_skin_1001` | _(unresolved: display_name_skaven_wind_globadier_skin_1001)_ | skin | vs_poison_wind_globadier | unresolved |
| `skin_bw_adept` | _(unresolved: skin_bw_adept)_ | skin | bw_adept | unresolved |
| `skin_bw_adept_1001` | _(unresolved: display_name_skin_bw_adept_1001)_ | skin | bw_adept | unresolved |
| `skin_bw_adept_1002` | _(unresolved: display_name_skin_bw_adept_1002)_ | skin | bw_adept | unresolved |
| `skin_bw_adept_ash` | _(unresolved: skin_bw_adept_ash)_ _(dlc:bogenhafen)_ | skin | bw_adept | unresolved |
| `skin_bw_adept_black_and_gold` | _(unresolved: skin_bw_adept_black_and_gold)_ | skin | bw_adept | unresolved |
| `skin_bw_adept_brown_and_yellow` | _(unresolved: skin_bw_adept_brown_and_yellow)_ | skin | bw_adept | unresolved |
| `skin_bw_adept_helmgart` | _(unresolved: skin_bw_adept_helmgart)_ | skin | bw_adept | unresolved |
| `skin_bw_adept_ostermark` | _(unresolved: skin_bw_adept_ostermark)_ | skin | bw_adept | unresolved |
| `skin_bw_adept_ostland` | _(unresolved: skin_bw_adept_redemption)_ | skin | bw_adept | unresolved |
| `skin_bw_adept_white` | _(unresolved: skin_bw_adept_white)_ | skin | bw_adept | unresolved |
| `skin_bw_default` | _(unresolved: skin_bw_default)_ | skin | bw_adept | unresolved |
| `skin_bw_myrmidia` | _(unresolved: skin_bw_myrmidia)_ | skin | bw_scholar | unresolved |
| `skin_bw_necromancer` | _(unresolved: skin_bw_necromancer)_ _(dlc:shovel)_ | skin | bw_necromancer | unresolved |
| `skin_bw_necromancer_0001` | _(unresolved: skin_bw_necromancer_0001)_ _(dlc:shovel_upgrade)_ | skin | bw_necromancer | unresolved |
| `skin_bw_necromancer_0001_a` | _(unresolved: skin_bw_necromancer_0001_a)_ _(dlc:shovel_upgrade)_ | skin | bw_necromancer | unresolved |
| `skin_bw_necromancer_0002` | _(unresolved: skin_bw_necromancer_0002)_ _(dlc:shovel_upgrade)_ | skin | bw_necromancer | unresolved |
| `skin_bw_necromancer_white` | _(unresolved: skin_bw_necromancer_white)_ _(dlc:shovel)_ | skin | bw_necromancer | unresolved |
| `skin_bw_scholar` | _(unresolved: skin_bw_scholar)_ | skin | bw_scholar | unresolved |
| `skin_bw_scholar_1001` | _(unresolved: display_name_skin_bw_scholar_1001)_ | skin | bw_scholar | unresolved |
| `skin_bw_scholar_1002` | _(unresolved: display_name_skin_bw_scholar_1002)_ | skin | bw_scholar | unresolved |
| `skin_bw_scholar_1003` | _(unresolved: display_name_skin_bw_scholar_1003)_ | skin | bw_scholar, bw_necromancer | unresolved |
| `skin_bw_scholar_ash` | _(unresolved: skin_bw_pyromancer_ash)_ _(dlc:bogenhafen)_ | skin | bw_scholar | unresolved |
| `skin_bw_scholar_black_and_gold` | _(unresolved: skin_bw_pyromancer_black_and_gold)_ | skin | bw_scholar | unresolved |
| `skin_bw_scholar_bronze` | _(unresolved: skin_bw_pyromancer_redemption)_ | skin | bw_scholar | unresolved |
| `skin_bw_scholar_brown_and_white` | _(unresolved: skin_bw_pyromancer_brown_and_yellow)_ | skin | bw_scholar | unresolved |
| `skin_bw_scholar_ostermark` | _(unresolved: skin_bw_pyromancer_ostermark)_ | skin | bw_scholar | unresolved |
| `skin_bw_scholar_white` | _(unresolved: skin_bw_scholar_white)_ | skin | bw_scholar | unresolved |
| `skin_bw_unchained` | _(unresolved: skin_bw_unchained)_ | skin | bw_unchained | unresolved |
| `skin_bw_unchained_1001` | _(unresolved: display_name_skin_bw_unchained_1001)_ | skin | bw_unchained | unresolved |
| `skin_bw_unchained_1002` | _(unresolved: display_name_skin_bw_unchained_1002)_ | skin | bw_unchained | unresolved |
| `skin_bw_unchained_ash` | _(unresolved: skin_bw_unchained_ash)_ _(dlc:bogenhafen)_ | skin | bw_unchained | unresolved |
| `skin_bw_unchained_black_and_gold` | _(unresolved: skin_bw_unchained_black_and_gold)_ | skin | bw_unchained | unresolved |
| `skin_bw_unchained_bronze` | _(unresolved: skin_bw_unchained_redemption)_ | skin | bw_unchained | unresolved |
| `skin_bw_unchained_brown_and_white` | _(unresolved: skin_bw_unchained_brown_and_yellow)_ | skin | bw_unchained | unresolved |
| `skin_bw_unchained_ostermark` | _(unresolved: skin_bw_unchained_ostermark)_ | skin | bw_unchained | unresolved |
| `skin_bw_unchained_white` | _(unresolved: skin_bw_unchained_white)_ | skin | bw_unchained | unresolved |
| `skin_dr_default` | _(unresolved: skin_dr_ranger)_ | skin | dr_ranger | unresolved |
| `skin_dr_engineer` | _(unresolved: display_name_skin_dr_engineer_default)_ _(dlc:cog)_ | skin | dr_engineer | unresolved |
| `skin_dr_engineer_1001` | _(unresolved: display_name_skin_dr_engineer_1001)_ _(dlc:cog)_ | skin | dr_engineer | unresolved |
| `skin_dr_engineer_black_and_gold` | _(unresolved: display_name_dr_engineer_black_and_gold)_ _(dlc:cog)_ | skin | dr_engineer | unresolved |
| `skin_dr_engineer_blue_and_gold` | _(unresolved: display_name_dr_engineer_blue_and_gold)_ _(dlc:cog)_ | skin | dr_engineer | unresolved |
| `skin_dr_engineer_brown_and_iron` | _(unresolved: display_name_dr_engineer_brown_and_iron)_ _(dlc:cog)_ | skin | dr_engineer | unresolved |
| `skin_dr_engineer_purple_and_copper` | _(unresolved: display_name_dr_engineer_purple_and_copper)_ _(dlc:cog)_ | skin | dr_engineer | unresolved |
| `skin_dr_engineer_white` | _(unresolved: skin_dr_engineer_white)_ | skin | dr_engineer | unresolved |
| `skin_dr_ironbreaker` | _(unresolved: skin_dr_ironbreaker)_ | skin | dr_ironbreaker | unresolved |
| `skin_dr_ironbreaker_1001` | _(unresolved: display_name_skin_dr_ironbreaker_1001)_ | skin | dr_ironbreaker | unresolved |
| `skin_dr_ironbreaker_black_and_gold` | _(unresolved: skin_dr_ironbreaker_black_and_gold)_ | skin | dr_ironbreaker | unresolved |
| `skin_dr_ironbreaker_blue` | _(unresolved: skin_dr_ironbreaker_barak_varr)_ _(dlc:bogenhafen)_ | skin | dr_ironbreaker | unresolved |
| `skin_dr_ironbreaker_crimson` | _(unresolved: skin_dr_ironbreaker_karak_norn)_ | skin | dr_ironbreaker | unresolved |
| `skin_dr_ironbreaker_green` | _(unresolved: skin_dr_ironbreaker_brown_and_yellow)_ | skin | dr_ironbreaker | unresolved |
| `skin_dr_ironbreaker_iron` | _(unresolved: skin_dr_ironbreaker_zhufbar)_ | skin | dr_ironbreaker | unresolved |
| `skin_dr_ironbreaker_white` | _(unresolved: skin_dr_ironbreaker_white)_ | skin | dr_ironbreaker | unresolved |
| `skin_dr_irondrake` | _(unresolved: skin_dr_irondrake)_ | skin | dr_ironbreaker | unresolved |
| `skin_dr_ranger` | _(unresolved: skin_dr_ranger_upgraded)_ | skin | dr_ranger | unresolved |
| `skin_dr_ranger_1001` | _(unresolved: display_name_skin_dr_ranger_1001)_ | skin | dr_ranger | unresolved |
| `skin_dr_ranger_1002` | _(unresolved: display_name_skin_dr_ranger_1002)_ | skin | dr_ranger | unresolved |
| `skin_dr_ranger_barak_varr` | _(unresolved: skin_dr_ranger_barak_varr)_ _(dlc:bogenhafen)_ | skin | dr_ranger | unresolved |
| `skin_dr_ranger_black_and_gold` | _(unresolved: skin_dr_ranger_black_and_gold)_ | skin | dr_ranger | unresolved |
| `skin_dr_ranger_brown_and_yellow` | _(unresolved: skin_dr_ranger_brown_and_yellow)_ | skin | dr_ranger | unresolved |
| `skin_dr_ranger_helmgart` | _(unresolved: skin_dr_ranger_helmgart)_ | skin | dr_ranger | unresolved |
| `skin_dr_ranger_karak_norn` | _(unresolved: skin_dr_ranger_karak_norn)_ | skin | dr_ranger | unresolved |
| `skin_dr_ranger_white` | _(unresolved: skin_dr_ranger_white)_ | skin | dr_ranger | unresolved |
| `skin_dr_ranger_zhufbar` | _(unresolved: skin_dr_ranger_zhufbar)_ | skin | dr_ranger | unresolved |
| `skin_dr_slayer` | _(unresolved: skin_dr_slayer)_ | skin | dr_slayer | unresolved |
| `skin_dr_slayer_1001` | _(unresolved: display_name_skin_dr_slayer_1001)_ | skin | dr_slayer | unresolved |
| `skin_dr_slayer_1002` | _(unresolved: display_name_skin_dr_slayer_1002)_ | skin | dr_slayer | unresolved |
| `skin_dr_slayer_1003` | _(unresolved: display_name_skin_dr_slayer_1003)_ | skin | dr_slayer | unresolved |
| `skin_dr_slayer_axe` | _(unresolved: skin_dr_slayer_quickslayer)_ | skin | dr_slayer | unresolved |
| `skin_dr_slayer_dragon` | _(unresolved: skin_dr_slayer_dragonslayer)_ | skin | dr_slayer | unresolved |
| `skin_dr_slayer_runes` | _(unresolved: skin_dr_slayer_oldslayer)_ | skin | dr_slayer | unresolved |
| `skin_dr_slayer_skaven` | _(unresolved: skin_dr_slayer_skavenslayer)_ | skin | dr_slayer | unresolved |
| `skin_dr_slayer_skull` | _(unresolved: skin_dr_slayer_skullslayer)_ | skin | dr_slayer | unresolved |
| `skin_dr_slayer_white` | _(unresolved: skin_dr_slayer_white)_ | skin | dr_slayer | unresolved |
| `skin_dr_slayer_wing` | _(unresolved: skin_dr_slayer_ravenslayer)_ _(dlc:bogenhafen)_ | skin | dr_slayer | unresolved |
| `skin_es_default` | _(unresolved: skin_es_default)_ | skin | es_mercenary | unresolved |
| `skin_es_huntsman` | _(unresolved: skin_es_huntsman)_ | skin | es_huntsman | unresolved |
| `skin_es_huntsman_1001` | _(unresolved: display_name_skin_huntsman_1001)_ | skin | es_huntsman | unresolved |
| `skin_es_huntsman_black_and_gold` | _(unresolved: skin_es_huntsman_nuln)_ | skin | es_huntsman | unresolved |
| `skin_es_huntsman_middenland` | _(unresolved: skin_es_huntsman_middenland)_ _(dlc:bogenhafen)_ | skin | es_huntsman | unresolved |
| `skin_es_huntsman_ostermark` | _(unresolved: skin_es_huntsman_ostermark)_ | skin | es_huntsman | unresolved |
| `skin_es_huntsman_red_and_white` | _(unresolved: skin_es_huntsman_talabecland)_ | skin | es_huntsman | unresolved |
| `skin_es_huntsman_white` | _(unresolved: skin_es_huntsman_white)_ | skin | es_huntsman | unresolved |
| `skin_es_huntsman_yellow_and_green` | _(unresolved: skin_es_huntsman_green)_ | skin | es_huntsman | unresolved |
| `skin_es_knight` | _(unresolved: skin_es_knight)_ | skin | es_knight | unresolved |
| `skin_es_knight_1001` | _(unresolved: display_name_skin_es_knight_1001)_ | skin | es_knight | unresolved |
| `skin_es_knight_1002` | _(unresolved: display_name_skin_es_knight_1002)_ | skin | es_knight | unresolved |
| `skin_es_knight_black_and_gold` | _(unresolved: skin_es_knight_blazing_sun)_ | skin | es_knight | unresolved |
| `skin_es_knight_bronze` | _(unresolved: skin_es_knight_brass_keep)_ | skin | es_knight | unresolved |
| `skin_es_knight_green` | _(unresolved: skin_es_knight_hermit)_ | skin | es_knight | unresolved |
| `skin_es_knight_middenland` | _(unresolved: skin_es_knight_wolf_knight)_ _(dlc:bogenhafen)_ | skin | es_knight | unresolved |
| `skin_es_knight_red` | _(unresolved: skin_es_knight_encarmine)_ | skin | es_knight | unresolved |
| `skin_es_knight_white` | _(unresolved: skin_es_knight_white)_ | skin | es_knight | unresolved |
| `skin_es_longshark` | _(unresolved: skin_es_longshark)_ | skin | es_huntsman | unresolved |
| `skin_es_mercenary` | _(unresolved: skin_es_mercenary)_ | skin | es_mercenary | unresolved |
| `skin_es_mercenary_1001` | _(unresolved: display_name_skin_es_mercenary_1001)_ | skin | es_mercenary | unresolved |
| `skin_es_mercenary_1002` | _(unresolved: display_name_skin_es_mercenary_1002)_ | skin | es_mercenary | unresolved |
| `skin_es_mercenary_1003` | _(unresolved: display_name_skin_es_mercenary_1003)_ | skin | es_mercenary | unresolved |
| `skin_es_mercenary_black_and_gold` | _(unresolved: skin_es_mercenary_black_and_gold)_ | skin | es_mercenary | unresolved |
| `skin_es_mercenary_carroburg` | _(unresolved: skin_es_mercenary_carroburg)_ | skin | es_mercenary | unresolved |
| `skin_es_mercenary_helmgart` | _(unresolved: skin_es_mercenary_helmgart)_ | skin | es_mercenary | unresolved |
| `skin_es_mercenary_middenland` | _(unresolved: skin_es_mercenary_middenland)_ _(dlc:bogenhafen)_ | skin | es_mercenary | unresolved |
| `skin_es_mercenary_ostermark` | _(unresolved: skin_es_mercenary_ostermark)_ | skin | es_mercenary | unresolved |
| `skin_es_mercenary_ostland` | _(unresolved: skin_es_mercenary_talabecland)_ | skin | es_mercenary | unresolved |
| `skin_es_mercenary_white` | _(unresolved: skin_es_mercenary_white)_ | skin | es_mercenary | unresolved |
| `skin_es_questingknight` | _(unresolved: display_name_skin_es_questing_knight_default)_ _(dlc:lake_upgrade)_ | skin | es_questingknight | unresolved |
| `skin_es_questingknight_1001` | _(unresolved: display_name_skin_es_questing_knight_1001)_ _(dlc:lake)_ | skin | es_questingknight | unresolved |
| `skin_es_questingknight_black_and_gold` | _(unresolved: display_name_es_questingknight_black_and_gold)_ _(dlc:lake_upgrade)_ | skin | es_questingknight | unresolved |
| `skin_es_questingknight_black_and_yellow` | _(unresolved: display_name_es_questingknight_black_and_yellow)_ _(dlc:lake_upgrade)_ | skin | es_questingknight | unresolved |
| `skin_es_questingknight_blue_and_white` | _(unresolved: display_name_skin_es_questing_knight_blue_and_white)_ _(dlc:lake)_ | skin | es_questingknight | unresolved |
| `skin_es_questingknight_white` | _(unresolved: skin_es_questingknight_white)_ | skin | es_questingknight | unresolved |
| `skin_es_questingknight_yellow_and_white` | _(unresolved: display_name_skin_es_questing_knight_yellow_and_white)_ _(dlc:lake_upgrade)_ | skin | es_questingknight | unresolved |
| `skin_wh_bountyhunter` | _(unresolved: skin_wh_bountyhunter)_ | skin | wh_bountyhunter | unresolved |
| `skin_wh_bountyhunter_1001` | _(unresolved: display_name_skin_wh_bountyhunter_1001)_ | skin | wh_bountyhunter | unresolved |
| `skin_wh_bountyhunter_1002` | _(unresolved: display_name_skin_wh_bountyhunter_1002)_ | skin | wh_bountyhunter | unresolved |
| `skin_wh_bountyhunter_1003` | _(unresolved: display_name_skin_wh_bountyhunter_1003)_ | skin | wh_bountyhunter | unresolved |
| `skin_wh_bountyhunter_black_and_gold` | _(unresolved: skin_wh_bounty_hunter_black_and_gold)_ | skin | wh_bountyhunter | unresolved |
| `skin_wh_bountyhunter_brown_and_white` | _(unresolved: skin_wh_bounty_hunter_ostermark)_ | skin | wh_bountyhunter | unresolved |
| `skin_wh_bountyhunter_green_and_yellow` | _(unresolved: skin_wh_bounty_hunter_grey_and_yellow)_ | skin | wh_bountyhunter | unresolved |
| `skin_wh_bountyhunter_middenland` | _(unresolved: skin_wh_bounty_hunter_middenland)_ _(dlc:bogenhafen)_ | skin | wh_bountyhunter | unresolved |
| `skin_wh_bountyhunter_white` | _(unresolved: skin_wh_bountyhunter_white)_ | skin | wh_bountyhunter | unresolved |
| `skin_wh_bountyhunter_yellow_and_red` | _(unresolved: skin_wh_bounty_hunter_executioner)_ | skin | wh_bountyhunter | unresolved |
| `skin_wh_captain` | _(unresolved: skin_wh_captain)_ | skin | wh_captain | unresolved |
| `skin_wh_captain_1001` | _(unresolved: display_name_skin_wh_captain_1001)_ | skin | wh_captain | unresolved |
| `skin_wh_captain_1002` | _(unresolved: display_name_skin_wh_captain_1002)_ | skin | wh_captain | unresolved |
| `skin_wh_captain_black_and_gold` | _(unresolved: skin_wh_captain_black_and_gold)_ | skin | wh_captain | unresolved |
| `skin_wh_captain_grey_and_yellow` | _(unresolved: skin_wh_captain_grey_and_yellow)_ | skin | wh_captain | unresolved |
| `skin_wh_captain_helmgart` | _(unresolved: skin_wh_captain_helmgart)_ | skin | wh_captain | unresolved |
| `skin_wh_captain_middenland` | _(unresolved: skin_wh_captain_middenland)_ _(dlc:bogenhafen)_ | skin | wh_captain | unresolved |
| `skin_wh_captain_ostermark` | _(unresolved: skin_wh_captain_ostermark)_ | skin | wh_captain | unresolved |
| `skin_wh_captain_ostland` | _(unresolved: skin_wh_captain_executioner)_ | skin | wh_captain | unresolved |
| `skin_wh_captain_white` | _(unresolved: skin_wh_captain_white)_ | skin | wh_captain | unresolved |
| `skin_wh_default` | _(unresolved: skin_wh_default)_ | skin | wh_captain | unresolved |
| `skin_wh_flagellant` | _(unresolved: skin_wh_flagellant)_ | skin | wh_zealot | unresolved |
| `skin_wh_priest` | _(unresolved: skin_wh_priest)_ _(dlc:bless)_ | skin | wh_priest | unresolved |
| `skin_wh_priest_0002` | _(unresolved: skin_wh_priest_0002)_ _(dlc:bless)_ | skin | wh_priest | unresolved |
| `skin_wh_priest_0002_a` | _(unresolved: skin_wh_priest_0002_a)_ _(dlc:bless)_ | skin | wh_priest | unresolved |
| `skin_wh_priest_1001` | _(unresolved: display_name_skin_wh_priest_1001_2023_q1)_ _(dlc:bless)_ | skin | wh_priest | unresolved |
| `skin_wh_priest_white` | _(unresolved: skin_wh_priest_white)_ _(dlc:bless)_ | skin | wh_priest | unresolved |
| `skin_wh_zealot` | _(unresolved: skin_wh_zealot)_ | skin | wh_zealot | unresolved |
| `skin_wh_zealot_1001` | _(unresolved: display_name_skin_wh_zealot_1001)_ | skin | wh_zealot | unresolved |
| `skin_wh_zealot_black_and_gold` | _(unresolved: skin_wh_zealot_black_and_gold)_ | skin | wh_zealot | unresolved |
| `skin_wh_zealot_crimson` | _(unresolved: skin_wh_zealot_executioner)_ | skin | wh_zealot | unresolved |
| `skin_wh_zealot_green_and_yellow` | _(unresolved: skin_wh_zealot_grey_and_yellow)_ | skin | wh_zealot | unresolved |
| `skin_wh_zealot_middenland` | _(unresolved: skin_wh_zealot_middenland)_ _(dlc:bogenhafen)_ | skin | wh_zealot | unresolved |
| `skin_wh_zealot_pure` | _(unresolved: skin_wh_zealot_ostermark)_ | skin | wh_zealot | unresolved |
| `skin_wh_zealot_white` | _(unresolved: skin_wh_zealot_white)_ | skin | wh_zealot | unresolved |
| `skin_ww_default` | _(unresolved: skin_ww_default)_ | skin | we_waywatcher | unresolved |
| `skin_ww_maidenguard` | _(unresolved: skin_ww_handmaiden)_ | skin | we_maidenguard | unresolved |
| `skin_ww_maidenguard_1001` | _(unresolved: display_name_skin_ww_maidenguard_1001)_ | skin | we_maidenguard | unresolved |
| `skin_ww_maidenguard_1002` | _(unresolved: display_name_skin_ww_maidenguard_1002)_ | skin | we_maidenguard | unresolved |
| `skin_ww_maidenguard_black_and_gold` | _(unresolved: skin_ww_handmaiden_black_and_gold)_ | skin | we_maidenguard | unresolved |
| `skin_ww_maidenguard_caledor` | _(unresolved: skin_ww_handmaiden_tirsyth)_ | skin | we_maidenguard | unresolved |
| `skin_ww_maidenguard_elyrion` | _(unresolved: skin_ww_handmaiden_frostmaiden)_ _(dlc:bogenhafen)_ | skin | we_maidenguard | unresolved |
| `skin_ww_maidenguard_red_and_yellow` | _(unresolved: skin_ww_handmaiden_spirit)_ | skin | we_maidenguard | unresolved |
| `skin_ww_maidenguard_white` | _(unresolved: skin_ww_maidenguard_white)_ | skin | we_maidenguard | unresolved |
| `skin_ww_maidenguard_white_and_gold` | _(unresolved: skin_ww_handmaiden_anmyr)_ | skin | we_maidenguard | unresolved |
| `skin_ww_moonmantle` | _(unresolved: skin_ww_moonmantle)_ | skin | we_maidenguard | unresolved |
| `skin_ww_shade` | _(unresolved: skin_ww_shade)_ | skin | we_shade | unresolved |
| `skin_ww_shade_1001` | _(unresolved: display_name_skin_ww_shade_1001)_ | skin | we_shade | unresolved |
| `skin_ww_shade_1002` | _(unresolved: display_name_skin_ww_shade_1002)_ | skin | we_shade | unresolved |
| `skin_ww_shade_ash` | _(unresolved: skin_ww_shade_ash)_ | skin | we_shade | unresolved |
| `skin_ww_shade_black_and_gold` | _(unresolved: skin_ww_shade_black_and_gold)_ | skin | we_shade | unresolved |
| `skin_ww_shade_crimson` | _(unresolved: skin_ww_shade_crimson)_ | skin | we_shade | unresolved |
| `skin_ww_shade_emerald` | _(unresolved: skin_ww_shade_emerald)_ | skin | we_shade | unresolved |
| `skin_ww_shade_midnight` | _(unresolved: skin_ww_shade_midnight)_ _(dlc:bogenhafen)_ | skin | we_shade | unresolved |
| `skin_ww_shade_white` | _(unresolved: skin_ww_shade_white)_ | skin | we_shade | unresolved |
| `skin_ww_thornsister` | _(unresolved: skin_we_thornsister)_ _(dlc:woods)_ | skin | we_thornsister | unresolved |
| `skin_ww_thornsister_1001` | _(unresolved: display_name_skin_ww_thornsister_1001)_ | skin | we_thornsister, we_shade, we_maidenguard, we_waywatcher | unresolved |
| `skin_ww_thornsister_black_and_gold` | _(unresolved: display_name_skin_ww_thornsister_black_and_gold)_ _(dlc:woods)_ | skin | we_thornsister | unresolved |
| `skin_ww_thornsister_blue` | _(unresolved: display_name_skin_ww_thornsister_blue)_ _(dlc:woods)_ | skin | we_thornsister | unresolved |
| `skin_ww_thornsister_green` | _(unresolved: display_name_skin_ww_thornsister_green)_ _(dlc:woods)_ | skin | we_thornsister | unresolved |
| `skin_ww_thornsister_redblack` | _(unresolved: display_name_skin_ww_thornsister_redblack)_ _(dlc:woods)_ | skin | we_thornsister | unresolved |
| `skin_ww_thornsister_white` | _(unresolved: skin_ww_thornsister_white)_ | skin | we_thornsister | unresolved |
| `skin_ww_waywatcher` | _(unresolved: skin_ww_waywatcher)_ | skin | we_waywatcher | unresolved |
| `skin_ww_waywatcher_1001` | _(unresolved: display_name_skin_ww_waywatcher_1001)_ | skin | we_waywatcher | unresolved |
| `skin_ww_waywatcher_1002` | _(unresolved: display_name_skin_ww_waywatcher_1002)_ | skin | we_waywatcher | unresolved |
| `skin_ww_waywatcher_anmyr` | _(unresolved: skin_ww_waywatcher_anmyr)_ | skin | we_waywatcher | unresolved |
| `skin_ww_waywatcher_atylwyth` | _(unresolved: skin_ww_waywatcher_atylwyth)_ _(dlc:bogenhafen)_ | skin | we_waywatcher | unresolved |
| `skin_ww_waywatcher_black_and_gold` | _(unresolved: skin_ww_waywatcher_black_and_gold)_ | skin | we_waywatcher | unresolved |
| `skin_ww_waywatcher_cythral` | _(unresolved: skin_ww_waywatcher_cythral)_ | skin | we_waywatcher | unresolved |
| `skin_ww_waywatcher_helmgart` | _(unresolved: skin_ww_waywatcher_helmgart)_ | skin | we_waywatcher | unresolved |
| `skin_ww_waywatcher_tirsyth` | _(unresolved: skin_ww_waywatcher_tirsyth)_ | skin | we_waywatcher | unresolved |
| `skin_ww_waywatcher_white` | _(unresolved: skin_ww_waywatcher_white)_ | skin | we_waywatcher | unresolved |

### kind: slot_packmaster_claw (2 entries, 2 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `packmaster_claw` | _(unresolved: )_ | inventory_item |  | unresolved |
| `packmaster_claw_combo` | _(unresolved: )_ | inventory_item |  | unresolved |

### kind: trinket (32 entries, 32 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `necklace` | _(unresolved: display_name_necklace_09)_ | necklace |  | unresolved |
| `necklace_02` | _(unresolved: display_name_necklace_02)_ | necklace |  | unresolved |
| `necklace_03` | _(unresolved: display_name_necklace_03)_ | necklace |  | unresolved |
| `necklace_04` | _(unresolved: display_name_necklace_04)_ | necklace |  | unresolved |
| `necklace_05` | _(unresolved: display_name_necklace_05)_ | necklace |  | unresolved |
| `necklace_06` | _(unresolved: display_name_necklace_06)_ | necklace |  | unresolved |
| `necklace_07` | _(unresolved: display_name_necklace_07)_ | necklace |  | unresolved |
| `necklace_08` | _(unresolved: display_name_necklace_08)_ | necklace |  | unresolved |
| `necklace_09` | _(unresolved: display_name_necklace_01)_ | necklace |  | unresolved |
| `necklace_10` | _(unresolved: display_name_necklace_10)_ | necklace |  | unresolved |
| `ring` | _(unresolved: display_name_ring_09)_ | ring |  | unresolved |
| `ring_02` | _(unresolved: display_name_ring_02)_ | ring |  | unresolved |
| `ring_03` | _(unresolved: display_name_ring_03)_ | ring |  | unresolved |
| `ring_04` | _(unresolved: display_name_ring_04)_ | ring |  | unresolved |
| `ring_05` | _(unresolved: display_name_ring_05)_ | ring |  | unresolved |
| `ring_06` | _(unresolved: display_name_ring_06)_ | ring |  | unresolved |
| `ring_07` | _(unresolved: display_name_ring_07)_ | ring |  | unresolved |
| `ring_08` | _(unresolved: display_name_ring_08)_ | ring |  | unresolved |
| `ring_09` | _(unresolved: display_name_ring_01)_ | ring |  | unresolved |
| `ring_10` | _(unresolved: display_name_ring_10)_ | ring |  | unresolved |
| `trinket` | _(unresolved: display_name_trinket_12)_ | trinket |  | unresolved |
| `trinket_02` | _(unresolved: display_name_trinket_02)_ | trinket |  | unresolved |
| `trinket_03` | _(unresolved: display_name_trinket_03)_ | trinket |  | unresolved |
| `trinket_04` | _(unresolved: display_name_trinket_04)_ | trinket |  | unresolved |
| `trinket_05` | _(unresolved: display_name_trinket_05)_ | trinket |  | unresolved |
| `trinket_06` | _(unresolved: display_name_trinket_06)_ | trinket |  | unresolved |
| `trinket_07` | _(unresolved: display_name_trinket_07)_ | trinket |  | unresolved |
| `trinket_08` | _(unresolved: display_name_trinket_08)_ | trinket |  | unresolved |
| `trinket_09` | _(unresolved: display_name_trinket_09)_ | trinket |  | unresolved |
| `trinket_10` | _(unresolved: display_name_trinket_10)_ | trinket |  | unresolved |
| `trinket_11` | _(unresolved: display_name_trinket_11)_ | trinket |  | unresolved |
| `trinket_12` | _(unresolved: display_name_trinket_01)_ | trinket |  | unresolved |

### kind: weapon (263 entries, 263 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `bardin_engineer_career_skill_weapon_preview` | _(unresolved: dr_steam_pistol_skin_01_name)_ _(dlc:cog)_ | dr_steam_pistol |  | unresolved |
| `bw_1h_crowbill` | _(unresolved: bw_1h_crowbill_skin_01_name)_ _(dlc:holly)_ | bw_1h_crowbill | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_crowbill_magic_01` | _(unresolved: bw_1h_crowbill_skin_01_magic_01_name)_ | bw_1h_crowbill | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flail_flaming` | _(unresolved: bw_1h_flail_flaming_skin_01_name)_ _(dlc:scorpion)_ | bw_1h_flail_flaming | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flail_flaming_magic_01` | _(unresolved: bw_1h_flail_flaming_skin_02_magic_01_name)_ | bw_1h_flail_flaming | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace` | _(unresolved: bw_1h_mace_skin_01_name)_ | bw_morningstar | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_magic_01` | _(unresolved: bw_1h_mace_skin_02_magic_01_name)_ | bw_morningstar | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger` | _(unresolved: bw_dagger_skin_01_name)_ | bw_1h_dagger | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_magic_01` | _(unresolved: bw_dagger_skin_02_magic_01_name)_ | bw_1h_dagger | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flame_sword` | _(unresolved: bw_1h_flaming_sword_skin_01_name)_ | bw_flame_sword | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flame_sword_magic_01` | _(unresolved: bw_1h_flaming_sword_skin_06_magic_01_name)_ | bw_flame_sword | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_ghost_scythe` | _(unresolved: bw_ghost_scythe_skin_01_name)_ _(dlc:shovel)_ | bw_ghost_scythe | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_ghost_scythe_magic_01` | _(unresolved: bw_ghost_scythe_skin_02_magic_01_name)_ _(dlc:shovel)_ | bw_ghost_scythe | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_necromancy_staff` | _(unresolved: bw_necromancy_staff_skin_01_name)_ _(dlc:shovel)_ | bw_necromancy_staff | bw_necromancer | unresolved |
| `bw_necromancy_staff_magic_01` | _(unresolved: bw_necromancy_staff_skin_02_magic_01_name)_ _(dlc:shovel)_ | bw_necromancy_staff | bw_necromancer | unresolved |
| `bw_skullstaff_beam` | _(unresolved: bw_beam_staff_skin_01_name)_ | bw_staff_beam | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_beam_magic_01` | _(unresolved: bw_beam_staff_skin_02_magic_01_name)_ | bw_staff_beam | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_fireball` | _(unresolved: bw_fireball_staff_skin_01_name)_ | bw_staff_firball | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_fireball_magic_01` | _(unresolved: bw_fireball_staff_skin_02_magic_01_name)_ | bw_staff_firball | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_flamethrower` | _(unresolved: bw_flamethrower_staff_skin_01_name)_ | bw_staff_flamethrower | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_flamethrower_magic_01` | _(unresolved: bw_flamethrower_staff_skin_04_magic_01_name)_ | bw_staff_flamethrower | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_geiser` | _(unresolved: bw_conflagration_staff_skin_01_name)_ | bw_staff_geiser | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_geiser_magic_01` | _(unresolved: bw_conflagration_staff_skin_01_magic_01_name)_ | bw_staff_geiser | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_spear` | _(unresolved: bw_spear_staff_skin_01_name)_ | bw_staff_spear | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_spear_magic_01` | _(unresolved: bw_spear_staff_skin_05_magic_01_name)_ | bw_staff_spear | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_sword` | _(unresolved: bw_1h_sword_skin_01_name)_ | bw_1h_sword | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_sword_magic_01` | _(unresolved: bw_1h_sword_skin_06_magic_01_name)_ | bw_1h_sword | bw_scholar, bw_adept, bw_unchained | unresolved |
| `dr_1h_axe` | _(unresolved: dw_1h_axe_skin_01_name)_ | dr_1h_axes | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_1h_axe_magic_01` | _(unresolved: dw_1h_axe_skin_04_magic_01_name)_ | dr_1h_axes | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_1h_hammer` | _(unresolved: dw_1h_hammer_skin_01_name)_ | dr_1h_hammer | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_1h_hammer_magic_01` | _(unresolved: dw_1h_hammer_skin_03_magic_01_name)_ | dr_1h_hammer | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes` | _(unresolved: dr_1h_throwing_axes_skin_01_name)_ _(dlc:scorpion)_ | dr_1h_throwing_axes | dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_magic_01` | _(unresolved: dr_1h_throwing_axes_skin_02_magic_01_name)_ | dr_1h_throwing_axes | dr_slayer, dr_ranger | unresolved |
| `dr_2h_axe` | _(unresolved: dw_2h_axe_skin_01_name)_ | dr_2h_axes | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_2h_axe_magic_01` | _(unresolved: dw_2h_axe_skin_02_magic_01_name)_ | dr_2h_axes | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_2h_cog_hammer` | _(unresolved: dr_cog_hammer_skin_01_name)_ _(dlc:cog)_ | dr_cog_hammer | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_magic_01` | _(unresolved: dr_cog_hammer_skin_02_magic_01_name)_ _(dlc:cog)_ | dr_cog_hammer | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_hammer` | _(unresolved: dw_2h_hammer_skin_01_name)_ | dr_2h_hammer | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_2h_hammer_magic_01` | _(unresolved: dw_2h_hammer_skin_03_magic_01_name)_ | dr_2h_hammer | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_2h_pick` | _(unresolved: dw_2h_pick_skin_01_name)_ | dr_2h_picks | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_2h_pick_magic_01` | _(unresolved: dw_2h_pick_skin_02_magic_01_name)_ | dr_2h_picks | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_crossbow` | _(unresolved: dw_crossbow_skin_01_name)_ | dr_crossbow | dr_ironbreaker, dr_ranger | unresolved |
| `dr_crossbow_magic_01` | _(unresolved: dw_crossbow_skin_03_magic_01_name)_ | dr_crossbow | dr_ironbreaker, dr_ranger | unresolved |
| `dr_drake_pistol` | _(unresolved: dw_drake_pistol_skin_01_name)_ | dr_drakefire_pistols | dr_ironbreaker | unresolved |
| `dr_drake_pistol_magic_01` | _(unresolved: dw_drake_pistol_skin_01_magic_01_name)_ | dr_drakefire_pistols | dr_ironbreaker | unresolved |
| `dr_drakegun` | _(unresolved: dw_drakegun_skin_02_name)_ | dr_drakegun | dr_ironbreaker | unresolved |
| `dr_drakegun_magic_01` | _(unresolved: dw_drakegun_skin_02_magic_01_name)_ | dr_drakegun | dr_ironbreaker | unresolved |
| `dr_dual_wield_axes` | _(unresolved: dw_dual_axe_skin_01_name)_ | dr_dual_axes | dr_slayer | unresolved |
| `dr_dual_wield_axes_magic_01` | _(unresolved: dw_dual_axe_skin_04_magic_01_name)_ | dr_dual_axes | dr_slayer | unresolved |
| `dr_dual_wield_hammers` | _(unresolved: dr_dual_wield_hammers_skin_01_name)_ _(dlc:holly)_ | dr_dual_wield_hammers | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_dual_wield_hammers_magic_01` | _(unresolved: dr_dual_wield_hammers_skin_01_magic_01_name)_ | dr_dual_wield_hammers | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_hammer_pistol_preview` | _(unresolved: dr_steam_pistol_skin_01_name)_ _(dlc:cog)_ | dr_steam_pistol |  | unresolved |
| `dr_handgun` | _(unresolved: dw_handgun_skin_01_name)_ | dr_handgun | dr_ironbreaker, dr_ranger | unresolved |
| `dr_handgun_magic_01` | _(unresolved: dw_handgun_skin_03_magic_01_name)_ | dr_handgun | dr_ironbreaker, dr_ranger | unresolved |
| `dr_rakegun` | _(unresolved: dw_grudge_raker_skin_01_name)_ | dr_grudgeraker | dr_ironbreaker, dr_ranger | unresolved |
| `dr_rakegun_magic_01` | _(unresolved: dw_grudge_raker_skin_03_magic_01_name)_ | dr_grudgeraker | dr_ironbreaker, dr_ranger | unresolved |
| `dr_shield_axe` | _(unresolved: dw_1h_axe_shield_skin_01_name)_ | dr_1h_axe_shield | dr_ironbreaker, dr_ranger | unresolved |
| `dr_shield_axe_magic_01` | _(unresolved: dw_1h_axe_shield_skin_04_magic_01_name)_ | dr_1h_axe_shield | dr_ironbreaker, dr_ranger | unresolved |
| `dr_shield_hammer` | _(unresolved: dw_1h_hammer_shield_skin_01_name)_ | dr_1h_hammer_shield | dr_ironbreaker, dr_ranger | unresolved |
| `dr_shield_hammer_magic_01` | _(unresolved: dw_1h_hammer_shield_skin_04_magic_01_name)_ | dr_1h_hammer_shield | dr_ironbreaker, dr_ranger | unresolved |
| `dr_steam_pistol` | _(unresolved: dr_steam_pistol_skin_01_name)_ _(dlc:cog)_ | dr_steam_pistol | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_magic_01` | _(unresolved: dr_steam_pistol_skin_01_magic_01_name)_ _(dlc:cog)_ | dr_steam_pistol | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `es_1h_flail` | _(unresolved: es_1h_flail_skin_01_name)_ | es_flail | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_magic_01` | _(unresolved: es_1h_flail_skin_04_magic_01_name)_ | es_flail | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_mace` | _(unresolved: es_1h_mace_skin_01_name)_ | es_1h_mace | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_magic_01` | _(unresolved: es_1h_mace_skin_05_magic_01_name)_ | es_1h_mace | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword` | _(unresolved: es_1h_sword_skin_01_name)_ | es_1h_sword | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_magic_01` | _(unresolved: es_1h_sword_skin_04_magic_01_name)_ | es_1h_sword | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer` | _(unresolved: es_2h_hammer_skin_05_name)_ | es_2h_war_hammer | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_magic_01` | _(unresolved: es_2h_hammer_skin_02_magic_01_name)_ | es_2h_war_hammer | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_tutorial` | _(unresolved: display_name_plentiful_empire_soldier_es_2h_war_hammer)_ | es_2h_war_hammer | empire_soldier_tutorial | unresolved |
| `es_2h_hammer_tutorial_magic_01` | _(unresolved: display_name_plentiful_empire_soldier_es_2h_war_hammer)_ | es_2h_war_hammer | empire_soldier_tutorial | unresolved |
| `es_2h_heavy_spear` | _(unresolved: es_2h_heavy_spear_skin_01_name)_ _(dlc:scorpion)_ | es_2h_heavy_spear | es_huntsman, es_mercenary | unresolved |
| `es_2h_heavy_spear_magic_01` | _(unresolved: es_2h_heavy_spear_skin_02_magic_01_name)_ | es_2h_heavy_spear | es_huntsman, es_mercenary | unresolved |
| `es_2h_sword` | _(unresolved: es_2h_sword_skin_01_name)_ | es_2h_sword | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_executioner` | _(unresolved: es_2h_sword_exe_skin_01_name)_ | es_2h_sword_executioner | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_executioner_magic_01` | _(unresolved: es_2h_sword_exe_skin_03_magic_01_name)_ | es_2h_sword_executioner | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_magic_01` | _(unresolved: es_2h_sword_skin_03_magic_01_name)_ | es_2h_sword | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_bastard_sword` | _(unresolved: es_bastard_sword_skin_01_name)_ _(dlc:lake)_ | es_bastard_sword | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_magic_01` | _(unresolved: es_bastard_sword_skin_05_magic_01_name)_ | es_bastard_sword | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_preview` | _(unresolved: es_bastard_sword_skin_01_name)_ | es_bastard_sword | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_blunderbuss` | _(unresolved: es_blunderbuss_skin_03_name)_ | es_blunderbuss | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_magic_01` | _(unresolved: es_blunderbuss_skin_01_magic_01_name)_ | es_blunderbuss | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_dual_wield_hammer_sword` | _(unresolved: es_dual_wield_hammer_sword_skin_01_name)_ _(dlc:holly)_ | es_dual_wield_hammer_sword | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_dual_wield_hammer_sword_magic_01` | _(unresolved: es_dual_wield_hammer_sword_skin_02_magic_01_name)_ | es_dual_wield_hammer_sword | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd` | _(unresolved: es_halberd_skin_01_name)_ | es_2h_halberd | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_magic_01` | _(unresolved: es_halberd_skin_03_magic_01_name)_ | es_2h_halberd | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun` | _(unresolved: es_handgun_skin_03_name)_ | es_handgun | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_magic_01` | _(unresolved: es_handgun_skin_02_magic_01_name)_ | es_handgun | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_longbow` | _(unresolved: es_longbow_skin_01_name)_ | ww_longbow | es_huntsman | unresolved |
| `es_longbow_magic_01` | _(unresolved: es_longbow_skin_04_magic_01_name)_ | ww_longbow | es_huntsman | unresolved |
| `es_longbow_tutorial` | _(unresolved: display_name_plentiful_empire_soldier_es_longbow)_ | ww_longbow | empire_soldier_tutorial | unresolved |
| `es_longbow_tutorial_magic_01` | _(unresolved: display_name_plentiful_empire_soldier_es_longbow)_ | ww_longbow | empire_soldier_tutorial | unresolved |
| `es_mace_shield` | _(unresolved: es_1h_mace_shield_skin_02_name)_ | es_1h_mace_shield | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_mace_shield_magic_01` | _(unresolved: es_1h_mace_shield_skin_04_magic_01_name)_ | es_1h_mace_shield | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun` | _(unresolved: es_repeating_handgun_skin_01_name)_ | es_repeating_handgun | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_magic_01` | _(unresolved: es_repeating_handgun_skin_01_magic_01_name)_ | es_repeating_handgun | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_sword_shield` | _(unresolved: es_1h_sword_shield_skin_02_name)_ | es_1h_sword_shield | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_sword_shield_breton` | _(unresolved: es_sword_shield_breton_skin_01_name)_ _(dlc:lake)_ | es_1h_sword_shield_breton | es_questingknight | unresolved |
| `es_sword_shield_breton_magic_01` | _(unresolved: es_sword_shield_breton_skin_05_magic_01_name)_ _(dlc:lake)_ | es_1h_sword_shield_breton | es_questingknight | unresolved |
| `es_sword_shield_magic_01` | _(unresolved: es_1h_sword_shield_skin_04_magic_01_name)_ | es_1h_sword_shield | es_huntsman, es_knight, es_mercenary | unresolved |
| `markus_questingknight_career_skill_weapon` | _(unresolved: )_ |  |  | unresolved |
| `markus_questingknight_career_skill_weapon_vs` | _(unresolved: )_ |  |  | unresolved |
| `vs_bw_1h_crowbill` | _(unresolved: bw_1h_crowbill_skin_01_name)_ _(dlc:holly)_ | bw_1h_crowbill | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_bw_1h_flail_flaming` | _(unresolved: bw_1h_flail_flaming_skin_01_name)_ _(dlc:scorpion)_ | bw_1h_flail_flaming | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_bw_1h_mace` | _(unresolved: bw_1h_mace_skin_01_name)_ | bw_morningstar | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_bw_dagger` | _(unresolved: bw_dagger_skin_01_name)_ | bw_1h_dagger | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_bw_deus_01` | _(unresolved: bw_deus_01_name)_ _(dlc:grass)_ | bw_deus_01 | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_bw_flame_sword` | _(unresolved: bw_1h_flaming_sword_skin_01_name)_ | bw_flame_sword | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_bw_ghost_scythe` | _(unresolved: bw_ghost_scythe_skin_01_name)_ _(dlc:shovel)_ | bw_ghost_scythe | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_bw_necromancy_staff` | _(unresolved: bw_necromancy_staff_skin_01_name)_ _(dlc:shovel)_ | bw_necromancy_staff | bw_necromancer | unresolved |
| `vs_bw_skullstaff_beam` | _(unresolved: bw_beam_staff_skin_01_name)_ | bw_staff_beam | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_bw_skullstaff_fireball` | _(unresolved: bw_fireball_staff_skin_01_name)_ | bw_staff_firball | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_bw_skullstaff_flamethrower` | _(unresolved: bw_flamethrower_staff_skin_01_name)_ | bw_staff_flamethrower | bw_scholar, bw_adept, bw_unchained | unresolved |
| `vs_bw_skullstaff_geiser` | _(unresolved: bw_conflagration_staff_skin_01_name)_ | bw_staff_geiser | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_bw_skullstaff_spear` | _(unresolved: bw_spear_staff_skin_01_name)_ | bw_staff_spear | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_bw_sword` | _(unresolved: bw_1h_sword_skin_01_name)_ | bw_1h_sword | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `vs_chaos_troll_axe` | _(unresolved: dw_1h_axe_skin_01_name)_ | dr_1h_axes | vs_chaos_troll | unresolved |
| `vs_dr_1h_axe` | _(unresolved: dw_1h_axe_skin_01_name)_ | dr_1h_axes | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `vs_dr_1h_hammer` | _(unresolved: dw_1h_hammer_skin_01_name)_ | dr_1h_hammer | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `vs_dr_1h_throwing_axes` | _(unresolved: dr_1h_throwing_axes_skin_01_name)_ _(dlc:scorpion)_ | dr_1h_throwing_axes | dr_slayer, dr_ranger | unresolved |
| `vs_dr_2h_axe` | _(unresolved: dw_2h_axe_skin_01_name)_ | dr_2h_axes | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `vs_dr_2h_cog_hammer` | _(unresolved: dr_cog_hammer_skin_01_name)_ _(dlc:cog)_ | dr_cog_hammer | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `vs_dr_2h_hammer` | _(unresolved: dw_2h_hammer_skin_01_name)_ | dr_2h_hammer | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `vs_dr_2h_pick` | _(unresolved: dw_2h_pick_skin_01_name)_ | dr_2h_picks | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `vs_dr_crossbow` | _(unresolved: dw_crossbow_skin_01_name)_ | dr_crossbow | dr_ironbreaker, dr_ranger | unresolved |
| `vs_dr_deus_01` | _(unresolved: dr_deus_01_name)_ _(dlc:grass)_ | dr_deus_01 | dr_ironbreaker, dr_engineer | unresolved |
| `vs_dr_drake_pistol` | _(unresolved: dw_drake_pistol_skin_01_name)_ | dr_drakefire_pistols | dr_ironbreaker, dr_engineer | unresolved |
| `vs_dr_drakegun` | _(unresolved: dw_drakegun_skin_02_name)_ | dr_drakegun | dr_ironbreaker, dr_engineer | unresolved |
| `vs_dr_dual_wield_axes` | _(unresolved: dw_dual_axe_skin_01_name)_ | dr_dual_axes | dr_slayer | unresolved |
| `vs_dr_dual_wield_hammers` | _(unresolved: dr_dual_wield_hammers_skin_01_name)_ _(dlc:holly)_ | dr_dual_wield_hammers | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `vs_dr_handgun` | _(unresolved: dw_handgun_skin_01_name)_ | dr_handgun | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `vs_dr_rakegun` | _(unresolved: dw_grudge_raker_skin_01_name)_ | dr_grudgeraker | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `vs_dr_shield_axe` | _(unresolved: dw_1h_axe_shield_skin_01_name)_ | dr_1h_axe_shield | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `vs_dr_shield_hammer` | _(unresolved: dw_1h_hammer_shield_skin_01_name)_ | dr_1h_hammer_shield | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `vs_dr_steam_pistol` | _(unresolved: dr_steam_pistol_skin_01_name)_ _(dlc:cog)_ | dr_steam_pistol | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `vs_es_1h_flail` | _(unresolved: es_1h_flail_skin_01_name)_ | es_flail | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `vs_es_1h_mace` | _(unresolved: es_1h_mace_skin_01_name)_ | es_1h_mace | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `vs_es_1h_sword` | _(unresolved: es_1h_sword_skin_01_name)_ | es_1h_sword | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `vs_es_2h_hammer` | _(unresolved: es_2h_hammer_skin_05_name)_ | es_2h_war_hammer | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `vs_es_2h_hammer_tutorial` | _(unresolved: display_name_plentiful_empire_soldier_es_2h_war_hammer)_ | es_2h_war_hammer | empire_soldier_tutorial | unresolved |
| `vs_es_2h_heavy_spear` | _(unresolved: es_2h_heavy_spear_skin_01_name)_ _(dlc:scorpion)_ | es_2h_heavy_spear | es_huntsman, es_mercenary | unresolved |
| `vs_es_2h_sword` | _(unresolved: es_2h_sword_skin_01_name)_ | es_2h_sword | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `vs_es_2h_sword_executioner` | _(unresolved: es_2h_sword_exe_skin_01_name)_ | es_2h_sword_executioner | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `vs_es_bastard_sword` | _(unresolved: es_bastard_sword_skin_01_name)_ _(dlc:lake)_ | es_bastard_sword | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `vs_es_blunderbuss` | _(unresolved: es_blunderbuss_skin_03_name)_ | es_blunderbuss | es_huntsman, es_knight, es_mercenary | unresolved |
| `vs_es_deus_01` | _(unresolved: es_deus_01_name)_ _(dlc:grass)_ | es_deus_01 | es_huntsman, es_knight, es_mercenary | unresolved |
| `vs_es_dual_wield_hammer_sword` | _(unresolved: es_dual_wield_hammer_sword_skin_01_name)_ _(dlc:holly)_ | es_dual_wield_hammer_sword | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `vs_es_halberd` | _(unresolved: es_halberd_skin_01_name)_ | es_2h_halberd | es_huntsman, es_knight, es_mercenary | unresolved |
| `vs_es_handgun` | _(unresolved: es_handgun_skin_03_name)_ | es_handgun | es_huntsman, es_knight, es_mercenary | unresolved |
| `vs_es_longbow` | _(unresolved: es_longbow_skin_01_name)_ | ww_longbow | es_huntsman | unresolved |
| `vs_es_longbow_tutorial` | _(unresolved: display_name_plentiful_empire_soldier_es_longbow)_ | ww_longbow | empire_soldier_tutorial | unresolved |
| `vs_es_mace_shield` | _(unresolved: es_1h_mace_shield_skin_02_name)_ | es_1h_mace_shield | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `vs_es_repeating_handgun` | _(unresolved: es_repeating_handgun_skin_01_name)_ | es_repeating_handgun | es_huntsman, es_knight, es_mercenary | unresolved |
| `vs_es_sword_shield` | _(unresolved: es_1h_sword_shield_skin_02_name)_ | es_1h_sword_shield | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `vs_es_sword_shield_breton` | _(unresolved: es_sword_shield_breton_skin_01_name)_ _(dlc:lake)_ | es_1h_sword_shield_breton | es_questingknight | unresolved |
| `vs_gutter_runner_claws` | _(unresolved: dw_1h_axe_skin_01_name)_ | we_dual_wield_daggers | vs_gutter_runner | unresolved |
| `vs_gutter_runner_claws_1001` | _(unresolved: display_name_vs_gutter_runner_claws_1001)_ | we_dual_wield_daggers | vs_gutter_runner | unresolved |
| `vs_packmaster_claw` | _(unresolved: dw_1h_axe_skin_01_name)_ | we_spear | vs_packmaster | unresolved |
| `vs_packmaster_claw_skin_1001` | _(unresolved: display_name_vs_packmaster_claw_1001)_ | we_spear | vs_packmaster | unresolved |
| `vs_poison_wind_globadier_orb` | _(unresolved: dw_1h_axe_skin_01_name)_ | dr_1h_axes | vs_poison_wind_globadier | unresolved |
| `vs_poison_wind_globadier_orb_1001` | _(unresolved: display_name_vs_poison_wind_globadier_orb_1001)_ | dr_1h_axes | vs_poison_wind_globadier | unresolved |
| `vs_rat_ogre_hands` | _(unresolved: dw_1h_axe_skin_01_name)_ | dr_1h_axes | vs_rat_ogre | unresolved |
| `vs_ratling_gunner_gun` | _(unresolved: dw_1h_axe_skin_01_name)_ | dr_drakegun | vs_ratling_gunner | unresolved |
| `vs_ratling_gunner_gun_1001` | _(unresolved: display_name_vs_ratling_gunner_gun_1001)_ | dr_drakegun | vs_ratling_gunner | unresolved |
| `vs_warpfire_thrower_gun` | _(unresolved: dw_1h_axe_skin_01_name)_ | dr_drakegun | vs_warpfire_thrower | unresolved |
| `vs_warpfire_thrower_gun_skin_1001` | _(unresolved: display_name_vs_warpfire_thrower_gun_1001)_ | dr_drakegun | vs_warpfire_thrower | unresolved |
| `vs_we_1h_axe` | _(unresolved: we_1h_axe_skin_01_name)_ _(dlc:holly)_ | we_1h_axe | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_we_1h_spears_shield` | _(unresolved: we_1h_spears_shield_skin_01_name)_ _(dlc:scorpion)_ | we_1h_spears_shield | we_maidenguard | unresolved |
| `vs_we_1h_sword` | _(unresolved: we_sword_skin_01_name)_ | ww_1h_sword | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_we_2h_axe` | _(unresolved: we_2h_axe_skin_07_name)_ | ww_2h_axe | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_we_2h_sword` | _(unresolved: we_2h_sword_skin_01_name)_ | ww_2h_sword | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_we_crossbow_repeater` | _(unresolved: we_crossbow_skin_01_name)_ | wh_repeating_crossbow | we_shade | unresolved |
| `vs_we_deus_01` | _(unresolved: we_deus_01_name)_ _(dlc:grass)_ | we_deus_01 | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_we_dual_wield_daggers` | _(unresolved: we_dual_dagger_skin_01_name)_ | ww_dual_daggers | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_we_dual_wield_sword_dagger` | _(unresolved: we_dual_sword_dagger_skin_04_name)_ | ww_sword_and_dagger | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_we_dual_wield_swords` | _(unresolved: we_dual_sword_skin_04_name)_ | ww_dual_swords | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_we_javelin` | _(unresolved: we_javelin_skin_01_name)_ _(dlc:woods)_ | we_javelin | we_thornsister, we_shade, we_maidenguard, we_waywatcher | unresolved |
| `vs_we_life_staff` | _(unresolved: we_life_staff_skin_01_name)_ _(dlc:woods)_ | we_life_staff | we_thornsister | unresolved |
| `vs_we_longbow` | _(unresolved: we_longbow_skin_05_name)_ | ww_longbow | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_we_shortbow` | _(unresolved: we_shortbow_skin_01_name)_ | ww_shortbow | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_we_shortbow_hagbane` | _(unresolved: we_hagbane_skin_01_name)_ | ww_hagbane | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_we_spear` | _(unresolved: we_spear_skin_01_name)_ | we_2h_spear | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `vs_wh_1h_axe` | _(unresolved: wh_1h_axe_skin_05_name)_ | wh_1h_axes | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `vs_wh_1h_falchion` | _(unresolved: wh_1h_falchion_skin_01_name)_ | wh_1h_falchions | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `vs_wh_1h_hammer` | _(unresolved: wh_1h_hammer_skin_01_name)_ _(dlc:bless)_ | wh_1h_hammer | wh_priest, wh_zealot | unresolved |
| `vs_wh_2h_billhook` | _(unresolved: wh_2h_billhook_skin_01_name)_ _(dlc:scorpion)_ | wh_2h_billhook | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `vs_wh_2h_hammer` | _(unresolved: wh_2h_hammer_skin_01_name)_ _(dlc:bless)_ | wh_2h_hammer | wh_priest, wh_zealot | unresolved |
| `vs_wh_2h_sword` | _(unresolved: wh_2h_sword_skin_01_name)_ | wh_2h_sword | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `vs_wh_brace_of_pistols` | _(unresolved: wh_brace_of_pistols_skin_01_name)_ | wh_brace_of_pisols | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `vs_wh_crossbow` | _(unresolved: wh_crossbow_skin_05_name)_ | wh_crossbow | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `vs_wh_crossbow_repeater` | _(unresolved: wh_repeating_crossbow_skin_01_name)_ | wh_repeating_crossbow | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `vs_wh_deus_01` | _(unresolved: wh_deus_01_name)_ _(dlc:grass)_ | wh_deus_01 | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `vs_wh_dual_hammer` | _(unresolved: wh_dual_hammer_skin_01_name)_ _(dlc:bless)_ | wh_dual_hammer | wh_priest, wh_zealot | unresolved |
| `vs_wh_dual_wield_axe_falchion` | _(unresolved: wh_dual_wield_axe_falchion_skin_01_name)_ _(dlc:holly)_ | wh_dual_wield_axe_falchion | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `vs_wh_fencing_sword` | _(unresolved: wh_fencing_sword_skin_01_name)_ | wh_fencing_sword | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `vs_wh_flail_shield` | _(unresolved: wh_flail_shield_skin_01_name)_ _(dlc:bless)_ | wh_flail_shield | wh_priest | unresolved |
| `vs_wh_hammer_book` | _(unresolved: wh_hammer_book_skin_01_name)_ _(dlc:bless)_ | wh_hammer_book | wh_priest | unresolved |
| `vs_wh_hammer_shield` | _(unresolved: wh_hammer_shield_skin_01_name)_ _(dlc:bless)_ | wh_hammer_shield | wh_priest | unresolved |
| `vs_wh_repeating_pistols` | _(unresolved: wh_repeating_pistol_skin_04_name)_ | wh_repeating_pistol | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `we_1h_axe` | _(unresolved: we_1h_axe_skin_01_name)_ _(dlc:holly)_ | we_1h_axe | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_1h_axe_magic_01` | _(unresolved: we_1h_axe_skin_02_magic_01_name)_ | we_1h_axe | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_1h_spears_shield` | _(unresolved: we_1h_spears_shield_skin_01_name)_ _(dlc:scorpion)_ | we_1h_spears_shield | we_maidenguard | unresolved |
| `we_1h_spears_shield_magic_01` | _(unresolved: we_1h_spears_shield_skin_02_magic_01_name)_ | we_1h_spears_shield | we_maidenguard | unresolved |
| `we_1h_sword` | _(unresolved: we_sword_skin_01_name)_ | ww_1h_sword | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_1h_sword_magic_01` | _(unresolved: we_sword_skin_06_magic_01_name)_ | ww_1h_sword | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe` | _(unresolved: we_2h_axe_skin_07_name)_ | ww_2h_axe | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_magic_01` | _(unresolved: we_2h_axe_skin_03_magic_01_name)_ | ww_2h_axe | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword` | _(unresolved: we_2h_sword_skin_01_name)_ | ww_2h_sword | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_magic_01` | _(unresolved: we_2h_sword_skin_08_magic_01_name)_ | ww_2h_sword | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_crossbow_repeater` | _(unresolved: we_crossbow_skin_01_name)_ | wh_repeating_crossbow | we_shade | unresolved |
| `we_crossbow_repeater_magic_01` | _(unresolved: we_crossbow_skin_01_magic_01_name)_ | wh_repeating_crossbow | we_shade | unresolved |
| `we_dual_wield_daggers` | _(unresolved: we_dual_dagger_skin_01_name)_ | ww_dual_daggers | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_wield_daggers_magic_01` | _(unresolved: we_dual_dagger_skin_07_magic_01_name)_ | ww_dual_daggers | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_wield_sword_dagger` | _(unresolved: we_dual_sword_dagger_skin_04_name)_ | ww_sword_and_dagger | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_wield_sword_dagger_magic_01` | _(unresolved: we_dual_sword_dagger_skin_07_magic_01_name)_ | ww_sword_and_dagger | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_wield_swords` | _(unresolved: we_dual_sword_skin_04_name)_ | ww_dual_swords | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_wield_swords_magic_01` | _(unresolved: we_dual_sword_skin_06_magic_01_name)_ | ww_dual_swords | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_javelin` | _(unresolved: we_javelin_skin_01_name)_ _(dlc:woods)_ | we_javelin | we_thornsister, we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_javelin_magic` | _(unresolved: we_javelin_skin_02_magic_01_name)_ _(dlc:woods)_ | we_javelin | we_thornsister, we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_life_staff` | _(unresolved: we_life_staff_skin_01_name)_ _(dlc:woods)_ | we_life_staff | we_thornsister | unresolved |
| `we_life_staff_magic` | _(unresolved: we_life_staff_skin_02_magic_01_name)_ _(dlc:woods)_ | we_life_staff | we_thornsister | unresolved |
| `we_longbow` | _(unresolved: we_longbow_skin_05_name)_ | ww_longbow | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_magic_01` | _(unresolved: we_longbow_skin_02_magic_01_name)_ | ww_longbow | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow` | _(unresolved: we_shortbow_skin_01_name)_ | ww_shortbow | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_hagbane` | _(unresolved: we_hagbane_skin_01_name)_ | ww_hagbane | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_hagbane_magic_01` | _(unresolved: we_shortbow_hagbane_skin_02_magic_01_name)_ | ww_hagbane | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_magic_01` | _(unresolved: we_shortbow_skin_02_magic_01_name)_ | ww_shortbow | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear` | _(unresolved: we_spear_skin_01_name)_ | we_2h_spear | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_magic_01` | _(unresolved: we_spear_skin_02_magic_01_name)_ | we_2h_spear | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `wh_1h_axe` | _(unresolved: wh_1h_axe_skin_05_name)_ | wh_1h_axes | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_magic_01` | _(unresolved: wh_1h_axe_skin_06_magic_01_name)_ | wh_1h_axes | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion` | _(unresolved: wh_1h_falchion_skin_01_name)_ | wh_1h_falchions | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_magic_01` | _(unresolved: wh_1h_falchion_skin_04_magic_01_name)_ | wh_1h_falchions | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_hammer` | _(unresolved: wh_1h_hammer_skin_01_name)_ _(dlc:bless)_ | wh_1h_hammer | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_magic_01` | _(unresolved: wh_1h_hammer_skin_02_magic_01_name)_ _(dlc:bless)_ | wh_1h_hammer | wh_priest, wh_zealot | unresolved |
| `wh_2h_billhook` | _(unresolved: wh_2h_billhook_skin_01_name)_ _(dlc:scorpion)_ | wh_2h_billhook | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_billhook_magic_01` | _(unresolved: wh_2h_billhook_skin_02_magic_01_name)_ | wh_2h_billhook | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_hammer` | _(unresolved: wh_2h_hammer_skin_01_name)_ _(dlc:bless)_ | wh_2h_hammer | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_magic_01` | _(unresolved: wh_2h_hammer_skin_02_magic_01_name)_ _(dlc:bless)_ | wh_2h_hammer | wh_priest, wh_zealot | unresolved |
| `wh_2h_sword` | _(unresolved: wh_2h_sword_skin_01_name)_ | wh_2h_sword | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_magic_01` | _(unresolved: wh_2h_sword_skin_04_magic_01_name)_ | wh_2h_sword | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols` | _(unresolved: wh_brace_of_pistols_skin_01_name)_ | wh_brace_of_pisols | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_magic_01` | _(unresolved: wh_brace_of_pistols_skin_05_magic_01_name)_ | wh_brace_of_pisols | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow` | _(unresolved: wh_crossbow_skin_05_name)_ | wh_crossbow | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_magic_01` | _(unresolved: wh_crossbow_skin_06_magic_01_name)_ | wh_crossbow | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_repeater` | _(unresolved: wh_repeating_crossbow_skin_01_name)_ | wh_repeating_crossbow | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_repeater_magic_01` | _(unresolved: wh_repeating_crossbow_skin_02_magic_01_name)_ | wh_repeating_crossbow | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_hammer` | _(unresolved: wh_dual_hammer_skin_01_name)_ _(dlc:bless)_ | wh_dual_hammer | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_magic_01` | _(unresolved: wh_dual_hammer_skin_02_magic_01_name)_ _(dlc:bless)_ | wh_dual_hammer | wh_priest, wh_zealot | unresolved |
| `wh_dual_wield_axe_falchion` | _(unresolved: wh_dual_wield_axe_falchion_skin_01_name)_ _(dlc:holly)_ | wh_dual_wield_axe_falchion | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_wield_axe_falchion_magic_01` | _(unresolved: wh_dual_wield_axe_falchion_skin_01_magic_01_name)_ | wh_dual_wield_axe_falchion | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_fencing_sword` | _(unresolved: wh_fencing_sword_skin_01_name)_ | wh_fencing_sword | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_magic_01` | _(unresolved: wh_fencing_sword_skin_07_magic_01_name)_ | wh_fencing_sword | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_flail_shield` | _(unresolved: wh_flail_shield_skin_01_name)_ _(dlc:bless)_ | wh_flail_shield | wh_priest | unresolved |
| `wh_flail_shield_magic_01` | _(unresolved: wh_flail_shield_skin_02_magic_01_name)_ _(dlc:bless)_ | wh_flail_shield | wh_priest | unresolved |
| `wh_hammer_book` | _(unresolved: wh_hammer_book_skin_01_name)_ _(dlc:bless)_ | wh_hammer_book | wh_priest | unresolved |
| `wh_hammer_book_magic_01` | _(unresolved: wh_hammer_book_skin_02_magic_01_name)_ _(dlc:bless)_ | wh_hammer_book | wh_priest | unresolved |
| `wh_hammer_shield` | _(unresolved: wh_hammer_shield_skin_01_name)_ _(dlc:bless)_ | wh_hammer_shield | wh_priest | unresolved |
| `wh_hammer_shield_magic_01` | _(unresolved: wh_hammer_shield_skin_02_magic_01_name)_ _(dlc:bless)_ | wh_hammer_shield | wh_priest | unresolved |
| `wh_priest_career_weapon_preview` | _(unresolved: wh_hammer_book_name)_ _(dlc:bless)_ | wh_hammer_book | wh_priest | unresolved |
| `wh_repeating_pistols` | _(unresolved: wh_repeating_pistol_skin_04_name)_ | wh_repeating_pistol | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistols_magic_01` | _(unresolved: wh_repeating_pistol_skin_05_magic_01_name)_ | wh_repeating_pistol | wh_zealot, wh_bountyhunter, wh_captain | unresolved |

### kind: weapon_pose (529 entries, 529 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `bw_1h_crowbill_weapon_pose_01` | _(unresolved: bw_1h_crowbill_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_crowbill_weapon_pose_02` | _(unresolved: bw_1h_crowbill_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_crowbill_weapon_pose_03` | _(unresolved: bw_1h_crowbill_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_crowbill_weapon_pose_04` | _(unresolved: bw_1h_crowbill_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_crowbill_weapon_pose_05` | _(unresolved: bw_1h_crowbill_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_crowbill_weapon_pose_06` | _(unresolved: bw_1h_crowbill_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_flail_flaming_weapon_pose_01` | _(unresolved: bw_1h_flail_flaming_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_flail_flaming_weapon_pose_02` | _(unresolved: bw_1h_flail_flaming_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_flail_flaming_weapon_pose_03` | _(unresolved: bw_1h_flail_flaming_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_flail_flaming_weapon_pose_04` | _(unresolved: bw_1h_flail_flaming_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_flail_flaming_weapon_pose_05` | _(unresolved: bw_1h_flail_flaming_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_flail_flaming_weapon_pose_06` | _(unresolved: bw_1h_flail_flaming_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_mace_weapon_pose_01` | _(unresolved: bw_1h_mace_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_mace_weapon_pose_02` | _(unresolved: bw_1h_mace_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_mace_weapon_pose_03` | _(unresolved: bw_1h_mace_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_mace_weapon_pose_04` | _(unresolved: bw_1h_mace_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_mace_weapon_pose_05` | _(unresolved: bw_1h_mace_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_1h_mace_weapon_pose_06` | _(unresolved: bw_1h_mace_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_dagger_weapon_pose_01` | _(unresolved: bw_dagger_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_dagger_weapon_pose_02` | _(unresolved: bw_dagger_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_dagger_weapon_pose_03` | _(unresolved: bw_dagger_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_dagger_weapon_pose_04` | _(unresolved: bw_dagger_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_dagger_weapon_pose_05` | _(unresolved: bw_dagger_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_dagger_weapon_pose_06` | _(unresolved: bw_dagger_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_deus_01_weapon_pose_01` | _(unresolved: bw_deus_01_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_deus_01_weapon_pose_02` | _(unresolved: bw_deus_01_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_deus_01_weapon_pose_03` | _(unresolved: bw_deus_01_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_deus_01_weapon_pose_04` | _(unresolved: bw_deus_01_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_deus_01_weapon_pose_05` | _(unresolved: bw_deus_01_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_deus_01_weapon_pose_06` | _(unresolved: bw_deus_01_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_flame_sword_weapon_pose_01` | _(unresolved: bw_flame_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_flame_sword_weapon_pose_02` | _(unresolved: bw_flame_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_flame_sword_weapon_pose_03` | _(unresolved: bw_flame_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_flame_sword_weapon_pose_04` | _(unresolved: bw_flame_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_flame_sword_weapon_pose_05` | _(unresolved: bw_flame_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_flame_sword_weapon_pose_06` | _(unresolved: bw_flame_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_ghost_scythe_weapon_pose_01` | _(unresolved: bw_ghost_scythe_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_ghost_scythe_weapon_pose_02` | _(unresolved: bw_ghost_scythe_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_ghost_scythe_weapon_pose_03` | _(unresolved: bw_ghost_scythe_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_ghost_scythe_weapon_pose_04` | _(unresolved: bw_ghost_scythe_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_ghost_scythe_weapon_pose_05` | _(unresolved: bw_ghost_scythe_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_ghost_scythe_weapon_pose_06` | _(unresolved: bw_ghost_scythe_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_necromancy_staff_weapon_pose_01` | _(unresolved: bw_necromancy_staff_emote_wheel)_ | weapon_pose | bw_necromancer | unresolved |
| `bw_necromancy_staff_weapon_pose_02` | _(unresolved: bw_necromancy_staff_emote_wheel)_ | weapon_pose | bw_necromancer | unresolved |
| `bw_necromancy_staff_weapon_pose_03` | _(unresolved: bw_necromancy_staff_emote_wheel)_ | weapon_pose | bw_necromancer | unresolved |
| `bw_necromancy_staff_weapon_pose_04` | _(unresolved: bw_necromancy_staff_emote_wheel)_ | weapon_pose | bw_necromancer | unresolved |
| `bw_necromancy_staff_weapon_pose_05` | _(unresolved: bw_necromancy_staff_emote_wheel)_ | weapon_pose | bw_necromancer | unresolved |
| `bw_necromancy_staff_weapon_pose_06` | _(unresolved: bw_necromancy_staff_emote_wheel)_ | weapon_pose | bw_necromancer | unresolved |
| `bw_skullstaff_beam_weapon_pose_01` | _(unresolved: bw_skullstaff_beam_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_beam_weapon_pose_02` | _(unresolved: bw_skullstaff_beam_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_beam_weapon_pose_03` | _(unresolved: bw_skullstaff_beam_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_beam_weapon_pose_04` | _(unresolved: bw_skullstaff_beam_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_beam_weapon_pose_05` | _(unresolved: bw_skullstaff_beam_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_beam_weapon_pose_06` | _(unresolved: bw_skullstaff_beam_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_fireball_weapon_pose_01` | _(unresolved: bw_skullstaff_fireball_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_fireball_weapon_pose_02` | _(unresolved: bw_skullstaff_fireball_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_fireball_weapon_pose_03` | _(unresolved: bw_skullstaff_fireball_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_fireball_weapon_pose_04` | _(unresolved: bw_skullstaff_fireball_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_fireball_weapon_pose_05` | _(unresolved: bw_skullstaff_fireball_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_fireball_weapon_pose_06` | _(unresolved: bw_skullstaff_fireball_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_flamethrower_weapon_pose_01` | _(unresolved: bw_skullstaff_flamethrower_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_flamethrower_weapon_pose_02` | _(unresolved: bw_skullstaff_flamethrower_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_flamethrower_weapon_pose_03` | _(unresolved: bw_skullstaff_flamethrower_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_flamethrower_weapon_pose_04` | _(unresolved: bw_skullstaff_flamethrower_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_flamethrower_weapon_pose_05` | _(unresolved: bw_skullstaff_flamethrower_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_flamethrower_weapon_pose_06` | _(unresolved: bw_skullstaff_flamethrower_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_skullstaff_geiser_weapon_pose_01` | _(unresolved: bw_skullstaff_geiser_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_geiser_weapon_pose_02` | _(unresolved: bw_skullstaff_geiser_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_geiser_weapon_pose_03` | _(unresolved: bw_skullstaff_geiser_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_geiser_weapon_pose_04` | _(unresolved: bw_skullstaff_geiser_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_geiser_weapon_pose_05` | _(unresolved: bw_skullstaff_geiser_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_geiser_weapon_pose_06` | _(unresolved: bw_skullstaff_geiser_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_spear_weapon_pose_01` | _(unresolved: bw_skullstaff_spear_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_spear_weapon_pose_02` | _(unresolved: bw_skullstaff_spear_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_spear_weapon_pose_03` | _(unresolved: bw_skullstaff_spear_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_spear_weapon_pose_04` | _(unresolved: bw_skullstaff_spear_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_spear_weapon_pose_05` | _(unresolved: bw_skullstaff_spear_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_skullstaff_spear_weapon_pose_06` | _(unresolved: bw_skullstaff_spear_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_sword_weapon_pose_01` | _(unresolved: bw_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_sword_weapon_pose_02` | _(unresolved: bw_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_sword_weapon_pose_03` | _(unresolved: bw_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_sword_weapon_pose_04` | _(unresolved: bw_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_sword_weapon_pose_05` | _(unresolved: bw_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_sword_weapon_pose_06` | _(unresolved: bw_sword_emote_wheel)_ | weapon_pose | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `default_weapon_pose_01` | _(unresolved: default_weapon_pose_01)_ | weapon_pose |  | unresolved |
| `dr_1h_axe_weapon_pose_01` | _(unresolved: dr_1h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_axe_weapon_pose_02` | _(unresolved: dr_1h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_axe_weapon_pose_03` | _(unresolved: dr_1h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_axe_weapon_pose_04` | _(unresolved: dr_1h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_axe_weapon_pose_05` | _(unresolved: dr_1h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_axe_weapon_pose_06` | _(unresolved: dr_1h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_hammer_weapon_pose_01` | _(unresolved: dr_1h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_hammer_weapon_pose_02` | _(unresolved: dr_1h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_hammer_weapon_pose_03` | _(unresolved: dr_1h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_hammer_weapon_pose_04` | _(unresolved: dr_1h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_hammer_weapon_pose_05` | _(unresolved: dr_1h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_hammer_weapon_pose_06` | _(unresolved: dr_1h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_1h_throwing_axes_weapon_pose_01` | _(unresolved: dr_1h_throwing_axes_emote_wheel)_ | weapon_pose | dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_weapon_pose_02` | _(unresolved: dr_1h_throwing_axes_emote_wheel)_ | weapon_pose | dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_weapon_pose_03` | _(unresolved: dr_1h_throwing_axes_emote_wheel)_ | weapon_pose | dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_weapon_pose_04` | _(unresolved: dr_1h_throwing_axes_emote_wheel)_ | weapon_pose | dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_weapon_pose_05` | _(unresolved: dr_1h_throwing_axes_emote_wheel)_ | weapon_pose | dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_weapon_pose_06` | _(unresolved: dr_1h_throwing_axes_emote_wheel)_ | weapon_pose | dr_slayer, dr_ranger | unresolved |
| `dr_2h_axe_weapon_pose_01` | _(unresolved: dr_2h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_axe_weapon_pose_02` | _(unresolved: dr_2h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_axe_weapon_pose_03` | _(unresolved: dr_2h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_axe_weapon_pose_04` | _(unresolved: dr_2h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_axe_weapon_pose_05` | _(unresolved: dr_2h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_axe_weapon_pose_06` | _(unresolved: dr_2h_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_cog_hammer_weapon_pose_01` | _(unresolved: dr_2h_cog_hammer_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_weapon_pose_02` | _(unresolved: dr_2h_cog_hammer_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_weapon_pose_03` | _(unresolved: dr_2h_cog_hammer_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_weapon_pose_04` | _(unresolved: dr_2h_cog_hammer_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_weapon_pose_05` | _(unresolved: dr_2h_cog_hammer_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_weapon_pose_06` | _(unresolved: dr_2h_cog_hammer_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_hammer_weapon_pose_01` | _(unresolved: dr_2h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_hammer_weapon_pose_02` | _(unresolved: dr_2h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_hammer_weapon_pose_03` | _(unresolved: dr_2h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_hammer_weapon_pose_04` | _(unresolved: dr_2h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_hammer_weapon_pose_05` | _(unresolved: dr_2h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_hammer_weapon_pose_06` | _(unresolved: dr_2h_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_pick_weapon_pose_01` | _(unresolved: dr_2h_pick_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_pick_weapon_pose_02` | _(unresolved: dr_2h_pick_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_pick_weapon_pose_03` | _(unresolved: dr_2h_pick_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_pick_weapon_pose_04` | _(unresolved: dr_2h_pick_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_pick_weapon_pose_05` | _(unresolved: dr_2h_pick_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_2h_pick_weapon_pose_06` | _(unresolved: dr_2h_pick_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_crossbow_weapon_pose_01` | _(unresolved: dr_crossbow_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger | unresolved |
| `dr_crossbow_weapon_pose_02` | _(unresolved: dr_crossbow_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger | unresolved |
| `dr_crossbow_weapon_pose_03` | _(unresolved: dr_crossbow_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger | unresolved |
| `dr_crossbow_weapon_pose_04` | _(unresolved: dr_crossbow_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger | unresolved |
| `dr_crossbow_weapon_pose_05` | _(unresolved: dr_crossbow_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger | unresolved |
| `dr_crossbow_weapon_pose_06` | _(unresolved: dr_crossbow_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger | unresolved |
| `dr_deus_01_weapon_pose_01` | _(unresolved: dr_deus_01_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_deus_01_weapon_pose_02` | _(unresolved: dr_deus_01_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_deus_01_weapon_pose_03` | _(unresolved: dr_deus_01_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_deus_01_weapon_pose_04` | _(unresolved: dr_deus_01_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_deus_01_weapon_pose_05` | _(unresolved: dr_deus_01_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_deus_01_weapon_pose_06` | _(unresolved: dr_deus_01_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drake_pistol_weapon_pose_01` | _(unresolved: dr_drake_pistol_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drake_pistol_weapon_pose_02` | _(unresolved: dr_drake_pistol_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drake_pistol_weapon_pose_03` | _(unresolved: dr_drake_pistol_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drake_pistol_weapon_pose_04` | _(unresolved: dr_drake_pistol_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drake_pistol_weapon_pose_05` | _(unresolved: dr_drake_pistol_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drake_pistol_weapon_pose_06` | _(unresolved: dr_drake_pistol_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drakegun_weapon_pose_01` | _(unresolved: dr_drakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drakegun_weapon_pose_02` | _(unresolved: dr_drakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drakegun_weapon_pose_03` | _(unresolved: dr_drakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drakegun_weapon_pose_04` | _(unresolved: dr_drakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drakegun_weapon_pose_05` | _(unresolved: dr_drakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drakegun_weapon_pose_06` | _(unresolved: dr_drakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_engineer | unresolved |
| `dr_dual_wield_axes_weapon_pose_01` | _(unresolved: dr_dual_wield_axes_emote_wheel)_ | weapon_pose | dr_slayer | unresolved |
| `dr_dual_wield_axes_weapon_pose_02` | _(unresolved: dr_dual_wield_axes_emote_wheel)_ | weapon_pose | dr_slayer | unresolved |
| `dr_dual_wield_axes_weapon_pose_03` | _(unresolved: dr_dual_wield_axes_emote_wheel)_ | weapon_pose | dr_slayer | unresolved |
| `dr_dual_wield_axes_weapon_pose_04` | _(unresolved: dr_dual_wield_axes_emote_wheel)_ | weapon_pose | dr_slayer | unresolved |
| `dr_dual_wield_axes_weapon_pose_05` | _(unresolved: dr_dual_wield_axes_emote_wheel)_ | weapon_pose | dr_slayer | unresolved |
| `dr_dual_wield_axes_weapon_pose_06` | _(unresolved: dr_dual_wield_axes_emote_wheel)_ | weapon_pose | dr_slayer | unresolved |
| `dr_dual_wield_hammers_weapon_pose_01` | _(unresolved: dr_dual_wield_hammers_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_dual_wield_hammers_weapon_pose_02` | _(unresolved: dr_dual_wield_hammers_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_dual_wield_hammers_weapon_pose_03` | _(unresolved: dr_dual_wield_hammers_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_dual_wield_hammers_weapon_pose_04` | _(unresolved: dr_dual_wield_hammers_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_dual_wield_hammers_weapon_pose_05` | _(unresolved: dr_dual_wield_hammers_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_dual_wield_hammers_weapon_pose_06` | _(unresolved: dr_dual_wield_hammers_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `dr_handgun_weapon_pose_01` | _(unresolved: dr_handgun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_handgun_weapon_pose_02` | _(unresolved: dr_handgun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_handgun_weapon_pose_03` | _(unresolved: dr_handgun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_handgun_weapon_pose_04` | _(unresolved: dr_handgun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_handgun_weapon_pose_05` | _(unresolved: dr_handgun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_handgun_weapon_pose_06` | _(unresolved: dr_handgun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_rakegun_weapon_pose_01` | _(unresolved: dr_rakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_rakegun_weapon_pose_02` | _(unresolved: dr_rakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_rakegun_weapon_pose_03` | _(unresolved: dr_rakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_rakegun_weapon_pose_04` | _(unresolved: dr_rakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_rakegun_weapon_pose_05` | _(unresolved: dr_rakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_rakegun_weapon_pose_06` | _(unresolved: dr_rakegun_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_axe_weapon_pose_01` | _(unresolved: dr_shield_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_axe_weapon_pose_02` | _(unresolved: dr_shield_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_axe_weapon_pose_03` | _(unresolved: dr_shield_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_axe_weapon_pose_04` | _(unresolved: dr_shield_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_axe_weapon_pose_05` | _(unresolved: dr_shield_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_axe_weapon_pose_06` | _(unresolved: dr_shield_axe_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_hammer_weapon_pose_01` | _(unresolved: dr_shield_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_hammer_weapon_pose_02` | _(unresolved: dr_shield_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_hammer_weapon_pose_03` | _(unresolved: dr_shield_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_hammer_weapon_pose_04` | _(unresolved: dr_shield_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_hammer_weapon_pose_05` | _(unresolved: dr_shield_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_shield_hammer_weapon_pose_06` | _(unresolved: dr_shield_hammer_emote_wheel)_ | weapon_pose | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `dr_steam_pistol_weapon_pose_01` | _(unresolved: dr_steam_pistol_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_weapon_pose_02` | _(unresolved: dr_steam_pistol_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_weapon_pose_03` | _(unresolved: dr_steam_pistol_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_weapon_pose_04` | _(unresolved: dr_steam_pistol_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_weapon_pose_05` | _(unresolved: dr_steam_pistol_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_weapon_pose_06` | _(unresolved: dr_steam_pistol_emote_wheel)_ | weapon_pose | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `es_1h_flail_weapon_pose_01` | _(unresolved: es_1h_flail_emote_wheel)_ | weapon_pose | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_weapon_pose_02` | _(unresolved: es_1h_flail_emote_wheel)_ | weapon_pose | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_weapon_pose_03` | _(unresolved: es_1h_flail_emote_wheel)_ | weapon_pose | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_weapon_pose_04` | _(unresolved: es_1h_flail_emote_wheel)_ | weapon_pose | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_weapon_pose_05` | _(unresolved: es_1h_flail_emote_wheel)_ | weapon_pose | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_weapon_pose_06` | _(unresolved: es_1h_flail_emote_wheel)_ | weapon_pose | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_mace_weapon_pose_01` | _(unresolved: es_1h_mace_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_1h_mace_weapon_pose_02` | _(unresolved: es_1h_mace_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_1h_mace_weapon_pose_03` | _(unresolved: es_1h_mace_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_1h_mace_weapon_pose_04` | _(unresolved: es_1h_mace_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_1h_mace_weapon_pose_05` | _(unresolved: es_1h_mace_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_1h_mace_weapon_pose_06` | _(unresolved: es_1h_mace_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_1h_sword_weapon_pose_01` | _(unresolved: es_1h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_1h_sword_weapon_pose_02` | _(unresolved: es_1h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_1h_sword_weapon_pose_03` | _(unresolved: es_1h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_1h_sword_weapon_pose_04` | _(unresolved: es_1h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_1h_sword_weapon_pose_05` | _(unresolved: es_1h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_1h_sword_weapon_pose_06` | _(unresolved: es_1h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_hammer_weapon_pose_01` | _(unresolved: es_2h_hammer_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_hammer_weapon_pose_02` | _(unresolved: es_2h_hammer_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_hammer_weapon_pose_03` | _(unresolved: es_2h_hammer_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_hammer_weapon_pose_04` | _(unresolved: es_2h_hammer_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_hammer_weapon_pose_05` | _(unresolved: es_2h_hammer_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_hammer_weapon_pose_06` | _(unresolved: es_2h_hammer_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_heavy_spear_weapon_pose_01` | _(unresolved: es_2h_heavy_spear_emote_wheel)_ | weapon_pose | es_huntsman, es_mercenary | unresolved |
| `es_2h_heavy_spear_weapon_pose_02` | _(unresolved: es_2h_heavy_spear_emote_wheel)_ | weapon_pose | es_huntsman, es_mercenary | unresolved |
| `es_2h_heavy_spear_weapon_pose_03` | _(unresolved: es_2h_heavy_spear_emote_wheel)_ | weapon_pose | es_huntsman, es_mercenary | unresolved |
| `es_2h_heavy_spear_weapon_pose_04` | _(unresolved: es_2h_heavy_spear_emote_wheel)_ | weapon_pose | es_huntsman, es_mercenary | unresolved |
| `es_2h_heavy_spear_weapon_pose_05` | _(unresolved: es_2h_heavy_spear_emote_wheel)_ | weapon_pose | es_huntsman, es_mercenary | unresolved |
| `es_2h_heavy_spear_weapon_pose_06` | _(unresolved: es_2h_heavy_spear_emote_wheel)_ | weapon_pose | es_huntsman, es_mercenary | unresolved |
| `es_2h_sword_executioner_weapon_pose_01` | _(unresolved: es_2h_sword_executioner_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_sword_executioner_weapon_pose_02` | _(unresolved: es_2h_sword_executioner_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_sword_executioner_weapon_pose_03` | _(unresolved: es_2h_sword_executioner_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_sword_executioner_weapon_pose_04` | _(unresolved: es_2h_sword_executioner_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_sword_executioner_weapon_pose_05` | _(unresolved: es_2h_sword_executioner_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_sword_executioner_weapon_pose_06` | _(unresolved: es_2h_sword_executioner_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_sword_weapon_pose_01` | _(unresolved: es_2h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_sword_weapon_pose_02` | _(unresolved: es_2h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_sword_weapon_pose_03` | _(unresolved: es_2h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_sword_weapon_pose_04` | _(unresolved: es_2h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_sword_weapon_pose_05` | _(unresolved: es_2h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_2h_sword_weapon_pose_06` | _(unresolved: es_2h_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_weapon_pose_01` | _(unresolved: es_bastard_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_weapon_pose_02` | _(unresolved: es_bastard_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_weapon_pose_03` | _(unresolved: es_bastard_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_weapon_pose_04` | _(unresolved: es_bastard_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_weapon_pose_05` | _(unresolved: es_bastard_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_weapon_pose_06` | _(unresolved: es_bastard_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_blunderbuss_weapon_pose_01` | _(unresolved: es_blunderbuss_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_weapon_pose_02` | _(unresolved: es_blunderbuss_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_weapon_pose_03` | _(unresolved: es_blunderbuss_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_weapon_pose_04` | _(unresolved: es_blunderbuss_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_weapon_pose_05` | _(unresolved: es_blunderbuss_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_weapon_pose_06` | _(unresolved: es_blunderbuss_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_deus_01_weapon_pose_01` | _(unresolved: es_deus_01_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_deus_01_weapon_pose_02` | _(unresolved: es_deus_01_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_deus_01_weapon_pose_03` | _(unresolved: es_deus_01_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_deus_01_weapon_pose_04` | _(unresolved: es_deus_01_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_deus_01_weapon_pose_05` | _(unresolved: es_deus_01_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_deus_01_weapon_pose_06` | _(unresolved: es_deus_01_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_dual_wield_hammer_sword_weapon_pose_01` | _(unresolved: es_dual_wield_hammer_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_dual_wield_hammer_sword_weapon_pose_02` | _(unresolved: es_dual_wield_hammer_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_dual_wield_hammer_sword_weapon_pose_03` | _(unresolved: es_dual_wield_hammer_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_dual_wield_hammer_sword_weapon_pose_04` | _(unresolved: es_dual_wield_hammer_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_dual_wield_hammer_sword_weapon_pose_05` | _(unresolved: es_dual_wield_hammer_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_dual_wield_hammer_sword_weapon_pose_06` | _(unresolved: es_dual_wield_hammer_sword_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_halberd_weapon_pose_01` | _(unresolved: es_halberd_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_weapon_pose_02` | _(unresolved: es_halberd_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_weapon_pose_03` | _(unresolved: es_halberd_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_weapon_pose_04` | _(unresolved: es_halberd_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_weapon_pose_05` | _(unresolved: es_halberd_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_weapon_pose_06` | _(unresolved: es_halberd_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_weapon_pose_01` | _(unresolved: es_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_weapon_pose_02` | _(unresolved: es_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_weapon_pose_03` | _(unresolved: es_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_weapon_pose_04` | _(unresolved: es_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_weapon_pose_05` | _(unresolved: es_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_weapon_pose_06` | _(unresolved: es_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_longbow_weapon_pose_01` | _(unresolved: es_longbow_emote_wheel)_ | weapon_pose | es_huntsman | unresolved |
| `es_longbow_weapon_pose_02` | _(unresolved: es_longbow_emote_wheel)_ | weapon_pose | es_huntsman | unresolved |
| `es_longbow_weapon_pose_03` | _(unresolved: es_longbow_emote_wheel)_ | weapon_pose | es_huntsman | unresolved |
| `es_longbow_weapon_pose_04` | _(unresolved: es_longbow_emote_wheel)_ | weapon_pose | es_huntsman | unresolved |
| `es_longbow_weapon_pose_05` | _(unresolved: es_longbow_emote_wheel)_ | weapon_pose | es_huntsman | unresolved |
| `es_longbow_weapon_pose_06` | _(unresolved: es_longbow_emote_wheel)_ | weapon_pose | es_huntsman | unresolved |
| `es_mace_shield_weapon_pose_01` | _(unresolved: es_mace_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_mace_shield_weapon_pose_02` | _(unresolved: es_mace_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_mace_shield_weapon_pose_03` | _(unresolved: es_mace_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_mace_shield_weapon_pose_04` | _(unresolved: es_mace_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_mace_shield_weapon_pose_05` | _(unresolved: es_mace_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_mace_shield_weapon_pose_06` | _(unresolved: es_mace_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_repeating_handgun_weapon_pose_01` | _(unresolved: es_repeating_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_weapon_pose_02` | _(unresolved: es_repeating_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_weapon_pose_03` | _(unresolved: es_repeating_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_weapon_pose_04` | _(unresolved: es_repeating_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_weapon_pose_05` | _(unresolved: es_repeating_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_weapon_pose_06` | _(unresolved: es_repeating_handgun_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_sword_shield_breton_weapon_pose_01` | _(unresolved: es_sword_shield_breton_emote_wheel)_ | weapon_pose | es_questingknight | unresolved |
| `es_sword_shield_breton_weapon_pose_02` | _(unresolved: es_sword_shield_breton_emote_wheel)_ | weapon_pose | es_questingknight | unresolved |
| `es_sword_shield_breton_weapon_pose_03` | _(unresolved: es_sword_shield_breton_emote_wheel)_ | weapon_pose | es_questingknight | unresolved |
| `es_sword_shield_breton_weapon_pose_04` | _(unresolved: es_sword_shield_breton_emote_wheel)_ | weapon_pose | es_questingknight | unresolved |
| `es_sword_shield_breton_weapon_pose_05` | _(unresolved: es_sword_shield_breton_emote_wheel)_ | weapon_pose | es_questingknight | unresolved |
| `es_sword_shield_breton_weapon_pose_06` | _(unresolved: es_sword_shield_breton_emote_wheel)_ | weapon_pose | es_questingknight | unresolved |
| `es_sword_shield_weapon_pose_01` | _(unresolved: es_sword_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_sword_shield_weapon_pose_02` | _(unresolved: es_sword_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_sword_shield_weapon_pose_03` | _(unresolved: es_sword_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_sword_shield_weapon_pose_04` | _(unresolved: es_sword_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_sword_shield_weapon_pose_05` | _(unresolved: es_sword_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_sword_shield_weapon_pose_06` | _(unresolved: es_sword_shield_emote_wheel)_ | weapon_pose | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `we_1h_axe_weapon_pose_01` | _(unresolved: we_1h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_1h_axe_weapon_pose_02` | _(unresolved: we_1h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_1h_axe_weapon_pose_03` | _(unresolved: we_1h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_1h_axe_weapon_pose_04` | _(unresolved: we_1h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_1h_axe_weapon_pose_05` | _(unresolved: we_1h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_1h_axe_weapon_pose_06` | _(unresolved: we_1h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_1h_spears_shield_weapon_pose_01` | _(unresolved: we_1h_spears_shield_emote_wheel)_ | weapon_pose | we_maidenguard | unresolved |
| `we_1h_spears_shield_weapon_pose_02` | _(unresolved: we_1h_spears_shield_emote_wheel)_ | weapon_pose | we_maidenguard | unresolved |
| `we_1h_spears_shield_weapon_pose_03` | _(unresolved: we_1h_spears_shield_emote_wheel)_ | weapon_pose | we_maidenguard | unresolved |
| `we_1h_spears_shield_weapon_pose_04` | _(unresolved: we_1h_spears_shield_emote_wheel)_ | weapon_pose | we_maidenguard | unresolved |
| `we_1h_spears_shield_weapon_pose_05` | _(unresolved: we_1h_spears_shield_emote_wheel)_ | weapon_pose | we_maidenguard | unresolved |
| `we_1h_spears_shield_weapon_pose_06` | _(unresolved: we_1h_spears_shield_emote_wheel)_ | weapon_pose | we_maidenguard | unresolved |
| `we_1h_sword_weapon_pose_01` | _(unresolved: we_1h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_1h_sword_weapon_pose_02` | _(unresolved: we_1h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_1h_sword_weapon_pose_03` | _(unresolved: we_1h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_1h_sword_weapon_pose_04` | _(unresolved: we_1h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_1h_sword_weapon_pose_05` | _(unresolved: we_1h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_1h_sword_weapon_pose_06` | _(unresolved: we_1h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_axe_weapon_pose_01` | _(unresolved: we_2h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_axe_weapon_pose_02` | _(unresolved: we_2h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_axe_weapon_pose_03` | _(unresolved: we_2h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_axe_weapon_pose_04` | _(unresolved: we_2h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_axe_weapon_pose_05` | _(unresolved: we_2h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_axe_weapon_pose_06` | _(unresolved: we_2h_axe_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_sword_weapon_pose_01` | _(unresolved: we_2h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_sword_weapon_pose_02` | _(unresolved: we_2h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_sword_weapon_pose_03` | _(unresolved: we_2h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_sword_weapon_pose_04` | _(unresolved: we_2h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_sword_weapon_pose_05` | _(unresolved: we_2h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_2h_sword_weapon_pose_06` | _(unresolved: we_2h_sword_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_crossbow_repeater_weapon_pose_01` | _(unresolved: we_crossbow_repeater_emote_wheel)_ | weapon_pose | we_shade | unresolved |
| `we_crossbow_repeater_weapon_pose_02` | _(unresolved: we_crossbow_repeater_emote_wheel)_ | weapon_pose | we_shade | unresolved |
| `we_crossbow_repeater_weapon_pose_03` | _(unresolved: we_crossbow_repeater_emote_wheel)_ | weapon_pose | we_shade | unresolved |
| `we_crossbow_repeater_weapon_pose_04` | _(unresolved: we_crossbow_repeater_emote_wheel)_ | weapon_pose | we_shade | unresolved |
| `we_crossbow_repeater_weapon_pose_05` | _(unresolved: we_crossbow_repeater_emote_wheel)_ | weapon_pose | we_shade | unresolved |
| `we_crossbow_repeater_weapon_pose_06` | _(unresolved: we_crossbow_repeater_emote_wheel)_ | weapon_pose | we_shade | unresolved |
| `we_deus_01_weapon_pose_01` | _(unresolved: we_deus_01_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_deus_01_weapon_pose_02` | _(unresolved: we_deus_01_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_deus_01_weapon_pose_03` | _(unresolved: we_deus_01_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_deus_01_weapon_pose_04` | _(unresolved: we_deus_01_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_deus_01_weapon_pose_05` | _(unresolved: we_deus_01_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_deus_01_weapon_pose_06` | _(unresolved: we_deus_01_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_daggers_weapon_pose_01` | _(unresolved: we_dual_wield_daggers_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_daggers_weapon_pose_02` | _(unresolved: we_dual_wield_daggers_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_daggers_weapon_pose_03` | _(unresolved: we_dual_wield_daggers_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_daggers_weapon_pose_04` | _(unresolved: we_dual_wield_daggers_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_daggers_weapon_pose_05` | _(unresolved: we_dual_wield_daggers_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_daggers_weapon_pose_06` | _(unresolved: we_dual_wield_daggers_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_sword_dagger_weapon_pose_01` | _(unresolved: we_dual_wield_sword_dagger_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_sword_dagger_weapon_pose_02` | _(unresolved: we_dual_wield_sword_dagger_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_sword_dagger_weapon_pose_03` | _(unresolved: we_dual_wield_sword_dagger_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_sword_dagger_weapon_pose_04` | _(unresolved: we_dual_wield_sword_dagger_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_sword_dagger_weapon_pose_05` | _(unresolved: we_dual_wield_sword_dagger_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_sword_dagger_weapon_pose_06` | _(unresolved: we_dual_wield_sword_dagger_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_swords_weapon_pose_01` | _(unresolved: we_dual_wield_swords_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_swords_weapon_pose_02` | _(unresolved: we_dual_wield_swords_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_swords_weapon_pose_03` | _(unresolved: we_dual_wield_swords_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_swords_weapon_pose_04` | _(unresolved: we_dual_wield_swords_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_swords_weapon_pose_05` | _(unresolved: we_dual_wield_swords_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_wield_swords_weapon_pose_06` | _(unresolved: we_dual_wield_swords_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_javelin_weapon_pose_01` | _(unresolved: we_javelin_emote_wheel)_ | weapon_pose | we_thornsister, we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_javelin_weapon_pose_02` | _(unresolved: we_javelin_emote_wheel)_ | weapon_pose | we_thornsister, we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_javelin_weapon_pose_03` | _(unresolved: we_javelin_emote_wheel)_ | weapon_pose | we_thornsister, we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_javelin_weapon_pose_04` | _(unresolved: we_javelin_emote_wheel)_ | weapon_pose | we_thornsister, we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_javelin_weapon_pose_05` | _(unresolved: we_javelin_emote_wheel)_ | weapon_pose | we_thornsister, we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_javelin_weapon_pose_06` | _(unresolved: we_javelin_emote_wheel)_ | weapon_pose | we_thornsister, we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_life_staff_weapon_pose_01` | _(unresolved: we_life_staff_emote_wheel)_ | weapon_pose | we_thornsister | unresolved |
| `we_life_staff_weapon_pose_02` | _(unresolved: we_life_staff_emote_wheel)_ | weapon_pose | we_thornsister | unresolved |
| `we_life_staff_weapon_pose_03` | _(unresolved: we_life_staff_emote_wheel)_ | weapon_pose | we_thornsister | unresolved |
| `we_life_staff_weapon_pose_04` | _(unresolved: we_life_staff_emote_wheel)_ | weapon_pose | we_thornsister | unresolved |
| `we_life_staff_weapon_pose_05` | _(unresolved: we_life_staff_emote_wheel)_ | weapon_pose | we_thornsister | unresolved |
| `we_life_staff_weapon_pose_06` | _(unresolved: we_life_staff_emote_wheel)_ | weapon_pose | we_thornsister | unresolved |
| `we_longbow_weapon_pose_01` | _(unresolved: we_longbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_longbow_weapon_pose_02` | _(unresolved: we_longbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_longbow_weapon_pose_03` | _(unresolved: we_longbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_longbow_weapon_pose_04` | _(unresolved: we_longbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_longbow_weapon_pose_05` | _(unresolved: we_longbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_longbow_weapon_pose_06` | _(unresolved: we_longbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_hagbane_weapon_pose_01` | _(unresolved: we_shortbow_hagbane_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_hagbane_weapon_pose_02` | _(unresolved: we_shortbow_hagbane_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_hagbane_weapon_pose_03` | _(unresolved: we_shortbow_hagbane_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_hagbane_weapon_pose_04` | _(unresolved: we_shortbow_hagbane_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_hagbane_weapon_pose_05` | _(unresolved: we_shortbow_hagbane_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_hagbane_weapon_pose_06` | _(unresolved: we_shortbow_hagbane_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_weapon_pose_01` | _(unresolved: we_shortbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_weapon_pose_02` | _(unresolved: we_shortbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_weapon_pose_03` | _(unresolved: we_shortbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_weapon_pose_04` | _(unresolved: we_shortbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_weapon_pose_05` | _(unresolved: we_shortbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_shortbow_weapon_pose_06` | _(unresolved: we_shortbow_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_spear_weapon_pose_01` | _(unresolved: we_spear_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_spear_weapon_pose_02` | _(unresolved: we_spear_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_spear_weapon_pose_03` | _(unresolved: we_spear_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_spear_weapon_pose_04` | _(unresolved: we_spear_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_spear_weapon_pose_05` | _(unresolved: we_spear_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_spear_weapon_pose_06` | _(unresolved: we_spear_emote_wheel)_ | weapon_pose | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `weapon_pose_pack_bardin_1h_shield` | _(unresolved: weapon_pose_pack_bardin_1h_shield_name)_ | weapon_pose_bundle | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `weapon_pose_pack_bardin_2h_weapon` | _(unresolved: weapon_pose_pack_bardin_2h_weapon_name)_ | weapon_pose_bundle | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `weapon_pose_pack_bardin_crossbow` | _(unresolved: weapon_pose_pack_bardin_crossbow_name)_ | weapon_pose_bundle | dr_ironbreaker, dr_ranger | unresolved |
| `weapon_pose_pack_bardin_dual_wield` | _(unresolved: weapon_pose_pack_bardin_dual_wield_name)_ | weapon_pose_bundle | dr_ironbreaker, dr_slayer, dr_ranger, dr_engineer | unresolved |
| `weapon_pose_pack_bardin_rifle` | _(unresolved: weapon_pose_pack_bardin_rifle_name)_ | weapon_pose_bundle | dr_ironbreaker, dr_ranger, dr_engineer | unresolved |
| `weapon_pose_pack_bardin_steam_pistol` | _(unresolved: weapon_pose_pack_bardin_steam_pistol_name)_ | weapon_pose_bundle | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `weapon_pose_pack_kerillian_2h_glaive` | _(unresolved: weapon_pose_pack_kerillian_2h_glaive_name)_ | weapon_pose_bundle | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `weapon_pose_pack_kerillian_bow` | _(unresolved: weapon_pose_pack_kerillian_bow_name)_ | weapon_pose_bundle | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `weapon_pose_pack_kerillian_dual_wield` | _(unresolved: weapon_pose_pack_kerillian_dual_wield_name)_ | weapon_pose_bundle | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `weapon_pose_pack_kerillian_life_staff` | _(unresolved: weapon_pose_pack_kerillian_life_staff_name)_ | weapon_pose_bundle | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `weapon_pose_pack_kerillian_spear` | _(unresolved: weapon_pose_pack_kerillian_spear_name)_ | weapon_pose_bundle | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `weapon_pose_pack_kerillian_spear_shield` | _(unresolved: weapon_pose_pack_kerillian_spear_shield_name)_ | weapon_pose_bundle | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `weapon_pose_pack_kruber_1h_shield` | _(unresolved: weapon_pose_pack_kruber_1h_shield_name)_ | weapon_pose_bundle | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `weapon_pose_pack_kruber_2h_hammer` | _(unresolved: weapon_pose_pack_kruber_2h_hammer_name)_ | weapon_pose_bundle | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `weapon_pose_pack_kruber_2h_sword` | _(unresolved: weapon_pose_pack_kruber_2h_sword_name)_ | weapon_pose_bundle | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `weapon_pose_pack_kruber_bastard_sword` | _(unresolved: weapon_pose_pack_kruber_bastard_sword_name)_ | weapon_pose_bundle | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `weapon_pose_pack_kruber_handgun` | _(unresolved: weapon_pose_pack_kruber_handgun_name)_ | weapon_pose_bundle | es_huntsman, es_knight, es_mercenary | unresolved |
| `weapon_pose_pack_kruber_shotgun` | _(unresolved: weapon_pose_pack_kruber_shotgun_name)_ | weapon_pose_bundle | es_huntsman, es_knight, es_mercenary | unresolved |
| `weapon_pose_pack_saltzpyre_1h_weapon` | _(unresolved: weapon_pose_pack_saltzpyre_1h_weapon_name)_ | weapon_pose_bundle | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `weapon_pose_pack_saltzpyre_brace_of_pistols` | _(unresolved: weapon_pose_pack_saltzpyre_brace_of_pistols_name)_ | weapon_pose_bundle | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `weapon_pose_pack_saltzpyre_crossbow` | _(unresolved: weapon_pose_pack_saltzpyre_crossbow_name)_ | weapon_pose_bundle | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `weapon_pose_pack_saltzpyre_dual_wield` | _(unresolved: weapon_pose_pack_saltzpyre_dual_wield_name)_ | weapon_pose_bundle | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `weapon_pose_pack_saltzpyre_dual_wield_hammers` | _(unresolved: weapon_pose_pack_saltzpyre_dual_wield_hammer_name)_ | weapon_pose_bundle | wh_priest, wh_zealot | unresolved |
| `weapon_pose_pack_saltzpyre_fencing_sword` | _(unresolved: weapon_pose_pack_saltzpyre_fencing_sword_name)_ | weapon_pose_bundle | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `weapon_pose_pack_sienna_1h` | _(unresolved: weapon_pose_pack_sienna_1h_name)_ | weapon_pose_bundle | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `weapon_pose_pack_sienna_1h_dagger` | _(unresolved: weapon_pose_pack_sienna_1h_dagger_name)_ | weapon_pose_bundle | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `weapon_pose_pack_sienna_1h_mace` | _(unresolved: weapon_pose_pack_sienna_1h_mace_name)_ | weapon_pose_bundle | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `weapon_pose_pack_sienna_1h_spells` | _(unresolved: weapon_pose_pack_sienna_1h_spells_name)_ | weapon_pose_bundle | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `weapon_pose_pack_sienna_ghost_scythe` | _(unresolved: weapon_pose_pack_sienna_ghost_scythe_name)_ | weapon_pose_bundle | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `weapon_pose_pack_sienna_staff_a` | _(unresolved: weapon_pose_pack_sienna_staff_a_name)_ | weapon_pose_bundle | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `wh_1h_axe_weapon_pose_01` | _(unresolved: wh_1h_axe_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_weapon_pose_02` | _(unresolved: wh_1h_axe_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_weapon_pose_03` | _(unresolved: wh_1h_axe_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_weapon_pose_04` | _(unresolved: wh_1h_axe_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_weapon_pose_05` | _(unresolved: wh_1h_axe_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_weapon_pose_06` | _(unresolved: wh_1h_axe_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_weapon_pose_01` | _(unresolved: wh_1h_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_weapon_pose_02` | _(unresolved: wh_1h_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_weapon_pose_03` | _(unresolved: wh_1h_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_weapon_pose_04` | _(unresolved: wh_1h_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_weapon_pose_05` | _(unresolved: wh_1h_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_weapon_pose_06` | _(unresolved: wh_1h_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_hammer_weapon_pose_01` | _(unresolved: wh_1h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_weapon_pose_02` | _(unresolved: wh_1h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_weapon_pose_03` | _(unresolved: wh_1h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_weapon_pose_04` | _(unresolved: wh_1h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_weapon_pose_05` | _(unresolved: wh_1h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_weapon_pose_06` | _(unresolved: wh_1h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_2h_billhook_weapon_pose_01` | _(unresolved: wh_2h_billhook_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_billhook_weapon_pose_02` | _(unresolved: wh_2h_billhook_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_billhook_weapon_pose_03` | _(unresolved: wh_2h_billhook_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_billhook_weapon_pose_04` | _(unresolved: wh_2h_billhook_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_billhook_weapon_pose_05` | _(unresolved: wh_2h_billhook_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_billhook_weapon_pose_06` | _(unresolved: wh_2h_billhook_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_hammer_weapon_pose_01` | _(unresolved: wh_2h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_weapon_pose_02` | _(unresolved: wh_2h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_weapon_pose_03` | _(unresolved: wh_2h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_weapon_pose_04` | _(unresolved: wh_2h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_weapon_pose_05` | _(unresolved: wh_2h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_weapon_pose_06` | _(unresolved: wh_2h_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_2h_sword_weapon_pose_01` | _(unresolved: wh_2h_sword_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_weapon_pose_02` | _(unresolved: wh_2h_sword_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_weapon_pose_03` | _(unresolved: wh_2h_sword_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_weapon_pose_04` | _(unresolved: wh_2h_sword_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_weapon_pose_05` | _(unresolved: wh_2h_sword_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_weapon_pose_06` | _(unresolved: wh_2h_sword_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_weapon_pose_01` | _(unresolved: wh_brace_of_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_weapon_pose_02` | _(unresolved: wh_brace_of_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_weapon_pose_03` | _(unresolved: wh_brace_of_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_weapon_pose_04` | _(unresolved: wh_brace_of_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_weapon_pose_05` | _(unresolved: wh_brace_of_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_weapon_pose_06` | _(unresolved: wh_brace_of_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_repeater_weapon_pose_01` | _(unresolved: wh_crossbow_repeater_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_repeater_weapon_pose_02` | _(unresolved: wh_crossbow_repeater_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_repeater_weapon_pose_03` | _(unresolved: wh_crossbow_repeater_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_repeater_weapon_pose_04` | _(unresolved: wh_crossbow_repeater_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_repeater_weapon_pose_05` | _(unresolved: wh_crossbow_repeater_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_repeater_weapon_pose_06` | _(unresolved: wh_crossbow_repeater_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_weapon_pose_01` | _(unresolved: wh_crossbow_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_weapon_pose_02` | _(unresolved: wh_crossbow_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_weapon_pose_03` | _(unresolved: wh_crossbow_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_weapon_pose_04` | _(unresolved: wh_crossbow_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_weapon_pose_05` | _(unresolved: wh_crossbow_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_weapon_pose_06` | _(unresolved: wh_crossbow_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_deus_01_weapon_pose_01` | _(unresolved: wh_deus_01_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_deus_01_weapon_pose_02` | _(unresolved: wh_deus_01_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_deus_01_weapon_pose_03` | _(unresolved: wh_deus_01_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_deus_01_weapon_pose_04` | _(unresolved: wh_deus_01_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_deus_01_weapon_pose_05` | _(unresolved: wh_deus_01_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_deus_01_weapon_pose_06` | _(unresolved: wh_deus_01_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_dual_hammer_weapon_pose_01` | _(unresolved: wh_dual_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_weapon_pose_02` | _(unresolved: wh_dual_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_weapon_pose_03` | _(unresolved: wh_dual_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_weapon_pose_04` | _(unresolved: wh_dual_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_weapon_pose_05` | _(unresolved: wh_dual_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_weapon_pose_06` | _(unresolved: wh_dual_hammer_emote_wheel)_ | weapon_pose | wh_priest, wh_zealot | unresolved |
| `wh_dual_wield_axe_falchion_weapon_pose_01` | _(unresolved: wh_dual_wield_axe_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_wield_axe_falchion_weapon_pose_02` | _(unresolved: wh_dual_wield_axe_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_wield_axe_falchion_weapon_pose_03` | _(unresolved: wh_dual_wield_axe_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_wield_axe_falchion_weapon_pose_04` | _(unresolved: wh_dual_wield_axe_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_wield_axe_falchion_weapon_pose_05` | _(unresolved: wh_dual_wield_axe_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_wield_axe_falchion_weapon_pose_06` | _(unresolved: wh_dual_wield_axe_falchion_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_fencing_sword_weapon_pose_01` | _(unresolved: wh_fencing_sword_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_weapon_pose_02` | _(unresolved: wh_fencing_sword_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_weapon_pose_03` | _(unresolved: wh_fencing_sword_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_weapon_pose_04` | _(unresolved: wh_fencing_sword_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_weapon_pose_05` | _(unresolved: wh_fencing_sword_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_weapon_pose_06` | _(unresolved: wh_fencing_sword_emote_wheel)_ | weapon_pose | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_flail_shield_weapon_pose_01` | _(unresolved: wh_flail_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_flail_shield_weapon_pose_02` | _(unresolved: wh_flail_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_flail_shield_weapon_pose_03` | _(unresolved: wh_flail_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_flail_shield_weapon_pose_04` | _(unresolved: wh_flail_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_flail_shield_weapon_pose_05` | _(unresolved: wh_flail_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_flail_shield_weapon_pose_06` | _(unresolved: wh_flail_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_book_weapon_pose_01` | _(unresolved: wh_hammer_book_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_book_weapon_pose_02` | _(unresolved: wh_hammer_book_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_book_weapon_pose_03` | _(unresolved: wh_hammer_book_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_book_weapon_pose_04` | _(unresolved: wh_hammer_book_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_book_weapon_pose_05` | _(unresolved: wh_hammer_book_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_book_weapon_pose_06` | _(unresolved: wh_hammer_book_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_shield_weapon_pose_01` | _(unresolved: wh_hammer_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_shield_weapon_pose_02` | _(unresolved: wh_hammer_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_shield_weapon_pose_03` | _(unresolved: wh_hammer_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_shield_weapon_pose_04` | _(unresolved: wh_hammer_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_shield_weapon_pose_05` | _(unresolved: wh_hammer_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_hammer_shield_weapon_pose_06` | _(unresolved: wh_hammer_shield_emote_wheel)_ | weapon_pose | wh_priest | unresolved |
| `wh_repeating_pistols_weapon_pose_01` | _(unresolved: wh_repeating_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistols_weapon_pose_02` | _(unresolved: wh_repeating_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistols_weapon_pose_03` | _(unresolved: wh_repeating_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistols_weapon_pose_04` | _(unresolved: wh_repeating_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistols_weapon_pose_05` | _(unresolved: wh_repeating_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistols_weapon_pose_06` | _(unresolved: wh_repeating_pistols_emote_wheel)_ | weapon_pose | wh_zealot, wh_bountyhunter, wh_captain | unresolved |

### kind: weapon_skin (948 entries, 948 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `bw_1h_crowbill_skin` | _(unresolved: )_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_crowbill_skin_01` | _(unresolved: bw_1h_crowbill_skin_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_crowbill_skin_01_magic_01` | _(unresolved: bw_1h_crowbill_skin_01_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_crowbill_skin_01_magic_02` | _(unresolved: bw_1h_crowbill_skin_01_magic_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_crowbill_skin_02` | _(unresolved: bw_1h_crowbill_skin_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_crowbill_skin_02_runed_01` | _(unresolved: bw_1h_crowbill_skin_02_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flail_flaming_skin` | _(unresolved: )_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flail_flaming_skin_01` | _(unresolved: bw_1h_flail_flaming_skin_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flail_flaming_skin_01_runed_01` | _(unresolved: bw_1h_flail_flaming_skin_01_runed_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flail_flaming_skin_01_runed_05` | _(unresolved: )_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flail_flaming_skin_02` | _(unresolved: bw_1h_flail_flaming_skin_02_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flail_flaming_skin_02_magic_01` | _(unresolved: bw_1h_flail_flaming_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flail_flaming_skin_02_magic_02` | _(unresolved: bw_1h_flail_flaming_skin_02_magic_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_01` | _(unresolved: bw_1h_flaming_sword_skin_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_01_runed_01` | _(unresolved: bw_1h_flaming_sword_skin_01_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_01_runed_03` | _(unresolved: bw_1h_flaming_sword_skin_01_runed_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_01_runed_05` | _(unresolved: bw_1h_flaming_sword_skin_01_runed_05_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_01_runed_06` | _(unresolved: bw_1h_flaming_sword_skin_01_runed_06_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_02` | _(unresolved: bw_1h_flaming_sword_skin_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_02_runed_01` | _(unresolved: bw_1h_flaming_sword_skin_02_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_02_runed_02` | _(unresolved: bw_1h_flaming_sword_skin_02_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_03` | _(unresolved: bw_1h_flaming_sword_skin_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_04` | _(unresolved: bw_1h_flaming_sword_skin_04_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_05` | _(unresolved: bw_1h_flaming_sword_skin_05_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_06` | _(unresolved: bw_1h_flaming_sword_skin_06_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_06_magic_01` | _(unresolved: bw_1h_flaming_sword_skin_06_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_06_magic_02` | _(unresolved: bw_1h_flaming_sword_skin_06_magic_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_07` | _(unresolved: bw_1h_flaming_sword_skin_07_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_flaming_sword_skin_08` | _(unresolved: bw_1h_flaming_sword_skin_08_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_skin` | _(unresolved: )_ | weapon_skin | bw_unchained, bw_adept, bw_scholar | unresolved |
| `bw_1h_mace_skin_01` | _(unresolved: bw_1h_mace_skin_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_skin_01_runed_01` | _(unresolved: bw_1h_mace_skin_01_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_skin_02` | _(unresolved: bw_1h_mace_skin_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_skin_02_magic_01` | _(unresolved: bw_1h_mace_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_skin_02_magic_02` | _(unresolved: bw_1h_mace_skin_02_magic_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_skin_03` | _(unresolved: bw_1h_mace_skin_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_skin_04` | _(unresolved: bw_1h_mace_skin_04_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_skin_05` | _(unresolved: bw_1h_mace_skin_05_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_skin_05_runed_01` | _(unresolved: bw_1h_mace_skin_05_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_skin_05_runed_02` | _(unresolved: bw_1h_mace_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_mace_skin_05_runed_06` | _(unresolved: bw_1h_mace_skin_05_runed_06_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_01` | _(unresolved: bw_1h_sword_skin_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_01_runed_01` | _(unresolved: bw_1h_sword_skin_01_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_01_runed_05` | _(unresolved: bw_1h_sword_skin_01_runed_05_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_02` | _(unresolved: bw_1h_sword_skin_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_02_runed_01` | _(unresolved: bw_1h_sword_skin_02_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_02_runed_02` | _(unresolved: bw_1h_sword_skin_02_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_02_runed_03` | _(unresolved: )_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_02_runed_06` | _(unresolved: )_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_03` | _(unresolved: bw_1h_sword_skin_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_04` | _(unresolved: bw_1h_sword_skin_04_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_05` | _(unresolved: bw_1h_sword_skin_05_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_06` | _(unresolved: bw_1h_sword_skin_06_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_06_magic_01` | _(unresolved: bw_1h_sword_skin_06_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_06_magic_02` | _(unresolved: bw_1h_sword_skin_06_magic_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_07` | _(unresolved: bw_1h_sword_skin_07_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_1h_sword_skin_08` | _(unresolved: bw_1h_sword_skin_08_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_01` | _(unresolved: bw_beam_staff_skin_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_02` | _(unresolved: bw_beam_staff_skin_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_02_magic_01` | _(unresolved: bw_beam_staff_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_02_magic_02` | _(unresolved: bw_beam_staff_skin_02_magic_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_03` | _(unresolved: bw_beam_staff_skin_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_04` | _(unresolved: bw_beam_staff_skin_04_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_04_runed_01` | _(unresolved: bw_beam_staff_skin_04_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_04_runed_05` | _(unresolved: bw_beam_staff_skin_04_runed_05_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_04_runed_06` | _(unresolved: )_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_05` | _(unresolved: bw_beam_staff_skin_05_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_05_runed_01` | _(unresolved: bw_beam_staff_skin_05_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_05_runed_02` | _(unresolved: bw_beam_staff_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_beam_staff_skin_05_runed_04` | _(unresolved: bw_beam_staff_skin_05_runed_04_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_conflagration_staff_skin_01` | _(unresolved: bw_conflagration_staff_skin_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_conflagration_staff_skin_01_magic_01` | _(unresolved: bw_conflagration_staff_skin_01_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_conflagration_staff_skin_01_magic_02` | _(unresolved: bw_conflagration_staff_skin_01_magic_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_conflagration_staff_skin_02` | _(unresolved: bw_conflagration_staff_skin_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_conflagration_staff_skin_02_runed_01` | _(unresolved: bw_conflagration_staff_skin_02_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_conflagration_staff_skin_02_runed_02` | _(unresolved: bw_conflagration_staff_skin_02_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_conflagration_staff_skin_02_runed_03` | _(unresolved: bw_conflagration_staff_skin_02_runed_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_conflagration_staff_skin_02_runed_06` | _(unresolved: bw_conflagration_staff_skin_02_runed_06_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin` | _(unresolved: )_ | weapon_skin | bw_unchained, bw_adept, bw_scholar | unresolved |
| `bw_dagger_skin_01` | _(unresolved: bw_dagger_skin_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_02` | _(unresolved: bw_dagger_skin_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_02_magic_01` | _(unresolved: bw_dagger_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_02_magic_02` | _(unresolved: bw_dagger_skin_02_magic_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_03` | _(unresolved: bw_dagger_skin_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_03_runed_01` | _(unresolved: bw_dagger_skin_03_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_03_runed_06` | _(unresolved: )_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_04` | _(unresolved: bw_dagger_skin_04_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_04_runed_01` | _(unresolved: bw_dagger_skin_04_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_04_runed_03` | _(unresolved: bw_dagger_skin_04_runed_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_05` | _(unresolved: bw_dagger_skin_05_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_05_runed_01` | _(unresolved: bw_dagger_skin_05_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_05_runed_02` | _(unresolved: bw_dagger_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_dagger_skin_05_runed_04` | _(unresolved: )_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_deus_01_skin_02_runed_05` | _(unresolved: bw_deus_01_skin_02_runed_05_name)_ _(dlc:grass)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_deus_skin_02_magic_02` | _(unresolved: bw_deus_skin_02_magic_02_name)_ _(dlc:grass)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_fireball_staff_skin_01` | _(unresolved: bw_fireball_staff_skin_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_fireball_staff_skin_01_runed_01` | _(unresolved: bw_fireball_staff_skin_01_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_fireball_staff_skin_01_runed_02` | _(unresolved: bw_fireball_staff_skin_01_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_fireball_staff_skin_01_runed_03` | _(unresolved: bw_fireball_staff_skin_01_runed_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_fireball_staff_skin_01_runed_04` | _(unresolved: bw_fireball_staff_skin_01_runed_04_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_fireball_staff_skin_01_runed_06` | _(unresolved: )_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_fireball_staff_skin_02` | _(unresolved: bw_fireball_staff_skin_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_fireball_staff_skin_02_magic_01` | _(unresolved: bw_fireball_staff_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_fireball_staff_skin_02_magic_02` | _(unresolved: bw_fireball_staff_skin_02_magic_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flame_sword_skin` | _(unresolved: )_ | weapon_skin | bw_unchained, bw_adept, bw_scholar | unresolved |
| `bw_flamethrower_staff_skin_01` | _(unresolved: bw_flamethrower_staff_skin_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flamethrower_staff_skin_02` | _(unresolved: bw_flamethrower_staff_skin_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flamethrower_staff_skin_02_runed_01` | _(unresolved: bw_flamethrower_staff_skin_02_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flamethrower_staff_skin_02_runed_04` | _(unresolved: bw_flamethrower_staff_skin_02_runed_04_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flamethrower_staff_skin_03` | _(unresolved: bw_flamethrower_staff_skin_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flamethrower_staff_skin_04` | _(unresolved: bw_flamethrower_staff_skin_04_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flamethrower_staff_skin_04_magic_01` | _(unresolved: bw_flamethrower_staff_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flamethrower_staff_skin_04_magic_02` | _(unresolved: bw_flamethrower_staff_skin_04_magic_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flamethrower_staff_skin_05` | _(unresolved: bw_flamethrower_staff_skin_05_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flamethrower_staff_skin_05_runed_01` | _(unresolved: bw_flamethrower_staff_skin_05_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flamethrower_staff_skin_05_runed_02` | _(unresolved: bw_flamethrower_staff_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_flamethrower_staff_skin_05_runed_06` | _(unresolved: bw_flamethrower_staff_skin_05_runed_06_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_ghost_scythe_skin` | _(unresolved: )_ | weapon_skin | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_ghost_scythe_skin_01` | _(unresolved: bw_ghost_scythe_skin_01_name)_ _(dlc:shovel)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_ghost_scythe_skin_01_runed_01` | _(unresolved: bw_ghost_scythe_skin_01_runed_01_name)_ _(dlc:shovel_upgrade)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_ghost_scythe_skin_01_runed_02` | _(unresolved: bw_ghost_scythe_skin_01_runed_02_name)_ _(dlc:shovel_upgrade)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_ghost_scythe_skin_02` | _(unresolved: bw_ghost_scythe_skin_02_name)_ _(dlc:shovel_upgrade)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_ghost_scythe_skin_02_magic_01` | _(unresolved: bw_ghost_scythe_skin_02_magic_01_name)_ _(dlc:shovel)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_ghost_scythe_skin_02_magic_02` | _(unresolved: bw_ghost_scythe_skin_02_magic_02_name)_ _(dlc:shovel)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_ghost_scythe_skin_02_runed_01` | _(unresolved: bw_ghost_scythe_skin_02_runed_01_name)_ _(dlc:shovel_upgrade)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_ghost_scythe_skin_02_runed_02` | _(unresolved: bw_ghost_scythe_skin_02_runed_02_name)_ _(dlc:shovel_upgrade)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_ghost_scythe_skin_02_runed_05` | _(unresolved: bw_ghost_scythe_skin_02_runed_05_name)_ _(dlc:shovel)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_ghost_scythe_skin_magic_01` | _(unresolved: bw_ghost_scythe_skin_02_magic_01_name)_ _(dlc:shovel)_ | bw_ghost_scythe | bw_scholar, bw_adept, bw_unchained, bw_necromancer | unresolved |
| `bw_necromancy_staff_skin` | _(unresolved: )_ | weapon_skin | bw_necromancer | unresolved |
| `bw_necromancy_staff_skin_01` | _(unresolved: bw_necromancy_staff_skin_01_name)_ _(dlc:shovel)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_necromancy_staff_skin_01_runed_01` | _(unresolved: bw_necromancy_staff_skin_01_runed_01_name)_ _(dlc:shovel_upgrade)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_necromancy_staff_skin_01_runed_02` | _(unresolved: bw_necromancy_staff_skin_01_runed_02_name)_ _(dlc:shovel_upgrade)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_necromancy_staff_skin_02` | _(unresolved: bw_necromancy_staff_skin_02_name)_ _(dlc:shovel_upgrade)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_necromancy_staff_skin_02_magic_01` | _(unresolved: bw_necromancy_staff_skin_02_magic_01_name)_ _(dlc:shovel)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_necromancy_staff_skin_02_magic_02` | _(unresolved: bw_necromancy_staff_skin_02_magic_02_name)_ _(dlc:shovel)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_necromancy_staff_skin_02_runed_01` | _(unresolved: bw_necromancy_staff_skin_02_runed_01_name)_ _(dlc:shovel_upgrade)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_necromancy_staff_skin_02_runed_02` | _(unresolved: bw_necromancy_staff_skin_02_runed_02_name)_ _(dlc:shovel_upgrade)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_necromancy_staff_skin_02_runed_05` | _(unresolved: bw_necromancy_staff_skin_02_runed_05_name)_ _(dlc:shovel)_ | weapon_skin | bw_necromancer | unresolved |
| `bw_skullstaff_beam_skin` | _(unresolved: )_ | weapon_skin | bw_unchained, bw_adept, bw_scholar | unresolved |
| `bw_skullstaff_fireball_skin` | _(unresolved: )_ | weapon_skin | bw_unchained, bw_adept, bw_scholar | unresolved |
| `bw_skullstaff_flamethrower_skin` | _(unresolved: )_ | weapon_skin | bw_unchained, bw_adept, bw_scholar | unresolved |
| `bw_skullstaff_geiser_skin` | _(unresolved: )_ | weapon_skin | bw_unchained, bw_adept, bw_scholar | unresolved |
| `bw_skullstaff_spear_skin` | _(unresolved: )_ | weapon_skin | bw_unchained, bw_adept, bw_scholar | unresolved |
| `bw_spear_staff_skin_01` | _(unresolved: bw_spear_staff_skin_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_02` | _(unresolved: bw_spear_staff_skin_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_02_runed_01` | _(unresolved: bw_spear_staff_skin_02_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_02_runed_05` | _(unresolved: )_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_03` | _(unresolved: bw_spear_staff_skin_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_04` | _(unresolved: bw_spear_staff_skin_04_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_04_runed_01` | _(unresolved: bw_spear_staff_skin_04_runed_01_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_04_runed_02` | _(unresolved: bw_spear_staff_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_04_runed_03` | _(unresolved: bw_spear_staff_skin_04_runed_03_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_04_runed_06` | _(unresolved: bw_spear_staff_skin_04_runed_06_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_05` | _(unresolved: bw_spear_staff_skin_05_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_05_magic_01` | _(unresolved: bw_spear_staff_skin_05_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_spear_staff_skin_05_magic_02` | _(unresolved: bw_spear_staff_skin_05_magic_02_name)_ | weapon_skin | bw_scholar, bw_adept, bw_unchained | unresolved |
| `bw_sword_skin` | _(unresolved: )_ | weapon_skin | bw_unchained, bw_adept, bw_scholar | unresolved |
| `dr_1h_axe_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_1h_hammer_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_skin_01` | _(unresolved: dr_1h_throwing_axes_skin_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_skin_01_runed_01` | _(unresolved: dr_1h_throwing_axes_skin_01_runed_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_skin_01_runed_05` | _(unresolved: )_ _(dlc:scorpion)_ | weapon_skin | dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_skin_02` | _(unresolved: dr_1h_throwing_axes_skin_02_name)_ _(dlc:scorpion)_ | weapon_skin | dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_skin_02_magic_01` | _(unresolved: dr_1h_throwing_axes_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_slayer, dr_ranger | unresolved |
| `dr_1h_throwing_axes_skin_02_magic_02` | _(unresolved: dr_1h_throwing_axes_skin_02_magic_02_name)_ | weapon_skin | dr_slayer, dr_ranger | unresolved |
| `dr_2h_axe_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_2h_cog_hammer_skin` | _(unresolved: )_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_skin_01` | _(unresolved: dr_cog_hammer_skin_01_name)_ _(dlc:cog_upgrade)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_skin_01_runed_01` | _(unresolved: dr_cog_hammer_skin_01_runed_01_name)_ _(dlc:cog_upgrade)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_skin_01_runed_02` | _(unresolved: dr_cog_hammer_skin_01_runed_02_name)_ _(dlc:cog_upgrade)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_skin_02` | _(unresolved: dr_cog_hammer_skin_02_name)_ _(dlc:cog_upgrade)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_skin_02_magic_01` | _(unresolved: dr_cog_hammer_skin_02_magic_01_name)_ _(dlc:cog)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_skin_02_magic_02` | _(unresolved: dr_2h_cog_hammer_skin_02_magic_02_name)_ _(dlc:cog)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_skin_02_runed_01` | _(unresolved: dr_cog_hammer_skin_02_runed_01_name)_ _(dlc:cog_upgrade)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_skin_02_runed_02` | _(unresolved: dr_steam_pistol_skin_02_runed_02_name)_ _(dlc:cog_upgrade)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_cog_hammer_skin_02_runed_05` | _(unresolved: dr_2h_cog_hammer_skin_02_runed_05_name)_ _(dlc:cog)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker, dr_slayer | unresolved |
| `dr_2h_hammer_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_2h_pick_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_crossbow_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_deus_01_skin_03_runed_05` | _(unresolved: dr_deus_01_skin_03_runed_05_name)_ _(dlc:grass)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dr_deus_skin_02_magic_02` | _(unresolved: dr_deus_skin_02_magic_02_name)_ _(dlc:grass)_ | weapon_skin | dr_ironbreaker, dr_engineer | unresolved |
| `dr_drake_pistol_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_drakegun_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_dual_wield_axes_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_dual_wield_hammers_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_dual_wield_hammers_skin_01` | _(unresolved: dr_dual_wield_hammers_skin_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_dual_wield_hammers_skin_01_magic_01` | _(unresolved: dr_dual_wield_hammers_skin_01_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_dual_wield_hammers_skin_01_magic_02` | _(unresolved: dr_dual_wield_hammers_skin_01_magic_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_dual_wield_hammers_skin_02` | _(unresolved: dr_dual_wield_hammers_skin_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_dual_wield_hammers_skin_02_runed_01` | _(unresolved: dr_dual_wield_hammers_skin_02_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_handgun_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_rakegun_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_shield_axe_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_shield_hammer_skin` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dr_steam_pistol_01_t2_magic_01` | _(unresolved: dr_steam_pistol_skin_01_magic_01_name)_ _(dlc:cog)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_skin` | _(unresolved: )_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_skin_01` | _(unresolved: dr_steam_pistol_skin_01_name)_ _(dlc:cog)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_skin_01_runed_01` | _(unresolved: dr_steam_pistol_skin_01_runed_01_name)_ _(dlc:cog_upgrade)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_skin_01_runed_02` | _(unresolved: dr_steam_pistol_skin_01_runed_02_name)_ _(dlc:cog_upgrade)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_skin_02` | _(unresolved: dr_steam_pistol_skin_02_name)_ _(dlc:cog_upgrade)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_skin_02_magic_02` | _(unresolved: dr_steam_pistol_skin_02_magic_02_name)_ _(dlc:cog)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_skin_02_runed_01` | _(unresolved: dr_steam_pistol_skin_02_runed_01_name)_ _(dlc:cog_upgrade)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_skin_02_runed_02` | _(unresolved: dr_steam_pistol_skin_02_runed_02_name)_ _(dlc:cog_upgrade)_ | weapon_skin | dr_engineer, dr_ranger, dr_ironbreaker | unresolved |
| `dr_steam_pistol_skin_02_runed_05` | _(unresolved: dr_steam_pistol_skin_02_runed_05_name)_ _(dlc:cog)_ | weapon_skin | dr_engineer, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_01` | _(unresolved: dw_1h_axe_shield_skin_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_02` | _(unresolved: dw_1h_axe_shield_skin_02_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_02_runed_01` | _(unresolved: dw_1h_axe_shield_skin_02_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_02_runed_06` | _(unresolved: dw_1h_axe_shield_skin_02_runed_06_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_03` | _(unresolved: dw_1h_axe_shield_skin_03_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_04` | _(unresolved: dw_1h_axe_shield_skin_04_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_04_magic_01` | _(unresolved: dw_1h_axe_shield_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_04_magic_02` | _(unresolved: dw_1h_axe_shield_skin_04_magic_02_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_05` | _(unresolved: dw_1h_axe_shield_skin_05_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_05_runed_01` | _(unresolved: dw_1h_axe_shield_skin_05_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_05_runed_02` | _(unresolved: dw_1h_axe_shield_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_shield_skin_05_runed_03` | _(unresolved: dw_1h_axe_shield_skin_05_runed_03_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_axe_skin_01` | _(unresolved: dw_1h_axe_skin_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_02` | _(unresolved: dw_1h_axe_skin_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_03` | _(unresolved: dw_1h_axe_skin_03_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_04` | _(unresolved: dw_1h_axe_skin_04_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_04_magic_01` | _(unresolved: dw_1h_axe_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_04_magic_02` | _(unresolved: dw_1h_axe_skin_04_magic_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_05` | _(unresolved: dw_1h_axe_skin_05_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_06` | _(unresolved: dw_1h_axe_skin_06_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_06_runed_01` | _(unresolved: dw_1h_axe_skin_06_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_06_runed_02` | _(unresolved: dw_1h_axe_skin_06_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_07` | _(unresolved: dw_1h_axe_skin_07_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_07_runed_01` | _(unresolved: dw_1h_axe_skin_07_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_axe_skin_07_runed_06` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_01` | _(unresolved: dw_1h_hammer_shield_skin_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_02` | _(unresolved: dw_1h_hammer_shield_skin_02_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_02_runed_01` | _(unresolved: dw_1h_hammer_shield_skin_02_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_02_runed_06` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_03` | _(unresolved: dw_1h_hammer_shield_skin_03_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_04` | _(unresolved: dw_1h_hammer_shield_skin_04_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_04_magic_01` | _(unresolved: dw_1h_hammer_shield_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_04_magic_02` | _(unresolved: dw_1h_hammer_shield_skin_04_magic_02_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_04_runed_01` | _(unresolved: dw_1h_hammer_shield_skin_04_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_04_runed_02` | _(unresolved: dw_1h_hammer_shield_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_04_runed_05` | _(unresolved: dw_1h_hammer_shield_skin_04_runed_05_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_shield_skin_05` | _(unresolved: dw_1h_hammer_shield_skin_05_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_1h_hammer_skin_01` | _(unresolved: dw_1h_hammer_skin_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_skin_02` | _(unresolved: dw_1h_hammer_skin_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_skin_02_runed_01` | _(unresolved: dw_1h_hammer_skin_02_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_skin_02_runed_06` | _(unresolved: dw_1h_hammer_skin_02_runed_06_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_skin_03` | _(unresolved: dw_1h_hammer_skin_03_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_skin_03_magic_01` | _(unresolved: dw_1h_hammer_skin_03_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_skin_03_magic_02` | _(unresolved: dw_1h_hammer_skin_03_magic_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_skin_04` | _(unresolved: dw_1h_hammer_skin_04_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_skin_04_runed_01` | _(unresolved: dw_1h_hammer_skin_04_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_skin_04_runed_02` | _(unresolved: dw_1h_hammer_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_skin_05` | _(unresolved: dw_1h_hammer_skin_05_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_1h_hammer_skin_06` | _(unresolved: dw_1h_hammer_skin_06_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_01` | _(unresolved: dw_2h_axe_skin_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_02` | _(unresolved: dw_2h_axe_skin_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_02_magic_01` | _(unresolved: dw_2h_axe_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_02_magic_02` | _(unresolved: dw_2h_axe_skin_02_magic_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_03` | _(unresolved: dw_2h_axe_skin_03_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_04` | _(unresolved: dw_2h_axe_skin_04_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_05` | _(unresolved: dw_2h_axe_skin_05_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_05_runed_01` | _(unresolved: dw_2h_axe_skin_05_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_05_runed_03` | _(unresolved: dw_2h_axe_skin_05_runed_03_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_06` | _(unresolved: dw_2h_axe_skin_06_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_06_runed_01` | _(unresolved: dw_2h_axe_skin_06_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_06_runed_02` | _(unresolved: dw_2h_axe_skin_06_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_06_runed_05` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_axe_skin_06_runed_06` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_01` | _(unresolved: dw_2h_hammer_skin_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_01_runed_01` | _(unresolved: dw_2h_hammer_skin_01_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_01_runed_05` | _(unresolved: dw_2h_hammer_skin_01_runed_05_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_02` | _(unresolved: dw_2h_hammer_skin_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_03` | _(unresolved: dw_2h_hammer_skin_03_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_03_magic_01` | _(unresolved: dw_2h_hammer_skin_03_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_03_magic_02` | _(unresolved: dw_2h_hammer_skin_03_magic_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_04` | _(unresolved: dw_2h_hammer_skin_04_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_04_runed_01` | _(unresolved: dw_2h_hammer_skin_04_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_04_runed_02` | _(unresolved: dw_2h_hammer_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_04_runed_06` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_05` | _(unresolved: dw_2h_hammer_skin_05_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_hammer_skin_06` | _(unresolved: dw_2h_hammer_skin_06_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_pick_skin_01` | _(unresolved: dw_2h_pick_skin_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_pick_skin_02` | _(unresolved: dw_2h_pick_skin_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_pick_skin_02_magic_01` | _(unresolved: dw_2h_pick_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_pick_skin_02_magic_02` | _(unresolved: dw_2h_pick_skin_02_magic_02_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_pick_skin_03` | _(unresolved: dw_2h_pick_skin_03_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_pick_skin_03_runed_01` | _(unresolved: dw_2h_pick_skin_03_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_pick_skin_03_runed_06` | _(unresolved: dw_2h_pick_skin_03_runed_06_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_pick_skin_04` | _(unresolved: dw_2h_pick_skin_04_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_pick_skin_04_runed_01` | _(unresolved: dw_2h_pick_skin_04_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_pick_skin_04_runed_02` | _(unresolved: dw_2h_pick_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_2h_pick_skin_04_runed_03` | _(unresolved: dw_2h_pick_skin_04_runed_03_name)_ | weapon_skin | dr_ironbreaker, dr_slayer, dr_ranger | unresolved |
| `dw_crossbow_skin_01` | _(unresolved: dw_crossbow_skin_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_crossbow_skin_02` | _(unresolved: dw_crossbow_skin_02_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_crossbow_skin_02_runed_01` | _(unresolved: dw_crossbow_skin_02_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_crossbow_skin_02_runed_04` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_crossbow_skin_02_runed_06` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_crossbow_skin_03` | _(unresolved: dw_crossbow_skin_03_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_crossbow_skin_03_magic_01` | _(unresolved: dw_crossbow_skin_03_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_crossbow_skin_03_magic_02` | _(unresolved: dw_crossbow_skin_03_magic_02_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_crossbow_skin_04` | _(unresolved: dw_crossbow_skin_04_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_crossbow_skin_04_runed_01` | _(unresolved: dw_crossbow_skin_04_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_crossbow_skin_04_runed_02` | _(unresolved: dw_crossbow_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_crossbow_skin_05` | _(unresolved: dw_crossbow_skin_05_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_drake_pistol_skin_01` | _(unresolved: dw_drake_pistol_skin_01_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drake_pistol_skin_01_magic_01` | _(unresolved: dw_drake_pistol_skin_01_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drake_pistol_skin_01_magic_02` | _(unresolved: dw_drake_pistol_skin_01_magic_02_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drake_pistol_skin_02` | _(unresolved: dw_drake_pistol_skin_02_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drake_pistol_skin_03` | _(unresolved: dw_drake_pistol_skin_03_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drake_pistol_skin_03_runed_01` | _(unresolved: dw_drake_pistol_skin_03_runed_01_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drake_pistol_skin_03_runed_06` | _(unresolved: dw_drake_pistol_skin_03_runed_06_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drake_pistol_skin_04` | _(unresolved: dw_drake_pistol_skin_04_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drake_pistol_skin_04_runed_01` | _(unresolved: dw_drake_pistol_skin_04_runed_01_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drake_pistol_skin_04_runed_02` | _(unresolved: dw_drake_pistol_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drake_pistol_skin_04_runed_03` | _(unresolved: )_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drakegun_skin_01` | _(unresolved: dw_drakegun_skin_01_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drakegun_skin_01_runed_01` | _(unresolved: dw_drakegun_skin_01_runed_01_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drakegun_skin_01_runed_06` | _(unresolved: )_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drakegun_skin_02` | _(unresolved: dw_drakegun_skin_02_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drakegun_skin_02_magic_01` | _(unresolved: dw_drakegun_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drakegun_skin_02_magic_02` | _(unresolved: dw_drakegun_skin_02_magic_02_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drakegun_skin_03` | _(unresolved: dw_drakegun_skin_03_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drakegun_skin_03_runed_01` | _(unresolved: dw_drakegun_skin_03_runed_01_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drakegun_skin_03_runed_02` | _(unresolved: dw_drakegun_skin_03_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_drakegun_skin_03_runed_05` | _(unresolved: dw_drakegun_skin_03_runed_05_name)_ | weapon_skin | dr_ironbreaker | unresolved |
| `dw_dual_axe_skin_01` | _(unresolved: dw_dual_axe_skin_01_name)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_02` | _(unresolved: dw_dual_axe_skin_02_name)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_03` | _(unresolved: dw_dual_axe_skin_03_name)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_04` | _(unresolved: dw_dual_axe_skin_04_name)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_04_magic_01` | _(unresolved: dw_dual_axe_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_04_magic_02` | _(unresolved: dw_dual_axe_skin_04_magic_02_name)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_05` | _(unresolved: dw_dual_axe_skin_05_name)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_06` | _(unresolved: dw_dual_axe_skin_06_name)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_06_runed_01` | _(unresolved: dw_dual_axe_skin_06_runed_01_name)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_06_runed_02` | _(unresolved: dw_dual_axe_skin_06_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_06_runed_04` | _(unresolved: dw_dual_axe_skin_06_runed_04_name)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_07` | _(unresolved: dw_dual_axe_skin_07_name)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_07_runed_01` | _(unresolved: dw_dual_axe_skin_07_runed_01_name)_ | weapon_skin | dr_slayer | unresolved |
| `dw_dual_axe_skin_07_runed_06` | _(unresolved: )_ | weapon_skin | dr_slayer | unresolved |
| `dw_grudge_raker_skin_01` | _(unresolved: dw_grudge_raker_skin_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_grudge_raker_skin_01_runed_01` | _(unresolved: dw_grudge_raker_skin_01_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_grudge_raker_skin_01_runed_03` | _(unresolved: dw_grudge_raker_skin_01_runed_03_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_grudge_raker_skin_01_runed_06` | _(unresolved: )_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_grudge_raker_skin_02` | _(unresolved: dw_grudge_raker_skin_02_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_grudge_raker_skin_02_runed_01` | _(unresolved: dw_grudge_raker_skin_02_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_grudge_raker_skin_02_runed_02` | _(unresolved: dw_grudge_raker_skin_02_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_grudge_raker_skin_02_runed_04` | _(unresolved: dw_grudge_raker_skin_02_runed_04_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_grudge_raker_skin_03` | _(unresolved: dw_grudge_raker_skin_03_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_grudge_raker_skin_03_magic_01` | _(unresolved: dw_grudge_raker_skin_03_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_grudge_raker_skin_03_magic_02` | _(unresolved: dw_grudge_raker_skin_03_magic_02_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_01` | _(unresolved: dw_handgun_skin_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_02` | _(unresolved: dw_handgun_skin_02_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_02_runed_01` | _(unresolved: dw_handgun_skin_02_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_02_runed_03` | _(unresolved: dw_handgun_skin_02_runed_03_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_02_runed_04` | _(unresolved: dw_handgun_skin_02_runed_04_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_02_runed_06` | _(unresolved: dw_handgun_skin_02_runed_06_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_03` | _(unresolved: dw_handgun_skin_03_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_03_magic_01` | _(unresolved: dw_handgun_skin_03_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_03_magic_02` | _(unresolved: dw_handgun_skin_03_magic_02_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_04` | _(unresolved: dw_handgun_skin_04_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_05` | _(unresolved: dw_handgun_skin_05_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_05_runed_01` | _(unresolved: dw_handgun_skin_05_runed_01_name)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `dw_handgun_skin_05_runed_02` | _(unresolved: dw_handgun_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | dr_ironbreaker, dr_ranger | unresolved |
| `es_1h_flail_skin` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `es_1h_flail_skin_01` | _(unresolved: es_1h_flail_skin_01_name)_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_02` | _(unresolved: es_1h_flail_skin_02_name)_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_02_runed_01` | _(unresolved: es_1h_flail_skin_02_runed_01_name)_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_02_runed_03` | _(unresolved: es_1h_flail_skin_02_runed_03_name)_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_03` | _(unresolved: es_1h_flail_skin_03_name)_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_04` | _(unresolved: es_1h_flail_skin_04_name)_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_04_magic_01` | _(unresolved: es_1h_flail_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_04_magic_02` | _(unresolved: es_1h_flail_skin_04_magic_02_name)_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_05` | _(unresolved: es_1h_flail_skin_05_name)_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_05_runed_01` | _(unresolved: es_1h_flail_skin_05_runed_01_name)_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_05_runed_02` | _(unresolved: es_1h_flail_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_05_runed_04` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_flail_skin_05_runed_06` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_captain, wh_bountyhunter | unresolved |
| `es_1h_mace_shield_skin_01` | _(unresolved: es_1h_mace_shield_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_shield_skin_02` | _(unresolved: es_1h_mace_shield_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_shield_skin_02_runed_01` | _(unresolved: es_1h_mace_shield_skin_02_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_shield_skin_02_runed_06` | _(unresolved: es_1h_mace_shield_skin_02_runed_06_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_shield_skin_03` | _(unresolved: es_1h_mace_shield_skin_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_shield_skin_03_runed_01` | _(unresolved: es_1h_mace_shield_skin_03_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_shield_skin_03_runed_02` | _(unresolved: es_1h_mace_shield_skin_03_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_shield_skin_03_runed_05` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_shield_skin_04` | _(unresolved: es_1h_mace_shield_skin_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_shield_skin_04_magic_01` | _(unresolved: es_1h_mace_shield_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_shield_skin_04_magic_02` | _(unresolved: es_1h_mace_shield_skin_04_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_shield_skin_05` | _(unresolved: es_1h_mace_shield_skin_05_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `es_1h_mace_skin_01` | _(unresolved: es_1h_mace_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_skin_02` | _(unresolved: es_1h_mace_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_skin_02_runed_01` | _(unresolved: es_1h_mace_skin_02_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_skin_02_runed_02` | _(unresolved: es_1h_mace_skin_02_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_skin_02_runed_06` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_skin_03` | _(unresolved: es_1h_mace_skin_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_skin_04` | _(unresolved: es_1h_mace_skin_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_skin_05` | _(unresolved: es_1h_mace_skin_05_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_skin_05_magic_01` | _(unresolved: es_1h_mace_skin_05_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_mace_skin_05_magic_02` | _(unresolved: es_1h_mace_skin_05_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_01` | _(unresolved: es_1h_sword_shield_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_02` | _(unresolved: es_1h_sword_shield_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_02_runed_01` | _(unresolved: es_1h_sword_shield_skin_02_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_02_runed_06` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_03` | _(unresolved: es_1h_sword_shield_skin_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_03_runed_01` | _(unresolved: es_1h_sword_shield_skin_03_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_03_runed_02` | _(unresolved: es_1h_sword_shield_skin_03_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_03_runed_03` | _(unresolved: es_1h_sword_shield_skin_03_runed_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_04` | _(unresolved: es_1h_sword_shield_skin_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_04_magic_01` | _(unresolved: es_1h_sword_shield_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_04_magic_02` | _(unresolved: es_1h_sword_shield_skin_04_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_shield_skin_05` | _(unresolved: es_1h_sword_shield_skin_05_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `es_1h_sword_skin_01` | _(unresolved: es_1h_sword_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_skin_01_runed_01` | _(unresolved: es_1h_sword_skin_01_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_skin_01_runed_02` | _(unresolved: es_1h_sword_skin_01_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_skin_01_runed_06` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_skin_02` | _(unresolved: es_1h_sword_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_skin_02_runed_01` | _(unresolved: es_1h_sword_skin_02_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_skin_02_runed_03` | _(unresolved: es_1h_sword_skin_02_runed_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_skin_03` | _(unresolved: es_1h_sword_skin_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_skin_04` | _(unresolved: es_1h_sword_skin_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_skin_04_magic_01` | _(unresolved: es_1h_sword_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_1h_sword_skin_04_magic_02` | _(unresolved: es_1h_sword_skin_04_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `es_2h_hammer_skin_01` | _(unresolved: es_2h_hammer_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_02` | _(unresolved: es_2h_hammer_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_02_magic_01` | _(unresolved: es_2h_hammer_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_02_magic_02` | _(unresolved: es_2h_hammer_skin_02_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_03` | _(unresolved: es_2h_hammer_skin_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_04` | _(unresolved: es_2h_hammer_skin_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_04_runed_01` | _(unresolved: es_2h_hammer_skin_04_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_04_runed_02` | _(unresolved: es_2h_hammer_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_04_runed_04` | _(unresolved: es_2h_hammer_skin_04_runed_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_05` | _(unresolved: es_2h_hammer_skin_05_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_06` | _(unresolved: es_2h_hammer_skin_06_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_06_runed_01` | _(unresolved: es_2h_hammer_skin_06_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_hammer_skin_06_runed_06` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_heavy_spear_skin` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_heavy_spear_skin_01` | _(unresolved: es_2h_heavy_spear_skin_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_mercenary | unresolved |
| `es_2h_heavy_spear_skin_01_runed_01` | _(unresolved: es_2h_heavy_spear_skin_01_runed_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_mercenary | unresolved |
| `es_2h_heavy_spear_skin_02` | _(unresolved: es_2h_heavy_spear_skin_02_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_mercenary | unresolved |
| `es_2h_heavy_spear_skin_02_magic_01` | _(unresolved: es_2h_heavy_spear_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_mercenary | unresolved |
| `es_2h_heavy_spear_skin_02_magic_02` | _(unresolved: es_2h_heavy_spear_skin_02_magic_02_name)_ | weapon_skin | es_huntsman, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_01` | _(unresolved: es_2h_sword_exe_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_02` | _(unresolved: es_2h_sword_exe_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_03` | _(unresolved: es_2h_sword_exe_skin_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_03_magic_01` | _(unresolved: es_2h_sword_exe_skin_03_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_03_magic_02` | _(unresolved: es_2h_sword_exe_skin_03_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_04` | _(unresolved: es_2h_sword_exe_skin_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_04_runed_01` | _(unresolved: es_2h_sword_exe_skin_04_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_04_runed_06` | _(unresolved: es_2h_sword_exe_skin_04_runed_06_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_05` | _(unresolved: es_2h_sword_exe_skin_05_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_05_runed_01` | _(unresolved: es_2h_sword_exe_skin_05_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_05_runed_02` | _(unresolved: es_2h_sword_exe_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_exe_skin_05_runed_04` | _(unresolved: es_2h_sword_exe_skin_05_runed_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_executioner_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `es_2h_sword_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `es_2h_sword_skin_01` | _(unresolved: es_2h_sword_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_02` | _(unresolved: es_2h_sword_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_02_runed_01` | _(unresolved: es_2h_sword_skin_02_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_02_runed_03` | _(unresolved: es_2h_sword_skin_02_runed_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_03` | _(unresolved: es_2h_sword_skin_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_03_magic_01` | _(unresolved: es_2h_sword_skin_03_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_03_magic_02` | _(unresolved: es_2h_sword_skin_03_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_04` | _(unresolved: es_2h_sword_skin_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_04_runed_01` | _(unresolved: es_2h_sword_skin_04_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_04_runed_02` | _(unresolved: es_2h_sword_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_04_runed_06` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_05` | _(unresolved: es_2h_sword_skin_05_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_2h_sword_skin_06` | _(unresolved: es_2h_sword_skin_06_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_bastard_sword_skin` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_skin_01` | _(unresolved: es_bastard_sword_skin_01_name)_ _(dlc:lake)_ | weapon_skin | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_skin_02` | _(unresolved: es_bastard_sword_skin_02_name)_ _(dlc:lake_upgrade)_ | weapon_skin | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_skin_03` | _(unresolved: es_bastard_sword_skin_03_name)_ _(dlc:lake_upgrade)_ | weapon_skin | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_skin_03_runed_01` | _(unresolved: es_bastard_sword_skin_03_runed_01_name)_ _(dlc:lake_upgrade)_ | weapon_skin | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_skin_03_runed_02` | _(unresolved: es_bastard_sword_skin_03_runed_02_name)_ _(dlc:lake_upgrade)_ | weapon_skin | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_skin_03_runed_05` | _(unresolved: es_bastard_sword_skin_03_runed_05_name)_ _(dlc:lake)_ | weapon_skin | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_skin_04` | _(unresolved: es_bastard_sword_skin_04_name)_ _(dlc:lake_upgrade)_ | weapon_skin | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_skin_04_magic_01` | _(unresolved: es_bastard_sword_skin_04_name)_ _(dlc:lake)_ | weapon_skin | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_bastard_sword_skin_04_magic_02` | _(unresolved: es_bastard_sword_skin_04_magic_02_name)_ _(dlc:lake)_ | weapon_skin | es_huntsman, es_knight, es_mercenary, es_questingknight | unresolved |
| `es_blunderbuss_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `es_blunderbuss_skin_01` | _(unresolved: es_blunderbuss_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_01_magic_01` | _(unresolved: es_blunderbuss_skin_01_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_01_magic_02` | _(unresolved: es_blunderbuss_skin_01_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_02` | _(unresolved: es_blunderbuss_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_02_runed_01` | _(unresolved: es_blunderbuss_skin_02_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_02_runed_02` | _(unresolved: es_blunderbuss_skin_02_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_02_runed_05` | _(unresolved: es_blunderbuss_skin_02_runed_05_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_03` | _(unresolved: es_blunderbuss_skin_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_04` | _(unresolved: es_blunderbuss_skin_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_04_runed_01` | _(unresolved: es_blunderbuss_skin_04_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_04_runed_04` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_04_runed_06` | _(unresolved: es_blunderbuss_skin_04_runed_06_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_blunderbuss_skin_05` | _(unresolved: es_blunderbuss_skin_05_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_deus_01_skin_01_runed_05` | _(unresolved: es_deus_01_skin_01_runed_05_name)_ _(dlc:grass)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_deus_skin_02_magic_02` | _(unresolved: es_deus_skin_02_magic_02_name)_ _(dlc:grass)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_dual_wield_hammer_sword_skin` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_dual_wield_hammer_sword_skin_01` | _(unresolved: es_dual_wield_hammer_sword_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_dual_wield_hammer_sword_skin_02` | _(unresolved: es_dual_wield_hammer_sword_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_dual_wield_hammer_sword_skin_02_magic_01` | _(unresolved: es_dual_wield_hammer_sword_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_dual_wield_hammer_sword_skin_02_magic_02` | _(unresolved: es_dual_wield_hammer_sword_skin_02_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_dual_wield_hammer_sword_skin_02_runed_01` | _(unresolved: es_dual_wield_hammer_sword_skin_02_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_dual_wield_hammer_sword_skin_02_runed_05` | _(unresolved: es_dual_wield_hammer_sword_skin_02_runed_05_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `es_halberd_skin_01` | _(unresolved: es_halberd_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_skin_02` | _(unresolved: es_halberd_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_skin_03` | _(unresolved: es_halberd_skin_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_skin_03_magic_01` | _(unresolved: es_halberd_skin_03_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_skin_03_magic_02` | _(unresolved: es_halberd_skin_03_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_skin_04` | _(unresolved: es_halberd_skin_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_skin_04_runed_01` | _(unresolved: es_halberd_skin_04_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_skin_04_runed_02` | _(unresolved: es_halberd_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_skin_04_runed_04` | _(unresolved: es_halberd_skin_04_runed_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_halberd_skin_04_runed_06` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `es_handgun_skin_01` | _(unresolved: es_handgun_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_01_runed_01` | _(unresolved: es_handgun_skin_01_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_01_runed_06` | _(unresolved: )_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_02` | _(unresolved: es_handgun_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_02_magic_01` | _(unresolved: es_handgun_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_02_magic_02` | _(unresolved: es_handgun_skin_02_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_02_runed_01` | _(unresolved: es_handgun_skin_02_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_02_runed_02` | _(unresolved: es_handgun_skin_02_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_02_runed_03` | _(unresolved: es_handgun_skin_02_runed_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_02_runed_05` | _(unresolved: es_handgun_skin_02_runed_05_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_03` | _(unresolved: es_handgun_skin_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_04` | _(unresolved: es_handgun_skin_04_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_handgun_skin_05` | _(unresolved: es_handgun_skin_05_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_longbow_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `es_longbow_skin_01` | _(unresolved: es_longbow_skin_01_name)_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_02` | _(unresolved: es_longbow_skin_02_name)_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_03` | _(unresolved: es_longbow_skin_03_name)_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_04` | _(unresolved: es_longbow_skin_04_name)_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_04_magic_01` | _(unresolved: es_longbow_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_04_magic_02` | _(unresolved: es_longbow_skin_04_magic_02_name)_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_04_runed_01` | _(unresolved: es_longbow_skin_04_runed_01_name)_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_04_runed_05` | _(unresolved: es_longbow_skin_04_runed_05_name)_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_05` | _(unresolved: es_longbow_skin_05_name)_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_05_runed_01` | _(unresolved: es_longbow_skin_05_runed_01_name)_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_05_runed_02` | _(unresolved: es_longbow_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_05_runed_03` | _(unresolved: )_ | weapon_skin | es_huntsman | unresolved |
| `es_longbow_skin_05_runed_06` | _(unresolved: es_longbow_skin_05_runed_06_name)_ | weapon_skin | es_huntsman | unresolved |
| `es_mace_shield_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `es_repeating_handgun_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `es_repeating_handgun_skin_01` | _(unresolved: es_repeating_handgun_skin_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_skin_01_magic_01` | _(unresolved: es_repeating_handgun_skin_01_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_skin_01_magic_02` | _(unresolved: es_repeating_handgun_skin_01_magic_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_skin_02` | _(unresolved: es_repeating_handgun_skin_02_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_skin_02_runed_01` | _(unresolved: es_repeating_handgun_skin_02_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_skin_02_runed_03` | _(unresolved: es_repeating_handgun_skin_02_runed_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_skin_02_runed_06` | _(unresolved: es_repeating_handgun_skin_02_runed_06_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_skin_03` | _(unresolved: es_repeating_handgun_skin_03_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_skin_03_runed_01` | _(unresolved: es_repeating_handgun_skin_03_runed_01_name)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_repeating_handgun_skin_03_runed_02` | _(unresolved: es_repeating_handgun_skin_03_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | es_huntsman, es_knight, es_mercenary | unresolved |
| `es_sword_shield_breton_skin` | _(unresolved: )_ | weapon_skin | es_questingknight | unresolved |
| `es_sword_shield_breton_skin_01` | _(unresolved: es_sword_shield_breton_skin_02_name)_ _(dlc:lake_upgrade)_ | weapon_skin | es_questingknight | unresolved |
| `es_sword_shield_breton_skin_02` | _(unresolved: es_sword_shield_breton_skin_03_name)_ _(dlc:lake_upgrade)_ | weapon_skin | es_questingknight | unresolved |
| `es_sword_shield_breton_skin_03` | _(unresolved: es_sword_shield_breton_skin_04_name)_ _(dlc:lake_upgrade)_ | weapon_skin | es_questingknight | unresolved |
| `es_sword_shield_breton_skin_03_runed_01` | _(unresolved: es_sword_shield_breton_skin_03_runed_01_name)_ _(dlc:lake_upgrade)_ | weapon_skin | es_questingknight | unresolved |
| `es_sword_shield_breton_skin_03_runed_02` | _(unresolved: es_sword_shield_breton_skin_03_runed_02_name)_ _(dlc:lake_upgrade)_ | weapon_skin | es_questingknight | unresolved |
| `es_sword_shield_breton_skin_03_runed_05` | _(unresolved: )_ _(dlc:lake_upgrade)_ | weapon_skin | es_questingknight | unresolved |
| `es_sword_shield_breton_skin_04` | _(unresolved: es_sword_shield_breton_skin_05_name)_ _(dlc:lake_upgrade)_ | weapon_skin | es_questingknight | unresolved |
| `es_sword_shield_breton_skin_04_magic_01_magic_01` | _(unresolved: es_sword_shield_breton_skin_05_magic_01_name)_ _(dlc:lake)_ | weapon_skin | es_questingknight | unresolved |
| `es_sword_shield_breton_skin_04_magic_02` | _(unresolved: es_sword_shield_breton_skin_04_magic_02_name)_ _(dlc:lake)_ | weapon_skin | es_questingknight | unresolved |
| `es_sword_shield_breton_skin_05` | _(unresolved: es_sword_shield_breton_skin_01_name)_ _(dlc:lake)_ | weapon_skin | es_questingknight | unresolved |
| `es_sword_shield_skin` | _(unresolved: )_ | weapon_skin | es_mercenary, es_knight, es_huntsman | unresolved |
| `we_1h_axe_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_1h_axe_skin_01` | _(unresolved: we_1h_axe_skin_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_1h_axe_skin_02` | _(unresolved: we_1h_axe_skin_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_1h_axe_skin_02_magic_01` | _(unresolved: we_1h_axe_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_1h_axe_skin_02_magic_02` | _(unresolved: we_1h_axe_skin_02_magic_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_1h_axe_skin_02_runed_01` | _(unresolved: we_1h_axe_skin_02_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_1h_spears_shield_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_1h_spears_shield_skin_01` | _(unresolved: we_1h_spears_shield_skin_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_maidenguard | unresolved |
| `we_1h_spears_shield_skin_01_runed_01` | _(unresolved: we_1h_spears_shield_skin_01_runed_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_maidenguard | unresolved |
| `we_1h_spears_shield_skin_01_runed_05` | _(unresolved: )_ _(dlc:scorpion)_ | weapon_skin | we_maidenguard | unresolved |
| `we_1h_spears_shield_skin_02` | _(unresolved: we_1h_spears_shield_skin_02_name)_ _(dlc:scorpion)_ | weapon_skin | we_maidenguard | unresolved |
| `we_1h_spears_shield_skin_02_magic_01` | _(unresolved: we_1h_spears_shield_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_maidenguard | unresolved |
| `we_1h_spears_shield_skin_02_magic_02` | _(unresolved: we_1h_spears_shield_skin_02_magic_02_name)_ | weapon_skin | we_maidenguard | unresolved |
| `we_1h_sword_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_2h_axe_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_2h_axe_skin_01` | _(unresolved: we_2h_axe_skin_07_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_02` | _(unresolved: we_2h_axe_skin_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_03` | _(unresolved: we_2h_axe_skin_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_03_magic_01` | _(unresolved: we_2h_axe_skin_03_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_03_magic_02` | _(unresolved: we_2h_axe_skin_03_magic_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_04` | _(unresolved: we_2h_axe_skin_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_05` | _(unresolved: we_2h_axe_skin_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_05_runed_01` | _(unresolved: we_2h_axe_skin_05_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_05_runed_02` | _(unresolved: we_2h_axe_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_05_runed_06` | _(unresolved: )_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_06` | _(unresolved: we_2h_axe_skin_06_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_07` | _(unresolved: we_2h_axe_skin_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_07_runed_01` | _(unresolved: we_2h_axe_skin_07_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_07_runed_03` | _(unresolved: we_2h_axe_skin_07_runed_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_axe_skin_08` | _(unresolved: we_2h_axe_skin_08_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_2h_sword_skin_01` | _(unresolved: we_2h_sword_skin_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_02` | _(unresolved: we_2h_sword_skin_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_03` | _(unresolved: we_2h_sword_skin_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_04` | _(unresolved: we_2h_sword_skin_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_05` | _(unresolved: we_2h_sword_skin_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_05_runed_01` | _(unresolved: we_2h_sword_skin_05_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_05_runed_06` | _(unresolved: )_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_06` | _(unresolved: we_2h_sword_skin_06_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_06_runed_01` | _(unresolved: we_2h_sword_skin_06_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_06_runed_02` | _(unresolved: we_2h_sword_skin_06_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_06_runed_03` | _(unresolved: we_2h_sword_skin_06_runed_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_07` | _(unresolved: we_2h_sword_skin_07_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_08` | _(unresolved: we_2h_sword_skin_08_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_08_magic_01` | _(unresolved: we_2h_sword_skin_08_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_08_magic_02` | _(unresolved: we_2h_sword_skin_08_magic_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_09` | _(unresolved: we_2h_sword_skin_09_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_2h_sword_skin_10` | _(unresolved: we_2h_sword_skin_10_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_crossbow_repeater_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_crossbow_skin_01` | _(unresolved: we_crossbow_skin_01_name)_ | weapon_skin | we_shade | unresolved |
| `we_crossbow_skin_01_magic_01` | _(unresolved: we_crossbow_skin_01_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade | unresolved |
| `we_crossbow_skin_01_magic_02` | _(unresolved: we_crossbow_skin_01_magic_02_name)_ | weapon_skin | we_shade | unresolved |
| `we_crossbow_skin_02` | _(unresolved: we_crossbow_skin_02_name)_ | weapon_skin | we_shade | unresolved |
| `we_crossbow_skin_02_runed_01` | _(unresolved: we_crossbow_skin_02_runed_01_name)_ | weapon_skin | we_shade | unresolved |
| `we_crossbow_skin_02_runed_03` | _(unresolved: we_crossbow_skin_02_runed_03_name)_ | weapon_skin | we_shade | unresolved |
| `we_crossbow_skin_03` | _(unresolved: we_crossbow_skin_03_name)_ | weapon_skin | we_shade | unresolved |
| `we_crossbow_skin_03_runed_01` | _(unresolved: we_crossbow_skin_03_runed_01_name)_ | weapon_skin | we_shade | unresolved |
| `we_crossbow_skin_03_runed_02` | _(unresolved: we_crossbow_skin_03_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | we_shade | unresolved |
| `we_crossbow_skin_03_runed_06` | _(unresolved: we_crossbow_skin_03_runed_06_name)_ | weapon_skin | we_shade | unresolved |
| `we_deus_01_skin_02_runed_05` | _(unresolved: we_deus_01_skin_02_runed_05_name)_ _(dlc:grass)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_deus_skin_01_magic_02` | _(unresolved: we_deus_skin_01_magic_02_name)_ _(dlc:grass)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher, we_thornsister | unresolved |
| `we_dual_dagger_skin_01` | _(unresolved: we_dual_dagger_skin_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_01_runed_01` | _(unresolved: we_dual_dagger_skin_01_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_01_runed_04` | _(unresolved: we_dual_dagger_skin_01_runed_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_02` | _(unresolved: we_dual_dagger_skin_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_02_runed_01` | _(unresolved: we_dual_dagger_skin_02_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_02_runed_02` | _(unresolved: we_dual_dagger_skin_02_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_02_runed_05` | _(unresolved: we_dual_dagger_skin_02_runed_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_02_runed_06` | _(unresolved: we_dual_dagger_skin_02_runed_06_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_03` | _(unresolved: we_dual_dagger_skin_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_04` | _(unresolved: we_dual_dagger_skin_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_05` | _(unresolved: we_dual_dagger_skin_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_06` | _(unresolved: we_dual_dagger_skin_06_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_07` | _(unresolved: we_dual_dagger_skin_07_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_07_magic_01` | _(unresolved: we_dual_dagger_skin_07_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_dagger_skin_07_magic_02` | _(unresolved: we_dual_dagger_skin_07_magic_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_01` | _(unresolved: we_dual_sword_dagger_skin_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_01_runed_01` | _(unresolved: we_dual_sword_dagger_skin_01_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_01_runed_02` | _(unresolved: we_dual_sword_dagger_skin_01_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_02` | _(unresolved: we_dual_sword_dagger_skin_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_02_runed_01` | _(unresolved: we_dual_sword_dagger_skin_02_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_02_runed_03` | _(unresolved: we_dual_sword_dagger_skin_02_runed_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_02_runed_06` | _(unresolved: )_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_04` | _(unresolved: we_dual_sword_dagger_skin_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_04_runed_01` | _(unresolved: we_dual_sword_dagger_skin_04_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_05` | _(unresolved: we_dual_sword_dagger_skin_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_05_runed_01` | _(unresolved: we_dual_sword_dagger_skin_05_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_06` | _(unresolved: we_dual_sword_dagger_skin_06_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_07` | _(unresolved: we_dual_sword_dagger_skin_07_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_07_magic_01` | _(unresolved: we_dual_sword_dagger_skin_07_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_dagger_skin_07_magic_02` | _(unresolved: we_dual_sword_dagger_skin_07_magic_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_01` | _(unresolved: we_dual_sword_skin_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_02` | _(unresolved: we_dual_sword_skin_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_02_runed_01` | _(unresolved: we_dual_sword_skin_02_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_02_runed_05` | _(unresolved: we_dual_sword_skin_02_runed_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_03` | _(unresolved: we_dual_sword_skin_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_04` | _(unresolved: we_dual_sword_skin_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_04_runed_01` | _(unresolved: we_dual_sword_skin_04_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_04_runed_06` | _(unresolved: )_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_05` | _(unresolved: we_dual_sword_skin_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_05_runed_01` | _(unresolved: we_dual_sword_skin_05_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_05_runed_02` | _(unresolved: we_dual_sword_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_05_runed_03` | _(unresolved: )_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_06` | _(unresolved: we_dual_sword_skin_06_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_06_magic_01` | _(unresolved: we_dual_sword_skin_06_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_06_magic_02` | _(unresolved: we_dual_sword_skin_06_magic_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_sword_skin_07` | _(unresolved: we_dual_sword_skin_07_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_dual_wield_daggers_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_dual_wield_sword_dagger_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_dual_wield_swords_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_hagbane_skin_01` | _(unresolved: we_hagbane_skin_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_hagbane_skin_01_runed_01` | _(unresolved: we_hagbane_skin_01_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_hagbane_skin_02` | _(unresolved: we_hagbane_skin_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_hagbane_skin_03` | _(unresolved: we_hagbane_skin_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_hagbane_skin_04` | _(unresolved: we_hagbane_skin_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_hagbane_skin_04_runed_01` | _(unresolved: we_hagbane_skin_04_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_hagbane_skin_04_runed_02` | _(unresolved: we_hagbane_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_hagbane_skin_04_runed_05` | _(unresolved: )_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_hagbane_skin_04_runed_06` | _(unresolved: we_hagbane_skin_04_runed_06_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_hagbane_skin_05` | _(unresolved: we_hagbane_skin_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_javelin_skin` | _(unresolved: )_ | weapon_skin | we_thornsister, we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_javelin_skin_01` | _(unresolved: we_javelin_skin_01_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_javelin_skin_01_runed_01` | _(unresolved: we_javelin_skin_01_runed_01_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_javelin_skin_01_runed_02` | _(unresolved: we_javelin_skin_01_runed_02_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_javelin_skin_02` | _(unresolved: we_javelin_skin_02_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_javelin_skin_02_magic_01` | _(unresolved: we_javelin_skin_02_magic_01_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_javelin_skin_02_magic_02` | _(unresolved: we_javelin_skin_02_magic_02_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_javelin_skin_02_runed_01` | _(unresolved: we_javelin_skin_02_runed_01_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_javelin_skin_02_runed_02` | _(unresolved: we_javelin_skin_02_runed_02_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_javelin_skin_02_runed_05` | _(unresolved: we_javelin_skin_02_runed_05_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_life_staff_skin` | _(unresolved: )_ | weapon_skin | we_thornsister | unresolved |
| `we_life_staff_skin_01` | _(unresolved: we_life_staff_skin_01_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_life_staff_skin_01_runed_01` | _(unresolved: we_life_staff_skin_01_runed_01_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_life_staff_skin_01_runed_02` | _(unresolved: we_life_staff_skin_01_runed_02_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_life_staff_skin_02` | _(unresolved: we_life_staff_skin_02_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_life_staff_skin_02_magic_01` | _(unresolved: we_life_staff_skin_02_magic_01_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_life_staff_skin_02_magic_02` | _(unresolved: we_life_staff_skin_02_magic_02_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_life_staff_skin_02_runed_01` | _(unresolved: we_life_staff_skin_02_runed_01_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_life_staff_skin_02_runed_02` | _(unresolved: we_life_staff_skin_02_runed_02_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_life_staff_skin_02_runed_05` | _(unresolved: we_life_staff_skin_02_runed_05_name)_ _(dlc:woods)_ | weapon_skin | we_thornsister | unresolved |
| `we_longbow_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_longbow_skin_01` | _(unresolved: we_longbow_skin_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_02` | _(unresolved: we_longbow_skin_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_02_magic_01` | _(unresolved: we_longbow_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_02_magic_02` | _(unresolved: we_longbow_skin_02_magic_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_03` | _(unresolved: we_longbow_skin_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_04` | _(unresolved: we_longbow_skin_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_05` | _(unresolved: we_longbow_skin_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_05_runed_04` | _(unresolved: )_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_06` | _(unresolved: we_longbow_skin_06_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_06_runed_01` | _(unresolved: we_longbow_skin_06_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_06_runed_02` | _(unresolved: we_longbow_skin_06_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_06_runed_03` | _(unresolved: we_longbow_skin_06_runed_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_06_runed_06` | _(unresolved: we_longbow_skin_06_runed_06_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_07` | _(unresolved: we_longbow_skin_07_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_08` | _(unresolved: we_longbow_skin_08_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_longbow_skin_09` | _(unresolved: we_longbow_skin_09_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_hagbane_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_shortbow_hagbane_skin_02_magic_01` | _(unresolved: we_shortbow_hagbane_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_hagbane_skin_02_magic_02` | _(unresolved: we_shortbow_hagbane_skin_02_magic_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_shortbow_skin_01` | _(unresolved: we_shortbow_skin_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin_01_runed_01` | _(unresolved: we_shortbow_skin_01_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin_01_runed_06` | _(unresolved: )_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin_02` | _(unresolved: we_shortbow_skin_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin_02_magic_01` | _(unresolved: we_shortbow_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin_02_magic_02` | _(unresolved: we_shortbow_skin_02_magic_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin_03` | _(unresolved: we_shortbow_skin_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin_04` | _(unresolved: we_shortbow_skin_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin_04_runed_01` | _(unresolved: we_shortbow_skin_04_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin_04_runed_02` | _(unresolved: we_shortbow_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin_04_runed_04` | _(unresolved: we_shortbow_skin_04_runed_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_shortbow_skin_05` | _(unresolved: we_shortbow_skin_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin` | _(unresolved: )_ | weapon_skin | we_waywatcher, we_maidenguard, we_shade | unresolved |
| `we_spear_skin_01` | _(unresolved: we_spear_skin_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin_02` | _(unresolved: we_spear_skin_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin_02_magic_01` | _(unresolved: we_spear_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin_02_magic_02` | _(unresolved: we_spear_skin_02_magic_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin_03` | _(unresolved: we_spear_skin_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin_03_runed_01` | _(unresolved: we_spear_skin_03_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin_03_runed_02` | _(unresolved: we_spear_skin_03_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin_03_runed_04` | _(unresolved: we_spear_skin_03_runed_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin_04` | _(unresolved: we_spear_skin_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin_04_runed_01` | _(unresolved: we_spear_skin_04_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin_04_runed_06` | _(unresolved: we_spear_skin_04_runed_06_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_spear_skin_05` | _(unresolved: we_spear_skin_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_01` | _(unresolved: we_sword_skin_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_02` | _(unresolved: we_sword_skin_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_02_runed_01` | _(unresolved: we_sword_skin_02_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_03` | _(unresolved: we_sword_skin_03_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_04` | _(unresolved: we_sword_skin_04_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_04_runed_01` | _(unresolved: we_sword_skin_04_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_04_runed_06` | _(unresolved: )_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_05` | _(unresolved: we_sword_skin_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_05_runed_01` | _(unresolved: we_sword_skin_05_runed_01_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_05_runed_02` | _(unresolved: we_sword_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_05_runed_05` | _(unresolved: we_sword_skin_05_runed_05_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_06` | _(unresolved: we_sword_skin_06_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_06_magic_01` | _(unresolved: we_sword_skin_06_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_06_magic_02` | _(unresolved: we_sword_skin_06_magic_02_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `we_sword_skin_07` | _(unresolved: we_sword_skin_07_name)_ | weapon_skin | we_shade, we_maidenguard, we_waywatcher | unresolved |
| `wh_1h_axe_skin` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_01` | _(unresolved: wh_1h_axe_skin_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_02` | _(unresolved: wh_1h_axe_skin_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_02_runed_01` | _(unresolved: wh_1h_axe_skin_02_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_02_runed_06` | _(unresolved: wh_1h_axe_skin_02_runed_06_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_03` | _(unresolved: wh_1h_axe_skin_03_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_04` | _(unresolved: wh_1h_axe_skin_04_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_04_runed_01` | _(unresolved: wh_1h_axe_skin_04_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_04_runed_02` | _(unresolved: wh_1h_axe_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_04_runed_03` | _(unresolved: wh_1h_axe_skin_04_runed_03_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_05` | _(unresolved: wh_1h_axe_skin_05_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_06` | _(unresolved: wh_1h_axe_skin_06_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_06_magic_01` | _(unresolved: wh_1h_axe_skin_06_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_axe_skin_06_magic_02` | _(unresolved: wh_1h_axe_skin_06_magic_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin_01` | _(unresolved: wh_1h_falchion_skin_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin_01_runed_01` | _(unresolved: wh_1h_falchion_skin_01_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin_01_runed_06` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin_02` | _(unresolved: wh_1h_falchion_skin_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin_02_runed_01` | _(unresolved: wh_1h_falchion_skin_02_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin_02_runed_02` | _(unresolved: wh_1h_falchion_skin_02_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin_02_runed_04` | _(unresolved: wh_1h_falchion_skin_02_runed_04_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin_03` | _(unresolved: wh_1h_falchion_skin_03_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin_04` | _(unresolved: wh_1h_falchion_skin_04_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin_04_magic_01` | _(unresolved: wh_1h_falchion_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_falchion_skin_04_magic_02` | _(unresolved: wh_1h_falchion_skin_04_magic_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_1h_hammer_skin` | _(unresolved: )_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_skin_01` | _(unresolved: wh_1h_hammer_skin_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_skin_01_runed_01` | _(unresolved: wh_1h_hammer_skin_01_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_skin_01_runed_02` | _(unresolved: wh_1h_hammer_skin_01_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_skin_02` | _(unresolved: wh_1h_hammer_skin_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_skin_02_magic_01` | _(unresolved: wh_1h_hammer_skin_02_magic_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_skin_02_magic_02` | _(unresolved: wh_1h_hammer_skin_02_magic_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_skin_02_runed_01` | _(unresolved: wh_1h_hammer_skin_02_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_1h_hammer_skin_02_runed_02` | _(unresolved: wh_1h_hammer_skin_02_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_2h_billhook_skin` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_billhook_skin_01` | _(unresolved: wh_2h_billhook_skin_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_billhook_skin_01_runed_01` | _(unresolved: wh_2h_billhook_skin_01_runed_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_billhook_skin_02` | _(unresolved: wh_2h_billhook_skin_02_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_billhook_skin_02_magic_01` | _(unresolved: wh_2h_billhook_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_billhook_skin_02_magic_02` | _(unresolved: wh_2h_billhook_skin_02_magic_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_hammer_skin` | _(unresolved: )_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_skin_01` | _(unresolved: wh_2h_hammer_skin_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_skin_01_runed_01` | _(unresolved: wh_2h_hammer_skin_01_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_skin_01_runed_02` | _(unresolved: wh_2h_hammer_skin_01_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_skin_02` | _(unresolved: wh_2h_hammer_skin_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_skin_02_magic_01` | _(unresolved: wh_2h_hammer_skin_02_magic_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_skin_02_magic_02` | _(unresolved: wh_2h_hammer_skin_02_magic_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_skin_02_runed_01` | _(unresolved: wh_2h_hammer_skin_02_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_skin_02_runed_02` | _(unresolved: wh_2h_hammer_skin_02_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_2h_hammer_skin_02_runed_05` | _(unresolved: wh_2h_hammer_skin_02_runed_05_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_2h_sword_skin` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_01` | _(unresolved: wh_2h_sword_skin_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_02` | _(unresolved: wh_2h_sword_skin_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_02_runed_01` | _(unresolved: wh_2h_sword_skin_02_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_02_runed_06` | _(unresolved: wh_2h_sword_skin_02_runed_06_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_03` | _(unresolved: wh_2h_sword_skin_03_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_04` | _(unresolved: wh_2h_sword_skin_04_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_04_magic_01` | _(unresolved: wh_2h_sword_skin_04_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_04_magic_02` | _(unresolved: wh_2h_sword_skin_04_magic_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_05` | _(unresolved: wh_2h_sword_skin_05_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_05_runed_01` | _(unresolved: wh_2h_sword_skin_05_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_05_runed_02` | _(unresolved: wh_2h_sword_skin_05_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_2h_sword_skin_05_runed_05` | _(unresolved: wh_2h_sword_skin_05_runed_05_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_01` | _(unresolved: wh_brace_of_pistols_skin_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_02` | _(unresolved: wh_brace_of_pistols_skin_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_03` | _(unresolved: wh_brace_of_pistols_skin_03_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_03_runed_01` | _(unresolved: wh_brace_of_pistols_skin_03_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_03_runed_02` | _(unresolved: wh_brace_of_pistols_skin_03_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_03_runed_05` | _(unresolved: wh_brace_of_pistols_skin_03_runed_05_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_04` | _(unresolved: wh_brace_of_pistols_skin_04_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_05` | _(unresolved: wh_brace_of_pistols_skin_05_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_05_magic_01` | _(unresolved: wh_brace_of_pistols_skin_05_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_05_magic_02` | _(unresolved: wh_brace_of_pistols_skin_05_magic_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_05_runed_01` | _(unresolved: wh_brace_of_pistols_skin_05_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_05_runed_03` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_05_runed_04` | _(unresolved: wh_brace_of_pistols_skin_05_runed_04_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_brace_of_pistols_skin_05_runed_06` | _(unresolved: wh_brace_of_pistols_skin_05_runed_06_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_repeater_skin` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_01` | _(unresolved: wh_crossbow_skin_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_02` | _(unresolved: wh_crossbow_skin_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_02_runed_01` | _(unresolved: wh_crossbow_skin_02_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_02_runed_05` | _(unresolved: wh_crossbow_skin_02_runed_05_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_02_runed_06` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_03` | _(unresolved: wh_crossbow_skin_03_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_04` | _(unresolved: wh_crossbow_skin_04_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_04_runed_01` | _(unresolved: wh_crossbow_skin_04_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_04_runed_02` | _(unresolved: wh_crossbow_skin_04_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_04_runed_03` | _(unresolved: wh_crossbow_skin_04_runed_03_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_05` | _(unresolved: wh_crossbow_skin_05_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_06` | _(unresolved: wh_crossbow_skin_06_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_06_magic_01` | _(unresolved: wh_crossbow_skin_06_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_06_magic_02` | _(unresolved: wh_crossbow_skin_06_magic_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_crossbow_skin_07` | _(unresolved: wh_crossbow_skin_07_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_deus_01_skin_03_runed_05` | _(unresolved: wh_deus_01_skin_03_runed_05_name)_ _(dlc:grass)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_deus_skin_02_magic_02` | _(unresolved: wh_deus_skin_02_magic_02_name)_ _(dlc:grass)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_dual_hammer_skin` | _(unresolved: )_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_skin_01` | _(unresolved: wh_dual_hammer_skin_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_skin_01_runed_01` | _(unresolved: wh_dual_hammer_skin_01_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_skin_01_runed_02` | _(unresolved: wh_dual_hammer_skin_01_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_skin_02` | _(unresolved: wh_dual_hammer_skin_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_skin_02_magic_01` | _(unresolved: wh_dual_hammer_skin_02_magic_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_skin_02_magic_02` | _(unresolved: wh_dual_hammer_skin_02_magic_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_skin_02_runed_01` | _(unresolved: wh_dual_hammer_skin_02_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_dual_hammer_skin_02_runed_02` | _(unresolved: wh_dual_hammer_skin_02_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest, wh_zealot | unresolved |
| `wh_dual_wield_axe_falchion_skin` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_wield_axe_falchion_skin_01` | _(unresolved: wh_dual_wield_axe_falchion_skin_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_wield_axe_falchion_skin_01_magic_01` | _(unresolved: wh_dual_wield_axe_falchion_skin_01_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_wield_axe_falchion_skin_01_magic_02` | _(unresolved: wh_dual_wield_axe_falchion_skin_01_magic_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_wield_axe_falchion_skin_02` | _(unresolved: wh_dual_wield_axe_falchion_skin_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_dual_wield_axe_falchion_skin_02_runed_01` | _(unresolved: wh_dual_wield_axe_falchion_skin_02_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_fencing_sword_skin` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_fencing_sword_skin_01` | _(unresolved: wh_fencing_sword_skin_01_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_01_runed_01` | _(unresolved: wh_fencing_sword_skin_01_runed_01_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_01_runed_02` | _(unresolved: wh_fencing_sword_skin_01_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_01_runed_03` | _(unresolved: wh_fencing_sword_skin_01_runed_03_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_01_runed_06` | _(unresolved: wh_fencing_sword_skin_01_runed_06_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_02` | _(unresolved: wh_fencing_sword_skin_02_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_03` | _(unresolved: wh_fencing_sword_skin_03_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_04` | _(unresolved: wh_fencing_sword_skin_04_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_05` | _(unresolved: wh_fencing_sword_skin_05_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_06` | _(unresolved: wh_fencing_sword_skin_06_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_07` | _(unresolved: wh_fencing_sword_skin_07_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_07_magic_01` | _(unresolved: wh_fencing_sword_skin_07_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_07_magic_02` | _(unresolved: wh_fencing_sword_skin_07_magic_02_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_fencing_sword_skin_08` | _(unresolved: wh_fencing_sword_skin_08_name)_ | weapon_skin | wh_bountyhunter, wh_captain, wh_zealot | unresolved |
| `wh_flail_shield_skin` | _(unresolved: )_ | weapon_skin | wh_priest | unresolved |
| `wh_flail_shield_skin_01` | _(unresolved: wh_flail_shield_skin_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_flail_shield_skin_01_runed_01` | _(unresolved: wh_flail_shield_skin_01_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_flail_shield_skin_01_runed_02` | _(unresolved: wh_flail_shield_skin_01_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_flail_shield_skin_02` | _(unresolved: wh_flail_shield_skin_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_flail_shield_skin_02_magic_01` | _(unresolved: wh_flail_shield_skin_02_magic_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_flail_shield_skin_02_magic_02` | _(unresolved: wh_flail_shield_skin_02_magic_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_flail_shield_skin_02_runed_01` | _(unresolved: wh_flail_shield_skin_02_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_flail_shield_skin_02_runed_02` | _(unresolved: wh_flail_shield_skin_02_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_flail_shield_skin_02_runed_05` | _(unresolved: )_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_book_skin` | _(unresolved: )_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_book_skin_01` | _(unresolved: wh_hammer_book_skin_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_book_skin_01_runed_01` | _(unresolved: wh_hammer_book_skin_01_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_book_skin_01_runed_02` | _(unresolved: wh_hammer_book_skin_01_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_book_skin_02` | _(unresolved: wh_hammer_book_skin_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_book_skin_02_magic_01` | _(unresolved: wh_hammer_book_skin_02_magic_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_book_skin_02_magic_02` | _(unresolved: wh_hammer_book_skin_02_magic_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_book_skin_02_runed_01` | _(unresolved: wh_hammer_book_skin_02_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_book_skin_02_runed_02` | _(unresolved: wh_hammer_book_skin_02_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_book_skin_02_runed_05` | _(unresolved: wh_hammer_book_skin_02_runed_05_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_shield_skin` | _(unresolved: )_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_shield_skin_01` | _(unresolved: wh_hammer_shield_skin_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_shield_skin_01_runed_01` | _(unresolved: wh_hammer_shield_skin_01_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_shield_skin_01_runed_02` | _(unresolved: wh_hammer_shield_skin_01_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_shield_skin_02` | _(unresolved: wh_hammer_shield_skin_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_shield_skin_02_magic_01` | _(unresolved: wh_hammer_shield_skin_02_magic_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_shield_skin_02_magic_02` | _(unresolved: wh_hammer_shield_skin_02_magic_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_shield_skin_02_runed_01` | _(unresolved: wh_hammer_shield_skin_02_runed_01_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_hammer_shield_skin_02_runed_02` | _(unresolved: wh_hammer_shield_skin_02_runed_02_name)_ _(dlc:bless)_ | weapon_skin | wh_priest | unresolved |
| `wh_repeating_crossbow_skin_01` | _(unresolved: wh_repeating_crossbow_skin_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_crossbow_skin_02` | _(unresolved: wh_repeating_crossbow_skin_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_crossbow_skin_02_magic_01` | _(unresolved: wh_repeating_crossbow_skin_02_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_crossbow_skin_02_magic_02` | _(unresolved: wh_repeating_crossbow_skin_02_magic_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_crossbow_skin_03` | _(unresolved: wh_repeating_crossbow_skin_03_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_crossbow_skin_03_runed_01` | _(unresolved: wh_repeating_crossbow_skin_03_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_crossbow_skin_03_runed_02` | _(unresolved: wh_repeating_crossbow_skin_03_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_crossbow_skin_03_runed_04` | _(unresolved: wh_repeating_crossbow_skin_03_runed_04_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_crossbow_skin_03_runed_05` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_crossbow_skin_03_runed_06` | _(unresolved: wh_repeating_crossbow_skin_03_runed_06_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_01` | _(unresolved: wh_repeating_pistol_skin_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_02` | _(unresolved: wh_repeating_pistol_skin_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_02_runed_01` | _(unresolved: wh_repeating_pistol_skin_02_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_02_runed_02` | _(unresolved: wh_repeating_pistol_skin_02_runed_02_name)_ _(dlc:bogenhafen)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_02_runed_03` | _(unresolved: wh_repeating_pistol_skin_02_runed_03_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_03` | _(unresolved: wh_repeating_pistol_skin_03_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_04` | _(unresolved: wh_repeating_pistol_skin_04_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_04_runed_01` | _(unresolved: wh_repeating_pistol_skin_04_runed_01_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_04_runed_06` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_05` | _(unresolved: wh_repeating_pistol_skin_05_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_05_magic_01` | _(unresolved: wh_repeating_pistol_skin_05_magic_01_name)_ _(dlc:scorpion)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistol_skin_05_magic_02` | _(unresolved: wh_repeating_pistol_skin_05_magic_02_name)_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |
| `wh_repeating_pistols_skin` | _(unresolved: )_ | weapon_skin | wh_zealot, wh_bountyhunter, wh_captain | unresolved |

## source: weapon_tweaker

### kind: wt_unlock (932 entries, 0 unresolved)

| key | display name | item_type | careers | provenance |
|-----|--------------|-----------|---------|------------|
| `bw_adept::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_1h_mace` | Sienna: Mace | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_dagger` | Sienna: Dagger | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_flame_sword` | Sienna: Flame Sword | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | bw_adept | mod_loc |
| `bw_adept::bw_sword` | Sienna: Sword | weapon_access | bw_adept | mod_loc |
| `bw_necromancer::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_1h_mace` | Sienna: Mace | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_dagger` | Sienna: Dagger | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_flame_sword` | Sienna: Flame Sword | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | bw_necromancer | mod_loc |
| `bw_necromancer::bw_sword` | Sienna: Sword | weapon_access | bw_necromancer | mod_loc |
| `bw_scholar::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_1h_mace` | Sienna: Mace | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_dagger` | Sienna: Dagger | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_flame_sword` | Sienna: Flame Sword | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | bw_scholar | mod_loc |
| `bw_scholar::bw_sword` | Sienna: Sword | weapon_access | bw_scholar | mod_loc |
| `bw_unchained::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_1h_mace` | Sienna: Mace | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_dagger` | Sienna: Dagger | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_flame_sword` | Sienna: Flame Sword | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | bw_unchained | mod_loc |
| `bw_unchained::bw_sword` | Sienna: Sword | weapon_access | bw_unchained | mod_loc |
| `dr_engineer::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_1h_axe` | Bardin: Axe | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_1h_hammer` | Bardin: Hammer | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_2h_axe` | Bardin: Great Axe | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_2h_hammer` | Bardin: Great Hammer | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_2h_pick` | Bardin: War Pick | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_crossbow` | Bardin: Crossbow | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_drakegun` | Bardin: Drakegun | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_dual_wield_axes` | Bardin: Dual Axes | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_dual_wield_hammers` | Bardin: Dual Hammers | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_handgun` | Bardin: Handgun | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_rakegun` | Bardin: Grudge-Raker | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_shield_hammer` | Bardin: Hammer and Shield | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::es_1h_sword` | Kruber: Sword | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::es_handgun` | Kruber: Handgun | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::we_1h_sword` | Kerillian: Sword | weapon_access | dr_engineer | mod_loc |
| `dr_engineer::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | dr_engineer | mod_loc |
| `dr_ironbreaker::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_1h_axe` | Bardin: Axe | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_1h_hammer` | Bardin: Hammer | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_2h_axe` | Bardin: Great Axe | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_2h_hammer` | Bardin: Great Hammer | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_2h_pick` | Bardin: War Pick | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_crossbow` | Bardin: Crossbow | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_drakegun` | Bardin: Drakegun | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_dual_wield_axes` | Bardin: Dual Axes | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_dual_wield_hammers` | Bardin: Dual Hammers | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_handgun` | Bardin: Handgun | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_rakegun` | Bardin: Grudge-Raker | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::dr_shield_hammer` | Bardin: Hammer and Shield | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::es_1h_sword` | Kruber: Sword | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::es_handgun` | Kruber: Handgun | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::we_1h_sword` | Kerillian: Sword | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ironbreaker::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | dr_ironbreaker | mod_loc |
| `dr_ranger::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_1h_axe` | Bardin: Axe | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_1h_hammer` | Bardin: Hammer | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_2h_axe` | Bardin: Great Axe | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_2h_hammer` | Bardin: Great Hammer | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_2h_pick` | Bardin: War Pick | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_crossbow` | Bardin: Crossbow | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_dual_wield_axes` | Bardin: Dual Axes | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_dual_wield_hammers` | Bardin: Dual Hammers | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_handgun` | Bardin: Handgun | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_rakegun` | Bardin: Grudge-Raker | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_shield_hammer` | Bardin: Hammer and Shield | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::es_1h_sword` | Kruber: Sword | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::es_handgun` | Kruber: Handgun | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::we_1h_sword` | Kerillian: Sword | weapon_access | dr_ranger | mod_loc |
| `dr_ranger::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | dr_ranger | mod_loc |
| `dr_slayer::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_1h_axe` | Bardin: Axe | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_1h_hammer` | Bardin: Hammer | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_2h_axe` | Bardin: Great Axe | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_2h_hammer` | Bardin: Great Hammer | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_2h_pick` | Bardin: War Pick | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_crossbow` | Bardin: Crossbow | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_dual_wield_axes` | Bardin: Dual Axes | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_dual_wield_hammers` | Bardin: Dual Hammers | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_handgun` | Bardin: Handgun | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_rakegun` | Bardin: Grudge-Raker | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_shield_hammer` | Bardin: Hammer and Shield | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::es_1h_sword` | Kruber: Sword | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::es_handgun` | Kruber: Handgun | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::we_1h_sword` | Kerillian: Sword | weapon_access | dr_slayer | mod_loc |
| `dr_slayer::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | dr_slayer | mod_loc |
| `es_huntsman::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_1h_mace` | Sienna: Mace | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_dagger` | Sienna: Dagger | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_flame_sword` | Sienna: Flame Sword | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::dr_2h_axe` | Bardin: Great Axe | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::dr_2h_pick` | Bardin: War Pick | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::dr_drakegun` | Bardin: Drakegun | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_1h_flail` | Saltzpyre: Flail | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_1h_mace` | Kruber: Mace | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_1h_sword` | Kruber: Sword | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_2h_hammer` | Kruber: Two-Handed Hammer | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_2h_heavy_spear` | Kruber: Tuskgor Spear | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_2h_sword` | Kruber: Greatsword | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_2h_sword_executioner` | Kruber: Executioner Sword | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_bastard_sword` | Kruber: Bretonnian Longsword | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_blunderbuss` | Kruber: Blunderbuss | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_deus_01` | Kruber: Spear and Shield | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_dual_wield_hammer_sword` | Kruber: Mace and Sword | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_halberd` | Kruber: Halberd | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_handgun` | Kruber: Handgun | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_longbow` | Kruber: Longbow | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_mace_shield` | Kruber: Mace and Shield | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_repeating_handgun` | Kruber: Repeating Handgun | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::es_sword_shield` | Kruber: Sword and Shield | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_1h_axe` | Kerillian: Elven Axe | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_1h_spears_shield` | Kerillian: Spear and Shield | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_1h_sword` | Kerillian: Sword | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_2h_axe` | Kerillian: Glaive | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_2h_sword` | Kerillian: Greatsword | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_crossbow_repeater` | Kerillian: Volley Crossbow | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_deus_01` | Kerillian: Moonfire Bow | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_dual_wield_daggers` | Kerillian: Dual Daggers | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_dual_wield_sword_dagger` | Kerillian: Sword and Dagger | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_dual_wield_swords` | Kerillian: Dual Swords | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_javelin` | Kerillian: Javelin | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_life_staff` | Kerillian: Deepwood Staff | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_longbow` | Kerillian: Longbow | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_shortbow` | Kerillian: Swift Bow | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_shortbow_hagbane` | Kerillian: Hagbane Short Bow | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::we_spear` | Kerillian: Spear | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_1h_axe` | Saltzpyre: Axe | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_2h_billhook` | Saltzpyre: Billhook | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_2h_hammer` | Saltzpyre: Holy Great Hammer | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_crossbow` | Saltzpyre: Crossbow | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_deus_01` | Saltzpyre: Griffon-foot | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_dual_hammer` | Saltzpyre: Dual Skull-Splitters | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_fencing_sword` | Saltzpyre: Rapier | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_flail_shield` | Saltzpyre: Flail and Shield | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_hammer_book` | Saltzpyre: Hammer and Tome | weapon_access | es_huntsman | mod_loc |
| `es_huntsman::wh_repeating_pistols` | Saltzpyre: Repeating Pistol | weapon_access | es_huntsman | mod_loc |
| `es_knight::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | es_knight | mod_loc |
| `es_knight::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | es_knight | mod_loc |
| `es_knight::bw_1h_mace` | Sienna: Mace | weapon_access | es_knight | mod_loc |
| `es_knight::bw_dagger` | Sienna: Dagger | weapon_access | es_knight | mod_loc |
| `es_knight::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | es_knight | mod_loc |
| `es_knight::bw_flame_sword` | Sienna: Flame Sword | weapon_access | es_knight | mod_loc |
| `es_knight::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | es_knight | mod_loc |
| `es_knight::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | es_knight | mod_loc |
| `es_knight::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | es_knight | mod_loc |
| `es_knight::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | es_knight | mod_loc |
| `es_knight::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | es_knight | mod_loc |
| `es_knight::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | es_knight | mod_loc |
| `es_knight::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | es_knight | mod_loc |
| `es_knight::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | es_knight | mod_loc |
| `es_knight::dr_2h_axe` | Bardin: Great Axe | weapon_access | es_knight | mod_loc |
| `es_knight::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | es_knight | mod_loc |
| `es_knight::dr_2h_pick` | Bardin: War Pick | weapon_access | es_knight | mod_loc |
| `es_knight::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | es_knight | mod_loc |
| `es_knight::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | es_knight | mod_loc |
| `es_knight::dr_drakegun` | Bardin: Drakegun | weapon_access | es_knight | mod_loc |
| `es_knight::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | es_knight | mod_loc |
| `es_knight::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | es_knight | mod_loc |
| `es_knight::es_1h_flail` | Saltzpyre: Flail | weapon_access | es_knight | mod_loc |
| `es_knight::es_1h_mace` | Kruber: Mace | weapon_access | es_knight | mod_loc |
| `es_knight::es_1h_sword` | Kruber: Sword | weapon_access | es_knight | mod_loc |
| `es_knight::es_2h_hammer` | Kruber: Two-Handed Hammer | weapon_access | es_knight | mod_loc |
| `es_knight::es_2h_heavy_spear` | Kruber: Tuskgor Spear | weapon_access | es_knight | mod_loc |
| `es_knight::es_2h_sword` | Kruber: Greatsword | weapon_access | es_knight | mod_loc |
| `es_knight::es_2h_sword_executioner` | Kruber: Executioner Sword | weapon_access | es_knight | mod_loc |
| `es_knight::es_bastard_sword` | Kruber: Bretonnian Longsword | weapon_access | es_knight | mod_loc |
| `es_knight::es_blunderbuss` | Kruber: Blunderbuss | weapon_access | es_knight | mod_loc |
| `es_knight::es_deus_01` | Kruber: Spear and Shield | weapon_access | es_knight | mod_loc |
| `es_knight::es_dual_wield_hammer_sword` | Kruber: Mace and Sword | weapon_access | es_knight | mod_loc |
| `es_knight::es_halberd` | Kruber: Halberd | weapon_access | es_knight | mod_loc |
| `es_knight::es_handgun` | Kruber: Handgun | weapon_access | es_knight | mod_loc |
| `es_knight::es_longbow` | Kruber: Longbow | weapon_access | es_knight | mod_loc |
| `es_knight::es_mace_shield` | Kruber: Mace and Shield | weapon_access | es_knight | mod_loc |
| `es_knight::es_repeating_handgun` | Kruber: Repeating Handgun | weapon_access | es_knight | mod_loc |
| `es_knight::es_sword_shield` | Kruber: Sword and Shield | weapon_access | es_knight | mod_loc |
| `es_knight::es_sword_shield_breton` | Kruber: Bretonnian Sword and Shield | weapon_access | es_knight | mod_loc |
| `es_knight::we_1h_axe` | Kerillian: Elven Axe | weapon_access | es_knight | mod_loc |
| `es_knight::we_1h_spears_shield` | Kerillian: Spear and Shield | weapon_access | es_knight | mod_loc |
| `es_knight::we_1h_sword` | Kerillian: Sword | weapon_access | es_knight | mod_loc |
| `es_knight::we_2h_axe` | Kerillian: Glaive | weapon_access | es_knight | mod_loc |
| `es_knight::we_2h_sword` | Kerillian: Greatsword | weapon_access | es_knight | mod_loc |
| `es_knight::we_crossbow_repeater` | Kerillian: Volley Crossbow | weapon_access | es_knight | mod_loc |
| `es_knight::we_deus_01` | Kerillian: Moonfire Bow | weapon_access | es_knight | mod_loc |
| `es_knight::we_dual_wield_daggers` | Kerillian: Dual Daggers | weapon_access | es_knight | mod_loc |
| `es_knight::we_dual_wield_sword_dagger` | Kerillian: Sword and Dagger | weapon_access | es_knight | mod_loc |
| `es_knight::we_dual_wield_swords` | Kerillian: Dual Swords | weapon_access | es_knight | mod_loc |
| `es_knight::we_javelin` | Kerillian: Javelin | weapon_access | es_knight | mod_loc |
| `es_knight::we_life_staff` | Kerillian: Deepwood Staff | weapon_access | es_knight | mod_loc |
| `es_knight::we_longbow` | Kerillian: Longbow | weapon_access | es_knight | mod_loc |
| `es_knight::we_shortbow` | Kerillian: Swift Bow | weapon_access | es_knight | mod_loc |
| `es_knight::we_shortbow_hagbane` | Kerillian: Hagbane Short Bow | weapon_access | es_knight | mod_loc |
| `es_knight::we_spear` | Kerillian: Spear | weapon_access | es_knight | mod_loc |
| `es_knight::wh_1h_axe` | Saltzpyre: Axe | weapon_access | es_knight | mod_loc |
| `es_knight::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | es_knight | mod_loc |
| `es_knight::wh_2h_billhook` | Saltzpyre: Billhook | weapon_access | es_knight | mod_loc |
| `es_knight::wh_2h_hammer` | Saltzpyre: Holy Great Hammer | weapon_access | es_knight | mod_loc |
| `es_knight::wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | weapon_access | es_knight | mod_loc |
| `es_knight::wh_crossbow` | Saltzpyre: Crossbow | weapon_access | es_knight | mod_loc |
| `es_knight::wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | weapon_access | es_knight | mod_loc |
| `es_knight::wh_deus_01` | Saltzpyre: Griffon-foot | weapon_access | es_knight | mod_loc |
| `es_knight::wh_dual_hammer` | Saltzpyre: Dual Skull-Splitters | weapon_access | es_knight | mod_loc |
| `es_knight::wh_fencing_sword` | Saltzpyre: Rapier | weapon_access | es_knight | mod_loc |
| `es_knight::wh_flail_shield` | Saltzpyre: Flail and Shield | weapon_access | es_knight | mod_loc |
| `es_knight::wh_hammer_book` | Saltzpyre: Hammer and Tome | weapon_access | es_knight | mod_loc |
| `es_knight::wh_repeating_pistols` | Saltzpyre: Repeating Pistol | weapon_access | es_knight | mod_loc |
| `es_mercenary::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_1h_mace` | Sienna: Mace | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_dagger` | Sienna: Dagger | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_flame_sword` | Sienna: Flame Sword | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::dr_2h_axe` | Bardin: Great Axe | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::dr_2h_pick` | Bardin: War Pick | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::dr_drakegun` | Bardin: Drakegun | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_1h_flail` | Saltzpyre: Flail | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_1h_mace` | Kruber: Mace | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_1h_sword` | Kruber: Sword | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_2h_hammer` | Kruber: Two-Handed Hammer | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_2h_heavy_spear` | Kruber: Tuskgor Spear | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_2h_sword` | Kruber: Greatsword | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_2h_sword_executioner` | Kruber: Executioner Sword | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_bastard_sword` | Kruber: Bretonnian Longsword | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_blunderbuss` | Kruber: Blunderbuss | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_deus_01` | Kruber: Spear and Shield | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_dual_wield_hammer_sword` | Kruber: Mace and Sword | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_halberd` | Kruber: Halberd | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_handgun` | Kruber: Handgun | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_longbow` | Kruber: Longbow | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_mace_shield` | Kruber: Mace and Shield | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_repeating_handgun` | Kruber: Repeating Handgun | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_sword_shield` | Kruber: Sword and Shield | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::es_sword_shield_breton` | Kruber: Bretonnian Sword and Shield | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_1h_axe` | Kerillian: Elven Axe | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_1h_spears_shield` | Kerillian: Spear and Shield | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_1h_sword` | Kerillian: Sword | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_2h_axe` | Kerillian: Glaive | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_2h_sword` | Kerillian: Greatsword | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_crossbow_repeater` | Kerillian: Volley Crossbow | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_deus_01` | Kerillian: Moonfire Bow | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_dual_wield_daggers` | Kerillian: Dual Daggers | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_dual_wield_sword_dagger` | Kerillian: Sword and Dagger | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_dual_wield_swords` | Kerillian: Dual Swords | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_javelin` | Kerillian: Javelin | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_life_staff` | Kerillian: Deepwood Staff | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_longbow` | Kerillian: Longbow | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_shortbow` | Kerillian: Swift Bow | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_shortbow_hagbane` | Kerillian: Hagbane Short Bow | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::we_spear` | Kerillian: Spear | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_1h_axe` | Saltzpyre: Axe | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_2h_billhook` | Saltzpyre: Billhook | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_2h_hammer` | Saltzpyre: Holy Great Hammer | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_crossbow` | Saltzpyre: Crossbow | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_deus_01` | Saltzpyre: Griffon-foot | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_dual_hammer` | Saltzpyre: Dual Skull-Splitters | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_fencing_sword` | Saltzpyre: Rapier | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_flail_shield` | Saltzpyre: Flail and Shield | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_hammer_book` | Saltzpyre: Hammer and Tome | weapon_access | es_mercenary | mod_loc |
| `es_mercenary::wh_repeating_pistols` | Saltzpyre: Repeating Pistol | weapon_access | es_mercenary | mod_loc |
| `es_questingknight::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_1h_mace` | Sienna: Mace | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_dagger` | Sienna: Dagger | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_flame_sword` | Sienna: Flame Sword | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::dr_2h_axe` | Bardin: Great Axe | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::dr_2h_pick` | Bardin: War Pick | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::dr_drakegun` | Bardin: Drakegun | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_1h_flail` | Saltzpyre: Flail | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_1h_mace` | Kruber: Mace | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_1h_sword` | Kruber: Sword | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_2h_hammer` | Kruber: Two-Handed Hammer | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_2h_heavy_spear` | Kruber: Tuskgor Spear | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_2h_sword` | Kruber: Greatsword | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_2h_sword_executioner` | Kruber: Executioner Sword | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_bastard_sword` | Kruber: Bretonnian Longsword | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_blunderbuss` | Kruber: Blunderbuss | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_deus_01` | Kruber: Spear and Shield | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_dual_wield_hammer_sword` | Kruber: Mace and Sword | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_halberd` | Kruber: Halberd | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_handgun` | Kruber: Handgun | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_longbow` | Kruber: Longbow | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_mace_shield` | Kruber: Mace and Shield | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_repeating_handgun` | Kruber: Repeating Handgun | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_sword_shield` | Kruber: Sword and Shield | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::es_sword_shield_breton` | Kruber: Bretonnian Sword and Shield | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_1h_axe` | Kerillian: Elven Axe | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_1h_spears_shield` | Kerillian: Spear and Shield | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_1h_sword` | Kerillian: Sword | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_2h_axe` | Kerillian: Glaive | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_2h_sword` | Kerillian: Greatsword | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_crossbow_repeater` | Kerillian: Volley Crossbow | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_deus_01` | Kerillian: Moonfire Bow | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_dual_wield_daggers` | Kerillian: Dual Daggers | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_dual_wield_sword_dagger` | Kerillian: Sword and Dagger | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_dual_wield_swords` | Kerillian: Dual Swords | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_javelin` | Kerillian: Javelin | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_life_staff` | Kerillian: Deepwood Staff | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_longbow` | Kerillian: Longbow | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_shortbow` | Kerillian: Swift Bow | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_shortbow_hagbane` | Kerillian: Hagbane Short Bow | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::we_spear` | Kerillian: Spear | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_1h_axe` | Saltzpyre: Axe | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_2h_billhook` | Saltzpyre: Billhook | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_2h_hammer` | Saltzpyre: Holy Great Hammer | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_crossbow` | Saltzpyre: Crossbow | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_deus_01` | Saltzpyre: Griffon-foot | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_dual_hammer` | Saltzpyre: Dual Skull-Splitters | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_fencing_sword` | Saltzpyre: Rapier | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_flail_shield` | Saltzpyre: Flail and Shield | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_hammer_book` | Saltzpyre: Hammer and Tome | weapon_access | es_questingknight | mod_loc |
| `es_questingknight::wh_repeating_pistols` | Saltzpyre: Repeating Pistol | weapon_access | es_questingknight | mod_loc |
| `we_maidenguard::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::bw_dagger` | Sienna: Dagger | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::bw_flame_sword` | Sienna: Flame Sword | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_1h_hammer` | Bardin: Hammer | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_2h_axe` | Bardin: Great Axe | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_2h_pick` | Bardin: War Pick | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_crossbow` | Bardin: Crossbow | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_drakegun` | Bardin: Drakegun | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_dual_wield_axes` | Bardin: Dual Axes | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_dual_wield_hammers` | Bardin: Dual Hammers | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_rakegun` | Bardin: Grudge-Raker | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_1h_flail` | Saltzpyre: Flail | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_1h_mace` | Kruber: Mace | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_2h_hammer` | Kruber: Two-Handed Hammer | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_2h_heavy_spear` | Kruber: Tuskgor Spear | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_2h_sword` | Kruber: Greatsword | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_2h_sword_executioner` | Kruber: Executioner Sword | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_bastard_sword` | Kruber: Bretonnian Longsword | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_blunderbuss` | Kruber: Blunderbuss | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_deus_01` | Kruber: Spear and Shield | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_dual_wield_hammer_sword` | Kruber: Mace and Sword | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_halberd` | Kruber: Halberd | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_handgun` | Kruber: Handgun | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_longbow` | Kruber: Longbow | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_mace_shield` | Kruber: Mace and Shield | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_repeating_handgun` | Kruber: Repeating Handgun | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_sword_shield` | Kruber: Sword and Shield | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::es_sword_shield_breton` | Kruber: Bretonnian Sword and Shield | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_1h_axe` | Kerillian: Elven Axe | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_1h_spears_shield` | Kerillian: Spear and Shield | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_1h_sword` | Kerillian: Sword | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_2h_axe` | Kerillian: Glaive | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_2h_sword` | Kerillian: Greatsword | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_crossbow_repeater` | Kerillian: Volley Crossbow | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_deus_01` | Kerillian: Moonfire Bow | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_dual_wield_daggers` | Kerillian: Dual Daggers | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_dual_wield_sword_dagger` | Kerillian: Sword and Dagger | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_dual_wield_swords` | Kerillian: Dual Swords | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_javelin` | Kerillian: Javelins | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_longbow` | Kerillian: Longbow | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_shortbow` | Kerillian: Swift Bow | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_shortbow_hagbane` | Kerillian: Hagbane Short Bow | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::we_spear` | Kerillian: Spear | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_1h_axe` | Saltzpyre: Axe | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_1h_hammer` | Saltzpyre: 1H Hammer | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_2h_billhook` | Saltzpyre: Billhook | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_2h_hammer` | Saltzpyre: 2H Hammer | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_2h_sword` | Saltzpyre: 2H Sword | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_crossbow` | Saltzpyre: Crossbow | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_deus_01` | Saltzpyre: Griffon-foot | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_dual_hammer` | Saltzpyre: Dual Hammers | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_dual_wield_axe_falchion` | Saltzpyre: Axe & Falchion | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_fencing_sword` | Saltzpyre: Rapier | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_flail_shield` | Saltzpyre: Flail and Shield | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_hammer_book` | Saltzpyre: Hammer and Tome | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_hammer_shield` | Saltzpyre: Skull-Splitter and Shield | weapon_access | we_maidenguard | mod_loc |
| `we_maidenguard::wh_repeating_pistols` | Saltzpyre: Repeater Pistol | weapon_access | we_maidenguard | mod_loc |
| `we_shade::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | we_shade | mod_loc |
| `we_shade::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | we_shade | mod_loc |
| `we_shade::bw_dagger` | Sienna: Dagger | weapon_access | we_shade | mod_loc |
| `we_shade::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | we_shade | mod_loc |
| `we_shade::bw_flame_sword` | Sienna: Flame Sword | weapon_access | we_shade | mod_loc |
| `we_shade::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | we_shade | mod_loc |
| `we_shade::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | we_shade | mod_loc |
| `we_shade::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | we_shade | mod_loc |
| `we_shade::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | we_shade | mod_loc |
| `we_shade::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | we_shade | mod_loc |
| `we_shade::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | we_shade | mod_loc |
| `we_shade::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | we_shade | mod_loc |
| `we_shade::dr_1h_hammer` | Bardin: Hammer | weapon_access | we_shade | mod_loc |
| `we_shade::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | we_shade | mod_loc |
| `we_shade::dr_2h_axe` | Bardin: Great Axe | weapon_access | we_shade | mod_loc |
| `we_shade::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | we_shade | mod_loc |
| `we_shade::dr_2h_pick` | Bardin: War Pick | weapon_access | we_shade | mod_loc |
| `we_shade::dr_crossbow` | Bardin: Crossbow | weapon_access | we_shade | mod_loc |
| `we_shade::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | we_shade | mod_loc |
| `we_shade::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | we_shade | mod_loc |
| `we_shade::dr_drakegun` | Bardin: Drakegun | weapon_access | we_shade | mod_loc |
| `we_shade::dr_dual_wield_axes` | Bardin: Dual Axes | weapon_access | we_shade | mod_loc |
| `we_shade::dr_dual_wield_hammers` | Bardin: Dual Hammers | weapon_access | we_shade | mod_loc |
| `we_shade::dr_rakegun` | Bardin: Grudge-Raker | weapon_access | we_shade | mod_loc |
| `we_shade::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | we_shade | mod_loc |
| `we_shade::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | we_shade | mod_loc |
| `we_shade::es_1h_flail` | Saltzpyre: Flail | weapon_access | we_shade | mod_loc |
| `we_shade::es_1h_mace` | Kruber: Mace | weapon_access | we_shade | mod_loc |
| `we_shade::es_2h_hammer` | Kruber: Two-Handed Hammer | weapon_access | we_shade | mod_loc |
| `we_shade::es_2h_heavy_spear` | Kruber: Tuskgor Spear | weapon_access | we_shade | mod_loc |
| `we_shade::es_2h_sword` | Kruber: Greatsword | weapon_access | we_shade | mod_loc |
| `we_shade::es_2h_sword_executioner` | Kruber: Executioner Sword | weapon_access | we_shade | mod_loc |
| `we_shade::es_bastard_sword` | Kruber: Bretonnian Longsword | weapon_access | we_shade | mod_loc |
| `we_shade::es_blunderbuss` | Kruber: Blunderbuss | weapon_access | we_shade | mod_loc |
| `we_shade::es_deus_01` | Kruber: Spear and Shield | weapon_access | we_shade | mod_loc |
| `we_shade::es_dual_wield_hammer_sword` | Kruber: Mace and Sword | weapon_access | we_shade | mod_loc |
| `we_shade::es_halberd` | Kruber: Halberd | weapon_access | we_shade | mod_loc |
| `we_shade::es_handgun` | Kruber: Handgun | weapon_access | we_shade | mod_loc |
| `we_shade::es_longbow` | Kruber: Longbow | weapon_access | we_shade | mod_loc |
| `we_shade::es_mace_shield` | Kruber: Mace and Shield | weapon_access | we_shade | mod_loc |
| `we_shade::es_repeating_handgun` | Kruber: Repeating Handgun | weapon_access | we_shade | mod_loc |
| `we_shade::es_sword_shield` | Kruber: Sword and Shield | weapon_access | we_shade | mod_loc |
| `we_shade::es_sword_shield_breton` | Kruber: Bretonnian Sword and Shield | weapon_access | we_shade | mod_loc |
| `we_shade::we_1h_axe` | Kerillian: Elven Axe | weapon_access | we_shade | mod_loc |
| `we_shade::we_1h_spears_shield` | Kerillian: Spear and Shield | weapon_access | we_shade | mod_loc |
| `we_shade::we_1h_sword` | Kerillian: Sword | weapon_access | we_shade | mod_loc |
| `we_shade::we_2h_axe` | Kerillian: Glaive | weapon_access | we_shade | mod_loc |
| `we_shade::we_2h_sword` | Kerillian: Greatsword | weapon_access | we_shade | mod_loc |
| `we_shade::we_crossbow_repeater` | Kerillian: Volley Crossbow | weapon_access | we_shade | mod_loc |
| `we_shade::we_deus_01` | Kerillian: Moonfire Bow | weapon_access | we_shade | mod_loc |
| `we_shade::we_dual_wield_daggers` | Kerillian: Dual Daggers | weapon_access | we_shade | mod_loc |
| `we_shade::we_dual_wield_sword_dagger` | Kerillian: Sword and Dagger | weapon_access | we_shade | mod_loc |
| `we_shade::we_dual_wield_swords` | Kerillian: Dual Swords | weapon_access | we_shade | mod_loc |
| `we_shade::we_javelin` | Kerillian: Javelins | weapon_access | we_shade | mod_loc |
| `we_shade::we_longbow` | Kerillian: Longbow | weapon_access | we_shade | mod_loc |
| `we_shade::we_shortbow` | Kerillian: Swift Bow | weapon_access | we_shade | mod_loc |
| `we_shade::we_shortbow_hagbane` | Kerillian: Hagbane Short Bow | weapon_access | we_shade | mod_loc |
| `we_shade::we_spear` | Kerillian: Spear | weapon_access | we_shade | mod_loc |
| `we_shade::wh_1h_axe` | Saltzpyre: Axe | weapon_access | we_shade | mod_loc |
| `we_shade::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | we_shade | mod_loc |
| `we_shade::wh_1h_hammer` | Saltzpyre: 1H Hammer | weapon_access | we_shade | mod_loc |
| `we_shade::wh_2h_billhook` | Saltzpyre: Billhook | weapon_access | we_shade | mod_loc |
| `we_shade::wh_2h_hammer` | Saltzpyre: 2H Hammer | weapon_access | we_shade | mod_loc |
| `we_shade::wh_2h_sword` | Saltzpyre: 2H Sword | weapon_access | we_shade | mod_loc |
| `we_shade::wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | weapon_access | we_shade | mod_loc |
| `we_shade::wh_crossbow` | Saltzpyre: Crossbow | weapon_access | we_shade | mod_loc |
| `we_shade::wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | weapon_access | we_shade | mod_loc |
| `we_shade::wh_deus_01` | Saltzpyre: Griffon-foot | weapon_access | we_shade | mod_loc |
| `we_shade::wh_dual_hammer` | Saltzpyre: Dual Hammers | weapon_access | we_shade | mod_loc |
| `we_shade::wh_dual_wield_axe_falchion` | Saltzpyre: Axe & Falchion | weapon_access | we_shade | mod_loc |
| `we_shade::wh_fencing_sword` | Saltzpyre: Rapier | weapon_access | we_shade | mod_loc |
| `we_shade::wh_flail_shield` | Saltzpyre: Flail and Shield | weapon_access | we_shade | mod_loc |
| `we_shade::wh_hammer_book` | Saltzpyre: Hammer and Tome | weapon_access | we_shade | mod_loc |
| `we_shade::wh_hammer_shield` | Saltzpyre: Skull-Splitter and Shield | weapon_access | we_shade | mod_loc |
| `we_shade::wh_repeating_pistols` | Saltzpyre: Repeater Pistol | weapon_access | we_shade | mod_loc |
| `we_thornsister::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::bw_dagger` | Sienna: Dagger | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::bw_flame_sword` | Sienna: Flame Sword | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_1h_hammer` | Bardin: Hammer | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_2h_axe` | Bardin: Great Axe | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_2h_pick` | Bardin: War Pick | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_crossbow` | Bardin: Crossbow | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_drakegun` | Bardin: Drakegun | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_dual_wield_axes` | Bardin: Dual Axes | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_dual_wield_hammers` | Bardin: Dual Hammers | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_rakegun` | Bardin: Grudge-Raker | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_1h_flail` | Saltzpyre: Flail | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_1h_mace` | Kruber: Mace | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_2h_hammer` | Kruber: Two-Handed Hammer | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_2h_heavy_spear` | Kruber: Tuskgor Spear | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_2h_sword` | Kruber: Greatsword | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_2h_sword_executioner` | Kruber: Executioner Sword | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_bastard_sword` | Kruber: Bretonnian Longsword | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_blunderbuss` | Kruber: Blunderbuss | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_deus_01` | Kruber: Spear and Shield | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_dual_wield_hammer_sword` | Kruber: Mace and Sword | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_halberd` | Kruber: Halberd | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_handgun` | Kruber: Handgun | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_longbow` | Kruber: Longbow | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_mace_shield` | Kruber: Mace and Shield | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_repeating_handgun` | Kruber: Repeating Handgun | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_sword_shield` | Kruber: Sword and Shield | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::es_sword_shield_breton` | Kruber: Bretonnian Sword and Shield | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_1h_axe` | Kerillian: Elven Axe | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_1h_spears_shield` | Kerillian: Spear and Shield | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_1h_sword` | Kerillian: Sword | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_2h_axe` | Kerillian: Glaive | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_2h_sword` | Kerillian: Greatsword | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_crossbow_repeater` | Kerillian: Volley Crossbow | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_deus_01` | Kerillian: Moonfire Bow | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_dual_wield_daggers` | Kerillian: Dual Daggers | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_dual_wield_sword_dagger` | Kerillian: Sword and Dagger | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_dual_wield_swords` | Kerillian: Dual Swords | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_javelin` | Kerillian: Javelins | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_life_staff` | Kerillian: Deepwood Staff | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_longbow` | Kerillian: Longbow | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_shortbow` | Kerillian: Swift Bow | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_shortbow_hagbane` | Kerillian: Hagbane Short Bow | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::we_spear` | Kerillian: Spear | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_1h_axe` | Saltzpyre: Axe | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_1h_hammer` | Saltzpyre: 1H Hammer | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_2h_billhook` | Saltzpyre: Billhook | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_2h_hammer` | Saltzpyre: 2H Hammer | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_2h_sword` | Saltzpyre: 2H Sword | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_crossbow` | Saltzpyre: Crossbow | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_deus_01` | Saltzpyre: Griffon-foot | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_dual_hammer` | Saltzpyre: Dual Hammers | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_dual_wield_axe_falchion` | Saltzpyre: Axe & Falchion | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_fencing_sword` | Saltzpyre: Rapier | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_flail_shield` | Saltzpyre: Flail and Shield | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_hammer_book` | Saltzpyre: Hammer and Tome | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_hammer_shield` | Saltzpyre: Skull-Splitter and Shield | weapon_access | we_thornsister | mod_loc |
| `we_thornsister::wh_repeating_pistols` | Saltzpyre: Repeater Pistol | weapon_access | we_thornsister | mod_loc |
| `we_waywatcher::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::bw_1h_flail_flaming` | Sienna: Flaming Flail | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::bw_dagger` | Sienna: Dagger | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::bw_flame_sword` | Sienna: Flame Sword | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_1h_hammer` | Bardin: Hammer | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_2h_axe` | Bardin: Great Axe | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_2h_pick` | Bardin: War Pick | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_crossbow` | Bardin: Crossbow | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_drakegun` | Bardin: Drakegun | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_dual_wield_axes` | Bardin: Dual Axes | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_dual_wield_hammers` | Bardin: Dual Hammers | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_rakegun` | Bardin: Grudge-Raker | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_1h_flail` | Saltzpyre: Flail | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_1h_mace` | Kruber: Mace | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_2h_hammer` | Kruber: Two-Handed Hammer | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_2h_heavy_spear` | Kruber: Tuskgor Spear | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_2h_sword` | Kruber: Greatsword | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_2h_sword_executioner` | Kruber: Executioner Sword | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_bastard_sword` | Kruber: Bretonnian Longsword | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_blunderbuss` | Kruber: Blunderbuss | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_deus_01` | Kruber: Spear and Shield | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_dual_wield_hammer_sword` | Kruber: Mace and Sword | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_halberd` | Kruber: Halberd | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_handgun` | Kruber: Handgun | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_longbow` | Kruber: Longbow | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_mace_shield` | Kruber: Mace and Shield | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_repeating_handgun` | Kruber: Repeating Handgun | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_sword_shield` | Kruber: Sword and Shield | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::es_sword_shield_breton` | Kruber: Bretonnian Sword and Shield | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_1h_axe` | Kerillian: Elven Axe | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_1h_spears_shield` | Kerillian: Spear and Shield | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_1h_sword` | Kerillian: Sword | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_2h_axe` | Kerillian: Glaive | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_2h_sword` | Kerillian: Greatsword | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_crossbow_repeater` | Kerillian: Volley Crossbow | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_deus_01` | Kerillian: Moonfire Bow | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_dual_wield_daggers` | Kerillian: Dual Daggers | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_dual_wield_sword_dagger` | Kerillian: Sword and Dagger | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_dual_wield_swords` | Kerillian: Dual Swords | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_javelin` | Kerillian: Javelins | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_longbow` | Kerillian: Longbow | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_shortbow` | Kerillian: Swift Bow | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_shortbow_hagbane` | Kerillian: Hagbane Short Bow | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::we_spear` | Kerillian: Spear | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_1h_axe` | Saltzpyre: Axe | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_1h_hammer` | Saltzpyre: 1H Hammer | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_2h_billhook` | Saltzpyre: Billhook | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_2h_hammer` | Saltzpyre: 2H Hammer | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_2h_sword` | Saltzpyre: 2H Sword | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_crossbow` | Saltzpyre: Crossbow | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_deus_01` | Saltzpyre: Griffon-foot | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_dual_hammer` | Saltzpyre: Dual Hammers | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_dual_wield_axe_falchion` | Saltzpyre: Axe & Falchion | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_fencing_sword` | Saltzpyre: Rapier | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_flail_shield` | Saltzpyre: Flail and Shield | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_hammer_book` | Saltzpyre: Hammer and Tome | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_hammer_shield` | Saltzpyre: Skull-Splitter and Shield | weapon_access | we_waywatcher | mod_loc |
| `we_waywatcher::wh_repeating_pistols` | Saltzpyre: Repeater Pistol | weapon_access | we_waywatcher | mod_loc |
| `wh_bountyhunter::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::bw_1h_mace` | Sienna: Mace | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::bw_dagger` | Sienna: Dagger | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::bw_flame_sword` | Sienna: Flame Sword | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_2h_axe` | Bardin: Greataxe | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_2h_hammer` | Bardin: 2H Hammer | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_2h_pick` | Bardin: Pickaxe | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_drakegun` | Bardin: Drakegun | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_rakegun` | Bardin: Grudge-Raker | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_shield_hammer` | Bardin: Hammer and Shield | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_1h_flail` | Saltzpyre: Flail | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_1h_mace` | Kruber: Mace | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_1h_sword` | Kruber: Sword | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_2h_hammer` | Kruber: Greathammer | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_2h_heavy_spear` | Kruber: Tuskgor Spear | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_2h_sword_executioner` | Kruber: Executioner Sword | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_bastard_sword` | Kruber: Bretonnian Longsword | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_blunderbuss` | Kruber: Blunderbuss | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_deus_01` | Kruber: Spear and Shield | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_dual_wield_hammer_sword` | Kruber: Mace and Sword | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_halberd` | Kruber: Halberd | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_handgun` | Kruber: Handgun | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_longbow` | Kruber: Longbow | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_mace_shield` | Kruber: Mace and Shield | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_repeating_handgun` | Kruber: Repeater Handgun | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_sword_shield` | Kruber: Sword and Shield | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::es_sword_shield_breton` | Kruber: Bretonnian Sword and Shield | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_1h_axe` | Kerillian: 1H Axe | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_1h_spears_shield` | Kerillian: Spear and Shield | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_1h_sword` | Kerillian: Sword | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_2h_axe` | Kerillian: Glaive | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_2h_sword` | Kerillian: Elf 2H Sword | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_crossbow_repeater` | Kerillian: Volley Crossbow | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_deus_01` | Kerillian: Moonfire Bow | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_dual_wield_daggers` | Kerillian: Dual Daggers | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_dual_wield_sword_dagger` | Kerillian: Sword & Dagger | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_dual_wield_swords` | Kerillian: Dual Swords | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_javelin` | Kerillian: Javelin | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_longbow` | Kerillian: Longbow | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_shortbow` | Kerillian: Shortbow | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_shortbow_hagbane` | Kerillian: Hagbane Shortbow | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::we_spear` | Kerillian: Spear | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_1h_axe` | Saltzpyre: Axe | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_1h_hammer` | Saltzpyre: Skull-Splitter | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_2h_billhook` | Saltzpyre: Billhook | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_2h_hammer` | Saltzpyre: Holy Great Hammer | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_2h_sword` | Saltzpyre: Greatsword | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_crossbow` | Saltzpyre: Crossbow | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_deus_01` | Saltzpyre: Griffon-foot | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_dual_hammer` | Saltzpyre: Dual Skull-Splitters | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_dual_wield_axe_falchion` | Saltzpyre: Axe and Falchion | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_fencing_sword` | Saltzpyre: Rapier | weapon_access | wh_bountyhunter | mod_loc |
| `wh_bountyhunter::wh_repeating_pistols` | Saltzpyre: Repeating Pistol | weapon_access | wh_bountyhunter | mod_loc |
| `wh_captain::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | wh_captain | mod_loc |
| `wh_captain::bw_1h_mace` | Sienna: Mace | weapon_access | wh_captain | mod_loc |
| `wh_captain::bw_dagger` | Sienna: Dagger | weapon_access | wh_captain | mod_loc |
| `wh_captain::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | wh_captain | mod_loc |
| `wh_captain::bw_flame_sword` | Sienna: Flame Sword | weapon_access | wh_captain | mod_loc |
| `wh_captain::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | wh_captain | mod_loc |
| `wh_captain::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | wh_captain | mod_loc |
| `wh_captain::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | wh_captain | mod_loc |
| `wh_captain::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | wh_captain | mod_loc |
| `wh_captain::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | wh_captain | mod_loc |
| `wh_captain::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | wh_captain | mod_loc |
| `wh_captain::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_2h_axe` | Bardin: Greataxe | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_2h_hammer` | Bardin: 2H Hammer | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_2h_pick` | Bardin: Pickaxe | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_drakegun` | Bardin: Drakegun | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_rakegun` | Bardin: Grudge-Raker | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_shield_hammer` | Bardin: Hammer and Shield | weapon_access | wh_captain | mod_loc |
| `wh_captain::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_1h_flail` | Saltzpyre: Flail | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_1h_mace` | Kruber: Mace | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_1h_sword` | Kruber: Sword | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_2h_hammer` | Kruber: Greathammer | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_2h_heavy_spear` | Kruber: Tuskgor Spear | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_2h_sword_executioner` | Kruber: Executioner Sword | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_bastard_sword` | Kruber: Bretonnian Longsword | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_blunderbuss` | Kruber: Blunderbuss | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_deus_01` | Kruber: Spear and Shield | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_dual_wield_hammer_sword` | Kruber: Mace and Sword | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_halberd` | Kruber: Halberd | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_handgun` | Kruber: Handgun | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_longbow` | Kruber: Longbow | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_mace_shield` | Kruber: Mace and Shield | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_repeating_handgun` | Kruber: Repeater Handgun | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_sword_shield` | Kruber: Sword and Shield | weapon_access | wh_captain | mod_loc |
| `wh_captain::es_sword_shield_breton` | Kruber: Bretonnian Sword and Shield | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_1h_axe` | Kerillian: 1H Axe | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_1h_spears_shield` | Kerillian: Spear and Shield | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_1h_sword` | Kerillian: Sword | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_2h_axe` | Kerillian: Glaive | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_2h_sword` | Kerillian: Elf 2H Sword | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_crossbow_repeater` | Kerillian: Volley Crossbow | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_deus_01` | Kerillian: Moonfire Bow | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_dual_wield_daggers` | Kerillian: Dual Daggers | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_dual_wield_sword_dagger` | Kerillian: Sword & Dagger | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_dual_wield_swords` | Kerillian: Dual Swords | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_javelin` | Kerillian: Javelin | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_longbow` | Kerillian: Longbow | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_shortbow` | Kerillian: Shortbow | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_shortbow_hagbane` | Kerillian: Hagbane Shortbow | weapon_access | wh_captain | mod_loc |
| `wh_captain::we_spear` | Kerillian: Spear | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_1h_axe` | Saltzpyre: Axe | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_1h_hammer` | Saltzpyre: Skull-Splitter | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_2h_billhook` | Saltzpyre: Billhook | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_2h_hammer` | Saltzpyre: Holy Great Hammer | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_2h_sword` | Saltzpyre: Greatsword | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_crossbow` | Saltzpyre: Crossbow | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_deus_01` | Saltzpyre: Griffon-foot | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_dual_hammer` | Saltzpyre: Dual Skull-Splitters | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_dual_wield_axe_falchion` | Saltzpyre: Axe and Falchion | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_fencing_sword` | Saltzpyre: Rapier | weapon_access | wh_captain | mod_loc |
| `wh_captain::wh_repeating_pistols` | Saltzpyre: Repeating Pistol | weapon_access | wh_captain | mod_loc |
| `wh_priest::es_1h_flail` | Saltzpyre: Flail | weapon_access | wh_priest | mod_loc |
| `wh_priest::wh_1h_hammer` | Saltzpyre: Skull-Splitter | weapon_access | wh_priest | mod_loc |
| `wh_priest::wh_2h_hammer` | Saltzpyre: Holy Great Hammer | weapon_access | wh_priest | mod_loc |
| `wh_priest::wh_dual_hammer` | Saltzpyre: Dual Skull-Splitters | weapon_access | wh_priest | mod_loc |
| `wh_priest::wh_flail_shield` | Saltzpyre: Flail and Shield | weapon_access | wh_priest | mod_loc |
| `wh_priest::wh_hammer_book` | Saltzpyre: Hammer and Tome | weapon_access | wh_priest | mod_loc |
| `wh_priest::wh_hammer_shield` | Saltzpyre: Skull-Splitter and Shield | weapon_access | wh_priest | mod_loc |
| `wh_zealot::bw_1h_crowbill` | Sienna: Crowbill | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::bw_1h_mace` | Sienna: Mace | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::bw_dagger` | Sienna: Dagger | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::bw_deus_01` | Sienna: Coruscation Staff | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::bw_flame_sword` | Sienna: Flame Sword | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::bw_ghost_scythe` | Sienna: Ensorcelled Reaper | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::bw_necromancy_staff` | Sienna: Soulstealer Staff | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::bw_skullstaff_beam` | Sienna: Beam Staff | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::bw_skullstaff_fireball` | Sienna: Fireball Staff | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::bw_skullstaff_geiser` | Sienna: Conflagration Staff | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::bw_skullstaff_spear` | Sienna: Bolt Staff | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_1h_throwing_axes` | Bardin: Throwing Axes | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_2h_axe` | Bardin: Greataxe | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_2h_cog_hammer` | Bardin: Cog Hammer | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_2h_hammer` | Bardin: 2H Hammer | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_2h_pick` | Bardin: Pickaxe | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_deus_01` | Bardin: Trollhammer Torpedo | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_drake_pistol` | Bardin: Drakefire Pistols | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_drakegun` | Bardin: Drakegun | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_rakegun` | Bardin: Grudge-Raker | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_shield_axe` | Bardin: Axe and Shield | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_shield_hammer` | Bardin: Hammer and Shield | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::dr_steam_pistol` | Bardin: Masterwork Pistol | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_1h_flail` | Saltzpyre: Flail | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_1h_mace` | Kruber: Mace | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_1h_sword` | Kruber: Sword | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_2h_hammer` | Kruber: Greathammer | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_2h_heavy_spear` | Kruber: Tuskgor Spear | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_2h_sword_executioner` | Kruber: Executioner Sword | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_bastard_sword` | Kruber: Bretonnian Longsword | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_blunderbuss` | Kruber: Blunderbuss | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_deus_01` | Kruber: Spear and Shield | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_dual_wield_hammer_sword` | Kruber: Mace and Sword | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_halberd` | Kruber: Halberd | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_handgun` | Kruber: Handgun | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_longbow` | Kruber: Longbow | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_mace_shield` | Kruber: Mace and Shield | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_repeating_handgun` | Kruber: Repeater Handgun | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_sword_shield` | Kruber: Sword and Shield | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::es_sword_shield_breton` | Kruber: Bretonnian Sword and Shield | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_1h_axe` | Kerillian: 1H Axe | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_1h_spears_shield` | Kerillian: Spear and Shield | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_1h_sword` | Kerillian: Sword | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_2h_axe` | Kerillian: Glaive | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_2h_sword` | Kerillian: Elf 2H Sword | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_crossbow_repeater` | Kerillian: Volley Crossbow | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_deus_01` | Kerillian: Moonfire Bow | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_dual_wield_daggers` | Kerillian: Dual Daggers | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_dual_wield_sword_dagger` | Kerillian: Sword & Dagger | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_dual_wield_swords` | Kerillian: Dual Swords | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_javelin` | Kerillian: Javelin | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_longbow` | Kerillian: Longbow | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_shortbow` | Kerillian: Shortbow | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_shortbow_hagbane` | Kerillian: Hagbane Shortbow | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::we_spear` | Kerillian: Spear | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_1h_axe` | Saltzpyre: Axe | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_1h_falchion` | Saltzpyre: Falchion | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_1h_hammer` | Saltzpyre: Skull-Splitter | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_2h_billhook` | Saltzpyre: Billhook | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_2h_hammer` | Saltzpyre: Holy Great Hammer | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_2h_sword` | Saltzpyre: Greatsword | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_crossbow` | Saltzpyre: Crossbow | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_deus_01` | Saltzpyre: Griffon-foot | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_dual_hammer` | Saltzpyre: Dual Skull-Splitters | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_dual_wield_axe_falchion` | Saltzpyre: Axe and Falchion | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_fencing_sword` | Saltzpyre: Rapier | weapon_access | wh_zealot | mod_loc |
| `wh_zealot::wh_repeating_pistols` | Saltzpyre: Repeating Pistol | weapon_access | wh_zealot | mod_loc |

