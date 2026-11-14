"""A4 helper: classify in-game regression checks by what their body reads. Read-only heuristics."""
import re, os, sys, collections
root = r"<repos>/vermintide-2-tweaker"
mods = ["chaos_wastes_tweaker_dev", "chaos_wastes_tweaker", "event_tweaker", "enemy_tweaker"]
start = re.compile(r'(?:_rt_register|rt_register|register_peer_check|_ct_rt_register|R\.register|register)\(\s*"([A-Za-z0-9_]+)"\s*,\s*function')
start2 = re.compile(r'name\s*=\s*"([A-Za-z0-9_]+)"\s*,\s*$')
ENGINE = re.compile(r'Managers\.|rawget\(_G|NetworkLookup|BuffTemplates|Breeds\b|DeusPowerUp|MutatorTemplates|LevelSettings|ScriptUnit|Unit\.|DEUS_|ProcFunctions|BuffFunctionTemplates|PickupSettings|Pickups\b|TerrorEvent|ConflictDirector|BossGrudgeMarks|BreedEnhancements|WindSettings|ItemMasterList|GameSettingsDevelopment')
MARKER = re.compile(r'[A-Z0-9_]*MARKER\b|SENTINEL|_VERIFIED\b')
PRES = re.compile(r'type\(mod\.[A-Za-z0-9_\.]+\)\s*~=\s*"(function|table)"')
CALL = re.compile(r'mod\.[A-Za-z0-9_]+\(|[A-Za-z_]+\.[a-z_]+\(')
for m in mods:
    base = os.path.join(root, m, "scripts")
    rows = []
    for dp, dn, fn in os.walk(base):
        for f in fn:
            if not f.endswith(".lua"): continue
            lines = open(os.path.join(dp, f), encoding="utf-8", errors="replace").read().splitlines()
            i = 0
            while i < len(lines):
                mm = start.search(lines[i])
                if mm:
                    name = mm.group(1); j = i + 1; body = []
                    depth_indent = len(lines[i]) - len(lines[i].lstrip())
                    while j < len(lines):
                        l = lines[j]
                        if re.match(r'^\s*end\)?\s*\)?\s*$', l) and (len(l) - len(l.lstrip())) <= depth_indent:
                            break
                        if not l.strip().startswith("--"): body.append(l)
                        j += 1
                    text = "\n".join(body)
                    eng = bool(ENGINE.search(text)); mk = bool(MARKER.search(text)); pr = bool(PRES.search(text))
                    if eng: cls = "engine-state"
                    elif mk and not CALL.search(re.sub(r'tostring\(|type\(|string\.\w+\(', '', text)): cls = "marker-constant"
                    elif mk: cls = "marker+logic"
                    elif pr and len(body) <= 12: cls = "presence-only"
                    else: cls = "mod-logic"
                    rows.append((f, i + 1, name, cls, len(body)))
                    i = j
                i += 1
    c = collections.Counter(r[3] for r in rows)
    print("==", m, "checks:", len(rows), dict(c))
    if "-v" in sys.argv:
        for r in sorted(rows, key=lambda r: (r[3], r[0], r[1])):
            print("   %-16s %s:%d %s (%d lines)" % (r[3], r[0], r[1], r[2], r[4]))
