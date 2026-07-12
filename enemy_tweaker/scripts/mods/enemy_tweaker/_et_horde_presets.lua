local mod = get_mod("enemy_tweaker")

-- _et_horde_presets.lua — horde preset catalog + composition backup/apply
--
-- Owns the curated HORDE_PRESETS catalog, the HordeCompositionsPacing /
-- HordeCompositions backup+restore pair, the preset-to-pacing-keys apply, and
-- the paced-horde size scaling of the LIVE CurrentHordeSettings clone.
-- Skeleton-based presets were removed in v0.4.0-dev pending a future
-- HordeCompositions overlay — see project memory `project_enemy_tweaker.md`.
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd before _et_director_hooks,
-- which re-applies these on ConflictDirector init/refresh). Consumed via
-- mod._et exports: HORDE_PRESETS, backup_compositions, restore_compositions,
-- apply_horde_preset, apply_horde_size_to_chs, original_compositions_pacing
-- (accessor — the backup is (re)assigned lazily, so consumers must not cache
-- the table reference).

local ET = mod._et
local _safe        = ET.safe
local _dbg_alert   = ET.dbg_alert
local _spawn_dbg   = ET.spawn_dbg
local _mult        = ET.mult
local _scale_count = ET.scale_count

local function _deep_copy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = _deep_copy(v)
    end
    return copy
end

-- ============================================================
-- Horde composition presets
-- ============================================================
-- Skeleton-based presets (necro_skeletons / ghost_skeletons / skeleton_mix)
-- were prototyped in v0.2.x → v0.3.8-dev but only made it into PACED hordes;
-- the majority of adventure-mission hordes are terror-event-driven and read
-- from HordeCompositions (194 keys) which the pacing-key patch never touched.
-- Skeleton clones also required extensive vanilla-table seeding (threat_values,
-- StatisticsDefinitions, hit_zones) at boot. Removed in v0.4.0-dev pending a
-- future iteration that overlays HordeCompositions entries. See project memory
-- `project_enemy_tweaker.md` for the design notes.

local HORDE_PRESETS = {}

HORDE_PRESETS.all_elites = {
    label = "All Elites",
    compositions = {
        skaven = {
            { name = "elites", weight = 1, breeds = {
                "skaven_storm_vermin", {8, 12},
                "skaven_storm_vermin_with_shield", {4, 6},
                "skaven_plague_monk", {3, 5},
            }},
        },
        chaos = {
            { name = "elites", weight = 1, breeds = {
                "chaos_warrior", {3, 5},
                "chaos_raider", {6, 8},
                "chaos_berzerker", {4, 6},
            }},
        },
        beastmen = {
            { name = "elites", weight = 1, breeds = {
                "beastmen_bestigor", {6, 10},
                "beastmen_gor", {8, 12},
            }},
        },
    },
}

HORDE_PRESETS.beastmen_invasion = {
    label = "Beastmen Invasion",
    compositions = {
        all = {
            { name = "ungors", weight = 5, breeds = {
                "beastmen_ungor", {15, 20},
                "beastmen_gor", {8, 12},
            }},
            { name = "bestigors", weight = 3, breeds = {
                "beastmen_gor", {10, 14},
                "beastmen_bestigor", {3, 5},
            }},
            { name = "archers", weight = 2, breeds = {
                "beastmen_ungor_archer", {6, 10},
                "beastmen_gor", {10, 14},
            }},
        },
    },
}

HORDE_PRESETS.chaos_only = {
    label = "Chaos Only",
    compositions = {
        all = {
            { name = "fanatics", weight = 5, breeds = {
                "chaos_fanatic", {20, 30},
                "chaos_marauder", {5, 8},
            }},
            { name = "marauders", weight = 3, breeds = {
                "chaos_marauder", {12, 16},
                "chaos_marauder_with_shield", {4, 6},
            }},
            { name = "raiders", weight = 2, breeds = {
                "chaos_fanatic", {15, 20},
                "chaos_raider", {4, 6},
                "chaos_berzerker", {3, 4},
            }},
        },
    },
}

