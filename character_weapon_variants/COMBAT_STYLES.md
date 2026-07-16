# CWV Combat Styles

Combat Styles let one exact crafted weapon instance select another complete
play package without minting another inventory item. The saved value is a
stable style id keyed by the instance's backend id; the item, illusion, glow,
properties, traits, and CWV identity do not change.

## Initial families

| Family | Supported items | Cycle (rotated to native style first) |
|---|---|---|
| Greatsword | Native Empire Greatsword and Bretonnian Longsword; migrated Imperial/Black Guard UUIDs | Greatsword, Imperial Longsword, Bretonnian, Kerillian |
| Greathammer | Kruber Greathammer, Warrior Priest Greathammer, CWV Sigmarite Greathammer | Kruber, Warrior Priest |
| Tuskgor Spear | Native Kruber Tuskgor Spear; migrated legacy Infantry Spear UUIDs | Hunter, Infantry |
| Spear and Shield | Native Kruber Chaos Wastes Spear and Shield and Kerillian Spear and Shield | Kruber, Elven |

Kerillian Greatsword style deep-clones the donor template and every referenced
damage profile before applying its package: 15% slower attack actions, 15%
more stagger, 15% more cleave, and unchanged damage. No donor or shared power
table is mutated.

Imperial Longsword style deep-clones Kruber's native
`two_handed_swords_template_1` action graph, not the Bretonnian
`bastard_sword_template`. It applies 15% faster attack actions, 15% less
damage, 15% less stagger, and 15% more cleave while retaining the Imperial
model transform. This makes the four entries semantically ordered as native
Greatsword, Imperial-tuned Greatsword, Bretonnian Longsword, and Kerillian
Greatsword rather than placing the Bretonnian graph twice in succession.

Infantry style reuses #596's cloned Kerillian spear package: 15% slower attack
actions, 15% more stagger, 15% more cleave, and 7.5% more damage. Hunter style
is the untouched native Tuskgor template. CWV adds Foot Knight to the native
Tuskgor Spear's authored availability without granting an item. The seven
shield-free Spear+Shield models now belong to Tuskgor Spear's illusion pool.

## Runtime ownership

`_cwv_combat_styles.lua` owns the catalogue, exact-instance store, template
selection, contextual inventory button, hotkey transition, peer state, and
diagnostics. `BackendUtils.get_item_template` remains CWV's one consolidated
template seam. A transition is rejected while a weapon action is active, then
otherwise rebuilds the currently wielded slot once through vanilla
`destroy_slot -> add_equipment -> wield`. A failed rebuild rolls persistence
back before a best-effort repair.

The inventory control appears only when the selected loadout item belongs to a
supported family and reads `Switch to: <next style>`. One physical mouse click
produces both VMF press and release flags, but press is observation-only and
the handler consumes exactly one release edge, so it commits exactly one
transition. The optional `Cycle Combat Style` hotkey applies to the wielded
supported instance in the keep or a mission and advances through the same
member order as the button.

The retired `cwv_es_infantry_spear`, `cwv_es_longsword`, and
`cwv_es_longsword_blackguard` master rows are promo restore bridges and hidden
from new crafting. Once CIM is available, CWV first plans and validates the
entire migration without mutation. It then rewrites each legacy craft in-place
to native Tuskgor Spear or Greatsword, maps/preserves its exact visual, and
seeds Infantry or Longsword style against the same backend UUID. Properties,
traits, power, rarity, glow, and all other opaque CIM fields remain untouched.
The Imperial, Black Guard, and Helmgart skin keys remain stable but are owned by
native Greatsword's illusion pool.

Custom inventory icons are also capability data, not globally safe strings.
`_cwv_inventory_icons.lua` publishes the exact CWV atlas renderer allow-list
and a vanilla fallback for every paired Dual Axe icon. A sibling renderer must
resolve through that contract; unknown renderers fail closed to the native icon.

