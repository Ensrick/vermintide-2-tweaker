"""A2 engine-contact-surface counter (read-only). Usage: py -3 A2_surface.py <mod_dir>"""
import os, re, sys, collections
root = sys.argv[1]
pats = {
    'mod:hook(': re.compile(r'\bmod:hook\s*\('),
    'mod:hook_safe(': re.compile(r'\bmod:hook_safe\s*\('),
    'mod:hook_origin(': re.compile(r'\bmod:hook_origin\s*\('),
    'mod:network_register': re.compile(r'\bmod:network_register\s*\('),
    'mod:network_send': re.compile(r'\bmod:network_send\s*\('),
    'mod:command': re.compile(r'\bmod:command\s*\('),
    'mod:set(': re.compile(r'\bmod:set\s*\('),
    'mod:get(': re.compile(r'\bmod:get\s*\('),
    'pcall(': re.compile(r'\bpcall\s*\('),
    'rawset(': re.compile(r'\brawset\s*\('),
    'rawget(': re.compile(r'\brawget\s*\('),
    'get_mod(': re.compile(r'\bget_mod\s*\('),
    'mod:dofile': re.compile(r'\bmod:dofile\s*\('),
    '_rt_register/rt_register(': re.compile(r'\b_?rt_register\s*\('),
    'Managers.package:load': re.compile(r'package[_a-z]*:load\s*\('),
    'Managers.package:unload': re.compile(r'package[_a-z]*:unload\s*\('),
    'Application.': re.compile(r'\bApplication\.[a-z_]+\s*\('),
    'printf(': re.compile(r'\bprintf\b'),
}
tot = collections.Counter(); per = collections.defaultdict(collections.Counter)
hooks = []
hookre = re.compile(r'\bmod:(hook|hook_safe|hook_origin)\s*\(\s*([A-Za-z_][\w\.]*|"[^"]+")\s*,\s*"([^"]+)"')
for dp, dn, fn in os.walk(root):
    for f in fn:
        if not f.endswith('.lua'): continue
        p = os.path.join(dp, f)
        try: src = open(p, encoding='utf-8', errors='replace').read()
        except Exception as e: continue
        lines = src.split('\n')
        for i, l in enumerate(lines, 1):
            s = l.strip()
            if s.startswith('--'): continue
            for k, r in pats.items():
                n = len(r.findall(l))
                if n: tot[k] += n; per[f][k] += n
            for m in hookre.finditer(l):
                hooks.append((m.group(1), m.group(2).strip('"'), m.group(3), f, i))
print('== totals'); [print(f'{v:6d}  {k}') for k, v in tot.most_common()]
print('== hooks per file')
hc = collections.Counter(h[3] for h in hooks)
for f, n in hc.most_common(): print(f'{n:4d}  {f}')
print('== hook targets (kind class.method file:line)')
for h in sorted(hooks, key=lambda x: (x[1], x[2])): print(f'{h[0]:11s} {h[1]}.{h[2]}  {h[3]}:{h[4]}')
print('== duplicate (class,method) targets')
dc = collections.defaultdict(list)
for h in hooks: dc[(h[1], h[2])].append(h)
for k, v in sorted(dc.items()):
    if len(v) > 1: print(k, [(x[0], x[3], x[4]) for x in v])
print('total literal hooks:', len(hooks), 'unique targets:', len(dc))
