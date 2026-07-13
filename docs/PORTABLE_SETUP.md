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

## VMBLauncher settings

VMBLauncher stores machine-specific paths and deployment targets outside this
repository at `%APPDATA%\VMBLauncher\settings.json`. Set its ProjectRoot to the
clone directory containing `.vmbrc`. Use `VMBLauncher.exe doctor` to validate
VMB, SDK, Steam, Workshop, and project paths.

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
