# MECHANICS.md — provenance-enforced game-mechanics substrate

This is the repo's **grounded** index of how VT2 / Stingray mechanics actually
work. It is NOT a tutorial and NOT written from anyone's recollection. Every
factual bullet carries a **provenance tag** proving where the claim came from.
`qa/check_mechanics_citations.ps1` fails the build on any untagged factual
bullet, so a claim cannot land here without a source.

> **Why this exists.** The recurring failure mode is: a session drifts on how a
> mechanic works, hallucinates to fill the gap, and the wrong claim propagates.
> The cure is a substrate that only accretes GROUNDED inputs. An entry that says
> `[unverified]` is the CORRECT state when no grounded source exists — it is an
> honest gap, surfaced and counted, never a hidden one. Filling a gap from model
> knowledge is the exact disease this file is engineered against.

## Relationship to the rest of the doc tree

This is an INDEX of grounded mechanics, not a fourth wall of prose. Where a fact
already lives in a memory note, `docs/BUG_CLASSES.md`, or the decompiled source,
the entry **points** to it rather than restating it.

- **MECHANICS.md (this file)** — "what is true about the engine/game, and how do
  we know." Greppable by domain.
- **Memory store** (`~/.claude/.../memory/`) — "how WE work" + cross-cutting
  observations. Many `reference_*` / `feedback_*` notes already cite ground
  truth; entries here carry a `[memory: <note>]` pointer to those.
- **`docs/BUG_CLASSES.md`** — symptom→mechanism→fix with Issue/commit citations.
  Mechanism facts are carried here with their citations.
- **`Vermintide-2-Source-Code/`** — the gold standard. `[src: file:line]` entries
  were opened and verified at the cited line.

## Provenance schema (MANDATORY on every factual bullet)

Every factual claim/bullet MUST carry exactly one tag:

| Tag | Tier | Meaning |
|---|---|---|
| `[src: <path>:<line>]` | gold | Verified by opening the decompiled source at that line. |
| `[dump: <file>]` | high | Captured from an in-game runtime dump (e.g. `ANIMATION_RESEARCH.md`, a gt name-dump). |
| `[memory: <note-name>]` | mid | Carried from a memory note that itself cites ground truth. |
| `[bugclass: §N]` | mid | Carried from a `docs/BUG_CLASSES.md` entry (which carries Issue/commit citations). |
| `[user: YYYY-MM-DD]` | low | The maintainer stated it. FLAG for source-confirmation; promote to `[src]` when found. |
| `[unverified]` | none | Explicitly NOT yet grounded. ALLOWED by the lint, but COUNTED and reported as a known gap. |

Non-factual lines (headings, prose framing, the "Domain:" labels, table column
headers) are not bullets and are not linted. Only `-` bullets that state a
mechanic need a tag.

The substrate is APPEND-mostly. Entries get PROMOTED up the tiers
(`[user]` → `[src]`) as they are confirmed. They are never silently invented.

---

## Domain: Lua / Stingray engine quirks

- `class(child, super)` COPIES every non-special key from `super` into `child` at
  class-definition time; there is no `__index` chain, so later replacing a method
  on the parent table does NOT affect a child defined earlier. [src: foundation/scripts/util/class.lua:51-57]
- The copy loop skips only `__index`, `delete`, `new`, `super` (the
  `special_functions` set). Everything else, including all methods, is copied by
  reference into the child at definition time. [src: foundation/scripts/util/class.lua:9-14]
- Consequence for hooking: hook the DERIVED class that is the runtime type, never
  the base. `MenuWorldPreviewer = class(MenuWorldPreviewer, HeroPreviewer)` runs
  at game load, before any mod, so by the time VMF replaces a `HeroPreviewer`
  method the `MenuWorldPreviewer` copy is already independent. [src: scripts/ui/views/menu_world_previewer.lua:7]
