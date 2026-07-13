# Copied shared Lua libraries

`tools/shared_lib/` is the canonical source for small primitives reused by
standalone Workshop mods. These are build-time copies, not a runtime shared mod:
every consumer bundles its own `_lib_*.lua` and loads it with `mod:dofile`.

After editing a canonical library or the consumer registry (`manifest.psd1`),
synchronize copies from the repository root:

```powershell
.\tools\shared_lib\sync-shared-libs.ps1 -Apply
```

The default mode is read-only and checks exact bytes, including line endings:

```powershell
.\tools\shared_lib\sync-shared-libs.ps1
.\qa\check_shared_lib_drift.ps1
```

Never edit a per-mod copy directly. A consumer needing different semantics gets
a differently named canonical library rather than a drifted local fork.
