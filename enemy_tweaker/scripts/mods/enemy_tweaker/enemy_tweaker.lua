local mod = get_mod("enemy_tweaker")

local MOD_VERSION = "0.2.2-dev"
mod:info("Enemy Tweaker v%s loaded", MOD_VERSION)
mod:echo("Enemy Tweaker v" .. MOD_VERSION)

-- ============================================================
-- Breed catalog
-- ============================================================

local FACTION_SKAVEN = {
    "skaven_slave",
    "skaven_clan_rat",
    "skaven_clan_rat_with_shield",
    "skaven_storm_vermin",
    "skaven_storm_vermin_with_shield",
    "skaven_storm_vermin_commander",
    "skaven_plague_monk",
    "skaven_gutter_runner",
    "skaven_pack_master",
    "skaven_poison_wind_globadier",
    "skaven_ratling_gunner",
    "skaven_warpfire_thrower",
    "skaven_rat_ogre",
    "skaven_stormfiend",
}

local FACTION_CHAOS = {
    "chaos_fanatic",
    "chaos_marauder",
    "chaos_marauder_with_shield",
    "chaos_berzerker",
    "chaos_raider",
    "chaos_warrior",
    "chaos_bulwark",
    "chaos_spawn",
    "chaos_troll",
    "chaos_vortex_sorcerer",
    "chaos_corruptor_sorcerer",
}

local FACTION_BEASTMEN = {
    "beastmen_ungor",
    "beastmen_ungor_archer",
    "beastmen_gor",
    "beastmen_bestigor",
    "beastmen_minotaur",
    "beastmen_standard_bearer",
}

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
-- Skeleton breed cloning
-- ============================================================
-- Clone chaos_skeleton (proven horde enemy) with different models
-- and inventory templates from pet/ethereal skeletons.

local SKELETON_BREEDS = {
    {
        name              = "et_necro_skeleton",
        source_model      = "pet_skeleton",
        inventory         = "undead_npc_skeleton",
        unit_template     = "ai_unit_skeleton",
    },
    {
        name              = "et_necro_skeleton_armored",
        source_model      = "pet_skeleton_armored",
        inventory         = "undead_npc_skeleton_armored",
        unit_template     = "ai_unit_skeleton",
    },
    {
        name              = "et_necro_skeleton_dual_wield",
        source_model      = "pet_skeleton_dual_wield",
        inventory         = "undead_npc_skeleton_dual_wield",
        unit_template     = "ai_unit_skeleton",
    },
    {
        name              = "et_necro_skeleton_shield",
        source_model      = "pet_skeleton_with_shield",
        inventory         = "undead_npc_skeleton_with_shield",
        unit_template     = "ai_unit_skeleton_with_shield",
    },
    {
        name              = "et_ghost_skeleton_hammer",
        source_model      = "ethereal_skeleton_with_hammer",
        inventory         = "undead_ethereal_skeleton_2h",
        unit_template     = "ai_unit_skeleton",
    },
    {
        name              = "et_ghost_skeleton_shield",
        source_model      = "ethereal_skeleton_with_shield",
        inventory         = "undead_ethereal_skeleton_with_shield",
        unit_template     = "ai_unit_skeleton_with_shield",
    },
}

-- Maps cloned breed name → source breed name whose package has the model
local PACKAGE_REDIRECT = {}

local _skeleton_breeds_registered = false

local function _register_skeleton_breeds()
    if _skeleton_breeds_registered then return end
    if not rawget(_G, "Breeds") or not Breeds.chaos_skeleton then return end

    local base = Breeds.chaos_skeleton
    local base_actions = rawget(_G, "BreedActions") and BreedActions.chaos_skeleton

    for _, def in ipairs(SKELETON_BREEDS) do
        local source = Breeds[def.source_model]
        if not source then
            mod:info("Skipping %s — source breed %s not loaded", def.name, def.source_model)
            goto continue
        end

        local breed = _deep_copy(base)
        breed.name = def.name
        breed.base_unit = source.base_unit
        breed.default_inventory_template = def.inventory
        breed.unit_template = def.unit_template
        breed.is_always_spawnable = true
        breed.race = "undead"

        Breeds[def.name] = breed

        if base_actions then
            BreedActions[def.name] = _deep_copy(base_actions)
        end

        PACKAGE_REDIRECT[def.name] = def.source_model

        mod:info("Registered skeleton breed: %s (model from %s)", def.name, def.source_model)

        ::continue::
    end

    _skeleton_breeds_registered = true
end

-- Register breeds immediately at mod load so the ConflictDirector
-- threat_values table (built at file-load time by iterating Breeds)
-- includes our custom breeds. Registering during ConflictDirector.init
-- is too late — threat_values is already frozen.
_register_skeleton_breeds()

-- ============================================================
-- Package loading hook
-- ============================================================
-- EnemyPackageLoader resolves breed name → package path via
-- _breed_package_name. Our cloned breeds have no package of their
-- own — redirect to the source breed's package.

mod:hook("EnemyPackageLoader", "_breed_package_name", function(func, self, breed_name)
    local redirect = PACKAGE_REDIRECT[breed_name]
    if redirect then
        return func(self, redirect)
    end
    return func(self, breed_name)
end)

-- ============================================================
-- Horde composition presets
-- ============================================================

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

