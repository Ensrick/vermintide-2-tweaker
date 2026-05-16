# Career Tweaker Changelog

## 0.2.16-dev (2026-05-15)

### Added: Three "double the 5% talent" reworks

Three new toggles, all following the same pattern: a career-specific buff template's percent doubled from 5% to 10%, with the in-game talent tooltip rewritten in-place so the displayed value matches.

| Toggle | Career | Talent | Buff template / field | 0.05 → 0.10 |
|--------|--------|--------|-----------------------|--------------|
| `rework_wh_zealot_power_5_to_10`              | Zealot (Victor)         | row-1 +5% Power         | `victor_zealot_power.buffs[1].multiplier`            | flat +Power stat_buff |
| `rework_dr_ranger_attack_speed_5_to_10`       | Ranger Vet (Bardin)     | row-2 +5% Attack Speed  | `bardin_ranger_attack_speed.buffs[1].multiplier`     | flat +Attack Speed stat_buff |
| `rework_we_maidenguard_crit_chance_5_to_10`   | Handmaiden (Kerillian)  | row-2 +5% Crit Chance   | `kerillian_maidenguard_crit_chance.buffs[1].bonus`   | flat +crit_chance stat_buff (uses `bonus` field, not `multiplier`) |

Menu placement: each lands under `Talent Reworks > Rework: <Character> > Rework: <Career>`. The Zealot toggle joins the existing Smite rework under `Saltzpyre > Zealot`; the Ranger Veteran and Handmaiden toggles create new `Rework: Bardin` and `Rework: Kerillian` top-level character subgroups.

#### Implementation

All three reuse a new `_build_stat_buff_rework(talent_name, buff_field, new_value)` factory in `career_tweaker_balance.lua`. The factory returns a `{ patches, custom_apply, custom_restore }` triple that:

1. Patches `BuffTemplates[talent_name].buffs[1][buff_field]` (runtime effect — applied/restored by the existing patch engine).
2. Walks `TalentIDLookup[talent_name]` to find the talent entry and overwrites `Talents[hero_name][talent_id].description_values[1].value` (tooltip text).

The factory assumes the buff template name matches the talent's `name` field and that `description_values[1]` is the relevant tooltip slot — verified for all three. Career-specific templates only, so patches don't bleed into other careers' equivalents (every career has its own `<career>_attack_speed` / `<career>_power` / `<career>_crit_chance` variant rather than a shared template — the shared `power_level_unbalance` template used by the level-15 row is NOT what these reworks touch).

#### Pyromancer skipped

Original request included Pyromancer's "5% attack speed" talent. Audit confirms Pyromancer (sienna_adept) has no flat 5% Attack Speed talent on any of her 6 rows — her only AS talent is `sienna_adept_attack_speed_on_enemies_hit_buff` at level 25 (15% AS for 5s after hitting 4+ enemies in one swing, conditional), and her flat passives are all overcharge-related. Toggle deferred pending clarification.

#### Field-name caveat

