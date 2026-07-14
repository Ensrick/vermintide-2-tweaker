# Retired Big Rebalance integration

Big Rebalance integration is retired. `buff_tweaker` (`bt`) previously owned the
shared master switch and network registrations, but was archived in June 2026.
The consumer fragments are not a coherent standalone feature:

| Consumer | Current contract |
|---|---|
| Tweaker: Weapons | Stable/dev BR implementations, definitions, and lifecycle stubs were deleted under #433; `br_*` widgets remain hidden historical reservations. |
| Tweaker: Chaos Wastes | No BR option surface or BR registration owner. The remaining optional `bt.net_replay` calls are historical diagnostics, not BR mechanics. |
| Tweaker: Enemies | BR implementation, fingerprint RPC, and lifecycle stub were deleted under #433; `br_*` widgets remain hidden historical reservations. Any rewrite would require a new peer-parity contract. |
| Tweaker: Careers | BR implementation and lifecycle stub were deleted in 0.3.70-dev (#433); `cbr_*` widgets and localization remain hidden historical reservations. The incomplete source is recoverable from git history. |

## Migration policy

Old `br_*` and `cbr_*` values may remain in VMF's saved settings. Consumers do
not read or apply them, and the option rows do not render. We deliberately do
not erase those user values at load time: deleting unknown keys is unnecessary
state mutation and would make forensic rollback harder. The identifiers remain
reserved inside commented historical blocks so they cannot be accidentally
reused for unrelated features.

Reactivation requires a new design issue that identifies one registration
owner, recovers and audits the missing source, defines multiplayer parity, and
adds current-game mechanical tests. Merely removing the old `bt` gate is not a
valid reactivation strategy.

`qa/check_retired_big_rebalance.ps1` blocks active BR widgets/module loads and
Workshop descriptions that advertise the retired integration.