HORDE_PRESETS.skaven_only = {
    label = "Skaven Only",
    compositions = {
        all = {
            { name = "slaves", weight = 5, breeds = {
                "skaven_slave", {30, 40},
                "skaven_clan_rat", {6, 10},
            }},
            { name = "clan_rats", weight = 3, breeds = {
                "skaven_clan_rat", {15, 20},
                "skaven_clan_rat_with_shield", {4, 6},
            }},
            { name = "stormvermin", weight = 2, breeds = {
                "skaven_slave", {20, 25},
                "skaven_storm_vermin", {4, 6},
                "skaven_plague_monk", {2, 3},
            }},
        },
    },
}

HORDE_PRESETS.mixed_factions = {
    label = "Mixed Factions",
    compositions = {
        all = {
            { name = "skaven_chaos", weight = 4, breeds = {
                "skaven_slave", {12, 16},
                "skaven_clan_rat", {4, 6},
                "chaos_fanatic", {10, 14},
                "chaos_marauder", {3, 5},
            }},
            { name = "all_three", weight = 3, breeds = {
                "skaven_clan_rat", {6, 8},
                "chaos_marauder", {4, 6},
                "beastmen_gor", {4, 6},
                "beastmen_ungor", {6, 8},
            }},
            { name = "elite_mix", weight = 2, breeds = {
                "skaven_storm_vermin", {3, 4},
                "chaos_raider", {3, 4},
                "beastmen_bestigor", {3, 4},
                "skaven_plague_monk", {2, 3},
            }},
        },
    },
}

-- ============================================================
-- State
-- ============================================================

local _original_compositions_pacing = nil
local _original_compositions = nil

-- ============================================================
-- Composition patching
-- ============================================================

local PACING_KEYS_SKAVEN = {
    "small", "medium", "large", "huge",
    "huge_shields", "huge_armor", "huge_berzerker",
    "mini_patrol",
}

local PACING_KEYS_CHAOS = {
    "chaos_medium", "chaos_large", "chaos_huge",
    "chaos_huge_shields", "chaos_huge_armor", "chaos_huge_berzerker",
    "chaos_mini_patrol",
}

local PACING_KEYS_BEASTMEN = {
    "beastmen_medium", "beastmen_large", "beastmen_huge",
    "beastmen_huge_armor", "beastmen_mini_patrol",
}

local function _get_preset()
    local preset_key = mod:get("horde_preset")
    if preset_key and preset_key ~= "off" and HORDE_PRESETS[preset_key] then
        return HORDE_PRESETS[preset_key]
    end
    return nil
end

local function _backup_compositions()
    if not _original_compositions_pacing and rawget(_G, "HordeCompositionsPacing") then
        _original_compositions_pacing = _deep_copy(HordeCompositionsPacing)
    end
    if not _original_compositions and rawget(_G, "HordeCompositions") then
        _original_compositions = _deep_copy(HordeCompositions)
    end
end

local function _restore_compositions()
    if _original_compositions_pacing then
        for k, v in pairs(_original_compositions_pacing) do
            HordeCompositionsPacing[k] = _deep_copy(v)
        end
    end
    if _original_compositions then
        for k, v in pairs(_original_compositions) do
            HordeCompositions[k] = _deep_copy(v)
        end
    end
end

