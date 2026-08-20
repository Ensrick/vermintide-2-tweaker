# Custom Weapon Model Import Pipeline

**Status:** canonical and normative for custom weapon geometry in this repository.

This guide turns a downloaded or authored model into a Vermintide 2 weapon
without repeating the Old Musket and issue #597 Greataxe failures. It covers
asset provenance, conversion, Stingray resources, runtime residency, preview
package discovery, multiplayer serialization, appearance surfaces, automated
gates, and co-op verification.

Read this together with [Weapon Appearance Standard](WEAPON_APPEARANCE_STANDARD.md)
and the owning mod's development guide. The appearance standard defines what
must render consistently; this document defines how a new resource safely
reaches those render paths.

## 1. The three independent proofs

A compiled model is not automatically usable. A custom weapon is ready only
when all three statements are independently true:

1. **Resident:** the custom unit, material, and textures are inside a package
   root actually loaded from the mod's `.mod` file.
2. **Preview-loadable:** vanilla preview code can acquire a package lifetime
   reference without asking `Application.resource_package` to discover a
   Workshop-defined path.
3. **Wire-safe:** every custom package name that can enter a profile inventory
   map serializes through `NetworkLookup.inventory_packages` without placing a
   custom reverse identity on peers.

Issue #597 proved why these are separate. The Greataxe first compiled but was
not resident from a runtime root, then became resident and previewable but still
crashed when `ProfileSynchronizer` serialized its custom `_3p` path.

## 2. Licensing and provenance gate

Do not convert an asset until its redistribution rights are recorded. “Free,”
“downloadable,” and “purchased” describe acquisition, not the right to commit
derived geometry and textures to a public repository or Workshop item.

For every candidate, record:

- title, author, author profile, source URL, and stable model UID;
- exact license name and license URL as shown at download time;
- download date and original archive SHA-256;
- whether duplicate downloads are byte-identical;
- which original files were selected;
- every technical or artistic modification;
- attribution text required in the mod's `THIRD_PARTY_NOTICES.md`.

CC0 and CC-BY assets are normally usable when their terms are satisfied. Other
licenses require a project decision before conversion. In particular, do not
ship NC-restricted assets while the project's public-use decision is pending,
and do not ship an AI/UUID-labelled model whose author, source, and license
cannot be proven. Sketchfab's “Free Standard” or paid Standard license must be
reviewed against the intended source and Workshop redistribution; never infer
permission from the price.

Keep original archives and source-authoring files in an untracked working tree.
Commit only the approved derived resources, reproducible conversion scripts,
the source manifest/hashes, and required notices. The Greataxe precedent is
`character_weapon_variants/tools/GREATAXE_ASSET_PIPELINE.md` plus
`character_weapon_variants/THIRD_PARTY_NOTICES.md`.

For extracted first-party game resources, record the source bundle/unit hash,
selected object/LOD, dependency texture hashes, channel interpretation, and
derived output hashes instead of inventing third-party attribution. Do not
commit unpacked game bundles or unmodified native resources. The Blightreaper
precedent is `weapons_of_chaos/tools/BLIGHTREAPER_ASSET_PIPELINE.md` plus its
scripted high-LOD export.

## 3. Source formats and conversion target

VMB/Stingray should receive FBX as the final mesh input.

| Source format | Use | Notes |
|---|---|---|
| FBX | Preferred | Lowest-friction input and the current Greataxe output. Re-export through the pinned Blender pipeline even when the download is already FBX. |
| GLB/glTF | Acceptable staging format | Good at retaining PBR texture relationships. Import into Blender, normalize, then export FBX. The current automated Greataxe helper does not yet accept it. |
| OBJ + MTL | Acceptable fallback | Geometry is simple, but material and texture relationships need explicit reconstruction. Current helper supports OBJ. |
| Collada/DAE | Legacy fallback | Used by Old Musket and one Greataxe source. Current helper supports DAE. |
| USDZ | Not supported by the current pipeline | Convert through a reviewed DCC workflow first; do not add an ad-hoc converter to a release task. |

