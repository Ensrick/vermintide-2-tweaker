# Career Tweaker Changelog

## 0.2.11-dev (2026-05-12)

### Changed: Stagger THP Rework dialed back from +100% to +50%

In-game testing showed the v0.2.9 `base_value` 1 → 2 (+100%) was too strong. Dropped to 1.5 (+50%): light/medium/heavy stagger now heal 0.375 / 1.5 / 3 THP per target instead of 0.5 / 2 / 4. The `max_targets = 3` cap stays. Perfect heavy-stagger swing across 3 enemies now tops out at 9 THP (was 12); typical medium-stagger swing across 3 caps at 4.5 THP (was 6).

### Changed: "Normalize THP-on-kill" → "Minimum THP-on-kill"

The v0.2.8 power-law normalization also overshot in-game. Replaced the toggle entirely with a simpler floor: when on, every breed's `bloodlust_health` gets clamped to at least `_MIN_THP_ON_KILL = 1`. Trash kills (vanilla 0..1) always pay out 1 THP; elites/specials/monsters keep their vanilla values untouched. Setting key renamed `balance_thp_breed_normalize` → `balance_thp_kill_minimum` (mod is private — no user-state migration needed). Display name now "All careers: Minimum THP-on-kill".

The same snapshot/restore mechanics carry over (record originals into `saved.breed_thp_originals`, walk on disable). Only breeds whose vanilla value is below the floor get touched, so restore only walks the changed set.

## 0.2.9-dev (2026-05-09)

### Changed: "Double THP on stagger" → "Stagger THP Rework"

Renamed the 0.2.7 stagger toggle and tightened it. The new behavior keeps the doubled `base_value` (1 → 2) but also drops `max_targets` from 5 → 3 — both fields patched on `BuffTemplates.thp_tank.buffs[1]`. Caps update from "≤20 THP per perfect heavy swing" to "≤12 THP per perfect heavy swing"; a typical medium-stagger swing now tops out at 6 THP instead of 10. Setting key renamed `balance_thp_on_stagger_doubled` → `balance_stagger_thp_rework` (mod is private, recently deployed — no user-state migration needed). Display name now "All careers: Stagger THP Rework".

The patches engine already supports multiple `{ field, value }` entries per setting (one apply/restore loop iterates `def.patches`), so the second patch slots in without engine changes.

## 0.2.8-dev (2026-05-08)

### Added: "Normalize THP-on-kill across enemy types" balance toggle

New checkbox under "Talent Balance Changes": `balance_thp_breed_normalize`. Compresses every breed's `bloodlust_health` (the per-enemy THP-on-kill amount used by Heal-on-Kill weapon traits, the Bloodlust CW trait, the Warrior Priest aftershock heal, and any other talent/buff that reads `breed.bloodlust_health`) toward a fixed pivot using a power law:

> `new = pivot × (vanilla / pivot) ^ n`, with `pivot = 10` and `n = 0.5`.

Vanilla THP-on-kill spans 1 (slave) → 50 (monster), a 50× spread. After normalization the spread collapses to roughly 3 → 22:

| Vanilla | Normalized |
|---------|------------|
| 1 (slave)            | ~3.2  |
| 1.5 (horde)          | ~3.9  |
| 2 (skaven roamer)    | ~4.5  |
| 3 (gor / chaos roamer) | ~5.5 |
| 8 (skaven elite/special) | ~8.9 |
| 10 (chaos special)   | 10    |
| 15 (chaos elite)     | ~12.2 |
| 30 (chaos warrior)   | ~17.3 |
| 35 (chaos bulwark)   | ~18.7 |
| 50 (monster)         | ~22.4 |

Implementation lives in `career_tweaker_balance.lua` as a `custom_apply` / `custom_restore` pair on `BALANCE_MODS.balance_thp_breed_normalize`. On apply, iterates `Breeds`, snapshots each breed's `bloodlust_health`, and overwrites with the transform; on disable / re-toggle the snapshot is written back. Each breed file copies its number out of `BreedTweaks.bloodlust_health` at game-load time (e.g. `breed_chaos_warrior.lua:134`), so we have to mutate every breed table directly — patching the central `BreedTweaks.bloodlust_health` table after load does nothing.

Pivot and exponent are intentionally fixed (no sliders) per the user's "just a reasonable tuning that I'll find via testing" preference. Tuning lives in `custom_apply` body.

## 0.2.7-dev (2026-05-08)

### Added: "Double THP on stagger" balance toggle

New checkbox under "Talent Balance Changes": `balance_thp_on_stagger_doubled`. Patches `BuffTemplates.thp_tank.buffs[1].base_value` from `1` → `2`, doubling the THP gained per stagger across all Heal-on-Stagger talents (every career that has one). Light / medium / heavy stagger now heal `0.5 / 2 / 4` THP per target instead of `0.25 / 1 / 2`. `max_targets` is unchanged at 5, so a perfect heavy-stagger swing across 5 enemies caps at 20 THP and a typical medium-stagger swing caps at 10 THP. The push branch (`is_push`) goes through the same `base_value * push_modifier` path so it scales with the toggle (push_modifier = 0.5, max push heal now 2 THP at heavy stagger).

This is the first balance entry that actually uses the `patches` field of `BALANCE_MODS` — the prior two (`balance_zealot_merc_allow_random_crits`, `balance_whc_parry_extended_window`) are hook-based with empty `patches{}`. Removed the stale "currently dead code" REVIEW comment now that the engine has a live consumer.

The Heal-on-Stagger nerf was part of [Patch 3.1 / "Big Balance Beta Update #1"](https://forums.fatsharkgames.com/t/pc-vermintide-2-the-big-balance-beta-update-1/28267) ("Reduced the temp health gained from the stagger talents… should now be more in line with the other temp health talents"). Fatshark didn't publish exact pre-nerf numbers; doubling chosen by user feel — pre-nerf was widely felt as ~2x current, which was slightly OP.

## 0.2.4-dev (2026-05-01)

### Changed: Migrated to VMB build pipeline

Moved from the raw Stingray SDK build (`crt.mod`, `settings.ini`, `lua_preprocessor_defines.config`, `.build/OUT/`) to VMB (`career_tweaker.mod`, `itemV2.cfg`, `bundleV2/`). Workshop ID `3716286199` and internal mod ID `"crt"` preserved — existing user settings are unaffected. `visibility` remains `"private"`.

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
