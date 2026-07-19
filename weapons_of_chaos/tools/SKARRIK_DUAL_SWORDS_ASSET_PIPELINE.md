# Skarrik Dual Swords asset pipeline

This records the reproducible, source-backed part of issue #615. It does not
claim that the item is registered or safe to equip yet. Runtime registration
must remain disabled until the shared multi-relic appearance and wire adapter
can carry both hands through owner, preview, bot, husk, transition, and
mixed-peer surfaces without adding a second competing spawn/sync hook.

## Native identities

The decompiled game/source inventory identifies Skarrik's hands separately:

- right: `units/weapons/enemy/wpn_skaven_set/wpn_skaven_sword_dual_right`
- left: `units/weapons/enemy/wpn_skaven_set/wpn_skaven_sword_dual_left`

Both resources and their materials were traced to bundle
`53f7c35959299191`. The source material references native texture IDs
`28E105E0AD31F399` (albedo), `A9D9E4D3A8440FF5` (tangent normal), and
`EC0DEBBFA142BC2B`. Listing the exact source bundle reports the last texture as
zero bytes; it is a default/empty resource, not missing image data. The authored
material therefore preserves the real albedo and normal and supplies explicit,
bounded roughness and metallic maps rather than inventing pixels for that empty
resource.

## Authored units

The extracted meshes are hand-specific and retain their material-slot names.
The first-person and third-person files are explicit package resources, even
where their current FBX bytes are identical, so later hold-pose tuning cannot
silently couple the two presentation channels.

| Resource | SHA-256 |
| --- | --- |
| `skarrik_sword_left.fbx` | `1A8D57C6744D22C9CAA80DE26BF62D369D98FFF3FE73B0895B54FC69252068AF` |
| `skarrik_sword_left_3p.fbx` | `1A8D57C6744D22C9CAA80DE26BF62D369D98FFF3FE73B0895B54FC69252068AF` |
| `skarrik_sword_right.fbx` | `FAD2FF7065C878DE9CEB6BF11750776DD325B958F38BAEBDD3255F63B2C8649E` |
| `skarrik_sword_right_3p.fbx` | `FAD2FF7065C878DE9CEB6BF11750776DD325B958F38BAEBDD3255F63B2C8649E` |

The extracted native DDS inputs were:

| Native input | Role | SHA-256 |
| --- | --- | --- |
| `28E105E0AD31F399.dds` | albedo | `5E5751305E5D1ED8E742101263E70912C48D14459AC223BB14E608CA8182FCDA` |
| `A9D9E4D3A8440FF5.dds` | tangent normal | `01971E3D3E556E393379DE35FD17EAB75F36A07FCF420F05D1E4603F4D3011C8` |

The checked-in compile inputs are under
`textures/woc_skarrik_dual_swords/`; their exact hashes and package closure are
enforced by `qa/check_woc_skarrik_asset_sources.ps1`.

## Shared Skarrik material ownership

Issue #615 owns the single authored Skarrik material and texture closure at
`units/woc_skarrik_dual_swords/skarrik_swords`. The champion halberd authored
under #614 uses the same native material family and references this exact path;
it must not copy these four textures or fork the material graph. Integrate and
compile #615 before #614. The unified boss catalogue then observes both asset
families through its authored-resource facet without loading or registering
either weapon.

## Runtime boundary

The safe fallback remains the resident player dual-swords identity
`we_dual_wield_swords` using `dual_wield_swords_template_1`. Same-WOC peers may
reconstruct the authored left/right appearance locally from a bounded relic
identity. Never serialize custom unit paths to an unmodded peer, and never add a
second `GearUtils.spawn_inventory_unit` or loadout-sync hook: extend WOC's
existing descriptor-driven chokepoint instead.
