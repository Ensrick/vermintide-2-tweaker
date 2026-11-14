# D5 VP coverage check: every bucket issue appears exactly once across
# (a) first column of the section 1 tables, (b) a pack's "| Issues |" row, (c) the "Owner only" line.
# Usage: py -3 scripts/D5_vp_coverage.py [--write]   (--write replaces the result block in plan/vp/D5.md)
import os, re, sys, collections

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VP = os.path.join(BASE, 'plan', 'vp', 'D5.md')
BUCKET = os.path.join(BASE, 'data', 'bucket_F_general_other.tsv')

text = open(VP, encoding='utf-8').read()
bucket = sorted(int(l.split('\t')[0]) for l in open(BUCKET, encoding='utf-8').read().splitlines()[1:])

s1 = text.split('\n## 1. ', 1)[1].split('\n## 2. ', 1)[0]
s2 = text.split('\n## 2. ', 1)[1].split('\n## 3. ', 1)[0]

places = collections.defaultdict(list)

# (a) no-rig rows: first cell is exactly one issue number
for line in s1.splitlines():
    m = re.match(r'^\|\s*#(\d+)\s*\|', line)
    if m:
        places[int(m.group(1))].append('no-rig')

# (c) owner only line (inside section 1)
for line in s1.splitlines():
    if line.startswith('Owner only:'):
        head = line.split('.', 1)[0]
        for n in re.findall(r'#(\d+)', head):
            places[int(n)].append('owner-only')

# (b) pack Issues rows
current = None
for line in s2.splitlines():
    h = re.match(r'^### (VP-D5-\d+)', line)
    if h:
        current = h.group(1)
    m = re.match(r'^\|\s*Issues\s*\|(.*)\|\s*$', line)
    if m and current:
        for n in re.findall(r'#(\d+)', m.group(1)):
            places[int(n)].append(current)

missing = [n for n in bucket if n not in places]
extra = sorted(n for n in places if n not in bucket)
dupes = {n: p for n, p in places.items() if len(p) != 1}
norig = sorted(n for n, p in places.items() if p == ['no-rig'])
owner = sorted(n for n, p in places.items() if p == ['owner-only'])
packs = collections.defaultdict(list)
for n, p in places.items():
    if len(p) == 1 and p[0].startswith('VP-'):
        packs[p[0]].append(n)
in_packs = sum(len(v) for v in packs.values())

ok = not missing and not extra and not dupes and len(places) == len(bucket) == 54
lines = []
lines.append('Result of the last run: %s.' % ('PASS' if ok else 'FAIL'))
lines.append('')
lines.append('| Location | Count | Issues |')
lines.append('|---|---|---|')
lines.append('| Section 1 no-rig tables | %d | %s |' % (len(norig), ' '.join(str(n) for n in norig)))
lines.append('| Owner only | %d | %s |' % (len(owner), ' '.join(str(n) for n in owner)))
for k in sorted(packs):
    lines.append('| %s | %d | %s |' % (k, len(packs[k]), ' '.join(str(n) for n in sorted(packs[k]))))
lines.append('| Total | %d | bucket has %d; missing %d; placed twice %d; not in bucket %d |' % (
    len(norig) + len(owner) + in_packs, len(bucket), len(missing), len(dupes), len(extra)))
block = '\n'.join(lines)
print(block)
if missing: print('MISSING', missing)
if dupes: print('DUPES', dupes)
if extra: print('EXTRA', extra)

if '--write' in sys.argv:
    start = '<!-- coverage:start -->'
    end = '<!-- coverage:end -->'
    new_block = start + '\n' + block + '\n' + end
    if 'COVERAGE-RESULT-PLACEHOLDER' in text:
        text = text.replace('COVERAGE-RESULT-PLACEHOLDER', new_block)
    else:
        text = re.sub(re.escape(start) + r'.*?' + re.escape(end), lambda _: new_block, text, flags=re.S)
    open(VP, 'w', encoding='utf-8', newline='\n').write(text)
    print('written')
sys.exit(0 if ok else 1)
