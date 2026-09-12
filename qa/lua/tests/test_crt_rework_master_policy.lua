return function(H, repo_root)
    local policy_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_rework_master_policy.lua"
    local module = assert(loadfile(policy_path))()
    local policy = module.new({ rework_b = {}, rework_a = {} }, { "trn_b", "trn_a" })

    local function load_localization()
        local require_key = "scripts/mods/career_tweaker/_crt_rework_master_policy"
        local previous = package.preload[require_key]
        package.preload[require_key] = function() return module end
        local loc_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_localization.lua"
        local ok, localization = pcall(assert(loadfile(loc_path)))
        package.preload[require_key] = previous
        H.truthy(ok, tostring(localization))
        return localization
    end

    local function change_map(changes)
        local out = {}
        for i = 1, #changes do
            H.equal(out[changes[i].id], nil, "duplicate write for " .. changes[i].id)
            out[changes[i].id] = changes[i].value
        end
        return out
    end

    H.test("CRT rework master enables one complete family in one bounded plan", function()
        local changes = policy:plan("ensrick", true, {
            rework_a = false, rework_b = false, trn_a = true, trn_b = false,
            [module.MASTER_ENSRICK] = false, [module.MASTER_TOURNEY] = true,
        })
        local got = change_map(changes)
        H.equal(#changes, 5, "only changed leaves and master flags should be written")
        H.equal(got.rework_a, true)
        H.equal(got.rework_b, true)
        H.equal(got.trn_a, false)
        H.equal(got[module.MASTER_ENSRICK], true)
        H.equal(got[module.MASTER_TOURNEY], false)
        H.equal(got.trn_b, nil, "already-false rival leaf should not be rewritten")
    end)

    H.test("CRT rework master off clears only its own family", function()
        local changes = change_map(policy:plan("tourney", false, {
            rework_a = true, rework_b = false, trn_a = true, trn_b = true,
            [module.MASTER_TOURNEY] = true,
        }))
        H.equal(changes.trn_a, false)
        H.equal(changes.trn_b, false)
        H.equal(changes[module.MASTER_TOURNEY], false)
        H.equal(changes.rework_a, nil, "custom rival state must be preserved")
    end)

    H.test("CRT rework master indicators represent exact family state", function()
        local partial = policy:derive_masters({ rework_a=true, rework_b=false, trn_a=false, trn_b=false })
        H.equal(partial[module.MASTER_ENSRICK], false)
        H.equal(partial[module.MASTER_TOURNEY], false)
        local exact = policy:derive_masters({ rework_a=false, rework_b=false, trn_a=true, trn_b=true })
        H.equal(exact[module.MASTER_ENSRICK], false)
        H.equal(exact[module.MASTER_TOURNEY], true)
    end)

    H.test("CRT all-reworks master plans both families without per-leaf callback fanout", function()
        local got = change_map(policy:plan("all", true, {
            rework_a = false, rework_b = true, trn_a = false, trn_b = true,
        }))
        H.equal(got.rework_a, true)
        H.equal(got.rework_b, nil)
        H.equal(got.trn_a, true)
        H.equal(got.trn_b, nil)
        H.equal(got[module.MASTER_ENSRICK], nil)
        H.equal(got[module.MASTER_TOURNEY], nil)
        H.equal(got[module.MASTER_ALL], true)

        local exact = policy:derive_masters({ rework_a=true, rework_b=true, trn_a=true, trn_b=true })
        H.equal(exact[module.MASTER_ENSRICK], false)
        H.equal(exact[module.MASTER_TOURNEY], false)
        H.equal(exact[module.MASTER_ALL], true)
    end)

    H.test("CRT family and all masters reconcile Foot Knight secondary carriers once", function()
        local globals = {
            get_mod = _G.get_mod,
            BuffTemplates = _G.BuffTemplates,
            BuffFunctionTemplates = _G.BuffFunctionTemplates,
            CareerSettings = _G.CareerSettings,
            SPProfiles = _G.SPProfiles,
            HeroWindowLoadoutInventory = _G.HeroWindowLoadoutInventory,
            HeroWindowLoadoutInventoryConsole = _G.HeroWindowLoadoutInventoryConsole,
            printf = _G.printf,
        }
        local perk_key = "scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names"
        local old_preload = package.preload[perk_key]
        local old_loaded = package.loaded[perk_key]
        local settings = {}
        local backend_types = { "ranged" }
        local menu_types = { "ranged" }
        local mock = {
            get = function(_, id) return settings[id] end,
            dofile = function(_, path)
                return assert(loadfile(repo_root .. "/career_tweaker/" .. path .. ".lua"))()
            end,
            hook = function() end,
        }

        _G.get_mod = function() return mock end
        _G.BuffTemplates = {}
        _G.BuffFunctionTemplates = nil
        _G.CareerSettings = {
            es_knight = {
                name = "es_knight",
                item_slot_types_by_slot_name = { slot_ranged = backend_types },
            },
        }
        _G.SPProfiles = {
            [4] = {
                careers = {
                    [3] = {
                        name = "es_knight",
                        item_slot_types_by_slot_name = { slot_ranged = menu_types },
                    },
                },
            },
        }
        _G.HeroWindowLoadoutInventory = nil
        _G.HeroWindowLoadoutInventoryConsole = nil
        _G.printf = function() end
        package.loaded[perk_key] = nil
        package.preload[perk_key] = function()
            return { uninterruptible_heavy = "uninterruptible_heavy" }
        end

        local foot_knight
        local ok, err = pcall(function()
            foot_knight = assert(loadfile(
                repo_root .. "/career_tweaker/scripts/mods/career_tweaker/_crt_foot_knight.lua"))()
            local master_policy = module.new({
                rework_es_knight_secondary_melee = {},
                rework_other = {},
            }, {
                trn_other = {},
            })

            local function exercise(family)
                settings = {}
                foot_knight.apply_settings()
                H.deep_equal(backend_types, { "ranged" })
                H.deep_equal(menu_types, { "ranged" })

                local batch = false
                local writer_calls, callback_calls = 0, 0
                local nested_owner_applies, engine_applies, live_applies = 0, 0, 0
                local function nested_setting_callback()
                    callback_calls = callback_calls + 1
                    if batch then return end
                    nested_owner_applies = nested_owner_applies + 1
                end
                local function write_changes(changes)
                    writer_calls = writer_calls + 1
                    batch = true
                    for _, change in ipairs(changes) do
                        settings[change.id] = change.value
                        nested_setting_callback()
                    end
                    batch = false
                    return true
                end

                local applied, changes = module.apply_bounded_master(
                    master_policy, family, true, settings,
                    write_changes,
                    function() engine_applies = engine_applies + 1 end,
                    function()
                        live_applies = live_applies + 1
                        foot_knight.apply_settings()
                    end)
                H.equal(applied, true)
                H.equal(writer_calls, 1)
                H.equal(callback_calls, #changes)
                H.equal(nested_owner_applies, 0,
                    "programmatic leaf callbacks must stay under the batch guard")
                H.equal(engine_applies, 1)
                H.equal(live_applies, 1)
                H.deep_equal(backend_types, { "melee", "ranged" })
                H.deep_equal(menu_types, { "melee", "ranged" })

                settings.rework_es_knight_secondary_melee = false
                foot_knight.apply_settings()
            end

            exercise("ensrick")
            exercise("all")
        end)

        if foot_knight then pcall(foot_knight.restore) end
        package.preload[perk_key] = old_preload
        package.loaded[perk_key] = old_loaded
        _G.get_mod = globals.get_mod
        _G.BuffTemplates = globals.BuffTemplates
        _G.BuffFunctionTemplates = globals.BuffFunctionTemplates
        _G.CareerSettings = globals.CareerSettings
        _G.SPProfiles = globals.SPProfiles
        _G.HeroWindowLoadoutInventory = globals.HeroWindowLoadoutInventory
        _G.HeroWindowLoadoutInventoryConsole = globals.HeroWindowLoadoutInventoryConsole
        _G.printf = globals.printf
        H.truthy(ok, tostring(err))
    end)

    H.test("CRT rework engines preserve the selected owner across conflict transitions", function()
        local value = 5
        local tourney_saved
        local balance_saved
        local tourney_on = true
        local ensrick_on = false

        local tourney = {
            restore = function()
                if tourney_saved ~= nil then value = tourney_saved end
                tourney_saved = nil
            end,
            apply = function()
                if tourney_saved ~= nil then value = tourney_saved end
                tourney_saved = nil
                if tourney_on and not ensrick_on then
                    tourney_saved = value
                    value = 20
                end
            end,
        }
        local balance = {
            apply = function()
                if balance_saved ~= nil then value = balance_saved end
                balance_saved = nil
                if ensrick_on then
                    balance_saved = value
                    value = 999
                end
            end,
        }

        module.reconcile_engines(balance, tourney)
        H.equal(value, 20, "Tourney should own the field before the conflict is selected")

        ensrick_on = true
        module.reconcile_engines(balance, tourney)
        H.equal(value, 999, "Tourney restore must not clobber the newly selected Ensrick value")

        ensrick_on = false
        module.reconcile_engines(balance, tourney)
        H.equal(value, 20, "Tourney should resume after the Ensrick conflict is cleared")
    end)

    H.test("CRT active rework labels carry derived family prefixes", function()
        local localization = load_localization()
        local checked = 0
        for key, row in pairs(localization) do
            if module.is_leaf_localization_key(key) then
                local _, metadata = module.family_for_setting(key)
                H.equal(row.en:sub(1, #metadata.label_prefix), metadata.label_prefix,
                    key .. " missing family prefix")
                H.equal(row.en:find("[Ensrick's Reworks]", 1, true), nil,
                    key .. " retained superseded suffix")
                checked = checked + 1
            end
        end
        H.truthy(checked > 50, "expected the complete active rework catalog")
        H.equal(localization.rework_master_group.en, "Master Toggles")
        H.equal(localization.rework_master_ensrick.en:find("[Ensrick", 1, true), nil,
            "navigation/master rows should remain undecorated")
        -- Every master control shares the control prefix; none may inherit an
        -- authorship prefix from the family whose setting prefix it happens
        -- to start with (the Tourney and all-reworks rows begin with rework_).
        for _, id in ipairs({ module.MASTER_ENSRICK, module.MASTER_TOURNEY,
                module.MASTER_ALL, module.MASTER_ARMOR }) do
            H.equal(module.family_for_setting(id), nil, id .. " must not be a family leaf")
            H.equal(localization[id].en:find("^%["), nil, id .. " must stay undecorated")
        end
        H.equal(localization.rework_master_tourney.en, "Enable all Tourney Balance Reworks")
        H.equal(localization.rework_master_all.en, "Enable All Reworks")
        H.equal(localization.rework_master_armor.en, "Enable all Armor Controls")
        H.truthy(type(localization.rework_master_armor_description) == "table"
            and type(localization.rework_master_armor_description.en) == "string",
            "armor master needs a player-facing description")
        H.equal(localization.rework_master_armor_description.en:find("\226\128\148", 1, true), nil,
            "no em dash in menu text")
    end)

    H.test("CRT data nests all four live master controls in their own group", function()
        local old_get_mod = _G.get_mod
        _G.get_mod = function()
            return { localize = function(_, id) return id end }
        end
        local data_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_data.lua"
        local ok, data = pcall(assert(loadfile(data_path)))
        _G.get_mod = old_get_mod
        H.truthy(ok, tostring(data))

        local found = {}
        local master_group_parent
        local function visit(widget, parent_id)
            if type(widget) ~= "table" then return end
            if widget.setting_id == "rework_master_group" then
                master_group_parent = parent_id
                H.equal(widget.type, "group")
            end
            if widget.setting_id == module.MASTER_ENSRICK or widget.setting_id == module.MASTER_TOURNEY
                    or widget.setting_id == module.MASTER_ALL or widget.setting_id == module.MASTER_ARMOR then
                found[widget.setting_id] = { type = widget.type, parent = parent_id, tooltip = widget.tooltip }
            end
            for _, child in ipairs(widget.sub_widgets or {}) do visit(child, widget.setting_id) end
        end
        for _, widget in ipairs(data.options and data.options.widgets or {}) do visit(widget, nil) end
        H.equal(master_group_parent, "talent_reworks_group")
        H.equal(found[module.MASTER_ENSRICK].type, "checkbox")
        H.equal(found[module.MASTER_ENSRICK].parent, "rework_master_group")
        H.equal(found[module.MASTER_TOURNEY].type, "checkbox")
        H.equal(found[module.MASTER_TOURNEY].parent, "rework_master_group")
        H.equal(found[module.MASTER_ALL].type, "checkbox")
        H.equal(found[module.MASTER_ALL].parent, "rework_master_group")
        H.equal(found[module.MASTER_ARMOR].type, "checkbox")
        H.equal(found[module.MASTER_ARMOR].parent, "rework_master_group")
        H.equal(found[module.MASTER_ARMOR].tooltip, "rework_master_armor_description")
    end)

    H.test("CRT every visible rework checkbox has one family prefix", function()
        local old_get_mod = _G.get_mod
        _G.get_mod = function()
            return { localize = function(_, id) return id end }
        end
        local data_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_data.lua"
        local ok, data = pcall(assert(loadfile(data_path)))
        _G.get_mod = old_get_mod
        H.truthy(ok, tostring(data))
        local localization = load_localization()

        local checked = 0
        local function visit(widget)
            if type(widget) ~= "table" then return end
            local family, metadata = module.family_for_setting(widget.setting_id)
            if family and widget.type == "checkbox" then
                local row = localization[widget.setting_id]
                H.truthy(type(row) == "table" and type(row.en) == "string",
                    widget.setting_id .. " missing localization")
                H.equal(row.en:sub(1, #metadata.label_prefix), metadata.label_prefix,
                    widget.setting_id .. " missing exact authorship prefix")
                checked = checked + 1
            end
            for _, child in ipairs(widget.sub_widgets or {}) do visit(child) end
        end
        for _, widget in ipairs(data.options and data.options.widgets or {}) do visit(widget) end
        H.truthy(checked > 50, "expected every active visible rework checkbox")
    end)

    -- Issue #221 armor cluster: a bounded snapshot/restore transaction.
    local armor = module.FAMILIES.armor
    local function saved(id) return armor.snapshot_prefix .. id end

    H.test("CRT #221 repeated armor ON preserves the held preimage for every leaf combination", function()
        for _, a in ipairs({ false, true }) do
            for _, b in ipairs({ false, true }) do
                local state = { [armor.ids[1]] = a, [armor.ids[2]] = b }
                local function apply(changes)
                    for _, change in ipairs(changes) do state[change.id] = change.value end
                end
                apply(policy:plan("armor", true, state))
                for _ = 1, 3 do
                    H.equal(#policy:plan("armor", true, state), 0, "held ON is an idempotent plan")
                end
                apply(policy:plan("armor", false, state))
                H.equal(state[armor.ids[1]], a, "first preimage must survive repeated ON")
                H.equal(state[armor.ids[2]], b, "second preimage must survive repeated ON")
            end
        end
    end)

    local runtime = assert(loadfile(repo_root .. "/qa/lua/tests/_crt_armor_runtime_fixture.lua"))()
    H.test("CRT #221 actual callback and GUT OFF-ON Apply retain the first snapshot", function()
        local world = runtime(repo_root, { [armor.ids[1]] = false, [armor.ids[2]] = true })
        world.mod:set(armor.master_id, true, true)
        local writes = world.calls.writes
        world.view:stage_set(world.category, armor.master_id, false)
        world.view:stage_set(world.category, armor.master_id, true)
        H.equal(world.calls.writes, writes, "staging does not write live settings")
        world.view:apply_pending(world.category)
        H.equal(world.calls.writes, writes + 1, "Apply persists the master but no snapshot replacement")
        H.equal(world.calls.events, 1, "owner participant writes remain silent")
        H.equal(next(world.view._pending.crt), nil, "real Apply completes its buffer")
        H.equal(world.view.captured[world.profiles.member_key("crt", armor.master_id)], true)
        H.equal(world.view.captured[world.profiles.member_key("crt", armor.snapshot_id)], nil,
            "private setting IDs never enter the visible profile map")
        H.equal(world.profiles.owner_states(world.view.captured).crt.saved[armor.ids[1]], false)
        world.mod:set(armor.master_id, false, true)
        H.equal(world.state[armor.ids[1]], false)
        H.equal(world.state[armor.ids[2]], true)
        H.equal(world.calls.engines, 0, "armor must not reconcile #445 owners")
        H.equal(world.calls.foot_knight, 0)
    end)

    H.test("CRT #221 held snapshot survives runtime recreation and another ON", function()
        local first = runtime(repo_root, { [armor.ids[1]] = true, [armor.ids[2]] = false })
        first.mod:set(armor.master_id, true, true)
        local restarted = runtime(repo_root, first.state)
        restarted.mod:set(armor.master_id, true, true)
        restarted.mod:set(armor.master_id, false, true)
        H.equal(restarted.state[armor.ids[1]], true)
        H.equal(restarted.state[armor.ids[2]], false)
        H.equal(first.state[armor.master_id], true, "fixture storage is independently reconstructed")

        restarted.mod:set(armor.ids[1], false, true)
        restarted.mod:set(armor.ids[2], true, true)
        restarted.mod:set(armor.master_id, true, true)
        restarted.mod:set(armor.master_id, false, true)
        H.equal(restarted.state[armor.ids[1]], false, "new transaction captures new choices")
        H.equal(restarted.state[armor.ids[2]], true)
    end)

    local function complete_world(a, b, surface, profile_values, vmf)
        local world = runtime(repo_root, { [armor.ids[1]] = a, [armor.ids[2]] = b }, vmf,
            { surface = surface, profile_values = profile_values })
        for _, node in ipairs(world.view._build_nodes) do
            if node.setting_id and world.state[node.setting_id] == nil then
                world.state[node.setting_id] = node.default_value
            end
        end
        world.profiles.migrate_all(world.store)
        return world
    end

    for _, surface in ipairs({ "standalone", "embedded" }) do
        H.test("CRT #221 " .. surface .. " sibling reconciliation rejection precedes every write", function()
            local world = complete_world(false, true, surface)
            local live, writes, reject = true, 0, true
            local other = {
                get = function() return live end,
                set = function(_, _, value) live, writes = value, writes + 1 end,
                on_settings_batch_changed = function() end,
                mod_tweaker_settings_owner = { version = 1, capture = function() end,
                    prepare = function(_, context)
                        if reject and context.kind == "reconcile" then error("planted sibling rejection") end
                    end },
            }
            world.category._owners = { ensure_other = { mod_id = "other", mod_obj = other } }
            world.category._owner_mod_ids = { "crt", "other" }
            world.view._build_nodes[#world.view._build_nodes + 1] = {
                setting_id = "ensure_other", type = "checkbox", default_value = false,
            }
            world.mod:set(armor.master_id, true, true)
            local values = assert(world.view:_profile_snapshot(world.category, false))
            values[world.profiles.member_key("crt", armor.master_id)] = nil
            values[world.profiles.member_key("other", "ensure_other")] = nil
            values[world.profiles.OWNER_STATE_KEY] = nil
            world.profile_values[world.profiles.slot_key("crt", 1)] = values
            world.profile_values["mt_profile_schema::ct_trial_cost_absolute"] = nil
            local before, bookkeeping = world.calls.writes, world.calls.profile_writes
            H.equal(world.view:_profile_ensure(world.category), false)
            H.equal(world.calls.writes, before)
            H.equal(world.calls.profile_writes, bookkeeping)
            H.equal(writes, 0)
            H.equal(world.state[armor.master_id], true)
            H.equal(world.state[armor.snapshot_id], true)
            H.equal(world.view._profile_ready["crt:1"], nil)
            reject = false
            H.equal(world.view:_profile_ensure(world.category), true)
            H.equal(writes, 1)
            H.equal(live, false)
            H.equal(world.state[armor.ids[1]], true)
            H.equal(world.state[armor.ids[2]], true)
        end)

        H.test("CRT #221 " .. surface .. " missing master does not normalize absent raw leaf storage", function()
            local world = complete_world(false, true, surface)
            local values = assert(world.view:_profile_snapshot(world.category, false))
            values[world.profiles.member_key("crt", armor.master_id)] = nil
            values[world.profiles.OWNER_STATE_KEY] = nil
            world.profile_values[world.profiles.slot_key("crt", 1)] = values
            world.state[armor.ids[1]] = nil -- native policy treats absence as false; do not persist it incidentally
            local writes = world.calls.writes
            H.equal(world.view:_profile_ensure(world.category), true)
            H.equal(world.state[armor.ids[1]], nil)
            H.equal(world.state[armor.ids[2]], true)
            H.equal(world.calls.writes, writes + 1, "only the absent held marker is normalized")
        end)

        H.test("CRT #221 " .. surface .. " reconciliation preparation rejects before migration", function()
            local world = complete_world(false, true, surface)
            local values = assert(world.view:_profile_snapshot(world.category, false))
            values[world.profiles.member_key("crt", armor.ids[1])] = nil
            world.profile_values[world.profiles.slot_key("crt", 1)] = values
            world.profile_values["mt_profile_schema::ct_trial_cost_absolute"] = nil
            local api, prepared = world.mod.mod_tweaker_settings_owner, 0
            local original = api.prepare
            api.prepare = function(pending, context)
                if context.kind == "reconcile" then
                    prepared = prepared + 1
                    error("planted reconciliation rejection")
                end
                return original(pending, context)
            end
            local writes, bookkeeping = world.calls.writes, world.calls.profile_writes
            H.equal(world.view:_profile_ensure(world.category), false)
            H.equal(prepared, 1)
            H.equal(world.calls.writes, writes)
            H.equal(world.calls.profile_writes, bookkeeping, "prepare rejection must precede schema writes")
            H.equal(world.view._profile_ready["crt:1"], nil)
            api.prepare = original
            H.equal(world.view:_profile_ensure(world.category), true)
        end)

        H.test("CRT #221 " .. surface .. " missing legacy master never restores existing leaves", function()
            for _, a in ipairs({ false, true }) do
                for _, b in ipairs({ false, true }) do
                    for _, stored_differs in ipairs({ false, true }) do
                        local world = complete_world(a, b, surface)
                        world.mod:set(armor.master_id, true, true)
                        local values = assert(world.view:_profile_snapshot(world.category, false))
                        local akey = world.profiles.member_key("crt", armor.ids[1])
                        local bkey = world.profiles.member_key("crt", armor.ids[2])
                        local masterkey = world.profiles.member_key("crt", armor.master_id)
                        values[masterkey], values[world.profiles.OWNER_STATE_KEY] = nil, nil
                        if stored_differs then values[akey], values[bkey] = false, false end
                        world.profile_values[world.profiles.slot_key("crt", 1)] = values
                        local writes, bookkeeping = world.calls.writes, world.calls.profile_writes
                        local old_a = world.state[armor.snapshot_prefix .. armor.ids[1]]
                        local old_b = world.state[armor.snapshot_prefix .. armor.ids[2]]
                        H.equal(world.view:_profile_ensure(world.category), true)
                        H.equal(world.state[armor.ids[1]], true, "missing master is not a user OFF command")
                        H.equal(world.state[armor.ids[2]], true, "do not restore the held preimage")
                        H.equal(world.state[armor.master_id], false)
                        H.equal(world.state[armor.snapshot_id], false, "legacy profile becomes custom")
                        H.equal(world.state[armor.snapshot_prefix .. armor.ids[1]], old_a)
                        H.equal(world.state[armor.snapshot_prefix .. armor.ids[2]], old_b)
                        H.equal(world.calls.writes, writes + 2, "only the master and ownership marker change")
                        H.equal(world.calls.profile_writes, bookkeeping + 1)
                        local stored = world.profiles.load(world.store, "crt", 1)
                        H.equal(stored[akey], values[akey])
                        H.equal(stored[bkey], values[bkey])
                        H.equal(stored[masterkey], false)
                        H.equal(stored[world.profiles.OWNER_STATE_KEY], nil, "no fabricated preimage")
                        world.mod:set(armor.master_id, false, true)
                        H.equal(world.state[armor.ids[1]], true, "a later OFF cannot reuse the retired preimage")
                        H.equal(world.state[armor.ids[2]], true)
                    end
                end
            end
        end)

        H.test("CRT #221 " .. surface .. " missing master retry never restores held leaves", function()
            for _, failed_id in ipairs({ armor.master_id, armor.snapshot_id }) do
                local world = complete_world(false, false, surface)
                world.mod:set(armor.master_id, true, true)
                local values = assert(world.view:_profile_snapshot(world.category, false))
                local masterkey = world.profiles.member_key("crt", armor.master_id)
                values[masterkey], values[world.profiles.OWNER_STATE_KEY] = nil, nil
                world.profile_values[world.profiles.slot_key("crt", 1)] = values
                local setter = world.mod.set
                world.mod.set = function(self, id, value, notify)
                    if id == failed_id then error("planted missing-master write failure") end
                    return setter(self, id, value, notify)
                end
                H.equal(world.view:_profile_ensure(world.category), false)
                H.equal(world.state[armor.ids[1]], true)
                H.equal(world.state[armor.ids[2]], true)
                H.equal(world.view._profile_ready["crt:1"], nil)
                H.equal(world.profiles.load(world.store, "crt", 1)[masterkey], nil)
                world.mod.set = setter
                H.equal(world.view:_profile_ensure(world.category), true)
                H.equal(world.state[armor.ids[1]], true)
                H.equal(world.state[armor.ids[2]], true)
                H.equal(world.state[armor.master_id], false)
                H.equal(world.state[armor.snapshot_id], false)
            end
        end)

        H.test("CRT #221 " .. surface .. " ensure rejects active foreign metadata before writes", function()
            local world = complete_world(false, true, surface)
            local values = assert(world.view:_profile_snapshot(world.category, false))
            values[world.profiles.OWNER_STATE_KEY].owners.crt.cluster = "foreign"
            values[world.profiles.member_key("crt", armor.ids[1])] = nil
            world.profile_values[world.profiles.slot_key("crt", 1)] = values
            world.state[armor.ids[1]] = true
            local writes, bookkeeping = world.calls.writes, world.calls.profile_writes
            local ok, err = pcall(world.view._profile_ensure, world.view, world.category)
            H.truthy(ok, tostring(err))
            H.equal(world.calls.writes, writes, "ensure must validate before applying a missing member")
            H.equal(world.calls.profile_writes, bookkeeping, "corrupt active metadata cannot be persisted")
            H.equal(world.state[armor.ids[1]], true)
            H.equal(world.view._profile_ready["crt:1"], nil, "rejected ensure remains retryable")
        end)

        H.test("CRT #221 " .. surface .. " actual capture replay restart OFF preserves all preimages", function()
            for _, a in ipairs({ false, true }) do
                for _, b in ipairs({ false, true }) do
                    local world = complete_world(a, b, surface)
                    world.mod:set(armor.master_id, true, true)
                    world.view:_switch_profile(2)
                    H.equal(world.profiles.get_active(world.store, "crt"), 2)
                    H.equal(world.state[armor.ids[1]], false, "unused profile uses false default, not live true")
                    H.equal(world.state[armor.ids[2]], false)
                    world.view:_switch_profile(1)
                    H.equal(world.profiles.get_active(world.store, "crt"), 1)
                    H.equal(world.state[armor.master_id], true)
                    H.equal(world.state[armor.snapshot_id], true)
                    local restarted = runtime(repo_root, world.state, nil,
                        { surface = surface, profile_values = world.profile_values })
                    restarted.mod:set(armor.master_id, false, true)
                    H.equal(restarted.state[armor.ids[1]], a)
                    H.equal(restarted.state[armor.ids[2]], b)
                    H.equal(restarted.state[armor.snapshot_id], false)
                end
            end
        end)

        H.test("CRT #221 " .. surface .. " legacy replay preserves explicit children as custom", function()
            local world = complete_world(false, true, surface)
            world.mod:set(armor.master_id, true, true)
            local legacy = assert(world.view:_profile_snapshot(world.category, false))
            legacy[world.profiles.OWNER_STATE_KEY] = nil
            legacy[world.profiles.member_key("crt", armor.ids[1])] = false
            world.profiles.save(world.store, "crt", 2, legacy)
            world.view:_switch_profile(2)
            H.equal(world.profiles.get_active(world.store, "crt"), 2)
            H.equal(world.state[armor.master_id], false)
            H.equal(world.state[armor.snapshot_id], false)
            H.equal(world.state[armor.ids[1]], false)
            H.equal(world.state[armor.ids[2]], true)
            world.mod:set(armor.master_id, false, true)
            H.equal(world.state[armor.ids[1]], false)
        end)

        H.test("CRT #221 " .. surface .. " rejects malformed owner metadata before any writes", function()
            local world = complete_world(false, true, surface)
            local values = assert(world.view:_profile_snapshot(world.category, false))
            values[world.profiles.OWNER_STATE_KEY].owners.crt.saved[armor.ids[1]] = "false"
            world.profiles.save(world.store, "crt", 2, values)
            local writes, bookkeeping = world.calls.writes, world.calls.profile_writes
            world.view:_switch_profile(2)
            H.equal(world.calls.writes, writes)
            H.equal(world.calls.profile_writes, bookkeeping)
            H.equal(world.profiles.get_active(world.store, "crt"), 1)
            H.equal(world.view._profile_replay, nil)
        end)

        H.test("CRT #221 " .. surface .. " failed replay retains exact context and retries once", function()
            local world = complete_world(false, true, surface)
            world.mod:set(armor.master_id, true, true)
            world.view:_switch_profile(2)
            local setter = world.mod.set
            local fail = true
            world.mod.set = function(self, id, value, notify)
                if fail and id == armor.ids[1] then error("planted armor persistence failure") end
                return setter(self, id, value, notify)
            end
            world.view:_switch_profile(1)
            H.truthy(world.view._profile_replay, "failed replay must retain pre-write plan")
            H.equal(world.calls.profile_events, 1, "only prior successful switch emitted")
            H.truthy(next(world.view._pending.crt))
            H.equal(world.profiles.get_active(world.store, "crt"), 2, "failed target is not active")
            fail = false
            world.view:apply_pending(world.category)
            H.equal(world.view._profile_replay, nil)
            H.equal(world.profiles.get_active(world.store, "crt"), 1)
            H.equal(world.calls.profile_events, 2, "successful retry emits exactly once after commit")
            world.mod:set(armor.master_id, false, true)
            H.equal(world.state[armor.ids[1]], false)
            H.equal(world.state[armor.ids[2]], true)
        end)
    end

    H.test("CRT #221 reconciliation cannot invent ownership or borrow profile metadata", function()
        local world = complete_world(false, true, "standalone")
        for _, context in ipairs({
            { kind = "reconcile", owner_id = "crt", metadata = {} },
            { kind = "reconcile", owner_id = "crt", enabled = true },
        }) do
            local pending = { [armor.master_id] = context.enabled == true }
            local writes = world.calls.writes
            H.equal(pcall(world.mod.mod_tweaker_settings_owner.prepare, pending, context), false)
            H.equal(world.calls.writes, writes)
        end
    end)

    H.test("CRT #221 mixed explicit leaf edits override the master without affecting other owners", function()
        local world = complete_world(true, false, "standalone")
        world.view:stage_set(world.category, armor.master_id, true)
        world.view:stage_set(world.category, armor.ids[1], false)
        world.view:stage_set(world.category, "unrelated", 42)
        world.view:apply_pending(world.category)
        H.equal(world.state[armor.ids[1]], false)
        H.equal(world.state[armor.ids[2]], false)
        H.equal(world.state[armor.master_id], false)
        H.equal(world.state[armor.snapshot_id], false)
        H.equal(world.state.unrelated, 42)
        H.equal(world.calls.events, 1, "only unrelated setting uses its original callback")
        H.equal(world.calls.engines, 0)
        H.equal(world.calls.foot_knight, 0)
    end)

    local malformed_profiles = {
        { "cyclic", function(values, key) local e = values[key]; e.owners.crt.loop = e end },
        { "function", function(values, key) values[key].owners.crt.saved[armor.ids[1]] = function() end end },
        { "deep", function(values, key)
            values[key].extra = { a = { a = { a = { a = {} } } } }
        end },
        { "oversized", function(values, key)
            for i = 1, 129 do values[key].owners.crt["extra" .. i] = true end
        end },
        { "foreign owner", function(values, key) values[key].owners.intruder = {} end },
        { "foreign cluster", function(values, key) values[key].owners.crt.cluster = "tourney" end },
        { "missing false", function(values, key) values[key].owners.crt.saved[armor.ids[1]] = nil end },
        { "hidden setting", function(values)
            values["3:crt" .. armor.snapshot_prefix .. armor.ids[1]] = true
        end },
        { "held mismatch", function(values, key) values[key].owners.crt.held = true end },
        { "unknown protocol", function(_, _, world) world.mod.mod_tweaker_settings_owner.version = 2 end },
        { "unavailable protocol", function(_, _, world) world.mod.mod_tweaker_settings_owner = nil end },
        { "rebound provider", function(_, _, world)
            world.category._owners = { [armor.ids[1]] = {
                mod_id = "intruder", mod_obj = { get = function() return false end },
            } }
        end },
    }

    H.test("CRT #221 named runtime profile check executes without mutating player settings", function()
        local world = complete_world(false, true, "standalone")
        local writes = world.calls.writes
        H.equal(world.profile_check(), nil)
        H.equal(world.calls.writes, writes)
    end)

    H.test("CRT #221 completion observer cannot undo successful replay", function()
        local world = complete_world(false, true, "standalone")
        world.calls.throw_observer = true
        world.view:_switch_profile(2)
        H.equal(world.profiles.get_active(world.store, "crt"), 2)
        H.equal(world.view._profile_replay, nil)
        H.equal(world.calls.profile_events, 1)
    end)

    H.test("CRT #221 merged replay preserves an unrelated owner's batch contract", function()
        local world = complete_world(false, true, "standalone")
        local other_state, batches, notifications = false, 0, 0
        local other = {
            get = function() return other_state end,
            set = function(_, _, value, notify)
                other_state = value
                if notify then notifications = notifications + 1 end
            end,
            on_settings_batch_changed = function() batches = batches + 1 end,
        }
        world.category._owners = { other_option = { mod_id = "other", mod_obj = other } }
        world.category._owner_mod_ids = { "crt", "other" }
        world.view._build_nodes[#world.view._build_nodes + 1] = {
            setting_id = "other_option", type = "checkbox", default_value = false,
        }
        world.mod:set(armor.master_id, true, true)
        world.view:_switch_profile(2)
        world.view:_switch_profile(1)
        H.equal(batches, 2)
        H.equal(notifications, 0)
        H.equal(other_state, false)
        H.equal(world.state[armor.snapshot_id], true)
        world.mod:set(armor.master_id, false, true)
        H.equal(world.state[armor.ids[1]], false)
        H.equal(world.state[armor.ids[2]], true)
    end)
    for _, item in ipairs(malformed_profiles) do
        H.test("CRT #221 actual profile rejects " .. item[1] .. " before any writer", function()
            local world = complete_world(false, true, "standalone")
            local values = assert(world.view:_profile_snapshot(world.category, false))
            item[2](values, world.profiles.OWNER_STATE_KEY, world)
            -- Deliberately plant corrupt persisted data without a fixture clone
            -- rejecting/normalizing it on behalf of the production reader.
            world.profile_values[world.profiles.slot_key("crt", 2)] = values
            world.profile_values["mt_profile_schema::ct_trial_cost_absolute"] = nil
            local writes, bookkeeping = world.calls.writes, world.calls.profile_writes
            world.view:_switch_profile(2)
            H.equal(world.calls.writes, writes)
            H.equal(world.calls.profile_writes, bookkeeping)
            H.equal(world.profiles.get_active(world.store, "crt"), 1)
        end)
        for _, surface in ipairs({ "standalone", "embedded" }) do
            H.test("CRT #221 " .. surface .. " ensure rejects " .. item[1] .. " before migration", function()
                for _, missing in ipairs({ false, true }) do
                    local world = complete_world(false, true, surface)
                    local values = assert(world.view:_profile_snapshot(world.category, false))
                    item[2](values, world.profiles.OWNER_STATE_KEY, world)
                    if missing then values[world.profiles.member_key("crt", armor.ids[1])] = nil end
                    world.profile_values[world.profiles.slot_key("crt", 1)] = values
                    world.profile_values["mt_profile_schema::ct_trial_cost_absolute"] = nil
                    world.state[armor.ids[1]] = true
                    world.view:stage_set(world.category, armor.ids[2], false)
                    local draft = world.view._pending.crt
                    local writes, bookkeeping = world.calls.writes, world.calls.profile_writes
                    local ok, result = pcall(world.view._profile_ensure, world.view, world.category)
                    H.truthy(ok, tostring(result))
                    H.equal(result, false)
                    H.equal(world.calls.writes, writes)
                    H.equal(world.calls.profile_writes, bookkeeping)
                    H.equal(world.profile_values[world.profiles.slot_key("crt", 1)], values)
                    H.equal(world.profile_values["mt_profile_schema::ct_trial_cost_absolute"], nil)
                    H.equal(world.view._pending.crt, draft)
                    H.equal(draft[armor.ids[2]], false)
                    H.equal(world.view._profile_ready["crt:1"], nil)
                    H.equal(world.state[armor.ids[1]], true)
                end
            end)
        end
    end

    for _, surface in ipairs({ "standalone", "embedded" }) do
        H.test("CRT #221 " .. surface .. " automatic ensure applies only additions in modern and legacy profiles", function()
            for _, spec in ipairs({ { false, false }, { false, true }, { true, false }, { true, true } }) do
                local legacy, missing = spec[1], spec[2]
                local world = complete_world(false, true, surface)
                world.view._build_nodes[#world.view._build_nodes + 1] = {
                    setting_id = "ensure_control", type = "checkbox", default_value = false,
                }
                world.state.ensure_control = true
                local values = assert(world.view:_profile_snapshot(world.category, false))
                local key = world.profiles.member_key("crt", "ensure_control")
                if missing then values[key] = nil end
                if legacy then values[world.profiles.OWNER_STATE_KEY] = nil end
                world.profile_values[world.profiles.slot_key("crt", 1)] = values
                -- Existing live choices deliberately differ from the active saved profile.
                world.mod:set(armor.master_id, true, true)
                local pre_a = world.state[armor.snapshot_prefix .. armor.ids[1]]
                local pre_b = world.state[armor.snapshot_prefix .. armor.ids[2]]
                local writes, bookkeeping = world.calls.writes, world.calls.profile_writes
                H.equal(world.view:_profile_ensure(world.category), true)
                local additional = missing and 1 or 0
                H.equal(world.calls.writes, writes + additional, "only the unrelated missing member is written")
                H.equal(world.calls.profile_writes, bookkeeping + additional)
                H.equal(world.state.ensure_control, not missing)
                H.equal(world.state[armor.master_id], true, "do not replay a stored false master")
                H.equal(world.state[armor.snapshot_id], true)
                H.equal(world.state[armor.snapshot_prefix .. armor.ids[1]], pre_a)
                H.equal(world.state[armor.snapshot_prefix .. armor.ids[2]], pre_b)
                local stored = world.profiles.load(world.store, "crt", 1)
                H.equal(stored[key], not missing)
                H.deep_equal(stored[world.profiles.OWNER_STATE_KEY], values[world.profiles.OWNER_STATE_KEY])
                H.equal(world.view:_profile_ensure(world.category), true)
                H.equal(world.calls.writes, writes + additional, "ready initialization is idempotent")
                world.mod:set(armor.master_id, false, true)
                H.equal(world.state[armor.ids[1]], false)
                H.equal(world.state[armor.ids[2]], true)
            end
        end)

        H.test("CRT #221 " .. surface .. " ensure preserves an unrelated provider's batch contract", function()
            local world = complete_world(false, true, surface)
            local live, writes, callbacks = true, 0, 0
            local provider = {
                get = function() return live end,
                set = function(_, id, value, notify)
                    H.equal(id, "ensure_other")
                    H.equal(notify, false)
                    live, writes = value, writes + 1
                end,
                on_settings_batch_changed = function(ids)
                    H.deep_equal(ids, { "ensure_other" })
                    callbacks = callbacks + 1
                end,
            }
            world.category._owners = { ensure_other = { mod_id = "other", mod_obj = provider } }
            world.category._owner_mod_ids = { "crt", "other" }
            world.view._build_nodes[#world.view._build_nodes + 1] = {
                setting_id = "ensure_other", type = "checkbox", default_value = false,
            }
            local values = assert(world.view:_profile_snapshot(world.category, false))
            values[world.profiles.member_key("other", "ensure_other")] = nil
            world.profile_values[world.profiles.slot_key("crt", 1)] = values
            local crt_writes = world.calls.writes
            H.equal(world.view:_profile_ensure(world.category), true)
            H.equal(writes, 1)
            H.equal(callbacks, 1)
            H.equal(live, false)
            H.equal(world.calls.writes, crt_writes, "validating CRT's complete profile must not commit it")
        end)

        H.test("CRT #221 " .. surface .. " ensure retries migration commit and persistence failures", function()
            for _, edge in ipairs({ "migration", "commit", "persistence" }) do
                local world = complete_world(false, true, surface)
                local values = assert(world.view:_profile_snapshot(world.category, false))
                local key = world.profiles.member_key("crt", armor.ids[1])
                values[key] = nil
                world.profile_values[world.profiles.slot_key("crt", 1)] = values
                world.state[armor.ids[1]] = true
                if edge == "migration" then world.profile_values["mt_profile_schema::ct_trial_cost_absolute"] = nil end
                local setter, save = world.mod.set, world.store.set
                if edge == "commit" then world.mod.set = function() error("planted ensure commit") end
                else world.store.set = function() error("planted ensure " .. edge) end end
                local writes = world.calls.writes
                H.equal(world.view:_profile_ensure(world.category), false, edge)
                H.equal(world.view._profile_ready["crt:1"], nil)
                H.equal(world.profile_values[world.profiles.slot_key("crt", 1)], values)
                H.equal(world.profiles.get_active(world.store, "crt"), 1)
                if edge ~= "persistence" then H.equal(world.calls.writes, writes) end
                world.mod.set, world.store.set = setter, save
                H.equal(world.view:_profile_ensure(world.category), true)
                H.equal(world.view._profile_ready["crt:1"], true)
                H.equal(world.profiles.load(world.store, "crt", 1)[key], false)
                H.equal(world.state[armor.ids[1]], false)
                H.equal(world.state[armor.ids[2]], true)
            end
        end)
    end

    H.test("CRT #221 failed replay cannot execute a stale prepared draft", function()
        local world = complete_world(false, true, "standalone")
        world.mod:set(armor.master_id, true, true)
        world.view:_switch_profile(2)
        local setter = world.mod.set
        world.mod.set = function() error("planted failure") end
        world.view:_switch_profile(1)
        world.mod.set = setter
        world.view:stage_set(world.category, armor.ids[1], false)
        local writes = world.calls.writes
        world.view:apply_pending(world.category)
        H.equal(world.calls.writes, writes, "changed input cannot borrow the old prepared plan")
        H.truthy(world.view._profile_replay)
        H.equal(world.view._pending.crt[armor.ids[1]], false)
        world.view:stage_set(world.category, armor.ids[1], true)
        world.view:apply_pending(world.category)
        H.equal(world.view._profile_replay, nil)
    end)

    H.test("CRT #221 armor commit retries every partial write without losing preimage", function()
        for fail_at = 1, 6 do
            local world = complete_world(false, false, "standalone")
            world.view:stage_set(world.category, armor.master_id, true)
            local setter, count = world.mod.set, 0
            world.mod.set = function(self, id, value, notify)
                count = count + 1
                if count == fail_at then error("planted write " .. fail_at) end
                return setter(self, id, value, notify)
            end
            world.view:apply_pending(world.category)
            world.mod.set = setter
            world.view:apply_pending(world.category)
            world.mod:set(armor.master_id, false, true)
            H.equal(world.state[armor.ids[1]], false)
            H.equal(world.state[armor.ids[2]], false)
        end
    end)

    local vmf_path = "C:/Users/danjo/source/repos/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua"
    local vmf_file = io.open(vmf_path, "rb")
    if vmf_file then vmf_file:close() end
    H.test_if(vmf_file ~= nil, "CRT #221 optional actual VMF persistence/events profile replay", function()
        for _, surface in ipairs({ "standalone", "embedded" }) do
            for _, a in ipairs({ false, true }) do
                for _, b in ipairs({ false, true }) do
                    local world = complete_world(a, b, surface, nil, vmf_path)
                    world.mod:set(armor.master_id, true, true)
                    world.view:_switch_profile(2)
                    world.view:_switch_profile(1)
                    local restarted = runtime(repo_root, world.state, vmf_path,
                        { surface = surface, profile_values = world.profile_values })
                    restarted.mod:set(armor.master_id, false, true)
                    H.equal(restarted.state[armor.ids[1]], a)
                    H.equal(restarted.state[armor.ids[2]], b)
                end
            end
        end
    end, "optional local VMF source unavailable; repository-owned behavior cases remain mandatory")

    H.test("CRT #221 actual master callback leaves #445 bounded reconciliation intact", function()
        local world = runtime(repo_root, { [armor.ids[1]] = false, [armor.ids[2]] = true })
        world.mod:set(armor.master_id, true, true)
        for _, master in ipairs({ module.MASTER_ENSRICK, module.MASTER_TOURNEY, module.MASTER_ALL }) do
            local engines, foot_knight = world.calls.engines, world.calls.foot_knight
            world.mod:set(master, true, true)
            H.equal(world.calls.engines, engines + 1)
            H.equal(world.calls.foot_knight, foot_knight + 1)
            H.equal(world.state[armor.snapshot_id], true, "family presets cannot release armor ownership")
        end
        world.mod:set(armor.master_id, false, true)
        H.equal(world.state[armor.ids[1]], false)
        H.equal(world.state[armor.ids[2]], true)
    end)

    H.test("CRT #221 armor family is an explicit-list cluster, not an authorship family", function()
        H.equal(armor.master_id, "rework_master_armor")
        H.equal(module.MASTER_ARMOR, "rework_master_armor")
        H.deep_equal(armor.ids, { "armor_gromril_ignore_chip", "armor_specials_dont_break_gromril" })
        H.equal(armor.ids, module.ARMOR_IDS, "FAMILIES.armor.ids must be the single ARMOR_IDS owner")
        H.equal(armor.label_prefix, nil, "cluster masters carry no authorship prefix")
        H.equal(armor.setting_prefix, nil)
        H.equal(module.family_for_setting("armor_gromril_ignore_chip"), nil,
            "armor leaves are not rework family members")
        H.equal(module.cluster_for_setting("armor_gromril_ignore_chip"), "armor")
        H.equal(module.cluster_for_setting("armor_specials_dont_break_gromril"), "armor")
        H.equal(module.cluster_for_setting("rework_master_armor"), nil)
        H.equal(module.cluster_for_master("rework_master_armor"), "armor")
        H.equal(module.cluster_for_master("rework_master_ensrick"), nil)
        H.equal(policy:cluster_for_leaf("armor_gromril_ignore_chip"), "armor")
        H.equal(policy:cluster_for_leaf("rework_a"), nil)
        H.equal(policy:cluster_for_master("rework_master_armor"), "armor")
        H.equal(policy:is_member("armor_gromril_ignore_chip"), nil,
            "authorship members must not include cluster leaves")
        H.deep_equal(policy.cluster_ids, {
            "armor_gromril_ignore_chip",
            "armor_specials_dont_break_gromril",
            "rework_master_armor",
            saved("armor_gromril_ignore_chip"),
            saved("armor_specials_dont_break_gromril"),
            "rework_master_armor_snapshot",
        })
        for _, id in ipairs(policy.cluster_ids) do
            H.equal(module.family_for_setting(id), nil, id .. " must not decorate as a rework leaf")
        end
    end)

    H.test("CRT #221 armor master ON snapshots exact leaf values and enables both leaves", function()
        local changes = policy:plan("armor", true, {
            armor_gromril_ignore_chip = false,
            armor_specials_dont_break_gromril = true,
        })
        local got = change_map(changes)
        H.equal(#changes, 4, "one leaf, the master, the snapshot flag, and one saved value")
        H.equal(got.armor_gromril_ignore_chip, true)
        H.equal(got.armor_specials_dont_break_gromril, nil, "already-on leaf is not rewritten")
        H.equal(got[armor.master_id], true)
        H.equal(got[armor.snapshot_id], true)
        H.equal(got[saved("armor_specials_dont_break_gromril")], true)
        H.equal(got[saved("armor_gromril_ignore_chip")], nil, "saved false equals the default and is not written")
        H.equal(got[module.MASTER_ENSRICK], nil, "cluster masters never touch the family radio")
        H.equal(got[module.MASTER_ALL], nil)
        H.equal(got.rework_a, nil)
        H.equal(got.trn_a, nil)
    end)

    H.test("CRT #221 armor master OFF restores the exact snapshot once and releases it", function()
        local state = {
            armor_gromril_ignore_chip = false,
            armor_specials_dont_break_gromril = true,
            rework_a = true,
        }
        local function apply(changes)
            for _, change in ipairs(changes) do state[change.id] = change.value end
        end
        apply(policy:plan("armor", true, state))
        H.equal(state.armor_gromril_ignore_chip, true)
        H.equal(state.armor_specials_dont_break_gromril, true)
        H.equal(state[armor.snapshot_id], true)

        local off = policy:plan("armor", false, state)
        local got = change_map(off)
        H.equal(got.armor_gromril_ignore_chip, false, "restored to the pre-toggle value")
        H.equal(got.armor_specials_dont_break_gromril, nil, "leaf already at its saved value is not rewritten")
        H.equal(got[armor.master_id], false)
        H.equal(got[armor.snapshot_id], false, "snapshot released")
        apply(off)
        H.equal(state.armor_gromril_ignore_chip, false)
        H.equal(state.armor_specials_dont_break_gromril, true)
        H.equal(state.rework_a, true, "unrelated family leaf untouched across the round trip")

        -- A second OFF with no held snapshot is a no-op.
        H.equal(#policy:plan("armor", false, state), 0)
    end)

    H.test("CRT #221 armor master OFF without a snapshot never rewrites saved leaves", function()
        local changes = change_map(policy:plan("armor", false, {
            armor_gromril_ignore_chip = true,
            armor_specials_dont_break_gromril = false,
            [armor.master_id] = true,
        }))
        H.equal(changes.armor_gromril_ignore_chip, nil, "hand-picked leaf preserved")
        H.equal(changes.armor_specials_dont_break_gromril, nil)
        H.equal(changes[armor.master_id], false, "only the master flag clears")
        H.equal(changes[armor.snapshot_id], nil)
    end)

    H.test("CRT #221 armor leaf hand edit closes the transaction without writing leaves", function()
        local changes = change_map(policy:plan_cluster_custom("armor", {
            armor_gromril_ignore_chip = true,
            armor_specials_dont_break_gromril = false,
            [armor.master_id] = true,
            [armor.snapshot_id] = true,
            [saved("armor_gromril_ignore_chip")] = false,
        }))
        H.equal(changes[armor.master_id], false)
        H.equal(changes[armor.snapshot_id], false)
        H.equal(changes.armor_gromril_ignore_chip, nil)
        H.equal(changes.armor_specials_dont_break_gromril, nil)
        H.equal(changes[saved("armor_gromril_ignore_chip")], nil, "stale saved values are inert, not rewritten")
        H.equal(#policy:plan_cluster_custom("armor", {}), 0, "closed transaction is a no-op")
        H.equal(#policy:plan_cluster_custom("ensrick", { [module.MASTER_ENSRICK] = true }), 0,
            "authorship families are not clusters")
    end)

    H.test("CRT #221 armor master runs as one bounded transaction with no engine reconcile", function()
        local settings = { armor_gromril_ignore_chip = false, armor_specials_dont_break_gromril = false }
        local batch = false
        local writer_calls, callback_calls, nested_applies = 0, 0, 0
        local reconciles, live_reconciles = 0, 0
        local function write_changes(changes)
            writer_calls = writer_calls + 1
            batch = true
            for _, change in ipairs(changes) do
                settings[change.id] = change.value
                callback_calls = callback_calls + 1
                if not batch then nested_applies = nested_applies + 1 end
            end
            batch = false
            return true
        end
        local applied, changes = module.apply_bounded_master(policy, "armor", true, settings,
            write_changes,
            function() reconciles = reconciles + 1 end,
            function() live_reconciles = live_reconciles + 1 end)
        H.equal(applied, true)
        H.equal(writer_calls, 1)
        H.equal(callback_calls, #changes)
        H.equal(nested_applies, 0)
        H.equal(reconciles, 1, "the caller supplies a no-op reconcile; it still runs exactly once")
        H.equal(live_reconciles, 1)
        H.equal(settings.armor_gromril_ignore_chip, true)
        H.equal(settings.armor_specials_dont_break_gromril, true)

        local failed, failed_changes = module.apply_bounded_master(policy, "armor", false, settings,
            function() return false end,
            function() reconciles = reconciles + 1 end,
            function() live_reconciles = live_reconciles + 1 end)
        H.equal(failed, false, "a failed write aborts before any reconcile")
        H.truthy(#failed_changes > 0)
        H.equal(reconciles, 1)
        H.equal(live_reconciles, 1)
    end)
end
