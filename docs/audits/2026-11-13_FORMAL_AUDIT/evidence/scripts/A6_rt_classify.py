# A6: classify gt_dev in-game regression checks (/gt_regression_test) by what their body does.
# Usage: py -3 A6_rt_classify.py <gt_dev script dir> <out.tsv>
# Classes (first match wins):
#   CALLS_PRODUCTION  the body invokes a mod function (directly, or through `local f = mod._x`) or a policy function
#   READS_STATE       the body reads live engine state (Managers, ScriptUnit, script_data, engine tables)
#   DATA_SHAPE        the body inspects the settings data or localization tables
#   MARKER_ONLY       the body only compares marker constants, flags, or types of fields
#   OTHER             none of the above
import re, sys, os, glob, io
d, out = sys.argv[1], sys.argv[2]
ALIAS = re.compile(r'local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*mod\.(_?[A-Za-z0-9_]+)\s*$', re.M)
POLICY = re.compile(r'[Pp]olicy[A-Za-z0-9_]*\.[A-Za-z_]+\(|\.should_[a-z_]+\(|\.validate_[a-z_]+\(|\.is_eligible\(|\.reconcile\(|\.prepare_utility_inputs\(|\.runtime_check\(')
STATE = re.compile(r'Managers\.|ScriptUnit\.|script_data|BotConstants|NetworkLookup|\bBreeds\b|RagdollSettings|PlayerUnitMovementSettings|World\.get_data')
DATA = re.compile(r'_data"\)|pcall\(require|mod:localize|_localization"\)')
MARKER = re.compile(r'MARKER|_wired\b|_armed\b|~= true then|type\([^)]*\) ~= "(function|table|number)"')
rows = []
for f in sorted(glob.glob(os.path.join(d, '*.lua'))):
    lines = io.open(f, encoding='utf-8', errors='replace').read().split('\n')
    starts = [i for i, l in enumerate(lines) if re.search(r'_rt_register\(\s*"', l) and not l.strip().startswith('--')]
    for k, i in enumerate(starts):
        name = re.search(r'_rt_register\(\s*"([^"]+)"', lines[i]).group(1)
        end = starts[k + 1] if k + 1 < len(starts) else min(len(lines), i + 200)
        body = '\n'.join(l for l in lines[i:end] if not l.strip().startswith('--'))
        calls = [c for c in re.findall(r'mod\.(_?[A-Za-z0-9_]+)\(', body) if c != '_gt_rt_register']
        for alias, target in ALIAS.findall(body):
            if re.search(r'(?<![A-Za-z0-9_.:])' + re.escape(alias) + r'\(', body) or re.search(r'pcall\(\s*' + re.escape(alias) + r'[,) ]', body):
                calls.append(target)
        if calls or POLICY.search(body):
            cls = 'CALLS_PRODUCTION'
        elif STATE.search(body):
            cls = 'READS_STATE'
        elif DATA.search(body):
            cls = 'DATA_SHAPE'
        elif MARKER.search(body):
            cls = 'MARKER_ONLY'
        else:
            cls = 'OTHER'
        rows.append((os.path.basename(f), i + 1, name, cls, ','.join(sorted(set(calls)))[:90], 'yes' if MARKER.search(body) else ''))
with io.open(out, 'w', encoding='utf-8', newline='\n') as fh:
    fh.write('file\tline\tcheck\tclass\tmod_functions_called\talso_tests_marker\n')
    for r in rows:
        fh.write('\t'.join(str(x) for x in r) + '\n')
from collections import Counter
print(len(rows), dict(Counter(r[3] for r in rows)))
