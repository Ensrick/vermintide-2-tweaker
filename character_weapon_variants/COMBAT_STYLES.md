# CWV Combat Styles

Combat Styles let one exact crafted weapon instance select another complete
play package without minting another inventory item. The saved value is a
stable style id keyed by the instance's backend id; the item, illusion, glow,
properties, traits, and CWV identity do not change.

## Initial families

| Family | Supported items | Cycle (rotated to native style first) |
|---|---|---|
| Greatsword | Native Kruber/Saltzpyre Greatswords and Bretonnian Longsword; migrated Imperial/Black Guard UUIDs | Empire/Saltzpyre: Greatsword, Kerillian, Bretonnian. Bretonnian: Bretonnian, Greatsword, Kerillian. |
| Greathammer | Kruber Greathammer, Warrior Priest Greathammer, CWV Sigmarite Greathammer | Kruber, Warrior Priest |
| Tuskgor Spear | Native Kruber Tuskgor Spear; migrated legacy Infantry Spear UUIDs | Hunter, Infantry |
| Spear and Shield | Native Kruber Chaos Wastes Spear and Shield and Kerillian Spear and Shield | Kruber, Elven |
| Sword and Shield | Native Empire Sword and Shield and Bretonnian Sword and Shield | Empire, Bretonnian |

Kerillian Greatsword style deep-clones the donor template and every referenced
damage profile before applying its package: 15% slower attack actions, 25%
more stagger, 25% more cleave, and 7.5% more damage. No donor or shared power
table is mutated.

Saltzpyre's native Greatsword uses that same canonical three-style family. Its
Kerillian and Bretonnian receiver descriptors reuse the source-backed wield
and action-event translations already proven by Weapon Tweaker for Witch
Hunter Captain, Bounty Hunter, and Zealot. Warrior Priest remains excluded
because Greatsword is not an authored availability for that career. The
translations flow through CWV's one bounded network animation funnel, so
owner third person and remote husks receive the same event without per-frame
state traffic.

On Bretonnian Longsword, the Kruber Greatsword style uses a receiver-specific
clone with unchanged damage and attack timing, 25% more stagger, and 25% less
cleave than native Greatsword. Its attack reach remains the donor's authored
`range_mod` signature `{1.5, 1.65}`, which currently exactly matches native
Bretonnian Longsword. Registration fails closed if those source signatures
ever diverge rather than silently shipping the wrong reach.

Imperial Longsword style deep-clones Kruber's native
`two_handed_swords_template_1` action graph, not the Bretonnian
`bastard_sword_template`. It applies 15% faster attack actions, 15% less
damage, 15% less stagger, and 15% more cleave while retaining the Imperial
model transform. Because that is still the native Greatsword action graph, the
Imperial entry is not exposed as a second public moveset on a native Greatsword.
It remains a valid hidden persistence state for legacy Imperial Longsword and
Black Guard UUID migration, so existing exact instances lose no authored
balance or presentation.

Native Greatsword's Bretonnian style owns a receiver-specific, 3P-only
presentation descriptor. Owner/bot third person, remote husks, inventory,
lobby/score, and item/Athanor previews reuse Imperial Longsword's reviewed
scale `{1.0, 0.8, 0.9}` and grip offset `{0, 0, -0.065}`. First person remains
owned by the Bretonnian donor state machine. In the reciprocal direction, the
native Bretonnian Longsword consumes one unified inverse presentation under
Greatsword and Kerillian styles: scale `{1.0, 1.25, 1.111111...}` and grip
offset `{0, 0, 0.065}` on owner first person and every third-person/preview
consumer. Retired Imperial/Black Guard rows already reference Empire
Greatsword meshes, so they intentionally do not consume that native
Bretonnian-mesh inverse.

Infantry style reuses #596's cloned Kerillian spear package: 15% slower attack
actions, 15% more stagger, 15% more cleave, and 7.5% more damage. Hunter style
is the untouched native Tuskgor template. CWV adds Foot Knight to the native
Tuskgor Spear's authored availability without granting an item. The seven
shield-free Spear+Shield models now belong to Tuskgor Spear's illusion pool.

## Runtime ownership

`_cwv_combat_styles.lua` owns the catalogue, exact-instance store, template
selection, contextual inventory button, hotkey transition, peer state, and
diagnostics. `BackendUtils.get_item_template` remains CWV's one consolidated
template seam. A transition preflights both hands, ends active weapon actions
through vanilla `WeaponUnitExtension:stop_action("interrupted")`, and then
rebuilds the currently wielded slot once through vanilla
`destroy_slot -> add_equipment -> wield`. A failed rebuild rolls persistence
back before a best-effort repair. Career actions fail closed and are never
cancelled by the style control. An asynchronously loaded style performs this
interrupt only after its resource is resident and the exact instance is still
wielded, so a failed or stale load does not cancel the player's attack.

