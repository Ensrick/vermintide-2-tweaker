# Character Weapon Variants — Recipes

The procedural how-to for adding a new variant. Read this first.

This file teaches you what to write and where to put it. The "why"
lives in `DEVELOPMENT.md` (rarity system, skin system, scale system,
template-clone architecture, base-weapon catalog). Animation work for
cross-character variants lives in `ANIMATION_FIX_PLAYBOOK.md` — every
recipe below points there when relevant.

If you're touching dual-wield, also read
`J_LEFTWEAPONATTACH_INVESTIGATION.md` once. It's the post-mortem for a
~20-version saga that produced the `_force_display_unit` rule.

---

## Decision tree — what are you making?

```
START
 │
 ├── A. NEW INVENTORY ITEM (gives the player a new weapon to equip)
 │    │
 │    ├── 1H melee, no shield, no off-hand .................... A1
 │    ├── 2H melee ............................................. A2
 │    ├── Has a shield in the off-hand ......................... A3
 │    ├── Identical-mesh dual-wield (same model both hands) .... A4
 │    ├── Mixed-mesh dual-wield (different models per hand) .... A5
 │    ├── Ranged ammo / thrown projectile ...................... A6
 │    └── Illusion-only (don't give the player an item, just
 │         expose the look as a cosmetic on existing items) .... A7
 │
 ├── B. NO NEW ITEM, just expand `can_wield` so a different
 │    character can equip an existing vanilla weapon ........... B1
 │
 ├── C. NEW COSMETIC SKIN — clone a vanilla skin and surface it
 │    as an illusion option in some other weapon's picker ...... C1
 │
 └── D. ADVANCED / EXPERIMENTAL
      └── 1P mesh ≠ 3P mesh (different look in held vs body view)
                        ........................................ D1
```

### Add-ons that compose with any A/B recipe

