# `.ship_claims/` -- legacy claim location

Live ship/version claims are stored at
`%APPDATA%\VMBLauncher\ship_claims\<mod_name>.claim`, not in this worktree.
That machine-global location is shared by every git worktree and by
VMBLauncher's nested upload gate (issue #724).

Full rationale, usage, and stale policy: **`tools/ship/CLAIMS.md`**.

## What's tracked vs ignored

- `README.md` (this file) remains tracked so old worktrees and operators find
  the current authority.
- Repo-local `*.claim` files remain gitignored for compatibility with older
  tooling, but current `claim.ps1` neither creates nor consumes them by default.
- `-ClaimsDir` is an explicit isolated test/diagnostic override.

## Claim file format

The machine-global authority contains one file per claimed mod, named exactly
`<mod_name>.claim` (the mod's repo-root directory name), containing:

```
# VT2 ship/version claim -- see tools/ship/CLAIMS.md
mod = weapon_tweaker
version = 0.12.274-beta
session = <explicit/Claude/Codex owner id, or deterministic worktree id>
created = 2026-07-18T04:12:33Z
```

- `mod`     -- the claimed mod's directory name.
- `version` -- the allocated next patch version (current `MOD_VERSION`,
  `PATCH + 1`, suffix preserved).
- `session` -- the enforced claiming owner. Verify and release require an exact
  match; foreign tasks cannot spend or delete a live claim.
- `created` -- ISO-8601 UTC timestamp; claims older than 2 hours are stale and
  may be broken by a new claimant.

## Lifecycle

```powershell
.\tools\ship\claim.ps1 -Mod <name>            # acquire + allocate next version
.\tools\ship\claim.ps1 -Mod <name> -Release   # free the claim
```

`tools/ship/ship.ps1` requires a live, version-matching claim before it will
build/deploy/upload. The owner must also match, and only that owner can release
the claim automatically on a successful ship.
`-NoClaim` bypasses the gate for solo sessions (see `tools/ship/CLAIMS.md`).