Pin Blender and image-tool versions in the asset-specific guide. Conversion
must be scriptable and repeatable; hand-edited exports without a recorded
recipe are not a stable source of truth.

## 4. Normalize mesh space before game tuning

The current Greataxe reference helper performs these technical changes:

1. remove non-mesh scene objects and detach inherited parents;
2. join all weapon mesh objects;
3. apply object location, rotation, and scale;
4. collapse to one short material slot such as `axe_mat`;
5. normalize the longest dimension to two Blender units;
6. put the inferred handle butt at the origin;
7. point the handle from the origin along positive X;
8. export FBX with `axis_forward=-Z`, `axis_up=Y`, applied unit scale, and no
   leaf bones.

Short material-slot names are mandatory. FBX exporters can truncate long
material paths, leaving a compiled `.unit` that references a nonexistent hash.
Bind a short slot to the full material resource in the `.unit` file.

Normalization creates a predictable starting point; it does not replace
in-game tuning. Perspective, character skeleton, attachment node, and animation
pose can all change the apparent orientation. Tune position, Euler/quaternion
rotation, and scale in 1P, local 3P, and preview. Bake accepted values into the
canonical per-weapon appearance definition. Never leave release behavior
dependent on a developer's live tuner store.

Do not treat `1p`, `3p`, or a shared node name as a complete transform key.
Select a closed-vocabulary attachment profile from the actual parent frame and
store every profile in the same appearance descriptor. The Old Musket
`0.1.524-dev` candidate separates held rifle and held polearm frames for owner
1P/character 3P from the camera-world display carrier used by loot, Athanor, and
illusion previews. Its display position `{0, 0, 0}`, Euler rotation
`{-90, -90, 0}`, and scale `{1, 1.1, 1.1}` are deliberately isolated for live
tuning. Offline tests can prove that the correct profile reaches each consumer;
they cannot prove those numbers look correct in the renderer.

## 5. Mesh, material, and texture resources

Each visual model needs at least:

```text
units/<family>/<model>/<model>.fbx
units/<family>/<model>/<model>.unit
units/<family>/<model>/<model>_3p.fbx
units/<family>/<model>/<model>_3p.unit
```

The `_3p` sibling is not optional: gameplay and previews derive it from the
base unit name. The same geometry may be copied initially, but the units must
carry perspective-appropriate render settings. The proven convention is
`shadow_caster = false` for 1P and `true` for 3P.

Two material strategies are supported:

### 5.1 Full PBR material

Use this when the asset must retain its own appearance. Derive a material from
the SDK's standard material and bind an explicit five-map set:

```text
textures/<family>/<model>/<model>_albedo.png + .texture
textures/<family>/<model>/<model>_normal.png + .texture
textures/<family>/<model>/<model>_roughness.png + .texture
textures/<family>/<model>/<model>_metallic.png + .texture
textures/<family>/<model>/<model>_ao.png + .texture
```

- albedo is sRGB;
- normal, roughness, metallic, and AO are linear;
- invert legacy gloss maps to obtain roughness;
- treat a legacy specular map only as a documented metallic approximation;
- use neutral white for missing AO rather than inventing detail;
- cap source textures at the project limit (currently 2048 for Greataxe).

The master package must list the custom material paths as well as units and
textures. A material file existing on disk does not prove that its shader or
texture dependencies compiled into the loaded root.

### 5.2 Vanilla-material/LA-style binding

Use this only when a named, tested runtime consumer actually reads the metadata
and binds the foreign material. Stingray's ordinary `GearUtils` and loot/hero
preview spawn paths do **not** interpret arbitrary `data.mat_to_use`; storing a
vanilla material reference there does not create a renderer binding. The August
20 #1155 Old Musket log proved both Handgun packages resident before the custom
unit still resolved `rifle_mat` to `#ID[00000000]`.

