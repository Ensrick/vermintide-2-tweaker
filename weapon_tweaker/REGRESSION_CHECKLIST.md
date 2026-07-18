# Regression Checklist — weapon_tweaker

## #664 - Executioner's Sword light headshot damage

| Field | Check |
|---|---|
| Candidate version | WT 0.12.268-beta / WT Dev 0.12.269-dev (not shipped) |
| Exact scope | Every `light_attack_*` sweep on `two_handed_swords_executioner_template_1`, including the push follow-up, uses the private profile while enabled and peer parity is confirmed. Both heavies and utility actions retain their authored profiles. |
| Damage | Repeatable light headshots are exactly 1.30x the disabled result. Body hits and both heavies are identical off/on; speed, stagger, cleave, crit, and armor data remain byte-for-byte cloned from vanilla. |
| Lifecycle | On/off/on does not stack. Disable and WT peer-parity loss restore exact original profile keys; parity recovery reapplies once. Cross-career users share the same effective template transaction. |
| Automated | Offline `test_cwv_axe_balance.lua`; `/wt_regression_test`: `issue664_executioner_light_headshot_boundary`. |

---

## #611 - per-career availability masters

| Field | Check |
|---|---|
| Candidate version | WT 0.12.267-beta / WT Dev 0.12.268-dev (not shipped) |
| Placement | Masters appear inside each existing `melee_<career>` / `ranged_<career>` leaf, above that career's weapons; none remain at the receiving-character slot level. |
| Scope | Toggling one master changes only its exact receiving career, slot, and source-character children. Other careers remain byte-for-byte untouched. |
| Derived state | Changing one child recomputes only its reverse-mapped master. It turns on only when every child in that one bucket is on. |
| Order/style | Every leaf orders present sources Kruber, Bardin, Kerillian, Saltzpyre, Sienna. Master text uses GUI Tweaker's `font_button_normal` warm tan; weapon rows remain unchanged. |
| Automated | Offline `test_wt_master_toggles.lua`; `/wt_regression_test`: `issue611_master_toggle_wiring`. |

---

## #620 - CWV Tuskgor Foot Knight conditional default

| Field | Check |
|---|---|
| Candidate version | WT 0.12.261-dev with CWV 0.1.422-dev |
| WT alone | On a fresh profile, Foot Knight's Tuskgor Spear availability remains default-off. |
| CWV ready | After CWV marks `es_2h_heavy_spear` as Combat Style-ready, the exact Foot Knight setting seeds on once and live `can_wield` contains `es_knight`. |
| Persistence | Turn the row off after seeding; state transitions and hot reload must not force it back on. |
| Automated | Offline `test_wt_cwv_tuskgor_default.lua`; `/wt_regression_test` passes `issue620_cwv_tuskgor_foot_knight_default`. |
| Retirement | WT has no availability rows for legacy Infantry Spear, Imperial Longsword, or Black Guard Blade; native Tuskgor/Greatsword rows remain the only controls. |

---

## #621/#622/#623 - opt-in weapon balance nerfs

| Field | Check |
|---|---|
| Candidate version | WT 0.12.260-dev |
| Automated | Offline `test_cwv_axe_balance.lua` covers capability discovery, private 0.90x cleave clones, deterministic registration/fallback, peer-parity hold, exact speed allow-lists, CWV exclusion, idempotence, and nil/non-nil restore. `/wt_regression_test`: `issue621_one_hand_axe_cleave_boundary`, `issue622_cog_hammer_heavy_speed_boundary`, `issue623_native_mace_sword_speed_boundary`. |
| 1H Axe | Enable **1H Axe: 10% Less Cleave** and compare a native 1H Axe against Dual Axes, Axe and Shield, and a 2H Axe. Only the single axe loses cleave. Disable and confirm vanilla cleave returns without restart. |
| Cog Hammer | Enable **Cog Hammer: 10% Slower Heavies**. Test both axe-mode heavies and both charged/hammer-mode heavies; each takes 10% longer. Lights in both modes, push, block, wield, and weapon special remain vanilla. |
| Mace and Sword | Enable **Mace and Sword: Slower Attacks**. Native L1/L2 and H1/H2 take 10% longer. L3/L4, push, block, and CWV Sword and Mace remain vanilla. Disable and confirm exact original cadence returns. |
| Co-op safety | The 1H Axe clone profiles apply only after existing WT peer parity confirms every human; losing parity restores vanilla pointers and the #431 wire floor retains vanilla profile IDs. Cog/Mace speed uses vanilla animation-variable replication and no new transport. |

