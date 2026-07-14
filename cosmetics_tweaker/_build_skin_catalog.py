"""Build VETERAN_SKIN_CATALOG.md from VT2 source + in-game dumps.

Parses every weapon_skins*.lua in the decompiled VT2 source for skin metadata,
then cross-references against our /dump_glows + /dump_skin_rarities log output
to attach English display names where available. Emits a single markdown
catalog grouped by glow template (and "no template" / non-Veteran rarity).

Run from repo root:
    py cosmetics_tweaker\\_build_skin_catalog.py

Output: cosmetics_tweaker\\VETERAN_SKIN_CATALOG.md
"""
from __future__ import annotations
import re
import sys
import os
import glob
import csv
from pathlib import Path

REPO = Path(r"C:\Users\danjo\source\repos\vermintide-2-tweaker")
SRC = Path(r"C:\Users\danjo\source\repos\Vermintide-2-Source-Code")
SKIN_DIR_GLOBS = [
    SRC / "scripts" / "settings" / "equipment",
    SRC / "scripts" / "settings" / "dlcs",
]
OUT = REPO / "cosmetics_tweaker" / "VETERAN_SKIN_CATALOG.md"
ICON_EXTRACT_DIR = REPO.parent / "_vt2_item_icons_extract"
ICON_DIR = ICON_EXTRACT_DIR / "icons"
ICON_REFERENCE_OUT = ICON_EXTRACT_DIR / "WEAPON_ICON_MODEL_REFERENCE.csv"
ICON_REFERENCE_GUIDE_OUT = ICON_EXTRACT_DIR / "WEAPON_ICON_MODEL_REFERENCE.md"

# Dump sources. The script also auto-scans the latest console_logs file for any
# [DUMP:names] / [DUMP:glows] / [DUMP:rarity] lines, so simply running the dump
# commands in-game and re-running this script picks up new English names.
LOG_DIR = Path(os.path.expandvars(r"%APPDATA%\Fatshark\Vermintide 2\console_logs"))

# Initial seed dumps from session tool results (still parsed in addition to logs
# so backfilled names from earlier sessions stay available even if the log file
# rolls over).
DUMP_FILES = [
    Path(r"C:\Users\danjo\.claude\projects\C--Users-danjo-source-repos\af0db1c3-0a9a-488e-902f-35b3bc2fb579\tool-results\toolu_0195Fky1wjLAGpeMiqE9jqRm.txt"),
    Path(r"C:\Users\danjo\.claude\projects\C--Users-danjo-source-repos\af0db1c3-0a9a-488e-902f-35b3bc2fb579\tool-results\toolu_01AWdhhgytr5zsmp7x17noBZ.txt"),
]


