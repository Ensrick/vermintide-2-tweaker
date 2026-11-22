"""Patch-day canary, part 1 (WP-T-04): do the literal string-form VMF hook targets of the mods still resolve to a
method defined in the decompiled vanilla source?

Ported from the 2026-11-13 audit script B2_hook_targets.py: it indexes every `Class.method = function`,
`function Class:method(` and `Class.method = Other.method` definition under the decompile's scripts/, foundation/
and core/, records `X = class(X, Parent)` parents, and resolves a hook target by walking the whole parent chain.
Then it reads every `mod:hook("Class", "method", ...)` (also hook_safe and hook_origin) in the mods' scripts/
folders. Table-form hooks (`mod:hook(SomeTable, "method", ...)`) cannot be checked this way and are only counted.

Static and read-only. Exit 0 when every target resolves or is allowlisted, 2 when one does not, 3 on a usage error.
Prints one summary line: "hook targets: <n> checked, <u> unresolved (<a> allowlisted)".

Usage:
    python hook_targets.py --decompile <Vermintide-2-Source-Code> [--repo <vermintide-2-tweaker>]
                           [--mods <dir> ...] [--allow qa/patchday/hook_allowlist.txt] [--self-test]
--mods defaults to every Dir of tools/mod-inventory.psd1. --self-test plants mod:hook("IngameUI", "not_in_modded", f)
(the hook game patch 6.12 broke) in a temporary mod folder and requires exit 2.
"""
import argparse
import collections
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_REPO = os.path.normpath(os.path.join(HERE, "..", ".."))

FN_RE = re.compile(r"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)[\.:]([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.M)
ASG_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\b", re.M)
ALIAS_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*$", re.M)
CLASS_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*class\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:,\s*([A-Za-z_][A-Za-z0-9_]*))?", re.M)
HOOK_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_\.]*[:\.](hook|hook_safe|hook_origin)\(\s*\"([A-Za-z_][A-Za-z0-9_]*)\"\s*,\s*\"([A-Za-z_][A-Za-z0-9_]*)\"")
TABLE_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_\.]*[:\.](hook|hook_safe|hook_origin)\(\s*([A-Za-z_][A-Za-z0-9_\.]*)\s*,\s*\"([A-Za-z_][A-Za-z0-9_]*)\"")
DIR_RE = re.compile(r"\bDir\s*=\s*'([^']+)'")


def index_vanilla(decompile):
    methods = collections.defaultdict(set)
    parents = {}
    files = 0
    for base in ("scripts", "foundation", "core"):
        for dirpath, _dirs, names in os.walk(os.path.join(decompile, base)):
            for name in names:
                if not name.endswith(".lua"):
                    continue
                files += 1
                with open(os.path.join(dirpath, name), encoding="utf-8-sig", errors="replace") as f:
                    text = f.read()
                for m in FN_RE.finditer(text):
                    methods[m.group(1)].add(m.group(2))
                for m in ASG_RE.finditer(text):
                    methods[m.group(1)].add(m.group(2))
                for m in ALIAS_RE.finditer(text):
                    methods[m.group(1)].add(m.group(2))
                for m in CLASS_RE.finditer(text):
                    if m.group(3):
                        parents[m.group(1)] = m.group(3)
    return methods, parents, files


def resolves(methods, parents, cls, meth):
    seen = set()
    while cls and cls not in seen:
        seen.add(cls)
        if meth in methods.get(cls, ()):
            return True
        cls = parents.get(cls)
    return False


def inventory_dirs(repo):
    path = os.path.join(repo, "tools", "mod-inventory.psd1")
    with open(path, encoding="utf-8-sig") as f:
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


def check(decompile, repo, mods, allow_path, quiet=False):
    methods, parents, files = index_vanilla(decompile)
    allowed = read_allowlist(allow_path)
    checked = 0
    table_form = 0
    unresolved = []
    allowlisted = []
    for mod in mods:
        root = mod if os.path.isabs(mod) else os.path.join(repo, mod)
        for dirpath, _dirs, names in os.walk(os.path.join(root, "scripts")):
            for name in sorted(names):
                if not name.endswith(".lua"):
                    continue
                path = os.path.join(dirpath, name)
                with open(path, encoding="utf-8", errors="replace") as f:
                    for number, line in enumerate(f, 1):
                        if line.lstrip().startswith("--"):
                            continue
                        m = HOOK_RE.search(line)
                        if m:
                            checked += 1
                            cls, meth = m.group(2), m.group(3)
                            if not resolves(methods, parents, cls, meth):
                                where = os.path.relpath(path, repo).replace("\\", "/")
                                target = "%s.%s" % (cls, meth)
                                (allowlisted if target in allowed else unresolved).append((where, number, target, cls in methods or cls in parents))
                            continue
                        m = TABLE_RE.search(line)
                        if m and m.group(2) != "_G":
                            table_form += 1
    if not quiet:
        print("vanilla files indexed: %d, classes and tables with methods: %d" % (files, len(methods)))
        print("table-form hooks (not checked): %d" % table_form)
        for where, number, target, known in unresolved:
            print("UNRESOLVED %s:%d  %s%s" % (where, number, target, "" if known else "   [class not in the decompile]"))
        for where, number, target, _known in allowlisted:
            print("allowlisted %s:%d  %s" % (where, number, target))
    print("hook targets: %d checked, %d unresolved (%d allowlisted)" % (checked, len(unresolved), len(allowlisted)))
    return 2 if unresolved else 0


def self_test(decompile, repo, allow_path):
    temp = tempfile.mkdtemp(prefix="vt2-patchday-")
    try:
        scripts = os.path.join(temp, "planted_mod", "scripts", "mods", "planted_mod")
        os.makedirs(scripts)
        with open(os.path.join(scripts, "planted_mod.lua"), "w", encoding="utf-8") as f:
            f.write('local mod = get_mod("planted_mod")\nmod:hook("IngameUI", "not_in_modded", function(func, self) return func(self) end)\n')
        code = check(decompile, repo, [os.path.join(temp, "planted_mod")], allow_path, quiet=True)
        ok = code == 2
        print("self-test: planted IngameUI.not_in_modded -> exit %d (%s)" % (code, "PASS" if ok else "FAIL, want 2"))
        return 0 if ok else 2
    finally:
        shutil.rmtree(temp, ignore_errors=True)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--decompile", required=True)
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--mods", nargs="*")
    parser.add_argument("--allow", default=os.path.join(HERE, "hook_allowlist.txt"))
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    if not os.path.isdir(os.path.join(args.decompile, "scripts")):
        print("ERROR: not a decompile root (no scripts/): %s" % args.decompile)
        return 3
    if args.self_test:
        return self_test(args.decompile, args.repo, args.allow)
    mods = args.mods if args.mods else inventory_dirs(args.repo)
    return check(args.decompile, args.repo, mods, args.allow, quiet=args.quiet)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
