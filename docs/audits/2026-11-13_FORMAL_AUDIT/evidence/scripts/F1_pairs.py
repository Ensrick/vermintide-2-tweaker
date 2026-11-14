import os,re,subprocess,difflib,sys,collections
R=r'<repos>/vermintide-2-tweaker'
PAIRS=[('weapon_tweaker','weapon_tweaker_dev','wt','wt_dev'),('chaos_wastes_tweaker','chaos_wastes_tweaker_dev','ct','ct_dev'),('crafting_in_modded','crafting_in_modded_dev','cim','cim_dev'),('general_tweaker','general_tweaker_dev','gt','gt_dev'),('gui_tweaker','gui_tweaker_dev','gut','gut_dev'),('verminious_dreams_lighting','verminious_dreams_lighting_dev','vdl','vdl_dev')]
files=subprocess.run(['git','-C',R,'ls-files'],capture_output=True,text=True).stdout.splitlines()
def rd(f): return open(os.path.join(R,f),encoding='utf-8',errors='replace').read().replace('\r','')
def ver(d):
    for f in files:
        if f.startswith(d+'/') and f.endswith('.lua'):
            m=re.search(r'MOD_VERSION\s*=\s*["\']([^"\']+)',rd(f))
            if m: return m.group(1)
    return '?'
def lastcommit(d):
    return subprocess.run(['git','-C',R,'log','-1','--format=%cs','--',d+'/scripts'],capture_output=True,text=True).stdout.strip()
for st,dv,sid,did in PAIRS:
    sf={f[len(st)+1:]:f for f in files if f.startswith(st+'/') and f.endswith('.lua')}
    df={f[len(dv)+1:].replace(dv,st):f for f in files if f.startswith(dv+'/') and f.endswith('.lua')}
    def norm(t):
        t=t.replace(dv,st); t=re.sub(r'\b'+re.escape(did)+r'\b',sid,t); return t
    same=diff=0; add=rem=0; worst=[]
    for k in sorted(set(sf)&set(df)):
        a=rd(sf[k]); b=norm(rd(df[k]))
        if a==b: same+=1
        else:
            diff+=1; al=a.splitlines(); bl=b.splitlines(); p=m=0
            for l in difflib.unified_diff(al,bl,lineterm='',n=0):
                if l.startswith('+') and not l.startswith('+++'): p+=1
                elif l.startswith('-') and not l.startswith('---'): m+=1
            add+=p; rem+=m; worst.append((p+m,k))
    od=sorted(set(df)-set(sf)); os_=sorted(set(sf)-set(df))
    odl=sum(rd(df[k]).count('\n') for k in od); osl=sum(rd(sf[k]).count('\n') for k in os_)
    print(f"\n== {st} (v{ver(st)}, last src commit {lastcommit(st)})  vs  {dv} (v{ver(dv)}, last {lastcommit(dv)})")
    print(f"   common files: {len(set(sf)&set(df))}  identical-after-namespace-normalization: {same}  differing: {diff} (+{add}/-{rem} lines dev vs stable)")
    print(f"   only in dev: {len(od)} files, {odl} lines   only in stable: {len(os_)} files, {osl} lines")
    for n,k in sorted(worst,reverse=True)[:6]: print('     diff',n,k)
    if od: print('     dev-only sample:',', '.join(os.path.basename(x) for x in od[:12]))
    if os_: print('     stable-only:',', '.join(os.path.basename(x) for x in os_[:12]))
print('\n== versions of single-stream mods')
for d in ['character_weapon_variants','weapons_of_chaos','cosmetics_tweaker','dynamic_cosmetic_portraits','character_dialogue','event_tweaker','enemy_tweaker','modded_progression','career_tweaker','tweaker']:
    print('  ',d,ver(d),lastcommit(d))
