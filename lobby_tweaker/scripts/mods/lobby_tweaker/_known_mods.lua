local mod = get_mod("lobby_tweaker")

-- ============================================================================
-- Known-mods fallback table: mod_id (string passed to new_mod) -> mode
-- ============================================================================
-- Mode glossary:
--   "R" = client_required  — joiner needs the mod or peer-visible state will
--                            diverge / crash on hash mismatch.
--   "C" = cosmetic         — joiner is fine without it; they just won't see
--                            what the host's mod renders.
--   "H" = host_only        — doesn't affect clients at all (debug / dumps).
--
-- This table is the SECOND step in mode resolution (see PHASE2_PROTOCOL.md):
--   1. Mod self-declaration via `mod._lt_mode`.
--   2. This table.
--   3. Default `R`.
--
-- The table is intentionally flat (no nesting) so that a future build step
-- could merge it with peer-tweaker known-mods tables without conflict
-- resolution. Add new entries alphabetically within each section.
--
-- WARNING: setting an unfamiliar mod to "C" is a footgun — if it touches
-- LevelSettings / NetworkLookup / breeds, mismatched peers WILL crash on
-- join. When uncertain, leave it out so the default `R` triggers and the
-- joiner is told to install it.

local KNOWN = {
    -- ----- Tweaker family (in this repo) ----------------------------------
    -- Mostly tagged R because they touch shared state (boons, weapons, careers,
    -- breeds, items) that joiners would mismatch on. The two C entries are
    -- the strictly-cosmetic/local ones.
    ["wt"]                         = "R", -- weapon_tweaker
    ["ct"]                         = "R", -- chaos_wastes_tweaker
    ["gt"]                         = "C", -- general_tweaker — 3P camera, debug dumps, mostly local QoL
    ["cosmetics_tweaker"]          = "C", -- visual-only; remote peer sees vanilla
    ["dynamic_cosmetic_portraits"] = "C", -- HUD/portrait sprites only
    ["crt"]                        = "R", -- career_tweaker — talent swaps affect networked state
    ["enemy_tweaker"]              = "R", -- spawn / breed substitution = host-broadcast
    ["character_weapon_variants"]  = "R", -- new item keys, joiner needs same ItemMasterList shape
    ["cim"]                        = "R", -- crafting_in_modded — registers craft surfaces
    ["event_tweaker"]              = "R", -- mutator / active_events injection
    ["mp"]                         = "C", -- modded_progression — local progression mirror
    ["la_prefix_patch"]            = "C", -- LA console quieter + UI toggles, no peer state
    ["lobby_tweaker"]              = "C", -- this mod itself is per-peer; not strictly required for the OTHER peer

    -- ----- Common community mods ------------------------------------------
    -- Conservative seed list — only entries whose canonical mod_id we are
    -- confident about. Default R covers anything missing here.
    ["UIImprovements"]             = "C", -- UI tweaks, local
    ["NumericUI"]                  = "C", -- HUD numeric overlays
    ["ThirdPersonEquipment"]       = "C", -- show held weapons on 3P body, visual
    ["NoFlashlight"]               = "C", -- visual
    ["ScoreboardTweaks"]           = "C", -- end-of-mission UI
    ["VisibleAmmo"]                = "C", -- HUD
    ["Crosshairs"]                 = "C", -- HUD
    ["BiggerLootDice"]             = "C", -- end-mission UI
    ["TrueSoloQoL"]                = "H", -- single-player only, host won't even matter
    ["AutoReadyUp"]                = "C", -- local UX
    ["NeuterUltVoicelines"]        = "C", -- audio
    ["BotImprovements-Combat"]     = "R", -- modifies bot AI host-side
    ["BotImprovements-Followers"]  = "R", -- modifies bot pathing host-side
    ["Loremasters-Armoury"]        = "R", -- adds custom-mesh weapons that peers need
    ["MoreItemsLibrary"]           = "R", -- IML-registered items appear in everyone's lookup
    ["WeaponsAreUseable"]          = "C", -- cosmetic equip toggle
    ["NoWobble"]                   = "C", -- camera, local
    ["host_migration"]             = "R", -- changes host transfer behaviour
    ["Penlight Lua Libraries"]     = "C", -- library; doesn't affect lobby
    ["vmf"]                        = "C", -- the framework itself; everyone has it
}

return KNOWN
