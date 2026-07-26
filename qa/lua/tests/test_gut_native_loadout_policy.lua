return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadout_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("native-loadout readonly preserves exact CWV instances", function()
        H.equal(Policy.readonly_action("slot_melee", "cwv_es_dual_axes_001"), "preserve")
        H.equal(Policy.readonly_action("slot_melee", "cwv_es_dual_maces_001"), "preserve")
        H.equal(Policy.readonly_action("slot_ranged", "cwv_es_crossbow_100"), "preserve")
        H.equal(Policy.is_cwv_backend_id("cwv_es_dual_axes"), false)
        H.equal(Policy.is_cwv_backend_id("D12DB867521442B3"), false)
    end)

    H.test("native-loadout readonly keeps official realm isolation policy", function()
        H.equal(Policy.mode(false, false), Policy.MODE_OFF)
        H.equal(Policy.mode(false, true), Policy.MODE_OFF)
        H.equal(Policy.mode(true, false), Policy.MODE_STORE)
        H.equal(Policy.mode(true, true), Policy.MODE_READONLY)
        H.equal(Policy.readonly_action("slot_hat", "mod_hat_instance"), "preserve")
        H.equal(Policy.readonly_action("slot_melee", "D12DB867521442B3"), "clear")
        H.equal(Policy.readonly_action("slot_necklace", "cwv_fake_001"), "block")
        H.equal(Policy.readonly_action("talents", "1,2,3,4,5,6"), "block")
    end)

    H.test("issue 954 bot designation snapshots do not alias owner rows", function()
        local slots = { "slot_melee", "slot_ranged", "slot_hat" }
        local owner_row = {
            slot_melee = "wp_hammer",
            slot_ranged = "wp_hammer_shield",
            slot_hat = { key = "wp_hat" },
            talents = "1,2,3,4,5,6",
        }
        local bot = Policy.snapshot_bot_loadout(owner_row, slots)

        H.equal(bot.slot_melee, "wp_hammer")
        H.equal(bot.slot_ranged, "wp_hammer_shield")
        H.equal(bot.slot_hat.key, "wp_hat")
        H.equal(bot.talents, nil)

        owner_row.slot_melee = "owner_changed"
        owner_row.slot_hat.key = "owner_hat_changed"
        H.equal(bot.slot_melee, "wp_hammer")
        H.equal(bot.slot_hat.key, "wp_hat")
    end)

    H.test("issue 954 bot snapshot rejects absent rows and slot contracts", function()
        H.equal(Policy.snapshot_bot_loadout(nil, { "slot_melee" }), nil)
        H.equal(Policy.snapshot_bot_loadout({}, nil), nil)
    end)

    H.test("issue 954 stable and dev runtime use detached bot snapshots", function()
        for _, stream in ipairs({ "gui_tweaker", "gui_tweaker_dev" }) do
            local module_path = repo_root .. "/" .. stream .. "/scripts/mods/"
                .. stream .. "/_gut_bot_loadout_snapshot.lua"
            local file = assert(io.open(module_path, "rb"))
            local module_source = file:read("*a")
            file:close()
            if stream == "gui_tweaker_dev" then
                H.truthy(module_source:find(
                    "snapshot, snapshot_detail = policy.snapshot_bot_loadout", 1, true))
                H.truthy(module_source:find(
                    "migration.entry.bot_loadout = migration.snapshot", 1, true))
                H.truthy(module_source:find(
                    "Runtime.snapshots_equal(bot[career_name], snapshot", 1, true))
                H.truthy(module_source:find(
                    "policy.snapshot_bot_loadout(snapshot, slot_names)", 1, true))
                H.truthy(module_source:find(
                    "bot[replacement.career_name] = replacement.snapshot", 1, true))
                H.truthy(module_source:find('"get_bot_loadout"', 1, true),
                    "dev bot consumer boundary is not hooked")
                H.truthy(module_source:find('safe_overlay(self, "bot-read")', 1, true),
                    "dev bot consumer boundary does not reconcile the runtime cache")
            else
                H.truthy(module_source:find(
                    "entry.bot_loadout = policy.snapshot_bot_loadout", 1, true))
                H.truthy(module_source:find(
                    "bot[career_name] = policy.snapshot_bot_loadout(snapshot", 1, true),
                    "stable detached snapshot behavior changed before promotion")
                H.equal(module_source:find('"get_bot_loadout"', 1, true), nil,
                    "in-flight dev bot-read repair leaked into stable")
            end

            local owner_path = repo_root .. "/" .. stream .. "/scripts/mods/"
                .. stream .. "/_gut_native_loadouts.lua"
            local owner = assert(io.open(owner_path, "rb"))
            local owner_source = owner:read("*a")
            owner:close()
            H.truthy(owner_source:find("BotLoadoutSnapshot.install(mod", 1, true))
            H.truthy(owner_source:find('name = "issue954_bot_loadout_snapshot"', 1, true))
        end
    end)

    H.test("issue 954 bot consumer repairs stale startup cache and in-place drift", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_bot_loadout_snapshot.lua"
        local Runtime = assert(loadfile(runtime_path))()
        local safe_hooks, hooks = {}, {}
        local fake_mod = {}
        function fake_mod:hook_safe(class_name, method_name, callback)
            safe_hooks[class_name .. "." .. method_name] = callback
        end
        function fake_mod:hook(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
        end

        local store = {
            witch_hunter = {
                bot_index = 2,
                loadouts = {
                    [1] = { slot_melee = "owner_sword", slot_ranged = "owner_crossbow" },
                    [2] = { slot_melee = "bot_hammer", slot_ranged = "bot_pistols" },
                },
                bot_loadout = {
                    slot_melee = "bot_hammer",
                    slot_ranged = "bot_pistols",
                },
            },
        }
        local policy = {}
        function policy.snapshot_bot_loadout(row, slots)
            if type(row) ~= "table" or type(slots) ~= "table" then return nil end
            local out = {}
            for i = 1, #slots do
                local slot = slots[i]
                local value = row[slot]
                if type(value) == "table" then
                    local copy = {}
                    for key, nested in pairs(value) do copy[key] = nested end
                    out[slot] = copy
                else
                    out[slot] = value
                end
            end
            return out
        end

        local old_printf = _G.printf
        _G.printf = function() end
        local persisted = 0
        Runtime.install(fake_mod, {
            mode = function(items) return items and items.is_adventure and "store" or "off" end,
            store = function() return store end,
            persist = function() persisted = persisted + 1 end,
            policy = policy,
            slot_names = { "slot_melee", "slot_ranged" },
            mode_off = "off",
            mode_store = "store",
            mode_readonly = "readonly",
            log_prefix = "gut_dev",
        })

        local getter = assert(hooks["BackendInterfaceItemPlayfab.get_bot_loadout"])
        local after_refresh = assert(
            safe_hooks["BackendInterfaceItemPlayfab.refresh_bot_loadouts"])
        local iface = {
            is_adventure = true,
            -- Simulate vanilla's owner-derived cache having been built before
            -- the mod installed or before its Adventure gate became eligible.
            _bot_loadouts = {
                witch_hunter = {
                    slot_melee = "owner_sword",
                    slot_ranged = "owner_crossbow",
                },
            },
        }
        H.equal(Runtime.live_check(iface, store, policy, { "slot_melee", "slot_ranged" }),
            "runtime bot cache mismatch career=witch_hunter")
        local forwarded
        local native_refreshed = false
        local result = getter(function(self, career_name)
            forwarded = career_name
            -- Vanilla get_bot_loadout refreshes synchronously when `_dirty`.
            -- The repair must happen after that refresh, not before it.
            self._bot_loadouts = {
                witch_hunter = {
                    slot_melee = "owner_after_dirty_refresh",
                    slot_ranged = "owner_crossbow",
                },
            }
            native_refreshed = true
            return self._bot_loadouts
        end, iface, "witch_hunter")
        H.equal(forwarded, "witch_hunter")
        H.truthy(native_refreshed)
        H.equal(result.witch_hunter.slot_melee, "bot_hammer")
        H.equal(result.witch_hunter.slot_ranged, "bot_pistols")
        H.equal(Runtime.live_check(iface, store, policy, { "slot_melee", "slot_ranged" }), nil)

        iface._bot_loadouts.witch_hunter.slot_melee = "owner_after_explicit_refresh"
        after_refresh(iface)
        H.equal(iface._bot_loadouts.witch_hunter.slot_melee, "bot_hammer")

        -- Same table identity, unexpected writer: the read edge must detect and
        -- repair it instead of trusting a one-shot identity stamp.
        iface._bot_loadouts.witch_hunter.slot_melee = "owner_changed_again"
        H.equal(Runtime.live_check(iface, store, policy, { "slot_melee", "slot_ranged" }),
            "runtime bot cache mismatch career=witch_hunter")
        result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.witch_hunter.slot_melee, "bot_hammer")

        -- Official/non-Adventure interfaces remain exactly native.
        iface.is_adventure = false
        iface._bot_loadouts.witch_hunter.slot_melee = "official_owner"
        result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.witch_hunter.slot_melee, "official_owner")
        H.equal(persisted, 0)
        _G.printf = old_printf
    end)

    H.test("issue 954 bounded snapshot comparison does not cause repair churn", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_bot_loadout_snapshot.lua"
        local Runtime = assert(loadfile(runtime_path))()
        local deep_a, deep_b = {}, {}
        local left, right = deep_a, deep_b
        for i = 1, 20 do
            left.child, right.child = {}, {}
            left, right = left.child, right.child
        end
        H.equal(Runtime.snapshots_equal(
            { slot_hat = deep_a },
            { slot_hat = deep_b },
            { "slot_hat" }
        ), nil)

        local wide_a, wide_b = {}, {}
        for i = 1, 300 do
            wide_a["key_" .. i] = i
            wide_b["key_" .. i] = i
        end
        H.equal(Runtime.snapshots_equal(
            { slot_hat = wide_a },
            { slot_hat = wide_b },
            { "slot_hat" }
        ), nil)
    end)

    H.test("issue 954 detached snapshot copying rejects wide and cyclic values", function()
        local wide = {}
        for i = 1, 300 do wide["key_" .. i] = i end
        local snapshot, detail = Policy.snapshot_bot_loadout(
            { slot_melee = wide },
            { "slot_melee" }
        )
        H.equal(snapshot, nil)
        H.equal(detail, "node-bound")

        local cyclic = {}
        cyclic.self = cyclic
        snapshot, detail = Policy.snapshot_bot_loadout(
            { slot_melee = cyclic },
            { "slot_melee" }
        )
        H.equal(snapshot, nil)
        H.equal(detail, "cycle")
    end)

    H.test("issue 954 bounded copy defers first-identity repair and migration", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_bot_loadout_snapshot.lua"
        local Runtime = assert(loadfile(runtime_path))()
        local hooks = {}
        local fake_mod = {}
        function fake_mod:hook_safe() end
        function fake_mod:hook(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
        end
        local wide = {}
        for i = 1, 300 do wide["key_" .. i] = i end
        local store = {
            witch_hunter = {
                bot_loadout = { slot_melee = wide },
            },
        }
        local persist_calls = 0
        local old_printf = _G.printf
        _G.printf = function() end
        Runtime.install(fake_mod, {
            mode = function() return "store" end,
            store = function() return store end,
            persist = function() persist_calls = persist_calls + 1 end,
            policy = Policy,
            slot_names = { "slot_melee" },
            mode_off = "off",
            mode_store = "store",
            mode_readonly = "readonly",
            log_prefix = "gut_dev",
        })
        local getter = assert(hooks["BackendInterfaceItemPlayfab.get_bot_loadout"])
        local iface = {
            _bot_loadouts = {
                witch_hunter = { slot_melee = "native" },
            },
        }
        local result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.witch_hunter.slot_melee, "native")
        H.equal(iface._bot_loadouts.witch_hunter.slot_melee, "native")
        H.equal(persist_calls, 0)

        local cyclic = {}
        cyclic.self = cyclic
        store.witch_hunter = {
            bot_index = 1,
            loadouts = {
                [1] = { slot_melee = cyclic },
            },
        }
        result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.witch_hunter.slot_melee, "native")
        H.equal(store.witch_hunter.bot_loadout, nil)
        H.equal(persist_calls, 0)
        _G.printf = old_printf
    end)

    H.test("issue 954 mixed valid and corrupt careers reconcile transactionally", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_bot_loadout_snapshot.lua"
        local Runtime = assert(loadfile(runtime_path))()
        local hooks = {}
        local fake_mod = {}
        function fake_mod:hook_safe() end
        function fake_mod:hook(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
        end
        local cyclic = {}
        cyclic.self = cyclic
        local store = {
            empire_soldier = {
                bot_index = 1,
                loadouts = {
                    [1] = { slot_melee = "valid_saved" },
                },
            },
            witch_hunter = {
                bot_index = 1,
                loadouts = {
                    [1] = { slot_melee = cyclic },
                },
            },
        }
        local persist_calls = 0
        local old_printf = _G.printf
        _G.printf = function() end
        Runtime.install(fake_mod, {
            mode = function() return "store" end,
            store = function() return store end,
            persist = function() persist_calls = persist_calls + 1 end,
            policy = Policy,
            slot_names = { "slot_melee" },
            mode_off = "off",
            mode_store = "store",
            mode_readonly = "readonly",
            log_prefix = "gut_dev",
        })
        local getter = assert(hooks["BackendInterfaceItemPlayfab.get_bot_loadout"])
        local iface = {
            _bot_loadouts = {
                empire_soldier = { slot_melee = "native_empire" },
                witch_hunter = { slot_melee = "native_wh" },
            },
        }

        local result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.empire_soldier.slot_melee, "native_empire")
        H.equal(result.witch_hunter.slot_melee, "native_wh")
        H.equal(store.empire_soldier.bot_loadout, nil)
        H.equal(store.witch_hunter.bot_loadout, nil)
        H.equal(persist_calls, 0)

        store.witch_hunter = nil
        result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.empire_soldier.slot_melee, "valid_saved")
        H.truthy(store.empire_soldier.bot_loadout)
        H.equal(persist_calls, 1)
        _G.printf = old_printf
    end)

    H.test("issue 954 bot-read reconciliation fails open and retries persistence", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_bot_loadout_snapshot.lua"
        local Runtime = assert(loadfile(runtime_path))()
        local hooks = {}
        local fake_mod = {}
        function fake_mod:hook_safe() end
        function fake_mod:hook(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
        end
        local store = {
            witch_hunter = {
                bot_index = 1,
                loadouts = {
                    [1] = { slot_melee = "bot_hammer" },
                },
            },
        }
        local persist_calls = 0
        local copy_fault = true
        local policy = {}
        function policy.snapshot_bot_loadout(row, slots)
            if copy_fault then error("copy fault") end
            local out = {}
            for i = 1, #slots do out[slots[i]] = row[slots[i]] end
            return out
        end
        local old_printf = _G.printf
        _G.printf = function() end
        Runtime.install(fake_mod, {
            mode = function() return "store" end,
            store = function() return store end,
            persist = function()
                persist_calls = persist_calls + 1
                if persist_calls == 1 then error("persist fault") end
            end,
            policy = policy,
            slot_names = { "slot_melee" },
            mode_off = "off",
            mode_store = "store",
            mode_readonly = "readonly",
            log_prefix = "gut_dev",
        })
        local getter = assert(hooks["BackendInterfaceItemPlayfab.get_bot_loadout"])
        local iface = {
            _bot_loadouts = {
                witch_hunter = { slot_melee = "native_owner" },
            },
        }

        local result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.witch_hunter.slot_melee, "native_owner",
            "a reconciliation fault must preserve the native return")
        H.equal(store.witch_hunter.bot_loadout, nil)

        copy_fault = false
        result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.witch_hunter.slot_melee, "bot_hammer")
        H.equal(persist_calls, 1)
        H.truthy(store.witch_hunter.bot_loadout)

        result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.witch_hunter.slot_melee, "bot_hammer")
        H.equal(persist_calls, 2, "failed migration persistence was not retried")
        _G.printf = old_printf
    end)

    H.test("issue 954 corrupt bot store is bounded and leaves native cache intact", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_bot_loadout_snapshot.lua"
        local Runtime = assert(loadfile(runtime_path))()
        local hooks = {}
        local fake_mod = {}
        function fake_mod:hook_safe() end
        function fake_mod:hook(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
        end
        local store = {}
        for i = 1, 65 do
            store["corrupt_" .. i] = {
                bot_loadout = { slot_melee = "unexpected" },
            }
        end
        local snapshot_calls = 0
        local policy = {}
        function policy.snapshot_bot_loadout()
            snapshot_calls = snapshot_calls + 1
            return { slot_melee = "unexpected" }
        end
        local old_printf = _G.printf
        _G.printf = function() end
        Runtime.install(fake_mod, {
            mode = function() return "store" end,
            store = function() return store end,
            persist = function() end,
            policy = policy,
            slot_names = { "slot_melee" },
            mode_off = "off",
            mode_store = "store",
            mode_readonly = "readonly",
            log_prefix = "gut_dev",
        })
        local iface = {
            _bot_loadouts = {
                witch_hunter = { slot_melee = "native" },
            },
        }
        local getter = assert(hooks["BackendInterfaceItemPlayfab.get_bot_loadout"])
        local result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.witch_hunter.slot_melee, "native")
        H.equal(snapshot_calls, 0)
        _G.printf = old_printf
    end)

    H.test("issue 954 refresh overlay uses concrete backend interface identity", function()
        local owner_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua"
        local owner = assert(io.open(owner_path, "rb"))
        local source = owner:read("*a")
        owner:close()
        H.truthy(source:find("local function _adventure_mode(items_iface)", 1, true),
            "Adventure gate cannot consume the concrete items interface")
        H.truthy(source:find("local mirror = items_iface and items_iface._backend_mirror", 1, true),
            "Adventure gate still requires Managers.backend identity during interface refresh")
        H.truthy(source:find('{ "BackendInterfaceItemPlayfab", "get_bot_loadout" }', 1, true),
            "hook inventory omits the dev bot-cache consumer boundary")
    end)

    H.test("native-loadout LA outer capture canonicalizes cosmetic identity", function()
        local value, source = Policy.canonical_equip_value("slot_hat", "la_inventory_uuid", {
            ItemId = "la_hat_masterlist",
        })
        H.equal(value, "la_hat_masterlist")
        H.equal(source, "ItemId")

        value, source = Policy.canonical_equip_value("slot_skin", "la_skin_uuid", {
            override_id = "la_skin_override",
            ItemId = "la_skin_masterlist",
        })
        H.equal(value, "la_skin_override")
        H.equal(source, "override_id")

        value, source = Policy.canonical_equip_value("slot_pose", "la_pose_uuid", nil)
        H.equal(value, nil)
        H.equal(source, "unresolved_item")

        value, source = Policy.canonical_equip_value("slot_melee", "la_weapon_uuid", nil)
        H.equal(value, "la_weapon_uuid")
        H.equal(source, "backend_id")
    end)

    H.test("native-loadout LA outer hook wires canonical cosmetics into owned storage", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("local value, source = _bu_canonical_value(backend_id, slot_name)", 1, true),
            "BackendUtils hook does not invoke canonical resolver")
        H.truthy(source:find("_capture_bu_equip(mode, mirror, career_name, slot_name, value, source)", 1, true),
            "resolved equip does not enter store/overlay capture")
        H.truthy(source:find("local is_loadout_slot = _is_loadout_slot(slot_name)", 1, true),
            "outer hook is not gated to the complete loadout-slot partition")
    end)

    H.test("issue 402 native loadout row integrity covers every slot", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("local function _repair_missing_loadout_slots(entry, official_rows)", 1, true),
            "missing-slot migration helper absent")
        H.truthy(source:find("entry._slot_integrity_v2 = true", 1, true),
            "slot-integrity migration marker absent")
        H.truthy(source:find("for i = 1, #LOADOUT_SLOT_NAMES do", 1, true),
            "corrupt-row predicate is not based on the canonical slot list")
        H.truthy(source:find("if row[slot] == nil then return true end", 1, true),
            "nil native loadout slots are not treated as corrupt")
        H.truthy(source:find("slots_repaired = _repair_missing_loadout_slots(entry, cd)", 1, true),
            "seed repair does not run the full-slot migration")
    end)

    H.test("issue 402 official scrub uses complete slot contract", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("for _, slot in ipairs(LOADOUT_SLOT_NAMES) do", 1, true),
            "official scrub does not iterate the canonical slot list")
        H.truthy(source:find("if not _slot_resolves(slot, id) then", 1, true),
            "official scrub does not treat nil/unresolved slots as broken")
        H.truthy(source:find('mod:echo("[scrub] official loadouts clean -- no broken native loadout slots")', 1, true),
            "scrub result still describes only weapon/frame coverage")
        H.truthy(source:find('rawget(ItemMasterList, id)', 1, true),
            "cosmetic slot resolver does not accept stable ItemMasterList keys")
    end)
end
