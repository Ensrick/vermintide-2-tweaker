-- #645 actor admission. Engine-free; every native table/resolver is injected.
-- No can_wield, item/career prefixes, viewer-profile fallback or cached verdict.
local M = {}
local REQUIRED = { es_1h_sword = "empire_soldier", we_1h_sword = "wood_elf" }
local function field(value, key)
    if type(value) ~= "table" then return nil end
    return rawget(value, key)
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    return ok and value or nil
end
-- Native class() instances inherit methods; raw data membership remains field().
-- A destroyed object's __index and a method body can both throw.
local function method(object, key, ...)
    if type(object) ~= "table" then return "missing" end
    local ok, fn = pcall(function() return object[key] end)
    if not ok then return "error" end
    if type(fn) ~= "function" then return "missing" end
    local called, value = pcall(fn, object, ...)
    if not called then return "error" end
    return "ok", value
end
local function player_indices(player)
    local ps, pi = method(player, "profile_index")
    local cs, ci = method(player, "career_index")
    if ps ~= "ok" or cs ~= "ok" then return nil end
    return pi, ci
end
local function pack(...) return { n = select("#", ...), ... } end
function M.restricted(key) return REQUIRED[key] ~= nil end
function M.admitted(key, profile)
    return REQUIRED[key] == nil or profile == REQUIRED[key]
end
function M.bind(deps)
    local A = { creation = nil }
    local function profiles() return call(deps.profiles) end
    local function careers() return call(deps.careers) end
    local function managers() return call(deps.managers) end
    local function index_profile(pi, ci)
        local profile = field(profiles(), pi)
        local career = field(field(profile, "careers"), ci)
        local name, display = field(career, "name"), field(profile, "display_name")
        if type(name) ~= "string" or type(display) ~= "string"
                or not rawequal(field(careers(), name), career)
                or field(career, "profile_name") ~= display then return nil end
        return display
    end
    local function player_profile(player)
        local pi, ci = player_indices(player)
        return index_profile(pi, ci)
    end
    local function peer_player(peer_id)
        return call(deps.peer_resolver.peer_player, field(managers(), "player"), peer_id, 1)
    end
    function A:peer_profile(peer_id)
        local player = peer_player(peer_id)
        if not player then return nil end
        local network = field(field(managers(), "state"), "network")
        local psync = field(network, "profile_synchronizer")
        local pi, ci = deps.peer_resolver.profile_by_peer(psync, peer_id, 1)
        return index_profile(pi, ci)
    end
    function A:is_local_unit(unit)
        local player = call(deps.peer_resolver.local_player, field(managers(), "player"), 1)
        return unit ~= nil and field(player, "player_unit") == unit
    end
    function A:inventory_profile(inventory, slot_name, item)
        local unit, player = field(inventory, "_unit"), field(inventory, "player")
        local pi, ci = player_indices(player)
        local profile = index_profile(pi, ci)
        local career = field(careers(), field(inventory, "_career_name"))
        if unit == nil or field(inventory, "is_bot") ~= false or type(profile) ~= "string"
                or not rawequal(career, field(field(field(profiles(), pi), "careers"), ci)) then return nil end
        if item ~= nil then
            local slot = field(field(field(inventory, "_equipment"), "slots"), slot_name)
            if not rawequal(field(slot, "item_data"), field(item, "data") or item) then return nil end
        end
        local pm = field(managers(), "player")
        local status, owner = method(pm, "owner", unit)
        if status == "error" or (status == "ok" and owner ~= nil
                and not rawequal(owner, player)) then return nil end
        return profile
    end
    function A:selected_profile(window)
        local hero, ci = field(window, "hero_name"), field(window, "career_index")
        if type(hero) ~= "string" then return nil end
        local pi = call(deps.find_profile_index, hero)
        local profile = index_profile(pi, ci)
        return profile == hero and profile or nil
    end
    function A:console_profile(content)
        return index_profile(field(content, "profile_index"), field(content, "career_index"))
    end
    function A:slot(peer_id, slot_name)
        local player = peer_player(peer_id)
        local unit = field(player, "player_unit")
        local inventory = unit and call(deps.inventory_for_unit, unit)
        if field(inventory, "_unit") ~= unit then return nil end
        local equipment = field(inventory, "_equipment")
        local slot = field(field(equipment, "slots"), slot_name)
        return field(slot, "item_data"), unit, inventory
    end
    function A:local_item_profile(item, backend_id)
        local player = call(deps.peer_resolver.local_player, field(managers(), "player"), 1)
        local inventory = field(player, "player_unit") and call(deps.inventory_for_unit, player.player_unit)
        if field(inventory, "_unit") ~= field(player, "player_unit")
                or not rawequal(field(inventory, "player"), player) then return nil end
        local equipment = field(inventory, "_equipment")
        local data = field(item, "data") or item
        for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
            local slot = field(field(equipment, "slots"), slot_name)
            -- The caller must supply the exact installed local item object.
            -- A copied backend id or a selected-other-hero item is not ownership.
            if data ~= nil and rawequal(field(slot, "item_data"), data) then
                return player_profile(player)
            end
        end
        return nil
    end
    function A:admit(key, item, backend_id, actor)
        if not M.restricted(key) then return true end
        local profile
        if actor ~= nil then
            profile = call(actor)
        else
            profile = self:local_item_profile(item, backend_id)
        end
        return M.admitted(key, profile)
    end
    function A:creation_profile(item)
        local context = self.creation
        if not context or not rawequal(context.item, item) then return nil end
        if (context.slot ~= "slot_melee" and context.slot ~= "slot_ranged")
                or context.is_bot ~= false or context.unit == nil then return nil end
        -- extensions_ready creates equipment before spawn() assigns PM ownership.
        -- The already-installed inventory extension holds that actual init player.
        local inventory = call(deps.inventory_for_unit, context.unit)
        if field(inventory, "_unit") ~= context.unit
                or field(inventory, "_career_name") ~= context.career
                or field(inventory, "is_bot") ~= false then return nil end
        local profile = self:inventory_profile(inventory)
        local career = field(careers(), context.career)
        if type(profile) ~= "string" or field(career, "profile_name") ~= profile then return nil end
        return profile
    end
    function A:with_creation(item, unit, slot, is_bot, career, fn, ...)
        if not M.restricted(field(item, "name")) then return fn(...) end
        local prior = self.creation
        -- Even an invalid nested actor shadows an outer valid context.
        self.creation = { item = item, unit = unit, slot = slot, is_bot = is_bot, career = career }
        local result = pack(pcall(fn, ...))
        self.creation = prior
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
    return A
end
return M
