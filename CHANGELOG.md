# Changelog

## 2026-07-13 - `character_weapon_variants` replicated cross-access swing audio

Repo-aggregate entry for Character Weapon Variants v0.1.393-dev / issue #398. Cross-access 3P event substitution now occurs before vanilla encodes and sends its animation RPC, so observers receive the same receiver-compatible animation and its authored weapon-foley/exertion timeline as the owner. The change deliberately leaves playback with vanilla rather than manually emitting Wwise events. Added bounded diagnostics and runtime regression coverage; awaiting two-player verification. No Workshop deployment.

## 2026-07-13 - `weapon_tweaker` Moonfire HUD loadout lifecycle

Repo-aggregate entry for Weapon Tweaker v0.12.228-dev / issue #585. Vanilla's energy HUD draws from the career energy extension rather than the equipped item, so drained cross-character energy could remain visible forever after Moonfire was replaced. WT now resets that nonnative stale value once when `slot_ranged` is no longer energy-based, while preserving equipped/stowed Moonfire recharge and native Kerillian handling. No Workshop deployment.

## 2026-07-13 - `weapon_tweaker` Moonfire stowed recharge parity

Repo-aggregate entry for Weapon Tweaker v0.12.227-dev / issue #584. Cross-character Moonfire now detects the energy weapon from the equipped ranged slot, matching native Kerillian recharge while melee is active. Recharge remains owner-authoritative, uses the native 1.5/s rate only for careers with no native rate, and has one shared wielded/stowed application path. No Workshop deployment.

## 2026-07-13 - WT/CWV native Dual Axes ownership boundary

Repo-aggregate entry for issue #582: Weapon Tweaker v0.12.226-dev removes Bardin's native `dr_dual_wield_axes` from Kruber and Saltzpyre availability, while Character Weapon Variants v0.1.391-dev preserves and regression-checks `cwv_es_dual_axes` and `cwv_wh_dual_axes`. WT also strips stale `can_wield` mutations and rejects invalid cached loadouts before falling back to vanilla. No Workshop deployment.

## 2026-07-13 - `weapon_tweaker` Saltzpyre Moonfire presentation

Repo-aggregate entry for Weapon Tweaker v0.12.225-dev / issue #580. Moonfire Bow on WHC, Bounty Hunter, and Zealot now reuses the established Saltzpyre crossbow third-person model, bolt, attachment, preview, husk, and event-remap pipeline. Kerillian and all first-person Moonfire behavior remain untouched. Added bounded diagnostics and runtime regression coverage; awaiting solo and coop verification. Workshop not uploaded.

## 2026-07-13 - `character_weapon_variants` dual-axes cosmetic parity

Repo-aggregate entry for CWV v0.1.390-dev / issue #579. Dual Axes now derives
its illusion set from the canonical Saltzpyre one-handed-axe combination pool,
including DLC-added tiers and the separate default skin. Generated clones keep
the source DLC requirement, both hand meshes, the dual-axes display rig, and
network registration. A runtime regression compares the source and generated
key sets. Full details are in `character_weapon_variants/CHANGELOG.md`.

## 2026-07-13 - `character_weapon_variants` skin reverse-index refresh

Repo-aggregate entry for CWV v0.1.388-dev / issue #567. After deferred variant
owners are registered, CWV now invalidates vanilla's lazy skin-to-weapon cache so
persisted custom skins are indexed from their valid owner combination pools.
Adds `[cwv:567]` diagnostics and regression coverage for the three reported
Sword and Mace, Dual Maces, and Axe and Shield skins. Full details are in
`character_weapon_variants/CHANGELOG.md`.

## 2026-07-13 - `crafting_in_modded_dev` auto-equips new weapons

Repo-aggregate entry for `cim_dev` v0.8.64-dev / issue #562. Added a default-on
option that equips the exact backend ID produced by a successful weapon craft in
the primary or secondary slot selected for crafting. The loadout write targets
the live selected loadout index and is paired with live-avatar equipment
recreation; disabling the option keeps the previous inventory-only behavior.
Accessories are unaffected. Full details and regression coverage are in
`crafting_in_modded_dev/CHANGELOG.md`.
## 2026-05-23 — `weapon_tweaker` per-career weapon toggle reorder

Repo-aggregate entry for `weapon_tweaker` v0.12.71-dev (full details in
`weapon_tweaker/CHANGELOG.md`).

Reordered every career's `unlock_<career>_<weapon>` widget tree (and the
matching localization keys) to a single deterministic rule: natives first
alphabetical → cross-character ports grouped by donor character
(`es → dr → we → wh → bw`) alphabetical within each donor → `*_deus_01`
at end of native and donor clusters. 334 data moves + 406 loc moves;
no setting_id additions/removals, no `default_value` flips, no
per-career inclusion changes.

Ordering rule documented in `_audit_wt_weapon_order.md` §4-5 (repo root).
Peregrinaje was evaluated as the canonical reference (per the user brief)
but rejected — it has no per-character ordering structure to mirror;
audit §1-2 has the full reasoning. The alphabetical-then-donor rule
satisfies the underlying intent (consistent ordering) and is mechanical
to verify and extend.

## 2026-05-21 — Stale-doc banner pass + deploy_*.ps1 reference sweep

Two follow-on cleanups against the doc set after the Section A archive pass.

### Stale-doc banners (5 files)

Added "Stale snapshot — superseded by AUDIT_2026_05_21.md" banner blocks at the top of:

