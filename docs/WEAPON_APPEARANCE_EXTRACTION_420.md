# Shared WeaponAppearance extraction boundary (#420)

## Outcome of the ownership audit

The three mods must remain independently loadable Workshop packages. A runtime
provider mod would violate that invariant and make load order observable, so the
only safe common-code mechanism is the repository's copied-library pattern:
one canonical file under `tools/shared_lib`, synchronized byte-for-byte into each
consumer and loaded by that consumer with its own `mod:dofile`.

Current ownership is not yet interchangeable:

| Mod | Current owner | Transform behavior | Texture behavior |
|---|---|---|---|
| CWV | private `WA` in the entry file | absolute scale/position/rotation; weak-key guarded additive offset | two live `Material.set_texture` call clusters |
| Cosmetics | entry helpers plus `_la_bridge.lua` | separate scale/offset implementations at each spawn surface | normal path uses `Unit.set_texture_for_materials`; mesh fallback still uses `Material.set_texture` |
| WT | entry helpers and Hold-Pose module | career-scoped scale/offset plus specialized durable composition | no general variant-texture owner |

The hook surfaces also differ. Each consumer resolves identity, hand, perspective,
career, residency, and render path before applying geometry. Those decisions do
not belong in the shared primitive and cannot be replaced safely in one bulk edit.

## Landed migration boundary

`tools/shared_lib/_lib_weapon_appearance.lua` is now the canonical primitive and
has synchronized standalone copies in CWV, Cosmetics, and WT. It exports
`new(optional_api)`; each consumer will construct one instance and keep its own
weak-key offset ledger. The instance owns only:

- absolute scale, position, and rotation;
- idempotent additive offset;
- position-over-offset precedence;
- per-unit texture application through `Unit.set_texture_for_materials`;
- fail-closed validation and protected engine calls.

It deliberately does not resolve item/skin identity, units, hand, perspective,
career, packages, ammo, network state, or render-path hooks. The API can be tested
offline through dependency injection, while production defaults bind VT2 globals.
CWV v0.1.405-dev is the first runtime consumer. It replaces only the private WA
implementation and preserves CWV's existing resolver/caller surface and exported
compatibility handles. The next source slice adopts the primitive in Cosmetics'
ordinary render-path scale/grip adapter. WT stable/dev must cut over together at
the normal beta-promotion boundary so the enforced stream-parity contract remains
exact. WT's durable per-frame pose owner remains separate because it owns
animation-tick retention and canonical baseline recovery, not one-shot transform
math.

## Loader proof

The library has no `get_mod` call and no sibling-mod dereference. A future consumer
loads only its bundled copy after its own namespace exists. Therefore:

1. any subset or order of CWV/Cosmetics/WT remains valid;
2. every mod receives an isolated additive-offset ledger;
3. a consumer cannot mutate another mod's module table;
4. exact-byte drift is blocked by `qa/check_shared_lib_drift.ps1`.

## Incremental cutover plan

1. **CWV geometry (landed v0.1.405-dev):** its private `WA` body now delegates to
   one `mod:dofile`; the existing `mod._cwv_weapon_appearance` compatibility
   handle and render-path resolution are unchanged.
2. **CWV textures:** replace both musket `Material.set_texture` clusters with one
   texture spec passed to `apply_textures`; test owner, husk, preview, and browser.
3. **Cosmetics transforms (source candidate landed):** ordinary render-path
   scale/offset helpers now delegate transform composition to the bundled WA
   instance. Durable/persisted or LA hand-selection policy remains with Cosmetics.
4. **Cosmetics texture fallback:** delete the mesh-material fallback only after
   the unit-local route is proven on every LA unit class. Never silently restore
   `Material.set_texture` as a compatibility fallback.
5. **WT transforms (promotion boundary):** migrate ordinary spawn-time and menu
   preview scale/offset helpers in stable and dev together during the normal beta
   promotion. Durable per-frame and #569 canonical rotation composition stay
   outside the primitive until their base-capture contract has a dedicated API.

Each cutover requires existing four-render-path regression coverage and an
in-game verification label appropriate to that consumer. The architecture phase
itself is repository-verifiable and must not claim the live banned calls are gone.
