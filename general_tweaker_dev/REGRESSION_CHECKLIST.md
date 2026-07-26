# Regression Checklist — general_tweaker

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to general_tweaker.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

Last updated: 2026-07-26.

## Runtime regression module boundaries

- `general_tweaker_dev.lua` owns the runtime registry and command lifecycle;
  `_gt_regression_checks.lua` receives that registry plus the few private
  helpers its closures require, and registers checks in their historical
  order. Keep checks lazy: engine globals assigned by later-loaded modules
  must be resolved when a check runs, not while it is registered.
- `_gt_bot_fixes.lua` owns hook installation and bot-fix state;
  `_gt_bot_update_fixes.lua` owns the FIX1 per-frame update policies and the
  single `PlayerBotBase.update` dispatcher. Do not install a second update
  hook when adding a policy; route it through that dispatcher.
- Detection: offline `test_gt_regression_module.lua` protects registry order,
  dependency injection, and singleton bot-update ownership; the focused bot
  tests concatenate the owning module when checking moved runtime signatures.

## Startup-safe infinite ammo (#662)

- [ ] A persisted Godmode + Unlimited Ammo configuration produces no `Network backend has not been set` or `consumer 'infinite_ammo' raised` line before the Keep local player exists.
- [ ] The reconciler uses only the pcall-contained `local_player_safe` policy; it does not call the unsafe `PlayerManager:local_player()` API.
- [ ] Once ready, Godmode's ammo child remains local-only while `/infinite_ammo` remains host-wide; disabling either owner preserves the buff while the other still owns it.
- Detection: offline `test_gt_network_readiness.lua`; runtime `/gt_regression_test` ownership check `issue549_godmode_power_and_ammo`.

## Bot follow utility nil guard

- [ ] Every GT no-ally/suppressed-ally return preserves vanilla's numeric `math.huge` distance sentinel; `_update_target_ally` never receives nil from GT's selector wrapper.
- [ ] The exact `player_bot_default_follow` consideration repairs a missing `ally_distance` to `math.huge` before native arithmetic.
- [ ] An unrelated missing or non-numeric utility input returns zero utility for only that malformed action; no generic infinity value is written and valid actions delegate unchanged.
- [ ] Creature Spawner does not own or register `Utility.get_action_utility`; bot fixes contain the only GT hook for the pair.
- [ ] `/gt_regression_test` passes `gt_bot_utility_nil_guard`.
- Detection: offline `test_gt_bot_utility_policy.lua`; runtime check `gt_bot_utility_nil_guard`.

## Keep-slot bot takeover (#247)

- [ ] Bot Takeover works in ordinary bot-filled Adventure, Chaos Wastes, and Weave parties: one native bot yields its slot and is restored on reclaim. An already free slot needs no displacement.
- [ ] The owner enters the vanilla observer camera; disabling takeover removes only the temporary bot and returns the human through native `force_respawn`.
- [ ] A four-human party, dead/missing owner unit, keep, Versus, tutorial, or absent native API rejects before the human unit is despawned and restores the checkbox.
- [ ] A client cannot claim another peer or local-player id. Host result acknowledgements converge the client checkbox to the host's actual active state; reason strings are bounded and retries remain idempotent.
- [ ] AFK takeover fires after 20 seconds, input requests reclaim, and manual takeover is not cancelled by incidental input.
- [ ] `/gt_regression_test` passes `issue247_keep_slot_takeover_wired` and the client-send queue checks.
- Detection: offline `test_gt_ai_takeover.lua`; source rationale and two-player matrix in `AI_TAKEOVER_247.md`. Overall verification is co-op because the authenticated request/result path must be exercised.

## Failed-join popup ownership hardening (#72)

- [ ] `/gt_regression_test` passes `issue72_lobby_failnotify_never_hands_popup_to_vanilla` and the four existing `gt_lobby_failnotify_*` checks.
- [ ] The enriched popup id exists only in GT's private pending registry; `StateLoading._popup_id` remains nil throughout takeover, preventing vanilla and GT from racing to consume the same one-shot result.
- [ ] Initial queue failure still delegates to vanilla, and known, unknown, and Workshop actions still drive teardown exactly once.
- [ ] `qa/check_rt_textual_invariants.ps1` passes the #72 forbidden-assignment rule for `_gt_lobby_failed_join_reveal.lua`.
- [ ] `_gt_debug_probes.lua` wraps VMF's `mod.update(dt)` using a single `dt` argument and forwards that exact value to the central registry.
- Detection: offline `test_gt_lobby_failnotify_hardening.lua`; runtime check `issue72_lobby_failnotify_never_hands_popup_to_vanilla`; tier-a #72 absence invariant.

