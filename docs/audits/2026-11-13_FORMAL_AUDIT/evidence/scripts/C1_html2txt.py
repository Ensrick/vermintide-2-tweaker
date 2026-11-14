import sys, re, html
for p in sys.argv[1:]:
    s = open(p, encoding='utf-8', errors='replace').read()
    s = re.sub(r'(?is)<(script|style).*?</\1>', '', s)
    s = re.sub(r'(?i)<br\s*/?>|</p>|</div>|</h\d>|</li>|</tr>|</pre>|</dt>|</dd>', '\n', s)
    s = re.sub(r'(?s)<[^>]+>', '', s)
    s = html.unescape(s)
    s = re.sub(r'[ \t]+\n', '\n', s)
    s = re.sub(r'\n{3,}', '\n\n', s)
    out = p[:-5] + '.txt'
    open(out, 'w', encoding='utf-8').write(s)
    print(out, len(s))
