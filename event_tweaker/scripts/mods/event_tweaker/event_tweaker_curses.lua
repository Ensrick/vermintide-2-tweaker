-- ============================================================
-- event_tweaker — shared Cursed Adventure curse catalog
-- ============================================================
-- Single source of truth for the Chaos Wastes / Be'lakor curse data, required
-- by ALL THREE mod files (event_tweaker.lua / _data.lua / _localization.lua).
--
-- WHY A SHARED MODULE (not a mod._field set in the script):
--   VMF loads a mod's files in the order localization -> data -> script (the
--   mod_script runs LAST). So anything the .lua script assigns to mod._X is
--   nil when _data.lua and _localization.lua are evaluated. A module pulled in
--   via require() is evaluated on first require (by whichever file gets there
--   first — the localization file) and cached, so all three files see the same
--   tables regardless of load order. This mirrors enemy_tweaker_breeds.lua,
--   which is require()'d from enemy_tweaker's script, data, AND localization.
--   (Burned once: v0.4.14-dev first shipped these as mod._ET_* exports in the
--   script — the entire Cursed Adventure UI group silently never built.)
--
-- The catalog itself was established by a 4-agent adversarial source audit
-- (2026-06-19); see event_tweaker/DEVELOPMENT.md "Cursed Adventure",
-- CHANGELOG 0.4.14-dev, and memory reference_vt2_mutator_packages_deus_only.

local M = {}

-- Curses that CANNOT run in adventure (hard crash) — never surfaced anywhere.
-- Load-bearing in BOTH the package filter's blind spot AND the dynamic
-- "Other Mutators" group: curse_belakors_shadows / curse_empathy are
-- PACKAGE-FREE, so the `not tmpl.packages` filter would let them through —
-- only this blacklist excludes them.
--   curse_bolt_of_change   — spawn path calls DeusMechanism-only
--                            get_deus_run_controller() (deus_mechanism.lua:523)
--                            -> nil-method crash on every bolt spawn.
--   curse_belakors_shadows — actually a WEAVE mutator; server_update does
--                            radius*radius with radius=nil outside a weave.
--   curse_empathy          — package-free, no deus deps, but a latent
--                            server-side nil-index (data.hero_side unset).
M.BROKEN_IN_ADVENTURE = {
    curse_bolt_of_change   = true,
    curse_belakors_shadows = true,
    curse_empathy          = true,
}

-- Package-bearing curses surfaced in the "Cursed Adventure" UI group. `god`
-- drives the cursed-sky tint; `dlc` is the content pack (morris = Chaos Wastes,
-- belakor = Trail of Treachery — both FREE updates, so owns_dlc() is a safe
-- no-op but kept for correctness). `experimental` = activates without crashing
-- but may be inert in adventure (no Deus economy / mission flow to pay off).
-- Order is the deterministic priority for the single-god sky tint when several
-- curses of different gods are active at once.
M.MANAGED_CURSES = {
    { id = "curse_blood_storm",          god = "khorne",   dlc = "morris"  },
    { id = "curse_skulls_of_fury",       god = "khorne",   dlc = "morris"  },
    { id = "curse_khorne_champions",     god = "khorne",   dlc = "morris"  },
    { id = "curse_corrupted_flesh",      god = "nurgle",   dlc = "morris"  },
    { id = "curse_rotten_miasma",        god = "nurgle",   dlc = "morris"  },
    { id = "curse_grey_wings",           god = "tzeentch", dlc = "belakor" },
    { id = "curse_belakor_totems",       god = "belakor",  dlc = "belakor" },
    { id = "curse_shadow_daggers",       god = "belakor",  dlc = "belakor" },
    { id = "curse_shadow_homing_skulls", god = "belakor",  dlc = "belakor" },
    { id = "curse_egg_of_tzeentch",      god = "tzeentch", dlc = "morris",  experimental = true },
    { id = "curse_greed_pinata",         god = "slaanesh", dlc = "morris",  experimental = true },
}

-- curse name -> Chaos god, for the cursed-sky tint. Covers BOTH the
-- package-bearing MANAGED_CURSES and the package-free curses that surface in
-- the host-only "Other Mutators" group, so those get themed lighting too.
M.CURSE_TO_GOD = {
    curse_blood_storm          = "khorne",   curse_blood_storm_v2       = "khorne",
    curse_skulls_of_fury       = "khorne",   curse_khorne_champions     = "khorne",
    curse_corrupted_flesh      = "nurgle",   curse_rotten_miasma        = "nurgle",
    nurgle_storm               = "nurgle",   curse_grey_wings           = "tzeentch",
    curse_egg_of_tzeentch      = "tzeentch", curse_change_of_tzeentch   = "tzeentch",
    curse_belakor_totems       = "belakor",  curse_shadow_daggers       = "belakor",
    curse_shadow_homing_skulls = "belakor",  curse_greed_pinata         = "slaanesh",
}

return M
