# Issue #660 appearance architecture gap audit

Date: 2026-07-17

Baseline: `3dfc52568c81f63f12105332252208e88f41ad36` (`origin/master`)

Scope: weapon/cosmetic identity, transforms, owner/remote husks, inventory and
item previews, Athanor/crafting previews, mission transitions, respawn, and
persisted pre-equipped replay. This is a source/closed-history audit, not an
in-game verification claim.

## Empirical result

The recurring failures are not caused by one bad offset. The repository has a
shared **unit mutation primitive**, but it does not yet have the provider-neutral
appearance descriptor, adapter registry, or lifecycle coordinator required by
#660.

The engine really does expose separate roots:

- owner/bot equipment starts at `GearUtils.create_equipment`; remote equipment
  starts at `GearUtils.spawn_inventory_unit`, and hot join has another sender
  (`GearUtils.hot_join_sync`). `[src: scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:7,155,462]`
- local resync and remote wield are separate extension paths.
  `[src: scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:249,1443,1926]`
  `[src: scripts/unit_extensions/default_player_unit/inventory/simple_husk_inventory_extension.lua:641]`
- inventory hero, item browser/Athanor, and their recipes are separate preview
  entry points. `[src: scripts/ui/views/world_hero_previewer.lua:895]`
  `[src: scripts/ui/views/menu_world_previewer.lua:635]`
  `[src: scripts/ui/views/hero_view/loot_item_unit_previewer.lua:246,538]`
- Hold-Tab reconstructs loadout data without an exact backend instance ID, then
  asks `UIUtils` for presentation. `[src: scripts/managers/player/player_manager.lua:69]`
  `[src: scripts/ui/views/ingame_player_list_ui_v2.lua:1529]`

Those engine boundaries require adapters. The architectural defect is that the
adapters still resolve and apply overlapping parts independently.

## Actual owners on current master

| Concern | Current owner(s) | What is shared | Verified gap |
|---|---|---|---|
| Atomic pose/textures | `tools/shared_lib/_lib_weapon_appearance.lua` | Atomic linked-root transform composition and unit-local texture writes | The library explicitly does **not** infer item identity, hand, perspective, render path, or package state (`:3-6`). |
| CWV exact unit identity | `_cwv_exact_appearance.lua`, `_cwv_appearance_lifecycle.lua`, and the CWV entry | One immutable-by-convention unit descriptor and bounded semantic identity ledger | Descriptor fields stop at provider/item/base/skin/right/left units (`_cwv_exact_appearance.lua:113-162`). Transform, material, glow, pose/template, icon/name, capability, and fallback-resource proofs are absent. |
| CWV previews | `_cwv_exact_appearance.lua` plus entry wrappers | Two recipe adapters (`hand_flags`, `base_identity`) share the unit descriptor | `M.SURFACES` is test data, not a runtime adapter registry; it names score screen but has no score adapter (`:10-22`). The entry still contains family-specific preview work after the generic swap. |
| CWV world replay | `_cwv_appearance_lifecycle.lua` plus entry hooks | Compact provider/item/base/skin/fingerprint messages; receiver reconstructs locally | Only melee/ranged unit identity is coordinated. Persisted instance load, generic peer-ready, respawn, rejoin, style/customization, lobby/score creation, and disable restore are not coordinator edges. |
| CWV transforms/presentation | CWV entry, transform maps, crowbill/musket family modules | The shared atomic setter is loaded by CWV | Unit identity and transforms still use different resolver maps. Browser code resolves `def` and applies transforms after the descriptor swap (`character_weapon_variants.lua:12294-12343`); Old Musket then runs another bespoke paint/track/transform path (`:12346-12364`). |
| Cosmetics models/material/glow/replay | Cosmetics entry plus `_cos_render.lua`, `_cos_wire.lua`, `_cos_la_replay_policy.lua`, `_cos_item_presentation.lua`, `_tpe.lua` | Some pure policies and one item-card descriptor exist | The synchronized `_lib_weapon_appearance.lua` copy is not loaded. `_cos_render.lua` explicitly keeps separate in-game and menu resolution, and grip offsets cover only the GearUtils path (`:110-127,170-198`). LA, glow, score, and offhand replay remain separate ledgers/retry paths in the entry. |
| WT transforms/pose | WT entry plus animation modules | WT reuses its own transform tables across selected owner/preview/husk hooks | WT does not load the shared appearance primitive. It retains separate scale, offset, rotation, durable per-frame grip, owner, husk, and MenuWorldPreviewer paths (`weapon_tweaker.lua:378-400,593-627,699-719,955-1051,3728-3799`). |
| WOC Blightreaper | `_woc_appearance_policy.lua`, `_woc_durable_transform.lua`, `_woc_mod_unit_preview.lua`, WOC entry | WOC loads the shared atomic setter | WOC owns a second family-specific descriptor (unit, donor, textures, transform at `_woc_appearance_policy.lua:6-68`) and its own durable tracker; it is not registered with the CWV identity/lifecycle ledger. |
| CIM Athanor/crafting | CIM entry and forge preview policies | Crash-safe preview gating | CIM's shared chokepoint currently decides whether `LootItemUnitPreviewer` may spawn (`crafting_in_modded.lua:2704-2805`); it does not consume a provider-neutral appearance descriptor. |
| Icons/names/Hold-Tab | Cosmetics `_cos_item_presentation.lua`, CWV `_cwv_inventory_icons.lua`, per-surface UI hooks | Cosmetics has a small item-card descriptor and CWV has renderer-safe icon fallback policy | These are separate from the world descriptor and lifecycle fingerprint, so a world-correct item can still have divergent icon/name/offhand state. |