---

## #597 - CWV Greataxe availability

| Field | Check |
|---|---|
| Automated | Offline `test_cwv_greataxe.lua` locks four authored defaults, 16 conditional careers, and 20 total controls. |
| Default owners | Mercenary, Huntsman, Foot Knight, and Grail Knight retain Greataxe while their exact children remain enabled. |
| Expansion | Every non-Kruber career is default-off and receives the CWV Greataxe only through its exact child toggle. |
| Retirement | `cwv_es_poleaxe` has no WT catalog/localization row and cannot appear as an unlock option. |

---

## #596/#620 - Tuskgor Infantry Combat Style availability

| Field | Check |
|---|---|
| Candidate version | WT 0.12.261-dev / CWV 0.1.422-dev |
| Automated | Offline `test_wt_cwv_independence` proves the retired CWV row has no WT catalog entry; `test_wt_cwv_tuskgor_default` covers native readiness/default behavior. |
| Default owners | Native Tuskgor keeps its ordinary WT rows. Foot Knight is default-off with WT alone and seeded on once when CWV's Combat Style family is ready. Grail Knight remains default-off. |
| Transition | Disable Foot Knight after the CWV seed, then transition/hot reload; the user's false remains false and no retired Infantry row returns. |

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

## #112 - Saltzpyre Kruber shield rotation

| Field | Check |
|---|---|
| Candidate version | WT 0.12.251-dev |
| Automated | Offline `test_wt_saltzpyre_coverage` locks the exact `{25, -17.5, -15}` catalog and Spear & Shield exclusion. `/wt_regression_test`: `issue112_saltzpyre_kruber_shield_baked_rotation` covers all three careers, CWV clone-name compatibility, native controls, and ownership scope. |
| Solo visual | On WHC/BH/Zealot, inspect Empire Mace & Shield, both Empire Sword & Shield families, and CWV Empire Axe & Shield through wield, block, attack, swap, and inventory preview. All use the shared corrected seating. |
| Exclusions | Kruber Spear & Shield is unchanged. Native Kruber and Warrior Priest receive no correction. First person remains unchanged. |
| Renderer contract | The same baked delta is reconstructed from canonical rotation for owner, bot, remote husk, and preview. There is no transform RPC and no accumulation. Remote parity remains protected by #587's co-op regression. |

---

## #593 - conditional Axe+Shield ownership on Saltzpyre

| Field | Check |
|---|---|
| Candidate version | WT 0.12.250-dev |
| Automated | Offline `test_wt_cwv_ownership` covers the active/inactive native handoff and Warrior Priest exclusion. `test_wt_cwv_independence` locks both Empire variant catalogs to four Kruber plus three standard Saltzpyre careers and the three conditional owners. `/wt_regression_test`: `issue593_conditional_cwv_axe_shield_ownership`. |
| WT only | With CWV disabled or absent, the saved WT Bardin Axe+Shield toggle remains the fallback for WHC, Bounty Hunter, and Zealot. |
| WT + CWV | Enabling CWV suppresses native `dr_shield_axe` on those careers and exposes `cwv_es_axe_shield` plus `cwv_es_axe_shield_veteran` under WT's CWV availability controls. Kruber's four authored owners remain unchanged; Warrior Priest receives neither Saltz handoff. |
| Transition | Disable and re-enable CWV without restarting. The Empire variants disappear/return for standard Saltzpyre while the saved native fallback does the inverse; no duplicate `can_wield` rows or stale cached native loadout survives. |

---

## #112 - Saltzpyre Empire Handgun grip offset

