# Enemy Tweaker Changelog

## 0.5.6-dev (2026-05-23) — Convert 6 NetworkLookup lookups to rawget (latent strict-__index crash fix)

### Why
`NetworkLookup.*` subtables install a strict `__index = error()` metatable at boot. Plain `NetworkLookup.foo[key]` on a missing key throws — see memory `reference_vt2_strict_lookup_rawget.md`. The lint pass on 2026-05-23 flagged six call sites inside the Big Rebalance sweep-damage hot path: `hit_zones[hit_zone_name]` (3 sites) and `damage_sources[item_name]` (3 sites). All six pull from vanilla-registered key spaces today, but they're latent bombs if a mod-injected weapon or breed key ever flows through the same path.

### Changed
- `enemy_tweaker_big_rebalance.lua` — converted six lookups to `rawget()`:
  - Line ~1087: `NetworkLookup.hit_zones[target_hit_zone_name]` → `rawget(...)`
  - Line ~1097: `NetworkLookup.damage_sources[damage_source]` → `rawget(...)`
  - Line ~1139: `NetworkLookup.damage_sources[damage_source]` → `rawget(...)`
  - Line ~1165: `NetworkLookup.hit_zones[hit_zone_name]` → `rawget(...)`
  - Line ~1185: `NetworkLookup.damage_sources[self.item_name]` → `rawget(...)`
  - Line ~1207: `NetworkLookup.damage_sources[damage_source]` → `rawget(...)`
- No defensive bailouts added: these sites feed `send_rpc_attack_hit` which already gets the vanilla path's nil propagation; we're matching vanilla behavior, just dropping the strict-`__index` crash. The lint flag was about latent breakage if a future change populates these vars from less-trusted sources.

### Verification
1. `tools/mod-lint/lint-mod.ps1` — passes.
2. `tools/lint/regression-lint.ps1 -Quiet` — sites no longer appear in `strict-table-lookup` findings.

## 0.5.5-dev (2026-05-23) — Reseed threat-value cache on mid-session difficulty-mimic re-enable (Issue #9)

### Bug
When user toggles enemy_tweaker OFF then back ON mid-mission, the ConflictDirector's threat-value cache and performance-manager state remain baked from init time (when hooks were inactive). Difficulty mimic re-applies the spawn settings correctly, but the director's internal threat-tracking state is stale. Zone-boundary auto-fixes it (refresh_conflict_director_patches fires), but the feeling is broken until then.

### Fix
At end of `mod.on_enabled`, after re-applying difficulty mimic and faction swap, call `active:refresh_conflict_director_patches()` on the active ConflictDirector (if in-mission). This invalidates the threat-value cache and reseeds the performance-manager state immediately, closing the gap to zone-boundary refresh.

**Approach:** Option A — Force a settings refresh on re-enable (vanilla method call).
- **Why this path:** Vanilla `ConflictDirector.refresh_conflict_director_patches()` already exists and is used internally at zone transitions. It's safe, deterministic, and exactly what we need.
- **Alternative (Option C) rejected:** Tooltip warning was simpler but less user-friendly.

### Verification
- `mod:info("[et:difficulty-mimic] reseeded threat-values on enable (%s)", os.date())` logged at apply site per memory `feedback_vt2_verify_before_shipping.md`.
- Manual test: toggle ET off/on in-mission, observe no threat-value desync until next zone boundary.

### Changed
- `enemy_tweaker.lua` — `mod.on_enabled` now calls `active:refresh_conflict_director_patches()` if active ConflictDirector exists.
- Version bumped: `0.5.4-dev` → `0.5.5-dev`.

## 0.5.4-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `enemy_tweaker.lua` — renamed `regression_test` → `et_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/et_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.4.2-dev (2026-05-16) — Fix `<<<...>>>` bracket-cascading on shared dropdown options

- **Bug:** dropdown option labels in Faction Substitution (2 of 3), Difficulty Mimic (5 of 6), and Breed Substitution (the second one) showed `<<<key>>>` or deeper bracket nests instead of localized labels. Root cause: I built each option table once at file scope (`local _MIMIC_OPTIONS = {...}`) and assigned the same table reference to multiple dropdowns. VMF's `options.lua: localize_dropdown_data` mutates `option.text = mod:localize(option.text)` in place. After the first dropdown of a group processes, option.text is the localized string ("Match (vanilla)"); the next sharing dropdown then tries `mod:localize("Match (vanilla)")` which has no loc entry → `<Match (vanilla)>`. Each additional shared dropdown wraps another layer of brackets.
- **Fix:** replaced shared option tables with factory functions (`_faction_swap_options()`, `_mimic_options()`, `_build_breed_options()`) called per-dropdown so each dropdown gets a fresh options table. The existing `horde_preset` dropdown was unaffected because its options were inlined uniquely.

