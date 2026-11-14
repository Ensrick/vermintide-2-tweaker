import re,sys,io,os,subprocess
sys.stdout=io.TextIOWrapper(sys.stdout.buffer,encoding='utf-8')
base=r'<audit-workspace>'
repo=r'<repos>/vermintide-2-tweaker'
nums=[l.split('\t')[0] for l in subprocess.run(['py','-3',base+r'\scripts\D2_meta.py'],capture_output=True,text=True,encoding='utf-8').stdout.strip().split('\n')]
dirs=['weapon_tweaker','weapon_tweaker_dev','cosmetics_tweaker','dynamic_cosmetic_portraits','character_dialogue','gui_tweaker','gui_tweaker_dev','crafting_in_modded','crafting_in_modded_dev','chaos_wastes_tweaker_dev','career_tweaker','character_weapon_variants']
# index all lua lines once
idx={}
for d in dirs:
    for root,_,files in os.walk(os.path.join(repo,d)):
        for f in files:
            if f.endswith('.lua'):
                p=os.path.join(root,f)
                try: lines=open(p,encoding='utf-8',errors='replace').read().split('\n')
                except: continue
                idx[p]=lines
def find(name):
    hits=[]
    for p,lines in idx.items():
        for i,l in enumerate(lines):
            if name in l:
                hits.append((os.path.relpath(p,repo).replace(os.sep,'/'),i+1))
    return hits
for n in nums:
    t=open(os.path.join(base,'issues','open',n+'.md'),encoding='utf-8',errors='replace').read()
    # last card
    cards=[m.start() for m in re.finditer(r'## CURRENT LIVE TEST',t)]
    card=t[cards[-1]:cards[-1]+6000] if cards else ''
    nxt=card.find('\n## COMMENT by')
    if nxt>0: card=card[:nxt]
    names=set(re.findall(r'`?(issue\d+_[a-z0-9_]+)`?',card))
    names|=set(re.findall(r'PASS: ([a-z0-9_]+)',card))
    allnames=set(re.findall(r'(issue'+n+r'_[a-z0-9_]+)',t))
    for nm in sorted(names|allnames):
        h=find(nm)
        mods=sorted(set(x[0].split('/')[0] for x in h))
        first=h[0] if h else None
        incard='CARD' if nm in names else 'thread'
        print(f"#{n}\t{incard}\t{nm}\t{len(h)} hits\t{','.join(mods) or 'ABSENT'}\t{(first[0]+':'+str(first[1])) if first else ''}")
    if not (names|allnames): print(f"#{n}\t-\t(no named check in card/thread)")
