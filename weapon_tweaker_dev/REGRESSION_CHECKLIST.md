# Regression Checklist — weapon_tweaker

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to weapon_tweaker.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

Last updated: 2026-09-01.

---

## #1436 - Hotfix 6.11.2 Dagger and Axe & Falchion history

| Field | Check |
|---|---|
| Candidate version | WT 0.12.328-beta / WT Dev 0.12.329-dev. |
| Default | **Sienna's Dagger** and **Saltzpyre's Axe and Falchion** default to **Current (Game Version 6.12.0)** and perform zero gameplay writes. |
| Historical | Select **Game Version 6.11.1**. Dagger Heavy Attack 2 restores `dagger_h1_medium_smiter_diag`; Axe & Falchion Heavy Attacks 1 and 2 restore `axe_falcion_heavy_smiter_vertical_right` on the right-hand route only. |
| Atomic refusal | A missing or foreign Axe & Falchion H1/H2 current guard refuses both family writes before mutation. |
| Restore/isolation | Returning to Current restores all three exact native routes and original table identities. Dagger and Axe & Falchion selections remain independent. |
| Automated | `test_wt_history_patch_6_11_2.lua`, the Hotfix 6.11.2 block in `test_wt_history_runtime.lua`, and `run_wt_history_patch_6_11_2_host_matrix.ps1` under PS7 + PS5.1. |

---

## #1436 - Patch 6.11.0 Kruber Longbow history

| Field | Check |
|---|---|
| Candidate version | WT 0.12.327-beta / WT Dev 0.12.328-dev (prior slice). |
| Default | **Kruber's Longbow** history defaults to **Current (Game Version 6.12.0)** and performs zero gameplay writes. |
| Historical | Select **Game Version 6.10.0**, restart, and confirm both `longbow_empire_template` and its tutorial clone use source-exact `aim_zoom_delay = 2`; no other Longbow leaf changes. |
| Atomic refusal | A missing tutorial template or either non-`0.22` current guard refuses the whole family before the gameplay template changes. |
| Restore/composition | Returning to Current restores both exact `0.22` leaves and original table identities. History installs before ordinary WT adapters, which continue to compose afterward. |
| Automated | `test_wt_history_patch_6_11_0.lua`, the Longbow block in `test_wt_history_runtime.lua`, and `run_wt_history_patch_6_11_0_host_matrix.ps1` under PS7 + PS5.1. |

---

## #943 - Fire Sword heavy attack tweaks

| Field | Check |
|---|---|
| Candidate version | Pending ship (version assigned by the coordinator at claim time). |
| Off state | With both settings off, every inspected `default` chain edge and every `heavy_attack_spell` timing value is numerically identical to vanilla, including after repeated on/off cycles. |
| Sweep opener | Enable **Flame Sword: Sweep Opens Heavies** only. An idle charged heavy opens with the sweep, the follow-up heavy is the nova, and both keep vanilla timing. Lights, push, block, weapon special, and the tooltip comparison stay vanilla. |
| Nova slowdown | Enable **Flame Sword: 10% Slower Nova Heavy** only. The nova stays the opener; its swing, hit, damage window, movement-slow window, and heavy continuation windows are all 10% longer with no cumulative drift across toggles or state transitions. |
| Composition | Both on: sweep opens, nova follows, only the nova is slower. |
| Isolation | Per-template-identity capture: a replaced/late template re-captures fresh vanilla values; no other Fire Sword action or other weapon changes. Wire-safe: sub_action re-route between vanilla names + attacker-local melee timing only. |
| Automated | Offline `test_wt_fire_sword.lua`; `/wt_regression_test`: `issue943_fire_sword_heavy_contract` (fixture projection + live idle-edge audit). |

---

## #1023 - live Hold-Pose HUD row (dev only)

