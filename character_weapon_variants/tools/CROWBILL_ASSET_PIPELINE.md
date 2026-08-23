# Crowbill Asset Pipeline

This asset-specific recipe implements the repository-wide
[`../../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md`](../../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md)
for issue #604. It converts only the six approved CC-BY 4.0 models. The
Sketchfab Free Standard Italian War Hammer is intentionally absent from the
source manifest, conversion script, package root, and shipped notices.

## Approved source manifest

| Output | Original model | Sketchfab UID | Selected source | Archive SHA-256 |
|---|---|---|---|---|
| `imperial_01` | Medieval War Hammer by Parelaxel | `665734b41cce4a49abeb757c3bda7705` | `WarHammerSF.fbx` plus the `WarHammer_Hammer_*` PBR maps | `A90B5FB669AAB55C3FC0C46A21815FC6A4FC573706EFF1B49B144F6B32C107CA` |
| `dawi_01` | War Hammer by soidev | `97ffc67970b54bebb35aa08f4723753e` | `Hammer.fbx` plus the `Hammer_HammerHead_*` and `Hammer_HammerHandle_*` PBR maps | `A02A997C3E04822C1830597AC3C2457EA5D97AFDBD445F6C30BFDD5EDF565B87` |
| `imperial_02` | war_hammer by Loqual | `cf9ad0c7fa8e4cecb323ecfadc787bea` | `model.dae` (`45643E59FF6B49FFF24A6984BB36B31BB8A8A258DD6141B3DC2DB67CDA7ECACA`) plus the `initialShadingGroup_*` PBR maps | `5741795455E8552114938C1B7B7BAC7BABBF03B2E71076DA1662E06BB53B9C2F` |
| `imperial_03` | Medieval Steel Warhammer by Peter Nox | `85caa1dc806c46fb9d256572fcd5854a` | `model.dae` (`F695D1582CE66FD1CD5E60EC4021770B461A3654A68F49120585E55DE602A382`) plus the `Material.001.01_*` PBR maps | `6B3E6E217936F3E6EBFCA5640F5330047872AF2C28684822D188EBAA5DEB4E38` |
| `imperial_04` | Warhammer - [ Diablo II ] by Ole Gunnar Isager | `6d9963339387410c9127811b72307e8f` | `Warhammer_low.fbx` (`4B844461ED3BC92F44568712E9C0A2BB7441195A668AD601937DD5070EE26421`) plus the `lambert1_*` PBR maps | `BDE2DF7A400A16529C83D9474B0ECBD158FB3DBC52B479FEAF4D10777CA0F819` |
| `imperial_05` | Steel Warhammer by Peter Nox | `ae48855265ee4fa4b7c80218f16a3c56` | `model.dae` (`BE1C897EB14CB6FE9A399B4A6B3247B195E8B4CD4A0052BAA3F53DD435AADDBC`) plus the `Material_*` PBR maps | `10B7534C8CF4E3C132692D78E2CEE9F7D89AC239615FB8349FF4FB4E93038DD8` |

All six archives were downloaded from Sketchfab on 2026-07-14. The duplicate
`medieval-war-hammer(1).zip` has the same SHA-256 as the selected archive and
does not enter the working source tree.

The four later archives are not duplicates of the first three audited models
or of one another: their Sketchfab UIDs, archive hashes, extracted mesh hashes,
vertex/polygon counts, normalized FBX hashes, and texture-set fingerprints all
differ. Their Blender import counts are `imperial_02` 10,317 vertices / 16,438
polygons, `imperial_03` 933 / 1,429, `imperial_04` 1,404 / 2,504, and
`imperial_05` 1,913 / 2,466. These import counts can exceed the Sketchfab API's
displayed vertex count because Blender splits vertices at UV/normal seams.

The selected extracted payloads are independently fingerprinted so a nested
source ZIP or texture substitution cannot masquerade as the same archive:

| Output | Selected mesh SHA-256 | Sorted texture-set SHA-256 |
|---|---|---|
| `dawi_01` | `CC2C8F42A710288846A58FA50FE17AAD923DE41586353380AA01C89141608119` | `6BC6A36BC87A2D0F68953FD9683E2F4D4CF4B2114AB1F6311B0930792AE91627` |
| `imperial_01` | `68283FD7DFB18F1ECFA96F50A944D5A5E718B74C73A5752B468CD3B5FFB5D8F8` | `CF1D80B947DB37F9464BB3F8F3AFAF63ACD984564F5F4B5771976EFE8B3B90AA` |
| `imperial_02` | `45643E59FF6B49FFF24A6984BB36B31BB8A8A258DD6141B3DC2DB67CDA7ECACA` | `31B6CAD4DB7C0E5CA66C02E808CE94917F68E0E88D0F156CA799EE65B428B764` |
| `imperial_03` | `F695D1582CE66FD1CD5E60EC4021770B461A3654A68F49120585E55DE602A382` | `E7CA28520B828082A59EE740989A41B22C57A2FF548D335E83C6AAFDE231D3BD` |
| `imperial_04` | `4B844461ED3BC92F44568712E9C0A2BB7441195A668AD601937DD5070EE26421` | `F61662D220821CF65EC74356202919FF3AA82CC3B3996F17FE1CAD006988E44C` |
| `imperial_05` | `BE1C897EB14CB6FE9A399B4A6B3247B195E8B4CD4A0052BAA3F53DD435AADDBC` | `67BC7F20A420563FEA46B5913BBAF2F3D8112BCBCBC3F4561FE6EE20FF641340` |

The texture-set fingerprint is SHA-256 over sorted `filename:file-SHA256`
records, not over filesystem timestamps or ZIP metadata.

## Untracked source tree

Raw archives and source-authoring files stay outside the public repository:

`C:\Users\danjo\source\repos\_cwv_crowbill_sources`

The checked-in wrapper verifies each original archive SHA-256 before producing
derived resources. It will not silently rebuild from a renamed or changed
download.

## Rebuild

From the repository root:

```powershell
& .\character_weapon_variants\tools\convert_crowbill_assets.ps1
```

The pinned defaults are Blender 4.4.0 and ImageMagick 7.1.2 Q16-HDRI. The
Blender helper joins and applies mesh geometry, normalizes the longest dimension
to two Blender units, places the inferred handle butt at the origin, aligns the
haft along positive X, collapses the mesh to the short `crowbill_mat` slot, and
exports FBX using `axis_forward=-Z` and `axis_up=Y`.

`imperial_01` arrives with independent head and handle material/UV spaces. The
helper places `HammerHead` and `HammerHandle` into the left and right halves of
one atlas before material collapse; the wrapper builds each matching atlas in
that same order. Both outputs receive separate 1P and `_3p` FBX/unit siblings.
Source maps are capped at 2048 pixels. Neither source includes AO, so the
pipeline supplies a neutral white AO map rather than inventing surface detail.

Conversion reports are written beside the untracked sources as
`<asset>-conversion.json` for all six outputs. Perspective- and
character-specific offsets, rotations, and scale must be tuned in game and then
baked into canonical appearance data; they are not hand-edited into these FBX
files.

## Runtime and verification boundary

The derived units, materials, and texture directories are flattened directly
into CWV's explicit master package root. Previewers borrow Sienna's globally
discoverable vanilla Crowbill package only as a lifetime anchor. Inventory
serialization uses forward-only aliases to the matching vanilla 1P/3P package
indices; reverse decoding remains vanilla-safe.

Compilation and bundle reachability prove residency, not visual correctness.
Before release, inspect owner 1P, owner 3P, bots, remote husks, inventory and
lobby previews, end-screen presentation, and illusion preview. Repeat after
weapon swap, respawn, mission transition, hot-join, host/client reversal, and
with a peer lacking CWV.
