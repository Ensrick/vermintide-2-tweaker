# Dawi Mace Asset Audit

This issue #602 audit applies the repository-wide
[`../../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md`](../../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md)
to the two candidate payloads staged outside the repository at
`C:\Users\danjo\source\repos\_cwv_dawi_mace_sources`. The source files remain
untracked. Neither candidate is approved for conversion or inclusion in CWV's
public package as of 2026-07-15.

## Decision

| Candidate | Technical payload | Provenance and license | Result |
|---|---|---|---|
| Tower Mace | Complete DAE plus five 2048x2048 PBR maps | Identified as *Tower Mace* by iceboxX708, Sketchfab UID `7cc646d8e8084a5fb2961855bca284e8`, offered under CC Attribution-NonCommercial | Blocked until the project explicitly approves that license for source and Workshop redistribution |
| UUID model | FBX plus 4096x4096 base-color, normal, and packed metallic/roughness maps | No author, title, source URL, stable asset ID, license, receipt, or attributable download metadata | Rejected from conversion until provenance is supplied; it also needs a low-poly game mesh and documented packed-map channels |

The shipped Bardin hammer and shield placeholders therefore remain the only
safe presentation. This is an asset-boundary decision, not permission to clone
the items or create screen-specific substitutes. The canonical item keys,
skin-family keys, gameplay templates, CIM provider identity, and Cosmetics
exact-hand contract remain unchanged.

## Tower Mace evidence

- Source page: `https://sketchfab.com/3d-models/tower-mace-7cc646d8e8084a5fb2961855bca284e8`
- Author/profile: iceboxX708, `https://sketchfab.com/iceboxX708`
- Source page publication date: 2019-07-19
- Downloaded outer archive SHA-256:
  `7929EADFF79A10BF6C5FC8C568EEE8F3E6F367C8DA2713274D3392FC4F4ADF2D`
- Selected nested source archive (`source/model.zip`) SHA-256:
  `6D4CF23FF13C38AEED071DD3899FDF2DB6303C501C8EEEC04923923395C2CABF`
- Selected DAE SHA-256:
  `6C2237CF0A4B701DCE655A5C9322A185C77BAEB149567B1DA63009FC76270F81`
- The DAE names one `Tower_Mace_SG` material and records an Assimp export at
  `2019-07-19T21:38:53`, matching the source page and texture stems.
- The downloaded outer archive's Windows zone metadata points to Sketchfab's
  archive host and embeds the same `7cc646d8e8084a5fb2961855bca284e8`
  model UID. This proves acquisition identity, not permission beyond the
  page's CC Attribution-NonCommercial license.
- Blender 4.4.0 imports one mesh with 5,531 vertices and 3,852 polygons. The
  payload contains albedo, AO, metallic, normal, and roughness maps, all
  2048x2048. This is technically suitable for the normal scripted conversion
  path after license approval.

Selected nested texture hashes:

| Channel | SHA-256 |
|---|---|
| Albedo | `01D7F652C100DDCDCA781C9F938D89D64ECCE7CE445FE158559B678583EBADE7` |
| AO | `5258FE9755EA2232A8651D0D129E5942165067C7EE6332C815345FDBDE4B288C` |
| Metallic | `F271CFA1D107113E3F5D5C4D3879809353D57274C0D97CF80ED20E270D53619E` |
| Normal | `926E2F5804E8FC30F060EB40F8725D0AE252DEB896509F0BA0B69730ACA3301E` |
| Roughness | `876900FBB9E2E4DC8F0C466B762CA7298D65518520F38FE49DA555C106239793` |

The duplicate texture folder outside `model.zip` is not byte-identical to the
selected nested JPEG/PNG set, so it must not silently replace those inputs.

## UUID model evidence

Downloaded outer archive SHA-256:
`F692447957312B18C976897BF50409108EEC8E3799DB023C75B5BE622F1CE0B8`.
Its Windows zone metadata records only `HostUrl=about:internet`; it supplies no
origin page or rights statement.

| File | SHA-256 |
|---|---|
| `output.fbx` | `16054F14B2A9E3CFB98915BD027C89AD9F74D76976AAE080689F6C2D376FC655` |
| Base color | `9C688D6CFFFE538143CCED698434CC690EDB57E19E3D604DDDE011BE3431B0E8` |
| Normal | `A27FF0EFC1C950B948972C258E1B837604A6B9BF932570FC74B06F9FF40F5184` |
| Packed metallic/roughness | `346A436B0C94CBCDB522C6C20E1F73157BF1A4B17E9D372599517EA3B5B77DB9` |

The FBX metadata contains only Blender 4.2.8 exporter data, generic
`/foobar.fbx` document paths, mesh `node_0`, and material `Material.001`.
Windows alternate streams contain no referrer or download URL. Blender 4.4.0
imports one mesh with 270,698 vertices and exactly 500,000 polygons. The FBX
material connects only base color and normal; it does not define which channels
of the third image are metallic and roughness. These are independent blockers:

1. supply the original author/title/page or generation record, stable ID,
   license terms, acquisition date, and original archive hash;
2. provide or produce an approved low-poly mesh with a reproducible
   retopology/bake recipe rather than shipping the 500,000-polygon source;
3. document the packed-map channel layout and derive explicit linear metallic
   and roughness maps.

## Empirical unblock routes

No code or asset conversion may begin until one of these routes produces a
recorded redistribution decision:

1. the project owner explicitly accepts the Tower Mace's CC BY-NC terms for
   this public-source, donation-linked Workshop project, records the decision,
   and includes the required attribution and license notice;
2. the Tower Mace author grants separate written permission compatible with
   the repository and Workshop distribution, with that permission archived in
   the source manifest;
3. the UUID/AI candidate receives an attributable generation or download
   record, an applicable license, a documented packed-map layout, and an
   approved reproducible low-poly/texture bake, or it is replaced by a CC0 or
   CC-BY mace with complete provenance.

The user's request to use a supplied mace is acceptance criteria for the
feature, but it does not identify which of the two archives should ship and
does not replace the missing license decision. Until one route closes, keeping
the resident vanilla fallback is the only policy that satisfies the repository
asset gate.

## Exact integration contract after approval

An approved model should extend `_cwv_dawi_maces.lua` as one canonical model
policy, not register new items. The same right-hand unit supplies Dawi Mace,
Dawi Mace and Shield, and both hands of Dawi Dual Maces; the existing resident
shield remains the left-hand unit for the shield family unless a separately
approved shield asset is provided.

The conversion must provide distinct 1P and `_3p` FBX/unit siblings, a short
material slot, explicit five-map texture resources, and a reproducible source
manifest. Flatten every unit, material, and texture into CWV's master package.
Register the policy with `_cwv_mod_unit_preview.lua`, borrowing the resident
Bardin hammer package for preview lifetime only, and install forward-only 1P
and 3P `NetworkLookup.inventory_packages` aliases without changing reverse
decode. Preserve the existing display rigs:

- Dawi Mace: `display_1h_hammer`;
- Dawi Mace and Shield: `display_shield_hammer`;
- Dawi Dual Maces: `display_dual_hammers`.

Compilation and static reachability will not prove the feature complete. The
release verification matrix must cover inventory character preview, illusion
picker, owner 1P, owner/local 3P, bot and remote husk, hot-join, host/client
reversal, mission transition, score view, independent dual-hand cosmetics, and
a peer without CWV. Crafting and Salvage use CIM's common synthetic-item
contract tracked in issue #628; #602 must not add a Dawi-only inventory adapter.