| Field | Check |
|---|---|
| Candidate version | WT 0.12.249-dev |
| Automated | Offline `test_wt_saltzpyre_coverage` locks `{0, -0.17, -0.05}`, durable membership, and runtime registration. `/wt_regression_test`: `issue112_saltzpyre_handgun_baked_offset` checks all three standard Saltzpyre careers, native Kruber exclusion, and an unmodified ranged control. |
| Solo repro | On Witch Hunter Captain, Bounty Hunter, or Zealot, equip Kruber's Empire Handgun and inspect the third-person model after wielding, firing, swapping away, and swapping back. |
| Expected | Handgun root position retains Y `-0.17` and Z `-0.05` relative to its canonical pose. X, rotation, and scale remain canonical/baked; animation ticks do not erase or compound the correction. First person and native Kruber Handgun remain unchanged. |
| Renderer scope | The source-baked durable table is consumed by owner, bot, remote-husk, and inventory-preview paths without transform RPC traffic. The position is solo-verifiable locally; #587 separately guards renderer fan-out. |

---

## #391 - per-career CWV availability

| Field | Check |
|---|---|
| Candidate version | WT 0.12.242-dev (not deployed) |
| Automated | Offline `test_wt_cwv_independence` requires 30 preserved item-master IDs and 142 unique career children, including #596's three default-on and 17 default-off controls, exact master/child composition, positive `cwv_variant` marker gating, and shared data/runtime/localization schema. `/wt_regression_test`: `issue391_cwv_per_career_availability`. |
| Exact career | With the Kruber Dual Axes parent enabled, disable Foot Knight only. Keep and mission inventory must retain the item for Mercenary, Huntsman, and Grail Knight and remove it only from Foot Knight. Re-enable it and repeat on Saltzpyre Dual Axes / Warrior Priest. |
| Compatibility master | Disable the existing per-item parent: every catalogued career loses the item. Re-enable it: each persisted child choice resumes without being overwritten. Most items retain four authored children; the two #593 Empire Axe+Shield rows also expose three standard Saltzpyre children. |
| Boundaries | WT touches only a live catalog key positively marked `cwv_variant == true`, and only the careers authored in that catalog row. CWV absent/disabled produces no clone writes. No hook, RPC, or per-frame work is added. |
| Source contract | CWV assigns `def.careers` directly to clone `can_wield`; vanilla `BackendInterfaceCommon.can_wield` and inventory macros use exact membership. Career DLC ownership remains a separate vanilla career-selection gate. |

---

## #388 - Deepwood cross-career overcharge presentation

| Check | Expected |
|---|---|
| Automated | Offline `test_wt_overcharge_presentation` passes exact identity, native profile projection, threshold colors, owner-local/runtime wiring, lazy HUD hook, and restore presence. `/wt_regression_test` passes `issue388_deepwood_overcharge_profile`. |
| Owner | On Kruber, Deepwood low/medium/high overcharge uses the Sister green bar, thorn screen particles, life-staff warning sounds, native decay/lockout, and no generic explosion. |
| Transition | Swap Deepwood out and back. One bounded `[wt:388] ... restored/applied` record appears per transition; prior extension fields and live screen particles do not leak. Disabling WT also restores. |
| Co-op | Both peers run the build. Repeat with each peer as owner; the other observes and spectates. Owner and spectator HUDs agree, overcharge value replication remains smooth, and no new RPC/desync appears. |
| Negative controls | Native Sister Deepwood is untouched. Moonfire remains on `energy_system`; Sienna/Bardin overcharge weapons retain their own colors, sounds, particles, and explosion policy. |

---

## #400 - Cross-career Flamestorm observer FX aim

| Field | Check |
|---|---|
| Candidate version | WT 0.12.238-dev (not deployed) |
| Automated | Offline `test_wt_flamestorm_fx` locks exact template/career policy and the single creation/update hook pair. `/wt_regression_test`: `issue400_cross_career_flamestorm_fx_uses_replicated_aim`. |
| Co-op visual | Player A equips Flamestorm Staff on a non-Sienna career and fires while aiming horizontally, upward, and downward. Player B confirms the flame begins at the 3P staff tip and follows Player A's aim. |
| Native control | Repeat on Sienna: her authored muzzle presentation remains unchanged. Drakegun and all other flamethrower-template users remain outside the exact-template policy. |
| Log evidence | One `[wt:400] applied career=<career> template=staff_flamethrower_template source=replicated_aim` row per observed wielder, with no per-frame repeats. |
| Authority | Visual-only observer correction on each peer. Damage remains owner/server authoritative; co-op is required because the corrected surface is the synchronized 3P particle. |

