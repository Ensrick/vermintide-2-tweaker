import sys; sys.path.insert(0, r'docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts')
import D6_lib as L, collections, re, datetime
c = L.load(); tl = c['tl']; by = c['by']
def close_info(x):
    n = x['number']
    nodes = tl[n]['timelineItems']['nodes']
    ce = [e for e in nodes if e['__typename'] == 'ClosedEvent']
    last = ce[-1]; t = L.ts(last['createdAt'])
    cl = last['closer']
    kind = 'MANUAL' if cl is None else ('PR' if cl['__typename'] == 'PullRequest' else 'COMMIT')
    cs = by.get(n, [])
    near = [cm for cm in cs if abs((L.ts(cm['created_at']) - t).total_seconds()) <= 600]
    before = [cm for cm in cs if L.ts(cm['created_at']) <= t + datetime.timedelta(seconds=600)]
    after = [cm for cm in cs if L.ts(cm['created_at']) > t + datetime.timedelta(seconds=600)]
    return dict(t=t, kind=kind, closer=cl, near=near, before=before, after=after, n_close=len(ce),
                reopened=sum(1 for e in nodes if e['__typename'] == 'ReopenedEvent'))
if __name__ == '__main__':
    want = [int(a) for a in sys.argv[2:]]
    cap = int(sys.argv[1])
    idx = {x['number']: x for x in c['closed']}
    for n in want:
        x = idx[n]; ci = close_info(x)
        print(f"=== #{n} [{x['state_reason']}] {x['title'][:110]}\n    labels: {', '.join(L.labels(x))} | closed {ci['t']} via {ci['kind']} {('PR#'+str(ci['closer']['number'])) if ci['kind']=='PR' else (ci['closer']['oid'][:8]+' '+ci['closer']['messageHeadline'][:60] if ci['kind']=='COMMIT' else '')} | comments total {len(by.get(n,[]))} near-close {len(ci['near'])} after {len(ci['after'])}")
        show = ci['near'][-1:] if ci['near'] else ci['before'][-1:]
        for cm in show:
            b = (cm['body'] or '').replace('\r', '')
            tag = 'NEAR' if ci['near'] else 'LAST-BEFORE'
            print(f"    [{tag} {cm['user']['login']} {cm['created_at']}] " + b[:cap].replace('\n', '\n      '))
        if not show: print('    [no comment before close]')
