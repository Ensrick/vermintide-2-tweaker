import re, sys, io, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
digest = open(os.path.join(base, "issues", "digest", "D2_wt_cosmetics_open_digest.md"), encoding="utf-8", errors="replace").read()
nums = re.findall(r"(?m)^=== #(\d+) \[open\]", digest)
res = {}
moji = []
topo = {}
for n in nums:
    t = open(os.path.join(base, "issues", "open", n + ".md"), encoding="utf-8", errors="replace").read()
    idx = [m.start() for m in re.finditer(r"## CURRENT LIVE TEST", t)]
    if not idx: continue
    card = t[idx[-1]:]
    j = card.find("## COMMENT by")
    if j > 0: card = card[:j]
    for cmd in re.findall(r"/([a-z_0-9]+_regression_test)", card):
        res.setdefault(cmd, set()).add(n)
    if re.search(r"[═-╬ΓÇ]", card): moji.append(n)
    m = re.search(r"\*\*Topology:\*\*\s*([A-Za-z-]+)", card)
    topo[n] = m.group(1) if m else "?"
for k in sorted(res): print(k, len(res[k]), sorted(res[k], key=int))
print("mojibake cards:", moji)
import collections
print("topology:", collections.Counter(topo.values()))
print("coop cards:", [n for n in topo if topo[n].lower().startswith("co")])
