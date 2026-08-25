# Regression Checklist — enemy_tweaker

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to enemy_tweaker.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

Last updated: 2026-08-25.

---
## Personal difficulty combat handicap (#61)

| Field | Detail |
|---|---|
| Authority | Client sends only its preset; host keys by authenticated `sender_peer_id` and applies damage. Wrong schema or non-host receiver is inert. |
| Scope | Direct hostile-AI incoming/outgoing damage only. Friendly fire, environment/self damage, bots, pets, healing, spawns, AI, and enemy health remain vanilla. |
| Bounds | Auto or target <= host is 1.0x/1.0x; one rank is 1.08x incoming/0.95x outgoing; two or more ranks cap at 1.25x/0.85x. |
| Unit lifetime | Before owner or breed lookup, nil/deleted units fail the `Unit.alive` gate. A lingering area effect with no living hostile source preserves vanilla damage; a neutral factor does not inspect attacker units. |
| Offline | `test_et_personal_handicap` covers policy bounds, damage math, authenticated RPC/static authority, nil/live/deleted unit boundaries, lingering Globadier source behavior, settings, and no lookup/buff registration. |
| Runtime | `/et_regression_test`: `issue61_personal_handicap_authoritative` and `issue640_personal_handicap_unit_lifetime` pass. |
| Lifecycle | `verify-fix-coop` only. Host Champion, client Cataclysm; verify both damage directions, then Auto, friendly fire, barrel/fall, bot, and pet controls. |

---
## Boss balance behaviors (#450)

| Field | Detail |
|---|---|
| Symptom | The data controls and grudge marks existed, but Halescourge's half-health add, Skarrik's ranged resistance, and Deathrattler's tracking penalty did not. |
| Root cause | No threshold monitor, exact ranged-damage branch, or Stormfiend-boss tracking adapter existed. |
| Expected | Host Adventure `ground_zero`, Cataclysm+, living arena Halescourge at or below 50% queues one Troll/Spawn. Skarrik takes 70% ranged damage and unchanged melee damage. Deathrattler tracks ratling targets at half rate and for half his dual-intro window; ordinary Stormfiends remain vanilla. |
| Safety | Halescourge shares existing post-spawn/update owners and the package-aware queue. Skarrik composes the existing singleton damage hook with exact breed/ranged gates. Deathrattler owns one exact method hook plus a reversible data snapshot. All controls default off. |
| Offline | `test_et_boss_behavior` covers threshold gates, catalogue, exact 0.70/0.50 policies, owner composition, setting wiring, and pool-substitution exemption. |
| Runtime | `/verify_boss_balance` reports boss data, Deathrattler's live rotation window, and Halescourge observer state. `[et:450] ... queued` appears once; failures are reason-deduplicated and retried at most twice per second. |
| Lifecycle | After integration/deployment, `verify-fix` (solo): Cata Halescourge success plus Legend/disabled controls; compare ranged/melee hits on Skarrik; strafe across Deathrattler's sustained fire and confirm ordinary Stormfiend control. |

---
## Boss idea portability audit (#451)

| Field | Detail |
|---|---|
| Safety boundary | Never put `skaven_stormfiend_boss`, `skaven_grey_seer`, `chaos_exalted_sorcerer`, or `chaos_troll_chief` directly into the ordinary monster pool. Their vanilla action sets are arena-coupled. |
| Automatic diagnostic | On mod load, exactly seven log-only `[et:451]` lines report breed/model, actions, behavior, inventory, wire, residency, and arena-risk state. |
| Optional mission census | Run `/et_boss_idea_audit` once in a representative mission. Compare boot/mission `model_resident`; the command adds only one chat summary and never spawns a boss. |
| Offline | `test_et_boss_ideas` covers catalog bounds, complete structure, package residency separation, and absent-global failure. |
| Runtime check | `/et_regression_test`: `issue451_boss_ideas_safely_decomposed` reports PASS with six complete source contracts and four arena-risk markers detected. |
| Lifecycle | The six-candidate census remains `diagnostics-armed`. The separate greataxe Chosen prototype uses `/et_spawn_chosen`; custom-breed registration safety is owned by #1413 and peer parity remains #371. |

---

## Atomic custom-breed registration (#1413)

