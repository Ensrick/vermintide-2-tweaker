# Multi-Mount Weapons — Inventory & Picker Design

**Goal.** Identify every VT2 weapon that has two or more independently-skinnable
visual units (right-hand body + left-hand body), and design how the existing
"offhand picker" in `cosmetics_tweaker` should be generalized to let the user
pick each mount's mesh independently.

The existing picker (lines 1488 ff. in
`cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua`) only
overrides `result.left_hand_unit` in the `BackendUtils.get_item_units` hook. It
was authored for sword+shield where the SHIELD is the visually-secondary item
and the player only customizes the shield. Several vanilla item_types break
that assumption — most notably Saltzpyre's rapier+pistol
(`item_type = "wh_fencing_sword"`, NOT `es_2h_rapier_pistol` as the task
brief assumed — see vanilla `ItemMasterList.vs_wh_fencing_sword` in
`scripts/settings/equipment/item_master_list_carousel.lua:1854`), where the
user might want to either (a) keep the bundled themed rapier+pistol set
visible together, or (b) pick the rapier model and the pistol model from
separate pools.

---

## 1. Inventory — Multi-Mount Weapons

Source-of-truth for "this template has two visible mounts":
`scripts/settings/equipment/weapon_skins.lua` (+ DLC siblings
`weapon_skins_paperweight.lua` and `weapon_skins_lake.lua`). A skin entry that
sets BOTH `right_hand_unit` and `left_hand_unit` (and where the units are
real player weapon meshes, not procedural projectile-spawners like
`wpn_fireball` or quivers) marks the parent template as multi-mount.

### Multi-mount weapons (mounts are independently meshed)

