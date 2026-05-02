# Cosmetics Tweaker Code Review (2026-05-01)

## Summary

The cosmetics_tweaker mod is the largest and most architecturally complex
mod in the repo, spanning ~2800 lines of main Lua, ~600 lines of LA bridge,
and ~12000 lines of auto-generated unlock widgets / managed-item data.
Recent v0.7.83/v0.7.84 fixes (sync preload, `_override_package_ready` gate,
HeroPreviewer.equip_item skin tracking) are correctly implemented and
address real crashes. Overall architecture is sound — the three-rendering-
paths discipline is broadly observed, the LA bridge is well-isolated in a
separate module, and the previous-session lessons (forward-references,
crashify guards, VMF-injection format) are all encoded.

The dominant theme of remaining concerns is **unguarded `ItemMasterList[k]`
accesses where the key is not provably an IML key**. ItemMasterList's
`__index` calls Crashify for unknown keys (item_master_list.lua:133), so
each unguarded site is a latent crash whenever the mod meets a stranger
key — third-party skins, CWV variants, LA backend_ids that arrive via
preview hooks, etc. v0.7.21 fixed one such site (`_skin_requires_unowned_dlc`)
but several remain.

The custom-illusion `_description` localization is hard-coded to the same
text as `_name` in the runtime `_custom_loc` table, so the descriptive text
in `cosmetics_tweaker_localization.lua` is dead.

Hat tinting is wired only into the in-game body path; inventory previewer
and hero-selection previewer are not covered. Listed as "Experimental" so
arguably acceptable, but worth documenting.

## Confirmed bugs / potential bugs

### POTENTIAL BUG (high — crashify exposure)
**Unguarded `ItemMasterList[<dynamic_key>]` lookups in 7+ sites.**
ItemMasterList has a `__index` metamethod (item_master_list.lua:133) that
calls `Crashify.print_exception` on missing keys, throwing an exception.
v0.7.21 fixed this in `_skin_requires_unowned_dlc`; the rest were missed:

| File:Line | Site | Risk |
|-----------|------|------|
| cosmetics_tweaker.lua:1524 | `ItemMasterList[skin_key]` in `get_weapon_skin_from_skin_key` hook | High — `skin_key` is whatever the illusion grid passes in, including LA-bridge keys (in WeaponSkins.skins but NOT in IML) |
| cosmetics_tweaker.lua:1530 | `data = ItemMasterList[skin_key]` (same site) | High |
| cosmetics_tweaker.lua:1532 | `rarity = ItemMasterList[skin_key]…` (same site) | High |
| cosmetics_tweaker.lua:1407 | `ItemMasterList[illusion.matching_weapon]` | Low — keys controlled in `_custom_illusions` table |
| cosmetics_tweaker.lua:1863 | `ItemMasterList[item.key]` in `_get_weapon_key_from_item` | Medium — item.key may be CWV/LA |
| cosmetics_tweaker.lua:1880 | `ItemMasterList[item.key]` in `_setup_illusions` | Medium |
| cosmetics_tweaker.lua:2107 | `ItemMasterList[item_data.matching_item_key]` in `BackendUtils.get_item_units` hook | Medium |
| cosmetics_tweaker.lua:2213 | `ItemMasterList[item_data.matching_item_key]` in `_resolve_item_type` | Medium |
| cosmetics_tweaker.lua:2331 | `ItemMasterList[item_name]` in `_spawn_item_post` | High — `item_name` could be a clone backend_id post-equip-item-swap |
| cosmetics_tweaker.lua:2454 | `ItemMasterList[weapon_key]` in `LootItemUnitPreviewer.spawn_units` hook | Medium |

Fix: replace each with `rawget(ItemMasterList, k)`.

### POTENTIAL BUG (medium)
**Custom illusion `_description` overridden by `_name` text.**
cosmetics_tweaker.lua:1448-1450 sets
`_custom_loc[skin_key .. "_description"] = illusion.display_name`. The
`Localize` hook below (line 1453) returns `_custom_loc[key]` first, which
shadows the descriptive entries in `cosmetics_tweaker_localization.lua`
("An Empire mace paired with a Bretonnian shield." etc.). Fix: don't set
`_description` overrides — let them fall through to VMF's localizer.

