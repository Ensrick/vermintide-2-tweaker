# Career Tweaker Changelog

## 0.3.9-dev (2026-05-23) — Convert 1 NetworkLookup lookup to rawget (latent strict-__index crash fix)

### Why
`NetworkLookup.*` subtables install a strict `__index = error()` metatable at boot. Plain `NetworkLookup.foo[key]` on a missing key throws — see memory `reference_vt2_strict_lookup_rawget.md`. The lint pass on 2026-05-23 flagged the talent-buff registration site as latent: the BR-stub registration path queries `NetworkLookup.buff_templates[name]` to skip already-registered names, but the strict metatable means an unregistered name would crash *before* the registration write that would fix it.

### Changed
- `career_tweaker_big_rebalance.lua` (`_register_talent_buff_template_if_missing`) — converted `not NetworkLookup.buff_templates[name]` to `not rawget(NetworkLookup.buff_templates, name)` so the "is this name new?" check returns false (write the entry) instead of crashing on the strict lookup.

### Verification
1. `tools/mod-lint/lint-mod.ps1` — passes.
2. `tools/lint/regression-lint.ps1 -Quiet` — site no longer appears in `strict-table-lookup` findings.

## 0.3.8-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `career_tweaker.lua` — renamed `regression_test` → `crt_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/crt_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.2.22-dev (2026-05-19)

### Added: Ranger Veteran +25 base HP (toggle)

New rework under **Rework: Bardin > Rework: Ranger Veteran**:
`rework_dr_ranger_base_hp_plus_25` — adds 25 to Ranger Veteran's base max HP (vanilla 100 → 125, matching Witch Hunter Captain).

Implementation: patches `CareerSettings.dr_ranger.attributes.max_hp` in `custom_apply` and restores the original in `custom_restore`. `PlayerUnitHealthExtension._get_base_max_health` reads `SPProfiles[profile].careers[index].attributes.max_hp`, and `SPProfiles.dwarf_ranger.careers` holds direct references to `CareerSettings.dr_*` (sp_profiles.lua:163), so the single field patch is what every health-calc path consumes. Takes effect on next mission load / hero respawn (vanilla recalculates max at extension init); does not retroactively bump an already-spawned Ranger's max in the current mission. Stacks multiplicatively with `max_health` / `max_health_alive` buffs.

## 0.2.21-dev (2026-05-19)

### Added: Zealot ability converts green → temporary HP (toggle)

New rework under **Rework: Saltzpyre > Rework: Zealot**:
`rework_wh_zealot_ability_green_to_thp` — when on, every Zealot Holy Fervour activation moves all current permanent (green) HP into temporary (white) HP. Synergizes with Zealot's missing-health damage passive: a full-HP activation drops him to 0 permanent HP, maxing the passive's damage multiplier while the THP buffer keeps him alive (and decays normally). Existing THP is preserved; conversion fires once per activation.

Implementation: `mod:hook_safe("CareerAbilityWHZealot", "_run_ability", ...)` reads `current_permanent_health()` and calls `health_extension:convert_to_temp(permanent)`. `convert_to_temp` self-routes — server mutates GameSession fields directly; client fires `rpc_request_convert_temp` to the server. Server-side clamps via `math.min(current_health, amount)`, so the read-back amount is overflow-safe. No `BuffTemplates` mutation and no `NetworkLookup.buff_templates` registration, so the toggle is host-controlled with no peer drift (per `feedback_vt2_gated_registration_diverges.md`).

## 0.2.20-dev (2026-05-18)

### Fixed: HARD DLC paywall bypass via talent swaps

