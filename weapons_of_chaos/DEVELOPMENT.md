# Weapons of Chaos — Development

Lets the player characters wield **enemy** weapons (chaos warrior blades,
skaven cleavers, beastmen axes, and the named keep trophy weapons such as
**Nurgloth's Scythe**). Built the duplicate-weapon way, modeled directly on
`character_weapon_variants` (CWV): every weapon is a real inventory item cloned
from a player base weapon template, with its held mesh swapped to an enemy
weapon's `.unit`.

> **Status:** early implementation with one registered item, Blightreaper. Its
> interim held mesh is the resident Empire sword because the intended trophy
> prop cannot be loaded safely. This doc remains the research foundation for
> enemy meshes, trophy paths, and the duplicate-item constraints.

All paths/line citations below are against the decompiled source at
`C:/Users/danjo/source/repos/Vermintide-2-Source-Code` (referred to as `src/`).

---

## 1. Where enemy weapon models live

The canonical catalog of enemy weapon meshes is
**`src/scripts/settings/ai_inventory_templates.lua`**. It builds a flat
`items = {}` table where each entry is:

```lua
items.wpn_skaven_sword_01_right = {
    unit_name = "units/weapons/enemy/wpn_skaven_set/wpn_skaven_sword_01",  -- the mesh
    attachment_node_linking = AttachmentNodeLinking.ai_1h_weapon.right,    -- enemy attach rig
}
```
(`ai_inventory_templates.lua:12-15`)

**Directory convention:** enemy weapon meshes live under
`units/weapons/enemy/<weapon_set>/<weapon_name>` — distinct from player weapons,
which live under `units/weapons/player/...`.

### Verified example `.unit` paths (copy-pasteable)

All confirmed in `ai_inventory_templates.lua` at the cited lines:

| Faction | Weapon | `.unit` path | Line |
|---|---|---|---|
| Skaven | Sword 01 | `units/weapons/enemy/wpn_skaven_set/wpn_skaven_sword_01` | 13 |
| Skaven | Short sword | `units/weapons/enemy/wpn_skaven_short_sword/wpn_skaven_short_sword` | 45 |
| Skaven | Stormvermin halberd | `units/weapons/enemy/wpn_skaven_set/wpn_skaven_halberd_41` | 552 |
| Skaven | Champion halberd | `units/weapons/enemy/wpn_skaven_set/wpn_skaven_halberd_stormvermin_champion` | 556 |
| Chaos | 2H axe 01 | `units/weapons/enemy/wpn_chaos_set/wpn_chaos_2h_axe_01` | 571 |
| Chaos | Marauder sword 01 (`moc`) | `units/weapons/enemy/wpn_chaos_set/wpn_moc_sword_01` | 595 |
| Chaos | Heavy maul 01 | `units/weapons/enemy/wpn_chaos_set/wpn_chaos_heavy_maul_01` | 818 |
| Chaos sorcerer | **Scythe (Nurgloth's)** | `units/weapons/enemy/wpn_chaos_sorcerer_scythe/wpn_chaos_sorcerer_scythe_01` | 699 |
| Beastmen | Gor axe 01 | `units/weapons/enemy/wpn_bm_gor_set_01/wpn_bm_gor_axe_01` | 966 |
| Beastmen | Gor sword 01 | `units/weapons/enemy/wpn_bm_gor_set_01/wpn_bm_gor_sword_01` | 986 |
| Beastmen | Bestigor halberd 01 | `units/weapons/enemy/wpn_bm_bestigor_set_01/wpn_bm_bestigor_halberd_01` | 1010 |
| Beastmen | Banner/standard | `units/weapons/enemy/wpn_bm_standard_01/wpn_bm_standard_01` | 1034 |
| Beastmen | Ungor spear 01 | `units/weapons/enemy/wpn_bm_ungor_set_01/wpn_bm_ungor_spear_01` | 1038 |

There are **hundreds** of entries (skaven sword 01-19+, chaos sets, beastmen
gor/bestigor/ungor/minotaur sets, undead/skeleton ethereal sets, sorcerer
book/staff). To enumerate the full set for a faction, grep:

```
src/scripts/settings/ai_inventory_templates.lua
  pattern:  unit_name = "units/weapons/enemy/<set_prefix>
```

### How breeds pick a weapon

Each breed file (`src/scripts/settings/breeds/breed_*.lua`) names a
`default_inventory_template` string. That template (defined further down in
`ai_inventory_templates.lua`, around line 1700+) lists which `items.*` keys the
breed equips. Example: `breed_chaos_exalted_sorcerer_drachenfels.lua` uses an
inventory template that includes `items.wpn_chaos_sorcerer_scythe_01`
(`ai_inventory_templates.lua:1707`). You don't need the breed/template plumbing
to build a player weapon — you only need the `unit_name` mesh path — but it's
how to discover which mesh a given enemy actually carries.

---

## 2. Keep trophy artifacts (the marquee target)

**Two distinct things share the "trophy" name — don't conflate them:**

1. **Keep display props** — the diorama statues mounted in the inn. Defined in
   **`src/scripts/settings/trophies.lua`** as `Trophies.hub_trophy_*` entries,
   each pointing at a **prop** unit under `units/props/inn/hub_trophy/...`:

   ```lua
   Trophies.hub_trophy_nurgloth = {
       description  = "keep_trophy_nurgloth_description",
       display_name = "keep_trophy_nurgloth",
       icon         = "icon_placeholder",
       sound_event  = "keep_trophy_nurgloth_description",
       unit_name    = "units/props/inn/hub_trophy/hub_trophy_nurgloth",  -- a STATUE, not a weapon
   }
   ```
   (`trophies.lua:46-52`)

   Full set (`trophies.lua:46-81`): `hub_trophy_nurgloth`, `_burblespue`,
   `_bodvarr`, `_bugman`, `_skarrik`, `_holly`, `_bogenhafen`, `_rasknitt`.
   These are **display dioramas** (a posed scene / bust), NOT the wieldable
   weapon mesh. Mounted via `keep_decoration_settings.lua` +
   `keep_decoration_trophy_extension.lua`.

2. **The actual wieldable weapon mesh.** For Nurgloth's Scythe the weapon model
   is the enemy scythe in §1:
   `units/weapons/enemy/wpn_chaos_sorcerer_scythe/wpn_chaos_sorcerer_scythe_01`
   (`ai_inventory_templates.lua:699`).

   **This is the path to clone onto a player weapon** — `hub_trophy_nurgloth`
   is a statue and is not wieldable. The same applies to the other named boss
   trophies: the wieldable artifact is the boss's enemy weapon mesh in
   `ai_inventory_templates.lua`, not the `hub_trophy_*` prop.

> **Open follow-up:** map each named keep trophy → the boss's actual enemy
> weapon `.unit`. Nurgloth → `wpn_chaos_sorcerer_scythe_01` is confirmed.
> Burblespue / Bodvarr / Skarrik / Rasknitt etc. need their boss breed's
> inventory template walked to find the corresponding `units/weapons/enemy/...`
> mesh (some bosses may use a unique one-off mesh; verify per-boss before
> promising a wieldable).

---

## 3. Player-wieldable item structure (what we clone)

Player weapons are entries in
**`src/scripts/settings/equipment/item_master_list_exported.lua`** (most
weapons; DLC weapons live in sibling files `item_master_list_anvil.lua`,
`_belakor.lua`, `_lake.lua`, `_morris.lua`, etc.). Canonical shape:

```lua
ItemMasterList.es_1h_sword = {
    item_type       = "es_1h_sword",
    slot_type       = "melee",
    template        = "one_handed_swords_template_1",  -- moveset / anim / hit detection
    right_hand_unit = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",  -- THE MESH
    -- left_hand_unit = "..."                           -- for shields / dual-wield
    rarity          = "plentiful",
    display_name    = "es_1h_sword_skin_01_name",       -- loc key
    description     = "es_1h_sword_skin_01_description", -- loc key
    hud_icon        = "weapon_generic_icon_sword",
    inventory_icon  = "icon_wpn_emp_sword_02_t1",
    skin_combination_table = "es_1h_sword_skins",
    property_table_name = "melee",
    trait_table_name    = "melee",
    can_wield = { "es_huntsman", "es_knight", "es_mercenary" },
}
```

The fields that matter for an enemy-mesh duplicate:
- **`right_hand_unit` / `left_hand_unit`** — swap these to the enemy `.unit`.
- **`template`** — keep the player base weapon's template so the moveset, hit
  detection, and animations stay intact (enemy meshes carry none of that).
- **`item_type` / `slot_type`** — keep matching the base weapon's slot.
- **`can_wield`** — the careers allowed to equip it.

---

## 4. Recommended duplicate approach (CWV pattern)

Enemy weapons are **not** player `ItemMasterList` items and have no player
template, no 1P variant, no moveset. So we do exactly what CWV does for
cross-character weapons, except the swapped mesh is an enemy `.unit` instead of
another character's player weapon:

1. **Pick a player base weapon** whose moveset/handling fits the enemy weapon's
   shape (e.g. a 2H scythe → a 2H sword or 2H hammer base; a skaven cleaver → a
   1H axe/sword base). The base's `template` defines how it plays.
2. **Clone the base's `ItemMasterList` entry** (CWV's `_variant_definitions` +
   `_build_entry` machinery) into a new `woc_<faction>_<name>` item.
3. **Swap `right_hand_unit` (and `left_hand_unit` if applicable) to the enemy
   `.unit`** from §1.
4. **Keep the base `template`** so the 1P view, moveset, and 3P body animations
   come from a real player weapon. (1P is universal across characters — see the
   repo's `feedback_1p_animations_universal.md`; never author per-character 1P.)
5. **Register `can_wield`, icons, loc, rarity** as CWV does.

Read **`../character_weapon_variants/RECIPES.md`** (decision tree + per-archetype
recipes — A1 single 1H melee and A2 2H melee are the closest fits for most
enemy weapons) and **`../character_weapon_variants/DEVELOPMENT.md`** (template
clone, scale/grip, custom-mesh, known errors). The recipe steps transfer
verbatim; only the mesh source differs.

### First gotchas (enemy meshes specifically)

- **No `_3p` sibling.** Player weapons rely on `gear_utils.lua` deriving the 3P
  unit by appending `_3p` to `right_hand_unit`. Enemy meshes under
  `units/weapons/enemy/...` are a **single model with no `_3p` variant** (enemies
  have no first-person view). Confirm whether the engine's `_3p` append finds a
  matching enemy 3P unit; if not, expect the 3P-derive path to fail and plan to
  either (a) point both 1P and 3P at the same enemy mesh, or (b) use CWV's
  per-perspective override pattern (RECIPES.md Recipe D1) which already handles
  "no separate 3P unit." **Verify in-game — this is the most likely first crash.**

- **Different attachment rig.** Enemy meshes attach via
  `AttachmentNodeLinking.ai_1h_weapon.right` (`j_rightweaponattach` /
  `j_leftweaponattach`) on an enemy skeleton, NOT the player weapon attach
  system. The player `template` you clone supplies the player-side attach, so
  the mesh rides the player's hand node — but grip offset / scale / rotation
  will almost certainly need tuning (enemy meshes are sized and origin-set for
  enemy skeletons). CWV's `_type_transforms` / scale+grip-offset machinery is
  the tool; apply on the **3P units only** (`feedback_cross_char_transforms_3p_only`).

- **Package loading.** Enemy weapon units load when the relevant enemies spawn
  in a mission, but they are **not** guaranteed loaded in the keep or in a
  mission that doesn't spawn that faction. A player equipping a beastman weapon
  in a skaven-only mission may hit a missing-package crash. Either declare the
  enemy unit as a static dependency in
  `resource_packages/weapons_of_chaos/weapons_of_chaos.package` (add a
  `unit = [ ... ]` block) or force-load via `Managers.package` per the
  `reference_vt2_package_load_needs_package_not_unit_path` memory and CWV's
  Tuskgor Javelin precedent. **Force-loading a unit path can throw an async,
  pcall-bypassing "Resource not found" crash — read that memory before doing it.**

> **⚠️ CONFIRMED 2026-06-29 (Blightreaper, v0.1.1-dev) — the keep-trophy diorama
> prop is NOT runtime-loadable as a weapon mesh; it HARD-CRASHED the game.**
> `units/props/inn/hub_trophy/hub_trophy_bogenhafen` has **no standalone
> `.package`**, is **absent from the boot-loaded `resource_packages/dlcs/bogenhafen`
> bundle**, and is **absent from the base keep `resource_packages/levels/inn`
> bundle** (all verified with `vt2_bundle_unpacker list`). The keep-decoration
> system loads it on demand from a package we can't statically depend on. WOC's
> `Managers.package:load("units/props/inn/hub_trophy/hub_trophy_bogenhafen", ...)`
> force-load fatally crashed on keep entry (`StateInGameRunning.on_enter` →
> `_register_blightreaper` → `_ensure_prop_loaded` → `resource_package` C-call →
> fatal that bypasses the surrounding `pcall`; the console log ends mid-frame).
> The SDK build also **refuses** a static `.package` `unit = [...]` dependency on
> it (no source `.unit` to compile). **Conclusion:** to wield this prop you must
> EXTRACT + author a real weapon `.unit` (its own `_3p` sibling + a loadable
> package). Until then WOC's Blightreaper renders the base Empire 1H sword mesh
> (interim, crash-free; fix shipped v0.1.3-dev). General rule for any enemy/prop
> mesh: **never `Managers.package:load` a unit path** — only ever load a real
> `.package` NAME you've verified contains the unit.

- **No first-person mesh authored.** Enemy weapons have no 1P-specific mesh. The
  player base weapon's `template` will still try to render a 1P weapon; pointing
  1P at the enemy mesh means the player sees the enemy model in first person
  (often fine, but it was authored at enemy scale/origin — expect grip tuning).

---

## 5. Reference index

- **`src/scripts/settings/ai_inventory_templates.lua`** — enemy weapon mesh
  catalog (`items.<key>.unit_name`). The source of every `.unit` in §1.
- **`src/scripts/settings/trophies.lua`** — keep display props
  (`Trophies.hub_trophy_*`, statues — NOT wieldable).
- **`src/scripts/settings/equipment/item_master_list_exported.lua`** — player
  weapon item shape (clone target). DLC weapons in the sibling
  `item_master_list_*.lua` files.
- **`src/scripts/settings/breeds/breed_*.lua`** — `default_inventory_template`
  per breed (maps a boss/enemy → which enemy weapon mesh it carries).
- **`../character_weapon_variants/RECIPES.md`** + **`.../DEVELOPMENT.md`** — the
  duplicate-weapon / variant-creation pattern this mod follows.
- Repo memory: `feedback_1p_animations_universal`,
  `feedback_cross_char_transforms_3p_only`,
  `reference_vt2_package_load_needs_package_not_unit_path`,
  `reference_vt2_la_package_force_load_crash`.
