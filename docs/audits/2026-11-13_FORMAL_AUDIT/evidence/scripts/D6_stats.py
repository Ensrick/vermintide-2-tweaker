import sys, os, json, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import D6_lib as L, D6_classify as K, D6_build as B
C = collections.Counter
rows = json.load(open(os.path.join(B.OUT, 'ledger_rows.json'), encoding='utf-8'))
rt = [r for r in rows if r['runtime']]
print('TOTAL', len(rows), 'reason', dict(C(r['reason'] for r in rows)), 'cat', dict(C(r['cat'] for r in rows)))
print('completed by cat', dict(C(r['cat'] for r in rows if r['reason'] == 'completed')))
print('final-close kind', dict(C(r['kind'] for r in rows)))
print('mech (all)', C(r['mech'] for r in rows).most_common())
print('mech (runtime completed)', C(r['mech'] for r in rt).most_common())
print('--- evidence, runtime completed', len(rt), dict(C(r['ev'] for r in rt)))
# A decomposition using direct recomputation
det = {}
for x in L.load()['closed']:
    r = B.analyse(x); det[x['number']] = r
def bucket(r):
    d = det[r['number']]
    if r['ev'] != 'A': return r['ev']
    if d['sub'] in ('A1', 'A1?'): return 'A-human-text'
    if d['sub'] == 'A3': return 'A-label-only'
    if d['sub'] == 'A-post': return 'A-post'
    # A2: is there also human-typed positive text or Fixed label?
    return 'A-agent-attributed' + ('+FixedLabel' if d['fixed_at_close'] else '')
print('A decomposition', C(bucket(r) for r in rt).most_common())
# human text anywhere pre-close
import datetime
def has_human_pos(n):
    x = K.closed[n]; d = det[n]; t = d['t_close'] + datetime.timedelta(minutes=10)
    for cm in L.load()['by'].get(n, []):
        if L.ts(cm['created_at']) <= t and B.is_human(cm) and B.POS.search(B.strip_att(cm['body'])): return True
    return False
A = [r for r in rt if r['ev'] == 'A']
hp = sum(1 for r in A if has_human_pos(r['number'])); fl = sum(1 for r in A if r['fixed_at_close'])
both = sum(1 for r in A if has_human_pos(r['number']) or r['fixed_at_close'])
print('A total', len(A), 'with human-typed positive text', hp, 'with Fixed label at close', fl, 'either', both, 'agent-attribution only', len(A) - both)
print('--- per mod (runtime completed): mod: n A B C D n-a | crash-or-critical C/D')
mods = collections.defaultdict(list)
for r in rt: mods[r['mod'].rstrip('?')].append(r)
for m, rs in sorted(mods.items(), key=lambda kv: -len(kv[1])):
    e = C(r['ev'] for r in rs)
    cd = sum(1 for r in rs if r['ev'] in ('C', 'D') and (r['typ'] == 'crash' or r['prio'] in ('0-critical', '1-major')))
    print(f"{m}\t{len(rs)}\t{e['A']}\t{e['B']}\t{e['C']}\t{e['D']}\t{e['n-a']}\t{cd}")
print('--- by type', {t: dict(C(r['ev'] for r in rt if r['typ'] == t)) for t in ('crash', 'bug', 'enhancement', 'feature', 'unlabelled')})
print('--- by closed month', {m: dict(C(r['ev'] for r in rt if r['closed'][:7] == m)) for m in sorted({r['closed'][:7] for r in rt})})
print('--- lifecycle at close (runtime completed)', C('+'.join(r['life_close']) or '(none)' for r in rt).most_common())
print('lifecycle at close x ev', sorted(C(('+'.join(r['life_close']) or '(none)', r['ev']) for r in rt).items()))
cur = [r for r in rows if r['reason'] == 'completed']
print('--- validation: read manually', sum(1 for r in rt if r['read']), 'of', len(rt))
rd = [r for r in rt if r['read']]
print('script_ev vs final among read:', sorted(C((r['script_ev'], r['ev']) for r in rd).items()))
print('overrides that changed class:', sum(1 for r in rd if r['script_ev'] != r['ev']), 'of', len(rd))
print('unread runtime completed', C(r['ev'] for r in rt if not r['read']))
print('--- recommendation', C(r['rec'].split(':')[0] for r in rows).most_common(), 'runtime', C(r['rec'].split(':')[0] for r in rt).most_common())
rv = [r for r in rt if r['rec'].startswith('REVERIFY')]
print('REVERIFY by typ/prio', C((r['typ'], r['prio']) for r in rv).most_common())
print('REVERIFY by mod', C(r['mod'].rstrip('?') for r in rv).most_common())
print('never-runtime-verified (C+D) runtime completed', sum(1 for r in rt if r['ev'] in ('C', 'D')), 'crash', sum(1 for r in rt if r['ev'] in ('C', 'D') and r['typ'] == 'crash'), 'critical/major', sum(1 for r in rt if r['ev'] in ('C', 'D') and r['prio'] in ('0-critical', '1-major')))
print('dev-only fixes (runtime completed)', sum(1 for r in rt if r['devonly']), C(r['mod'].rstrip('?') for r in rt if r['devonly']).most_common())
print('fix col', C(r['fix'] for r in rt).most_common())
print('referenced by open: closed issues', sum(1 for r in rows if r['refs']), 'runtime completed', sum(1 for r in rt if r['refs']))
print('silent closes', sum(1 for r in rows if r['silent']), 'runtime completed', sum(1 for r in rt if r['silent']))