-- v0.6.0-dev: rewritten for 0-15x multiplier semantics. At multiplier == 0
-- the breeds drop to 0 (hard suppress); at 1.0 the composition is unchanged;
-- otherwise round-to-nearest. Each breed entry's {min, max} amount tuple is
-- scaled separately. Wrapped in pcall so a malformed composition entry (e.g.
-- a non-{min,max} table from a future engine patch) logs a warning and
-- skips that entry rather than crashing the whole apply pass.
local function _apply_size_multiplier(composition, multiplier)
    if not composition or multiplier == 1 then return end
    for vi, variant in ipairs(composition) do
        if variant.breeds then
            for i = 1, #variant.breeds do
                local entry = variant.breeds[i]
                if type(entry) == "table" and #entry == 2 then
                    local ok, err = pcall(function()
                        entry[1] = _scale_count(entry[1], multiplier)
                        entry[2] = _scale_count(entry[2], multiplier)
                    end)
                    if not ok then
                        mod:warning("[et:paced] _apply_size_multiplier entry skip (variant=%d, breed_idx=%d): %s",
                            vi, i, tostring(err))
                        _dbg_alert("paced multiplier entry skip (variant=%d, breed_idx=%d): %s",
                            vi, i, tostring(err))
                    end
                end
            end
        end
    end
end

-- HordeCompositionsPacing entries each carry a `loaded_probs` field built from
-- variant weights via LoadedDice.create at conflict_settings file-load time
-- (see scripts/settings/conflict_settings.lua:636). horde_spawner.lua reads
-- composition.loaded_probs at lines 139/243/349/743 — losing it crashes
-- LoadedDice.roll_easy on the next horde. We rebuild it here so replacement
-- compositions remain spawnable.
local function _build_loaded_probs(variants)
    local LD = rawget(_G, "LoadedDice")
    if not LD or not LD.create then return nil end
    local weights = {}
    for i, v in ipairs(variants) do
        weights[i] = (v and v.weight) or 1
    end
    return { LD.create(weights) }
end

local function _apply_preset_to_pacing_keys(keys, preset_variants)
    for _, key in ipairs(keys) do
        if HordeCompositionsPacing[key] then
            local sound = HordeCompositionsPacing[key].sound_settings
            local new_variants = _deep_copy(preset_variants)
            new_variants.sound_settings = sound
            new_variants.loaded_probs = _build_loaded_probs(new_variants)
            HordeCompositionsPacing[key] = new_variants
        end
    end
end

-- v0.6.0-dev: horde_size_multiplier semantics changed from int percent
-- (25-300, default 100) to decimal multiplier (0-15, default 1). Users with
-- saved values from v0.5.x will see a slider value of 100 → effectively
-- max-clamped to 15x on first load; CHANGELOG flags re-setting after upgrade.
-- The whole apply pass is _safe-wrapped so a single bad composition entry
-- can't break the preset rotation.
local function _apply_horde_preset()
    local preset = _get_preset()
    local multiplier = math.min(_mult("horde_size_multiplier"), 5)  -- v0.7.11-dev: cap 5x (log parity with the apply)
    local mutated_keys = 0

    _safe("apply_horde_preset_swap", function()
        if not preset then return end
        local comps = preset.compositions
        if comps.all then
            _apply_preset_to_pacing_keys(PACING_KEYS_SKAVEN, comps.all)
            _apply_preset_to_pacing_keys(PACING_KEYS_CHAOS, comps.all)
            _apply_preset_to_pacing_keys(PACING_KEYS_BEASTMEN, comps.all)
        else
            if comps.skaven then
                _apply_preset_to_pacing_keys(PACING_KEYS_SKAVEN, comps.skaven)
            end
            if comps.chaos then
                _apply_preset_to_pacing_keys(PACING_KEYS_CHAOS, comps.chaos)
            end
            if comps.beastmen then
                _apply_preset_to_pacing_keys(PACING_KEYS_BEASTMEN, comps.beastmen)
            end
        end
    end)

    -- v0.7.9-dev: paced-horde SIZE scaling moved off this global. The engine
    -- sizes paced hordes from CurrentHordeSettings.compositions_pacing
    -- (horde_spawner.lua:136/348/742), which is a DEEP clone of the global taken
    -- at conflict_director.lua:881 (table.clone recurses — table.lua:40-45), so a
    -- global-side mutation never reaches the spawner (and scaling the global here
    -- would ALSO double-apply once the clone is made from it, then scaled again).
    -- Size is now applied to the live clone in
    -- _apply_horde_size_to_current_horde_settings(), called from the init +
    -- refresh hooks (mirrors faction-swap / roaming). The preset SWAP above still
    -- mutates the global; the fresh clone inherits it.

    mod:info("[et:paced] applied: preset=%s multiplier=%.1f keys_mutated=%d",
        tostring(mod:get("horde_preset") or "off"), multiplier, mutated_keys)