HORDE_PRESETS.necro_skeletons = {
    label = "Necromancer Skeletons",
    compositions = {
        all = {
            { name = "swords", weight = 5, breeds = {
                "et_necro_skeleton", {15, 22},
                "et_necro_skeleton_armored", {3, 5},
            }},
            { name = "mixed", weight = 3, breeds = {
                "et_necro_skeleton", {10, 14},
                "et_necro_skeleton_dual_wield", {4, 6},
                "et_necro_skeleton_shield", {2, 4},
            }},
            { name = "armored", weight = 2, breeds = {
                "et_necro_skeleton_armored", {6, 8},
                "et_necro_skeleton_shield", {4, 6},
            }},
        },
    },
}

HORDE_PRESETS.ghost_skeletons = {
    label = "Ghost Skeletons",
    compositions = {
        all = {
            { name = "hammers", weight = 5, breeds = {
                "et_ghost_skeleton_hammer", {12, 18},
                "et_ghost_skeleton_shield", {3, 5},
            }},
            { name = "shields", weight = 3, breeds = {
                "et_ghost_skeleton_shield", {6, 10},
                "et_ghost_skeleton_hammer", {8, 12},
            }},
            { name = "swarm", weight = 2, breeds = {
                "et_ghost_skeleton_hammer", {20, 28},
            }},
        },
    },
}

HORDE_PRESETS.skeleton_mix = {
    label = "All Skeletons Mixed",
    compositions = {
        all = {
            { name = "necro_heavy", weight = 4, breeds = {
                "et_necro_skeleton", {10, 14},
                "et_necro_skeleton_armored", {2, 3},
                "et_ghost_skeleton_hammer", {4, 6},
            }},
            { name = "ghost_heavy", weight = 3, breeds = {
                "et_ghost_skeleton_hammer", {8, 12},
                "et_ghost_skeleton_shield", {3, 5},
                "et_necro_skeleton_dual_wield", {3, 5},
            }},
            { name = "elite_skeletons", weight = 2, breeds = {
                "et_necro_skeleton_shield", {4, 6},
                "et_necro_skeleton_armored", {4, 6},
                "et_ghost_skeleton_shield", {4, 6},
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

local function _apply_preset_to_pacing_keys(keys, preset_variants)
    for _, key in ipairs(keys) do
        if HordeCompositionsPacing[key] then
            local sound = HordeCompositionsPacing[key].sound_settings
            local new_variants = _deep_copy(preset_variants)
            HordeCompositionsPacing[key] = new_variants
            HordeCompositionsPacing[key].sound_settings = sound
        end
    end
end

local function _apply_horde_preset()
    local preset = _get_preset()
    if not preset then return end

    local comps = preset.compositions
    local multiplier = (mod:get("horde_size_multiplier") or 100) / 100

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
-- Hooks
-- ============================================================

-- The threat_values upvalue in conflict_director.lua is built at file-load
-- time by iterating Breeds. Our custom breeds may not exist yet, so
-- register them into the threat system via set_threat_value after init.
mod:hook("ConflictDirector", "init", function(func, self, ...)
    _register_skeleton_breeds()
    local result = func(self, ...)

    for _, def in ipairs(SKELETON_BREEDS) do
        if Breeds[def.name] then
            self:set_threat_value(def.name, Breeds[def.name].threat_value or 0)
        end
    end

    _backup_compositions()
    _restore_compositions()
    _apply_horde_preset()
    _build_swap_map()
    mod:info("Enemy Tweaker: compositions applied (preset=%s, size=%d%%)",
        tostring(mod:get("horde_preset")), mod:get("horde_size_multiplier") or 100)
    return result
end)

mod:hook("HordeSpawner", "compose_horde_spawn_list", function(func, self, composition, ...)
    return _apply_breed_swap(func(self, composition, ...))
end)

mod:hook("HordeSpawner", "compose_blob_horde_spawn_list", function(func, self, composition, ...)
    return _apply_breed_swap(func(self, composition, ...))
end)

-- ============================================================
-- Settings change handler
-- ============================================================

mod.on_setting_changed = function(setting_id)
    if _original_compositions_pacing then
        _restore_compositions()
        _apply_horde_preset()
        _build_swap_map()
        mod:echo("Enemy Tweaker: settings updated")
    end
end

mod.on_disabled = function()
    _restore_compositions()
    _breed_swap_map = {}
    mod:echo("Enemy Tweaker disabled — compositions restored")
end

mod.on_enabled = function()
    _register_skeleton_breeds()
    if _original_compositions_pacing then
        _apply_horde_preset()
        _build_swap_map()
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

    mod:echo("Skeleton breeds registered: %s", tostring(_skeleton_breeds_registered))
    mod:echo("Package redirects: %d", next(PACKAGE_REDIRECT) and #SKELETON_BREEDS or 0)
end)

mod:command("et_check_skeletons", "Verify skeleton breed registration", function()
    for _, def in ipairs(SKELETON_BREEDS) do
        local b = rawget(_G, "Breeds") and Breeds[def.name]
        if b then
            mod:echo("  OK: %s -> base_unit=%s, inv=%s, template=%s",
                def.name, tostring(b.base_unit), tostring(b.default_inventory_template), tostring(b.unit_template))
        else
            local source = rawget(_G, "Breeds") and Breeds[def.source_model]
            mod:echo("  MISSING: %s (source %s %s)", def.name, def.source_model,
                source and "exists" or "also missing")
        end
    end
end)
