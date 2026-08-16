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

    H.test("issue 1033 clears modded stores without replacing table identity", function()
        local store = { mercenary = { selected_index = 2 }, ranger = { selected_index = 1 } }
        local overlay = { mercenary = { [2] = { slot_hat = "mod_hat" } }, zealot = {} }
        local store_identity, overlay_identity = store, overlay

        local count, found = Policy.clear_modded_loadouts(store, overlay, "mercenary")
        H.equal(count, 1)
        H.equal(found, true)
        H.equal(store, store_identity)
        H.equal(overlay, overlay_identity)
        H.equal(store.mercenary, nil)
        H.equal(overlay.mercenary, nil)
        H.truthy(store.ranger ~= nil)
        H.truthy(overlay.zealot ~= nil)

        count, found = Policy.clear_modded_loadouts(store, overlay)
        H.equal(count, 2)
        H.equal(found, true)
        H.equal(next(store), nil)
        H.equal(next(overlay), nil)
    end)

    H.test("issue 1033 reset preserves the #954 bot designation across the clear", function()
        local designated = {
            selected_index = 3,
            _seeded = true,
            _slot_integrity_v2 = true,
            bot_index = 2,
            bot_loadout = { slot_melee = "bot_hammer", slot_ranged = "bot_pistols" },
            _bot_designation_snapshot_v2 = true,
            loadouts = {
                [1] = { slot_melee = "modded_sword" },
                [2] = { slot_melee = "bot_hammer", slot_ranged = "bot_pistols" },
            },
        }
        local store = {
            mercenary = designated,
            ranger = { selected_index = 1, _seeded = true, loadouts = { [1] = {} } },
        }
        local overlay = { mercenary = { [1] = { slot_hat = "mod_hat" } } }
        local snapshot_identity = designated.bot_loadout

        local count = Policy.clear_modded_loadouts(store, overlay)
        H.equal(count, 2)
        -- Designated career: exactly the designation set survives on a bare
        -- re-seedable shell; every modded-loadout field is wiped.
        local kept = store.mercenary
        H.truthy(kept, "bot designation dropped by full reset")
        H.equal(kept.bot_index, 2)
        H.equal(kept.bot_loadout, snapshot_identity)
        H.equal(kept._bot_designation_snapshot_v2, true,
            "one-time native-import marker wiped: next read would re-import PlayerData (#954)")
        H.equal(kept._seeded, nil, "seed marker must clear so DEFAULT forces a reseed")
        H.equal(kept._slot_integrity_v2, nil)
        H.equal(next(kept.loadouts), nil, "modded saved rows must clear")
        H.equal(kept.selected_index, 1)
        -- Undesignated career and the cosmetic overlay clear exactly as before.
        H.equal(store.ranger, nil)
        H.equal(next(overlay), nil)

        -- Explicit-career reset takes the same boundary.
        local store2 = { mercenary = {
            bot_index = 1,
            bot_loadout = { slot_melee = "bot" },
            _bot_designation_snapshot_v2 = true,
            loadouts = { [1] = { slot_melee = "modded" } },
        } }
        local overlay2 = { mercenary = { [1] = { slot_skin = "mod_skin" } } }
        local count2, found2 = Policy.clear_modded_loadouts(store2, overlay2, "mercenary")
        H.equal(count2, 1)
        H.equal(found2, true)
        H.truthy(store2.mercenary, "bot designation dropped by explicit-career reset")
        H.equal(store2.mercenary.bot_index, 1)
        H.equal(store2.mercenary._bot_designation_snapshot_v2, true)
        H.equal(next(store2.mercenary.loadouts), nil)
        H.equal(overlay2.mercenary, nil)

        -- A partial designation (pre-#954 store shape: index only, no marker) is
        -- still the user's choice and survives field-for-field.
        local store3 = { mercenary = { bot_index = 3, loadouts = { [3] = {} } } }
        Policy.clear_modded_loadouts(store3, {})
        H.equal(store3.mercenary.bot_index, 3)
        H.equal(store3.mercenary._bot_designation_snapshot_v2, nil)
    end)

    H.test("issue 273 gear capture requires durable slot ownership, cosmetics exempt", function()
        -- Gear slots: capture-eligible only on an explicit true owner verdict (fail closed).
        H.equal(Policy.capture_slot_durable("slot_melee", true), true)
        H.equal(Policy.capture_slot_durable("slot_melee", false), false)
        H.equal(Policy.capture_slot_durable("slot_ranged", nil), false)
        H.equal(Policy.capture_slot_durable("slot_necklace", false), false)
        -- Cosmetic slots keep current behavior: Deus maps them to "items"
        -- (backend_interface_deus_base.lua:7-14), so they stay unconditionally eligible.
        H.equal(Policy.capture_slot_durable("slot_skin", false), true)
        H.equal(Policy.capture_slot_durable("slot_hat", nil), true)
        H.equal(Policy.capture_slot_durable("slot_frame", false), true)
        H.equal(Policy.capture_slot_durable("slot_pose", false), true)

        -- End-to-end with the exit path's true-table-identity owner semantics
        -- (_gut_exit_snapshot_core.lua): a Deus-owned melee slot is rejected, an
        -- items-owned one accepted, unknown ownership fails closed.
        local core_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_exit_snapshot_core.lua"
        local Core = assert(loadfile(core_path))()
        local items_interface, deus_interface = {}, {}
        H.equal(Policy.capture_slot_durable("slot_melee",
            Core.slot_owned_by_items(deus_interface, items_interface)), false)
        H.equal(Policy.capture_slot_durable("slot_melee",
            Core.slot_owned_by_items(items_interface, items_interface)), true)
        H.equal(Policy.capture_slot_durable("slot_ranged",
            Core.slot_owned_by_items(nil, items_interface)), false)
    end)

    H.test("issue 273 BackendUtils capture hook wires the owner gate for gear", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        local gate_use = source:find(
            "if Policy.capture_slot_durable(slot_name, _slot_owned_by_items(slot_name)) then",
            1, true)
        H.truthy(gate_use, "equip capture does not consult the durable-owner gate")
        local owner_def = source:find("local function _slot_owned_by_items(slot_name)", 1, true)
        H.truthy(owner_def, "shared slot-owner resolver missing")
        H.truthy(owner_def < gate_use,
            "owner resolver must be defined before the capture hook that captures it")
        H.truthy(source:find(
            "return ok and ExitSnapshotCore.slot_owned_by_items(slot_interface, items_interface)",
            1, true), "owner resolver no longer uses true-table-identity semantics")
        H.truthy(source:find("reason=foreign-loadout-interface", 1, true),
            "foreign-owner skip evidence missing")
    end)

    H.test("issue 1033 plans deterministic official career copies", function()
        local mirror = { _career_data = {
            zealot = { { slot_melee = "hammer" } },
            mercenary = { { slot_melee = "sword" } },
            malformed = false,
        } }
        H.deep_equal(Policy.official_seed_careers(mirror), { "mercenary", "zealot" })
        H.deep_equal(Policy.official_seed_careers(mirror, "zealot"), { "zealot" })
        H.deep_equal(Policy.official_seed_careers(mirror, "missing"), {})
        H.deep_equal(Policy.official_seed_careers(nil), {})
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
        H.equal(persisted, 1,
            "legacy detached snapshot should receive its one-time migration marker")
        _G.printf = old_printf
    end)

    H.test("issue 954 imports pre-owner vanilla bot designation exactly once", function()
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
                selected_index = 1,
                loadouts = {
                    [1] = { slot_melee = "owner_sword", slot_ranged = "owner_crossbow" },
                    [2] = { slot_melee = "bot_hammer", slot_ranged = "bot_pistols" },
                },
            },
            empire_soldier = {
                selected_index = 1,
                bot_index = 2,
                bot_loadout = { slot_melee = "explicit_sword", slot_ranged = "explicit_gun" },
                loadouts = {
                    [1] = { slot_melee = "native_wrong", slot_ranged = "native_wrong" },
                    [2] = { slot_melee = "explicit_sword", slot_ranged = "explicit_gun" },
                },
            },
        }
        local native = { witch_hunter = 2, empire_soldier = 1 }
        local persist_calls = 0
        local old_printf = _G.printf
        _G.printf = function() end
        Runtime.install(fake_mod, {
            mode = function() return "store" end,
            store = function() return store end,
            persist = function() persist_calls = persist_calls + 1 end,
            policy = Policy,
            slot_names = { "slot_melee", "slot_ranged" },
            mode_off = "off",
            mode_store = "store",
            mode_readonly = "readonly",
            log_prefix = "gut_dev",
            native_bot_assignments = function() return native end,
        })
        local getter = assert(hooks["BackendInterfaceItemPlayfab.get_bot_loadout"])
        local iface = {
            _bot_loadouts = {
                witch_hunter = { slot_melee = "owner_sword", slot_ranged = "owner_crossbow" },
                empire_soldier = { slot_melee = "native_wrong", slot_ranged = "native_wrong" },
            },
        }

        local result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(store.witch_hunter.bot_index, 2)
        H.equal(store.witch_hunter.bot_loadout.slot_melee, "bot_hammer")
        H.equal(result.witch_hunter.slot_melee, "bot_hammer")
        H.equal(store.empire_soldier.bot_index, 2,
            "existing GUT designation must outrank stale PlayerData")
        H.equal(result.empire_soldier.slot_melee, "explicit_sword")
        H.equal(persist_calls, 1)
        H.equal(Runtime.live_check(
            iface, store, Policy, { "slot_melee", "slot_ranged" }, native), nil)

        -- Editing the source row after import must not mutate the bot snapshot,
        -- and the migration marker must prevent repeat persistence.
        store.witch_hunter.loadouts[2].slot_melee = "player_edited_after_import"
        iface._bot_loadouts.witch_hunter.slot_melee = "player_edited_after_import"
        result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.witch_hunter.slot_melee, "bot_hammer")
        H.equal(store.witch_hunter.bot_loadout.slot_melee, "bot_hammer")
        H.equal(persist_calls, 1)
        _G.printf = old_printf
    end)

    H.test("issue 954 runtime check rejects native assignment with zero owned snapshot", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_bot_loadout_snapshot.lua"
        local Runtime = assert(loadfile(runtime_path))()
        local store = {
            witch_hunter = {
                selected_index = 1,
                loadouts = { [1] = { slot_melee = "owner" } },
            },
        }
        local iface = { _bot_loadouts = { witch_hunter = { slot_melee = "owner" } } }
        H.equal(Runtime.live_check(
            iface, store, Policy, { "slot_melee" }, { witch_hunter = 1 }),
            "native bot designation not imported career=witch_hunter")
    end)

    H.test("issue 954 native designation waits for its saved row", function()
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
                loadouts = { [1] = { slot_melee = "owner" } },
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
            native_bot_assignments = function() return { witch_hunter = 2 } end,
        })
        local getter = assert(hooks["BackendInterfaceItemPlayfab.get_bot_loadout"])
        local iface = { _bot_loadouts = { witch_hunter = { slot_melee = "owner" } } }

        local result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.witch_hunter.slot_melee, "owner")
        H.equal(store.witch_hunter.bot_loadout, nil)
        H.equal(persist_calls, 0)

        store.witch_hunter.loadouts[2] = { slot_melee = "late_bot_row" }
        result = getter(function(self) return self._bot_loadouts end, iface)
        H.equal(result.witch_hunter.slot_melee, "late_bot_row")
        H.equal(store.witch_hunter.bot_loadout.slot_melee, "late_bot_row")
        H.equal(persist_calls, 1)
        _G.printf = old_printf
    end)

    H.test("issue 954 absent and malformed native designations do not churn", function()
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
            witch_hunter = { loadouts = { [1] = { slot_melee = "owner" } } },
            empire_soldier = { loadouts = { [1] = { slot_melee = "owner" } } },
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
            native_bot_assignments = function()
                return { empire_soldier = "not-an-index" }
            end,
        })
        local getter = assert(hooks["BackendInterfaceItemPlayfab.get_bot_loadout"])
        local iface = {
            _bot_loadouts = {
                witch_hunter = { slot_melee = "owner" },
                empire_soldier = { slot_melee = "owner" },
            },
        }
        getter(function(self) return self._bot_loadouts end, iface)
        H.equal(persist_calls, 1)
        getter(function(self) return self._bot_loadouts end, iface)
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

    -- Canonical loadout slot list (backend_interface_item_playfab.lua:25-35),
    -- mirroring LOADOUT_SLOT_NAMES in _gut_native_loadouts.lua.
    local SLOT_NAMES = {
        "slot_ranged", "slot_melee", "slot_skin", "slot_hat",
        "slot_necklace", "slot_ring", "slot_trinket_1", "slot_frame", "slot_pose",
    }
    local JEWELRY = { slot_necklace = true, slot_ring = true, slot_trinket_1 = true }

    local function full_row(prefix)
        local row = {}
        for _, slot in ipairs(SLOT_NAMES) do row[slot] = prefix .. slot end
        return row
    end

    H.test("issues 375/402 row integrity repairs missing slots, never deliberate unequips", function()
        -- Vanilla marks exactly the three jewelry slots unequippable
        -- (inventory_settings.lua:43/52/61): empty jewelry is a legitimate choice.
        H.truthy(type(Policy.UNEQUIPPABLE_SLOTS) == "table")
        for slot in pairs(JEWELRY) do
            H.equal(Policy.is_unequippable_slot(slot), true)
        end
        H.equal(Policy.is_unequippable_slot("slot_melee"), false)
        H.equal(Policy.is_unequippable_slot("slot_hat"), false)

        -- Predicate: nil row corrupt; complete row healthy; each never-emptiable slot
        -- missing => corrupt; each jewelry slot missing => still healthy.
        H.equal(Policy.row_is_corrupt_partial(nil, SLOT_NAMES), true)
        H.equal(Policy.row_is_corrupt_partial(full_row("x_"), SLOT_NAMES), false)
        for _, slot in ipairs(SLOT_NAMES) do
            local row = full_row("x_")
            row[slot] = nil
            H.equal(Policy.row_is_corrupt_partial(row, SLOT_NAMES), not JEWELRY[slot],
                "predicate wrong for missing " .. slot)
        end

        -- Migration pass: fills genuinely-missing visual slots from official, leaves
        -- deliberately-emptiable jewelry empty, never clobbers owned values.
        local official = full_row("off_")
        local entry = { loadouts = { { slot_melee = "own_m", slot_ranged = "own_r" } } }
        local repaired = Policy.repair_missing_loadout_slots(entry, { official }, SLOT_NAMES)
        H.equal(repaired, 4)  -- skin, hat, frame, pose
        local row = entry.loadouts[1]
        H.equal(row.slot_melee, "own_m")
        H.equal(row.slot_ranged, "own_r")
        H.equal(row.slot_skin, "off_slot_skin")
        H.equal(row.slot_hat, "off_slot_hat")
        H.equal(row.slot_necklace, nil)
        H.equal(row.slot_ring, nil)
        H.equal(row.slot_trinket_1, nil)

        -- A healthy row with a deliberate ring unequip survives the migration intact.
        local edited = full_row("own_")
        edited.slot_ring = nil
        local entry2 = { loadouts = { edited } }
        H.equal(Policy.repair_missing_loadout_slots(entry2, { official }, SLOT_NAMES), 0)
        H.equal(edited.slot_ring, nil)
    end)

    H.test("issue 375 corrupt-row refill repairs everything except accessory slots", function()
        local official = full_row("off_")
        official.talents = "1,2,3,4,5,6"
        -- Corruption signature: lost its melee. Genuinely-missing slots (and talents)
        -- refill; jewelry holes stay empty; owned values survive.
        local corrupt = { slot_ranged = "own_r" }
        H.equal(Policy.row_is_corrupt_partial(corrupt, SLOT_NAMES), true)
        local filled = Policy.repair_corrupt_row(corrupt, official)
        H.equal(filled, 6)  -- melee, skin, hat, frame, pose, talents
        H.equal(corrupt.slot_melee, "off_slot_melee")
        H.equal(corrupt.slot_ranged, "own_r")
        H.equal(corrupt.slot_hat, "off_slot_hat")
        H.equal(corrupt.talents, "1,2,3,4,5,6")
        H.equal(corrupt.slot_necklace, nil)
        H.equal(corrupt.slot_ring, nil)
        H.equal(corrupt.slot_trinket_1, nil)
    end)

    H.test("issue 1033 native reseed is one bounded mod-owned transaction", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        local reset_start = assert(source:find("function M.reset_modded_loadouts", 1, true))
        local reset_end = assert(source:find("mod._gut_reset_modded_loadouts", reset_start, true))
        local reset_source = source:sub(reset_start, reset_end - 1)
        H.truthy(reset_source:find("Policy.clear_modded_loadouts(store, overlay, career_arg)", 1, true))
        H.truthy(reset_source:find("Policy.official_seed_careers(mirror, career_arg)", 1, true))
        H.truthy(reset_source:find("_ensure_seeded(mirror, careers[i], true)", 1, true))
        H.truthy(reset_source:find("_persist()\n    _persist_overlay()\n    _dirtify()", 1, true),
            "bulk reset must persist each mod-owned table once and dirtify once")
        H.truthy(source:find("mod._gut_reset_modded_loadouts = function(source)", 1, true))
        H.equal(reset_source:find("mirror:set_character_data", 1, true), nil,
            "official reseed must not write the mirror")
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