- `Unit.node(unit, name)` raises an ENGINE-level fatal (not a Lua error) when the
  node is absent, so `pcall` does not catch it; use the `Unit.has_node(unit, name)`
  boolean companion for existence checks. [memory: (CLAUDE.md § High-frequency engine quirks)]
- `Quaternion` / `Vector3` / `Matrix4x4` returns are stack temporaries valid only
  within the current frame; store via the `*Box` wrappers and `:unbox()` at apply
  time. [bugclass: §12]
- Lua 5.1 hard limit: 200 locals per function (including the top-level chunk);
  wrap helper groups in `do ... end` to release their locals. [bugclass: §11]
- Lua 5.1 `#t` is undefined for arrays with nil holes (binary boundary search), so
  bare `unpack(t, i)` past a nil truncates non-deterministically; capture real
  arity with `select("#", ...)` and pass an explicit `j`. [bugclass: §3]

## Domain: Inventory / Equipment

- `SimpleInventoryExtension.init` sets `self._career_name = career_name` at line 47,
  BEFORE `extensions_ready` fires — so in-mission spawn hooks should read career
  from this field, not from `Managers.player:owner(unit):career_name()` (the
  unit→player reverse association is not yet established at spawn timing). [src: scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:47]
- `GearUtils.create_equipment` (line 273 branch) returns the 4-tuple
  `(weapon_unit_3p, ammo_unit_3p, weapon_unit_1p, ammo_unit_1p)`; for melee
  weapons the two `ammo_*` slots are nil, producing the nil-hole tuple behind the
  unpack-truncation bug class. [src: scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:273]
- `SimpleInventoryExtension` (self-owned) and `SimpleHuskInventoryExtension`
  (remote peers) are registered as SEPARATE extension entries with no inheritance
  between them; a hook on one does not fire for the other. [src: scripts/network/unit_extension_templates.lua:13]
- The husk-side equivalent entries for inventory live at the same file's husk
  registration block (lines 71, 90, 264, 290, 371). [src: scripts/network/unit_extension_templates.lua:71]
- `HeroPreviewer` / `MenuWorldPreviewer` slot keying is split: `_item_info_by_slot`
  is string-keyed (`"melee"`/`"ranged"`), `_equipment_units` is numeric-keyed
  (`slot_index`); bridge via `info.spawn_data[1].slot_index`. [memory: (CLAUDE.md § Three Weapon Rendering Paths)]
- The runtime keep inventory previewer instance is `MenuWorldPreviewer`, not
  `HeroPreviewer`; `HeroPreviewer` itself is only instantiated by
  `team_previewer.lua`. [memory: feedback_inventory_preview_hook_menuworldpreviewer]
- cim's loadout-restore must hook `BackendUtils.set_loadout_item` (table-form,
  deferred), not just `BackendInterfaceItemPlayfab` — LA routes menu equips through
  a clone that bypasses the class hook. [memory: reference_cim_equip_capture_la_dispatch]
- The full cim recipe→synth→craft→mirror→persistence flow (including
  `_forged_weapons` + `_modded_loadout` and the cross-mod API) is mapped in its
  memory note; read it before touching the craft path. [memory: reference_cim_weapon_crafting_flow]
- A base `ItemMasterList` weapon-TYPE key's own `display_name` / `localized_name`
  is the DEFAULT COSMETIC SKIN's name, NOT the weapon-type name: e.g.
  `ItemMasterList.dr_2h_pick.display_name = "dw_2h_pick_skin_01_name"` ("…Azdrek")
  and `ItemMasterList.es_handgun.display_name = "es_handgun_skin_03_name"`, with
  `item.localized_name = Localize(item.display_name)` precomputed at boot. So
  ItemMasterList holds BOTH weapon types AND cosmetic skins/illusions, and
  `localized_name` on a base key is cosmetic-grade — UNSAFE as a weapon-TYPE
  label. Key any "what weapon TYPE is this" UI on a curated key→type map (wt's
  `_WEAPON_NAME`), not on `localized_name`. Same trap as the vs_* cosmetic-grade
  display strings below. [src: scripts/settings/equipment/item_master_list_exported.lua:7500 (dr_2h_pick), :6797 (es_handgun); scripts/settings/equipment/item_master_list.lua:115 (localized_name = Localize(display_name))]

