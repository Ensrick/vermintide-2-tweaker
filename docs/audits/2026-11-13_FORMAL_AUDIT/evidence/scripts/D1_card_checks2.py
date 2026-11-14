# D1 helper 2: wider net for named checks in the newest real card AND the issue body.
import os, re, json
A = r'<audit-workspace>'
REPO = r'<repos>/vermintide-2-tweaker'
d = json.load(open(os.path.join(A, 'scripts', 'D1_card_checks_out.json')))
SKIP = {'.git', '.temp', 'node_modules', 'bundleV2', '.claude', '.worktrees'}
blob = {}
for root, dirs, files in os.walk(REPO):
    dirs[:] = [x for x in dirs if x not in SKIP]
    for f in files:
        if f.endswith('.lua') and '/scripts/mods/' in root.replace(os.sep, '/') + '/':
            p = os.path.join(root, f)
            blob[os.path.relpath(p, REPO).replace(os.sep, '/')] = open(p, encoding='utf-8', errors='replace').read()
def find(name):
    q1, q2 = '"' + name + '"', "'" + name + "'"
    return [k for k, v in blob.items() if q1 in v or q2 in v]
PAT = [re.compile(r'\b((?:cwv_|cos_|woc_|cim_|wt_|gut_)?issue\d+(?:_\d+)?_[a-z0-9_]+)\b'),
       re.compile(r'PASS: `?([a-z][a-z0-9_]+)'), re.compile(r'`([a-z][a-z0-9_]+)`?: PASS'),
       re.compile(r'`((?:cwv|cos|woc|cim|wt)_[a-z0-9_]*(?:safe|guards|coverage|scoped|gate|installed|registered|contract|valid|parity)[a-z0-9_]*)`'),
       re.compile(r'`([a-z0-9_]*(?:_guards|_ungated|_all_senders))`')]
def comments(text):
    parts = re.split(r'^## COMMENT by (\S+) at (\S+)\s*$', text, flags=re.M)
    return parts[0], [(parts[i], parts[i + 1], parts[i + 2]) for i in range(1, len(parts), 3)]
lines = []
for r in d['rows']:
    n = r['n']
    text = open(os.path.join(A, 'issues', 'open', f'{n}.md'), encoding='utf-8', errors='replace').read()
    body, cs = comments(text)
    cards = [b for (a, t, b) in cs if re.search(r'^## CURRENT LIVE TEST', b, re.M)]
    card = cards[-1] if cards else ''
    for where, t in (('card', card), ('body', body)):
        names = set()
        for p in PAT:
            names |= set(p.findall(t))
        for nm in sorted(names):
            h = find(nm)
            lines.append(f"#{n}\t{where}\t{nm}\t{'MISSING' if not h else h[0].split('/')[-1]}")
open(os.path.join(A, 'scripts', 'D1_card_checks2_out.tsv'), 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
print(len(lines), 'names;', sum(1 for l in lines if l.endswith('MISSING')), 'missing')
for l in lines:
    if l.endswith('MISSING'): print(l)
