# D6: per-issue feature extraction + heuristic closure-mechanism / evidence classification for all 613 closed issues.
import sys, os, re, json, collections, datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import D6_lib as L
c = L.load(); by = c['by']; tl = c['tl']
le = json.load(open(os.path.join(L.A, 'scripts', 'D6_out', 'label_events.json'), encoding='utf-8'))
closed = {x['number']: x for x in c['closed']}
openi = {x['number']: x for x in c['openi']}
OWNER = 'Ensrick'

def strip_att(b):
    b = (b or '').replace('\r', '')
    t = re.sub(r'\[[^\]]*\]\(https://github\.com/user-attachments/[^)]*\)', '', b)
    t = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', t)
    t = re.sub(r'<img[^>]*>', '', t).strip()
    return t
AGENT_PREFIX = re.compile(r"^(Closing because|Closing as|Closing board hygiene|Closing per|Closing the|Closed (at|as|per)|Historical lifecycle normalization|Tracked under umbrella|Lifecycle (correction|note|triage)|Label correction|Consolidated into|Duplicate of|Test method|Post-fix pass|User verif|Author verified|User confirmed|Verified (by|on|in-game on|tooling|fixed|from)|Fixed by PR|Fixed - confirmed in-game by|Fixed and closing|Rain(Religion)? verified|Autonomous|Implemented and merged|Executed:|Downgrading|Re-verified|Superseded|Official-stream|Corpus sweep|Cross-reference|Branch inventory|Deep[- ]review|Umbrella|Reopen|Not planned|Won't)", re.I)
THIRD = re.compile(r"\b(the|by) (user|reporter|owner|author|project owner|playtester)\b|\buser('s)? (sign-off|direction|verif\w*|confirm\w*|quote|report\w*)|\bRain(Religion)? (confirmed|verified)", re.I)
def is_human_typed(cm):
    """True if the comment looks typed by a person (owner in the web UI, or any non-owner account)."""
    if cm['user']['login'] != OWNER: return True
    t = strip_att(cm['body'])
    if len(t) > 700: return False
    if re.search(r"\*\*|^#+ |`[^`]+`|ManifestID|\bv?\d+\.\d+\.\d+-(dev|beta)|\b[0-9a-f]{7,40}\b", t, re.M): return False
    if AGENT_PREFIX.search(t): return False
    if '\\n' in t or THIRD.search(t): return False
    return True
