-- _mp_fresh_profile_runtime.lua - routes the native items/loadouts interface
-- to the MP-owned Fresh profile (issue #840, items/loadouts slice).
--
-- Every consumer of the items interface reaches the same object whether it
-- calls Managers.backend:get_interface("items") or the loadout override
-- registry [src: backend_manager_playfab.lua:201-209,329-341], so routing
-- the class methods covers both. The root reads that touch the native
-- mirror are routed; derived methods (get_filtered_items, has_item,
-- equipped_by, get_cosmetic_loadout, get_item_rarity, ...) call those roots
-- through `self:` and therefore follow the route without their own hook.
--
-- get_item_from_id is routed as well (issue #1637): it is the reader every
-- spawn, inventory, hero-view, crafting-preview and loadout-sync path uses
-- to turn a loadout id into a record [src: backend_utils.lua:30-46;
-- simple_inventory_extension.lua:375-425,883; gear_utils.lua:601], so it
-- answers from the Fresh view directly instead of depending on the hook
-- topology of get_all_backend_items.
--
-- Instance shadows (issue #1637): a sibling mod may hook the live interface
-- INSTANCE rather than the class. VMF then builds a second hook chain on the
-- instance whose tail is the vanilla method itself, never the class chain
-- [src: vmf hooks.lua get_orig_function/create_internal_hook, the
-- `_registry.uids` origin remap], so the class-level route is bypassed for
-- every call that reaches the instance: loadout ids came from the native
-- mirror while get_item_from_id answered from the Fresh view, and the Keep
-- spawn ferrored on an empty melee slot. The tick therefore joins the
-- instance chain for every routed method a sibling shadowed, keeping the
-- per-call decision identical on both paths.
--
-- Routing is a per-call decision, never a mutation of the native object, so
-- every exit path (setting change, realm, fault, disable) restores official
-- reads by simply delegating to the original method. The native mirror is
-- never written while routing is active; writes commit to the MP profile
-- through a copy-on-write persistence transaction.
--
-- Owned by: modded_progression.lua (single install call). No Managers or VMF
-- globals are read directly; everything arrives through `deps`.
local Runtime = {}

Runtime.CLASS = "BackendInterfaceItemPlayfab"
Runtime.LOG_PREFIX = "[mp:fresh]"
Runtime.PENDING_SLICES = "xp_talents,currencies,crafting_loot"
Runtime.READ_METHODS = {
    "get_all_backend_items", "get_all_fake_backend_items", "get_loadout", "get_bot_loadout",
    "get_career_loadouts", "get_selected_career_loadout", "get_default_loadouts",
    "get_default_override", "get_loadout_item_id", "get_backend_id_from_cosmetic_item",
    "get_unlocked_weapon_poses", "get_equipped_weapon_pose_skins", "get_equipped_weapon_pose_skin",
    "sum_best_power_levels", "equipped_by_loadout", "is_equipped_by_any_loadout",
}
Runtime.WRITE_METHODS = {
    "set_loadout_item", "set_loadout_index", "add_loadout", "delete_loadout", "set_weapon_pose_skin",
}
-- Fresh-first id lookups: a miss continues down the hook chain (sibling
-- synthetic ids still resolve) and the chain ends at vanilla, which reads
-- the routed get_all_backend_items [src: backend_interface_item_playfab.lua:384-389].
Runtime.LOOKUP_METHODS = { "get_item_from_id" }

function Runtime.routed_methods()
    local all = {}
    for _, list in ipairs({ Runtime.READ_METHODS, Runtime.LOOKUP_METHODS, Runtime.WRITE_METHODS }) do
        for _, method in ipairs(list) do all[#all + 1] = method end
    end
    return all
end

-- Native records carry these fields [src: playfab_mirror_base.lua:1723-1787];
-- the spawn path reads data/backend_id [src: simple_inventory_extension.lua:384-388]
-- and the buff path reads properties/traits/rarity [src: gear_utils.lua:601-620].
Runtime.EQUIPMENT_RECORD_FIELDS = { "data", "backend_id", "key", "rarity", "power_level", "properties", "traits" }
Runtime.COSMETIC_RECORD_FIELDS = { "data", "backend_id", "key", "rarity" }

local function capture(...)
    return select("#", ...), { ... }
end

local function sanitize(err)
    local text = tostring(err):gsub("[\r\n]+", " ")
    return text:sub(1, 120)
end

-- A vanilla level-1 hero carries hero power per_level * 1 + starting
-- [src: backend_utils.lua:84-90] and the total power floor is
-- MIN_POWER_LEVEL_CAP [src: power_level_settings.lua:5]; the difference is
-- the average item power that makes a fresh loadout sit exactly on the floor.
function Runtime.starter_item_power(min_power, cap, per_level, starting)
    if type(cap) ~= "number" or type(per_level) ~= "number" or type(starting) ~= "number" then
        return type(min_power) == "number" and math.max(0, min_power) or 0
    end
    local floor = type(min_power) == "number" and min_power or 0
    return math.max(floor, cap - (per_level + starting))
end

function Runtime.install(mod, deps)
    deps = deps or {}
    local State = assert(deps.state, "state is required")
    local rt_register = assert(deps.rt_register, "rt_register is required")
    local print_log = assert(deps.print_log, "print_log is required")
    local is_modded_realm = assert(deps.is_modded_realm, "is_modded_realm is required")
    local starting_state = assert(deps.starting_state, "starting_state is required")
    local global = assert(deps.global, "global accessor is required")
    local managers = deps.managers or function() return nil end
    local emporium_inventory = deps.emporium_inventory or function() return {} end
    local emporium_revision = deps.emporium_revision or function() return 0 end

    local R = {
        resolved = false,
        reason = nil,
        enabled = true,
        faulted = nil,
        handlers = {},
        last_token = nil,
    }
    local profile
    local view

    local function log(fmt, ...)
        local args = { ... }
        local n = select("#", ...)
        pcall(function()
            print_log(Runtime.LOG_PREFIX .. " " .. fmt, unpack(args, 1, n))
        end)
    end

    -- ------------------------------------------------------------
    -- Boot-time resolution: every routed method must exist on the live class.
    -- ------------------------------------------------------------
    local class = global(Runtime.CLASS)
    local missing = {}
    if type(class) ~= "table" then
        R.reason = "class_missing"
    else
        for _, method in ipairs(Runtime.routed_methods()) do
            if type(class[method]) ~= "function" then missing[#missing + 1] = method end
        end
        if #missing > 0 then
            table.sort(missing)
            R.reason = "missing:" .. table.concat(missing, ",")
        else
            R.resolved = true
        end
    end

    -- ------------------------------------------------------------
    -- Profile persistence (VMF settings backed)
    -- ------------------------------------------------------------
    local function load_profile()
        local ok, raw = pcall(mod.get, mod, State.SETTING_KEY)
        local normalized, reason = State.normalize(ok and raw or nil)
        profile = normalized
        return ok and reason or "unreadable"
    end

    local function persist(candidate)
        mod:set(State.SETTING_KEY, candidate, false)
    end

    load_profile()

    local function env()
        local from_level = global("PowerLevelFromLevelSettings")
        return {
            item_master_list = global("ItemMasterList"),
            career_settings = global("CareerSettings"),
            deus_default_loadout = global("DeusDefaultLoadout"),
            deus_mapping = global("DeusStartingWeaponTypeMapping"),
            item_power_level = Runtime.starter_item_power(
                global("MIN_POWER_LEVEL"), global("MIN_POWER_LEVEL_CAP"),
                type(from_level) == "table" and from_level.power_level_per_level or nil,
                type(from_level) == "table" and from_level.starting_power_level or nil),
        }
    end

    -- Same classification order as the #577 mirror overlay: weapon skin,
    -- cosmetic, weapon pose, plain item [src: playfab_mirror_base.lua:2494-2526].
    local function classify(key, data)
        local weapon_skins = global("WeaponSkins")
        if type(weapon_skins) == "table" and type(weapon_skins.skins) == "table"
                and weapon_skins.skins[key] then
            return "weapon_skin"
        end
        local cosmetic_utils = global("CosmeticUtils")
        if type(cosmetic_utils) == "table" and type(cosmetic_utils.is_cosmetic_item) == "function"
                and cosmetic_utils.is_cosmetic_item(data.slot_type) then
            return "cosmetic"
        end
        if data.slot_type == "weapon_pose" then return "weapon_pose" end
        return "item"
    end

    local function skin_item_key(skin_name)
        local weapon_skins = global("WeaponSkins")
        local fn = type(weapon_skins) == "table" and weapon_skins.matching_weapon_skin_item_key or nil
        if type(fn) ~= "function" then return nil end
        local ok, key = pcall(fn, skin_name)
        return ok and type(key) == "string" and key or nil
    end

    local function fault(stage, err)
        R.faulted = stage
        view = nil
        -- The fault line IS the transition receipt; the token flips here so the
        -- next predicate evaluation does not print a second transition.
        R.last_token = "official:fault"
        log("route state=official:fault stage=%s error=%s generation=%d backend=none",
            tostring(stage), sanitize(err), profile.generation)
    end

    local function ensure_seeded()
        if State.items_slice(profile) then return true end
        local e = env()
        if type(e.item_master_list) ~= "table" or type(e.career_settings) ~= "table" then
            return false, "data_unavailable"
        end
        local slice, report = State.seed_items(profile, e)
        if report.careers == 0 or report.weapons == 0 then return false, "seed_empty" end
        local candidate = State.copy(profile)
        candidate.slices[State.SLICE] = slice
        persist(candidate)
        profile = candidate
        view = nil
        local sources = {}
        for name, n in pairs(report.sources) do sources[#sources + 1] = name .. "=" .. n end
        table.sort(sources)
        log("seed generation=%d careers=%d weapons=%d jewellery=%d cosmetics=%d missing=%d item_power=%d sources=%s backend=none",
            profile.generation, report.careers, report.weapons, report.jewellery, report.cosmetics,
            report.missing, e.item_power_level, table.concat(sources, ";"))
        return true
    end

    local function transition(token)
        if token == R.last_token then return end
        R.last_token = token
        log("route state=%s generation=%d slices=items pending=%s backend=none",
            token, profile.generation, Runtime.PENDING_SLICES)
    end

    local function compute_token()
        if not R.enabled then return "official:disabled" end
        if not R.resolved then return "official:unresolved" end
        if R.faulted then return "official:fault" end
        if not is_modded_realm() then return "official:realm" end
        if starting_state() ~= "fresh" then return "official:setting" end
        local seeded, reason = ensure_seeded()
        if not seeded then return "official:" .. tostring(reason) end
        return "active"
    end

    function R.active()
        local ok, token = pcall(compute_token)
        if not ok then
            fault("route", token)
            token = "official:fault"
        end
        transition(token)
        return token == "active"
    end

    function R.state_token()
        return R.last_token
    end

    function R.set_enabled(flag)
        R.enabled = flag == true
        view = nil
    end

    -- The live items interface instance without the get_interface warning
    -- (#695); _interfaces is the manager's own field [src: backend_manager_playfab.lua:201-208].
    local function live_items_interface()
        local m = managers()
        local backend = type(m) == "table" and m.backend or nil
        if type(backend) ~= "table" then return nil end
        local interfaces = rawget(backend, "_interfaces")
        local instance = type(interfaces) == "table" and interfaces.items or nil
        return type(instance) == "table" and instance or nil
    end

    -- Routed methods a sibling shadowed on the instance table (a raw field
    -- on the instance, not the class), i.e. the calls that bypass the class chain.
    function R.instance_shadows(instance)
        local shadows = {}
        if type(instance) ~= "table" then return shadows end
        for _, method in ipairs(Runtime.routed_methods()) do
            if rawget(instance, method) ~= nil then shadows[#shadows + 1] = method end
        end
        return shadows
    end

    local wrappers = {}
    R.joined = setmetatable({}, { __mode = "k" })

    -- Join the instance chain for every shadowed routed method, once per
    -- (instance, method). The routed wrapper is the same closure the class
    -- hook uses, so the per-call decision is identical on both paths.
    function R.join_instance(instance)
        if type(instance) ~= "table" or not R.resolved then return 0 end
        local joined = R.joined[instance]
        if not joined then
            joined = {}
            R.joined[instance] = joined
        end
        local added = {}
        for _, method in ipairs(R.instance_shadows(instance)) do
            if not joined[method] and wrappers[method] then
                mod:hook(instance, method, wrappers[method])
                joined[method] = true
                added[#added + 1] = method
            end
        end
        if #added > 0 then
            log("instance_join methods=%s backend=none", table.concat(added, ","))
        end
        return #added
    end

    function R.tick()
        R.active()
        local instance = live_items_interface()
        if instance then R.join_instance(instance) end
    end

    function R.reset()
        local candidate = State.new_profile(profile)
        local ok, err = pcall(persist, candidate)
        if not ok then
            log("reset_failed generation=%d error=%s backend=none", profile.generation, sanitize(err))
            return false
        end
        profile = candidate
        view = nil
        R.faulted = nil
        R.last_token = nil
        log("reset generation=%d backend=none", profile.generation)
        return true
    end

    function R.profile()
        return profile
    end

    function R.status()
        local slice = State.items_slice(profile)
        return string.format("fresh_profile generation=%d items=%s route=%s resolved=%s",
            profile.generation, slice and "seeded" or "unseeded",
            tostring(R.last_token or "unevaluated"), tostring(R.resolved))
    end

    -- ------------------------------------------------------------
    -- Runtime view of the persisted slice
    -- ------------------------------------------------------------
    local function current_view()
        local slice = State.items_slice(profile)
        assert(slice, "fresh profile is not seeded")
        local extras_revision = emporium_revision()
        if not view or view.revision ~= slice.revision or view.extras_revision ~= extras_revision then
            view = State.hydrate(slice, env(), {
                revision = extras_revision,
                emporium = emporium_inventory(),
                classify = classify,
                skin_item_key = skin_item_key,
            })
        end
        return view
    end
    R.view = current_view

    local function commit(mutate)
        local candidate = State.copy(profile)
        local slice = State.items_slice(candidate)
        if not slice then return false, "unseeded" end
        local ok, reason = mutate(slice)
        if not ok then return false, reason end
        persist(candidate)
        profile = candidate
        view = nil
        return true
    end

    local function game_mode_key()
        local m = managers()
        local state = type(m) == "table" and m.state or nil
        local game_mode = type(state) == "table" and state.game_mode or nil
        if type(game_mode) ~= "table" or type(game_mode.game_mode_key) ~= "function" then return nil end
        local ok, key = pcall(game_mode.game_mode_key, game_mode)
        return ok and key or nil
    end

    local function mechanism_name()
        local m = managers()
        local mechanism = type(m) == "table" and m.mechanism or nil
        if type(mechanism) ~= "table" or type(mechanism.current_mechanism_name) ~= "function" then return nil end
        local ok, name = pcall(mechanism.current_mechanism_name, mechanism)
        return ok and name or nil
    end

    local function inventory_settings()
        local settings = global("InventorySettings")
        return type(settings) == "table" and settings or {}
    end

    local function bot_equipment()
        local player_data = global("PlayerData")
        local selection = type(player_data) == "table" and player_data.loadout_selection or nil
        return type(selection) == "table" and selection.bot_equipment or nil
    end

    local function bot_loadouts()
        local allowed = inventory_settings().bot_loadout_allowed_mechanisms
        local mechanism = mechanism_name()
        return State.bot_loadouts(current_view(), bot_equipment(),
            type(allowed) == "table" and mechanism ~= nil and allowed[mechanism] == true)
    end

    -- ------------------------------------------------------------
    -- Handlers (self = the native interface instance; never touched)
    -- ------------------------------------------------------------
    local H = R.handlers

    function H.get_all_backend_items() return current_view().items end
    function H.get_all_fake_backend_items() return current_view().fake_items end
    function H.get_loadout() return State.loadouts(current_view()) end
    function H.get_bot_loadout() return bot_loadouts() end
    function H.get_career_loadouts(_, career) return State.career_loadouts(current_view(), career) end
    function H.get_selected_career_loadout(_, career) return State.selected_index(current_view(), career) end
    -- Mechanism default loadouts are a versus feature outside this slice.
    function H.get_default_loadouts() return nil end
    function H.get_default_override() return nil end
    local fallback_seen = {}
    function H.get_loadout_item_id(_, career, slot_name, is_bot)
        local allowed_modes = inventory_settings().bot_loadout_allowed_game_modes
        local key = game_mode_key()
        local bot_allowed = type(allowed_modes) == "table" and key ~= nil and allowed_modes[key] == true
        local bot_loadout = is_bot and bot_allowed and bot_loadouts()[career] or nil
        local id, reason = State.loadout_item_id(current_view(), career, slot_name, {
            is_bot = is_bot, bot_allowed = bot_allowed, bot_loadout = bot_loadout, env = env(),
        })
        if reason then
            -- One receipt per (career, slot, unresolved id): bounded by the loadout table.
            local seen_key = tostring(career) .. "/" .. tostring(slot_name) .. "/" .. reason
            if not fallback_seen[seen_key] then
                fallback_seen[seen_key] = true
                log("slot_fallback career=%s slot=%s %s to=%s backend=none",
                    tostring(career), tostring(slot_name), reason, tostring(id))
            end
        end
        return id
    end
    -- [src: backend_interface_item_playfab.lua:384-389]
    function H.get_item_from_id(_, backend_id)
        if backend_id == nil then return nil end
        return current_view().items[backend_id]
    end
    function H.get_backend_id_from_cosmetic_item(_, name) return current_view().unlocked_cosmetics[name] end
    function H.get_unlocked_weapon_poses() return current_view().unlocked_weapon_poses end
    function H.get_equipped_weapon_pose_skins() return current_view().pose_skins end
    function H.get_equipped_weapon_pose_skin(_, parent) return current_view().pose_skins[parent] end
    function H.sum_best_power_levels() return State.sum_best_power_levels(current_view()) end
    function H.equipped_by_loadout(_, backend_id) return State.equipped_by_loadout(current_view(), backend_id) end
    function H.is_equipped_by_any_loadout(_, backend_id)
        return State.is_equipped_by_any_loadout(current_view(), backend_id)
    end

    -- [src: backend_interface_item_playfab.lua:635-670]
    function H.set_loadout_item(_, item_id, career, slot_name, optional_loadout_index)
        local items = current_view().items
        local item = item_id ~= nil and items[item_id] or nil
        if not item then
            log("equip_rejected reason=item_unknown career=%s slot=%s backend=none",
                tostring(career), tostring(slot_name))
            return false
        end
        if item.rarity == "magic" then return false end
        local value = item_id
        if State.COSMETIC_SLOTS[slot_name] or slot_name == "slot_pose" then
            value = item.override_id or item.ItemId
        end
        local ok, reason = commit(function(slice)
            return State.set_loadout_item(slice, career, slot_name, value, optional_loadout_index)
        end)
        if not ok then
            log("equip_rejected reason=%s career=%s slot=%s backend=none",
                tostring(reason), tostring(career), tostring(slot_name))
            return false
        end
        return true
    end
    function H.set_loadout_index(_, career, index)
        commit(function(slice) return State.set_loadout_index(slice, career, index) end)
    end
    function H.add_loadout(_, career)
        local limit = inventory_settings().MAX_NUM_CUSTOM_LOADOUTS
        commit(function(slice) return State.add_loadout(slice, career, limit) end)
    end
    function H.delete_loadout(_, career, index)
        commit(function(slice) return State.delete_loadout(slice, career, index) end)
    end
    -- [src: backend_interface_item_playfab.lua:587-602]
    function H.set_weapon_pose_skin(_, parent_item_name, weapon_skin_backend_id)
        if not weapon_skin_backend_id then return end
        local current = current_view()
        local item = current.items[weapon_skin_backend_id]
        local skin_key = item and item.skin
        if not skin_key or current.pose_skins[parent_item_name] == skin_key then return end
        commit(function(slice) return State.set_weapon_pose_skin(slice, parent_item_name, skin_key) end)
    end

    -- ------------------------------------------------------------
    -- Route wrappers
    -- ------------------------------------------------------------
    local function route_read(method)
        local handler = assert(H[method], method)
        local wrapper = function(func, self, ...)
            if not R.active() then return func(self, ...) end
            local n, results = capture(pcall(handler, self, ...))
            if results[1] then return unpack(results, 2, n) end
            fault(method, results[2])
            return func(self, ...)
        end
        wrappers[method] = wrappers[method] or wrapper
        return wrapper
    end

    -- Fresh-first lookup: a handler hit answers; a miss continues down the
    -- chain (its tail reads the routed root, so no native record can answer
    -- while the route is active); a handler throw latches the fault.
    local function route_lookup(method)
        local handler = assert(H[method], method)
        local wrapper = function(func, self, ...)
            if not R.active() then return func(self, ...) end
            local ok, result = pcall(handler, self, ...)
            if not ok then
                fault(method, result)
            elseif result ~= nil then
                return result
            end
            return func(self, ...)
        end
        wrappers[method] = wrappers[method] or wrapper
        return wrapper
    end

    local function route_write(method, failure_value)
        local handler = assert(H[method], method)
        local wrapper = function(func, self, ...)
            if not R.active() then return func(self, ...) end
            local n, results = capture(pcall(handler, self, ...))
            if results[1] then return unpack(results, 2, n) end
            log("write_rejected method=%s error=%s backend=none", method, sanitize(results[2]))
            return failure_value
        end
        wrappers[method] = wrappers[method] or wrapper
        return wrapper
    end

    if R.resolved then
        mod:hook(Runtime.CLASS, "get_item_from_id", route_lookup("get_item_from_id"))
        mod:hook(Runtime.CLASS, "get_all_backend_items", route_read("get_all_backend_items"))
        mod:hook(Runtime.CLASS, "get_all_fake_backend_items", route_read("get_all_fake_backend_items"))
        mod:hook(Runtime.CLASS, "get_loadout", route_read("get_loadout"))
        mod:hook(Runtime.CLASS, "get_bot_loadout", route_read("get_bot_loadout"))
        mod:hook(Runtime.CLASS, "get_career_loadouts", route_read("get_career_loadouts"))
        mod:hook(Runtime.CLASS, "get_selected_career_loadout", route_read("get_selected_career_loadout"))
        mod:hook(Runtime.CLASS, "get_default_loadouts", route_read("get_default_loadouts"))
        mod:hook(Runtime.CLASS, "get_default_override", route_read("get_default_override"))
        mod:hook(Runtime.CLASS, "get_loadout_item_id", route_read("get_loadout_item_id"))
        mod:hook(Runtime.CLASS, "get_backend_id_from_cosmetic_item", route_read("get_backend_id_from_cosmetic_item"))
        mod:hook(Runtime.CLASS, "get_unlocked_weapon_poses", route_read("get_unlocked_weapon_poses"))
        mod:hook(Runtime.CLASS, "get_equipped_weapon_pose_skins", route_read("get_equipped_weapon_pose_skins"))
        mod:hook(Runtime.CLASS, "get_equipped_weapon_pose_skin", route_read("get_equipped_weapon_pose_skin"))
        mod:hook(Runtime.CLASS, "sum_best_power_levels", route_read("sum_best_power_levels"))
        mod:hook(Runtime.CLASS, "equipped_by_loadout", route_read("equipped_by_loadout"))
        mod:hook(Runtime.CLASS, "is_equipped_by_any_loadout", route_read("is_equipped_by_any_loadout"))
        mod:hook(Runtime.CLASS, "set_loadout_item", route_write("set_loadout_item", false))
        mod:hook(Runtime.CLASS, "set_loadout_index", route_write("set_loadout_index", nil))
        mod:hook(Runtime.CLASS, "add_loadout", route_write("add_loadout", nil))
        mod:hook(Runtime.CLASS, "delete_loadout", route_write("delete_loadout", nil))
        mod:hook(Runtime.CLASS, "set_weapon_pose_skin", route_write("set_weapon_pose_skin", nil))
    else
        transition("official:unresolved")
        log("route unresolved reason=%s backend=none", tostring(R.reason))
    end

    -- ------------------------------------------------------------
    -- In-game regression checks
    -- ------------------------------------------------------------
    rt_register("mp840_fresh_route_methods_resolved", function()
        if not R.resolved then
            return "items interface route unresolved: " .. tostring(R.reason)
        end
    end)

    rt_register("mp840_fresh_profile_envelope_valid", function()
        local ok, raw = pcall(mod.get, mod, State.SETTING_KEY)
        if not ok then return "profile setting unreadable" end
        local _, reason = State.normalize(raw)
        if raw ~= nil and reason ~= nil then return "stored profile is malformed: " .. reason end
        if type(profile) ~= "table" or profile.generation < 1 then return "in-memory profile invalid" end
    end)

    rt_register("mp840_fresh_route_write_never_touches_native", function()
        if not R.active() then return end
        local mirror = { _inventory_items = { official = { ItemId = "x" } }, _career_data = { a = {} } }
        local fake_self = { _backend_mirror = mirror }
        local snapshot = State.copy(mirror)
        local native_called = false
        local wrapper = route_write("set_loadout_item", false)
        local result = wrapper(function() native_called = true; return true end,
            fake_self, "mp840_rt_missing_item", "es_mercenary", "slot_melee")
        if native_called then return "routed write reached the native method" end
        if result ~= false then return "unknown item equip did not fail closed" end
        local function same(a, b)
            if type(a) ~= type(b) then return false end
            if type(a) ~= "table" then return a == b end
            for k, v in pairs(a) do if not same(v, b[k]) then return false end end
            for k in pairs(b) do if a[k] == nil then return false end end
            return true
        end
        if not same(mirror, snapshot) then return "native mirror mutated by a routed write" end
    end)

    -- ------------------------------------------------------------
    -- #1637: every id a view answers must resolve in the same view
    -- ------------------------------------------------------------
    local function record_problem(record, fields)
        if type(record) ~= "table" then return "no record" end
        for _, field in ipairs(fields) do
            if record[field] == nil then return "missing " .. field end
        end
        return nil
    end

    -- Every career/slot id the view answers must resolve to a native-shaped
    -- record, and every playable career (a DeusDefaultLoadout row) must answer
    -- both weapon slots so the Keep spawn always finds its wield slot.
    local function audit_view(view, lookup_id, lookup_item, e)
        local resolved = 0
        local playable = type(e.deus_default_loadout) == "table" and e.deus_default_loadout or {}
        for career in pairs(type(view) == "table" and view.careers or {}) do
            for _, slot in ipairs(State.LOADOUT_SLOTS) do
                local id = lookup_id(career, slot)
                if id == nil then
                    if State.WEAPON_SLOTS[slot] and playable[career] ~= nil then
                        return string.format("%s %s answered no id", tostring(career), slot)
                    end
                else
                    local cosmetic = State.COSMETIC_SLOTS[slot] or slot == "slot_pose"
                    local fields = cosmetic and Runtime.COSMETIC_RECORD_FIELDS or Runtime.EQUIPMENT_RECORD_FIELDS
                    local problem = record_problem(lookup_item(id), fields)
                    if problem then
                        return string.format("%s %s id=%s %s", tostring(career), slot, tostring(id), problem)
                    end
                    resolved = resolved + 1
                end
            end
        end
        if resolved == 0 then return "no career/slot resolved" end
        return nil
    end
    R.audit_view = audit_view

    -- A throwaway profile seeded from the live client data, never persisted.
    local function fixture_view()
        local e = env()
        local slice = State.seed_items(State.new_profile(nil), e)
        return State.hydrate(slice, e, {
            revision = 0, emporium = {}, classify = classify, skin_item_key = skin_item_key,
        }), e
    end

    rt_register("mp840_fresh_route_spawn_lookup_closed", function()
        if not R.resolved then return "items interface route unresolved: " .. tostring(R.reason) end
        local view, e = fixture_view()
        local problem = audit_view(view, function(career, slot)
            return (State.loadout_item_id(view, career, slot, { env = e }))
        end, function(id) return view.items[id] end, e)
        if problem then return "fixture profile: " .. problem end
        if R.active() then
            problem = audit_view(current_view(), function(career, slot)
                return H.get_loadout_item_id(nil, career, slot, false)
            end, function(id) return H.get_item_from_id(nil, id) end, e)
            if problem then return "live route: " .. problem end
        else
            local native = {}
            local id = wrappers.get_loadout_item_id(function() return "native-id" end, native, "career", "slot_melee")
            local item = wrappers.get_item_from_id(function(_, backend_id)
                return "native:" .. tostring(backend_id)
            end, native, "native-id")
            if id ~= "native-id" or item ~= "native:native-id" then
                return "inactive route did not delegate the native lookup"
            end
        end
    end)

    rt_register("mp840_fresh_route_instance_shadows_joined", function()
        if not R.resolved then return "items interface route unresolved: " .. tostring(R.reason) end
        local instance = live_items_interface()
        if not instance then return "items interface unavailable" end
        local joined = R.joined[instance] or {}
        for _, method in ipairs(R.instance_shadows(instance)) do
            if not joined[method] then return "instance shadow not joined: " .. method end
        end
    end)

    return R
end

return Runtime
