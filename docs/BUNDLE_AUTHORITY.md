# Bundle authority control plane

Issue #1412 adds a fail-closed control plane for the generated files under an
active mod's `bundleV2/` directory. The exact selector is the mandatory
`BundleAuthority` field in `tools/mod-inventory.psd1`.

## Modes

`tracked` is the established mode. The complete normalized output set remains
Git-tracked, BuildOnly writes a schema-3 receipt beside the mod, final ship
rebuilds and compares the working set with the reviewed Git tree, and the
existing publication/deployment flow is unchanged.

`receipt` is a prepared storage mode. The Git tree contains zero generated
`bundleV2` outputs and exactly one scoped root ignore rule:

```gitignore
/<mod>/bundleV2/
```

The mod still carries a schema-3 `.build-receipt.json`. That receipt must bind
the exact current source, inventory `RootBundle`, source-qualified descriptor,
complete normalized output map, normalization policy, and VMBLauncher builder
identity. If a local build is materialized, its complete output set must equal
the receipt byte-for-byte by filename, length, and SHA-256. Missing, extra,
renamed, changed, nested, reparse-point, or case-colliding output fails closed.

All active inventory rows remain `tracked` as of issue #1422. This control
plane does not itself migrate a real mod.

## Immutable publication snapshots

Issue #1422 adds one authority-neutral byte snapshot boundary without enabling
any receipt downstream lane. `Get-VtPublicationSnapshot` derives inventory,
root, mode, metadata, and source inputs from one exact commit. In `tracked`
mode it returns the same Git blob bytes and complete output-set identity the
publisher already consumed.

The receipt path exists for offline fixtures and future reviewed phases only.
It requires the exact committed schema-3 receipt, exact scoped ignore rule,
zero committed `bundleV2` outputs, commit-qualified source and normalization
proof, the expected builder version, and a byte-identical materialized output
set. Every materialized file is opened with restrictive handles; its bytes,
length, hash, file identity, directory identity, and the complete directory
snapshot are reconciled before the handles are released. Returned byte arrays
are detached from disk and from one another.

This snapshot proves bytes; it does not grant authority to publish them.

## Typed transitions

Changing authority is not ordinary bundle retirement and must not use a
`VT2-Bundle-Retirement` trailer.

A `tracked` to `receipt` transition is one reviewed transaction containing:

1. the exact inventory mode flip;
2. only the exact scoped ignore-rule addition;
3. deletion of all and only the previously tracked complete output map; and
4. a schema-3 receipt whose output map exactly equals that removed map and
   whose source/policy/builder proof matches the transition head.

The inverse `receipt` to `tracked` transaction removes only that scoped ignore
rule and restores every receipt-bound output with exact content. A partial
index, split commit, forged receipt, tracked leftover, unrelated output
deletion, or non-exact restoration is rejected.

`qa/check_bundle_authority.ps1` owns repository-state and transition
validation. `qa/check_release_bundle_atomicity.ps1` delegates typed transition
and receipt-mode runtime atomicity to that contract instead of weakening its
ordinary tracked-bundle retirement rule.

## Deliberately disabled downstream lanes

Receipt authority currently supports normalization, BuildOnly output
generation, receipt validation, and the offline immutable snapshot fixture
only. Workshop publication, local/remote deployment, updater consumption, and
recovery consumption remain disabled.
`tools/ship/ship.ps1` rejects receipt authority before acquiring the machine
transaction lease unless `-BuildOnly` was selected. Publisher and
Workshop-receipt boundaries continue to fail closed on non-tracked authority.
Both publisher tracked gates remain in place even though the shared snapshot
can prove receipt bytes.

Do not add an updater, release, deploy, or recovery consumer by bypassing this
gate. Each downstream lane requires its own reviewed immutable-byte contract
and adversarial coverage before the policy can be enabled.
