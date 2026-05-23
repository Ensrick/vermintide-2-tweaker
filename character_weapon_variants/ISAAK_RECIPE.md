# Lessons from Peregrinaje for 3P Animation Remapping (CWV Reference)

A learning-reference doc, NOT a migration target. Reads Isaak's Peregrinaje
mod source for what it teaches about 3P-side animation discipline, then
applies those lessons to CWV's intentionally cross-character moveset
porting. Source file referenced throughout:
`_peregrinaje_extract/named/scripts/mods/Peregrinaje/tweaks/new_weapons.lua`.

---

## TL;DR

CWV's whole reason for existing is cross-character moveset porting:
giving Kruber Sienna's 2H mace moveset, giving Bardin Saltzpyre's priest
1H moveset, giving Kruber Kerillian's dual swords. The 1P side just
works (the `first_person_base` unit is universal across characters). The
3P body is where the work lives — receiver Y's 3P skeleton has its own
authored event vocabulary, and the source weapon X's `anim_event` strings
have to be remapped onto a "good enough" subset of Y's native vocabulary
to make the body look natural to other players in the lobby.

Isaak's Peregrinaje mod is the best in-the-wild reference for that
remap discipline. We learn its technique. We do NOT copy its
architecture — Isaak's mod has a strictly narrower scope than CWV.

---

## What Isaak's mod actually does

Peregrinaje adds NEW WEAPON ITEMS that the receiver wields with the
receiver's own native moveset. Markus gets a torch+shield using Markus's
own native 1H sword+shield template. Bardin gets a torch+shield using
Bardin's own native 1H axe+shield template. Kerillian gets a torch+shield
using Kerillian's own native 1H spear+shield template.

Every Peregrinaje variant pattern at lines 123-145 / 363-385 / 434-456
follows the same shape:

```lua
-- Markus' torch+shield (line 123): clones from a MARKUS-NATIVE template
local entry = table.clone(ItemMasterList.es_sword_shield)
```

```lua
-- Bardin's torch+shield (line 363): clones from a BARDIN-NATIVE template
local entry = table.clone(ItemMasterList.dr_shield_axe)
```

```lua
-- Kerillian's torch+shield (line 434): clones from a KERILLIAN-NATIVE template
local entry = table.clone(ItemMasterList.we_1h_spears_shield)
```

So Peregrinaje's design is "same-character new item." The donor concept
(a torch instead of a sword) is purely a visual swap on the right hand;
the moveset, state machine, wield pose, and 3P body all come from the
receiver's native template chain. Three separate masterlist clones, one
per receiver, each rooted in that receiver's own kit.

This is a strict subset of what CWV does.

---

## What CWV does that Isaak doesn't

CWV deliberately ships variants whose `base_weapon` is a DIFFERENT
character's vanilla weapon, then makes the receiver wield it. Examples
from `character_weapon_variants.lua`:

- `cwv_es_maul` (line 558) — Kruber wielding Sienna's 2H mace
  (`base_weapon = "bw_1h_mace"`, which is display-2H). Bringing Sienna's
  2H mace moveset and feel onto Kruber.
- `cwv_es_priest_greathammer` / `cwv_dr_priest_greathammer` (lines 463,
  483) — Kruber and Bardin wielding Saltzpyre's priest 2H greathammer
  moveset.
- `cwv_es_warpriest_hammer` (line 511) — Kruber wielding the Skullsplitter
  mesh on Saltzpyre's priest 1H hammer template.
- `cwv_es_dual_swords` etc. — Kruber wielding Kerillian's dual swords.

These are not bugs to "fix" toward receiver-native templates. They are
the entire feature: semi-lore-friendly variants that play differently
enough from a receiver's vanilla loadout that they feel like natural
new variants, by bringing another character's moveset onto the receiver.

The Workshop description and design intent are explicit: CWV variants
intentionally cross-character clone so a player who wants
"Kruber-with-Sienna's-mace" or "Kruber-with-Kerillian's-dual-swords"
gets that. Cross-character base templates are the design.

---

## The lessons we learn from Isaak

Isaak's mod is the cleanest reference in the wild for these five
techniques. CWV reuses each:

### a. Closed-vocabulary rule

Every `anim_event` (or `anim_event_3p`) string you write into a 3P
field MUST already exist in the destination 3P state machine's authored
event vocabulary. No skeleton-probe invention; no "this name sounds
plausible." See `[[feedback_anim_closed_vocabulary]]`.