`apply_talent_swaps` iterated all 20 careers — including the five DLC careers (Grail Knight, Warrior Priest, Necromancer, Outcast Engineer, Sister of the Thorn) — and copied their talent trees + `activated_ability` + `passive_ability` onto the player's selected career without consulting DLC ownership. The dropdown UI listed every career unconditionally, so a player who didn't own a DLC could pick its career as a swap source and the talents/ability took effect **at runtime**: Grail Knight ult, Warrior Priest aftershock heal, Necromancer commander, Outcast Engineer pressure gauge, Sister of the Thorn entanglement. That is a paid-content runtime bypass, not just a UI peek — fixed.

#### The gate

New helper `_career_requires_unowned_dlc(career_name)` mirrors `_skin_requires_unowned_dlc` from `cosmetics_tweaker.lua:38`, but reads `CareerSettings[career_name].required_dlc` instead of `ItemMasterList[skin_key].required_dlc`. Base careers have no `required_dlc` field so they short-circuit to false; DLC careers carry the field via their per-DLC `career_settings_<dlc>.lua` registration in the VT2 source.

DLC IDs settled (cited from the decompiled `c:\Users\danjo\source\repos\Vermintide-2-Source-Code` per-DLC `career_settings_*.lua` files):

| Career | `required_dlc` | Source file |
|---|---|---|
| `dr_engineer` (Outcast Engineer) | `"cog"` | `scripts/settings/dlcs/cog/career_settings_cog.lua:32` |
| `es_questingknight` (Grail Knight) | `"lake"` | `scripts/settings/dlcs/lake/career_settings_lake.lua:21` |
| `wh_priest` (Warrior Priest) | `"bless"` | `scripts/settings/dlcs/bless/career_settings_bless.lua:22` |
| `bw_necromancer` (Necromancer) | `"shovel"` | `scripts/settings/dlcs/shovel/career_settings_shovel.lua:21` |
| `we_thornsister` (Sister of the Thorn) | `"woods"` | `scripts/settings/dlcs/woods/career_settings_woods.lua:21` |

(The task brief listed only four DLC careers; the data-driven gate auto-covers `we_thornsister` too — base careers in `scripts/settings/profiles/career_settings.lua` have zero `required_dlc` entries, so no false positives.)

#### Apply-time, both sides

The gate runs at swap-apply time inside `apply_talent_swaps`, not at dropdown-build time:

1. **Source check (load-bearing)** — if `_career_requires_unowned_dlc(src_name)` is true we `goto continue` and never mutate the destination career's slot. This is what closes the bypass.
2. **Target check (defensive)** — same skip if `_career_requires_unowned_dlc(career_name)` is true. A non-owner can't equip the DLC career anyway, but if they hand-edit settings we still refuse to mutate that career's `TalentTrees` slot / `activated_ability` / `passive_ability`.

Both skips log an info-level line; nothing visible to the player.

#### Why the UI isn't touched

