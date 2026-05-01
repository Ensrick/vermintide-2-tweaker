# Changelog

## [2026-04-29] cosmetics_tweaker v0.7.0-dev
### Added
- Unlock All Portrait Frames toggle (modded only, DLC ownership respected)

## [2026-04-29] cosmetics_tweaker v0.6.38-dev
### Added
- DLC ownership gate — skins requiring unowned DLC stay locked even with Unlock All Illusions enabled
- Full modded-realm illusion unlock/apply pipeline (5 hook points, up from 3)

### Fixed
- Locked illusions not applying — missing fake backend IDs, UI locked flag, craft button eac-untrusted gate
- Applied skins stripped on backend refresh — `bypass_skin_ownership_check` now set on local craft

## [2026-04-29] weapon_tweaker v0.10.6-dev
### Added
- Grip offset for Kruber wielding Saltzpyre's Skullsplitter (`wh_1h_hammer`, z +0.15)
- Grip offset for Kruber wielding Saltzpyre's Skullsplitter & Shield (`wh_hammer_shield`, right hand only, z +0.15)
- Per-hand grip offset support — offset entries can specify `hand = "right"` or `hand = "left"` to target one hand only (default both)

### Fixed
- Menu preview grip offsets not applying — `MenuWorldPreviewer._spawn_item_unit` resolved `self._character_name` (hero name like `empire_soldier`) before `_local_career_name()` (career name like `es_mercenary`), so the `es_` prefix never matched
- Menu preview grip offsets applied 4x — `fake_slot` pointed all four unit fields at the same unit, causing the additive offset to quadruple
- `BackendInterfaceWeavesPlayFab.commit` hook error — `commit` method doesn't exist on that class; moved hook to `BackendManagerPlayFab.commit`

## [2026-04-28] cosmetics_tweaker v0.6.19-dev
### Added
- Modded-realm illusion swap — Apply button re-enabled, craft calls intercepted locally instead of PlayFab
- Custom illusion injection system — new weapon skins appear as selectable illusions in the vanilla browser
- "Mace & Bretonnian Shield" custom illusion (Empire mace + GK Bretonnian shield)
- Unlock All Weapon Illusions toggle (modded only)
- Bretonnian Sword & Shield thickness fix (sword only, shield unaffected)
- Loremaster's Armoury bridge toggle

### Fixed
- Craft button sound loop caused by stale `is_held` hotspot flag after fast local craft completion
- Inventory preview scaling both sword and shield on Bretonnian weapons (now right-hand only via `_fields`)
- Illusion browser not applying scale overrides (skin key resolution via `matching_item_key`)

## [2026-04-24 v0.4.0-dev]
### Added
- Two-tier animation redirect system: career-aware redirects for phantom events + standard `has_animation_event` fallback
- Cross-character ranged animation redirects:
  - Kerillian's Volley Crossbow on Saltzpyre careers uses his native volley crossbow animations (`to_repeating_crossbow`)
  - Saltzpyre's Volley Crossbow on Kerillian careers uses her native volley crossbow animations (`to_repeating_crossbow_elf`)
  - Kerillian's Longbow on Kruber careers uses his native longbow animations (`to_es_longbow`)
  - Kruber's Longbow on Kerillian careers uses her native longbow animations (`to_longbow`)
- Cross-character melee animation redirects:
  - Sienna's Crowbill (`bw_1h_crowbill`) uses 1H sword animation on non-Sienna careers; WP uses skullsplitter animation
  - Axes (`to_1h_axe`) redirect to 1H sword on Sienna careers; WP uses skullsplitter animation
  - 1H swords (`to_1h_sword`) redirect to skullsplitter animation on WP
  - Skullsplitter (`to_1h_hammer_shield_priest`) redirects to `to_1h_hammer_shield` on non-WP careers
- New weapon unlocks:
  - Saltzpyre's Volley Crossbow (`wh_crossbow_repeater`) for all 4 Kerillian careers
  - Sienna's Crowbill (`bw_1h_crowbill`) for all non-Sienna careers
  - Saltzpyre's Hammer (`wh_1h_hammer`) for all careers
  - Saltzpyre's Skullsplitter (`wh_hammer_shield`) for Kruber and Bardin careers only (crashes on characters without shield model)
  - Kruber's Mace & Shield (`es_mace_shield`) and Bardin's Hammer & Shield (`dr_shield_hammer`) for Warrior Priest
- Career action injection: non-native weapon templates now receive the career's ability action so career abilities work with cross-character weapons

### Fixed
- Battle Wizard (`bw_adept`) and Pyromancer (`bw_scholar`) career names were swapped — corrected labels and menu order
- Skullsplitter restricted to Kruber/Bardin only — shield weapons crash on characters without shield skeleton support

### Technical
- Career-aware redirect table (`_career_anim_redirect`) handles phantom animation events that exist on all skeletons but only play real animations on native characters
- `invert` flag controls redirect direction: `false` = redirect when career doesn't match prefix, `true` = redirect when it does
- `overrides` map allows per-career alternative targets (e.g., WP gets `to_1h_hammer_shield_priest` instead of default `to_1h_sword`)
- Standard redirect table (`_anim_redirect`) uses `Unit.has_animation_event` native check for genuinely missing events
- All redirect calls wrapped in `pcall` to prevent crashes from animation mismatches

## [2026-04-24 v0.3.0-dev]
### Fixed
- Removed `we_1h_spears_shield` (Kerillian's Spear & Shield) from Grail Knight — crashes hero previewer due to missing model/animations for Kruber.
- Added `es_deus_01` (Kruber's Spear & Shield) to Grail Knight instead. Note: weapon key is `es_deus_01`, not an obvious name.

### Added
- `wt dump` command — dumps all equipped item data (key, item_type, template, rarity, units, can_wield) to console log.
- Cross-character longbow unlocks: `we_longbow` for all 4 Kruber careers, `es_longbow` for all 4 Kerillian careers.
- Cross-character crossbow unlocks: `dr_crossbow` for WHC/BH/Zealot, `wh_crossbow` for all 4 Bardin careers.
- Kerillian's Volley Crossbow (`we_crossbow_repeater`) for all 4 Saltzpyre careers.
- Bardin's Crossbow (`dr_crossbow`) for Engineer and Slayer.
- Bardin's Throwing Axes (`dr_1h_throwing_axes`) for Ironbreaker and Engineer.
- Separated ranged weapon unlocks into dedicated Ranged section in mod settings menu.

## [2026-04-23]
### Changed
- Modularized the project into three separate mods: `weapon_tweaker`, `career_tweaker`, and `chaos_wastes_tweaker`.
- Updated `weapon_tweaker` with the core weapon unlocking and animation logic.

### Fixed
- Fixed a fatal Stingray compiler crash caused by missing `valid_tags` in `lua_preprocessor_defines.config`.
- Improved hook safety in `weapon_tweaker.lua` to prevent engine-level assertion failures when pcall fails.

### Added
- Aggressive debug logging for weapon creation, animation events, and slot wielding in `weapon_tweaker`.
- New `enable_weapon_debug_logging` setting to toggle detailed logs.

## [2026-04-21]
### Fixed
- Fixed `BackendUtils.get_item_units` hook that was causing crashes by incorrectly handling return values.
- Fixed `apply_weapon_unlocks` to correctly restore `can_wield` to `nil` when the original was `nil`.
