# Execution protocol: how to carry out one work package (WP) or verification pack (VP)

One page. It describes the repository as it is on 2026-11-13 (master `592253d1`). Each step names the script or file that makes it true. `<repos>` is the folder that holds `vermintide-2-tweaker`. If a later card replaces a step, the card wins.

## 0. Before you touch anything

- Read `AGENTS.md`, then your one card. Do not read the audit.
- Your session may start in the shared primary checkout, `<repos>/vermintide-2-tweaker`. Other sessions keep uncommitted work there. In that folder run only read-only git commands and `tools/worktrees/worktree.ps1`. Never `git add`, `commit`, `stash`, `reset`, `clean`, `checkout` or `pull` there.
- The primary's `.git/config` sets `user.name = VT2 QA`, which overrides the owner's global identity in every worktree (`git config --show-origin --get-all user.name`). Do not edit git config. Commit with the global identity: `git -c user.name="$(git config --global user.name)" -c user.email="$(git config --global user.email)" commit ...`.

## 1. Pick and claim

1. Every id in the card's "Depends on" must be merged: `gh pr list --state merged --search "<DEP-ID> in:title"` shows it.
2. The card must be free: `gh pr list --state open --search "<ID> in:title"` and `git ls-remote --heads origin "wp/<ID>-*"` both print nothing.
3. Create your worktree from the primary checkout (`tools/worktrees/worktree.ps1:138-171`):
   `pwsh -NoProfile -File tools/worktrees/worktree.ps1 -Action Create -Name <id-lowercase>-<slug> -Branch wp/<ID>-<slug> -TargetPath <repos>/../vt2-worktrees/<id-lowercase>-<slug>`
   - `-Name` must match `^[a-z0-9][a-z0-9._-]{0,47}$` (line 139), so write `wp-g-03-guard`, not `WP-G-03`.
   - Pass `-TargetPath`. The default is the system temp folder (line 157), which gets cleaned. Never put a worktree inside `<repos>` (`tools/worktrees/README.md`).
   - The budget is 8 extra worktrees and 12 GiB (lines 17-18, `qa/check_worktree_budget.ps1`). If creation is refused, stop. Never close a worktree you did not create.
4. Publish the claim: in the worktree run `git push -u origin wp/<ID>-<slug>`. After your first commit open the draft pull request: `gh pr create --draft --base master --title "<ID>: <card title>" --body-file <file>`. The body follows `.github/pull_request_template.md` and links issues with `Refs #N` only (`qa/check_pr_autoclose.ps1` rejects closing keywords without a receipt).

## 2. Execute

- Do the card's steps in order. One card per pull request.
- Stage by explicit path. Never `git add -A` or `git add .`.
- The pre-commit hook runs eight steps (`tools/hooks/pre-commit.ps1:7-43`): whitespace, dev-only edits, bundle atomicity, build receipts, `qa/run_all.ps1 -Quick -SkipLua -Staged`, `tools/mod-lint/lint-mod.ps1`, hook test coverage, native resource safety. Let it finish. Do not pass `--no-verify`.
- Before each push run `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` and require the final `[worktree-purity] OK` line (`qa/README.md`).
- New `.ps1` files: ASCII only, `-Quiet` switch, exit codes 0 pass / 1 warnings / 2 errors (`qa/README.md`, "Adding a new check").

## 3. Does this card include a ship?

Run `git diff --name-only origin/master...HEAD`.

- **No path under a mod folder** (the 21 `Dir` values in `tools/mod-inventory.psd1`): no claim, no version bump, no build, no ship. This is the normal case for tracks G, P, T, H and for every VP (`qa/runtime/...`, `qa/lua/tests/...`).
- **Any path under a mod folder, documentation included:** the change is a mod change. Every file in a mod folder except `bundleV2/` and `.build-receipt.json` is a build input (`tools/ship/build-receipt.ps1:122-135`), and runtime source must land with its bundle in the same commit (`qa/check_release_bundle_atomicity.ps1`, `qa/check_build_receipts.ps1`). Follow `PROJECT_STANDARDS.md` section 6.6 exactly:
  1. `pwsh tools/ship/claim.ps1 -Mod <folder>` prints the allocated version (exit 0 acquired, 1 held by someone else: stop).
  2. Set `MOD_VERSION` to that number, write the top `CHANGELOG.md` entry, then `pwsh tools/ship/ship.ps1 -Mod <folder> -BuildOnly` (builds and writes the receipt; no deploy, no upload).
  3. Commit source, the `bundleV2` root bundle and `.build-receipt.json` together. Land the pull request (section 5).
  4. From a clean worktree at the exact new master commit run `pwsh tools/ship/ship.ps1 -Mod <folder>` (add `-AllowPublic` when `itemV2.cfg` says public). A claim older than 24 hours no longer authorizes a ship (`tools/ship/claim.ps1`, `-StaleHours` default 24), so finish within a day.
  5. If the ship leaves `tools/verify/live_test_contract_exceptions.psd1` modified, land that one file through its own pull request at once.
