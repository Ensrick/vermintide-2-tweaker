# Cosmetics Tweaker — Development Notes

Detailed technical reference for the `cosmetics_tweaker` mod. Read alongside `CHANGELOG.md` (version-by-version history) and `TODO.md` (open work).

## Module map (#1159 structural phase complete)

`cosmetics_tweaker.lua` is the composition root ratcheted by
`qa/decomposition_contracts.psd1`. The bounded #1159 sequence extracted render,
glow, wire, lifecycle, replay, transport, offhand catalog/picker/state/apply,
preview, equipment, attachment, spawn, local/remote wield, item-presentation,
diagnostic, and scheduler owners without changing their engine registration
order. The final slice moved exact-instance offhand state restoration and local
paint gating into dedicated owners, separated read-only offhand/glow diagnostics,
and isolated the Deus mission-only precedence policy. At 1,494 nonblank lines and
37 required owners, Cosmetics now satisfies the 1,500-line structural-completion
target. Future changes must preserve or reduce that ceiling; behavior and
cross-surface appearance completeness remain governed by their own issues and
tests rather than inferred from file size alone.

**Shared namespace `mod._cos`** (the event_tweaker `mod._evt` pattern,
PROJECT_STANDARDS § 2.2a) carries cross-module state. It is created in the entry
manifest (just after the `_flush_log` helper) and populated with the handles the
`_cos_*` modules consume BEFORE they are `mod:dofile`'d: `U` (the `_cosmetic_unlocks`
map), `LA_BRIDGE`, `flush_log`, `skin_requires_unowned_dlc`, `custom_skin_keys`
(shared with the wire-safety senders + regression suite), `custom_illusions` (shared
with the offhand force-loader), and `apply_cosmetic_unlocks` (exported by the unlocks
module for the entry's lifecycle callbacks). Phase 2 added `is_unit`, `scale_units`,
`offset_units`, and `apply_unit_path_scale_hand` (exported by `_cos_render`). #420
adds one entry-created `weapon_appearance` instance that `_cos_render` captures;
the equipment and preview owners call the apply helpers via `mod._cos.*`, and the
entry keeps an `is_unit` alias injected into the offhand-apply and glow-probe owners. Phase 3 added
`apply_glow_override` and `glow_owner_peer_for_unit` (exported by `_cos_glow`): the same
three render hooks call them via `mod._cos.*` for the per-equip glow paint. `_cos_glow`
also owns the init of the `mod._glow_by_peer` per-peer cache and the
`mod._unit_to_backend_id` weak map. `_cos_glow_transport` receives the same
`mod._glow_by_peer` table through an explicit install dependency; the entry keeps
its alias for the shared remote-husk wield owner.
`mod:dofile` is NOT a singleton, so modules never dofile each other — each is dofile'd
exactly once from the manifest.

| Module | Owns / public surface (on `mod._cos` unless noted) |
|---|---|
| `cosmetics_tweaker.lua` (entry) | Composition root: MOD_VERSION (launcher parses it here — never move it), load banner/echo, embed manifest, shared `mod._cos` namespace, ordered owner installation, remaining live render adapters, and #282 MH session-residency diagnostics. Its 1,494-line ceiling is the completed structural-phase ratchet. |
| `_cos_mod_lifecycle.lua` | Idempotent owner of the existing `on_game_state_changed`, `on_disabled`, and `on_unload` callbacks. Preserves transition telemetry, bounded LA/glow/replay arming, TPE/LA disable cleanup, and offhand-package unload order. It receives the four earlier entry locals explicitly and adds no hook, RPC, update loop, or persistence surface. |
| `_cos_la_replay_runtime.lua` | Idempotent #660 owner of the bounded Loremaster appearance-replay coordinator. Owns the replay state initialization plus `apply`/`on_edge` status and invalidation routing at the historical post-`_la_reconcile`, pre-RPC position. It receives the pure replay policy and five existing runtime dependencies explicitly and adds no hook, RPC, update loop, lifecycle callback, persistence write, or renderer mutation. |
| `_cos_glow_transport.lua` | Idempotent host-authoritative per-peer glow transport/replay owner. Owns the existing `cos_glow_apply_req` / `cos_glow_apply` registrations, coalesced local publisher, bounded material-only rehydrate queue, and hot-join replay helpers at their historical post-LA-RPC, pre-husk-wield position. It adds no hook, lifecycle callback, persistence write, or material mutation; the frame scheduler's existing `mod.update`, hot-join, picker, and shared husk hooks consume its stable `mod._*` functions. |
| `_cos_update_scheduler.lua` | #1159 single VMF frame owner. Owns the historical `mod.update` action order: rewield drain, authored-registration retries, transition replay, persistence pruning, local scan/probes, bounded `cos_la_state_req`, peer purge, TPE/glow convergence, and the LA pending-apply drain. It registers no hook, RPC receiver, command, or lifecycle callback. The existing state pull remains five-second/eight-attempt bounded and every material/transition retry stays network-silent. `_la_bridge_init_done` and `_la_pending_apply` remain entry locals and cross through getter/setter pairs because this owner rebinds both. Reinstall refreshes action-time dependencies while retaining one stable update function. |
| `_cos_item_presentation_runtime.lua` | #1159 engine-facing exact-instance item-card owner. Phase 1 owns icon/name/description resolution and the single `UIUtils.get_ui_information_from_item` hook; Phase 2 installs the contextual Hold-Tab peer-cache adapter only after LA receivers exist. It preserves all four vanilla returns, keeps provider icons local, and refreshes action-time dependency bags on reinstall. The pure descriptor policy remains in `_cos_item_presentation.lua`; this owner adds no RPC, command, lifecycle/update callback, persistence write, equipment spawn, material mutation, or package load. |
| `_cos_spawn_boundary.lua` | #1159 ordered attachment/preview spawn owner. Owns the optional-headpiece `Application.can_get` gate, attachment-link policy installation, low-level `World.link_unit` LA queue, and the combined Hero/Menu `_spawn_item_unit` hook. One hook preserves MH-before-vanilla and authored-surface/glow-identity/LA-queue/score-paint-after-vanilla order. It refreshes action-time dependencies without duplicate registration and adds no RPC, command, lifecycle/update callback, persistence write, or package load. |
| `_cos_moonfire_puff_runtime.lua` | #1159 cosmetic projectile-impact owner. Owns the existing conditional six-method Unit/Husk Moonfire hit surface, exact `we_deus_01*` classifier, setting gate, and yield to Tweaker: Weapons' AOE revert. Reinstall refreshes the particle and mod dependencies without duplicating hooks; it adds no gameplay damage, RPC, command, lifecycle/update callback, persistence write, or package load. |
| `_cos_offhand_catalog.lua` | Idempotent independent-offhand catalog/package owner. Owns the #565 PackageManager reference lifecycle, authored mesh/readiness and inventory-icon resolvers, static shield/dual catalogs, lazy CWV pool discovery, and deferred all-pool preload implementation. It adds no hook, RPC, command, lifecycle/update callback, persistence/session state, UI, render, or LA-merge behavior; the entry consumes its returned function/data bag at the historical pre-session-state seam. |
| `_cos_offhand_state_runtime.lua` | Exact-instance offhand catalog-state owner. Owns one-shot LA merge, bounded persisted restoration, lazy pool lookup, and receiver-side dual-unit validation over the canonical option/selection tables. It adds no hook, RPC, command, lifecycle/update callback, or render mutation. |
| `_cos_offhand_apply_runtime.lua` | Shared authored-offhand local render transaction for live equipment, hero preview, and illusion preview. Owns item-type resolution, spawned-mesh validation, Cosmetics/LA material dispatch, customization suppression, and Deus yield. The mesh gate and paint cannot be split across adapters. |
| `_cos_offhand_diagnostics.lua` | Read-only `/la_offhand_dump` and `/offhand_debug` owner. It reports bridge resolution, pool/selection state, and engine-surface availability without mutation. |
| `_cos_glow_diagnostics_runtime.lua` | Bounded #574 log evidence plus `/glow_status` and `/glow_trace`. Two-phase installation exposes the logger early while retaining the commands' historical registration position. |
| `_cos_deus_yield_policy.lua` | Weapon-only Chaos Wastes precedence owner. Keep-instance authored cosmetics yield to rolled Deus skins only in active `deus` mission nodes; `inn_deus` and `map_deus` remain live. |
| `_cos_diag_deus_yield.lua` | Bounded issue-owned evidence for that precedence boundary. It preserves the `[cos:518]` engine-log receipt family and exposes owner-wield, local paint-skip, and remote husk-miss emitters. Each channel deduplicates and stops after 16 records; the module adds no hook, RPC, command, chat output, persistence write, or renderer mutation. |
| `_cos_la_gate_recovery.lua` | Bounded-lease recovery owner for fail-closed LA preview refusals (#481, cwv #474 donor recipe). One printf marker per (gate, key) names the refusing gate; at most one session lease per declared vanilla parent package (`units/weapons/player/...` prefix enforced structurally); mod-bundled/third-party owners are never leased. Consumed by `_la_bridge.lua` (exported as `M.gate_recovery`) and `_cos_cim_preview.lua`. |
| `_cos_la_prespawn_lease.lua` | #696 path-1 pre-spawn parent-package lease, pure factory. Static map of the five #940-traced LA unit paths (message board, back board, visible quest letter, Kruber shield02 1p/3p) to their declared vanilla parent material packages (Breton black_and_gold skin package per `cosmetics_lake.lua:36`; per-unit `units/weapons/player/...` shield donors). One bounded session lease per package at the all-mods-loaded edge, LA-gated, `can_get`-preflighted; the spawn seam records per-path residency once ([cos:696] receipts, cap 24). Owned/instantiated by `_material_hijack_embedded.lua` (exported as `prespawn_lease`); offline: `test_cos_la_prespawn_lease.lua`. |
| `_cos_glow_surface_policy.lua` | #1147 pure surface-glow policy (a #660 descriptor consumer). Engine-free wearer-payload resolution (transported `_glow_by_peer` state first, live local active payload for the local wearer's pre-echo window), the per-item glow paint math (moved verbatim from `_cos_glow.lua` with an injected write primitive so the offline suite drives the real repaint), the surface repaint executor, and the painted-mesh postcondition classifier (success is a NAMED glow-capable mesh, never call completion). Consumed by `_cos_glow.lua`; offline: `test_cos_glow_surface_policy.lua`. |
| `_cos_offhand_picker.lua` | Idempotent weapon-customization offhand picker owner. Owns the existing magic-family filter; offhand row setup; hover/input/draw hooks; exact selected-primary resolver; and `_ct_on_offhand_pressed` class method. Its engine tables are action-time getters. It adds no RPC, command, lifecycle/update callback, durable persistence, render hook, package catalog, exit commit/revert, or LA pool merge. |
| `_cos_preview_runtime.lua` | Idempotent preview presentation owner. Owns the 12 existing MenuWorldPreviewer/HeroPreviewer equipment and spawn, TeamPreviewer score-lineup, LootItemUnitPreviewer package/spawn/lifecycle, and adjacent authored-outfit attachment replay hooks in exact historical order. It exports the stable score peer resolver through its owner bag. A persistent holder refreshes all 17 injected LA/glow/score/CIM/helper dependencies before the reinstall guard; callbacks read the current shared `mod._cos` consumer map. Ordinary previews resolve action-time customization identity; a `cim_preview` marker never consults that generic fallback or the ordinary 2.0 scale path. It adds no RPC, command, persistence write, update-loop owner, or husk hook. |
| `_cos_cim_preview.lua` + `_cos_cim_preview_wiring.lua` | Engine-free #481 adapter plus its hook-free engine/dependency composition. It admits only the exact scoped backend/item/type/skin and current Loremaster hand-pool selection, requires the exact 3P unit to be resident, takes a per-previewer ref only on an already-loaded known parent material package, pairs returned units with `spawn_data`, and retries the existing guarded material adapter within one bounded generation/deadline. Timeout, missing/foreign/stale identity, destroy, and provider absence retain the resident compiled/base presentation. It registers no hook, loads no absent package, uses no raw native setter, and sends/persists nothing. |
| `_cos_news_feed_safety.lua` | Idempotent stale-news-widget containment owner. Owns the single existing `NewsFeedUI.draw` origin hook, preserves vanilla pass and active-news order, closes the pass before descending purge/recycle, and retains the historical five-purge diagnostic threshold. A persistent holder refreshes its renderer getter and logger before the reinstall guard. It adds no RPC, command, lifecycle/update callback, persistence, or appearance behavior. |
| `_cos_glow_picker_host.lua` | Idempotent host-window adapter for the existing `_glow_picker.lua` subsystem. Owns exactly five `HeroWindowCosmeticsLoadout` / `HeroWindowItemCustomization` input, draw, and exit hooks plus `/glow_picker_hooks` and `/glow_picker`, preserving their historical registration position. Hot reload refreshes injected picker, logger, version, and wielded-unit resolver dependencies without adding another registration. It owns no RPC, update loop, persistence, material mutation, or picker state machine. |
| `_cos_local_wield_runtime.lua` | Idempotent local-player wield appearance owner. Owns the single `SimpleInventoryExtension._wield_slot` hook that replays stored LA offhand state, restores and binds exact-item glow state, updates the active glow identity, and repaints the already-spawned local weapon units. It rejects remote units before mutation and adds no RPC, command, lifecycle/update callback, persistence write, or remote-husk behavior. |
| `_cos_la_husk_identity_runtime.lua` | Idempotent remote-husk identity/spawn owner. Owns wearer resolution, human/bot career validation, LA variant lookup, stale peer-slot cleanup, mission-world lookup, wielded-item matching, the bounded LA spawn monitor, the read-only mission-state dump, and the single `SimpleHuskInventoryExtension.init` hook. It refreshes dependencies without duplicate registration and adds no RPC, persistence, UI, or material writer. |
| `_cos_husk_wield_runtime.lua` | Idempotent remote weapon-wield transaction owner. Owns the single `SimpleHuskInventoryExtension._wield_slot` hook, publishes a stack-style current-wield accessor for equipment assembly, restores context across normal and error returns, preserves eight vanilla returns, and then performs existing glow binding/repaint/rehydrate and LA reconcile in order. It adds no RPC, command, lifecycle/update callback, persistence write, or package load. |
| `_cos_command_owner.lua` | Single #504 command-lifecycle owner. Owns the lazy regression registry and `/cos_regression_test` runner plus `/cos_persist_dump`, `/cos_persist_replay`, and `/cos_persist_clear`. Returns the register function consumed by `_cos_runtime_checks.lua`; repeated install is idempotent. It owns no hook, RPC, renderer, or lifecycle callback. |
| `_cos_glow_editor_button.lua` | Idempotent #377/#504 contextual Edit Glow button owner. Owns family/open-state policy binding, enabled/selected styling, and widget construction. The host customization view retains position, input, and draw ownership; this module adds no hook, RPC, polling, persistence, or renderer mutation. |
| `_cos_item_grid_presentation.lua` | Idempotent #377/#650/#795 item-grid and illusion-card presentation owner. Owns the single pre-`pass_data` `UIWidget.init` enrichment hook, the three existing `ItemGridUI` refresh hooks, weak live-surface registries, and the committed glow/composite refresh callback. It receives the existing policies and late-bound composed-appearance resolver; it adds no lifecycle callback, RPC, persistence, or appearance semantics. |
| `_cos_runtime_checks.lua` | Registers the 61 late runtime checks in historical order plus the single `/verify_gk_set` command. `issue420_shared_weapon_appearance_owner` proves the exact instance retained by `mod._cos` exposes the shared apply contract. Receives every entry-private table/helper through one explicit dependency table; closures remain lazy so live state is inspected only when the registry runs. It owns no hooks, RPCs, or lifecycle callback. |
| `_cos_diag_glow.lua` | Owns `/glow_dump`, `/glow_probe`, `/glow_scan`, `/glow_scan_stop`, `/glow_restore`, `/la_shield_glow_probe`, both bounded scan tick functions, and the exported `wielded_units_for_probe` helper consumed by the later manual picker command. It receives only player-safety, unit-liveness, and log-flush helpers. |
| `_cos_la_commands.lua` | Owns the read-only LA diagnostic commands `/la_dump`, `/la_trace`, `/la_force`, `/la_attach`, `/la_loadout`, and `/la_hats`. Captures the already-loaded bridge plus career/log helpers; no hook or lifecycle ownership. |
| `_cos_diagnostics.lua` | Read-only dump/probe chat commands (`/flush_log`, `/dump_glows`, `/dump_skin_rarities`, `/dump_all_names`, `/check_vmf`, `/probe_hat`, `/probe_cosmetics`, `/cos_421_diag`). The #421 command reports custom-key catalog symmetry, the four wire-surface registrations, the pure substitution/restore proofs, and whether the live repro actually has a custom skin equipped. Reads `mod._cos.flush_log`; no exports. |
| `_cos_illusions.lua` | Custom weapon-illusion + LA shield skin injection into `ItemMasterList`/`WeaponSkins`/`NetworkLookup` (`_custom_illusions`, `_la_shield_skin_specs`), the `get_unlocked_weapon_skins` unlock hook, the `_G.Localize` display-name hook. Populates `mod._cos.custom_skin_keys`; exports `mod._cos.custom_illusions`. |
| `_cos_unlocks.lua` | Per-career cosmetic unlocks (`apply_cosmetic_unlocks` + `_CHARACTER_CAREERS`), Unlock-All portrait frames, vanilla-unobtainable cosmetic grants, the two `PlayFabMirrorAdventure` hooks, `/frames_status` + `/cosmetics_status`. Exports `mod._cos.apply_cosmetic_unlocks`. |
| `_cos_render.lua` | Render-path weapon scale/grip apply layer: the two visual-override data tables (`_unit_path_scale_overrides` + `_breton_sword_thiccc`, empty `_weapon_grip_offsets`) and the resolve/apply helpers (`_resolve_for_career`, `_resolve_render_unit_path`, `_resolve_factor`, `_apply_unit_path_scale_hand`, `_scale_units`, `_offset_units`), plus the `_is_unit` liveness primitive. #420 captures the one entry-installed Cosmetics-local `WeaponAppearance` instance and delegates ordinary one-shot scale/offset composition to it. Exports `mod._cos.{is_unit, scale_units, offset_units, apply_unit_path_scale_hand}`; identity, hand, renderer, hook, and lifecycle policy remain Cosmetics-owned in the equipment/preview owners. |
| `_cos_glow.lua` | Weapon glow APPLY subsystem (v0.9.79-dev Phase 3): the `_COLOR_PRESETS` table, shader-variable maps, per-peer cache reads, `_apply_glow_override`, and the #650 descriptor-only `_apply_composed_shield_glow` adapter. Captures `mod._cos.is_unit`; owns the unit/backend cache and exports `mod._cos.{apply_glow_override, apply_composed_shield_glow, glow_owner_peer_for_unit}`. Render hooks and diagnostics remain in the entry; `_cos_glow_transport.lua` owns the RPC publisher/replay boundary. |
| `_cos_glow_badge_policy.lua` | Pure #377 presentation policy: active committed-state classification, clamped rune RGB, deterministic intensity-weighted magic blend, and family-scoped manual-button availability. No engine globals, persistence writes, hooks, or networking. |
| `_cos_la_option_icon_policy.lua` | Pure #923 target-qualified LA option policy. Creates immutable per-item-type option records, resolves only the exact live skin's provider icon, indexes restart restoration by item type + hand + Armoury key, and fails closed to the native icon. Provider icon names remain local and are never persisted or synchronized. |
| `_cos_glow_panel_layout.lua` | Pure #377 Information-panel host adapter. Resolves the live vanilla `info_window`, constructs the shared ornate frame styles, positions the persistent toggle locally, owns panel hit testing, and transactionally suppresses/restores only `_info_widgets` around the native overview draw. It fails closed on malformed geometry and contains no engine globals. |
| `_cos_glow_cim_bridge.lua` | Pure #48 optional-persistence policy. Sanitizes one bounded versioned exact-item+illusion blob, prefers `cim_dev` over `cim`, calls only CIM's public exact-craft APIs, imports only on a Cosmetics-local miss, and clears only an identity-matched blob. CIM never renders or interprets glow. |
| `_cos_magic_skin_gateway.lua` | Pure #48 illusion-grid visibility policy. Weavebound and Shyish families remain hidden by default, the exact equipped skin remains visible, and the explicit default-off gateway reveals both families without altering vanilla row geometry so selection can hand off to Edit Glow. |
| `_cos_modded_illusion_swap.lua` | Single #504 owner for the eight modded-realm illusion selection/crafting/completion hooks and their private fake-id/pending-request state. It yields the bypass to CIM at fire time, remains idempotent on repeated install, and keeps the malformed local-craft completion guard beside the request producer. |
| `_cos_composite_icon_catalog.lua` / `_cos_composite_icons.lua` | #650 exact-instance composed appearance catalog and descriptor/cache/cell policy. A descriptor owns primary/offhand icon layers plus the compatible shield's effective glow material write; held rendering and item-card tint consume the same RGB. Renderer residency is an icon-adapter concern and cannot suppress held appearance. The module also owns weak publication and bounded telemetry to preserve the Lua 5.1 entry limit. Crafting and Hold-Tab remain pending adapters. |
| `_cos_custom_hats.lua` | Authored hat registry (#612): stable item/backend identity, custom-unit resolver, default-enabled availability toggle, and vanilla peer fallback metadata. It reuses the shared bounded appearance registry but remains independent of Loremaster's Armoury installation. |
| `_cos_attachment_link_policy.lua` | #950 attachment-link owner with an engine-independent node-map partition policy. It preserves valid source/target pairs, reports absent optional pairs, accepts numeric engine indices, and installs the guarded wrapper without globally cancelling compatible custom attachments. |
| `_cos_attachment_spawn_sync.lua` | #1159 attachment-slot LA spawn/sync owner. Owns the four engine seams that spawn or synchronise an attachment-category cosmetic onto a player body: `PlayerHuskAttachmentExtension.create_attachment`, `PlayerUnitAttachmentExtension.game_object_initialized` and `.spawn_resynced_loadout`, and the plain-table `AttachmentUtils.hot_join_sync` (which also carries the non-attachment hot-join replay that rides the same seam). Each seam resolves the LA identity before vanilla and re-emits the LA apply after. `_la_pending_apply` arrives as a getter because the apply-runtime and frame-scheduler drains both rebind it; `_net_safe_hook_status` arrives by reference so the entry's startup verification still sees the two registration flags. It adds no RPC, command, lifecycle/update callback, persistence write, or UI hook. |
| `_cos_equipment_assembly.lua` | #1159 live equipment-assembly owner. Owns the two NESTED seams that build a body's equipment: `BackendUtils.get_item_units` (the one place the mod rewrites the unit table vanilla is about to spawn - #513 score-screen LA hat mesh, husk LA mesh swap incl. the #373 magic-shield paint receiver, #416 husk vanilla per-hand mesh, and the per-backend-id offhand selection override) and `GearUtils.create_equipment` (MH-embed textures/particles before vanilla, glow unit binding, scale, grip offset, LA offhand paint, Grail Knight shield variant, #574 glow rehydrate, composed-appearance glow). They travel as ONE owner because create_equipment sets `_in_create_equipment` around its vanilla call and get_item_units reads it (#150) - nothing else does, so the flag is now private to this module. #481 additionally consumes CIM's stack-scoped context at the synchronous `get_item_units` seam: only exact identity may enter `_cos_cim_preview`; a present but rejected scope never borrows the customization backend. `_current_husk_wield` and `_active_customization_backend_id` arrive as getters because their runtime owners rebind both. It adds no RPC, command, lifecycle/update callback, persistence write, or UI hook. |
| `_cos_la_apply_runtime.lua` | #1159 LA appearance apply/revert/reconcile owner. Owns the render side of a stored LA entry in both directions: the unified apply core `_apply_la_on_unit` (the terminal funnel every trigger runs through, hence the single #518 deus gate and #14 cross-skeleton guard, dispatching hat / armor / offhand / illusion), the post-spawn offhand mesh re-swap `_ensure_offhand_mesh`, the three revert primitives `mod._la_native_pulse` / `mod._la_restore_native_hat` / `mod._la_apply_revert_recv`, and the single render-reconcile entry point `mod._la_reconcile` (#264 I3). Apply and revert are ONE owner because `_offhand_reswap_state`, the per-owner pulse cooldown and try-cap table, is written by both sides. It registers NOTHING - no hook, command, RPC or dofile - which is why the move could not perturb hook order. `_la_pending_apply` arrives as a getter AND a SETTER (the only crossing needing both: the frame scheduler rebinds it in `mod.update`, this owner rebinds it in the revert purge); `_la_equips_by_peer` arrives by value on a single-assignment proof. The unused `_try_apply_by_peer` decomposition carry was retired in v0.9.208-dev (#1241). |
| `_cos_la_sync_transport.lua` | #1159 cos_la_* peer-sync transport owner. Owns the wire for LA appearance state end to end: the peer-identity layer (`_host_peer_id`, `_local_peer_id_quick`, `_is_local_server`, `_wearer_unit_for_peer`, `_local_player_peer_id`, `mod._la_career_for_unit`), the three senders (`_send_la_apply`, `mod._send_la_revert`, `mod._send_offhand_mesh`) sharing one 0.5s emit-dedup window and one 300s-TTL deferred queue (`mod._drain_deferred_la_emits`), the receiver-side vanilla mesh store `mod._store_offhand_mesh_recv`, all four `mod:network_register` handlers (`cos_la_apply_req`, `cos_la_state_req`, `cos_la_state_ack`, `cos_la_apply`) with host-authoritative validate/record/rebroadcast and the #416 hot-join replay, and the deferred peer purge (`PlayerManager.remove_player` / `add_remote_player` + `mod._la_tick_peer_purges`). Send and receive are ONE owner because `_last_emit_at` is written by all three senders AND swept by the purge tick, the queue is appended by all three and drained by one function that re-derives host identity, and the receivers call the senders' own store helper. It installs in TWO phases from one dofile - phase 1 (identity/send/queue, registration-free) at the former entry line 2378, phase 2 (`owner.install_receivers()`, the six registrations) at the former line 3192 - because the entry interleaves unrelated code between the halves, and phase 2 is a closure inside phase 1 so the receive half keeps the same lexical view it had in the entry. Phase 2 asserts it runs exactly once. `_la_pending_apply` arrives as a getter (the receiver appends, sibling owners rebind); `_la_equips_by_peer` and `_glow_by_peer` arrive by value on single-assignment proofs. It adds no RPC channel, command, lifecycle/update callback, persistence write, or UI hook. |
| `_cos_la_loadout_safety.lua` | #1159 LA loadout-state + vanilla-RPC net-safe sender owner. Answers one question: when the local player wears an LA (or Cosmetics-authored) cosmetic, what does the rest of the world see. Two inseparable halves. LOADOUT STATE: `_install_skin_loadout_safety` and its deferred hooks `BackendUtils.set_loadout_item` (the #520 user-intent chokepoint that caches the clone in `mod.loadout_cache` AND writes the authoritative persist, because `career_name` is an argument there) plus `get_loadout`, `get_loadout_item_id` and `get_item_rarity` on the "items" backend interface, the one-shot `_fixup_server_clones`, and the #520 disk rehydrate that makes an equipped LA hat survive a restart. The `get_loadout_item_id` hook carries the bot-loadout guard: `is_bot` must be forwarded and a bot must never read `mod.loadout_cache` (career+slot keyed, holds the LOCAL player's picks), or every bot clones the host's gear. WIRE SUBSTITUTION: the `CosmeticUtils.update_cosmetic_slot` and `LoadoutUtils.sync_loadout_slot` hooks, which substitute the vanilla equivalent for every outgoing vanilla encode and SKIP the call entirely when no fallback exists (crash GUID fa479a72: a locally-registered `NetworkLookup` index fatals a vanilla peer on decode). That substitution is UNCONDITIONAL and carries no settings read (issue 371 / BUG_CLASSES 31). One owner because the substitution hooks read the very cache the loadout hooks write, both resolve through the same `_la_vanilla_fallback`, and both maintain `_local_la_equips` for hot-join replay. It exports `_la_vanilla_fallback`, `_wire_career_for_player` and `_install_skin_loadout_safety` back to the entry as the same function objects their remaining consumers already resolved. `_send_la_apply` arrives as a GETTER (this owner installs ABOVE the entry's sender assignment); `_la_equips_by_peer` and `_local_la_equips` arrive by value on single-assignment proofs. It does NOT own `_net_safe_hook_status` or `_la_substitute_name` - both stay entry state, brokered to `_cos_attachment_spawn_sync`. It adds no RPC channel, command, lifecycle/update callback, or UI hook. |
| `_cos_grail_knight_set.lua` | Authored Purpure/Azure set registry (#629): vanilla-geometry item registration, exact per-instance material paint for hat/outfit/shield, independent offhand descriptor, and inventory-hero visibility replay. #658 adds its deterministic per-career `can_wield` policy: the set stays native to Grail Knight while default-off Mercenary/Huntsman/Foot Knight toggles only extend inventory availability. They do not relax #698's career-scoped peer appearance identity. |
| `_cos_wire.lua` | Phase 4a #421 weapon-skin wire boundary. Captures `mod._cos.custom_skin_keys` after `_cos_illusions`, exports the shared pure `mod._cos_wire_safe_custom_skin` policy, the exception-safe `mod._cos_wire_null_custom_skins` helper, and the `mod._cos_skin_wire_surfaces` registry. It owns the three vanilla `rpc_add_equipment` sender hooks (`SimpleInventoryExtension.game_object_initialized`, `SimpleInventoryExtension._spawn_resynced_loadout`, `GearUtils.hot_join_sync`); the entry module's existing `CosmeticUtils.update_cosmetic_slot` hook consumes the same policy for the fourth, GameSession, wire surface. Local slot state is restored even if the wrapped sender raises a Lua error. |
| `_cos_offhand_preload_lifecycle.lua` | Pure generation-scoped ownership/readiness ledger for #565 async offhand packages. It has no engine or mod dependencies so shared-handle callbacks retained after unload can be reproduced offline. `_cos_offhand_catalog.lua` owns all PackageManager calls and bounded diagnostics. |
| `_cos_offhand_session_state.lua` | Pure #504 exact-backend-item/per-hand customization-session owner. It owns pending selections, Apply baselines/markers, one-way legacy-shape migration, and clone-on-snapshot/restore. It deliberately owns no durable persistence, renderer, hook, or RPC; those existing consumers retain the same table identities through the entry aliases. |
| `_mh_package_lifecycle.lua` | Pure #282 process-session ownership ledger for embedded Material-Hijack skin packages. It loads exactly once per path, adopts an existing exact reference if the ledger is reinitialized, and exposes read-only held/reference summaries. This does not make Cosmetics hot reload safe. There is deliberately no mod-owned release API: native renderer retirement has no proven Lua boundary, so `PackageManager.destroy` is the sole release owner. |
| `_cos_offhand_names.lua` | Pure #641 component display-name policy: independent offhand-weapon/shield keys, deterministic source fallback, primary-first label composition, presentation-only decoration, and deduplicated inventory rows. |
| `_cos_la_instance_policy.lua` | Pure exact-item presentation policy for LA/Cosmetics components. Owns direct Armoury-key/bridge-clone icon identity, exact-skin-first authored icon lookup with representative cross-family fallback, backend fallback qualification, hand-pool ownership, and `spawn_data` target validation for Athanor/illusion previews; missing identity or mesh evidence fails closed. |
| `_cos_husk_identity.lua` | #698 career-scoped remote appearance policy plus the dependency-injected spawn-monitor owner. Creates career-stamped peer-store entries, requires exact active-career agreement, invalidates stale human records on career change, and preserves host-owned bots that merely alias the human's peer id. It owns no hooks, RPCs, or direct engine globals. |
| `_cos_weapon_pose_policy.lua` / `_cos_weapon_poses.lua` | #485 pure authored-pose catalog plus the local modded-realm SocialWheelUI adapter. Replaces only the gathered pose rows; never grants backend ownership or mutates ItemMasterList. Missing-parent fallback is bounded diagnostics pending compatibility proof. |
| `_la_shield_parity.lua` | Pure #266 availability policy: the single complete Kruber native/CWV shield item-type catalogue and its weapon-agnostic fan-out helper. `_la_bridge.lua` consumes it; it owns no render or engine surface. |

Pre-existing `_*.lua` modules (`_la_bridge`, `_material_hijack_embedded[_anim]`,
`_moreitemslibrary_embedded`, `_cosmetic_unlocks`, `_tpe`, `_glow_picker`,
`_la_persistence`, `_la_okri`, `_ui_dump`, `_cos_diag_lasync`, `_cos_offhand_preload_lifecycle`, `_la_shield_parity`, `_la_prefix_embedded`)
predate this split and are captured as entry locals by the top manifest — leave
their internals alone.

### Where new code goes

- **New layered weapon-icon family or glow style** -> add exact primary,
  offhand, and style mappings to `_cos_composite_icon_catalog.lua`; keep cache,
  fallback, and byte-color behavior in `_cos_composite_icons.lua`. A new UI
  surface is only an adapter and must prove exact/synchronized identity plus
  renderer-local materials before consuming the descriptor.

- **New item-grid or illusion-card glow/composite presentation adapter** ->
  `_cos_item_grid_presentation.lua`. Preserve its one pre-`pass_data`
  `UIWidget.init` owner and three `ItemGridUI` refresh hooks; do not add a
  second hook for the same class/method or move appearance resolution into the
  UI owner.

- **New mod-wide transition or teardown side effect** ->
  `_cos_mod_lifecycle.lua`. Preserve the single three-callback owner and the
  existing within-callback order; do not wrap or replace a callback elsewhere.
- **New per-peer glow payload, validation, or hot-join replay behavior** ->
  `_cos_glow_transport.lua`. Keep both RPC registrations together, preserve
  host authority and schema rejection, and keep the local rehydrate tick
  network-silent and bounded. Render/material behavior stays in `_cos_glow.lua`
  or `_cos_husk_wield_runtime.lua`.

- **New bounded per-frame coordination, deferred retry, or frame-order change** ->
  `_cos_update_scheduler.lua`. Preserve its single `mod.update` assignment,
  current action order, five-second/eight-attempt state-pull bound, and paired
  accessors for rebound bridge/queue state. Add no second update wrapper or RPC
  registration; feature-specific work stays in its existing owner and exposes a
  cheap bounded tick to this scheduler.

- **New independent shield/dual catalog row, CWV pool source, package-residency
  rule, authored offhand mesh resolver, or offhand inventory-icon lookup** ->
  `_cos_offhand_catalog.lua`. Preserve its idempotent installer and explicit
  dependencies; keep picker UI, render hooks, durable/session state, LA pool
  merge, RPC, and lifecycle/update callbacks in their existing owners.

- **New weapon-customization offhand row, cell interaction, hover/draw behavior,
  magic-family grid filter, or selected-primary picker rule** ->
  `_cos_offhand_picker.lua`. Preserve its two wrapping hooks, one safe hook,
  and one class-method assignment in historical order. Screen-exit commit/revert,
  LA pool merge, persistence, transport, and spawned-unit rendering stay outside.

- **New diagnostic dump/probe command** → `_cos_diagnostics.lua`. Route through
  engine `printf` / `mod:info` (users run with mod logs OFF), `_flush_log` at the end.
  Extend `_cos_diag_glow.lua` only for the existing wielded-material scan family,
  and `_cos_la_commands.lua` only for commands that directly inspect `LA_BRIDGE`.
- **New `/cos_regression_test` registration** → `_cos_runtime_checks.lua`. Add its
  dependency to the install table if it needs entry-private state; never make the
  module dofile another owner or eagerly snapshot runtime state.
- **Regression runner behavior or LA persistence maintenance commands** →
  `_cos_command_owner.lua`. Keep the four public command names and registration
  order stable; runtime assertions still belong in `_cos_runtime_checks.lua`.
- **New preview consumer of an independently selected shield/offhand** → resolve
  exact backend identity and current hand-pool ownership through
  `_cos_la_instance_policy.lua`, then pass the preview engine's queued unit path
  to its adapter. Never accept unreadable runtime unit metadata as proof and
  never repaint a row-2-owned component through a second whole-skin provider.
- **Preview equipment/spawn/score/package lifecycle behavior** →
  `_cos_preview_runtime.lua`. Preserve its 12-hook order, keep engine tables
  action-time late-bound, refresh all injected dependencies before its reinstall
  guard, and inject any mutable entry state through a getter.
- **News-feed stale-widget or draw-pass containment** →
  `_cos_news_feed_safety.lua`. Preserve its single origin hook, vanilla active-news
  iteration, action-time renderer lookup, balanced pass, post-pass descending purge,
  recycling behavior, and bounded diagnostics.
- **Glow-picker input/draw hosting or its two manual diagnostic commands** →
  `_cos_glow_picker_host.lua`. The picker state machine and widgets remain in
  `_glow_picker.lua`; preserve the five-hook/two-command cardinality and inject
  rebound dependencies through the owner's stable state.
- **Local-player appearance replay immediately after a wield-slot change** →
  `_cos_local_wield_runtime.lua`. Keep its early local-unit ownership check, its
  one `_wield_slot` hook, and its network-silent LA/glow replay. Remote husk replay
  belongs to the existing transport/husk owners, not this seam.
- **New custom illusion / weapon-skin or LA-shield injection** →
  `_cos_illusions.lua`. Register the key into `mod._cos.custom_skin_keys` so the
  wire-safety senders null it on the wire.
- **New hat/skin/frame unlock or backend-mirror grant** → `_cos_unlocks.lua`; walk the
  DLC three-places checklist (`mod._cos.skin_requires_unowned_dlc`) before any
  `_unlocked_*` write.
- **New authored hat with its own unit/materials** → `_cos_custom_hats.lua`. Register
  identity unconditionally, change only availability/rendering with settings, provide
  a vanilla wire fallback, and package every unit/material/texture/icon resource.
  Open cloth/plume cards require both an alpha-aware shader (`use_opacity_map = 1`)
  and reverse-facing geometry: standard backface culling does not make an alpha PNG
  two-sided. Do not decode a vanilla packed map into PBR channels by position alone;
  validate metallic/roughness statistics and pin every derived response map. Rigged
  custom attachments also need a same-name textual `.bones` source; the current SDK
  rejects inline `animation_blender_bones`. When a vanilla controller source is absent
  from the Mod Tools, retain the exact package-safe donor geometry and replace only its
  per-instance textures. Register newly linked player attachments through the shared
  complete-snapshot FadeSystem adapter; ordinary `AttachmentUtils.link` does not enroll
  hats in camera fade, and a partial `{hat}` snapshot can discard weapon membership. The complete reproducible
  Encarmine recipe lives in `tools/encarmine_asset_pipeline/README.md`.
- **New weapon-model scale or grip-offset override** → `_cos_render.lua`. Add a
  `_unit_path_scale_overrides` entry (keyed by unit-path substring) or a
  `_weapon_grip_offsets` entry (keyed by item name + career prefix); the equipment
  and preview owners already call `mod._cos.scale_units` / `.offset_units` at their
  existing seams, so no new call site is needed. Transform composition stays behind
  the captured shared primitive; do not restore private setters. Need a liveness
  check? use `mod._cos.is_unit`.
- **New glow color/shader-variable/preset or glow apply-path change** → `_cos_glow.lua`.
  Register a new variable in `_GLOW_VAR_BRIGHTNESS` (+ `_GLOW_GROUP_COLOR_SETTING` for a
  new component) per GLOW_SYSTEM §9; the three render hooks in the entry already call
  `mod._cos.apply_glow_override`, so no new call site is needed. Glow SYNC/RPC changes
  (per-peer `cos_glow_apply` broadcast) go to `_cos_glow_transport.lua`;
  `/glow_status`, `/glow_trace`, and bounded #574 evidence belong to
  `_cos_glow_diagnostics_runtime.lua`.
- **New custom weapon-skin wire sender or #421 null/restore change** → `_cos_wire.lua`.
  Keep all sender registrations and the frozen regression surface together; the
  substitution is never setting-gated.
- **New attachment-category (hat) spawn or sync path, or a change to how one
  resolves its LA identity** → `_cos_attachment_spawn_sync.lua`. All four seams
  (husk create, local game-object init, resynced loadout, hot join) live together
  because they share one contract: substitute or pre-patch before vanilla, restore,
  then re-emit. Keep the plain-table nil-guarded `AttachmentUtils` registration shape,
  and reach rebound entry state through its getter rather than capturing a value.
- **A new override lane on the unit table vanilla spawns for an item, or new
  work on the live in-keep/in-mission body spawn** -> `_cos_equipment_assembly.lua`.
  The two seams are nested, not merely adjacent: `create_equipment` brackets the
  `get_item_units` call with `_in_create_equipment`, so keep them in one module and
  keep every mesh lane package-gated through `_override_package_ready`. Keep the
  plain-table nil-guarded `BackendUtils` registration shape, and reach rebound entry
  state (husk-wield context, customization backend id) through its getter.
- **Rendering a stored LA entry onto a body, or putting the body back to vanilla**
  -> `_cos_la_apply_runtime.lua`. Every new apply trigger must funnel through
  `_apply_la_on_unit` rather than growing its own re-apply, and every new revert
  path through `mod._la_reconcile` -- that funnelling is what lets the #518 deus
  gate and the #14 character gate each live at exactly one site. Any new pulse
  must share `_offhand_reswap_state` so it cannot bypass the rate limit. If you
  add state that the entry also rebinds, hand it over as an accessor and add the
  matched control/treatment pair to `test_cos_la_apply_runtime.lua`; a getter
  alone is not enough when the owner rebinds too.
- **Anything that puts LA appearance state on the wire, reads it off the wire, or
  decides who the host / wearer is** -> `_cos_la_sync_transport.lua`. Do not add a
  fifth RPC name: the `cos_la_apply` payload is deliberately additive-optional
  (`revert`, `offhand_unit`) and `COS_RPC_SCHEMA` only bumps for a breaking shape
  change, so a new concern gets a new optional field handled BEFORE the
  `armoury_key` gate, exactly like the shipped revert and offhand branches. Every
  sender must route through the same host-short-circuit / client-request /
  deferred-queue shape and stamp the same dedup key, or the purge tick's per-peer
  sweep of `_last_emit_at` will not reach it. New registrations belong in phase 2;
  moving anything into phase 1 changes mod-wide registration order.
- **Anything that decides which backend_id a cosmetic slot resolves to, or that
  substitutes a cosmetic identity on an outgoing VANILLA encode** →
  `_cos_la_loadout_safety.lua`. `mod.loadout_cache` has exactly one writer path
  (the `set_loadout_item` hook) and one authoritative persist call; a second
  writer elsewhere re-opens #520, where the equipped LA cosmetic died with the
  session. Any new vanilla sender that encodes an item or skin name through a
  strict `NetworkLookup` table gets its substitution HERE, unconditional and
  never behind a toggle (issue 371 / BUG_CLASSES 31) - and when no vanilla
  equivalent exists the only correct action is to skip the send, never to pass
  the LA key through. This owner installs ABOVE the entry's `_send_la_apply`
  assignment, so anything it needs from the transport must arrive as a getter,
  not an install-time value; add the matched control/treatment pair to
  `test_cos_la_loadout_safety.lua` when you add one, because a by-value capture
  freezes nil silently and every substitution test stays green.
  `_net_safe_hook_status` and `_la_substitute_name` are NOT this owner's: they
  stay entry state the entry brokers to `_cos_attachment_spawn_sync`.
- **Anything touching the LA bridge/husk, other customization/glow UI,
  or live weapon render-path hooks** → still in
  `cosmetics_tweaker.lua` until a later phase extracts them (the render hooks' scale/grip
  apply helpers already live in `_cos_render.lua` and their glow apply helpers in
  `_cos_glow.lua`); grep ALL files for an existing hook on the `(Class, method)` before
  adding one (VMF drops the second — NON-NEGOTIABLE 8).
- **New independent offhand-weapon or shield display-name rule** →
  `_cos_offhand_names.lua`; keep component/hand identity separate from unit paths,
  persistence, and networking. Add player-authored English strings to
  `cosmetics_tweaker_localization.lua` using the key emitted by
  `/cos_offhand_name_inventory`. Existing shield registries remain the fallback
  source until a final independent name is authored.
- **New pending offhand customization-session state or Apply/revert bookkeeping** →
  `_cos_offhand_session_state.lua`. Key by exact backend item and then hand; do
  not put durable save data, renderer state, or peer transport into this owner.
- **New cross-module value** → export onto `mod._cos` in the owning module (which must
  be earlier in the manifest than its consumers) and localize it at the consumer's top.

## Independent offhand (shield) illusion picker

### Borrowed vanilla families and CWV ownership

Some CWV skins deliberately retain a vanilla `matching_item_key` because the
engine's illusion-apply path needs a real vanilla template. This is a
compatibility relation, not presentation ownership. CWV stamps the canonical
target in `ItemMasterList[skin].cwv_owner_item_type`; matching-key pool builders
must route through `_cos_cwv_family_contract.skin_source_allowed`. The default is
vanilla-only. A mod-owned source enters a borrowed pool only through an explicit
`admitted_owner_item_types` set on that exact hand declaration. This prevents a
Dawi Mace or Cudgel from leaking into Kruber's Sword+Mace merely because all
three safely apply through `es_1h_mace`.

The two-row picker on the weapon customization screen lets the user pick a shield independent of the weapon illusion. Vanilla shield options have `unit` set; LA (Loremaster's Armoury) options have `la_armoury_key`, `vanilla_skin`, and `intended_unit`.

### Dual-weapon ownership contract (#583)

Remote equipment is a special identity boundary: vanilla husks carry the base
item key, even when CWV has already reconstructed an exact per-peer descriptor.
Never validate a received CWV hand against the base weapon's cosmetic pool.
`_cos_cwv_peer_identity.lua` may select an exact CWV item type only from CWV's
schema-matched, fingerprint-validated descriptor and only when that type is in
Cosmetics' registered independent-dual catalog. Every other state retains the
base item type and the restrictive compatibility result. Do not infer family
identity from the received unit path and do not add a second network channel.

Dual weapons reuse the same per-backend/per-hand substrate without pretending
the offhand is a shield. Vanilla's normal illusion row is the sole owner of the
main/right hand. Cosmetics adds one left/offhand row sourced from that family's
exact hand column; `Follow Main Illusion` stores no override. Native definitions
are available at Cosmetics load, while CWV's seven generated dual families are
built lazily after CWV registers its string-keyed skins.

Inventory icons follow the same ownership boundary. A dual weapon always keeps
the icon of vanilla row 1 / the main-right illusion; a saved left-hand override
cannot replace it. A shield weapon instead follows its selected left-hand shield.
Vanilla shield options persist the exact authored inventory icon beside the mesh,
while LA shields resolve `SKIN_LIST[armoury_key].icons[vanilla_skin]`. This is a
per-backend presentation override only and does not participate in DLC ownership
or unlock filtering.

CWV's Dawi Mace family declares that boundary in
`_cos_cwv_family_contract.lua`. `cwv_dr_dawi_mace` and
`cwv_dr_dawi_dual_maces` keep primary-mace icon ownership. Dual Maces exposes
two independently persisted hand choices sourced from Bardin's canonical
`dr_1h_hammer` cosmetic family. `cwv_dr_dawi_mace_shield` keeps vanilla row 1
as its primary-mace selector, borrows the Bardin shield pool from
`dr_1h_axe_shield`, and gives the shield ownership of the inventory icon. The
contract registers data with the existing exact-hand picker, persistence, and
peer replay; it adds no Dawi-specific render or network hook.

The native reference is `scripts/settings/dlcs/bless/weapon_skins_bless.lua`:
the `wh_dual_hammer_skin_*` records carry both hand fields and
`wh_dual_hammer_skins` supplies the rarity buckets. The owning item type is
`wh_dual_hammer` in `item_master_list_bless.lua`. Do not infer hand meshes from
display names or inventory icons; source the authored hand field.

### Independent component names (#641)

Visual ownership and item-card text ownership use the same component boundary.
The normal illusion row retains the primary/right-hand source name. Every
selectable dual-weapon left-hand option carries its source skin identity plus a
stable `cos_offhand_weapon_<source>_left_name` localization key resolved by
`_cos_offhand_names.lua`. If that independent key has no authored string, the
picker deterministically displays the localized source illusion name; it never
falls through to the raw skin key during normal runtime resolution.

Shield options carry a separate `cos_shield_<identity>_left_name` key (or an
explicit existing custom-shield localization key) and fall back to their
existing shield-specific name. Hover labels are composed as
`Primary Illusion + Offhand/Shield`: the primary half is reused from the source
illusion for the primary model currently being previewed, never invented as a
monolithic weapon-pair name.

The same canonical component record owns flavor text. An authored component
description wins; otherwise `_cos_offhand_names.lua` resolves the source
illusion description and finally readable generated copy. The centralized
`_cos_item_presentation.lua` descriptor publishes that component description
through `UIUtils.get_ui_information_from_item`; it must never leave the primary
weapon's description in place after resolving an independent component.

This policy is presentation-only. Persistence continues to store the exact
backend item, hand field, and unit path, and networking continues to send the
bounded direct-mesh payload. Run
`/cos_offhand_name_inventory` for the live deduplicated naming queue; authoring
instructions and the key schema are in `OFFHAND_ILLUSION_NAMES.md`.

Committed direct meshes persist as `offhands[backend_id][left_hand_unit].unit_path`.
The successful `_apply_weapon_skin_craft_complete` callback is the durable commit
edge for both vanilla row 1 and Cosmetics' independent row 2. `on_exit` may emit
and re-wield, but must not be the first durable write: closing the process or a
cross-mod view rebuild can bypass that later callback. The row-2 commit filters
the pending queue by exact backend ID and retains the component skin key so two
instances cannot collapse into a template-wide choice.
Restore and remote husk application accept the path only when it remains in the
current item type's compatible left-hand pool. A salvaged item, removed variant,
wrong hand, missing package, or mismatched family yields to the normal paired
illusion. Network commits reuse `cos_la_apply`'s additive `offhand_unit` field:
one last-choice queue entry per backend item and hand, host-authoritative cache,
transition rebroadcast, and the existing acknowledged/bounded hot-join pull.

### Render paths
LA paint and mesh override must apply on three independent render paths:

| Path | Hook target | Skin signal | Notes |
|------|-------------|-------------|-------|
| Customization preview | `LootItemUnitPreviewer:spawn_units` (`mod:hook`, NOT `hook_safe`) | `item.skin` set | `self._spawned_units` is assigned by the *caller* AFTER `spawn_units` returns; capture the returned `units` array directly |
| In-game body | `GearUtils.create_equipment` | `result.skin` set | spawns both 1p and 3p halves |
| Inventory/equipment menu character preview | `HeroPreviewer:_spawn_item` and `MenuWorldPreviewer:_spawn_item` (via `_spawn_item_post`) | `_equip_skin_by_item[previewer][item_name]` populated by `equip_item` hook | `item_name` is the WEAPON master key (not a skin entry) — we MUST capture the `skin` arg from `equip_item` for has_skin to work |

Authored full-body skin textures have one additional ordering boundary. The
previewer spawns `mesh_unit` hidden and sets
`character_unit_hidden_after_spawn = true`; on a later update,
`_update_units_visibility` calls `_set_character_visibility(true)`, which
reapplies `skin_data.material_changes` to that same mesh
([src: `world_hero_previewer.lua:98-105,204-254,367-379,543-585`]). A custom
texture replay must therefore wait until `character_unit_visible == true`
before caching the mesh. Hiding invalidates that cache so a later show can
replay after vanilla's material restore. A successful spawn-frame paint or log
line is not evidence that the visible inventory mannequin retained the texture.

### Mesh resolution (`intended_unit`)
For LA options, the target mesh comes from `variant.new_units[1]` in LA's SKIN_LIST. This is the **only** reliable source — texture-path regex and lex-sorted icon keys both produced visibly wrong meshes in earlier versions.

| variant kind | `new_units` | `is_vanilla_unit` | Action |
|--------------|-------------|-------------------|--------|
| `texture` | set | `true` | Use `new_units[1]` as `intended_unit`. Vanilla mesh + LA texture paint. |
| `texture` | nil | n/a | Normally `intended_unit = nil` and LA paints the current same-family shield. Exception: Weavebound/Shyish magic shields do not expose LA's diffuse slot, so the exact known magic unit is replaced by its geometrically identical non-magic receiver before paint. The receiver table is family-scoped; never infer one from a generic `_magic` suffix. |
| `unit` | set | n/a | **Filtered out** of the picker. Points to LA's custom-authored mesh files (e.g. `units/empire_shield/...`) with no standalone package; spawning crashes `world.spawn_unit`. Restoring requires hooking LA's package-load bootstrap. |

### Package preload (critical — was the recurring crash source)
1p and 3p meshes are **separate packages** in vanilla VT2 (confirmed by `WeaponUtils.get_weapon_packages` and LA's bootstrap, which loads both halves explicitly).

When the user picks an offhand override, our `BackendUtils.get_item_units` hook sets `result.left_hand_unit` to a path whose package may not be in the equipped skin's package chain. The engine asserts if the unit isn't loaded.

Rules:
1. **Async, non-prioritized load only.** `Managers.package:load(path, "cosmetics_tweaker_offhand", callback, true, false)`. The 1P+3P `Application.can_get` gate keeps an override hidden until the units are spawnable, so there is no reason to block startup with `ResourcePackage.flush`.
2. **Load both halves.** `<unit_path>` AND `<unit_path>_3p`. The in-game body needs both; the customization preview only needs 3p.
3. **Defensive gate.** `_override_package_ready(unit_path)` in the `BackendUtils.get_item_units` hook verifies both units via `Application.can_get("unit", ...)` before applying the override.
4. **Generation-scoped callback.** Vanilla retains callbacks on a shared in-flight package when our reference unloads but another owner remains. Invalidate the lifecycle generation before unloading; a callback with the dead token must never recreate readiness state. Never mutate PackageManager's private callback table.
5. **One owned reference per path.** Dedupe before `load`, release the exact sorted ownership snapshot once on mod unload, and keep detailed late-callback/release-failure diagnostics capped at four rows.

### `has_skin` gate (don't mutate base templates)
The `BackendUtils.get_item_units` mesh override and the LA paint must both skip when no illusion is equipped — applying overrides to the base weapon template would leak LA visuals onto items the user didn't customize.

Per render path:
- `BackendUtils.get_item_units` hook: gate on `resolved_skin` (the `skin` arg, fall back to `Managers.backend:get_interface("items"):get_skin(backend_id)`).
- Customization preview: `item.skin ~= nil` OR `item_data.item_type == "weapon_skin"`.
- In-game body: `result.skin ~= nil`.
- Inventory character preview: `item_data.item_type == "weapon_skin"` OR `_equip_skin_by_item[previewer][item_name]` populated.

### NEVER call `LA.apply_new_skin_from_texture` for offhand
LA's apply function mutates `WeaponSkins.skins[skin].inventory_icon` and `ItemMasterList[skin].inventory_icon` **permanently**. Once we trigger it, vanilla inventory icons leak LA heraldics globally. Use the local re-implementation `_paint_offhand_textures_locally(unit, variant)` in `_la_bridge.lua` — it only touches the supplied unit's mesh materials via `Material.set_texture(mat, slot, path)` using the shield slot hashes:
- diff: `texture_map_c0ba2942`
- pack: `texture_map_0205ba86`
- norm: `texture_map_59cd86b9`

LA uses different slots for `swap_hand="armor"` (`texture_map_64cc5eb8` / `_861dbfdc` / `_abb81538`) and 1p fps units. For shield 3p paint these slots are correct.

### Auto-select on customization screen open
`_setup_illusions` resolves the currently-equipped illusion's `left_hand_unit` and matches it against the picker pool. The skin lookup chain is:
1. `item.skin` (BackendItem field)
2. `Managers.backend:get_interface("items"):get_skin(item.backend_id)` — vanilla-crafted weapons often hit this fallback (item.skin is nil)
3. `WeaponSkins.default_skins[item.key]`
4. `item_data.left_hand_unit` (template default)

Any stored `_offhand_selection` whose mesh no longer matches the rendered shield is discarded — the picker always reflects what's visible. Without this, cycling main-hand illusions visually swapped the shield too.

### Diagnostic commands
- `/la_offhand_dump` — each LA shield variant → resolved `intended_unit`, source (`new_units` / `no_override` / `unresolved`), texture path, icon keys.
- `/offhand_debug` — dumps the picker pool and current `_offhand_selection`.
- `[LA paint]` lines in `Console.log` — shows where the paint flow stopped (gate / variant lookup / paint call).

### Weapon identity before LA paint

Every offhand or weapon-illusion replay must prove that the stored entry belongs to the currently wielded item before touching a hand unit. Resolve the active slot from `inventory._equipment.wielded_slot`; `inventory.wielded_slot` is only a compatibility fallback for the husk extension and is absent on the local-owner extension. Match offhand entries by the wielded item's template/name/key/item type. Only the illusion path may additionally match a cosmetic slot key. An unresolved or different wielded item is a restrictive skip, never permission to paint: the pending queue or next-wield reconcile retries the matching weapon. `/cos_regression_test` check `cos_la_weapon_identity_gate_local_wearer` locks this #514 invariant.

### Career identity before peer-store replay

`peer_id` is a transport address, not a durable wearer identity: the same human can change careers without changing peers, and host-owned bots can share that peer. Every `_la_equips_by_peer` material/mesh entry therefore carries `wearer_career`. Resolve it from the live inventory extension's `_career_name` first, with the exact Player API only as an owner-side fallback. A remote human husk may consume the record only when its stamped career exactly equals `SimpleHuskInventoryExtension._career_name`; missing or mismatched identity fails closed and a confirmed career change invalidates stale slots before wield. A non-player-controlled bot never consumes or purges the human peer store. Keep this field on apply requests, authoritative apply broadcasts, deferred sends, pull-on-ready replies, and hot-join replay; changing that required shape requires an RPC schema bump. `/cos_regression_test` check `issue698_husk_career_identity` and `test_cos_husk_identity.lua` lock the #698 boundary.

## Known limitations
- LA `kind="unit"` variants (custom-mesh Empire basic shields, the elf `_mesh` variants, etc.) are not exposed — needs LA-package-load integration to register their meshes for on-demand spawning.
- The `_equip_skin_by_item` map is per-previewer with weak keys; if a previewer is reused across different equipped items without `equip_item` being called for each slot, has_skin may report stale data. Hasn't reproduced in practice.

## Cross-mod dependencies
- **Loremaster's Armoury** (steamcommunity / `dalokraff/Loremasters-Armoury`): texture variants used by the LA bridge in the offhand picker.
- **MoreItemsLibrary**: registers LA's hat/armor clones as separate inventory items (different feature; not used for offhand).
- **Material-Hijack** (planned): for Purified-outfit dirt removal and other texture swap features.
