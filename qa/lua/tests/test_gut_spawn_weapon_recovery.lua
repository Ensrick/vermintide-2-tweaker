-- Behavioral coverage for the #1637 consumer-boundary recovery adapter:
-- candidate order, the literal printf miss route and its module-local ledger,
-- dedupe, error containment, the sync-RPC shadow hook and the install() wiring.
-- The global printf is swapped ONLY here, in the offline harness: deployed
-- source must never touch it (the deployed-source authority rejects any
-- deployed mod that mutates global printf, record-wide and fail-closed).
return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Policy = assert(loadfile(root .. "_gut_native_loadout_policy.lua"))()
    local SpawnPolicy = assert(loadfile(root .. "_gut_spawn_weapon_policy.lua"))()
    local Recovery = assert(loadfile(root .. "_gut_spawn_weapon_recovery.lua"))()

    local function with_printf(fn)
        local captured = {}
        local old = rawget(_G, "printf")
        rawset(_G, "printf", function(fmt, ...)
            captured[#captured + 1] = string.format(fmt, ...)
        end)
        local result = { pcall(fn, captured) }
        rawset(_G, "printf", old)
        if not result[1] then error(result[2], 0) end
        return captured
    end

    local function world()
        local master = {
            bw_sword = { key = "bw_sword", name = "bw_sword", slot_type = "melee", rarity = "plentiful",
                template = "one_handed_swords_template_1", right_hand_unit = "u", can_wield = { "bw_unchained" } },
            bw_skullstaff_fireball = { key = "bw_skullstaff_fireball", name = "bw_skullstaff_fireball",
                slot_type = "ranged", rarity = "plentiful", template = "staff", right_hand_unit = "u",
                left_hand_unit = "l", can_wield = { "bw_unchained" } },
        }
        local settings = { bw_unchained = { item_slot_types_by_slot_name = {
            slot_melee = { "melee" }, slot_ranged = { "ranged" } } } }
        local selected = { slot_melee = "official_melee", slot_ranged = "official_ranged" }
        local defaults = { { slot_melee = "default_melee", slot_ranged = "default_ranged" } }
        local mirror = {
            _career_loadouts = { bw_unchained = 2 },
            _career_data = { bw_unchained = { [2] = selected } },
        }
        function mirror:get_default_loadouts(career)
            H.equal(career, "bw_unchained")
            return defaults
        end
        local w = { live = {}, owned = {}, master = master, settings = settings,
            selected = selected, defaults = defaults, mirror = mirror, loadout_ids = {} }
        w.iface = { _backend_mirror = mirror }
        function w.iface:get_item_from_id(id) return w.live[id] end
        function w.iface:get_all_backend_items() return w.owned end
        w.deps = {
            items_interface = function() return w.iface end,
            loadout_item_id = function(career, slot, is_bot)
                w.loadout_ids[#w.loadout_ids + 1] = { career = career, slot = slot, is_bot = is_bot }
                return "saved_" .. slot
            end,
            master_list = function() return w.master end,
            career_settings = function() return w.settings end,
        }
        function w.recover(mode)
            return Recovery.new(Policy, SpawnPolicy, function(seen)
                H.equal(seen, w.iface)
                return mode or Policy.MODE_STORE
            end, Policy.MODE_STORE, w.deps)
        end
        return w
    end

    H.test("GUT #1637 adapter walks official, default, retry, owned, synthetic in order", function()
        local w = world()
        local recover, synthetic_keys, ledger = w.recover()
        local captured = with_printf(function()
            local item = recover("bw_unchained", "slot_melee", false, false, 0)
            H.equal(item.key, "bw_sword")
            H.equal(item.backend_id, nil)
            H.equal(item.data, w.master.bw_sword)
            H.equal(item.gut_synthetic_default, true)
        end)
        H.equal(synthetic_keys.bw_sword, true)
        H.equal(#captured, 2)
        H.truthy(captured[1]:find("^%[gut:1637%] miss career=bw_unchained slot=slot_melee is_bot=false resolved=false spawn_depth=0 mode=store loadout_id=saved_slot_melee id_resolves=false tried="))
        H.truthy(captured[1]:find("tried=official%-selected:official_melee=nil,career%-default:default_melee=nil,retry:saved_slot_melee=nil,default%-owned:bw_sword=none,default%-synthetic:bw_sword=ok source=career%-default%-synthetic key=bw_sword error=nil$"))
        H.equal(captured[2], "[gut:1637] recovered missing spawn weapon career=bw_unchained slot=slot_melee bot=false source=career-default-synthetic backend_id=nil key=bw_sword")
        H.equal(w.selected.slot_melee, "official_melee", "official data must not be mutated")
        H.equal(w.defaults[1].slot_melee, "default_melee")
        H.deep_equal(w.loadout_ids[1], { career = "bw_unchained", slot = "slot_melee", is_bot = false })

        -- The ledger mirrors the route: one successful miss, one successful
        -- recovery, and the fields behind the exact line above.
        H.equal(ledger.miss.count, 1)
        H.equal(ledger.miss.ok, 1)
        H.equal(ledger.miss.last.ok, true)
        H.equal(ledger.miss.last.error, nil)
        local f = ledger.miss.last.fields
        H.equal(f.career, "bw_unchained")
        H.equal(f.slot, "slot_melee")
        H.equal(f.is_bot, false)
        H.equal(f.resolved, false)
        H.equal(f.spawn_depth, 0)
        H.equal(f.mode, "store")
        H.equal(f.loadout_id, "saved_slot_melee")
        H.equal(f.id_resolves, "false")
        H.equal(f.source, "career-default-synthetic")
        H.equal(f.key, "bw_sword")
        H.equal(table.concat(f.trace, ","),
            "official-selected:official_melee=nil,career-default:default_melee=nil,retry:saved_slot_melee=nil,default-owned:bw_sword=none,default-synthetic:bw_sword=ok")
        H.equal(ledger.recovered.count, 1)
        H.equal(ledger.recovered.ok, 1)
        H.equal(ledger.recovered.last.fields, f)
        H.equal(ledger.sync_shadow.count, 0)
    end)

    H.test("GUT #1637 adapter stops at the first live candidate per stage", function()
        local w = world()
        w.live.official_melee = { backend_id = "official_melee" }
        w.live.default_melee = { backend_id = "default_melee" }
        w.live.saved_slot_melee = { backend_id = "saved_slot_melee" }
        w.owned.owned_sword = { ItemId = "bw_sword" }
        w.live.owned_sword = { backend_id = "owned_sword" }

        local function run()
            local out
            local captured = with_printf(function()
                out = w.recover()("bw_unchained", "slot_melee", true, nil, 1)
            end)
            return out, captured
        end

        local item, captured = run()
        H.equal(item.backend_id, "official_melee")
        H.truthy(captured[1]:find("is_bot=nil resolved=true spawn_depth=1", 1, true))
        H.truthy(captured[1]:find("id_resolves=true", 1, true))
        H.truthy(captured[1]:find("tried=official-selected:official_melee=ok source=official-selected", 1, true))
        H.truthy(captured[2]:find("source=official-selected backend_id=official_melee key=nil", 1, true))

        w.live.official_melee = nil
        item, captured = run()
        H.equal(item.backend_id, "default_melee")
        H.truthy(captured[1]:find("tried=official-selected:official_melee=nil,career-default:default_melee=ok source=career-default", 1, true))

        w.live.default_melee = nil
        item, captured = run()
        H.equal(item.backend_id, "saved_slot_melee")
        H.truthy(captured[1]:find(",retry:saved_slot_melee=ok source=retry", 1, true))

        w.live.saved_slot_melee = nil
        item, captured = run()
        H.equal(item.backend_id, "owned_sword")
        H.truthy(captured[1]:find(",retry:saved_slot_melee=nil,default-owned:owned_sword=ok source=career-default-owned key=bw_sword", 1, true))
        H.truthy(captured[2]:find("source=career-default-owned backend_id=owned_sword key=bw_sword", 1, true))

        w.live.owned_sword = nil
        item, captured = run()
        H.equal(item.key, "bw_sword")
        H.equal(item.backend_id, nil)
        H.truthy(captured[1]:find(",default-owned:owned_sword=nil,default-synthetic:bw_sword=ok source=career-default-synthetic", 1, true))
    end)

    H.test("GUT #1637 miss line is written once per career and slot", function()
        local w = world()
        local recover, _, ledger = w.recover()
        local captured = with_printf(function()
            recover("bw_unchained", "slot_melee", false, false, 0)
            recover("bw_unchained", "slot_melee", false, false, 0)
            recover("bw_unchained", "slot_ranged", false, false, 0)
            recover("bw_unchained", "slot_ranged", false, false, 0)
        end)
        local misses, hits = 0, 0
        for _, line in ipairs(captured) do
            if line:find("^%[gut:1637%] miss ") then misses = misses + 1 end
            if line:find("^%[gut:1637%] recovered ") then hits = hits + 1 end
        end
        H.equal(misses, 2)
        H.equal(hits, 2)
        H.truthy(captured[3]:find("slot=slot_ranged", 1, true))
        H.truthy(captured[3]:find("key=bw_skullstaff_fireball", 1, true))
        H.equal(ledger.miss.count, 2, "the ledger counts routes, not calls")
        H.equal(ledger.recovered.count, 2)
        H.equal(ledger.miss.last.fields.slot, "slot_ranged")
    end)

    H.test("GUT #1637 adapter still logs when inert, without an interface, or on errors", function()
        local w = world()
        local captured = with_printf(function()
            H.equal(w.recover(Policy.MODE_READONLY)("bw_unchained", "slot_melee", false, false, 0), nil)
        end)
        H.equal(#captured, 1)
        H.truthy(captured[1]:find("mode=readonly loadout_id=saved_slot_melee id_resolves=false tried=none source=inert-mode key=nil error=nil", 1, true))

        w.deps.items_interface = function() return nil end
        captured = with_printf(function()
            H.equal(w.recover()("bw_unchained", "slot_melee", false, false, 0), nil)
        end)
        H.truthy(captured[1]:find("mode=no-iface loadout_id=saved_slot_melee id_resolves=n/a tried=none source=no-iface", 1, true))

        w.deps.items_interface = function() return w.iface end
        w.deps.loadout_item_id = function() error("backend down") end
        w.iface.get_item_from_id = function() error("items down") end
        captured = with_printf(function()
            local item = w.recover()("bw_unchained", "slot_melee", false, false, 0)
            H.equal(item.key, "bw_sword", "a throwing resolver still reaches the synthetic default")
        end)
        H.truthy(captured[1]:find("loadout_id=error:", 1, true))
        H.truthy(captured[1]:find("backend down", 1, true))
        H.truthy(captured[1]:find("official-selected:official_melee=error,career-default:default_melee=error,default-owned:bw_sword=none,default-synthetic:bw_sword=ok", 1, true))

        w.deps.master_list = function() error("master gone") end
        captured = with_printf(function()
            H.equal(w.recover()("bw_unchained", "slot_melee", false, false, 0), nil)
        end)
        H.truthy(captured[1]:find("source=error", 1, true))
        H.truthy(captured[1]:find("error=", 1, true))
        H.truthy(captured[1]:find("master gone", 1, true))
    end)

    H.test("GUT #1637 adapter is silent for non-weapon slots and unresolved defaults", function()
        local w = world()
        local captured = with_printf(function()
            H.equal(w.recover()("bw_unchained", "slot_hat", false, false, 0), nil)
            H.equal(w.recover()("bw_unchained", "slot_pose", false, false, 0), nil)
        end)
        H.equal(#captured, 0)
        H.equal(#w.loadout_ids, 0, "non-weapon slots must not touch the backend")

        w.master = {}
        captured = with_printf(function()
            H.equal(w.recover()("bw_unchained", "slot_melee", false, false, 0), nil)
        end)
        H.equal(#captured, 1)
        H.truthy(captured[1]:find(",career-default:nil=no-candidate source=unresolved key=nil", 1, true))
    end)

    H.test("GUT #1637 printf route is the literal global, never a cached function", function()
        local w = world()
        local recover, _, ledger = w.recover()
        local first = with_printf(function()
            recover("bw_unchained", "slot_melee", false, false, 0)
        end)
        H.equal(#first, 2)
        local old = rawget(_G, "printf")
        rawset(_G, "printf", nil)
        local ok = pcall(recover, "bw_unchained", "slot_ranged", false, false, 0)
        rawset(_G, "printf", old)
        H.equal(ok, true, "a missing printf global must not escape the recovery")
        -- The ledger records the failed pcall instead of hiding it.
        H.equal(ledger.miss.count, 2)
        H.equal(ledger.miss.ok, 1)
        H.equal(ledger.miss.last.ok, false)
        H.truthy(tostring(ledger.miss.last.error):find("nil", 1, true), tostring(ledger.miss.last.error))
        H.equal(ledger.miss.last.fields.slot, "slot_ranged")
        H.equal(ledger.recovered.count, 2)
        H.equal(ledger.recovered.ok, 1)
        H.equal(ledger.recovered.last.ok, false)
    end)

    H.test("GUT #1637 sync guard shadows only synthetic defaults on the loadout RPC", function()
        local keys = { bw_sword = true }
        local ledger = Recovery.new_ledger()
        local guard = Recovery.sync_guard(SpawnPolicy, keys, ledger)
        local forwarded = {}
        local function func(player, slot, item, peer)
            forwarded[#forwarded + 1] = { player = player, slot = slot, item = item, peer = peer }
            return "sent"
        end
        local raw = { key = "bw_sword", rarity = "plentiful" }
        local captured = with_printf(function()
            H.equal(guard(func, "player", "slot_melee", raw, "peer"), "sent")
            guard(func, "player", "slot_melee", raw, nil)
        end)
        H.equal(forwarded[1].player, "player")
        H.equal(forwarded[1].slot, "slot_melee")
        H.equal(forwarded[1].peer, "peer")
        H.equal(forwarded[1].item.key, "bw_sword")
        H.equal(forwarded[1].item.power_level, SpawnPolicy.SYNTHETIC_POWER_LEVEL)
        H.equal(forwarded[1].item ~= raw, true)
        H.equal(forwarded[2].item.power_level, SpawnPolicy.SYNTHETIC_POWER_LEVEL)
        H.equal(#captured, 1)
        H.equal(captured[1], "[gut:1637] sync shadow slot=slot_melee key=bw_sword power_level=300")
        H.equal(raw.power_level, nil)
        H.equal(ledger.sync_shadow.count, 1)
        H.equal(ledger.sync_shadow.ok, 1)
        H.equal(ledger.sync_shadow.last.ok, true)
        H.deep_equal(ledger.sync_shadow.last.fields, { slot = "slot_melee", key = "bw_sword", power_level = 300 })

        local real = { key = "bw_sword", rarity = "plentiful", power_level = 250 }
        guard(func, "player", "slot_melee", real, nil)
        H.equal(forwarded[3].item, real, "a real instance passes through untouched")
        local other = { key = "bw_dagger" }
        guard(func, "player", "slot_melee", other, nil)
        H.equal(forwarded[4].item, other, "non-synthetic keys pass through untouched")
        guard(func, "player", "slot_hat", raw, nil)
        H.equal(forwarded[5].item, raw, "non-weapon slots pass through untouched")
        H.equal(ledger.sync_shadow.count, 1, "pass-through items never log")

        -- A guard built without a ledger owns a private one and still works.
        local bare = Recovery.sync_guard(SpawnPolicy, keys)
        captured = with_printf(function()
            H.equal(bare(func, "player", "slot_melee", { key = "bw_sword", rarity = "plentiful" }, nil), "sent")
        end)
        H.equal(#captured, 1)
    end)

    H.test("GUT #1637 install wires the recovery, the sync hook, the ledger and the selftest surface", function()
        local hooks = {}
        local mod = {}
        function mod:dofile(path)
            H.equal(path, "scripts/mods/gui_tweaker_dev/_gut_spawn_weapon_policy")
            return SpawnPolicy
        end
        function mod:hook(obj, method, fn)
            hooks[#hooks + 1] = { obj = obj, method = method, fn = fn }
        end
        local loadout_utils = { sync_loadout_slot = function() end }
        local old = rawget(_G, "LoadoutUtils")
        rawset(_G, "LoadoutUtils", loadout_utils)
        local ok, recover = pcall(Recovery.install, mod, Policy, function() return Policy.MODE_STORE end, Policy.MODE_STORE)
        rawset(_G, "LoadoutUtils", old)
        H.truthy(ok, tostring(recover))
        H.equal(type(recover), "function")
        H.equal(#hooks, 1)
        H.equal(hooks[1].obj, loadout_utils)
        H.equal(hooks[1].method, "sync_loadout_slot")
        local surface = mod._gut_spawn_weapon_selftest
        H.equal(type(surface), "table")
        H.equal(surface.policy, SpawnPolicy)
        H.equal(type(surface.synthetic_keys), "table")
        H.equal(type(surface.ledger), "table")
        H.equal(surface.ledger.miss.count, 0)
        H.equal(surface.ledger.sync_shadow.count, 0)

        -- The exposed ledger is the one the installed sync hook writes.
        surface.synthetic_keys.bw_sword = true
        local captured = with_printf(function()
            hooks[1].fn(function() return "sent" end, "player", "slot_melee",
                { key = "bw_sword", rarity = "plentiful" }, nil)
        end)
        H.equal(#captured, 1)
        H.equal(surface.ledger.sync_shadow.count, 1)
        H.equal(surface.ledger.sync_shadow.last.ok, true)

        -- The ordering proof runs through the ambient printf, never a swap.
        captured = with_printf(function()
            H.equal(surface.ordering(), nil)
        end)
        H.equal(#captured, 12, "every proof stage logs through the ambient global")
        local err, results = surface.census(
            { bw_sword = { slot_type = "melee", rarity = "plentiful", template = "t", right_hand_unit = "u", can_wield = { "bw_unchained" } },
              bw_staff = { slot_type = "ranged", rarity = "plentiful", template = "t", right_hand_unit = "u", can_wield = { "bw_unchained" } } },
            nil, { "bw_unchained" })
        H.equal(err, nil)
        H.equal(#results, 2)
    end)

    H.test("GUT #1637 selftest ordering proof passes and reports a broken order", function()
        local before = rawget(_G, "printf")
        local captured = with_printf(function()
            H.equal(Recovery.selftest_ordering(Policy, SpawnPolicy, Policy.MODE_STORE), nil)
        end)
        H.equal(#captured, 12)
        H.truthy(captured[1]:find("^%[gut:1637%] miss career=gut_rt1637_probe slot=slot_melee "), captured[1])
        local broken = {}
        for k, v in pairs(Policy) do broken[k] = v end
        broken.official_weapon_candidates = function() return {}, {} end
        local err
        with_printf(function()
            err = Recovery.selftest_ordering(broken, SpawnPolicy, Policy.MODE_STORE)
        end)
        H.equal(type(err), "string")
        H.truthy(err:find("candidate order mismatch", 1, true), err)
        H.equal(rawget(_G, "printf"), before, "selftest must leave the printf global alone")
    end)

    H.test("GUT #1637 selftest never replaces the global printf and fails when the route cannot run", function()
        -- A sentinel global asserts its own identity on every call: had the
        -- selftest swapped printf, the sentinel would not be the callee.
        local old = rawget(_G, "printf")
        local calls, displaced = 0, 0
        local function sentinel(fmt, ...)
            calls = calls + 1
            if rawget(_G, "printf") ~= sentinel then displaced = displaced + 1 end
            return string.format(fmt, ...)
        end
        rawset(_G, "printf", sentinel)
        local err = Recovery.selftest_ordering(Policy, SpawnPolicy, Policy.MODE_STORE)
        local after = rawget(_G, "printf")
        rawset(_G, "printf", old)
        H.equal(err, nil)
        H.equal(after, sentinel)
        H.equal(calls, 12)
        H.equal(displaced, 0)

        -- No printf at all: the route's pcall fails and the proof says so.
        rawset(_G, "printf", nil)
        err = Recovery.selftest_ordering(Policy, SpawnPolicy, Policy.MODE_STORE)
        rawset(_G, "printf", old)
        H.equal(type(err), "string")
        H.truthy(err:find("miss route pcall failed", 1, true), err)

        -- A printf that throws is reported the same way, with its error.
        rawset(_G, "printf", function() error("printf exploded") end)
        err = Recovery.selftest_ordering(Policy, SpawnPolicy, Policy.MODE_STORE)
        rawset(_G, "printf", old)
        H.equal(type(err), "string")
        H.truthy(err:find("miss route pcall failed", 1, true), err)
        H.truthy(err:find("printf exploded", 1, true), err)
    end)

    H.test("GUT #1637 deployed recovery source never writes the global printf", function()
        local file = assert(io.open(root .. "_gut_spawn_weapon_recovery.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.equal(source:find('rawset(_G, "printf"', 1, true), nil, "deployed source swaps the global printf")
        H.equal(source:find("_G.printf =", 1, true), nil, "deployed source assigns the global printf")
        H.equal(source:find("setfenv", 1, true), nil)
        H.equal(source:find("getfenv", 1, true), nil)
        H.truthy(source:find('pcall(printf, "[gut:1637] miss career=%s slot=%s', 1, true),
            "the literal miss route must stay")
    end)
end
