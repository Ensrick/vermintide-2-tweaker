# Regression Checklist — cosmetics_tweaker

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to cosmetics_tweaker.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

Last updated: 2026-07-15.

---
## Grail Knight inventory hero replay (#629)

| Field | Value |
|---|---|
| Symptom | The Purpure/Azure outfit applied in live third person but the inventory-screen character model showed the donor outfit even though the log recorded `surface=hero_preview`. |
| Root cause | The preview replay painted and cached `mesh_unit` on its hidden spawn frame. On the following update, vanilla `_update_units_visibility` called `_set_character_visibility(true)` and restored `skin_data.material_changes`; the same-mesh cache then suppressed every corrective repaint. |
| Fix version | cosmetics_tweaker v0.9.128-dev |
| Expected | Hidden or not-yet-visible meshes are never cached. The first visible frame paints once after vanilla's material restore; hide/show, view reopen, and career respawn invalidate and replay once without per-frame writes. |
| Detection | Offline `test_cos_grail_knight_set.lua` simulates hidden spawn, visible transition, same-mesh steady state, hide/show, and new-mesh respawn. `/cos_regression_test` passes `issue629_grail_knight_set_contract`. |
| Tracking | GitHub issue #629. |

---
## Authored Encarmine Helmet (#612)

| Field | Value |
|---|---|
| Identity | `cos_encarmine_hat` is registered exactly once regardless of settings; toggle changes never append or reorder `NetworkLookup.item_names`. |
| Ownership | Foot Knight only, no DLC requirement; disabling hides the item and resolves equipped state to the vanilla Laurel Helm. |
| Assets | Derivative unit has separate armor/cloth mesh slots, custom diffuse maps, untouched vanilla normal/combined sources, an authored inventory icon, and pinned response maps. Cloth diffuse alpha <=15 is cleared, every retained texel is alpha 255, cut alpha is compiler-enabled, and retained RGB is lifted 4x. Armor roughness has exactly the bounded 166/110 paint/detail response. Each of the 372 source plume faces has one reversed counterpart (744 render faces). The FBX and same-name `.bones` retain all 13 Laurel bones and six weighted dynamic joints. |
| Surfaces | Inventory grid, hero/lobby preview, local third person, remote husk, hot join, transitions, and score screen converge on one appearance. Package-facing records stay on Laurel; only final spawn choke points substitute the resident custom unit. Every custom spawn receives the resident Laurel controller; live owner/husk attachments are enrolled once in camera fade. |
| Peer safety | Cosmetics peers receive the bounded custom appearance token; peers without Cosmetics receive only `knight_hat_0006`. |
| Detection | Offline `test_cos_custom_hats.lua` proves preview/live/husk/replay spawn adapters, permanent package quarantine, alpha graph, face/material revision, runtime controller install, and fade enrollment. The bundle reachability gate pins the FBX, textual bones, and all authored maps; `/cos_regression_test` passes `issue612_encarmine_hat_contract`; bounded `[cos:612]` lines identify each applied surface; two-player visual/motion/fade/fallback verification. |

---
## Network teardown player lookup (#609)

| Field | Value |
|---|---|
| Invariant | Every Cosmetics local-player lookup uses the shared `local_player_safe` gate; no update, state callback, hook, or diagnostic calls bare `local_player()`. |
| Title/teardown | No live network game returns nil without touching `Network.peer_id()`; queued lifecycle work remains bounded and retries only after a player is safe. |
| In-game | A live game returns the same player and preserves cosmetic, glow, persistence, and TPE behavior. |
| Detection | Offline `test_cos_glow_lifecycle.lua`; `/cos_regression_test` passes `local_player_safe_network_lifecycle_609`; title transition yields zero Cosmetics `Network backend has not been set` stacks. |

---
## Manual glow editor and committed badges (#377)

| Field | Value |
|---|---|
| Scope | Hero-view inventory and illusion grids; exact backend item plus skin identity. |
| Open policy | Selection and wield never open the editor. The persistent in-view button is the only contextual open/close action. |
| Commit boundary | Badge state reads durable Apply data only. Dirty live previews never alter a badge. |
| Color | Rune uses committed RGB. Magic uses the deterministic intensity-weighted lower/upper/dots blend. |
| Refresh | One Apply callback refreshes weakly tracked live grids/windows once; no per-frame decode or RPC traffic. |
| Asset safety | Authored PNG is packaged unchanged and runtime tinted. Missing atlas/material fails closed with one bounded warning. |
| Detection | Offline `test_cos_glow_badge_policy.lua` and `test_cos_glow_lifecycle.lua`; `/cos_regression_test` passes `glow_manual_editor_button_377`. |