## 0.4.1-dev (2026-05-16) — Difficulty Mimic

### Added
- **Difficulty Mimic** menu under Enemy Spawns. 6 independent dropdowns (Horde Composition / Specials / Horde Frequency / Roaming Density / Intensity / Boss-Event), each overrides the difficulty key used by `ConflictUtils.patch_settings_with_difficulty` for that subsystem. Player/enemy HP/damage stay on the real difficulty. Use cases: Champion stats + Cataclysm-1 horde sizes; Legend stats + Recruit specials; etc.
- Hooks `ConflictDirector.refresh_conflict_director_patches` (already hooked for faction-swap) — runs mimic FIRST (replaces `CurrentHordeSettings` / `CurrentSpecialsSettings` / `CurrentPacing` / `CurrentPackSpawningSettings` / `CurrentIntensitySettings` / `CurrentBossSettings`), then faction-swap mutates `CurrentHordeSettings` in place.
- `on_setting_changed` triggers a live re-apply via the active CD if the player is in a mission — no level restart needed.
- `et_status` prints active mimic overrides.

## 0.4.0-dev (2026-05-16) — Faction substitution; skeleton clones removed

### Added
- **Faction Substitution menu** (3 dropdowns: Replace Skaven / Chaos / Beastmen Hordes With ...). Hooks `ConflictDirector.refresh_conflict_director_patches` and rewrites `CurrentHordeSettings.{ambush,vector,vector_blob,mini_patrol}_composition` based on the user's map. Handles both string fields (e.g. `"medium"` → `"beastmen_medium"`) and Cataclysm list-of-strings fields. Re-applies on every per-zone CD switch so Athel Yenlui / Hunger in the Dark / etc. honor the swap across the chaos-zone transition. Affects paced/blob hordes only — terror-event hordes still use vanilla `HordeCompositions` (separate workstream).
- `et_status` command now prints the active faction-swap map plus the current `CurrentHordeSettings.*_composition` values, so you can verify the rewrite actually fired in-mission.

### Removed
- **Skeleton breed clones** (`et_necro_skeleton{,_armored,_dual_wield,_shield}`, `et_ghost_skeleton_{hammer,shield}`) and the three skeleton horde presets (`Necromancer Skeletons` / `Ghost Skeletons` / `All Skeletons Mixed`). Reason: paced-only patching meant skeletons were rare in adventure missions (most hordes are terror-event-driven, bypassing `HordeCompositionsPacing`), and the clones required extensive vanilla-table seeding at boot (`threat_values`, `StatisticsDefinitions.*_per_breed`, `BreedHitZonesLookup`) — multiple boot-time crashes across v0.3.3 → v0.3.8 paid for that. Deferred until the terror-event-composition patcher lands. The design lessons live in `feedback_vt2_pairs_breeds_at_file_load.md` and `feedback_vt2_threat_values_upvalue_built_once.md` so any future revival builds on them. See `project_enemy_tweaker.md`.
- Defensive `ConflictDirector.calculate_threat_value` hook — no longer needed without our custom breeds.
- `EnemyPackageLoader._breed_package_name` redirect hook — same reason.
- `et_check_skeletons` command.
- Skeleton entries from `enemy_tweaker_breeds.lua` (`M.SKELETON`, `_SKELETON_SET`, `et_*` `BREED_NAME_OVERRIDES`, "Undead" faction group in localization).

## 0.3.8-dev (2026-05-16) — Overlay source-breed hit_zones on skeleton clones

- **Bug:** `action_sweep.lua:291: attempt to index local 'hit_zone' (a nil value)` on melee hit against a skeleton clone mid-mission. Root cause: clone deep-copied chaos_skeleton's `hit_zones` (whose `actors` lists reference chaos_skeleton's actor names) but used pet_skeleton / ethereal_skeleton's `base_unit`. `DamageUtils.create_hit_zone_lookup` walks `breed.hit_zones[*].actors` and looks up each name on the actual unit via `Unit.actor`; missing names are logged with `printf` and silently dropped, leaving the per-unit lookup partial. First sweep that hit an unmapped actor's node got `breed.hit_zones_lookup[node] = nil` and crashed on the subsequent `.name` deref.
- **Fix:** in `_register_skeleton_breeds`, after seeding the clone from chaos_skeleton, overlay `breed.hit_zones = _deep_copy(source.hit_zones)` so actor names line up with whatever model unit we adopted (pet_skeleton, ethereal_skeleton_with_hammer, etc.). chaos_skeleton's AI / perception / unit_template still drive behavior; only the per-actor hit map is taken from the source breed.

