# D6 shared loader (read-only over the audit cache).
import json, os, re, collections, datetime
A = r'<audit-workspace>'
D = os.path.join(A, 'data')
def load_concat(p):
    raw = open(p, encoding='utf-8').read(); dec = json.JSONDecoder(); i = 0; out = []
    while i < len(raw):
        while i < len(raw) and raw[i].isspace(): i += 1
        if i >= len(raw): break
        obj, j = dec.raw_decode(raw, i); out += obj; i = j
    return out
def labels(x): return [l['name'] for l in x['labels']]
def ts(s): return datetime.datetime.strptime(s, '%Y-%m-%dT%H:%M:%SZ')
_cache = {}
def load():
    if _cache: return _cache
    openi = json.load(open(os.path.join(D, 'open_issues.json'), encoding='utf-8'))
    raw = load_concat(os.path.join(D, 'closed_raw.json'))
    closed = [x for x in raw if 'pull_request' not in x]
    prs = [x for x in raw if 'pull_request' in x]
    comments = load_concat(os.path.join(D, 'comments_raw.json'))
    by = collections.defaultdict(list)
    for c in comments: by[int(c['issue_url'].rsplit('/', 1)[1])].append(c)
    for v in by.values(): v.sort(key=lambda c: c['created_at'])
    tl = json.load(open(os.path.join(A, 'scripts', 'D6_out', 'timeline.json'), encoding='utf-8'))
    _cache.update(openi=openi, closed=closed, prs=prs, by=by, tl={int(k): v for k, v in tl.items()})
    return _cache
MOD_ORDER = [('CWV','cwv'),('WOC','woc'),('Tweaker: Weapons','wt'),('Tweaker: Cosmetics','cosmetics'),('dcp','dcp'),('Character Dialogue','dialogue'),
             ('Tweaker: Chaos Wastes','cw'),('Tweaker: Events','events'),('Tweaker: Enemies','enemies'),('cim','cim'),('Progression','mp'),
             ('Tweaker: Career','career'),('Tweaker: GUI','gut'),('Tweaker: General','gt')]
def mod_of(L):
    for k, v in MOD_ORDER:
        if k in L: return v
    return 'other'
def all_label_names():
    c = load(); cnt = collections.Counter()
    for x in c['closed'] + c['openi']:
        for l in labels(x): cnt[l] += 1
    return cnt
