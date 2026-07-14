# Progressive Elite Modifiers (#323)

Status: diagnostics armed; co-op evidence required; activation disabled.

The requested curve is mission 1 = 0%, mission 2 = 5%, mission 3 = 10%,
mission 4 = 15%, and mission 5 onward = 20%. CT can derive that exactly from
`DeusRunController.get_completed_level_count()` without creating a new
difficulty tier.

## Source boundary

Ordinary `ConflictDirector` spawns receive no enhancement list. Vanilla applies
enhancements only when `optional_data.enhancements` exists
(`conflict_director.lua:2029-2042`). The grudge generator supplies a monster
`base` plus entries from the 13-member `BossGrudgeMarks` set and only bans one
specific troll/periodic-shield pair (`grudge_mark_settings.lua:108-140,191-195`).
That is not evidence that all boss buffs are safe on every elite or special.

There is one source-proven elite recipe: Geheimnisnacht's Chaos Warrior uses
`elite_base` plus either `shockwave` or `ignore_death_aura`
(`geheimnisnacht_2021_generic_terror_events.lua:9-22`). Those two form the
first safe allowlist candidate. The other 13 remain boss-only until their buff
assumptions and cleanup are audited on elite bodies.

## Armed census

`_ct_progressive_elite_audit.lua` observes the existing post-spawn boundary. It
does not alter the spawn payload or apply buffs. It counts eligible elite and
special spawns and evaluates them with a deterministic 0-99 sampler against the
requested rate. Output is capped at seven `[ct:323]` summaries per session,
enough for all five mission exits plus two `/ct_progressive_elite_audit` captures.

The census also requires all 15 enhancement templates, exactly 13 vanilla boss
marks, and exactly two source-proven elite candidates. No setting is exposed
until these counts and the observed spawn volume show that a 20% ceiling is
safe.

## Verification gate

Host and client should run one full pilgrimage, capturing `[ct:323]` at each
mission depth. Only the host's spawn census is authoritative; the client log
confirms CT/mission parity and absence of unexpected enhancement application.
Rates must be 0/5/10/15/20, `activation=disabled`, and the source catalog must
remain `catalog=15 templates=15 boss_only=13 elite_source_proven=2 missing=0`.
Run `/ct_regression_test` and require
`PASS: issue323_progressive_elite_feasibility`.
