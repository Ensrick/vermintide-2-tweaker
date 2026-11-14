# A5 helper: dev vs stable drift for crafting_in_modded pair (namespace-normalized). Read-only.
import os, difflib, re
root = r"<repos>/vermintide-2-tweaker"
dev = os.path.join(root, "crafting_in_modded_dev", "scripts", "mods", "crafting_in_modded_dev")
st = os.path.join(root, "crafting_in_modded", "scripts", "mods", "crafting_in_modded")
def norm(s):
    s = s.replace("crafting_in_modded_dev", "crafting_in_modded").replace('"cim_dev"', '"cim"')
    return s
def name(n): return n.replace("crafting_in_modded_dev", "crafting_in_modded")
dfiles = {name(f): f for f in os.listdir(dev) if f.endswith(".lua")}
sfiles = {f: f for f in os.listdir(st) if f.endswith(".lua")}
print("dev-only:", sorted(set(dfiles) - set(sfiles)))
print("stable-only:", sorted(set(sfiles) - set(dfiles)))
tot_add = tot_del = 0; same = 0; rows = []
for k in sorted(set(dfiles) & set(sfiles)):
    a = norm(open(os.path.join(st, sfiles[k]), encoding="utf-8", errors="replace").read()).splitlines()
    b = norm(open(os.path.join(dev, dfiles[k]), encoding="utf-8", errors="replace").read()).splitlines()
    if a == b: same += 1; continue
    add = dele = 0
    for l in difflib.unified_diff(a, b, lineterm="", n=0):
        if l.startswith("+") and not l.startswith("+++"): add += 1
        elif l.startswith("-") and not l.startswith("---"): dele += 1
    tot_add += add; tot_del += dele
    rows.append((add + dele, k, add, dele, len(a), len(b)))
print("identical after namespace normalization:", same, "differing:", len(rows))
for r in sorted(rows, reverse=True):
    print("  %-48s +%d -%d (stable %d -> dev %d lines)" % (r[1], r[2], r[3], r[4], r[5]))
print("total +%d -%d" % (tot_add, tot_del))