## Domain: Networking / RPC

- Direct widening of network-bounded resource maxes (`_max_overcharge`,
  `_max_energy`, `_max_ammo`, etc.) crashes peers via fassert — these caps are
  hardcoded in the engine `.network_config`; buff resources via consumption-side
  stat_buffs (`reduced_overcharge`, `ammo_used_multiplier`) instead. [memory: feedback_vt2_max_resource_consumption_side]
- Downward CLAMPS of `_max_*` (a `math.min(...)` RHS, or guarded
  `if X > CONST then X = CONST end`) are SAFE; only bare upward assignments crash. [bugclass: (CHECKS.md row 7f)]
- Stingray `EventManager:register(object, event_name, callback_name)` requires the
  3rd arg to be a STRING method name on `object`; a function value makes the
  engine emit `No function found with name '[function]'` and the handler silently
  dies. [bugclass: §3b]
- `Managers.state.event` is REBUILT on every state transition (StateInGame /
  StateLoading / StateTitleScreen); event registrations must be re-applied on each
  fresh handle. [bugclass: §3b]
- VMF `mod:network_send(channel, "server", ...)` silently drops the send;
  resolve the host peer_id explicitly (e.g. `Managers.account:peer_id_of_host()`). [bugclass: §15]
- RPC payload shape changes across mod versions corrupt receivers parsing by
  position; gate every RPC on a per-mod `<MOD>_RPC_SCHEMA` first positional arg. [bugclass: §9]
- VMF RPC string payloads are capped at 500 chars by a Stingray hardcap; chunk
  longer payloads. [memory: reference_vmf_rpc_string_cap]

## Domain: Spawning / Conflict-Director

- `HordeCompositionsPacing` entries each carry a `loaded_probs` field built from
  variant weights via `LoadedDice.create` at `conflict_settings.lua:636`
  file-load time; `horde_spawner.lua` reads `composition.loaded_probs` at lines
  139/243/349/743 — replacing a composition without rebuilding `loaded_probs`
  crashes `LoadedDice.roll_easy` on the next horde. [src: scripts/settings/conflict_settings.lua:636]
- Hook wrappers over spawn/composition functions must capture ALL returns; these
  functions commonly return 2-3 values and a `return wrapper(func(...))` collapses
  all but the first (e.g. `HordeSpawner.compose_blob_horde_spawn_list`'s
  `num_to_spawn`). [bugclass: §2]
- Adventure-injected levels crash on the `no_roamers` mutator; ct strips
  incompatible mutators as the mitigation. [memory: reference_vt2_adventure_pack_spawning_compat]
- Vanilla `NetworkedFlowStateManager` leaks and fatals at 512 states; ct patches
  it via `mod:hook`. [memory: reference_vt2_networked_flow_state_leak]

## Domain: Animation / 3P

- 1P animations are universal across all six characters (the `first_person_base`
  unit is shared); only the 3P body is character-specific and needs cross-character
  remap work. Never override `anim_event` / `wield_anim` / `state_machine` per
  character. [memory: feedback_1p_animations_universal]
- Universal does not mean automatically resident: `ProfileSynchronizer` derives
  first-person state-machine packages from the backend loadout visible during its
  inventory-list pass, so a later modded resync can wield a different template
  against a stale package list. Any cross-character state machine used across that
  boundary needs a source-verified, mod-owned synchronous residency lease before
  `PlayerUnitFirstPerson.set_state_machine`; that engine call is not a recoverable
  `pcall` seam. [src: scripts/game_state/components/profile_synchronizer.lua:71-175]