| `item_type` | Careers (`can_wield`) | Mount A (slot = right_hand_unit) | Mount B (slot = left_hand_unit) | Currently handled by offhand picker? | Suggested picker rows |
|---|---|---|---|---|---|
| **Shield weapons (sword/mace/axe/hammer/flail/spear + shield)** — already covered | | | | | |
| `es_1h_sword_shield` | `es_mercenary`, `es_huntsman`, `es_knight`, `es_questingknight`, `es_engineer` (kruber) | sword (~20 variants across `wh_1h_sword_skins` etc.) | empire/GK/deus shield (~12 in `_offhand_options.es_1h_sword_shield`) | YES — left picker (12 vanilla shields + LA pool) | 1 (left) |
| `es_1h_mace_shield` | kruber careers | mace (`one_handed_hammer_template_2`) | empire/GK shield (aliased `_shallow_copy`) | YES | 1 (left) |
| `es_1h_sword_shield_breton` | `es_questingknight` (Grail Knight) | GK sword (`one_handed_sword_shield_template_2` skins, `weapon_skins_lake.lua`) | GK shield (8 variants, lake DLC) | YES | 1 (left) |
| `es_deus_01` | kruber (Chaos Wastes deus melee) | sword | deus shield | YES | 1 (left) |
| `dr_1h_axe_shield` | bardin careers | axe (~5 variants `dr_1h_axe_skins`) | dwarf shield (~8 in pool) | YES | 1 (left) |
| `dr_1h_hammer_shield` | bardin careers | hammer | dwarf shield (aliased) | YES | 1 (left) |
| `wh_flail_shield` | saltzpyre careers | flail | WP shield (3 vanilla) | YES | 1 (left) |
| `wh_hammer_shield` | saltzpyre careers | hammer | WP shield (aliased) | YES | 1 (left) |
| `we_1h_spears_shield` (item_type for Bardin OE shield-spear too? — see note) | wood elf (Sister of the Thorn lookalike) | spear (`one_handed_spears_shield_template`) | elven shield (2 variants) | YES | 1 (left) |
| **Asymmetric dual-wields — already covered for the LEFT-hand pick only** | | | | | |
| `ww_sword_and_dagger` (`we_1h_sword_dagger`) | `we_waystalker`, `we_shade`, `we_handmaiden`, `we_thornsister` | sword (`we_one_hand_sword_skins`, ~6 variants) | dagger (`we_dual_wield_sword_dagger_skins` → `left_hand_unit`, ~10 variants) | YES — LEFT only (dagger). RIGHT (sword) is fixed to whatever the equipped illusion bundles. | 2 (right + left) — currently 1 |
| `wh_dual_wield_axe_falchion` | `wh_bountyhunter`, `wh_captain`, `wh_zealot` | axe (right; `wh_1h_axe_skins` borrowed) | falchion (left; `wh_1h_falchion_skins` borrowed per `_DUAL_WIELD_POOLS`) | YES — LEFT only (falchion). | 2 (right + left) — currently 1 |
| `es_dual_wield_hammer_sword` | `es_mercenary`, `es_huntsman`, `es_knight` | mace (`es_1h_mace_skins`? — actually right=`wpn_emp_mace_04_t2`, no native skin table) | sword (left; `es_1h_sword_skins` borrowed) | YES — LEFT only (sword). | 2 (right + left) — currently 1 |
| **Asymmetric exotic — NOT covered yet (the user's reported gap)** | | | | | |
| `wh_fencing_sword` (rapier + pistol) | `wh_bountyhunter`, `wh_captain`, `wh_zealot` | rapier — `right_hand_unit` walks `wh_fencing_sword_skins` (`wpn_fencingsword_01_t1` … `wpn_fencingsword_t1`, ~10 variants) | pistol — `left_hand_unit` walks the same skins (`wpn_emp_pistol_01_t1`, `_02_t1`, `_02_t2`, `_02_t2_runed_01`, `_03_t1`, `_03_t2`, `_03_t2_runed_01`, ~6 distinct) | **NO** — not in `_offhand_options`. Picker doesn't even render today. | 2 (right + left) |
| **Symmetric dual-wields — same mesh in both hands per skin** | | | | | |
| `wh_brace_of_pisols` (sic — vanilla typo) | `wh_bountyhunter`, `wh_captain`, `wh_zealot` | pistol R | pistol L (same unit as R in every vanilla skin) | NO — not in `_offhand_options` | 2 (right + left) so user can mix |
| `dr_drakefire_pistols` (`brace_of_drakefirepistols_template_1`) | `dr_ironbreaker`, `dr_ranger`, `dr_slayer`, `dr_engineer` | drake pistol R | drake pistol L (same) | NO | 2 |
| `ww_dual_swords` (`dual_wield_swords_template_1`) | wood elf careers | elf sword R | elf sword L (same) | NO | 2 |
| `ww_dual_daggers` (`we_1h_dual_daggers` / `we_dual_wield_daggers`) | wood elf careers | elf dagger R | elf dagger L (same per skin) | YES — but picker treats it as "swap LEFT from full dagger pool"; RIGHT not pickable. | 2 (right + left) — currently 1 |
| `dr_dual_axes` (`dual_wield_axes_template_1`) | bardin | dwarf axe R | dwarf axe L (same) | YES — LEFT only. | 2 — currently 1 |
| `dr_dual_wield_hammers` (`dual_wield_axe_falchion_template` — confusingly named template) | bardin | dwarf hammer R | dwarf hammer L (same) | YES — LEFT only. | 2 — currently 1 |
| `wh_dual_hammer` (Saltzpyre WP twin hammers) | `wh_priest`, `wh_zealot` | `wpn_wh_1h_hammer_01` (sole variant) | same (sole variant) | NO — single unit, no skin variants exist | 0 (excluded — pool size 1) |

**Total multi-mount item_types: 19**.
Of these, 8 are currently handled fully (sword+shield family). 5 are partially
handled (dual-wields where only the left hand is exposed). 6 are completely
unhandled (rapier+pistol, brace_of_pistols, drakefire_pistols, ww_dual_swords,
and the redundant cases below). Excluding the no-skin-variant case
`wh_dual_hammer` leaves 18 viable.

### Confirmed-excluded (NOT multi-mount in the meaningful sense)

| Template | Reason |
|---|---|
| All bows (`longbow_template_1`, `longbow_empire_template`, `shortbow_template_1`, `shortbow_hagbane_template_1`) | Bow body is `left_hand_unit` only. Arrows are procedural `ammo_unit` (quiver/arrow VFX), not wieldable mesh. |
| All crossbows (`crossbow_template_1`, `repeating_crossbow_template_1`, `repeating_crossbow_elf_template`) | Same as bows — crossbow body in `left_hand_unit`, bolt is `ammo_unit`. |
| All staves (`staff_flamethrower_template`, `staff_blast_beam_template_1`, `staff_fireball_*`, `staff_spark_spear_template_1`, `staff_necromancy`, etc.) | `left_hand_unit = "units/weapons/player/wpn_fireball/wpn_fireball"` is the SAME procedural VFX spawn unit across every staff skin. Not a wieldable variant. |
| `es_handgun`, `es_repeating_handgun`, `dr_handgun`, `es_blunderbuss`, `dr_grudgeraker`, `wh_repeating_pistol`, `dr_drakegun`, `dr_steam_pistol` (and other single-mount ranged) | Template `left_hand_unit = ""`; skin entries set only `right_hand_unit` (the weapon body). No second wieldable mount. |
| `es_bastard_sword` (`bastard_sword_template`, lake DLC) | Verified single-mount (skins set only `right_hand_unit`). |
| `wh_dual_hammer` | Both hands use the same `wpn_wh_1h_hammer_01` mesh; no skin variants in any DLC. Pool would be size 1. |

### Off-canvas / out-of-scope

- **CWV variants** (character_weapon_variants mod). Each CWV variant has its
  own `item_type` (`cwv_*` prefix). The picker hook keys on the BASE
  template's `item_type`. The recommendation in §4 covers this.
- **Career-skill weapons** (`*_career_skill.lua` templates,
  `victor_bountyhunter_career_skill.lua` etc.). Some have a `left_hand_unit`
  set (probe weapon, magic ball, etc.) but they're not user-skinnable.
- **Necromancer skeletons** (`bw_necromancy_staff`) — single staff mount,
  skeletons are AI units, not held meshes.
- **Belakor crystal, healing draught, grenades, potions, statues, sacks,
  flags, barrels, beer bottles** — non-melee/non-ranged "weapons" that hold
  the `left_hand_unit` field for engine reasons but have no skinnable
  alternatives.

---

## 2. Architecture Proposal (recommended path)

**Extend the existing `_offhand_options` / `_offhand_selection` infrastructure
with a per-mount dimension. Keep ONE picker mechanism; add row-1 (right hand)
above the current row (left hand) when the item_type is in the new
`_MULTI_MOUNT_ITEM_TYPES` set.**

Rationale:
1. `_offhand_selection` is already keyed by `backend_id` (per-weapon-instance,
   not per item_type). Adding a sub-key for `hand_field` ("right_hand_unit" /
   "left_hand_unit") is a one-line schema change and the existing preload /
   network sync / persistence-stash logic all still applies — only the
   override site (`result.left_hand_unit = override_unit`) needs to learn to
   write the matching field per selection.
2. Parallel pickers (a separate `_mount_options` system) would duplicate
   widget creation, hotspot handling, husk-mesh-swap probes, LA-bridge merge,
   and the `cos_la_apply` RPC payload. The shipped offhand picker already has
   ~600 lines of edge-case fixes (preview-cycle backend_id fallback, husk
   wield gates, package preload races, deferred LA-emit drain). Forking it
   to add row-1 would re-burn those fixes.
3. The user's mental model is "pick what each hand holds" — a single picker
   surface with two rows (labeled "Right Hand" / "Left Hand") matches that
   directly.

**Schema (existing → new):**

```
-- Existing:
_offhand_selection[backend_id] = { name=..., unit=..., rarity=... }

-- New:
_offhand_selection[backend_id] = {
    right_hand_unit = { name=..., unit=..., rarity=... },  -- nil if not picked
    left_hand_unit  = { name=..., unit=..., rarity=... },
}
```

A migration shim in `_setup_illusions` and `_ct_on_offhand_pressed` reads the
legacy table (a flat option table) and treats it as `left_hand_unit` to keep
saves and in-session state working.

---

## 3. Required Code Changes (file-by-file)

### `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua`

**Data model (~line 1636).**

1. Add a `_MULTI_MOUNT_ITEM_TYPES` set listing the item_types that need a
   second (right-hand) picker row:
   - `wh_fencing_sword` (rapier + pistol)
   - `wh_brace_of_pisols` (pistol pair)
   - `dr_drakefire_pistols` (drakefire pair)
   - `ww_dual_swords` (elf sword pair)
   - `ww_dual_daggers` (already partially covered — promote to 2-row)
   - `ww_sword_and_dagger` (sword + dagger)
   - `dr_dual_axes` (dwarf axe pair — promote)
   - `dr_dual_wield_hammers` (dwarf hammer pair — promote)
   - `es_dual_wield_hammer_sword` (mace + sword — promote)
   - `wh_dual_wield_axe_falchion` (axe + falchion — promote)

2. Generalize `_DUAL_WIELD_POOLS` (line ~1729) into a per-hand spec.
   Currently each item_type maps to ONE `{skin_table, unit_field}`. New
   shape: each item_type maps to a per-hand table, e.g.:
   ```
   wh_fencing_sword = {
       right_hand_unit = { skin_table = "wh_fencing_sword_skins", unit_field = "right_hand_unit" },
       left_hand_unit  = { skin_table = "wh_fencing_sword_skins", unit_field = "left_hand_unit"  },
   },
   ```
   `_build_offhand_options_from_skin_table` already takes `unit_field` as
   an arg (line 1757), so it works as-is.

3. Refactor `_offhand_options` storage from
   `_offhand_options[item_type] = {opt, opt, …}` to
   `_offhand_options[item_type][hand_field] = {opt, opt, …}`. Shield
   weapons (single picker row) just store everything under
   `left_hand_unit`, so the migration is a one-line reshape:
   `_offhand_options[item_type] = { left_hand_unit = oldArray }`.

**UI widget creation (~line 2227-2253).**

4. In the `for i, opt in ipairs(options) do` widget loop, gate ON the new
   per-hand structure. The picker should render TWO rows if both
   `right_hand_unit` and `left_hand_unit` pools are present, ONE row
   otherwise. Each widget already stores `widget.content.skin_key =
   "__offhand_" .. i` — extend to `"__offhand_<hand>_<i>"` (`<hand>` =
   `r` or `l`) so the hotspot dispatcher knows which hand it's setting.

5. Place row 1 (right hand, if present) ABOVE the existing offhand_y
   (~95 px) and row 2 (left hand) at the existing position. Add a small
   `_ct_offhand_row_label_widget_right` / `_left` text widget per row
   labeled "Right Hand" / "Left Hand" so the user doesn't have to guess.

**Hotspot dispatch (~line 2370 `_ct_on_offhand_pressed`).**

6. Extend the function signature to `_ct_on_offhand_pressed(self, hand,
   index)`. Read `_offhand_options[item_type][hand][index]` and write to
   `_offhand_selection[backend_id][hand]` (new sub-key shape).

**Override site (~line 2737).**

7. Replace the single `result.left_hand_unit = override_unit` write with:
   ```
   local sel = effective_backend_id and _offhand_selection[effective_backend_id]
   if sel then
       for hand_field, opt in pairs(sel) do  -- "right_hand_unit", "left_hand_unit"
           local unit = opt.unit or opt.intended_unit
           if unit and _override_package_ready(unit) then
               result[hand_field] = unit
           end
       end
   end
   ```
   The hard-coded `left_hand_unit` write is the only behavioral block.

**Husk-mesh-swap probe (~line 2602-2654).**

8. The LA husk-mesh-swap branch also hard-codes `result.left_hand_unit =
   la_unit`. If the user's selection was for right hand, mirror to the
   right field instead. Read the `hand_field` from the
   `_la_equips_by_peer[wearer_peer][slot_name]` cache entry — that's
   where the host's selection was recorded.

**Network sync (~line 4365-4378).**

9. `_la_equips_by_peer[wearer_peer][slot_name]` currently stores
   `{kind, armoury_key, vanilla_key}`. Add `hand_field` to it. Extend
   the `cos_la_apply` RPC payload (line 4371) to include `hand_field`,
   and the receiver (line ~4500 `_apply_la_offhand_to_units` and the
   broadcast cache write at ~4365) to honor it. RPC string-size cap
   (`VMF_RECIPES.md § VMF RPC string cap = 500`) is not a risk
   — adding one short string field per equip is well under cap.

**Preload (`_force_load_all_offhand_packages`, line ~2137-2174).**

10. Walk both rows of every multi-mount pool. The current loop iterates
    `for _wkey, pool in pairs(_offhand_options)` over a flat array; under
    the new shape it iterates `for _wkey, hand_pools in pairs(_offhand_options)`
    then `for _hand, pool in pairs(hand_pools)`. The `_preload_offhand_package`
    call is the same.

**Auto-select on screen entry (~line 2274-2326).**

11. The auto-select block reads `item_data.left_hand_unit` to figure out
    which existing pool entry to mark `is_selected`. Extend to read both
    `item_data.right_hand_unit` and `item_data.left_hand_unit`, match
    each against the corresponding pool, and mark both as selected.
    Without this the user has to re-click the picker every time they
    open the customization screen for a fresh item.

**Persistence.**

12. Currently `_offhand_selection` is in-memory only (line 1835 comment:
    "In-memory only this round; disk persistence via mod settings is a
    follow-up."). NOT a blocker for this work — but if/when persistence
    is added, the per-hand structure serializes cleanly to cjson with no
    schema decisions to make beyond "store a `{ right_hand_unit = {...},
    left_hand_unit = {...} }` table per backend_id."

### `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua`

13. `M.la_offhand_options_by_weapon_type[weapon_type] = list` (line 41,
    384, 510) is keyed by weapon_type with a flat array. Promote to
    `M.la_offhand_options_by_weapon_type[weapon_type][hand_field] = list`.
    LA today only ships shield + bow variants, both of which slot into
    `left_hand_unit`, so the migration just nests the existing
    populator output under `["left_hand_unit"]`. If LA later ships a
    pistol skin (unlikely; see §4 edge cases), it would slot under
    `["right_hand_unit"]` or `["left_hand_unit"]` per its own
    `swap_hand` field.

### `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker_localization.lua`

14. Add two new strings for the picker row labels: `ct_picker_right_hand`
    ("Right Hand") and `ct_picker_left_hand` ("Left Hand"). Used by the
    label widgets added in step 5.

### `cosmetics_tweaker_data.lua`

No changes — the multi-mount behavior should be ON by default for users
who already have the offhand picker. (If gating is desired add a single
"Enable second-hand picker for dual-wields and rapier+pistol" toggle, but
the existing single-row picker is already opt-in by virtue of opening the
customization screen.)

---

## 4. Edge Cases / Risk Catalogue

### a. Bundled "themed set" skins

Many fencing_sword skins ship a matching pair (e.g. `wh_fencing_sword_skin_01`
bundles `wpn_fencingsword_01_t1` + `wpn_emp_pistol_01_t1`; the runed variants
bundle the runed rapier with the runed pistol). When the player picks "skin
X" via the vanilla illusion picker, both pair-members swap together.

**Decision:** the multi-mount picker should ADD options on top, not REPLACE
the bundled set. Concretely: when the user opens the customization screen
the right-hand pool is populated by enumerating
`wh_fencing_sword_skins → right_hand_unit` across rarity tiers (de-dup'd),
the left-hand pool by `→ left_hand_unit` similarly. Auto-select marks the
units matching the equipped illusion as selected; the user can then change
one independently and the other stays bundled.

This is consistent with the existing shield picker's behavior (you can pick
a GK shield on top of an empire-shield-bundled illusion).

### b. LA pistol / non-shield offhand skins

LA today ships shield meshes + shield textures (and recently bows). No
pistol mesh exists in LA's `SKIN_LIST`. Three forward-looking notes:

- If LA later adds a pistol mesh with `swap_hand = "left_hand_unit"` (or
  `right_hand_unit`), the proposed `M.la_offhand_options_by_weapon_type[wt][hand_field]`
  populator handles it without further changes.
- LA-paint variants (texture-only, no mesh swap) work per-mount as long as
  the target unit accepts the LA material. The painter pipeline already
  uses the resolved per-hand `unit_name` from `LootItemUnitPreviewer.spawn_units`
  (line ~3860), not a hard-coded left assumption.
- LA's `swap_hand = "right_hand_unit"` is already a code-path in
  `_la_bridge.lua` (line 232, 265 — already handles bows). The existing
  parser is fine; what changes is the consumer (the picker) honoring the
  field.

### c. Husk / multiplayer sync

`BackendUtils.get_item_units` runs on the OWNING peer for local-player
spawns and on the LOCAL peer for husk wields (via `_wield_slot` hook in
`_tpe.lua`). The override write happens locally on each peer. Today the
LA husk-mesh-swap branch overrides `left_hand_unit` only. After step 7-8,
both fields get overridden per the receiver-side cached `hand_field`.

Vanilla mounts (the new path for fencing_sword right-hand) DON'T need
network sync at all — the override is a function of the locally-picked
selection and the locally-known IML data. Each peer independently
resolves the same unit path from the same `_offhand_selection` storage
write that the LA bridge already broadcasts via `cos_la_apply`. The
broadcast carries `armoury_key` (or `vanilla_key`) which the receiver
turns into a unit path locally. No new RPC type required.

ONE caveat: the broadcast currently doesn't fire for VANILLA offhand
picks (only LA), per `_send_la_apply` gating. If multi-mount picks are
intended to propagate to peers, a parallel `cos_offhand_apply` (or
extending `cos_la_apply` to carry `kind = "vanilla_offhand"`) is needed.
Existing comment at line 2585 says vanilla selections are local-only by
design. Recommendation: keep vanilla picks local-only for v1 (matches
shipped behavior); broadcast can be added later without schema churn
because each peer's `_offhand_selection` is private.

### d. CWV variants (character_weapon_variants)

CWV variants share the BASE template's `item_type` only when the variant
explicitly inherits it; the CWV recipe in
`character_weapon_variants/RECIPES.md` calls out `cwv_variant = true` plus
a sibling-mod gate. For rapier+pistol CWV variants (e.g. a hypothetical
`cwv_es_outrider_fencing_sword`), the picker auto-applies because the
hook keys on `item_data.item_type` after resolving via `matching_item_key`
(line 2712-2716). No extra work needed PROVIDED the CWV variant keeps
the base `item_type` ("wh_fencing_sword") — which the CWV doctrine
already enforces.

### e. Symmetric dual-wields with one shared pool

For `wh_brace_of_pisols`, `dr_drakefire_pistols`, `ww_dual_swords`,
`dr_dual_axes`, `ww_dual_daggers`: every vanilla skin sets BOTH hands to
the SAME unit. The picker can show two rows with the same pool, letting
the user mix (e.g. pistol_01_t1 in right hand, pistol_02_t2_runed_01 in
left hand). This is genuinely new visual capability not available in
vanilla — the user can have a mismatched brace of pistols.

Risk: the engine animates both hands assuming they're the same model.
Mismatched brace SHOULD work (the rig fires both anchors regardless),
but visual artifacts on reload animations are possible if the two
pistols have different barrel lengths or grip nodes. Same risk class as
the existing shield-mismatch case; verify in-game before shipping.

### f. Asymmetric dual-wields with mixed pools

For `ww_sword_and_dagger`, `wh_dual_wield_axe_falchion`,
`es_dual_wield_hammer_sword`: the right-hand pool is a different weapon
KIND from the left. The user can pick from sword variants in right,
dagger variants in left. The current LEFT-only picker already exposes
the smaller hand's pool. Adding a RIGHT row exposes the bigger hand's
pool. Both walk the borrowed single-hand skin table per `_DUAL_WIELD_POOLS`.

### g. Animation grip / left-hand offset mismatch

Some skins ship `action_anim_overrides = { animation_variation_id = X }`
to tweak grip animations for that skin (see fencing_sword skin entries
at ~line 825 in weapon_skins.lua — most use `animation_variation_id = 0`).
The picker bypasses skin selection and overrides the unit directly, so
the equipped illusion's `animation_variation_id` is used as-is. If the
override unit's grip differs significantly from the bundled mate, the
hand attachment node may look slightly off. Same risk as the existing
shield picker; rate as low.

### h. Hot-reload safety

`feedback_hot_reload_unfixable.md`: cosmetics_tweaker is NOT hot-reload
safe. After landing the change, restart the game for testing — Ctrl+Shift+R
will crash because `BackendUtils.get_item_units` is hooked.

### i. Preload cost

`_force_load_all_offhand_packages` (line 2137) currently preloads ~20
unique shield + LA-shield + LA-bow units. Adding the new pools roughly
doubles that count (each dual-wield template adds 6-10 distinct unit
paths). Memory cost: each `Managers.package:load` of a weapon unit is
~1-5 MB resident; the existing preload set is already ~50-100 MB and
the engine handles it. Add ~50 MB for the new pools. Within budget for
the 1080p / 1440p test rigs the team uses; document in CHANGELOG.

---

## 5. Out-of-Scope Confirmations

- **Bows + arrows**: arrow is procedural `ammo_unit`. Confirmed excluded.
- **Crossbows + bolts**: bolt is procedural `ammo_unit`. Confirmed excluded.
- **Staves + fireballs**: `wpn_fireball` is a single VFX-only spawn unit
  shared across every staff skin. Not user-skinnable. Confirmed excluded.
- **`wh_dual_hammer`**: pool size 1 (only `wpn_wh_1h_hammer_01`); picker
  would be a dead row. Confirmed excluded.
- **Necromancer skeletons / utility spell weapons**: AI units, not held
  meshes. Confirmed excluded.
- **Career-skill weapons / grenades / potions / barrels / sacks / flags /
  belakor crystal / healing draught**: not user-skinnable. Confirmed
  excluded.

### Ambiguous cases for user adjudication

1. **`bw_staff_*` (BW staves)** — the user might want a "decorative
   left-hand fireball ornament" picker. Vanilla ships exactly one
   `wpn_fireball` unit; there is nothing to pick from. Leave excluded
   unless a custom unit is authored.
2. **`dr_drakefire_pistols`** — the brace mechanically fires from BOTH
   hands but the recoil animation reads as a single weapon. Whether the
   second pistol's mesh actually renders in-game during firing should
   be verified — if the engine swaps to a single-pistol firing pose,
   the picker for the "unfired" hand is decorative only. Same caveat as
   `wh_brace_of_pisols`.
3. **`wh_dual_hammer`** — confirmed pool size 1. Should the picker
   render an empty disabled row, or be omitted entirely? Recommend
   omit (the existing `if not options or #options == 0 then return`
   guard at line 2215 already drops it).