| Field | Detail |
|---|---|
| Owners | `_et_custom_breed_registrar.lua` is the only registration mechanism. Warlord and Chosen modules contribute declarative policy/specs and preserve their existing spawn gates, commands, and combat diagnostics. |
| Planning | Breed/actions, detached callback views, six statistics families, already-live performance state, package aliases, dismemberment, faction/elite membership, hit zones, presentation, and all three wire identities are completed off-table. `breeds`, `damage_sources`, and `statistics_path_names` run through `_lib_network_lookup` shadows. |
| Capacity | A new damage-source index must fit `NetworkConstants.damage_source_id.max` or guarded `Network.type_info("damage_source_id").max`; a new statistics-path index must fit `Network.type_info("statistics_path_lookup").max`. Missing authority fails allocation closed. An exact same-name statistics segment is reusable global identity, and exact existing rows revalidate, without a capacity read. |
| Commit | Threat seed first; reversible raw-table writes second; readiness remains rollback-covered; `Breeds[name]` is the final raw write. Reverse alias arrays are replaced from copies rather than edited in place. |
| Opaque exception | `threat_values` is a hidden upvalue with no getter. A throwing setter produces a terminal `threat_state_indeterminate`, leaves structural state unpublished, and is not blindly retried. No production `debug.getupvalue` dependency. |
| Reload | The schema-3 marker pins detached cycle/topology-safe breed/actions content, the donor declaration/duration graph, live identities, canonical threat/elite, all three numeric wire IDs, original dismemberment, and hit-zone identity/content. Only source-declared outputs written by `SET_BREED_DIFFICULTY` may vary. One detached expected graph preserves the current engine-baked source outputs' cycles, sharing, and separation; live actions must match it and remain disjoint from source/declarations. Donor declaration topology is pinned separately because Foundation cloning may split one shared donor declaration. Declarations, durations, custom topology, and other fields stay pinned. Performance alone is dynamic and must remain a finite nonnegative integer. Persistent drift fails before threat or readiness; only ephemeral presentation/readiness rows may republish. |
| Presentation | Every table-valued declared presentation is copied into a graph disjoint from every declaration and every other selected presentation row. Detached authorities require primitive keys and nil metatables. Reload rejects in-place content mutation and root/nested/cross-row re-aliasing before any live write. |
| Offline | `test_et_custom_breed_registrar` drives the real Warlord/Chosen specs through pre-bake registration and fresh registrar reloads after two engine-style difficulty passes; validates faithful Foundation no-seen clone behavior for the real three-action Chosen declaration topology, donor sharing/splitting drift, mutable table-key/metatable rejection, hot-join statistics path encode/decode, all three strict axes, both capacity boundaries, table-presentation graph separation, coherent breed/action/threat/elite/wire/dismemberment/hit-zone/marker tamper, topology drift, false/non-table residue, callback isolation, every planner failure, every raw-write rollback including false prior shapes, and opaque-setter terminal behavior. `test_shared_network_lookup` pins helper ownership/load order and byte identity. |
| Integration | Source review is not a release. The serialized publisher must regenerate the exact root bundle and current receipt from the reviewed commit before build/deploy/publication evidence is claimed. |
| Scope | #371 peer parity, #324 Warlord combat behavior, and #451 boss classification remain separate. |

---
## Premium-skin special variants (#452)

| Field | Detail |
|---|---|
| Safety boundary | The five Versus appearances are full player cosmetic attachments, not AI `base_unit` replacements. Diagnostics must not spawn/link them or mutate ordinary breeds. |
| Automatic structure audit | Exactly six boot `[et:452]` rows cover breed/actions, behavior tree, inventory, network lookup, item/cosmetic, package residency, and attachment owner/source-node count. |
| Natural-spawn audit | The existing `_post_spawn_unit` hook calls a read-only observer. Each target ordinary special logs once per session, with all owner/source nodes counted and at most eight missing names sampled; five rows maximum. |
| Offline | `test_et_special_variants` covers five-candidate uniqueness, structure readiness, behavior/inventory/wire/node failure, owner-node de-duplication, and absence of spawn/network mutation. |
| Runtime | `/et_regression_test`: `issue452_special_variant_assets_classified` and `issue452_live_probe_bounded` pass. Normal play should eventually report `compatible=true` for encountered targets. |
| Lifecycle | `diagnostics-armed` (solo). Do not move to a gameplay fix until owner-node compatibility is known; any rendered appearance or replacement then requires `verify-fix-coop`. |

---
## Enemy special modifiers (#453)

