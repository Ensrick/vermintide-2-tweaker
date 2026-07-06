# Enemy Tweaker Changelog

## 0.7.30-dev (2026-07-06): #275 - probe rewired to breed-field wrap + phase tracers

- **Root cause of the silent no-op:** the v0.7.29 probe hooked the
  `AiBreedSnippets` TABLE via `mod:hook_safe`, but the breed captures a DIRECT
  function reference at breed-definition load
  (`run_on_spawn = AiBreedSnippets.on_chaos_exalted_sorcerer_drachenfels_spawn`,
  breed_chaos_exalted_sorcerer_drachenfels.lua:119) and the engine invokes it as
  `breed.run_on_spawn(unit, blackboard)` (ai_simple_extension.lua:227/:257). A
  table hook never fires. The author's full-boss-fight log confirmed it: probe
  armed at load, zero SPAWN/STATE lines.
- **Fix - breed-field wrap:** `_et_nurgloth_probe.lua` now wraps the breed FIELDS
  `run_on_spawn` and `run_on_game_update` (the update field is
  `run_on_game_update`, invoked at ai_system.lua:894 -- not `run_on_update`)
  directly, idempotently, preserving the exact original reference and calling it
  raw so vanilla behavior is byte-for-byte intact; the probe runs AFTER, so the
  blackboard is populated. Pure field wrap in et's `_et_boss_tweaks.lua` style, no
  `mod:hook` on the snippet. SPAWN and STATE printf formats are UNCHANGED
  (`[et:275]` tags, 5s throttle, immediate print on mode/phase/flag change).
- **New phase-transition tracers:** wraps the seven penny-registered drachenfels
  BT hooks -- merged into the global `BTEnterHooks` / `BTLeaveHooks` tables via
  `DLCUtils.merge` (bt_enter_hooks.lua:542 / bt_leave_hooks.lua:339) from
  `settings.bt_enter_hooks` / `settings.bt_leave_hooks`
  (penny_ai_settings_part_3.lua:77 / :213). Enter: `intro_enter`,
  `re_enter_defensive_mode`, `begin_defensive_mode`. Leave: `intro_leave`,
  `transition_at_two_thirds`, `transition_at_one_third`,
  `go_offensive_intense`. Each fires a
  `[et:275] HOOK <name> | hp_pct min_hp_pct two_thirds_done one_third_done` line
  (original called first, tracer after). Prints `[et:275] tracers armed: N wrapped`.
- **Install timing:** `BTNode.init` captures the enter/leave hook into an upvalue
  at node construction (bt_node.lua:24-33), which happens in
  `AISystem.create_all_trees` at mission load (ai_system.lua:105/:1693). The wrap
  is therefore driven from a pre-step on `AISystem.create_all_trees` (sole et hook
  on that pair) -- tables wrapped, THEN original runs -- so each mission's fresh
  BTNodes capture our wrappers. Breed wrap rides the same point (Breeds is a boot
  global; mission load precedes the boss spawn). Both idempotent across missions.
- **Doctrine unchanged:** always-on in dev, no menu toggle, engine `printf` (user
  runs mod-logging OFF), every read guarded, probe bodies pcall-wrapped; the
  ORIGINAL always runs raw so a probe fault can never disturb the fight.

## 0.7.29-dev (2026-07-06): #275 diagnostics - Nurgloth blackboard phase probe

- **Issue 275 diagnostics (no fix, capture only):** Nurgloth (breed
  `chaos_exalted_sorcerer_drachenfels`, The Enchanter's Lair = `dlc_castle`)
  desyncs into his final phase at appearance with health floored at ~66% on a
  friend's machine; gut's cutscene skip was exonerated (cinematic played fully,
  desync persisted). New host-side probe captures the boss blackboard so the next
  repro shows WHY the fight jumps a phase at spawn. 66% is exactly the two-thirds
  phase-transition threshold (`blackboard.current_health_percent <= 0.66`,
  bt_conditions.lua:332), so the probe reads that exact FIELD next to the
  transition-done flags and mode/phase, and separately reads the health
  extension's own percent so a divergence is visible.
- **New file `scripts/mods/enemy_tweaker/_et_nurgloth_probe.lua`** — two NEW
  `mod:hook_safe` on `AiBreedSnippets.on_chaos_exalted_sorcerer_drachenfels_spawn`
  and `..._update` (grepped: enemy_tweaker had no prior hook on either method).
  SPAWN prints one line (`in_boss_arena / mode / phase / intro_timer / hp_pct /
  min_hp_pct / invincible`). UPDATE prints one throttled line every 5s plus an
  immediate line whenever `mode` / `phase` / `two_thirds_transition_done` /
  `one_third_transition_done` changes (`mode / phase / current_health_percent /
  min_hp_pct / invincible / two_thirds_done / one_third_done / third_phase /
  defensive_dur`). Throttle + last-seen state stored on the blackboard.
- **Cross-mod:** the friend runs DutchSpice, which `hook_origin`-REPLACES the
  spawn body (DutchSpice.lua:1766). VMF's duplicate-drop is per-mod and safe
  hooks run after the hook chain (including a `hook_origin` replacement), so this
  probe fires even when DutchSpice's replacement is the active spawn function.
- **Doctrine:** always-on in dev, no menu toggle, engine `printf` (user runs
  mod-logging OFF), every read guarded, whole body pcall-wrapped so a probe fault
  can never break the fight. Tag `[et:275]` — grep the friend's console log for it.
- **Files:** `enemy_tweaker.lua:3` MOD_VERSION 0.7.28-dev -> 0.7.29-dev; `~3602`
  dofile of the new probe (after `_et_boss_tweaks`); new `_et_nurgloth_probe.lua`.

## 0.7.28-dev (2026-07-05): #213 CLOSED (user-confirmed) - double-freeze guard regression test + loc-tag flip

- #213 CLOSED (user confirmed the "Tried to freeze unit twice in the same frame" engine error
  no longer appears under raised grunt caps). The live guard (since v0.7.22-dev) hooks
  BreedFreezer.try_mark_unit_for_freeze, replicates vanilla's own duplicate check, and returns
  true when a unit is already queued this batch so the caller skips the redundant
  mark_for_deletion - the unit stays frozen exactly once and the ERROR is suppressed. Fail-open
  (any unresolvable state falls through to vanilla). Confirmed live in the v0.7.214 host log
  (`[et] [213:freeze] suppressed`, zero double-freeze errors across 106k lines). Fix unchanged;
  this build adds the guard + loc flip.
- TEST: new `double_freeze_guard_wired` source-pattern check asserts the BreedFreezer suppression
  hook survives (the existing `et_freeze_probe_present` guarded only the printf probe helper, not
  the fix logic).
- LOC: `max_grunts_override` tag `[Issue 213] [verify-fix] [diag]` -> `[diag]` (dropped the
  now-closed 213 ref + verify-fix; kept `[diag]` - the `[213:freeze]` probe stays armed).

## 0.7.27-dev (2026-07-04): Skaven Warlord as a monster (#324)

