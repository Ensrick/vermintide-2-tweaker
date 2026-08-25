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

All active inventory rows remain `tracked` as of issue #1412. This control
plane does not itself migrate a real mod.

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
generation, and receipt validation only. Workshop publication, local/remote
deployment, updater consumption, and recovery consumption remain disabled.
`tools/ship/ship.ps1` rejects receipt authority before acquiring the machine
transaction lease unless `-BuildOnly` was selected. Publisher and
reproducibility boundaries continue to fail closed on non-tracked authority.

Do not add an updater, release, deploy, or recovery consumer by bypassing this
gate. Each downstream lane requires its own reviewed immutable-byte contract
and adversarial coverage before the policy can be enabled.