## Reciprocal family registry

Issue #645 replaces the remaining behavior-specific branches with one bounded
descriptor contract. Each style row owns its exact template, first-person
resource, optional DLC requirement, optional presentation key, and per-member
receiver remap key. Catalogue validation rejects an incomplete style, duplicate
cycle entry, unknown remap, or receiver outside its family before the runtime
can expose it.

Kruber and Elven Spear and Shield is the first reciprocal family because the
vanilla source and the existing WT evidence prove both donors and the two
necessary event translations. CWV deep-clones each donor only to author the
opposite skeleton's wield route. First-person actions and balance remain exact;
the descriptor maps `attack_swing_stab_lh` to `attack_swing_stab` on Kruber and
`attack_swing_up` to `attack_swing_stab_lh` on Kerillian. The Kruber style
requires `grass`; the Elven style requires `scorpion`, and the cycle skips an
unowned donor rather than bypassing vanilla DLC ownership.

Provenance: Kruber's item/template uses `es_deus_01_template`, `grass`,
`to_es_deus_01`, and the `.../melee/es_deus_01` state machine [src:
`scripts/settings/equipment/item_master_list_morris.lua:190-205`;
`scripts/settings/equipment/weapon_templates/es_deus_01.lua:1749-1750`].
Kerillian's uses `one_handed_spears_shield_template`, `scorpion`,
`to_1h_spear_shield`, and `.../melee/1h_spear_shield` [src:
`scripts/settings/equipment/item_master_list_anvil.lua:69-84`;
`scripts/settings/equipment/weapon_templates/1h_spears_shield.lua:1484-1485`].
The bidirectional event translations are the existing source-audited WT
contract [repo: `docs/WEAPON_CATALOG.md:310-322`].

One-handed axes, Glaive/Great Axe, Empire/Elven one-handed swords, and
Elf/Tuskgor spears are not registered as styles yet. They remain in a separate
diagnostic allow-list. The existing pre-RPC 3P action seam records each distinct
owner event once, up to 32 rows per candidate family per session, using
`[cwv:645]`; it does not load resources, mutate templates, or expose UI rows.

## Presentation and networking

The ordinary vanilla equipment item remains on the native equipment wire.
CWV peers exchange only schema, operation, slot, family id, and style id over
`cwv_combat_style_v1`; state publishes on transitions, wield, gameplay entry,
and a bounded hot-join query/reply, never per frame. Query replies publish
directly to the requesting peer and do not emit another query.

Imperial Longsword proportions are a style-owned transform. The existing
shared CWV transform consumers apply it to owner/bot third person, remote
husks, inventory/lobby/score character previews, and item/Athanor previews.
Other styles explicitly suppress the legacy Imperial transform so switching
back cannot leave stale scale or grip. First-person donor state machines come
from the selected template; existing CWV network-bound animation redirects
remain the receiver-side 3P owner.

## Source seams

- `scripts/managers/backend/backend_utils.lua:136`: canonical item-template
  resolution.
- `scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:627`:
  vanilla owner wield/re-wield transaction.
- `scripts/unit_extensions/default_player_unit/inventory/simple_husk_inventory_extension.lua:314`:
  remote re-wield and attached-unit refresh.
- `scripts/ui/views/hero_view/windows/hero_window_loadout.lua:124,213`:
  selected-slot input and loadout presentation refresh.

## Extension contract

Add a style as an immutable catalogue row containing its label, registered
template, source-audited resource, DLC gate, optional presentation descriptor,
and bounded receiver remap key. Add an item member with an explicit default and
deterministic cycle, then extend the catalogue-validation test. Never mutate a
donor template, persist a table/function, send a template over the wire, poll
per frame, or special-case another preview surface outside the shared
appearance consumers. A candidate without complete remap/transform evidence
belongs in `DIAGNOSTIC_CANDIDATES`, not `FAMILIES`.
