# D6 final pipeline: evidence class + closure mechanism + recommendation for all 613 closed issues
# -> findings/D6_ledger.tsv + scripts/D6_out/ledger_rows.json. Read-only over the audit cache.
import sys, os, re, json, collections, datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import D6_lib as L, D6_classify as K
from D6_tables import LINK, LINK_WHY, FIXCITE, FIXNO, MAN
c = L.load(); by = c['by']; tl = c['tl']; le = K.le
OUT = os.path.join(L.A, 'scripts', 'D6_out')
fc = {int(k): v for k, v in json.load(open(os.path.join(OUT, 'fixcheck_all.json'), encoding='utf-8')).items()}
TOP200 = set(int(x) for x in open(os.path.join(OUT, 'top200.txt')).read().split())
REST_READ = set(int(x) for x in open(os.path.join(OUT, 'rest_nonA.txt')).read().split())
OWNER = 'Ensrick'
strip_att = K.strip_att

AGENT_PREFIX = re.compile(r"^(Closing|Closed|Historical lifecycle|Tracked under|Lifecycle|Label correction|Consolidat|Duplicate of|Test method|Post-fix pass|User verif|Author verified|User confirmed|User-confirmed|Verified (by|on|in-game|tooling|fixed|from|in)|Fixed by PR|Fixed - confirmed in-game by|Fixed and closing|Rain(Religion)? verified|Autonomous|Implemented and merged|Executed:|Downgrading|Re-verified|Superseded|Official-stream|Corpus sweep|Cross-ref|Branch inventory|Deep[- ]review|Umbrella|Reopen|Not planned|Stale-close|Research complete|Audit implementation|Diagnostics are now|No shipped work|User decision pending|Clarification from|Regression diagnosis|Additional equipment|Unblocked|Processed\.|Direction reversed|Not a bug|PR \d+ merged|Removing the stale|Shipped|Merged in)", re.I)
THIRD = re.compile(r"\b(the|by) (user|reporter|owner|author|project owner|playtester|tester|maintainer)\b|\buser('s)? (sign-off|direction|verif\w*|confirm\w*|quote|report\w*)|\bRain(Religion)? (confirmed|verified)|\bby Ensrick\b", re.I)

def is_human(cm):
    """Typed by a person: any non-owner account, or a short plain owner-account comment without agent markers."""
    if cm['user']['login'] != OWNER: return True
    t = strip_att(cm['body'])
    if len(t) > 700: return False
    if re.search(r"\*\*|^#+ |`[^`]+`|ManifestID|\bv?\d+\.\d+\.\d+-(dev|beta)|\b[0-9a-f]{7,40}\b", t, re.M): return False
    if AGENT_PREFIX.search(t) or '\\n' in t or THIRD.search(t): return False
    return True

