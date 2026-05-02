# Veteran Weapon Skin Catalog

Auto-generated from VT2 decompiled source + in-game `/dump_glows` and `/dump_skin_rarities` output.
Regenerate via `py cosmetics_tweaker\_build_skin_catalog.py`. Last build parsed 20 files / 891 skins / resolved 829 English names.

Cross-reference: `memory/reference_vt2_weapon_glow_system.md` for system architecture.

## Glow templates (HDR RGB, vector3)

Applied at spawn via `GearUtils.apply_material_settings` → `MaterialSettingsTemplates[material_settings_name]`. Values >1 are HDR/overbright (produce bloom).

| Template | Variable | RGB | Skin-key suffix | UI/community label |
|---|---|---|---|---|
| `purple_glow` | `rune_emissive_color` | (3, 1, 9) | `_runed_02` | "Weave-Forged" (colloquial) |
| `golden_glow` | `rune_emissive_color` | (8, 5, 1.5) | `_runed_03` | Geheimnisnacht 2021 dawn |
| `deep_crimson` | `rune_emissive_color` | (7, 0, 0.1) | `_runed_04` | Skulls 2023 (Khorne) |
| `life_green` | `rune_emissive_color` | (7, 9, 0.1) | `_runed_05` | GOTWF (Sister of the Thorn) |
| `lileath` | `rune_emissive_color` | (5.8, 6.3, 9) | `_runed_06` | Morris 2025 (CW Lileath) |
| `versus` | 5-channel (see below) | varies | `_magic_02` | Versus rewards (Wind of Death) |
| `white_glow` | (NOT REGISTERED) | — | `_runed_02_white` | Abandoned feature, 1 referrer |

`versus` channels: `color_glow_high=(2.5,2,4)`, `color_glow_low=(0.7,0.3,1)`, `color_smoke_high=(0.06,0.15,0.22)`, `color_smoke_low=(0.06,0.03,0.03)`, `color_dots=(8.35,3.5,7)`.

## Rarity → UI label (resolved via Localize in-game)

| Code rarity | UI label | Total skins (this catalog) |
|---|---|---|
| `common` | Common | 73 |
| `exotic` | Exotic | 137 |
| `magic` | (unloc) | 85 |
| `plentiful` | Plentiful | 54 |
| `promo` | (unloc) | 16 |
| `rare` | Rare | 84 |
| `unique` | **Veteran** | 442 |

---

## Veteran skins with `purple_glow` template (81 items)

| Display name | Skin key | Description loc-key | Right unit | Left unit | Source file |
|---|---|---|---|---|---|
| Aldthrund | `dw_handgun_skin_05_runed_02` | `dw_handgun_skin_05_runed_02_name` | `units/weapons/player/wpn_dw_handgun_02_t3/wpn_dw_handgun_02_t3_runed_01` | `—` | `weapon_skins.lua` |
| Ashbringer | `bw_flamethrower_staff_skin_05_runed_02` | `bw_flamethrower_staff_skin_05_runed_02_name` | `units/weapons/player/wpn_brw_flame_staff_05/wpn_brw_flame_staff_05_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Asrai's Reach | `we_longbow_skin_06_runed_02` | `we_longbow_skin_06_runed_02_name` | `—` | `units/weapons/player/wpn_we_bow_03_t2/wpn_we_bow_03_t2_runed_01` | `weapon_skins.lua` |
| Banishing Blade | `es_bastard_sword_skin_03_runed_02` | `es_bastard_sword_skin_03_runed_02_name` | `units/weapons/player/wpn_emp_gk_sword_02_t1/wpn_emp_gk_sword_02_t1_runed_01` | `—` | `weapon_skins_lake.lua` |
| Battlebond | `es_halberd_skin_04_runed_02` | `es_halberd_skin_04_runed_02_name` | `units/weapons/player/wpn_wh_halberd_04/wpn_wh_halberd_04_runed_01` | `—` | `weapon_skins.lua` |
| Bitterblossom | `we_shortbow_skin_04_runed_02` | `we_shortbow_skin_04_runed_02_name` | `—` | `units/weapons/player/wpn_we_bow_short_04/wpn_we_bow_short_04_runed_01` | `weapon_skins.lua` |
| Bjuna's Reaper | `bw_ghost_scythe_skin_01_runed_02` | `bw_ghost_scythe_skin_01_runed_02_name` | `units/weapons/player/wpn_bw_ghost_scythe_01/wpn_bw_ghost_scythe_01_runed_01` | `—` | `weapon_skins_shovel.lua` |
| Brockmann's Duty | `es_2h_sword_exe_skin_05_runed_02` | `es_2h_sword_exe_skin_05_runed_02_name` | `units/weapons/player/wpn_emp_sword_exe_05_t1/wpn_emp_sword_exe_05_t1_runed_01` | `—` | `weapon_skins.lua` |
| Burden and Boon | `es_1h_mace_shield_skin_03_runed_02` | `es_1h_mace_shield_skin_03_runed_02_name` | `units/weapons/player/wpn_emp_mace_02_t2/wpn_emp_mace_02_t2_runed_01` | `units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01` | `weapon_skins.lua` |
| Charrenrush | `bw_1h_mace_skin_05_runed_02` | `bw_1h_mace_skin_05_runed_02_name` | `units/weapons/player/wpn_brw_mace_05/wpn_brw_mace_05_runed_01` | `—` | `weapon_skins.lua` |
| Cleaver of Fate | `we_2h_axe_skin_05_runed_02` | `we_2h_axe_skin_05_runed_02_name` | `units/weapons/player/wpn_we_2h_axe_03_t1/wpn_we_2h_axe_03_t1_runed_01` | `—` | `weapon_skins.lua` |
| Dancer's Galria | `we_dual_sword_dagger_skin_01_runed_02` | `we_dual_sword_dagger_skin_01_runed_02_name` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2_runed_01` | `units/weapons/player/wpn_we_dagger_01_t1/wpn_we_dagger_01_t1_runed_01` | `weapon_skins.lua` |
| Darkaringrund | `dw_1h_hammer_shield_skin_04_runed_02` | `dw_1h_hammer_shield_skin_04_runed_02_name` | `units/weapons/player/wpn_dw_hammer_02_t2/wpn_dw_hammer_02_t2_runed_01` | `units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05_runed_01` | `weapon_skins.lua` |
| Dawn and Dusk | `we_dual_sword_skin_05_runed_02` | `we_dual_sword_skin_05_runed_02_name` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2_runed_01` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2_runed_01` | `weapon_skins.lua` |
| Dicer | `es_1h_sword_skin_01_runed_02` | `es_1h_sword_skin_01_runed_02_name` | `units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1_runed_01` | `—` | `weapon_skins.lua` |
| Dread Draich | `we_2h_sword_skin_06_runed_02` | `we_2h_sword_skin_06_runed_02_name` | `units/weapons/player/wpn_we_2h_sword_03_t2/wpn_we_2h_sword_03_t2_runed_01` | `—` | `weapon_skins.lua` |
| Duty and Courage | `es_1h_sword_shield_skin_03_runed_02` | `es_1h_sword_shield_skin_03_runed_02_name` | `units/weapons/player/wpn_emp_sword_02_t2/wpn_emp_sword_02_t2_runed_01` | `units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01` | `weapon_skins.lua` |
| Eternal Mist | `we_hagbane_skin_04_runed_02` | `we_hagbane_skin_04_runed_02_name` | `—` | `units/weapons/player/wpn_we_bow_short_04/wpn_we_bow_short_04_runed_01` | `weapon_skins.lua` |
| Ethis Char | `bw_dagger_skin_05_runed_02` | `bw_dagger_skin_05_runed_02_name` | `units/weapons/player/wpn_brw_dagger_05/wpn_brw_dagger_05_runed_01` | `—` | `weapon_skins.lua` |
| Fastflight | `wh_repeating_crossbow_skin_03_runed_02` | `wh_repeating_crossbow_skin_03_runed_02_name` | `—` | `units/weapons/player/wpn_wh_repeater_crossbow_t3/wpn_wh_repeater_crossbow_t3_runed_01` | `weapon_skins.lua` |
| Flameleaper | `bw_spear_staff_skin_04_runed_02` | `bw_spear_staff_skin_04_runed_02_name` | `units/weapons/player/wpn_brw_spear_staff_04/wpn_brw_spear_staff_04_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Flamespitter | `bw_fireball_staff_skin_01_runed_02` | `bw_fireball_staff_skin_01_runed_02_name` | `units/weapons/player/wpn_brw_staff_02/wpn_brw_staff_02_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Foolbane | `wh_1h_falchion_skin_02_runed_02` | `wh_1h_falchion_skin_02_runed_02_name` | `units/weapons/player/wpn_emp_sword_04_t2/wpn_emp_sword_04_t2_runed_01` | `—` | `weapon_skins.lua` |
| Grand Theogonist’s Flail & Shield | `wh_flail_shield_skin_02_runed_02` | `wh_flail_shield_skin_02_runed_02_name` | `units/weapons/player/wpn_emp_flail_05_t1/wpn_emp_flail_05_t1_runed_01` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed` | `weapon_skins_bless.lua` |
| Grand Theogonist’s Paired Skull-splitters | `wh_dual_hammer_skin_02_runed_02` | `wh_dual_hammer_skin_02_runed_02_name` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_runed` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_runed` | `weapon_skins_bless.lua` |
| Grand Theogonist’s Reckoner | `wh_2h_hammer_skin_02_runed_02` | `wh_2h_hammer_skin_02_runed_02_name` | `units/weapons/player/wpn_wh_2h_hammer_02/wpn_wh_2h_hammer_02_runed` | `—` | `weapon_skins_bless.lua` |
| Grand Theogonist’s Skull-Splitter | `wh_1h_hammer_skin_02_runed_02` | `wh_1h_hammer_skin_02_runed_02_name` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_runed` | `—` | `weapon_skins_bless.lua` |
| Grand Theogonist’s Skull-Splitter & Blessed Tome | `wh_hammer_book_skin_02_runed_02` | `wh_hammer_book_skin_02_runed_02_name` | `units/weapons/player/wpn_wh_book_02/wpn_wh_book_02_runed` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_runed` | `weapon_skins_bless.lua` |
| Grand Theogonist’s Skull-Splitter & Shield | `wh_hammer_shield_skin_02_runed_02` | `wh_hammer_shield_skin_02_runed_02_name` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_runed` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed` | `weapon_skins_bless.lua` |
| Grimdrakktuk | `dw_drake_pistol_skin_04_runed_02` | `dw_drake_pistol_skin_04_runed_02_name` | `units/weapons/player/wpn_dw_drake_pistol_02_t2/wpn_dw_drake_pistol_02_t2_runed_01` | `units/weapons/player/wpn_dw_drake_pistol_02_t2/wpn_dw_drake_pistol_02_t2_runed_01` | `weapon_skins.lua` |
| Gromdalbarag | `dw_grudge_raker_skin_02_runed_02` | `dw_grudge_raker_skin_02_runed_02_name` | `units/weapons/player/wpn_dw_rakegun_t2/wpn_dw_rakegun_t2_runed_01` | `—` | `weapon_skins.lua` |
| Hab's Cleaver | `wh_1h_axe_skin_04_runed_02` | `wh_1h_axe_skin_04_runed_02_name` | `units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2_runed_01` | `—` | `weapon_skins.lua` |
| Headcracker | `es_1h_mace_skin_02_runed_02` | `es_1h_mace_skin_02_runed_02_name` | `units/weapons/player/wpn_emp_mace_02_t2/wpn_emp_mace_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Hothering's Flare | `bw_beam_staff_skin_05_runed_02` | `bw_beam_staff_skin_05_runed_02_name` | `units/weapons/player/wpn_brw_beam_staff_05/wpn_brw_beam_staff_05_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Kadarakh's Blaze | `bw_1h_sword_skin_02_runed_02` | `bw_1h_sword_skin_02_runed_02_name` | `units/weapons/player/wpn_brw_sword_01_t2/wpn_brw_sword_01_t2_runed_01` | `—` | `weapon_skins.lua` |
| Kalancoggrund | `dr_2h_cog_hammer_skin_01_runed_02` | `dr_cog_hammer_skin_01_runed_02_name` | `units/weapons/player/wpn_dw_coghammer_01_t1/wpn_dw_coghammer_01_t1_runed` | `—` | `weapon_skins_cog.lua` |
| Karond Crossbow | `we_crossbow_skin_03_runed_02` | `we_crossbow_skin_03_runed_02_name` | `—` | `units/weapons/player/wpn_we_repeater_crossbow_t3/wpn_we_repeater_crossbow_t3_runed_01` | `weapon_skins.lua` |
| Khazkarinaz | `dw_1h_axe_shield_skin_05_runed_02` | `dw_1h_axe_shield_skin_05_runed_02_name` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05_runed_01` | `weapon_skins.lua` |
| Kladkrak | `dw_1h_hammer_skin_04_runed_02` | `dw_1h_hammer_skin_04_runed_02_name` | `units/weapons/player/wpn_dw_hammer_02_t2/wpn_dw_hammer_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Levity | `wh_crossbow_skin_04_runed_02` | `wh_crossbow_skin_04_runed_02_name` | `—` | `units/weapons/player/wpn_emp_crossbow_03_t2/wpn_emp_crossbow_03_t2_runed_01` | `weapon_skins.lua` |
| Lykosian War Staff | `bw_necromancy_staff_skin_02_runed_02` | `bw_necromancy_staff_skin_02_runed_02_name` | `units/weapons/player/wpn_bw_necromancy_staff_02/wpn_bw_necromancy_staff_02_runed_01` | `units/weapons/player/wpn_invisible_weapon` | `weapon_skins_shovel.lua` |
| Malice | `we_hagbane_skin_01_runed_02` | `we_hagbane_skin_01_runed_02_name` | `—` | `units/weapons/player/wpn_we_bow_short_01/wpn_we_bow_short_01_runed_01` | `weapon_skins.lua` |
| Maraz-Ungor | `dw_2h_axe_skin_06_runed_02` | `dw_2h_axe_skin_06_runed_02_name` | `units/weapons/player/wpn_dw_2h_axe_03_t2/wpn_dw_2h_axe_03_t2_runed_01` | `—` | `weapon_skins.lua` |
| Marazthrundtak | `dr_steam_pistol_skin_01_runed_02` | `dr_steam_pistol_skin_01_runed_02_name` | `units/weapons/player/wpn_dw_steam_pistol_01_t1/wpn_dw_steam_pistol_01_t1_runed_01` | `—` | `weapon_skins_cog.lua` |
| Nagashizzar Cleaver | `bw_ghost_scythe_skin_02_runed_02` | `bw_ghost_scythe_skin_02_runed_02_name` | `units/weapons/player/wpn_bw_ghost_scythe_02/wpn_bw_ghost_scythe_02_runed_01` | `—` | `weapon_skins_shovel.lua` |
| Narskrundaz | `dw_2h_pick_skin_04_runed_02` | `dw_2h_pick_skin_04_runed_02_name` | `units/weapons/player/wpn_dw_pick_01_t4/wpn_dw_pick_01_t4_runed_01` | `—` | `weapon_skins.lua` |
| Nightceyl | `we_sword_skin_05_runed_02` | `we_sword_skin_05_runed_02_name` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Nornaz | `dw_1h_axe_skin_06_runed_02` | `dw_1h_axe_skin_06_runed_02_name` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `—` | `weapon_skins.lua` |
| Pegasus Bulwark | `es_sword_shield_breton_skin_03_runed_02` | `es_sword_shield_breton_skin_03_runed_02_name` | `units/weapons/player/wpn_emp_gk_sword_02_t1/wpn_emp_gk_sword_02_t1_runed_01` | `units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02_runed_01` | `weapon_skins_lake.lua` |
| Piercer | `wh_fencing_sword_skin_01_runed_02` | `wh_fencing_sword_skin_01_runed_02_name` | `units/weapons/player/wpn_fencingsword_01_t1/wpn_fencingsword_01_t1_runed_01` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2_runed_01` | `weapon_skins.lua` |
| Priest’s Flail & Shield | `wh_flail_shield_skin_01_runed_02` | `wh_flail_shield_skin_01_runed_02_name` | `units/weapons/player/wpn_emp_flail_02_t1/wpn_emp_flail_02_t1_runed_01` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed` | `weapon_skins_bless.lua` |
| Priest’s Paired Skull-splitters | `wh_dual_hammer_skin_01_runed_02` | `wh_dual_hammer_skin_01_runed_02_name` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01_runed` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01_runed` | `weapon_skins_bless.lua` |
| Priest’s Reckoner | `wh_2h_hammer_skin_01_runed_02` | `wh_2h_hammer_skin_01_runed_02_name` | `units/weapons/player/wpn_wh_2h_hammer_01/wpn_wh_2h_hammer_01_runed` | `—` | `weapon_skins_bless.lua` |
| Priest’s Skull-Splitter | `wh_1h_hammer_skin_01_runed_02` | `wh_1h_hammer_skin_01_runed_02_name` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01_runed` | `—` | `weapon_skins_bless.lua` |
| Priest’s Skull-Splitter & Blessed Tome | `wh_hammer_book_skin_01_runed_02` | `wh_hammer_book_skin_01_runed_02_name` | `units/weapons/player/wpn_wh_book_02/wpn_wh_book_02_runed` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01_runed` | `weapon_skins_bless.lua` |
| Priest’s Skull-Splitter & Shield | `wh_hammer_shield_skin_01_runed_02` | `wh_hammer_shield_skin_01_runed_02_name` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01_runed` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed` | `weapon_skins_bless.lua` |
| Rabble Rouser | `es_handgun_skin_02_runed_02` | `es_handgun_skin_02_runed_02_name` | `units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Redemption | `es_1h_flail_skin_05_runed_02` | `es_1h_flail_skin_05_runed_02_name` | `units/weapons/player/wpn_emp_flail_05_t1/wpn_emp_flail_05_t1_runed_01` | `—` | `weapon_skins.lua` |
| Redemptor's Kindrathi | `we_javelin_skin_02_runed_02` | `we_javelin_skin_02_runed_02_name` | `units/weapons/player/wpn_invisible_weapon` | `units/weapons/player/wpn_we_javelin_02/wpn_we_javelin_02_runed` | `weapon_skins_woods.lua` |
| Redemptor's Sariothi | `we_life_staff_skin_02_runed_02` | `we_life_staff_skin_02_runed_02_name` | `—` | `units/weapons/player/wpn_we_life_staff_02/wpn_we_life_staff_02_runed` | `weapon_skins_woods.lua` |
| Roster of the Righteous | `wh_brace_of_pistols_skin_03_runed_02` | `wh_brace_of_pistols_skin_03_runed_02_name` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2_runed_01` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2_runed_01` | `weapon_skins.lua` |
| Skyclaw | `es_longbow_skin_05_runed_02` | `es_longbow_skin_05_runed_02_name` | `—` | `units/weapons/player/wpn_emp_bow_05/wpn_emp_bow_05_runed_01` | `weapon_skins.lua` |
| Slenderatha | `we_dual_dagger_skin_02_runed_02` | `we_dual_dagger_skin_02_runed_02_name` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `weapon_skins.lua` |
| Spear of Renewal | `we_spear_skin_03_runed_02` | `we_spear_skin_03_runed_02_name` | `units/weapons/player/wpn_we_spear_03/wpn_we_spear_03_runed_01` | `—` | `weapon_skins.lua` |
| Steamsmith's Coggrund | `dr_2h_cog_hammer_skin_02_runed_02` | `dr_cog_hammer_skin_02_runed_02_name` | `units/weapons/player/wpn_dw_coghammer_01_t2/wpn_dw_coghammer_01_t2_runed` | `—` | `weapon_skins_cog.lua` |
| Steamsmith's Thrundtak | `dr_steam_pistol_skin_02_runed_02` | `dr_steam_pistol_skin_02_runed_02_name` | `units/weapons/player/wpn_dw_steam_pistol_01_t2/wpn_dw_steam_pistol_01_t2_runed_01` | `—` | `weapon_skins_cog.lua` |
| Thagthrund | `dw_drakegun_skin_03_runed_02` | `dw_drakegun_skin_03_runed_02_name` | `units/weapons/player/wpn_dw_iron_drake_03/wpn_dw_iron_drake_03_runed_01` | `—` | `weapon_skins.lua` |
| The Blessed Blade | `wh_2h_sword_skin_05_runed_02` | `wh_2h_sword_skin_05_runed_02_name` | `units/weapons/player/wpn_empire_2h_sword_05_t1/wpn_2h_sword_05_t1_runed_01` | `—` | `weapon_skins.lua` |
| The Cindermark | `bw_1h_flaming_sword_skin_02_runed_02` | `bw_1h_flaming_sword_skin_02_runed_02_name` | `units/weapons/player/wpn_brw_sword_01_t2/wpn_brw_flaming_sword_01_t2_runed_01` | `—` | `weapon_skins.lua` |
| The Conflagrator | `bw_conflagration_staff_skin_02_runed_02` | `bw_conflagration_staff_skin_02_runed_02_name` | `units/weapons/player/wpn_brw_staff_04/wpn_brw_staff_04_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| The Nuln Reaper | `wh_repeating_pistol_skin_02_runed_02` | `wh_repeating_pistol_skin_02_runed_02_name` | `units/weapons/player/wpn_empire_pistol_repeater/wpn_empire_pistol_repeater_t2_runed_01` | `—` | `weapon_skins.lua` |
| The Sword of Peace | `es_2h_sword_skin_04_runed_02` | `es_2h_sword_skin_04_runed_02_name` | `units/weapons/player/wpn_empire_2h_sword_03_t2/wpn_2h_sword_03_t2_runed_01` | `—` | `weapon_skins.lua` |
| The Vengeful Maid | `es_repeating_handgun_skin_03_runed_02` | `es_repeating_handgun_skin_03_runed_02_name` | `units/weapons/player/wpn_emp_handgun_repeater_t3/wpn_emp_handgun_repeater_t3_runed_01` | `—` | `weapon_skins.lua` |
| The Weight of Duty | `es_2h_hammer_skin_04_runed_02` | `es_2h_hammer_skin_04_runed_02_name` | `units/weapons/player/wpn_empire_2h_hammer_02_t2/wpn_2h_hammer_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Thunderosity | `es_blunderbuss_skin_02_runed_02` | `es_blunderbuss_skin_02_runed_02_name` | `units/weapons/player/wpn_empire_blunderbuss_02_t2/wpn_empire_blunderbuss_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Tormentor's Kindrathi | `we_javelin_skin_01_runed_02` | `we_javelin_skin_01_runed_02_name` | `units/weapons/player/wpn_invisible_weapon` | `units/weapons/player/wpn_we_javelin_01/wpn_we_javelin_01_runed` | `weapon_skins_woods.lua` |
| Tormentor's Sariothi | `we_life_staff_skin_01_runed_02` | `we_life_staff_skin_01_runed_02_name` | `—` | `units/weapons/player/wpn_we_life_staff_01/wpn_we_life_staff_01_runed` | `weapon_skins_woods.lua` |
| Uzkultukaz | `dw_dual_axe_skin_06_runed_02` | `dw_dual_axe_skin_06_runed_02_name` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `weapon_skins.lua` |
| Vengeance Stave | `bw_necromancy_staff_skin_01_runed_02` | `bw_necromancy_staff_skin_01_runed_02_name` | `units/weapons/player/wpn_bw_necromancy_staff_01/wpn_bw_necromancy_staff_01_runed_01` | `units/weapons/player/wpn_invisible_weapon` | `weapon_skins_shovel.lua` |
| Zakiaz Drekmaraz | `dw_crossbow_skin_04_runed_02` | `dw_crossbow_skin_04_runed_02_name` | `—` | `units/weapons/player/wpn_dw_xbow_02_t2/wpn_dw_xbow_02_t2_runed_01` | `weapon_skins.lua` |
| Zondreugi | `dw_2h_hammer_skin_04_runed_02` | `dw_2h_hammer_skin_04_runed_02_name` | `units/weapons/player/wpn_dw_2h_hammer_02_t2/wpn_dw_2h_hammer_02_t2_runed_01` | `—` | `weapon_skins.lua` |

## Veteran skins with `golden_glow` template (25 items)

