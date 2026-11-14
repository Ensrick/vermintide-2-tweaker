# D1 auditor helper (read-only on the repo): for every issue in the D1 bucket, take the newest REAL
# "## CURRENT LIVE TEST" card and verify that every named regression check, chat command and build
# version it cites actually exists in master source.
import os, re, sys, json, io
A = r'<audit-workspace>'
REPO = r'<repos>/vermintide-2-tweaker'
DIG = os.path.join(A, 'issues', 'digest', 'D1_cwv_woc_open_digest.md')
nums = [int(m.group(1)) for m in re.finditer(r'^=== #(\d+) \[open\]', open(DIG, encoding='utf-8').read(), re.M)]
# ---- load lua source (active mod dirs only)
SKIP = {'.git', '.temp', 'node_modules', 'bundleV2', '.claude', '.worktrees'}
src = {}
for root, dirs, files in os.walk(REPO):
    dirs[:] = [d for d in dirs if d not in SKIP]
    for f in files:
        if f.endswith('.lua'):
            p = os.path.join(root, f)
            try:
                src[os.path.relpath(p, REPO).replace(os.sep, '/')] = open(p, encoding='utf-8', errors='replace').read()
            except OSError:
                pass
blob_mod = {k: v for k, v in src.items() if '/scripts/mods/' in k}
def find_literal(name):
    hits = []
    q1, q2 = '"' + name + '"', "'" + name + "'"
    for k, v in blob_mod.items():
        if q1 in v or q2 in v:
            hits.append(k)
    return hits
def find_command(cmd):
    pat = re.compile(r'mod:command\(\s*["\']' + re.escape(cmd) + r'["\']')
    return [k for k, v in blob_mod.items() if pat.search(v)]
versions = {}
for k, v in blob_mod.items():
    m = re.search(r'^local MOD_VERSION\s*=\s*"([^"]+)"', v, re.M)
    if m:
        versions[k.split('/')[0]] = m.group(1)
def split_comments(text):
    parts = re.split(r'^## COMMENT by (\S+) at (\S+)\s*$', text, flags=re.M)
    out = []
    for i in range(1, len(parts), 3):
        out.append((parts[i], parts[i + 1], parts[i + 2]))
    return out
CHECK_RE = re.compile(r'`([a-z][a-z0-9]*(?:_[a-z0-9]+){2,})`')
CMD_RE = re.compile(r'`/([a-z][a-z0-9_]+)')
VER_RE = re.compile(r'v?(\d+\.\d+\.\d+(?:-(?:dev|beta|alpha))?)')
NOT_CHECKS = re.compile(r'^(es|dr|we|wh|bw|woc|cwv_es|cwv_dr|units|wpn|rpc|slot|one_handed|two_handed|player|attack|to|la|imperial|we_|unlock)_')
rows = []
for n in nums:
    p = os.path.join(A, 'issues', 'open', f'{n}.md')
    text = open(p, encoding='utf-8', errors='replace').read()
    labels = re.search(r'^labels: (.*)$', text, re.M).group(1)
    cs = split_comments(text)
    cards = [(a, t, b) for (a, t, b) in cs if re.search(r'^## CURRENT LIVE TEST', b, re.M)]
    row = {'n': n, 'labels': labels, 'ncards': len(cards), 'card_date': None, 'checks': {}, 'cmds': {}, 'versions': [], 'last_comment': cs[-1][1][:10] if cs else None, 'ncomments': len(cs)}
    if cards:
        a, t, b = cards[-1]
        row['card_date'] = t[:10]
        row['card_is_last_real'] = True
        for name in sorted(set(CHECK_RE.findall(b))):
            if NOT_CHECKS.match(name):
                continue
            row['checks'][name] = find_literal(name)
        for cmd in sorted(set(CMD_RE.findall(b))):
            row['cmds'][cmd] = find_command(cmd)
        row['versions'] = sorted(set(VER_RE.findall(b.split('**Expected')[0])))[:8]
    rows.append(row)
json.dump({'versions': versions, 'rows': rows}, open(os.path.join(A, 'scripts', 'D1_card_checks_out.json'), 'w'), indent=1)
out = io.StringIO()
out.write('MOD_VERSION on master: ' + ', '.join(f'{k}={v}' for k, v in sorted(versions.items())) + '\n\n')
for r in rows:
    miss_checks = [c for c, h in r['checks'].items() if not h]
    miss_cmds = [c for c, h in r['cmds'].items() if not h]
    out.write(f"#{r['n']} card={r['card_date']} ({r['ncards']} cards) last_comment={r['last_comment']} versions={r['versions']}\n")
    out.write(f"   labels: {r['labels']}\n")
    for c, h in r['checks'].items():
        out.write(f"   check {c}: {'MISSING' if not h else h[0] + (' +%d' % (len(h) - 1) if len(h) > 1 else '')}\n")
    for c, h in r['cmds'].items():
        out.write(f"   cmd /{c}: {'MISSING' if not h else h[0]}\n")
open(os.path.join(A, 'scripts', 'D1_card_checks_out.txt'), 'w', encoding='utf-8').write(out.getvalue())
print('issues', len(rows), 'lua files', len(src), 'mod lua', len(blob_mod))
