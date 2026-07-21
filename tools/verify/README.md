# Live in-game test queue

`generate_playtest.ps1` turns only the open issues that are ready to test in
Vermintide 2 now into one ordered solo/co-op walk.

## Run

```powershell
pwsh tools/verify/generate_playtest.ps1
pwsh tools/verify/generate_playtest.ps1 -SelfTest
pwsh tools/verify/generate_playtest.ps1 -OutDir C:\tmp\playtest
```

The tool is read-only against GitHub and overwrites `docs/PLAYTEST_SCRIPT.md`
and `docs/PLAYTEST_COOP.md`. Change the generator and regenerate; do not
hand-edit its output.

## Queue contract

Every open issue carries exactly one lifecycle:

- `not-started`: not ready for live testing.
- `diagnostics-armed`: an in-game diagnostic is runnable now.
- `verify-fix`: a complete candidate fix is runnable now.

`Fixed` and `verify-fix-coop` are invalid on open issues. `coop-required` is an
orthogonal qualifier on a ready lifecycle, not a lifecycle itself. Blocked and
tooling/repository-only issues remain `not-started` and never enter these docs.

Every ready issue must have a latest comment in this exact shape:

```markdown
## CURRENT LIVE TEST

**Build/banner:** v0.12.300-dev, confirm `[wt:LOAD]`
**Topology:** Solo

1. Open Weapon Tweaker in the Mod Tweaker menu.
2. Equip Kruber's Mace and perform the reported action.

**Expected:** Kruber's Mace behaves normally and the game does not crash.
```

When a mod does not emit a `[name:LOAD]` marker, reproduce and clearly label
its whole versioned runtime banner instead, for example:
`**Build/banner:** exact banner: [WOC] v0.1.42-dev loaded`.

Use localized names visible to players. Snake-case internal keys are rejected
inside numbered steps. Exact player-entered slash commands such as
`/woc_pose_reset` are allowed when wrapped in backticks in the card. The newest
exact card is authoritative; a newer incomplete card invalidates an older
complete card.

For co-op, finish useful solo testing first, then use:

```markdown
**Topology:** Co-op (host and one client)
**Solo status:** Passed; only remote rendering remains.
```

Only then add `coop-required`. A co-op card without a passed/completed/exhausted
solo status fails policy.

## Fail-closed behavior

The generator fetches the queue candidates in one batch and validates each via
`lifecycle_method_policy.ps1` before creating its output directory or writing a
document. Any retired lifecycle, blocked leakage, stale/mismatched co-op label,
tooling queue entry, missing field, missing numbered step, or internal key aborts
the run and names every invalid issue. Invalid candidates are never silently
published into a tester checklist.

The same policy is consumed by ship automation, the open-issue audit, and the
blocking CI tracker guard.
