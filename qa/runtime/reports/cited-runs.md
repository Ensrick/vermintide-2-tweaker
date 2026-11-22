# Rig runs cited as evidence

`tools/harness/Remove-OldRuns.ps1` keeps every run folder whose name appears in a file under `qa/runtime/reports/` (WP-H-09 step 5). This file names the runs that the harness code, its tests and `docs/program/wp/H.md` cite as evidence, so retention keeps them whole. Retention runs only when a run is given `-Retain <N>`, and even then it keeps every pruned run's summaries, evidence and plan under `runs/_archive/<run>/`; this list is for the runs whose console log and settings copy must stay too. Add a run here when a commit, a case or a card cites it.

| Run folder | Cited for |
|---|---|
| `20261114-025153-e1-direct-visible-cb9ee067` | H.md proven fact 1: direct start, modded realm (also in `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/rig-runs/`) |
| `20261114-025504-smoke-keep-81c936d6` | H.md proven fact 3: private desktop, no window on the user desktop (also in the audit evidence) |
| `20261114-060427-smoke-keep-4b32903a` | H.md proven facts 9 and 11: driver to the keep and back (also in the audit evidence) |
| `20261114-061008-smoke-keep-5f5ca4b0` | H.md proven facts 11 and 13: the start-up commit's `keep_decorations` request (also in the audit evidence) |
| `20261114-061313-smoke-keep-9d23f887` | H.md proven facts 11 and 14: shield up before the first commit (also in the audit evidence) |
| `20261115-085154-shield-equip-3d617f44` | `qa/runtime/_rig/shield_equip.lua` |
| `20261115-144350-mission-smoke-75899d31` | `tools/harness/driver/vt2_rig_driver.lua` `T.main`: unit calls fail inside the case coroutine |
| `20261115-162744-lead-cases-a2-9709b2c8` | `qa/runtime/cwv/a2f01_outrider_wire_name.lua` |
| `20261122-024431-api-selftest-09002eef` | driver 0.4.8 `T.teleport` POSITION_LOOKUP fix and the `api_ui` layout wait (#1923) |