---
## Authored heroic weapon poses (#485)

| Field | Value |
|---|---|
| Scope | Default-off, local presentation only, and active only when `script_data["eac-untrusted"]` identifies the modded realm. |
| Catalog | Include only valid `ItemMasterList` rows with `item_type="weapon_pose"`, exact `parent`, numeric `pose_index`, and an authored animation event; sort deterministically. |
| Backend boundary | Do not write `unlocked_weapon_poses`, fake inventory, equipped pose skins, or PlayFab read-only data. |
| Live refresh | Changing the option makes `SocialWheelUI._is_dirty` rebuild the current weapon's page once. |
| Missing catalog | Preserve vanilla behavior and emit one `[cos:485]` record per missing parent. Do not borrow another weapon's package yet. |
| Detection | Offline `test_cos_weapon_pose_policy.lua`; `/cos_regression_test` passes `issue485_authored_weapon_poses_local_only`. |
| Lifecycle | `diagnostics-armed` until at least one no-catalog weapon establishes a safe donor-animation and icon-package policy. |

---
## Diagnostics / Regression Suite

### oop-phase4a-wire-boundary -- custom skins never enter vanilla lookups

| Field | Value |
|-------|-------|
| Scope | Structural extraction of the three vanilla `rpc_add_equipment` sender guards; no wire or gameplay behavior change. |
| Invariant | Every custom illusion skin is temporarily nil only while vanilla encodes/sends it, then restored locally. The boundary is unconditional and covers initial spawn, resynced equip, and hot join. |
| Module | `_cos_wire.lua`, manifest-ordered after `_cos_illusions.lua`. |
| Detection | Offline `test_cos_wire.lua`; `/cos_regression_test` passes `wire_skin_null_ungated` and `wire_skin_null_all_senders`. |
| Verification | Co-op exercise initial spawn, mid-session re-equip, and hot join with a `ct_*` illusion; owner retains the local illusion and no peer crashes. |
| Tracking | GitHub issue #504 Phase 4a; issue #421 wire-safety invariant. |

---

### la-exact-instance-persistence-icons -- no shared icon mutation

| Field | Value |
|-------|-------|
| Symptom | LA illusions survived only in session and inventory icons were either vanilla or leaked onto unrelated same-type weapons. |
| Root cause | LA's authored icon is keyed by `(armoury_key, vanilla_skin)` in `SKIN_LIST[*].icons`; the reverted v0.9.9.0 attempt read `WeaponSkins.skins[armoury_key]` and mutated shared icon tables. Persisted exact-item records also outlived deleted official items. |
| Mod(s) | cosmetics_tweaker + Loremaster's Armoury |
| Fix version(s) | cosmetics_tweaker v0.9.99-dev |
| Category | INTEGRATION / SOLO |
| Repro | Apply different LA choices to two same-type backend items, restart, inspect both inventory icons/renders, then delete one modified item and return to the keep. |
| Expected post-fix | Each surviving backend item restores and displays only its own authored icon/illusion. Duals keep the row-1/main-right icon regardless of their saved left override; shields follow the selected left-hand shield, including LA's authored variant/base-skin icon. Unmodified instances retain vanilla icons. Missing metadata fails closed; deleted-item overrides are pruned after the backend-ready delay. |
| Detection | Offline `test_cos_la_instance_policy.lua` passes; `/cos_regression_test` passes `la_exact_instance_inventory_icon_376`; console prints one bounded `[la-state] INSTANCE-PRUNE N...` summary. |

---

### la-kruber-shield-catalogue-compatibility -- native and CWV pools preserve mesh provenance

