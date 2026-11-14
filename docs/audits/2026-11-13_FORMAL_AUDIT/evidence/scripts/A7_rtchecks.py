# A7: count in-game regression checks in gut_dev and classify (source-text needle vs runtime/pure assertion). Read-only.
import re, os, glob, sys
m = sys.argv[1] if len(sys.argv) > 1 else "gui_tweaker_dev"
d = os.path.join(r"<repos>/vermintide-2-tweaker", m, "scripts", "mods", m)
tot = 0; rows = []
for f in sorted(glob.glob(os.path.join(d, "**", "*.lua"), recursive=True)):
    t = open(f, encoding="utf-8", errors="replace").read()
    # direct registrations
    names = re.findall(r'(?:_rt_register|register|mod\._gut_rt_register)\(\s*"([\w]+)"\s*,\s*function', t)
    # table-style: { name = "x", fn = function
    names += re.findall(r'name\s*=\s*"([\w]+)"\s*,\s*fn\s*=', t)
    names += re.findall(r'rt_checks\[#[\w\.]*rt_checks \+ 1\]\s*=\s*\{\s*name\s*=\s*"([\w]+)"', t)
    names = list(dict.fromkeys(names))
    if not names: continue
    # body classification per check: slice text from name occurrence to next registration
    idxs = sorted((t.find('"' + n + '"'), n) for n in names)
    for i, (pos, n) in enumerate(idxs):
        end = idxs[i + 1][0] if i + 1 < len(idxs) else min(len(t), pos + 6000)
        body = t[pos:end]
        src = bool(re.search(r'src_read|read_source|_rt_src_read|io\.open|getinfo', body))
        eng = bool(re.search(r'Managers\.|rawget\(_G|ScriptUnit|Unit\.|World\.', body))
        rows.append((os.path.basename(f), n, src, eng))
    tot += len(names)
print("total named checks:", tot)
from collections import Counter
c = Counter(); per = Counter()
for f, n, src, eng in rows:
    k = ("source-needle" if src else "") + ("+engine-read" if eng else "") or "pure/self-test"
    c[k] += 1; per[f] += 1
for k, v in c.most_common(): print(f"  {k:28s} {v}")
print("per file:")
for f, v in per.most_common(): print(f"  {v:3d} {f}")
