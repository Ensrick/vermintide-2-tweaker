import io
def patch(p, reps):
    s = open(p, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, 'missing in %s: %s' % (p, a[:70])
        s = s.replace(a, b, 1)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)
patch('A2_wp_part1.md', [
 ("- `_lib_network_lookup.lua` is a synced copy (`tools/shared_lib/`): do not edit it. `mod:dofile` returns a fresh module each call, so the record must hang on `mod`.",
  "- `_lib_network_lookup.lua` is a synced copy (`tools/shared_lib/`): do not edit it. `mod:dofile` returns a fresh module each call, so the record must hang on `mod`.\n- Out of scope: the transactional owners (`CWV/*_construction_owner.lua`, `_cwv_old_musket_melee_owner.lua`, `_cwv_tuskgor_spear_style_construction.lua`) register on detached copies and publish through their own commit step. Leave them. Every name they add starts with `cwv_`."),
])
patch('A2_wp_part2.md', [
 ("never clears it (`CWV/_cwv_regression_identity.lua:1382-1389`); other checks call `lifecycle:clear_peer(...)` (`:403`).",
  "never clears it (`CWV/_cwv_regression_identity.lua:1382-1389`); other checks do clear theirs on the same live table (`:844,970`)."),
 ("clear the peer the same way `:403` does (`lifecycle` is reachable as `_om._appearance_lifecycle`; call `:clear_peer(\"rt474-peer\")`).",
  "clear the peer the way `:970` does: `_om._appearance_lifecycle:clear_peer(\"rt474-peer\")` (method defined at `CWV/_cwv_appearance_lifecycle.lua:338`)."),
 ("and one loop that keeps the exact existing condition (`existing ~= nil and not rawequal(existing, _registered_keys[key])`, `pcall(admit, def)`, `ready ~= true`).",
  "and one loop with the existing condition: refuse when `existing ~= nil and not rawequal(existing, _registered_keys[key])`, or `pcall(admit, def)` fails, or its result is not `true` (three of the five copies write `~=` instead of `rawequal`; for plain tables that is the same test)."),
 ("Load the catalog exactly as `qa/lua/tests/test_cwv_crowbill_family.lua` does.",
  "Load the catalog the way `qa/lua/tests/test_cwv_regression_harness_1656.lua:25-40` does (`dofile(root .. \"_cwv_variant_catalog.lua\")({ om = om }).definitions` with the pure policy modules loaded into `om`)."),
 ("are resolved by loading those pure modules (the existing crowbill test shows how).",
  "are resolved by loading those pure modules into `om` (the loader named in step 2 does this)."),
])
print('ok')
