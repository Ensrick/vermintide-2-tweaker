# E1: check a draft root guide (AGENTS.md) against the line patterns that
# qa/check_publication_doctrine.ps1 rejects in root guides, plus size, ASCII and privacy.
import re, sys
p = sys.argv[1]
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 6144
raw = open(p, "rb").read()
s = raw.decode("utf-8")
anchor = "#66-ship-doctrine-keyed-off-the-mod_version-suffix-canonical-2026-07-01"
print("bytes:", len(raw), "limit:", limit, "OK" if len(raw) <= limit else "TOO LARGE")
print("has CLAUDE link:", "](CLAUDE.md)" in s, "| has 6.6 link:", ("](PROJECT_STANDARDS.md" + anchor + ")") in s)
BS = chr(92)
pats = {
    "ship recipe line": r"^\s*\." + BS + BS + "tools" + BS + BS + "ship" + BS + BS + r"(?:claim|ship)\.ps1\b",
    "launcher all/upload": r"(?i)(?:VMBLauncher(?:\.exe)?|vmblauncher|&\s+`?\$\w+)\s+(?:all|upload)\b",
    "standalone all": r"(?i)(?:\bor\b|\buse\b|\brun\b|->)\s+(?:`all(?:\s|`|<)|all\s*<)",
    "restart after upload": r"(?i)after every upload[^\r\n]*restart\s+(?:VT2|Steam|the game|game)\b",
    "post-upload landing": r"(?i)(?:after (?:an? )?(?:upload|publishing|publication)[^\r\n]*\b(?:commit|push|pull request)\b|\b(?:commit|push|pull request)\b[^\r\n]*after (?:the )?(?:upload|publishing|publication))",
    "hardcoded launcher": r"(?i)vmb-launcher-main-current-[0-9]+|VMBLauncher\.exe",
    "raw vmb build": r"(?i)vmb\.js",
    "workshop size": r"(?i)Always check Workshop page file size after upload",
    "bump every build": r"(?i)Bump MOD_VERSION \(3-segment semver \+ suffix\) every build|Always increment `?MOD_VERSION`? before every build",
    "confirmed-upload recovery": r"(?i)\b(?:confirmed\s+upload|post-upload|deploy-verify\s+mismatch|hash mismatch)\b",
    "non-ascii": r"[^\x00-\x7f]",
    "personal path": r"(?i)C:" + BS + BS + "Users",
}
bad = 0
for name, rx in pats.items():
    hits = [i + 1 for i, l in enumerate(s.split("\n")) if re.search(rx, l)]
    if hits: bad += 1
    print(f"{name}: {hits}")
print("RESULT:", "clean" if bad == 0 else f"{bad} pattern group(s) hit")