| Field | Value |
|-------|-------|
| Symptom | CWV Axe and Shield showed only Loremaster Bretonnian choices and no vanilla shields; selecting a Bretonnian choice wrapped heater-shield textures around an Imperial shield mesh. |
| Root cause | The LA merge created a new CWV pool without first seeding the vanilla Empire shields. The old parity rule also spread every pure-paint Bretonnian variant to every Kruber shield even though those entries declare no replacement unit and require Bretonnian UVs. |
| Mod(s) | cosmetics_tweaker + Loremaster's Armoury; character_weapon_variants for CWV rows |
| Fix version(s) | pending release |
| Category | INTEGRATION / MULTIPLAYER |
| Repro | Compare the LA offhand row on Kruber Sword and Shield, Mace and Shield, Bretonnian Sword and Shield, Spear and Shield, and CWV Axe/Longsword/Warrior-Priest Hammer shield weapons. |
| Expected post-fix | CWV Empire-family weapons expose the complete vanilla Empire pool plus Empire-compatible LA choices. Pure Bretonnian paint stays on the Bretonnian family; a custom-unit LA option may span families because it carries its authored mesh. Whenever an LA entry declares `new_units`, paint occurs only on that exact 1P/3P unit. |
| Detection | `/cos_regression_test` passes `la_kruber_shield_catalogue_compatibility_204`; offline `test_cos_la_shield_parity.lua` locks the complete item catalogue, Empire/Breton isolation, CWV vanilla seeding, and declared-unit paint gate. Coop verifies customization preview, local 1P/3P, inventory hero preview, transition, and remote husk rendering. |
| Tracking | GitHub issues #204 and #266. |

### la-offhand-wielded-weapon-identity -- shield paint cannot wrap another weapon

| Field | Value |
|-------|-------|
| Symptom | A Loremaster shield pick stored on Grail Knight's secondary Bretonnian Sword and Shield wraps its texture around the mace of the currently wielded CWV Sword and Mace at mission spawn. |
| Root cause | The identity guard read `inventory.wielded_slot`, which is present on the husk inventory but absent on the local-owner inventory. The local wielded item resolved to nil and the old conditional fell through permissively, painting whichever left-hand unit was active. |
| Mod(s) | cosmetics_tweaker + character_weapon_variants + Loremaster's Armoury |
| Fix version(s) | cosmetics_tweaker v0.9.85-dev; user verified on v0.9.87-dev |
| Category | INTEGRATION |
| Repro | As Grail Knight, equip CWV Sword and Mace in the primary melee slot and a Bretonnian Sword and Shield with an LA shield pick in the secondary slot, then enter a mission spawning with Sword and Mace wielded. |
| Expected post-fix | Sword and Mace remains unpainted; wielding the Bretonnian Sword and Shield applies the stored LA paint only to its shield. An unresolved or different wielded identity fails closed and retries on the matching weapon's next wield. |
| Detection | `/cos_regression_test` passes `cos_la_weapon_identity_gate_local_wearer`. The wrong-weapon spawn replay logs one bounded `[la-state] APPLY SKIP wrong-weapon` identifying the stored shield template and wielded Sword and Mace template. User verification log `console-2026-07-13-19.20.26-40f91837-d631-41e8-8743-340abd87907c.log` contains both signals. |
| Tracking | GitHub issue #514. |

### independent-dual-offhands -- native and CWV per-instance hand ownership

| Field | Value |
|-------|-------|
| Symptom | Warrior Priest Dual Skullsplitters and CWV dual weapons could not retain an offhand cosmetic independently from the paired main illusion. |
| Root cause | The native registry excluded `wh_dual_hammer`, CWV's generated skin tables were unavailable at Cosmetics load order, direct unit choices had no durable record, and the UI treated both custom rows as hand owners instead of leaving main-hand ownership with vanilla row 1. |
| Mod(s) | cosmetics_tweaker; character_weapon_variants when installed |
| Fix version(s) | cosmetics_tweaker v0.9.97-dev |
| Category | INTEGRATION / MULTIPLAYER |
| Repro | Customize native Dual Skullsplitters or any CWV dual family, choose a row-1 main illusion and a distinct offhand, Apply, restart/transition, and observe from another peer. |
| Expected post-fix | Row 1 owns main/right and the inventory icon; one added row owns left/offhand visuals only; Follow Main clears only the offhand override. Choices persist by backend item and hand, render in preview/1P/local3P/remote husk, and converge on transition/hot join. Invalid stored or received units fail closed to the main illusion. |
| Detection | `/cos_regression_test` passes `independent_dual_offhands_583`, `cos_la_offhand_persistence_roundtrip`, and `issue483_cwv_sword_mace_individualized_cosmetics`. Direct peer replay remains one last-choice queue entry per `(backend_id, hand)`, uses the existing RPC schema, and is replayed by the bounded acknowledged state pull. |
| Tracking | GitHub issue #583. |