The `bonus` vs `multiplier` distinction is load-bearing. The `critical_strike_chance` stat_buff consumes `bonus` additively at the `buff_extension` level (`buff_extension.lua:196`), while `power_level` and `attack_speed` stat_buffs consume `multiplier`. Picking the wrong field silently no-ops the runtime effect (the tooltip still updates because that's driven by `description_values`, not the buff field). Reflected this in the factory call sites.

## 0.2.15-dev (2026-05-15)

### Changed: Minimum THP-on-kill floor 1 → 1.5

Audit of `BreedTweaks.bloodlust_health` (breed_tweaks.lua:594) shows the actual vanilla minimum for combat breeds is `skaven_horde = 1` (slaves). All other hordes are already at 1.5 (`beastmen_horde` = ungor, `chaos_horde` = fanatic); roamers are 2–3; everything above is much higher. The pre-existing floor of 1 was therefore a no-op — slaves already met it, and the only sub-1 entries (`breed_chaos_greed_pinata` and `breed_training_dummy`, both 0) are props you don't kill for THP.

Bumped `_MIN_THP_ON_KILL` to 1.5 so slaves lift to match the other hordes; nothing else changes (the clamp only fires when `v < floor`, and every other breed's vanilla value already exceeds 1.5). The CHANGELOG/localization claim that "slaves/hordes sit at 0..1" was incorrect — slaves are exactly 1, hordes are 1.5 — so the toggle description is rewritten to reflect the actual values.

## 0.2.14-dev (2026-05-15)

### Fixed: Talent-swap dropdown options wrapped in `<<...>>` brackets

Every talent-swap dropdown (`talent_swap_<career>`) listed its options as `{ text = "None (default)", value = "none" }` etc. — raw English strings. VMF resolves the `text` field as a localization key via `mod:localize(key)` and, when the key isn't registered, falls back to wrapping it in `<<key>>` markers so authors notice the missing entry. The fallback was firing on every option in every talent-swap widget, so the dropdowns rendered as `<<None (default)>>`, `<<Ironbreaker (Bardin)>>`, etc.

Replaced each `text = "<display string>"` with `text = "talent_swap_option_<value>"` and registered the matching `talent_swap_option_*` entries in `career_tweaker_localization.lua` (21 keys: one for `none` + one per career). Display text is unchanged; the brackets are gone.

## 0.2.13-dev (2026-05-15)

### Added: Bounty Hunter Double-Shotted rework — 80% refund on headshot

New checkbox under `Talent Reworks > Rework: Saltzpyre > Rework: Bounty Hunter > Rework: Double-Shotted — 80% refund on headshot`.

Vanilla Double-Shotted (`victor_bountyhunter_activated_ability_railgun`): when the Locked And Loaded shot connects as a headshot on its first target, `victor_bounty_hunter_reduce_activated_ability_cooldown_railgun` (buff_templates.lua:3615) adds the delayed buff `victor_bountyhunter_activated_ability_railgun_delayed_add`, which on removal (0.25s later) calls `career_extension:reduce_activated_ability_cooldown_percent(buff.multiplier)`. The template `multiplier` is 0.6, so the refund is 60%. With this rework on, the value is patched to 0.8 — 80% refund.

The visible "60%" in the inventory talent tooltip is read from `Talents.victor[talent_id].description_values[1].value`, set at game-init from `buff_tweak_data.victor_bountyhunter_activated_ability_railgun.multiplier`. By the time VMF mods run, that value is already frozen on the talent entry, so the rework's `custom_apply` walks `TalentIDLookup["victor_bountyhunter_activated_ability_railgun"]` to find the talent table and rewrites `description_values[1].value` in place; `custom_restore` puts it back. The tooltip doesn't refresh live — players need to close and re-enter the talent panel after toggling (same caveat as Hellborg's Tutelage).

The patches engine already supports `{ buff = ..., field = ..., value = ... }` entries alongside custom_apply/custom_restore on the same rework, so no engine changes were needed.

## 0.2.12-dev (2026-05-15)

### Added: "Talent Reworks" menu structure (Talent Reworks > General | Rework: \<Character\> > Rework: \<Career\> > Rework: \<Talent\>)

Replaced the flat "Talent Balance Changes" group with a nested hierarchy so future reworks slot in by character/career instead of accumulating in a wall of checkboxes. Every submenu and toggle is prefixed `Rework: ` so the player always knows which top-level menu they're in:

- **General** — cross-career toggles (Stagger THP, Minimum THP-on-kill)
- **Rework: Kruber** > **Rework: Mercenary** > Hellborg's Tutelage (new — see below)
- **Rework: Saltzpyre** > **Rework: Zealot** > Smite (split from old combined Zealot/Merc toggle), **Rework: Witch Hunter Captain** > Extended parry window

Setting IDs renamed to match the new naming scheme (mod is pre-release; no user-state migration needed):

| Old | New |
|-----|-----|
| `balance_zealot_merc_allow_random_crits` | (split) `rework_wh_zealot_smite_random_crits` + new `rework_es_mercenary_hellborgs_tutelage` |
| `balance_whc_parry_extended_window`      | `rework_wh_captain_parry_window` |
| `balance_stagger_thp_rework`             | `rework_general_stagger_thp` |
| `balance_thp_kill_minimum`               | `rework_general_thp_kill_minimum` |

`on_setting_changed`'s pattern updated from `^balance_` to `^rework_` to match.

### Added: Hellborg's Tutelage rework (Mercenary)

New checkbox under `Talent Reworks > Rework: Kruber > Rework: Mercenary > Rework: Hellborg's Tutelage`.

Vanilla Hellborg's Tutelage (the `markus_mercenary_crit_count` talent) grants a guaranteed crit every 5 melee hits but attaches the perk `{ "no_random_crits" }`, which `ActionUtils.is_critical_strike` reads to force the random-crit roll to false. The rework keeps the guaranteed-every-5 cadence intact but flips the trade-off: random crits are re-enabled, and in exchange the random crit chance is reduced by a flat 10% (0.10) for the duration of the talent.

Implementation is hook-based and idempotent (each hook reads `mod:get(...)` on every call, so toggling takes effect on the next attack):

1. **`TalentExtension.has_talent_perk`** — `self._career_name == "es_mercenary"` branch returns `false` for `"no_random_crits"` when the toggle is on, so `is_critical_strike` falls through to the normal `get_critical_strike_chance` path. The same hook also handles the Zealot Smite rework (`wh_zealot` branch), so the two toggles don't bleed across careers.
2. **`ActionUtils.get_critical_strike_chance`** — when the player is on Mercenary, has Hellborg's Tutelage selected (`talent_ext:has_talent("markus_mercenary_crit_count")`), and the toggle is on, subtracts 0.10 from the post-buff chance with a floor of 0. Mercenary's base 5% crit chance zeros out at the floor but crit-chance stacking (weapon traits, properties, bench buffs, talents like Bloodlust) still pushes it positive. Hooked table-form (`ActionUtils` is a plain global, not a class) with a load-order guard.
3. **`_G.Localize`** — overrides the `markus_mercenary_crit_count_desc` key with `"Critical Strike every %d melee hits. Random Critical Strike chance reduced by 10%%."` while the toggle is on, so the in-game talent description in the inventory talent panel matches the new behavior. `%%` because the post-Localize string is re-fed through `string.format` with `description_values` per `feedback_vt2_localize_string_format_pipeline.md`.

The Zealot Smite half of the old combined `balance_zealot_merc_allow_random_crits` toggle is preserved as `rework_wh_zealot_smite_random_crits` (under `Rework: Saltzpyre > Rework: Zealot`); its semantics are unchanged — random crits re-enabled with no chance penalty. The Mercenary half is now the new Hellborg's Tutelage rework instead.

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
