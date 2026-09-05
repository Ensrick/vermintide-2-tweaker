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
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |
| Observed canonical default tip (same commit) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

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

### Patch 2.0.6 boundary

Patch 2.0.6 uses an adjacent-boundary contract for Kruber's and Bardin's
Handguns:

| Role | Source revision |
|---|---|
| Game version 2.0.5 | `b5a93414e883825f69c61eb3e90e73f52d6c2e80` |
| Post-boundary Patch 2.0.6 | `750fa8f8a393d807f2f7205dfed4b60b6abe3c46` |
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

The adjacent source diff selects exactly three gameplay leaves on the former
shared Handgun template: hipfire and aimed `ignore_shield_hit` are absent, while
aimed `ignore_armour_hit` is `true`. Current source clones the same gameplay
table into `handgun_template_1` and `handgun_template_2`, then changes only
Bardin's presentation fields. The generator pins that immutable clone
relationship and emits the three historical leaves for each current clone, for
six operations total. Current Versus clones, key-order churn, and the adjacent
`weapons.lua` damage-over-time network fix remain explicitly excluded. The
official boundary is [Patch 2.0.6](https://forums.fatsharkgames.com/t/vermintide-2-patch-2-0-6-1/35277).

### Patch 2.0.9.1 boundary

Patch 2.0.9.1 uses an adjacent-boundary contract for Kruber's Halberd:

| Role | Source revision |
|---|---|
| Game version 2.0.9 | `6d41bab482ac64ebebc5c8bba2c3a47954952af9` |
| Post-boundary Patch 2.0.9.1 | `90c7c21adb7aa2b7de5fcdca5094727895fbeb1a` |
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

The official fix restored the missing overhead after the Halberd push attack.
The adjacent evaluator selects exactly 20 leaves under
`light_attack_down.allowed_chain_actions`: eleven scalar replacements, six
scalar removals, and three complete chain-row removals. The current-anchor pass
proves all 20 guards, including exact nested-table values for the three later
rows. The selector commits the complete chain change as one family transaction;
one missing, foreign, or stale leaf refuses before any write, and returning to
Current restores the original table identities. No profiles, RPCs, assets, or
ordinary Weapon Tweaks are part of this slice. The official boundary is
[Patch 2.0.9.1](https://forums.fatsharkgames.com/t/vermintide-2-patch-2-0-9-1/36058).

### Patch 2.0.10 boundary

Patch 2.0.10 uses an adjacent-boundary contract for Kerillian's Sword and
Dagger:

| Role | Source revision |
|---|---|
| Game version 2.0.9.1 | `90c7c21adb7aa2b7de5fcdca5094727895fbeb1a` |
| Post-boundary Patch 2.0.10 | `67d593c4f98653e1d511105b6adeebb5d6619c58` |
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

The adjacent damage-profile diff contains exactly two scalar changes:
`light_slashing_linesman_dual_medium.melee_boost_override` changes from `4`
to `3.5`, while `light_slashing_smiter_stab_dual.melee_boost_override`
changes from `3.5` to `4`. Current source routes those profiles through both
left and right damage-profile fields of `heavy_attack` and `heavy_attack_2`.
The historical selector therefore clones the two complete current-schema
profiles, restores only those two values, and swaps exactly four pinned routes.
The native shared profiles remain immutable. A missing or foreign hand route
refuses the complete plan before any write; Current remains a zero-write state,
and ordinary Tweaker: Weapons changes continue to layer afterward. The official
boundary is [Patch 2.0.10](https://forums.fatsharkgames.com/t/vermintide-2-patch-2-0-10/36215).

### Patch 3.1 boundary

Patch 3.1 uses an adjacent-boundary contract for Kruber's Blunderbuss and
Tuskgor Spear:

| Role | Source revision |
|---|---|
| Pre-Patch 3.1 source | `c96aa3858011ecd557d55d80b66fe3bb8342eeb2` |
| Post-boundary Patch 3.1 source | `3f0e3ba442d8dcafb8b5f829ff6c2a95ae24ae63` |
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

The adjacent source diff contains exactly two catalogued gameplay leaves:
`blunderbuss_template_1.ammo_data.max_ammo`, from `12` to `16`, and
`two_handed_heavy_spears_template.block_fatigue_point_multiplier`, from
`0.25` to `0.5`. Each family selector projects only its own bounded delta over
the exact current guard; neither is a complete Game 3.0 baseline. The current-only
`blunderbuss_template_1_vs` is absent from both boundary revisions and remains
explicitly excluded. The official boundary is
[Patch 3.1](https://www.vermintide.com/news/patch-31).

The runtime completeness ledger classifies this and every other exposed
family/state as either `adjacent_delta` or
`complete_direct_historical_baseline`. It records declared scope, official
coverage, later-same-leaf/cumulative policy, explicit exclusions, and the
exact `13 / 26 / 38 / 15 / 236` catalog/family/family-state/state/operation
census. Default catalog loading refuses any missing, extra, duplicate,
malformed, or count-drifted declaration; public and Dev ledger bytes must be
identical.

### Patch 3.2 boundary

Patch 3.2 uses an adjacent-boundary contract for Kerillian's One-Handed Axe:

| Role | Source revision |
|---|---|
| Game version 3.1.0 | `3f0e3ba442d8dcafb8b5f829ff6c2a95ae24ae63` |
| Post-boundary 3.2 scripts | `98965ca6e57e46d5a161f7262471b2124e0d0823` |
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

The adjacent evidence selects exactly one operation: the push-follow-up
`additional_critical_strike_chance`, from historical `0.1` to post-boundary
`0.2`. Current source no longer carries this leaf, so selecting Game Version
3.1.0 adds exactly `0.1` and returning to Current removes the field. The
independent oracle also proves that the older
`local weapon_template = weapon_template or {}` source shape is evaluated with
revision-local symbolic state; otherwise the later revision could overwrite
the historical snapshot and hide the change. The official boundary is
[Patch 3.2](https://www.vermintide.com/news/patch-32-quality-of-life-update).

### Patch 4.1.1 boundary

Patch 4.1.1 uses an adjacent-boundary contract for the Masterwork Pistol:

| Role | Source revision |
|---|---|
| Game version 4.0.1 | `872027662e076477451c8c4bf077473d8ab9e27d` |
| Post-boundary 4.1.1 | `d5f1fa23c97e0e324db047cabb21faeffa9819bf` |
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

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
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

The declared source closure is six files at all three revisions: the base
power/profile files, the Morris/Cog/Woods profile contributors loaded during
rehydration, and the Hagbane weapon template. The gate preflights all 18 exact
revision/path/blob objects, then disables lazy fetch and optional Git locks for
every extractor, oracle, route, and catalog read.

The profile evaluator finds exactly two adjacent leaves: Patch 4.6 adds
`allow_dot_finesse_hit = true` to `shortbow_hagbane` and
`shortbow_hagbane_charged`. The historical selector registers two deterministic
private profiles cloned from the current 6.12.1 payloads with only those flags
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
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

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
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

The adjacent 6.7.2-to-6.8.1 evidence selects exactly one operation: Kerillian's
Greatsword first-heavy `range_mod`, `1.55` to historical `1.45`. A second
evidence file re-reads only that selected path at 6.7.2 and 6.12.1 to establish
the runtime guard. Both primary and independent exact-double evaluators must
agree. The official boundary is [Patch 6.8.0 / Hotfix 6.8.1](https://forums.fatsharkgames.com/t/geheimnisnacht-and-the-skull-of-blosphoros-return-patch-6-8-0-hotfix-6-8-1/113884).

### Patch 6.11.0 boundary

Patch 6.11.0 uses an adjacent-boundary contract for Kruber's Longbow:

| Role | Source revision |
|---|---|
| Game version 6.10.0 | `5ff26df11311ba011f3313b9b232ed0d8b64b921` |
| Post-boundary 6.11.0 | `abe82ab4ba3e00c22d912093b37234c59f8a00d9` |
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

The adjacent evidence selects the same exact scalar leaf on both evaluated
templates: `actions.action_two.default.aim_zoom_delay`, from current/post
`0.22` to historical `2`. The source clones both
`longbow_empire_template` and `longbow_empire_tutorial_template` before
export, so the selector treats them as one family and commits both operations
atomically. A missing or foreign tutorial guard refuses before the gameplay
template changes. Current performs no writes, exact restore preserves both
template and sibling identities, and ordinary Tweaker: Weapons adapters load
after the selected baseline. No damage profile, RPC, asset, or global root is
owned. The official boundary is [Patch 6.11.0](https://forums.fatsharkgames.com/t/weapon-balance-update-patch-6-11-0-patch-notes/121528).

### Hotfix 6.11.2 boundary

Hotfix 6.11.2 uses adjacent-boundary contracts for Sienna's Dagger Heavy
Attack 2 and Saltzpyre's Axe & Falchion Heavy Attacks 1 and 2:

| Role | Source revision |
|---|---|
| Game version 6.11.1 | `1a0a4e0caf5c119bfe8d42a4d1bc23b34a7b005e` |
| Post-boundary 6.11.2 | `9fbf92c11acfaca5c49f5e40d565b0743a2bdf43` |
| Current content anchor (6.12.1) | `25fd7b8433e839b678d1c98a7a9af80918cbc252` |

The Dagger evidence selects exactly one operation:
`one_handed_daggers_template_1.actions.action_one.heavy_attack_right.damage_profile`,
from current/post-boundary `medium_burning_smiter_stab_H` to historical
`dagger_h1_medium_smiter_diag`. The Axe & Falchion evidence selects exactly
`heavy_attack.damage_profile_right` and
`heavy_attack_2.damage_profile_right` on
`dual_wield_axe_falchion_template`, from current/post-boundary
`light_slashing_smiter_dual` to historical
`axe_falcion_heavy_smiter_vertical_right`. All identities are native current
damage profiles, and the current network lookup is built from the complete
native `DamageProfileTemplates` table. The reproducibility gate pins both
template histories and the native profile/lookup blobs, so these states require
no private profile, RPC, or fallback transport. The official boundary is
[Hotfix 6.11.2](https://forums.fatsharkgames.com/t/hotfix-6-11-2-2nd-of-june-hotfix-6-11-3/122090).

## Exact reproduction

From the repository root, with the pinned Vermintide source checkout available:

```powershell
$lua = '.\qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'
$source = 'C:\path\to\Vermintide-2-Source-Code'
& $lua '.\tools\weapon-history\generate_patch_2_0_6_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_2_0_6' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_2_0_6_catalog.lua'

& $lua '.\tools\weapon-history\generate_patch_2_0_9_1_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_2_0_9_1' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_2_0_9_1_catalog.lua'

& $lua '.\tools\weapon-history\generate_patch_2_0_10_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_2_0_10' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_2_0_10_catalog.lua'

& $lua '.\tools\weapon-history\generate_patch_3_1_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_3_1' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_3_1_catalog.lua'

& $lua '.\tools\weapon-history\generate_patch_3_2_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_3_2' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_3_2_catalog.lua'

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

& $lua '.\tools\weapon-history\generate_patch_6_11_0_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_6_11_0' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_6_11_0_catalog.lua'

& $lua '.\tools\weapon-history\generate_patch_6_11_2_history.lua' `
    $source `
    '.\tools\weapon-history\evidence\patch_6_11_2' `
    '.\weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_6_11_2_catalog.lua'
```

Then run the non-mutating exact-output gate:

```powershell
.\qa\run_wt_history_patch_2_0_6_host_matrix.ps1
.\qa\run_wt_history_patch_2_0_9_1_host_matrix.ps1
.\qa\run_wt_history_patch_2_0_10_host_matrix.ps1 -SourceRepo $source -RequireSource
.\qa\run_wt_history_patch_3_1_host_matrix.ps1
.\qa\run_wt_history_patch_3_2_host_matrix.ps1
.\qa\check_wt_history_patch_4_1_1_reproducibility.ps1 -SourceRepo $source -RequireSource
.\qa\run_wt_history_patch_4_1_1_host_matrix.ps1
.\qa\check_wt_history_patch_4_6_reproducibility.ps1 -SourceRepo $source -RequireSource
.\qa\run_wt_history_patch_4_6_host_matrix.ps1 -SourceRepo $source -RequireSource
.\qa\check_wt_history_reproducibility.ps1 -SourceRepo $source -RequireSource
.\qa\check_wt_history_patch_6_0_reproducibility.ps1 -SourceRepo $source -RequireSource
.\qa\run_wt_history_patch_6_6_host_matrix.ps1
.\qa\check_wt_history_patch_6_8_reproducibility.ps1 -SourceRepo $source -RequireSource
.\qa\run_wt_history_patch_6_11_0_host_matrix.ps1 -SourceRepo $source -RequireSource
.\qa\run_wt_history_patch_6_11_2_host_matrix.ps1 -SourceRepo $source -RequireSource
```

`current_source_anchor.lua` is the single identity consumed by all thirteen
generators and their PowerShell checks. Schema 2 records the semantic 6.12.1
content commit as the observed default-branch tip with an empty metadata gap;
the strict reader retains schema-1 support for historical direct-parent/
README-only receipts. Ordinary QA runs
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
failure when freshness is required). Injected elapsed-time and wait/kill
observers prove every programmed phase budget, including a 5763 ms hosted
resume that authorizes no later wait and fails closed after one helper
containment action. Scheduler and synchronous OS-call latency is recorded only
as diagnostic evidence because it cannot provide a hard real-time ceiling. One
real Windows PowerShell 5.1 hanging-helper case retains exact PID/start cleanup
and no-orphan proof. `run_wt_history_source_host_matrix.ps1` owns the freshness
and incomplete-checkout self-tests exactly once under both hosts; patch-specific
matrices do not repeat them. The probe never fetches or writes `FETCH_HEAD`.

The Patch 5.2 gate verifies the pinned evidence extractor, generator, source catalog,
independent oracle/spec/routes, evidence hashes, and generated public catalog.
It also derives all 36 referenced source paths from the thirteen checked-in
source catalogs/specifications and proves their Git blob identities are equal
between the retired 6.12.0 and current 6.12.1 anchors, making the refresh a
provenance-only transition.
When the source checkout is present it rehydrates all nine evidence artifacts
through both evaluators, requires byte-exact primary output and exact-double
semantic agreement with the independent oracle, regenerates the route/blob
oracle, then requires byte-exact catalog equality. In source-less CI it still
enforces every pinned artifact and reports source regeneration as a visible
skip. The Patch 2.0.6, Patch 2.0.9.1, Patch 2.0.10, Patch 3.1, Patch 3.2, Patch 4.1.1, Patch 4.6, Patch 6.8, Patch 6.11.0, and Hotfix 6.11.2 gates apply the same fail-closed policy to
their adjacent boundaries, current-anchor rehydration, two evaluators, and
generated catalogs. The Patch 2.0.6, Patch 2.0.9.1, Patch 2.0.10, Patch 3.1, Patch 3.2, Patch 4.1.1, Patch 4.6, Patch 6.6, Patch 6.11.0, and Hotfix 6.11.2 host matrices
apply that policy under both PowerShell 7 and Windows PowerShell 5.1; Patch 4.6
accepts `-SourceRepo` and `-RequireSource` for the strict release proof, while
ordinary source-less QA reports pinned-only validation without claiming source
regeneration. Patch 3.2 pins immutable-revision isolation, Patch 4.1.1 pins
present-false preservation, and Patch 6.6 includes
both source paths plus the server-authority runtime contract. The Patch 4.6 gate additionally pins its
seven-artifact census, independently regenerates the two current profile
routes, and proves both emitted private profiles differ from current only by
the absent finesse flag. Before any of the thirteen reproduction gates
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