| Add-on | When to use | Section |
|---|---|---|
| **Stat modifier** | Damage / speed / cleave / stagger different from base | `Stat-modifier add-on` |
| **Damage-type swap** | Removing fire DoT, AoE, or any "wrong-element" effect | `Damage-type swap add-on` |
| **Inverse-hand** | Mirror the base weapon's left/right damage profiles | `Inverse-hand add-on` |
| **Disable a special action** | Remove a weapon's special ability (pistol shot, auto-catch reload, etc.) | `Disable a weapon special action add-on` |
| **Cross-pool cosmetics** | Curated illusions sourced from a DIFFERENT weapon's skin pool | `Cosmetic harvesting from a different weapon's skin pool` |
| **Per-perspective scale** | 1P held view needs different scale than 3P body | `Per-perspective scale` |
| **Animation 3P fix** | Cross-character moveset, body T-poses or wrong clip | See `ANIMATION_FIX_PLAYBOOK.md` |

---

## Universal preflight (every recipe assumes you've done this)

**Names lie. Always verify against `Vermintide-2-Source-Code` before writing
defs.** Two real failure modes I (and prior agents) keep hitting:

- A weapon called `bw_1h_mace` may be display-2H (the in-game weapon
  reads as two-handed even though its template name says "one-handed").
  The IML entry's `template` and `slot_type` are the ground truth.
- A `damage_profile` called `medium_blunt_smiter_heavy` can still resolve
  to a `_burn_*` `PowerLevelTemplates` entry in `damage_profile_templates.lua`.
  The profile name doesn't tell you what fields its `default_target` /
  `targets` / `critical_strike` chain to.

Use the verification commands below for every preflight item — don't trust
the IML key, the template name, or `ITEM_LIST.md` alone.

### Preflight checklist

- [ ] **Find and verify the base weapon's `ItemMasterList` entry.**
      Source dump path: `C:/Users/danjo/source/repos/Vermintide-2-Source-Code/scripts/settings/equipment/`.
      The exported entry is in `item_master_list_exported.lua` (most weapons)
      or one of the DLC files (`item_master_list_anvil.lua`, `_belakor.lua`,
      `_lake.lua`, `_morris.lua`, etc.).
      ```
      Grep pattern: ItemMasterList\.<base_key>\s*=
      ```
      Read the entry. Note: `template`, `item_type`, `slot_type`, `right_hand_unit`,
      `can_wield`, `skin_combination_table`. These are the ground truth.
      `../ITEM_LIST.md` is a list of keys but doesn't carry these fields —
      always cross-reference.
- [ ] **Find the source weapon template file.** From the IML entry, the
      `template` field gives you the template name. Find the file:
      `Vermintide-2-Source-Code/scripts/settings/equipment/weapon_templates/<name>.lua`
      (file naming is approximate — `2h_hammers.lua` → `two_handed_hammers_template_1`).
      Read `wield_anim`, `state_machine`, every `anim_event = "..."` (those
      are your closed vocabulary if this is the SOURCE template), and every
      `damage_profile = "..."` / `hit_effect = "..."` / `impact_sound_event = "..."`.
- [ ] **Walk the damage_profile chain for fire/AoE/DoT references.** For
      every `damage_profile` value the source template uses, grep for it
      in `damage_profile_templates.lua` (and the DLC variants — `_morris.lua`,
      `_woods.lua`, etc.). Look for `_burn_`, `_burning_`, `dot_template_name`,
      `slam_burn_aoe`, `damage_type = "burn"` in the resolved chain
      (`default_target`, `targets`, `critical_strike`, `cleave_distribution`).
      Wizard / priest / flame templates frequently route through `_burn_*`
      `PowerLevelTemplates` entries even when the profile NAME is
      `medium_blunt_*`. If the chain has burn, you need the
      Damage-type swap add-on.
- [ ] **Confirm unit paths.** From the IML entry's `right_hand_unit` (and
      `left_hand_unit` if shield/dual). For curated illusions, also harvest
      from `WeaponSkins.skins[<base>_skin_01]` entries (in `weapon_skins.lua`
      or DLC variants). Unit assets live in DLC packages — the mod strips
      `required_dlc` on cwv entries, but the unit still has to load (see
      `DEVELOPMENT.md` "required_dlc clearing").
- [ ] **Pick `item_key`.** Convention: `cwv_<character_prefix>_<short_name>`.
      Character prefixes: `es_` (Empire / Kruber), `wh_` (Witch Hunter /
      Saltzpyre), `dr_` (Dwarf / Bardin), `we_` (Wood Elf / Kerillian),
      `bw_` (Bright Wizard / Sienna). Use the **wielder's** prefix, not
      the source weapon's.
- [ ] **Pick rarity.** See `DEVELOPMENT.md` "Rarity". Common cases:
      `default` for a forge-friendly blacksmith template, `exotic` for
      a curated tuned weapon, `unique` for a "veteran" version
      with traits and properties pre-rolled.
- [ ] **Decide `item_type`.** Set it to `cwv_<short_name>` if you want a
      curated cosmetic picker (the variant gets its own
      `skin_combination_table` so vanilla skins don't bleed in). Leave it
      unset if reusing the base weapon's vanilla skin pool is acceptable.
- [ ] **Pick `careers`.** Use the helpers at the top of
      `character_weapon_variants.lua`:
      `_es_all_careers`, `_wh_all_careers`, `_bw_all_careers`. For partial
      sets (e.g. excluding Grail Knight) write the list inline.
- [ ] **Plan icon work.** A variant is **NOT complete** until it has its
      own `inventory_icon` and `hud_icon`. Until custom icons are
      authored, point at the source weapon's vanilla icons as
      placeholders and add a TODO note. See "Icons — completion gate"
      below.
- [ ] **Verify packages for any cross-character unit reference.** When
      the variant references unit paths from a DIFFERENT character's
      kit than the `base_weapon` — held meshes, illusion source meshes,
      pickup units, projectile units, OR per-perspective 3P override
      units — that unit might not be in the loaded inventory package
      for your variant's equip. Vanilla queues packages off the
      variant's `right_hand_unit` / `left_hand_unit` only. The
      Tuskgor Javelin (CHANGELOG v0.1.118) and brace_repeater (open
      issue) both hit this. Two paths: add the unit's package as a
      static dependency in
      `resource_packages/character_weapon_variants/character_weapon_variants.package`,
      or force-load via `Managers.package` at runtime. Spot-check by
      equipping the variant in-game and looking for `World.spawn_unit`
      crashes.

---

## Universal common steps (every "new item" recipe ends with these)

After writing the def, you almost always also need:

1. **`_variant_definitions`** (line ~69) — the def itself.
2. **(if `item_type` set)** add to **`_seed_targets`** (line ~2594) so a
   curated `skin_combination_table` is created for it.
3. **(if `item_type` set)** add to **`_item_type_to_skin_table`** (line ~3273)
   inside `_build_entry` so the cloned IML entry's `skin_combination_table`
   field points at your curated table.
4. **(dual-wield only)** add to **`_force_display_unit`** (line ~2451) with
   the correct rig for the weapon family.
5. **Bump `MOD_VERSION`** at line 3. Required every build (see
   `feedback_version_bump.md`).
6. **Add a `CHANGELOG.md` entry** under a new dated heading.
7. **Build and deploy** — see `DEVELOPMENT.md` "Step 3" or `CLAUDE.md`
   "Build Commands".
8. **Full game restart.** No hot-reload — see `CLAUDE.md` "Hot-reload crashes".
9. **Walk the verification matrix** at the bottom of this file.

Localization is automatic: the Localize hook at line ~2303 maps
`<item_key>_name` → `display_name`, `<item_key>_description` → `description`,
`<item_key>_skin_name` → `skin_display_name`.

---

# Recipes

Each recipe references a real shipped variant as canon. Open that variant
in `character_weapon_variants.lua` to see the live def alongside the
recipe.

---

## Recipe A1 — Single 1H melee, no shield

**Canon:** `cwv_es_warpriest_hammer` (Skullsplitter on Kruber, line ~330)
or `cwv_es_cudgel` (Kruber 1H mace stat-clone, line ~413).

**Pattern:** clone an existing 1H weapon's IML entry, swap
`right_hand_unit` to your chosen mesh, optionally set `template` to
either an existing template (preserves the moveset) or a stat-modified
clone (see Stat-modifier add-on).

**Def template:**

```lua
{
    item_key        = "cwv_<char>_<name>",
    base_weapon     = "wh_1h_hammer",                 -- vanilla 1H hammer (priest moveset)
    display_name    = "Warrior-Priest Hammer",
    description     = "<lore text>",
    character       = "empire_soldier",               -- sp_profiles display_name
    careers         = _es_all_careers,
    right_hand_unit = "units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01",
    inventory_icon  = "icon_wpn_wh_1h_hammer_01",
    hud_icon        = "weapon_generic_icon_hammer1h",
    skin_display_name = "Warrior-Priest Hammer",
    rarity          = "exotic",
    template        = "one_handed_hammer_priest_template",  -- vanilla template
    traits          = { "melee_attack_speed_on_crit" },
    properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
    item_type       = "cwv_<short_name>",             -- only if you want a curated picker
}
```

**Common steps:** all 9 (see Universal common steps).

**Animation considerations:** if the base weapon's moveset was authored
on a different character's skeleton, 3P body events may be missing on
the new wielder. Check with `wt animlog` after equip. If anything
T-poses or stub-plays, see `ANIMATION_FIX_PLAYBOOK.md`.

---

## Recipe A2 — Two-handed melee

**Canon:** `cwv_es_longsword` (Recruit Longsword, default-rarity blacksmith
template, line ~135) and `cwv_es_longsword_blackguard` (Black Guard Blade,
unique, line ~158).

**Pattern:** same as A1 but the base weapon is two-handed. The two
shipped 2H families demonstrate two patterns:

- **Curated unique** (Black Guard Blade): `rarity = "unique"`, traits
  pre-applied, ships with a fixed illusion baked in.
- **Default-rarity blacksmith template** (Recruit Longsword): `rarity =
  "default"`, `power_level = 5`. Forge will let the player re-roll
  properties, salvage, and apply illusions to it. **Read DEVELOPMENT.md
  "Blacksmith Template Pattern" before writing one of these** — the
  rarity/skin gating is non-obvious.

**Def template (curated unique):**

```lua
{
    item_key        = "cwv_es_longsword_blackguard",
    base_weapon     = "es_bastard_sword",
    display_name    = "Black Guard Blade",
    description     = "<lore text>",
    character       = "empire_soldier",
    careers         = _es_all_careers,
    right_hand_unit = "units/weapons/player/wpn_empire_2h_sword_03_t2/wpn_2h_sword_03_t2",
    inventory_icon  = "icon_wpn_empire_2h_sword_03_t2",
    hud_icon        = "weapon_generic_icon_sword",
    skin_display_name = "Black Guard Blade",
    rarity          = "unique",
    template        = "imperial_longsword_template",  -- stat-clone, see Stat-modifier add-on
    item_type       = "cwv_imperial_longsword",       -- shared with sibling variants
    -- Scale/grip cascades from `_type_transforms.cwv_imperial_longsword`.
}
```

**Def template (default-rarity blacksmith):**

```lua
{
    item_key        = "cwv_es_longsword",
    base_weapon     = "es_bastard_sword",
    display_name    = "Recruit Longsword",
    description     = "<lore text>",
    character       = "empire_soldier",
    careers         = _es_all_careers,
    right_hand_unit = "units/weapons/player/wpn_empire_2h_sword_04_t1/wpn_2h_sword_04_t1",
    inventory_icon  = "icon_wpn_empire_2h_sword_04_t1",
    hud_icon        = "weapon_generic_icon_sword",
    skin_display_name = "Recruit Longsword",
    rarity          = "default",
    power_level     = 5,                              -- low; the forge rolls properties
    template        = "imperial_longsword_template",
    item_type       = "cwv_imperial_longsword",
    -- NO `traits` / `properties` — the forge rolls them.
}
```

**Critical for default-rarity:** `_build_entry` automatically skips the
`mod_data.CustomData.skin = "<item_key>_skin"` pre-apply when
`def.rarity == "default"`. If you accidentally set a skin, the forge
locks the item. The `BackendUtils.get_item_units` cwv-override hook
(line ~3765) ensures `entry.right_hand_unit` still wins at render time
when no skin is applied.

---

## Recipe A3 — Shield-bearing weapon

**Canon:** `cwv_es_axe_shield` (Axe and Shield, default, line ~71) and
`cwv_es_axe_shield_veteran` (Imperial Axe and Shield, unique, line ~86).

**Pattern:** clone the base shield-weapon's IML entry, set BOTH
`right_hand_unit` (the weapon) and `left_hand_unit` (the shield).

**Def template (unique tier):**

```lua
{
    item_key        = "cwv_es_axe_shield_veteran",
    base_weapon     = "dr_shield_axe",                -- Bardin's axe+shield (NOT dr_1h_axe_shield)
    display_name    = "Imperial Axe and Shield",
    description     = "<lore text>",
    character       = "empire_soldier",
    careers         = { "es_mercenary", "es_huntsman", "es_knight" },
    right_hand_unit = "units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2_magic_01",
    left_hand_unit  = "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic",
    inventory_icon  = "icon_wpn_dw_shield_01_axe",
    hud_icon        = "weapon_generic_icon_axe_and_sheild",
    skin_display_name = "Imperial Axe and Shield",
    rarity          = "unique",
    traits          = { "melee_counter_push_power" },
    properties      = { block_cost = 1, power_vs_skaven = 1 },
}
```

**Why no `_force_display_unit` here?** Shield rigs only attach the
weapon to `j_rightweaponattach` and the shield to `j_leftshieldattach`
(or similar shield-specific node). The vanilla shield weapon's
`display_unit` already handles both correctly. Dual-wield is the case
that needs `_force_display_unit` — see A4.

**Animation:** shield wield-pose can read wrong on a foreign body. See
`cwv_we_sword_shield` (line ~102) for an example that also writes a
`_create_elven_sword_shield_template` clone with a `wield_anim_3p =
"to_1h_spear_shield"` redirect for elf careers, plus the BASE template
patch the inventory previewer needs. Pattern documented in
`ANIMATION_FIX_PLAYBOOK.md` and DEVELOPMENT.md "Animation: System B".

---

## Recipe A4 — Identical-mesh dual-wield

**Canon:** `cwv_es_dual_swords` (line ~353), `cwv_es_dual_axes` (line ~463),
`cwv_es_dual_maces` (line ~508).

**Pattern:** same mesh in both hands. Requires a dual-attach `display_unit`
or the cosmetic picker crashes with `[Script Error]: j_leftweaponattach`.

**Def template:**

```lua
{
    item_key        = "cwv_es_dual_swords",
    base_weapon     = "we_dual_wield_swords",
    display_name    = "Imperial Dual Swords",
    description     = "<lore text>",
    character       = "empire_soldier",
    careers         = _es_all_careers,
    right_hand_unit = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",
    left_hand_unit  = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",  -- IDENTICAL
    inventory_icon  = "icon_wpn_emp_sword_02_t1",
    hud_icon        = "weapon_generic_icon_dual_elf_sword",
    skin_display_name = "Imperial Dual Swords",
    rarity          = "exotic",
    template        = "imperial_dual_swords_template",  -- stat-clone, see Stat-modifier add-on
    traits          = { "melee_attack_speed_on_crit" },
    properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
    item_type       = "cwv_es_dual_swords",             -- REQUIRED for dual-wield
}
```

**Mandatory extra registrations** (in addition to all 9 universal common steps):

1. **`_force_display_unit`** at line ~2451 — pick the rig matching your
   weapon family:

   | Mesh family | Rig | Vanilla precedent |
   |---|---|---|
   | Swords | `units/weapons/weapon_display/display_dual_weapons` | `we_dual_sword_skin_01` (`weapon_skins.lua:5750`) |
   | Axes | `units/weapons/weapon_display/display_dual_axes` | `dw_dual_axe_skin_01` (`weapon_skins.lua:2364`) |
   | Hammers/maces | `units/weapons/weapon_display/display_dual_hammers` | `weapon_skins_bless.lua:395` |
   | Daggers | `units/weapons/weapon_display/display_dual_daggers` | `we_dual_wield_daggers` skins |

2. **`_seed_targets`** entry: `cwv_<short> = "cwv_<short>_skins"`.
3. **`_item_type_to_skin_table`** entry: `cwv_<short> = "cwv_<short>_skins"`.

**Why `display_dual_*` matters** — single-hand rigs only author
`j_rightweaponattach`; the previewer crashes when it tries to attach
the left unit. The constraint isn't visible at registration time, only
at the runtime attach call. See `J_LEFTWEAPONATTACH_INVESTIGATION.md`
for the full ~20-version post-mortem.

**Optional but common: dual-wield illusion harvest.** If you want to
expose every vanilla skin from a related 1H weapon family as an
illusion on this dual variant (e.g. all `wh_1h_axe` skins on
`cwv_es_dual_axes`), write a dedicated registrar like
`_register_saltzpyre_1h_axe_dual_illusions` (line ~2974). Its body is:

- Scan `ItemMasterList` for entries where `item_type == "weapon_skin"`
  and `matching_item_key == "<source_1h_key>"`.
- For each match, build a clone with `right_hand_unit = source.right_hand_unit`,
  `left_hand_unit = source.right_hand_unit` (mirror), and force
  `display_unit = "units/weapons/weapon_display/display_dual_<family>"`.
- Set `matching_item_key = "<your_cwv_item_key>"` on the clone (NOT the
  base — this routes it into your curated picker).
- Append to `WeaponSkins.skin_combinations.<your_skin_table>` and
  inject into `NetworkLookup.weapon_skins` + `NetworkLookup.item_names`.
- Mark `_custom_skin_keys[new_key] = true` so the unlocked-skins hook
  picks it up.

The three shipped registrars (`_register_kruber_1h_sword_dual_illusions`,
`_register_saltzpyre_1h_axe_dual_illusions`, `_register_es_1h_mace_dual_illusions`)
are templates; copy whichever is closest.

**Animation:** dual-wield routes via `_cross_access_template_wield_3p`
(if cross-character) or via the variant's own template clone's
`wield_anim_3p` and `wield_anim_career_3p`. See
`imperial_dual_swords_template` (line ~1141) for the canonical example.
Cross-character per-action remaps live in `_cross_access_action_remap`
(line ~759). For specifics: `ANIMATION_FIX_PLAYBOOK.md`.

---

## Recipe A5 — Mixed-mesh dual-wield (inverse hand layout)

**Canon:** `cwv_es_sword_and_mace` (line ~385) — the inverse of vanilla
`es_dual_wield_hammer_sword`. Vanilla puts mace=right, sword=left;
the variant puts sword=right, mace=left.

**Pattern:** same as A4 but the meshes differ between hands AND the
damage profiles, hit effects, and impact sounds need to swap to follow
the new hand layout. Otherwise the visible mace plays slashing damage
or vice-versa, and audio doesn't match the model.

**Def template:**

```lua
{
    item_key        = "cwv_es_sword_and_mace",
    base_weapon     = "es_dual_wield_hammer_sword",
    display_name    = "Sword and Mace",
    description     = "<lore text>",
    character       = "empire_soldier",
    careers         = _es_all_careers,
    right_hand_unit = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",  -- sword now in right
    left_hand_unit  = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",   -- mace in left
    inventory_icon  = "icon_es_dual_wield_hammer_sword_01",
    hud_icon        = "weapon_generic_icon_falken",
    skin_display_name = "Sword and Mace",
    rarity          = "exotic",
    template        = "sword_and_mace_template",     -- inverse-hand clone, see Inverse-hand add-on
    traits          = { "melee_attack_speed_on_crit" },
    properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
    item_type       = "cwv_es_sword_and_mace",       -- needed: vanilla skins would invert your layout
}
```

**Why `item_type` is critical here:** without it, the variant inherits
`es_dual_wield_hammer_sword`'s `skin_combination_table`. Vanilla skins
in that table set `right=mace + left=sword` — the OPPOSITE of your
intent. Applying any vanilla illusion would flip the hands and erase
the variant's identity. Forcing your own combo table prevents this.

**Mandatory extras:** all of A4's steps (`_force_display_unit`,
`_seed_targets`, `_item_type_to_skin_table`) PLUS write a
`sword_and_mace_template` per-action damage swap. See Inverse-hand
add-on below.

---

## Recipe A6 — Ranged ammo / thrown projectile

**Canon:** `cwv_es_javelin` (line ~199) and `cwv_wh_javelin` (line ~234) —
"Tuskgor Javelin", boar-spear visual on the elf javelin moveset.

This is the heaviest recipe in the file. Ranged weapons touch ten
subsystems that single-hand melee ignores: `ammo_unit`, `ammo_unit_3p`,
`projectile_units_template`, `pickup_template_name`,
`link_pickup_template_name`, custom `Pickups.ammo` registration,
`AllPickups`, `NetworkLookup.husks`, `NetworkLookup.pickup_names`,
and a `PlayerProjectileUnitExtension.init` hook to swap to your
cloned template.

**Def template:**

```lua
{
    item_key        = "cwv_es_javelin",
    base_weapon     = "we_javelin",
    display_name    = "Tuskgor Javelin",
    description     = "<lore text>",
    character       = "empire_soldier",
    careers         = _es_all_careers,
    -- Held meshes: javelin lives on left_hand_unit; right is invisible.
    right_hand_unit = "units/weapons/player/wpn_invisible_weapon",
    left_hand_unit  = "units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01",
    inventory_icon  = "icon_emp_boar_spear_01",
    hud_icon        = "weapon_generic_icon_falken",
    skin_display_name = "Tuskgor Javelin",
    rarity          = "exotic",
    template        = "tuskgor_javelin_template",     -- stat clone, see Stat-modifier add-on
    traits          = { "ranged_replenish_ammo_headshot" },
    properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
    -- Projectile + pickup overrides — must be registered separately (below).
    projectile_units_template = "cwv_tuskgor_javelin",
    pickup_template_name      = "cwv_tuskgor_javelin_pickup",
    link_pickup_template_name = "cwv_tuskgor_javelin_link_pickup",
    -- Optional: shrink the held mesh in 3P + previews but keep 1P at native
    -- so the throw anim doesn't clip the camera.
    left_hand_scale = { 0.80, 0.80, 0.80 },
    scale_3p_only   = true,
}
```

**Skin-mirror requirement (critical):** ammo weapons MUST have
`ammo_unit` (and ideally `ammo_unit_3p`, `projectile_units_template`,
`pickup_template_name`, `link_pickup_template_name`) mirrored onto
the skin entry. `BackendUtils.get_item_units` overwrites these from
the skin template unconditionally when a skin applies — an absent
field nukes the inherited base value, and the previewer concatenates
nil → crash. `_register_variant_skins` already handles this by
falling back to `def.<field>` or `base.<field>`, but you must SET the
fields on the def for that fallback to find them. See lines 2400–2486.

**Custom asset registration** — write a `_register_<shortname>_assets`
function modeled after `_register_tuskgor_javelin_assets` (line ~1546).
It must:

1. **`ProjectileUnits.<key>`** — controls in-flight + stuck mesh.
2. **`NetworkLookup.projectile_units`** rawset injection.
3. **`NetworkLookup.husks`** rawset injection — required by the
   non-link pickup spawn path. Without this the first throw crashes
   with `Table husks does not contain key: <unit>`.
4. **`Pickups.ammo.<pickup_key>`** + **`Pickups.ammo.<link_pickup_key>`** —
   modeled after `anvil_pickup_settings.lua`'s throwing axe pickups.
   Includes `can_interact_func` / `outline_available_func` /
   `on_pick_up_func` closures that gate the pickup to wielders of your
   weapon (via `inv:has_ammo_consuming_weapon_equipped("<ammo_type>")`).
5. **`AllPickups`** mirror — pickup_system reads here.
6. **`NetworkLookup.pickup_names`** rawset injection.

**Critical: `unit_template_name`.** Use `"limited_owned_pickup_unit"`
(NOT `"limited_owned_pickup_projectile_unit"`). The `_projectile_unit`
template requires the unit to have a physics actor named `"throw"`;
held-mesh `_3p` units typically don't have it and crash
`Actor.create_actor`. The non-projectile template spawns statically at
the impact position without bouncing — acceptable trade.

**Stat-clone hook:** the projectile system reads the BASE template at
runtime, NOT your clone (per `feedback_cwv_projectile_template_lookup.md`).
Hook `PlayerProjectileUnitExtension.init` and swap `self._current_action`,
`self._impact_data`, `self.projectile_info`, and
`self._impact_damage_profile_id` onto your clone's `throw_charged`
sub-action. See lines 1788–1874 for the canonical pattern. Filter on
`extension_init_data.item_name == "<base_weapon>"` and match
`slot_data.skin` against `^cwv_.+_<shortname>_skin$` to scope to your
variants.

**Inline damage profile clone:** thrown projectiles use INLINE damage
profiles (`default_target.power_distribution_near.attack` is a literal
number), NOT the PowerLevelTemplates string-key indirection used by
melee weapons. `_clone_damage_profile` won't work — use
`_clone_inline_throw_profile` (line ~2003) for the throw and
`_clone_damage_profile` for the melee stab sub-actions.

**Throwing-axe-style stick + pickup:** vanilla javelins use
`link = true` + `wall_nail = true` + `flow_event_on_walls = "teleport_out"`
(the auto-recall). Replace with `link_pickup = true` +
`pickup_settings = { use_weapon_skin = true, link_hit_zones = {...} }`
on every `kind = "thrown_projectile"` sub-action's `impact_data`. See
`tuskgor_javelin_template` lines ~2183–2202.

**Auto-catch reload removal:** to convert a finite-stack thrown weapon,
override `template.actions.weapon_reload.default.condition_func` and
`chain_condition_func` to a `_always_false` closure (line ~2138). Plus
`ammo_data.block_ammo_pickup = false` and `unique_ammo_type = false`
so vanilla ammo crates refill the stack.

**Animation:** ranged weapons that don't share their wielder's native
3P body skeleton (e.g. elf javelin moveset on Kruber) need a 3P body
event remap (`_tj_anim_remap`, line ~2091) AND a per-career
`wield_anim_career_3p` mapping into a sub-graph the body has. Patch
both the clone AND the BASE template (per
`feedback_cwv_previewer_template_lookup.md`). Trade: shield-stance
sub-graphs are melee-only — `attack_throw` / `throw_charge` / `reload`
have no analogs and the body stands still during the throw window
(throw mechanics still work, just no visible body motion). See
lines ~2230–2256 and `ANIMATION_FIX_PLAYBOOK.md`.

---

## Recipe A7 — Skin-only variant (illusion-only)

**Canon:** `cwv_es_longsword_nordland` (Nordland Claymore, line ~258).

**Pattern:** the variant exists only to expose a look as a cosmetic
illusion on sibling variants. The player never sees it as a wieldable
inventory item.

**Def template:**

```lua
{
    item_key        = "cwv_es_longsword_nordland",
    base_weapon     = "es_bastard_sword",
    display_name    = "Nordland Claymore",
    description     = "<lore text>",
    character       = "empire_soldier",
    careers         = _es_all_careers,
    right_hand_unit = "units/weapons/player/wpn_greatsword/wpn_greatsword",
    inventory_icon  = "icon_wpn_greatsword",
    hud_icon        = "weapon_generic_icon_sword",
    skin_display_name = "Nordland Claymore",
    rarity          = "exotic",
    template        = "imperial_longsword_template",
    item_type       = "cwv_imperial_longsword",
    skin_only       = true,                           -- THIS LINE
}
```

**What `skin_only = true` does:** `_auto_register_all` skips the
inventory-item mirror (line ~3465) so the player never receives the
item. `_register_variant_skins` STILL runs for it (gated only by
`def.no_skin`, not `def.skin_only`), so the skin entry exists in
`WeaponSkins.skins[<item_key>_skin]` and `ItemMasterList[<item_key>_skin]`
and shows up in any sibling variant's curated picker (because the seed
loop includes every def of the matching `item_type`).

**Critical:** `_register_variant_skins` writes
`ItemMasterList[<skin_key>].matching_item_key = def.base_weapon`, NOT
`def.item_key`. Vanilla `_apply_skin_to_item` does
`ItemHelper.get_template_by_item_name(matching_item_key)` and crashes
when the key isn't in `ItemMasterList` with a real template. Since
skin-only variants aren't mirrored into IML, using `def.item_key` here
crashes (this was the v0.1.95 bug — GUID `ca46d7b2`).

---

## Recipe B1 — Cross-access (no new item)

**Canon:** `wh_dual_wield_axe_falchion` accessible to Kruber (line ~556),
`dr_dual_wield_axes` accessible to Kruber and Saltzpyre.

**Pattern:** the weapon already exists in the game. You just want
another character to equip it. No new IML entry, no skin, no auto-
registration, no `_seed_targets`. Just expand `can_wield`.

**Where to add:**

```lua
-- _cross_access_can_wield (line ~556)
local _cross_access_can_wield = {
    wh_dual_wield_axe_falchion = _es_all_careers,
    -- add: <vanilla_item_key> = <careers_to_add>,
}
```

**Often-needed companion patches:**

1. **3P wield routing.** A foreign career's body may not author the
   weapon's native wield SM. Route them into a sub-graph their body
   does have, via `_cross_access_template_wield_3p` (line ~601):

   ```lua
   <base_template_name> = {
       <foreign_career> = "to_<target_sm_in_foreign_body>",
       ...
   },
   ```

2. **Per-action 3P event remap.** When specific attacks read wrong
   on the foreign body. See `_cross_access_action_remap` (line ~759)
   and `ANIMATION_FIX_PLAYBOOK.md`. The closed-vocabulary rule applies
   absolutely here.

**No `item_type`, no skin entry, no `_force_display_unit`** — the
vanilla item already has all of those.

---

## Recipe C1 — Custom illusion (cosmetic clone)

**Canon:** every entry in `_custom_illusions` (line ~2631).

**Pattern:** clone a vanilla skin's visual data (display name,
inventory icon, HUD icon, glow material, model) and surface it as an
illusion option in some other weapon's cosmetic picker. No new
inventory item, no stats, no template.

**Entry template:**

```lua
{
    skin_key        = "cwv_<descriptive_unique_key>",
    matching_weapon = "<target_weapon_iml_key>",     -- which weapon's picker shows this
    source_skin     = "<vanilla_skin_key_in_WeaponSkins.skins>",
    can_wield       = _<char>_careers,
    -- Optional fields:
    target_combo    = "cwv_<short>_skins",            -- explicit picker, overrides matching_weapon's table
    right_hand_unit_override = "<unit>",              -- when source's hand layout doesn't match target's
    left_hand_unit_override  = "<unit>",
    right_hand_scale  = { x, y, z },                  -- if source mesh is too big/small for target slot
    right_hand_offset = { x, y, z },                  -- if grip needs adjustment
}
```

**`matching_weapon` vs `target_combo`** — these are independent.

- `matching_weapon` controls which weapon's `_apply_skin_to_item`
  template lookup resolves correctly. It must be a real IML key with a
  valid `template` field (the engine crashes otherwise — see
  v0.1.95 lesson).
- `target_combo` controls which `skin_combination_table` the skin
  appears in (i.e. which weapon's picker shows it). Defaults to
  `ItemMasterList[matching_weapon].skin_combination_table`. Override
  when you want the skin in a DIFFERENT picker than `matching_weapon`'s
  default — e.g. surfacing 2H sword skins as illusions on the Imperial
  Longsword's curated picker while keeping `matching_weapon =
  "es_bastard_sword"` so the template lookup resolves to
  `bastard_sword_template`.

**Hand-unit overrides** — use when the source skin's mesh layout
doesn't match the target slot. Examples:

- A greathammer (`source.right_hand_unit` only) being applied to a
  mace+shield target: set `left_hand_unit_override` to the target's
  default shield so the off-hand isn't empty.
- A 2H model in a 1H slot reading oversized: scale and offset.

**Mandatory side-effects** — `_register_custom_illusions` (line ~2716)
already handles all of these for entries in `_custom_illusions`:

- Inject into `ItemMasterList[skin_key]` as a `weapon_skin` entry.
- Inject into `WeaponSkins.skins[skin_key]` (visual data clone).
- Append to `WeaponSkins.skin_combinations[target_combo][rarity]`.
- Inject into `NetworkLookup.weapon_skins` (rawget/rawset — the table
  has an error-throwing `__index`).
- Inject into `NetworkLookup.item_names` (rawset).
- Mark in `_custom_skin_keys` for the unlocked-skins hook.

**Animation:** none. Custom illusions only swap the model. If both
weapons share the same `template`, no anim work is needed. If they
don't, you're not making an illusion — you're making a variant
(Recipe A1–A6).

---

## Recipe D1 — Per-perspective unit swap (1P ≠ 3P mesh) — EXPERIMENTAL

**Status: experimental. Default-OFF setting toggle. Crashes on equip
in some cases due to package-loading; see "Package loading
constraint" below.**

When the variant should look DIFFERENT in first-person (the player's
view) than in third-person (other players' / inventory previewer
view). E.g. brace of pistols 1P + repeating handgun 3P.

**Canon:** `cwv_es_brace_repeater` (line ~568) — Saltzpyre's brace of
pistols on Kruber, with a repeating handgun visible to other players
and in the 3P inventory preview.

### How vanilla derives 3P units

`gear_utils.lua:189` appends `_3p` to `right_hand_unit` to derive the
3P unit name:

```lua
local weapon_unit_3p_name = weapon_unit_name .. "_3p"
local weapon_unit_3p = Managers.state.unit_spawner:spawn_local_unit_with_extensions(
    weapon_unit_3p_name, unit_template_3p_name, extension_init_data_3p)
