# A6 round 2: line-number and wording corrections in plan/wp/GT.md (kept for provenance).
import io, sys
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
reps = [
 ("| `commander_no_pos` | `AICommanderExtension._update_units` | `GTD/general_tweaker_dev.lua:546-575` | commander has no position |",
  "| `commander_no_pos` | `AICommanderExtension._update_units` | `GTD/general_tweaker_dev.lua:551-575` | commander has no position |"),
 ("5. `GTD/general_tweaker_dev.lua`: replace the whole block `:546-575` (comment and hook) with one line",
  "5. `GTD/general_tweaker_dev.lua`: replace the whole block `:551-575` (comment and hook) with one line"),
 ("(b) static: in the source text, the lines containing `mod:set(\"ai_takeover_enabled\", true)`, `mod:set(\"ai_takeover_enabled\", false)` and `not mod:get(\"ai_takeover_enabled\"))` do not exist any more in that two-argument form except inside `_ai_set_local_active`;",
  "(b) static: read the source text, collect every line that contains `mod:set(\"ai_takeover_enabled\"`, and assert that exactly one of them does not end its call with `, true)` (the one inside `_ai_set_local_active`, which passes the variable `active`);"),
]
for a, b in reps:
    assert a in s, a[:60]
    s = s.replace(a, b)
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("ok")