| Field | Check |
|---|---|
| Candidate version | Pending ship (version assigned by the coordinator at claim time). |
| Visibility | The row appears only while the Hold-Pose master and the focused channel are enabled AND a live local-owner target unit resolves. Bypass, losing the unit, or leaving the applicable state removes the row without erasing saved values. |
| Focus | The row identifies First Person/Third Person and Right Hand/Left Hand and follows the last relevant `wt_dev_hp_*` edit, including enable toggles and settings batches. |
| Values | Displayed Pos X/Y/Z (+0.000 m precision) and Rot P/Y/R (+0.0 deg precision) exactly match the normalized `_component_plan` handed to `_apply_pose_to`; no internal item key is rendered. |
| Ownership | One `IngameHud.update` post-hook mod-wide, read-only, local-only; no RPC, no shared-template mutation, no public-widget exposure. Existing #616/#569 Hold-Pose regressions remain green. |
| Automated | Offline `test_wt_hold_pose.lua` (#1023 sections); `/wt_regression_test`: `issue1023_live_hold_pose_hud`. |

---

## #1190 - loadout-row weapon isolation

| Field | Check |
|---|---|
| Cache contract | WT's cross-career cache is keyed `career -> loadout index -> slot`; a write or read for one Roman-numeral row cannot override another row. Baseline-native weapons bypass the WT cache and retain vanilla persistence. |
| Native Slayer | Give Slayer distinct native weapons in loadouts I, II, and III (for example Cog Hammer, Greataxe, and Dual Hammers). Manually replace the weapon in III, switch III -> II -> I -> III, and confirm every row shows and equips only its own weapon. |
| Genuine cross-career | Put one genuinely cross-career WT weapon in a single Slayer row and native controls in the other rows. Repeat III -> II -> I -> III; the WT weapon returns only with its authored row and is never written into the other rows. |
| Bot isolation | Select or preview a bot loadout while the local player has a cached WT weapon. Bot reads remain vanilla and never receive the local player's cached backend ID. |
| Add/delete lifecycle | Add a row, equip a WT weapon there, then delete a row before it and repeat with the cached row itself. Surviving rows retain their own weapons; deleting a cached row cannot leak its weapon into another index. |
| Restart | After a full game restart, native rows retain their vanilla values. When GUT owns persisted modded rows, each cross-career row is restored independently; WT-alone never writes a cross-career item into PlayFab. |
| Live core | Enable a genuine cross-career Slayer weapon first, then run `/verify_wt_loadout_cache reset`. Re-equip two distinct native melee weapons in rows I and II and the cross-career weapon in III. Starting on III, switch III -> I -> II -> III; run `/verify_wt_loadout_cache` once and require `CORE PASS`. Missing observations report `CORE NOT RUN`; cache bleed or a wrong route reports `FAIL`. |
| Automated | Offline `test_wt_loadout_cache.lua` proves the immutable 83-weapon native catalog, legacy-cache reset, row isolation, add/delete shifting, and nonmutating all-row overlay. `/wt_regression_test`: `issue1190_loadout_cache_is_row_scoped` is the structural smoke check; it does not replace the armed live cycle. |

---

## #316 - Empire Longbow cross-career variable zoom

| Field | Check |
|---|---|
| Candidate version | WT Dev 0.12.307-dev (public mirror 0.12.306-beta). |
| Automated | `/wt_regression_test`: require the candidate check `issue316_empire_longbow_cross_career_variable_zoom` PASS; `issue316_kruber_longbow_zoom_contract` retains the already-shipped draw/presentation boundary as a negative invariant. Offline `test_wt_longbow_variable_zoom.lua` proves the exact action identity, six-career allow-list, authored thresholds, exclusions, one hook owner, and public/Dev policy identity. |
| Owner zoom | Equip the Empire Longbow on Mercenary and Bounty Hunter at minimum. Aim and press action special repeatedly; each cycles the authored zoom levels. Huntsman is the native control and an unrelated bow is the negative item control. |
| Retired diagnostic | The consumed `[wt:316]` base-zoom observer was removed under #499 because it did not exercise weapon-special cycling or Bounty Hunter. Current acceptance uses the two named runtime checks and the public Solo procedure only. |
| Boundary | Owner camera state stays local and vanilla-owned. No shared action mutation, custom RPC, or new lookup row; topology is Solo. |

---

## #168 - Hold-Pose independent right/left controls

| Field | Check |
|---|---|
| Candidate version | WT Dev 0.12.307-dev. |
| Automated | `/wt_regression_test`: `issue168_hold_pose_independent_hands` requires the four distinct 1P/3P hand groups, rejects the retired single-hand selector, and executes different right/left nine-value plans. Offline `test_wt_hold_pose.lua` pins the same production seam and exact unit-to-plan routing. |
| Third person | Enable the tuner. Give the right hand a visible position-only value and the left hand a distinct rotation plus non-uniform scale; apply and confirm neither hand inherits the other's values. Swap the patterns and repeat. |
| First person | Enable First Person and repeat with separate `fp_rh` and `fp_lh` groups. Each local hand changes independently; Third Person remains on its own values. |
| Reset/bypass | Toggle the master off and back on: saved values remain, while the captured baseline is restored during bypass. The existing global reset may reset both hands; no single-hand reset is claimed. |
| Boundary | Local-player 1P/3P weapon roots only. Inventory preview, hero preview, bots, remote husks, score screens, and baked transforms remain excluded. |

---

## #611 - per-career availability masters

| Field | Check |
|---|---|
| Candidate version | WT 0.12.267-beta / WT Dev 0.12.268-dev (not shipped) |
| Placement | Masters appear inside each existing `melee_<career>` / `ranged_<career>` leaf, above that career's weapons; none remain at the receiving-character slot level. |
| Scope | Toggling one master changes only its exact receiving career, slot, and source-character children. Other careers remain untouched. |
| Derived state | Changing one child recomputes only its reverse-mapped master. It turns on only when every child in that one bucket is on. |
| Order/style | Every leaf orders present sources Kruber, Bardin, Kerillian, Saltzpyre, Sienna. Master text uses GUI Tweaker's `font_button_normal` warm tan; weapon rows remain unchanged. |
| Automated | Offline `test_wt_master_toggles.lua`; `/wt_regression_test`: `issue611_master_toggle_wiring`; stream parity gate. |

---

## #732 - CWV Infantry spear on Saltzpyre first-light crash

| Field | Check |
|---|---|
| Candidate version | WT 0.12.276-beta / 0.12.277-dev |
| Automated | Offline `test_wt_cwv_effective_template` proves the effective clone shares the donor remap and wield tables in both streams. `/wt_regression_test`: `issue732_cwv_infantry_spear_saltzpyre_remap`. |
| Solo crash path | On WHC, Bounty Hunter, or Zealot, equip Tuskgor Spear, select Infantry Combat Style, and perform the first light. `attack_swing_down_left_axe` must resolve to `attack_swing_stab`; no `Unit.animation_event` fault. |
| Chain coverage | Exercise complete light, heavy, block, push, weapon-swap, and re-wield chains. All three standard Saltzpyre careers retain the `to_2h_billhook` receiver vocabulary. |
| Boundaries | Native Kerillian remains on the donor's deliberate no-remap branch. First-person actions, CWV balance, sound-bank residency, and Warrior Priest are unchanged. |

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

### vt2-husk-extension-class-pair — Hooking the self-owned class doesn't fire for husks

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Feature works on local player but not on remote players (husks) as observed from a different machine. |
| Root cause | `unit_extension_templates.lua` defines `self_owned_extensions` and `husk_extensions` as parallel arrays. `SimpleInventoryExtension` ≠ `SimpleHuskInventoryExtension` — no method inheritance. Hooking one is a silent no-op for remote players. |
| Mod(s) | weapon_tweaker, cosmetics_tweaker, character_weapon_variants |
| Fix version(s) | weapon_tweaker v0.12.37, ct v0.9.0.10 |
| Category | INTEGRATION |
| Repro | 1. Friend equips a weapon needing your mod's per-wield logic (animation remap, paint, etc.). 2. You watch from across the map as their character on YOUR screen. 3. Look for the remap/paint/swap to apply on their husk. |
| Expected post-fix | Husk has the remap/paint/swap applied. Same visual as the local player would see if they were holding the weapon. |
| Detection | Visual check on the husk. For anim remap: husk's swings match local. For paint: husk's shield/hat matches LA texture. |


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

## Animation / 3P

### 1p-animations-universal — Never override 1P anim_event / state_machine / wield_anim

| Field | Value |
|-------|-------|
| Symptom | 1P attack animations corrupted across all characters when a per-career 1P override is added. |
| Root cause | `first_person_base` unit is shared across all six characters. Any weapon's 1P state machine plays correctly on any character's first-person hands by default. Overriding 1P puts the state machine into the wrong weapon state. |
| Mod(s) | weapon_tweaker, character_weapon_variants |
| Fix version(s) | weapon_tweaker v0.9.69 |
| Category | STATIC |
| Repro | (Static rule — no live repro. Adding any `anim_event` (1P) override per character will break 1P.) |
| Expected post-fix | Only `anim_event_3p`, `wield_anim_3p`, `wield_anim_career_3p` are overridden per character. |
| Detection | Lint: grep mod source for `anim_overrides_1p` or 1P state-machine overrides per character. Should be absent. |


---

### vt2-no-bows-on-warrior-priest — Warrior Priest's 3P skeleton lacks ranged-stance events

| Field | Value |
|-------|-------|
| Symptom | When `wh_priest` is added to a cross-character bow/crossbow/longbow port unlock, his 3P body either holds the previous weapon's idle (silent no-op) or hits an engine fatal in downstream code asserting the wield event resolved. |
| Root cause | Warrior Priest's 3P skeleton authors only the six universal wields plus `to_2h_hammer`. No `to_crossbow`/`to_longbow`/`to_repeating_crossbow`. |
| Mod(s) | weapon_tweaker |
| Fix version(s) | wt v0.12.46-dev (audit) |
| Category | STATIC |
| Repro | 1. Add `wh_priest` to a bow/crossbow port's unlock map or `_*_WIELD_3P` table. 2. Equip the weapon on Warrior Priest. 3. Wield. |
| Expected post-fix | wh_priest is omitted from every ranged-bow/crossbow/longbow port table. He stays in melee cross-character ports (1H hammer, 2H hammer, 1H hammer+shield only). |
| Detection | Grep `wt` source for `wh_priest` in any `*_WIELD_3P` / unlock-map block; should be absent for bow-class ports. |


---

### vt2-no-tpose-default-stance — Missing 3P event holds previous weapon's idle (NOT T-pose)

| Field | Value |
|-------|-------|
| Symptom | After equipping a cross-character weapon, the 3P body keeps the LAST weapon's idle stance and silently no-ops the missing attack event. No T-pose, no engine fatal. |
| Root cause | VT2 SM handles missing `anim_event_3p` as no-op + previous-state retain. Not a T-pose. |
| Mod(s) | weapon_tweaker, character_weapon_variants |
| Fix version(s) | docs corrected 2026-05-19 |
| Category | MANUAL |
| Repro | 1. Equip a cross-character weapon known to have a missing 3P anim event. 2. Swing/wield it. 3. Observe 3P body. |
| Expected post-fix | The body stays in the previous weapon's idle (silent missing-event no-op). Reports/QA matrices must use "previous-weapon idle" wording — not "T-pose." |
| Detection | Visual + `wt animlog` console output (`[MISSING]` on the 3P line indicates the event is unauthored). |


---

### anim-remap-per-unit-state — Single-global remap makes husks animate as if holding viewer's weapon

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Remote players' (husks') 3P animations on cross-character weapons play as if they're holding whatever the LOCAL viewer is holding. |
| Root cause | Pre-v0.12.35 weapon_tweaker stored `_current_weapon_template` / `_3p_weapon_remap` / `_last_remap_template` as module globals — populated only by the LOCAL viewer's wield. The Unit.animation_event hook then applied that remap to every body, including husks. |
| Mod(s) | weapon_tweaker |
| Fix version(s) | wt v0.12.35 |
| Category | INTEGRATION |
| Repro | 1. You hold a vanilla weapon. 2. Friend holds a cross-character weapon. 3. Watch friend's husk swing. |
| Expected post-fix | Husk's swings use HIS weapon's remap. Per-unit state weak-keyed by body unit. |
| Detection | `/regression_test` in wt verifies the per-unit state table is weak-keyed (`__mode = "k"`). Visual confirm: husks animate correctly regardless of local viewer's weapon. |