```

So `wpn_emp_pistol_01_t1` → spawns `wpn_emp_pistol_01_t1_3p` for 3P.
The 1P and 3P meshes are different unit assets (3P is typically a
lower-detail LOD) but share the same authored mesh family.

### What this recipe adds

A custom hook on `GearUtils.spawn_inventory_unit` that lets vanilla
spawn the default 3P unit, then destroys it and spawns a totally
different 3P unit at the same body attachment. Same hook fires for
husks (remote-player view of you), so other players also see the swap.

### Def fields

```lua
{
    item_key        = "cwv_<char>_<name>",
    base_weapon     = "<source_iml_key>",
    -- 1P meshes (also default 3P before swap):
    right_hand_unit = "<source_1P_mesh>",
    left_hand_unit  = "<source_1P_mesh>",
    -- 3P override fields (NEW, optional):
    -- The override is the FULL 3P unit path (suffix already applied —
    -- we bypass vanilla's automatic `_3p` append).
    right_hand_unit_3p_override = "<full_3P_unit_path_including__3p_suffix>",
    -- The sentinel `false` means "no 3P unit at all for this hand"
    -- (used when 3P weapon is single-handed but 1P is dual):
    left_hand_unit_3p_override  = false,
    -- ...rest of def normal...
    template        = "<short>_template",
    item_type       = "cwv_<short>",
}
```

### Template clone

Same as Recipe A1–A6 — clone the source template and route 3P wield
to the target weapon's SM. The source and target may share most
event names natively (e.g. brace and repeater both use
`attack_shoot`, `attack_shoot_fast`, `lock_target`); only the
non-shared events need per-action `anim_event_3p` remap.

```lua
template.wield_anim_3p = "to_<target_3p_sm>"
template.wield_anim_career_3p = {
    es_mercenary = "to_<target_3p_sm>", ...
}
```

Plus the BASE-template wield-patch for the inventory previewer
(per `feedback_cwv_previewer_template_lookup.md`).

### Package loading constraint (open issue)

The override unit must be in a package the package-loader has loaded
for this equip. Vanilla queues packages based on `right_hand_unit`,
NOT on our override field. So if `right_hand_unit` is the brace and
the override is the repeater, the repeater's package isn't queued;
`spawn_local_unit_with_extensions` for the unloaded 3P unit crashes
hard (sometimes not pcall-catchable).

**Same lesson as the Tuskgor Javelin saga (CHANGELOG v0.1.118):** the
elf javelin pickup unit wasn't in the loaded packages for a boar-spear
equip, and `World.spawn_unit` crashed. Resolution there was to use
the boar spear unit for both paths.

For per-perspective swap, two paths to fix:

1. **Add the override unit as a static dependency** of the cwv mod's
   `resource_packages/character_weapon_variants/character_weapon_variants.package`
   (declares it as always-loaded with the mod).
2. **Force-load the package at runtime** via `Managers.package` before
   the spawn, then unload on unequip. More complex; doesn't bloat
   the always-loaded set.

Until either fix is applied, the swap mechanism is gated behind the
VMF setting `cwv_3p_swap_enabled` (default OFF).

### Caveats (even after package loading is solved)

1. **Reload anim desync**: 1P plays the source weapon's reload (e.g.
   brace's two-handed cross-arm reload); 3P plays the target weapon's
   reload (e.g. repeater's lever). Different durations. Gameplay
   timing follows 1P. Visually obvious from the 3P side.
2. **Bots wielding the variant**: bots may not have a `backend_id`
   matching the cwv pattern, so the swap doesn't fire for their
   equips. They see the source weapon's 1P mesh in 3P. Acceptable
   trade.
3. **Cosmetic illusions**: not implemented in v1. Each illusion would
   need both a 1P mesh AND a 3P override. Easier to ship without
   illusions until the swap is stable.
4. **Muzzle / shot effects**: hit / muzzle effects attach to the
   spawned unit. The override's mesh needs the standard attachment
   nodes (`a_fx_muzzle_flash` etc.). Verify by spot-check on the
   target weapon's vanilla functionality.

### The hook (architectural reference)

See `mod:hook("GearUtils", "spawn_inventory_unit", ...)` near the end
of `character_weapon_variants.lua`. Pattern:

1. Always call vanilla first; capture all 4 return values
   (`weapon_3p, ammo_3p, weapon_1p, ammo_1p` — vanilla returns 2 in
   husk path, 4 in local path; Lua tolerates extras).
2. Resolve cwv def from `item_data.backend_id`. If no override or
   setting disabled, return vanilla's values.
3. Outer pcall around the swap. Spawn override BEFORE destroying
   vanilla's 3P unit. If spawn fails, fall back to vanilla (don't
   strand the equip with no 3P unit).
4. On override == false sentinel: destroy vanilla's 3P unit and
   return nil.

If the swap fails for ANY reason, the equip never breaks — vanilla's
3P unit (the source mesh) stays attached as a fallback.

---

# Add-ons

## Stat-modifier add-on

When the variant needs different damage / speed / cleave / stagger
than the base weapon, write a `_create_<short>_template` function that
clones the base template and walks `template.actions[*][*]` to scale
fields. Set `template = "<short>_template"` on the def to point at
your clone.

**Canonical examples:** `_create_imperial_longsword_template` (line ~935),
`_create_imperial_dual_swords_template` (line ~1141), `_create_cudgel_template`
(line ~1216), `_create_shortsword_template` (line ~1407).

**Pattern shape:**

```lua
local _<SHORT>_DAMAGE_MULT  = 0.85   -- or whatever
local _<SHORT>_SPEED_MULT   = 1.15
local _<SHORT>_CLEAVE_MULT  = 1.15
local _<SHORT>_STAGGER_MULT = 0.85

local function _create_<short>_template()
    if not Weapons or not Weapons.<base_template> then
        mod:warning("<base_template> not found — <Display> stat mods unavailable")
        return
    end
    if Weapons.<short>_template then return end                     -- idempotent

    local template = table.clone(Weapons.<base_template>, true)     -- DEEP clone

    if template.actions then
        for _, action_group in pairs(template.actions) do
            if type(action_group) == "table" then
                for _, sub_action in pairs(action_group) do
                    if type(sub_action) == "table" then
                        if sub_action.anim_time_scale then
                            sub_action.anim_time_scale = sub_action.anim_time_scale * _<SHORT>_SPEED_MULT
                        end
                        if sub_action.damage_profile then
                            sub_action.damage_profile = _clone_damage_profile(
                                sub_action.damage_profile,
                                "cwv_<unique_prefix>_",
                                {
                                    damage  = _<SHORT>_DAMAGE_MULT,
                                    stagger = _<SHORT>_STAGGER_MULT,
                                    cleave  = _<SHORT>_CLEAVE_MULT,
                                }
                            )
                        end
                    end
                end
            end
        end
    end

    Weapons.<short>_template = template
    mod:info("Created <short>_template (...)")
end

_create_<short>_template()
```

**Hard rules:**

- **Always `table.clone(t, true)` (deep).** Shallow clones leak
  mutations into vanilla actions.
- **One unique prefix per multiplier set.** `_clone_damage_profile`
  is idempotent (early-returns on existing profile clones), so
  reusing a prefix means the second caller silently inherits the
  first caller's multipliers. Never reuse `cwv_il_`, `cwv_ess_`,
  `cwv_eds_`, `cwv_cudgel_`, `cwv_shortsword_`, `cwv_tj_`.
- **Two-level loop only.** `actions → action_group → sub_action`.
  `anim_time_scale` and `damage_profile` never live deeper.
- **Never touch `sub_action.anim_event` (1P).** 1P is universal —
  see `feedback_1p_animations_universal.md`. Anim work is
  3P-only and only via `anim_event_3p`.

**Inline-shape damage profiles (thrown projectiles):** use
`_clone_inline_throw_profile` (line ~2003) instead of
`_clone_damage_profile`. They have different shapes —
PowerLevelTemplates string-key vs literal `power_distribution_near.attack`.

---

## Damage-type swap add-on

When the variant needs to remove a damage type the base weapon has
(e.g. "Sienna's dagger but no fire DoT and no AoE slam").

**Canon:** `_create_shortsword_template` (line ~1407).

### Step 0 — find the fire (or AoE, or whatever)

Don't trust profile names. Walk the chain.

1. Open the SOURCE weapon template (e.g.
   `Vermintide-2-Source-Code/scripts/settings/equipment/weapon_templates/1h_hammers_wizard.lua`).
   Grep for `damage_profile = "..."` — note every distinct profile name and
   which sub-action uses it.
2. Also grep for `hit_effect = "..."`, `impact_sound_event = "..."`,
   `armor_impact_sound_event = "..."`, `no_damage_impact_sound_event = "..."`,
   `damage_profile_aoe = "..."`, `damage_profile_target = "..."`. These can
   all carry fire-themed values.
3. For every distinct `damage_profile` value, grep
   `damage_profile_templates.lua` (and DLC variants) for both:
   - `DamageProfileTemplates\.<name>\s*=` (the base definition), and
   - `DamageProfileTemplates\.<name>\.(default_target|targets|critical_strike|cleave_distribution)\s*=` (the override lines, often elsewhere in the file)
   Read the resolved field values. Look for `_burn_*`, `_burning_*`,
   `dot_template_name`, `slam_burn_aoe`, `damage_type = "burn*"`. THESE are
   the actual fire indicators.
4. For every fire-bearing profile, find a non-burn analog of the same shape
   in `damage_profile_templates.lua`. Examples (verified in the source):
   - `medium_blunt_smiter_heavy` (burn) → `medium_blunt_smiter_2h_hammer` (clean, same heavy-smiter shape)
   - `dagger_burning_slam_fencer` (burn) → `medium_slashing_linesman` (per shortsword precedent)

If no clean analog exists for a given burn profile shape, you have two
options: clone-and-rewrite (replace the burn `default_target` references
in the cloned profile — more involved than the swap-map pattern), or
remove the field entirely (`false` in the swap map, accepting the loss
of that sub-action's damage component — only safe for AoE/secondary
fields).

### Three-step pass (existing recipe)

**Three-step pass inside the actions loop:**

```lua
-- Step 1: BEFORE _clone_damage_profile, swap burning damage profiles
-- to non-burning analogs (or remove for fields with no clean analog).
local _<SHORT>_DAMAGE_PROFILE_SWAP = {
    dagger_burning_slam_fencer        = "medium_slashing_linesman",
    dagger_burning_slam_fencer_aoe    = false,                       -- remove
    dagger_burning_slam_target_fencer = false,                       -- remove
    medium_burning_smiter_stab_H      = "medium_slashing_smiter_stab",
}
-- Within sub_action loop:
local swap_fields = { "damage_profile", "damage_profile_aoe", "damage_profile_target" }
for _, field in ipairs(swap_fields) do
    local profile = sub_action[field]
    if profile and _<SHORT>_DAMAGE_PROFILE_SWAP[profile] ~= nil then
        sub_action[field] = _<SHORT>_DAMAGE_PROFILE_SWAP[profile] or nil
    end
end

-- Step 2: clone-and-scale the (now-swapped) damage_profile per Stat-modifier add-on.

-- Step 3: AFTER the clone, swap fire-themed FX/sound fields too. This is the
-- step v0.1.155 missed and v0.1.156 fixed — staff_spark FX package isn't
-- loaded for non-Sienna wielders, so a sub-action that fired its hit_effect
-- crashed the engine.
local _<SHORT>_FX_SWAP = {
    hit_effect = {
        staff_spark = "melee_hit_sword_1h",
    },
    impact_sound_event = {
        fire_hit = "slashing_hit",
    },
    armor_impact_sound_event = {
        fire_hit = "slashing_hit",
    },
    no_damage_impact_sound_event = {
        fire_hit_armour = "slashing_hit_armour",
    },
}
for field, swap_map in pairs(_<SHORT>_FX_SWAP) do
    local current = sub_action[field]
    if current and swap_map[current] then
        sub_action[field] = swap_map[current]
    end
end
```

**Critical:** the order is mandatory. Step 1 must run BEFORE Step 2
(otherwise you scale the wrong profile, or worse, scale a swapped
profile into a fresh `cwv_<prefix>_<wrong_name>` clone). Step 3 catches
FX/sound fields that survived the first two steps — without it,
sub-actions still reference burning effect packages, and the engine
crashes mid-sweep on first impact.

**Strict-lookup gotcha:** every replacement damage profile name must
already exist in `DamageProfileTemplates`. `NetworkLookup.damage_profiles`
has an error-throwing `__index` that crashes on missing keys. v0.1.151
shipped `medium_slashing_linesman_fencer` — that doesn't exist — and
crashed first attack. v0.1.154 fixed it by switching to the real key
`medium_slashing_linesman`.

---

## Inverse-hand add-on

When the variant inverts the base weapon's hand layout (e.g. mace+sword
where vanilla is sword+mace). Damage profiles, hit effects, and impact
sounds need to swap to follow the new layout.

**Canon:** `_create_sword_and_mace_template` (line ~1312).

**Pattern:**

```lua
local _<SHORT>_RIGHT_HAND_SWAP = {
    damage_profile = { <was_left_type> = <becomes_right_type> },
    hit_effect     = { <was_left_fx>   = <becomes_right_fx> },
    impact_sound_event = { <was_left_sfx> = <becomes_right_sfx> },
    no_damage_impact_sound_event = { <was_left_armor_sfx> = <becomes_right_armor_sfx> },
}
local _<SHORT>_LEFT_HAND_SWAP = {
    -- mirror of the above
}

local function _<short>_apply_field_swaps(sub_action, swaps)
    for field, swap_map in pairs(swaps) do
        local current = sub_action[field]
        if current and swap_map[current] then
            sub_action[field] = swap_map[current]
        end
    end
end

-- In the sub_action loop:
local hand = sub_action.weapon_action_hand
if hand == "right" then
    _<short>_apply_field_swaps(sub_action, _<SHORT>_RIGHT_HAND_SWAP)
elseif hand == "left" then
    _<short>_apply_field_swaps(sub_action, _<SHORT>_LEFT_HAND_SWAP)
elseif hand == "both" then
    -- Swap left/right damage profile references where they differ.
    local pl = sub_action.damage_profile_left
    local pr = sub_action.damage_profile_right
    if pl and pr and pl ~= pr then
        sub_action.damage_profile_left  = pr
        sub_action.damage_profile_right = pl
    end
end
```

**Animations are unchanged** — the body still goes through the same
state machine and plays the same dual-wield clips. Only data swaps.

---

## Scale: type-level vs per-illusion (cross-model picker)

When a variant ships a curated set of cosmetic illusions that all use a
different mesh family from the source template, you usually want every
illusion to render at a corrected scale.

### Type-level (preferred default)

For "all illusions in this variant should share the same scale" — write
a single `_type_transforms[<item_type>]` entry. It applies to the default
mesh AND every illusion that resolves through this variant's
`item_type` (because the registration loop at line ~3599 walks
`_resolve_field(def, "right_hand_scale")` which falls through to the
type entry).

```lua
local _type_transforms = {
    cwv_es_maul = {
        right_hand_scale  = { 1.4, 1.4, 2.0 },
    },
}
```

Used by: `cwv_imperial_longsword` (Y −20%, Z −10% across the family).

### Per-illusion override (when one mesh deviates)

When a SPECIFIC source mesh in the curated illusion set has different
proportions from the rest, override per-illusion. Set `right_hand_scale`
/ `left_hand_scale` / `right_hand_offset` / `left_hand_offset` directly
on the `_custom_illusions` entry. The synthetic-def builder at
line ~3631 picks these up into `_skin_transform_map[<skin_key>]`, and
`_resolve_field` finds them BEFORE falling through to the type-level.

```lua
{
    skin_key       = "cwv_<short>_<source>",
    matching_weapon = "wh_1h_hammer",
    source_skin    = "es_2h_hammer_skin_01",
    target_combo   = "cwv_<short>_skins",
    right_hand_scale  = { 0.75, 0.75, 0.575 },   -- overrides type-level
    right_hand_offset = { 0, 0, -0.04 },
    can_wield      = _es_careers,
},
```

Used by: `cwv_es_warpriest_hammer` (rescales 8 greathammer illusions
down to fit a 1H slot).

### Decision rule

- All illusions = same family / same scale → **type-level** (cleaner).
- One illusion = different proportions → **per-illusion override**.
- Mix of both → type-level for the default, per-illusion for the outliers.

Don't duplicate scale fields per variant when a type-level entry would
suffice. See `feedback_cwv_imperial_longsword_family.md`.

---

## Disable a weapon special action add-on

When the variant should NOT have the source weapon's special ability —
e.g. Saltzpyre's rapier without the pistol-shot, or the tuskgor javelin
without the magic auto-catch reload.

**Canon:** `_create_rapier_template` (line ~3259) — disables
`action_three.*.condition_func` to remove the pistol shoot.
`_create_tuskgor_javelin_template` (line ~2502) — disables
`weapon_reload.default.condition_func` to remove the auto-catch reload.

### Pattern

The action stays defined for state-machine / network consistency but
its `condition_func` (and `chain_condition_func`) returns false, so the
engine never transitions into the action.

```lua
-- Module-scope helper (file scope, declared once and shared so VMF
-- hook bookkeeping doesn't see a fresh closure on each call).
local function _always_false() return false end

-- Inside _create_<short>_template, after table.clone:
if template.actions and template.actions.<action_name> then
    for _, sub_action in pairs(template.actions.<action_name>) do
        if type(sub_action) == "table" then
            sub_action.condition_func       = _always_false
            sub_action.chain_condition_func = _always_false
        end
    end
end
```

`<action_name>` is the action group key in the source template
(`action_one`, `action_two`, `action_three`, `weapon_reload`, etc.).

### What this DOES NOT do

- **It does not remove the action from the state machine.** The action
  is still wired into chains (e.g. `action_two`'s `block_shot` chain
  still references `action_three`). Pressing the input that would
  trigger it produces no transition; the player just sees nothing happen.
- **It does not detach related visual / audio.** If the source action's
  `anim_event` is referenced from elsewhere, that reference still
  resolves. Usually fine — the disabled action's anim never fires anyway.
- **It does not prevent the action from being COMPILED into the loadout.**
  The action stays in the action_lookup_data table, just never executes.

### Don't reach for this when

- The action's mere existence corrupts state (rare — most actions are
  gated by condition_func at fire time, so blocking the func is enough).
- You need to remove the input binding entirely (different mechanism —
  modify `template.action_inputs` instead).

### Hand-in-hand with: hide the off-hand mesh

A weapon with a "shoot the off-hand pistol" special action usually has
a visible pistol mesh on the off-hand. Disabling the action leaves the
mesh attached. To remove it visually:

```lua
left_hand_unit = "units/weapons/player/wpn_invisible_weapon",
```

The slot still exists for the engine's purposes; it just renders nothing.
See `cwv_es_rapier` (line ~547).

### Critical: strip component bindings from the cloned template's
### attachment_node_linking

Multi-component weapons (pistols, drakefires, the cogwork hammer, etc.)
have `<hand>_hand_attachment_node_linking` with bindings to mesh-specific
node names like `lock_hammer`, `trigger`, `lock_lid`, `rotator`. Vanilla
calls `Unit.node(weapon_unit, target_name)` for every binding at attach
time — and crashes with `[Script Error]: <target_name>` if the unit
doesn't have that node.

`wpn_invisible_weapon` does NOT have those component nodes. So when you
swap a pistol mesh for the invisible mesh, you also have to override
the cloned template's linking to strip the component bindings:

```lua
-- Inside _create_<short>_template, after table.clone:
template.left_hand_attachment_node_linking = {
    first_person = {
        wielded   = { { source = "j_leftweaponattach", target = 0 } },
        unwielded = { { source = "j_hips",             target = 0 } },
    },
    third_person = {
        display   = { { source = "j_leftweaponattach", target = 0 } },
        wielded   = { { source = "j_leftweaponattach", target = 0 } },
        unwielded = { { source = "j_hips",             target = 0 } },
    },
}
```

This attaches the invisible weapon to the body's `j_leftweaponattach`
node at the weapon's root (node 0 — every unit has this). No component
lookups, no crashes.

**Patch the CLONE only**, not the base template. Native wielders
(Saltzpyre with the rapier+pistol) still need the full component
bindings for their pistol mesh. Mutating the base would break them.

Hit by `cwv_es_rapier` v0.1.183 → fixed v0.1.187. Crash GUID
`acb910d1-a625-49b1-b899-86d48d27462d`.

### Same hazard, ILLUSIONS edition: omit `left_hand_unit` on cross-character illusions

The clone-template override (above) handles the variant's IN-GAME equip:
the cloned template's stripped linking is used when the engine spawns the
invisible left mesh. But COSMETIC ILLUSIONS hit a different code path
(`LootItemUnitPreviewer._load_item_units`) that reads
`item_units.left_hand_unit` from the SKIN entry, then spawns + attaches
using the BASE template's linking (the BASE still has the full pistol
component bindings).

If the illusion entry sets `left_hand_unit = "wpn_invisible_weapon"`,
the previewer will:

1. Append `_3p` → spawn `wpn_invisible_weapon_3p`
2. Look up `item_template.left_hand_attachment_node_linking.third_person.display`
   on the BASE template (still has full pistol bindings)
3. Call `GearUtils.link` which iterates the bindings, calling
   `Unit.node(display_unit, source)` and `Unit.node(weapon_unit, target)`
   for each
4. Crash on the first node that doesn't resolve (we hit `j_leftweaponattach`
   in v0.1.191; component lookups would also fail)

**Fix: don't set `left_hand_unit` on the illusion entries at all.** Per
`BackendUtils.get_item_units` line 174, the function unconditionally
overwrites `item_units.left_hand_unit` from the skin entry's value
(including nil). With nil, the previewer's `if left_hand_unit then`
branch (line 281 of `loot_item_unit_previewer.lua`) skips the left-hand
spawn entirely. No spawn → no node lookup → no crash.

```lua
-- WRONG — crashes the cosmetic picker
local iml_entry = {
    -- ...
    left_hand_unit = "units/weapons/player/wpn_invisible_weapon",
    -- ...
}
local ws_entry = {
    -- ...
    left_hand_unit = "units/weapons/player/wpn_invisible_weapon",
    -- ...
}

-- RIGHT — picker skips left-hand spawn entirely
local iml_entry = {
    -- ...
    -- left_hand_unit DELIBERATELY omitted
    -- ...
}
local ws_entry = {
    -- ...
    -- left_hand_unit DELIBERATELY omitted
    -- ...
}
```

The variant's DEFAULT skin (no illusion applied) can still carry
`left_hand_unit = invisible_pistol` via the variant's own IML entry — so
the no-pistol identity is enforced there. Only the illusion entries omit
it. With an illusion applied: no left mesh at all, and since the
intended look was invisible anyway, no visible difference.

Hit by `cwv_es_rapier` v0.1.191 → fixed v0.1.192. Crash GUID
`962fe355-a0d4-43fd-9a29-bd64fca6a0ac`.

### Same hazard, BODY-skeleton edition: cross-character `unwielded` bones

The rapier crash above was about WEAPON-MESH nodes (`lock_hammer` on
the pistol unit). The same `Unit.node` failure mode also fires the
other way — when the linking references a BODY-SKELETON bone that
exists only on the source character's body but not on the wielder's.

**Canon:** `cwv_es_maul` v0.1.188. Sienna's wizard hammer template
uses `AttachmentNodeLinking.brw_hammer.third_person.unwielded.source =
"a_unwielded_brw_mace"` — a custom bone authored on her 3P body for
the holstered-mace pose. Kruber's body doesn't have it; opening the
inventory on a Kruber career carrying the Maul crashed with
`[Script Error]: a_unwielded_brw_mace`.

The cloned-template override (recipe above) only fixes the in-game
equip path. The **inventory previewer reads the BASE template**, not
our clone (`feedback_cwv_previewer_template_lookup.md`), and bypasses
the override. To fix the previewer too you need to also patch the
BASE template's linking — but scoped tightly so native wielders
aren't broken.

**Pattern: patch only the offending unwielded slot on the base.**

```lua
local base = Weapons.<base_template_name>
if base and base.right_hand_attachment_node_linking
        and base.right_hand_attachment_node_linking.third_person then
    base.right_hand_attachment_node_linking.third_person.unwielded = {
        { source = "j_hips", target = 0 },
    }
end
```

`wielded` and `first_person` typically use universal bones
(`j_rightweaponattach`, `j_leftweaponattach`, `j_hips`) that exist on
all 6 character bodies, so leaving them intact preserves the native
wielder's in-hand behavior. Only the unwielded (holstered) pose
changes — to a standard hip attachment instead of the
character-specific bone. Small visual regression for the native
wielder; fixes the cwv variant's previewer crash.

**Before patching the base, verify the linking entry isn't shared
with other weapon templates.** Grep `AttachmentNodeLinking.<key>`
across `Vermintide-2-Source-Code/scripts/`. If only ONE template
references it, the patch is well-scoped. If multiple do, you'd be
affecting weapons unrelated to your variant — choose a different
approach (per-variant runtime hook, or accept the previewer crash and
warn the user not to preview).

### Decision rule

| Failure node lives on | Patch the CLONE | Patch the BASE | Notes |
|---|---|---|---|
| Weapon mesh (e.g. `lock_hammer`, `trigger`) | ✓ Required | ✗ Don't | Native wielder's mesh has the node; only your invisible/swapped mesh lacks it |
| Body skeleton (e.g. `a_unwielded_brw_mace`) | ✓ Required (in-game) | ✓ Required (previewer), scoped to unwielded | Kruber/Bardin/etc. lack the source character's custom bone |

---

## Cosmetic harvesting from a different weapon's skin pool

When the variant's curated cosmetic illusions should come from
**another weapon's** skin pool entirely, not the variant's
`base_weapon` skin pool. This is for variants whose visual identity
is "the X-half of weapon Y" — e.g. the Maul takes only the mace half
of mace+sword skins.

**Canon:** `_register_macesword_mace_maul_illusions` (line ~4146) —
harvests from `es_dual_wield_hammer_sword` skins for the Maul, NOT
from `es_1h_mace` (the variant's `base_weapon`).

### Pattern

Same shape as the dual-wield illusion harvest functions
(`_register_kruber_1h_sword_dual_illusions` etc.) but the
`matching_item_key` filter is the OTHER weapon's IML key, not the
variant's base. Single-handed harvest from a dual-handed source means
you take ONLY `source.right_hand_unit` (or `left_hand_unit`) and
discard the other half.

```lua
local function _register_<short>_illusions()
    if not ItemMasterList or not WeaponSkins then return end

    local source_keys = {}
    for skin_key, entry in pairs(ItemMasterList) do
        if type(entry) == "table"
                and entry.item_type == "weapon_skin"
                and entry.matching_item_key == "<other_weapon_iml_key>" then
            source_keys[#source_keys + 1] = skin_key
        end
    end
    table.sort(source_keys)

    -- Force a single-rig display_unit because the source's rig is
    -- typically dual or wrong-family for our variant's slot shape.
    local single_hand_display = "units/weapons/weapon_display/display_<family>"

    for _, source_key in ipairs(source_keys) do
        local new_key = "cwv_<short>_" .. source_key
        if _custom_skin_keys[new_key] then goto continue end
        local source = WeaponSkins.skins[source_key]
        if not source or not source.right_hand_unit then goto continue end

        -- Take ONLY right_hand_unit. Discard source's left_hand_unit
        -- (the OTHER weapon's half — doesn't belong on our variant).
        local iml_entry = {
            key               = new_key,
            name              = new_key,
            item_type         = "weapon_skin",
            slot_type         = "weapon_skin",
            matching_item_key = "cwv_<short>",
            rarity            = source.rarity,
            display_name      = source.display_name,
            description       = source.description,
            display_unit      = single_hand_display,  -- override source's rig
            hud_icon          = source.hud_icon,
            inventory_icon    = source.inventory_icon,
            information_text  = "information_weapon_skin",
            right_hand_unit   = source.right_hand_unit,
            -- Deliberately no left_hand_unit
            template          = source.template,
            can_wield         = _<char>_all_careers,
        }
        if source.material_settings_name then
            iml_entry.material_settings_name = source.material_settings_name
        end
        ItemMasterList[new_key] = iml_entry

        local ws_entry = {
            description     = source.description,
            display_name    = source.display_name,
            display_unit    = single_hand_display,
            hud_icon        = source.hud_icon,
            inventory_icon  = source.inventory_icon,
            rarity          = source.rarity,
            right_hand_unit = source.right_hand_unit,
            template        = source.template,
        }
        if source.material_settings_name then
            ws_entry.material_settings_name = source.material_settings_name
        end
        WeaponSkins.skins[new_key] = ws_entry

        local combos = WeaponSkins.skin_combinations.cwv_<short>_skins
        if combos then
            local rarity = source.rarity or "exotic"
            local tier = combos[rarity]
            if tier then tier[#tier + 1] = new_key end
        end

        if NetworkLookup and NetworkLookup.weapon_skins
                and not rawget(NetworkLookup.weapon_skins, new_key) then
            local tbl = NetworkLookup.weapon_skins
            local idx = #tbl + 1
            rawset(tbl, idx, new_key)
            rawset(tbl, new_key, idx)
        end
        if NetworkLookup and NetworkLookup.item_names
                and not rawget(NetworkLookup.item_names, new_key) then
            local tbl = NetworkLookup.item_names
            local idx = #tbl + 1
            rawset(tbl, idx, new_key)
            rawset(tbl, new_key, idx)
        end

        _custom_skin_keys[new_key] = true
        ::continue::
    end
end
```

### Right vs left — pick deliberately

Look at the source skin data and decide which hand carries the mesh
your variant wants. Mace+sword skins (`es_dual_wield_hammer_sword`)
have:
- `right_hand_unit` = mace mesh
- `left_hand_unit` = sword mesh

If you want the mace, take right. If you want the sword, take left
(rename `right_hand_unit = source.left_hand_unit` in the IML/WS
entries).

### Display rig must match the variant's slot shape

Source skin's `display_unit` is for the source's slot shape (dual,
shield, etc.). Your variant is single-hand or has a different
attachment layout. Force `display_unit` on every clone to a rig that
matches your variant. Single-hand examples:
- 1H hammer/mace: `display_1h_hammer`
- 1H sword: `display_1h_swords` or `display_1h_weapon`
- 1H axe: `display_1h_axes`

Wrong rig = `j_leftweaponattach` crash on the cosmetic picker (the
old `J_LEFTWEAPONATTACH_INVESTIGATION.md` lesson).

---

## Per-perspective scale (`_1p` / `_3p` suffixes)

When 1P (held first-person view) and 3P (third-person body) need
different scales — usually because a model authored for 3P proportions
reads small in 1P, or because a 1P throw animation would clip the
camera at full scale.

**Pattern:**

```lua
{
    -- ...other fields...
    right_hand_scale     = { 1.0, 1.0, 1.0 },      -- unified default
    right_hand_scale_1p  = { 1.1, 1.1, 1.1 },      -- bigger in 1P only
    -- 3P inherits the unified value.
}
```

**Resolution:** per-perspective field → unified field → type-level
default → nil. The unified field is fine for normal cross-perspective
tuning; reach for `_1p` / `_3p` only when 1P and 3P need to differ.

**`scale_3p_only = true`** is the older mechanism for "skip 1P
entirely." Equivalent to setting `*_scale_1p = {1, 1, 1}` when the
unified is non-1.0. Use `scale_3p_only` when you want to opt OUT of 1P
scaling; use `_1p` overrides when you want a DIFFERENT 1P scale than
3P.

See `cwv_es_dual_swords` (line ~353) and `cwv_es_javelin` (line ~199)
for shipped examples.

---

# Icons — completion gate

A variant is **NOT complete** until it ships its own `inventory_icon`
(menu) and `hud_icon` (in-game). Until custom icons are authored, point
at the source weapon's vanilla icons as placeholders.

When using placeholders:

- **Add a `-- TODO icon: ...` comment** on the def's `inventory_icon`
  / `hud_icon` lines.
- **Mark the variant in `WEAPON_CATALOG.md` CWV section** as "Notes:
  TODO custom icons (placeholder)".
- **Mention in the CHANGELOG entry** that icons are placeholder.

The placeholder must come from a real vanilla atlas key. Wrong type
crashes the GUI renderer (`Material 'X' not found in Gui` — see
CHANGELOG v0.1.10).

| Field | Atlas prefix | Example |
|---|---|---|
| `inventory_icon` | `icon_wpn_*` | `icon_wpn_brw_mace_01` |
| `hud_icon` | `weapon_generic_icon_*` | `weapon_generic_icon_mace` |

The HUD icon is generic-by-shape (sword, axe, hammer, mace, staff,
halberd, etc.) so reusing the source's HUD icon is usually fine. The
inventory icon is mesh-specific — using the source's looks "wrong"
in the inventory until replaced.

---

# Pre-deploy checklist

Before every build:

- [ ] **`MOD_VERSION` bumped** at line 3. Required to confirm the build
      loaded — see `feedback_version_bump.md`.
- [ ] **`CHANGELOG.md` entry added** under a new `## 0.1.X-dev (YYYY-MM-DD)` heading.
- [ ] **Forward-reference audit.** Every function/local you call must be
      defined ABOVE the call site. Lua 5.1 has no hoisting. This
      codebase has shipped 5+ crashes from this single bug class —
      see `feedback_lua_forward_reference.md`. Skim from your edit
      down to file end.
- [ ] **Build:** `node C:/Users/danjo/source/repos/vmb/vmb.js build character_weapon_variants --no-workshop --cwd`
- [ ] **Bundle output verified** — `bundleV2/` should have fresh files.
- [ ] **Deploy** to `C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\3716869446`.
- [ ] **Full game restart.** Hot-reload is unsafe — see
      `feedback_hot_reload_unfixable.md`.

---

# Verification matrix

After deploy + restart, walk every applicable cell:

| Path | What to do | What to check |
|---|---|---|
| **Inventory** | Open inventory on the variant's character | Item appears with correct name, description, icon, rarity color |
| **Character preview** | Click the variant in inventory | Mesh renders correctly (no T-pose, no base-weapon mesh fallback). Wield pose looks right. Scale + grip offset applied. |
| **Illusion picker** | Open the variant's cosmetic menu | Picker opens without crash. Curated illusions show up; vanilla skins don't bleed through. Each illusion thumbnail spawns correctly. (Dual-wield: BOTH hands render — the `j_leftweaponattach` regression test.) |
| **Forge (if `rarity = "default"`)** | Re-roll properties, salvage, apply illusion | All forge actions work. Item shows as unlocked, not locked-illusion. |
| **In-game equip** | Enter a mission, swap to the weapon | Weapon spawns. Wield pose correct in 3P (use a mirror or spectator). Held mesh visible in 1P. |
| **In-game combat** | Run the full chain: L1, L2, L3, H1, H2, push, push-attack | Each clip plays visibly on the 3P body. No `[MISSING]` warnings in `wt animlog`. Damage feels right (vs base — verify with `cwv_dump_javelin_impact` or similar dumper). |
| **Native-wielder regression** | Equip the BASE weapon on its native wielder | Nothing changed for them. Saltzpyre's native axe+falchion still animates as before, etc. (System B and cross-access remap are scoped per-career; if a native wielder regressed, you mutated a shared template.) |
| **Husk check (cross-character only)** | Have a teammate or bot wield the variant | Their body looks right too. Cross-access remap doesn't cover husks by default — note any gap. |
| **Multiplayer** | Join a lobby with the variant equipped | No crash on item sync. Other peers either need the mod or see the matchmaking gate (see `project_modded_matchmaking.md`). |

If any cell fails, see `ANIMATION_FIX_PLAYBOOK.md` for animation
issues, `J_LEFTWEAPONATTACH_INVESTIGATION.md` for dual-wield rig
issues, or open the relevant CHANGELOG entry for the recipe's canon
variant — most failure modes have a documented fix history.

---

# When this guide is wrong

This file describes how the system works as of MOD_VERSION
`0.1.159-dev`. If a recipe's claim conflicts with current code, the
code wins — open a CHANGELOG entry to fix the recipe.

For deeper architectural questions, see `DEVELOPMENT.md`. For
animation, `ANIMATION_FIX_PLAYBOOK.md`. For the ~20-version saga
behind `_force_display_unit`, `J_LEFTWEAPONATTACH_INVESTIGATION.md`.
For the per-mod build commands, parent `CLAUDE.md`.
