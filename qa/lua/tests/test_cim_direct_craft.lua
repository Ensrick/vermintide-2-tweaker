return function(H, repo_root)
    local fixture = assert(loadfile(repo_root
        .. "/qa/lua/tests/_cim_temper_fixture.lua"))()(H, repo_root)
    local root = fixture.root
    local install = fixture.install
    local install_direct_owner = fixture.install_direct_owner
    local contract = fixture.contract
    local read = fixture.read
    local deep_clone = fixture.deep_clone
    local ownership_token = fixture.ownership_token
    local make_mod = fixture.make_mod
    local context = fixture.context
    local with_craft_surface_globals = fixture.with_craft_surface_globals
    local make_craft_surface_mod = fixture.make_craft_surface_mod
    local cwv_seed_fixture = fixture.cwv_seed_fixture

    H.test("CIM #1141 direct craft entry paths share the guarded commit owner", function()
        local mod = make_mod()
        local validations = 0
        local owner = install_direct_owner({
            mod = mod,
            contract = {
                validate_temper_owned_instance = function(
                        item, backend_id, record, master)
                    validations = validations + 1
                    return item == "item" and backend_id == "bid"
                        and record == "record" and master == "master",
                        "identity_rejected"
                end,
            },
        })
        local ok, reason = owner.commit({}, "bid", {})
        H.equal(ok, false)
        H.equal(reason, "transaction_unavailable")

        local seen
        mod._cim_temper_runtime_state = {
            commit_craft = function(data, backend_id, evidence)
                seen = { data, backend_id, evidence }
                return true, "registered"
            end,
        }
        local data, evidence = {}, {}
        ok, reason = owner.commit(data, "bid", evidence)
        H.equal(ok, true)
        H.equal(reason, "registered")
        H.deep_equal(seen, { data, "bid", evidence })

        mod._cim_temper_runtime_state.commit_craft = function()
            error("commit exploded")
        end
        ok, reason = owner.commit({}, "bid", {})
        H.equal(ok, false)
        H.truthy(reason:find("transaction_exception:", 1, true))
        H.truthy(reason:find("commit exploded", 1, true))

        ok, reason = owner.validate_saved_occupant(
            "item", "bid", "record", "master")
        H.equal(ok, true)
        H.equal(reason, nil)
        H.equal(validations, 1)
        ok, reason = owner.validate_saved_occupant(
            "foreign", "bid", "record", "master")
        H.equal(ok, false)
        H.equal(reason, "identity_rejected")
    end)

    H.test("CIM #1141 standard forge uses canonical commit and token rollback", function()
        local mod = make_craft_surface_mod()
        local injected, registered, rollbacks, rollback_refreshes = 0, 0, 0, 0
        local payloads, evidence_seen = {}, {}
        install(context(mod, {
            inject_item = function(data, backend_id)
                injected = injected + 1
                payloads[#payloads + 1] = data
                return true, nil, ownership_token(backend_id, data.item_key),
                    function()
                        rollbacks = rollbacks + 1
                        return true
                    end
            end,
            register_craft = function(_, data)
                registered = registered + 1
                if registered == 2 then return false, "save rejected" end
                return true, data
            end,
            refresh_backend = function()
                rollback_refreshes = rollback_refreshes + 1
                return true
            end,
            note_craft = function() end,
            print_line = function(_, _, source_backend_id, raw_item_key)
                evidence_seen[#evidence_seen + 1] = {
                    source_backend_id, raw_item_key,
                }
            end,
        }))

        local master = {
            es_sword = {
                key = "es_sword", slot_type = "melee", item_type = "weapon",
                rarity = "default", can_wield = { "es_mercenary" },
            },
        }
        with_craft_surface_globals(mod, master, nil, function()
            assert(loadfile(root .. "standard_forge.lua"))()
            mod._cim_craft_via_synth({ melee = true }, "weapon")
            mod._cim_craft_via_synth({ melee = true }, "weapon")
        end)

        H.equal(injected, 2)
        H.equal(registered, 2)
        H.equal(rollbacks, 1)
        H.equal(rollback_refreshes, 1)
        H.equal(payloads[1].item_key, "es_sword")
        H.equal(payloads[1].career_name, "es_mercenary")
        H.equal(payloads[1].via_mirror, true)
        H.equal(evidence_seen[1][2], "es_sword")
        local saw_failure = false
        for _, message in ipairs(mod.messages) do
            if message:find("craft transaction FAILED", 1, true)
                    and message:find("save rejected", 1, true) then
                saw_failure = true
            end
        end
        H.truthy(saw_failure, "standard forge must surface transaction rejection")
    end)

    H.test("CIM #1141 standard forge preserves both real CWV seed bands", function()
        for _, suffix in ipairs({ "000", "001" }) do
            local fixture = cwv_seed_fixture(suffix)
            local mod = make_craft_surface_mod()
            mod._cim_test_items_by_id = {
                [fixture.backend_id] = fixture.live,
            }
            local commits, evidence = {}, {}
            install(context(mod, {
                get_cwv_seed_identity_provider = function()
                    return fixture.provider
                end,
                inject_item = function(data, backend_id)
                    commits[#commits + 1] = data.item_key
                    return true, nil, ownership_token(
                        backend_id, data.item_key)
                end,
                register_craft = function(_, data) return true, data end,
                note_craft = function() end,
                print_line = function(_, _, source_backend_id, raw_item_key)
                    evidence[#evidence + 1] = {
                        source_backend_id, raw_item_key,
                    }
                end,
            }))

            with_craft_surface_globals(mod, fixture.master, nil, function()
                assert(loadfile(root .. "standard_forge.lua"))()
                mod._cim_standard_forge_active = true
                local crafting = {
                    _last_id = 0,
                    _craft_requests = {},
                    _backend_mirror = {},
                    _get_valid_recipe = function()
                        return { name = "craft_weapon" }, {
                            fixture.backend_id,
                        }
                    end,
                }
                mod.hooks.craft(
                    function() error("custom forge must not call vanilla") end,
                    crafting, "es_mercenary", { fixture.backend_id },
                    "craft_weapon")
            end)

            H.deep_equal(commits, { fixture.item_key }, suffix)
            H.equal(evidence[1][1], fixture.backend_id, suffix)
            H.equal(evidence[1][2], fixture.donor_key, suffix)
        end
    end)

    H.test("CIM #1141 installed craft hook completes despite post-commit observer exceptions", function()
        for _, fault in ipairs({
                "interface", "item_reader", "echo", "probe", "trace",
                "hostile_error", "failure_logger",
            }) do
            local fixture = cwv_seed_fixture("001")
            local mod = make_craft_surface_mod()
            mod._cim_test_items_by_id = { [fixture.backend_id] = fixture.live }
            local injected, persisted, noted, rollback = 0, 0, 0, 0
            local live, saved = {}, {}
            install(context(mod, {
                get_cwv_seed_identity_provider = function() return fixture.provider end,
                inject_item = function(data, backend_id)
                    injected = injected + 1
                    live[backend_id] = data
                    return true, nil, ownership_token(backend_id, data.item_key),
                        function() rollback = rollback + 1; return true end
                end,
                register_craft = function(backend_id, data)
                    persisted = persisted + 1
                    saved[backend_id] = data
                    return true, data
                end,
                note_craft = function() noted = noted + 1 end,
            }))
            with_craft_surface_globals(mod, fixture.master, nil, function(surface)
                assert(loadfile(root .. "standard_forge.lua"))()
                mod._cim_standard_forge_active = true
                local native_get = Managers.backend.get_interface
                local sources_read, observer_hits, receipts = 0, 0, 0
                Managers.backend.get_interface = function(self, name)
                    if name == "items" and persisted > 0 then
                        if fault == "interface" or fault == "failure_logger" then
                            observer_hits = observer_hits + 1
                            error("postcommit interface failure")
                        elseif fault == "hostile_error" then
                            observer_hits = observer_hits + 1
                            error(setmetatable({}, { __tostring = function()
                                error("error object cannot be rendered")
                            end }))
                        end
                    end
                    local items = native_get(self, name)
                    if name ~= "items" then return items end
                    return { get_item_from_id = function(_, backend_id)
                        if persisted > 0 and fault == "item_reader" then
                            observer_hits = observer_hits + 1
                            error("postcommit item read failure")
                        end
                        if backend_id == fixture.backend_id then
                            sources_read = sources_read + 1
                        end
                        return items:get_item_from_id(backend_id)
                    end }
                end
                if fault == "echo" then
                    mod.echo = function()
                        if persisted == 0 then return end
                        observer_hits = observer_hits + 1
                        error("postcommit echo failure")
                    end
                end
                if fault == "probe" then
                    mod._cim_autodump_craft_synth_result = function()
                        observer_hits = observer_hits + 1
                        error("postcommit probe failure")
                    end
                end
                rawset(_G, "printf", function(format)
                    if format:find("[cim:1141] postcommit_observer_failed", 1, true) then
                        receipts = receipts + 1
                        if fault == "failure_logger" then error("logger failure") end
                    elseif fault == "trace" and format:find("[cim:390] crafted CWV", 1, true) then
                        observer_hits = observer_hits + 1
                        error("postcommit unit trace failure")
                    end
                end)
                local prior = { "prior-request" }
                local crafting = {
                    _last_id = 14, _craft_requests = { [14] = prior },
                    _backend_mirror = {},
                    _get_valid_recipe = function()
                        return { name = "craft_weapon" }, { fixture.backend_id }
                    end,
                }
                local called, id, recipe = pcall(mod.hooks.craft,
                    function() error("custom forge must not call vanilla") end,
                    crafting, "es_mercenary", { fixture.backend_id }, "craft_weapon")
                H.equal(called, true, fault .. ": " .. tostring(id))
                H.equal(id, 15, fault)
                H.equal(recipe.name, "craft_weapon", fault)
                H.equal(crafting._craft_requests[14], prior, fault)
                local completed = crafting._craft_requests[15]
                H.equal(#completed, 1, fault)
                H.equal(completed[1][3], 1, fault)
                local backend_id = completed[1][1]
                H.equal(live[backend_id], saved[backend_id], fault)
                H.equal(saved[backend_id].item_key, fixture.item_key, fault)
                H.equal(injected, 1, fault)
                H.equal(persisted, 1, fault)
                H.equal(noted, 1, fault)
                H.equal(rollback, 0, fault)
                H.truthy(sources_read > 0, "must exercise the real seed lookup first")
                H.equal(observer_hits, 1, fault .. " did not reach its fault")
                H.equal(surface.dirties(), 1, fault)
                H.equal(receipts, fault == "probe" and 0 or 1, fault)
                local check = mod.checks.issue1141_postcommit_observation_boundary
                H.equal(type(check), "function")
                H.equal(check(), nil)
            end)
        end
    end)

    H.test("CIM #1141 real persistence owner passes its normalized record to real craft diagnostics", function()
        for _, fault in ipairs({ "none", "diagnostic_logger" }) do
            local seed = cwv_seed_fixture("001")
            local mod = make_craft_surface_mod()
            local persisted, injected, rollback = 0, 0, 0
            local live = { [seed.backend_id] = seed.live }
            local injected_payload, observed_record, observed_calls
            observed_calls = 0
            mod._cim_test_items_by_id = live
            function mod:set(key, value)
                self.settings[key] = value
                if key == "forged_weapons" then persisted = persisted + 1 end
            end
            local original_dofile = mod.dofile
            function mod:dofile(path)
                if path:find("_cim_custom_glow_notice", 1, true)
                        or path:find("_cim_mil_entry_builder", 1, true) then
                    return assert(loadfile(root .. path:match("([^/]+)$") .. ".lua"))()
                end
                return original_dofile(self, path)
            end
            with_craft_surface_globals(mod, seed.master, nil, function(surface)
                local mirror = { _inventory_items = live }
                Managers.backend.get_backend_mirror = function() return mirror end
                local items = Managers.backend:get_interface("items")
                items.get_all_backend_items = function() return live end
                local owner = assert(loadfile(root .. "_cim_forge_state_owner.lua"))()({
                    mod = mod, rt_register = mod._cim_rt_register,
                    get_mod = function() return nil end,
                    get_item_master_list = function() return seed.master end,
                    print_line = function() end,
                })
                -- Ignore the owner's initial empty-store normalization save.
                persisted = 0
                assert(loadfile(root .. "cim_debug.lua"))()
                install(context(mod, {
                    get_cwv_seed_identity_provider = function() return seed.provider end,
                    inject_item = function(data, backend_id)
                        injected = injected + 1
                        injected_payload = data
                        live[backend_id] = {
                            backend_id = backend_id, key = data.item_key,
                            rarity = data.rarity, data = seed.master[data.item_key],
                        }
                        return true, nil, ownership_token(backend_id, data.item_key),
                            function() rollback = rollback + 1; return true end
                    end,
                    -- No register_craft stub: use the actual owner's true,entry result.
                }))
                mod._cim_is_modded_backend_id = function(backend_id)
                    return owner.get_forged_weapons()[backend_id] ~= nil
                end
                local diagnostic = mod._cim_autodump_craft_synth_result
                mod._cim_autodump_craft_synth_result = function(...)
                    observed_calls = observed_calls + 1
                    observed_record = select(5, ...)
                    return diagnostic(...)
                end
                local info = mod.info
                local logger_failures = 0
                function mod:info(message, ...)
                    if fault == "diagnostic_logger" and message:find(
                            "[craft_synth_result/standard_forge_synth]", 1, true) then
                        logger_failures = logger_failures + 1
                        error("real diagnostic logger failed")
                    end
                    return info(self, message, ...)
                end
                assert(loadfile(root .. "standard_forge.lua"))()
                mod._cim_standard_forge_active = true
                local prior = { "prior-request" }
                local crafting = {
                    _last_id = 14, _craft_requests = { [14] = prior },
                    _backend_mirror = mirror,
                    _get_valid_recipe = function()
                        return { name = "craft_weapon" }, { seed.backend_id }
                    end,
                }
                local called, id = pcall(mod.hooks.craft,
                    function() error("custom forge must not call vanilla") end,
                    crafting, "es_mercenary", { seed.backend_id }, "craft_weapon")
                H.equal(called, true, fault .. ": " .. tostring(id))
                H.equal(id, 15)
                H.equal(crafting._craft_requests[14], prior)
                local completed = crafting._craft_requests[15]
                H.equal(#completed, 1)
                H.equal(completed[1][3], 1)
                local backend_id = completed[1][1]
                local committed = owner.get_forged_weapons()[backend_id]
                H.equal(observed_calls, 1)
                H.equal(observed_record, committed,
                    "diagnostics must receive the real owner's normalized entry, not its success flag")
                H.truthy(committed ~= injected_payload, "normalization must be exercised")
                H.equal(committed.schema_version, contract.SCHEMA_VERSION)
                H.equal(committed.item_key, seed.item_key)
                H.equal(mod.settings.forged_weapons[backend_id].item_key, seed.item_key)
                H.equal(persisted, 1)
                H.equal(injected, 1)
                H.equal(rollback, 0)
                H.equal(surface.dirties(), 1)
                H.deep_equal(mod._cim_recent_craft_bids, { backend_id })
                local pending = mod._cim_pending_visibility_checks
                if fault == "none" then
                    H.equal(#pending, 1, "real diagnostic must schedule visibility work")
                    H.equal(pending[1].bid, backend_id)
                    H.equal(pending[1].item_key, seed.item_key)
                    H.equal(pending[1].frames_until_check, 2)
                    mod._cim_autodump_run_visibility_checks()
                    H.equal(#mod._cim_pending_visibility_checks, 1)
                    mod._cim_autodump_run_visibility_checks()
                    H.equal(#mod._cim_pending_visibility_checks, 0)
                    local immediate, delayed = 0, 0
                    for _, message in ipairs(mod.messages) do
                        if message:find("[craft_synth_result/standard_forge_synth]", 1, true) then
                            immediate = immediate + 1
                        elseif message:find("[craft_visibility/standard_forge_synth]", 1, true) then
                            delayed = delayed + 1
                            H.truthy(message:find("found_in_all=true", 1, true))
                            H.truthy(message:find("visible_to_career=true", 1, true))
                        end
                    end
                    H.equal(immediate, 5)
                    H.equal(delayed, 1)
                else
                    H.equal(logger_failures, 1, "fault must reach the real logger")
                    H.equal(#pending, 0)
                end
                H.equal(crafting._craft_requests[15], completed,
                    "observational callbacks must not republish completion")
                H.equal(persisted, 1)
                H.equal(surface.dirties(), 1)
            end)
        end
    end)

    H.test("CIM #1141 post-commit observer failure receipts are bounded", function()
        local mod = make_craft_surface_mod()
        local owner = install_direct_owner({ mod = mod, contract = contract })
        local prior = rawget(_G, "printf")
        local receipts = 0
        rawset(_G, "printf", function() receipts = receipts + 1 end)
        local ok, reason = pcall(function()
            owner.observe_standard_craft = function() error("observer failed") end
            for index = 1, 12 do
                local result, committed = owner.finish_standard_craft(
                    "es_sword", "bounded-" .. index, {}, "es_mercenary")
                H.equal(committed, true)
                H.equal(result[1][1], "bounded-" .. index)
            end
            H.equal(receipts, 8)
        end)
        rawset(_G, "printf", prior)
        if not ok then error(reason, 0) end
    end)

    H.test("CIM #1141 standard forge rejects unauthenticated CWV seeds", function()
        local fixture = cwv_seed_fixture("001")
        local cases = {
            {
                name = "absent",
                provider = function() return nil, "mod_absent" end,
            },
            {
                name = "tampered",
                provider = function()
                    return {
                        schema = fixture.provider.schema,
                        owner = fixture.provider.owner,
                        capability = fixture.provider.capability,
                        resolve = function(_, backend_id)
                            local proof, reason = fixture.provider:resolve(backend_id)
                            if proof then
                                proof = deep_clone(proof)
                                proof.fingerprint = "tampered"
                            end
                            return proof, reason
                        end,
                        sample = function(_, item_key)
                            return fixture.provider:sample(item_key)
                        end,
                    }
                end,
            },
        }
        for _, case in ipairs(cases) do
            local mod = make_craft_surface_mod()
            mod._cim_test_items_by_id = {
                [fixture.backend_id] = fixture.live,
            }
            local injections, persisted = 0, 0
            install(context(mod, {
                get_cwv_seed_identity_provider = case.provider,
                inject_item = function()
                    injections = injections + 1
                    return true
                end,
                register_craft = function()
                    persisted = persisted + 1
                    return true
                end,
            }))
            local unrelated = { state = "older-complete" }
            local in_flight = { state = "in-flight" }
            local crafting
            with_craft_surface_globals(mod, fixture.master, nil, function(surface)
                assert(loadfile(root .. "standard_forge.lua"))()
                mod._cim_standard_forge_active = true
                crafting = {
                    _last_id = 40,
                    _craft_requests = { [7] = unrelated, [40] = in_flight },
                    _backend_mirror = {},
                    _get_valid_recipe = function()
                        return { name = "craft_weapon" }, {
                            fixture.backend_id,
                        }
                    end,
                }
                local craft_id, completion = mod.hooks.craft(
                    function() error("custom forge must not call vanilla") end,
                    crafting, "es_mercenary", { fixture.backend_id },
                    "craft_weapon")
                H.equal(craft_id, nil, case.name)
                H.equal(completion, false, case.name)
                H.equal(crafting._last_id, 41, case.name)
                H.equal(crafting._craft_requests[41], nil,
                    case.name .. " must not publish a completed request")
                H.equal(crafting._craft_requests[7], unrelated,
                    case.name .. " must preserve unrelated requests")
                H.equal(crafting._craft_requests[40], in_flight,
                    case.name .. " must preserve the prior in-flight request")
                H.equal(surface.dirties(), 0,
                    case.name .. " must not invalidate presentation")
            end)
            H.equal(injections, 0, case.name)
            H.equal(persisted, 0, case.name)
            local rejected = false
            for _, message in ipairs(mod.messages) do
                if message:find(
                        "Cannot resolve selected CWV Blacksmith weapon", 1, true) then
                    rejected = true
                end
            end
            H.equal(rejected, true, case.name)
        end
    end)

    H.test("CIM #1141 standard forge canonical rejection is not a completed craft", function()
        local mod = make_craft_surface_mod()
        local injection_attempts, persisted, noted = 0, 0, 0
        local published_rows = {}
        mod._cim_test_items_by_id = {
            ["ordinary-seed"] = {
                backend_id = "ordinary-seed",
                key = "es_sword",
                rarity = "default",
                data = {
                    key = "es_sword", name = "es_sword",
                    slot_type = "melee", item_type = "weapon",
                    rarity = "default", can_wield = { "es_mercenary" },
                },
            },
        }
        install(context(mod, {
            inject_item = function()
                injection_attempts = injection_attempts + 1
                return nil, "canonical injection rejected"
            end,
            register_craft = function()
                persisted = persisted + 1
                return true
            end,
            note_craft = function() noted = noted + 1 end,
        }))
        local master = {
            es_sword = {
                key = "es_sword", name = "es_sword",
                slot_type = "melee", item_type = "weapon",
                rarity = "default", can_wield = { "es_mercenary" },
            },
        }
        local unrelated = { state = "older-complete" }
        local in_flight = { state = "in-flight" }
        with_craft_surface_globals(mod, master, nil, function(surface)
            assert(loadfile(root .. "standard_forge.lua"))()
            mod._cim_standard_forge_active = true
            local crafting = {
                _last_id = 90,
                _craft_requests = { [12] = unrelated, [90] = in_flight },
                _backend_mirror = published_rows,
                _get_valid_recipe = function()
                    return { name = "craft_weapon" }, {
                        "ordinary-seed",
                    }
                end,
            }
            local craft_id, completion = mod.hooks.craft(
                function() error("custom forge must not call vanilla") end,
                crafting, "es_mercenary", { "ordinary-seed" },
                "craft_weapon")
            H.equal(craft_id, nil)
            H.equal(completion, false)
            H.equal(crafting._last_id, 91)
            H.equal(crafting._craft_requests[91], nil,
                "rejected transaction must not look complete")
            H.equal(crafting._craft_requests[12], unrelated,
                "rejection must preserve unrelated requests")
            H.equal(crafting._craft_requests[90], in_flight,
                "rejection must preserve the prior in-flight request")
            H.equal(surface.dirties(), 0,
                "rejected transaction must not invalidate presentation")
        end)
        H.equal(injection_attempts, 1)
        H.equal(next(published_rows), nil,
            "rejected injector must not publish a mirror row")
        H.equal(persisted, 0)
        H.equal(noted, 0)
        local rejected = false
        for _, message in ipairs(mod.messages) do
            if message:find("craft transaction FAILED", 1, true)
                    and message:find("canonical injection rejected", 1, true) then
                rejected = true
            end
        end
        H.equal(rejected, true)
    end)

    H.test("CIM #1141 standard forge pre-commit rejection is not a completed craft", function()
        local ordinary_master = {
            es_sword = {
                key = "es_sword", name = "es_sword",
                slot_type = "melee", item_type = "weapon",
                rarity = "default", can_wield = { "es_mercenary" },
            },
        }
        local cases = {
            {
                name = "no career",
                backend_id = "ordinary-seed",
                master = ordinary_master,
                item = {
                    backend_id = "ordinary-seed", key = "es_sword",
                    rarity = "default", data = ordinary_master.es_sword,
                },
                arrange = function()
                    Managers.player.local_player = function() return nil end
                end,
                message = "no local career resolved",
            },
            {
                name = "invalid slot",
                backend_id = "material-seed",
                master = {
                    crafting_material_scrap = {
                        key = "crafting_material_scrap",
                        name = "crafting_material_scrap",
                        slot_type = "crafting_material",
                        item_type = "crafting_material",
                        rarity = "default",
                        can_wield = { "es_mercenary" },
                    },
                },
                item = function()
                    return {
                        backend_id = "material-seed",
                        key = "crafting_material_scrap",
                        rarity = "default",
                        data = {
                            key = "crafting_material_scrap",
                            slot_type = "crafting_material",
                        },
                    }
                end,
                message = "isn't a weapon/jewellery slot",
            },
            {
                name = "no eligible item",
                backend_id = "missing-seed",
                master = {},
                item = function() return nil end,
                message = "No eligible items for career",
            },
        }

        for _, case in ipairs(cases) do
            local mod = make_craft_surface_mod()
            mod._cim_test_items_by_id = {
                [case.backend_id] = case.item,
            }
            local injections, persisted, noted = 0, 0, 0
            install(context(mod, {
                inject_item = function()
                    injections = injections + 1
                    error(case.name .. " must reject before injection")
                end,
                register_craft = function()
                    persisted = persisted + 1
                    error(case.name .. " must reject before persistence")
                end,
                note_craft = function() noted = noted + 1 end,
            }))
            local older = { state = "older-complete" }
            local in_flight = { state = "in-flight" }
            with_craft_surface_globals(mod, case.master, nil, function(surface)
                assert(loadfile(root .. "standard_forge.lua"))()
                mod._cim_standard_forge_active = true
                if case.arrange then case.arrange() end
                local crafting = {
                    _last_id = 70,
                    _craft_requests = { [3] = older, [70] = in_flight },
                    _backend_mirror = {},
                    _get_valid_recipe = function()
                        return { name = "craft_weapon" }, {
                            case.backend_id,
                        }
                    end,
                }
                local craft_id, completion = mod.hooks.craft(
                    function() error("custom forge must not call vanilla") end,
                    crafting, "es_mercenary", { case.backend_id },
                    "craft_weapon")
                H.equal(craft_id, nil, case.name)
                H.equal(completion, false, case.name)
                H.equal(crafting._last_id, 71, case.name)
                H.equal(crafting._craft_requests[71], nil,
                    case.name .. " must not publish a completed request")
                H.equal(crafting._craft_requests[3], older,
                    case.name .. " must preserve older requests")
                H.equal(crafting._craft_requests[70], in_flight,
                    case.name .. " must preserve the prior in-flight request")
                H.equal(surface.dirties(), 0,
                    case.name .. " must not invalidate presentation")
            end)
            H.equal(injections, 0, case.name)
            H.equal(persisted, 0, case.name)
            H.equal(noted, 0, case.name)
            local saw_message = false
            for _, message in ipairs(mod.messages) do
                if message:find(case.message, 1, true) then
                    saw_message = true
                end
            end
            H.equal(saw_message, true, case.name)
        end
    end)

    H.test("CIM #1141 standard forge preserves legacy silent-drop completion", function()
        local mod = make_craft_surface_mod()
        local master = {
            es_sword = {
                key = "es_sword", name = "es_sword",
                slot_type = "melee", item_type = "weapon",
                rarity = "default", can_wield = { "es_mercenary" },
            },
        }
        local unrelated = { state = "pending" }
        with_craft_surface_globals(mod, master, nil, function(surface)
            assert(loadfile(root .. "standard_forge.lua"))()
            mod._cim_standard_forge_active = true
            local crafting = {
                _last_id = 5,
                _craft_requests = { [2] = unrelated },
                _backend_mirror = {},
                _get_valid_recipe = function() return nil end,
            }
            local craft_id, completion = mod.hooks.craft(
                function() error("active forge must not call vanilla") end,
                crafting, "es_mercenary", { "ordinary-seed" },
                "unknown_recipe")
            H.equal(craft_id, 6)
            H.equal(completion.name, "cim_noop")
            H.deep_equal(crafting._craft_requests[6], {})
            H.equal(crafting._craft_requests[2], unrelated)
            H.equal(surface.dirties(), 0)
        end)
    end)

    H.test("CIM #1141 SaveWeapon import commits atomically and contains rollback", function()
        local mod = make_craft_surface_mod()
        local injected, registered, rollbacks, rollback_refreshes = 0, 0, 0, 0
        local evidence_by_key = {}
        install(context(mod, {
            inject_item = function(data, backend_id)
                injected = injected + 1
                return true, nil, ownership_token(backend_id, data.item_key),
                    function()
                        rollbacks = rollbacks + 1
                        return true
                    end
            end,
            register_craft = function(_, data)
                registered = registered + 1
                if data.item_key == "dr_1h_axe" then
                    return false, "save rejected"
                end
                return true, data
            end,
            refresh_backend = function()
                rollback_refreshes = rollback_refreshes + 1
                return true
            end,
            note_craft = function() end,
            print_line = function(_, _, source_backend_id, raw_item_key)
                if source_backend_id then
                    evidence_by_key[raw_item_key] = source_backend_id
                end
            end,
        }))

        local saveweapon = {
            get = function(_, key)
                if key ~= "saved_items" then return nil end
                return {
                    es_sword_11 = "false/nil/trait_ok/prop_ok",
                    dr_1h_axe_12 = "true/nil/trait_ok/prop_ok",
                }
            end,
            get_item_name_from_save_id = function(_, save_id)
                if save_id == "es_sword_11" then return "es_sword" end
                if save_id == "dr_1h_axe_12" then return "dr_1h_axe" end
            end,
        }
        local master = {
            es_sword = { key = "es_sword", slot_type = "melee" },
            dr_1h_axe = { key = "dr_1h_axe", slot_type = "melee" },
        }
        local surface
        with_craft_surface_globals(mod, master, saveweapon, function(state)
            surface = state
            assert(loadfile(root .. "saveweapon_import.lua"))()
            mod._cim_saveweapon_import()
        end)

        H.equal(injected, 2)
        H.equal(registered, 2)
        H.equal(rollbacks, 1)
        H.equal(rollback_refreshes, 1)
        H.equal(surface.refreshes(), 1)
        H.equal(surface.dirties(), 1)
        H.equal(evidence_by_key.es_sword, "es_sword_11")
        H.equal(evidence_by_key.dr_1h_axe, "dr_1h_axe_12")
        local summary
        for _, message in ipairs(mod.messages) do
            if message:find("SaveWeapon import:", 1, true) then summary = message end
        end
        H.truthy(summary and summary:find("1 imported", 1, true))
        H.truthy(summary and summary:find("1 invalid", 1, true))
    end)

end