---

### anim-closed-vocabulary — Remap target must be in target template's authored anim_event set

| Field | Value |
|-------|-------|
| Symptom | After adding a cross-character remap, the body either does nothing or plays the wrong clip on the targeted event — even though `Unit.has_animation_event` returns TRUE. |
| Root cause | The master state machine knows event names that have no visible clip in the current sub-graph. Only events authored on the wield-SM-matching template are guaranteed to have a real clip. Picking from the skeleton-events probe table or `Unit.has_animation_event` is invention. |
| Mod(s) | weapon_tweaker, character_weapon_variants |
| Fix version(s) | CWV v0.1.158-0.1.193 (multiple) |
| Category | STATIC |
| Repro | 1. Add a remap entry whose target isn't in the target template's authored `anim_event` set. 2. Equip the weapon on the cross-character. 3. Swing. |
| Expected post-fix | Every remap target appears in `dumps/weapon_actions.txt` for the target template. Run `wt force3p <target>` to visually verify the clip plays. |
| Detection | Lint or audit: for each entry in `_3p_template_remaps`/`_3p_key_remaps`, confirm target is in `dumps/weapon_actions.txt` for the target template. Plus visual `wt force3p`. |


---

### 1p-animations-universal-recurring — Recurring AI mistake of overriding 1P per character