| Display name | Skin key | Description loc-key | Right unit | Left unit | Source file |
|---|---|---|---|---|---|
| Myrmidia's Axe of the Dawn | `dw_2h_axe_skin_05_runed_03` | `dw_2h_axe_skin_05_runed_03_name` | `units/weapons/player/wpn_dw_2h_axe_03_t1/wpn_dw_2h_axe_03_t1_runed_01` | `—` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Blessing of Dawn's Radiance | `es_1h_sword_shield_skin_03_runed_03` | `es_1h_sword_shield_skin_03_runed_03_name` | `units/weapons/player/wpn_emp_sword_02_t2/wpn_emp_sword_02_t2_runed_01` | `units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Blessing upon Ancestral Axe and Shield | `dw_1h_axe_shield_skin_05_runed_03` | `dw_1h_axe_shield_skin_05_runed_03_name` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05_runed_01` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Crossbow of the Dawn | `wh_crossbow_skin_04_runed_03` | `wh_crossbow_skin_04_runed_03_name` | `—` | `units/weapons/player/wpn_emp_crossbow_03_t2/wpn_emp_crossbow_03_t2_runed_01` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Dagger of the Dawn | `bw_dagger_skin_04_runed_03` | `bw_dagger_skin_04_runed_03_name` | `units/weapons/player/wpn_brw_dagger_04/wpn_brw_dagger_04_runed_01` | `—` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Flail of the Dawn | `es_1h_flail_skin_02_runed_03` | `es_1h_flail_skin_02_runed_03_name` | `units/weapons/player/wpn_emp_flail_02_t1/wpn_emp_flail_02_t1_runed_01` | `—` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Flaming Sword of the Fiery Dawn | `bw_1h_flaming_sword_skin_01_runed_03` | `bw_1h_flaming_sword_skin_01_runed_03_name` | `units/weapons/player/wpn_brw_sword_01_t1/wpn_brw_flaming_sword_01_t1_runed_01` | `—` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Glaive of the Dawn | `we_2h_axe_skin_07_runed_03` | `we_2h_axe_skin_07_runed_03_name` | `units/weapons/player/wpn_we_2h_axe_04_t1/wpn_we_2h_axe_04_t1_runed_01` | `—` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Great Sword of the Dawn | `es_2h_sword_skin_02_runed_03` | `es_2h_sword_skin_02_runed_03_name` | `units/weapons/player/wpn_empire_2h_sword_01_t2/wpn_2h_sword_01_t2_runed_01` | `—` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Handgun of the Dawn | `dw_handgun_skin_02_runed_03` | `dw_handgun_skin_02_runed_03_name` | `units/weapons/player/wpn_dw_handgun_01_t2/wpn_dw_handgun_01_t2_runed_01` | `—` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Longbow of the Dawn | `we_longbow_skin_06_runed_03` | `we_longbow_skin_06_runed_03_name` | `—` | `units/weapons/player/wpn_we_bow_03_t2/wpn_we_bow_03_t2_runed_01` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Rapier of the Dawn and Flintlocks of Righteous Radiance | `wh_fencing_sword_skin_01_runed_03` | `wh_fencing_sword_skin_01_runed_03_name` | `units/weapons/player/wpn_fencingsword_01_t1/wpn_fencingsword_01_t1_runed_01` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2_runed_01` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Spear of the Dawn | `bw_spear_staff_skin_04_runed_03` | `bw_spear_staff_skin_04_runed_03_name` | `units/weapons/player/wpn_brw_spear_staff_04/wpn_brw_spear_staff_04_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Sword and Dagger of the Dawn | `we_dual_sword_dagger_skin_02_runed_03` | `we_dual_sword_dagger_skin_02_runed_03_name` | `units/weapons/player/wpn_we_sword_01_t2/wpn_we_sword_01_t2_runed_01` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia's Volley Gun of the Dawn | `es_repeating_handgun_skin_02_runed_03` | `es_repeating_handgun_skin_02_runed_03_name` | `units/weapons/player/wpn_emp_handgun_repeater_t2/wpn_emp_handgun_repeater_t2_runed_01` | `—` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia’s Axe of the Dawn | `wh_1h_axe_skin_04_runed_03` | `wh_1h_axe_skin_04_runed_03_name` | `units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2_runed_01` | `—` | `weapon_skins_geheimnisnacht_2025.lua` |
| Myrmidia’s Conflagration Staff of the Dawn | `bw_conflagration_staff_skin_02_runed_03` | `bw_conflagration_staff_skin_02_runed_03_name` | `units/weapons/player/wpn_brw_staff_04/wpn_brw_staff_04_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_geheimnisnacht_2025.lua` |
| Myrmidia’s Elven Repeating Crossbow of the Dawn | `we_crossbow_skin_02_runed_03` | `we_crossbow_skin_02_runed_03_name` | `—` | `units/weapons/player/wpn_we_repeater_crossbow_t2/wpn_we_repeater_crossbow_t2_runed_01` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia’s Fireball Staff of the Dawn | `bw_fireball_staff_skin_01_runed_03` | `bw_fireball_staff_skin_01_runed_03_name` | `units/weapons/player/wpn_brw_staff_02/wpn_brw_staff_02_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia’s Greatsword of the Dawn | `we_2h_sword_skin_06_runed_03` | `we_2h_sword_skin_06_runed_03_name` | `units/weapons/player/wpn_we_2h_sword_03_t2/wpn_we_2h_sword_03_t2_runed_01` | `—` | `weapon_skins_geheimnisnacht_2025.lua` |
| Myrmidia’s Grudge-Raker of the Dawn | `dw_grudge_raker_skin_01_runed_03` | `dw_grudge_raker_skin_01_runed_03_name` | `units/weapons/player/wpn_dw_rakegun_t1/wpn_dw_rakegun_t1_runed_01` | `—` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia’s Handgun of the Dawn | `es_handgun_skin_02_runed_03` | `es_handgun_skin_02_runed_03_name` | `units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2_runed_01` | `—` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia’s Repeating Pistol of the Dawn | `wh_repeating_pistol_skin_02_runed_03` | `wh_repeating_pistol_skin_02_runed_03_name` | `units/weapons/player/wpn_empire_pistol_repeater/wpn_empire_pistol_repeater_t2_runed_01` | `—` | `weapon_skins_geheimnisnacht_2021.lua` |
| Myrmidia’s Sword of the Dawn | `es_1h_sword_skin_02_runed_03` | `es_1h_sword_skin_02_runed_03_name` | `units/weapons/player/wpn_emp_sword_02_t2/wpn_emp_sword_02_t2_runed_01` | `—` | `weapon_skins_geheimnisnacht_2025.lua` |
| Myrmidia’s War Pick of the Dawn | `dw_2h_pick_skin_04_runed_03` | `dw_2h_pick_skin_04_runed_03_name` | `units/weapons/player/wpn_dw_pick_01_t4/wpn_dw_pick_01_t4_runed_01` | `—` | `weapon_skins_geheimnisnacht_2025.lua` |

## Veteran skins with `deep_crimson` template (15 items)

| Display name | Skin key | Description loc-key | Right unit | Left unit | Source file |
|---|---|---|---|---|---|
| Crimson Beam Staff | `bw_beam_staff_skin_05_runed_04` | `bw_beam_staff_skin_05_runed_04_name` | `units/weapons/player/wpn_brw_beam_staff_05/wpn_brw_beam_staff_05_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_skulls_2023.lua` |
| Crimson Daggers | `we_dual_dagger_skin_01_runed_04` | `we_dual_dagger_skin_01_runed_04_name` | `units/weapons/player/wpn_we_dagger_01_t1/wpn_we_dagger_01_t1_runed_01` | `units/weapons/player/wpn_we_dagger_01_t1/wpn_we_dagger_01_t1_runed_01` | `weapon_skins_skulls_2023.lua` |
| Crimson Dual Axes | `dw_dual_axe_skin_06_runed_04` | `dw_dual_axe_skin_06_runed_04_name` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `weapon_skins_skulls_2025.lua` |
| Crimson Elven Spear | `we_spear_skin_03_runed_04` | `we_spear_skin_03_runed_04_name` | `units/weapons/player/wpn_we_spear_03/wpn_we_spear_03_runed_01` | `—` | `weapon_skins_skulls_2025.lua` |
| Crimson Falchion | `wh_1h_falchion_skin_02_runed_04` | `wh_1h_falchion_skin_02_runed_04_name` | `units/weapons/player/wpn_emp_sword_04_t2/wpn_emp_sword_04_t2_runed_01` | `—` | `weapon_skins_skulls_2023.lua` |
| Crimson Flamewave Staff | `bw_flamethrower_staff_skin_02_runed_04` | `bw_flamethrower_staff_skin_02_runed_04_name` | `units/weapons/player/wpn_brw_flame_staff_02/wpn_brw_flame_staff_02_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_skulls_2025.lua` |
| Crimson Great Hammer | `es_2h_hammer_skin_04_runed_04` | `es_2h_hammer_skin_04_runed_04_name` | `units/weapons/player/wpn_empire_2h_hammer_02_t2/wpn_2h_hammer_02_t2_runed_01` | `—` | `weapon_skins_skulls_2023.lua` |
| Crimson Greatsword | `es_2h_sword_exe_skin_05_runed_04` | `es_2h_sword_exe_skin_05_runed_04_name` | `units/weapons/player/wpn_emp_sword_exe_05_t1/wpn_emp_sword_exe_05_t1_runed_01` | `—` | `weapon_skins_skulls_2023.lua` |
| Crimson Grudge-Raker | `dw_grudge_raker_skin_02_runed_04` | `dw_grudge_raker_skin_02_runed_04_name` | `units/weapons/player/wpn_dw_rakegun_t2/wpn_dw_rakegun_t2_runed_01` | `—` | `weapon_skins_skulls_2023.lua` |
| Crimson Halberd | `es_halberd_skin_04_runed_04` | `es_halberd_skin_04_runed_04_name` | `units/weapons/player/wpn_wh_halberd_04/wpn_wh_halberd_04_runed_01` | `—` | `weapon_skins_skulls_2025.lua` |
| Crimson Pistols | `wh_brace_of_pistols_skin_05_runed_04` | `wh_brace_of_pistols_skin_05_runed_04_name` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_runed_01` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_runed_01` | `weapon_skins_skulls_2023.lua` |
| Crimson Spellstaff | `bw_fireball_staff_skin_01_runed_04` | `bw_fireball_staff_skin_01_runed_04_name` | `units/weapons/player/wpn_brw_staff_02/wpn_brw_staff_02_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_skulls_2023.lua` |
| Crimson Swift Bow | `we_shortbow_skin_04_runed_04` | `we_shortbow_skin_04_runed_04_name` | `—` | `units/weapons/player/wpn_we_bow_short_04/wpn_we_bow_short_04_runed_01` | `weapon_skins_skulls_2023.lua` |
| Crimson Volley Crossbow | `wh_repeating_crossbow_skin_03_runed_04` | `wh_repeating_crossbow_skin_03_runed_04_name` | `—` | `units/weapons/player/wpn_wh_repeater_crossbow_t3/wpn_wh_repeater_crossbow_t3_runed_01` | `weapon_skins_skulls_2025.lua` |
| Zanthrund | `dw_handgun_skin_02_runed_04` | `dw_handgun_skin_02_runed_04_name` | `units/weapons/player/wpn_dw_handgun_02_t3/wpn_dw_handgun_02_t3_runed_01` | `—` | `weapon_skins_skulls_2023.lua` |

## Veteran skins with `life_green` template (30 items)

| Display name | Skin key | Description loc-key | Right unit | Left unit | Source file |
|---|---|---|---|---|---|
| Eternos-Ichor Beam Staff | `bw_beam_staff_skin_04_runed_05` | `bw_beam_staff_skin_04_runed_05_name` | `units/weapons/player/wpn_brw_beam_staff_04/wpn_brw_beam_staff_04_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_gotwf_2025.lua` |
| Eternos-Ichor Blunderbuss | `es_blunderbuss_skin_02_runed_05` | `es_blunderbuss_skin_02_runed_05_name` | `units/weapons/player/wpn_empire_blunderbuss_02_t2/wpn_empire_blunderbuss_02_t2_runed_01` | `—` | `weapon_skins_gotwf_2024.lua` |
| Eternos-Ichor Bretonnian Longsword | `es_bastard_sword_skin_03_runed_05` | `es_bastard_sword_skin_03_runed_05_name` | `units/weapons/player/wpn_emp_gk_sword_02_t1/wpn_emp_gk_sword_02_t1_runed_01` | `—` | `weapon_skins_gotwf_2024.lua` |
| Eternos-Ichor Briar Javelin | `we_javelin_skin_02_runed_05` | `we_javelin_skin_02_runed_05_name` | `units/weapons/player/wpn_invisible_weapon` | `units/weapons/player/wpn_we_javelin_02/wpn_we_javelin_02_runed` | `weapon_skins_gotwf.lua` |
| Eternos-Ichor Cog Hammer | `dr_2h_cog_hammer_skin_02_runed_05` | `dr_2h_cog_hammer_skin_02_runed_05_name` | `units/weapons/player/wpn_dw_coghammer_01_t2/wpn_dw_coghammer_01_t2_runed` | `—` | `weapon_skins_gotwf_2024.lua` |
| Eternos-Ichor Coruscation Staff | `bw_deus_01_skin_02_runed_05` | `bw_deus_01_skin_02_runed_05_name` | `units/weapons/player/wpn_bw_deus_02/wpn_bw_deus_02_runed` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_gotwf.lua` |
| Eternos-Ichor Crossbow | `wh_crossbow_skin_02_runed_05` | `wh_crossbow_skin_02_runed_05_name` | `—` | `units/weapons/player/wpn_emp_crossbow_02_t2/wpn_emp_crossbow_02_t2_runed_01` | `weapon_skins_gotwf_2024.lua` |
| Eternos-Ichor Deepwood Staff | `we_life_staff_skin_02_runed_05` | `we_life_staff_skin_02_runed_05_name` | `—` | `units/weapons/player/wpn_we_life_staff_02/wpn_we_life_staff_02_runed` | `weapon_skins_gotwf_2024.lua` |
| Eternos-Ichor Drakegun | `dw_drakegun_skin_03_runed_05` | `dw_drakegun_skin_03_runed_05_name` | `units/weapons/player/wpn_dw_iron_drake_03/wpn_dw_iron_drake_03_runed_01` | `—` | `weapon_skins_gotwf_2024.lua` |
| Eternos-Ichor Dreugi | `dw_2h_hammer_skin_01_runed_05` | `dw_2h_hammer_skin_01_runed_05_name` | `units/weapons/player/wpn_dw_2h_hammer_01_t1/wpn_dw_2h_hammer_01_t1_runed_01` | `—` | `weapon_skins_gotwf.lua` |
| Eternos-Ichor Dual Swords | `we_dual_sword_skin_02_runed_05` | `we_dual_sword_skin_02_runed_05_name` | `units/weapons/player/wpn_we_sword_01_t2/wpn_we_sword_01_t2_runed_01` | `units/weapons/player/wpn_we_sword_01_t2/wpn_we_sword_01_t2_runed_01` | `weapon_skins_gotwf_2024.lua` |
| Eternos-Ichor Flame-Sword | `bw_1h_flaming_sword_skin_01_runed_05` | `bw_1h_flaming_sword_skin_01_runed_05_name` | `units/weapons/player/wpn_brw_sword_01_t1/wpn_brw_flaming_sword_01_t1_runed_01` | `—` | `weapon_skins_gotwf.lua` |
| Eternos-Ichor Glaia | `we_dual_dagger_skin_02_runed_05` | `we_dual_dagger_skin_02_runed_05_name` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `weapon_skins_gotwf.lua` |
| Eternos-Ichor Greatsword | `wh_2h_sword_skin_05_runed_05` | `wh_2h_sword_skin_05_runed_05_name` | `units/weapons/player/wpn_empire_2h_sword_05_t1/wpn_2h_sword_05_t1_runed_01` | `—` | `weapon_skins_gotwf_2025.lua` |
| Eternos-Ichor Griffon Foot | `wh_deus_01_skin_03_runed_05` | `wh_deus_01_skin_03_runed_05_name` | `units/weapons/player/wpn_wh_deus_03/wpn_wh_deus_03_runed` | `units/weapons/player/wpn_wh_deus_03/wpn_wh_deus_03_runed` | `weapon_skins_gotwf.lua` |
| Eternos-Ichor Hammer and Shield | `dw_1h_hammer_shield_skin_04_runed_05` | `dw_1h_hammer_shield_skin_04_runed_05_name` | `units/weapons/player/wpn_dw_hammer_02_t2/wpn_dw_hammer_02_t2_runed_01` | `units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02_runed_01` | `weapon_skins_gotwf_2025.lua` |
| Eternos-Ichor Hammer and Tome | `wh_hammer_book_skin_02_runed_05` | `wh_hammer_book_skin_02_runed_05_name` | `units/weapons/player/wpn_wh_book_02/wpn_wh_book_02_runed` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_runed` | `weapon_skins_gotwf_2025.lua` |
| Eternos-Ichor Handgun | `es_handgun_skin_02_runed_05` | `es_handgun_skin_02_runed_05_name` | `units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2_runed_01` | `—` | `weapon_skins_gotwf.lua` |
| Eternos-Ichor Longbow | `es_longbow_skin_04_runed_05` | `es_longbow_skin_04_runed_05_name` | `—` | `units/weapons/player/wpn_emp_bow_04/wpn_emp_bow_04_runed_01` | `weapon_skins_gotwf_2025.lua` |
| Eternos-Ichor Masterwork Pistol | `dr_steam_pistol_skin_02_runed_05` | `dr_steam_pistol_skin_02_runed_05_name` | `units/weapons/player/wpn_dw_steam_pistol_01_t2/wpn_dw_steam_pistol_01_t2_runed_01` | `—` | `weapon_skins_gotwf.lua` |
| Eternos-Ichor Moonfire Bow | `we_deus_01_skin_02_runed_05` | `we_deus_01_skin_02_runed_05_name` | `—` | `units/weapons/player/wpn_we_deus_02/wpn_we_deus_02_runed` | `weapon_skins_gotwf_2025.lua` |
| Eternos-Ichor Pistols | `wh_brace_of_pistols_skin_03_runed_05` | `wh_brace_of_pistols_skin_03_runed_05_name` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2_runed_01` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2_runed_01` | `weapon_skins_gotwf.lua` |
| Eternos-Ichor Reckoner Great Hammer | `wh_2h_hammer_skin_02_runed_05` | `wh_2h_hammer_skin_02_runed_05_name` | `units/weapons/player/wpn_wh_2h_hammer_02/wpn_wh_2h_hammer_02_runed` | `—` | `weapon_skins_gotwf_2024.lua` |
| Eternos-Ichor Scythe | `bw_ghost_scythe_skin_02_runed_05` | `bw_ghost_scythe_skin_02_runed_05_name` | `units/weapons/player/wpn_bw_ghost_scythe_02/wpn_bw_ghost_scythe_02_runed_01` | `—` | `weapon_skins_gotwf_2025.lua` |
| Eternos-Ichor Soulstealer Staff | `bw_necromancy_staff_skin_02_runed_05` | `bw_necromancy_staff_skin_02_runed_05_name` | `units/weapons/player/wpn_bw_necromancy_staff_02/wpn_bw_necromancy_staff_02_runed_01` | `units/weapons/player/wpn_invisible_weapon` | `weapon_skins_gotwf_2024.lua` |
| Eternos-Ichor Spear and Shield | `es_deus_01_skin_01_runed_05` | `es_deus_01_skin_01_runed_05_name` | `units/weapons/player/wpn_es_deus_spear_01/wpn_es_deus_spear_01_runed` | `units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01` | `weapon_skins_gotwf_2025.lua` |
| Eternos-Ichor Sword | `bw_1h_sword_skin_01_runed_05` | `bw_1h_sword_skin_01_runed_05_name` | `units/weapons/player/wpn_brw_sword_01_t1/wpn_brw_sword_01_t1_runed_01` | `—` | `weapon_skins_gotwf_2024.lua` |
| Eternos-Ichor Sword | `we_sword_skin_05_runed_05` | `we_sword_skin_05_runed_05_name` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2_runed_01` | `—` | `weapon_skins_gotwf_2025.lua` |
| Eternos-Ichor Trollhammer Torpedo | `dr_deus_01_skin_03_runed_05` | `dr_deus_01_skin_03_runed_05_name` | `—` | `units/weapons/player/wpn_dr_deus_03/wpn_dr_deus_03_runed` | `weapon_skins_gotwf_2025.lua` |
| Eternos-Ichor Trusty Companions | `es_dual_wield_hammer_sword_skin_02_runed_05` | `es_dual_wield_hammer_sword_skin_02_runed_05_name` | `units/weapons/player/wpn_emp_mace_05_t2/wpn_emp_mace_05_t2_runed_01` | `units/weapons/player/wpn_emp_sword_06_t2/wpn_emp_sword_06_t2_runed_01` | `weapon_skins_gotwf.lua` |

## Veteran skins with `lileath` template (54 items)

