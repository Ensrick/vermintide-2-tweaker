import re,os,sys,collections
A=sys.argv[1]; F=os.path.join(A,'findings'); out=[]
pat_h=re.compile(r'^#{2,4}\s+((?:[A-E]\d-)?F\d+)\s*\|\s*(S[0-3])[^|]*\|\s*([^|]+)\|\s*(.+)$')
pat_t=re.compile(r'^\|\s*((?:[A-E]\d-)?F\d+)\s*\|\s*(S[0-3])[^|]*\|\s*(.+?)\s*\|\s*(.*)$')
for fn in sorted(os.listdir(F)):
    if not fn.endswith('.md'): continue
    rid=fn[:-3]; seen=set()
    for line in open(os.path.join(F,fn),encoding='utf-8',errors='replace'):
        line=line.rstrip('\n'); m=pat_h.match(line)
        if m:
            fid,sev,cat,title=m.groups()
        else:
            m=pat_t.match(line)
            if not m: continue
            fid,sev,title,_=m.groups(); cat=''
        if not fid.startswith(rid): fid=rid+'-'+fid
        if fid in seen: continue
        seen.add(fid); out.append((rid,fid,sev,cat.strip(),re.sub(r'\s+',' ',title).strip()[:260]))
c=collections.Counter((r[0],r[2]) for r in out)
rids=sorted({r[0] for r in out})
print('report  S0 S1 S2 S3 total')
tot=collections.Counter()
for r in rids:
    row=[c[(r,s)] for s in ('S0','S1','S2','S3')]; print(f'{r:6} ',*[f'{x:2}' for x in row], sum(row))
    for s,x in zip(('S0','S1','S2','S3'),row): tot[s]+=x
print('TOTAL  ',*[f'{tot[s]:2}' for s in ('S0','S1','S2','S3')], sum(tot.values()))
with open(os.path.join(A,'data','FINDINGS_REGISTER.tsv'),'w',encoding='utf-8') as f:
    f.write('report\tid\tseverity\tcategory\ttitle\n')
    for r in out: f.write('\t'.join(r)+'\n')
print('\nS0 findings:')
for r in out:
    if r[2]=='S0': print(' ',r[1],'|',r[4][:210])
