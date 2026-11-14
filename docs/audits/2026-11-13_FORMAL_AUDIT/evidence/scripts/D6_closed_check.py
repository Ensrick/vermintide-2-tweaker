import re, collections
t = open(r'docs/program/vp\CLOSED.md', encoding='utf-8').read()
lines = t.split('\n')
bad = 0; cur_cols = None
for i, ln in enumerate(lines):
    if ln.startswith('|'):
        n = len(ln.strip().strip('|').split(' | '))
        if cur_cols is None: cur_cols = n
        elif n != cur_cols and not set(ln.replace('|', '').strip()) <= set('-'):
            bad += 1; print('line', i + 1, 'cells', n, 'expected', cur_cols, ':', ln[:100])
    else: cur_cols = None
print('table rows with a wrong cell count:', bad)
print('non-ascii chars:', sorted(set(ch for ch in t if ord(ch) > 127)))
print('VP cards:', len(re.findall(r'^### VP-CL-\d\d ', t, re.M)), '| case rows:', sum(1 for l in lines if l.startswith('| `qa/')))
print('LINK table rows:', sum(1 for l in lines if re.match(r'^\| #\d+ .*\(evidence ', l)), '| comment blocks:', t.count('Comment to post on #'))
nums = collections.Counter(int(m) for m in re.findall(r'^\| #(\d+) ', t, re.M))
print('words:', len(t.split()))