## 0.3.7-dev (2026-05-16) — Add `name` leaf marker on seeded stats entries

- **Bug:** v0.3.6's seeded entries on `StatisticsDefinitions.player.kills_per_breed_persistent` and the difficulty subtables triggered `statistics_database.lua:102: bad argument #1 to 'pairs' (table expected, got string)` at PlayFab stat-register time. Root cause: `_init_backend_stat` uses `if definition.name then` to decide leaf vs. category — without `name`, it recurses, and the recursion walks into the `database_name` string field and crashes on `pairs(string)`. The decompile of `statistics_definitions.lua` in our source repo shows vanilla's persistent entries also without `name`, but the LIVE game must include it (otherwise vanilla would crash itself).
- **Fix:** added `name = n` to `kills_per_breed_persistent[n]` and `name = n .. "_" .. difficulty_name` to both `kills_per_breed_difficulty[n][diff]` and `kill_assists_per_breed_difficulty[n][diff]` so the leaf check fires before the recursion goes off the rails.

## 0.3.6-dev (2026-05-16) — Seed per-breed statistics entries for custom skeletons

- **Bug:** with v0.3.5's threat-value fix in place, damaging a skeleton triggered `[StatisticsDatabase] No statistics definition found with path 'StatisticsDefinitions.player.damage_dealt_per_breed.et_ghost_skeleton_hammer'`. Same root cause class as the threat_values one — `statistics_definitions.lua:615` walks `pairs(Breeds)` at file-load to build per-breed stat tables, our skeletons miss the cutoff, and `StatisticsDatabase._create_stat` ferrors on the first lookup.
- **Fix:** after threat-value registration in `_register_skeleton_breeds`, mirror the vanilla Breeds loop and seed every per-breed entry directly on `StatisticsDefinitions.player.*`: `kills_per_breed`, `kills_per_breed_persistent` (with `source = "player_data"` and `database_name`), `kill_assists_per_breed`, `damage_dealt_per_breed`, `kills_per_race` (if breed has one and race isn't already there), plus the per-difficulty `kills_per_breed_difficulty[n][diff]` and `kill_assists_per_breed_difficulty[n][diff]` subtables. `StatisticsDatabase._create_stat` re-reads the definitions table at call time, so additions are live without further plumbing.

## 0.3.5-dev (2026-05-15) — Eager threat-value registration (works when mod is disabled)

- **Bug:** v0.3.3/v0.3.4's defensive hook on `ConflictDirector.calculate_threat_value` was bypassed when the user had Enemy Tweaker toggled off in VMF settings. VMF still loads our script (which mutates `Breeds` to add the `et_*_skeleton` clones), but skips our hooks. PerformanceManager seeds `activated_per_breed` from `pairs(Breeds)` at level start — our skeletons are in there. `calculate_threat_value` walks that table and hits `threat_values["et_necro_skeleton_shield"] * 0` → `nil * 0` → crash, because no hook ever populated `threat_values` for our breeds. Confirmed via crash log frame [1] locals.
- **Fix:** register threat values DIRECTLY via `ConflictDirector.set_threat_value(nil, name, value)` inside `_register_skeleton_breeds`, not via a hook. The method doesn't use `self`, so calling it as a static writer goes straight to the file-local `threat_values` upvalue. Runs eagerly at mod-script load, so the entries exist regardless of whether the mod's hooks are enabled. The defensive `calculate_threat_value` hook from v0.3.3 stays as a backstop for any future custom breed (ours or another mod's) that's added after this point.

## 0.3.4-dev (2026-05-15) — Build + deploy v0.3.3 fix

- Rebuild bump: v0.3.3-dev's `calculate_threat_value` crash fix was committed to source but never built; the deployed bundle remained the May-10 pre-fix copy and the user re-hit the crash. Same code, fresh bundle.

## 0.3.3-dev (2026-05-15) — Fix `calculate_threat_value` nil-arithmetic crash

- **Bug:** `[Script Error]: scripts/managers/conflict_director/conflict_director.lua:2479: attempt to perform arithmetic on a nil value`. The vanilla `threat_values` upvalue is built ONCE at game-boot by iterating `Breeds`. Our `et_*_skeleton` clones are added to `Breeds` after that loop runs, so the upvalue lookup `threat_values[breed_name] * amount` returns nil whenever an unregistered breed shows up in `activated_per_breed`. The existing `ConflictDirector.init` hook calls `set_threat_value` for our skeletons, but only fires on level transition — any path that hits `calculate_threat_value` before then (or any other mod adding breeds we don't know about) still crashes.
- **Fix:** added a defensive hook on `ConflictDirector.calculate_threat_value` that pre-flights `activated_per_breed` and idempotently calls `self:set_threat_value(name, Breeds[name].threat_value or 0)` for every breed before the original runs. Backstops every code path, not just the skeleton clones.

## 0.3.2-dev (2026-05-10) — Fix bracketed widget labels

- **Bug:** widget labels and dropdown options displayed as `<horde_preset>`, `<preset_off>`, `<%>` etc. Root cause: `_data.lua` called `mod:localize(...)` at file-load time before VMF's loc table was registered, so the function returned its `<key>` fallback; that bracketed string then became the literal widget text. Plus `unit_text = "%"` was treated as a loc key (per the user's own DEVELOPMENT.md "Known Errors") and `%` is an invalid format specifier.
- **Fix:**
  - Pass raw localization keys (strings) to `text` / `tooltip` / dropdown-option `text` — VMF resolves them at render time, after loc is loaded.
  - Removed `unit_text`. The `%` is baked into the `Horde Size (%%)` label (with `%%` escape per VMF's `string.format` pass).
  - Pre-generate every dynamic per-difficulty / per-special loc entry inside `_localization.lua` so widgets can use auto-localization via setting_id with no need for `text` overrides.
- **Refactor:** moved breed lists, label resolver, difficulty list, and key builder to a new shared module `enemy_tweaker_breeds.lua` so `_data.lua` and `_localization.lua` share one source of truth.

## 0.3.1-dev (2026-05-08) — Per-difficulty Special Spawns

- **Specials UI restructured.** Replaced the Default/Disable/Customize dropdown with a nested layout: Enemy Spawns → Special Spawns → one collapsible per difficulty (Recruit, Veteran, Champion, Legend, Cataclysm 1, Cataclysm 2, Cataclysm 3). Each difficulty gets its own Max Specials Active, Max Specials of Same Type, Spawn Weights (per-special collapsible), Disabled Specials (per-special collapsible).
- **Defaults pre-populated from VT2's `SpecialDifficultyOverrides`** (conflict_settings.lua), so untouched sliders match vanilla numbers per difficulty (e.g. Cataclysm = 5 max, Legend = 4 max).
- **Hooks now read the active difficulty** at spawn time via `Managers.state.difficulty:get_difficulty()` and look up `et_diff_<key>_*` settings. Always-on (no global toggle); leaving values at defaults preserves vanilla behavior.
- Dropped the spawn cooldown min/max controls and the Use Spawn Weights toggle. Weights are always applied; default of 1 across the board produces uniform random selection (vanilla equivalent).

## 0.3.0-dev (2026-05-08) — Specials control, localized breed names, reorganized horde UI

- **Specials group** (new): Default / Disable / Customize dropdown plus controls for max specials alive, max same type alive, spawn cooldown min/max, per-special enable/disable, and per-special spawn weights. Built on three `SpecialsPacing` hooks (`specials_by_slots` instance, `setup_functions.specials_by_slots`, `select_breed_functions.get_random_breed`) — no-op when mode = Default.
- **Localized breed dropdowns**: breed-swap from/to now show "Stormvermin" instead of `skaven_storm_vermin`. Resolved at runtime via `Localize()` with a humanized-key fallback and explicit overrides for the names VT2 doesn't ship strings for (Lifeleech Sorcerer, Blightstormer, custom skeletons).
- **Horde preset dropdown reorganized**: items now prefixed `Faction:` (Skaven / Chaos / Beastmen / Mixed) vs `Theme:` (All Elites / Necromancer Skeletons / Ghost Skeletons / All Skeletons Mixed) so the two concepts no longer mix in one flat list.
- **Bugfix**: horde size multiplier now applies whether or not a preset is selected (was previously gated behind the preset early-return — users who set "200%" with no preset got vanilla hordes).

## 0.2.4-dev (2026-05-06) — Fix init crash on NetworkLookup strict-lookup

- Mod failed to load with `[NetworkLookup.lua] Table breeds does not contain key: et_necro_skeleton`. The existence check `not nl_breeds[def.name]` was itself a GET that tripped the strict `__index` metatable before the key got written. Switched to `rawget` for the check; direct assignment is unchanged.

## 0.2.2-dev

CHANGELOG started after the fact — earlier dev iterations are not documented here. See `git log -- enemy_tweaker/` for the actual history.

Future entries should follow the format used by the other tweaker mods: one `## <version> (date) — <one-line summary>` heading per change set, with bullet points or a short paragraph below.

