-- Boundary tests for _cim_weave_loadout_owner (#1159 cim_dev decomposition).
--
-- This owner is the slice that brought the cim_dev entry under the 2500-line
-- hard limit, so it is also the slice with the most ways to be silently wrong.
-- The tests lock five things a structural move can break: the seam (one
-- install, between the immutable-relic UI and the EAC commit block), the hook
-- set (exactly the ten MUTABLE BackendInterfaceWeavesPlayFab registrations, and
-- nothing the sibling owners already hold), the injected-accessor contract (all
-- four entry stores are read LIVE, never snapshotted), the forward-declaration
-- coupling the entry still needs for `_bubble_cap`, and the bubble-cap math the
-- Athanor's grid occupancy depends on.
return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local entry = read("crafting_in_modded_dev.lua")
    local owner = read("_cim_weave_loadout_owner.lua")
    local wire_owner = read("_cim_loadout_wire_owner.lua")

    local function load_owner()
        return assert(loadfile(root .. "_cim_weave_loadout_owner.lua"))()
    end
    local function load_temper_runtime()
        return assert(loadfile(root .. "_cim_temper_runtime.lua"))()
    end
    local temper_transaction = assert(loadfile(
        root .. "_cim_temper_transaction.lua"))()

    -- Stand-in for the VMF mod object. Records every registration so hook
    -- cardinality and order can be asserted directly, and serves the two
    -- dofile'd dependencies the moved body pulls at install time.
    local function fake_mod(settings)
        local m = {
            hooks = {}, dofiles = {}, settings_installs = 0,
            _settings = settings or {}, messages = {}, checks = {},
        }
        function m:hook(target, method)
            self.hooks[#self.hooks + 1] = { target = target, method = method, kind = "hook" }
        end
        function m:hook_safe(target, method)
            self.hooks[#self.hooks + 1] = { target = target, method = method, kind = "hook_safe" }
        end
        function m:command(name) self.commands = self.commands or {}; self.commands[#self.commands + 1] = name end
        function m:get(key) return self._settings[key] end
        function m:set(key, value) self._settings[key] = value end
        function m:info(message)
            self.messages[#self.messages + 1] = { kind = "info", text = message }
        end
        function m:warning(message)
            self.messages[#self.messages + 1] = { kind = "warning", text = message }
        end
        function m:echo(message)
            self.messages[#self.messages + 1] = { kind = "echo", text = message }
        end
        function m:dofile(path)
            self.dofiles[#self.dofiles + 1] = path
            return {
                install = function()
                    m.settings_installs = m.settings_installs + 1
                end,
            }
        end
        return m
    end

    local function install_owner(mod, stores)
        stores = stores or {}
        local install = load_owner()
        return install({
            mod = mod,
            is_active = stores.is_active or function() return false end,
            get_forge_item_props = stores.get_forge_item_props or function() return {} end,
            get_forged_weapons = stores.get_forged_weapons or function() return {} end,
            get_amulet_dirty = stores.get_amulet_dirty or function() return { false, false, false } end,
            forge_save = stores.forge_save or function() end,
            temper_transaction = stores.temper_transaction or temper_transaction,
            get_raw_mirror_item = stores.get_raw_mirror_item or function() return nil end,
        })
    end

    -- `_cap_grid_property_arrays` reports over-occupancy through the engine's
    -- raw printf before it trims. Supply that one global for the duration.
    local function with_printf(body)
        local saved = rawget(_G, "printf")
        local lines = {}
        rawset(_G, "printf", function(fmt, ...) lines[#lines + 1] = tostring(fmt) end)
        local ok, err = pcall(body, lines)
        rawset(_G, "printf", saved)
        if not ok then error(err, 0) end
        return lines
    end

    -- The seed pass reaches the backend items interface directly, exactly as it
    -- did in the entry. Supply the narrowest stand-in that lets it run.
    local function with_backend(items, body)
        local saved = rawget(_G, "Managers")
        rawset(_G, "Managers", {
            backend = { get_interface = function() return items end },
        })
        local ok, err = pcall(body)
        rawset(_G, "Managers", saved)
        if not ok then error(err, 0) end
    end

    local function count_message(mod, kind, fragment)
        local count = 0
        for _, message in ipairs(mod.messages or {}) do
            if message.kind == kind
                    and (not fragment
                        or tostring(message.text):find(fragment, 1, true)) then
                count = count + 1
            end
        end
        return count
    end

    -- Compose the real mutable-loadout owner with the real Temper button hook.
    -- The contract adapter is deliberately narrow: this suite owns the Apply
    -- publication transaction, while the identity validator's adversarial
    -- matrix lives in test_cim_temper_runtime.lua.
    local function run_apply_hook(options)
        options = options or {}
        local mod = fake_mod()
        local hooked, safe_hooked = {}, {}
        function mod:hook(_, method, fn) hooked[method] = fn end
        function mod:hook_safe(_, method, fn) safe_hooked[method] = fn end

        local old_item_properties = { power_vs_skaven = 0.4 }
        local old_item_traits = { "old_trait" }
        local old_custom_data = {
            properties = options.noop and "encoded-properties" or "old-properties-json",
            traits = options.noop and "encoded-traits" or "old-traits-json",
            sentinel = "preserve-custom",
        }
        local item = {
            rarity = "modded",
            properties = old_item_properties,
            traits = old_item_traits,
            CustomData = old_custom_data,
            cim_injection_owner = "crafting_in_modded",
            sentinel = "preserve-cache",
        }
        -- The native item interface may hold a deep-cloned cache.  Keep the raw
        -- mirror row deliberately distinct so the test catches cache-only Apply.
        local old_raw_properties = { power_vs_skaven = 0.4 }
        local old_raw_traits = { "old_trait" }
        local old_raw_custom_data = {
            properties = options.noop and "encoded-properties" or "old-properties-json",
            traits = options.noop and "encoded-traits" or "old-traits-json",
            sentinel = "preserve-raw-custom",
        }
        local raw_item = {
            rarity = "modded",
            properties = old_raw_properties,
            traits = old_raw_traits,
            CustomData = old_raw_custom_data,
            cim_injection_owner = "crafting_in_modded",
            sentinel = "preserve-raw",
        }
        local old_saved_properties = { power_vs_skaven = 0.4 }
        local old_saved_traits = { "old_trait" }
        local old_external_traits = options.noop and {} or { "parked_trait" }
        local record = {
            item_key = "es_sword",
            properties = old_saved_properties,
            traits = old_saved_traits,
            trait = "old_trait",
            external_traits = old_external_traits,
            sentinel = "preserve-record",
        }
        local records = { bid = record }
        local slot_count = options.noop and 2 or 3
        local draft = {
            properties = {
                weave_power_vs_skaven = slot_count == 2
                    and { 1, 2 } or { 1, 2, 3 },
            },
            traits = { weave_old_trait = 1 },
        }
        local drafts = { ["es_mercenary|bid"] = draft }
        local saves, refreshes, candidate_seen = 0, 0, nil
        local items_backend = {
            get_item_from_id = function(_, backend_id)
                return backend_id == "bid" and item or nil
            end,
            _refresh = function()
                refreshes = refreshes + 1
                -- Model the native cache rebuilding from raw mirror authority.
                item.properties = {
                    power_vs_skaven = raw_item.properties.power_vs_skaven,
                }
                item.traits = { raw_item.traits[1] }
                item.CustomData.properties = raw_item.CustomData.properties
                item.CustomData.traits = raw_item.CustomData.traits
            end,
        }
        local exports = install_owner(mod, {
            is_active = function() return true end,
            get_forge_item_props = function() return drafts end,
            get_forged_weapons = function() return records end,
            forge_save = function(candidate)
                saves = saves + 1
                candidate_seen = candidate
                H.equal(item.properties, old_item_properties,
                    "live properties published before persistence")
                H.equal(item.traits, old_item_traits,
                    "live traits published before persistence")
                H.equal(item.CustomData, old_custom_data,
                    "CustomData published before persistence")
                H.equal(raw_item.properties, old_raw_properties,
                    "raw mirror properties published before persistence")
                H.equal(raw_item.traits, old_raw_traits,
                    "raw mirror traits published before persistence")
                H.equal(raw_item.CustomData, old_raw_custom_data,
                    "raw mirror CustomData published before persistence")
                H.equal(record.properties, old_saved_properties,
                    "saved properties published before persistence")
                H.equal(record.traits, old_saved_traits,
                    "saved traits published before persistence")
                H.equal(record.external_traits, old_external_traits,
                    "parked traits published before persistence")
                if options.save_throw then error("save exploded") end
                if options.save_reject then return false, "save denied" end
            end,
            get_raw_mirror_item = function(backend_id)
                if options.raw_accessor_throw then
                    error("raw mirror accessor exploded")
                end
                if options.raw_missing then return nil end
                return backend_id == "bid" and raw_item or nil
            end,
        })

        local applies, discards, apply_ok, apply_detail = 0, 0, nil, nil
        local loadout = {}
        for key, value in pairs(exports) do loadout[key] = value end
        loadout.apply_item_draft = function(...)
            applies = applies + 1
            apply_ok, apply_detail = exports.apply_item_draft(...)
            return apply_ok, apply_detail
        end
        loadout.discard_item_draft = function(...)
            discards = discards + 1
            return exports.discard_item_draft(...)
        end

        local contract = {
            validate_temper_owned_instance = function() return true end,
            temper_source_requires_cwv_provider = function() return false end,
            resolve_temper_craft_source = function()
                return nil, "craft path must remain unreachable"
            end,
            is_cwv_provider_key = function() return false end,
            validate_mirror_ownership_token = function() return true end,
            rollback_mirror_item = function() return true end,
        }
        local syncs, sounds = 0, 0
        load_temper_runtime()({
            mod = mod,
            is_active = function() return true end,
            transaction = temper_transaction,
            contract = contract,
            loadout = loadout,
            get_forged_record = function(backend_id)
                return records[backend_id]
            end,
            get_item_master = function() return { key = "es_sword" } end,
            get_raw_mirror_item = function() return raw_item end,
            bulk_accessory_craft = { craft_all = function() return 0 end },
            craft_accessory = function() return false end,
            inject_item = function() error("Apply must not inject") end,
            rt_register = function(name, fn) mod.checks[name] = fn end,
            print_line = function() end,
        })
        local window = {
            _career_name = "es_mercenary",
            _selected_item = function() return item, "bid" end,
            _sync_backend_loadout = function() syncs = syncs + 1 end,
            _play_sound = function() sounds = sounds + 1 end,
        }

        local saved_managers = rawget(_G, "Managers")
        local saved_cjson = rawget(_G, "cjson")
        rawset(_G, "Managers", {
            backend = { get_interface = function() return items_backend end },
        })
        if options.cjson_missing then
            rawset(_G, "cjson", nil)
        else
            rawset(_G, "cjson", {
                encode = function(value)
                    if options.encode_throw then error("encode exploded") end
                    return #value > 0 and "encoded-traits" or "encoded-properties"
                end,
            })
        end
        local call_ok, call_error = pcall(
            hooked._upgrade_magic_level,
            function() error("vanilla Apply must not run") end, window)
        rawset(_G, "Managers", saved_managers)
        rawset(_G, "cjson", saved_cjson)

        return {
            mod = mod,
            call_ok = call_ok,
            call_error = call_error,
            item = item,
            raw_item = raw_item,
            record = record,
            records = records,
            draft = draft,
            drafts = drafts,
            old_item_properties = old_item_properties,
            old_item_traits = old_item_traits,
            old_custom_data = old_custom_data,
            old_raw_properties = old_raw_properties,
            old_raw_traits = old_raw_traits,
            old_raw_custom_data = old_raw_custom_data,
            old_saved_properties = old_saved_properties,
            old_saved_traits = old_saved_traits,
            old_external_traits = old_external_traits,
            saves = saves,
            refreshes = refreshes,
            refresh = function() return items_backend:_refresh() end,
            get_refreshes = function() return refreshes end,
            candidate_seen = candidate_seen,
            applies = applies,
            discards = discards,
            apply_ok = apply_ok,
            apply_detail = apply_detail,
            syncs = syncs,
            sounds = sounds,
            safe_hooked = safe_hooked,
        }
    end

    local MUTABLE_HOOKS = {
        "get_loadout_properties", "get_loadout_traits", "get_loadout_talents",
        "get_mastery", "set_loadout_property", "remove_loadout_property",
        "set_loadout_trait", "remove_loadout_trait", "set_loadout_talent",
        "remove_loadout_talent",
    }

    H.test("CIM weave-loadout owner installs exactly once at the original seam", function()
        H.equal(count_plain(entry,
            "scripts/mods/crafting_in_modded_dev/_cim_weave_loadout_owner"), 1)

        -- The block used to execute between the immutable-relic UI install and
        -- the BackendManagerPlayFab commit suppression. It must also stay BELOW
        -- _cim_weave_economy, whose cost hook closes over the `_bubble_cap`
        -- upvalue this owner binds.
        local economy_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_weave_economy", 1, true))
        local relic_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_immutable_relic_ui", 1, true))
        local seam_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_weave_loadout_owner", 1, true))
        local commit_at = assert(entry:find(
            'mod:hook("BackendManagerPlayFab", "commit"', 1, true))
        H.truthy(economy_at < seam_at, "economy facade installs above the seam")
        H.truthy(relic_at < seam_at, "seam must follow the immutable-relic UI install")
        H.truthy(seam_at < commit_at, "seam must precede the commit suppression")
    end)

    H.test("CIM weave-loadout owner is the sole home of the ten mutable weave hooks", function()
        for _, method in ipairs(MUTABLE_HOOKS) do
            local needle = 'mod:hook("BackendInterfaceWeavesPlayFab", "' .. method .. '"'
            H.equal(count_plain(owner, needle), 1, "owner must own " .. method)
            H.equal(count_plain(entry, needle), 0, "entry must not retain " .. method)
        end
        for _, needle in ipairs({
            "local function _seed_one_item(",
            "local function _forge_seed_item(",
            "local function _forge_apply_to_amulet(",
            "local function _forge_apply_to_item(",
            "local function _get_career_talent_tree(",
            "local function _patch_movespeed_buff()",
            "local _AMULET_SLOT_BY_INDEX",
            "local _PROPERTY_BUBBLE_CAP_STATIC",
            "_store_property_slot = function(",
            "_cap_grid_property_arrays = function(",
            "_bubble_cap = function(",
        }) do
            H.equal(count_plain(owner, needle), 1, "owner must own " .. needle)
            H.equal(count_plain(entry, needle), 0, "entry must not retain " .. needle)
        end
    end)

    H.test("CIM weave-loadout owner leaves commit and wire safety with their owners", function()
        -- The commit suppression is anti-tamper safety for BOTH craft surfaces
        -- (it also reads mod._cim_standard_forge_active), so it must never sit
        -- behind this owner's install. The #278/#371 layer stays put too.
        for _, needle in ipairs({
            'mod:hook("BackendManagerPlayFab", "commit"',
            "mod._cim_standard_forge_active",
        }) do
            H.truthy(count_plain(entry, needle) >= 1, "entry must retain " .. needle)
            H.equal(count_plain(owner, needle), 0, "owner must not absorb " .. needle)
        end
        for _, needle in ipairs({
            "local function wire_safe_rarity(rarity)",
            'mod:network_register("cim_modded_slot"',
            'mod:hook("PlayerManager", "rpc_sync_loadout_slot"',
        }) do
            H.equal(count_plain(wire_owner, needle), 1,
                "wire owner must retain " .. needle)
            H.equal(count_plain(entry, needle), 0,
                "entry must not retain " .. needle)
            H.equal(count_plain(owner, needle), 0,
                "weave owner must not absorb " .. needle)
        end
    end)

    H.test("CIM weave-loadout owner keeps the public flat surface unwidened", function()
        -- The owner publishes no mod._cim_* field of its own; the only mod-table
        -- write is its private install state.
        H.equal(count_plain(owner, "mod._cim_weave_loadout_owner_state"), 2)
        for _, forbidden in ipairs({
            "mod._cim_bubble_cap", "mod._cim_store_property_slot",
            "mod._cim_forge_seed_item", "mod._cim_get_forged_weapons",
        }) do
            H.equal(owner:find(forbidden, 1, true), nil,
                "owner must not publish " .. forbidden)
            H.equal(entry:find(forbidden, 1, true), nil,
                "entry must not publish " .. forbidden)
        end
    end)

    H.test("CIM weave-loadout owner reads every entry store live, never snapshotted", function()
        -- open_forge and HeroViewStateWeaveForge.on_exit rebind _forge_item_props
        -- to a FRESH table and flip _custom_forge_active; _forge_load rebinds
        -- _forged_weapons. A captured reference would serve the previous session.
        for _, local_decl in ipairs({
            "local _custom_forge_active", "local _forge_item_props",
            "local _forged_weapons", "local _amulet_dirty",
        }) do
            H.equal(count_plain(owner, local_decl), 0,
                "owner must not declare its own " .. local_decl)
        end
        for _, accessor in ipairs({
            "is_active", "get_forge_item_props", "get_forged_weapons",
            "get_amulet_dirty", "forge_save", "get_raw_mirror_item",
        }) do
            H.truthy(owner:find("ctx." .. accessor, 1, true),
                "owner consumes ctx." .. accessor)
        end
        H.truthy(entry:find("is_active = function() return _custom_forge_active end", 1, true))
        H.truthy(entry:find("get_forge_item_props = function() return _forge_item_props end", 1, true))
        H.truthy(entry:find("get_forged_weapons = _forge_state.get_forged_weapons", 1, true))
        H.truthy(entry:find("get_amulet_dirty = function() return _amulet_dirty end", 1, true))
        H.truthy(entry:find("get_raw_mirror_item = function(backend_id)", 1, true))

        -- Drive it: rebind the store and flip the flag AFTER install, then prove
        -- the hook body seeds into the NEW table, the way a second Athanor open
        -- does. A snapshot would keep serving the previous session's seed.
        local mod = fake_mod()
        local props_store, active = {}, false
        local hooked = {}
        function mod:hook(target, method, fn) hooked[method] = fn end
        install_owner(mod, {
            is_active = function() return active end,
            get_forge_item_props = function() return props_store end,
        })

        -- Inactive: the wrapper must fall through to vanilla untouched.
        local vanilla_calls = 0
        local function vanilla() vanilla_calls = vanilla_calls + 1; return "vanilla" end
        H.equal(hooked.get_loadout_traits(vanilla, {}, "es_mercenary", "bid"), "vanilla")
        H.equal(vanilla_calls, 1)

        active = true
        local fresh = {}
        props_store = fresh
        with_backend({ get_item_from_id = function() return nil end }, function()
            local seeded = hooked.get_loadout_traits(
                function() error("vanilla must not run while the forge is cim-open") end,
                {}, "es_mercenary", "bid")
            H.equal(type(seeded), "table")
            H.truthy(next(fresh) ~= nil, "seed must land in the REBOUND props table")
            H.equal(fresh["es_mercenary|bid"].traits, seeded,
                "the hook must return the freshly seeded traits table")
        end)
        H.equal(vanilla_calls, 1, "no extra vanilla call once the forge is cim-open")
    end)

    H.test("CIM weave-loadout owner registers the ten hooks in their original order", function()
        local mod = fake_mod()
        install_owner(mod)
        H.equal(#mod.hooks, 10, "exactly the ten mutable loadout hooks install")
        for i, method in ipairs(MUTABLE_HOOKS) do
            H.equal(mod.hooks[i].target, "BackendInterfaceWeavesPlayFab", "hook " .. i .. " class")
            H.equal(mod.hooks[i].method, method, "hook " .. i .. " method")
            H.equal(mod.hooks[i].kind, "hook", "hook " .. i .. " must be a wrap hook")
        end
        -- The movespeed settings-change re-apply is registered at install, as
        -- it was in the entry, and is the owner's only dofile.
        H.deep_equal(mod.dofiles,
            { "scripts/mods/crafting_in_modded_dev/_cim_settings_runtime" })
        H.equal(mod.settings_installs, 1)
    end)

    H.test("CIM #1141 weapon writes remain draft-only until one Apply", function()
        local mod = fake_mod()
        local hooked = {}
        function mod:hook(_, method, fn) hooked[method] = fn end
        local store, saves = {}, 0
        local item = {
            rarity = "modded",
            properties = {},
            traits = { "old_trait" },
        }
        local persisted = {
            properties = {},
            traits = { "old_trait" },
        }
        local exports = install_owner(mod, {
            is_active = function() return true end,
            get_forge_item_props = function() return store end,
            get_forged_weapons = function() return { bid = persisted } end,
            forge_save = function() saves = saves + 1 end,
            get_raw_mirror_item = function() return item end,
        })

        with_backend({
            get_item_from_id = function(_, backend_id)
                if backend_id == "bid" then return item end
            end,
        }, function()
            hooked.set_loadout_trait(function() error("vanilla must not run") end,
                {}, "es_mercenary", "weave_new_trait", 1, "bid")
            H.deep_equal(item.traits, { "old_trait" })
            H.deep_equal(persisted.traits, { "old_trait" })
            H.equal(saves, 0)

            local ok, changed = exports.apply_item_draft("es_mercenary", "bid")
            H.truthy(ok)
            H.truthy(changed)
            H.deep_equal(item.traits, { "new_trait" })
            H.deep_equal(persisted.traits, { "new_trait" })
            H.equal(saves, 1)

            ok, changed = exports.apply_item_draft("es_mercenary", "bid")
            H.truthy(ok)
            H.equal(changed, false)
            H.equal(saves, 1)
        end)
    end)

    H.test("CIM #1141 rejected or throwing Apply persistence is atomic and retryable", function()
        local cases = {
            { name = "save reject", save_reject = true,
              save_reason = "save_rejected:save denied" },
            { name = "save throw", save_throw = true,
              save_reason = "save_exception:" },
        }
        for _, case in ipairs(cases) do
            local result = run_apply_hook(case)
            H.equal(result.call_ok, true,
                case.name .. " must not escape the production button hook")
            H.equal(result.applies, 1, case.name .. " apply count")
            H.equal(result.saves, 1, case.name .. " save count")
            H.equal(result.refreshes, 0,
                case.name .. " must not rebuild the native item cache")
            H.equal(result.apply_ok, false, case.name .. " owner result")
            H.truthy(tostring(result.apply_detail):find(
                case.save_reason, 1, true), case.name .. " save evidence")

            -- The writer sees a detached candidate; neither the live item nor
            -- the canonical forged record was published before persistence.
            H.truthy(result.candidate_seen ~= result.records,
                case.name .. " candidate registry must be detached")
            H.truthy(result.candidate_seen.bid ~= result.record,
                case.name .. " candidate record must be detached")
            H.equal(result.item.properties, result.old_item_properties,
                case.name .. " live properties identity")
            H.equal(result.item.traits, result.old_item_traits,
                case.name .. " live traits identity")
            H.equal(result.item.CustomData, result.old_custom_data,
                case.name .. " CustomData identity")
            H.equal(result.item.CustomData.properties,
                "old-properties-json", case.name .. " CustomData properties")
            H.equal(result.item.CustomData.traits,
                "old-traits-json", case.name .. " CustomData traits")
            H.equal(result.item.sentinel, "preserve-cache",
                case.name .. " unrelated cache field")
            H.equal(result.raw_item.properties, result.old_raw_properties,
                case.name .. " raw properties identity")
            H.equal(result.raw_item.traits, result.old_raw_traits,
                case.name .. " raw traits identity")
            H.equal(result.raw_item.CustomData, result.old_raw_custom_data,
                case.name .. " raw CustomData identity")
            H.equal(result.raw_item.CustomData.properties,
                "old-properties-json", case.name .. " raw CustomData properties")
            H.equal(result.raw_item.CustomData.traits,
                "old-traits-json", case.name .. " raw CustomData traits")
            H.equal(result.raw_item.sentinel, "preserve-raw",
                case.name .. " unrelated raw field")
            H.equal(result.record.properties, result.old_saved_properties,
                case.name .. " saved properties identity")
            H.equal(result.record.traits, result.old_saved_traits,
                case.name .. " saved traits identity")
            H.equal(result.record.trait, "old_trait",
                case.name .. " saved trait")
            H.equal(result.record.external_traits,
                result.old_external_traits,
                case.name .. " parked-traits identity")
            H.equal(result.record.sentinel, "preserve-record",
                case.name .. " unrelated record field")

            -- Returning false is the hook's retry contract: no draft discard,
            -- UI resync, completion sound, or success/no-op echo may occur.
            H.equal(result.drafts["es_mercenary|bid"], result.draft,
                case.name .. " draft must remain retryable")
            H.equal(result.discards, 0, case.name .. " discard count")
            H.equal(result.syncs, 0, case.name .. " sync count")
            H.equal(result.sounds, 0, case.name .. " sound count")
            H.equal(count_message(result.mod, "echo"), 0,
                case.name .. " success echo count")
            H.equal(count_message(result.mod, "warning", "Apply failed:"), 1,
                case.name .. " bounded failure warning")
        end
    end)

    H.test("CIM #1141 Apply contains raw-authority and encoding failures", function()
        local cases = {
            { name = "missing raw authority", raw_missing = true,
              reason = "raw_mirror_item" },
            { name = "throwing raw authority", raw_accessor_throw = true,
              reason = "raw_mirror_accessor_exception:" },
            { name = "throwing JSON encoder", encode_throw = true,
              reason = "encode_properties_exception:" },
            { name = "missing JSON encoder", cjson_missing = true,
              reason = "json_encoder_unavailable" },
        }
        for _, case in ipairs(cases) do
            local result = run_apply_hook(case)
            H.truthy(result.call_ok, case.name .. " must stay inside the hook")
            H.equal(result.applies, 1, case.name .. " apply count")
            H.equal(result.saves, 0, case.name .. " persistence count")
            H.equal(result.refreshes, 0, case.name .. " refresh count")
            H.equal(result.apply_ok, false, case.name .. " owner result")
            H.truthy(tostring(result.apply_detail):find(
                case.reason, 1, true), case.name .. " reason")
            H.equal(result.item.properties, result.old_item_properties,
                case.name .. " cache properties identity")
            H.equal(result.item.traits, result.old_item_traits,
                case.name .. " cache traits identity")
            H.equal(result.item.CustomData, result.old_custom_data,
                case.name .. " cache CustomData identity")
            H.equal(result.raw_item.properties, result.old_raw_properties,
                case.name .. " raw properties identity")
            H.equal(result.raw_item.traits, result.old_raw_traits,
                case.name .. " raw traits identity")
            H.equal(result.raw_item.CustomData, result.old_raw_custom_data,
                case.name .. " raw CustomData identity")
            H.equal(result.record.properties, result.old_saved_properties,
                case.name .. " record properties identity")
            H.equal(result.record.traits, result.old_saved_traits,
                case.name .. " record traits identity")
            H.equal(result.drafts["es_mercenary|bid"], result.draft,
                case.name .. " draft remains retryable")
            H.equal(result.discards, 0, case.name .. " discard count")
            H.equal(result.syncs, 0, case.name .. " UI sync count")
            H.equal(result.sounds, 0, case.name .. " completion sound count")
            H.equal(count_message(result.mod, "warning", "Apply failed:"), 1,
                case.name .. " bounded warning")
        end
    end)

    H.test("CIM #1141 successful and no-op Apply publish exactly once", function()
        local success = run_apply_hook()
        H.equal(success.call_ok, true)
        H.equal(success.applies, 1)
        H.equal(success.saves, 1)
        H.equal(success.refreshes, 0)
        H.equal(success.apply_ok, true)
        H.equal(success.apply_detail, true)
        H.deep_equal(success.item.properties, { power_vs_skaven = 0.6 })
        H.deep_equal(success.item.traits, { "old_trait" })
        H.equal(success.item.CustomData.properties, "encoded-properties")
        H.equal(success.item.CustomData.traits, "encoded-traits")
        H.deep_equal(success.raw_item.properties, { power_vs_skaven = 0.6 })
        H.deep_equal(success.raw_item.traits, { "old_trait" })
        H.equal(success.raw_item.CustomData.properties, "encoded-properties")
        H.equal(success.raw_item.CustomData.traits, "encoded-traits")
        H.equal(success.item.CustomData, success.old_custom_data,
            "cache CustomData table identity must survive publication")
        H.equal(success.raw_item.CustomData, success.old_raw_custom_data,
            "raw CustomData table identity must survive publication")
        H.truthy(success.item.properties ~= success.raw_item.properties,
            "cache and raw properties must not alias")
        H.truthy(success.item.traits ~= success.raw_item.traits,
            "cache and raw traits must not alias")
        H.deep_equal(success.record.properties, { power_vs_skaven = 0.6 })
        H.deep_equal(success.record.traits, { "old_trait" })
        H.equal(success.record.trait, "old_trait")
        H.deep_equal(success.record.external_traits, {})
        H.equal(success.record.sentinel, "preserve-record")
        H.equal(success.drafts["es_mercenary|bid"], nil)
        H.equal(success.discards, 1)
        H.equal(success.syncs, 1)
        H.equal(success.sounds, 1)
        H.equal(count_message(success.mod, "echo",
            "Applied staged properties and trait"), 1)
        H.equal(count_message(success.mod, "warning"), 0)

        -- A later native-style cache rebuild reads the raw mirror.  Because
        -- Apply published the authority as well as the current cache, it must
        -- preserve rather than revert the selected payload.
        success.refresh()
        H.equal(success.get_refreshes(), 1,
            "the explicit test refresh must run exactly once")
        H.deep_equal(success.item.properties, { power_vs_skaven = 0.6 })
        H.deep_equal(success.item.traits, { "old_trait" })
        H.equal(success.item.CustomData.properties, "encoded-properties")
        H.equal(success.item.CustomData.traits, "encoded-traits")

        local noop = run_apply_hook({ noop = true })
        H.equal(noop.call_ok, true)
        H.equal(noop.applies, 1)
        H.equal(noop.saves, 0, "a no-op must not persist")
        H.equal(noop.refreshes, 0)
        H.equal(noop.apply_ok, true)
        H.equal(noop.apply_detail, false)
        H.equal(noop.item.properties, noop.old_item_properties)
        H.equal(noop.item.traits, noop.old_item_traits)
        H.equal(noop.item.CustomData, noop.old_custom_data)
        H.equal(noop.raw_item.properties, noop.old_raw_properties)
        H.equal(noop.raw_item.traits, noop.old_raw_traits)
        H.equal(noop.raw_item.CustomData, noop.old_raw_custom_data)
        H.equal(noop.raw_item.sentinel, "preserve-raw")
        H.equal(noop.record.properties, noop.old_saved_properties)
        H.equal(noop.record.traits, noop.old_saved_traits)
        H.equal(noop.record.external_traits, noop.old_external_traits)
        H.equal(noop.drafts["es_mercenary|bid"], nil)
        H.equal(noop.discards, 1)
        H.equal(noop.syncs, 1)
        H.equal(noop.sounds, 0)
        H.equal(count_message(noop.mod, "echo",
            "No staged changes to apply"), 1)
        H.equal(count_message(noop.mod, "warning"), 0)
    end)

    H.test("CIM weave-loadout owner install is idempotent", function()
        local mod = fake_mod()
        local install = load_owner()
        local ctx = {
            mod = mod,
            is_active = function() return false end,
            get_forge_item_props = function() return {} end,
            get_forged_weapons = function() return {} end,
            get_amulet_dirty = function() return {} end,
            forge_save = function() end,
            temper_transaction = temper_transaction,
        }
        local first = install(ctx)
        local second = install(ctx)
        H.equal(first, second, "a second install must return the first exports")
        H.equal(#mod.hooks, 10, "hooks must not re-register")
        H.equal(mod.settings_installs, 1, "the settings listener must not re-register")
    end)

    H.test("CIM weave-loadout owner rebinds injected resolvers across a reload", function()
        local mod = fake_mod()
        local install = load_owner()
        local first_props, second_props = { a = true }, { b = true }
        local function ctx_for(props, active)
            return {
                mod = mod,
                is_active = function() return active end,
                get_forge_item_props = function() return props end,
                get_forged_weapons = function() return {} end,
                get_amulet_dirty = function() return {} end,
                forge_save = function() end,
                temper_transaction = temper_transaction,
            }
        end
        install(ctx_for(first_props, false))
        install(ctx_for(second_props, true))
        local state = mod._cim_weave_loadout_owner_state
        H.equal(state.get_forge_item_props(), second_props,
            "reload must adopt the fresh seed-store accessor")
        H.equal(state.is_active(), true, "reload must adopt the fresh active-state accessor")
        H.equal(#mod.hooks, 10, "reload must not duplicate the hooks")
    end)

    H.test("CIM weave-loadout owner refuses an incomplete context", function()
        local install = load_owner()
        H.equal(pcall(install), false)
        H.equal(pcall(install, { mod = fake_mod() }), false)
        H.equal(pcall(install, {
            mod = fake_mod(), is_active = function() return false end,
        }), false)
    end)

    H.test("CIM weave-loadout owner exports its four math helpers and temper boundary", function()
        local mod = fake_mod()
        local exports = install_owner(mod)
        local names = {}
        for name in pairs(exports) do names[#names + 1] = name end
        table.sort(names)
        H.deep_equal(names, {
            "apply_item_draft", "bubble_cap", "cap_grid_property_arrays",
            "discard_item_draft", "item_draft_payload", "store_property_slot",
            "value_for_bubbles",
        })
        for _, name in ipairs(names) do
            H.equal(type(exports[name]), "function", name .. " must be callable")
        end
        -- The late regression installer receives them under its existing keys.
        H.truthy(entry:find("bubble_cap = _bubble_cap", 1, true))
        H.truthy(entry:find("value_for_bubbles = _value_for_bubbles", 1, true))
        H.truthy(entry:find("cap_grid_property_arrays = _cap_grid_property_arrays", 1, true))
        H.truthy(entry:find("store_property_slot = _store_property_slot", 1, true))
    end)

    H.test("CIM weave-loadout owner leaves exactly one forward declaration in the entry", function()
        -- Only `_bubble_cap` has a consumer ABOVE the seam: _cim_weave_economy's
        -- get_property_mastery_costs hook resolves it at callback time. Without
        -- the forward local that closure reads a nil GLOBAL and the Athanor
        -- crashes on the first property-cost query.
        H.equal(count_plain(entry, "\nlocal _bubble_cap\n"), 1,
            "the entry keeps the one genuine forward declaration")
        H.equal(count_plain(entry, "_bubble_cap = _WEAVE_LOADOUT_OWNER.bubble_cap"), 1,
            "the seam binds the forward-declared local")
        H.truthy(entry:find("bubble_cap = function(property_name) return _bubble_cap(property_name) end", 1, true),
            "the economy facade still resolves the cap at callback time")
        -- The other three are ordinary locals assigned at the seam; the two with
        -- no entry consumer at all are gone.
        for _, decl in ipairs({
            "local _value_for_bubbles = _WEAVE_LOADOUT_OWNER.value_for_bubbles",
            "local _store_property_slot = _WEAVE_LOADOUT_OWNER.store_property_slot",
            "local _cap_grid_property_arrays = _WEAVE_LOADOUT_OWNER.cap_grid_property_arrays",
        }) do
            H.equal(count_plain(entry, decl), 1, "seam must assign " .. decl)
        end
        for _, dead in ipairs({ "\nlocal _bubbles_for_value\n", "\nlocal _strip_weave\n" }) do
            H.equal(count_plain(entry, dead), 0,
                "a forward local with no entry consumer must not survive as nil")
        end
    end)

    H.test("CIM weave-loadout owner preserves the #86 bubble caps and key normalization", function()
        local mod = fake_mod({ movespeed_2pct_mode = false })
        local exports = install_owner(mod)
        local cap = exports.bubble_cap
        -- Every caller key form collapses to the bare name (#86 take 3): the
        -- game sends `weave_stamina`, older code sent `weave_properties_stamina`.
        for _, key in ipairs({
            "stamina", "weave_stamina", "properties_stamina", "weave_properties_stamina",
        }) do
            H.equal(cap(key), 2, key .. " must cap at 2 bubbles")
        end
        for _, key in ipairs({ "movespeed", "weave_movespeed", "weave_properties_movespeed" }) do
            H.equal(cap(key), 1, key .. " must cap at 1 bubble")
        end
        H.equal(cap("weave_attack_speed"), 5, "generic properties keep the 5-bubble row")
        -- The 2pct toggle uncaps movespeed to five +2% steps, read dynamically.
        mod._settings.movespeed_2pct_mode = true
        H.equal(cap("weave_movespeed"), 5, "2pct mode must uncap movespeed live")
        H.equal(cap("weave_stamina"), 2, "2pct mode must not touch stamina")
    end)

    H.test("CIM weave-loadout owner keeps the #86 read-chokepoint trim layer-aware", function()
        local mod = fake_mod({ movespeed_2pct_mode = false })
        local exports = install_owner(mod)
        with_printf(function(logged)
            -- Single weapon: one layer, so the whole array caps at the bubble cap.
            local weapon = { weave_stamina = { 1, 2, 3, 4, 5 } }
            exports.cap_grid_property_arrays(weapon, "bid-1")
            H.deep_equal(weapon.weave_stamina, { 1, 2 })

            -- Amulet (no backend id): one property may legitimately appear once
            -- per accessory layer of ten, so a blanket trim would wrongly drop
            -- the necklace and trinket copies.
            local amulet = { weave_movespeed = { 1, 2, 11, 12, 21 } }
            exports.cap_grid_property_arrays(amulet, nil)
            H.deep_equal(amulet.weave_movespeed, { 1, 11, 21 })

            -- Already within cap: untouched, and idempotent on a second pass.
            local clean = { weave_attack_speed = { 1, 2, 3 } }
            exports.cap_grid_property_arrays(clean, "bid-1")
            exports.cap_grid_property_arrays(clean, "bid-1")
            H.deep_equal(clean.weave_attack_speed, { 1, 2, 3 })
            H.truthy(#logged >= 2, "each real trim must self-report through printf")
        end)
    end)

    H.test("CIM weave-loadout owner routes the write cap through the #959 policy", function()
        local mod = fake_mod({ movespeed_2pct_mode = false })
        local seen
        mod._cim959_accessory_property_policy = {
            store_property_slot = function(props, key, slot_index, cap, layer_size)
                seen = { key = key, slot = slot_index, cap = cap, layer_size = layer_size }
                return { slot_index }, true, "stored", 1
            end,
        }
        local exports = install_owner(mod)
        with_printf(function()
            local arr = exports.store_property_slot({}, "weave_stamina", 3, 10)
            H.deep_equal(arr, { 3 })
            H.equal(seen.cap, 2, "the policy must receive the property's own bubble cap")
            H.equal(seen.layer_size, 10)
        end)
        -- Fail loud, not silently uncapped, if the shared policy goes missing.
        mod._cim959_accessory_property_policy = nil
        H.equal(pcall(exports.store_property_slot, {}, "weave_stamina", 3, 10), false)
    end)

    H.test("CIM weave-loadout owner holds no view lifecycle or persistence store", function()
        -- The Athanor on_enter crash-guard cascade, the preview world, the
        -- widget material policy, and the persisted equip store all belong to
        -- other owners. Assert on what this file REGISTERS and CALLS.
        for _, forbidden in ipairs({
            'mod:hook("HeroView', 'mod:hook_safe("HeroView',
            'mod:hook("HeroWindow', 'mod:hook_safe("HeroWindow',
            "set_loadout_item", "_modded_loadout", "_unit_previewer",
            "shading_environment", "create_screen_gui", "Managers.ui",
            "ingame_ui", "UIWidget", "package:load", "network_register",
            "mod:command(",
        }) do
            H.equal(owner:find(forbidden, 1, true), nil,
                "owner must not touch " .. forbidden)
        end
        H.equal(count_plain(owner, "mod:hook"), 10)
    end)
end