POS = re.compile(r"\b(works?|working|worked|fixed|functional|confirmed|verified|as intended|as expected|resolved|no longer|correctly|implemented as expected|haven'?t seen|don'?t see the issue|good)\b", re.I)
NEG = re.compile(r"(not fixed|isn'?t fixed|still (broken|crash\w*|happen\w*|occur\w*|not|doesn'?t|wrong|there|present|an issue|fails?|missing|see\w*|get\w*|has|have|show\w*|need\w*)|doesn'?t (work|function|appear|show|apply)|does not (work|function|appear|show|apply)|not (working|functional)|isn'?t (working|functional)|(occur\w*|happen\w*|crash\w*) again|came back|is back|\bbroke\b|broken|regress\w*|\bfails?\b|\bfailed\b|didn'?t work|did not work|no change|not resolved|unresolved|same (issue|crash|problem|bug)|remains\b|incorrect|unfortunately)", re.I)
# agent text that attributes a verdict to a human
ATTR = re.compile(r"((user|owner|author|reporter|playtester|rain(religion)?|project owner|tester|human)('s)?\b[^.\n]{0,80}\b(verified|confirmed|verification|confirmation|reports? (it |that )?(works|working|fixed)|tested)|verified (fixed |working )?(in[- ]game )?by the (user|reporter|owner|author|project owner|playtester)|(confirmed|verified|validated)[^.\n]{0,40}in[- ]game|in[- ]game (user )?(confirmation|verification|sign-off)|two-player (session|test)|live (co-?op )?session (confirm|verif)|human[- ]verified|user[- ]confirmed|(user|owner|author|reporter)('s)? (in-game )?sign-off|per user (verification|direction|confirmation)|at (the )?user'?s direction|verified [^.\n]{0,60}by Rain(Religion)?|closing per user)", re.I)
ATTR_NEG = re.compile(r"(not yet|pending|awaiting|needs?\b|required?\b|requires|owed|until|cannot|can't|no in-game|without in-game|has not been|hasn't been|unverified|must be|still needs|waiting|NOT closing|ready for in-game|does not itself|not itself|\bif\b|\bonce\b|\bwhen\b)", re.I)
LOGREF = re.compile(r"(console-20\d\d-\d\d-\d\d|session log|live session|captured log|runtime log|in-game log|from the log|log shows|log confirms|log evidence|log proves)", re.I)
LOGPOS = re.compile(r"(no (new )?(script )?error|zero|confirm|verif|shows|proves|clean|did not|didn't|absent|present|fired|loaded|emitted|records?|PASS)", re.I)
STATIC = re.compile(r"(source-confirmed|hosted QA|QA (run )?[`\[]?\d*[`\]]? ?pass|exact-master|merged as|PR #\d+ merged|regression (check|test|marker|guard)|_rt_register|unit test|headless|luacheck|\blint|static (check|gate|evidence|proof)|qa/check|check_[a-z_]+\.ps1|deterministic|repository invariant|fix is still present|code review|Autonomous (completion|verification))", re.I)
SHIP = re.compile(r"(shipped|deployed|uploaded|Fixed in|fix candidate|landed|released|implemented|merged)", re.I)
SUPERSEDE = re.compile(r"(superseded by|supersed\w+ (by|into)|duplicate of|consolidated into|folded into|merged into|tracked (under|in|by|as|separately in)|rolled into|absorbed (by|into)|covered by|moved to|continues? (in|under|as)|replaced by|closing in favou?r of|subsumed (by|into|under))\s*(the )?(deployed |open |umbrella |issue |parent )*#?(\d{1,4})", re.I)
REF = re.compile(r'(?<![\w/])#(\d{1,4})\b')
TOOL_TITLE = re.compile(r"(\bCI\b|\bQA\b|ship(\.ps1| pipeline| path|-cycle)?\b|pre-commit|workflow|worktree|tracker|launcher|VMBLauncher|changelog|\bdocs?\b|documentation|runbook|\bgate\b|check_[a-z_]+|\blint|luacheck|headless|release (manifest|asset|zip)|updater|\bbranch(es)?\b|GitHub|issue (label|lifecycle|card)|live-test card|script(s)? lane|harness|hook(s)? install|repo(sitory)?\b|stale probes)", re.I)
LOGDUMP_TITLE = re.compile(r"^(logs?\b|test log|game log|log (for|cwv|in)\b|logs related)", re.I)
MOD_TITLE = [(r'\b(cwv|cross[- ]?weapon)', 'cwv'), (r'\b(woc|weapons of chaos)\b', 'woc'), (r'\b(wt|weapon[_ ]tweaker)(_dev)?\b', 'wt'),
             (r'\b(cosmetics?(_tweaker)?|cos)\b', 'cosmetics'), (r'\bdcp\b|dynamic portraits', 'dcp'), (r'\b(ct|ct_dev|chaos[_ ]wastes)\b', 'cw'),
             (r'\b(et|enemy[_ ]tweaker)\b', 'enemies'), (r'\b(cim|crafting in modded)\b', 'cim'), (r'\b(mp|modded progression)\b', 'mp'),
             (r'\b(crt|career[_ ]tweaker)\b', 'career'), (r'\b(gut|gui tweaker|mod tweaker|tweaker: gui)\b', 'gut'), (r'\b(gt|gt_dev|general[_ ]tweaker)\b', 'gt')]