### POTENTIAL BUG (low)
**Right-only `_fields` filter in `LootItemUnitPreviewer.spawn_units`
hook is fragile.** cosmetics_tweaker.lua:2484-2496. The `right_only` flag
is set true if ANY entry in `_fields` matches "right". Mixed
`{ "left_unit_3p", "right_unit_3p" }` would scale only the right; pure-left
`{ "left_unit_1p" }` would fall through to "scale all" (and scale the
right too). Today the only consumer is `_breton_sword_thiccc` (right-only
on `es_sword_shield_breton`), so no current bug, but the logic is fragile.

### POTENTIAL BUG (low)
**Hat tinting only fires on in-game body path.** The `_maybe_tint` call
sits inside `GearUtils.create_equipment` at line ~2257. It is NOT invoked
on `HeroPreviewer._spawn_item` (inventory previewer) or end-of-round
previews. Setting is labelled "Experimental" so arguably acceptable.

### POTENTIAL BUG (low — dead code)
**Captured-but-unused `orig_hook = BackendUtils.set_loadout_item`** in
`_fixup_server_clones` (cosmetics_tweaker.lua:2615). Local is set then
never read.

## Open questions

- **`hotspot.on_pressed` semantics** in offhand picker draw loop
  (cosmetics_tweaker.lua:2017-2023). If sticky-until-consumed, this could
  re-fire the click handler multiple frames in a row. Vanilla illusion
  buttons gate this through a state machine; ours doesn't.
- **`apply_offhand_to_unit(world, unit, armoury_key, vanilla_skin)`**
  parameters `world` and `vanilla_skin` are unused — kept for API parity
  with `apply_direct`. Drop or document?
- **MIL toggle-off path**: `la_bridge_enable = false` after a session with
  it on — registered IML entries persist (no MIL unregister). Documented?

## Refactor / cleanup candidates

- **`_resolve_intended_unit`** has unused `la_key` and `sorted_icons`
  parameters (la_bridge.lua:130). Can be dropped.
- **Massive auto-generated `_cosmetic_unlocks.lua`** (11929 lines) —
  perhaps split per-character to ease editor open-times? Pure
  developer-experience concern; runtime is fine.
- **Two unique scaling implementations** (`_scale_units` at line ~2161
  for in-game vs. inline scaling logic at lines ~2369-2404 in
  `_spawn_item_post`, and again at lines ~2462-2498 in the LootItemUnit
  hook). Three near-identical copies — would benefit from a single helper.
- **`_get_kruber_merc_hat_key` / `_get_kruber_merc_skin_key`** are
  hardcoded to `es_mercenary` and the only career with a portrait map.
  As more hats get portraits per the TODO, this needs generalization.
- **`U.managed`** in `_cosmetic_unlocks.lua` and `_CHARACTER_CAREERS` in
  `cosmetics_tweaker.lua` redundantly encode the character→careers map.
  The python generator already produces `info.character`; the Lua side
  hardcodes the inverse. Consider exposing `_CHARACTER_CAREERS` from the
  generator output to keep them in sync.

## Doc/code mismatches

- **DEVELOPMENT.md "Shield Weapons" table** lists `dr_shield_hammer`,
  `dr_shield_axe`, `wh_hammer_shield`, `wh_flail_shield` as "Weapon Key"
  — these are actually IML KEY NAMES (e.g. `dr_shield_hammer` is the IML
  key). The runtime `_offhand_options` is correctly keyed by `item_type`
  (`dr_1h_axe_shield`, `dr_1h_hammer_shield`, `wh_flail_shield`,
  `wh_hammer_shield`). The DEV doc conflates the two — inventory_settings
  also uses `dr_shield_hammer` etc. as item_type for some careers, while
  carousel/scorpion uses `dr_1h_*_shield`. Worth a note in
  DEVELOPMENT.md that `_offhand_options` is keyed by `item_type` and the
  table needs to cover ALL item_type strings sharing the same model
  family.
