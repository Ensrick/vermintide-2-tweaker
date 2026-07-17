# Portable Maintainer Setup

This document owns machine-local repository configuration. Build, deploy, and
upload doctrine remains in `CLAUDE.md`; launcher implementation guidance lives
in the separately maintained VMBLauncher repository.

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
override. The launcher is invoked with the exact `--config` path that the
wrapper temporarily binds.

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
`all` can build, deploy, or upload.

## VMBLauncher settings

VMBLauncher stores machine-specific paths and deployment targets outside this
repository at `%APPDATA%\VMBLauncher\settings.json`. Set its ProjectRoot to the
usual clone directory containing `.vmbrc`. Use `VMBLauncher.exe doctor` to
validate VMB, SDK, Steam, Workshop, and project paths.

`tools/ship/ship.ps1` does not trust that global ProjectRoot during a ship.
Multiple git worktrees share the same launcher settings, so the wrapper
temporarily binds ProjectRoot to the repository containing the invoked script,
asks VMBLauncher to report the resolved mod folder, and compares the root,
`MOD_VERSION`, git commit, and `published_id` with that invoking checkout. Any
mismatch aborts before `VMBLauncher all` can build, deploy, or upload. The
original settings file is restored byte-for-byte in a `finally` block on both
success and failure. A named OS mutex covers binding, validation, the complete
launcher action, and restoration so parallel worktree ships cannot race the
shared file (issue #647). This is a wrapper guard; VMBLauncher's normal `all`
build/deploy/upload semantics are unchanged.

Remote hosts are also local settings. Configure `RemoteDeployTargets` in the
launcher settings and SSH aliases in `~/.ssh/config`; never place hostnames,
credentials, keys, or per-machine Workshop paths in tracked repository files.
An empty or disabled target list is valid for contributors without a second
test machine. Existing maintainer targets remain in local launcher settings
and are unaffected by this repository change.

## Maintainer release topology

The canonical release command remains:

```powershell
pwsh -NoProfile -File tools/ship/ship.ps1 -Mod <mod-name>
```

`ship.ps1` invokes the ignored `.vmbrc` indirectly through VMBLauncher, and
VMBLauncher performs the configured local and remote deployments. Use
`-NoRemote` only for the documented one-off exception; do not copy bundles into
Workshop folders or invoke VMB, the SDK uploader, SSH, or SCP directly.

When migrating an existing checkout, preserve the old `.vmbrc` before updating,
then restore it as the ignored local file. Existing `%APPDATA%` launcher settings
and remote targets require no migration.
