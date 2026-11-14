"""A2: measure the shared `_om` god-object in CWV (fields, writers, readers) and comment ratio. Read-only."""
import os, re, sys, collections
root = sys.argv[1]; objname = sys.argv[2] if len(sys.argv) > 2 else '_om'
fields_w = collections.defaultdict(set); fields_r = collections.defaultdict(set)
wre = re.compile(r'(?<![\w.])' + re.escape(objname) + r'\.([A-Za-z_]\w*)\s*(?:,\s*[\w.]+\s*)*=(?!=)')
rre = re.compile(r'(?<![\w.])' + re.escape(objname) + r'\.([A-Za-z_]\w*)')
fre = re.compile(r'function\s+' + re.escape(objname) + r'\.([A-Za-z_]\w*)')
tot_lines = tot_comment = tot_blank = 0
files_using = 0
per_file = {}
for dp, dn, fn in os.walk(root):
    for f in sorted(fn):
        if not f.endswith('.lua'): continue
        src = open(os.path.join(dp, f), encoding='utf-8', errors='replace').read().split('\n')
        c = b = 0; used = False
        for l in src:
            s = l.strip()
            if not s: b += 1; continue
            if s.startswith('--'): c += 1; continue
            code = l.split('--')[0] if '--' in l and '"' not in l else l
            for m in wre.finditer(code): fields_w[m.group(1)].add(f)
            for m in fre.finditer(code): fields_w[m.group(1)].add(f)
            for m in rre.finditer(code): fields_r[m.group(1)].add(f); used = True
        tot_lines += len(src); tot_comment += c; tot_blank += b
        per_file[f] = (len(src), c)
        if used: files_using += 1
allf = set(fields_w) | set(fields_r)
print(f'object {objname}: distinct fields={len(allf)} written={len(fields_w)} files_touching={files_using}')
multi = {k: v for k, v in fields_w.items() if len(v) > 1}
print('fields written from >1 file:', len(multi))
for k, v in sorted(multi.items(), key=lambda kv: -len(kv[1]))[:25]: print('   ', k, sorted(v))
never_written = sorted(k for k in fields_r if k not in fields_w)
print('fields read but never assigned via `obj.x =` (may be set via table ctor / other alias):', len(never_written))
print('   ', never_written[:60])
written_never_read_elsewhere = sorted(k for k in fields_w if fields_r[k] <= fields_w[k] and len(fields_r[k]) <= 1)
print('fields only touched in a single file:', len(written_never_read_elsewhere))
cross = sorted(((len(fields_r[k] | fields_w[k]), k) for k in allf), reverse=True)[:20]
print('most widely shared fields (files, name):', cross)
print(f'LOC total={tot_lines} comment-only lines={tot_comment} ({100*tot_comment/tot_lines:.1f}%) blank={tot_blank} code~={tot_lines-tot_comment-tot_blank}')
worst = sorted(((c/max(n,1), f, n, c) for f, (n, c) in per_file.items() if n > 150), reverse=True)[:12]
print('highest comment ratio (files >150 lines):'); [print(f'   {r:.0%} {f} ({c}/{n})') for r, f, n, c in worst]
