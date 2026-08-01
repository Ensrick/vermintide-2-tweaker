# Crafting in Modded Changelog

## 0.8.92 (2026-08-01) - #48 custom-glow fallback notice [verify-fix]

- When saved CIM weapons contain opaque custom-glow data but Tweaker:
  Cosmetics is absent, log one bounded informational notice per session and
  retain the vanilla material appearance. CIM still never interprets or
  renders the blob.
- The provider lookup fails closed and remains retryable; repeated forge-load
  passes cannot spam the log.

## 0.8.91 (2026-07-17) - PUBLIC RELEASE: full dev rollup (0.8.34 to 0.8.91)

Promotes the entire dev line since the 0.8.34 wire-safety hotfix. New crafting-flow
features, a large batch of forge and CWV crafted-identity fixes, and the always-on
craft-path instrumentation (issue 682) now ship to the public build.

### Features
- Newly crafted weapons auto-equip by default (issue 562).
- Forge freedom toggles: allow any trait and property on any weapon, and allow Chaos
  Wastes traits on crafted weapons (issue 414, issue 44).
- Modded salvage autofill for the standard bench (issue 618).
- /forge_delete_all bulk cleanup command (issue 277).
- Keep forge stays interactable in the modded realm (issue 624).
- Optional Weapons of Chaos Poisoned Edge trait (issue 655).
- Base Power level slider is now honored on new crafts.
- Accessory craft button gives clear success feedback.
- In-mission Athanor crafting, behind a GUI Tweaker opt-in (issue 83).
- Settings sorted A to Z, with plain-English option descriptions.

### Fixes
- Athanor shows literal property values (issue 244).
- Hold-Tab illusion icon renders correctly (issue 246, issue 598, issue 629, issue 641).
- Vanilla illusion choices persist on modded items (issue 563).
- CWV crafted items keep their variant identity and render as the variant (issue 390,
  issue 392, issue 524, issue 592, issue 628, issue 484).
- Console craft no longer errors on a nil recipe (issue 407).
- CWV Blacksmith selector fixed (issue 524).
- Athanor icon closure no longer crashes (issue 617).
- Hover popup fixed (issue 521).
- Cost and trait display corrected (issue 238, issue 239).
- Modded upgrade copy fixed (issue 263).
- Weapons of Chaos relic is immutable where required (issue 637).
- Old Musket preview gate fixed (issue 474, issue 481).

### Instrumentation
- The always-on craft-path probes from the dev line now ship in stable (issue 682).

### Files
- Full source port (9 updated Lua files + 20 new feature modules) with identity
  re-stamped to cim / crafting_in_modded; MOD_VERSION set to 0.8.91; the
  store_tag_icon_weapon_modded material/texture added to the resource package.
  itemV2.cfg published_id and public visibility unchanged.

## 0.8.34 (2026-07-07) — HOTFIX: default cim host CTDs non-cim clients on any crafted-item equip (issue 278)

Targeted crash hotfix promoted from cim_dev v0.8.54-dev — ONLY the wire-safety fix
below; no other in-flight dev work is included.

- SYMPTOM (issue 278): a cim host crashes every player in the lobby who does NOT have
  cim, the moment the host equips a crafted item. Reproduces with DEFAULT settings, so
  it hit users broadly.
- ROOT CAUSE: the sender-side wire-safety rewrite (swap a crafted item's "modded"
  rarity to a vanilla "unique" before `LoadoutUtils.sync_loadout_slot` encodes the
  loadout RPC) was bundled behind `persist_modded_loadouts` (DEFAULT OFF) by the
  v0.8.15 master gate. With the toggle off the hook is a pure pass-through, so
  `rarity_id = NetworkLookup.rarities["modded"]` goes on the wire. Every crafted item
  carries "modded" rarity (modded_rarities.lua:212); that id is undefined on a non-cim
  client, which reverse-looks-up nil and fatals at `RaritySettings[nil].order`
  (loadout_utils.lua:73). Wire crash-safety was wrongly coupled to a persistence feature.
- FIX: hoist the "modded"->"unique" wire rewrite OUT of the persist gate — it now runs
  UNCONDITIONALLY whenever a "modded" item is synced (single-sourced in the pure helper
  `_cim_wire_safe_rarity`). Only the cim<->cim `cim_modded_slot` side-channel (which
  restores modded chrome on cim clients; vanilla drops it) stays gated. Wire safety is
  now independent of every toggle, per the issue-371 mandate (no mod may ever crash a
  peer that lacks it).
- REGRESSION: `/cim_regression_test` -> `wire_rarity_rewrite_ungated`.

## 0.8.33 (2026-06-29) — PUBLIC RELEASE: the complete Athanor property/slot fix (#86) + full dev rollup

Promotes the entire `crafting_in_modded_dev` line (through 0.8.33-dev) to the public build. The headline is the **finally-correct #86 fix** — the 0.8.9 public build only had a partial stamina-key fix; the real blocker turned out to be a hard 2-distinct-property ceiling.

### Fixed #86 — the Athanor property grid, properly this time

The public 0.8.9 fix re-keyed the stamina bubble-cap but the symptom persisted because the actual blocker was a **2-distinct-property ceiling** enforced in three places (an add-time gate, a destructive load-time trimmer that clobbered extra properties on every restart, and the per-property slot reservation). All three are now raised to the grid's real ceiling.

- **Stamina** = 2 slots, **Movement Speed** = 1 slot, **every other property** = its full 5-bubble range (1 bubble = 20%, 5 = full — vanilla weave behavior). `movespeed_2pct_mode` still uncaps movespeed to 5 by design.
- **The "max 2 properties per item" wall is gone** — up to 10 distinct properties per weapon/accessory layer. The grid's 10 slots are a shared budget, so you trade off: more distinct properties at fewer bubbles each, or fewer maxed-out ones.
- A dev over-correction (briefly capping every property to a single bubble) was caught and reverted before this release; regression test `default_property_cap_is_five_bubbles` pins the default at 5 with scaling.

### Also rolled up from dev since 0.8.10

- The full #86 investigation chain (takes 3–6) and the read-/write-path slot-occupancy guards.
- `/cim_regression_test` coverage for #96 (gut-gated in-mission option) and the property-cap behavior.
- All prior dev hardening already present in 0.8.8/0.8.9 stays in place (in-mission Athanor Keep-only, loadout persistence opt-in/default-off, Versus-weapon grid fixes, in-mission forge crash guards, Trollhammer/CW-weapon forge-editor crash fixes).

### Files
- Full source port from `crafting_in_modded_dev` (9 Lua files) with identity re-stamped to `cim` / `crafting_in_modded`; `MOD_VERSION` → `0.8.33`; `itemV2.cfg` title + description refreshed (published_id and public visibility unchanged).

