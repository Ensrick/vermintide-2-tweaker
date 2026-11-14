# D6: read-only GraphQL fetch of label events for every closed issue (batched).
import json, subprocess, sys, os, time
A = r'<audit-workspace>'
OUT = os.path.join(A, 'scripts', 'D6_out', 'label_events.json')
nums = [int(l.split('\t', 1)[0]) for i, l in enumerate(open(os.path.join(A, 'data', 'closed_index.tsv'), encoding='utf-8')) if i]
res = json.load(open(OUT, encoding='utf-8')) if os.path.exists(OUT) else {}
FRAG = '''number
 timelineItems(itemTypes:[LABELED_EVENT, UNLABELED_EVENT], first:100) { totalCount nodes { __typename
  ... on LabeledEvent { createdAt actor{login} label{name} }
  ... on UnlabeledEvent { createdAt actor{login} label{name} }
 } }'''
todo = [n for n in nums if str(n) not in res]
B = 30
for k in range(0, len(todo), B):
    chunk = todo[k:k+B]
    q = 'query { repository(owner:"Ensrick", name:"vermintide-2-tweaker") {\n' + '\n'.join(f'i{n}: issue(number:{n}) {{ {FRAG} }}' for n in chunk) + '\n} }'
    p = subprocess.run(['gh', 'api', 'graphql', '-f', 'query=' + q], capture_output=True, text=True, encoding='utf-8')
    if p.returncode != 0:
        print('ERR', chunk[0], p.stderr[:400]); sys.exit(1)
    d = json.loads(p.stdout)['data']['repository']
    for key, v in d.items(): res[str(v['number'])] = v
    json.dump(res, open(OUT, 'w', encoding='utf-8'))
    time.sleep(0.4)
print('done', len(res), 'truncated', sum(1 for v in res.values() if v['timelineItems']['totalCount'] > 100))
