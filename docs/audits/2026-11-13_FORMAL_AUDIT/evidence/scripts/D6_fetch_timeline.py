# D6: read-only GraphQL fetch of closing events for every closed issue (batched; ~25 queries).
import json, subprocess, sys, os, time
A = r'<audit-workspace>'
OUT = os.path.join(A, 'scripts', 'D6_out', 'timeline.json')
nums = []
for i, line in enumerate(open(os.path.join(A, 'data', 'closed_index.tsv'), encoding='utf-8')):
    if i == 0: continue
    nums.append(int(line.split('\t', 1)[0]))
res = {}
if os.path.exists(OUT):
    res = json.load(open(OUT, encoding='utf-8'))
FRAG = '''number stateReason closedAt
 timelineItems(itemTypes:[CLOSED_EVENT, REOPENED_EVENT, CROSS_REFERENCED_EVENT, CONNECTED_EVENT, REFERENCED_EVENT], first:100) { totalCount nodes { __typename
  ... on ClosedEvent { createdAt actor{login} stateReason closer { __typename ... on PullRequest { number title mergedAt } ... on Commit { oid messageHeadline } } }
  ... on ReopenedEvent { createdAt actor{login} }
  ... on CrossReferencedEvent { createdAt willCloseTarget source { __typename ... on PullRequest { number state merged title } ... on Issue { number state } } }
  ... on ConnectedEvent { createdAt subject { __typename ... on PullRequest { number } } }
  ... on ReferencedEvent { createdAt commit { oid messageHeadline } }
 } }'''
todo = [n for n in nums if str(n) not in res]
B = 25
for k in range(0, len(todo), B):
    chunk = todo[k:k+B]
    q = 'query { repository(owner:"Ensrick", name:"vermintide-2-tweaker") {\n' + '\n'.join(f'i{n}: issue(number:{n}) {{ {FRAG} }}' for n in chunk) + '\n} }'
    p = subprocess.run(['gh', 'api', 'graphql', '-f', 'query=' + q], capture_output=True, text=True, encoding='utf-8')
    if p.returncode != 0:
        print('ERR', chunk[0], p.stderr[:400]); sys.exit(1)
    d = json.loads(p.stdout)['data']['repository']
    for key, v in d.items():
        res[str(v['number'])] = v
    json.dump(res, open(OUT, 'w', encoding='utf-8'))
    print('fetched', len(res), '/', len(nums)); sys.stdout.flush()
    time.sleep(0.5)
print('done', len(res))
