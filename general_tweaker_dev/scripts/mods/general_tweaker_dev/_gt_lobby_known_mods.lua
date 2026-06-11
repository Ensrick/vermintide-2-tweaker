local _ = get_mod("gt_dev")  -- keep for parity with sibling _gt_lobby_* files

-- ============================================================================
-- Known-mods fallback table (migrated from lobby_tweaker 2026-05-25)
-- mod_id (string passed to new_mod) -> mode
-- ============================================================================
-- Mode glossary:
--   "R" = client_required  -- joiner needs the mod or peer-visible state will
--                             diverge / crash on hash mismatch.
--   "C" = cosmetic         -- joiner is fine without it; they just won't see
--                             what the host's mod renders.
--   "H" = host_only        -- doesn't affect clients at all (debug / dumps).
--
-- This table is the SECOND step in mode resolution:
--   1. Mod self-declaration via `mod._lt_mode` (legacy field name kept for
--      back-compat with peer mods still tagging that way).
--   2. This table.
--   3. Default `R`.
--
-- The table is intentionally flat. Add new entries alphabetically within
-- each section. Setting an unfamiliar mod to "C" is a footgun -- if it
-- touches LevelSettings / NetworkLookup / breeds, mismatched peers WILL
-- crash on join. When uncertain, leave it out so the default `R` triggers.

local KNOWN = {
    -- ----- Tweaker family (in this repo) ----------------------------------
    -- Mostly tagged R because they touch shared state (boons, weapons, careers,
    -- breeds, items) that joiners would mismatch on. The C entries are the
    -- strictly-cosmetic/local ones.
    ["wt"]                         = "R", -- weapon_tweaker
    ["ct"]                         = "R", -- chaos_wastes_tweaker
    ["gt"]                         = "C", -- general_tweaker -- 3P camera, debug dumps, host-side lobby tools (this mod)
    ["cosmetics_tweaker"]          = "C", -- visual-only; remote peer sees vanilla
    ["dynamic_cosmetic_portraits"] = "C", -- HUD/portrait sprites only
    ["crt"]                        = "R", -- career_tweaker -- talent swaps affect networked state
    ["enemy_tweaker"]              = "R", -- spawn / breed substitution = host-broadcast
    ["character_weapon_variants"]  = "R", -- new item keys, joiner needs same ItemMasterList shape
    ["cim"]                        = "R", -- crafting_in_modded -- registers craft surfaces
    ["event_tweaker"]              = "R", -- mutator / active_events injection
    ["mp"]                         = "C", -- modded_progression -- local progression mirror

    -- ----- Common community mods ------------------------------------------
    -- Conservative seed list -- only entries whose canonical mod_id we are
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