- **A stable folder** (`chaos_wastes_tweaker/`, `crafting_in_modded/`, `general_tweaker/`, `gui_tweaker/`, `verminious_dreams_lighting/`): the pre-commit hook blocks the edit (`qa/check_dev_only_edits.ps1`) and CI needs the maintainer's `stable-promotion-approved` grant (`qa/check_promotion_authorization.ps1`). Do the `_dev` part in its own pull request, open the stable part as a second draft pull request, and stop there. Never add that label yourself.
- If the machine has no launcher or `VMBLauncher doctor` reports an error (`docs/PORTABLE_SETUP.md`), stop before step 1 and say so in the pull request.

## 4. Prove it

Run every command under the card's "Acceptance" in the worktree. Paste each command and its last lines of output into the pull request body under "Verification". A rig result is quoted as `auto-verified (R) on <mod> <version> <commit>, run <id>`. If an acceptance command fails, the card is not done: fix it or follow "Stop and escalate".

## 5. Land

1. `gh pr ready <n>`, then `gh pr checks <n> --watch`. Required checks are `qa-gate`, `stable-promotion-authorization` and `pr-autoclose-authorization`; the branch must be up to date with master (`tools/github/protect-master.ps1:8,33`).
2. If the pull request is behind: `gh pr update-branch <n>` and wait for the new run.
3. Merge with a merge commit: `gh pr merge <n> --merge --delete-branch`. Confirm `gh pr view <n> --json state` says `MERGED`.
4. Wait for the master run on the merge commit: `gh run list --branch master --workflow QA --limit 3`. A ship needs it green on the exact commit (`tools/ship/publication-authorization.ps1:56`).
5. Close your worktree from the primary checkout, never from inside it (`tools/worktrees/worktree.ps1:174-221`): `pwsh -NoProfile -File tools/worktrees/worktree.ps1 -Action Close -TargetPath <path> -DeleteMergedBranch`.

## 6. When `qa-gate` fails for a reason outside your change

First compare with master: `gh run list --branch master --workflow QA --limit 1`. If master fails on the same step, the cause is not yours.

| Failing step or message | Cause | What you do |
|---|---|---|
| `check-lifecycle-cardinality.ps1` (`.github/workflows/qa.yml:125-141`) | Tracker state: a label, a pinned card or a tester comment on some issue | Not your diff. Do not edit the workflow, the guard or any label. Write the issue numbers and error codes in the pull request under "Blocked by", leave it as draft, take another card. WP-G-03 removes this step |
| `census is older than 14 days` (`qa/check_branch_reconciliation_census.ps1:14`) | The committed branch census aged out (last refreshed 2026-11-11) | Separate pull request `chore: refresh branch census` using the command in `docs/generated/README.md`. Never hand-edit the generated files |
| Merge blocked, branch behind | Strict up-to-date rule | `gh pr update-branch <n>` |
| Network or GitHub error in a step | Transient | `gh run rerun <run-id> --failed`, once |
| `Receipt-route override tree drift` (`tools/verify/live_test_source_authority.ps1:1786`) | Someone's ship has not landed its pin file yet | Wait for that pull request to merge, then update your branch |
| `[worktree-purity]` failure, or anything else | Treat as caused by your change | Fix it. If you cannot explain it, stop and report |

Never weaken, skip or delete a check to get green.

## 7. Stop and report

Stop when a "Stop and escalate" condition of the card is met, when a file the card names does not match its description, or when a step would need a rule in `AGENTS.md` to be broken. Write what you found in the pull request body, leave it as draft, and close nothing.
