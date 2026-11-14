# D1 helper: static unit-path registration check for CWV + WOC + Cosmetics illusions.
# A "units/..." literal handed to the engine must be either (a) a vanilla unit (named somewhere in the
# decompiled source) or (b) a unit authored inside the mod directory. Anything else is a candidate
# "unit not found / package not registered" at spawn.
import os, re, collections
SRC = r'<repos>/Vermintide-2-Source-Code'
REPO = r'<repos>/vermintide-2-tweaker'
A = r'<audit-workspace>'
U = re.compile(r'"(units/[A-Za-z0-9_/\.]+)"')
van = set()
for root, dirs, files in os.walk(SRC):
    dirs[:] = [d for d in dirs if d != '.git']
    for f in files:
        if f.endswith('.lua'):
            try: s = open(os.path.join(root, f), encoding='utf-8', errors='replace').read()
            except OSError: continue
            van.update(U.findall(s))
print('vanilla unit literals:', len(van))
res = []
for mod in ('character_weapon_variants', 'weapons_of_chaos'):
    base = os.path.join(REPO, mod)
    own = set()
    for root, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if d not in ('bundleV2', 'art_source', '.git')]
        for f in files:
            if f.endswith('.unit'):
                own.add(os.path.relpath(os.path.join(root, f), base).replace(os.sep, '/')[:-5])
    pk = ''
    rp = os.path.join(base, 'resource_packages')
    if os.path.isdir(rp):
        for root, dirs, files in os.walk(rp):
            for f in files:
                pk += open(os.path.join(root, f), encoding='utf-8', errors='replace').read()
    sdir = os.path.join(base, 'scripts', 'mods', mod)
    seen = collections.OrderedDict()
    for f in sorted(os.listdir(sdir)):
        if not f.endswith('.lua') or 'regression' in f: continue
        for i, line in enumerate(open(os.path.join(sdir, f), encoding='utf-8', errors='replace'), 1):
            code = line.split('--')[0]
            for p in U.findall(code):
                seen.setdefault(p, (f, i))
    n_v = n_o = 0
    for p, (f, i) in seen.items():
        b = p[:-3] if p.endswith('_3p') else p
        if p in van or b in van or (p + '_3p') in van: n_v += 1; continue
        if p in own or b in own:
            n_o += 1
            if p not in pk and b not in pk and p.split('/')[-1] not in pk:
                res.append((mod, f, i, p, 'OWN_UNIT_NOT_IN_PACKAGE_FILE'))
            continue
        res.append((mod, f, i, p, 'NOT_VANILLA_NOT_OWN'))
    print(mod, 'unit literals', len(seen), 'vanilla', n_v, 'own', n_o, 'own .unit files', len(own))
open(os.path.join(A, 'scripts', 'D1_unit_paths_out.tsv'), 'w', encoding='utf-8').write('\n'.join('\t'.join(map(str, r)) for r in res) + '\n')
print('unresolved:', len(res))
for r in res[:60]: print('\t'.join(map(str, r)))
