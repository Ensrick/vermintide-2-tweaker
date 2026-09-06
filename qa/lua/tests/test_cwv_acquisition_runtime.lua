-- #592: execute the installed production registration hook and its migration,
-- not a parallel seed algorithm or a dense-only ownership fixture.
return function(H, repo_root)
    local root = repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local acquisition = assert(loadfile(root .. "_cwv_acquisition.lua"))()
    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end
    local function clone(value)
        if type(value) ~= "table" then return value end
        local copy = {}
        for key, child in pairs(value) do copy[key] = clone(child) end
        return copy
    end
    local function registration_loader(env)
        local text = read("_cwv_item_registration_owner.lua")
        -- PUC 5.1 lacks Stingray's goto extension. Lower only the three proven
        -- continue branches in the one definition loop, preserving its body.
        local count
        text, count = text:gsub("for _, def in ipairs%(_variant_definitions%) do",
            "for _, def in ipairs(_variant_definitions) do\n\t\trepeat")
        H.equal(count, 1, "registration loop shape changed")
        text, count = text:gsub("goto continue", "break")
        H.equal(count, 3, "registration continue set changed")
        text, count = text:gsub("::continue::", "until true")
        H.equal(count, 1, "registration continue target changed")
        local chunk = assert(loadstring(text, "@_cwv_item_registration_owner.lua"))
        setfenv(chunk, env)
        return chunk()
    end
    local key = "cwv_es_musket_old"
    local function run_case(options)
        local events = { added = {}, removed = {}, reads = {}, messages = {} }
        local records = options.records or {}
        local live, snapshots = {}, {}
        for _, suffix in ipairs({ "000", "001", "002", "003" }) do
            local id = key .. "_" .. suffix
            live[id] = { backend_id = id, rarity = "modded", power_level = 300,
                skin = "saved_illusion_" .. suffix, properties = { crit = 0.05 } }
            snapshots[id] = clone(live[id])
        end
        local relic = { backend_id = "woc_blightreaper_001", marker = "WOC" }
        live[relic.backend_id] = relic
        local outside_ledger = { key .. "_100", key .. "_uuid", "unrelated_item" }
        for _, id in ipairs(outside_ledger) do live[id] = { backend_id = id } end
        local before = {}
        for id, item in pairs(live) do before[id] = item end
        local after_seed = false
        local function owner(name)
            if not options[name] then return nil end
            if options[name] == "missing" then return {} end
            if options[name] == "nonfunction" then return { _cim_get_craft = 17 } end
            if options[name] == "lookup_throws" then
                return setmetatable({}, { __index = function()
                    events.reads[name] = (events.reads[name] or 0) + 1
                    error("getter lookup failed")
                end })
            end
            return { _cim_get_craft = function(id)
                events.reads[name] = (events.reads[name] or 0) + 1
                if options[name] == "throws"
                        or (options.throw_after_seed and after_seed) then
                    error("ownership ledger unavailable")
                end
                return records[name] and records[name][id] or nil
            end }
        end
        local mods = { cim_dev = owner("dev"), cim = owner("stable") }
        local mil = {}
        function mil:add_mod_items_to_local_backend(rows, name)
            H.equal(name, "character_weapon_variants")
            for _, entry in ipairs(rows) do
                local id = entry.mod_data.backend_id
                events.added[#events.added + 1] = id
                live[id] = { backend_id = id, data = entry, CustomData = {},
                    rarity = "modded", power_level = 300, skin = "MIL-default" }
            end
            after_seed = true
        end
        function mil:remove_mod_items_from_local_backend(ids, name)
            H.equal(name, "character_weapon_variants")
            for _, id in ipairs(ids) do
                events.removed[#events.removed + 1] = id
                live[id] = nil
            end
        end
        mods.MoreItemsLibrary = mil
        local hooks = {}
        local mod = { _cwv_acquisition = acquisition }
        function mod:get() return true end
        function mod:hook_safe(class, method, fn) hooks[class .. "." .. method] = fn end
        function mod:hook(class, method, fn) hooks[class .. "." .. method] = fn end
        function mod:info(fmt, ...) events.messages[#events.messages + 1] = string.format(fmt, ...) end
        mod.warning, mod.error = mod.info, mod.info
        local item_master = { es_handgun = { key = "es_handgun", name = "es_handgun",
            slot_type = "ranged", item_type = "handgun", template = "handgun_template_1" } }
        local env = setmetatable({
            get_mod = function(name) return mods[name] end,
            ItemMasterList = item_master, NetworkLookup = { item_names = {} },
            Weapons = {}, CareerSettings = {}, ActionTemplates = {},
            table = setmetatable({ clone = clone }, { __index = table }),
            printf = function() end,
            WeaponSkins = { skins = {}, skin_combinations = {},
                matching_weapon_skin_item_key = function() return nil end },
            Managers = { backend = { get_interface = function()
                return { get_item_from_id = function(_, id) return live[id] end }
            end } },
        }, { __index = _G })
        env._G = env
        local om = { infantry_spear = { ITEM_KEY = "cwv_es_infantry_spear" },
            deus_identity = { install = function()
                return { installed = 0, existing = 0, degraded = 0, skipped = {} }
            end } }
        local definitions = { { item_key = key, base_weapon = "es_handgun", instances = 3 } }
        registration_loader(env)(mod, {
            om = om, dbg = function() end, dbg_alert = function() end,
            variant_definitions = definitions, custom_skin_keys = {},
            network_lookup = { register_named = function(lookup, name, value)
                local index = #lookup[name] + 1
                lookup[name][index], lookup[name][value] = value, index
            end },
            cwv_career_weapon_actions = { install = function()
                return { ok = true, template_count = 0 }
            end },
        })
        local hook = assert(hooks["StateInGameRunning.on_enter"])
        hook()
        local added, removed = #events.added, #events.removed
        hook()
        H.equal(#events.added, added, "repeat gameplay entry duplicated registration")
        H.equal(#events.removed, removed, "repeat gameplay entry repeated cleanup")
        H.equal(live[relic.backend_id], relic, "migration touched WOC")
        for _, id in ipairs(outside_ledger) do
            H.equal(live[id], before[id], "migration escaped its finite authored ledger")
        end
        for _, ledger in pairs(records) do
            for id in pairs(ledger) do
                H.equal(live[id], before[id], "exact CIM-owned row was replaced/deleted: " .. id)
                H.deep_equal(live[id], snapshots[id], "exact CIM-owned fields were changed: " .. id)
            end
        end
        return events, live, om, before
    end

    H.test("CWV #592 installed registration preserves both CIM streams across absent dev", function()
        local scenarios = {
            { stable = true, records = { stable = { [key .. "_001"] = {} } } },
            { dev = true, records = { dev = { [key .. "_001"] = {} } } },
            { dev = true, stable = true, records = {
                dev = { [key .. "_001"] = {} }, stable = { [key .. "_002"] = {} },
            } },
        }
        for _, options in ipairs(scenarios) do
            local events, live, om = run_case(options)
            H.deep_equal(events.added, { key .. "_000" })
            H.equal(om._cwv_blacksmith_seed_count, 1)
            H.equal(live[key .. "_000"].power_level, 5)
            H.equal(live[key .. "_000"].rarity, "default")
            H.equal(live[key .. "_000"].skin, nil)
            if options.stable then H.truthy((events.reads.stable or 0) > 0) end
            if options.dev then H.truthy((events.reads.dev or 0) > 0) end
            H.equal(live[key .. "_003"], nil, "finite unowned extra was not cleaned")
        end
    end)

    H.test("CWV #592 installed registration preserves occupied fallback and refuses double collision", function()
        local events, _, om = run_case({ stable = true,
            records = { stable = { [key .. "_000"] = {} } } })
        H.deep_equal(events.added, { key .. "_001" })
        H.equal(om._cwv_blacksmith_seed_count, 1)
        events, _, om = run_case({ dev = true, stable = true,
            records = { dev = { [key .. "_001"] = {} },
                stable = { [key .. "_000"] = {} } } })
        H.equal(#events.added, 0)
        H.equal(#events.removed, 0)
        H.equal(om._cwv_blacksmith_seed_count, 0)
    end)

    H.test("CWV #592 installed registration fails closed on unreadable ledgers in either stream", function()
        for _, options in ipairs({
            { stable = "throws" }, { dev = "throws" },
            { stable = "throws", dev = true },
            { stable = true, dev = "throws", records = { stable = { [key .. "_001"] = {} } } },
        }) do
            local events, live, om, before = run_case(options)
            H.equal(#events.added, 0)
            H.equal(#events.removed, 0)
            H.equal(om._cwv_blacksmith_seed_count, 0)
            for id, item in pairs(before) do H.equal(live[id], item) end
            if options.stable then H.truthy((events.reads.stable or 0) > 0) end
            if options.dev then H.truthy((events.reads.dev or 0) > 0) end
        end
    end)

    H.test("CWV #592 cleanup preserves rows when ownership becomes unreadable after seed registration", function()
        local events, live, om, before = run_case({ stable = true,
            throw_after_seed = true, records = { stable = { [key .. "_002"] = {} } } })
        H.deep_equal(events.added, { key .. "_001" })
        H.equal(om._cwv_blacksmith_seed_count, 1)
        H.equal(#events.removed, 0)
        for id, item in pairs(before) do
            if id ~= key .. "_001" then H.equal(live[id], item) end
        end
    end)

    H.test("CWV #592 installed registration refuses present owners with unreadable getters", function()
        for _, mode in ipairs({ "missing", "nonfunction", "lookup_throws" }) do
            for _, options in ipairs({
                { stable = mode }, { dev = mode },
                { stable = mode, dev = true }, { stable = true, dev = mode },
                { stable = true, dev = mode, records = { stable = { [key .. "_001"] = {} } } },
                { stable = mode, dev = true, records = { dev = { [key .. "_001"] = {} } } },
            }) do
                local events, live, om, before = run_case(options)
                H.equal(#events.added, 0, mode .. " getter allowed seed replacement")
                H.equal(#events.removed, 0, mode .. " getter allowed legacy deletion")
                H.equal(om._cwv_blacksmith_seed_count, 0)
                for id, item in pairs(before) do H.equal(live[id], item) end
            end
        end
    end)

    H.test("CWV #592 no CIM still registers one seed and cleans only finite extras", function()
        local events, live, om = run_case({})
        H.deep_equal(events.added, { key .. "_001" })
        H.equal(om._cwv_blacksmith_seed_count, 1)
        H.equal(live[key .. "_000"], nil)
        H.equal(live[key .. "_002"], nil)
        H.equal(live[key .. "_003"], nil)
        H.equal(next(events.reads), nil)
        H.deep_equal(events.removed, { "cwv_es_infantry_spear_001",
            key .. "_000", key .. "_002", key .. "_003" })
    end)

    H.test("CWV #592 named runtime check detects nullable owners and unsafe cleanup", function()
        local text = read("_cwv_regression_render.lua")
        local first = assert(text:find('_rt_register("issue592_bounded_blacksmith_acquisition", function()', 1, true))
        local last = assert(text:find("\nend)", first, true))
        local block = text:sub(first, last + 5)
        local function check(policy)
            local registered
            local env = setmetatable({ Managers = { backend = { get_interface = function() return {} end } },
                ItemMasterList = {} }, { __index = _G })
            local chunk = assert(loadstring("local _rt_register, mod, _variant_definitions, _registered_keys = ...\n" .. block))
            setfenv(chunk, env)
            chunk(function(_, fn) registered = fn end,
                { _cwv_acquisition = policy, _cwv_blacksmith_seed_ids = {}, _cwv_blacksmith_seed_count = 0 },
                { { item_key = key, instances = 2, cwv_retired = true } }, {})
            return registered()
        end
        H.equal(check(acquisition), nil)
        local bad_probe = {}
        for name, value in pairs(acquisition) do bad_probe[name] = value end
        bad_probe.owner_probe = function(...) -- planted original truncation
            local owners = { ... }
            return function(id)
                for _, owner in ipairs(owners) do
                    if owner._cim_get_craft(id) then return true end
                end
                return false
            end
        end
        H.truthy(check(bad_probe):find("public CIM ledger", 1, true))
        local missing_getter = {}
        for name, value in pairs(acquisition) do missing_getter[name] = value end
        missing_getter.owner_probe = function(...)
            local owners, count = { ... }, select("#", ...)
            return function(id)
                for index = 1, count do
                    local owner = owners[index]
                    if owner and type(owner._cim_get_craft) == "function"
                            and owner._cim_get_craft(id) then return true end
                end
                return false
            end
        end
        H.truthy(check(missing_getter):find("unreadable owner", 1, true))
        local bad_cleanup = {}
        for name, value in pairs(acquisition) do bad_cleanup[name] = value end
        bad_cleanup.should_remove = function(id, legacy, owned)
            return legacy[id] == true and owned(id) ~= true
        end
        H.truthy(check(bad_cleanup):find("not preserved", 1, true))
    end)
end
