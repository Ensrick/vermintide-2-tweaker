import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import D6_lib as L, D6_classify as K
c = L.load(); by = c['by']
le = K.le
def show(n, before=6, cap=150):
    x = K.closed[n]
    items = []
    for e in le[str(n)]['timelineItems']['nodes']:
        nm = e['label']['name'] if e['label'] else '?'
        if nm in ('Fixed', 'verify-fix', 'diagnostics-armed', 'not-started', 'verify-fix-coop', 'duplicate', 'wontfix', 'deferred', 'verify-in-game', 'probe-live', 'blocked'):
            items.append((e['createdAt'], ('+' if e['__typename'] == 'LabeledEvent' else '-') + nm))
    for cm in by.get(n, []):
        b = K.strip_att(cm['body']).replace('\n', ' / ')
        items.append((cm['created_at'], f"{'H' if K.is_human_typed(cm) else 'a'}[{cm['user']['login'][:7]}] {b[:cap]}"))
    for e in c['tl'][n]['timelineItems']['nodes']:
        if e['__typename'] == 'ClosedEvent':
            cl = e['closer']; items.append((e['createdAt'], 'CLOSED ' + ('manual' if cl is None else ('PR#%d' % cl['number'] if cl['__typename'] == 'PullRequest' else 'commit ' + cl['oid'][:8]))))
        elif e['__typename'] == 'ReopenedEvent': items.append((e['createdAt'], 'REOPENED'))
    items.sort()
    ci = max(i for i, it in enumerate(items) if it[1].startswith('CLOSED'))
    print(f"=== #{n} [{x['state_reason']}] {x['title'][:80]} | {','.join(L.labels(x))[:90]}")
    # merge same-second label events
    out = []
    for t, s in items[max(0, ci - before): ]:
        if out and out[-1][0][:16] == t[:16] and s[0] in '+-' and out[-1][1][0] in '+-': out[-1] = (out[-1][0], out[-1][1] + ' ' + s)
        else: out.append((t, s))
    for t, s in out: print('   ', t[5:16], s)
if __name__ == '__main__':
    args = sys.argv[1:]
    before = 6; cap = 150
    for n in args: show(int(n), before, cap)