def find_recent_logs(n: int = 5) -> list[Path]:
    if not LOG_DIR.exists():
        return []
    files = sorted(LOG_DIR.glob("console-*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[:n]

# Each weapon_skins*.lua entry looks like:
#   {
#       name = "skin_key",
#       data = { ...fields, possibly nested braces e.g. can_wield = {...}... },
#   },
# The data block can contain nested {...} so we need a brace-balanced extractor,
# not a simple regex (data fields like `can_wield = { ... }` break greedy `.*?`).
NAME_RE = re.compile(r"\bname\s*=\s*\"([^\"]+)\"\s*,\s*data\s*=\s*\{")
FIELD_RE = re.compile(r"(\w+)\s*=\s*\"([^\"]*)\"")


def _extract_balanced(text: str, start: int) -> tuple[str, int]:
    """Return (body_inside_braces, end_pos_after_closing_brace).

    `start` points at the `{` opening the data block. We track depth and
    skip over Lua string literals so braces inside strings don't confuse us.
    """
    assert text[start] == "{"
    depth = 1
    i = start + 1
    n = len(text)
    while i < n:
        c = text[i]
        if c == '"':
            # Skip string literal (handle escaped quote).
            i += 1
            while i < n:
                if text[i] == '\\' and i + 1 < n:
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1 : i], i + 1
        i += 1
    raise ValueError("unbalanced braces")


def parse_skins(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    out = []
    for m in NAME_RE.finditer(text):
        skin_key = m.group(1)
        # m.end() points just past the data-opening `{` — back up one char to it.
        brace_pos = m.end() - 1
        try:
            body, _ = _extract_balanced(text, brace_pos)
        except ValueError:
            continue
        fields = dict(FIELD_RE.findall(body))
        fields["_skin_key"] = skin_key
        fields["_source_file"] = path.name
        out.append(fields)
    return out


def parse_dump_names(dump_files: list[Path]) -> dict[str, dict]:
    """Extract resolved English names + descriptions per skin key from log output.

    Looks for lines from /dump_glows like:
        [DUMP:glows] SKIN|<tpl>|name="..."|desc="..."|...|key=<skin_key>
    and from /dump_skin_rarities WITH/WITHOUT/WHITE/PAIR variants.
    """
    out: dict[str, dict] = {}

    skin_re = re.compile(r"SKIN\|[^|]+\|name=\"([^\"]*)\".*?\|key=([\w_]+)")
    desc_re = re.compile(r"SKIN\|[^|]+\|name=\"[^\"]*\"\|desc=\"([^\"]*)\"")
    with_re = re.compile(r"WITH\|[^|]+\|tpl=[^|]+\|name=\"([^\"]*)\"\|key=([\w_]+)")
    without_re = re.compile(r"WITHOUT\|[^|]+\|name=\"([^\"]*)\"\|key=([\w_]+)")
    white_re = re.compile(r"WHITE\|key=([\w_]+)\|rarity=[^|]+\|name=\"([^\"]*)\"\|desc=\"([^\"]*)\"")
    pair_re = re.compile(r"PAIR\|01_name=\"([^\"]*)\"\|01_tpl=([^|]+)\|01_rarity=[^|]+\|02_name=\"([^\"]*)\"\|02_tpl=([^|]+)\|02_rarity=[^|]+\|prefix=([\w_]+)")
    # [DUMP:names] from /dump_all_names — the comprehensive backfill source.
    name_full_re = re.compile(r"NAME\|key=([\w_]+)\|name=\"([^\"]*)\"\|desc=\"([^\"]*)\"")

    for path in dump_files:
        if not path.exists():
            print(f"[WARN] dump file missing: {path}", file=sys.stderr)
            continue
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            m = skin_re.search(line)
            if m:
                name, key = m.group(1), m.group(2)
                rec = out.setdefault(key, {})
                rec["name"] = name
                d = desc_re.search(line)
                if d:
                    rec["desc"] = d.group(1)
                continue
            m = with_re.search(line)
            if m:
                name, key = m.group(1), m.group(2)
                out.setdefault(key, {})["name"] = name
                continue
            m = without_re.search(line)
            if m:
                name, key = m.group(1), m.group(2)
                out.setdefault(key, {})["name"] = name
                continue
            m = white_re.search(line)
            if m:
                key, name, desc = m.group(1), m.group(2), m.group(3)
                rec = out.setdefault(key, {})
                rec["name"] = name
                rec["desc"] = desc
                continue
            m = pair_re.search(line)
            if m:
                n01, tpl01, n02, tpl02, prefix = m.groups()
                out.setdefault(prefix + "_runed_01", {})["name"] = n01
                out.setdefault(prefix + "_runed_02", {})["name"] = n02
                continue
            m = name_full_re.search(line)
            if m:
                key, name, desc = m.group(1), m.group(2), m.group(3)
                rec = out.setdefault(key, {})
                rec["name"] = name
                if desc and desc != "(loc fail)":
                    rec["desc"] = desc
    return out


def parse_existing_catalog_names(path: Path) -> dict[str, dict]:
    """Keep previously resolved names when old transient dump files disappear."""
    out: dict[str, dict] = {}
    if not path.exists():
        return out
    row_re = re.compile(r"^\|\s*(.*?)\s*\|\s*`([\w_]+)`\s*\|")
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = row_re.match(line)
        if not match:
            continue
        name, key = match.groups()
        if name and not name.startswith("_(name unresolved"):
            out[key] = {"name": name}
    return out


def weapon_family(skin_key: str) -> str:
    """Return the stable weapon-family portion of a skin key."""
    return re.sub(r"_skin_.*$", "", skin_key)


def write_icon_reference(skins: list[dict]) -> None:
    """Emit the source-of-truth skin -> icon -> hand-unit cross-reference."""
    ICON_EXTRACT_DIR.mkdir(parents=True, exist_ok=True)
    columns = [
        "weapon_family",
        "skin_key",
        "display_name",
        "display_name_loc_key",
        "inventory_icon",
        "png_filename",
        "png_present",
        "right_hand_unit",
        "left_hand_unit",
        "rarity",
        "material_settings_name",
        "source_file",
    ]
    rows = []
    for s in sorted(skins, key=lambda item: (weapon_family(item["_skin_key"]), item["_skin_key"])):
        icon = s.get("inventory_icon", "")
        png = f"{icon}.png" if icon else ""
        rows.append({
            "weapon_family": weapon_family(s["_skin_key"]),
            "skin_key": s["_skin_key"],
            "display_name": s.get("_localized_name", ""),
            "display_name_loc_key": s.get("display_name", ""),
            "inventory_icon": icon,
            "png_filename": png,
            "png_present": "yes" if png and (ICON_DIR / png).is_file() else "no",
            "right_hand_unit": s.get("right_hand_unit", ""),
            "left_hand_unit": s.get("left_hand_unit", ""),
            "rarity": s.get("rarity", ""),
            "material_settings_name": s.get("material_settings_name", ""),
            "source_file": s["_source_file"],
        })

    with ICON_REFERENCE_OUT.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)

    dual_axes = [row for row in rows if row["weapon_family"] == "dw_dual_axe"]
    missing = [row for row in rows if row["inventory_icon"] and row["png_present"] == "no"]
    lines = [
        "# Weapon Icon / Model Reference",
        "",
        "Generated from the decompiled game's `weapon_skins*.lua` definitions by",
        "`vermintide-2-tweaker/cosmetics_tweaker/_build_skin_catalog.py`.",
        "",
        "Open `WEAPON_ICON_MODEL_REFERENCE.csv` in Excel and filter any column. The useful lookup chain is:",
        "",
        "`weapon family / skin key -> inventory icon PNG -> right-hand model + left-hand model -> glow/material -> source file`",
        "",
        "Notes:",
        "",
        "- An inventory icon represents the complete item. Dual weapons still have separate left/right unit fields.",
        "- Multiple skins may intentionally reuse one inventory icon, particularly glow variants whose appearance comes from the model/material.",
        "- `png_present = no` identifies a source reference that is not currently in the extracted `icons` folder.",
        "- `display_name_loc_key` is the game's localization key; `display_name` is the resolved English name when captured from an in-game dump.",
        "",
        f"Catalog totals: **{len(rows)} skins**, **{len(dual_axes)} Dual Axes entries**, **{len(missing)} referenced icons currently absent**.",
        "",
        "## Dual Axes quick reference",
        "",
        "| Display name | Skin key | PNG | Right model | Left model | Glow/material |",
        "|---|---|---|---|---|---|",
    ]
    for row in dual_axes:
        name = row["display_name"] or "_(unresolved)_"
        right = Path(row["right_hand_unit"]).name if row["right_hand_unit"] else "-"
        left = Path(row["left_hand_unit"]).name if row["left_hand_unit"] else "-"
        material = row["material_settings_name"] or "-"
        lines.append(
            f'| {name} | `{row["skin_key"]}` | `{row["png_filename"]}` | `{right}` | `{left}` | `{material}` |'
        )
    lines.extend([
        "",
        "## Saltzpyre hatchet-related search terms",
        "",
        "Filter the CSV for `axe_hatchet` in either hand-unit column. Important base icon names include:",
        "",
        "- `icon_wpn_axe_hatchet_t1.png` - one-handed axe/hatchet model family.",
        "- `icon_wpn_axe_hatchet_t2.png` - alternate hatchet used by Axe and Falchion.",
        "- `icon_wh_dual_wield_axe_falchion_01.png` - combined Axe and Falchion inventory icon.",
        "- `icon_axe_hatchet_t2_magic_01.png` - Weave/Shyish-style hatchet model icon.",
        "",
    ])
    ICON_REFERENCE_GUIDE_OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {ICON_REFERENCE_OUT} ({len(rows)} rows)")
    print(f"Wrote {ICON_REFERENCE_GUIDE_OUT}")


def main():
    # Gather every weapon_skins*.lua under the source tree.
    paths: list[Path] = []
    for d in SKIN_DIR_GLOBS:
        for p in d.rglob("weapon_skins*.lua"):
            paths.append(p)
    paths = sorted(set(paths))
    print(f"Parsing {len(paths)} weapon_skins files...")

    skins: list[dict] = []
    for p in paths:
        skins.extend(parse_skins(p))
    print(f"Parsed {len(skins)} skin entries")

    # Cross-reference dumps for English names. Pull from session tool results
    # AND the most recent console logs (where /dump_all_names output lands).
    sources = list(DUMP_FILES) + find_recent_logs(5)
    print(f"Scanning {len(sources)} dump sources for English names...")
    # The Markdown catalog is durable; log/tool dumps are transient. Start with
    # names from the previous catalog, then let current dumps add or update them.
    dump_names = parse_existing_catalog_names(OUT)
    current_dump_names = parse_dump_names(sources)
    for key, values in current_dump_names.items():
        dump_names.setdefault(key, {}).update(values)
    resolved = 0
    for s in skins:
        nm = dump_names.get(s["_skin_key"])
        if nm:
            if "name" in nm:
                s["_localized_name"] = nm["name"]
                resolved += 1
            if "desc" in nm:
                s["_localized_desc"] = nm["desc"]
    print(f"Resolved English names for {resolved}/{len(skins)} skins from dumps")

    # Bucket by template (or by rarity for non-Veteran).
    by_tpl: dict[str, list[dict]] = {}
    no_tpl_unique: list[dict] = []
    other_rarity: dict[str, list[dict]] = {}
    for s in skins:
        rarity = s.get("rarity", "<nil>")
        tpl = s.get("material_settings_name")
        if rarity == "unique":
            if tpl:
                by_tpl.setdefault(tpl, []).append(s)
            else:
                no_tpl_unique.append(s)
        else:
            other_rarity.setdefault(rarity, []).append(s)

    def sort_key(s):
        return (s.get("_localized_name", "~zzz_" + s["_skin_key"]).lower(), s["_skin_key"])

    for lst in by_tpl.values():
        lst.sort(key=sort_key)
    no_tpl_unique.sort(key=sort_key)
    for lst in other_rarity.values():
        lst.sort(key=sort_key)

    # Emit markdown.
    lines: list[str] = []
    w = lines.append

    w("# Veteran Weapon Skin Catalog")
    w("")
    w("Auto-generated from VT2 decompiled source + in-game `/dump_glows` and `/dump_skin_rarities` output.")
    w(f"Regenerate via `py cosmetics_tweaker\\_build_skin_catalog.py`. Last build parsed {len(paths)} files / {len(skins)} skins / resolved {resolved} English names.")
    w("")
    w("Cross-reference: `memory/reference_vt2_weapon_glow_system.md` for system architecture.")
    w("")
    w("## Glow templates (HDR RGB, vector3)")
    w("")
    w("Applied at spawn via `GearUtils.apply_material_settings` → `MaterialSettingsTemplates[material_settings_name]`. Values >1 are HDR/overbright (produce bloom).")
    w("")
    w("| Template | Variable | RGB | Skin-key suffix | UI/community label |")
    w("|---|---|---|---|---|")
    w("| `purple_glow` | `rune_emissive_color` | (3, 1, 9) | `_runed_02` | \"Weave-Forged\" (colloquial) |")
    w("| `golden_glow` | `rune_emissive_color` | (8, 5, 1.5) | `_runed_03` | Geheimnisnacht 2021 dawn |")
    w("| `deep_crimson` | `rune_emissive_color` | (7, 0, 0.1) | `_runed_04` | Skulls 2023 (Khorne) |")
    w("| `life_green` | `rune_emissive_color` | (7, 9, 0.1) | `_runed_05` | GOTWF (Sister of the Thorn) |")
    w("| `lileath` | `rune_emissive_color` | (5.8, 6.3, 9) | `_runed_06` | Morris 2025 (CW Lileath) |")
    w("| `versus` | 5-channel (see below) | varies | `_magic_02` | Versus rewards (Wind of Death) |")
    w("| `white_glow` | (NOT REGISTERED) | — | `_runed_02_white` | Abandoned feature, 1 referrer |")
    w("")
    w("`versus` channels: `color_glow_high=(2.5,2,4)`, `color_glow_low=(0.7,0.3,1)`, `color_smoke_high=(0.06,0.15,0.22)`, `color_smoke_low=(0.06,0.03,0.03)`, `color_dots=(8.35,3.5,7)`.")
    w("")
    w("## Rarity → UI label (resolved via Localize in-game)")
    w("")
    w("| Code rarity | UI label | Total skins (this catalog) |")
    w("|---|---|---|")
    counts = {}
    for s in skins:
        r = s.get("rarity", "<nil>")
        counts[r] = counts.get(r, 0) + 1
    label = {
        "plentiful": "Plentiful", "common": "Common", "rare": "Rare",
        "magic": "(unloc)", "exotic": "Exotic", "unique": "**Veteran**",
        "event": "Event", "promo": "(unloc)", "default": "(unloc)",
    }
    for r in sorted(counts):
        w(f"| `{r}` | {label.get(r, '(unknown)')} | {counts[r]} |")
    w("")
    w("---")
    w("")

    # Per-template Veteran-rarity sections.
    template_order = ["purple_glow", "golden_glow", "deep_crimson", "life_green", "lileath", "versus", "white_glow"]
    for tpl in template_order:
        items = by_tpl.get(tpl, [])
        w(f"## Veteran skins with `{tpl}` template ({len(items)} items)")
        w("")
        if not items:
            w("_(none in source)_")
            w("")
            continue
        w("| Display name | Skin key | Description loc-key | Right unit | Left unit | Source file |")
        w("|---|---|---|---|---|---|")
        for s in items:
            nm = s.get("_localized_name", "_(name unresolved — re-run /dump_glows)_")
            w("| {nm} | `{key}` | `{desc}` | `{r}` | `{l}` | `{src}` |".format(
                nm=nm,
                key=s["_skin_key"],
                desc=s.get("display_name", ""),
                r=s.get("right_hand_unit", "—"),
                l=s.get("left_hand_unit", "—"),
                src=s["_source_file"],
            ))
        w("")

    # No-template Veteran (the 160 "Stylish" colloquial group).
    w(f"## Veteran skins with NO glow template — \"Stylish\" colloquial ({len(no_tpl_unique)} items)")
    w("")
    w("These items have `rarity = \"unique\"` but no `material_settings_name`. Visual = baked unit emission only.")
    w("Each typically pairs with a `_runed_02` sibling (same unit, `purple_glow` template, different display name).")
    w("")
    w("| Display name | Skin key | Right unit | Left unit | Source file |")
    w("|---|---|---|---|---|")
    for s in no_tpl_unique:
        nm = s.get("_localized_name", "_(name unresolved)_")
        w("| {nm} | `{key}` | `{r}` | `{l}` | `{src}` |".format(
            nm=nm,
            key=s["_skin_key"],
            r=s.get("right_hand_unit", "—"),
            l=s.get("left_hand_unit", "—"),
            src=s["_source_file"],
        ))
    w("")

    # Other rarities (lower tiers).
    w("---")
    w("")
    w("## Lower-rarity skins (no glow templates ever apply)")
    w("")
    w("These rarities never have `material_settings_name` set. Listed compactly for completeness.")
    w("")
    for r in ["exotic", "rare", "magic", "common", "plentiful", "promo", "event", "default"]:
        items = other_rarity.get(r, [])
        if not items:
            continue
        w(f"### `{r}` ({len(items)} items)")
        w("")
        w("| Display name | Skin key | Right unit | Left unit | Source file |")
        w("|---|---|---|---|---|")
        for s in items:
            nm = s.get("_localized_name", "_(name unresolved — re-run /dump_skin_rarities with no sample limit)_")
            w("| {nm} | `{key}` | `{r}` | `{l}` | `{src}` |".format(
                nm=nm,
                key=s["_skin_key"],
                r=s.get("right_hand_unit", "—"),
                l=s.get("left_hand_unit", "—"),
                src=s["_source_file"],
            ))
        w("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {OUT} ({len(lines)} lines)")
    write_icon_reference(skins)


if __name__ == "__main__":
    main()
