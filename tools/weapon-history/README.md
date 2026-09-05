# Weapon-history evidence and reproduction

This directory owns bounded, source-exact weapon-history slices for Tweaker:
Weapons issue #1436. It is an offline build input, not runtime content.
Nothing below `tools/weapon-history/` belongs in a Workshop bundle.

## Anchors and evidence

The generator projects three immutable historical revisions directly onto the
current decompiled-source anchor:

| State | Source revision |
|---|---|
| Game version 5.1.1 | `8224b4436e20905a6ba463cb28fa2d7771bb2330` |
| Game version 5.2.0 | `4f496970e2e7514bef7d612ab91331aa065d5e52` |
| Game version 5.2.3 | `cdc0a86e24e017119e6d6998870bf76f6e76e868` |
| Current anchor (6.11.3) | `c5e4968b1fbb00c49884e56d640ef990a9c04dd0` |

The inert Lua modules in `evidence/patch_5_2/` preserve the semantic snapshots,
damage profiles, family ownership, explicit exclusions, official patch-note
URLs, and SHA-256 evidence ledger. The generator fails closed if the filtered
operation budgets drift from `91 / 74 / 9`, the global-operation budget differs
from `8`, or the profile-route budgets differ from `11 / 3`.

`extract_weapon_history.lua` is the preserved source evaluator that owns those
evidence values. It pins the C numeric locale and emits finite doubles with
`%.17g`, the Lua 5.1-safe round-trip boundary. Both its symbolic-expression
formatter and final serializer use that contract. Set `WT_HISTORY_OUTPUT` when
generating an artifact so it writes canonical LF bytes through a binary handle.

`source_oracle/` is an independent evaluator/specification lane. It encodes
numbers as exact `math.ldexp` expressions, regenerates current template routes
and Git blob identities, and semantically compares every preserved snapshot and
profile against immutable source. See `source_oracle/README.md`.

Official scope references:

- [Patch 5.2.0](https://www.vermintide.com/news/gifts-of-the-wolf-father-and-patch-520)
- [Hotfix 5.2.3](https://forums.fatsharkgames.com/t/hotfix-megathread-5-2-x-current-5-2-3/91155)

### Patch 6.6 boundary

Patch 6.6 uses an adjacent-boundary contract across both Deepwood Staff source
owners:

| Role | Source revision |
|---|---|
| Game version 6.5.4 | `5a74a378502353b075cbe0c3abe37da07f1d9bc9` |
| Post-boundary 6.6.0 scripts | `877aa9b2720d297e0594f7039773eca610324f5b` |
| Current anchor (6.11.3) | `c5e4968b1fbb00c49884e56d640ef990a9c04dd0` |

The adjacent evidence selects exactly three absent historical leaves: the
`chaos_bulwark` row in `staff_life` and `staff_life_vs` prioritized breeds, and
the matching `spirit_storm.reduce_duration_per_breed` row. Current values are
`1`, `1`, and `0.5`. Removing all three recreates the pre-6.6 behavior while
leaving later rows such as `chaos_tether_sorcerer` untouched. The evaluator's
`table.set` implementation and its capture of the side-effect assignment to
`DLCSettings.woods.vortex_templates` are covered by byte-exact regeneration in
both source evaluators. The official boundary is [Patch 6.6.0 / Hotfix 6.6.1](https://forums.fatsharkgames.com/t/new-map-the-well-of-dreams-live-now-skulls-in-game-event-patch-6-6-0-hotfix-6-6-1/108063).

This family is deliberately host/solo only. Vanilla
`ActionSpiritStorm.fire` sends `rpc_summon_vortex` to the server, the server
spawns the network vortex, and `SummonedVortexExtension` reads the vortex
template's breed-duration multiplier. A client-side selector could therefore
present a selected state without owning the authoritative behavior. The
runtime refuses the historical state on a client and transactionally applies
or restores all three leaves on the host.

### Patch 6.8 boundary

Patch 6.8 uses an adjacent-boundary contract so later edits to the same source
file cannot leak into the historical selector:

| Role | Source revision |
|---|---|
| Game version 6.7.2 | `b7c15fc61a3b34fae7d1e2de47f52198e26851ce` |
| Post-boundary 6.8.1 | `447f4eb49921ba08fbbbb945609ce2b9891f4898` |
| Current anchor (6.11.3) | `c5e4968b1fbb00c49884e56d640ef990a9c04dd0` |

The adjacent 6.7.2-to-6.8.1 evidence selects exactly one operation: Kerillian's
Greatsword first-heavy `range_mod`, `1.55` to historical `1.45`. A second
evidence file re-reads only that selected path at 6.7.2 and 6.11.3 to establish
the runtime guard. Both primary and independent exact-double evaluators must
agree. The official boundary is [Patch 6.8.0 / Hotfix 6.8.1](https://forums.fatsharkgames.com/t/geheimnisnacht-and-the-skull-of-blosphoros-return-patch-6-8-0-hotfix-6-8-1/113884).

## Exact reproduction

From the repository root, with the pinned Vermintide source checkout available:

```powershell
$lua = '.\qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'
$source = 'C:\path\to\Vermintide-2-Source-Code'
& $lua '.\tools\weapon-history\generate_patch_5_2_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_5_2' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_5_2_catalog.lua'

& $lua '.\tools\weapon-history\generate_patch_6_6_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_6_6' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_6_6_catalog.lua'

& $lua '.\tools\weapon-history\generate_patch_6_8_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_6_8' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_6_8_catalog.lua'
```

Then run the non-mutating exact-output gate:

```powershell
.\qa\check_wt_history_reproducibility.ps1 -SourceRepo $source -RequireSource
.\qa\run_wt_history_patch_6_6_host_matrix.ps1
.\qa\check_wt_history_patch_6_8_reproducibility.ps1 -SourceRepo $source -RequireSource
```

The Patch 5.2 gate verifies the pinned evidence extractor, generator, source catalog,
independent oracle/spec/routes, evidence hashes, and generated public catalog.
When the source checkout is present it rehydrates all nine evidence artifacts
through both evaluators, requires byte-exact primary output and exact-double
semantic agreement with the independent oracle, regenerates the route/blob
oracle, then requires byte-exact catalog equality. In source-less CI it still
enforces every pinned artifact and reports source regeneration as a visible
skip. The Patch 6.8 gate applies the same fail-closed policy to its adjacent
boundary, current-anchor rehydration, two evaluators, and generated catalogs.
The Patch 6.6 host matrix applies that policy under both PowerShell 7 and
Windows PowerShell 5.1, including both source paths and the server-authority
runtime contract.
`qa/check_wt_stream_parity.ps1` separately proves that the dev stream
carries the namespace-normalized catalog.

Do not hand-edit the generated catalog. A deliberate evidence or generator
revision must be regenerated from immutable source, reviewed, and accompanied
by an explicit update to the pinned hashes in the reproducibility gate.
