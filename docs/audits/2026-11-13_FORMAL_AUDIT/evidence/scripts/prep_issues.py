import json,sys,os,collections,re
A=sys.argv[1]; D=os.path.join(A,'data')
def load_concat(p):
    raw=open(p,encoding='utf-8').read(); dec=json.JSONDecoder(); i=0; out=[]
    while i<len(raw):
        while i<len(raw) and raw[i].isspace(): i+=1
        if i>=len(raw): break
        obj,j=dec.raw_decode(raw,i); out+=obj; i=j
    return out
openi=json.load(open(os.path.join(D,'open_issues.json'),encoding='utf-8'))
closed=[x for x in load_concat(os.path.join(D,'closed_raw.json')) if 'pull_request' not in x]
comments=load_concat(os.path.join(D,'comments_raw.json'))
by=collections.defaultdict(list)
for c in comments:
    n=int(c['issue_url'].rsplit('/',1)[1]); by[n].append(c)
print('open',len(openi),'closed',len(closed),'comments',len(comments))
def labels(x): return [l['name'] for l in x['labels']]
# bucket priority order
ORDER=[('A_weapons',['Tweaker: Weapons','CWV','WOC']),
       ('B_cosmetics',['Tweaker: Cosmetics','dcp','Character Dialogue']),
       ('C_cw_events_enemies',['Tweaker: Chaos Wastes','Tweaker: Events','Tweaker: Enemies']),
       ('D_cim_mp_career',['cim','Progression','Tweaker: Career']),
       ('E_gui',['Tweaker: GUI']),
       ('F_general_other',['Tweaker: General'])]
def bucket(x):
    L=set(labels(x))
    for name,keys in ORDER:
        if L & set(keys): return name
    return 'F_general_other'
def write(x,state,dirn):
    n=x['number']; cs=sorted(by.get(n,[]),key=lambda c:c['created_at'])
    p=os.path.join(dirn,f'{n}.md');
    with open(p,'w',encoding='utf-8') as f:
        f.write(f"# #{n} {x['title']}\n")
        f.write(f"state: {state} | author: {x['user']['login']} | created: {x['created_at'][:10]} | updated: {x['updated_at'][:10]} | closed: {(x.get('closed_at') or '')[:10]} | state_reason: {x.get('state_reason')}\n")
        f.write(f"labels: {', '.join(labels(x))}\n\n## BODY\n{x.get('body') or ''}\n")
        for c in cs:
            f.write(f"\n## COMMENT by {c['user']['login']} at {c['created_at']}\n{c.get('body') or ''}\n")
    return os.path.getsize(p)
od=os.path.join(A,'issues','open'); cd=os.path.join(A,'issues','closed'); os.makedirs(od,exist_ok=True); os.makedirs(cd,exist_ok=True)
bk=collections.defaultdict(list); sizes=collections.Counter()
for x in openi:
    b=bucket(x); bk[b].append(x); sizes[b]+=write(x,'open',od)
tot=0
for x in closed: tot+=write(x,'closed',cd)
for b,xs in sorted(bk.items()):
    with open(os.path.join(A,'data',f'bucket_{b}.tsv'),'w',encoding='utf-8') as f:
        f.write('number\tauthor\tcreated\tupdated\tn_comments\tlabels\ttitle\n')
        for x in sorted(xs,key=lambda x:x['number']):
            f.write('\t'.join([str(x['number']),x['user']['login'],x['created_at'][:10],x['updated_at'][:10],str(len(by.get(x['number'],[]))),','.join(labels(x)),x['title']])+'\n')
    print(b,len(xs),'issues',sizes[b]//1024,'KB')
with open(os.path.join(A,'data','closed_index.tsv'),'w',encoding='utf-8') as f:
    f.write('number\tauthor\tcreated\tclosed\tstate_reason\tn_comments\tlabels\ttitle\n')
    for x in sorted(closed,key=lambda x:x['number']):
        f.write('\t'.join([str(x['number']),x['user']['login'],x['created_at'][:10],(x.get('closed_at') or '')[:10],str(x.get('state_reason')),str(len(by.get(x['number'],[]))),','.join(labels(x)),x['title']])+'\n')
print('closed files KB',tot//1024)
# lifecycle & age stats
import datetime
now=datetime.date(2026,11,13)
life=collections.Counter();
for x in openi:
    L=labels(x); lc=[l for l in L if l in('verify-fix','diagnostics-armed','not-started')]
    life[tuple(lc)]+=1
print('lifecycle combos',life.most_common())
ages=[(now-datetime.date.fromisoformat(x['created_at'][:10])).days for x in openi]
ages.sort(); print('age days median',ages[len(ages)//2],'p90',ages[int(len(ages)*.9)],'max',ages[-1])
vf=[x for x in openi if 'verify-fix' in labels(x)]
print('verify-fix by author',collections.Counter(x['user']['login'] for x in vf).most_common())
print('non-owner open:')
for x in openi:
    if x['user']['login'] not in('Ensrick',): print('  ',x['number'],x['user']['login'],labels(x),x['title'][:70])
# closed per month, opened per month
om=collections.Counter(x['created_at'][:7] for x in openi+closed); cm=collections.Counter((x.get('closed_at') or '')[:7] for x in closed)
print('opened/closed per month:');
for m in sorted(set(om)|set(cm)): print('  ',m,om.get(m,0),cm.get(m,0))
