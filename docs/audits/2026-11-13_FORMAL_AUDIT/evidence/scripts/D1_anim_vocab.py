# D1 helper: static anim-event vocabulary check for CWV + WOC.
# Every third-person anim event a mod hands to the engine is encoded through NetworkLookup.anims
# (Vermintide-2-Source-Code/scripts/network_lookup/anims_lookup_table.lua). A name that is neither
# in that table nor appended by the mod is a candidate "does not contain key" fatal / silent no-op.
import os, re, sys, collections
SRC = r'<repos>/Vermintide-2-Source-Code'
REPO = r'<repos>/vermintide-2-tweaker'
A = r'<audit-workspace>'
t = open(os.path.join(SRC, 'scripts', 'network_lookup', 'anims_lookup_table.lua'), encoding='utf-8-sig').read()
anims = set(re.findall(r'^\t"([^"]+)",', t, re.M))
# every anim-ish string that vanilla weapon templates / career / state code uses (1P+3P vocabulary proxy)
van = collections.Counter()
KEYRE = re.compile(r'\b([a-z_0-9]*anim[a-z_0-9]*|[a-z_0-9]*_event|wield_anim[a-z_0-9]*)\s*=\s*"([^"]+)"')
for root, dirs, files in os.walk(os.path.join(SRC, 'scripts')):
    for f in files:
        if f.endswith('.lua'):
            try: s = open(os.path.join(root, f), encoding='utf-8', errors='replace').read()
            except OSError: continue
            for k, v in KEYRE.findall(s):
                van[v] += 1
out = []
for mod in ('character_weapon_variants', 'weapons_of_chaos'):
    base = os.path.join(REPO, mod, 'scripts', 'mods', mod)
    for f in sorted(os.listdir(base)):
        if not f.endswith('.lua') or f.startswith('_lib_') or 'regression' in f: continue
        for i, line in enumerate(open(os.path.join(base, f), encoding='utf-8', errors='replace'), 1):
            code = line.split('--')[0]
            for k, v in KEYRE.findall(code):
                if 'sound' in k or 'wwise' in k or 'proc' in k: continue
                if not re.match(r'^[a-z][a-z0-9_]+$', v): continue
                if v in anims: continue
                out.append((mod, f, i, k, v, 'vanilla_uses_%d' % van[v] if van[v] else 'NOT_IN_VANILLA'))
open(os.path.join(A, 'scripts', 'D1_anim_vocab_out.tsv'), 'w', encoding='utf-8').write(
    '\n'.join('\t'.join(map(str, r)) for r in out) + '\n')
print('NetworkLookup.anims static entries:', len(anims), '; non-member anim/event literals:', len(out))
c = collections.Counter((r[4], r[5]) for r in out)
for (v, st), n in sorted(c.items(), key=lambda x: (x[0][1], -x[1])):
    print(f'{n:4d} {st:18s} {v}')
