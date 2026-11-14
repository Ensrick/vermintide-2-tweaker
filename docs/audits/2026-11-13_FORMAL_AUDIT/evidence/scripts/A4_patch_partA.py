"""A4 helper: small corrections to plan/wp/CW.md (part A), then append part B. Writes only inside the audit workspace."""
import io, os, sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
p = os.path.join(root, "plan", "wp", "CW.md")
pb = os.path.join(here, "A4_cw_partB.md")
t = io.open(p, encoding="utf-8").read()

reps = [
    (r"""publish `mod._ct_boon_rollable = function(name) local modded = _injected_dormants[name] ~= nil; local safe = mod._ct_wire_safe ~= nil and mod._ct_wire_safe() == true; return mod._ct_wire_policy.rollable(modded, _added_to_pool[name] == true, safe) end`.""",
     r"""publish `mod._ct_boon_rollable = function(name) local modded = _injected_dormants[name] ~= nil; local policy = mod._ct_wire_policy; if not policy then return not modded end; local safe = mod._ct_wire_safe ~= nil and mod._ct_wire_safe() == true; return policy.rollable(modded, _added_to_pool[name] == true, safe) end`."""),
    (r"""Steps: `T.set` every `enable_boon_*` option to false (""",
     r"""Steps: `T.set` `enable_boon_reworks` to true and every other `enable_boon_*` option to false ("""),
    (r"""Add cases: (a) with a fake `run_state` holding one vanilla and one custom power-up row for one player,""",
     r"""Add cases: (a) with a fake `run_state` holding one vanilla and one custom power-up row for one player (use the nested shape `_ct_each_server_state_row` walks, `CTD/_ct_peer_parity_owner.lua:422-445`),"""),
]
missing = 0
for a, b in reps:
    n = t.count(a)
    if n != 1:
        missing += 1
        sys.stdout.write("NOT FOUND (%d): %s\n" % (n, a[:90]))
        continue
    t = t.replace(a, b)

if "### WP-CW-07" not in t:
    t = t.rstrip("\n") + "\n" + io.open(pb, encoding="utf-8").read()

io.open(p, "w", encoding="utf-8", newline="\n").write(t)
cards = t.count("\n### WP-CW-")
sys.stdout.write("done, missing=%d, cards=%d, lines=%d, em_dashes=%d\n" % (missing, cards, t.count("\n"), t.count(u"—")))
