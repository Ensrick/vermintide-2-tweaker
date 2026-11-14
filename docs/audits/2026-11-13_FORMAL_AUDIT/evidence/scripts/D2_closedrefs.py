import re,sys,io,csv,collections
sys.stdout=io.TextIOWrapper(sys.stdout.buffer,encoding='utf-8')
base=r'<audit-workspace>'
txt=open(base+r'\issues\digest\D2_wt_cosmetics_open_digest.md',encoding='utf-8',errors='replace').read()
blocks=re.split(r'(?m)^=== #',txt)[1:]
refby=collections.defaultdict(list)
for b in blocks:
    num=re.match(r'(\d+)',b).group(1)
    m=re.search(r'(?m)^refs: (.*)$',b)
    if not m: continue
    for r in re.findall(r'#(\d+)\(c\)',m.group(1)):
        refby[r].append(num)
sig={}
for row in csv.DictReader(open(base+r'\data\closed_reopen_signals.tsv',encoding='utf-8',errors='replace'),delimiter='\t'):
    sig[row['number']]=row
for r in sorted(refby,key=int):
    s=sig.get(r)
    if not s: print(r,'NOSIG',refby[r]); continue
    print('\t'.join([r,s['score'],s['closed'],s['reason'],'conf='+s['has_confirmation_text'],'nonowner='+s['nonowner_comments'],s['labels'][:70],s['title'][:60],'<- '+','.join(refby[r])]))