CWV also publishes the narrow dot-call contract
`get_effective_combat_style_template_name(item, backend_id, owner_unit, slot_name)`.
It returns only the active donor template name for a proven local exact instance
or for a remote `(peer, slot, family, style)` state already received by CWV.
Weapon Tweaker consumes this value when populating its per-unit 3P animation
state. WT validates that the returned name is registered in `Weapons` and falls
back to `item.template` when CWV is absent, disabled, unsupported, raises, or
returns an unknown name. WT does not mirror the family/style catalogue.

On each changed remote style edge, CWV first resolves the human wearer through
the shared protected peer resolver. The protected call must be made in an
explicit branch: routing `pcall` through `and` collapses its player return and
was the exact #786 failure. Owner, local-player, direct peer, and fallback peer
results all require positive human identity; host bots share the host's
transport peer id and must never consume its peer+slot style row.

CWV then performs one immediate husk re-wield. The
refresh first proves that the synchronized slot is still wielded and already
contains item data. If the style edge won the race against the ordinary
equipment RPC, CWV keeps the existing render intact and retries only the local
refresh at 0.25-second cadence, capped at eight total attempts. A style for an
unwielded slot waits for the next natural wield instead of entering vanilla's
partial empty-slot wield path.
That path stops weapon FX/attached units and updates wield state even though
`_wield_slot` rejects the missing item before rebuilding equipment. The
bounded `[cwv:620/786] style husk refresh` row reports resolver source,
effective donor template, right/left 3P liveness, edge, and attempt count.
[src: `scripts/unit_extensions/default_player_unit/inventory/simple_husk_inventory_extension.lua:316-326,641-658,761-775`]

The inventory control appears only when the selected loadout item belongs to a
supported family and reads `Switch to: <next style>`. Small unboxed text above
it displays the active ordinal (`Moveset 1 / 3` on desktop, compact `1 / 3` on
controller grids), derived from the same DLC-filtered member order as the
transition itself. One physical mouse click produces both VMF press and release
flags, but press is observation-only and the handler consumes exactly one
release edge, so it commits exactly one transition. The optional `Cycle Combat
Style` hotkey applies to the wielded supported instance in the keep or a
mission and advances through the same member order as the button.

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

Empire and Bretonnian Sword and Shield form a second reciprocal family. Each
style resolves the complete native donor template rather than copying only its
actions: Empire uses `one_handed_sword_shield_template_1` with
`.../melee/1h_sword_shield`; Bretonnian uses
`one_handed_sword_shield_template_2` with
`.../melee/1h_sword_shield_breton`. The equipped item remains authoritative
for the sword, shield, illusion, glow, and icon. Both donors are native Kruber
graphs with registered wield/action events, so they require no invented 3P
translation or model transform. The Bretonnian style is gated by `lake`.

Provenance: Empire item/template identity is source-backed at
`scripts/settings/equipment/item_master_list_exported.lua:6639-6658` and
`scripts/settings/equipment/weapon_templates/1h_swords_shield.lua:1364-1365`;
Bretonnian is at `scripts/settings/dlcs/lake/item_master_list_lake.lua:411-429`
and `scripts/settings/equipment/weapon_templates/1h_swords_shield_breton.lua:1250-1251`.

The CWV-to-WT effective-template contract below is a third-person animation
handoff only; it does not repair first-person donor-state-machine events. A
reciprocal Spear and Shield style is not verification-ready until its receiver
plays `parry_pose` while blocking in first person as well as its attack chain.
Both vanilla donors declare `action_two.default` as a left-hand `block` using
`parry_pose`, so a missing Kruber block after selecting Elven style is a live
state-machine/package/rebuild boundary, not a WT 3P remap symptom.
[src: `scripts/settings/equipment/weapon_templates/1h_spears_shield.lua:1425-1433,1484-1485`;
`scripts/settings/equipment/weapon_templates/es_deus_01.lua:1371-1379,1749-1750`]

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

Presentation can be style-owned or receiver-specific. The existing shared CWV
transform consumers apply the resolved descriptor to owner/bot third person,
remote husks, inventory/lobby/score character previews, and item/Athanor
previews. Receiver resolution combines the bounded synchronized family/style
edge with the concrete native item already being rendered; no item key is added
to the wire. Styles without a descriptor explicitly suppress the legacy
Imperial transform so switching back cannot leave stale scale or grip.
First-person donor state machines come from the selected template; existing
CWV network-bound animation redirects remain the receiver-side 3P owner.

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
and bounded receiver overrides for template, remap, or presentation. Add an
item member with an explicit default and deterministic cycle, then extend the
catalogue-validation test. Do not put two entries with the same action graph in
one public member order; legacy-only style IDs may remain outside that order for
lossless migration. Never mutate a donor template, persist a table/function,
send a template over the wire, poll per frame, or special-case another preview
surface outside the shared appearance consumers. A candidate without complete
remap/transform evidence belongs in `DIAGNOSTIC_CANDIDATES`, not `FAMILIES`.

When resolving an exact item, an explicit CWV identity is authoritative. If a
custom CWV key is not itself a registered family member, resolution fails
closed and never falls through to the clone's inherited vanilla `name`. This
prevents custom Sword-and-Shield variants, and future variants, from losing
their authored template or balance merely because a native donor joins a
Combat Style family.
