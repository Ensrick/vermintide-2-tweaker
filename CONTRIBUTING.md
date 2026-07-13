# Contributing to Vermintide 2 Tweaker

Thank you for helping improve the Tweaker mods. This guide is the human entry
point for setup, issue selection, implementation, testing, and review. Detailed
engineering policy remains in [PROJECT_STANDARDS.md](./PROJECT_STANDARDS.md);
this guide links to its owner sections instead of copying them.

## Five-minute setup

### Requirements

| Tool | Supported role |
|---|---|
| Windows 10/11 | Primary development, QA, build, and deployment environment. |
| Git for Windows | Clone, branches, worktrees, and hooks. |
| PowerShell 7.x (`pwsh`) | Primary shell for repository QA and tooling. Windows PowerShell 5.1 compatibility is retained where a script explicitly claims it. |
| Lua 5.1 | Vermintide 2 runtime dialect; do not use newer standard-library APIs. |
| .NET 9 runtime/SDK | Required only when building or running VMBLauncher. |
| Current Vermintide 2 and VMF | Required only for in-game verification. Exact game and VMF versions are not pinned in this repository. |

The GitHub CLI (`gh`) is optional for local code work and useful for maintainers
handling issues and releases. Engine-facing work also needs the decompiled game
source available locally; mechanics claims without a source citation must be
marked `[unverified]` as described in
[PROJECT_STANDARDS section 12a](./PROJECT_STANDARDS.md#12a-mechanics-knowledge-substrate--capture-doctrine).

```powershell
git clone https://github.com/Ensrick/vermintide-2-tweaker.git
Set-Location vermintide-2-tweaker
./tools/install-hooks.ps1
./qa/run_all.ps1 -Quick -SkipLua
```

The last command is the fast static gate and never launches Vermintide 2. Run
the full gate before opening a pull request:

```powershell
./qa/run_all.ps1
./tools/mod-lint/lint-mod.ps1
```

See [qa/CHECKS.md](./qa/CHECKS.md) for blocking versus advisory checks and the
bug classes each check covers.

## Choose and claim work

1. Choose an existing issue where possible. New issue titles have at most eight
   words after the `[mod]` prefix and use the repository issue form.
2. Read [MOD_OWNERSHIP.md](./MOD_OWNERSHIP.md) and check `.in_progress/` before
   editing a mod. Coordinate if another branch or session owns the same files.
3. Use a focused branch. Avoid mixing unrelated fixes in one pull request.
4. For a bug, read [docs/BUG_TRIAGE_RUNBOOK.md](./docs/BUG_TRIAGE_RUNBOOK.md) and
   match [docs/BUG_CLASSES.md](./docs/BUG_CLASSES.md) before changing code.

Every open issue has exactly one tracker lifecycle label:

- `not-started` until the first code or diagnostic work ships.
- `verify-fix` after a complete solo-verifiable fix ships with an in-game test
  comment and expected result.
- `verify-fix-coop` instead when verification requires two or more people.
- `diagnostics-armed` after a runtime probe ships with reproduction steps and
  expected output.
- `Fixed` only after the maintainer or designated playtester confirms the fix
  in game. It remains open until hardening, documentation, and regression work
  are complete.

Documentation and tooling issues do not use the in-game verification labels;
they are validated autonomously and closed with evidence. The complete taxonomy
and prerequisites live in
[PROJECT_STANDARDS section 11](./PROJECT_STANDARDS.md#11-pending-work-tracking).

## Stable, dev, and single streams

Five mod families have separate stable and development directories:

| Stable | Development |
|---|---|
| `chaos_wastes_tweaker` | `chaos_wastes_tweaker_dev` |
| `crafting_in_modded` | `crafting_in_modded_dev` |
| `general_tweaker` | `general_tweaker_dev` |
| `gui_tweaker` | `gui_tweaker_dev` |
| `verminious_dreams_lighting` | `verminious_dreams_lighting_dev` |

All in-flight changes for these families go into the `_dev` directory. Stable
directories receive deliberate promotions only. `weapon_tweaker` is the active
single stream; `weapon_tweaker_dev` is stale and must not be edited. The legacy
`tweaker` directory is frozen.

The complete stream and promotion rules live in
[docs/PROMOTION_PROCESS.md](./docs/PROMOTION_PROCESS.md). The canonical directory
inventory is in [README.md](./README.md#mod-directory).

## Ground changes in the engine

Before changing a hook or asserting how the game works, trace the relevant
vanilla path in the decompiled source. Record this engine trace in the issue and
pull request:

| Field | Question answered |
|---|---|
| Vanilla entry point | Which exact `Class.function` begins the path? |
| State owner | Which object or table owns the affected state? |
| Authority | Does the host, client, local player, or every peer decide? |
| Runtime lifecycle | Does it run at registration, creation, update, RPC, teardown, or UI render? |
| Native seam | What is the narrowest safe interception or data-mutation point? |
| Runtime unknown | What timing, asset, or live-state fact can source not prove? |
| Test topology | Can one player verify it, or are host and client required? |

Use `file:line` citations for evidence and `Class.function` as the durable symbol
reference. Start with [docs/engine/README.md](./docs/engine/README.md) and the
affected mod's `ENGINE_SURFACE.md`. Runtime facts that source cannot establish
belong in a focused `printf` probe, not an assumption.

## Implement and test

- Use Lua 5.1 syntax and preserve vanilla return shapes.
- Before adding `mod:hook` or `mod:hook_safe`, search the entire mod for the same
  `(Class, method)` pair. VMF silently drops duplicate registrations from one
  mod; consolidate behavior into the existing hook.
- Keep entry points small and place coherent features in documented modules.
- Update the affected mod's version, `CHANGELOG.md`, and owning reference docs
  when producing a build. Documentation-only changes do not bump mod versions.
- Never claim a game fix is complete before in-game confirmation.

Testing has three distinct tiers:

1. Repository QA (`qa/*.ps1`) checks source without running the game.
2. Per-mod `/<mod>_regression_test` commands assert live engine invariants.
3. Temporary issue diagnostics collect facts the source cannot provide.

Every bug fix needs a regression check that would fail if the defect returned.
Networked changes need explicit host/client coverage. See
[PROJECT_STANDARDS sections 2.2b and 15](./PROJECT_STANDARDS.md#22b-test-and-diagnostic-tiers-issues-499--501-2026-07-12)
for the complete contracts.

## Pull requests

Before requesting review:

- Keep the pull request limited to one coherent issue or feature.
- Rebase or merge the current `master` without discarding unrelated work.
- Run the full QA and mod-lint commands shown above.
- Complete the engine trace and verification sections in the pull request
  template; use `N/A` with a reason when no game runtime is involved.
- Link the issue, but do not close an in-game issue before user verification and
  its post-fix pass.
- Do not commit local settings, credentials, investigation notes, or manually
  generated Workshop-directory content.

## Build and release boundary

[VMBLauncher](https://github.com/Ensrick/vmb-launcher) is the only supported
build, deploy, and Workshop upload path. Do not invoke the raw builder,
`ugc_tool`, or copy files into a Workshop item directory. Contributors normally
submit source and verification evidence; the maintainer owns deployment,
Workshop visibility, stable promotion, and public release decisions.

If a maintainer asks you to produce a build, follow the current ship doctrine in
[PROJECT_STANDARDS section 6.6](./PROJECT_STANDARDS.md#66-ship-doctrine-keyed-off-the-mod_version-suffix-canonical-2026-07-01)
and the VMBLauncher documentation. Never launch Vermintide 2 or another
interactive application on someone else's machine without explicit permission.

## Documentation changes

Update the document that owns the topic and link to it elsewhere. Pending work
belongs in GitHub Issues, not a new roadmap. Investigation snapshots are
ephemeral; distill durable findings into the appropriate reference or
postmortem. See
[PROJECT_STANDARDS section 7](./PROJECT_STANDARDS.md#7-documentation-standards)
for the repository's document lifecycle.