### cwv-dawi-mace-appearance-contract -- primary, dual, and shield ownership

| Field | Value |
|-------|-------|
| Repro | Craft each Dawi Mace family weapon through CIM. Change the single mace illusion; give Dual Maces visibly different primary/offhand illusions; give Mace and Shield visibly different mace/shield illusions. Restart, transition, and observe from another peer. |
| Expected post-fix | Single Mace and Dual Maces use the primary mace for their inventory icon. Dual Maces retain the exact offhand independently. Mace and Shield uses the selected Bardin shield for its icon and retains mace/shield choices independently. Preview, 1P, local 3P, remote husk, and hot join converge through the existing exact-hand paths. |
| Detection | Offline `test_cos_cwv_dawi_mace_contract` passes and confirms all three canonical item/skin-table keys, hand ownership, Bardin source pools, and absence of a bespoke Dawi RPC/hook. |
| Tracking | Dawi Mace family implementation. |

### issue483-cwv-sword-mace-individualized-cosmetics -- independent hands and peer replay

| Field | Value |
|-------|-------|
| Symptom | CWV Sword and Mace exposed only generated paired illusions, so a player could not choose the right-hand sword and left-hand mace cosmetics independently. |
| Root cause | Cosmetics' two-row picker registry knew only vanilla dual item types and skin-combination-table sources; `cwv_es_sword_and_mace` and its distinct source families were absent. |
| Mod(s) | cosmetics_tweaker + character_weapon_variants |
| Fix version(s) | cosmetics_tweaker v0.9.95-dev |
| Category | INTEGRATION / MULTIPLAYER |
| Repro | Equip CWV Sword and Mace, open customization, and inspect or change each hand's cosmetic locally and from a second peer. |
| Expected post-fix | Vanilla row 1 owns the sword/right hand and the added offhand row contains only `es_1h_mace` meshes plus Follow Main. Applying one hand does not overwrite the other, and the chosen pair survives wield swaps plus initial/hot join on both viewers. |
| Detection | `/cos_regression_test` passes `issue483_cwv_sword_mace_individualized_cosmetics`; it validates both exact source families and the existing direct-unit sender, receiver, and hot-join store. Coop verification covers visible per-hand independence and state replay. |
| Tracking | GitHub issue #483. |

### glow-picker-explicit-apply -- persistence and peer rendering

| Field | Value |
|-------|-------|
| Symptom | RGB edits had no Apply button; closing silently persisted a mutable live-preview table and no per-item color reached peers. |
| Root cause | The picker implemented save-on-close without dirty/committed snapshots, while the retained glow RPC carried an empty state after the global glow menu was removed. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.9.92-dev (Apply/persistence), v0.9.93-dev (spawn/preview/husk fan-out), v0.9.94-dev (initial/hot-join convergence) |
| Category | INTEGRATION / MULTIPLAYER |
| Repro | Edit a glow slider, close or Apply, reopen/restart, and observe the same weapon from local 1P/3P and a second client. |
| Expected post-fix | Close discards preview-only edits; one Apply persists the exact backend-item+illusion identity and emits one host-authoritative active-glow update; repeated Apply is a no-op. |
| Detection | `/cos_regression_test` passes `glow_picker_apply_transaction_574` and `glow_picker_render_fanout_574`; offline `test_cos_glow_lifecycle.lua` and tier-a invariants lock the exact identity, explicit transaction, render fan-out, and bounded no-network-retry join contract. One successful click logs one `[glow_picker:apply] committed` line. Bounded `[cos:574] sync ...`, `state-pull reply`, `rehydrate armed|complete|expired`, and `repaint path=husk_wield ...` lines prove the owner, preview, and peer paths. User coop verification on 2026-07-13 confirmed peer sync after swaps, per-instance persistence across game exit, inventory-preview parity, and client leave/rejoin reconstruction. The join retry is local paint only, capped at 40 attempts/10 seconds, with zero new RPC channels. |
| Tracking | GitHub issue #574. |

### score-lineup-snapshot-peer-resolution -- local and remote LA hats

