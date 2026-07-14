# Issue #221: Historical subgroup-master audit

#445 already supplies Career Tweaker's safe whole-family controls. The remaining historical proposal is not one setting family: it combines armor hooks, Unchained overcharge hooks, native rework template mutations, and Tourney/native per-career catalogs.

`/crt_umbrella_audit` records one bounded `[crt:221]` line with:

- active/total counts for the complete Ensrick and Tourney catalogs;
- Unchained native-rework and separate runtime-overcharge counts;
- Outcast Engineer native-rework counts;
- the two armor-hook settings;
- `cluster_gates=0/4` and `mutation=false`.

The zero is intentional. A visible subgroup master is not safe until its catalog has one complete reversible lifecycle contract. In particular, a menu-only parent or a bulk `mod:set` loop would miss live hooks, erase custom child state, or leave already-mutated templates active.

## Promotion criteria for any subgroup

1. Define the exact leaf and non-leaf owner catalog.
2. Gate every feature entry point, including hook-owned behavior.
3. Restore exact vanilla/template state when the master is disabled.
4. Preserve saved child choices while the master is off.
5. Apply or restore each owner once, with nested callbacks suppressed.
6. Prove default behavior is unchanged and peer/network registration is independent of the toggle.

Until those criteria are met, #445 is the supported master-control surface and the subgroup census is diagnostic only.
