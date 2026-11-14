import re,sys,io,os
sys.stdout=io.TextIOWrapper(sys.stdout.buffer,encoding='utf-8')
base=r'<audit-workspace>'
nums=sys.argv[2:]
k=int(sys.argv[1])
for n in nums:
    t=open(os.path.join(base,'issues',('closed' if os.path.exists(os.path.join(base,'issues','closed',n+'.md')) and not os.path.exists(os.path.join(base,'issues','open',n+'.md')) else 'open'),n+'.md'),encoding='utf-8',errors='replace').read()
    parts=re.split(r'(?m)^## COMMENT by ',t)
    print('=== #'+n,'ncomments',len(parts)-1)
    for p in parts[-k:]:
        if p.startswith('# #'): continue
        head,_,body=p.partition('\n')
        body=re.sub(r'\s+',' ',body)[:420]
        print('  *',head,'::',body)
