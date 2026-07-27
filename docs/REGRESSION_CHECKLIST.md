# Regression Checklist — vermintide-2-tweaker

This list catalogues every documented past error in the monorepo. Before any release that touches a relevant subsystem, walk the entries marked for that subsystem and verify each fix is still in place.

The companion `regression-lint.ps1` (in `tools/lint/`) catches STATIC-category items at build time. The `/regression_test` chat command (added to most mods) catches UNIT/INTEGRATION items at runtime. This file covers MANUAL-category items that require human QA, plus the full historical record.

`tools/github/audit-open-issues.ps1` is the issue-history companion to this
checklist. It compares every live open issue with every closed issue using
auditable signals: direct issue references, exact subsystem labels, the
lifecycle/surface classes distilled from this checklist, exact code identifiers,
and corpus-rare normalized terms. Each candidate records the points contributed
by every signal and the closed issue's actual verification/closure evidence.
The output is a manual review queue only: fuzzy similarity never proves a common
root cause and never authorizes automatic reopening.

Last updated: 2026-05-22. Source: CHANGELOG.md files + ~/.claude memory.

---

## Retired features

### Big Rebalance consumers remain hidden and unloaded — issue #321

**[STATIC + SOLO UI]**

- Run `qa/check_retired_big_rebalance.ps1`; it must pass for WT/WT-dev, CT/CT-dev, ET, and CRT.
- Open each consumer in Mod Tweaker. No Big Rebalance, `br_*`, or `cbr_*` group may render.
- Existing saved legacy values are ignored, not erased. No BR mechanics apply after restart.
- Workshop descriptions must not advertise the retired integration.
- Reactivation requires a new reviewed owner/parity/source design; removing the old `bt` gate alone is forbidden.

## Multiplayer / Network Sync

### Pusfume remains independent of Tweaker mods

**[STATIC + SOLO + MULTIPLAYER]**

- Run `qa/check_pusfume_compatibility.ps1`; unreviewed direct `pusfume`
  references in active Lua must be absent.
- With Pusfume absent, exercise the changed career/profile/loadout/package path
  and confirm existing Tweaker behavior is unchanged.
- With Pusfume and the changed Tweaker set enabled, select Pusfume, enter the
  Adventure Keep, equip its loadout, enter and leave an Adventure mission, and
  confirm no script, package, career-index, or missing-resource error occurs.
- Repeat host/client with the same Pusfume build on both peers when the change
  touches synchronized state. Confirm both peers resolve the same career and
  loadout through mission transitions.
- Disable or remove the changed Tweaker mod and confirm Pusfume still works. A
  Tweaker mod must never become a Pusfume dependency.
- If coexistence fails, fail only the conflicting optional Tweaker feature back
  to vanilla behavior. Do not mutate or disable Pusfume to make Tweaker pass.

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

### vmf-rpc-string-cap — VMF mod:network_send silently drops payloads over 500 chars

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Host log shows `Failed to pack parameter 3, too many characters in string with max length 500`; clients receive nothing. |
| Root cause | Stingray's RPC packer hard-caps string parameters at 500 chars (`network_utils.lua:93 STRING_MAX=500`); VMF JSON-packs all args into one string. Error fires inside a safe-hook wrapper so the broadcast silently no-ops. |
| Mod(s) | chaos_wastes_tweaker (and any mod doing host→client settings sync) |
| Fix version(s) | ct v0.7.59-alpha (chunked send) |
| Category | INTEGRATION |
| Repro | 1. Host enables a large-table settings sync (e.g. ct host-settings broadcast). 2. Joiner joins. 3. Trigger the sync (host changes a setting). |
| Expected post-fix | Clients receive the sync chunked into ≤400-char payloads with session/seq/total framing; final settings table assembled on receiver matches host. |
| Detection | Host console log should NOT contain `Failed to pack parameter`. Client `/dump_synced_settings` (or equivalent) should match host's settings table. |

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

### ct-graph-snapshot-rpc — Different peers generate different CW maps when load-time toggle mutates LevelSettings

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Host and client see different per-node levels / curses / themes on the CW map despite using same seed. |
| Root cause | `inject_adventure_maps` mutates `LEVEL_AVAILABILITY.TRAVEL/SIGNATURE/ARENA` at module-load. Vanilla `deus_populate_graph` indexes into those arrays. Same seed × different arrays = different per-node picks. Toggle can't be runtime-resynced because `#NetworkLookup.level_keys` folds into lobby `combined_hash`. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.64 |
| Category | INTEGRATION |
| Repro | 1. Host enables `inject_adventure_maps`. 2. Client installs ct without that toggle. 3. Host starts a CW run. 4. Compare each peer's map view. |
| Expected post-fix | Client's map snapshot is overwritten by host's broadcast; node levels/themes/curses agree. Late-arrival re-apply happens at `DeusMapScene.on_enter`. |
| Detection | Each player runs `/ct_dump_graph` (or visually inspects the map nodes). Maps must match. |

### vt2-lobby-combined-hash — Mods that grow LevelSettings break lobby join

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Joiner gets `Join failed - Game version mismatch` popup; chat shows `[ChatManager][1]System` mismatch. |
| Root cause | Lobby `combined_hash` includes `num_levels` (count of LevelSettings entries). Mods that register new levels post-boot raise `num_levels` per-peer; if one side has the feature on and the other off, hashes differ. LevelSettings entries cannot be cleanly un-registered — game restart required to revert. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | Documented; mitigation = restart game after toggling. |
| Category | MANUAL |
| Repro | 1. Player A enables ct `inject_adventure_maps`. 2. Player B has ct disabled or feature off. 3. Either tries to join the other's lobby. |
| Expected post-fix | If host warning surfaces in UI, friends can avoid the mismatch by restarting after toggling. Console `Making combined_hash:` lines should print same num_levels on both peers. |
| Detection | `console-*.log` grep for `Making combined_hash:`; compare `num_levels=` between host and client. |

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

### ct-husk-hook-shadow-tpe — Two hook_safe on same Class.method silently drop the second

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | VMF boot log warns `Attempting to rehook active hook [wield]` then silently keeps only the first registration; the second hook body never runs. |
| Root cause | `_tpe.lua` registers a `hook_safe(SimpleHuskInventoryExtension, "wield", ...)`. Any later `hook_safe` on the same Class+method is dropped by VMF. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.9.0.10 |
| Category | INTEGRATION |
| Repro | 1. Add a second hook_safe on SimpleHuskInventoryExtension.wield in cosmetics_tweaker.lua. 2. Restart. 3. Watch boot log for the warning. |
| Expected post-fix | Either consolidate to one hook, or move to `_wield_slot` wrap which chains correctly. Boot log shows no rehook warning. |
| Detection | Grep boot log for `Attempting to rehook active hook`. Should be absent. |