def mod_and_cat(x):
    Ls = set(L.labels(x)); m = L.mod_of(Ls); title = x['title']
    if m == 'other':
        for rx, mm in MOD_TITLE:
            if re.search(rx, title, re.I): m = mm + '?'; break
    if Ls & {'tooling', 'documentation'}: cat = 'tooling'
    elif 'audit' in Ls: cat = 'audit'
    elif LOGDUMP_TITLE.search(title.strip()): cat = 'logdump'
    elif m == 'other' and TOOL_TITLE.search(title): cat = 'tooling?'
    elif 'question' in Ls: cat = 'question'
    else: cat = 'runtime'
    typ = 'crash' if 'crash' in Ls or re.search(r'\b(CTD|crash\w*|fatal|freeze|access violation)', title, re.I) else ('bug' if 'bug' in Ls else ('feature' if 'feature' in Ls else ('enhancement' if 'enhancement' in Ls else 'unlabelled')))
    prio = next((p for p in ['0-critical', '1-major', '2-moderate', '3-low'] if p in Ls), '')
    return m, cat, typ, prio

def analyse(x):
    n = x['number']; Ls = L.labels(x)
    nodes = tl[n]['timelineItems']['nodes']
    ce = [e for e in nodes if e['__typename'] == 'ClosedEvent']; last = ce[-1]
    t_close = L.ts(last['createdAt']); cl = last['closer']
    kind = 'MANUAL' if cl is None else ('PR' if cl['__typename'] == 'PullRequest' else 'COMMIT')
    closer = '' if cl is None else (f"PR#{cl['number']}" if kind == 'PR' else cl['oid'][:9])
    cs = by.get(n, [])
    win = datetime.timedelta(minutes=10)
    pre = [cm for cm in cs if L.ts(cm['created_at']) <= t_close + win]
    post = [cm for cm in cs if L.ts(cm['created_at']) > t_close + win]
    near = [cm for cm in cs if abs((L.ts(cm['created_at']) - t_close).total_seconds()) <= 600]
    ship_i = next((i for i, cm in enumerate(pre) if SHIP.search(cm['body'] or '')), None)
    logev = []; static = []
    verdicts = []  # chronological (time, code, who, text, comment-id); codes: P/N/M human-typed, p agent-attributed
    for i, cm in enumerate(cs):
        b = cm['body'] or ''; t = strip_att(b); when = L.ts(cm['created_at'])
        if is_human_typed(cm):
            p = bool(POS.search(t)); ng = bool(NEG.search(t))
            code = 'M' if (p and ng) else ('P' if p else ('N' if ng else None))
            if code: verdicts.append((when, code, cm['user']['login'], t[:160], id(cm)))
        else:
            for m in ATTR.finditer(b):
                ctx = b[max(0, m.start() - 70): m.end() + 50]
                if not ATTR_NEG.search(ctx):
                    verdicts.append((when, 'p', 'agent-attributed', ctx.replace('\n', ' ')[:160], id(cm))); break
            if LOGREF.search(b) and (ship_i is None or i >= ship_i) and LOGPOS.search(b): logev.append(when)
            if STATIC.search(b): static.append(when)
    fixed_label = 'Fixed' in Ls
    fl_events = [e for e in le[str(n)]['timelineItems']['nodes'] if e['__typename'] == 'LabeledEvent' and e['label'] and e['label']['name'] == 'Fixed']
    pre_v = [v for v in verdicts if v[0] <= t_close + win]
    post_v = [v for v in verdicts if v[0] > t_close + win]
    tail_ids = {id(cm) for cm in (pre[-3:] + near)}
    attr_tail = [v for v in pre_v if v[1] == 'p' and v[4] in tail_ids]
    hv = [v for v in pre_v if v[1] in 'PNM']
    last_h = hv[-1] if hv else None
    if attr_tail: ev = 'A'; evn = f"closing-window agent comment attributes in-game confirmation: {attr_tail[-1][3][:90]}"
    elif last_h and last_h[1] == 'P': ev = 'A'; evn = f"last human-typed verdict before close positive ({last_h[2]} {str(last_h[0])[:10]}): {last_h[3][:90]}"
    elif last_h and last_h[1] == 'M': ev = 'A' if fixed_label else 'A?'; evn = f"mixed human-typed verdict before close ({last_h[2]} {str(last_h[0])[:10]}): {last_h[3][:90]}"
    elif last_h and last_h[1] == 'N': ev = 'N!'; evn = f"last human-typed verdict before close NEGATIVE ({last_h[2]} {str(last_h[0])[:10]}): {last_h[3][:90]}"
    elif any(v[1] == 'p' for v in pre_v): ev = 'A'; evn = f"earlier agent comment attributes in-game confirmation: {[v for v in pre_v if v[1]=='p'][-1][3][:90]}"
    elif fixed_label and fl_events and L.ts(fl_events[-1]['createdAt']) <= t_close + win: ev = 'A3'; evn = 'Fixed label applied before close with no confirmation text (owner UI click presumed)'
    elif any(w <= t_close + win for w in logev): ev = 'B'; evn = 'agent cites a console/session log after the ship claim'
    elif any(w <= t_close + win for w in static): ev = 'C'; evn = 'static/CI/regression wording only'
    elif ship_i is not None or kind != 'MANUAL': ev = 'D'; evn = 'ship/merge claim only, no verification wording'
    else: ev = 'D'; evn = 'no fix or verification wording before close'
    if ev in ('B', 'C', 'D') and fixed_label and fl_events:
        evn += ' | Fixed label applied %s (after close)' % fl_events[-1]['createdAt'][:10]
    sup = None
    close_text = '\n'.join((cm['body'] or '') for cm in (near or pre[-1:]))
    ms = SUPERSEDE.search(close_text)
    if ms: sup = int(ms.group(ms.lastindex))
    m, cat, typ, prio = mod_and_cat(x)
    return dict(n=n, title=x['title'], author=x['user']['login'], labels=Ls, mod=m, cat=cat, typ=typ, prio=prio, reason=x['state_reason'],
                t_close=t_close, kind=kind, closer=closer, n_comments=len(cs), n_pre=len(pre), n_post=len(post), near=near, pre=pre, post=post,
                ev=ev, evn=evn, verdicts=verdicts, post_v=post_v, sup=sup, fixed_label=fixed_label, reopened=sum(1 for e in nodes if e['__typename'] == 'ReopenedEvent'),
                lifecycle_at_close=[l for l in Ls if l in ('verify-fix', 'diagnostics-armed', 'not-started', 'Fixed')])

