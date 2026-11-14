import os,re,subprocess,collections,sys
R=r'<repos>/vermintide-2-tweaker'
ACTIVE=['weapon_tweaker','character_weapon_variants','weapons_of_chaos','cosmetics_tweaker','dynamic_cosmetic_portraits','character_dialogue','chaos_wastes_tweaker_dev','event_tweaker','enemy_tweaker','crafting_in_modded_dev','modded_progression','career_tweaker','general_tweaker_dev','gui_tweaker_dev','verminious_dreams_lighting_dev']
files=subprocess.run(['git','-C',R,'ls-files'],capture_output=True,text=True).stdout.splitlines()
hk=re.compile(r'mod:(hook|hook_safe|hook_origin)\s*\(\s*([A-Za-z_][\w\.]*|"[^"]+")\s*,\s*"([^"]+)"')
tg=collections.defaultdict(lambda: collections.defaultdict(list)); dyn=collections.Counter(); tot=collections.Counter()
allh=re.compile(r'mod:(?:hook|hook_safe|hook_origin)\s*\(')
for f in files:
    top=f.split('/')[0]
    if top not in ACTIVE or not f.endswith('.lua'): continue
    t=open(os.path.join(R,f),encoding='utf-8',errors='replace').read()
    n=len(allh.findall(t)); tot[top]+=n; m=hk.findall(t); dyn[top]+=n-len(m)
    for kind,cls,meth in m:
        tg[(cls.strip('"'),meth)][top].append(kind)
print('static-literal hook targets:',len(tg),' total hook call sites:',sum(tot.values()),' non-literal (dynamic/loop-registered) sites:',sum(dyn.values()))
multi=[(k,v) for k,v in tg.items() if len(v)>=2]
print('targets hooked by >=2 active mods:',len(multi),'  by >=3:',sum(1 for k,v in multi if len(v)>=3))
for k,v in sorted(multi,key=lambda kv:-len(kv[1]))[:45]:
    print(f"  {len(v)}  {k[0]}.{k[1]}  <- "+', '.join(f"{m.replace('_tweaker','').replace('_dev','')}:{'/'.join(sorted(set(x)))}" for m,x in sorted(v.items())))
same=[(k,m,x) for k,v in tg.items() for m,x in v.items() if len(x)>=2]
print('\nsame mod hooking the same literal (Class, method) more than once (VMF drops/rehooks):',len(same))
for k,m,x in sorted(same,key=lambda r:-len(r[2]))[:25]: print('  ',len(x),m,k[0]+'.'+k[1],x)
cls=collections.Counter()
for (c,m),v in tg.items(): cls[c]+=sum(len(x) for x in v.values())
print('\nmost-hooked classes:',cls.most_common(25))
