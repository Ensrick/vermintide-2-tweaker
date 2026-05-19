local mod = get_mod("enemy_tweaker")

local MOD_VERSION = "0.4.2-dev"
mod:info("Enemy Tweaker v%s loaded", MOD_VERSION)
mod:echo("Enemy Tweaker v" .. MOD_VERSION)

-- ============================================================
-- Helpers
-- ============================================================

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
local _breed_swap_map = {}
local _faction_swap_map = {}

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

local function _apply_size_multiplier(composition, multiplier)
    if not composition or multiplier == 1.0 then return end
    for _, variant in ipairs(composition) do
        if variant.breeds then
            for i = 1, #variant.breeds do
                local entry = variant.breeds[i]
                if type(entry) == "table" and #entry == 2 then
                    entry[1] = math.max(1, math.floor(entry[1] * multiplier + 0.5))
                    entry[2] = math.max(1, math.floor(entry[2] * multiplier + 0.5))
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

local function _apply_horde_preset()
    local preset = _get_preset()
    local multiplier = (mod:get("horde_size_multiplier") or 100) / 100

    if preset then
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
    end

    -- Size multiplier applies independently of preset selection so users
    -- can scale vanilla hordes too.
    if multiplier ~= 1.0 then
        for key, comp in pairs(HordeCompositionsPacing) do
            if type(comp) == "table" and #comp > 0 then
                _apply_size_multiplier(comp, multiplier)
            end
        end
    end
end

-- ============================================================
-- Breed substitution
-- ============================================================

local function _build_swap_map()
    _breed_swap_map = {}

    local swap_from = mod:get("breed_swap_from")
    local swap_to   = mod:get("breed_swap_to")
    if swap_from and swap_to and swap_from ~= "off" and swap_to ~= "off" and swap_from ~= swap_to then
        _breed_swap_map[swap_from] = swap_to
    end
end

local function _apply_breed_swap(result)
    if not next(_breed_swap_map) then return result end
    for i = 1, #result do
        local breed_name = result[i]
        if type(breed_name) == "string" and _breed_swap_map[breed_name] then
            local replacement = _breed_swap_map[breed_name]
            if rawget(_G, "Breeds") and Breeds[replacement] then
                result[i] = replacement
            end
        end
    end
    return result
end

-- ============================================================
-- Faction substitution (whole-faction horde slot swap)
-- ============================================================
-- VT2 picks a ConflictDirector per mission (and per-zone via
-- override_conflict_setting on the level), which sets CurrentHordeSettings.
-- Each `*_composition` field on that settings table is a string like "medium"
-- (skaven), "chaos_medium", "beastmen_medium". By rewriting those strings
-- right after ConflictDirector.refresh_conflict_director_patches runs, we
-- redirect every paced horde slot to a different faction's comp family. This
-- means Athel Yenlui (default → chaos zones) can be configured to spawn
-- Beastmen everywhere, Chaos everywhere, or the user's chosen mix.
--
-- NOTE: terror-event hordes use HordeCompositions (event_medium / chaos_raiders_*
-- / etc.) and bypass this rewrite. That patch is a separate workstream.

local FACTION_PREFIX = {
    skaven = "",
    chaos = "chaos_",
    beastmen = "beastmen_",
}

local FACTION_PREFIX_LIST = {
    { faction = "chaos", prefix = "chaos_" },
    { faction = "beastmen", prefix = "beastmen_" },
    -- skaven last because it's the empty-prefix fallback
}

