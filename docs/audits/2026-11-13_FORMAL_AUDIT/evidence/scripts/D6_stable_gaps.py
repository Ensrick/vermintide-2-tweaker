# D6 round 2: table of closed issues whose fix identifiers exist in the _dev tree but not in the stable sibling (origin/master).
import sys, os, json, subprocess, re
REPO = r'<repos>/vermintide-2-tweaker'
OUT = r'docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/D6_out'
def git(*a): return subprocess.run(['git', '-C', REPO] + list(a), capture_output=True, text=True, encoding='utf-8', errors='replace').stdout
rows = json.load(open(os.path.join(OUT, 'ledger_rows.json'), encoding='utf-8'))
fc = {int(k): v for k, v in json.load(open(os.path.join(OUT, 'fixcheck_all.json'), encoding='utf-8')).items()}
DEV = {'chaos_wastes_tweaker': 'chaos_wastes_tweaker_dev', 'general_tweaker': 'general_tweaker_dev', 'crafting_in_modded': 'crafting_in_modded_dev'}
stable_files = {s: set(os.path.basename(p) for p in git('ls-tree', '-r', '--name-only', 'origin/master', '--', s + '/scripts').split('\n') if p) for s in DEV}
def score(t):
    s = len(t)
    if re.search(r'\d{2,4}', t): s += 30
    if t.startswith('_'): s += 10
    if '_' not in t: s -= 15
    return s
out = []
for r in rows:
    if not (r['runtime'] and r['devonly']): continue
    f = fc[r['number']]; sd = f['stable_dir']; dd = DEV[sd]
    picked = []
    for t in sorted(f['stable_missing'], key=score, reverse=True):
        hit = git('grep', '-n', '-I', '-w', '-F', '-e', t, 'origin/master', '--', dd + '/scripts').split('\n')
        hit = [h for h in hit if h]
        if not hit: continue
        # prefer a definition line
        best = next((h for h in hit if re.search(r'(function\s+[\w.:]*%s|%s\s*=|_rt_register\(\s*["\']%s)' % (re.escape(t), re.escape(t), re.escape(t)), h)), hit[0])
        p = best.split(':', 3); path, line = p[1], p[2]
        cnt = git('grep', '-c', '-I', '-w', '-F', '-e', t, 'origin/master', '--', sd)
        n_stable = sum(int(l.rsplit(':', 1)[1]) for l in cnt.split('\n') if l)
        if n_stable: continue
        picked.append((t, path, line, os.path.basename(path) in stable_files[sd]))
        if len(picked) == 2: break
    out.append(dict(n=r['number'], mod=r['mod'], sd=sd, dd=dd, typ=r['typ'], prio=r['prio'], title=r['title'], picked=picked, nmiss=len(f['stable_missing']), ndev=f['n_dev_live'], ev=r['ev'], closed=r['closed']))
json.dump(out, open(os.path.join(OUT, 'stable_gaps.json'), 'w', encoding='utf-8'))
for o in out:
    print(f"#{o['n']} {o['mod']} {o['typ']} {o['prio'][:1] or '-'} {o['nmiss']}/{o['ndev']} | {o['title'][:60]}")
    for t, path, line, same in o['picked']: print(f"     {t} @ {path}:{line} | same file in stable: {same}")
