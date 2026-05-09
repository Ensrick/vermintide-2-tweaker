# `j_leftweaponattach` crash on `cwv_es_dual_swords` cosmetic picker

**Status: RESOLVED in v0.1.145 (user-confirmed working).**

This document is the post-mortem for a crash that recurred across ~20 versions
(v0.1.122 → v0.1.142) before being fully fixed. It's preserved because the
final root cause was non-obvious and a future change to dual-wield variants
could re-trigger it without this context.

If you're touching `_register_variant_skins`, `_register_kruber_1h_sword_dual_illusions`,
or adding a new cwv dual-wield variant, **read the Resolution and Lessons sections
below before changing display_unit values**.

---

## Resolution (v0.1.145)

`cwv_es_dual_swords` skin entries — both the auto-generated default
(`cwv_es_dual_swords_skin`) and each of the 17 Kruber-1h-sword illusion
clones (`cwv_es_dual_swords_es_1h_sword_skin_*`) — must use:

```lua
display_unit    = "units/weapons/weapon_display/display_dual_weapons"
left_hand_unit  = right_hand_unit  -- both populated, not nil
```

Set on **both** the `WeaponSkins.skins[skin_key]` entry **and** the
`ItemMasterList[skin_key]` entry. The previewer's
`LootItemUnitPreviewer._spawn_link_unit` (`loot_item_unit_previewer.lua:467-477`)
reads `display_unit` from both layers and falls through; setting it on only
one is the v0.1.131 false-negative trap (see Lessons).

`display_dual_weapons` is the rig vanilla `we_dual_sword_skin_*`
(`weapon_skins.lua:5750`/`5764`/`5778`/`5792`) and the `dual_wield_swords_template_1`
(`dual_wield_swords.lua:1497`) use. The vanilla elf-dual-sword cosmetic picker
is a shipped, working game feature — therefore that rig authors
`j_leftweaponattach`. We piggyback on the same rig.

The runtime workarounds added across earlier attempts have all been removed:

- The `_in_loot_previewer_load` thread-local flag (v0.1.142, H4).
- The wrapper hook on `LootItemUnitPreviewer._load_item_units` (v0.1.142).
- The right→left mirror block in the `BackendUtils.get_item_units` hook
  (v0.1.93, originally for default-rarity blacksmith templates; the
  `_kruber_1h_dual_skin_keys` extension was added in ~v0.1.136).

Vanilla `BackendUtils.get_item_units` populates `result.left_hand_unit` from
the skin entry directly — once the entry has the field, no mirror is needed
in any caller (in-game, character preview, cosmetic picker, or forge).

The `_kruber_1h_dual_skin_keys` registry is kept as an inert marker (no
runtime consumer) in case a future hook needs to filter on
`cwv_es_dual_swords` skin lineage. Safe to remove if not used by 6 months
out.

---

## Lessons

### L1 — When changing a `display_unit`, change it on EVERY skin entry, not just the new ones

The v0.1.131 attempt (H2 below) switched the 17 Kruber illusions to
`display_dual_weapons` but left the auto-generated default
`cwv_es_dual_swords_skin` on `display_1h_weapon`. Opening the cosmetic menu
previews the **default skin first**, so the crash hit before any illusion
was clicked. The crash log showed source hash = `display_1h_weapon`, which
matched neither of the two rigs supposedly under test, and the
investigation incorrectly concluded `display_dual_weapons` was also broken.

**Repeatable form of the trap:** if you change a `display_unit` to test a
hypothesis, run a grep for the old value across the entire mod's skin
registration code and confirm zero remaining references — or expect the
test to silently exercise the wrong rig.

### L2 — `display_unit` must be set on BOTH the IML entry AND the WeaponSkins.skins entry

The previewer chain reads from both layers (`loot_item_unit_previewer.lua:467-477`
and `:270` via `BackendUtils.get_item_units`). v0.1.99 → v0.1.103 was a
multi-version bug where setting it on one layer didn't propagate. Same
lesson re-applied for the dual-wield case.

### L3 — A working vanilla feature is strong indirect evidence about the underlying asset

