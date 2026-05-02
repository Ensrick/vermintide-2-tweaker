<!--
REVIEW (2026-05-01): Reference content (career codes, native ownership, phantom events,
cross-character compat matrix) is consistent with WEAPON_CATALOG.md and WORK_ITEMS.md. No
build/upload references in this file.

The "Known Working Cross-Character Combinations" table is a high-level summary that overlaps
with WEAPON_CATALOG.md's status columns. Consider noting which is authoritative: WEAPON_CATALOG.md
labels itself as "the authoritative source" (DEVELOPMENT.md confirms this).

Suggest adding a one-line cross-reference at top: "See WEAPON_CATALOG.md for per-weapon attack
chain detail and remap-table identity; this file is a high-level compatibility summary."
-->
# Weapon & Animation Compatibility Reference

## Character Models

Each character has one shared model across all careers, except Warrior Priest:

| Character   | Model          | Notes                                        |
|-------------|----------------|----------------------------------------------|
| Kruber      | `es_` skeleton | Shared by Mercenary, Huntsman, FK, GK        |
| Bardin      | `dr_` skeleton | Shared by Ranger, Ironbreaker, Slayer, Engi  |
| Kerillian   | `we_` skeleton | Shared by Waystalker, Handmaiden, Shade, SotT|
| Saltzpyre   | `wh_` skeleton | Shared by WHC, BH, Zealot                    |
| Warrior Priest | unique skeleton | Only career with its own model/skeleton    |
| Sienna      | `bw_` skeleton | Shared by Battle Wizard, Pyro, Unchained, Necro |

## Native Weapon Ownership

### One-Handed Melee (by wield animation)

| Weapon Key           | Display Name            | Native To  | Wield Anim                     |
|----------------------|-------------------------|------------|--------------------------------|
| `es_1h_sword`        | Kruber's Sword          | Kruber     | `to_1h_sword`                  |
| `es_1h_mace`         | Kruber's Mace           | Kruber     | `to_1h_mace`                   |
| `dr_1h_axe`          | Bardin's Axe            | Bardin     | `to_1h_axe`                    |
| `dr_1h_hammer`       | Bardin's Hammer         | Bardin     | `to_1h_hammer`                 |
| `we_1h_sword`        | Kerillian's Sword       | Kerillian  | `to_1h_sword`                  |
| `wh_1h_falchion`     | Saltzpyre's Falchion    | Saltzpyre  | `to_1h_falchion`               |
| `wh_1h_axe`          | Saltzpyre's Axe         | Saltzpyre  | `to_1h_axe`                    |
| `wh_1h_hammer`       | Saltzpyre's Hammer      | Saltzpyre  | `to_1h_hammer`                 |
| `bw_sword`           | Sienna's Sword          | Sienna     | `to_1h_sword`                  |
| `bw_1h_crowbill`     | Sienna's Crowbill       | Sienna     | `to_1h_crowbill`               |

### Shield Weapons

| Weapon Key           | Display Name            | Native To      | Wield Anim                     |
|----------------------|-------------------------|----------------|--------------------------------|
| `es_mace_shield`     | Kruber's Mace & Shield  | Kruber         | `to_1h_hammer_shield`          |
| `dr_shield_hammer`   | Bardin's Hammer & Shield| Bardin         | `to_1h_hammer_shield`          |
| `dr_shield_axe`      | Bardin's Axe & Shield   | Bardin         | `to_1h_axe_shield`             |
| `wh_hammer_shield`   | Skullsplitter           | Warrior Priest | `to_1h_hammer_shield_priest`   |
| `es_deus_01`         | Kruber's Spear & Shield | Kruber         | (spear anim)                   |
| `we_1h_spears_shield`| Kerillian's Spear & Shield | Kerillian   | (spear anim)                   |

### Ranged Weapons (cross-character)

| Weapon Key              | Display Name                | Native To  | Wield Anim                       |
|-------------------------|-----------------------------|------------|----------------------------------|
| `we_longbow`            | Kerillian's Longbow         | Kerillian  | `to_longbow`                     |
| `es_longbow`            | Kruber's Longbow            | Kruber     | `to_es_longbow`                  |
| `we_crossbow_repeater`  | Kerillian's Volley Crossbow | Kerillian  | `to_repeating_crossbow_elf`      |
| `wh_crossbow_repeater`  | Saltzpyre's Volley Crossbow | Saltzpyre  | `to_repeating_crossbow`          |
| `dr_crossbow`           | Bardin's Crossbow           | Bardin     | `to_crossbow`                    |
| `wh_crossbow`           | Saltzpyre's Crossbow        | Saltzpyre  | `to_crossbow`                    |

## Animation Compatibility

### Phantom Events (career-aware redirect required)

These animation events exist on ALL character skeletons but only play real animations on the native character. `Unit.has_animation_event()` returns `true` for all of them, making standard detection impossible. Must use career prefix matching.

| Event                          | Real On     | Redirect Target               | Notes                          |
|--------------------------------|-------------|-------------------------------|--------------------------------|
| `to_longbow`                   | Kerillian   | `to_es_longbow`               | Kruber has his own longbow anim|
| `to_repeating_crossbow_elf`    | Kerillian   | `to_repeating_crossbow`       | Saltzpyre volley crossbow anim |
| `to_1h_crowbill`               | Sienna      | `to_1h_sword`                 | WP override: `to_1h_hammer_shield_priest` |
| `to_1h_axe`                    | Non-Sienna  | `to_1h_sword` (for Sienna)    | WP override: `to_1h_hammer_shield_priest` |
| `to_1h_sword`                  | Non-WP      | `to_1h_hammer_shield_priest` (for WP) | WP has unique skeleton |
| `to_1h_hammer_shield_priest`   | WP only     | `to_1h_hammer_shield`         | For non-WP Saltzpyre careers   |