Two additional static facts matter:

1. The shared-library QA test proves five copies are byte-identical, but only
   CWV and WOC load their copies. Byte identity is not consumer adoption.
   `[repo: qa/lua/tests/test_shared_weapon_appearance.lua:156-181]`
   `[repo: character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua:9925-9929]`
   `[repo: weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua:150-164]`
2. The CWV entry remains 12,401 lines and Cosmetics remains 10,465 lines on
   this baseline. The extracted policies are useful, but lifecycle hooks and
   post-spawn family writers still live in the entries, so deleting a superseded
   writer cannot yet be enforced by ownership boundaries.

## Direct closed-issue crosscheck

GitHub state was read on 2026-07-17. Every issue below is closed; the cited
commit is the first matching repository commit subject, not proof that the
whole #660 matrix passed.

| Closed cluster | Issues | Narrow result and current implication |
|---|---|---|
| Preview | #409 (`a17849a`), #617 (`3e2d1b7`) | #409 fixed one Old Musket inventory pose; #617 crash-gated custom preview resources. Neither supplied a generic preview adapter/postcondition registry. |
| Husk/model/transform | #270 (`3aa9218`), #282 (`283abdf`), #397/#418 (`d1817a7`), #475 (`0a34c28`), #495 (`d39853b`), #580 (`848ae67`), #587 (`a5a37a6`) | These fixed residency, one family transform fan-out, wire skin leakage, or specific substitutions. Their repeated separate hooks are evidence for the missing shared owner, not evidence against it. |
| Transition/hot join | #234 (`c602b7b`), #264/#265 (`9b0ff20`), #267 (`86bea02`), #268 (`8b6c2fa`), #574 (`ea02fcc`) | #267 is the direct predecessor of current #233: persisted pre-equipped state can still be absent until a live change. #574 remains valid for its original glow scope; composed offhand/icon glow is current #650. |
| Exact instance identity | #390 (`587cb1e`), #392 (`dd6906f`), #563 (`0f3b6ce`), #592 (`0fc29bb`), #620 (`ffbc1f4`) | Crafting/base identity and persistence were repaired in their owners. #620 added style switching, while current #645/#657 show that style model/template replay is not part of the generic appearance lifecycle. |
| Pose | #569 (`c598651`), #603/#606 (`470afcd`) | Rotation composition and two preview idles were fixed narrowly. They did not consolidate WT/CWV/Cosmetics/WOC pose ownership. |
| Texture/per-hand | #514 (`938b06c`), #612 (`ebb5716`) | Per-hand and donor-material lessons exist, but the Cosmetics pipelines remain separate from the world identity fingerprint and other providers. |
| Score/UI | #513 (`29c5873`), #639 (`b0a410f`) | Score wearer identity and one cosmetic set's text were repaired; generic world/UI descriptor parity remains absent. |
| Resource/wire safety | #403 (`bdb7389`), #422 (`1d9cb95`), #654 (`355b0d4`) | These are necessary crash floors. They prove optional resources/identifiers need explicit local capability and vanilla-safe fallback fields in the canonical descriptor. |

The most important closure lesson is that “correct on the reported surface” was
often enough to close an issue. It was not proof of a complete appearance
contract. #234, #264, #397, #409, and #620 are clear examples of a narrow
surface/lifecycle fix later recurring under another issue number.

## CI gap fixed by this audit

Commit `167940e` made `G-APPEARANCE` executable, but the manifest itself owned
the closed vocabulary. Deleting a required cell from both
`SurfaceVocabulary`/`ReplayEdgeVocabulary` and every contract still passed.
Also, the surface vocabulary collapsed all `LootItemUnitPreviewer` consumers
into `item_browser` and omitted lobby, score, Hold-Tab, and ordinary crafting.

This audit hardens the gate without making a runtime claim:

- the checker now owns immutable minimum surface, replay-edge, and concern
  vocabularies;
- self-test plants vocabulary-contraction failures;
- the manifest enumerates inventory, cosmetic, Athanor, crafting, lobby, score,
  and Hold-Tab separately;
- it also enumerates instance load, wield, customization/style changes,
  peer-ready, rejoin, preview reopen, lobby/score creation, and mod-disable
  restore;
- cells without a generic adapter are marked `deferred`, with reasons.

## Smallest safe runtime migration sequence

No runtime mutation is justified by this static audit alone. The next safe
sequence is:

1. Define a provider-neutral immutable descriptor type and provider adapters.
   First include exact identity, per-hand units, full per-perspective atomic
   pose, material/glow, effective template/pose, icon/name, resource/capability
   proof, and vanilla fallback. Keep the existing CWV compact wire payload as
   one provider adapter rather than expanding vanilla lookups.
2. Add a registry of adapter capabilities/postconditions for every canonical
   surface. Reuse an engine primitive where appropriate, but retain distinct
   acceptance cells for Athanor, cosmetic preview, crafting, lobby, score, and
   Hold-Tab because their input identity shapes differ.
3. Add one bounded coordinator with generation/fingerprint coalescing for every
   canonical replay edge. Persisted pre-equipped state must replay at a proven
   peer-ready edge; respawn/rejoin must clear stale generations before replay.
4. Migrate one complete family (the existing CWV exact-unit slice is the best
   seed), add retained-state postconditions and mixed-mod fallback tests, then
   delete that family's superseded resolver/writer paths.
5. Register Cosmetics, WOC, WT, and CIM adapters one concern at a time. Do not
   call a synchronized library copy “adopted” until the mod actually loads and
   routes the relevant concern through it.

Until that migration passes the co-op matrix, #660 must remain open and no
single-surface setter or source-only test should be treated as verification.
