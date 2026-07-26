# Issue #786 — remote Combat Style transition evidence and recovery routes

## Proven failure

The paired 2026-07-20 logs record matching Combat Style state on both peers,
followed every time by `style husk refresh ... refreshed=false detail=player
unavailable`. This excludes a missing transmit/receive edge. Source then shows
the receiver using:

```lua
local ok, player = pm and pcall(pm.player_from_peer_id, pm, peer_id, 1)
```

Lua adjusts the result of `and` to one value. `ok` receives `pcall`'s success
boolean and `player` is nil even when `PlayerManager.player_from_peer_id`
returned the correct human. The same class-26 idiom existed in Combat Style's
owner resolver, Crowbill owner/local/remote mode paths, Old Musket owner/local/
remote mode and sound paths, and Crowbill team-preview tuple lookup. This is
why a cosmetic Apply could appear to revive a model while the style/mode path
itself remained inert.

## Closed-regression corpus

The current repair was cross-checked against the closed Combat Style and
remote-husk families recorded by #660: #620/#644/#648, #395/#396/#397/#418/
#478/#495/#580/#587, #234/#264/#265/#267/#268, #390/#392/#563, #569/#603/
#606, #514/#612, and #403/#422/#654. Those closures establish separate floors
for exact state, residency, per-hand identity, lifecycle replay, transforms,
pose, and wire safety. The adjacent closed mode/husk controls #280/#412/#483/
#484/#583/#698/#741/#742/#762/#789 were also reviewed; none changes the failed
peer-to-human lookup. These closures do not falsify #786: the paired style state
arrives, then the shared owner lookup deterministically discards the returned
player. The fix therefore preserves the existing descriptor, residency, and
wire paths and changes only the shared owner resolution plus a bounded local
lifecycle retry.

## Implemented route

`_cwv_peer_resolver.lua` is the sole protected owner/local/peer/profile lookup
policy for these CWV paths. Calls use explicit branches, preserve all relevant
returns, and positively human-gate owner, local-player, direct peer, and
`players_at_peer` results without selecting a host-owned bot. An explicit
`is_player_controlled = false` is authoritative even if a stale local-player id
claims slot 1. Combat Style retains one pending local refresh per
`(peer, slot, family, style)` when the human unit or equipment is genuinely not
ready. It retries at 0.25-second cadence for at most eight total attempts,
coalesces newer style state, sends no retry traffic, and leaves unwielded slots
to the next natural wield.

## Evidence-routed fallback paths

1. If a paired retest receives state but ends with eight `player unavailable`
   attempts, capture the receiver's `Managers.player:players_at_peer(peer)`
   roster and local-player ids at the first attempt. Extend the shared resolver
   only for an empirically observed PlayerManager shape; do not add another
   style-specific lookup.
2. If the resolver reports success but readiness remains `slot not ready`, bind
   the pending drain to the already-canonical `SimpleHuskInventoryExtension.init`
   or post-equipment peer-ready edge and keep the same coalesced ledger. Do not
   poll or resend style state.
3. If re-wield reports the expected template but both hand units are absent or
   the base model survives, route the exact `(peer, slot, family, style)` into
   #660's shared appearance postcondition and inspect #749 resource closure.
   Do not treat another re-wield or a cosmetic Apply as a fix.
4. If the hand units and model are correct but animations remain native, trace
   WT's effective-template/action owner under #661/#946. Preserve the rendered
   descriptor and fix the receiver animation mapping independently.

## Regression ownership

- `test_cwv_peer_resolver.lua`: protected return and profile-tuple preservation,
  same-peer human/bot style-and-mode routing across owner/local/direct/fallback
  paths, and collapsed-idiom source sweep.
- `test_cwv_combat_styles.lua`: retry cadence, successful convergence,
  unwielded-slot terminal behavior, and hard attempt bound.
- `issue786_peer_resolution_multi_return`: in-game runtime self-check for the
  protected player/profile return contract, owner/direct bot rejection, and
  installed bounded style owner.

This source change is not deployed and must not carry an in-game tester label
until the serialized CWV release owner builds and uploads it.