## #341 - Bolt Staff primary overcharge reduction

| Field | Check |
|---|---|
| Candidate version | WT 0.12.237-dev (not deployed) |
| Automated | Offline `test_wt_bolt_staff_overcharge` covers exact 40% scaling, live toggle/revert, unrelated-key isolation, and unavailable-table failure. `/wt_regression_test`: `issue341_bolt_staff_primary_overcharge_contract` locks the live scalar and both primary sub-actions' unique `spark` key. |
| Solo comparison | From zero overcharge, fire ten uncharged Bolt Staff primary bolts with the option off, vent to zero, enable it, and repeat. Enabled heat should be about 60% of the off result. |
| Negative control | Fire charged bolts before and after enabling the option. Their overcharge, damage, projectile behavior, and cadence remain vanilla. |
| Authority | Owner-local scalar consumed at projectile fire; no RPC, custom lookup, or co-op verification required. |

## #316 - Kruber Longbow draw animation on non-Huntsman careers

| Field | Check |
|---|---|
| Fixed version | WT 0.12.264-beta; the bounded owner-camera probe remains available in the friends-only development stream. |
| Automated | `/wt_regression_test`: `issue316_kruber_longbow_zoom_contract` locks the vanilla `ActionAim` fingerprint, Mercenary/Foot Knight/Grail Knight native `draw_bow` handling, Huntsman exclusion, and Saltzpyre's crossbow presentation remap. The bounded lifecycle probe is development-stream-only. |
| Co-op visual | With matching WT builds, equip Kruber's Longbow on Mercenary, Foot Knight, and Grail Knight. For each career, a second player observes partial draw, full draw/hold, release, return, weapon swap, and mission transition; reverse roles. Huntsman is the unchanged native control. |
| Negative controls | First-person aim and camera zoom remain unchanged. Saltzpyre's non-Priest careers still use the Crossbow model and `to_zoom` presentation substitution. |
| Log evidence | Public beta emits no issue-specific live probe rows. In the development stream, `[wt:316] ... remap=native_draw_bow` proves policy selection and camera rows deliberately report `visible_draw=unverified`; neither is accepted as proof that the owner or remote-husk clip visibly played. |
| Authority | The fix uses WT's existing per-unit 3P event funnel for owner bodies and remote husks and adds no custom RPC. Visible remote playback still requires two-player verification, so `verify-fix-coop` is the sole verification label. |

## #585 - Moonfire energy bar clears after ranged replacement

| Field | Check |
|---|---|
| Fix version | WT 0.12.228-dev (user verified 2026-07-13) |
| Automated | `/wt_regression_test`: `issue585_moonfire_energy_hud_loadout_lifecycle`; offline Lua coverage checks nonnative reset, full-state no-op, Moonfire preservation, and native Kerillian exclusion. |
| Repeater transition | On a non-Kerillian career, drain Moonfire below full, replace it with Repeater Crossbow, and return to gameplay. The energy bar disappears without a mission restart. |
| Saltzpyre ranged | Repeat by replacing Moonfire with a normal Saltzpyre ranged weapon such as Crossbow or Handgun. No stale bar remains. |
| Re-equip | Re-equip Moonfire, drain energy, wield melee, and verify the bar/current charge and #584 background recharge work normally. Replacing it again clears the bar once. |
| Native control | Kerillian Moonfire and normal Kerillian loadout changes retain vanilla energy behavior; WT must not inspect or reset her nonzero native-rate extension. |
| Log evidence | One `[wt:585] cleared stale energy HUD after ranged-slot replacement` line per successful drained-Moonfire removal; no per-frame spam after energy reaches full. |

## #584 - Moonfire recharges while stowed

| Field | Check |
|---|---|
| Fix version | WT 0.12.227-dev (user verified 2026-07-13) |
| Automated | `/wt_regression_test`: `issue584_moonfire_stowed_native_regen_contract` covers melee-active Moonfire, bow-active single-rate behavior, native Kerillian exclusion, non-Moonfire replacement, and an empty ranged slot. |
| Cross-career | On Kruber, Bardin, Saltzpyre, or Sienna with Moonfire equipped: drain energy, switch to melee, and verify the bar continues refilling at the native 1.5/s rate. |
| Slot swaps | Repeatedly swap melee/ranged while below maximum. Recharge speed must remain constant, with no doubled increments or pause while melee is active. |
| Negative controls | Equip a normal ammo ranged weapon; WT must not drive `energy_system`. On Kerillian, Moonfire retains vanilla recharge with no WT addition. |
| Authority | Verify on the owning player. The helper must not update remote husks or add an RPC; vanilla energy replication remains authoritative. |