| Display name | Skin key | Description loc-key | Right unit | Left unit | Source file |
|---|---|---|---|---|---|
| Axe and Shield of Bitter Dreams | `dw_1h_axe_shield_skin_02_runed_06` | `dw_1h_axe_shield_skin_02_runed_06_name` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02_runed_01` | `weapon_skins_morris_2024.lua` |
| Axe of Bitter Dreams | `dw_1h_axe_skin_07_runed_06` | `dw_1h_axe_skin_07_runed_06_name` | `units/weapons/player/wpn_dw_axe_04_t1/wpn_dw_axe_04_t1_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Axe of Bitter Dreams | `wh_1h_axe_skin_02_runed_06` | `wh_1h_axe_skin_02_runed_06_name` | `units/weapons/player/wpn_axe_02_t2/wpn_axe_02_t2_runed_01` | `—` | `weapon_skins_morris_2024.lua` |
| Beam Staff of Bitter Dreams | `bw_beam_staff_skin_04_runed_06` | `bw_beam_staff_skin_04_runed_06_name` | `units/weapons/player/wpn_brw_beam_staff_04/wpn_brw_beam_staff_04_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris_2025.lua` |
| Blunderbuss of Bitter Dreams | `es_blunderbuss_skin_04_runed_06` | `es_blunderbuss_skin_04_runed_06_name` | `units/weapons/player/wpn_empire_blunderbuss_t2/wpn_empire_blunderbuss_t2_runed_01` | `—` | `weapon_skins_morris_2024.lua` |
| Bolt Staff of Bitter Dreams | `bw_spear_staff_skin_04_runed_06` | `bw_spear_staff_skin_04_runed_06_name` | `units/weapons/player/wpn_brw_spear_staff_04/wpn_brw_spear_staff_04_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris_2024.lua` |
| Conflagration Staff of Bitter Dreams | `bw_conflagration_staff_skin_02_runed_06` | `bw_conflagration_staff_skin_02_runed_06_name` | `units/weapons/player/wpn_brw_staff_04/wpn_brw_staff_04_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris_2024.lua` |
| Crossbow of Bitter Dreams | `dw_crossbow_skin_02_runed_06` | `dw_crossbow_skin_02_runed_06_name` | `—` | `units/weapons/player/wpn_dw_xbow_01_t2/wpn_dw_xbow_01_t2_runed_01` | `weapon_skins_morris_2025.lua` |
| Crossbow of Bitter Dreams | `wh_crossbow_skin_02_runed_06` | `wh_crossbow_skin_02_runed_06_name` | `—` | `units/weapons/player/wpn_emp_crossbow_02_t2/wpn_emp_crossbow_02_t2_runed_01` | `weapon_skins_morris_2025.lua` |
| Dagger of Bitter Dreams | `bw_dagger_skin_03_runed_06` | `bw_dagger_skin_03_runed_06_name` | `units/weapons/player/wpn_brw_dagger_03/wpn_brw_dagger_03_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Daggers of Bitter Dreams | `we_dual_dagger_skin_02_runed_06` | `we_dual_dagger_skin_02_runed_06_name` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `weapon_skins_morris_2024.lua` |
| Drakefire Pistols of Bitter Dreams | `dw_drake_pistol_skin_03_runed_06` | `dw_drake_pistol_skin_03_runed_06_name` | `units/weapons/player/wpn_dw_drake_pistol_02_t1/wpn_dw_drake_pistol_02_t1_runed_01` | `units/weapons/player/wpn_dw_drake_pistol_02_t1/wpn_dw_drake_pistol_02_t1_runed_01` | `weapon_skins_morris_2024.lua` |
| Drakegun of Bitter Dreams | `dw_drakegun_skin_01_runed_06` | `dw_drakegun_skin_01_runed_06_name` | `units/weapons/player/wpn_dw_iron_drake_01/wpn_dw_iron_drake_01_t1_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Dual Axes of Bitter Dreams | `dw_dual_axe_skin_07_runed_06` | `dw_dual_axe_skin_07_runed_06_name` | `units/weapons/player/wpn_dw_axe_04_t1/wpn_dw_axe_04_t1_runed_01` | `units/weapons/player/wpn_dw_axe_04_t1/wpn_dw_axe_04_t1_runed_01` | `weapon_skins_morris_2025.lua` |
| Dual Swords of Bitter Dreams | `we_dual_sword_skin_04_runed_06` | `we_dual_sword_skin_04_runed_06_name` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1_runed_01` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1_runed_01` | `weapon_skins_morris_2025.lua` |
| Executioner Sword of Bitter Dreams | `es_2h_sword_exe_skin_04_runed_06` | `es_2h_sword_exe_skin_04_runed_06_name` | `units/weapons/player/wpn_emp_sword_exe_04_t1/wpn_emp_sword_exe_04_t1_runed_01` | `—` | `weapon_skins_morris_2024.lua` |
| Falchion of Bitter Dreams | `wh_1h_falchion_skin_01_runed_06` | `wh_1h_falchion_skin_01_runed_06_name` | `units/weapons/player/wpn_emp_sword_04_t1/wpn_emp_sword_04_t1_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Fireball Staff of Bitter Dreams | `bw_fireball_staff_skin_01_runed_06` | `bw_fireball_staff_skin_01_runed_06_name` | `units/weapons/player/wpn_brw_staff_02/wpn_brw_staff_02_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris_2025.lua` |
| Flail of Bitter Dreams | `es_1h_flail_skin_05_runed_06` | `es_1h_flail_skin_05_runed_06_name` | `units/weapons/player/wpn_emp_flail_05_t1/wpn_emp_flail_05_t1_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Flame Sword of Bitter Dreams | `bw_1h_flaming_sword_skin_01_runed_06` | `bw_1h_flaming_sword_skin_01_runed_06_name` | `units/weapons/player/wpn_brw_sword_01_t1/wpn_brw_flaming_sword_01_t1_runed_01` | `—` | `weapon_skins_morris_2024.lua` |
| Flamestorm Staff of Bitter Dreams | `bw_flamethrower_staff_skin_05_runed_06` | `bw_flamethrower_staff_skin_05_runed_06_name` | `units/weapons/player/wpn_brw_flame_staff_05/wpn_brw_flame_staff_05_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris_2024.lua` |
| Glaive of Bitter Dreams | `we_2h_axe_skin_05_runed_06` | `we_2h_axe_skin_05_runed_06_name` | `units/weapons/player/wpn_we_2h_axe_03_t1/wpn_we_2h_axe_03_t1_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Great Axe of Bitter Dreams | `dw_2h_axe_skin_06_runed_06` | `dw_2h_axe_skin_06_runed_06_name` | `units/weapons/player/wpn_dw_2h_axe_03_t2/wpn_dw_2h_axe_03_t2_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Great Hammer of Bitter Dreams | `dw_2h_hammer_skin_04_runed_06` | `dw_2h_hammer_skin_04_runed_06_name` | `units/weapons/player/wpn_dw_2h_hammer_02_t2/wpn_dw_2h_hammer_02_t2_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Great Hammer of Bitter Dreams | `es_2h_hammer_skin_06_runed_06` | `es_2h_hammer_skin_06_runed_06_name` | `units/weapons/player/wpn_empire_2h_hammer_03_t2/wpn_2h_hammer_03_t2_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Greatsword of Bitter Dreams | `es_2h_sword_skin_04_runed_06` | `es_2h_sword_skin_04_runed_06_name` | `units/weapons/player/wpn_empire_2h_sword_03_t2/wpn_2h_sword_03_t2_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Greatsword of Bitter Dreams | `we_2h_sword_skin_05_runed_06` | `we_2h_sword_skin_05_runed_06_name` | `units/weapons/player/wpn_we_2h_sword_03_t1/wpn_we_2h_sword_03_t1_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Greatsword of Bitter Dreams | `wh_2h_sword_skin_02_runed_06` | `wh_2h_sword_skin_02_runed_06_name` | `units/weapons/player/wpn_empire_2h_sword_02_t2/wpn_2h_sword_02_t2_runed_01` | `—` | `weapon_skins_morris_2024.lua` |
| Grudge-raker of Bitter Dreams | `dw_grudge_raker_skin_01_runed_06` | `dw_grudge_raker_skin_01_runed_06_name` | `units/weapons/player/wpn_dw_rakegun_t1/wpn_dw_rakegun_t1_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Hagbane Bow of Bitter Dreams | `we_hagbane_skin_04_runed_06` | `we_hagbane_skin_04_runed_06_name` | `—` | `units/weapons/player/wpn_we_bow_short_04/wpn_we_bow_short_04_runed_01` | `weapon_skins_morris_2024.lua` |
| Halberd of Bitter Dreams | `es_halberd_skin_04_runed_06` | `es_halberd_skin_04_runed_06_name` | `units/weapons/player/wpn_wh_halberd_04/wpn_wh_halberd_04_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Hammer and Shield of Bitter Dreams | `dw_1h_hammer_shield_skin_02_runed_06` | `dw_1h_hammer_shield_skin_02_runed_06_name` | `units/weapons/player/wpn_dw_hammer_01_t2/wpn_dw_hammer_01_t2_runed_01` | `units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02_runed_01` | `weapon_skins_morris_2025.lua` |
| Hammer of Bitter Dreams | `dw_1h_hammer_skin_02_runed_06` | `dw_1h_hammer_skin_02_runed_06_name` | `units/weapons/player/wpn_dw_hammer_01_t2/wpn_dw_hammer_01_t2_runed_01` | `—` | `weapon_skins_morris_2024.lua` |
| Handgun of Bitter Dreams | `dw_handgun_skin_02_runed_06` | `dw_handgun_skin_02_runed_06_name` | `units/weapons/player/wpn_dw_handgun_01_t2/wpn_dw_handgun_01_t2_runed_01` | `—` | `weapon_skins_morris_2024.lua` |
| Handgun of Bitter Dreams | `es_handgun_skin_01_runed_06` | `es_handgun_skin_01_runed_06_name` | `units/weapons/player/wpn_empire_handgun_02_t1/wpn_empire_handgun_02_t1_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Longbow of Bitter Dreams | `es_longbow_skin_05_runed_06` | `es_longbow_skin_05_runed_06_name` | `—` | `units/weapons/player/wpn_emp_bow_05/wpn_emp_bow_05_runed_01` | `weapon_skins_morris_2024.lua` |
| Longbow of Bitter Dreams | `we_longbow_skin_06_runed_06` | `we_longbow_skin_06_runed_06_name` | `—` | `units/weapons/player/wpn_we_bow_03_t2/wpn_we_bow_03_t2_runed_01` | `weapon_skins_morris_2024.lua` |
| Mace and Shield of Bitter Dreams | `es_1h_mace_shield_skin_02_runed_06` | `es_1h_mace_shield_skin_02_runed_06_name` | `units/weapons/player/wpn_emp_mace_02_t2/wpn_emp_mace_02_t2_runed_01` | `units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01` | `weapon_skins_morris_2024.lua` |
| Mace of Bitter Dreams | `bw_1h_mace_skin_05_runed_06` | `bw_1h_mace_skin_05_runed_06_name` | `units/weapons/player/wpn_brw_mace_05/wpn_brw_mace_05_runed_01` | `—` | `weapon_skins_morris_2024.lua` |
| Mace of Bitter Dreams | `es_1h_mace_skin_02_runed_06` | `es_1h_mace_skin_02_runed_06_name` | `units/weapons/player/wpn_emp_mace_02_t2/wpn_emp_mace_02_t2_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Pistols of Bitter Dreams | `wh_brace_of_pistols_skin_05_runed_06` | `wh_brace_of_pistols_skin_05_runed_06_name` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_runed_01` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_runed_01` | `weapon_skins_morris_2024.lua` |
| Rapier of Bitter Dreams | `wh_fencing_sword_skin_01_runed_06` | `wh_fencing_sword_skin_01_runed_06_name` | `units/weapons/player/wpn_fencingsword_01_t1/wpn_fencingsword_01_t1_runed_01` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2_runed_01` | `weapon_skins_morris_2024.lua` |
| Repeater Pistol of Bitter Dreams | `wh_repeating_pistol_skin_04_runed_06` | `wh_repeating_pistol_skin_04_runed_06_name` | `units/weapons/player/wpn_empire_pistol_repeater_02/wpn_empire_pistol_repeater_02_t1_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Repeating Handgun of Bitter Dreams | `es_repeating_handgun_skin_02_runed_06` | `es_repeating_handgun_skin_02_runed_06_name` | `units/weapons/player/wpn_emp_handgun_repeater_t2/wpn_emp_handgun_repeater_t2_runed_01` | `—` | `weapon_skins_morris_2024.lua` |
| Shortbow of Bitter Dreams | `we_shortbow_skin_01_runed_06` | `we_shortbow_skin_01_runed_06_name` | `—` | `units/weapons/player/wpn_we_bow_short_01/wpn_we_bow_short_01_runed_01` | `weapon_skins_morris_2025.lua` |
| Spear of Bitter Dreams | `we_spear_skin_04_runed_06` | `we_spear_skin_04_runed_06_name` | `units/weapons/player/wpn_we_spear_04/wpn_we_spear_04_runed_01` | `—` | `weapon_skins_morris_2024.lua` |
| Sword and Dagger of Bitter Dreams | `we_dual_sword_dagger_skin_02_runed_06` | `we_dual_sword_dagger_skin_02_runed_06_name` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1_runed_01` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `weapon_skins_morris_2025.lua` |
| Sword and Shield of Bitter Dreams | `es_1h_sword_shield_skin_02_runed_06` | `es_1h_sword_shield_skin_02_runed_06_name` | `units/weapons/player/wpn_emp_sword_02_t2/wpn_emp_sword_02_t2_runed_01` | `units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01` | `weapon_skins_morris_2025.lua` |
| Sword of Bitter Dreams | `bw_1h_sword_skin_02_runed_06` | `bw_1h_sword_skin_02_runed_06_name` | `units/weapons/player/wpn_brw_sword_01_t2/wpn_brw_sword_01_t2_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Sword of Bitter Dreams | `es_1h_sword_skin_01_runed_06` | `es_1h_sword_skin_01_runed_06_name` | `units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Sword of Bitter Dreams | `we_sword_skin_04_runed_06` | `we_sword_skin_04_runed_06_name` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1_runed_01` | `—` | `weapon_skins_morris_2025.lua` |
| Volley Crossbow of Bitter Dreams | `we_crossbow_skin_03_runed_06` | `we_crossbow_skin_03_runed_06_name` | `—` | `units/weapons/player/wpn_we_repeater_crossbow_t3/wpn_we_repeater_crossbow_t3_runed_01` | `weapon_skins_morris_2024.lua` |
| Volley Crossbow of Bitter Dreams | `wh_repeating_crossbow_skin_03_runed_06` | `wh_repeating_crossbow_skin_03_runed_06_name` | `—` | `units/weapons/player/wpn_wh_repeater_crossbow_t3/wpn_wh_repeater_crossbow_t3_runed_01` | `weapon_skins_morris_2024.lua` |
| War Pick of Bitter Dreams | `dw_2h_pick_skin_03_runed_06` | `dw_2h_pick_skin_03_runed_06_name` | `units/weapons/player/wpn_dw_pick_01_t3/wpn_dw_pick_01_t3_runed_01` | `—` | `weapon_skins_morris_2024.lua` |

## Veteran skins with `versus` template (83 items)

| Display name | Skin key | Description loc-key | Right unit | Left unit | Source file |
|---|---|---|---|---|---|
| Shyish-Infused Axe | `dw_1h_axe_skin_04_magic_02` | `dw_1h_axe_skin_04_magic_02_name` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Axe | `wh_1h_axe_skin_06_magic_02` | `wh_1h_axe_skin_06_magic_02_name` | `units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Axe and Falchion | `wh_dual_wield_axe_falchion_skin_01_magic_02` | `wh_dual_wield_axe_falchion_skin_01_magic_02_name` | `units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2_magic_01` | `units/weapons/player/wpn_emp_sword_05_t2/wpn_emp_sword_05_t2_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Axe and Shield | `dw_1h_axe_shield_skin_04_magic_02` | `dw_1h_axe_shield_skin_04_magic_02_name` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2_magic_01` | `units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Beam Staff | `bw_beam_staff_skin_02_magic_02` | `bw_beam_staff_skin_02_magic_02_name` | `units/weapons/player/wpn_brw_beam_staff_02/wpn_brw_beam_staff_02_magic_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Bill Hook | `wh_2h_billhook_skin_02_magic_02` | `wh_2h_billhook_skin_02_magic_02_name` | `units/weapons/player/wpn_wh_billhook_02/wpn_wh_billhook_02_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Blunderbuss | `es_blunderbuss_skin_01_magic_02` | `es_blunderbuss_skin_01_magic_02_name` | `units/weapons/player/wpn_empire_blunderbuss_02_t1/wpn_empire_blunderbuss_02_t1_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Bolt Staff | `bw_spear_staff_skin_05_magic_02` | `bw_spear_staff_skin_05_magic_02_name` | `units/weapons/player/wpn_brw_spear_staff_05/wpn_brw_spear_staff_05_magic_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Brace of Pistols | `wh_brace_of_pistols_skin_05_magic_02` | `wh_brace_of_pistols_skin_05_magic_02_name` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_magic_01` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Bretonnian Longsword | `es_bastard_sword_skin_04_magic_02` | `es_bastard_sword_skin_04_magic_02_name` | `units/weapons/player/wpn_emp_gk_sword_02_t2/wpn_emp_gk_sword_02_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Bretonnian Sword and Shield | `es_sword_shield_breton_skin_04_magic_02` | `es_sword_shield_breton_skin_04_magic_02_name` | `units/weapons/player/wpn_emp_gk_sword_02_t2/wpn_emp_gk_sword_02_t2_magic_01` | `units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Cog Hammer | `dr_2h_cog_hammer_skin_02_magic_02` | `dr_2h_cog_hammer_skin_02_magic_02_name` | `units/weapons/player/wpn_dw_coghammer_01_t2/wpn_dw_coghammer_01_t2_magic` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Conflagration Staff | `bw_conflagration_staff_skin_01_magic_02` | `bw_conflagration_staff_skin_01_magic_02_name` | `units/weapons/player/wpn_brw_staff_03/wpn_brw_staff_03_magic_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Coruscation Staff | `bw_deus_skin_02_magic_02` | `bw_deus_skin_02_magic_02_name` | `units/weapons/player/wpn_bw_deus_02/wpn_bw_deus_02_magic` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Crossbow | `dw_crossbow_skin_03_magic_02` | `dw_crossbow_skin_03_magic_02_name` | `—` | `units/weapons/player/wpn_dw_xbow_02_t1/wpn_dw_xbow_02_t1_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Crossbow | `we_crossbow_skin_01_magic_02` | `we_crossbow_skin_01_magic_02_name` | `—` | `units/weapons/player/wpn_we_repeater_crossbow_t1/wpn_we_repeater_crossbow_t1_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Crossbow | `wh_crossbow_skin_06_magic_02` | `wh_crossbow_skin_06_magic_02_name` | `—` | `units/weapons/player/wpn_empire_crossbow_t2/wpn_empire_crossbow_tier2_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Crowbill | `bw_1h_crowbill_skin_01_magic_02` | `bw_1h_crowbill_skin_01_magic_02_name` | `units/weapons/player/wpn_brw_crowbill_01/wpn_brw_crowbill_01_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Dagger | `bw_dagger_skin_02_magic_02` | `bw_dagger_skin_02_magic_02_name` | `units/weapons/player/wpn_brw_dagger_02/wpn_brw_dagger_02_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Drakefire Pistols | `dw_drake_pistol_skin_01_magic_02` | `dw_drake_pistol_skin_01_magic_02_name` | `units/weapons/player/wpn_dw_drake_pistol_01_t1/wpn_dw_drake_pistol_01_t1_magic_01` | `units/weapons/player/wpn_dw_drake_pistol_01_t1/wpn_dw_drake_pistol_01_t1_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Drakegun | `dw_drakegun_skin_02_magic_02` | `dw_drakegun_skin_02_magic_02_name` | `units/weapons/player/wpn_dw_iron_drake_02/wpn_dw_iron_drake_02_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Dual Axes | `dw_dual_axe_skin_04_magic_02` | `dw_dual_axe_skin_04_magic_02_name` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2_magic_01` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Dual Daggers | `we_dual_dagger_skin_07_magic_02` | `we_dual_dagger_skin_07_magic_02_name` | `units/weapons/player/wpn_we_dagger_03_t2/wpn_we_dagger_03_t2_magic_01` | `units/weapons/player/wpn_we_dagger_03_t2/wpn_we_dagger_03_t2_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Dual Hammers | `dr_dual_wield_hammers_skin_01_magic_02` | `dr_dual_wield_hammers_skin_01_magic_02_name` | `units/weapons/player/wpn_dw_hammer_02_t1/wpn_dw_hammer_02_t1_magic_01` | `units/weapons/player/wpn_dw_hammer_02_t1/wpn_dw_hammer_02_t1_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Dual Swords | `we_dual_sword_skin_06_magic_02` | `we_dual_sword_skin_06_magic_02_name` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1_magic_01` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Elven Axe | `we_1h_axe_skin_02_magic_02` | `we_1h_axe_skin_02_magic_02_name` | `units/weapons/player/wpn_we_axe_03_t2/wpn_we_axe_03_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Elven Spear | `we_spear_skin_02_magic_02` | `we_spear_skin_02_magic_02_name` | `units/weapons/player/wpn_we_spear_02/wpn_we_spear_02_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Ensorcelled Reaper | `bw_ghost_scythe_skin_02_magic_02` | `bw_ghost_scythe_skin_02_magic_02_name` | `units/weapons/player/wpn_bw_ghost_scythe_02/wpn_bw_ghost_scythe_02_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Executioner Sword | `es_2h_sword_exe_skin_03_magic_02` | `es_2h_sword_exe_skin_03_magic_02_name` | `units/weapons/player/wpn_emp_sword_exe_03_t1/wpn_emp_sword_exe_03_t1_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Falchion | `wh_1h_falchion_skin_04_magic_02` | `wh_1h_falchion_skin_04_magic_02_name` | `units/weapons/player/wpn_emp_sword_05_t2/wpn_emp_sword_05_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Fireball Staff | `bw_fireball_staff_skin_02_magic_02` | `bw_fireball_staff_skin_02_magic_02_name` | `units/weapons/player/wpn_brw_staff_05/wpn_brw_staff_05_magic_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Flail | `es_1h_flail_skin_04_magic_02` | `es_1h_flail_skin_04_magic_02_name` | `units/weapons/player/wpn_emp_flail_04_t1/wpn_emp_flail_04_t1_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Flail and Shield | `wh_flail_shield_skin_02_magic_02` | `wh_flail_shield_skin_02_magic_02_name` | `units/weapons/player/wpn_emp_flail_04_t1/wpn_emp_flail_04_t1_magic_01` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_magic` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Flamewave Staff | `bw_flamethrower_staff_skin_04_magic_02` | `bw_flamethrower_staff_skin_04_magic_02_name` | `units/weapons/player/wpn_brw_flame_staff_04/wpn_brw_flame_staff_04_magic_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Flaming Flail | `bw_1h_flail_flaming_skin_02_magic_02` | `bw_1h_flail_flaming_skin_02_magic_02_name` | `units/weapons/player/wpn_brw_flaming_flail_02/wpn_brw_flaming_flail_02_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Flaming Sword | `bw_1h_flaming_sword_skin_06_magic_02` | `bw_1h_flaming_sword_skin_06_magic_02_name` | `units/weapons/player/wpn_brw_sword_03_t2/wpn_brw_flaming_sword_03_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Glaive | `we_2h_axe_skin_03_magic_02` | `we_2h_axe_skin_03_magic_02_name` | `units/weapons/player/wpn_we_2h_axe_02_t1/wpn_we_2h_axe_02_t1_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Great Axe | `dw_2h_axe_skin_02_magic_02` | `dw_2h_axe_skin_02_magic_02_name` | `units/weapons/player/wpn_dw_2h_axe_01_t2/wpn_dw_2h_axe_01_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Great Hammer | `dw_2h_hammer_skin_03_magic_02` | `dw_2h_hammer_skin_03_magic_02_name` | `units/weapons/player/wpn_dw_2h_hammer_02_t1/wpn_dw_2h_hammer_02_t1_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Great Hammer | `wh_2h_hammer_skin_02_magic_02` | `wh_2h_hammer_skin_02_magic_02_name` | `units/weapons/player/wpn_wh_2h_hammer_02/wpn_wh_2h_hammer_02_magic` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Great Sword | `wh_2h_sword_skin_04_magic_02` | `wh_2h_sword_skin_04_magic_02_name` | `units/weapons/player/wpn_empire_2h_sword_04_t2/wpn_2h_sword_04_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Greatsword | `es_2h_sword_skin_03_magic_02` | `es_2h_sword_skin_03_magic_02_name` | `units/weapons/player/wpn_empire_2h_sword_03_t1/wpn_2h_sword_03_t1_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Griffon-Foot | `wh_deus_skin_02_magic_02` | `wh_deus_skin_02_magic_02_name` | `units/weapons/player/wpn_wh_deus_02/wpn_wh_deus_02_magic` | `units/weapons/player/wpn_wh_deus_02/wpn_wh_deus_02_magic` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Grudge-Raker | `dw_grudge_raker_skin_03_magic_02` | `dw_grudge_raker_skin_03_magic_02_name` | `units/weapons/player/wpn_dw_rakegun_t3/wpn_dw_rakegun_t3_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Hagbane Shortbow | `we_shortbow_hagbane_skin_02_magic_02` | `we_shortbow_hagbane_skin_02_magic_02_name` | `—` | `units/weapons/player/wpn_we_bow_short_02/wpn_we_bow_short_02_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Halberd | `es_halberd_skin_03_magic_02` | `es_halberd_skin_03_magic_02_name` | `units/weapons/player/wpn_wh_halberd_03/wpn_wh_halberd_03_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Hammer | `dw_1h_hammer_skin_03_magic_02` | `dw_1h_hammer_skin_03_magic_02_name` | `units/weapons/player/wpn_dw_hammer_02_t1/wpn_dw_hammer_02_t1_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Hammer and Shield | `dw_1h_hammer_shield_skin_04_magic_02` | `dw_1h_hammer_shield_skin_04_magic_02_name` | `units/weapons/player/wpn_dw_hammer_02_t1/wpn_dw_hammer_02_t1_magic_01` | `units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Handgun | `dw_handgun_skin_03_magic_02` | `dw_handgun_skin_03_magic_02_name` | `units/weapons/player/wpn_dw_handgun_02_t1/wpn_dw_handgun_02_t1_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Handgun | `es_handgun_skin_02_magic_02` | `es_handgun_skin_02_magic_02_name` | `units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Javelin | `we_javelin_skin_02_magic_02` | `we_javelin_skin_02_magic_02_name` | `units/weapons/player/wpn_invisible_weapon` | `units/weapons/player/wpn_we_javelin_02/wpn_we_javelin_02_magic` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Life Staff | `we_life_staff_skin_02_magic_02` | `we_life_staff_skin_02_magic_02_name` | `—` | `units/weapons/player/wpn_we_life_staff_02/wpn_we_life_staff_02_magic` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Longbow | `es_longbow_skin_04_magic_02` | `es_longbow_skin_04_magic_02_name` | `—` | `units/weapons/player/wpn_emp_bow_04/wpn_emp_bow_04_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Longbow | `we_longbow_skin_02_magic_02` | `we_longbow_skin_02_magic_02_name` | `—` | `units/weapons/player/wpn_we_bow_01_t2/wpn_we_bow_01_t2_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Longsword | `es_1h_sword_skin_04_magic_02` | `es_1h_sword_skin_04_magic_02_name` | `units/weapons/player/wpn_emp_sword_03_t2/wpn_emp_sword_03_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Mace | `bw_1h_mace_skin_02_magic_02` | `bw_1h_mace_skin_02_magic_02_name` | `units/weapons/player/wpn_brw_mace_02/wpn_brw_mace_02_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Mace | `es_1h_mace_skin_05_magic_02` | `es_1h_mace_skin_05_magic_02_name` | `units/weapons/player/wpn_emp_mace_03_t2/wpn_emp_mace_03_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Mace and Shield | `es_1h_mace_shield_skin_04_magic_02` | `es_1h_mace_shield_skin_04_magic_02_name` | `units/weapons/player/wpn_emp_mace_03_t2/wpn_emp_mace_03_t2_magic_01` | `units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Mace and Sword | `es_dual_wield_hammer_sword_skin_02_magic_02` | `es_dual_wield_hammer_sword_skin_02_magic_02_name` | `units/weapons/player/wpn_emp_mace_04_t3/wpn_emp_mace_04_t3_magic_01` | `units/weapons/player/wpn_emp_sword_06_t2/wpn_emp_sword_06_t2_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Masterwork Pistol | `dr_steam_pistol_skin_02_magic_02` | `dr_steam_pistol_skin_02_magic_02_name` | `units/weapons/player/wpn_dw_steam_pistol_01_t2/wpn_dw_steam_pistol_01_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Moonfire Bow | `we_deus_skin_01_magic_02` | `we_deus_skin_01_magic_02_name` | `—` | `units/weapons/player/wpn_we_deus_01/wpn_we_deus_01_magic` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Paired Skull-Splitters | `wh_dual_hammer_skin_02_magic_02` | `wh_dual_hammer_skin_02_magic_02_name` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_magic` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_magic` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Rapier | `wh_fencing_sword_skin_07_magic_02` | `wh_fencing_sword_skin_07_magic_02_name` | `units/weapons/player/wpn_fencingsword_04_t2/wpn_fencingsword_04_t2_magic_01` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Repeated Pistol | `wh_repeating_pistol_skin_05_magic_02` | `wh_repeating_pistol_skin_05_magic_02_name` | `units/weapons/player/wpn_empire_pistol_repeater_02/wpn_empire_pistol_repeater_02_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Repeating Handgun | `es_repeating_handgun_skin_01_magic_02` | `es_repeating_handgun_skin_01_magic_02_name` | `units/weapons/player/wpn_emp_handgun_repeater_t1/wpn_emp_handgun_repeater_t1_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Skull-Splitter and Blessed Tome | `wh_hammer_book_skin_02_magic_02` | `wh_hammer_book_skin_02_magic_02_name` | `units/weapons/player/wpn_wh_book_02/wpn_wh_book_02_magic` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_magic` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Skull-Splitter and Shield | `wh_hammer_shield_skin_02_magic_02` | `wh_hammer_shield_skin_02_magic_02_name` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_magic` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_magic` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Skull-Splitter Hammer | `wh_1h_hammer_skin_02_magic_02` | `wh_1h_hammer_skin_02_magic_02_name` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_magic` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Soulstealer Staff | `bw_necromancy_staff_skin_02_magic_02` | `bw_necromancy_staff_skin_02_magic_02_name` | `units/weapons/player/wpn_bw_necromancy_staff_02/wpn_bw_necromancy_staff_02_magic_01` | `units/weapons/player/wpn_invisible_weapon` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Spear | `es_2h_heavy_spear_skin_02_magic_02` | `es_2h_heavy_spear_skin_02_magic_02_name` | `units/weapons/player/wpn_emp_boar_spear_02/wpn_emp_boar_spear_02_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Spear and Shield | `es_deus_skin_02_magic_02` | `es_deus_skin_02_magic_02_name` | `units/weapons/player/wpn_es_deus_spear_02/wpn_es_deus_spear_02_magic` | `units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Spear and Shield | `we_1h_spears_shield_skin_02_magic_02` | `we_1h_spears_shield_skin_02_magic_02_name` | `units/weapons/player/wpn_we_spear_02/wpn_we_spear_02_magic_01` | `units/weapons/player/wpn_we_shield_02/wpn_we_shield_02_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Swift Bow | `we_shortbow_skin_02_magic_02` | `we_shortbow_skin_02_magic_02_name` | `—` | `units/weapons/player/wpn_we_bow_short_02/wpn_we_bow_short_02_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Sword | `bw_1h_sword_skin_06_magic_02` | `bw_1h_sword_skin_06_magic_02_name` | `units/weapons/player/wpn_brw_sword_03_t2/wpn_brw_sword_03_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Sword | `we_sword_skin_06_magic_02` | `we_sword_skin_06_magic_02_name` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Sword and Dagger | `we_dual_sword_dagger_skin_07_magic_02` | `we_dual_sword_dagger_skin_07_magic_02_name` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1_magic_01` | `units/weapons/player/wpn_we_dagger_03_t2/wpn_we_dagger_03_t2_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Sword and Shield | `es_1h_sword_shield_skin_04_magic_02` | `es_1h_sword_shield_skin_04_magic_02_name` | `units/weapons/player/wpn_emp_sword_03_t2/wpn_emp_sword_03_t2_magic_01` | `units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Throwing Axes | `dr_1h_throwing_axes_skin_02_magic_02` | `dr_1h_throwing_axes_skin_02_magic_02_name` | `units/weapons/player/wpn_invisible_weapon` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Trollhammer Torpedo | `dr_deus_skin_02_magic_02` | `dr_deus_skin_02_magic_02_name` | `—` | `units/weapons/player/wpn_dr_deus_02/wpn_dr_deus_02_magic` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Two-Handed Sword | `we_2h_sword_skin_08_magic_02` | `we_2h_sword_skin_08_magic_02_name` | `units/weapons/player/wpn_we_2h_sword_04_t2/wpn_we_2h_sword_04_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Volley Crossbow | `wh_repeating_crossbow_skin_02_magic_02` | `wh_repeating_crossbow_skin_02_magic_02_name` | `—` | `units/weapons/player/wpn_wh_repeater_crossbow_t2/wpn_wh_repeater_crossbow_t2_magic_01` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused War Pick | `dw_2h_pick_skin_02_magic_02` | `dw_2h_pick_skin_02_magic_02_name` | `units/weapons/player/wpn_dw_pick_01_t2/wpn_dw_pick_01_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |
| Shyish-Infused Warhammer | `es_2h_hammer_skin_02_magic_02` | `es_2h_hammer_skin_02_magic_02_name` | `units/weapons/player/wpn_empire_2h_hammer_01_t2/wpn_2h_hammer_01_t2_magic_01` | `—` | `weapon_skins_versus_rewards.lua` |

