# Patch 5.2 independent source oracle

This lane prevents the generated Tweaker: Weapons history catalog from testing
itself. Its family/state matrix is declared in `patch_5_2_source_spec.lua`;
historical/current values remain in the preserved extractor evidence; and
`patch_5_2_routes_oracle.lua` is regenerated directly from immutable Git objects
in the decompiled source checkout. No runtime-catalog value is an oracle input.

Pinned source input:

- repository: a local checkout of `Aussiemon/Vermintide-2-Source-Code` that
  contains every pinned commit, `commit:path`, and blob below; the shared
  read-only selector proves the complete ledger before regeneration
- current content anchor (6.12.0): `038498af2b565bcb10bf5ed225638293a7640c83`
- historical anchors: the full revisions in `patch_5_2_source_spec.lua`

From the Tweaker repository root, verify the exact-number serializer:

```powershell
qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe `
  tools/weapon-history/source_oracle/extract_weapon_history_oracle.lua `
  --self-test
```

Regenerate the route/blob oracle with canonical LF bytes:

```powershell
$source = 'C:/path/to/Vermintide-2-Source-Code'
$env:WT_HISTORY_OUTPUT = `
  'tools/weapon-history/source_oracle/patch_5_2_routes_oracle.lua'
qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe `
  tools/weapon-history/source_oracle/extract_weapon_history_oracle.lua `
  --source-repo $source `
  --routes 038498af2b565bcb10bf5ed225638293a7640c83 `
  tools/weapon-history/source_oracle/patch_5_2_source_spec.lua
```

The standalone test `qa/lua/tests/test_wt_history_source_oracle.lua` proves all
14 families and 22 states against independently loaded source evidence. It also
checks the 182-operation census, historical result fidelity, 13 source profiles,
one derived profile, route/source-only classification, exact Git blob identity,
zero-write preflight, actual runtime installation, commit, and exact-reference
restore. The suite is registered in `qa/lua/run.lua` and is part of full QA.