- The local player uses two units: `player.player_unit` is the 3P body (receives
  `anim_event_3p`, character-specific skeleton — remap lives here); a separate
  non-player unit is the 1P hands (receives `anim_event`, universal). [memory: (CLAUDE.md § Animation Remapping)]
- Per-weapon 3P skeleton event-vocabulary probe results across the six character
  bodies are recorded data, not inference. [dump: ANIMATION_RESEARCH.md]
- `wield_anim_career_3p` is NOT read by the engine — it was an invented field with
  no consuming code path (confirmed dead during the monolithic-tweaker era). [dump: ANIMATION_RESEARCH.md]
- The mutator template `server_*_function` fields are dead as written; the engine
  wraps them into `template.server.start_function` (etc.) at boot, so hook the
  wrapped form. [memory: reference_vt2_mutator_template_server_wrap]

## Domain: Cosmetics / Illusions

- The `weaves` material-settings shape (vanilla
  `weapon_material_settings_templates.lua:52`) requires all five vector3 channels
  (`color_glow_high`/`color_glow_low`/`color_smoke_high`/`color_smoke_low` + one
  more) to be present; the per-instance glow popup depends on this exact shape. [src: scripts/settings/equipment/weapon_material_settings_templates.lua:52]
- Adding a runtime weapon skin requires injecting into three tables
  (`ItemMasterList[skin_key]`, `WeaponSkins.skins[skin_key]`,
  `WeaponSkins.skin_combinations[...]`) then hooking
  `get_unlocked_weapon_skins` + `_G.Localize`. [memory: (CLAUDE.md § Custom Illusion Injection)]
- To add buttons/popups to a hero-view menu, build an OWN-scenegraph overlay drawn
  off the host window's `_draw` hook; never inject `create_default_button`
  anchored to a host viewport node. [memory: reference_vt2_menu_button_overlay_pattern]
- Strict-lookup global tables (`ItemMasterList`, `NetworkLookup.weapon_skins`,
  etc.) install an `__index` metamethod that raises a crashify exception on a
  missing key; read via `rawget` to bypass it. [bugclass: §4]

## Domain: Store / progression UI

- The Emporium panel calls `_sync_player_wallet` during its native update, but rebuilds wallet widget text and geometry only when a `get_chips` value differs from its cached `_currencies` entry. [src: scripts/ui/views/hero_view/windows/store/store_window_panel.lua:169-176,601-652]
- The Emporium item preview treats a changed product-version id as a force-refresh; `_sync_presentation_item` then recalculates `can_afford` through the parent store state's wallet read before setting the purchase-button state. [src: scripts/ui/views/hero_view/windows/store/store_window_item_preview.lua:401-443,872-993]
- `BackendUtils.get_fake_currency_item` clones the selected `Currencies` entry and returns that clone plus its item key and reward-description localization key, so per-call presentation metadata can be changed without mutating the global currency catalog. [src: scripts/managers/backend/backend_utils.lua:326-348]

## Domain: Careers / Talents / DLC gating

- Chaos Wastes initial talents are stored as generic `talent_<tier>_<column>`
  power-ups; `_add_initial_power_ups` materializes the selected tier/column rows
  before event boons, while `DeusPowerUpUtils` resolves each generic identity to
  the current career's talent name and icon through `TalentTrees`/`TalentIDLookup`.
  [src: scripts/managers/game_mode/mechanisms/deus_run_controller.lua:471-495; scripts/helpers/deus_power_up_utils.lua:259-322]

- Closing either vanilla talent picker unconditionally writes the selected rows,
  calls `TalentExtension:talents_changed()`, and reapplies ammo buffs, even when
  no row changed; `talents_changed()` then reaches `apply_buffs_from_talents`,
  which clears all prior talent buffs before rebuilding them. [src: scripts/ui/views/hero_view/windows/hero_window_talents.lua:53-74; scripts/ui/views/hero_view/windows/hero_window_talents_console.lua:67-88; scripts/unit_extensions/default_player_unit/talents/talent_extension.lua:48-101]

