# Weapon-history evidence and reproduction

This directory owns bounded, source-exact weapon-history slices for Tweaker:
Weapons issue #1436. It is an offline build input, not runtime content.
Nothing below `tools/weapon-history/` belongs in a Workshop bundle.

## Anchors and evidence

The Patch 5.2 generator projects three immutable historical revisions directly
onto the current decompiled-source anchor:

| State | Source revision |
|---|---|
| Game version 5.1.1 | `8224b4436e20905a6ba463cb28fa2d7771bb2330` |
| Game version 5.2.0 | `4f496970e2e7514bef7d612ab91331aa065d5e52` |
| Game version 5.2.3 | `cdc0a86e24e017119e6d6998870bf76f6e76e868` |
| Current content anchor (6.12.0) | `038498af2b565bcb10bf5ed225638293a7640c83` |
| Observed canonical default tip (README-only child) | `fd46866fe4d9aad8a1f1480fad4be6b960d4f83e` |

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

### Patch 4.1.1 boundary

Patch 4.1.1 uses an adjacent-boundary contract for the Masterwork Pistol:

| Role | Source revision |
|---|---|
| Game version 4.0.1 | `872027662e076477451c8c4bf077473d8ab9e27d` |
| Post-boundary 4.1.1 | `d5f1fa23c97e0e324db047cabb21faeffa9819bf` |
| Current content anchor (6.12.0) | `038498af2b565bcb10bf5ed225638293a7640c83` |

