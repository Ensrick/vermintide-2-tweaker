# Crowbill family

The Crowbill family is registration-first. It exposes two stable CWV item
identities while replacement art remains blocked on provenance and licence
review:

| Item | Authored defaults | Current model | Gameplay source |
|---|---|---|---|
| `cwv_es_imperial_crowbill` | All Kruber and Saltzpyre careers | Resident vanilla Crowbill placeholder | `bw_1h_crowbill` / `one_handed_crowbill` |
| `cwv_dr_dawi_crowbill` | All Bardin careers | Resident vanilla Crowbill placeholder | `bw_1h_crowbill` / `one_handed_crowbill` |

CWV registers definitions only. CIM owns crafting and persistence; these items
must never be automatically granted. WT exposes independent controls for all 20
careers, with only the authored defaults enabled initially. Cosmetics owns the
distinct item-type/skin-table contracts and sources eligible vanilla illusions
from `bw_1h_crowbill`. Chaos Wastes uses the generic dedicated CWV Deus identity
so exact item type and cosmetics survive conversion when peer parity permits.

## Hammer mode contract

Weapon Special toggles between normal Crowbill mode (the default) and Hammer
mode. Hammer mode rotates the model 180 degrees around its authored haft axis,
keeps the same moveset and timing, multiplies attack and impact cleave by 1.60,
multiplies direct damage by 0.85, and removes armour piercing from light attacks.
The mode applies to both CWV variants; applying it to vanilla Sienna Crowbill is
an optional CWV setting. Runtime mechanics live in the isolated hammer-mode
module and consume `_cwv_crowbill_family.lua` rather than duplicating constants.

Presentation is owned by `_cwv_crowbill_presentation.lua`. It captures the
authored/native base rotation once and computes `base * local-Z(180°)` for
Hammer mode; returning to Crowbill mode writes the captured base. The same
resolver is called from owner/bot equipment creation, remote-husk spawning,
the shared Hero/MenuWorld preview reconstruction seam, and the item browser.
Weak tracking permits one bounded reapply at a mode transition. There is no
per-frame pose application or mode RPC. This is model-path agnostic, so a
licensed custom unit selected by the manifest receives the same presentation
contract as the current resident placeholder.

## Asset gate

No downloaded or custom mesh path may enter the registration module, master
package, or preview alias map until the asset audit records author, source URL,
licence, redistribution/modification permission, archive hash, and attribution.
Until then every surface must use the resident vanilla placeholder.

### Candidate audit — 2026-07-14

The original archives remain outside the repository. Their Windows download
provenance streams identify the exact Sketchfab model UIDs; archive hashes and
the public Sketchfab API were checked on 2026-07-14.