## Host bot command wheel (#359)

- [ ] The option defaults off; only the host sees the extra second wheel page, and disabling it removes that page on the next open.
- [ ] Attack Now uses the host's last living enemy ping for exactly 10 seconds and never adds a custom network event or lookup entry.
- [ ] Group Up and Cover Me override follow assignment for 8 and 12 seconds, then return to the configured vanilla/GT follow mode.
- [ ] Wait copies the social wheel's aimed world position, parks the selected bot within 4 m of it for 30 seconds, and never falls back to the player's feet; expiry clears only the matching GT-owned hold token.
- [ ] Revive, rescue, combat safety, scripted holds, and clients' social-wheel events remain authoritative and unmodified.
- Detection: offline `test_gt_bot_command_policy.lua`; `/gt_regression_test` checks `issue359_bot_command_wheel` and `issue600_wait_aim_and_duration`.

## Godmode HUD indicator (#381)

- [ ] Exact local Godmode ON shows one small `GODMODE` cue in the upper-right; OFF, nil, and non-boolean values draw nothing.
- [ ] Toggle-off removes the cue on the next HUD frame; no timer, stale latch, network state, or remote-peer state controls visibility.
- [ ] The indicator and Melee Attack Warning edge flash render together through the one `IngameHud.update` hook.
- [ ] Missing in-game renderer fails closed; clamped layout stays inside the 1920x1080 `hud_scale_fit` canvas.
- Detection: offline `test_gt_godmode_indicator.lua`; `/gt_regression_test` check `issue381_godmode_hud_indicator`.

## Smart bot Ranger ale use (#365)

- [ ] The child toggle defaults off and does nothing while Bot Behavior Improvements is off.
- [ ] Any active teammate below three `ale_defence` or `ale_attack_speed` stacks keeps every Ranger ale reserved for humans.
- [ ] Exactly 50% remaining is rejected; strictly above 50% for both sub-buffs on every active teammate permits a bot to claim the exact ale pickup.
- [ ] Ordinary greedy/instant pickup cannot bypass the gate; disabling the child revokes an outstanding smart exception on the next mule update.
- [ ] Census work is capped to the active side roster and cached for 0.5 seconds; no RPC or replacement consume action exists.
- Detection: offline `test_gt_bot_ale_policy.lua`; `/gt_regression_test` check `issue365_smart_bot_ale_policy`.

## Additional bot improvement families (#488)

- [ ] With Bot Behavior Improvements and its new child enabled, the first gas hit on a bot is unchanged; repeated hits within two seconds step through 20%, 40%, 60%, 80%, then 100% matching resistance.
- [ ] Gas and warpfire stacks remain independent; stacks expire individually at two seconds; humans, ordinary fire, friendly bombs, melee, and other damage are unchanged.
- [ ] `[gt:488] bot-hazard` logs only first/full milestones and never exceeds 16 rows.
- [ ] A shield bot facing a Ratling emits bounded `[gt:488] ratling-shield` rows showing melee/wielded capability, projectile-hit attribution, cover, and blocking state. Diagnostics do not change cover or request block.
- [ ] `/gt_regression_test` passes `issue488_bot_improvement_families`.
- Detection: offline `test_gt_bot_hazard_resistance`; source/runtime notes in `BOT_IMPROVEMENTS_488.md`. Hazard verification is solo; any later shield behavior is co-op.

## Localization lifecycle sync (#345)

