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
`%APPDATA%\VMBLauncher\ship_claims\<mod>.claim`. This is the one machine-global
authority shared by every worktree, `ship.ps1`, and VMBLauncher's nested upload
gate. The create uses the OS `CREATE_NEW` disposition: exactly one racer's
create can succeed; every other racer gets `IOException` and reports
contention. The claim body is written through the exclusive handle, so a reader
never sees an empty claim mid-write.

The tracked repo-local `.ship_claims/README.md` remains a discovery and legacy
transition note only. Current `claim.ps1` does not place live claims there.
`-ClaimsDir` is reserved for isolated self-tests and diagnostics.

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

# 3. Ship. ship.ps1 verifies a live claim whose version EQUALS the source
#    MOD_VERSION, then (on success) auto-releases the claim.
.\tools\ship\ship.ps1 -Mod weapon_tweaker

# Free your own claim manually (abandoned work, or ship never ran):
.\tools\ship\claim.ps1 -Mod weapon_tweaker -Release
```

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

### `-NoClaim` escape hatch

`ship.ps1 -Mod <name> -NoClaim` skips the gate with a loud warning. Use it only
in a **solo** session (no other sessions shipping on this machine), or for an
urgent fix when the broker is in the way. It exists so the rollout of this gate
can never brick a ship.

## Stale policy

A claim older than **2 hours** (`-StaleHours`) is stale. A new claimant will
break a stale claim (deleting it and taking its own), and says so in the output.
This keeps a crashed or abandoned session from wedging a mod's version stream
forever. A stale claim never authorizes a ship -- `ship.ps1` treats it as absent.

## Caveats

- **Machine-global, not network-global.** Every worktree on this Windows user
  account contends on one lock and VMBLauncher reads the same file. Another
  computer still needs a future remote/GitHub-backed reservation layer.
- **Owner handoff remains explicit.** Separate manual worktrees derive different
  fallback owner IDs. A Claude/Codex identity or explicit
  `VT2_SHIP_SESSION_ID` survives child processes; a future durable token can
  authorize a deliberate cross-owner handoff without weakening ownership.
- **Advisory sibling: `.in_progress/`.** Claims are about version allocation;
  `.in_progress/` sentinels are about who is editing which files. They are
  complementary -- keep dropping a sentinel for multi-step work.

## Self-test

`claim.ps1 -SelfTest` runs offline fixtures: allocate-increment (with 4-segment
rejection), timestamp round-trip + staleness, the former repo-local/global split,
nested-uploader visibility through the shared authority, idempotent re-claim vs
contention, stale-break, release (own + idempotent), the ship.ps1 verify
contract, foreign-owner verify/release refusal, and a real two-process,
two-worktree race asserting exactly one process acquires. It is wired into
`qa/run_selftests.ps1` (and therefore `qa/run_all.ps1` full pass + CI). Exit
codes: 0 pass, 2 regression.
