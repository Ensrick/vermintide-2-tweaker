# gui_tweaker_dev - engine contact surface

What vanilla VT2/Stingray does at every seam `gut_dev` touches, and why the mod is
there. This is the per-mod companion to the subsystem set in `docs/engine/`
(read `docs/engine/README.md` for house style). It does **not** re-explain a
subsystem the engine docs own - it names the seam, cites the vanilla behavior,
and links out. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `gut` line numbers are in
the named `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/*.lua` module (or its
`hb/` subdir). `§N` = a `docs/BUG_CLASSES.md` class; `#N` / "issue N" = a GitHub
issue. Grep-verified 2026-07-12 against the decompile and the mod source. The
FreeFlightManager and PlayFabMirrorBase citations below were opened and confirmed
line by line, as were `IngameUI.setup_views` / the DLC `ui_views` seam and
`HudCustomizer`; the remaining `[src:]` citations are carried from the cited
`gut_dev` module comments, which cite the decompile in turn (and were themselves
grep-verified when written).

**Dev/stable relationship.** This documents `gui_tweaker_dev` (`gut_dev`,
MOD_VERSION `0.2.303-dev`, friends-only Workshop 3751024698), the ACTIVE working
stream. `gui_tweaker/` (`gut`, public-alpha Workshop 3732144878) is its read-only
public twin; per repo `CLAUDE.md` all in-flight work happens in the dev dir and
promotion is a separate user-triggered action, so this doc cites only `gut_dev`
line numbers. Several always-on `printf` diagnostics gate on a dev-stream check
that survives the dev->stable promotion sed.

`gut` is a **broad UI/GUI bundle**, not a deep render mod: ~35 modules covering
in-game drag-to-reposition HUD customization, native saved loadouts scoped to the
modded realm, a native-chrome Mod Tweaker settings view, an in-keep Bestiary/Armory
compendium, and the migrated `gt` third-person camera / free camera / cutscene-skip
features, plus a large forked slice of the HideBuffs "UI Tweaks" mod under `hb/`.
Its engine contact clusters into five surfaces - camera/viewport lifecycle, the
backend loadout mirror, HUD composition + drag, the HideBuffs fork, and view/window
injection - each with its own subsystem note below.

### Mod Tweaker module ownership

The two presentation owners keep lifecycle and engine-facing view attachment in
`_mod_tweaker_view.lua` and `_mod_tweaker_state.lua`. Their input, numeric/search
editing, pointer dispatch, hover/tooltips, and renderer passes live in the sibling
`*_interaction.lua` modules and are installed exactly once through explicit
dependency tables. `_gut_mod_tweaker_contracts.lua` owns the runtime contract
registrations formerly embedded in the root entry, while
`_gut_ui_tweaks_integration.lua` owns the absorbed HideBuffs/UI Tweaks bootstrap
and returns only its temporal and synchronization lifecycle adapters. None of the
four extracted module families may register an engine hook, command, or mod
lifecycle callback. Stable uses the same boundaries; only the documented dev
Dialogue dependency is additional. Both package manifests already include
`scripts/mods/<id>/*`, so the extracted root modules are bundled without an
individual manifest row. Offline `test_gut_module_extraction.lua` enforces these
ownership, parity, and package contracts.

## Hook table

~135 registration sites across ~35 modules, grouped below into rows-of-concern.
`[hook]` = full wrapper (`mod:hook`, can rewrite args/returns); `[safe]` =
`mod:hook_safe` (post-callback, no override, chains across mods); `[tbl]` =
table-form hook against a plain-table / class-table target resolved after main
(nil-guarded); `[dis]`/`[en]` = `mod:hook_disable` / `hook_enable` (toggles a
vanilla or foreign-mod hook, no body). gut has NO class-hook central registry -
every per-frame feature CHAINS `mod.update` (capture-prev / call-prev-first), so
"rides mod.update" in a trap column means a chained tick, not a hook. Per repo
`CLAUDE.md` NON-NEGOTIABLE 8, VMF drops a second hook on the same `(Class,
method)`; every module below carries a pre-flight grep note, and consolidations
are flagged in the trap column.

### Surface 1a - Third-person camera + screen-particle suppression (owner: `docs/engine/08`, `/04`; `_gut_camera.lua`)

