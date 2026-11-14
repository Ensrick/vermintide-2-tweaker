# D6 round 2: assemble plan/vp/CLOSED.md from the authored fragments plus generated tables.
# Read-only over the audit cache; git is only used by D6_stable_gaps_table.py (already run).
import sys, os, re, json, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import D6_lib as L
from D6_tables import LINK, LINK_WHY, MAN
OUT = os.path.join(L.A, 'scripts', 'D6_out')
c = L.load()
closed = {x['number']: x for x in c['closed']}
openi = {x['number']: x for x in c['openi']}
rows = {r['number']: r for r in json.load(open(os.path.join(OUT, 'ledger_rows.json'), encoding='utf-8'))}

def clean(s):
    return s.replace('\u2014', '-').replace('\u2013', '-').replace('|', '/').replace('\n', ' ').strip()

def reason(n):
    w = LINK_WHY.get(n)
    if n in MAN and MAN[n][3] and n in (174, 568, 495):
        w = MAN[n][3] + (' ' + w if w and n != 174 else '')
    return clean(w or '')

def for_comment(t, o):
    t = re.sub(r'(open|reopened) #%d(?!\d)' % o, 'this issue', t)
    t = re.sub(r'#%d(?!\d)' % o, 'this issue', t)
    t = re.sub(r'^this issue( [(][^)]*[)])?: ', 'reported here: ', t)
    return t

# ---------------- Part 2
lk = [r for r in rows.values() if r['rec'].startswith('LINK-TO-OPEN')]
by_open = collections.defaultdict(list)
for r in lk: by_open[int(r['rec'].split(':')[1])].append(r)
p2 = []
p2.append('## Part 2. LINK (closed issues whose symptom an OPEN issue already owns)\n')
p2.append('%d closed issues map onto %d open issues. Post ONE comment per open issue, using the text block under its table. Do not reopen any closed issue in this part. Do not edit labels.\n' % (len(lk), len(by_open)))
p2.append('How each closed issue ended: `completed` rows were closed as fixed; `not_planned` and `duplicate` rows were consolidated. "Evidence" is the round 1 evidence class of the closed issue (A = human in-game confirmation, B = session log, C = static only, D = none, n-a = not a runtime fix).\n')
def sev(o):
    L_ = [l['name'] for l in openi[o]['labels']]
    return ({'0-critical': 0, '1-major': 1, '2-moderate': 2, '3-low': 3}.get(next((p for p in ('0-critical', '1-major', '2-moderate', '3-low') if p in L_), ''), 4), -len(by_open[o]), o)
for o in sorted(by_open, key=sev):
    ox = openi[o]; ol = [l['name'] for l in ox['labels']]
    prio = next((p for p in ('0-critical', '1-major', '2-moderate', '3-low') if p in ol), 'no priority')
    life = next((p for p in ('verify-fix', 'diagnostics-armed', 'not-started') if p in ol), 'no lifecycle')
    rs = sorted(by_open[o], key=lambda r: r['number'])
    p2.append('### Open #%d %s (%s, %s): %d closed predecessor%s\n' % (o, clean(ox['title']), prio, life, len(rs), '' if len(rs) == 1 else 's'))
    p2.append('| Closed issue | Open issue that tracks it | One-line reason |')
    p2.append('|---|---|---|')
    for r in rs:
        x = closed[r['number']]
        p2.append('| #%d %s (%s %s, evidence %s) | #%d | %s |' % (r['number'], clean(x['title'])[:70], r['reason'], r['closed'], r['ev'], o, reason(r['number'])))
    p2.append('')
    p2.append('Comment to post on #%d:\n' % o)
    p2.append('```')
    p2.append('Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:')
    for r in rs:
        x = closed[r['number']]
        how = {'completed': 'closed as fixed', 'not_planned': 'closed not planned', 'duplicate': 'closed as duplicate'}[r['reason']]
        p2.append('- #%d (%s %s): %s' % (r['number'], how, r['closed'], for_comment(reason(r['number']), o)))
    p2.append('Their acceptance is owed here. They stay closed.')
    p2.append('```\n')

# flat index
p2.append('### Flat index (closed issue -> open issue)\n')
p2.append('| Closed | Open | Closed | Open | Closed | Open | Closed | Open |')
p2.append('|---|---|---|---|---|---|---|---|')
flat = sorted((r['number'], int(r['rec'].split(':')[1])) for r in lk)
for i in range(0, len(flat), 4):
    cells = []
    for a, b in flat[i:i + 4]: cells += ['#%d' % a, '#%d' % b]
    while len(cells) < 8: cells.append('')
    p2.append('| ' + ' | '.join(cells) + ' |')
p2.append('')

# ---------------- Part 4 table
gap_lines = open(os.path.join(OUT, 'stable_gaps_table.md'), encoding='utf-8').read().split('\n')
def gap_table(tag):
    out = ['| Issue | Fix identifier | Present in dev at path:line | Absent in stable (hits) | Crash-class? | Same-named file exists in stable? |', '|---|---|---|---|---|---|']
    on = False
    for ln in gap_lines:
        if ln in ('CW', 'GT'): on = (ln == tag); continue
        if on and ln.startswith('|'):
            cells = [c_.strip() for c_ in ln.strip().strip('|').split(' | ')]
            m = re.search(r'= (\d+)$', cells[3])
            cells[3] = m.group(1) if m else cells[3]
            out.append('| ' + ' | '.join(clean(x) if i == 0 else x for i, x in enumerate(cells)) + ' |')
    return out

p1 = open(os.path.join(OUT, 'closed_part1.md'), encoding='utf-8').read().rstrip() + '\n'
p3 = open(os.path.join(OUT, 'closed_part3.md'), encoding='utf-8').read().rstrip() + '\n'
p4 = open(os.path.join(OUT, 'closed_part4.md'), encoding='utf-8').read()
p4 = p4.replace('{{CW_TABLE}}', '\n'.join(gap_table('CW'))).replace('{{GT_TABLE}}', '\n'.join(gap_table('GT'))).rstrip() + '\n'
text = p1 + '\n' + '\n'.join(p2) + '\n' + p3 + '\n' + p4
dst = os.path.join(L.A, 'plan', 'vp')
os.makedirs(dst, exist_ok=True)
open(os.path.join(dst, 'CLOSED.md'), 'w', encoding='utf-8', newline='\n').write(text)
print('written', os.path.join(dst, 'CLOSED.md'), len(text), 'chars;', 'LINK rows', len(lk), 'open targets', len(by_open))
print('em dashes:', text.count('\u2014'), 'personal paths:', len(re.findall(r'C:\\\\Users|/c/Users', text)))
