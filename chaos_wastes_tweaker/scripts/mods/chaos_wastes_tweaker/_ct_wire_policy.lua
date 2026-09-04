-- Exact public-stream wire contract for issue #426.
--
-- Public Tweaker: Chaos Wastes v0.7.131-beta registered ten power-up names
-- and nineteen buff-template names into process-local NetworkLookup axes. The
-- order below is the observed public registration order. It is deliberately
-- NOT alphabetical: changing it would renumber rows for a frozen public peer.
-- Gameplay uses this module only through _ct_peer_parity_owner.lua.

local M = {}

local POWER_ORDER = {
    "ct_meta_stagger",
    "ct_meta_crit",
    "ct_meta_health",
    "ct_meta_cooldown",
    "ct_meta_ammo",
    "ct_meta_movespeed",
    "ct_boon_asuryan_wrath",
    "ct_boon_manann_tempest",
    "ct_boon_taal_twinned_arrow",
    "ct_boon_vauls_anvil",
}

local BUFF_ORDER = {
    "ct_miracle_of_ulric",
    "ct_miracle_of_isha_aegis",
    "ct_miracle_of_isha_wounds",
    "ct_meta_stagger_stack",
    "power_up_ct_meta_stagger_exotic",
    "ct_meta_crit_stack",
    "power_up_ct_meta_crit_exotic",
    "ct_meta_health_stack",
    "power_up_ct_meta_health_exotic",
    "ct_meta_cooldown_stack",
    "power_up_ct_meta_cooldown_exotic",
    "ct_meta_ammo_stack",
    "power_up_ct_meta_ammo_exotic",
    "ct_meta_movespeed_stack",
    "power_up_ct_meta_movespeed_exotic",
    "power_up_ct_boon_asuryan_wrath_unique",
    "power_up_ct_boon_manann_tempest_unique",
    "power_up_ct_boon_taal_twinned_arrow_unique",
    "power_up_ct_boon_vauls_anvil_unique",
}

local POWER_RARITY = {
    ct_meta_stagger = "exotic",
    ct_meta_crit = "exotic",
    ct_meta_health = "exotic",
    ct_meta_cooldown = "exotic",
    ct_meta_ammo = "exotic",
    ct_meta_movespeed = "exotic",
    ct_boon_asuryan_wrath = "unique",
    ct_boon_manann_tempest = "unique",
    ct_boon_taal_twinned_arrow = "unique",
    ct_boon_vauls_anvil = "unique",
}

local BUFFS = {}
for i = 1, #BUFF_ORDER do BUFFS[BUFF_ORDER[i]] = true end

M.POWER_UP_COUNT = 10
M.BUFF_COUNT = 19
M.WIRE_ROW_COUNT = 29
M.IDENTITY_NAMESPACE = "ct-public-wire-v1"
M.MAX_STATE_ROWS = 4096

-- These are the complete public controls that can cause one of the cataloged
-- rows to be offered, granted, or applied. Disabling a boon remains usable and
-- is intentionally not presentation-gated.
M.GATED_SETTING_IDS = {
    "start_boon_ct_meta_stagger",
    "start_boon_ct_meta_crit",
    "start_boon_ct_meta_health",
    "start_boon_ct_meta_cooldown",
    "start_boon_ct_meta_ammo",
    "start_boon_ct_meta_movespeed",
    "start_boon_ct_boon_asuryan_wrath",
    "start_boon_ct_boon_manann_tempest",
    "start_boon_ct_boon_taal_twinned_arrow",
    "start_boon_ct_boon_vauls_anvil",
    "enable_boon_asuryan_wrath",
    "enable_boon_manann_tempest",
    "enable_boon_taal_twinned_arrow",
    "enable_boon_vauls_anvil",
    "tweak_miracle_of_isha_aegis",
    "tweak_miracle_of_isha_wounds",
    "tweak_miracle_of_ulric_persistent",
}

M.GATE_REASON = "Unavailable until every player in the lobby has the same Tweaker: Chaos Wastes wire catalog."

local function copy_array(values)
    local out = {}
    for i = 1, #values do out[i] = values[i] end
    return out
end

local function copy_power_map()
    local out = {}
    for name, rarity in pairs(POWER_RARITY) do out[name] = { rarity = rarity } end
    return out
end

local function positive_integer(value)
    return type(value) == "number" and value > 0 and value == value
        and value ~= math.huge and value ~= -math.huge
        and value <= 9007199254740991
        and math.floor(value) == value
end