## #582 - native Bardin Dual Axes vs dedicated CWV variants

| Field | Check |
|---|---|
| Fix version | WT 0.12.226-dev; CWV 0.1.391-dev (user verified 2026-07-13) |
| Automated | `/wt_regression_test`: `issue582_native_dual_axes_cwv_ownership_boundary`; `/cwv_regression_test`: `issue582_dual_axes_native_variant_ownership_boundary` and `dual_axes_cosmetic_family_parity`. |
| Availability | Native `dr_dual_wield_axes` is absent from every Kruber and Saltzpyre WT category/control. Bardin remains unchanged. Kerillian remains unchanged. |
| CWV owners | Kruber receives `cwv_es_dual_axes`; Saltzpyre receives `cwv_wh_dual_axes`. Both retain their full curated illusion pools and receiver-specific 3P mappings. |
| Stale loadout | Start with native Dual Axes cached/equipped on WHC or Kruber from an older WT build, then load 0.12.226. The invalid cache is discarded and vanilla loadout fallback occurs without crash or native item leakage. |
| Visual | Equip each CWV variant, swap/stow, complete light/heavy chains, and inspect/apply at least one illusion. The item key must remain the dedicated CWV key. |

## #580 - Saltzpyre Moonfire Bow uses crossbow 3P presentation

| Field | Check |
|---|---|
| Fix version | 0.12.225-dev (unverified candidate) |
| Automated | `/wt_regression_test`: `issue580_moonfire_saltzpyre_crossbow_3p_contract` passes. It checks the shared mission/preview predicate, all three non-Priest wield mappings, wh-scoped fire/aim remaps, target linking, and the vanilla 1P fingerprint. |
| Solo visual | On WHC, BH, and Zealot: equip Moonfire in the keep and mission, swap/stow, hip-fire, hold aim, and charged-fire. The body/preview shows Saltzpyre's crossbow and bolt while first person remains the Moonfire Bow. |
| Coop visual | A second peer observes each career spawn, equip/swap, aim, and fire. The remote husk must retain the visible crossbow and bolt. Repeat after joining in progress. |
| Reload/energy | Drain Moonfire energy and press reload during/after attacks. No crossbow gameplay reload or ammo behavior may replace Moonfire's vanilla energy transition; only the 3P presentation vocabulary changes. |
| Log evidence | One bounded `[wt:580] event=applied ... native_we_untouched=true remaps=3` line at template patch time. Existing `[wt sp-longbow-crossbow]` entry/swap/skip lines identify mission/husk swap results. |

## #536 - local 3P reload omission / wrong Elf Volley Crossbow receiver sequence

| Field | Check |
|---|---|
| Fix version | 0.12.224-dev (unverified candidate) |
| Automated | `/wt_regression_test`: `reload_3p_volley_contract_is_receiver_native` and `reload_3p_event_selection_matches_vanilla_precedence` pass. |
| Solo visual | In local 3P on WHC/BH/Zealot, fire and reload Elf Volley Crossbow. The body must visibly use the multi-stage volley-crossbow sequence, not the ordinary crossbow reload. |
| Native controls | Saltzpyre Repeater Crossbow and Kerillian's native Elf Volley Crossbow remain unchanged. Active reload does not double-play. |
| Coop visual | One WT player and one observer verify that origin and remote views both show the same volley reload without duplicate RPCs or crashes. |
| Log evidence | `[wt:536:reload]` reports receiver stance and target. `dispatch_unverified` / `local_3p_replay_dispatched` requires human visual confirmation; missing/rejected transitions are failures. |

## #576 - false-confirmed scythe / elf-spear Saltzpyre 3P chains

