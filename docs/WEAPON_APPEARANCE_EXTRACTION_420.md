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
| CWV | one local shared instance in `_cwv_weapon_transform_owner.lua` | shared absolute scale/position/rotation and weak-key guarded additive offset; family adapters retain identity/lifecycle policy | Old Musket uses its strict unit-local residency/paint owner |
| Cosmetics | one entry-created local shared instance consumed by `_cos_render.lua` | ordinary one-shot scale/offset composition is shared; LA/TPE and any durable owners remain specialized | normal paths use unit-local writes; legacy texture fallbacks remain outside #420 |
| WT beta/dev | one local shared instance per stream plus `_wt_transform_runtime.lua` | ordinary scale/offset composition is shared; Hold-Pose and durable rotation retain their measured-retention ownership | no general variant-texture owner |

The hook surfaces also differ. Each consumer resolves identity, hand, perspective,
career, residency, and render path before applying geometry. Those decisions do
not belong in the shared primitive and cannot be replaced safely in one bulk edit.

## Landed migration boundary

`tools/shared_lib/_lib_weapon_appearance.lua` is now the canonical primitive and
has synchronized standalone copies in CWV, Cosmetics, both WT streams, and WOC.
It exports `new(optional_api)`; each consumer constructs one instance and keeps its own
weak-key offset ledger. The instance owns only:

- absolute scale, position, and rotation;
- idempotent additive offset;
- position-over-offset precedence;
- per-unit texture application through `Unit.set_texture_for_materials`;
- fail-closed validation and protected engine calls.

It deliberately does not resolve item/skin identity, units, hand, perspective,
career, packages, ammo, network state, or render-path hooks. The API can be tested
offline through dependency injection, while production defaults bind VT2 globals.
CWV v0.1.405-dev was the first runtime consumer. Both WT streams and WOC now
construct their own mod-local instances too. The #420 Cosmetics slice constructs
one instance in its entry before `_cos_render.lua` loads and delegates that
ordinary adapter's scale and additive-offset composition. Identity, hand,
perspective, render-path, specialized LA/TPE behavior, and durable-retention
policies remain with the owning mods.

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
2. **CWV Old Musket textures (landed under #1155):** strict residency and
   unit-material proof guard one unit-local texture owner across its implemented
   owner, husk, and preview cells. This stricter family adapter supersedes the
   original direct `apply_textures` cutover sketch.
3. **Cosmetics transforms (source-complete; release pending):** ordinary
   fresh-spawn scale/offset helpers delegate to the bundled shared instance.
   Durable/persisted, LA, TPE, and hand-selection policy remains with Cosmetics.
4. **Cosmetics texture fallback:** delete the mesh-material fallback only after
   the unit-local route is proven on every LA unit class. Never silently restore
   `Material.set_texture` as a compatibility fallback.
5. **WT transforms (landed in stable/dev together):** ordinary spawn-time and
   menu-preview scale/offset helpers delegate to the bundled WA instance. Durable
   per-frame and #569 canonical rotation composition stay outside the primitive:
   they own captured baselines and animation-tick retention, not one-shot math.

The current #420 acceptance is the Cosmetics ordinary-transform cutover plus a
regression that rejects restoring its private setters. The source boundary is
repository-verifiable; visual no-drift still requires the released Cosmetics
build. Broader material, texture-fallback, retained-state, and lifecycle parity
remain under #660 rather than keeping #420 open after this adapter ships.
