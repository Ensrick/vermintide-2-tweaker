# Critical Weapon Action Ownership Audit — Wave D

Date: 2026-07-21
Canonical issues: #112, #661
Evidence: issue #930 session log plus current VT2 source-derived contracts in
`BUG_CLASSES.md` sections 42 and 59.

## Result

The issues share the live wield lifecycle but do not share one mutable state:

| Issue | Broken invariant | Root | Owner |
|---|---|---|---|
| #112 | A cached 3P remap must match both the weapon and receiver skeleton. | The remap cache identity was `(template or key)` only. Reusing the same weapon across a character switch could retain the prior career's receiver map. | WT animation state policy |
| #661 | Every exact effective template usable by a career must contain every weapon-bound activated-ability row by canonical identity. | Crafted CWV instances can expose an inherited vanilla key at `_wield_slot`, so WT could not resolve the CWV owner and exited before its final seam. Crowbill's private pick/hammer templates were also absent from the declared effective family. | CWV exact identity/family provider + WT wield lifecycle |

Combining their state would be incorrect. Animation remaps select receiver 3P
events; career actions are executable template rows. The reusable architecture is
the authoritative, bounded local wield boundary and exact provider identity.

## Open/closed cross-reference

### #112 animation family

- #290 is the canonical generated-map/receiver-safety merge repair.
- Closed #196, #248, #286, and #576 repaired or audited individual Billhook,
  Executioner, Greataxe, and Saltzpyre vocabulary rows.
- Open #748 and #946 remain per-action vocabulary/coverage work. They do not
  supersede the career-sensitive cache invalidation fixed here.

### #661 career-action family

- #930 is evidence-only and correctly consolidated into #661.
- Closed #412 is an interrupt-chain boundary, not an action-provider repair.
- Closed #425/#506 are wire/parity or stale-state safety and do not establish
  local effective-template action identity.
- #632/#690 are weapon-package manifestations under the #661 invariant.
- Prior Old Musket/Outrider fixes correctly added their alternate templates but
  did not cover exact identity recovery for every later CWV provider or the
  Crowbill style family.

## Implemented source-backed path

1. CWV publishes its existing exact, definition-backed item resolver. It accepts
   canonical stamps/backend evidence only and never guesses from a `cwv_` prefix.
2. WT resolves that provider identity before an inherited direct key at local
   wield, then reconciles the actual `BackendUtils.get_item_template` result
   before vanilla continues.
3. Unknown providers fail open without mutation. A direct IML key is WT-managed
   only when the exact key occurs in WT's current receiver-career unlock map;
   provider-resolved CWV identities are explicitly managed. This preserves
   Pusfume's full authority over its own items and action templates, as well as
   any other independently owned weapon system.
4. Imperial and Dawi Crowbill declare both private style templates with exact
   donor provenance, so registration-time and live reconciliation cover both.
5. WT's animation remap cache identity includes receiver career.
6. Offline and runtime checks cover exact-key precedence, Pusfume-style unknown
   ownership, Crowbill alternate templates, pre-call ownership, and career-based
   cache invalidation.

## Bounded fallbacks if live evidence falsifies the preferred path

1. If the exact provider key resolves but `BackendUtils` returns the wrong
   template, add a provider-owned effective-template resolver to the same
   contract; do not infer it in WT.
2. If the action row is canonical at wield but activation still fails, instrument
   the first `CharacterStateHelper._get_chain_action_data` rejection for the
   exact item/career/action and split the failure from #661.
3. If a later owner replaces the template after pre-wield reconciliation, move
   the same idempotent transaction to that proven provider replacement edge;
   never add a per-frame repair.

No Workshop upload, deployment, lifecycle-label change, or Pusfume mutation is
authorized by this audit.
