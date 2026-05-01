# Cross-Mod Architecture — Weapon Sharing & Cosmetics

## Overview

Three mods with distinct responsibilities, designed to work independently but enhance each other when co-installed.

| Mod | Role | Dependencies |
|-----|------|-------------|
| **weapon_tweaker** | Unlocks existing weapons across careers (same item, different wielder) | None |
| **cosmetics_tweaker** | Cosmetic customization: offhand illusions, skins, icons, glow maps | None (optional: character_weapon_variants, MoreItemsLibrary) |
| **character_weapon_variants** | Adds brand-new weapon items combining models from multiple characters | MoreItemsLibrary |

---

## Mod 1: weapon_tweaker

**Responsibility:** Allow any character to equip any other character's existing weapons.

- Patches `can_wield` on `ItemMasterList` entries so career restrictions are lifted
- Handles animation remapping so cross-career weapons play correctly on the new skeleton
- Does NOT create new items — it unlocks existing ones
- Does NOT handle cosmetics — the weapon keeps whatever skin/illusion it already has

**What it does NOT do:**
- No new ItemMasterList entries
- No model swaps or cosmetic overrides
- No shield mixing across characters
- No custom icons or descriptions

**Interface point with character_weapon_variants:**
- weapon_tweaker may detect the character_weapon_variants and suppress redundant unlocks (e.g., if the new mod already provides "Imperial Axe and Shield" for Kruber, weapon_tweaker doesn't also need to unlock Bardin's axe+shield on Kruber)
- Optional: weapon_tweaker could offer a setting "Use [new mod] weapons instead of raw cross-career unlocks" for weapon types that have a purpose-built variant

---

## Mod 2: cosmetics_tweaker

**Responsibility:** Cosmetic customization — offhand illusion swaps, weapon skins, hat/outfit unlocks, glow maps, custom icons.

### Core features (independent, no other mods needed)
- **Offhand illusion swap:** Per-character curated shield/offhand options on the weapon customization screen
  - Options table keyed by `character + weapon_type`
  - Selection state keyed by `character + weapon_type` (no cross-character bleed)
  - Only shows lore-appropriate options for the current character by default
- **Hat/skin unlocks:** Intra-character cosmetic sharing
- **Weapon glow maps:** RGB color picker for `rune_emissive_color`
- **Custom illusion injection:** New weapon skins via WeaponSkins table patching

