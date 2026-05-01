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

## Multiplayer Compatibility Matrix

| Scenario | Visual Result |
|----------|--------------|
| All players have character_weapon_variants | Everyone sees correct models — real items sync via network |
| Host has character_weapon_variants, client doesn't | Client sees missing/unknown item — **mod required for all players** |
| Player A has cosmetics_tweaker, Player B doesn't | Offhand swaps are client-local only (player A sees their choice, player B sees vanilla) |
| Player A has weapon_tweaker, Player B doesn't | Cross-career weapons visible to both (items exist in backend), but animations may look wrong to player B |

---

## Open Questions

1. **Crafting menu ownership** — does the crafting UI live in character_weapon_variants, cosmetics_tweaker, or a shared UI mod? Simplest: in character_weapon_variants itself.
2. **Icon pipeline** — custom icons per new weapon. Format, resolution, and atlas injection method TBD (see cosmetics_tweaker TODO "Custom illusion icons").
3. **Animation ownership** — if a new weapon needs animation remaps, does character_weapon_variants ship them or delegate to weapon_tweaker? Cleaner if the new mod is self-contained, but duplicates weapon_tweaker's remap infrastructure.
4. **Scope of new weapons** — curated case-by-case. Need to enumerate which cross-character combos are worth building as real items vs. leaving as raw weapon_tweaker unlocks.
5. **Cosmetic curation approach** — lore-friendly by default, hand-picked per character. Only models and illusions matching the current character's aesthetic are shown.
