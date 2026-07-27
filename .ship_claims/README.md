# `.ship_claims/` -- legacy documentation pointer

Live claim files no longer belong in a source checkout. The authoritative
machine-global directory is:

```text
%APPDATA%\VMBLauncher\ship_claims\
```

That is the same authority consulted by separate worktrees and nested
VMBLauncher processes. This directory remains tracked only so older checkout
instructions lead to the current policy. Do not create claim files here.

Full rationale, usage, ownership rules, and stale policy:
**`tools/ship/CLAIMS.md`**.
