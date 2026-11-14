# D6: open issues that describe a CLOSED issue as regressed / recurring / same symptom / incomplete.
import sys, os, re, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import D6_lib as L, D6_classify as K
c = L.load(); by = c['by']
STRONG = re.compile(r"(regress(ion|ed|es|ing)? (of|from|in|on|against|introduced|caused)|regression of closed|re-?regress\w*|recur\w*|re-?open\w*|same (symptom|class|bug|crash|root cause|failure|signature|defect|mechanism|family)|not (actually |fully |really )?fixed|came back|resurfac\w*|reappear\w*|incomplete|did not fix|didn't fix|insufficient|residual|never (actually )?(worked|verified|fixed|tested)|unverified|was closed (without|before)|closed prematurely|reintroduc\w*|re-?broke\w*|still (broken|crash\w*|fail\w*|happen\w*|occur\w*|repro\w*|present|there|wrong)|sibling of closed|supersed\w+ closed|follow-?up (to|of) closed|closed-but|again\b|twin of|duplicate of closed|un-?fixed)", re.I)
NOISE = re.compile(r"regression[ _-](test|check|suite|coverage|guard|marker|net|proof|run|harness|control|lock)", re.I)
def pairs():
    out = []
    for o in c['openi']:
        texts = [('body', o.get('body') or '', o['created_at'])] + [('c', cm['body'] or '', cm['created_at']) for cm in by.get(o['number'], [])]
        best = {}
        for kind, tx, when in texts:
            for m in K.REF.finditer(tx):
                k = int(m.group(1))
                if k not in K.closed or k == o['number']: continue
                lo = max(0, m.start() - 110); hi = min(len(tx), m.end() + 110)
                ctx = tx[lo:hi].replace('\r', '').replace('\n', ' ')
                ctx2 = NOISE.sub('', ctx)
                sg = sorted({mm.group(0).lower() for mm in STRONG.finditer(ctx2)})
                if sg and (k not in best or len(sg) > len(best[k][1])): best[k] = (ctx, sg, when[:10])
        for k, (ctx, sg, when) in best.items(): out.append((k, o['number'], sg, ctx, when))
    return out
if __name__ == '__main__':
    P = pairs()
    byc = collections.defaultdict(list)
    for k, o, sg, ctx, when in P: byc[k].append((o, sg, ctx, when))
    print('pairs', len(P), 'closed issues', len(byc))
    with open(os.path.join(L.A, 'scripts', 'D6_out', 'openref_signals.txt'), 'w', encoding='utf-8') as f:
        for k in sorted(byc, key=lambda k: (-len(byc[k]), k)):
            x = K.closed[k]; r = K.analyse(x)
            f.write(f"## closed #{k} [{x['state_reason'][:4]} {str(r['t_close'])[:10]} ev={r['ev']} {r['mod']} {r['typ']} {r['prio'][:1]}] {x['title'][:90]}\n")
            for o, sg, ctx, when in sorted(byc[k]):
                f.write(f"   open #{o} ({when}) [{'/'.join(sg)[:50]}]: ...{ctx}...\n")
    print('written')
