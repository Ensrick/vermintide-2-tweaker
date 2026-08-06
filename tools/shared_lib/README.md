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

## Peer parity modes and wire catalogs

`_lib_peer_parity.lua` preserves its original four-argument VMF payload unless
the consumer explicitly supplies `opts.wire_identity`. Legacy consumers therefore
remain byte-compatible when the canonical library gains exact-mode support.

Exact mode sends a bounded identity, peer epoch, challenge, and challenge echo.
It rejects schema or identity mismatches, replies not bound to the current
challenge, unchallenged epoch changes, and epochs retired on disconnect/roster
expiry. Retirement is bounded per peer and across peers so the replay defense
cannot grow without limit.

`_lib_wire_catalog.lua` builds the exact identity. Call
`build_identity(namespace, entries, lookup)` with a stable semantic namespace,
the complete owned-name registry, and the live bidirectional numeric lookup.
Optional fallback mappings are included explicitly in `entries`; missing or
asymmetric numeric proof fails closed. Do not use a mod version or presence bit
as a substitute for the catalog identity.

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
