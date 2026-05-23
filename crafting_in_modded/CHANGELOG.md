# Crafting in Modded Changelog

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
