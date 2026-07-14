# Issue 452: premium-skin special variants

## Current boundary

The five requested appearances exist as the `skin_1001` Versus cosmetics, but
they are not AI enemy units. Each cosmetic uses a dark-pact **player** base and
links a `third_person_attachment` mesh from `dark_pact_skins`. Assigning that
attachment as an AI breed's `base_unit` would omit the enemy unit's actors,
extensions, hit zones, locomotion, inventory, and network contract.

A safe implementation therefore needs five new breeds cloned from the ordinary
AI specials, with cosmetic attachment spawning added separately. Every peer must
register identical breed/network lookup rows. The host may then replace an
already selected matching special at a bounded default 5% probability. This is
event-level replacement, not mutation of the shared vanilla breed.

## Runtime diagnostics

Enemy Tweaker v0.7.48-dev writes exactly six `[et:452]` lines at load: one summary
and one row for each proposed variant. The census is read-only and reports:

- base breed and `BreedActions` availability;
- premium `ItemMasterList` and `Cosmetics` availability;
- exact third-person attachment path;
- whether `Application.can_get("unit", path)` currently sees that mesh;
- confirmation that the mesh is a player attachment, not an AI base unit;
- ordinary breed behavior-tree, inventory-template, and network-lookup readiness;
- the number of owner/source skeleton nodes required by the attachment map.

The existing `ConflictDirector._post_spawn_unit` hook is shared with the boss
grudge feature rather than duplicated. When each of the five ordinary specials
spawns naturally, it writes at most one additional `[et:452] live` line for that
breed. Fatshark's `AttachmentUtils.link` reads each map row's `source` node from
the owner and its `target` node from the attachment. The line therefore compares
every de-duplicated owner/source node in the premium mesh's
`AttachmentNodeLinking` map with the real AI unit and reports a bounded sample
of at most eight missing nodes. Across a session the live probe is capped at
five lines. It does not spawn or link a cosmetic and makes no gameplay change.

Run `/et_regression_test` and require
`issue452_special_variant_assets_classified` and
`issue452_live_probe_bounded` to pass. Attach the current log if
it fails or if any row reports `resident=false`. This census can be performed
solo. Let normal play produce `[et:452] live` rows; `compatible=true` proves the
owner-side skeleton seam for that breed. Eventual attachment target-node rendering,
custom-breed lookup parity, and replacement must still be verified in co-op.

## Behavior slices

The work should proceed independently after the common clone/appearance/wire
foundation:

1. Shadowskulk: speed/health, then proximity visibility and downed-pounce damage.
2. Mist-Runner: speed/health, hook-state acceleration, hoist timing, stagger immunity.
3. Putrescent Kin: armor, burst duration, cone spread, stamina damage.
4. Festerblight: armor and explosion radius, then a portable lingering fire area.
5. Bile-Blight: bile ground/camera effect, then a bounded replicated curse-stack buff.

Do not begin with the curse or lingering-area effects: they add new buff/area
lifecycles before the common breed, attachment, package, and peer-parity seams
have been proven.

## Source evidence

- `scripts/settings/equipment/item_master_list_cosmetics_2024_q2.lua:3-104`
  registers the five `skin_1001` items.
- `scripts/settings/dlcs/cosmetics_2024_q2/cosmetics_cosmetics_2024_q2.lua:4-103`
  defines their player bases and attachment meshes.
- `scripts/settings/dlcs/carousel/attachment_node_linking_vs.lua:217-1036`
  defines the full player-skeleton node maps consumed by the live compatibility
  probe.
- `scripts/settings/breeds/breed_players_vs.lua:5-404` clones ordinary breeds
  for player-controlled Pactsworn; it is not an AI-special variant system.
- The five ordinary AI sources are `breed_skaven_gutter_runner.lua`,
  `breed_skaven_pack_master.lua`, `breed_skaven_poison_wind_globadier.lua`,
  `breed_skaven_warpfire_thrower.lua`, and `breed_skaven_ratling_gunner.lua`.
