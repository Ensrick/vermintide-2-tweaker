# Worktree lifecycle

The repository permits at most eight secondary worktrees using at most 12 GiB
combined. The blocking guard is `qa/check_worktree_budget.ps1`; it runs in Quick
QA, the pre-commit hook, full QA, and shipping preflight.

Read-only investigation does not get a worktree. Create one only when isolated
writes are required:

```powershell
.\tools\worktrees\worktree.ps1 -Action Create -Name issue-123
```

The default location is the system temporary directory, never `source\repos`.
The command refuses creation at the count limit.

Close it in the same session after its work is committed. Run the close command
from the primary checkout, not from inside the target worktree; Windows may keep
the executing script file open and prevent removal of its own directory.

```powershell
Set-Location C:\Users\danjo\source\repos\vermintide-2-tweaker
.\tools\worktrees\worktree.ps1 -Action Close -TargetPath "$env:TEMP\vt2-issue-123"
```

Close refuses dirty source and ambiguous ignored files. It can force-remove only
a clean registered worktree containing narrowly allowlisted build output or
machine-local files. It never archives or guesses about source. Preserve dirty
work in a commit/branch before retrying.

Audit at any time:

```powershell
.\tools\worktrees\worktree.ps1 -Action Audit
```

If an external application creates worktrees without this wrapper, the next
Quick QA/pre-commit fails once the global count or disk budget is exceeded.
