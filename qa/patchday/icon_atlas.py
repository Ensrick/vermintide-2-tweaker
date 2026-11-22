"""Patch-day canary, part 2 (WP-T-04): do the literal icon names of the mods still exist in the game's icon atlases?

Python port of the 2026-11-13 audit script D4_icon_atlas_check.sh, over every mod instead of one. It collects every
literal `icon = "<name>"` in the mods' scripts/ folders and looks for an entry `<name> = {` in the decompile's icon
atlases: every scripts/ui/atlas_settings/*.lua. The audit checked gui_icons_atlas.lua only, from which game patch
6.12 removed icons (#1686). The mods also use icons of gui_menus_atlas, gui_hud_atlas, gui_belakor_atlas and
others, which that one file would report as missing. --atlas narrows the check to one file. Icons built at run time
or reused from vanilla tables by reference are not seen (blind spot of the audit).

Static and read-only. Exit 0 when every name exists or is allowlisted, 2 when one does not, 3 on a usage error.
Prints one summary line: "icon names: <n> checked, <m> missing (<a> allowlisted)".

Usage:
    python icon_atlas.py --decompile <Vermintide-2-Source-Code> [--repo <vermintide-2-tweaker>] [--mods <dir> ...]
                         [--allow qa/patchday/icon_allowlist.txt] [--atlas <file>] [--self-test]
"""
import argparse
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
ICON_RE = re.compile(r"\bicon\s*=\s*\"([a-z0-9_]+)\"")
DIR_RE = re.compile(r"\bDir\s*=\s*'([^']+)'")


def inventory_dirs(repo):
    with open(os.path.join(repo, "tools", "mod-inventory.psd1"), encoding="utf-8-sig") as f:
        return DIR_RE.findall(f.read())


def read_allowlist(path):
    allowed = set()
    if path and os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                entry = line.split("#", 1)[0].strip()
                if entry:
                    allowed.add(entry)
    return allowed


def atlas_names(atlases):
    names = set()
    for atlas in atlases:
        with open(atlas, encoding="utf-8-sig", errors="replace") as f:
            names.update(re.findall(r"(?m)^\s*\[?\"?([A-Za-z0-9_]+)\"?\]?\s*=\s*\{", f.read()))
    return names


def check(atlas, repo, mods, allow_path, quiet=False):
    names = atlas_names(atlas)
    allowed = read_allowlist(allow_path)
    seen = {}
    for mod in mods:
        root = mod if os.path.isabs(mod) else os.path.join(repo, mod)
        for dirpath, _dirs, files in os.walk(os.path.join(root, "scripts")):
            for name in sorted(files):
                if not name.endswith(".lua"):
                    continue
                path = os.path.join(dirpath, name)
                with open(path, encoding="utf-8", errors="replace") as f:
                    for number, line in enumerate(f, 1):
                        if line.lstrip().startswith("--"):
                            continue
                        for m in ICON_RE.finditer(line):
                            seen.setdefault(m.group(1), (os.path.relpath(path, repo).replace("\\", "/"), number))
    missing = sorted(k for k in seen if k not in names and k not in allowed)
    allowlisted = sorted(k for k in seen if k not in names and k in allowed)
    if not quiet:
        for k in missing:
            print("MISSING-IN-ATLAS %s  (first at %s:%d)" % (k, seen[k][0], seen[k][1]))
        for k in allowlisted:
            print("allowlisted %s" % k)
    print("icon names: %d checked, %d missing (%d allowlisted)" % (len(seen), len(missing), len(allowlisted)))
    return 2 if missing else 0


def self_test(atlas, repo, allow_path):
    temp = tempfile.mkdtemp(prefix="vt2-patchday-icons-")
    try:
        scripts = os.path.join(temp, "planted_mod", "scripts", "mods", "planted_mod")
        os.makedirs(scripts)
        with open(os.path.join(scripts, "planted_mod.lua"), "w", encoding="utf-8") as f:
            f.write('return { icon = "vt2_patchday_planted_missing_icon" }\n')
        code = check(atlas, repo, [os.path.join(temp, "planted_mod")], allow_path, quiet=True)
        ok = code == 2
        print("self-test: planted icon vt2_patchday_planted_missing_icon -> exit %d (%s)" % (code, "PASS" if ok else "FAIL, want 2"))
        return 0 if ok else 2
    finally:
        shutil.rmtree(temp, ignore_errors=True)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--decompile", required=True)
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--mods", nargs="*")
    parser.add_argument("--allow", default=os.path.join(HERE, "icon_allowlist.txt"))
    parser.add_argument("--atlas", default=None)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    folder = os.path.join(args.decompile, "scripts", "ui", "atlas_settings")
    if args.atlas:
        atlas = [args.atlas]
    elif os.path.isdir(folder):
        atlas = sorted(os.path.join(folder, n) for n in os.listdir(folder) if n.endswith(".lua"))
    else:
        atlas = []
    if not atlas or not all(os.path.isfile(a) for a in atlas):
        print("ERROR: icon atlas files not found under %s" % folder)
        return 3
    if args.self_test:
        return self_test(atlas, args.repo, args.allow)
    mods = args.mods if args.mods else inventory_dirs(args.repo)
    return check(atlas, args.repo, mods, args.allow, quiet=args.quiet)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