| Field | Check |
|---|---|
| Fix version | 0.12.223-dev (unverified candidate) |
| Automated | `/wt_regression_test`: `issue576_reopened_ports_and_action_chain_contract` and `issue411_dev_picker_source_events_resolve_live` pass. |
| Solo visual | Enable 3P Anim Picker. On WHC/BH/Zealot test every Reaper row and Elf Spear H1 from idle: hold through charge, then release. Both wind-up and committed strike must be visible. |
| Log evidence | `[wt:576]` separately records weapon/template/career, phase, source, target, origin and outcome. Spear H1 requires all four phase labels. `accepted_unverified*` is not a pass. |
| Catalog | Saltzpyre offers `es_2h_hammer` and excludes `dr_2h_hammer`; Reaper's animation target remains WP Greathammer SET A. |
| Confirmation gate | Do not return either key to `_CONFIRMED.saltzpyre` until every registered source event has explicit visual verification evidence. |

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to weapon_tweaker.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

Last updated: 2026-07-13.

---

### issue569-wp-remap-orientation - Standard Saltzpyre WP-remap weapons face forward

| Field | Value |
|-------|-------|
| Symptom | Non-native 3P weapons face backwards when standard Saltzpyre careers use `to_2h_hammer_priest`. |
| Root cause | The animation remap changes the body attachment-node orientation, while vanilla links weapon node 0 with no corrective local transform. Follow-up: Hold-Pose live apply rebuilt an absolute pose from slider values, so a position-only edit supplied identity rotation and erased the correction. |
| Fix version(s) | 0.12.221-dev; Hold-Pose composition follow-up 0.12.222-dev |
| Category | INTEGRATION / MULTIPLAYER |
| Repro | On standard Saltzpyre, wield two non-native families mapped to WP greathammer; observe locally and from another peer, then swap/stow. Enable Hold-Pose live apply; change only RH position Z while all RH rotations remain zero, then change only rotation and reset. |
| Expected post-fix | Wielded weapons receive one 180-degree local-Z correction. Position-only tuning preserves corrected rotation and scale; rotation-only tuning preserves canonical/baked position and scale; repeated frames do not compound; zero/reset restores baseline. Native WP greathammer, 1P, preview, and husk ownership boundaries remain correct. |
| Detection | `/wt_regression_test`: `issue569_wp_hammer_remap_orientation_scope` PASS. `[wt:569]` reports tracked exact weapon/career, correction state, and `hold-pose compose position=... rotation=... scale=preserved compounds=false`. |

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
| Repro | 1. Hand-write `itemV2.cfg` with `tags = [ ];`. 2. Run `vmblauncher upload <mod>` for first time. 3. Watch failure. |
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
| Fix version(s) | n/a — use `vmblauncher all` |
| Category | MANUAL |
| Repro | 1. Run `vmblauncher upload <mod>`. 2. Restart VT2. 3. Watch console show old version. |
| Expected post-fix | Use `vmblauncher all <mod>` (build + deploy + upload) during iterative dev. |
| Detection | After every upload, restart VT2; console version matches bumped MOD_VERSION. |


---

### feedback-deploy-vs-upload-distinction — Local deploy doesn't reach subscribers

| Field | Value |
|-------|-------|
| Symptom | Friend / subscriber still reports old behavior; only the author's local install is updated. |
| Root cause | `deploy_all.ps1` only copies to LOCAL workshop folder. Subscribers get the version on Steam, which needs `upload`. |
| Mod(s) | all |
| Fix version(s) | n/a — use `vmblauncher all` |
| Category | MANUAL |
| Repro | 1. Run `vmblauncher deploy <mod>` only. 2. Friend reports no change. |
| Expected post-fix | Use `vmblauncher all <mod>` for changes intended to reach subscribers. |
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
| Repro | 1. Hand-scaffold a new mod (skip `vmb create`). 2. Run `vmblauncher upload <mod>` without copying `item_preview.png`. 3. Watch failure. |
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
| Repro | 1. Set `MOD_VERSION = "0.9.9.1-revert"`. 2. Run `vmblauncher all <mod>`. 3. See Workshop title carry the descriptor. |
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

### issue587-baked-transform-husk-fanout — committed transforms reach remote husks

