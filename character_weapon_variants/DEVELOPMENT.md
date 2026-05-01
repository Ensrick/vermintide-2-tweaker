# Character Weapon Variants — Development Guide

## Adding a New Variant Weapon

### Overview

A variant weapon is a new inventory item that uses an existing weapon template (moveset, stats, attack chains) but with different visual models. The system clones a base weapon's `ItemMasterList` entry, overrides the unit paths, registers a custom skin, injects it into `NetworkLookup`, and registers it via MoreItemsLibrary.

### Step 1: Define the variant

Add an entry to `_variant_definitions` in `character_weapon_variants.lua`:

```lua
{
    item_key        = "cwv_es_axe_shield_exotic",   -- unique key, prefix with cwv_
    base_weapon     = "dr_shield_axe",              -- ItemMasterList key to clone
    display_name    = "Imperial Axe and Shield",    -- shown in inventory
    description     = "A battle-hardened hatchet...",
    character       = "empire_soldier",             -- sp_profiles display_name
    careers         = { "es_mercenary", "es_huntsman", "es_knight" },
    right_hand_unit = "units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2_magic_01",
    left_hand_unit  = "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic",
    inventory_icon  = "icon_wpn_dw_shield_01_axe",  -- menu icon (icon_wpn_* atlas)
    hud_icon        = "weapon_generic_icon_axe_and_sheild", -- in-game HUD (weapon_generic_icon_* atlas)
    skin_display_name = "Imperial Axe and Shield",  -- shown in cosmetics menu
    rarity          = "unique",                     -- see Rarity section
    traits          = { "melee_counter_push_power" },
    properties      = { block_cost = 1, power_vs_skaven = 1 },
}
```

### Step 2: Localization

Localization is automatic. The Localize hook maps:
- `<item_key>_name` → `display_name`
- `<item_key>_description` → `description`
- `<item_key>_skin_name` → `skin_display_name`

### Step 3: Build and deploy

```powershell
Set-Location "C:\Users\danjo\source\repos\vermintide-2-tweaker"
node C:/Users/danjo/source/repos/vmb/vmb.js build character_weapon_variants --no-workshop --cwd
# Deploy to workshop folder
$wsDir = "C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\3716869446"
Get-ChildItem "character_weapon_variants\bundleV2" -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $wsDir $_.Name) -Force }
```

## Rarity

VT2 rarity values and their display:

| Value | Color | Display | Use |
|-------|-------|---------|-----|
| `"common"` | White | No background | — |
| `"plentiful"` | Green | Green background | — |
| `"rare"` | Blue | Blue background | — |
| `"exotic"` | Orange | Orange background | Standard max-rolled weapon |
| `"unique"` | Red | Red background | Veteran item (red illusion tier) |
| `"magic"` | Purple | Purple background | Weave-forged items |

### Critical: Rarity Registration Pattern

Items must be registered with `rarity = "default"` in `entry.rarity`, `mod_data.rarity`, and `mod_data.CustomData.rarity`. The actual display rarity is set **after** registration by modifying the live backend item:

```lua
-- During registration (in _build_entry):
entry.rarity = "default"
entry.mod_data.rarity = "default"
entry.mod_data.CustomData.rarity = "default"

-- After add_mod_items_to_local_backend + _refresh():
local item = backend_items:get_item_from_id(backend_id)
item.rarity = "unique"        -- display rarity
item.data.rarity = "unique"   -- data-level rarity
item.CustomData.rarity = "unique"  -- serialized rarity
```

If you set rarity directly on the entry (not `"default"`), the item renders as a template/blacksmith item with no rarity color, no cosmetics menu, and grey text.

## Skin System

Every variant weapon needs a custom skin registered in three places:

### 1. `WeaponSkins.skins[skin_key]`
Contains the unit paths the renderer uses. `BackendUtils.get_item_units` resolves models through the skin, completely overriding the base entry's unit paths.

### 2. `NetworkLookup.weapon_skins`
Required for network serialization. Must use `rawget`/`rawset` because the table has an error-throwing `__index` metamethod:

```lua
if not rawget(NetworkLookup.weapon_skins, skin_key) then
    local idx = #NetworkLookup.weapon_skins + 1
    rawset(NetworkLookup.weapon_skins, idx, skin_key)
    rawset(NetworkLookup.weapon_skins, skin_key, idx)
end
```

### 3. `mod_data.CustomData.skin` and `mod_data.skin`
Set on the item entry so the backend resolves to the custom skin.

### `skin_combination_table`

Do **NOT** clear `skin_combination_table` on the cloned entry. The cosmetics/illusion menu reads this field to determine available skins. Keeping the base weapon's table means vanilla illusions for that weapon type appear in the cosmetics gear menu.

## Icon Systems

Two completely separate atlas systems — using the wrong type in either field crashes the GUI renderer:

| Field | Atlas Prefix | Example | Used For |
|-------|-------------|---------|----------|
| `inventory_icon` | `icon_wpn_*` | `icon_wpn_dw_shield_01_axe` | Menu/inventory UI |
| `hud_icon` | `weapon_generic_icon_*` | `weapon_generic_icon_axe_and_sheild` | In-game HUD |

## Properties and Traits

### Property format
Properties in `mod_data.properties` and `CustomData.properties` use `1` for max roll (not decimal fractions). The game's `buff_tweak_data` applies the actual percentage.

```lua
-- Definition:
properties = { block_cost = 1, power_vs_skaven = 1 },

-- Serialized in CustomData:
properties = '{"block_cost":1,"power_vs_skaven":1}',
```

### Valid melee properties
`attack_speed`, `crit_chance`, `crit_boost`, `stamina`, `block_cost`, `push_block_arc`, `power_vs_skaven`, `power_vs_chaos`, `power_vs_unarmoured`, `power_vs_armoured`, `power_vs_large`, `power_vs_frenzy`

### Valid melee traits
| Internal Name | Display Name |
|--------------|-------------|
| `melee_attack_speed_on_crit` | Swift Slaying |
| `melee_timed_block_cost` | Parry |
| `melee_counter_push_power` | Opportunist |
| `melee_increase_damage_on_block` | Off Balance |
| `melee_reduce_cooldown_on_crit` | Resourceful Combatant |
| `melee_shield_on_assist` | Heroic Intervention |

### Traits in CustomData
Traits are a JSON array of strings, with a parallel Lua table:

```lua
-- CustomData (JSON string):
traits = '["melee_counter_push_power"]',

-- mod_data (Lua table):
traits = { "melee_counter_push_power" },
```

## Registration Timing

**Backend is nil at mod init.** Calling `add_mod_items_to_local_backend` during mod script initialization crashes with `attempt to index local 'backend' (a nil value)`.

The correct pattern: hook `StateInGameRunning.on_enter` (string-form, lazy resolution). The backend is guaranteed ready when entering the keep or a mission.

```lua
mod:hook_safe("StateInGameRunning", "on_enter", function()
    _auto_register_all()
end)
```

Use a flag (`_auto_registered`) to prevent duplicate registration on subsequent level loads.

## Adding Cross-Character Illusions

Cross-character illusions let one character use another character's weapon cosmetics in the illusion/cosmetics menu. Unlike variant weapons (new items via MoreItemsLibrary), illusions are purely visual — they add selectable skins to an existing weapon.

### How it works

Each illusion entry clones all visual data from a vanilla skin at runtime via `WeaponSkins.skins[source_skin]`. This guarantees the display name, description, rarity color, inventory icon, HUD icon, glow material, and model path all match the original exactly — no manual copying.

The registration function (`_register_custom_illusions`) injects each illusion into four places:
1. `ItemMasterList[skin_key]` — as a `weapon_skin` item, with `matching_item_key` pointing to the target weapon
2. `WeaponSkins.skins[skin_key]` — visual data (unit paths, icons, rarity, glow)
3. `WeaponSkins.skin_combinations[table_name]` — adds to the correct rarity tier so it appears in the cosmetics browser
4. `NetworkLookup.weapon_skins` — network serialization (uses `rawget`/`rawset`)

A `hook_safe` on `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` marks all custom skins as unlocked.

### Step 1: Find the vanilla skin keys

Look up the source skins in `Vermintide-2-Source-Code/scripts/settings/equipment/weapon_skins.lua` (base game) and the DLC files under `scripts/settings/dlcs/*/weapon_skins_*.lua`. Each skin entry has a `name` and `data` block with `rarity`, `right_hand_unit`, `inventory_icon`, `hud_icon`, `material_settings_name` (for glows), etc.

Also check `skin_combinations` at the bottom of those files to see which rarity tiers the vanilla skin appears in. The tiers are: `common`, `rare`, `exotic`, `unique`, `bogenhafen`, `magic`.

### Step 2: Identify all skin variants

A weapon typically has multiple tiers of the same model family. For greatswords:
- **Base skins**: `_skin_01` through `_skin_05`/`_06` (plentiful, common, rare, exotic)
- **Runed/glowing**: `_skin_XX_runed_01` (unique — red illusion tier)
- **Bogenhafen**: `_skin_XX_runed_02` (unique with `material_settings_name = "purple_glow"`)
- **Geheimnisnacht**: `_skin_XX_runed_03` (unique with `material_settings_name = "golden_glow"`)
- **Weavebound**: `_skin_XX_magic_01` (magic — yellow/purple weave icon)
- **Versus**: `_skin_XX_magic_02` (unique with `material_settings_name = "versus"`)
- **Chaos Wastes**: `_skin_XX_runed_06` (unique with `material_settings_name = "lileath"`)

Include all of these to give a complete cosmetic roster.

### Step 3: Add entries to `_custom_illusions`

Each entry only needs three fields plus career list — everything else is cloned from the source skin:

```lua
{ skin_key = "cwv_es_2h_sword_wh_04_magic_01", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_04_magic_01", can_wield = _es_careers },
```

- `skin_key`: unique key, prefixed with `cwv_`. Convention: `cwv_<target_weapon>_<source_char>_<variant>`
- `matching_weapon`: the target weapon's `ItemMasterList` key (what weapon gets the illusion)
- `source_skin`: the vanilla `WeaponSkins.skins` key to clone from
- `can_wield`: career list for the target character

### Step 4: Build and deploy

Same as variant weapons — VMB build, copy to Workshop folder, full game restart (no hot-reload).

### What NOT to do

- Don't manually specify `rarity`, `inventory_icon`, `hud_icon`, `display_name`, or `material_settings_name` — clone from `source_skin`
- Don't add skins to all rarity tiers — the registration function adds to the matching tier only
- Don't add localization entries — vanilla loc keys are reused from the source skin

### Animation considerations

Cross-character illusions only swap the 3D model. If both weapons share the same `template` (e.g., `two_handed_swords_template_1` for all greatswords), no animation work is needed. If the templates differ, you'll need animation remapping in weapon_tweaker.

## Custom Templates (Stat Modifications)

To create a weapon variant with different combat stats (damage, speed, cleave, stagger), clone the base weapon template and modify the relevant data tables at mod init.

### Template cloning approach

1. Deep-clone `Weapons[base_template]` into a new template name
2. Iterate all actions and sub-actions:
   - **Speed**: Multiply `anim_time_scale` on each sub-action (higher = faster animation)
   - **Damage profiles**: Clone each referenced `DamageProfileTemplates` entry with a prefix
3. For each cloned damage profile, clone and modify `PowerLevelTemplates` entries:
   - **Damage**: `power_distribution.attack` in `default_target`, `targets`, and `critical_strike`
   - **Stagger**: `power_distribution.impact` in the same tables
   - **Cleave**: `cleave_distribution.attack` and `.impact`
4. Register: `Weapons[new_template_name] = cloned_template`
5. Set `template` field in the variant definition — `_build_entry` applies it to the cloned `ItemMasterList` entry

### Key globals

| Table | Contains | Available at mod init? |
|-------|----------|----------------------|
| `Weapons` | Template name → template data | Yes |
| `DamageProfileTemplates` | Profile name → string keys into PowerLevelTemplates | Yes |
| `PowerLevelTemplates` | Key → actual numeric data (power_distribution, cleave_distribution, etc.) | Yes |

### DamageProfileTemplates structure

```lua
DamageProfileTemplates["heavy_slashing_axe_linesman"] = {
    armor_modifier = "armor_modifier_axe_linesman_H",     -- don't modify
    charge_value = "heavy_attack",                         -- don't modify
    cleave_distribution = "cleave_distribution_axe_linesman_H",  -- clone + modify
    critical_strike = "critical_strike_axe_linesman_H",    -- clone + modify
    default_target = "default_target_axe_linesman_H",      -- clone + modify
    targets = "targets_axe_linesman_H",                    -- clone + modify
}
```

Each string key resolves into `PowerLevelTemplates[key]` which has the actual values (`power_distribution.attack`, `power_distribution.impact`, etc.).

## Model Scaling

Variant definitions support `right_hand_scale = {x, y, z}` and `left_hand_scale = {x, y, z}`. These apply `Unit.set_local_scale` across all three rendering paths:

1. **In-game**: Hook `GearUtils.create_equipment` → scale `result.right_unit_1p`, `.right_unit_3p`, etc.
2. **Inventory preview**: Hook `HeroPreviewer._spawn_item` / `MenuWorldPreviewer._spawn_item` → scale `self._equipment_units[slot].right` / `.left`
3. **Illusion browser**: Hook `LootItemUnitPreviewer.spawn_units` → scale `self._spawned_units`

Cosmetics_tweaker has its own `_weapon_scale_overrides` system using the same hook points. Both mods' hooks stack via VMF — no conflicts as long as they target different item keys.

### Axis reference (Stingray/VT2)

| Axis | Effect |
|------|--------|
| X | Width/thickness (0.65 = thin bret longsword) |
| Y | Depth (rarely modified) |
| Z | Length (blade length along the weapon) |

## Reference: Base Weapon Keys

Use `ItemMasterList` keys (not `item_type`):
- `dr_shield_axe` (not `dr_1h_axe_shield`) — Bardin's axe and shield
- `dr_shield_hammer` — Bardin's hammer and shield
- `es_2h_sword` — Kruber's greatsword
- `wh_2h_sword` — Saltzpyre's greatsword
- `es_bastard_sword` — Kruber's Bretonnian Longsword (DLC: lake, template: bastard_sword_template)
- `wh_1h_axe` — Saltzpyre's one-handed axe

Full catalog: see `ITEM_LIST.md` in the repo root.