POS = re.compile(r"\b(works?|working|worked|fixed|functional|confirmed|verified|as intended|as expected|resolved|no longer|correctly|haven'?t seen|don'?t see the issue|good|persist\w*|perfect)\b", re.I)
NEG = re.compile(r"(not fixed|isn'?t fixed|still (broken|crash\w*|happen\w*|occur\w*|not|doesn'?t|wrong|there|present|an issue|fails?|missing|too|exist\w*)|doesn'?t (work|function|appear|show|apply)|does not (work|function|appear|show|apply)|not (working|functional|available)|isn'?t (working|functional)|(occur\w*|happen\w*) again|stopped working|came back|is back|\bbroke\b|broken|regress\w*|didn'?t work|did not work|no change|no effect|not resolved|unresolved|same (issue|crash|problem|bug)|incorrect|were missing|isn't the intended)", re.I)
ATTR = re.compile(r"((user|owner|author|reporter|playtester|rain(religion)?|project owner|tester|maintainer|human)('s)?\b[^.\n]{0,80}\b(verified|confirmed|confirms|verification|confirmation|reconfirmed|reports? (it |that )?(works|working|fixed)|tested|crafted)|verified[^.\n]{0,90}by (the )?(user|reporter|owner|author|project owner|playtester|tester|maintainer|rain(religion)?)|(confirmed|verified|validated)[^.\n]{0,40}in[- ]game|in[- ]game (user )?(confirmation|verification|sign-off)|(verified|confirmed) in (paired |two-player |live )?(co-?op )?(testing|session)|two-player (session|test)|human[- ]verified|user[- ]confirmed|(user|owner|author|reporter)('s)? (in-game )?sign-off|per user (verification|direction|confirmation)|at (the )?user'?s direction|closing per user|per your call|you confirmed|fixed label seen|\(user call|user determination|explicitly confirms)", re.I)
ATTR_NEG = re.compile(r"(not yet|pending|awaiting|awaits|needs? |required|requires|owed|until|cannot|can't|no in-game|without in-game|has not been|hasn't been|unverified|must be|still needs|waiting|NOT closing|ready for in-game|does not itself|not itself|leaving open|not as user-verified|not being closed as|rather than|if the |once the |before in-game|still reproduces)", re.I)
LOGREF = re.compile(r"(console-20\d\d-\d\d-\d\d|session log|live session|captured log|runtime log|in-game log|host log|client log|from the log|log shows|log confirms|log evidence|log proves|log records)", re.I)
LOGPOS = re.compile(r"(no (new )?(script )?error|zero|confirm|verif|shows|proves|clean|did not|didn't|absent|present|fired|loaded|emitted|records?|PASS|without reproducing)", re.I)
STATIC = re.compile(r"(source-confirmed|verified in code|hosted QA|QA (run )?[`\[]?\d*[`\]]? ?pass|exact-master|merged as|PR #?\d+ merged|regression (check|test|marker|guard|suite)|_rt_register|unit test|headless|luacheck|\blint|static (check|gate|evidence|proof)|qa/|check_[a-z_]+\.ps1|deterministic|repository invariant|still present|present in (the )?current|code review|Autonomous|decompile|grep)", re.I)
SHIP = re.compile(r"(shipped|deployed|uploaded|Fixed in|fix candidate|landed|released|implemented|merged|Resolved in)", re.I)
SUPERSEDE = re.compile(r"(superseded by|supersed\w+ (by|into)|duplicate(/subset)? of|consolidat\w+ into|folded into|merged into|subsumed by|absorbed into|closing in favou?r of|closed into|tracked (separately )?(under|in|on|as))\s*(the )?(reopened |closed-Fixed |closed |deployed |open |critical |canonical |umbrella |issue |parent |animation )*(umbrella )?#?(\d{1,4})", re.I)
NOTBUG = re.compile(r"(not[- ]a[- ]bug|not-a-ct-bug|not a ct_dev bug|working[- ]as[- ]designed|as disproved|Automated disproof|intentional design|not needed|version mismatch|vanilla game issue|infeasible)", re.I)
STRUCT_TEXT = re.compile(r"(Closing autonomously per CLAUDE\.md rule 13|Closed autonomously \(tooling/tests class\)|harness instrumentation|no gameplay surface|repository invariant|repository-only|docs-only|Autonomous completion evidence|Autonomously verified and closing)", re.I)
STRUCT_TITLE = re.compile(r"(regression (marker |runner |test )?checks?\b|regression runner|Regression Test$|Backfill|Refresh stale|physically reorder|remove temporary .* diagnostic|refresh dev stream|Remove (obsolete|dead)|leaks bare global|Dead Big Rebalance|Stale probes|chat-command name collision|VMB build|Remove io\.open|Localize Weapon Names in Developer UI|dead Anim Picker entry|escape chat-debt census)", re.I)
LIFE = {'Fixed', 'verify-fix', 'verify-fix-coop', 'diagnostics-armed', 'not-started', 'verify-in-game', 'probe-live'}

