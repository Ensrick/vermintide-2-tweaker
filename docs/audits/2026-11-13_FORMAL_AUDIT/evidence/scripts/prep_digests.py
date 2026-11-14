import json,sys,os,collections,re,datetime
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
for c in comments: by[int(c['issue_url'].rsplit('/',1)[1])].append(c)
for v in by.values(): v.sort(key=lambda c:c['created_at'])
state={x['number']:'open' for x in openi}; state.update({x['number']:'closed' for x in closed})
title={x['number']:x['title'] for x in openi+closed}
def labels(x): return [l['name'] for l in x['labels']]
def cap(s,n):
    s=(s or '').replace('\r',''); return s if len(s)<=n else s[:n]+f'\n...[truncated {len(s)-n} chars]'
ref_re=re.compile(r'(?<![\w/])#(\d{2,4})\b')
def refs(x):
    t=(x.get('body') or '')+'\n'+'\n'.join(c.get('body') or '' for c in by.get(x['number'],[]))
    return sorted({int(m) for m in ref_re.findall(t) if int(m)!=x['number'] and int(m) in state})
def digest(x,st,bcap,ccap,ncom):
    n=x['number']; cs=by.get(n,[])
    out=[f"=== #{n} [{st}] {x['title']}",
         f"author={x['user']['login']} created={x['created_at'][:10]} updated={x['updated_at'][:10]} closed={(x.get('closed_at') or '')[:10]} reason={x.get('state_reason')} comments={len(cs)}",
         f"labels: {', '.join(labels(x))}"]
    r=refs(x)
    if r: out.append('refs: '+' '.join(f"#{m}({state[m][0]})" for m in r[:40]))
    out.append('--- body'); out.append(cap(x.get('body'),bcap))
    cards=[c for c in cs if 'CURRENT LIVE TEST' in (c.get('body') or '')]
    shown=set()
    if cards and st=='open':
        c=cards[-1]; shown.add(c['id']); out.append(f"--- newest CURRENT LIVE TEST card ({c['created_at'][:10]}, {len(cards)} cards total)"); out.append(cap(c['body'],2200))
    rest=[c for c in cs if c['id'] not in shown and 'CURRENT LIVE TEST' not in (c.get('body') or '')]
    humans=[c for c in rest if c['user']['login']!='Ensrick']
    for c in humans[-2:]:
        shown.add(c['id']); out.append(f"--- non-owner comment by {c['user']['login']} {c['created_at'][:10]}"); out.append(cap(c['body'],900))
    for c in [c for c in rest if c['id'] not in shown][-ncom:]:
        out.append(f"--- comment by {c['user']['login']} {c['created_at'][:10]}"); out.append(cap(c['body'],ccap))
    return '\n'.join(out)+'\n\n'
ORDER=[('D1_cwv_woc',['CWV','WOC']),('D2_wt_cosmetics',['Tweaker: Weapons','Tweaker: Cosmetics','dcp','Character Dialogue']),
       ('D3_cw_events_enemies',['Tweaker: Chaos Wastes','Tweaker: Events','Tweaker: Enemies']),
       ('D4_cim_mp_career_gui',['cim','Progression','Tweaker: Career','Tweaker: GUI']),('D5_general_other',[])]
def bucket(x):
    L=set(labels(x))
    for name,keys in ORDER:
        if L & set(keys): return name
    return 'D5_general_other'
os.makedirs(os.path.join(A,'issues','digest'),exist_ok=True)
bk=collections.defaultdict(list)
for x in sorted(openi,key=lambda x:x['number']): bk[bucket(x)].append(x)
for b,xs in bk.items():
    p=os.path.join(A,'issues','digest',f'{b}_open_digest.md')
    with open(p,'w',encoding='utf-8') as f:
        for x in xs: f.write(digest(x,'open',3000,1000,2))
    print(b,len(xs),os.path.getsize(p)//1024,'KB', 'lines',sum(1 for _ in open(p,encoding='utf-8')))
# closed signals
open_refs=collections.Counter()
for x in openi:
    for m in refs(x):
        if state[m]=='closed': open_refs[m]+=1
conf_re=re.compile(r'(user confirmed|confirmed in[- ]game|verified in[- ]game|in-game confirm|works now|confirmed working|confirmed fixed|RainReligion confirmed|Ensrick confirmed|live[- ]test(ed)? pass|PASS\b)',re.I)
rows=[]
for x in closed:
    n=x['number']; cs=by.get(n,[]); L=labels(x)
    txt=(x.get('body') or '')+'\n'+'\n'.join(c.get('body') or '' for c in cs)
    has_conf=bool(conf_re.search(txt)); nonowner=sum(1 for c in cs if c['user']['login']!='Ensrick')
    lifecycle=[l for l in L if l in('verify-fix','diagnostics-armed','not-started')]
    score=0
    if x.get('state_reason')=='completed':
        score+=3*min(open_refs.get(n,0),3)
        if 'verify-fix' in L or 'diagnostics-armed' in L: score+=3
        if not has_conf: score+=2
        if 'bug' in L or 'crash' in L: score+=1
        if 'tooling' in L or 'documentation' in L or 'audit' in L: score-=4
    rows.append((score,n,x['user']['login'],(x.get('closed_at') or '')[:10],x.get('state_reason'),open_refs.get(n,0),int(has_conf),nonowner,','.join(L),x['title']))
rows.sort(reverse=True)
with open(os.path.join(D,'closed_reopen_signals.tsv'),'w',encoding='utf-8') as f:
    f.write('score\tnumber\tauthor\tclosed\treason\topen_issue_refs\thas_confirmation_text\tnonowner_comments\tlabels\ttitle\n')
    for r in rows: f.write('\t'.join(map(str,r))+'\n')
p=os.path.join(A,'issues','digest','D6_closed_digest_top200.md')
cl={x['number']:x for x in closed}
with open(p,'w',encoding='utf-8') as f:
    for r in rows[:200]: f.write(digest(cl[r[1]],'closed',1500,700,3))
print('closed digest',os.path.getsize(p)//1024,'KB')
print('closed completed',sum(1 for x in closed if x.get('state_reason')=='completed'),
      'with lifecycle label at close',sum(1 for x in closed if x.get('state_reason')=='completed' and set(labels(x))&{'verify-fix','diagnostics-armed'}),
      'no confirmation text',sum(1 for r in rows if r[4]=='completed' and r[6]==0),
      'referenced by open issues',sum(1 for r in rows if r[5]>0))
print('closed by day top:',collections.Counter((x.get('closed_at') or '')[:10] for x in closed).most_common(8))
# open: last-card age and number of cards
cc=[];
for x in openi:
    cards=[c for c in by.get(x['number'],[]) if 'CURRENT LIVE TEST' in (c.get('body') or '')]
    cc.append(len(cards))
print('open issues with >=1 card',sum(1 for c in cc if c),'total cards',sum(cc),'max',max(cc))
print('comments by author top',collections.Counter(c['user']['login'] for c in comments).most_common(6))
