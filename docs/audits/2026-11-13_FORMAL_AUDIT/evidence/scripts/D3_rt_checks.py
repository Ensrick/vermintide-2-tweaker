# D3: classify runtime regression checks (rt_register) by what they actually read. Read-only.
import re, sys, os, glob
R = r"<repos>/vermintide-2-tweaker"
trees = {
 "ct_dev": "chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev",
 "ct_official": "chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker",
 "enemy": "enemy_tweaker/scripts/mods/enemy_tweaker",
 "event": "event_tweaker/scripts/mods/event_tweaker",
}
pat = re.compile(r'rt_register\(\s*"([A-Za-z0-9_]+)"')
for tname, rel in trees.items():
    names = {}
    for f in glob.glob(os.path.join(R, rel, "*.lua")):
        src = open(f, encoding="utf-8", errors="replace").read()
        lines = src.split("\n")
        for m in pat.finditer(src):
            name = m.group(1)
            start = src.count("\n", 0, m.start())
            # take body until next rt_register or 80 lines
            body = []
            for i in range(start, min(len(lines), start + 80)):
                if i > start and "rt_register(" in lines[i]:
                    break
                body.append(lines[i])
            b = "\n".join(body)
            live = bool(re.search(r'Managers\.|ScriptUnit|Unit\.|World\.|NetworkLookup|rawget\(_G, "(Breeds|BuffTemplates|DeusPowerUp|Managers|NetworkLookup|LevelSettings|MutatorTemplates|WeaponTraits|GrudgeMark|BossGrudgeMarks|AreaSettings)', b))
            marker = bool(re.search(r'MARKER', b))
            fnpresence = bool(re.search(r'type\(mod\.[A-Za-z0-9_]+\) ~= "function"|type\(.*\) ~= "function"', b))
            kind = "live-state" if live else ("marker-only" if marker else ("fn-presence" if fnpresence else "other"))
            names[name] = (kind, os.path.basename(f), start + 1)
    from collections import Counter
    c = Counter(k for k, _, _ in names.values())
    print(tname, "checks=", len(names), dict(c))
    if "-v" in sys.argv:
        for n, (k, f, l) in sorted(names.items()):
            print("   ", k, n, f"{f}:{l}")