- **TODO.md "In Progress"** lists "Independent offhand illusion swap" as
  In Progress, but per the changelog v0.7.72-v0.7.84 the system is fully
  implemented and shipped, including LA shield integration. The "remaining"
  items (per-option rarity, persistence) are mostly done — rarity is
  applied via `widget.content.rarity = rarity`, but session persistence
  is not (selections are kept in-memory only via `_offhand_selection`).
- **TODO.md "Cosmetic unlocks — In progress"** is shipped (`_cosmetic_unlocks.lua`
  exists with 1500+ items, apply_cosmetic_unlocks runs on game state
  changes).
- **TODO.md "Custom illusion icons"** still accurate (placeholder icons
  remain).
- **CHANGELOG.md** is up to date through v0.7.84-dev (today's date).

## Settings coherence

The settings tree has three categories:
1. Top-level toggles (4): `dynamic_portraits`, `unlock_all_illusions`,
   `unlock_all_frames`, `la_bridge_enable`.
2. `appearance_group` → `weapon_model_group` (1: `es_bastard_sword_thiccc`)
   and `experimental_tints_group` (1: `tint_pureheart_white`).
3. Auto-generated `cos_unlock_*` widget tree (~1272 toggles).

Verified each top-level setting_id has matching `_data` widget,
`_localization` entry (with `_tooltip` companion), and is referenced from
`mod:get(...)` in `cosmetics_tweaker.lua`. No orphans found.

The auto-generated tree is correctly hooked up via `apply_cosmetic_unlocks`
and `mod.on_setting_changed`. The Localize keys (`cos_unlock_<career>_<key>`,
`cos_unlock_<career>_group`, `cos_unlock_<career>_hats_group`,
`cos_unlock_<career>_skins_group`, `cos_unlock_<character>_group`) all
match the python generator's output.

## Hook patterns

| Hook | Form | Notes |
|------|------|-------|
| `BackendUtils.get_item_units` | table-form, nil-guarded | Correct per CLAUDE.md |
| `BackendUtils.set_loadout_item` | table-form (inside install_skin_loadout_safety) | Correct — must be on BackendUtils, not items_iface (per v0.7.58) |
| `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` | string-form | Correct |
| `BackendInterfaceCraftingPlayfab.craft` | string-form | Correct |
| `BackendInterfaceCraftingPlayfab.update` (hook_safe) | string-form | Correct |
| `BackendInterfaceItemPlayfab.get_weapon_skin_from_skin_key` | string-form | Correct |
| `PlayFabMirrorBase.get_unlocked_cosmetics` (hook_safe) | string-form | Correct |
| `_G.Localize` | _G table-form | Correct |
| `HeroWindowItemCustomization.{_setup_illusions, _state_draw_overview, _enable_craft_button, _on_illusion_index_pressed, _update_state_craft_button}` | string-form | Correct |
| `HeroPreviewer.equip_item` / `_spawn_item` / `_spawn_item_unit` | string-form | Correct |
| `MenuWorldPreviewer.equip_item` / `_spawn_item` / `_spawn_item_unit` | string-form | Correct |
| `LootItemUnitPreviewer.spawn_units` | string-form (mod:hook, NOT hook_safe — per v0.7.74 lesson) | Correct |
| `GearUtils.create_equipment` | string-form | Correct |
| `UnitFrameUI.draw` (hook_safe) | string-form | Correct |
| `NewsFeedUI.draw` | hook_origin (full replacement) | Correct — per v0.7.4 fix; needed for hot-reload safety |
| `AttachmentUtils.link` (hook_safe) | table-form, rawget guarded | Correct |
| `World.link_unit` (hook_safe) | table-form, rawget guarded | Correct |
| `items_iface.{get_loadout, get_loadout_item_id, get_item_rarity}` | instance-form (table-form on captured instance) | Correct, but instance-form means hook is dead if backend manager replaces the instance — usually a session-restart event |

`BackendUtils.can_wield_item` is **not** hooked. Correct (per CLAUDE.md).

## Three rendering paths audit

| Override | In-game (`GearUtils.create_equipment`) | Inventory previewer (`HeroPreviewer._spawn_item`) | Illusion browser (`LootItemUnitPreviewer.spawn_units`) | Notes |
|---|---|---|---|---|
| `_weapon_scale_overrides` | ✓ via `_scale_units` | ✓ via `_spawn_item_post` (lines 2369-2404) | ✓ inline (lines 2462-2498), with `matching_item_key` resolution for skin keys | Three separate implementations; consider consolidating. |
| `_weapon_grip_offsets` | ✓ via `_offset_units` | ✗ Not in `_spawn_item_post` | ✗ Not in spawn_units hook | Currently unused (table is empty), but if grip offsets are added, must be patched into all three paths. |
| `_offhand_selection` (vanilla `unit` swap) | ✓ via `BackendUtils.get_item_units` hook (covers all three since they all call `get_item_units`) | ✓ (same hook) | ✓ (same hook) | Centralized — best pattern. |
| `_offhand_selection` (LA `intended_unit` swap) | ✓ same hook | ✓ same hook | ✓ same hook | Same as above. |
| `_offhand_selection` (LA texture paint) | ✓ via `_apply_la_offhand_to_units` in GearUtils hook | ✓ via `_spawn_item_post` | ✓ inline (line 2447 in spawn_units hook) | All three paths covered after v0.7.84 fix. |
| `_hat_tints` (Pureheart white) | ✓ via `_maybe_tint` loop | ✗ NOT applied | ✗ NOT applied | "Experimental" — gap acknowledged. |
| Portrait swap (career_settings) | n/a (data-source swap, propagates to every UI surface) | n/a | n/a | Per v0.7.62 architecture decision. Single point of mutation. |

`MenuWorldPreviewer._spawn_item_unit` is hooked **only for LA-clone hat
tracking** (`_spawn_item_unit_la_hook`), not for per-hand operations.
Consistent with CLAUDE.md guidance.

## Package loading audit

**`_preload_one(package_path)`** at lines 1669-1689:
- Sync (`async = false`). ✓ Per v0.7.83 fix.
- `pcall`-wrapped — swallows "package not found" for paths absent on
  user's install. ✓
- Idempotent via `_preloaded_offhand_packages[path]` cache.
- Reference name: `"cosmetics_tweaker"` (matches mod ID — packages stay
  resident under our refcount for the session).

**`_preload_offhand_package(unit_path)`** at lines 1691-1696:
- Loads BOTH `<unit_path>` AND `<unit_path>_3p` per v0.7.82 finding (the
  in-game body spawns both halves; the customization previewer spawns
  only 3p).

**`_preload_offhand_for_option(opt)`** at lines 1698-1702:
- Handles both vanilla `opt.unit` AND LA `opt.intended_unit`.

**Call sites:**
- `_setup_illusions` auto-select branch (line 1985): preloads on screen
  open.
- `_ct_on_offhand_pressed` (line 2039): preloads on user click.

**`_override_package_ready(unit_path)`** at lines 1708-1714:
- Defensive gate inside `BackendUtils.get_item_units` hook (line 2128).
- Checks BOTH 1p AND 3p packages before applying override. ✓

**Outstanding risk:** if a third party (e.g. another mod, or a future
weapon variant) sets a `_offhand_selection` entry without going through
`_setup_illusions` / `_ct_on_offhand_pressed`, the package preload would
be skipped, and `_override_package_ready` is the only safety net. The
gate logs a SKIP — this is correct, fail-safe behavior.

## UIRenderer._injected_material_sets safety

The portrait system uses VMF's `custom_gui_textures` API, declared in
`cosmetics_tweaker_data.lua` lines 75-125. Format is correct nested-table
form (per v0.7.51 fix): each `ui_renderer_injections` entry is a table
beginning with the renderer name (`"ingame_ui"`) followed by material
paths.

The mod does NOT manually mutate `UIRenderer._injected_material_sets`.
The `portrait_diag` command **reads** the table for diagnostic output but
does not write. ✓

The pre-v0.7.21 manual injection (`_ensure_material_injected`,
`_remove_injected_material`, `UIRenderer.create` hook) has been fully
removed. The `_injected_material_sets` poisoning lesson is encoded
correctly. ✓

The `NewsFeedUI.draw` hook_origin replacement (lines 593-631) provides
hot-reload safety per v0.7.4. Per-widget pcall keeps `begin_pass` /
`end_pass` balanced, and stale widgets are pruned after the pass closes.
Engine-level unbalanced pass-stack would cascade into other UI surfaces.

## Custom portrait system

| Asset | Count | Status |
|-------|-------|--------|
| `materials/ui/<name>.material` | 21 (7 hats × 3 sizes) | All declarations match texture filenames; `gui:DIFFUSE_MAP` shader, single `diffuse_map` slot |
| `gui/1080p/single_textures/custom_portraits/<name>.texture` | 21 | All point to matching `.png` filenames (verified 3 samples) |
| `gui/1080p/single_textures/custom_portraits/<name>.png` | 21 | Present |
| `cosmetics_tweaker.package` material entries | 21 | Match material filenames |
| `cosmetics_tweaker.package` texture entries | 21 | Match texture filenames |
| `cosmetics_tweaker_data.lua` `textures` | 21 | Match texture names |
| `cosmetics_tweaker_data.lua` `ui_renderer_injections[1]` | 22 entries (1 renderer name + 21 material paths) | Correct |
| `_PORTRAIT_MATERIALS` Lua list | 21 | Match (purely informational) |
| `_hat_portrait_map` Lua mapping | 7 hats | Each entry has `hud`/`medium`/`small` keys |

All seven Kruber Mercenary hat portraits (0004, 0006, 0007, 0009, 1001,
1002, 1003) are fully wired end-to-end. No orphans. No stragglers in
materials/ that aren't in the package, and no package entries without
files.

The portrait system follows the v0.7.62 architecture: swap
`SPProfiles[5].careers[1].portrait_image` directly. Single point of
mutation, propagates to HUD, hero selection, ESC menu, tab overlay, and
end-of-round automatically. Restoration via `mod.on_unload`.

The `_check_portrait_materials_ready` probe walks `_collect_all_guis`
and tests `portrait_kruber_mercenary_hat_1002` via `Gui.material()`.
Once any GUI has it, the flag is set and the swap can happen.

**Limitation**: only Kruber Mercenary hats have portraits today. Adding
other careers requires Photoshop work + extending `_hat_portrait_map`,
`_PORTRAIT_MATERIALS`, and the package + data declarations. Per the TODO,
the pipeline is planned but not built.

## LA bridge correctness

The bridge is well-isolated in `_la_bridge.lua` and uses correct timing:
- **`spawn_units` hook is `mod:hook` not `hook_safe`** (per v0.7.74 fix).
  We capture the returned `units` array directly because the caller
  (`_on_packages_loaded`) only assigns `self._spawned_units = units`
  AFTER `spawn_units` returns. ✓
- **Mesh-must-match-texture**: `intended_unit` from `variant.new_units[1]`
  is the source of truth (per v0.7.79). Texture-only variants
  (`new_units` absent) leave `intended_unit = nil`, letting LA paint onto
  whatever shield the user's vanilla illusion provides. ✓
- **Apply gate** uses raw function replacement (`LA.apply_new_skin_from_texture`
  re-assigned). Per v0.7.55 simplification, ALL managed armoury_keys are
  blocked by default; `_bridge_active` flag opens the gate for our own
  apply calls.
- **No global side effects**: `_paint_offhand_textures_locally` is a
  reimplementation of LA's `apply_texture_to_all_world_units` that touches
  ONLY the supplied unit's mesh materials — no `WeaponSkins.skins[…]
  .inventory_icon` or `ItemMasterList[…].inventory_icon` writes. Fixes the
  v0.7.78 leak.
- **Loadout cache** correctly hooks `BackendUtils.set_loadout_item`
  (table-form), NOT `items_iface.set_loadout_item` (per v0.7.58 lesson).
- **Read-time redirects**: `get_loadout` and `get_loadout_item_id`
  redirect server-leaked clone backend_ids to vanilla.
- **Startup fixup** (`_fixup_server_clones`) handles legacy session
  pollution.

`apply_offhand_to_unit` is gated on `has_skin = true` (per v0.7.78
"Override leaking onto base weapon template" fix) — base weapon spawns
with no skin no longer paint LA textures.

LA's `kind="unit"` variants are filtered out of the offhand pool
(`_is_supported_variant`) — they need LA's own package preload which
isn't wired up. Documented limitation.

## CWV integration

The mod skips CWV variants via `if not item_data.cwv_variant` in:
- `GearUtils.create_equipment` hook (line ~2253)
- `LootItemUnitPreviewer.spawn_units` hook (line ~2436)

This defers visual handling to character_weapon_variants. Correct per
CROSS_MOD_ARCHITECTURE.md. There's no positive integration here yet
(e.g. registering offhand options for CWV items), but the no-cross-talk
gate is in place.

`_get_weapon_key_from_item` (line 1862) doesn't have a CWV-aware path —
if a CWV item appears in inventory illusions (probably not since CWV
items are gated to MIL), `item.data.item_type` would be the CWV variant
type and `_offhand_options` lookup would miss. This is acceptable today.

## rawget guards

Confirmed correct usage:
- `_skin_requires_unowned_dlc` (line 36): `rawget(ItemMasterList, …)`
- `NetworkLookup.weapon_skins` membership check (line 1422): `rawget`
- `NetworkLookup.item_names` (la_bridge.lua:272): `rawget`
- `_la_bridge`'s `pick_vanilla_key` follow-up at la_bridge.lua:239:
  `rawget(ItemMasterList, vanilla_key)`
- `la_hats` command (cosmetics_tweaker.lua:2763):
  `rawget(ItemMasterList, item.key or bid)`

Missing rawget guards (per "Confirmed bugs" section above): 7 sites.

## Auto-generated `_cosmetic_unlocks.lua`

The 11929-line file is consistently formatted and matches what `_gen_unlocks.py`
emits. Spot-checked structure:
- `managed = { [item_key] = { section, character, native = {…} }, … }` ✓
- `localization = { cos_unlock_*_group = { en = "…" }, … }` ✓
- `widgets = { { setting_id, type="group", sub_widgets = { … } }, … }` ✓
- `return { managed = managed, widgets = widgets, localization = localization }` ✓

Generator-runtime alignment:
- `_CHARACTER_CAREERS` in cosmetics_tweaker.lua matches `CHARACTERS` in
  _gen_unlocks.py. ✓
- `wh_priest` excluded both ways. ✓
- Setting ID format `cos_unlock_<career>_<item_key>` matches between
  generator widget output (line 213 of generator) and runtime apply
  (cosmetics_tweaker.lua:1113 `mod:get("cos_unlock_" .. career .. "_" .. item_key)`).
- Group setting IDs `cos_unlock_<character>_group`,
  `cos_unlock_<career>_group`, `cos_unlock_<career>_<sec>_group` all
  declared in localization. ✓

The `default_value` per checkbox is `true` for native careers, `false`
otherwise — matches `apply_cosmetic_unlocks` behavior (toggle off → strip
career from `can_wield`).

`_cos_probe.txt` (1497 lines) is the input — leave alone unless re-running
probe.

## Non-obvious things now clarified

- **`_cosmetic_unlocks` per-item character coupling**: The python script
  rejects items native to multiple characters or to wh_priest only. So
  `U.managed` is a clean per-character partition — no item is owned by
  more than one character. This is how the strip-and-re-add pattern in
  `apply_cosmetic_unlocks` is safe: only the character's own careers are
  added/removed, leaving wh_priest untouched.
- **`_offhand_options` keyed by `item_type` not `key`**: This is the
  string from `ItemMasterList[k].item_type` (e.g. `dr_1h_axe_shield`,
  `wh_flail_shield`, `es_deus_01`), shared across multiple IML keys.
  `_get_weapon_key_from_item` resolves to `item_type` via
  `data.item_type` first. The aliases at lines 1772-1776 cover sibling
  weapon types that share offhand pools (mace_shield aliased to
  sword_shield, etc.).
- **Sync vs async preload race**: pre-v0.7.83, `Managers.package:load(…, true)`
  returned immediately while loading async; clicking Apply fast enough
  raced the spawn. Sync (`false`) blocks for ~one frame per shield.
  Acceptable hitch.
- **`NewsFeedUI.draw` hook is hot-reload protection**, not normal-game
  rendering protection — per v0.7.4, third-party atlases (LA's, VMF's)
  get torn down on hot-reload while their widgets are still on screen.
  Per-widget pcall keeps `begin_pass`/`end_pass` balanced.
- **`_bridge_active` flag**: opened only by `apply_direct` and our local
  paint helpers. LA's own update queues are blocked by the gate when
  closed. Without this, LA's autonomous loadout-watching hooks would
  silently override vanilla hats with LA textures.

## Dead code

- **`_PORTRAIT_MATERIALS` array** (cosmetics_tweaker.lua:499-521) —
  defined but never read. Could be removed; the data is duplicated in
  `cosmetics_tweaker_data.lua` `custom_gui_textures.ui_renderer_injections`
  which IS used.
- **`_skin_portrait_map`** (cosmetics_tweaker.lua:561) — defined as
  empty; populated by no code path; read by `_sync_portrait_settings`
  (line ~803) which falls through to `_restore_portrait_settings` if the
  hat key doesn't have a portrait. So this is a future-extension stub,
  not strictly dead.
- **`_get_hat_item_key_for_unit`** (line 686) — the generic version is
  defined but the only caller path uses `_get_kruber_merc_hat_key`
  instead. The generic helper is unused.
- **`_pending_local_craft`** is set/cleared correctly; no dead code there.
- **Captured `orig_hook` in `_fixup_server_clones`** (line 2615) —
  flagged as POTENTIAL BUG above; remove.
- **`_resolve_intended_unit` unused params** (`la_key`, `sorted_icons`)
  — kept from a prior heuristic; safe to drop.
- **`apply_offhand_to_unit` unused params** (`world`, `vanilla_skin`)
  — kept for API parity; safe to drop or document.

## Notes for future AI agents

1. **Forward references will crash this mod**. Five separate forward-
   reference bugs have been encountered in this codebase
   (feedback_lua_forward_reference.md). When adding a function, search
   for callers ABOVE it before saving. If a function is referenced in a
   hook closure, its definition must precede the hook installation point,
   not just exist somewhere in the file.
2. **Hot-reload is unfixable**. Do not add `mod.on_reload` handlers.
   Always restart the game after deploying. The `NewsFeedUI.draw`
   hook is protection against OTHER mods' hot-reload, not for our own.
3. **`ItemMasterList[k]` is dangerous**. Always `rawget(ItemMasterList, k)`
   when `k` could come from outside our control. Same for
   `NetworkLookup.weapon_skins` and `NetworkLookup.item_names`.
4. **VMF `custom_gui_textures.ui_renderer_injections`** must be a list
   of nested tables, each starting with the UI script name (e.g.
   `"ingame_ui"`) followed by material paths. Flat strings are silently
   skipped. NEVER manually inject into `UIRenderer._injected_material_sets`
   — Stingray will silently poison the entire Gui material loading pass.
5. **The three rendering paths**: in-game (`GearUtils.create_equipment`),
   inventory previewer (`HeroPreviewer._spawn_item`), illusion browser
   (`LootItemUnitPreviewer.spawn_units`). Every visual override must
   cover all three. `MenuWorldPreviewer._spawn_item_unit` is NOT usable
   for per-hand work (no hand indicator).
6. **`BackendUtils` is a plain table**. Hook with table-form
   (`mod:hook(BackendUtils, …)`), guard with `if BackendUtils then`.
   String-form does not resolve.
7. **`BackendUtils.set_loadout_item` ≠ `items_iface:set_loadout_item`**.
   For cosmetic slot writes, must hook the BackendUtils dispatch directly.
8. **Sync package load** = `Managers.package:load(path, ref, nil, false)`.
   Async (`true`) creates a race against the Apply button.
9. **Custom illusion `_description` localization** is currently shadowed
   by `_custom_loc[skin .. "_description"] = display_name` — see bug list.
   Don't add new descriptions to `_custom_illusions` and expect them to
   show; fix the shadow first.
10. **LA bridge requires Loremasters-Armoury AND MoreItemsLibrary**.
    `mod.update` defers init until both are detected. Toggling
    `la_bridge_enable` off mid-session does NOT unregister the items.
