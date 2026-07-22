# Critical Multiplayer and Resource-Safety Audit — 2026-07-21

Scope: issues #282, #371, #423, #424, #426, #430, #470, #491,
#749, and #947. This audit records only source, log, issue-history, and
decompiled-game evidence available on 2026-07-21. It does not claim an
in-game result without a matching deployed build and attached test log.

## Shared safety boundary

Stingray resource calls such as particle creation, renderer/material binding,
Gui creation, and package load/unload can terminate below Lua. A `pcall` does
not make those operations safe. `qa/check_native_resource_safety.ps1` now
blocks newly added native boundaries unless the source carries a stable
`resource-safety` token also present under `qa/`. The gate runs in full QA and
against the staged diff in pre-commit. This prevents expansion of the unsafe
surface; it does not retroactively fix the open runtime issues below.

Pusfume is an external compatibility authority. Tweaker code must yield toward
vanilla-compatible behavior when capability or ownership is uncertain and must
not rewrite, disable, or commandeer Pusfume-owned assets or behavior.

## Issue dispositions

### #282 — package refcount leak / unload deadlock

Evidence: #927/#937/#940 share the fatal `#ID[5ab1500d]`; #930 is a non-fatal
control. Every session balances the named `cosmetics_tweaker_offhand` and
`cwv_husk_override_units` references, and each fatal logs the Material-Hijack
ledger's post-StateIngame release as complete with no delayed entry. The fatal
sessions then stall in `PatchedResourcePackage::unload`. The current producer
is therefore the manually released renderer-backed Material-Hijack donor
package, not the ordinary multi-owner `NOT unloaded` lines.

Candidate paths if the first repair fails:

1. Keep one mod-owned reference per Material-Hijack donor package for the
   process session and let `PackageManager.destroy` own final release.
2. If that still fails, remove dynamic donor-package loading by compiling the
   required material closure into a Cosmetics-owned package.
3. Remove cross-mod ownership by assigning each package to one provider and
   making consumers request capabilities without calling load/unload directly.

### #371 — mixed-lobby feature safety umbrella

Evidence: separate failures exist on damage-profile, skin, item, buff, particle,
and package axes. Mod-presence alone does not prove matching numeric lookups or
resident assets. The capability-token foundation is not merged or deployed;
the issue remains `not-started`.

Candidate paths:

1. Exchange versioned capability tokens per wire axis and permit custom payloads
   only after positive peer acknowledgement.
2. Substitute a receiver-safe vanilla identity at every sender choke when
   parity is absent or unknown.
3. Suppress the feature locally with a bounded log and user-facing explanation
   when no mechanically safe substitute exists.

### #423 — cloned damage profile sent to a non-CWV host

Evidence: CWV `0.1.463-dev` contains a sender-side damage-profile floor and
offline regression coverage. The later attached scoreboard crash belonged to
the weapon-skin axis, not `rpc_attack_hit`. Blocker #776 is closed. A pinned
solo diagnostic card is live and `diagnostics-armed`; co-op remains deliberately
deferred until the solo floor passes.

Candidate paths if the current floor fails:

1. Extend the existing sender choke to the newly evidenced damage-profile RPC.
2. Convert every cloned profile to its recorded vanilla source ID before wire
   encoding whenever parity is unconfirmed.
3. Block only the unsafe hit event when no proven vanilla source exists, logging
   the profile and sender once.

### #424 — thrown variant spawn RPCs

Evidence: a crash floor exists, but the product decision among hiding, blocking,
or substituting the thrown variant in mixed lobbies is unresolved. The issue is
`blocked` and must not carry a live-test label.

Candidate paths after that decision:

1. Substitute a mechanically equivalent vanilla pickup/projectile identity.
2. Hide the variant from inventory and crafting while an incompatible peer is
   present.
3. Keep it visible but block throw/spawn with a clear local explanation.

### #426 — modded boon/miracle identity