VMF dropdown options are part of the widget's saved schema. Dropping options at registration time would invalidate any user's existing setting that referenced a now-removed option (the saved value falls through to default; if they re-acquire the DLC the option doesn't come back without a restart). The apply-time gate is data-driven, so it works whether the player owns the DLC at boot, mid-session, or never — and saved settings stay portable across machines with different DLC ownership.

#### Balance reworks unchanged

`career_tweaker_balance.lua` was re-audited: `BALANCE_MODS` patches `BuffTemplates` entries for `victor_zealot_power`, `bardin_ranger_attack_speed`, `kerillian_maidenguard_crit_chance`, `victor_bountyhunter_activated_ability_railgun_delayed_add`, `markus_mercenary_crit_count`, `wh_captain` parry actions, `thp_tank`, and `Breeds[*].bloodlust_health`. Every target is base-career or cross-career — no DLC-career-specific templates. The audit conclusion stands: reworks are global table patches and harmless to non-owners (they can't equip the career, so the patched buff template never attaches). No changes needed in this file.

## 0.2.19-dev (2026-05-17)

### Added: Per-character experience level override

Five numeric widgets under a new **Character Experience Level** group — one per hero (Bardin, Kruber, Kerillian, Saltzpyre, Sienna). `0` = use real XP (default), `1`–`35` = force that character to report exactly that level everywhere.

Single chokepoint: hook `ExperienceSettings.get_experience(hero_name)` and return `ExperienceSettings.get_total_experience_required_for_level(override)` when the user has set a non-zero value for that hero. Every downstream consumer — the inventory level badge, character-select tile, mission-spawn `level` network field, network_server's hero-level check, scoreboard, even chest reward level — reads through `get_experience`, so one hook covers all of them and the computed `level` / `progress` / `extra_levels` stay internally consistent.

Per character (not per career): VT2 stores XP keyed on `hero_attributes["dwarf_ranger" | "empire_soldier" | "wood_elf" | "witch_hunter" | "bright_wizard"]`, so all four careers under one hero share the same XP and therefore the same level. Use case: testing host/client features that gate on level (e.g. Athanor unlock at 11, weave forge access, etc.) without grinding XP on a fresh modded-realm character.

Modded realm only by definition — Workshop mods can only execute under `script_data["eac-untrusted"]`. The hook never writes to the backend.

## 0.2.18-dev (2026-05-16)

### Fixed: Talent-swap dropdown options rendering as `<<<<<...None (default)>>>>>` (nested brackets)

After v0.2.14 added per-option `talent_swap_option_*` localization keys, the first dropdown rendered correctly but every subsequent dropdown wrapped the resolved text in another pair of angle brackets — the 20th career's dropdown showed nineteen layers (`<<<<<<<<<<<<<<<<<<<None (default)>>>>>>>>>>>>>>>>>>>`).

Root cause: VMF's `options.lua localize_dropdown_data` mutates each option's `text` field in place (`option.text = mod:localize(option.text)`). All 20 dropdowns shared a single `local talent_swap_options = {…}` table reference, so:

1. First dropdown registered → `option.text` was `"talent_swap_option_none"` → mod:localize → `"None (default)"`.
2. Second dropdown registered → same physical table → `option.text` is now `"None (default)"` (not a key) → mod:localize falls back to `"<None (default)>"`.
3. Third dropdown → `"<<None (default)>>"`, and so on through the 20th.

Replaced the shared `talent_swap_options` table with a `_talent_swap_options()` factory function that returns a freshly-built table on every call. All 20 dropdowns now invoke the factory at widget construction so each gets its own option list to mutate.

This pattern is documented in `enemy_tweaker_data.lua:17-24`, which spells out the identical trap; the doc-comment is referenced in the new factory's header so the next person reading this file sees the rule.

## 0.2.17-dev (2026-05-16)

### Fixed: Boot-time `string.format` crashes from un-escaped `%` in localization strings

Four widget labels were crashing at boot when VMF resolved them through the localization → `string.format` pipeline: `rework_dr_ranger_attack_speed_5_to_10`, `rework_we_maidenguard_crit_chance_5_to_10`, `rework_wh_zealot_power_5_to_10`, `rework_wh_bountyhunter_double_shotted_80`. Each contained literal percent signs (`+5%`, `80%`, etc.) that `string.format` interpreted as malformed format directives.

Per `feedback_vt2_localize_string_format_pipeline.md`, any localization string that gets fed through `string.format` (talent description tooltips, VMF widget labels at registration, the chaos_wastes_tweaker Localize-hook descriptions) must escape literal `%` as `%%`. The escape collapses back to a single `%` after formatting.

Swept the entire `career_tweaker_localization.lua`: every raw `%` in user-facing strings is now `%%`. Beyond the four flagged labels, this also covered their `_description` siblings and three pre-existing strings that contained un-escaped percents (`rework_general_stagger_thp_description`, `rework_es_mercenary_hellborgs_tutelage_description`, `rework_wh_zealot_smite_random_crits_description`) — those weren't crashing at boot, presumably because tooltips render lazily, but they were the same bug waiting to fire on hover.

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
