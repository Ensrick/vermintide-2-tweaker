# Portable Maintainer Setup

This document owns machine-local repository configuration. Build, deploy, and
upload doctrine is owned by [PROJECT_STANDARDS.md section 6.6](../PROJECT_STANDARDS.md#66-ship-doctrine-keyed-off-the-mod_version-suffix-canonical-2026-07-01);
launcher implementation guidance lives in the separately maintained
VMBLauncher repository.

## Repository-only work

Documentation edits and the PowerShell QA suite do not require Steam, the
Vermintide 2 SDK, VMB, or `.vmbrc`. From a clean clone:

```powershell
pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua
```

Install the repository hooks after cloning when contributing changes:

```powershell
pwsh -NoProfile -File tools/install-hooks.ps1
```

## Local VMB configuration

VMB reads one `.vmbrc`; it does not merge a tracked base with a per-user
override. VMBLauncher also requires the file to be named `.vmbrc` in its
configured ProjectRoot. Consequently the real file is ignored and the
portable template is tracked:

```powershell
Copy-Item .vmbrc.example .vmbrc
```

The example assumes the VMB repository is a sibling directory named `vmb` and
uses `../vmb/.template-vmf`. Change only the ignored `.vmbrc` if VMB lives
elsewhere. The default Steam and SDK paths are fallback values; because
`use_fallback` is `false`, VMB normally discovers Steam rather than forcing
those paths.

Do not commit `.vmbrc`. Confirm before committing:

```powershell
git check-ignore .vmbrc
```

### Shipping from a clean linked worktree

Git linked worktrees intentionally omit both ignored dependencies: `.vmbrc`
and the separately maintained `tools/vmb-launcher/` checkout. The canonical
`tools/ship/ship.ps1` wrapper resolves those machine-local dependencies without
changing which checkout supplies mod source.

Launcher resolution is deterministic: `VT2_SHIP_VMB_LAUNCHER` when explicitly
set, then the invoking worktree, the ProjectRoot recorded in VMBLauncher
settings, and the primary git worktree. An explicitly configured missing or
empty launcher is a hard failure; the wrapper does not silently ignore a bad
override. Launcher configuration isolation follows the section 6.6 owner
contract: each launcher child receives the same transaction-private `--config`
bound to the invoking worktree.

If the invoking worktree already has `.vmbrc`, that file wins and is never
overwritten. Otherwise the wrapper checks `VT2_SHIP_VMBRC`, the configured
ProjectRoot, the primary git worktree, and finally the invoking checkout's
tracked `.vmbrc.example`. Before accepting any candidate, it parses the JSON
and proves that `mods_dir`, interpreted from the invoking worktree, resolves to
the invoking worktree itself. A config that points at `mods`, another checkout,
or an absolute foreign source root fails before VMBLauncher runs. The accepted
bytes are written only to the required `<ProjectRoot>/.vmbrc` name for the
launcher action and removed in `finally` after both success and failure.

These fallbacks supply tooling and configuration only. The pre-existing ship
identity gate still requires VMBLauncher `info` to resolve the invoking mod
directory and match its git commit, `MOD_VERSION`, and `published_id` before
the wrapper can build or deploy. Publication is a separate internal launcher
verb and remains available only to the canonical `ship.ps1` transaction; direct
`all`, `upload`, and GUI publication cannot construct its authority.

## VMBLauncher settings

VMBLauncher stores machine-specific paths and deployment targets outside this
repository at `%APPDATA%\VMBLauncher\settings.json`. Set its ProjectRoot to the
usual clone directory containing `.vmbrc`. Use `VMBLauncher.exe doctor` to
validate VMB, SDK, Steam, Workshop, and project paths.

For shipping from another worktree, do not retarget or restore this shared
settings file. Canonical ship uses it as discovery input, then creates a
separate private configuration for the exact invoking checkout. The private
file, not the shared settings file, is removed during cleanup. See
[PROJECT_STANDARDS.md section 6.6](../PROJECT_STANDARDS.md#66-ship-doctrine-keyed-off-the-mod_version-suffix-canonical-2026-07-01)
for the single transaction owner, identity validation, cleanup/recovery, and
publication-receipt requirements (issues #647/#1180). This setup guide does
not define an alternative binding or restoration procedure.

Remote hosts are also local settings. Configure `RemoteDeployTargets` in the
launcher settings and SSH aliases in `~/.ssh/config`; never place hostnames,
credentials, keys, or per-machine Workshop paths in tracked repository files.
An empty or disabled target list is valid for contributors without a second
test machine. Existing maintainer targets remain in local launcher settings
and are unaffected by this repository change.

## Maintainer release topology

The canonical merge-first release transaction is owned by
`PROJECT_STANDARDS.md` section 6.6. This setup document does not redefine its
claim, `-BuildOnly`, protected merge, or final clean-default-HEAD phases.
`ship.ps1` invokes the ignored `.vmbrc` indirectly through VMBLauncher and
performs configured local and remote deployments without opening interactive
windows. Use `-NoRemote` only for the exception defined by the owner doctrine;
do not copy bundles into Workshop folders or invoke VMB, direct launcher
publication, GUI publication, the SDK uploader, SSH, or SCP directly.

When migrating an existing checkout, preserve the old `.vmbrc` before updating,
then restore it as the ignored local file. Existing `%APPDATA%` launcher settings
and remote targets require no migration.