- [ ] Closed issue references #65, #255, #261, #293, #295, #297, #448, #468, #492, #515, and #529 do not appear in General Tweaker's visible setting labels.
- [ ] Bot Behavior Improvements shows only `[verify-fix] [Issue 139, 142, 469 & 488]`; Follow snap-back distance shows only `[verify-fix] [Issue 139]` and no stale diagnostic marker.
- [ ] AOE immunity (#469), all heal-allies controls (#523), Improved Bot Combat (#298), and keep-dummy collision (#304) show `[verify-fix]` with their issue number.
- [ ] `qa/check_loc_tags.ps1` reports no player-facing lifecycle metadata.

## Improved Bot Combat advanced controls (#298)

- [ ] Master remains default-off; all children default-on and reproduce the former bundled behavior.
- [ ] Disabling a child delegates only its attack, ping, chase, gunner, boss, or ability hook family to vanilla.
- [ ] Meter sliders are squared exactly once: 7.1 m chase, 11.8 m gunner cover, and 15 m boss engagement by default.
- [ ] `BTBotMeleeAction.run` nil-weapon crash guard remains ungated.
- Detection: offline `test_gt_improved_bot_combat_controls`; `/gt_regression_test` check `issue298_improved_bot_combat_controls`.

## Bot heal-allies policy (#523)

- [ ] With the feature on, a bot carrying Medical Supplies selects a non-wounded human at 15% permanent health, but not just above it; setting the slider to 0 prevents ordinary top-off heals.
- [ ] A wounded human is eligible up to the separate 100% default threshold; lowering that threshold delays wounded healing independently.
- [ ] Non-wounded Zealot is excluded by default. Wounded Zealot remains eligible by default, and turning off Heal Zealot when wounded excludes that case too.
- [ ] Revive/rescue targets still outrank healing; Draughts never heal others; enemies nearby still block the native `can_heal_player` action.
- [ ] `/gt_regression_test` passes `issue523_bot_heal_allies_policy`; offline `test_gt_bot_heal_policy.lua` passes.

---

## Godmode outgoing damage and ammo (#549, supersedes #382)

- [ ] **[MULTIPLAYER]** Host and joining client each enable Godmode + 9999 Damage Per Strike; each positive enemy hit resolves as 9999 on the authoritative host.
- [ ] Friendly fire, self damage, immune zero-damage results, bots, and peers without the child toggle never receive the override.
- [ ] Godmode + Unlimited Ammo suppresses only the owner's ammo/overcharge consumption; disabling Godmode restores consumption even when the hidden child remains checked.
- [ ] `/infinite_ammo` retains its host-wide scope and composes by ownership: turning either source off does not remove the buff while the other remains active.
- [ ] `/gt_regression_test` passes `issue549_godmode_power_and_ammo`.

---

## Correlated aid/teleport diagnostics (#139, #384)

- [ ] In a two-human split, an aid-adjacent final follow change emits one `[gt:139:chain] FOLLOW` row with bot, old/new follow, side aid, need type, and #492 state.
- [ ] A blocked leash emits `[gt:139:chain] VETO` naming the same bot and aid ally; a teleport within three seconds emits one `TELEPORT` row with `veto_age`, `same_aid`, final selector/action follow, and bailout identity.
- [ ] Ordinary follow churn and ordinary teleports with no aid, recent veto, or bailout do not emit `[gt:139:chain]` rows.
- [ ] D1 `from`/`to` coordinates use immediate `Unit.world_position` and differ after a real snap; they no longer repeat the stale `POSITION_LOOKUP` value from the wrapped action.
- [ ] `/gt_regression_test` passes `issue139_aid_trace_correlation`; offline `test_gt_teleport_loop_policy.lua` passes.

## Close-range no-path teleport retry bound (#385)

- [ ] With a 15 m follow distance, a bot at a path-failure/no-return seam may execute one `vanilla_no_path` or `backward_no_path` unstick.
- [ ] While the bot remains below 15 m, another no-path teleport is suppressed for five seconds and emits one latched `[gt:385]` record rather than a per-frame flood.
- [ ] Outside the leash, after the retry window, and for ordinary `vanilla_40m` / `tighter_leash` branches, teleport behavior remains available.
- [ ] `[gt:btlab:d1]` names the exact no-path branch instead of `trigger=unknown`.
- [ ] `/gt_regression_test` passes `gt_bot385_close_no_path_retry_bound`; offline `test_gt_teleport_loop_policy.lua` passes.

---

## Noclip world-boundary death routes (#241)

- [ ] As solo host with noclip on, an authored kill volume logs `kill-volume instant death` once and does not kill the local player.
- [ ] As solo host with noclip on, flying below `z=-240` logs `host out-of-bounds suicide` once and does not kill the local player.
- [ ] **[MULTIPLAYER]** As a joining client with noclip on, repeat both tests; the deep-floor route logs `client out-of-bounds suicide RPC` once and the host does not kill the client.
- [ ] With noclip off, kill volumes, deep-floor death, and ordinary combat death remain vanilla; remote players are never protected by the local gate.
- [ ] `/gt_regression_test` passes `issue241_noclip_boundary_routes`.

---

## Godmode stagger and debuff trace (#548)

- [ ] With godmode enabled, direct boss/monster hits no longer launch the protected player.
- [ ] Troll Bile and any remaining debuff reproduction emits unique `[gt:548]` template names automatically, capped at 24 records for the session.
- [ ] With godmode disabled, ordinary hit stagger and buff application remain vanilla.
- [ ] `/gt_regression_test` passes `issue548_godmode_stagger_and_debuff_probe`.

---

## Closed-chest bot pickup probe (#347)

- [ ] As solo host with one bot, arm `/gt_chest_pickup_probe` beside one ordinary closed chest, wait, open it normally, and attach all `[gt:347]` records.
- [ ] The probe never opens the chest, assigns a pickup, or mutates a bot blackboard; the trace stops at 32 classifications or 16 phase-deduplicated records.
- [ ] Compare the availability census before/after opening, then use `assigned`, `nav_result`, `can_loot`, and `pickup_stop` to locate the first missing phase.
- [ ] `/gt_regression_test` passes `issue347_closed_chest_pickup_diagnostics`.

---

## Awaiting-rescue bot leash policy (#300)

- [ ] Parent toggle off: vanilla behavior remains unchanged and bots do not select awaiting-respawn allies through gt.
- [ ] Parent on + Ignore follow leash on (default): existing unlimited awaiting-rescue pursuit remains available.
- [ ] Ignore follow leash off + custom range off: pursuit is bounded by the active Follow snap-back distance.
- [ ] Ignore follow leash off + custom range on: the dedicated 10-100 m slider bounds the pick, including the exact boundary.
- [ ] Ordinary knocked-down, ledge, and hook rescues remain unchanged; no second hook or network field is introduced.
- [ ] `/gt_regression_test` passes `issue300_rescue_awaiting_range_policy`.

---

## Host disconnect lifecycle probe (#309)

- [ ] **[MULTIPLAYER]** Host runs `/gt_disconnect_grace_probe`, then one alive client disconnects and reconnects within 30 seconds.
- [ ] Host log contains bounded `[gt:309]` `pre_on_enter`, `post_on_enter`, six scheduled samples, and (when the same peer identity returns in-window) `rejoin`; total records never exceeds 10.
- [ ] The probe does not delay removal, add invulnerability, send an RPC, or otherwise change vanilla disconnect/bot-fill behavior.
- [ ] `/gt_regression_test` passes `issue309_disconnect_grace_diagnostics_armed`.

---

## Chaos Wastes creature-spawn queue diagnostics (#254)

- [ ] In a Chaos Wastes mission, one manual creature request emits one `[gt:254] phase=enqueue` row, at most one `phase=blocked` row, and exactly one terminal `phase=outcome` row.
- [ ] The terminal row identifies `spawned`, `left_queue_without_spawn_lut`, `timeout`, `director_replaced`, or bounded capacity eviction without per-frame output.
- [ ] A vanilla breed substitution records both the requested and effective queued breed; package readiness is classified against the effective breed.
- [ ] Adventure creature-spawn behavior and closed #693's client-to-host request path are unchanged.
- [ ] `/gt_regression_test` passes `issue254_deus_spawn_queue_diagnostics_armed`.
- Detection: offline `test_gt_creature_spawner_deus_queue_diag.lua`; runtime `[gt:254]` queue trace.

---

## Disconnect service failure diagnostics (#753)

- [ ] A Steam/client or P2P incident emits one transition line prefixed `[gt:753]`, not one line per update frame.
- [ ] Every line contains measured `steam_connected`, `backend_disconnected`, and `observed` fields; a `NetworkClient` failure also contains `reason` and before/after channel state.
- [ ] An unrelated `eac_authorize_failed` transition does not emit a `[gt:753]` P2P line.
- [ ] A PlayFab error that reaches `_is_disconnected=true` emits `edge=playfab_disconnect` with the last queued reason when one was observed.
- [ ] The probe never sends an RPC, changes a popup, retries a connection, or changes any teardown result.
- [ ] `/gt_regression_test` passes `issue753_disconnect_failure_diagnostics_armed`.

---

## Player-stat HUD and census diagnostics (#797)

- [ ] **Player stat HUD** is off by default. Enabling it shows career, wielded item/template/style, current action/sub-action/damage profile, and the fixed health/stamina/movement/cooldown/attack/critical/power/damage/defense families without chat/log spam or networking.
- [ ] Every consumer-effective supported row reconciles base plus displayed deltas to final. Authoritative health/stamina remainder is an explicit `unattributed-engine-delta`; exact downstream modifiers say `factor`, never `final`. `activated_cooldown` is labeled an activation factor and never appears as `max_cooldown * factor`, because the native call first consumes current cooldown, cost, refund, and optional modified cost. Movement says `UNSUPPORTED(stance/status/current_movement_speed_scale/player_speed_scale-dependent)` and never presents `PlayerUnitMovementSettings.move_speed` alone as effective.
- [ ] Stamina regen uses the live status getter as its denominator: six fatigue points produce an unbuffed `1.5 / 6 * 100 = 25` gauge-per-second base before `fatigue_regen`. If authoritative max fatigue is absent or non-positive, the row says `UNSUPPORTED(max-fatigue-unavailable)`.
- [ ] Current action time scale has separate chain/action (`is_animation=false`) and animation (`is_animation=true`) rows. Both compose action base, generic, weapon-family, and drakefire transforms; charge time follows the exact `scale_chain_window_by_charge_time_buff OR (scale_anim_by_charge_time_buff AND is_animation)` truth table. The action-settings critical row composes career/action/melee-or-ranged/heavy/generic stages, while effective critical chance says `UNSUPPORTED(runtime-overrides-unobservable)`. Target/profile/difficulty-dependent power and proc/action-dependent push/dodge finals also say `UNSUPPORTED(reason)`.
- [ ] Expanded rows retain the exact native stage key plus active parent/child buff identity; collapsed root stages say `root-aggregate` rather than inventing per-source arithmetic. Proc, conditional, function/table multiplier, and missing-base paths are never evaluated through the engine.
- [ ] Compact shows eight high-value families. Expanded pages expose every family, consumer, and wrapped contribution with `/gt_stat_hud_page`; no generated text clips horizontally or hides behind a fixed page cap.
- [ ] Bottom-left/right anchors remain outside the top-left bot HUD and top-right Godmode indicator occupancy. The renderer uses standard colors and no hardcoded panel chrome.
- [ ] `/gt_stat_hud_metrics` shows 4 Hz bounded samples, provenance rebuilds only on unit/equipment/action/buff edges, formatting only when values change, and bounded row/line allocations. Stat/stage/source truncation is visible and absent rows fail closed.
- [ ] Toggle-off, mod disable, game-state transitions, native health/status death (including while `Unit.alive` is still true), and a missing local extension immediately clear the cached panel without retaining a GUI/world handle.
- [ ] `/gt_regression_test` passes `issue797_player_stat_hud`.
- [ ] `/gt_stat_probe` writes one `[gt:797]` census to the engine log and never echoes diagnostic output into chat.
- [ ] `/gt_stat_trace` writes exactly five bounded samples at 0, 0.25, 1, 3, and 10 seconds, then terminates.
- [ ] Each sample reports career, item/template/style, action/sub-action/profile, reconciled values, exact factors, exact stage/source identity, and unsupported reasons without calling `apply_buffs_to_value`.
- [ ] Death, respawn, career/equipment transitions, or a missing extension produce a bounded `skip=` row rather than an error or retained engine handle.
- [ ] `/gt_regression_test` passes `issue797_player_stat_diagnostics_armed`.
- Detection: offline `test_gt_player_stat_probe.lua`; runtime commands `/gt_stat_probe` and `/gt_stat_trace`; `/gt_regression_test` checks `issue797_player_stat_diagnostics_armed` and `issue797_player_stat_hud`; source owner `docs/engine/10_damage_buffs_and_talents.md`.

---

## Keep dummy player collision (#304)

- [ ] With the toggle off (default), a keep training dummy blocks the local player as vanilla does.
- [ ] With the toggle on, the local player walks through the dummy while hit markers/damage readout and all authored hit zones still work.
- [ ] Turning the toggle off restores blocking immediately; enemies outside keep-type levels are unaffected.
- [ ] `/gt_regression_test` passes `gt304_keep_dummy_constraint_scope`.

---

## Debug Highlights local renderer (#302)

- [ ] With Debug Highlights + Interactables enabled in the keep, `[gt:302] invocation=IngameHud.update active` appears and yellow projected wireframes render locally.
- [ ] No wireframe data is sent to peers; #534 networking remains limited to host-exclusive bot-leash positions.
- [ ] `/gt_regression_test` passes `gt_dh_hud_update_invocation_302`.

---
## Multiplayer / Network Sync

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

## Localization / UI

### vmf-dropdown-options-mutated — Multi-angle-bracket cascades from shared options table

| Field | Value |
|-------|-------|
| Symptom | VMF dropdown shows `<<key>>` or `<<<key>>>` cascades on second/third dropdown sharing an options table. |
| Root cause | VMF's `localize_dropdown_data` mutates `option.text` in place. Two dropdowns referencing the same options table get the first localized; the second tries to localize the already-localized string. |
| Mod(s) | enemy_tweaker, career_tweaker, **general_tweaker (Choose Grail Knight Quests — 3 shared dropdowns)**, any mod with multiple dropdowns of the same option set |
| Fix version(s) | enemy_tweaker v0.4.2-dev, crt v0.2.18-dev (talent-swap dropdown cascade), **gt_dev v0.2.96-dev (`_gt_gk_quest_options()` factory + loc keys; guarded by `_rt_register("gk_quest_dropdowns_dont_share_options")`)** |
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

## Engine / Crash Safety

### vt2-world-liveness-lineobject-cleanup — Cached LineObject cleanup dispatches into a destroyed world (Leave Game AV)

**[CRASH]**

| Field | Value |
|-------|-------|
| Symptom | Deterministic C-level access violation (0xc0000005) on host Leave Game with a debug-draw overlay on. No Lua crash block; pcall does not help. |
| Root cause | `StateIngame.on_exit` nils `Managers.player.is_server` (player_manager.lua:180) before `_teardown_world` destroys the level world (state_ingame.lua:719); VMF mods_update keeps ticking between states, so the overlay's cleanup path called `LineObject.reset`/`dispatch` on freed handles. Companion: `WorldManager.world()` fasserts on a missing world (world_manager.lua:111-115), so bare `world("level_world")` reads on mod-update paths are also fatal. |
| Mod(s) | general_tweaker (`_gt_bot_teleport_lab.lua` `_clear_and_null`, `_gt_debug_highlights.lua` `_clear`, plus `has_world` probes in `_do_draw`/`_world()`/`_gt_solo_qol.lua`/`_gt_melee_warning.lua`) |
| Fix version(s) | gt_dev v0.2.196-dev (issue 459) |
| Category | UNIT (`/gt_regression_test` check `gt_459_lineobject_cleanup_liveness_gated`) + MANUAL |
| Repro | 1. Host a run (CW or adventure). 2. Enable Dev Tools bot HUD or leash lines (or debug highlights). 3. Leave Game from the pause menu. |
| Expected post-fix | No crash; console log shows `[gt:459] skipped LineObject cleanup - cached world is dead` once per teardown. Engine cleanup calls run only when the live `level_world` is IDENTICAL to the cached handle (`live == w`); cached fields are always nulled. |
| Detection | `/gt_regression_test` fails if either cleanup site loses the `live == w` identity gate. See repo `docs/BUG_CLASSES.md` class 32. |


---

## Slugs

- feedback-deploy-vs-upload-distinction
- feedback-mod-version-format
- feedback-pre-deploy-checklist
- feedback-redundant-safeguards-ok
- feedback-search-changelog-for-known-crashes
- feedback-workshop-upload-verify
- feedback-workshop-upload-without-deploy
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
- vt2-world-liveness-lineobject-cleanup
