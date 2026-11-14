"""A4 helper: apply text corrections to the CW work-package part B file. Writes only inside the audit workspace."""
import io, os, sys

here = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(here, "A4_cw_partB.md")
t = io.open(p, encoding="utf-8").read()

reps = [
    # 1. tree-diff command: normalise both sides
    (r"""`for f in chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/*.lua; do b=$(basename "$f" | sed 's/^chaos_wastes_tweaker\(_data\|_localization\)\?\.lua$/chaos_wastes_tweaker_dev\1.lua/'); d=chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/$b; [ -f "$d" ] && ! diff -q <(sed 's/chaos_wastes_tweaker_dev/chaos_wastes_tweaker/g; s/ct_dev/ct/g' "$d") "$f" >/dev/null && echo "$b"; done`""",
     r"""`N='s/chaos_wastes_tweaker_dev/chaos_wastes_tweaker/g; s/ct_dev/ct/g'; for f in chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/*.lua; do b=$(basename "$f" | sed 's/^chaos_wastes_tweaker\(_data\|_localization\)\?\.lua$/chaos_wastes_tweaker_dev\1.lua/'); d=chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/$b; [ -f "$d" ] && ! diff -q <(sed "$N" "$d") <(sed "$N" "$f") >/dev/null && echo "$b"; done` (both sides are normalised because some file names contain `ct_dev`)"""),
    # 2. et test case (c)
    (r"""(c) `count_units_by_breed` returns 1: phase is `"pending"`, and after advancing the module clock by 10 s through `mod.update` it is `"kicked"` and exactly one host chat line was echoed;""",
     r"""(c) `count_units_by_breed` returns 1: phase is `"pending"`; advance the module clock by 10 s through `mod.update`, call the `is_network_state_fully_synced_for_peer` hook again, and the phase is `"kicked"` with exactly one host chat line echoed;"""),
    # 3. WP-CW-08 rig for ct
    (r"""- RIG: add `qa/runtime/ct_dev/wp_cw_08_host_path.lua` (and for `ct`), arena `keep`:""",
     r"""- RIG: add `qa/runtime/ct_dev/wp_cw_08_host_path.lua` (and a copy for `ct` without the first assertion: public has no `_ct_effective_setting_source`), arena `keep`:"""),
    # 4. settings wording
    (r"""Reconcile settings: 30 ids exist only in dev, 13 only in public (""",
     r"""Reconcile settings: 30 widget ids (containers included) exist only in dev, 13 only in public ("""),
    # 5. checklist rows with measured values
    (r"""| `git grep -n "mod\._" -- <M>/<tree>_data.lua <M>/<tree>_localization.lua` prints nothing | not measured |""",
     r"""| `git grep -n "mod\._" -- <M>/<tree>_data.lua <M>/<tree>_localization.lua` shows no read of a field the script sets | pass (3 hits, comments) / pass (5 hits, fields the data file sets itself from `enemy_tweaker_breeds.lua`) / pass (0 hits) |"""),
    (r"""| `git grep -nE "Managers\.|ScriptUnit|mod:hook" -- "<M>/*_policy.lua" "<M>/*_core.lua"` prints nothing | not measured |""",
     r"""| `git grep -nE "Managers\.|ScriptUnit|mod:hook" -- "<M>/*_policy.lua" "<M>/*_core.lua"` prints nothing outside comments | pass (3 files) / pass (6 files) / pass (19 files, 1 comment hit) |"""),
    (r"""| fail (3 files) / fail (2 files) / fail (9 files) |""",
     r"""| fail (3 files) / fail (2 files) / fail (7 files) |"""),
    (r"""| `git grep -nE "rawset\(lookup|\[#lookup \+ 1\]|t\[idx\] = name" -- <M>` prints nothing outside the registrar | pass (no writes) / pass / fail (3 appenders) |""",
     r"""| `git grep -nE "#lookup \+ 1|rawset\(lookup|t\[idx\] = name" -- <M>` prints nothing outside `_lib_network_lookup.lua` | pass (0 hits) / pass (0 hits) / fail (7 hits in 3 appenders) |"""),
    (r"""| `git grep -ln "mod:hook" -- "<M>/*diag*.lua"` files each test the switch before hooking | fail (3 hooks) / not measured / fail |""",
     r"""| `git grep -c "mod:hook" -- "<M>/*diag*.lua"`: every listed file tests the switch before hooking | fail (`_evt_diagnostics.lua`, 3 hooks) / pass (no hooks in diagnostics files) / fail (3 files, 10 hooks) |"""),
]

missing = 0
for a, b in reps:
    n = t.count(a)
    if n != 1:
        missing += 1
        sys.stdout.write("NOT FOUND (%d): %s\n" % (n, a[:90]))
        continue
    t = t.replace(a, b)

io.open(p, "w", encoding="utf-8", newline="\n").write(t)
sys.stdout.write("done, missing=%d\n" % missing)