| Field | Detail |
|---|---|
| Catalog | 13 standard BossGrudgeMarks plus Geheimnisnacht Repulse (`shockwave`) and Devious Delvings Berserk (`termite_base`). |
| Structure audit | `/et_modifier_audit` checks root enhancement/buff/wire identity, recursively follows at most 32 `buff_to_add*` templates, and resolves every named buff callback. |
| Natural-spawn audit | The singleton `_post_spawn_unit` hook samples two distinct breeds per requested category (eight rows maximum). Rows report required extensions/state, vanilla breed bans, existing enhancements, and eligible/rejected modifier counts without applying anything. |
| Offline | `test_et_enemy_modifiers` covers catalog, wire/enhancement drift, child/function chains, category precedence, capability rejection, breed bans, and hook ownership. |
| Runtime | `/et_regression_test`: `issue453_modifier_catalog_wire_ready` and `issue453_live_prerequisite_probe_bounded` pass. Capture representative `[et:453] live` rows. |
| Lifecycle | `diagnostics-armed` (solo). Actual modifier application changes combat and replication and must move to `verify-fix-coop`. |

---
## Per-difficulty enemy health multiplier (#369)

| Field | Detail |
|---|---|
| Scope | Hostile AI only, including specials, monsters, and lords; excludes heroes, critters, and friendly necromancer skeletons. |
| Bounds/default | Every difficulty exposes 0.1x-5.0x with 1.0x as vanilla. Runtime sanitization repeats those bounds. |
| Spawn path | Host wraps `GenericHealthExtension.init` and scales its final `extension_init_data.health`; never mutates shared `Breeds.max_health`. |
| Live apply | A queued settings transaction rescales tracked living enemies once, preserving damage percentage and using vanilla max-health/damage replication. |
| Offline | `test_et_health_multiplier` passes boundary, target-policy, percentage, and single-hook wiring checks. |
| In-game | `[verify-fix-coop]` Host at 0.5x and 2.0x; verify a regular enemy and monster on both peers, then move the slider while one is damaged and confirm its health percentage is unchanged. |

---
## ConflictDirector tick fault containment (#479)

| Field | Value |
|---|---|
| Symptom | `terror_event_mixer.lua:1800` repeats every frame; latest log recorded 1,173 skipped ticks in 17.46 seconds and two ET records per failure. |
| Cause | Post-processing left the first processed element nil; `start_event` threw before `EnemyRecycler.update_main_path_events` advanced the current event id, so the same patrol event retried forever. |
| Fix | Log one bounded fault episode; for this exact error remove the partial active event, perform vanilla's missed index advance, and quarantine only ET pacing overrides. Never re-run the failed tick. |
| Runtime checks | `/et_regression_test`: `issue479_tick_fault_logging_bounded`, `issue479_malformed_main_path_event_quarantined`, and `issue479_cd_tick_no_rerun_and_restore` all PASS. |
| In-game | Play through a main-path patrol trigger. If quarantine fires, expect exactly one fault, one quarantine, one recovery summary, continued director activity, and no repeated event trigger. |

---
## Settings lifecycle

### settings-burst-bounded -- bulk resets apply once

| Field | Detail |
|---|---|
| Symptom | DEFAULT or `/et_reset` exhausts the Lua heap while many settings fire synchronous callbacks. |
| Root cause | Each VMF notification ran the full composition restore and ConflictDirector refresh chain. |
| Expected post-fix | Setting ids queue synchronously; one full reapply runs on the next frame regardless of burst size. |
| Detection | Offline `test_et_settings_queue`; in-game `/et_regression_test` check `issue560_settings_reapply_coalesced`; `[et:560]` prints one applied count per drain. |
| Repro | In a mission, open the Enemy Tweaker Mod Tweaker tab, press DEFAULT, confirm, and Apply. Defaults persist without a heap crash. |

### et-bodvarr-runtime-breed-key -- boss features target War Camp's registered breed

| Field | Detail |
|---|---|
| Symptom | `boss_balance_targets_present` and `boss_grudge_targets_present` report missing `chaos_exalted_champion`; Bodvarr health and Crippling toggles silently do nothing. |
| Root cause | The features used the shared unsuffixed source/action-family stem, but vanilla registers and spawns Bodvarr as `chaos_exalted_champion_warcamp`. `_norsca` belongs to Skittergate's separate champion. |
| Expected post-fix | Both Bodvarr features target only `chaos_exalted_champion_warcamp`; Skittergate remains unaffected. |
| Detection | In-game `/et_regression_test` checks `boss_balance_targets_present` and `boss_grudge_targets_present` both pass; runtime `Breeds` contains the War Camp key and no unsuffixed key. |
| Repro | Enable each default-OFF Bodvarr toggle and play War Camp on the required difficulty. The health multiplier/Crippling mark applies to Bodvarr; repeat Skittergate and confirm its champion is unchanged. |

---
## Multiplayer / Network Sync

