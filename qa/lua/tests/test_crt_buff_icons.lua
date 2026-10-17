-- #1686: every icon crt hands to the vanilla HUD must exist in the live UI
-- atlas. Game Version 6.13.0 removed two 6.12.1 atlas keys crt used; BuffUI
-- passes the raw name on (buff_ui.lua:128/135) and an atlas miss reaches
-- Gui_bitmap (ui_renderer.lua:74/117), the "Material 'X' not found in Gui"
-- fatal (docs/BUG_CLASSES.md section 23).

return function(H, repo_root)
    local root = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"

    local REMOVED_6130 = {
        kerillian_maidenguard_cooldown_on_nearby_allies = true,        -- 6.12.1 gui_icons_atlas.lua:14508
        sienna_unchained_activated_ability_power_on_enemies_hit = true, -- 6.12.1 gui_icons_atlas.lua:7830
    }
    -- Test-local seam for UIAtlasHelper.has_atlas_settings_by_texture_name
    -- (ui_atlas_helper.lua:605): the names crt uses that exist at Game Version
    -- 6.13.0 (93dea911), gui_icons_atlas.lua line cited.
    local ATLAS_6130 = {
        maidenguard_4_2 = true,                                       -- :9454
        unchained_6_1 = true,                                         -- :7746
        bardin_engineer_ranged_crit_count = true,                     -- :15138
        markus_knight_passive_block_cost_aura = true,                 -- :14298
        markus_knight_damage_taken_ally_proximity = true,             -- :14522
        markus_knight_movement_speed_on_incapacitated_allies = true,  -- :14340
        sienna_unchained_reduced_damage_taken_after_venting = true,   -- :8950
        icons_placeholder = true,                                     -- :5674
    }

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local value = file:read("*a")
        file:close()
        return value
    end

    local function atlas(names)
        return {
            has_atlas_settings_by_texture_name = function(name)
                return names[name] == true
            end,
        }
    end

    local function without(names, removed)
        local copy = {}
        for key, value in pairs(names) do
            if key ~= removed then copy[key] = value end
        end
        return copy
    end

    local function load_icons()
        return assert(loadfile(root .. "_crt_buff_icons.lua"), "_crt_buff_icons.lua missing")()
    end

    -- Every crt Lua module (Lua 5.1 cannot list a directory).
    local CRT_FILES = {
        "_career_tweaker_balance_hooks.lua", "_crt_armor_settings_owner.lua",
        "_crt_balance_catalog.lua", "_crt_balance_catalog_early.lua",
        "_crt_balance_catalog_engineer.lua", "_crt_balance_catalog_focused_spirit.lua",
        "_crt_balance_catalog_late.lua", "_crt_career_unlock.lua",
        "_crt_damage_classification.lua", "_crt_dance_of_blades.lua", "_crt_diagnostics.lua",
        "_crt_flagellation.lua", "_crt_flagellation_policy.lua", "_crt_focused_spirit.lua",
        "_crt_foot_knight.lua", "_crt_foot_knight_policy.lua", "_crt_regression.lua",
        "_crt_rework_master_policy.lua", "_crt_settings_owner.lua", "_crt_talent_menu_guard.lua",
        "_crt_talent_selection.lua", "_crt_talent_swap.lua", "_crt_tourney_catalog.lua",
        "_crt_umbrella_audit_policy.lua", "_crt_wire_policy.lua", "_crt_wire_runtime.lua",
        "_lib_network_lookup.lua", "_lib_peer_parity.lua", "_lib_wire_catalog.lua",
        "career_tweaker.lua", "career_tweaker_armor_overcharge.lua", "career_tweaker_balance.lua",
        "career_tweaker_data.lua", "career_tweaker_localization.lua", "career_tweaker_mutex.lua",
        "career_tweaker_oe_cooldown.lua", "career_tweaker_tourney.lua",
    }

    H.test("CRT #1686 every literal icon crt sets exists in the 6.13.0 atlas", function()
        local seen = 0
        for _, name in ipairs(CRT_FILES) do
            local source = read(root .. name)
            for icon in source:gmatch('%f[%w_]icon%s*=%s*"([%w_]+)"') do
                seen = seen + 1
                H.truthy(not REMOVED_6130[icon],
                    name .. " still uses the atlas key 6.13.0 removed: " .. icon)
                H.truthy(ATLAS_6130[icon], name .. " icon " .. icon .. " not in the 6.13.0 atlas")
            end
        end
        -- The two Leading Shots buff rows stay literal; a smaller count means
        -- the scan pattern broke, not that crt is clean.
        H.truthy(seen >= 2, "icon literal scan found too few icons: " .. seen)
        local balance = read(root .. "career_tweaker_balance.lua")
        local unchained = assert(balance:match('BuffTemplates%.crt_unchained_ult_max_us = {(.-)\n    }'),
            "crt_unchained_ult_max_us registration not found")
        H.truthy(not unchained:find('icon = "sienna_unchained_activated_ability_power_on_enemies_hit"', 1, true),
            "Unchained career-skill buff still uses the atlas key 6.13.0 removed")
    end)

    H.test("CRT #1686 Dance of Blades and Unchained icons are the 6.13.0 names", function()
        local dance = dofile(root .. "_crt_dance_of_blades.lua")
        local stack = dance.templates()[dance.stack_buff].buffs
        H.equal(stack[1].icon, "maidenguard_4_2")
        H.equal(stack[2].icon, nil, "incoming vulnerability half must stay icon-less")
        H.truthy(dance.validate(dance.templates()), "Dance of Blades contract drifted")
        local icons = load_icons()
        H.equal(icons.UNCHAINED_ULT_ICON, "unchained_6_1")
        H.equal(icons.LEADING_SHOTS_ICON, "bardin_engineer_ranged_crit_count")
    end)

    H.test("CRT #1686 guard drops only icons the atlas cannot prove", function()
        local icons = load_icons()
        local template = { buffs = {
            { name = "a", icon = "maidenguard_4_2" },
            { name = "b", icon = "kerillian_maidenguard_cooldown_on_nearby_allies" },
            { name = "c" },
        } }
        local rewrites = icons.guard_template(atlas(ATLAS_6130), "crt_x", template)
        H.equal(#rewrites, 1)
        H.equal(rewrites[1].name, "crt_x")
        H.equal(rewrites[1].index, 2)
        H.equal(rewrites[1].from, "kerillian_maidenguard_cooldown_on_nearby_allies")
        H.equal(rewrites[1].reason, "not_in_atlas")
        H.equal(template.buffs[1].icon, "maidenguard_4_2")
        H.equal(template.buffs[2].icon, nil)
        H.equal(template.buffs[3].icon, nil)
        H.equal(#icons.guard_template(atlas(ATLAS_6130), "crt_x", template), 0, "guard is idempotent")

        local unavailable = { buffs = { { icon = "maidenguard_4_2" } } }
        rewrites = icons.guard_template(nil, "crt_y", unavailable)
        H.equal(unavailable.buffs[1].icon, nil, "missing helper must fail closed")
        H.equal(rewrites[1].reason, "atlas_unavailable")
        local raising = { buffs = { { icon = "maidenguard_4_2" } } }
        icons.guard_template({ has_atlas_settings_by_texture_name = function() error("boom") end },
            "crt_z", raising)
        H.equal(raising.buffs[1].icon, nil, "raising helper must fail closed")
        H.equal(#icons.guard_template(atlas(ATLAS_6130), "stub", { buffs = {}, _crt_pending = true }), 0)
        H.equal(#icons.guard_template(atlas(ATLAS_6130), "none", nil), 0)
    end)

    H.test("CRT #1686 apply sweep guards every registered name in set or list form", function()
        local icons = load_icons()
        local templates = {
            crt_a = { buffs = { { icon = "sienna_unchained_activated_ability_power_on_enemies_hit" } } },
            crt_b = { buffs = { { icon = "unchained_6_1" } } },
            foreign = { buffs = { { icon = "not_a_crt_name" } } },
        }
        local rewrites = icons.guard_names(atlas(ATLAS_6130), templates, { crt_a = true, crt_b = true, crt_missing = true })
        H.equal(#rewrites, 1)
        H.equal(templates.crt_a.buffs[1].icon, nil)
        H.equal(templates.crt_b.buffs[1].icon, "unchained_6_1")
        H.equal(templates.foreign.buffs[1].icon, "not_a_crt_name", "sweep must not touch foreign templates")
        templates.crt_a.buffs[1].icon = "missing_icon"
        H.equal(#icons.guard_names(atlas(ATLAS_6130), templates, { "crt_a" }), 1)
        H.equal(#icons.guard_names(atlas(ATLAS_6130), nil, { "crt_a" }), 0)
    end)

    H.test("CRT #1686 talent icon keeps the vanilla icon on an atlas miss", function()
        local icons = load_icons()
        H.equal(icons.talent_icon(atlas(ATLAS_6130), icons.LEADING_SHOTS_ICON, "vanilla"),
            "bardin_engineer_ranged_crit_count")
        H.equal(icons.talent_icon(atlas(without(ATLAS_6130, "bardin_engineer_ranged_crit_count")),
            icons.LEADING_SHOTS_ICON, "vanilla"), "vanilla")
        H.equal(icons.talent_icon(nil, icons.LEADING_SHOTS_ICON, "vanilla"), "vanilla")
    end)

    H.test("CRT #1686 Leading Shots routes its talent icon through the guard", function()
        local build = assert(loadfile(root .. "_crt_balance_catalog_engineer.lua"))()
        local perk_module = "scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names"
        local saved_globals = {
            BuffTemplates = rawget(_G, "BuffTemplates"), AttackTypes = rawget(_G, "AttackTypes"),
            Talents = rawget(_G, "Talents"), TalentIDLookup = rawget(_G, "TalentIDLookup"),
            UIAtlasHelper = rawget(_G, "UIAtlasHelper"), preload = package.preload[perk_module],
            loaded = package.loaded[perk_module],
        }
        local function run(names)
            package.loaded[perk_module] = nil
            package.preload[perk_module] = function() return { guaranteed_crit = "guaranteed_crit" } end
            local talent = { buffs = {}, icon = "vanilla_talent_icon" }
            _G.BuffTemplates = {}
            _G.AttackTypes = { projectile = 1, instant_projectile = 2, heavy_instant_projectile = 3 }
            _G.Talents = { dwarf_ranger = { [1] = talent } }
            _G.TalentIDLookup = { bardin_engineer_improved_explosives = { hero_name = "dwarf_ranger", talent_id = 1 } }
            _G.UIAtlasHelper = atlas(names)
            local defs = build({ make_stub = function() return { _crt_pending = true } end, buff_icons = load_icons() })
            defs.rework_dr_engineer_leading_shots.custom_apply({})
            return talent.icon
        end
        local ok, err = pcall(function()
            H.equal(run(ATLAS_6130), "bardin_engineer_ranged_crit_count")
            H.equal(run(without(ATLAS_6130, "bardin_engineer_ranged_crit_count")), "vanilla_talent_icon")
        end)
        for key, value in pairs(saved_globals) do
            if key == "preload" then package.preload[perk_module] = value
            elseif key == "loaded" then package.loaded[perk_module] = value
            else _G[key] = value end
        end
        if not ok then error(err, 0) end
    end)

    H.test("CRT #1686 audit passes on 6.13.0 and fails on drift", function()
        local icons = load_icons()
        local dance = dofile(root .. "_crt_dance_of_blades.lua")
        local fk_icons = {
            crt_fk_rock_shield_power = "markus_knight_passive_block_cost_aura",
            crt_fk_teamwork_great_power = "markus_knight_damage_taken_ally_proximity",
            crt_fk_final_march = "markus_knight_movement_speed_on_incapacitated_allies",
        }
        local live = { crt_unchained_ult_max_us = { buffs = { { icon = icons.UNCHAINED_ULT_ICON } } } }
        local function entries()
            return icons.icon_entries({
                factory_templates = dance.templates(), foot_knight_icons = fk_icons,
                buff_templates = live, names = { crt_unchained_ult_max_us = true },
            })
        end
        local list = entries()
        H.truthy(#list >= 7, "audit covers constants, factory, Foot Knight and live rows")
        H.equal(icons.audit(atlas(ATLAS_6130), list), nil)

        local message = icons.audit(atlas(without(ATLAS_6130, "maidenguard_4_2")), entries())
        H.truthy(message and message:find("maidenguard_4_2", 1, true), "factory drift must fail the audit")
        message = icons.audit(atlas(without(ATLAS_6130, "unchained_6_1")), entries())
        H.truthy(message and message:find("unchained_6_1", 1, true), "constant drift must fail the audit")
        live.crt_unchained_ult_max_us.buffs[1].icon = "sienna_unchained_activated_ability_power_on_enemies_hit"
        message = icons.audit(atlas(ATLAS_6130), entries())
        H.truthy(message and message:find("live crt_unchained_ult_max_us", 1, true), "live stale icon must fail")
        H.truthy(icons.audit(nil, entries()):find("unavailable", 1, true))
        H.truthy(icons.audit(atlas(ATLAS_6130), {}):find("no crt icon entries", 1, true))
    end)

    H.test("CRT #1686 every crt icon registration routes through the guard", function()
        local balance = read(root .. "career_tweaker_balance.lua")
        local entry = read(root .. "career_tweaker.lua")
        local fk = read(root .. "_crt_foot_knight.lua")
        local regression = read(root .. "_crt_regression.lua")
        local composer = read(root .. "_crt_balance_catalog.lua")
        local icons = load_icons()
        local load_at = assert(entry:find('mod._crt.buff_icons = mod:dofile("scripts/mods/career_tweaker/_crt_buff_icons")', 1, true),
            "entry must load the guard")
        local balance_at = assert(entry:find('pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_balance")', 1, true))
        H.truthy(load_at < balance_at, "guard must load before the balance registrations")
        local unchained = assert(balance:match('BuffTemplates%.crt_unchained_ult_max_us = {(.-)\n    }'))
        H.truthy(unchained:find('icon = "' .. icons.UNCHAINED_ULT_ICON .. '"', 1, true),
            "Unchained template and audited constant diverged")
        local sweep = assert(entry:find("buff_icons.guard_names(rawget(_G, \"UIAtlasHelper\"),\n            rawget(_G, \"BuffTemplates\"), mod._crt_mod_registered_buff_names))", 1, true),
            "entry must sweep every crt-registered template")
        local wrap_at = assert(entry:find("balance.apply = function(...)\n        apply_registrations(...)\n        sweep_icons(\"apply\")", 1, true),
            "every balance apply pass must end with the sweep")
        H.truthy(entry:find('sweep_icons("load")', 1, true), "load-time registrations must be swept")
        H.truthy(balance_at < sweep and sweep < wrap_at)
        H.truthy(composer:find("ctx.buff_icons = ctx.buff_icons or", 1, true), "catalog context must carry the guard")
        H.truthy(fk:find('icons.guard_and_log(rawget(_G, "UIAtlasHelper"), "foot_knight", name, body)', 1, true))
        H.truthy(regression:find('_rt_register("issue1686_buff_icons_in_atlas"', 1, true))
        H.equal(balance:find("_G.printf", 1, true), nil)
        H.equal(read(root .. "_crt_buff_icons.lua"):find("_G.printf", 1, true), nil)
    end)

    local home = os.getenv("USERPROFILE") or ""
    local atlas_path = (os.getenv("VT2_SOURCE_ROOT") or (home .. "/source/repos/Vermintide-2-Source-Code"))
        .. "/scripts/ui/atlas_settings/gui_icons_atlas.lua"
    local handle = io.open(atlas_path, "rb")
    local vanilla_atlas = handle and handle:read("*a")
    if handle then handle:close() end
    H.test_if(vanilla_atlas ~= nil, "CRT #1686 fixture matches the local decompiled 6.13.0 atlas", function()
        for name in pairs(ATLAS_6130) do
            H.truthy(vanilla_atlas:find("\n\t" .. name .. " = {", 1, true), name .. " missing from local atlas")
        end
        for name in pairs(REMOVED_6130) do
            H.equal(vanilla_atlas:find("\n\t" .. name .. " = {", 1, true), nil, name .. " back in local atlas")
        end
    end, "optional local decompiled vanilla atlas unavailable")
end