### vt2-husk-rpc-race — Vanilla rpc_create_attachment races CT cos_la_apply, destroys LA unit

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | LA-textured hat appears briefly on remote players' view of host, then reverts to vanilla after a beat. Re-equip on host required to fix. |
| Root cause | Both `cos_la_apply` (CT broadcast) and vanilla `rpc_create_attachment` arrive on the same channel. Vanilla's late RPC sees CT's LA unit as `old_slot_data`, destroys it, spawns vanilla mesh. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.9.0.9 |
| Category | INTEGRATION |
| Repro | 1. Friend joins your lobby (you = host). 2. You equip an LA `kind="texture"` hat for the first time this session. 3. Friend watches your character. |
| Expected post-fix | Friend immediately sees the LA-textured hat; texture remains after vanilla RPC arrives (vanilla now patches `item_data.unit` to LA path before spawn). |
| Detection | Visual: friend sees the LA-colored hat without you needing to re-equip. |

### ct-offhand-force-preload — Cross-character shield/illusion package not loaded on clients → crash

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Client crash `unit_spawner.lua:354: spawn_unit` with `unit_name = "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03_3p"` (or other cross-character shield path) the moment host wields a cosmetics_tweaker offhand option. |
| Root cause | Vanilla only preloads packages off `right_hand_unit`/`left_hand_unit` of items in each peer's inventory. CT injects shield meshes from other characters' kits → client never loaded that package → synchronous `rpc_wield_equipment` races the async ProfileSynchronizer load → crash. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.9.0.4 |
| Category | INTEGRATION |
| Repro | 1. Host: any Kruber/Bret career, equip a GK-shield offhand variant via cosmetics_tweaker (e.g. `wpn_emp_gk_shield_03`). 2. Client joins keep. 3. Host wields the shield. |
| Expected post-fix | All offhand-option / custom-illusion / LA-shield unit packages force-loaded at mod init on EVERY peer (idempotent, ~50 packages). No crash on first wield. |
| Detection | Client console: no `Resource '#ID[...]' not found` / `spawn_unit` crash on wield. Add `/cos dump_force_loaded` to check the loaded set. |

### vt2-mutator-template-server-wrap — Dead-field hook silently no-ops

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Mutator-template hook compiles and registers without error but never affects gameplay. |
| Root cause | `mutator_templates.lua:236-269` wraps each `server_start_function`/`server_stop_function`/etc. into `template.server.start_function`/`template.server.stop_function` closures at boot. The flat `server_start_function` field is dead after wrap; hooking it silently no-ops. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.66 (pre-deploy QA catch) |
| Category | STATIC |
| Repro | (No live repro — caught by code audit before deploy.) |
| Expected post-fix | Mutator lifecycle hooks target `template.server.start_function` (etc.), not `template.server_start_function`. |
| Detection | Grep mod sources for `mod:hook.*server_start_function`. Should be absent (use `template.server.start_function` instead). |

### vt2-networked-flow-state-leak — Vanilla bug fatals at 512 networked flow states

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Engine fatal `[NetworkedFlowStateManager] Too many object states(512).` after a long session, most often CW with multiple cursed chests. |
| Root cause | Vanilla `NetworkedFlowStateManager.clear_object_state` nils `_object_states[unit]` but never decrements `_num_states`. Counter is monotonic. Worst offender: CW cursed_chest_objective_unit buff applied to every cursed-chest enemy. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.3-alpha |
| Category | INTEGRATION |
| Repro | 1. Enable ct + `inject_adventure_maps`, `cursed_chest_count > 1`. 2. Play a long CW run (~30-60 min) with many cursed-chest enemy spawns. 3. Watch for crash near `_num_states` cap. |
| Expected post-fix | ct's hook on `clear_object_state` decrements `_num_states` by the count of states being released. Run completes without the 512 fatal. |
| Detection | `/regression_test` in ct checks the patch is wired. In long sessions, dump `_num_states` via `/ct_flow_states` (if available). |

### cross-mod-br-registration-sync — Subset divergence across BR-aware mods

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Player A (wt+ct+et installed) gets different NetworkLookup buff indices than Player B (only ct installed). Host's rpc_add_buff resolves to wrong buff on client. |
| Root cause | wt/ct/et each pre-register Big Rebalance templates at mod load. If their lists differ (subset vs full union), peer indices drift. |
| Mod(s) | weapon_tweaker, chaos_wastes_tweaker, enemy_tweaker, buff_tweaker |
| Fix version(s) | buff_tweaker v0.0.1+ (consolidated registration via single bt master); also see byte-identical canonical lists shipped 2026-05-21. |
| Category | STATIC |
| Repro | (Lint-checkable via diff of `*_big_rebalance_registrations.lua`.) |
| Expected post-fix | Each BR-aware mod ships byte-identical sorted canonical list, OR all peers consume bt for BR registration. |
| Detection | Diff `wt/scripts/.../weapon_tweaker_big_rebalance_registrations.lua` against ct/et equivalents — only filename comment and `local mod = get_mod(...)` should differ. |

### vt2-dormant-buff-template-dual-register — Runtime-injected boons crash on apply

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Crash `buff_extension.lua:177 attempt to index local 'buff_template' (a nil value)` the first time an injected boon is rolled and applied. |
| Root cause | Vanilla merges `DeusPowerUpBuffTemplates` → `_G.BuffTemplates` once at boot (via DLCUtils). Mods load AFTER that merge. Writing only to `DeusPowerUpBuffTemplates` at runtime leaves `BuffTemplates` un-aware; `BuffUtils.get_buff_template(name)` returns nil. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.32 |
| Category | INTEGRATION |
| Repro | 1. Toggle an `activate_dormant_*` boon in ct settings. 2. Start CW run. 3. Trigger a shrine/altar that can roll the newly-activated boon. 4. Apply it. |
| Expected post-fix | Mod writes to BOTH `DeusPowerUpBuffTemplates[name]` AND `_G.BuffTemplates[name]`. Boon applies without crash. |
| Detection | `/regression_test` in ct includes a dual-table buff-write check. |

### vt2-deus-power-up-rarities — Common-rarity boons crash CW shrine roll

| Field | Value |
|-------|-------|
| Symptom | Crash `deus_power_up_utils.lua:208 (live :189) attempt to index a nil value` during `generate_random_power_up`. Locals show offending `power_up.rarity = "common"`. |
| Root cause | `DeusPowerUpRarities = {"event","rare","exotic","unique"}` only. `common`/`plentiful` are weapon-drop rarities; injecting a boon at common rarity fails the LUT build at file load. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.37 (remapped squats, deus_larger_clip to rare) |
| Category | STATIC |
| Repro | 1. Inject any custom boon at `rarity = "common"` or `"plentiful"`. 2. Start CW run. 3. Roll the boon at a chest/shrine. |
| Expected post-fix | All mod-injected boons use only `event`/`rare`/`exotic`/`unique`. No crash on roll. |
| Detection | Lint: grep mod source for `rarity = "common"` / `rarity = "plentiful"` inside ct boon injection blocks. |

