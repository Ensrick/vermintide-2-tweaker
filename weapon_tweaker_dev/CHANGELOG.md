# Weapon Tweaker Changelog

## 0.12.275-dev (2026-07-17) - #661 reconciliation build: both parallel fixes [verify-fix]

- Runtime-parity mirror of weapon_tweaker 0.12.274-beta: carries BOTH parallel #661 changes - the shared library's private-clone action ownership (below) and the inject-site clone-identity restore in `_inject_career_actions` (canonical `ActionTemplates` identity restored on mismatched career-action rows before install; residual conflicts report `conflict:<action>@<template>`). Two different builds were briefly uploaded as the prior version pair by parallel sessions; this version is unambiguous.

**Solo verify:** as 0.12.274-beta.

## 0.12.274-dev (2026-07-17) - #661 private-clone action ownership [verify-fix]

- Mirrored beta 0.12.273's provider-neutral clone-preparation contract while
  preserving the friends-only tuning overlay and `wt_dev` namespace.
- Private providers can now discard copied donor claims and canonicalize only
  source-proven inherited career actions before WT claims the same row.
- Repeated preparation is inert; unproven or later foreign replacements remain
  conflicts and provider release remains exact-owner safe.

**Solo verify:** With CWV enabled, wield a CWV weapon on Bardin and Kruber and
use each career ability before and after swapping weapons. `/wt_regression_test`
must pass without `conflict:action_career_dr_3` or
`conflict:action_career_es_4`.

## 0.12.273-dev (2026-07-17) - #661 career-action reconciliation [verify-fix]

- Reconciled every career action after the deferred post-CWV availability pass, including alternate ability rows.
- Added identity-safe provider claims so WT cleanup cannot delete native, replaced, or still-required CWV/WOC action rows.
- Expanded engine-free coverage for late registration, repeated reconciliation, release order, replacement, and conflicts.

**Solo verify:** equip cross-character weapons on at least two careers, use every career ability before and after a weapon swap, and run `/wt_regression_test`. Abilities must remain usable and career-action checks must pass.

## 0.12.272-dev (2026-07-17) - runtime-check module boundary (#2) [tooling]

- Moved the runtime regression and verification catalogue behind one explicit installer while preserving all dev-only checks, their order, and command ownership.
- Reduced the entry point below its frozen size ceiling and retained byte-normalized public/dev parity for shared behavior.
- Added focused coverage for module loading, registration counts, and the availability-sort verifier.

## 0.12.271-dev (2026-07-17) - #664 Executioner's Sword light-headshot parity [verify-fix]

- Mirrored public beta 0.12.270's default-off **Executioner's Sword: +30% Light Headshot Damage** toggle into the friends-only development stream without changing the dev animation/hold-pose overlay.
- Every Executioner's Sword light sweep uses a private, deterministic, #431 parity-gated profile and receives an exact 1.30x final-damage multiplier only when VT2 classifies the hit as a headshot. Body hits, heavies, speed, stagger, cleave, critical chance, and armor interaction remain unchanged.
- Added the shared offline and `/wt_regression_test` coverage for every-light scope, exact multiplier, profile isolation, parity hold, repeated-toggle idempotence, and exact restoration.

**Verification (in-game):** Compare light headshots, body hits, and both heavies with the option off/on/off, then run `/wt_regression_test`. Only light headshots should rise by exactly 30%, and `issue664_executioner_light_headshot_boundary` should PASS.

## 0.12.270-dev (2026-07-17) - #611 [verify-fix] gear-style availability master parity

- Mirrored beta's advanced-options Weapon Availability masters into the friends-only dev stream without changing the animation/pose tuning overlay.
- The visible master checkbox selects/clears its exact source-character set; its gear exposes the individual weapon rows for partial manual selection. Partial choices remain enabled while the derived master stays off.
- Preserved per-career scope, melee/ranged separation, requested source order, and bounded repaint. Expanded offline and runtime contracts reject flat duplicates or missing gear children.

## 0.12.269-dev (2026-07-17) - complete cross-career ability actions

- Mirrored the public beta's provider-neutral career-action integration while
  preserving the friends-only animation and hold-pose tooling overlay.
- Every enabled native port and CWV template now receives every weapon-bound
  activated-ability row, including Waywatcher's alternate piercing action;
  incomplete providers emit one bounded runtime error instead of silently
  leaving a weapon unable to activate an ultimate.

## 0.12.268-dev (2026-07-16) - #611 [verify-fix] per-career master parity

- Mirrored the public beta's redesigned Weapon Availability masters into the friends-only runtime stream without changing the development overlay.
- Masters now live inside each receiving career's Melee/Ranged subgroup, affect only that career, and appear in the fixed source order Kruber, Bardin, Kerillian, Saltzpyre, Sienna.
- Changing one child recomputes only its corresponding career/slot/source master. Master labels use GUI Tweaker's established warm-tan dropdown-heading color through VMF's supported checkbox-widget style.
- Kept `_wt_master_toggles.lua` byte-identical between beta and dev and expanded offline plus `/wt_regression_test` coverage for scope, order, cascade, targeted recompute, seeding, and styling.

## 0.12.267-dev (2026-07-16) - issue 611 Weapon Availability master toggles

- Runtime-parity refresh of the public beta's issue 611 master toggles. Each receiving character's Melee and Ranged group starts with "Enable All &lt;Character&gt; Melee/Ranged Weapons" masters, one per source character present; a master enables or disables its whole set in one click, and deselecting any covered weapon flips its master OFF while leaving the rest as-is.
- Source character is read from each weapon's display label (dev status tags stripped first), so ports whose owner differs from the key prefix group under the character the player sees. Child sets are built after the sort and Career Weapon Variants strip, and each master is reconciled to its children at load.
- Added `/wt_regression_test` check `issue611_master_toggle_wiring` covering the master/children maps, the reverse index, per-child source-label grouping, and localization ownership.

## 0.12.266-dev (2026-07-15) - #635 preserve the development overlay

- Kept the live 3P Animation Picker, Hold-Pose tuner, port-status decoration, tuning diagnostics, and their regression coverage in the friends-only `wt_dev` stream while the public beta removes them.
- Kept the bounded #290 Billhook and #316 Longbow live probes in this friends-only stream while removing their hooks, output, and owner module from public WT.
- Added a blocking stream contract that compares every common runtime file exactly after removing uniquely paired, self-tested overlay blocks. It rejects unmarked gameplay drift, malformed markers, and any dev-surface leak into public WT.
- Gameplay behavior is unchanged from `0.12.265-dev`; this bump identifies the separately rebuilt, deployed, and uploaded development stream.
- Removed the retired Kruber Longbow zoom-controls claim from this stream's Workshop feature list.

## 0.12.265-dev (2026-07-15) - #634 restore the friends-only dev stream

- Rebased the `wt_dev` runtime on the complete `0.12.264-beta` public baseline, including every modularized weapon, animation, appearance, diagnostics, and regression subsystem.
- Preserved the separate `wt_dev` VMF/settings namespace, friends-only Workshop item `3748824853`, dev preview image, and live animation/hold-pose tuning controls.
- Added a blocking stream-parity gate: future beta changes must reach dev unless the difference is an explicitly documented stream identity or presentation field.

## 0.12.139-dev (2026-07-14) - #433 remove dead Big Rebalance payload [not deployed]

- Mirrored stable WT's retirement cleanup: deleted the unreachable Big Rebalance implementation and definitions (165,617 bytes total), its no-op lifecycle dispatch, and its dead-only true-flight regression helpers/checks.
- Active dev animation tooling and all normal WT features remain unchanged. Saved `br_*` values are preserved and their identifiers remain reserved.
- Repository-only verification: retired-BR absence gate, WT-dev lint, Lua tests, and Quick QA. No in-game behavior existed to verify.

## 0.12.138-dev (2026-07-13) - #321 retire stale Big Rebalance product surface [not deployed]

- Big Rebalance remains intentionally unloaded and its `br_*` options remain hidden; the Workshop description no longer advertises the retired `bt` integration.
- Saved legacy values remain ignored and reserved. The repository-wide retired-BR gate prevents an active widget/module load from returning accidentally. Tag `[verify-fix]`.

## 0.12.137-dev (2026-06-28) — Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.12.132-dev (2026-06-19) — CRITICAL multiplayer fix: anim-event RPC feedback loop (every player's 3P stuck on endless repeat)

### Fixed (game-breaking, multiplayer)
A/B-confirmed: with wt enabled, in a 2+ human lobby **every** player's 3P animation was stuck on an endless repeat/loop, on **every** weapon. Disabling wt cleared it instantly.

**Root cause:** the `AnimationSystem.anim_event_with_variable_float` crash-guard hook (added v0.12.128, `weapon_tweaker.lua:2510`) **dropped vanilla's 6th parameter `skip_sync`**. The networked-anim RPC receiver (`rpc_anim_event_variable_float`, `animation_system.lua:312`) replays a received event with `skip_sync=true` precisely so it does **not** re-broadcast. With `skip_sync` omitted from the hook signature, `func(...)` was called with only 5 args → `skip_sync=nil` → vanilla's `if not skip_sync and Managers.state.network:game()` (`animation_system.lua:140`) re-sent the RPC. So **every husk that received a variable'd anim event re-broadcast it → infinite host↔client RPC feedback loop**, re-firing the animation every network tick. Only manifests in a network game with ≥2 humans (needs a peer to bounce the RPC with) — hence "only in a lobby with another player," all humans, every weapon, solo immune.

**Fix:** thread `skip_sync` through the hook signature and pass it to `func` unchanged, so husk replays stay local (`skip_sync=true`) as vanilla intends. The find-variable crash guard (the hook's original purpose — prevents the `es_bastard_sword`-charged-on-non-native `animation_set_variable(nil)` crash) is untouched.

> v0.12.128–v0.12.131 (the crash guard + its drop-vs-fire-bare tuning, from the memory-leak thread) shipped without CHANGELOG entries; this entry documents the regression they introduced and its fix.

## 0.12.127-dev (2026-06-19) — Anim confirmed: Saltzpyre Billhook on all Kruber careers

Flipped `unlock_es_{mercenary,huntsman,knight,questingknight}_wh_2h_billhook` to `[confirmed working]` (user-verified in-game). Per-receiver this time (Kruber only) — Kerillian receivers stay `[untested]`. See `TESTING_STATUS.md`.

## 0.12.126-dev (2026-06-19) — Forced-GC leak test on mission exit (lua_heap diagnosis)

INSTRUMENT ONLY. The host log already revealed the real mechanism via the existing per-state heap sampler: the Lua heap **ratchets up per mission** (≈150 MB keep baseline → 513 MB mission 1 → 311 MB after exit → 699 MB mission 2 — i.e. each mission loads ≈365 MB and ≈160 MB of it is NOT freed on exit). wt's own per-transition apply is only +6 KB, so it's not wt's direct allocation — it's that something during the mission isn't released. The one thing the live sampler couldn't answer (it deliberately never forces GC) is whether that un-freed heap is a true retained-reference **leak** or just collectable garbage. This adds a forced `collectgarbage("collect")` on `StateIngame/exit` that logs `reclaimed garbage` vs `survives GC` — if "survives GC" climbs each mission, it's a real leak to hunt; if it returns to baseline, it's GC pressure. Debug-gated (`enable_debug_logging`). Combine with 0.12.125's boot breakdown.

## 0.12.125-dev (2026-06-19) — Per-subsystem boot mem-probes (lua_heap-cap diagnosis)

INSTRUMENT ONLY (no behavior change) — to find what actually drives wt's Lua-heap footprint instead of guessing. Added ungated boot `[mem-probe]` lines that print the lua delta of each heavy subsystem on one boot:
- `wt weapon_backend: +X MB` — the backend dofile, which the existing `boot_lua` total never counted (baseline is set *after* it).
- `wt_dev_anim catalog+vocab: +X MB (N entries)` — the dev anim picker's dynamic catalog + skeleton vocab, built at boot (`_ensure_catalog_built`).
- `wt_dev_anim widget_tree: +X MB (N char groups)` — the per-pair dropdown tree VMF holds.
- `wt_dev_anim loc_keys: +X MB (N strings)` — the option-text loc strings (two per vocab value per entry).

All `[picker-only]` subsystems are resident at boot for every player even if they never open the picker — the suspected baseline-raiser that leaves less headroom for the per-mission force-load spike. Boot once with the log open; the breakdown tells us exactly where the heap goes, then we cut it.

## 0.12.124-dev (2026-06-19) — Animation test-status labels in the weapon availability menu

Prefixed the cross-character weapon entries in the availability menu with `[untested]` (the 3P-animation testing surface) and `[confirmed working]` for verified weapons, so we can track what's animation-ready for release. Same-character entries (native skeleton — animations work by default) are left unlabeled, as are group headers. 633 cross-character entries labeled `[untested]`; **Kerillian: Spear** (`we_spear`) and **Saltzpyre: Axe** (`wh_1h_axe`) marked `[confirmed working]` across all receivers (15 entries). See `TESTING_STATUS.md`.

## 0.12.123-dev (2026-06-19) — Warrior Priest punch buff (Reckoner Greathammer special): 3x stagger, 2x damage

### Added
- **`wt_priest_punch_buff`** (Weapon Overrides group, default OFF) — triples the stagger and doubles the damage of the Warrior Priest 2h hammer's **special attack**, the punch (`attack_slam`, reached via the weapon's push-stagger special). The punch action on `Weapons.two_handed_hammer_priest_template` vanilla-points at the shared `light_blunt_smiter_stab` damage profile; since that profile is shared with other weapons, we register a **private cloned profile** `wt_priest_punch_buffed` with the punch's damage (`power_distribution.attack ×2`) and stagger (`power_distribution.impact ×3`) scaled on its `default_target` + `targets`, then repoint only the punch action's `damage_profile` at it while the toggle is on (restoring the original key when off).
  - Profile is registered into `NetworkLookup.damage_profiles` **unconditionally at load** (same determinism rule as `wt_authentic_pistol`, PROJECT_STANDARDS §9.3) so a host with the toggle on and a client with it off don't diverge on the network index. Only the action repoint is gated.
  - Regression: `wt_priest_punch_buff_wired` (profile registered + in NetworkLookup + default_target scaled 2×/3×).

## 0.12.120-dev (2026-06-17) — Crash fix: universal attachment-node guard (Skullsplitter + tome on Kruber); remove Kruber Longbow zoom toggles

### Crash fix — `j_rightweaponcomponent11` engine-fatal on equip
Reported 2026-06-17 (GUID 459bd95e): equipping **Skullsplitter + a tome on Kruber Mercenary** hard-crashed the hero-view weapon preview with `[Script Error] j_rightweaponcomponent11`. Root cause: `GearUtils.link_units` runs `Unit.node(source, link.source)` per attachment link (`gear_utils.lua:293-308`), and `Unit.node` is **engine-fatal on a missing node** (bypasses pcall). The tome sub-unit's linking maps its `j_page_nr*` nodes onto `j_rightweaponcomponent11-14`, which Kruber's body lacks in this cross-character context. The existing per-spawn guard (`_wt_validate_attachment_sources`) only covers the weapon's own `.third_person` linking; a sub-attachment carries its **own** flat linking table that never passes through that hook (confirmed via the two distinct table addresses in the crash locals).
- **Fix:** new hook on `GearUtils.link_units` (the universal choke point — `GearUtils.link` calls it via the table) that **drops any link whose source/target node is absent** before the engine reads it. Purely subtractive — valid links (nodes present) are untouched, so it can't regress visibility (unlike the v0.12.112/.113 global-mutation bug that broke elf bows). Catches preview **and** in-mission, for every weapon/sub-attachment. `WT_LINK_UNITS_NODE_GUARD_MARKER`.
- Filter logic factored into a pure, engine-free `mod._wt_link_filter` with a new `/wt_regression_test` check **`link_units_node_guard`** (drops missing-node links, keeps present ones, zero-copy on the all-present path).

### Removed — Kruber Longbow zoom toggles
Removed the `kruber_longbow_disable_zoom` / `kruber_longbow_manual_zoom` settings and the `_patch_kruber_longbow_zoom` patcher (lua + `_data` + `_localization`). The Kruber Longbow keeps vanilla zoom behavior. (The unrelated longbow **3P model swap** for cross-character is untouched.)

## 0.12.119-dev (2026-06-11) — Flaming Flail wield redirect (fixes broken wield stance on non-Sienna); /wt_coverage skeleton probe

### Why
Two items off the new ANIMATION_COVERAGE.md walk list that don't need an in-game tuning session:
- **Flaming Flail (bw_1h_flail_flaming) on non-Sienna receivers** had a broken wield stance — the H2 attack redirect existed but the wield event didn't (the exact gap DECISIONS:36 flagged as needs-fix). 🧊 on both the Kruber and Kerillian rows.
- No in-game probe existed to bulk-answer "which of this character's ports have authored 3P events?" — deriving coverage was a manual `/animlog` + `/dump_actions` + eyeball walk per port.

