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
local M = {}

local function trace_entry(label, id, state)
    return tostring(label) .. ":" .. tostring(id) .. "=" .. state
end

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
function M.new(Policy, SpawnPolicy, adventure_mode, mode_store, deps)
    deps = deps or {}
    local items_interface = deps.items_interface or default_items_interface
    local loadout_item_id = deps.loadout_item_id or default_loadout_item_id
    local master_list = deps.master_list or function() return rawget(_G, "ItemMasterList") end
    local career_settings = deps.career_settings or function() return rawget(_G, "CareerSettings") end

    local logged_miss, logged_hit = {}, {}
    local synthetic_keys = {}

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
            pcall(printf, "[gut:1637] miss career=%s slot=%s is_bot=%s resolved=%s spawn_depth=%s mode=%s loadout_id=%s id_resolves=%s tried=%s source=%s key=%s error=%s",
                tostring(career_name), tostring(slot_name), tostring(received_is_bot),
                tostring(is_bot), tostring(spawn_depth), tostring(d.mode),
                tostring(d.loadout_id), tostring(d.id_resolves),
                #d.trace > 0 and table.concat(d.trace, ",") or "none",
                tostring(d.source), tostring(d.key), tostring(d.error))
        end

        if item ~= nil then
            local hit_token = miss_token .. "\0" .. tostring(d.backend_id or d.key)
            if not logged_hit[hit_token] then
                logged_hit[hit_token] = true
                pcall(printf, "[gut:1637] recovered missing spawn weapon career=%s slot=%s bot=%s source=%s backend_id=%s key=%s",
                    tostring(career_name), tostring(slot_name), tostring(is_bot),
                    tostring(d.source), tostring(d.backend_id), tostring(d.key))
            end
        end
        return item
    end

    return recover, synthetic_keys
end

-- LoadoutUtils.sync_loadout_slot hook body: only a GUT synthetic default (a raw
-- master-list row with no power_level) is swapped for the RPC-safe shadow.
function M.sync_guard(SpawnPolicy, synthetic_keys)
    local logged = {}
    return function(func, player, slot_name, item, ...)
        if SpawnPolicy.needs_sync_shadow(slot_name, item, synthetic_keys) then
            item = SpawnPolicy.shadow_sync_item(item)
            if not logged[item.key] then
                logged[item.key] = true
                pcall(printf, "[gut:1637] sync shadow slot=%s key=%s power_level=%s",
                    tostring(slot_name), tostring(item.key), tostring(item.power_level))
            end
        end
        return func(player, slot_name, item, ...)
    end
end