The strongest evidence that `display_dual_weapons` authors `j_leftweaponattach`
was that the vanilla elf-dual-sword cosmetic picker uses the same rig and
is a shipped, working feature. Fatshark would not ship a feature that
crashes the game on every click.

We could have committed to this fix two weeks earlier if we'd reasoned
from the vanilla precedent first. Instead we tested in isolation and got
mistrap'd by L1 (above). When debugging a "this rig is broken"
hypothesis, **first check whether vanilla uses that rig successfully** —
if yes, the rig is fine and the bug is in our usage of it.

### L4 — `BackendUtils.get_item_units` mirror hooks fire for every caller

The `BackendUtils.get_item_units` hook can't distinguish "in-game equip"
from "cosmetic picker" without contextual hacks (thread-local flags,
inspecting the call stack, item_data type discrimination). The cleanest
fix is to populate the underlying skin/IML entries correctly so no
runtime mirror is needed. Mirrors that fire for every caller are
fragile and tend to leak across contexts.

---

## Symptom

Opening the cosmetics-illusion picker on `cwv_es_dual_swords` (Imperial Dual
Swords), or clicking any cosmetic preview thumbnail there, raised:

```
[Script Error]: j_leftweaponattach
```

Reproduced in v0.1.122, v0.1.123, v0.1.128, v0.1.130, v0.1.131, v0.1.132,
v0.1.136, v0.1.138.

## Verified facts (preserved for reference)

### F1 — The crash is from `Unit.node(source, "j_leftweaponattach")`

Stack trace (v0.1.138, GUID `01b5fbdd`):

```
[0] =[C]: in function node
[1] gear_utils.lua:325  link_units
[2] gear_utils.lua:318  link
[3] loot_item_unit_previewer.lua:528  _spawn_items inner
[4] cosmetics_tweaker.lua:2488  hook
[5] character_weapon_variants.lua:3162  hook_chain
[6] vmf/modules/core/hooks.lua:180  spawn_units (via VMF)
[7] loot_item_unit_previewer.lua:494  _spawn_items
[8] loot_item_unit_previewer.lua:229  post_update
```

### F2 — `Unit.node` raises this error format when the named node is absent

The C-API `Unit.node(unit, name)` performs `fassert`-style lookup; the
engine prints `[Script Error]: <node_name>` when the lookup fails.

### F3 — The source unit varied across crashes

Resolved via murmur64 hashing in the unpacker:

| Crash GUID | Source unit hash | Maps to |
| --- | --- | --- |
| `e2d8c912` (v0.1.122) | `75f0aff36a2ed89c` | `display_1h_weapon` |
| `c7722012` (v0.1.131) | `75f0aff36a2ed89c` | `display_1h_weapon` |
| `01b5fbdd` (v0.1.138) | `d2ea17f6a7257076` | `display_1h_swords` |

Reference hashes (computed):

| Path | Hash |
| --- | --- |
| `display_1h_weapon` | `75F0AFF36A2ED89C` |
| `display_1h_swords` | `D2EA17F6A7257076` |
| `display_dual_weapons` | `58AE951DBB4E4944` |
| `display_dual_axes` | `BEE890853ACF8ECA` |
| `display_dual_daggers` | `68B6C218C0619134` |
| `display_dual_hammers` | `8F0BA7749D4F01F7` |
| `dual_wield_axe_falchion` | `DACC2229DD308B2D` |

### F4 — In v0.1.138, the crash hit a Kruber 1h-sword illusion entry

Lua locals from `01b5fbdd`:

- `item_key = "cwv_es_dual_swords_es_1h_sword_skin_04"` — generated illusion.
- `unit_name = "units/weapons/player/wpn_emp_sword_03_t2/wpn_emp_sword_03_t2_3p"` — Kruber 1h sword 3P model.
- `unit_attachment_node_linking[1] = { source = "j_leftweaponattach", target = 0 }`.

The previewer was attaching a left unit even though the skin entry had
`left_hand_unit = nil` since v0.1.136 — F5 explains why.

### F5 — Our `BackendUtils.get_item_units` hook restored `left_hand_unit`