| Field | Value |
|-------|-------|
| Symptom | End-of-mission lineup shows each LA hat's original vanilla hat for both wearer and client. |
| Root cause | TeamPreviewer first ran after `PlayerManager:remove_player`, so it needed the score snapshot. The initial snapshot resolver then treated `peer_id` as wearer identity even though bot score rows reuse their owning host's peer, allowing the host's LA store to bleed across careers. The spawn monitor made the inverse mistake and purged the host's valid store when a host-owned bot had a different skeleton. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.9.91-dev (snapshot source), v0.9.95-dev (player-controlled wearer boundary) |
| Category | INTEGRATION / MULTIPLAYER |
| Repro | Two modded peers equip LA hats, finish a mission, and inspect local plus remote lineup rows. |
| Expected post-fix | Human rows resolve from `score_snapshot`; their previewer hats swap/paint before display. Bot rows sharing a host peer remain vanilla, cannot read the host's LA store, and cannot purge it when their skeleton differs. |
| Detection | `/cos_regression_test` passes `cos_la_score_screen_apply_wired`. Log has bounded `BOT-OWNER-ALIAS retained`, human `SCORE-ROW role=local/remote ... source=score_snapshot` followed by `SCORE-HAT` markers, and bot rows as `role=bot source=score_snapshot_bot peer=nil` with no subsequent bot hat swap. |
| Tracking | GitHub issue #513. |

### offhand-preload-async-bounded -- no blocking startup package storm

| Field | Value |
|-------|-------|
| Symptom | Startup performs dozens of Cosmetics-owned synchronous package loads and stalls `Application::update` for about 1.58 seconds. |
| Root cause | Bulk offhand preloading retained a synchronous workaround after the 1P+3P `Application.can_get` readiness gate made early override exposure safe. Follow-up: vanilla retains our callback on a shared in-flight handle after our reference unloads, so an unguarded callback could repopulate cleared readiness state. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.9.90-dev (async conversion), v0.9.96-dev (generation-scoped unload callback) |
| Category | INTEGRATION |
| Repro | Start VT2 with package debugging enabled and count `cosmetics_tweaker, sync-read` lines before the first keep frame. |
| Expected post-fix | Offhand packages are queued as `async-read`; an unready override falls back to the base mesh; unload balances every `cosmetics_tweaker_offhand` reference; a callback retained by another owner after unload is rejected by its stale generation token. |
| Detection | `/cos_regression_test` passes `offhand_preload_async_bounded_565`; offline lifecycle tests pass; startup contains `[cos:565] offhand bulk preload queued mode=async` and no Cosmetics-owned bulk `sync-read` storm. Shutdown prints one lifecycle summary. Any late callback is ignored and detailed rows are capped at 4. |
| Tracking | GitHub issue #565. |

### white-glow-unregistered-fallback -- do not require vanilla's missing template

| Field | Value |
|-------|-------|
| Symptom | `/cos_regression_test` always reports `material_settings_templates_loaded -- missing weapon mat templates: white_glow`. |
| Root cause | Vanilla's Morris skin catalog contains one `white_glow` referrer, but `weapon_material_settings_templates.lua` registers only the other eight weapon template families. The suite incorrectly treated referrer names and registered template names as the same set. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.9.89-dev |
| Category | INTEGRATION |
| Repro | Run `/cos_regression_test` in the keep on an unmodified current game data set. |
| Expected post-fix | `material_settings_templates_loaded` passes, still checks every registered vanilla weapon template, and separately locks the lone Nornaz skin's `white_glow` fallback mapping. |
| Detection | `/cos_regression_test`; inspect `material_settings_templates_loaded`. |
| Tracking | GitHub issue #566. |

## Chaos Wastes integration

### la-deus-yield-active-mission-only — Pilgrimage Chamber must retain LA weapons

| Field | Value |
|-------|-------|
| Symptom | A recalled LA weapon cosmetic is visible in inventory/customization previews but disappears from the live weapon after entering Pilgrimage Chamber. |
| Root cause | The weapon precedence gate treated mechanism `deus` as synonymous with an active expedition. Vanilla uses that mechanism for `inn_deus` (Pilgrimage Chamber), `map_deus` (route/shrine map), and `deus` (actual mission). |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.9.88-dev |
| Category | INTEGRATION |
| Repro | Equip an LA cosmetic on Spear and Shield in the keep; enter `morris_hub`; then begin an expedition and upgrade the weapon. |
| Expected post-fix | LA remains on the live weapon in Pilgrimage Chamber; the rolled/upgraded Chaos Wastes skin wins in an expedition mission; LA reasserts in a hub without losing saved or synced state. |
| Detection | `/cos_regression_test` passes `cos_la_deus_yield_active_mission_only`; staging log contains one `[la-state] DEUS-YIELD bypass mechanism=deus game_mode=inn_deus` marker; no `DEUS-YIELD suppressed` marker occurs until game mode `deus`. |
| Tracking | GitHub issue #518. |