| Field | Value |
|-------|-------|
| Symptom | (Same as 1p-animations-universal.) |
| Root cause | The user has corrected this multiple times in different sessions. Default to 3P-only scope from the first sketch of any anim work. |
| Mod(s) | weapon_tweaker, character_weapon_variants |
| Fix version(s) | n/a — process rule |
| Category | STATIC |
| Repro | (Documentation rule.) |
| Expected post-fix | Code comments around anim fields explicitly tag 1P as universal/out-of-scope. |
| Detection | Audit: grep code comments near anim hooks for the 1P-universal annotation. |


---

### 3p-anim-fix-process — Closed-vocab + visual-verify procedure for cross-character anims

| Field | Value |
|-------|-------|
| Symptom | Cross-character weapon plays charge but no strike, or stays in previous weapon's idle. |
| Root cause | Skeleton events probe is too broad; visual verification via `wt force3p` is required. |
| Mod(s) | weapon_tweaker, character_weapon_variants |
| Fix version(s) | doc reference (no patch line) |
| Category | MANUAL |
| Repro | 1. `wt animlog` in chat. 2. Perform full light + heavy chain. 3. Find `[MISSING]` events. 4. Pick remap target from target template's closed list. 5. `wt force3p <candidate>` to visually verify before committing. |
| Expected post-fix | Every remap is closed-vocab + visually verified. |
| Detection | Procedure adherence — see `weapon_tweaker/CROSS_CHARACTER_PORT_RECIPE.md`. |


