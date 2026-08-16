return function(H, repo_root)
    local relative = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_cim_preview.lua"
    local Module = assert(loadfile(repo_root .. "/" .. relative))()

    local function make_context(generation, backend_id)
        backend_id = backend_id or "bid-481"
        return {
            contract = Module.CONTRACT,
            surface = "cim_preview",
            provider = "cim_dev",
            constructor = "properties",
            generation = generation or 1,
            backend_id = backend_id,
            item_key = "es_sword_shield",
            item_type = "es_1h_sword_shield",
            skin = "es_sword_shield_skin_01",
            exact_backend_identity = true,
        }
    end

    local function fixture(options)
        options = options or {}
        local clock = { value = 10 }
        local current = { value = nil }
        local package_state = {
            loaded = options.parent_loaded ~= false,
            refs = {}, loads = 0, unloads = 0,
        }
        local application = {
            can_get = function(kind, path)
                if kind == "unit" then
                    return path == "units/la_shield_3p"
                        and options.unit_resident ~= false
                end
                return kind == "package" and path == "units/la_shield_3p"
                    and options.standalone_package == true
            end,
        }
        local packages = {}
        function packages:has_loaded(path, reference)
            if path ~= "units/parent.package" or not package_state.loaded then
                return false
            end
            if reference ~= nil then return package_state.refs[reference] == true end
            return true
        end
        function packages:load(path, reference)
            H.equal(path, "units/parent.package")
            H.truthy(package_state.loaded,
                "adapter must never force-load an unheld parent package")
            package_state.loads = package_state.loads + 1
            package_state.refs[reference] = true
        end
        function packages:unload(path, reference)
            H.equal(path, "units/parent.package")
            package_state.unloads = package_state.unloads + 1
            package_state.refs[reference] = nil
        end

        local cim_mod = {
            _cim_preview_context_current = function() return current.value end,
        }
        local selections = {
            ["bid-481"] = {
                left_hand_unit = { la_armoury_key = "la-shield", unit = "units/la_shield" },
            },
        }
        local pool = {
            left_hand_unit = {
                { la_armoury_key = "la-shield", unit = "units/la_shield" },
            },
        }
        local calls = { applied = 0, contexts = {}, migrated = 0, recoveries = {} }
        local la_bridge = {
            la_kind_unit_parent_packages = {
                ["la-shield"] = "units/parent.package",
            },
        }
        if options.gate_recovery ~= false then
            la_bridge.gate_recovery = {
                recover = function(gate, key, context, reason, allow_lease)
                    calls.recoveries[#calls.recoveries + 1] = {
                        gate = gate, key = key, context = context,
                        reason = reason, allow_lease = allow_lease,
                    }
                end,
            }
        end
        local api = Module.new({
            get_mod = function(id)
                if id == "cim_dev" then return cim_mod end
            end,
            get_application = function() return application end,
            get_package_manager = function() return packages end,
            get_offhand_options = function(item_type)
                H.equal(item_type, "es_1h_sword_shield")
                return pool
            end,
            migrate_selection = function(backend_id)
                H.equal(backend_id, "bid-481")
                calls.migrated = calls.migrated + 1
            end,
            offhand_selection = selections,
            instance_policy = {
                selection_owned = function(selection, received_pool)
                    return received_pool == pool.left_hand_unit
                        and selection.la_armoury_key == "la-shield"
                end,
            },
            resolve_variant = function(key)
                if key == "la-shield" then
                    return { kind = "unit", new_units = {
                        "units/la_shield", "units/la_shield_3p",
                    } }, options.variant_source or "loremaster"
                end
            end,
            apply_exact = function(_world, unit, key, _, context)
                H.equal(unit, "live-unit")
                H.equal(key, "la-shield")
                calls.applied = calls.applied + 1
                calls.contexts[#calls.contexts + 1] = context
                return options.apply_ready ~= false
            end,
            is_unit = function(unit) return unit == "live-unit" end,
            la_bridge = la_bridge,
            now = function() return clock.value end,
            max_attempts = options.max_attempts or 3,
            retry_window = options.retry_window or 1,
            log = function() end,
        })
        return api, current, clock, package_state, selections, pool, calls
    end

    local ITEM = {
        key = "es_sword_shield",
        item_type = "es_1h_sword_shield",
        backend_id = "bid-481",
        skin = "es_sword_shield_skin_01",
    }

    H.test("Cosmetics CIM preview exact identity fails closed", function()
        local api, current = fixture()
        local context, reason, scoped = api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin)
        H.equal(context, nil)
        H.equal(reason, "not-cim")
        H.equal(scoped, false)

        current.value = make_context(1)
        context, reason, scoped = api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin)
        H.equal(context, current.value)
        H.equal(reason, "exact")
        H.equal(scoped, true)

        current.value = make_context(1)
        context, reason, scoped = api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin)
        H.equal(context, nil)
        H.equal(reason, "invalid-generation")
        H.equal(scoped, true,
            "a provider reload cannot reuse a remembered generation token")
        current.value = make_context(2)

        for _, row in ipairs({
            { ITEM, nil, ITEM.item_type, ITEM.skin, "backendless" },
            { ITEM, "foreign", ITEM.item_type, ITEM.skin, "foreign-backend" },
            { { key = "foreign", item_type = ITEM.item_type },
                "bid-481", ITEM.item_type, ITEM.skin, "foreign-item" },
            { ITEM, "bid-481", "foreign-type", ITEM.skin, "foreign-item-type" },
            { ITEM, "bid-481", ITEM.item_type, "foreign-skin", "foreign-skin" },
        }) do
            local accepted, rejected, present = api.resolve_scoped_identity(
                row[1], row[2], row[3], row[4])
            H.equal(accepted, nil)
            H.equal(rejected, row[5])
            H.equal(present, true)
        end

        current.value = make_context(3)
        current.value.backend_id = nil
        current.value.exact_backend_identity = false
        context, reason, scoped = api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin)
        H.equal(context, nil)
        H.equal(reason, "backendless")
        H.equal(scoped, true)
    end)

    H.test("Cosmetics CIM preview retains only an already-loaded parent", function()
        local api, current, _, packages = fixture()
        current.value = make_context(1)
        local context = assert(api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        local ok, reason = api.prepare_override(context, "left_hand_unit",
            { la_armoury_key = "la-shield" }, "units/la_shield", false,
            ITEM.item_type)
        H.equal(ok, true)
        H.equal(reason, "ready")
        local previewer = {}
        ok, reason = api.capture_load(previewer, "units/la_shield_3p")
        H.equal(ok, true)
        H.equal(reason, "captured")
        H.equal(packages.loads, 1)
        api.destroy(previewer)
        H.equal(packages.unloads, 1)

        local native, native_current, _, native_packages = fixture({
            standalone_package = true,
        })
        native_current.value = make_context(3)
        local native_context = assert(native.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        H.truthy(native.prepare_override(native_context, "left_hand_unit",
            { la_armoury_key = "la-shield" }, "units/la_shield", true,
            ITEM.item_type))
        local native_previewer = { _cim_preview_context = native_context }
        ok, reason = native.capture_load(native_previewer, "units/la_shield_3p")
        H.equal(ok, false)
        H.equal(reason, "native-package",
            "a real standalone package must remain on vanilla's load path")
        H.equal(native_packages.loads, 1,
            "the already-loaded parent still receives a previewer lease")
        native.destroy(native_previewer)
        H.equal(native_packages.unloads, 1)

        local blocked, blocked_current, _, blocked_packages = fixture({
            parent_loaded = false,
        })
        blocked_current.value = make_context(2)
        local blocked_context = assert(blocked.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        ok, reason = blocked.prepare_override(blocked_context,
            "left_hand_unit", { la_armoury_key = "la-shield" },
            "units/la_shield", true, ITEM.item_type)
        H.equal(ok, false)
        H.equal(reason, "parent-not-loaded")
        H.equal(blocked_packages.loads, 0,
            "missing parent must never be force-loaded")

        local foreign, foreign_current = fixture({
            variant_source = "cosmetics",
        })
        foreign_current.value = make_context(4)
        local foreign_context = assert(foreign.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        ok, reason = foreign.prepare_override(foreign_context,
            "left_hand_unit", { la_armoury_key = "la-shield" },
            "units/la_shield", true, ITEM.item_type)
        H.equal(ok, false)
        H.equal(reason, "foreign-provider",
            "the CIM bridge admits Loremaster selections only")

        ok, reason = api.prepare_override(context, "left_hand_unit",
            { la_armoury_key = "la-shield" }, "units/foreign", true,
            ITEM.item_type)
        H.equal(ok, false)
        H.equal(reason, "foreign-unit",
            "an authored unit pair cannot be rebound to a guessed path")
    end)

    H.test("Cosmetics CIM preview routes refusals to bounded gate recovery (#481)", function()
        -- parent-not-loaded: the declared vanilla parent IS the missing owner;
        -- the refusal stands (fail-closed) and recovery is asked to lease it.
        local blocked, blocked_current, _, blocked_packages, _, _, blocked_calls =
            fixture({ parent_loaded = false })
        blocked_current.value = make_context(1)
        local blocked_context = assert(blocked.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        local ok, reason = blocked.prepare_override(blocked_context,
            "left_hand_unit", { la_armoury_key = "la-shield" },
            "units/la_shield", true, ITEM.item_type)
        H.equal(ok, false)
        H.equal(reason, "parent-not-loaded")
        H.equal(blocked_packages.loads, 0,
            "the adapter itself still never force-loads")
        H.equal(#blocked_calls.recoveries, 1)
        local recovery = blocked_calls.recoveries[1]
        H.equal(recovery.gate, "parent-not-loaded")
        H.equal(recovery.key, "la-shield")
        H.equal(recovery.context, "cim_preview")
        H.equal(recovery.allow_lease, nil,
            "the declared parent owner is lease-eligible")

        -- unit-not-resident: the missing owner is the LA bundle, never
        -- lease-safe, so the recovery call must be marker-only.
        local absent, absent_current, _, _, _, _, absent_calls =
            fixture({ unit_resident = false })
        absent_current.value = make_context(2)
        local absent_context = assert(absent.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        ok, reason = absent.prepare_override(absent_context,
            "left_hand_unit", { la_armoury_key = "la-shield" },
            "units/la_shield", true, ITEM.item_type)
        H.equal(ok, false)
        H.equal(reason, "unit-not-resident")
        H.equal(#absent_calls.recoveries, 1)
        H.equal(absent_calls.recoveries[1].gate, "unit-not-resident")
        H.equal(absent_calls.recoveries[1].allow_lease, false,
            "an LA-bundle owner must never be leased")

        -- A la_bridge without the recovery owner degrades to plain refusal.
        local bare, bare_current, _, bare_packages =
            fixture({ parent_loaded = false, gate_recovery = false })
        bare_current.value = make_context(3)
        local bare_context = assert(bare.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        ok, reason = bare.prepare_override(bare_context,
            "left_hand_unit", { la_armoury_key = "la-shield" },
            "units/la_shield", true, ITEM.item_type)
        H.equal(ok, false)
        H.equal(reason, "parent-not-loaded")
        H.equal(bare_packages.loads, 0)
    end)

    H.test("Cosmetics CIM preview keeps malformed scopes off generic load", function()
        local api, current, _, packages = fixture()
        local old_context = make_context(1)
        current.value = old_context
        H.truthy(api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        H.truthy(api.prepare_override(old_context, "left_hand_unit",
            { la_armoury_key = "la-shield" }, "units/la_shield", true,
            ITEM.item_type))

        current.value = { contract = "foreign-contract" }
        local previewer = { _cim_preview_context = old_context }
        local captured, reason, scoped = api.capture_load(
            previewer, "units/la_shield_3p")
        H.equal(captured, false)
        H.equal(reason, "invalid-contract")
        H.equal(scoped, true)
        H.equal(packages.loads, 0,
            "an invalid live scope cannot fall back to an older marker")

        current.value = nil
        previewer._cim_preview_context = { contract = "foreign-contract" }
        H.equal(api.surface(previewer), "cim_preview",
            "a malformed private marker must suppress generic preview policy")
        captured, reason, scoped = api.capture_load(
            previewer, "units/la_shield_3p")
        H.equal(captured, false)
        H.equal(reason, "invalid-contract")
        H.equal(scoped, true)
    end)

    H.test("Cosmetics CIM preview matches hand path and applies at neutral surface", function()
        local api, current, _, packages, _, _, calls = fixture()
        current.value = make_context(1)
        local context = assert(api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        H.truthy(api.prepare_override(context, "left_hand_unit",
            { la_armoury_key = "la-shield" }, "units/la_shield", true,
            ITEM.item_type))
        local previewer = { _cim_preview_context = context }
        H.truthy(api.capture_load(previewer, "units/la_shield_3p"))
        local applied, reason = api.spawn(previewer, {
            { unit_name = "units/foreign_3p" },
            { unit_name = "units/la_shield_3p" },
        }, { "foreign-unit", "live-unit" }, "world")
        H.equal(applied, true)
        H.equal(reason, "applied")
        H.equal(calls.applied, 1)
        H.equal(calls.contexts[1], "cim_preview")
        H.equal(packages.loads, 1)

        local mismatch = { _cim_preview_context = make_context(2) }
        applied, reason = api.spawn(mismatch, {
            { unit_name = "units/foreign_3p" },
        }, { "live-unit" }, "world")
        H.equal(applied, false)
        H.equal(reason, "no-owned-spawn")
        H.equal(calls.applied, 1)
    end)

    H.test("Cosmetics CIM preview retries boundedly then retains base", function()
        local api, current, _, _, _, _, calls = fixture({
            apply_ready = false, max_attempts = 2, retry_window = 1,
        })
        current.value = make_context(1)
        local context = assert(api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        H.truthy(api.prepare_override(context, "left_hand_unit",
            { la_armoury_key = "la-shield" }, "units/la_shield", true,
            ITEM.item_type))
        local previewer = { _cim_preview_context = context }
        H.truthy(api.capture_load(previewer, "units/la_shield_3p"))
        local applied, reason = api.spawn(previewer,
            { { unit_name = "units/la_shield_3p" } },
            { "live-unit" }, "world")
        H.equal(applied, false)
        H.equal(reason, "pending")
        applied, reason = api.update(previewer)
        H.equal(applied, false)
        H.equal(reason, "pending")
        applied, reason = api.update(previewer)
        H.equal(applied, false)
        H.equal(reason, "timeout-base-retained")
        H.equal(calls.applied, 2)
        H.equal(api.debug_state().jobs[previewer], nil)

        local timed, timed_current, timed_clock = fixture({
            apply_ready = false, max_attempts = 9, retry_window = 0.5,
        })
        timed_current.value = make_context(2)
        local timed_context = assert(timed.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        H.truthy(timed.prepare_override(timed_context, "left_hand_unit",
            { la_armoury_key = "la-shield" }, "units/la_shield", true,
            ITEM.item_type))
        local timed_previewer = { _cim_preview_context = timed_context }
        H.truthy(timed.capture_load(timed_previewer, "units/la_shield_3p"))
        H.equal(timed.spawn(timed_previewer,
            { { unit_name = "units/la_shield_3p" } },
            { "live-unit" }, "world"), false)
        timed_clock.value = timed_clock.value + 1
        applied, reason = timed.update(timed_previewer)
        H.equal(applied, false)
        H.equal(reason, "timeout-base-retained")
    end)

    H.test("Cosmetics CIM preview isolates generations and simultaneous previewers", function()
        local api, current, _, packages, selections, _, calls = fixture()
        current.value = make_context(1)
        local first_context = assert(api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        H.truthy(api.prepare_override(first_context, "left_hand_unit",
            selections["bid-481"].left_hand_unit, "units/la_shield", true,
            ITEM.item_type))
        local first = { _cim_preview_context = first_context }
        H.truthy(api.capture_load(first, "units/la_shield_3p"))

        current.value = make_context(2)
        local second_context = assert(api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        H.truthy(api.prepare_override(second_context, "left_hand_unit",
            selections["bid-481"].left_hand_unit, "units/la_shield", true,
            ITEM.item_type))
        local second = { _cim_preview_context = second_context }
        H.truthy(api.capture_load(second, "units/la_shield_3p"))
        H.equal(packages.loads, 2,
            "simultaneous previewers require independent references")

        H.equal(api.spawn(first, { { unit_name = "units/la_shield_3p" } },
            { "live-unit" }, "world"), true)
        H.equal(api.spawn(second, { { unit_name = "units/la_shield_3p" } },
            { "live-unit" }, "world"), true)
        H.equal(calls.applied, 2)
        api.destroy(first)
        api.destroy(second)
        H.equal(packages.unloads, 2)
    end)

    H.test("Cosmetics CIM preview drops stale work across destroy and reopen", function()
        local api, current, _, packages, selections, _, calls = fixture({
            apply_ready = false,
        })
        current.value = make_context(1)
        local first_context = assert(api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        H.truthy(api.prepare_override(first_context, "left_hand_unit",
            selections["bid-481"].left_hand_unit, "units/la_shield", true,
            ITEM.item_type))
        local previewer = { _cim_preview_context = first_context }
        H.truthy(api.capture_load(previewer, "units/la_shield_3p"))
        local applied, reason = api.spawn(previewer,
            { { unit_name = "units/la_shield_3p" } },
            { "live-unit" }, "world")
        H.equal(applied, false)
        H.equal(reason, "pending")
        H.equal(calls.applied, 1)

        -- A marker from a reopened constructor invalidates generation 1 before
        -- its next reconcile can touch the replacement previewer.
        previewer._cim_preview_context = make_context(2)
        applied, reason = api.update(previewer)
        H.equal(applied, false)
        H.equal(reason, "stale-generation")
        H.equal(calls.applied, 1)
        H.equal(api.debug_state().jobs[previewer], nil)

        api.destroy(previewer)
        H.equal(packages.unloads, 1)
        current.value = previewer._cim_preview_context
        local second_context = assert(api.resolve_scoped_identity(
            ITEM, "bid-481", ITEM.item_type, ITEM.skin))
        H.truthy(api.prepare_override(second_context, "left_hand_unit",
            selections["bid-481"].left_hand_unit, "units/la_shield", true,
            ITEM.item_type))
        H.truthy(api.capture_load(previewer, "units/la_shield_3p"))
        applied, reason = api.spawn(previewer,
            { { unit_name = "units/la_shield_3p" } },
            { "live-unit" }, "world")
        H.equal(applied, false)
        H.equal(reason, "pending")
        H.equal(calls.applied, 2,
            "reopened generation owns exactly one fresh reconcile")
        H.equal(api.debug_state().jobs[previewer][1].generation, 2)
        api.destroy(previewer)
        H.equal(packages.unloads, 2)
    end)

    H.test("Cosmetics CIM source contains no unsafe native setters", function()
        local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
        local source = file:read("*a")
        file:close()
        for _, forbidden in ipairs({
            "Unit.set_all_materials", "Unit.set_texture_for_materials",
            "Unit.set_local_scale", "Material.set_texture", "World.spawn_unit",
        }) do
            H.equal(source:find(forbidden, 1, true), nil, forbidden)
        end
        H.truthy(source:find("max_attempts", 1, true))
        H.truthy(source:find("stale%-generation") ~= nil)

        local bridge_relative = "cosmetics_tweaker/scripts/mods/"
            .. "cosmetics_tweaker/_la_bridge.lua"
        local bridge_file = assert(io.open(repo_root .. "/" .. bridge_relative, "rb"))
        local bridge_source = bridge_file:read("*a")
        bridge_file:close()
        H.truthy(bridge_source:find(
            'elseif context == "ingame" or context == "network_husk"',
            1, true))
        H.truthy(bridge_source:find('or context == "cim_preview" then',
            1, true), "CIM must reach guarded texture paint without material swap")
    end)

    H.test("Cosmetics CIM wiring preserves one adapter across live reload", function()
        local wiring_relative = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
            .. "_cos_cim_preview_wiring.lua"
        local wire = assert(loadfile(repo_root .. "/" .. wiring_relative))()
        local existing = { sentinel = "stable-adapter" }
        local mod = {
            _cos_cim_preview = existing,
            dofile = function()
                error("a live reload must not replace adapter-owned generations")
            end,
        }
        H.equal(wire(mod), existing)
    end)
end
