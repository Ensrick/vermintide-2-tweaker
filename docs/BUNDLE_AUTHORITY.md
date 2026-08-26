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

Issue #1422 adds one authority-neutral byte snapshot boundary.
`Get-VtPublicationSnapshot` derives inventory,
root, mode, metadata, and source inputs from one exact commit. In `tracked`
mode it returns the same Git blob bytes and complete output-set identity the
publisher already consumed.

The receipt path requires the exact committed schema-3 receipt, exact scoped
ignore rule,
zero committed `bundleV2` outputs, commit-qualified source and normalization
proof, the expected builder version, and a byte-identical materialized output
set. Every materialized file is opened with restrictive handles; its bytes,
length, hash, file identity, directory identity, and the complete directory
snapshot are reconciled before the handles are released. Returned byte arrays
are detached from disk and from one another.

This snapshot proves bytes; the separate Phase D gates below decide whether a
consumer may publish them.

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

## Receipt-authority publication boundary

Issue #1426 enables only Workshop/GitHub publication for receipt authority.
Canonical ship still requires the clean live default-branch commit, merged PR,
hosted QA, machine claim, transaction and executable leases, and an approved
launcher advertising `receipt-authority-publication-v1`. A receipt-authority
publisher clean-builds and normalizes before capture, validates the committed
schema-3 receipt and complete source/output/policy/builder proof, freezes those
bytes into the ZIP and hosted receipt, and gives the launcher that exact hosted
receipt. The launcher independently reconstructs the committed proof and
compares the complete locked SDK-staging set immediately before `ugc_tool`.

Tracked publication keeps its established pre-build Git-blob selection and
Git-blob receipt route. Receipt authority cannot bootstrap a new Workshop ID;
first upload remains tracked-only. Receipt authority also keeps local/remote
deployment, updater consumption, and recovery restoration disabled. Do not
bypass those policy fields: each later consumer needs its own reviewed
immutable-byte contract and adversarial coverage.

## Durable recovery producer boundary

Issue #1430 adds metadata production, not recovery execution. A newly staged
release entry receives a `recovery` schema-1 child only when the immutable
publication snapshot is backed by a committed, exact schema-3 build receipt.
That record binds all of the following in one source-exact shape:

- repository, release tag, the exact case-sensitive `<mod_id>.zip` asset filename,
  byte length, and SHA-256;
- mod folder/id, Workshop id, version, clean source commit, item cfg, inventory,
  ignore-state, and builder provenance;
- bundle authority, canonical root, source-qualified descriptor, and complete
  ordinal output map with its aggregate fingerprint; and
- the committed build-receipt blob/hash plus its source, output, builder, and
  normalization-policy proof.

The asset coordinates available before upload are deliberately logical and
immutable: repository, tag, filename, byte length, and hash. Numeric GitHub
release/asset IDs do not exist when the record is constructed. A future
consumer may persist those numeric IDs in an installed-state sidecar after it
has resolved and verified the asset; the producer must not predict them.
Filtered carry-forward preserves a sibling record verbatim, including the tag
where its exact asset was first recorded. Only a newly staged row must bind the
manifest's current release tag.

Tracked entries with a missing or schema-2 receipt retain their existing
behavior and are explicitly classified as legacy rather than source-exact.
Receipt authority has no safe legacy byte reconstruction, so it fails closed if
the durable record cannot be produced. No updater, historical resolver, file
replacement, deployment, authority transition, or active inventory-row change
is enabled by this producer contract.
