# A5 helper: list hook registrations (class, method) per mod, with file:line. Read-only.
import re, sys, os, collections
root = r"<repos>/vermintide-2-tweaker"
mods = sys.argv[1:] or ["crafting_in_modded_dev", "modded_progression", "career_tweaker"]
pat = re.compile(r'^\s*(?:local\s+\w+\s*=\s*)?(?:[\w\.]+\s*=\s*)?(\w+)[:.](hook|hook_safe|hook_origin)\(\s*([^,]+?)\s*,\s*("[^"]+"|[\w\.]+)')
for m in mods:
    rows = []
    for dp, dn, fn in os.walk(os.path.join(root, m, "scripts")):
        for f in fn:
            if not f.endswith(".lua"): continue
            p = os.path.join(dp, f)
            with open(p, encoding="utf-8", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    s = line.strip()
                    if s.startswith("--"): continue
                    mm = pat.match(line)
                    if mm:
                        rows.append((mm.group(3).strip('"'), mm.group(4).strip('"'), mm.group(2), f, i))
    print("== %s: %d hook sites" % (m, len(rows)))
    cnt = collections.Counter((r[0], r[1]) for r in rows)
    dups = [k for k, v in cnt.items() if v > 1]
    print("   duplicates (same class+method registered >1x in mod):", dups)
    byclass = collections.Counter(r[0] for r in rows)
    for c, n in byclass.most_common():
        print("   %-45s %d" % (c, n))
    if "-v" in os.environ.get("A5V", ""):
        for r in sorted(rows):
            print("     %s.%s [%s] %s:%d" % r)