The adjacent evidence selects exactly one operation on
`heavy_steam_pistol_template_1.ammo_data.reload_on_ammo_pickup`: historical
`true`. Current source retains the key with value `false`; absence and false
are therefore distinct guard states throughout extraction, generation,
planning, rollback, and restore. Independent 3-by-3 true/false/absent
self-tests pin that presence contract in both evaluator lanes. The official
boundary is [Patch 4.1.1](https://forums.fatsharkgames.com/t/patch-notes-version-4-1-1/43407).

### Patch 4.6 boundary

Patch 4.6 uses the exact adjacent profile boundary and rehydrates only the
approved Hagbane payload against the current profile schema:

| Role | Source revision |
|---|---|
| Game version 4.5.1 | `0cec9547152a395c4f35f75288f29d8b18b8294f` |
| Post-boundary 4.6 scripts | `b38754a3bd61983118215359845d5b4fe5005014` |
| Current content anchor (6.12.0) | `038498af2b565bcb10bf5ed225638293a7640c83` |

The declared source closure is six files at all three revisions: the base
power/profile files, the Morris/Cog/Woods profile contributors loaded during
rehydration, and the Hagbane weapon template. The gate preflights all 18 exact
revision/path/blob objects, then disables lazy fetch and optional Git locks for
every extractor, oracle, route, and catalog read.

The profile evaluator finds exactly two adjacent leaves: Patch 4.6 adds
`allow_dot_finesse_hit = true` to `shortbow_hagbane` and
`shortbow_hagbane_charged`. The historical selector registers two deterministic
private profiles cloned from the current 6.12.0 payloads with only those flags
removed, then parity-gates the two source-proven current template routes. It
never mutates the shared native profiles. Current is a zero-write state; a
missing route refuses the complete two-route plan before any write.

The adjacent Hagbane template evidence is retained as an exclusion ledger: the
`__symbol` row is decompiler/refactor noise, `aoe_on_bounce` is explicitly
Ricochet-talent behavior, and the separately declared `weapon_diagram` root is
presentation-only. None enters the weapon-balance catalog. Moonfire Bow is also
excluded from this independently safe slice because its historical
state crosses a global buff profile route, buff timing, and two live explosion
table references that the current runtime cannot yet commit as one peer-safe
transaction. The official boundary is [Patch 4.6](https://www.vermintide.com/news/patch-46-patch-notes).

### Patch 6.6 boundary

Patch 6.6 uses an adjacent-boundary contract across both Deepwood Staff source
owners:

| Role | Source revision |
|---|---|
| Game version 6.5.4 | `5a74a378502353b075cbe0c3abe37da07f1d9bc9` |
| Post-boundary 6.6.0 scripts | `877aa9b2720d297e0594f7039773eca610324f5b` |
| Current content anchor (6.12.0) | `038498af2b565bcb10bf5ed225638293a7640c83` |

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
| Current content anchor (6.12.0) | `038498af2b565bcb10bf5ed225638293a7640c83` |

The adjacent 6.7.2-to-6.8.1 evidence selects exactly one operation: Kerillian's
Greatsword first-heavy `range_mod`, `1.55` to historical `1.45`. A second
evidence file re-reads only that selected path at 6.7.2 and 6.12.0 to establish
the runtime guard. Both primary and independent exact-double evaluators must
agree. The official boundary is [Patch 6.8.0 / Hotfix 6.8.1](https://forums.fatsharkgames.com/t/geheimnisnacht-and-the-skull-of-blosphoros-return-patch-6-8-0-hotfix-6-8-1/113884).

## Exact reproduction

From the repository root, with the pinned Vermintide source checkout available:

```powershell
$lua = '.\qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'
$source = 'C:\path\to\Vermintide-2-Source-Code'
& $lua '.\tools\weapon-history\generate_patch_4_1_1_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_4_1_1' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_4_1_1_catalog.lua'

& $lua '.\tools\weapon-history\generate_patch_4_6_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_4_6' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_4_6_catalog.lua'

& $lua '.\tools\weapon-history\generate_patch_5_2_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_5_2' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_5_2_catalog.lua'

& $lua '.\tools\weapon-history\generate_patch_6_0_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_6_0' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_6_0_catalog.lua'

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
.\qa\check_wt_history_patch_4_1_1_reproducibility.ps1 -SourceRepo $source -RequireSource
.\qa\run_wt_history_patch_4_1_1_host_matrix.ps1
.\qa\check_wt_history_patch_4_6_reproducibility.ps1 -SourceRepo $source -RequireSource
.\qa\run_wt_history_patch_4_6_host_matrix.ps1 -SourceRepo $source -RequireSource
.\qa\check_wt_history_reproducibility.ps1 -SourceRepo $source -RequireSource
.\qa\check_wt_history_patch_6_0_reproducibility.ps1 -SourceRepo $source -RequireSource
.\qa\run_wt_history_patch_6_6_host_matrix.ps1
.\qa\check_wt_history_patch_6_8_reproducibility.ps1 -SourceRepo $source -RequireSource
```

`current_source_anchor.lua` is the single identity consumed by all six
generators and their PowerShell checks. It separates the semantic 6.12.0
content commit from the later README-only default-branch tip. Ordinary QA runs
`check_wt_history_source_freshness.ps1` opportunistically: an unreachable
remote reports a visible skip while all pinned offline evidence remains
blocking, but a reachable mismatched or malformed remote fails. Canonical
BuildOnly/release runs use `-RequireRemoteFresh`, so network unavailability or
any default-ref/tip movement blocks before compilation. The probe is bounded
`git ls-remote --symref`; its advertised 1--60 second budget includes bounded
termination proof. PowerShell 7 uses `Process.Kill(true)`. Windows PowerShell
5.1, whose process API cannot kill descendants, invokes the trusted
`%SystemRoot%\System32\taskkill.exe /PID <pid> /T /F` with captured output,
exit status, and a bounded helper-process containment budget. A nonzero,
timed-out, or unproven tree kill is unavailable (visible skip in ordinary QA,
failure when freshness is required). Real nested parent/descendant and injected
taskkill failure/timeout fixtures prove both hosts leave no helper orphan. The
probe never fetches or writes `FETCH_HEAD`.

The Patch 5.2 gate verifies the pinned evidence extractor, generator, source catalog,
independent oracle/spec/routes, evidence hashes, and generated public catalog.
When the source checkout is present it rehydrates all nine evidence artifacts
through both evaluators, requires byte-exact primary output and exact-double
semantic agreement with the independent oracle, regenerates the route/blob
oracle, then requires byte-exact catalog equality. In source-less CI it still
enforces every pinned artifact and reports source regeneration as a visible
skip. The Patch 4.1.1, Patch 4.6, and Patch 6.8 gates apply the same fail-closed policy to
their adjacent boundaries, current-anchor rehydration, two evaluators, and
generated catalogs. The Patch 4.1.1, Patch 4.6, and Patch 6.6 host matrices
apply that policy under both PowerShell 7 and Windows PowerShell 5.1; Patch 4.6
accepts `-SourceRepo` and `-RequireSource` for the strict release proof, while
ordinary source-less QA reports pinned-only validation without claiming source
regeneration. Patch 4.1.1 pins present-false preservation and Patch 6.6 includes
both source paths plus the server-authority runtime contract. The Patch 4.6 gate additionally pins its
seven-artifact census, independently regenerates the two current profile
routes, and proves both emitted private profiles differ from current only by
the absent finesse flag. Before any of the six reproduction gates
selects a source checkout, the central read-only selector proves every pinned
commit, `commit:path` identity,
and blob object. A stale or partial checkout is therefore unavailable: ordinary
QA emits a visible skip, while `-RequireSource` fails closed. Selection never
fetches, lazily retrieves promisor objects, mutates the checkout, or relies on
`FETCH_HEAD`.
`qa/check_wt_stream_parity.ps1` separately proves that the dev stream
carries the namespace-normalized catalog.

Do not hand-edit the generated catalog. A deliberate evidence or generator
revision must be regenerated from immutable source, reviewed, and accompanied
by an explicit update to the pinned hashes in the reproducibility gate.