def labels_at(n, t):
    cur = set()
    for e in le[str(n)]['timelineItems']['nodes']:
        if L.ts(e['createdAt']) > t: break
        nm = e['label']['name'] if e['label'] else None
        if not nm: continue
        if e['__typename'] == 'LabeledEvent': cur.add(nm)
        else: cur.discard(nm)
    return cur

def analyse(x):
    n = x['number']; base = K.analyse(x)
    t_close = base['t_close']; win = datetime.timedelta(minutes=10)
    cs = by.get(n, []); pre = base['pre']; near = base['near']
    ship_i = next((i for i, cm in enumerate(pre) if SHIP.search(cm['body'] or '')), None)
    hv = []; ap = []; logev = False; static = False
    for i, cm in enumerate(cs):
        b = cm['body'] or ''; t = strip_att(b); when = L.ts(cm['created_at'])
        if is_human(cm):
            p = bool(POS.search(t)); ng = bool(NEG.search(t))
            code = 'M' if (p and ng) else ('P' if p else ('N' if ng else None))
            if code: hv.append((when, code, cm['user']['login'], t[:110].replace('\n', ' ')))
        else:
            for m in ATTR.finditer(b):
                if not ATTR_NEG.search(b[max(0, m.start() - 60): m.end() + 15]):
                    ap.append((when, b[max(0, m.start() - 30): m.end() + 60].replace('\n', ' ')[:110])); break
            if when <= t_close + win:
                if LOGREF.search(b) and (ship_i is None or i >= ship_i) and LOGPOS.search(b): logev = True
                if STATIC.search(b): static = True
    hv_pre = [v for v in hv if v[0] <= t_close + win]; hv_post = [v for v in hv if v[0] > t_close + win]
    ap_pre = [v for v in ap if v[0] <= t_close + win]; ap_post = [v for v in ap if v[0] > t_close + win]
    lab_close = labels_at(n, t_close + datetime.timedelta(minutes=2))
    life_close = sorted(lab_close & LIFE)
    fixed_at_close = 'Fixed' in lab_close
    last_h = hv_pre[-1] if hv_pre else None
    tail_t = L.ts(pre[-3]['created_at']) if len(pre) >= 3 else (L.ts(pre[0]['created_at']) if pre else None)
    ap_tail = [v for v in ap_pre if tail_t and v[0] >= tail_t]
    sub = ''
    if ap_tail and not (last_h and last_h[1] == 'N' and last_h[0] > ap_tail[-1][0]):
        ev = 'A'; sub = 'A2'; why = 'agent closing comment attributes in-game confirmation: "%s"' % ap_tail[-1][1]
    elif last_h and last_h[1] == 'P':
        ev = 'A'; sub = 'A1'; why = 'human-typed verdict %s by %s: "%s"' % (str(last_h[0])[:10], last_h[2], last_h[3])
    elif last_h and last_h[1] == 'M' and fixed_at_close:
        ev = 'A'; sub = 'A1'; why = 'mixed human-typed verdict + Fixed label: "%s"' % last_h[3]
    elif last_h and last_h[1] == 'M':
        ev = 'A'; sub = 'A1?'; why = 'mixed human-typed verdict %s by %s: "%s"' % (str(last_h[0])[:10], last_h[2], last_h[3])
    elif last_h and last_h[1] == 'N' and not fixed_at_close:
        ev = 'D'; sub = 'N'; why = 'LAST HUMAN VERDICT NEGATIVE %s by %s: "%s"' % (str(last_h[0])[:10], last_h[2], last_h[3])
    elif ap_pre:
        ev = 'A'; sub = 'A2'; why = 'earlier agent comment attributes in-game confirmation: "%s"' % ap_pre[-1][1]
    elif fixed_at_close:
        ev = 'A'; sub = 'A3'; why = 'Fixed label applied before close with no confirmation text (owner UI click presumed)'
    elif ap_post or (hv_post and hv_post[-1][1] == 'P'):
        ev = 'A'; sub = 'A-post'; why = 'confirmation recorded only after close'
    elif logev: ev = 'B'; why = 'agent cites a console/session log after the ship claim'
    elif static: ev = 'C'; why = 'static/CI/regression/code-review wording only'
    elif ship_i is not None: ev = 'D'; why = 'ship claim only, no verification wording'
    else: ev = 'D'; why = 'no fix or verification wording before close'
    close_text = '\n'.join((cm['body'] or '') for cm in (near or pre[-1:]))
    ms = SUPERSEDE.search(close_text); sup = int(ms.group(ms.lastindex)) if ms else None
    if base['cat'] == 'runtime' and ((STRUCT_TEXT.search(close_text) and ev != 'A') or STRUCT_TITLE.search(x['title'])): base['cat'] = 'tooling?'
    base.update(ev=ev, sub=sub, why=why, life_close=life_close, fixed_at_close=fixed_at_close, sup=sup, notbug=bool(NOTBUG.search(close_text[:400])),
                silent=(base['kind'] == 'MANUAL' and not near), post_neg=bool(hv_post and hv_post[-1][1] == 'N'))
    return base