## 0.8.10 — 2026-06-28
- Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.8.9 (2026-06-24) — PUBLIC RELEASE: stamina slot fix (#86) + ESC-backout inventory leak fix (#88) + gut-gated in-mission option (#96)

Promotes three confirmed dev fixes to the public build. The in-mission Athanor stays Keep-only (unchanged from 0.8.8). All dev-only "[untested]" option labels were stripped on this public version.

### Fixed #86 — the Stamina property consumed 5 inventory slots instead of 2

Adding the Stamina property in the Athanor consumed 5 of the 10 property slots instead of exactly 2, blocking a second property even though the 2-distinct-property cap should have allowed it. Root cause: the per-property bubble-cap table was keyed by the bare name (`stamina`/`movespeed`), but the weave UI passes the category key `weave_properties_stamina`, which the strip helper reduces to `properties_stamina` — so the cap lookup missed and fell back to the default 5. That default-5 drove the slot count (`get_property_mastery_costs`), the persisted slot-index array, and the value/seed math. Re-keyed the table to `properties_stamina = 2` / `properties_movespeed = 1` (the post-strip key). Stamina now uses exactly 2 slots; movespeed 1 (5 with the 2pct toggle).

### Fixed #88 — backing out of the in-mission ESC menu pulled up the loadout inventory

The in-mission standard crafting bench enabled loadout/inventory access by flipping `InventorySettings.inventory_loadout_access_supported_game_modes` permanently and never restoring it. The single vanilla read site is `HeroView.on_enter`, so a persistent flip made every later HeroView open in the mission — including the ESC-menu backout — read the mode as supported and init the loadout inventory mid-mission. Fixed by scoping the flip to cim's own view open: a one-shot flag set before cim's transition, plus a `HeroView.on_enter` hook that saves the original values, lets vanilla read the flipped ones, then restores them. The ESC-menu HeroView now reads the untouched vanilla table and bails — no leak. The standard bench still opens in-mission.

### Changed #96 — "Allow standard crafting bench in mission" option hidden when GUI Tweaker isn't installed

The `allow_in_mission` option only does something useful when GUI Tweaker (gut) supplies the in-mission menu access, so its checkbox is now hidden in cim's settings when gut isn't installed. VMF has no native conditional-widget feature, so the widget is conditionally built: a load-order-safe presence check (`get_mod("gut")` plus a scan of the engine ModManager mod manifest by Workshop title) prunes the entry when gut is absent. When gut is present, nothing changes.

## 0.8.8 (2026-06-24) — PUBLIC RELEASE: promote the dev crafting fixes; the in-mission Athanor is Keep-only on this build

Public-stable promotion of the `crafting_in_modded_dev` work through v0.8.22-dev. Standard (Keep Smithy) crafting and the Keep Athanor are the confirmed-working surfaces; the **in-mission Athanor (weave forge) is deliberately disabled** on the public build because its mid-mission crash class is not subscriber-safe yet.

### In-mission Athanor disabled (Keep-only) — the headline safety change

`mod.open_forge` (the Athanor / `weave_forge` state) now **hard-requires the Keep / Chaos Wastes hub** and no longer honors the `allow_in_mission` toggle. It cannot open mid-mission via the forge hotkey on this build. This walls off the HDR-glow / `Material not found` / `ui_store_preview` mid-mission fatal class (Issues #81/#83) that the dev clone is still hardening. The Keep Athanor is fully functional and unchanged.

- `allow_in_mission` now governs **only** the standard crafting bench in missions; its label/description were rewritten to say so. The `forge_hotkey` label/description were rewritten to "Keep only".
- The in-mission crash-fix hooks promoted from dev (Fix B/B2..B6) remain in the code but are inert on the public build (the only in-mission entry that reached them is now gated). They stay so a future re-enable is a one-line gate change, not a re-port.

### Promoted from dev (v0.8.7-dev .. v0.8.22-dev)

- **Standard crafting bench in-mission (material-clean)** — new `open_standard_crafting` entry point opens the vanilla Keep Smithy bench (salvage / craft / re-roll properties + traits / upgrade rarity / apply illusion / convert dust) mid-run. Renders cleanly (flat atlas widgets, no preview world, no HDR/shading shims). New `Standard Crafting` hotkey (default unbound) + `/cim_craft_standard` chat command. Adventure/survival only (Chaos Wastes is loadout-locked). Honors `allow_in_mission`. (0.8.21-dev)
- **Owned Versus (`vs_*`) weapon twins no longer leak into the Adventure inventory grid** — re-hides an owned `vs_*` twin (most visible once an illusion is applied to the crafted twin) at the inventory display layer, while keeping deliberately-crafted `vs_*` weapons visible and craftable. Extends the existing `get_filtered_items` hook (no new hook). (0.8.22-dev)
- **Index-aware modded-loadout persistence** — the loadout save/restore store is now keyed per loadout index (`optional_loadout_index`), fixing bot loadouts cloning the host's gear, with a migration from the old flat schema. (0.8.13-dev / 0.8.14-dev)
- **Loadout persistence is now OPT-IN, DEFAULT OFF** — cim no longer perturbs vanilla bot/player loadouts unless the player turns persistence on. (0.8.15-dev)
- **In-mission forge crash hardening (Fix B/B2..B6)** — promoted in full (HDR armoury_atlas world skip, `weave_menu_*` / `athanor_skilltree_*` raw-material prune, per-frame `set_scalar` bloom-pulse skip, skill-tree ring/cluster suppression). On the public build these are inert because the in-mission Athanor entry is gated off; they ride along for the eventual re-enable and to harden the dev clone. (0.8.16-dev .. 0.8.20-dev)
- **Test-status labels on menu entries** + assorted debug/diagnostic tooling promoted from dev. (0.8.7-dev / 0.8.8-dev / 0.8.10-dev .. 0.8.12-dev)

(Supersedes the unreleased stable 0.8.7 bump, which carried no CHANGELOG entry. All `cim_dev` / `crafting_in_modded_dev` identity tokens were normalized to the stable `cim` / `crafting_in_modded` identity during promotion.)

## 0.8.6 (2026-06-18) — Fix Trollhammer select-crash (weave tooltip) + add craft-button audio feedback

### Fixed — crash on selecting the Trollhammer Torpedo (and other deus/CW weapons)
Selecting the Trollhammer Torpedo (`dr_deus_01`) in the Athanor editor hard-crashed `hero_window_weave_properties.lua:1701: attempt to concatenate local 'tooltip_slot_sub_title' (a nil value)` in `_sync_backend_loadout` (via `on_enter`). Next-in-sequence deus/CW crash after the v0.8.2 `_setup_menu_options` guard: cim re-exposes deus/CW weapons whose property/trait/talent table-names aren't weave categories, so the per-slot tooltip lookup misses → nil → concatenate crash. The tooltip-string tables are per-call locals (not pre-seedable), so the fix wraps `HeroWindowWeaveProperties._sync_backend_loadout` in a pcall under the modded forge — property/trait editing still works; only the unknown-category tooltip degrades. New hook (distinct class from the existing `HeroWindowWeaveForgeWeapons._sync_backend_loadout` hook — no duplicate).

### Fixed — silent Athanor craft buttons
The weapon-select pane CRAFT (`_equip_item`) and the editor CRAFT (`_upgrade_magic_level`) crafted and returned without playing the completion sound (vanilla's sound sits past the custom-forge early-return), so those buttons gave no audio feedback. Both now call `self:_play_sound("play_gui_craft_forge_button_completed")` on a successful craft.

## 0.8.5 (2026-06-18) — Drop Versus-carousel twins that shadow a real Adventure weapon (the "wh_book" locked entry)

### Why
User report: a non-craftable book entry (reported as `wh_book_name`) showed up **locked** in the Athanor weapon list. Root cause: cim enumerates raw `ItemMasterList` and **intentionally** surfaces `vs_*` Versus-carousel weapons as craftable (it clears their `mechanisms` on craft so the result is Adventure-visible). But a handful of `vs_*` items have a **real non-versus Adventure twin sharing the same `display_name`** — notably `vs_wh_hammer_book` vs the real `wh_hammer_book`. cim's list dedups by `display_name`, so the Versus twin can win the dedup and render as a locked, uncraftable row (`backend_id = nil`) that **hides** the real craftable weapon.

### Fixed
- New `_cim_versus_shadowed(data, real_names)` gate in `standard_forge.lua` (+ `_cim_is_versus` / `_cim_real_display_names` helpers), applied to all three craft-list builders: the menu weapon list (`_setup_weapon_list`), the standard-forge random-pick pool, and the blacksmith template cache. A versus item is dropped **only when a real (non-versus) item with the same `display_name` exists** — unique `vs_*` weapons (no real twin) stay craftable; the real `wh_hammer_book` replaces its locked versus twin. The real-`display_name` set is built once per list-build (O(n)).
- Explicitly **not** a blanket versus exclusion — that would remove the intentional cross-character/versus crafting feature. Backported in lockstep with `crafting_in_modded_dev` v0.8.6-dev.

## 0.8.4 (2026-06-17) — Issue #71 (Option A): re-enable in-editor CRAFT for weapons so "set properties → craft" works

### Why
Issue #71's second report (carlotheemo, on public v0.8.0): "press weapon, press greatsword, temper, add 5 atsp + 5 crit, add Swift Slayer, back, then craft → Outcome: No properties." Root cause: cim splits "craft a weapon" from "edit a weapon's properties". The **weapon-select pane** CRAFT button always mints a **blank** weapon (empty properties/traits, fresh backend id). Property/trait edits in the **weave-properties editor** mutate the in-editor item in place via `_forge_apply_to_item`; the editor's own CRAFT button — which clones those edits into a new item (the same machinery the amulet uses) — was **hidden for melee/ranged** weapons and its hook early-returned. So setting properties in the editor and then crafting produced a blank weapon (the reporter backed out and used the blank weapon-select CRAFT).

### Changed
- **`crafting_in_modded.lua`** — `_set_essence_upgrade_cost` hook: removed the melee/ranged branch that hid the `upgrade_button`; it now shows **"CRAFT"** for weapons.
- **`crafting_in_modded.lua`** — `_upgrade_magic_level` hook: removed the melee/ranged early-return so weapons fall through to the existing mint-new path (clones `item.properties` / `item.traits` into a fresh `_athanor_inject_item` craft). Re-enables a path that already shipped for the amulet — no new code.

### Behavior
- Working flow: open the weave-properties editor on a weapon → set bubbles/trait → press **CRAFT** in the editor → a new modded weapon carrying those edits lands in inventory (equip from there). The weapon-select pane's CRAFT still mints a blank weapon (pick-and-craft-clean) as before.

### Also includes (folded in from unreleased 0.8.3)
- **Amulet (weave-properties) crash guard (Issue #71, primary report)** — `BackendInterfaceWeavesPlayFab.get_talent_required_forge_level` now returns `0` under the modded forge (mirrors the existing property/trait guards). Fixes the hard crash `backend_interface_weaves_playfab.lua:1252: attempt to index local 'progression_data' (a nil value)` when pressing the amulet, caused by feeding adventure career talents (e.g. `mercenary_helborgs_tutelage`) into the weave talent picker. New `/cim_regression_test` check `weave_talent_forge_level_guard_present`.

## 0.8.3 (2026-06-17) — Hotfix: amulet (weave-properties) crash on adventure career talents (Issue #71)

### Why
User report (Issue #71, carlotheemo, 2026-06-01, on public v0.8.0): pressing the amulet in the modded forge (open `HeroWindowWeaveProperties` via B → amulet) crashed `backend_interface_weaves_playfab.lua:1252: attempt to index local 'progression_data' (a nil value)` in `get_talent_required_forge_level`, called from `hero_window_weave_properties.lua:_setup_menu_options`. Crash locals confirm it: `talent_name = "mercenary_helborgs_tutelage"` (an es_mercenary **Adventure** talent), `progression_data = nil`, `forge_level = 999`. Under `_custom_forge_active` cim feeds the player's loadout talents (adventure career talents) into the weave talent picker; vanilla `get_talent_required_forge_level` does `progression_data = progression_settings.talents[talent_name]` then `progression_data.required_forge_level` — adventure talents have no weave-progression entry, so `progression_data` is nil and the index is a hard crash. cim already guarded the sibling `get_property_required_forge_level` and `get_trait_required_forge_level` (both `return 0` under the modded forge) but missed the talent one. Targeted backport from `crafting_in_modded_dev` v0.7.74-dev (only this fix — not the rest of the in-flight dev work).

### Changed
- **`crafting_in_modded.lua`** — added the missing `BackendInterfaceWeavesPlayFab.get_talent_required_forge_level` hook returning `0` under `_custom_forge_active` (passthrough otherwise), mirroring the existing property/trait guards. No duplicate-hook conflict (it was previously unhooked in stable).

### Tests
- New `/cim_regression_test` check `weave_talent_forge_level_guard_present` — source-pattern guard that FAILS if the new hook is removed (needle split across two literals to avoid self-match; no-op when source introspection is unavailable).

### To verify (in-game)
- Open the modded forge, press B, click the amulet, and confirm the weave-properties editor opens (talent/property/trait sections render) with **no crash**.

## 0.8.2 (2026-06-16) — Hotfix: Trollhammer Torpedo crashes the forge stat editor

### Why
Friend crash log (2026-06-16): selecting the Trollhammer Torpedo (`dr_deus_01`) in the modded forge crashed `hero_window_weave_properties.lua:385: bad argument #1 to 'ipairs' (table expected, got nil)` in `HeroWindowWeaveProperties._setup_menu_options`. Vanilla stamps `slot_unlock.category = item_data.property_table_name / trait_table_name`, then does `ipairs(WeaveTraits.categories[category])` / `WeaveProperties.categories[category]` / `WeaveLoadoutSettings[career].talent_tree[category]` with no nil-check. cim's Athanor forge re-exposes adventure / Chaos Wastes weapons (the Trollhammer's `property_table_name` is `deus_trollhammer_torpedo`) whose table-names aren't keys in those weave tables → nil → `ipairs(nil)` hard-errors. Two targeted backports from `crafting_in_modded_dev` (only these fixes — not the rest of the in-flight dev work):

### Changed
- **Forge stat-editor crash guard** (cim_dev v0.7.75) — new singleton `mod:hook("HeroWindowWeaveProperties", "_setup_menu_options", ...)` seeds an empty `{}` pool for every progression category the weave tables don't know about before vanilla runs. `ipairs({})` is a no-op, so the affected picker renders empty (no weave traits/properties/talents for that weapon) instead of crashing. Idempotent, scoped to the categories in play.
- **Forge 3D-preview CTD guard** (cim_dev v0.7.70) — ported `_forge_preview_unsafe` + the two `LootItemUnitPreviewer` (`_spawn_link_unit` / `_load_item_units`) hooks. A *separate*, no-traceback hard CTD that fires when the previewer spawns the Trollhammer's 3D model (display unit / 3p package absent from the forge world). Skips the spawn (3D model omitted) when the units aren't resident/loadable; gated on `_custom_forge_active`. Stable previously lacked this guard entirely.

### Notes
- Stat editing works fully for the Trollhammer after this — the weapon just shows no weave-trait/property picker entries and no spinning 3D model. Other weapons are unaffected.

## 0.8.1 (2026-06-08) — Hotfix: in-mission crafting-menu crash `hero_view.lua:175: attempt to index local 'hdr_gui_data'`

### Why
User report (2026-06-07): with **Allow in mission** enabled, opening the crafting menu in a map crashes with `[Script Error]: scripts/ui/views/hero_view/hero_view.lua:175: attempt to index local 'hdr_gui_data' (a nil value)`. Targeted hotfix backported from `crafting_in_modded_dev` v0.7.71-dev (only this fix — not the rest of the in-flight dev work).

### Root cause
Same class as the existing `_setup_gamepad_gui` fix, one level up on the parent `HeroView`. Vanilla `HeroView._setup_hdr_gui` (`hero_view.lua:136-165`) only builds `self._hdr_gui_data` when `is_in_inn` (false in a mission), so the Athanor forge windows' per-frame `parent:hdr_renderer()`/`hdr_top_renderer()` calls dereference `self._hdr_gui_data.bottom`/`.top` on a nil → fatal.

### Changed
- `crafting_in_modded.lua` (after the `_setup_gamepad_gui` block) — three hooks on base `HeroView`: `_setup_hdr_gui` flips `is_in_inn=true` for the vanilla call (pcall-wrapped, flag restored) so the HDR renderers build in mission; `hdr_renderer`/`hdr_top_renderer` fall back to the view's own renderer if `_hdr_gui_data` is ever still nil. Cleanup is leak-safe (`destroy_hdr_gui` is not gated on `is_in_inn`). The failure path logs via **`mod:warning` (ungated)** so a problem surfaces in the log without enabling Debug Logging.
- MOD_VERSION → 0.8.1.

### Tests
- `heroview_hdr_renderer_guard_failsafe` (`/cim_regression_test`) — drives the hooked accessors with a synthetic nil-`_hdr_gui_data` self and asserts no raise + fallback.

### To verify
Enable *Allow in mission*, start a map, open the crafting menu, change a weapon's properties — no crash.

A large batch promoted from the dev branch (0.7.48 → 0.8.0). Headline fixes:

- **Crafted weapons now actually appear in your inventory.** Versus-carousel weapons (the `vs_*` items — "Gallant's Blade", "Soldier's Coach Gun", etc.) are tagged `mechanisms = {"versus"}`, which the Adventure inventory grid filters out. The craft succeeded but the item was hidden by game mode. cim now clears that scoping on crafted items so they show up in Adventure (the DLC paywall is left intact). Also added the missing `dirtify_interfaces()` so crafts appear immediately without a menu re-open.
- **Your modded loadout is remembered and re-equipped on game load (issue #22).** Previously, modded items you'd equipped weren't on your character after a restart. Two causes fixed: (1) with Loremaster's Armoury installed, menu equips dispatch through `BackendUtils.set_loadout_item` and bypassed cim's capture hook — cim now hooks the stable outer entry point so every equip is recorded; (2) cim now re-equips the live keep character after restore (the character spawns before the deferred restore completes), using vanilla's own equip mechanism. Non-modded weapons are unaffected (vanilla handles those).
- **Per-accessory craft buttons in the Athanor accessories view** — CRAFT NECKLACE / CHARM / TRINKET, implemented as a proper own-scenegraph overlay (no more layout breakage). Jewelry crafting is on the Athanor; the standard forge stays a select-template-and-craft flow.
- **"JEWELLERY" → "ACCESSORIES"** on the forge surfaces.
- **Stamina/property slot accounting fixed** — 2-stamina no longer over-consumes slots; the per-property bubble caps (stamina 2 / movespeed 1) are correct.

**Stability:** comprehensive in-game regression-test suite (`/cim_regression_test`), duplicate-hook guards, pcall-fenced UI and backend paths, and a hardening review before release. New diagnostics gated behind `Debug Logging` (off by default).

(Per-change detail lives in the dev branch CHANGELOG. Internal: ported from `crafting_in_modded_dev` v0.7.69-dev; mod-id `cim`.)

## 0.7.48-alpha (2026-05-25) — JEWELRY label-hunt runtime probe (issue #38 data-gathering)

Issue #38 ("JEWELRY" still visible on the main forge page) has resisted two fix attempts (v0.7.35 Localize override + v0.7.37 `HeroWindowLoadoutInventory.on_enter` `category.display_name` mutation). The only literal "Jewellery" string a grep of vanilla UI source turns up is `hero_window_loadout_definitions.lua:602` — already patched — so the surface the user is actually seeing must come from a different rendering path I haven't located by static analysis.

**Approach:** add a runtime probe that walks every active window's `_widgets_by_name` on entry and logs every widget whose content contains "jewel" (case-insensitive, recursive to depth 3 through nested tables). Output goes to the log when `enable_debug_logging` is on. Next session's log will pinpoint exactly which widget needs patching, and the fix becomes mechanical.

Probe fires on entry to:

- `HeroViewStateWeaveForge` parent (via existing autodump hook chain)
- `HeroWindowWeaveProperties` / `HeroWindowWeaveForgeOverview` / `HeroWindowWeaveForgeWeapons` (Athanor surfaces — added probe call to existing on_enter hooks)
- `HeroWindowCrafting` / `HeroWindowCraftingConsole` / `HeroWindowItemCustomization` (routed through `_cim_autodump_forge_open` — the consolidated lifecycle callback in `standard_forge.lua` now passes `self` along; the probe runs there to avoid a duplicate `hook_safe` registration that VMF would silently drop)
- `HeroWindowLoadoutInventory` / `HeroWindowLoadoutInventoryConsole` / `HeroWindowCraftingList` / `HeroWindowCraftingListConsole` / `HeroWindowCraftingInventoryConsole` (new dedicated probe hooks — no existing cim on_enter to collide with)

Output format: each widget that contains "jewel" gets a `widget [<name>] -- N match(es):` header followed by indented `<path.to.field> = "literal text"` lines. Summary `scan complete: N widget(s) with 'jewel' text on <window_name>` per probe run.

**User action required to gather the data:** enable `Debug Logging` in cim's VMF settings, open the menu where the JEWELRY label is visible, then send the latest `console-*.log`. The probe output will tell us the exact widget. With that, the fix is one to a few lines.

**Touched files:** `cim_debug.lua` (new helper + hook fan-out), `standard_forge.lua` (one-arg addition to existing autodump call), `crafting_in_modded.lua` (MOD_VERSION bump), `CHANGELOG.md`.

## 0.7.47-alpha (2026-05-25) — Allow Athanor (B hotkey) in Chaos Wastes staging hub

User report 2026-05-25 EOD: pressing B in the Chaos Wastes staging area echoed `"Crafting menu disabled in Chaos Wastes (would crash on preview world load)"` and refused to open the Athanor. The staging hub is where players configure their loadout between expeditions — closing the menu there defeats one of the mod's core use cases.

**Root cause.** The blanket `mech == "deus" -> block` gate in `mod.open_forge()` was added 2026-05-22 (crash GUID `fa1ec6f8`) to dodge the same `levels/ui_store_preview/world: not loaded` fatal that bit issue #50. That crash was fixed in v0.7.45-alpha by rewriting `_create_item_preview_widget_definition` to skip the un-loaded preview level when not in keep. With the underlying fatal gone, the broad CW block became overcautious.

**Fix.** Removed the deus-mechanism early-return at `open_forge`. The remaining keep-gate (`DamageUtils.is_in_inn`) correctly distinguishes:

- **CW staging hub** (`morris_hub`) → `is_in_inn = true` → **allowed**
- **Active Deus level** (mid-expedition) → `is_in_inn = false` → still gated by `allow_in_mission` toggle (default off; opt-in for crash testing)
- Adventure keeps / Inn variants → `is_in_inn = true` → allowed (unchanged)
- Adventure missions → `is_in_inn = false` → gated by `allow_in_mission` (unchanged)

**Touched files:** `crafting_in_modded.lua`, `CHANGELOG.md`.

## 0.7.46-alpha (2026-05-25) — Restore dev/alpha/beta load banner + expanded crafting-menu autodumps

### Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("Crafting in Modded v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

`crafting_in_modded.lua` — added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[cim] v<MOD_VERSION> loaded")` runs once.

### Expanded crafting-menu autodumps (user request 2026-05-25 EOD)

User direction: "Crafting in modded should dump info about whatever crafting menu the player is in whenever debug mode is on."

Existing autodumps already covered menu *open* (standard forge / Athanor / property editor / salvage / customization), restore-pass completion, and backend-ready. Added coverage for the navigation events inside an open menu, so the log captures every state change the user might be wondering about:

| New hook point | Dump content |
|---|---|
| `HeroWindowCrafting._change_recipe_page` (+ Console variant) | Recipe tile switch — logs `page=<idx> recipe=<name> display=<display_key>` whenever the user clicks salvage / craft_random_item / reroll_props / etc. |
| `HeroWindowWeaveForgeOverview.on_enter` | Athanor's 3-viewport overview — logs career + `amulet_introduced` flag |
| `HeroWindowWeaveForgeWeapons.on_enter` | Athanor weapon-select pane — logs career + selected_slot_name |
| `set_loadout_property` / `set_loadout_trait` / `remove_*` cim hooks | Every bubble write — logs `verb=<set_property|remove_property|set_trait|remove_trait> career=<x> key=<x> slot=<x> bid=<x>` |
| `mod._cim_autodump_customization_item` (helper, callable from anywhere) | Gear-icon menu selected item — bid + key + rarity + slot + skin + power |

All entries gated on `enable_debug_logging` — every entrypoint short-circuits when off, no overhead during normal play. Bubble-write hooks log BEFORE cim's existing forge-active gate runs, so writes that fall through to vanilla are captured too. Output goes to `mod:info` (log only) — no chat spam.

**New file:** none — extends `cim_debug.lua`. **Touched files:** `cim_debug.lua` (new helpers + 5 new hooks), `crafting_in_modded.lua` (4 autodump calls injected at the top of existing weave-property/trait hooks), `CHANGELOG.md`.

## 0.7.45-alpha (2026-05-25) — CRASH FIX: gear-icon mid-mission (issue #50)

User report 2026-05-25 (crash GUID `3bd92d07-8d83-467d-8098-9142a9c7c9bf`): game **crashed** when clicking general_tweaker's mid-mission inventory gear icon. With cim enabled this should open `HeroWindowItemCustomization` so cosmetics / properties / traits can be edited in-mission.

**Crash banner:** `hero_window_item_customization.lua:410: Level not loaded: levels/ui_store_preview/world`. Triggered at 21:49:30.695, 60s into a `military` adventure mission.

**Root cause.** Vanilla `_create_item_preview_widget_definition` (line 382-435) builds the widget definition inline and calls `LevelResource.object_set_names("levels/ui_store_preview/world")` at line 410 while populating the style table. That call fatals when ui_store_preview isn't loaded — which is every adventure / CW mission. cim's existing hook (added in an earlier patch and documented at lines 1163-1204) called vanilla first and post-stripped `level_name` / `object_sets`, but the strip never ran because vanilla never returned.

**Fix.** Skip the vanilla call entirely when not in keep — construct the widget definition from scratch, mirroring vanilla's shape minus `level_name` and `object_sets`. `_FORGE_MISSION_SAFE_ENV` (`environment/ui_hdr`) used in place of `environment/ui_store_preview`. The item still renders because `LootItemUnitPreviewer` uses `resource_packages/levels/ui_loot_preview` from `GlobalResources`. Sibling hook on `_register_object_sets` (line 1251+) already handles the no-level case correctly.

Keep behavior unchanged — `_is_in_keep()` gate at the top of the hook still calls vanilla.

**Touched files:** `crafting_in_modded.lua`, `CHANGELOG.md`. **Issue #50 stays OPEN until user confirms in-game.**

## 0.7.44-alpha (2026-05-25) — Action-rejection feedback visibility + stamina/movespeed click-cap removal (issues #47, #49)

Two connected user reports from 2026-05-25, same root cause: the v0.7.38 blanket `mod.echo` chat suppression silenced action-rejection messages, making cap-enforced clicks look like "nothing happened" → "100% broken" perception.

### Action-rejection messages now use `mod:warning` (always visible)

Roughly a dozen `mod:echo` calls that fire on rejected user actions (craft failures, backend-not-ready, no-eligible-items, DLC-locked illusions, distinct-property cap, etc.) converted to `mod:warning`. `mod:warning` is NOT patched by v0.7.38's chat-suppression — warnings always surface to chat AND log regardless of `enable_debug_logging`. Semantically correct too: the user attempted an action that wasn't allowed.

Sites converted:
- `crafting_in_modded.lua`: distinct-property cap (issue #47 partial), stamina/movespeed bubble cap (now removed, see below), Athanor craft-failed paths (4 sites), backend-not-ready, "no weapon selected"
- `standard_forge.lua`: reroll-no-input, "Cannot craft / wrong slot_type", "No eligible items", crafting interface not ready, backend mirror not ready
- `illusion_swap.lua`: "Cannot apply illusion — requires DLC you don't own"

Diagnostic / load-time / status echoes stay as `mod:echo` (silenced unless debug logging on).

### Stamina / movespeed per-property bubble cap REMOVED (issue #49)

User report: "the stamina and movement speed properties still require the same number of free slots to be assigned and until enough space is clear it blocks more properties."

Root cause: vanilla's bubble grid renders 10 clickable slots regardless of property type, but cim's `set_loadout_property` hook silently rejected clicks past `_PROPERTY_BUBBLE_CAP_STATIC[property]` (stamina=2, movespeed=1). User would click visibly-empty slots 3-5 on a stamina row and see no fill — cim's check rejected the click before vanilla's bubble render could update.

Fix: removed the per-property bubble-cap rejection in `crafting_in_modded.lua:~2356`. Clicks now succeed for stamina/movespeed up to all 5 visible slots.

**Game value unchanged.** `_value_for_bubbles` still clamps the persisted property value at 1.0 (= vanilla +2 stamina tier 5, = +5% movespeed). Extra clicks beyond the engine cap write redundantly but produce no further game effect.

**Known inconsistency:** on session reload, `_bubbles_for_value` seeds only the engine-max bubble count (2 stamina / 1 movespeed) from the persisted value, so "I had 5 stamina bubbles filled" loads back as 2. The game-effect value is correct throughout — only the displayed bubble count compresses on reload. A full fix needs the click count persisted separately; deferred to a later patch.

**Distinct-property cap (MAX_DISTINCT_PROPERTIES = 2) is unchanged** — it's a vanilla-crash gate for `HeroWindowItemCustomization`'s Apply-Skin preview (only ships widgets for hotspot_1 / hotspot_2; a third distinct key crashes `item_customization.lua:1213`). The distinct-cap warning also goes through `mod:warning` now, so users see "Max 2 distinct properties per item" feedback when they hit that.

**Issues #47 and #49 stay OPEN until the user confirms in-game.**

**Touched files:** `crafting_in_modded.lua`, `standard_forge.lua`, `illusion_swap.lua`, `CHANGELOG.md`.

## 0.7.43-alpha (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- crafting_in_modded_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- crafting_in_modded.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build crafting_in_modded -- verification only. NOT deployed, NOT uploaded.

## 0.7.42-alpha (2026-05-25) — `custom_glow` pass-through field for sibling-mod overlays

### Why
cosmetics_tweaker is building a per-instance weavebound-glow customizer for the Bretonian Longsword (Evengleam) and other magic-family weapons. The glow state needs to persist per backend_id alongside the skin and survive game restarts. CIM already has the right substrate — `_forged_weapons[backend_id]` is keyed by backend_id and round-trips through VMF settings on every save — so the cleanest integration is a single opaque pass-through field on the entry. CIM stores it, doesn't interpret it; cosmetics_tweaker writes / reads / applies.

### Added
- `custom_glow` field on every `_forged_weapons[bid]` entry. Pass-through only — CIM never reads its contents. Persists through `_forge_save` / `_forge_load` / `_cim_register_craft` like every other field.
- `mod._cim_set_custom_glow(backend_id, blob)` — sibling-mod updater that amends just the overlay slot on an existing entry and persists immediately. Returns true on write, false when the backend_id is unknown.

### Behavior when cosmetics_tweaker isn't installed
The `custom_glow` blob sits unread on the in-memory entry. No apply path runs. The weavebound skin renders with its vanilla baked materials — the correct fallback. No crash, no warning spam. cosmetics_tweaker's apply code is the only consumer; if it's not loaded, the field is inert data.

### Schema compatibility
Legacy saves without the field load cleanly (nil = no overlay). New saves include the field for every entry (nil-valued when no overlay is active).

## 0.7.40-alpha (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[cim] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `crafting_in_modded.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[cim] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.7.40-alpha.

## 0.7.39-alpha (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `crafting_in_modded.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing seven cim regression checks.
- `itemV2.cfg` — bumped to v0.7.39-alpha.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused).
- 0 bare `mod:echo` reclassified — cim already has a global `mod.echo` redirect (top of file) that routes every `mod:echo` to `mod:info` when the toggle is OFF. The new `_dbg_alert` helper bypasses that redirect (by guarding on the toggle = ON path).

## 0.7.38-alpha (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). cim previously had `debug_mode` nested inside `debug_group` near the bottom — renamed and un-nested.

### Changed
- `crafting_in_modded_data.lua` — removed `debug_group` wrapper; `debug_mode` widget renamed to `enable_debug_logging` and moved to the bottom of `options.widgets` as a direct top-level child.
- `crafting_in_modded_localization.lua` — removed `debug_group` / `debug_mode` / `debug_mode_description` strings; added `enable_debug_logging` + `enable_debug_logging_tooltip` per the standard.
- `cim_debug.lua` — `_enabled()` now reads `mod:get("enable_debug_logging")` (was `debug_mode`). Module-load info line updated. Header docstring updated.
- `crafting_in_modded.lua` — added file-local `_dbg(fmt, ...)` helper at top of file. Output prefix `[cim:dbg]`.
- `itemV2.cfg` — title + description bumped to v0.7.38-alpha.

### Notes
- **Migration**: the saved value of `debug_mode` is not auto-carried into `enable_debug_logging`. Users who had the old toggle on must re-tick the new `Debug Logging` checkbox after first load. VMF defaults the new key to `false`.

### Chat-output suppression by default (user feedback 2026-05-25)

User reported cim was spamming the in-game chat with load / restore / status messages. New behavior: at the top of `crafting_in_modded.lua` (before any `mod:command` registration or sub-module load) we monkey-patch `mod.echo` so every `mod:echo(...)` call in cim is silently redirected to `mod:info(...)` (log only) UNLESS the universal `enable_debug_logging` setting is ON. When ON, the patched echo calls the original — chat output is restored exactly as before, plus the v0.7.36+ autodumps already pipe to log.

Side effect: user-invoked dump commands (`/inv_dump`, `/forge_list`, `/cim_dump_loadout`, `/mirror_dump`, `/salvage_debug`, `/craft_dump`, etc.) also go log-only when debug logging is OFF. To run them and watch the output in chat, tick `Debug Logging` in cim's VMF settings. `mod:error` and `mod:warning` are not patched and still surface to chat on issue.

Also dropped the redundant startup banner `mod:echo("Crafting in Modded v" .. MOD_VERSION)` — the `mod:info` line immediately above it already records the load.

## 0.7.37-alpha (2026-05-25) — Three user-reported fixes: JEWELRY label, accessory power readout, base-power loc placeholder

### "JEWELRY" → "Accessories" on the loadout inventory grid (issue #38)

v0.7.35-alpha added a `_G.Localize` override for `crafting_recipe_craft_jewellery` etc., which fixed the recipe-page titles inside the crafting forge. But the user reported the **JEWELRY** label still visible on the main loadout inventory page.

Root cause: `hero_window_loadout_definitions.lua:602` defines `display_name = "Jewellery"` as a **literal string** in the `category_settings` table, NOT a loc key. `HeroWindowLoadoutInventory._change_category_by_index` reads it raw and writes it directly to the `item_grid_header` widget — `_G.Localize` is never called on it.

Fix in `modded_rarities.lua`: new `mod:hook_safe("HeroWindowLoadoutInventory", "on_enter", ...)` that walks `self._categories` after vanilla builds it, and mutates the jewellery entry's `display_name` to "Accessories". Vanilla's subsequent header write then naturally uses the new value. Single source mutation — all consumers (header, future tooltips) automatically pick up the change.

**Issue #38 stays OPEN until the user confirms the label in-game**, per user directive 2026-05-25.

### Accessory crafting viewport showed "0" for power — now reflects `base_power_level` setting

The Athanor amulet viewport (viewport 2 — the central "accessory crafting" panel) showed `0` next to the power label. cim's `_forge_apply_ui_polish` updates `viewport_power_value_1` and `viewport_power_value_3` from the equipped melee / ranged item's `power_level`, but the slot_map skipped viewport 2 entirely because the amulet doesn't track a single equipped item.

Fix: write `viewport_power_value_2` with the configured `base_power_level` setting (default 300). That matches what a newly-crafted accessory would actually receive, making the readout meaningful instead of a stuck `0`.

### "Base power for new crafts" setting no longer shows "< >" placeholder

`crafting_in_modded_data.lua` declared `unit_text = ""` on the `base_power_level` numeric widget. VMF treats `unit_text` as a loc key — `Localize("")` returns the unresolved-key placeholder `<>`, which renders next to the value as "< >".

Fix: omit the `unit_text` field entirely. A bare numeric is fine for a power-level value.

**Touched files:** `modded_rarities.lua`, `crafting_in_modded.lua`, `crafting_in_modded_data.lua`, `CHANGELOG.md`.

## 0.7.36-alpha (2026-05-25) — Debug-mode toggle + auto-dump diagnostics on menu opens / key events

New VMF setting under a "Debug" group: **Debug mode (auto-dump diagnostics)**. Default OFF.

When ON, cim fires a curated set of diagnostic snapshots to the game log (`%appdata%\Fatshark\Vermintide 2\console_logs\`, no chat spam) at well-known UI transitions and state changes:

| Hook point | What gets logged |
|---|---|
| Standard forge / customization menu open (`HeroWindowCrafting` / `HeroWindowCraftingConsole` / `HeroWindowItemCustomization` `on_enter`) | EAC flag, forge-active flag, show_only_modded flag, mechanism, current career; mirror modded/vanilla counts; every equipped slot for the current career with bid + rarity |
| Athanor open (`HeroViewStateWeaveForge.on_enter`) | `_forged_weapons` saved count + current career |
| Property editor open (`HeroWindowWeaveProperties.on_enter`) | Selected item bid + key + rarity + slot + skin + properties + traits + power, or "amulet layout" if no selected item |
| Salvage page open (`CraftPageSalvage` / `CraftPageSalvageConsole` `on_enter`) | Vanilla salvage-filter result count + modded item count within it (so a "my modded items don't appear in salvage" report is diagnosable from the log alone) |
| `_restore_modded_loadout` finished | Per-career summary of saved entries — spots careers with 0 saved entries (candidates for "my X career loadout wasn't restored" reports) |
| Backend interfaces ready (`BackendManagerPlayFab._create_interfaces`) | mirror size + forged_weapons count + total `_modded_loadout` entries |

All entries are prefixed `[cim-debug] [<context>] ...` so they're greppable. Every entrypoint is a fast no-op when the setting is OFF — zero overhead for normal play.

**Why a new module:** the existing on-demand chat commands (`/inv_dump`, `/mirror_dump`, `/cim_dump_loadout`, `/forge_list`, `/salvage_debug`) echo to chat for interactive use. The autodumps go log-only and are tuned for diagnosing user-forwarded logs after the fact — no need for the user to remember which command produces which snapshot at which moment.

**New files:** `cim_debug.lua`. **Touched files:** `crafting_in_modded.lua` (sub-module loader + 2 autodump call sites), `crafting_in_modded_data.lua` (new Debug group + setting), `crafting_in_modded_localization.lua` (4 strings), `standard_forge.lua` (autodump in consolidated `on_enter` lifecycle callback), `CHANGELOG.md`.

## 0.7.35-alpha (2026-05-24) — Standard forge accessory craft buttons + "CRAFT NEW WEAPON" removed on property editor + Jewellery→Accessories rename

User direction 2026-05-24, three connected changes to the crafting menu:

### Standard forge now has three on-screen accessory craft buttons

Vanilla's `Craft Jewellery` recipe rolls a random jewelry slot. The template-drop affordance (drop a slot-specific blacksmith template → recipe pins to that slot) shipped in v0.7.27 / v0.7.28 but is undiscoverable — players don't know to drop a template first.

Three new buttons injected into `HeroWindowCrafting.window_bottom`, visible whenever the standard forge is open: **CRAFT NECKLACE**, **CRAFT CHARM**, **CRAFT TRINKET**. Clicking one calls the existing `_craft_via_synth(slot_filter, label)` helper directly — same code path as the `/cim_craft_*` chat commands. New code lives at the bottom of `standard_forge.lua` (`_STANDARD_FORGE_BUTTONS` + `_ensure_std_forge_buttons` + `_show_std_forge_buttons` + `_handle_std_forge_button_clicks`), mirroring the Athanor amulet button pattern in `crafting_in_modded.lua:1106-1194`. Gated on `_cim_standard_forge_active` so the buttons appear only on the forge UI.

**Followup TODO:** `HeroWindowCraftingConsole` (gamepad / inventory-tab variant) has a different scenegraph and needs its own button injection pass.

### "CRAFT NEW WEAPON" button removed from the property editor (melee/ranged)

When the player opens an already-equipped melee or ranged item in `HeroWindowWeaveProperties` and tweaks the bubble grid, `_forge_apply_to_item` already mutates the equipped item in place. The repurposed `upgrade_button` was relabeled "CRAFT NEW WEAPON" and minted a redundant new modded item with the same edits — confusing and inverted the "modify your equipped item" mental model.

`_set_essence_upgrade_cost` hook now hides the button entirely (`btn.content.visible = false`) when `slot_type` is `melee` or `ranged`. The `_upgrade_magic_level` handler also early-returns for that case so a stray gamepad activation doesn't bypass the hidden button and mint a phantom craft. To craft a brand-new weapon, the player picks one in the weapon-select pane.

Amulet case (no `selected_item`) and the three cim per-slot accessory buttons in the amulet view are unchanged.

### "Jewellery" → "Accessories" rename on the main forge menu

Extended the existing `_G.Localize` hook in `modded_rarities.lua` with a `_CIM_LOC_OVERRIDES` table covering:

- `crafting_recipe_craft_jewellery` → "Craft Accessories"
- `description_crafting_recipe_craft_jewellery` → "Craft a new accessory (necklace, charm, or trinket) for your current career."
- `crafting_recipe_jewellery_reroll_properties` → "Reroll Accessory Properties"
- `crafting_recipe_jewellery_reroll_traits` → "Reroll Accessory Traits"

Matches the player-facing slot names (necklace / charm / trinket) — the vanilla "jewellery" label was abstract.

### Sibling-mod post-restore callback shim (for cosmetics_tweaker LA persistence)

New public API on `mod` (cim): `mod._cim_register_restore_callback(fn)`. Registered functions fire at the end of every `_restore_modded_loadout` pass (initial + 1.0s deferred + 3.0s deferred), wrapped in pcall so a misbehaving subscriber can't take down cim's restore.

Use case: cosmetics_tweaker's parallel work on persisting LA-applied weapon illusions (issue #22). cosmetics_tweaker captures `{ illusion_key, paint, offhand }` per (career, slot) at apply time and registers a callback that re-applies the saved selections after cim has restored the modded backend_ids. Callbacks must be idempotent — they fire 3× per session boot.

**Touched files:** `standard_forge.lua`, `crafting_in_modded.lua`, `modded_rarities.lua`, `CHANGELOG.md`.

## 0.7.34-alpha (2026-05-24) — Athanor craft no longer auto-equips (icon/equip divergence)

User report 2026-05-24: pressing **CRAFT** on the Athanor's weapon-select pane (or the CRAFT NEW WEAPON button on a selected melee/ranged item) updated the equipment-slot icon to the freshly crafted item, but the actually-equipped weapon in that slot stayed unchanged — icon and equip diverged.

**Root cause.** Three call sites in `crafting_in_modded.lua` ran `backend_items.set_loadout_item(...)` immediately after creating the new modded item:
- `HeroWindowWeaveForgeWeapons._equip_item` hook (~line 2557) — weapon-select pane CRAFT button
- `_cim_amulet_craft_one_slot` (~line 2682) — per-slot amulet craft
- `HeroWindowWeaveProperties._upgrade_magic_level` hook (~line 2765) — CRAFT NEW WEAPON button on the property editor

`set_loadout_item` updates the PlayFab mirror loadout entry (which drives the slot icon) but doesn't rebuild the in-keep equipped unit, so the slot showed one item while still playing another.

**Fix.** Removed all three `set_loadout_item` calls. The craft path now: mirror-injects the new item → persists to `_forged_weapons` → echoes "Crafted & saved: X — equip from inventory". Player equips manually from inventory when they want to.

The two craft viewports in the Athanor (melee + ranged) now match their intended purpose: surface what's craftable for the selected slot, mint a new modded item into inventory, and stop. Modifying-in-place an already-equipped item remains a separate flow via the gear-icon reroll menu (`HeroWindowItemCustomization`).

**Side-effect cleanup.** Salvage-filter comment block (`filter_items` hook ~line 824) updated — it no longer claims "auto-equip on craft" as the reason for the unconditional salvage surfacing.

**Touched files:** `crafting_in_modded.lua`, `CHANGELOG.md`. Issue [#12](https://github.com/Ensrick/vermintide-2-tweaker/issues/12).

## 0.7.33-alpha (2026-05-23) — Fixed: stale loadout entries overwrote vanilla equip on restore + verbose diagnostic logging

User report 2026-05-23 (cim v0.7.32 load): equipped accessories (necklace / charm / trinket) and last-equipped weapons did not restore after a fresh game load. Log showed `Restored 5 modded loadout entries` firing 3 times across state transitions but no detail on WHICH entries were touched.

**Root cause.** `mod:hook_safe(BackendInterfaceItemPlayfab, "set_loadout_item", ...)` at line ~567 only SAVED entries when the new item was modded. It never CLEARED a slot when the user later equipped a vanilla / Save Weapon / Loadout Manager / etc. item there. Stale modded entries stayed in `_modded_loadout` forever. On next session boot, `_restore_modded_loadout` ran AFTER vanilla PlayFab restored each slot and faithfully re-equipped the stale modded item, clobbering what the user had at session-end.

**Fix.** Hook now ALWAYS clears the slot's cim entry first, then re-saves only if the new item is modded. Vanilla equips clean up the cim record; modded equips refresh it. The saved state always matches currently-equipped, not frozen at first-modded-equip-ever.

**Verbose logging.** Three log surfaces upgraded from aggregate-count to per-entry detail so future user reports are diagnosable from the log alone:

- `_restore_modded_loadout` — now prints `[restore] OK <career>/<slot> -> <bid> (<key>)` for each restored entry, `[restore] MISSING ...` for entries whose bid isn't in the mirror, `[restore] ERROR ...` for pcall failures. Summary line: `[restore] total=N restored=N missing=N errored=N`. Also logs `[restore] skipped` reasons when the function early-returns.
- Property trim in `_create_interfaces` — now prints `[trim] <key> (bid=<bid>) kept=[a,b] dropped=[c,d,e]` per item that gets clipped. Previously only the aggregate `Trimmed N items` line existed, so it was impossible to tell which items lost which properties.

**Touched files:** `crafting_in_modded.lua`, `CHANGELOG.md`.

**Test gap closed.** Regression-test additions queued in a parallel patch:
- `/cim_regression_test` round-trip checks for `_modded_loadout` (modded save → reload → confirm; non-modded equip → confirm stale entry cleared)
- `tools/mod-lint/lint-mod.ps1` static check for any `set_loadout_item` hook missing the clear-before-save pattern

## 0.7.32-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `crafting_in_modded.lua` — renamed `regression_test` → `cim_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/cim_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.7.9-dev (2026-05-18) — DLC gate on craftable weapons
**Report:** "Crafting in modded unlocks all weapons for players, and that's a good thing, but it also unlocks dlc weapons that players may not own."

Vanilla gates DLC weapons behind `required_dlc` on the `ItemMasterList` entry, checked via `Managers.unlock:is_dlc_unlocked`. Modded crafting is a power-up over the vanilla progression unlocks (career levels, crafting materials) — NOT a bypass for paid DLC content. `illusion_swap.lua` already respects this gate for cosmetic skins (`_skin_requires_unowned_dlc`, v0.6 series); the parallel was missing on the weapon side.

**Fix:** new local helper `_item_requires_unowned_dlc(item_key)` in `standard_forge.lua` reads `ItemMasterList[item_key].required_dlc` and returns `not Managers.unlock:is_dlc_unlocked(...)`. Exposed as `mod._cim_item_requires_unowned_dlc` for cross-file use. Added to three weapon-eligibility passes:

1. `_build_template_cache` — the synthetic "blacksmith's template" injection from v0.7.7. This is the main user-visible surface; without this filter, the Craft Item recipe page lists every DLC weapon family alongside owned ones.
2. `_make_craft_synth`'s `eligible` random pool — defense-in-depth for the no-input-item fallback path.
3. `HeroWindowWeaveForgeWeapons._setup_weapon_list` — the custom Athanor forge's weapon list, which walks `ItemMasterList` directly.

CWV / mod-added weapons are unaffected — character_weapon_variants explicitly strips `required_dlc` on its cloned entries (cwv `_build_entry`), so the gate is a no-op for them.

## 0.7.8-dev (2026-05-17) — Fix: v0.7.7 templates never built (rehook warning shadowed callback)
**Symptom:** v0.7.7 logged two rehook warnings at startup —
```
[MOD][cim][WARNING] (hook_safe): Attempting to rehook active hook [on_enter].
```
one for `HeroWindowCrafting`, one for `HeroWindowCraftingConsole`. The standard forge's existing `on_enter` hook (set `_cim_standard_forge_active = true`) and the new template-rebuild `on_enter` hook were registered as TWO separate `mod:hook_safe(Class, "on_enter", ...)` calls. Per `feedback_vmf_hook_safe_no_chain`, VMF silently drops the second registration — so `_build_template_cache()` was never called on forge entry, the template cache stayed empty, and the Craft Item recipe page still hid every unlocked weapon family.

**Fix:** consolidated into one callback. The existing on_enter hook now does both jobs (flip the active flag AND rebuild the cache, the latter via `mod._cim_rebuild_template_cache` resolved at call time). Removed the duplicate hook block at the bottom of `standard_forge.lua`.

The lazy-build at the head of `_cim_inject_templates` (`if not next(_template_cache) then _build_template_cache() end`) stays as defense in depth — covers the edge case where filter runs before the first on_enter fires (it shouldn't, but cheap to keep).

## 0.7.7-dev (2026-05-16) — Standard forge "Craft Item": craft any career-eligible weapon
**Report:** "If a player hasn't unlocked a certain kind of weapon then they can't craft or use it." Vanilla `can_craft_with` (backend_interface_common.lua:498) only matches `rarity == "default"` items, and the player only has those for career-level-unlocked weapon families — so the Craft Item recipe page silently hides every weapon family they haven't grinded to. CWV / mod-added weapons never get a default template at all.

**Fix:** synthesize a "blacksmith's template" item per career-eligible weapon family on standard-forge open and inject them into the Craft Item recipe's inventory list. Templates aren't in the backend mirror — they never leak into the regular inventory tab (different filter). Clicking craft feeds the template's `key` into the existing `_make_craft_synth` path, which clones it into a fresh modded-rarity item via `add_item` the same way as before.

Three additions in `standard_forge.lua`:
1. `_build_template_cache()` — walks `ItemMasterList` for `slot_type in {melee,ranged,ring,necklace,trinket}`, `can_wield contains current career`, rarity not `magic`/`promo`, item_type not `weapon_skin`. Cache is keyed by synthetic bid `"cim_template_<key>"`, rebuilt on every `HeroWindowCrafting{,Console}` `on_enter` to stay in sync with career switches between visits.
2. `mod._cim_inject_templates(items, filter)` — appends one template per `item_type` not already represented by a real default-rarity entry. Gated on `_is_active() and filter:find("can_craft_with")` so it only fires for the right recipe page.
3. `BackendInterfaceItemPlayfab.get_item_from_id` hook — resolves `cim_template_*` bids back to the cached entry. The synth's `item_interface:get_item_from_id(bid)` lookup goes through this hook, reads `.key`, and clones the underlying weapon as usual.

`crafting_in_modded.lua`'s existing `get_filtered_items` hook gets one new line: call `mod._cim_inject_templates(filtered, filter)` after the modded-only filtering pass.

**Net effect:** the Craft Item recipe page lists every melee / ranged / jewellery family the current career can wield, regardless of XP-gate state. Player picks one, clicks craft, gets a new modded-rarity weapon of that type.

## 0.7.6-dev (2026-05-13) — Fix inv_dump crash; narrow modded-bid heuristic; new `mirror_dump`
Three changes diagnosing the "modded items not visible in inventory grid" report:

### 1. Narrow `_cim_is_modded_backend_id`
Old version matched any UUID-format backend_id (`^%x+-%x+-%x+-%x+-%x+$`) on the theory that we use `Application.guid()` for our crafts. But `PlayFabMirrorBase._create_fake_inventory_items` also uses `guid()` for every fake weapon-skin / cosmetic / weapon-pose entry — so when `unlock_all_illusions` is on (now unconditional in cim's `get_unlocked_weapon_skins` hook, v0.7.3+), ~1500 fake skin items get UUID bids and were *all* misclassified as "modded".

Visible symptom: `/inv_dump` reported `modded=1553 vanilla=887` and the sample-item output showed weapon_skin / frame items instead of actual crafted weapons. The 4 real crafts were buried.

Fix: regex removed. Modded backend_ids are now strictly `_forged_weapons[bid]` (cim's own registered crafts) or `cwv_*` prefix (character_weapon_variants). Rarity-based detection (`item.rarity == "modded"` or `"promo"`) still covers anything we miss.

### 2. Fix inv_dump crash
`/inv_dump`'s "FILTERED" pass built a sequential array from the bid-keyed `get_all_backend_items()` dict and passed it to `BackendInterfaceCommon.filter_items`. That function iterates with `for backend_id, item in pairs(items)` — so it saw backend_ids `1, 2, 3, …`. `get_item_rarity(1)` called `get_item_from_id(1)` which returned nil, then crashed on `item.skin` (or `item.rarity` depending on the line). Fix: pass `all` directly (already bid-keyed).

### 3. New `/mirror_dump` command
For diagnosing item-missing-from-grid reports specifically. Walks every saved craft in `mod:get("forged_weapons")` and reports per-bid: key, rarity, slot_type, can_wield, in_mirror (`backend_mirror._inventory_items[bid] ~= nil`), in_items_iface (`get_all_backend_items()[bid] ~= nil`), and current loadout slot. Summary line: `saved=N in_mirror=N in_items_iface=N`.

Use this to find which of (a) item not in mirror, (b) mirror has it but `item.data` is nil, (c) `can_wield` doesn't match current career, (d) other filter drop, is the actual cause.

## 0.7.5-dev (2026-05-13) — Fix rehook warning + consolidate craft hook
**Warning at launch:** `[MOD][cim][WARNING] (hook): Attempting to rehook active hook [craft].`

**Cause:** `standard_forge.lua` and `illusion_swap.lua` both registered a `mod:hook("BackendInterfaceCraftingPlayfab", "craft", ...)`. VMF rejects the second registration on the same class+method silently, dropping the hook — so illusion_swap.lua's craft logic was *dead code*. Illusion-apply would fall through to vanilla `craft()` and PlayFab → EAC kick in modded realm.

**Fix:** moved illusion_swap.lua's craft body into a helper `mod._cim_try_illusion_apply(self, career, ids, recipe)`. `standard_forge.lua`'s existing craft hook now calls this helper FIRST (regardless of `_is_active`) and returns its result if non-nil. One craft hook, both behaviors. No rehook warning.

This pattern matches the [[feedback_vmf_hook_safe_no_chain]] rule — for shared class+method hooks, consolidate into one callback rather than two.

## 0.7.4-dev (2026-05-13) — Fix Chaos Wastes crash from custom rarity in pool_excludes
**Crash:** `deus_run_controller.lua:2130 attempt to index a nil value` when opening a Deus weapon chest. Stack: `get_weapon_pool` → `_generate_stored_weapon` → `DeusChestExtension:update`. Crash locals showed `pool_rarity = "modded"`, `excluded_weapon_group = "es_halberd"`.

**Cause:** When a chest grants a unique-rarity weapon, vanilla calls `DeusRunController._remove_weapon_from_pool`. That asks `RarityUtils.get_lower_rarities("unique")`, which iterates `RaritySettings` and returns every rarity with `order < 5` — including our `"modded"` (order=4). The function then writes `pool_excludes["modded"][weapon_group] = true`. On the next chest, `get_weapon_pool` iterates the excludes:

```lua
weapon_pool[pool_rarity][excluded_weapon_group] = nil
```

`weapon_pool` is built from `DeusDropRarityWeights` (vanilla deus rarities only), so `weapon_pool["modded"]` is nil → crash.

**Fix:** new pre-hook on `DeusRunController.get_weapon_pool` in `modded_rarities.lua`. Before vanilla iterates, scrub `pool_excludes` of any rarity key not in the base deus weapon pool. Idempotent — repairs already-contaminated CW runs AND prevents future crashes regardless of which custom rarity caused the pollution (so adding more rarities via `mod.register_rarity` is safe in CW too).

The fix is co-located with the rarity registry on purpose: custom rarities are the population vector, so the compat patch belongs with the registration logic.

## 0.7.3-dev (2026-05-13) — Unlock all DLC-owned illusions + inv_dump diagnostic
Two changes:

### 1. Unlock all DLC-owned weapon illusions in modded realm
Previously vanilla locked illusions (e.g. "Sword of Bitter Dreams") rendered as locked in cim's illusion-swap grid even though the synthetic-backend-id path would happily craft them — the Apply button was disabled because the backend mirror said the skin wasn't unlocked.

New `hook_safe("BackendInterfaceCraftingPlayfab", "get_unlocked_weapon_skins")` in `illusion_swap.lua` iterates `WeaponSkins.skins` and marks every entry as unlocked on the local mirror, except skins gated behind unowned DLC (`_skin_requires_unowned_dlc` — same DLC gate used by the rest of illusion_swap.lua). Only runs when `script_data["eac-untrusted"]` is true (modded realm).

Mirrors cosmetics_tweaker's `unlock_all_illusions` setting, but unconditional in cim — the modded-realm illusion swap doesn't make sense without the unlock, so there's no toggle.

### 2. New `/inv_dump` diagnostic command
Run in the developer console to dump:
- eac-untrusted flag, standard_forge_active flag, show_only_modded_weapons setting, current mechanism, career
- Modded-item count vs vanilla count in the backend mirror
- Per-item detail for the first 8 modded items (backend_id, key, rarity, slot_type, can_wield, wieldable-by-current-career, mechanisms)
- The result of running the loadout grid's actual filter (`available_in_current_mechanism and can_wield_by_current_career and ...`) against the full backend item list, to identify which filter clause is dropping modded items

For diagnosing "modded items not visible in the inventory grid" reports.

## 0.7.2-dev (2026-05-13) — Migrate illusion-swap UI from cosmetics_tweaker; refreshed `icon_bg_modded`
Two changes:

### 1. Modded-realm illusion swap (migrated from cosmetics_tweaker v0.8.49)
cim now ships its own copy of the "change weapon cosmetics in modded realm" pipeline, so the feature is available even when cosmetics_tweaker isn't installed. cosmetics_tweaker yields to cim when both are loaded — each hook in cosmetics_tweaker's illusion-swap section checks `get_mod("cim")` at fire time and defers to the original.

New file `illusion_swap.lua` registers the six hooks that unlock the vanilla illusion-apply flow against the `eac-untrusted` modded-realm gate:

| Hook | Purpose |
|---|---|
| `BackendInterfaceItemPlayfab.get_weapon_skin_from_skin_key` | Synthetic backend ids for unowned skins so the grid can reference them |
| `HeroWindowItemCustomization._enable_craft_button` | Temporarily clear `eac-untrusted` so the Apply button enables for `apply_weapon_skin`. Force-clear hotspot held flags on disable to prevent the fast-completion sound loop |
| `HeroWindowItemCustomization._on_illusion_index_pressed` | Clear `content.locked = false` on clicked widgets |
| `HeroWindowItemCustomization._update_state_craft_button` | Clear `eac-untrusted` for the state check |
| `BackendInterfaceCraftingPlayfab.craft` | Write `item.skin` to the local backend mirror instead of sending to PlayFab |
| `BackendInterfaceCraftingPlayfab.update` | Defer completion one frame to match vanilla async timing |

DLC ownership is respected — skins with `required_dlc` in ItemMasterList only unlock if the player owns that DLC.

**Persistence for modded items:** when the craft hook applies a skin to a backend_id that `_cim_is_modded_backend_id` recognizes, it writes `craft.skin = skin_key` into `_forged_weapons[bid]` and calls `_cim_persist_crafts()`. cim's existing `_forge_load` already reads `w.skin` from the save and threads it into the rebuilt item on next launch, so modded-item cosmetics survive a game restart.

**What was NOT migrated:** the offhand/shield picker (a separate row of buttons that swaps the left-hand model independently). User explicitly excluded it from this migration.

**What was NOT migrated:** the `_custom_skin_keys` registry (cosmetics_tweaker's own custom illusions). Those still work in cosmetics_tweaker because they live in `WeaponSkins.skins` and its own `get_unlocked_weapon_skins` hook is unaffected by this migration.

### 2. Refreshed `icon_bg_modded` PNG
User updated `D:\Game Mods\Vermintide 2 modding\CWV Item Icons\source pngs 84x84\icon_bg_modded.png` (16455 → 18419 bytes). Copied into the mod, rebundled.

## 0.7.1-dev (2026-05-12) — Ship `icon_bg_modded` rarity-background texture
v0.7.0 introduced the `"modded"` rarity but didn't supply an icon background, so every modded item rendered with the vanilla `icons_placeholder` "missing texture" tile in the inventory grid.

Asset pipeline (mirrors `dynamic_cosmetic_portraits`):
- New 80×80 PNG at `gui/1080p/single_textures/cim/icon_bg_modded.png` (user-authored from extracted `icon_bg_exotic` template, recolored to pale gold)
- Matching `icon_bg_modded.texture` (DXT5, sRGB) compile definition
- Matching `icon_bg_modded.material` using `gui:DIFFUSE_MAP` shader
- `.package` updated with `material = [...]` and `texture = [...]` entries so VMB bundles the asset

VMF wiring in `crafting_in_modded_data.lua`:
- `custom_gui_textures.textures = { "icon_bg_modded" }`
- `custom_gui_textures.ui_renderer_injections` covers 10 UI surfaces: `ingame_ui`, `ingame_ui_settings`, `hero_view`, `hero_view_state_loot`, `hero_view_state_store`, `hero_view_state_weave_forge`, `start_game_state_settings_overview`, `level_end_view_base`, `level_end_view_versus`, `ui_manager`. Matches the broad list dynamic_cosmetic_portraits uses, since rarity backgrounds render in identical surfaces.

`modded_rarities.lua` gained step 8 in `register_rarity()`: writes `opts.texture` into `UISettings.item_rarity_textures[name]` so vanilla code resolves the rarity name to our texture. The default `"modded"` registration now sets `texture = "icon_bg_modded"`.

## 0.7.0-dev (2026-05-12) — Custom `modded` rarity replaces `promo` for crafts
Promo rarity blocked customization. Vanilla source has two hard-coded gates that special-case `"promo"` and `"default"`:

- `ui_widgets_honduras.lua:2407` — the inventory cog icon `content_check_function` disables itself when `(rarity == "default" or "promo")` and the slot type isn't in `InventorySettings.customize_default_slot_types_allowed[mechanism]`. In adventure mode that allowlist is `{}`, so the cog was disabled for every promo item — player couldn't even open the customization window.
- `hero_window_item_customization.lua:179` — `_setup_availble_states` collapses to just `{"item_setting"}` for default/promo, stripping properties, traits, and upgrade tabs.

Fix: register a new rarity `"modded"` that's not in those special-case lists, so both gates fall through to the normal `rarity_rating` chain. With `order = 4` (exotic-level) the cog opens AND all four customization tabs are available.

New file `modded_rarities.lua` exposes a reusable registry — `mod.register_rarity(name, opts)` — that wires a custom rarity into all 6 tables the game reads:

| Table | Purpose |
|---|---|
| `UISettings.item_rarity_order` | Sort order + drives `_setup_availble_states` |
| `UISettings.item_rarities` | Iteration list for rarity-filter UI |
| `RaritySettings` | `{display_name, color, frame_color, order}` |
| `RarityIndex` | Mirror of `.order` |
| `ORDER_RARITY` | Mirrored array (string keys + numeric indices) |
| `NetworkLookup.rarities` | Required for inventory sync round-trip |

Color is data — pass either an existing palette name (`"exotic"`, `"magic"`, etc.) OR a `{a, r, g, b}` table. Default for `"modded"` is soft pale gold `{255, 248, 237, 197}`. Hooks `_G.Localize` to resolve `rarity_display_name_modded` → "Modded".

All four new-craft paths in `crafting_in_modded.lua` (Athanor weapon equip, Athanor amulet, amulet `_upgrade_magic_level`, `_athanor_inject_item` fallback) plus two in `standard_forge.lua` switched from `rarity = "promo"` to `"modded"`.

Backward compat: `_forge_load` migrates pre-v0.7.0 saved crafts (`rarity == "promo"`) to `"modded"` on load and re-saves. `_cim_is_modded_item` accepts both `"modded"` and `"promo"` so any stragglers still surface in the salvage list. `NetworkLookup.rarities` still includes `"promo"` for legacy roundtripping.

Bumped version 0.6.4-dev → 0.7.0-dev (rarity migration = minor version bump).

## 0.6.4-dev (2026-05-10) — Defer-retry saved crafts that need other mods' ItemMasterList entries
Most likely root cause of "purple/crafted weapons treated as blacksmith variants" + "not showing in salvage": the v0.4.1 `rawget(ItemMasterList, item_key)` pre-check in `_athanor_inject_item` skips a saved craft whose `item_key` isn't registered yet (typical case: `cwv_*` keys when CWV hasn't finished its `_create_interfaces` hook). The crafted item never enters the mirror this session, so the player sees the blacksmith template in that slot instead.

Three changes:

1. **Skipped injections are now deferred, not lost.** `_athanor_inject_all` tracks skipped bids in `_pending_inject = { [bid] = weapon_data, ... }`.
2. **Retry on every state change.** New `mod.on_game_state_changed` calls `_athanor_retry_pending()`. Once the sibling mod registers the missing key, the next state transition re-injects the saved craft.
3. **Skip-already-injected.** When `_create_interfaces` fires multiple times (it does), `_athanor_inject_all` checks the mirror's `_inventory_items[bid]` first — avoids duplicate `add_item` calls and misleading "restored N" log lines.

Also promoted the "skipped N saved crafts" message from `mod:info` to `mod:echo` so it's visible in chat without opening the log.

## 0.6.3-dev (2026-05-10) — Amulet CRAFT button visible + clickable (was "Fully Upgraded" greyed)
The amulet's `upgrade_button` was rendering as "Fully Upgraded" and disabled. Two vanilla guards in `HeroWindowWeaveProperties._set_essence_upgrade_cost` (`hero_window_weave_properties.lua:1856-1897`):

- Line 1886: when `essence_amount` is nil, button text falls back to `Localize("menu_weave_forge_upgrade_loadout_button_cap")` = "Fully Upgraded". Our weaves hooks always return 0/nil essence so this branch always fires.
- Line 1895: `disable_button = script_data["eac-untrusted"] or ...` — modded realm sets `eac-untrusted = true`, so the button is permanently disabled.

Post-hooked `_set_essence_upgrade_cost` (runs on every refresh) to override:
- `button_content.title_text` = "CRAFT MODDED JEWELLERY" (amulet path) or "CRAFT NEW WEAPON" (single-item path)
- `button_hotspot.disable_button = false`
- Hides the price-icon alpha + the "not enough essence" warning widget

Combined with the existing `_upgrade_magic_level` hijack (which performs the actual craft on click), the button is now both visible AND functional.

## 0.6.2-dev (2026-05-10) — `/salvage_debug` diagnostic command
Adds a focused diagnostic for "why isn't my modded craft showing in salvage?". Dumps every entry in `_forged_weapons` plus whether it's currently in the backend mirror (`inv=Y/N`), the mirror's rarity, the slot_type, the item_key, and the bid. Also dumps any promo-rarity items in the mirror that AREN'T in our save (orphans).

Most likely failure modes the dump reveals:
- `inv=N` → the saved craft didn't re-inject this session (ItemMasterList key not registered yet — usually a `cwv_*` key with CWV not loaded at our hook time).
- `rarity != promo` → the item's CustomData didn't round-trip through `_update_data` correctly, so the rarity-based salvage fallback misses it.
- `slot=<no data>` → the item's `data` field is nil; usually means the ItemMasterList entry is missing.

## 0.6.1-dev (2026-05-10) — Salvage rarity fallback + forward-declare `_amulet_dirty`
Two fixes:

1. **Salvage now matches by `rarity == "promo"` first.** Added `mod._cim_is_modded_item(item)` — same as the bid-heuristic check, plus an early-return for `item.rarity == "promo"`. Salvage post-hook switched to it. Catches modded crafts whose backend_id format doesn't fit the current regex (older mod versions, items synced from another machine, etc) — the user reported a saved purple-rarity axe+falchion not surfacing.

2. **Forward-declare `_amulet_dirty` at the top of the Athanor section.** v0.6.0 declared it `local` further down (line 959), but the `on_exit` reset at line 474 closed over it as a nil global → indexing `_amulet_dirty[1] = false` would have errored on forge close. Moved the declaration above the hook so both the hook and the helpers see the same upvalue.

## 0.6.0-dev (2026-05-10) — Amulet CRAFT button: per-slot dirty tracking, modded copies on edit
The amulet's CRAFT button (repurposed `upgrade_button`) now handles the 3-accessory case. When the player edits bubbles or trait slots in the amulet, we mark the matching accessory dirty (`_amulet_dirty[1..3]`); pressing CRAFT iterates the three slots and creates a new modded item only for slots that were edited this session.

For each dirty slot we read the equipped item's current `properties` / `traits` (already mutated in-place by auto-apply on bubble click), clone them into a new modded item via `_athanor_inject_item`, persist via `mod._cim_register_craft`, and equip via `set_loadout_item`. Vanilla items the player edited get a permanent modded counterpart; modded items they edited get a fresh saved snapshot.

Pressing CRAFT with no edits echoes "No accessory edits to craft" and does nothing. Dirty flags reset on `HeroViewStateWeaveForge.on_exit`.

Updated `AMULET_OF_ASHUR.md` with full status, slot-order rationale, data-flow summary, and remaining polish items.

## 0.5.6-dev (2026-05-09) — Fix amulet slot index mapping (charm/necklace were inverted)
The user reported necklace data displayed at the top of the amulet view but the picker (the menu where you choose properties / traits) was showing CHARM options. Root cause: vanilla `WeaveCareerProgression` orders the amulet's 3 slots by accessory POOL:

- slot 1 = `offence_accessory` → **charm**
- slot 2 = `defence_accessory` → **necklace**
- slot 3 = `utility_accessory` → **trinket**

`HeroWindowWeaveProperties._setup_menu_options` reads the `category` field on each progression entry and renders the matching property/trait pool in the picker. I'd assigned necklace=1, charm=2, trinket=3 — exactly inverted for slots 1 and 2 — so the necklace's data went into a slot whose picker rendered charm options.

Fixed `_AMULET_SLOT_BY_INDEX` to match `WeaveCareerProgression`. Both `_forge_seed_item` and `_forge_apply_to_amulet` iterate the same table, so the apply path is consistent.

## 0.5.5-dev (2026-05-09) — Adventure talents wired into the amulet's talent picker
The amulet UI's talent picker shows the player's career talent tree from `WeaveLoadoutSettings[career].talent_tree` — which is set to `TalentTrees[profile][index]` (see `weave_loadout_settings_*.lua`), i.e. exactly the same 6×3 tree adventure mode uses. So the talents the player sees ARE adventure talents.

Wired three hooks for read/write:

- **`get_loadout_talents`**: reads the player's adventure picks via `Managers.backend:get_interface("talents"):get_talents(career)` (returns array of 6 column picks 1..3), maps each row's pick to its talent name via `TalentTrees[profile][index][row][pick]`, returns `{[talent_name] = row}` — the format the bubble grid expects.
- **`set_loadout_talent(career, talent_name, row)`**: finds which column in that row owns `talent_name`, calls `talents:set_talents(career, picks)` with the updated array. Write-through to vanilla: the player's actual career talents change immediately and persist via the regular adventure save layer.
- **`remove_loadout_talent`**: no-op. The bubble grid emits remove→set pairs on each swap; we commit the new pick directly in `set_loadout_talent`, no need to model the intermediate state because adventure rows always have one talent.

Now opening the amulet should show your current talent picks highlighted, and changing them in the picker writes through to your actual career.

## 0.5.4-dev (2026-05-09) — Fix amulet slot names (charm + trinket weren't populating)
The amulet seed/apply was reading `slot_charm` and `slot_trinket`, but VT2's `career_settings` names them `slot_ring` (legacy) and `slot_trinket_1`. `get_loadout_item_id(career, "slot_charm")` returned nil, so the seed silently dropped both items — only the necklace populated the bubble grid.

Centralized the slot list in `_AMULET_SLOT_BY_INDEX = { [1] = "slot_necklace", [2] = "slot_ring", [3] = "slot_trinket_1" }` and updated both `_forge_seed_item` and `_forge_apply_to_amulet` to iterate it. Charm and trinket should now populate (and apply correctly to the right items on edit).

Talents (the 6 talent slots in the amulet layout) still aren't populated — that needs translating adventure talent picks (numeric 1-3 per row) into the weave-talent name format the bubble grid expects, which is a separate integration.

## 0.5.3-dev (2026-05-09) — Surface modded items in salvage regardless of equip state
The salvage filter post-hook was respecting vanilla's "no equipped, no in-loadout, no favorited" rule for modded items. That hid every freshly-crafted modded item — we auto-equip on craft via `set_loadout_item`, so the new item is immediately considered equipped + in-loadout, making it un-salvageable.

Modded crafts are throwaway by design — the user owns their lifecycle and should be able to scrap them at will. Relaxed the post-hook to add modded items unconditionally (still slot-typed to weapons/jewellery only). Vanilla items keep the original guards.

## 0.5.2-dev (2026-05-08) — Fix salvage crash on UI reward presentation
Salvage was crashing the game with `backend_interface_item_playfab.lua:354: attempt to index local 'item' (a nil value)`. The salvage page's `on_craft_completed` iterates the craft result and calls `_set_reward_material_by_index(backend_id, amount)` → `item_interface:get_key(backend_id)` → unguarded `item.key`. Vanilla's salvage result contains produced-material bids (scrap / dust); our synth was incorrectly putting the consumed weapon bids in there, and those bids were already removed from the mirror by the time the UI processed them → nil item → crash.

Fix: salvage synth now returns an empty result `{}` (we don't produce materials in modded). The UI iterates nothing, no nil access. The actual removal + unregister + loadout-clear logic is unchanged.

## 0.5.1-dev (2026-05-08) — Amulet bubble seed + apply for properties & traits
Wired the seed/apply chain for the amulet's 3-item case:

**Seed** (`_forge_seed_item` with `item_backend_id == nil`): reads the player's currently equipped necklace, charm, and trinket and packs each item's properties into its own bubble layer (necklace = slot indices 1..10, charm = 11..20, trinket = 21..30). Each item's first trait fills the matching trait widget (necklace = trait slot 1, charm = trait slot 2, trinket = trait slot 3).

**Apply** (`_forge_apply_to_amulet`): groups property fills by layer to figure out which accessory each bubble belongs to, converts back to fractional values, and writes to each accessory's `item.properties` / `item.traits` in the local mirror. Modded items also flush to the `_forged_weapons` save layer.

Talents are still TBD (the 6 talent slots in the layout populate from `BackendInterfaceWeavesPlayFab.get_loadout_talents`, which we currently return `{}` from). Wiring those to adventure talents is the next push.

## 0.5.0-dev (2026-05-08) — Amulet click flows through to vanilla 3-section UI
**Major rework**: vanilla `HeroWindowWeaveProperties.on_enter` already chooses between two pre-built layouts based on `_selected_item()`:
- `weapon_slot_layout` (1 trait + 10 properties) when an item is selected
- `amulet_slot_layout` (3 trait slots × 30 property slots in 3 layers + 6 talent slots) when no item is selected

The amulet viewport's `data.item` is nil, so a click already routes to `weave_properties` with `selected_item = nil` → vanilla auto-renders the WoM-style 3-section amulet UI we wanted. The previous cycling-through-slots approach was OVERRIDING this with the single-item layout. Reverted.

What's now live:
- Amulet viewport title shows "JEWELLERY / Necklace + Charm + Trinket"
- Click flows to vanilla weave_properties → 3-section UI renders
- The CRAFT button (repurposed upgrade_button) still fires our craft logic, but currently expects a single selected_item — needs rework for the 3-item amulet case (next phase)

What's NOT yet wired:
- Bubble grid is empty on entry (our `_forge_seed_item` returns empty for nil item_backend_id) — needs to read necklace + charm + trinket and merge
- Apply (in-place edit) doesn't distribute properties to the correct accessory yet
- CRAFT for amulet should produce 3 new items (one per slot) instead of one
- Talent row reads from `BackendInterfaceWeavesPlayFab.get_loadout_talents` (we return `{}`) — need to redirect to adventure talents

These come in 0.5.x patches. This release exists to verify the right UI renders.

## 0.4.5-dev (2026-05-08) — Per-slot Craft label + non-modded edit hint
- The CRAFT button now reads "CRAFT NEW NECKLACE" / "CRAFT NEW CHARM" / "CRAFT NEW TRINKET" / "CRAFT NEW WEAPON" depending on the source slot.
- When the player opens the editor for a non-modded item, a one-time `mod:echo` reminds them that bubble edits are session-only and CRAFT makes a permanent modded copy.

## 0.4.4-dev (2026-05-08) — Craft button in the bubble-grid editor (Phase A.5 partial)
The properties window's `upgrade_button` (vanilla "Upgrade Power" for Winds of Magic) is now repurposed in the modded forge as **CRAFT**. Hijacked `HeroWindowWeaveProperties._upgrade_magic_level` to short-circuit the vanilla magic-level upgrade and instead:

1. Read the currently selected item's `properties` and `traits` (already up-to-date because the bubble grid mutates them in-place via `_forge_apply_to_item`).
2. Synthesize a new modded item via `_athanor_inject_item` with `rarity = promo`, `via_mirror = true`.
3. Persist it in `_forged_weapons` via `mod._cim_register_craft`.
4. Equip it in the source slot (necklace / charm / trinket / melee / ranged).

The button's text widget is re-labeled to "CRAFT" and kept visible (previous versions hid it). The existing Apply flow (bubble click → in-place mutation) still works in parallel for editing equipped modded items without making a new copy. Greying the button when the equipped item is non-modded is still TBD (Phase A.5 finish).

## 0.4.3-dev (2026-05-08) — Amulet click auto-cycles slots; viewport title shows next slot
The amulet viewport's title now reads `EDIT: NECKLACE` / `EDIT: CHARM` / `EDIT: TRINKET` to indicate which accessory the next click will edit. After each click+edit, the amulet's slot pointer auto-advances to the next accessory — three clicks in a row visit all three.

The slot pointer (`mod._cim_amulet_slot`) is reset to necklace whenever `HeroViewStateWeaveForge.on_enter` fires so each forge session starts in a known state. The `/amulet_n` / `/amulet_c` / `/amulet_t` commands still let the user jump directly.

The existing weave Apply flow (bubble grid → `_forge_apply_to_item` → `item.properties`) already handles accessory items because their property keys map cleanly to `WeaveProperties` weave-prefixed entries. No changes needed for Apply on jewellery.

## 0.4.2-dev (2026-05-08) — Amulet routes to weave_properties for chosen accessory (Phase A.3 partial)
The amulet viewport click now actually opens the bubble-grid editor for the player's selected jewellery slot. We pre-populate `self._params.selected_item / selected_slot_name / selected_unit_name` (matching what vanilla's `_handle_input` does for melee/ranged) and let the parent state transition to `weave_properties` normally.

The slot cycle lives on `mod._cim_amulet_slot` (default `slot_necklace`). Three console commands set it: `/amulet_n`, `/amulet_c`, `/amulet_t`. The next phase will replace these with on-screen Necklace / Charm / Trinket buttons inside the editor and add the Apply / Craft buttons.

The bubble grid renders via `WeaveProperties` weave-prefixed entries; accessory props (`weave_protection_chaos`, `weave_curse_resistance`, etc.) are present in WeaveProperties so the existing `_forge_seed_item` mapping works without changes.

## 0.4.1-dev (2026-05-08) — Crash fix + amulet click stub (Phase A.2)
**Crash fix.** A saved `cwv_*` craft (e.g. `cwv_es_javelin`) was triggering `[ItemMasterList] ItemMaster List has no item cwv_es_javelin → game close` during `_create_interfaces`. The `_athanor_inject_all` re-injection runs before `character_weapon_variants` registers its variants in `ItemMasterList`. Added a `rawget(ItemMasterList, item_key)` pre-check in `_athanor_inject_item`: skip + log if the key isn't registered yet. Affected items just won't be re-injected this session (re-craftable).

**Bogus hook removed.** v0.3.10 added a hook for `HeroWindowCraftingInventory` (non-Console variant) — that class doesn't exist in current VT2 builds, VMF logged "trying to hook object that doesn't exist". Guarded with `rawget(_G, "HeroWindowCraftingInventory")`.

**Phase A.2 stub.** Amulet viewport click now intercepted in `HeroWindowWeaveForgeOverview._handle_input` — echoes a placeholder instead of letting vanilla route to `weave_properties` with a nil item (which would have entered a broken state). Phase A.4 will swap the echo for the real 3-subsection editor window.

## 0.4.0-dev (2026-05-08) — Athanor amulet viewport visible (Phase A.1)
First step of the AMULET_OF_ASHUR.md plan. The central amulet viewport is now visible in the modded Athanor — `_initialize_viewports` hook flips `amulet_introduced` from `false` to `true`, and `_forge_apply_ui_polish` no longer force-hides the viewport_2 widget cluster. Click currently still routes to vanilla `weave_properties` (with no item, so probably a no-op or weird state). Phase A.2+ will wire the click to a custom 3-subsection editor for necklace/charm/trinket plus talents.

## 0.3.12-dev (2026-05-08) — Athanor hover preview uses the standard item-tooltip box
The B-hotkey forge previously rendered a custom three-panel preview (overview / properties / trait) built from `UIWidgets.create_item_option_*`. Replaced with a single `UIWidgets.create_simple_item_tooltip` widget — the same tooltip pass (`item_tooltip`) that the regular inventory and crafting menus show on hover. Same set of `tooltip_passes` as the deus run-stats screen (item_titles, properties, traits, light/heavy/push/ranged attack stats, etc).

`_forge_populate_item_panels` and `_forge_hide_item_panels` collapsed to a single `tt.content.item = item or nil` call. `_wt_overview_widget`/`_wt_properties_widget`/`_wt_trait_widget` removed.

## 0.3.11-dev (2026-05-08) — Reroll properties / traits with shuffle-bag (no repeats)
Implemented `reroll_weapon_properties`, `reroll_jewellery_properties`, `reroll_weapon_traits`, `reroll_jewellery_traits`. Reroll cycles through every entry in `WeaponProperties.combinations[<prop_table>].exotic` (or `WeaponTraits.combinations[<trait_table>]`) before repeating any — when the bag is exhausted it resets and starts over.

Each item's shuffle state lives in its `_forged_weapons` save entry (`rerolled_props_indices`, `rerolled_trait_indices`), so closing/reopening the game doesn't reset the bag. Properties are always set to max value (1.0); the user gets to see every combo without the dice working against them.

Added two public helpers on the mod object: `mod._cim_get_craft(bid)` (returns the saved entry) and `mod._cim_persist_crafts()` (writes `mod:set("forged_weapons")`).

## 0.3.10-dev (2026-05-08) — Hide crafting-material displays
Modded crafting doesn't consume materials, so showing scrap/dust counts and recipe ingredient costs was just clutter. Two hooks:

1. **Per-recipe ingredient list** — post-hook `setup_recipe_requirements` on every material-gated CraftPage (and its console twin) sets `material_text_*` and `material_icon_*` widget visibility to false after vanilla populates them.
2. **Top inventory material panel** — post-hook `HeroWindowCraftingInventoryConsole._update_crafting_material_panel` (and the non-console variant) hides the row showing player material counts.

Both apply each refresh, so any ticks that re-show the widgets are immediately re-hidden.

## 0.3.9-dev (2026-05-08) — Auto-hide vanilla weapons from all crafting menus
The inventory filter now also engages whenever the standard crafting UI is open (`mod._cim_standard_forge_active`), regardless of the "Show only modded weapons" setting. Rationale: vanilla weapons can't actually be salvaged/upgraded/rerolled in modded realm — the commit-block prevents PlayFab from learning about the change, so vanilla items revert on next session. Showing them in crafting menus was misleading.

Default-rarity items (blacksmith's templates) still pass through the filter — the "Craft Item" recipe uses `can_craft_with` which only matches default rarity, so removing them would break the choose-what-to-craft flow.

## 0.3.8-dev (2026-05-08) — Surface modded crafts in the salvage inventory grid
The vanilla `can_salvage` filter macro (`backend_interface_common.lua:412`) explicitly excludes `rarity == "promo"` and `rarity == "magic"`, so our modded crafts (always promo for the purple icon) were filtered out of the salvage tab — the user couldn't drop them in to scrap. Added a post-hook on `BackendInterfaceCommon.filter_items`: when the filter expression contains `can_salvage`, scan the input items for any modded backend_ids that the vanilla filter excluded, and add them back if they pass the same equipped/loadout/favorited checks. The salvage UI now shows promo modded crafts alongside vanilla salvageable items.

## 0.3.7-dev (2026-05-08) — Salvage now persistently removes modded crafts
The salvage synth removed items from the local mirror, but modded crafts saved in `_forged_weapons` would be re-injected on next session — making them effectively unsalvageable across runs. Salvage now also calls `mod._cim_unregister_craft(bid)` (drops the save entry) and `mod._cim_clear_modded_loadout_for_bid(bid)` (removes any (career, slot) entry pointing at the salvaged item, so loadout-restore doesn't try to re-equip a deleted item). Added an `mod:echo` summary so the player sees what was scrapped.

Vanilla items still revert on game restart because the commit-block prevents PlayFab from learning about the local removal — this is intentional, the only way to actually delete a vanilla item is via the live PlayFab session.

## 0.3.6-dev (2026-05-07) — Standard-forge crafts roll 2 max props + 1 trait + promo rarity
Standard-forge crafts now produce the same "good" item shape as the Athanor:
- **Rarity = `promo`** (purple icon background — signals "modded craft" in the inventory grid).
- **2 random properties** rolled from `WeaponProperties.combinations[<weapon's property_table>][exotic]` (the 2-property tier), each set to **max value (1.0)**.
- **1 random trait** rolled from `WeaponTraits.combinations[<weapon's trait_table>]`.
- Properties and traits are also written into `CustomData.properties`/`CustomData.traits` (cjson-encoded) so `_update_data` picks them up after `add_item`, and saved into `_forged_weapons` so they persist across game restarts.

Vanilla rolled within the slot type and didn't always max stats; modded mode prefers reliable maxed gear since players are choosing what to craft.

## 0.3.5-dev (2026-05-07) — Always clone the dropped weapon (default-rarity is the chosen weapon)
v0.3.1–0.3.4 only cloned the dropped weapon when its rarity was NOT "default" — exactly backwards. The "blacksmith's weapons" players drop into the recipe slot ARE default-rarity items (starter weapons like the Imperial Longsword the character spawned with). They represent a specific weapon type, not a generic placeholder. Skipping them sent every craft to the random pool, which happened to land on similar weapons and looked like "always crafts my currently equipped weapon type".

Fix: clone the dropped item's `key` / `ItemId` regardless of rarity. The random pool now only fires when the slot is genuinely empty.

## 0.3.4-dev (2026-05-07) — Re-enable mutating standard-forge recipes (cim was not the cause)
The cosmetic regression reported in 0.3.3 was on the **vanilla gear icon** path (`HeroWindowItemCustomization` → cosmetics_tweaker's own `craft` hook), not cim's standard-forge "Apply Illusion" tab. cim's standard-forge synth was never invoked in that flow because `_cim_standard_forge_active` is only set while `HeroWindowCrafting`/`HeroWindowCraftingConsole` is open — the gear icon opens a different window. Re-enabled `salvage`, `apply_weapon_skin`, `extract_weapon_skin`, `upgrade_item_rarity_*`. Investigating the cosmetics_tweaker side separately.

## 0.3.3-dev (2026-05-07) — Disable mutating standard-forge recipes (cosmetic interaction bug)
User reported that applying a skin to a CWV Imperial Longsword via the standard forge "permanently overrode an existing cosmetic option". The mutating synth functions (`salvage`, `apply_weapon_skin`, `extract_weapon_skin`, `upgrade_item_rarity_*`) all call `mirror:update_item` / `mirror:remove_item`, which writes through `_update_data` and may corrupt the canonical state of mod-injected items (CWV weapons in particular have their own session-regenerated state). Disabled all four until we understand the failure mode. Additive recipes (`craft_random_item` / `craft_weapon` / `craft_jewellery`) remain enabled — they only call `mirror:add_item` with a fresh backend_id, the proven-safe Athanor pattern.

## 0.3.2-dev (2026-05-07) — Resolve craft target via item.key/ItemId; restore CWV in random pool
- **Use `get_item_from_id(bid)`** to resolve the dropped item's `.key` and `.ItemId` (which `_update_data` populates from the ItemMasterList lookup). v0.3.1 used `get_item_masterlist_data` which returns the ItemMasterList entry but doesn't carry the lookup key, so the clone target was nil and the synth fell through to the random pool every time.
- **Re-include `cwv_*` keys in the random pool** — user wants modded variants available there too.
- Added `[cim] Cloning chosen weapon: <key>` echo whenever the synth picks up a real weapon from the slot.

## 0.3.1-dev (2026-05-07) — Specific-weapon crafting + exclude CWV from random pool (superseded by 0.3.2)
- **Drop a real weapon to clone it.** When the player puts a non-default-rarity item in the craft slot, the synth now uses that item's exact `ItemId` instead of rolling random within the slot type. Drop a halberd → get a copy of that halberd.
- **Excluded `cwv_*` keys from the random pool.** They live in `ItemMasterList` from the character_weapon_variants mod and were being rolled, producing duplicates of items the player already owned.
- Random pick is still the fallback when the slot is empty or holds a default-rarity placeholder.

## 0.3.0-dev (2026-05-07) — Persistent modded inventory + filter + loadout restore
Three new behaviors aimed at making modded play feel like a separate sandbox:

1. **Standard-forge crafts now persist across game runs.** Items created via the inventory crafting tab are saved to `mod:set("forged_weapons")` (same layer as the Athanor) and re-injected on `BackendManagerPlayFab._create_interfaces`. New `via_mirror` flag on each saved entry distinguishes mirror-path items (Athanor + standard forge → restored via `backend_mirror:add_item`) from MIL-path items (legacy `/forge_confirm` → restored via MoreItemsLibrary). Public helper: `mod._cim_register_craft(backend_id, weapon_data)`.

2. **Toggleable inventory filter** — VMF setting *"Show only modded weapons in inventory"* (default off). When on, hooks `BackendInterfaceItemPlayfab.get_filtered_items` and drops every item whose `slot_type` is `melee`/`ranged`/`trinket`/`ring`/`necklace` AND whose `backend_id` doesn't match a modded pattern (`cwv_*`, UUID format, or registered in `_forged_weapons`). Crafting materials and cosmetics are unaffected.

3. **Modded loadout restore** — VMF setting *"Restore modded loadout each session"* (default on). Each time the player equips a modded item, the (career, slot) → backend_id is saved to `mod:set("modded_loadout")`. After re-injection on session start, those slots are re-equipped via `backend_items:set_loadout_item`, so switching to vanilla and back doesn't wipe the modded loadout.

New helpers exposed on the mod object: `mod._cim_register_craft`, `mod._cim_unregister_craft`, `mod._cim_is_modded_backend_id`.

## 0.2.7-dev (2026-05-07) — Diagnostics: synth echoes + `/craft_recent`
Added per-craft `mod:echo` showing the rolled item key + rarity + backend_id, plus a console command `/craft_recent` that lists every backend-mirror item flagged as new (post-load additions). Used to diagnose why crafted weapons weren't appearing in the inventory grid.

## 0.2.6-dev (2026-05-07) — Defense-in-depth: drop crafting* requests at the PlayFab queue
Two changes so a stray `crafting*` PlayFab request can never trigger the EAC kick:

1. **`craft()` no longer falls through to the original** when the forge is active. Previously, an unrecognized recipe (e.g. one we haven't synthesized yet) delegated to vanilla `craft()`, which enqueued an `ExecuteCloudScript` request with `send_eac_challenge = true` (`playfab_request_queue.lua:44`). In modded realm the EAC client is unavailable, so the response triggers `playfab_eac_error` (reason 511) → "Backend rejected the challenge response" → quit. Now we silently drop unrecognized recipes with an `mod:echo` instead.

2. **Added a `PlayFabRequestQueue.enqueue` hook** that drops any `crafting*` cloud-function request while the forge is open. Catches every known PlayFab crafting RPC: `craftingSalvage`, `craftingRandomItem`, `craftingSpecificItem`, `craftingRerollProperties`, `craftingRerollTraits`, `craftingUpgradeRarity`, `craftingApplySkin2`, `craftingExtractSkin`, `craftingDowngradeDust`. Other PlayFab traffic (achievements, daily quests, etc) continues to flow normally.

## 0.2.5-dev (2026-05-06) — Hook Console UI variants (real cause of "Backend rejected" kicks)
The inventory crafting tab on PC uses the **Console** UI classes (`HeroWindowCraftingConsole`, `CraftPageCraftItemConsole`, etc), not the desktop variants. v0.2.4 only hooked the non-Console classes, so `_cim_standard_forge_active` was never set, the commit-block never engaged, the craft request short-circuit never fired, the original `craft()` enqueued an EAC challenge to PlayFab, EAC client unavailable in modded realm → `BACKEND_PLAYFAB_ERRORS.ERR_PLAYFAB_EAC_ERROR` (511) → "Backend rejected the challenge response" → quit.

Fix: extended the lifecycle hooks to also cover `HeroWindowCraftingConsole.on_enter`/`on_exit`, and added all `*Console` CraftPage classes (`CraftPageCraftItemConsole`, `CraftPageRollPropertiesConsole`, `CraftPageRollTraitConsole`, `CraftPageUpgradeItemConsole`, `CraftPageApplySkinConsole`, `CraftPageConvertDustConsole`) to the `_MATERIAL_GATED_PAGES` list. Backend hooks (`_get_valid_recipe`, `craft`) are class-level and already fire regardless of UI variant.

## 0.2.4-dev (2026-05-06) — Fix duplicate `commit` hook (root cause of "Backend rejected" kicks)
v0.2.2 introduced a second `BackendManagerPlayFab.commit` hook in `standard_forge.lua` alongside the existing Athanor commit hook in the main module. VMF detected it as a rehook and **silently dropped the second registration** (warning at startup: "Attempting to rehook active hook [commit]"). The Athanor hook only checks `_custom_forge_active`, so during standard-forge use the commit was NOT blocked → mutations leaked to PlayFab → anti-tamper rejected the session.

Fix: single commit hook in main module checks both flags. `standard_forge.lua` now stores its active flag on `mod._cim_standard_forge_active` instead of installing its own hook.

## 0.2.3-dev (2026-05-06) — Implement craft-from-scratch (random item / weapon / jewellery)
- `craft_random_item`, `craft_weapon`, `craft_jewellery` now produce a new item via `backend_mirror:add_item` (purely additive — same pattern as the Athanor, no anti-tamper risk).
- Picks a random `ItemMasterList` entry filtered by: career's `can_wield`, slot_type matching the input placeholder if any, excluding weapon_skin / magic / promo rarities.
- Result rarity = `exotic`, power_level = 300. Properties/traits are empty by default; players can roll them via the Athanor (`B`) or the standard forge's reroll recipes once those are wired up.
- The input slot item is left intact (vanilla would consume it, but that triggers anti-tamper).

## 0.2.2-dev (2026-05-06) — Re-enable standard forge with Athanor commit-block pattern
Same `BackendManagerPlayFab.commit` no-op pattern the Athanor already uses for property/trait edits. The crash in v0.2.0 was caused by `CraftingManager.craft` calling `Managers.backend:commit()` after each craft, which pushed our local mutations to PlayFab → anti-tamper rejection. With the standard forge state tracked via `HeroWindowCrafting.on_enter`/`on_exit`, the commit hook now no-ops both Athanor sessions and standard-forge sessions. Mutations are session-only — they vanish on game restart when PlayFab reloads the canonical inventory.

## 0.2.1-dev (2026-05-06) — Disable standard forge hooks (PlayFab anti-tamper crash)
v0.2.0 mutated existing inventory items (`mirror:remove_item`, `mirror:update_item`) which triggered PlayFab's "Backend rejected the challenge response -1" anti-tamper response, kicking the session. The Athanor works because it only ADDS new items (server-tolerant of unknown GUIDs); modifying server-tracked items causes desync rejection. Re-disabled `standard_forge.lua` until the recipes are redesigned to use the additive pattern.

## 0.2.0-dev (2026-05-06) — Standard Keep forge support (BROKEN — see 0.2.1)
- Added `standard_forge.lua` module that enables the Keep's standard crafting menus (Olesya's Cauldron / Lohner's forge) in modded realm without requiring crafting materials.
- UI: post-hooks `setup_recipe_requirements` on 6 CraftPage classes (`CraftItem`, `RollProperties`, `RollTrait`, `UpgradeItem`, `ApplySkin`, `ConvertDust`) to force `_has_all_requirements = true`.
- Backend: hooks `BackendInterfaceCraftingPlayfab._get_valid_recipe` to bypass material validation; hooks `craft()` to short-circuit the PlayFab roundtrip and synthesize results locally.
- Implemented recipes: `salvage`, `apply_weapon_skin`, `extract_weapon_skin`, `upgrade_item_rarity_*` (4 tiers).
- Stubbed (falls through to vanilla, will fail in modded): `craft_random_item`/`craft_weapon`/`craft_jewellery`, `reroll_weapon_properties`/`reroll_jewellery_properties`, `reroll_weapon_traits`/`reroll_jewellery_traits`, `convert_blue_dust`/`convert_orange_dust`.

## 0.1.0-dev (2026-05-05) — Initial split from Weapon Tweaker
- Spun out the Athanor crafting system from `weapon_tweaker` into its own mod.
- Crafted weapons saved under `mod:set("forged_weapons")` in the new `cim` namespace; weapons saved under the old `wt` namespace are not migrated.
- All Athanor forge UI hooks, the B hotkey opener, item creation/persistence, and the `craft_dump` diagnostic command moved here.