---
## Multiplayer / Network Sync

### la-hat-cross-skeleton-leak — LA hat cached for one career attaches to a different character's body at mission start

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Host sees an LA hat equipped on a teammate's body that belongs to a different character (e.g. GK Pureheart helm shows up on Warrior Priest at mission start). Client view is unaffected. Often a host-owned bot whose career differs from the host's. |
| Root cause | `_apply_la_on_unit`'s character-mismatch guard derived `owner_char_path` from the cached LA emit's `vanilla_key` instead of the actual `owner_unit`. Both `vanilla_key.unit` and `la_unit_path` resolved to the emitter's character, so the mismatch comparison was a tautology. When `_wearer_unit_for_peer` happened to return the WP bot (host owns multiple player_units), the LA mesh attached to the wrong skeleton. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.9.11-dev (guard rewritten to source `owner_char_path` from the unit's actual existing slot_hat, with SPProfiles fallback); v0.9.13-dev (extracted to pure helper `_la_chars_compatible` + behavioral tests + runtime spawn-monitor); v0.9.95-dev (bot mismatch cannot purge human-owner state). |
| Category | INTEGRATION |
| Repro | 1. Host equips an LA hat on Grail Knight (or any career). 2. Lobby has a teammate (bot or remote player) whose career differs from the host's, e.g. Warrior Priest. 3. Host starts a mission. 4. Without fix: GK LA hat may attach to WP body on host's view. |
| Expected post-fix | LA hat stays on the host's GK body. WP body wears its vanilla WP hat. The mismatch guard logs and skips the cross-skeleton patch. A host-owned bot may produce `CROSS-SKELETON MISMATCH` plus `BOT-OWNER-ALIAS retained`; that is expected evidence that the host store was preserved, not a failed attach. |
| Detection | (a) `/cos_regression_test` passes the `la_chars_compatible_*` checks and `cos_la_score_screen_apply_wired`. (b) A bot mismatch must be paired with `BOT-OWNER-ALIAS retained`; no bot receives a mesh swap. (c) Manual: equip an LA hat on GK, start a mission with a WP bot, and confirm GK keeps the LA hat while WP remains vanilla through the score lineup. |
| Tracking | GitHub issue #14. |


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


---

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


---

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


---

### mh-package-refcount-leak — MH embed accumulated one package reference per hijacked wield, never released

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Shutdown: ~20 `Package still referenced, NOT unloaded` lines then crashify `'#ID[...]' not unloaded, this can potentially cause an deadlock` on BOTH peers; in-mission `Locking a resource that is about to be unloaded!` at map transitions. 92 loads of one `_3p` package in a single host session. |
| Root cause | `_safe_load_package` called `Managers.package:load(path, "global")` on every replace_textures/add_particles event. `PackageManager.load` increments a per-(package, reference_name) count on EVERY call (package_manager.lua:26-27); nothing ever called unload. Same shape (slower): LootItemUnitPreviewer parent-package refs taken per browser open, never released. |
| Mod(s) | cosmetics_tweaker (issue 282 cosmetics-owned slice; wt/cwv audit still open) |
| Fix version(s) | cosmetics_tweaker v0.9.76-dev (dedupe registry + mod-owned ref `cosmetics_tweaker_mh` + release on StateIngame exit / mod unload / previewer destroy) |
| Category | UNIT + MANUAL |
| Repro | 1. Equip a hijacked-material weapon (e.g. CWV custom musket). 2. Wield it repeatedly (10+ swaps). 3. Exit to keep, quit the game. 4. Without fix: repeated `[PackageManager] Load` refs and the shutdown crashify block. |
| Expected post-fix | ONE `[cos:282] first-load` line per package per level, `[cos:282] dedupe-skip` on later wields, `[cos:282] unload` at keep/mission exit; no crashify `not unloaded` block at shutdown. |
| Detection | (a) `/cos_regression_test` — `mh_package_single_reference` must pass. (b) Console log greps above. |
| Tracking | GitHub issue #282 (stays open for wt/cwv). |


---

