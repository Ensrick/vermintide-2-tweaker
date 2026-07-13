# Regression Checklist — character_weapon_variants

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to character_weapon_variants.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

Last updated: 2026-07-13.

---

## Multiplayer

### issue474-old-musket-remote-continuity — Hot join loses cross-slot identity and custom mesh has no remote report

| Field | Value |
|-------|-------|
| Symptom | A joining observer sees the melee-slot Old Musket as a vanilla Handgun; after a live ranged re-equip the custom model is correct but its shot is silent for the observer. |
| Root cause | Hot-join safety must null the locally appended CWV skin until peer parity is known, removing the only positive variant identity from the vanilla base-item wire shape. Separately, `ActionHandgun` only explicitly plays `fire_sound_event`, but vanilla Handgun defines none; its report is authored in the compiled rifle unit, which the custom mesh does not contain. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.377-dev, v0.1.394-dev, v0.1.395-dev (#474) |
| Category | MULTIPLAYER |
| Repro | Equip Old Musket in melee, let a second player hot-join, then live re-equip and repeat in ranged. Observer checks custom model/pose/transforms and listens to hip/ADS shots; reverse host/client roles. |
| Expected post-fix | Handshake remains safe, then one post-parity replay restores exact Old Musket identity in either slot. Each real Old Musket shot produces one positional vanilla rifle report for other peers and no additional report for the owner. |
| Detection | `/cwv_regression_test`: `issue474_old_musket_hot_join_identity_and_remote_fire`; logs show bounded `[cwv:579] replayed ...` on parity enable and one `[cwv:474] remote old-musket rifle fire dispatched ...` per shot. |

### issue478-outrider-husk-handedness — Skinless crafted Outrider is wholly invisible remotely

| Field | Value |
|-------|-------|
| Symptom | A crafted, skinless Outrider resolves to the correct CWV definition on the observing client, yet both remote 3P hand units are nil and the whole weapon is invisible. |
| Root cause | Vanilla obtains base `dr_deus_01` units and branches on their hand fields before `GearUtils.spawn_inventory_unit`. The base is left-mounted, while Outrider is a right-mounted blunderbuss with `no_left_hand`; CWV's existing correction inside the later per-hand spawn could suppress the stale left call but could not create the right call vanilla never scheduled. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.379-dev, v0.1.395-dev (#478) |
| Category | MULTIPLAYER / CRASH FLOOR |
| Repro | Craft an Outrider through CIM so it has no skin, equip it on Kruber, and have a second player observe it in the keep and a mission; reverse host/client roles. Include a native Bardin Trollhammer control. |
| Expected post-fix | The observer sees only the right-hand blunderbuss. CWV preselects authored hands before vanilla's spawn branch; the later residency gate still suppresses any unsafe stale unit. Skinned/native weapons remain unchanged. |
| Detection | `/cwv_regression_test`: `cwv_husk_nonresident_spawn_deferred`; one bounded `[cwv:478] husk preselected hands ...` line proves the upstream decision, and no nonresident-spawn error follows. |

---

## Weapon Skins

### issue586-dual-axes-fp-residency — Resync cannot wield an unloaded state machine

| Field | Value |
|-------|-------|
| Symptom | Client C-fatals on `units/beings/player/first_person_base/state_machines/melee/dual_axes` while a CWV Dual Axes loadout is resynchronized. |
| Root cause | `ProfileSynchronizer` built its first-person package list from the prior backend loadout, then CWV's equipment resync wielded `dual_wield_axes_template_1` before the new state-machine package was resident. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | 0.1.392-dev (#586) |
| Category | INTEGRATION / CRASH |
| Repro | As client, equip `cwv_es_dual_axes` or `cwv_wh_dual_axes` through a loadout resync whose previous melee weapon uses another state machine. |
| Expected post-fix | The CWV-owned `dual_axes` FP package lease is already resident; equip, swap away/back, character change, and loadout resync do not crash or increase its reference count. |
| Detection | `/cwv_regression_test`: `issue586_cross_character_dual_axes_fp_residency`; then verify both ES and WH variants through the live transition matrix above. |

### issue582-dual-axes-owner-boundary — Native base must not compete with CWV variants

| Field | Value |
|-------|-------|
| Symptom | Kruber/Saltzpyre can equip native `dr_dual_wield_axes`; CWV correctly declines to re-key it, bypassing the dedicated variant's ownership/cosmetic identity. |
| Root cause | WT independently exposed Bardin's native base alongside CWV's `cwv_es_dual_axes` and `cwv_wh_dual_axes`. |
| Mod(s) | weapon_tweaker, character_weapon_variants |
| Fix version(s) | WT v0.12.226-dev; CWV v0.1.391-dev (#582) |
| Category | INTEGRATION |
| Repro | Enable WT native Dual Axes on Kruber/Saltzpyre, equip a Bardin illusion, and observe the key remains `dr_dual_wield_axes` rather than a CWV owner. |
| Expected post-fix | Native base has no ES/WH receiver; both dedicated CWV entries remain registered for their four receiver careers with #579 cosmetic parity. |
| Detection | `/cwv_regression_test`: `issue582_dual_axes_native_variant_ownership_boundary` plus `dual_axes_cosmetic_family_parity`; `/wt_regression_test`: `issue582_native_dual_axes_cwv_ownership_boundary`. |


---

### issue567-deferred-owner-cache - Custom skin reverse-index rebuilds

| Field | Value |
|-------|-------|
| Symptom | Save/loadout refresh logs `Incorrectly configured weapon skins for cwv_*` and can reject or revert a persisted custom illusion. |
| Root cause | Vanilla lazily snapshots skin-to-owner mappings before CWV's backend-deferred weapon owner rows exist, then retains the stale private cache. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | 0.1.388-dev |
| Category | INTEGRATION |
| Repro | Equip the three issue #567 skins, reload the keep, and let bot/loadout refresh complete. |
| Expected post-fix | No `Incorrectly configured weapon skins` warnings. `[cwv:567]` reports `association=valid` for all three; skins remain equipped and render locally and on a husk. |
| Detection | Run `/cwv_regression_test`; require `issue567_skin_reverse_index_valid` PASS. |

---
## Multiplayer / Network Sync

### issue398-cross-access-remote-audio — Owner and husk consume one receiver event

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | A remote listener cannot hear weapon swing foley or character exertion for a cross-access CWV weapon, although the wielder hears both locally. |
| Root cause | CWV substituted the donor 3P event in `Unit.animation_event`, after vanilla had already encoded and sent that event. The owner played the receiver event locally while husks received a donor event their body could no-op. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | 0.1.393-dev (#398) |
| Category | INTEGRATION |
| Repro | Player A equips a cross-access weapon such as Axe and Falchion or Dual Axes on Kruber and performs light, heavy, push, and push-attack chains while Player B listens nearby. Repeat after swapping host/client roles. |
| Expected post-fix | Player B sees each receiver-compatible attack and hears both its weapon swing foley and character exertion. Player A hears one local copy. Native-wielder and native-weapon controls remain unchanged. |
| Detection | `/cwv_regression_test` requires `issue398_cross_access_audio_uses_networked_receiver_event` PASS. Logs show bounded `[cwv:398] networked 3P remap` lines, no `network remap declined`, and no relevant `[cwv husk-fx] ... SKIP`. Test one host-owned and one client-owned weapon, then reverse listener/wielder roles. |

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


---

### cwv-cosmetic-family-parity — Same-family harvest drifts from canonical owner pool

| Field | Value |
|-------|-------|
| Symptom | A CWV variant offers only some cosmetics from the corresponding vanilla weapon; DLC/weave skins are commonly absent. |
| Root cause | The registrar scans `ItemMasterList` at one load instant or appends only to a fixed set of rarity tiers. Vanilla's authoritative pool is the owner's `WeaponSkins.skin_combinations` table, which DLC files extend with tiers such as `magic`; the default skin is stored separately in `WeaponSkins.default_skins`. |
| Mod(s) | character_weapon_variants |
| Fix version(s) | CWV v0.1.390-dev, v0.1.394-dev (#579) |
| Category | INTEGRATION |
| Repro | Open the Dual Axes illusion picker and compare its unique cosmetic keys with `wh_1h_axe_skins` plus `WeaponSkins.default_skins.wh_1h_axe`; select one with visibly distinct hands, inspect the inventory character preview, then join as a second player and inspect the owner's husk after the parity handshake. |
| Expected post-fix | Exact source/clone key-set parity; source tier memberships and `required_dlc` are preserved; each clone has both hands and the family display rig. The inventory character preview and remote husk preserve the exact generated skin instead of reverting to the variant default. |
| Detection | `/cwv_regression_test` checks `dual_axes_cosmetic_family_parity` and `issue579_dual_axes_preview_and_husk_skin_continuity`; coop log contains one bounded `[cwv:579] replayed ... after peer-parity confirmation` line per parity-enable edge. |


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


---

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


---

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


---

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


---

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


---

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


---

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


---

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


---

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


---

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


---

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


---

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


---

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

## Slugs

- 1p-animations-universal
- 1p-animations-universal-recurring
- 3p-anim-fix-process
- anim-closed-vocabulary
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
- loot-previewer-hook-not-safe
- lua-forward-reference
- preview-slot-keying
- ps5-getcontent-utf8
- ugc-tool-forward-slashes
- ugc-tool-pushes-all-cfg-fields
- vmblauncher-handscaffold-first-upload
- vmf-dropdown-options-mutated
- vmf-grip-offset-sign
- vmf-mod-localization-not-global
- vmf-network-send-recipients
- vmf-widget-id-unique
- vt2-chat-command-syntax
- vt2-class-hook-derived
- vt2-force-load-only-listed-paths
- vt2-hash-reverse-lookup
- vt2-husk-extension-class-pair
- vt2-lua-200-locals
- vt2-mod-command-inventory
- vt2-no-custom-package-paths
- vt2-no-tpose-default-stance
- vt2-quaternion-vector3-box-for-storage
- vt2-unit-node-not-pcall-safe
