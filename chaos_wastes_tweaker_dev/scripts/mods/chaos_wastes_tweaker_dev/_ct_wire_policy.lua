-- _ct_wire_policy.lua -- pure wire policy for the #426 peer-parity gate.
--
-- Two halves, one owner:
--
--   EXACT CATALOG (this file's reason to exist). ct registers its modded boons
--   and miracles into two process-local NetworkLookup axes. The beacon proves a
--   peer RUNS ct; it does not prove that peer's integers mean the same names.
--   Two ct peers on different builds can both ack while their boon indices
--   disagree, and the decode is a STRICT-__index fatal, not a nil (#1191, the
--   v0.7.66 index-drift class). This module owns the closed catalogs, the
--   deterministic sorted reservation that keeps ids build-stable, the composite
--   identity the beacon compares, and the post-finalization integrity snapshot.
--
--   PRESENTATION (v0.7.319-dev). While the gate is closed, the saved rows that
--   control gated content must read as unavailable rather than silently doing
--   nothing. career_tweaker closes the same gap with _crt_wire_policy.lua; this
--   is ct's copy of that contract.
--
-- Kept pure so qa/lua drives the exact shipped decisions with no engine
-- globals, no hooks, and no mod handle. Owned by: _ct_peer_parity_owner.lua
-- (identity/integrity/gate) and _ct_boon_registry.lua (reservation).

local M = {}

-- ---------------------------------------------------------------------------
-- The closed catalogs
-- ---------------------------------------------------------------------------
-- Every name ct writes into NetworkLookup.deus_power_up_templates. Membership
-- is EXACT: a similarly prefixed vanilla or third-party name is not captured,
-- and a ct name missing here fails catalog finalization rather than riding the
-- wire uncovered. `rarity` is the DeusPowerUps bucket the runtime check reads.
local POWER_UPS = {
    ct_meta_stagger = { rarity = "exotic" },
    ct_meta_crit = { rarity = "exotic" },
    ct_meta_health = { rarity = "exotic" },
    ct_meta_cooldown = { rarity = "exotic" },
    ct_meta_ammo = { rarity = "exotic" },
    ct_meta_movespeed = { rarity = "exotic" },
    ct_boon_vauls_anvil = { rarity = "unique" },
    ct_boon_manann_tempest = { rarity = "unique" },
    ct_boon_taal_twinned_arrow = { rarity = "unique" },
    ct_boon_asuryan_wrath = { rarity = "unique" },
    ct_boon_anath_raema_swiftness = { rarity = "unique" },
    ct_kill_heal = { rarity = "exotic" },
}

-- Every name ct writes into NetworkLookup.buff_templates: one power_up_* buff
-- per cataloged power-up, the six meta stack templates, and the three miracles.
-- `ct_meta_movespeed_stack_1` and `ct_meta_movespeed_apply` are deliberately
-- ABSENT - the first is a sub-buff `name` field inside the stack template's
-- `buffs` array and the second a BuffFunctionTemplates key; neither is a
-- top-level BuffTemplates entry and neither is registered into the lookup
-- (`_ct_meta_boon_owner.lua` registers only the stack name).
local BUFFS = {
    power_up_ct_meta_stagger_exotic = true,
    power_up_ct_meta_crit_exotic = true,
    power_up_ct_meta_health_exotic = true,
    power_up_ct_meta_cooldown_exotic = true,
    power_up_ct_meta_ammo_exotic = true,
    power_up_ct_meta_movespeed_exotic = true,
    power_up_ct_boon_vauls_anvil_unique = true,
    power_up_ct_boon_manann_tempest_unique = true,
    power_up_ct_boon_taal_twinned_arrow_unique = true,
    power_up_ct_boon_asuryan_wrath_unique = true,
    power_up_ct_boon_anath_raema_swiftness_unique = true,
    power_up_ct_kill_heal_exotic = true,
    ct_meta_stagger_stack = true,
    ct_meta_crit_stack = true,
    ct_meta_health_stack = true,
    ct_meta_cooldown_stack = true,
    ct_meta_ammo_stack = true,
    ct_meta_movespeed_stack = true,
    ct_miracle_of_ulric = true,
    ct_miracle_of_isha_aegis = true,
    ct_miracle_of_isha_wounds = true,
}

-- Locked so a new boon cannot be added to one catalog and forgotten in the
-- other: the runtime finalizer refuses to build an identity unless the counts
-- still agree, and the integrity snapshot pins the same total.
M.POWER_UP_COUNT = 12
M.BUFF_COUNT = 21
M.WIRE_ROW_COUNT = 33

-- ---------------------------------------------------------------------------
-- Presentation contract (v0.7.319-dev, unchanged by the exact-catalog work)
-- ---------------------------------------------------------------------------
-- Every saved row whose content registers a ct-owned index into the two axes
-- above and therefore rides a vanilla RPC to peers. Grouped by what the row
-- controls so a future boon has an obvious home. The umbrella row is included
-- deliberately: with the gate closed it cannot enable anything, so leaving it
-- live would be the one control that still looks actionable.
--
-- The commented-out activate_dormant_* group in the data file is intentionally
-- absent - those widgets do not exist at runtime, and a gate spec naming an
-- unknown setting id is rejected wholesale by runtime_gate_spec.
--
-- The twelve start_boon_* rows joined in v0.7.322-dev: a starting boon is gate
-- surface 3 (_add_initial_power_ups), so while the gate is closed those rows
-- are exactly as inert as the rework toggles and must say so. Every id is a
-- live BOON_TREE-generated widget, asserted against _collect_setting_ids by
-- the issue426_runtime_gate_presentation instrument.
--
-- disable_boon_* rows are deliberately NOT gated: disabling modded content is
-- safe in any lobby, and greying those rows would remove the player's only
-- control that still does something while parity is missing.
M.GATED_SETTING_IDS = {
    -- Umbrella over every trait-boon row below.
    "enable_boon_reworks",
    -- Trait boons: power_up_ct_boon_*_unique (CT_TRAIT_BOONS).
    "enable_boon_anath_raema_swiftness",
    "enable_boon_asuryan_wrath",
    "enable_boon_manann_tempest",
    "enable_boon_taal_twinned_arrow",
    "enable_boon_vauls_anvil",
    -- Starting boons: one row per cataloged power-up.
    "start_boon_ct_meta_stagger",
    "start_boon_ct_meta_crit",
    "start_boon_ct_meta_health",
    "start_boon_ct_meta_cooldown",
    "start_boon_ct_meta_ammo",
    "start_boon_ct_meta_movespeed",
    "start_boon_ct_boon_vauls_anvil",
    "start_boon_ct_boon_manann_tempest",
    "start_boon_ct_boon_taal_twinned_arrow",
    "start_boon_ct_boon_asuryan_wrath",
    "start_boon_ct_boon_anath_raema_swiftness",
    "start_boon_ct_kill_heal",
    -- Miracles: ct_miracle_* buff templates.
    "tweak_miracle_of_isha_aegis",
    "tweak_miracle_of_isha_wounds",
    "tweak_miracle_of_ulric_persistent",
}

-- Player-facing reason shown on a gated row. No issue/lifecycle metadata and no
-- em dashes (CLAUDE.md non-negotiable 11 + LOCALIZATION_STANDARD section 13).
M.GATE_REASON = "Unavailable until every player in the lobby has Tweaker: Chaos Wastes."

-- ---------------------------------------------------------------------------
-- Catalog accessors
-- ---------------------------------------------------------------------------
local function copy_map(source)
    local out = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            local row = {}
            for field, field_value in pairs(value) do row[field] = field_value end
            out[key] = row
        else
            out[key] = value
        end
    end
    return out
end

local function sorted_names(entries)
    local names = {}
    for name in pairs(entries) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- A lookup row is only usable if BOTH directions agree: vanilla decodes by
-- integer (deus_run_state_spec.lua:85) and ct encodes by name, so a half-written
-- row is a fatal decode on the receiving peer rather than a local nil.
local function valid_lookup_row(lookup, name)
    local id = type(lookup) == "table" and rawget(lookup, name) or nil
    return type(id) == "number" and id > 0 and math.floor(id) == id
        and rawget(lookup, id) == name
end

function M.power_up_entries() return copy_map(POWER_UPS) end
function M.buff_entries() return copy_map(BUFFS) end

function M.count(entries)
    local n = 0
    for _ in pairs(entries or {}) do n = n + 1 end
    return n
end

function M.is_power_up(name) return POWER_UPS[name] ~= nil end
function M.is_buff(name) return BUFFS[name] == true end

-- Miracle/boon purchase decision. A cataloged power-up may only change hands
-- while the exact gate is open; vanilla names are always purchasable.
function M.purchase_allowed(name, exact_safe)
    return not M.is_power_up(name) or exact_safe == true
end

-- Two-way proof that the runtime injection registry and this catalog describe
-- the same set. A name in one and not the other means a boon was added without
-- updating the wire contract, which is precisely the drift #1191 is about.
function M.power_registry_ready(registry)
    if type(registry) ~= "table" then return false, "power-registry-missing" end
    for name in pairs(POWER_UPS) do
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

-- ---------------------------------------------------------------------------
-- Deterministic reservation
-- ---------------------------------------------------------------------------
-- Called ONCE, as early as possible, before any feature-order registration path
-- can append a name. Reserving in sorted order makes the assigned integers a
-- function of the catalog alone, so two ct peers agree even when their toggles,
-- DLC, or load order differ. Reservation is unconditional (the v0.7.67 split:
-- registration is unconditional, POOL insertion is toggle-gated) - it grants no
-- gameplay, it only pins the numbering.
local function reserve_axis(network_lookup, axis, entries)
    local lookup = type(network_lookup) == "table" and rawget(network_lookup, axis)
    if type(lookup) ~= "table" then return nil, "lookup-axis-missing:" .. axis end
    local added = 0
    local names = sorted_names(entries)
    for i = 1, #names do
        local name = names[i]
        local existing = rawget(lookup, name)
        if existing == nil then
            local id = #lookup + 1
            lookup[id], lookup[name] = name, id
            added = added + 1
        elseif not valid_lookup_row(lookup, name) then
            return nil, "lookup-mismatch:" .. axis .. ":" .. name
        end
    end
    return added
end

function M.reserve_lookups(network_lookup)
    local power_added, power_err = reserve_axis(
        network_lookup, "deus_power_up_templates", POWER_UPS)
    if power_added == nil then return nil, power_err end
    local buff_added, buff_err = reserve_axis(network_lookup, "buff_templates", BUFFS)
    if buff_added == nil then return nil, buff_err end
    return { power_up = power_added, buff = buff_added }
end

-- ---------------------------------------------------------------------------
-- Finalization: readiness, identity, integrity
-- ---------------------------------------------------------------------------
-- Every cataloged name must resolve on all the tables the grant and apply paths
-- read, not just the lookup: a boon present in the pool but missing from
-- BuffTemplates crashes on first apply (buff_extension.lua:177, the dual-table
-- registration trap).
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
    for name, spec in pairs(POWER_UPS) do
        if not valid_lookup_row(power_lookup, name) then
            return false, "power-lookup-mismatch:" .. name
        end
        if type(templates) ~= "table" or type(templates[name]) ~= "table" then
            return false, "power-template-missing:" .. name
        end
        if type(powers) ~= "table" or type(powers[spec.rarity]) ~= "table"
                or type(powers[spec.rarity][name]) ~= "table" then
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

-- The string the beacon puts on the wire. Both axes are fingerprinted through
-- the shared canonical builder (name + exact bidirectional id, length-prefixed),
-- then folded to a short fixed-width token because the transport caps a wire
-- field at 64 chars with a restricted alphabet.
function M.build_identity(Catalog, network_lookup)
    if type(Catalog) ~= "table" or type(Catalog.build_identity) ~= "function" then
        return nil, "wire-catalog-library-missing"
    end
    local power_identity_entries = {}
    for name in pairs(POWER_UPS) do power_identity_entries[name] = true end
    local power, power_err = Catalog.build_identity(
        "ct.deus_power_up_templates", power_identity_entries,
        network_lookup and network_lookup.deus_power_up_templates)
    if not power then return nil, power_err end
    local buff, buff_err = Catalog.build_identity(
        "ct.buff_templates", BUFFS, network_lookup and network_lookup.buff_templates)
    if not buff then return nil, buff_err end
    local canonical = "ct-wire-v1|power=" .. power .. "|buff=" .. buff
    local h1 = feed_hash(104729, 131, 2147483647, canonical)
    local h2 = feed_hash(130363, 257, 2147483629, canonical)
    return string.format("ct-wire-v1:%d:%08x:%08x", M.WIRE_ROW_COUNT, h1, h2)
end

-- Capture the exact lookup objects and bidirectional ids once after catalog
-- finalization. `integrity` scans this fixed data without allocating on the
-- success path, so the wire-safe predicate can call it per grant without
-- rebuilding hashes or maps.
function M.capture_integrity(network_lookup)
    if type(network_lookup) ~= "table" then return nil, "network-lookup-missing" end
    local snapshot = { network_lookup = network_lookup, rows = {} }
    local axes = {
        { name = "deus_power_up_templates", entries = POWER_UPS },
        { name = "buff_templates", entries = BUFFS },
    }
    for axis_index = 1, #axes do
        local axis = axes[axis_index]
        local lookup = rawget(network_lookup, axis.name)
        if type(lookup) ~= "table" then
            return nil, "lookup-axis-missing:" .. axis.name
        end
        local names = sorted_names(axis.entries)
        for i = 1, #names do
            local name = names[i]
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

-- Cheap per-call re-proof that the catalog the peers verified is still the
-- catalog this process holds. Catches a late third-party rewrite of either axis
-- (or a swapped lookup table) that would silently invalidate the shared
-- identity without any peer transition to notice it.
function M.integrity(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.network_lookup) ~= "table"
            or type(snapshot.rows) ~= "table"
            or #snapshot.rows ~= M.WIRE_ROW_COUNT then
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

-- ---------------------------------------------------------------------------
-- Strip filters
-- ---------------------------------------------------------------------------
-- Used by the parity-loss strip. Order and identity of every surviving row are
-- preserved: vanilla and third-party entries must come out byte-identical.
function M.filter_power_ups(values)
    local filtered, removed = {}, 0
    if type(values) ~= "table" then return filtered, removed end
    for i = 1, #values do
        local value = values[i]
        if type(value) == "table" and M.is_power_up(value.name) then
            removed = removed + 1
        else
            filtered[#filtered + 1] = value
        end
    end
    return filtered, removed
end

function M.filter_power_up_names(values)
    local filtered, removed = {}, 0
    if type(values) ~= "table" then return filtered, removed end
    for i = 1, #values do
        local value = values[i]
        if M.is_power_up(value) then removed = removed + 1
        else filtered[#filtered + 1] = value end
    end
    return filtered, removed
end

function M.filter_persistent_buffs(values)
    local filtered, removed = {}, 0
    if type(values) ~= "table" then return filtered, removed end
    for i = 1, #values do
        local value = values[i]
        if M.is_buff(value) then removed = removed + 1
        else filtered[#filtered + 1] = value end
    end
    return filtered, removed
end

-- ---------------------------------------------------------------------------
-- Mod Tweaker gate
-- ---------------------------------------------------------------------------
function M.runtime_gate_setting_ids()
    local out = {}
    for i = 1, #M.GATED_SETTING_IDS do out[i] = M.GATED_SETTING_IDS[i] end
    return out
end

-- Build the Mod Tweaker gate spec. Copies the id list so a later mutation of the
-- caller's table cannot retarget a live gate, and rejects a malformed list
-- outright rather than registering a partial gate that greys the wrong rows.
--
-- ARITY NOTE: ct takes the id list explicitly (mod_id, setting_ids, evaluate),
-- matching crt. wt's copy takes (mod_id, evaluate) and sources the list from its
-- own module. The divergence is deliberate and per-mod: the explicit list is
-- what lets ct's caller and its offline tests feed adversarial lists (duplicate,
-- empty, non-string) through the SAME validator the shipped call uses.
function M.runtime_gate_spec(mod_id, setting_ids, evaluate)
    if setting_ids == nil then setting_ids = M.runtime_gate_setting_ids() end
    if type(mod_id) ~= "string" or mod_id == ""
            or type(setting_ids) ~= "table" or type(evaluate) ~= "function" then
        return nil
    end
    local copied, seen = {}, {}
    for i = 1, #setting_ids do
        local setting_id = setting_ids[i]
        if type(setting_id) ~= "string" or setting_id == "" or seen[setting_id] then
            return nil
        end
        seen[setting_id] = true
        copied[#copied + 1] = setting_id
    end
    if #copied == 0 then return nil end
    return { mod_id = mod_id, setting_ids = copied, evaluate = evaluate }
end

-- Optional bridge. GUT is not a dependency: when it is absent this returns false
-- and the runtime gate above continues to carry the whole safety burden. Both
-- the dev and stable Mod Tweaker ids are probed because a tester may run either.
function M.try_register_runtime_gate(get_mod_fn, gate_id, spec)
    if type(get_mod_fn) ~= "function" or type(gate_id) ~= "string"
            or gate_id == "" or type(spec) ~= "table" then
        return false, "runtime-gate-arguments-invalid"
    end
    for _, gut_id in ipairs({ "gut_dev", "gut" }) do
        local ok, gut = pcall(get_mod_fn, gut_id)
        local tweaker = ok and type(gut) == "table" and gut.mod_tweaker or nil
        if type(tweaker) == "table"
                and type(tweaker.register_runtime_gate) == "function" then
            local ok_register, registered = pcall(
                tweaker.register_runtime_gate, tweaker, gate_id, spec)
            if ok_register and registered == true then return true end
            -- Optional dev GUI damage must not prevent the stable GUI alias from
            -- owning presentation. Gameplay safety never depends on either.
        end
    end
    return false, "mod-tweaker-unavailable"
end

return M
