-- WP-GUT-04 (#402): loadout isolation contract 1. Loads the production module of each listed
-- tree with loadfile and exercises rows_clean, the functional writer probe and the fail-closed
-- status logic with fake classes. The live probe through the real hooks is the rig case
-- qa/runtime/gut/issue_402_isolation_contract.lua.
return function(H, repo_root)
    local TREES = { "gui_tweaker_dev" }

    local KEYS = {
        "slot_ranged", "slot_melee", "slot_skin", "slot_hat",
        "slot_necklace", "slot_ring", "slot_trinket_1", "slot_frame", "slot_pose", "talents",
    }

    local function load_module(tree)
        local path = repo_root .. "/" .. tree .. "/scripts/mods/" .. tree .. "/_gut_loadout_isolation.lua"
        return assert(loadfile(path))()
    end

    local function read_source(tree, file)
        local f = assert(io.open(repo_root .. "/" .. tree .. "/scripts/mods/" .. tree .. "/" .. file, "rb"))
        local src = f:read("*a")
        f:close()
        return src
    end

    local function rows()
        return {
            es_mercenary = {
                { slot_melee = "m1", slot_necklace = "n1", talents = "1,2,3,1,2,3" },
                { slot_melee = "m2", slot_necklace = "n2", talents = "1,1,1,1,1,1" },
            },
            we_shade = { { slot_melee = "s1" } },
        }
    end

    -- A fake class whose two writers answer `answer(...)`; records every self it was given.
    local function fake_class(answer)
        local selves = {}
        local class = {
            set_character_data = function(self, ...)
                selves[#selves + 1] = self
                return answer("set_character_data", self, ...)
            end,
            set_career_read_only_data = function(self, ...)
                selves[#selves + 1] = self
                return answer("set_career_read_only_data", self, ...)
            end,
        }
        return class, selves
    end

    local function deps_for(Isolation, class, overrides)
        local live_mirror = { _characters_data_key = "characters_data",
            _career_data = rows(), _career_data_mirror = rows() }
        local deps = {
            class = class,
            in_modded_realm = function() return true end,
            mode = function() return "store" end,
            mirror = function() return live_mirror end,
            keys = KEYS,
        }
        for k, v in pairs(overrides or {}) do deps[k] = v end
        return deps, live_mirror
    end

    local function each_tree(fn)
        for i = 1, #TREES do
            fn(load_module(TREES[i]), " (" .. TREES[i] .. ")", TREES[i])
        end
    end

    local function token_class(Isolation)
        return fake_class(function(method, self, a, b, c, d)
            local career = method == "set_character_data" and a or d
            if career == Isolation.PROBE_CAREER then return Isolation.PROBE_TOKEN end
        end)
    end

    H.test("loadout isolation rows_clean compares rows, keys and row sets", function()
        each_tree(function(Isolation, label)
            H.equal(Isolation.rows_clean(rows(), rows(), KEYS), true, "equal tables are clean" .. label)

            local changed = rows()
            changed.es_mercenary[2].slot_necklace = "cim_minted_necklace"
            local clean, detail = Isolation.rows_clean(changed, rows(), KEYS)
            H.equal(clean, false, "one differing slot is not clean" .. label)
            H.truthy(type(detail) == "string" and detail:find("es_mercenary", 1, true)
                and detail:find("row=2", 1, true) and detail:find("slot_necklace", 1, true),
                "detail names career, row and key" .. label)

            local extra = rows()
            extra.es_mercenary[3] = { slot_melee = "m3" }
            H.equal((Isolation.rows_clean(extra, rows(), KEYS)), false, "an extra row is not clean" .. label)
            H.equal((Isolation.rows_clean(rows(), extra, KEYS)), false, "a row missing on the live side is not clean" .. label)

            local extra_career = rows()
            extra_career.wh_zealot = { { slot_melee = "z1" } }
            H.equal((Isolation.rows_clean(extra_career, rows(), KEYS)), false, "an extra career is not clean" .. label)

            local talents = rows()
            talents.we_shade[1].talents = "2,2,2,2,2,2"
            H.equal((Isolation.rows_clean(talents, rows(), KEYS)), false, "talents are compared" .. label)

            local other_key = rows()
            other_key.es_mercenary[1].not_a_loadout_key = true
            H.equal(Isolation.rows_clean(other_key, rows(), KEYS), true, "keys outside the list are ignored" .. label)

            H.equal(Isolation.rows_clean(nil, rows(), KEYS), nil, "missing career_data" .. label)
            H.equal(Isolation.rows_clean(rows(), nil, KEYS), nil, "missing mirror" .. label)
            H.equal(Isolation.rows_clean(rows(), rows(), nil), nil, "missing keys" .. label)
        end)
    end)

    H.test("loadout isolation probe owns the chokepoint only when both writers answer the token", function()
        each_tree(function(Isolation, label)
            local class, selves = token_class(Isolation)
            local deps, live_mirror = deps_for(Isolation, class)
            local iso = Isolation.new(deps)
            H.equal(iso.contract, 1, "contract field" .. label)
            local status = iso:status()
            H.equal(status.contract, 1, label)
            H.equal(status.realm_modded, true, label)
            H.equal(status.mode, "store", label)
            H.equal(status.chokepoint_owned, true, "token from both writers owns the chokepoint" .. label)
            H.equal(status.official_rows_clean, true, label)
            H.equal(status.reason, nil, label)
            H.equal(#selves, 2, "both writers probed once" .. label)
            for i = 1, #selves do
                H.truthy(selves[i] ~= live_mirror, "the probe never receives the live mirror" .. label)
                H.equal(selves[i]._characters_data_key, "characters_data", "throwaway self carries the Adventure key" .. label)
            end
            H.truthy(selves[1] ~= selves[2], "each writer gets its own throwaway self" .. label)
            local safe, reason = iso.safe_to_write_loadout()
            H.equal(safe, true, "store mode with a live capture is safe" .. label)
            H.equal(reason, nil, label)

            H.equal(iso.status().chokepoint_owned, true, "dot call works like colon call" .. label)
        end)
    end)

    H.test("loadout isolation probe fails closed on throw, nil, partial answers and missing writers", function()
        each_tree(function(Isolation, label)
            local throwing = fake_class(function(_, self) return self._career_data.missing.field end)
            local s = Isolation.new(deps_for(Isolation, throwing)).status()
            H.equal(s.chokepoint_owned, false, "a writer that throws (vanilla on a throwaway self) is not owned" .. label)
            H.truthy(type(s.reason) == "string", "a reason is given" .. label)
            H.equal((Isolation.new(deps_for(Isolation, throwing)).safe_to_write_loadout()), false, label)

            local silent = fake_class(function() return nil end)
            H.equal(Isolation.new(deps_for(Isolation, silent)).status().chokepoint_owned, false,
                "a writer that returns nil is not owned" .. label)

            local half = fake_class(function(method, self, a)
                if method == "set_character_data" and a == Isolation.PROBE_CAREER then return Isolation.PROBE_TOKEN end
            end)
            H.equal(Isolation.new(deps_for(Isolation, half)).status().chokepoint_owned, false,
                "only one writer answering is not owned" .. label)

            local wrong = fake_class(function() return "gut-captured-v0" end)
            H.equal(Isolation.new(deps_for(Isolation, wrong)).status().chokepoint_owned, false,
                "a different token is not owned" .. label)

            for _, class in ipairs({ false, {}, { set_character_data = function() end } }) do
                local iso = Isolation.new(deps_for(Isolation, class or nil))
                H.equal(iso.status().chokepoint_owned, false, "missing class or writer is not owned" .. label)
                H.equal((iso.safe_to_write_loadout()), false, label)
            end
        end)
    end)

    H.test("loadout isolation safe_to_write_loadout is false when mode is off whatever the probe says", function()
        each_tree(function(Isolation, label)
            local class = token_class(Isolation)
            local iso = Isolation.new(deps_for(Isolation, class, { mode = function() return "off" end }))
            H.equal(iso.status().chokepoint_owned, true, "the probe itself still answers" .. label)
            H.equal(iso.status().mode, "off", label)
            local safe, reason = iso.safe_to_write_loadout()
            H.equal(safe, false, "mode off is never safe" .. label)
            H.truthy(type(reason) == "string" and reason ~= "", "a reason is given" .. label)

            local readonly = Isolation.new(deps_for(Isolation, class, { mode = function() return "readonly" end }))
            H.equal(readonly.status().mode, "readonly", label)
            H.equal((readonly.safe_to_write_loadout()), true, "readonly mode with a live capture is safe" .. label)
        end)
    end)

    H.test("loadout isolation fails closed on unknown mode, official realm and dependency errors", function()
        each_tree(function(Isolation, label)
            local class = token_class(Isolation)
            local unknown = Isolation.new(deps_for(Isolation, class, { mode = function() return "STORE" end }))
            H.equal(unknown.status().mode, "off", "an unknown mode reports off" .. label)
            H.equal((unknown.safe_to_write_loadout()), false, "an unknown mode is not safe" .. label)

            local mode_error = Isolation.new(deps_for(Isolation, class, { mode = function() error("boom") end }))
            H.equal((mode_error.safe_to_write_loadout()), false, "a mode error is not safe" .. label)

            local no_mode = Isolation.new(deps_for(Isolation, class, { mode = false }))
            H.equal((no_mode.safe_to_write_loadout()), false, "a missing mode function is not safe" .. label)

            local official = Isolation.new(deps_for(Isolation, class, { in_modded_realm = function() return false end }))
            H.equal(official.status().realm_modded, false, label)
            H.equal((official.safe_to_write_loadout()), false, "never safe outside the modded realm" .. label)

            local realm_error = Isolation.new(deps_for(Isolation, class, { in_modded_realm = function() error("x") end }))
            H.equal((realm_error.safe_to_write_loadout()), false, "a realm error is not safe" .. label)

            local no_deps = Isolation.new(nil)
            local s = no_deps.status()
            H.equal(s.contract, 1, label)
            H.equal(s.chokepoint_owned, false, label)
            H.equal((no_deps.safe_to_write_loadout()), false, "no dependencies is not safe" .. label)

            local mirror_error = Isolation.new(deps_for(Isolation, class, { mirror = function() error("no backend") end }))
            H.equal(mirror_error.status().official_rows_clean, nil, "an unreadable mirror leaves rows unknown" .. label)
            H.equal(mirror_error.status().chokepoint_owned, true, label)
            H.equal((mirror_error.safe_to_write_loadout()), false, "an unreadable live mirror is not safe" .. label)
            local no_mirror = Isolation.new(deps_for(Isolation, class, { mirror = function() return nil end }))
            H.equal((no_mirror.safe_to_write_loadout()), false, "a missing live mirror is not safe" .. label)

            local versus_deps, versus_mirror = deps_for(Isolation, class)
            versus_mirror._characters_data_key = "vs_characters_data"
            local versus = Isolation.new(versus_deps)
            H.equal(versus.status().chokepoint_owned, true, "the probe carries the Adventure key" .. label)
            local versus_safe, versus_reason = versus.safe_to_write_loadout()
            H.equal(versus_safe, false, "a Versus mirror passes writes to vanilla, so it is not safe" .. label)
            H.truthy(type(versus_reason) == "string" and versus_reason ~= "", label)

            local dirty_deps, dirty_mirror = deps_for(Isolation, class)
            dirty_mirror._career_data.es_mercenary[1].slot_melee = "minted"
            local dirty = Isolation.new(dirty_deps).status()
            H.equal(dirty.official_rows_clean, false, "a changed official row is reported" .. label)
            H.truthy(type(dirty.reason) == "string" and dirty.reason:find("slot_melee", 1, true), label)
        end)
    end)

    H.test("loadout isolation in-game check covers both realms", function()
        each_tree(function(Isolation, label)
            local class = token_class(Isolation)
            H.equal(Isolation.check(Isolation.new(deps_for(Isolation, class))), nil, "modded realm, capture live" .. label)
            H.truthy(Isolation.check(nil), "unpublished contract fails" .. label)

            local throwing = fake_class(function(_, self) return self._career_data.x end)
            H.truthy(Isolation.check(Isolation.new(deps_for(Isolation, throwing))),
                "modded realm without capture fails" .. label)

            local dirty_deps, dirty_mirror = deps_for(Isolation, class)
            dirty_mirror._career_data.es_mercenary[1].slot_melee = "minted"
            H.truthy(Isolation.check(Isolation.new(dirty_deps)), "modded realm with dirty official rows fails" .. label)

            local no_mirror = Isolation.new(deps_for(Isolation, class, { mirror = function() return nil end }))
            H.equal(Isolation.check(no_mirror), nil, "unknown rows do not fail the modded check" .. label)

            local official_vanilla = Isolation.new(deps_for(Isolation, throwing, {
                in_modded_realm = function() return false end, mode = function() return "off" end }))
            H.equal(Isolation.check(official_vanilla), nil, "official realm reaching vanilla passes" .. label)

            local official_answered = Isolation.new(deps_for(Isolation, class, {
                in_modded_realm = function() return false end, mode = function() return "off" end }))
            H.truthy(Isolation.check(official_answered), "a token answered in the official realm fails (mode gate broken)" .. label)
        end)
    end)

    H.test("loadout isolation probe answer sits right after the MODE_OFF return in both writer hooks", function()
        for i = 1, #TREES do
            local tree = TREES[i]
            local src = read_source(tree, "_gut_native_loadouts.lua")
            local hooks = {
                { 'mod:hook("PlayFabMirrorAdventure", "set_character_data"', "career_name" },
                { 'mod:hook("PlayFabMirrorAdventure", "set_career_read_only_data"', "career" },
            }
            for _, hook in ipairs(hooks) do
                local start = src:find(hook[1], 1, true)
                H.truthy(start, tree .. ": hook present " .. hook[1])
                local off_end = start and select(2, src:find("if m == MODE_OFF or not " .. hook[2] .. " then\n        return func%(self, [^\n]+%)\n    end\n", start))
                H.truthy(off_end, tree .. ": MODE_OFF early return found")
                local probe = "    if " .. hook[2] .. " == Isolation.PROBE_CAREER then return Isolation.PROBE_TOKEN end\n"
                H.equal(off_end and src:sub(off_end + 1, off_end + #probe), probe,
                    tree .. ": probe answer must directly follow the MODE_OFF return in " .. hook[1])
            end
            local _, count = src:gsub('mod:hook%("PlayFabMirrorAdventure", "set_character_data"', "")
            H.equal(count, 1, tree .. ": one set_character_data hook")
            local _, count2 = src:gsub('mod:hook%("PlayFabMirrorAdventure", "set_career_read_only_data"', "")
            H.equal(count2, 1, tree .. ": one set_career_read_only_data hook")
            H.truthy(src:find("mod.loadout_isolation = Isolation.new({", 1, true), tree .. ": contract published")
            H.equal(src:find('"_check_career_data"', 1, true), nil, tree .. ": no hook on _check_career_data")
        end
    end)

    -- Executes each tree's real _gut_native_loadouts.lua against detached Lua values (same
    -- approach as test_gut_public_native_loadouts.lua). PlayFabMirrorAdventure dispatches into
    -- the registered hook exactly as a VMF hook chain does, with a vanilla stand-in that, like the
    -- real writers (playfab_mirror_base.lua:1928-1930, :3631-3633), indexes `self` first.
    local SLOTS = { "slot_ranged", "slot_melee", "slot_skin", "slot_hat", "slot_necklace",
        "slot_ring", "slot_trinket_1", "slot_frame", "slot_pose" }
    local function native_fixture(tree, options)
        options = options or {}
        local mod_id = tree == "gui_tweaker" and "gut" or "gut_dev"
        local state = { settings = { native_loadouts = {}, native_cosmetic_overlay = {} },
            hooks = {}, checks = {}, writes = {}, vanilla_calls = 0 }
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.MODDED_REALM = options.official ~= true
        env.script_data = { ["eac-untrusted"] = true }
        env.InventorySettings = { MAX_NUM_CUSTOM_LOADOUTS = 30 }
        env.ItemMasterList = {}
        env.PlayerData = { loadout_selection = { bot_equipment = {} } }
        env.printf = function() end
        local row, items = { talents = "1,2,3,4,5,6" }, {}
        for _, slot in ipairs(SLOTS) do
            local id = "official_" .. slot
            row[slot] = id
            items[id] = { backend_id = id, data = { key = id }, ItemId = id }
        end
        local mirror_row = {}
        for k, v in pairs(row) do mirror_row[k] = v end
        local mirror = {
            _characters_data_key = options.versus and "vs_characters_data" or "characters_data",
            _career_data = { es_mercenary = { row } }, _career_data_mirror = { es_mercenary = { mirror_row } },
            _career_loadouts = { es_mercenary = 1 }, _inventory_items = items,
        }
        function mirror:get_default_loadouts() return { row } end
        local iface = { _backend_mirror = mirror, _items = items, _dirty = false, _bot_loadouts = {} }
        function iface:get_item_from_id(id) return self._items[id] end
        function iface:get_all_backend_items() return self._items end
        local backend = { _interfaces = { items = iface } }
        function backend:get_interface() return iface end
        function backend:get_loadout_interface_by_slot() return iface end
        function backend:dirtify_interfaces() end
        function backend:commit() end
        env.Managers = { backend = backend }
        env.BackendUtils = { set_loadout_item = function() end,
            get_loadout_item_id = function(_, slot) return row[slot] end,
            get_loadout_item = function(_, slot) return items[row[slot]] end }
        env.LoadoutUtils = { sync_loadout_slot = function() end }
        local function vanilla_set_character_data(self, career)
            state.vanilla_calls = state.vanilla_calls + 1
            return self._career_data[career]
        end
        local function vanilla_set_career_read_only_data(self, _, _, _, career)
            state.vanilla_calls = state.vanilla_calls + 1
            return self._career_loadouts[career]
        end
        env.PlayFabMirrorAdventure = {
            set_character_data = function(...)
                return state.hooks["PlayFabMirrorAdventure.set_character_data"](vanilla_set_character_data, ...)
            end,
            set_career_read_only_data = function(...)
                return state.hooks["PlayFabMirrorAdventure.set_career_read_only_data"](vanilla_set_career_read_only_data, ...)
            end,
        }
        local mod = { _gut_reset_presentation = { capture_before = function() end, reconcile = function() end } }
        function mod:get(key) return state.settings[key] end
        function mod:set(key, value) state.settings[key] = value; state.writes[#state.writes + 1] = key end
        function mod:echo() end
        function mod:command() end
        local function hook(_, class, method, callback)
            if class == env.BackendUtils then class = "BackendUtils" end
            if class == env.LoadoutUtils then class = "LoadoutUtils" end
            state.hooks[tostring(class) .. "." .. method] = callback
        end
        mod.hook, mod.hook_safe = hook, hook
        mod._gut_rt_register = function(name, callback) state.checks[name] = callback end
        env.get_mod = function(name) if name == mod_id then return mod end end
        function mod:dofile(path)
            local f = assert(io.open(repo_root .. "/" .. tree .. "/" .. path .. ".lua", "rb"))
            local text = f:read("*a")
            f:close()
            local loader = assert(loadstring(text, "@" .. path))
            setfenv(loader, env)
            return loader()
        end
        mod._gut_official_loadout_boot_guard = mod:dofile("scripts/mods/" .. tree .. "/_gut_official_loadout_boot_guard")
        local loader = assert(loadstring(read_source(tree, "_gut_native_loadouts.lua"), "@" .. tree .. "-native"))
        setfenv(loader, env)
        state.native = loader()
        state.mod, state.env, state.mirror = mod, env, mirror
        return state
    end

    H.test("loadout isolation real writer hooks answer the probe in store and readonly mode only", function()
        for i = 1, #TREES do
            local tree = TREES[i]
            local s = native_fixture(tree)
            local iso = s.mod.loadout_isolation
            H.truthy(type(iso) == "table", tree .. ": contract published on the mod object")
            H.equal(iso.contract, 1, tree)
            local status = iso.status()
            H.equal(status.realm_modded, true, tree)
            H.equal(status.mode, "store", tree)
            H.equal(status.chokepoint_owned, true, tree .. ": both real hooks answered the probe")
            H.equal(status.official_rows_clean, true, tree)
            H.equal((iso.safe_to_write_loadout()), true, tree .. ": store mode is safe")
            H.equal(s.vanilla_calls, 0, tree .. ": the probe never reached vanilla in store mode")
            H.equal(s.settings.native_loadouts.__gut_isolation_probe__, nil, tree .. ": the probe wrote nothing")
            H.equal(#s.writes, 0, tree .. ": the probe persisted nothing")
            H.equal(type(s.checks.issue402_isolation_contract), "function", tree .. ": in-game check registered")
            H.equal(s.checks.issue402_isolation_contract(), nil, tree .. ": in-game check passes in store mode")

            -- A real career write is still captured into the store, never into official data.
            s.mirror.set_character_data = s.env.PlayFabMirrorAdventure.set_character_data
            s.mirror:set_character_data("es_mercenary", "slot_necklace", "minted_necklace")
            H.equal(s.mirror._career_data.es_mercenary[1].slot_necklace, "official_slot_necklace", tree)
            H.equal(s.settings.native_loadouts.es_mercenary.loadouts[1].slot_necklace, "minted_necklace", tree)
            H.equal(iso.status().official_rows_clean, true, tree .. ": official rows still equal the mirror")

            s.settings.gut_use_non_modded_loadouts = true
            local readonly = iso.status()
            H.equal(readonly.mode, "readonly", tree)
            H.equal(readonly.chokepoint_owned, true, tree .. ": readonly hooks answer the probe too")
            H.equal(s.vanilla_calls, 0, tree)
        end
    end)

    H.test("loadout isolation real hooks reach vanilla in the official realm and Versus is unsafe", function()
        for i = 1, #TREES do
            local tree = TREES[i]
            local official = native_fixture(tree, { official = true })
            local iso = official.mod.loadout_isolation
            local status = iso.status()
            H.equal(status.realm_modded, false, tree)
            H.equal(status.mode, "off", tree)
            H.equal(status.chokepoint_owned, false, tree .. ": official realm must not answer the probe")
            H.equal(official.vanilla_calls, 2, tree .. ": both probes reached the vanilla writers")
            H.equal((iso.safe_to_write_loadout()), false, tree)
            H.equal(official.checks.issue402_isolation_contract(), nil, tree .. ": in-game check passes in official")

            local versus = native_fixture(tree, { versus = true })
            H.equal(versus.mod.loadout_isolation.status().chokepoint_owned, true, tree)
            local safe, reason = versus.mod.loadout_isolation.safe_to_write_loadout()
            H.equal(safe, false, tree .. ": a Versus mirror passes writes to vanilla")
            H.truthy(type(reason) == "string", tree)

            local leaked = native_fixture(tree)
            leaked.mirror._career_data.es_mercenary[1].slot_melee = "leaked_minted_id"
            H.equal(leaked.mod.loadout_isolation.status().official_rows_clean, false, tree)
            H.truthy(leaked.checks.issue402_isolation_contract(), tree .. ": a dirty official row fails the check")
        end
    end)
end