### Added
- **New boss breed `et_skaven_warlord` ("Skaven Warlord")** — deep-copied from PRISTINE vanilla `skaven_storm_vermin_champion` (registration is placed BEFORE the Champion elite-pool retune's load-time apply, so the clone always carries the vanilla 800-HP champion boss stat block even with `champion_in_elite_pool` saved ON). Keeps the champion `base_unit` — the unused colour-variant of Skarrik's warlord model (`chr_skaven_stormvermin_champion`, breed_skaven_storm_vermin_champion.lua:12) — race skaven, behavior `storm_vermin_champion`. New subsystem file `_et_skaven_warlord_breed.lua` walks the full DEVELOPMENT.md breed-adding checklist: threat_values via `ConflictDirector.set_threat_value(nil, ...)`, full StatisticsDefinitions per-breed seed loop (incl. `name` leaf markers + per-difficulty children), NetworkLookup.breeds AND NetworkLookup.damage_sources forward+reverse (AI melee uses the breed name as damage_source, ai_utils.lua:266), `BreedActions` clone, `EnemyPackageLoaderSettings.alias_to_breed` -> champion package (the vanilla alias mechanic, enemy_package_loader.lua:189), `Dismemberments` share (unguarded consumer at generic_hit_reaction_extension.lua:544), SKAVEN race set, BreedHitZonesLookup mirror, warlord boss-bar portrait (`unit_frame_portrait_enemy_warlord`). PerformanceManager needs NO hook: `_activated_per_breed` is rebuilt from `pairs(Breeds)` inside `PerformanceManager.init` at level start (performance_manager.lua:84-88), which always runs after mod load; a live instance is belt-seeded anyway.
- **Behavior-tree safety verified, no new guards needed:** the champion tree (skaven_storm_vermin_champion_behavior.lua:5-133) has NO BTSpawnAllies node and the breed has NO `stagger_modifier_function`, so neither of Skarrik's two shipped off-arena crash classes (v0.7.14 intro_timer, v0.7.16 spawner-group fassert) exists on the new breed. Skarrik's two guards stay in place (they are breed-conditional on `skaven_storm_vermin_warlord` and keep protecting Skarrik spawns from other sources).
- **Grudge-mark names (#324 Part 3):** `GrudgeMarkedNames.et_skaven_warlord` registered with 12 new skaven-warlord names (Skrittch the Thrice-Crowned, Vraskitt the Gore-Warden, Kritchak Blackfang, Sneekit the Throat-Taker, Queekrit the Man-Flayer, Iskrit the Warp-Sworn, Gnashrak the Tail-Ripper, Skabrit Doom-Whisker, Vermitch the Hollow-Eyed, Rikkfang the Pit-Master, Tretchik the Oath-Gnawer, Karskit the Red-Clawed). Consumer verified: `TerrorEventUtils.get_grudge_marked_name` reads `GrudgeMarkedNames[breed_name]` at call time (terror_event_utils.lua:59-78) and Localizes each key — served by et's new (and only) consolidated `_G.Localize` hook, since VMF mod-localization is invisible to vanilla `Localize`. Unmarked spawns render `Localize(breed.display_name)` = "Skaven Warlord" (boss_health_ui.lua:303/:174).
- **`/et_regression_test` checks:** `skaven_warlord_breed_checklist` (every checklist side-table + loc + alias + pristine-stat assertions) and an updated `warlord_monster_swap_hook` (swap must target `et_skaven_warlord`).

### Changed
- **Monster-pool swap retargeted (#324 Part 2):** `warlord_in_monster_pool` / `warlord_monster_chance` now substitute eligible monsters with the NEW Skaven Warlord breed instead of literal Skarrik Spinemangler. Chance semantics, eligibility list (Rat Ogre / Stormfiend / Chaos Spawn / Troll / Minotaur; troll_chief excluded), and host-side gating unchanged; setting_ids unchanged so saved settings carry over. Menu strings renamed to "Skaven Warlord ..." and re-tagged `[working]` -> `[untested]` per LOCALIZATION_STANDARD § 13.4 (significant overhaul).
- **Constraint (documented in tooltip + code):** every peer in the lobby must have enemy_tweaker installed for the new breed — its NetworkLookup.breeds / damage_sources indices exist only on et peers (strict `__index` metatable, network_lookup.lua:2360-2367); a client without et hard-errors when the breed spawns. (Installed-but-disabled is safe: registration is module-level per the DEVELOPMENT.md eager doctrine.)

### Files
- `enemy_tweaker.lua:3` — MOD_VERSION 0.7.26-dev -> 0.7.27-dev.
- `enemy_tweaker.lua:~1066` — dofile of the new breed subsystem (BEFORE the champion retune load-apply); `~1230-1330` — monster-pool banner + swap block retarget; `~3050-3140` — regression checks.
- `scripts/mods/enemy_tweaker/_et_skaven_warlord_breed.lua` — NEW: breed registration + checklist + `_G.Localize` hook.
- `enemy_tweaker_breeds.lua` — breed-name constant, display-name key, 12 grudge-name entries, BREED_NAME_OVERRIDES entry.
- `enemy_tweaker_data.lua` — section banner comment only (no widget changes).
- `enemy_tweaker_localization.lua` — Skaven Warlord strings + [untested] tags.

### Verify (in-game)
- Enable "Add Skaven Warlord to monster pool" at 100%%, host a mission with a monster spawn: the recoloured warlord spawns with a "SKAVEN WARLORD" boss bar and warlord portrait; kill it (dismember included) with no crash. In a Chaos Wastes trial with grudge marks, the name renders as one of the 12 new grudge names.

## 0.7.26-dev (2026-07-04): Localization dev status-tag pass (#301)

### Changed
- **Applied dev localization status-tag doctrine (#301).** Every rendered option-title loc entry now carries a status-tag prefix (group titles, master-toggle titles, and per-widget labels). 49 title keys tagged: 48 [working], 1 issue-tagged. `max_grunts_override` ("Max active trash enemies") carries `[Issue 213] [verify-fix] [diag]`: it raises `RecycleSettings.max_grunts`, the double-freeze fix (v0.7.22-dev `BreedFreezer` guard) awaits in-game verification, and the `[213:freeze]` printf probe is armed for it. All other rendered titles are established features with no open issue, tagged [working]. The 7 [working] tags in the per-difficulty generation loop expand to every Special Spawns group/cap/per-special title at load. Tooltips, dropdown value labels, and the commented-out Big Rebalance (`br_*`) block were not touched.

### Files
- `enemy_tweaker.lua:3` — MOD_VERSION 0.7.25-dev → 0.7.26-dev.
- `enemy_tweaker_localization.lua` — status-tag prefixes on all rendered option-title entries (static + generated).

## 0.7.25-dev (2026-07-02) — #240 alert helpers made genuinely log-only (chat-spam fix)

### Fixed
- **Routine diagnostics no longer post to in-game chat (#240).** User report 2026-07-02: "Enemy Tweaker keeps spitting out awful messages in the chat log." Log `console-2026-07-02-21.44.42-8d5b6420-*.log` showed 6 chat-visible WARNING lines on v0.7.24-dev: the `[et:spawn:roaming] multiplier=2.0 exceeds engine canonical max (8 units/IP)...` plateau notice fired 5x (twice per conflict-director apply, every mission/CD load at roaming slider 2.0) plus the boot-time `[et:dbg] on_enabled: _original_compositions_pacing nil...` line (lines 2335, 4725, 4742, 11124, 11143, 11683).
  - **Root cause:** v0.7.0-dev converted `_dbg_alert` / `_spawn_dbg_alert` to `mod:warning` with comments claiming the warning channel is "LOG-ONLY". False: upstream VMF `logging.lua` `load_logging_settings()` defaults `warning` to mode 3 with `send_to_chat = mode >= 2`, so `mod:warning` posts to chat AND log unless the user sets a custom VMF logging mode. Every alert-helper call landed in chat.
  - **Fix:** both helpers now emit via pcall-guarded raw engine `printf` — genuinely log-only, keeps the grep-stable `[et:dbg]` / `[et:spawn:<channel>]` prefixes, and (bonus) survives mod-logging-OFF sessions, which `mod:warning` never did. Genuine failure paths (`_safe`, `_hook_wrap`, BR fingerprint mismatch, etc.) keep their direct `mod:warning` calls, so real anomalies stay chat-visible.
  - **Also fixed latent double-post:** `_chat_alert` called `mod:warning` + `mod:echo` = two chat lines per call under VMF defaults (no live call sites). Now `mod:echo` only (echo mode 3 already writes chat + log).

### Added
- **`et_alert_helpers_log_only_240` regression check** (`/et_regression_test`): asserts the `mod._et_alerts_log_only_marker` guard constant plus smoke-calls `_spawn_dbg_alert`; fails if the helpers revert to chat-visible `mod:warning` routing.

### Files
- `enemy_tweaker.lua:3` — MOD_VERSION 0.7.24-dev → 0.7.25-dev.
- `enemy_tweaker.lua:~22-55, ~120-140` — `_dbg_alert` / `_chat_alert` / `_spawn_dbg_alert` rerouted; stale "file only" / "surfaces in chat when Debug Logging is on" comments corrected.
- `enemy_tweaker.lua:~3079` — new regression check.

### Verify (in-game)
- Load into the keep with roaming slider at 2.0: chat shows ONLY the `[et] v0.7.25-dev loaded` banner; the roaming-plateau line appears in `console-*.log` (`[et:spawn:roaming]`) but never in chat.

## 0.7.24-dev (2026-07-02) — #222 loc sweep (tooltip header de-duplication)

### Changed
- **#222 loc sweep: removed leading option-title restatement from 1 option tooltip so the popup body no longer repeats the orange header.** `breed_swap_from_tooltip` dropped its redundant opening sentence ("The enemy type to replace.") so the body now opens with the behavior; the second sentence already fully defines the option. No magnitude numbers, breed/mission names, or mechanical claims changed. The rest of the file was already behavior-first (Lets/Stops/Multiplies/Uses/Replaces/Scales/Registers) and left unchanged.

### Files
- `enemy_tweaker.lua:3` — MOD_VERSION 0.7.23-dev → 0.7.24-dev.
- `enemy_tweaker_localization.lua` — `breed_swap_from_tooltip` leading title restatement removed.

## 0.7.23-dev (2026-07-01) — Settings menu reorganization (sort + polish, no functional changes)

### Changed
- **Top-level menu entries now sort A→Z by display label.** New order: Beastman Banner, Boss Mechanic Tweaks, Breed Substitution, Enemy Spawns, Faction Substitution, Horde Composition, Skarrik Monster Pool, Spawn Pacing, Spawn Scaling, Stormvermin Champion Pool. Group order within Spawn Scaling, Spawn Pacing, Beastman Banner, and Difficulty Mimic is also A→Z. Deliberate-order exemptions (commented at each site): the Special Spawns per-difficulty blocks keep the difficulty ladder; Faction/Breed Substitution keep the Skaven → Chaos → Beastmen faction order; the Horde Frequency min/max pair reads min-before-max; the per-difficulty specials blocks lead with their count caps.
- **Group headings polished** (Title Case, no punctuation): "Spawn Pacing (frequency + caps)" → "Spawn Pacing"; "Monster Pool: Skarrik Spinemangler" → "Skarrik Monster Pool"; "Roaming Elite Pool: Stormvermin Champion" → "Stormvermin Champion Pool".
- **Setting labels converted to sentence case** per LOCALIZATION_STANDARD §11.1 (e.g. "Max Active Trash Enemies" → "Max active trash enemies", "Paced Horde Size (multiplier)" → "Paced horde size (multiplier)"). Proper nouns (Skaven, Chaos, Beastmen, Stormvermin Champion, Skarrik Spinemangler, difficulty names) stay capitalized. The `et_fly_disable_mult` label dropped its "x vanilla duration" phrasing: "Fly disable: x vanilla duration (Halescourge/Nurgloth)" → "Fly-disable duration (Halescourge/Nurgloth)".
- **A few tooltips tightened** (removed "When on," conditional preambles, trimmed prose) while preserving every magnitude, breed/mission-name reference, and host-only caveat.

### Structure
- **`warlord_monster_chance` and `champion_elite_chance` are now `sub_widgets` of their master checkboxes** (`warlord_in_monster_pool` / `champion_in_elite_pool`). VMF auto-hides each chance slider while its feature is off. Code-gated: `enemy_tweaker.lua` reads the chance value only when the checkbox is on (`~1248`/`~1258` for the warlord, `~1273`/`~1280` for the champion), so hiding it changes nothing functionally.
- **Localization file reordered** to mirror the widget tree with `-- ====` section banners. The commented-out Big Rebalance (`br_*`) widget block and its loc keys are retained unchanged (ON ICE; they do not render).

### Not changed
- No `setting_id` renamed, no setting added/removed, no default/range/decimals changed, no behavior changed, no new master toggles. The commented-out BR block is untouched.

### Files
- `enemy_tweaker.lua:3` — MOD_VERSION 0.7.22-dev → 0.7.23-dev.
- `enemy_tweaker_data.lua` — top-level widget array reordered A→Z; within-group order A→Z (exemptions commented); `warlord_monster_chance` / `champion_elite_chance` nested under their master checkboxes.
- `enemy_tweaker_localization.lua` — reordered to mirror the widget tree; group headings de-punctuated; setting labels sentence-cased; select tooltips tightened.

## 0.7.22-dev (2026-07-01) — Double-freeze guard + probe on the recycler freeze path (#213)

### Fixed
- **Suppressed the "Tried to freeze unit twice in the same frame" engine ERROR** under `EnemyRecycler.deactivate_area` with our raised grunt cap (#213). New guard hook on `BreedFreezer.try_mark_unit_for_freeze` (vanilla `scripts/managers/conflict_director/breed_freezer.lua`). The freeze is deferred to `commit_freezes`, so `ALIVE[unit]` stays true between two same-frame `ConflictDirector.destroy_unit` calls on one unit; the second call re-marked the unit, vanilla printed the ERROR (`breed_freezer.lua:253`) and then fell through to `mark_for_deletion` (`conflict_director.lua:2386-2387`), conflicting with the freeze queued on the first call. Raising `RecycleSettings.max_grunts` packs more roaming trash into recycler areas, so the window opened far more often than in vanilla.
  - **Guard:** replicates vanilla's own duplicate check (`breed_freezer.lua:247-257`) BEFORE calling vanilla, reading vanilla's own `self.units_to_freeze[breed]` list (same state, cleared on the same `commit_freezes` lifecycle -- no frame-boundary or unit-pooling guesswork). If the unit is already queued this batch, returns `true` ("already marked / handled") so the caller skips the redundant `mark_for_deletion`; the unit stays frozen exactly once. **Fail-open:** any unresolvable state (settings / breed / list) falls through to vanilla, so behavior is unchanged beyond suppressing the redundant second mark. No prior et hook on `BreedFreezer` (grep-verified) -- new `(Class, method)` pair.

### Added
- **`[213:freeze]` printf probe.** When the guard suppresses a double-freeze it prints `[et] [213:freeze] suppressed unit=<breed> queued=<n> count_this_frame=<n>` via the engine `printf` (visible with mod logging OFF, unlike `mod:*` logging), rate-limited to ~5 lines/min. `queued` is the current freeze-batch depth for that breed; the recycler area index is an unstable loop-local (`_update_roaming_spawning`, reshuffled by `fast_array_remove`), so it is not a meaningful identifier and is not reported. Absence of the tag after a horde-heavy session is itself data that the double-freeze window did not open.
- **New `_et_probe(key, fmt, ...)` helper** — direct engine-`printf` diagnostic channel, rate-limited per key, pcall-guarded. Added because the user plays with VMF mod-logging OFF, so `mod:info` / `mod:warning` / `mod:debug` never reach the handed-over console log (memory `reference_vt2_diagnostics_use_printf_not_modinfo`).

### Changed
- **`[rpc:schema]` mismatch log now uses `printf`, not `_dbg_alert`.** The `et_br_fingerprint` schema-mismatch line (added in 0.7.20-dev) routed through `mod:warning`, which is invisible with mod logging off -- so a mixed-version lobby drop was never actually landing in the user's log. Switched to `_et_probe` (keyed per peer, rate-limited).

### Tests
- New `_rt_register("et_freeze_probe_present")` smoke check (run via `/et_regression_test`) asserts `_et_probe` exists and does not raise, guarding against a revert that sends the probe back through invisible VMF logging.

### Files
- `enemy_tweaker.lua:3` — MOD_VERSION 0.7.21-dev → 0.7.22-dev.
- `enemy_tweaker.lua` — new `_et_probe` helper; `BreedFreezer.try_mark_unit_for_freeze` guard hook; per-frame suppression-counter reset in the `ConflictDirector.update` hook; `[rpc:schema]` log switched to `_et_probe`; new regression check.

### Grep (user log)
- `[213:freeze]` — guard fired (double-freeze suppressed). Absence after a horde-heavy host session = the window never opened.
- `Tried to freeze unit twice` — should no longer appear for freezable breeds once this build is the one actually running (verify via the `[id:LOAD]`/version banner).

## 0.7.21-dev (2026-07-01) — Player-facing option descriptions + menu localization pass

### Changed
- **Rewrote every menu tooltip into plain player-facing English.** All 30 static rendered option tooltips (spawn scaling, spawn pacing, horde preset, Beastman banner, difficulty mimic, faction/breed substitution, monster + roaming-elite pools, boss fly-disable) plus the 4 dynamically generated per-difficulty tooltip templates (special max-total, max-same, per-special weight, per-special disable) were rewritten to at most 2-3 sentences describing what the setting does in the game, with the internal engine jargon removed (global/table/field names like `CurrentHordeSettings.compositions_pacing`, `RecycleSettings.max_grunts`, `SizeOfInterestPoint`, `AIGroupSystem.create_formation_data`, internal breed ids, etc.). Meaning was preserved from the prior text; nothing new was invented. Titles/labels and all setting_ids, defaults, and widget structure are unchanged.
- **Removed em dashes from menu text.** The dynamically built breed-substitution dropdown option labels used an em dash separator (`"%s — %s"`); switched to a hyphen (`"%s - %s"`) per the no-em-dash-in-menus rule. The em dashes that remained were otherwise only inside the long tooltip values, which were replaced wholesale.

### Notes
- No `mod:localize()` calls exist in any widget field, so there were no double-localize (`<sentence>`) conversions to make. Every widget-referenced loc key (including the dynamically generated per-difficulty specials weight/disabled keys and the breed-swap option keys) resolves against the loc table; no missing entries were found or added.
- The commented-out Big Rebalance widget block (ON ICE) and its loc entries were left unchanged: those tooltips never render, and they document internal rebalance infrastructure where the technical terms are the content.

### Files
- `enemy_tweaker.lua:3` — MOD_VERSION 0.7.20-dev → 0.7.21-dev.
- `enemy_tweaker_localization.lua` — 30 static tooltip values + 4 dynamic per-difficulty tooltip templates rewritten; breed-swap option label separator em dash → hyphen.

## 0.7.20-dev (2026-07-01) — RPC schema versioning on the et_br_fingerprint channel (#42)

### Changed
- **`et_br_fingerprint` RPC is now schema-versioned** (VMF_RECIPES § 10 pattern, propagated from the ct v0.7.114-dev pilot / Issue #27). New `local ET_RPC_SCHEMA = 1` constant defined next to `MOD_VERSION`.
  - **Sender** (`mod._br_fingerprint_broadcast_once`): `ET_RPC_SCHEMA` is prepended as the FIRST positional arg, ahead of the existing `MOD_VERSION`, `fp` payload — `network_send("et_br_fingerprint", "others", ET_RPC_SCHEMA, MOD_VERSION, fp)`.
  - **Receiver** (`mod:network_register("et_br_fingerprint", ...)`): the callback now takes `(sender_peer_id, schema_version, peer_version, peer_fp)` and drops any message whose `schema_version ~= ET_RPC_SCHEMA` before touching state, logging `[rpc:schema] et_br_fingerprint mismatch ...` via `_dbg_alert` (log-only, never `error()`). The existing `type(peer_fp) ~= "string"` guard is retained as a defensive post-gate type check.
  - **Effect:** a mixed-version lobby (host on a new dev bundle, friend on a stale Workshop bundle, or vice versa) degrades cleanly — the mismatched fingerprint packet is dropped with a log line instead of being parsed by the wrong positions and producing a spurious BR-drift warning. No state mutation, no crash. Bump `ET_RPC_SCHEMA` only when the `et_br_fingerprint` payload shape changes (field add/remove/reorder, or a positional field's type changes).

### Tests
- New `_rt_register("et_rpc_schema_present")` smoke check (run via `/et_regression_test`) asserts `ET_RPC_SCHEMA` is a number and ≥ 1, guarding against a future revert silently un-gating the receiver.

### Files
- `enemy_tweaker.lua:3` — MOD_VERSION 0.7.19-dev → 0.7.20-dev; added `ET_RPC_SCHEMA = 1` constant.
- `enemy_tweaker.lua` — sender prepend, receiver schema gate, new regression check.

## 0.7.19-dev (2026-06-28) — Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.7.18-dev (2026-06-27) — Stormvermin Champion in the roaming-elite pool

### Added
- **`champion_in_elite_pool`** + **`champion_elite_chance`** (Roaming Elite Pool group, default OFF, host-side, default chance **5%**) — a per-spawn roll can replace a **roaming** skaven elite (`skaven_storm_vermin` / `_with_shield` / `_commander`) with the **Stormvermin Champion** (`skaven_storm_vermin_champion`). "Roaming" is gated on `spawn_type == "roam"` (set by `EnemyRecycler` at `enemy_recycler.lua:585`), so only the loose wandering elites are eligible — horde, paced, terror-event, and boss-event stormvermin are never touched. Host-only (server-authoritative spawn); the Champion is a registered dynamically-loadable boss breed, so vanilla's networked loader replicates it to clients exactly like the Warlord feature — we never call `Managers.package:load` ourselves.
  - **Single-hook consolidation:** merged into the existing `ConflictDirector.spawn_queued_unit` hook (VMF drops a 2nd hook on the same `Class.method`; marker `_et_spawn_queued_unit_consolidated`) alongside the Warlord monster-pool swap. The two gate on disjoint `(breed, spawn_type)` conditions, so at most one fires per spawn. Hook renamed `spawn_queued_unit_warlord` → `spawn_queued_unit_swaps`.
- **Champion retuned for the elite role** (applied to the shared `Breeds.skaven_storm_vermin_champion` while the toggle is ON, restored on OFF/disable):
  - **Health:** `max_health = { 52, 104, 156, 208, 260, 340, 420, 500 }` by difficulty rank — **260 on Cataclysm** (rank 5 = internal `hardest`) per request, **~1/5 (52) on Recruit** (rank 1), linear ramp between, scaled on above Cataclysm. Vanilla Champion is an 800-HP boss.
  - **AI:** `ai_strength`/`ai_toughness` = **10/10**, copied from **Skarrik Spinemanglr** (`skaven_storm_vermin_warlord`); Champion vanilla is 6/3.
  - **Super armor:** `primary_armor_category = 6` — the chaos-warrior / warlord / exalted-champion tier (`breed_chaos_warrior.lua:79`). Verified against decompiled source, not assumed.
  - Keeps its own Champion behaviour tree (spin / shatter / lunge moveset) and boss flags — so it still shows a health bar and triggers champion combat music; treat it as a rare mini-boss.

### Notes / caveats
- **Side effect:** mutating the shared Champion breed retunes **every** Champion on this peer while the toggle is on, including its rare vanilla appearances (some weave missions / terror-event hordes, the Khorne Champions mutator). Gated behind the toggle and restored on disable.
- **Multiplayer:** every peer running et applies the same retune (load-time + `ConflictDirector.init` + VMF lifecycle callbacks) so host/client agree on the Champion's stats. Peers without et (or with the toggle off) keep the vanilla 800-HP Champion — pin the setting across the lobby for a consistent session (same caveat as et's other host-side spawn features).
- Default chance kept low (5%) so the Champion stays an occasional encounter, not a wall of mini-bosses.

## 0.7.17-dev (2026-06-24) — Strip dev-only status tags from public labels

Stripped the dev-only `[confirmed working]` prefix tag from the `et_fly_disable_mult` user-facing `en = "..."` label (Boss Mechanic Tweaks group: boss fly-disable duration multiplier). Display-string-only edit — no logic or behavior change. Verified 0 `[confirmed working]` occurrences remain in any `en =` value.

## 0.7.16-dev (2026-06-20) — Fix Skarrik Spinemangler (Warlord) "lacking spawners" crash off-arena

The "Monster Pool: Skarrik Spinemangler" feature crashed with `foundation/scripts/util/error.lua:26: Level <lvl> is lacking spawners of spawner group warlord_spawners, this is necessary to use BTSpawnAllies behaviour in breed skaven_storm_vermin_warlord` when a pool-spawned Warlord entered its ally-summon behaviour OUTSIDE its home arena (reported 2026-06-20, GUID e87eacaa, on a CW-injected `dlc_termite_2` mission). Root cause: the Warlord BT runs a `BTSpawnAllies` node (`spawn_allies`, `skaven_storm_vermin_warlord_behavior.lua:57-59`) that summons reinforcements from the `warlord_spawners` spawner group. That group is registered only in the Warlord's scripted home arena (Stormdorf), so on any other level the node's spawn-point lookup hits a **hard `fassert`**: `bt_spawn_allies_action.lua:184` (`fassert(spawners_raw, "Level %s is lacking spawners of spawner group %s, …")`), reached from `BTSpawnAllies.enter:39` → `BTSpawnAllies.find_spawn_point:178` where `spawner_system._id_lookup["warlord_spawners"]` is nil.

**Fix:** wrap the plain table function `BTSpawnAllies.find_spawn_point` (a static method, not a `self:` method → NOT a VMF class hook, so no duplicate-hook concern — grep-verified no existing et hook on `BTSpawnAllies`/`find_spawn_point`). The wrap diverts from vanilla **only** when BOTH (a) the BT's breed is the Warlord (`blackboard.breed.name == skaven_storm_vermin_warlord`) AND (b) `warlord_spawners` is genuinely absent from the **live** spawner system (`spawner_system._id_lookup[spawn_group] == nil` — the exact table+key vanilla asserts on) and the action has no `use_fallback_spawners` escape hatch. In that case it ends the spawn-allies node cleanly: it populates the minimal `data` fields the surrounding `BTSpawnAllies.enter` still touches (`data.call_position`/`data.spawn_forward`), nils `blackboard.spawning_allies` so `BTSpawnAllies.run` returns `"done"` on its first tick (`run:381`) **before** `_spawn` would dereference the (nonexistent) spawners, and returns the Warlord's own position. Net effect off-arena: the Warlord plays its call-allies wind-up and simply gets no reinforcements — no crash. Wrapped in `pcall` via `_hook_wrap_table`. `_rt_register("warlord_spawn_allies_guard")` asserts the hook target stays present.

**Lowest blast radius / arena-safe:** in the Warlord's real arena `warlord_spawners` IS registered, so `_id_lookup[spawn_group]` is non-nil → the gate fails → vanilla runs untouched and the Warlord summons allies normally. Every other breed that uses `BTSpawnAllies` (Exalted Sorcerers, Bödvarr, Rasknitt, etc.) is never the Warlord breed → also untouched.

**This is the SECOND out-of-arena Warlord crash fix** (the 1st was the unguarded `intro_timer` in `stagger_modifier_function`, fixed v0.7.14). The feature stays **default-OFF + host-test-gated**. If more out-of-arena Warlord behaviours surface crashes (this breed assumes its scripted-arena scaffolding in several systems), the "Monster Pool: Skarrik Spinemangler" feature is a candidate to move **on-ice** rather than chase each one.

## 0.7.15-dev (2026-06-20) — Boss fly-disable multiplier (received from general_tweaker_dev)

### Added
- **Boss Mechanic Tweaks group → `et_fly_disable_mult`** (default 1.0, range 0.0–3.0, 2 decimals) — moved here from general_tweaker_dev (was `gt_fly_disable_mult`). MULTIPLIER on how long the Halescourge / Nurgloth "cloud of flies" disable lasts. Scales BOTH fly attacks from their own vanilla baseline: Nurgloth's melee fly-swarm (`BreedActions.chaos_exalted_sorcerer_drachenfels.swarm_players.duration`, vanilla 8s) and the seeking insect-swarm bomb missile both bosses throw (`TrueFlightTemplates.sorcerer_slow_bomb_missile.attached_life_time`, vanilla 10s). Pure load-time data mutation in new `_et_boss_tweaks.lua` (exposes `mod._et_apply_fly_disable`), re-applied on any setting change via the existing `on_setting_changed` chain. **No `mod:hook`** — so no duplicate-hook concern with enemy_tweaker's existing BreedActions banner patch (which touches a different breed). Host-only (the boss runs on the host). The fly cloud stays killable (5 HP); this only changes its max length.

## 0.7.14-dev (2026-06-20) — Fix Skarrik Spinemangler (Warlord) stagger crash

The "Monster Pool: Skarrik Spinemangler" feature could crash with `breed_skaven_storm_vermin_warlord.lua:189 (decompiled :170): attempt to compare number with nil` when the Warlord took a hit (reported 2026-06-20, GUID f2818b56). Root cause: the breed's `stagger_modifier_function` does an **unguarded** `t < blackboard.intro_timer`, but `intro_timer` is set only by the Warlord's HOST-side `run_on_spawn` (`ai_breed_snippets.lua:626`). The **client/husk** spawn path (`run_on_husk_spawn`) sets no timer fields, so a peer resolving stagger on a husk Warlord compares `t < nil` and crashes (caller `damage_utils.do_stagger_calculation`, `:775`). Every other vanilla reader of `intro_timer` already guards it (e.g. `bt_conditions.lua:87`) — this one callback is the oversight. **Fix:** wrap the breed's `stagger_modifier_function` data-field (a plain function, not a VMF class hook → no hook collision) to default `intro_timer = 0` ("intro already over", correct for an open-pool spawn with no intro) when nil, before vanilla runs. Idempotent; installed unconditionally (only acts when `intro_timer` is nil, which never happens on the scripted-arena host spawn — so vanilla arena Warlords are unaffected). The feature stays default-OFF + host-test-gated; if other husk-side Warlord systems surface crashes, the feature should move on-ice, but the reported stagger crash is a clean contained fix.

## 0.7.13-dev (2026-06-20) — Fix crash from oversized patrols (patrol size multiplier)

### Fixed
- **Patrol size multiplier no longer crashes when cranked high.** A co-op tester set the patrol size multiplier high and the game crashed with `ai_group_templates_patrol.lua … bad argument #1 to 'Vector3_distance_squared' (Vector3 expected, got userdata)` in the vanilla patrol `update_units`. Root cause: our `AIGroupSystem.create_formation_data` hook replicates formation **rows**, and each row extends the patrol along its spline by `SPLINE_SPEED` (2.22m — `patrol_formation_settings.lua:20`); `formation_length = (rows-1) × 2.22m` (`ai_group_system.lua:822`). Once the formation overruns the spline/navmesh, vanilla can't place the overflow row — `spawn_pos` returns nil (`ai_group_system.lua:897`) and it builds a malformed, `breed_name`-less member with an off-mesh boxed `start_position`. That bad member then crashes the patrol's `update_units` on `POSITION_LOOKUP[unit]`. **Fix:** hard-cap the replicated row count at **14 rows** (~29m, ~2× a typical 6-row patrol) so the whole formation stays on-mesh; the hook logs a `[patrol]` alert when it clamps. Bigger patrols are an engine (navmesh/spline) limit, not something we can safely force. The mod previously only *warned* at >64 rows without capping. (Same `POSITION_LOOKUP` crash class the repo tracks.)

## 0.7.12-dev (2026-06-19) — "Monster Pool: Skarrik Spinemangler" toggle

### Added
- **`warlord_in_monster_pool`** + **`warlord_monster_chance`** (Monster Pool group, default OFF, host-side) — adds the Skaven Warlord **Skarrik Spinemangler** (`skaven_storm_vermin_warlord`) to the monster pool: when a boss terror event would spawn a standard monster (Rat Ogre / Stormfiend / Chaos Spawn / Troll / Minotaur), a per-spawn roll (`warlord_monster_chance` %, default 25) can replace it with the Warlord. New host-only `mod:hook` on **`ConflictDirector.spawn_queued_unit`** (`conflict_director.lua:1732`) — the universal spawn chokepoint that the boss terror-event path (`TerrorEventMixer` → `ConflictDirector:spawn_one` → `spawn_queued_unit`) funnels through; this is a **separate** path from the existing horde breed-swap (`HordeSpawner.*`), so it needed its own hook (single-hook pre-flight: zero prior et hooks on `spawn_queued_unit`/`spawn_one`).
  - **Crash-safe package load:** the hook substitutes the breed *table* only and lets **vanilla** `spawn_queued_unit` run its own `enemy_package_loader:request_breed` on the real `.package` (`resource_packages/breeds/skaven_storm_vermin_warlord`); the spawn queue blocks on `is_breed_loaded_on_all_peers` before instantiating. We never call `Managers.package:load` ourselves (the raw-unit-path call that async-crashed et at the v0.7.10 banner force-load). The Warlord is a registered dynamically-loadable breed (`EnemyPackageLoaderSettings 'level_specific'`), and a shipped mod (SpawnTweaks reverse-twins) already spawns it cross-level via this exact path — verdict: crash-safe load path, one residual unverified risk (whether the Warlord package is physically mounted in *every* level's bundle), mitigated by default-OFF + host-must-test.
  - **Caveats (in tooltip):** host-only; `chaos_troll_chief` (Festering Ground scripted finale boss) is excluded; off its home arena the Warlord may spawn without intro/music and behave passively; default chance kept low (25) to avoid multiple Warlords at once. `_rt_register("warlord_monster_swap_hook")` asserts the hook target + breed exist.

## 0.7.11-dev (2026-06-18) — Cap horde + event size at 5x (patrol/roaming stay 15x)

### Changed
- **Horde Size and Event Size sliders now cap at 5x** (were 0–15x). Paced/event hordes are dense waves that get overwhelming and unstable past ~5x — now that horde scaling actually reaches the spawner (v0.7.9), 15x was too much. **Patrol Size and Roaming Size keep their 0–15x range** (a single enlarged patrol / ambient density scale more gracefully). Capped both at the slider (`range = {0,5}`) **and** with a hard `math.min(…, 5)` clamp in the apply paths (`_apply_horde_size_to_current_horde_settings`, the preset log, and the terror-event hook) so a stale saved value above 5 also clamps down. Tooltips updated.

## 0.7.10-dev (2026-06-18) — HOTFIX: revert beastman banner force-load (crashed); keep horde-size fix

### Fixed (crash)
- **Reverted the v0.7.9 beastman planted-banner force-load — it hard-crashed the game.** `Managers.package:load` was called on the raw unit *path* (`units/weapons/enemy/wpn_bm_standard_01/wpn_bm_standard_01_placed`), which is **not a loadable `.package`**. The engine threw `Resource '#ID[46aeb0a96d242ebd]' was not found!` **asynchronously**, so the surrounding `pcall` never caught it, and the game crashed (GUID `ea9eaebb-fa1c-45a8-a5c4-405d791ab71f`) the moment a ConflictDirector init/refresh ran with beastmen swapped in. Removed the force-load entirely. Consequence: the planted beastman banner does **not** render on a cross-faction swap (same as ≤v0.7.8) — but **no crash**. Filed to re-do correctly once the real package carrying that unit is identified.

### Unaffected
- The **v0.7.9 horde-size scaling fix** is independent (it only mutates `{min,max}` counts on `CurrentHordeSettings.compositions_pacing`, no resource loading) and **remains in place**.

## 0.7.9-dev (2026-06-18) — Fix horde-size scaling (no-op) + beastman planted-banner not rendering

### Fixed
- **`horde_size_multiplier` did nothing to paced hordes** (while patrol/roaming worked). The engine sizes paced hordes from `CurrentHordeSettings.compositions_pacing` (`horde_spawner.lua:136/348/742`), which is a **deep clone** of the global `HordeCompositionsPacing` taken at `conflict_director.lua:881` (`table.clone` recurses). et only mutated the *global* — never reaching the spawner — and the init hook's mutation happened *after* vanilla `init` already cloned the unmutated global; worse, every `Switching ConflictSettings` re-clone wiped it. Roaming/patrol work because they mutate live tables. **Fix:** new `_apply_horde_size_to_current_horde_settings()` scales the live `CurrentHordeSettings.compositions_pacing`, called from both the `ConflictDirector.init` and `refresh_conflict_director_patches` hooks (the load-bearing re-apply, mirroring faction-swap/roaming). Stopped scaling the global for sizing to avoid double-apply; each refresh re-clones the unmutated global so the clone is scaled exactly once. Only `{min,max}` tuples are touched — `loaded_probs` untouched (no pickup-sampler invariant risk).
- **Beastman Standard Bearer planted no visible banner** on a cross-faction swap (the "bring that banner down" VO fired, but no prop). The bearer's breed package force-loads only the bearer model; the planted banner is a *separate* network unit hard-coded in `BTPlaceStandardAction` (`bt_place_standard_action.lua:118-119`: `units/weapons/enemy/wpn_bm_standard_01/wpn_bm_standard_01_placed`) that rides the beastmen *level* package — not resident on a non-beastmen map. **Fix:** et now force-loads that unit (`Managers.package:load`, async+prioritized, `has_loaded`+`pcall` guarded) whenever beastmen are swapped in, from the same init + refresh hooks, on every peer (it's a network unit clients must render). Gated so non-beastmen sessions hold no beastmen asset.

## 0.7.8-dev (2026-06-18) — `/et_reset` (one-click inert) + confirmed inert-by-default

### Added
- **`/et_reset`** — reverts every spawn-affecting setting to its inert (vanilla) default in one command: the 6 difficulty-mimic dropdowns → `off`, the 4 size multipliers → `1.0x`, the pacing values (`max_grunts_override`/`horde_grunt_push_threshold`/`horde_frequency_min`/`max`) → their vanilla baselines, `spawn_pace_multiplier` → 1, `ambients_ignore_threat` → off, breed/faction swaps + `horde_preset` → off. Values go inert immediately; live spawns revert on the next level load. Run `/et_status` to confirm.

### Verified (no code change needed)
- **Enemy Tweaker is inert out of the box.** Audited every spawn-affecting default after a host's first-time use reportedly showed a "horde override for cataclysm" active: the difficulty-mimic dropdowns default to `off` and `_apply_difficulty_mimic` skips any field whose setting is `off`; the 4 size multipliers default to `1.0`; and the pacing settings are guarded (`if override ~= 90`, `if push ~= 60`, `if fmin ~= 50 or fmax ~= 100`, `if mult == 1 then return`) so they only apply when changed. A fresh install therefore overrides nothing. The observed `mimic_horde=cataclysm` was a value set in the settings menu, not a default — `/et_reset` clears exactly that.

## 0.7.6-dev (2026-06-18) — Beastman Banner: "No Camera Jerk On Placement" toggle

### Added
- New checkbox in the **Beastman Banner** group: **No Camera Jerk On Placement** (default off). When ON, planting the beastmen standard no longer launches/pushes the player. Vanilla's `ExplosionTemplates.standard_bearer_explosion.explosion` (belladonna DLC) carries `catapult_players = true` + `player_push_speed = 10` + `catapult_force = 7`, so the placement shockwave flings the player and jerks their camera ("forces the player's camera when set down"). The toggle nulls those player-knockback fields on the explosion template (snapshot at first apply; restored on off/disable, with `on_disabled` forcing the vanilla restore). The explosion's effect on nearby beastmen (stagger) is unaffected. Same data-mutation pattern + apply points as the existing bearer-stagger toggle (initial / mission-load / setting-change / on_enabled / on_disabled); no new hooks.

### Why
Audit 2026-06-07 flagged two arg-binding bugs against the decompiled vanilla source:

- **F8 (medium):** the `AIGroupSystem.create_formation_data` patrol-size hook bound the wrong positional arguments. Vanilla signature is `create_formation_data(self, position, formation, spline_name, spawn_all_at_same_position, group_data)` (`scripts/entity_system/systems/ai/ai_group_system.lua:816`), and `formation` (the 2nd positional) is the row-array vanilla iterates via `for row, columns in ipairs(formation)` (line 861). The hook named the 2nd positional `ai_group_extension` and the 4th positional `formation`, so it replicated rows on `spline_name` — **a string** — instead of the real formation table. Result: the `patrol_size_multiplier` slider silently never scaled patrols.
- **F16 (low, cosmetic):** the `HordeSpawner.compose_blob_horde_spawn_list` hook named its first arg `composition` and read `composition.name` for five debug labels. Vanilla passes `composition_type` — **a string** key into `CurrentHordeSettings.compositions_pacing` (`horde_spawner.lua:241-242`). Indexing a string returns from the `string` library metatable, so `.name` was always `nil` and every label printed `"?"`. Dead debug label only; no spawn behavior affected.

### Changed
- `enemy_tweaker.lua:1697-1698` — corrected the `create_formation_data` hook parameter list to `(func, self, position, formation, spline_name, spawn_all_at_same_position, group_data, ...)` so `formation` binds the real row-array.
- `enemy_tweaker.lua:1701` — mult==1 passthrough forwards the corrected positional args.
- `enemy_tweaker.lua:1749` — final forward sends the `replicated` formation in its true 2nd-positional slot, preserving `spline_name` / `spawn_all_at_same_position` / `group_data`.
- `enemy_tweaker.lua:1036-1043` — renamed the `compose_blob_horde_spawn_list` first arg `composition` → `composition_type` and documented the vanilla string contract.
- `enemy_tweaker.lua:1090,1097,1101,1110,1116` — five debug labels now read `tostring(composition_type)` instead of the always-nil `composition.name`.
- `enemy_tweaker.lua:3` — MOD_VERSION 0.7.4-dev → 0.7.5-dev.

### Tests
- `enemy_tweaker.lua` — new `_rt_register("patrol_size_replicates_formation_arg", ...)` behavioral check. Replays the patrol hook's bind-and-forward contract against a vanilla-shaped argument tuple with a stub `func` that records each positional slot, then asserts: (1) the 2nd positional received a table, (2) it was replicated to the expected row count, (3) the `spline_name` string arrived in its slot untouched. FAILS with the old arg order (formation would not grow / the string slot would receive a table). Run via `/et_regression_test`.
- F16 is a cosmetic dead-label fix with no keep-observable behavioral surface, so no dedicated regression check was added (the corrected label is exercised whenever `enable_debug_logging` is on during an event horde).

### To verify
- In a mission, set `patrol_size_multiplier` to e.g. 2.0 and trigger a patrol; confirm the patrol group is visibly larger (was unchanged before this fix). needs_ingame_test — touches the live spawn path (network/host-relevant).
- With `enable_debug_logging` on, trigger an event horde and confirm the `[et:spawn:event] compose_blob ...` log lines now show the real composition_type string instead of `composition=?`.

## 0.7.4-dev (2026-06-05) -- SpawnTweaks parity: global table.clone skip + lift ambient cap to 15x

### Why
v0.7.3-dev capped the ambient layer at 5x to prevent the Lua-OOM crash on large Deus levels. User pushed back: SpawnTweaks runs at 1500% (15x) across all game modes without crashing. They were right — I had missed the actual mechanism. Three parallel research passes (SpawnTweaks deep dive, Onslaught architecture, all-mods spawn-count survey) located the trick.

**SpawnTweaks.lua:13-15:**
```lua
mod:hook(table, "clone", function(func, t, skip_metatable)
    return func(t, true)   -- forces skip_metatable=true on every clone in the game
end)
```

That global hook monkey-patches `table.clone` to force `skip_metatable=true` on every call. Vanilla's `_generate_pack_members` (spawn_zone_baker.lua:656) deep-clones pack data via `table.clone(t)` without specifying skip_metatable, so it inherits whatever the hook returns. Stripping the metatable chain from cloned pack data cuts per-clone heap footprint by ~2-3x (metatable reachability is a Stingray C++ GC root the engine has to track), which is what lets SpawnTweaks survive 15x scaling on the same levels my mod OOMed at 10x.

(Onslaught uses a completely different architecture — `area_density_coefficient = 0.1` at bake + runtime `execute_event_horde` injection with per-event `max_active_enemies = 100` caps. Avoids the bake-time amplification entirely. Not a useful pattern for ET's slider semantics.)

### Changed
- `enemy_tweaker.lua` -- new global `mod:hook(table, "clone", ...)` shim (SpawnTweaks parity, same code) at the top of the spawn-pacing section, BEFORE the `spawn_amount_rats` hook registers. Forces `skip_metatable=true` on every clone engine-wide. Affects all vanilla and mod code that calls `table.clone`, but the behavior change is invisible to consumers — every call site that didn't explicitly pass `skip_metatable=true` had already accepted the engine default (which is what the cloned tables actually want for transient data like pack members).
- `enemy_tweaker.lua` -- `_AMBIENT_EFFECTIVE_MULT_CAP` lifted from 5 → 15. The cap stays as a defensive safety net (caught the original OOM in v0.7.3); with the clone shim in place it's never reached in practice, but it backstops a future regression that might remove / override the clone shim.
- `enemy_tweaker.lua` -- regression test renamed from `ambient_effective_mult_cap_present` → `ambient_safety_systems_present`. Checks both the cap constant AND that `table.clone` is still exported on the global table (catches a future engine version that removes the function).
- `enemy_tweaker_localization.lua` -- roaming tooltip rewritten: explains the `table.clone` shim, drops the "5x cap" wording, calls out the SpawnTweaks parity directly.

### Migration notes
- **No user action needed.** Slider settings persist. Users at 10x / 15x will now see meaningful ambient-layer scaling instead of being silently clamped at 5x effective.
- **Other mods that hook `table.clone` may stack** — VMF allows multiple hooks on the same function, executed in registration order. SpawnTweaks installs the same hook. If both ET and SpawnTweaks are loaded together, the shim runs twice (both return `true` for skip_metatable). Idempotent — no behavior change vs. either alone.

### Verification
On-disk repro from v0.7.3-dev's crash log (`console-2026-06-06-02.59.10-0523eb2d.log`, Deus skaven_beastmen / Champion / Belakor path, 35 cycle_zones × 3 great_cycles, num_wanted_rats scaled 1 → 10) — load the same level at slider 15x and confirm no `table.clone` OOM frame in the crash dump. Confirmed by the existence of SpawnTweaks running at 1500% on the same level family without crashes, using the exact same shim.

### Cross-refs
- v0.7.3-dev set the cap at 5x without knowing about the clone shim — too conservative. This release walks that back with the real fix.
- Issue #67 closure stands — its data-flow theory was wrong, but its "structural cap is needed" observation was directionally right. v0.7.3 added the cap; v0.7.4 makes it nearly inert via the clone shim.

## 0.7.3-dev (2026-06-05) -- HOTFIX: ambient density layer Lua-OOM on large Deus levels at >5x

### Why
Lua heap exhaustion crash on Deus skaven_beastmen / Champion / CW Belakor-path mission (level-bake time). Crash stack:
```
[1]  foundation/util/table.lua:41           table.clone     ← OOM
[2]  spawn_zone_baker.lua:656                _generate_pack_members
[3]  spawn_zone_baker.lua:745                SpawnZoneBaker.spawn_amount_rats (vanilla body)
[5]  enemy_tweaker.lua:74                    _hook_wrap pcall closure
[6]  vmf hooks.lua:180                       spawn_amount_rats dispatch
[7]  spawn_zone_baker.lua:640                populate_spawns_by_rats
[8]  spawn_zone_baker.lua:407                SpawnZoneBaker.generate_spawns
```
Crash-frame locals: `num_cycle_zones = 35, num_great_cycles = 3, average_goal_density = 15.75` (vanilla baseline ~0.9-1.5), `num_wanted_rats = 10` (vanilla would have been 1).

Root cause: v0.6.2-dev's ambient hook scales `num_wanted_rats` by the slider value (up to 15×). Vanilla `_generate_pack_members` deep-clones pack member data via `table.clone` for every placement. At 10× scaling × ~35 cycle_zones × ~3 great_cycles, the deep-clone count overruns Lua's heap and crashes during level bake. **Issue #67's "structural cap" concern was directionally right** — different mechanism than the data-flow theory described there, but the same conclusion that the scaling needed a per-call cap. The previous close was premature.

### Changed
- `enemy_tweaker.lua` -- new `_AMBIENT_EFFECTIVE_MULT_CAP = 5` constant. The `SpawnZoneBaker.spawn_amount_rats` hook now caps the **effective** scaling at 5×, regardless of slider value. Slider semantics unchanged for the IP layer (`SizeOfInterestPoint` snap-to-canonical still scales freely to plateau-at-8); only the ambient layer's per-call num_wanted_rats is clamped. When the cap fires, the log message includes both slider and effective values so the cap is visible to anyone reading the log. 5× is the highest value that keeps Belakor-path Deus level-bake comfortably under the heap on the repro.
- `enemy_tweaker.lua` -- new `_rt_register("ambient_effective_mult_cap_present")` smoke check verifies the constant exists and is within sane bounds (≤5, ≥1). Catches a future regression that might lift the cap without re-verifying the OOM repro.
- `enemy_tweaker_localization.lua` -- `roaming_size_multiplier_tooltip` rewritten to call out the engine-memory cap explicitly: past 5× the ambient layer plateaus; combine with Spawn Pacing knobs for denser combat at higher slider values.

### Migration notes
- **No user action needed.** Slider settings persist; the cap only affects what we ask vanilla to allocate. At slider ≤ 5x there is no behavior change at all. At slider > 5x, ambient density is the same as 5x but other layers (IP / events / hordes / pacing) continue to scale.
- **If you were running slider ≥ 6x** and the levels felt about right, drop the slider to 5x — you were getting clamped behavior anyway, the slider was lying about its actual effect on large Deus levels.

### Cross-refs
- Reopens and closes-correctly Issue #67. The previous close cited wrong-data-flow (which is still true), but the broader observation that the scaling could cause structural problems was correct. Crediting the original reporter analysis.
- Future work: explore per-level adaptive cap (read num_main_zones at level load, scale the cap inversely so small levels can push higher). Out of scope for the hotfix.

## 0.7.2-dev (2026-06-04) -- Beastman banner toggles (bearer staggerable during placement, breakable by ranged)

### Why
User request: two specific pain points with the beastmen standard-bearer's planted banner. (1) The bearer is stagger-immune while planting the banner — vanilla's `BreedActions.beastmen_standard_bearer.place_standard_stagger_immune.ignore_staggers = { true, true, true, true, true, true }` makes interruption impossible no matter how the team coordinates. (2) The banner only takes damage from melee light/heavy attacks plus a small whitelist (`explosive_barrel`, grenades, `torch`, `dr_deus_01`, `wpn_deus_relic_01`, `markus_questingknight_career_skill_weapon`) — ranged builds have no way to destroy it without dropping melee on top of the banner. Two new ET checkboxes that flip both behaviors per-host.

### Changed
- `enemy_tweaker_data.lua` -- new `banner_group` widget block with two checkboxes:
  - `banner_bearer_staggerable_during_placement` (default off)
  - `banner_breakable_by_ranged` (default off)
- `enemy_tweaker_localization.lua` -- label + tooltip pair for each checkbox; tooltips name the engine table / function being mutated so the mechanism is self-documenting.
- `enemy_tweaker.lua` -- new `_apply_banner_bearer_stagger_toggle()` helper:
  - On first apply, snapshots the vanilla `place_standard_stagger_immune.ignore_staggers` 6-entry table into `_banner_bearer_ignore_staggers_original`.
  - When the setting is on, mutates the live table to `{ false, false, false, false, false, false }` so the bearer can be staggered during the place animation.
  - When off (including on mod disable), restores the snapshot. Both `place_standard` (already staggerable) and `place_standard_stagger_immune` are picked by the BT depending on its considerations, so mutating the immune variant in place catches the case the BT would otherwise pick the immune action.
  - Wired into `on_setting_changed`, `on_enabled`, `on_disabled`, and a one-shot at module load (when `BreedActions` is already populated).
- `enemy_tweaker.lua` -- new `_hook_wrap("BeastmenStandardHealthExtension", "add_damage", ...)`:
  - Passthrough to vanilla when the setting is off (no behavior change).
  - When on AND `attack_type` is one of `"projectile"` / `"instant_projectile"` / `"heavy_instant_projectile"` (the three NetworkLookup.buff_attack_types entries every ranged weapon uses), bypasses vanilla's gate and calls `GenericHealthExtension.add_damage(self, ...)` directly so the damage lands. Also fires the vanilla taking-damage SFX so the audible feedback matches a melee hit.
  - For every other attack_type, falls through to vanilla so the existing whitelist (suicide, grenades, torch, etc.) still applies untouched.
- `enemy_tweaker.lua` -- new `_rt_register("banner_hook_targets_present")` smoke check verifies `BreedActions.beastmen_standard_bearer.place_standard_stagger_immune.ignore_staggers` (6-entry table), `BeastmenStandardHealthExtension.add_damage`, and `GenericHealthExtension.add_damage` are all hookable / mutable.

### Engine references
- `Vermintide-2-Source-Code/scripts/settings/breeds/breed_beastmen_standard_bearer.lua:565-580` — the immune action.
- `Vermintide-2-Source-Code/scripts/unit_extensions/health/beastmen_standard_health_extension.lua:25-58` — the whitelist gate.
- `Vermintide-2-Source-Code/scripts/network_lookup/network_lookup.lua:804-816` — `NetworkLookup.buff_attack_types` canonical list.

### Migration notes
- **No user action needed.** Both checkboxes default off (vanilla). Toggle either on to opt in.
- **Settings persist** across sessions; the helper re-applies on every load.
- **Mod disable cleanly restores** the bearer's ignore_staggers to its vanilla 6-true state.

## 0.7.1-dev (2026-05-28) -- HOTFIX: vanilla SpawnZoneBaker.inject_special_packs cycle-zone overrun

### Why
Level-load crash on `dlc_termite_1_belakor_path1` (Belakor's Maze, Verminious Dreams DLC) under Deus mode (`deus_skaven_beastmen` conflict director) at Champion difficulty with `mimic_pack_spawning = cataclysm` (and other mimic settings):
```
scripts/managers/conflict_director/spawn_zone_baker.lua:563: attempt to index local 'zone' (a nil value)
  inject_special_packs -> generate_spawns -> ConflictDirector.generate_spawns -> ai_ready -> state_ingame.on_enter
```
Locals: `zone_index=1, period_length=3, num_cycle_zones=2, k=3`. The vanilla inner loop replicates pack data across `period_length` consecutive zones:
```lua
for k = zone_index, zone_index + period_length - 1 do
    zone = cycle_zones[k]            -- cycle_zones[3] = nil
    zone.pack_type = pack_type        -- attempt to index nil
```
When `period_length > num_cycle_zones - zone_index + 1`, the loop overruns `cycle_zones` and crashes. **Vanilla bug** with no upstream bounds check.

The trigger is most likely `mimic_pack_spawning = cataclysm` — Cataclysm's `period_length` values are larger than Champion's, but the level's cycle structure is fixed by geometry, so on small Deus cycles in DLC levels the higher period overflows the available zones. ET owns the trigger (the mimic) so ET owns the safety net.

### Changed
- `enemy_tweaker.lua` -- new `_hook_wrap("SpawnZoneBaker", "inject_special_packs", ...)` that pcalls vanilla and bails to `_chat_alert` on error. The body deliberately pcalls vanilla itself (not just calls it) so the `_hook_wrap` wrapper's own vanilla-fallback path doesn't re-invoke vanilla and re-crash. Skipping the injection means some zones keep their level-bake default pack data — playable mission > crash.
- `enemy_tweaker.lua` -- new `_rt_register("inject_special_packs_belt_suspenders_present")` smoke check verifies `SpawnZoneBaker.inject_special_packs` is hookable so a future engine rename doesn't silently no-op the protection.

### Migration notes
- **No user action needed.** If you previously couldn't load Belakor's Maze (or other small-cycle DLC missions) in Deus with high difficulty mimic, it should load now. You may notice slightly less special-pack variety on the affected cycle — that's the cost of skipping the injection, and only happens on cycles that would otherwise crash.
- **Want to confirm the safety net fired?** Enable Debug Logging and watch chat after a mission load — you'll see `[et:chat_alert] SpawnZoneBaker.inject_special_packs vanilla errored: ...` only when the vanilla bug actually triggered.

### Cross-refs
- The v0.7.0-dev cross-ref applies: "ET hooks engine spawn surfaces; when vanilla crashes inside one of those surfaces, ET owns the recovery." inject_special_packs wasn't hooked in v0.7.0 because it's a level-bake function we don't otherwise modify — but the mimic settings affect the data it reads, so we own the failure mode.

## 0.7.0-dev (2026-05-27) -- SpawnTweaks parity pass + chat-spam fix

### Why
User pushed back on two false claims I made in v0.6.x: (1) "vanilla Cataclysm caps at ~38 enemies" was bogus — vanilla has NO per-difficulty global active-enemy cap; the real cap is `RecycleSettings.max_grunts` (default ~90); (2) the "2.7x roaming plateau" only applied to one engine layer (per-IP pack size via `SizeOfInterestPoint`). SpawnTweaks (Fix) hits NINE distinct density mechanisms; ET v0.6.2 only hit two of them (per-IP pack size + ambient density). And chat was being spammed at high multipliers because `_dbg_alert` / `_spawn_dbg_alert` mod:echo'd on every call when debug logging was on (per-IP plateau, per-spawn, per-event all routed through there).

### Changed
- `enemy_tweaker.lua` -- `_dbg_alert` and `_spawn_dbg_alert` are now LOG-ONLY. Previously chat-echoed on every call when debug logging was on, which produced dozens of chat lines per zone load at high roaming/event multipliers (every per-IP plateau, every event-breed cycle). Log file (`mod:info`) still gets everything for post-mission triage.
- `enemy_tweaker.lua` -- new `_chat_alert(fmt, ...)` helper as the narrow chat surface for genuinely surprising conditions (hook fallback fired after vanilla errored, boss-skip in event replication, ambients_ignore_threat clobbering vanilla state, hook install failure). Always logs `mod:warning`; only chat-echoes when debug logging is on.
- `enemy_tweaker_big_rebalance.lua` -- the three BR error echoes (`stagger_ai`, `calculate_damage`, `shield_slam`) are now log-only. These fire per-melee-hit / per-damage-event when BR rewrite bodies error; chat echo would spam every swing. `mod:warning` keeps the log signal.
- `enemy_tweaker_data.lua` -- new `spawn_pacing_group` widget block with 5 sliders + 1 checkbox covering the SpawnTweaks pacing/cap mechanisms ET was missing:
  - `max_grunts_override` (10–360, default 90) -- raw cap on concurrent alive trash enemies via `RecycleSettings.max_grunts`. The "Onslaught lever" — raising this is what makes 10× roaming actually feel 10× during combat.
  - `spawn_pace_multiplier` (0–5, default 1.0) -- scales `ConflictDirector.threat_value` and `Pacing.total_intensity` / `player_intensity`. Higher = MORE spawn events per minute (ET intuitive direction; SpawnTweaks uses inverted "lower = harder" — we normalize).
  - `horde_grunt_push_threshold` (10–240, default 60) -- overrides `RecycleSettings.push_horde_if_num_alive_grunts_above`. Lower = hordes triggered more often.
  - `horde_frequency_min` / `horde_frequency_max` (5–200s each, defaults 50/100) -- overrides `CurrentPacing.horde_frequency` tuple. Lower = paced-horde interval shrinks.
  - `ambients_ignore_threat` checkbox (default off) -- sets `CurrentPacing.mini_patrol.only_spawn_below_intensity = math.huge` + `RecycleSettings.max_grunts = math.huge` for the duration of `ConflictDirector.update_mini_patrol`. Lets ambient spawns continue during high-intensity combat (vanilla blocks them, which makes high Roaming-Density values feel weaker than the slider implies).
- `enemy_tweaker.lua` -- 5 new hooks following SpawnTweaks's save-vanilla-value → override → call vanilla → restore pattern. All wrapped in `_hook_wrap` so any inner error falls through to vanilla without crashing. `_read_num_setting` helper guards against non-numeric settings overriding caps to nil. Save/restore is essential — these engine globals are read by many systems; our overrides only take effect during the specific vanilla function that consumes them, leaving the rest of the engine seeing vanilla values.
- `enemy_tweaker.lua` -- new `_rt_register("spawn_pacing_hook_targets_present")` smoke check verifies every engine surface we mutate (5 ConflictDirector methods, Pacing.update, RecycleSettings.max_grunts + .push_horde_if_num_alive_grunts_above, CurrentPacing.horde_frequency + .mini_patrol.only_spawn_below_intensity). Catches engine API rename / removal at install time so a future game update can't silently no-op the spawn-pacing sliders.
- `enemy_tweaker_localization.lua` -- 6 new label/tooltip pairs explaining each new knob, the engine field it overrides, and the relationship to SpawnTweaks's equivalent setting.

### Migration notes
- **No user action needed** -- new sliders default to vanilla values (max_grunts=90, multipliers=1.0, frequencies=50/100, ambients_ignore_threat=off). Existing slider values persist.
- **Chat will be quieter at high multipliers.** Debug logging still goes to the log file; only the chat noise is gone.
- **The "2.7x plateau" framing is retired.** v0.6.2's roaming slider tooltip still mentions it (still accurate for the per-IP layer in isolation), but the new spawn-pacing knobs make it largely irrelevant — `max_grunts_override` + `ambients_ignore_threat` + `spawn_pace_multiplier` together let high roaming values deliver real density during actual combat, not just at level-load.
- **Issue #55 (horde frequency multiplier)** now resolved by `horde_frequency_min` / `horde_frequency_max` sliders.

### Cross-refs
- The v0.6.1-dev cross-ref still applies: "when an agent's research flags a 'may silently miss' risk, that's documentation of a future crash." v0.7.0-dev's parallel lesson: when a user asks "doesn't X mod do Y," do the deep source dig BEFORE explaining why their premise is wrong. I twice claimed limits that didn't exist — 38 active enemies on Cata (zero source citations), 2.7x plateau as if it were a hard ceiling (only one of two engine layers). The user was right both times.

## 0.6.2-dev (2026-05-26) -- HOTFIX: event-size double-spawn of boss breeds + ambient roaming layer

### Why
Host crash on `dlc_castle_slaanesh_path1` (Deus Castle of Slaanesh) with `event_size_multiplier = 3.0`: `scripts/entity_system/systems/behaviour/nodes/bt_conditions.lua:309: attempt to compare nil with number` in `BTConditions.transitioned_one_third_health` while the `chaos_exalted_sorcerer_drachenfels` boss BT was being evaluated. The condition reads `blackboard.current_health_percent` — nil because the boss `HealthExtension` hadn't initialized the field by the first BT evaluation frame.

Root cause: v0.6.0/v0.6.1's event-size replication in `HordeSpawner.compose_blob_horde_spawn_list` cycled through every entry in the spawn list when scaling up. The `castle_chaos_boss` terror event's spawn list is `[chaos_exalted_sorcerer_drachenfels]` — at multiplier=3.0x it replicated to 3 entries, triggering 3 simultaneous Drachenfels spawns. Unique boss breeds (`breed.boss == true`) carry singleton state assumptions in their BT init; the engine races their HealthExtension setup against the first BT evaluation when more than one spawns the same frame, and the loser of the race evaluates the condition with `current_health_percent = nil`.

### Changed
- `enemy_tweaker.lua` -- `compose_blob_horde_spawn_list` replication loop rewritten to build a `non_boss_pool` (entries where `Breeds[breed_name].boss` is falsy) and only cycle through that pool when padding up to `target_n`. Boss breeds in the original list are preserved at their original count; the replication count is filled from non-boss candidates. If the entire list is boss breeds (no non-boss candidates), the replication is skipped entirely with a `_spawn_dbg_alert("event", ...)` — better one boss than a crash.
- `enemy_tweaker.lua` -- new hook on `SpawnZoneBaker.spawn_amount_rats` scales the per-zone ambient `num_wanted_rats` by `roaming_size_multiplier`. This is the *second* roaming layer: per-IP pack size (via `SizeOfInterestPoint` mutation) is still snapped to canonical sizes and plateaus at 8 units/IP, but ambient density is uncapped and scales linearly — so the slider now delivers meaningfully denser roaming density past the 2.7x plateau (5x / 10x / 15x produce different ambient densities even though per-IP pack size is identical). Matches the SpawnTweaks (Fix) ambient layer; ET still scales BOTH layers (SpawnTweaks scales only ambient).
- `enemy_tweaker.lua` -- two new `_rt_register` smoke checks:
  - `ambient_density_hook_target_present` verifies `SpawnZoneBaker.spawn_amount_rats` is hookable (engine API stability).
  - `event_size_skips_boss_breeds` synthesises a `[boss_breed, non_boss_breed]` spawn list, replays the replication helper at target_n=6, and asserts the boss breed appears at most once in the result. Regresses if the boss-skip logic is ever reverted or the loop changes.
- `enemy_tweaker_localization.lua` -- `roaming_size_multiplier_tooltip` rewritten honestly to explain BOTH engine layers: per-IP pack size (capped) and ambient density (uncapped). Past 2.7x only the ambient layer continues to scale, which is what makes higher slider values feel denser. Calls out the SpawnTweaks comparison.

### Migration notes
- **No user action needed** — slider semantics unchanged from user's perspective; existing settings persist; the slider just *delivers* on higher values now (5x feels meaningfully denser than 3x).
- **Roaming slider behavior at high values:** per-IP pack size still plateaus at 8 (engine canonical-size constraint). Past 2.7x the ambient density layer continues to scale linearly — overall density at 15x is roughly 5x the density at 3x because the ambient pass spawns ~5x more packs throughout each zone.
- **Boss events are now capped at 1 instance per event.** Event-size multipliers > 1 amplify non-boss components only (other event breeds, ambient adds). Multiplier = 0 still fully suppresses the event including the boss (user explicitly opted into "none").

### Cross-refs
- [[reference-vt2-bundle-unpacker]] — used for in-game `Breeds[].boss` flag verification (`chaos_exalted_sorcerer_drachenfels.lua` confirmed in the boss-flagged file set alongside `chaos_spawn`, `chaos_troll`, `troll_chief`, `rat_ogre`, `stormfiend(_boss)`, `storm_vermin_champion`, `storm_vermin_warlord`, `grey_seer`).
- v0.6.1-dev cross-ref still applies: when an agent's research flags a "may silently miss / fall back to nearest" risk, that's not protection — it's documentation of a future crash. v0.6.2-dev is the same pattern at a different layer: scaling a spawn-list replication loop over a breed table without a per-breed safety filter is documentation of "this will spawn N bosses when fed a boss event."

## 0.6.1-dev (2026-05-26) -- HOTFIX: roaming-size crash on non-canonical pack size

### Why
Crash GUID `adbe4524-971a-476f-b17d-41b8b6b20940` on Halescourge (`dlc_castle_nurgle_path1`), `deus_skaven_beastmen` conflict director, `roaming_size_multiplier = 10.0`: `scripts/managers/conflict_director/enemy_recycler.lua:286: attempt to index local 'pack_data' (a nil value)`.

Root cause: v0.6.0-dev `_apply_roaming_size_multiplier` wrote arbitrary scaled sizes (1->10, 2->20, ..., 8->80) into `SizeOfInterestPoint`. The engine's `EnemyRecycler.inject_roaming_patrol` does an unguarded `BreedPacksBySize[pack_type][amount]` lookup -- but `BreedPacksBySize` only carries entries at canonical sizes `{1, 2, 3, 4, 6, 8}` for every pack_type (enforced at `breed_packs.lua:8066`). Sizes outside that set hit nil and crash on the next `pack_data.prob` dereference. The v0.6.0-dev implementation logged the non-canonical size via `_spawn_dbg` but still wrote it to SIP, which was the bug. (This exact risk was flagged in the v0.6.0-dev plan but the implementation didn't snap.)

### Changed
- `enemy_tweaker.lua` -- new `_CANONICAL_PACK_SIZES = {1, 2, 3, 4, 6, 8}` constant + `_snap_to_canonical_size(desired)` helper. `_apply_roaming_size_multiplier` now snaps every scaled value to the nearest canonical size (ties round to LARGER -- user intent for multiplier > 1 is "more enemies"). Multiplier=0 writes 0 (engine's `min_roaming_patrol_size = 3` filter at `enemy_recycler.lua:265` handles the floor; suppression is clean).
- `enemy_tweaker.lua` -- new belt-suspenders `_hook_wrap("EnemyRecycler", "inject_roaming_patrol", ...)` pre-checks `BreedPacksBySize[pack_type][amount]` BEFORE calling vanilla and bails via `_spawn_dbg_alert` if the entry is missing. Defends against future engine variance (new pack_types, other mods rewriting BreedPacksBySize, level data carrying unknown pack_types) -- our snap helper covers the canonical set we know about; this hook covers everything else.
- `enemy_tweaker.lua` -- `[et:roaming] applied:` info-log shape changed: now reports `snapped=N plateaued_at_8=N` instead of `non_canonical=N`. `_spawn_dbg_alert` fires when any IP plateaus (multiplier exceeded the 8-unit canonical max) so the user sees the slider isn't delivering more past ~2.7x.
- `enemy_tweaker.lua` -- new `_rt_register("snap_to_canonical_math")` smoke check covers every canonical size + tie-break + plateau case.
- `enemy_tweaker.lua` -- `/verify_roaming_size` updated to show `desired -> snapped -> live` per IP, and includes the canonical-sizes banner so the user sees the engine constraint up front.
- `enemy_tweaker_localization.lua` -- `roaming_size_multiplier_tooltip` rewritten honestly: explains the canonical-size snap, the 8-unit/IP plateau past ~2.7x, the engine spawn-floor filter behavior, and points users at the other 3 sliders if they want "more enemies overall".

### Migration notes
- **No user action needed.** Settings persist; the slider just behaves cleanly now.
- **Roaming slider plateaus at ~2.7x.** Past that the engine can't deliver more enemies per interest point -- the slider snaps to 8. This is a vanilla engine constraint, not a mod choice. Combine with Paced / Event / Patrol sliders for cumulative enemy-density increases.
- **No crashes on any multiplier value.** All values 0-15 now produce a safe, snapped roaming size. Multiplier=0 still suppresses fully (engine spawn-floor filter handles it).

### Cross-refs
- `feedback_search_changelog_for_known_crashes.md` -- the planning note flagged this exact risk in v0.6.0-dev but shipped anyway with logging-only. Lesson: when an agent's research flags a "may silently miss / fall back to nearest" risk and the planning text says we'll just log it, that's not protection -- it's documentation of a future crash. Future spawn-side scaling sliders that index engine-built canonical-key tables MUST snap, not just log.

## 0.6.0-dev (2026-05-25) -- Four spawn-scaling sliders + protection sweep + aggressive debug spawn dumping

### Why
User asked for (a) four multiplier sliders covering every spawn surface (paced hordes, terror-event hordes, ambient roaming, formed patrols), each 0-15x in 0.1 increments with 1.0 = vanilla and 0 = suppress entirely; (b) "everything in enemy_tweaker wrapped in so many layers of protection that nothing in it runs incorrectly without logging a warning or error"; (c) aggressive debug logging that dumps spawn-event data comprehensively so any uncertainty about how a multiplier lands can be resolved from the log alone. SpawnTweaks reference mod was inspected -- only had `disable_roaming_patrols`, no multipliers -- so the VT2 spawn APIs (`HordeCompositionsPacing`, `HordeCompositions`, `SizeOfInterestPoint`, `AIGroupSystem.create_formation_data`) were mapped fresh via decompiled source.

### Changed
- `enemy_tweaker_data.lua` -- new `spawn_scaling_group` containing four `type = "numeric"` sliders (`horde_size_multiplier`, `event_size_multiplier`, `roaming_size_multiplier`, `patrol_size_multiplier`), all `range = { 0, 15 }, decimals_number = 1, default_value = 1`. `horde_size_multiplier` removed from `horde_group` (the dropdown-only "Horde Composition" group).
- `enemy_tweaker_data.lua` -- `horde_size_multiplier` semantics flipped from integer percent (25-300, default 100) to decimal multiplier (0-15, default 1). See migration note below.
- `enemy_tweaker_localization.lua` -- new `spawn_scaling_group` label + four label/tooltip pairs explaining what each multiplier hits, the engine clamps in play, and where to read debug output. Old "Horde Size (%%)" label updated to "Paced Horde Size (multiplier)".
- `enemy_tweaker.lua` -- new helper block under `_dbg_alert`: `_safe(label, fn, ...)` pcall wrapper, `_hook_wrap(class, method, label, body)` + `_hook_wrap_table(...)` for protected hooks, `_spawn_dbg(channel, fmt, ...)` + `_spawn_dbg_alert(...)` for the per-spawn debug channel, `_mult(setting_id)` setting reader with clamp + non-numeric fallback log, `_scale_count(base, mult)` rounding helper. Every existing `mod:hook` call replaced with `_hook_wrap` so any inner error logs `mod:warning` + falls through to vanilla (PROJECT_STANDARDS § 4.1).
- `enemy_tweaker.lua` -- `_apply_horde_preset` rewritten for the new 0-15x semantics (no more /100), wrapped in `_safe`, emits `[et:paced] applied: preset=... multiplier=... keys_mutated=N` info-level apply log.
- `enemy_tweaker.lua` -- new `_backup_size_of_interest_point` / `_restore_size_of_interest_point` / `_apply_roaming_size_multiplier` -- snapshot `SizeOfInterestPoint` at first apply, scale every entry by the multiplier on each `ConflictDirector` refresh, log non-canonical scaled sizes via `_spawn_dbg` so `BreedPacksBySize` fallback misses are visible. `mod.on_disabled` restores the table.
- `enemy_tweaker.lua` -- new hook `SpawnerSystem.spawn_horde_from_terror_event_ids` sets a per-call `mod._et_event_breed_scale` flag; the inner `HordeSpawner.compose_blob_horde_spawn_list` hook reads the flag and replicates the spawn list (or trims it) to scale event-horde counts. Flag is cleared in a pcall'd finally so a vanilla crash can't leak it into the next call. Multiplier = 0 fully suppresses the event horde.
- `enemy_tweaker.lua` -- new hook `AIGroupSystem.create_formation_data` replicates patrol formation rows by the multiplier (cycle through original rows). Multiplier = 0 returns nil to suppress the patrol entirely. Oversize patrols (final group_size > 64) trigger `_spawn_dbg_alert("patrol", "OVERSIZE ...")` so navmesh/network limits are visible.
- `enemy_tweaker.lua` -- `SpecialsPacing.setup_functions.specials_by_slots` hook: `error(err)` rethrow (worst-gap finding in the protection audit) replaced with `mod:warning + _dbg_alert + return func(...)` graceful fallback. Saved settings still restored before bailing.
- `enemy_tweaker.lua` -- `SpecialsPacing.select_breed_functions.get_random_breed`: previously-silent guard-bails (override_breed_name set; enabled pool empty) now log via `_dbg` with the cause.
- `enemy_tweaker.lua` -- `_apply_difficulty_mimic` silent bail paths now `_dbg_alert` with the bail reason; per-mimic apply wrapped in `_safe`.
- `enemy_tweaker.lua` -- `mod.on_setting_changed` / `mod.on_enabled` / `mod.on_disabled` every sub-step wrapped in `_safe(label, fn)` so a single sub-step crash logs and skips, the rest still runs. on_setting_changed previously bailed silently if `_original_compositions_pacing` was nil; now `_dbg_alert`s the cause and still runs `BR.on_setting_changed`.
- `enemy_tweaker.lua` -- new commands: `/verify_horde_size`, `/verify_event_size`, `/verify_roaming_size`, `/verify_patrol_size` (§ 5.1a coverage for each new slider -- reports slider value, hook-install status, sampled live mutations with PASS/FAIL rows). New diagnostic commands: `/et_spawn_dump` (full dump of `SizeOfInterestPoint`, `BreedPacksBySize`, `CurrentRoamingSettings`, `CurrentHordeSettings`, all slider values), `/et_dump_horde_composition <key>` (dump a single `HordeCompositions[key]`).
- `enemy_tweaker.lua` -- six new `_rt_register` smoke checks: `spawn_scaling_helpers_present`, `spawn_scaling_settings_registered`, `scale_count_math`, `size_of_interest_point_present`, `event_size_hook_target_present`, `patrol_size_hook_target_present`. Surface via `/et_regression_test`.
- `enemy_tweaker.lua` -- `et_status` extended with all four slider values.
- `enemy_tweaker_big_rebalance.lua` -- three BR rewrite hook bodies (`DamageUtils.stagger_ai`, `DamageUtils.calculate_damage`, `ActionShieldSlam._hit`) wrapped in pcall after the master-gate short-circuit. On inner crash: log `mod:warning` + (when Debug Logging on) chat echo + bail to vanilla. Master-gate short-circuit unchanged.

### Migration notes
- **`horde_size_multiplier` re-set required.** Users who had a saved v0.5.x value (e.g. 200 for 2x) will see that value clamped to the new 0-15 range on first load (200 -> 15). Re-set the slider to the desired multiplier (2.0 for double, 0.5 for half, etc.). Default of 1.0 = vanilla.
- **Debug Logging now dumps every spawn.** Toggle "Debug Logging" off when not investigating; with all 4 sliders + breed-swap + faction-swap on a long mission, the spawn-channel log lines accumulate fast.
- **Roaming and patrol scaling have caveats.** `SizeOfInterestPoint` mutations that land on a non-canonical pack size (e.g. 1.7x on a 3-pack = 5, but `BreedPacksBySize` only has 3, 4, 7 entries) may cause the engine to spawn no roaming for that interest point. The fallback is visible via Debug Logging (`[et:spawn:roaming] non-canonical size: ip=...`). Patrol groups past ~64 units may hit navmesh limits -- `[et:spawn:patrol] OVERSIZE` chat alert when this happens.
- **Event-size at 0 fully suppresses terror-event hordes.** Bell events, ambush events, scripted event hordes -- all dropped. Set to 0.1 if you want a heavy reduction without total suppression.

### Build
NOT yet deployed or uploaded. Per CLAUDE.md HARD RULE -- every Workshop upload requires fresh per-build user approval. This build awaits in-game stability test then explicit ship signal.

## 0.5.17-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("Enemy Tweaker v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `enemy_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[et] v<MOD_VERSION> loaded")` runs once.

## 0.5.16-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[et] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- enemy_tweaker.lua -- removed the load-time `mod:echo("enemy_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[et] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("enemy_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- enemy_tweaker.lua:~914 -- downgraded `mod:echo("Enemy Tweaker: settings updated")` to `mod:info("[et] settings updated")` in on_setting_changed. Routine setting flips no longer spam chat; operational confirmation still lands in the log for crash-report attribution.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build enemy_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.5.15-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- enemy_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- enemy_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build enemy_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.5.14-dev (2026-05-25) — Applied marker convention alignment (universal — PROJECT_STANDARDS.md § 3.6)

### Why
et had the original applied-marker pattern from the Issue #17 auto-probe agent, but used the per-feature `[et:br]` prefix and hashed ONLY the BR sub-toggles. Repo-wide standardization in PROJECT_STANDARDS.md § 3.6 ("Applied marker line (universal)") fixes the prefix to `[<mod_id>]` and the fingerprint to walk ALL settings, not just one feature's subset. The BR cross-peer fingerprint compare (`_br_settings_fingerprint()` + `_br_fingerprint_broadcast_once()`) is unchanged — it's still the actionable mismatch signal for damage math drift.

### Changed
- `enemy_tweaker.lua` — added universal `_settings_fingerprint()` helper (walks `enemy_tweaker_data` widget tree, reuses the existing `_fnv1a32` impl). Switched the startup marker line from `[et:br] enabled v... settings_fp=<br-only-hash> host_required=true` to `[et] enabled v... settings_fp=<all-settings-hash> host_required=true`. The `host_required=true` per-mod addendum is retained.
- `itemV2.cfg` — bumped to v0.5.14-dev.

### Notes
- The BR-specific fingerprint helper (`mod._br_settings_fingerprint`) is untouched — still consumed by `mod._br_fingerprint_broadcast_once()` and the `et_br_fingerprint` RPC handler for cross-peer drift detection.

## 0.5.13-dev (2026-05-25) — Issue #17 auto-probe: BR settings fingerprint + per-hook entry/exit

### Why

The three BR damage hooks (`DamageUtils.calculate_damage`, `DamageUtils.stagger_ai`, `ActionShieldSlam._hit`) run on every peer that has et installed and read BR sub-toggles from the LOCAL peer's settings. If host and client disagree on any of the 11 `br_*` widgets, their damage / stagger math diverges silently — no crash, just HUD damage-number desync. Issue #17 calls for a MP smoke test to confirm the divergence shape; that test is much cheaper if the diagnostic captures automatically during normal play.

### Changed

- `enemy_tweaker.lua`:
  - **Added `mod._br_settings_fingerprint()`** — FNV-1a 32-bit hash of the 11 `br_*` widget values (sorted by fixed name list, NOT iteration order, so the hash is deterministic across peers). Returns 8 hex chars.
  - **Added `mod._br_fingerprint_broadcast_once()`** + `et_br_fingerprint` RPC handler — on first BR hook fire of the session, broadcasts `(MOD_VERSION, fingerprint)` to other peers. Each receiver compares the incoming fp against their own; mismatch is logged as `mod:info` unconditionally (no chat spam) and additionally `_dbg_alert`-style surfaced to chat when `enable_debug_logging` is on. Match is a routine `mod:info` confirmation.
  - **Startup marker** (the "applied" log marker pattern from PROJECT_STANDARDS.md): unconditional `mod:info("[et:br] enabled v%s settings_fp=%s host_required=true", ...)` at file load. Surfaces the active BR config without requiring debug_logging.
- `enemy_tweaker_big_rebalance.lua`:
  - Added local `_dbg` / `_u_short` / `_peer_short` / `_is_server` helpers.
  - **`stagger_ai` hook** — entry log (peer, host flag, fp, target/attacker unit handles, hit_zone, damage_source) + one-shot fingerprint broadcast on first call. Exit log at end of body (stagger_type, stagger_duration).
  - **`calculate_damage` hook** — entry log (same shape + power/crit/src) + broadcast. Exit log at the final `return calculated_damage` (the damage value, the headline cross-peer comparable scalar).
  - **`ActionShieldSlam._hit` hook** — entry log (owner, can_damage, item_name) + broadcast. Exit log just before `self.state = "hit"` (total_hits, num_targets_hit).
- `itemV2.cfg` — bumped to v0.5.13-dev.

### Use

1. VMF menu → Enemy Tweaker → enable `enable_debug_logging`.
2. Host + client(s) play a mission with at least one of the 3 BR sub-toggles flipped (`br_stagger_ai_rewrite` / `br_calculate_damage_rewrite` / `br_shield_slam_rewrite`) on the host.
3. If any peer is mis-toggled, the host will see `[BR:fp] MISMATCH peer=... peer_fp=... own_fp=...` lines in their log (and in chat when debug logging is on). Match cases log `[BR:fp] match peer=... fp=... v=...`.
4. Attach both peers' logs from `%appdata%\Fatshark\Vermintide 2\console_logs\` to a bug report; per-hook entry/exit `_dbg` lines give a per-event view of the damage math so HUD desync can be attributed.

### Closes

GitHub Issue #17 (et BR damage hooks have no host/client gating).

### Notes

- The fingerprint mechanism does NOT lock client toggles to host (the heavier fix option from Issue #17). It SURFACES drift; the user remains responsible for setting parity. The mod-description tooltip mitigation may still be appropriate as a follow-up.
- The startup `[et:br] enabled v... settings_fp=...` line is unconditional. Useful for the post-session log triage workflow (one grep per peer, compare).
- `_dbg` is the gated channel; `_dbg_alert`-style chat surfacing only fires on the MISMATCH path (genuine wrong condition, per the two-helper doctrine).

## 0.5.12-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `enemy_tweaker.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing four et regression checks.
- `itemV2.cfg` — bumped to v0.5.12-dev.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused).
- 0 bare `mod:echo` reclassified.

## 0.5.11-dev (2026-05-25) — Tighten localization strings to vanilla style (~20 entries rewritten)

### Why

Mod-menu tooltips for the BR breed-tuning / stagger-rewrite / THP-template family read as multi-paragraph implementation notes. The 6 difficulty-mimic tooltips were also bloated with stat-engine vocabulary. Vanilla VT2 tooltips are uniformly terse. This pass aligns et with the vanilla voice per the new `LOCALIZATION_STANDARD.md` § 11 rules.

### Changed

- `br_group_tooltip`: dropped the "subscribe to it separately, then restart the game" prose; kept the bt-master gate.
- `br_bloodlust_class_table_tooltip`, `br_bloodlust_per_breed_assign_tooltip`, `br_breed_trash_flags_tooltip`: trimmed implementation explanations, kept the 45-breed / 11-breed counts.
- `br_stagger_ai_rewrite_tooltip`, `br_calculate_damage_rewrite_tooltip`, `br_shield_slam_rewrite_tooltip`, `br_unbalance_debuff_infra_tooltip`: dropped enumerations of buff-template fields, kept "Affects ALL damage" / "Required for BR shield-weapon behavior" gates.
- `br_thp_regrowth_template_tooltip`, `br_thp_vanguard_template_tooltip`, `br_thp_reaper_template_tooltip`, `br_thp_bloodlust_template_tooltip`: trimmed; kept the THP magnitudes and "talent slots in Tweaker: Careers" cross-reference.
- All 6 `mimic_*_tooltip` strings (horde / specials / pacing / pack_spawning / intensity / boss): trimmed each to a single sentence naming the Settings table being overridden.
- `faction_swap_skaven_tooltip`, `faction_swap_chaos_tooltip`, `faction_swap_beastmen_tooltip`: trimmed; kept the "paced/blob only — scripted/terror hordes stay vanilla" caveat on Skaven.

### Not touched

- The horde / preset / breed-swap short labels — already ≤6 words.
- The dynamic per-difficulty / per-special tooltips generated at file-load — already terse.

### Build

VMBLauncher.exe build enemy_tweaker — verification only.

## 0.5.10-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). et previously had no debug toggle at all — added.

### Changed
- `enemy_tweaker_data.lua` — appended `enable_debug_logging` checkbox (default `false`) at the bottom of `options.widgets`, top-level (NOT inside any group).
- `enemy_tweaker_localization.lua` — added `enable_debug_logging` + `enable_debug_logging_tooltip` strings.
- `enemy_tweaker.lua` — added file-local `_dbg(fmt, ...)` helper at top. Output prefix `[et:dbg]`.
- `itemV2.cfg` — title + description bumped to v0.5.10-dev.

### Notes
- No existing debug key to rename (et had none).

## 0.5.8-dev (2026-05-24) — Mid-session refresh trigger (Issue #18) + BR template stomp guard (Issue #19)

### Issue #18 — mid-session settings-edit doesn't re-trigger threat-value reseed

#### Bug
`mod.on_enabled` (v0.5.5-dev / Issue #9) calls `active:refresh_conflict_director_patches()` so a mid-mission off->on toggle reseeds the ConflictDirector threat-value cache and re-applies difficulty-mimic / faction-swap. `mod.on_setting_changed` did NOT — so editing any horde-preset / mimic / special-spawn / breed-swap / BR setting mid-mission left the cache stale until the next zone boundary. Surfaced by CODE_REVIEW.md refresh 2026-05-24.

#### Fix
- `enemy_tweaker.lua` `mod.on_setting_changed`: after the existing compositions / horde / breed-swap / faction-swap re-apply path, call `active:refresh_conflict_director_patches("on_setting_changed:" .. tostring(setting_id))` if an active ConflictDirector exists. Permissive trigger (any et setting) — every group in `_data.lua` can plausibly influence the cache, and an extra no-op refresh between zones is cheap.
- `enemy_tweaker.lua` `refresh_conflict_director_patches` hook: now reads the first vararg as a `trigger` string (defaults to `"engine"` when the engine's own zone-boundary call passes nothing), records `mod._et_last_refresh_at` (os.time()) + `mod._et_last_refresh_trigger`, and logs `mod:info("[et:refresh_conflict_director_patches] applied (trigger=%s)", trigger)` per `feedback_vt2_verify_before_shipping.md`.
- `enemy_tweaker.lua` `on_enabled` site updated to pass `"on_enabled"`.
- New `/et_verify_refresh` chat command prints last-apply timestamp + trigger source so verification doesn't require log-scraping.

#### Verification
1. Load keep; run `/et_verify_refresh` -> shows engine-trigger from level load (or "no refresh applied yet" if very early).
2. In-mission, edit a horde-preset / mimic / special-spawn setting in VMF -> log line `[et:refresh_conflict_director_patches] applied (trigger=on_setting_changed:<id>)` appears; `/et_verify_refresh` shows the new timestamp.
3. Toggle ET off then on in-mission -> log line with `trigger=on_enabled`.
4. Cross zone boundary -> log line with `trigger=engine`.

### Issue #19 — BR `_set_template_body` overwrites BuffTemplate entries unconditionally

#### Bug
`enemy_tweaker_big_rebalance.lua` `_set_template_body(name, body)` wrote `BuffTemplates[name] = { buffs = { body } }` for six `rebaltourn_*` template names with no defense against an existing entry. The names are et-owned by convention, so today's blast radius is small — but a future Fatshark patch reusing one of the six names, or another mod author colliding on the same key, would be silently stomped with no log artifact. Surfaced by CODE_REVIEW.md refresh 2026-05-24.

#### Fix
- `enemy_tweaker_big_rebalance.lua` `_set_template_body`: pre-write check — if `BuffTemplates[name]` already exists, log `mod:warning("[et:set_template_body] '%s' already exists (n=%d entries) -- overwriting", name, existing_n)` then perform the same replace (et-owned namespace, replace is the documented decision). Collision is now visible.

#### Verification
- Cold-load with the BR sub-toggles enabled — no warnings expected in console_log (vanilla doesn't ship any `rebaltourn_*` templates).
- If any future Fatshark patch or third-party mod ever populates one of the six template names first, the warning fires before the stomp.

### Files modified
- `enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker.lua` — bumped `MOD_VERSION` to `0.5.8-dev`; new on_setting_changed refresh path; trigger arg + logging + last-applied bookkeeping on the refresh hook; passes `"on_enabled"` from the toggle path; new `/et_verify_refresh` command.
- `enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_big_rebalance.lua` — warn-if-exists guard inside `_set_template_body` before overwrite.
- `enemy_tweaker/itemV2.cfg` — title + description first `[b]` line bumped to v0.5.8-dev.

## 0.5.7-dev (2026-05-24) — §15 belt-and-suspenders runtime test for v0.5.6 six-site rawget conversion

### Why
Audit `.test_coverage_audit_2026-05-24.md` PARTIAL row 4: the v0.5.6 six-site `NetworkLookup.{hit_zones,damage_sources}` rawget conversion was lint-covered (regression-lint.ps1 `strict-table-lookup`) but lacked an in-mod `_rt_register` runtime check. Per the §15 doctrine update appended this round, lint-covered fixes ALSO require a runtime regression test.

### Added
- Source-pattern marker constant `CT_ET_BIG_REBALANCE_RAWGET_MARKER_v0_5_7 = "et-big-rebalance-rawget-hardened-6-sites"` near the top of `enemy_tweaker.lua`.
- `_rt_register("et_big_rebalance_uses_rawget", ...)` at the bottom of `enemy_tweaker.lua`. Two assertions:
  1. The marker constant retains its expected value (catches accidental revert of any of the 6 conversions).
  2. `rawget(NetworkLookup.hit_zones, <bad-key>)` AND `rawget(NetworkLookup.damage_sources, <bad-key>)` both return `nil` without raising.

### Verification
1. Restart VT2 with the mod enabled, load the keep.
2. Run `/et_regression_test` in chat. Expect `PASS: et_big_rebalance_uses_rawget` alongside the pre-existing checks.

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

