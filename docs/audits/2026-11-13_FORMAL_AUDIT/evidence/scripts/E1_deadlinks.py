# E1: find backticked or markdown-linked repo paths in rule surfaces that do not exist on disk.
import re, os, sys
REPO = r"<repos>/vermintide-2-tweaker"
files = sys.argv[1:]
BT = chr(96)
EXT = r"(?:md|ps1|psd1|lua|json|py|yml|cfg)"
rx = re.compile(BT + r"([A-Za-z0-9_.\-/]+\." + EXT + r")" + BT + r"|\]\(([A-Za-z0-9_.\-/]+\." + EXT + r")(?:#[^)]*)?\)")
tracked = None
def tracked_names():
    global tracked
    if tracked is None:
        import subprocess
        out = subprocess.run(["git", "-C", REPO, "ls-files"], capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
        tracked = set(os.path.basename(x) for x in out.splitlines())
    return tracked
for f in files:
    p = f if os.path.isabs(f) else os.path.join(REPO, f)
    s = open(p, "rb").read().decode("utf-8", "replace")
    base = os.path.dirname(p)
    seen = set(); miss = []
    for i, line in enumerate(s.split("\n"), 1):
        for m in rx.finditer(line):
            t = (m.group(1) or m.group(2))
            if t in seen: continue
            seen.add(t)
            cands = [os.path.join(REPO, t), os.path.join(base, t)]
            if any(os.path.exists(c) for c in cands): continue
            bare = "/" not in t
            if bare and t in tracked_names():
                miss.append((i, t, "bare name; exists elsewhere in repo (ambiguous)"))
            else:
                miss.append((i, t, "NOT FOUND"))
    nf = [m for m in miss if m[2] == "NOT FOUND"]
    print(f"== {f}: {len(seen)} distinct path refs, {len(nf)} not found, {len(miss)-len(nf)} bare/ambiguous")
    for i, t, why in miss:
        if why == "NOT FOUND": print(f"   L{i}: {t}  [{why}]")