### ct-skin-wire-senders — ct_* illusion key must be nulled on EVERY vanilla skin sender, not just initial spawn

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Peers WITHOUT cosmetics_tweaker CTD (strict `NetworkLookup.weapon_skins` `__index` fatal, network_lookup.lua:2362) when a cosmetics user applies/wears a ct_* illusion — on mission spawn, on mid-session equip, or when hot-joining the lobby. |
| Root cause | Vanilla encodes `weapon_skin_id = NetworkLookup.weapon_skins[<live slot skin>]` on THREE senders: `SimpleInventoryExtension.game_object_initialized` (:259), `._spawn_resynced_loadout` (:1451, the mid-session equip path), `GearUtils.hot_join_sync` (gear_utils.lua:484). Plus the player_sync_data GameSession axis via `CosmeticUtils.update_cosmetic_slot` (cosmetic_utils.lua:205-251). v0.9.74 covered only the first. |
| Mod(s) | cosmetics_tweaker |
| Fix version(s) | cosmetics_tweaker v0.9.74-dev (goi), v0.9.76-dev (resync + hot-join + sync-data axes) |
| Category | UNIT + MULTIPLAYER MANUAL |
| Repro | 1. Cosmetics user equips `ct_es_mace_gk_shield_01` (or a heavy-spear deus illusion). 2. A NON-mod peer is in the lobby (or hot-joins). 3. Spawn into mission, then ALSO re-apply the illusion mid-session. |
| Expected post-fix | Non-mod peer never crashes on any of the three events; owner keeps the custom visual locally; `[cos:421] wire skin null (<surface>)` logs on each send. |
| Detection | (a) `/cos_regression_test` — `wire_skin_null_ungated` + `wire_skin_null_all_senders` must pass. (b) 2-player manual per Repro. |
| Tracking | GitHub issue #421 (refs issue 371 / BUG_CLASSES 31). |


---

## Cosmetics / LA / CWV / Engine Bugs

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


---

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


---

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


---

### la-magic-shield-paint-receiver — LA heraldry invisible on Weavebound/Shyish shields

| Field | Value |
|-------|-------|
| Symptom | Loremasters shield options are selectable on a Weavebound or Shyish shield, but every option still looks like the original magic shield. |
| Root cause | The dedicated magic shield unit does not expose LA's standard diffuse slot; the texture API reports success without changing visible pixels. |
| Mod(s) | cosmetics_tweaker, Loremasters-Armoury |
| Fix version(s) | pending (#373) |
| Category | INTEGRATION |
| Repro | Equip an Empire, Bretonnian, or Spear+Shield Weavebound/Shyish illusion, select a same-family LA texture shield, and leave the customization screen. |
| Expected post-fix | The magic unit is replaced once with its exact same-family non-magic paint receiver, then LA heraldry is visible on owner preview/body and remote husk. Breton and Empire textures never cross families. |
| Detection | `qa/lua/tests/test_cos_la_shield_parity.lua` locks the exact receiver allow-list and cross-family rejection; verify visually with two players. |


---

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


---

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


---

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

- ct-husk-hook-shadow-tpe
- ct-offhand-force-preload
- ct-skin-wire-senders
- cwv-backend-id-lookup
- feedback-deploy-vs-upload-distinction
- feedback-mod-version-format
- feedback-pre-deploy-checklist
- feedback-redundant-safeguards-ok
- feedback-search-changelog-for-known-crashes
- feedback-vmf-hook-safe-no-chain
- feedback-workshop-upload-verify
- feedback-workshop-upload-without-deploy
- gated-registration-divergence
- la-custom-mesh-unsupported
- la-hat-kind-texture-needs-paint
- la-icon-key-vs-item-type
- la-kind-unit-pipeline
- la-offhand-paint-pipeline
- loot-previewer-hook-not-safe
- lua-forward-reference
- mh-package-refcount-leak
- preview-slot-keying
- ps5-getcontent-utf8
- ugc-tool-forward-slashes
- ugc-tool-pushes-all-cfg-fields
- vmblauncher-handscaffold-first-upload
- vmf-custom-gui-textures
- vmf-dropdown-options-mutated
- vmf-network-send-recipients
- vmf-renderer-creator-keys
- vmf-widget-id-unique
- vt2-chat-command-syntax
- vt2-class-hook-derived
- vt2-force-load-only-listed-paths
- vt2-hash-reverse-lookup
- vt2-husk-extension-class-pair
- vt2-husk-rpc-race
- vt2-mod-command-inventory
- vt2-player-unit-field