### Enhanced features (when character_weapon_variants is installed)
- Detects character_weapon_variants via `get_mod("new_weapons_mod_id")` at load
- Registers additional offhand options for new weapon items (e.g., the "Imperial Axe and Shield" item gets Kruber's full shield roster in offhand swap)
- Provides cosmetic variation on top of the new mod's base items
- Custom icons for new weapons could live here OR in the character_weapon_variants (TBD — wherever the icon assets are bundled)

### Enhanced features (when weapon_tweaker is installed)
- Detects weapon_tweaker via `get_mod("wt")`
- For raw cross-career unlocks (not new mod items), applies per-character cosmetic defaults so the weapon doesn't look out of place
- Example: Kerillian equipping Kruber's sword+shield via weapon_tweaker → cosmetics_tweaker auto-applies elven shield as default offhand

### What it does NOT do
- Does not create new weapon items (that's the character_weapon_variants)
- Does not unlock weapons across careers (that's weapon_tweaker)
- Does not change weapon mechanics, stats, or movesets

---

## Mod 3: character_weapon_variants

**Responsibility:** Create brand-new weapon items that combine models, animations, and stats from different characters into lore-friendly packages.

### Examples
| New Weapon | Character | Source Models | Notes |
|-----------|-----------|-------------|-------|
| Imperial Axe and Shield | Kruber | Saltzpyre's axe + Kruber's empire shields | Axe fits imperial aesthetic |
| Imperial Spear and Shield | Kruber | Kerillian's spear moveset + Kruber's shields | Different stats/moveset from Kruber's own spear+shield |
| (more TBD per case-by-case curation) | | | |

### Architecture
- **MoreItemsLibrary** (hard dependency) to register new `ItemMasterList` entries
- Each new weapon is a real networked item with:
  - Unique `item_key` (e.g., `kruber_imperial_axe_shield`)
  - Custom `inventory_icon` and `hud_icon`
  - Custom `description` text differentiating it from similar weapons
  - Proper `can_wield` restricted to intended character(s)
  - `left_hand_unit` / `right_hand_unit` pointing to the desired model combination
- Weapons obtained through a **crafting menu** (in-mod or via cosmetics_tweaker's planned crafting UI)
- **Multiplayer safe:** Items are real backend objects, network-replicated — all players with the mod see the same thing

### What it does NOT do
- No career unlocking (weapon_tweaker handles that)
- No cosmetic variation within a weapon (cosmetics_tweaker handles offhand swap etc.)
- No animation remapping (inherits from whatever weapon template it's based on, or weapon_tweaker provides remaps)

### Interface points
- **weapon_tweaker:** Can detect this mod and defer to its purpose-built items instead of raw cross-career unlocks for the same weapon type
- **cosmetics_tweaker:** Can detect this mod and register offhand/illusion options for its items

---

## Detection Pattern

All three mods use the same optional detection pattern:

```lua
-- In cosmetics_tweaker:
local cwv = get_mod("character_weapon_variants")  -- nil if not installed
local weapon_tweaker = get_mod("wt")               -- nil if not installed

if cwv then
    -- Register enhanced offhand options for new weapon items
    -- Register custom cosmetic defaults
end

if weapon_tweaker then
    -- Apply per-character cosmetic defaults for raw cross-career unlocks
end
```

No hard dependencies. Each mod's core features work standalone.

---

## Loremaster's Armoury Bridge (cosmetics_tweaker ↔ LA)

Exposes Loremaster's Armoury (LA) cosmetic recolors as separate equippable items in VT2's native inventory, so the player can have "Pureheart Red" and "Pureheart White" selectable side-by-side without LA's normal mode (which silently overrides a vanilla item's textures based on a VMF settings dropdown).

**Dependencies:** Loremaster's Armoury, MoreItemsLibrary (MIL). Both optional — bridge is a no-op if either is missing.

**Files:**
- `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua` — clone registration, apply gate, texture routing
- `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua` — loadout hooks, preview hooks, diagnostic commands (search for "LA bridge" / "la_bridge" / "loadout" sections)

### How it works end-to-end

#### 1. Clone Registration (boot time, `_la_bridge.lua:register_all`)

Iterates `LA.SKIN_LIST`, filters for `swap_hand == "hat" or "armor"`, matches each variant's `new_units[1]` to a vanilla `ItemMasterList` key via a unit-path index, then clones the IML entry:

```
backend_id = vanilla_key .. "_LA_" .. la_key
   e.g. "questing_knight_hat_0001_LA_Kruber_Pureheart_helm_red"
```

Clone entry modifications (`build_clone_entry`):
- `entry.key = suffix_id` — unique IML key
- `entry.name = suffix_id` — **critical**: the game's `parse_item_master_list()` sets `.name = key` on all IML entries at boot. Clones created after boot inherit the vanilla `.name` via `table.clone()`. If `.name` isn't overridden, `HeroWindowCharacterPreview._populate_loadout` thinks vanilla and clone are the same item and skips preview updates.
- `entry.display_name = suffix_id .. "_name"` — localization key, resolved via `_G.Localize` hook to "Human Readable (LA)"
- `entry.rarity = "exotic"` — orange border in the grid
- `entry.cos_la_armoury_key = la_key` — LA's internal key for texture lookup
- `entry.cos_la_vanilla_key = vanilla_key` — original hat key

Clones are registered with MIL via `mil():add_mod_items_to_local_backend(entries, "cosmetics_tweaker")` and added to `NetworkLookup.item_names` to prevent network-lookup crashes.

**Lookup tables** (all on the `M` module table):
| Table | Key → Value | Purpose |
|-------|-------------|---------|
| `backend_to_armoury` | clone backend_id → LA armoury_key | Identify which LA variant a clone represents |
| `backend_to_vanilla` | clone backend_id → vanilla IML key | Find the original hat for server-redirect and LA's `skin` arg |
| `armoury_to_backend` | LA armoury_key → clone backend_id | Gate: block LA from self-applying managed keys |
| `unit_path_to_clones` | vanilla unit path → list of clone backend_ids | In-game hook: detect when a clone's unit spawns |

#### 2. Apply Gate (`_la_bridge.lua:install_apply_gate`)

Raw function replacement on `LA.apply_new_skin_from_texture`. When a managed armoury_key fires AND `M._bridge_active` is false, the call is blocked. This prevents LA's own hooks (which watch loadout changes and queue texture swaps) from overriding vanilla hats with LA textures.

When the bridge itself wants to apply a texture, it sets `M._bridge_active = true`, calls the original function, then sets it back to false.

#### 3. Loadout Cache (cosmetics_tweaker.lua, `_install_skin_loadout_safety`)

Clone backend_ids must NEVER reach the PlayFab server — vanilla clients would crash on unknown ids. Pattern borrowed from AllHats mod (lines 38-71).

**Write hook** (`BackendUtils.set_loadout_item`):
- Clone equip → cache locally, do NOT call original (server never sees the clone id)
- Vanilla equip → clear cache entry, call original (server gets the vanilla id)

**CRITICAL**: Hook must be on `BackendUtils.set_loadout_item` (table-form), NOT on `items_iface.set_loadout_item`. The game's `_set_loadout_item` calls `BackendUtils.set_loadout_item()`, which dispatches via `Managers.backend:get_loadout_interface_by_slot(slot_name)` — this returns a DIFFERENT interface than `Managers.backend:get_interface("items")`. Hooking the items interface misses cosmetic slot writes entirely.

**Read hooks** (`items_iface.get_loadout`, `items_iface.get_loadout_item_id`):
- Merge cache into loadout reads so the game sees the clone as equipped
- Redirect any server-stored clone backend_ids to vanilla (defense against pre-hook leak)

**Startup fixup** (`_fixup_server_clones`):
- Reads raw server loadout (temporarily disabling cache), finds leaked clone ids, replaces them with vanilla via `get_loadout_interface_by_slot().set_loadout_item()` directly

#### 4. Preview Hooks (cosmetics_tweaker.lua)

**`MenuWorldPreviewer.equip_item` wrapping hook:**
When the cosmetics grid selects a clone, the game calls `equip_item(item_name, slot, backend_id)` where `item_name` is the vanilla key (from `item.data.name` which the game resolves from the backend item). The hook detects clone backend_ids and swaps `item_name` to the clone's `suffix_id`, so `ItemMasterList[suffix_id]` is used for spawn data (custom display name, custom rarity).

**`HeroPreviewer._spawn_item` / `MenuWorldPreviewer._spawn_item` wrapping hook:**
Sets `self._cos_la_spawning = backend_id` during clone spawns so downstream hooks (e.g. `_spawn_item_unit`) know to apply LA textures.

**Preview update mechanism** (`HeroWindowCharacterPreview._populate_loadout`):
The game compares `item.data.name` against the previewer's stored `item_name_by_slot_type()` to decide whether to re-equip. Since our clones have `entry.name = suffix_id` (unique per clone), switching between vanilla and any clone always triggers the re-equip.

#### 5. In-Game Texture Application

**`AttachmentUtils.link` hook** and **`HeroPreviewer._spawn_item_unit` hook_safe:**
When a hat unit spawns whose unit path matches a clone in `unit_path_to_clones`, the bridge checks whether that clone is equipped (via `find_active_clone_for_unit_path`). If so, it calls `apply_direct()` which:
1. Sets `M._bridge_active = true` (gate pass)
2. Calls `LA.apply_new_skin_from_texture(armoury_key, world, vanilla_key, unit)` directly
3. Sets `M._bridge_active = false`
4. Suppresses LA's queues for that unit to prevent double-application

If the vanilla hat is equipped (no clone), the bridge suppresses any LA queue entry for that unit.

### Diagnostic Commands

| Command | Purpose |
|---------|---------|
| `cos la_dump` | Registry contents: all clone backend_ids and their armoury_keys |
| `cos la_hats` | All hats for current career with VANILLA/CLONE labels, rarity, equipped status, cache state, raw server value |
| `cos la_trace 1/0` | Per-hook tracing of every equip_item, _spawn_item, AttachmentUtils.link firing |
| `cos la_force <key>` | Bypass detection, apply an LA variant directly to the player's spawned hat unit |
| `cos la_loadout` | Dump loadout_cache contents |
| `cos la_dump_attachments` | Walk player unit's attachment tree, dump unit_name/skin/hand per node |

### Lessons Learned (for future AI agents)

1. **`parse_item_master_list()` sets `.name = key`** on all IML entries at boot. Any entries added after boot (by MIL or direct IML insert) must set `.name` manually, or the preview system will treat them as identical to their clone source.

2. **`BackendUtils.set_loadout_item` ≠ `items_iface:set_loadout_item`**. The game dispatches loadout writes via `get_loadout_interface_by_slot()` which returns slot-specific interfaces. Hooking the items interface only catches weapon/trinket slots; cosmetic slots go through a different interface. Always hook `BackendUtils` directly for universal interception.

3. **Clone backend_ids MUST NOT reach the server.** Cache locally, merge into reads. If they leak (from sessions before hooks were installed), detect and replace on startup.

4. **LA's own hooks watch loadout changes and queue texture swaps autonomously.** The apply gate must block ALL managed armoury_keys by default, only opening for bridge-initiated calls via the `_bridge_active` flag.

5. **MIL does not propagate `rarity` for cosmetic items.** Setting `entry.rarity = "exotic"` and `mod_data.CustomData.rarity = "exotic"` on the clone entry does not guarantee the grid shows an orange border. The rarity may still read as "default" from the backend. Visual distinction relies primarily on the "(LA)" display name suffix.

6. **The preview character model is a separate `MenuWorldPreviewer` world**, not the in-game keep character. Hat changes in-game go through `attachment_extension:create_attachment_in_slot` on the player unit. Preview hat changes go through `MenuWorldPreviewer.equip_item` → `_spawn_item` → `_spawn_item_unit`.

7. **`_populate_loadout` only calls `equip_item` for items where `item.data.name ~= current_item_name`.** For melee/ranged, the condition is bypassed (`item_slot_type == "melee"` always passes). For hats/cosmetics, the `.name` check is the sole gate. This is why setting `.name = suffix_id` is critical.

---

## Multiplayer Compatibility Matrix

| Scenario | Visual Result |
|----------|--------------|
| All players have character_weapon_variants | Everyone sees correct models — real items sync via network |
| Host has character_weapon_variants, client doesn't | Client sees missing/unknown item — **mod required for all players** |
| Player A has cosmetics_tweaker, Player B doesn't | Offhand swaps are client-local only (player A sees their choice, player B sees vanilla) |
| Player A has cosmetics_tweaker + LA bridge, Player B doesn't | LA clone textures are client-local. Clone backend_ids never reach the server (loadout cache), so Player B sees the vanilla hat |
| Player A has weapon_tweaker, Player B doesn't | Cross-career weapons visible to both (items exist in backend), but animations may look wrong to player B |

---

## Open Questions

1. **Crafting menu ownership** — does the crafting UI live in character_weapon_variants, cosmetics_tweaker, or a shared UI mod? Simplest: in character_weapon_variants itself.
2. **Icon pipeline** — custom icons per new weapon. Format, resolution, and atlas injection method TBD (see cosmetics_tweaker TODO "Custom illusion icons").
3. **Animation ownership** — if a new weapon needs animation remaps, does character_weapon_variants ship them or delegate to weapon_tweaker? Cleaner if the new mod is self-contained, but duplicates weapon_tweaker's remap infrastructure.
4. **Scope of new weapons** — curated case-by-case. Need to enumerate which cross-character combos are worth building as real items vs. leaving as raw weapon_tweaker unlocks.
5. **Cosmetic curation approach** — lore-friendly by default, hand-picked per character. Only models and illusions matching the current character's aesthetic are shown.