Isaak demonstrates this implicitly: in `bardin_torch_and_shield`
(lines 405-423), he sets `state_machine =
"units/beings/player/first_person_base/state_machines/melee/1h_axe_shield"`
and then every `anim_event` he writes
(`"attack_swing_charge_left_diagonal_pose"`,
`"attack_swing_heavy_down"`, `"attack_swing_down"`) is a string that
exists in the 1h_axe_shield SM's authored vocabulary. He doesn't invent
event names; he picks from what the destination SM already has.

CWV applies the same rule, except the SM in question is the RECEIVER's
native 3P body's vocabulary for whatever wield SM we route into.

### b. NetworkLookup symmetric registration discipline

Both directions of `NetworkLookup.item_template_names`, in order. Lines
403-404 (Bardin) and 474-475 (Kerillian):

```lua
NetworkLookup.item_template_names[#NetworkLookup.item_template_names + 1] = "bardin_torch_and_shield"
NetworkLookup.item_template_names.bardin_torch_and_shield = #NetworkLookup.item_template_names + 1
```

The second line's `+ 1` resolves to the index just written by the first
line. Forgetting either direction means the lookup silently returns nil
in one direction and the engine crashes on the first network sync.

CWV's helpers (`_register_variant_skins`, `_register_custom_illusions`)
follow the same shape with `rawget`/`rawset` because some NetworkLookup
sub-tables have error-throwing `__index` metamethods.

### c. Masterlist field hygiene

Lines 142-145 (Markus):

```lua
entry.item_type             = "markus_torch_and_shield_peregrinaje"
entry.template              = "markus_torch_and_shield"
entry.skin_combination_table = nil
entry.peregrinaje_added     = true
```

Four critical fields:
- `item_type` — groups for the skin-pool + UI; must be unique per
  variant if you want a curated skin pool.
- `template` — links to `Weapons.<key>`; MUST match the table key you
  write into the `Weapons` global.
- `skin_combination_table = nil` — suppresses inherited illusion pool
  unless you curate one.
- `peregrinaje_added = true` — cross-mod marker. CWV equivalent:
  `cwv_variant = true`. Sibling mods (cosmetics_tweaker, weapon_tweaker,
  LA bridges) gate on this so they don't apply unintended logic to mod
  variants.

### d. `table.clone` then mutate only what you need

Don't re-author the whole weapon template; clone and override the
minimum. Markus (line 165) clones the matching same-character 1H sword
shield template and only overrides the units. Bardin (line 405) clones
the already-modified Markus variant (to inherit per-action sound/FX
work) and overrides only what differs.

CWV follows this everywhere. Every `_create_<variant>_template`
function in `character_weapon_variants.lua` starts with
`table.clone(Weapons.<base>, true)` (deep) and walks
`template.actions[*][*]` to rewrite only the fields that genuinely
differ from base.

### e. When `state_machine` on a CWV-OWN template is safe

Isaak's `bardin_torch_and_shield` (line 409) sets `state_machine` on a
brand-new `Weapons.bardin_torch_and_shield` table. This looks like a
violation of "never override `state_machine` per character" but is
NOT — and the distinction matters for CWV.

| Pattern | OK? | Why |
|---|---|---|
| Mutate a SHARED vanilla template's `state_machine` field | NO | Shared template is wielded by multiple careers; changing its SM breaks every native wielder's 1P. |
| Mutate a shared MOD template per-receiver at runtime (hook on equip) | NO | Same outcome — the next wielder gets the previous wielder's SM. |
| Set `state_machine` on a NEW `Weapons.<key>` table that this variant owns | YES | This is a freshly-minted template owned by ONE variant. Its SM is its own contract; nothing else reads or shares it. |

Isaak's line 409 is the third row. He's writing the SM field onto a
brand-new table whose `key`, `item_type`, and `template` all point at
`bardin_torch_and_shield`. The 1P-universal rule was authored against
the first two anti-patterns and does not apply to the third.

CWV does the same on its own template clones — when a variant ships
its own `Weapons.<key>` (via `_create_<variant>_template`), setting
SM-related fields on that clone is the right move; the variant owns
that template.

---

## The 3P remap technique CWV inherits from this reference

When CWV brings source-weapon X's actions to receiver Y, the 3P side
needs an `anim_event_3p` remap onto Y's good-enough native vocabulary.
The procedure:

1. Walk the source weapon X's template `actions[*][*]` and collect
   every distinct `anim_event` string.
2. For each one, decide whether Y's 3P body skeleton has that event
   available — via `Unit.has_animation_event` runtime probe (`/force3p`
   chat command) or a static audit of Y's native templates'
   `anim_event` vocabularies (`/dump_actions`).
3. For events that don't exist on Y's 3P body in the wield SM Y will
   sit in, pick a "functionally similar enough" Y-native string —
   ideally same swing direction, same chain context, same damage shape
   — and write it as `sub_action.anim_event_3p` on the cloned template.
4. Test live with `/animlog` watching for `[MISSING]` warnings during
   the L1/L2/L3/H1/H2/push/push-attack chain. Iterate.

Concrete example (matching the user's intuition):

> Kerillian dual swords on Kruber → mix-and-match Kruber Mace+Sword
> anim events to cover the dual sword action set.

The Kruber Mace+Sword (one_handed_sword_template_1 or dual_hammer_sword
SM) has a well-authored set of light/heavy/push events on Kruber's
empire-soldier 3P body. When porting Kerillian's `dual_wield_swords_template_1`
to Kruber, we route 3P wield via `template.wield_anim_3p =
"to_dual_hammer_sword_es"` and remap per-action events from the elf
vocabulary onto event names that the empire-soldier 3P body has
authored as visible transitions in that SM. The result reads as a
natural dual-sword moveset on Kruber's body to anyone watching him in
the lobby.

For per-3P-body weak-keyed state and per-husk remap, reference
`[[feedback_anim_remap_per_unit_state]]`. For closed-vocabulary
discipline, `[[feedback_anim_closed_vocabulary]]`.

The full nine-step procedure including the BASE-template patch for the
inventory previewer, the chain-pairing rule for heavy-charge / heavy-release
direction, and the `pre_action_anim_event` SM-switch antipattern is in
`ANIMATION_FIX_PLAYBOOK.md`.

---

## What this doc does NOT do

This doc does NOT recommend migrating CWV variants toward
receiver-native base templates. That would erase the feature.

Cross-character base templates (`base_weapon = "bw_1h_mace"` on a
Kruber variant, `base_weapon = "wh_1h_hammer"` on a Bardin variant,
etc.) are the design. A future audit walking the variant catalog and
noting "this clones from another character" is not a list of bugs —
it's an inventory of the intentional cross-character ports.

What CWV variants DO take from Isaak is the discipline that makes
those ports look right on the receiver's 3P body:

- Receiver-native wield SM routing for 3P (`wield_anim_3p`,
  `wield_anim_career_3p`).
- Per-action `anim_event_3p` remap into the receiver's closed
  vocabulary.
- Hand-attachment / unwielded-bone overrides for the receiver's
  skeleton (`AttachmentNodeLinking.one_handed_melee_weapon.right`
  etc., per the `a_unwielded_*` character-specific bone rule in
  `DEVELOPMENT.md`).

The 1P side is universal across characters and needs no work
(`[[feedback_1p_animations_universal]]`).

---

## Cross-references

- `DEFINITION_OF_DONE.md` — every variant authored under this reference
  walks the universal + trait-gated checklists before declaring
  complete. Relevant gates: G-CROSS-CHAR (every cross-character
  variant), G-3P-ANIM (when receiver's body lacks events), G-DUAL,
  G-MESH-FAMILY, G-BLACKSMITH.
- `RECIPES.md` — decision tree for picking an archetype and per-archetype
  copy-paste recipes. This reference complements the recipes; it does
  not replace them.
- `ANIMATION_FIX_PLAYBOOK.md` — full 9-step procedure for the
  per-action remap.
- `DEVELOPMENT.md` — System B template-clone architecture, attachment
  node linking gotchas, BASE template patching for the previewer.
- `[[feedback_1p_animations_universal]]` — the rule that makes 1P side
  automatic.
- `[[feedback_anim_closed_vocabulary]]` — the constraint on remap
  target strings.
- `[[feedback_anim_remap_per_unit_state]]` — per-3P-body weak-keyed
  remap state.
- `[[reference_cwv_blacksmith_template]]` — variant pattern for
  `rarity = "default"` forge-friendly templates.
- `[[feedback_cwv_clone_name_clobber]]` — CWV-specific masterlist
  field-hygiene gotcha (CWV keeps inherited `entry.name`, Isaak
  overrides it).
