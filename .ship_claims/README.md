# `.ship_claims/` -- ship/version claim locks

Atomic mutual-exclusion locks that stop parallel sessions on this machine from
allocating the **same** next `MOD_VERSION` and uploading competing bundles.
Managed entirely by `tools/ship/claim.ps1`; you should not create or edit these
files by hand.

Full rationale, usage, and stale policy: **`tools/ship/CLAIMS.md`**.

## What's tracked vs ignored

- `README.md` (this file) is **tracked** so the convention is discoverable.
- Every `*.claim` file is **gitignored** (see `.gitignore`) -- claims are
  ephemeral per-session coordination state, not commit history. This mirrors
  the `.in_progress/*.md` sentinel convention.

## Claim file format

One file per claimed mod, named exactly `<mod_name>.claim` (the mod's repo-root
directory name), containing:

```
# VT2 ship/version claim -- see tools/ship/CLAIMS.md
mod = weapon_tweaker
version = 0.12.274-beta
session = <CLAUDE_SESSION_ID, or pid<PID>-<rand> when unset>
created = 2026-07-18T04:12:33Z
```

- `mod`     -- the claimed mod's directory name.
- `version` -- the allocated next patch version (current `MOD_VERSION`,
  `PATCH + 1`, suffix preserved).
- `session` -- the claiming session's identifier.
- `created` -- ISO-8601 UTC timestamp; claims older than 2 hours are stale and
  may be broken by a new claimant.

## Lifecycle

```powershell
.\tools\ship\claim.ps1 -Mod <name>            # acquire + allocate next version
.\tools\ship\claim.ps1 -Mod <name> -Release   # free the claim
```

`tools/ship/ship.ps1` requires a live, version-matching claim before it will
build/deploy/upload, and releases the claim automatically on a successful ship.
`-NoClaim` bypasses the gate for solo sessions (see `tools/ship/CLAIMS.md`).
