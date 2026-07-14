# Character Weapon Variants — Development Guide

## Registration and acquisition contract

CWV owns weapon definitions: `ItemMasterList` rows, templates, skins, packages,
and network lookup entries. It must never add a player-owned instance to a
local/backend inventory. Crafting in Modded is the sole acquisition owner: it
mints the backend ID, persists that exact ID, and equips the Primary or
Secondary slot the player chose.

Do not infer ownership from a `cwv_` prefix. A CWV item is owned only when its
exact backend ID exists in CIM's persisted craft table. Migration code may
remove only the finite historical auto-grant IDs derived from authored
`instances` counts; broad prefix or numeric-range deletion is forbidden.

> **Before declaring a variant complete: walk
> `DEFINITION_OF_DONE.md`.** Universal + trait-gated checklists, plus
> the `**DoD:**` footer that every variant CHANGELOG entry must end
> with. This is the gate; the docs below are reference.
>
> **Adding a new variant?** Start with **`RECIPES.md`** — that's the
> procedural how-to (decision tree + per-archetype copy-paste
> recipes). This file is the reference: rarity system, skin system,
> scale system, animation architecture, base-weapon catalog.
> Cross-link from RECIPES.md as needed.
>
> **3P animation work?** See **`ANIMATION_FIX_PLAYBOOK.md`** — the
> 9-step closed-vocabulary procedure. The "Animation: System B" and
> "Animation: cross-access" sections later in this file are the
> architectural reference for that playbook.
>
> **Dual-wield variant?** Read the post-mortem in
> **`J_LEFTWEAPONATTACH_INVESTIGATION.md`** once. It explains why the
> `_force_display_unit` rule exists.

## Design intent — cross-character base templates are the feature

CWV variants intentionally clone from cross-character base templates
to bring other characters' movesets onto receivers (Kruber wielding
Sienna's 2H mace via `bw_1h_mace`, Bardin wielding Saltzpyre's priest
hammer via `wh_1h_hammer`, Kruber wielding Kerillian's dual swords via
`we_dual_wield_swords`, etc.). This is the design, not a bug — the
whole point is semi-lore-friendly variants that play differently
enough from a receiver's vanilla loadout to feel like natural new
weapons.

**User's framing (2026-05-23):**

> "We can still benefit from Isaak. In cases like Kruber using
> Dual-Skullsplitters. They have a different first person wield
> animation. Though they may be functionally the same without my
> toggle for hammers to play different; so I like how in first
> person the regular wield animation looks different even if the
> moveset is the same. It differentiates them. I like how the first
> person animations are working. They work just fine. We're using
> Isaaks' mod to learn how to get 3rd person animations working. The
> character models lack the right state machines to use each other's
> animations, so we improvise by using a native weapon that's just
> good enough."

> "CWV is more about making semi-lore-friendly variants of the
> weapons where possible, that play differently enough that they
> feel like natural new variants."

**What this means in practice:**

- **1P is universal — wielder gets the donor character's 1P feel for
  free.** No remap needed. The `first_person_base` unit is shared
  across all six characters.
- **3P is where we improvise.** Receiver character's body lacks the
  donor's state machine. Pick a "good enough" native weapon's anim
  vocab and remap `anim_event_3p` onto its events so bystanders see
  something plausible. Receiver-appropriate `AttachmentNodeLinking`
  to avoid foreign unwielded bones.
- **The 1P differentiation IS the variant's identity** even when
  moveset and stats are functionally identical to a native. Example:
  Dual-Skullsplitters on Kruber — same moveset as Kruber's mace
  family, but the 1P wield animation is different. Functional
  identity comes later, optionally, via the planned hammer/mace
  toggle (`TODO.md`).

**Canonical CWV cross-character examples:**

- **`warpriest_hammer`** — Skullsplitter mesh on Kruber. Different 1P
  wield from Kruber's native mace family. Mechanically identical
  without the planned hammer-vs-mace toggle.
- **`priest_greathammer`** — Saltzpyre's priest 2H moveset given to
  Kruber/Bardin.
- **`maul`** — Sienna's 2H mace moveset on Kruber.

