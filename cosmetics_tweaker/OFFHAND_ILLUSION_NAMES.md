# Independent Component Illusion Text Catalog

This is the authoring reference for independent offhand-weapon and shield text
(#641). It is a data catalog, not a work-status tracker. The live picker pools
remain authoritative because DLC and Character Weapon Variants can add skins
after Tweaker: Cosmetics loads.

## Component boundaries

- Primary/right-hand weapons reuse the source illusion name for the exact
  primary model being previewed.
- Offhand/left-hand weapons use the independent key schema below.
- Shields use their own independent key namespace. Existing shield copy is the
  deterministic fallback until a final name is authored.
- Combined labels are composed at display time as `Primary + Offhand/Shield`;
  no monolithic pair name is saved.
- Flavor text belongs to the selected offhand or shield. Component-authored
  descriptions win, then the source illusion description, then readable
  generated component copy. The primary weapon description is never reused.
- Localization ownership is explicit: authored `cos_*` keys resolve through
  `mod:localize`, while vanilla source-illusion description keys resolve only
  through `_G.Localize`. These resolvers are never substituted for each other.

Changing a name changes presentation only. The saved selection, unit path,
source skin key, exact backend-item identity, and network payload stay intact.

## Generate the current inventory

Run `/cos_offhand_name_inventory`, then search the console log for
`[cosmetics:offhand-names]`. The command emits tab-separated rows sorted by
component kind and identity:

```text
component_kind  component_identity  hand_field  localization_key  current_name  status  item_types
```

`status=source` means no independent name has been authored and the existing
source name is shown. `status=generated` is the fail-safe for missing source
copy. `status=authored` means the independent key resolved. Shared components
appear once with every compatible item type comma-separated.

## Name one component

Copy the row's exact `localization_key` into
`cosmetics_tweaker_localization.lua` and add the chosen English name. Add the
matching `_description` key for authored flavor text. Weapon offhands use
`cos_offhand_weapon_...`; shields use `cos_shield_...`.

Custom shields may provide a pre-existing explicit localization key. The
confirmed Purpure/Azure shield uses `cos_gk_purpure_azure_shield_name` and is
named `The Blood-Bloomed Bouclier`; its flavor text is owned by
`cos_gk_purpure_azure_shield_description`.

Do not change the source skin key, component identity, hand field, or unit path.
Unnamed entries intentionally show their existing source name, so names can be
added one by one without breaking old items or saves.

## Stable schema

For identifier-safe component identities, the schemas are:

```text
cos_offhand_weapon_<source_skin_key>_<left|right>_name
cos_offhand_weapon_<source_skin_key>_<left|right>_description
cos_shield_<stable_component_identity>_<left|right>_name
cos_shield_<stable_component_identity>_<left|right>_description
```

Non-identifier identities receive a normalized token plus a deterministic
hash. Always copy the generated key rather than recreating it by hand.
