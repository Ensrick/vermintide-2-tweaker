"""A4 helper: list hook sites (any receiver) per mod. Read-only."""
import re, sys, os, collections
root = r"<repos>/vermintide-2-tweaker"
mods = sys.argv[1:] or ["chaos_wastes_tweaker_dev", "event_tweaker", "enemy_tweaker"]
pat = re.compile(r'(\w+)\s*:\s*(hook|hook_safe|hook_origin)\s*\(\s*([^,\)]+)\s*,\s*("?[\w\.]+"?)?')
for m in mods:
    base = os.path.join(root, m, "scripts")
    rows = []
    for dp, dn, fn in os.walk(base):
        for f in fn:
            if not f.endswith(".lua"): continue
            p = os.path.join(dp, f)
            with open(p, encoding="utf-8", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    s = line.strip()
                    if s.startswith("--"): continue
                    code = line.split("--")[0]
                    for mm in pat.finditer(code):
                        rows.append((f, i, mm.group(1), mm.group(2), mm.group(3).strip(), (mm.group(4) or "").strip('"')))
    print("==", m, "hook sites:", len(rows))
    byfile = collections.Counter(r[0] for r in rows)
    bykind = collections.Counter(r[3] for r in rows)
    print("  kinds:", dict(bykind))
    for f, n in byfile.most_common():
        print("  %3d %s" % (n, f))
    if "-v" in os.environ.get("A4V", ""):
        for r in rows:
            print("   ", "%s:%d %s:%s(%s, %s)" % r)