end

-- v0.7.9-dev: scale paced hordes by applying horde_size_multiplier to the LIVE
-- post-clone CurrentHordeSettings.compositions_pacing — the table the engine
-- actually reads to size a paced horde (horde_spawner.lua:136/348/742). That
-- table is a fresh DEEP clone of the global HordeCompositionsPacing taken at each
-- refresh (conflict_director.lua:881; table.clone recurses — table.lua:40-45), so
-- mutating the global never reaches the spawner. Mirror faction-swap/roaming:
-- re-apply in the init AND refresh hooks. Idempotent-by-fresh-clone — each
-- refresh re-clones the UNMUTATED global (et restores it before this runs), so
-- each clone is scaled exactly once (no multiplier^2 compounding).
local function _apply_horde_size_to_current_horde_settings()
    local multiplier = math.min(_mult("horde_size_multiplier"), 5)  -- v0.7.11-dev: hard-cap 5x (also clamps a stale saved >5)
    if multiplier == 1 then return end
    local CHS = rawget(_G, "CurrentHordeSettings")
    if not CHS or type(CHS.compositions_pacing) ~= "table" then return end
    _safe("apply_horde_size_to_CHS", function()
        local n = 0
        for _, comp in pairs(CHS.compositions_pacing) do
            -- Only array-shaped composition entries have #comp > 0; this skips the
            -- sound_settings / loaded_probs non-array fields. _apply_size_multiplier
            -- scales only the {min,max} tuples, never loaded_probs, so the
            -- LoadedDice / pickup-sampler invariant is untouched.
            if type(comp) == "table" and #comp > 0 then
                _apply_size_multiplier(comp, multiplier)
                n = n + 1
            end
        end
        _spawn_dbg("paced", "horde size -> CurrentHordeSettings.compositions_pacing: mult=%.1f keys=%d", multiplier, n)
    end)
end

-- v0.7.10-dev: the beastman planted-banner force-load (v0.7.9) is REVERTED — it
-- crashed. `Managers.package:load` was called on the raw UNIT PATH
-- (units/weapons/enemy/wpn_bm_standard_01/wpn_bm_standard_01_placed), which is
-- NOT a loadable .package; the engine threw "Resource '#ID[...]' not found"
-- ASYNCHRONOUSLY (so the surrounding pcall never caught it) and hard-crashed the
-- game (GUID ea9eaebb-fa1c-45a8-a5c4-405d791ab71f) on the first CD init/refresh
-- with beastmen swapped in. Removed entirely until the correct PACKAGE that
-- carries that unit is identified (TODO). Consequence: the planted beastman
-- banner does not render on a cross-faction swap — same as <=v0.7.8 — but no
-- crash. The v0.7.9 horde-size fix is independent and stays.

ET.HORDE_PRESETS = HORDE_PRESETS
ET.backup_compositions = _backup_compositions
ET.restore_compositions = _restore_compositions
ET.apply_horde_preset = _apply_horde_preset
ET.apply_horde_size_to_chs = _apply_horde_size_to_current_horde_settings
-- Accessor, not a table export: the backup is assigned lazily on the first
-- ConflictDirector.init, so consumers (lifecycle guard, /verify_horde_size)
-- must read it at call time.
ET.original_compositions_pacing = function() return _original_compositions_pacing end