- `REPO_REVIEW.md` (2026-05-01 snapshot)
- `REVIEW_AGGREGATE.md` (2026-05-01 snapshot)
- `CONSISTENCY_REVIEW.md` (2026-05-02 snapshot)
- `WORK_ITEMS.md` (self-stamped 2026-04-27)
- `CROSS_CAREER_PACKAGE_FIX.md` (theory later disproven — added stronger banner line noting current cross-career package handling lives in `AUDIT_2026_05_21.md`)

Original content preserved under the banner; these files retain historical value (file:line citations, pre-VMB pipeline references, diagnostic notes).

### deploy_*.ps1 reference sweep (4 files)

The four shims (`deploy_all.ps1`, `deploy_ct.ps1`, `deploy_gt.ps1`, `deploy_wt.ps1`) were archived to `_archive/legacy_deploy_scripts/` earlier today. Live docs that prescribed running them as the canonical deploy step were updated to point at `VMBLauncher.exe deploy <mod>` (or `all <mod>` for full build+deploy+upload):

- `DEVELOPMENT.md` — directory diagram, Quick iteration loop, Build / Deploy sections, "deploy_all.ps1: variables null inside foreach loop" known-error entry, cosmetics_tweaker Build & Deploy
- `event_tweaker/DEVELOPMENT.md` — "Adding a new mutator" step 4 + Build & deploy section
- `dynamic_cosmetic_portraits/CLAUDE.md` — Build & deploy section
- `dynamic_cosmetic_portraits/DEVELOPMENT.md` — step 8 of the portrait-authoring workflow

Historical references in audit reports (`AUDIT_section_*.md`), memory-doc snapshots (`REPO_REVIEW.md`, `REVIEW_AGGREGATE.md`), `_archive/` READMEs, and per-mod CHANGELOG entries were left alone — they document past state and are correct as historical record.

## 2026-05-21 — Repo archive pass

Section A audit recommendations applied. Created `_archive/` for cold storage
of pre-VMB and otherwise-deprecated content. Nothing on the active build path
moved. See `_archive/README.md` for full per-folder inventory.

### Moved

- `old-backup/` (entire folder, self-flagged for deletion in its own README) → `_archive/old-backup/`. Contents include 7 pre-VMB SDK scripts, 4 loose hex-named bundle files, `tweaker_manual_install.zip`, `lighting_tweaker_20260516/` pre-rename snapshot of `verminious_dreams_lighting`, and the dir's `ANTIGRAVITY.md` / `README.md`.
- `bundleHistory.dat`, `launcher_screenshot.png`, `readme.txt` (root-level stale) → `_archive/root-misc/`.
- `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker_localization.lua.v0726.bak` → `_archive/backups/`.
- `verminious_dreams_lighting/item_preview.png.bak` → `_archive/backups/verminious_dreams_lighting_item_preview.png.bak` (renamed for source-mod traceability).
- `deploy_all.ps1`, `deploy_ct.ps1`, `deploy_gt.ps1`, `deploy_wt.ps1` → `_archive/legacy_deploy_scripts/`. All four moved as one unit because the three shims call `deploy_all.ps1`. Use `VMBLauncher.exe deploy <mod>` directly going forward.

### Kept at root

- `settings.ini` — flagged for review but still referenced in CLAUDE.md's mod-file-structure section; Section A audit marked it **KEEP** because VMB tooling may still read it from cwd. Re-audit after one release cycle.
- All 5 `upload_*.ps1` wrappers — each adds a visibility-regression guard on top of `VMBLauncher.exe upload` (Section A: "highest-value guard of all" for `upload_wt.ps1`).
- `send_keys.ps1` — referenced by `reference_remote_vt2.md`; active dev tool.

### Reference updates

- `CLAUDE.md` — Build Commands section updated to point at `VMBLauncher.exe deploy <mod>` and note the archived shims.

### Flagged but not moved (require further sign-off)

- Legacy `tweaker/` mod tree.
- `cosmetics_tweaker/`'s ~13 ephemeral diagnosis `.md` files (active investigation).
- `_tools/extract_all_bundles.ps1` (active reusable tool).
- `cosmetics_tweaker/.build/`, `cosmetics_tweaker/upload/`, `cosmetics_tweaker/pcb-log.log`, `chaos_wastes_tweaker/boon_loc_dump.txt`, and the three `.lua.processed` SDK artifacts (gitignored — disk clutter only; Section A recommends DELETE, but the user's archival list did not authorize this pass to touch them).

## [2026-05-06] dynamic_cosmetic_portraits v0.1.0 — split from cosmetics_tweaker
### Added
- New standalone mod (Workshop ID `3721036701`, private) wrapping the
  hat/outfit-aware HUD & hero-select character portrait system that
  previously shipped inside `cosmetics_tweaker`.
- 10 portrait sets at split (8 Kruber Mercenary hats + Felix outfit + VT1
  Champion of Ubersreik outfit). v0.1.1 added Plumed Horseshoe (11 total).
- `CHARACTER_COSMETIC_CATALOG.md` moved into the new mod (it's exclusively a
  portrait-authoring reference). The catalog still sources from
  `cosmetics_tweaker/_cos_probe.txt`.
- Per-mod docs: `dynamic_cosmetic_portraits/{CHANGELOG,DEVELOPMENT,TODO}.md`.

### Changed (cosmetics_tweaker → v0.8.0)
- Removed the dynamic-portrait subsystem (~570 lines of Lua, the
  `dynamic_portraits` setting, the `custom_gui_textures` block, 60 package
  declarations, and 90 asset files). The `NewsFeedUI:draw` hot-reload
  safety hook stayed — it protects illusion / LA bridge atlases, not
  portrait materials. See `cosmetics_tweaker/CHANGELOG.md` v0.8.0 entry
  for the per-file delta.

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
- `/dump` command — dumps all equipped item data (key, item_type, template, rarity, units, can_wield) to console log.
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
