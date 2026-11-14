import sys, os, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import D6_lib as L, D6_classify as K
c = L.load()
orefs = K.open_refs()
def one(n, capc=230, nv=3):
    x = K.closed[n]; r = K.analyse(x)
    out = [f"#{n} [{r['reason'][:4]}] {r['kind']}{(' '+r['closer']) if r['closer'] else ''} {str(r['t_close'])[:10]} | {r['mod']} {r['cat']} {r['typ']} {r['prio'][:1]} | life={','.join(r['lifecycle_at_close'])} | ev={r['ev']} | reop={r['reopened']} | {r['author'][:8]} | {r['title'][:90]}"]
    for v in r['verdicts'][-nv:]:
        out.append(f"   v {str(v[0])[5:10]} {v[1]} {v[2][:6]}: {v[3][:125]}".replace('\n', ' '))
    show = r['near'][-1:] or r['pre'][-1:]
    for cm in show:
        b = K.strip_att(cm['body']).replace('\n', ' ')
        out.append(f"   close[{cm['created_at'][5:10]} {'H' if K.is_human_typed(cm) else 'a'}]: {b[:capc]}")
    if r['post']:
        cm = r['post'][-1]
        out.append(f"   post({len(r['post'])})[{cm['created_at'][:10]}]: {K.strip_att(cm['body']).replace(chr(10), ' ')[:150]}")
    refs = orefs.get(n, [])
    sig = [(o, s) for o, ctx, s in refs if s]
    if refs:
        out.append(f"   openrefs={len(refs)} sig: " + '; '.join(f"#{o}:{'/'.join(s)[:34]}" for o, s in sig[:6]))
    return '\n'.join(out)
if __name__ == '__main__':
    for n in [int(a) for a in sys.argv[1:]]: print(one(n))