local function _composition_faction(comp_str)
    for _, fp in ipairs(FACTION_PREFIX_LIST) do
        if comp_str:sub(1, #fp.prefix) == fp.prefix then
            return fp.faction
        end
    end
    return "skaven"
end

local function _strip_faction_prefix(comp_str, faction)
    local prefix = FACTION_PREFIX[faction]
    if prefix == "" then return comp_str end
    return comp_str:sub(#prefix + 1)
end

local function _build_faction_swap_map()
    _faction_swap_map = {}
    for _, faction in ipairs({"skaven", "chaos", "beastmen"}) do
        local target = mod:get("faction_swap_" .. faction)
        if target and target ~= "off" and target ~= faction and FACTION_PREFIX[target] then
            _faction_swap_map[faction] = target
        end
    end
end

local function _remap_composition(comp_str)
    if type(comp_str) ~= "string" then return comp_str end
    local from = _composition_faction(comp_str)
    local to = _faction_swap_map[from]
    if not to then return comp_str end
    local base = _strip_faction_prefix(comp_str, from)
    local new_str = FACTION_PREFIX[to] .. base
    -- Only rewrite if the target composition actually exists; otherwise the
    -- spawner will crash trying to index a nil composition.
    local HCP = rawget(_G, "HordeCompositionsPacing")
    if HCP and HCP[new_str] then
        return new_str
    end
    return comp_str
end

local COMPOSITION_FIELDS = {
    "ambush_composition", "vector_composition",
    "vector_blob_composition", "mini_patrol_composition",
}

local function _apply_faction_swap_to_current_horde_settings()
    if not next(_faction_swap_map) then return end
    local CHS = rawget(_G, "CurrentHordeSettings")
    if not CHS then return end
    for _, field in ipairs(COMPOSITION_FIELDS) do
        local v = CHS[field]
        if type(v) == "string" then
            CHS[field] = _remap_composition(v)
        elseif type(v) == "table" then
            for i, s in ipairs(v) do
                v[i] = _remap_composition(s)
            end
        end
    end
end

-- ============================================================
-- Difficulty mimic (per-system difficulty override)
-- ============================================================
-- Each Current* settings table is built by patch_settings_with_difficulty
-- against a specific difficulty key. Mimic lets the user override the
-- difficulty key used PER SYSTEM, so they can play on (e.g.) Champion stats
-- but use Cataclysm-1's horde compositions, special spawn frequency, roaming
-- density, etc. Player/enemy stats stay on the real difficulty — only the
-- spawn-side fields are re-patched.
--
-- MIMIC_SYSTEMS maps the user-facing setting → director field name → name of
-- the Current* global. After ConflictDirector.refresh_conflict_director_patches
-- runs, for each system where the user picked a difficulty override, we
-- re-patch from director.<field> with the override difficulty and overwrite
-- the Current* global. Order is important: difficulty mimic runs BEFORE
-- faction-swap, because mimic REPLACES the table and faction-swap mutates
-- in place.

local MIMIC_SYSTEMS = {
    { setting = "mimic_horde",         field = "horde",         current = "CurrentHordeSettings" },
    { setting = "mimic_specials",      field = "specials",      current = "CurrentSpecialsSettings" },
    { setting = "mimic_pacing",        field = "pacing",        current = "CurrentPacing" },
    { setting = "mimic_pack_spawning", field = "pack_spawning", current = "CurrentPackSpawningSettings" },
    { setting = "mimic_intensity",     field = "intensity",     current = "CurrentIntensitySettings" },
    { setting = "mimic_boss",          field = "boss",          current = "CurrentBossSettings" },
}

local VALID_DIFFICULTIES = {
    normal = true, hard = true, harder = true, hardest = true,
    cataclysm = true, cataclysm_2 = true, cataclysm_3 = true,
}

local function _apply_difficulty_mimic(self)
    local CDs = rawget(_G, "ConflictDirectors")
    local director = CDs and CDs[self.current_conflict_settings]
    if not director then return end
    local mgr = Managers.state and Managers.state.difficulty
    local fallback_difficulty = mgr and mgr.fallback_difficulty
    local CU = rawget(_G, "ConflictUtils")
    if not CU or not CU.patch_settings_with_difficulty then return end

    for _, m in ipairs(MIMIC_SYSTEMS) do
        local user_difficulty = mod:get(m.setting)
        if user_difficulty and user_difficulty ~= "off"
                and VALID_DIFFICULTIES[user_difficulty]
                and director[m.field] then
            local rebuilt = CU.patch_settings_with_difficulty(
                table.clone(director[m.field]), user_difficulty, fallback_difficulty)
            _G[m.current] = rebuilt
        end
    end
end

-- ============================================================
-- Hooks
-- ============================================================

mod:hook("ConflictDirector", "init", function(func, self, ...)
    local result = func(self, ...)

    _backup_compositions()
    _restore_compositions()
    _apply_horde_preset()
    _build_swap_map()
    _build_faction_swap_map()
    _apply_difficulty_mimic(self)
    _apply_faction_swap_to_current_horde_settings()

    mod:info("Enemy Tweaker: compositions applied (preset=%s, size=%d%%)",
        tostring(mod:get("horde_preset")), mod:get("horde_size_multiplier") or 100)
    return result
end)

-- refresh_conflict_director_patches runs whenever the active conflict
-- director changes (zone boundary override, mid-mission switches). It
-- rebuilds CurrentHordeSettings via table.clone(director.horde), so any
-- faction-swap rewrites from a previous CD are lost — re-apply after.
-- Order: difficulty mimic first (replaces Current* tables), then faction-swap
-- (mutates CurrentHordeSettings in place).
mod:hook("ConflictDirector", "refresh_conflict_director_patches", function(func, self, ...)
    func(self, ...)
    _apply_difficulty_mimic(self)
    _apply_faction_swap_to_current_horde_settings()
end)

-- compose_blob_horde_spawn_list returns (spawn_list, num_to_spawn) — a real list,
-- so in-place breed swap on the list works.
mod:hook("HordeSpawner", "compose_blob_horde_spawn_list", function(func, self, composition, ...)
    local spawn_list, num_to_spawn = func(self, composition, ...)
    return _apply_breed_swap(spawn_list), num_to_spawn
end)

-- compose_horde_spawn_list returns (sum, sum_a, sum_b) — three integers, NOT
-- a list. Breed names live in file-local upvalues spawn_list_a/_b inside
-- horde_spawner.lua and are popped per-spawn by spawn_unit. So the only place
-- to substitute ambush breeds reliably is at the per-unit spawn site:
-- HordeSpawner.spawn_unit(self, hidden_spawn, breed_name, goal_pos, horde).
mod:hook("HordeSpawner", "spawn_unit", function(func, self, hidden_spawn, breed_name, goal_pos, horde)
    if breed_name and _breed_swap_map[breed_name] then
        local replacement = _breed_swap_map[breed_name]
        if rawget(_G, "Breeds") and Breeds[replacement] then
            breed_name = replacement
        end
    end
    return func(self, hidden_spawn, breed_name, goal_pos, horde)
end)

-- ============================================================
-- Special spawns — per-difficulty
-- ============================================================
-- The user configures Max Specials Active, Max Same Type, per-special spawn
-- weight, and per-special disabled toggle independently for each difficulty
-- (Recruit / Veteran / Champion / Legend / Cataclysm 1/2/3). Defaults pulled
-- from VT2's SpecialDifficultyOverrides so unmodified sliders match vanilla.
--
-- Three SpecialsPacing hooks:
--   1) instance specials_by_slots — no override needed currently (cooldowns
--      not exposed in v0.3.1 UI), but the hook is in place for future use.
--   2) setup_functions.specials_by_slots — overrides CurrentSpecialsSettings
--      .max_specials and filters .breeds via per-breed disabled toggles,
--      restored after the original returns.
--   3) select_breed_functions.get_random_breed — applies weighted selection
--      and max_of_same override per the active difficulty.
--
-- Setting key convention (defined in enemy_tweaker_data.lua):
--   et_diff_<difficulty>_max_total
--   et_diff_<difficulty>_max_same
--   et_diff_<difficulty>_weight_<breed>
--   et_diff_<difficulty>_disabled_<breed>