---

### vmf-grip-offset-sign — +Z = grip lower

| Field | Value |
|-------|-------|
| Symptom | Confusion about sign convention; "hand on blade" tuning goes the wrong direction. |
| Root cause | When user says "grip too high / hand on blade", use POSITIVE Z to move grip lower. |
| Mod(s) | weapon_tweaker, character_weapon_variants |
| Fix version(s) | doc rule |
| Category | MANUAL |
| Repro | n/a |
| Expected post-fix | Documented in `weapon_tweaker.lua:1016`. |
| Detection | Process. |


---

## Cosmetics / LA / CWV / Engine Bugs

### cwv-backend-id-lookup — item_data.key returns BASE weapon key for cwv items

| Field | Value |
|-------|-------|
| Symptom | Visual transform / animation / scale fails silently on cwv items because the lookup table is keyed by cwv_item_key but `item_data.key` returns the base weapon key. |
| Root cause | MoreItemsLibrary `cwv_*` items have `data.key` / `data.name` returning the BASE weapon key. The custom CWV identity lives in `item_data.backend_id` (`cwv_<key>_001`). |
| Mod(s) | character_weapon_variants, cosmetics_tweaker, weapon_tweaker |
| Fix version(s) | doc rule + per-hook resolution helpers |
| Category | STATIC |
| Repro | 1. Add a `_my_lookup_table[cwv_key]` keyed lookup. 2. Read via `item_data.key`. 3. Notice lookup silently returns nil. |
| Expected post-fix | Resolve via `backend_id:match("^(cwv_.-)_%d%d%d$")`. |
| Detection | Lint: search per-mod hooks for `item_data.key` / `item_data.name` direct lookups against `_my_table[cwv_key]`. |