## Veteran skins with `white_glow` template (1 items)

| Display name | Skin key | Description loc-key | Right unit | Left unit | Source file |
|---|---|---|---|---|---|
| Nornaz | `deus_dw_1h_axe_skin_06_runed_02_white` | `dw_1h_axe_skin_06_runed_02_name` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `—` | `weapon_skins_morris.lua` |

## Veteran skins with NO glow template — "Stylish" colloquial (153 items)

These items have `rarity = "unique"` but no `material_settings_name`. Visual = baked unit emission only.
Each typically pairs with a `_runed_02` sibling (same unit, `purple_glow` template, different display name).

| Display name | Skin key | Right unit | Left unit | Source file |
|---|---|---|---|---|
| Absolver | `wh_1h_axe_skin_04_runed_01` | `units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2_runed_01` | `—` | `weapon_skins.lua` |
| Alabrin Stragaz | `dw_1h_axe_skin_07_runed_01` | `units/weapons/player/wpn_dw_axe_04_t1/wpn_dw_axe_04_t1_runed_01` | `—` | `weapon_skins.lua` |
| Aqshy's Generous Servant | `bw_flamethrower_staff_skin_02_runed_01` | `units/weapons/player/wpn_brw_flame_staff_02/wpn_brw_flame_staff_02_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Aqshy's Lament | `bw_deus_01_skin_02_runed` | `units/weapons/player/wpn_bw_deus_02/wpn_bw_deus_02_runed` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris.lua` |
| Araflane's Daughters | `we_dual_sword_dagger_skin_04_runed_01` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1_runed_01` | `units/weapons/player/wpn_we_dagger_01_t1/wpn_we_dagger_01_t1_runed_01` | `weapon_skins.lua` |
| Ariel's Breath | `we_hagbane_skin_04_runed_01` | `—` | `units/weapons/player/wpn_we_bow_short_04/wpn_we_bow_short_04_runed_01` | `weapon_skins.lua` |
| Azamarkarinaz | `dw_1h_axe_shield_skin_05_runed_01` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05_runed_01` | `weapon_skins.lua` |
| Baron Brech's Beauty | `es_2h_sword_skin_02_runed_01` | `units/weapons/player/wpn_empire_2h_sword_01_t2/wpn_2h_sword_01_t2_runed_01` | `—` | `weapon_skins.lua` |
| Baron Shrak's Pride | `wh_brace_of_pistols_skin_03_runed_01` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2_runed_01` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2_runed_01` | `weapon_skins.lua` |
| Bitterbreath | `we_crossbow_skin_02_runed_01` | `—` | `units/weapons/player/wpn_we_repeater_crossbow_t2/wpn_we_repeater_crossbow_t2_runed_01` | `weapon_skins.lua` |
| Blackbrook Blade | `es_1h_sword_skin_01_runed_01` | `units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1_runed_01` | `—` | `weapon_skins.lua` |
| Blaze Reaper | `bw_ghost_scythe_skin_02_runed_01` | `units/weapons/player/wpn_bw_ghost_scythe_02/wpn_bw_ghost_scythe_02_runed_01` | `—` | `weapon_skins_shovel.lua` |
| Bleakhollow Locus | `bw_necromancy_staff_skin_02_runed_01` | `units/weapons/player/wpn_bw_necromancy_staff_02/wpn_bw_necromancy_staff_02_runed_01` | `units/weapons/player/wpn_invisible_weapon` | `weapon_skins_shovel.lua` |
| Bleakwood Kindrathi | `we_javelin_skin_02_runed_01` | `units/weapons/player/wpn_invisible_weapon` | `units/weapons/player/wpn_we_javelin_02/wpn_we_javelin_02_runed` | `weapon_skins_woods.lua` |
| Bleakwood Sariothi | `we_life_staff_skin_02_runed_01` | `—` | `units/weapons/player/wpn_we_life_staff_02/wpn_we_life_staff_02_runed` | `weapon_skins_woods.lua` |
| Bloodreaper | `we_crossbow_skin_03_runed_01` | `—` | `units/weapons/player/wpn_we_repeater_crossbow_t3/wpn_we_repeater_crossbow_t3_runed_01` | `weapon_skins.lua` |
| Boppity Stick | `bw_1h_mace_skin_01_runed_01` | `units/weapons/player/wpn_brw_mace_01/wpn_brw_mace_01_runed_01` | `—` | `weapon_skins.lua` |
| Bozdokaz Az-Dreugi | `dw_2h_axe_skin_06_runed_01` | `units/weapons/player/wpn_dw_2h_axe_03_t2/wpn_dw_2h_axe_03_t2_runed_01` | `—` | `weapon_skins.lua` |
| Bugritbok | `dr_deus_01_skin_02_runed` | `—` | `units/weapons/player/wpn_dr_deus_02/wpn_dr_deus_02_runed` | `weapon_skins_morris.lua` |
| Bugritbok | `dr_deus_01_skin_03_runed` | `—` | `units/weapons/player/wpn_dr_deus_03/wpn_dr_deus_03_runed` | `weapon_skins_morris.lua` |
| Cadai-galand | `we_deus_01_skin_02_runed` | `—` | `units/weapons/player/wpn_we_deus_02/wpn_we_deus_02_runed` | `weapon_skins_morris.lua` |
| Callach's Cursed Blades | `we_dual_sword_dagger_skin_02_runed_01` | `units/weapons/player/wpn_we_sword_01_t2/wpn_we_sword_01_t2_runed_01` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `weapon_skins.lua` |
| Chain of Office | `es_1h_flail_skin_05_runed_01` | `units/weapons/player/wpn_emp_flail_05_t1/wpn_emp_flail_05_t1_runed_01` | `—` | `weapon_skins.lua` |
| Champion's Longbow | `es_longbow_skin_05_runed_01` | `—` | `units/weapons/player/wpn_emp_bow_05/wpn_emp_bow_05_runed_01` | `weapon_skins.lua` |
| Count Schmidt's Mauler | `es_1h_mace_skin_02_runed_01` | `units/weapons/player/wpn_emp_mace_02_t2/wpn_emp_mace_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Counterfeit Ghal Maraz | `es_2h_hammer_skin_06_runed_01` | `units/weapons/player/wpn_empire_2h_hammer_03_t2/wpn_2h_hammer_03_t2_runed_01` | `—` | `weapon_skins.lua` |
| Dagger of Aqshy | `bw_dagger_skin_03_runed_01` | `units/weapons/player/wpn_brw_dagger_03/wpn_brw_dagger_03_runed_01` | `—` | `weapon_skins.lua` |
| Dantov's Guard | `es_deus_01_skin_02_runed` | `units/weapons/player/wpn_es_deus_spear_02/wpn_es_deus_spear_02_runed` | `units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_runed` | `weapon_skins_morris.lua` |
| Daraz Karagmaraz | `dw_2h_pick_skin_04_runed_01` | `units/weapons/player/wpn_dw_pick_01_t4/wpn_dw_pick_01_t4_runed_01` | `—` | `weapon_skins.lua` |
| Deathbringer | `wh_repeating_pistol_skin_02_runed_01` | `units/weapons/player/wpn_empire_pistol_repeater/wpn_empire_pistol_repeater_t2_runed_01` | `—` | `weapon_skins.lua` |
| Defender of the Reik | `wh_2h_sword_skin_02_runed_01` | `units/weapons/player/wpn_empire_2h_sword_02_t2/wpn_2h_sword_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Defiance and Destiny | `es_dual_wield_hammer_sword_skin_02_runed_01` | `units/weapons/player/wpn_emp_mace_05_t2/wpn_emp_mace_05_t2_runed_01` | `units/weapons/player/wpn_emp_sword_06_t2/wpn_emp_sword_06_t2_runed_01` | `weapon_skins_paperweight.lua` |
| Dire-Weave | `we_hagbane_skin_01_runed_01` | `—` | `units/weapons/player/wpn_we_bow_short_01/wpn_we_bow_short_01_runed_01` | `weapon_skins.lua` |
| Dokcoggrund | `dr_2h_cog_hammer_skin_01_runed_01` | `units/weapons/player/wpn_dw_coghammer_01_t1/wpn_dw_coghammer_01_t1_runed` | `—` | `weapon_skins_cog.lua` |
| Dorkdrengi Tukaz | `dw_dual_axe_skin_07_runed_01` | `units/weapons/player/wpn_dw_axe_04_t1/wpn_dw_axe_04_t1_runed_01` | `units/weapons/player/wpn_dw_axe_04_t1/wpn_dw_axe_04_t1_runed_01` | `weapon_skins.lua` |
| Drakkdrengi Tukaz | `dw_dual_axe_skin_06_runed_01` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `weapon_skins.lua` |
| Dream and Nightmare | `we_dual_sword_skin_05_runed_01` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2_runed_01` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2_runed_01` | `weapon_skins.lua` |
| Dronak Ginit-Barag | `dw_grudge_raker_skin_02_runed_01` | `units/weapons/player/wpn_dw_rakegun_t2/wpn_dw_rakegun_t2_runed_01` | `—` | `weapon_skins.lua` |
| Drungirorkaz | `dw_grudge_raker_skin_01_runed_01` | `units/weapons/player/wpn_dw_rakegun_t1/wpn_dw_rakegun_t1_runed_01` | `—` | `weapon_skins.lua` |
| Edrael's Will | `we_shortbow_skin_01_runed_01` | `—` | `units/weapons/player/wpn_we_bow_short_01/wpn_we_bow_short_01_runed_01` | `weapon_skins.lua` |
| Effinghast's Striker | `es_1h_mace_shield_skin_03_runed_01` | `units/weapons/player/wpn_emp_mace_02_t2/wpn_emp_mace_02_t2_runed_01` | `units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01` | `weapon_skins.lua` |
| Eldritch Reaper | `bw_ghost_scythe_skin_01_runed_01` | `units/weapons/player/wpn_bw_ghost_scythe_01/wpn_bw_ghost_scythe_01_runed_01` | `—` | `weapon_skins_shovel.lua` |
| Elector's Burden | `es_1h_flail_skin_02_runed_01` | `units/weapons/player/wpn_emp_flail_02_t1/wpn_emp_flail_02_t1_runed_01` | `—` | `weapon_skins.lua` |
| Elgimarazok | `dw_crossbow_skin_04_runed_01` | `—` | `units/weapons/player/wpn_dw_xbow_02_t2/wpn_dw_xbow_02_t2_runed_01` | `weapon_skins.lua` |
| Elvarin's Rod of Destruction | `bw_deus_01_skin_01_runed` | `units/weapons/player/wpn_bw_deus_01/wpn_bw_deus_01_runed` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris.lua` |
| Endbringer | `we_2h_axe_skin_05_runed_01` | `units/weapons/player/wpn_we_2h_axe_03_t1/wpn_we_2h_axe_03_t1_runed_01` | `—` | `weapon_skins.lua` |
| Evergreen Reaver | `we_1h_axe_skin_02_runed_01` | `units/weapons/player/wpn_we_axe_03_t1/wpn_we_axe_03_t1_runed_01` | `—` | `weapon_skins_paperweight.lua` |
| Feuerbach's Last Word | `bw_fireball_staff_skin_01_runed_01` | `units/weapons/player/wpn_brw_staff_02/wpn_brw_staff_02_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Feuerbach's Rapper | `bw_1h_mace_skin_05_runed_01` | `units/weapons/player/wpn_brw_mace_05/wpn_brw_mace_05_runed_01` | `—` | `weapon_skins.lua` |
| Flamesword of the Elder Fleissman | `bw_1h_flaming_sword_skin_01_runed_01` | `units/weapons/player/wpn_brw_sword_01_t1/wpn_brw_flaming_sword_01_t1_runed_01` | `—` | `weapon_skins.lua` |
| Flamesword of the Younger Fleissman | `bw_1h_flaming_sword_skin_02_runed_01` | `units/weapons/player/wpn_brw_sword_01_t2/wpn_brw_flaming_sword_01_t2_runed_01` | `—` | `weapon_skins.lua` |
| Flammen's Retort | `bw_1h_crowbill_skin_02_runed_01` | `units/weapons/player/wpn_brw_crowbill_02/wpn_brw_crowbill_02_runed_01` | `—` | `weapon_skins_paperweight.lua` |
| Frostfiend | `we_deus_01_skin_03_runed` | `—` | `units/weapons/player/wpn_we_deus_03/wpn_we_deus_03_runed` | `weapon_skins_morris.lua` |
| Furisome Flame-Stave | `bw_flamethrower_staff_skin_05_runed_01` | `units/weapons/player/wpn_brw_flame_staff_05/wpn_brw_flame_staff_05_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Ghullaz Az-Dreugi | `dw_2h_axe_skin_05_runed_01` | `units/weapons/player/wpn_dw_2h_axe_03_t1/wpn_dw_2h_axe_03_t1_runed_01` | `—` | `weapon_skins.lua` |
| Gilded Glory | `es_halberd_skin_04_runed_01` | `units/weapons/player/wpn_wh_halberd_04/wpn_wh_halberd_04_runed_01` | `—` | `weapon_skins.lua` |
| Glam's Laughing Blades | `we_dual_sword_skin_04_runed_01` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1_runed_01` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1_runed_01` | `weapon_skins.lua` |
| Goldgather | `es_2h_sword_skin_04_runed_01` | `units/weapons/player/wpn_empire_2h_sword_03_t2/wpn_2h_sword_03_t2_runed_01` | `—` | `weapon_skins.lua` |
| Grauber's Arms | `es_deus_01_skin_01_runed` | `units/weapons/player/wpn_es_deus_spear_01/wpn_es_deus_spear_01_runed` | `units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01` | `weapon_skins_morris.lua` |
| Grimm's Hand-Taker | `wh_1h_falchion_skin_01_runed_01` | `units/weapons/player/wpn_emp_sword_04_t1/wpn_emp_sword_04_t1_runed_01` | `—` | `weapon_skins.lua` |
| Grobbok | `dr_deus_01_skin_01_runed` | `—` | `units/weapons/player/wpn_dr_deus_01/wpn_dr_deus_01_runed` | `weapon_skins_morris.lua` |
| Grundalaz Karaz-Skaud | `dw_1h_hammer_shield_skin_04_runed_01` | `units/weapons/player/wpn_dw_hammer_02_t2/wpn_dw_hammer_02_t2_runed_01` | `units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05_runed_01` | `weapon_skins.lua` |
| Grungni's Vengeance | `dr_dual_wield_hammers_skin_02_runed_01` | `units/weapons/player/wpn_dw_hammer_01_t2/wpn_dw_hammer_01_t2_runed_01` | `units/weapons/player/wpn_dw_hammer_01_t2/wpn_dw_hammer_01_t2_runed_01` | `weapon_skins_paperweight.lua` |
| Grungron Grund | `dw_1h_hammer_skin_02_runed_01` | `units/weapons/player/wpn_dw_hammer_01_t2/wpn_dw_hammer_01_t2_runed_01` | `—` | `weapon_skins.lua` |
| Gustgleam | `bw_1h_sword_skin_02_runed_01` | `units/weapons/player/wpn_brw_sword_01_t2/wpn_brw_sword_01_t2_runed_01` | `—` | `weapon_skins.lua` |
| Harmony and Discord | `we_dual_sword_dagger_skin_05_runed_01` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2_runed_01` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `weapon_skins.lua` |
| Hazkhalaz Skrundaz | `dw_2h_pick_skin_03_runed_01` | `units/weapons/player/wpn_dw_pick_01_t3/wpn_dw_pick_01_t3_runed_01` | `—` | `weapon_skins.lua` |
| Helmgart's Roar | `es_blunderbuss_skin_04_runed_01` | `units/weapons/player/wpn_empire_blunderbuss_t2/wpn_empire_blunderbuss_t2_runed_01` | `—` | `weapon_skins.lua` |
| Infused Immolator of Itza | `bw_beam_staff_skin_04_runed_01` | `units/weapons/player/wpn_brw_beam_staff_04/wpn_brw_beam_staff_04_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Initiate’s Flail & Shield | `wh_flail_shield_skin_01_runed_01` | `units/weapons/player/wpn_emp_flail_02_t1/wpn_emp_flail_02_t1_runed_01` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed` | `weapon_skins_bless.lua` |
| Initiate’s Reckoner | `wh_2h_hammer_skin_01_runed_01` | `units/weapons/player/wpn_wh_2h_hammer_01/wpn_wh_2h_hammer_01_runed` | `—` | `weapon_skins_bless.lua` |
| Initiate’s Skull-Splitter | `wh_1h_hammer_skin_01_runed_01` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01_runed` | `—` | `weapon_skins_bless.lua` |
| Innovator's Coggrund | `dr_2h_cog_hammer_skin_02_runed_01` | `units/weapons/player/wpn_dw_coghammer_01_t2/wpn_dw_coghammer_01_t2_runed` | `—` | `weapon_skins_cog.lua` |
| Innovator's Thrundtak | `dr_steam_pistol_skin_02_runed_01` | `units/weapons/player/wpn_dw_steam_pistol_01_t2/wpn_dw_steam_pistol_01_t2_runed_01` | `—` | `weapon_skins_cog.lua` |
| Kaia's Stormsword | `we_sword_skin_04_runed_01` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1_runed_01` | `—` | `weapon_skins.lua` |
| Karaz Gift | `es_bastard_sword_skin_03_runed_01` | `units/weapons/player/wpn_emp_gk_sword_02_t1/wpn_emp_gk_sword_02_t1_runed_01` | `—` | `weapon_skins_lake.lua` |
| Karugromthiaz Karinaz | `dw_1h_axe_shield_skin_02_runed_01` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02_runed_01` | `weapon_skins.lua` |
| Katalhuyk | `dw_drakegun_skin_01_runed_01` | `units/weapons/player/wpn_dw_iron_drake_01/wpn_dw_iron_drake_01_t1_runed_01` | `—` | `weapon_skins.lua` |
| Katha's Funeral Swords | `we_dual_sword_skin_02_runed_01` | `units/weapons/player/wpn_we_sword_01_t2/wpn_we_sword_01_t2_runed_01` | `units/weapons/player/wpn_we_sword_01_t2/wpn_we_sword_01_t2_runed_01` | `weapon_skins.lua` |
| Kell's Vanguard | `es_1h_mace_shield_skin_02_runed_01` | `units/weapons/player/wpn_emp_mace_02_t2/wpn_emp_mace_02_t2_runed_01` | `units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01` | `weapon_skins.lua` |
| Kellerman's Arms | `es_deus_01_skin_03_runed` | `units/weapons/player/wpn_es_deus_spear_03/wpn_es_deus_spear_03_runed` | `units/weapons/player/wpn_es_deus_shield_03/wpn_es_deus_shield_03_runed` | `weapon_skins_morris.lua` |
| Lamenter's Kindrathi | `we_javelin_skin_01_runed_01` | `units/weapons/player/wpn_invisible_weapon` | `units/weapons/player/wpn_we_javelin_01/wpn_we_javelin_01_runed` | `weapon_skins_woods.lua` |
| Lamenter's Sariothi | `we_life_staff_skin_01_runed_01` | `—` | `units/weapons/player/wpn_we_life_staff_01/wpn_we_life_staff_01_runed` | `weapon_skins_woods.lua` |
| Leopold's Favourite | `es_1h_sword_shield_skin_02_runed_01` | `units/weapons/player/wpn_emp_sword_02_t2/wpn_emp_sword_02_t2_runed_01` | `units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01` | `weapon_skins.lua` |
| Lhunegal Alabrinaz | `dw_1h_axe_skin_06_runed_01` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01` | `—` | `weapon_skins.lua` |
| Lothlann's Woebringer | `we_2h_axe_skin_07_runed_01` | `units/weapons/player/wpn_we_2h_axe_04_t1/wpn_we_2h_axe_04_t1_runed_01` | `—` | `weapon_skins.lua` |
| Luthor Flamestrike's Letter Opener | `bw_dagger_skin_05_runed_01` | `units/weapons/player/wpn_brw_dagger_05/wpn_brw_dagger_05_runed_01` | `—` | `weapon_skins.lua` |
| Madman's Conduit | `bw_deus_01_skin_03_runed` | `units/weapons/player/wpn_bw_deus_03/wpn_bw_deus_03_runed` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris.lua` |
| Marietta's Molten Massacre | `bw_beam_staff_skin_05_runed_01` | `units/weapons/player/wpn_brw_beam_staff_05/wpn_brw_beam_staff_05_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Mercy and Carnage | `we_dual_dagger_skin_02_runed_01` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2_runed_01` | `weapon_skins.lua` |
| Nornak Drakktuk | `dw_drake_pistol_skin_04_runed_01` | `units/weapons/player/wpn_dw_drake_pistol_02_t2/wpn_dw_drake_pistol_02_t2_runed_01` | `units/weapons/player/wpn_dw_drake_pistol_02_t2/wpn_dw_drake_pistol_02_t2_runed_01` | `weapon_skins.lua` |
| Oblivion | `we_2h_sword_skin_06_runed_01` | `units/weapons/player/wpn_we_2h_sword_03_t2/wpn_we_2h_sword_03_t2_runed_01` | `—` | `weapon_skins.lua` |
| Old (Mostly) Faithful | `es_blunderbuss_skin_02_runed_01` | `units/weapons/player/wpn_empire_blunderbuss_02_t2/wpn_empire_blunderbuss_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Otto Hieder's Never-Miss Mechanism | `es_handgun_skin_02_runed_01` | `units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Ravensblade | `wh_1h_falchion_skin_02_runed_01` | `units/weapons/player/wpn_emp_sword_04_t2/wpn_emp_sword_04_t2_runed_01` | `—` | `weapon_skins.lua` |
| Rhuni Drakktuk | `dw_drake_pistol_skin_03_runed_01` | `units/weapons/player/wpn_dw_drake_pistol_02_t1/wpn_dw_drake_pistol_02_t1_runed_01` | `units/weapons/player/wpn_dw_drake_pistol_02_t1/wpn_dw_drake_pistol_02_t1_runed_01` | `weapon_skins.lua` |
| Rhunkiaz Grund | `dw_1h_hammer_skin_04_runed_01` | `units/weapons/player/wpn_dw_hammer_02_t2/wpn_dw_hammer_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Rikaz Grundreugi | `dw_2h_hammer_skin_01_runed_01` | `units/weapons/player/wpn_dw_2h_hammer_01_t1/wpn_dw_2h_hammer_01_t1_runed_01` | `—` | `weapon_skins.lua` |
| Rinnaz Grundreugi | `dw_2h_hammer_skin_04_runed_01` | `units/weapons/player/wpn_dw_2h_hammer_02_t2/wpn_dw_2h_hammer_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Rod of Resplendent Ruin | `bw_conflagration_staff_skin_02_runed_01` | `units/weapons/player/wpn_brw_staff_04/wpn_brw_staff_04_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Sable Shield of Parandot | `es_sword_shield_breton_skin_03_runed_01` | `units/weapons/player/wpn_emp_gk_sword_02_t1/wpn_emp_gk_sword_02_t1_runed_01` | `units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02_runed_01` | `weapon_skins_lake.lua` |
| Scarloc's Longbow | `we_longbow_skin_06_runed_01` | `—` | `units/weapons/player/wpn_we_bow_03_t2/wpn_we_bow_03_t2_runed_01` | `weapon_skins.lua` |
| Sceolan's Eye-Thieves | `we_dual_dagger_skin_01_runed_01` | `units/weapons/player/wpn_we_dagger_01_t1/wpn_we_dagger_01_t1_runed_01` | `units/weapons/player/wpn_we_dagger_01_t1/wpn_we_dagger_01_t1_runed_01` | `weapon_skins.lua` |
| Scuttlestaff | `bw_necromancy_staff_skin_01_runed_01` | `units/weapons/player/wpn_bw_necromancy_staff_01/wpn_bw_necromancy_staff_01_runed_01` | `units/weapons/player/wpn_invisible_weapon` | `weapon_skins_shovel.lua` |
| Sheenstrike | `bw_dagger_skin_04_runed_01` | `units/weapons/player/wpn_brw_dagger_04/wpn_brw_dagger_04_runed_01` | `—` | `weapon_skins.lua` |
| Spear of the Everglades | `we_spear_skin_03_runed_01` | `units/weapons/player/wpn_we_spear_03/wpn_we_spear_03_runed_01` | `—` | `weapon_skins.lua` |
| Spear of Tirsyth | `we_spear_skin_04_runed_01` | `units/weapons/player/wpn_we_spear_04/wpn_we_spear_04_runed_01` | `—` | `weapon_skins.lua` |
| Spite-Tongue | `we_shortbow_skin_04_runed_01` | `—` | `units/weapons/player/wpn_we_bow_short_04/wpn_we_bow_short_04_runed_01` | `weapon_skins.lua` |
| Sword of the Forsaken Hero | `we_2h_sword_skin_05_runed_01` | `units/weapons/player/wpn_we_2h_sword_03_t1/wpn_we_2h_sword_03_t1_runed_01` | `—` | `weapon_skins.lua` |
| The Bastion | `es_1h_sword_shield_skin_03_runed_01` | `units/weapons/player/wpn_emp_sword_02_t2/wpn_emp_sword_02_t2_runed_01` | `units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01` | `weapon_skins.lua` |
| The Bögenhafen Banger | `es_handgun_skin_01_runed_01` | `units/weapons/player/wpn_empire_handgun_02_t1/wpn_empire_handgun_02_t1_runed_01` | `—` | `weapon_skins.lua` |
| The Carroburg Honour-Blade | `es_2h_sword_exe_skin_04_runed_01` | `units/weapons/player/wpn_emp_sword_exe_04_t1/wpn_emp_sword_exe_04_t1_runed_01` | `—` | `weapon_skins.lua` |
| The Doom of Anmyr | `we_sword_skin_05_runed_01` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| The Griffon's Roar | `es_repeating_handgun_skin_03_runed_01` | `units/weapons/player/wpn_emp_handgun_repeater_t3/wpn_emp_handgun_repeater_t3_runed_01` | `—` | `weapon_skins.lua` |
| The Judge's Mark | `wh_repeating_crossbow_skin_03_runed_01` | `—` | `units/weapons/player/wpn_wh_repeater_crossbow_t3/wpn_wh_repeater_crossbow_t3_runed_01` | `weapon_skins.lua` |
| The Reiksmarshal's Great Leveller | `es_2h_hammer_skin_04_runed_01` | `units/weapons/player/wpn_empire_2h_hammer_02_t2/wpn_2h_hammer_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| The Runic Ruinator | `bw_spear_staff_skin_04_runed_01` | `units/weapons/player/wpn_brw_spear_staff_04/wpn_brw_spear_staff_04_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| The Vanquisher | `wh_crossbow_skin_04_runed_01` | `—` | `units/weapons/player/wpn_emp_crossbow_03_t2/wpn_emp_crossbow_03_t2_runed_01` | `weapon_skins.lua` |
| The Voice of Lileath | `we_deus_01_skin_01_runed` | `—` | `units/weapons/player/wpn_we_deus_01/wpn_we_deus_01_runed` | `weapon_skins_morris.lua` |
| Theogonist’s Reckoner | `wh_2h_hammer_skin_02_runed_01` | `units/weapons/player/wpn_wh_2h_hammer_02/wpn_wh_2h_hammer_02_runed` | `—` | `weapon_skins_bless.lua` |
| Theogonist’s Skull-Splitter | `wh_1h_hammer_skin_02_runed_01` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_runed` | `—` | `weapon_skins_bless.lua` |
| Theogonist’s Skull-Splitter & Shield | `wh_hammer_shield_skin_02_runed_01` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_runed` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed` | `weapon_skins_bless.lua` |
| Throngdrengiaz Karingrund | `dw_1h_hammer_shield_skin_02_runed_01` | `units/weapons/player/wpn_dw_hammer_01_t2/wpn_dw_hammer_01_t2_runed_01` | `units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02_runed_01` | `weapon_skins.lua` |
| Thrynthrag | `dw_handgun_skin_02_runed_01` | `units/weapons/player/wpn_dw_handgun_01_t2/wpn_dw_handgun_01_t2_runed_01` | `—` | `weapon_skins.lua` |
| Urbarthrundtak | `dr_steam_pistol_skin_01_runed_01` | `units/weapons/player/wpn_dw_steam_pistol_01_t1/wpn_dw_steam_pistol_01_t1_runed_01` | `—` | `weapon_skins_cog.lua` |
| Van Hal's Executioner | `wh_2h_sword_skin_05_runed_01` | `units/weapons/player/wpn_empire_2h_sword_05_t1/wpn_2h_sword_05_t1_runed_01` | `—` | `weapon_skins.lua` |
| Vengrynaz Drekmaraz | `dw_crossbow_skin_02_runed_01` | `—` | `units/weapons/player/wpn_dw_xbow_01_t2/wpn_dw_xbow_01_t2_runed_01` | `weapon_skins.lua` |
| Vinereaver | `we_sword_skin_02_runed_01` | `units/weapons/player/wpn_we_sword_01_t2/wpn_we_sword_01_t2_runed_01` | `—` | `weapon_skins.lua` |
| Volans' Failed Experiment | `bw_spear_staff_skin_02_runed_01` | `units/weapons/player/wpn_brw_spear_staff_02/wpn_brw_spear_staff_02_runed_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Von Kraddock's Judge | `wh_1h_axe_skin_02_runed_01` | `units/weapons/player/wpn_axe_02_t2/wpn_axe_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Von Mecklenburg's Revenge | `es_2h_sword_exe_skin_05_runed_01` | `units/weapons/player/wpn_emp_sword_exe_05_t1/wpn_emp_sword_exe_05_t1_runed_01` | `—` | `weapon_skins.lua` |
| Von Meinkopt's Whirligig of Death | `es_repeating_handgun_skin_02_runed_01` | `units/weapons/player/wpn_emp_handgun_repeater_t2/wpn_emp_handgun_repeater_t2_runed_01` | `—` | `weapon_skins.lua` |
| Von Tarnus' Last Gift | `bw_1h_sword_skin_01_runed_01` | `units/weapons/player/wpn_brw_sword_01_t1/wpn_brw_sword_01_t1_runed_01` | `—` | `weapon_skins.lua` |
| Weave-bound Kindrathi | `we_javelin_skin_02_magic_01` | `units/weapons/player/wpn_invisible_weapon` | `units/weapons/player/wpn_we_javelin_02/wpn_we_javelin_02_magic` | `weapon_skins_woods.lua` |
| Weave-bound Sariothi | `we_life_staff_skin_02_magic_01` | `—` | `units/weapons/player/wpn_we_life_staff_02/wpn_we_life_staff_02_magic` | `weapon_skins_woods.lua` |
| Weave-Reign Blades | `we_dual_sword_dagger_skin_01_runed_01` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2_runed_01` | `units/weapons/player/wpn_we_dagger_01_t1/wpn_we_dagger_01_t1_runed_01` | `weapon_skins.lua` |
| Wernigoth's Arming Sword | `es_1h_sword_skin_02_runed_01` | `units/weapons/player/wpn_emp_sword_02_t2/wpn_emp_sword_02_t2_runed_01` | `—` | `weapon_skins.lua` |
| Zarazaz Kantuzthrag | `dw_handgun_skin_05_runed_01` | `units/weapons/player/wpn_dw_handgun_02_t3/wpn_dw_handgun_02_t3_runed_01` | `—` | `weapon_skins.lua` |
| Zharrstromez | `dw_drakegun_skin_03_runed_01` | `units/weapons/player/wpn_dw_iron_drake_03/wpn_dw_iron_drake_03_runed_01` | `—` | `weapon_skins.lua` |
| _(name unresolved)_ | `wh_brace_of_pistols_skin_05_runed_01` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_runed_01` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_runed_01` | `weapon_skins.lua` |
| _(name unresolved)_ | `wh_crossbow_skin_02_runed_01` | `—` | `units/weapons/player/wpn_emp_crossbow_02_t2/wpn_emp_crossbow_02_t2_runed_01` | `weapon_skins.lua` |
| _(name unresolved)_ | `wh_deus_01_skin_01_runed` | `units/weapons/player/wpn_wh_deus_01/wpn_wh_deus_01_runed` | `units/weapons/player/wpn_wh_deus_01/wpn_wh_deus_01_runed` | `weapon_skins_morris.lua` |
| _(name unresolved)_ | `wh_deus_01_skin_02_runed` | `units/weapons/player/wpn_wh_deus_02/wpn_wh_deus_02_runed` | `units/weapons/player/wpn_wh_deus_02/wpn_wh_deus_02_runed` | `weapon_skins_morris.lua` |
| _(name unresolved)_ | `wh_deus_01_skin_03_runed` | `units/weapons/player/wpn_wh_deus_03/wpn_wh_deus_03_runed` | `units/weapons/player/wpn_wh_deus_03/wpn_wh_deus_03_runed` | `weapon_skins_morris.lua` |
| _(name unresolved)_ | `wh_dual_hammer_skin_01_runed_01` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01_runed` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01_runed` | `weapon_skins_bless.lua` |
| _(name unresolved)_ | `wh_dual_hammer_skin_02_runed_01` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_runed` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_runed` | `weapon_skins_bless.lua` |
| _(name unresolved)_ | `wh_dual_wield_axe_falchion_skin_02_runed_01` | `units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2_runed_01` | `units/weapons/player/wpn_emp_sword_04_t2/wpn_emp_sword_04_t2_runed_01` | `weapon_skins_paperweight.lua` |
| _(name unresolved)_ | `wh_fencing_sword_skin_01_runed_01` | `units/weapons/player/wpn_fencingsword_01_t1/wpn_fencingsword_01_t1_runed_01` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2_runed_01` | `weapon_skins.lua` |
| _(name unresolved)_ | `wh_flail_shield_skin_02_runed_01` | `units/weapons/player/wpn_emp_flail_05_t1/wpn_emp_flail_05_t1_runed_01` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed` | `weapon_skins_bless.lua` |
| _(name unresolved)_ | `wh_hammer_book_skin_01_runed_01` | `units/weapons/player/wpn_wh_book_02/wpn_wh_book_02_runed` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01_runed` | `weapon_skins_bless.lua` |
| _(name unresolved)_ | `wh_hammer_book_skin_02_runed_01` | `units/weapons/player/wpn_wh_book_02/wpn_wh_book_02_runed` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_runed` | `weapon_skins_bless.lua` |
| _(name unresolved)_ | `wh_hammer_shield_skin_01_runed_01` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01_runed` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed` | `weapon_skins_bless.lua` |
| _(name unresolved)_ | `wh_repeating_pistol_skin_04_runed_01` | `units/weapons/player/wpn_empire_pistol_repeater_02/wpn_empire_pistol_repeater_02_t1_runed_01` | `—` | `weapon_skins.lua` |