local _setting_key = mod._setting_key or function(diff_key, suffix, breed)
    if breed then return string.format("et_diff_%s_%s_%s", diff_key, suffix, breed) end
    return string.format("et_diff_%s_%s", diff_key, suffix)
end

local function _active_difficulty()
    -- Returns the current mission difficulty key (normal/hard/.../cataclysm_3)
    -- or "normal" if the manager isn't ready (mod load before any mission).
    local m = rawget(_G, "Managers")
    if not m or not m.state or not m.state.difficulty then return "normal" end
    local diff = m.state.difficulty:get_difficulty()
    return diff or "normal"
end

local function _enabled_specials_for(diff_key, source_breeds)
    -- Filter source_breeds by per-breed disabled toggle for the given difficulty.
    -- Always returns a fresh list — never mutates source.
    local out = {}
    for i = 1, #source_breeds do
        local name = source_breeds[i]
        if not mod:get(_setting_key(diff_key, "disabled", name)) then
            out[#out + 1] = name
        end
    end
    return out
end

if rawget(_G, "SpecialsPacing") then
    -- (1) Per-update hook — reserved for future cooldown overrides; currently no-op.

    -- (2) Setup-time: max_specials override + breeds filter.
    if SpecialsPacing.setup_functions and SpecialsPacing.setup_functions.specials_by_slots then
        mod:hook(SpecialsPacing.setup_functions, "specials_by_slots", function(func, t, slots, method_data, state_data)
            local CSS = rawget(_G, "CurrentSpecialsSettings")
            if not CSS then
                return func(t, slots, method_data, state_data)
            end

            local diff_key = _active_difficulty()
            local saved_breeds = CSS.breeds
            local saved_max    = CSS.max_specials

            local user_max = mod:get(_setting_key(diff_key, "max_total"))
            if user_max then CSS.max_specials = user_max end
            CSS.breeds = _enabled_specials_for(diff_key, saved_breeds)

            local ok, err = pcall(func, t, slots, method_data, state_data)

            CSS.breeds       = saved_breeds
            CSS.max_specials = saved_max

            if not ok then error(err) end
        end)
    end

    -- (3) Per-pick: weighted selection + max_of_same override.
    if SpecialsPacing.select_breed_functions and SpecialsPacing.select_breed_functions.get_random_breed then
        mod:hook(SpecialsPacing.select_breed_functions, "get_random_breed", function(func, slots, specials_settings, method_data, state_data, ...)
            -- Preserve vanilla coordinated-attack override (set up in setup_functions
            -- when method_data.always_coordinated + same_breeds). Skipping this
            -- breaks coordinated attacks.
            if state_data and state_data.override_breed_name then
                return func(slots, specials_settings, method_data, state_data, ...)
            end

            local diff_key = _active_difficulty()
            local pool = _enabled_specials_for(diff_key, specials_settings.breeds)
            if #pool == 0 then
                return func(slots, specials_settings, method_data, state_data, ...)
            end

            -- Weighted selection. Default weight is 1 → uniform random, matching
            -- vanilla. Setting any weight to 0 effectively disables that breed (same
            -- as the disabled checkbox, just a softer route).
            local total = 0
            local weights = {}
            for i, name in ipairs(pool) do
                local w = mod:get(_setting_key(diff_key, "weight", name)) or 1
                weights[i] = w
                total = total + w
            end
            if total <= 0 then
                -- All weights zero — fall back to uniform pick from the pool.
                return pool[math.random(1, #pool)]
            end

            -- Apply max_of_same override before the weighted pick so the loop respects it.
            local user_max_same = mod:get(_setting_key(diff_key, "max_same"))
            local max_same = user_max_same or method_data.max_of_same or 1
            if #pool == 1 then
                -- Only one eligible breed: skip the max_of_same constraint or we softlock.
                local r = math.random() * total
                local acc = 0
                for i, name in ipairs(pool) do
                    acc = acc + weights[i]
                    if r <= acc then return name end
                end
                return pool[#pool]
            end

            -- Count current alive-per-breed for max_of_same enforcement.
            local count = {}
            for i = 1, #slots do
                local b = slots[i].breed
                count[b] = (count[b] or 0) + 1
            end

            local max_tries = 20
            for _ = 1, max_tries do
                local r = math.random() * total
                local acc = 0
                for i, name in ipairs(pool) do
                    acc = acc + weights[i]
                    if r <= acc then
                        if (count[name] or 0) < max_same then
                            return name
                        end
                        break
                    end
                end
            end

            -- Last resort: return first eligible (max-of-same not yet hit), else first in pool.
            for _, name in ipairs(pool) do
                if (count[name] or 0) < max_same then return name end
            end
            return pool[1]
        end)
    end
end

-- ============================================================
-- Settings change handler
-- ============================================================

local function _reapply_via_active_cd()
    -- For settings whose effect lives on the Current* tables (faction-swap,
    -- difficulty-mimic), we need an active ConflictDirector to re-patch
    -- against. If we're in the keep / no mission active, the next mission's
    -- init hook will pick up new settings automatically.
    local active = Managers.state and Managers.state.conflict
    if active then
        _apply_difficulty_mimic(active)
        _apply_faction_swap_to_current_horde_settings()
    end
end

mod.on_setting_changed = function(setting_id)
    if _original_compositions_pacing then
        _restore_compositions()
        _apply_horde_preset()
        _build_swap_map()
        _build_faction_swap_map()
        _reapply_via_active_cd()
        mod:echo("Enemy Tweaker: settings updated")
    end
end

mod.on_disabled = function()
    _restore_compositions()
    _breed_swap_map = {}
    _faction_swap_map = {}
    -- Note: we can't undo the in-place CurrentHordeSettings rewrite from here
    -- without rebuilding it from director.horde. The next refresh_conflict_director_patches
    -- (zone change, level transition) will rebuild it from scratch — and our
    -- hook will be inactive, so no swap is re-applied. Within the same active
    -- CD, the swap remains until the next refresh.
    mod:echo("Enemy Tweaker disabled — compositions restored")
end

mod.on_enabled = function()
    if _original_compositions_pacing then
        _apply_horde_preset()
        _build_swap_map()
        _build_faction_swap_map()
        _reapply_via_active_cd()
        mod:echo("Enemy Tweaker enabled")
    end
end

-- ============================================================
-- Commands
-- ============================================================

mod:command("et_dump_breeds", "List all registered breed names by faction", function()
    if not rawget(_G, "Breeds") then
        mod:echo("Breeds table not loaded yet")
        return
    end

    local factions = { skaven = {}, chaos = {}, beastmen = {}, undead = {}, other = {} }

    for name, data in pairs(Breeds) do
        if type(data) == "table" then
            local race = data.race
            if race == "skaven" then
                table.insert(factions.skaven, name)
            elseif race == "chaos" then
                table.insert(factions.chaos, name)
            elseif race == "beastmen" then
                table.insert(factions.beastmen, name)
            elseif race == "undead" then
                table.insert(factions.undead, name)
            else
                table.insert(factions.other, name)
            end
        end
    end

    for faction, breeds in pairs(factions) do
        table.sort(breeds)
        if #breeds > 0 then
            mod:echo("--- %s (%d) ---", faction, #breeds)
            for _, name in ipairs(breeds) do
                local b = Breeds[name]
                local flags = ""
                if b.special then flags = flags .. " [special]" end
                if b.boss then flags = flags .. " [boss]" end
                if b.elite then flags = flags .. " [elite]" end
                mod:echo("  %s  base_unit=%s  template=%s%s", name,
                    tostring(b.base_unit), tostring(b.unit_template), flags)
            end
        end
    end
end)

mod:command("et_dump_compositions", "List all pacing composition keys", function()
    if not rawget(_G, "HordeCompositionsPacing") then
        mod:echo("HordeCompositionsPacing not loaded")
        return
    end

    local keys = {}
    for k, _ in pairs(HordeCompositionsPacing) do
        table.insert(keys, k)
    end
    table.sort(keys)

    mod:echo("--- Pacing Compositions (%d) ---", #keys)
    for _, k in ipairs(keys) do
        local comp = HordeCompositionsPacing[k]
        local variants = 0
        if type(comp) == "table" then
            for i = 1, #comp do
                if comp[i] then variants = variants + 1 end
            end
        end
        mod:echo("  %s (%d variants)", k, variants)
    end
end)

mod:command("et_status", "Show current Enemy Tweaker state", function()
    local preset_key = mod:get("horde_preset") or "off"
    local preset = HORDE_PRESETS[preset_key]
    mod:echo("Preset: %s", preset and preset.label or "Off")
    mod:echo("Size multiplier: %d%%", mod:get("horde_size_multiplier") or 100)

    local swap_from = mod:get("breed_swap_from") or "off"
    local swap_to = mod:get("breed_swap_to") or "off"
    if swap_from ~= "off" and swap_to ~= "off" then
        mod:echo("Breed swap: %s -> %s", swap_from, swap_to)
    else
        mod:echo("Breed swap: none")
    end

    local any_faction_swap = false
    for _, faction in ipairs({"skaven", "chaos", "beastmen"}) do
        local target = mod:get("faction_swap_" .. faction) or "off"
        if target ~= "off" and target ~= faction then
            mod:echo("Faction swap: %s -> %s", faction, target)
            any_faction_swap = true
        end
    end
    if not any_faction_swap then
        mod:echo("Faction swap: none")
    end

    local any_mimic = false
    for _, m in ipairs(MIMIC_SYSTEMS) do
        local v = mod:get(m.setting) or "off"
        if v ~= "off" then
            mod:echo("Difficulty mimic: %s = %s", m.field, v)
            any_mimic = true
        end
    end
    if not any_mimic then
        mod:echo("Difficulty mimic: none")
    end

    if rawget(_G, "CurrentHordeSettings") then
        mod:echo("--- Active CurrentHordeSettings ---")
        for _, field in ipairs(COMPOSITION_FIELDS) do
            local v = CurrentHordeSettings[field]
            if type(v) == "string" then
                mod:echo("  %s = %s", field, v)
            elseif type(v) == "table" then
                mod:echo("  %s = [%s]", field, table.concat(v, ", "))
            end
        end
    end
end)