| Field | Value |
|-------|-------|
| Symptom | Kruber Scythe/Glaive baked grip is correct in owner 3P and preview but raw on another player's remote husk. |
| Root cause | Vanilla `SimpleHuskInventoryExtension._wield_slot` spawns husk equipment directly and never enters WT's `GearUtils.create_equipment` transform path; durable offsets also scanned only the local player. |
| Mod(s) | weapon_tweaker |
| Fix version(s) | wt v0.12.229-dev (#587) |
| Category | CO-OP / STATIC |
| Repro | Two WT peers: Player A equips Kruber Scythe and Glaive; Player B observes, then A swaps and respawns. Reverse roles. |
| Expected post-fix | Owner, bot, remote husk, and preview consume identical baked scale/position values. Scythe is +0.6 Z and Glaive +0.285 Z on Kruber; native Sienna and unmodified Kruber control remain vanilla. #569 rotation composes; 1P is untouched. |
| Detection | `/wt_regression_test` passes `issue587_baked_transform_husk_fanout`; bounded `[wt:587] tracked role=remote_husk ... transport=none` appears. No transform RPC/per-frame payload exists. |


---

### issue290-billhook-bake-merge — saved picks cannot delete receiver-facing events

| Field | Value |
|-------|-------|
| Symptom | Kruber equips Saltzpyre's Billhook but most or all 3P attacks have no visible body animation. |
| Root cause | The v0.12.203 bake assigned a five-row `es_` table over the complete Billhook-to-polearm map. Its keys were 1P `anim_event` names, while five actions emit their distinct `anim_event_3p` values to the body, so the replacement matched neither those actions nor the safety rows it deleted. |
| Mod(s) | weapon_tweaker |
| Fix version(s) | wt v0.12.230-dev (#290) |
| Category | STATIC / DIAGNOSTIC |
| Repro | On Kruber, equip `wh_2h_billhook`; perform full lights, both heavies, push, and special hook while watching 3P. |
| Expected post-fix | Baked picks overlay the complete receiver map. Every effective Billhook 3P event is remapped or native on the polearm body; 1P and native Saltzpyre remain untouched. |
| Detection | `/wt_regression_test` passes `issue290_billhook_kruber_effective_3p_complete`; bounded `[wt:290]` live rows are available only in the friends-only development stream. |


---

### wt-cim-widget-strip-removed - Dead CIM widget filtering stays removed

| Field | Value |
|-------|-------|
| Symptom | `weapon_tweaker_data.lua` scans loaded mods and recursively walks every settings widget, but can never match a target. |
| Root cause | Commit `a7012f3` removed the `cw_melee_traits` and `cw_ranged_traits` groups without removing their CIM detection/strip scaffold. |
| Mod(s) | weapon_tweaker |
| Fix version(s) | wt v0.12.217-dev (#218) |
| Category | STATIC |
| Repro | Load settings with or without Crafting in Modded; the old walk produced the identical widget tree. |
| Expected post-fix | No CIM detection/strip symbols or deleted group IDs remain in active wt data. Hidden default-true backend/UI/animation feature-flag labels remain documented and present. |
| Detection | `qa/check_rt_textual_invariants.ps1` enforces the four `#218` absence/presence invariants. |


---

---

### issue594-saltzpyre-hammer-shield-ownership

| Field | Value |
|-------|-------|
| Symptom | WT offers Bardin Hammer & Shield beside the more appropriate Kruber Mace & Shield on all three non-Priest Saltzpyre careers. |
| Root cause | The June shield-combo override added both native item keys even though the existing analogue policy already preferred the Empire pair. |
| Mod(s) | weapon_tweaker |
| Fix version(s) | wt v0.12.232-dev (#594) |
| Category | STATIC / OWNERSHIP |
| Repro | Open Weapon Availability for Witch Hunter Captain, Bounty Hunter, or Zealot and inspect shield-combo rows. |
| Expected post-fix | Kruber Mace & Shield remains; Bardin Hammer & Shield is absent. Old enabled settings cannot preserve `can_wield` or backend-cache ownership. CWV absent/active/disabled produces the same result. |
| Detection | Lua suite passes `test_wt_native_ownership`; `/wt_regression_test` passes `issue594_saltzpyre_hammer_shield_ownership`. |


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
- issue290-billhook-bake-merge
- issue587-baked-transform-husk-fanout
- issue594-saltzpyre-hammer-shield-ownership
- wt-cim-widget-strip-removed
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
