# Blightreaper Asset Pipeline

This is the reproducible source record for the issue #613 Blightreaper import.
It supplements the repository's canonical custom weapon model pipeline.

## Source identity

The hub trophy `units/props/inn/hub_trophy/hub_trophy_bogenhafen` is a posed
diorama and must never be used as a held unit or passed to PackageManager. The
actual sword is a separately placed unit in the Bögenhafen city level bundle:

- unit resource: `A9AECA9EA15818DA`;
- source unit SHA-256:
  `8FE2CAE290D03416F4625BBF0C6E2DCB19750EECC6B713F48C2988C00D286F04`;
- selected high-LOD object: `6692D5DA`;
- geometry: 2,608 vertices, 2,858 polygons;
- native high-LOD material: `A9AECA9EA15818DA`.

This is a derived Fatshark game resource used only by this Vermintide 2 mod;
third-party model attribution does not apply. Do not commit unpacked game
bundles or the unmodified native unit.

## Material resources

The native material resolves these texture resources:

| Resource | Role | Source DDS SHA-256 |
|---|---|---|
| `E6AB38B75D7D9F4E` | albedo | `86E527D685F3B00C8ACBDEE12302F9D90180961A1C9DCF5858ABB816A9681EE2` |
| `751BDA5C60330E94` | two-channel tangent normal | `A585D41B32F97169047FAC48697E5247437A829BD4093A9C565A3A379DC9059A` |
| `19E12EFD2E45F9F2` | packed metallic/roughness/rune mask | `41A6BB34BDDE0E3DF13D591854CB11C18BFF2813134F86CF197310F738C16544` |
| `2E82F037A3245005` | native pulsing-shader noise, bound to both parent-material pulse slots | `E86BA601B35DD93D6E497544564C5687414C1E6D41A8CDBD8B02C2DFF4B30E6F` |

The packed channels become R=metallic, G=roughness, and B=emissive. Rebuild
normal Z from the decoded R/G channels before exporting the normal PNG:

```text
z = 0.5 + 0.5 * sqrt(max(0, 1 - (2r - 1)^2 - (2g - 1)^2))
```

Committed derived-output hashes:

| Output | SHA-256 |
|---|---|
| `blightreaper.fbx` | `BCF1F7D5ED0CBC26C5AEA6AD9FA01249DDD63422747F02AFCDC3C46770D6920F` |
| `blightreaper_albedo.png` | `C0F30302B5C7BA9509F9E6F9EE34667F70832BADFC97D4D61C57E03719D65A06` |
| `blightreaper_normal.png` | `9A6EE50C9EE14249364698A1CAAAD2EF94BD0F57F191936B3ADABC420CCB4057` |
| `blightreaper_metallic.png` | `11B23D104ABB9669E161A145076000E87D36B9123EA72BB40D48FD2FF4FEFEBA` |
| `blightreaper_roughness.png` | `D8286E6E1F0DE1531188B083B044613AB7F57B453BE889EC048E1D532EF6F6E4` |
| `blightreaper_emissive.png` | `8370D8FDAC18720A178BED690D4A31F5B69356F1CE7331289438DBB1DA4F727B` |
| `blightreaper_packed.png` | `8E8138764578B2FC760FE34CF0A14C2D293A711F4DB19364074ED9355E0046C9` |
| `blightreaper_noise.png` | `7CA9AAC06D3749E7F0B3EFFEF9837E7AF4E581D20C33889B82DF9C94CCAE2D1A` |

The decompiled native material retains parent `EA15CAA2A17CD818`, maps the
packed texture into slot `15DD7D93`, maps the same noise texture into both
`499B0151` and `66402E57`, and retains gold `{5, 4.4, 0}` plus scalar
`1.746000051498413`. These are research inputs, not compile-ready Stingray
source. An unquoted hash fails material parsing; a quoted hash parses but the
SDK compiler then requests the unavailable source path
`EA15CAA2A17CD818.material`. Do not retry either hash form: neither is a
buildable material source.

## Pulse donor

The native appearance is shader-driven emissive animation. No Blightreaper
particle, flow, or unit animation binding was found. The base-game Kruber runed
Empire sword is the bounded replacement shader donor:

- 1P unit/material/package:
  `units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1_runed_01`;
- 3P sibling: the same path with `_3p`;
- standalone package hashes verified in the installed bundles:
  `767E95AC6F261662` (1P) and `F378E3B3BCD290B4` (3P);
- vanilla availability is grounded by
  `scripts/settings/equipment/weapon_skins.lua:3886,3900`.

Its decompiled material has the same behavioral contract as the trophy:
two noise inputs, `rune_emissive_color`, `intensity`, `pulse`, and matching
UV/pulse vectors. WOC binds that resident material once per spawned WOC unit,
then replaces its albedo, normal, packed M/R/rune, emissive, and both noise
inputs with WOC resources. It sets the native trophy values
`rune_emissive_color={5,4.4,0}`, `intensity=1.746000051498413`, and
`pulse={1,0.5}`. The different 1P/3P rune slots are explicitly described by
`_woc_appearance_policy.lua`.

All resources are preflighted with `Application.can_get` before any engine
material call. Texture writes use the vanilla per-unit primitive
`Unit.set_texture_for_materials` (see `gear_utils.lua:150`), never shared
`Material.set_texture`. Application is spawn/event driven, weakly deduplicated,
and has no update loop or RPC. If a donor material or WOC texture is absent, it
logs one bounded `[WOC:613] pulse SKIP` line and leaves the compile-valid WOC
material in place.

## Mesh export

Use Blender with Bitsquid Blender Tools enabled. Set:

- `WOC_EXTRACT_ROOT` to the unpacked resource root containing the source unit;
- `WOC_BITSQUID_PYDEPS` to the add-on's Python dependency directory.

Then invoke Blender in background mode:

```powershell
blender --background --python weapons_of_chaos/tools/export_blightreaper_fbx.py -- `
  <extract-root>/A9AECA9EA15818DA.unit `
  weapons_of_chaos/units/woc_blightreaper/blightreaper.fbx
```

The script selects only the verified high LOD, assigns the short
`blightreaper_mat` slot, rotates the native Z-long sword onto the player weapon
X axis, centers the cross-section, moves the pommel to the origin, preserves
the native 1.515 m length, and exports `-Z` forward / `Y` up. Copy the verified
FBX byte-for-byte for the initial `_3p` sibling; perspective differences live
in the `.unit` render settings.

## Build and reachability

The WOC master package explicitly lists the material, both units, five static
PBR textures, the native packed map, and the native pulse-noise map. Run:

```powershell
pwsh -NoProfile -File qa/check_custom_unit_bundle_reachability.ps1
pwsh -NoProfile -File qa/check_dofile_package_coverage.ps1
VMBLauncher.exe build weapons_of_chaos
```

Never add a `Managers.package:load` call for the authored unit path. Previewers
and loadout collection borrow the verified runed Empire sword package lease
while the WOC master bundle owns the actual unit residency.

The canonical presentation transform is applied once per spawned unit through
the synchronized `_lib_weapon_appearance.lua` consumer: Euler XYZ
`{-90, -90, -90}` degrees and offset `{0, 0, -0.3}`. Do not duplicate these
values in individual preview hooks or drive them per frame.