### gated-registration-divergence — Toggle-gated mod-load registration produces different network indices across peers

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Client crash `network_lookup.lua:2514: Table buff_templates/inventory_packages/level_keys does not contain key: <N>` when host fires `rpc_add_buff` or sets a shared state from a feature the host toggled but the client didn't. |
| Root cause | Mod-load registration into `_G.BuffTemplates` / `DeusPowerUpBuffTemplates` / `DeusPowerUpTemplates` / `NetworkLookup.*` / `LevelSettings` gated on a per-user setting → different subsets registered per peer → indices drift. |
| Mod(s) | chaos_wastes_tweaker, cosmetics_tweaker, weapon_tweaker, character_weapon_variants, buff_tweaker, enemy_tweaker, career_tweaker |
| Fix version(s) | ct v0.7.60 (dormants), ct v0.7.61 (trait boons), ct v0.7.62 (adventure levels), cosmetics_tweaker v0.8.66 (LA shields), crt v0.3.3-dev (22 talent-rework buffs), bt v0.1.1-alpha |
| Category | INTEGRATION |
| Repro | 1. Player A enables a setting-gated feature that injects new buffs/boons/levels (e.g. ct's `activate_dormant_*` or `inject_adventure_maps`). 2. Player B installs the same mod with the feature OFF. 3. Player A hosts a CW run / adventure. 4. Player B joins and plays until host applies the gated buff (or until an injected level loads). |
| Expected post-fix | All four players' indices match. No `does not contain key` crash on the client. Host's rpc_add_buff resolves to the correct buff name on every client. |
| Detection | Console log on client side. Search for `Table .* does not contain key:` or any `network_lookup.lua:2514`. Should be absent. |


---

### vmf-network-send-recipients — `"server"` recipient is silently dropped

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Client emit log fires, host receive log never fires. No error, no warning. |
| Root cause | VMF's `convert_names_to_numbers` accepts only `"all"`, `"others"`, `"local"`, or a literal peer_id. `"server"` / `"host"` / `"clients"` fall into else branch and are treated as a literal peer_id; `_vmf_users[peer_id]` lookup fails; `send_rpc_vmf_data` returns silently. |
| Mod(s) | cosmetics_tweaker, chaos_wastes_tweaker, any mod with client→host RPCs |
| Fix version(s) | cosmetics_tweaker v0.9.0.15-hotfix |
| Category | INTEGRATION |
| Repro | 1. Friend hosts a lobby. 2. You join as CLIENT. 3. Perform an action that should send an RPC to the host (e.g. cosmetics_tweaker LA cosmetic apply). |
| Expected post-fix | Host receives the RPC; you see the action reflected on the host's screen (and on other clients via host re-broadcast). |
| Detection | Add `mod:info("[emit] CLIENT->req")` before the send and `mod:info("[recv]")` at the receiver. Recv must fire when the test runs with you as client. |


---

### cross-mod-br-registration-sync — Subset divergence across BR-aware mods

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Player A (wt+ct+et installed) gets different NetworkLookup buff indices than Player B (only ct installed). Host's rpc_add_buff resolves to wrong buff on client. |
| Root cause | wt/ct/et each pre-register Big Rebalance templates at mod load. If their lists differ (subset vs full union), peer indices drift. |
| Mod(s) | weapon_tweaker, chaos_wastes_tweaker, enemy_tweaker, buff_tweaker |
| Fix version(s) | buff_tweaker v0.0.1+ (consolidated registration via single bt master); also see byte-identical canonical lists shipped 2026-05-21. |
| Category | STATIC |
| Repro | Run `qa/check_retired_big_rebalance.ps1`. |
| Expected post-fix | Retired BR implementation/registration files stay absent; hidden identifiers remain reserved only for save compatibility. |
| Detection | The blocking retirement gate rejects restored loaders, executable lifecycle plumbing, or unhidden BR widgets. |


---

## Cosmetics / LA / CWV / Engine Bugs

### vt2-threat-values-upvalue-built-once — Custom breed crashes calculate_threat_value

| Field | Value |
|-------|-------|
| Symptom | Crash `conflict_director.lua:2479 attempt to perform arithmetic on a nil value` after a custom-breed mod loads, especially when mod is disabled in VMF settings. |
| Root cause | `ConflictDirector` declares `local threat_values = {}` at file scope and fills it by iterating `Breeds` at game boot. Custom breeds added after that are absent. A defensive hook is insufficient when the mod is disabled (VMF still runs module code but skips hooks). |
| Mod(s) | enemy_tweaker |
| Fix version(s) | enemy_tweaker v0.3.5-dev |
| Category | INTEGRATION |
| Repro | 1. Have a mod register a custom breed at module load. 2. Disable the mod in VMF settings. 3. Start a mission. 4. Custom breed spawns (because its registration ran). |
| Expected post-fix | The eager #1413 registrar calls `CD.set_threat_value(nil, name, value)` after complete preflight and before structural publication, never from a hook. |
| Detection | `/regression_test` (enemy_tweaker) verifies the eager write. |


---

### vt2-pairs-breeds-at-file-load — 3 vanilla tables snapshot Breeds at boot

| Field | Value |
|-------|-------|
| Symptom | Custom breeds added post-boot crash in multiple places: `calculate_threat_value`, `event_ai_unit_activated`, `StatisticsDatabase._create_stat`. |
| Root cause | `conflict_director.lua` (threat_values), `performance_manager.lua` (activated_per_breed), `statistics_definitions.lua` (per-breed stat tables) all iterate `pairs(Breeds)` at file-load. Mod-added breeds miss all three. |
| Mod(s) | enemy_tweaker |
| Fix version(s) | enemy_tweaker v0.3.3 → v0.3.6 |
| Category | INTEGRATION |
| Repro | (Same as threat-values; the other two paths surface at first activate / first damage.) |
| Expected post-fix | One eager #1413 transaction seeds threat, named statistics definitions, and any already-live performance table before publishing the breed; future `PerformanceManager.init` scans the published `Breeds` row. |
| Detection | `/regression_test` in enemy_tweaker walks all three. |


---

### vt2-strict-lookup-rawget — NetworkLookup tables error on missing-key GET

| Field | Value |
|-------|-------|
| Symptom | Mod load crashes when `if not nl_breeds[name] then ...` runs the existence check. |
| Root cause | `network_lookup.lua` installs a strict `__index` that errors on any unknown key. Plain bracket lookup trips it. |
| Mod(s) | enemy_tweaker, buff_tweaker, career_tweaker |
| Fix version(s) | enemy_tweaker v0.2.4-dev, bt v0.1.1-alpha, crt v0.3.4-dev |
| Category | STATIC |
| Repro | 1. Add `if not NetworkLookup.breeds[name] then NetworkLookup.breeds[name] = ... end` at mod load. 2. Start the game. |
| Expected post-fix | Use `rawget(NetworkLookup.breeds, name)` for the existence check. |
| Detection | Lint: grep mod source for `NetworkLookup\.\w+\[` without surrounding `rawget`. |


---

### hook-multi-return-collapse — Wrapper drops multi-return values

| Field | Value |
|-------|-------|
| Symptom | Crash `for limit must be a number` (or similar nil-from-vanilla error) in code downstream of a wrapped function. |
| Root cause | `return wrapper(func(self, ...))` collapses every return after the first into wrapper's argument list; downstream sees nil. |
| Mod(s) | enemy_tweaker |
| Fix version(s) | enemy_tweaker v0.2.4 |
| Category | STATIC |
| Repro | 1. Hook a function returning `(a, b, c)` via `return transform(func(self, ...))`. 2. Run the wrapped code path. |
| Expected post-fix | `local a, b, c = func(self, ...); return transform(a), b, c`. |
| Detection | Audit each `mod:hook` wrapper — confirm multi-return capture. |

### vmf-renderer-creator-keys (cont.) — see Cosmetics section |


---

## Localization / UI

### vmf-dropdown-options-mutated — Multi-angle-bracket cascades from shared options table

| Field | Value |
|-------|-------|
| Symptom | VMF dropdown shows `<<key>>` or `<<<key>>>` cascades on second/third dropdown sharing an options table. |
| Root cause | VMF's `localize_dropdown_data` mutates `option.text` in place. Two dropdowns referencing the same options table get the first localized; the second tries to localize the already-localized string. |
| Mod(s) | enemy_tweaker, career_tweaker, any mod with multiple dropdowns of the same option set |
| Fix version(s) | enemy_tweaker v0.4.2-dev, crt v0.2.18-dev (talent-swap dropdown cascade) |
| Category | STATIC |
| Repro | 1. Define `local _SHARED = { { text = "off", value = "off" }, ... }`. 2. Use `options = _SHARED` on two different dropdown widgets. 3. Open settings. |
| Expected post-fix | Each dropdown gets its own options table (inline literal or factory function `_build_options()`). No bracket cascade. |
| Detection | Open mod's VMF settings UI; look for `<<...>>` text in any dropdown. Should be absent. |


---

### vmf-widget-id-unique — Duplicate setting_id breaks settings page

| Field | Value |
|-------|-------|
| Symptom | Mod's ENTIRE settings page disappears in VMF UI. Boot log: `Widgets N and M have the same setting_id`. |
| Root cause | VMF requires every widget's `setting_id` to be globally unique across the settings tree. Can't have one setting appear in two different category groups. |
| Mod(s) | chaos_wastes_tweaker, others |
| Fix version(s) | ct v0.7.26-test |
| Category | STATIC |
| Repro | 1. Duplicate any widget under two different groups (same setting_id). 2. Open settings. |
| Expected post-fix | Unique setting_ids only; use display-name prefixes for cross-cutting categorization. |
| Detection | Boot log grep for `same setting_id`. Should be absent. |


---

### vt2-chat-command-syntax — Commands are `/<name>` directly, not `/<modid> <name>`

| Field | Value |
|-------|-------|
| Symptom | Documentation / Workshop description shows commands as `/wt dump` / `/cos probe_hat` — wrong; misinforms players. |
| Root cause | `mod:command("name", ...)` registers `/name` directly. Mod-id is internal identifier, not chat prefix. |
| Mod(s) | all |
| Fix version(s) | doc rule (audit 2026-05-19) |
| Category | STATIC |
| Repro | n/a |
| Expected post-fix | Every doc / cfg description / CHANGELOG references commands as `/<name>` directly. |
| Detection | Lint: grep `CHANGELOG.md` / `itemV2.cfg` / `*.md` for `/wt `, `/ct `, `/cos ` etc. before each command. Should be absent. |


---

### vt2-mod-command-inventory — Audit command name collisions

| Field | Value |
|-------|-------|
| Symptom | Two mods register the same `/name`; one shadows the other. |
| Root cause | Chat-command namespace is global. |
| Mod(s) | all |
| Fix version(s) | inventory snapshot 2026-05-19 |
| Category | STATIC |
| Repro | n/a |
| Expected post-fix | Cross-check every new `mod:command("name", ...)` against the monorepo inventory. Rename if collision. |
| Detection | Lint pass over all mod sources comparing `mod:command(` first args. |


---

## Build / Deploy / Workshop

### lua-forward-reference — Functions called before definition crash at runtime

| Field | Value |
|-------|-------|
| Symptom | Game crashes on first frame with `attempt to call global 'NAME' (a nil value)` from a function defined later in the file. |
| Root cause | Lua 5.1 does NOT hoist `local function` definitions. Shipped 6+ times in cosmetics_tweaker (v0.7.1, v0.7.37, v0.7.39, v0.7.51, v0.7.53, v0.8.39). |
| Mod(s) | cosmetics_tweaker, others |
| Fix version(s) | cosmetics_tweaker v0.8.40 (defensive `M.fn = function()` pattern) |
| Category | STATIC |
| Repro | (Static rule — any forward reference will crash on first use.) |
| Expected post-fix | All `local function NAME` definitions appear ABOVE every call site. For helpers that logically belong in a different section, hoist as `M.NAME = function()` on a module table. |
| Detection | `tools/lint/regression-lint.ps1` walks each mod's Lua and reports forward refs. |


---

### feedback-pre-deploy-checklist — Forgetting checklist costs ~2 min/restart per skipped check

| Field | Value |
|-------|-------|
| Symptom | (Same as lua-forward-reference.) Burned 5+ times in v0.7.x portrait work. |
| Root cause | No mandatory pre-deploy gate. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | (Process.) |
| Expected post-fix | Before EVERY build+deploy: (1) forward-reference audit, (2) MOD_VERSION bump, (3) changelog update, (4) bundle verification, (5) hash verification. |
| Detection | VMBLauncher build gate integrates lint suite. |


---

### ugc-tool-forward-slashes — `tags = [];` causes 0x2 first-upload failure

| Field | Value |
|-------|-------|
| Symptom | First upload of a new mod fails with `generic failure (probably empty content directory) (0x2)` even though staging is otherwise correct. |
| Root cause | `tags = [];` line in `itemV2.cfg`. ugc_tool adds that line itself after a successful first upload — pre-writing it causes the 0x2. |
| Mod(s) | every newly-created mod's first upload |
| Fix version(s) | vmb-launcher v0.2.8 |
| Category | STATIC |
| Repro | 1. Hand-write `itemV2.cfg` with `tags = [ ];`. 2. Run the canonical reviewed ship sequence from `PROJECT_STANDARDS.md` section 6.6. 3. Confirm the cfg gate rejects it before publication. |
| Expected post-fix | Don't include `tags = [];` in the staged cfg for first upload. (Also: disable Zapret if present.) |
| Detection | Audit cfg before first upload; ensure no `tags` line. |


---

### ps5-getcontent-utf8 — PS 5.1 Get-Content -Raw mangles UTF-8

| Field | Value |
|-------|-------|
| Symptom | Workshop description shows `â€¢` instead of `•` (and similar garbled multi-byte chars). |
| Root cause | PowerShell 5.1's `Get-Content -Raw` uses system code page (Windows-1252), not UTF-8. Multi-byte UTF-8 silently mangled. |
| Mod(s) | any mod whose cfg contains bullets / em-dashes / accented chars |
| Fix version(s) | _upload_helper.ps1 fix 2026-05-14 |
| Category | STATIC |
| Repro | 1. Put `•` in description in source cfg. 2. Run an upload via a tool using `Get-Content -Raw`. 3. Workshop page shows `â€¢`. |
| Expected post-fix | Use `[System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)` and `WriteAllText(... , [System.Text.UTF8Encoding]::new($false))` (no BOM). |
| Detection | After upload, verify Workshop page shows correct chars; or compute `xxd -p source.cfg | grep -o 'e280a2' | wc -l` and match against staged. |


---

### feedback-workshop-upload-verify — `Upload finished` lies; check workshop_log.txt + file size

| Field | Value |
|-------|-------|
| Symptom | User reports the mod hasn't changed despite multiple "successful" uploads. |
| Root cause | ugc_tool prints `Upload finished` on no-op. Steam logs `No content change detected` in `workshop_log.txt`. Workshop page `time_updated` doesn't bump on no-op. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | 1. Upload a mod whose bundle is byte-identical to Workshop. 2. Read "Upload finished" message. 3. Notice page didn't change. |
| Expected post-fix | After every upload, grep `C:\Program Files (x86)\Steam\logs\workshop_log.txt` for `Uploaded new content` (not `No content change detected`). For friends_only items, eyeball Workshop page file size. |
| Detection | Manual log check OR Workshop page file-size check after every upload. |


---

### feedback-workshop-upload-without-deploy — Author's local install stays stale

| Field | Value |
|-------|-------|
| Symptom | After uploading a new version, you restart VT2 and console still echoes the OLD version. |
| Root cause | Steam doesn't reliably re-download Workshop items the same Steam account authored. |
| Mod(s) | all |
| Fix version(s) | n/a - canonical reviewed ship; see `PROJECT_STANDARDS.md` section 6.6 |
| Category | MANUAL |
| Repro | Historical direct-publication path: upload without the reviewed tracked bundle/deploy transaction, then observe the author still loading the old version. The current receipt gate blocks this path. |
| Expected post-fix | Use the canonical merge-first reviewed ship sequence in `PROJECT_STANDARDS.md` section 6.6; direct launcher publication is prohibited. |
| Detection | PC-A uses the hash-verified local deploy without restarting Steam; volunteer testers unsubscribe/resubscribe through the dev collection. Confirm the newest console log's `[<id>:LOAD]` version. |


---

### feedback-deploy-vs-upload-distinction — Local deploy doesn't reach subscribers

| Field | Value |
|-------|-------|
| Symptom | Friend / subscriber still reports old behavior; only the author's local install is updated. |
| Root cause | `deploy_all.ps1` only copies to LOCAL workshop folder. Subscribers get the version on Steam, which needs `upload`. |
| Mod(s) | all |
| Fix version(s) | n/a - canonical reviewed ship; see `PROJECT_STANDARDS.md` section 6.6 |
| Category | MANUAL |
| Repro | 1. Run `vmblauncher deploy <mod>` only. 2. Friend reports no change. |
| Expected post-fix | Use the canonical merge-first reviewed ship sequence in `PROJECT_STANDARDS.md` section 6.6 for subscriber-facing changes. |
| Detection | After every iterative fix, verify both the local file AND the Workshop page changed. |


---

### ugc-tool-pushes-all-cfg-fields — Every upload overwrites title/desc/preview/visibility

| Field | Value |
|-------|-------|
| Symptom | Workshop page title/description/preview reverts to whatever the local cfg says. |
| Root cause | ugc_tool reads `itemV2.cfg` and pushes EVERY field on every upload. Direct edits to the live Workshop page are reverted. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | 1. Edit live Workshop page directly. 2. Upload from local cfg. 3. Live page reverts. |
| Expected post-fix | Cross-check cfg vs live Workshop page BEFORE every upload. Ensure cfg's title/desc/preview/visibility reflect the desired live state. |
| Detection | Manual pre-upload audit. |


---

### vmblauncher-handscaffold-first-upload — Missing `item_preview.png` creates orphan Workshop items

| Field | Value |
|-------|-------|
| Symptom | First upload of a hand-scaffolded mod fails with `0x9` invalid preview file, but ugc_tool still created a Workshop item. |
| Root cause | vmblauncher does NOT synthesize a placeholder preview. ugc_tool creates the Workshop item BEFORE validating preview/content. On failure, item exists but isn't written back to cfg. |
| Mod(s) | every newly-scaffolded mod |
| Fix version(s) | doc rule |
| Category | MANUAL |
| Repro | 1. Hand-scaffold a new mod (skip `vmb create`) without `item_preview.png`. 2. Run the canonical reviewed ship sequence from `PROJECT_STANDARDS.md` section 6.6. 3. Confirm preflight rejects the missing preview before publication. |
| Expected post-fix | Copy `vmb/.template-vmf/item_preview.png` into mod root BEFORE first upload. If failure occurs, capture orphan publisher_id from stdout, convert signed→unsigned, write `published_id = <N>L;` to cfg manually, then retry. |
| Detection | Verify `item_preview.png` exists in mod root before any first upload. |


---

### feedback-mod-version-format — Release-track suffix only (alpha/beta/dev)

| Field | Value |
|-------|-------|
| Symptom | Workshop title shows weird suffixes like `v0.9.9.1-revert` / `v0.9.8.7-revert` / `v0.7.81-hotfix`. |
| Root cause | Suffix should be track-only (`alpha`/`beta`/`dev`/`rc`). Change-descriptors belong in changelog, not version. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | STATIC |
| Repro | 1. Set `MOD_VERSION = "0.9.9.1-revert"`. 2. Run the canonical nonpublishing `ship.ps1 -BuildOnly` phase. 3. Confirm version QA rejects the descriptor before publication. |
| Expected post-fix | `MOD_VERSION = "X.Y.Z[.W][-alpha|beta|dev|rc]"`. No change descriptors. |
| Detection | Lint: grep each mod's `MOD_VERSION` for suffix tokens outside the allowed set. |


---

### feedback-redundant-safeguards-ok — Belt-and-suspenders dual-table writes are OK

| Field | Value |
|-------|-------|
| Symptom | (Not a bug — process note.) |
| Root cause | When redundancy is cheap and missed-path failure is silent, write to multiple tables / install multiple gates. Examples: dual buff registration (DeusPowerUpBuffTemplates + _G.BuffTemplates), late-arrival re-apply paths, idempotent registration. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | n/a |
| Expected post-fix | Don't strip "redundant" safeguards without confirming the missed-path failure has actually been eliminated. |
| Detection | Code review process. |


---

### feedback-search-changelog-for-known-crashes — Grep CHANGELOG before theorizing

| Field | Value |
|-------|-------|
| Symptom | (Process rule.) |
| Root cause | Most surprising VT2 crashes have a documented prior fix. Searching memory + CHANGELOG.md before theorizing saves 1-2 wasted versions per crash. |
| Mod(s) | all |
| Fix version(s) | n/a |
| Category | MANUAL |
| Repro | n/a |
| Expected post-fix | Before theorizing about a crash, grep all `CHANGELOG.md` + `memory/` for the literal crash signature. |
| Detection | Process. |


---

### vt2-hash-reverse-lookup — Decipher `Resource '#ID[hash]' not found!` via murmur hash

**[GAME-PATCH-WATCH]**

| Field | Value |
|-------|-------|
| Symptom | `[Engine Error]: Resource '#ID[xxx]' was not found!` with no path. |
| Root cause | Hash is murmur64 of a Stingray resource path. Need to brute-hash candidate paths and match. |
| Mod(s) | all |
| Fix version(s) | doc rule |
| Category | MANUAL |
| Repro | n/a |
| Expected post-fix | Use `C:/Tools/vt2_bundle_unpacker/target/release/unpacker.exe murmur hash <path>` to find the missing resource. Don't speculate. |
| Detection | When crash occurs, run hash candidates before authoring a fix. |


---

## Slugs

- cross-mod-br-registration-sync
- feedback-deploy-vs-upload-distinction
- feedback-mod-version-format
- feedback-pre-deploy-checklist
- feedback-redundant-safeguards-ok
- feedback-search-changelog-for-known-crashes
- feedback-workshop-upload-verify
- feedback-workshop-upload-without-deploy
- gated-registration-divergence
- hook-multi-return-collapse
- lua-forward-reference
- ps5-getcontent-utf8
- ugc-tool-forward-slashes
- ugc-tool-pushes-all-cfg-fields
- vmblauncher-handscaffold-first-upload
- vmf-dropdown-options-mutated
- vmf-network-send-recipients
- vmf-widget-id-unique
- vt2-chat-command-syntax
- vt2-hash-reverse-lookup
- vt2-mod-command-inventory
- vt2-pairs-breeds-at-file-load
- vt2-strict-lookup-rawget
- vt2-threat-values-upvalue-built-once
