# QA Checks Map

For every documented bug class in this repo's history, the check that catches it
going forward. **Status as of 2026-07-22.**

This doc is the contract between [PROJECT_STANDARDS.md](../PROJECT_STANDARDS.md)
and the runnable QA tooling in this directory. Every memory file or audit
finding that names a recurring bug class should appear here with its detection
method.

Run all checks with: `qa\run_all.ps1`. CI (`.github/workflows/qa.yml`) runs the
same `run_all.ps1` full gate (the policy engine below decides what blocks) plus a
blocking all-mods `lint-mod.ps1` step on every push + PR (issue #429).
The workflow/protected-branch contract is guarded by `check_ci_hardening.ps1`;
activation and the emergency path are documented in `docs/CI_PROTECTION.md` (#540).
The release/lint/cfg mod set is centralized in `tools/mod-inventory.psd1`;
`check_mod_inventory.ps1` blocks an active mod from being omitted or an archived
mod from remaining in that inventory (#546).

Issue #321's retired-feature contract is enforced by
`check_retired_big_rebalance.ps1`: active `br_*`/`cbr_*` widgets, executable
consumer module loads, or Workshop descriptions advertising Big Rebalance are
blocking errors. Historical implementations and saved setting identifiers stay
reserved and inert for migration/forensic purposes.

The canonical `tools/ship/ship.ps1` path runs `run_all.ps1 -Quick -SkipLua`
(including offline Lua 5.1 unit tests) plus target-mod lint before any build,
deploy, or upload. This is the release red gate from issue #591; in-game
regression commands remain for engine lifecycle, rendering, and peer behavior
that cannot be faithfully exercised by the host runtime.

Issue #724 adds publication authorization before mutation: exact live
default-branch HEAD, an associated merged PR, successful hosted `qa-gate`, a
machine-global mod/version claim, newest CHANGELOG identity equal to
`MOD_VERSION`, and a clean build whose complete output equals the selected
tracked Git blobs or committed schema-3 receipt. The publisher independently
re-queries live GitHub state rather than trusting caller JSON. VMBLauncher
requires a five-minute capability and independently rechecks clean HEAD, merged
PR, hosted `qa-gate`, claim owner, cfg, authority proof, and every bundle hash
immediately before `ugc_tool`. There is no emergency publication bypass.

## Gate semantics (run_all exit codes)

Individual checks follow a **0 / 1 / 2 convention**: `0` = clean, `1` = advisory
WARNINGS, `2` (or higher) = ERRORS. `run_all.ps1` aggregates these so that:

- **Warnings (exit 1) are REPORTED but never fail the gate.** They are collected
  and printed loudly under a `WARNINGS (non-blocking)` summary block, and
  `run_all` still exits `0`. This is deliberate: pre-existing advisory warnings
  (bare-unpack in stable files, cfg title drift, stale `.in_progress` sentinels,
  data<->loc diffs) must not block unrelated commits, because a gate that blocks
  on noise trains sessions to bypass the pre-commit hook with `--no-verify`.
- **Errors (exit >=2) fail the gate.** `run_all` exits with the highest error
  code seen. The pre-commit hook (`qa/run_all.ps1 -Quick -SkipLua`) therefore
  blocks only on genuine breakage.
- **Execution failures (reserved exits 90–99) always fail the gate before policy
  is applied.** An Advisory check may report legitimate exit 1/2 findings, but a
  parser, missing-host, or tool crash is QA infrastructure failure, not an
  advisory result (issue #85).

The following checks are pinned in `run_all.ps1` to a non-default policy via the
`Run-Check -Policy` parameter:

| Check | Policy | Reason |
|---|---|---|
| `check_published_ids` | `Blocking` | Signals a real published_id collision (Workshop-item hijack) via **exit 1**. Any non-zero from it is a hard error, so it must fail the gate despite using exit 1. |
| `check_in_progress` | `Advisory` | Multi-agent coordination surface only ("Never blocks - just surfaces awareness", per CLAUDE.md). No exit code it returns (including exit 2 on a malformed sentinel) ever fails the gate; a non-zero is reported as an advisory notice. |
| `check_worktree_budget` | `Standard` | Blocking local-capacity guard added after the 2026-07-30 cleanup found 707 registered worktrees and reclaimed at least 323.81 GiB. It excludes the primary checkout, permits at most 8 secondary worktrees using at most 12 GiB combined, warns above 2 GiB per tree, and never deletes. CI normally has zero secondary worktrees. Its offline `-SelfTest` covers count, disk, primary exclusion, large-tree warnings, and stale registrations; `run_selftests.ps1` also exercises the lifecycle wrapper's Windows self-close boundary. |
| `check_diff_whitespace` | `Standard` | Non-mutating Git patch hygiene (issue #1174). Default Quick/full QA checks unstaged plus staged diffs and, when `GITHUB_BASE_REF` exists, the exact `origin/<base>...HEAD` pull-request range. The installed pre-commit hook runs `-Staged` before extension filtering, so docs-only trailing whitespace is covered. Hosted `qa-gate` also invokes the explicit base-to-head range. Exit 2 prints affected paths/lines; an indeterminate Git range exits 99 and blocks. Offline self-test plants staged-only, committed-only, repaired, unstaged, and invalid-range cases. |
| `check_pipeline_state` | `Advisory` | Pipeline-state ladder (source → CHANGELOG → bundle → upload) surfacing stranded fixes. ALWAYS exits 0 on a live run (report-only), so it never blocks; pinned Advisory alongside `check_in_progress`. Reads `workshop_log.txt` when present and marks the upload column `n/a` where it is absent (CI), so it is safe everywhere. Its `-SelfTest` (auto-discovered by `run_selftests.ps1`) still exits 2 on a verdict-logic regression. |
| `check_native_resource_safety` | `Standard` | Diff gate for pcall-bypassing Stingray resource boundaries. New particle creation, screen/world Gui creation, texture/material binding, or package load/unload calls in active mod Lua require a nearby `-- resource-safety: <token>` annotation whose exact token exists under `qa/`. Runs in full QA and staged pre-commit; self-test covers missing annotation, missing evidence, multi-call coverage, and source-path filtering. |
| `check_native_resource_contracts` | `Standard` | Full-tree #749/#1125 renderer-resource census. Exact file/kind/count rows cover particles, texture/material binds, shared-writer descriptor reachability, Gui creation/lookups, UIRenderer creation hooks, shading-environment writes, and shared V2 residency proofs. Any new, removed, or moved boundary blocks until its policy and evidence are reviewed; global wrappers are explicitly distinguished from strict Tweaker-owned calls. Repository-relative exclusions make the census identical in the primary checkout and linked worktrees, including worktrees whose parent path contains `.claude` (#1101). |
| `check_cwv_old_musket_asset_contract` | `Standard` | Issue #1155 deterministic source-asset ratchet. It pins the original Old Musket source SHA/topology/component signature, numeric orthonormal determinant-1 basis, semantic trigger-to-native-handgun anchor, a second signed trigger-tail roll landmark, normalized signed output bounds, stable ordered geometry/winding digest, current FBX integrity hashes and identifiers, and byte identity between the checked-in 1P/3P outputs. It runs in Quick/full QA without Blender or the external source DAE. |
| `check_cwv_old_musket_compiled_contract` | `Standard` | Issue #1155 post-compiler ratchet. A dependency-free VT2 v189 parser opens the exact CWV root bundle and requires one 1P unit, one 3P unit, and one authored material resource; one `rifle` renderer per view with exactly 16,483 triangles; signed bounds within 0.005 m of the immutable asset contract; dominant +Y orientation plus signed X/Z roll inequalities that reject the upside-down antipode; exact 1P/3P geometry parity; and `rifle_mat` bound to the authored material. Missing or stale bundles fail clearly. Ordinary Quick/full QA runs it after the source-asset gate. `ship.ps1 -BuildOnly` skips it during pre-build QA, then runs it explicitly against the newly compiled CWV root before reporting success. |
| `check_issue_status_labels` | `Advisory` | GitHub issue status-label doctrine surface (PROJECT_STANDARDS §11). Uses the standard 0/1/2 convention (1 = findings, 2 = self/read error) but is pinned Advisory so it NEVER blocks — it queries GitHub (must not fail a commit offline) and its findings are nudges the maintainer reviews, not hard errors. |
| `check_stale_docs` | `Advisory` | Doc-hygiene surface (issue #429). Staleness is TIME-based (`check_stale_docs.ps1` flags a doc at its `$StaleDays = 14` default with no edit), so exit 2 must NOT hard-block a commit/CI on calendar drift. Pinned Advisory (formalizing the old CI `continue-on-error`). Remediation: `run_all.ps1 -FixStale`. |
| `luacheck` | `Advisory` | Lua static-analysis surface (issue #429). The ~415-warning baseline is driven down over sessions, not per-commit (CWV bare-globals cleanup, PROJECT_STANDARDS §11). Pinned Advisory — the policy-engine version of the old CI `\|\| true`. Flip to Standard once the baseline is clean. |
| `check_logging` | `Standard` | Logging-hygiene surface (issues #429/#427, rows 58a-d). Existing echo/per-frame debt remains an exit-1 warning, while scanner failures and any new warning-backed diagnostic helper exceed the exact #427 migration floor and exit 2. The floor tolerates only the three public stable-stream helper lines already corrected in their dev twins; authorized promotion may remove them monotonically. |
| `check_hook_test_coverage` | `Advisory` | Hook/NetworkLookup regression-coverage surface (issue #429, row 24a). Diff-scoped; warn-only in `run_all` AND pre-commit while we gather signal. Self-exits 0 on an indeterminate diff. Consider Standard once the `-- hook-test:` / `_rt_register` convention is established. |

`check_release_bundle_atomicity` remains Standard/blocking. It is diff-scoped,
uses each active mod's `RootBundle` identity from `tools/mod-inventory.psd1`,
and rejects runtime, itemV2.cfg, or newest CHANGELOG release-identity changes
that omit that exact bundle. Shared VMF bundles and asset sidecars do not count.
Docs/tests-only and bundle-only reconciliation diffs pass. A trusted #676
promotion grant exempts only the exact approved stable directory's
metadata-only promotion diff; runtime source is never exempted. Fixture coverage lives in
`qa/fixtures/release_bundle_atomicity/cases.psd1` (issue #724).

Everything else uses the default `Standard` policy (exit 1 = warning, exit >=2 =
error). Checks that already hard-fail on exit 2 and never emit exit 1
(`check_vmf_widget_types`, `check_event_register_signature`,
`check_cross_mod_deps`, `check_command_collisions`, `check_mechanics_citations`,
`check_dev_only_edits`) keep blocking on their errors under this default.

`check_pusfume_compatibility.ps1` is also Standard/blocking. It preserves the
binding Pusfume non-interference clauses in `PROJECT_STANDARDS.md` and
`docs/CROSS_MOD_ARCHITECTURE.md`, requires the release matrix in
`docs/REGRESSION_CHECKLIST.md`, and rejects direct `pusfume` references in active
Lua unless the line carries the explicit `pusfume-compat-reviewed` annotation.
The annotation records review; the live matrix remains required for runtime
compatibility claims.

### Ratchet baselines (issue #429)

Two Standard-policy checks would otherwise be permanently red on pre-existing,
not-per-session-fixable violations, so they are **ratcheted**: the current
violation set is frozen in `qa/baselines/*.json` and the check fails only on a
NEW offender (or growth past a frozen count). This lets the full gate BLOCK on
regressions without being permanently red.

| Check | Baseline file | Frozen | Fails on |
|---|---|---|---|
| `check_file_sizes` | `qa/baselines/file_sizes.json` and `qa/baselines/file_sizes_target.json` | every current hard-limit and target-tier offender has an exact ceiling; hidden repository-internal worktree checkouts are excluded | a NEW hand-written Lua file crossing either threshold, or a baselined file GROWING beyond its frozen non-empty-logical-line count. Shrinkage and removal are allowed and reported for baseline retirement. Generator-owned pure-data tables are recognized only by an `AUTO-GENERATED ... DO NOT HAND-EDIT` banner plus a top-level `return {`, matching PROJECT_STANDARDS §2.1's data exemption. |
| `check_name_integrity` | `qa/baselines/name_integrity.json` | 7 errors in the committed-oracle, no-VtSrc view | a NEW semantic error only. `qa/oracles/vanilla_loc_keys.json` preserves source-proven vanilla keys needed in CI, while the ratchet deliberately reruns without the optional source checkout. Check-2 identity excludes the diagnostic source path, so moving unchanged code between modules cannot manufacture a new error. |

Regenerating a baseline is an **explicit** action (`<check>.ps1 -UpdateBaseline`,
or `check_file_sizes.ps1 -UpdateTargetBaseline` for the independent target-tier
map), never automatic, and requires maintainer sign-off because it can hide a
real new violation. `check_name_integrity -UpdateBaseline` retains the committed vanilla
oracle but forces the no-VtSrc view, so the baseline always matches CI regardless
of the local checkout.

## Legend

- **AUTO**: detected by a script in this directory; runs in CI
- **MANUAL**: human / Claude must verify before ship; checklist item only
- **PRE-SHIP**: covered by the pre-ship subagent review pattern (PROJECT_STANDARDS §5.3)
- **DEFERRED**: known gap, not catchable today; tracked here so it's not forgotten

## Documented bug classes → detection

### Lua-level static issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 1 | Forward-reference crashes (5+ instances) | `feedback_lua_forward_reference.md` | `luacheck` `--no-self` flag catches use-before-decl | AUTO (CI) |
| 2 | Unescaped `%` in localization strings (13 found in one audit); digit-percent literals such as `10% chance` must not be mistaken for `% c` format directives (#346) | `feedback_keep_docs_current.md` + AUDIT_section_c.md | `check_localization.ps1` parses localization values, strips `%%`, rejects digit-percent literals and invalid remaining directives, and ignores lookalike fixtures outside canonical `<mod>/scripts/mods` layout. Self-test: `-SelfTest` (literal, escaped, formatted, and layout fixtures). | AUTO (script) |
| 2a | Cross-mod translations begin before English/1.0 freeze, omit a Fatshark PC language, drift Lua format tokens, use a wrong locale ID, leave runtime-generated rows outside the exportable catalog, or silently redefine one static key (#444) | `docs/TRANSLATION_READINESS_444.md` | `check_translation_readiness.ps1` v1.2.0 inventories `fr/pl/es/tr/de/br-pt/ru`, compares ordered format signatures, detects unknown locale IDs, computed localization generators, and duplicate static identities, and has fixture coverage. Default is diagnostic while blocked; `-Strict` is the future release gate. | MANUAL (diagnostic) |
| 3 | Bare `_foo = function` globals (namespace pollution, CWV has 9) | AUDIT_section_d.md | `luacheck` `unused`/`global` warning | AUTO (CI) |
| 4 | Lua 5.1 incompatibility (`table.unpack`, `goto` in SDK mods) | CLAUDE.md "Lua Environment" | `luacheck` Lua 5.1 dialect mode | AUTO (CI) |
| 5 | Unused locals / dead code | AUDIT_section_d.md | `luacheck` `unused` warning | AUTO (CI) |
| 6 | Wrong storage key (`_attachments[X]` vs `.slots[X]`) — v0.9.8.4 lesson | `feedback_vt2_dormant_buff_template_dual_register.md` + ATTACHMENT_STORAGE_AUDIT.md (archived: `_archive/docs/cosmetics_tweaker/`) | Hard to detect statically; mitigated by PRE-SHIP "verify against vanilla source" rule | PRE-SHIP |
| 7 | `goto`/`continue` in SDK mods (Lua 5.1 limitation) | CLAUDE.md | `luacheck` syntax mode | AUTO (CI) |
| 7a | `--[[ ... ]]` long-comment with embedded `]]` (closes block prematurely) | wt v0.12.69 burn | `luacheck` syntax mode (line "expected '=' ',' or 'in'") | AUTO (CI) |
| 7b | Cross-mod chat-command name collision (7 mods registered `regression_test`) | GitHub Issues #11 / #1176 + `reference_vt2_chat_command_syntax.md` | `check_command_collisions.ps1` reads the authoritative `tools/mod-inventory.psd1` and scans only those canonical `<mod>/scripts/mods/` roots. It never recursively infers owners from arbitrary top-level containers, so QA fixtures, tooling, and valid nested `.claude/worktrees/` checkouts are not pseudo-mods. Its offline `-SelfTest` plants both a nested checkout copy and a real cross-owner collision; `check_ps51_compatibility.ps1 -SelfTest` executes that fixture under PowerShell 7 and Windows PowerShell 5.1. | AUTO (script) |
| 7c | `unpack(t, i)` without explicit `j` → nil-hole truncation (Lua 5.1 `#table` undefined for sparse arrays). Burned weapon_tweaker v0.12.77 → .78 → .79 on 2026-05-25 in a single 2-hour fix cycle. | `docs/VMF_RECIPES.md § 2a` + `CLAUDE.md` engine-quirks + `PROJECT_STANDARDS.md § 9.9` | `check_unpack_safety.ps1` regex scan with `select("#", ...)` / inline-pragma suppression. GitHub Issue #36. | AUTO (script) |
| 7d | Invalid VMF widget `type` (e.g. `text_input`, `slider`, `string`) — breaks entire mod options init at load time, options page vanishes in-game. Burned gt v0.2.60-dev on 2026-05-25 (widget #103 `type="text_input"`). | `docs/VMF_RECIPES.md § 6a` (VMF widget type whitelist) + `docs/BUG_CLASSES.md` "Invalid VMF widget type breaks options init" | `check_vmf_widget_types.ps1` regex scan against canonical 6-type whitelist (`group`/`header`/`checkbox`/`dropdown`/`numeric`/`keybind`). Hard-fail (exit 2) on any non-canonical type — no warning tier, no suppression pragma. | AUTO (script) |
| 7d2 | Malformed numeric `range` — a `range` field with ≠ 2 elements (typically a 3-element `{ min, max, step }`) fails the SAME options-init validation (`'range' field must contain an array-like table with 2 elements`) and kills the ENTIRE mod's options (no `[<mod>:LOAD]`, every tweak gone). A "step" CANNOT live in range[3]; snap in `on_setting_changed`. Burned ct_dev v0.7.188-dev (`starting_coins` range `{ 0, 3000, 25 }`, #164 — mod fully dead until v0.7.189-dev reverted it). | this file + ct_dev CHANGELOG 0.7.189-dev + `docs/BUG_CLASSES.md` | `check_vmf_widget_types.ps1` (same script as 7d) — single-line `range = { ... }` element count; hard-fail (exit 2) on count ≠ 2. Self-test fixture `widget_range_bad.lua`. | AUTO (script) |
| 7e | Stingray `event:register(obj, "ev", FN_VALUE)` — 3rd arg must be a STRING method name on `obj`, not a function value. Engine logs `No function found with name '[function]'` and the handler silently dies. Burned gt v0.2.61 → .62 → .63 → .64 on 2026-05-25 (four separate fixes across lobby MOTD / session-ignore / slot-reservations). | `docs/VMF_RECIPES.md § 12` ("Stingray `event:register` signature") + `docs/BUG_CLASSES.md` "Stingray event:register function-value 3rd arg" | `check_event_register_signature.ps1` regex scan for `:register(<obj>, "<event>", <arg3>)` where `<arg3>` doesn't start with `"`. Hard-fail (exit 2). No suppression pragma. This static check IS the live gate; the former `bt:safe_event_register` runtime safety net (buff_tweaker v0.1.10-alpha+) is RETIRED (bt archived 2026-06). | AUTO (script) |
| 7f | Network-bound engine field WIDENING — a direct `<ident>._max_(overcharge\|energy\|ammo\|charge\|health\|stamina\|push_power) = <rhs>` that RAISES the cap crashes peers via fassert (engine `.network_config` hardcaps these). Burned ct v0.7.100-dev (`energy_ext._max_energy = ...`). | CLAUDE.md memory `feedback_vt2_max_resource_consumption_side` + chaos_wastes_tweaker v0.7.100-dev CHANGELOG | `lint-mod.ps1` Pattern A (Find-NetworkBoundMutation). Heuristic REFINED 2026-05-29 for precision: (a) the former "Pattern B" `stat_buff = "max_*"` data-table string match was REMOVED — those are buff-template literals resolved by the engine's network-safe buff system, not field writes (false-positived on crt's two `stat_buff = "max_health"` entries); (b) DOWNWARD CLAMPS are SAFE — `math.min(...)` RHS or a guarded `if X > CONST then X = CONST end` (canonical: chaos_wastes_tweaker.lua:7831 `_max_ammo` clamp, the load-bearing FIX for a CW-boon cap-widening crash); (c) bare WIDENING assignments STILL fire. WARN (exit 1); ERROR under `-Strict`. `-- LINT_OK_NETBOUND` escape hatch. | AUTO (script) |

### itemV2.cfg / Workshop-level issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 8 | `tags = [ ]` causes ugc_tool 0x2 error | `feedback_ugc_tool_forward_slashes.md` | `check_cfg.ps1` regex scan | AUTO (script) |
| 9 | Missing preview file referenced by cfg | various | `check_cfg.ps1` file-exists check | AUTO (script) |
| 10 | MOD_VERSION constant missing in main lua | `feedback_version_in_workshop_title.md` + CLAUDE.md §"Version bumping" | `check_versions.ps1` regex scan | AUTO (script) |
| 10a | 4-segment MOD_VERSION (e.g. `0.9.9.4-dev`) — the retired within-patch-hotfix anti-pattern; semver is 3-segment `MAJOR.MINOR.PATCH[-track]`. Burned cosmetics_tweaker 2026-05-23. | CLAUDE.md §"Version bumping" | `check_versions.ps1` — flags a 4th numeric segment as a WARNING (exit 1) instead of silently stripping it (issue #429). Normalize on the next bump. | AUTO (script) |
| 11 | cfg title doesn't carry the current version suffix, or an optional leading tester-visible `[b]... vX[/b]` description banner drifts from `MOD_VERSION`. A 2026-08-06 WT 0.12.292-beta publication reached the final launcher gate before the stale 0.12.291-beta title failed closed; no Workshop upload occurred. | `feedback_version_in_workshop_title.md` | `check_versions.ps1` cross-check; title and new banner drift are blocking, while three exact pre-existing description triplets are frozen as a ratchet until intentionally updated. `-SelfTest` plants stale title and banner fixtures. | AUTO (blocking script) |
| 12 | Visibility accidentally flipped to public | `feedback_workshop_metadata_user_dictates.md` | `check_cfg.ps1` whitelist visibility per mod | AUTO (script) |
| 13 | Description doesn't include bug-reporting block | (PROJECT_STANDARDS §7) | `check_cfg.ps1` regex for "issues" link + log path | AUTO (script) |
| 14 | BMC link missing or modified | `reference_bmc_button.md` | `check_cfg.ps1` regex for BMC SVG URL | AUTO (script) |
| 15 | Workshop upload "Upload finished" doesn't mean transferred | `feedback_workshop_upload_verify.md` | Post-upload Workshop page check | MANUAL |
| 16 | Steam doesn't auto-subscribe to own uploads (first-time blocker) | `reference_vmblauncher_handscaffold_first_upload.md` | (info doc; not a check) | MANUAL |

### Localization issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 17 | Referenced but undefined localization key (widget setting_id without entry) | AUDIT_section_c.md | `check_localization.ps1` data↔loc diff | AUTO (script) |
| 18 | Defined but unreferenced key (dead localization) | AUDIT_section_c.md | `check_localization.ps1` data↔loc diff | AUTO (script) |
| 19 | Missing `mod_description` (mh, vdl reported in audit) | AUDIT_section_c.md | `check_localization.ps1` required-key list | AUTO (script) |
| 19a | setting_id with NO loc entry (the red-tooltip class) — stricter ERROR variant of #17 | `docs/generated/README.md` | `check_name_integrity.ps1` check 1 (ERROR, skips concat-fragment ids) | AUTO (script, standalone) |
| 19b | A mod-assigned `display_name`/`item_type`/`description` literal-string key that resolves in NO loc table (mod / any-mod / vanilla) and isn't literal English — typo'd/orphan render key. `Localize(item_type)` is a real render path. | `docs/generated/README.md` | `check_name_integrity.ps1` check 2 (ERROR). Runtime-registered names (cwv `_display_names`, cosmetics `_custom_loc`) resolved via the `NAME_MAP.generated.json` oracle. | AUTO (script, standalone) |
| 19c | Orphan loc key — defined in a mod's `_localization.lua`, referenced nowhere in its Lua/data (some are dynamic) | `docs/generated/README.md` | `check_name_integrity.ps1` check 3 (WARN; concat-prefix aware) | AUTO (script, standalone) |
| 19d | Documented port decision not wired into all 3 surfaces (unlock_map + checkbox + loc) — "decisions must bake immediately" | `feedback_decisions_must_bake_immediately` | `check_decisions_wired.ps1` — parses `weapon_tweaker/CROSS_CHARACTER_PORT_DECISIONS.md`, 3-way: REGRESSION (shipped but missing = ERROR) / LEAK (skip-marked but present = ERROR) / PENDING (To-ADD not yet wired = backlog). Also flags ORPHAN (in unlock_map, no decision row) + UNCLASSIFIABLE (ambiguous doc row). The checker and `gen-name-map.ps1` share `tools/wt-unlock-parser.ps1`, which resolves both legacy literals and #159's documented `W.SYMBOL` keys, applies the source's bounded idempotent additions and removals, and fails closed on missing, malformed, or unknown registry data. Self-test covers REGRESSION, LEAK, mixed literal/symbolic lists, symbolic add/remove mutations, unknown symbols, and a missing registry. | AUTO (script, in run_all) |
| 19e | Player-facing lifecycle/issue metadata leaks into any active stable, beta, or dev localization surface (#694), or runtime status-decoration machinery can re-add it. | `docs/LOCALIZATION_STANDARD.md § 13` "No lifecycle metadata in player-facing localization" | `check_loc_tags.ps1` scans active localization files plus dynamic `en` construction, excludes frozen legacy `tweaker/`, preserves functional qualifiers, and exits 2 on violations. `-MigrationBase <ref>` proves English values equal the merge-base values after lifecycle removal only and that localization keys/count/order did not drift. `-SelfTest` covers forbidden and permitted vocabularies. BLOCKING. | AUTO (script, in run_all) |
| 19f | GitHub issue STATUS-LABEL or live-card deployment-contract drift — an open issue lacks exactly one of `not-started` / `diagnostics-armed` / `verify-fix`, uses retired open `Fixed` / `verify-fix-coop`, or leaks an invalid issue into the live-test queue. | `PROJECT_STANDARDS.md § 11` "Labels" | The advisory `check_issue_status_labels.ps1` retains the CHANGELOG-reference nudge. The blocking grammar in `tools/github/check-lifecycle-cardinality.ps1` pages open labels and complete ready-issue comments through GraphQL and rejects lifecycle/cardinality/pin/topology drift. Its staged deployed-source authority resolves each build to one clean latest-release row, reads Lua only from the recorded commit/tree, tokenizes strings/comments away, excludes literal-false registrations, and binds exact registered commands and literal receipt signatures to that one build. Receipt evidence is finite only through a direct loop-free command callback or immutable tree/source/signature overrides with emitter and guard-token anchors; `goto`, marker-wide families, fake/shadowed printf names, and cross-file global/environment logger mutation do not authorize it. Command-owned receipts require their exact owning command, and native-chat exclusions cannot suppress a contradictory positive evidence requirement. Existing-card authority defects are reported without joining blocking lifecycle errors during backlog repair. Canonical `ship.ps1` enforces authority before a new ready transition, and `refresh-cards.ps1` before a pinned-card rewrite. Optional Workshop coordinates must be supplied as one consistent item/ManifestID pair, but Steam ManifestID authority is outside this corrective lane. CI checks out blob-filtered full history with non-cone sparse `qa`, `tools`, and `*/scripts/mods/` patterns so shared Lua blobs hydrate in the checkout pack instead of per-object promisor fetches; the authority batch-prefetches any still-missing deployed blobs in bounded fetches (a partial-clone self-test fixture proves recovery with lazy fetch forbidden), and the guard emits per-phase timing evidence against its five-minute ceiling. `check_ci_hardening.ps1` plants removal of that active-source hydration boundary. Dual-host adversarial fixtures cover string/comment/long-bracket phantoms, fake/member/shadowed/reassigned/multi-hop aliases, cross-file environment mutation, literal-false routes, backward-`goto` cycles, nested or looping command emitters, command/receipt mismatches, contradictory native-chat prose, helper top-level and per-frame emitters, unrelated command context, dirty/duplicate/version-drifted release rows, exact-command/menu/build/card parsing, seven anchored prior false rejects, and the known-unbounded #491 route. | AUTO (blocking lifecycle grammar + report-only global source audit; strict ship/refresh transitions) |
| 19g | **Retired by #694.** Localization is no longer a GitHub lifecycle surface, so bidirectional loc-tag ↔ issue-label synchronization would enforce the wrong architecture. | `docs/LOCALIZATION_STANDARD.md § 13` | `check_issue_tag_sync.ps1` removed. GitHub lifecycle automation remains covered by row 19f and `tools/ship/ship.ps1`; player-facing leakage is blocked by row 19e. | RETIRED |
| 19h | Promotion leak at SHIP time (issue #327) — a stable/public split-mod ship carrying (a) forbidden lifecycle/status metadata in localization, (b) a pre-release MOD_VERSION suffix nobody named, or (c) a MOD_VERSION that does not match/increase over the stable CHANGELOG. | `docs/PROMOTION_PROCESS.md` "Invariants" + `LOCALIZATION_STANDARD.md § 13` | `check_promotion.ps1` is a stable-ship defense-in-depth gate; the repository-wide row 19e gate already forbids lifecycle metadata in every stream. `VT2_SUFFIX_OK=1` retains the user-named public prerelease override. Self-test covers localization leak, suffix, and monotonicity cases. | AUTO (ship.ps1, stable targets) |
| 19i | A recurring open issue is handled without checking the empirically-related closed history, a fuzzy match is mistaken for proof and reopened automatically, or an issue silently lacks exactly one lifecycle/type/severity label. | `docs/REGRESSION_CHECKLIST.md` + live GitHub issue history | `tools/github/audit-open-issues.ps1` compares every open issue with all closed issues and audits the current lifecycle/type/severity cardinality. Ranking records direct references, exact subsystem labels, lifecycle/surface classes, exact code identifiers, corpus-rare terms, and actual closure/verification evidence. Every high-confidence relation is retained; the configurable match count is only a minimum floor for medium/low review candidates. Workflow and severity labels are excluded from subsystem similarity. The report is read-only and explicitly forbids automatic reopening. `-SelfTest` fixtures prove more than five direct ancestors cannot be truncated, unrelated closure evidence cannot create a relation, missing severity is reported, transparency reasons survive, and every open issue retains three fallbacks. The self-test is auto-run by `qa/run_selftests.ps1`; live GitHub generation remains a deliberate networked maintenance action. | AUTO (offline self-test in full run_all; live report on demand) |
| 19j | Tooltip/description bodies repeat their own localized title, causing VMF/Mod Tweaker popups to show the option name in the header and again as the first body text (#222). | `docs/OVERNIGHT_RETROSPECTIVE_2026-07-15.md` "Popup bodies must not repeat their titles" | `check_loc_description_titles.ps1` scans active `*_localization.lua` files for sibling `foo` + `foo_tooltip`/`foo_description` English pairs and exits 2 if the body starts by repeating the normalized title. `mod_description` is excluded. Self-test covers clean behavior-first text, colon restatement, and functional parenthetical qualifiers. | AUTO (script, in run_all Quick) |
| 20 | Inconsistent CHANGELOG header format (3+ styles in use) | `_archive/audits/2026-05-08/AUDIT_section_b.md` | `check_changelog_format.ps1` (future) | DEFERRED |

### Hook / vanilla-API issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 21 | Hook on BASE class when DERIVED is the runtime type | CLAUDE.md §"HOOK THE DERIVED CLASS" + `feedback_vt2_class_hook_derived.md` | Hard to detect statically; mitigated by PRE-SHIP review | PRE-SHIP |
| 22 | Hook drops vanilla arg through too-narrow signature (`function(func,self,a,b,c)` when vanilla takes 5) | weapon_tweaker_backend.lua audit | PRE-SHIP review pattern | PRE-SHIP |
| 23 | Guard returns without calling vanilla `func` — silently changes state | PROJECT_STANDARDS §4.2 + ATTACHMENT_STORAGE_AUDIT lesson | PRE-SHIP review pattern | PRE-SHIP |
| 24 | "Attempting to rehook active hook" (same Class+method hooked twice in one mod handle) | v0.9.8.2 lesson | PRE-SHIP review (grep `mod:hook` for duplicate Class+method pairs per file) | PRE-SHIP |
| 24a | A diff ADDS a `mod:hook`/`mod:hook_safe` or a `NetworkLookup` write in a mod's lua but ships NO regression marker, so the singleton-hook invariant (#24, CLAUDE.md NON-NEG #8) and the gated-registration invariant (#29) go unchecked as the mod evolves. | CLAUDE.md NON-NEG #8 + `feedback_vmf_no_duplicate_hooks` + `feedback_vt2_gated_registration_diverges.md` | `check_hook_test_coverage.ps1` — parses `git diff -U0` (`-Range` default `HEAD~1..HEAD`, `-Staged`, or `origin/<base>...HEAD` in CI). A file that adds a hook/NL-write is covered iff the diff also adds a `_rt_register(`, carries a `-- hook-test: <check>` comment, OR the mod already ships an `_rt_register` suite. WARNING-only (exit 1), pinned **Advisory** in `run_all` + a warn-only step in pre-commit — gathers signal, never blocks; self-exits 0 on an indeterminate diff. Coverage-EXISTENCE, not per-hook proof (a marker can't be statically matched to one hook). The `_rt_register` suite it credits is the tier-(b) in-game regression harness defined in `PROJECT_STANDARDS.md` §2.2b (this gate is tier (a)). Self-test: `-SelfTest` (synthetic diff through the pure parser + decision fn). | AUTO (script, in run_all + pre-commit) |
| 25 | 1P animation override per character (breaks universal anim chain) | `feedback_1p_animations_universal.md` | PRE-SHIP review (grep for `anim_event = ` or `wield_anim = ` in cross-character contexts) | PRE-SHIP |
| 26 | Speculative defense stacking (v0.9.8.3-7 chain) | PROJECT_STANDARDS §9.1 | PRE-SHIP review pattern | PRE-SHIP |

### Network / multiplayer issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 27 | VMF RPC string > 500 chars (Stingray hardcap) | `reference_vmf_rpc_string_cap.md` | Manual — VMF doesn't expose payload size; mitigated by chunking pattern | MANUAL |
| 28 | `network_send(..., "server", ...)` silently dropped | `reference_vmf_network_send_recipients.md` | `check_network_send.ps1` regex scan for `"server"` as recipient (future) | DEFERRED |
| 29 | Conditional registration → peer NetworkLookup drift → crash on join | `feedback_vt2_gated_registration_diverges.md` | PRE-SHIP review (every `BuffTemplates[X] = ` or `NetworkLookup.X[#X+1] = ` must be unconditional + sorted) | PRE-SHIP |
| 29a | CT adventure/duplicate level registration exceeds VT2's fixed `weight_array.max_size` and crashes before the keep loads | Issue #590; crash GUID `9bd4c67f-8633-4b29-b4e3-7e306bd82feb`; ct_dev DEVELOPMENT "Adventure pool duplicate aliases and the network level budget" | `check_level_lookup_budget.ps1` derives mission x theme cost, enforces 792 <= 1,024 for the current catalog/baseline, and forbids duplicate-alias LevelSettings/NetworkLookup writes. Blocking in Quick/full `run_all` and `publish-release`. | AUTO (script) |
| 30 | Mutator template `server_start_function` field is dead (must hook `server.start_function`) | `feedback_vt2_mutator_template_server_wrap.md` | PRE-SHIP review pattern | PRE-SHIP |
| 31 | Husk RPC race (rpc_create_attachment arrives after cos_la_apply) | `reference_vt2_husk_rpc_race.md` | Architectural; mitigated by hook ordering | PRE-SHIP |
| 32 | Husk extension class pair (Simple* vs SimpleHusk*) — must hook both | `feedback_vt2_husk_extension_class_pair.md` | PRE-SHIP review (any hook on `Simple*Extension` must check sibling `SimpleHusk*Extension`) | PRE-SHIP |
| 33 | Lobby `combined_hash` includes `num_levels` — injecting level_keys breaks vanilla join | `reference_vt2_lobby_combined_hash.md` | Architectural; mitigated in ct via shim | PRE-SHIP |

### Vanilla-API drift issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 34 | `DeusPowerUp` rarities limited to event/rare/exotic/unique only | `reference_vt2_deus_power_up_rarities.md` | PRE-SHIP review pattern | PRE-SHIP |
| 35 | Skittergate loot_amount_settings nil for hybrid breed names | (just fixed v0.7.82 via `__index` metatable) | Caught at runtime via mod:warning; metatable is the fix | (FIXED) |
| 36 | Vanilla `NetworkedFlowStateManager` leak (fatals at 512 states) | `reference_vt2_networked_flow_state_leak.md` | Architectural; ct patches via `mod:hook` | (PATCHED) |
| 37 | Adventure-injected levels crash on no_roamers mutator | `reference_vt2_adventure_pack_spawning_compat.md` | Architectural; ct strips incompatible mutators | (PATCHED) |
| 38 | Custom ExplosionTemplates need `.name` + global registration | `reference_vt2_custom_explosion_template.md` | PRE-SHIP review | PRE-SHIP |
| 39 | VMF custom_gui_textures must list ui_renderer_injections | `reference_vmf_renderer_creator_keys.md` | PRE-SHIP review | PRE-SHIP |

### Cosmetics-specific issues (handed off to other agent group)

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 40 | Cross-character LA hat applied to wrong skeleton (j_spine1 / j_spine2 crash) | ATTACHMENT_STORAGE_AUDIT.md (archived: `_archive/docs/cosmetics_tweaker/`) | Cosmetics agent group | HANDED OFF |
| 41 | Same-character LA hat with incompatible attachment_node_linking (j_spine2 v2 — e6fc17e2 crash) | (new this session) | Cosmetics agent group | HANDED OFF |
| 42 | Vanilla offhand picks don't sync across peers | HOST_CLIENT_AUDIT.md | Cosmetics agent group | HANDED OFF |
| 43 | Per-peer glow RPC unimplemented | HOST_CLIENT_AUDIT.md | `glow_picker_render_fanout_574`, `test_cos_glow_lifecycle.lua`; #574 user co-op verified 2026-07-13 | (PATCHED) |
| 44 | LA armor apply leaks icons into vanilla inventory | HOST_CLIENT_AUDIT.md | Cosmetics agent group | HANDED OFF |
| 45 | `_apply_la_on_unit` offhand respawn pending-queue fragile | HOST_CLIENT_AUDIT.md | Cosmetics agent group | HANDED OFF |
| 46 | CWV ammo weapons need full skin field mirroring | `feedback_cwv_ammo_unit_required.md` | PRE-SHIP review (covered by CWV DoD gate) | PRE-SHIP |
| 47 | CWV cross-character variants — base item gets cross-mod registration | `feedback_cwv_clone_name_clobber.md` | PRE-SHIP review | PRE-SHIP |
| 48 | CWV custom-mesh — multiple pitfalls | `reference_cwv_custom_mesh_material.md` | PRE-SHIP review (CWV RECIPES.md) | PRE-SHIP |

### Docs / repo hygiene issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 49 | Stale audit/review markdown > 14 days unbanner'd; also a snapshot-banner'd doc left OUTSIDE `_archive/` (issue #502) | PROJECT_STANDARDS §7.2 | `check_stale_docs.ps1` two scans: (1) date scan (`$StaleDays = 14` default, exit 2); (2) banner-placement scan (issue #502, exit 1) - a doc whose head carries the snapshot banner ("...this snapshot is from...") but sits outside `_archive/` should be `git mv`'d there. Scan 2 is head-only (no false positive on format docs), skips `CODE_REVIEW.md` (mandatory per-mod canonical doc, §7.1) and gitignored files (untracked, not `git mv`-able). (3) pointer-stub link integrity (issue #432, exit 1) - a doc HEAD with a supersession/pointer banner (SUPERSEDED / moved to / merged into) whose markdown `.md` link resolves to no file (checked against the stub dir AND repo root) is a dangling stub from a later rename; time-independent, guards the #432 consolidation's ~15 stubs. All pinned **Advisory** in `run_all` (issue #429) - staleness is TIME-based and must not hard-block a commit/CI. Fix staleness with `run_all.ps1 -FixStale`; fix placement by archiving; fix a dangling stub by repointing its link. | AUTO (script, advisory) |
| 50 | Memory cited claim no longer matches current code | PROJECT_STANDARDS §12.3 | PRE-SHIP review (verify before recommending) | PRE-SHIP |
| 51 | CHANGELOG entry missing for current MOD_VERSION | PROJECT_STANDARDS §6.4 | `check_versions.ps1` cross-check | AUTO (script) |
| 52 | File exceeds the 1500-line target or 2500-line hard limit | PROJECT_STANDARDS §2.1 | `check_file_sizes.ps1` uses the canonical `Get-Content | Measure-Object -Line` metric: empty logical lines are excluded and whitespace-only lines count. It ratchets both tiers: `qa/baselines/file_sizes.json` freezes hard-limit debt, while `qa/baselines/file_sizes_target.json` freezes exact ceilings for current target-tier debt (issues #429/#2). A new threshold crossing or growth past either ceiling blocks; shrinkage/removal is allowed and surfaced for retirement. Repository-internal worktree checkouts are excluded. | AUTO (script + adversarial `-SelfTest`) |
| 52b | Accidental edit to a split-mod STABLE dir, or a promotion PR self-authorizes through branch-owned metadata/code (dev/stable split; stable is write-by-promotion-only). | CLAUDE.md NON-NEG #3 + `PROMOTION_PROCESS.md` | `check_dev_only_edits.ps1` flags stable-dir changes. A base-owned `pull_request_target` status checks out only protected-branch code; `check_promotion_authorization.ps1` permits only a same-repository PR with the live `stable-promotion-approved` label and an admin/maintain-authored comment bound to every changed stable dir, current MOD_VERSION, and exact head SHA. `qa-gate` independently exports only those dirs and runs `check_promotion.ps1` for each; branch protection requires both statuses. The gate resolves the exact PR diff: authorization-bound Markdown maintenance other than `CHANGELOG.md` skips release-only suffix/version checks, while every runtime, cfg, localization, changelog, bundle, or other stable-file change retains them. A push, label removal, fork, untrusted actor, stale version, edited-after-grant comment, or PR-authored gate rewrite fails closed. Local promotion retains the explicit `VT2_PROMOTION=1` maintainer path. The checks carry offline self-tests. Issues #429/#676/#1025. | AUTO (base-owned authorization + protected PR QA + run_all + pre-commit) |
| 52a | Uncited mechanic claim in the MECHANICS substrate — a factual bullet in `docs/MECHANICS.md` with no provenance tag (the hallucination-propagation class). Cure for "session drifts on a mechanic, hallucinates, wrong claim spreads." | `feedback_vmf_ui_no_guessing` (generalized to ALL mechanics) + PROJECT_STANDARDS §13 | `check_mechanics_citations.ps1` — scans factual bullets only in `docs/MECHANICS.md`; every bullet under a `## Domain:` heading (including under `###` subheadings, which subdivide a Domain rather than closing it — fixed 2026-08-02) must carry `[src:]`/`[dump:]`/`[memory:]`/`[bugclass:]`/`[user:]` or `[unverified]`. `[unverified]` is ALLOWED + counted as the known-gaps backlog metric. ERROR (exit 2) on any untagged bullet. Independently resolves every `[src:]` ref in `MECHANICS.md`, `BUG_CLASSES.md`, `WEAPON_APPEARANCE_STANDARD.md`, and `CROSS_MOD_ARCHITECTURE.md` (file exists, line in range, parseable payload) when the decompile checkout is present; missing decompile is a clean visible SKIP (CI), `-RequireSource` makes absence blocking, `-ResolveSrc` runs the four-document resolver standalone. Self-test plants uncited + unverified + cited bullets plus a subheading case. Wired into `run_all.ps1` (Standard policy — exit 2 blocks). | AUTO (script, in run_all) |
| 52c | Decompiled-source citations have no reproducible snapshot identity, or their cited file/function drifts after a source update (issue #543). | `docs/engine/README.md` maintenance rules + `docs/engine/SOURCE_PROVENANCE.json` | `check_source_provenance.ps1` — always validates the committed manifest schema (source commit, game/runtime revisions, extraction provenance, timestamps, safe anchor paths). With an optional sibling `Vermintide-2-Source-Code` checkout it additionally requires the pinned Git HEAD and game version, then verifies one file + stable `Class.function`/symbol anchor per engine subsystem. Missing local source is a clean, visible SKIP in CI; `-RequireSource` makes absence blocking for a maintainer refresh. Self-test covers schema, symbol success/failure, path traversal, and optional-source behavior. | AUTO (script, in run_all) |
| 52d | Pure Lua transforms regress but cannot be exercised outside the game (issue #544). | `qa/lua/README.md` + PROJECT_STANDARDS §2.2 | `check_lua_unit_tests.ps1` runs dependency-free suites against production helpers under a pinned, vendored PUC-Rio Lua 5.1.5 runtime. The gate is offline and runs in both Quick and full QA; `-SelfTest` proves both the harness pass path and planted-failure detection. Initial coverage owns deterministic attack-chain sorting/filtering and label normalization. Engine hooks/RPCs stay in the in-game tier; source spelling stays in textual invariants. | AUTO (script, in run_all Quick + full) |
| 52l | A refactor cuts a Lua range mid-block, or otherwise introduces syntax that textual gates cannot detect, while PUC Lua 5.1 cannot parse Vermintide's supported `goto` extension (#1223). | Issue #1223; PR #1222 ad-hoc parse audit | `check_lua_parse.ps1` structurally parses every active inventory mod's `scripts/mods/**/*.lua` with the SHA-256-pinned vendored Luacheck parser. It enumerates exact files with `-Force` and uses bounded 40-file batches, so Windows-hidden build inputs are included without an unbounded command line. All semantic warning families are disabled here; parser rejection is source exit 2, while missing/unreadable inputs, inventory defects, or tool failure are infrastructure exit 99. The parser accepts the repository's authored `goto`, but is not proof of the exact VT2/LuaJIT runtime dialect. The gate runs even under `-Quick -SkipLua`. `-SelfTest` proves `goto`, warning suppression, a 41-file/two-batch path, a late Windows-hidden syntax failure, parser I/O classification, and empty-inventory rejection. | AUTO (blocking script, Quick/full run_all + pre-commit) |
| 52e | CI skips an unlisted build-input extension, runs a mutable action, gains write credentials, executes PR code in a trusted boundary, or branch protection is weakened/activated while QA is red (issue #540). | `docs/CI_PROTECTION.md` | `check_ci_hardening.ps1` validates no push path filter, least-privilege permissions, immutable action SHAs, non-persistent checkout credentials, concurrency/timeout/event coverage, PS5 release self-tests, base-owned promotion/PR-closure workflows, and the fail-closed protection tool. `tools/github/protect-master.ps1` refuses application until latest master QA succeeds, then requires `qa-gate`, `stable-promotion-authorization`, and `pr-autoclose-authorization` for admins and blocks force-push/deletion. All policy tools carry offline self-tests. | AUTO (run_all + guarded maintainer apply) |
| 52f | Canonical active-mod inventory drifts: an active `itemV2.cfg` mod is omitted from release/lint, a retired mod remains, or directory/VMF/Workshop identity and visibility disagree (issue #546). | `tools/mod-inventory.psd1` + `tools/publish-release/README.md` | `check_mod_inventory.ps1` cross-checks every active root cfg, main-source `get_mod()` id, README directory table, Workshop id, visibility, stream/public policy, and uniqueness. Missing canonical inventory is a hard error in cfg and lint consumers. Self-test plants duplicate, omitted, and metadata-drift cases. | AUTO (script, Quick/full run_all) |
| 52j | A merged PR auto-closes an issue before user verification and the post-fix pass (issue #750; PR #969 closed #592). | `PROJECT_STANDARDS.md` section 11 "Pull-request closure integrity" | `check_pr_autoclose.ps1` blocks all nine GitHub closing keywords (case-insensitive, optional colon, local/cross-repo/full-URL refs) unless the issue has a trusted exact closure receipt. Local missing context skips visibly; the required base-owned pre-merge status fails closed. A second trusted workflow reopens unauthorized closures post-merge. | AUTO (Quick/full run_all, protected pre-merge status, post-merge audit) |
| 52g | A custom `.unit` compiles into an unrooted sibling bundle, or a preview loads the unit path as a package but the same-ID `.package`/material closure was never compiled, so source tests and upload-file counts pass while asynchronous UI loading fatals with `Resource '#ID[...]' was not found`. | CWV Greataxe package failure (2026-07-14); Encarmine Helmet `BD55DCA31255AAEC.package` failure (#612, 2026-07-15) | `check_custom_unit_bundle_reachability.ps1` Murmur-hashes every authored custom unit and inspects compiled bundle contents with the VT2 unpacker. Every `.unit` must be resident in a bundle named by an explicit source `.mod` package root. A sibling `.package` additionally promises that PackageManager can load the unit path directly: the gate requires its same-ID package forwarder in the explicit root, its standalone bundle, its unit, every material bound by the unit, and every texture referenced by those materials. The Encarmine contract also pins both supplied diffuse SHA-256 values and the four unchanged vanilla normal/packed source hashes. The check runs in Quick/full QA when the local unpacker and compression dictionary are available. | AUTO (script, local tool-backed) |
| 52h | An appearance concern gains a provider/adapter but omits one render surface, replay edge, or named offline test, recreating the issue #660 whack-a-mole class while source-local tests remain green. A second failure mode (#1158): the registry spelled a surface differently from the census (`remote_husk_3p` vs `husk`), so one domain had two vocabularies and a gap could hide between them - neither gate could tell that two rows were the same row. | `docs/WEAPON_APPEARANCE_STANDARD.md` §8a + issue #660 closed-history audit | `appearance_contracts.psd1` is the registry; `check_appearance_contracts.ps1` owns immutable minimum surface/replay/concern vocabularies so the registry cannot silently shrink them. **Single vocabulary:** new surface/edge names enter through `tools/shared_lib/_lib_appearance_descriptor.lua` (`M.CELLS`/`M.EDGES`) ONLY; the manifest uses canonical spellings and every name is validated against `tools/shared_lib/_lib_appearance_name_authority.lua` (read under the pinned vendored Lua 5.1 host, same mechanism as the census gap generator), which binds each legacy spelling, records contract names deliberately finer than the census as refinements, and records genuine census gaps. The ordinary `crafting_preview` bench is now a canonical surface distinct from the CIM `cim_preview` forge (#1198). A legacy spelling fails naming its replacement; an unmapped name fails naming the authority. The gate requires all 17 canonical surfaces in every concern and reverse-checks its explicit required set against the descriptor authority, so a newly canonical surface cannot hide between the two registries (#1197). The authority is deliberately outside the descriptor because `manifest.psd1` byte-syncs the descriptor into the CWV mod bundle. Every registered concern declares each cell as `covered`, `deferred`, or `not-applicable`, with reasons for non-covered cells and an existing named test for covered cells. Claims are `structural-only`; this is not runtime verification. Blocking in Quick/full `run_all`. `-SelfTest` proves vocabulary-contraction, missing-cell, missing-tests, unmapped-covered-cell, stale-test-name, legacy-spelling, unmapped-name, and unrepresented-canonical-surface failures, plus that the live authority and full required set agree. | AUTO (script, Quick/full run_all) |
| 52j | An appearance census declares a hole (or closes one) and the committed issue-660 backlog is not regenerated, so `docs/generated/APPEARANCE_CENSUS_GAPS.generated.md` keeps reporting a gap count that no longer matches the censuses - the stale-catalog-that-gets-trusted class the generated docs exist to prevent. | Issue #1157 surface x edge re-key + `docs/generated/README.md` | `tools/gen-appearance-gaps/gen-appearance-gaps.ps1` expands every census in `_lib_appearance_descriptor.lua`'s `M.CENSUS_FILES` through the shared `M.expand_matrix` (driven under the pinned vendored Lua 5.1 host, so the report and `test_appearance_census` agree by construction) and writes the deduplicated backlog. `check_appearance_census_gaps.ps1` delegates to the generator's `-Check` mode, which regenerates in memory and compares byte-for-byte while reusing the committed `Generated:` stamp so a stale date is never reported as content drift. `-SelfTest` proves determinism and that the comparator rejects mutated text. Blocking in Quick/full `run_all`. | AUTO (script, Quick/full run_all) |
| 52i | The #504 decomposition inventory becomes stale prose, an oversized entry silently regrows, a completed phase is falsely claimed while above target, an already-extracted owner disappears, or a PR raises a frozen ceiling to conceal regrowth. | `docs/OOP_REFACTOR_PLAN.md` current execution inventory + PROJECT_STANDARDS §2.2a | `decomposition_contracts.psd1` is the phase registry. `check_decomposition_contracts.ps1` requires all ten canonical phases, unique repo-relative entry paths, `complete`/`partial` state, downward-only entry ceilings, and existing owner modules referenced by each entry. Complete phases must remain below the 1500-line target. In PR CI it reads the manifest at `origin/$GITHUB_BASE_REF`, always prints the exact total ceiling delta against master, blocks any existing contract ceiling increase/removal, and distinguishes a newly inventoried contract from regrowth. Its self-test proves positive, planted current growth, missing owner/phase, ceiling burn, planted base-relative regrowth/removal, and inventory expansion. | AUTO (script, Quick/full run_all) |

### Process issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 53 | Hot-reload assumption (Ctrl+Shift+R breaks unit-creation hooks + non-Lua resources) | `feedback_hot_reload_unfixable.md` | (info; user/Claude must full-restart for hot mods) | MANUAL |
| 54 | PS 5.1 `Get-Content -Raw` defaults to Windows-1252, not UTF-8 | `feedback_ps5_getcontent_utf8.md` | (info; affects tooling authors only) | MANUAL |
| 55 | Workshop upload metadata user-dictated (only version suffix auto-managed) | `feedback_workshop_metadata_user_dictates.md` + `feedback_version_in_workshop_title.md` | PRE-SHIP review (any cfg description change must be user-requested) | PRE-SHIP |
| 56 | Deploy to PC-B every time (launcher v0.4.0+ auto-pushes) | `feedback_deploy_both_machines.md` | Handled by VMBLauncher | (HANDLED) |
| 57 | Always Workshop-upload + publish GitHub release together | `feedback_post_workshop_upload_github_release.md` | (workflow pattern) | MANUAL |
| 60 | Native stderr + `$ErrorActionPreference='Stop'` + stream redirection = terminating `NativeCommandError` on PS 5.1 — an EXPECTED-failure probe (e.g. `gh release view` on a not-yet-created tag, `gh auth status` unauthenticated) kills the whole pipeline script mid-run (issue #489, died mid-ship 2026-07-11). Never `& gh ... 2>&1 \| Out-Null` under EAP=Stop; route probes through `Invoke-NativeProbe` (ship.ps1) / `Invoke-GhQuiet` (publish-release.ps1): EAP scoped to Continue, stderr discarded, exit code is the only signal. | issue #489 | `ship.ps1 -SelfTest` (probe no-throw + exit-code propagation + EAP-restore cases; runs in `run_selftests.ps1`) | AUTO (script, in run_selftests) |
| 60a | PowerShell variable names are CASE-INSENSITIVE: an internal `$mods = ...` assignment silently OVERWRITES a `[string[]]$Mods` parameter — publish-release's per-mod filter (issues #436/#493) saw 19 inventory hashtables instead of the shipped mod name and aborted a live ship (2026-07-13). Internal variable renamed `$releaseSet`. | issue #493 | `ship.ps1 -SelfTest` (asserts publish-release.ps1 declares `[string[]]$Mods` and never assigns lowercase `$mods`) | AUTO (script, in run_selftests) |
| 60b | Filtered release validation must not demand carried siblings' bundle files in the one-mod staging directory. Only `RequiredModIds` were rebuilt; carried entries still receive schema/provenance validation, while byte validation is scoped to the staged set. Historical carried entries may also predate `bundle_files`: absent/null JSON values must not become one phantom record under PowerShell array semantics. | live deployment regressions, 2026-07-14 and 2026-07-28; issue #1036 | `check_release_manifest.ps1 -SelfTest` builds one staged entry plus one fully-provenanced carried sibling with no staged directory, accepts the filtered manifest, and still rejects malformed carried provenance. JSON-round-tripped absent/null records route to the whole-ZIP-SHA transition only when explicitly carried and not staged; staged/unclassified missing records fail, while provenance-bearing carries retain strict inner-file verification. | AUTO (script, in run_selftests) |
| 60c | Steam rewrites a textual `.mod` descriptor from LF to CRLF, causing the canonical ship gate's raw SHA-256 check to report a false deploy mismatch even though every compiled bundle is current. Equivalence must never spread to `.mod_bundle` or hide real descriptor changes. | issue #646; `BUG_CLASSES.md` class 52 | `ship.ps1 -SelfTest` exercises the live comparator: LF/CRLF-only `.mod` differences pass; changed descriptor text and standalone CR fail; `.mod_bundle` remains byte-exact. Auto-discovered by `run_selftests.ps1`. | AUTO (script, in run_selftests) |
| 60d | Multiple git worktrees share VMBLauncher's global `ProjectRoot`; a ship invoked from one worktree can otherwise build and upload stale source from another while using the invoking worktree's version metadata. | issue #647; `BUG_CLASSES.md` class 53 | Under the machine transaction, `ship.ps1` reads global settings once for dependency discovery, creates one durable private exact-root `--config`, and never rewrites shared settings. It validates root/version/commit/id before separate build/deploy/upload actions. `ship.ps1 -SelfTest` covers byte-exact shared preservation, private binding, exact stale/live PID-start cleanup, and four identity mismatch cases. | AUTO (script, in run_selftests) |
| 60e | GitHub's release-by-tag route can return HTTP 503 while the releases-list, release-asset, and upload routes remain healthy. Treating every failed tag probe as "absent" either aborts a filtered ship or attempts a duplicate release. | issue #651; `BUG_CLASSES.md` class 55 | `check_github_release_fallback.ps1 -SelfTest` covers canonical success, 404, 503 exact-list fallback, bounded pagination/exhaustion, ambiguous/no match, exact asset selection, asset-id download, and release-id clobber with manifest last. Auto-discovered by `run_selftests.ps1`; `ship.ps1 -SelfTest` pins delegation/no duplicate tag probe. | AUTO (script, in run_selftests) |
| 60f | Long-lived `agent/*` and `codex/*` refs are merged or deleted from branch names, issue numbers, version files, or path overlap alone; patch-equivalent successors and genuinely stranded fixes become indistinguishable (issue #625). | `docs/BRANCH_RECONCILIATION_WORKFLOW.md` + committed branch census | `branch-reconciliation-census.ps1` inventories local/remote refs without mutation, deduplicates identical tips, and records exact ancestry, `git cherry`, issue refs, changed paths, current-source overlap, ahead/behind, and version/manifest signals. Only exact ancestors and complete pure patch-equivalent tips receive automatic states. `check_branch_reconciliation_census.ps1` validates the committed schema, age, generator hash, JSON/Markdown parity, and proof predicates offline; both scripts carry PS7/PS5.1 fixture self-tests. | AUTO (offline gate in Quick/full; live census regeneration is deliberate) |
| 60g | A clean-worktree ship resolves VMBLauncher from configured `ProjectRoot`, but a later phase re-resolves mutable path bytes, follows a junction outside the approved location, records another executable's version, or releases its proof before build/release/upload completes. | issue #683/#1400; `BUG_CLASSES.md` class 53 | The resolver rejects unapproved provenance and every reparse component. Canonical ship opens one read/delete-denying executable lease, binds canonical path + stable file ID + Int64 length + SHA-256 + version from that handle, and starts every capability/build/deploy/upload child through the same hidden process boundary. Publisher receives the live same-runspace lease; identity/content is checked before `Start()` and after `WaitForExit()`, and disposal occurs only after upload, before transaction release. `check_vmb_launcher_path.ps1 -SelfTest` covers process execution, write/delete/rename/replacement denial, altered same-version bytes, junction escape/retarget, path comparisons, forged/mutated/disposed leases, and static ship/publisher wiring. The host matrix requires it under Windows PowerShell 5.1 and PowerShell 7. | AUTO (blocking dual-host matrix in full run_all) |
| 60h | A BOM-less UTF-8 PowerShell script contains smart punctuation in live code; Windows PowerShell 5.1 decodes it through the ANSI code page, a resulting smart quote terminates the string, and `run_all` can misclassify the parser crash as Advisory. | issue #85; `BUG_CLASSES.md` class 72 | `check_ps51_compatibility.ps1` byte-checks the explicit ASCII bootstrap/release set and derives the full QA/pre-commit invocation closure, which `run_ps51_parse_matrix.ps1` parses with the actual PS5 parser. Its dual-host self-test covers zero/fresh/stale/malformed sentinels, planted BOM-less failure vs UTF-8 BOM success, and `run_all -SelfTest` proves legitimate advisory findings remain non-blocking while parser/host/tool failures block. | AUTO (Quick/full run_all + PS5 CI step + self-tests) |
| 60i | A tool rewrites a tracked `.mod` working copy to CRLF while Git's text normalization makes `git status` look clean; publication then hashes raw bytes that do not match the reviewed/indexed descriptor, or a root descriptor silently differs from its `bundleV2` copy. | issue #1085; issue #646 | `check_mod_descriptor_line_endings.ps1` enumerates every tracked `.mod`, rejects CR bytes, compares raw unfiltered worktree objects with index blobs, and requires byte-identical root/bundleV2 pairs. Its PS5-compatible self-test proves clean LF, hidden CRLF/index drift, and pair-drift paths. | AUTO (blocking Quick/full run_all + self-tests) |
| 60j | Two release streams share one runtime load tag, so a post-ship card refresher mistakes the sibling's anchored version for the just-shipped stream and bulk-rewrites valid live-test cards (#1102: public WT beta rewrote 15 WT Dev cards). | issue #1102 | `ship.ps1` passes exact mod directory, Workshop ID, and display/stream identity. `refresh-cards.ps1` inventories same-tag siblings and requires an exact stream name or unambiguous item identity before any version rewrite; a card whose anchor belongs to a sibling may receive only the shipped item's exact manifest update. Offline fixtures cover public/dev cross-contamination, same-stream refresh, ambiguous fail-closed behavior, and #948-shaped item-only manifest preservation. `check_ps51_compatibility.ps1 -SelfTest` executes the same fixture under PowerShell 7 and Windows PowerShell 5.1. | AUTO (ship post-upload + dual-host self-tests) |
| 60k | A runtime LOAD banner is delegated to a helper Lua file, so canonical ship falls back to the source directory while the card refresher independently discovers the helper-owned tag and rejects the post-upload refresh (#1298: `crafting_in_modded_dev` versus `[cim:LOAD]`). | issue #1298 | `load-tag-resolution.ps1` is the shared deterministic resolver: one main-file tag is authoritative; otherwise exactly one unique case-sensitive root-Lua tag wins before any caller fallback; conflicting literals fail closed. Root discovery includes Windows-hidden Lua inputs. `ship.ps1 -SelfTest` pins pre-lifecycle resolution and named refresher passthrough. `refresh-cards.ps1 -SelfTest` exercises helper-only CIM, main precedence, an actual hidden conflicting helper, case-variant conflicts, inventory propagation, and marker-free fallback; `check_ps51_compatibility.ps1 -SelfTest` runs those fixtures under PowerShell 7 and Windows PowerShell 5.1. | AUTO (ship post-upload + dual-host self-tests) |
| 60l | Sequential single-stream card refreshes strand stale cross-mod cards because every intermediate body still fails deployed-source authority; no-op parser reconstruction or overlapping duplicate-coordinate edits can also mutate or abort the repair (#1343). | issue #1343 | `refresh-cards.ps1 -ReconcileAllStreams` joins the complete deployed-source inventory, attributes shared tags fail-closed, plans every anchor update in one candidate, preserves original line endings and byte-exact no-ops, removes non-overlapping duplicate coordinate clauses, and validates the final card once before any GraphQL mutation. Dual-host fixtures cover atomic cross-mod updates, public/dev shared tags, ambiguity, known incomplete coordinates, cross-line duplicates, adjacent first/last duplicate clauses, CRLF preservation, and no recognized surface. | AUTO (corrective dry-run/live lane + dual-host self-tests) |
| 61 | "Fixed" conflates five pipeline states — in source / in the CHANGELOG / compiled into `bundleV2` / uploaded to Workshop / pulled by the player. A fix stranded on a lower rung (`[not deployed]` CHANGELOG entries like cim #246; a mod uploaded while the tester still runs the prior version, e.g. mp 0.2.29 vs a 0.2.28 tester) is invisible until five surfaces are read by hand, surfacing later as "nothing you fixed works". | this row + `feedback_local_deploy_clobbered_must_upload` / `feedback_github_release_is_not_workshop_upload` | `check_pipeline_state.ps1` prints one ladder row per active mod in `tools/mod-inventory.psd1` (frozen `tweaker` excluded there; dev/stable pairs are separate rows): source `MOD_VERSION`, newest `## <version>` CHANGELOG header, bundle state (`fresh`/`STALE`/`none` — newest `bundleV2` mtime vs newest `scripts/` mtime, a stated mtime HEURISTIC that is checkout-sensitive and only meaningful on the live working tree), last `Uploaded new content`/`No content change` timestamp for the cfg `published_id` from `workshop_log.txt` (opened shared-read since Steam holds it), a `[not deployed]` flag (top-3 CHANGELOG entries), and a verdict `IN-SYNC` / `CHANGELOG-DRIFT` / `BUNDLE-STALE` / `UPLOAD-BEHIND` (combined with `+`). Read-only; ALWAYS exits 0 (Advisory in `run_all`); upload column is `n/a` when the log is absent (CI). Self-test: `-SelfTest` (planted verdict + CHANGELOG-parser fixtures), auto-discovered by `run_selftests.ps1`. | AUTO (advisory, in run_all) |
| 61a | Protected master accepts runtime/version/config/newest-release changes without the owning mod's exact output-authority proof, or silently deletes a tracked sibling bundle during clean-build/merge resolution (#724, #1100; PRs #759/#765/#766/#767/#769/#1099). | issue #724/#1100 evidence + reconciliation PRs #771/#772/#773/#1099 | `check_release_bundle_atomicity.ps1` compares the staged/PR/push diff against each mod's declared `BundleAuthority`. Tracked authority requires exact root A/M; shared/sidecar bundles do not count. Receipt authority delegates to the schema-3, zero-tracked-output, complete typed transition proof in `bundle-authority.ps1`. Outside that exact transition, any tracked bundle deletion requires a newly added exact `VT2-Bundle-Retirement: <16-hex>.mod_bundle` trailer, and an active tracked canonical root cannot be deleted. Docs/tests-only, historical changelog prose, authority-proof-only reconciliation, exact title synchronization, and the mandatory first-upload `published_id = 0L` to positive-ID reconciliation pass only under their fail-closed predicates. The ID lane still requires #1278's refreshed receipt and unchanged version/title/other cfg bytes. Stable metadata-only promotion requires the existing explicit promotion sanction. `-SelfTest` loads the direct fixture matrix. | AUTO (blocking Quick/full CI + pre-commit) |
| 61b | A Workshop upload starts from an unmerged/dirty worktree, stale default-branch commit, failed/missing hosted QA, caller-forged authorization JSON, claim-only direct launcher/GUI publication, foreign claim owner, stale-first CHANGELOG, or bundle bytes different from the reviewed commit. | issue #724; independent audit | `check_versions.ps1` and `release-identity.ps1` require exact newest release identity. `claim.ps1` uses the machine-global authority and multi-process race fixtures. `ship.ps1` enforces BuildOnly before commit/review, then requires clean live default HEAD. The publisher independently re-queries exact default HEAD, merged PR, and hosted `qa-gate`; VMBLauncher requires a five-minute root/commit/mod/version/owner/cfg/bundle capability and repeats live Git/GitHub/hash checks immediately before `ugc_tool`. Offline fixtures reject forged JSON, dirty/premerge publication, stale/foreign claims, failed QA, and changed/extra bundle blobs. | AUTO (blocking QA + ship/launcher adversarial self-tests) |
| 61c | Active documentation teaches direct launcher `all`/`upload`, post-upload commit/push, or restarting Steam after every upload; default launcher publish verification opens GUI/Explorer or performs incidental build/deploy actions. | issue #1025; user-observed VMBLauncher popup 2026-07-27 | `check_publication_doctrine.ps1` scans active docs while excluding changelogs, postmortems, status, investigations, audits, and archives. It requires the noninteractive merge-first owner tokens and rejects the three stale advice classes. `-SelfTest` plants direct-all, post-upload-commit, and restart failures. The launcher repository independently splits default headless/read-only smoke from explicit `-Interactive` / `-IntegrationActions` suites and guards that split. | AUTO (blocking Quick/full QA + self-tests) |
| 61d | A manifest/display mod ID contains uppercase characters (WOC), so the PowerShell publisher emits a hosted receipt coordinate accepted by its case-insensitive regex but rejected by VMBLauncher's case-sensitive security gate before `ugc_tool`. | issue #1049; WOC v0.1.48-dev publication refusal | `Get-WorkshopPublicationReceiptAssetName` accepts only the canonical lowercase source-folder slug; `publish-release.ps1` no longer derives receipt names from manifest `mod_id`; and PowerShell receipt validation uses the same case-sensitive regex as VMB. `check_publication_receipt.ps1 -SelfTest` plants the WOC/folder mismatch, rejects uppercase input, and pins the producer to `receiptInput.Folder`. | AUTO (offline receipt self-test, full QA) |
| 61e | A QA/check command silently edits source, index state, or an existing untracked file, invalidating clean-clone evidence or clobbering a developer's dirty worktree while still reporting success (#546). | `PROJECT_STANDARDS.md` §2.2b + issue #546 | `worktree_state.ps1` fingerprints status, separate binary index and unstaged diffs, and the names/content hashes of all non-ignored untracked files. Normal Quick/full `run_all.ps1` compares exact pre/post state and blocks on mutation; it does not require the initial tree to be clean. `-FixStale` is the sole explicit orchestration write mode and visibly skips the comparison. The `run_all -SelfTest` fixture proves clean equality, untracked-name/content detection, index-only and tracked-worktree mutation detection, restoration, and PS5/PS7 compatibility. | AUTO (blocking Quick/full run_all + CI) |
| 61f | A fix remains in a split mod's dev stream while a stable ship proceeds without exposing the debt, as happened for #278 and remained possible for non-critical #139. | issue #1160 + `docs/PROMOTION_PROCESS.md` | `promotion-status.ps1` compares normalized source and dev/public changelog provenance, then emits one loud per-pair STRANDED-FIX REVIEW with exact dev/public versions and every dev-header issue reference absent from stable. Crash/critical references remain the `-Strict` subset. `ship.ps1` invokes the report for every split-stream target before build/deploy/upload and fails if the report cannot run; backlog stays advisory and never auto-promotes. Offline self-tests plant a non-critical stranded fix, a promoted body citation, and a missing critical fix. | AUTO (every canonical split ship + run_selftests) |
| 61g | A second VMB/Stingray/settings/release/upload transaction starts while the first parent or descendant still mutates; hard death strands SDK DENY ACLs or an ordinary success leaves child/grandchild residue. | issue #1180; `BUG_CLASSES.md` class 86 | VMBLauncher 0.6.0 and PowerShell wrappers share `Global\Ensrick.VMBLauncher.Transaction.v1`, a durable PID/start/session/mod/root owner record, and a named kill-on-close process Job. Abandoned recovery polls `JobObjectBasicAccountingInformation.ActiveProcesses`, closes every temporary query handle immediately, and accepts only zero or an absent exact Job; it never waits for unsupported ordinary Job signalling. Ordinary release authenticates and drains residue before unlock. ACL recovery is exact journal/identity/descriptor based. Capability gates reject 0.5.9 before release mutation. Fake-process tests cover an ordinarily emptied still-open Job, prequeued contenders, hard/normal residue, GUI settings two-process lost updates, canonical shell breakaway, PS7/PS5.1 hosts, and legacy ACL repair without real VMB/Steam/Workshop actions. | AUTO (launcher xUnit + transaction host matrix + ship/publication self-tests) |
| 61h | BuildOnly compiles one dirty source snapshot, then a later edit is staged beside older opaque output; root-only atomicity cannot prove either the compiler inputs or every emitted file correspond (#1278/#1400). | issues #1278/#1400 | `ship.ps1` fingerprints exact raw bytes plus Git-clean blobs for every regular compiler input before/after the clean build, rejects unreproducible raw/filter drift, normalizes only handle-locked inventoried sidecars, and writes deterministic schema 3. Clean-filter materialization uses an isolated temporary Git object store with no real-store alternate, so read-only provenance cannot add or freshen repository objects. The receipt binds the source map to the complete canonical output map (names, lengths, hashes, root, source-qualified descriptor, builder/version, aggregate and policy fingerprints). Working, staged, committed, BuildOnly, and final-ship paths share the validator; untouched schema 2 remains compatible and all inventory rows stay explicitly tracked. The 23-fixture suite retains #1278's ignored/hidden, EOL/filter, `.gitattributes`, type-change, first-upload, during-build, and post-BuildOnly cases while adding exact output/policy/type/object-store adversaries. | AUTO (blocking BuildOnly + pre-commit + Quick/full QA + dual-host self-tests) |
| 61i | Build, receipt, release, and reproducibility phases independently classify `bundleV2`, so an extra/wrong descriptor, same-name replacement, normalization race, or staging alias can pass one boundary and enter another (#1400). | issue #1400 | `bundle-output-set.ps1` is the single ordinal complete-output authority. It rejects nested/reparse/case-colliding/noncanonical entries, binds stable file identity while hashing, verifies a second snapshot, and source-qualifies the descriptor. Normalization deletes an approved name+SHA only through its locked handle. Schema-3 receipts, release manifests, immutable commit-byte ZIP construction, and reproducibility consume that contract; mutable staging can fail a release but cannot select hosted bytes. `run_bundle_output_set_host_matrix.ps1` executes output-set, normalization, and receipt adversaries under PS7 and PS5.1 as a blocking full-QA gate. | AUTO (blocking full QA + dual-host fixtures) |
| 61j | A generated-output storage migration untracks only part of `bundleV2`, leaves tracked output beside a receipt, accepts a stale/forged schema, or silently enables an unreviewed publisher/updater path (#1412). | issue #1412 + `docs/BUNDLE_AUTHORITY.md` | `bundle-authority.ps1` owns exact `tracked`/`receipt` modes, the per-mod scoped ignore rule, bidirectional transition proof, and typed downstream policy. `check_bundle_authority.ps1` requires schema 3, zero tracked outputs in receipt mode, exact root/descriptor/source/policy/builder proof, materialized-build equality, and an atomic all-and-only output-map transition. Atomicity delegates typed transitions to this contract. Phase D enables only `Publish`; deploy/update/recover stay false. All active rows remain tracked. Dual-host adversaries cover unsupported/missing modes, schema/receipt failure, leftovers, partial/extra/split changes, ignore drift, wrong content, case collisions, and non-exact restoration. | AUTO (blocking Quick/full QA + dual-host fixtures) |
| 61k | Receipt authority proves output identities but has no immutable byte source, while the tracked publisher independently reconstructs the same output map; a later storage migration could reread mutable paths, alias returned buffers, or accidentally turn byte availability into publish authority (#1422). | issue #1422 + issues #558/#1400/#1412 | `Get-VtPublicationSnapshot` owns one commit-qualified output and byte shape. Tracked mode preserves exact Git blobs. Receipt mode requires committed schema 3, inventory, ignore state, source map, root, descriptor, policy, builder, zero tracked outputs, and a matching materialized set whose bytes and file/directory identities stay locked through a second snapshot. Returned arrays are detached. The snapshot grants no consumer authority by itself. `check_publication_snapshot.ps1` and the output-set fixtures run under PS7 and PS5.1. | AUTO (blocking full QA + dual-host fixtures) |
| 61l | Receipt bytes are provable but canonical ship, GitHub release, hosted receipt, and VMBLauncher staging disagree on authority, so removing tracked bundles either blocks every release or tempts a mutable-path/upload bypass (#1426). | issue #1426 + #558 phases A-C | Receipt authority is publication-only and requires `receipt-authority-publication-v1`. Tracked publishing preserves pre-build Git-blob selection. Receipt publishing clean-builds and normalizes before capture, binds the committed schema-3 receipt/source/output/policy/builder proof into the hosted receipt, and makes VMBLauncher independently reconstruct that proof before exact locked-staging comparison. Receipt bootstrap, deploy, updater/recovery consumption remain disabled; no active row migrates in this phase. Capability, receipt, authority, snapshot, staging-set, tamper, and ordering fixtures fail closed under both PowerShell hosts and launcher xUnit. | AUTO (blocking full QA + launcher tests + dual-host fixtures) |
| 61m | The latest release is mutable and older installs have no durable source-exact publication coordinate, so an updater cannot safely distinguish a stale/mixed install or recover the exact historical bytes that produced it (#1430). | issue #1430 + #558 phase E | The publisher adds a strict schema-1 `recovery` child only from one immutable publication snapshot plus its exact committed schema-3 receipt. It binds mod/Workshop/version, repo/tag/asset bytes, clean source/item/inventory/ignore proof, builder, authority/root/descriptor, complete output map/fingerprint, and receipt/normalization proof. Missing/schema-2 tracked receipts remain explicit legacy; receipt authority fails closed. No resolver, download, replacement, deployment, row flip, or updater consumer is enabled. `check_release_recovery_record.ps1` creates a temporary Git fixture and plants working-tree replacement, missing/schema-2 receipt, identity/coordinate, malformed length, unknown field, output-map/order/blob/fingerprint, receipt/policy, and authority adversaries under both hosts. | AUTO (blocking full QA + dual-host fixture) |
| 61n | A hand-written immutable-review digest uses culture-sensitive `Sort-Object` while claiming ordinal ordering, so unchanged candidate bytes receive conflicting evidence identities (#1435; repeated in #1429/#1430). | `tools/review/README.md` + PROJECT_STANDARDS §5.3a | `content-manifest.ps1` binds an explicit root/base/bounded path set into one ordinal, strict UTF-8-no-BOM/LF manifest with present/deleted rows, percent-encoded normalized paths, raw length/SHA-256, and a base-bound aggregate. It rejects duplicate/case-colliding/out-of-root/reparse/unbounded inputs before hashing. `check_content_manifest.ps1` exercises en-US/tr-TR/invariant cultures, an ordinal-vs-culture fixture, every digest axis, hostile inputs, PS5.1/PS7, and hermetic frozen byte archives for the real #1429/#1430 reviewer sets. | AUTO (blocking Quick/full QA + hosted CI) |

### Logging hygiene (chat-echo / per-frame / warn-chat)

`check_logging.ps1` encodes PROJECT_STANDARDS § 3.6 (Debug logging + "Chat-echo
policy" matrix) and `docs/BUG_CLASSES.md § 17` (chat-echo spam + Variant B). Three
advisory sub-checks in one full-repo scan (mirrors `check_unpack_safety.ps1`'s
comment/string-blanking + block-depth model). It uses **Standard** policy in
`run_all`: existing census findings exit 1 and remain non-blocking, while a
scanner failure or new #427 warn-chat regression exits 2. Each category has a
false-positive-safe escape.

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 58a | `mod:echo` in a § 3.6 "NEVER" context — a module-load banner (not the MOD_VERSION dev banner), an `on_setting_changed`/`on_enabled`/`on_disabled` lifecycle body, or a hook-callback body — i.e. the sites BUG_CLASSES § 17 says to audit against the chat-echo matrix. Echoes in ordinary functions and `mod:command`/keybind handler bodies are NOT flagged (a static tool can't trace a reply routed through a private helper without a call graph — favor precision). | PROJECT_STANDARDS § 3.6 "Chat-echo policy" + `docs/BUG_CLASSES.md § 17` | `check_logging.ps1` category **echo**. Escape a legit § 3.6-OK-row site (high-impact toggle, `on_disabled` limitation notice, ct's "Granted N boons" hook reply) with an inline `-- allow-echo: <reason>`. | AUTO (script, advisory) |
| 58b | `mod:info`/`mod:warning` inside a per-frame callback (`function update`, `mod.update`, `X.update`/`X:update`, inline `mod:hook*(..., "update", …)`) — logs every frame, floods the console + costs a `string.format` per tick. | PROJECT_STANDARDS § 3.6 + `docs/VMF_RECIPES.md § 2b` (traced_hook per-frame caveat) | `check_logging.ps1` category **per-frame**. Escape an intentional throttled/one-shot site with `-- allow-perframe: <reason>`. | AUTO (script, advisory) |
| 58c | `mod:warning` inside a dbg/alert HELPER (`_dbg_alert`, `_spawn_dbg_alert`, a `dbg`/`alert`-named helper — not a `chat`-named one). The **Issue #240** class: `mod:warning` is believed log-only but VMF `logging.lua` defaults `warning` to mode 3 (`send_to_chat = mode >= 2`), so a "log-only alert" helper spams chat. Sanctioned form is pcall-guarded raw `printf` (et v0.7.25-dev). Genuine failure-path `mod:warning` (ordinary guards, `_safe`) is NOT flagged. | `reference_vmf_warning_channel_posts_to_chat.md` + `docs/BUG_CLASSES.md § 17 Variant B` (#240) | `check_logging.ps1` category **warn-chat**. Escape an intentional in-helper chat warning with `-- allow-warn-chat: <reason>`. | AUTO (script, advisory) |
| 58d | A new warning-backed diagnostic helper recreates #427 while the wider logging-hygiene backlog is still being reduced. | #427 + closed #240 | `check_logging.ps1` exact-fingerprints the three remaining stable-stream debts before returning its advisory census. Removing any is accepted; a new path or changed/additional site exits 2. `-WarnChatRegression` provides a zero/2 issue-specific invocation. Self-test proves known/removal/new-path/new-text verdicts. | AUTO (blocking error path in the Standard `run_all` check) |

### Regression-check source-text invariants (tier a, issue #511 / #516)

`check_rt_textual_invariants.ps1` is the tier-(a) home (PROJECT_STANDARDS § 2.2b)
for the SOURCE-TEXT invariants that issue #511 removed from the in-game
`/<mod>_regression_test` suites. Those checks read the mod's own source via
`io.open` and grepped for a marker; the retail Stingray VM registers no `io`
library (mods are `loadstring`'d into the shared `_G`, `mod_manager.lua:375`), so
each threw `attempt to index global 'io'` and FALSE-FAILED on healthy code. The
runtime half of each check became a load-time marker; the genuinely textual half
(a literal that must be PRESENT, or a forbidden pattern that must be ABSENT) moved
here.

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 59 | A `/<mod>_regression_test` source-pattern invariant (a fix's marker literal, or an absence guard like "no bare `:local_player()` in `_gt_debug_highlights.lua`") that in-game markers cannot capture, silently reworded or removed as the mod evolves. Issue #511 stripped these from the Lua suites (retail has no `io`); without a repo gate they had no home. | issue #511 (root cause) + PROJECT_STANDARDS § 2.2b tier (a) + the per-mod CHANGELOG #511 entries | `check_rt_textual_invariants.ps1` — scans a per-entry NEEDLE MANIFEST (`qa/rt_textual_invariants.psd1`): each row names the mod, the repo-relative file, a needle (literal or regex), polarity (`present`/`absent`), an `issueRef`, and a note; `present` supports `minCount`/`maxCount` (e.g. ct #145 wired at both graph branches = minCount 2; WOC #422 wire-safety hook is a singleton = min/max 1). Absence needles are first-class (the two gt dh guards use a comment-excluding regex `(?!\s*--)` because the file documents the invariant in a comment). A MISSING FILE is a FAIL (the invariant moved — update the manifest). Hard-fail (exit 2) on any FAIL; Standard policy in `run_all` (full pass). Runs in a few seconds (literal `String.IndexOf` / one `[regex]::Matches` per entry). Self-test: `-SelfTest` (synthetic fixtures — present pass, minCount, comment-excluding absence, naive-absence fail, missing-file fail). Current manifest: 72 needles across gt_dev (36), ct_dev (7), gut_dev (13), cim_dev (3), WOC (3), and dcp (6), plus four other-mod entries; #575 adds four metric/wiring guards. | AUTO (script, in run_all) |

## Coverage summary

| Category | AUTO | PRE-SHIP | MANUAL | DEFERRED | HANDED OFF | FIXED |
|---|---|---|---|---|---|---|
| Lua static | 13 | 1 | — | — | — | — |
| cfg/Workshop | 8 | — | 2 | — | — | — |
| Localization | 10 | — | — | 1 | — | — |
| Hooks / vanilla-API | — | 6 | — | — | — | — |
| Network / multiplayer | — | 5 | 1 | 1 | — | — |
| Vanilla-API drift | — | 3 | — | — | — | 3 |
| Cosmetics-specific | — | 3 | — | — | 6 | — |
| Docs hygiene | 6 | 1 | — | — | — | — |
| Process | 1 | 1 | 3 | — | — | 1 |
| **TOTAL** | **38** | **20** | **6** | **2** | **6** | **4** |

**50% of documented bug classes are now automatable (38/76).** Another 26%
covered by pre-ship review pattern. Remaining are architectural,
intentionally manual, or handed off.

## Current luacheck baseline

As of 2026-05-23, after initial config tuning:

- **Total warnings**: 415 (down from 1951 baseline before config tuning)
- **CWV bare globals (audit finding)**: 141 warnings — real cleanup work
  tracked in PROJECT_STANDARDS §11 #9
- **Net non-CWV warnings**: 274 — distributed across unused locals (W211),
  shadowing (W431/W621/W421/W422), nil-init (W231), unreachable code (W511),
  and a few remaining undefined globals (SDK reference materials in
  `enemy_tweaker/.spawn_tweaks_ref/` aren't part of active mods)

**Goal**: drive non-CWV warnings below 100 over the next several sessions.
As of issue #429, luacheck runs through `run_all.ps1` pinned **Advisory** in
both CI and local (the policy-engine replacement for the old CI `|| true`) —
flip it to Standard once CWV bare globals are refactored and the baseline is
clean.

## Copied shared-library drift (issue #428)

`check_shared_lib_drift.ps1` is a blocking exact-byte gate over
`tools/shared_lib/manifest.psd1`. It rejects missing or locally edited per-mod
`_lib_*.lua` copies, including line-ending-only drift. Repair declared copies
with `tools/shared_lib/sync-shared-libs.ps1 -Apply`; consumers remain bundled
and standalone at runtime.

Exact-byte comparison only sees what the manifest names, so the gate also runs
a two-way census (issue #1159): every `_lib_*.lua` in a mod tree must be a
declared consumer, and every `_lib_*.lua` in `tools/shared_lib` must be a
declared `Source`. An undeclared copy fails on absence from the manifest, not
on difference from canonical - it could sit identical today and fork silently
tomorrow with no gate watching. Build output (`bundleV2`), archives, and hidden
tool-owned checkouts are excluded, and the self-test pairs each planted census
failure with an excluded-path run that must stay green. A tools-only canonical
library (`_lib_appearance_name_authority.lua`, read by
`check_appearance_contracts.ps1`) declares `Consumers = @()`.

`check_wt_stream_parity.ps1` is the blocking contract gate for the active
`weapon_tweaker` public-beta and `weapon_tweaker_dev` friends-only streams. It
exact-compares every common runtime file after removing only uniquely paired,
self-tested stream-overlay blocks, allowlists the four dev-only tuning/probe
modules, and independently rejects dev files, widgets, commands, and issue-specific
live probes from the public beta. Player-facing lifecycle tags are forbidden in
both streams by `check_loc_tags.ps1`. It also
checks public setting/localization ownership, allowlists the public read-only
support commands, pins both Workshop IDs/visibilities, and requires dev to be
one patch ahead. Preview images, changelogs, generated bundles, and Workshop
metadata remain independent presentation/history surfaces.

`check_wt_history_reproducibility.ps1` is the blocking full-QA provenance gate
for issue #1436's Patch 5.2 selector slice. It pins the generator, source
catalog, nine evidence artifacts, and generated public catalog. When the
complete decompiled source checkout exists, it additionally regenerates to a
temporary file and requires byte-exact equality. The central selector first
proves every required commit, `commit:path`, and blob through read-only Git
queries; missing, stale, or partial source keeps the pinned ledger active and
emits a visible regeneration skip, while `-RequireSource` fails closed.

`check_wt_history_patch_3_1_reproducibility.ps1` pins the exact five-file
evidence census and four-artifact ledger for the bounded Blunderbuss and
Tuskgor Spear slices. It proves the adjacent `max_ammo` change from `12` to
`16` and block-cost change from `0.25` to `0.5`, rehydrates both exact current
guards, excludes the current-only Versus template, independently reproduces
both evaluator lanes, and regenerates byte-identical public/dev
catalogs. It also pins the byte-identical machine-readable completeness ledger:
8 catalogs, 21 unique families, 32 family/state rows, 10 distinct states, and
201 scalar operations, with every exposed row classified as an adjacent delta
or complete direct historical baseline. The blocking
`run_wt_history_patch_3_1_host_matrix.ps1` repeats the gate and source-selection
adversaries under PowerShell 7 and Windows PowerShell 5.1.

`check_wt_history_patch_3_2_reproducibility.ps1` pins the exact three-file
evidence census and two-artifact ledger for Kerillian's One-Handed Axe. It
requires the single adjacent `0.1` critical-chance operation, rehydrates that
path to an absent current guard, and independently reproduces both evidence
lanes plus byte-identical public/dev catalogs. Its oracle self-test also proves
that fallback-global mutable proxies remain isolated between immutable source
revisions. The blocking `run_wt_history_patch_3_2_host_matrix.ps1` repeats this
contract and the source-selection adversaries under PowerShell 7 and Windows
PowerShell 5.1.

`check_wt_history_patch_4_1_1_reproducibility.ps1` pins the exact three-file
evidence census and two-artifact ledger for the Patch 4.1.1 Masterwork Pistol
slice. It proves the three historical/post/current commit-path-blob rows,
requires byte-exact primary evidence and catalog generation, exact semantic
agreement from the independent oracle, current-anchor rehydration, and
byte-identical public/dev catalogs. Both evaluators run independent 3-by-3
true/false/absent presence self-tests before optional source discovery, so
source-less CI still exercises the boolean contract. The blocking
`run_wt_history_patch_4_1_1_host_matrix.ps1` repeats the gate and both source
selection adversaries under PowerShell 7 and Windows PowerShell 5.1.

`check_wt_history_patch_4_6_reproducibility.ps1` pins the bounded Hagbane-only
slice: six immutable source files and all 18 exact revision/path/blob inputs,
seven evidence artifacts, the independent two-route oracle, and byte-identical
public/dev catalogs. All post-selection Git reads disable lazy fetch and
optional locks. Both evaluator lanes
reproduce the historical, post-boundary, and current profile payloads. The gate
requires exactly the two `allow_dot_finesse_hit` additions, retains the
Ricochet `aoe_on_bounce`, presentation-only `weapon_diagram`, and refactor
symbol as explicit exclusions, and proves the generated private profiles
preserve the current schema.
`run_wt_history_patch_4_6_host_matrix.ps1` repeats that patch-specific gate
under PowerShell 7 and Windows PowerShell 5.1. The real-source gate also rejects an otherwise complete ledger with the
current Woods profile blob identity altered, while the no-lazy-fetch guard
prevents an absent object from being fetched after source selection.
Ordinary source-less CI reports pinned-only validation; the documented
`-SourceRepo ... -RequireSource` invocation is the strict dual-host release
proof and rejects any source-regeneration skip.

`check_wt_history_patch_6_0_reproducibility.ps1` pins the bounded Patch 6.0
two-shield scalar and Fireball profile slice. Its source-unavailable messages
share the same visible-skip/required-failure contract as the other six gates,
so the incomplete-checkout adversary now covers every supported slice.

`check_wt_history_source_freshness.ps1` consumes the one weapon-history anchor
manifest and reads only the canonical remote's symbolic HEAD with bounded,
noninteractive `git ls-remote`. Ordinary QA accepts genuine network
unavailability as a visible skip while retaining every pinned offline gate; a
reachable lagged, moved, malformed, or ambiguous remote is blocking. Canonical
WT public/dev BuildOnly and release runs require remote freshness, so an
unavailable remote also blocks there. Offline adversarial fixtures cover exact
tip, lag, default-branch movement, malformed/ambiguous output, timeout, and the
optional-versus-required unavailability split under both PowerShell hosts. The
1--60 second total budget includes bounded tree-termination proof: PS7 uses
`Process.Kill(true)`, while PS5.1 uses trusted system `taskkill.exe /T /F` with
captured status plus bounded helper containment. Nonzero, timed-out, or
unproven termination returns immediately as unavailable. Real nested
parent/descendant and taskkill failure/timeout fixtures prove the policy split,
cleanup, and no root, descendant, or helper orphan. One
monotonic stopwatch allocates smooth, positive network/action/proof phases and
charges process startup plus every output/process wait to absolute deadlines.
At 3 seconds those phases are 750/1687/563 ms; the 15-second production default
is 11000/3000/1000 ms, and the 60-second maximum is 56000/3000/1000 ms. The
final proof phase is conditional: a timed-out helper uses it for containment,
while a successful taskkill reserves it for root proof. An early successful
taskkill may donate unused action time forward, but no phase moves the total
deadline. Exhaustive allocator, root-exit output, expired-deadline, 1-second
fail-closed, and delayed-real-taskkill fixtures pin the contract. Injected
elapsed-time and wait/kill observers prove the exact programmed waits at every
phase boundary, including a host resume at 5763 ms: later waits are zero, the
hung helper is contained once, root proof is skipped, and output fails closed.
Raw scheduler and synchronous OS-call latency is diagnostic rather than a hard
real-time correctness assertion. One real PS5.1 hanging-helper case retains
exact PID/start-time cleanup and orphan detection.

`check_wt_history_source_checkout.ps1` is the offline source-selection
adversary. Under both PowerShell hosts it presents all eight reproduction gates
for Patch 3.1, 3.2, 4.1.1, 4.6, 5.2, 6.0, 6.6, and 6.8,
with an intentionally incomplete Git checkout, requires an ordinary visible
skip and a `-RequireSource` failure from each, and restores its environment
without fetch (including promisor lazy-fetch), network access, checkout
mutation, or deletion.

`run_wt_history_source_host_matrix.ps1` is the one blocking full-QA owner for
both generic self-tests. It runs each once under PowerShell 7 and Windows
PowerShell 5.1; `run_selftests.ps1` honors their `SELFTEST-OWNER` declarations,
and a static fixture rejects duplicated shared-matrix wiring or any generic
source guard reintroduced into a patch-specific host matrix.

`run_wt_history_patch_6_6_host_matrix.ps1` is the blocking dual-host gate for
the Patch 6.6 Deepwood Staff slice. Under both PowerShell 7 and Windows
PowerShell 5.1 it runs the pinned-artifact gate, regenerates the adjacent
6.5.4-to-6.6.0 evidence and current-anchor guards when source is available,
requires independent-oracle agreement, and regenerates the byte-exact public
and dev catalogs. Its three-operation transaction covers both staff templates
and the server-owned spirit-storm vortex leaf; the runtime refuses the
historical state on a client.

`check_wt_history_patch_6_8_reproducibility.ps1` is the corresponding blocking
gate for the Patch 6.8 Kerillian Greatsword slice. It selects the operation from
the exact adjacent 6.7.2-to-6.8.1 diff, rehydrates only that selected path
against the current 6.12.0 content anchor, and requires byte-exact primary evidence,
exact-double agreement with the independent source oracle, byte-exact public
and dev catalogs, and byte-exact catalog regeneration. Source-less CI retains
the complete pinned-artifact gate and reports the regeneration skip.

## Current state of each check

| Check | Last run | Notes |
|---|---|---|
| `check_cfg.ps1` | ✅ OK | all 20 cfgs pass |
| `check_versions.ps1` | ✅ title/release identity blocking; semver debt advisory | cfg title drift is blocking after the failed-closed WT 0.12.292-beta publication; description triplet debt and 4-segment MOD_VERSIONs retain their documented ratchets (row 10a). |
| `check_unpack_safety.ps1` | ✅ OK | all sites in ct/mp/wt either explicit-j or annotated (post-Issue #36 audit) |
| `check_vmf_widget_types.ps1` | ✅ OK | all 23 active `*_data.lua` clean post-gt v0.2.60-dev `text_input` fix (2026-05-25) |
| `check_event_register_signature.ps1` | ✅ OK | clean post-gt v0.2.61 → .64 fix cycle (2026-05-25). This static check is the live gate; the former `bt:safe_event_register` runtime safety net (buff_tweaker v0.1.10-alpha+) is RETIRED (bt archived 2026-06). |
| `check_wt_history_reproducibility.ps1` | ✅ OK (2026-08-28) | Issue #1436 full-QA gate for the pinned Patch 5.2 evidence ledger and byte-exact generated catalog; exact regeneration runs only from a checkout whose complete pinned commit/path/blob ledger passes the read-only selector. |
| `run_wt_history_patch_3_1_host_matrix.ps1` | ✅ OK (2026-08-30) | Issue #1436 blocking dual-host gate for the exact bounded Patch 3.1 Blunderbuss maximum-ammunition and Tuskgor Spear block-cost boundaries, current-only Versus exclusion, independent-oracle agreement, byte-exact public/dev catalogs, and fail-closed completeness ledger. |
| `run_wt_history_patch_3_2_host_matrix.ps1` | ✅ OK (2026-08-29) | Issue #1436 blocking dual-host gate for the exact Patch 3.2 Kerillian One-Handed Axe boundary, absent current guard, revision-isolated older source evaluator, independent-oracle agreement, and byte-exact public/dev catalogs. |
| `run_wt_history_patch_4_1_1_host_matrix.ps1` | ✅ OK (2026-08-29) | Issue #1436 blocking dual-host gate for the exact Patch 4.1.1 Masterwork Pistol boundary, present-false current guard, independent 3-by-3 evaluator presence tests, current rehydration, two-artifact/three-file evidence contract, and byte-exact public/dev catalogs. |
| `check_wt_history_patch_4_6_reproducibility.ps1` | ✅ OK (2026-08-29) | Issue #1436 source-exact Hagbane-only Patch 4.6 gate: two finesse-DoT profile leaves, two current routes, current-schema private rehydration, Ricochet/weapon-diagram/refactor exclusions, primary/oracle agreement, and byte-exact public/dev catalogs. |
| `run_wt_history_patch_4_6_host_matrix.ps1` | ✅ OK (2026-08-29) | Issue #1436 blocking dual-host validator for the complete six-file/18-object Patch 4.6 source closure, one-DLC-blob-identity adversary, no-fetch/no-lock extraction and exact raw-environment restoration; strict `-RequireSource` performs and requires both regenerations, while source-less CI is explicitly pinned-only. |
| `check_wt_history_patch_6_0_reproducibility.ps1` | ✅ OK (2026-08-29) | Issue #1436 full-QA gate for the bounded Patch 6.0 shield-scalar and Fireball-profile slice; exact primary/oracle reproduction and catalog generation pass from the complete pinned source checkout. |
| `check_wt_history_source_freshness.ps1` | ✅ OK (2026-08-30) | Issues #1436/#540 central 6.12.0 semantic anchor plus separately observed canonical default tip; ordinary offline QA may visibly skip only unavailable network, while WT BuildOnly/release requires exact remote ref/tip freshness without fetch/FETCH_HEAD mutation. Injected 750/1687/563 ms deadline traces prove every programmed wait, including the 5763 ms resume adversary; scheduler/OS latency is diagnostic, and one real PS5.1 hanging-helper case retains exact cleanup proof. |
| `check_wt_history_source_checkout.ps1` | ✅ OK (2026-08-30) | Offline PS7/PS5.1 adversary proves that stale/partial Git trees visibly skip ordinary regeneration and fail closed under `-RequireSource` for the Patch 3.1, 3.2, 4.1.1, 4.6, 5.2, 6.0, 6.6, and 6.8 gates. |
| `run_wt_history_source_host_matrix.ps1` | ✅ OK (2026-08-30) | Issue #540 blocking dual-host owner for the generic freshness and incomplete-checkout self-tests. Full QA invokes it exactly once; static coverage forbids patch-specific matrices and `run_selftests.ps1` from multiplying the same process fixtures. |
| `run_wt_history_patch_6_6_host_matrix.ps1` | ✅ OK (2026-08-28) | Issue #1436 blocking dual-host gate for the exact Patch 6.6 Deepwood Staff adjacent boundary, 6.12.0 current guards, independent-oracle agreement, and byte-exact public/dev catalogs. |
| `check_wt_history_patch_6_8_reproducibility.ps1` | ✅ OK (2026-08-28) | Issue #1436 full-QA gate for the source-adjacent Patch 6.8 Kerillian Greatsword boundary, current-anchor rehydration, independent oracle agreement, and byte-exact generated catalogs. |
| `check_localization.ps1` | ⚠ 28 warnings | ct BOON_TREE category_ids; et_diff_ + mut_ false-positive prefixes |
| `check_loc_tags.ps1` | ✅ OK (#694 migration) | Blocking scan covers every active stream, dynamic `en` construction, and obsolete decoration helpers; migration mode verifies key/order/count and value semantics against the merge base. |
| `check_issue_status_labels.ps1` | ⚠ 1 warning (2026-07-04) | Post label-audit: only #322 (a `tracked-not-fixed` context-mention in ct's #294 crash-fix entry — correctly unlabeled; the check surfaces it for review). All other latest-entry refs are labeled or in skipped loc-sweep entries. Self-test passes. Advisory (never blocks; self-exits 0 offline). |
| `run_selftests.ps1` | ✅ OK (2026-08-30) | Unit-test entry point: auto-discovers every ordinary `qa/check_*.ps1` with a `[switch]$SelfTest` param plus explicit tools, while checks with a `SELFTEST-OWNER` declaration run only through their dedicated dual-host wrapper. It replays output on failure and exits 2 on any regression, so a broken check blocks full QA. Rows 60g and the #540 weapon-history source guards have dedicated blocking PS7/PS5.1 wrappers. |
| `run_vmb_launcher_path_host_matrix.ps1` | ✅ OK (2026-07-17) | Issue #683 dual-host gate: invokes `check_vmb_launcher_path.ps1 -SelfTest` in both PowerShell 7 and Windows PowerShell 5.1, fails closed when either host is unavailable or either contract fails, and is an explicit Blocking full-run `Run-Check`. |
| `run_bundle_output_set_host_matrix.ps1` | ✅ OK (2026-08-26) | Issues #1400/#1412/#1422/#1426/#1430 dual-host gate: runs the shared output-set, exact tracked/receipt authority, handle-locked normalization, schema-3 receipt, immutable snapshot, receipt-publication, and durable recovery-record adversarial suites under PowerShell 7 and Windows PowerShell 5.1; full `run_all.ps1` treats either host's failure as blocking. |
| `check_lua_unit_tests.ps1` | ✅ OK (2026-07-13) | Offline host-unit tier (issue #544): vendored Lua 5.1.5, dependency-free harness, and 3 initial production-helper tests for Bestiary & Armory attack-chain classification/sorting/label normalization. Runs in Quick + full QA. `-SelfTest` proves the harness pass path and planted-failure detection and is auto-discovered by `run_selftests.ps1`. Tier boundary and binary provenance live in `qa/lua/README.md`. |
| `check_lua_parse.ps1` | ✅ OK (2026-08-13) | Blocking structural syntax tier (issue #1223): SHA-256-pinned vendored Luacheck parses every active-mod Lua source by exact path in bounded 40-file batches, including Windows-hidden inputs. It runs in Quick/full QA even when `-SkipLua` suppresses advisory analysis. The dual-host self-test proves authored `goto`, ignored semantic warnings, 41-file batching, a late hidden syntax failure, infrastructure-vs-source exits, and empty-inventory rejection. This is malformed-source detection, not exact VT2 runtime-dialect validation. |
| `check_dofile_package_coverage.ps1` | ✅ OK (2026-07-14) | Blocking Quick gate added after WOC #595: every literal active-mod `mod:dofile` target exists as `.lua` source and is covered by the owning `.package` Lua list, exactly or by wildcard. Prevents source-only helpers from becoming Workshop `Resource not found` startup crashes. |
| `check_diagnostic_ownership.ps1` | ✅ OK (2026-08-23) | Issue #499 blocking Quick/full gate over the checked-in shrinking registry. Rejects an unknown `*probe*`/`_diag_*` production root, missing issue/stream/prefix/load-owner/arming/bound metadata, new standalone probe names beyond the two exact GT standing owners, and unreviewed issue diagnostics in public streams. PS7/PS5.1 offline fixtures cover unknown probe, unregistered diagnostic, closed mocked issue, stable issue diagnostic, missing metadata, the #1309-style alias, and standing owners. The hosted lifecycle guard separately validates active rows against its already-fetched open issues. |
| `check_dcp_portrait_atlas.ps1` | ✅ OK (2026-07-21) | Blocking Quick/full issue #526 gate: the 24 HUD/small atlas sprites must be pixel-exact copies of their source PNGs, descriptor UV spans must match, and every 86x108 HUD alpha channel must exactly equal the canonical vanilla silhouette. Prevents stale atlas output, GDI+ edge-color rewriting, and mask drift before VMB. |
| `check_branch_reconciliation_census.ps1` | ✅ OK (2026-07-17) | Offline issue #625 gate: validates the committed branch census schema, <=14-day freshness, current generator hash, unique tip/ref ownership, summary parity, and exact ancestry/patch-equivalence proofs without assuming CI has the maintainer's local refs. PS7 and PS5.1 self-tests cover valid, semantic-auto-classification, stale, duplicate-ref, and generator-drift fixtures. |
| `check_pipeline_state.ps1` | ⚠ ladder gaps (2026-07-18, first run) | Row 61. Advisory pipeline-state ladder (always exits 0). First live run on a busy multi-agent working tree: 16/21 mods off IN-SYNC (mostly `UPLOAD-BEHIND`/`BUNDLE-STALE` from local edits+builds not yet shipped), 5 IN-SYNC, 4 `[not deployed]` markers (enemy_tweaker, event_tweaker, vdl, vdl_dev). Public items behind: weapon_tweaker (3 rungs), chaos_wastes_tweaker, general_tweaker, crafting_in_modded, verminious_dreams_lighting. Hand-verified against raw mtimes+log for wt/ct/cwv. Self-test 3-family verdict + parser fixtures pass. |
| `check_name_integrity.ps1` | ⚠ baselined (issue #429) | 7 semantic errors remain frozen in `qa/baselines/name_integrity.json`. The blocking ratchet always uses the committed vanilla oracle plus the no-VtSrc view, even when a maintainer has the optional source checkout; diagnostics still use the richer source inventory. Check-2 keys are path-insensitive, so module extraction does not look like a new localization defect. Self-test covers planted missing keys, source-file moves, and the offline menu-key oracle. |
| `check_decisions_wired.ps1` | ⚠ exit 1 (2026-05-30, in run_all full pass) | 95 decisions parsed: 77 WIRED, 0 REGRESSION, 0 LEAK, 2 PENDING (`Kruber/dr_dual_wield_hammers` stale doc row, `Kruber/we_javelin` deferred-experimental), 78 ORPHAN (Saltzpyre/Kerillian decision sections stubbed — code ahead of doc), 1 UNCLASSIFIABLE. Self-test passes. |
| `check_mechanics_citations.ps1` | ✅ OK (2026-08-02) | 80 cited factual bullets across 13 domains (`[src:]` decompiled-verified, `[memory:]`, `[bugclass:]`, `[dump:]`), 4 honest `[unverified]` gaps, 0 uncited. Two independent checks now: tag SHAPE, plus `[src:]` RESOLUTION — 112/112 refs open against the decompiled tree with every cited line in range: MECHANICS 83, BUG_CLASSES 22, WEAPON_APPEARANCE_STANDARD 5, CROSS_MOD_ARCHITECTURE 2 (`-ResolveSrc` runs this set alone; a missing `Vermintide-2-Source-Code` checkout is a clean visible SKIP, as in CI, and `-RequireSource` makes absence blocking). Prior count (45/8 domains) was stale AND understated: a `###` subheading was terminating its parent `## Domain:` region, so the 16-bullet Inventory / Equipment domain was never linted at all — fixed 2026-08-02, self-test now plants an uncited bullet under a subheading. Self-test passes 8/8. Run the script for the live per-domain breakdown. |
| `check_file_sizes.ps1` | ⚠ ratcheted debt (issues #429/#2) | The hard baseline retains 2 canonical files above 2,500 lines; the independent target baseline is the live target-tier debt census rather than duplicating its changing count here. Both tiers freeze exact non-empty-logical-line ceilings: a new crossing or any growth blocks, while shrinkage/removal is allowed and surfaced for baseline retirement. Whitespace-only lines count. Nested repository-internal worktree copies and explicitly generated pure-data tables are excluded. The #786 and Old Musket test-owner splits retired `test_cwv_husk_adapter.lua` and `test_cwv_old_musket_presentation.lua` from target debt while preserving the exact 3,118-test total. |
| `check_decomposition_contracts.ps1` | ✅ OK (2026-08-23) | Issue #504/#1159 machine-readable census retains all 10 canonical entry phases plus #2's completed GT Dev bot-fix helper contract at or below the 1,500-line target. Blocking in Quick/full QA; self-test covers growth, owner loss, phase deletion, inventory expansion, and base-relative ceiling burns. Structural completion is not an in-game feature-verification claim. |
| `check_dev_only_edits.ps1` | ✅ OK (2026-07-08) | Dev/stable split guard (row 52b, issue #429). Standard in `run_all`, `-Staged` in pre-commit. Clean working tree = exit 0. Self-test passes. |
| `check_logging.ps1` | Historical baseline: 56 findings (2026-07-08); current #427 warn-chat debt: 3 exact public stable-stream sites | Rows 58a-d (issues #429/#427). The original warn-chat backlog fell from 16 to CT/GT/VDL stable only; all dev twins and single-stream owners are console-only. Ordinary census debt exits 1, but any new warn-chat fingerprint or scanner failure exits 2. Self-test covers five scanner fixtures plus the monotonic migration floor. |
| `check_hook_test_coverage.ps1` | ✅ OK (2026-07-08, first run) | Row 24a (issue #429). Diff-scoped (default `HEAD~1..HEAD`, `-Staged`, or CI `origin/<base>...HEAD`). Over `HEAD~10..HEAD` all added hooks/NL-writes resolved covered (mods ship suites). Advisory in `run_all` + warn-only pre-commit step 4. Self-exits 0 on indeterminate diff. Self-test 7/7. |
| `check_stale_docs.ps1` | ⚠ 19 stale (advisory) | Pinned Advisory in `run_all` (issue #429) — TIME-based, non-blocking. 19 docs currently >14 days (script `$StaleDays` default) without a SUPERSEDED banner; fix with `-FixStale`. |
| `check_rt_textual_invariants.ps1` | ✅ OK (2026-07-12, first run) | Row 59 (issue #516). Tier-a gate for the source-text invariants issue #511 moved out of the in-game rt suites. 56 needles across gt_dev/ct_dev/gut_dev/cim_dev/WOC/dcp, all PASS against live source. Standard policy in `run_all` full pass (exit 2 blocks). Self-test 6/6. Both failure modes (absent-needle violation + missing file) proven via a synthetic manifest. |
| `luacheck` | ⚠ ~415 warnings (advisory) | Pinned Advisory in `run_all` AND CI (issue #429; was CI `\|\| true`). Baseline; 141 = CWV finding, 274 net real signal. Drive down, then flip to Standard. |

## Generated name-map (key → display-name) + integrity validator

The authoritative INTERNAL-key → in-game DISPLAY-name map is **generated**, not
hand-maintained — see `docs/generated/README.md`. Two related pieces:

```powershell
# 1. Regenerate the authoritative map (date is a required param — env has no clock):
pwsh -NoProfile -File tools/gen-name-map/gen-name-map.ps1 -GenDate 2026-05-30
#    -> docs/generated/NAME_MAP.generated.json  (machine-authoritative)
#    -> docs/generated/NAME_MAP.generated.md    (grep this, not the legacy catalogs)

# 2. Validate localization integrity (3 checks: missing setting_id loc = ERROR,
#    unresolvable assigned name = ERROR, orphan loc key = WARN):
pwsh -NoProfile -File qa/check_name_integrity.ps1            # all mods
pwsh -NoProfile -File qa/check_name_integrity.ps1 -SelfTest  # planted-fault proof
```

`check_name_integrity.ps1` reads `NAME_MAP.generated.json` as a runtime-name
oracle (so cwv/cosmetics runtime-registered names don't false-positive) — run the
generator first for best results. It **is wired into `run_all.ps1`** (Standard)
and, as of issue #429, **ratcheted**: the pre-existing errors are frozen in
`qa/baselines/name_integrity.json` (the committed-oracle, no-VtSrc view, so the
same semantic keys cover CI and local), and the check blocks only on a NEW error.
The runtime-name oracle and the source-proven vanilla-key oracle are committed;
the optional decompiled checkout enriches diagnostics but cannot hide ratchet
drift because the blocker reruns in CI's source-less view. Check-2 ratchet keys
exclude source paths while diagnostics retain them. (Not yet in the launcher's blocking upload
preflight; that would mirror the `QaScriptGate.RunAsync(mod, ...)` pattern in
`tools/vmb-launcher/Services/ModRunner.cs`, exit 2 = block.)

## What's NOT covered yet (gaps)

1. **Network send recipient validation** (#28): would need a `check_network_send.ps1`
   that grep's for `mod:network_send` and verifies the 2nd arg is `"all"`,
   `"others"`, `"local"`, or a peer_id literal — not `"server"`.

2. **CHANGELOG format consistency** (#20): three styles in use across mods.
   Could be normalized by `check_changelog_format.ps1` — low ROI, skip until
   it bites.

3. **Wrong-key storage access at runtime** (#6): caught only by reading vanilla
   source carefully. PRE-SHIP review is the safety net.

4. **Same-character LA hat with template-vs-mesh node mismatch** (#41, this
   session's e6fc17e2 crash): handed off to cosmetics agent group.

5. **In-game smoke tests**: no headless Stingray runtime. Would require
   instrumented in-game commands that auto-verify state after every load.
   Tracked in PROJECT_STANDARDS §11 as future work.

## How to add a check

When a new bug class is discovered:
1. **Document the bug** in a memory file (`feedback_*.md` or `reference_*.md`).
2. **Add a row** to the appropriate table above with:
   - Bug class name
   - Memory file reference
   - Detection method
   - Status
3. **If AUTO**: scaffold the script in `qa/check_<name>.ps1`, wire into `qa/run_all.ps1`.
4. **If PRE-SHIP**: update PROJECT_STANDARDS §5.3 review template.
5. **If MANUAL**: ensure CLAUDE.md or PROJECT_STANDARDS surface the rule.

## When this doc is wrong

If a check name doesn't match the script, fix one or the other. If a bug class
is missing from the tables, add it. This is a living index, not a snapshot.