### vt2-adventure-pack-spawning-compat — `no_roamers` mutator crashes on adventure-injected levels

| Field | Value |
|-------|-------|
| Symptom | Crash `mutator_no_roamers.lua:6 bad argument #1 to 'pairs' (table expected, got nil)` on first SIGNATURE-zone load of a CW run that landed on an adventure-injected level. |
| Root cause | CW pacing mutator `no_roamers` does `pairs(pack_spawning_settings.difficulty_overrides)`. Vanilla `chaos_light` PackSpawningSettings entry lacks that field — fine on its native campaign use, but on CW adventure-injected nodes it surfaces. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.41 |
| Category | INTEGRATION |
| Repro | 1. Enable `inject_adventure_maps`. 2. Start a CW run, navigate to a SIGNATURE node (the modifier zone). 3. Land on an adventure-injected level (any campaign mission added to the pool). |
| Expected post-fix | Mod hooks `MutatorHandler.tweak_pack_spawning_settings` and strips `no_roamers` from zone-mutator lists when the level is adventure-injected. Vanilla CW levels stay untouched. |
| Detection | `/regression_test` in ct verifies the strip hook is wired. |

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

### cwv-dual-wield-display-rig — Dual-wield variant missing display_dual_weapons crashes picker

| Field | Value |
|-------|-------|
| Symptom | Cosmetic illusion picker crashes on open with `[Script Error]: j_leftweaponattach` (or other dual-attach node name). |
| Root cause | Picker attaches each hand's weapon unit to a display-unit pivot. Vanilla single-rigs (`display_1h_swords`, `display_1h_weapon`) only author right-hand attach. Dual variants need `display_dual_weapons` (or matching `display_dual_axes`/etc.) with both `j_rightweaponattach` and `j_leftweaponattach`. AND `left_hand_unit` must be populated. AND set on BOTH the skin AND the ItemMasterList layers. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.145 (the false-negative trap) |
| Category | INTEGRATION |
| Repro | 1. Add a new CWV dual-wield variant without `display_unit = "units/weapons/weapon_display/display_dual_weapons"`. 2. Open cosmetic picker. 3. Watch crash. |
| Expected post-fix | Both layers carry `display_unit = "display_dual_weapons"` (or matching family rig) AND `left_hand_unit` populated. Picker opens cleanly. |
| Detection | Audit each dual-wield variant: search `_register_variant_skins` AND `_register_*_dual_illusions` for the rig path; both must match. |

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

## Cosmetics / LA / CWV

### la-hat-kind-texture-needs-paint — Texture-paint LA hats show vanilla colors on remote husks

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Friend equips an LA hat with `kind="texture"` (recolored vanilla mesh, e.g. white Pureheart). On your screen of their character: correct hat MESH but wrong COLOR (vanilla diffuse). |
| Root cause | `kind="texture"` requires `apply_new_skin_from_texture` after `create_attachment`. LA's local-equip queue handles this for self; cosmetics_tweaker's broadcast receiver did not for husks. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.9.0.2 |
| Category | INTEGRATION |
| Repro | 1. Friend equips `Kruber_Pureheart_helm_white` or other `kind="texture"` LA hat. 2. You watch their character on your screen. |
| Expected post-fix | Hat appears in correct LA texture color on your screen. |
| Detection | Visual confirm. Or `/cos dump_la_state` shows the paint was applied to the husk hat unit. |

### la-kind-unit-pipeline — Custom-mesh LA shield AV crash in customization preview

| Field | Value |
|-------|-------|
| Symptom | Access violation at offset 0x8 in `Unit.set_texture_for_materials` when customization-preview spawns a `kind="unit"` LA shield (e.g. Reiland). |
| Root cause | LA's `kind="unit"` shields use vanilla material via `mat_to_use` directive. In customization preview's narrow per-world resource graph, the material resolves to `#ID[00000000]` (null) at spawn time. Painting on the null material AVs. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.8.47-0.8.49 |
| Category | INTEGRATION |
| Repro | 1. Open customization preview (row-2 shield picker) for a Kruber sword+shield variant. 2. Pick Reiland (or any `kind="unit"` shield). 3. Watch crash. |
| Expected post-fix | For `loot_previewer` context only, `Unit.set_all_materials(unit, parent_path)` binds vanilla material BEFORE `set_texture_for_materials`. For `ingame`/`hero_previewer` contexts, early-return (vanilla rendering already handles them). |
| Detection | Crash log check. After fix, opening the picker on Reiland shows correct mesh + texture, no AV. |

### la-offhand-paint-pipeline — Magenta or wrong-shield LA paint leaks via shared material

| Field | Value |
|-------|-------|
| Symptom | After equipping an LA offhand variant, other shields globally show magenta or wrong textures; LA paint sticks across shield changes. |
| Root cause | `Material.set_texture` mutates the SHARED baked material; every unit referencing it inherits the override. LA paint must use `Unit.set_texture_for_materials` (per-unit override) instead. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.8.18 |
| Category | INTEGRATION |
| Repro | 1. Equip an LA offhand `kind="texture"` shield. 2. Switch to a different vanilla shield. 3. Observe colors leak between shields. |
| Expected post-fix | `_paint_offhand_textures_locally` uses `Unit.set_texture_for_materials(unit, slot_name, path)` — per-unit override, no shared-material mutation. |
| Detection | Visual: cycle through several shields; each should render with its own texture. |

### la-icon-key-vs-item-type — LA icon prefix mismatch with game item_type → empty picker pool

| Field | Value |
|-------|-------|
| Symptom | LA shield pool builds but never surfaces in the picker. Log shows `[LA bridge] <prefix> offhand pool: N entries` AND `[LA paint] skip: no _offhand_selection for <other_prefix>`. |
| Root cause | LA's `icons` table key prefix (`es_sword_shield_breton_skin_*`) doesn't match game's `ItemMasterList[item].item_type` (`es_1h_sword_shield_breton`). |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.8.22 |
| Category | STATIC |
| Repro | 1. Add a new LA weapon family without translating to game item_type. 2. Open picker. 3. Confirm pool is empty. |
| Expected post-fix | `_LA_WEAPON_TYPE_ALIAS` map normalizes both fanout and `_LA_EXTRA_WEAPON_TYPES` lookups. |
| Detection | `/cos la_offhand_dump` should show `weapons=[...]` matching the same item_type strings printed in `[LA bridge]` log lines. |

### la-custom-mesh-unsupported — `kind="unit"` LA shields can't be safely cross-paired with rawget/rawset