### Changed
- **`weapon_tweaker.lua` (`_career_anim_redirect`):** `to_1h_flail_flaming → to_1h_flail` for non-`bw_` careers (Sienna keeps her native event; `wh_priest` override → `to_1h_hammer`, consistent with the table's other entries). `to_1h_flail` is the universal Empire-flail wield already proven on every character via es_1h_flail. **Needs in-game verify** — flipped to 🔧 in ANIMATION_COVERAGE.md.
- **`wt_dev_anim_picker.lua`: new `/wt_coverage` command** (PROJECT_STANDARDS §3.7 data harness): for the CURRENT character, walks every catalog port and reports wield + per-action `anim_event_3p` authored-ness against the live 3P skeleton — one parseable `[wt:coverage]` line per port, FULL/PARTIAL/NONE summary. One command per character refreshes the coverage matrix statuses. (Authored ≠ visibly plays in chain states — final word stays with the eye.)

## 0.12.118-dev (2026-06-11) — Anim picker: tuned picks now survive restart (boot re-apply); two display-name mislabels fixed

### Why
The user's animation workflow is: tune a port's 3P picks in the dev Anim Picker menu in-game, verify by eye, then have the values baked into source. The structural hole (2026-06-11 system audit): picks applied live via `on_setting_changed` and persisted in the VMF store, but **nothing replayed them onto `Weapons.*` at boot** — every tuned port silently reverted to patcher/template defaults on restart until baked. That made the picker a one-session scratchpad instead of the intended tune→persist→export→bake loop.

### Changed (`wt_dev_anim_picker.lua`)
- **`M.reapply_stored_picks()`** — called from `M.install()` (end of main wt.lua, AFTER all template patchers): walks `_setting_index` and re-applies every stored pick onto the live templates via the same `_apply_wield_change`/`_apply_anim_event_change` paths as a live menu change. Logs an ungated one-line summary (`N stored pick(s) applied`) so the user can confirm their tuning is live without Debug Logging.
- **Only user-CHANGED settings re-apply.** Each `_setting_index` rec now captures its build-time `default_value`; a stored value equal to it is skipped. Load-bearing guard: widget defaults are captured at `_data.lua` time (BEFORE the main-file template patchers run), so blindly re-applying everything would overwrite patcher output with stale pre-patcher state — exactly the brace/longbow/repeating-pistol ports.
- **Display-name mislabel fixes** (`_WEAPON_NAME`): `we_deus_01` = **Moonfire Bow** (was "Deus Greatsword") and `we_life_staff` = **Deepwood Staff** (was "Moonfire Bow"). The per-character `*_deus_01` keys are the CW weapons; the old labels would have routed tuning decisions at the wrong weapon.

### Notes
- The tuned values remain session-layer until exported (`/wt_dump_anim_picks`, paste-ready `_WIELD_3P`/`_ANIM_REMAP_3P` blocks) and baked into the patcher tables — boot re-apply makes the interim state survive restarts, it does not replace baking.

## 0.12.117-dev (2026-06-08) — BR true-flight extra-shot gating matches vanilla; regression harness gets a skip channel (Issue #74)

### Why
Issue #74 follow-through from the 2026-06-08 re-review:
- The BR true-flight `fire` reimpl gated `set_shooting()` / ammo / overcharge / energy on `self.extra_buff_shot`, which is only ever assigned `false` — so under extra-shot buffs (Waywatcher +projectile talent, extra-shot procs) the free extra projectiles also bumped spread state and charged ammo/overcharge where vanilla skips them.
- `/wt_regression_test` counted `"skip: ..."` returns as FAIL, polluting the failure count whenever game tables weren't loaded yet.

### Changed
- **`weapon_tweaker_big_rebalance.lua`:** new file-scope `mod._wt_tf_is_extra_shot(i, num_projectiles, num_extra_shots)` implementing vanilla's per-projectile test exactly (`extra_shots_idx = num_projectiles - num_extra_shots + 1; is_extra_shot = extra_shots_idx <= i`, action_true_flight_bow.lua:128,132). All four gates (set_shooting / ammo / overcharge / energy) now key off it. Also tidied the mangled-but-equivalent `shot_count_offset` ternary to vanilla's form (action_true_flight_bow.lua:137).
- **`weapon_tweaker.lua`:** `/wt_regression_test` runner gained a SKIP channel — `"skip: <reason>"` returns are echoed and counted separately, no longer FAIL. Summary line now reports passed/failed/skipped.

### Tests
- `wt_br_trueflight_extra_shot_gating_matches_vanilla` — pins vanilla's truth table (0 extras → none flagged; 5 projectiles / 2 extras → exactly i=4,5 flagged; nil extras behaves as 0).

## 0.12.116-dev (2026-06-08) — Fix BR true-flight speed falloff sign-flip (projectiles 2+ fired backwards)

### Why
Post-ship re-review of the v0.12.115 audit fixes (fresh-eyes verification pass, 2026-06-08) found a pre-existing bug two lines below the audited `extra_buff_shot` gate in the BR true-flight `fire` reimpl: the per-projectile speed falloff was the **sign-flip** of vanilla — `speed = speed * (i * 0.05 - 1)` instead of vanilla's `speed = speed * (1 - i * 0.05)` (`action_true_flight_bow.lua:152`). For every projectile after the first (i ≥ 2) the multiplier is negative (i=2 → −0.9×), so with `br_hook_trueflight_fire` enabled, multi-projectile fires (Waywatcher extra-projectile talent, extra-shot buffs) launched projectiles 2+ **backwards at negative speed**. Present since the reimpl landed (~28 versions).

### Changed
- **`weapon_tweaker_big_rebalance.lua`:** falloff factored into `mod._wt_tf_projectile_speed(speed, i)` (file scope, NOT inside the master-gated hook installer, so it exists even with BR off) implementing vanilla's formula; the fire loop now calls it.

### Tests
- `wt_br_trueflight_speed_falloff_matches_vanilla` — asserts i=1 passes through unmodified, i=2 matches vanilla's 0.9× exactly, and i=2..5 all stay positive (the sign-flip made them negative).

## 0.12.115-dev (2026-06-07) — Audit fixes: brace damage-profile peer-index divergence, bot loadout arg, true-flight dead branch, dead loc keys

### Why
Repo-wide audit (2026-06-07). (Note: the CHANGELOG had drifted — MOD_VERSION was at 0.12.114-dev with no entries since 0.12.95-dev; this entry brings the head current. The .96–.114 gap is pre-existing and out of scope.)

### Changed
- **`weapon_tweaker.lua` ~2807 (HIGH, MP):** the `wt_authentic_pistol` custom damage profile was registered into `NetworkLookup.damage_profiles` only inside the toggle-gated `_apply_authentic_brace_mode()`. Per `PROJECT_STANDARDS §9.3` (gated-registration divergence), a host with the authentic-brace toggle ON and a client with it OFF get **different network indices** for that profile → `NetworkLookup` strict `__index` crash ("Table damage_profiles does not contain key") or silent wrong-damage decode when a networked brace shot resolves on the other peer. Now registers the profile **unconditionally at load** (`_wt_clone_shot_sniper_no_dropoff()` is idempotent; same load timing); only the template patching stays toggle-gated. **Residual:** full cross-*mod-set* determinism (peer also runs CWV/other NetworkLookup appenders vs not) still needs routing through bt's shared sorted registry — tracked as a follow-up.
- **`weapon_tweaker_backend.lua` ~170 (MEDIUM):** the `get_loadout_item_id` hook dropped vanilla's 4th `is_bot` arg (`backend_interface_item_playfab.lua:512`) on both fall-through calls, so bot loadout lookups silently used the player-default path. Now threads `is_bot` through and only answers the modded cache for the local player (`not is_bot`); bot queries fall through to vanilla.
- **`weapon_tweaker_big_rebalance.lua` ~2503/2529 (LOW):** the BR `ActionTrueFlightBow.fire` reimpl declared an `add_spread` 2nd param that vanilla never passes (`action_true_flight_bow.lua:121` is `fire(self, current_action)`), so its `if add_spread then spread_extension:set_shooting() end` branch was dead — spread "shooting" state was never set on true-flight fires. Dropped the vestigial param; gate on the reimpl's own `not self.extra_buff_shot` to match vanilla (`action_true_flight_bow.lua:143`).
- **`weapon_tweaker_localization.lua` ~1064 (cleanup):** removed 6 orphan loc strings for long-deleted settings (`enable_weapon_unlocks_core`, `enable_weapon_runtime_guards`, `enable_weapon_wield_slot_guard`, `enable_weapon_create_equipment_guard`, `enable_weapon_career_action_injection`, `force_bretonnian_shield_unlock`) flagged by `qa/check_name_integrity.ps1`.
- MOD_VERSION → 0.12.115-dev.

### Tests
- `wt_authentic_pistol_profile_registered_unconditionally` (`/wt_regression_test`) — asserts `wt_authentic_pistol` is in `DamageProfileTemplates` + `NetworkLookup.damage_profiles` regardless of the toggle. Fails if the registration is ever re-gated.
- `is_bot` passthrough and the true-flight gate are not cleanly keep-testable (need a live bot loadout / the BR true-flight path) — verify in-game per below.

### To verify
- **MP (needs 2 clients):** host with authentic-brace ON, client with it OFF, fire the brace at an enemy near the client — no `damage_profiles` crash and damage is correct. This is the load-bearing one; **do not promote until 2-client verified.**
- Bots: equip a modded weapon, check a bot's loadout resolves to its own gear (not your modded weapon).

## v0.12.95-dev — 2026-05-26

- **REMOVED**: Saltzpyre's crossbow as a toggle for the 4 Kruber careers. Ceded ownership to `character_weapon_variants` v0.1.347-dev's `cwv_es_crossbow` variant (default-on). The polish items it carried (3P grip offsets vs rifle anims, smoke FX on shot, missing bolt in 3P) made it too heavyweight for wt's "simple toggle" model.
- Strips the `_patch_crossbow_template_for_kruber` base template patcher (`wield_anim_career_3p[es_*] = "to_handgun"`), the `_build_crossbow_kruber_safe_third_person` lazy builder, and the `_wt_crossbow_kruber_attach_safe_apply` preview-time attachment-node substitution — all migrated to CWV.
- Bardin's wh_crossbow toggles (default-off) are unchanged; Saltzpyre's native wh_crossbow access is unchanged.

## 0.12.89-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("Weapon Tweaker v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `weapon_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[wt] v<MOD_VERSION> loaded")` runs once.

## 0.12.88-dev (2026-05-25) -- Sprinkle `_dbg` instrumentation at anim-remap dispatch / template patchers / BR function hooks (sampled on hot paths)

### Why
User enabled `enable_debug_logging` and played; log captured almost nothing for wt because the load-bearing event points (template patchers, anim-remap REMAP/FORCE/REDIR branches, BR function hooks) had no `_dbg` calls. Dummy-static-bug triage needs visibility into whether wt's animation_event hook is firing at all, whether the cross-character REMAP path is being hit, and whether the BR function hooks (Flamethrower / Beam / TrueFlight) are taking the modded path or vanilla.

### Changed
- `weapon_tweaker.lua`:
  - **`Unit.animation_event` hook (line ~1159)** -- added file-local `_anim_event_call_count` sample counter (`_ANIM_EVENT_SAMPLE_N = 60`) and a `_dbg("[wt:anim] event=enter ...")` at the top of the body that fires 1-in-60 calls. PER-FRAME hot path -- sampling is mandatory.
  - **REMAP branch inside the same hook** -- added `_anim_event_remap_count` (separate counter, `_ANIM_EVENT_SAMPLE_REMAP_N = 30`) + `_dbg("[wt:anim] event=REMAP src=... -> tgt=... career=... tmpl=... key=... sample=N")` so cross-character anim REMAP hits are visible without flood.
  - **`_patch_brace_template_for_kruber` / `_patch_longbow_empire_template_for_saltzpyre` / `_patch_longbow_template_1_for_saltzpyre` / `_patch_repeating_pistol_template_1_for_kruber`** -- added `_dbg("[wt:tpl_patch] event=applied template=<name> career_overrides=N action_remaps=M")` exit lines + a `_dbg_alert` on the missing-template skip path. Boot-time only; always-on.
- `weapon_tweaker_big_rebalance.lua`:
  - Added local `_dbg` helper at the top (file-local mirroring of the main file's helper since Lua 5.1 file-locals don't cross dofile boundaries).
  - **`BR.apply_all` entry + exit** -- `[wt:br_hooks] event=apply_all_begin master_active=...` / `event=apply_all_done hooks_installed=...`. Boot-time only; always-on.
  - **`_install_function_hooks`** -- added `[wt:br_hooks] event=install_begin` / `event=install_done flamethrower=... beam=... trueflight=...` markers; `event=skip_install reason=master_off` on the bt master-off short-circuit.
  - **Flamethrower `_select_targets`, Beam `client_owner_post_update`, TrueFlight `client_owner_start_action` + `fire`** -- each got its own sample counter (`_BR_HOOK_SAMPLE_N = 60`) and a `_dbg("[wt:br_hooks] event=<hook_name> sample=N ...")` line. Beam is per-frame while held; sampling is mandatory. Flamethrower/TrueFlight are per-fire but sampled for consistency.

### Existing instrumentation left unchanged (verified still present + correct)
- **`SimpleInventoryExtension.wield` (Layer 3 `traced_hook` at line ~1474)** -- emits paired `[wt:trace] event=enter|exit class=SimpleInventoryExtension method=wield` lines (gated on debug_logging) PLUS the existing `[wield] slot=... career=... key=... template=... anim_event_3p=... wield_anim_3p=...` line at line ~1526.
- **`SimpleHuskInventoryExtension.wield` (`safe_hook` at line ~1548)** -- no extra trace needed; husk wield is a pass-through whose state-population side effect is captured by `_populate_unit_state_from_wield`.
- **`GearUtils.create_equipment` (Layer 3 `traced_hook` at line ~1730)** -- emits paired enter/exit trace lines under debug_logging. Existing `[create_equipment] pre-resolved item_units` log line preserved.
- **`GearUtils.spawn_inventory_unit` (Layer 3 `traced_hook` at line ~2883)** -- the cross-character 3P swap dispatch; emits paired enter/exit trace lines. The downstream swap helpers (`_wt_brace_3p_swap_apply`, `_wt_longbow_3p_swap_apply`, `_wt_repeating_pistol_3p_swap_apply`) each already log `[wt brace-3p-swap]` / `[wt sp-longbow-crossbow]` / `[wt rp-pistol-handgun]` enter/SKIP/swap lines on every path -- well-instrumented, left as-is.
- **`MenuWorldPreviewer.equip_item` post-hook (line ~3465)** -- preview swap helpers each emit `[wt brace-3p-swap preview]` / `[wt sp-longbow-crossbow preview]` / `[wt rp-pistol-handgun preview]` lines on success. Already-instrumented.

### What I deliberately skipped
- **`mod.update` / per-frame update consumer bodies** -- none in wt's hot path that would benefit; per the brief.
- **Inner per-action / per-sub_action loops inside the template patchers** -- count+rollup is enough; per-iteration would emit dozens of lines per template at boot.
- **`Unit.animation_event` REDIR / FORCE / SUFFIX branches** -- the existing `_log_anims` (`/animlog` command) chat-echo path already covers per-event detail; adding a second sampled-debug stream would duplicate. The REMAP branch is the highest-suspect for cross-character bugs, so it's the one branch that got a dedicated sample counter.
- **`Unit.animation_event` per-call** without sampling -- would flood the log; 1-in-60 covers "is the hook even firing?" diagnostics.
- **Damage-path hooks on `DamageUtils.*` / `ActionAttack.*`** -- wt has no direct hooks on these classes (verified via Grep). Only the BR function hooks (Flamethrower / Beam / TrueFlight) interact with the damage pipeline, and those got their own `[wt:br_hooks]` markers.
- **`_safe_hook.lua` body** -- already has Layer 3 traced_hook which emits `[wt:trace] event=enter|exit class=... method=... n_args=... / n_returned=...` on every fire. Adding additional `_dbg` inside the wrapper would double-emit.

### Build
`VMBLauncher.exe build weapon_tweaker` -- verification only. NOT deployed, NOT uploaded (user-explicit doctrine 2026-05-25 EOD: develop, test, then user approves per-build for ship).

## 0.12.87-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[wt] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- weapon_tweaker.lua -- removed the load-time `mod:echo("weapon_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[wt] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("weapon_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build weapon_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.12.86-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- weapon_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- weapon_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build weapon_tweaker -- verification only. NOT deployed, NOT uploaded.

## v0.12.85-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[wt] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging). Additive to the existing "Weapon Tweaker: Baseline Active" operational line further down — does not replace it.

### Changed
- `weapon_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[wt] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.12.85-dev.

### Notes
- Fingerprint walks the post-CIM-strip widget tree on the local peer — surfaces what settings are actually live, not just the canonical definition.

## v0.12.84-dev — Layer 3 traced_hook helper: structured entry/exit log lines gated on debug logging

### Why
User idea: "Wrap every part of the code in a logger that shows us that it fired" when debug mode is on. Targeted form: wrap every `mod:hook` body with `[wt:trace] event=fire class=GearUtils method=spawn_inventory_unit n_args=N` at entry and `[returned n_vals=M]` at exit. Catches "did the hook fire?" and "did it return what we expected?" — exactly the v0.12.77/.78/.79 safe_hook bug class.

Layered on top of the existing wt safe_hook helpers:
- Layer 1 (existing): `mod:hook` — vanilla VMF (chain dispatch, no isolation).
- Layer 2 (v0.12.77+): `mod:safe_hook` — pcall-isolated + multi-return-safe wrap.
- Layer 3 (NEW): `mod:traced_hook` — Layer 2 PLUS structured entry/exit log lines gated on `enable_debug_logging`.

A consumer adopts `mod:traced_hook` when they want fire-confirmation + return-shape visibility. Otherwise stays on `mod:safe_hook`.

### Added
- `_safe_hook.lua` — `mod.traced_hook(self, class, method, handler)` and `mod.traced_hook_safe(self, class, method, handler)` methods. Both delegate to safe_hook / safe_hook_safe (Layer 2) for pcall isolation + multi-return preservation — do NOT re-implement either. Layer the trace lines on top by wrapping the user handler in a tracing closure.
  - Trace format: `[wt:trace] event=enter class=<C> method=<m> n_args=N` and `[wt:trace] event=exit  class=<C> method=<m> n_returned=M`.
  - Gate: `mod:get("enable_debug_logging")`. Toggle off => no trace lines, semantically identical to safe_hook.
  - Layer 3 marker constant `CT_WT_TRACED_HOOK_MARKER_v0_12_84 = "wt-traced-hook-layer3-installed"` for the new regression test.
- New `/wt_regression_test` check `wt_traced_hook_present` (next to the existing `wt_safe_hook_installed` block at ~L4357):
  - Asserts marker constant present.
  - Asserts `mod.traced_hook` and `mod.traced_hook_safe` are callable.
  - Smoke-tests installation + invocation on a fresh dummy class with toggle OFF then toggle ON. Asserts no crash and that the 3-return / 1-nil-hole shape survives the wrapper in both modes. Restores prior toggle state on exit.

### Migrated
Three load-bearing safe_hook call sites flipped to traced_hook. These fire on weapon wield / equip events (NOT per-frame), so trace lines are flood-safe.

- `weapon_tweaker.lua` L1414 — `mod:safe_hook("SimpleInventoryExtension", "wield", ...)` → `mod:traced_hook(...)`. Local-player wield. Confirms the wield hook fires per slot swap.
- `weapon_tweaker.lua` L1666 — `mod:safe_hook("GearUtils", "create_equipment", ...)` → `mod:traced_hook(...)`. In-game (path 1 of 3) weapon rendering. Per-mission-spawn / per-keep-load rate.
- `weapon_tweaker.lua` L2813 — `mod:safe_hook("GearUtils", "spawn_inventory_unit", ...)` → `mod:traced_hook(...)`. Cross-character 3P swap dispatch. The canonical 5-return / 2-nil-hole function that motivated the safe_hook fix cycle. Trace shows n_args + n_returned per fire — debugging swap regressions gets concrete return-count visibility for the first time.

### Rate-limit caveat
Per-frame hooks (e.g. `mod.update`) MUST NOT be wrapped in `traced_hook` — at 60+ fires/sec they would flood the log when the toggle is on. The three migrated sites are all event-rate. wt has no per-frame hook adoption today; if/when it does, leave it on `safe_hook` and document the rate-limit reason inline.

### Files changed
- `weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua` — added Layer 3 header subsection + `mod.traced_hook` / `mod.traced_hook_safe` methods + `CT_WT_TRACED_HOOK_MARKER_v0_12_84` constant.
- `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua` — MOD_VERSION bump; 3 hook sites migrated; new `_rt_register("wt_traced_hook_present", ...)` block.
- `weapon_tweaker/itemV2.cfg` — title + description bumped to v0.12.84-dev.
- `VMF_RECIPES.md § 2b` — extended with Layer 3 traced_hook sub-section + rate-limit caveat.
- `PROJECT_STANDARDS.md § 3.6` — one-line cross-ref to traced_hook (Layer 3) added.

### Verification
1. Restart VT2, load keep.
2. `/wt_regression_test` — new check `wt_traced_hook_present` should PASS. Existing `wt_safe_hook_installed` + `wt_safe_hook_preserves_multi_returns_with_nil_holes` checks must continue to PASS (Layer 3 stacks on top of Layer 2; it does not replace it).
3. Toggle `Debug Logging` ON in the VMF mod menu, wield a weapon and equip another — expect to see paired `[wt:trace] event=enter|exit class=SimpleInventoryExtension method=wield n_args=...` / `n_returned=...` lines plus matching pairs for `GearUtils.create_equipment` and `GearUtils.spawn_inventory_unit` in `%APPDATA%\Fatshark\Vermintide 2\console_logs\`.
4. Toggle Debug Logging OFF — no `[wt:trace]` lines should emit.

### Sample log lines (toggle on)
```
[wt:trace] event=enter class=GearUtils method=spawn_inventory_unit n_args=12
[wt:trace] event=exit  class=GearUtils method=spawn_inventory_unit n_returned=4
```

## 0.12.83-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `weapon_tweaker.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing seven wt regression checks.
- `weapon_tweaker.lua` ~L3152 — promoted ONE `_dbg(...)` call site to `_dbg_alert(...)`: the `[wt sp-longbow-crossbow] SKIP (pcall returned nil — internal abort, see prior warning)` line. This branch only fires after the preceding `mod:warning("[wt sp-longbow-crossbow] pcall ERROR ...")` has already logged, so the follow-up SKIP is part of the alert chain. With the toggle on, the user will see both messages in chat.
- `itemV2.cfg` — bumped to v0.12.83-dev.

### Notes
- 35 existing `_dbg(...)` call sites audited. 34 kept as `_dbg` (state/scale/wield/transition confirmations, plus expected SKIP branches like "career not Kruber" / "hand=right, not left" / "vanilla v_w3p was nil" — all are normal guard paths, not error conditions). 1 promoted to `_dbg_alert` (the post-pcall-failure SKIP at L3152).
- 0 bare `mod:echo` reclassified — all `mod:echo` calls are inside `/wt_*` / `/verify_*` chat command bodies (user-operational) or are permanent operational output (load banner).

### Notes on judgment calls
- SKIP branches like `[wt brace-3p-swap] SKIP (career not Kruber: %s)` and `(vanilla v_w3p was nil)` use the alert word "nil" but represent expected-skip paths where the guard is intentional. Per the policy's "Ambiguous → leave as `_dbg`. Conservative default."
- `[wt sp-longbow-crossbow] SKIP (crossbow 3P package not loaded)` similarly — package-not-loaded is an expected timing condition, not an error.

## 0.12.82-dev (2026-05-25) — Finish §3.6 rename: migrate stale `mod:get("wt_debug_mode")` gate call sites

### Why
v0.12.81-dev renamed the widget from `wt_debug_mode` to `enable_debug_logging` in `weapon_tweaker_data.lua` + `_localization.lua`, but four `mod:get("wt_debug_mode")` call sites in `weapon_tweaker.lua` (the `_dbg` helper at L118, the `D = mod:get(...)` cached wield-hook gate at L1442, the loadout-dump gate at L3782, plus comments) were not updated in the same pass. Result: the widget wrote `enable_debug_logging` while the gate read `wt_debug_mode` — debug mode was de-facto non-functional. `tools/mod-lint/lint-mod.ps1` doesn't catch a stale `mod:get` against a removed widget, so this slipped through.

### Fixed
- `weapon_tweaker.lua` — all four call sites now read `mod:get("enable_debug_logging")`. The legacy-key migration logic at L132-145 deliberately keeps a `mod:get("wt_debug_mode")` (with a `legacy_wtdebug` local) so an early-adopter's pre-rename clicked-on value still gets carried over.

### Note
The `mod:echo("Weapon Tweaker v" .. MOD_VERSION)` at line 97 still fires unconditionally — wt is on the `-dev` track, so the user-policy "no chat-echo unless `enable_debug_logging`" only applies to stable releases. The echo gets gated automatically the day wt drops the `-dev` suffix.

## 0.12.81-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). wt previously had `wt_debug_mode` nested inside `diagnostics_group` — renamed and un-nested.

### Changed
- `weapon_tweaker_data.lua` — removed `diagnostics_group` wrapper; `wt_debug_mode` renamed to `enable_debug_logging` at top-level bottom of `options.widgets`.
- `weapon_tweaker_localization.lua` — removed `diagnostics_group` / `wt_debug_mode` / `wt_debug_mode_description`; added `enable_debug_logging` + `enable_debug_logging_tooltip` per the standard.
- `weapon_tweaker.lua`:
  - `_dbg(fmt, ...)` helper now reads `mod:get("enable_debug_logging")` (was `wt_debug_mode`). Output prefix `[wt:dbg]` unchanged.
  - All other `mod:get("wt_debug_mode")` call sites (wield hook cached lookup, `_dbg_dump_local_player_loadout`) renamed to `enable_debug_logging`.
  - `_migrate_legacy_debug_setting()` now ALSO carries the saved value of `wt_debug_mode` (in addition to the v0.12.74 legacy `debug` / `enable_weapon_debug_logging` keys) into the new `enable_debug_logging` key on first load. Sentinel `wt_debug_migration_v1` continues to gate it to one-time.
- `itemV2.cfg` — title + description bumped to v0.12.82-dev.

### Notes
- **Migration**: existing users with `wt_debug_mode = true` get auto-carried into `enable_debug_logging = true` on first load via the migration helper.

## 0.12.81-dev (2026-05-25) — Tighten localization strings to vanilla style (15 entries rewritten)

### Why

Mod-menu descriptions in `weapon_tweaker_localization.lua` drifted into multi-paragraph essays for `authentic_brace_of_pistols`, the Moonfire Bow toggles, the Kruber Longbow zoom pair, and the Big Rebalance master/meta-init tooltips. Vanilla VT2 tooltips are uniformly terse. This pass aligns wt's heavy hitters with the vanilla voice per the new `LOCALIZATION_STANDARD.md` § 11 rules.

### Changed

- `authentic_brace_of_pistols_description`: 838 → 305 chars; kept all 5 mechanical bullets (handgun shot, single-shot, no manual reload, ammo cap, spread) + "Requires restart" but dropped the flavor commentary ("Flintlocks weren't tack-drivers...").
- `wt_debug_mode_description`: 565 → 220 chars; kept the `[wt:dbg]` tag enumeration + "off = warnings only" but dropped per-event prose.
- `moonfire_aoe_revert_description`, `moonfire_cosmetic_puff_description`: trimmed; kept 1.5m / 0.75m magnitudes and the "override" relationship between the two toggles.
- `kruber_longbow_disable_zoom_description`, `kruber_longbow_manual_zoom_description`: dropped state-machine internals ("zoom_in stage, ~0.01s delay") that don't help the player.
- `br_master_description`, `br_misc_weapons_meta_init_description`, `br_hook_shield_slam_description`, `br_shield_slam_replace_description`, `br_misc_status_dodge_count_description`, `br_misc_chaos_raider_special_staggers_description`: trimmed "subscribe to it separately, then restart the game" prose, kept the bt-master gate.
- `weapon_traits_description`, `cw_melee_traits_description`, `cw_ranged_traits_description`: trimmed.

### Not touched

- The vanilla trait descriptions (`trait_melee_*_description`, `trait_ranged_*_description`, `cw_trait_*_description`) are already vanilla-style (Critical hits grant +20%% attack speed for 5 seconds.) — left as canon.
- Per-BR-toggle short labels (`br_1h_hammer_*`, `br_2h_sword_*`, etc.) — already ≤6 words.

### Build

VMBLauncher.exe build weapon_tweaker — verification only.

## 0.12.80-dev (2026-05-25) — Hardening: regression test fixture for safe_hook multi-return + nil-hole preservation

### Why
v0.12.79's CHANGELOG closed with "Worth adding a regression test that asserts safe_hook'd functions preserve all positional returns INCLUDING nil values." This release adds that test as a hard fixture under `/wt_regression_test`.

The existing `wt_safe_hook_installed` check (kept) only validates the module loaded and the methods are callable — it does NOT exercise the actual multi-return path that broke silently across v0.12.77/.78/.79. The new check builds a fresh dummy class per invocation, wraps a 5-return / 2-nil-hole method via `mod:safe_hook`, and asserts positional integrity through the wrapper.

### Added
- New `/wt_regression_test` check `wt_safe_hook_preserves_multi_returns_with_nil_holes` (next to `wt_safe_hook_installed`, not replacing it):
  - Builds a dummy class on every invocation with `method = function(self, ...) return 1, nil, 2, nil, 3 end` (mimics melee-weapon `GearUtils.spawn_inventory_unit`'s nil-hole shape, more aggressive — 5 returns, 2 nils).
  - Fresh table identity per run guarantees VMF's duplicate-hook guard never trips, so the test is rerunnable any number of times in one session.
  - Wraps the method via `mod:safe_hook(_dummy_class, "method", function(func, ...) return func(...) end)`.
  - Captures the call result via `select("#", ...)` + table-pack idiom and asserts `n == 5` plus each positional slot exact-value (catches both v0.12.77 single-return collapse AND v0.12.78 non-deterministic `#table` truncation).
  - Returns self-diagnosing failure strings (e.g. `safe_hook truncated multi-return: got n=2 expected 5 (results=1,nil,...)`).
  - Also covers the error path: safe-hooks a `raiser` method that raises and asserts safe_hook itself didn't blow up with its own internal error (vs. the expected `test-raise` propagating from vanilla fall-through).
- New version constant `MOD_VERSION = "0.12.80-dev"` (was `0.12.79-dev`).

### Files changed
- `scripts/mods/weapon_tweaker/weapon_tweaker.lua` — `MOD_VERSION` bump; new `_rt_register("wt_safe_hook_preserves_multi_returns_with_nil_holes", ...)` block appended next to the existing `wt_safe_hook_installed` block (~L4226).
- `itemV2.cfg` — title + description bumped to v0.12.80-dev.

### Verification
1. Restart VT2, load keep.
2. `/wt_regression_test` — new check `wt_safe_hook_preserves_multi_returns_with_nil_holes` should PASS.
3. To prove the test would catch the bug: temporarily revert `_safe_hook.lua`'s `unpack(results, 2, n)` back to `unpack(results, 2)` and re-run — the check fails with a diagnostic message naming the truncated count.

## 0.12.79-dev (2026-05-25) — CRITICAL FIX #2: `unpack(results, 2)` non-deterministic with nil holes

### Why
v0.12.78's fix replaced `local ok, result_or_err = xpcall(...)` with `local results = { xpcall(...) }; return unpack(results, 2)`. That preserved trailing returns BUT introduced a subtler bug: `unpack(results, 2)` without an explicit `j` argument defaults to `j = #results`.

In Lua 5.1, `#table` is **undefined behavior for arrays with nil holes**. `GearUtils.spawn_inventory_unit` returns 4 values (`weapon_3p, ammo_3p, weapon_1p, ammo_1p`) — `ammo_3p` and `ammo_1p` are **nil for melee weapons**. So the xpcall result table `{true, weapon_3p, nil, weapon_1p, nil}` has non-deterministic length: `#t` could be 2, 3, 4, or 5 depending on Lua's internal boundary search.

This still produced nil-weapon-units in the inventory pipeline → infinity ammo HUD + corrupted 1P weapon rendering, ONLY visible when CWV's chained `mod:hook` was the next consumer (CWV re-emitted the nil values back to the engine). With CWV disabled, wt's truncation was less visible because the engine tolerated some nil returns; with CWV enabled, the chained re-emit cemented the corruption.

### Fixed
Capture the actual return count via `select("#", ...)` and pass it as `j` to `unpack` so nil holes are preserved:
```lua
local function _capture(...) return select("#", ...), { ... } end
local n, results = _capture(xpcall(handler, _error_handler, func, ...))
if results[1] then
    return unpack(results, 2, n)  -- explicit j preserves nil holes
end
```

### Bug timeline (per user investigation)
- v0.12.76 and earlier: no safe_hook wrapper → vanilla VMF mod:hook handled returns correctly → no bug
- v0.12.77 (Issue #26 fix shipped today): safe_hook introduced with `local ok, result_or_err` collapse → bug introduced (drops returns 2+)
- v0.12.78 (my first attempt at the fix shipped today): `unpack(results, 2)` without `j` → still broken (non-deterministic truncation)
- v0.12.79 (this release): `unpack(results, 2, n)` with explicit `j` → FIXED

### Lesson
The "table-pack the returns" idiom is necessary but not sufficient — you ALSO need `select("#", ...)` to know the true count when the function may return nils. This is the second time we hit a `VMF_RECIPES.md § 2` variant in 24 hours. Worth adding a regression test that asserts safe_hook'd functions preserve all positional returns INCLUDING nil values.

### Verification
1. Restart VT2. Load keep on Grail Knight (or any melee-weapon-equipping career).
2. Confirm ammo HUD shows finite number (NOT ∞).
3. Confirm 1P weapon model + grip renders correctly.
4. `/wt_regression_test` — `wt_safe_hook_installed` PASS.

## 0.12.78-dev (2026-05-25) — CRITICAL FIX: `safe_hook` wrapper multi-return collapse

### Why
v0.12.77's `_safe_hook.lua` shipped a textbook violation of `VMF_RECIPES.md` § 2 ("Hook wrappers collapse multi-returns"). The wrapper captured `local ok, result_or_err = xpcall(handler, ...)` and returned only `result_or_err` — silently dropping any 2nd / 3rd / 4th return value.

Several VT2 functions return multiple values:
- `GearUtils.spawn_inventory_unit` returns **4 values** (`weapon_unit_3p, ammo_unit_3p, weapon_unit_1p, ammo_unit_1p`) — wt v0.12.77 converted this site, so callers received only `weapon_unit_3p` and got `nil` for the other three.

### Symptoms (reported live by user on Grail Knight 2026-05-25 06:04)
- **Infinity-symbol ammo HUD** ← `ammo_unit_3p` collapsed to nil → ammo extension reads through missing unit → `nil` / `math.huge` arithmetic → ∞ glyph rendered.
- **First-person weapons rendered weirdly** ← `weapon_unit_1p` collapsed to nil → engine renders fallback / empty hands / wrong attachment.

### Fixed
`_safe_hook.lua` now table-packs the xpcall returns and `unpack(results, 2)` on success, preserving multi-return semantics:
```lua
local results = { xpcall(handler, _error_handler, func, ...) }
if results[1] then
    return unpack(results, 2)  -- Lua 5.1 unpack
end
```
Future-proofs every safe_hook'd function that returns multi-values, not just `spawn_inventory_unit`.

### Verification
1. Restart VT2. Load into keep on any Empire Soldier career.
2. Confirm ammo HUD shows a numeric value (NOT ∞) on any ranged weapon.
3. Confirm 1P weapon model + grip renders correctly.
4. Run `/wt_regression_test` — `wt_safe_hook_installed` should still PASS.

### Lesson
The new helper failed to apply its own repo's documented recipe. Adding a pre-merge gate that asserts `_safe_hook.lua` round-trips multi-returns through a test fixture is a follow-up worth filing.

## 0.12.77-dev (2026-05-25) — pcall-isolated `mod:safe_hook` wrapper (Issue #26)

### Why

A single `mod:hook` body that raises currently kills every later consumer
in the chain silently — no log, no error, just stops working. VMF's
`safe_calls.lua` xpcalls the outermost hook entry but does NOT isolate
consumers from each other when multiple mods stack hooks on the same
`(Class, method)`. Symptom in the wild: cosmetics_tweaker hook A raises
→ wt hook B never fires → user sees a missing feature with no diagnostic
log line. Fixes the diagnostic-cost side of GH #26 by giving wt a
drop-in-compatible wrapper that pcall-isolates each consumer's body.

### Added

- `weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua` — module
  attaches `mod.safe_hook(self, class, method, fn)` and
  `mod.safe_hook_safe(self, class, method, fn)` methods. Wraps `fn` in
  xpcall; on error logs `[wt:safe_hook] <Class>.<method> raised: <err>`
  via `mod:error` (with stack trace from `Script.callstack()`), then
  falls through to `func(...)` so the original engine path and every
  later consumer in the chain stay intact.
- `mod:dofile("scripts/mods/weapon_tweaker/_safe_hook")` require near
  the top of `weapon_tweaker.lua`, after MOD_VERSION and before any
  hook call site, so `mod.safe_hook` exists by the time consumers below
  reach for it.
- New marker constant `CT_WT_SAFE_HOOK_MARKER_v0_12_74 =
  "wt-safe-hook-pcall-isolated"` set by `_safe_hook.lua` (read by the
  regression-test check below).
- `/wt_regression_test` check `wt_safe_hook_installed`: asserts the
  marker constant is present + both `mod.safe_hook` and
  `mod.safe_hook_safe` are callable functions. Catches accidental
  removal of the require in future refactors.
- New section in repo-root `VMF_RECIPES.md`: "Pcall-isolated hooks
  (mod:safe_hook)" — when to use vs raw `mod:hook`, the
  consumer-isolation principle, signature compatibility, and the v1
  scope (wt-local; cross-mod sharing is Wave-2).
- New version constant `MOD_VERSION = "0.12.77-dev"` (was `0.12.76-dev`).

### Changed

- 5 representative hook sites converted from `mod:hook` / `mod:hook_safe`
  to `mod:safe_hook` / `mod:safe_hook_safe`:
  - `SimpleInventoryExtension.wield` (local-player wield + 1P-hands
    capture).
  - `SimpleHuskInventoryExtension.wield` (husk-side per-unit state
    population for cross-character 3P remap).
  - `GearUtils.create_equipment` (in-game keep + mission spawn render
    path — path 1 of 3).
  - `GearUtils.spawn_inventory_unit` (cross-character 3P swap dispatch).
  - `LevelEndView._verify_weapon_data` (end-of-mission victory screen).
- Each converted site picks up the consumer-isolation contract: a raise
  in this mod's body logs + falls through to vanilla instead of killing
  every later mod's hook on the same Class.method.

### Anti-patterns avoided

- Did NOT convert every `mod:hook` call site in `weapon_tweaker.lua` —
  establish the pattern, demonstrate adoption, and stop. Per Issue #26's
  scope: 3-5 sites, not a wholesale refactor.
- `mod:safe_hook` is a drop-in compatible signature with `mod:hook` — no
  call-site changes needed beyond the method name.
- Self-contained inside `weapon_tweaker/` for v1. Cross-mod sharing
  (helper in `bt` or a `vmf_shared/` package) is a Wave-2 concern; not
  in scope here.

### Verification

- `VMBLauncher.exe build weapon_tweaker` — green.
- `/wt_regression_test` — `wt_safe_hook_installed` PASS expected
  (validates marker + method-callable + type checks).
- Behavior of the 5 converted hook sites is unchanged on the happy path
  (xpcall wraps the body but returns its result through unchanged).
- Issue #26 closed on this version.

---

## 0.12.76-dev (2026-05-25) — wt_debug_mode toggle + diagnostic event subscriptions + legacy widget migration

### Why

Two orphan checkboxes (`debug`, `enable_weapon_debug_logging`) were defined
in `_data.lua` since the legacy monolithic Tweaker era but never read by
`weapon_tweaker.lua` — `CODE_REVIEW.md` line 135 / 213 flagged them as
dead settings. Meanwhile, every cross-character 3P unit swap path (brace,
longbow, repeater pistol), per-spawn unit override resolution, weapon
scale/offset application, and the end-of-mission `_verify_weapon_data`
hook fired their `mod:info(...)` diagnostic lines unconditionally, which
makes the console log noisy for anyone running multiple Tweaker mods at
once. Consolidate into one user-facing toggle that gates the noisy
fine-grained diagnostics, leaving load-time status and warnings/errors
unchanged.

### Added

- `wt_debug_mode` checkbox under a new `diagnostics_group` ("Diagnostics")
  in `_data.lua`. Default OFF. Localization key + `_description` per
  `LOCALIZATION_STANDARD.md`.
- `_dbg(fmt, ...)` helper near the top of `weapon_tweaker.lua` (right
  after the load-time `mod:info` banner). Routes to `mod:info("[wt:dbg] " .. fmt, ...)`
  only when `wt_debug_mode` is on; no-op otherwise.
- One-time migration helper `_migrate_legacy_debug_setting()` runs at
  module load. If either `debug` or `enable_weapon_debug_logging` was
  set to `true` by an older version, it ORs them into `wt_debug_mode`
  and writes a `wt_debug_migration_v1 = true` sentinel so the migration
  never reruns. Clears both legacy keys on the same pass.
- StateIngame-enter loadout dump in `mod.on_game_state_changed(status,
  state_name)` — when debug is on and `status == "enter"` /
  `state_name == "StateIngame"`, dumps career_name + per-slot (item_key,
  item_type, template) for the local player via `inventory_system._career_name`
  + `equipment().slots`. Gated inside the helper too (belt-and-suspenders).
- Wield-time diagnostic in the existing `SimpleInventoryExtension.wield`
  hook. When debug is on, dumps slot_name, career_name, item_key,
  template, `anim_event_3p`, `wield_anim_3p` for each wield. Separate
  from the `_log_anims`/`/animlog`-driven block so users don't need to
  toggle two systems.
- New version constant `MOD_VERSION = "0.12.76-dev"` (was `0.12.75-dev` from
  the parallel Issue #26 `_safe_hook` landing).

### Changed

- 17 verbose `mod:info(...)` calls in `weapon_tweaker.lua` converted to
  `_dbg(...)`:
  - `[create_equipment] pre-resolved item_units` (per-spawn override
    resolution).
  - `[scale_probe]` one-time per-weapon slot_data field probe (2 lines).
  - `Scaled %s on %s` / `Offset %s on %s` per-spawn unit transforms (3
    lines).
  - `[wt brace-3p-swap]` enter / SKIP / hid-left-pistol / swapped (4 lines).
  - `[wt sp-longbow-crossbow]` enter / SKIP-hand / SKIP-career /
    SKIP-no-v_w3p / SKIP-package / SKIP-bolt-package / swapped /
    SKIP-pcall-nil (8 lines).
  - `[wt rp-pistol-handgun]` enter / SKIP-hand / SKIP-career /
    SKIP-no-v_w3p / SKIP-package / swapped (6 lines).
  - `[wt brace-3p-swap preview]` / `[wt sp-longbow-crossbow preview]` /
    `[wt rp-pistol-handgun preview]` per-equip swap confirmations (3
    lines).
  - `[verify_weapon_data]` LevelEndView hook entry + unwrap (2 lines).
  - `[team_previewer cb]` preview_items unwrap (1 line).
- Retired the `debug` + `enable_weapon_debug_logging` widget definitions
  in `_data.lua`. The keys live in user_settings.config for legacy
  users until the one-time migration clears them.

### Kept as `mod:info` (always print)

- `Weapon Tweaker v%s loaded` + `Weapon Tweaker: Baseline Active` —
  load-time / state-entry status.
- `[wt brace-3p-swap] force-loaded repeater 3P unit` + `[wt
  sp-longbow-crossbow] force-loaded %s` — one-time mod-init status.
- `[wt authentic-brace] applied` + `[wt kruber-longbow-zoom] applied` —
  one-time apply confirmations.
- `[regression] PASS/FAIL`, `[regression-test-command] registered`,
  `/dump`, `/dump_weapons`, `/sm_probe` outputs — command-driven, only
  fire when the user explicitly invokes.
- All `mod:warning` / `mod:error` calls — never gated.
- `[WIELD]` + `[animlog]` blocks gated behind `_log_anims` (toggled via
  `/animlog` chat command) — independent of the new VMF toggle.

### Anti-patterns avoided

- Single checkbox, single helper — no per-feature debug categories, no
  log-level enum.
- `wt_debug_mode` chosen as the key name (NOT `debug`, which would
  collide with the legacy widget and prevent the migration from
  distinguishing the two).
- `_dbg` calls inside the wield hook cache `mod:get("wt_debug_mode")`
  into a local `D` before the block to avoid two table lookups per
  wield.

### Verification

1. Restart VT2 with the mod enabled, load the keep.
2. Open VMF mod options, scroll to weapon_tweaker, expand "Diagnostics".
   Confirm `Debug Mode` checkbox is present with the description from
   `_localization.lua`.
3. With debug OFF (default): equip a brace of pistols on Kruber Foot
   Knight. Console log should show no `[wt:dbg]` lines and no
   per-spawn `[wt brace-3p-swap]` entries.
4. Toggle debug ON. Wield/unwield a weapon → expect `[wt:dbg] [wield]
   slot=slot_melee career=...` line per wield.
5. Start a mission. On state entry: `[wt:dbg] [loadout] StateIngame
   enter career=...` + per-slot lines.
6. Equip a cross-character weapon (e.g. brace on Kruber). The
   `[wt:dbg] [wt brace-3p-swap]` enter / swapped lines appear.
7. Confirm legacy migration: with `debug = true` in a stale
   user_settings.config, first load post-update should write
   `wt_debug_mode = true` + `wt_debug_migration_v1 = true` and clear
   the old keys (visible by re-opening user_settings.config).

## 0.12.73-dev (2026-05-24) — §15 belt-and-suspenders runtime test for v0.12.72 rawget conversion

### Why
Audit `.test_coverage_audit_2026-05-24.md` PARTIAL row 1: the v0.12.72 `ItemMasterList rawget` conversion was lint-covered (regression-lint.ps1 `strict-table-lookup`) but lacked an in-mod `_rt_register` runtime check. Per the §15 doctrine update appended this round, lint-covered fixes ALSO require a runtime regression test — both surfaces are needed for PASS.

### Added
- Source-pattern marker constant `CT_WT_ITEMMASTERLIST_RAWGET_MARKER_v0_12_73 = "wt-itemmasterlist-rawget-hardened"` near the top of `weapon_tweaker.lua`.
- `_rt_register("wt_itemmasterlist_uses_rawget", ...)` at the bottom of `weapon_tweaker.lua`. Two assertions:
  1. The marker constant retains its expected value (catches accidental revert / refactor deletion of the hardening block).
  2. `rawget(ItemMasterList, <known-bad-key>)` returns `nil` without raising (catches a future regression where ItemMasterList grows a metatable that breaks rawget).

### Verification
1. Restart VT2 with the mod enabled, load the keep.
2. Run `/wt_regression_test` in chat. Expect `PASS: wt_itemmasterlist_uses_rawget` alongside the four pre-existing checks.

## 0.12.72-dev (2026-05-23) — Issue #8: defensive rawget on user-input ItemMasterList lookups

### Why

`ItemMasterList[user_input_key]` Crashifies on unknown keys via vanilla's
strict `__index` metatable. A user typing `/forge nonexistent_weapon` (or
any future chat command, save-data drift, or peer-late-join race that
reaches an unrecognized key) would have hit an unrecoverable engine fatal
instead of a graceful nil-and-log. The repo-wide convention (already
practiced in `cosmetics_tweaker`) is to wrap every non-literal-key
lookup in `rawget()` so the strict-metatable bypass is unreachable.

### Changed

Converted every `ItemMasterList[<var>]` site to `rawget(ItemMasterList, <var>)`
in `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua`:

- `weapon_tweaker.lua:175` — `_strip_removed_kruber_unlocks` walk (was line 171).
- `weapon_tweaker.lua:208` — `apply_weapon_unlocks` strip pass.
- `weapon_tweaker.lua:226` — `apply_weapon_unlocks` add-back pass.
- `weapon_tweaker.lua:277` — `patch_career_actions_on_weapons` ability-action injection.
- `weapon_tweaker.lua:3835` — `/dump_weapons` chat-command dump loop.

All five sites previously iterated keys from internal literal tables
(`_kruber_removed_pairs`, `weapon_unlock_map`, sorted snapshot of
`pairs(ItemMasterList)`), so the strict-`__index` crash was unreachable
*today* but brittle on future refactors (e.g. if a user-input or
save-data key ever flows into one of these helpers). The conversion
matches the cosmetics_tweaker convention (lines 1305 / 1239 / 4555–4556)
and the file's own comment header at line 18 promising rawget hygiene.

The line-3961 `team_previewer.cb_hero_unit_spawned_skin_preview` hook
already used `rawget(ItemMasterList, item.item_name)` as part of the
v0.12.52-dev parade-crash fix — no change there.

### Verification

1. In the keep, type `/dump_weapons` — should print the same weapon
   dump as before (rawget on a known-good key is identical to direct
   index for present keys).
2. With cross-character weapon toggles ON, equip a cross-career weapon
   in the keep inventory previewer — unlock + ability-action injection
   paths exercise the four `apply_weapon_unlocks` /
   `patch_career_actions_on_weapons` sites.
3. (Future-proofing) Any new chat command in wt that accepts a weapon
   key as a chat-arg can now safely call `rawget(ItemMasterList, key)`
   following the same pattern.

## 0.12.71-dev (2026-05-23) — Reorder per-career weapon toggles into canonical order

### What

`weapon_tweaker_data.lua` and `weapon_tweaker_localization.lua` had each
career's `unlock_<career>_<weapon>` widget list in a mix of lore-grouped,
add-order, and ad-hoc orderings — different per character bucket. Both
files reordered in lockstep so every career follows one mechanical rule:

1. **Native weapons first** (alphabetical by base-weapon key after the
   `unlock_<career>_` prefix), with any `*_deus_01` entry sorting to the
   end of the native cluster.
2. **Cross-character ports next**, grouped by donor character in
   `es → dr → we → wh → bw` order, alphabetical within each donor
   bucket, donor `_deus_01` at end of donor group.
3. Ambiguous template-alias setting_ids (e.g. Saltzpyre's `es_1h_flail`,
   visually a Saltzpyre flail using the shared `es_1h_flail` ItemMasterList
   key) sort by their **literal setting_id prefix**, not in-game character
   ownership — keeps the rule mechanical and deterministic from the
   setting_id alone.

334 widget moves in data, 406 string moves in loc (loc has both melee +
ranged blocks intermixed per career, so loc moves > data moves). Every
move is a re-order only — no setting_ids added, removed, renamed, or
re-defaulted. `default_value` and per-career inclusions/exclusions
(e.g. `es_sword_shield_breton` only on merc + GK, drake-vs-steam-pistol
career split on Bardin, `wh_priest`'s unique melee pool) preserved
exactly as-is.

### Why

- **Discoverability:** new contributors and players adding a weapon need
  a predictable insert point. The mixed prior ordering required
  guessing the family group; new alphabetical-by-donor is mechanical.
- **Maintainability:** `feedback_alphabetical_order.md` mandates moving
  loc + data together. A mechanical ordering rule makes that
  enforceable — `sort -u` works for verification.
- **No internal-consistency cost:** all 4 careers per character bucket
  already shared the same melee/ranged ordering (audit confirmed), so
  reordering by mechanical rule preserves per-character symmetry while
  removing the historical drift.

Ordering rule + alternatives considered in
`_audit_wt_weapon_order.md` §4-5 (repo root). Peregrinaje was
evaluated as the canonical reference per user brief but rejected — its
`tweaks/new_weapons.lua` is a `pairs(DeusWeaponGroups)` walk and
`tweaks/weapon_options.lua` is a flat unordered registry; neither
provides a per-career ordering to mirror. Full rationale in §1-2 of
the audit doc.

### Files touched

- `scripts/mods/weapon_tweaker/weapon_tweaker_data.lua`
- `scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua`
- `scripts/mods/weapon_tweaker/weapon_tweaker.lua` (MOD_VERSION bump only)

Pre-edit copies kept at `.bak.v0.12.70-dev` siblings of the two
touched scripts/mods files for diff insurance.

### Verification

1. Visual spot-check of `weapon_tweaker_data.lua:71-94` (merc native +
   ports — alphabetical + donor-grouped) and `weapon_tweaker_data.lua:428-435`
   (wh_priest — natives alphabetical, `es_1h_flail` correctly sorts under
   `es_*` donor bucket per ambiguous-alias rule).
2. Data/loc parity scan: both files have 428 unique `unlock_*` setting_ids,
   1:1 mapping (`set(data_sids) == set(loc_sids)`, no dups on either side).
3. Per-career divergences preserved: `es_sword_shield_breton` present
   only on `melee_es_mercenary` + `melee_es_questingknight`; Bardin
   drake-vs-steam-pistol career split intact; `wh_priest` 7-weapon
   pool + absent `ranged_wh_priest` group preserved.

## 0.12.70-dev (2026-05-23) — Remove polearm-preview diagnostic + defensive ItemMasterList audit

### Issue #7: Remove `_wt_polearm_preview_diag` diagnostic helper

The polearm preview diagnostic was scaffolded in v0.12.56 to log template/wield-event/animation data for a user-reported regression (Kruber Mercenary holding wrong stance on `es_halberd` / `es_2h_heavy_spear` preview). The regression was subsequently fixed in v0.12.64. The 4-line-per-equip diagnostic log noise is no longer earning its keep.

Deleted:
- `_POLEARM_DIAG_KEYS` whitelist table
- `_wt_polearm_preview_diag(self, item_name, slot)` function
- Call site in `MenuWorldPreviewer.equip_item` hook_safe
- Associated comment block

**Verification:** Inventory previewer works normally. No `[wt polearm-diag]` lines appear in logs.

### Issue #8: Defensive ItemMasterList lookup audit (resolved as side effect)

Audit pass to wrap user-input ItemMasterList lookups with `rawget(ItemMasterList, key)` pattern. The only remaining direct-index read with a dynamic key was inside `_wt_polearm_preview_diag` (deleted above), which took `item_name` from the hooked method parameter and validated it against `_POLEARM_DIAG_KEYS` before use. All other ItemMasterList accesses in the file iterate over hardcoded or self-validated key lists and are safe. Deletion of the diagnostic function resolves this audit item.

See CLAUDE.md Key conventions section for the pattern.

## 0.12.69-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `weapon_tweaker.lua` — renamed `regression_test` → `wt_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/wt_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.12.67-dev (2026-05-22) — Authentic Brace: primary spread 3× → 2×

Single-shot LMB (action_one.default — primary mode of fire) was too inaccurate per user feel-test. `_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT` dialled from 3.0 → 2.0; primary clone (`wt_authentic_brace_of_pistols_spread`) now scales every numeric leaf of the cloned `brace_of_pistols` spread template by 2× instead of 3×. Secondary mult unchanged at 9.0, so the rapid-fire / lock-target mode stays as wide-spread as before — the gap between primary and secondary widens to 4.5×.

## 0.12.66-dev (2026-05-22) — Add /regression_test command

### Added

- `/regression_test` chat command runs 4 in-game smoke checks for past fix-state: SimpleHuskInventoryExtension presence, weak-keyed per-3P-body anim-remap state shape, wh_priest's `weapon_unlock_map` excludes bows/crossbows/longbows, and the billhook 3P remap marker. Output: PASS/FAIL per check to chat plus log.

## 0.12.64-dev (2026-05-22) — Fixed: Kruber-on-billhook missing swing animations (regression dating to v0.12.55/56)

### Bug

User report: billhook animations broken after the v0.12.60-dev Kruber polearm preview fix. Three-subagent investigation (`_billhook_anim_diagnosis/`) traced the regression to **v0.12.55/56**, not v0.12.60. v0.12.60 made the codepath more visible but didn't introduce the bug.

### Root cause

`_WIELD_ANIM_CAREER_3P_PATCHES` (line ~1931, added v0.12.55) writes `Weapons.two_handed_billhooks_template.wield_anim_career_3p[es_*] = "to_polearm"` directly into the weapon template at boot. When Kruber wields Saltzpyre's billhook:

1. The patcher's value is already in the template at boot, so the **engine fires `to_polearm` directly** (not the original `to_2h_billhook`).
2. `Unit.animation_event` hook receives `to_polearm` with `career = es_huntsman` / `es_mercenary`.
3. Hook walks `_career_anim_redirect.to_polearm`:
   - `overrides[es_mercenary] = nil` → override branch skipped.
   - `prefix = "es_"`, `invert = nil`, career matches → `should_redirect = false`.
4. The two places `_resolve_3p_remap` is consulted to install `state.remap` (lines ~1127, ~1156) both bail. **`state.remap` stays nil.**
5. Subsequent billhook-specific attack events (`attack_swing_stab`, `attack_swing_left_diagonal`, `attack_swing_charge_stab`, etc.) fire raw on Kruber's polearm SM and silently no-op — polearm stance doesn't author billhook-named swing events.

Visible symptom: Kruber-on-billhook gets the correct stance (polearm) but **swing animations don't play**.

### Why v0.12.60 was innocent

v0.12.60's one-line `career and` short-circuit at line 1153 affects only the `_career_anim_redirect` path for **preview units** where `career == nil`. The Kruber-on-billhook in-mission case has a real career, so v0.12.60 doesn't change its behavior either way. Per subagent #46's git diff against HEAD, the redirect table is byte-identical pre/post v0.12.60. Per subagent #47's log scan, the preview path tested works clean. The regression is older and only manifests during actual wielding.

### Fix

Extended the unconditional weapon-change block at `weapon_tweaker.lua:1011-1026` with a fallback. When neither `_resolve_template_remap` nor `_resolve_key_remap` hits, ask `_resolve_3p_remap(event_name, career)` whether the wield event (which may have been patcher-rewritten) has an associated career-prefix remap in `_3p_remap_triggers`. The same lookup powers the override and redirect branches further down the hook; we're now also calling it from the wield-event path so the swing-event remap installs regardless of whether the wield event reached the hook in its original form or in the patcher-rewritten form.

### Symmetric coverage

Same fallback also fixes the inverse case: Saltzpyre wielding Kerillian's elf spear (the patcher rewrites `to_spear → to_2h_billhook` for `wh_*`). Pre-fix the swing-event remap installs only on the override-branch path; post-fix it installs from the wield-event path too.

### What v0.12.60's gate still does

The `career and` short-circuit at line 1153 stays. It blocks the redirect from firing on nil-career preview units (which would otherwise route polearm-class wields to whatever alt event the preview body happens to author — see v0.12.60's CHANGELOG entry). The new fallback is gated on the same `state and event_name:sub(1,3) == "to_"` check as the rest of the wield-event block, so preview units (no `state`) still don't reach it.

## 0.12.63-dev (2026-05-21) — Fixed: VMF crashify-exception in 10 trait-description tooltips

Per Section C of the 2026-05-21 audit, 10 trait-description strings at lines 550-588 of weapon_tweaker_localization.lua contained literal `%` characters (`+20%`, `5%`, etc.). VMF routes every localization through `safe_string_format` (`string.format`), so a single `%` triggers a `<<crashify-exception>>` event every time the tooltip is rendered — the same bug class fixed in gt 0.2.35. Escaped each occurrence to `%%`. No visual change (one displayed `%` after format).

## 0.12.62-dev (2026-05-21) — Move Big Rebalance master to bt (Tweaker: Buffs)

Refactored the wt-side Big Rebalance integration to depend on the new sister mod `bt` (Tweaker: Buffs). wt no longer ships its own copy of the 419-line `weapon_tweaker_big_rebalance_registrations.lua` (deleted; archived under `_big_rebalance_extract/deprecated_registration_files/`) and no longer exposes its own `br_master_enable_registrations` widget.

`BR.register_all()` is now a no-op shim. Per-feature toggles gate on `(get_mod("bt") or {}).is_br_active and get_mod("bt"):is_br_active()` instead of a local checkbox — when bt is installed and its master is on, wt's BR sub-toggles work; otherwise they silently no-op.

User-visible impact: subscribe to `bt` once, enable its master once, and any of wt/ct/et BR sub-toggles you flip will function. Removes the prior cross-mod sync rule.

## 0.12.61-dev (2026-05-21) — Core's Big Rebalance integration (opt-in)

Source mod: Core's Big Rebalance (Workshop ID `2705276978`,
"Weapon Balance" decompile). Credit to Core for the original
balance design; this is a re-implementation, not a redistribution.

Added the `[Big Rebalance]` group with the master toggle
`br_master_enable_registrations` and ~113 per-toggle widgets buckets
weapons / damage profiles / hooks / wield permissions / misc.
Every toggle defaults `false` — Big Rebalance is opt-in.

New files:
- `scripts/mods/weapon_tweaker/weapon_tweaker_big_rebalance.lua` — apply
  logic + function hooks (Flamethrower / Beam / TrueFlight start+fire).
- `scripts/mods/weapon_tweaker/weapon_tweaker_big_rebalance_defs.lua` —
  pure-data definitions for NewDamageProfileTemplates, ExplosionTemplates,
  and BuffTemplates that wt owns.
- `scripts/mods/weapon_tweaker/weapon_tweaker_big_rebalance_registrations.lua`
  — canonical alphabetical cross-mod registration list. Identical content
  ships in ct and et (diff-checked) per the gated-registration-divergence rule.

Master toggle `br_master_enable_registrations` runs a single pass that
writes every BR_REGISTRATIONS entry into DamageProfileTemplates /
ExplosionTemplates / BuffTemplates / StatBuffApplicationMethods and
appends each to NetworkLookup in sorted order, UNCONDITIONALLY on every
peer (per `feedback_vt2_gated_registration_diverges`). Per-toggle
changes that depend on those registrations only function when master is on.

Cross-mod dependencies left unimplemented in wt (per user direction):
- `DamageUtils.stagger_ai` / `apply_buffs_to_damage` / `calculate_damage`
  rewrites are et-owned; wt toggles that reference them work in
  isolation but reach full intent only with et's stagger rewrite.
- Talent buff bulk-registration is ct-owned; wt's registration list
  carries the *names* for index alignment but defers definitions to ct.

Open items (flagged in `impl_wt_summary.md`):
- `br_cog_rework` ships the speed/crit fields but defers the 19-entry
  chain-action / baked-sweep rewrites — too large for a clean
  toggle-gated implementation in one pass.
- `br_hook_shield_slam` is currently a gate-only toggle (no body); table-
  replacement half is covered by `br_shield_slam_replace`.
- `br_misc_status_dodge_count` surfaces only the `dodge_count = 2` knob;
  the full `GenericStatusExtension.init` rewrite stays with et.

## 0.12.60-dev (2026-05-20) — ROOT CAUSE: Unit.animation_event hook redirecting preview-unit wield events when career=nil

The polearm preview bug is finally root-caused. The v0.12.56 diagnostic data captured on 2026-05-20 (`console-2026-05-21-01.11.04-*.log`) showed:

```
item=es_halberd career=es_mercenary template=two_handed_halberds_template_1
  tpl.wield_anim=to_polearm wac3p[c]=to_polearm resolved=to_polearm
  has(resolved)=true has(to_polearm)=true has(to_2h_billhook)=false has(to_spear)=true
```

Every field that should be right IS right: the template patcher's `wield_anim_career_3p[es_mercenary] = "to_polearm"` landed, the engine resolved the wield event to `to_polearm`, AND Kruber's preview body authors `to_polearm` natively. So the event SHOULD fire and the pose should appear. Yet the pose was wrong.

The disconnect: `has(to_spear)=true` ALSO appears on Kruber's preview body. Kruber's preview body authors both `to_polearm` AND `to_spear` (the spear is one of the cross-character ports wt enables, so the engine pre-loads the spear SM on his body). That single line is what unlocks the trace.

### The redirect-with-nil-career bug

wt's `Unit.animation_event` hook (`weapon_tweaker.lua:909+`) intercepts every animation event globally. For a wield event on the previewer's character_unit:

1. `_unit_career_name(unit)` walks the unit's extension chain — `career_system` first, then `inventory_system`, then `Managers.player:owner`. The previewer's character_unit has **none** of these (it's a model unit, not a player unit), so the helper returns nil.
2. `is_local = _is_local_player_unit(unit)` is false (preview unit ≠ local player_unit), so the `_local_career_name()` fallback doesn't trigger either.
3. The hook continues with `career = nil`.
4. `career_redir = _career_anim_redirect["to_polearm"]` is the entry `{ alt = "to_spear", prefix = "es_", overrides = {...} }`.
5. The `overrides[career]` lookup short-circuits because `career` is nil. Good.
6. `matches_prefix = career and ...` evaluates to **nil → falsy**.
7. `should_redirect = career_redir.invert and matches_prefix or (not career_redir.invert and not matches_prefix)` reduces to `(nil and false) or (true and true)` = **true**.
8. `_safe_has_anim(unit, career_redir.alt)` — alt is `"to_spear"` — returns **true** on Kruber's preview body.
9. Hook fires `to_spear` instead of `to_polearm`. Kruber's body enters spear stance. Pose lands wrong.

Same flow corrupts every polearm-class wield on any preview body that authors the alt event:

| Wield event fired | Career resolves to | Redirect target | Hits |
|---|---|---|---|
| `to_polearm` (Kruber on halberd / Tuskgor) | nil | `to_spear` | Kruber preview body authors `to_spear` → redirects |
| `to_polearm` (Kruber on Saltzpyre billhook, via my wac3p remap) | nil | `to_spear` | same — redirects |
| `to_spear` (Kerillian on elf spear) | nil | `to_polearm` | Kerillian preview body authors `to_polearm` → redirects |
| `to_2h_billhook` (Saltzpyre on billhook) | nil | `to_polearm` | Saltzpyre preview body authors `to_polearm` → redirects |

Every native polearm-class preview was being silently routed to the wrong event. The "Kruber on billhook works" report from earlier was actually wrong — the redirect IS firing, but the wrong stance happened to look close enough to halberd stance that it passed visual inspection (both are `to_polearm`-class poses on the Empire skeleton).

### The fix

Gate `should_redirect` on `career` being non-nil. When career resolution fails (preview units, anonymous probes), don't redirect — fall through to native firing of the original event. The redirect mechanism is only meaningful for in-mission cross-character ports where the wielder's career is known; for anonymous units the safe behaviour is to let the body fire whatever event the engine sent it.

```lua
-- weapon_tweaker.lua:1100 (post-fix)
local should_redirect = career and (career_redir.invert and matches_prefix or (not career_redir.invert and not matches_prefix))
```

The `career_redir.overrides[career]` path (line 1080) already short-circuits on nil career and didn't need touching.

### Why this latent bug only surfaced now

The wt animation-event hook has carried this nil-career codepath since v0.9.x, but the bug stayed invisible because:

1. **The `_career_anim_redirect` table only had polearm-class entries with `alt` events the alternate-character bodies don't author.** Saltzpyre's preview body doesn't natively author `to_polearm`, Kerillian's body doesn't natively author `to_2h_billhook`, etc. So even when the hook tried to redirect, `_safe_has_anim` failed and the event fell through to native firing anyway — masking the bug.
2. **v6.11.0 (2026-05-18) didn't change `_career_anim_redirect` or `_safe_has_anim` — but Fatshark may have widened the preview body's SM-load coverage in an earlier patch.** Kruber's preview body authoring BOTH `to_polearm` AND `to_spear` is the missing ingredient that lets the redirect succeed and corrupt the pose. Whether this is new in v6.11.0 or older, the field repro is consistent with "some preview bodies started authoring more events than they used to".
3. **My v0.12.55/56/57 work added wield_anim_career_3p entries on the polearm templates**, which made the wield event actually reach the wt hook via the previewer's `_spawn_item_unit → Unit.animation_event` path with the right event name. Pre-v0.12.55, the previewer fired vanilla `wield_anim` (`to_2h_billhook` for billhook, etc.) — which Saltzpyre's preview body authored natively — so the redirect tried to fire on those events too but `_safe_has_anim` for the alt was probably false on the relevant bodies. The diag confirms the alt presence is what flipped.

The combination of "preview unit has no career_system" + "preview body authors the alt event" is what triggers the bug. Both conditions are necessary; the fix removes the first.

### Diagnostic kept (for now)

The polearm-diag from v0.12.56 / v0.12.59 stays in place for one or two more versions to confirm the fix on all four polearms. Once you eyeball halberd / Tuskgor / billhook / elf spear all looking right on every career, I'll delete the diag and tighten the file back up.

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.59 → 0.12.60; the should_redirect formula now requires `career` to be truthy before computing the prefix-match-based redirect decision. Single-line behavioural change; the rest of the hook is untouched.

## 0.12.59-dev (2026-05-20) — Polearm preview diagnostic: extend to `we_spear`, dump full `wield_anim_career_3p` table

User reports Mercenary halberd + Tuskgor still broken AND new repro on Kerillian native elf spear + Saltzpyre native billhook (both showing the previous weapon's stance). Static analysis says the engine's `world_hero_previewer.lua:1003` fallback chain (`wield_anim_career_3p[career]` → `wield_anim_career[career]` → `wield_anim`) should fire vanilla `wield_anim` for any career not in the `wield_anim_career_3p` table — and Kerillian (`we_*`) and Saltzpyre (`wh_*` for billhook) are not in those tables on their respective native weapons. Math says the fallback should hold; field repro says it doesn't.

I cannot find a code-level explanation from static read alone. Need the runtime data.

**Two changes to the existing v0.12.56 diagnostic:**

1. Added `we_spear` to `_POLEARM_DIAG_KEYS` so the probe also fires when Kerillian's elf spear is equipped in the keep.
2. The log line now also dumps the **full** contents of `tpl.wield_anim_career_3p` (sorted `k=v` pairs) and the presence of `to_1h_hammer` (for Warrior Priest path checks). The previous version only printed the single `wac3p[career]` lookup — useful for confirming the engine fallback hit, but not for catching the case where the patcher's writes never landed on the live template (revert by another mod, hot-reload artefact, wrong-template-name typo).

**What I'm trying to distinguish:**

- If the log shows `wac3p_table=nil` or empty `{}` on the affected items → the wt patcher never ran or another mod overwrote the field. Fix is at the patcher level.
- If the log shows the expected `wac3p_table={es_*=..., wh_*=...}` but `has(resolved)=false` → the resolved event genuinely isn't authored on the preview body. Fix is to pick a different target event (or force-load the state machine).
- If the log shows the expected table AND `has(resolved)=true` but the pose still looks wrong → some hook fires AFTER the wield event and corrupts the state machine. Fix is hook-ordering or a SM force-reset.

User repro path: open keep inventory, click halberd → Tuskgor → billhook → elf spear in turn, paste the four `[wt polearm-diag]` lines from the in-game log (`%APPDATA%\..\..\AppData\Roaming\Fatshark\Vermintide 2\console_*.log` on the current session).

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.58 → 0.12.59; `_POLEARM_DIAG_KEYS` gains `we_spear`; `_wt_polearm_preview_diag` log line extended with `wac3p_table=...` dump and `has(to_1h_hammer)` / `cunit_alive` fields.

## 0.12.58-dev (2026-05-20) — Kruber Longbow disable-zoom: switch to `zoom_condition_function` gate (game v6.11.0 fallout)

User reported that `kruber_longbow_disable_zoom` no longer killed the sniper zoom. Root cause: game v6.11.0 (Aussiemon/Vermintide-2-Source-Code @abe82ab4, 2026-05-18) dropped `aim_zoom_delay` on `longbows_empire_template.actions.action_two.default` from `2.0` → `0.22` (the only line that changed in `longbows_empire.lua`). The old wt disable patch leaned on `aim_zoom_delay = math.huge` to push the engine's `aim_zoom_time` beyond reach, but that's only the inner timing gate inside `action_aim.lua:128-134`:

```lua
if not self.zoom_condition_function or self.zoom_condition_function() then
    -- ...
    if not status_extension:is_zooming() and t >= self.aim_zoom_time then
        status_extension:set_zooming(true, current_action.default_zoom)
    end
end
```

Static read says `t >= math.huge` is never true and the patch should still hold, but the field repro after v6.11.0 says otherwise. Most plausible culprit: `scale_delay_value` (`action_aim.lua:13`) divides `aim_zoom_delay` by `ActionUtils.get_action_time_scale` per the active buff stack — if any buff pushes that scale to infinity or NaN, `math.huge / inf = NaN` and `t >= NaN` is false on every CPU but the field result was clearly inconsistent. Rather than chase the math, gate the OUTER check directly.

**Fix.** Set `aim.zoom_condition_function = function() return false end` in the disable branch. The engine's outermost gate at `action_aim.lua:128` then short-circuits the entire zoom block before it reaches any timer arithmetic, regardless of buffs / time scale / vanilla delay value. The old field writes (`aim_zoom_delay = math.huge`, `heavy_aim_flow_event = nil`, `heavy_aim_flow_delay = nil`, `default_zoom = nil`) stay in place as belt-and-suspenders.

**Manual-zoom branch** also sets `zoom_condition_function = function() return true end` explicitly — mirrors the shape vanilla writes (a closure returning `true`), so we don't drift from the template's authored type.

**v6.11.0 cross-check.** Diffed every weapon template and aim-related engine file between v6.10.0 (`5ff26df1`) and v6.11.0 (`abe82ab4`); the only relevant change is the `aim_zoom_delay = 0.22` constant. No new fields, no new code paths, so `zoom_condition_function` is and remains the right gate.

**No setting-change re-apply.** The patch still runs once at module init and the toggle is still labelled "Restart required" in localization. Mutating the shared template mid-mission would race with in-flight aim actions that already cached `self.aim_zoom_time`. Restart-on-toggle is the simplest invariant.

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.57 → 0.12.58; `_patch_kruber_longbow_zoom` rewritten to set `zoom_condition_function` as the primary gate; comment block updated with v6.10.0 vs v6.11.0 vanilla values and the rationale for switching gates.

## 0.12.57-dev (2026-05-20) — Remove Skullsplitter / Skull-Splitter+Shield / Bardin Hammer+Shield from Kruber's roster

Per user direction. Three cross-character weapons no longer offered to any Kruber career (`es_mercenary` / `es_huntsman` / `es_knight` / `es_questingknight`):
- `wh_1h_axe` — "Saltzpyre: Axe" (Skullsplitter)
- `wh_hammer_shield` — "Saltzpyre: Skull-Splitter and Shield"
- `dr_shield_hammer` — "Bardin: Hammer and Shield"

The three weapons stay available everywhere else they belong: `wh_1h_axe` remains native to Saltzpyre's three captain careers, `wh_hammer_shield` remains native to Warrior Priest plus the Saltzpyre cross-character row, and `dr_shield_hammer` remains native to all four Bardin careers. Only the four Kruber career rows lose the offering.

**Three surfaces touched:**
- `weapon_tweaker.lua` — removed all twelve `(es_*, weapon)` pairs from `weapon_unlock_map` (lines 31-34). Added `_kruber_removed_pairs` + `_strip_removed_kruber_unlocks` and wired it as the first step of `apply_weapon_unlocks` so existing users who had any of the toggles set true still get their stale `item.can_wield[<es_career>]` entry stripped on next init (or next setting change). Idempotent — runs cheaply on every reapply.
- `weapon_tweaker_data.lua` — deleted twelve `unlock_es_*_<weapon>` checkbox widget entries across the four Kruber melee groups. Removed `_cwv_managed_settings` table + `_strip_cwv_widgets` helper + its call site — they only stripped `wh_1h_axe` widgets when CWV was installed, and with `wh_1h_axe` gone from wt entirely there's nothing to strip. The CWV detector loop was simplified to just `_has_cim`.
- `weapon_tweaker_localization.lua` — deleted the matching twelve `unlock_es_*_<weapon> = { en = "..." }` strings across the four Kruber localization blocks.

Also cleaned `_cwv_managed` in `weapon_tweaker.lua` (line ~63): removed the dead `wh_1h_axe = true` entry from each of the four Kruber career rows. The CWV variant `cwv_es_axe_shield` (Kruber's "Imperial Axe and Shield") is unaffected — that variant is owned end-to-end by the `character_weapon_variants` mod and never went through wt's unlock map.

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.56 → 0.12.57; weapon_unlock_map trimmed; `_cwv_managed` cleaned; `_kruber_removed_pairs` + `_strip_removed_kruber_unlocks` added; first line of `apply_weapon_unlocks` calls the stripper.
- `weapon_tweaker_data.lua` — 12 widget rows removed; dead CWV-strip code excised; detector loop simplified.
- `weapon_tweaker_localization.lua` — 12 label rows removed.

## 0.12.56-dev (2026-05-20) — Kruber polearm preview: add explicit es_* entries + diagnostic probe

User repro of v0.12.55-dev showed Mercenary (Kruber) still holding the previous-weapon stance when previewing **native** `es_halberd` and `es_2h_heavy_spear` in the keep inventory. Both templates have vanilla `wield_anim = "to_polearm"`; Kruber's 3P body authors `to_polearm` natively (proven by `_career_anim_redirect.to_polearm.alt = "to_spear"` only applying to non-es_ careers — meaning es_ careers are expected to play `to_polearm` natively). So the engine's `world_hero_previewer.lua:1003` fallback chain (`wield_anim_career_3p[career]` → `wield_anim_career[career]` → `wield_anim`) should fire `to_polearm` on Kruber's preview body and the polearm stance should appear. Why it doesn't is unknown from static read.

**Two changes:**

1. **Explicit `es_*` entries** added to both polearm templates' `wield_anim_career_3p` (alongside the existing wh_* entries from v0.12.55). This forces the wield event to fire through the same code path as the billhook template's es_* entry that the user already confirmed works pre-patch — bypassing whatever interaction is short-circuiting the engine's `wield_anim` fallback. The entries map every Kruber career to `"to_polearm"`, which is what the fallback was supposed to deliver anyway, so the runtime behavior on the in-mission path is unchanged.

2. **Diagnostic helper `_wt_polearm_preview_diag`** wired into the `MenuWorldPreviewer.equip_item` hook. On every equip of `es_halberd` / `es_2h_heavy_spear` / `wh_2h_billhook`, logs the resolved wield event and whether the character_unit has it, plus the presence of the three candidate `to_*` events. Output goes to `[wt polearm-diag]` in the in-game log. Use one repro pass to capture the data, then delete the helper once the root cause is identified. Cost: 4 log lines per polearm equip while debugging.

If the diagnostic shows `has(to_polearm)=false` on Kruber's `character_unit`, the preview body genuinely lacks the polearm 3P SM — that would mean we need a different target event (probably `to_2h_hammer`) or a state-machine force-load. If `has(to_polearm)=true` but the stance is still wrong, the issue is elsewhere (e.g. another mod's hook firing on the same event and corrupting the SM).

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.55 → 0.12.56; expanded `_WIELD_ANIM_CAREER_3P_PATCHES.two_handed_halberds_template_1` and `.two_handed_heavy_spears_template` with es_* keys; added `_wt_polearm_preview_diag` helper and wired it into the consolidated equip_item hook.

## 0.12.55-dev (2026-05-20) — Inventory wield-stance: close the polearm gap (halberd / Tuskgor / billhook)

Adds the missing `wield_anim_career_3p` template patches for the three polearm-class cross-character pairs that had in-mission redirects (`_career_anim_redirect`, line ~225) but no template-side patch — so the keep inventory previewer (`MenuWorldPreviewer`) was firing a wield event the target body doesn't author, and the cross-character wielder held the prior weapon's idle stance.

**New gaps closed:**
- **`two_handed_halberds_template_1`** (Kruber's halberd `es_halberd`) on `wh_captain` / `wh_bountyhunter` / `wh_zealot` → `to_2h_billhook`. Saltzpyre now enters his billhook stance when previewing the halberd in the keep, matching the in-mission behavior the `_career_anim_redirect.to_polearm` override at line 239-240 already produced.
- **`two_handed_heavy_spears_template`** (Kruber's Tuskgor spear `es_2h_heavy_spear`) on the same three Saltzpyre careers → `to_2h_billhook`. Same root cause and same fix.
- **`two_handed_billhooks_template`** (Saltzpyre's billhook `wh_2h_billhook`) on `es_mercenary` / `es_huntsman` / `es_knight` / `es_questingknight` → `to_polearm`. Kruber's halberd stance, matching `_career_anim_redirect.to_2h_billhook` (line 247-248). User confirmed this preview already looked correct pre-patch, so this entry is belt-and-suspenders — it bakes the in-mission redirect into the template so both paths agree natively without depending on engine-fallback timing.

**Refactor:** the previous `_WE_SPEAR_WIELD_3P_OVERRIDES` table + `_patch_elf_spear_template_for_non_elves` function (single-template, wield-only) is replaced by a declarative `_WIELD_ANIM_CAREER_3P_PATCHES` table + one `_apply_wield_anim_career_3p_patches` applier covering all four polearm templates. New gaps surface as additional table rows instead of additional patcher functions. The four pre-existing patchers that ALSO do per-action `anim_event_3p` remap loops (brace / longbow_empire / longbow_template_1 / repeating_pistol) are kept as-is — they encode action-table logic that doesn't fit the declarative table.

**Why this couldn't be discovered earlier from the in-mission behavior alone:** `_career_anim_redirect` only fires through wt's `Unit.animation_event` hook. The inventory previewer doesn't go through that hook — it reads `wield_anim_career_3p` directly off the weapon template. So a missing template patch silently broke the preview pose while in-mission play looked fine, hiding the gap until a player paid attention to the keep stance. Documented in the patch block's comment.

**wh_priest** is intentionally absent from every entry — his row in `weapon_unlock_map` (line 49) has no polearm/spear/billhook/bow/crossbow, so any entry would be dead per `feedback_vt2_no_bows_on_warrior_priest` and the no-T-pose-stance audit closed in v0.12.48-dev.

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.54 → 0.12.55; replaced lines ~1838-1892 (the elf-spear-only patch block) with a declarative `_WIELD_ANIM_CAREER_3P_PATCHES` table containing all four polearm templates + one unified applier.

## 0.12.54-dev (2026-05-20) — Extend `TeamPreviewer` defense to invalid-key (Shape B) crashes

Extends the v0.12.53 belt-and-suspenders pre-hook to also handle the case where `item.item_name` is a **string that isn't in `ItemMasterList`** — not just the nested-table shape. PrincessLyndsey's crash repro on v0.12.52 used `we_maidenguard` as the leaking value; `we_maidenguard` is a **career-name string** (used in `can_wield` lists per `item_master_list.lua:14`), NOT an `ItemMasterList` key. Vanilla `team_previewer.lua:120-121` does `ItemMasterList[item_name]` then `item_template.slot_type` — when `item_name` is a string-but-not-a-key, the lookup returns nil under the strict-lookup metatable and the next line crashes on nil-index.

The v0.12.53 hook only unwrapped table-shape values, so it left career-name string leaks unguarded. Now the same pre-hook also `rawget`s the candidate against `ItemMasterList` (per memory `feedback_vt2_strict_lookup_rawget` — strict-lookup tables must use rawget for existence probes) and clears `item.item_name = nil` if the lookup misses. The downstream `if item_name then` guard at `team_previewer.lua:119` then skips that slot cleanly. No effect when `item.item_name` is a valid IML key (the common case).

Root-cause investigation deferred: the upstream code path that wrote `"we_maidenguard"` (a career name) into a `preview_items[i].item_name` slot is unknown. Could be a stale loadout reference, a versus parading-view bug (`versus_team_parading_view_v2.lua:597` reads `career_settings.preview_items[2].item_name` and forwards it verbatim — a CWV variant or career-name leak there would propagate), or an older bailout still in flight from a Fatshark change we haven't tracked. The Shape B guard turns the crash into a silent skip + warning log, which is the right user-facing behavior regardless of which upstream produces the bad data.

## 0.12.53-dev (2026-05-20) — Belt-and-suspenders parade-crash defense at `TeamPreviewer.cb_hero_unit_spawned_skin_preview`

End-of-mission parade crash recurred at `team_previewer.lua:120: attempt to index local 'item_template' (a nil value)` — same bailout-shape root cause documented in v0.12.25-dev (vanilla `LevelEndView._verify_weapon_data` writes `verified_weapon = { item_name = career_settings.preview_items[1] }`, where `preview_items[1]` is a `{ item_name = "..." }` table not a string, so `verified_weapon.item_name` ends up holding a nested table). Reproduced 2026-05-20 with PrincessLyndsey666 hosting Chaos Wastes, finishing on `we_maidenguard` (career_settings.preview_items[1] = `{ item_name = "we_spear" }`). The "is not wieldable" diagnostic print fired (vanilla `level_end_view_v2.lua:326`), confirming the bailout path was taken — but the existing post-hook on `_verify_weapon_data` (`weapon_tweaker.lua:3628-3645`) **did not log the unwrap**, despite the hook being registered (log line 1256: `[MOD][wt][INFO] (hook): Hooking '_verify_weapon_data' from [LevelEndView]`). Whether the hook never fired or the mutation was lost between hook exit and `team_previewer.cb_hero_unit_spawned_skin_preview` reading `preview_items[2].item_name` is unresolved — no other mod hooks `_verify_weapon_data`, the deployed bundle includes the fix code, and the running version is v0.12.52-dev (log line 1231).

**Two changes:**

1. **Entry-point instrumentation on the existing `_verify_weapon_data` post-hook** — log `player.name / career_index / weapon_slot / weapon.item_name` at the TOP of the wrapper (before `func(...)`). On the next repro this distinguishes "hook never fired" from "hook fired but mutation didn't propagate." Cheap, info-level only.

2. **Belt-and-suspenders pre-hook on `TeamPreviewer.cb_hero_unit_spawned_skin_preview`** — walk `hero_data.preview_items` BEFORE the loop body runs, and for any `item.item_name` that's a `{ item_name = "..." }` table, unwrap to the inner string (or clear to nil if unexpected). This catches the broken shape at the frame just above the actual crash site (`team_previewer.lua:117-120` does `local item_name = item.item_name; ItemMasterList[item_name]`), regardless of which upstream path produced the bad data. No-op for the well-formed-string case.

Per memory `feedback_redundant_safeguards_ok.md` — the user endorses belt-and-suspenders writes when redundancy is cheap and the missed-path failure is silent. A nil-index crash on the parade view is exactly such a silent failure (no recovery, kicks the player to keep).

**Risk:** Very low. Pre-hook walks a 2-element table and rewrites a field that's already broken if shape matches the nested-table case. Non-bailout success path (where `item.item_name` is a string) untouched. Hook target is `TeamPreviewer` (defined in `scripts/ui/views/team_previewer.lua`), used only by `LevelEndView._setup_team_previewer` per grep — versus paths use `VersusTeamParadingViewV2` which also goes through TeamPreviewer per the same grep so they get the same coverage.

**Bug B (note, not addressed here):** Vanilla `BackendInterfaceCommon.can_wield(we_maidenguard, "we_dual_wield_sword_dagger")` returned false despite that pair being natively wieldable per `dumps/weapon_native_careers.txt:59`. Likely cause: `apply_weapon_unlocks` at `weapon_tweaker.lua:80-122` strips careers destructively then re-adds only toggle-enabled ones. The bailout fires whenever the user toggles a NATIVE (career × weapon) pair OFF — but the strip-rebuild walks `weapon_unlock_map` rather than checking against a native baseline. Worth a separate fix that distinguishes "wt-added cross-career unlock" from "vanilla-native pair", but tracking as follow-up — out of scope for this patch.

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION bump 0.12.52 → 0.12.53; entry-point `mod:info` on the existing `_verify_weapon_data` hook (~L3629); new `TeamPreviewer.cb_hero_unit_spawned_skin_preview` pre-hook block appended after the verify hook (~L3650+).

## 0.12.52-dev (2026-05-19) — Moonfire puff visible to remote peers

Adds `mod:hook_safe` registrations on `PlayerProjectileHuskExtension` (`hit_enemy` / `hit_level_unit` / `hit_non_level_unit`) so the cosmetic puff (and the AOE-revert FX) plays on every peer that sees the arrow, not just the shooter's own machine. Previously only `PlayerProjectileUnitExtension` was hooked — that extension only runs on the shooter's client, so remote peers (host or other clients, depending on who fired) never saw the puff. Same husk-vs-self class-pair gap as the cosmetics_tweaker reload-paint bug (see `feedback_vt2_husk_extension_class_pair`).

The husk extension carries all the same fields `_wt_moonfire_on_hit` reads, so the existing callback works as-is. Refactored the hook registration to a small loop over the two class names and three method names — adds resilience if future VT2 patches add a fourth hit method.

AOE-revert side stays safe: `DamageUtils.create_explosion` already gates damage on `is_server`, so calling it from a husk hook on clients spawns FX but does no damage — exactly the per-peer pattern the prior comment block described as the intent.

## 0.12.51-dev (2026-05-19) — Moonfire AOE revert crash fix

Fixes host-side crash `area_damage_system.lua:347: attempt to index local 'explosion_template' (a nil value)` introduced in v0.12.49-dev when the **`moonfire_aoe_revert`** toggle was on and any Moonfire arrow impact reached the damage-buffer drain (queue-overflow path or next-frame `_update_aoe_damage_buffer`).

Root cause: `_MOONFIRE_AOE_TEMPLATE` was an unregistered local table with no `.name` field. `DamageUtils.create_explosion` forwards `explosion_template.name` to `AreaDamageSystem.add_aoe_damage_target` (17th positional arg), which writes it onto the ring-buffer entry. `_damage_unit` later calls `ExplosionUtils.get_template(name)` → `ExplosionTemplates[name]`. With `name = nil` the lookup returned nil and the next line (`explosion_template.explosion`) crashed. Vanilla templates avoid this because `explosion_templates.lua` runs `for name, t in pairs(ExplosionTemplates) do t.name = name end` at engine boot — but mods load after that loop fires, so any mod-defined template must populate `.name` itself **and** register into `ExplosionTemplates` so the late-stage lookup succeeds.

Fix: name the template `"wt_moonfire_aoe_revert"`, set `.name` explicitly, and write into `ExplosionTemplates[name]` at module init.

## 0.12.50-dev (2026-05-19) — Kruber Longbow zoom overrides (disable / manual)

Two new toggles under **Weapon Overrides**, both default OFF. Restart required (template patch applied at module init).

- **`kruber_longbow_disable_zoom`** — strips the longbow's delayed sniper-style heavy zoom entirely. Sets `aim_zoom_delay = math.huge` on `action_two.default` and nil's both `heavy_aim_flow_event` (`"lua_heavy_zoom"`) and `heavy_aim_flow_delay`. Holding right-click still draws the bow and applies the planted-charging movement debuff, but the camera never zooms.
- **`kruber_longbow_manual_zoom`** — replaces the heavy-zoom flow with Kerillian-longbow-style instant manual zoom. Adds `default_zoom = "zoom_in"`, sets `aim_zoom_delay = 0.01`, nil's the heavy-zoom fields. Hold right-click → bow draws AND zooms immediately; release to unzoom. **Overrides** `disable_zoom` when both are on (more specific).

### Affected templates

Patches both `Weapons.longbow_empire_template` and `Weapons.longbow_empire_tutorial_template` so the tutorial mission stays consistent. The cross-character port to Saltzpyre (`_patch_longbow_empire_template_for_saltzpyre`) lives on the same template, so any zoom override propagates to wh_captain / wh_bountyhunter / wh_zealot when they wield the Empire Longbow via the cross-character unlock.

### Implementation

Patcher runs once at module init, after `_patch_longbow_empire_template_for_saltzpyre` and after the moonfire AOE block. No hooks — direct mutation of the template's `action_two.default` aim action. Vanilla flow event `lua_heavy_zoom` is just unhooked from this template; the flow event itself still exists for any other content that might fire it (currently nothing else does).

## 0.12.49-dev (2026-05-19) — Moonfire Bow: pre-nerf AOE revert + cosmetic puff toggles

Two new toggles under **Weapon Overrides**, both default OFF. Restores (or just visually echoes) the small magical AOE every Moonfire Bow arrow used to detonate with before the nerf.

- **`moonfire_cosmetic_puff`** — cosmetic only. On every Moonfire arrow impact (enemy / level geometry / non-level prop) spawns one `fx/wpnfx_we_deus_01_impact` particle effect at the hit position. No damage, no friendly fire, no AOE — purely the lost visual.
- **`moonfire_aoe_revert`** — gameplay revert. Same hit paths, but routes through `DamageUtils.create_explosion` with a 1.5m radius (0.75m max-damage core) using the existing `poison_aoe` damage profile and an `attacker_power_level_offset = -0.5` cut so it reads as splash, not as a primary-damage detonation. `no_prop_damage` and `no_friendly_fire` are set. Visual is a 4-puff cluster (center + 3 jittered ~0.3m offsets) so the revert reads as visibly bigger than the cosmetic puff. **Overrides the cosmetic toggle** when both are on.

### Multiplayer model

Both hooks run on every peer's `PlayerProjectileUnitExtension` instance — VFX plays on every peer's screen for everyone's Moonfire arrows. Damage is gated by `_is_server` inside `create_explosion`, so host applies the AOE damage authoritatively; clients run the VFX-only path even though they call the same function. No `NetworkLookup` writes, no `LevelSettings` changes — lobby `combined_hash` is unaffected, so toggling on after the fact does not change which lobbies you can join (see `[[reference-vt2-lobby-combined-hash]]`).

### Why hook_safe on three hit paths

`PlayerProjectileUnitExtension` exposes `hit_enemy`, `hit_level_unit`, and `hit_non_level_unit` (plus `hit_player` for friendly-fire — intentionally skipped to avoid puffs on teammate hits). All three carry `hit_position` as the same argument index; one shared `_wt_moonfire_on_hit(self, hit_position)` callback covers them. `hook_safe` is correct because we do not need to modify the return value or short-circuit vanilla — we only piggyback the hit event.

### `we_deus_01` prefix match

Match is on `string.sub(self.item_name, 1, 10) == "we_deus_01"` so every Moonfire skin / illusion / variant carries the toggle through. CWV does not yet ship a `cwv_we_deus_01_*` variant; if one lands, the matcher needs widening.

## 0.12.48-dev (2026-05-19) — Drop Warrior Priest from Kerillian Volley Crossbow port (closes priest-ranged audit)

Third and final pass of the no-bows-on-Warrior-Priest audit (`feedback_vt2_no_bows_on_warrior_priest.md`). The user rule's body explicitly enumerates volley-crossbows; team-lead acked extending the strip to the surviving Priest+`we_crossbow_repeater` (Kerillian Volley Crossbow) entry that shipped pre-v0.12.x.

### Three surfaces touched

- `weapon_unlock_map.wh_priest`: drop trailing `"we_crossbow_repeater"`. Priest's row is now MELEE-ONLY (`wh_dual_hammer`, `es_1h_flail`, `wh_flail_shield`, `wh_1h_hammer`, `wh_hammer_shield`, `wh_hammer_book`, `wh_2h_hammer`).
- `_data.lua`: remove `unlock_wh_priest_we_crossbow_repeater` widget. The `ranged_wh_priest` group is now empty, so the whole group is removed and replaced with a comment marker citing the rule. (Empty VMF groups can render as label-with-nothing; clean removal avoids that visual oddity.)
- `_localization.lua`: remove `unlock_wh_priest_we_crossbow_repeater` label AND the now-orphaned `ranged_wh_priest = "Ranged: Warrior Priest"` group label (the group itself is gone).

No `_WIELD_3P` table to touch — `we_crossbow_repeater` cross-character relies on the global `_career_anim_redirect.to_repeating_crossbow_elf` (line 221) which redirects non-`we_*` careers to `to_repeating_crossbow`. Priest's body authors neither event, so the entry silently no-op'd pre-strip (he held prior-weapon idle stance while equipping the Volley Crossbow). Now functionally gated at `can_wield` instead — Priest can no longer equip the weapon at all.

### Audit close

Full `grep wh_priest` across `weapon_tweaker.lua`, `_data.lua`, `_localization.lua` returns:
- `weapon_unlock_map.wh_priest`: melee-only.
- `_data.lua melee_wh_priest` group: 7 melee unlocks (`wh_dual_hammer`, `es_1h_flail`, `wh_flail_shield`, `wh_1h_hammer`, `wh_hammer_shield`, `wh_hammer_book`, `wh_2h_hammer`). All ✓.
- `_data.lua` ranged_wh_priest: absent (comment marker in place).
- `_localization.lua` Priest labels: 1 group label (`melee_wh_priest`) + 7 weapon labels, all melee. All ✓.
- `_career_anim_redirect` (line 218+) Priest overrides: all target `to_1h_hammer` / `to_1h_hammer_shield` (melee). ✓
- `_suffix_career_map` (line 267+) Priest entries: all target `_1h_hammer` / `_1h_hammer_shield` suffixes (melee). ✓
- `_SP_LONGBOW_CROSSBOW_WIELD_3P` (line 1708): comment cites rule, Priest absent. ✓
- `_WE_LONGBOW_CROSSBOW_WIELD_3P` (line 1760): comment cites rule, Priest absent. ✓
- elf-spear patcher (line 1850+): Priest comments only document the unrelated `we_spear` exclusion (Priest never unlocks Kerillian's spear). ✓

**Zero ranged cross-character `wh_priest` entries remain. The audit is closed.** Future ports targeting bows / crossbows / longbows / volley-crossbows must continue to omit Priest per the rule.

### Previously-shipped state

`unlock_wh_priest_we_crossbow_repeater` was `default_value = false`, so opt-in only. Any player who toggled it on:
- The "Ranged: Warrior Priest" group header is gone from VMF settings on next reload. Their checkbox state survives in settings.config but maps to nothing readable.
- `apply_weapon_unlocks` strips Priest from `ItemMasterList.we_crossbow_repeater.can_wield` on next reload. Existing Volley Crossbow inventory items on Priest stay in inventory but the equip slot is empty until they swap.
- Previously-broken 3P render (Priest holding prior-weapon idle stance while equipping the Volley Crossbow) is gone.

## 0.12.47-dev (2026-05-19) — Drop Warrior Priest from historical Empire Longbow on Saltzpyre port

Companion to v0.12.46-dev. Team-lead acked extending the no-bows-on-Warrior-Priest rule (`feedback_vt2_no_bows_on_warrior_priest.md`) to the **pre-existing** Empire Longbow on Saltzpyre port (`es_longbow` on `wh_priest`, shipped pre-v0.12.x in `_SP_LONGBOW_CROSSBOW_WIELD_3P`). v0.12.46-dev stripped Priest from the NEW Port A (`we_longbow`); v0.12.47-dev does the same for the OLDER port that predated the rule.

Same four surfaces as the v0.12.46-dev change:
- `weapon_unlock_map.wh_priest`: drop trailing `"es_longbow"`.
- `_data.lua`: remove `unlock_wh_priest_es_longbow` checkbox.
- `_localization.lua`: remove `unlock_wh_priest_es_longbow` label.
- `_SP_LONGBOW_CROSSBOW_WIELD_3P`: drop `wh_priest = "to_crossbow"` entry; comment updated to cite the rule and the pre-v0.12.47-dev shipped state.

### Previously-shipped state

The widget defaulted to `false`, so the most likely impact on existing players is zero — Priest+Empire-Longbow was an opt-in pairing and was visually broken when toggled on anyway. For any player who DID toggle it on:
- The checkbox disappears from the VMF settings menu on next reload.
- `apply_weapon_unlocks` (`weapon_tweaker.lua:80`) strips Priest from `ItemMasterList.es_longbow.can_wield` on next reload because the unlock map no longer carries the pair. Their existing Empire-Longbow item on Priest stays in inventory (modded items don't lose backend entries), but the equip slot will show empty and the weapon won't be wieldable until they switch careers or pick a different ranged.
- The previously-broken 3P render (Priest holding his prior weapon's idle pose while firing arrows) is gone; vanilla Priest ranged options are unaffected.

### Audit complete

`wh_priest` now appears in NO `_<PORT>_WIELD_3P` table and in NO ranged cross-character unlock anywhere in the mod. Audit signal: `grep -n wh_priest weapon_tweaker.lua weapon_tweaker_data.lua weapon_tweaker_localization.lua` returns only `weapon_unlock_map.wh_priest` (with no ranged cross-character entries) and the comment citations in the two wield-3p tables. The rule is now enforced in code as well as memory.

## 0.12.46-dev (2026-05-19) — Drop Warrior Priest from Port A (Elf Longbow on Saltzpyre)

Per the user rule established 2026-05-19 (memory `feedback_vt2_no_bows_on_warrior_priest.md`): never add `wh_priest` to bow/crossbow/longbow cross-character ports. Priest's 3P body skeleton authors only the six universal wields plus `to_2h_hammer` — no `to_longbow`, no `to_crossbow`, no `to_repeating_crossbow`. Cross-character ranged ports that include him would produce no playable wield motion on his body.

Port A (`we_longbow` on Saltzpyre, shipped in v0.12.44-dev / consolidated under v0.12.45-dev) was authored before the rule was set and included Priest as a parity entry. Removed in three places this version:
- `weapon_unlock_map.wh_priest`: drop trailing `"we_longbow"`.
- `_data.lua`: remove `unlock_wh_priest_we_longbow` checkbox.
- `_localization.lua`: remove `unlock_wh_priest_we_longbow` label.
- `_WE_LONGBOW_CROSSBOW_WIELD_3P`: drop `wh_priest = "to_crossbow"` entry; comment updated to cite the rule and the dead-vocabulary diagnosis.

### Audit on the pre-existing es_longbow port

The older `_SP_LONGBOW_CROSSBOW_WIELD_3P` (Empire Longbow on Saltzpyre, shipped pre-v0.12.x) also lists `wh_priest = "to_crossbow"` plus carries `"es_longbow"` in `weapon_unlock_map.wh_priest`. That predates the rule. Pending team-lead confirmation before stripping shipped behavior — the entry is currently dead/no-op (Priest's `can_wield` already includes `es_longbow` so the checkbox is functional, but his body still can't render `to_crossbow` so the stance fires nothing). Will follow up once team-lead acks the audit. The new rule is documented in memory regardless so future ports won't repeat the mistake.

No build/deploy risk: this is a strict subtraction. Port A's other three Saltzpyre careers (`wh_captain`, `wh_bountyhunter`, `wh_zealot`) are unaffected. No new tables, no new helpers, no new force-load paths.

## 0.12.45-dev (2026-05-19) — Cross-character ports: Kerillian Longbow on Saltzpyre + Saltzpyre Repeating Pistol on Kruber

Two new cross-character ports shipped in the same iteration cycle via the canonical `CROSS_CHARACTER_PORT_RECIPE.md` procedure. Both follow the seven-step recipe end-to-end. v0.12.44-dev shipped Port A standalone; v0.12.45-dev adds Port B and consolidates both under one CHANGELOG block.

### Port A — `we_longbow` (Kerillian's Longbow) on all four Saltzpyre careers → empire crossbow 3P

The four Saltzpyre careers (`wh_captain`, `wh_bountyhunter`, `wh_zealot`, `wh_priest`) can now equip Kerillian's elf longbow (`we_longbow`); on Saltzpyre's body it renders as the empire crossbow 3P mesh with crossbow firing/zoom animations. 1P stays the elf longbow (1P is universal across characters — `feedback_1p_animations_universal.md`).

Sibling to the existing `es_longbow` (Kruber's empire longbow) port on Saltzpyre. Same 3P target mesh, same anim_event vocabulary, same 3P unit paths — so the in-mission + preview swap helpers are **reused with the dispatch predicate widened**; no new force-load and no new unit constants required. This is the "reusing an existing helper for sibling ports" pattern documented in `CROSS_CHARACTER_PORT_RECIPE.md` Section 2.

**Surface changes:**
- `weapon_unlock_map`: append `"we_longbow"` to all four Saltzpyre rows.
- `_data.lua`: four `unlock_wh_*_we_longbow` checkboxes (`default_value = false`).
- `_localization.lua`: four "Kerillian: Longbow" labels.
- `weapon_tweaker.lua`:
  - New `_patch_longbow_template_1_for_saltzpyre()` mutating `Weapons.longbow_template_1`:
    - `wield_anim_career_3p[wh_*] = "to_crossbow"`
    - per-action `anim_event_3p` for `attack_shoot_fast → attack_shoot`, `attack_shoot_fast_last → attack_shoot_last`, `draw_bow → to_zoom`. Crossbow SM has no `*_fast` variants; `to_zoom` is the crossbow's aim-hold (`action_two.default.anim_event`).
  - In-mission `GearUtils.spawn_inventory_unit` dispatcher: predicate widened to `item_data.name == "es_longbow" or item_data.name == "we_longbow"`. `_wt_longbow_3p_swap_apply` helper body is fully source-template-agnostic — substitutes `Weapons.crossbow_template_1` linking to dodge the `a_unwielded_bow` non-pcall-safe engine fatal (`feedback_vt2_unit_node_not_pcall_safe`).
  - Preview `MenuWorldPreviewer.equip_item` helper `_wt_longbow_preview_swap_apply`: predicate widened the same way.

### Port B — `wh_repeating_pistols` (Saltzpyre's Repeating Pistol) on all four Kruber careers → repeating handgun 3P

The four Kruber careers (`es_mercenary`, `es_huntsman`, `es_knight`, `es_questingknight`) can now equip Saltzpyre's revolving Repeating Pistol (`wh_repeating_pistols`); on Kruber's body it renders as the empire repeating handgun 3P mesh with repeating-handgun firing/aim animations. Right-hand-only weapon (no left-hand secondary, no ammo unit) — simpler equip-side shape than the brace port. 1P stays the Repeating Pistol.

**Vocabulary overlaps cleanly:** source `repeating_pistol_template_1` fires `attack_shoot` (action_one.default + action_one.bullet_spray) and `lock_target` (action_two.default); target `repeating_handgun_template_1` authors `attack_shoot`, `attack_shoot_last`, `attack_shoot_fast`, `attack_shoot_fast_last`, `lock_target`, `lock_target_loop`, `reload` natively. Per-action `anim_event_3p` remap table is intentionally **empty** — only `wield_anim_career_3p[es_*] = "to_repeating_handgun"` is needed. This is the case Section 2 step (e) of the recipe calls out as "skip step (e) when every source action's anim_event already exists in the target SM vocabulary unchanged."

**New helper required (not a dispatcher-widen).** The sibling-port checklist hits 4/5 against the brace hook (same target unit `_BRACE_REPEATER_3P_UNIT`, same right-hand orientation, no ammo unit on either, neither needs left-hand secondary handling for B1) but fails on the fifth criterion: the source template's `right_hand_attachment_node_linking.third_person.wielded` references **weapon-mesh-side nodes** (`lock_hammer`, `rotator`, `trigger_t1`) that don't exist on the repeating handgun mesh — linking via them would `Unit.node` engine fatal that bypasses pcall (sibling of crashify://f210b3b7). The brace's table is simpler (`j_rightweaponattach → 0` only) and survives the swap unchanged; we don't get that luxury here. Solution: substitute the **target template's** `right_hand_attachment_node_linking.third_person.wielded` for the link call in both the in-mission and preview paths.

**Surface changes:**
- `weapon_unlock_map`: append `"wh_repeating_pistols"` to all four Kruber rows.
- `_data.lua`: four `unlock_es_*_wh_repeating_pistols` checkboxes (`default_value = false`).
- `_localization.lua`: four "Saltzpyre: Repeating Pistol" labels.
- `weapon_tweaker.lua`:
  - New `_patch_repeating_pistol_template_1_for_kruber()` mutating `Weapons.repeating_pistol_template_1`: sets `wield_anim_career_3p[es_*] = "to_repeating_handgun"`. No per-action remap (vocabulary overlap).
  - New `_wt_repeating_pistol_3p_swap_apply` helper parallel to `_wt_longbow_3p_swap_apply`. Spawns `_BRACE_REPEATER_3P_UNIT`, links via `Weapons.repeating_handgun_template_1.right_hand_attachment_node_linking.third_person.wielded`, mirrors vanilla `_wield_slot` visibility (hide on local 1P, keep visible on husks — `feedback_vt2_husk_extension_class_pair` lessons inherited from the brace swap).
  - New `_wt_repeating_pistol_preview_swap_apply` helper parallel to `_wt_longbow_preview_swap_apply`. Mutates `entry.unit_name = _BRACE_REPEATER_3P_UNIT` AND `entry.unit_attachment_node_linking = handgun_tpl.right_hand_attachment_node_linking.third_person` (whole `third_person` table, covering both wielded and unwielded paths so the holster-mount also avoids the node fatal).
  - Dispatcher predicates added to both consolidated hooks (`GearUtils.spawn_inventory_unit` + `MenuWorldPreviewer.equip_item`) for `item_data.name == "wh_repeating_pistols"`.
  - **No new force-load**: `_BRACE_REPEATER_3P_UNIT` is already force-loaded by `_force_load_brace_repeater_3p_unit()` at mod init — Port B reuses the same target unit as the brace swap.

### Verification matrix (per the recipe doc)

Pending QA (`qa` teammate, task #5). For each port, walk all eight cells of the verification matrix in `CROSS_CHARACTER_PORT_RECIPE.md` Section 5:
- Keep inventory preview: target career rotates with target mesh in target wield stance. Port A = Saltzpyre with crossbow+bolt in `to_crossbow`; Port B = Kruber with repeating handgun in `to_repeating_handgun`.
- Solo mission: 3P body shows target mesh + target firing/attack anims on every action. 1P unchanged.
- Multiplayer host viewing husk + vice versa: both halves show target mesh.
- Wield/unwield cycle: stance re-enters cleanly; no stuck idle stance, no engine fatal on holster (`feedback_vt2_no_tpose_default_stance.md` — missing-event no-ops would hold the previous weapon's idle, not T-pose).
- Toggle setting off, re-enter keep: career stripped from `can_wield`.

Diagnostic log signatures per port:
- Port A: `[wt sp-longbow-crossbow] enter ...` then `[wt sp-longbow-crossbow] swapped 3P bow→crossbow ...`
- Port B: `[wt rp-pistol-handgun] enter ...` then `[wt rp-pistol-handgun] swapped 3P pistol → handgun ...`

## 0.12.43-dev (2026-05-17) — Longbow swap: add entry/skip diagnostic logging (parity with brace)

The brace→repeater swap has had verbose `enter` / `SKIP (<reason>)` log lines on every entry path since v0.12.37, which made it possible to see exactly why the swap was silently bailing for husks. The longbow→crossbow helper never got the same treatment — it only logged on the SUCCESS path, so every silent bail (hand check, career check, `v_w3p` nil, package not loaded, pcall returned nil) was invisible in the host's console.

After a v0.12.42 fresh launch with Saltzpyre wielding `es_longbow` (host viewing the husk), the host log contains the force-load lines at startup but ZERO `[wt sp-longbow-crossbow]` entries during gameplay. The swap is bailing somewhere before the success log. Without entry-level logging we can't tell which gate fires.

Added the same diagnostic pattern as the brace hook:
- **Entry log**: `enter hand=<...> husk=<bool> owner_unit_3p=<bool> career=<...> owner_known=<bool> owner=<name> v_w3p=<bool> v_a3p=<bool>` — captures all decision inputs.
- **SKIP log per bail path**: `hand != left`, `career not Saltzpyre`, `v_w3p was nil`, `crossbow 3P package not loaded`, `bolt 3P package not loaded`, `pcall returned nil`.

No functional change. Just observability. After this lands, a fresh test session will tell us exactly which branch the husk path is hitting.

## 0.12.42-dev (2026-05-17) — Elf spear preview stance: bake wield_anim_career_3p

### Bug

Saltzpyre wielding Kerillian's spear (`we_spear`) showed the wrong stance in the keep inventory preview — vanilla `to_spear` polearm pose instead of the billhook stance he uses in-mission. (In-mission was already correct via the `_career_anim_redirect.to_spear` → `to_2h_billhook` redirect for `wh_*` overrides.)

### Root cause

The `_career_anim_redirect` table intercepts `Unit.animation_event(unit_3p, "to_spear")` calls. The in-mission wield flow goes through this hook, so the redirect fires and Saltzpyre enters billhook stance.

The keep inventory previewer (`MenuWorldPreviewer`) sets up the character model's wield animation by reading `wield_anim_career_3p` (or `wield_anim_3p`, or `wield_anim`) directly off the weapon template at spawn time. It doesn't fire the wield event through a path our `Unit.animation_event` hook intercepts. The vanilla elf spear template has `wield_anim = "to_spear"` only (no per-career 3P override), so the previewer fired `to_spear` on Saltzpyre's body and got vanilla polearm-stance.

### Fix

Bake the in-mission `_career_anim_redirect.to_spear.overrides` mapping into the spear template's `wield_anim_career_3p` at mod init — parallel pattern to `_patch_brace_template_for_kruber` and `_patch_longbow_empire_template_for_saltzpyre`:

```lua
Weapons.two_handed_spears_elf_template_1.wield_anim_career_3p = {
    wh_captain      = "to_2h_billhook",
    wh_bountyhunter = "to_2h_billhook",
    wh_zealot       = "to_2h_billhook",
    es_mercenary    = "to_polearm",
    es_huntsman     = "to_polearm",
    es_knight       = "to_polearm",
    es_questingknight = "to_polearm",
}
```

Both paths (in-mission + preview) now resolve to the correct stance natively. Kerillian and unmapped careers fall back to `wield_anim = "to_spear"` as before — wood-elf SM authors `to_spear` natively. The `_career_anim_redirect.to_spear` entry stays — it still covers any re-fires of `to_spear` through the animation_event path (push-attack stance resets, etc.).

### Why only Saltzpyre + Kruber

Per `weapon_unlock_map`, the elf spear is unlocked for Kerillian (native), all four Kruber careers, and Saltzpyre's wh_captain / wh_bountyhunter / wh_zealot. Bardin, Sienna, and wh_priest don't unlock it — entries for them would be dead.

## 0.12.41-dev (2026-05-17) — Remove Sienna's Sword (`bw_sword`) from all Saltzpyre careers

Dropped `bw_sword` from `weapon_unlock_map` for `wh_captain` / `wh_bountyhunter` / `wh_zealot`, and removed the three matching VMF checkboxes + localization entries. `apply_weapon_unlocks` will strip any previously-added Saltzpyre entries from `ItemMasterList.bw_sword.can_wield` on next reload. Sienna native access (Adept / Scholar / Unchained / Necromancer) is unchanged. `wh_priest` never had this entry. No remap/scale/grip state touched.

## 0.12.40-dev (2026-05-17) — Remove Bardin's Crossbow (`dr_crossbow`) from all Saltzpyre careers

Dropped `dr_crossbow` from `weapon_unlock_map` for `wh_captain` / `wh_bountyhunter` / `wh_zealot`, and removed the three matching VMF checkboxes + localization entries. `apply_weapon_unlocks` will strip any previously-added Saltzpyre entries from `ItemMasterList.dr_crossbow.can_wield` on next reload. Bardin native access (Ranger / Ironbreaker / Slayer / Engineer) is unchanged. `wh_priest` never had this entry. No remap/scale/grip state touched.

## 0.12.39-dev (2026-05-17) — Hide brace left pistol on husks too

### Bug

After v0.12.38 made the brace→repeater swap visible to the host on remote-player Kruber husks, the **left-hand brace pistol** remained visible alongside the swapped repeater on the right hand. Same `wh_brace_of_pistols` issue: the template renders two pistols (one per hand), and the spawn hook only swaps the right hand.

### Root cause

Two parallel issues, both rooted in the husk/self-owned class split:

1. The `mod:hook_safe("SimpleInventoryExtension", "show_third_person_inventory", ...)` re-hider only fires on the self-owned class. Per `unit_extension_templates.lua` (line 71), husks use `SimpleHuskInventoryExtension`, which has its own `show_third_person_inventory` method that our hook doesn't cover. Same trap recorded in [[feedback_vt2_husk_extension_class_pair]] and just hit yesterday in v0.12.37.

2. Even if we hook the husk class, `SimpleHuskInventoryExtension._wield_slot` never calls `self:show_third_person_inventory()` at the end (the self-owned `simple_inventory_extension.lua:692` does, but the husk version doesn't). So a hook on the husk method wouldn't fire on initial wield — only on later state-driven visibility toggles (ghost mode, grabbed-by-tentacle).

### Fix

Two-part:

- **Hook both classes' `show_third_person_inventory`** — factored the existing hook body into `_hide_brace_left_pistol(self, show)` and registered it on both `SimpleInventoryExtension` and `SimpleHuskInventoryExtension`. Belt for any later visibility toggles that go through this method.
- **Hide directly in the spawn hook** — added a branch in the `GearUtils.spawn_inventory_unit` hook for `hand == "left"` + brace + Kruber career, hiding `v_w3p` immediately via the same `Unit.has_visibility_group/set_visibility` branching the existing hook uses. Suspenders for the initial-wield case on husks where the show_third_person_inventory path doesn't fire.

### Why both

- The spawn-time hide is the primary fix and covers the initial wield case for both local and husk.
- The show_third_person_inventory hook stays for later toggles (e.g. a husk coming out of ghost mode re-enables 3P inventory, which would otherwise re-show the left pistol).

## 0.12.38-dev (2026-05-17) — Brace/longbow swap: don't hide 3P unit on husks

### Bug

After v0.12.37 made the brace→repeater swap correctly fire on the host for remote-player Kruber husks (confirmed by the diagnostic log line `swapped 3P brace → repeater on career=es_mercenary (husk=true)`), the host STILL saw the vanilla brace mesh instead of the repeater.

### Root cause

Both the brace→repeater and longbow→crossbow swap bodies called `Unit.set_unit_visibility(new_unit, false)` unconditionally. That's correct for the LOCAL player path — vanilla `_wield_slot` (both `SimpleInventoryExtension` and `SimpleHuskInventoryExtension`) hides the 3P weapon when a 1P unit exists, because the local player sees their hands in 1P, not their 3P body. But for HUSKS, there's no 1P, so vanilla LEAVES the 3P unit visible — that's exactly how other players see the held weapon. Our unconditional hide inverted that for husks: the new repeater unit was rendered invisible, while the original brace had been `mark_for_deletion`-ed, so the host saw the brace mesh for a frame or two (before deletion landed) and then nothing.

### Fix

Both swap helpers (brace at the `GearUtils.spawn_inventory_unit` hook, longbow at `_wt_longbow_3p_swap_apply`) now gate the visibility hide on `owner_unit_1p`:

```lua
if owner_unit_1p then
    Unit.set_unit_visibility(new_unit, false)
end
```

Matches vanilla `simple_husk_inventory_extension.lua:750-756` (and the equivalent block in `simple_inventory_extension.lua`) which uses `if right_hand_weapon_unit_1p then ... set_unit_visibility(weapon_unit_3p, false)`.

### Diagnostic log update

The brace swap's success log now also reports the visibility decision (`vis=true` = unit was made invisible, i.e. local player path; `vis=false` = unit stays visible, i.e. husk path).

## 0.12.37-dev (2026-05-16) — Multiplayer husk fixes: husk wield hook + robust career lookup + brace-swap diagnostics

### Bug

Two multiplayer issues, same root cause class:
1. **Animation remap** (regression in v0.12.35's per-unit migration): the wield hook hooked only `SimpleInventoryExtension.wield`. Remote-player husks use a different class — `SimpleHuskInventoryExtension` — so `_unit_state[husk_unit]` never got populated. The animation_event hook had no per-husk weapon info and fell back to "no remap" for husks.
2. **Brace → repeater 3P unit swap**: didn't fire on the host's view of a client's Kruber wielding the brace. The user (client) saw their own Kruber as repeater correctly, but the host saw the brace mesh.

### Root cause (both issues)

Per `unit_extension_templates.lua`:
- `self_owned_extensions` (lines 12 / 43) → `SimpleInventoryExtension`
- `husk_extensions` (lines 71 / 90) → `SimpleHuskInventoryExtension`

The two classes share no method inheritance. `SimpleHuskInventoryExtension.wield` (line 314 in source) is a separate codepath. It DOES call `GearUtils.spawn_inventory_unit` (line 666), so the brace hook's `mod:hook("GearUtils", "spawn_inventory_unit", ...)` registration DOES fire for husks — but `_unit_career_name(owner_unit_3p)` was reading from the inventory extension's `_career_name`, which is only set when the husk extension's init received a Player object whose `career_name()` was non-nil at that exact moment (race-prone on lobby-formed remote players).

### Fix

- **`_unit_career_name`** — switched to using `career_system` extension as the primary source. `CareerExtension` is attached to both local player_units AND husks (per `unit_extension_templates.lua` line 75) and its `init` sets `self._career_name` directly from `career_data.name` (`career_extension.lua:23`) — no race, no Player-object dependency. The inventory_system and `Managers.player:owner` paths remain as fallbacks.

- **New `mod:hook("SimpleHuskInventoryExtension", "wield", ...)`** — populates `_unit_state[self._unit]` for remote-player husks, mirroring the SimpleInventoryExtension hook from v0.12.35. Factored the state-population body into `_populate_unit_state_from_wield` so the two hook callbacks stay in lockstep.

- **Brace swap diagnostic logging** — every brace spawn now logs (filtered, at most 2 lines per equip): `hand`, `husk=true/false` (derived from `owner_unit_1p == nil`), career resolution, owner-player resolution, and skip reason if the swap bailed. Lets us see exactly what the host's machine reports for a remote Kruber wielding the brace.

### Notes

- The brace swap hook's existing claim "Husks: same hook fires because remote-player spawn flows through the same `GearUtils.spawn_inventory_unit`" was correct about the hook firing. The actual gap was career detection, not hook registration.
- See [[feedback_vt2_husk_extension_class_pair]] (new memory): for any feature that needs to behave correctly for remote players, audit whether the hooked class has a `Husk*` sibling per `unit_extension_templates.lua`. Hook both, or hook a global function (like `GearUtils.spawn_inventory_unit`) that both classes route through.

## 0.12.36-dev (2026-05-16) — Remove Saltzpyre's Axe (`wh_1h_axe`) from all Kerillian careers

Dropped `wh_1h_axe` from `weapon_unlock_map` for `we_waywatcher` / `we_maidenguard` / `we_shade` / `we_thornsister`, and removed the four matching VMF checkboxes + localization entries. `apply_weapon_unlocks` will strip any previously-added Kerillian entries from `ItemMasterList.wh_1h_axe.can_wield` on next reload. Saltzpyre native access (Captain / Bounty Hunter / Zealot) and Kruber CWV-managed access are unchanged. No remap/scale/grip state touched.

## 0.12.35-dev (2026-05-16) — Per-unit animation remap state (multiplayer fix)

### Bug

Cross-career weapon 3P animations played correctly only on the local player's screen for **their own** weapon. Other players' cross-career weapons rendered with the wrong remap (or none at all) unless the local viewer happened to be holding the same weapon on the same career.

### Root cause

The remap system tracked weapon and remap state as a **single set of globals** (`_current_weapon_template`, `_current_weapon_key`, `_3p_weapon_remap`, `_last_remap_template`). The `SimpleInventoryExtension.wield` hook updated these only when `self._unit == player.player_unit`, so husks never registered. The `Unit.animation_event` hook then applied the (local-player) remap to every 3P body it processed — including remote-player husks — so husks animated as if they were holding the host's weapon on the host's career.

### Fix

Per-unit state, weak-keyed by the 3P body unit:

```lua
local _unit_state = setmetatable({}, { __mode = "k" })
-- entries: { template, key, remap, last_remap_id }
```

- **`SimpleInventoryExtension.wield` hook** — lifted the `self._unit == player.player_unit` gate around state capture. Now populates `_unit_state[self._unit]` for every wield, on every player (local + husks + bots). The `_local_fp_unit` capture stays local-gated (we only need to identify *our own* 1P hands for the redirect-skip early-return).

- **`Unit.animation_event` hook** — all references to the old globals replaced with `_state_for(unit)` lookups. Career resolution switched from `_local_career_name()` to `_unit_career_name(unit)` (falls back to the local career only if the unit lookup fails). 1P early-return moved AHEAD of the state work so 1P events don't allocate state entries.

- **Flail direct-redirect block** (Saltzpyre's flail H1/H2 and Sienna's flaming flail H2 cross-career fixes) — was previously `is_local`-only because the global `_current_weapon_key` only tracked the local viewer. Now reads `state.key` per-unit and uses the unit's own career, so a remote Saltzpyre with es_1h_flail also gets the fix on the host's screen.

- **`to_*` remap reset** — also per-unit now. Each husk re-resolves its own remap on weapon switch via `state.last_remap_id`.

- **`/info` command** — now queries the local player's `_unit_state` entry for the displayed 3P-remap name.

### Notes

- The per-unit table is weak-keyed (`__mode = "k"`) so dead units release automatically without a separate cleanup pass.
- Bot inventories use the same `SimpleInventoryExtension`, so this also fixes bot 3P anims (which were previously rendered with the local viewer's remap).
- 1P universality is preserved — only the 3P body unit and remote husks ever enter the redirect/remap blocks. Per `feedback_animation_remap_rules`, 1P animations work on every character with every weapon and are never touched.

## 0.12.34-dev (2026-05-16) — Wide curation pass: Bardin / Kerillian / Sienna

Continuing the curation pass from v0.12.33. All removals trim default-OFF widgets and the matching unlock-map entries; no remap/scale/grip state is touched (those tables either had no entries for the removed careers, or had entries for unrelated careers that still wield the weapon).

**Bardin (all 4 careers) lose:**
- `wh_1h_hammer` — Saltzpyre's Skull-Splitter
- `wh_hammer_shield` — Saltzpyre's Skull-Splitter & Shield

**Kerillian (all 4 careers) lose:**
- `dr_1h_axe`, `dr_1h_hammer` — Bardin's Axe / Hammer
- `wh_2h_sword`, `wh_1h_hammer`, `wh_1h_falchion` — Saltzpyre's Greatsword / Skull-Splitter / Falchion
- `bw_sword`, `bw_1h_crowbill` — Sienna's Sword / Crowbill
- `es_1h_sword`, `es_halberd`, `es_2h_heavy_spear` — Kruber's Sword / Halberd / Tuskgor Spear

**Sienna (all 4 careers) lose every non-`bw_` weapon** — keeping only the seven Sienna-native melee options (`bw_1h_crowbill`, `bw_dagger`, `bw_ghost_scythe`, `bw_flame_sword`, `bw_1h_flail_flaming`, `bw_1h_mace`, `bw_sword`) plus the staff ranged options. Removed: `dr_1h_axe`, `dr_1h_hammer`, `we_1h_sword`, `es_1h_mace`, `wh_1h_axe`, `wh_1h_falchion`, `es_1h_flail`, `wh_1h_hammer`. The Necromancy Staff (`bw_necromancy_staff`) remains correctly exclusive to Necromancer.

## 0.12.33-dev (2026-05-16) — Bulk curation pass + fix `bow_root` in-game crash on Saltzpyre + longbow

## 0.12.33-dev (2026-05-16) — Bulk curation pass + fix `bow_root` in-game crash on Saltzpyre + longbow

### Crash fix — `crashify://92f9907f-45a1-4688-b415-441287faa34d`

`[Script Error]: bow_root` when Saltzpyre (any career) equipped Kruber's longbow IN-MISSION (not the keep preview — that path was fixed in v0.12.29). Sibling bug to v0.12.29's `a_unwielded_bow` crash: `_wt_longbow_3p_swap_apply` linked the spawned crossbow `new_weapon` using the LONGBOW template's `left_hand_attachment_node_linking.third_person.wielded` table, which references `bow_root` — a node that exists on the bow weapon mesh but not on the crossbow mesh. Engine `Unit.node` raised a fatal that bypassed our pcall (`feedback_vt2_unit_node_not_pcall_safe`). Fix: pull the wielded linking from `Weapons.crossbow_template_1.left_hand_attachment_node_linking.third_person.wielded` instead — same approach as the preview fix, applied to the in-game wielded code path. The brace→repeater swap doesn't hit this class because the brace and repeater templates happen to share compatible weapon-side node names; longbow and crossbow do not.

### Curation: remove never-functional cross-character options

Removed unlock entries (and matching VMF widgets + localization) where the underlying animation / skeleton compatibility was never going to work cleanly. All removals are default-OFF toggles, so no user with a saved-ON setting is silently disabled — but the menu noise is gone.

**Bardin (all 4 careers — Ranger / Ironbreaker / Slayer / Engineer) lose:**
- `bw_sword` — Sienna's Sword
- `wh_dual_hammer` — Saltzpyre's Dual Skull-Splitters

**Saltzpyre Captain / Bounty Hunter / Zealot lose:**
- `dr_1h_axe`, `dr_dual_wield_hammers`, `dr_1h_hammer` — Bardin axe / dual hammers / hammer
- `we_2h_sword` — Kerillian's Greatsword
- `bw_1h_flail_flaming` — Sienna's Flaming Flail

**Warrior Priest additionally loses (16 weapons stripped; WP now offers only its native moveset + a couple compatible holdouts):**
- All four Bardin entries above plus `dr_shield_hammer`
- `we_spear`, `we_1h_sword`
- `es_halberd`, `es_1h_mace`, `es_mace_shield`, `es_1h_sword`, `es_2h_heavy_spear`
- `wh_1h_axe`, `wh_2h_billhook`, `wh_1h_falchion`
- `bw_1h_crowbill`, `bw_1h_flail_flaming`, `bw_sword`

WP retains: `wh_dual_hammer`, `es_1h_flail`, `wh_flail_shield`, `wh_1h_hammer`, `wh_hammer_shield`, `wh_hammer_book`, `wh_2h_hammer`, `we_crossbow_repeater`, `es_longbow`.

`apply_weapon_unlocks` will strip the now-unmanaged career entries from each weapon's `ItemMasterList.<key>.can_wield` on next reload. The `_3p_remap_triggers` and `_weapon_scale_overrides` tables for the affected weapons are untouched — they still serve any character/career combo that legitimately wields them.

## 0.12.32-dev (2026-05-16) — Remove Saltzpyre's Axe (`wh_1h_axe`) from all Bardin careers

Dropped `wh_1h_axe` from `weapon_unlock_map` for `dr_ranger` / `dr_ironbreaker` / `dr_slayer` / `dr_engineer`, and removed the four matching VMF checkboxes + localization entries. `apply_weapon_unlocks` will strip any previously-added Bardin entries from `ItemMasterList.wh_1h_axe.can_wield` on next reload. Saltzpyre / Kruber (CWV-managed) / wh_priest access unchanged. The `_cwv_managed.es_*.wh_1h_axe = true` rows are for Kruber and untouched.

## 0.12.31-dev (2026-05-16) — Remove Bardin's Great Hammer (`dr_2h_hammer`) + Bardin's Hammer (`dr_1h_hammer`) from all Kruber careers

Dropped both keys from `weapon_unlock_map` for `es_mercenary` / `es_huntsman` / `es_knight` / `es_questingknight`, and removed the eight matching VMF checkboxes + localization entries (4 careers × 2 weapons). `apply_weapon_unlocks` will strip any previously-added Kruber entries from `ItemMasterList.dr_1h_hammer.can_wield` and `dr_2h_hammer.can_wield` on next reload. Bardin / wh_priest access is unchanged. `_weapon_scale_overrides.dr_1h_hammer.we_` (Kerillian-only) is untouched.

## 0.12.30-dev (2026-05-16) — Remove Sienna's 1h Sword (`bw_sword`) from all Kruber careers

Dropped `bw_sword` from `weapon_unlock_map` for `es_mercenary` / `es_huntsman` / `es_knight` / `es_questingknight`, and removed the four matching VMF checkboxes + localization entries. `apply_weapon_unlocks` will strip any previously-added Kruber entries from `ItemMasterList.bw_sword.can_wield` on next reload. Bardin / wh_priest / Sienna access is unchanged; the `_3p_remap_triggers` and `_weapon_scale_overrides` entries for `bw_sword` are untouched (Bardin still wields it, scale/remap rows were already `dr_`-only).

## 0.12.29-dev (2026-05-16) — Fix `a_unwielded_bow` keep-inventory preview crash on Saltzpyre + longbow; menu labels prefixed with "Melee:" / "Ranged:"

**Crash fix.** `crashify://f210b3b7-ad4f-4e62-b680-9d1e2bc91684` — `[Script Error]: a_unwielded_bow`. Reproed by previewing `es_longbow` on a Saltzpyre career (in this case `wh_bountyhunter`). The v0.12.22 preview swap (`_wt_longbow_preview_swap_apply`) replaced `entry.unit_name` with the empire crossbow 3P unit but left `entry.unit_attachment_node_linking` pointing at the longbow template's table. The longbow's `.unwielded` half references `a_unwielded_bow`, a skeleton node that exists on the empire / elf 3P bodies but NOT on Saltzpyre's. World preview mounts the unwielded (holstered) weapon, calls `Unit.node(saltzpyre_body, "a_unwielded_bow")`, and the engine raises a fatal that bypasses pcall (per `feedback_vt2_unit_node_not_pcall_safe`). Fix: also overwrite `entry.unit_attachment_node_linking` with `Weapons.crossbow_template_1.left_hand_attachment_node_linking.third_person` — the WH crossbow template Saltzpyre uses natively, whose attachment nodes are known to exist on his body. Guarded with a `Weapons.crossbow_template_1` nil check; if the lookup fails we bail before the mesh swap so we don't crash. The in-game `_wt_longbow_3p_swap_apply` already uses `.wielded` (universal hand bone, exists on all 3P bodies) and was unaffected.

**Menu labels.** Prefixed every `melee_*` and `ranged_*` group label in `_localization.lua` with `Melee: ` / `Ranged: ` so the navigation chain reads `Melee: Kruber` → `Melee: Mercenary` (and same for `Ranged: …`). Leaf weapon checkboxes keep their existing `<Character>: <Weapon>` labels. Pure localization-string change, no widget-tree or code change.

## 0.12.28-dev (2026-05-15) — Fix Kerillian native elf-spear 3P animations

`_3p_remap_triggers.to_spear` was missing a `we_` entry, so when Kerillian wielded her own elf spear, `_resolve_3p_remap` fell through to `_default = _3p_remap_spear_to_polearm`. That table was authored for **Kruber wielding the elf spear** (mapping elf-spear attack events to Kruber's polearm-skeleton equivalents) and breaks Kerillian's down_left / left attacks when applied to her own skeleton. Symptom: messed up 3P spear animations on every Kerillian career, visible on bots / other players. Fix: added `we_ = false` to declare "Kerillian native, no remap", mirroring the existing `wh_ = false` pattern on `to_2h_billhook`. One-line data fix; no behavior change for cross-character spear wielders (Kruber/Saltzpyre still get their respective remaps).

## 0.12.27-dev (2026-05-15) — Rename `/status` → `/info` to clear command-name collision

Startup log was showing `[MOD][wt][ERROR] (command): command name 'status' is already used by another mod 'SpawnTweaks'`. SpawnTweaks loads first and owns the global `status` command name — VMF rejects our duplicate registration, leaving `/status` non-functional. Renamed our debug-state command to `info`. Same handler body; new invocation is `/info`. (Reminder: VT2 chat commands are typed as `/<registered-name>` directly — no mod-id prefix.)

## 0.12.26-dev (2026-05-12) — Authentic Brace: final secondary-spread tune, 12× → 9×

`_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT` dialled back from 12.0 to **9.0** per user feel-test ("9× and I think that'll do"). Primary spread stays at 3×, so secondary is now exactly 3× the primary multiplier (was 4× in v0.12.21–v0.12.25). The doc-block step (5) reference value updated to match. No other authentic-brace behavior changes — speed, reticle reticle-jump fix, ammo, reload, damage all unchanged.

## 0.12.25-dev (2026-05-12) — Fix end-of-mission parade crash + consolidate duplicate hooks

**End-of-mission parade crash** (crashify://811e5718-2e04-4995-8a22-0880c44cf44d): `team_previewer.lua:120: attempt to index local 'item_template' (a nil value)`. Triggered when a player has a `character_weapon_variants` cross-character variant in their loadout — CWV variants inherit `entry.name` from the base weapon (per `feedback_cwv_clone_name_clobber.md`), so the level-end verifier looks up the BASE `ItemMasterList` entry whose `can_wield` doesn't include the new career → `BackendInterfaceCommon.can_wield(career, item_data)` returns false → vanilla `LevelEndView._verify_weapon_data` hits a bailout path that assigns `verified_weapon.item_name = career_settings.preview_items[1]`. But `career_settings.preview_items[1]` is now `{ item_name = "..." }` (a table), not a string — Fatshark changed the shape of `preview_items` without updating this bailout path. `team_previewer.cb_hero_unit_spawned_skin_preview` then does `ItemMasterList[that-table]` → crash. Fix: post-hook `LevelEndView._verify_weapon_data` to unwrap the table-shape to its inner `.item_name` string, or clear to nil if unexpected. Reproduced with the user having `we_javelin` (cwv_es_javelin → base we_javelin name) on `es_huntsman`.

**Duplicate-hook warning consolidation** (per memory `feedback_vmf_hook_safe_no_chain` and the user's request):

- `mod:hook("GearUtils", "spawn_inventory_unit", ...)` was registered twice (brace pistols → repeater swap and longbow → crossbow swap). VMF chained these correctly but logged `(hook): Attempting to rehook active hook [spawn_inventory_unit]` each game load. Consolidated: the longbow swap body is now a local helper `_wt_longbow_3p_swap_apply` called from the brace hook's dispatch block. Forward-declared per `feedback_lua_forward_reference`.

- `mod:hook_safe("MenuWorldPreviewer", "equip_item", ...)` was registered THREE times (brace preview swap, longbow preview swap, item-key capture for `_spawn_item_unit` lookup). VMF's `hook_safe` does NOT chain duplicates from the same mod — only the LAST registration actually fired, so the brace preview swap and longbow preview swap were silently dead since they were registered. Consolidated all three into one hook_safe that calls two local helpers (`_wt_capture_preview_item_key`, `_wt_longbow_preview_swap_apply`) followed by the inline brace swap. Forward-declared both helpers. Two fixed bugs as a side effect: brace pistols and longbow now show the swapped 3P mesh in the keep inventory previewer again (they didn't on v0.12.24).

**Files changed:**
- `weapon_tweaker.lua` — version bump, vanilla-bug-fix hook for `LevelEndView._verify_weapon_data` at end of file, two forward declarations + closure-helper conversions for the consolidated hook registrations.

## 0.12.24-dev (2026-05-12) — Pre-resolve per-career `item_units` (fix CW bot crash on bw_ghost_scythe — second attempt)

**Why a second attempt:** v0.12.23 added a `career_name` fallback recovered from `unit_3p`'s `inventory_system._career_name`. The fallback's `mod:warning` log line never fired in the second crash repro (cbcace55), confirming `career_name` was already non-nil at our hook entry. The hook chain still dropped it somewhere between our wrapper (crash-dump frame [12] shows `career_name = "bw_unchained"`) and the unwrapped `gear_utils.create_equipment` (frame [10] shows `nil`). Mechanism unknown — static inspection of the three hook frames (CWV, cosmetics_tweaker, weapon_tweaker) shows clean varargs pass-through.

**Workaround:** instead of trying to fix the lost arg, sidestep the broken path. Vanilla `gear_utils.create_equipment` does `item_units = override_item_units or BackendUtils.get_item_units(item_data, nil, nil, career_name)` — so if we **pre-resolve** `item_units` ourselves (calling `BackendUtils.get_item_units` with the real `career_name`) and pass the result as `override_item_units`, gear_utils uses our version verbatim and never enters the chain-broken code path.

**Gating:** only fires when `item_data` has `right_hand_unit_override[career_name]` or `left_hand_unit_override[career_name]`. Covers the entire Sienna scythe family (`bw_ghost_scythe` / `_magic_01` and their skins) plus any other vanilla weapon with per-career unit overrides. The v0.12.23 `career_name` recovery from `inventory_system` is kept (now feeds this pre-resolve block when arrival is nil).

**Files changed:**
- `weapon_tweaker.lua` — version bump, added pre-resolve `override_item_units` block to the `create_equipment` hook (≈12 lines).

## 0.12.23-dev (2026-05-12) — Recover lost career_name in `create_equipment` (fix CW bot crash on bw_ghost_scythe)

**Crash:** Chaos Wastes mission start, bot Sienna *Unchained* (`bw_unchained`) spawning with `bw_ghost_scythe` in `slot_melee` — engine fatal `Unit not found #ID[877616b4d5c71f36]` (= `units/weapons/player/wpn_bw_ghost_scythe_01/wpn_bw_ghost_scythe_01_3p`, the Necromancer base mesh) inside `world.spawn_unit`. crashify://77917479-d053-4d34-b6b9-629878a7e6ec.

**Cause:** Vanilla `ItemMasterList.bw_ghost_scythe.right_hand_unit_override.bw_unchained = "..._fire"` should redirect Unchained to the `_fire` variant; the package preloader correctly force-loaded `wpn_bw_ghost_scythe_01_fire_3p` for the bot. But at equip time `BackendUtils.get_item_units` returned the BASE unit because `career_name` was `nil` when `gear_utils.create_equipment` called it (the override block at `backend_utils.lua:159-162` is gated on `career_name`). Crash-dump locals show `career_name = "bw_unchained"` at every modded hook frame (`weapon_tweaker:1313`, `cosmetics_tweaker:2542`, `character_weapon_variants:8488`) yet `nil` at the unwrapped `gear_utils.create_equipment` entry — so the hook chain dropped the arg somewhere on the way down to the original. Engine asserts in `world.spawn_unit` bypass pcall (`feedback_vt2_unit_node_not_pcall_safe.md`), so the existing pcall guard didn't help.

**Fix:** In our `GearUtils.create_equipment` hook, if `career_name` arrives nil but `unit_3p` has an `inventory_system` extension, read `_career_name` from it and pass that to `func`. `SimpleInventoryExtension.init` sets `_career_name` before `extensions_ready` fires our hook (`feedback_vt2_mission_spawn_career_lookup.md`), so this is always populated for player/bot mission spawns. 4 lines, weapon-agnostic — protects every weapon that uses per-career `right_hand_unit_override` (the Sienna scythe family + any future ones).

A `mod:warning` on the fallback path will surface other call sites that hit this so we can root-cause the chain pass-through bug separately.

**Files changed:**
- `weapon_tweaker.lua` — version bump, fallback block inside `create_equipment` hook.

## 0.12.22-dev (2026-05-12) — Kruber's Longbow on Saltzpyre with crossbow 3P visuals

New cross-character feature, mirrors the `wh_brace_of_pistols` → repeater pattern from v0.12.2-v0.12.17 but in the opposite direction (Kruber-weapon on Saltzpyre) and with one new wrinkle (LEFT-hand swap + ammo unit swap).

**End-user behavior:**
- Per-career VMF checkboxes for `wh_captain`, `wh_bountyhunter`, `wh_zealot`, `wh_priest` ("Kruber: Longbow", default OFF). Toggle ON to make `es_longbow` equippable on that Saltzpyre career.
- 1P (the player's first-person view): Saltzpyre wields a longbow, fires arrows. Vanilla longbow gameplay — same actions, same damage, same anim events. Per the universal-1P rule (`feedback_1p_animations_universal`).
- 3P (other players' view of Saltzpyre, AND the keep inventory character preview): Saltzpyre appears to wield Saltzpyre's **crossbow** with a **bolt** loaded, playing the crossbow wield + fire 3P animations.

**Implementation (`scripts/mods/weapon_tweaker/weapon_tweaker.lua`):**
- `weapon_unlock_map`: appended `"es_longbow"` to all 4 Saltzpyre career entries.
- `_force_load_sp_crossbow_3p_units()` at mod init: force-loads `wpn_empire_crossbow_tier1_3p` (the crossbow 3P weapon) and `wpn_crossbow_bolt_3p` (the bolt 3P ammo) under references `wt_sp_crossbow_3p` / `wt_sp_crossbow_bolt_3p`. Same async-load pattern the brace-repeater uses.
- `_patch_longbow_empire_template_for_saltzpyre()` at mod init: patches `Weapons.longbow_empire_template` in place — sets `wield_anim_career_3p[wh_*] = "to_crossbow"` (3P wield SM transition) and per-action `anim_event_3p` remaps for events the crossbow 3P SM doesn't author identically: `attack_shoot_fast → attack_shoot`, `attack_shoot_fast_last → attack_shoot_last`, `draw_bow → to_zoom`. Per-career keying means Kruber/Kerillian native wielders see no change.
- New `mod:hook("GearUtils", "spawn_inventory_unit", ...)` parallel to the brace hook. Gates on `item_data.name == "es_longbow"`, `hand == "left"`, career-starts-with-`wh_`. Swaps v_w3p (bow 3P → crossbow 3P) via `Managers.state.unit_spawner:spawn_local_unit_with_extensions` and v_a3p (arrow 3P → bolt 3P) via `GearUtils._attach_ammo_unit`. The bolt attaches using the CROSSBOW template's `ammo_data.ammo_unit_attachment_node_linking.third_person.wielded` (NOT the longbow's arrow linking) so the bolt mounts at the crossbow's nock position. 1P returns left untouched. Full pcall wrap — any failure falls back to vanilla bow/arrow.
- New `mod:hook_safe("MenuWorldPreviewer", "equip_item", ...)` parallel to the brace preview hook. Mutates `info.spawn_data` left_hand entry's `unit_name` → crossbow 3P. No ammo swap in preview (vanilla preview doesn't spawn the bow's arrow). Hooks `MenuWorldPreviewer`, NOT `HeroPreviewer`, per `feedback_inventory_preview_hook_menuworldpreviewer` (the v0.12.17 lesson).

**Files changed:**
- `weapon_tweaker.lua` — version bump, unlock_map (4 lines), force-load block, template patcher, in-game spawn hook, preview hook.
- `weapon_tweaker_data.lua` — 4 new VMF checkboxes (one per Saltzpyre career), all default false.
- `weapon_tweaker_localization.lua` — 4 new "Kruber: Longbow" strings, slotted alphabetically among the existing "Kruber: *" entries.

**Career detection:** uses the v0.12.17 `_unit_career_name` (inventory-extension-first, `Managers.player` fallback) — handles mission-spawn timing correctly. No new helper needed.

**Verification matrix (please test):**
1. Enable `unlock_wh_zealot_es_longbow` (or any career), equip `es_longbow` on that Saltzpyre career.
2. Keep inventory preview: Saltzpyre's preview model holds a crossbow (no visible bolt — preview doesn't render ammo on bows). ✅ if crossbow mesh.
3. Load into a mission: Saltzpyre's 3P body (third-person camera, or another player's view) shows him holding a crossbow with a bolt loaded, playing crossbow wield + fire animations. ✅ if crossbow + bolt + crossbow anims.
4. First-person view in-game: Saltzpyre's 1P shows a longbow + arrow, fires with longbow draw animation, full longbow gameplay (damage profile = arrow_carbine, charge mechanic etc.). ✅ if 1P unchanged from vanilla longbow.
5. Other Saltzpyre career equipping the option: same as above. Try `wh_priest` (notable because it has no native ranged weapon).

**If this does NOT work, here's what to check next, in order:**
- **Crash on equip "Unit not found":** the force-load failed. Look for `[wt sp-longbow-crossbow] force-loaded` in startup log. If absent, the unit paths might be wrong — verify `wpn_empire_crossbow_tier1_3p` and `wpn_crossbow_bolt_3p` resolve. The crossbow unit path was sourced from `wh_crossbow.left_hand_unit + "_3p"` and the bolt from `wh_crossbow.ammo_unit + "_3p"`; if vanilla relies on different package keys for these (unlikely — same code path the brace-repeater uses successfully), use [[reference_vt2_bundle_unpacker]] to brute-hash candidate paths.
- **Bow still showing in 3P:** check log for `[wt sp-longbow-crossbow] swapped`. If absent, the hook isn't firing — confirm career_name resolution (see `feedback_vt2_mission_spawn_career_lookup`). If hook fires but bow still showing, package readiness check might be failing — early return on line 2150ish — temporarily log `Managers.package:has_loaded(_SP_CROSSBOW_3P_UNIT, "wt_sp_crossbow_3p")` to confirm.
- **Crossbow rendered but bolt missing / wrong position:** check log for `arrow→bolt(true)` vs `arrow→bolt(false)`. False means `crossbow_template_1.ammo_data.ammo_unit_attachment_node_linking` was nil — global `Weapons` table might not be loaded at mod init yet. Late-bind by deferring the bolt-linking lookup into the swap pcall body (already done — it reads `Weapons` at swap time, not at module load), but if it's still nil there, try `AttachmentNodeLinking.bolt` directly.
- **Wrong 3P anim:** longbow's per-action `anim_event_3p` overrides might not be enough. Check log for which events fire via the existing `/animlog` command. Saltzpyre's 3P crossbow SM has event names from `Vermintide-2-Source-Code` skeleton dumps — see `reference_3p_skeleton_events`. If the wield is wrong, try `to_crossbow_loaded` instead of `to_crossbow` in `_SP_LONGBOW_CROSSBOW_WIELD_3P`.
- **Keep inventory preview unchanged but in-mission works:** identical class-hook trap to v0.12.16; verify the preview hook is registered on `MenuWorldPreviewer`, not `HeroPreviewer`. (Source check: line containing `if item_name ~= "es_longbow" then return end` should be immediately under `mod:hook_safe("MenuWorldPreviewer", "equip_item", ...)`.)
- **In-mission revert (works in keep, breaks on mission load):** same class as v0.12.16 bug #2 — would mean `_unit_career_name` returned nil. v0.12.17 fix should prevent this; if it still happens, see `feedback_vt2_mission_spawn_career_lookup` fallback notes (try `career_system:career_name()` instead).

**Doc updates:** none beyond this CHANGELOG entry. The patterns this feature uses (MenuWorldPreviewer hook, inventory-extension-first career lookup, force-load pattern, base-template wield_anim_career_3p) are already documented in CLAUDE.md / DEVELOPMENT.md / the four memory entries created in v0.12.17. This release is the second user of those patterns — they now have two reference call sites.

## 0.12.21-dev (2026-05-12) — Authentic Brace: reticle jumps to wide on RMB, secondary speed back to vanilla, secondary spread 16×→12×

Three related changes from user feel-testing v0.12.20.

**Reticle two-step jump fixed** — the user observed the crosshair "unnaturally going from small to large" when entering rapid fire. Root cause: vanilla brace sets `spread_template_override = "pistol_special"` on BOTH `action_two.default` (the RMB lock-target / aim action) AND `action_one.fast_shot` (the rapid-fire shot). v0.12.19's spread-clone patch only walked `action_one.[default|fast_shot|special_action_shoot]` and rewrote their overrides to our wider clone; `action_two.default` was missed, so its override still pointed at vanilla `pistol_special` (max_pitch≈1.0). Result was a two-stage reticle expansion: RMB press → reticle jumps to vanilla pistol_special width, then LMB press → action_one.fast_shot triggers, reticle jumps again to the much wider clone.
- Fix: extended the override-rewrite to walk EVERY action of the template (`for _, sub_actions in pairs(tpl.actions)`), not just `action_one`. Any sub-action with `spread_template_override == "pistol_special"` is rewritten to our wider clone. Now `action_two.default` also uses the wider clone, so the moment RMB is pressed, `WeaponSpreadExtension:override_spread_template()` sets `current_pitch = state_settings.max_pitch` (= 12× the vanilla pistol_special max) and the reticle visually jumps directly to its final wide size with no intermediate stop.
- This matches the behavior the user described — "when the player first takes aim, the reticle should naturally be large to represent the accuracy, like any normal weapon".

**Secondary fire speed back to vanilla** — `_SLOW_MULT` 2.0 → **1.0**. The user said the v0.12.19-v0.12.20 secondary speed ("50% of vanilla") felt too slow and asked to double it. Doubling the speed = halving the duration multiplier = 1.0, which is the no-scaling identity. Practical effect: rapid fire fires at ~4 shots/sec (vanilla cadence) instead of v0.12.19-v0.12.20's ~2 shots/sec. Primary fire / wield / reload still run at 2× speed (`_FAST_MULT = 0.5`), so secondary is now exactly half the speed of primary at vanilla cadence.
- The walker logic that branches on FAST vs SLOW per sub-action / per chain is retained verbatim; with `_SLOW_MULT = 1.0` the "slow" branches are no-ops. Keeping the structure means re-tuning to 1.2 / 1.5 / 2.0 later is a one-line constant change.

**Secondary spread 16× → 12×** — `_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT` dialled back per user feel-test ("16 was too high for inaccuracy"). Primary spread mult stays at 3×. Secondary is now 4× the primary multiplier (was ~5.3× in v0.12.20).

**Files changed:** `scripts/mods/weapon_tweaker/weapon_tweaker.lua`
- Line 24: version bump 0.12.20-dev → 0.12.21-dev.
- `_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT`: 16.0 → 12.0 (comment updated to note action_two.default coverage).
- `_SLOW_MULT`: 2.0 → 1.0 (comment updated; walker structure unchanged).
- Spread-override rewrite loop in step 5: was `for sub_name in ipairs({"default","fast_shot","special_action_shoot"}) do … tpl.actions.action_one[sub_name] …`; now `for _, sub_actions in pairs(tpl.actions) do for _, sub in pairs(sub_actions) do …` — walks every sub-action of every action. New comment explains the two-step reticle jump and why action_two.default needs the rewrite too.
- Doc-block step (2) updated to reference v0.12.19-v0.12.21 history.
- Doc-block step (5) updated: secondary mult value 16.0 → 12.0, mention "applied to EVERY sub-action … incl. action_two.default lock-target" so the reticle behavior is documented.
- Doc-block step (7) updated: speed history (2.0 → 1.0) and the rationale for keeping the split walker structure.
- Info log: re-worded to print the new values and call out the action_two.default coverage.

**Behavior expectations in-game:**
- LMB tap single shot: 2× faster than vanilla, 3× spread. Unchanged from v0.12.20.
- Press RMB (lock-target / aim): reticle jumps directly to the wide secondary size — no two-step expansion, no visible lerp. Spread immediately represents the actual rapid-fire accuracy.
- Hold RMB then LMB → rapid fire: vanilla cadence (~4 shots/sec, was ~2 in v0.12.20), 12× spread (was 16×). Slower than primary, much less accurate than primary, vanilla pacing.
- Reload, mag, damage, ammo unchanged from v0.12.19.

## 0.12.20-dev (2026-05-12) — Authentic Brace: spread tuning pass — primary 4×→3×, secondary 8×→16×

Two-constant tune of the v0.12.19 spread split, per user feel-test. Primary fire is now tighter (single-shot LMB rewards aim more than "spray and pray"), and secondary fire is much sprayer (rapid-fire is now firmly a suppression / point-blank mode, not a substitute for aimed shots).

- `_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT`: 4.0 → **3.0**. Single-shot LMB (action_one.default → default brace spread clone) is ~25% tighter than v0.12.19.
- `_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT`: 8.0 → **16.0**. Rapid-fire (action_one.fast_shot → pistol_special clone) is 2× wider than v0.12.19, ≈5.3× the primary spread.
- Doc-block reference values in the step (5) commentary updated to match.

No mechanical changes — speed, ammo, damage, reload all unchanged from v0.12.19. Pure number tune.

## 0.12.19-dev (2026-05-12) — Authentic Brace: split primary/secondary fire, restore manual reload (6/12, 1-at-a-time)

User request: differentiate the brace's primary (LMB single-shot) and secondary (RMB-hold rapid-fire) modes. Secondary should be slower AND less accurate than primary; primary keeps its 2× speed and current accuracy. Plus they've changed their mind on reload — bring manual reload back, with a small mag and shot-by-shot loading.

**Speed split (step 7, formerly a uniform 2× speedup):** introduced `_FAST_MULT = 0.5` (2× speed, applied to primary and everything else) and `_SLOW_MULT = 2.0` (50% of vanilla speed, applied to secondary fire). The walker now branches per-sub-action:
- `action_one.fast_shot` sub-action itself: SLOW. `total_time` 1 → 2, `reload_time` 0.1 → 0.2 — the rapid-fire shot's own duration doubles vs vanilla.
- Chain `start_time`s use SLOW when the source sub-action is secondary (so fast_shot's self-loop at `start_time=0.25` becomes 0.5 — rapid-fire cadence drops from ~4 shots/sec to ~2 shots/sec) OR when the chain TARGETS fast_shot (so the RMB-into-rapid-fire chain from `action_two.default` at `start_time=0.25` also becomes 0.5 — entering rapid fire from the lock-target pose takes 2× the vanilla delay).
- Everything else (primary single shot, reload, wield, action_two's hold-pose mechanics, special_action_shoot) keeps the FAST mult — unchanged from v0.12.18 behavior. `0`/`math.huge` still skipped.

**Spread split (step 5, formerly a single `_AUTHENTIC_BRACE_SPREAD_MULT=4.0`):** split into two constants:
- `_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT = 4.0` — applied to the cloned brace default spread (single-shot LMB). Unchanged from v0.12.15-v0.12.18; primary fire stays at the same "dramatic" accuracy it had before.
- `_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT = 8.0` — applied to the cloned `pistol_special` spread that `fast_shot` uses via `spread_template_override`. Secondary fire is now 2× more inaccurate than primary. `_wt_clone_spread_wider` gained a `mult` parameter; the two clone callsites pass primary / secondary respectively.

**Reload re-enabled, mag/reserve resized (steps 3 + 4):**
- Step 3 (was: stub `weapon_reload.default.condition_func` / `chain_condition_func` with `_disable_action` to block manual reload): now a no-op. `weapon_reload.default` is left vanilla, so pressing R triggers the normal reload animation. The now-unused `_disable_action` local was deleted.
- Step 4 ammo (was: `clip=12 / per_reload=12 / max=12`, no-reserve, no-per-shot-reload): now `clip=6 / per_reload=1 / max=12`. Mag holds 6, reserve holds 6, each reload animation loads one round; player can keep tapping R to fill the mag round-by-round or interrupt with a shot at any time. Matches a flintlock-pistol-bandolier feel.

**Files changed (one file):** `scripts/mods/weapon_tweaker/weapon_tweaker.lua`
- Line 24: version bump 0.12.18-dev → 0.12.19-dev.
- Lines 1557-1605: doc comment block rewritten (steps 2, 3, 4, 5, 7 all updated to new behavior; step 6 left as historical note).
- Lines 1668-1717: spread mult split into PRIMARY/SECONDARY constants; `_wt_clone_spread_wider` takes a `mult` parameter; the two callsites pass the right one.
- Removed: `_disable_action` local (was only used by the old step 3 manual-reload-disable; no callers left after the step 3 update).
- Step 3 block: now a no-op + explanatory comment (manual reload re-enabled).
- Step 4 block: `ammo_per_clip = 6`, `ammo_per_reload = 1`, `max_ammo = 12`.
- Step 7 block: speed pass rewritten with per-sub-action / per-chain mult selection.
- Info log: now prints primary/secondary spread mults and "primary-speed=2x, secondary-fire-speed=0.5x" separately so the in-game log makes the split visible.

**Behavior expectations in-game:**
- LMB tap single shot: same as v0.12.18 (2× faster than vanilla, 4× spread).
- Hold RMB then LMB → rapid fire: now ~2 shots/sec (vs v0.12.18 ~8 shots/sec; vanilla ~4 shots/sec) with 8× spread — slower than vanilla AND much more inaccurate. Effectively a "spray volley" mode.
- Press R: vanilla manual reload animation runs, loads 1 round. Tap R again, another round, until mag is full or reserve is empty.
- Mag is 6 rounds; full carry is 12.

**No fast_shot chain rewrite** (the v0.12.13 "rewrite every `sub_action == 'fast_shot'` chain to `default`" defense) — keeping the rapid-fire path reachable is now the explicit design intent, since the user wants it to function (just slower and less accurate). Reverted in v0.12.15, not reintroduced here.

## 0.12.18-dev (2026-05-11) — Kruber Longbow on Mercenary and Foot Knight

Added `es_longbow` (Kruber's Empire longbow) to the unlock pool for `es_mercenary` and `es_knight`. Huntsman has it natively; Questing Knight already had it. New checkboxes default to off so existing users see no change until they opt in.

- `weapon_tweaker.lua`: appended `"es_longbow"` to `weapon_unlock_map.es_mercenary` and `weapon_unlock_map.es_knight`.
- `weapon_tweaker_data.lua`: added `unlock_es_mercenary_es_longbow` and `unlock_es_knight_es_longbow` checkboxes in the respective `ranged_*` groups (default `false`).
- `weapon_tweaker_localization.lua`: added the two `"Kruber: Longbow"` strings.

No animation work needed — Mercenary and Foot Knight share Kruber's 3P body skeleton, so the Huntsman longbow event vocabulary applies directly.

## 0.12.17-dev (2026-05-11) — Brace → Repeater swap: fix BOTH preview-path and mission-spawn revert
Two bugs in the v0.12.16-dev attempt. Both fixed here; both produce the same symptom shape (in-game keep model right, somewhere-else wrong) but have different root causes.

**Bug 1 — Inventory preview unchanged.** v0.12.16 hooked `HeroPreviewer.equip_item`. The keep inventory previewer is `MenuWorldPreviewer` (verified: `hero_window_character_preview.lua:171`, `character_selection_view.lua:52`, every `:new(...)` caller of the inventory). VT2's `foundation/scripts/util/class.lua:51-57` COPIES parent methods into the child at class-definition time (no `__index` chain); when `MenuWorldPreviewer = class(MenuWorldPreviewer, HeroPreviewer)` runs at game load, `MenuWorldPreviewer.equip_item` becomes a *static copy* of `HeroPreviewer.equip_item`. VMF `mod:hook("HeroPreviewer", "equip_item", ...)` replaces `HeroPreviewer.equip_item` with a wrapper, but `MenuWorldPreviewer.equip_item` still points at the original unwrapped function — the hook NEVER FIRES on inventory previewer instances. v0.12.16's inline comment claiming "the parent hook fires for both" was the misconception that kept tripping past agents.

Fix: changed BOTH `mod:hook_safe("HeroPreviewer", "equip_item", ...)` hooks (the brace-3P-preview swap and the scale-capture pending-key) to `mod:hook_safe("MenuWorldPreviewer", "equip_item", ...)`. Hook body unchanged. Comment rewritten to call out the class-copy trap and cross-link `feedback_vt2_class_hook_derived`.

**Bug 2 — In-mission 3P reverts to vanilla pistols.** v0.12.16's in-game `GearUtils.spawn_inventory_unit` hook detected Kruber via `_unit_career_name(owner_unit_3p)`, which read `Managers.player:owner(unit):career_name()`. At mission spawn, `SimpleInventoryExtension.extensions_ready` calls `add_equipment_by_category` → `add_equipment` → `GearUtils.create_equipment` → our `spawn_inventory_unit` hook. At THAT moment `Managers.player`'s unit→player reverse association has not yet been re-pointed at the freshly-spawned mission player_unit, so `pm:owner(unit) → nil` and the helper returns nil → hook bails on line 1847 → vanilla brace 3P units returned → Kruber holds the brace in-mission. The keep works because the keep avatar is long-associated.

Fix: rewrote `_unit_career_name` to read `_career_name` from the unit's `inventory_system` extension FIRST. That field is set by `SimpleInventoryExtension.init:47` BEFORE `extensions_ready` fires our hook, so it is always populated by the time the hook runs. `Managers.player` retained as fallback for husk / post-spawn lookups.

**Versions changed:** `MOD_VERSION` 0.12.16-dev → 0.12.17-dev.

**Files changed (one file):** `scripts/mods/weapon_tweaker/weapon_tweaker.lua`
- Line 24: version bump
- Lines 841-856: `_unit_career_name` rewritten (inventory-ext-first, Managers.player fallback)
- Lines 1957-1996: brace-preview hook class swapped + comment rewritten
- Lines 2027-2050: scale-capture hook class swapped + comment trimmed

**Verification matrix (please report which still fails):**
1. Equip brace on Kruber in keep → in-keep 3P shows repeater (worked in v0.12.16, should still work).
2. Open inventory at keep → Kruber preview model shows repeater (NEW — bug 1 fix).
3. Load into mission → Kruber's in-mission 3P shows repeater (NEW — bug 2 fix).
4. Other player joins → husk Kruber shows repeater for them (existing path; husks use `simple_husk_inventory_extension` which still routes through the spawn hook — career resolution goes through Managers.player fallback for husks since husk extension key may differ from "inventory_system"; flag if this regresses).

**If this fix does NOT work, here is what to check next, in order:**
- **Check the in-game log** (`mod:info` messages tagged `[wt brace-3p-swap]` and `[wt brace-3p-swap preview]`) — they print career_name and indicate which path was taken. Silence means the hook didn't fire at all. Non-silence with "kept vanilla unit" means a pcall failed inside the swap body.
- **If preview still wrong (bug 1 still present):** add `mod:echo` at the top of the `MenuWorldPreviewer.equip_item` hook to confirm it's firing at all. If it's not, the keep inventory might be using a DIFFERENT class derived from `MenuWorldPreviewer` (e.g. a subclass) that copied AGAIN — hook that one instead. Verify with `local cls = getmetatable(self); print(cls.__name or tostring(cls))` inside the hook.
- **If mission-spawn revert still present (bug 2 still present):** the `_career_name` field on the inventory_system extension might not be named `_career_name` on the active inventory class. Add a printf with `ext._career_name` and `ext.career_name` and `ext.career_extension and ext.career_extension:career_name()` to figure out which field is populated. Alternative source: `ScriptUnit.extension(unit, "career_system"):career_name()` — the career extension is also registered on the player unit before extensions_ready.
- **Husk path (other players' view of Kruber):** husks use `SimpleHuskInventoryExtension` and might register under a different extension key (`simple_husk_inventory` rather than `inventory_system`). If the husk view shows the wrong thing, expand `_unit_career_name`'s primary probe to also try the husk extension key.
- **Package not loaded race:** the in-game swap pcall body explicitly bails (`return v_w3p`) when `Managers.package:has_loaded(_BRACE_REPEATER_3P_UNIT, "wt_brace_repeater_3p")` is false. If mission load loses the reference (it shouldn't — the load is under our mod's reference at module init, no level transition releases that), the swap silently no-ops. Look for the `mod:info("force-loaded repeater 3P unit")` line on startup; absence means the force-load failed.

## 0.12.16-dev (2026-05-11) — Brace → Repeater swap: cover inventory character preview path (SUPERSEDED by 0.12.17-dev — see above for why)
- Fixed: the brace-of-pistols → repeater 3P swap on Kruber didn't apply to the inventory character preview screen — the preview still rendered the brace's two-pistol mesh while in-game 3P (other players' view of your Kruber) correctly showed the Empire repeating handgun. Cause: the v0.1.187 migration hooked `GearUtils.spawn_inventory_unit` for the in-game equip flow (path 1), but `HeroPreviewer` / `MenuWorldPreviewer` use a different code path — they call `World.spawn_unit(world, unit_name)` directly from a precomputed `spawn_data` table built in `HeroPreviewer.equip_item` (path 2, per `CLAUDE.md` "Three Weapon Rendering Paths"). The spawn_inventory_unit hook never fires for the previewer, so the brace mesh shipped through unmodified.
- Fix: new `mod:hook_safe("HeroPreviewer", "equip_item", ...)` post-hook. When the equipped item is `wh_brace_of_pistols` and `self._current_career_name` starts with `es_` (Kruber career), mutate `self._item_info_by_slot[slot_type].spawn_data` before `_spawn_item` reads it:
  - Right-hand entry: rewrite `unit_name` → `_BRACE_REPEATER_3P_UNIT` (the same repeater 3P unit path the in-game hook spawns).
  - Left-hand entry: drop it. Mirrors the existing `show_third_person_inventory` left-pistol-hide hook — the brace's left pistol would otherwise clip through the repeater's body.
- Package readiness is already taken care of: the repeater 3P unit is force-loaded at mod init via `_force_load_brace_repeater_3p_unit()` (Managers.package:load with prioritize=true), so `World.spawn_unit` in the previewer resolves the resource without needing a per-previewer package load.
- MenuWorldPreviewer (the post-WoM inventory previewer) inherits from HeroPreviewer and doesn't define its own `equip_item`, so the parent hook fires for both — same pattern the adjacent scale-pending-key hook relies on.

## 0.12.15-dev (2026-05-10) — Authentic Brace: lean into rapid-fire, dramatic spread, 12-round mag
- Reverted: step 2 (the `action_two.default` mutation that replaced the vanilla lock-target/fast-shot gate with a `kind="aim"` handgun-style zoom) — gone. action_two.default is left untouched. Right-click does the vanilla lock_target + fast_shot rapid-fire chain. Rationale: rapid fire kept surfacing through paths we couldn't fully exorcise (v0.12.10–v0.12.13 chased it through `lookup_data`, the 3P camera tree, the chain rewrite); the user would rather lean in than keep firefighting.
- Reverted: step 6 (the defensive walk that rewrote every `chain.sub_action == "fast_shot"` to `"default"`) — gone. fast_shot's own self-loop is allowed to function as vanilla intended. Combined with the speed-up that's still in step 7, rapid fire is fast.
- Changed: `_AUTHENTIC_BRACE_SPREAD_MULT` 1.087 → **4.0**. Every numeric leaf on the cloned `brace_of_pistols` spread template scales 4× (`max_pitch` / `max_yaw` / `immediate_pitch` / `immediate_yaw` across every stance — still / moving / crouch / zoomed). The result is dramatic spread on every single shot.
- Added: parallel `pistol_special` clone (`wt_authentic_brace_pistol_special_spread`), also 4× scaled. The vanilla `pistol_special` spread is what `action_one.fast_shot` and `action_one.special_action_shoot` use via `spread_template_override` (≈ rapid-fire). Without scaling this one too, the "dramatic" feel only shows on single shots and rapid fire stays at vanilla pistol_special accuracy. Now both modes are equally inaccurate.
- Reverted: ammo cap 8 → 12. Restores the v0.12.6 cap; per user feedback 8 was too strict. `ammo_per_clip = ammo_per_reload = max_ammo = 12`. No-reserve / no-per-shot-reload behavior unchanged.
- Updated: description only on the accuracy bullet — "~8% (spread widened proportionally on all stances)" → "DRAMATICALLY reduced — spread widened 4× on every stance (and on rapid-fire / pistol_special too)". Other bullets left as-is per the literal request, including the now-stale "Right-click (aim down sights / rapid-fire mode) is disabled" line (gameplay is back to vanilla on that path; leave as-is unless asked to revise).

## 0.12.14-dev (2026-05-09) — Authentic Brace: 2x penetration
- Added: `wt_authentic_pistol` damage profile clone now halves `cleave_distribution.attack` and `cleave_distribution.impact` from shot_sniper's vanilla 0.3/0.3 → 0.15/0.15. Each target consumes half the cleave power, so the projectile passes through roughly twice as many enemies. Vanilla shot_sniper penetrates ~3 targets; Authentic Brace shots now penetrate ~6.
- Implementation lives in `_wt_clone_shot_sniper_no_dropoff()` alongside the dropoff-flattening pass — runs once at module init when the toggle is on, registered in `NetworkLookup.damage_profiles` like before. No new network surface area.

## 0.12.13-dev (2026-05-09) — Authentic Brace: kill fast_shot rapid-fire path
- Fixed: holding right-click and clicking after reload (or other action transitions) could put the brace into `action_one.fast_shot`, whose `allowed_chain_actions` self-chain at `start_time = 0.25` — halved to 0.125 by the v0.12.12 2x speed pass, that's ~8 shots/sec rapid-fire. v0.12.10's action_two.default mutation removed the obvious vanilla path (action_two → fast_shot at lines 303/309 of `brace_of_pistols.lua`), but at least one path the user found still reached fast_shot.
- Fix: defensive walk of every sub-action's chain table — any chain entry whose `sub_action == "fast_shot"` is rewritten to `"default"`. Touches fast_shot's own self-loop (lines 132/144 of the brace template), so even if some unaccounted-for path lands the player in fast_shot, the chains exit to single-shot after one shot. Belt-and-suspenders: also rewrites any other action's chains that happen to point at fast_shot. Done as new step (6) in `_apply_authentic_brace_mode`, before the 2x-speed pass (now step 7), so the speed-up sees the fixed chain entries.

## 0.12.12-dev (2026-05-09) — Authentic Brace: hide off-hand pistol, 8-round cap, 2x action speed
- Fixed: in 3P, Kruber's repeater swap left the **left-hand brace pistol** still rendering, clipping through the repeater. The right-hand 3P swap (in `GearUtils.spawn_inventory_unit` hook) only fires for `hand == "right"`. Hooking the spawn for the left hand and hiding it isn't sufficient because `SimpleInventoryExtension.show_third_person_inventory` (`simple_inventory_extension.lua:1014-1075`) flips visibility back to `true` on every wield. New approach: post-hook `show_third_person_inventory` and force `equipment.left_hand_wielded_unit_3p` invisible whenever the wielded item is `wh_brace_of_pistols` and the wielder's career starts with `es_` (Kruber). Mirrors the visibility-group branching vanilla uses so it applies to whichever path the unit was rendered through. Active regardless of the authentic-brace toggle — the left pistol is unwanted on Kruber whether or not the brace is "authenticated".
- Changed: `Authentic Brace of Pistols` ammo cap reduced 12 → 8. `ammo_per_clip = 8`, `ammo_per_reload = 8`, `max_ammo = 8`. Matches the brace's "8 pistols on the bandolier" cosmetic. No-reserve / no-per-shot-reload behavior from v0.12.8 is unchanged.
- Added: 2x action speed when the toggle is ON. Walks `Weapons.brace_of_pistols_template_1.actions[*][*]` and halves `total_time`, `total_time_secondary`, `fire_time`, `minimum_hold_time`, `cooldown`, `reload_time`, and every `allowed_chain_actions[*].start_time`. `0` and `math.huge` are skipped (preserves "instant" and "hold-forever" semantics). Applied last in `_apply_authentic_brace_mode` so the new aim action's fields from step (2) (`minimum_hold_time = 0.3`, `cooldown = 0.3`) get halved too — zoom snaps in/out at 0.15s.

## 0.12.11-dev (2026-05-09) — Fix Authentic Brace zoom crash in 3rd-person mode
- Fixed: right-click aim crashed in 3rd-person mode at `camera_manager.lua:387` (`attempt to index field 'node' (a nil value)`). v0.12.10 set `default_zoom = "first_person_node"` on the aim action. `GenericStatusExtension.set_zooming` (`generic_status_extension.lua:1519`) appends `_third_person` to the camera name when 3P mode is on, producing `"first_person_node_third_person"` — which doesn't exist in the camera tree. `CameraManager.set_camera_node` then constructs `next_node = { node = tree.nodes[node_name] }` with `node = nil` and crashes when it dereferences it later in the function.
- Fix: clear `default_zoom` (set to `nil`). Engine default is `"zoom_in"`, which has both `zoom_in` and `zoom_in_third_person` defined in `camera_settings.lua:18-19` — works in either camera mode. Vanilla Empire handgun also omits this field for the same reason; matching that prior art.
- Compatible with general_tweaker's third-person camera toggle. Right-click in 3P now zooms the over-shoulder camera in just like the handgun does.

## 0.12.10-dev (2026-05-09) — Fix Authentic Brace right-click crash (lookup_data preservation)
- Fixed: right-click on the brace with the toggle ON crashed at `action_utils.lua:834` (`attempt to index field 'lookup_data' (a nil value)` in the user's runtime, line 927 in their build). v0.12.9 replaced `Weapons.brace_of_pistols_template_1.actions.action_two.default` with a freshly-constructed table — but at game load `weapons.lua:312` walks every weapon template and attaches `lookup_data = { item_template_name, action_name, sub_action_name }` to each sub-action. `ActionUtils.resolve_action_selector` dereferences that field on every action transition; a fresh table without it crashed on the first right-click.
- Fix: mutate the existing `action_two.default` table in place instead of replacing it. Strip the dummy/lock-target fields (`anim_event`, `anim_end_event`, `anim_end_event_condition_func`, `spread_template_override`, `buff_data`) and overwrite the rest with the aim-action config. `lookup_data` and any other engine-attached metadata stays attached. End-user behavior identical to the v0.12.9 intent: handgun-style FOV zoom on right-click, no animation.

## 0.12.9-dev (2026-05-09) — Authentic Brace: right-click is now handgun-style zoom (no anim)
- Changed: `action_two.default` is now a clean optical zoom instead of being disabled outright. v0.12.6 left it as a dead `kind="dummy"` (lock-target pose, fast-shot mode) with `condition_func = always_false` to short-circuit it; v0.12.9 replaces it with a fresh `kind="aim"` action that triggers the engine's standard zoom path (`set_zooming(true, default_zoom)` in `action_aim.lua:134`) with `default_zoom = "first_person_node"` — same zoom the Empire handgun uses on right-click.
- No animation: `anim_event` and `anim_end_event` are deliberately omitted. The brace's state machine (`dual_pistol`) doesn't have `to_zoom`/`to_unzoom` events so any anim would be a missing-event warning anyway, and the user wanted "no ADS animation, just a zoom" specifically. The shoulder stays at hip; the camera FOV tightens.
- Chain actions: while zoomed, `action_one` (left-click) still fires the regular shot, `weapon_reload` and `action_wield` still chain — same set the handgun exposes. `fast_shot` and the lock-target pose are unreachable now (action_two no longer leads to them).
- `condition_func` mirrors the handgun: aim is denied if `total_remaining_ammo <= 0`, so an empty brace can't pretend to zoom. `unzoom_condition_function` follows the standard "don't unzoom on interrupting action" idiom.
- `_disable_action` (the always-false sentinel) is still in use for `weapon_reload.default` — only the action_two patch path changed.

## 0.12.8-dev (2026-05-09) — Authentic Brace: no reload animation between shots
- Changed: with `Authentic Brace of Pistols` ON, ammo is now `ammo_per_clip = 12 / ammo_per_reload = 12 / max_ammo = 12` instead of `1 / 1 / 12`. The whole 12-round pool lives in the clip, reserve is zero. Player clicks → fires → clicks → fires straight through 12 shots with no reload animation between any of them.
- How it works: `weapon_reload.auto_reload.condition_func` (`brace_of_pistols.lua:475`) returns `ammo_count() == 0 AND can_reload()`. With clip == max_ammo, the clip is non-empty until the very last shot, so the auto-reload chain — still wired in `action_one.default.allowed_chain_actions` — never gates true and the animation never plays. After the 12th shot, `can_reload()` is also false (reserve=0), so even the empty-click moment doesn't trigger an animation. Effectively the brace becomes a 12-round magazine that just runs out when empty (until ammo pickup).
- Trade-off: starting reserve goes from 11 to 0. Total ammo capacity is unchanged at 12 — you're still firing the same number of shots per ammo refill, just with all of them immediately accessible instead of staged through a chamber.

## 0.12.7-dev (2026-05-09) — Authentic Brace damage profile NetworkLookup fix
- Fixed: `Authentic Brace of Pistols` toggle silently did nothing in v0.12.6. The cloned damage profile `wt_authentic_pistol` was added to `DamageProfileTemplates` but never registered in `NetworkLookup.damage_profiles`. That lookup is built once at game-load (`network_lookup.lua:2203`) and frozen with an `__index` metatable that errors on unknown keys (`:2356`); `PlayerProjectileUnitExtension._init` (`:92`) does `NetworkLookup.damage_profiles[impact_data.damage_profile]` at every projectile spawn, so every brace shot threw and the firing path bailed out before any damage was applied — making the entire toggle invisible in-game.
- Fix: mirror the CWV pattern (`character_weapon_variants.lua:1364`) — after inserting the clone into `DamageProfileTemplates`, also `rawset` the key into `NetworkLookup.damage_profiles` at both `#tbl+1` (numeric → string) and `[key]` (string → numeric) so projectile spawn finds a valid network ID.
- Spread template clone (`wt_authentic_brace_of_pistols_spread`) didn't need the same treatment — `SpreadTemplates` isn't in `NetworkLookup` and is read by-reference at fire time.
- All other v0.12.6 patches (ammo_data clip/reload/max, `weapon_reload.default` condition_funcs, `action_two.default` ADS gate, `ignore_shield_hit` per sub-action) were already applying correctly; only the damage-profile path was broken.

## 0.12.6-dev (2026-05-09) — Authentic Brace of Pistols toggle
- Added: new `Weapon Overrides → Authentic Brace of Pistols` VMF setting (default OFF). When ON, patches `Weapons.brace_of_pistols_template_1` in place at mod init with five behavior changes that turn the brace into a flintlock-style single-shot pistol:
  - **Damage**: every firing sub-action's `impact_data.damage_profile` switches from `shot_carbine` to `wt_authentic_pistol` (a clone of Kruber's handgun's `shot_sniper` with the near→far dropoff flattened — full damage at all ranges). Plus `ignore_shield_hit = true` on the firing sub-actions, mirroring the handgun's shield-break behavior.
  - **No ADS / rapid-fire**: `action_two.default.condition_func` returns false, so right-click no longer enters lock-target mode. The `fast_shot` chain it gates is unreachable, leaving only the single-shot left-click.
  - **No manual reload**: `weapon_reload.default` `condition_func` and `chain_condition_func` both return false. The `auto_reload` chain (`auto_chain = true`) still fires automatically from action_one and refills the chamber after each shot — same pattern as throwing axes / bows.
  - **Ammo**: `ammo_per_clip = 1`, `ammo_per_reload = 1`, `max_ammo = 12` (vanilla: clip 12 / reload 2 / max 30). One shot in the chamber, auto-loads the next from a 12-round reserve.
  - **Spread**: `default_spread_template` switches to `wt_authentic_brace_of_pistols_spread`, a clone of `SpreadTemplates.brace_of_pistols` with every `max_pitch` / `max_yaw` / `immediate_pitch` / `immediate_yaw` scaled by 1.087 (~8% wider = ~8% less accurate). Recursive scale walk handles the nested `continuous` / `immediate` / per-stance leaves.
- Toggle requires a restart to apply or revert — the patches are applied in place to the global `Weapons.brace_of_pistols_template_1` and there's no snapshot of vanilla state to restore from.
- Affects every wielder of the brace (Saltzpyre native + Kruber via WT cross-access). The 3P unit swap on Kruber is independent of this toggle and continues to work as before.

## 0.12.5-dev (2026-05-09) — Brace of Pistols 3P-swap package fix
- Fixed: Kruber equipping `wh_brace_of_pistols` crashed with `[Script Error]: Unit not found` when the brace-3P-swap hook tried to spawn the Empire repeater rifle 3P unit (crash GUID d9e1d3d3). The repeater unit's per-unit package isn't pre-loaded by the brace's vanilla inventory package — Saltzpyre never needed it because his brace 3P stays the brace, and Kruber's other career packages don't share assets with Saltzpyre's repeater-rifle pool.
- Fix mirrors the CWV Tuskgor-Javelin pattern (`feedback_cwv_cross_character_unit_packages.md`): force-load the repeater 3P unit at WT mod init via `Managers.package:load(unit_path, "wt_brace_repeater_3p", nil, async=true, prioritize=true)`. Stingray treats the unit path as a synthetic per-unit package, same way `PickupPackageLoader` does — by the time any equip flow runs, the resource is loaded and `spawn_local_unit_with_extensions` finds it.
- Defensive guard: the swap hook now checks `Managers.package:has_loaded(_BRACE_REPEATER_3P_UNIT, "wt_brace_repeater_3p")` before attempting the spawn, falling back to vanilla brace 3P unit if the load hasn't completed yet (rare race during very-early equip before the async load lands).

## 0.12.4-dev (2026-05-08) — Adventure trait pool toggles + Chaos Wastes traits
- Added: new collapsible `Weapon Traits (Adventure)` group in the VMF settings with four sub-groups:
  - `Adventure Melee Traits` — checkboxes for the 6 vanilla melee traits (Swift Slaying, Parry, Off Balance, Heroic Intervention, Resourceful Combatant, Opportunist). All default ON.
  - `Adventure Ranged Traits` — checkboxes for the 8 unique vanilla ranged traits across the `ranged_ammo` and `ranged_heat` pools (Inspirational Shot, Scrounger, Conservative Shooter, Resourceful Sharpshooter, Hunter, Barrage, Thermal Equalizer, Heat Sink). All default ON.
  - `Chaos Wastes Melee Traits` — 15 CW traits (Shockwave, Armor Breaker, Shield of Isha, Bloodthirst, Headhunter, Home Run, Shield of Splinters, Serrated Blade, Crescendo Strike, Follow Up, Always Blocking, Big Swing Stagger, Crit Chain Lightning, Collateral Damage, melee Heal on Crit). All default OFF.
  - `Chaos Wastes Ranged Traits` — 5 CW ranged-only traits (Refilling Shot, Piercing Projectile, Extra Shot, Ranged Crit Explosion, Ammo Pickup Reload Speed). All default OFF.
- Mechanism: rewrites `WeaponTraits.combinations[melee/ranged_ammo/ranged_heat/trollhammer_torpedo]` in place to reflect the toggles. Existing CW traits are already in `WeaponTraits.traits` and `BuffTemplates` (merged at game load by `weapon_traits_morris.lua`) — they only failed to appear in adventure crafting because the vanilla pools didn't list them.
- UI gating: the two `Chaos Wastes …` groups are stripped from the widget tree when `crafting_in_modded` is not installed (mirrors the existing `_strip_cwv_widgets` pattern). The runtime always honours stored values regardless of cim presence.
- Lifecycle: trait filters re-apply on `on_setting_changed` (any `trait_*` or `cw_trait_*` id) and on `on_game_state_changed`. `on_disabled` reverts the pools to a snapshot captured on first apply.
- Empty-pool safety: if every toggle in a pool ends up off, the pool falls back to the captured vanilla snapshot rather than leaving cim's reroll with nothing to pick.
- Cross-mod contract: `crafting_in_modded` already reads `WeaponTraits.combinations[trait_table]` dynamically (no hardcoded keys) so weapon_tweaker's mutations propagate automatically. Documented this contract above `_reroll_traits` in `cim/standard_forge.lua` to lock in the design.

## 0.12.3-dev (2026-05-08)
- Wired: `wh_brace_of_pistols` checkbox in `_data.lua` for all 4 Kruber career ranged groups + matching `_localization.lua` labels ("Saltzpyre: Brace of Pistols"). v0.12.2 added the unlock to `weapon_unlock_map` but missed the UI checkbox definitions — without those the unlock UI didn't surface the option, so the user couldn't actually toggle it on. Default OFF (per the existing pattern for cross-character ranged weapons).
- Removed: `unlock_es_*_dr_handgun` checkboxes for all 4 Kruber careers + the `dr_handgun` entry in each Kruber career's `weapon_unlock_map` list + the matching localization entries. Per user — Bardin's Handgun ("rifle") was a cross-character cosmetic curiosity that the user doesn't want surfaced as a Kruber option. Bardin's natives (`dr_ranger`, `dr_ironbreaker`) and the other Bardin careers' lists are unchanged.

## 0.12.2-dev (2026-05-08) — Brace of Pistols on Kruber (migrated from CWV)
- Added: `wh_brace_of_pistols` cross-access on all 4 Kruber careers (`es_mercenary` / `es_huntsman` / `es_knight` / `es_questingknight`) in `weapon_unlock_map`. Kruber can now equip Saltzpyre's brace via the standard wt unlock UI.
- Added: 3P unit swap hook on `GearUtils.spawn_inventory_unit`. When a Kruber career equips `wh_brace_of_pistols`, the brace's 3P body unit is destroyed and replaced with the Empire repeating handgun mesh (`wpn_emp_handgun_repeater_t1_3p`). The 1P side keeps the brace cross-arm fire animation, so the user sees the brace in first-person but other players (and the inventory preview) see Kruber wielding a repeater. Pcall-wrapped: any swap failure returns vanilla units unchanged → equipping never breaks because of this hook.
- Added: base `brace_of_pistols_template_1` patches scoped to Kruber careers — `wield_anim_career_3p` for `es_*` → `to_repeating_handgun` (Kruber's vanilla repeater wield SM), and per-action `anim_event_3p` remap for `special_action` (the brace's fire-all-8-pistols finisher) → `attack_shoot_fast` (closest repeater clip; the special_action event isn't authored on Kruber's repeater SM). Saltzpyre native wielders fall through unchanged.
- Migrated from `character_weapon_variants` v0.1.189 — the previous `cwv_es_brace_repeater` standalone variant + `_cwv_3p_unit_override_swap` infrastructure has been removed from CWV. Same end-user behavior, but lives on the vanilla brace cross-access path now (no separate inventory item).

## 0.12.0-dev (2026-05-05) — Crafting subsystem split out into Crafting in Modded mod
The entire Athanor crafting subsystem (~1800 lines: NetworkLookup patch, forge persistence, Athanor UI hooks, BackendInterfaceWeavesPlayFab redirects, HeroWindowWeaveForgeWeapons hooks, `/forge*` console commands, `/craft_dump` command, `forge_hotkey` keybind) has been moved into a new sibling mod, `crafting_in_modded` (internal ID `cim`). Weapon Tweaker now focuses solely on cross-career weapon unlocks, animation remapping, and scale/offset.

Migration note: weapons crafted under prior versions of `wt` are saved under the `wt` namespace and will not be migrated to `cim`. They are session-only artifacts and will be lost on the upgrade.

## 0.11.20-dev (2026-05-05) — Deduplicate crafting weapon list
- Crafting menu now deduplicates entries by `display_name` — no more duplicate weapons in the list.
- Excluded `promo` rarity items (player's own crafted weapons) from appearing as craft templates.
- Removed `backend_id` lookup from list population (unnecessary for a craft template catalogue).

## 0.11.19-dev (2026-05-05) — Fix startup rehook warnings
- Merged duplicate `HeroPreviewer.equip_item` hook_safe registrations into one (removed dead debug probe).
- Merged duplicate `BackendManagerPlayFab._create_interfaces` hook_safe registrations via forward-declared `_athanor_inject_all`.
- Eliminates two `[WARNING] Attempting to rehook active hook` messages on startup.

## 0.11.18-dev (2026-05-05) — Fix crafted items treated as MIL templates
- Crafted (promo) weapons now inject via `backend_mirror:add_item()` instead of MoreItemsLibrary. Fixes: template-style gray background, blocked cosmetic editing.
- Added `_athanor_inject_item` / `_athanor_inject_all` functions for promo item lifecycle.
- `_forge_inject_all` now skips promo items (handled by Athanor path instead).
- Persistence: `_forge_save` now stores `rarity` and `traits` array.
- Weapon list: cleared "Magic Level" / "1800" power text from craft template entries.
- Added `/craft_dump` diagnostic command for rarity/localization/backend debugging.

## 0.11.17-dev (2026-05-02) — Dual axes: distinct light chain animations
v0.11.15's light remaps collapsed L1, L3, L4 onto the same dual_hammers `attack_swing_left` (L1 swing), making 3 of the 5 lights look identical. Spread them across all 5 dual_hammers light anim_events instead:
- L2 release `attack_swing_right_diagonal` → `attack_swing_left` (dual_hammers L1)
- L3 release `attack_swing_left` → `attack_swing_down` (dual_hammers L2)
- L4 release `attack_swing_right` → `attack_swing_up` (dual_hammers L4)
- L5 release `attack_swing_down` → `attack_swing_stab` (dual_hammers L5)
- L1 release `attack_swing_left_diagonal` left native — plays as dual_hammers L3 swing.

Heavy chain unchanged (user confirmed perfect in v0.11.15).

## 0.11.15-dev (2026-05-01) — Dual axes: per-attack remaps to dual-hammers SM
Animlog from v0.11.13 dr_ranger play showed all attack events firing without `[MISSING]` tags but several producing no visible 3P animation — the dual-hammers SM (loaded by the wield redirect) doesn't have transitions for dual-axe-specific events. Added template-based remaps in `_3p_template_remaps[dual_wield_axes_template_1]` for the 5 problematic events:
- `attack_swing_charge_diagonal` → `attack_swing_charge_left` (L3 + H3 charge windup)
- `attack_swing_heavy_right` → `attack_swing_heavy_right_diagonal` (H1 release)
- `attack_swing_heavy` → `attack_swing_heavy_down` (H2 release)
- `attack_swing_right_diagonal` → `attack_swing_left_diagonal` (L2)
- `attack_swing_right` → `attack_swing_left` (L4)

Per-career entries for `dr_ironbreaker` / `dr_ranger` / `dr_engineer`; `dr_slayer` has no entry so `_resolve_template_remap` returns nil and native dual-axes animations play. Targets are the dual_hammers template's anim_events — `Unit.has_animation_event` was TRUE on the original events too (per memory rule), so visual confirmation is the only test that matters.

## 0.11.13-dev (2026-05-01) — Dual axes on Bardin's non-Slayer careers
- Added `to_dual_axes` → `to_dual_hammers` redirect for non-`dr_slayer` careers. `dr_dual_wield_axes` is already unlocked for Ironbreaker/Ranger/Engineer in `weapon_unlock_map`, but `to_dual_axes` is the Slayer-only wield event — without this redirect, the 3P SM stays in idle on the other Bardin careers and no attack animations play. Mirrors the v0.9.116 pattern used for `to_dual_hammers_priest`. Slayer is unaffected (matches the prefix and skips the redirect). Per-attack remaps may follow once `/animlog` reveals which dual-axe-specific events (`attack_swing_charge_diagonal`, `attack_swing_heavy_right`, `attack_swing_heavy`, `attack_swing_right_diagonal`, `attack_swing_right`) don't animate on the dual-hammers SM.

## 0.11.8-dev (2026-05-01) — Migrated to VMB build pipeline

Moved from the raw Stingray SDK build (`wt.mod`, `settings.ini`, `lua_preprocessor_defines.config`, `.build/OUT/`) to VMB (`weapon_tweaker.mod`, `itemV2.cfg`, `bundleV2/`). Workshop ID `3712896117` and internal mod ID `"wt"` preserved — existing user settings are unaffected. `itemV2.cfg` set to `visibility = "private"`.

Intermediate dev versions 0.11.5–0.11.7 were undocumented in this changelog; treat them as iterative cleanup leading into the VMB migration.

## 0.11.4-dev (2026-05-01) — Crafted items: promo rarity (purple icon background)
- **Crafted items now use `"promo"` rarity** — purple icon background (`icon_bg_promo`). Patches `NetworkLookup.rarities` at mod init to add `"promo"` entry, preventing the `NetworkLookup.lua` crash on equip (v0.11.3 used `"promo"` without the lookup patch → crash on re-equip).

## 0.11.3-dev (2026-04-30) — Crafted items: promo rarity attempt (BROKEN)
- Set crafted item rarity to `"promo"` for purple background. **Crashed** on equip: `NetworkLookup.rarities` doesn't contain `"promo"`. Reverted in 0.11.4.

## 0.11.2-dev (2026-04-30) — Mod Weapon Crafting: live property/trait apply
- **Bubble grid changes now apply to the real item.** Added `_forge_apply_to_item()` — converts weave-format properties (slot indices → float values) and traits (weave keys → regular keys) back to the backend item on every set/remove. Also updates `CustomData` JSON for persistence within the session.

## 0.11.1-dev (2026-04-30) — Mod Weapon Crafting: property slot overlap fix
- **Fixed bubble grid slot collision.** Property slot indices now assigned sequentially across all properties (property 1 → slots {1,2,...}, property 2 → slots {N+1,...}) instead of both starting from slot 1. Prevents properties from overriding each other in the weave forge grid.

## 0.11.0-dev (2026-04-30) — Mod Weapon Crafting: item creation system
- **Client-side item crafting.** "Choose Weapon" now shows ALL career weapons (not weave templates). Selecting a weapon and clicking "CRAFT" creates a new item via `backend_mirror:add_item()` with `Application.guid()` backend IDs, power 300, exotic rarity.
- **Hooked 5 methods on `HeroWindowWeaveForgeWeapons`:** `_present_item` (no locked state), `_set_presentation_locked_state` (never locked), `_update_equip_button_status` (CRAFT label), `_on_list_index_selected` (always enable craft), `_equip_item` (create + equip item).
- Crafted items are session-only — lost on game restart (PlayFab resync).

## 0.10.42–0.10.47-dev (2026-04-30) — Forge UI: panel positioning polish
- Iterated icon and text positioning within overview/properties/trait panels. Final offsets: overview Y=740 (icon internal Y=-20), properties Y=500 (option text nudged -10), trait Y=310.

## 0.10.34–0.10.41-dev (2026-04-30) — Forge UI: item detail panels on hover, viewport polish
- **Item detail panels on hover.** Hovering melee (viewport 1) or ranged (viewport 3) shows the weapon's overview, properties, and trait panels in the center viewport 2 area — uses `UIWidgets.create_item_option_overview/properties/trait` factory widgets initialized via `UIWidget.init()`.
- **Viewport 2 (amulet) hidden** — unused in mod forge, all viewport 2 widgets set to `content.visible = false`.
- **Hover highlight color** changed from white to grey (123, 123, 123 RGB).
- **Panel positioning** iterated across multiple versions to align icon, properties, and trait vertically (final offsets: overview Y=630, properties Y=470, trait Y=320).

## 0.10.33-dev (2026-04-30) — Forge UI: hover highlights to white, cluster glow recolor
- Overview viewport hover highlights (`viewport_button_highlight_`, `viewport_button_text_highlight_`) recolored from purple to white.
- Properties sub-menu `cluster_background_effect_1` recolored from purple to deep red.

## 0.10.32-dev (2026-04-30) — Forge UI: enhanced forge_dump_props diagnostics
- `forge_dump_props` command now reports preview state (`_viewport_widget`, `_item_previewer`, `_previewer_initialized`) and property/trait key mapping results for debugging the properties sub-menu.

## 0.10.31-dev (2026-04-30) — Forge UI: properties sub-menu power fix, additional widget hiding
- Properties sub-menu power display now reads from `params.selected_item.backend_id` (was nil via `_item_backend_id`). Shows real weapon power instead of spoofed 1800.
- Additional widget hiding in properties layout: level title/value, mastery, upgrade button, wheel rings.

## 0.10.30-dev (2026-04-30) — Forge UI: forge_dump_props diagnostic command
- Added `/forge_dump_props` command using `mod:echo` (always flushes) instead of `mod:info`. Dumps properties window widgets, `params.selected_item`, and property/trait key mapping results.

## 0.10.15–0.10.29-dev (2026-04-29–30) — Mod Weapon Crafting forge UI
### Added
- **Athanor forge repurposed as Mod Weapon Crafting UI.** Opens via B hotkey. Backend hooks (`BackendInterfaceWeavesPlayFab`) intercept all weave loadout queries to serve real equipped weapon data.
- **Property/trait pre-fill from real items.** `_forge_seed_item()` reads equipped weapon's `.properties` and `.traits`, maps regular keys to weave-prefixed keys (`crit_boost` → `weave_crit_boost`), and converts float values to bubble-slot arrays. Seed persists across edits so adding/removing properties doesn't discard existing data.
- **`/forge_dump` command** for traversing forge UI widget hierarchy (`ingame_ui.views[current_view]._machine._state._active_windows`).

### Changed
- **Header rebranded**: "Weave Power" label replaced with "MOD WEAPON CRAFTING" in large white text.
- **Background recolored**: Bottom smoke/ember effects changed from amber/purple to deep red (`bottom_glow_smoke_1/2/3`, `bottom_glow_embers_1`). Top fog layer (`top_glow_smoke_1`) recolored to match.
- **Power displays fixed**: Overview viewports show real weapon power levels. "Level: 999" labels hidden across overview and properties layouts.

### Removed (hidden)
- Forge level display, Athanor essence counter/icon, upgrade button, mastery counter/title/icon, wheel/ring background decorations — all set to `content.visible = false` when custom forge is active.

## 0.10.29-dev (2026-04-30) — Remove on_reload package clearing
### Fixed
- **`on_reload` package clearing caused locked resource crash.** Clearing `loaded_packages = {}` on our mods prevented the engine's `unload_mod` from calling `release_resource_package` on those handles — the resources stayed locked in the resource manager. When the engine then tried to unload a subsequent mod whose package shared or referenced those resources, it hit `ensure_unlocked` and crashed with *"Unloading a locked resource, lock count: 1"*. The `on_reload` hack was originally added to prevent VMF atlas crashes during `/reload`, but that's now handled properly by cosmetics_tweaker's `VMFOptionsView.update` pre-check guard. Removed the package clearing entirely; `on_reload` is now a no-op.

## 0.10.28-dev (2026-04-29) — Match human-readable mod names in OURS lookup
### Fixed
- **Scoped `on_reload` matched zero mods.** v0.10.26 used `m.name = "wt"` etc. as the key into `OURS`, but `mod_manager.lua` sets `mod.name` to the human-readable Workshop title (`"Weapon Tweaker"`, `"Cosmetics Tweaker"`...). The check missed every tweaker mod, so `on_reload` cleared zero packages — defeating the purpose. Symptom: `[WT] on_reload DONE (cleared packages on 0 tweaker mods of 72 total)` followed by *"Unloading a locked resource #ID[ddcb1a7c], lock count: 48"* crash. Fix: switched the `OURS` keys to the actual `m.name` values.

## 0.10.26-dev (2026-04-29) — Scope on_reload package clear to our mods only
### Fixed
- **`on_reload` was nuking third-party atlases.** `wt.mod`'s `on_reload` cleared `loaded_packages` on all 72 installed mods, not just our tweakers. After every `/reload`, VMF's `vmf_atlas`, Loremaster's Armoury's `armoury_atlas` / `la_notification_icon`, and any other mod's atlas got their package handles wiped. The materials stayed in GPU memory until *something* did a name lookup — at which point the engine fataled with `Material 'X' not found in Gui`. Symptoms cascaded across UI surfaces: NewsFeedUI, VMF options view, world markers, inventory exit. Fix: scope the package clear to a known set (`wt`, `ct`, `gt`, `crt`, `t`, `cosmetics_tweaker`) and leave every other mod alone.

## 0.10.11-dev (2026-04-29) — Remove stale forge draw hooks
### Fixed
- **Mod load errors**: Four `mod:hook_safe` calls targeting `HeroWindowWeaveForgeOverview.draw`, `HeroWindowWeaveForgePanel.draw`, `HeroWindowWeaveForgeBackground.draw`, `HeroWindowWeaveProperties.draw` failed at startup — Fatshark removed the `draw` methods on these classes in a prior patch. The hooks were debug instrumentation for the defunct `forge_dump` command. Removed.

## 0.10.21-dev (2026-04-29) — Kerillian spear+shield H2 fix
- Removed erroneous `attack_swing_heavy_down_right` → `attack_swing_heavy_down` from `_3p_remap_deus_to_spear_shield`. The elf's native spear+shield SM uses `attack_swing_heavy_down_right` for its own H2 release — the remap was overriding a natively-working event with one that produces no animation.

## 0.10.20-dev (2026-04-29) — Kerillian greatsword grip tuning
- Z-offset for `es_2h_sword` and `wh_2h_sword` on `we_*` set to `{0, 0, -0.12}` — `-0.25` was overcorrection, `-0.07` was imperceptible.

## 0.10.19-dev (2026-04-29) — Kerillian greatsword grip offset (larger)
- Z-offset for `es_2h_sword` and `wh_2h_sword` on `we_*` increased to `{0, 0, -0.25}` — previous `-0.07` was not noticeable.

## 0.10.17-dev (2026-04-29) — Kerillian greatsword push-attack fix
- Push-attack remap corrected: `attack_swing_down_right` → `attack_swing_heavy` (elf greatsword default heavy release). Previous version used `attack_swing_stab` which didn't match.

## 0.10.16-dev (2026-04-29) — Kerillian greatsword remap refinement
- Changed H1 heavy release remap (`attack_swing_heavy_left_diagonal`) from `attack_swing_heavy` to `attack_swing_left` so Kerillian's H1 release visually matches her L1 swing when wielding Kruber's/Saltzpyre's greatsword.
- Added push-attack remap: `attack_swing_down_right` → `attack_swing_stab`. Push-attack was previously unanimated on Kerillian with the human greatsword.

## 0.9.129-dev (2026-04-28) — Inventory preview now respects scale & grip offset
- Added `MenuWorldPreviewer:equip_item` and `MenuWorldPreviewer:_spawn_item_unit` hooks. The new (post-WoM) inventory preview uses MenuWorldPreviewer instead of HeroPreviewer/GearUtils for character display; the existing in-game scale/offset code never reached those preview units. Now we capture the weapon key from `equip_item` (where it's exposed as the first arg) and apply scale/offset to the unit when it's spawned via `_spawn_item_unit` (where item_data is the weapon TEMPLATE, not the inventory item — so the key isn't directly available there). Per-previewer mapping is weak-keyed so it doesn't pin the previewer in memory.

## 0.9.120-dev (2026-04-28) — Bardin's axe on Kerillian X/Y scale
- Added `dr_1h_axe` scale `{0.85, 0.85, 1}` for `we_*` careers — 15% thinner X/Y, length unchanged.

## 0.9.119-dev (2026-04-28) — Crowbill H1/H3 fix on Bardin
- Added `dr_` override to `one_handed_crowbill`. H1 and H3 used to remap to `attack_swing_heavy` which produces no animation on Bardin's crowbill SM; now they use the elf-sword overhead targets (`attack_swing_charge_left_diagonal` + `attack_swing_heavy_down`). H2 unchanged. Other careers' crowbill behavior preserved via `_default`.

## 0.9.118-dev (2026-04-28) — Bardin grip on Saltzpyre's dual hammers
- Z-offset `{0, 0, 0.15}` for `wh_dual_hammer` on `dr_*`.

## 0.9.116-dev (2026-04-28) — wh_dual_hammer wield-event redirect
- Added `to_dual_hammers_priest` → `to_dual_hammers` redirect for non-Saltzpyre careers. Saltzpyre's dual hammers fire `to_dual_hammers_priest` on wield; this event is missing on Bardin's skeleton, leaving the SM in idle and producing no 3P attack animations. Redirecting to Bardin's native dual-hammers wield event loads his working SM, and since both weapons fire the same chain events, all attacks now animate identically to native.

## 0.9.115-dev (2026-04-28) — Localization: Saltzpyre's dual hammers
- Renamed `Saltzpyre: Dual Hammers` → `Saltzpyre: Dual Skull-Splitters` in all 8 settings entries, matching the Skull-Splitter naming used for the single hammer and hammer+shield variants.

## 0.9.114-dev (2026-04-28) — Heavy chain windup matches release direction
- bw_sword / es_1h_sword on Bardin: H3+ chained heavy charge windup remapped to match the right-swing release direction (was vertical, now right-pose). Visual consistency through long heavy chains.

## 0.9.113-dev — H3+ chain windup added (bw_sword, es_1h_sword)
- Added `attack_swing_charge_left_pose` remap so the third-position heavy in a chain has a visible windup instead of firing native (no animation) on Bardin. Fixes "first heavy loses charge animation" reported in chained heavy sequences.

## 0.9.111-0.9.112-dev — Elf sword H3 fix
- Added `attack_swing_heavy_down_right → attack_swing_heavy_down` and `attack_swing_charge_right_diagonal_pose → attack_swing_charge_left_diagonal` to `we_1h_sword`. The elf sword has 3 distinct heavy event pairs; H3's release is now vertical to match H1.

## 0.9.108-0.9.110-dev — Cross-career H1 fixes (bw_sword, es_1h_sword, wh_1h_falchion)
- Differentiated the two heavy variants in each weapon's chain on Bardin: one variant routed to elf-H1 vertical, the other to elf-H2 right swing. Falchion got a `dr_` override so non-Bardin careers keep their existing `_default` remap unchanged.
- Added grip Z-offset `+0.05` for `bw_sword` and `es_1h_sword` on Bardin (matching the elf sword fix in 0.9.105).

## 0.9.106-0.9.107-dev — Initial bw_sword H1 redirect, scoped to Bardin
- Added `bw_sword` key remap (charge → vertical windup, release → vertical heavy) on cross-career, then scoped to `dr_` only so other careers aren't unintentionally affected.

## 0.9.105-dev — Bardin grip Z-offset
- Z-offset `+0.05` added for `we_1h_sword` (Kerillian's sword) when wielded by Bardin to fix grip riding too high. Coordinate convention discovered: weapon-local Z axis is along the blade.

## 0.9.102-0.9.104-dev — Elf sword heavy chain on Bardin
- `we_1h_sword`: H1 charge `attack_swing_charge_down → attack_swing_charge_left_diagonal`, H2 release `attack_swing_heavy_left_up → attack_swing_heavy_right`, H2 charge `attack_swing_charge_left → attack_swing_charge_right_pose`. L1 charge gains a windup as a side effect (same source event).

## 0.9.96-dev — Saltzpyre flail push-attack fix
- Narrow native-wielder redirect: on `es_1h_flail` + career prefix `wh_*`, `attack_swing_right` → `attack_swing_right_diagonal`. Vanilla `attack_swing_right` produces no visible animation on Saltzpyre's flail SM. The user explicitly authorized this native-wielder modification after `/force3p` confirmed the vanilla event was broken.

## 0.9.93-dev — Crowbill L2 fix on Kruber
- Removed `attack_swing_left → attack_swing_down` from the crowbill `_default` remap. L2 was collapsing into L1's vertical; native `attack_swing_left` plays a right swing on Kruber's crowbill SM (verified via `/force3p`).

## 0.9.92-dev — Flaming flail H1 native overhead
- Removed all template-level remaps for `one_handed_flails_flaming_template`. H1 charge `attack_swing_charge_down` and release `attack_swing_heavy_down` fire natively as the correct overhead on Bardin. Earlier versions remapped them and broke the H1 visual.

## 0.9.88-0.9.91-dev — Cross-career flail (Saltzpyre's flail) and flaming flail H2
- `es_1h_flail` on non-Saltzpyre: H1 release (`attack_swing_left`) and H2 release (`attack_swing_heavy_left`) → `attack_swing_heavy`. Direct `func()` calls in the hook (remap-table corrupts the SM for these events — same pattern as billhook `stab_02`).
- `bw_1h_flail_flaming` on non-Sienna: only H2 release (`attack_swing_heavy_left`) needs the same redirect; H1 fires natively as the correct overhead.

## 0.9.89-dev — Husk-safety for the flail redirect
- Added `_unit_career_name` helper using `Managers.player:owner(unit)`. The flail direct-redirect now gates on `is_local` AND uses the unit-owner career, so it only modifies the local player's flail when the local player is non-Saltzpyre. Husks of other players using non-flail weapons no longer have their `attack_swing_left` events hijacked.

## 0.3.0-dev (2026-04-24)

### Added: Cross-character 1H weapon unlocks for all 20 careers

Added 8 base 1H weapons that share compatible animations across all characters:
- `es_1h_sword` (Kruber's Sword) — all non-Kruber careers
- `es_1h_mace` (Kruber's Mace) — all non-Kruber careers
- `bw_sword` (Sienna's Sword) — all non-Sienna careers
- `wh_1h_falchion` (Saltzpyre's Falchion) — all non-Saltzpyre careers
- `dr_1h_axe` (Bardin's Axe) — all non-Bardin careers
- `wh_1h_axe` (Saltzpyre's Axe) — all non-Saltzpyre careers
- `we_1h_sword` (Kerillian's Sword) — all non-Kerillian careers
- `dr_1h_hammer` (Bardin's Hammer) — all non-Bardin careers

### Added: Shield weapons, spears, and career-specific unlocks

- `dr_shield_hammer` (Bardin's Hammer & Shield) — all Kruber careers
- `es_mace_shield` (Kruber's Mace & Shield) — all Bardin careers
- `es_2h_heavy_spear` (Kruber's Spear) — Foot Knight, Grail Knight
- `we_1h_spears_shield` (Kerillian's Spear & Shield) — Waystalker, Shade, Sister of the Thorn, Grail Knight
- `es_halberd` (Halberd) — Grail Knight
- `we_crossbow_repeater` (Volley Crossbow) — Waystalker, Handmaiden, Sister of the Thorn

### Changed: Settings menu restructured

VMF settings menu reorganized into Melee > Character > Career and Ranged > Character > Career hierarchy. Each weapon is an individual checkbox (all off by default).

## 0.2.1-dev (2026-04-24)

### Added: Bretonnian Sword & Shield for Mercenary

Added `es_sword_shield_breton` unlock for `es_mercenary`.

## 0.2.0-dev (2026-04-24)

### Fixed: `BackendUtils.can_wield_item` hook error on every load/toggle

**Symptom:** VMF logs `[MOD][wt][ERROR] (hook): trying to hook function or method that doesn't exist: [BackendUtils.can_wield_item]` each time the mod loads or is toggled.

**Root cause:** `BackendUtils.can_wield_item` does not exist as a hookable method at any point during the weapon_tweaker's lifecycle. The old monolithic tweaker happened to load at a time when it was available, but as a separate Workshop mod the timing is different.

**Investigation:** Tried multiple approaches — string-form hooks (`mod:hook("BackendUtils", ...)`), deferred hooks in `mod.update` with `rawget` and metatable checks — none worked because the method genuinely isn't hookable for this mod.

**Fix:** Removed the `BackendUtils.can_wield_item` hook entirely. Per the AnyWeapon mod (reference implementation), this hook is unnecessary — weapon eligibility is controlled by modifying `ItemMasterList[weapon_key].can_wield` directly (which `apply_weapon_unlocks` already does). The `ItemGridUI._on_category_index_change` hook handles inventory UI filtering.

**Rule of thumb:** Don't hook `BackendUtils.can_wield_item`. Modify `can_wield` lists on `ItemMasterList` entries directly.

### Fixed: Missing localization keys for mod settings

Added localization entries for `kruber_weapons`, `es_mercenary_weapons`, `unlock_es_mercenary_dr_1h_axe`, `debug_group`, and `enable_weapon_debug_logging`. Naming convention follows old tweaker style (e.g. "Axe (Bardin)" not "Unlock Dwarf 1H Axe").

### Added: Version logging

Mod now logs `Weapon Tweaker v<version> loaded` on init so the running version can be verified in the console log.

### Fixed: Deploy workflow

`deploy_all.ps1` now deploys directly to Workshop content folders (e.g. `552500/3712896117`) for hot reload during development, in addition to `upload/content` for Workshop uploads. The fake local install (ID `9000000002`) approach was removed — the game loads from the real Workshop folder.