| Intended use | Model and author | Source / licence | Original payload | Archive SHA-256 | Decision |
|---|---|---|---|---|---|
| Dawi Crowbill | Medieval War Hammer by Parelaxel | [Sketchfab `665734b41cce4a49abeb757c3bda7705`](https://sketchfab.com/3d-models/medieval-war-hammer-665734b41cce4a49abeb757c3bda7705), [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) | `WarHammerSF.fbx`; one 4096px base-color/metallic/normal/roughness set; 2,532 vertices / 4,498 triangles | `A90B5FB669AAB55C3FC0C46A21815FC6A4FC573706EFF1B49B144F6B32C107CA` | Approved for a future attributed conversion. `medieval-war-hammer(1).zip` is a byte-identical duplicate and must not enter the source set. |
| Imperial Crowbill candidate A | War Hammer by soidev | [Sketchfab `97ffc67970b54bebb35aa08f4723753e`](https://sketchfab.com/3d-models/war-hammer-97ffc67970b54bebb35aa08f4723753e), [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) | `Hammer.fbx`; separate head/handle 2048px base-color/metallic/normal/roughness sets; 788 vertices / 1,310 triangles | `A02A997C3E04822C1830597AC3C2457EA5D97AFDBD445F6C30BFDD5EDF565B87` | Approved for a future attributed conversion. |
| Imperial Crowbill candidate B | war_hammer by Loqual | [Sketchfab `cf9ad0c7fa8e4cecb323ecfadc787bea`](https://sketchfab.com/3d-models/war-hammer-cf9ad0c7fa8e4cecb323ecfadc787bea), [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Collada; 10,317 Blender-import vertices / 16,438 polygons; complete PBR set | `5741795455E8552114938C1B7B7BAC7BABBF03B2E71076DA1662E06BB53B9C2F` | Approved as provisional Imperial Model 02. |
| Imperial Crowbill candidate C | Medieval Steel Warhammer by Peter Nox | [Sketchfab `85caa1dc806c46fb9d256572fcd5854a`](https://sketchfab.com/3d-models/medieval-steel-warhammer-85caa1dc806c46fb9d256572fcd5854a), [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Collada; 933 Blender-import vertices / 1,429 polygons; complete PBR set | `6B3E6E217936F3E6EBFCA5640F5330047872AF2C28684822D188EBAA5DEB4E38` | Approved as provisional Imperial Model 03. |
| Imperial Crowbill candidate D | Warhammer - [ Diablo II ] by Ole Gunnar Isager | [Sketchfab `6d9963339387410c9127811b72307e8f`](https://sketchfab.com/3d-models/warhammer-diablo-ii-6d9963339387410c9127811b72307e8f), [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) | FBX; 1,404 vertices / 2,504 polygons; complete PBR set | `BDE2DF7A400A16529C83D9474B0ECBD158FB3DBC52B479FEAF4D10777CA0F819` | Approved as provisional Imperial Model 04. |
| Imperial Crowbill candidate E | Steel Warhammer by Peter Nox | [Sketchfab `ae48855265ee4fa4b7c80218f16a3c56`](https://sketchfab.com/3d-models/steel-warhammer-ae48855265ee4fa4b7c80218f16a3c56), [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Collada; 1,913 Blender-import vertices / 2,466 polygons; complete PBR set | `10B7534C8CF4E3C132692D78E2CEE9F7D89AC239615FB8349FF4FB4E93038DD8` | Approved as provisional Imperial Model 05. |
| Excluded candidate | Italian War Hammer by pepe (`pepetos`) | [Sketchfab `1b159f52cb9646f98b31b0da98f79e97`](https://sketchfab.com/3d-models/italian-war-hammer-1b159f52cb9646f98b31b0da98f79e97), [Sketchfab Free Standard](https://sketchfab.com/licenses) | `model.dae`; 8 mesh objects; one 4096px albedo/AO/metallic/normal/roughness set; 8,082 API vertices / 15,920 triangles | `BC2375EA42E8BBF489BF5F2447C7F68E19907F38F50248E602048A674C1C9BF5` | **Permanently excluded.** Do not convert, package, register, or ship. |

The six approved CC-BY sources require author/profile/source/licence entries in
`THIRD_PARTY_NOTICES.md` when derived resources are actually committed. Their
technical modifications must also be listed there. The user permanently
excluded the Free Standard Italian candidate; it must not be converted,
packaged, registered, or added to the shipping notice.

Conversion must follow `docs/CUSTOM_WEAPON_MODEL_PIPELINE.md`: re-export through
the pinned Blender workflow to FBX, join and apply mesh transforms, normalize
the longest dimension to two Blender units, put the handle butt at the origin
with the haft along positive X, use a short material slot, and export with
`axis_forward=-Z` / `axis_up=Y`. Emit separate 1P and `_3p` FBX/unit siblings,
cap PBR maps at 2048px, use neutral white AO where the source has none, and bake
only accepted in-game scale/offset/rotation values into the canonical family
definition after all appearance surfaces have been checked.

## Appearance and pose verification

Every replacement model or hammer-mode change must explicitly pass each cell:

| Surface | Model/skin | Transform/mode face | Wield/idle + attacks |
|---|:---:|:---:|:---:|
| Owner first person | ☐ | ☐ | ☐ |
| Owner local third person | ☐ | ☐ | ☐ |
| Bot | ☐ | ☐ | ☐ |
| Remote husk | ☐ | ☐ | ☐ |
| Inventory-screen character preview | ☐ | ☐ | ☐ |
| Lobby character presentation | ☐ | ☐ | ☐ |
| End-of-mission score/team preview | ☐ | ☐ | ☐ |
| Illusion/Athanor preview | ☐ | ☐/n/a | n/a |

Also verify weapon swap, death/respawn, mission transition, hot-join, host/client
ownership reversal, game restart, and a peer without CWV. A peer without the mod
must receive a vanilla-safe identity and must never be sent a custom resource.
