import re,sys,io
sys.stdout=io.TextIOWrapper(sys.stdout.buffer,encoding='utf-8')
p=r'<audit-workspace>/issues\digest\D2_wt_cosmetics_open_digest.md'
txt=open(p,encoding='utf-8',errors='replace').read()
blocks=re.split(r'(?m)^=== #',txt)[1:]
LIFE=['verify-fix','diagnostics-armed','not-started']
for b in blocks:
    lines=b.split('\n')
    m=re.match(r'(\d+) \[open\] (.*)',lines[0])
    num,title=m.group(1),m.group(2)
    a=re.search(r'author=(\S+) created=(\S+) updated=(\S+).*comments=(\d+)',lines[1])
    labels=[x.strip() for x in lines[2].replace('labels: ','').split(',')]
    life=[l for l in labels if l in LIFE]
    pri=[l for l in labels if re.match(r'\d-',l)]
    typ=[l for l in labels if l in('bug','crash','enhancement','feature','regression','question','tooling')]
    other=[l for l in labels if l not in LIFE and l not in pri and l not in typ]
    ncards=re.search(r'newest CURRENT LIVE TEST card \((\S+), (\d+) cards',b)
    print('\t'.join([num,a.group(1),a.group(2),a.group(3),a.group(4),'/'.join(life) or '-','/'.join(pri) or '-','/'.join(typ) or '-','|'.join(other),(ncards.group(1)+':'+ncards.group(2)) if ncards else 'nocard',title[:70]]))