---

## Lower-rarity skins (no glow templates ever apply)

These rarities never have `material_settings_name` set. Listed compactly for completeness.

### `exotic` (137 items)

| Display name | Skin key | Right unit | Left unit | Source file |
|---|---|---|---|---|
| Adept's Flame-Sword | `bw_1h_flaming_sword_skin_03` | `units/weapons/player/wpn_brw_sword_02_t1/wpn_brw_flaming_sword_02_t1` | `—` | `weapon_skins.lua` |
| Adept's Sword | `bw_1h_sword_skin_03` | `units/weapons/player/wpn_brw_sword_02_t1/wpn_brw_sword_02_t1` | `—` | `weapon_skins.lua` |
| Adjudicator's Axe | `wh_1h_axe_skin_03` | `units/weapons/player/wpn_axe_03_t1/wpn_axe_03_t1` | `—` | `weapon_skins.lua` |
| Ambusher's Ceyl | `we_sword_skin_06` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1` | `—` | `weapon_skins.lua` |
| Ambusher's Draich | `we_2h_sword_skin_04` | `units/weapons/player/wpn_we_2h_sword_02_t2/wpn_we_2h_sword_02_t2` | `—` | `weapon_skins.lua` |
| Ambusher's Khelthrax | `we_2h_axe_skin_04` | `units/weapons/player/wpn_we_2h_axe_02_t2/wpn_we_2h_axe_02_t2` | `—` | `weapon_skins.lua` |
| Ambusher's Nastirrath | `we_longbow_skin_04` | `—` | `units/weapons/player/wpn_we_bow_02_t2/wpn_we_bow_02_t2` | `weapon_skins.lua` |
| Antlersong | `we_longbow_skin_06` | `—` | `units/weapons/player/wpn_we_bow_03_t2/wpn_we_bow_03_t2` | `weapon_skins.lua` |
| Aqshy's Cut | `bw_1h_flaming_sword_skin_08` | `units/weapons/player/wpn_brw_sword_04_t2/wpn_brw_flaming_sword_04_t2` | `—` | `weapon_skins.lua` |
| Asrai's Tally | `we_2h_sword_skin_08` | `units/weapons/player/wpn_we_2h_sword_04_t2/wpn_we_2h_sword_04_t2` | `—` | `weapon_skins.lua` |
| Atylwyth Longbow | `we_longbow_skin_08` | `—` | `units/weapons/player/wpn_we_bow_04_t2/wpn_we_bow_04_t2` | `weapon_skins.lua` |
| Aunty Bessie | `es_handgun_skin_05` | `units/weapons/player/wpn_empire_handgun_t3/wpn_empire_handgun_t3` | `—` | `weapon_skins.lua` |
| Bane of Greenskins | `es_2h_sword_skin_02` | `units/weapons/player/wpn_empire_2h_sword_01_t2/wpn_2h_sword_01_t2` | `—` | `weapon_skins.lua` |
| Bane of Heretics | `wh_1h_axe_skin_04` | `units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2` | `—` | `weapon_skins.lua` |
| Bann's Amazing Boltcaster | `bw_spear_staff_skin_04` | `units/weapons/player/wpn_brw_spear_staff_04/wpn_brw_spear_staff_04` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Barak Maraz | `dw_1h_hammer_skin_05` | `units/weapons/player/wpn_dw_hammer_03_t1/wpn_dw_hammer_03_t1` | `—` | `weapon_skins.lua` |
| Battleblade | `es_1h_sword_skin_04` | `units/weapons/player/wpn_emp_sword_03_t2/wpn_emp_sword_03_t2` | `—` | `weapon_skins.lua` |
| Battlebriar | `we_2h_sword_skin_06` | `units/weapons/player/wpn_we_2h_sword_03_t2/wpn_we_2h_sword_03_t2` | `—` | `weapon_skins.lua` |
| Brackensong Blades | `we_dual_sword_dagger_skin_07` | `units/weapons/player/wpn_we_sword_03_t2/wpn_we_sword_03_t2` | `units/weapons/player/wpn_we_dagger_03_t2/wpn_we_dagger_03_t2` | `weapon_skins.lua` |
| Breath of the Wind | `we_shortbow_skin_05` | `—` | `units/weapons/player/wpn_we_bow_short_05/wpn_we_bow_short_05` | `weapon_skins.lua` |
| Bright College Staff of Ceremonies | `bw_flamethrower_staff_skin_05` | `units/weapons/player/wpn_brw_flame_staff_05/wpn_brw_flame_staff_05` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Captain Dreist's Deathbringer | `es_blunderbuss_skin_02` | `units/weapons/player/wpn_empire_blunderbuss_02_t2/wpn_empire_blunderbuss_02_t2` | `—` | `weapon_skins.lua` |
| Captain's Trusty Companions | `es_dual_wield_hammer_sword_skin_02` | `units/weapons/player/wpn_emp_mace_05_t2/wpn_emp_mace_05_t2` | `units/weapons/player/wpn_emp_sword_06_t2/wpn_emp_sword_06_t2` | `weapon_skins_paperweight.lua` |
| Claws of Cellidin-thar | `we_dual_dagger_skin_05` | `units/weapons/player/wpn_we_dagger_02_t3/wpn_we_dagger_02_t3` | `units/weapons/player/wpn_we_dagger_02_t3/wpn_we_dagger_02_t3` | `weapon_skins.lua` |
| Coethinaryal | `we_dual_sword_skin_03` | `units/weapons/player/wpn_we_sword_01_t3/wpn_we_sword_01_t3` | `units/weapons/player/wpn_we_sword_01_t3/wpn_we_sword_01_t3` | `weapon_skins.lua` |
| Crusher | `es_2h_hammer_skin_06` | `units/weapons/player/wpn_empire_2h_hammer_03_t2/wpn_2h_hammer_03_t2` | `—` | `weapon_skins.lua` |
| Daith's Throatslitters | `we_dual_dagger_skin_02` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2` | `weapon_skins.lua` |
| Dalkaringrund | `dw_1h_hammer_shield_skin_05` | `units/weapons/player/wpn_dw_hammer_03_t1/wpn_dw_hammer_03_t1` | `units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05` | `weapon_skins.lua` |
| Dawazbak | `dr_deus_01_skin_03` | `—` | `units/weapons/player/wpn_dr_deus_03/wpn_dr_deus_03` | `weapon_skins_morris.lua` |
| Deepwood Claw | `we_2h_axe_skin_08` | `units/weapons/player/wpn_we_2h_axe_04_t2/wpn_we_2h_axe_04_t2` | `—` | `weapon_skins.lua` |
| Dokmaraz | `dw_crossbow_skin_04` | `—` | `units/weapons/player/wpn_dw_xbow_02_t2/wpn_dw_xbow_02_t2` | `weapon_skins.lua` |
| Donglizrikkazen | `dw_2h_hammer_skin_02` | `units/weapons/player/wpn_dw_2h_hammer_01_t2/wpn_dw_2h_hammer_01_t2` | `—` | `weapon_skins.lua` |
| Doom on a Stick | `es_halberd_skin_04` | `units/weapons/player/wpn_wh_halberd_04/wpn_wh_halberd_04` | `—` | `weapon_skins.lua` |
| Drakkenrar | `dr_deus_01_skin_02` | `—` | `units/weapons/player/wpn_dr_deus_02/wpn_dr_deus_02` | `weapon_skins_morris.lua` |
| Dreiberg's Disintegrator | `bw_beam_staff_skin_04` | `units/weapons/player/wpn_brw_beam_staff_04/wpn_brw_beam_staff_04` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Dronthrund | `dw_grudge_raker_skin_03` | `units/weapons/player/wpn_dw_rakegun_t3/wpn_dw_rakegun_t3` | `—` | `weapon_skins.lua` |
| Dronvarfaz Rork | `dw_handgun_skin_05` | `units/weapons/player/wpn_dw_handgun_02_t3/wpn_dw_handgun_02_t3` | `—` | `weapon_skins.lua` |
| Drungazaz | `dw_2h_axe_skin_05` | `units/weapons/player/wpn_dw_2h_axe_03_t1/wpn_dw_2h_axe_03_t1` | `—` | `weapon_skins.lua` |
| Durnschott's Pulveriser | `es_1h_flail_skin_05` | `units/weapons/player/wpn_emp_flail_05_t1/wpn_emp_flail_05_t1` | `—` | `weapon_skins.lua` |
| Elder's Gift | `we_dual_sword_skin_07` | `units/weapons/player/wpn_we_sword_03_t2/wpn_we_sword_03_t2` | `units/weapons/player/wpn_we_sword_03_t2/wpn_we_sword_03_t2` | `weapon_skins.lua` |
| Ember Mace | `bw_1h_mace_skin_04` | `units/weapons/player/wpn_brw_mace_04/wpn_brw_mace_04` | `—` | `weapon_skins.lua` |
| Evengleam | `es_bastard_sword_skin_04` | `units/weapons/player/wpn_emp_gk_sword_02_t2/wpn_emp_gk_sword_02_t2` | `—` | `weapon_skins_lake.lua` |
| Fauschlag | `es_2h_hammer_skin_02` | `units/weapons/player/wpn_empire_2h_hammer_01_t2/wpn_2h_hammer_01_t2` | `—` | `weapon_skins.lua` |
| Firegobbet | `bw_spear_staff_skin_05` | `units/weapons/player/wpn_brw_spear_staff_05/wpn_brw_spear_staff_05` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Flensing Blade | `wh_1h_falchion_skin_04` | `units/weapons/player/wpn_emp_sword_05_t2/wpn_emp_sword_05_t2` | `—` | `weapon_skins.lua` |
| Fleshrake | `we_crossbow_skin_03` | `—` | `units/weapons/player/wpn_we_repeater_crossbow_t3/wpn_we_repeater_crossbow_t3` | `weapon_skins.lua` |
| Ghalaz | `dw_1h_axe_skin_06` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2` | `—` | `weapon_skins.lua` |
| Glamourstrike | `we_spear_skin_05` | `units/weapons/player/wpn_we_spear_05/wpn_we_spear_05` | `—` | `weapon_skins.lua` |
| Gordrengi Tukaz | `dw_dual_axe_skin_04` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2` | `weapon_skins.lua` |
| Gorogaz Grund | `dw_1h_hammer_skin_06` | `units/weapons/player/wpn_dw_hammer_03_t2/wpn_dw_hammer_03_t2` | `—` | `weapon_skins.lua` |
| Greenleaf's Hadraich | `we_1h_axe_skin_02` | `units/weapons/player/wpn_we_axe_03_t1/wpn_we_axe_03_t1` | `—` | `weapon_skins_paperweight.lua` |
| Grobdrengi Tukaz | `dw_dual_axe_skin_06` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2` | `units/weapons/player/wpn_dw_axe_03_t2/wpn_dw_axe_03_t2` | `weapon_skins.lua` |
| Hacker | `es_2h_sword_exe_skin_05` | `units/weapons/player/wpn_emp_sword_exe_05_t1/wpn_emp_sword_exe_05_t1` | `—` | `weapon_skins.lua` |
| Halfling-Splitter | `es_2h_sword_skin_04` | `units/weapons/player/wpn_empire_2h_sword_03_t2/wpn_2h_sword_03_t2` | `—` | `weapon_skins.lua` |
| Hammer and Anvil | `es_1h_mace_shield_skin_04` | `units/weapons/player/wpn_emp_mace_03_t1/wpn_emp_mace_03_t1` | `units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04` | `weapon_skins.lua` |
| Hand of Atylwyth | `we_deus_01_skin_03` | `—` | `units/weapons/player/wpn_we_deus_03/wpn_we_deus_03` | `weapon_skins_morris.lua` |
| Hawkhallow | `es_longbow_skin_05` | `—` | `units/weapons/player/wpn_emp_bow_05/wpn_emp_bow_05` | `weapon_skins.lua` |
| Helmgart's Watch-Sword | `es_2h_sword_skin_06` | `units/weapons/player/wpn_greatsword/wpn_greatsword` | `—` | `weapon_skins.lua` |
| Hero's Blade | `es_bastard_sword_skin_03` | `units/weapons/player/wpn_emp_gk_sword_02_t1/wpn_emp_gk_sword_02_t1` | `—` | `weapon_skins_lake.lua` |
| Karak Smakit | `dw_1h_hammer_shield_skin_04` | `units/weapons/player/wpn_dw_hammer_02_t2/wpn_dw_hammer_02_t2` | `units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04` | `weapon_skins.lua` |
| Kazak Makaz | `dw_1h_axe_shield_skin_04` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2` | `units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04` | `weapon_skins.lua` |
| Kazakdibnaz Durazmaraz | `dw_2h_pick_skin_04` | `units/weapons/player/wpn_dw_pick_01_t4/wpn_dw_pick_01_t4` | `—` | `weapon_skins.lua` |
| Konk Maraz | `dw_1h_hammer_skin_03` | `units/weapons/player/wpn_dw_hammer_02_t1/wpn_dw_hammer_02_t1` | `—` | `weapon_skins.lua` |
| Krumper | `es_1h_flail_skin_04` | `units/weapons/player/wpn_emp_flail_04_t1/wpn_emp_flail_04_t1` | `—` | `weapon_skins.lua` |
| Lileath's Boon | `we_sword_skin_04` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1` | `—` | `weapon_skins.lua` |
| Longbeard's Az | `dw_1h_axe_skin_07` | `units/weapons/player/wpn_dw_axe_04_t1/wpn_dw_axe_04_t1` | `—` | `weapon_skins.lua` |
| Longbeard's Tukgrund | `dr_dual_wield_hammers_skin_02` | `units/weapons/player/wpn_dw_hammer_01_t2/wpn_dw_hammer_01_t2` | `units/weapons/player/wpn_dw_hammer_01_t2/wpn_dw_hammer_01_t2` | `weapon_skins_paperweight.lua` |
| Masterwork Pistols | `wh_brace_of_pistols_skin_02` | `units/weapons/player/wpn_emp_pistol_02_t1/wpn_emp_pistol_02_t1` | `units/weapons/player/wpn_emp_pistol_02_t1/wpn_emp_pistol_02_t1` | `weapon_skins.lua` |
| Matriarch's Crowbill | `bw_1h_crowbill_skin_02` | `units/weapons/player/wpn_brw_crowbill_02/wpn_brw_crowbill_02` | `—` | `weapon_skins_paperweight.lua` |
| Meistod's Zweihander | `wh_2h_sword_skin_04` | `units/weapons/player/wpn_empire_2h_sword_04_t2/wpn_2h_sword_04_t2` | `—` | `weapon_skins.lua` |
| Meteoric Greatsword | `wh_2h_sword_skin_05` | `units/weapons/player/wpn_empire_2h_sword_05_t1/wpn_2h_sword_05_t1` | `—` | `weapon_skins.lua` |
| Mhornarstok | `dw_2h_hammer_skin_05` | `units/weapons/player/wpn_dw_2h_hammer_03_t1/wpn_dw_2h_hammer_03_t1` | `—` | `weapon_skins.lua` |
| Modryn's Claws | `we_dual_sword_dagger_skin_05` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2` | `units/weapons/player/wpn_we_dagger_02_t2/wpn_we_dagger_02_t2` | `weapon_skins.lua` |
| Morr's Deliverer | `es_1h_mace_skin_05` | `units/weapons/player/wpn_emp_mace_03_t2/wpn_emp_mace_03_t2` | `—` | `weapon_skins.lua` |
| Mournlight Blades | `we_dual_dagger_skin_07` | `units/weapons/player/wpn_we_dagger_03_t2/wpn_we_dagger_03_t2` | `units/weapons/player/wpn_we_dagger_03_t2/wpn_we_dagger_03_t2` | `weapon_skins.lua` |
| Nar Karinaz | `dw_1h_axe_shield_skin_05` | `units/weapons/player/wpn_dw_axe_03_t1/wpn_dw_axe_03_t1` | `units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05` | `weapon_skins.lua` |
| Pride of Stirland | `es_longbow_skin_04` | `—` | `units/weapons/player/wpn_emp_bow_04/wpn_emp_bow_04` | `weapon_skins.lua` |
| Riverman's Spear & Shield | `es_deus_01_skin_02` | `units/weapons/player/wpn_es_deus_spear_02/wpn_es_deus_spear_02` | `units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02` | `weapon_skins_morris.lua` |
| Scrapsprayer | `es_blunderbuss_skin_05` | `units/weapons/player/wpn_empire_blunderbuss_t3/wpn_empire_blunderbuss_t3` | `—` | `weapon_skins.lua` |
| Searspike | `bw_dagger_skin_04` | `units/weapons/player/wpn_brw_dagger_04/wpn_brw_dagger_04` | `—` | `weapon_skins.lua` |
| Sentinel's Drannach | `we_spear_skin_03` | `units/weapons/player/wpn_we_spear_03/wpn_we_spear_03` | `—` | `weapon_skins.lua` |
| Sentinel's Khelthrax | `we_2h_axe_skin_02` | `units/weapons/player/wpn_we_2h_axe_01_t2/wpn_we_2h_axe_01_t2` | `—` | `weapon_skins.lua` |
| Sergeant's Handgun | `es_handgun_skin_02` | `units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2` | `—` | `weapon_skins.lua` |
| Severance | `we_2h_sword_skin_10` | `units/weapons/player/wpn_we_2h_sword_05_t2/wpn_we_2h_sword_05_t2` | `—` | `weapon_skins.lua` |
| Shards of Coldfell | `we_dual_dagger_skin_03` | `units/weapons/player/wpn_we_dagger_02_t1/wpn_we_dagger_02_t1` | `units/weapons/player/wpn_we_dagger_02_t1/wpn_we_dagger_02_t1` | `weapon_skins.lua` |
| Shelter and Slaughter | `es_1h_sword_shield_skin_04` | `units/weapons/player/wpn_emp_sword_03_t2/wpn_emp_sword_03_t2` | `units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04` | `weapon_skins.lua` |
| Shield of Honour Renewed | `es_sword_shield_breton_skin_03` | `units/weapons/player/wpn_emp_gk_sword_02_t1/wpn_emp_gk_sword_02_t1` | `units/weapons/player/wpn_emp_gk_shield_05/wpn_emp_gk_shield_05` | `weapon_skins_lake.lua` |
| Skruffsmakaz | `dw_2h_axe_skin_06` | `units/weapons/player/wpn_dw_2h_axe_03_t2/wpn_dw_2h_axe_03_t2` | `—` | `weapon_skins.lua` |
| Skullshatter | `es_1h_mace_skin_04` | `units/weapons/player/wpn_emp_mace_03_t1/wpn_emp_mace_03_t1` | `—` | `weapon_skins.lua` |
| Smouldersteel | `bw_1h_sword_skin_08` | `units/weapons/player/wpn_brw_sword_04_t2/wpn_brw_sword_04_t2` | `—` | `weapon_skins.lua` |
| Song's Whisper | `we_shortbow_skin_04` | `—` | `units/weapons/player/wpn_we_bow_short_04/wpn_we_bow_short_04` | `weapon_skins.lua` |
| Spiritbreaker | `we_hagbane_skin_05` | `—` | `units/weapons/player/wpn_we_bow_short_05/wpn_we_bow_short_05` | `weapon_skins.lua` |
| Staff of the Cursed North | `bw_deus_01_skin_02` | `units/weapons/player/wpn_bw_deus_02/wpn_bw_deus_02` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris.lua` |
| Stokdawazbakaz | `dw_2h_hammer_skin_06` | `units/weapons/player/wpn_dw_2h_hammer_03_t2/wpn_dw_2h_hammer_03_t2` | `—` | `weapon_skins.lua` |
| Sword of Mastery | `bw_1h_sword_skin_06` | `units/weapons/player/wpn_brw_sword_03_t2/wpn_brw_sword_03_t2` | `—` | `weapon_skins.lua` |
| Talabecland Waldguarder | `es_deus_01_skin_03` | `units/weapons/player/wpn_es_deus_spear_03/wpn_es_deus_spear_03` | `units/weapons/player/wpn_es_deus_shield_03/wpn_es_deus_shield_03` | `weapon_skins_morris.lua` |
| The Cursed Stick of Pietr Kross | `bw_beam_staff_skin_05` | `units/weapons/player/wpn_brw_beam_staff_05/wpn_brw_beam_staff_05` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| The Dagger of Rothscarn | `bw_dagger_skin_05` | `units/weapons/player/wpn_brw_dagger_05/wpn_brw_dagger_05` | `—` | `weapon_skins.lua` |
| The Force of Argument | `bw_1h_mace_skin_05` | `units/weapons/player/wpn_brw_mace_05/wpn_brw_mace_05` | `—` | `weapon_skins.lua` |
| The Honour of Ubersreik | `es_1h_mace_shield_skin_05` | `units/weapons/player/wpn_emp_mace_03_t2/wpn_emp_mace_03_t2` | `units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05` | `weapon_skins.lua` |
| The Lost Blade of Torgovann | `we_sword_skin_07` | `units/weapons/player/wpn_we_sword_03_t2/wpn_we_sword_03_t2` | `—` | `weapon_skins.lua` |
| The Marksman | `wh_crossbow_skin_06` | `—` | `units/weapons/player/wpn_empire_crossbow_t2/wpn_empire_crossbow_tier2` | `weapon_skins.lua` |
| The Mountain | `es_2h_hammer_skin_04` | `units/weapons/player/wpn_empire_2h_hammer_02_t2/wpn_2h_hammer_02_t2` | `—` | `weapon_skins.lua` |
| The Reckoning | `wh_1h_axe_skin_06` | `units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2` | `—` | `weapon_skins.lua` |
| The Reiklander's Welcome | `es_repeating_handgun_skin_03` | `units/weapons/player/wpn_emp_handgun_repeater_t3/wpn_emp_handgun_repeater_t3` | `—` | `weapon_skins.lua` |
| The Searing Sword of Miragliano | `bw_1h_flaming_sword_skin_06` | `units/weapons/player/wpn_brw_sword_03_t2/wpn_brw_flaming_sword_03_t2` | `—` | `weapon_skins.lua` |
| The Sword and Shield of Alturin | `es_sword_shield_breton_skin_04` | `units/weapons/player/wpn_emp_gk_sword_02_t2/wpn_emp_gk_sword_02_t2` | `units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01` | `weapon_skins_lake.lua` |
| The Twin Swords of Fyr Darric | `we_dual_sword_skin_05` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2` | `weapon_skins.lua` |
| The Unstoppable | `es_2h_sword_exe_skin_04` | `units/weapons/player/wpn_emp_sword_exe_04_t1/wpn_emp_sword_exe_04_t1` | `—` | `weapon_skins.lua` |
| Tukazulaz | `dw_dual_axe_skin_02` | `units/weapons/player/wpn_dw_axe_01_t2/wpn_dw_axe_01_t2` | `units/weapons/player/wpn_dw_axe_01_t2/wpn_dw_axe_01_t2` | `weapon_skins.lua` |
| Twisted Keystaff | `bw_deus_01_skin_03` | `units/weapons/player/wpn_bw_deus_03/wpn_bw_deus_03` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris.lua` |
| Uncle Ekhart's Defiance | `es_longbow_skin_04_runed_01` | `—` | `units/weapons/player/wpn_emp_bow_04/wpn_emp_bow_04_runed_01` | `weapon_skins.lua` |
| Urklinkaz | `dw_1h_axe_skin_04` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2` | `—` | `weapon_skins.lua` |
| Uzkulaz | `dw_2h_axe_skin_04` | `units/weapons/player/wpn_dw_2h_axe_02_t2/wpn_dw_2h_axe_02_t2` | `—` | `weapon_skins.lua` |
| Verbel's Masterwork | `es_1h_sword_shield_skin_05` | `units/weapons/player/wpn_emp_sword_03_t2/wpn_emp_sword_03_t2` | `units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05` | `weapon_skins.lua` |
| Von Tarnus' Meltdown | `bw_flamethrower_staff_skin_04` | `units/weapons/player/wpn_brw_flame_staff_04/wpn_brw_flame_staff_04` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Warrior's Thrund | `dw_handgun_skin_04` | `units/weapons/player/wpn_dw_handgun_02_t2/wpn_dw_handgun_02_t2` | `—` | `weapon_skins.lua` |
| Waystalker's Shadow Bow | `we_deus_01_skin_02` | `—` | `units/weapons/player/wpn_we_deus_02/wpn_we_deus_02` | `weapon_skins_morris.lua` |
| Withersight | `we_hagbane_skin_04` | `—` | `units/weapons/player/wpn_we_bow_short_04/wpn_we_bow_short_04` | `weapon_skins.lua` |
| Wutrothzan Drekmaraz | `dw_crossbow_skin_05` | `—` | `units/weapons/player/wpn_dw_xbow_02_t3/wpn_dw_xbow_02_t3` | `weapon_skins.lua` |
| Zharrhirn | `dw_drakegun_skin_03` | `units/weapons/player/wpn_dw_iron_drake_03/wpn_dw_iron_drake_03` | `—` | `weapon_skins.lua` |
| Zintiaz Drakktuk | `dw_drake_pistol_skin_04` | `units/weapons/player/wpn_dw_drake_pistol_02_t2/wpn_dw_drake_pistol_02_t2` | `units/weapons/player/wpn_dw_drake_pistol_02_t2/wpn_dw_drake_pistol_02_t2` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_brace_of_pistols_skin_03` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_brace_of_pistols_skin_05` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_crossbow_skin_03` | `—` | `units/weapons/player/wpn_emp_crossbow_03_t1/wpn_emp_crossbow_03_t1` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_crossbow_skin_04` | `—` | `units/weapons/player/wpn_emp_crossbow_03_t2/wpn_emp_crossbow_03_t2` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_crossbow_skin_07` | `—` | `units/weapons/player/wpn_empire_crossbow_t3/wpn_empire_crossbow_tier3` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_deus_01_skin_02` | `units/weapons/player/wpn_wh_deus_02/wpn_wh_deus_02` | `units/weapons/player/wpn_wh_deus_02/wpn_wh_deus_02` | `weapon_skins_morris.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_deus_01_skin_03` | `units/weapons/player/wpn_wh_deus_03/wpn_wh_deus_03` | `units/weapons/player/wpn_wh_deus_03/wpn_wh_deus_03` | `weapon_skins_morris.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_dual_wield_axe_falchion_skin_02` | `units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2` | `units/weapons/player/wpn_emp_sword_04_t2/wpn_emp_sword_04_t2` | `weapon_skins_paperweight.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_fencing_sword_skin_04` | `units/weapons/player/wpn_fencingsword_03_t1/wpn_fencingsword_03_t1` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_fencing_sword_skin_05` | `units/weapons/player/wpn_fencingsword_03_t2/wpn_fencingsword_03_t2` | `units/weapons/player/wpn_emp_pistol_01_t1/wpn_emp_pistol_01_t1` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_fencing_sword_skin_08` | `units/weapons/player/wpn_fencingsword_t1/wpn_fencingsword_t1` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_repeating_crossbow_skin_02` | `—` | `units/weapons/player/wpn_wh_repeater_crossbow_t2/wpn_wh_repeater_crossbow_t2` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_repeating_crossbow_skin_03` | `—` | `units/weapons/player/wpn_wh_repeater_crossbow_t3/wpn_wh_repeater_crossbow_t3` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_repeating_pistol_skin_03` | `units/weapons/player/wpn_empire_pistol_repeater/wpn_empire_pistol_repeater_t3` | `—` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_repeating_pistol_skin_05` | `units/weapons/player/wpn_empire_pistol_repeater_02/wpn_empire_pistol_repeater_02_t2` | `—` | `weapon_skins.lua` |

