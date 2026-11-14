import sys, re
root = r"<audit-workspace>/issues\open"
for n in sys.argv[1:]:
    s = open(root + "\\" + n + ".md", encoding="utf-8", errors="replace").read()
    title = s.split("\n", 1)[0]
    labels = re.search(r"^labels: (.*)$", s, re.M).group(1)
    blocks = s.split("## COMMENT by ")
    cards = [b for b in blocks if "## CURRENT LIVE TEST" in b]
    print("=" * 100); print(title[:110]); print("labels:", labels[:150]); print("cards in thread:", len(cards), " comments:", len(blocks) - 1)
    if cards:
        c = cards[-1]
        c = c[c.index("## CURRENT LIVE TEST"):]
        print(c[:2300])
