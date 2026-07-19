# Translation readiness (#444)

Status: blocked by design until English copy and the intended 1.0 mod releases are
stable. Audit schema: **v1.2.0**.

## Supported language contract

Vermintide 2's current PC language selector exposes eight language IDs:
`en`, `fr`, `pl`, `es`, `tr`, `de`, `br-pt`, and `ru`
(`scripts/ui/views/options_view.lua:6855-6887`, 2026-07-12 source snapshot).
Xbox locale normalization recognizes additional platform locales, but those are
not selectable PC localization bundles and are not #444's first release target
(`scripts/boot.lua:178-229`). Re-audit this list after a game update.

## Automated census

Run:

```powershell
pwsh -NoProfile -File qa/check_translation_readiness.ps1
pwsh -NoProfile -File qa/check_translation_readiness.ps1 -SelfTest
```

Default mode is observation-only while the issue is blocked. It inventories each
active `*_localization.lua`, counts statically authored English entries, and
reports explicit coverage for all seven target translations. It also compares
ordered Lua `string.format` tokens, including escaped literal percent signs,
rejects mistyped/unsupported language IDs, and inventories computed localization
generators which cannot be represented in a static translation catalog. It also
detects duplicate static keys before parser hashtable collapse can hide which
English row the Lua runtime ultimately retains.

Baseline on 2026-07-19: 21 active localization files, 6,765 statically authored
English entries, 47,355 missing target-language values, zero unknown language
IDs, 31 computed-generator statements across eight active localization files,
and zero duplicate static English identities across the active catalog.
Generator counts are migration blockers rather than translation coverage.
All seven target slots are currently relying on English fallback. This is a
planning snapshot, not a frozen translation manifest.

`-Strict` is the future release gate. It exits 2 when any English entry lacks an
explicit target string, changes its format-token signature, uses an unknown
locale code, remains behind a computed key outside the static catalog, or defines
one static localization identity more than once. Do not enable strict mode in
shipping automation until the user declares English frozen and the relevant 1.0
release set is named.

## Translation workflow

1. Freeze an English source revision and export its key/value catalog.
   Refactor every reported computed-key generator into an explicit exportable
   catalog first; a static translation cannot safely target an identity which is
   invented only while the localization file executes.
   Resolve every duplicate static identity first; translation catalogs must map
   one key to one unambiguous English source row.
2. Translate by key, preserving functional qualifiers, product names, keybind
   notation, and every format token exactly. Never introduce issue or
   development-lifecycle status into player-facing text.
3. Use Fatshark's language IDs verbatim; Brazilian Portuguese must use the quoted
   Lua key `["br-pt"]` because a hyphen is not valid in a bare identifier.
4. Review terminology per mod and in context. Machine output is a draft, not a
   release artifact.
5. Run the existing localization integrity checker, the translation census, its
   self-test, and each affected mod's runtime localization regression.
6. Test menus at narrow resolutions for expansion and truncation, plus language
   switching/reload behavior.

The census intentionally does not auto-edit localization files, infer translations,
or treat VMF's English fallback as completed language support.
