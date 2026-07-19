# CI and protected `master`

Issue #540 makes the QA workflow and branch protection one fail-closed release boundary.

## CI contract

The `QA / qa-gate` check runs for every push to `master`/`main`, every pull request into
those branches, and manual dispatches. Pushes deliberately have no path filter: compiled
packages, textures, materials, project metadata, PowerShell, C#, and future build inputs
must not bypass QA merely because an allowlist omitted their extension.

The workflow has repository read-only permissions, does not retain checkout credentials,
pins third-party actions to immutable commit SHAs, cancels superseded runs on the same ref,
and keeps a job timeout. The normal gate uses PowerShell 7; release surfaces that explicitly
promise Windows PowerShell 5.1 compatibility (`check_promotion.ps1` and `ship.ps1`) also run
their offline self-tests under the inbox `powershell` host.

`Stable Promotion Authorization / stable-promotion-authorization` is the second
required PR status. It is a `pull_request_target` workflow loaded from protected
`master`, checks out only that base revision, and uses read-only metadata access.
It never executes incoming PR code. Ordinary PRs pass it without a grant; stable
promotion PRs must satisfy the version- and SHA-bound maintainer process in
`docs/PROMOTION_PROCESS.md`.

`qa/check_ci_hardening.ps1` enforces this contract locally and in CI. Its `-SelfTest`
plants a mutable action reference, a fragile push path filter, and weakened protection to
prove those failures are detected.

## Enabling branch protection

Do not protect a permanently red branch: it prevents normal recovery through the required
check. First restore a successful completed `QA` run on `master` (issue #2 / the current
file-size ratchet backlog), then preview and apply:

```powershell
./tools/github/protect-master.ps1
./tools/github/protect-master.ps1 -Apply
```

The tool refuses to apply unless the latest completed master QA run is `success`. The policy
requires both `qa-gate` and `stable-promotion-authorization` on an up-to-date branch,
applies to administrators, requires PR conversations to be resolved, and disables
force-push and branch deletion. It does not require an approving review, so a solo
maintainer can merge after the automated gates pass.

After applying, confirm the rule through GitHub's branch settings or:

```powershell
gh api repos/Ensrick/vermintide-2-tweaker/branches/master/protection
```

## Emergency maintainer path

Protection is not bypassed for routine urgency. If the required check infrastructure itself
is unavailable and an emergency repository repair cannot wait:

1. Open a GitHub issue recording the outage, repair commit, reason, and rollback plan.
2. Temporarily disable only the blocking requirement in GitHub branch settings; never enable
   force pushes or deletion.
3. Push the smallest repair, manually run `qa/run_all.ps1` and all-mod lint locally, and link
   their results on the issue.
4. Re-run `protect-master.ps1 -Apply` immediately after QA is green, verify protection through
   the API, and close the incident with the unprotected time window recorded.

This is an audited break-glass procedure, not a standing administrator bypass.