### `rare` (84 items)

| Display name | Skin key | Right unit | Left unit | Source file |
|---|---|---|---|---|
| Adept's Beam Staff | `bw_beam_staff_skin_03` | `units/weapons/player/wpn_brw_beam_staff_03/wpn_brw_beam_staff_03` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Adept's Bolt Staff | `bw_spear_staff_skin_03` | `units/weapons/player/wpn_brw_spear_staff_03/wpn_brw_spear_staff_03` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Adept's Dagger | `bw_dagger_skin_03` | `units/weapons/player/wpn_brw_dagger_03/wpn_brw_dagger_03` | `—` | `weapon_skins.lua` |
| Adept's Flamewave Staff | `bw_flamethrower_staff_skin_03` | `units/weapons/player/wpn_brw_flame_staff_03/wpn_brw_flame_staff_03` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Adept's Mace | `bw_1h_mace_skin_03` | `units/weapons/player/wpn_brw_mace_03/wpn_brw_mace_03` | `—` | `weapon_skins.lua` |
| Adjudicator's Excoriator | `wh_1h_falchion_skin_02` | `units/weapons/player/wpn_emp_sword_04_t2/wpn_emp_sword_04_t2` | `—` | `weapon_skins.lua` |
| Adjudicator's Greatsword | `wh_2h_sword_skin_02` | `units/weapons/player/wpn_empire_2h_sword_02_t2/wpn_2h_sword_02_t2` | `—` | `weapon_skins.lua` |
| Ambusher's Ceyla | `we_dual_sword_skin_06` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1` | `weapon_skins.lua` |
| Ambusher's Galria | `we_dual_sword_dagger_skin_06` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1` | `units/weapons/player/wpn_we_dagger_03_t1/wpn_we_dagger_03_t1` | `weapon_skins.lua` |
| Ambusher's Glaia | `we_dual_dagger_skin_06` | `units/weapons/player/wpn_we_dagger_03_t1/wpn_we_dagger_03_t1` | `units/weapons/player/wpn_we_dagger_03_t1/wpn_we_dagger_03_t1` | `weapon_skins.lua` |
| Apprentice's Conflagration Staff | `bw_conflagration_staff_skin_02` | `units/weapons/player/wpn_brw_staff_04/wpn_brw_staff_04` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Apprentice's Fireball Staff | `bw_fireball_staff_skin_02` | `units/weapons/player/wpn_brw_staff_05/wpn_brw_staff_05` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Billowblade | `bw_1h_flaming_sword_skin_04` | `units/weapons/player/wpn_brw_sword_02_t2/wpn_brw_flaming_sword_02_t2` | `—` | `weapon_skins.lua` |
| Bitterweald Kindrathi | `we_javelin_skin_02` | `units/weapons/player/wpn_invisible_weapon` | `units/weapons/player/wpn_we_javelin_02/wpn_we_javelin_02` | `weapon_skins_woods.lua` |
| Bitterweald Sariothi | `we_life_staff_skin_02` | `—` | `units/weapons/player/wpn_we_life_staff_02/wpn_we_life_staff_02` | `weapon_skins_woods.lua` |
| Bonemulcher | `we_2h_axe_skin_06` | `units/weapons/player/wpn_we_2h_axe_03_t2/wpn_we_2h_axe_03_t2` | `—` | `weapon_skins.lua` |
| Brigstan's Executor | `wh_1h_axe_skin_02` | `units/weapons/player/wpn_axe_02_t2/wpn_axe_02_t2` | `—` | `weapon_skins.lua` |
| Chamberlain's Flail | `es_1h_flail_skin_03` | `units/weapons/player/wpn_emp_flail_03_t1/wpn_emp_flail_03_t1` | `—` | `weapon_skins.lua` |
| Draich of the Soul-Lost | `we_2h_sword_skin_07` | `units/weapons/player/wpn_we_2h_sword_04_t1/wpn_we_2h_sword_04_t1` | `—` | `weapon_skins.lua` |
| Durazankaz | `dw_2h_pick_skin_03` | `units/weapons/player/wpn_dw_pick_01_t3/wpn_dw_pick_01_t3` | `—` | `weapon_skins.lua` |
| Flesh-Smelter's Blade | `bw_1h_sword_skin_07` | `units/weapons/player/wpn_brw_sword_04_t1/wpn_brw_sword_04_t1` | `—` | `weapon_skins.lua` |
| Glade Guardian's Ceyla | `we_dual_sword_skin_01` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1` | `weapon_skins.lua` |
| Glade Guardian's Drannach | `we_spear_skin_02` | `units/weapons/player/wpn_we_spear_02/wpn_we_spear_02` | `—` | `weapon_skins.lua` |
| Glade Guardian's Hadraich | `we_1h_axe_skin_01` | `units/weapons/player/wpn_we_axe_01_t2/wpn_we_axe_01_t2` | `—` | `weapon_skins_paperweight.lua` |
| Glade Guardian's Khelthrax | `we_2h_axe_skin_03` | `units/weapons/player/wpn_we_2h_axe_02_t1/wpn_we_2h_axe_02_t1` | `—` | `weapon_skins.lua` |
| Handmaiden's Nastirrath | `we_longbow_skin_07` | `—` | `units/weapons/player/wpn_we_bow_04_t1/wpn_we_bow_04_t1` | `weapon_skins.lua` |
| Hans von Glint's Heir-Sword | `bw_1h_sword_skin_04` | `units/weapons/player/wpn_brw_sword_02_t2/wpn_brw_sword_02_t2` | `—` | `weapon_skins.lua` |
| Hero's Sword and Shield | `es_sword_shield_breton_skin_02` | `units/weapons/player/wpn_emp_gk_sword_01_t2/wpn_emp_gk_sword_01_t2` | `units/weapons/player/wpn_emp_gk_shield_04/wpn_emp_gk_shield_04` | `weapon_skins_lake.lua` |
| High Priest’s Paired Skull-splitters | `wh_dual_hammer_skin_02` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02` | `weapon_skins_bless.lua` |
| High Priest’s Reckoner | `wh_2h_hammer_skin_02` | `units/weapons/player/wpn_wh_2h_hammer_02/wpn_wh_2h_hammer_02` | `—` | `weapon_skins_bless.lua` |
| High Priest’s Skull-Splitter | `wh_1h_hammer_skin_02` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02` | `—` | `weapon_skins_bless.lua` |
| Karaz Dronaz | `dw_1h_axe_skin_05` | `units/weapons/player/wpn_dw_axe_03_t1/wpn_dw_axe_03_t1` | `—` | `weapon_skins.lua` |
| Longbeard's Tukaz | `dw_dual_axe_skin_07` | `units/weapons/player/wpn_dw_axe_04_t1/wpn_dw_axe_04_t1` | `units/weapons/player/wpn_dw_axe_04_t1/wpn_dw_axe_04_t1` | `weapon_skins.lua` |
| Master's Crowbill | `bw_1h_crowbill_skin_01` | `units/weapons/player/wpn_brw_crowbill_01/wpn_brw_crowbill_01` | `—` | `weapon_skins_paperweight.lua` |
| Moritorium Staff | `bw_necromancy_staff_skin_02` | `units/weapons/player/wpn_bw_necromancy_staff_02/wpn_bw_necromancy_staff_02` | `units/weapons/player/wpn_invisible_weapon` | `weapon_skins_shovel.lua` |
| Murderer's Crossbow | `we_crossbow_skin_02` | `—` | `units/weapons/player/wpn_we_repeater_crossbow_t2/wpn_we_repeater_crossbow_t2` | `weapon_skins.lua` |
| Ongrunaz Thrund | `dw_handgun_skin_02` | `units/weapons/player/wpn_dw_handgun_01_t2/wpn_dw_handgun_01_t2` | `—` | `weapon_skins.lua` |
| Predator's Draich | `we_2h_sword_skin_09` | `units/weapons/player/wpn_we_2h_sword_05_t1/wpn_we_2h_sword_05_t1` | `—` | `weapon_skins.lua` |
| Predator's Nastirrath | `we_longbow_skin_03` | `—` | `units/weapons/player/wpn_we_bow_02_t1/wpn_we_bow_02_t1` | `weapon_skins.lua` |
| Sentinel's Ceyla | `we_dual_sword_skin_02` | `units/weapons/player/wpn_we_sword_01_t2/wpn_we_sword_01_t2` | `units/weapons/player/wpn_we_sword_01_t2/wpn_we_sword_01_t2` | `weapon_skins.lua` |
| Sentinel's Draich | `we_2h_sword_skin_02` | `units/weapons/player/wpn_we_2h_sword_01_t2/wpn_we_2h_sword_01_t2` | `—` | `weapon_skins.lua` |
| Sentinel's Edduath | `we_shortbow_skin_03` | `—` | `units/weapons/player/wpn_we_bow_short_03/wpn_we_bow_short_03` | `weapon_skins.lua` |
| Sentinel's Galria | `we_dual_sword_dagger_skin_02` | `units/weapons/player/wpn_we_sword_01_t2/wpn_we_sword_01_t2` | `units/weapons/player/wpn_we_dagger_01_t2/wpn_we_dagger_01_t2` | `weapon_skins.lua` |
| Sentinel's Glaia | `we_dual_dagger_skin_04` | `units/weapons/player/wpn_we_dagger_02_t2/wpn_we_dagger_02_t2` | `units/weapons/player/wpn_we_dagger_02_t2/wpn_we_dagger_02_t2` | `weapon_skins.lua` |
| Sentinel's Kenuiath | `we_hagbane_skin_03` | `—` | `units/weapons/player/wpn_we_bow_short_03/wpn_we_bow_short_03` | `weapon_skins.lua` |
| Sergeant's Executioner | `es_2h_sword_exe_skin_03` | `units/weapons/player/wpn_emp_sword_exe_03_t1/wpn_emp_sword_exe_03_t1` | `—` | `weapon_skins.lua` |
| Sergeant's Greatsword | `es_2h_sword_skin_05` | `units/weapons/player/wpn_empire_2h_sword_04_t1/wpn_2h_sword_04_t1` | `—` | `weapon_skins.lua` |
| Sergeant's Halberd | `es_halberd_skin_03` | `units/weapons/player/wpn_wh_halberd_03/wpn_wh_halberd_03` | `—` | `weapon_skins.lua` |
| Sergeant's Handcannon | `es_blunderbuss_skin_04` | `units/weapons/player/wpn_empire_blunderbuss_t2/wpn_empire_blunderbuss_t2` | `—` | `weapon_skins.lua` |
| Sergeant's Longbow | `es_longbow_skin_03` | `—` | `units/weapons/player/wpn_emp_bow_03/wpn_emp_bow_03` | `weapon_skins.lua` |
| Sergeant's Longsword | `es_1h_sword_skin_02` | `units/weapons/player/wpn_emp_sword_02_t2/wpn_emp_sword_02_t2` | `—` | `weapon_skins.lua` |
| Sergeant's Longsword and Shield | `es_1h_sword_shield_skin_01` | `units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1` | `units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1` | `weapon_skins.lua` |
| Sergeant's Mace | `es_1h_mace_skin_03` | `units/weapons/player/wpn_emp_mace_02_t3/wpn_emp_mace_02_t3` | `—` | `weapon_skins.lua` |
| Sergeant's Mace and Shield | `es_1h_mace_shield_skin_01` | `units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1` | `units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1` | `weapon_skins.lua` |
| Sergeant's Repeating Handgun | `es_repeating_handgun_skin_02` | `units/weapons/player/wpn_emp_handgun_repeater_t2/wpn_emp_handgun_repeater_t2` | `—` | `weapon_skins.lua` |
| Sergeant's Trusty Companions | `es_dual_wield_hammer_sword_skin_01` | `units/weapons/player/wpn_emp_mace_04_t2/wpn_emp_mace_04_t2` | `units/weapons/player/wpn_emp_sword_06_t1/wpn_emp_sword_06_t1` | `weapon_skins_paperweight.lua` |
| Sergeant's Warhammer | `es_2h_hammer_skin_01` | `units/weapons/player/wpn_empire_2h_hammer_01_t1/wpn_2h_hammer_01_t1` | `—` | `weapon_skins.lua` |
| Severung | `we_sword_skin_05` | `units/weapons/player/wpn_we_sword_02_t2/wpn_we_sword_02_t2` | `—` | `weapon_skins.lua` |
| Stalwart's Blade | `es_bastard_sword_skin_02` | `units/weapons/player/wpn_emp_gk_sword_01_t2/wpn_emp_gk_sword_01_t2` | `—` | `weapon_skins_lake.lua` |
| Thagi Rikkazen | `dw_1h_hammer_skin_04` | `units/weapons/player/wpn_dw_hammer_02_t2/wpn_dw_hammer_02_t2` | `—` | `weapon_skins.lua` |
| The Brass Reaper | `bw_ghost_scythe_skin_02` | `units/weapons/player/wpn_bw_ghost_scythe_02/wpn_bw_ghost_scythe_02` | `—` | `weapon_skins_shovel.lua` |
| The Cauteriser | `bw_1h_flaming_sword_skin_07` | `units/weapons/player/wpn_brw_sword_04_t1/wpn_brw_flaming_sword_04_t1` | `—` | `weapon_skins.lua` |
| The Longbow of Seasons | `we_longbow_skin_09` | `—` | `units/weapons/player/wpn_we_bow_05_t1/wpn_we_bow_05_t1` | `weapon_skins.lua` |
| Tinkerer's Coggrund | `dr_2h_cog_hammer_skin_02` | `units/weapons/player/wpn_dw_coghammer_01_t2/wpn_dw_coghammer_01_t2` | `—` | `weapon_skins_cog.lua` |
| Tinkerer's Thrundtak | `dr_steam_pistol_skin_02` | `units/weapons/player/wpn_dw_steam_pistol_01_t2/wpn_dw_steam_pistol_01_t2` | `—` | `weapon_skins_cog.lua` |
| Warrior's Az | `dw_1h_axe_skin_03` | `units/weapons/player/wpn_dw_axe_02_t1/wpn_dw_axe_02_t1` | `—` | `weapon_skins.lua` |
| Warrior's Az-Dreugi | `dw_2h_axe_skin_03` | `units/weapons/player/wpn_dw_2h_axe_02_t1/wpn_dw_2h_axe_02_t1` | `—` | `weapon_skins.lua` |
| Warrior's Dammaz-Thrund | `dw_grudge_raker_skin_02` | `units/weapons/player/wpn_dw_rakegun_t2/wpn_dw_rakegun_t2` | `—` | `weapon_skins.lua` |
| Warrior's Drakktuk | `dw_drake_pistol_skin_02` | `units/weapons/player/wpn_dw_drake_pistol_01_t2/wpn_dw_drake_pistol_01_t2` | `units/weapons/player/wpn_dw_drake_pistol_01_t2/wpn_dw_drake_pistol_01_t2` | `weapon_skins.lua` |
| Warrior's Drekmakaz | `dw_crossbow_skin_02` | `—` | `units/weapons/player/wpn_dw_xbow_01_t2/wpn_dw_xbow_01_t2` | `weapon_skins.lua` |
| Warrior's Grundreugi | `dw_2h_hammer_skin_04` | `units/weapons/player/wpn_dw_2h_hammer_02_t2/wpn_dw_2h_hammer_02_t2` | `—` | `weapon_skins.lua` |
| Warrior's Karinaz | `dw_1h_axe_shield_skin_03` | `units/weapons/player/wpn_dw_axe_02_t1/wpn_dw_axe_02_t1` | `units/weapons/player/wpn_dw_shield_03_t1/wpn_dw_shield_03` | `weapon_skins.lua` |
| Warrior's Karingrund | `dw_1h_hammer_shield_skin_03` | `units/weapons/player/wpn_dw_hammer_02_t1/wpn_dw_hammer_02_t1` | `units/weapons/player/wpn_dw_shield_03_t1/wpn_dw_shield_03` | `weapon_skins.lua` |
| Warrior's Tukaz | `dw_dual_axe_skin_03` | `units/weapons/player/wpn_dw_axe_02_t1/wpn_dw_axe_02_t1` | `units/weapons/player/wpn_dw_axe_02_t1/wpn_dw_axe_02_t1` | `weapon_skins.lua` |
| Warrior's Tukgrund | `dr_dual_wield_hammers_skin_01` | `units/weapons/player/wpn_dw_hammer_03_t1/wpn_dw_hammer_03_t1` | `units/weapons/player/wpn_dw_hammer_03_t1/wpn_dw_hammer_03_t1` | `weapon_skins_paperweight.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_crossbow_skin_02` | `—` | `units/weapons/player/wpn_emp_crossbow_02_t2/wpn_emp_crossbow_02_t2` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_dual_wield_axe_falchion_skin_01` | `units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2` | `units/weapons/player/wpn_emp_sword_05_t2/wpn_emp_sword_05_t2` | `weapon_skins_paperweight.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_fencing_sword_skin_03` | `units/weapons/player/wpn_fencingsword_02_t2/wpn_fencingsword_02_t2` | `units/weapons/player/wpn_emp_pistol_01_t1/wpn_emp_pistol_01_t1` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_fencing_sword_skin_06` | `units/weapons/player/wpn_fencingsword_04_t1/wpn_fencingsword_04_t1` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_flail_shield_skin_02` | `units/weapons/player/wpn_emp_flail_05_t1/wpn_emp_flail_05_t1` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1` | `weapon_skins_bless.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_hammer_book_skin_02` | `units/weapons/player/wpn_wh_book_02/wpn_wh_book_02` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02` | `weapon_skins_bless.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_hammer_shield_skin_02` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1` | `weapon_skins_bless.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_repeating_crossbow_skin_01` | `—` | `units/weapons/player/wpn_wh_repeater_crossbow_t1/wpn_wh_repeater_crossbow_t1` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_repeating_pistol_skin_02` | `units/weapons/player/wpn_empire_pistol_repeater/wpn_empire_pistol_repeater_t2` | `—` | `weapon_skins.lua` |

