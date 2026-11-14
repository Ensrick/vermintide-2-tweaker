# D6: for a closed issue, find commits on origin/master citing it, extract identifiers the fix introduced in .lua files,
# and test whether they still exist in origin/master .lua sources. Read-only git commands only (log, show, grep).
import sys, os, re, subprocess, json
REPO = r'<repos>/vermintide-2-tweaker'
OUT = r'docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/D6_out'
def git(*a):
    p = subprocess.run(['git', '-C', REPO] + list(a), capture_output=True, text=True, encoding='utf-8', errors='replace')
    return p.stdout
_idx = None
def lua_index():
    global _idx
    if _idx is None:
        f = os.path.join(OUT, 'master_lua_tokens.txt')
        if not os.path.exists(f):
            out = git('grep', '-h', '-o', '-I', '-E', r'[A-Za-z_][A-Za-z0-9_]{5,}', 'origin/master', '--', '*.lua')
            open(f, 'w', encoding='utf-8').write('\n'.join(sorted(set(out.split('\n')))))
        _idx = set(open(f, encoding='utf-8').read().split('\n'))
    return _idx
DEF = [re.compile(r'function\s+([A-Za-z_][\w.:]*)\s*\('), re.compile(r'\b(mod\.[A-Za-z_]\w+)\s*='), re.compile(r'local\s+function\s+(\w+)'),
       re.compile(r'local\s+([A-Za-z_]\w{9,})\s*='), re.compile(r'["\']([a-z][a-z0-9_]{11,})["\']'), re.compile(r'\[([a-z_]+:[\w-]+)\]')]
def tokens(lines):
    s = set()
    for ln in lines:
        if ln.lstrip().startswith('--'): continue
        for rx in DEF:
            for m in rx.finditer(ln):
                t = m.group(1).split('.')[-1].split(':')[-1]
                if len(t) >= 10 and not t.isupper(): s.add(t)
    return s
def check(n, max_commits=30):
    log = git('log', 'origin/master', '--no-merges', '-E', f'--grep=#{n}([^0-9]|$)', '--format=%H%x09%ad%x09%s', '--date=short')
    commits = [l.split('\t') for l in log.strip().split('\n') if l.strip()]
    intro = {}; files = set()
    for sha, date, subj in commits[:max_commits]:
        diff = git('show', '--format=', '--unified=0', '--no-color', sha, '--', '*.lua')
        add = []; rem = []; cur = None
        for ln in diff.split('\n'):
            if ln.startswith('+++ b/'): cur = ln[6:]; files.add(cur)
            elif ln.startswith('+') and not ln.startswith('+++'): add.append(ln[1:])
            elif ln.startswith('-') and not ln.startswith('---'): rem.append(ln[1:])
        new = tokens(add) - tokens(rem)
        for t in new: intro.setdefault(t, sha[:8])
    idx = lua_index()
    missing = sorted(t for t in intro if t not in idx)
    return dict(n=n, commits=len(commits), first=(commits[-1][1] if commits else ''), subjects=[c[2][:80] for c in commits[:4]], ntok=len(intro), missing=missing, files=sorted(files)[:6], nfiles=len(files))
if __name__ == '__main__':
    res = []
    for a in sys.argv[1:]:
        r = check(int(a)); res.append(r)
        pct = (100 * (r['ntok'] - len(r['missing'])) // r['ntok']) if r['ntok'] else -1
        print(f"#{r['n']}: commits={r['commits']} first={r['first']} lua_files={r['nfiles']} tokens={r['ntok']} present={pct}% missing={len(r['missing'])} :: {', '.join(r['missing'][:14])}")
        if r['commits'] and r['ntok'] == 0: print('     subjects:', ' | '.join(r['subjects']))
    json.dump(res, open(os.path.join(OUT, 'fixcheck_last.json'), 'w', encoding='utf-8'))
