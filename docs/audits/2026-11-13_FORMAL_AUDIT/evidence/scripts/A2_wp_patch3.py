"""A2 round 2: final wording patches for plan/wp/CWV.md (run from the audit workspace root)."""
import re

p = 'plan/wp/CWV.md'
s = open(p, encoding='utf-8').read()


def rep(a, b):
    global s
    assert a in s, 'missing: ' + a[:90]
    s = s.replace(a, b, 1)


rep('(a) Load `weapon_tweaker/scripts/mods/weapon_tweaker/_wt_history_2_0_10_catalog.lua` the way `qa/lua/tests/test_cwv_shortsword_construction.lua` or the wt history tests load it, read `current_source.revision`, and assert that every 40-hex literal used in a `"revision"` comparison in the six cwv files equals it.',
    '(a) Read as text the six cwv files named in Context and the `_wt_history_*.lua` files of BOTH `weapon_tweaker/scripts/mods/weapon_tweaker/` and `weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/` (name them in the test; take the list from `git ls-files`, 19 per tree today). Assert that every 40-hex string literal in the cwv files (23 distinct today) occurs in each tree\'s text, and that the literal compared with `"revision"` in `_cwv_history_producer_binding.lua` is the `revision` value of `current_source` in `_wt_history_2_0_10_catalog.lua`.')

rep('- OFFLINE: suite exits 0. Changing the `revision` string in a scratch copy of the wt catalog makes `test_cwv_admission_pins` fail and name the cwv files (run it once to prove, do not commit).',
    '- OFFLINE: suite exits 0. Changing the `revision` string in a scratch copy of `_wt_history_2_0_10_catalog.lua` makes `test_cwv_admission_pins` fail and name the cwv file and literal (run it once to prove, do not commit).')

rep('`T.expect_rt("WOC", "issue595_required_runtime_helpers_loaded")`, and `host_forbid_log = { "scripts/mods/weapons_of_chaos/" .. "_" }` is NOT used (too broad); the three assertions are the evidence.',
    '`T.expect_rt("WOC", "issue595_required_runtime_helpers_loaded")`.')

# card 02 acceptance: replace the whole grep sentence (located by its stable prefix and suffix)
m = re.search(r'`git grep -c "\^mod\.on_enabled\(\).*?reports one hit per mod\.', s, re.S)
assert m, 'card 02 grep sentence not found'
s = s[:m.start()] + '`git grep -n "mod.on_enabled()" -- character_weapon_variants/scripts weapons_of_chaos/scripts` shows exactly one call line per mod (the definitions read `mod.on_enabled = function()` and do not match).' + s[m.end():]

rep('add `mod:dofile("scripts/mods/character_weapon_variants/_cwv_live_checks").install(mod, { om = _om, variant_definitions = _variant_definitions })`.',
    'add `mod:dofile("scripts/mods/character_weapon_variants/_cwv_live_checks").install(mod, { om = _om, variant_definitions = _variant_definitions })` (before the `mod.on_enabled()` line if WP-CWV-02 has landed).')

rep('29 forty-character hash literals sit in six runtime files',
    '29 forty-character hash literals (23 distinct) sit in six runtime files')

open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('patched; lines:', s.count('\n'))
