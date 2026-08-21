# Old Musket Asset Pipeline

This recipe implements the repository-wide
[`../../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md`](../../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md)
for the Old Musket and issue #1155.

## Why the old export failed

The licensed Sketchfab DAE is one unparented mesh. Its barrel points along +X,
its DAE metadata is Y-up, and its object origin is at the model's geometric center --
roughly halfway down the barrel. It has no grip, root, or muzzle node. The old
conversion only changed FBX exporter axes, so CWV tried to compensate with five
different absolute runtime poses. RainReligion's CWV 0.1.524-dev run proved the
model and authored material survived every tested surface and a mission
transition, but every pose postcondition failed and rifle/bayonet orientations
were visibly wrong.

This is an asset-frame defect, not a package or material defect.

## Empirical donor frame

The first-party Empire Handgun 1P and 3P compiled units were extracted from the
installed VT2 bundles for read-only comparison and imported with Bitsquid
Blender Tools. Both use an identity root. Their longitudinal axis is +Y. A
complete signed geometry comparison also gives the donor's transverse
distribution: X `[-0.0346,+0.0482]` and Z `[-0.1434,+0.1151]`. This matters
because a 180-degree roll around +Y preserves the longitudinal axis while
reversing both transverse signs.

The root-to-`j_trigger` displacement used for the semantic anchor is
`(X=0, Y=-0.00376364007, Z=0.03986279666)`.

The native Tuskgor Spear was inspected separately. It uses an identity root and
points along +Z. Therefore one normalized asset cannot be identity under both
parents: rifle surfaces use the Handgun frame at identity, while bayonet mode
uses one explicit +90 degree X-axis adapter to map +Y onto the polearm's +Z.

This is the same successful principle used by Doomrocket's Warlock Engineer
weapon pipeline: preserve a known-good engine attachment frame, bake source
geometry into that frame around a semantic grip/root, and do not multiply by a
character hand inverse.

## Deterministic semantic root

The source file is pinned by SHA-256
`A20C6161C9B6302FF424BFC801D036BEE2C8D793D3A027BE309140C04B791550`,
10,014 vertices, 16,483 polygons, 26,411 edges, one UV layer, and a fingerprint
over all 110 disconnected component sizes. The unique 366-vertex trigger lever
is the reviewed landmark. Its upper 2 mm cap contains exactly 42 vertices and
acts as the trigger-pivot proxy. That pivot is matched to the native Handgun
`j_trigger` displacement to locate the weapon root. This follows Doomrocket's
successful semantic-grip method while avoiding an unsafe AABB-center or
nearest-surface heuristic.

CWV 0.1.525 used source +Y -> Handgun +Z and source +Z -> Handgun +X. Rain's
live run proved that basis was upside down on every renderer. The accepted
right-handed mapping is the exact 180-degree +Y roll of that failed basis:

- source +X -> native +Y (forward);
- source -Y -> native +Z;
- source -Z -> native +X.

The trigger pivot remains pinned to native `j_trigger`. The opposite cap of the
same unique trigger component is a second signed landmark: from the pivot it
must resolve to approximately `(0.00187, 0.02359, 0.04711)`. This prevents a
future dominant-axis or absolute-dot test from accepting the upside-down
antipode again. The normalized signed bounds, X
`[-0.00824,+0.04306]` and Z `[-0.14237,+0.09674]`, now agree with the donor's
signed distribution rather than only its unsigned span.

Any source, topology, component, landmark, material-slot, UV, or round-trip
bounds drift aborts conversion.

## Rebuild

From the repository root:

```powershell
& .\character_weapon_variants\tools\convert_old_musket_assets.ps1
```

The default input is the audited local extraction under
`%USERPROFILE%\Downloads\old-musket\extracted\model\model.dae`, and the
default converter is Blender 4.4 under `%ProgramFiles%`. The command rewrites
the checked-in 1P and 3P FBXs and `old_musket_asset_contract.json`. The raw
licensed source and native donor assets are not copied into the repository.

## Verification boundary

The converter reimports both outputs and proves exact renderer name
`rifle`, material slot `rifle_mat`, topology, UV presence, canonical bounds,
an ordered geometry/winding digest, and identical 1P/3P bytes. Repository QA
pins the checked-in byte hashes as integrity values and separately pins the
stable semantic digest; Blender FBX object IDs and timestamps are exporter
metadata and are not themselves evidence of a different weapon.
Post-build QA then parses the compiled v189 unit resources and independently
proves exact resource cardinality, one `rifle` renderer, 16,483 triangles,
signed bounds, +Y dominance, both signed transverse roll inequalities,
identical 1P/3P geometry, and the
`rifle_mat`-to-authored-material binding. Custom-unit reachability remains a
separate explicit-bundle-root check.

Offline gates prove the coordinate and resource contracts, not final animation
composition. The first normalized candidate still requires bounded live checks
for rifle and bayonet modes in owner 1P, owner 3P, inventory character preview,
and illusion/CIM display. Co-op husk verification follows only after those solo
cells retain their exact pose.

The runtime descriptor retains rotations only as finite `(x,y,z,w)` numbers.
At the atomic `Unit.set_local_pose` boundary, the Old Musket adapter reconstructs
one same-frame value with `Quaternion.from_elements`. Raw Stingray Quaternions
are opaque temporary values: they must neither be stored nor probed for Lua
fields such as `.unbox`. The structured receipt records the atomic mode, node,
bounded error, and post-write readback so a construction or setter failure
cannot masquerade as retained identity.
