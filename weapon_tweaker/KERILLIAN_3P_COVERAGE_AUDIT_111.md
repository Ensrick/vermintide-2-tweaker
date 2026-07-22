# Historical Kerillian routing ledger (#111)

Issue #948 supersedes this receiver-specific verification ledger. Its 60
cross-character rows remain routing evidence only: 44 have historical wired
routes, 14 have candidate ranged routes, and 2 have no route decision. Every
row is untested in the new matrix.

`/wt_audit_kerillian_3p` remains as a deprecated alias to the #948 census. It
never runs automatically or reports Working.

Current verification belongs on #948. If the universal approach fails:
(1) split the 14 ranged routes into a bounded picker batch, (2) restore a
Kerillian-only live matrix without static promotion, or (3) quarantine failing
rows default-off until current owner/remote evidence exists.