---

### cwv-cross-character-unit-packages — Cross-character unit refs need package preload

| Field | Value |
|-------|-------|
| Symptom | First-throw / first-equip crash in `World.spawn_unit` for a unit from a different character's natural package. |
| Root cause | Vanilla queues packages off `right_hand_unit`/`left_hand_unit`. Cross-character pickup/projectile/3P-override units aren't auto-queued. |
| Mod(s) | character_weapon_variants, weapon_tweaker |
| Fix version(s) | CWV v0.1.118 (Tuskgor Javelin), wt v0.12.5-dev (brace repeater) |
| Category | INTEGRATION |
| Repro | 1. Add a CWV variant with `right_hand_unit_3p_override` from another character. 2. Equip on a peer who never carried that source weapon. 3. Wield + use. |
| Expected post-fix | `Managers.package:load(<path>, "ref", nil, true, true)` at mod init for every cross-character path. Plus `has_loaded` guard in the swap hook. |
| Detection | First-equip test on a fresh launch. No crash. |


---

### vt2-force-load-only-listed-paths — Engine fatals on force-load of unlisted display units

| Field | Value |
|-------|-------|
| Symptom | Async `_pop_queue` engine fatal `Resource '#ID[...]' not found` AFTER a synchronous pcall returns success. |
| Root cause | `Managers.package:load(<path>, ...)` requires `<path>` to appear in `scripts/network_lookup/inventory_package_list.lua`. Embedded resources (display units, etc.) crash. |
| Mod(s) | character_weapon_variants, weapon_tweaker, cosmetics_tweaker |
| Fix version(s) | CWV v0.1.224, v0.1.289 |
| Category | STATIC |
| Repro | 1. Add `Managers.package:load("units/weapons/weapon_display/display_2h_spears_wood_elf", ...)` at mod init. 2. Restart VT2. 3. Engine fatals on _pop_queue. |
| Expected post-fix | Grep `inventory_package_list.lua` for every path before force-loading. If absent, find a different solution (load parent package, override `display_unit`, etc.). |
| Detection | Audit every `Managers.package:load(...)` call site against `inventory_package_list.lua`. |


---

### vt2-class-hook-derived — Hook the derived class, never the base

| Field | Value |
|-------|-------|
| Symptom | A hook on `HeroPreviewer`/`PlayFabMirrorBase` registers correctly per VMF log but silently never fires on the runtime instance. |
| Root cause | VT2's `class()` copies parent methods into child at class-definition time. `MenuWorldPreviewer.method = original_HeroPreviewer.method` (independent copy made before mods load). Hooks on the base method never reach the child instance. |
| Mod(s) | cosmetics_tweaker, weapon_tweaker, character_weapon_variants |
| Fix version(s) | wt v0.12.17, cosmetics_tweaker v0.7.99 |
| Category | STATIC |
| Repro | 1. `mod:hook("HeroPreviewer", "equip_item", ...)`. 2. Open keep inventory. 3. Watch hook never fire. |
| Expected post-fix | Hook `MenuWorldPreviewer.equip_item` (the derived class actually instantiated). Or hook both for safety. |
| Detection | Audit each hook on `HeroPreviewer*`/`PlayFabMirrorBase*` — should be the derived class name. |


---

### inventory-preview-hook-menuworldpreviewer — Specific instance of class-hook-derived

