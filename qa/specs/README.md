# Verification specs

One JSON file per issue, `qa/specs/issue_<issue>.json`: how that issue is decided.
`qa/check_verify_specs.ps1` (run by `qa/run_all.ps1`) validates every `*.json` here
except `spec.schema.json`. `spec.schema.json` (JSON Schema draft-07) is for editors.

| Field | Type and rule | VP field |
|---|---|---|
| `schema` | integer `1` | |
| `issue` | integer; the file is `qa/specs/issue_<issue>.json` | Issues |
| `class` | one of `U` `S` `R` `V` `C` `X` | the letter after the issue number |
| `status` | `draft` (converted, not runnable) or `ready` | |
| `vp` | string `VP-<BUCKET>-<NN>` or null | VP id |
| `arena` | `none`, `boot`, `keep`, `deus`, `coop`, `mission:<level_key>`; `unknown` only while `draft`; `none` only for class U, S, X | Arena |
| `mods` | array of `{ "dir", "min_version", "settings" }`; `dir` is a `Dir` of `tools/mod-inventory.psd1` (the folder names the stream); required for R, V, C | Mods and stream |
| `boots` | integer, 0 or more | Boots |
| `depends_on` | array of WP ids | Depends on |
| `setup` | string | Setup |
| `cases` | array of `{ "script", "steps": [], "assertions": [], "pass_closes": bool }`; required for R and C | Cases |
| `offline` | array of `{ "class": "U" or "S", "command", "expect" }`; required for U and S | table "issues that need NO rig" |
| `rt_checks` | array of `{ "mod", "check", "behavioural": bool }` | Reused in-mod checks |
| `left_for_humans` | array of strings; required for V and C | Left for humans |
| `on_fail` | string | If it FAILS |
| `source` | `{ "card_comment_id", "card_date", "ledger" }` | provenance of a converted card |

Checker rules:

- R1: the file name matches `issue`.
- R2: `schema`, `issue`, `class`, `status`, `vp` and `arena` are always present; every other field is optional unless R3 requires it; enum values and types are valid; no unknown top-level key.
- R3: the class-conditional requirements in the table (a required array must be non-empty).
- R4: every `mods[].dir` is a `Dir` in the inventory.
- R5: when `status` is `ready`, every `cases[].script` is a file under `qa/runtime/`; every `offline[].command` is non-empty, and its first token that ends in `.ps1` or `.lua` exists; `arena` is not `unknown`.
- R6: when `status` is `draft`, empty `script` and `command` strings are allowed.

Paths (`cases[].script`, files named in `offline[].command`) are repo-relative with `/`.
No spec file goes under a mod folder. The checker never calls GitHub.
