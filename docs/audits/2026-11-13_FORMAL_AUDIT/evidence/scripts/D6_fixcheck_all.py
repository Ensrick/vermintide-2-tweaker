# D6: automated "is the claimed fix still on master" survey for every closed issue.
# Method: commits on origin/master citing #N (subject first, body as fallback) -> identifiers ADDED (and not removed) by those
# commits in .lua files -> does each identifier still occur in origin/master .lua sources (anywhere / in the stable sibling tree)?
# Read-only git: log, show, grep.
import sys, os, re, subprocess, json, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
REPO = r'<repos>/vermintide-2-tweaker'
OUT = r'docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/D6_out'
def git(*a):
    return subprocess.run(['git', '-C', REPO] + list(a), capture_output=True, text=True, encoding='utf-8', errors='replace').stdout
PAIRS = {'chaos_wastes_tweaker_dev': 'chaos_wastes_tweaker', 'crafting_in_modded_dev': 'crafting_in_modded', 'general_tweaker_dev': 'general_tweaker',
         'gui_tweaker_dev': 'gui_tweaker', 'verminious_dreams_lighting_dev': 'verminious_dreams_lighting', 'weapon_tweaker': 'weapon_tweaker_dev'}
# 1. token index per top-level dir
idx_path = os.path.join(OUT, 'master_lua_tokens_by_dir.json')
if os.path.exists(idx_path):
    by_dir = {k: set(v) for k, v in json.load(open(idx_path, encoding='utf-8')).items()}
else:
    out = git('grep', '-I', '-o', '-E', r'[A-Za-z_][A-Za-z0-9_]{9,}', 'origin/master', '--', '*.lua')
    by_dir = collections.defaultdict(set)
    for ln in out.split('\n'):
        p = ln.split(':', 2)
        if len(p) == 3: by_dir[p[1].split('/', 1)[0]].add(p[2])
    json.dump({k: sorted(v) for k, v in by_dir.items()}, open(idx_path, 'w', encoding='utf-8'))
ALL = set().union(*by_dir.values())
# 2. commit -> issues
log = git('log', 'origin/master', '--no-merges', '--format=%H%x09%ad%x09%s%x09%b%x00', '--date=short')
subj = collections.defaultdict(list); body = collections.defaultdict(list)
REF = re.compile(r'(?<![\w/])#(\d{1,4})\b')
ncommits = 0
for rec in log.split('\x00'):
    rec = rec.strip('\n')
    if not rec: continue
    p = rec.split('\t', 3)
    if len(p) < 3: continue
    ncommits += 1
    sha, date, s = p[0], p[1], p[2]; b = p[3] if len(p) > 3 else ''
    for m in set(REF.findall(s)): subj[int(m)].append((sha, date, s))
    for m in set(REF.findall(b)) - set(REF.findall(s)): body[int(m)].append((sha, date, s))
DEF = [re.compile(r'function\s+([A-Za-z_][\w.:]*)\s*\('), re.compile(r'\b(mod\.[A-Za-z_]\w+)\s*='), re.compile(r'local\s+function\s+(\w+)'),
       re.compile(r'local\s+([A-Za-z_]\w{9,})\s*='), re.compile(r'["\']([a-z][a-z0-9_]{11,})["\']')]
def toks(lines):
    s = set()
    for ln in lines:
        if ln.lstrip().startswith('--'): continue
        for rx in DEF:
            for m in rx.finditer(ln):
                t = m.group(1).split('.')[-1].split(':')[-1]
                if len(t) >= 10 and not t.isupper(): s.add(t)
    return s
_show = {}
def commit_tokens(sha):
    if sha in _show: return _show[sha]
    diff = git('show', '--format=', '--unified=0', '--no-color', sha, '--', '*.lua')
    per = collections.defaultdict(lambda: ([], [])); cur = None
    for ln in diff.split('\n'):
        if ln.startswith('+++ b/'): cur = ln[6:].split('/', 1)[0]
        elif ln.startswith('+++ '): cur = None
        elif cur and ln.startswith('+') and not ln.startswith('+++'): per[cur][0].append(ln[1:])
        elif cur and ln.startswith('-') and not ln.startswith('---'): per[cur][1].append(ln[1:])
    res = {d: toks(a) - toks(r) for d, (a, r) in per.items()}
    _show[sha] = res; return res
def survey(n):
    cs = subj.get(n) or []
    src = 'subject'
    if not cs: cs = body.get(n) or []; src = 'body'
    cs = cs[:25]
    intro = collections.defaultdict(set)
    for sha, date, s in cs:
        for d, ts in commit_tokens(sha).items(): intro[d] |= ts
    alltok = set().union(*intro.values()) if intro else set()
    miss_any = sorted(t for t in alltok if t not in ALL)
    dev_tok = set(); stable_missing = set(); stable_dir = None
    for d, ts in intro.items():
        if d in PAIRS and d != 'weapon_tweaker':
            dev_tok |= ts; stable_dir = PAIRS[d]
            stable_missing |= {t for t in ts if t in by_dir.get(d, ()) and t not in by_dir.get(PAIRS[d], ())}
    dev_live = {t for t in dev_tok if any(t in by_dir.get(d, ()) for d in PAIRS)}
    return dict(n=n, src=src if cs else 'none', commits=len(cs), first=(cs[-1][1] if cs else ''), last=(cs[0][1] if cs else ''), ntok=len(alltok), miss_any=miss_any,
                dirs=sorted(intro), n_dev_live=len(dev_live), stable_missing=sorted(stable_missing), stable_dir=stable_dir)
if __name__ == '__main__':
    nums = [int(l.split('\t', 1)[0]) for i, l in enumerate(open(os.path.join(os.path.dirname(OUT), '..', 'data', 'closed_index.tsv'), encoding='utf-8')) if i]
    res = {}
    for k, n in enumerate(nums):
        res[n] = survey(n)
        if k % 100 == 0: print('..', k, file=sys.stderr); sys.stderr.flush()
    json.dump(res, open(os.path.join(OUT, 'fixcheck_all.json'), 'w', encoding='utf-8'))
    print('commits scanned', ncommits, 'issues', len(res))
    c = collections.Counter()
    for r in res.values():
        if r['commits'] == 0: c['no-commit'] += 1
        elif r['ntok'] == 0: c['commit-no-lua-token'] += 1
        else:
            pct = 100 * (r['ntok'] - len(r['miss_any'])) / r['ntok']
            c['>=90%' if pct >= 90 else ('60-90%' if pct >= 60 else '<60%')] += 1
    print(c)
