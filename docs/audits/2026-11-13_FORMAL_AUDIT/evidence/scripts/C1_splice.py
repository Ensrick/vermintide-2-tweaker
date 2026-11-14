import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
new = open(sys.argv[2], encoding='utf-8').read()
i = s.index("### 5.6 Worked example")
j = s.index("### 5.7 Screenshot channel")
s = s[:i] + new + s[j:]
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('ok', len(s))
