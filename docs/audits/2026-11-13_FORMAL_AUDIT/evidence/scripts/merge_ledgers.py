import csv,os,sys,collections,json,re
A=sys.argv[1]; F=os.path.join(A,'findings')
rows=[]; hdrs={}
for b in ['D1','D2','D3','D4','D5']:
    p=os.path.join(F,b+'_ledger.tsv')
    with open(p,encoding='utf-8',errors='replace',newline='') as f:
        r=list(csv.reader(f,delimiter='\t',quoting=csv.QUOTE_NONE))
    h=[c.strip().split(' ')[0].lower() for c in r[0]]; hdrs[b]=h
    for x in r[1:]:
        if not x or not x[0].strip(): continue
        d=dict(zip(h,[c.strip() for c in x])); d['bucket']=b; rows.append(d)
for b,h in hdrs.items(): print(b,len([r for r in rows if r['bucket']==b]),h)
nums=[int(re.sub(r'\D','',r['number'])) for r in rows]
openi=json.load(open(os.path.join(A,'data','open_issues.json'),encoding='utf-8'))
on={x['number'] for x in openi}
print('ledger rows',len(rows),'unique',len(set(nums)),'missing from ledger',sorted(on-set(nums)),'extra',sorted(set(nums)-on))
def norm(v,keys):
    v=(v or '').upper()
    for k in keys:
        if v.startswith(k): return k
    return v.split(':')[0].split(' ')[0] or '?'
C=collections.Counter
vc=C(); disp=C(); fs=C(); ac=C(); ty=C(); cross=collections.defaultdict(C)
for r in rows:
    v=(r.get('verification_class') or '?').strip().upper()[:1]; r['vc']=v; vc[v]+=1
    d=norm(r.get('disposition'),['KEEP-FIX','KEEP-VERIFY','CLOSE-NOT-PLANNED','CLOSE-OUT-OF-SCOPE','CLOSE-DUPLICATE','MERGE-INTO','OWNER-DECISION','CLOSE-STATIC-VERIFIABLE']); r['disp']=d; disp[d]+=1
    f=(r.get('fix_state') or '?').split(':')[0].strip().lower(); r['fs']=f; fs[f]+=1
    ac[(r.get('author_class') or '?').lower()]+=1; ty[(r.get('type') or '?').lower()]+=1
    cross[r.get('lifecycle','?')][v]+=1
print('verification class',vc.most_common()); print('disposition',disp.most_common()); print('fix_state',fs.most_common()); print('author',ac.most_common()); print('type',ty.most_common())
print('lifecycle x class:');
for k,v in cross.items(): print('  ',k,dict(v))
tot=len(rows); auto=vc['R']+vc['S']+vc['U']
print(f"automatable (R+S+U) {auto}/{tot} = {auto*100//tot}%  | C {vc['C']} | V {vc['V']} | X {vc['X']}")
print('per bucket class:')
for b in ['D1','D2','D3','D4','D5']:
    c=C(r['vc'] for r in rows if r['bucket']==b); print('  ',b,dict(c))
# write master
cols=['number','bucket','mod','author_class','type','lifecycle','priority','summary','cluster','fix_state','verification_class','auto_check','disposition','related','confidence','note']
with open(os.path.join(A,'data','MASTER_LEDGER.tsv'),'w',encoding='utf-8',newline='') as f:
    w=csv.writer(f,delimiter='\t',quoting=csv.QUOTE_NONE,escapechar=chr(92)); w.writerow(cols)
    for r in sorted(rows,key=lambda r:int(re.sub(r'\D','',r['number']))): w.writerow([(r.get(c) or '').replace('\t',' ') for c in cols])
cl=C((r['bucket'],r.get('cluster','')) for r in rows)
print('clusters total',len(cl),' clusters with >=3:',sum(1 for k,v in cl.items() if v>=3))
for (b,c),v in cl.most_common(45): print('  ',v,b,c)
