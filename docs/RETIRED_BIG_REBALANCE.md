# Retired Big Rebalance integration

Big Rebalance integration is retired. `buff_tweaker` (`bt`) previously owned the
shared master switch and network registrations, but was archived in June 2026.
The consumer fragments are not a coherent standalone feature:

| Consumer | Current contract |
|---|---|
| Tweaker: Weapons | BR module is not loaded; `br_*` widgets are hidden. |
| Tweaker: Chaos Wastes | No BR option surface or BR registration owner. The remaining optional `bt.net_replay` calls are historical diagnostics, not BR mechanics. |
| Tweaker: Enemies | BR module is not loaded; `br_*` widgets are hidden. Its damage/stagger rewrites would also require an explicit peer-parity contract before reactivation. |
| Tweaker: Careers | BR module is replaced by a no-op lifecycle stub; `cbr_*` widgets and localization are hidden. Twenty-seven archived toggle bodies remain unimplemented. |

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