```lua
mod:hook(BackendUtils, "get_item_units", function(func, item_data, backend_id, skin, career_name)
    local result = func(...)
    if resolved_skin and _kruber_1h_dual_skin_keys[resolved_skin] then
        result.left_hand_unit = result.right_hand_unit  -- mirror
    end
    ...
end)
```

This hook fires for **every** caller of `BackendUtils.get_item_units`,
including the cosmetic previewer. The mirror put `left_hand_unit` back on
the result the previewer read, and the previewer then took the
`if left_hand_unit then ... attach left ...` branch.

This was the proximate cause for the v0.1.136+ crashes. Earlier crashes
(v0.1.122–v0.1.132) had different proximate causes — see disproven
hypotheses below.

## Disproven hypotheses (final status)

### H1 — `display_1h_swords` lacks `j_leftweaponattach`, switch to `display_1h_weapon` (v0.1.123)

**Disproven.** v0.1.128 crash had source hash `75f0aff36a2ed89c` = `display_1h_weapon`, same crash. Both rigs are single-sword displays.

### H2 — `display_1h_weapon` lacks the node, switch to `display_dual_weapons` (v0.1.131)

**FALSE NEGATIVE — see L1.** The v0.1.131 crash on `cwv_es_dual_swords_skin` still showed source hash `75f0aff36a2ed89c` = `display_1h_weapon`, NOT `display_dual_weapons`. The auto-generated default skin was still inheriting `display_1h_weapon` because the change only touched `_register_kruber_1h_sword_dual_illusions`, not `_register_variant_skins`. The hypothesis was correct; the test was bad.

### H3 — Drop `left_hand_unit` from skin so previewer's `if left_hand_unit then` skips (v0.1.136)

**Disproven.** Stopped the crash for the default skin's menu-open preview, but the BackendUtils mirror (F5) restored `left_hand_unit` for the illusion clones, so clicking any illusion thumbnail re-triggered the crash (v0.1.138).

### H4 — Gate the BackendUtils mirror behind a `_in_loot_previewer_load` flag (v0.1.142)

**Stopped the crash, with regression.** Cosmetic picker no longer crashed but rendered only one sword. The forge / Athanor preview also lost the second sword (same `LootItemUnitPreviewer` class, same gate). User regression: they expected two swords. Superseded by H5.

### H5 — Switch to `display_dual_weapons` rig + restore `left_hand_unit` on every skin entry (v0.1.145)

**CONFIRMED WORKING.** User tested. Cosmetic picker, Athanor forge preview, in-game equipped weapon, and inventory character preview all show two Kruber swords. No crash on any path.

## Version history

| Version | Approach | Outcome |
| --- | --- | --- |
| 0.1.122 | First Kruber 1h sword cosmetic enumeration; inherited `source.display_unit` | Crash on click (H1) |
| 0.1.123 | Override `display_unit` to `display_1h_weapon` | Crash on click (H1 disproven) |
| 0.1.128 | Drop `left_hand_unit` from skin (no mirror) | Worked for preview but in-game lost left sword |
| 0.1.130 | (mismatch — user version bump beyond change) | Same crash |
| 0.1.131 | Switch to `display_dual_weapons` for illusions only | Crash on menu open (H2 false negative — default skin still using `display_1h_weapon`) |
| 0.1.132 | (further variants tried) | (data lost) |
| 0.1.136 | Drop `left_hand_unit` from BOTH default skin AND illusions, mirror right→left in BackendUtils hook | Menu opens (default skin no crash). Click an illusion → still crashes (H3 disproven) |
| 0.1.138 | Same approach with refinements | Same crash |
| 0.1.142 | Add `_in_loot_previewer_load` gate around BackendUtils mirror | Crash stopped. Regression: cosmetic picker AND forge show only one sword (H4) |
| **0.1.145** | **Switch skins to `display_dual_weapons` rig + restore `left_hand_unit`; remove gate, mirror, and previewer wrapper** | **CONFIRMED WORKING — user tested. Two swords in picker, forge, in-game, character preview.** |