4. **`es_2h_rapier_pistol`** — the task brief referenced this name; the
   vanilla item_type is `wh_fencing_sword` and it's SALTZPYRE's weapon,
   not Kruber's. The brief may have meant Saltzpyre, or there may be a
   CWV variant the user is thinking of. Recommend confirming with user.

---

## File path citations

Vanilla source:
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\settings\equipment\weapon_skins.lua`
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\settings\equipment\weapon_skins_paperweight.lua`
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\settings\equipment\weapon_skins_lake.lua`
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\settings\equipment\weapon_skins_scorpion.lua`
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\settings\equipment\weapon_templates\fencing_swords.lua`
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\settings\equipment\weapon_templates\brace_of_pistols.lua`
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\settings\equipment\weapon_templates\brace_of_drake_pistols.lua`
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\settings\equipment\weapon_templates\dual_wield_*.lua` (all 7 variants)
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\settings\equipment\item_master_list_carousel.lua` (`vs_wh_fencing_sword`, `vs_wh_dual_hammer`, etc.)

Mod source (touched by this design):
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\scripts\mods\cosmetics_tweaker\cosmetics_tweaker.lua` (lines 1488-1822, 2192-2470, 2595-2776, 4365-4378)
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\scripts\mods\cosmetics_tweaker\_la_bridge.lua` (lines 34-510)
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\scripts\mods\cosmetics_tweaker\cosmetics_tweaker_localization.lua` (two new strings)

Reference docs (this repo):
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\CLAUDE.md` — Three Weapon Rendering Paths, hot-reload constraint
- Memory: `reference_la_offhand_paint.md`, `reference_la_hat_kind_texture.md`,
  `reference_ct_husk_hook_shadow_tpe.md`, `reference_ct_offhand_force_preload.md`,
  `reference_vmf_rpc_string_cap.md`