### `magic` (85 items)

| Display name | Skin key | Right unit | Left unit | Source file |
|---|---|---|---|---|
| Dromthicoggrund | `dr_2h_cog_hammer_skin_02_magic_01` | `units/weapons/player/wpn_dw_coghammer_01_t2/wpn_dw_coghammer_01_t2_magic` | `—` | `weapon_skins_cog.lua` |
| Evengleam | `es_bastard_sword_skin_04_magic_01` | `units/weapons/player/wpn_emp_gk_sword_02_t2/wpn_emp_gk_sword_02_t2_magic_01` | `—` | `weapon_skins_lake.lua` |
| Krankthrundtak | `dr_steam_pistol_01_t2_magic_01` | `units/weapons/player/wpn_dw_steam_pistol_01_t2/wpn_dw_steam_pistol_01_t2_magic_01` | `—` | `weapon_skins_cog.lua` |
| Righteous Arms | `es_sword_shield_breton_skin_04_magic_01_magic_01` | `units/weapons/player/wpn_emp_gk_sword_02_t2/wpn_emp_gk_sword_02_t2_magic_01` | `units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01_magic_01` | `weapon_skins_lake.lua` |
| The Brass Reaper | `bw_ghost_scythe_skin_02_magic_01` | `units/weapons/player/wpn_bw_ghost_scythe_02/wpn_bw_ghost_scythe_02_magic_01` | `—` | `weapon_skins_shovel.lua` |
| Weave-Forged Axe | `wh_1h_axe_skin_06_magic_01` | `units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Az | `dw_1h_axe_skin_04_magic_01` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Az-Dreugi | `dw_2h_axe_skin_02_magic_01` | `units/weapons/player/wpn_dw_2h_axe_01_t2/wpn_dw_2h_axe_01_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Beam Staff | `bw_beam_staff_skin_02_magic_01` | `units/weapons/player/wpn_brw_beam_staff_02/wpn_brw_beam_staff_02_magic_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_scorpion.lua` |
| Weave-Forged Bill Hook | `wh_2h_billhook_skin_02_magic_01` | `units/weapons/player/wpn_wh_billhook_02/wpn_wh_billhook_02_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Bolt Staff | `bw_spear_staff_skin_05_magic_01` | `units/weapons/player/wpn_brw_spear_staff_05/wpn_brw_spear_staff_05_magic_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_scorpion.lua` |
| Weave-Forged Ceyl | `we_sword_skin_06_magic_01` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Ceyla | `we_dual_sword_skin_06_magic_01` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1_magic_01` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Coach Gun | `es_blunderbuss_skin_01_magic_01` | `units/weapons/player/wpn_empire_blunderbuss_02_t1/wpn_empire_blunderbuss_02_t1_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Conflagration Staff | `bw_conflagration_staff_skin_01_magic_01` | `units/weapons/player/wpn_brw_staff_03/wpn_brw_staff_03_magic_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_scorpion.lua` |
| Weave-Forged Coruscation Staff | `bw_deus_01_skin_magic` | `units/weapons/player/wpn_bw_deus_01/wpn_bw_deus_01_magic` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris.lua` |
| Weave-Forged Coruscation Staff | `bw_deus_02_skin_magic` | `units/weapons/player/wpn_bw_deus_02/wpn_bw_deus_02_magic` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris.lua` |
| Weave-Forged Crossbow | `we_crossbow_skin_01_magic_01` | `—` | `units/weapons/player/wpn_we_repeater_crossbow_t1/wpn_we_repeater_crossbow_t1_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Crowbill | `bw_1h_crowbill_skin_01_magic_01` | `units/weapons/player/wpn_brw_crowbill_01/wpn_brw_crowbill_01_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Dagger | `bw_dagger_skin_02_magic_01` | `units/weapons/player/wpn_brw_dagger_02/wpn_brw_dagger_02_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Dammaz-Thrund | `dw_grudge_raker_skin_03_magic_01` | `units/weapons/player/wpn_dw_rakegun_t3/wpn_dw_rakegun_t3_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Draich | `we_2h_sword_skin_08_magic_01` | `units/weapons/player/wpn_we_2h_sword_04_t2/wpn_we_2h_sword_04_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Drakkthrund | `dw_drakegun_skin_02_magic_01` | `units/weapons/player/wpn_dw_iron_drake_02/wpn_dw_iron_drake_02_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Drakktuk | `dw_drake_pistol_skin_01_magic_01` | `units/weapons/player/wpn_dw_drake_pistol_01_t1/wpn_dw_drake_pistol_01_t1_magic_01` | `units/weapons/player/wpn_dw_drake_pistol_01_t1/wpn_dw_drake_pistol_01_t1_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Drannach | `we_spear_skin_02_magic_01` | `units/weapons/player/wpn_we_spear_02/wpn_we_spear_02_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Drannach-Isalt | `we_1h_spears_shield_skin_02_magic_01` | `units/weapons/player/wpn_we_spear_02/wpn_we_spear_02_magic_01` | `units/weapons/player/wpn_we_shield_02/wpn_we_shield_02_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Drekmakaz | `dw_crossbow_skin_03_magic_01` | `—` | `units/weapons/player/wpn_dw_xbow_02_t1/wpn_dw_xbow_02_t1_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Edduath | `we_shortbow_skin_02_magic_01` | `—` | `units/weapons/player/wpn_we_bow_short_02/wpn_we_bow_short_02_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Executioner's Sword | `es_2h_sword_exe_skin_03_magic_01` | `units/weapons/player/wpn_emp_sword_exe_03_t1/wpn_emp_sword_exe_03_t1_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Falchion | `wh_1h_falchion_skin_04_magic_01` | `units/weapons/player/wpn_emp_sword_05_t2/wpn_emp_sword_05_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Fireball Staff | `bw_fireball_staff_skin_02_magic_01` | `units/weapons/player/wpn_brw_staff_05/wpn_brw_staff_05_magic_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_scorpion.lua` |
| Weave-Forged Flail | `es_1h_flail_skin_04_magic_01` | `units/weapons/player/wpn_emp_flail_04_t1/wpn_emp_flail_04_t1_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Flame-Sword | `bw_1h_flaming_sword_skin_06_magic_01` | `units/weapons/player/wpn_brw_sword_03_t2/wpn_brw_flaming_sword_03_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Flamethrower Staff | `bw_flamethrower_staff_skin_04_magic_01` | `units/weapons/player/wpn_brw_flame_staff_04/wpn_brw_flame_staff_04_magic_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_scorpion.lua` |
| Weave-Forged Galria | `we_dual_sword_dagger_skin_07_magic_01` | `units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1_magic_01` | `units/weapons/player/wpn_we_dagger_03_t2/wpn_we_dagger_03_t2_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Glaia | `we_dual_dagger_skin_07_magic_01` | `units/weapons/player/wpn_we_dagger_03_t2/wpn_we_dagger_03_t2_magic_01` | `units/weapons/player/wpn_we_dagger_03_t2/wpn_we_dagger_03_t2_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Greatsword | `es_2h_sword_skin_03_magic_01` | `units/weapons/player/wpn_empire_2h_sword_03_t1/wpn_2h_sword_03_t1_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Greatsword | `wh_2h_sword_skin_04_magic_01` | `units/weapons/player/wpn_empire_2h_sword_04_t2/wpn_2h_sword_04_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Grund | `dw_1h_hammer_skin_03_magic_01` | `units/weapons/player/wpn_dw_hammer_02_t1/wpn_dw_hammer_02_t1_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Grundreugi | `dw_2h_hammer_skin_03_magic_01` | `units/weapons/player/wpn_dw_2h_hammer_02_t1/wpn_dw_2h_hammer_02_t1_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Hadraich | `we_1h_axe_skin_02_magic_01` | `units/weapons/player/wpn_we_axe_03_t2/wpn_we_axe_03_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Halberd | `es_halberd_skin_03_magic_01` | `units/weapons/player/wpn_wh_halberd_03/wpn_wh_halberd_03_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Handgun | `es_handgun_skin_02_magic_01` | `units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Incinerator | `bw_1h_flail_flaming_skin_02_magic_01` | `units/weapons/player/wpn_brw_flaming_flail_02/wpn_brw_flaming_flail_02_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Karinaz | `dw_1h_axe_shield_skin_04_magic_01` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2_magic_01` | `units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Karingrund | `dw_1h_hammer_shield_skin_04_magic_01` | `units/weapons/player/wpn_dw_hammer_02_t1/wpn_dw_hammer_02_t1_magic_01` | `units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Kenuiath | `we_shortbow_hagbane_skin_02_magic_01` | `—` | `units/weapons/player/wpn_we_bow_short_02/wpn_we_bow_short_02_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Khelthrax | `we_2h_axe_skin_03_magic_01` | `units/weapons/player/wpn_we_2h_axe_02_t1/wpn_we_2h_axe_02_t1_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Longbow | `es_longbow_skin_04_magic_01` | `—` | `units/weapons/player/wpn_emp_bow_04/wpn_emp_bow_04_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Longsword | `es_1h_sword_skin_04_magic_01` | `units/weapons/player/wpn_emp_sword_03_t2/wpn_emp_sword_03_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Longsword and Shield | `es_1h_sword_shield_skin_04_magic_01` | `units/weapons/player/wpn_emp_sword_03_t2/wpn_emp_sword_03_t2_magic_01` | `units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Mace | `bw_1h_mace_skin_02_magic_01` | `units/weapons/player/wpn_brw_mace_02/wpn_brw_mace_02_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Mace | `es_1h_mace_skin_05_magic_01` | `units/weapons/player/wpn_emp_mace_03_t2/wpn_emp_mace_03_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Mace and Shield | `es_1h_mace_shield_skin_04_magic_01` | `units/weapons/player/wpn_emp_mace_03_t2/wpn_emp_mace_03_t2_magic_01` | `units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Moonfire Bow | `we_deus_02_skin_magic` | `—` | `units/weapons/player/wpn_we_deus_02/wpn_we_deus_02_magic` | `weapon_skins_morris.lua` |
| Weave-Forged Nastirrah | `we_longbow_skin_02_magic_01` | `—` | `units/weapons/player/wpn_we_bow_01_t2/wpn_we_bow_01_t2_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Repeating Handgun | `es_repeating_handgun_skin_01_magic_01` | `units/weapons/player/wpn_emp_handgun_repeater_t1/wpn_emp_handgun_repeater_t1_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Skrundaz | `dw_2h_pick_skin_02_magic_01` | `units/weapons/player/wpn_dw_pick_01_t2/wpn_dw_pick_01_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Spear and Shield | `es_deus_01_skin_magic` | `units/weapons/player/wpn_es_deus_spear_01/wpn_es_deus_spear_01_magic` | `units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic` | `weapon_skins_morris.lua` |
| Weave-Forged Spear and Shield | `es_deus_02_skin_magic` | `units/weapons/player/wpn_es_deus_spear_02/wpn_es_deus_spear_02_magic` | `units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic` | `weapon_skins_morris.lua` |
| Weave-Forged Sword | `bw_1h_sword_skin_06_magic_01` | `units/weapons/player/wpn_brw_sword_03_t2/wpn_brw_sword_03_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Thrund | `dw_handgun_skin_03_magic_01` | `units/weapons/player/wpn_dw_handgun_02_t1/wpn_dw_handgun_02_t1_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Trollhammer Torpedo | `dr_deus_01_skin_magic` | `—` | `units/weapons/player/wpn_dr_deus_01/wpn_dr_deus_01_magic` | `weapon_skins_morris.lua` |
| Weave-Forged Trollhammer Torpedo | `dr_deus_02_skin_magic` | `—` | `units/weapons/player/wpn_dr_deus_02/wpn_dr_deus_02_magic` | `weapon_skins_morris.lua` |
| Weave-Forged Trusty Companions | `es_dual_wield_hammer_sword_skin_02_magic_01` | `units/weapons/player/wpn_emp_mace_04_t3/wpn_emp_mace_04_t3_magic_01` | `units/weapons/player/wpn_emp_sword_06_t2/wpn_emp_sword_06_t2_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Tukaz | `dw_dual_axe_skin_04_magic_01` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2_magic_01` | `units/weapons/player/wpn_dw_axe_02_t2/wpn_dw_axe_02_t2_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Tukgrund | `dr_dual_wield_hammers_skin_01_magic_01` | `units/weapons/player/wpn_dw_hammer_02_t1/wpn_dw_hammer_02_t1_magic_01` | `units/weapons/player/wpn_dw_hammer_02_t1/wpn_dw_hammer_02_t1_magic_01` | `weapon_skins_scorpion.lua` |
| Weave-Forged Tuskgor Spear | `es_2h_heavy_spear_skin_02_magic_01` | `units/weapons/player/wpn_emp_boar_spear_02/wpn_emp_boar_spear_02_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weave-Forged Warhammer | `es_2h_hammer_skin_02_magic_01` | `units/weapons/player/wpn_empire_2h_hammer_01_t2/wpn_2h_hammer_01_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |
| Weavebound Reckoner | `wh_2h_hammer_skin_02_magic_01` | `units/weapons/player/wpn_wh_2h_hammer_02/wpn_wh_2h_hammer_02_magic` | `—` | `weapon_skins_bless.lua` |
| Weavebound Skull-Splitter | `wh_1h_hammer_skin_02_magic_01` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_magic` | `—` | `weapon_skins_bless.lua` |
| Weavebound Soulstealer Staff | `bw_necromancy_staff_skin_02_magic_01` | `units/weapons/player/wpn_bw_necromancy_staff_02/wpn_bw_necromancy_staff_02_magic_01` | `units/weapons/player/wpn_invisible_weapon` | `weapon_skins_shovel.lua` |
| Woodweaver's Moonfire Bow | `we_deus_01_skin_magic` | `—` | `units/weapons/player/wpn_we_deus_01/wpn_we_deus_01_magic` | `weapon_skins_morris.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_brace_of_pistols_skin_05_magic_01` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_magic_01` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_magic_01` | `weapon_skins_scorpion.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_crossbow_skin_06_magic_01` | `—` | `units/weapons/player/wpn_empire_crossbow_t2/wpn_empire_crossbow_tier2_magic_01` | `weapon_skins_scorpion.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_deus_01_skin_magic` | `units/weapons/player/wpn_wh_deus_01/wpn_wh_deus_01_magic` | `units/weapons/player/wpn_wh_deus_01/wpn_wh_deus_01_magic` | `weapon_skins_morris.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_deus_02_skin_magic` | `units/weapons/player/wpn_wh_deus_02/wpn_wh_deus_02_magic` | `units/weapons/player/wpn_wh_deus_02/wpn_wh_deus_02_magic` | `weapon_skins_morris.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_dual_hammer_skin_02_magic_01` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_magic` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_magic` | `weapon_skins_bless.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_dual_wield_axe_falchion_skin_01_magic_01` | `units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2_magic_01` | `units/weapons/player/wpn_emp_sword_05_t2/wpn_emp_sword_05_t2_magic_01` | `weapon_skins_scorpion.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_fencing_sword_skin_07_magic_01` | `units/weapons/player/wpn_fencingsword_04_t2/wpn_fencingsword_04_t2_magic_01` | `units/weapons/player/wpn_emp_pistol_03_t2/wpn_emp_pistol_03_t2_magic_01` | `weapon_skins_scorpion.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_flail_shield_skin_02_magic_01` | `units/weapons/player/wpn_emp_flail_04_t1/wpn_emp_flail_04_t1_magic_01` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_magic` | `weapon_skins_bless.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_hammer_book_skin_02_magic_01` | `units/weapons/player/wpn_wh_book_02/wpn_wh_book_02_magic` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_magic` | `weapon_skins_bless.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_hammer_shield_skin_02_magic_01` | `units/weapons/player/wpn_wh_1h_hammer_02/wpn_wh_1h_hammer_02_magic` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_magic` | `weapon_skins_bless.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_repeating_crossbow_skin_02_magic_01` | `—` | `units/weapons/player/wpn_wh_repeater_crossbow_t2/wpn_wh_repeater_crossbow_t2_magic_01` | `weapon_skins_scorpion.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_repeating_pistol_skin_05_magic_01` | `units/weapons/player/wpn_empire_pistol_repeater_02/wpn_empire_pistol_repeater_02_t2_magic_01` | `—` | `weapon_skins_scorpion.lua` |

### `common` (73 items)

