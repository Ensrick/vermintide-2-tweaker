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

## Native renderer residency contract

`_lib_resource_residency.lua` V2 separates two contracts that must not be
collapsed:

- strict helpers (`resource_resident`, `texture_set_resident`,
  `unit_materials_resident`, `gui_material_resident`) protect Tweaker-owned
  optional native calls and fail closed on absent or indeterminate proof;
- `probe` / `filter_material_pairs` are for global wrappers and preserve unknown
  vanilla, third-party, and Pusfume resources. Only positively proved absence may
  be filtered.

The exact consumer list lives in `manifest.psd1`. The full active-tree native
boundary ratchet lives in `qa/native_resource_contracts.psd1` and is enforced by
`qa/check_native_resource_contracts.ps1`.