def mech(r, ev):
    if r['kind'] == 'PR': return 'PR-AUTOCLOSE'
    if r['kind'] == 'COMMIT': return 'COMMIT-KEYWORD-AUTOCLOSE'
    if r['reason'] == 'duplicate' or (r['reason'] == 'not_planned' and r['sup']): return 'SUPERSEDED-BY-OTHER-ISSUE'
    if r['reason'] == 'not_planned': return 'NOT-PLANNED-DECISION'
    if r['cat'] in ('tooling', 'tooling?', 'audit'): return 'TOOLING-DETERMINISTIC'
    if r['cat'] == 'logdump': return 'SUPERSEDED-BY-OTHER-ISSUE'
    if ev == 'A': return 'MANUAL-WITH-INGAME-CONFIRMATION'
    if ev == 'B': return 'MANUAL-WITH-LOG-EVIDENCE'
    if r['sup'] or ev == 'n-a': return 'SUPERSEDED-BY-OTHER-ISSUE' if r['sup'] else 'NOT-PLANNED-DECISION'
    return 'MANUAL-NO-EVIDENCE'

def build():
    orefs = K.open_refs()
    rows = []
    for x in sorted(c['closed'], key=lambda x: x['number']):
        n = x['number']; r = analyse(x)
        runtime = (r['cat'] == 'runtime' and r['reason'] == 'completed')
        ev = r['ev'] if runtime else 'n-a'
        script_ev = ev
        note = []; conf = 'L'; rec = None
        manual = n in MAN
        if manual:
            mev, mrec, mconf, mnote = MAN[n]
            if mev: ev = mev
            rec = mrec; conf = mconf
            if mnote: note.append(mnote)
        elif n in TOP200 or n in REST_READ:
            conf = 'M'
        if not runtime: ev = 'n-a'
        m = mech(r, ev)
        if rec is None:
            if n in LINK: rec = 'LINK-TO-OPEN:%d' % LINK[n]
            elif not runtime: rec = 'LEAVE-CLOSED'
            elif ev in ('A', 'B'): rec = 'LEAVE-CLOSED'
            elif r['notbug'] or (r['sup'] and r['sup'] in K.closed): rec = 'LEAVE-CLOSED'
            elif r['sup'] and r['sup'] in K.openi: rec = 'LINK-TO-OPEN:%d' % r['sup']
            else: rec = 'REVERIFY-VIA-HARNESS'
        if n in LINK and LINK_WHY.get(n) and n not in (174,): note.append(LINK_WHY[n])
        if runtime and not manual: note.append(('%s: ' % r['sub'] if r['sub'] else '') + r['why'])
        if r['silent']: note.append('silent close (no comment within 10 min)')
        if runtime and r['life_close'] and r['life_close'] != ['Fixed']: note.append('lifecycle at close: ' + '+'.join(r['life_close']))
        if r['reopened']: note.append('reopened %dx before final close' % r['reopened'])
        if r['post_neg']: note.append('NEGATIVE human-typed comment after close')
        f = fc.get(n, {})
        if n in FIXNO: fix = 'no'; note.append(FIXNO[n])
        elif n in FIXCITE: fix = 'yes'; note.append('fix on master (manual): ' + FIXCITE[n])
        elif f.get('ntok') and f['ntok'] < 8:
            fix = 'not-checked'; note.append('auto check inconclusive: only %d fix identifiers' % f['ntok'])
        elif f.get('ntok'):
            pct = 100 * (f['ntok'] - len(f['miss_any'])) // f['ntok']
            fix = 'yes' if pct >= 80 else ('partial' if pct >= 50 else 'no')
            note.append('auto identifier survival %d/%d (%d commit%s citing #%d)' % (f['ntok'] - len(f['miss_any']), f['ntok'], f['commits'], '' if f['commits'] == 1 else 's', n))
            if fix != 'yes': note.append('missing e.g. ' + ', '.join(f['miss_any'][:4]))
        else: fix = 'not-checked'
        pair_mod = {'chaos_wastes_tweaker': 'cw', 'general_tweaker': 'gt', 'gui_tweaker': 'gut', 'crafting_in_modded': 'cim', 'verminious_dreams_lighting': 'vdl'}.get(f.get('stable_dir'))
        devonly = bool(f.get('stable_dir') and f.get('n_dev_live', 0) >= 2 and len(f['stable_missing']) / f['n_dev_live'] >= 0.6 and r['mod'].rstrip('?') == pair_mod)
        if devonly: note.append('dev-only: %d/%d fix identifiers absent from stable %s' % (len(f['stable_missing']), f['n_dev_live'], f['stable_dir']))
        refs = sorted({o for o, _, _ in orefs.get(n, [])})
        rows.append(dict(number=n, mod=r['mod'], closed=str(r['t_close'])[:10], mech=m, ev=ev, script_ev=script_ev, sub=(r['sub'] if runtime else ''), refs=refs, fix=fix, rec=rec, conf=conf,
                         note='; '.join(note), cat=r['cat'], typ=r['typ'], prio=r['prio'], reason=r['reason'], kind=r['kind'], title=x['title'], life_close=r['life_close'],
                         silent=r['silent'], author=r['author'], fixed_at_close=r['fixed_at_close'], manual=manual, read=(n in TOP200 or n in REST_READ or manual), devonly=devonly,
                         runtime=runtime))
    return rows

