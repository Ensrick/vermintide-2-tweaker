# Regression Checklist — career_tweaker

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to career_tweaker.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

> **Suite location:** `/crt_regression_test` lives in `scripts/mods/career_tweaker/_crt_regression.lua`. It locks the casting/transposition and retired #440 probe exclusion boundaries while requiring the read-only #221 census.

Last updated: 2026-08-23.

---
## Foot Knight feature suite (#619)

| Field | Value |
|-------|-------|
| Scope | Six independent default-off controls: heavy interruption immunity, aura range, Rock shield offense, Teamwork great-weapon offense, Final March, and secondary melee. |
| Capability boundary | Shield and non-polearm great-weapon checks consume the live weapon template. WT/CWV clones inherit behavior; Flail & Shield is included despite its exceptional `FLAIL_1H` type, while glaives/scythes remain excluded. |
| Tradeoffs | Rock toggle multiplies only dodge distance by 0.90. Teamwork toggle cancels only the native -0.10 damage-taken passive; aura DR, 5% ally stacks, and Final March DR remain. |
| Authority/network | Host reconciles humans/bots; client reconciles local owner. Custom templates remain local-only and never enter `NetworkLookup` or a vanilla RPC. |
| Final March | Requires a nonempty roster of other allies whose exact status is dead. Downed/disabled is false. One mission latch; 60 seconds; disabler stagger is server-only. |
| Talent text | Rock uses the authored `_desc_2` key and composes range/shield toggles per lookup; Teamwork uses its authored `_desc_2` key. All-off delegates to vanilla localization exactly. |
| Buff-bar feedback | Stable local effect buffs use their exact resident vanilla Foot Knight talent icons. Both Rock effects use Rock of Reikland; Teamwork uses That's Bloody Teamwork. Conditional bonuses and Final March expose icons only for their active lifetime; Final March owns one icon-bearing sub-buff, and the internal Teamwork DR canceller has no icon. |
| Secondary slot | Reconciles both backend `CareerSettings` and menu `SPProfiles` carriers in place to include `{ "melee", "ranged" }`; removes only its owned melee insertion and abandons ownership after foreign array replacement. Both desktop and controller inventory category builders recheck the exact career object before caching its filter. Sparse profile/career arrays are traversed with `pairs` (#935). |
| Detection | Offline `test_crt_foot_knight_policy.lua`; runtime `/crt_regression_test` checks `issue619_foot_knight_contract`, both concrete inventory hooks, and `issue699_foot_knight_icon_census`; transition-only `[crt:619] secondary-slot`, `[crt:935] menu-slot`, and `[crt:699]` live HUD diagnostics. #935 is solo-testable on the controller inventory. Full #699 acceptance is co-op: client-local Foot Knight plus host spectating a Foot Knight bot, while preserving #663's two-Foot-Knight no-flicker behavior. |

---
## Foot Knight multi-source aura ownership (#663)

| Field | Value |
|-------|-------|
| Symptom | Two Foot Knights make a shared aura icon disappear/reappear because vanilla update/remove functions resolve any target buff with the same template. |
| Ownership | Each driver owns only its target claims. One aggregate vanilla server buff exists per template/target; the first claim adds or adopts it and only the final release removes it. |
| Network | Uses existing vanilla buff names and `BuffSystem` RPCs. No custom lookup name, custom RPC, or per-tick send is introduced. |
| Lifecycle | Driver removal releases its own claims. Mission reset flushes aggregate server ids. Mod disable restores every exact vanilla update/remove function, including nil absence. |
| Detection | Offline `test_crt_foot_knight_policy.lua`; runtime `/crt_regression_test` check `issue663_foot_knight_aura_source_ownership`; bounded transition prefix `[crt:663]`; two-human walk in CHANGELOG 0.4.2-beta. |

---
## Ranger Veteran ale action speed (#367)

| Field | Value |
|-------|-------|
| Source boundary | `bardin_survival_ale.actions.action_one.default` authors `total_time=1.9`; `WeaponUnitExtension` divides both completion and animation playback by the action's `anim_time_scale`. |
| Expected | Default-off leaves the exact vanilla action. Enabled derives `anim_time_scale=1.9/0.75` (2.533333...), producing a 0.75-second action and matching 1P/3P animation while preserving the standard consume/buff path. |
| Restore | Toggle-off and mod-disable restore either the exact prior scale or exact nil absence; an unexpected action shape remains untouched. |
| Detection | Offline `test_crt_ale_animation.lua`; runtime `/crt_regression_test` check `issue367_ale_one_second_drink` (registered name retained for output stability); apply marker `[crt:367]`; solo timing/buff check in CHANGELOG 0.4.1-beta. |

---
## Rework-family master controls (#445)

| Field | Value |
|-------|-------|
| Scope | Active Career Tweaker native reworks and Tourney Balance ports only. Retired Big Rebalance keys remain hidden and inert. |
| Expected | Selecting either family enables its complete catalog, clears the rival family, and performs one final apply per owner. Turning a master off clears only that family; any partial leaf selection shows both masters off. |
| Layout | Stock VMF keeps both all-on checkboxes under `Talent Reworks > Master Toggles`. Current Mod Tweaker replaces the pair with one `Rework Family` radio collapsible and an explicit `None [Default]` choice; Zealot's two THP conversions receive the same presentation. |
| Labels | Every active leaf title begins with `[Ensrick]` or `[Tourney Balance]`; navigation groups, tooltips, and master rows do not. The metadata is shared with the runtime policy rather than duplicated in localization. |
| Detection | Offline `test_crt_rework_master_policy.lua` + `test_gut_exclusive_radio.lua`; runtime `/crt_regression_test` checks `issue445_rework_family_masters` and `crt_mod_tweaker_exclusive_groups_registered`; solo UI walk in CHANGELOG 0.4.8-beta plus #446 radio verification. |

---
## Deferred subgroup-master census (#221)

| Field | Value |
|-------|-------|
| Scope | Remaining Unchained, Engineer, armor, per-career, and Tourney subgroup-master proposal after GT #297, CT's deployed umbrellas, and CRT #445's complete family controls. |
| Boundary | Native/Tourney template owners and live armor/overcharge hook reads do not share one reversible lifecycle. No subgroup checkbox is exposed until an exact owner can preserve child choices while master-off and apply/restore each owner once. |
| Expected | Startup and `/crt_umbrella_audit` each emit one bounded `[crt:221]` row with `whole_family=present`, `cluster_gates=0/4`, and `mutation=false`. No setting changes and no gameplay hooks originate from the census. |
| Detection | Offline `test_crt_umbrella_audit.lua`; beta contract `career_tweaker/tests/check_public_beta.ps1`; runtime `/crt_regression_test` check `issue221_umbrella_audit_armed`. |

---
## Bardin disabler dodge investigation (#440)

| Field | Value |
|-------|-------|
| Symptom | Bardin is anecdotally less consistent at dodging Packmasters, Lifeleeches, or Gutter Runners. |
| Source boundary | All profiles clone one dodge table. Packmaster/Lifeleech use common dodge status; Gutter uses root+0.2 trajectory, 1m trigger overlap, and `j_neck` tracking. Compiled player trigger geometry remains unverified. |
| Fix version(s) | 0.3.68-dev diagnostic source; excluded from 0.4.0-beta; retired from production in 0.4.26-beta |
| Expected | The public beta installs no disabler/dodge hooks and emits no `[crt:440]` rows. |
| Detection | Offline `test_crt_bardin_disabler_source_contract.lua` preserves the engine-source findings and proves the probe file/tick are absent. `/crt_regression_test` must report `PASS: public_beta_issue_probes_disabled`; the name is retained for output stability. Any future co-op investigation requires a newly reviewed bounded diagnostic owner. |

---
## No-op talent-menu close preserves live buffs (#283)

| Field | Value |
|-------|-------|
| Symptom | Opening and closing Talents without changing a row rebuilds every talent buff and erases accumulated stacks such as Bounty Hunter's Job Well Done. |
| Expected | Identical desktop/controller selections skip persistence and talent/ammo reapply; changing any row delegates to vanilla unchanged. The beta still exposes no casting/transposition widgets or runtime exports and never reads saved swap selections. |
| Detection | Offline `test_crt_talent_selection.lua`; `/crt_regression_test` checks `issue283_talent_menu_noop_guard` and `public_beta_talent_swaps_disabled`; solo in-game Job Well Done check from issue #283. |

---
## Handmaiden Focused Spirit (#472)

| Field | Value |
|-------|-------|
| Symptom | The partial stacking rework can grow or rearm on both copies of a `buffer="both"` talent, while the tooltip routes a mod-local key through the engine-global localizer. Mixed chip-exemption settings can also diverge owner/server stack state. |
| Source boundary | Vanilla's proc receives only attacker, amount, and damage type (`player_unit_health_extension.lua:702-703`), so Ratling identity is captured synchronously from the full `add_damage` call. A remote human owns one client talent copy and the server owns its mirror; the owner decides, the server removes the corresponding mirror stack, and bots use one server writer. |
| Configuration | The edge-driven `crt_focused_spirit_config` channel carries both boolean settings only after exact CRT catalog parity. Missing/mismatched/stale/contradictory/foreign state fails closed to vanilla. It announces on parity, setting change, or one reply and never polls. |
| Expected | Starting from zero, exactly one mirrored 5% stack appears per complete ten-second interval through five. One ordinary hit removes one stack from each mirrored copy and creates one cooldown. Configured chip/DoT preserves both stack count and deadline. |
| Localization | Keep `kerillian_maidenguard_power_level_on_unharmed_desc`. The one global `Localize` hook composes all four setting combinations. Chip-only text remains printf-escaped because vanilla values remain; stacking text uses literal percents because the rework clears `description_values`. |
| Lifecycle | Pending rearms and synchronous damage context clear on either setting change and mod disable. A setting change requires talent reapply or mission reload; do not infer live reseeding. Death, talent loss, and a failed wrapped damage call cannot schedule a deferred cooldown. |
| Detection | Offline `test_crt_damage_classification.lua` plus `test_crt_focused_spirit.lua`; runtime `/crt_regression_test` check `issue472_focused_spirit_contract`; read-only `/crt_verify_focused_spirit`; bounded `[crt:472]` rows include role, action, source/type, stack/cooldown before/after, and wrapped success. Run the exact solo card before reversed-role co-op. |

---
## Handmaiden Dance of Blades pair stacks (#473)

| Field | Value |
|-------|-------|
| Stack ownership | The outgoing and incoming halves have distinct local sub-buff names because `BuffExtension` enforces `max_stacks` by `sub_buff_template.name`. Both remain children of the unchanged network-visible top-level stack template. |
| Authority | The `on_hit` proc is `authority="server"`. Client-local hit processing writes zero stacks; the forwarded server path writes one. Host-local and bot hits each write one. Closed peer parity writes zero. |
| Lifetime | Each top-level application gives both halves the same start/end time. `refresh_durations=false` on both halves; later hits cannot move an older pair's expiry. Hits one through fifteen add a complete pair and hit sixteen adds neither. |
| Wire stability | The top-level dodge/proc/stack names and alphabetical registration order are unchanged. The local outgoing/incoming names never enter `NetworkLookup`; no RPC, hook, or update loop was added. |
| Detection | Offline `test_crt_dance_of_blades.lua` models the exact engine bucket/expiry and authority predicates with planted old-defect controls. Runtime `/crt_regression_test` check `issue473_dance_of_blades_contract` validates the installed live templates, including exact distinct names, incoming `stacking_name`, and server authority. |

---
## Multiplayer / Network Sync

### crt-networked-rework-peer-parity — Modded buff names on vanilla rpc_add_buff CTD non-crt peers (issue 425)

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | A peer WITHOUT crt fatals `Table buff_templates does not contain key: <N>` (buff_system.lua:430 decode) when a crt player triggers a networked talent rework, or instantly on hot-join (BuffSystem.hot_join_sync replay). |
| Root cause | Seven reworks + the trn_wh_priest tourney port push mod-registered names through ProcFunctions.add_buff / add_buff_on_special_kill / BuffSystem:add_buff / the server-controlled overcharge-chunk and distance-aura drivers, all of which encode `NetworkLookup.buff_templates[name]` onto `rpc_add_buff`. Stub pre-registration only protects crt-to-crt lobbies. |
| Mod(s) | career_tweaker |
| Fix version(s) | crt v0.3.55-dev (peer-parity gate + wire-safe wrappers + hot-join filter) |
| Category | INTEGRATION |
| Repro | 1. You run crt with one of the seven `network_unsafe` reworks on (e.g. GK Virtue of the Impetuous Knight). 2. A friend WITHOUT crt joins. 3. Play the reworked career, trigger the proc (kills / overcharge). 4. Also test the friend hot-joining mid-mission while a Sienna overcharge-driver rework is active. |
| Expected post-fix | No crash on any peer. Your side logs `[crt:425] parity degraded` + a chat notice, and the rework behaves VANILLA until everyone has crt (auto re-enables). With all peers on crt the rework is unchanged. |
| Detection | Non-crt peer's console log clean of `network_lookup.lua` / `does not contain key`; your log carries the `[crt:425]` trail. `/crt_regression_test` locks the invariants (wrapper registration, unsafe-catalog parity, no-raw-networked-funcs sweep). |

---

### crt-exact-buff-catalog-parity — Positive server ID collides with timed CRT buff (issue 776)

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Client crashes in `BuffSystem.rpc_add_buff` with `Cannot use duration for server controlled buffs!`; the three attached logs received positive server IDs 12, 13, and 9 while local lookup ID 1574 resolved to `crt_questingknight_impetuous_as`. |
| Root cause | Issue #425's schema-1 handshake proved only CRT presence. It did not prove that every peer assigned the same numeric `NetworkLookup.buff_templates` ID to every CRT name, so an unrelated host buff could decode locally as a timed CRT template. |
| Mod(s) | career_tweaker |
| Fix version(s) | Candidate: crt v0.4.6-beta |
| Category | INTEGRATION |
| Repro | Two-player lobby with the previously colliding catalogs. Trigger the host-side buff activity captured in the #776 logs while the client runs CRT, then repeat with GK Impetuous Knight kills and a hot join. Include unrelated host numeric IDs 12, 13, and 9 as collision controls. |
| Expected post-fix | Networked CRT reworks stay vanilla until every peer proves the exact CRT name+numeric fingerprint. A CRT-resolving mismatch is dropped before vanilla; exact peers use native `LocalAndServer` timed sync, refresh one 20-second stack, and expire normally. No crash and no unbounded logging. |
| Detection | `/crt_regression_test` passes `crt_wire_catalog_identity_exact_776`, `crt_rpc_add_buff_receiver_floor_776`, `crt_impetuous_timed_sync_contract_776`, and `crt_wire_runtime_gate_catalog_exact_776`; offline `test_crt_wire_contract.lua` and `test_peer_parity_transition.lua` pass, including immediate enabled-to-disabled mismatch delivery. In logs, at most one `[crt:776] rpc_add_buff dropped` row appears per reason/template. |

---

### crt-authoritative-path-wire-floor — Parity reads bypassed the exact-catalog proof (issue 1158)

**[MULTIPLAYER]** [untested]

| Field | Value |
|-------|-------|
| Symptom | No user-visible symptom on its own. This closes three ways the #425/#776 gates could report "parity is settled" while the proof behind that answer had already lapsed: the beacon was published to every call site even when `mod:network_register` never took the channel callback; each call site re-derived its own answer straight off the beacon, so a catalog that shifted AFTER `build_identity` fingerprinted it kept the boot-time identity live; and the optional Mod Tweaker grey-out retried `get_mod()` once a second forever when GUT was absent. |
| Root cause | The exact-catalog identity is built once at load. Nothing re-verified that `NetworkLookup.buff_templates` still resolved every owned name in BOTH directions afterwards, and nothing verified the beacon's transport had actually committed before gameplay owners started trusting it. |
| Mod(s) | career_tweaker |
| Fix version(s) | Candidate: crt v0.4.21-beta (composite floor + bounded runtime-gate retry) |
| Category | INTEGRATION |
| Repro | Offline only, via the planted-defect proofs below; there is no in-game repro that does not require forcing a lookup rewrite or a `network_register` failure. In-game this must be confirmed as a NON-regression: a 2-4 player lobby where every peer has crt must behave exactly as v0.4.20, and a mixed lobby must still degrade to vanilla and auto-re-enable. |
| Expected post-fix | Two floors share one transport-committed + catalog-exact base. `mod._crt_wire_safe()` adds the beacon's settled state and owns apply/restore churn, the tourney port, the `rpc_add_buff` receiver, and the GUT grey-out. `mod._crt_wire_live()` adds an instant roster evaluation and owns every individual send. Keeping them separate is load-bearing: `applied_state()` is refreshed by a 0.5s poll (`_lib_peer_parity.lua` `POLL_INTERVAL`) while `all_peers_have()` re-evaluates per call, so routing a per-send guard through the settled read would keep emitting modded buff names for up to one poll interval after a non-crt peer joins — the #425 CTD. A beacon whose install did not commit is never published, and the runtime-gate retry retires after 30 attempts. |
| Detection | Offline `test_crt_wire_contract.lua` passes `CRT #1158 catalog_intact rejects a lookup row that lost one direction`, `CRT #1158 composite floor is false when any single conjunct fails`, `CRT #1158 runtime gate retry is bounded and permits late success`, and `CRT #1158 every authoritative parity read routes through the floor`. The last is the standing lock: it fails if any apply engine reintroduces a bare `mod._crt_peer_parity` read, or if the live guard is collapsed onto the settled read. `tools\mod-lint\lint-mod.ps1 -Mod career_tweaker` stays at zero findings. In-game, `[crt:425] WARNING peer-parity install did not commit` must NOT appear in a normal session — if it does, the beacon never registered and every networked rework is correctly inert. |

---

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

## Cosmetics / LA / CWV / Engine Bugs

### feedback-vmf-hook-safe-no-chain — Two hook_safe on same Class.method silently drop one

| Field | Value |
|-------|-------|
| Symptom | Boot log shows `Hooking 'method' from [Class]` twice with identical Origin pointer, but neither callback fires. |
| Root cause | VMF treats the second registration as a replacement, not a chain — only one runs, with no error. |
| Mod(s) | character_weapon_variants, cosmetics_tweaker, career_tweaker, lobby_tweaker |
| Fix version(s) | CWV v0.1.99, crt v0.2.34-dev (BH Double-Shotted hook collision), lobby_tweaker v0.1.0-dev (Boot hook collision) |
| Category | STATIC |
| Repro | 1. Add two `mod:hook_safe(Class, method, ...)` calls in the same file. 2. Restart. 3. Watch neither fire. |
| Expected post-fix | Consolidate to one hook_safe; or hook a sibling method. |
| Detection | Lint: grep for duplicate `mod:hook_safe(.*,` per Class+method pair within each mod source. |


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

### vt2-localize-string-format-pipeline — Hand-written tooltip strings get `%%` formatted

| Field | Value |
|-------|-------|
| Symptom | Boon/talent/property tooltip shows `[Invalid String Format]` placeholder. |
| Root cause | `UIUtils.format_localized_description` runs `string.format` on every description. Literal `%` (e.g. `+25%`) is invalid format spec. |
| Mod(s) | chaos_wastes_tweaker, weapon_tweaker, general_tweaker, career_tweaker, lobby_tweaker |
| Fix version(s) | ct v0.5.2-dev, wt v0.12.63-dev, gt v0.2.35, crt v0.2.17-dev, crt v0.2.36-dev (34 crashify exceptions), lobby_tweaker v0.1.1-dev |
| Category | STATIC |
| Repro | 1. Add a description override with `25%` literal. 2. Open the tooltip in-game. |
| Expected post-fix | Escape literal `%` as `%%` in Localize hook overrides AND in `_localization.lua` strings (VMF's `safe_string_format` also routes through string.format). |
| Detection | Lint: grep mod localization files and Localize hooks for single `%` not followed by `s`/`d`/etc. format chars. |


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

### crt-ranger-ale-independent-decay — Multi-sub-buff patch indexing

| Field | Value |
|-------|-------|
| Symptom | Ranger Veteran's three ale stacks all expire together after the newest drink refreshes every stack. |
| Root cause | Both vanilla ale sub-buffs set `refresh_durations = true`; `BuffExtension._add_stacking_buff` consequently rewrites every existing stack's start/end time. |
| Mod(s) | career_tweaker |
| Fix version(s) | 0.3.67-dev (#366) |
| Category | AUTO + MANUAL |
| Repro | Enable the rework and collect three ales at staggered times. |
| Expected post-fix | Damage-reduction and attack-speed stacks retain matching independent 300-second clocks and expire 3 to 2 to 1 in collection order. |
| Detection | Lua test `test_crt_ale_decay`; runtime `/crt_regression_test` check `issue366_ale_independent_stack_decay`; solo HUD observation. |


---

## Slugs

- feedback-deploy-vs-upload-distinction
- feedback-mod-version-format
- feedback-pre-deploy-checklist
- feedback-redundant-safeguards-ok
- feedback-search-changelog-for-known-crashes
- feedback-vmf-hook-safe-no-chain
- feedback-workshop-upload-verify
- feedback-workshop-upload-without-deploy
- crt-ranger-ale-independent-decay
- gated-registration-divergence
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
- vt2-localize-string-format-pipeline
- vt2-mod-command-inventory
- vt2-strict-lookup-rawget
