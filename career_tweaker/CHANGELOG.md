# Career Tweaker Changelog

## 0.2.3-dev (2026-04-29)

### Fixed: Dropdown options showing <<>> brackets

VMF dropdown `text` fields must be literal display strings, not
localization keys. Changed all talent swap dropdown options from
localization key references (e.g. `"cname_dr_ironbreaker"`) to inline
strings (e.g. `"Ironbreaker (Bardin)"`). Removed unused localization
entries for dropdown options.

### Removed: Melee-in-ranged-slot feature

Removed the "Allow Melee in Ranged Slot" checkbox and all associated
logic (`apply_slot_settings`, `_original_slot_2_allowed`). This feature
doesn't belong in career_tweaker.

### Removed: Career action injection checkbox

Removed the "Inject Career Actions on Unlocked Weapons" checkbox. This
setting was always handled by weapon_tweaker; the checkbox here was
non-functional.

## 0.2.2 (2026-04-29)

### Fixed: Balance module not found — missing from resource package

`career_tweaker_balance.lua` was not registered in `career_tweaker.package`,
so the Stingray compiler never bundled it. `mod:dofile` failed with
`Resource not found`, leaving `balance` as nil. Every subsequent
`on_game_state_changed` call crashed with `attempt to index upvalue
'balance' (a nil value)`, spamming errors on every state transition.

Fix: Added the file to `resource_packages/career_tweaker.package`.

### Fixed: Cascading crash when balance module fails to load

If `mod:dofile` for the balance module fails for any reason, the mod now
logs the error and substitutes a no-op stub so lifecycle hooks
(`on_game_state_changed`, `on_setting_changed`, `on_disabled`) continue
working. Previously a single load failure cascaded into errors on every
game state transition.

## 0.2.1 (2026-04-29)

### Fixed: Empty VMF groups crash mod options init

VMF requires groups to have at least 1 sub_widget. Empty placeholder groups
for Bardin, Kruber, Kerillian, and Sienna caused `new_mod` to fail options
initialization with: `[widget "balance_kruber_group" (group)]: must have at
least 1 sub_widget`. Removed empty character sub-groups; balance checkboxes
are now flat under the "Talent Balance Changes" group until they have enough
entries to warrant sub-grouping.

## 0.2.0 (2026-04-29)

### Added: Talent balance modification framework

New data-driven system for toggling per-talent balance changes via VMF
checkboxes. Supports both simple BuffTemplates field patches and hook-based
modifications. All changes default to off.

Initial balance mods:
- **Zealot/Merc: Allow random crits with guaranteed crit talent** — The
  "crit every 5 hits" talent normally disables all natural random crits via
  the `no_random_crits` talent perk. This toggle suppresses that perk so
  natural crits can proc between guaranteed ones. (Hook on
  `TalentExtension.has_talent_perk`)
- **WHC: Parry crit talent doubles parry window** — Extends the parry
  timing window from 0.5s to 1.0s. (Hook on `ActionBlock` and
  `ActionMeleeStart` `client_owner_start_action`)

### Fixed: Talent picker UI not refreshing after swap

Hooks `HeroWindowTalents.on_enter`/`on_exit` to track the live window
instance. After `apply_talent_swaps()`, calls `_update_talent_sync()` on
the tracked instance to force the UI to re-read swapped talent trees.

### Fixed: Weapon-ability crash on cross-character swap

Replaced `pcall`-based crash recovery with a deterministic skip list.
Careers with weapon-based abilities (e.g. Grail Knight) skip the ability
swap when the target is a different character. Talent tree swap still
applies. Logs an info message instead of silently catching an exception.

### Changed: Deleted incorrect entry point

Removed `career_tweaker.mod` — the correct entry point is `crt.mod`
(registers as `"crt"` matching all `get_mod("crt")` calls). Having both
caused double-registration errors.

## 0.1.1 (2026-04-29)

### Added: Workshop upload

First Workshop upload as private item (ID 3716286199). Fixed `item.cfg`
to use relative paths and private visibility. Added Workshop ID to
`deploy_all.ps1` and `CLAUDE.md`.

## 0.1.0-dev (2026-04-24)

### Added: Version logging

Mod now logs `Career Tweaker v<version> loaded` on init so the running version can be verified in the console log.
