# Issue #371 mixed-lobby capability reconciliation

Audit date: 2026-07-21. Rebased source baseline: `e7efd142`. This document records
repository and tracker facts used to separate the next implementation work. It
does not mark #371 or any child ready for in-game testing.

## Current contract

Network-unsafe features are inert while required peer evidence is unknown or
negative. Saved settings are retained. Mod Tweaker shows the affected setting
as disabled with a player-facing explanation; the stock VMF menu eventually
hides it. Gameplay/network containment remains in the owning mod and may never
depend on the UI gate.

Numeric `NetworkLookup` identity is not proven by mod presence. Lookup-index
axes use unconditional vanilla-safe wire values plus semantic string channels
where required. A capability gate is for genuinely modded behavior or assets,
not permission to send an unproven numeric index.

Issue #424 has one explicit policy: when any peer lacks Career Weapon Variants,
unsafe thrown variants are disabled rather than silently becoming a different
weapon. The existing sender-side vanilla projectile/pickup fallback remains as
a second containment floor for the hot-join interval before the feature can be
disabled. Bomb/world-pool injection remains inert until its own sender boundary
is proven.

## Open critical children

| Issue | Current tracker state | Reconciled role |
|---|---|---|
| #278 | `verify-fix`, `coop-required` | Keyed loadout wire; shipped sender floor awaiting peer proof. |
| #413 | `verify-fix` | Shadow Adventure package/residency child; shipped solo stage remains in its own queue. |
| #421 | `verify-fix`, `coop-required` | Cosmetic skin wire; shipped floor awaiting peer proof. |
| #423 | `diagnostics-armed` | Damage-profile lookup child; diagnostics remain the current next action. |
| #424 | `blocked`, `not-started` | Genuine thrown-resource gate. Disable policy is now settled, implementation is not. |
| #426 | `not-started` | Custom boon/miracle capability consumer remains unshipped. |
| #430 | `blocked`, `not-started` | Custom curse session containment remains blocked/unshipped. |
| #491 | `diagnostics-armed` | Paired-skin/resource child remains in diagnostic collection. |

Related open issues are not collapsed into this crash umbrella unless they
share its wire/capability boundary: #296 is pickup recovery, #598 is local
Hold-Tab presentation, #613 is the wider WOC presentation/peer-safety backlog,
#660 owns render-surface appearance unification, and #741 owns unconditional
skin-index nulling after lookup-space divergence evidence.

## Closed sibling evidence

| Issues | Durable evidence retained |
|---|---|
| #270, #280, #294 | Receiver/resource/spawn floors must remain unconditional. |
| #425, #431, #776 | Gameplay lookup features require exact identity or fail-closed gating. |
| #495, #734, #737 | Skin indices must not cross vanilla wire merely because peers report the same mod. |
| #506 | Parity state commits before callbacks; consumers must never observe stale applied state. |
| #536, #588, #654 | Wield/loadout/property paths need independent sender containment. |
| #655 | Future reusable WOC traits still require a capability before network activation. |
| #803 | Duplicate/feature half of #413; no second implementation owner. |

## Preserved staged worktrees

Two older experiments were inspected read-only and remain untouched:

- `_wt_371_capability_phase1`, HEAD `9f3acd1b`, has 12 staged files with
  4,428 insertions and 369 deletions. It contains the stronger protocol base:
  session epochs, challenge-bound proof, bounded complete envelopes, capability
  state, and missing-peer introspection.
- `_wt_371_feature_capabilities`, detached HEAD `e4a6350c`, has 26 staged files
  with 2,327 insertions and 308 deletions. It contains an earlier overlapping
  protocol plus broad production feature opt-ins.

No worktree lock or live Codex owner was present during the audit. A global
Claude process existed, but its working directory could not be attributed, so
ownership was not assumed. Neither experiment is safe to merge as-is: both are
based on older master revisions and overlap each other across the parity library
and six mod streams. The protocol base must be rebased and reviewed first;
feature opt-ins must then be ported individually against that one base.

## Non-overlapping implementation sequence

1. Land the dev-GUT runtime-gate registry and both live Mod Tweaker row
   consumers. This slice has no production registrations and cannot declare
   #371 test-ready.
2. Rebase the stronger capability protocol alone. Preserve its epoch,
   challenge, payload-bound, and missing-peer contracts; rerun shifted lookup,
   stale acknowledgement, disconnect, and hot-join tests.
3. Port one owner capability at a time. Each owner provides a localized reason,
   disables its gameplay/network boundary, and registers only its exact Mod
   Tweaker setting ids. Saved values remain untouched.
4. Implement #424 first among genuine resource gates: disable the thrown weapon
   in a mixed lobby while retaining the sender fallback for join races.
5. Add the stock VMF presentation adapter only after the runtime owner API is
   stable. Hiding a row must not delete or rewrite its persisted value.
6. Add static enforcement for new custom lookup ids, vanilla RPC payloads,
   resources, and spawned units, then reconcile every open child before any
   umbrella-level live-test label is added.

## This slice

Tweaker: GUI dev `0.2.309-dev` adds `register_runtime_gate`,
`unregister_runtime_gate`, `runtime_gate_status`, `apply_runtime_gate`, and
`prune_runtime_gated_pending`.
Multiple predicates can compose on one setting. Predicate errors and malformed
availability results block the row. Both UI paths evaluate the live state before
row input, so a join/leave transition greys or restores the row without changing
saved settings. The owner-side gameplay gate, production registrations, VMF
adapter, merge, build, deployment, and in-game verification are intentionally
outside this isolated slice.
