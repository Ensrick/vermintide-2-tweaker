-- Official promotion: execute the installed native owner and both private children.
-- Captured callbacks operate on detached Lua values only; this proves routing,
-- retained stores and return/error contracts, not VMF, cloud or game execution.
return function(H, repo_root)
    local base = "gui_tweaker/scripts/mods/gui_tweaker/"
    local command_path = "scripts/mods/gui_tweaker/_gut_native_loadout_commands"
    local check_path = "scripts/mods/gui_tweaker/_gut_native_loadout_checks"
    local function read(path)
        local file = assert(io.open(repo_root .. "/" .. path, "rb"))
        local source = file:read("*a"); file:close(); return source
    end
    local core = read(base .. "_gut_native_loadouts.lua")
    local check_names = {
        "issue954_bot_loadout_snapshot", "issue354_wt_loadout_lifecycle_trace",
        "native_loadouts_failsafe_inert", "native_loadouts_mod_owned_exempt_readonly",
        "issue353_outer_capture_transaction", "issue1033_default_official_reseed_wired",
        "issue273_capture_owner_gate", "native_loadouts_no_hardcoded_6",
        "native_loadouts_gear_fallback_nondestructive", "native_loadouts_official_write_chokepoint",
        "native_loadouts_hook_targets_unique", "native_loadouts_fallback_index_translation",
        "native_loadouts_trace_throttle_per_change", "native_loadouts_seed_repair_predicate",
        "issue375_deliberate_empty_slots_preserved", "issue402_official_scrub_all_slots",
        "issue354_exit_snapshot_lifecycle_edges", "issue1688_modded_realm_authority",
        "native_loadouts_installed",
    }
    local slots = { "slot_ranged", "slot_melee", "slot_skin", "slot_hat", "slot_necklace",
        "slot_ring", "slot_trinket_1", "slot_frame", "slot_pose" }
    local cosmetic = { slot_skin = true, slot_hat = true, slot_frame = true, slot_pose = true }
    local function capture(...) return select("#", ...), { ... } end
    local function fixture(options)
        options = options or {}
        local state = {
            settings = { native_loadouts = {}, native_cosmetic_overlay = {} },
            hooks = {}, commands = {}, command_order = {}, checks = {}, loads = {},
            writes = {}, lines = {}, echoes = {}, dirtied = 0, commits = 0,
            raw_resolves = 0, live = {}, overrides = {},
        }
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.MODDED_REALM = options.official ~= true
        env.script_data = { ["eac-untrusted"] = true }
        env.InventorySettings = { MAX_NUM_CUSTOM_LOADOUTS = 30 }
        env.ItemMasterList = {}
        env.PlayerData = { loadout_selection = { bot_equipment = {} } }
        env.printf = function(fmt, ...) state.lines[#state.lines + 1] = string.format(fmt, ...) end
        local row, items = { talents = "1,2,3,4,5,6" }, {}
        for _, slot in ipairs(slots) do
            local id = "official_" .. slot
            row[slot] = id
            items[id] = { backend_id = id, data = { key = id }, ItemId = id }
            state.live[slot] = id
            if cosmetic[slot] then env.ItemMasterList[id] = { key = id } end
        end
        local mirror = {
            _characters_data_key = options.versus and "vs_characters_data" or "characters_data",
            _career_data = { es_mercenary = { row } },
            _career_loadouts = { es_mercenary = 1 }, _inventory_items = items,
        }
        function mirror:get_default_loadouts() return { row } end
        local iface = {
            _backend_mirror = mirror, _items = items, _dirty = false, _bot_loadouts = {},
        }
        function iface:get_item_from_id(id)
            state.raw_resolves = state.raw_resolves + 1
            if options.resolve_error then error("resolve-failure", 0) end
            return self._items[id]
        end
        function iface:get_all_backend_items() return self._items end
        local backend = { _interfaces = { items = iface } }
        function backend:get_interface(name)
            H.equal(name, "items")
            if state.backend_error then error("backend-failure", 0) end
            return iface
        end
        function backend:get_loadout_interface_by_slot(slot)
            if state.owner_error then error("owner-failure", 0) end
            return state.overrides[slot] or iface
        end
        function backend:dirtify_interfaces() state.dirtied = state.dirtied + 1 end
        function backend:commit(force, callback)
            H.equal(force, true); state.commits = state.commits + 1
            state.commit_callback = callback
            return state.commit_id
        end
        env.Managers = { backend = backend }
        env.BackendUtils = {
            set_loadout_item = function() end,
            get_loadout_item_id = function(_, slot) return state.live[slot] end,
            get_loadout_item = function(_, slot)
                local id = state.live[slot]
                return id and items[id]
            end,
        }
        env.LoadoutUtils = { sync_loadout_slot = function() end }
        local mod = {
            _gut_reset_presentation = { capture_before = function() end, reconcile = function() end },
        }
        function mod:get(key) return state.settings[key] end
        function mod:set(key, value)
            H.truthy(key == "native_loadouts" or key == "native_cosmetic_overlay",
                "unexpected persistent setting " .. tostring(key))
            state.settings[key] = value; state.writes[#state.writes + 1] = key
        end
        function mod:echo(message) state.echoes[#state.echoes + 1] = message end
        function mod:command(name, _, callback)
            H.equal(state.commands[name], nil, "duplicate command " .. name)
            state.commands[name] = callback; state.command_order[#state.command_order + 1] = name
        end
        local function hook(_, class, method, callback)
            if class == env.BackendUtils then class = "BackendUtils" end
            if class == env.LoadoutUtils then class = "LoadoutUtils" end
            local name = class .. "." .. method
            H.equal(state.hooks[name], nil, "duplicate hook " .. name)
            state.hooks[name] = callback
        end
        mod.hook, mod.hook_safe = hook, hook
        mod._gut_rt_register = function(name, callback)
            H.equal(state.checks[name], nil); state.checks[name] = callback
        end
        env.get_mod = function(name) if name == "gut" then return mod end end
        function mod:dofile(path)
            state.loads[path] = (state.loads[path] or 0) + 1
            if options.disconnect == path then return {} end
            local loader = assert(loadstring(read("gui_tweaker/" .. path .. ".lua"), "@" .. path))
            setfenv(loader, env)
            local owner = loader()
            if path == command_path and options.disconnect_slot_resolver then
                local install = owner.install
                owner.install = function(...)
                    local api = install(...); api.slot_resolves = nil; return api
                end
            elseif path == check_path and options.check_create_error then
                owner.create = function() error(options.check_create_error, 0) end
            end
            return owner
        end
        mod._gut_official_loadout_boot_guard = mod:dofile(
            "scripts/mods/gui_tweaker/_gut_official_loadout_boot_guard")
        local loader = assert(loadstring(core, "@installed-public-native-owner")); setfenv(loader, env)
        local ok, native = pcall(loader)
        if options.disconnect or options.disconnect_slot_resolver or options.check_create_error then
            return ok, native, state
        end
        H.equal(ok, true, tostring(native))
        function mirror:set_character_data(career, slot, id, set_mirror, index)
            return state.hooks["PlayFabMirrorAdventure.set_character_data"](
                function(self, c, s, value, _, i)
                    self._career_data[c][i or 1][s] = value
                end, self, career, slot, id, set_mirror, index)
        end
        state.native, state.mod, state.env, state.mirror, state.iface, state.items =
            native, mod, env, mirror, iface, items
        function state:read(slot, index)
            return self.hooks["PlayFabMirrorAdventure.get_character_data"](
                function(m, career, key, idx)
                    return m._career_data[career][idx or m._career_loadouts[career]][key]
                end, mirror, "es_mercenary", slot, index)
        end
        return state
    end

    H.test("GUT official native owner installs private children once with original surfaces/order", function()
        local s = fixture()
        H.deep_equal(s.command_order, { "reset_modded_loadouts", "gut_loadout_status", "scrub_official_loadouts" })
        H.equal(s.loads[command_path], 1); H.equal(s.loads[check_path], 1)
        H.equal(s.loads["scripts/mods/gui_tweaker/_gut_official_loadout_boot_guard"], 1)
        H.equal(s.native.MARKER, "native_loadouts_v1")
        H.equal(s.native.loadout_lifecycle_owner.bind_snapshot_edges ~= nil, true)
        H.equal(type(s.mod._gut_reset_modded_loadouts), "function")
        H.equal(type(s.mod._gut_recover_missing_weapon), "function")
        H.equal(#s.native.rt_checks, #check_names)
        for i, name in ipairs(check_names) do
            H.equal(s.native.rt_checks[i].name, name)
            H.equal(s.native.rt_checks[i].fn(), nil, name)
        end
        H.equal(s.native.rt_checks[18].fn, s.mod._gut_official_loadout_boot_guard.check_realm_authority)
        H.equal(type(s.checks.issue954_modded_career_import), "function")
        H.equal(#s.writes, 0, "installation/checks persisted data")
        H.truthy(read("gui_tweaker/resource_packages/gui_tweaker/gui_tweaker.package")
            :find('"scripts/mods/gui_tweaker/*"', 1, true))
    end)

    H.test("GUT official native private-owner disconnection and missing resolver fail loudly", function()
        for _, path in ipairs({ command_path, check_path }) do
            local ok, err = fixture({ disconnect = path })
            H.equal(ok, false); H.truthy(tostring(err):find("nil value", 1, true))
        end
        local ok, err = fixture({ disconnect_slot_resolver = true })
        H.equal(ok, false); H.truthy(tostring(err):find("slot_resolves function required", 1, true))
        local token = {}
        ok, err = fixture({ check_create_error = token })
        H.equal(ok, false); H.equal(err, token)
    end)

    H.test("GUT official and Versus native hooks preserve exact passthrough tuples/no writes", function()
        for _, options in ipairs({ { official = true }, { versus = true } }) do
            local s = fixture(options)
            local function vanilla() return "first", nil, "third", nil end
            local args = { "es_mercenary", "slot_melee", "replacement", false, 1 }
            for _, method in ipairs({ "get_character_data", "get_career_loadouts", "has_loadout",
                "set_character_data", "set_career_read_only_data", "set_loadout_index",
                "add_loadout", "delete_loadout" }) do
                local n, tuple = capture(s.hooks["PlayFabMirrorAdventure." .. method](
                    vanilla, s.mirror, unpack(args)))
                H.equal(n, 4, method); H.equal(tuple[1], "first"); H.equal(tuple[3], "third")
            end
            local diverged, written = s.native.exit_snapshot("test")
            H.equal(diverged, 0); H.equal(written, false); H.equal(#s.writes, 0)
            H.equal(next(s.settings.native_loadouts), nil); H.equal(s.commits, 0)
        end
    end)

    H.test("GUT public store/readonly writers retain official isolation and deliberate empty jewelry", function()
        local s = fixture()
        H.equal(s:read("slot_melee"), "official_slot_melee")
        local official = s.mirror._career_data.es_mercenary[1]
        s.mirror:set_character_data("es_mercenary", "slot_melee", "late_modded_weapon")
        s.mirror:set_character_data("es_mercenary", "slot_ring", nil)
        H.equal(official.slot_melee, "official_slot_melee")
        H.equal(official.slot_ring, "official_slot_ring")
        H.equal(s.settings.native_loadouts.es_mercenary.loadouts[1].slot_ring, nil)
        H.equal(s:read("slot_melee"), "official_slot_melee", "unresolved fallback changed")
        H.equal(s.settings.native_loadouts.es_mercenary.loadouts[1].slot_melee, "late_modded_weapon")
        H.equal(s.raw_resolves, 0, "mirror read invoked refreshing item resolver")
        s.settings.gut_use_non_modded_loadouts = true
        s.mirror:set_character_data("es_mercenary", "slot_melee", "ordinary_weapon")
        s.mirror:set_character_data("es_mercenary", "slot_hat", "modded_hat")
        s.mirror:set_character_data("es_mercenary", "slot_melee", "cwv_es_dual_axes_001")
        H.equal(s:read("slot_hat"), "modded_hat")
        H.equal(s:read("slot_melee"), "cwv_es_dual_axes_001")
        H.equal(s.settings.native_cosmetic_overlay.es_mercenary[1].slot_hat, "modded_hat")
        H.equal(official.slot_hat, "official_slot_hat"); H.equal(s.commits, 0)
    end)

    H.test("GUT public outer capture preserves tuple/error behavior and denies Deus gear", function()
        local s = fixture()
        s:read("slot_melee") -- installs the deferred existing outer hook
        local capture_equip = assert(s.hooks["BackendUtils.set_loadout_item"])
        local function vanilla() return "equipped", nil, "last", nil end
        s.overrides.slot_melee = {}
        local n, tuple = capture(capture_equip(vanilla, "deus_generated", "es_mercenary", "slot_melee"))
        H.equal(n, 4); H.equal(tuple[1], "equipped"); H.equal(tuple[3], "last")
        H.equal(s.settings.native_loadouts.es_mercenary.loadouts[1].slot_melee, "official_slot_melee")
        s.overrides.slot_melee = nil
        capture_equip(vanilla, "new_modded", "es_mercenary", "slot_melee")
        H.equal(s.settings.native_loadouts.es_mercenary.loadouts[1].slot_melee, "new_modded")
        s.backend_error = true
        n, tuple = capture(capture_equip(vanilla, "ignored", "es_mercenary", "slot_hat"))
        H.equal(n, 4); H.equal(tuple[3], "last")
        H.equal(s.settings.native_loadouts.es_mercenary.loadouts[1].slot_hat, "official_slot_hat")
        local token = {}
        local ok, err = pcall(capture_equip, function() error(token, 0) end,
            "ignored", "es_mercenary", "slot_hat")
        H.equal(ok, false); H.equal(err, token)
    end)

    H.test("GUT public exit snapshot skips foreign gear, canonicalizes cosmetics and stays idempotent", function()
        local s = fixture()
        s:read("slot_melee")
        s.overrides.slot_melee = {}; s.live.slot_melee = "deus_generated"
        s.items.cosmetic_bid = { override_id = "stable_hat", ItemId = "other_hat" }
        s.live.slot_hat = "cosmetic_bid"
        local diverged, written = s.native.exit_snapshot("unload")
        H.equal(diverged, 1); H.equal(written, true)
        local row = s.settings.native_loadouts.es_mercenary.loadouts[1]
        H.equal(row.slot_melee, "official_slot_melee"); H.equal(row.slot_hat, "stable_hat")
        local before = #s.writes
        diverged, written = s.native.exit_snapshot("unload")
        H.equal(diverged, 0); H.equal(written, false); H.equal(#s.writes, before)
        H.equal(s.mirror._career_data.es_mercenary[1].slot_hat, "official_slot_hat")
    end)

    H.test("GUT public commands resolve late realm/backend and official scrub remains report-only by default", function()
        local s = fixture()
        s.commands.scrub_official_loadouts("apply")
        H.truthy(s.echoes[#s.echoes]:find("OFFICIAL", 1, true)); H.equal(s.commits, 0)
        s.env.MODDED_REALM = false
        s.mirror._career_data.es_mercenary[2] = { slot_melee = "unresolved" }
        local before = #s.writes
        s.commands.scrub_official_loadouts()
        H.equal(s.mirror._career_data.es_mercenary[2].slot_melee, "unresolved")
        H.equal(s.commits, 0); H.equal(#s.writes, before)
        s.commit_id = "commit-7"
        s.commands.scrub_official_loadouts("apply")
        H.equal(s.mirror._career_data.es_mercenary[2].slot_melee, "official_slot_melee")
        H.equal(s.commits, 1); H.equal(#s.writes, before)
        H.truthy(s.echoes[#s.echoes]:find("cloud commit requested (id=commit-7)", 1, true))
        s.commit_callback("failed")
        H.truthy(s.echoes[#s.echoes]:find("cloud commit FAILED", 1, true))
        s.commit_callback("success")
        H.truthy(s.echoes[#s.echoes]:find("cloud commit complete", 1, true))
        s.backend_error = true
        s.commands.gut_loadout_status()
        H.truthy(s.echoes[#s.echoes]:find("store EMPTY", 1, true))
    end)

    H.test("GUT public reset uses one durable owner and preserves detached bot designation", function()
        local s = fixture()
        s:read("slot_melee")
        local store = s.settings.native_loadouts
        local entry = store.es_mercenary
        entry.bot_index = 1; entry.bot_loadout = { slot_melee = "bot_weapon" }
        entry._bot_designation_snapshot_v2 = true
        entry.loadouts[1].slot_melee = "modded_weapon"
        local before = #s.writes
        local ok, result = s.mod._gut_reset_modded_loadouts("default")
        H.equal(ok, true); H.equal(result.seeded, 1); H.equal(#s.writes - before, 2)
        H.equal(s.settings.native_loadouts, store, "reset created a competing store")
        H.equal(store.es_mercenary.loadouts[1].slot_melee, "official_slot_melee")
        H.equal(store.es_mercenary.bot_loadout.slot_melee, "bot_weapon")
        H.equal(store.es_mercenary.bot_index, 1); H.equal(s.commits, 0)
    end)
end
