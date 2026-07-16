# Dawi Mace family

Issue #602 defines three CWV gameplay identities:

| Item key | Gameplay source | Default careers | Cosmetic ownership |
|---|---|---|---|
| `cwv_dr_dawi_mace` | Kruber Mace | Ranger Veteran, Ironbreaker, Slayer | Primary mace |
| `cwv_dr_dawi_mace_shield` | Kruber Mace and Shield | Ranger Veteran, Ironbreaker | Shield owns the icon; mace and shield remain independently selectable |
| `cwv_dr_dawi_dual_maces` | CWV Dual Maces | Ranger Veteran, Ironbreaker, Slayer | Primary owns the icon; both hands remain independently selectable |

Tweaker: Weapons publishes all twenty careers for each identity. The authored
Bardin careers above are default-on; every other career is an explicit
default-off opt-in. CIM discovers and crafts the items through CWV's ordinary
`cwv_variant` registration contract. CWV does not grant inventory instances.

## Gameplay identity

The three variants reuse `one_handed_hammer_template_1`,
`one_handed_hammer_shield_template_1`, and `cwv_dual_maces_template`. Those are
the existing mace identities governed by issue #599. No per-item gameplay
template is cloned, so enabling the mace/hammer distinction modifies each
moveset once and cannot compound because several items share it.

## Asset boundary

The first public implementation uses resident vanilla Bardin hammer and shield
units as placeholders. Do not add the downloaded Tower Mace while its BY-NC
license decision is pending, and do not add the UUID-labelled AI model without
provenance. Final custom models may replace the placeholder unit paths after
license, attribution, conversion, package-residency, preview, and multiplayer
wire-safety review; they must not change the canonical item or skin-table keys.
The candidate hashes, geometry inspection, exact blockers, and resumable
integration contract are recorded in
[`tools/DAWI_MACE_ASSET_AUDIT.md`](tools/DAWI_MACE_ASSET_AUDIT.md).

Canonical skin tables are `<item_key>_skins`. Cosmetics owns exact-hand
persistence, independent dual/offhand selection, icon ownership, and peer
replay through `_cos_cwv_family_contract.lua`; no Dawi-specific RPC is needed.
