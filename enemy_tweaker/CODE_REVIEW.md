> [!WARNING]
> ⚠ **SUPERSEDED** — this snapshot is from 2026-05-24 (48 days old).
> Recent state may differ. Kept for historical context — verify against current
> code before acting on findings. Remove this banner manually after a refresh
> or move the doc to `_archive/audits/2026-05-24/`.
# Enemy Tweaker Code Review (2026-05-24)

> **[SUPERSEDED 2026-07-14 — #433 retired the implementation]** The Big Rebalance module, lifecycle stub, and fingerprint RPC described below were deleted. Hidden `br_*` identifiers remain reserved only for save compatibility; historical source is recoverable from git. Do not treat BR findings in this snapshot as current work.

**Version reviewed:** `0.7.1-dev` (per `MOD_VERSION` in `scripts/mods/enemy_tweaker/enemy_tweaker.lua:3`).

> **Header re-stamped 2026-05-29; body findings predate this version and may be stale — see GitHub Issues for current state.** This review was originally written against `0.5.7-dev`; the header version was corrected to match disk on 2026-05-29 but the body below was NOT re-reviewed. Treat individual findings as point-in-time observations from the `0.5.7-dev` era.

Scope: every Lua file under `enemy_tweaker/scripts/mods/enemy_tweaker/` (5 files, 2231 lines main + BR, 836 lines data/loc/breeds). Reviewed against the running VT2 source under `Vermintide-2-Source-Code/scripts/managers/conflict_director/` and `scripts/utils/loaded_dice.lua`.

Files reviewed:
- `enemy_tweaker.mod` (entry point)
- `itemV2.cfg`
- `scripts/mods/enemy_tweaker/enemy_tweaker.lua` (964 lines)
- `scripts/mods/enemy_tweaker/enemy_tweaker_big_rebalance.lua` (1267 lines)
- `scripts/mods/enemy_tweaker/enemy_tweaker_data.lua` (381 lines)
- `scripts/mods/enemy_tweaker/enemy_tweaker_breeds.lua` (236 lines)
- `scripts/mods/enemy_tweaker/enemy_tweaker_localization.lua` (219 lines)
- `CHANGELOG.md`, `EXPANSION_PLAN.md`, `SKELETON_HORDES.md` (skimmed for context)

---

## 1. Mod purpose

Tweaker: Enemies is a host-side spawn / enemy-tuning mod. Its surface area covers six independent systems, every one toggleable from the VMF settings menu:

1. **Horde composition presets** — replace VT2's paced `HordeCompositionsPacing` entries with single-faction or themed compositions (Skaven Only, Beastmen Invasion, All Elites, etc.) plus a 25–300% horde-size scaler.
2. **Difficulty mimic** — override the difficulty key used by `ConflictUtils.patch_settings_with_difficulty` per spawn subsystem (horde / specials / pacing / pack_spawning / intensity / boss), so the player can run Champion stats with Cataclysm horde sizes (or any mix).
3. **Per-difficulty special spawn controls** — max active, max same type, per-special weight, per-special disable; configured independently for each of the 7 difficulties (Recruit → Cataclysm 3).
4. **Breed substitution** — runtime swap of one breed name for another across paced/blob horde spawn lists and per-unit ambush spawns.
5. **Faction swap** — rewrite the active `CurrentHordeSettings.*_composition` strings so an entire faction's paced hordes are replaced by another faction's compositions for the current mission.
6. **Big Rebalance integration** — opt-in port of Core's BR enemy-side rebalance (stagger formula rewrite, damage-calc rewrite, shield-slam rewrite, THP-on-kill buff template bodies, per-breed bloodlust_health, breed.trash flags, on-stagger unbalance debuff). Gated through the sibling `bt` (buff_tweaker) mod's master toggle.

The legacy custom skeleton breeds (necro / ghost) prototyped in 0.2.x–0.3.8-dev were **removed in v0.4.0-dev** (see header comment in `enemy_tweaker.lua:57-66`). They only ever affected paced hordes, not the terror-event-driven `HordeCompositions` table that drives most adventure spawns, and required extensive boot-time seeding into vanilla tables (threat_values, StatisticsDefinitions, hit_zones). The future skeleton iteration is deferred until a HordeCompositions-overlay path is designed.

---

## 2. Architecture overview

### File structure
| File | Role |
|---|---|
| `enemy_tweaker.lua` | Main module: presets, faction-swap, difficulty-mimic, breed-swap, per-difficulty specials hooks, lifecycle (`on_enabled` / `on_disabled` / `on_setting_changed`), chat commands, regression-test scaffold. |
| `enemy_tweaker_big_rebalance.lua` | All Big Rebalance code (`require`'d as `BR`). Exports `on_enabled` / `on_disabled` / `on_setting_changed` driven from the main module. Hooks `DamageUtils.stagger_ai`, `DamageUtils.calculate_damage`, `ActionShieldSlam._hit`. |
| `enemy_tweaker_breeds.lua` | Shared data + helpers (`SKAVEN`/`CHAOS`/`BEASTMEN`/`LORDS`/`MONSTERS`/`CRITTERS` lists, faction/role predicates, `collect_specials()`, `breed_label()`, `DIFFICULTIES` table, `setting_key()`/`breed_swap_option_key()` formatters). Required by both `_data.lua` and `_localization.lua` so widgets and loc keys stay in sync. |
| `enemy_tweaker_data.lua` | VMF widget tree. Builds horde / faction-swap / breed-swap / per-difficulty specials groups + 16 BR sub-toggles. Uses **factory functions** for every dropdown options table (the 0.4.2-dev fix for the `<<<key>>>` bracket-cascading bug). |
| `enemy_tweaker_localization.lua` | Static `loc` table plus dynamic per-difficulty / per-breed entries appended in two loops over `B.DIFFICULTIES` × `SPECIALS` and `FACTION_GROUPS` × breed lists. |

### Hook points (9 total)
| File | Class | Method | Wrapper kind | Purpose |
|---|---|---|---|---|
| main | `ConflictDirector` | `init` | string-form `mod:hook` | Backup compositions, apply preset, build swap maps, apply mimic + faction swap. Runs once per mission. |
| main | `ConflictDirector` | `refresh_conflict_director_patches` | string-form `mod:hook` | Re-apply mimic + faction swap after zone-boundary CD switches (VT2 calls this to rebuild `Current*Settings`). |
| main | `HordeSpawner` | `compose_blob_horde_spawn_list` | string-form `mod:hook` | Breed-swap pass over the returned spawn-list (returns BOTH `spawn_list` and `num_to_spawn` — captures multi-return per `VMF_RECIPES.md` §2). |
| main | `HordeSpawner` | `spawn_unit` | string-form `mod:hook` | Per-unit breed-swap for ambush hordes (compose_horde_spawn_list returns ints, not a list — substitute at spawn site). |
| main | `SpecialsPacing.setup_functions.specials_by_slots` | (table-form) | `mod:hook` | Overrides `CurrentSpecialsSettings.max_specials` and filters `.breeds` via per-difficulty disabled toggles, restored after `func` returns. |
| main | `SpecialsPacing.select_breed_functions.get_random_breed` | (table-form) | `mod:hook` | Weighted random pick + `max_of_same` enforcement per active difficulty. |
| BR | `DamageUtils` | `stagger_ai` | table-form `mod:hook` | Big Rebalance stagger rewrite (gated on `br_stagger_ai_rewrite` AND bt master). |
| BR | `DamageUtils` | `calculate_damage` | table-form `mod:hook` | BR damage-calc rewrite (gated on `br_calculate_damage_rewrite` AND bt master). |
| BR | `ActionShieldSlam` | `_hit` | table-form `mod:hook` | BR shield-slam rewrite (gated on `br_shield_slam_rewrite` AND bt master). |

All wrappers use `mod:hook` (full transform). No `mod:hook_safe` anywhere in the mod. The two `SpecialsPacing` hooks are intentionally table-form because `SpecialsPacing.setup_functions` / `.select_breed_functions` are plain sub-tables, not classes (the engine never registers them as hookable strings).

### State (file-scope upvalues)
- `_original_compositions_pacing`, `_original_compositions` — deep-copy of `HordeCompositionsPacing` / `HordeCompositions` captured on first `_backup_compositions()`, restored on every settings change / disable.
- `_breed_swap_map`, `_faction_swap_map` — rebuilt from settings via `_build_swap_map()` / `_build_faction_swap_map()` on every state change.
- BR module: `_original_bloodlust_health`, `_original_trash` (per-breed restore tables), `_br_master_applied`, `_br_hooks_installed` (idempotency flags).

### Cross-mod gating
- **Big Rebalance master toggle lives in `bt` (Tweaker: Buffs)**, not in et. `BR._master_on()` calls `get_mod("bt"):is_br_active()`; if bt isn't installed or its master is off, every BR sub-toggle in et is a no-op (with a warning logged on per-feature check). Registration of buff templates / damage profiles / explosion templates also happens inside bt; et's `REG` table is now an empty stub (lines 38 of BR file) — comment block explains this is the post-extraction of the cross-mod-shared registration list.

---

## 3. Risk hotspots

### R1. `v0.5.5-dev` mid-session reseed path — narrow but defensible
`mod.on_enabled` (main `:740-760`) was extended with `active:refresh_conflict_director_patches()` to invalidate the threat-value cache when the user toggles et off→on during a mission (issue #9, now closed). The call is **idempotent on vanilla** — `refresh_conflict_director_patches` is the same vanilla method VT2 invokes at every zone boundary, so calling it once extra is safe. Two things to keep an eye on:

1. The reseed only runs when `Managers.state.conflict` is non-nil. If the user enables the mod from the main menu / hub world there is no active CD, the call is skipped (correctly), and the next mission's `ConflictDirector.init` hook handles seeding. The control flow looks right, but live verification with the user toggling off-on inside a mission has not been logged anywhere I could grep — `mod:info("[et:difficulty-mimic] reseeded threat-values on enable")` shows up in the source but no observation of it firing has been recorded. Worth a quick smoke confirmation.
2. The path only fires from `on_enabled` — `on_setting_changed` calls `_reapply_via_active_cd()` which does NOT call `refresh_conflict_director_patches`, just re-runs mimic + faction-swap. If the user changes a *mimic* setting mid-mission (without toggling the mod off-on), the threat-value cache might still go stale until zone boundary. Possibly intentional ("only flush on hard re-enable"), possibly an inconsistency.

### R2. `_apply_horde_preset` mutates EVERY `HordeCompositionsPacing` entry when multiplier ≠ 1.0
The size-multiplier loop at `enemy_tweaker.lua:312-318` iterates **every key in `HordeCompositionsPacing`**, including ones the preset never touched (versus / weave / deus variants, mod-injected compositions). The `_restore_compositions()` step on each settings-change restores cleanly because we deep-copy the originals, but any third-party mod that runs AFTER et and reads `HordeCompositionsPacing[some_other_key]` will see scaled numbers. Low-risk in practice (et is generally meant to be authoritative on horde composition), but document or scope the loop to known keys if a compat issue surfaces.

### R3. Faction-swap is irreversible within an active CD
The `on_disabled` handler (`enemy_tweaker.lua:727-738`) acknowledges that mutating `CurrentHordeSettings.*_composition` in place is non-recoverable without a director-rebuild — the comment block at `:731-735` is explicit. Next `refresh_conflict_director_patches` (zone change) restores it. Acceptable, but the player won't see the swap revert until they cross a zone boundary or restart the mission; the `mod:echo("Enemy Tweaker disabled — compositions restored")` line could mislead.

### R4. Big Rebalance hook bodies are large verbatim ports of decompiled source
The `_do_damage_calculation` helper (BR `:631-840`, 210 lines) and `ActionShieldSlam._hit` body (BR `:1017-1219`, 203 lines) are copy-pastes from Core's Big Rebalance decompile. The six `rawget(NetworkLookup.{hit_zones,damage_sources}, ...)` calls (lines 1087, 1097, 1139, 1165, 1185, 1207) are the v0.5.6-dev hardening — they now match `PROJECT_STANDARDS.md`'s strict-`__index` rule. The risk is upstream drift: any future Fatshark patch that changes `DamageUtils.calculate_damage` semantics will silently diverge from the BR hook body. This is inherent to the verbatim-port design pattern; no fix available short of feature-pinning to a vanilla version.

### R5. `BR._stub_template` no-ops because `REG.BR_BUFF_TEMPLATES` is empty
Per the comment block at `enemy_tweaker_big_rebalance.lua:31-38`, the canonical registration list was extracted into `bt`. The local `REG` stub is `{ BR_BUFF_TEMPLATES = {}, ... }`. `_register_buff_templates()` (`:268-300`) iterates an empty list, returns true (because the `BT`/`NL` guard passes), and `_br_master_applied = true` is set without any actual registration work. That's fine **as long as `bt` is installed and has done its own registration pass**. If a user installs et without bt and flips the master on (impossible via UI now — the et master toggle was removed in this refactor — but possible by editing settings.json), the THP/unbalance template bodies will be `_set_template_body(name, body)` writes into a `BuffTemplates` table that has no NetworkLookup index for the name, and the first RPC referencing the template will fail. The `_feature_on` check guards this since it requires `_master_on()` which requires bt — but defensive enforcement at boot would be worth adding.

### R6. Defensive logging is sparse, especially in the spawn hot path
- `mod:info` fires once per `ConflictDirector.init` ("compositions applied"), once per BR registration burst, and once per mid-session reseed.
- No logging on faction-swap rewrites (silent unless `/et_status` is invoked).
- No logging on per-unit breed-swap fallbacks (when `Breeds[replacement]` is nil, the original breed silently spawns).
- `_warn` fires only for: `bt` missing in `_feature_on`, BR cross-cutting class tables not loaded, BR buff-template registration failure.

For multiplayer crash diagnosis the gaps could matter — if a client without the mod RPC's an unexpected breed name (because the host did a swap), there's no host-side trail. Adding a `mod:info` at apply-time on every swap-map rebuild would help triage.

### R7. No host/client gating
Every hook runs on every peer. The composition / faction-swap / mimic mutations are harmless on clients (the host runs the spawn logic), but the BR `DamageUtils.calculate_damage` / `DamageUtils.stagger_ai` hooks DO run on every peer that has the mod, and the math is purely local (calculate_damage is called inside `is_server` branches anyway by the time it matters for damage resolution). Per `enemy_tweaker_big_rebalance.lua:418` / `:855` the only `is_server` check inside BR is in proc-function bodies that are explicitly server-only. There's no documented assumption that all peers must have the same BR sub-toggles enabled. **If host has `br_calculate_damage_rewrite` ON and client has it OFF**, the client's local calculate_damage call returns vanilla numbers while the server's says BR numbers — likely results in client-side prediction divergence (rubberbanding hit reactions) rather than a crash, but worth a multiplayer smoke test before public release.

### R8. `_set_template_body` overwrites prior buffs unconditionally
`enemy_tweaker_big_rebalance.lua:362-366` — `_set_template_body(name, body)` does `BT[name] = { buffs = { body } }`. If anything in vanilla, bt, or another mod has populated `BT[name].buffs` with additional entries, this stomps them. The BR file owns these template names exclusively (`rebaltourn_regrowth` / `_vanguard` / `_reaper` / `_bloodlust` / `_tank_unbalance` / `_tank_unbalance_buff`) so the conflict surface is small, but a future cross-mod boon/talent that wanted to extend one of those templates would be silently overridden.

---

## 4. QA status

### Tests / checks present
- **`/et_regression_test` chat command** (renamed from `regression_test` in v0.5.4-dev to avoid the cross-mod collision). Four `_rt_register` checks:
  1. `dropdown_options_factories` — marker-only check confirming the v0.4.2 factory-function fix is still in place.
  2. `horde_compose_returns_multivalue` — verifies `HordeSpawner.compose_blob_horde_spawn_list` + `HordeSpawner.spawn_unit` exist (catches upstream method renames).
  3. `breed_swap_map_table` — confirms `_breed_swap_map` is a table.
  4. `et_big_rebalance_uses_rawget` — v0.5.7 runtime check: marker constant present + `rawget(NetworkLookup.{hit_zones,damage_sources}, <bad-key>)` returns nil without raising.
- **Lint coverage**: `tools/lint/regression-lint.ps1`'s `strict-table-lookup` flag covers the six BR sites statically.
- **Diagnostic commands**: `/et_dump_breeds` (breeds by faction with `special`/`boss`/`elite` flags), `/et_dump_compositions` (pacing keys + variant counts), `/et_status` (current preset / multiplier / swap / mimic / `CurrentHordeSettings` snapshot).
- **REGRESSION_CHECKLIST.md** exists at mod root.

### Gaps
- **No multiplayer smoke test recorded** for the BR hook divergence scenario described in R7.
- **No verification log** for the mid-session reseed code path added in v0.5.5-dev — the `mod:info` is wired but I couldn't find a session-log artifact confirming the `[et:difficulty-mimic] reseeded threat-values on enable` line ever appeared.
- **No regression check** for the faction-swap → `_remap_composition` fall-back path (`enemy_tweaker.lua:411-414` — when target composition doesn't exist, return original; not currently asserted).
- **No regression check** for the per-difficulty specials hook when the active difficulty has zero enabled specials (line 635-637 falls back to `func(...)`, presumably vanilla behavior, but unverified).
- BR `_set_template_body` overwrite behavior (R8) has no test.

---

## 5. Open follow-ups

Cross-checked against `gh issue list --state open`. There is no `enemy_tweaker` label in the repo's label set, so issues touching this mod are filed under `audit` / `bug` / etc. The currently open repo issues with even loose enemy_tweaker relevance:

- **Issue #2** (`audit, refactor`) — *8 Lua files over 2500-line hard limit*. Enemy Tweaker is **not currently on the list** (`enemy_tweaker.lua` 964 lines, `enemy_tweaker_big_rebalance.lua` 1267 lines, both well under the 1500-line target). Mentioned here only to note the absence — no action needed.

Recently closed for this mod:
- **Issue #9** (closed 2026-05-23) — *et: difficulty-mimic threat-value seeding gap on mid-session re-enable*. Fixed in v0.5.5-dev (R1 above). Live verification still desirable.
- **Issue #11** (closed 2026-05-23) — *Cross-mod chat-command name collision: 7 mods all registered 'regression_test'*. Fixed in v0.5.4-dev (renamed to `/et_regression_test`).

### Suggested new follow-ups (not yet filed)

These are NOT cited Issue numbers — file with `gh issue create` first before referencing.

1. **Multiplayer-divergence smoke test for BR sub-toggles.** Host and client must agree on `br_calculate_damage_rewrite` / `br_stagger_ai_rewrite` / `br_shield_slam_rewrite` or local damage prediction diverges. Document the requirement; consider host-only `mod:info` warning if the mod detects it's a client and BR is active (no easy way to check the host's settings, but at least log).
2. **`on_setting_changed` mimic re-apply should consider calling `refresh_conflict_director_patches`** to match the `on_enabled` path. The threat-value-cache invalidation gap (R1.2) is a latent edition of the issue #9 bug for the mid-mission settings-edit case.
3. **`/et_status` should report active BR sub-toggles** (and whether bt master is on / installed). Currently shows preset / multiplier / swaps / mimic; doesn't surface BR state, which makes triage of BR-related reports awkward.
4. **Description-block version drift** in `itemV2.cfg` (still says v0.5.5-dev). Fix on next upload — `VMBLauncher.exe upload` only rewrites the title, not description.
5. **EXPANSION_PLAN.md still references B1 / B2 from the 2026-05-01 review** as "Open from CODE_REVIEW.md, verify before Phase 1." Both bugs are fixed (the current `_apply_preset_to_pacing_keys` rebuilds `loaded_probs` via `_build_loaded_probs`; ambush breed-swap is at `HordeSpawner.spawn_unit` not `compose_horde_spawn_list`). Update the plan doc.

---

## 6. Settings coherence (spot check)

Sampled `mod:get` keys against widget definitions and localization:

| `mod:get` key | data.lua widget | loc key | Notes |
|---|---|---|---|
| `horde_preset` | dropdown | yes | 6 options, all localized |
| `horde_size_multiplier` | numeric | yes | `%%` escape correct in label |
| `breed_swap_from` / `breed_swap_to` | dropdown (factory `_build_breed_options`) | yes | per-breed loc keys built in loc loop |
| `faction_swap_{skaven,chaos,beastmen}` | dropdown (factory `_faction_swap_options`) | yes | |
| `mimic_{horde,specials,pacing,pack_spawning,intensity,boss}` | dropdown (factory `_mimic_options`) | yes | |
| `et_diff_<diff>_max_total`, `_max_same`, `_weight_<breed>`, `_disabled_<breed>` | numeric / checkbox (dynamic) | yes (dynamic) | both sides loop `B.DIFFICULTIES × SPECIALS` |
| `br_*` (16 sub-toggles) | checkbox | yes | each with `_tooltip` |

No orphan reads, no missing loc keys spotted in the spot check. The factory-function rule from v0.4.2-dev is intact — every shared dropdown options table is rebuilt per dropdown.

---

## 7. Notes for future agents

1. **Version is `0.5.7-dev`** in `enemy_tweaker.lua:3` (`MOD_VERSION`). Title in `itemV2.cfg` matches; description body lags one version.
2. **`MOD_VERSION` constant gets bumped EVERY edit per `CLAUDE.md` rules.** The version is echoed in-game on load (`mod:echo("Enemy Tweaker v" .. MOD_VERSION)`).
3. **Don't add a master toggle for BR back into et.** The master is intentionally owned by `bt`. The et BR toggles all gate through `BR._feature_on` → `_master_on()` → `bt:is_br_active()`.
4. **`HordeSpawner.compose_horde_spawn_list` (no `_blob`) returns three integers, not a list.** Hook `HordeSpawner.spawn_unit` for ambush breed-swap, not `compose_horde_spawn_list`. The fix is already in place (line 535); don't regress.
5. **`HordeCompositionsPacing[key].loaded_probs` MUST be rebuilt when replacing a composition.** `_build_loaded_probs` at `enemy_tweaker.lua:265-273` does this; the comment block above it cites the upstream callsites. Removing it crashes `LoadedDice.roll_easy` on the next horde.
6. **Custom skeleton breeds were removed in v0.4.0-dev** and live only in project memory now. Don't reintroduce them without the HordeCompositions-overlay design.
7. **Every BR `NetworkLookup.{hit_zones,damage_sources}[key]` lookup MUST use `rawget`.** The strict-`__index` metatable will fatal otherwise. Six sites converted in v0.5.6-dev (lines 1087, 1097, 1139, 1165, 1185, 1207 of the BR file). The `et_big_rebalance_uses_rawget` regression check guards this.
8. **Chat commands are typed as `/et_regression_test`, `/et_status`, `/et_dump_breeds`, `/et_dump_compositions` — no mod-id prefix.** The `et_` is part of the registered command name, not a chat prefix.
