-- _gut_spawn_weapon_recovery.lua -- consumer-boundary loadout recovery (#1637).
--
-- A mirror read can observe a backend id that disappears during the following
-- item-interface refresh. SimpleInventoryExtension then consumes nil and aborts
-- while wielding the default melee slot. This adapter is deliberately separate
-- from the already-frozen native-loadouts owner: it runs only after vanilla's
-- BackendUtils.get_loadout_item returned nil, delegates candidate selection to
-- the pure policies, and never writes the modded loadout store.
--
-- Candidate order (0.2.353-dev): native result, official selected row, mirror
-- default row, one immediate retry of the loadout id vanilla just failed on,
-- then the vanilla career default (an owned backend instance of that key when
-- the player has one, else a master-list synthetic without a backend id, see
-- _gut_spawn_weapon_policy.lua). Every weapon-slot miss writes exactly one
-- bounded `[gut:1637] miss` line per career/slot/session, whatever the mode
-- or outcome, so a silent recovery can never happen again.
--
-- Route ledger (0.2.354-dev): every receipt below is a literal
-- `pcall(printf, ...)` so the deployed-source authority can prove the route
-- from source, and each site records its pcall result in a module-local
-- ledger so the in-game regression check can prove the route RAN. The proof
-- never replaces the global printf: the authority rejects any deployed mod
-- that mutates it, record-wide and fail-closed, because raw printf evidence
-- for every mod becomes untrustworthy. Only the offline harness may swap it.
local M = {}

local function trace_entry(label, id, state)
    return tostring(label) .. ":" .. tostring(id) .. "=" .. state
end

local function new_ledger()
    return {
        miss = { count = 0, ok = 0 },
        recovered = { count = 0, ok = 0 },
        sync_shadow = { count = 0, ok = 0 },
    }
end

-- Records one pcall(printf, ...) outcome: how often the route ran, how often
-- the pcall succeeded, and the fields behind the last line.
local function record(ledger, kind, ok, err, fields)
    local entry = ledger[kind]
    entry.count = entry.count + 1
    if ok then entry.ok = entry.ok + 1 end
    entry.last = { ok = ok == true, error = (not ok) and tostring(err) or nil, fields = fields }
end

M.new_ledger = new_ledger

local function default_items_interface()
    local managers = rawget(_G, "Managers")
    local backend = managers and managers.backend
    return backend and backend._interfaces and backend._interfaces.items or nil
end

local function default_loadout_item_id(career_name, slot_name, is_bot)
    local backend_utils = rawget(_G, "BackendUtils")
    if type(backend_utils) ~= "table" or type(backend_utils.get_loadout_item_id) ~= "function" then
        error("BackendUtils.get_loadout_item_id unavailable")
    end
    return backend_utils.get_loadout_item_id(career_name, slot_name, is_bot)
end

-- deps (all optional, defaults read the live globals):
--   items_interface()            -> BackendInterfaceItemPlayfab instance
--   loadout_item_id(c, s, bot)   -> BackendUtils.get_loadout_item_id
--   master_list()                -> ItemMasterList
--   career_settings()            -> CareerSettings
-- Returns recover, synthetic_keys, ledger.
function M.new(Policy, SpawnPolicy, adventure_mode, mode_store, deps)
    deps = deps or {}
    local items_interface = deps.items_interface or default_items_interface
    local loadout_item_id = deps.loadout_item_id or default_loadout_item_id
    local master_list = deps.master_list or function() return rawget(_G, "ItemMasterList") end
    local career_settings = deps.career_settings or function() return rawget(_G, "CareerSettings") end

    local logged_miss, logged_hit = {}, {}
    local synthetic_keys = {}
    local ledger = new_ledger()

    local function get_defaults(owner, career)
        return owner:get_default_loadouts(career)
    end

    local function attempt(career_name, slot_name, is_bot, d)
        local iface = items_interface()
        d.mode = iface ~= nil and tostring(adventure_mode(iface)) or "no-iface"

        local ok_id, id = pcall(loadout_item_id, career_name, slot_name, is_bot)
        d.loadout_id = ok_id and id or ("error:" .. tostring(id))
        local function resolve(backend_id)
            return iface:get_item_from_id(backend_id)
        end
        if ok_id and id ~= nil and iface ~= nil then
            local ok_r, item = pcall(resolve, id)
            d.id_resolves = ok_r and tostring(item ~= nil) or "error"
        else
            d.id_resolves = "n/a"
        end

        if iface == nil then d.source = "no-iface" return nil end
        if d.mode ~= mode_store then d.source = "inert-mode" return nil end

        local function try(label, backend_id)
            local ok, item = pcall(resolve, backend_id)
            local hit = ok and type(item) == "table"
            d.trace[#d.trace + 1] = trace_entry(label, backend_id,
                hit and "ok" or (ok and "nil" or "error"))
            return hit and item or nil
        end

        local ids, labels = Policy.official_weapon_candidates(
            iface._backend_mirror, career_name, slot_name, get_defaults)
        for i = 1, #ids do
            local item = try(labels[i], ids[i])
            if item then d.source, d.backend_id = labels[i], ids[i] return item end
        end

        if ok_id and id ~= nil then
            local item = try("retry", id)
            if item then d.source, d.backend_id = "retry", id return item end
        end

        local key, how, entry = SpawnPolicy.select_default_weapon_key(
            master_list(), career_settings(), career_name, slot_name)
        if key == nil then
            d.trace[#d.trace + 1] = trace_entry("career-default", "nil", tostring(how))
            d.source = "unresolved"
            return nil
        end
        d.key = key

        local ok_all, all_items = pcall(function() return iface:get_all_backend_items() end)
        local owned = ok_all and SpawnPolicy.find_owned_instance(all_items, key) or nil
        if owned ~= nil then
            local item = try("default-owned", owned)
            if item then d.source, d.backend_id = "career-default-owned", owned return item end
        else
            d.trace[#d.trace + 1] = trace_entry("default-owned", key, ok_all and "none" or "error")
        end

        local item = SpawnPolicy.build_synthetic_item(key, entry)
        if item == nil then
            d.trace[#d.trace + 1] = trace_entry("default-synthetic", key, "invalid")
            d.source = "unresolved"
            return nil
        end
        synthetic_keys[key] = true
        d.trace[#d.trace + 1] = trace_entry("default-synthetic", key, "ok")
        d.source = "career-default-synthetic"
        return item
    end

    local function recover(career_name, slot_name, is_bot, received_is_bot, spawn_depth)
        if not SpawnPolicy.WEAPON_SLOTS[slot_name] then return nil end
        local d = { trace = {}, source = "unresolved" }
        local ok, item = pcall(attempt, career_name, slot_name, is_bot, d)
        if not ok then
            d.error = tostring(item)
            d.source = "error"
            item = nil
        end

        local miss_token = tostring(career_name) .. "\0" .. tostring(slot_name)
        if not logged_miss[miss_token] then
            logged_miss[miss_token] = true
            d.career, d.slot, d.is_bot, d.resolved, d.spawn_depth =
                career_name, slot_name, received_is_bot, is_bot, spawn_depth
            local ok_miss, err_miss = pcall(printf, "[gut:1637] miss career=%s slot=%s is_bot=%s resolved=%s spawn_depth=%s mode=%s loadout_id=%s id_resolves=%s tried=%s source=%s key=%s error=%s",
                tostring(career_name), tostring(slot_name), tostring(received_is_bot),
                tostring(is_bot), tostring(spawn_depth), tostring(d.mode),
                tostring(d.loadout_id), tostring(d.id_resolves),
                #d.trace > 0 and table.concat(d.trace, ",") or "none",
                tostring(d.source), tostring(d.key), tostring(d.error))
            record(ledger, "miss", ok_miss, err_miss, d)
        end

        if item ~= nil then
            local hit_token = miss_token .. "\0" .. tostring(d.backend_id or d.key)
            if not logged_hit[hit_token] then
                logged_hit[hit_token] = true
                local ok_hit, err_hit = pcall(printf, "[gut:1637] recovered missing spawn weapon career=%s slot=%s bot=%s source=%s backend_id=%s key=%s",
                    tostring(career_name), tostring(slot_name), tostring(is_bot),
                    tostring(d.source), tostring(d.backend_id), tostring(d.key))
                record(ledger, "recovered", ok_hit, err_hit, d)
            end
        end
        return item
    end

    return recover, synthetic_keys, ledger
end

-- LoadoutUtils.sync_loadout_slot hook body: only a GUT synthetic default (a raw
-- master-list row with no power_level) is swapped for the RPC-safe shadow.
function M.sync_guard(SpawnPolicy, synthetic_keys, ledger)
    local logged = {}
    ledger = ledger or new_ledger()
    return function(func, player, slot_name, item, ...)
        if SpawnPolicy.needs_sync_shadow(slot_name, item, synthetic_keys) then
            item = SpawnPolicy.shadow_sync_item(item)
            if not logged[item.key] then
                logged[item.key] = true
                local ok_sync, err_sync = pcall(printf, "[gut:1637] sync shadow slot=%s key=%s power_level=%s",
                    tostring(slot_name), tostring(item.key), tostring(item.power_level))
                record(ledger, "sync_shadow", ok_sync, err_sync,
                    { slot = slot_name, key = item.key, power_level = item.power_level })
            end
        end
        return func(player, slot_name, item, ...)
    end
end

-- Offline proof of the candidate order and of the literal printf miss route.
-- Runs against fake deps only (no engine, no live state) so both the offline
-- harness and /gut_regression_test can execute it. Every line goes through
-- the ambient global printf; the proof reads each instance's ledger and fails
-- when a route did not run or its pcall failed. Returns nil or an error.
function M.selftest_ordering(Policy, SpawnPolicy, mode_store)
    local master = {
        gut_rt1637_sword = {
            slot_type = "melee", rarity = "plentiful", template = "t",
            right_hand_unit = "u", can_wield = { "gut_rt1637_probe" },
        },
    }
    local settings = { gut_rt1637_probe = { item_slot_types_by_slot_name = { slot_melee = { "melee" } } } }
    local live = {}
    local owned_items = {}
    local mirror = {
        _career_loadouts = { gut_rt1637_probe = 1 },
        _career_data = { gut_rt1637_probe = { { slot_melee = "official_id" } } },
    }
    function mirror:get_default_loadouts() return { { slot_melee = "default_id" } } end
    local iface = { _backend_mirror = mirror }
    function iface:get_item_from_id(id) return live[id] end
    function iface:get_all_backend_items() return owned_items end
    local loadout_id = "original_id"
    local function fresh(adventure_mode)
        return M.new(Policy, SpawnPolicy, adventure_mode or function() return mode_store end, mode_store, {
            items_interface = function() return iface end,
            loadout_item_id = function() return loadout_id end,
            master_list = function() return master end,
            career_settings = function() return settings end,
        })
    end
    -- The route must have run exactly `expected` times and its last pcall
    -- must have succeeded; returns the fields behind the last line.
    local function route(ledger, kind, expected)
        local entry = ledger[kind]
        if entry.count ~= expected then
            return nil, kind .. " route ran " .. entry.count .. " time(s), expected " .. expected
        end
        if expected == 0 then return true end
        if not entry.last or not entry.last.ok then
            return nil, kind .. " route pcall failed: " .. tostring(entry.last and entry.last.error)
        end
        return entry.last.fields
    end

    local ok, err = pcall(function()
        -- 1. Everything nil: the whole chain runs and ends on the synthetic default.
        local recover, _, ledger = fresh()
        local item = recover("gut_rt1637_probe", "slot_melee", false, nil, 0)
        if type(item) ~= "table" or item.key ~= "gut_rt1637_sword" or item.backend_id ~= nil then
            return "all-nil run did not end on the synthetic career default"
        end
        local miss, why = route(ledger, "miss", 1)
        if not miss then return why end
        local expected = "official-selected:official_id=nil,career-default:default_id=nil,retry:original_id=nil,default-owned:gut_rt1637_sword=none,default-synthetic:gut_rt1637_sword=ok"
        local tried = table.concat(miss.trace, ",")
        if tried ~= expected then return "candidate order mismatch: " .. tried end
        if miss.source ~= "career-default-synthetic" or miss.loadout_id ~= "original_id"
            or miss.id_resolves ~= "false" or miss.mode ~= tostring(mode_store)
            or miss.career ~= "gut_rt1637_probe" or miss.slot ~= "slot_melee"
            or miss.is_bot ~= nil or miss.resolved ~= false or miss.spawn_depth ~= 0 then
            return "miss ledger lacks a required field"
        end
        local hit
        hit, why = route(ledger, "recovered", 1)
        if not hit then return why end
        if hit ~= miss or hit.key ~= "gut_rt1637_sword" then
            return "recovered line missing after synthetic fallback"
        end
        -- 2. Dedupe: a second miss for the same career/slot is silent.
        recover("gut_rt1637_probe", "slot_melee", false, nil, 0)
        if ledger.miss.count ~= 1 or ledger.recovered.count ~= 1 then
            return "miss line was not deduplicated"
        end
        -- 3. Native-first ordering with fresh recover instances per stage; each
        --    stage must log its miss and its recovery through the route.
        local function first_hit()
            local r, _, l = fresh()
            local got = r("gut_rt1637_probe", "slot_melee", false, nil, 0)
            local fields, e = route(l, "miss", 1)
            if not fields then return nil, e end
            fields, e = route(l, "recovered", 1)
            if not fields then return nil, e end
            return got and got.backend_id, fields.source
        end
        live.official_id = { backend_id = "official_id" }
        live.default_id = { backend_id = "default_id" }
        live.original_id = { backend_id = "original_id" }
        owned_items.owned_id = { ItemId = "gut_rt1637_sword" }
        live.owned_id = { backend_id = "owned_id" }
        local id, source = first_hit()
        if id ~= "official_id" then
            return "official selected row must win before the default row (" .. tostring(source) .. ")"
        end
        live.official_id = nil
        id, source = first_hit()
        if id ~= "default_id" then
            return "mirror default row must win before the retry (" .. tostring(source) .. ")"
        end
        live.default_id = nil
        id, source = first_hit()
        if id ~= "original_id" then
            return "retry of the original loadout id must win before the career default (" .. tostring(source) .. ")"
        end
        live.original_id = nil
        id, source = first_hit()
        if id ~= "owned_id" then
            return "owned instance of the career default must win before the synthetic (" .. tostring(source) .. ")"
        end
        -- 4. A non-weapon slot never runs or logs.
        local r, _, l = fresh()
        if r("gut_rt1637_probe", "slot_hat", false, nil, 0) ~= nil
            or l.miss.count ~= 0 or l.recovered.count ~= 0 then
            return "non-weapon slot must stay silent"
        end
        -- 5. Inert mode still logs the miss and returns nil.
        local inert, _, inert_ledger = fresh(function() return "readonly" end)
        if inert("gut_rt1637_probe", "slot_ranged", false, nil, 0) ~= nil then
            return "inert mode must return nil"
        end
        local fields, e = route(inert_ledger, "miss", 1)
        if not fields then return e end
        if fields.source ~= "inert-mode" or inert_ledger.recovered.count ~= 0 then
            return "inert mode must still log the miss"
        end
        -- 6. A throwing dependency is contained and logged as an error.
        local broken, _, broken_ledger = fresh(function() error("mode boom") end)
        if broken("gut_rt1637_probe", "slot_melee", false, nil, 0) ~= nil then
            return "a throwing dependency must return nil"
        end
        fields, e = route(broken_ledger, "miss", 1)
        if not fields then return e end
        if fields.source ~= "error" or not tostring(fields.error):find("mode boom", 1, true) then
            return "a throwing dependency must log the miss with its error"
        end
        return nil
    end)
    if not ok then return "selftest raised: " .. tostring(err) end
    return err
end

-- Wires the adapter into the mod: recovery function, sync-RPC shadow hook and
-- the selftest surface used by _gut_bot_pose.lua's regression checks (the
-- installed instance's ledger included, so the live route can be proven).
function M.install(mod, Policy, adventure_mode, mode_store)
    local SpawnPolicy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_spawn_weapon_policy")
    local recover, synthetic_keys, ledger = M.new(Policy, SpawnPolicy, adventure_mode, mode_store)
    local loadout_utils = rawget(_G, "LoadoutUtils")
    if type(loadout_utils) == "table" and type(loadout_utils.sync_loadout_slot) == "function" then
        -- hook-test: issue1637_spawn_weapon_default_fallback
        mod:hook(loadout_utils, "sync_loadout_slot", M.sync_guard(SpawnPolicy, synthetic_keys, ledger))
    end
    mod._gut_spawn_weapon_selftest = {
        policy = SpawnPolicy,
        synthetic_keys = synthetic_keys,
        ledger = ledger,
        ordering = function() return M.selftest_ordering(Policy, SpawnPolicy, mode_store) end,
        census = function(master_list, career_settings, careers)
            return SpawnPolicy.census(master_list, career_settings, careers)
        end,
    }
    return recover
end

return M