### Standard Redirects (has_animation_event check)

These events are genuinely missing from non-native skeletons, so `Unit.has_animation_event()` works correctly.

| Event                          | Fallback                      | Notes                          |
|--------------------------------|-------------------------------|--------------------------------|
| `to_repeating_crossbow`        | `to_repeating_crossbow_elf`   | Saltzpyre's on Kerillian       |
| `to_es_longbow`                | `to_longbow`                  | Kruber's on Kerillian          |

### Known Working Cross-Character Combinations

| Weapon                  | Works On          | Animation Used        | Status     |
|-------------------------|-------------------|-----------------------|------------|
| Flaming Flail (Sienna)  | Saltzpyre careers | Native (partial)      | Tested — heavy attack wind-up animation missing, all else works |
| Flaming Flail (Sienna)  | Kruber careers    | Native                | Tested     |
| Flail (Saltzpyre)       | Sienna careers    | Native (partial)      | Tested — heavy attack wind-up animation missing, all else works |
| Crowbill (Sienna)       | All non-Sienna    | 1H sword              | Tested     |
| Crowbill (Sienna)       | Warrior Priest    | Skullsplitter         | Tested     |
| Axes (any)              | Sienna            | 1H sword              | Tested     |
| Axes (any)              | Warrior Priest    | Skullsplitter         | Tested     |
| 1H Swords (any)         | Warrior Priest    | Skullsplitter         | Tested     |
| Kerillian Volley Xbow   | Saltzpyre careers | His volley xbow anim  | Tested     |
| Saltzpyre Volley Xbow   | Kerillian careers | Her volley xbow anim  | Tested     |
| Kerillian Longbow       | Kruber careers    | His longbow anim      | Tested     |
| Kruber Longbow          | Kerillian careers | Her longbow anim      | Tested     |
| Skullsplitter           | Kruber/Bardin     | Hammer & shield       | Tested     |
| Mace & Shield (Kruber)  | Warrior Priest    | Native? (untested)    | Untested   |
| Hammer & Shield (Bardin)| Warrior Priest    | Native? (untested)    | Untested   |

### Known Crashes / Incompatibilities

| Weapon                  | Crashes On              | Reason                                    |
|-------------------------|-------------------------|-------------------------------------------|
| `wh_hammer_shield`      | Sienna, Kerillian, WHC/BH/Zealot | Missing shield model/skeleton support |
| `we_1h_spears_shield`   | Kruber (Grail Knight)   | Missing model/animations for Kruber       |

### Untested / Unknown

- Flail (`es_1h_flail`) — has `es_` prefix but is a Saltzpyre weapon (likely a dev design change). Kruber has native animations for it, no redirect needed
- Falchion (`wh_1h_falchion`) animation `to_1h_falchion` — works natively on all careers except Warrior Priest; WP redirects to `to_1h_hammer`
- Mace (`es_1h_mace`) animation `to_1h_mace` — works natively on all careers, no redirect needed
- Hammer (`dr_1h_hammer`) animation `to_1h_hammer` — works natively on all careers, no redirect needed
- Hammer (`wh_1h_hammer`) animation `to_1h_hammer` — expected to work natively on all skeletons, untested
- Bardin's 2H weapons on other characters
- All Sienna staves crash the game when equipped on any non-Sienna career

## Career Internal IDs

| Career ID          | Display Name         | Character  | Career Index |
|--------------------|----------------------|------------|--------------|
| `es_mercenary`     | Mercenary            | Kruber     | 1            |
| `es_huntsman`      | Huntsman             | Kruber     | 2            |
| `es_knight`        | Foot Knight          | Kruber     | 3            |
| `es_questingknight`| Grail Knight         | Kruber     | 4            |
| `dr_ranger`        | Ranger Veteran       | Bardin     | 1            |
| `dr_ironbreaker`   | Ironbreaker          | Bardin     | 2            |
| `dr_slayer`        | Slayer               | Bardin     | 3            |
| `dr_engineer`      | Engineer             | Bardin     | 4            |
| `we_waywatcher`    | Waystalker           | Kerillian  | 1            |
| `we_maidenguard`   | Handmaiden           | Kerillian  | 2            |
| `we_shade`         | Shade                | Kerillian  | 3            |
| `we_thornsister`   | Sister of the Thorn  | Kerillian  | 4            |
| `wh_captain`       | Witch Hunter Captain | Saltzpyre  | 1            |
| `wh_bountyhunter`  | Bounty Hunter        | Saltzpyre  | 2            |
| `wh_zealot`        | Zealot               | Saltzpyre  | 3            |
| `wh_priest`        | Warrior Priest       | Saltzpyre  | 4            |
| `bw_adept`         | Battle Wizard        | Sienna     | 1            |
| `bw_scholar`       | Pyromancer           | Sienna     | 2            |
| `bw_unchained`     | Unchained            | Sienna     | 3            |
| `bw_necromancer`   | Necromancer          | Sienna     | 4            |
