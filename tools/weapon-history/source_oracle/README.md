# Independent weapon-history source oracle

This lane prevents generated Tweaker: Weapons history catalogs from testing
themselves. The Patch 5.2 family/state matrix is declared in
`patch_5_2_source_spec.lua`;
historical/current values remain in the preserved extractor evidence; and
`patch_5_2_routes_oracle.lua` is regenerated directly from immutable Git objects
in the decompiled source checkout. No runtime-catalog value is an oracle input.

The same independently written evaluator also reproduces the adjacent/current
evidence lanes for Patch 2.0.6, 2.0.9.1, 2.0.10, 3.1, 3.2, 4.1.1, 4.6, 6.0, 6.6,
6.8, and Hotfix 6.11.2.
Patch 2.0.6 proves the three shared historical Handgun penetration leaves
before the generator projects them onto the two immutable current clones.
Patch 2.0.9.1 proves the complete 20-leaf Halberd push-follow-up chain
boundary, including three current-only chain rows and exact nested-table
guards, before the generator emits one atomic historical projection.
Patch 2.0.10 independently proves the two Sword-and-Dagger heavy-profile
values and regenerates the four exact current left/right routes without reading
the runtime catalog. Patch 3.1
proves the bounded Blunderbuss `max_ammo` and Tuskgor Spear
`block_fatigue_point_multiplier` boundaries and independently confirms that
the current-only Versus template is outside the adjacent Blunderbuss family.
Patch 4.6 additionally
uses `patch_4_6_source_spec.lua` to regenerate the exact two current Hagbane
profile routes without reading the runtime catalog. Its enclosing gate also
declares and preflights the Morris/Cog/Woods contributors used by both profile
rehydrators: six source files and 18 exact objects total, with lazy fetch and
optional Git locks disabled after selection. Its `--self-test` includes an
independent 3-by-3 true/false/absent presence table and serialized false-versus-
absence assertions, so a present `false` source leaf cannot silently become an
unset leaf. It also evaluates two adversarial immutable revisions that use the
historical `local weapon_template = weapon_template or {}` pattern and proves
their mutable symbolic roots remain distinct, preventing a later evaluation
from overwriting an earlier snapshot and hiding a real source change.
Hotfix 6.11.2 independently selects Sienna Dagger Heavy Attack 2's one
damage-profile route, rehydrates its current native-profile guard, and agrees
with the primary evaluator before catalog generation. Its enclosing gate also
pins the current native damage-profile and network-lookup blobs, proving both
profile identities share the vanilla lookup without adding transport.

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

The standalone test `qa/lua/tests/test_wt_history_source_oracle.lua` proves the
Patch 5.2 set of 14 families and 22 states against independently loaded source
evidence. It also checks that slice's 182-operation census, historical result
fidelity, 13 source profiles,
one derived profile, route/source-only classification, exact Git blob identity,
zero-write preflight, actual runtime installation, commit, and exact-reference
restore. It separately pins Patch 4.1.1's current present-false guard through
planning, commit, and exact restore. Patch 4.6's dedicated reproducibility gate
requires primary/oracle agreement for historical, post-boundary, and current
profile payloads plus byte-exact route-oracle regeneration. The suite is
registered in
`qa/lua/run.lua` and is part of full QA.