- The DLC id for gated content lives on the master entry's `required_dlc` field;
  the vanilla gate is `Managers.unlock:is_dlc_unlocked(required_dlc)`, pre-checked
  with `dlc_exists` to avoid the fassert at `unlock_manager.lua:527`. [src: scripts/settings/dlc_settings.lua:274]
- event_tweaker's DLC-by-mutator/preset ids were taken from `dlc_settings.lua`:
  `:274` (geheimnisnacht_2021), `:576` (geheimnisnacht_2025), `:287`
  (skulls_2023). [src: scripts/settings/dlc_settings.lua:274]
- `vs_*` ItemMasterList keys are Versus-carousel items (`mechanisms={"versus"}`);
  they craft into the mirror but the Adventure grid filters them out at the
  `get_filtered_items` layer — debug the filtered layer, not
  `get_all_backend_items`. [memory: reference_vt2_versus_items_hidden_in_adventure]
- `DeusPowerUp` rarities are limited to event/rare/exotic/unique only. [memory: reference_vt2_deus_power_up_rarities]

## Domain: VMF framework

- VMF silently DROPS the second `mod:hook` / `mod:hook_safe` on the same
  `(Class, method)` pair from the same mod; consolidate concerns into one callback. [bugclass: §1]
- VMF stores all settings under one flat
  `Application.set_user_setting("mods_settings", <table>)` keyed by mod_name then
  setting_id; read-only fallback is
  `Application.user_setting("mods_settings", mod_name, setting_id)`. [memory: reference_vmf_persistence_namespace]
- Valid VMF widget `type` values are exactly `group` / `header` / `checkbox` /
  `dropdown` / `numeric` / `keybind`; any other value (e.g. `text_input`, `slider`,
  `string`) breaks the whole mod's options init at load. [bugclass: §18]
- VMF numeric widgets have no `step` field; stepping coarser than 1 (or
  `10^-decimals_number`) is impossible in stock VMF. [memory: reference_vmf_numeric_widget_no_step]
- `mod:set` from `on_setting_changed` updates the store but NOT the currently-open
  widget; mutex/dependent-checkbox patterns only refresh on view re-open. [memory: reference_vmf_checkbox_cached_display_state]
- Child-window `update` hooks fire BEFORE `_widgets` / `_widgets_by_name` are
  populated; drive per-frame widget mutations from the PARENT state's `update`. [memory: reference_vt2_widget_timing_pattern]

---

## Known gaps (intentionally `[unverified]` — the honest backlog)

These are mechanics that have come up but for which NO grounded source was found
or opened during seeding. They are placeholders ON PURPOSE. Do NOT fill them from
model knowledge — grep the decompiled source, capture a dump, or get a maintainer
statement, then promote.

- Exact `ConflictDirector` spawn/pacing pipeline entry-point function names and
  their call order (intensity → pacing → horde compose → spawn). Not yet opened in
  `scripts/managers/conflict_director/conflict_director.lua`. [unverified]
- The precise `NetworkConstants` field names and numeric caps for each bounded
  resource (overcharge/energy/ammo/health/stamina/push_power). The memory note
  establishes that caps exist and crash on widening, but the exact constant table
  and values have not been read out of source. [unverified]
- Whether `Unit.actor` / other `Unit.*` engine APIs share the exact same
  pcall-bypassing fatal behavior as `Unit.node` (the `has_*` companion rule is
  asserted generally but only `Unit.node` is confirmed). [unverified]
- The fifth required `weaves` vector3 channel name (four are enumerated from the
  cosmetics code comment; the full five-field list at
  `weapon_material_settings_templates.lua:52` was not read out). [unverified]