local function finite_integer(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
        and value >= -2147483648 and value <= 2147483647
        and math.floor(value) == value
end

local function valid_lookup_row(lookup, name)
    local id = type(lookup) == "table" and rawget(lookup, name) or nil
    return positive_integer(id) and rawget(lookup, id) == name
end

function M.power_up_entries() return copy_power_map() end
function M.buff_entries()
    local out = {}
    for name in pairs(BUFFS) do out[name] = true end
    return out
end
function M.power_order() return copy_array(POWER_ORDER) end
function M.buff_order() return copy_array(BUFF_ORDER) end
function M.is_power_up(name) return POWER_RARITY[name] ~= nil end
function M.is_buff(name) return BUFFS[name] == true end
function M.is_owned_power_up_name(name)
    return type(name) == "string" and name:find("^ct_") ~= nil
end
function M.is_owned_buff_name(name)
    return type(name) == "string"
        and (name:find("^ct_") ~= nil or name:find("^power_up_ct_") ~= nil)
end

function M.count(values)
    local n = 0
    for _ in pairs(values or {}) do n = n + 1 end
    return n
end

local function valid_name(value)
    return type(value) == "string" and value ~= ""
end

-- This is the same complete-table proof required by the canonical
-- _lib_network_lookup registrar. It lives here because a 10+19 reservation has
-- to preflight BOTH axes before either one is mutated; calling a one-row
-- registrar repeatedly could leave half the public catalog committed.
local function inspect_axis(network_lookup, axis_name, order, maximum_id)
    local lookup = type(network_lookup) == "table" and rawget(network_lookup, axis_name)
    if type(lookup) ~= "table" then return nil, "lookup-axis-missing:" .. axis_name end

    local numeric_count, numeric_max = 0, 0
    for key, value in next, lookup do
        if type(key) == "number" then
            if not positive_integer(key) then
                return nil, "lookup-numeric-key-invalid:" .. axis_name
            end
            if key > maximum_id then
                return nil, "lookup-capacity-exceeded:" .. axis_name
            end
            numeric_count = numeric_count + 1
            if key > numeric_max then numeric_max = key end
            if not valid_name(value) or rawget(lookup, value) ~= key then
                return nil, "lookup-pair-asymmetric:" .. axis_name
            end
        elseif type(key) == "string" then
            if not valid_name(key) or not positive_integer(value)
                    or rawget(lookup, value) ~= key then
                return nil, "lookup-pair-asymmetric:" .. axis_name
            end
            if value > maximum_id then
                return nil, "lookup-capacity-exceeded:" .. axis_name
            end
        else
            return nil, "lookup-key-invalid:" .. axis_name
        end
    end
    if numeric_count ~= numeric_max then
        return nil, "lookup-numeric-side-sparse:" .. axis_name
    end

    local existing = 0
    for i = 1, #order do
        local name = order[i]
        local id = rawget(lookup, name)
        if id ~= nil then
            if not valid_lookup_row(lookup, name) then
                return nil, "lookup-mismatch:" .. axis_name .. ":" .. name
            end
            existing = existing + 1
        end
    end

    if existing ~= 0 and existing ~= #order then
        return nil, "partial-existing-catalog:" .. axis_name
    end

    if existing == #order then
        local first = rawget(lookup, order[1])
        for i = 1, #order do
            if rawget(lookup, order[i]) ~= first + i - 1 then
                return nil, "legacy-order-mismatch:" .. axis_name .. ":" .. order[i]
            end
        end
        return {
            lookup = lookup, order = order, added = 0,
            first_id = first, last_id = first + #order - 1,
        }
    end

    local first = numeric_max + 1
    if first + #order - 1 > maximum_id then
        return nil, "lookup-capacity-exceeded:" .. axis_name
    end
    return {
        lookup = lookup, order = order, added = #order,
        first_id = first, last_id = first + #order - 1,
    }
end

function M.reserve_lookups(network_lookup, capacities)
    -- Preflight both complete raw tables first. In particular, a malformed
    -- buff axis must leave the power axis byte-for-byte and raw-shape intact.
    local buff_max = type(capacities) == "table" and rawget(capacities, "buff")
    if not positive_integer(buff_max) then
        return nil, "lookup-capacity-missing:buff_templates"
    end
    local power, power_error = inspect_axis(
        network_lookup, "deus_power_up_templates", POWER_ORDER, 255)
    if not power then return nil, power_error end
    local buff, buff_error = inspect_axis(
        network_lookup, "buff_templates", BUFF_ORDER, buff_max)
    if not buff then return nil, buff_error end
    if power.lookup == buff.lookup then return nil, "lookup-axes-aliased" end

    for _, plan in ipairs({ power, buff }) do
        if plan.added > 0 then
            for i = 1, #plan.order do
                local name = plan.order[i]
                local id = plan.first_id + i - 1
                rawset(plan.lookup, id, name)
                rawset(plan.lookup, name, id)
            end
        end
    end
    -- Reservation plans retain mutable engine tables and the module-private
    -- frozen order while the atomic commit runs.  Never publish either object:
    -- callers only need scalar evidence, and exposing `order` would let a
    -- diagnostic accidentally mutate the catalog contract for later calls.
    return {
        power_up = {
            added = power.added,
            first_id = power.first_id,
            last_id = power.last_id,
        },
        buff = {
            added = buff.added,
            first_id = buff.first_id,
            last_id = buff.last_id,
        },
    }
end

function M.power_registry_ready(registry)
    if type(registry) ~= "table" then return false, "power-registry-missing" end
    for name in pairs(POWER_RARITY) do
        if type(registry[name]) ~= "table" then
            return false, "registered-power-missing:" .. name
        end
    end
    for name in pairs(registry) do
        if not M.is_power_up(name) then
            return false, "registered-power-unowned:" .. tostring(name)
        end
    end
    return true
end

function M.catalog_ready(globals)
    globals = globals or {}
    local network_lookup = globals.NetworkLookup
    local power_lookup = type(network_lookup) == "table"
        and rawget(network_lookup, "deus_power_up_templates")
    local buff_lookup = type(network_lookup) == "table"
        and rawget(network_lookup, "buff_templates")
    local templates = globals.DeusPowerUpTemplates
    local powers = globals.DeusPowerUps
    local buffs = globals.BuffTemplates

    for name, rarity in pairs(POWER_RARITY) do
        if not valid_lookup_row(power_lookup, name) then
            return false, "power-lookup-mismatch:" .. name
        end
        if type(templates) ~= "table" or type(templates[name]) ~= "table" then
            return false, "power-template-missing:" .. name
        end
        if type(powers) ~= "table" or type(powers[rarity]) ~= "table"
                or type(powers[rarity][name]) ~= "table" then
            return false, "power-runtime-missing:" .. name
        end
    end
    for name in pairs(BUFFS) do
        if not valid_lookup_row(buff_lookup, name) then
            return false, "buff-lookup-mismatch:" .. name
        end
        if type(buffs) ~= "table" or type(buffs[name]) ~= "table" then
            return false, "buff-template-missing:" .. name
        end
    end
    return true
end

local function feed_hash(seed, multiplier, modulus, value)
    for i = 1, #value do
        seed = (seed * multiplier + string.byte(value, i)) % modulus
    end
    return seed
end

function M.build_identity(Catalog, network_lookup)
    if type(Catalog) ~= "table" or type(Catalog.build_identity) ~= "function" then
        return nil, "wire-catalog-library-missing"
    end
    local power_entries = {}
    for name in pairs(POWER_RARITY) do power_entries[name] = true end
    local power, power_error = Catalog.build_identity(
        M.IDENTITY_NAMESPACE .. ".deus_power_up_templates", power_entries,
        network_lookup and rawget(network_lookup, "deus_power_up_templates"))
    if not power then return nil, power_error end
    local buff, buff_error = Catalog.build_identity(
        M.IDENTITY_NAMESPACE .. ".buff_templates", BUFFS,
        network_lookup and rawget(network_lookup, "buff_templates"))
    if not buff then return nil, buff_error end
    local canonical = "ct-wire-v1|power=" .. power .. "|buff=" .. buff
    local h1 = feed_hash(104729, 131, 2147483647, canonical)
    local h2 = feed_hash(130363, 257, 2147483629, canonical)
    return string.format("ct-wire-v1:%d:%08x:%08x", M.WIRE_ROW_COUNT, h1, h2)
end

function M.capture_integrity(network_lookup)
    if type(network_lookup) ~= "table" then return nil, "network-lookup-missing" end
    local snapshot = { network_lookup = network_lookup, rows = {} }
    local axes = {
        { name = "deus_power_up_templates", order = POWER_ORDER },
        { name = "buff_templates", order = BUFF_ORDER },
    }
    for a = 1, #axes do
        local axis = axes[a]
        local lookup = rawget(network_lookup, axis.name)
        if type(lookup) ~= "table" then return nil, "lookup-axis-missing:" .. axis.name end
        for i = 1, #axis.order do
            local name = axis.order[i]
            if not valid_lookup_row(lookup, name) then
                return nil, "lookup-mismatch:" .. axis.name .. ":" .. name
            end
            snapshot.rows[#snapshot.rows + 1] = {
                axis = axis.name,
                lookup = lookup,
                name = name,
                id = rawget(lookup, name),
            }
        end
    end
    return snapshot
end

function M.integrity(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.network_lookup) ~= "table"
            or type(snapshot.rows) ~= "table" or #snapshot.rows ~= M.WIRE_ROW_COUNT then
        return false, "integrity-snapshot-invalid"
    end
    for i = 1, #snapshot.rows do
        local row = snapshot.rows[i]
        if rawget(snapshot.network_lookup, row.axis) ~= row.lookup
                or rawget(row.lookup, row.name) ~= row.id
                or rawget(row.lookup, row.id) ~= row.name then
            return false, "integrity-mismatch:" .. tostring(row.axis)
                .. ":" .. tostring(row.name)
        end
    end
    return true
end

local function inspect_array(values, entry_valid)
    if type(values) ~= "table" then return nil, "array-missing" end
    local count, maximum = 0, 0
    for key in next, values do
        if not positive_integer(key) or key > M.MAX_STATE_ROWS then
            return nil, "array-key-invalid"
        end
        count = count + 1
        if key > maximum then maximum = key end
    end
    if count ~= maximum then return nil, "array-sparse" end
    for i = 1, maximum do
        local valid, reason = entry_valid(rawget(values, i))
        if not valid then return nil, reason .. ":" .. tostring(i) end
    end
    return maximum
end

local function valid_power_up(value)
    if type(value) ~= "table" then return false, "power-up-entry-invalid" end
    if not valid_name(rawget(value, "name")) then
        return false, "power-up-name-invalid"
    end
    local name = rawget(value, "name")
    local rarity = rawget(value, "rarity")
    if not valid_name(rarity) then
        return false, "power-up-rarity-invalid"
    end
    if M.is_power_up(name) and rarity ~= POWER_RARITY[name] then
        return false, "power-up-rarity-mismatch"
    end
    if not finite_integer(rawget(value, "client_id")) then
        return false, "power-up-client-id-invalid"
    end
    return true
end

local function valid_named_entry(value)
    return valid_name(value), "name-entry-invalid"
end

function M.filter_power_ups(values, exact_safe)
    local filtered, removed = {}, 0
    local count, reason = inspect_array(values, valid_power_up)
    if not count then return nil, 0, reason end
    for i = 1, count do
        local value = rawget(values, i)
        local name = rawget(value, "name")
        local owned = M.is_owned_power_up_name(name)
        if owned and (exact_safe ~= true or not M.is_power_up(name)) then
            removed = removed + 1
        else
            filtered[#filtered + 1] = value
        end
    end
    return filtered, removed
end

function M.filter_power_up_names(values, exact_safe)
    local filtered, removed = {}, 0
    local count, reason = inspect_array(values, valid_named_entry)
    if not count then return nil, 0, reason end
    for i = 1, count do
        local name = rawget(values, i)
        local owned = M.is_owned_power_up_name(name)
        if owned and (exact_safe ~= true or not M.is_power_up(name)) then
            removed = removed + 1
        else filtered[#filtered + 1] = name end
    end
    return filtered, removed
end

function M.filter_persistent_buffs(values, exact_safe)
    local filtered, removed = {}, 0
    local count, reason = inspect_array(values, valid_named_entry)
    if not count then return nil, 0, reason end
    for i = 1, count do
        local name = rawget(values, i)
        local owned = M.is_owned_buff_name(name)
        if owned and (exact_safe ~= true or not M.is_buff(name)) then
            removed = removed + 1
        else filtered[#filtered + 1] = name end
    end
    return filtered, removed
end

function M.power_up_allowed(name, exact_safe)
    if not M.is_owned_power_up_name(name) then return true end
    return M.is_power_up(name) and exact_safe == true
end

function M.buff_allowed(name, exact_safe)
    if not M.is_owned_buff_name(name) then return true end
    return M.is_buff(name) and exact_safe == true
end

-- `DeusRunController.rpc_deus_shop_power_up_bought` maps its sender, divides
-- the encoded discount, clones `DeusPowerUps[rarity][name]`, and writes the
-- supplied client id before `_try_buy_power_up` gets control
-- (`deus_run_controller.lua:1058-1068`). Validate that whole source contract
-- before native can touch it. Valid vanilla/third-party rows stay independent
-- of CT parity, while a current CT row requires the exact sender/roster proof
-- supplied by the owner. Every engine-table read is raw so a strict lookup
-- metatable cannot turn a rejected packet into another crash.
function M.shop_power_up_decision(power_ups, rarity, name, client_id, discount,
        sender, sender_exact, server_peer_id, receiver_is_server)
    if not valid_name(rarity) or not valid_name(name) then
        return false, "shop-identity-invalid"
    end
    if receiver_is_server ~= true or not valid_name(sender)
            or not valid_name(server_peer_id) or sender == server_peer_id then
        return false, "shop-sender-context-invalid"
    end
    if not finite_integer(client_id) then
        return false, "shop-client-id-invalid"
    end
    -- Vanilla sends a percentage multiplied by 10,000 (currently either 0 or
    -- 5,000). Keep the complete percentage domain, but reject a forged
    -- negative price or a value above a 100% discount before native arithmetic.
    if not finite_integer(discount) or discount < 0 or discount > 10000 then
        return false, "shop-discount-invalid"
    end
    local current = M.is_power_up(name)
    local owned = M.is_owned_power_up_name(name)
    if owned and not current then return false, "stale-ct-identity" end
    if current and POWER_RARITY[name] ~= rarity then
        return false, "power-up-rarity-mismatch"
    end
    -- Reject an unproven CT request before even consulting the mutable engine
    -- registry. The callback may be retained after a failed owner transaction,
    -- and pending/rejected/foreign peers must remain inert in that state.
    if current and sender_exact ~= true then
        return false, "ct-sender-unproven"
    end
    local rarity_rows = type(power_ups) == "table" and rawget(power_ups, rarity)
    local row = type(rarity_rows) == "table" and rawget(rarity_rows, name)
    if type(row) ~= "table" or rawget(row, "name") ~= name
            or rawget(row, "rarity") ~= rarity then
        return false, "shop-runtime-row-invalid"
    end
    return true
end

-- Unknown numeric rows are never handed to NetworkLookup's strict __index.
-- A locally recognized CT row additionally requires exact sender proof.
function M.receiver_decision(name, sender_exact, kind)
    if name == nil then return false, "unknown-lookup-id" end
    local current, owned
    if kind == "power_up" then
        current, owned = M.is_power_up(name), M.is_owned_power_up_name(name)
    elseif kind == "buff" then
        current, owned = M.is_buff(name), M.is_owned_buff_name(name)
    else
        return false, "receiver-kind-invalid"
    end
    if owned and not current then return false, "stale-ct-identity" end
    if current then
        return sender_exact == true, sender_exact == true and nil or "ct-sender-unproven"
    end
    return true
end

function M.runtime_gate_setting_ids() return copy_array(M.GATED_SETTING_IDS) end

function M.runtime_gate_spec(mod_id, setting_ids, evaluate)
    if setting_ids == nil then setting_ids = M.runtime_gate_setting_ids() end
    if type(mod_id) ~= "string" or mod_id == "" or type(setting_ids) ~= "table"
            or type(evaluate) ~= "function" then return nil end
    local copied, seen = {}, {}
    for i = 1, #setting_ids do
        local id = setting_ids[i]
        if type(id) ~= "string" or id == "" or seen[id] then return nil end
        seen[id] = true
        copied[#copied + 1] = id
    end
    if #copied == 0 then return nil end
    return { mod_id = mod_id, setting_ids = copied, evaluate = evaluate }
end

function M.try_register_runtime_gate(get_mod_fn, gate_id, spec)
    if type(get_mod_fn) ~= "function" or type(gate_id) ~= "string" or gate_id == ""
            or type(spec) ~= "table" then
        return false, "runtime-gate-arguments-invalid"
    end
    for _, gut_id in ipairs({ "gut", "gut_dev" }) do
        local ok, gut = pcall(get_mod_fn, gut_id)
        local tweaker = ok and type(gut) == "table" and gut.mod_tweaker or nil
        if type(tweaker) == "table" and type(tweaker.register_runtime_gate) == "function" then
            local registered_ok, registered = pcall(
                tweaker.register_runtime_gate, tweaker, gate_id, spec)
            if registered_ok and registered == true then return true end
        end
    end
    return false, "mod-tweaker-unavailable"
end

return M
