# A5 helper: classify family host-Lua tests as behavioural vs source-text assertions (heuristic). Read-only.
import os, re, sys
d = r"qa\lua\tests"
fams = {"cim": re.compile(r"^test_cim_"), "mp": re.compile(r"^test_mp_"), "crt": re.compile(r"^test_crt_")}
for fam, pat in fams.items():
    tot_cases = tot_text = tot_beh = tot_lines = 0; files = 0; rows = []
    for f in sorted(os.listdir(d)):
        if not pat.match(f): continue
        files += 1
        s = open(os.path.join(d, f), encoding="utf-8", errors="replace").read()
        lines = s.count("\n") + 1
        cases = len(re.findall(r"\bH\.test(?:_if)?\(", s))
        # source-text assertions: plain find on a source/text variable, H.contains(source..), match on source
        text = len(re.findall(r"(?:source|src|text|body|main|entry|chunk|code|content)[\w\.]*:find\(|H\.(?:contains|not_contains|matches)\(|:match\(\"|string\.find\((?:source|src|text|body|main|entry)", s))
        # behavioural: calls into loaded module objects followed by equal/truthy assertions
        beh = len(re.findall(r"H\.(?:equal|deep_equal|same|truthy|falsy|is_true|is_false|is_nil|raises|near)\(", s))
        reads = len(re.findall(r"io\.open\(|read_file\(|read_source\(|H\.read\(|slurp\(", s))
        loads = len(re.findall(r"loadfile\(|dofile\(|load_module\(|loadstring\(|require\(", s))
        tot_cases += cases; tot_text += text; tot_beh += beh; tot_lines += lines
        rows.append((f, lines, cases, text, beh, reads, loads))
    print("== %s: files=%d lines=%d cases=%d text_asserts~%d value_asserts~%d" % (fam, files, tot_lines, tot_cases, tot_text, tot_beh))
    for r in rows:
        ratio = r[3] / max(1, r[3] + r[4])
        print("   %-48s lines=%-5d cases=%-4d text~%-4d value~%-4d reads=%-3d loads=%-3d text_share=%.0f%%" % (r + (ratio * 100,)))
