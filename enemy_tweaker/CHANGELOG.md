# Enemy Tweaker Changelog

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