For these, the 3P body improvises with the closest receiver-native
animation set (Kruber's Mace+Sword for several variants). Bystander
view is "good enough"; the wielder gets the donor's 1P feel.

**Anti-pattern to avoid:** do **not** audit a CWV variant and flag
"this clones from `es_2h_hammer` but the receiver is Sienna — should
clone from `bw_1h_mace`." That recommendation destroys the variant's
whole point. Peregrinaje (`ISAAK_RECIPE.md`) is a learning reference
for 3P remap discipline; it is NOT a migration target. Peregrinaje
clones receiver-native templates (its scope is narrower than CWV's),
which is exactly what CWV deliberately does not do.

### Isaak's Peregrinaje — what to use it for, what NOT to use it for

When studying Isaak's `_peregrinaje_extract/named/scripts/mods/Peregrinaje/tweaks/new_weapons.lua`, his pattern is:

1. Clone from a **receiver-native** base template (the character already owns the moveset).
2. Override individual `anim_event` entries per action, drawing only from that template's existing state-machine vocabulary.

That pattern is **correct for Isaak's scope** — same-character new-weapon creation. It is **wrong for CWV's scope** — intentional cross-character moveset porting.

**Use Isaak's source for:**
- **3P anim_event remap discipline** — picking individual events from a target template's vocabulary.
- **Masterlist field hygiene** — what fields a clean weapon entry needs.
- **Template registration ordering** — when in the boot sequence custom templates have to land.
- **NetworkLookup symmetric registration** — keeping host/client lookup tables in sync.
- **Closed-vocabulary rule** — remap targets must already exist in the target wield-SM template's `anim_event` set; no inventing events. See `ANIMATION_FIX_PLAYBOOK.md` § "Three non-negotiable rules" item 2.

**Do NOT use Isaak's source for:**
- Proposing migrating any CWV variant toward Isaak's receiver-native cloning pattern. Recommendations of the form "switch `maul` to clone `es_2h_hammer` instead of `bw_1h_mace`" or "this variant should clone from a Kruber-native template since the receiver is Kruber" are wrong. They destroy the variant's identity because CWV variants *intentionally* clone cross-character base templates to port the donor's moveset.

**How to apply:** any time a CWV variant clones from a non-receiver-native template, do **not** flag as a defect. Treat as intentional unless the user explicitly says otherwise. If you're unsure why a base template was picked, ask the user — don't propose a "fix."

**Burned 2026-05-23:** audited CWV variants flagging `maul`, `priest_greathammer`, and `warpriest_hammer` as having "wrong" base templates when they were correctly cross-character by design. Cost: one round-trip of misframed migration plan.

## Adding a New Variant Weapon — Quick Index

The full procedural how-to lives in `RECIPES.md`. This section is a
short index pointing back into this file's reference content.

| Question | Where to look |
|---|---|
| What kind of variant am I making? | `RECIPES.md` — Decision tree |
| Which fields go in the def? | `RECIPES.md` — per-archetype recipe |
| What does each rarity tier mean? | This file — Rarity |
| When is `rarity = "default"` correct? | This file — Blacksmith Template Pattern |
| How do skins, illusions, and `display_unit` fit together? | This file — Skin System |
| How do we import, package, preview, network, and verify custom weapon models? | [`../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md`](../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md) — canonical pipeline and #597 post-mortem |
| What goes in `inventory_icon` vs `hud_icon`? | This file — Icon Systems |
| Which traits and properties are valid? | This file — Properties and Traits |
| When does mod registration actually run? | This file — Registration Timing |
| Custom moveset / stat changes? | This file — Animation: System B + Custom Templates |
| Cross-access (`can_wield` expansion)? | This file — Animation: cross-access |
| Per-perspective scale (`_1p` / `_3p`)? | This file — Model Scaling and Grip Offsets |
| What's the base weapon's IML key? | Top-level `ITEM_LIST.md` |

### Build and deploy

```powershell
Set-Location "C:\Users\danjo\source\repos\vermintide-2-tweaker"
node C:/Users/danjo/source/repos/vmb/vmb.js build character_weapon_variants --no-workshop --cwd
# Deploy to workshop folder
$wsDir = "C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\3716869446"
Get-ChildItem "character_weapon_variants\bundleV2" -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $wsDir $_.Name) -Force }
```

Bump `MOD_VERSION` (line 3 of `character_weapon_variants.lua`) on every
build. Hot-reload is unsafe — full game restart after every deploy. See
`feedback_version_bump.md` and `feedback_hot_reload_unfixable.md`.

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

Items must be registered with `rarity = "default"` in `entry.rarity`, `mod_data.rarity`, and `mod_data.CustomData.rarity`. The actual display rarity is then set **after** registration by modifying the live backend item — but **only if `def.rarity ~= "default"`** (`_auto_register_all` skips the upgrade for blacksmith templates):

```lua
-- During registration (in _build_entry):
entry.rarity = "default"
entry.mod_data.rarity = "default"
entry.mod_data.CustomData.rarity = "default"

-- After add_mod_items_to_local_backend + _refresh():
-- Skipped entirely when def.rarity == "default"
local item = backend_items:get_item_from_id(backend_id)
item.rarity = "unique"        -- display rarity
item.data.rarity = "unique"   -- data-level rarity
item.CustomData.rarity = "unique"  -- serialized rarity
```

`def.rarity = "default"` is the "blacksmith template" path — see the next section. Any other value goes through the upgrade.

## Blacksmith Template Pattern

A "blacksmith template" is the unlocked white/grey starter weapon that the forge will let the player re-roll properties on, salvage, and apply illusions to — same UX as vanilla `es_bastard_sword`'s default-rarity drop from a commendation chest. CWV's `cwv_es_longsword` (Imperial Longsword) and `cwv_es_axe_shield` are examples.

### Def fields

```lua
{
    item_key      = "cwv_<weapon>",
    base_weapon   = "es_bastard_sword",     -- vanilla weapon to clone
    rarity        = "default",              -- blacksmith template tier
    power_level   = 5,                      -- low; properties will roll
    right_hand_unit = "...",                -- the variant's DEFAULT model
    left_hand_unit  = "...",                -- (same)
    -- traits / properties intentionally omitted: forge rolls them
}
```

### What `_build_entry` does for a default-rarity variant

1. `entry = table.clone(base, true)` — entry inherits the base weapon's `name`, `key`, and `right_hand_unit`. Do NOT clobber `name` / `key` (per `feedback_cwv_clone_name_clobber.md`); inherited values are needed for downstream lookups not to crash.
2. `entry.right_hand_unit = def.right_hand_unit` — overrides the base mesh with the variant's chosen default model. **This is the variant's permanent default model, not an illusion.**
3. `entry.cwv_variant = true` — cross-mod marker.
4. `entry.skin_combination_table = "<type>_skins"` — so the cosmetic menu knows which illusions are available for this item type.
5. **NO `mod_data.CustomData.skin` set** (gated by `def.rarity ~= "default"`). Vanilla blacksmith templates have a nil skin field, and the forge requires that to treat the item as unlocked. Pre-applying any skin makes the forge lock the item ("locked variant" UI).

### Why the variant's mesh still renders without a pre-applied skin

The CWV mod hooks `BackendUtils.get_item_units`. When the resolution returns no skin and the `backend_id` matches the `cwv_<key>_001` pattern, the hook forces `result.right_hand_unit` and `result.left_hand_unit` to the def's overrides. This compensates for the upstream code path where vanilla `BackendUtils.get_item_units` reads `item_data.right_hand_unit` from whatever item_data was passed in — and that path can land on the BASE entry (whose `right_hand_unit` is the base mesh) because CWV entries inherit `entry.name` from the clone.

When the user later applies a different illusion via the cosmetic menu, `result.skin` becomes non-nil and the hook leaves the result alone — user-selected illusions win over the def's default.

### Skin entry handling

`_register_variant_skins` still creates a `cwv_<key>_skin` entry in `WeaponSkins.skins`, in `WeaponSkins.skin_combinations[<type>_skins]`, and in `ItemMasterList[skin_key]`. That's so OTHER variants of the same item_type can apply this variant's look as an illusion via the cosmetic menu. The variant itself doesn't reference its own skin — its base model already IS that look.

**`matching_item_key` on the ItemMasterList skin entry MUST be `def.base_weapon`, not `def.item_key`.** Vanilla `_apply_skin_to_item` does `ItemHelper.get_template_by_item_name(matching_item_key)`. For `skin_only` variants (e.g. `cwv_es_longsword_nordland`) the def's `item_key` is NOT mirrored into ItemMasterList by `_auto_register_all` (skin-only entries are deliberately not handed to the player as inventory items), so a lookup against `def.item_key` returns nil and crashes. The `def.base_weapon` (e.g. `es_bastard_sword`) is always present in `ItemMasterList` with a real template — see CHANGELOG v0.1.95.

### Forge interactions verified

- Re-roll properties: works (default-rarity items show the property roll UI).
- Apply illusion: works post-v0.1.91 (the skin-side `ItemMasterList[skin_key]` entry is now registered) and post-v0.1.95 (`matching_item_key` correctly points at the base weapon).
- Salvage: works.
- Inventory display: white border, no rarity glow — same as a vanilla blacksmith template.

### When to use the blacksmith template pattern

- Variant is meant as a "starter" or generic alternative — like
  vanilla blacksmith drops.
- Power level should be low (5).
- Properties should roll on the forge, not be pre-baked.
- Player should be able to apply any sibling variant's illusion to
  it.

For curated exotic/unique variants (Halfling Splitter, Helmgart
Watchsword, Black Guard Blade): use a different pattern —
`rarity = "exotic"` / `"unique"`, pre-applied skin via mod_data,
traits / properties baked in. Those ship with a fixed visual
identity.

### Common bugs (and the fixes that landed them)

| Symptom | Root cause | Fixed in |
|---|---|---|
| Forge says "locked variant", no re-roll | `mod_data.CustomData.skin` was pre-applied | v0.1.87: gate skin pre-apply on `def.rarity ~= "default"` |
| Inventory preview renders BASE weapon mesh | `BackendUtils.get_item_units` fell back to base entry's `right_hand_unit` | v0.1.93: `BackendUtils.get_item_units` hook forces the cwv override when no skin applied |
| Grip offset doesn't apply on inventory preview | `_cwv_spawn_item_post` looked up `_equipment_units[<string slot_type>]`, table is numeric-keyed | v0.1.84: bridge via `info.spawn_data[1].slot_index` |
| Illusion picker crashes opening | `ItemMasterList[skin_key]` was nil | v0.1.91: register weapon_skin entry in ItemMasterList |
| "Requested template ... does not exist" on illusion swap | `matching_item_key = def.item_key`, but skin_only variants aren't in ItemMasterList | v0.1.95: use `def.base_weapon` instead |

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

Set on the item entry so the backend resolves to the variant's skin **as the curated default cosmetic**. Done ONLY for non-default-rarity variants — see "Blacksmith Template Pattern" above.

- **Curated exotic / unique variants** (e.g. Black Guard Blade, Imperial Axe and Shield): pre-apply the skin. They ship with their illusion baked in as part of their identity.
- **Default-rarity blacksmith templates** (e.g. Imperial Longsword): leave both fields nil. The mesh comes from `entry.right_hand_unit` directly via the `BackendUtils.get_item_units` cwv-override hook. Pre-applying a skin would make the forge treat the item as a locked illusion variant.

`_build_entry` gates the pre-apply on `def.rarity ~= "default"`.

### `skin_combination_table`

Do **NOT** clear `skin_combination_table` on the cloned entry. The cosmetics/illusion menu reads this field to determine available skins. Keeping the base weapon's table means vanilla illusions for that weapon type appear in the cosmetics gear menu.

### Dual-wield variants — display rig requirements

When adding a dual-wield variant (or any variant where `def.left_hand_unit` is set), the cosmetic illusion picker requires the skin entry to use a **dual-attach display rig**. Picking the wrong rig crashes the previewer with `[Script Error]: j_leftweaponattach` the moment the menu opens or a thumbnail is clicked.

**The three requirements:**

1. **Use a dual-attach `display_unit`.** Single-sword rigs (`display_1h_swords`, `display_1h_weapon`) only author `j_rightweaponattach`. Dual rigs author both nodes. Pick by mesh family:

   | Variant flavor | Required `display_unit` | Vanilla precedent |
   |---|---|---|
   | Identical-mesh swords (e.g. `cwv_es_dual_swords`) | `units/weapons/weapon_display/display_dual_weapons` | `we_dual_sword_skin_01` (`weapon_skins.lua:5750`) |
   | Identical-mesh axes (e.g. `cwv_es_dual_axes`) | `units/weapons/weapon_display/display_dual_axes` | `dr_dual_wield_axes` skins |
   | Identical-mesh hammers (e.g. `cwv_es_dual_maces`) | `units/weapons/weapon_display/display_dual_hammers` | `dr_dual_wield_hammers` skins |
   | Identical-mesh daggers | `units/weapons/weapon_display/display_dual_daggers` | `we_dual_wield_daggers` skins |
   | Mixed mesh (axe + falchion) | `units/weapons/weapon_display/dual_wield_axe_falchion` | `wh_dual_wield_axe_falchion` skins |

   When in doubt, find the vanilla weapon with the same model layout and copy its `display_unit` (it's typically on the `weapon_template.display_unit` field in `scripts/settings/equipment/weapon_templates/<template>.lua`).

2. **Set `left_hand_unit` on the skin entry**, typically `= right_hand_unit` for identical-mesh dual-wield. If left is nil, vanilla `BackendUtils.get_item_units` returns nil for left, the previewer skips left attach, and only the right weapon renders — single-sword preview regression.

3. **Set both fields on BOTH layers**: the `WeaponSkins.skins[skin_key]` entry AND the `ItemMasterList[skin_key]` weapon_skin entry. The previewer reads them via two different chains (`LootItemUnitPreviewer._spawn_link_unit:467-477` and `BackendUtils.get_item_units` from `_load_item_units:270`). Setting them on only one layer is a v0.1.99/0.1.103 latent bug — silently picks up a wrong-rig fallback.

**Cross-character illusions:** when registering vanilla skins from a different weapon family as illusions on a cwv dual-wield variant (e.g. Kruber 1h-sword skins on `cwv_es_dual_swords`), do NOT inherit `source.display_unit` from the source skin. The source skin's rig is for its native weapon family (likely a single-sword rig like `display_1h_swords`) and won't have `j_leftweaponattach`. Force the dual-wield rig on the cloned skin entry instead. See `_register_kruber_1h_sword_dual_illusions` for the canonical pattern.

**Why this is non-obvious:** the constraint is invisible at registration time — the runtime crash only fires when the previewer attempts to attach. The exact rig requirement comes from the engine's `Unit.node()` lookup against the spawned display unit, which has no Lua-visible schema. The investigation that surfaced this rule cost ~20 versions (v0.1.122 → v0.1.145); see `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the full post-mortem and the false-negative trap that masked it for so long.

## Naming flow for cwv variants

VT2 displays a weapon's name through multiple keys depending on the UI element. Get any one of them wrong and the user sees a mismatched label. The flow:

| UI surface | Reads | For our cwv items |
|---|---|---|
| Inventory tile name | `UIUtils.get_ui_information_from_item(item)` → branches on `item.skin` | When skin pre-applied (exotic): `WeaponSkins.skins[skin].display_name` (= `<item_key>_skin_name` → mapped via `_display_names`). When no skin (default rarity): `item.data.display_name` (= `<item_key>_name`). Both flow through our Localize hook. ✓ |
| Cosmetics customization title | `UIUtils.get_ui_information_from_item` (same as above) | Same. ✓ |
| Cosmetics inventory header / loot drop banner / crafting subtitle | `Localize(item_data.item_type)` directly | **Trap.** If `entry.item_type` is inherited from the clone (e.g. `bw_dagger`), this returns "Dagger" — the BASE weapon's localized name — even though the illusion shows "Shortsword". Must override `entry.item_type` to a cwv-prefixed key and map it in `_display_names`. |
| Skin picker thumbnail name | `Localize(skin_template.display_name)` | Set per skin via `<item_key>_skin_name` in `_register_variant_skins` and per illusion via the source skin's `display_name` plus `_register_custom_illusions`. ✓ |
| Weapon-type localization elsewhere | Various `Localize(item_data.<key>)` paths read miscellaneous fields | The `cwv_variant` boolean on `entry` is the cross-mod marker — sibling mods (cosmetics_tweaker, weapon_tweaker) gate name-keyed lookups on this. |

**The critical rule** (added v0.1.173): `_build_entry` ALWAYS sets `entry.item_type = def.item_type or def.item_key`. The fallback to `def.item_key` is what fixes the "Dagger" leak — without it, variants that don't declare `def.item_type` inherit the base weapon's item_type from the clone (per `feedback_cwv_clone_name_clobber.md` we deliberately keep `entry.name` / `entry.key` inherited, but item_type is safe to override since vanilla code mostly checks for marker strings like `"weapon_skin"`, not specific weapon types).

**Localization registration** is centralized at the bottom of `_variant_definitions` iteration:

```lua
for _, def in ipairs(_variant_definitions) do
    _display_names[def.item_key .. "_name"]        = def.display_name
    _display_names[def.item_key .. "_description"] = def.description
    if def.skin_display_name then
        _display_names[def.item_key .. "_skin_name"] = def.skin_display_name
    end
    -- The item_type → display_name binding is what fixes the "Dagger"
    -- inheritance bug. Always register, with the same fallback rule
    -- _build_entry uses for entry.item_type.
    _display_names[def.item_type or def.item_key] = def.display_name
end
```

Symptom to watch for: if you add a new variant and the inventory tile / cosmetics title shows the right name but a header / drop banner / sort label shows the BASE weapon's name, the variant probably didn't get its `item_type` registered correctly. Verify with a `Localize("<your_item_key>")` test in the console.

## Attachment node linking — character-specific bone names

A subtler trap in the same family as the j_leftweaponattach saga, surfaced v0.1.169:

Cross-character template clones inherit the source template's `right_hand_attachment_node_linking` and `left_hand_attachment_node_linking`. These linkings carry **wielded** AND **unwielded** node names. The unwielded node is where the weapon sheaths to the character's body when not held — and some templates use **character-specific bone names** for unwielded.

Concrete case: `one_handed_hammer_wizard_template_1` (Sienna's 1H mace) uses `AttachmentNodeLinking.brw_hammer`, which sets `unwielded.source = "a_unwielded_brw_mace"` — a bone authored only on Sienna's empire-female 3P body skeleton. When `cwv_es_maul` clones this template for Kruber and the player unequips, `Unit.node()` looks for `a_unwielded_brw_mace` on Kruber's skeleton, doesn't find it, and crashes (same shape as `j_leftweaponattach` errors — `[Script Error]: a_unwielded_brw_mace`).

**The rule:** when cloning a template across characters, override the inherited attachment node linking to a **generic** linking that uses common-skeleton bone names:

| Source template uses | Override to | Generic unwielded bone |
|---|---|---|
| `AttachmentNodeLinking.brw_hammer` (Sienna 1H mace) | `AttachmentNodeLinking.one_handed_melee_weapon.right` (1H) or `.two_handed_melee_weapon` (2H silhouette) | `a_unwielded_1h_right` / `a_unwielded_2h` |
| Other character-specific linkings | Same — pick `one_handed_melee_weapon` or `two_handed_melee_weapon` based on the variant's visual class | Generic |

**How to identify a character-specific linking**: grep `attachment_node_linking.lua` for `a_unwielded_<character_prefix>_*` source names. Anything with `brw_`, `dr_`, `we_`, `wh_` prefix in the bone name is character-specific.

The fix in `_create_<variant>_template`:

```lua
-- Override character-specific linking inherited from clone source.
if AttachmentNodeLinking and AttachmentNodeLinking.two_handed_melee_weapon then
    template.right_hand_attachment_node_linking = AttachmentNodeLinking.two_handed_melee_weapon
end
```

See `_create_maul_template` for the canonical example. The fix happens AFTER the table.clone since clone preserves the original linking reference.

## BASE template patching for previewer compatibility

The inventory previewer (`world_hero_previewer.lua` `equip_item`) calls `ItemHelper.get_template_by_item_name(item_name)` where `item_name` is the BASE weapon's name (cwv variants inherit `entry.name` per `feedback_cwv_clone_name_clobber.md`). This means the previewer reads the **BASE template**, NOT our cwv clone. Two consequences:

**1. Per-career wield events** — see `feedback_cwv_previewer_template_lookup.md`. If you set `wield_anim_career_3p` on your cloned template for Kruber routing, the previewer ignores it. Patch the BASE template's `wield_anim_career_3p` too (scoped to your cwv careers; vanilla wielders fall through unchanged).

**2. Hand-attachment fields** (added v0.1.181) — when a variant's hand layout differs from the base weapon's, the BASE template's `right_hand_attachment_node_linking` / `left_hand_attachment_node_linking` may be missing for the variant's used hand. Concrete case: `cwv_es_outrider_grenade_launcher` clones from `dr_deus_01` (Bardin trollhammer, left-hand-mount, base template only sets `left_hand_attachment_node_linking`). Our variant mounts the gun on the right hand (blunderbuss model), so the previewer hits the right-hand path → reads `item_template.right_hand_attachment_node_linking.third_person` on the BASE template → crashes (nil index, crash GUID `c847908d`).

**The rule:** when your variant uses a hand the base weapon doesn't, patch the BASE template at the end of your `_create_<variant>_template` function:

```lua
-- BASE template patch — previewer ignores our clone's right_hand_attachment_node_linking,
-- so add it here too. Bardin's right_hand_unit stays nil natively, so the previewer's
-- right-hand path never fires for him → harmless side effect for vanilla wielders.
if Weapons.<base_template_name> and AttachmentNodeLinking and AttachmentNodeLinking.<linking_name> then
    Weapons.<base_template_name>.right_hand_attachment_node_linking = AttachmentNodeLinking.<linking_name>
end
```

See `_create_outrider_grenade_launcher_template` (the trollhammer-template-on-blunderbuss-model variant) for the canonical example. Same pattern as the v0.1.84 elven sword shield wield-routing fix.

## Cross-template Frankenstein weapons (visual ≠ behavior)

Sometimes you want a variant that looks and animates like one vanilla weapon but behaves and sounds like another — e.g. `cwv_es_outrider_grenade_launcher` is Kruber's blunderbuss visually (model + 1P/3P state machine + wield anims) but Bardin Engineer's Trollhammer Torpedo behaviorally (single-shot grenade-thrower projectile, charge-and-release, blast damage, trollhammer sounds).

**The structural pattern:**

1. **Pick the BEHAVIOR side as the source for the template clone.** Cloning the trollhammer template gives us its `actions`, `ammo_data`, `attack_meta_data`, `default_loaded_projectile_settings`, `wwise_dep_*` — all the mechanical knobs.
2. **Override the visual layer fields** at the end of the clone:
   - `state_machine` → the visual weapon's 1P state machine path
   - `wield_anim` (and `_no_ammo`, `_not_loaded` variants) → visual weapon's wield events
   - `display_unit` → visual weapon's preview rig
   - `right_hand_attachment_node_linking` / `left_hand_attachment_node_linking` → match the visual weapon's hand mount
3. **Verify anim_event compatibility.** The behavior-side template's `actions` reference per-action `anim_event` strings (e.g. `"attack_shoot"`). For the swap to play correctly, those event names must EXIST in the visual-side state machine. If the source uses unique events that the visual SM doesn't have, you'll need a per-sub-action `anim_event` remap (same pattern as cross-character anim work).
4. **Hand-mount swap.** If the behavior template's weapon was mounted on a different hand than the visual:
   - Iterate `template.actions.action_one` and any sub-actions; flip `weapon_action_hand`
   - Flip `template.ammo_data.ammo_hand`
   - Move `template.wwise_dep_left_hand` → `template.wwise_dep_right_hand` (or vice versa)
   - Clear `template.left_hand_unit` / `left_hand_attachment_node_linking` (or right) so the inherited mount slot doesn't fight the new one
   - Set the variant def's `no_left_hand = true` (or future `no_right_hand`) so `_build_entry` clears the inherited model on that side
5. **Patch the BASE template** for previewer compatibility (see "BASE template patching" above).

**Tunings** (per-action stat tweaks): apply at the same time as the visual swap. Common: projectile speed, reload time multiplier on `ammo_data.reload_time`, damage profile clone with multipliers via `_clone_damage_profile`, `attack_meta_data.max_range`. See `_create_outrider_grenade_launcher_template` for the canonical example.

**Known limitation:** action timing fields (`fire_time`, `total_time`, `damage_window_start/end`) come from the BEHAVIOR side. They won't necessarily match the VISUAL state machine's anim length. Result: visual desync (e.g. character finishes the shoot anim before/after the projectile actually fires). Acceptable trade-off in most cases; tune if it reads wrong.

## `no_left_hand` / `no_right_hand` def flag

`_build_entry` supports a `def.no_left_hand = true` flag (added v0.1.181). When set, it explicitly nils out `entry.left_hand_unit` after the clone, even if the base weapon had one.

**Why this is distinct from `def.left_hand_unit = nil`:** the existing override gate is `if def.left_hand_unit then entry.left_hand_unit = def.left_hand_unit end`, so a `nil` value just means "don't override → inheritance kicks in". The flag explicitly clears it.

**When to use it:** when your variant inherits a hand-mounted model from the base that the variant doesn't want — typically when moving from left-mount to right-mount or vice versa (see Frankenstein recipe above). Without the flag, the variant renders BOTH the inherited base model AND the new mount — visually a Frankenstein two-weapon appearance.

Symmetrical `def.no_right_hand` not yet implemented because no current variant needs it — the trollhammer-side is the only "wrong-hand-mount" base weapon we've cloned. Add when needed; pattern is one line in `_build_entry`.

## Skin entry fallbacks — gate on base presence

`_register_variant_skins` mirrors several fields from the variant def into the `WeaponSkins.skins` entry, with fallbacks to either the base weapon or related def fields. **Some fallbacks must be gated on the base weapon actually having the field** — otherwise you force a value into a slot the base never used, which trips downstream assertions.

**The `ammo_unit` trap (v0.1.184, crash GUID `2df233ae`):**

The original code:

```lua
local ammo_unit = def.ammo_unit or def.left_hand_unit  -- WRONG
```

Worked for thrown ammo variants (`cwv_es_javelin`, base `we_javelin`) where `we_javelin` IML has `ammo_unit` set — the fallback to `def.left_hand_unit` mirrored the held mesh as the throw projectile. Same fallback **broke** non-ammo-projectile variants whose base weapon's template has `ammo_data` (so `GearUtils.spawn_inventory_unit` checks `ammo_data.ammo_hand`) but no `ammo_unit` (nothing visually attached to the body).

Concrete case: `cwv_es_brace_repeater` (base `wh_brace_of_pistols`). The brace template has `ammo_data.ammo_hand = "right"`. Vanilla doesn't set `ammo_unit` so the gate `if ammo_data and ammo_data.ammo_hand == hand and ammo_unit_name then` doesn't fire. Our cwv variant force-set `ammo_unit = def.left_hand_unit` (the pistol mesh) → gate fires → `fassert(ammo_unit_attachment_node_linking, ...)` fails because the brace template never defines `ammo_unit_attachment_node_linking`.

**The fix:**

```lua
local ammo_unit = def.ammo_unit or (base.ammo_unit and def.left_hand_unit)
```

Only inherits the held mesh as ammo_unit when the base weapon already uses one.

**The general rule** (apply when adding new fallbacks in `_register_variant_skins` or similar): if your fallback assumes the base behaves a certain way, GATE it on `base.<assumed_field>` existing. Don't force a value into a field the base never used — vanilla downstream code probably doesn't tolerate it.

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

A `hook_safe` on `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` marks custom skins as unlocked only when their copied `ItemMasterList.required_dlc` is absent or owned. Never omit the source ownership field from a clone: a custom key is not permission to bypass DLC ownership.

For complete same-family harvests, derive the source key set from the owner's `WeaponSkins.skin_combinations[ItemMasterList[owner].skin_combination_table]`, preserving every tier membership, then add `WeaponSkins.default_skins[owner]` because vanilla stores the default outside the combination pool. Do not discover a family by scanning `ItemMasterList`: DLC tables can merge later, and a fixed destination tier schema silently drops later tiers such as `magic`. Canonical examples: `cwv_es_dual_axes` and `cwv_wh_dual_axes` / issue #579.

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

Cross-character illusions only swap the 3D model. If both weapons share the same `template` (e.g., `two_handed_swords_template_1` for all greatswords), no animation work is needed.

For **new variant weapons** (separate items, not just illusions), animation work belongs in this mod via the template-clone path — see "Animation: System B" below. The `weapon_tweaker` runtime hook is the right tool only for vanilla items unlocked on new careers and for husk fixes; CWV variants own their template and should bake the redirects directly into the clone.

> **Note — availability is a separate axis from animation ownership (Issue #368, 2026-07-05).**
> The above is about who bakes 3P *animation* redirects (CWV owns its variants' anims). It does
> NOT mean CWV owns *availability*. wt and CWV are **independent** on availability (overlap
> allowed): CWV is default-on with no per-weapon toggles, and wt is the availability control
> surface — when co-installed, wt's per-weapon toggles default ON for the overlapping weapons and
> also cover CWV's `cwv_variant` items. See `CROSS_MOD_ARCHITECTURE.md`.

## Animation: System B (template-clone path)

Variant weapons that need 3P animation fixes (cross-character moveset, missing clips on the target body) handle that work **here**, not in `weapon_tweaker`. The pattern is to clone the source template at mod load, rewrite the animation fields we care about, and store the clone as a new entry in the `Weapons` global. The variant's `template` field points at the clone, so the engine spawns it with our edits.

This complements the runtime-hook path in `weapon_tweaker` (System A). See the top-level `DEVELOPMENT.md` "Two parallel systems" table for when each applies. Short version: System B is the right tool whenever we own the item.

### The 1P/3P rule (load-bearing)

**1P animations are universal across all six characters.** The `first_person_base` unit is shared, so any weapon's 1P clips and state machine play correctly on any character's first-person view. Never override `anim_event` (1P), `wield_anim` (1P), `state_machine`, or `anim_event_1p` per character. All System B work targets the **3P body** via `anim_event_3p`, `wield_anim_3p`, and `wield_anim_career_3p`.

The character-specific 3P body skeletons (empire-soldier, wood-elf, dwarf, witch-hunter, bright-wizard, undead) each have their own authored event vocabulary. When a cross-character variant's clip names don't exist on the target skeleton, that's the failure mode we're fixing.

### Engine resolution

Per-sub-action lookup (`Vermintide-2-Source-Code/scripts/unit_extensions/weapons/weapon_unit_extension.lua:512`):

```lua
local event_3p = get_action_anim_event(..., "anim_event_3p") or event
```

The 3P body plays `sub_action.anim_event_3p` if set, else falls back to `sub_action.anim_event`. The fallback is the failure mode for cross-character clones — the elf event name might not exist on Kruber's body. Our fix is to write `anim_event_3p` per sub-action so the body plays a clip that *does* exist.

The lookup is dumb: no career branch, no skin branch beyond `weapon_skin_anim_overrides[skin].anim_event_3p`. So career-conditional sub-action behavior isn't reachable from a single template — if you need that, ship per-career variant items (which is the whole CWV approach).

### The pattern

Every System B template clone follows the same shape (see `_create_imperial_dual_swords_template`, `_create_elven_sword_shield_template`):

1. **Guard.** Bail if the source template isn't loaded yet, or if our clone already exists.
   ```lua
   if not Weapons or not Weapons.dual_wield_swords_template_1 then return end
   if Weapons.imperial_dual_swords_template then return end
   ```

2. **Deep clone.** Always pass `true` to `table.clone` so nested action tables aren't aliased back to vanilla.
   ```lua
   local template = table.clone(Weapons.dual_wield_swords_template_1, true)
   ```

3. **Walk `template.actions[*][*]` and rewrite `anim_event_3p`.** Use a small flat remap table keyed on the source's `anim_event` value. Only target events that are missing or visually wrong on the target skeleton — same-named events that exist on both bodies need no entry.
   ```lua
   local _ids_anim_remap = {
       attack_swing_charge_diagonal = "attack_swing_charge_left",
       attack_swing_heavy_right     = "attack_swing_heavy_right_diagonal",
       push_stab                    = "attack_push",
   }
   for _, action_group in pairs(template.actions) do
       if type(action_group) == "table" then
           for _, sub_action in pairs(action_group) do
               if type(sub_action) == "table" and sub_action.anim_event
                  and _ids_anim_remap[sub_action.anim_event] then
                   sub_action.anim_event_3p = _ids_anim_remap[sub_action.anim_event]
               end
           end
       end
   end
   ```
   Never touch `sub_action.anim_event` — that's the 1P field. Only write `anim_event_3p`.

4. **Override the wield pose.** Set `template.wield_anim_3p` (default for any career) and optionally `template.wield_anim_career_3p` (per-career overrides keyed by career name).
   ```lua
   template.wield_anim_3p = "to_dual_hammer_sword_es"
   template.wield_anim_career_3p = {
       es_mercenary = "to_dual_hammer_sword_es",
       es_huntsman  = "to_dual_hammer_sword_es",
       -- ...
   }
   ```

5. **Register the clone.**
   ```lua
   Weapons.imperial_dual_swords_template = template
   ```
   The variant definition then sets `template = "imperial_dual_swords_template"` and `_build_entry` writes that onto the cloned `ItemMasterList` entry.

6. **Patch the BASE template's `wield_anim_career_3p` for the inventory previewer.** This is the non-obvious step. The character previewer (`HeroPreviewer._spawn_item`) reads the **base** template's `wield_anim_career_3p`, not our clone — because at preview time the system resolves through the original template chain. Without this patch, the in-keep menu shows the wrong wield pose. Scope the patch tightly to the variant's careers so unrelated careers fall through to vanilla.
   ```lua
   local base = Weapons.dual_wield_swords_template_1
   if base then
       base.wield_anim_career_3p = base.wield_anim_career_3p or {}
       base.wield_anim_career_3p.es_mercenary      = "to_dual_hammer_sword_es"
       base.wield_anim_career_3p.es_huntsman       = "to_dual_hammer_sword_es"
       base.wield_anim_career_3p.es_knight         = "to_dual_hammer_sword_es"
       base.wield_anim_career_3p.es_questingknight = "to_dual_hammer_sword_es"
   end
   ```
   Do **not** clobber `wield_anim_career_3p` wholesale — merge keys.

7. **Call the function at file load** (after the `Weapons` global is populated by VMF).
   ```lua
   _create_imperial_dual_swords_template()
   ```

### What you can change beyond clip names

System B owns the entire sub-action object, not just the event name. Inside the same `for sub_action in pairs(action_group)` loop you can also rewrite:

| Field | Effect |
| :--- | :--- |
| `total_time` | Action duration (the engine waits this long before the action ends) |
| `damage_window_start` / `_end` | When hits register, in seconds from action start |
| `anim_time_scale` | Speed multiplier on the played clip — useful when the substitute clip is shorter or longer than the source |
| `kind` | `sweep`, `stab`, `push`, etc. — selects the hit-detection routine |
| `range_mod` | Hit reach |
| `dedicated_target_range` | Target lock-on distance |
| `damage_profile` / `damage_profile_left` / `damage_profile_right` | Per-action damage data (clone via `_clone_damage_profile` if you need to scale) |
| `allowed_chain_actions` | Combo chain — what this sub-action can transition into |
| `anim_event_from_chain` | Substitute clip when this sub-action was reached *via* a specific previous chain link (so H2 can look different depending on what preceded it) |

The most common authoring drift: you swap `anim_event_3p` to a clip that's a different length than the source, and `damage_window_*` is now misaligned. Rewrite the timing fields when this happens.

### When to override more than the event name

- **Substitute clip is shorter/longer than source** → adjust `total_time`, `damage_window_*`, `anim_time_scale` together. The animation plays through `total_time`; if it ends earlier the body holds whatever idle stance was active before the clip started (per `feedback_vt2_no_tpose_default_stance.md` — not a T-pose), if it ends later the next action stalls.
- **Visual swing direction differs** (e.g. source's right-handed horizontal becomes a diagonal on target body) → either accept it, pick a different clip, or rebuild the chain so the visible motion makes combo sense.
- **Charge wind-up direction doesn't match release direction** → MAY look incoherent. Source templates pair specific charge sub-actions with specific release sub-actions via the chain graph; remapping each independently can break the visual pairing (charge cocks left, release strikes right). Whether the disconnect reads as wrong is SM-specific — empire-soldier 3P (Kruber) shows it on the first heavy from idle; wood-elf 3P (Kerillian) often blends through it. If a heavy combo's *first* swing from idle looks wrong, walk the source template's `default → heavy_attack` chain and confirm your charge remap target leaves the wind-up direction matching the release direction. (See `_create_imperial_dual_swords_template` for a worked example: H1's charge had to be re-routed to `attack_swing_charge_right` after the H1 release was swapped to `attack_swing_heavy_right_diagonal`.)
- **No clip on the target skeleton matches the source intent at all** → restructure the sub-action: change `kind`, `range_mod`, `damage_window`, and pick a clip that makes the new motion read correctly.
- **Chain context matters** (H2 should look different if it followed a left vs right H1) → use `anim_event_from_chain[action_name][sub_action_name].anim_event_3p`.

### Reaching clips that live in a different SM sub-graph

The 3P body's master state machine is organised into sub-graphs per weapon type. `wield_anim_3p = "to_<sm>"` puts the body in that sub-graph; from there, only events the sub-graph has *visible* transitions for will play a clip. A clip authored in `1h_sword_shield` (e.g. `attack_swing_stab`) is generally NOT reachable from the `dual_hammer_sword` sub-graph just by firing the event name — `force3p` may report `exists=true` because the master SM knows the event, but the destination state may be a stub that produces no visible animation.

Two realistic options when a clip lives elsewhere:

1. **Commit the wield to the SM that owns the clip.** Set `template.wield_anim_3p = "to_<that_sm>"` and re-author your action set against that SM's vocabulary. The 3P body permanently uses that sub-graph's idle / walk / block / wield poses while this weapon is equipped. **Reference pattern: Peregrinaje's `markus_torch_and_shield`** — they set `wield_anim = "to_1h_axe_shield"` and authored every sub-action's `anim_event` against 1h_axe_shield's vocabulary. Trade-off: the body's posture follows the SM, so the model has to fit. A torch fits axe+shield; two swords don't fit sword+shield without looking like "sword + improvised shield."
2. **Accept the clip is unreachable** and pick the closest-matching clip from the wield SM's authored vocabulary.

#### What does NOT work

- **`pre_action_anim_event` SM-switch graft** — firing `to_<other_sm>` as `pre_action_anim_event`, the cross-SM clip as `anim_event_3p`, and `to_<original_sm>` as `anim_end_event_3p` does NOT cleanly route a single action through a foreign sub-graph. Two failure modes confirmed in v0.1.89:
  - The wield-change clip from `to_<other_sm>` plays visibly and eats the action's damage window before the target clip can play.
  - `anim_end_event_condition_func` on most release sub-actions returns false on `action_complete`, gating ALL end events including the return transition — the body gets permanently stuck in the new sub-graph for every subsequent action.
- **Just firing the cross-SM event name as `anim_event_3p`** — `force3p exists=true` is necessary but not sufficient. Watch the body during force3p; only "the body visibly animated" counts as confirmation.

### Hard limits

System B can't author new clips. We pick from what the target skeleton's state machine already has. If Kruber's empire-soldier body genuinely lacks any clip that depicts the visual the source weapon needs, the best we can do is the closest existing clip in the wield SM's vocabulary — there's no path to ship new animation files from a workshop mod, and (per the section above) cross-sub-graph grafting via `pre_action_anim_event` is not a clean alternative.

### Discovery commands

- `/dump_actions <pattern>` dumps every `Weapons` template's `actions[*][*]` with both `anim_event` and `anim_event_3p` for each sub-action — use this to read the source template you're cloning from and to find candidate substitute clips on related templates.
- `/animlog` toggles per-event logging tagged 1P / 3P-body / 3P-husk with `[MISSING]` / `REDIR` / `REMAP` markers — use this to verify the clone's `anim_event_3p` values actually exist on the target body and that no event is hitting the engine fallback path.
- `/force3p <event>` fires an event on the last-seen 3P unit so you can preview a candidate clip without rebuilding. **`exists=true` in the output is not the same as visible playback.** It comes from `Unit.has_animation_event`, which returns true whenever the master SM knows the event name — but the destination state in the current sub-graph may be a stub that animates nothing. Always watch the 3P body during the test. Only "the body visibly moved" counts as confirmation that the clip will play during real action firing.

### Common mistakes

- **Touching `anim_event` (1P).** Always write `anim_event_3p` only. The 1P side is shared and self-corrects.
- **Forgetting the base-template patch.** The clone has the right wield pose in-game but the menu preview is wrong. Step 6 above.
- **Shallow clone.** Without `table.clone(..., true)`, mutations leak into vanilla actions. Always deep-clone.
- **Wholesale `wield_anim_career_3p = {...}` on the base template.** Clobbers any keys other careers added. Merge per-key instead.
- **Adding a remap entry that was already same-named on the target body.** No-op at best, masks problems at worst (you start "fixing" things that weren't broken). Verify with `/dump_actions` on the target's native template first.
- **Chain action references that don't exist.** If you delete a sub-action, also delete `allowed_chain_actions` entries elsewhere that pointed at it.
- **Trusting `force3p exists=true` as proof a clip plays.** It only proves the SM has a transition; the destination may be a stub. Always verify visually.
- **Trying to graft a single cross-SM clip via `pre_action_anim_event` SM-switch.** See "Reaching clips that live in a different SM sub-graph" above — both failure modes are reproducible. Use the wield-commit pattern (Peregrinaje-style) if you need cross-SM clips, or accept the closest in-SM clip.
- **Remapping charge and release independently and breaking their direction pairing.** When you swap a heavy release, also walk the source's chain graph to find which charge sub-actions feed it, and remap those charges so the wind-up direction matches the new strike. Direction-mismatch isn't always visible (Kerillian's wood-elf 3P often blends through it) but Kruber's empire-soldier 3P will surface it on the first heavy from idle.

## Animation: cross-access weapons (career-specific runtime remap)

System B (template clone) is the right tool when CWV ships a new item with a custom template. It is **not** the right tool when CWV expands `can_wield` on a vanilla item so a foreign career can equip the existing weapon (the "cross-access" pattern). For that case the vanilla item points at the vanilla template, which is shared with the native wielder — mutating that template's per-action `anim_event_3p` to fix the foreign wielder's animations also changes them for the native wielder, which is wrong.

The engine has no per-career `anim_event_3p` resolution at the sub-action level (`weapon_unit_extension.lua:512` reads `current_action_settings.anim_event_3p` directly with no career context). The remap must therefore happen at the **network-bound 3P animation layer**: hook `WeaponUnitExtension._play_3p_anim` and replace the event before vanilla looks it up and sends its animation RPC. This ordering is load-bearing. A `Unit.animation_event` hook is too late: vanilla has already encoded and sent the donor event, so it can make the owner's body look correct while remote husks receive an event their body cannot play, including its authored swing-foley and exertion timeline.

### Where it lives

Code: `character_weapon_variants.lua` → "Cross-character per-action 3P anim event remap" section. Three pieces:

1. **Per-(item, career) remap tables** — `_kruber_axe_falchion_remap`, etc. — and the dispatch table `_cross_access_action_remap[item_key][career_name] = remap`.
2. **Wield tracker** — `mod:hook_safe("SimpleInventoryExtension", "wield", ...)` updates `_cross_access_local_weapon_key` and `_cross_access_local_career` when the local player swaps melee weapons. Cheap state for the hot-path lookup.
3. **The network-bound hook** — `mod:hook("WeaponUnitExtension", "_play_3p_anim", ...)` verifies the owner unit is the local 3P body, resolves the tracked (item, career, source-event) substitution, verifies the target is in `NetworkLookup.anims`, then calls vanilla with the target event. Vanilla owns both the local `Unit.animation_event` call and the RPC, so the owner and every observer consume the same receiver-compatible event.

### How to add a new cross-access remap

Concrete example (axe+falchion on Kruber):

```lua
local _kruber_axe_falchion_remap = {
    -- H1 chain (charge_down → heavy_down): no overhead clip on dual_hammer_sword,
    -- route to right-side heavy. Charge AND release both swap to keep direction
    -- pairing coherent.
    attack_swing_charge_down = "attack_swing_charge_right",
    attack_swing_heavy_down  = "attack_swing_heavy_right_diagonal",
    -- H2 release (heavy_left): preserve LEFT direction.
    attack_swing_heavy_left  = "attack_swing_heavy_left_diagonal",
    -- Light + push variants.
    attack_swing_down_left   = "attack_swing_left_diagonal",
    attack_push              = "attack_swing_left_diagonal",
}

local _cross_access_action_remap = {
    wh_dual_wield_axe_falchion = {
        es_mercenary      = _kruber_axe_falchion_remap,
        es_huntsman       = _kruber_axe_falchion_remap,
        es_knight         = _kruber_axe_falchion_remap,
        es_questingknight = _kruber_axe_falchion_remap,
    },
}
```

Procedure:

1. **Identify source events.** Run `/dump_actions <pattern>` (or grep the source template's `anim_event` values) for the item's template. Note which sub-action each event belongs to and what role it plays (light, heavy, charge, push).
2. **Identify the foreign body's wield SM.** The wielder's `wield_anim_career_3p` should already route them into a sub-graph that exists on their body — this is set up in `_cross_access_template_wield_3p` above.
3. **Map source events to substitutes authored on the foreign wield SM.** Use the same vocabulary the foreign body's native templates author. `/force3p <event>` with the cross-access weapon equipped is the verification: watch the body, "exists=true" alone is meaningless.
4. **Walk the chain graph for direction coherence.** When you remap a heavy release, look at which charge sub-actions chain into it (in the source template's `allowed_chain_actions`) and remap those charges to a wind-up that matches the new release direction. Kruber's empire-soldier 3P body surfaces direction-mismatch at the cold start of a heavy combo; other bodies sometimes blend through it but assume they will not.
5. **Add the (item, career) entries.** Reuse the same remap table for sibling careers when they share a body (all 4 Kruber careers, all 4 Saltzpyre careers, etc.) — keep one `local _<wielder>_<weapon>_remap` table and assign by reference.

### What's NOT remapped

- **1P events.** Universal across characters; `_play_3p_anim` is exclusively the third-person path. Per the load-bearing rule from "Animation: System B," never write `anim_event` (1P), `wield_anim` (1P), or `state_machine` per character.
- **A second husk-side remap.** The owning peer chooses the receiver-compatible event before vanilla's RPC. Remote peers then play that same event through `AnimationSystem`; remapping it again on the listener would risk divergence and duplicate audio.
- **Native wielders.** A career that's not a key in `_cross_access_action_remap[item_key]` falls through every event unchanged — that's why Saltzpyre's native axe+falchion animations are unaffected even though the same template still reads the event.
- **Cross-SM clips.** This hook just rewrites event names. The substitute event still has to be authored in whichever sub-graph the foreign body is currently in (set by the wield redirect). Cross-SM grafting (firing a clip from a different sub-graph) is documented as a dead-end in "Reaching clips that live in a different SM sub-graph."

### Common mistakes (specific to this pattern)

- **Mutating the base template's `anim_event_3p` to "fix" Kruber.** Affects Saltzpyre too. Use the runtime hook instead. (This bug shipped in v0.1.133 → v0.1.139 before the runtime hook was added in v0.1.140.)
- **Moving the remap to `Unit.animation_event`.** That engine call happens after `_play_3p_anim` has encoded and sent `event_3p`. The owner can appear fixed while observers still get the donor event and lose both motion and animation-authored audio.
- **Tracking weapon at every hook fire instead of via wield hook.** Querying the player's current weapon on every anim event is expensive. Track once on `SimpleInventoryExtension.wield` and read the cached value.
- **Career-name typos.** Career names are exact strings (`es_mercenary`, not `es_meercenary`). No prefix matching in this pattern — if you want all Kruber careers, list all four.

### When to use which animation pattern

| Situation | Pattern |
| :--- | :--- |
| New CWV variant item with custom template | **System B** (template clone) — own the template, edit `anim_event_3p` on sub-actions directly. |
| Cross-access via `can_wield` expansion, wield works but specific actions don't read right on foreign body | **Cross-access runtime remap** (this section) |
| Cross-access via `can_wield`, wield itself reads wrong (wrong sub-graph on foreign body) | `wield_anim_career_3p` patch on base template (career-keyed natively by engine — see `_cross_access_template_wield_3p`) |
| Vanilla weapon unlocked for new career via `weapon_tweaker.weapon_unlock_map` | **System A** (weapon_tweaker's own runtime hooks) |

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

## Model Scaling and Grip Offsets

Two layers, in precedence order:

1. **Per-variant fields on the def** — `right_hand_scale`, `right_hand_offset`, `left_hand_scale`, `left_hand_offset`. Use these only when a specific variant deviates from its weapon type.
2. **Type-level entry** — `_type_transforms[item_type] = { right_hand_scale = ..., right_hand_offset = ..., ... }`. **This is the primary way to tune a weapon type.** Each `cwv_*` `item_type` defines a new conceptual weapon (e.g. `cwv_imperial_longsword`); changes at the type level cascade to every variant sharing that type.

**Architectural rule (user-mandated):** when the user says "fix the
scale on the Imperial Longsword" or "set the grip on the X", they
mean it as a property of the WEAPON TYPE. Edit
`_type_transforms[<type>]` — ONE entry that cascades to every
variant. Don't pick one variant and tune it; don't duplicate the
same fields across multiple variant defs in lockstep. CWV's whole
point is creating new conceptual weapons; the data layout reflects
that. User's framing: *"If we're modifying a model, we modify the
model. If we're modifying a type of weapon, we modify that type."*
Same principle applies to any future visual/feel attribute that
gets a similar split (animation overrides, material settings, etc.)
— the type/variant distinction is the architectural rule, not just
a scale-system rule.

### Per-perspective overrides (`_1p` / `_3p`)

The unified scale/offset fields cascade to both 1P (held first-person view) and 3P (third-person body, what other players see). To target one perspective only, suffix the field name with `_1p` or `_3p`:

| Field | Effect |
| :--- | :--- |
| `right_hand_scale_1p` | Override 1P right-hand scale only; 3P keeps the unified value (or its `_3p` override if set) |
| `right_hand_scale_3p` | Override 3P right-hand scale only; 1P keeps the unified value (or its `_1p` override if set) |
| `left_hand_scale_1p` / `_3p` | Same, left hand |
| `right_hand_offset_1p` / `_3p` | Same pattern for grip offset |
| `left_hand_offset_1p` / `_3p` | Same pattern for grip offset |

Resolution at apply time: the per-perspective field is checked first, fallback to the unified field, fallback to the type-level entry.

Use case: a weapon's model reads correctly in 3P but looks small/large in the held first-person view. Set just the unified field for normal cross-perspective tuning; reach for `_1p` / `_3p` only when 1P and 3P need to differ. Example from `cwv_es_dual_swords`: the right/left swords needed +10% in first person to feel right in the held view but stayed at 1.0 in 3P, since the 3P body's grip and posture were already authored for the model size.

`scale_3p_only = true` is the older mechanism for "skip 1P entirely." That still works (and is functionally equivalent to setting `*_scale_1p = {1, 1, 1}` when the unified is non-1.0). Use `scale_3p_only` when you want to OPT-OUT of 1P scaling entirely; use `_1p` overrides when you want a *different* 1P scale than 3P.

The resolution helper:
```lua
local function _resolve_field(def, field)
    if def[field] ~= nil then return def[field] end
    local tt = def.item_type and _type_transforms[def.item_type]
    return tt and tt[field] or nil
end
```

Used at all four transform-application sites: `GearUtils.create_equipment`, `HeroPreviewer._spawn_item` / `MenuWorldPreviewer._spawn_item` (inside `_cwv_spawn_item_post`), and `LootItemUnitPreviewer.spawn_units`. The `_transform_map` registration loop also goes through `_resolve_field` so variants with no per-variant transform still get registered when their type contributes one.

The three rendering paths each call `Unit.set_local_scale` / `Unit.set_local_position` with the resolved values:
1. **In-game**: `GearUtils.create_equipment` → `result.right_unit_1p`, `.right_unit_3p`, `.left_unit_1p`, `.left_unit_3p`. Honors `def.scale_3p_only` to skip 1P units.
2. **Inventory preview**: `HeroPreviewer._spawn_item` / `MenuWorldPreviewer._spawn_item` → `self._equipment_units[slot_index].right` / `.left`. **Critical bridge**: `_resolve_preview_def` returns `info` from `self._item_info_by_slot`, which is keyed by string `slot_type` ("melee"/"ranged"); but `_equipment_units` is keyed by NUMERIC `slot_index`. Cross via `info.spawn_data[1].slot_index` (vanilla `equip_item` populates that field per spawn at `world_hero_previewer.lua:704/728`). Looking up `equip_units[slot_type_string]` returns nil and the entire apply path silently no-ops — fixed in v0.1.84 after diagnostic logs caught it; same bridge bug cosmetics_tweaker hit in v0.7.88. Don't refactor this lookup back to a string-keyed loop.
3. **Illusion browser**: `LootItemUnitPreviewer.spawn_units` → `self._spawned_units`.

### Adding a New Weapon Type

When the mod is creating a brand-new conceptual weapon (which is the whole point of CWV), declare it at the type level:
```lua
_type_transforms.cwv_<weapon_name> = {
    right_hand_scale  = { x, y, z },
    right_hand_offset = { x, y, z },
    -- left_hand_* if dual-handed
}
```
Then on each variant of that type, set `item_type = "cwv_<weapon_name>"` and leave the scale/offset fields off. A future "make all <weapon_name> variants thinner" tweak is one edit at the type entry.

### Per-Variant Override

When a single variant uses a model with different axis conventions than the rest of its type family (e.g. `cwv_es_longsword_nordland` uses `wpn_greatsword`, distinct from the Empire `wpn_empire_2h_sword_*` family the rest of the Imperial Longsword type uses), set the per-variant field on that def specifically. It'll take precedence over the type entry without affecting siblings.

### Companion Mod Coordination

Cosmetics_tweaker has its own scale system (`_unit_path_scale_overrides`, model-path-keyed via `string.find` against the resolved `spawn_data[i].unit_name`) — see `cosmetics_tweaker/DEVELOPMENT.md` "Weapon Scale Overrides". Both mods' hooks stack via VMF; CWV's transforms are item-type-keyed (cwv items only) and cosmetics' are model-path-keyed (any item using a flagged model), so they don't collide as long as the type-level CWV tune doesn't deliberately mimic a model the cosmetics path is also scaling.

### Axis reference (Stingray/VT2)

| Axis | Effect | Notes |
|------|--------|-------|
| X | Width/thickness | Bretonian longsword's wide axis (`_breton_sword_thiccc = {0.65, 1, 1}` thins X) |
| Y | Width/thickness | Imperial greatsword's wide axis (Imperial Longsword type uses Y for thinning) |
| Z | Length | Blade length along the weapon. `+Z` grip offset lowers grip toward hilt; `-Z` raises toward blade tip (`feedback_grip_offset_sign.md`) |

The "wide axis" is model-specific: different unit authoring rotates the mesh differently, so X-vs-Y for "width" needs to be checked per family. Length (Z) is consistent across the families surveyed so far.

## Bayonet / fixed-attachment child units (linked-mesh decorations)

A weapon variant can carry an extra mesh "welded" onto its main rifle/sword/etc. — a bayonet on a musket, a tassel on a sword, a chain on an axe. The mechanism is `World.link_unit`, the same Stingray pattern the Tuskgor Javelin uses for its carrier visual. Compared to baking the decoration into a custom `.unit` file (which would mean shipping a binary asset), the linked-unit approach uses only existing vanilla units + Lua glue.

### Setup pattern

1. **Pick the decoration unit.** Any vanilla `units/weapons/player/<name>` unit works as the child. Both the 1P (`<name>`) and 3P (`<name>_3p`) variants need to exist (verify in `scripts/network_lookup/inventory_package_list.lua`).

2. **Force-load both packages at mod init** via `Managers.package:load(unit_path, ref, nil, async=true, prioritize=true)`. The decoration unit lives in a vanilla package that may not be loaded for this character (e.g. a Kerillian sword used as a Kruber bayonet). Without force-load, the spawn crashes "Resource not loaded" — same family of issue as `feedback_cwv_cross_character_unit_packages.md`. The 3P variant is a **separate package** at `<unit_path>_3p`; load both.

3. **Hook `GearUtils.spawn_inventory_unit`**, gate on the parent's template (template-table reference comparison: `item_template == Weapons.<your_template>`, NOT `item_data.name` — cwv variants inherit base weapon name per `feedback_cwv_clone_name_clobber.md`). The hook is called once per hand on every weapon spawn; gate on `hand == "right"` (or whatever) and on the template.

4. **Spawn the child unit**, then call `World.link_unit(world, child, 0, parent, 0)` to lock the child to the parent's root node. After link, set `Unit.set_local_position`, `Unit.set_local_rotation`, and `Unit.set_local_scale` on the child to position it relative to the parent.

5. **Track the parent → child pair in a weak-keyed table** so visibility and cleanup hooks can find the child later. Also stash via `Unit.set_data(parent, "<key>", child)` for the cleanup hook to find without iterating the table.

6. **Visibility sync**: `World.link_unit` propagates **transforms** but NOT visibility. When the player swaps weapons, vanilla calls `Unit.set_unit_visibility(parent, false)` on the unwielded units (it doesn't destroy them — they're just hidden). The linked child stays fully visible floating in space unless we mirror visibility. Hook `mod:hook_safe("SimpleInventoryExtension", "_wield_slot")` and walk the tracked-pairs table; for each pair, set the child's visibility based on whether the parent matches `equipment.right_hand_wielded_unit` (or `_3p`).

7. **Cleanup**: hook `GearUtils.destroy_wielded` to read the data slot and `Managers.state.unit_spawner:mark_for_deletion(child)`. Important: `mark_for_deletion` is **async** (queues for end-of-next-frame). Call `Unit.set_unit_visibility(child, false)` BEFORE marking for deletion or the child renders for one extra frame at its last world position (the "floating bayonet" symptom).

8. **Idempotent attach**: the spawn hook can fire twice on the same parent unit (e.g. cosmetic application that refreshes equipment without going through `destroy_wielded`). Make `_attach` skip if a child is already tracked for the parent — otherwise the second attach orphans the first child. Also have the visibility-sync hook destroy "orphan" children (parent dead, child alive) as a defensive cleanup.

### Axis convention notes (from the musket bayonet saga)

For Kruber's empire-handgun rifle (`wpn_empire_handgun_t1`) the local axes are:
- **+Y** = barrel direction (the axis the rifle's `_type_transforms` Y-scale stretches along)
- **+Z** = "up" perpendicular (positive Z places the child above the rifle)
- **+X** = side perpendicular

For Empire 1H sword meshes (`wpn_emp_sword_*`), the blade extends along the model's **+Y**. Mounting the blade along the rifle's barrel needs `Quaternion.axis_angle(Vector3(1, 0, 0), -π/2)` (rotate -90° about local X — swings model +Y to point along rifle +Y... wait, see history below for the actual finding).

The right convention is empirically derived per mesh family — there's no universal rule. The musket bayonet went through 5+ iterations before landing on `position {0, 0.76, 0.025}` + `rotation axis_angle(X, -π/2)` for the held pose.

## Stance toggle via runtime template swap

The musket variant has TWO templates registered on `Weapons.*`:
- `musket_template` — ranged (handgun shoot)
- `musket_template_melee` — clone of a melee template (Kruber's tuskgor spear in this case)

Pressing the special key (action_three) swaps the player's wielded weapon between the two templates. Vanilla doesn't natively support stance toggling, so we implement it by **destroying and re-creating the slot's equipment** with a different template returned from a `BackendUtils.get_item_template` hook.

The idle root scan can start `action_three`, but it is not consulted while a
weapon action owns the extension. `_cwv_old_musket_interrupt` therefore installs
one `{action/input = "action_three", sub_action = "default", start_time = 0,
clear_buffer = true}` entry in every non-toggle Old Musket sub-action. This is
the native Rapier/career-interrupt pattern: `WeaponUnitExtension:start_action`
finishes the same-hand action with `new_interupting_action` before starting the
dummy toggle. Preserve all existing chains, make installation idempotent, and
do not use `clear_input` (the helper reads `clear_buffer`). The action itself is
excluded to prevent a buffered special from self-chaining during teardown.

### Components

1. **Per-item stance flag** at `item_data.mod_data.cwv_<variant>_stance` ("ranged" / "melee"). Stored on the IML entry's `mod_data` (a CWV convention used by `_build_entry`); persists across wield/unwield because the IML entry isn't recreated.

2. **`action_three.default`** on each template: `kind = "dummy"`, `total_time = ~0.4`, with an `enter_function` that calls a stance-toggle helper. The helper:
   - Reads + flips the stance flag on `item_data.mod_data`
   - **Captures current ammo** via `ammo_extension:total_ammo_fraction()` BEFORE destroying the slot (otherwise the new spawn refills to max — every toggle = free reload)
   - Calls `inv:destroy_slot(slot, true)` → `inv:add_equipment(slot, item_data, nil, nil, ammo_fraction)` → `inv:wield(slot)`. The 5th arg to `add_equipment` is the ammo percent passed through to the new equipment.

3. **`BackendUtils.get_item_template` hook**: when `add_equipment` re-runs `create_equipment`, it calls `BackendUtils.get_item_template(item_data)` to look up the template. Our hook intercepts: if the item is the variant AND `mod_data.<stance> == "melee"`, return `Weapons.<variant>_melee`; otherwise return the ranged template. The recreated weapon spawns with the swapped moveset.

4. **`lookup_data` attach** on every sub-action of the cloned templates. Vanilla `weapons.lua:305-312` walks every action.sub_action of every `Weapons[<key>]` entry at boot and attaches `lookup_data = { item_template_name, action_name, sub_action_name }`. Our mod-loaded templates miss that pass — without the manual attach, the chain selector's `resolve_action_selector` crashes "attempt to index field 'lookup_data' (a nil value)" the first time the template is touched.

5. **Force-load alternate template's state machine**. The melee template's state_machine path (e.g. `units/beings/player/first_person_base/state_machines/melee/polearm`) is loaded for the character only when their loadout includes a weapon using it. Add it to `inventory_package_list.lua` to verify the path is loadable, then `Managers.package:load` at mod init. State machines DO load via the per-asset synthetic package mechanism, same as units.

6. **Override `display_unit` on the alternate template** to a Kruber-loaded rig (e.g. `display_1h_handguns`). The cloned template's inherited `display_unit` may live in another character's package and isn't always loadable as a standalone path (verified via `inventory_package_list.lua`). The previewer's job is to spin the wielded mesh on a stage; any rig that's loaded works visually.

### Per-template runtime overrides (rotation, position, scale)

The cloned melee template uses a different `attachment_node_linking` than the ranged template (e.g. `polearm` vs `pistol.right`), so the rifle ends up in a different orientation when wielded in melee mode. Apply corrections in the `GearUtils.spawn_inventory_unit` hook, gated on `item_template == Weapons.<melee_template>`:

- **Rotation**: `Quaternion.axis_angle(...)` to rotate the rifle so the receiver/stock face the right way. Compose with multiple axes via `Quaternion.multiply(q1, q2)` (q2 applied first in local frame, then q1 on top). For Kruber's polearm grip the musket needs `q_y * q_z` where both are `+π/2`.
- **Position**: read current local position (set by attachment_node_linking), ADD a delta, set back. Compose-friendly so the polearm offset isn't fought.
- **1P-only scale-down**: handheld view often reads too large in a polearm grip. Apply additional scale to `v_w1p` only, by reading current scale (set by the type-level transform at `GearUtils.create_equipment` hook time) and multiplying. 3P stays at the type-level scale so other players see the normal-sized weapon.

All three apply AFTER the type-level CWV transforms run (CWV transforms fire from `create_equipment`; our overrides fire from the later `spawn_inventory_unit`), so they compose correctly without fighting the existing scale logic.

### Floating-bayonet failure modes (and fixes)

Three distinct ways the bayonet can render where it shouldn't:

| Symptom | Cause | Fix |
|---|---|---|
| Bayonet visible after weapon swap | `Unit.set_unit_visibility` on parent doesn't propagate to linked child | `_wield_slot` post-hook: walk tracked pairs, set child visibility per parent |
| One-frame "floating bayonet" after stance toggle | `mark_for_deletion` is async; child renders at last world position for one frame | Call `Unit.set_unit_visibility(child, false)` BEFORE `mark_for_deletion` |
| Extra bayonet on ranged equip ("orphan") | A code path bypasses `destroy_wielded` (cosmetic application, equipment refresh) and re-fires our spawn hook on the same parent → second bayonet attached, first orphans | (a) Make `_attach` idempotent: skip if pair already tracked for the rifle. (b) `_wield_slot` post-hook also destroys orphans (parent dead, child alive) as defensive cleanup |

## Husk rendering path

The single most misdiagnosed CWV surface. A variant that looks and behaves
perfectly for the LOCAL wielder and their BOTS can be invisible, wrong-mesh,
wrong-scale, or carry an extra ammo mesh on a REMOTE player's screen (a
"husk"). See `docs/BUG_CLASSES.md` class 27 for the umbrella. This section is
the mechanism + doctrine + the per-variant coverage audit.

### Mechanism — the husk only ever sees the BASE item

CWV variants keep `entry.name = base_weapon` (the clone-name-clobber;
clobbering it to the cwv key crashes the owner equip path — see "Naming flow
for cwv variants" and `feedback_cwv_clone_name_clobber.md`). The equipment RPC
encodes an item as `NetworkLookup.item_names[item_data.name]`, so the wire
carries the **base weapon key**, plus a separately-synced **skin name**.

On the receiving client, `SimpleHuskInventoryExtension.add_equipment`
(`simple_husk_inventory_extension.lua:185`) does `item_data =
ItemMasterList[item_name]` — the VANILLA base entry — and stores
`{ item_data = <base>, skin = <skin_name> }`. The husk therefore knows nothing
about the CWV instance: no `cwv_variant` marker, no `cwv_<key>_001`
backend_id. **The only husk-reachable positive signals are the synced skin
name and a base+career inference.**

Two spawn paths, only one of which husks take:

| Path | Entry | Discriminator | CWV apply lives in |
|---|---|---|---|
| Owner / bot | `GearUtils.create_equipment` | has a 1P rig | the create_equipment hook (owner transforms, etc.) |
| **Husk (remote)** | `SimpleHuskInventoryExtension._wield_slot` -> `GearUtils.spawn_inventory_unit` | `owner_unit_1p == nil` | the `spawn_inventory_unit` hook, husk block gated on `not owner_unit_1p` |

Consequence: **any fix written only on the owner path, or that reads
`item_data.backend_id` / `.cwv_variant`, is invisible to husks.** Husk fixes
must live in the `spawn_inventory_unit` hook and resolve via positive signals.

### Residency doctrine — force-load the OVERRIDE units, not the base

The mesh a husk actually spawns for a curated variant is the **synced skin's**
per-hand units. `_register_variant_skins` sets `skin.right_hand_unit =
def.right_hand_unit` and `skin.left_hand_unit = def.left_hand_unit`, so **the
curated skin's meshes ARE the def's override units.** When those override units
are non-resident on a client not playing the source character, the skin-path
spawn fails and the husk shows the base mesh (or nothing) — issues 396 / 401.

The client auto-loads the package for the synced *base* name, so:

- **Override DIFFERS from base** -> the base package loads the WRONG mesh; the
  override package is NOT auto-loaded (the wire name is the base). The override
  units must be **force-loaded** to be resident. (27 of 30 variants.)
- **Override EQUALS base, or no override** -> the base name loads the correct
  mesh; nothing extra to force-load. (musket / rapier / crossbow — the base IS
  the intended appearance.)

The v0.1.367-dev residency pass is **data-driven**: it walks every def and
force-loads any `right_hand_unit` / `left_hand_unit` (+ its `_3p` form) that
differs from `rawget(ItemMasterList, base_weapon)`'s same field, via one shared
predicate `_om._husk_override_unit_needs_residency` (the regression test asserts
against the SAME predicate, so a new variant is covered by construction). It is
**boot-time, at the keep, a bounded ~23-unique-mesh deduped ref-held set** — NOT
a mission-load blanket force-load (that is the wt+cosmetics 1 GiB Lua-heap crash
class). The invisible-weapon sentinel (javelin right hand) is skipped.

Two things are intentionally KEPT alongside it:
1. The `dr_shield_axe` base-unit force-load = the issue-280 **crash floor** for
   the no-skin base-path spawn (a race / hot-join can spawn the base units
   before the package lands).
2. The `SimpleHuskInventoryExtension.start_weapon_fx` nil-slot guard = the
   **durable crash net** protecting ANY husk weapon from the
   `equipment.slots[nil]` CTD, independent of residency.

### Positive-signal rule (mesh + transform + ammo) — v0.1.377-dev (#474/#475)

Husk mesh re-key AND transform fallback route through ONE decision point,
`_om._husk_resolve_display_def(base, career, skin)`, with this order:

1. **Wire skin PRIMARY.** A skin in either def-keyed cwv namespace — base
   `<item_key>_skin` or pairing `<item_key>_<tail>` (lazy longest-prefix,
   cached) — positively identifies the variant: re-key mesh + apply the def's
   transforms REGARDLESS of `can_wield` (#474: the old can_wield-excluded map
   could never fire for the Old Musket because vanilla `es_handgun.can_wield`
   already contains the Kruber careers). The skin template's own per-hand
   units beat the def defaults, so pairing skins keep their exact shield/sword
   combination. Residency still gates the write: vanilla overrides via the
   shared resident-3p guard (#403/#418), the mod-bundled Old Musket mesh via
   `_om._husk_custom_bundle_unit` (always resident; force-loading it is the
   #403 boot fatal). Exceptions by design: the cross-source illusion families
   named OUTSIDE any def's item_key (`cwv_il_es/wh_*`, `cwv_es_priest_es/wh_*`)
   don't resolve here — their skin data already drives the display and they
   carry no def transforms; the decline log wording marks them as cwv-family,
   not native. NOTE (review finding): this arm is fed by today's skin wire
   LEAK — the null-on-wire hook covers only base `_skin_keys` on
   `game_object_initialized`, so pairing skins (and resync/hot-join base
   skins) reach cwv clients un-nulled. A future all-sender null (the
   cosmetics #421 treatment) MUST be peer-parity-gated or this arm goes dark.
2. **A present NON-cwv skin NEVER re-keys** (#475 Invariant 1). A native item
   virtually always carries a vanilla/LA skin on the wire; mis-applying a
   variant to it (the falsified "can never mis-apply" claim of the boot-time
   map) is strictly worse than a variant degrading to base display.
3. **Skinless echoes only** fall back to the base+career positive inference,
   with `can_wield` evaluated LAZILY at wield time (`_om._husk_pair_native_now`)
   — the boot-time snapshot predated weapon_tweaker's can_wield patches (#475's
   second hole). A currently-wieldable pair declines: the shape is ambiguous
   between a wt-freedom native wield and a variant echo, and ambiguous shows
   base. The skinned wield that follows still re-keys via arm 1.

`backend_id` on the husk is always the base's, so it never resolves a cwv key.

- **Ammo strip** (issue 399) still uses the boot-built base+career inference:
  a base weapon on a career that CANNOT natively wield it (dwarf-exclusive
  `dr_deus_01` on a Kruber = only the CWV Outrider). Gated on `(item_data.name
  == base) AND (career in the variant's careers)` so a genuine dwarf wielding
  the real Trollhammer is never touched. KNOWN residual (surfaced during the
  #474/#475 fix, not changed): under wt freedom a non-dwarf CAN wield the
  native Trollhammer, and the strip would wrongly hide its torpedo on
  observers' screens — same false-positive class as #475, cosmetic-only.

**Stays broken until #392:** anything that needs the husk to resolve the CWV
INSTANCE when NO cwv skin is on the wire — every cim-CRAFTED copy (no skin),
and any default-rarity blacksmith template equipped without an applied illusion
(pending in-game confirmation of whether its skin survives sync). The throttled
`[cwv husk-transform] no cwv def resolved` log is the evidence arm that names
which equips fall through. #392 is the fix: put a net-safe cwv marker / skin on
the wire so the husk can see the instance.

### Per-variant husk coverage audit (v0.1.367-dev)

30 defs. "Override vs base": whether the def's per-hand override mesh differs
from the base weapon's — the residency trigger. "Husk transform": whether the
variant has a scale/offset (def- or type-level) and how it resolves on the husk.

| Variant | Base | Override vs base | Residency (issue 396/401) | Ammo (399) | Husk transform (397) |
|---|---|---|---|---|---|
| cwv_es_axe_shield | dr_shield_axe | DIFFERS (R+L) | force-loaded | - | none |
| cwv_es_axe_shield_veteran | dr_shield_axe | DIFFERS (R+L) | force-loaded | - | none |
| cwv_we_sword_shield | es_sword_shield | DIFFERS (R+L) | force-loaded | - | none |
| cwv_we_sword_shield_veteran | es_sword_shield | DIFFERS (R+L) | force-loaded | - | none |
| cwv_es_longsword | es_bastard_sword | DIFFERS (R) | force-loaded | - | type; **default-rarity — resolves only if skin syncs (#392 risk)** |
| cwv_es_longsword_blackguard | es_bastard_sword | DIFFERS (R) | force-loaded | - | type; resolves w/ skin |
| cwv_es_longsword_nordland | es_bastard_sword | DIFFERS (R) | force-loaded | - | type; skin_only illusion — resolves when applied |
| cwv_es_longsword_shield | es_sword_shield_breton | DIFFERS (R+L) | force-loaded | - | type; resolves w/ skin |
| cwv_es_javelin | we_javelin | DIFFERS (L; R=invis sentinel) | force-loaded (boar spear) | - | def; resolves w/ skin |
| cwv_wh_javelin | we_javelin | DIFFERS (L; R=invis sentinel) | force-loaded (boar spear) | - | def; resolves w/ skin |
| cwv_es_outrider_grenade_launcher | dr_deus_01 | DIFFERS (R) | force-loaded | **strip (no_ammo_unit)** | none |
| cwv_es_musket | es_handgun | same (R) | none needed (base loads) | - | type; SCALE needs skin (skinless = native scale) |
| cwv_es_musket_old | es_handgun | DIFFERS (R, MOD-BUNDLED custom mesh) | EXCLUDED from force-load (mod-bundle = always resident; loading it is the #403 boot fatal, BUG_CLASSES 28) | - | none (native-authored scale) |
| cwv_dr_priest_greathammer | wh_2h_hammer | DIFFERS (R, dwarf mesh) | force-loaded | - | none |
| cwv_es_priest_greathammer | wh_2h_hammer | DIFFERS (R) | force-loaded | - | none |
| cwv_es_warpriest_hammer | wh_1h_hammer | DIFFERS (R) | force-loaded | - | none |
| cwv_es_maul | bw_1h_mace | DIFFERS (R) | force-loaded | - | type; resolves w/ skin |
| cwv_es_greataxe | dr_2h_axe | DIFFERS (R; custom manifest) | force-loaded | - | manifest model; resolves w/ skin |
| cwv_es_rapier | wh_fencing_sword | same (R) | none needed (base loads) | - | type; SCALE needs skin (skinless = native scale) |
| cwv_es_crossbow | wh_crossbow | no override | none needed (base loads) | - | none |
| cwv_es_dual_swords | we_dual_wield_swords | DIFFERS (R+L) | force-loaded | - | def; resolves w/ skin |
| cwv_es_sword_and_mace | es_dual_wield_hammer_sword | DIFFERS (R+L) | force-loaded | - | none |
| cwv_es_cudgel | es_1h_mace | DIFFERS (R) | force-loaded | - | none |
| cwv_es_shortsword | bw_dagger | DIFFERS (R) | force-loaded | - | def; resolves w/ skin |
| cwv_es_dual_axes | dr_dual_wield_axes | DIFFERS (R+L) | force-loaded | - | none |
| cwv_wh_dual_axes | dr_dual_wield_axes | DIFFERS (R+L) | force-loaded | - | none |
| cwv_es_dual_maces | dr_dual_wield_hammers | DIFFERS (R+L) | force-loaded | - | none |
| cwv_wh_dual_maces | dr_dual_wield_hammers | DIFFERS (R+L) | force-loaded | - | none |
| cwv_es_dual_warpriest_hammers | wh_dual_hammer | DIFFERS (R+L) | force-loaded | - | def; resolves w/ skin |
| cwv_es_warpriest_hammer_shield | wh_hammer_shield | DIFFERS (R+L) | force-loaded | - | def; resolves w/ skin |

**Residency:** 27 of 30 force-loaded by the data-driven pass; 3 (musket,
rapier, crossbow) need none because the synced base name already loads the
correct mesh. **Ammo:** 1 strip (outrider), disambiguated by dr_deus_01 being
dwarf-exclusive; no other base carries an ammo mesh the variant should hide
(crossbow legitimately shows bolts). **Transform:** resolves on the husk only
when the curated skin syncs; the standout risk is `cwv_es_longsword` (default
rarity + override-differ — if its skin does not survive sync the husk shows the
base bastard-sword at native scale), plus every cim-crafted copy of any
variant. Those await #392.

## Known Errors / Gotchas

A consolidated catalog of CWV-specific failure modes that have shipped
and been fixed. Skim this before authoring a new variant; check it
first when an existing variant suddenly breaks.

### Item identification — always go through `backend_id`, never `item_data.key`

For items registered via MoreItemsLibrary (every `cwv_*` item),
`item_data.key` returns the **BASE weapon key** (e.g.
`es_bastard_sword`), NOT the custom CWV item_key (e.g.
`cwv_es_longsword_veteran`). Same for `item_data.name`. The custom
identity lives in `item_data.backend_id`, formatted as
`<item_key>_<3-digit-instance>` (e.g. `cwv_es_longsword_veteran_001`)
— **but only for CWV's own instances and cim standard-forge crafts.**
A cim **Athanor** craft mints `Application.guid()` (a UUID) as the
backend_id, which no pattern match can decode (issue 482: crafted
the former Poleaxe lost its scale/grip on every owner-side path).

**Always resolve through the shared ladder, never a bare regex:**
```lua
local cwv_key = _om._cwv_key_for_item(item_data.backend_id, item_data)
if cwv_key and _my_lookup_table[cwv_key] then
    -- found, use cwv_key
end
```
The ladder tries: (1) the `cwv_<key>_NNN` bid pattern, (2) the
`item_data.cwv_key` field `_build_entry` stamps on every IML clone
(survives vanilla's `table.clone` in `get_item_from_masterlist`),
(3) a backend `get_item_from_id(bid)` hop for callers that only carry
the bid (previewer `_item_info_by_slot`). Guarded by the
`cwv_key_resolution_uuid_safe` regression check.

**Why:** this bug has bitten at least four code paths (animation
weapon-tracking via ActionWield, model scale/offset transforms via
`GearUtils.create_equipment`, preview transforms via
`HeroPreviewer._spawn_item`, and the v0.1.317 multi-instance preview
regex). Each time, items appeared to "work" because the function was
called but the lookup silently failed (`_lookup[base_key]` returns
nil), so visuals/animations stayed at vanilla defaults — looking like
the variant didn't take effect. Variants without custom transforms
(e.g. shield variants without scale) masked the bug because they
didn't need the lookup.

**Critical: match `_%d%d%d$`, NOT `_001$`.** Variants with
`def.instances = N` (introduced v0.1.271 for `cwv_es_musket` /
`cwv_es_musket_old` to give the player N copies) generate
backend_ids `_001`, `_002`, ..., `_NNN`. A hardcoded `_001` regex
silently returns nil for instance 2+, the resolver exits early, and
the previewer-side texture + transform binding is skipped. Symptom:
the second backend instance displays in the inventory previewer with
no textures and no scale/grip applied — looks like a white
default-stage version. Burned in v0.1.317 (2026-05-12); affected
every multi-instance variant since v0.1.271. Audit other reverse
lookups via `Grep "backend_id:match" character_weapon_variants/`.

**Diagnostic:** when adding a `mod:info` debug log on a per-item
lookup, include the resolved cwv_key — silent lookup failures are
how this bug class hides. For preview hooks where backend_id isn't a
direct argument, iterate `self._item_info_by_slot` and match each
entry's `backend_id`.

### CWV inventory previewer uses the BASE template, not the cwv clone

The inventory previewer (`world_hero_previewer.lua` `equip_item`)
resolves weapon templates via:

```lua
local item_template = ItemHelper.get_template_by_item_name(item_name)
-- which does: ItemMasterList[item_name].template -> Weapons[template_name]
```

`item_name` here is the **base weapon key** (per the backend_id
lookup rule above — CWV items inherit `entry.name = base.name`), so
the previewer reads `Weapons.<base_template>` — NEVER our cwv clone.
**Modifying the cloned template alone does nothing for the inventory
preview.**

Symptoms are silent: the menu previewer plays the wrong wield
animation (or none, leaving the character in the previous weapon's
pose), without errors. In-game works fine because
`simple_inventory_extension.lua` reads `item_data.template` directly
from the slot data (which IS our cwv entry).

**How to apply:** any template-level modification needed for the
inventory preview path (especially `wield_anim_career_3p`,
`wield_anim_career`, idle/state-machine fields,
`<hand>_hand_attachment_node_linking` for hand-mount-flip variants)
must also be applied to the **base** template. Scope to a
career-keyed table so vanilla wielders of the base template fall
through unchanged:

```lua
local base = Weapons.one_handed_sword_shield_template_1
base.wield_anim_career_3p = base.wield_anim_career_3p or {}
for k, v in pairs(my_elf_careers_to_event) do
    base.wield_anim_career_3p[k] = v
end
```

History: v0.1.44 added `wield_anim_career_3p` to the cloned
template, didn't fix the menu pose. v0.1.48 patched the base
template, fixed it. v0.1.181 (`cwv_es_outrider_grenade_launcher`)
hit the same trap for `right_hand_attachment_node_linking` — see
"BASE template patching for previewer compatibility" above.

### CWV projectile system reads the BASE template at runtime

**For any cwv weapon that fires a projectile (javelins, throwing
axes, future thrown variants), do NOT clone the weapon template
under a renamed key and expect the projectile system to use it.**

`PlayerProjectileUnitExtension.init` reads
`ItemMasterList[item_name].template` at projectile init, where
`item_name` is the BASE weapon key. A renamed clone (e.g.
`tuskgor_javelin_template` cloned from `javelin_template`) is **dead
code at runtime** — the engine never looks it up for projectile
spawning.

The wield-time path (which DOES use the cloned template via
`item_data.template`) explains why `max_ammo` works on the clone but
`link_pickup`, projectile speed, and impact_data do NOT — those
latter live on the action sub-table the projectile init reads via
the BASE lookup.

**Two valid options:**

1. **Mutate the base template in place.** Affects ALL wielders of
   that base weapon — only acceptable if every variant should share
   the modification.
2. **Clone-and-swap with a runtime hook** (cwv-friendly). Hook
   `PlayerProjectileUnitExtension.init` post-vanilla, look up the
   projectile's owner's `slot_ranged` slot_data, and if the cwv
   skin matches, swap `self._current_action`, `self._impact_data`,
   `self.projectile_info`, and `self._impact_damage_profile_id` to
   point at the cloned template's sub-action.

**Critical detection field:** `slot_data.skin` carries the cwv
prefix at runtime, NOT `slot_data.id` (slot name like
`"slot_ranged"`) or `slot_data.backend_id` (nil at this layer). Use
`bid:match("^cwv_.+_javelin_skin$")` or similar. v0.1.106 diagnostic
dump confirmed this.

**Burned 30+ versions** (Tuskgor Javelin, 2026-05-06 → 2026-05-07).
v0.1.65 onward shipped a cloned `tuskgor_javelin_template` with
stat tweaks, impact_data swapped, custom damage profiles. v0.1.96
diagnostic confirmed every javelin throw at runtime logged
`tmpl=javelin_template` (BASE) and `link=true link_pickup=nil`
(BASE values). 30+ versions of "fixes" — rotation cleanup hooks,
husk-lookup injection, stick-and-pickup behavior swap, in-flight
projectile model swap — were ALL applied to the cloned template
that was unused at projectile-spawn time. Diagnosis only landed
once we hooked `_handle_linking` unconditionally and saw
`tmpl=javelin_template` in the log.

Workflow: build the runtime `init` hook FIRST (before adding any
impact_data / projectile_speed / damage_profile changes to the
clone). Verify with a `[cwv stick] init post-fix swap` log line per
throw. Without that line firing, your clone's projectile-side
fields are dead code.

### Ammo weapons need full skin field mirroring

When creating a variant whose `base_weapon` is an ammo weapon
(`is_ammo_weapon = true`, e.g. `we_javelin`), the custom skin entry
registered in `_register_variant_skins` MUST mirror multiple fields
from the base ItemMasterList entry — not just `ammo_unit`.

**Why:** `BackendUtils.get_item_units`
(`scripts/managers/backend/backend_utils.lua:174-180`)
unconditionally overwrites a whole set of fields on `units` from
`skin_template` whenever a skin is set:

```lua
left_hand_unit            = skin_template.left_hand_unit
right_hand_unit           = skin_template.right_hand_unit
ammo_unit                 = skin_template.ammo_unit
ammo_unit_3p              = skin_template.ammo_unit_3p
projectile_units_template = skin_template.projectile_units_template
pickup_template_name      = skin_template.pickup_template_name
link_pickup_template_name = skin_template.link_pickup_template_name
icon                      = skin_template.hud_icon
material_settings_name    = skin_template.material_settings_name
```

Anything absent on the skin becomes nil — even though the base IML
had a valid value. Downstream paths nil-cascade:

- **Equip / previewer crash** — `world_hero_previewer.lua` does
  `left_hand_unit = item_units.ammo_unit; left_unit = left_hand_unit
  .. "_3p"` for `is_ammo_weapon` items. nil ammo_unit → "attempt to
  concatenate local 'left_hand_unit' (a nil value)".
- **Throw / pickup crashes** — nil `projectile_units_template` /
  `pickup_template_name` breaks projectile spawn and on-ground
  pickup spawn.

**How to apply** (since v0.1.64): `_register_variant_skins` already
mirrors all five fields with `def.<field> or base.<field>` fallback,
where `base = ItemMasterList[def.base_weapon]`. When adding a NEW
ammo-weapon variant:

- Set `def.left_hand_unit` to the held model's 1P path (the
  previewer concatenates `_3p`, so the asset's `_3p` sibling must
  exist in a loaded package — verify in
  `dlcs/<dlc>/<dlc>_equipment_settings.lua` package list).
- If the held model and the thrown projectile should differ, set
  `def.ammo_unit` explicitly; otherwise the fallback uses
  `left_hand_unit` (gated — see below).
- Don't override `projectile_units_template` unless you're also
  cloning the projectile config — the base entry's value (e.g.
  `"javelin"` → `Projectiles.javelin`) is the safe default.

**Diagnostic signal:** `_register_variant_skins` logs `Registered
custom skin: <key> (ammo_unit=..., projectile=...)`. If either is
`nil`, that code path will crash on use.

**Gate the fallback on the base actually using the field
(v0.1.184).** The original `ammo_unit = def.ammo_unit or
def.left_hand_unit` fallback was TOO BROAD — it forced an
`ammo_unit` value onto cwv variants whose base weapon doesn't use
one. Concrete case: `cwv_es_brace_repeater` (base
`wh_brace_of_pistols`). The brace template has `ammo_data.ammo_hand
= "right"` but no `ammo_unit` (vanilla brace doesn't attach a
visible ammo model). Our skin force-set `ammo_unit =
def.left_hand_unit` (the pistol mesh), triggering
`GearUtils.spawn_inventory_unit`'s gate
`if ammo_data and ammo_data.ammo_hand == hand and ammo_unit_name
then` → `fassert(ammo_unit_attachment_node_linking)` failed because
the brace template doesn't define it. Crash chain landed in
`simple_inventory_extension: attempt to index local
'slot_equipment_data' (a nil value)` (crash GUID `2df233ae`).

**The fix (current code):**

```lua
local ammo_unit = def.ammo_unit or (base.ammo_unit and def.left_hand_unit)
```

Only fall back to `def.left_hand_unit` when the BASE weapon's IML
has `ammo_unit`. Preserves javelin/spear behavior; nukes the
spurious ammo_unit on brace/pistol-family variants.

**General rule:** for ANY new `_register_variant_skins` fallback —
GATE on the base weapon actually using the assumed field. Don't
force a value into a field the base never used; vanilla downstream
code (assertions in `spawn_inventory_unit`, `world_hero_previewer`,
etc.) is built around the base's shape and breaks if cwv injects
unexpected non-nil values.

### Cross-character unit references need package loading

Generated dual weapons have an additional first-person residency invariant.
`ProfileSynchronizer` may snapshot the prior backend loadout's package set before
CWV's resynchronized equipment replaces it. The next `_wield_slot` immediately
installs the new template's state machine, so asynchronous loading or a
per-weapon special case is unsafe: engine C faults before Lua can recover.
Issue #586 therefore owns a closed catalog of all generated dual owners and the
five source-verified vanilla state-machine paths they resolve to (`dual_swords`,
`dual_hammer_sword_es`, `dual_axes`, `dual_hammers`, and
`dual_hammers_priest`). Add every new paired owner to that catalog and the
runtime receiver matrix in the same change; acquire each package synchronously
under one lifecycle-balanced CWV reference.

Vanilla queues inventory packages off the equipped item's
`right_hand_unit` / `left_hand_unit` and the item's `required_dlc`
chain. It does **NOT** walk every reference inside the template,
skin entry, or pickup_settings. Cross-character units sit in
packages keyed to ANOTHER character's kit, which only get loaded
when THAT character has the relevant item equipped.

**Manifests as:**
`Managers.state.unit_spawner:spawn_local_unit_with_extensions` or
`World.spawn_unit` called with an unloaded unit path crashes hard
(sometimes not pcall-catchable; sometimes returns nil; sometimes
throws engine-level errors that propagate up and wreck unrelated
state).

**Known incidents:**

- **Tuskgor Javelin (CHANGELOG v0.1.118):** `cwv_es_javelin` had
  `right_hand_unit = boar spear`, `left_hand_unit = boar spear`.
  The pickup template referenced `prj_we_javelin_01_3ps` (elf
  javelin pickup unit). On first throw, `World.spawn_unit` crashed
  because the elf javelin package wasn't queued. Resolution: use
  the boar spear unit for both the in-flight and pickup paths.
- **Brace-Repeater (cwv v0.1.180–0.1.183; recurred in
  weapon_tweaker v0.12.5-dev 2026-05-09):** cwv_es_brace_repeater
  had `right_hand_unit = pistol` and a per-perspective
  `right_hand_unit_3p_override = repeater_3p`. The repeater
  package wasn't queued for a brace equip; spawning the repeater
  3P unit crashed the equip. After functionality migrated to
  weapon_tweaker, the same crash recurred at GUID d9e1d3d3 the
  first time Kruber equipped the brace. Fix: force-load the
  repeater 3P unit at WT mod init via
  `Managers.package:load(_BRACE_REPEATER_3P_UNIT,
  "wt_brace_repeater_3p", nil, true, true)` (Tuskgor pup pattern),
  plus a `Managers.package:has_loaded` guard in the swap hook to
  fall back to vanilla brace 3P if the load hasn't completed yet.

**How to apply** — when writing a variant that references any unit
path from outside its `base_weapon`'s natural package:

1. **Cross-check the unit's package source.** Grep
   `Vermintide-2-Source-Code/scripts/settings/dlcs/<dlc>/<dlc>_equipment_settings.lua`
   and similar for the unit name. Confirm the package it lives in.
2. **If different from the variant's natural package**, choose one:
   - **Static dependency:** add the unit (or its package) to
     `resource_packages/character_weapon_variants/character_weapon_variants.package`.
     Always loaded; bloats the always-loaded set but simplest.
   - **Runtime force-load:** call `Managers.package:load(<package>,
     ...)` before the spawn, then `:unload(<package>, ...)` on
     unequip. Tighter memory footprint; more code.
   - **Avoid the cross-character reference:** if the cosmetic
     effect can be achieved using units from the variant's natural
     package, prefer that (Tuskgor Javelin's resolution).
3. **Spot-check by equipping in-game.** A `World.spawn_unit` crash
   on first equip / first action is the smoking gun.

**Defensive coding** — if the cross-character unit MIGHT not be
loaded, wrap the spawn in pcall AND structure your hook so failure
falls back to a working state (vanilla unit, no swap, etc.) rather
than half-applying a broken state. The brace_repeater hook learned
this: spawn override FIRST, only destroy vanilla AFTER override
spawn succeeds. Otherwise a failed override leaves the equip with
no 3P unit.

### CWV variants must NOT clobber inherited `entry.name` / `entry.key`

In `_build_entry`, after `table.clone(base, true)`:

**DO NOT** override `entry.name` or `entry.key` — they're inherited
from the base weapon (e.g. `"es_bastard_sword"`) and downstream code
(`BackendUtils.get_item_units`, equipment pipeline) does
`ItemMasterList[item.name]` lookups that fall back to the base
weapon's data. If you set `entry.name = def.item_key`, those
lookups return nil because cwv items are added via MIL
`add_mod_items_to_local_backend` (NOT to ItemMasterList) — instant
crash on equip with `backend_utils.lua: attempt to index local
'item_data' (a nil value)`.

**DO** add a marker field:
```lua
entry.cwv_variant = true
```

Then sibling mods (`cosmetics_tweaker`, `weapon_tweaker`) gate
`item_data.name`-keyed lookups on it:
```lua
if result and item_data and not item_data.cwv_variant then
    _scale_units(result, item_data.name, career_name)
    _offset_units(result, item_data.name, career_name)
end
```

**Why both halves matter:**
- Inheritance is load-bearing for backend lookups — clobbering it
  breaks equip.
- WITHOUT the flag/skip, sibling mods' weapon-name-keyed overrides
  leak onto cwv variants. Concrete case: `es_bastard_sword_thiccc =
  true` in cosmetics_tweaker scaled `cwv_es_longsword` to `{0.65,
  1.0, 1.0}` (paper-thin) because the cosmetics_tweaker GearUtils
  hook used `item_data.name == "es_bastard_sword"` to match.

**Hooks that still need the flag gate** (item-name-keyed paths in
sibling mods):
- `GearUtils.create_equipment` (in-game render — most visible leak)
- `LootItemUnitPreviewer.spawn_units` (skin browser)
- `_spawn_item_post` (HeroPreviewer/MenuWorldPreviewer) is already
  safe — it matches by `item_name` parameter (the cwv item key,
  not inherited name)

**Update 2026-05-01 evening:** cosmetics_tweaker (v0.7.87+)
migrated its **scale** system from item-name-keyed to
unit-path-keyed (`_unit_path_scale_overrides`, substring match
against the resolved model path). The `cwv_variant` flag remains
load-bearing for grip-offset, hat tinting, and LA-paint paths
(still item-name-keyed) on the `GearUtils.create_equipment` hook.

**Update 2026-05-05 (v0.7.98):** menu hooks no longer use the
`cwv_variant` gate at all. Root cause of the open issue: menu
hooks (`HeroPreviewer/MenuWorldPreviewer._spawn_item`,
`LootItemUnitPreviewer.spawn_units`) had been resolving paths via
`item_data.right_hand_unit` + a separate `info.skin_name` →
`WeaponSkins.skins[…]` lookup, redundant with what vanilla had
already computed. Switched both menu hooks to read paths straight
from `spawn_data[i].unit_name` — vanilla `equip_item` /
`_load_item_units` populates that field after calling
`BackendUtils.get_item_units`. That's the only truth source for
"what unit IS being rendered in this slot right now." A cwv item's
`unit_name` is always its variant model, so it can't accidentally
match a base-weapon pattern, which made the gate redundant.
**Default contract for new sibling mods that hook menu paths:**
read paths from `spawn_data[i].unit_name`, never re-resolve. The
flag is still required for any item-name-keyed override
(offset/tint/LA-paint on the GearUtils path).

### Mod-shipped custom mesh paths cannot be `Application.resource_package` discovery targets

> **Current rule:** this section explains the global-discovery limitation, but
> its old blanket conclusion that the item must retain a vanilla unit path is
> superseded by the proven Greataxe bridge. New work must follow
> [`../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md`](../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md):
> flatten custom resources into an explicit master root, borrow a vanilla
> package only for preview lifetime tracking, and forward-alias both custom
> package names for ProfileSynchronizer without changing reverse lookup.

VT2 modding does **NOT** support shipping new resource paths that
are loadable via `Application.resource_package(path)`. **Custom
meshes must reuse a vanilla unit path** (LA's pattern), not invent
a new one.

**Why:** two separate resource registries exist:
- `Mod.resource_package(mod.handle, name)` — mod-scoped registry,
  used by `mod_manager.lua:421` to load each entry in `.mod`'s
  `packages = {...}`. Resources loaded this way are accessible
  WITHIN THE MOD but NOT globally findable.
- `Application.resource_package(name)` — global registry. Resolves
  paths to bundle files in the game's `bundle/` folder (vanilla
  content). Cannot see mod-scoped packages.

Vanilla code (e.g. `world_hero_previewer._load_packages`) calls
`package_manager:load(right_hand_unit .. "_3p", ...)` which routes
through `Application.resource_package`. So any `right_hand_unit`
path that isn't vanilla will crash there with `[Engine Error]:
Resource '#ID[<hash>]' not found!` where `<hash>` is the murmur64
of a mod-defined path.

**How to apply:** when adding a CWV variant with a custom mesh,
set `right_hand_unit` to a vanilla unit path (e.g.
`units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1`).
Then overlay your custom mesh via one of:
- **LA-style pattern:** author a `.unit` data block referencing a
  vanilla material; mod's PackageManager hooks intercept package
  loads. See `RECIPES.md` "LA custom-mesh pattern" recipe.
- **Bayonet pattern:** spawn a child unit linked to the vanilla
  unit (`World.link_unit`), hide the vanilla mesh via
  `Unit.set_unit_visibility`, force-load custom mesh's package,
  sync visibility across FP/3P. See "Bayonet / fixed-attachment
  child units" section above.

**Verified evidence (v0.1.275 crash):**
- LA mod ships 104 .unit + 149 .texture resources but ZERO sibling
  .package files. All its "custom" units are at vanilla paths.
- Vanilla rifle bundle `3c8a9acd3d48bc69` contains the .unit +
  .material directly — NO .package resource inside. The bundle
  FILE is the package.
- Adding sibling paths to .mod's packages list creates
  `.mod_bundle` files in workshop folder, but they're not
  engine-discoverable for `Application.resource_package`.
- v0.1.271–275 burned 4 versions trying every workaround.

**Don't waste time on:**
- Authoring sibling `.package` files. Doesn't help.
- Adding sibling paths to `.mod` `packages = {...}`. Doesn't help.
- Adding `package = [...]` to master `.package`. Compiles, but
  resources only accessible mod-scoped.

The shippable `cwv_es_musket` variant works because its
`right_hand_unit` is the vanilla
`units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1`.
The crash only hit `cwv_es_musket_old` (v0.1.271–276) because it
tried `units/cwv_es_musket_custom/cwv_es_musket_custom`.

## Thrown-pickup wire safety is a gameplay boundary

A vanilla fallback key can be safe to encode but mechanically incompatible.
The Tuskgor Javelin uses ammo type `throwing_javelin`; vanilla throwing-axe
pickups only interact with `throwing_axe`. Preserve the CWV recovery pickup
when peer parity is confirmed, and use the vanilla fallback only while parity
is unconfirmed. Never increase its tiny throwing-weapon `spawn_weighting` to
make it ordinary map loot; normal ammo crates already refill the finite stack.

## Build discipline — don't fabricate breakpoints

When proposing trait/property combos for new variants:

- **Never make up VT2 weapon breakpoint claims** (e.g. "this combo
  one-shot headshots Stormvermin on Cata"). They're patch-sensitive,
  depend on the exact talent stack, and the user has 4000h+ of
  empirical knowledge — fabricated numbers waste time and erode
  trust.
- **Crit-dependent breakpoints are NOT "reliable" unless paired
  with a guaranteed-crit talent.** Don't sell a crit chain as a
  reliable kill plan.
- **Damage and stagger breakpoints are separate tables.** Be
  explicit about which one a build is targeting.
- **Scope is regular Cataclysm only** (not C1/C3, per user
  2026-05-13).
- **If you don't know the breakpoint, say so plainly and ask.**
  Don't guess. Either:
  1. Ask the user what breakpoint they want to hit, then pick the
     combo that gets there.
  2. Check the Royale w/ Cheese community breakpoint spreadsheet
     (see below).

**Burned 2026-05-13** in the CWV "5 modded instances" planning
conversation: claimed Kruber axe+shield would one-shot headshot
Cata Stormvermin with Mercenary Paymaster + Swift Slaying. Wrong —
there is no reliable Cata SV one-shot-headshot breakpoint for 1H
axe+shield without crit. User had to correct multiple proposed
builds. The combos in the table were valid Lua, but the breakpoint
*justifications* were fiction.

### Royale w/ Cheese community breakpoint spreadsheet

The canonical breakpoint data for VT2 weapon/enemy damage and stagger
at every difficulty lives in a community-maintained spreadsheet,
typically attributed to / linked from Royale w/ Cheese's user guides.

- **Scope for CWV planning: regular Cataclysm only** (not C1/C3),
  per user 2026-05-13.
- Breakpoints are patch-sensitive and depend on the exact talent
  stack — the spreadsheet is the authoritative reference.
- Damage breakpoints and **stagger** breakpoints are separate
  tables — be explicit which one is in play.
- Don't assume a remembered breakpoint claim still holds across
  patches — verify before recommending.

**Specific URL not yet captured.** When planning a CWV instance
aimed at a specific breakpoint, ask the user for the spreadsheet
URL OR for the relevant breakpoint data ("what's the Cata X
breakpoint for Y with Z talents?").

## Reference: Base Weapon Keys

Use `ItemMasterList` keys (not `item_type`):
- `dr_shield_axe` (not `dr_1h_axe_shield`) — Bardin's axe and shield
- `dr_shield_hammer` — Bardin's hammer and shield
- `es_2h_sword` — Kruber's greatsword
- `wh_2h_sword` — Saltzpyre's greatsword
- `es_bastard_sword` — Kruber's Bretonnian Longsword (DLC: lake, template: bastard_sword_template)
- `wh_1h_axe` — Saltzpyre's one-handed axe

Full catalog: see `ITEM_LIST.md` in the repo root.

## #596 Infantry Spear reference implementation

`cwv_es_infantry_spear` is the canonical independently-scaled melee clone. Its behavior source is `two_handed_spears_elf_template_1`; its model source is the right-hand spear field of `es_deus_01` and that owner's seven skins [src: `spears_wood_elf.lua:1-4,1559`; `item_master_list_morris.lua:137-159`; `weapon_skins_morris.lua:144-267`]. `ActionUtils.get_action_time_scale` starts from `anim_time_scale or 1`, while action completion, chain windows, and sweep hit windows divide by that scale [src: `action_utils.lua:538-563`; `weapon_unit_extension.lua:477-490,930-936`; `action_sweep.lua:153-156,455-459`]. Accordingly, the helper scales only `melee_start` and `sweep`; it does not rewrite individual timestamps or unrelated block/push actions.

Damage, impact, and cleave remain separate `_clone_damage_profile` multipliers. Never scale the generic `damage_profile_inner`/`damage_profile_outer` push rows when a spec asks for weapon-hit tuning only.

## #597 Greataxe model-manifest implementation

`cwv_es_greataxe` replaces the retired Poleaxe family. Its gameplay template is a deep clone of `two_handed_axes_template_1` with no timing or damage-profile changes, preserving Bardin's Greataxe behavior exactly [src: `item_master_list_exported.lua:7298-7317`; `2h_axes.lua:1-1181`]. Kruber's four careers explicitly wield through `to_2h_hammer`; the action substitutions are copied from WT's `two_handed_axes_template_1` receiver map, not independently guessed [src: `weapon_tweaker/_wt_anim_remap_data.lua:31-38`; `weapon_tweaker/wt_wield_patches.lua:226`].

Converted third-party assets have one code-side seam: `_cwv_greataxe.lua` `MODELS`. A row is eligible only when `key`, provisional `display_name`, and `right_hand_unit` are non-empty. The first eligible row owns the generated base illusion; subsequent rows register as curated picker illusions. Keep license/source attribution with the converted asset metadata, and never add a row until its unit loads successfully.
## One-handed mace and hammer identity toggle (Issue #599)

`enable_cwv_mace_hammer_identity` is a default-on, hot-reversible gameplay
toggle. Its scope is an explicit semantic allowlist in
`_cwv_mace_hammer_identity.lua`; it never scans template names. Maces use
`anim_time_scale * 1.05` on attack-start, sweep, and shield-slam actions.
Hammers swap direct `kind = "sweep"` attacks to CWV-owned cloned
profiles with `power_distribution.attack * 1.125` and cleave attack/impact
capacity `* 0.75`. Impact power (stagger magnitude), ordinary push profiles,
charge actions, block, wield, and the original damage/power rows are untouched.

The mace family is `one_handed_hammer_template_1`,
`one_handed_hammer_wizard_template_1`,
`one_handed_hammer_shield_template_1`, and CWV's isolated
`cwv_dual_maces_template`. The hammer family is
`one_handed_hammer_template_2`, `one_handed_hammer_priest_template`, both
ordinary/priest hammer-and-shield templates, and both ordinary/priest Dual
Hammer templates. CWV's Warrior-Priest Hammer, Dual Warrior-Priest Hammers,
and Warrior-Priest Hammer and Shield inherit those hammer templates. All 2H
hammers, Maul, Hammer and Tome, and mixed Mace and Sword are deliberate
exclusions. Source provenance: VT2
`scripts/settings/equipment/item_master_list_exported.lua:6571,6673,7073,7350,7394`
and `item_master_list_carousel.lua:2057,2129,2199`.
## Axe identity balance toggles (Issue #601)

Three default-on settings remain independent: Greataxe light critical chance,
Dual Axes light critical chance, and Dual Axes cleave.
`additional_critical_strike_chance` is floored at `0.10` on named
`light_attack_*` sweep releases. Existing stronger values are preserved; the
Greataxe upward light already authored at `0.10` therefore remains `0.10`
instead of becoming `0.20`. This includes each weapon's push follow-up,
but excludes heavy releases, charge/start actions, ordinary push, block, and
wield. The Greataxe pass owns both `two_handed_axes_template_1` and the
independent `cwv_greataxe_template`; the latter is applied only after its clone
exists. Dual Axes variants inherit `dual_wield_axes_template_1`, so the native
template is their single gameplay owner.

Dual Axes cleave swaps `damage_profile`, `damage_profile_left`, and
`damage_profile_right` on every direct `kind = "sweep"` attack. Generated
`cwv_axe_cleave_*` profiles clone the original profile and its cleave row,
scaling only cleave `attack` and `impact` by `1.10`. Damage, stagger power,
timing, and source rows remain unchanged. Each toggle snapshots exact prior
fields, is idempotent, restores independently, and composes into CWV's one
canonical enable/disable/unload callback owner. Source provenance: VT2
`scripts/settings/equipment/weapon_templates/2h_axes.lua:185-1048`,
`dual_wield_axes.lua:348-1775`, and `scripts/helpers/action_utils.lua:23-28`.
