import json, re, collections
d = json.load(open(r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/B2_out\rt_checks.json", encoding="utf-8"))
str_re = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')
def strip(body):
    out = []
    for l in body.split("\n"):
        l2 = str_re.sub('""', l)
        k = l2.find("--")
        if k >= 0: l2 = l2[:k]
        out.append(l2)
    return "\n".join(out)
marker_re = re.compile(r'MARKER|_marker\b|fix_markers|_io_read_text|_rt_src_read|io\.open|getinfo|SENTINEL|sentinel|_read_source|source_text|src_text')
live_re = re.compile(r'\bManagers\s*[\.\[]|\bScriptUnit\b|\bUnit\.|\bWorld\.|\bApplication\.|\bNetwork\.|\bGui\.|\bMaterial\.|\bWwise\w*\b|player_unit|local_player|\bPOSITION_LOOKUP\b|\bVector3\b|\bLevelHelper\b|\bMesh\.')
data_re = re.compile(r'\b(ItemMasterList|Weapons|BuffTemplates|NetworkLookup|WeaponSkins|Deus\w+|Breeds|BreedActions|CareerSettings|TalentTrees|Talents|TalentBuffTemplates|DamageProfileTemplates|ActionTemplates|MutatorTemplates|PackSpawningSettings|LevelSettings|Cosmetics|UISettings|PowerLevel\w*|MaterialSettingsTemplates|WeaponTraits|WeaponProperties|CurrentPacing|ConflictDirectors|HordeSettings|HordeCompositions\w*|DLCSettings|AttachmentNodeLinking|SPProfiles|PROFILES_BY_NAME|ProfileSynchronizer|Pickups|AllPickups|BuffFunctionTemplates|ProcFunctions|StatBuffApplicationMethods|GameModeSettings|DifficultySettings|ExplosionTemplates|Unlockables|Rarity\w*|InventorySettings|ItemHelper|BackendUtils|GearUtils|ActionUtils|UIAtlasHelper|UIWidgets|IngameUI\w*|HeroView\w*|HeroWindow\w*|StartGame\w*|package\.loaded|CLASS\b|ActivatedAbilitySettings|PassiveAbilitySettings|AiBreedSnippets|Missions|QuestSettings|LootRatPickups|TerrorEventBlueprints|WeaveSettings|MechanismSettings|MoodSettings|EquipmentUI\w*|NewsFeed\w*|BTConditions|BotActions|BTBot\w+|[A-Z][A-Za-z]+Extension|[A-Z][A-Za-z]+System|[A-Z][A-Za-z]+Manager\w*)\b')
call_re = re.compile(r'([A-Za-z_][A-Za-z0-9_]*(?:[\.:][A-Za-z_][A-Za-z0-9_]*)*)\s*\(')
BUILT = set("type rawget rawset tostring tonumber pairs ipairs next select pcall xpcall unpack get_mod require setmetatable getmetatable error assert function if elseif while for return and or not".split())
def is_builtin(c):
    if c in BUILT: return True
    if c.startswith(("string.", "table.", "math.")): return True
    last = c.split(":")[-1].split(".")[-1]
    if last in ("format","find","match","sub","gsub","lower","upper","len","rep","concat","insert","sort","floor","abs","max","min","get","echo","info","warning","debug"): return True
    if re.match(r'_?rt_register$', last): return True
    return False
res = []
for o in d:
    if not o["inline"]:
        o["cls"] = "indirect(named fn)"; res.append(o); continue
    code = strip(o["body"])
    # drop the registration line's own call
    has_marker = bool(marker_re.search(code))
    gnames = " ".join(re.findall(r'rawget\(\s*_G\s*,\s*"(\w+)"', o["body"]) + re.findall(r'_G\[\s*"(\w+)"', o["body"]) + re.findall(r'package\.loaded\[\s*"([^"]+)"', o["body"]) + re.findall(r'require\(\s*"(scripts/(?!mods/)[^"]+)"', o["body"]))
    live = bool(live_re.search(code)) or bool(live_re.search(gnames)); data = bool(data_re.search(code)) or bool(data_re.search(gnames)) or bool(re.search(r'scripts/', gnames))
    calls = set(m.group(1) for m in call_re.finditer(code))
    other = sorted(c for c in calls if not is_builtin(c))
    READERS = ("_rt_src_read","_io_read_text","_gut_read_all","read_all","getinfo","open","lines","read","close","_read_source")
    other_nr = [c for c in other if c.split(":")[-1].split(".")[-1] not in READERS]
    if has_marker and not other_nr: other = []
    if live: cls = "R-live (reads Managers/world/unit state)"
    elif data: cls = "R-data (reads live engine data tables/classes)"
    elif other: cls = "L (calls mod logic with synthetic inputs, no engine read)"
    elif has_marker: cls = "M (marker/source-text only)"
    else: cls = "E (existence/shape/constant only)"
    o["cls"] = cls; o["marker"] = has_marker; o["other_calls"] = other[:6]
    res.append(o)
json.dump(res, open(r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/B2_out\rt_checks_classified.json", "w", encoding="utf-8"), indent=0)
tot = collections.Counter(o["cls"] for o in res)
print("TOTAL", len(res))
for k, v in tot.most_common(): print(f"  {v:4d} {100*v/len(res):5.1f}%  {k}")
print("checks containing a marker/source-text assertion at all:", sum(1 for o in res if o.get("marker")))
bym = collections.defaultdict(collections.Counter)
for o in res: bym[o["mod"]][o["cls"][:6]] += 1
keys = ["R-live","R-data","L (cal","M (mar","E (exi","indire"]
print(f"{'mod':32s} " + " ".join(f"{k:>7s}" for k in keys) + "   total  marker-any")
for m, c in sorted(bym.items(), key=lambda kv: -sum(kv[1].values())):
    mk = sum(1 for o in res if o["mod"] == m and o.get("marker"))
    print(f"{m:32s} " + " ".join(f"{c[k]:7d}" for k in keys) + f"   {sum(c.values()):5d}  {mk:5d}")
