# Portable Old Musket QA inputs

`cwv_old_musket_native_6_13.lua` is generated pure fixture data, not production
logic. It contains the complete native Handgun and Tuskgor source, the exact
native Handgun post-update callback, and four resolved native donor tables.
Native commit: `93dea911a4cc464a0eb51cfdc3a443297bfc4550` (game6.13).

The adjacent provenance JSON records exact source Git blobs/SHA256, normalized
source-string hashes, captured donor-data hash and complete fixture hash. Raw
native UTF-8 BOM/CRLF bytes are preserved in source hashes; executable source
strings use the existing test reader's BOM removal and LF normalization.
Resolved data came from executing the actual raw damage-profile definitions
and native PowerLevel resolution, not hand-transcribed equations or values.
The frozen capture recipe lives in the reviewed issue428 portability evidence;
its native adapter explicitly uses `load_external`, not the portable snapshot,
when regenerating. Updating any fixture is a source-review operation, never an
automatic test repair. The pure-data banner uses the existing file-size
classification contract; no ratchet or checker policy was changed.

`cwv_old_musket_ranged_prior_runtime.lua` is the complete exact pre-bayonet
installer from approved ranged revision2, SHA256
`b37c6f2ffa54aa9814fd1036d2fbe51363319b830b1964f97f7afe297cb5cec0`.
Its actual publication/constructor body is the healthy old/new oracle, not a
recreated expected descriptor. The provenance JSON binds this source and its
approved supplemental binding. Do not replace it with current production code.

Required portable inputs fail when missing or malformed. Core construction,
rollback, admission, latched native callback, stance and healthy equivalence
tests do not need `VT2_SOURCE_ROOT`, an external game checkout or an ignored
review directory. The existing native adapter retains `load_external` for one
optional additional comparison against a real source checkout. An absent
external checkout skips only that provenance comparison, never the core tests.

These are engine-free Lua ledger proofs. They do not prove Stingray ABI,
native animation/playback, sound worlds, live action cleanup or co-op behavior.