| Field | Value |
|-------|-------|
| Symptom | User selects an LA custom-mesh shield, then another → crash `Table inventory_packages does not contain key: ..._3p`. |
| Root cause | Calling LA's `swap_units_new` from outside its `mod.update` loop races LA's own tick; LA reads `NetworkLookup.inventory_packages` without rawget; strict `__index` errors. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.8.11-0.8.13 (intentionally filtered out, see _la_bridge `_is_supported_variant`) |
| Category | STATIC |
| Repro | (Cosmetics_tweaker's bridge intentionally filters these out — see "Don't relax this without solving 1+2.") |
| Expected post-fix | `_la_bridge._is_supported_variant` returns false for `kind="unit"` AND `kind="texture" + new_units && !is_vanilla_unit`. |
| Detection | Audit `_la_bridge.lua` `_is_supported_variant` for the filter. |

### cwv-clone-name-clobber — Variant defs must NOT override entry.name / entry.key

| Field | Value |
|-------|-------|
| Symptom | Crash `backend_utils.lua: attempt to index local 'item_data' (a nil value)` on equip of cwv item. |
| Root cause | Downstream `ItemMasterList[item.name]` lookups fall back to the base entry. Clobbering `entry.name = def.item_key` breaks the fallback chain. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV pattern in `_build_entry`; supported by `cwv_variant = true` marker flag. |
| Category | STATIC |
| Repro | (Static rule — would crash any equip.) |
| Expected post-fix | `_build_entry` keeps inherited `entry.name` and adds `entry.cwv_variant = true`. Sibling mods gate `item_name`-keyed overrides on the flag. |
| Detection | `/regression_test` in CWV checks every cwv IML entry has `cwv_variant = true` and does NOT clobber `entry.name`. |

### cwv-imperial-longsword-family — Tune the type, not the model

| Field | Value |
|-------|-------|
| Symptom | User reports scale/grip changes work on one variant but break across the family. |
| Root cause | CWV creates new TYPES of weapons. Tunes should go in `_type_transforms[item_type]`, NOT per-variant. Per-variant overrides only when a model genuinely needs a different axis convention. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | doc rule |
| Category | STATIC |
| Repro | (Architectural — any new tune that gets duplicated across variants is wrong.) |
| Expected post-fix | Every type-level tune lives in `_type_transforms[type]`. |
| Detection | Code audit: each new transform field should appear once per type, not once per variant. |

### cwv-ammo-unit-required — Variants cloned from ammo weapons must mirror skin fields

| Field | Value |
|-------|-------|
| Symptom | (a) Previewer crash `world_hero_previewer.lua attempt to concatenate local 'left_hand_unit' (a nil value)`. (b) Throw crashes. (c) Pickup crashes. |
| Root cause | `BackendUtils.get_item_units` unconditionally overwrites `left_hand_unit/right_hand_unit/ammo_unit/ammo_unit_3p/projectile_units_template/pickup_template_name/link_pickup_template_name` from the skin's fields. Anything absent on the skin becomes nil; downstream paths nil-cascade. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.64 (mirror), v0.1.184 (gate `def.left_hand_unit` fallback on `base.ammo_unit`) |
| Category | INTEGRATION |
| Repro | 1. Create a new CWV variant whose base is `we_javelin` (or other `is_ammo_weapon = true`). 2. Don't mirror the skin fields. 3. Try to equip + throw + pickup. |
| Expected post-fix | `_register_variant_skins` mirrors ammo_unit/ammo_unit_3p/projectile_units_template/pickup_template_name/link_pickup_template_name with `def.<field> or base.<field>` fallback. For non-ammo bases (brace), gate the `def.left_hand_unit` fallback on `base.ammo_unit` existing. |
| Detection | `/regression_test` in CWV checks ammo-bearing bases have their skin fields mirrored. |

### cwv-frankenstein-template — Cross-template variants need base-template patching

| Field | Value |
|-------|-------|
| Symptom | Previewer crashes when a CWV variant uses one template's visual layer + another's behavior, especially with hand-mount flip. Crash GUID example: c847908d. |
| Root cause | Previewer reads `ItemMasterList[base_name].template` (the BASE template) for hand-attachment-linking lookups. Variant uses opposite hand → base template's hand field is nil → crash. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.181 |
| Category | INTEGRATION |
| Repro | 1. Create a CWV variant cloned from a left-hand weapon, flipped to right-hand mount. 2. Open inventory preview. 3. Watch crash. |
| Expected post-fix | At end of `_create_<variant>_template`, also patch base template's missing-hand linking: `Weapons.<base>.right_hand_attachment_node_linking = AttachmentNodeLinking.<linking>`. |
| Detection | Open inventory preview on every cross-template Frankenstein variant. No crash. |

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

### cwv-previewer-template-lookup — Previewer reads BASE template, not the cwv clone

| Field | Value |
|-------|-------|
| Symptom | Wield animation, idle stance, or state-machine override applied to cwv template appears in-game but NOT in inventory preview. |
| Root cause | `world_hero_previewer.lua` resolves via `ItemHelper.get_template_by_item_name(item_name)`; `item_name = base_weapon_key` for cwv items. Modifications to the cwv-cloned `Weapons.<key>` are invisible to the preview. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.48 |
| Category | STATIC |
| Repro | 1. Add `wield_anim_career_3p` to the cwv-cloned template only. 2. Open inventory preview. 3. Notice wrong wield. |
| Expected post-fix | Mirror the change to the BASE template under a career-keyed table that excludes native-using careers. |
| Detection | Open inventory preview for every cwv variant whose template differs from base. Visual matches in-game. |

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

### cwv-projectile-template-lookup — Projectile system reads BASE template, swap via init hook

| Field | Value |
|-------|-------|
| Symptom | Cloned thrown weapon's stats/impact_data/projectile_speed take no effect; only wield-time fields (max_ammo, state_machine) work. |
| Root cause | `PlayerProjectileUnitExtension.init` reads `ItemMasterList[item_name].template` at projectile creation; `item_name` is the BASE key for cwv items. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.100 |
| Category | INTEGRATION |
| Repro | 1. Clone javelin_template under a new name with modified `impact_data` (e.g. `link_pickup = true`). 2. Throw. 3. Observe vanilla behavior persists. |
| Expected post-fix | Hook `PlayerProjectileUnitExtension.init` post-vanilla. Detect cwv ownership via `slot_data.skin`. Swap `_current_action`/`_impact_data`/`projectile_info`/`_impact_damage_profile_id` to clone. |
| Detection | Add `[cwv stick] init post-fix swap` log on every throw. Should fire. |

### cwv-blacksmith-template — Default-rarity variants have 7 non-obvious rules

| Field | Value |
|-------|-------|
| Symptom | (Various.) Forge shows variant as locked / re-roll disabled / illusion picker crashes / variant mesh wrong in preview. |
| Root cause | Multiple rules: (1) inherit name, (2) no skin pre-apply, (3) entry's right_hand_unit = variant's default model, (4) BackendUtils.get_item_units hook needed, (5) matching_item_key = def.base_weapon (not def.item_key), (6) skin registers in 3 tables, (7) skip rarity upgrade. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.91, v0.1.95 |
| Category | INTEGRATION |
| Repro | (Per-rule manual verification.) |
| Expected post-fix | Forge UI: white border, re-roll enabled, illusion list = full type's skin_combinations. Variant mesh persists on equip. |
| Detection | Walk the verification checklist in `reference_cwv_blacksmith_template.md` for every default-rarity variant. |

### cwv-custom-mesh-material — Three sharp edges shipping a custom FBX

| Field | Value |
|-------|-------|
| Symptom | (a) Material name truncated → crash. (b) SDK compile error `material could not be found`. (c) Engine error `Resource '#ID[hash]' not found`. |
| Root cause | FBX exporter truncates material slot names ~60 chars. Vanilla material paths unavailable at SDK compile time. `Application.resource_package` is global only; mod-shipped paths must use vanilla resource paths via overlay pattern. Also: `<unit>.package` and `<unit>_3p.package` sibling files required. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.272 (and follow-ups) |
| Category | INTEGRATION |
| Repro | 1. Author a new mod with a custom FBX. 2. Skip any of the three rules. 3. Watch SDK compile fail / equip crash. |
| Expected post-fix | Short FBX material name + long path in `.unit` materials block. Author own `.material` referencing mod-relative path. `_3p.fbx`/`_3p.unit` siblings shipped. `_3p.package` sibling shipped + listed in master `.package`. |
| Detection | Build mod with `vmblauncher build`. Equip + walk in-game. Mesh has correct PBR textures (not pink, not flat-gray, not invisible). |

### vt2-no-custom-package-paths — Custom-mesh weapons must piggyback vanilla paths

| Field | Value |
|-------|-------|
| Symptom | Engine error `Resource '#ID[<hash>]' not found!` where `<hash>` is the murmur64 of a mod-defined unit path. |
| Root cause | `Application.resource_package(path)` is global registry; `Mod.resource_package` is mod-scoped. Vanilla code (previewer / GearUtils) uses the global. Mod-defined paths never resolve there. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.276 (after burning 4 versions on this) |
| Category | STATIC |
| Repro | 1. Set `right_hand_unit = "units/cwv_*/cwv_*"` (custom path). 2. Open inventory preview. 3. Watch crash. |
| Expected post-fix | `right_hand_unit` always points at a vanilla unit path; custom mesh is overlaid via the LA pattern (`mat_to_use` + PackageManager hooks + master `.package` unit glob). |
| Detection | Audit each CWV variant's `right_hand_unit`; should always be a vanilla `units/weapons/...` path. |

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

### vt2-unit-node-not-pcall-safe — Unit.node engine fatal bypasses pcall

| Field | Value |
|-------|-------|
| Symptom | `pcall(Unit.node, unit, name)` does NOT catch the missing-node fatal. Game halts with `[Script Error]: <node name>`. |
| Root cause | Stingray C-side APIs can bypass Lua protected-mode entirely. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.291 |
| Category | STATIC |
| Repro | 1. Call `pcall(Unit.node, unit, "j_doesnt_exist")`. 2. Expect graceful fail. 3. Game crashes. |
| Expected post-fix | Always use `Unit.has_node(unit, name)` for existence check first. |
| Detection | Lint: grep mod source for `pcall(Unit.node`. Should be absent. |

### vt2-quaternion-vector3-box-for-storage — Raw Quaternion/Vector3 are single-frame temporaries

| Field | Value |
|-------|-------|
| Symptom | Stored rotation/position works on first frame, then drifts to garbage (often appears as identity or weirdly perpendicular). |
| Root cause | Stingray Quaternion/Vector3 are stack-allocated; storing raw value in Lua global/table/upvalue makes it stale after the current frame. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.298 |
| Category | STATIC |
| Repro | 1. `_my_rot = Quaternion.axis_angle(Vector3(1,1,-1), -math.pi/2)`. 2. Next frame, `Unit.set_local_rotation(unit, 0, _my_rot)`. 3. Observe perpendicular/garbage orientation. |
| Expected post-fix | `_my_rot_box = QuaternionBox(Quaternion.axis_angle(...))`; at use site `Unit.set_local_rotation(unit, 0, _my_rot_box:unbox())`. Same for Vector3 → Vector3Box. |
| Detection | Lint: grep mod sources for global/table-level `Quaternion.` or `Vector3.` assignments without `*Box(...)` wrapper. |

### vt2-lua-200-locals — Lua 5.1 main-chunk 200-local limit hit on large files

| Field | Value |
|-------|-------|
| Symptom | Stingray compile error `main function has more than 200 local variables`. |
| Root cause | Lua 5.1/LuaJIT 200-local-per-function cap, including top-level chunk. Large mod files accumulate past this. |
| Mod(s) | character_weapon_variants, chaos_wastes_tweaker |
| Fix version(s) | CWV v0.1.304 |
| Category | STATIC |
| Repro | 1. Add many top-level `local function`/`local var =` declarations until file has 200+. 2. Build. |
| Expected post-fix | Wrap helper-function groups in `do ... end` scopes so their locals release back to the main chunk. |
| Detection | Build the mod with `vmblauncher build`. If "main function has more than 200 local variables" appears, wrap groups in do/end. |

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

### loot-previewer-hook-not-safe — `self._spawned_units` assigned after spawn_units returns

| Field | Value |
|-------|-------|
| Symptom | LootItemUnitPreviewer hook fires but `self._spawned_units` is nil → all gated logic silently no-ops. |
| Root cause | Vanilla `_spawn_items` assigns `self._spawned_units = units` AFTER `spawn_units` returns. `mod:hook_safe` post-callback fires before that assignment. |
| Mod(s) | cosmetics_tweaker, character_weapon_variants |
| Fix version(s) | cosmetics_tweaker (early), CWV v0.1.127 |
| Category | STATIC |
| Repro | 1. Use `mod:hook_safe("LootItemUnitPreviewer", "spawn_units", ...)`. 2. Read `self._spawned_units` in callback. 3. Observe nil. |
| Expected post-fix | Use `mod:hook` (full wrapper); read `units` from the wrapped call's return. |
| Detection | Lint: grep mod sources for `mod:hook_safe.*LootItemUnitPreviewer.*spawn_units`. Should be absent. |

### preview-slot-keying — _item_info_by_slot vs _equipment_units key types

| Field | Value |
|-------|-------|
| Symptom | `MenuWorldPreviewer._spawn_item` hook fires, logs say transform applied, but no scale/offset reaches the unit. |
| Root cause | `_item_info_by_slot[<string slot_type>]` ("melee"/"ranged") vs `_equipment_units[<numeric slot_index>]`. Using string as key on numeric table returns nil silently. |
| Mod(s) | cosmetics_tweaker, character_weapon_variants |
| Fix version(s) | cosmetics_tweaker v0.7.88, CWV v0.1.84 |
| Category | STATIC |
| Repro | 1. In a `_spawn_item` post-hook, iterate `_item_info_by_slot` and use the iterator key on `_equipment_units`. 2. Notice transform never applies. |
| Expected post-fix | Bridge via `info.spawn_data[1].slot_index`. |
| Detection | Visual: scale/offset in inventory preview matches in-game body. |

### cwv-resolve-preview-def-instance-regex — Multi-instance variants beyond _001 silently fail

| Field | Value |
|-------|-------|
| Symptom | Second/third instance of any multi-instance CWV variant shows white in keep inventory (no texture, no transform). |
| Root cause | `_resolve_preview_def` regex was `"^(cwv_.-)_001$"` — matches only instance 1. Instance _002+ silently failed. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.317 |
| Category | STATIC |
| Repro | 1. Set `instances = 2` on a CWV variant. 2. Open keep inventory previewer with both instances. 3. Notice instance 2 is texture-less. |
| Expected post-fix | Regex `"^(cwv_.-)_%d%d%d$"`. |
| Detection | Lint: grep mod sources for `backend_id:match("^%(cwv_`. Pattern must accept any 3-digit suffix. |

### vmf-renderer-creator-keys — Material 'X' not found in Gui crashes on pause-menu / loot view

| Field | Value |
|-------|-------|
| Symptom | Crash `Material 'X' not found in Gui at ui_passes.lua:134` when opening certain UI surfaces. |
| Root cause | VMF reads `ui_renderer_creator` from `debug.traceback()` at frame 4. Lua 5.1 tail-call elimination means frame 4 is usually the OUTER caller, not the inner factory. Every entry-point .lua file must be listed in `ui_renderer_injections`. |
| Mod(s) | dynamic_cosmetic_portraits, cosmetics_tweaker |
| Fix version(s) | dynamic_cosmetic_portraits v0.1.4-0.1.6 |
| Category | INTEGRATION |
| Repro | 1. Mod registers custom material with creator `"ingame_ui_settings"` only. 2. Open Spoils of War / Lohner's Emporium / hero diorama / etc. 3. Observe crash. |
| Expected post-fix | `_renderer_creators` enumerates `ingame_ui`, `ingame_ui_settings`, `hero_view`, `hero_view_state_loot`, `hero_view_state_store`, `hero_view_state_weave_forge`, `start_game_state_settings_overview`, `store_item_purchase_popup`, `store_welcome_popup`, `level_end_view_base`, `level_end_view_versus`, `game_mode_map_deus`, `ui_manager`. |
| Detection | Walk every UI surface (pause menu, all keep sub-views, Spoils, Emporium, end-of-mission, CW map). No crash. |

### vmf-custom-gui-textures — ui_renderer_injections needs nested tables

| Field | Value |
|-------|-------|
| Symptom | Material registration silently does nothing; `Gui.material(gui, name)` returns nil; custom portraits/icons don't appear. |
| Root cause | VMF expects `ui_renderer_injections = { { "creator", "material1", ... }, ... }` (nested tables). A flat list of strings is silently skipped — no error, no log. |
| Mod(s) | dynamic_cosmetic_portraits, cosmetics_tweaker |
| Fix version(s) | dynamic_cosmetic_portraits investigation v0.7.37-v0.7.50 |
| Category | STATIC |
| Repro | 1. Set `ui_renderer_injections = { "ingame_ui", "material1" }` (flat). 2. Open game. 3. Probe `Gui.material(gui, "material1")` returns nil. |
| Expected post-fix | Nested-table format. |
| Detection | Audit `_data.lua` files: each `ui_renderer_injections` entry is a nested table starting with creator string. |

### vt2-portrait-system — Dynamic portrait swap via career_settings only

| Field | Value |
|-------|-------|
| Symptom | Custom portraits show in HUD but not in hero selection / pause menu / Spoils / end-of-mission. |
| Root cause | Per-widget `content.portrait` swaps only cover the HUD path. The only universal swap is `SPProfiles[profile].careers[career].portrait_image` at runtime. |
| Mod(s) | dynamic_cosmetic_portraits |
| Fix version(s) | v0.7.62 |
| Category | INTEGRATION |
| Repro | 1. Equip a portrait-bound hat. 2. Open hero selection / ESC menu / Spoils. 3. Check if custom portrait appears. |
| Expected post-fix | Custom portrait visible in every UI surface that shows the character's portrait. |
| Detection | Walk every portrait-display surface. |

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

## Chaos Wastes (Boons, Mutators, Level Injection)

### vt2-jewelry-traits-become-cw-boons — Necklace/charm/trinket traits ARE CW boons

| Field | Value |
|-------|-------|
| Symptom | Confusion about whether Decanter / Home Brewer / Barkskin / etc. are "weapon traits" or "boons" — they're boons in CW. |
| Root cause | All necklace/charm/trinket traits register as boons in `DeusPowerUpTemplates`. Weapon traits stay weapon traits in both modes. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | doc rule |
| Category | MANUAL |
| Repro | 1. Open ct disable-boon menu. 2. Look at boon list. 3. Note Decanter et al. live there. |
| Expected post-fix | Mod descriptions / UI label them as boons in CW context. |
| Detection | `/dump_boon_loc` in ct should show jewelry traits in the boon list. |

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

### vt2-threat-values-upvalue-built-once — Custom breed crashes calculate_threat_value

| Field | Value |
|-------|-------|
| Symptom | Crash `conflict_director.lua:2479 attempt to perform arithmetic on a nil value` after a custom-breed mod loads, especially when mod is disabled in VMF settings. |
| Root cause | `ConflictDirector` declares `local threat_values = {}` at file scope and fills it by iterating `Breeds` at game boot. Custom breeds added after that are absent. A defensive hook is insufficient when the mod is disabled (VMF still runs module code but skips hooks). |
| Mod(s) | enemy_tweaker |
| Fix version(s) | enemy_tweaker v0.3.5-dev |
| Category | INTEGRATION |
| Repro | 1. Have a mod register a custom breed at module load. 2. Disable the mod in VMF settings. 3. Start a mission. 4. Custom breed spawns (because its registration ran). |
| Expected post-fix | Eager direct-table writes via `CD.set_threat_value(nil, name, value)` at registration site, NOT a hook. |
| Detection | `/regression_test` (enemy_tweaker) verifies the eager write. |

### vt2-pairs-breeds-at-file-load — 3 vanilla tables snapshot Breeds at boot

| Field | Value |
|-------|-------|
| Symptom | Custom breeds added post-boot crash in multiple places: `calculate_threat_value`, `event_ai_unit_activated`, `StatisticsDatabase._create_stat`. |
| Root cause | `conflict_director.lua` (threat_values), `performance_manager.lua` (activated_per_breed), `statistics_definitions.lua` (per-breed stat tables) all iterate `pairs(Breeds)` at file-load. Mod-added breeds miss all three. |
| Mod(s) | enemy_tweaker |
| Fix version(s) | enemy_tweaker v0.3.3 → v0.3.6 |
| Category | INTEGRATION |
| Repro | (Same as threat-values; the other two paths surface at first activate / first damage.) |
| Expected post-fix | Eager direct-table writes to ALL three tables (`set_threat_value`, `_activated_per_breed` via init hook, `StatisticsDefinitions.player.*_per_breed[name] = { ..., name = breed_name }`). |
| Detection | `/regression_test` in enemy_tweaker walks all three. |

### special-events-name-required — Injected live-events entries need `name`

| Field | Value |
|-------|-------|
| Symptom | Game crashes on startup (keep load) with `table index is nil` from `dialogue_system.lua:198`. |
| Root cause | DialogueSystem reads `event_data.name` and writes `self._global_context[event_name]`. Without `name`, the assignment errors. |
| Mod(s) | event_tweaker |
| Fix version(s) | event_tweaker v0.2.1-dev |
| Category | STATIC |
| Repro | 1. Inject a live event with `{ weekly_event = "append", mutators = {...} }` (no name). 2. Start the game. |
| Expected post-fix | Every injected entry has non-nil string `name`. |
| Detection | Lint: grep `event_tweaker` injection sites for `name = ...`. |

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

### vt2-unit-actor-one-indexed — Unit.actor iteration must start at 1

| Field | Value |
|-------|-------|
| Symptom | Collision/scene-query disable silently no-ops; players still bumped by altar/chest collider on injected adventure levels. |
| Root cause | `Unit.actor(unit, i)` is 1-indexed. Iterating `for i = 0, num_actors - 1` returns nil at index 0 and skips the final actor. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.6.19 |
| Category | STATIC |
| Repro | 1. Iterate `for i = 0, Unit.num_actors(unit) - 1 do ... end`. 2. Walk into the altar. 3. Get blocked. |
| Expected post-fix | `for i = 1, Unit.num_actors(unit) do ... end`. |
| Detection | Lint: grep mod sources for `for i = 0,` followed by `Unit.actor(`. |

---

## Localization / UI

### vmf-mod-localization-not-global — `_localization.lua` keys not in global Localize

| Field | Value |
|-------|-------|
| Symptom | HUD pickup popup / interaction prompt shows `<cwv_interaction_*>` (bracketed key) instead of localized text. |
| Root cause | VMF's `_localization.lua` is a private lookup readable only via `mod:localize(key)`. Vanilla code calling `_G.Localize(key)` doesn't see it. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.199 |
| Category | STATIC |
| Repro | 1. Add `cwv_my_pickup_string = { en = "Foo" }` to `_localization.lua`. 2. Set `Pickups.ammo[...].hud_description = "cwv_my_pickup_string"`. 3. Walk near the pickup. |
| Expected post-fix | Add the key to the `_G.Localize` hook's `_hud_strings` table too. |
| Detection | Visual: pickup popups / interaction prompts show real text, not `<key>`. |

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

### vt2-player-unit-field — player_unit is a field, not a method

| Field | Value |
|-------|-------|
| Symptom | Crash `attempt to call method 'player_unit' (a userdata value)` on any code path that calls `pl:player_unit()`. |
| Root cause | `player_unit` is a Player field, not a method. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.8.8 |
| Category | STATIC |
| Repro | 1. Write `pl:player_unit()`. 2. Run that code path. |
| Expected post-fix | `pl.player_unit` (field access). |
| Detection | Lint: grep mod sources for `:player_unit(`. Should be absent. |

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

### la-prefix-patch — Patching VMFMod prototype before target mod loads

| Field | Value |
|-------|-------|
| Symptom | `get_mod("Loremasters-Armoury")` returns nil at load order. Wrapper hook never installs. |
| Root cause | `new_mod` runs the target mod's `mod_script` BEFORE returning, so the target isn't visible to mods loaded above it in launcher order. |
| Mod(s) | la_prefix_patch |
| Fix version(s) | la_prefix_patch v0.2.0-dev |
| Category | STATIC |
| Repro | (Documented; only relevant when adding new prototype patches.) |
| Expected post-fix | Patch `VMFMod.hook`/`hook_safe`/`hook_origin` directly with target-name filter. Patcher loads above target. |
| Detection | Visual: target mod's noisy log lines suppressed. |

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

### release-source-not-immutable — Published bundle cannot be rebuilt from its recorded commit

| Field | Value |
|-------|-------|
| Symptom | A schema-2 manifest records `source_state: dirty`, or a clean entry's raw bundle hashes cannot be reproduced from `source_commit`. |
| Root cause | Historical publication allowed build/upload before immutable source review, so `HEAD` could be only a baseline rather than the exact build input. |
| Mod(s) | release tooling; all published VMB mods |
| Fix version(s) | transition gate for issue #558 |
| Category | STATIC / PROCESS |
| Repro | Before build, run `.\qa\check_release_reproducibility.ps1 -Mod <mod> -AuditOnly`. After publication, run the full command against a separate checkout of the manifest's `source_commit` with the recorded VMBLauncher version. |
| Expected post-fix | Pre-build audit reports CLEAN; fresh `VMBLauncher build --clean` produces exactly the recorded `.mod_bundle` and `.mod` filenames and SHA-256 values. No deploy or upload occurs during the proof. |
| Detection | Offline self-test: `.\qa\check_release_reproducibility.ps1 -SelfTest`. Live transition remains report-only until maintainers approve commit-before-build failure/rollback policy. |

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

### feedback-workshop-upload-without-deploy — Author's local install stays stale

| Field | Value |
|-------|-------|
| Symptom | After uploading a new version, you restart VT2 and console still echoes the OLD version. |
| Root cause | Steam doesn't reliably re-download Workshop items the same Steam account authored. |
| Mod(s) | all |
| Fix version(s) | canonical reviewed ship workflow |
| Category | MANUAL |
| Repro | 1. Run `vmblauncher upload <mod>`. 2. Restart VT2. 3. Watch console show old version. |
| Expected post-fix | Claim; run `ship.ps1 -BuildOnly`; commit/push/PR/qa-gate/merge; then run canonical ship from clean live default HEAD. |
| Detection | After every upload, restart VT2; console version matches bumped MOD_VERSION. |

### feedback-deploy-vs-upload-distinction — Local deploy doesn't reach subscribers

| Field | Value |
|-------|-------|
| Symptom | Friend / subscriber still reports old behavior; only the author's local install is updated. |
| Root cause | `deploy_all.ps1` only copies to LOCAL workshop folder. Subscribers get the version on Steam, which needs `upload`. |
| Mod(s) | all |
| Fix version(s) | canonical reviewed ship workflow |
| Category | MANUAL |
| Repro | 1. Run `vmblauncher deploy <mod>` only. 2. Friend reports no change. |
| Expected post-fix | Use the canonical reviewed ship sequence for subscriber-facing changes; local deploy remains non-publishing. |
| Detection | After every iterative fix, verify both the local file AND the Workshop page changed. |

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

### vt2-workshop-folder-steam-managed — Don't write into workshop/content/552500/<real_id>/

| Field | Value |
|-------|-------|
| Symptom | Friend's mod folder is wiped after running a deploy/update tool. |
| Root cause | Steam manages the Workshop content folder. Foreign writes get reverted or the entire folder deleted. |
| Mod(s) | tooling (vt2-mod-updater); affects friends downstream |
| Fix version(s) | vt2-mod-updater v0.2.0 (synthetic 10XXXXXXXXXX IDs) |
| Category | MANUAL |
| Repro | (Historic — vt2-mod-updater v0.1.0 wiped a friend's career_tweaker folder.) |
| Expected post-fix | Use synthetic ID range (`10<real_workshop_id>`) for friend-side deploys. Friends unsubscribe on Workshop to avoid double-load. |
| Detection | Audit deploy tooling for writes into `steamapps/workshop/content/552500/<real_id>/`. |

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

## Misc

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

### feedback-cwv-definition-of-done — DoD gate before declaring variant done

| Field | Value |
|-------|-------|
| Symptom | (Process.) CWV variants shipping incomplete (offhand crashes / missing pickups / no scale / forge broken / etc.). |
| Root cause | No single gate per variant. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | DEFINITION_OF_DONE.md (rule) |
| Category | MANUAL |
| Repro | n/a |
| Expected post-fix | Walk `character_weapon_variants/DEFINITION_OF_DONE.md` for every new variant. CHANGELOG entry ends with `**DoD:**` footer. |
| Detection | CHANGELOG audit — every variant entry has the DoD footer. |

### vt2-max-overheat-modifier-unified — `max_overcharge` (not `max_overheat_modifier`) is the stat_buff key

| Field | Value |
|-------|-------|
| Symptom | Boon advertising "+5% max overheat" has no effect, OR Sienna staff/Bardin drakefire crashes at `_calculate_and_set_buffed_max_overcharge_values` with `Max overcharge outside value bounds allowed by network variable!`. |
| Root cause | Wrong stat_buff key won't fire. Correct key is `max_overcharge`. Also: bound is ~60 (engine .network_config) — exceeding crashes. Use `reduced_overcharge` instead for "more comfortable casting" semantics. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.80-alpha |
| Category | INTEGRATION |
| Repro | 1. Add `{ stat_buff = "max_overcharge", multiplier = 0.05 }` and stack to 12 boons. 2. Equip Sienna staff. 3. Watch crash at 64/60 cap. |
| Expected post-fix | Use `reduced_overcharge` with negative multiplier for safe stacking. |
| Detection | `/regression_test` in ct checks the buff key. |

---

## Table of Contents (by slug)

- 1p-animations-universal
- 1p-animations-universal-recurring
- 3p-anim-fix-process
- anim-closed-vocabulary
- anim-remap-per-unit-state
- cross-mod-br-registration-sync
- ct-graph-snapshot-rpc
- ct-husk-hook-shadow-tpe
- ct-offhand-force-preload
- cwv-ammo-unit-required
- cwv-backend-id-lookup
- cwv-blacksmith-template
- cwv-clone-name-clobber
- cwv-cross-character-unit-packages
- cwv-custom-mesh-material
- cwv-dual-wield-display-rig
- cwv-frankenstein-template
- cwv-imperial-longsword-family
- cwv-previewer-template-lookup
- cwv-projectile-template-lookup
- cwv-resolve-preview-def-instance-regex
- feedback-cwv-definition-of-done
- feedback-deploy-vs-upload-distinction
- feedback-mod-version-format
- feedback-pre-deploy-checklist
- feedback-redundant-safeguards-ok
- feedback-search-changelog-for-known-crashes
- feedback-vmf-hook-safe-no-chain
- feedback-workshop-upload-verify
- feedback-workshop-upload-without-deploy
- gated-registration-divergence
- hook-multi-return-collapse
- inventory-preview-hook-menuworldpreviewer
- la-custom-mesh-unsupported
- la-hat-kind-texture-needs-paint
- la-icon-key-vs-item-type
- la-kind-unit-pipeline
- la-offhand-paint-pipeline
- la-prefix-patch
- loot-previewer-hook-not-safe
- lua-forward-reference
- preview-slot-keying
- ps5-getcontent-utf8
- special-events-name-required
- ugc-tool-forward-slashes
- ugc-tool-pushes-all-cfg-fields
- vmblauncher-handscaffold-first-upload
- vmf-custom-gui-textures
- vmf-dropdown-options-mutated
- vmf-grip-offset-sign
- vmf-mod-localization-not-global
- vmf-network-send-recipients
- vmf-renderer-creator-keys
- vmf-rpc-string-cap
- vmf-widget-id-unique
- vt2-adventure-pack-spawning-compat
- vt2-chat-command-syntax
- vt2-class-hook-derived
- vt2-custom-explosion-template
- vt2-deus-power-up-rarities
- vt2-dormant-buff-template-dual-register
- vt2-force-load-only-listed-paths
- vt2-hash-reverse-lookup
- vt2-husk-extension-class-pair
- vt2-husk-rpc-race
- vt2-jewelry-traits-become-cw-boons
- vt2-lobby-combined-hash
- vt2-localize-string-format-pipeline
- vt2-lua-200-locals
- vt2-max-overheat-modifier-unified
- vt2-mission-spawn-career-lookup
- vt2-mod-command-inventory
- vt2-mutator-template-server-wrap
- vt2-networked-flow-state-leak
- vt2-no-bows-on-warrior-priest
- vt2-no-custom-package-paths
- vt2-no-tpose-default-stance
- vt2-pairs-breeds-at-file-load
- vt2-player-unit-field
- vt2-portrait-system
- vt2-quaternion-vector3-box-for-storage
- vt2-strict-lookup-rawget
- vt2-threat-values-upvalue-built-once
- vt2-unit-actor-one-indexed
- vt2-unit-node-not-pcall-safe
- vt2-workshop-folder-steam-managed
# Mod Tweaker profiles (#561)

- In the keep and in a mission, profile 1 starts from the user's current settings.
- Profiles 2-10 start from declared defaults and restore independently per tab.
- When a mod adds a setting, an older profile inherits that setting's current
  declared default without changing any explicitly saved value (including false).
- Persist the reconciled snapshot only after every added default commits through
  the bounded owner transaction; a failed owner callback must not mark migration
  complete.
- Switching profiles with pending edits applies those edits to the old profile first.
- DEFAULT plus Apply updates only the active profile on the visible tab.
- The active number and values survive a full restart, including merged tabs.
- Keybinds remain unchanged when profiles switch.
- With search active, switching profiles keeps the filter usable and does not alter
  the saved collapsible expansion snapshot.