SIG = re.compile(r"(regress\w*|still (broken|crash|fail|happen|occur|repro|present|there|wrong)\w*|recur\w*|re-?open\w*|same (symptom|class|bug|crash|root cause|failure|signature)|not (actually |fully |really )?fixed|came back|resurfac\w*|reappear\w*|incomplete|did not fix|didn't fix|insufficient|residual|never (actually )?(worked|verified|fixed)|unverified|was closed (without|before)|closed prematurely|reintroduc\w*|re-?broke\w*|sibling of closed)", re.I)
def open_refs():
    """closed issue number -> list of (open issue number, context, signal words)"""
    out = collections.defaultdict(list)
    for o in c['openi']:
        texts = [(o.get('body') or '')] + [(cm['body'] or '') for cm in by.get(o['number'], [])]
        best = {}
        for tx in texts:
            for m in REF.finditer(tx):
                k = int(m.group(1))
                if k in closed and k != o['number']:
                    ctx = tx[max(0, m.start() - 170): m.end() + 170].replace('\r', '').replace('\n', ' ')
                    sigs = sorted({mm.group(0).lower() for mm in SIG.finditer(ctx)})
                    if k not in best or (sigs and not best[k][1]): best[k] = (ctx, sigs)
        for k, (ctx, sigs) in best.items(): out[k].append((o['number'], ctx, sigs))
    return out

if __name__ == '__main__':
    rows = [analyse(x) for x in c['closed']]
    comp = [r for r in rows if r['reason'] == 'completed']
    print('closed', len(rows), 'completed', len(comp))
    print('category', collections.Counter(r['cat'] for r in rows))
    print('kind', collections.Counter(r['kind'] for r in rows))
    rt = [r for r in comp if r['cat'] == 'runtime']
    print('runtime completed', len(rt), collections.Counter(r['ev'] for r in rt))
    print('runtime completed by Fixed label x ev', sorted(collections.Counter((r['fixed_label'], r['ev']) for r in rt).items()))
    print('lifecycle at close (runtime completed)', collections.Counter(tuple(sorted(r['lifecycle_at_close'])) for r in rt))