| Field | Value |
|-------|-------|
| Symptom | Inventory preview shows base-weapon mesh / wrong scale / wrong wield even though in-game equip works. |
| Root cause | (Same as vt2-class-hook-derived, applied to the keep inventory previewer.) |
| Mod(s) | weapon_tweaker |
| Fix version(s) | wt v0.12.17 |
| Category | STATIC |
| Repro | 1. Hook `HeroPreviewer.equip_item` only. 2. Equip a CWV variant or override-scale weapon. 3. Open inventory. |
| Expected post-fix | Both hooks: HeroPreviewer (for `team_previewer.lua`) AND MenuWorldPreviewer (for keep inventory). |
| Detection | Visual: keep inventory previewer matches in-game body. |


---

### vt2-mission-spawn-career-lookup — Managers.player:owner returns nil at mission-spawn

| Field | Value |
|-------|-------|
| Symptom | Career-gated 3P-unit swap works in keep but reverts to vanilla at mission spawn. |
| Root cause | At mission spawn, `Managers.player:owner(player_unit)` hasn't been re-pointed at the new mission-side unit. Returns nil → hook bails. |
| Mod(s) | weapon_tweaker |
| Fix version(s) | wt v0.12.17 |
| Category | INTEGRATION |
| Repro | 1. Equip Kruber brace-of-pistols (which weapon_tweaker swaps to repeating handgun 3P). 2. Start mission. 3. Watch husk shows brace pistols, not repeater. |
| Expected post-fix | Career resolved via `ScriptUnit.has_extension(unit, "inventory_system")._career_name` first; `Managers.player:owner` used only as fallback. |
| Detection | Cross-character weapon equip in keep + mission spawn; same 3P mesh both contexts. |


---

### vt2-custom-explosion-template — Custom ExplosionTemplate needs .name AND _G registration

| Field | Value |
|-------|-------|
| Symptom | Host fatal `area_damage_system.lua:347 attempt to index local 'explosion_template' (a nil value)` after first AOE hit drains the ring buffer. |
| Root cause | Vanilla's `explosion_templates.lua` loop sets `.name` on every template at engine boot, before mods load. Custom templates miss this. |
| Mod(s) | weapon_tweaker |
| Fix version(s) | wt v0.12.51-dev |
| Category | STATIC |
| Repro | 1. Add `_MY_EXPLOSION_TEMPLATE = { explosion = {...} }` (no .name, no _G write). 2. Pass to `DamageUtils.create_explosion`. 3. Wait for next-frame drain. |
| Expected post-fix | Template has explicit `.name = "<modid>_<name>"` AND is registered into `_G.ExplosionTemplates[name]`. |
| Detection | `/regression_test` in wt verifies the template name + registration. |


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

## Slugs

- 1p-animations-universal
- 1p-animations-universal-recurring
- 3p-anim-fix-process
- anim-closed-vocabulary
- anim-remap-per-unit-state
- cross-mod-br-registration-sync
- cwv-backend-id-lookup
- cwv-cross-character-unit-packages
- feedback-deploy-vs-upload-distinction
- feedback-mod-version-format
- feedback-pre-deploy-checklist
- feedback-redundant-safeguards-ok
- feedback-search-changelog-for-known-crashes
- feedback-workshop-upload-verify
- feedback-workshop-upload-without-deploy
- gated-registration-divergence
- inventory-preview-hook-menuworldpreviewer
- lua-forward-reference
- ps5-getcontent-utf8
- ugc-tool-forward-slashes
- ugc-tool-pushes-all-cfg-fields
- vmblauncher-handscaffold-first-upload
- vmf-dropdown-options-mutated
- vmf-grip-offset-sign
- vmf-network-send-recipients
- vmf-widget-id-unique
- vt2-chat-command-syntax
- vt2-class-hook-derived
- vt2-custom-explosion-template
- vt2-force-load-only-listed-paths
- vt2-hash-reverse-lookup
- vt2-husk-extension-class-pair
- vt2-localize-string-format-pipeline
- vt2-mission-spawn-career-lookup
- vt2-mod-command-inventory
- vt2-no-bows-on-warrior-priest
- vt2-no-tpose-default-stance
