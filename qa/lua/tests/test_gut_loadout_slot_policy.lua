return function(H, repo_root, controls)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_loadout_slot_policy.lua"
    local Policy = assert(loadfile(path))()

    local function career(slot_ranged)
        return {
            es_knight = {
                item_slot_types_by_slot_name = {
                    slot_melee = { "melee" },
                    slot_ranged = slot_ranged,
                    slot_hat = { "hat" },
                },
            },
            dr_slayer = {
                item_slot_types_by_slot_name = {
                    slot_melee = { "melee" },
                    slot_ranged = { "melee", "ranged" },
                },
            },
            es_questingknight = {
                item_slot_types_by_slot_name = {
                    slot_melee = { "melee" },
                    slot_ranged = { "melee", "ranged" },
                },
            },
        }
    end

    H.test("GUT loadout policy follows live Foot Knight secondary capability", function()
        local settings = career({ "ranged" })
        local cwv_item = {
            slot_type = "melee",
            can_wield = { "es_knight" },
            backend_id = "cwv_es_greataxe_001",
        }

        local ok = Policy.validate(cwv_item, "slot_ranged", "es_knight", settings)
        H.equal(ok, false, "melee must be rejected before the CRT capability exists")

        table.insert(settings.es_knight.item_slot_types_by_slot_name.slot_ranged, 1, "melee")
        ok = Policy.validate(cwv_item, "slot_ranged", "es_knight", settings)
        H.equal(ok, true, "live CRT capability must be observed without reload")
        H.equal(cwv_item.backend_id, "cwv_es_greataxe_001", "CWV identity must remain exact")

        table.remove(settings.es_knight.item_slot_types_by_slot_name.slot_ranged, 1)
        ok = Policy.validate(cwv_item, "slot_ranged", "es_knight", settings)
        H.equal(ok, false, "toggle-off capability removal must be observed without reload")
    end)

    H.test("GUT loadout policy preserves native dual-melee careers", function()
        local settings = career({ "ranged" })
        local slayer_item = { slot_type = "melee", can_wield = { "dr_slayer" } }
        local grail_item = { slot_type = "melee", can_wield = { "es_questingknight" } }

        H.equal(Policy.validate(slayer_item, "slot_ranged", "dr_slayer", settings), true)
        H.equal(Policy.validate(grail_item, "slot_ranged", "es_questingknight", settings), true)
    end)

    H.test("GUT loadout policy accepts WT and CWV by capability not key", function()
        local settings = career({ "melee", "ranged" })
        local wt_item = { key = "foreign_wt_weapon", slot_type = "melee", can_wield = { "es_knight" } }
        local cwv_item = { key = "cwv_es_infantry_spear", slot_type = "melee", can_wield = { "es_knight" } }

        H.equal(Policy.validate(wt_item, "slot_ranged", "es_knight", settings), true)
        H.equal(Policy.validate(cwv_item, "slot_ranged", "es_knight", settings), true)
    end)

    H.test("GUT loadout policy rejects absent capabilities and wield permission", function()
        local settings = career({ "melee", "ranged" })
        local wrong_career = { slot_type = "melee", can_wield = { "dr_slayer" } }
        local wrong_type = { slot_type = "ranged", can_wield = { "es_knight" } }

        H.equal(Policy.validate(wrong_career, "slot_ranged", "es_knight", settings), false)
        H.equal(Policy.validate(wrong_type, "slot_hat", "es_knight", settings), false)
        H.equal(Policy.validate(wrong_type, "slot_ranged", "missing_career", settings), false)
        H.equal(Policy.validate(wrong_type, "missing_slot", "es_knight", settings), false)
        H.equal(Policy.validate(nil, "slot_ranged", "es_knight", settings), false)
    end)

    -- Complete installed owner against a mandatory exact old source block.
    -- This is detached command/backend value flow, not a VMF/game emulator.
    controls = controls or {}
    local prefix = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local function text(path)
        local f = assert(io.open(path, "rb"))
        local s = f:read("*a"); f:close()
        return (s:gsub("\r\n", "\n"))
    end
    local function pack(...) return { n = select("#", ...), ... } end
    local function replace(s, from, to, wanted)
        local n, at, parts = 0, 1, {}
        while true do
            local a, b = s:find(from, at, true)
            if not a then parts[#parts + 1] = s:sub(at); break end
            parts[#parts + 1] = s:sub(at, a - 1); parts[#parts + 1] = to
            n = n + 1; at = b + 1
        end
        assert(n == wanted, "actual mutation boundary drift")
        return table.concat(parts)
    end
    local main = text(prefix .. "gui_tweaker_dev.lua")
    local first = assert(main:find("-- #2: closed legacy saved-loadout command owner;", 1, true))
    local last = assert(main:find("-- ============================================================\n-- Versus host-crash fix:", first, true))
    local entry_span = main:sub(first, last - 1)
    local publisher_first = assert(main:find("mod._gut925_generation = function()", 1, true))
    local publisher_last = assert(main:find("-- [mem-probe]", publisher_first, true))
    local publisher = main:sub(publisher_first, publisher_last - 1)

    local function fixture(old, options)
        options = options or {}
        local f = { trace = {}, install_order = {}, commands = {}, checks = {}, store = {}, writes = {},
            talents_values = { 11, 22, 33 }, items = {}, loading = true }
        local function record(kind, ...) f.trace[#f.trace + 1] = { kind, ... } end
        local function log(kind, fmt, ...) record(kind, string.format(fmt, ...)) end
        local player = { profile_index = function() return 1 end, career_index = function() return 1 end }
        local gear = { slot_melee = "gear-A", slot_ranged = "gear-B" }
        local cosmetics = { slot_hat = "hat-A", slot_frame = "frame-A" }
        for slot, id in pairs(gear) do
            f.items[id] = { key = id, data = { name = id, slot_type = slot == "slot_melee" and "melee" or "ranged", can_wield = { "es_knight" } } }
        end
        f.items["hat-A"] = { key = "hat-A", data = { name = "hat-A", slot_type = "hat" } }
        f.items["frame-A"] = { key = "frame-A", data = { name = "frame-A", slot_type = "frame" } }
        local item_iface = {
            get_loadout_item_id = function(_, career_name, slot)
                record("get", career_name, slot)
                return gear[slot] or cosmetics[slot]
            end,
            get_item_from_id = function(_, id) return f.items[id] end,
        }
        local talents_iface = {
            get_talents = function() return f.talents_values end,
            set_talents = function(_, career_name, values)
                if f.throw_talents then error("talent-error", 0) end
                record("talents", career_name, table.concat(values, ","))
            end,
        }
        f.backend = { get_interface = function(_, which)
            if f.no_items and which == "items" then return nil end
            return which == "items" and item_iface or talents_iface
        end }
        f.env = setmetatable({
            Managers = { player = { local_player = function() return player end }, backend = f.backend },
            SPProfiles = { { careers = { { name = "es_knight", display_name = "career_knight" } } } },
            CareerSettings = { es_knight = { item_slot_types_by_slot_name = {
                slot_melee = { "melee" }, slot_ranged = { "ranged" }, slot_hat = { "hat" }, slot_frame = { "frame" },
            } } },
            InventorySettings = { slots_by_ui_slot_index = { { name = "slot_melee" }, { name = "slot_ranged" } },
                slots_by_cosmetic_index = { { name = "slot_hat" }, { name = "slot_frame" } } },
            Localize = function(key) return "LOCAL:" .. key end,
            os = { time = function() return 123456 end, date = function() return "FIXED-DATE" end },
            table = setmetatable({ clone = function(values)
                local out = {}; for k, v in pairs(values) do out[k] = v end; return out
            end }, { __index = table }),
        }, { __index = _G })
        f.env._G = f.env
        local mod = {}
        f.mod = mod
        function mod:get(key) return f.store[key] end
        function mod:set(key, value) f.store[key] = value; record("store", key) end
        function mod:echo(fmt, ...) log("echo", fmt, ...) end
        function mod:command(name, help, callback)
            assert(not f.commands[name], "duplicate command")
            f.install_order[#f.install_order + 1] = "command:" .. name
            f.commands[name] = callback
            f.help = f.help or {}; f.help[name] = help
        end
        f.env.mod = mod
        f.env._dbg = function(fmt, ...) log("debug", fmt, ...) end
        f.env._dbg_alert = function(fmt, ...) log("alert", fmt, ...) end
        f.env.printf = function(fmt, ...)
            if f.loading then f.install_order[#f.install_order + 1] = "printf" end
            log("printf", fmt, ...)
        end
        f.env._rt_register = function(name, callback)
            f.install_order[#f.install_order + 1] = "check:" .. name
            if options.registrar_error then error(options.registrar_error, 0) end
            f.checks[#f.checks + 1] = { name = name, callback = callback }
        end
        local function load_module(file)
            local source = text(file)
            if not old and file:find("_gut_saved_loadout_commands.lua", 1, true) then
                if controls.drop_set then source = replace(source, "BackendUtils.set_loadout_item", "BackendUtils.disconnected", 2) end
                if controls.drop_publish then source = replace(source, "mod._gut925_publish_if_unobserved", "mod._gut925_disconnected", 2) end
                if controls.freeze_engine then source = replace(source, "function M.install(deps)\n",
                    "function M.install(deps)\n    local Managers, SPProfiles, CareerSettings, InventorySettings, BackendUtils, Localize = Managers, SPProfiles, CareerSettings, InventorySettings, BackendUtils, Localize\n", 1) end
                if controls.freeze_policy then source = replace(source,
                    "local _gut_loadout_slot_policy = deps.slot_policy",
                    "local _gut_loadout_slot_policy = { validate = deps.slot_policy.validate }", 1) end
            end
            local chunk = assert(loadstring(source, "@" .. file)); setfenv(chunk, f.env)
            return chunk()
        end
        local Lib = load_module(prefix .. "_lib_ui_presentation_refresh.lua")
        mod._ui_presentation_refresh_lib = Lib
        mod._ui_presentation_refresh = assert(Lib.attach(f.env, "gut_dev", 32))
        local inner = assert(Lib.attach(f.env, "inner", 32))
        local pub = assert(loadstring(publisher, "@actual-root-publisher")); setfenv(pub, f.env); pub()
        mod._gut925_disconnected = function() end
        f.env.BackendUtils = {
            disconnected = function() end,
            set_loadout_item = function(id, career_name, slot)
                if id == f.throw_item then error("item-error", 0) end
                record("set", id, career_name, slot)
                f.writes[#f.writes + 1] = { id, career_name, slot }
                if f.inner_publish then inner:publish({ kind = "loadout", backend_id = id, slot_name = slot }) end
                if f.return_false then return false end
            end,
        }
        function mod:dofile(module_path)
            local name = module_path:match("([^/]+)$")
            assert(name == "_gut_loadout_slot_policy" or name == "_gut_saved_loadout_commands", "unexpected nested load")
            f.install_order[#f.install_order + 1] = name == "_gut_loadout_slot_policy" and "policy" or "owner"
            local api = load_module(prefix .. name .. ".lua")
            if name == "_gut_loadout_slot_policy" then f.policy = api
            else
                local actual = api.install
                api.install = function(deps) f.deps = deps; return actual(deps) end
            end
            return api
        end
        if old then
            -- Required tracked exact body: never an external checkout, environment SKIP or reconstructed algorithm.
            local chunk = assert(loadfile(repo_root .. "/qa/lua/fixtures/gut_saved_loadout_commands_gui365.lua"))
            setfenv(chunk, f.env); chunk()
        else
            local span = entry_span
            local policy = 'local _gut_loadout_slot_policy = mod:dofile(\n    "scripts/mods/gui_tweaker_dev/_gut_loadout_slot_policy"\n)\n'
            if controls.drop_install then span = span:sub(1, assert(span:find('mod:dofile("scripts/mods/gui_tweaker_dev/_gut_saved_loadout_commands")', 1, true)) - 1) end
            if controls.early_install then span = replace(span, policy, "", 1) .. policy end
            local chunk = assert(loadstring(span, "@actual-entry-saved-loadout-span")); setfenv(chunk, f.env); chunk()
        end
        f.loading = false
        function f:call(name, value) return pack(assert(self.commands[name], "actual command missing")(value)) end
        function f:save() self:call("save_loadout", "1"); return self.store.loadouts.es_knight[1] end
        function f:generation() return self.mod._ui_presentation_refresh:stats().generation end
        return f
    end
    local function equivalent(configure, action, verify)
        local old, current = fixture(true), fixture(false)
        if configure then configure(old); configure(current) end
        local a, b = pack(action(old)), pack(action(current))
        H.deep_equal(b, a, "callback return/cardinality drift")
        H.deep_equal(current.trace, old.trace, "actual owner operation/log trace drift")
        H.deep_equal(current.store, old.store, "saved store drift")
        H.equal(current:generation(), old:generation(), "publication generation drift")
        if verify then verify(current) end
    end

    H.test("GUT saved-loadout owner actual entry installs one ordered check and three commands", function()
        local f = fixture(false)
        H.deep_equal(f.install_order, { "policy", "owner", "printf", "check:issue619_saved_loadout_live_slot_capability",
            "command:save_loadout", "command:load_loadout", "command:list_loadouts" })
        H.equal(#f.checks, 1); H.equal(f.checks[1].callback(), nil)
        H.equal(f.help.save_loadout, "Save current loadout to slot N (1-30)")
        H.equal(f.help.load_loadout, "Load loadout from slot N (1-30) for current career")
        H.equal(f.help.list_loadouts, "List saved loadouts for current career")
    end)
    H.test("GUT saved-loadout owner actual commands match portable healthy old body", function()
        equivalent(nil, function(f) f:save(); f:call("load_loadout", "1"); return f:call("list_loadouts") end, function(f)
            local saved = f.store.loadouts.es_knight[1]
            H.equal(saved.gear.slot_melee, "gear-A"); H.equal(saved.cosmetics.slot_hat, "hat-A")
            H.equal(saved.gear.slot_hat, nil); H.equal(saved.cosmetics.slot_melee, nil)
            H.truthy(saved.talents ~= f.talents_values); H.equal(saved.frame, "frame-A")
            H.equal(#f.writes, 4); H.equal(f:generation(), 4)
        end)
    end)
    H.test("GUT saved-loadout owner preserves pcall-success false-return counting", function()
        equivalent(function(f) f.return_false = true end, function(f) f:save(); return f:call("load_loadout", "1") end,
            function(f) H.equal(#f.writes, 4); H.equal(f:generation(), 4) end)
    end)
    H.test("GUT saved-loadout owner keeps actual inner-provider publication suppression", function()
        equivalent(function(f) f.inner_publish = true end, function(f) f:save(); return f:call("load_loadout", "1") end,
            function(f) H.equal(f:generation(), 4) end)
    end)
    H.test("GUT saved-loadout owner rejects gear cosmetic namespace contamination", function()
        equivalent(nil, function(f)
            local saved = f:save(); saved.gear = { unknown = "gear-A" }; saved.cosmetics = { slot_melee = "hat-A" }
            return f:call("load_loadout", "1")
        end, function(f) H.equal(#f.writes, 0) end)
    end)
    H.test("GUT saved-loadout owner preserves native errors and four-result summary", function()
        equivalent(function(f) f.throw_item = "gear-A"; f.throw_talents = true end,
            function(f) f:save(); return f:call("load_loadout", "1") end, function(f)
                H.equal(#f.writes, 3)
                H.truthy(f.trace[#f.trace][2]:find("talents_set=no errors=2", 1, true))
            end)
    end)
    H.test("GUT saved-loadout owner missing player and backend keep exact refusal paths", function()
        equivalent(function(f) f.env.Managers.player = nil end,
            function(f) return f:call("save_loadout", "1") end)
        equivalent(function(f) f.no_items = true end,
            function(f) return f:call("save_loadout", "1") end)
    end)
    H.test("GUT saved-loadout owner cross-career missing-item and slot arguments match old", function()
        equivalent(nil, function(f)
            for _, arg in ipairs({ "bad", "0", "31" }) do f:call("save_loadout", arg) end
            f:call("save_loadout", "1.9")
            f.store.loadouts.es_knight[1].career_name = "dr_slayer"
            return f:call("load_loadout", "1")
        end)
        equivalent(nil, function(f) f:save(); f.items["gear-A"] = nil; return f:call("load_loadout", "1") end)
    end)
    H.test("GUT saved-loadout owner live capability insert remove is read at each restore", function()
        equivalent(nil, function(f)
            local saved = f:save(); saved.gear.slot_ranged = "gear-A"
            f:call("load_loadout", "1")
            local capabilities = f.env.CareerSettings.es_knight.item_slot_types_by_slot_name.slot_ranged
            table.insert(capabilities, 1, "melee"); f:call("load_loadout", "1")
            table.remove(capabilities, 1); return f:call("load_loadout", "1")
        end, function(f) H.equal(#f.writes, 10) end)
    end)
    H.test("GUT saved-loadout owner captures private config but reads the same policy table method", function()
        local f = fixture(false); f:save()
        f.deps.mod = {}; f.deps.slot_policy = {}; f.deps.dbg = function() error("retargeted config") end
        f.deps.dbg_alert = function() error("retargeted alert") end
        local calls = 0
        f.policy.validate = function() calls = calls + 1; return false, "late-table-policy" end
        f:call("load_loadout", "1")
        H.equal(calls, 4); H.equal(#f.writes, 0)
        local alerts = 0
        for _, row in ipairs(f.trace) do if row[1] == "alert" then alerts = alerts + 1 end end
        H.equal(alerts, 4); H.equal(f.trace[#f.trace][1], "debug")
    end)
    H.test("GUT saved-loadout owner engine globals and publisher fields remain late", function()
        equivalent(nil, function(f)
            f.env.Managers = { player = f.env.Managers.player, backend = { get_interface = function(_, which)
                f.trace[#f.trace + 1] = { "late-backend", which }
                return f.backend:get_interface(which)
            end } }
            f.env.SPProfiles = { { careers = { { name = "es_knight", display_name = "late-career" } } } }
            f.env.Localize = function(key) return "LATE:" .. key end
            f.env.InventorySettings = { slots_by_ui_slot_index = { { name = "slot_melee" } },
                slots_by_cosmetic_index = { { name = "slot_hat" } } }
            f.env.CareerSettings = { es_knight = { item_slot_types_by_slot_name = {
                slot_melee = { "ranged" }, slot_hat = { "hat" },
            } } }
            local set = f.env.BackendUtils.set_loadout_item
            f.env.BackendUtils = { set_loadout_item = function(...)
                f.trace[#f.trace + 1] = { "late-set" }; return set(...)
            end }
            f:save()
            local calls = 0
            f.mod._gut925_generation = function() return 700 end
            f.mod._gut925_publish_if_unobserved = function(before) H.equal(before, 700); calls = calls + 1 end
            f:call("load_loadout", "1"); H.equal(calls, 1)
            return f:call("list_loadouts")
        end, function(f)
            H.equal(#f.writes, 1)
            local backends, sets = 0, 0
            for _, row in ipairs(f.trace) do
                if row[1] == "late-backend" then backends = backends + 1 end
                if row[1] == "late-set" then sets = sets + 1 end
            end
            H.truthy(backends > 0); H.equal(sets, 1)
        end)
    end)
    H.test("GUT saved-loadout owner registrar error escapes with original object and no masking", function()
        local token = {}
        for _, old in ipairs({ true, false }) do
            local ok, err = pcall(fixture, old, { registrar_error = token })
            H.equal(ok, false); H.equal(err, token)
        end
    end)
end
