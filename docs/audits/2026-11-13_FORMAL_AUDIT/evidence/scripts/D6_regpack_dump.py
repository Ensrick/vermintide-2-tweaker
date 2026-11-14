import sys, os, re, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import D6_lib as L, D6_classify as K
c = L.load()
nums = json.load(open(os.path.join(L.A, 'scripts', 'D6_out', 'regpack_numbers.json')))
want = [int(a) for a in sys.argv[2:]] or nums
cap = int(sys.argv[1])
FIX = re.compile(r'(\*\*Fix|Fix \(|Fix:|Fixed in|Resolved in|Resolved |Verified |Shipped|Implemented|shipped|Root cause|Closing|Closed|Done in|Both parts)', re.I)
for n in want:
    x = K.closed[n]; cs = c['by'].get(n, [])
    body = (x.get('body') or '').replace('\r', '')
    pick = None
    for cm in reversed(cs):
        if FIX.search(cm['body'] or ''): pick = cm['body']; break
    if pick is None:
        m = re.search(r'(\*\*Fix[^\n]*\n?.{0,%d}|## Fix.{0,%d})' % (cap, cap), body, re.S)
        pick = m.group(0) if m else body[-cap:]
    t = K.strip_att(pick).replace('\n', ' ')
    ids = sorted(set(re.findall(r'`([A-Za-z_][A-Za-z0-9_.:]{5,60})`', pick + ' ' + body)), key=len, reverse=True)[:10]
    print(f"### #{n} {x['title'][:100]}\n  FIX: {t[:cap]}\n  IDS: {', '.join(ids)}")