Migrated from `gt` 2026-06-29 (#191); behavior unchanged, ids `tp_*` -> `gut_tp_*`.

| Class.method (kind) | Vanilla behavior at the seam | Why gut hooks it | Trap / invariant |
|---|---|---|---|
| `PlayerUnitFirstPerson.set_first_person_mode` [hook] `_gut_camera.lua:169` | Flips the local view between 1P and 3P; the guard `override OR NOT third_person_mode OR NOT attract_mode` [src: `player_unit_first_person.lua:907`] always passes (attract_mode nil) so any system can restore 1P | Block a 1P restore while the 3P camera owns the view (`_tp_enabled and active and not override`) | Must YIELD while a cutscene owns the camera or the post-cutscene 1P restore is swallowed forever - `CutsceneSystem:is_active() == (active_camera ~= nil)` and the restore runs BEFORE `active_camera` is niled [src: `cutscene_system.lua:83-85`,`:154-156`] |
| `PlayerUnitFirstPerson.create_screen_particles` [hook] `_gut_camera.lua:180` / `stop_spawning_screen_particles` [hook] `:206` / `destroy_screen_particles` [hook] `:210` | Create/stop/destroy the 1P screenspace particle overlay (buff/ability screen FX) | Suppress screen FX in 3P (`#209`); nil-guard the two particle sinks so an unguarded vanilla caller cannot crash on the nil id we return | `nil` return is safe ONLY for `BuffExtension` (guards `if effect_id`); overcharge + vortex exit paths pass a stored id unchecked (`#216`, crash `0a41da66`) - hence the sink guards + the overcharge hook below |
| `PlayerUnitOverchargeExtension._update_screen_effect` [hook] `_gut_camera.lua:196` | Lazily creates the overcharge overlay id then calls `World.set_particles_material_scalar` every tick while overcharge > 0 | Destroy + skip the overcharge overlay in 3P (Bolt Staff heat crash, `#216`) | Calls the vanilla `_destroy_all_screen_space_particles` helper (nils both id fields) - do not hand-nil |
| `GenericStatusExtension.set_zooming` [safe] `_gut_camera.lua:242` / `switch_variable_zoom` [safe] `:247` | On aim, write the weapon's zoom camera node (engine appends `_third_person`) to the follow unit's `settings_node` [src: `generic_status_extension.lua:1516-1523`/`:1563`] | `gut_tp_disable_zoom_in` (#202): force the node back to `over_shoulder` for EVERY weapon uniformly, view-only (aim mechanics key off `self.zooming`, not the node) | Gated on `Development.parameter("third_person_mode")` - the same flag the engine reads - so it is inert outside the 3P camera; each method hooked once |
| `PlayerUnitFirstPerson.extensions_ready` [hook] `_gut_camera.lua:255` | Fires on the LOCAL player's own 1P spawn | Defer tp: flip OFF, force 1P, then re-arm via a 0.5 s `mod.update` timer so the FP system finishes init first | gut's ONLY hook on this method; re-apply is timer-driven, NOT another `extensions_ready` hook. tp is force-cleared on every game-state change and re-armed here |

### Surface 1b - Free camera / free-flight (owner: `docs/engine/08`, `/04`, §32; `_gut_freecam.lua`)

Uses the engine's own `FreeFlightManager` (the "Photo Mode" mechanism); never touches locomotion (the old gt attempt's crash class). Issue #307.

| Class.method (kind) | Vanilla behavior | Why gut hooks it | Trap / invariant |
|---|---|---|---|
| `PlayerInputExtension.is_input_blocked` [hook] `_gut_freecam.lua:364` | Checked in `PlayerInputExtension.get`, which then nullifies the read [src: `player_input_extension.lua:146-157`,`:149`] | Return true while freecam owns the LOCAL player - the reliable character freeze the old gt attempt lacked. CONSOLIDATED (#310): also returns true while HUD edit mode wants input suspended (`mod._gut_hud_customizer.should_suspend_input()` = edit mode active AND no cutscene owns input), so the mouse drives the HUD drag editor not the camera | Local-player-only (husks untouched); this is why gut can UNBLOCK the input devices on enter (the #307 hard-lock fix) and still hold the character. VMF drops a 2nd hook on this pair, so the #310 edit-mode block lives in THIS body, not a hook in `_hud_customizer.lua` |
| `FreeFlightManager._exit_free_flight` [safe] `_gut_freecam.lua:374` | Tears down the overlay viewport + observers [src: `free_flight_manager.lua:619`] | Sync gut's flag if the engine exits free flight for any reason gut did not drive | Pre-flight: no other gut hook on `FreeFlightManager`. The `_enter_free_flight` [src: `:584`] / `_clear_free_flight` [src: `:531`] entry points are CALLED, not hooked |

Direct-call seams (not hooks, but load-bearing): `_enter_free_flight` [src: `free_flight_manager.lua:584`] creates the detached viewport and calls `block_device_except_service("FreeFlight", ...)` on all three devices [src: `:610-612`] (gut immediately reverses it with `device_unblock_all_services`); `register_player` seeds the per-player data slot on spawn [src: `:537`]; on a world teardown mid-freecam the engine routes to `_clear_free_flight` [src: `:531`] which does NOT call `_exit_free_flight`, so gut's `on_game_state_changed` force-resets the flag (§32). Every world lookup routes through a `has_world`-gated `_live_world` (a bare `world()` FASSERTS in the no-world window, §32).

### Surface 1c - Cutscene skip + fade + loading-monologue (owner: `docs/engine/08`; `_gut_cutscenes.lua`, `_gut_monologue.lua`)

Migrated from `gt` (#106 skip 2026-06-25, #192 monologue 2026-06-29). All `CutsceneSystem` hooks are table-form, guarded `if CutsceneSystem`.

| Class.method (kind) | Vanilla behavior | Why gut hooks it | Trap / invariant |
|---|---|---|---|
| `CutsceneSystem.skip_pressed` [hook,tbl] `_gut_cutscenes.lua:322` | ESC/Space skip, gated behind `script_data.skippable_cutscenes` [src: `cutscene_system.lua:98`] | Scope-unlock the skip ONLY around this call, ONLY for a cutscene carrying a wired `event_on_skip` flow event (#275 policy) | Never latch the unlock globally - a boss/phase cinematic with `event_on_skip=nil` (Nurgloth on `dlc_castle`) must play out or the fight desyncs into a ~66%-health softlock (memory `reference_vt2_cutscene_wired_on_skip_policy`) |
| `CutsceneSystem.flow_cb_cutscene_effect` [hook,tbl] `_gut_cutscenes.lua` | Fires a named cutscene flow effect incl. `fx_fade` | Order-independent fade classification (#140/#257/#274 ROUND 3): every `fx_fade` classifies against the system's live cutscene EPISODE in the pure `_gut_cutscene_skipwindow.lua` - one-shot in-skip-call fade, deferred-skip PENDING window, post-skip straggler window (rolling grace + hard cap), and the bounded pre-identity INTRO WATCH (#257, Well of Dreams = `dlc_termite_3`) | CONSOLIDATED: all fade concerns live in this SAME body (VMF drops a 2nd hook); the swallow site carries the `_gut_cutscene_fade_swallow_site` marker pinned by rt-check + `qa/rt_textual_invariants.psd1`. `_gut_cutscene_probe257.lua` stays behavior-free (32-record cap) and now records the REAL per-callback verdict. Trade-off: a standalone `fx_fade` during a live window/watch is also swallowed (cosmetic pop, documented) |
| `CutsceneSystem.flow_cb_activate_cutscene_logic` [hook,tbl] / `flow_cb_activate_cutscene_camera` [hook,tbl] / `flow_cb_deactivate_cutscene_cameras` [safe,tbl] | Activate cutscene logic / activate a cutscene camera / deactivate all cutscene cameras | Logic-activate OPENS a new episode (the release half of the single skip-window release condition) then runs the deferred auto-skip evaluation (issue-275/274 intro-only policy unchanged); camera activations classify per episode - suppressed while the skipped episode's window is live, released + passed when a DIFFERENT non-nil `event_on_skip` proves a new cutscene (#274: a legitimate later cutscene always passes; the window's 45 s hard cap bounds the worst case) | The #140 round-1 camera-node one-shot fade-arm is REMOVED (subsumed by the pending window - identity at the camera node implies logic already queued the skip); deactivate hook is log-only + episode contact |
| `ShowCursorStack.pop` [hook,tbl] `_gut_cutscenes.lua:515` | Pops one cursor-show stack reason | Cutscene-flow cursor bookkeeping | gut only CALLS `ShowCursorStack.show`/`.hide` elsewhere; this is the sole `.pop` hook |

`_gut_monologue.lua` registers NO hooks: it sets `script_data.disable_level_intro_dialogue` (the vanilla debug-screen flag read at [src: `state_loading.lua:585`,`:635`]) to skip Lohner/Olesya VO. It writes the bare `script_data` name (`script_data = script_data or {}`, `_gut_monologue.lua:19`) - audited under #496 and DISPROVED as a shadow risk: `_G.script_data` is created at engine boot [src: `boot.lua:4` -> `boot_init.lua:79`], before `ModManager:new` [src: `boot.lua:404`] ever loads a mod, so the `or {}` branch is dead and the assignment aliases the real global; VMF dofiles mod files with NO setfenv (vmf `safe_calls.lua:71-79`), so the field write at `:20` mutates the exact table `state_loading.lua:585/:635` reads (see dead ends).

### Surface 2 - Native saved-loadouts mirror (owner: `docs/engine/11`; `_gut_native_loadouts.lua`)

Issue #175: makes the vanilla I-VI loadout bar read/write a modded-only store while
in the EAC-untrusted realm, so official-realm loadouts are never touched. Hooked at
the CONCRETE subclass `PlayFabMirrorAdventure` (NOT the base - `class()` copies parent
methods at definition [src: `class.lua:51-57`], so a base hook misses the live
instance). Tri-mode gate: `MODE_OFF` (official/Versus, fully inert) / `MODE_STORE`
(default modded) / `MODE_READONLY` (#287 mod-owned overlay: cosmetics plus exact CWV
backend instances; ordinary gameplay values remain official-read-only).

| Class.method (kind) | Vanilla behavior at the seam | Why gut hooks it | Trap / invariant |
|---|---|---|---|
| `PlayFabMirrorAdventure.get_character_data` [hook] `_gut_native_loadouts.lua` | Resolves one slot's value from `_career_data[career][index or selected]`, nil if absent [src: `playfab_mirror_base.lua:1909-1919`] | STORE: serve the slot from the modded store; per-read official fallback for a gear id unresolvable RIGHT NOW; #375 emits one bounded changed-state snapshot tying the caller and requested/resolved/selected indices to both weapon rows and the value served | NEVER destructively sanitize - synthetic ids (cim craft, LA/cosmetics UUID) register LATE (2026-07-02 spawn-fatals); resolve via RAW field reads only, NEVER `iface:get_item_from_id` (recursion -> 1 GiB heap, v0.2.173 burn); weapon-slot last resort is `get_default_loadouts` [src: `:1955-1966`]. The #375 cache is deduplicated and hard-capped at 128 records, never a per-frame log. |
| `PlayFabMirrorAdventure.get_career_loadouts` [hook] `:596` / `has_loadout` [hook] | Return `(selected_index, loadouts_array)` [src: `playfab_mirror_base.lua:1944`] / whether a loadout index exists [src: `:1921`] | STORE: serve the store's rows/index; READONLY: overlay mod-owned cosmetics and exact `cwv_*_NNN` weapon instances onto a deepcopy of the official array | STORE-space vs official-space loadout indices share NO relationship; forwarding one into the other is the #387/#372 fatal class. Ordinary gear never enters the readonly overlay. |
| `PlayFabMirrorAdventure.set_character_data` [hook] `:640` / `set_loadout_index` [hook] `:676` / `add_loadout` [hook] `:699` / `delete_loadout` [hook] `:727` | Write a slot then push via `set_career_read_only_data` [src: `playfab_mirror_base.lua:1928`,`:1941`]; select/add/delete a loadout, each ending in `dirtify_interfaces` + a cloud encode [src: `:1968`(guard `:1975`, dirtify `:1990`),`:2036`,`:1994`] | Capture the write into the store and DO NOT call the original, so `_career_data`/`_characters_data` stay clean and the diff-based commit finds nothing to push | The isolation guarantee: leaving those tables unmutated is EXACTLY what stops modded loadouts overwriting official cloud data (character-data push is NOT eac-gated); each store branch replicates the vanilla guard it mirrors (`:1975`/`:2001`/`:2005`) |
| `PlayFabMirrorAdventure.set_career_read_only_data` [hook] `:763` | The `_characters_data` writer, the cloud-push payload source, NOT eac-gated | Catch the LA-clone bypass path that reaches this as a method call; block career-scoped writes, pass character-level (career-nil) through | #287: cosmetic slots divert to the modded overlay on this path too |
| `BackendUtils.set_loadout_item` [hook,tbl] `_gut_native_loadouts.lua` | The stable OUTER equip entry point the hero view calls [src: `hero_view_state_overview.lua:1108`] | Capture gear **and cosmetics** that route through an LA-CLONED interface and bypass the concrete mirror hooks (#353); #354 also records enabled WT cross-character captures here | TABLE-form against the post-LA `BackendUtils`, installed deferred once the backend answers; cosmetics resolve through the selected loadout interface and persist vanilla's `override_id or ItemId` identity [src: `backend_interface_item_playfab.lua:635-665`], never the transient backend id; unresolved cosmetics skip with bounded evidence; seeds before first STORE write (#375). The #354 trace reads raw tables, filters to enabled WT selected weapon rows, deduplicates, and caps at 24 records. |
| `BackendInterfaceItemPlayfab.refresh_bot_loadouts` [safe] `:801` | Rebuilds `_bot_loadouts` from `_loadouts` | Overlay store bot designations after vanilla builds the table | Post-callback; no other gut hook on this method |
| `HeroWindowLoadoutSelectionConsole._save_bot_equipment` [hook] `:822` / `_populate_context_menu_loadout` [hook] `:888` | Bot checkbox writes realm-shared `PlayerData.loadout_selection` [src: `hero_window_loadout_selection_console.lua:671-683`]; context-menu preview reads each gear id with NO nil-guard [src: `:913-933`] | Write `bot_index` to the store + skip the PlayerData write; substitute any unresolvable equipment id in a SHALLOW COPY so hovering a saved loadout does not CTD at `ui_utils.lua:248` (#372) | Two DIFFERENT methods on this class, plus `_show_context_menu` in `_gut_mission_inventory.lua` - all distinct pairs; live re-fetch fixes the orphaned-cache stale preview (#379) |

### Surface 3a - HUD drag-reposition core (owner: `docs/engine/09`; `_hud_customizer.lua`, main)

A 10-widget registry; each entry mutates one HUD widget's scenegraph node `local_position`. Reimplements vanilla `HudCustomizer` against real HUD widget nodes.

| Class.method (kind) | Vanilla behavior | Why gut hooks it | Trap / invariant |
|---|---|---|---|
| `<10 registered HUD classes>.init` [safe] `_hud_customizer.lua:389` / `.destroy` [safe] `:412` | Each HUD element (`AbilityUI`, `EquipmentUI`, `OverchargeBarUI`, `BuffUI`, `BossHealthUI`, ...) builds/tears its `ui_scenegraph` | Capture the live view instance and apply the saved per-resolution offset to its node on init; drop the ref on destroy | 20 registration sites via a loop; each widget's vanilla baseline is NON-zero, so gut writes baseline + delta (a raw offset like vanilla `HudCustomizer.run` [src: `hud_customizer.lua:32`] snaps the widget to origin, v0.2.8 F5 fix); when UI Tweaks owns the element (#312) gut PINS its node to vanilla and writes through to HB instead |
| `IngameHud.post_update` [safe] `gui_tweaker_dev.lua:906` | Per-frame HUD composite tick | Drive edit-mode activation + the drag state machine + draw the overlay using IngameHud's renderer | The overlay draw needs a renderer; falls back to `Managers.ui._ingame_ui_context.ui_top_renderer` when `self._ingame_ui_context.ui_renderer` is absent. Activation mirrors vanilla `HudCustomizer.is_active` (chat-focused + left-alt) [src: `hud_customizer.lua:22-24`] plus a sticky toggle. (#310) The drag for gut-owned elements is CONFINED to the displayable HUD area (`confine_delta` clamps the box `[world, world+size]` into `[0 .. res_w*inv_scale] x [0 .. res_h*inv_scale]`, `ui_scenegraph.lua:210-246`); UI-Tweaks-owned elements delegate to HB and are not clamped. Input suspension while editing rides the `is_input_blocked` hook (surface 1b), not this tick |
| `IngameViewLayoutLogic.setup_button_layout` [safe] `gui_tweaker_dev.lua:1047` | Builds the ESC/keep menu button layout data [src: `ingame_view_layout_logic.lua:17-60`] | Inject the "Mod Tweaker" ESC entry into the button list | `hook_safe` is correct - vanilla mutates the layout data in place |

### Surface 3b - HUD-derived readouts + combat cues (owner: `docs/engine/09`, `/10`; the `_gut_*` HUD feature modules)

| Class.method (kind) | Vanilla behavior | Why gut hooks it | Trap / invariant |
|---|---|---|---|
| `UnitFrameUI.add_damage_feedback` [hook] `gui_tweaker_dev.lua:741` | Feeds the team-HUD damage-flash for a hit | Damage-number readout source | Full wrapper to read the pre-mutation event; local-player scoping |
| `DamageUtils.add_damage_network` [hook] `_gut_damage_numbers.lua:98` / `add_damage_network_player` [hook] `:112` | Apply already-final damage on the authoritative machine (DoT/bomb path; player-weapon path) | Observe damage to render floating numbers | Static fns, no `self`; distinct methods from gt's godmode hooks (gut has no godmode) - no cross-mod pair collision |
| `IngameHud.update` [safe] `_gut_respawn_timer.lua` | Per-frame HUD composite | DRAW the respawn timer after vanilla has updated/drawn the live team-frame scenegraphs (#285) | Distinct from `IngameHud.post_update` (surface 3a) - different method, no dup. The countdown widget is drawn through the affected `UnitFrameUI.ui_scenegraph` and its canonical `portrait_pivot`; copying the frame hierarchy drifted from live HUD layout. The `_rt_register` gate locks the hook and live-anchor contract. |
| `UnitFramesHandler._sync_player_stats` [hook] `_numericui_cooldown_realtime.lua:50` / `CareerExtension.current_ability_cooldown` [hook] `:58` | Sync a unit-frame's stat block / report an ability's cooldown | Real-time numeric cooldown readout (NumericUI-compat) | Cooperates with the hb NumericUI-compat disable in `hb_on_all_mods_loaded` (disables NumericUI's own `_create_unit_frame_by_type` hook) |
| `FatigueUI.update_shields` [hook] `_gut_parry_indicator.lua:72` / `ActionPushStagger.*` [safe] `:111-122` / `ActionSweep.*` [safe] `:128-131` / `<block interactable defs>.start/update/stop` [safe] `:141-152` | Stamina-shield HUD tick / push+block action lifecycle / block interactable lifecycle | Parry-window indicator | Action classes are per-action tables resolved after main; each hooked once, safe post-callbacks; `FatigueUI.update_shields` is the only full wrapper |
| `<game-mode class>.game_mode_hud_disabled` [hook] `_hide_ui.lua:194` | Reports whether the HUD is force-disabled for the mode | Hide-HUD cycle feature | Hooked per resolved game-mode class; `mod.gut_hud_cycle` is a `mod.`-field for the VMF keybind |

`_gut_buffbar_endtime_fix.lua` registers NO class hook (rides an `mod.update`-chained tick). `_gut_uitweaks_sync.lua` / `_gut_uitweaks_temporal_fix.lua` provide the #312 ownership map + the UI-Tweaks temporal-drift fix consumed by surface 3a (memory `reference_ui_tweaks_temporal_fix`, `reference_vt2_uitweaks_sync_crossmod_settings`).

### Surface 4 - The HideBuffs fork (owner: `docs/engine/09`; `hb/`)

A renamespaced fork of the HideBuffs "UI Tweaks" mod (`get_mod("HideBuffs")` -> `get_mod("gut_dev")`). Every HideBuffs lifecycle callback is renamed `mod.hb_<name>` and CHAINED from gut's own callback; `mod.hb_update` iterates `mod.update_funcs`. Grouped aggressively - the fork is large.

| Class.method (kind) | Vanilla behavior | Why gut hooks it | Trap / invariant |
|---|---|---|---|
| 14 HUD-element hooks in `hb/hide_elements.lua` [hook, one row of concern] (`ChallengeTrackerUI._draw` `:52`, `TutorialUI.update`/`.update_mission_tooltip`/`.update_objective_tooltip_widget` `:92-135`, `MissionObjectiveUI.draw` `:156`, `BossHealthUI._draw` `:168`, `GameModeManager.has_activated_mutator` `:191`, `IngameHud._update_components_visibility` `:220`, `OutlineSystem.always` `:233`, `DialogueSystem.trigger_sound_event_with_subtitles` `:242`, `PlayerHud.set_current_location` `:261`, `SubtitleGui.update` [safe] `:279`, `TwitchVoteUI._draw` `:300`, `WaitForRescueUI.update` `:320`, `TwitchIconView._draw` `:332`, `UnitFrameUI._update_bar_flash` `:344`) | The vanilla draw/update paths for tutorial, mission-objective, boss-HP, outlines, subtitle, twitch, area-text, and HP-flash HUD elements | Hide / reposition / restyle each per the ported `mod.SETTING_NAMES.*` toggles | Each `(Class, method)` hooked ONCE in the fork; a per-hook error in a `_draw`/`update` body just fails that element. These are the ORIGINAL HideBuffs hooks, preserved hook-vs-hook_safe |
| 3 loading-screen hooks in `hb/level_loading_screen.lua` [hook] (`StateLoading._trigger_sound_events` `:20`, `LoadingView.setup_tip_text` `:35`, `LoadingView.create_ui_elements` `:48`) | Loading-screen sound trigger + tip text + UI build | Hide loading tips/subtitles, disable level-intro audio | Reference `mod.SETTING_NAMES` string ids backfilled in `hb_data.lua` (the options-tree builder was stripped; gut owns its own `_data.lua`) |
| `UIAnimation.init` [dis] `hb/mod_events.lua:23` / `Material.set_vector2` [dis] `:24` / `UnitFrameUI.set_portrait_status` [en] `:52` | (engine anim init / material vector write / portrait-status draw) | Enable/disable these on the hb enable/disable lifecycle | Runs from `mod.hb_on_enabled` / `hb_on_disabled`, chained off gut's `on_enabled`/`on_disabled` |

### Surface 5a - Mod Tweaker view injection + ESC entry (owner: `docs/engine/09`; main, `_mod_tweaker_view.lua`)

| Class.method (kind) | Vanilla behavior | Why gut hooks it | Trap / invariant |
|---|---|---|---|
| `IngameUI.setup_views` [safe] `gui_tweaker_dev.lua:1316` | Builds `self.views` from `view_settings.views_function(ctx)` [src: `ingame_ui.lua:145-146`], called from `IngameUI.init` with the context as an ARG [src: `:107`]; the vanilla DLC-view path is `DLCUtils.map_list("ui_views", ...)` [src: `:33`] | Attach `mod_tweaker_view` directly into `self.views` (gut does NOT register through the DLC `ui_views` list) | Capture the context ARG, not `self.ingame_ui_context` - the latter is set at [src: `ingame_ui.lua:138`] AFTER `setup_views` runs, so reading it here is nil and made `ModTweakerView:new` throw (crashed IngameUI at `:625`). The transition-time lazy `_attach_view` is the GUARANTEED path; this early attach may no-op |
| `LocalizationManager.init` [safe] `gui_tweaker_dev.lua:1360` / `IngameView.on_enter` [safe] `:1367` | Localizer init rebuilds `_backend_localizations`; ESC-menu entry draw localizes `mod_tweaker_button_name` via `_base_lookup` [src: `localization_manager.lua:50-51`] | SUPPLY the button string into `_backend_localizations` (the shared bottom of both `lookup` and `simple_lookup`), re-supplying after any re-init | Do NOT hook `_G.Localize` (rawset-replaced on init) or `LocalizationManager.lookup` (the button uses the sibling `simple_lookup`, `ui_passes.lua:1599`) - both are interception that miss a path; supplying data is immune (`IngameView.on_enter` is distinct from gut's `HeroView.on_enter`) |
| `HeroWindowIngameView._update_presentation` [safe] `gui_tweaker_dev.lua:1412` | Lays out the modern keep/ESC menu button column (`offset[2] = -(60*index-1)`, panel `total_height+90`) [src: `hero_window_ingame_view.lua:490-515`] | Compact the column when gut's own Mod Tweaker button pushes it past ~8 to 10 buttons and overflows off-screen (#93, always-on) | The legacy `IngameView` is only the bare in-MISSION menu and has no `set_background_height`/logo - 8 versions of hooking it never fired; the modern menu is this class. No-op below the overflow threshold |
| `OptionsView.build_settings_list` [hook] `_gut_video_profiles.lua` | Builds each native options-tab widget list from its definition | Prepend five-slot graphics profile controls only to `video_settings_list` | Consolidated singleton for #292; source `options_view.lua:1029-1147`; unsupported Video values are skipped. Every non-Video definition is forwarded by identity and untouched. CKC has no vanilla Options integration (#528). |

`_mod_tweaker_view.lua` is a `class()` view borrowing the IngameUI renderer; it creates a modal input service `create_input_service("gut_mod_tweaker","IngameMenuKeymaps","IngameMenuFilters")` and maps keyboard/mouse/gamepad to it (`:64-69`). The bare pcall there is a backlog P2 (swallows a `create_input_service` failure - the view opens dead with no log). Issue #630's `_gut_dx12_fence630.lua` is an observation-only owner around this existing pass: it edge-logs view entry/exit, selected tab, `Window.has_focus()`, and balanced draw calls with a 48-line process cap. It creates no renderer/world/unit/package, skips no frame, and changes no focus behavior. The captured 2026-07-15 dump spent 15.791 seconds in `RI::wait_for_fence` / `D3D12RenderDevice::end_frame` after `[Window] Window => inactive`; absent a Lua exception or an identified ownership imbalance, a focus workaround would be speculative.

### Surface 5b - In-mission keep menus + Bestiary/Armory + probes (owner: `docs/engine/09`, `/06`; `_gut_mission_*.lua`, `_ba_*.lua`, the `_gut_*_probe.lua` set)

| Class.method (kind) | Vanilla behavior | Why gut hooks it | Trap / invariant |
|---|---|---|---|
| `HeroView.init` [safe] `_ba_heroview_inject.lua:46` / `StateInGameRunning.update` [safe] `:66` | HeroView builds its screen-descriptor list; ingame tick | Append the `gut_compendium` (Bestiary/Armory) + `gut_mod_tweaker` KEEP sub-states into HeroView's screen list; capture `ingame_ui_context` so `/armory` `/bestiary` can open from the keep | TWO screens appended in the SAME `HeroView.init` loop (never add a 2nd hook); the `StateInGameRunning.update` hook self-disables after the first capture; distinct from gut's `HeroView.on_enter` |
| `HeroWindowPanelConsole.create_ui_elements` [hook] `_ba_compendium_tabs.lua:216` / `_on_panel_button_selected` [hook] `:231` / `HeroWindowBackgroundConsole._update_object_sets` [hook] `_ba_armory_window.lua:421` | Build the hero-view top tab strip / handle a tab click / manage the background 3D object sets | Compendium tab injection + armory background management (Bestiary+Armory, memory `project_bestiary_armory_in_gut`) | Console-variant classes; each pair hooked once |
| In-mission keep menus in `_gut_mission_inventory.lua` [~10 hooks] (`HeroWindowLoadoutConsole._customize_item` `:164` etc., `HeroWindowItemCustomization._create_item_preview_widget_definition` `:246`/`_register_object_sets` `:281`, `HeroWindowPanelConsole.on_enter`, `HeroWindowCosmeticsLoadoutConsole._equip_item_presentation`, `HeroWindowCosmeticsLoadoutPoseInventoryConsole.draw`, `HeroWindowLoadoutSelectionConsole._show_context_menu`) | The keep inventory/loadout/cosmetic console windows | Enable the keep inventory + loadout menus mid-mission | #89 contract: GUT owns the only mid-mission entry and the two level-free mount hooks; Cosmetics owns the companion render/apply path. The mount hooks are inert in keep and with CIM present. `mod._gut89_mount_surfaces` plus runtime/offline checks pin both registrations. Each `(Class, method)` remains singleton mod-wide. |
| Mission map/start-game in `_gut_mission_map.lua` [10 hooks] (`StartGameWindowBackgroundConsole._create_viewport_definition`/`_update_object_sets`/`_setup_object_sets`/`post_update`, `StartGameWindowAreaSelectionConsoleV2._assign_video_player`, `StartGameWindowAreaSelection._setup_video_player`, `VoteManager._server_start_vote`/`_start_vote_base`, `MatchmakingStateWaitForCountdown.on_enter` [safe], `GameModeManager.complete_level`) | Start-game map viewport/video/countdown; mission-vote creation; level completion | Enable the in-mission map, surface the vanilla game-settings vote to clients in the mission HUD (#700), and arm auto-start | `_create_viewport_definition` is a full wrapper because the vanilla body derefs a keep-only field. `game_settings_vote` is already in `NetworkLookup.voting_types`, but vanilla marks it `ingame_vote=false` [src: `vote_templates.lua:306-319`]. Its active per-vote template is shallow-copied and promoted only in a live Adventure mission, satisfying both the HUD draw gate [src: `ingame_voting_ui.lua:267-301`; `vote_manager.lua:282-283`] and the separate input gate [src: `vote_manager.lua:331-373`] while leaving the shared template, keep votes, and unrelated votes unchanged. The copy also adds an identity `modify_title_text` only when absent: `IngameVotingUI.start_vote` localizes the title only on that branch [src: `ingame_voting_ui.lua:116-121`], whereas the keep's MissionVotingUI localizes either branch [src: `mission_voting_ui.lua:256-264`]. This prevents the raw `game_settings_vote` key without double-localizing or replacing an authored modifier. |
| `StartGameWindowMissionSelectionConsole._profile_difficulty_index_completed` [hook] `_gut_guard649_mission_completion.lua` | Iterates `profile.careers` and reads `completed_career_levels/<career>/<level>/<difficulty>` for Mission Select completion presentation [src: `start_game_window_mission_selection_console.lua:503-524`] | Prevent #649's missing-definition fatal when another mod registers a career after vanilla's statistics definitions were generated | Exact-path and presentation-only: fully defined profiles delegate by identity; a shallow profile view omits only undefined careers. Never hook or pcall `StatisticsDatabase`, and never mutate the live profile. Definitions are generated from the boot-time `CareerSettings` set [src: `statistics_definitions.lua:556-576`] |
| `CharacterSelectionView.post_update_on_enter` [safe] `_gut_mission_hero_select.lua:332` / `on_exit` [safe] `:340` | Mid-mission hero/career select view lifecycle | Career-swap-in-place respawn support (memory `reference_vt2_native_loadout_system`) | Both singletons; restore points |
| `IngamePlayerListUI._update_dynamic_widget_information` [hook] / `_setup_mission_data` [hook] `_gut_tab_property_refresh.lua` | Held-Tab panel: renders per-player rows from the `Managers.player:player_loadouts()` RPC snapshot [src: `ingame_player_list_ui_v2.lua:1450,1507,1527-1539`] frozen at `add_equipment` (wire shape has NO skin field, `loadout_utils.lua:70-88`); builds adventure tome/grim/dice rows with no mechanism gate [src: `:436-514`] | ONE live-session loadout provider (#245 properties/traits + #246 equipped illusion + #250 CW talent repair post-pass + #533 deus row filter): local rows reconcile from the exact live backend instance, every row's skin from the synchronized (wearer, slot) cosmetic identity, per `docs/WEAPON_APPEARANCE_STANDARD.md` section 2 | BOTH pairs owned by this ONE module (pre-flight: `_gut_scoreboard_live.lua` owns `IngamePlayerListUI._draw` only - a distinct pair). Display-only: never calls `LoadoutUtils.sync_loadout_slot` (modded-key re-serialization over the vanilla RPC is the cross-peer wire-safety hazard); skin writes are template-residency-guarded (vanilla icon pass derefs `WeaponSkins.skins[skin]` unguarded, `ui_utils.lua:238-245`) |
| `UIRenderer.create` [hook] `_gut_gui_material_guard.lua:298` | Creates a UI renderer with a material set | Guard against a missing GUI material at renderer create (keep-only Gui materials CTD) | memory `reference_vt2_keep_only_gui_materials` / `reference_vt2_create_screen_gui_missing_material_crash` |
| `StateInGameRunning.on_enter` [safe] `_la_atlas_keepalive.lua:101` / `PackageManager.unload` [safe] `:111` | Mission-start state enter / package unload | Pin LA's atlas package so the Mod Tweaker's borrowed renderer never draws against a freed atlas (in-mission 3rd/4th-open crash) | NEVER force-load a non-resident LA package (re-introduces the 0.2.54 crash) - only re-pin when already resident (memory `reference_la_atlas_keepalive` pattern) |
| Observation probes [~8 hooks] (`_gut_menu_transition_probe.lua` `IngameUI.transition_with_fade`/`handle_transition` [safe] `:129`/`:144`, `_gut_glow_probe.lua` `OptionsView.draw_widgets`/`IngameUI.update` [safe] `:338`/`:449`, `_gut_diag_optionsview.lua` `OptionsView.on_enter`/`update_apply_button` [safe] `:118`/`:163`, `_gut_keybind_probe.lua` `VMFOptionsView.<methods>` [safe] `:122`, `_gut_173_probes.lua` `GameModeAdventure.force_respawn` [safe] `:45`) | Menu transitions, options draw/enter, VMF options view, respawn | Log-only diagnostics for menu/view/keybind/respawn triage | All `hook_safe` observe-only; `IngameUI.update` is owned by `_gut_glow_probe`, so the keybind probe fans its work in rather than re-hooking (VMF drop) |

## Subsystem notes (how the vanilla flow runs, for gut's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc carries the full architecture.

### 1. Camera / viewport / free-flight (owner: `docs/engine/08`, `/04`; §32)

gut's 3P camera does not move a viewport - it sets `Development._hardcoded_dev_params.third_person_mode` (the release-safe path, since `Development.set_parameter` is a no-op in release) and patches the `over_shoulder` / zoom nodes in `CameraSettings.first_person`, then blocks the vanilla 1P-restore at `set_first_person_mode` [src: `player_unit_first_person.lua:907`]. The free CAMERA is the separate engine subsystem `FreeFlightManager`: `_enter_free_flight` [src: `free_flight_manager.lua:584`] creates an overlay viewport via `ScriptWorld.create_free_flight_viewport` and renders from a detached camera while the player unit keeps simulating; `_exit_free_flight` [src: `:619`] tears it down; `_clear_free_flight` [src: `:531`] is the dead-world variant that drops the flags without a world lookup. The load-bearing trap is §32 (dead-world): `mod.update`-chained code keeps ticking through `StateIngame` teardown where the free-flight world is gone, and `WorldManager.world()` FASSERTS on a missing name, so every world lookup routes through a `has_world`-gated `_live_world` and no world handle is ever cached (resolved fresh from the engine's own `data.viewport_world_name`). Because gut leaves the `disable_free_flight` gate UP (so the engine's F8/F9 dispatcher never runs and cannot misfire), the engine's own dead-world cleanup never runs for gut - `on_game_state_changed` force-exits instead, and `is_input_blocked` must never be left true into the next state. The #307 hard-lock came from `_enter_free_flight`'s `block_device_except_service` [src: `:610-612`] cutting ESC/chat/keybinds; gut reverses it immediately and relies on the `is_input_blocked` hook to freeze the character instead.

### 2. Backend native-loadout mirror (owner: `docs/engine/11`)

Every loadout read/write funnels through ONE object, the backend mirror `PlayFabMirrorAdventure`. The vanilla base methods live in `playfab_mirror_base.lua`: `get_character_data` [src: `:1909`] resolves `_career_data[career][index or selected][key]`; the writers (`set_character_data` [src: `:1928`], `set_loadout_index` [src: `:1968`], `add_loadout` [src: `:2036`], `delete_loadout` [src: `:1994`]) each mutate `_career_data`/`_characters_data` and end in a `dirtify_interfaces` + a `cjson.encode` cloud push [src: `:1987-1990`,`:2030-2033`,`:2063-2066`]. gut captures each write into a VMF-persisted store and NO-OPs the original, so the diff-based commit finds those tables clean and never pushes modded loadouts over the official cloud data. Reads serve from the store, so the interface caches (which refresh FROM the mirror) pick up modded values with no interface-layer reimplementation. The recurring hazards are: (a) STORE-space vs official-space loadout indices are unrelated, so a fallback into official data must pass a NIL index (official selected row) not the store index (#387/#372 spawn-fatal); (b) a gear id unresolvable RIGHT NOW is NOT gone - synthetic cim/LA/cosmetics ids register late, so no destructive sanitize, only a per-read official fallback; (c) resolving an id must NEVER call `iface:get_item_from_id` from inside the mirror read (it triggers `_refresh` -> mirror-read -> unbounded recursion -> 1 GiB heap, v0.2.173), only RAW field reads of `_items`/`_inventory_items`. The deep dive - interface cache lifecycle, LA clone dispatch, the equip-capture layering above the mirror - is `docs/engine/11`.

The equip-time capture (mirror write hooks + the outer `BackendUtils.set_loadout_item` capture) only fires on equip EVENTS, so state that reaches the live interface through a path that fires none of them (LA-cloned cosmetic dispatch #353, a WT cross-character weapon whose enable/apply lands outside a captured equip #354) is never stored and is lost on quit. The exit-time snapshot backstop closes that gap: `M.exit_snapshot(edge)` (in `_gut_native_loadouts.lua`, pure diff in `_gut_exit_snapshot_core.lua`) is driven from three bounded exit edges chained off gut's VMF lifecycle callbacks in `gui_tweaker_dev.lua` - `on_game_state_changed` (`exit StateIngame`, `enter StateTitleScreen`) and `on_unload`. It re-reads the live selected loadout via `BackendUtils.get_loadout_item_id`/`get_loadout_item` (the per-slot, LA-aware readers - NOT a mirror-read hook, so the `get_item_from_id` recursion trap does not apply here, same as `/gut_loadout_status`), canonicalized to the store's format (gear = backend id; cosmetics = `override_id or ItemId`), and reconciles any diverged slot of the SELECTED row into the store (STORE mode) or the readonly overlay (READONLY mode, `preserve`-eligible slots only) through the SAME single writer. It adds NO hook. It is non-destructive (a gear id gates on `RESOLVE_YES`; an unresolved live read is a skip, never a clear), idempotent (a clean state diverges 0 and writes nothing), inert outside the modded Adventure realm, and never touches official cloud data. Diagnostic: `[gut:persist] edge=<name> diverged=<n> written=<bool>`.

### 3. HUD composition + drag-reposition (owner: `docs/engine/09`)

The HUD is a set of element classes (`AbilityUI`, `EquipmentUI`, `BuffUI`, `BossHealthUI`, ...), each owning a `ui_scenegraph` whose nodes carry a `local_position`. gut's customizer keeps a 10-entry registry mapping widget id -> `(class_name, movement_node_id, drag_bounds_node_id, vanilla_position)`, `hook_safe`s each class's `init` to capture the live instance, and writes `baseline + saved_delta` into the movement node's `local_position` (the baseline is the registry's `vanilla_position`; a raw delta zeroes the non-zero vanilla baselines and snaps the widget to origin, the v0.2.8 F5 fix - contrast vanilla `HudCustomizer.run` [src: `hud_customizer.lua:32`], whose customized nodes baseline at {0,0} so a raw write is fine). Matching vanilla's separate `drag_scenegraph_id` and `root_scenegraph_id` [src: `hud_customizer.lua:43-47,110-122`], hit testing, confinement, and overlay drawing use the positive-size drag-bounds node rather than a zero-size movement pivot. Edit mode, the drag hit-test, and the overlay draw all ride `IngameHud.post_update` [src: gut `gui_tweaker_dev.lua:906`], acquiring the renderer off `self._ingame_ui_context.ui_renderer` (fallback `Managers.ui._ingame_ui_context.ui_top_renderer`); activation mirrors vanilla `HudCustomizer.is_active` (chat-focused + left-alt) [src: `hud_customizer.lua:22-24`] plus a sticky toggle for accessibility. Offsets persist per-resolution (`hud_offsets[<WxH>][widget_id]`) so a resolution change reads a different bucket. The #312 UI-Tweaks integration inverts ownership: when the standalone UI Tweaks mod owns an element, gut pins its own node to vanilla and writes the drag through to HB's store instead, so the two never stack. This is the same widget re-init / `OptionsView` `cb_` takeover lifecycle family the engine docs cover (memory `reference_vt2_options_widgets_raw_materials`, `reference_vt2_optionsview_synthesized_cb_takeover`).

Issue #310 adds one required normalization at this boundary: `CareerAbilityBarUI` stores its graph in `_ui_scenegraph` [src: `scripts/ui/hud_ui/career_ability_bar_ui.lua:101`], unlike the public `ui_scenegraph` spelling used by `EnergyBarUI` [src: `scripts/ui/hud_ui/energy_bar_ui.lua:49`] and `OverchargeBarUI` [src: `scripts/ui/hud_ui/overcharge_bar_ui.lua:145`]. All editor paths use `scenegraph_for_view` so the private spelling cannot silently remove that element. On each deliberate edit-mode entry, a bounded ten-row `[gut:310] HUD coverage` snapshot classifies live view, graph, movement-node, drag-bounds, and size readiness; it does not run per frame.

#442's career-themed holder is the existing `EquipmentUI.background_panel`, not a
new health-frame view. Vanilla selects `UISettings.hud_inventory_panel_data[career]
or .default` and writes both texture id and authored texture size every update
[src: `equipment_ui.lua:350-359`]. `_gut_diagnostics.lua` therefore inventories
that data seam without adding an engine hook: two capped `[gut:442]` lines prove
Engineer and Priest are the only dedicated entries and identify the eighteen art
gaps. Runtime atlas registration is intentionally deferred until the unique
transparent assets described in `CAREER_HUD_HOLDER_RESEARCH_442.md` exist; a Lua
texture id cannot create an uncompiled Stingray UI resource.

#314's Simple UI compatibility is a separate generic-window surface. `_gut_simple_ui_compat.lua` installs no engine or external-mod hook: its chained `mod.update` tick reads the installed mod's public `SimpleUI.windows.list`, applies the pure viewport policy, and mutates each existing `window.position` table in place. A fitted window is clamped wholly inside `UIResolution()`; an oversized window is pinned so its left edge and top title/drag edge remain reachable. It is inert when Simple UI is absent and does not overlap the scenegraph-node HUD Customizer. Direct source/resource absorption remains barred until the upstream repository supplies a redistribution license; see `SIMPLE_UI_INTEGRATION_PLAN.md`.

### 4. The HideBuffs fork boot chain (owner: `docs/engine/09`)

`hb/` is a renamespaced fork of the HideBuffs "UI Tweaks" mod. Because gut already defines `mod.update` / `mod.on_setting_changed` / `mod.on_game_state_changed` / `mod.on_enabled` / `mod.on_disabled` / `mod.on_all_mods_loaded`, every HideBuffs lifecycle callback is renamed `mod.hb_<name>` and the gut orchestrator (`gui_tweaker_dev.lua`) CHAINS each `hb_<name>` from the matching gut callback. `mod.hb_update` iterates `mod.update_funcs` (the registration list Phase-2 features push per-frame work into) and is called from gut's own `mod.update`. The known engine-adjacent hazard is the backlog P1 row: `mod.hb_update` iterates `update_funcs` with NO per-consumer isolation [src: gut `hb/mod_events.lua:92-97`], so one erroring update_func kills every later one that frame - the fix is to `pcall` each update_func (matching the `gt_dev` registry semantics), because all of it rides `mod.update` [src: `boot.lua:748-750`]. The data-only `hb_data.lua` keeps the literal `SETTING_NAMES` / priority-buff tables but STRIPS the VMF options-tree builder (gut owns its own `_data.lua`), backfilling the dynamically-appended setting-id string keys the hide-elements/loading-screen forks reference. The 14 `hide_elements.lua` hooks + 3 `level_loading_screen.lua` hooks are the ORIGINAL HideBuffs hooks preserved hook-vs-`hook_safe`; each `(Class, method)` is owned once by the fork.

### 5. View / window injection (owner: `docs/engine/09`)

`IngameUI.setup_views` [src: `ingame_ui.lua:145`] builds `self.views` from `view_settings.views_function(ctx)` [src: `:146`] and is called from `IngameUI.init` with the context passed as an ARGUMENT [src: `:107`] - `self.ingame_ui_context` is not stored until later [src: `:138`]. Vanilla registers DLC-provided views by mapping over the DLC `ui_views` lists at the top of the same file [src: `DLCUtils.map_list("ui_views", ...)`, `:33`]. gut does NOT go through that DLC path - it injects `mod_tweaker_view` (and the `gut_compendium` / `gut_mod_tweaker` HeroView sub-states) directly into the built `self.views` / HeroView screen list, capturing the context ARG at the `setup_views` post-hook (reading `self.ingame_ui_context` there is nil and crashed the view construction, so the transition-time lazy `_attach_view` is the guaranteed path). The Mod Tweaker view is a `class()` that BORROWS the IngameUI renderer (never creates one), registers a modal input service, and exits via `transition_with_fade("ingame_menu")`. The per-tab
label policy is engine-free presentation data shared by both presentations through
`_mod_tweaker_tab_labels.lua`; its `mp` to `PROGRESSION` mapping (#525) changes neither
Modded Progression's VMF name/settings nor the #573/#578 progression systems, and adds no
localization or engine hook. Profile persistence remains engine-free. For #919,
`_mod_tweaker_profile_events.lua` adds one replaceable diagnostic observer per tab;
both presentation owners emit `{tab_id, slot, phase}` only after the target profile
transaction has applied. The owner then reads its own domain values. This API adds no
hook, update callback, setting payload, or network traffic, and a throwing observer is
contained. The per-tab search bar (#497/#559) adds NO engine seam: it is a
fixed `mt_search` widget above the (shrunk)
`list_mask`, focused on click, fed by `Keyboard.keystrokes()` (the same raw path the numeric
type-to-edit uses, chat-blocked via `ChatManager.block_chat_input_for_one_frame`), and applied
as a filter STAGE inside the view's own `_build_rows` row-rebuild pipeline (flat render of
label-matching nodes + their ancestors + matched-group descendants) -- not a hook. Its #572
magnifier is the exact atlas-backed `search_filters_icon` material used by
`HeroWindowCraftingInventoryConsole` [src: `hero_window_crafting_inventory_console_definitions.lua:503-504,779-796`].
The atlas entry is a padded 128x128 tile. Mod Tweaker renders the tile at 95x95 (15% smaller than the
prior 112px pass) and x=-28/y=0, placing its visible glyph at approximately x=8..32 wholly inside the
30px field while text retains x=47. The empty prompt is `Search <active tab label>`, sourced from the
same rendered tab widget rather than a duplicate label map. The view mirrors `_search_focused` into widget content each
frame; the texture pass draws only while unfocused. It remains passive, and the original full-field
hotspot is still the only input target. Filter rendering is
transactional: `_mod_tweaker_search.lua` snapshots the selected tab's persistent expansion set on
the first non-empty query, filtered group rows use a display-only expanded flag, and clear/Escape/
neutral click/tab switch/menu exit restore the snapshot. A clicked result instead commits its ancestor
group chain; auto-collapse ON replaces the tab's old branches, while OFF restores them before adding
the required ancestors. No arbitrary top result is selected. Numeric-editor caret geometry follows the
native text pass: `UIFontByResolution` resolves scaled material/size, `UIRenderer.text_size` receives
`style.font_type`, and centered X subtracts the measured glyph origin before adding the measured prefix
advance [src: `scripts/ui/ui_passes.lua:1964-1990,2177-2181`; `scripts/ui/ui_renderer.lua:1254-1260`].
Clicks choose the nearest measured insertion boundary rather than estimating by character count, so signs,
decimal points, proportional digits, and UI scale share one contract. Two ESC-menu surfaces sit here: the button LABEL is supplied as backend-localization DATA (not a `Localize` hook - the global is rawset-replaced on init and the button localizes through the sibling `simple_lookup`), and the modern keep menu's button column (`HeroWindowIngameView._update_presentation` [src: `hero_window_ingame_view.lua:490-515`]) is compacted because gut's own Mod Tweaker button pushes it to overflow. The keep also hosts the injected Bestiary/Armory compendium via HeroView sub-states and the in-mission keep-inventory console windows (`docs/engine/06` owns the inventory/preview seams).

#272's scoreboard inventory is currently observation-only. `_gut_diagnostics.lua`
chains the existing VMF lifecycle callbacks (no engine hook), inventories
`ScoreboardHelper.scoreboard_topic_stats`, and takes at most one delayed live
snapshot after `StateIngame` becomes ready. It calls the same
`get_grouped_topic_statistics` source used by the end screen [src:
`scripts/helpers/scoreboard_helper.lua:344-436`] and caps the process at four
records. It neither intercepts Tab input nor adds a network channel; the phased
UI and custom-stat ownership decisions live in `SCOREBOARD_RESEARCH_272.md`.

#437 adds the missing Adventure disconnect lifecycle without changing scoreboard
rendering or transport. On the server only, `_gut_scoreboard_retention.lua` wraps
`StatisticsDatabase.unregister` to read ScoreboardHelper's exact leaf paths before
vanilla deletes `statistics[id]` [src: `statistics_database.lua:164-174`], then
post-hooks `register` to restore those non-persistent values after vanilla creates
the empty row [src: `:150-162`]. This mirrors Deus' explicit
`save_persisted_score` / `restore_persisted_score` boundary [src:
`game_mode_deus.lua:50,205,216-219`; `deus_run_controller.lua:779-806`] but is
gated to an active Adventure `StateIngame` host. Storage is mission-local, keyed
by the same stable `stats_id`, capped at 8 players x 64 paths, cleared on exit,
and adds no RPC; progression/backend statistics are never copied.

## What the engine will NOT let us do (dead ends, already paid for)

Distilled from the module headers and `docs/BUG_CLASSES.md` - do not re-discover.

- **A `mod.update`-chained tick cannot safely touch the free-flight world unconditionally.** It ticks through `StateIngame` teardown where the world is gone; `WorldManager.world` FASSERTS on a missing name and a viewport into a freed world is uncatchable. Route every lookup through a `has_world` gate (§32); the free camera never caches a world handle.
- **You cannot fix the post-cutscene 1P restore by leaving the 3P-camera block always-on.** A cutscene's END path restores 1P through the same `set_first_person_mode(active, override=nil)` shape the block swallows, so the block MUST yield while `CutsceneSystem:is_active()` [src: `cutscene_system.lua:83-85`]. And you cannot globally unlock cutscene skipping: a boss/phase cinematic with `event_on_skip=nil` desyncs the fight if skipped, so only a cutscene carrying a wired `event_on_skip` may be unlocked, scoped to the `skip_pressed` call (#275).
- **The mirror write hooks must NO-OP vanilla, not "write then also push."** The isolation guarantee is that `_career_data`/`_characters_data` stay unmutated so the diff-based cloud commit finds nothing dirty; character-data pushes are NOT eac-gated, so any pass-through would leak modded loadouts onto official cloud data (#175). Correspondingly, a store gear id that will not resolve right now must NEVER be sanitized out - synthetic cim/LA/cosmetics ids register late and a nulled weapon slot fatals at spawn.
- **Never resolve an item id via `iface:get_item_from_id` from inside a mirror read.** It calls `_refresh` when dirty, which re-enters the mirror read = unbounded recursion -> ~1 GiB `lua_heap` exhaustion (v0.2.173, surfaced at `cosmetics_tweaker.lua:1513`). Read the raw source tables (`_items` when clean, `_inventory_items` + the game-mode overlay when dirty) with plain field indexing.
- **You cannot capture LA-routed menu equips at the mirror.** Loremaster's Armoury clones the item interface, and the clone's copied methods bypass the `PlayFabMirrorAdventure` class hook, so gear equips never reach `set_character_data` - capture at the stable OUTER `BackendUtils.set_loadout_item` entry point instead, table-form against the post-LA reference (memory `reference_cim_equip_capture_la_dispatch`).
- **The HUD drag baseline is not {0,0}.** Real HUD widget nodes baseline at their vanilla `local_position` (equipment_ui pivot {0,69}, buff_ui pivot_root {150,18}, boss_health pivot_parent {0,-72}), so writing a raw drag offset zeros the baseline and snaps the widget to screen origin - always write baseline + delta (v0.2.8 F5).
- **`IngameUI.setup_views` runs BEFORE `self.ingame_ui_context` exists.** Reading `self.ingame_ui_context` in the post-hook is nil (it is set at `ingame_ui.lua:138`, after `setup_views` at `:107`), which made `ModTweakerView:new` throw and crashed `IngameUI` on transition to the missing view. Capture the context ARG; treat the transition-time lazy attach as the guaranteed path.
- **The ESC "Mod Tweaker" label cannot be fixed by hooking the localizer.** `_G.Localize` is rawset-replaced in `LocalizationManager.init`, and the button localizes through `simple_lookup` (a sibling of `lookup`), so both interception hooks miss a path. SUPPLY the string into `_backend_localizations` [src: `localization_manager.lua:50-51`], the shared bottom of both paths - data, not a wrapped closure.
- **The `#194` `script_data` "mod-env shadow" class cannot fire in retail (#496 disproof).** The shadow needs `_G.script_data` to be nil when a mod first assigns the bare name - impossible: `boot.lua:4` dofiles `boot_init` which creates it [src: `boot_init.lua:79`; also `application_parameter.lua:5`] long before `ModManager:new` [src: `boot.lua:404`] loads any mod. Nor is there a sandbox to divert the write: the native loader is bare `loadstring`+`pcall` [src: `mod_manager.lua:375,386,162`] and VMF loads mod files via plain `dofile` with no `setfenv` anywhere (vmf `vmf_mod_manager.lua:39` -> `safe_calls.lua:71-79`) - proven empirically because VMF's own dofile'd `new_mod`/`get_mod` globals (`vmf_mod_manager.lua:74,110`) are visible to every `.mod` chunk. The only wholesale `script_data` replacement is boot-time, non-release + `-use-clean-settings` gated [src: `application_parameter.lua:152-158`]. So `_gut_monologue.lua:19-20` reliably mutates the table `state_loading.lua:585/:635` reads; #194's changelog root-cause narrative was wrong (its fix worked via the per-tick `_handle_bots` enforce hooks). `rawget(_G,"script_data")` remains fine style, but is not load-bearing.

## #749 borrowed-renderer residency boundary

The singleton `UIRenderer.create` hook is a global boundary, not an owned draw.
Its V2 filter drops only material pairs whose absence is positively proved and
preserves original vanilla/third-party/Pusfume arguments when the probe is
missing, throwing, or indeterminate. GUT-owned injections still require strict
positive material proof.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a gut hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. Line numbers are against the 2026-07-12 decompile and `gut_dev`
module source - match crash logs by function name, not line. This documents
`gui_tweaker_dev` (the active dev stream); never cite stable `gui_tweaker/` line
numbers - promotion is user-triggered and the two streams drift. Structural
template is `character_weapon_variants/ENGINE_SURFACE.md`; keep the section shape
(hook table -> subsystem notes -> dead ends) stable.
