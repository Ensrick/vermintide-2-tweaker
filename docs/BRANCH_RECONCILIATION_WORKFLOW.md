# Branch reconciliation workflow

Issue #625 tracks the accumulated local and remote `agent/*` and `codex/*`
branches. The reconciliation process is evidence-first and report-only. A
branch name, referenced issue, version edit, or overlapping path is a lead for
review, never authority to merge or delete a ref.

## Generate a current census

Fetching is an explicit operator action because it mutates remote-tracking
refs. The census tool itself does not fetch, check out, merge, delete, push, or
edit refs.

```powershell
git fetch origin --prune
pwsh -NoProfile -File tools/github/branch-reconciliation-census.ps1 `
  -RepoRoot . `
  -BaseRef origin/master `
  -OutputPath docs/generated/BRANCH_RECONCILIATION.generated.json `
  -MarkdownPath docs/generated/BRANCH_RECONCILIATION.generated.md
```

Run the command from a clean worktree based on the latest `origin/master`.
Review the JSON as the authoritative record; the Markdown sibling is a compact
census. Identical tips are one record with every local and remote ref retained
as an alias.

## Evidence and dispositions

The report records the base commit, each unique tip, aliases, ancestry,
ahead/behind counts, divergent commits, `git cherry -v` results, issue
references, changed paths, paths changed on current source since the merge
base as a count, exact path overlap, and version/manifest paths.

Only two dispositions are automatic:

- `integrated-ancestor`: the exact tip is an ancestor of the recorded base.
- `patch-equivalent`: the branch has divergent non-merge commits, every one is
  a `git cherry` minus patch, and the patch comparison is complete.

Every other tip is `review-required`. In particular, unique patches, merge
commits, unrelated histories, version conflicts, manifest edits, diagnostics,
and source overlap require semantic review. `git cherry` compares patch IDs;
it does not prove runtime behavior, intent, completeness, or that a similarly
named later fix superseded the branch.

## Review a `review-required` tip

1. Read its divergent commits and issue references, then read the current
   implementation and the relevant open and closed issue history.
2. Inspect changed paths and current-source overlap. Treat overlap and version
   files as conflict warnings, not as evidence that either side is correct.
3. Reproduce the branch's claim with the smallest relevant tests or logs.
4. Choose and record one evidence-backed outcome:
   - integrate a bounded current-tree transplant and run applicable QA;
   - superseded, citing the canonical commit and verification that owns the
     same behavior;
   - diagnostics-only or obsolete, citing the issue/log evidence that makes it
     non-shippable;
   - retain for further review with the exact missing evidence.
5. Merge or delete a ref only as a separate, deliberate operation after that
   review. Never bulk merge or bulk delete census entries.

The report is a point-in-time snapshot. The base and branches can move after
generation, so use its recorded SHAs when evaluating evidence and regenerate
before acting on a stale snapshot.

## Offline QA contract

```powershell
pwsh -NoProfile -File qa/check_branch_reconciliation_census.ps1
```

The gate deliberately does not enumerate live refs. CI clones often omit local
branches and most remote-tracking branches, so regeneration in CI would produce
a misleading partial census. Instead it verifies schema, a maximum 14-day age,
the current generator SHA-256, unique ref/tip ownership, summary counts, exact
proof predicates for automatic dispositions, and JSON/Markdown fingerprint
parity. The generator hash normalizes checkout line endings so LF/CRLF does not
create platform-only failures. A changed generator or expired snapshot requires deliberate local
regeneration with the full ref inventory.

Both the generator and gate have `-SelfTest` fixtures. Run them under `pwsh`
and `powershell.exe` when changing PowerShell compatibility logic.
