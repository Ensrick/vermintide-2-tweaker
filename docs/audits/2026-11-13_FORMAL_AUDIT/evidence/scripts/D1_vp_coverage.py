# D1 round 2: coverage proof for plan/vp/D1.md.
# Every issue of the D1 bucket must appear exactly once across:
#   (a) the first column of the section 1 "No rig needed" table,
#   (b) the "Issues" field of a VP card,
#   (c) the first column of the section 4 "Owner only" table.
# Usage: py -3 scripts/D1_vp_coverage.py [--write]   (--write replaces the result block in the file)
import os, re, sys, collections

A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VP = os.path.join(A, 'plan', 'vp', 'D1.md')
DIG = os.path.join(A, 'issues', 'digest', 'D1_cwv_woc_open_digest.md')
text = open(VP, encoding='utf-8').read()
bucket = [int(m) for m in re.findall(r'^=== #(\d+) \[open\]', open(DIG, encoding='utf-8').read(), re.M)]

def section(start_pat, end_pat):
    s = re.search(start_pat, text, re.M)
    e = re.search(end_pat, text[s.end():], re.M)
    return text[s.end(): s.end() + (e.start() if e else len(text))]

def first_col_issues(block):
    out = []
    for line in block.split('\n'):
        m = re.match(r'^\| #(\d+) \|', line)
        if m:
            out.append(int(m.group(1)))
    return out

norig = first_col_issues(section(r'^## 1\. No rig needed', r'^## 2\. '))
owner = first_col_issues(section(r'^## 4\. Owner only', r'^## 5\. '))
packs = collections.OrderedDict()
for m in re.finditer(r'^### (VP-D1-\d+) [^\n]*\n(.*?)(?=^### VP-D1-|^## 3\. )', text, re.M | re.S):
    vid, body = m.group(1), m.group(2)
    row = re.search(r'^\| Issues \| (.*) \|$', body, re.M)
    packs[vid] = [int(x) for x in re.findall(r'#(\d+)', row.group(1))] if row else []
where = collections.defaultdict(list)
for n in norig: where[n].append('no-rig')
for n in owner: where[n].append('owner-only')
for vid, nums in packs.items():
    for n in nums: where[n].append(vid)
missing = sorted(set(bucket) - set(where))
extra = sorted(set(where) - set(bucket))
dup = sorted(n for n, w in where.items() if len(w) != 1)
classes = collections.Counter()
for vid, body in re.findall(r'^### (VP-D1-\d+) [^\n]*\n(.*?)(?=^### VP-D1-|^## 3\. )', text, re.M | re.S):
    row = re.search(r'^\| Issues \| (.*) \|$', body, re.M)
    for cls in re.findall(r'#\d+ \(([A-Z])', row.group(1)):
        classes[cls] += 1
pack_total = sum(len(v) for v in packs.values())
lines = [
    '```',
    f'bucket issues            : {len(bucket)}',
    f'section 1 no-rig rows    : {len(norig)}  {sorted(norig)}',
    f'VP cards                 : {len(packs)}',
    f'issues in VP Issues field: {pack_total}  (by class: ' + ', '.join(f'{k}={v}' for k, v in sorted(classes.items())) + ')',
    f'section 4 owner-only rows: {len(owner)}  {sorted(owner)}',
    f'sum                      : {len(norig) + pack_total + len(owner)}',
    f'missing from the file    : {missing}',
    f'not in the bucket        : {extra}',
    f'listed more than once    : {dup}',
    'per card                 : ' + '; '.join(f'{k[-2:]}={len(v)}' for k, v in packs.items()),
    'verdict                  : ' + ('PASS (each of the 71 issues appears exactly once)'
                                    if not missing and not extra and not dup and len(where) == len(bucket) == 71 else 'FAIL'),
    '```',
]
out = '\n'.join(lines)
print(out)
if '--write' in sys.argv:
    new, n = re.subn(r'(Result of the last run is recorded below by the script\'s own output:\n\n).*?(\n\n## 6\. )',
                     lambda m: m.group(1) + out + m.group(2), text, flags=re.S)
    assert n == 1, 'result block not found'
    open(VP, 'w', encoding='utf-8', newline='\n').write(new)
    print('written')