if __name__ == '__main__':
    rows = build()
    p = os.path.join(L.A, 'findings', 'D6_ledger.tsv')
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write('number\tmod\tclosed_date\tclosure_mechanism\tevidence_class\treferenced_by_open\tfix_still_on_master\trecommendation\tconfidence\tnote\n')
        for r in rows:
            tag = '[%s %s%s%s] ' % (r['typ'], r['prio'] or 'no-prio', '' if r['cat'] == 'runtime' else ' ' + r['cat'], '' if r['reason'] == 'completed' else ' ' + r['reason'])
            f.write('\t'.join([str(r['number']), r['mod'], r['closed'], r['mech'], r['ev'], ','.join(map(str, r['refs'])), r['fix'], r['rec'], r['conf'],
                               (tag + r['note']).replace('\t', ' ').replace('\n', ' ').replace('—', '-').replace('–', '-')]) + '\n')
    json.dump(rows, open(os.path.join(OUT, 'ledger_rows.json'), 'w', encoding='utf-8'), default=str)
    C = collections.Counter
    print('rows', len(rows))
    print('mech', C(r['mech'] for r in rows).most_common())
    rt = [r for r in rows if r['runtime']]
    print('runtime completed', len(rt), 'ev', C(r['ev'] for r in rt).most_common(), 'sub', C(r['sub'] for r in rt).most_common())
    print('rec', C(r['rec'].split(':')[0] for r in rows).most_common())
    print('conf', C(r['conf'] for r in rows).most_common())
