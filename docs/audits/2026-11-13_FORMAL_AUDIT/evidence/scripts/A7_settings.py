# A7: settings <-> readers cross-reference for a gut stream (read-only).
import re, sys, os, glob
repo = r"<repos>/vermintide-2-tweaker"
m = sys.argv[1] if len(sys.argv) > 1 else "gui_tweaker_dev"
d = os.path.join(repo, m, "scripts", "mods", m)
data = open(os.path.join(d, m + "_data.lua"), encoding="utf-8", errors="replace").read()
ids = re.findall(r'setting_id\s*=\s*"([^"]+)"', data)
files = [f for f in glob.glob(os.path.join(d, "**", "*.lua"), recursive=True)]
src = {}
for f in files:
    b = os.path.basename(f)
    if b in (m + "_data.lua", m + "_localization.lua"): continue
    src[b] = open(f, encoding="utf-8", errors="replace").read()
allsrc = "\n".join(src.values())
print("setting_ids in data:", len(ids), "unique:", len(set(ids)))
noread = []
for s in sorted(set(ids)):
    n = allsrc.count('"' + s + '"')
    if n == 0: noread.append(s)
print("settings with ZERO quoted occurrences outside data/loc:", len(noread))
for s in noread: print("   ", s)
# readers with no setting: mod:get("x") where x not in data ids
gets = set(re.findall(r'mod:get\(\s*"([^"]+)"\s*\)', allsrc))
sets = set(re.findall(r'mod:set\(\s*"([^"]+)"', allsrc))
print("mod:get literal keys:", len(gets), " mod:set literal keys:", len(sets))
print("mod:get keys not declared as widget (hidden persistence or dead readers):")
for g in sorted(gets - set(ids)): print("   ", g, "(also set)" if g in sets else "(NEVER set by literal)")
print("mod:set keys not declared as widget:")
for g in sorted(sets - set(ids)): print("   ", g)
