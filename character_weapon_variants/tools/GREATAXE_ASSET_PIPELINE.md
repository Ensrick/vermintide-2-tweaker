# Greataxe Asset Pipeline

Issue #597 replaces CWV's Poleaxe with a Kruber Greataxe and five temporary
illusion names. This pipeline converts the user's licensed Sketchfab downloads
without committing the original archives or source-authoring files.

## Source and deduplication record

| Asset | Sketchfab UID | Download archive SHA-256 |
|-------|----------------|--------------------------|
| `axe_01` | `a6d3f8a9816e427d95648dfafe77714f` | `B3B98FBAEDB7CA7A61074A0BDF67D46F2AA2019DF38232FA44581C396964E8C9` |
| `axe_02` | `220e559cd70a4cb9b73e4e19df23377e` | `A8F5E38EE3303BA670B3248C0ADA6812D9E1094ED136613ADC1B385F54CB398E` |
| `axe_03` | `54992b8b04bd41d29476fe77bd2b6a8c` | `6FD8B00B73F3B7C9B69FAC5F24A6AC29FAEDBAF3E25918BABC1A1B9212D3C149` |
| `axe_04` | `5e2c48044a9045a2b24014fa59db3d8b` | `B95BD2F9E1AEEB5E57027712EEA9360714416C9EF662BA14C854A13D793CDC6E` |
| `axe_05` | `ae71823d5dc8451c96c7ca0f56d83a07` | `3EF0D8FCD5275EA45D394990D0E282D2253E7A351369815515552D850D5351B9` |

`battle-axe(1).zip` duplicated `battle-axe.zip` byte-for-byte, and
`viking-war-axe(1).zip` duplicated `viking-war-axe.zip` byte-for-byte. Only one
archive from each pair enters the working source tree. The two archives named
`viking-axe` have different hashes and model UIDs, so both are real candidates.

The CC-BY 4.0 author/source/license record is in `../THIRD_PARTY_NOTICES.md`.

## Local source tree

The default untracked source root is:

`C:\Users\danjo\source\repos\_cwv_greataxe_sources`

Expand the five licensed downloads into the numbered folders used by the
manifest in `convert_greataxe_assets.ps1`. Nested source ZIP/RAR archives must
also be expanded. Do not move those raw sources into `character_weapon_variants`.

## Rebuild

From the repository root:

```powershell
& .\character_weapon_variants\tools\convert_greataxe_assets.ps1
```

Requirements are Blender 4.4, ImageMagick 7, and the Vermintide 2 SDK standard
material at its normal Steam path. Override `-SourceRoot`, `-Blender`,
`-Magick`, or `-ModRoot` for another workstation.

The Blender helper joins geometry, emits one `axe_mat` material slot,
normalizes the inferred handle to two units along positive X, and writes a JSON
conversion report beside the untracked sources. The wrapper generates 1P/3P
FBX and unit resources, a PBR material, processed five-map texture sets, and
`.texture` definitions. All ten units, five materials, and texture directories
are flattened into CWV's master package. Do not generate unit-named sibling
packages: vanilla previewers resolve those through the global package namespace,
which cannot discover Workshop-defined paths. CWV's preview bridge borrows a
vanilla Greataxe package reference while spawning the resident custom unit.

Compilation proves only that Stingray accepts the resource graph. Each illusion
still needs in-game 1P, local 3P, remote-husk, inventory-preview, and illusion-
browser inspection. Use WT's live transform tools for final rotation, offset,
and scale; bake accepted values into the canonical CWV definition afterward.
