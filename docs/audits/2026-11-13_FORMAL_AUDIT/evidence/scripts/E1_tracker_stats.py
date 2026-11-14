# E1: tracker process statistics from the cached issue data (read-only).
import json, os, re, collections, datetime, statistics, sys
A = r"<audit-workspace>"; D = os.path.join(A, "data")
def load_concat(p):
    raw = open(p, encoding="utf-8").read(); dec = json.JSONDecoder(); i = 0; out = []
    while i < len(raw):
        while i < len(raw) and raw[i].isspace(): i += 1
        if i >= len(raw): break
        obj, j = dec.raw_decode(raw, i); out += obj; i = j
    return out
openi = json.load(open(os.path.join(D, "open_issues.json"), encoding="utf-8"))
closed = [x for x in load_concat(os.path.join(D, "closed_raw.json")) if "pull_request" not in x]
comments = load_concat(os.path.join(D, "comments_raw.json"))
by = collections.defaultdict(list)
for c in comments:
    by[int(c["issue_url"].rsplit("/", 1)[1])].append(c)
for n in by: by[n].sort(key=lambda c: c["created_at"])
def labels(x): return [l["name"] for l in x["labels"]]
LIFE = {"not-started", "diagnostics-armed", "verify-fix"}
PRIO = {"0-critical", "1-major", "2-moderate", "3-low"}
TYPE = {"bug", "enhancement", "feature"}
CARD = re.compile(r"^\s*##\s+CURRENT LIVE TEST\b", re.M)
VER = re.compile(r"\bv?(\d+\.\d+\.\d+(?:-(?:dev|beta|alpha|rc\d*))?)\b")
FALL = re.compile(r"\*\*Fallback 1\*\*")
def d(s): return datetime.datetime.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")
NOW = datetime.datetime(2026, 11, 13, 20, 0, 0)
print("open issues:", len(openi), " closed issues:", len(closed), " comments total:", len(comments))
auth = collections.Counter(c["user"]["login"] for c in comments)
print("comment authors (all issues):", auth.most_common(12))
tb = sum(len((c.get("body") or "").encode("utf-8")) for c in comments)
print("comment bytes total: %d (~%d tokens)" % (tb, tb // 4))
open_nums = set(int(x["number"]) for x in openi)
oc = [c for n in open_nums for c in by.get(n, [])]
print("comments on OPEN issues:", len(oc), "bytes", sum(len((c.get('body') or '').encode('utf-8')) for c in oc))
print("  by author:", collections.Counter(c["user"]["login"] for c in oc).most_common(8))
# cards
def cards(n): return [c for c in by.get(n, []) if CARD.search(c.get("body") or "")]
card_counts = []; card_bytes = []; reissue = []; life = collections.Counter(); nocard_ready = 0
issue_iss = issue_author = collections.Counter()
title_words = []; body_words = []; fallback_issues = 0
card_resp = collections.Counter(); cards_total_open = 0
ready_age_days = []; cards_per_ready = []
viol = collections.Counter()
last_card_age = []
tester_after_card = 0
for x in openi:
    n = int(x["number"]); L = set(labels(x))
    lc = L & LIFE; life[",".join(sorted(lc)) or "(none)"] += 1
    if len(lc) != 1: viol["lifecycle!=1"] += 1
    if len(L & PRIO) != 1: viol["priority!=1"] += 1
    if len(L & TYPE) != 1: viol["type!=1"] += 1
    t = re.sub(r"^\s*(\[[^\]]+\]|[A-Za-z_ ]+:)\s*", "", x["title"])
    tw = len(t.split()); title_words.append(tw)
    bw = len((x.get("body") or "").split()); body_words.append(bw)
    cs = cards(n); card_counts.append(len(cs)); cards_total_open += len(cs)
    for c in cs: card_bytes.append(len(c["body"].encode("utf-8")))
    if any(FALL.search(c.get("body") or "") for c in by.get(n, [])): fallback_issues += 1
    ready = bool(lc & {"diagnostics-armed", "verify-fix"})
    if ready:
        cards_per_ready.append(len(cs))
        if not cs: nocard_ready += 1
        else:
            last = cs[-1]; last_card_age.append((NOW - d(last["created_at"])).days)
            # any non-owner comment after the newest card?
            after = [c for c in by[n] if c["created_at"] > last["created_at"] and c["user"]["login"] != "Ensrick"]
            if after: tester_after_card += 1
    # response to cards: for each card, is there a non-owner comment before the next card?
    for i, c in enumerate(cs):
        nxt = cs[i + 1]["created_at"] if i + 1 < len(cs) else "9999"
        resp = [k for k in by[n] if c["created_at"] < k["created_at"] < nxt and k["user"]["login"] != "Ensrick"]
        card_resp["card followed by a non-owner comment" if resp else "card with no non-owner comment before next card/now"] += 1
print("\nlifecycle label sets on open issues:", dict(life))
print("label cardinality violations on open issues:", dict(viol))
def q(a, p): a = sorted(a); return a[min(len(a) - 1, int(p * len(a)))] if a else None
print("\nCURRENT LIVE TEST cards on OPEN issues: total %d over %d issues; issues with >=1 card: %d" % (cards_total_open, len(openi), sum(1 for k in card_counts if k)))
print("  cards per open issue: mean %.2f median %s p90 %s max %s" % (statistics.mean(card_counts), statistics.median(card_counts), q(card_counts, .9), max(card_counts)))
print("  distribution:", sorted(collections.Counter(card_counts).items()))
print("  ready (verify-fix/diag-armed) issues: %d; cards per ready issue mean %.2f median %s max %s; ready with zero cards: %d" % (len(cards_per_ready), statistics.mean(cards_per_ready), statistics.median(cards_per_ready), max(cards_per_ready), nocard_ready))
print("  card size bytes: mean %d median %d max %d ; total card bytes %d (~%d tokens)" % (statistics.mean(card_bytes), statistics.median(card_bytes), max(card_bytes), sum(card_bytes), sum(card_bytes) // 4))
print("  newest-card age on ready issues (days): median %s p90 %s max %s" % (statistics.median(last_card_age), q(last_card_age, .9), max(last_card_age)))
print("  ready issues where ANY non-owner commented after the newest card:", tester_after_card)
print("  card outcome:", dict(card_resp))
# closed-issue cards
cc = [len(cards(int(x["number"]))) for x in closed]
print("cards on CLOSED issues: total %d over %d closed issues (%d with >=1)" % (sum(cc), len(closed), sum(1 for k in cc if k)))
allcards = sum(cc) + cards_total_open
print("cards overall:", allcards)
print("\ntitle words (after prefix) on open issues: median %s; >8 words: %d of %d" % (statistics.median(title_words), sum(1 for w in title_words if w > 8), len(title_words)))
print("body words on open issues: median %s p90 %s max %s; >200 words: %d; >400: %d" % (statistics.median(body_words), q(body_words, .9), max(body_words), sum(1 for w in body_words if w > 200), sum(1 for w in body_words if w > 400)))
print("open issues with a 'Fallback 1' comment (three-fallback rule):", fallback_issues, "of", len(openi))
nc = [len(by.get(int(x["number"]), [])) for x in openi]
print("comments per open issue: mean %.1f median %s p90 %s max %s" % (statistics.mean(nc), statistics.median(nc), q(nc, .9), max(nc)))
# non-owner activity
nonowner = [c for c in comments if c["user"]["login"] != "Ensrick"]
print("\nnon-owner comments total:", len(nonowner), collections.Counter(c["user"]["login"] for c in nonowner).most_common(10))
rr = sorted(c["created_at"] for c in comments if c["user"]["login"] == "RainReligion")
print("RainReligion comments:", len(rr), "first", rr[0][:10] if rr else None, "last", rr[-1][:10] if rr else None)
bym = collections.Counter(c["created_at"][:7] for c in comments if c["user"]["login"] == "RainReligion")
print("  per month:", sorted(bym.items()))
bym2 = collections.Counter(c["created_at"][:7] for c in comments if c["user"]["login"] == "Ensrick")
print("owner-account comments per month:", sorted(bym2.items()))
cm = collections.Counter(c["created_at"][:7] for c in comments if CARD.search(c.get("body") or ""))
print("cards posted per month:", sorted(cm.items()))
# comment classes on open issues (owner account)
kinds = collections.Counter()
for c in oc:
    b = c.get("body") or ""
    if CARD.search(b): kinds["CURRENT LIVE TEST card"] += 1
    elif FALL.search(b): kinds["three-fallback comment"] += 1
    elif re.search(r"CLOSURE AUTHORIZATION", b): kinds["closure authorization"] += 1
    elif re.search(r"(?i)lifecycle|label", b) and len(b) < 900: kinds["short lifecycle/label note"] += 1
    elif re.search(r"(?i)\bshipped\b|\bdeployed\b|uploaded", b): kinds["ship/deploy note"] += 1
    else: kinds["other"] += 1
print("\ncomment kinds on open issues:", dict(kinds))
# top issues by card count
top = sorted(((len(cards(int(x['number']))), int(x['number']), x['title'][:60]) for x in openi), reverse=True)[:12]
print("top open issues by card count:", top)
# age
ages = [(NOW - d(x["created_at"])).days for x in openi]
print("open issue age days: median %s p90 %s" % (statistics.median(ages), q(ages, .9)))
ext = collections.Counter(x["user"]["login"] for x in openi)
print("open issue authors:", ext.most_common(8))
