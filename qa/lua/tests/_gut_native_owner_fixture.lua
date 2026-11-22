-- Shared fixture: executes a tree's real _gut_native_loadouts.lua against detached Lua values
-- (same approach as test_gut_public_native_loadouts.lua). It proves routing and table effects of
-- the actual hook bodies, not VMF, cloud or game execution.
--
-- VMF-faithful settings: mod:get and mod:set deep-copy tables
-- (Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:54,74), so a test reads
-- the last SAVED copy (`state:saved(key)`) and counts saves per key (`state.saves[key]`).
-- Hooks are recorded by "Class.method"; `state:hook(name, ...)` calls one with a vanilla spy that
-- counts calls (`state.vanilla_calls`) and, like the real writers on a missing table, indexes
-- `self` first.
--
-- Usage: local Fixture = assert(loadfile(repo_root .. "/qa/lua/tests/_gut_native_owner_fixture.lua"))()
--        local s = Fixture.new(repo_root, "gui_tweaker_dev", options)
return (function()
    local Fixture = {}

    local function deepcopy(t)
        if type(t) ~= "table" then return t end
        local c = {}
        for k, v in pairs(t) do c[k] = deepcopy(v) end
        return c
    end
    Fixture.deepcopy = deepcopy

    Fixture.SLOTS = { "slot_ranged", "slot_melee", "slot_skin", "slot_hat",
        "slot_necklace", "slot_ring", "slot_trinket_1", "slot_frame", "slot_pose" }
    Fixture.GEAR = { "slot_ranged", "slot_melee", "slot_necklace", "slot_ring", "slot_trinket_1" }
    Fixture.WEAPONS = { "slot_melee", "slot_ranged" }

    -- Official row `n` for a career: every slot "<career>_<slot>_<n>", talents "n,n,n,n,n,n".
    function Fixture.official_row(career, n)
        local row = { talents = string.rep(tostring(n) .. ",", 5) .. tostring(n) }
        for i = 1, #Fixture.SLOTS do
            local slot = Fixture.SLOTS[i]
            row[slot] = career .. "_" .. slot .. "_" .. tostring(n)
        end
        return row
    end

    -- options:
    --   official = true          official realm (MODDED_REALM false)
    --   readonly = true          "Use non-modded loadouts" on
    --   careers = { es_mercenary = { rows = n, selected = i } }   official data (default 2 rows, 1)
    --   store, overlay           initial saved settings (deep-copied in)
    --   max_loadouts             InventorySettings.MAX_NUM_CUSTOM_LOADOUTS (default 30)
    --   extra_items              additional resolvable backend ids
    --   live                     { [slot] = id } BackendUtils live values (default: selected official row)
    function Fixture.new(repo_root, tree, options)
        options = options or {}
        local mod_id = tree == "gui_tweaker" and "gut" or "gut_dev"
        local function read(path)
            local f = assert(io.open(repo_root .. "/" .. path, "rb"))
            local text = f:read("*a")
            f:close()
            return text
        end
        local state = {
            settings = {
                native_loadouts = deepcopy(options.store or {}),
                native_cosmetic_overlay = deepcopy(options.overlay or {}),
                gut_use_non_modded_loadouts = options.readonly and true or false,
            },
            saves = {}, hooks = {}, checks = {}, commands = {}, lines = {}, echoes = {},
            vanilla_calls = 0, vanilla_args = {}, dirtied = 0, commits = 0,
        }
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.MODDED_REALM = options.official ~= true
        -- Engine math.clamp (Vermintide-2-Source-Code/foundation/scripts/util/math.lua:25-33).
        env.math = setmetatable({ clamp = function(value, min, max)
            if max < value then return max elseif value < min then return min end
            return value
        end }, { __index = math })
        env.script_data = { ["eac-untrusted"] = true }
        env.InventorySettings = { MAX_NUM_CUSTOM_LOADOUTS = options.max_loadouts or 30 }
        env.ItemMasterList = {}
        env.PlayerData = { loadout_selection = { bot_equipment = {} } }
        env.SPProfiles = { { careers = { { name = "es_mercenary" }, { name = "es_huntsman" } } } }
        env.printf = function(fmt, ...) state.lines[#state.lines + 1] = string.format(fmt, ...) end

        local careers = options.careers or { es_mercenary = { rows = 2, selected = 1 } }
        local career_data, career_loadouts, items = {}, {}, {}
        for career, spec in pairs(careers) do
            local rows = {}
            for n = 1, spec.rows do
                rows[n] = Fixture.official_row(career, n)
                for _, v in pairs(rows[n]) do items[v] = { backend_id = v, data = { key = v }, ItemId = v } end
            end
            career_data[career] = rows
            career_loadouts[career] = spec.selected
        end
        for _, id in ipairs(options.extra_items or {}) do
            items[id] = { backend_id = id, data = { key = id }, ItemId = id }
        end
        local mirror = {
            _characters_data_key = options.versus and "vs_characters_data" or "characters_data",
            _career_data = career_data,
            _career_data_mirror = deepcopy(career_data),
            _career_loadouts = career_loadouts,
            _inventory_items = items,
        }
        function mirror:get_default_loadouts(career) return { Fixture.official_row(career, 1) } end
        state.official_initial = deepcopy(career_data)
        state.official_loadouts_initial = deepcopy(career_loadouts)

        local iface = { _backend_mirror = mirror, _items = items, _dirty = false, _bot_loadouts = {} }
        function iface:get_item_from_id(id) return self._items[id] end
        function iface:get_all_backend_items() return self._items end
        local backend = { _interfaces = { items = iface } }
        function backend:get_interface() return iface end
        function backend:get_loadout_interface_by_slot() return iface end
        function backend:dirtify_interfaces() state.dirtied = state.dirtied + 1 end
        function backend:commit() state.commits = state.commits + 1 end
        env.Managers = { backend = backend }

        local first = next(careers)
        local live = options.live
        env.BackendUtils = {
            set_loadout_item = function() end,
            get_loadout_item_id = function(career, slot)
                if live then return live[slot] end
                local rows = career_data[career]
                local row = rows and rows[career_loadouts[career] or 1]
                return row and row[slot]
            end,
            get_loadout_item = function(career, slot)
                local id = env.BackendUtils.get_loadout_item_id(career, slot)
                return id and items[id]
            end,
        }
        env.LoadoutUtils = { sync_loadout_slot = function() end }

        local mod = {
            _gut_reset_presentation = { capture_before = function() end, reconcile = function() end },
        }
        function mod:get(key) return deepcopy(state.settings[key]) end
        function mod:set(key, value)
            state.settings[key] = deepcopy(value)
            state.saves[key] = (state.saves[key] or 0) + 1
        end
        function mod:echo(message) state.echoes[#state.echoes + 1] = message end
        function mod:command(name, _, callback) state.commands[name] = callback end
        local function hook(_, class, method, callback)
            if class == env.BackendUtils then class = "BackendUtils" end
            if class == env.LoadoutUtils then class = "LoadoutUtils" end
            state.hooks[tostring(class) .. "." .. method] = callback
        end
        mod.hook, mod.hook_safe = hook, hook
        mod._gut_rt_register = function(name, callback) state.checks[name] = callback end
        env.get_mod = function(name) if name == mod_id then return mod end end
        function mod:dofile(path)
            local loader = assert(loadstring(read(tree .. "/" .. path .. ".lua"), "@" .. path))
            setfenv(loader, env)
            return loader()
        end
        mod._gut_official_loadout_boot_guard = mod:dofile("scripts/mods/" .. tree .. "/_gut_official_loadout_boot_guard")
        local loader = assert(loadstring(read(tree .. "/scripts/mods/" .. tree .. "/_gut_native_loadouts.lua"),
            "@" .. tree .. "-native-owner"))
        setfenv(loader, env)
        state.native = loader()
        state.mod, state.env, state.mirror, state.iface, state.items = mod, env, mirror, iface, items
        state.first_career = first

        function state:saved(key) return deepcopy(self.settings[key]) end
        -- Calls a recorded hook. Mirror hooks get the fixture mirror as `self`.
        function state:hook(name, ...)
            local callback = assert(self.hooks[name], "hook not registered: " .. name)
            local function vanilla(...)
                self.vanilla_calls = self.vanilla_calls + 1
                self.vanilla_args[#self.vanilla_args + 1] = { ... }
                local target = ...
                if type(target) == "table" and target._career_data then
                    -- read-only vanilla stand-ins for the mirror readers
                    local _, career, key, index = ...
                    if name:find("get_character_data", 1, true) then
                        local rows = target._career_data[career]
                        local row = rows and rows[index or target._career_loadouts[career]]
                        return row and row[key]
                    end
                end
                return nil
            end
            if name:find("^PlayFabMirrorAdventure%.") then
                return callback(vanilla, self.mirror, ...)
            end
            return callback(vanilla, ...)
        end
        function state:official_untouched()
            local function equal(a, b)
                if a == b then return true end
                if type(a) ~= "table" or type(b) ~= "table" then return false end
                for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
                for k in pairs(b) do if a[k] == nil then return false end end
                return true
            end
            return equal(self.mirror._career_data, self.official_initial)
                and equal(self.mirror._career_data_mirror, self.official_initial)
                and equal(self.mirror._career_loadouts, self.official_loadouts_initial)
        end
        return state
    end

    return Fixture
end)()
