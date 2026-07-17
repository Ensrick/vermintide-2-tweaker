# Translation readiness (#444)

Status: blocked by design until English copy and the intended 1.0 mod releases are
stable. Audit schema: **v1.0.0**.

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
ordered Lua `string.format` tokens, including escaped literal percent signs.

Baseline on 2026-07-14: 21 active localization files, 6,915 statically authored
English entries, and 48,405 missing target-language values (all seven target
slots are currently relying on English fallback). This is a planning snapshot,
not a frozen translation manifest.

`-Strict` is the future release gate. It exits 2 when any English entry lacks an
explicit target string or changes its format-token signature. Do not enable
strict mode in shipping automation until the user declares English frozen and
the relevant 1.0 release set is named.

## Translation workflow

1. Freeze an English source revision and export its key/value catalog.
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
