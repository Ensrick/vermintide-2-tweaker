return function(H, repo_root)
    local base = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"
    local catalog = assert(loadfile(base .. "_crt_tourney_catalog.lua"))()

    local function read_all(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function load_data()
        local previous = _G.get_mod
        _G.get_mod = function() return { localize = function(_, id) return id end } end
        local ok, data = pcall(assert(loadfile(base .. "career_tweaker_data.lua")))
        _G.get_mod = previous
        H.truthy(ok, tostring(data))
        return data
    end

    H.test("CRT Tourney catalog owns 17 presets and 46 unique mutation leaves", function()
        H.equal(#catalog.CAREERS, 17)
        H.equal(#catalog.MASTER_IDS, 17)
        H.equal(#catalog.LEAF_IDS, 46)
        local seen = {}
        for _, leaf_id in ipairs(catalog.LEAF_IDS) do
            H.equal(seen[leaf_id], nil, "duplicate leaf " .. leaf_id)
            seen[leaf_id] = true
            H.truthy(catalog.MASTER_BY_LEAF[leaf_id], "unowned leaf " .. leaf_id)
        end
    end)

    H.test("CRT Tourney career presets write only changed leaves and derive exact state", function()
        for _, career in ipairs(catalog.CAREERS) do
            local changes = catalog.plan_master(career.master_id, true, {})
            H.equal(#changes, #career.leaves + 1)
            local current = { [career.master_id] = true }
            for _, leaf_id in ipairs(career.leaves) do current[leaf_id] = true end
            H.equal(#catalog.plan_master(career.master_id, true, current), 0)
            H.equal(catalog.derive_master(career.master_id, current), true)
            current[career.leaves[1]] = false
            H.equal(catalog.derive_master(career.master_id, current), false)
        end
    end)

    H.test("CRT Tourney legacy ON presets expand once without touching other careers", function()
        local first = catalog.CAREERS[1]
        local second = catalog.CAREERS[2]
        local changes = catalog.plan_legacy_migration({ [first.master_id] = true })
        H.equal(#changes, #first.leaves)
        local seen = {}
        for _, change in ipairs(changes) do seen[change.id] = change.value end
        for _, leaf_id in ipairs(first.leaves) do H.equal(seen[leaf_id], true) end
        for _, leaf_id in ipairs(second.leaves) do H.equal(seen[leaf_id], nil) end

        local migrated = { [first.master_id] = true }
        for _, leaf_id in ipairs(first.leaves) do migrated[leaf_id] = true end
        H.equal(#catalog.plan_legacy_migration(migrated), 0)
    end)

    H.test("CRT Tourney leaves are integrated under their career and old root is gone", function()
        local data = load_data()
        local parent_by_id = {}
        local function visit(widget, parent_id)
            if type(widget) ~= "table" then return end
            if widget.setting_id then parent_by_id[widget.setting_id] = parent_id end
            for _, child in ipairs(widget.sub_widgets or {}) do visit(child, widget.setting_id) end
        end
        for _, widget in ipairs(data.options.widgets) do visit(widget, nil) end
        H.equal(parent_by_id.trn_career_group, nil)
        for _, career in ipairs(catalog.CAREERS) do
            H.equal(parent_by_id[career.master_id], career.parent_id)
            for _, leaf_id in ipairs(career.leaves) do
                H.equal(parent_by_id[leaf_id], career.parent_id)
            end
        end
    end)

    H.test("CRT Tourney runtime implements every catalog leaf and no preset mutates gameplay", function()
        local source = read_all(base .. "career_tweaker_tourney.lua")
        for _, leaf_id in ipairs(catalog.LEAF_IDS) do
            H.truthy(source:find(leaf_id .. " =", 1, true), "missing runtime leaf " .. leaf_id)
        end
        for _, master_id in ipairs(catalog.MASTER_IDS) do
            H.equal(source:find("    " .. master_id .. " =", 1, true), nil,
                "career preset must not own a runtime mutation: " .. master_id)
        end
        H.truthy(source:find("trn_wh_priest_prayer_movement_speed = {", 1, true))
        H.truthy(source:find("network_unsafe = true", 1, true), "WP leaf lost peer-parity gate")
    end)

    H.test("CRT Tourney visible controls use concise TB attribution and descriptions", function()
        local policy = assert(loadfile(base .. "_crt_rework_master_policy.lua"))()
        local require_key = "scripts/mods/career_tweaker/_crt_rework_master_policy"
        local previous = package.preload[require_key]
        package.preload[require_key] = function() return policy end
        local ok, localization = pcall(assert(loadfile(base .. "career_tweaker_localization.lua")))
        package.preload[require_key] = previous
        H.truthy(ok, tostring(localization))
        for _, id in ipairs(catalog.MASTER_IDS) do
            H.equal(localization[id].en:sub(1, 4), "[TB]")
        end
        for _, id in ipairs(catalog.LEAF_IDS) do
            H.equal(localization[id].en:sub(1, 4), "[TB]")
            H.truthy(localization[id .. "_description"], "missing description for " .. id)
        end
    end)

    H.test("CRT Tourney exact conflicts cover every shared field and preserve Ensrick live", function()
        local saved_globals = {
            get_mod = _G.get_mod, BuffTemplates = _G.BuffTemplates,
            NetworkLookup = _G.NetworkLookup, printf = _G.printf,
        }
        local settings = {}
        local mock = {
            _crt_peer_parity = { applied_state = function() return "enabled" end },
            get = function(_, id) return settings[id] end,
            dofile = function(_, path) return assert(loadfile(repo_root .. "/career_tweaker/" .. path .. ".lua"))() end,
        }
        _G.get_mod = function() return mock end
        _G.printf = function() end
        _G.NetworkLookup = { buff_templates = {} }
        _G.BuffTemplates = {}

        local cases = {
            {
                tourney = "trn_es_huntsman_crit_aura_range",
                ensrick = "rework_es_huntsman_crit_aura_unlimited_range",
                buff = "markus_huntsman_passive_crit_aura", field = "range", value = 20,
            },
            {
                tourney = "trn_es_knight_protective_presence",
                ensrick = "rework_es_knight_protective_presence_10m_rock_20m",
                buff = "markus_knight_passive", field = "range", value = 20,
            },
            {
                tourney = "trn_es_questingknight_kill_move_speed_duration",
                ensrick = "rework_es_questingknight_virtue_of_impetuous_buffed",
                buff = "markus_questing_knight_ability_buff_on_kill_movement_speed",
                field = "duration", value = 25,
            },
            {
                tourney = "trn_dr_ranger_exuberance_dr",
                ensrick = "rework_dr_ranger_exuberance_stacking_dr",
                buff = "bardin_ranger_reduced_damage_taken_headshot_buff",
                field = "multiplier", value = -0.2,
            },
            {
                tourney = "trn_wh_bountyhunter_double_shotted_refund",
                ensrick = "rework_wh_bountyhunter_double_shotted_80",
                buff = "victor_bountyhunter_activated_ability_railgun_delayed_add",
                field = "multiplier", value = 0.8,
            },
            {
                tourney = "trn_wh_bountyhunter_just_reward_cooldown",
                ensrick = "rework_wh_bountyhunter_just_reward_5s_cooldown",
                buff = "victor_bountyhunter_activated_ability_passive_cooldown_reduction",
                field = "cooldown", value = 4.5,
            },
            {
                tourney = "trn_wh_zealot_melee_power",
                ensrick = "rework_wh_zealot_power_5_to_10",
                buff = "victor_zealot_power", field = "multiplier", value = 0.2,
            },
            {
                tourney = "trn_bw_adept_famished_flames",
                ensrick = "rework_bw_adept_famished_flames_buffed",
                buff = "sienna_adept_increased_burn_damage", field = "multiplier", value = 1.5,
            },
            {
                tourney = "trn_bw_adept_fires_from_ash",
                ensrick = "rework_bw_adept_fires_from_ash_1pct_plus_thp",
                buff = "sienna_adept_cooldown_reduction_on_burning_enemy_killed",
                field = "cooldown_reduction", value = 0.02,
            },
        }
        for _, case in ipairs(cases) do
            _G.BuffTemplates[case.buff] = { buffs = {{ [case.field] = 0 }} }
        end

        local ok, err = pcall(function()
            local runtime = assert(loadfile(base .. "career_tweaker_tourney.lua"))()
            local expected = {}
            for _, case in ipairs(cases) do expected[case.tourney] = case.ensrick end

            local conflict_count = 0
            for leaf_id, rivals in pairs(runtime.CONFLICTS) do
                conflict_count = conflict_count + 1
                H.truthy(expected[leaf_id], "unexpected conflict leaf " .. tostring(leaf_id))
                H.equal(#rivals, 1, "conflict must remain exact for " .. leaf_id)
                H.equal(rivals[1], expected[leaf_id], "wrong Ensrick owner for " .. leaf_id)
            end
            H.equal(conflict_count, #cases, "known exact-conflict table drift")

            -- Derive every literal buff-field overlap from production sources.
            -- Zealot's helper-built patch is covered by the explicit table above.
            local balance_source = read_all(base .. "career_tweaker_balance.lua")
            local balance_owners = {}
            local current_id
            for line in balance_source:gmatch("[^\r\n]+") do
                current_id = line:match("^    (rework_[%w_]+)%s*=") or current_id
                local buff, field = line:match('buff%s*=%s*"([^"]+)".-field%s*=%s*"([^"]+)"')
                if current_id and buff and field then
                    local key = buff .. "|" .. field
                    balance_owners[key] = balance_owners[key] or {}
                    balance_owners[key][current_id] = true
                end
            end
            local literal_overlap_leaves = {}
            for leaf_id, definition in pairs(runtime.TOURNEY_MODS) do
                for _, patch in ipairs(definition.patches or {}) do
                    local owners = balance_owners[patch.buff .. "|" .. patch.field]
                    for owner_id in pairs(owners or {}) do
                        literal_overlap_leaves[leaf_id] = true
                        local found = false
                        for _, rival in ipairs(runtime.CONFLICTS[leaf_id] or {}) do
                            if rival == owner_id then found = true; break end
                        end
                        H.truthy(found, leaf_id .. " misses shared-field owner " .. owner_id)
                    end
                end
            end
            local literal_overlap_count = 0
            for _ in pairs(literal_overlap_leaves) do literal_overlap_count = literal_overlap_count + 1 end
            H.equal(literal_overlap_count, 8, "literal shared-field census drift")

            for index, case in ipairs(cases) do
                local field = _G.BuffTemplates[case.buff].buffs[1]
                local sentinel = 700 + index
                field[case.field] = sentinel
                settings[case.tourney] = true
                settings[case.ensrick] = true
                runtime.apply()
                H.equal(field[case.field], sentinel,
                    case.tourney .. " overwrote the selected Ensrick owner")

                settings[case.ensrick] = false
                runtime.apply()
                H.equal(field[case.field], case.value,
                    case.tourney .. " did not resume after Ensrick cleared")

                settings[case.tourney] = false
                runtime.apply()
                H.equal(field[case.field], sentinel,
                    case.tourney .. " did not restore the prior owner exactly")
            end
            runtime.restore()
        end)

        _G.get_mod = saved_globals.get_mod
        _G.BuffTemplates = saved_globals.BuffTemplates
        _G.NetworkLookup = saved_globals.NetworkLookup
        _G.printf = saved_globals.printf
        H.truthy(ok, tostring(err))
    end)

    H.test("CRT Tourney runtime applies and restores leaves independently", function()
        local saved_globals = {
            get_mod = _G.get_mod, BuffTemplates = _G.BuffTemplates,
            NetworkLookup = _G.NetworkLookup, printf = _G.printf,
            PassiveAbilitySettings = _G.PassiveAbilitySettings,
        }
        local settings = {}
        local mock = {
            _crt_peer_parity = { applied_state = function() return "enabled" end },
            get = function(_, id) return settings[id] end,
            dofile = function(_, path) return assert(loadfile(repo_root .. "/career_tweaker/" .. path .. ".lua"))() end,
        }
        _G.get_mod = function() return mock end
        _G.printf = function() end
        _G.NetworkLookup = { buff_templates = {} }
        _G.PassiveAbilitySettings = {}
        _G.BuffTemplates = {
            markus_huntsman_passive_crit_aura = { buffs = {{ range = 5 }} },
            markus_huntsman_activated_ability_increased_reload_speed = { buffs = {{ multiplier = -0.4 }} },
            markus_huntsman_activated_ability_increased_reload_speed_duration = { buffs = {{ multiplier = -0.4 }} },
            bardin_slayer_push_on_dodge = { buffs = {{}} },
        }

        local ok, err = pcall(function()
            local runtime = assert(loadfile(base .. "career_tweaker_tourney.lua"))()
            settings.trn_es_huntsman_prowl_reload_speed = true
            runtime.apply()
            H.equal(_G.BuffTemplates.markus_huntsman_passive_crit_aura.buffs[1].range, 5)
            H.equal(_G.BuffTemplates.markus_huntsman_activated_ability_increased_reload_speed.buffs[1].multiplier, -0.25)

            settings.trn_es_huntsman_crit_aura_range = true
            settings.rework_es_huntsman_crit_aura_unlimited_range = true
            runtime.apply()
            H.equal(_G.BuffTemplates.markus_huntsman_passive_crit_aura.buffs[1].range, 5,
                "exact conflict should suppress only the aura leaf")
            H.equal(_G.BuffTemplates.markus_huntsman_activated_ability_increased_reload_speed.buffs[1].multiplier, -0.25,
                "unrelated Huntsman leaf must remain active")

            settings.trn_es_huntsman_prowl_reload_speed = false
            settings.trn_es_huntsman_crit_aura_range = false
            settings.trn_dr_slayer_dodge_damage_reduction = true
            runtime.apply()
            local slayer = _G.BuffTemplates.bardin_slayer_push_on_dodge.buffs[1]
            H.equal(slayer.stat_buff, "damage_taken")
            H.equal(slayer.multiplier, -0.15)
            runtime.restore()
            H.equal(slayer.stat_buff, nil, "nil source field must restore exactly")
            H.equal(slayer.multiplier, nil, "nil source field must restore exactly")
        end)

        _G.get_mod = saved_globals.get_mod
        _G.BuffTemplates = saved_globals.BuffTemplates
        _G.NetworkLookup = saved_globals.NetworkLookup
        _G.printf = saved_globals.printf
        _G.PassiveAbilitySettings = saved_globals.PassiveAbilitySettings
        H.truthy(ok, tostring(err))
    end)
end