-- Offline proof of the candidate order and of the literal printf miss route.
-- Runs against fake deps only (no engine, no live state) so both the offline
-- harness and /gut_regression_test can execute it. Returns nil or an error.
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
    local recover = M.new(Policy, SpawnPolicy, function() return mode_store end, mode_store, {
        items_interface = function() return iface end,
        loadout_item_id = function() return loadout_id end,
        master_list = function() return master end,
        career_settings = function() return settings end,
    })

    local captured = {}
    local real_printf = rawget(_G, "printf")
    rawset(_G, "printf", function(fmt, ...)
        captured[#captured + 1] = string.format(fmt, ...)
    end)
    local ok, err = pcall(function()
        -- 1. Everything nil: the whole chain runs and ends on the synthetic default.
        local item = recover("gut_rt1637_probe", "slot_melee", false, nil, 0)
        if type(item) ~= "table" or item.key ~= "gut_rt1637_sword" or item.backend_id ~= nil then
            return "all-nil run did not end on the synthetic career default"
        end
        local miss = captured[1]
        if type(miss) ~= "string" or miss:sub(1, 15) ~= "[gut:1637] miss" then
            return "miss line was not the first line through printf"
        end
        local expected = "official-selected:official_id=nil,career-default:default_id=nil,retry:original_id=nil,default-owned:gut_rt1637_sword=none,default-synthetic:gut_rt1637_sword=ok"
        if not miss:find("tried=" .. expected, 1, true) then
            return "candidate order mismatch: " .. miss
        end
        if not miss:find("source=career-default-synthetic", 1, true)
            or not miss:find("loadout_id=original_id", 1, true)
            or not miss:find("id_resolves=false", 1, true)
            or not miss:find("mode=" .. tostring(mode_store), 1, true) then
            return "miss line lacks a required field: " .. miss
        end
        if type(captured[2]) ~= "string" or captured[2]:sub(1, 20) ~= "[gut:1637] recovered" then
            return "recovered line missing after synthetic fallback"
        end
        -- 2. Dedupe: a second miss for the same career/slot is silent.
        local before = #captured
        recover("gut_rt1637_probe", "slot_melee", false, nil, 0)
        if #captured ~= before then return "miss line was not deduplicated" end
        -- 3. Native-first ordering with fresh recover instances per stage.
        local function fresh()
            return M.new(Policy, SpawnPolicy, function() return mode_store end, mode_store, {
                items_interface = function() return iface end,
                loadout_item_id = function() return loadout_id end,
                master_list = function() return master end,
                career_settings = function() return settings end,
            })
        end
        live.official_id = { backend_id = "official_id" }
        live.default_id = { backend_id = "default_id" }
        live.original_id = { backend_id = "original_id" }
        owned_items.owned_id = { ItemId = "gut_rt1637_sword" }
        live.owned_id = { backend_id = "owned_id" }
        local r = fresh()
        if r("gut_rt1637_probe", "slot_melee", false, nil, 0).backend_id ~= "official_id" then
            return "official selected row must win before the default row"
        end
        live.official_id = nil
        r = fresh()
        if r("gut_rt1637_probe", "slot_melee", false, nil, 0).backend_id ~= "default_id" then
            return "mirror default row must win before the retry"
        end
        live.default_id = nil
        r = fresh()
        if r("gut_rt1637_probe", "slot_melee", false, nil, 0).backend_id ~= "original_id" then
            return "retry of the original loadout id must win before the career default"
        end
        live.original_id = nil
        r = fresh()
        if r("gut_rt1637_probe", "slot_melee", false, nil, 0).backend_id ~= "owned_id" then
            return "owned instance of the career default must win before the synthetic"
        end
        -- 4. A non-weapon slot never runs or logs.
        before = #captured
        if r("gut_rt1637_probe", "slot_hat", false, nil, 0) ~= nil or #captured ~= before then
            return "non-weapon slot must stay silent"
        end
        -- 5. Inert mode still logs the miss and returns nil.
        local inert = M.new(Policy, SpawnPolicy, function() return "readonly" end, mode_store, {
            items_interface = function() return iface end,
            loadout_item_id = function() return loadout_id end,
            master_list = function() return master end,
            career_settings = function() return settings end,
        })
        before = #captured
        if inert("gut_rt1637_probe", "slot_ranged", false, nil, 0) ~= nil then
            return "inert mode must return nil"
        end
        if #captured ~= before + 1 or not captured[#captured]:find("source=inert-mode", 1, true) then
            return "inert mode must still log the miss"
        end
        -- 6. A throwing dependency is contained and logged as an error.
        local broken = M.new(Policy, SpawnPolicy, function() error("mode boom") end, mode_store, {
            items_interface = function() return iface end,
            loadout_item_id = function() return loadout_id end,
            master_list = function() return master end,
            career_settings = function() return settings end,
        })
        before = #captured
        if broken("gut_rt1637_probe", "slot_melee", false, nil, 0) ~= nil then
            return "a throwing dependency must return nil"
        end
        if #captured ~= before + 1 or not captured[#captured]:find("source=error", 1, true)
            or not captured[#captured]:find("mode boom", 1, true) then
            return "a throwing dependency must log the miss with its error"
        end
        return nil
    end)
    rawset(_G, "printf", real_printf)
    if not ok then return "selftest raised: " .. tostring(err) end
    return err
end

-- Wires the adapter into the mod: recovery function, sync-RPC shadow hook and
-- the selftest surface used by _gut_bot_pose.lua's regression checks.
function M.install(mod, Policy, adventure_mode, mode_store)
    local SpawnPolicy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_spawn_weapon_policy")
    local recover, synthetic_keys = M.new(Policy, SpawnPolicy, adventure_mode, mode_store)
    local loadout_utils = rawget(_G, "LoadoutUtils")
    if type(loadout_utils) == "table" and type(loadout_utils.sync_loadout_slot) == "function" then
        -- hook-test: issue1637_spawn_weapon_default_fallback
        mod:hook(loadout_utils, "sync_loadout_slot", M.sync_guard(SpawnPolicy, synthetic_keys))
    end
    mod._gut_spawn_weapon_selftest = {
        policy = SpawnPolicy,
        synthetic_keys = synthetic_keys,
        ordering = function() return M.selftest_ordering(Policy, SpawnPolicy, mode_store) end,
        census = function(master_list, career_settings, careers)
            return SpawnPolicy.census(master_list, career_settings, careers)
        end,
    }
    return recover
end

return M