The default and preferred pattern is therefore section 5.1: bind the FBX slot in
the `.unit` top-level `materials` table to a mod-owned `.material`, include that
material and every texture dependency in the loaded master package, prove all
resources before any native call, and census the material handles after binding.
Old Musket `0.1.524-dev` is the self-contained reference candidate: source,
manifest, native-resource, and engine-free checks prove the authored closure,
but in-game material retention is still pending the #1155 solo matrix. A
foreign/LA binding must document its real consumer, its renderer-local residency
proof, and an actual fallback; package interception alone is only balanced
lifetime bookkeeping and never evidence that the foreign material attached.

Do not solve first-person depth/shadow problems by spawning a generic child
overlay unless the feature is genuinely an attachment. The Old Musket overlay
attempt rendered on the wrong layer, over the hands, and with incorrect shadow.

## 6. Unit definition and display rig

The custom unit is the weapon mesh. `display_unit` is a separate vanilla stage
rig used by inventory/illusion preview code to attach that mesh. Select a
vanilla display rig with the correct authored nodes:

- single weapon: matching single-hand or two-hand family rig;
- shield: a shield-and-weapon rig with left and right attachment nodes;
- dual wield: a dual rig containing both `j_rightweaponattach` and
  `j_leftweaponattach`.

Do not inherit `display_unit` blindly from an illusion belonging to another
shape. A wrong rig can compile and then crash only when the picker calls
`Unit.node`. Record the vanilla item/skin used as the display-rig precedent.

If the imported FBX has no weapon skeleton, do not call `Unit.node` speculatively
or rely on `pcall`; missing Stingray nodes can be engine-fatal. Use
`Unit.has_node` before decorative link operations, or author the expected bones.
The root attachment still has to link the weapon to the hand.

## 7. VMB authoring and the runtime-root rule

All active mods build through VMBLauncher. Do not invoke raw VMB, the SDK
compiler, or upload tools directly.

The mod's source `.mod` declares one or more package roots:

```lua
packages = {
    "resource_packages/<mod>/<mod>",
}
```

The corresponding master `.package` must directly include every custom unit,
material, and texture required at runtime. The current CWV Greataxe pattern is
explicit/flattened:

```text
unit = [ custom 1P and 3P unit paths ]
material = [ custom material paths ]
texture = [ custom texture directories ]
```

### Master root versus standalone package

These are not equivalent:

- **Master/root package:** named by `.mod packages`; VMF loads it and its
  flattened resources become resident.
- **Standalone or forwarding package:** may compile to a `.mod_bundle`, but is
  not resident unless it is itself an explicit load root that the runtime can
  actually discover.
- **Vanilla global package:** discoverable by
  `Application.resource_package`; Workshop-defined package names are not.

Do not count a generated `.mod_bundle`, a nested `package = [...]` edge, or a
same-hash file beside the root as proof of residency. Issue #597's first crash
was caused by exactly that assumption. Flattening all Greataxe resources into
the explicit CWV master root made them resident.

## 8. Preview package collection

Hero/inventory and loot/illusion previewers collect package names from the
resolved unit paths and ask the global package manager to load them. The custom
unit may already be resident, but `Application.resource_package(custom_path)`
still cannot discover a Workshop package by that name.

The proven custom-path bridge has two responsibilities:

1. replace the previewer's package lifetime reference with a resident vanilla
   analogue (for Greataxe, Bardin's vanilla Greataxe package);
2. leave `spawn_data.unit_name` pointing at the custom unit while
   `Application.can_get("unit", custom_path)` proves residency.

If residency is absent, fail closed by changing spawn data to the vanilla
analogue and logging the mismatch once. Never proceed to `World.spawn_unit`
with an unproven custom unit. Translate custom bookkeeping keys back to the
borrowed vanilla package during unload.

CWV's reference implementation is `_cwv_mod_unit_preview.lua`. It covers both
`HeroPreviewer._load_packages` and `LootItemUnitPreviewer.load_package`; fixing
only one menu is incomplete.

## 9. ProfileSynchronizer and network lookup safety

`ProfileSynchronizer` serializes the inventory's first- and third-person
package maps through strict `NetworkLookup.inventory_packages`. Residency and
preview aliases do not affect this encoder. A custom name lookup will crash if
it lacks an index.

For every custom model, provide two forward aliases:

```lua
custom_1p_path       -> vanilla_1p_index
custom_1p_path_3p    -> vanilla_3p_index
```

Read base indices with `rawget`; `NetworkLookup` tables use strict missing-key
metatables. Install aliases only when the vanilla indices exist. Missing base
indices must fail closed.

**Never overwrite the reverse mappings** (`index -> path`) for an ordinary
custom weapon. Reverse decode must remain the vanilla path, so a peer without
the mod receives only a vanilla, resident identity. A mod-capable peer may then
restore the exact custom model through the existing bounded appearance/identity
channel. Do not stream model state per frame, and do not add an unbounded RPC
because a visual was imported.

The Old Musket established this forward-only pattern. Issue #597 extends it to
all five Greataxe models: ten custom paths alias to the matching two vanilla
Greataxe indices, with tests proving that reverse decode is unchanged.

## 10. Render-surface completeness

Registration is incomplete until the selected model is consistent on every
applicable surface:

| Surface | Required observation |
|---|---|
| Owner first person | Correct mesh, material, depth, scale, grip, and attack motion |
| Owner local third person | Correct mesh, transform, shadow, wield and attack animations |
| Remote husk | Other mod-capable player sees the exact selected model and baked transform |
| Bot | Host and client render the bot consistently |
| Inventory character preview | Exact instance/illusion, correct pose and display rig |
| Illusion/Athanor preview | Every model opens and swaps without load or attachment crash |
| Lobby/keep presentation | Model persists across join, wield, and inventory transitions |
| End-of-mission score/team preview | Exact item does not revert to the base model |

Use the shared appearance identity and per-hand contract. Do not add separate
model-resolution logic for each surface; that recreates the visual
“whack-a-mole” class this repository is eliminating.

Peers without the content mod must never be asked to load a custom unit, skin,
icon, or package. Their allowed degradation is a vanilla model/identity, not a
crash. Icons and custom cosmetics need the same positive peer-capability gate.

## 11. Automated gates

Before deployment, require all applicable gates:

1. **Provenance test:** source manifest, license decision, notices, archive
   hashes, and duplicate classification are present.
2. **Conversion test:** scripted conversion reproduces the expected mesh names,
   material slot, bounds/orientation report, and 1P/3P pair.
3. **Source resource test:** each model has its `.fbx`, `.unit`, `_3p.fbx`,
   `_3p.unit`, material strategy, and expected texture definitions.
4. **Manifest test:** the explicit master package includes every required
   unit/material/texture and does not rely on an unrooted forwarding bundle.
5. **Compiled reachability:** run
   `qa/check_custom_unit_bundle_reachability.ps1`. It Murmur64-hashes authored
   units and proves each is physically present in a bundle named by an explicit
   `.mod` package root. A skipped gate is not a pass for release evidence.
6. **Policy unit tests:** enumerate every model, both package paths, preview
   alias, wire alias, missing-base behavior, and preserved reverse map.
7. **Repository QA:** run the offline Lua suite, relevant localization/name
   gates, `git diff --check`, and the owning mod's lint/regression suite.
8. **Clean VMB build:** use `VMBLauncher.exe build <mod>` and inspect fresh
   `bundleV2` output. Use the bundle unpacker/Murmur hashes to prove resources;
   raw byte search cannot see hashed entries.

Automated gates prove structure and serialization policy. They cannot prove
pose quality, material appearance, animation playback, or observer parity;
those remain in-game tests.

## 12. Deploy and co-op verification

Follow repository deployment doctrine. Build, deploy locally and to the active
remote tester target through VMBLauncher/`ship.ps1`; never hand-copy a bundle or
use raw upload tools. Confirm both peers report the intended mod version/hash
before interpreting a visual mismatch.

For every imported model:

1. craft it through CIM with automatic equip both off and on;
2. inspect the Athanor/illusion browser before and after selection;
3. inspect inventory character preview;
4. wield in the keep and enter a mission;
5. perform lights, heavies, charges, pushes, blocks, swaps, and career actions;
6. observe owner 1P and local 3P;
7. have the second player observe the remote husk, then swap weapons and rejoin;
8. test host and client ownership in both directions;
9. test a peer without the content mod and require vanilla fallback/no crash;
10. inspect lobby and end-of-mission team views;
11. restart the game and confirm exact-instance persistence;
12. attach both logs and check for package, resource, node, lookup, or fallback
    warnings.

A custom model that only works for the host or only after opening inventory is
not verified.

## 13. Issue #597 post-mortem and prevention

### Failure A: Athanor resource crash

**Symptom:** selecting Greataxe Model 01 crashed on resource hash
`f4c81c97baad78f8`.

**Cause:** all resources compiled, but the model units lived in forwarding
bundles that were not runtime load roots. The previewer then tried to discover
the custom path through the global package namespace. Compilation and bundle
existence were false-positive evidence.

**Fix:** flatten all ten units, five materials, and texture directories into
CWV's explicit master package; borrow a vanilla Greataxe package for preview
lifetime tracking; verify residency before spawning; add the compiled-root
reachability gate.

### Failure B: craft/auto-equip profile crash

**Symptom:** preview worked and the unit was resident, but crafting with
auto-equip crashed during profile resync because
`units/cwv_es_greataxe/axe_01/axe_01_3p` was absent from strict
`NetworkLookup.inventory_packages`.

**Cause:** preview package translation does not change the first/third-person
package maps collected for `ProfileSynchronizer`.

**Fix:** forward-alias all ten custom paths to vanilla Bardin Greataxe indices;
preserve reverse vanilla entries; fail closed if base indices are absent; test
the entire path set and reverse map.

### Prevention rule

Every new model row must land with all of these in the same change:

- 1P and 3P unit resources in an explicit runtime root;
- compiled reachability evidence;
- a vanilla preview-package analogue and missing-residency fallback;
- forward-only 1P/3P network aliases;
- model-count/path-completeness and reverse-map tests;
- the full owner/preview/remote/score verification matrix.

## 14. Troubleshooting

| Symptom | Likely boundary | First checks |
|---|---|---|
| SDK compile says material/resource missing | Authoring graph | Short FBX material slot; material exists; texture paths and `.texture` definitions match; avoid compile-validated references to unavailable vanilla materials |
| Bundle exists but `Application.can_get("unit", path)` is false | Runtime root | `.mod packages` root; master package directly lists unit; run compiled reachability gate |
| `Resource '#ID[...]' was not found` in preview | Global package discovery | Murmur-hash the requested path; confirm preview bridge substitutes a vanilla package and preserves/falls back spawn data |
| Strict `inventory_packages` missing-key crash | Profile/equip wire | Both custom 1P/3P forward aliases; `rawget` vanilla indices; reverse map untouched |
| Preview shows vanilla but in-world is custom | Preview spawn identity | `spawn_data.unit_name`, exact skin/instance resolution, residency fallback warning, both previewer hooks |
| Owner sees custom but client sees vanilla | Appearance capability/replay | peer versions, positive capability handshake, exact appearance lifecycle replay, remote husk reapply on wield/join |
| Client without mod crashes | Unsafe custom payload | reverse lookup overwritten, custom skin/icon/package sent without parity, missing vanilla fallback |
| Weapon is red, transparent, or untextured | Material/texture | compiled material and channel maps, sRGB flags, sampler names, material applied on that render surface |
| Weapon faces wrong direction or floats | Transform | normalized mesh axes, attachment hand, baked per-character 3P transform, preview transform path |
| `j_leftweaponattach` or another node crashes | Display/link rig | matching vanilla display rig, left/right unit fields, `Unit.has_node` guard, authored bones |
| Correct in mission, wrong on inventory or score screen | Surface duplication | shared appearance resolver, MenuWorldPreviewer/team preview hooks, exact instance identity |
| Works only after opening inventory or swapping | Missing lifecycle edge | apply at spawn/wield/join/transition rather than relying on menu refresh side effects |

When the engine reports only a resource hash, compute Murmur64 for suspected
paths and inspect the compiled root bundle. Do not guess from filenames or
assume the newest source reached the deployed Workshop build.
