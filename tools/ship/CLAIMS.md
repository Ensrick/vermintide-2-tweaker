# Ship / version claim broker

`tools/ship/claim.ps1` is an atomic mutual-exclusion lock over a mod's next
build. It stops parallel Claude sessions on this machine from allocating the
**same** next `MOD_VERSION` and uploading competing bundles.

## Why it exists

Multiple sessions running on one machine repeatedly picked the same next patch
version and shipped colliding Workshop bundles, each forcing a manual
"reconciliation build". Documented incidents:

- cosmetics `0.9.143` **and** `0.9.145` allocated in parallel
- weapon_tweaker `0.12.273-beta`
- weapon_tweaker_dev `0.12.274-dev`

The `.in_progress/` sentinels (see `CLAUDE.md` "Multi-agent coordination") are
**advisory awareness** only. This broker is the enforced version-allocation lock
that `ship.ps1` refuses to ship without.

## The lock

Acquiring a claim is an **atomic exclusive file create** of
`%APPDATA%\VMBLauncher\ship_claims\<mod>.claim`. This is the machine-global
directory used by VMBLauncher, so separate git worktrees, the outer ship
wrapper, and nested launcher processes all consult the same authority. The
create uses the OS `CREATE_NEW` disposition: exactly one racer's create can
succeed; every other racer gets `IOException` and reports contention.

The repo-local `.ship_claims/` directory is a tracked legacy documentation
pointer only. It is not the default claim authority. `-ClaimsDir` exists for
isolated tests and diagnostics, not normal shipping.

### Claim file format

```
# VT2 ship/version claim -- see tools/ship/CLAIMS.md
mod = weapon_tweaker
version = 0.12.274-beta
session = <explicit/Claude/Codex owner id, or deterministic worktree id>
created = 2026-07-18T04:12:33Z
```

`version` is the allocated **next** patch version: the mod's current
`MOD_VERSION` with `PATCH + 1`, preserving the `-dev` / `-beta` / `-alpha` /
`-rc` suffix. 4-segment versions are rejected (normalize per the `CLAUDE.md`
"Format: 3-segment semver only" rule before claiming).

`session` is an enforced owner credential. Resolution order is
`VT2_SHIP_SESSION_ID`, `CLAUDE_SESSION_ID`, `CODEX_THREAD_ID`, then a stable
fingerprint of the invoking worktree for a normal manual shell. Verification
and release both require the exact same owner; a foreign task cannot consume or
erase a same-version live claim.

## Usage (claim -> bump -> ship -> release)

```powershell
# 1. Claim the mod. This reads its CURRENT MOD_VERSION and allocates the next
#    patch, printing it. Claim BEFORE you bump the source.
.\tools\ship\claim.ps1 -Mod weapon_tweaker
#    -> Allocated version: 0.12.274-beta

# 2. Set  local MOD_VERSION = "0.12.274-beta"  in the mod's lua, make your
#    changes, write the CHANGELOG entry.

# 3. Build the tracked release artifact without deploying or publishing.
.\tools\ship\ship.ps1 -Mod weapon_tweaker -BuildOnly

# 4. Commit source + bundle + the generated .build-receipt.json together, push,
#    open the PR, pass hosted qa-gate, and merge. Any relevant source edit after
#    BuildOnly invalidates the receipt and requires another BuildOnly run. Raw
#    working bytes must also be reproducible from the Git-clean staged blobs.

# 5. From a clean worktree at the exact live default-branch commit, ship.
#    ship.ps1 verifies the same live claim, merged PR, hosted qa-gate, and
#    freshly rebuilt bundle bytes. It records release provenance, then gives
#    VMBLauncher the exact five-minute receipt hosted on that GitHub release.
#    The launcher independently downloads those bytes, rechecks root, commit,
#    owner, mod/version, cfg/source hashes, and the exact SDK-staged content
#    immediately before ugc_tool.
.\tools\ship\ship.ps1 -Mod weapon_tweaker

# Free your own claim manually (abandoned work, or ship never ran):
.\tools\ship\claim.ps1 -Mod weapon_tweaker -Release
```

First-upload bootstrap is the exception to automatic release. When the reviewed
cfg carries `published_id = 0L`, the successful bootstrap writes only Steam's
assigned ID, stops before lifecycle labeling/test-readiness output, and keeps
the claim held. Rerun canonical BuildOnly so the refreshed receipt binds the
assigned-ID cfg, then commit the ID-only cfg and receipt, pass protected PR QA,
merge, and run the ordinary canonical ship from the new live default HEAD. The
root may remain byte-identical; the narrow atomicity exception accepts only
`0L` to one positive ID with every other cfg byte and `MOD_VERSION` unchanged.
Releasing the claim earlier permits another clean worktree to create a second
Workshop item.

Claim **before** bumping the source: the broker allocates from the current (not
yet bumped) version. Re-running `claim.ps1 -Mod <name>` in the same session is
idempotent -- it returns the version you already hold, it does not allocate again.

## ship.ps1 enforcement

Near the top of a ship (after param parsing, before the QA gates and before any
build/deploy/upload) `ship.ps1` calls
`claim.ps1 -Mod <name> -Verify -ExpectedVersion <source MOD_VERSION>` and aborts
when the claim is:

- **absent** -- no one claimed this mod; run `claim.ps1 -Mod <name>` first.
- **mismatched** -- the claim's version is not the source `MOD_VERSION` being
  shipped (another session likely allocated a different number).
- **stale** -- the claim is older than the stale window and no longer valid.
- **foreign-owned** -- the version matches, but another Claude/Codex/manual
  worktree owner created the claim.

On a fully successful ship, `ship.ps1` releases its own claim automatically.
Foreign releases fail closed and leave the original claim intact.

### `-NoClaim`

`-NoClaim` is accepted only with `-BuildOnly`, which cannot deploy or upload.
Workshop publication cannot bypass the machine-global claim.
The inverse is equally important: a matching claim is version coordination,
not publication authorization. Direct launcher `upload`/`all`, GUI
publication, and caller-authored JSON cannot publish on a claim alone.

## Stale policy

A claim older than **24 hours** (`-StaleHours`) is stale. This covers a normal
feature-branch review and hosted-QA cycle without releasing the reserved
version. A new claimant will
break a stale claim (deleting it and taking its own), and says so in the output.
This keeps a crashed or abandoned session from wedging a mod's version stream
forever. A stale claim never authorizes a ship -- `ship.ps1` treats it as absent.

## Cross-worktree ownership

Codex/Claude task identities survive child processes and worktree changes. A
manual multi-worktree release must set one explicit identity before both claim
and ship, for example `$env:VT2_SHIP_SESSION_ID = 'wt-0.12.274-beta'`. A
different owner cannot spend or erase the claim even when the version matches.

Claims are about version allocation; `.in_progress/` sentinels are advisory
editing awareness. They remain complementary.

## Self-test

`claim.ps1 -SelfTest` runs offline fixtures: allocate-increment (with 4-segment
rejection), timestamp round-trip + staleness, idempotent re-claim vs contention,
stale-break, release (own + idempotent), the ship.ps1 verify contract, and a
foreign-owner verify/release refusal, nested-authority visibility, plus a real
two-worktree/two-process race asserting exactly one process acquires. It is wired into
`qa/run_selftests.ps1` (and therefore `qa/run_all.ps1` full pass + CI). Exit
codes: 0 pass, 2 regression.
