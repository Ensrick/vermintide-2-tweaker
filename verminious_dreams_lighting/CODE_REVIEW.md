# Code Review: verminious_dreams_lighting

**Version reviewed:** `1.0.6` (per `MOD_VERSION` in `scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting.lua`)
**Date:** 2026-05-29
**Audit verdict:** initial scaffold — not yet a full review

> This file is a **scaffold** created to satisfy the PROJECT_STANDARDS §7.1
> requirement that public-Workshop mods carry a `CODE_REVIEW.md`. The section
> bodies below are stubs — no findings have been recorded yet. A full review
> pass should fill these in against the running VT2 source and the mod's
> current code. Do not treat the absence of findings here as a clean bill of
> health; it just means the review hasn't been done.
>
> In-flight work for this mod happens in `verminious_dreams_lighting_dev/`
> (friends-only stream) per CLAUDE.md § "Dev/stable split workflow"; only
> merged-down releases land in this stable directory.

---

## 1. Mod purpose

_Stub — to be filled during the first full review pass._

Per CLAUDE.md mod directory: per-mission lighting overhaul for the three
Verminious Dreams DLC missions (The Forsaken Temple / Devious Delvings / The
Well of Dreams). Ships per-mission ShadingEnvironment + Light component
overrides; live tuning via `/vdl_*` chat commands. Client-side only — no host
requirement, no version-sync risk.

## 2. Architecture overview

_Stub — to be filled during the first full review pass._

See `verminious_dreams_lighting/DEVELOPMENT.md` for the per-mission lighting
tuning architecture (ShadingEnvironment + Light overrides for
dlc_termite_1/2/3).

## 3. Risk hotspots

_Stub — to be filled during the first full review pass._

## 4. QA status

_Stub — to be filled during the first full review pass._

See `verminious_dreams_lighting/REGRESSION_CHECKLIST.md` for the per-mod
regression gates.

## 5. Open follow-ups

_Stub — to be filled during the first full review pass. File actionable items
as GitHub Issues per PROJECT_STANDARDS §11 rather than listing them only here._

## 6. Notes for future agents

_Stub — to be filled during the first full review pass._