Evidence: parity and strip floors exist, but the bounded `/ct_426_diag`
instrumentation is source-only and unmerged. The issue remains `not-started`
and is not ready for live testing.

Candidate paths:

1. Strip modded boon/miracle numeric IDs before any unconfirmed peer snapshot.
2. Transmit a vanilla-safe placeholder and reconstruct the local presentation
   only on acknowledged peers.
3. Keep the feature host-local and disable acquisition while any incompatible
   peer is present.

### #430 — Event Tweaker curse compatibility

Evidence: containment exists, but the curse catalogue and mixed-peer product
behavior are incomplete. The issue is `blocked` and outside the test queue.

Candidate paths:

1. Permit only vanilla curse IDs that every peer can resolve.
2. Map unsupported curses to an explicitly selected vanilla fallback.
3. Disable custom curse selection for mixed lobbies and retain vanilla mission
   behavior without mutating another mod's state.

### #470 — Chaos Wastes rank-8 hit reaction

Evidence: rank-8 backfill exists, while the remaining verification depends on
open issue #505. The issue remains `blocked` and outside the live-test queue.

Candidate paths:

1. Complete #505 and verify the existing backfill at the original hit-reaction
   consumer.
2. Clamp unsupported ranks to the highest vanilla rank before lookup.
3. Supply a bounded complete rank table at initialization and assert every
   consumer index offline.

### #491 — CWV pairing skin/package crash

Evidence: CWV `0.1.449-dev` added base-weapon package shadowing; current master
also carries skin-wire substitution floors. The attached crash predates the
package fix. Blocker #776 is closed. A pinned solo card targets both a CWV item
and a native item with a CWV pairing illusion; `diagnostics-armed` is correct,
with co-op deferred until the solo floor passes.

Candidate paths if the package shadow still fails:

1. Instrument the exact item/unit/package collector tuple that missed its
   marker, then repair the single collector seam.
2. Gate equipment replay on confirmed package residency when the corrected
   manifest arrives asynchronously.
3. Choose an explicitly universal vanilla item, unit, and skin fallback as one
   atomic payload rather than substituting skin alone.

### #749 — borrowed renderer residency umbrella

Evidence: Cosmetics consumes a shared strict-residency helper, but CIM, CWV,
GUT, and GT do not yet share that boundary. The umbrella remains `not-started`;
the new QA gate prevents additional uncovered native calls but is not completion.

Candidate paths:

1. Move all borrowed preview/runtime renderers to one provider-owned resident
   lease service with explicit acquire/release phases.
2. Copy only the minimum renderer descriptors into each owner and require the
   owner package before native material/texture calls.
3. Fail closed to an asset-free vanilla preview when renderer/material
   residency cannot be proven synchronously.

### #947 — CIM Chaos Wastes trait particle crash

Evidence: both attached logs are the same CIM `0.8.101-dev` session. The fatal
particle hash `179c9e8cea64ff13` resolves to `fx/cw_enemy_explosion`, contained
in `resource_packages/dlcs/morris_ingame`. The log loaded `morris` and its
platform package, not `morris_ingame`. The stack enters
`deus_ranged_crit_explosion_on_damage_dealt` and reaches native
`World.create_particles`. This is the same pcall-bypassing resource class as
closed #128, with an additional mixed-peer capability risk through the vanilla
explosion RPC. The issue remains `not-started`.

Candidate paths:

1. Acquire `morris_ingame` before enabling the trait and keep it resident until
   the world/session boundary, but only when every receiving peer can render it.
2. Suppress the proc outside an active Chaos Wastes mission and log the decision
   once.
3. Preserve damage with an effectless or universally resident substitute and
   never send the unavailable particle identity over the wire.

## Queue result

- Solo live testing now: #423 and #491 (`diagnostics-armed`, pinned cards).
- Co-op live testing now: none. `coop-required` is added only after those solo
  floors pass and a replacement pinned card defines the host/peer matrix.
- Blocked and not testable: #424, #430, #470.
- Architecture/source work, not yet testable: #282, #371, #426, #749, #947.