| Display name | Skin key | Right unit | Left unit | Source file |
|---|---|---|---|---|
| Apprentice's Beam Staff | `bw_beam_staff_skin_02` | `units/weapons/player/wpn_brw_beam_staff_02/wpn_brw_beam_staff_02` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Apprentice's Bolt Staff | `bw_spear_staff_skin_02` | `units/weapons/player/wpn_brw_spear_staff_02/wpn_brw_spear_staff_02` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Apprentice's Dagger | `bw_dagger_skin_02` | `units/weapons/player/wpn_brw_dagger_02/wpn_brw_dagger_02` | `—` | `weapon_skins.lua` |
| Apprentice's Flamewave Staff | `bw_flamethrower_staff_skin_02` | `units/weapons/player/wpn_brw_flame_staff_02/wpn_brw_flame_staff_02` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Apprentice's Mace | `bw_1h_mace_skin_02` | `units/weapons/player/wpn_brw_mace_02/wpn_brw_mace_02` | `—` | `weapon_skins.lua` |
| Beardling's Coggrund | `dr_2h_cog_hammer_skin_01` | `units/weapons/player/wpn_dw_coghammer_01_t1/wpn_dw_coghammer_01_t1` | `—` | `weapon_skins_cog.lua` |
| Beardling's Dammaz-Thrund | `dw_grudge_raker_skin_01` | `units/weapons/player/wpn_dw_rakegun_t1/wpn_dw_rakegun_t1` | `—` | `weapon_skins.lua` |
| Beardling's Karinaz | `dw_1h_axe_shield_skin_02` | `units/weapons/player/wpn_dw_axe_01_t2/wpn_dw_axe_01_t2` | `units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02` | `weapon_skins.lua` |
| Beardling's Karingrund | `dw_1h_hammer_shield_skin_02` | `units/weapons/player/wpn_dw_hammer_01_t2/wpn_dw_hammer_01_t2` | `units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02` | `weapon_skins.lua` |
| Beardling's Thrund | `dw_handgun_skin_03` | `units/weapons/player/wpn_dw_handgun_02_t1/wpn_dw_handgun_02_t1` | `—` | `weapon_skins.lua` |
| Beardling's Thrundtak | `dr_steam_pistol_skin_01` | `units/weapons/player/wpn_dw_steam_pistol_01_t1/wpn_dw_steam_pistol_01_t1` | `—` | `weapon_skins_cog.lua` |
| Beardling's Tukaz | `dw_dual_axe_skin_01` | `units/weapons/player/wpn_dw_axe_01_t1/wpn_dw_axe_01_t1` | `units/weapons/player/wpn_dw_axe_01_t1/wpn_dw_axe_01_t1` | `weapon_skins.lua` |
| Boughbreaker | `we_2h_axe_skin_05` | `units/weapons/player/wpn_we_2h_axe_03_t1/wpn_we_2h_axe_03_t1` | `—` | `weapon_skins.lua` |
| Clatterstaff | `bw_necromancy_staff_skin_01` | `units/weapons/player/wpn_bw_necromancy_staff_01/wpn_bw_necromancy_staff_01` | `units/weapons/player/wpn_invisible_weapon` | `weapon_skins_shovel.lua` |
| Death Reign | `we_longbow_skin_05` | `—` | `units/weapons/player/wpn_we_bow_03_t1/wpn_we_bow_03_t1` | `weapon_skins.lua` |
| Evernight | `we_sword_skin_03` | `units/weapons/player/wpn_we_sword_01_t3/wpn_we_sword_01_t3` | `—` | `weapon_skins.lua` |
| Gallant's Blade | `es_bastard_sword_skin_01` | `units/weapons/player/wpn_emp_gk_sword_01_t1/wpn_emp_gk_sword_01_t1` | `—` | `weapon_skins_lake.lua` |
| Glade Guardian's Draich | `we_2h_sword_skin_03` | `units/weapons/player/wpn_we_2h_sword_02_t1/wpn_we_2h_sword_02_t1` | `—` | `weapon_skins.lua` |
| Glade Guardian's Edduath | `we_shortbow_skin_02` | `—` | `units/weapons/player/wpn_we_bow_short_02/wpn_we_bow_short_02` | `weapon_skins.lua` |
| Glade Guardian's Galria | `we_dual_sword_dagger_skin_01` | `units/weapons/player/wpn_we_sword_02_t1/wpn_we_sword_02_t1` | `units/weapons/player/wpn_we_dagger_02_t1/wpn_we_dagger_02_t1` | `weapon_skins.lua` |
| Glade Guardian's Kenuiath | `we_hagbane_skin_02` | `—` | `units/weapons/player/wpn_we_bow_short_02/wpn_we_bow_short_02` | `weapon_skins.lua` |
| Greenleaf's Drannach | `we_spear_skin_01` | `units/weapons/player/wpn_we_spear_01/wpn_we_spear_01` | `—` | `weapon_skins.lua` |
| Greenleaf's Khelthrax | `we_2h_axe_skin_01` | `units/weapons/player/wpn_we_2h_axe_01_t1/wpn_we_2h_axe_01_t1` | `—` | `weapon_skins.lua` |
| Karaz Dumaz | `dw_1h_axe_skin_02` | `units/weapons/player/wpn_dw_axe_01_t2/wpn_dw_axe_01_t2` | `—` | `weapon_skins.lua` |
| Lhunekvinn | `dw_crossbow_skin_03` | `—` | `units/weapons/player/wpn_dw_xbow_02_t1/wpn_dw_xbow_02_t1` | `weapon_skins.lua` |
| Master's Flame-Sword | `bw_1h_flaming_sword_skin_02` | `units/weapons/player/wpn_brw_sword_01_t2/wpn_brw_flaming_sword_01_t2` | `—` | `weapon_skins.lua` |
| Master's Sword | `bw_1h_sword_skin_02` | `units/weapons/player/wpn_brw_sword_01_t2/wpn_brw_sword_01_t2` | `—` | `weapon_skins.lua` |
| Matriarch's Flame-Sword | `bw_1h_flaming_sword_skin_05` | `units/weapons/player/wpn_brw_sword_03_t1/wpn_brw_flaming_sword_03_t1` | `—` | `weapon_skins.lua` |
| Matriarch's Sword | `bw_1h_sword_skin_05` | `units/weapons/player/wpn_brw_sword_03_t1/wpn_brw_sword_03_t1` | `—` | `weapon_skins.lua` |
| Mournglade Kindrathi | `we_javelin_skin_01` | `units/weapons/player/wpn_invisible_weapon` | `units/weapons/player/wpn_we_javelin_01/wpn_we_javelin_01` | `weapon_skins_woods.lua` |
| Mournglade Sariothi | `we_life_staff_skin_01` | `—` | `units/weapons/player/wpn_we_life_staff_01/wpn_we_life_staff_01` | `weapon_skins_woods.lua` |
| Naggrundak Drakktuk | `dw_drake_pistol_skin_03` | `units/weapons/player/wpn_dw_drake_pistol_02_t1/wpn_dw_drake_pistol_02_t1` | `units/weapons/player/wpn_dw_drake_pistol_02_t1/wpn_dw_drake_pistol_02_t1` | `weapon_skins.lua` |
| Noviciate’s Reckoner | `wh_2h_hammer_skin_01` | `units/weapons/player/wpn_wh_2h_hammer_01/wpn_wh_2h_hammer_01` | `—` | `weapon_skins_bless.lua` |
| Noviciate’s Skull-Splitter | `wh_1h_hammer_skin_01` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01` | `—` | `weapon_skins_bless.lua` |
| Noviciate’s Skull-Splitter & Shield | `wh_hammer_shield_skin_01` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1` | `weapon_skins_bless.lua` |
| Poacher's Longbow | `es_longbow_skin_02` | `—` | `units/weapons/player/wpn_emp_bow_02/wpn_emp_bow_02` | `weapon_skins.lua` |
| Sentinel's Ceyl | `we_sword_skin_02` | `units/weapons/player/wpn_we_sword_01_t2/wpn_we_sword_01_t2` | `—` | `weapon_skins.lua` |
| Sentinel's Nastirrath | `we_longbow_skin_02` | `—` | `units/weapons/player/wpn_we_bow_01_t2/wpn_we_bow_01_t2` | `weapon_skins.lua` |
| Shimmerstrike | `we_2h_sword_skin_05` | `units/weapons/player/wpn_we_2h_sword_03_t1/wpn_we_2h_sword_03_t1` | `—` | `weapon_skins.lua` |
| Skarrenruf Maraz | `dw_2h_axe_skin_02` | `units/weapons/player/wpn_dw_2h_axe_01_t2/wpn_dw_2h_axe_01_t2` | `—` | `weapon_skins.lua` |
| Skullsplitter Sword | `wh_1h_falchion_skin_03` | `units/weapons/player/wpn_emp_sword_05_t1/wpn_emp_sword_05_t1` | `—` | `weapon_skins.lua` |
| Soldier's Coach Gun | `es_blunderbuss_skin_03` | `units/weapons/player/wpn_empire_blunderbuss_t1/wpn_empire_blunderbuss_t1` | `—` | `weapon_skins.lua` |
| Soldier's Executioner | `es_2h_sword_exe_skin_02` | `units/weapons/player/wpn_emp_sword_exe_02_t1/wpn_emp_sword_exe_02_t1` | `—` | `weapon_skins.lua` |
| Soldier's Greatsword | `es_2h_sword_skin_03` | `units/weapons/player/wpn_empire_2h_sword_03_t1/wpn_2h_sword_03_t1` | `—` | `weapon_skins.lua` |
| Soldier's Halberd | `es_halberd_skin_02` | `units/weapons/player/wpn_wh_halberd_02/wpn_wh_halberd_02` | `—` | `weapon_skins.lua` |
| Soldier's Handgun | `es_handgun_skin_01` | `units/weapons/player/wpn_empire_handgun_02_t1/wpn_empire_handgun_02_t1` | `—` | `weapon_skins.lua` |
| Soldier's Longsword | `es_1h_sword_skin_03` | `units/weapons/player/wpn_emp_sword_03_t1/wpn_emp_sword_03_t1` | `—` | `weapon_skins.lua` |
| Soldier's Longsword and Shield | `es_1h_sword_shield_skin_03` | `units/weapons/player/wpn_emp_sword_03_t1/wpn_emp_sword_03_t1` | `units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03` | `weapon_skins.lua` |
| Soldier's Mace | `es_1h_mace_skin_02` | `units/weapons/player/wpn_emp_mace_02_t2/wpn_emp_mace_02_t2` | `—` | `weapon_skins.lua` |
| Soldier's Mace and Shield | `es_1h_mace_shield_skin_03` | `units/weapons/player/wpn_emp_mace_02_t3/wpn_emp_mace_02_t3` | `units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03` | `weapon_skins.lua` |
| Soldier's Repeating Handgun | `es_repeating_handgun_skin_01` | `units/weapons/player/wpn_emp_handgun_repeater_t1/wpn_emp_handgun_repeater_t1` | `—` | `weapon_skins.lua` |
| Soldier's Warhammer | `es_2h_hammer_skin_03` | `units/weapons/player/wpn_empire_2h_hammer_02_t1/wpn_2h_hammer_02_t1` | `—` | `weapon_skins.lua` |
| Sputtering Conflagration Staff | `bw_conflagration_staff_skin_01` | `units/weapons/player/wpn_brw_staff_03/wpn_brw_staff_03` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Sputtering Fireball Staff | `bw_fireball_staff_skin_01` | `units/weapons/player/wpn_brw_staff_02/wpn_brw_staff_02` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Stalker's Crossbow | `we_crossbow_skin_01` | `—` | `units/weapons/player/wpn_we_repeater_crossbow_t1/wpn_we_repeater_crossbow_t1` | `weapon_skins.lua` |
| Stalwart's Sword and Shield | `es_sword_shield_breton_skin_01` | `units/weapons/player/wpn_emp_gk_sword_01_t1/wpn_emp_gk_sword_01_t1` | `units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02` | `weapon_skins_lake.lua` |
| Strollaz Grundreugi | `dw_2h_hammer_skin_03` | `units/weapons/player/wpn_dw_2h_hammer_02_t1/wpn_dw_2h_hammer_02_t1` | `—` | `weapon_skins.lua` |
| Templar's Axe | `wh_1h_axe_skin_01` | `units/weapons/player/wpn_axe_02_t1/wpn_axe_02_t1` | `—` | `weapon_skins.lua` |
| Templar's Flail | `es_1h_flail_skin_02` | `units/weapons/player/wpn_emp_flail_02_t1/wpn_emp_flail_02_t1` | `—` | `weapon_skins.lua` |
| Templar's Greatsword | `wh_2h_sword_skin_03` | `units/weapons/player/wpn_empire_2h_sword_02_t3/wpn_2h_sword_02_t3` | `—` | `weapon_skins.lua` |
| Von Meinkopt's Single-Shooter | `es_handgun_skin_04` | `units/weapons/player/wpn_empire_handgun_t2/wpn_empire_handgun_t2` | `—` | `weapon_skins.lua` |
| Vysserik's Verdigrised Vanquisher | `bw_ghost_scythe_skin_01` | `units/weapons/player/wpn_bw_ghost_scythe_01/wpn_bw_ghost_scythe_01` | `—` | `weapon_skins_shovel.lua` |
| Warrior's Drakkthrund | `dw_drakegun_skin_01` | `units/weapons/player/wpn_dw_iron_drake_01/wpn_dw_iron_drake_01_t1` | `—` | `weapon_skins.lua` |
| Warrior's Grund | `dw_1h_hammer_skin_02` | `units/weapons/player/wpn_dw_hammer_01_t2/wpn_dw_hammer_01_t2` | `—` | `weapon_skins.lua` |
| Warrior's Skrundaz | `dw_2h_pick_skin_02` | `units/weapons/player/wpn_dw_pick_01_t2/wpn_dw_pick_01_t2` | `—` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_brace_of_pistols_skin_04` | `units/weapons/player/wpn_emp_pistol_03_t1/wpn_emp_pistol_03_t1` | `units/weapons/player/wpn_emp_pistol_03_t1/wpn_emp_pistol_03_t1` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_crossbow_skin_01` | `—` | `units/weapons/player/wpn_emp_crossbow_02_t1/wpn_emp_crossbow_02_t1` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_dual_hammer_skin_01` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01` | `weapon_skins_bless.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_fencing_sword_skin_02` | `units/weapons/player/wpn_fencingsword_02_t1/wpn_fencingsword_02_t1` | `units/weapons/player/wpn_emp_pistol_02_t2/wpn_emp_pistol_02_t2` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_fencing_sword_skin_07` | `units/weapons/player/wpn_fencingsword_04_t2/wpn_fencingsword_04_t2` | `units/weapons/player/wpn_emp_pistol_01_t1/wpn_emp_pistol_01_t1` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_flail_shield_skin_01` | `units/weapons/player/wpn_emp_flail_02_t1/wpn_emp_flail_02_t1` | `units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1` | `weapon_skins_bless.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_hammer_book_skin_01` | `units/weapons/player/wpn_wh_book_02/wpn_wh_book_02` | `units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01` | `weapon_skins_bless.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_repeating_pistol_skin_01` | `units/weapons/player/wpn_empire_pistol_repeater/wpn_empire_pistol_repeater_t1` | `—` | `weapon_skins.lua` |

### `plentiful` (54 items)

| Display name | Skin key | Right unit | Left unit | Source file |
|---|---|---|---|---|
| Adjudicator's Flail | `es_1h_flail_skin_01` | `units/weapons/player/wpn_emp_flail_01_t1/wpn_emp_flail_01_t1` | `—` | `weapon_skins.lua` |
| Amadri's Dawnspear | `we_spear_skin_04` | `units/weapons/player/wpn_we_spear_04/wpn_we_spear_04` | `—` | `weapon_skins.lua` |
| Apprentice's Flame-Sword | `bw_1h_flaming_sword_skin_01` | `units/weapons/player/wpn_brw_sword_01_t1/wpn_brw_flaming_sword_01_t1` | `—` | `weapon_skins.lua` |
| Apprentice's Sword | `bw_1h_sword_skin_01` | `units/weapons/player/wpn_brw_sword_01_t1/wpn_brw_sword_01_t1` | `—` | `weapon_skins.lua` |
| Beardling's Az | `dw_1h_axe_skin_01` | `units/weapons/player/wpn_dw_axe_01_t1/wpn_dw_axe_01_t1` | `—` | `weapon_skins.lua` |
| Beardling's Az-Dreugi | `dw_2h_axe_skin_01` | `units/weapons/player/wpn_dw_2h_axe_01_t1/wpn_dw_2h_axe_01_t1` | `—` | `weapon_skins.lua` |
| Beardling's Debgrozthrund Trolldrengi | `dr_deus_01_skin_01` | `—` | `units/weapons/player/wpn_dr_deus_01/wpn_dr_deus_01` | `weapon_skins_morris.lua` |
| Beardling's Drakkthrund | `dw_drakegun_skin_02` | `units/weapons/player/wpn_dw_iron_drake_02/wpn_dw_iron_drake_02` | `—` | `weapon_skins.lua` |
| Beardling's Drakktuk | `dw_drake_pistol_skin_01` | `units/weapons/player/wpn_dw_drake_pistol_01_t1/wpn_dw_drake_pistol_01_t1` | `units/weapons/player/wpn_dw_drake_pistol_01_t1/wpn_dw_drake_pistol_01_t1` | `weapon_skins.lua` |
| Beardling's Drekmakaz | `dw_crossbow_skin_01` | `—` | `units/weapons/player/wpn_dw_xbow_01_t1/wpn_dw_xbow_01_t1` | `weapon_skins.lua` |
| Beardling's Grund | `dw_1h_hammer_skin_01` | `units/weapons/player/wpn_dw_hammer_01_t1/wpn_dw_hammer_01_t1` | `—` | `weapon_skins.lua` |
| Beardling's Grundreugi | `dw_2h_hammer_skin_01` | `units/weapons/player/wpn_dw_2h_hammer_01_t1/wpn_dw_2h_hammer_01_t1` | `—` | `weapon_skins.lua` |
| Beardling's Skrundaz | `dw_2h_pick_skin_01` | `units/weapons/player/wpn_dw_pick_01_t1/wpn_dw_pick_01_t1` | `—` | `weapon_skins.lua` |
| Feeble Mace | `bw_1h_mace_skin_01` | `units/weapons/player/wpn_brw_mace_01/wpn_brw_mace_01` | `—` | `weapon_skins.lua` |
| Gallant's Sword and Shield | `es_sword_shield_breton_skin_05` | `units/weapons/player/wpn_emp_gk_sword_01_t1/wpn_emp_gk_sword_01_t1` | `units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03` | `weapon_skins_lake.lua` |
| Glade Guardian's Ceyl | `we_sword_skin_01` | `units/weapons/player/wpn_we_sword_01_t1/wpn_we_sword_01_t1` | `—` | `weapon_skins.lua` |
| Glade Guardian's Glaia | `we_dual_dagger_skin_01` | `units/weapons/player/wpn_we_dagger_01_t1/wpn_we_dagger_01_t1` | `units/weapons/player/wpn_we_dagger_01_t1/wpn_we_dagger_01_t1` | `weapon_skins.lua` |
| Glade Guardian's Nastirrath | `we_longbow_skin_01` | `—` | `units/weapons/player/wpn_we_bow_01_t1/wpn_we_bow_01_t1` | `weapon_skins.lua` |
| Greenleaf's Celya | `we_dual_sword_skin_04` | `units/weapons/player/wpn_we_sword_01_t1/wpn_we_sword_01_t1` | `units/weapons/player/wpn_we_sword_01_t1/wpn_we_sword_01_t1` | `weapon_skins.lua` |
| Greenleaf's Draich | `we_2h_sword_skin_01` | `units/weapons/player/wpn_we_2h_sword_01_t1/wpn_we_2h_sword_01_t1` | `—` | `weapon_skins.lua` |
| Greenleaf's Edduath | `we_shortbow_skin_01` | `—` | `units/weapons/player/wpn_we_bow_short_01/wpn_we_bow_short_01` | `weapon_skins.lua` |
| Greenleaf's Galria | `we_dual_sword_dagger_skin_04` | `units/weapons/player/wpn_we_sword_01_t1/wpn_we_sword_01_t1` | `units/weapons/player/wpn_we_dagger_01_t1/wpn_we_dagger_01_t1` | `weapon_skins.lua` |
| Greenleaf's Kenuiath | `we_hagbane_skin_01` | `—` | `units/weapons/player/wpn_we_bow_short_01/wpn_we_bow_short_01` | `weapon_skins.lua` |
| Greenleaf's Moonfire Bow | `we_deus_01_skin_01` | `—` | `units/weapons/player/wpn_we_deus_01/wpn_we_deus_01` | `weapon_skins_morris.lua` |
| Patchwork Axe | `wh_1h_axe_skin_05` | `units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1` | `—` | `weapon_skins.lua` |
| Patchwork Pistols | `wh_brace_of_pistols_skin_01` | `units/weapons/player/wpn_emp_pistol_01_t1/wpn_emp_pistol_01_t1` | `units/weapons/player/wpn_emp_pistol_01_t1/wpn_emp_pistol_01_t1` | `weapon_skins.lua` |
| Recruit's Blunderbuss | `es_blunderbuss_skin_01` | `units/weapons/player/wpn_empire_blunderbuss_02_t1/wpn_empire_blunderbuss_02_t1` | `—` | `weapon_skins.lua` |
| Recruit's Chopping Stick | `es_halberd_skin_01` | `units/weapons/player/wpn_wh_halberd_01/wpn_wh_halberd_01` | `—` | `weapon_skins.lua` |
| Recruit's Executioner | `es_2h_sword_exe_skin_01` | `units/weapons/player/wpn_emp_sword_exe_01_t1/wpn_emp_sword_exe_01_t1` | `—` | `weapon_skins.lua` |
| Recruit's Greatsword | `es_2h_sword_skin_01` | `units/weapons/player/wpn_empire_2h_sword_01_t1/wpn_2h_sword_01_t1` | `—` | `weapon_skins.lua` |
| Recruit's Handgun | `es_handgun_skin_03` | `units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1` | `—` | `weapon_skins.lua` |
| Recruit's Longsword | `es_1h_sword_skin_01` | `units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1` | `—` | `weapon_skins.lua` |
| Recruit's Longsword and Shield | `es_1h_sword_shield_skin_02` | `units/weapons/player/wpn_emp_sword_02_t2/wpn_emp_sword_02_t2` | `units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02` | `weapon_skins.lua` |
| Recruit's Mace | `es_1h_mace_skin_01` | `units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1` | `—` | `weapon_skins.lua` |
| Recruit's Mace and Shield | `es_1h_mace_shield_skin_02` | `units/weapons/player/wpn_emp_mace_02_t2/wpn_emp_mace_02_t2` | `units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02` | `weapon_skins.lua` |
| Recruit's Spear and Shield | `es_deus_01_skin_01` | `units/weapons/player/wpn_es_deus_spear_01/wpn_es_deus_spear_01` | `units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02` | `weapon_skins_morris.lua` |
| Recruit's Warhammer | `es_2h_hammer_skin_05` | `units/weapons/player/wpn_empire_2h_hammer_03_t1/wpn_2h_hammer_03_t1` | `—` | `weapon_skins.lua` |
| Soldier's Longbow | `es_longbow_skin_01` | `—` | `units/weapons/player/wpn_emp_bow_01/wpn_emp_bow_01` | `weapon_skins.lua` |
| Sputtering Beam Staff | `bw_beam_staff_skin_01` | `units/weapons/player/wpn_brw_beam_staff_01/wpn_brw_beam_staff_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Sputtering Bolt Staff | `bw_spear_staff_skin_01` | `units/weapons/player/wpn_brw_spear_staff_01/wpn_brw_spear_staff_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Sputtering Coruscation Staff | `bw_deus_01_skin_01` | `units/weapons/player/wpn_bw_deus_01/wpn_bw_deus_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins_morris.lua` |
| Sputtering Flamewave Staff | `bw_flamethrower_staff_skin_01` | `units/weapons/player/wpn_brw_flame_staff_01/wpn_brw_flame_staff_01` | `units/weapons/player/wpn_fireball/wpn_fireball` | `weapon_skins.lua` |
| Templar's Excoriator | `wh_1h_falchion_skin_01` | `units/weapons/player/wpn_emp_sword_04_t1/wpn_emp_sword_04_t1` | `—` | `weapon_skins.lua` |
| Tilean Paperweight | `bw_dagger_skin_01` | `units/weapons/player/wpn_brw_dagger_01/wpn_brw_dagger_01` | `—` | `weapon_skins.lua` |
| Twilight's Last Gleaming | `we_2h_axe_skin_07` | `units/weapons/player/wpn_we_2h_axe_04_t1/wpn_we_2h_axe_04_t1` | `—` | `weapon_skins.lua` |
| Umgak Karinaz | `dw_1h_axe_shield_skin_01` | `units/weapons/player/wpn_dw_axe_01_t1/wpn_dw_axe_01_t1` | `units/weapons/player/wpn_dw_shield_01_t1/wpn_dw_shield_01` | `weapon_skins.lua` |
| Umgak Karingrund | `dw_1h_hammer_shield_skin_01` | `units/weapons/player/wpn_dw_hammer_01_t1/wpn_dw_hammer_01_t1` | `units/weapons/player/wpn_dw_shield_01_t1/wpn_dw_shield_01` | `weapon_skins.lua` |
| Umgak Thrund | `dw_handgun_skin_01` | `units/weapons/player/wpn_dw_handgun_01_t1/wpn_dw_handgun_01_t1` | `—` | `weapon_skins.lua` |
| Umgak Tukaz | `dw_dual_axe_skin_05` | `units/weapons/player/wpn_dw_axe_03_t1/wpn_dw_axe_03_t1` | `units/weapons/player/wpn_dw_axe_03_t1/wpn_dw_axe_03_t1` | `weapon_skins.lua` |
| Unbalanced Greatsword | `wh_2h_sword_skin_01` | `units/weapons/player/wpn_empire_2h_sword_02_t1/wpn_2h_sword_02_t1` | `—` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_crossbow_skin_05` | `—` | `units/weapons/player/wpn_empire_crossbow_t1/wpn_empire_crossbow_tier1` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_deus_01_skin_01` | `units/weapons/player/wpn_wh_deus_01/wpn_wh_deus_01` | `units/weapons/player/wpn_wh_deus_01/wpn_wh_deus_01` | `weapon_skins_morris.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_fencing_sword_skin_01` | `units/weapons/player/wpn_fencingsword_01_t1/wpn_fencingsword_01_t1` | `units/weapons/player/wpn_emp_pistol_01_t1/wpn_emp_pistol_01_t1` | `weapon_skins.lua` |
| _(name unresolved — re-run /dump_skin_rarities with no sample limit)_ | `wh_repeating_pistol_skin_04` | `units/weapons/player/wpn_empire_pistol_repeater_02/wpn_empire_pistol_repeater_02_t1` | `—` | `weapon_skins.lua` |

### `promo` (16 items)

| Display name | Skin key | Right unit | Left unit | Source file |
|---|---|---|---|---|
| Beardling's Azdrek | `dr_1h_throwing_axes_skin_01` | `units/weapons/player/wpn_invisible_weapon` | `—` | `weapon_skins_anvil.lua` |
| Cherished Azdrek | `dr_1h_throwing_axes_skin_01_runed_01` | `units/weapons/player/wpn_invisible_weapon` | `—` | `weapon_skins_anvil.lua` |
| Cruciform Firebox | `bw_1h_flail_flaming_skin_02` | `units/weapons/player/wpn_brw_flaming_flail_02/wpn_brw_flaming_flail_02` | `—` | `weapon_skins_anvil.lua` |
| Dressad's Roaster | `bw_1h_flail_flaming_skin_01` | `units/weapons/player/wpn_brw_flaming_flail_01/wpn_brw_flaming_flail_01` | `—` | `weapon_skins_anvil.lua` |
| Giantkiller's Spear | `es_2h_heavy_spear_skin_01_runed_01` | `units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_runed_01` | `—` | `weapon_skins_anvil.lua` |
| Huntsman's Spear | `es_2h_heavy_spear_skin_01` | `units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01` | `—` | `weapon_skins_anvil.lua` |
| Krelgar's Redeemer | `wh_2h_billhook_skin_02` | `units/weapons/player/wpn_wh_billhook_02/wpn_wh_billhook_02` | `—` | `weapon_skins_anvil.lua` |
| Longbeard's Azdrek | `dr_1h_throwing_axes_skin_02` | `units/weapons/player/wpn_invisible_weapon` | `—` | `weapon_skins_anvil.lua` |
| Princess's Glamour-Shield | `we_1h_spears_shield_skin_01_runed_01` | `units/weapons/player/wpn_we_spear_03/wpn_we_spear_03` | `units/weapons/player/wpn_we_shield_01/wpn_we_shield_01_runed_01` | `weapon_skins_anvil.lua` |
| Sea Guard's Drannach-Isalt | `we_1h_spears_shield_skin_02` | `units/weapons/player/wpn_we_spear_02/wpn_we_spear_02` | `units/weapons/player/wpn_we_shield_02/wpn_we_shield_02` | `weapon_skins_anvil.lua` |
| Templar's Spear | `es_2h_heavy_spear_skin_02` | `units/weapons/player/wpn_emp_boar_spear_02/wpn_emp_boar_spear_02` | `—` | `weapon_skins_anvil.lua` |
| The Boegarmund Blade | `wh_2h_billhook_skin_01_runed_01` | `units/weapons/player/wpn_wh_billhook_01/wpn_wh_billhook_01_runed_01` | `—` | `weapon_skins_anvil.lua` |
| The Brass Flail | `bw_1h_flail_flaming_skin_01_runed_01` | `units/weapons/player/wpn_brw_flaming_flail_01/wpn_brw_flaming_flail_01_runed_01` | `—` | `weapon_skins_anvil.lua` |
| The Spear of Stirland | `wh_2h_billhook_skin_01` | `units/weapons/player/wpn_wh_billhook_01/wpn_wh_billhook_01` | `—` | `weapon_skins_anvil.lua` |
| Tiranoc Watch-Shield | `we_1h_spears_shield_skin_01` | `units/weapons/player/wpn_we_spear_01/wpn_we_spear_01` | `units/weapons/player/wpn_we_shield_01/wpn_we_shield_01` | `weapon_skins_anvil.lua` |
| Weave-Forged Azdrek | `dr_1h_throwing_axes_skin_02_magic_01` | `units/weapons/player/wpn_invisible_weapon` | `—` | `weapon_skins_scorpion.lua` |
