-- Issue #1656: the cwv harness-defect rows of the 2026-09-21 triage. Each case runs the
-- SHIPPED check body (the whole render module installed, or the check lifted verbatim out of
-- its owner with that owner's own `local x = ctx.y` header) against a world assembled from
-- production modules: the real variant catalog, appearance lifecycle, exact-appearance
-- resolver, husk transform policy, Crowbill runtime, the entry's own #423 recorder and the
-- registration owner's own #482 ladder. Before the fix every case below FAILS the same way the
-- live suite did; after it they pass, and each check still fails loudly when its premise is
-- removed (PROJECT_STANDARDS 5.1d rule 2).
return function(H, repo_root)
    local root = repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local text = file:read("*a")
        file:close()
        return (text:gsub("\r\n", "\n"))
    end

    -- Run `body` with the named globals replaced, restoring them even when it raises.
    local function with_globals(values, body)
        local saved = {}
        for name, value in pairs(values) do
            saved[name] = { value = rawget(_G, name) }
            rawset(_G, name, value)
        end
        local ok, err = pcall(body)
        for name, slot in pairs(saved) do rawset(_G, name, slot.value) end
        if not ok then error(err, 0) end
    end

    local function load_catalog()
        local om = {
            greataxe = dofile(root .. "_cwv_greataxe.lua"),
            dawi_maces = dofile(root .. "_cwv_dawi_maces.lua"),
            crowbill_family = dofile(root .. "_cwv_crowbill_family.lua"),
            crowbill_hammer_mode = dofile(root .. "_cwv_crowbill_hammer_mode.lua"),
            crowbill_runtime = dofile(root .. "_cwv_crowbill_runtime.lua"),
        }
        return dofile(root .. "_cwv_variant_catalog.lua")({ om = om }).definitions, om
    end

    local function find_in(defs)
        return function(key)
            for _, def in ipairs(defs) do
                if def.item_key == key then return def end
            end
            return nil
        end
    end

    -- Registration eligibility exactly as _cwv_item_registration_owner.lua:609 skips it; the
    -- needle test below pins that this predicate is still the production one.
    local function registered_set(defs)
        local registered = {}
        for _, def in ipairs(defs) do
            if not def.skin_only and not def.cwv_retired then registered[def.item_key] = true end
        end
        return registered
    end

    local RANGED_BASES = { es_handgun = true, we_javelin = true, wh_crossbow = true, dr_deus_01 = true }
    local function engine_tables(defs)
        local item_master, skins = {}, {}
        for _, def in ipairs(defs) do
            if type(def.base_weapon) == "string" and not item_master[def.base_weapon] then
                item_master[def.base_weapon] = {
                    key = def.base_weapon,
                    slot_type = RANGED_BASES[def.base_weapon] and "ranged" or "melee",
                    right_hand_unit = "units/weapons/player/base/" .. def.base_weapon,
                }
            end
            -- _cwv_skin_registry.lua:173-188: every non-no_skin def owns "<key>_skin".
            if not def.no_skin then
                skins[def.item_key .. "_skin"] = {
                    right_hand_unit = def.right_hand_unit, left_hand_unit = def.left_hand_unit,
                }
            end
        end
        return item_master, { skins = skins }
    end

    -- `_rt_register("<name>", function() ... end)` through the first column-anchored `end)`.
    local function lift_check(source, name)
        local from = assert(source:find('_rt_register("' .. name .. '", function()', 1, true),
            name .. " is no longer registered")
        local line_start = source:sub(1, from):match("()[^\n]*$")
        local block_end = assert(source:find("\nend)\n", from, true), name .. " has no column-anchored end)")
        return source:sub(line_start, block_end + 5)
    end

    -- The owner's own `local x = ctx.y` header, so the lifted check binds exactly what ships.
    local function owner_header(source)
        local lines = {}
        for line in source:match("return function%(mod, ctx%)\n(.-)\n\n"):gmatch("[^\n]+") do
            H.truthy(line:match("^local [%w_]+ = ctx%.[%w_]+$"), "unexpected header line: " .. line)
            lines[#lines + 1] = line
        end
        return table.concat(lines, "\n")
    end

    local function run_identity_check(name, mod, ctx)
        local source = read("_cwv_regression_identity.lua")
        local chunk = assert(loadstring("local mod, ctx = ...\n" .. owner_header(source) .. "\n"
            .. lift_check(source, name), "@" .. name))
        local captured
        ctx.rt_register = function(_, fn) captured = fn end
        chunk(mod, ctx)
        H.equal(type(captured), "function", name .. " did not register")
        local ok, verdict = pcall(captured)
        H.truthy(ok, name .. " raised instead of returning a verdict: " .. tostring(verdict))
        return verdict
    end

    local function install_render(mod, om, extra)
        local captured = {}
        mod._cwv_dev_anim_picker = mod._cwv_dev_anim_picker or { install = function() end }
        mod.info = mod.info or function() end
        local issue692 = dofile(root .. "_cwv_issue692_transform_check.lua")
        local ctx = {
            issue692_check = issue692, issue692_register = issue692.register,
            mod_version = "qa-1656", om = om, dbg = function() end,
            rt_register = function(name, fn) captured[name] = fn end,
            variant_definitions = {}, registered_keys = {}, display_names = {},
            find_def = function() return nil end, build_entry = function() end,
            auto_register_all = function() end, cross_access_action_remap = {},
            wield_hook_registration_count = 0, transform_map = {},
            skin_transform_map = {}, crowbill_transform_by_unit = {}, custom_skin_keys = {},
        }
        for key, value in pairs(extra or {}) do ctx[key] = value end
        with_globals({ _MEM_PROBE_T0_CWV = collectgarbage("count") }, function()
            assert(loadfile(root .. "_cwv_regression_render.lua"))()(mod, ctx)
        end)
        return captured
    end

    -- ------------------------------------------------------------------------------------
    -- Entry wiring: dbg_helpers_two_channel and issue396 (undeclared-global class).
    -- ------------------------------------------------------------------------------------

    H.test("CWV #1656 regression context binds only identifiers the entry declares", function()
        local entry = read("character_weapon_variants.lua")
        local from = assert(entry:find("local _cwv_regression_context = {", 1, true))
        local block = entry:sub(from, assert(entry:find("\n}\n", from, true)))
        local keys = {}
        for key, value in block:gmatch("\n%s*([%w_]+)%s*=%s*([^,\n]+),") do
            keys[key] = value
            if value:match("^[%a_][%w_]*$") then
                local declared = entry:find("\nlocal " .. value .. "%s*=")
                    or entry:find("\nlocal function " .. value .. "%(")
                    or entry:find("\nlocal [%w_, ]*" .. value .. "[%w_, ]*%s*=")
                H.truthy(declared, "regression context key " .. key .. " binds undeclared global " .. value)
            end
        end
        H.equal(keys.dbg_alert, "_dbg_alert", "the regression context must carry the entry's _dbg_alert")
        H.truthy(entry:find("\nlocal function _dbg_alert%("), "_dbg_alert is an entry local function")
        H.equal(keys.display_names, "_om.display_names")
        H.truthy(keys.regression_fixtures and keys.regression_fixtures:find("_cwv_regression_fixtures", 1, true))
    end)

    H.test("CWV #1656 bootstrap owner publishes the display names the #396 check reads", function()
        local defs, om = load_catalog()
        local mod = {}
        function mod:dofile(path)
            return dofile(repo_root .. "/character_weapon_variants/" .. path .. ".lua")
        end
        function mod:hook() end
        function mod:info() end
        function mod:warning() end
        with_globals({ ItemMasterList = {}, get_mod = function() return nil end }, function()
            dofile(root .. "_cwv_variant_bootstrap_owner.lua")(mod, { om = om, variant_definitions = defs })
        end)
        H.equal(type(om.display_names), "table", "bootstrap owner did not publish _om.display_names")
        H.equal(om.display_names.cwv_imperial_longsword, "Imperial Longsword")
        H.equal(om.display_names.cwv_es_longsword_nordland_skin_name, "Helmgart Watchsword")
    end)

    H.test("CWV #1656 dbg_helpers_two_channel drives the context's dbg_alert", function()
        local alerts = {}
        local checks = install_render({}, {}, {
            dbg_alert = function(fmt) alerts[#alerts + 1] = fmt end,
        })
        H.equal(checks.dbg_helpers_two_channel(), nil)
        H.equal(alerts[1], "smoke test", "the check must exercise the entry helper it was handed")
        -- Unwired helper still fails loudly.
        local unwired = install_render({}, {}, {})
        H.equal(unwired.dbg_helpers_two_channel(), "_dbg_alert helper missing")
    end)

    -- ------------------------------------------------------------------------------------
    -- Fixture selection (pure module) against the real catalog.
    -- ------------------------------------------------------------------------------------

    -- GUARD, not fix evidence: this needle passes on the pre-fix base too. It pins
    -- registered_set() above to the registrar's predicate so the other cases stay honest.
    H.test("CWV #1656 registration predicate is still the registrar's", function()
        local registration = read("_cwv_item_registration_owner.lua")
        H.truthy(registration:find("if def.skin_only or def.cwv_retired then", 1, true),
            "registration no longer skips skin_only/cwv_retired; update registered_set()")
        H.truthy(registration:find(
            "if type(candidate) ~= \"string\" or not _registered_keys[candidate] then return nil end", 1, true))
    end)

    H.test("CWV #1656 fixture owner is a registered melee def, never a retired one", function()
        local fixtures = dofile(root .. "_cwv_regression_fixtures.lua")
        local defs = load_catalog()
        local registered = registered_set(defs)
        local item_master, weapon_skins = engine_tables(defs)
        local fx = fixtures.registered_owner(defs, registered, item_master, weapon_skins)
        H.truthy(fx, "no fixture chosen from the real catalog")
        H.equal(fx.key, "cwv_es_axe_shield", "first eligible def in authored order")
        H.equal(fx.base, "dr_shield_axe")
        H.equal(fx.skin, "cwv_es_axe_shield_skin")
        H.equal(fx.def, find_in(defs)("cwv_es_axe_shield"))
        -- Walk the selection down the whole catalog: it must never land on a def the
        -- registrar skips, a cross-slot def or a ranged base.
        local remaining = {}
        for key in pairs(registered) do remaining[key] = true end
        local seen = 0
        while true do
            local pick = fixtures.registered_owner(defs, remaining, item_master, weapon_skins)
            if not pick then break end
            seen = seen + 1
            H.truthy(not pick.def.cwv_retired and not pick.def.skin_only and not pick.def.cross_slot)
            H.equal(item_master[pick.base].slot_type, "melee")
            remaining[pick.key] = nil
        end
        H.truthy(seen > 10, "most catalog melee defs are eligible fixtures")
        H.equal(fixtures.registered_owner(defs, {}, item_master, weapon_skins), nil)
        H.equal(fixtures.registered_owner(defs, registered, item_master, nil), nil)
        local retired_only = { cwv_es_longsword = true, cwv_es_longsword_blackguard = true,
            cwv_es_longsword_nordland = true }
        H.equal(fixtures.registered_owner(defs, retired_only, item_master, weapon_skins), nil,
            "a retired/skin-only key can never become a fixture even if marked registered")
    end)

    H.test("CWV #1656 generated pair skin is read from generator output", function()
        local fixtures = dofile(root .. "_cwv_regression_fixtures.lua")
        local owner = "cwv_es_sword_and_mace"
        local item_master = {
            [owner .. "_skin"] = { cwv_owner_item_type = owner },
            [owner .. "_wpn_b_wpn_c"] = { cwv_owner_item_type = owner },
            [owner .. "_wpn_a_wpn_d"] = { cwv_owner_item_type = owner },
            [owner .. "_wpn_0_onehand"] = { cwv_owner_item_type = owner },
            [owner .. "_wpn_0_foreign"] = { cwv_owner_item_type = "cwv_es_dual_swords" },
            cwv_es_dual_swords_wpn_x = { cwv_owner_item_type = owner },
        }
        local weapon_skins = { skins = {
            [owner .. "_skin"] = { right_hand_unit = "r", left_hand_unit = "l" },
            [owner .. "_wpn_b_wpn_c"] = { right_hand_unit = "b", left_hand_unit = "c" },
            [owner .. "_wpn_a_wpn_d"] = { right_hand_unit = "a", left_hand_unit = "d" },
            [owner .. "_wpn_0_onehand"] = { right_hand_unit = "o" },
            [owner .. "_wpn_0_foreign"] = { right_hand_unit = "f", left_hand_unit = "g" },
            cwv_es_dual_swords_wpn_x = { right_hand_unit = "x", left_hand_unit = "y" },
        } }
        H.equal(fixtures.generated_pair_skin(item_master, weapon_skins, owner), owner .. "_wpn_a_wpn_d")
        item_master[owner .. "_wpn_a_wpn_d"] = nil
        H.equal(fixtures.generated_pair_skin(item_master, weapon_skins, owner), owner .. "_wpn_b_wpn_c")
        item_master[owner .. "_wpn_b_wpn_c"] = nil
        H.equal(fixtures.generated_pair_skin(item_master, weapon_skins, owner), nil,
            "the default skin, one-handed rows and foreign owners are never pairs")
        H.equal(fixtures.generated_pair_skin(nil, weapon_skins, owner), nil)
    end)

    -- ------------------------------------------------------------------------------------
    -- Identity checks: #660, #396, #416 against a registration-faithful lifecycle world.
    -- ------------------------------------------------------------------------------------

    -- Loaded tolerantly here only so a pre-fix tree reaches each check's own verdict; the
    -- fixture-owner case above requires the module outright.
    local function fixtures_or_nil()
        local chunk = loadfile(root .. "_cwv_regression_fixtures.lua")
        return chunk and chunk() or nil
    end

    local function identity_world(opts)
        opts = opts or {}
        local defs, catalog_om = load_catalog()
        local find_def = find_in(defs)
        local registered = registered_set(defs)
        local item_master, weapon_skins = engine_tables(defs)
        for key, row in pairs(opts.extra_item_master or {}) do item_master[key] = row end
        for key, row in pairs(opts.extra_skins or {}) do weapon_skins.skins[key] = row end
        local policy = dofile(root .. "_cwv_appearance_lifecycle.lua")
        local exact = dofile(root .. "_cwv_exact_appearance.lua")
        local function world_descriptor(key, skin, instance_id)
            local def = find_def(key)
            local base = def and item_master[def.base_weapon]
            if not base then return nil, "base_missing" end
            return exact.resolve_spawn_descriptor({
                provider = "cwv", instance_id = instance_id, variant = def, base = base,
                base_item_key = def.base_weapon, fallback_item_key = def.base_weapon,
                explicit_skin = skin, weapon_skins = weapon_skins.skins, item_master = item_master,
            })
        end
        -- Adapters as _cwv_item_identity_transport_owner.lua:213-291 shapes them; the local
        -- side answers only for a REGISTERED key (the #482 ladder gate, registration :130-133).
        local lifecycle = policy.new({
            resolve_local = function(slot_data)
                local item = slot_data and slot_data.item_data
                if not item then return nil, nil end
                local key = registered[item.cwv_key] and item.cwv_key or nil
                if not key then return nil, item.name end
                return world_descriptor(key, slot_data.skin), item.name
            end,
            resolve_remote = function(payload, peer_id)
                local def = find_def(payload.item_key)
                if not def or def.skin_only or def.base_weapon ~= payload.base_item_key then
                    return nil, "item_or_base"
                end
                return world_descriptor(def.item_key, payload.skin_key ~= "" and payload.skin_key or nil,
                    tostring(peer_id) .. ":" .. tostring(payload.slot))
            end,
            send = function() return true end,
        })
        local om = {
            appearance_lifecycle_policy = policy,
            _appearance_lifecycle = lifecycle,
            _cwv_identity_payloads = function(slots)
                local payloads = {}
                for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
                    local payload = lifecycle:payload_for(slot_name, slots[slot_name])
                    if payload then payloads[#payloads + 1] = payload end
                end
                return payloads
            end,
            _cwv_accept_identity = function(peer, schema, payload) return lifecycle:accept(peer, schema, payload) end,
            _cwv_identity_descriptor_for_peer = function(peer, slot, base) return lifecycle:descriptor(peer, slot, base) end,
            _cwv_request_peer_identities = function() end,
            _husk_resolve_display_def = function(base, _, skin)
                local def = skin and find_def(skin:gsub("_skin$", ""))
                if def and def.base_weapon == base then return def, "skin" end
                return nil, "skin_foreign"
            end,
            _wire_null_skins = function(slots, send)
                local saved = {}
                for index, slot in ipairs(slots) do saved[index] = slot.skin; slot.skin = nil end
                send()
                for index, slot in ipairs(slots) do slot.skin = saved[index] end
            end,
        }
        om._cwv_identity_def_for_peer = function(peer, slot, base)
            local descriptor, state = lifecycle:descriptor(peer, slot, base)
            return descriptor and find_def(descriptor.variant_key), state
        end
        local mod = {
            _cwv_identity_surfaces = {
                network = true, game_object_initialized = true, spawn_resynced_loadout = true,
                hot_join_sync = true, peer_ready = true, mission_transition_peer_pull = true,
                mission_transition = true,
            },
            _cwv_skin_wire_surfaces = { vanilla_skin_replay_retired = true },
            _cwv_preview_meshswap_apply = function() end,
        }
        local display_names = {
            cwv_imperial_longsword = "Imperial Longsword",
            cwv_es_longsword_nordland_skin_name = "Helmgart Watchsword",
        }
        local ctx = {
            mod_version = "qa-1656", om = om, dbg = function() end,
            variant_definitions = defs, registered_keys = registered,
            display_names = display_names,
            regression_fixtures = fixtures_or_nil(),
            find_def = find_def, build_entry = function() end, auto_register_all = function() end,
            cross_access_action_remap = {}, wield_hook_registration_count = 1,
            issue719_transaction_check = function() end,
        }
        local globals = { ItemMasterList = item_master, WeaponSkins = weapon_skins }
        return mod, ctx, globals, catalog_om
    end

    H.test("CWV #1656 issue660 replays the lifecycle on a registered owner", function()
        local mod, ctx, globals = identity_world()
        with_globals(globals, function()
            H.equal(run_identity_check("issue660_world_identity_lifecycle_replay", mod, ctx), nil)
        end)
        -- Registration premise removed: the check must fail loudly, not pass on nothing.
        local mod2, ctx2, globals2 = identity_world()
        for key in pairs(ctx2.registered_keys) do ctx2.registered_keys[key] = nil end
        with_globals(globals2, function()
            local verdict = run_identity_check("issue660_world_identity_lifecycle_replay", mod2, ctx2)
            H.equal(type(verdict), "string")
        end)
    end)

    H.test("CWV #1656 issue396 keeps the Longsword facts and runs transport on a registered owner", function()
        local mod, ctx, globals = identity_world()
        with_globals(globals, function()
            H.equal(run_identity_check("issue396_imperial_longsword_identity_and_remote_husk", mod, ctx), nil)
        end)
        local mod2, ctx2, globals2 = identity_world()
        ctx2.display_names = {}
        with_globals(globals2, function()
            H.equal(run_identity_check("issue396_imperial_longsword_identity_and_remote_husk", mod2, ctx2),
                "weapon-family and illusion localization keys are conflated")
        end)
    end)

    H.test("CWV #1656 issue416_483 derives its Sword+Mace pair from the generator", function()
        local owner = "cwv_es_sword_and_mace"
        -- The tester's session: eight pairs registered, none of them the old hand-composed key.
        local extra_iml, extra_skins = {}, {}
        for index = 1, 8 do
            local key = owner .. "_wpn_emp_sword_0" .. index .. "_t2_wpn_emp_mace_0" .. index .. "_t2"
            extra_iml[key] = { cwv_owner_item_type = owner }
            extra_skins[key] = { right_hand_unit = "units/sword_" .. index, left_hand_unit = "units/mace_" .. index }
        end
        local mod, ctx, globals = identity_world({ extra_item_master = extra_iml, extra_skins = extra_skins })
        with_globals(globals, function()
            H.equal(run_identity_check("issue416_483_transition_generated_skin_identity", mod, ctx), nil)
        end)
        local mod2, ctx2, globals2 = identity_world()
        with_globals(globals2, function()
            H.equal(run_identity_check("issue416_483_transition_generated_skin_identity", mod2, ctx2),
                "no generated Sword+Mace pair illusion with both hands is registered")
        end)
    end)

    -- ------------------------------------------------------------------------------------
    -- cwv_key_resolution_uuid_safe rung 3 against the registration owner's own ladder.
    -- ------------------------------------------------------------------------------------

    local function production_ladder(registered_entries)
        local registration = read("_cwv_item_registration_owner.lua")
        local from = assert(registration:find("local function _registered_cwv_key(candidate)", 1, true))
        local ladder_at = assert(registration:find("_om._cwv_key_for_item = function(backend_id, item_data)", from, true))
        local block = registration:sub(from, assert(registration:find("\nend\n", ladder_at, true)) + 4)
        local om = {}
        local chunk = assert(loadstring("local _registered_keys, _om, printf, Managers = ...\n" .. block, "@ladder"))
        chunk(registered_entries, om, function() end, nil)
        return assert(om._cwv_key_for_item)
    end

    H.test("CWV #1656 cwv_key_resolution_uuid_safe pins a registered legacy key", function()
        local defs = load_catalog()
        local registered = registered_set(defs)
        local iml = {}
        for key in pairs(registered) do iml[key] = { cwv_key = key } end
        local entries = {}
        for key in pairs(registered) do entries[key] = iml[key] end
        local owner = assert(loadfile(root .. "_cwv_regression_runtime_identity.lua"))()
        local rows = owner({
            mod = {}, om = { _cwv_key_for_item = production_ladder(entries) },
            variant_definitions = defs, find_def = find_in(defs), build_entry = function() end,
            auto_register_all = function() end, cross_access_action_remap = {},
            wield_hook_registration_count = 1,
        })
        local check
        for _, row in ipairs(rows) do
            if row.name == "cwv_key_resolution_uuid_safe" then check = row.fn end
        end
        H.equal(type(check), "function")
        with_globals({ ItemMasterList = iml }, function()
            H.equal(check(), nil)
        end)
    end)

    -- ------------------------------------------------------------------------------------
    -- Render checks: #604 multi-return and the #423 Crowbill wire contract.
    -- ------------------------------------------------------------------------------------

    H.test("CWV #1656 issue604 control leg keeps the selector's source", function()
        local family = dofile(root .. "_cwv_crowbill_family.lua")
        local policy = dofile(root .. "_cwv_husk_transform_policy.lua")
        local by_unit, by_variant, skin_map, unit_map, variant_map = {}, {}, {}, {}, {}
        for _, model in ipairs(family.MODELS) do
            local applied = {}
            for key, value in pairs(model) do applied[key] = value end
            applied.crowbill_model_key = model.key
            by_unit[model.right_hand_unit] = applied
            skin_map[model.key] = applied
            unit_map[model.right_hand_unit] = applied
            unit_map[model.right_hand_unit .. "_3p"] = applied
            if not by_variant[model.variant_key] then
                by_variant[model.variant_key] = model
                variant_map[model.variant_key] = applied
            end
        end
        local bound = policy.bind({
            find_def = function(key) return by_variant[key] end,
            resolve_def = function() return nil end,
            plan_transform = function(def, hand, perspective)
                local prefix = hand == "left" and "left_hand_" or "right_hand_"
                local function field(name)
                    return def[prefix .. name .. "_" .. perspective] or def[prefix .. name]
                end
                local scale, scale_multiplier = field("scale"), field("scale_multiplier")
                local offset, rotation = field("offset"), field("rotation")
                return { scale = scale, scale_multiplier = scale_multiplier, offset = offset,
                    rotation = rotation,
                    should_apply = (scale or scale_multiplier or offset or rotation) and true or false }
            end,
            model_by_unit = by_unit,
        })
        local om = {
            _cwv_select_husk_transform_def = bound.select,
            _cwv_husk_transform_apply_plan = bound.plan,
            _cwv_resolve_crowbill_transform = function() end,
            _cwv_crowbill_transform_delivery = {},
            _cwv_crowbill_transform_evidence = {
                stats = function() return { limit = 96, per_model_limit = 16, count = 0 } end,
            },
        }
        local checks = install_render({ _cwv_crowbill_family = family }, om, {
            skin_transform_map = skin_map, transform_map = variant_map, crowbill_transform_by_unit = unit_map,
        })
        H.equal(checks.issue604_dawi_crowbill_model01_transform(), nil)
    end)

    H.test("CWV #1656 Crowbill hammer contract asserts the #423 shared vanilla donor", function()
        local family = dofile(root .. "_cwv_crowbill_family.lua")
        local policy = dofile(root .. "_cwv_crowbill_hammer_mode.lua")
        local runtime = dofile(root .. "_cwv_crowbill_runtime.lua")
        local entry = read("character_weapon_variants.lua")
        local from = assert(entry:find("_om._cwv_damage_profile_wire_source = {}", 1, true))
        local fn_at = assert(entry:find("function _om._record_cwv_dp_source(cwv_key, source_name)", from, true))
        local recorder = assert(loadstring("local _om = ...\n"
            .. entry:sub(from, assert(entry:find("\nend\n", fn_at, true)) + 4), "@recorder"))
        local function clone(value, seen)
            if type(value) ~= "table" then return value end
            seen = seen or {}
            if seen[value] then return seen[value] end
            local copy = {}
            seen[value] = copy
            for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
            return copy
        end
        local action_one, damage_profiles, power_levels = {}, {}, {}
        for action_name in pairs(policy.DIRECT_ACTIONS) do
            local profile = "fixture_" .. action_name
            action_one[action_name] = { kind = "sweep", damage_profile = profile, anim_time_scale = 1.1,
                total_time = 1.5, allowed_chain_actions = {} }
            damage_profiles[profile] = { cleave_distribution = "cleave_" .. profile,
                armor_modifier = "armor_" .. profile, default_target = "target_" .. profile,
                targets = "targets_" .. profile }
            power_levels["cleave_" .. profile] = { attack = 1, impact = 1 }
            power_levels["armor_" .. profile] = { attack = { 1, 0.5, 1, 1, 1, 0.5 } }
            power_levels["target_" .. profile] = { power_distribution = { attack = 1, impact = 1 } }
            power_levels["targets_" .. profile] = { { power_distribution = { attack = 1, impact = 1 } } }
        end
        local saved_clone = table.clone
        table.clone = function(value) return clone(value) end
        local ok, err = pcall(with_globals, {
            Weapons = { [policy.SOURCE_TEMPLATE_KEY] = { actions = { action_one = action_one } } },
            DamageProfileTemplates = damage_profiles, PowerLevelTemplates = power_levels,
            NetworkLookup = { damage_profiles = {} },
        }, function()
            local om = { crowbill_hammer_mode = policy, crowbill_family = family,
                _cwv_key_for_item = function(_, item) return item.cwv_key end }
            recorder(om)
            local fake_mod = {
                _cwv_old_musket_interrupt = { install = function(template)
                    for _, action in pairs(template.actions.action_one) do
                        action.allowed_chain_actions[#action.allowed_chain_actions + 1] =
                            { action = "action_three", input = "action_three", start_time = 0 }
                    end
                end },
                get = function() return nil end,
                network_register = function() end,
            }
            H.truthy(runtime.install(fake_mod, om))
            local checks = install_render({ _cwv_crowbill_runtime = runtime,
                _cwv_crowbill_hammer_mode = policy }, om)
            H.equal(checks.cwv_crowbill_hammer_runtime_contract(), nil)
            -- Dropping the fallback for one face must still fail the contract.
            for action_name in pairs(policy.DIRECT_ACTIONS) do
                local hammer = rawget(_G, "Weapons")[policy.HAMMER_TEMPLATE_KEY].actions.action_one[action_name]
                om._cwv_damage_profile_wire_source[hammer.damage_profile] = nil
                break
            end
            local verdict = checks.cwv_crowbill_hammer_runtime_contract()
            H.truthy(type(verdict) == "string" and verdict:find("mixed%-peer damage fallback missing"),
                "a face without a vanilla fallback must fail: " .. tostring(verdict))
        end)
        table.clone = saved_clone
        if not ok then error(err, 0) end
    end)

    H.test("CWV #1656 Crowbill hammer contract binds the shared donor to the source action's own profile", function()
        local family = dofile(root .. "_cwv_crowbill_family.lua")
        local policy = dofile(root .. "_cwv_crowbill_hammer_mode.lua")
        local runtime = dofile(root .. "_cwv_crowbill_runtime.lua")
        local entry = read("character_weapon_variants.lua")
        local from = assert(entry:find("_om._cwv_damage_profile_wire_source = {}", 1, true))
        local fn_at = assert(entry:find("function _om._record_cwv_dp_source(cwv_key, source_name)", from, true))
        local recorder = assert(loadstring("local _om = ...\n"
            .. entry:sub(from, assert(entry:find("\nend\n", fn_at, true)) + 4), "@recorder"))
        local function clone(value, seen)
            if type(value) ~= "table" then return value end
            seen = seen or {}
            if seen[value] then return seen[value] end
            local copy = {}
            seen[value] = copy
            for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
            return copy
        end
        -- Vanilla shape: light_attack_left carries the burning stab
        -- (1h_crowbills.lua:684), whose wire donor is the non-burning twin.
        local action_one, damage_profiles, power_levels = {}, {}, {}
        for action_name in pairs(policy.DIRECT_ACTIONS) do
            local profile = action_name == "light_attack_left" and policy.BURNING_STAB_PROFILE
                or "fixture_" .. action_name
            action_one[action_name] = { kind = "sweep", damage_profile = profile, anim_time_scale = 1.1,
                total_time = 1.5, allowed_chain_actions = {} }
        end
        for _, profile in ipairs({ policy.BURNING_STAB_PROFILE, policy.NONBURNING_STAB_PROFILE,
                "fixture_heavy_attack", "fixture_heavy_attack_left", "fixture_heavy_attack_right_up",
                "fixture_light_attack_right", "fixture_light_attack_last", "fixture_light_attack_upper",
                "fixture_light_attack_bopp", "fixture_unrelated" }) do
            damage_profiles[profile] = { cleave_distribution = "cleave_" .. profile,
                armor_modifier = "armor_" .. profile, default_target = "target_" .. profile,
                targets = "targets_" .. profile }
            power_levels["cleave_" .. profile] = { attack = 1, impact = 1 }
            power_levels["armor_" .. profile] = { attack = { 1, 0.5, 1, 1, 1, 0.5 } }
            power_levels["target_" .. profile] = { power_distribution = { attack = 1, impact = 1 } }
            power_levels["targets_" .. profile] = { { power_distribution = { attack = 1, impact = 1 } } }
        end
        local saved_clone = table.clone
        table.clone = function(value) return clone(value) end
        local ok, err = pcall(with_globals, {
            Weapons = { [policy.SOURCE_TEMPLATE_KEY] = { actions = { action_one = action_one } } },
            DamageProfileTemplates = damage_profiles, PowerLevelTemplates = power_levels,
            NetworkLookup = { damage_profiles = {} },
        }, function()
            local om = { crowbill_hammer_mode = policy, crowbill_family = family,
                _cwv_key_for_item = function(_, item) return item.cwv_key end }
            recorder(om)
            local fake_mod = {
                _cwv_old_musket_interrupt = { install = function(template)
                    for _, action in pairs(template.actions.action_one) do
                        action.allowed_chain_actions[#action.allowed_chain_actions + 1] =
                            { action = "action_three", input = "action_three", start_time = 0 }
                    end
                end },
                get = function() return nil end,
                network_register = function() end,
            }
            H.truthy(runtime.install(fake_mod, om))
            local checks = install_render({ _cwv_crowbill_runtime = runtime,
                _cwv_crowbill_hammer_mode = policy }, om)
            H.equal(checks.cwv_crowbill_hammer_runtime_contract(), nil,
                "the burning stab's non-burning wire donor is the source action's own profile")
            local weapons = rawget(_G, "Weapons")
            local wire = om._cwv_damage_profile_wire_source
            local pick = weapons[runtime.PICK_TEMPLATE_KEY].actions.action_one.heavy_attack
            local hammer = weapons[policy.HAMMER_TEMPLATE_KEY].actions.action_one.heavy_attack
            -- Both faces agreeing on the WRONG vanilla profile must still fail.
            wire[pick.damage_profile], wire[hammer.damage_profile] = "fixture_unrelated", "fixture_unrelated"
            local verdict = checks.cwv_crowbill_hammer_runtime_contract()
            H.truthy(type(verdict) == "string"
                and verdict:find("is not the source action's vanilla profile", 1, true),
                "a shared but foreign donor must fail: " .. tostring(verdict))
            -- The right donor that DamageProfileTemplates no longer carries must fail.
            wire[pick.damage_profile], wire[hammer.damage_profile] = "fixture_heavy_attack", "fixture_heavy_attack"
            H.equal(checks.cwv_crowbill_hammer_runtime_contract(), nil)
            damage_profiles.fixture_heavy_attack = nil
            verdict = checks.cwv_crowbill_hammer_runtime_contract()
            H.truthy(type(verdict) == "string"
                and verdict:find("names an unregistered or cwv_ profile", 1, true),
                "an unregistered donor must fail: " .. tostring(verdict))
        end)
        table.clone = saved_clone
        if not ok then error(err, 0) end
    end)
end
