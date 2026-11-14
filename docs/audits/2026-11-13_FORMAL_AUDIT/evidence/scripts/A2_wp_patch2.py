def patch(p, reps):
    s = open(p, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, 'missing in %s: %s' % (p, a[:70])
        s = s.replace(a, b, 1)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)
patch('A2_wp_part3.md', [
 ("- RIG: after the next build, boot plus `keep`: `host_forbid_log = { \"is not a resource\", \"weapons_of_chaos.lua\" .. \":\" }` is too broad; use instead `T.expect(get_mod(\"WOC\") ~= nil)`, `T.expect(rawget(ItemMasterList, \"woc_blightreaper\") ~= nil)` and `T.expect_rt(\"WOC\", \"issue595_required_runtime_helpers_loaded\")`.",
  "- RIG: on a build made after the change, `qa/runtime/woc/a2f18_package_wildcard.lua`, arena `keep`: `T.expect(get_mod(\"WOC\") ~= nil)`, `T.expect(rawget(ItemMasterList, \"woc_blightreaper\") ~= nil)`, `T.expect_rt(\"WOC\", \"issue595_required_runtime_helpers_loaded\")`, and `host_forbid_log = { \"scripts/mods/weapons_of_chaos/\" .. \"_\" }` is NOT used (too broad); the three assertions are the evidence."),
 ("- Every call to a VMF-hooked function goes through VMF's dispatcher, which packs the return values into a table and unpacks them again (`vmf/scripts/mods/vmf/modules/core/hooks.lua:172-190`). VMF cannot remove a hook, only mark it inactive, and an inactive hook still goes through the dispatcher (`:135-169`).",
  "- Every call to a VMF-hooked function goes through VMF's dispatcher, which builds a new table for the return values on each call and unpacks it again (`vmf/scripts/mods/vmf/modules/core/hooks.lua:78-81,176-187`). VMF cannot remove a hook, only mark it inactive, and an inactive hook still goes through the dispatcher (`:137-168`)."),
 ("arena `mission:military` (three bots, no cwv weapon equipped: this is the cost every session pays).",
  "arena `mission:military` (level key at `scripts/settings/level_settings.lua:1264`), with no cwv weapon equipped: this is the cost every session pays."),
])
patch('A2_wp_part2.md', [
 ("`qa/lua/tests/test_cwv_regression_harness_1656.lua:25-40` does", "`qa/lua/tests/test_cwv_regression_harness_1656.lua:31-40` does"),
])
print('ok')
