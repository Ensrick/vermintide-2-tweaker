# Historical Bardin routing ledger (#110)

Issue #948 supersedes this receiver-specific verification ledger. The five
historical cross-character rows still have wired event/model routes, but static
wiring is not current visual or action verification.

`/wt_audit_bardin_3p` remains as a deprecated alias to the #948 census. It emits
five `U` (untested) cells and never runs automatically or reports Working.

Current verification belongs on #948. If the universal approach fails:
(1) restore a Bardin-only live pass without automatic promotion, (2) test the
four 1H event-map rows separately from Handgun, or (3) quarantine any failing
row default-off while keeping its routing evidence.
