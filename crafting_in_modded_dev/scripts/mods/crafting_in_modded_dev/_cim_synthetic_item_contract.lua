-- _cim_synthetic_item_contract.lua -- canonical CIM-owned item policy.
--
-- A crafted mod weapon is one identity shared by every CIM surface. Provider
-- mods own ItemMasterList definitions; CIM owns acquired backend instances and
-- their persistence. This engine-free module normalizes that boundary once,
-- validates provider rows before a UI consumes them, builds the one mirror
-- payload shape, and applies vanilla-compatible salvage safety rules.

local M = {}

M.SCHEMA_VERSION = 1
M.OWNER = "cim"
M.CWV_SEED_IDENTITY_SCHEMA = 2
M.CWV_SEED_IDENTITY_OWNER = "character_weapon_variants"
M.CWV_SEED_IDENTITY_CAPABILITY = "cwv.blacksmith-seed.identity.v2"
M.MIRROR_OWNERSHIP_SCHEMA = 2
M.MIRROR_OWNERSHIP_CAPABILITY = "cim.mirror-item.ownership.v2"

-- ============================================================
-- issues 628/682/793: the REGISTERED provider gate
-- ============================================================
-- One validator boundary for every acquisition enumerator and restorer.
-- Independent ItemMasterList walks re-created the #793 bypass (the Athanor
-- list offered `woc_blightreaper`, an immutable WOC relic, then the craft
-- died at mirror injection with an unclassifiable `reason=nil` - issue 682's
-- confirmed boundary). Every enumerator routes rows through `gate_item` and
-- every record boundary routes through `gate_record`; both self-register the
-- surface so `unrouted_surfaces()`/`report_unrouted()` can name any walk that
-- still bypasses the schema. Install sites additionally call
-- `register_enumerator` at load so the census is deterministic at boot.
M.PROVIDER_GATE_SURFACES = {
    "athanor_list",     -- HeroWindowWeaveForgeWeapons._setup_weapon_list walk (crafting_in_modded_dev.lua)
    "blacksmith_list",  -- standard-forge acquisition template catalog (_cim_template_catalog via standard_forge.lua)
    "mirror_restore",   -- _forge_load saved-record normalize + legacy MIL re-inject (crafting_in_modded_dev.lua)
    "mirror_injection", -- backend-mirror add_item boundaries: Athanor/standard-forge/import crafts + registration
    "salvage",          -- BackendInterfaceCommon.filter_items salvage adapter (_cim_inventory_filter.lua)
}

-- `modded_rarities.lua` has no provider-item enumerator. Its Chaos Wastes hook
-- only removes custom rarity names from a vanilla pool-excludes map before
-- vanilla reads it; it never walks, creates, or converts a CIM/provider item.
M.NON_ENUMERATOR_BOUNDARIES = {
    cw_conversion = "rarity-exclude-scrub-only",
}

local _routed_surfaces = {}

function M.register_enumerator(surface)
    if type(surface) ~= "string" or surface == "" then return false end
    _routed_surfaces[surface] = true
    return true
end

-- Variadic install-time registration so an entry can declare its routed
-- surfaces in one line (the entry file is under a decomposition ceiling).
function M.register_enumerators(...)
    for i = 1, select("#", ...) do
        M.register_enumerator((select(i, ...)))
    end
end

function M.is_surface_routed(surface)
    return _routed_surfaces[surface] == true
end

function M.unrouted_surfaces()
    local missing = {}
    for i = 1, #M.PROVIDER_GATE_SURFACES do
        local surface = M.PROVIDER_GATE_SURFACES[i]
        if not _routed_surfaces[surface] then missing[#missing + 1] = surface end
    end
    return missing
end

-- Capped self-report (issue 628 scope 3): one line naming every expected
-- surface that is not routed through the gate. `printer` is injected
-- (engine printf at runtime; a capture in tests) so the module stays
-- engine-free. Emits at most `cap` lines per session (default 3), nothing
-- when every expected surface is routed.
local _unrouted_report_emits = 0

function M.report_unrouted(printer, cap)
    if type(printer) ~= "function" then return false end
    cap = tonumber(cap) or 3
    if _unrouted_report_emits >= cap then return false end
    local missing = M.unrouted_surfaces()
    if #missing == 0 then return false end
    _unrouted_report_emits = _unrouted_report_emits + 1
    local total = #M.PROVIDER_GATE_SURFACES
    printer(string.format("[cim:628] provider gate unrouted walks=%s routed=%d/%d",
        table.concat(missing, ","), total - #missing, total))
    return true
end

local SALVAGE_SLOTS = {
    melee = true,
    ranged = true,
    ring = true,
    necklace = true,
    trinket = true,
}

local UNSALVAGEABLE_RARITIES = {
    default = true,
    promo = true,
    magic = true,
}

local function copy_map(value)
    local result = {}
    if type(value) == "table" then
        for key, child in pairs(value) do result[key] = child end
    end
    return result
end

local function copy_array(value)
    local result = {}
    if type(value) == "table" then
        for i = 1, #value do result[i] = value[i] end
    end
    return result
end

local function nonempty_array(value)
    return type(value) == "table" and #value > 0
end

function M.provider_for(item_key, master)
    if type(master) == "table" then
        if master.cwv_variant == true or master.cwv_definition == true
                or type(master.cwv_key) == "string" then
            return "cwv"
        end
        if master.woc_variant == true then return "woc" end
    end
    if type(item_key) == "string" then
        if item_key:sub(1, 4) == "cwv_" then return "cwv" end
        if item_key:sub(1, 4) == "woc_" then return "woc" end
    end
    return "vanilla"
end

function M.is_immutable_relic(item)
    if type(item) ~= "table" then return false end
    if item.woc_unique_relic == true then return true end
    if type(item.data) == "table" and item.data.woc_unique_relic == true then return true end
    local custom = item.CustomData
    return type(custom) == "table"
        and (custom.woc_unique_relic == true or custom.woc_unique_relic == "true")
end

-- WOC owns trophy acquisition and guarantees exactly one canonical backend
-- instance.  Classify that ownership from the stable provider identity as well
-- as the live marker: CIM restores its save before WOC necessarily registers
-- ItemMasterList, so a stale `woc_*` record must remain rejectable even when
-- `master` is not available yet (issue 822).
function M.is_immutable_relic_identity(item_key, item, backend_id)
    if M.is_immutable_relic(item) then return true end
    if M.provider_for(item_key, item) == "woc" then return true end
    return type(backend_id) == "string" and backend_id:sub(1, 4) == "woc_"
end

-- Returns true for ordinary vanilla rows (they remain vanilla-owned), or for a
-- complete provider row. A malformed mod-provider definition returns false and
-- a bounded problem list so acquisition selectors can reject it before draw.
function M.validate_provider(item_key, master)
    local provider = M.provider_for(item_key, master)
    if provider == "vanilla" then return true, {}, provider end

    -- WOC trophy weapons are deterministic one-per-account local relics.  The
    -- provider marker is the sole cross-mod boundary: no CIM acquisition path
    -- may turn one into a second crafted/editable instance.
    if M.is_immutable_relic_identity(item_key, master) then
        return false, { "immutable_relic" }, provider
    end

    local problems = {}
    if type(item_key) ~= "string" or item_key == "" then
        problems[#problems + 1] = "item_key"
    end
    if type(master) ~= "table" then
        problems[#problems + 1] = "master"
        return false, problems, provider
    end
    if not SALVAGE_SLOTS[master.slot_type] then
        problems[#problems + 1] = "slot_type"
    end
    if not nonempty_array(master.can_wield) then
        problems[#problems + 1] = "can_wield"
    end
    if type(master.template) ~= "string" or master.template == "" then
        problems[#problems + 1] = "template"
    end
    if type(master.item_type) ~= "string" or master.item_type == "" then
        problems[#problems + 1] = "item_type"
    end
    if type(master.inventory_icon) ~= "string" or master.inventory_icon == "" then
        problems[#problems + 1] = "inventory_icon"
    end

    return #problems == 0, problems, provider
end

-- Forward-declared so normalization and every downstream consumer share the
-- same identity ladder. The implementation is assigned below after the
-- provider/record helpers, but module callers cannot run until dofile returns.
local _canonical_item_key

function M.normalize_record(backend_id, input, master)
    if type(backend_id) ~= "string" or backend_id == "" then
        return nil, "backend_id"
    end
    if type(input) ~= "table" then return nil, "record" end

    local item_key = _canonical_item_key(input, backend_id)
    if type(item_key) ~= "string" or item_key == "" then
        return nil, "item_key"
    end

    if M.is_immutable_relic_identity(item_key, master, backend_id) then
        return nil, "provider:immutable_relic"
    end

    if master ~= nil then
        local ok, problems = M.validate_provider(item_key, master)
        if not ok then return nil, "provider:" .. table.concat(problems, ",") end
    end

    local rarity = input.rarity
    if rarity == nil or rarity == "promo" then rarity = "modded" end

    local traits = input.traits
    if type(traits) ~= "table" then
        traits = input.trait and { input.trait } or {}
    end

    return {
        schema_version = M.SCHEMA_VERSION,
        owner = M.OWNER,
        backend_id = backend_id,
        item_key = item_key,
        provider = M.provider_for(item_key, master),
        slot_type = type(master) == "table" and master.slot_type or input.slot_type,
        properties = copy_map(input.properties),
        trait = input.trait,
        traits = copy_array(traits),
        skin = input.skin,
        power_level = tonumber(input.power_level) or 300,
        rarity = rarity,
        via_mirror = input.via_mirror ~= false,
        rerolled_props_indices = copy_array(input.rerolled_props_indices),
        rerolled_trait_indices = copy_array(input.rerolled_trait_indices),
        custom_glow = input.custom_glow,
        -- #1001: durable exact-instance favorite bit. Only `true` is carried
        -- (false and nil both mean not-favorite), so foreign inputs that never
        -- set it normalize to nil and round-trips cannot invent a mark.
        favorite = input.favorite == true or nil,
    }
end

-- Enumerator-row boundary of the registered gate (issues 628/793). Same
-- return contract as `validate_provider` - `(ok, problems_array, provider)` -
-- so existing catalog report plumbing consumes it unchanged. Self-registers
-- the surface as routed.
function M.gate_item(surface, item_key, master)
    M.register_enumerator(surface)
    return M.validate_provider(item_key, master)
end

-- One-call form for engine enumerator walks: gate the row and, on rejection,
-- append `{ key, problems }` to the caller's collection for the capped log.
-- Returns false ONLY on an explicit provider rejection.
function M.gate_enumerated_row(surface, item_key, master, rejected)
    local ok, problems = M.gate_item(surface, item_key, master)
    if ok == false then
        if type(rejected) == "table" then
            rejected[#rejected + 1] = { key = tostring(item_key), problems = problems or {} }
        end
        return false
    end
    return true
end

-- Capped, sorted rejection log for one enumerator surface, then the
-- unrouted-walk self-report (issue 628 scope 3). `printer` is injected
-- (engine printf at runtime) so the module stays engine-free.
function M.log_gate_rejections(printer, surface, rejected, cap)
    if type(printer) ~= "function" or type(rejected) ~= "table" then return end
    table.sort(rejected, function(a, b) return a.key < b.key end)
    cap = tonumber(cap) or 8
    local limit = #rejected < cap and #rejected or cap
    for i = 1, limit do
        printer(string.format("[cim:628] provider rejected before UI surface=%s key=%s missing=%s",
            tostring(surface), rejected[i].key, table.concat(rejected[i].problems, ",")))
    end
    if #rejected > limit then
        printer(string.format("[cim:628] provider_rejected_more surface=%s count=%d",
            tostring(surface), #rejected - limit))
    end
    M.report_unrouted(printer)
end

-- Record boundary of the registered gate (issue 682). Wraps
-- `normalize_record` and guarantees a NON-NIL string reason on rejection:
-- the confirmed 682 failure logged `reason=nil` because call sites collapsed
-- the multi-return through `contract and contract.normalize_record(...)`
-- (Lua's and/or truncates to one value) - an unclassifiable rejection.
function M.gate_record(surface, backend_id, input, master)
    M.register_enumerator(surface)
    local record, reason = M.normalize_record(backend_id, input, master)
    if record then return record, nil end
    return nil, reason or "unclassified"
end

function M.build_mirror_payload(record, master, json_encode)
    if type(record) ~= "table" then return nil, "record" end
    local normalized, err = M.normalize_record(record.backend_id, record, master)
    if not normalized then return nil, err end

    local custom_data = {
        power_level = tostring(normalized.power_level),
        rarity = normalized.rarity,
        -- #484: ItemId is exact when CIM creates the mirror row, but CWV's
        -- provider clone deliberately keeps the inherited vanilla `.key` and
        -- `.name`.  Some backend/menu rebuilds therefore hand consumers only
        -- the base es_handgun shape plus this CustomData table.  Keep the exact
        -- acquisition identity in the payload instead of asking every surface
        -- to infer it from a backend-id naming convention.
        cim_acquisition_key = normalized.item_key,
        cim_provider = normalized.provider,
    }
    if normalized.provider == "cwv" then
        custom_data.cwv_key = normalized.item_key
    end
    if type(json_encode) == "function" then
        custom_data.properties = json_encode(normalized.properties)
        custom_data.traits = json_encode(normalized.traits)
    end
    if normalized.skin then custom_data.skin = normalized.skin end

    normalized._mirror_master = master
    return {
        ItemId = normalized.item_key,
        ItemInstanceId = normalized.backend_id,
        CustomData = custom_data,
    }, nil, normalized
end

-- issue 628: the ONE canonical identity for a synthetic item, owned here and
-- consumed by every CIM surface (salvage eligibility below AND the standard-forge
-- acquisition selector via `_cim_template_selector.set_canonical_key_resolver`).
-- Before this, the salvage path resolved identity as `ItemId or key or cwv_key`
-- while the craft selector used a cwv_key-first, backend-id-aware resolver. They
-- disagreed for any CWV row presented with its inherited BASE `.key`/`.name`
-- (CWV's `_build_entry` deliberately keeps them the base weapon for vanilla
-- equip/preview fallbacks and stamps the variant only on `.cwv_key`,
-- character_weapon_variants.lua:10318-10330). A variant-keyed salvage record then
-- failed the `item_key` check and the crafted weapon never appeared in Salvage.
-- Resolution priority (highest first):
--   1. `item_key` / `cim_acquisition_key` / `cwv_key` -- the exact craft key on a
--      synthetic selector row, reconstructed wrapper, or its CustomData.
--      Direct, nested-data, and mod-data shapes are equivalent.
--   2. `cwv_<key>_NNN` backend-id band -- legacy CWV blacksmith instances that
--      encoded the variant only in the backend id.
--   3. `ItemId` / `key` / `data.key` -- ordinary vanilla identity.
_canonical_item_key = function(item, backend_id_override)
    if type(item) ~= "table" then return nil end
    local data = type(item.data) == "table" and item.data or nil
    local custom = type(item.CustomData) == "table" and item.CustomData
        or (data and type(data.CustomData) == "table" and data.CustomData)
    local mod_data = type(item.mod_data) == "table" and item.mod_data
        or (data and type(data.mod_data) == "table" and data.mod_data)
    local exact = item.item_key
        or item.cim_acquisition_key
        or (data and data.cim_acquisition_key)
        or (custom and custom.cim_acquisition_key)
        or item.cwv_key
        or (data and data.cwv_key)
        or (mod_data and mod_data.cwv_key)
        or (custom and custom.cwv_key)
    if type(exact) == "string" and exact ~= "" then
        return exact
    end
    local backend_id = item.backend_id or item.ItemInstanceId or backend_id_override
    if type(backend_id) == "string" then
        local cwv_key = backend_id:match("^(cwv_.-)_%d%d%d$")
        if cwv_key then return cwv_key end
    end
    local key = item.ItemId or item.key or (data and data.key)
    return type(key) == "string" and key or nil
end

M.canonical_item_key = _canonical_item_key

-- #1141: Temper-Craft consumes a provider-owned Blacksmith selector, not an
-- arbitrary cwv-shaped instance or the vanilla donor identity retained by the
-- provider clone. Any CWV evidence moves resolution onto this stricter path.
-- Ordinary vanilla, Pusfume, WOC, and unknown external rows keep the existing -- pusfume-compat-reviewed: non-CWV rows stay on the unchanged canonical path.
-- canonical ladder and never depend on CWV being installed.
local function _row_has_cwv_evidence(row)
    if type(row) ~= "table" then return false end
    if row.cwv_variant == true or row.cwv_definition == true then return true end
    for _, field in ipairs({
        "item_key", "cim_acquisition_key", "cwv_key", "ItemId", "key",
    }) do
        local value = row[field]
        if type(value) == "string" and value:sub(1, 4) == "cwv_" then
            return true
        end
    end
    return false
end

local function _visit_item_rows(item, visit)
    if type(item) ~= "table" or type(visit) ~= "function" then return end
    local data = type(item.data) == "table" and item.data or nil
    local top_custom = type(item.CustomData) == "table" and item.CustomData or nil
    local data_custom = data and type(data.CustomData) == "table"
        and data.CustomData or nil
    local top_mod = type(item.mod_data) == "table" and item.mod_data or nil
    local data_mod = data and type(data.mod_data) == "table" and data.mod_data or nil
    visit(item, "item")
    if data then visit(data, "data") end
    if top_custom then visit(top_custom, "CustomData") end
    if data_custom then visit(data_custom, "data.CustomData") end
    if top_mod then visit(top_mod, "mod_data") end
    if data_mod then visit(data_mod, "data.mod_data") end
    if top_mod and type(top_mod.CustomData) == "table" then
        visit(top_mod.CustomData, "mod_data.CustomData")
    end
    if data_mod and type(data_mod.CustomData) == "table" then
        visit(data_mod.CustomData, "data.mod_data.CustomData")
    end
end

local function _item_has_cwv_evidence(item)
    local found = false
    _visit_item_rows(item, function(row)
        if _row_has_cwv_evidence(row) then found = true end
    end)
    return found
end

function M.temper_source_requires_cwv_provider(selected_item, live_item,
        backend_id)
    return type(backend_id) == "string" and backend_id:sub(1, 4) == "cwv_"
        or _item_has_cwv_evidence(selected_item)
        or _item_has_cwv_evidence(live_item)
end

local function _collect_semantic_cwv_stamps(item, stamps)
    _visit_item_rows(item, function(row)
        for _, field in ipairs({
            "item_key", "cim_acquisition_key", "cwv_key",
        }) do
            local value = row[field]
            if type(value) == "string" and value:sub(1, 4) == "cwv_" then
                stamps[value] = true
            end
        end
    end)
end

local function _cwv_observation_conflict(item, backend_id, item_key,
        donor_key, require_backend)
    local backend_seen, stamp_seen, conflict = false, false, nil
    _visit_item_rows(item, function(row)
        if conflict then return end
        for _, field in ipairs({ "backend_id", "ItemInstanceId" }) do
            local value = row[field]
            if value ~= nil then
                backend_seen = true
                if type(value) ~= "string" or value ~= backend_id then
                    conflict = "backend_id"
                    return
                end
            end
        end
        for _, field in ipairs({ "ItemId", "key" }) do
            local value = row[field]
            if value ~= nil and (type(value) ~= "string"
                    or value ~= item_key and value ~= donor_key) then
                conflict = "semantic_key"
                return
            end
        end
        for _, field in ipairs({
            "item_key", "cim_acquisition_key", "cwv_key",
        }) do
            local value = row[field]
            if value ~= nil then
                stamp_seen = true
                if type(value) ~= "string" or value ~= item_key then
                    conflict = "semantic_stamp"
                    return
                end
            end
        end
    end)
    if conflict then return conflict, stamp_seen end
    if require_backend and not backend_seen then
        return "backend_id_missing", stamp_seen
    end
    return nil, stamp_seen
end

function M.resolve_temper_craft_source(selected_item, live_item, backend_id,
        provider)
    if type(selected_item) ~= "table" and type(live_item) ~= "table" then
        return nil, "source_item"
    end
    local source_item = type(live_item) == "table" and live_item or selected_item
    local ordinary_key = type(live_item) == "table"
        and _canonical_item_key(live_item, backend_id) or nil
    ordinary_key = ordinary_key or _canonical_item_key(selected_item, backend_id)
    local has_cwv_evidence = M.temper_source_requires_cwv_provider(
        selected_item, live_item, backend_id)
    if not has_cwv_evidence then
        if type(ordinary_key) ~= "string" or ordinary_key == "" then
            return nil, "item_key"
        end
        if M.is_immutable_relic_identity(
                ordinary_key, source_item, backend_id) then
            return nil, "immutable_relic"
        end
        return {
            owner = "source",
            item_key = ordinary_key,
            backend_id = backend_id,
            fingerprint = "ordinary|" .. tostring(backend_id)
                .. "|" .. ordinary_key,
        }, nil
    end

    if type(provider) ~= "table"
            or provider.schema ~= M.CWV_SEED_IDENTITY_SCHEMA
            or provider.owner ~= M.CWV_SEED_IDENTITY_OWNER
            or provider.capability ~= M.CWV_SEED_IDENTITY_CAPABILITY
            or type(provider.resolve) ~= "function" then
        return nil, "cwv_provider_unavailable"
    end
    if type(live_item) ~= "table" then
        return nil, "cwv_live_item_unavailable"
    end

    local called, proof, reason = pcall(
        provider.resolve, provider, backend_id)
    if not called then return nil, "cwv_provider_exception" end
    if type(proof) ~= "table" then
        return nil, "cwv_provider:" .. tostring(reason or "rejected")
    end
    local item_key = proof.item_key
    local donor_key = proof.donor_key
    if type(item_key) ~= "string" or item_key == ""
            or type(donor_key) ~= "string" or donor_key == "" then
        return nil, "cwv_provider_proof_mismatch"
    end
    local expected_fingerprint = "cwv-blacksmith-seed-v2|"
        .. tostring(backend_id) .. "|" .. item_key .. "|" .. donor_key
    if type(proof) ~= "table"
            or proof.schema ~= M.CWV_SEED_IDENTITY_SCHEMA
            or proof.owner ~= M.CWV_SEED_IDENTITY_OWNER
            or proof.capability ~= M.CWV_SEED_IDENTITY_CAPABILITY
            or proof.backend_id ~= backend_id
            or proof.item_key ~= item_key
            or proof.donor_key ~= donor_key
            or proof.fingerprint ~= expected_fingerprint then
        return nil, "cwv_provider_proof_mismatch"
    end

    local stamps = {}
    _collect_semantic_cwv_stamps(selected_item, stamps)
    _collect_semantic_cwv_stamps(live_item, stamps)
    for stamp in pairs(stamps) do
        if stamp ~= item_key then return nil, "cwv_source_stamp_conflict" end
    end
    local selected_conflict = _cwv_observation_conflict(
        selected_item, backend_id, item_key, donor_key, false)
    if selected_conflict then
        return nil, "cwv_selected_" .. selected_conflict .. "_conflict"
    end
    local live_conflict, live_stamp = _cwv_observation_conflict(
        live_item, backend_id, item_key, donor_key, true)
    if live_conflict then
        return nil, "cwv_live_" .. live_conflict .. "_conflict"
    end
    if not live_stamp then return nil, "cwv_live_stamp_missing" end
    return {
        owner = M.CWV_SEED_IDENTITY_OWNER,
        item_key = item_key,
        backend_id = backend_id,
        fingerprint = proof.fingerprint,
        proof = proof,
    }, nil
end

-- MoreItemsLibrary backendifies the exact entry CIM supplies, but deliberately
-- keeps a CWV clone's vanilla donor key in ItemId/key.  Retain that entry by
-- object identity: copied stamps or another row with the same backend id cannot
-- impersonate a legacy craft, while saved legacy records still survive because
-- `_cim_mil_entry_builder` reissues them on every backend bootstrap.
local _issued_legacy_mil_entries = setmetatable({}, { __mode = "k" })

local LEGACY_DEFINITION_FIELDS = {
    "key", "name", "slot_type", "template", "item_type", "inventory_icon",
    "display_name", "description", "right_hand_unit", "left_hand_unit",
    "cwv_key", "cwv_variant", "cwv_definition",
}

local function _legacy_definition_matches(entry, master)
    for i = 1, #LEGACY_DEFINITION_FIELDS do
        local field = LEGACY_DEFINITION_FIELDS[i]
        if entry[field] ~= master[field] then return false end
    end
    local left, right = entry.can_wield, master.can_wield
    if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then
        return false
    end
    for i = 1, #right do
        if left[i] ~= right[i] then return false end
    end
    return true
end

function M.register_legacy_mil_entry(record, master, entry)
    if type(record) ~= "table" or record.owner ~= M.OWNER
            or record.schema_version ~= M.SCHEMA_VERSION
            or record.via_mirror ~= false
            or type(master) ~= "table" or type(entry) ~= "table"
            or entry == master then
        return false, "legacy_issuance_contract"
    end
    local provider_ok = M.validate_provider(record.item_key, master)
    if not provider_ok
            or record.provider ~= M.provider_for(record.item_key, master)
            or not _legacy_definition_matches(entry, master) then
        return false, "legacy_issuance_provider"
    end
    local mod_data = type(entry.mod_data) == "table" and entry.mod_data or nil
    local custom = mod_data and type(mod_data.CustomData) == "table"
        and mod_data.CustomData or nil
    if entry.cim_acquisition_key ~= record.item_key
            or not mod_data or not custom
            or mod_data.backend_id ~= record.backend_id
            or mod_data.ItemInstanceId ~= record.backend_id
            or mod_data.cim_acquisition_key ~= record.item_key
            or custom.cim_acquisition_key ~= record.item_key
            or custom.cim_provider ~= record.provider then
        return false, "legacy_issuance_identity"
    end
    if record.provider == "cwv" then
        if entry.cwv_key ~= record.item_key
                or mod_data.cwv_key ~= record.item_key
                or custom.cwv_key ~= record.item_key then
            return false, "legacy_issuance_cwv"
        end
    elseif entry.cwv_key ~= nil or mod_data.cwv_key ~= nil
            or custom.cwv_key ~= nil then
        return false, "legacy_issuance_foreign_cwv"
    end
    local native_key = entry.key or entry.name
    if type(native_key) ~= "string" or native_key == "" then
        return false, "legacy_issuance_native_identity"
    end
    _issued_legacy_mil_entries[entry] = {
        backend_id = record.backend_id,
        item_key = record.item_key,
        provider = record.provider,
        native_key = native_key,
        master = master,
    }
    return true, nil
end

local function _validate_legacy_mil_authority(authority, data, backend_id,
        record, master)
    local issued = type(data) == "table" and _issued_legacy_mil_entries[data]
        or nil
    if type(issued) ~= "table"
            or issued.backend_id ~= backend_id
            or issued.item_key ~= record.item_key
            or issued.provider ~= record.provider
            or issued.master ~= master then
        return false, "owned_legacy_issuance"
    end
    if authority.IsModItem ~= true
            or authority.CreatedBy ~= "crafting_in_modded_dev"
            or authority.ItemId ~= issued.native_key
            or authority.key ~= issued.native_key then
        return false, "owned_native_identity"
    end
    return true, nil
end

-- A non-default CWV-looking row is not automatically an editable instance.
-- Apply authority comes from CIM's exact persisted record plus the live row
-- reconstructed from that record. Mirror rows use their private injection
-- marker; legacy MIL rows use the private exact-entry issuance above.
function M.validate_temper_owned_instance(item, backend_id, record, master,
        raw_item)
    if type(item) ~= "table" or type(record) ~= "table" then
        return false, "owned_item"
    end
    local authority = raw_item or item
    local valid, reason = M.validate_instance(authority, record)
    if not valid then return false, "owned_" .. tostring(reason) end
    local data = type(authority.data) == "table" and authority.data or nil
    if type(master) ~= "table" then return false, "owned_master_identity" end
    if record.via_mirror ~= false then
        if data ~= master then return false, "owned_master_identity" end
        -- PlayFabMirrorBase._update_data hydrates these exact fields from
        -- ItemId. Stamps cannot authorize a differently hydrated native row.
        if authority.key ~= record.item_key
                or authority.ItemId ~= record.item_key then
            return false, "owned_native_identity"
        end
    else
        local legacy_ok, legacy_reason = _validate_legacy_mil_authority(
            authority, data, backend_id, record, master)
        if not legacy_ok then return false, legacy_reason end
    end
    local provider_ok = M.validate_provider(record.item_key, master)
    if not provider_ok
            or record.provider ~= M.provider_for(record.item_key, master) then
        return false, "owned_provider"
    end
    local conflict
    local function inspect(observed)
        _visit_item_rows(observed, function(row)
            if conflict then return end
            for _, field in ipairs({ "backend_id", "ItemInstanceId" }) do
                local value = row[field]
                if value ~= nil and (type(value) ~= "string"
                        or value ~= backend_id) then
                    conflict = "backend_id"
                    return
                end
            end
            for _, field in ipairs({
                "item_key", "cim_acquisition_key", "cwv_key",
            }) do
                local value = row[field]
                if value ~= nil and (type(value) ~= "string"
                        or value ~= record.item_key) then
                    conflict = "semantic_stamp"
                    return
                end
            end
            if row.cim_provider ~= nil
                    and row.cim_provider ~= record.provider then
                conflict = "provider_stamp"
            end
        end)
    end
    inspect(authority)
    if item ~= authority and not conflict then
        local observed_valid, observed_reason = M.validate_instance(item, record)
        if not observed_valid then
            return false, "owned_ui_" .. tostring(observed_reason)
        end
        local expected_native = record.item_key
        if record.via_mirror == false then
            expected_native = _issued_legacy_mil_entries[data].native_key
        end
        if item.key ~= expected_native
                or item.ItemId ~= nil and item.ItemId ~= expected_native then
            return false, "owned_ui_native_identity"
        end
        inspect(item)
    end
    if conflict then return false, "owned_" .. conflict end
    if record.via_mirror ~= false then
        local custom = type(authority.CustomData) == "table"
            and authority.CustomData or nil
        if not custom
                or custom.cim_injection_owner ~= M.OWNER
                or custom.cim_injection_schema
                    ~= tostring(M.MIRROR_OWNERSHIP_SCHEMA)
                or type(custom.cim_injection_nonce) ~= "string"
                or custom.cim_injection_nonce == ""
                or custom.cim_acquisition_key ~= record.item_key
                or custom.cim_provider ~= record.provider then
            return false, "owned_injection_proof"
        end
        if record.provider == "cwv" then
            if custom.cwv_key ~= record.item_key then
                return false, "owned_cwv_stamp"
            end
        elseif custom.cwv_key ~= nil then
            return false, "owned_foreign_cwv_stamp"
        end
    end
    return true, nil
end

local _issued_mirror_tokens = setmetatable({}, { __mode = "k" })

local function _same_array(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    for key in pairs(left) do
        if type(key) ~= "number" or key < 1 or key > #left
                or key % 1 ~= 0 then
            return false
        end
    end
    return true
end

local function _same_map(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for key, value in pairs(left) do
        if right[key] ~= value then return false end
    end
    for key, value in pairs(right) do
        if left[key] ~= value then return false end
    end
    return true
end

local function _mirror_expectation(backend_id, item_key, payload, record)
    local custom = type(payload) == "table"
        and type(payload.CustomData) == "table" and payload.CustomData or nil
    if type(record) ~= "table" or not custom
            or record.backend_id ~= backend_id or record.item_key ~= item_key
            or type(record.rarity) ~= "string" or record.rarity == ""
            or type(record.power_level) ~= "number"
            or type(record.traits) ~= "table"
            or type(record.properties) ~= "table"
            or type(record.provider) ~= "string" or record.provider == ""
            or type(record._mirror_master) ~= "table"
            or type(custom.power_level) ~= "string"
            or tonumber(custom.power_level) ~= record.power_level
            or custom.rarity ~= record.rarity
            or type(custom.traits) ~= "string"
            or type(custom.properties) ~= "string"
            or custom.cim_acquisition_key ~= item_key
            or custom.cim_provider ~= record.provider
            or custom.skin ~= record.skin then
        return nil
    end
    if record.provider == "cwv" then
        if custom.cwv_key ~= item_key then return nil end
    elseif custom.cwv_key ~= nil then
        return nil
    end
    return {
        backend_id = backend_id,
        item_key = item_key,
        rarity = record.rarity,
        power_level = record.power_level,
        skin = record.skin,
        traits = copy_array(record.traits),
        properties = copy_map(record.properties),
        provider = record.provider,
        master = record._mirror_master,
        custom_power_level = custom.power_level,
        custom_traits = custom.traits,
        custom_properties = custom.properties,
    }
end

local function _mirror_token_fingerprint(backend_id, item_key, nonce, expected)
    return table.concat({
        "cim-mirror-item-v2", backend_id, item_key, nonce,
        expected.provider, expected.rarity, expected.custom_power_level,
        expected.skin or "<nil>", expected.custom_traits,
        expected.custom_properties,
    }, "|")
end

function M.mirror_ownership_token(backend_id, item_key, nonce, payload, record)
    if type(backend_id) ~= "string" or backend_id == ""
            or type(item_key) ~= "string" or item_key == ""
            or type(nonce) ~= "string" or nonce == ""
            or type(payload) ~= "table" then
        return nil
    end
    local expected = _mirror_expectation(
        backend_id, item_key, payload, record)
    if not expected then return nil end
    local token = {
        schema = M.MIRROR_OWNERSHIP_SCHEMA,
        owner = M.OWNER,
        capability = M.MIRROR_OWNERSHIP_CAPABILITY,
        backend_id = backend_id,
        item_key = item_key,
        nonce = nonce,
        payload = payload,
        fingerprint = _mirror_token_fingerprint(
            backend_id, item_key, nonce, expected),
    }
    _issued_mirror_tokens[token] = {
        payload = payload,
        expected = expected,
    }
    return token
end

function M.validate_mirror_ownership_token(token, backend_id, item_key)
    local issued = type(token) == "table" and _issued_mirror_tokens[token] or nil
    return type(issued) == "table"
        and token.schema == M.MIRROR_OWNERSHIP_SCHEMA
        and token.owner == M.OWNER
        and token.capability == M.MIRROR_OWNERSHIP_CAPABILITY
        and token.backend_id == backend_id
        and token.item_key == item_key
        and type(token.nonce) == "string" and token.nonce ~= ""
        and token.payload == issued.payload
        and token.fingerprint == _mirror_token_fingerprint(
            backend_id, item_key, token.nonce, issued.expected)
end

local function _mirror_row_owned_by_token(row, token)
    local issued = type(token) == "table" and _issued_mirror_tokens[token] or nil
    if type(row) ~= "table" or type(issued) ~= "table"
            or not M.validate_mirror_ownership_token(
                token, token.backend_id, token.item_key)
            or row ~= issued.payload then
        return false
    end
    local custom = type(row.CustomData) == "table" and row.CustomData or nil
    if row.ItemInstanceId ~= token.backend_id
            or row.ItemId ~= token.item_key
            or not custom
            or custom.cim_injection_owner ~= M.OWNER
            or custom.cim_injection_schema ~= tostring(M.MIRROR_OWNERSHIP_SCHEMA)
            or custom.cim_injection_nonce ~= token.nonce then
        return false
    end
    return true
end

local function _mirror_row_matches(row, token)
    if not _mirror_row_owned_by_token(row, token) then return false end
    local issued = _issued_mirror_tokens[token]
    local expected = issued and issued.expected
    if type(expected) ~= "table" then return false end
    local custom = row.CustomData
    if row.backend_id ~= token.backend_id or row.key ~= token.item_key
            or row.data ~= expected.master
            or row.rarity ~= expected.rarity
            or row.power_level ~= expected.power_level
            or row.skin ~= expected.skin
            or not _same_array(row.traits, expected.traits)
            or not _same_map(row.properties, expected.properties)
            or custom.cim_acquisition_key ~= token.item_key
            or custom.cim_provider ~= expected.provider
            or custom.rarity ~= expected.rarity
            or custom.power_level ~= expected.custom_power_level
            or custom.skin ~= expected.skin
            or custom.traits ~= expected.custom_traits
            or custom.properties ~= expected.custom_properties then
        return false
    end
    if expected.provider == "cwv" then
        if custom.cwv_key ~= token.item_key then return false end
    elseif custom.cwv_key ~= nil then
        return false
    end
    local valid = true
    _visit_item_rows(row, function(candidate)
        for _, field in ipairs({
            "item_key", "cim_acquisition_key", "cwv_key",
        }) do
            local stamp = candidate[field]
            if stamp ~= nil and stamp ~= token.item_key then valid = false end
        end
        local provider = candidate.cim_provider
        if provider ~= nil and provider ~= expected.provider then valid = false end
        for _, field in ipairs({ "backend_id", "ItemInstanceId" }) do
            local value = candidate[field]
            if value ~= nil and value ~= token.backend_id then valid = false end
        end
    end)
    return valid
end

-- During the synchronous add/postcondition boundary, exact object identity is
-- the strongest ownership proof available.  If an engine callback damages our
-- marker and then throws, remove that exact object; never remove a replacement.
local function _cleanup_injected_payload(mirror, backend_id, token)
    local issued = type(token) == "table" and _issued_mirror_tokens[token] or nil
    if type(issued) ~= "table" then return false, "ownership_token" end
    local current = rawget(mirror._inventory_items, backend_id)
    if current == nil then
        _issued_mirror_tokens[token] = nil
        return true, nil
    end
    if current ~= issued.payload then return false, "mirror_replaced" end
    local removed, remove_error = pcall(mirror.remove_item, mirror, backend_id)
    local absent = rawget(mirror._inventory_items, backend_id) == nil
    -- A callback that returns normally is not proof that it removed anything.
    -- Contain the exact object we issued after every callback outcome, while
    -- preserving any replacement installed by engine/user code.
    if not absent
            and rawget(mirror._inventory_items, backend_id) == issued.payload then
        rawset(mirror._inventory_items, backend_id, nil)
        absent = true
    end
    if not removed and not absent then return false, tostring(remove_error) end
    if not absent then
        return false, "mirror_remove_postcondition"
    end
    _issued_mirror_tokens[token] = nil
    return true, nil
end

local function _cleanup_owned_mirror_row(mirror, backend_id, token)
    local current = rawget(mirror._inventory_items, backend_id)
    if not _mirror_row_owned_by_token(current, token) then
        return false, "mirror_identity_mismatch"
    end
    local removed, remove_error = pcall(mirror.remove_item, mirror, backend_id)
    local absent = rawget(mirror._inventory_items, backend_id) == nil
    local issued = _issued_mirror_tokens[token]
    -- Treat remove_item as a request, not a postcondition.  A normal-returning
    -- no-op implementation must not strand our exact owned mirror row.
    if not absent and type(issued) == "table"
            and rawget(mirror._inventory_items, backend_id) == issued.payload then
        rawset(mirror._inventory_items, backend_id, nil)
        absent = true
    end
    if not removed and not absent then return false, tostring(remove_error) end
    if not absent then
        return false, "mirror_remove_postcondition"
    end
    _issued_mirror_tokens[token] = nil
    return true, nil
end

function M.inject_mirror_item(mirror, backend_id, payload, nonce_factory, record)
    if type(mirror) ~= "table" or type(mirror.add_item) ~= "function"
            or type(mirror.remove_item) ~= "function"
            or type(mirror._inventory_items) ~= "table" then
        return nil, "mirror_contract_unavailable"
    end
    if type(backend_id) ~= "string" or backend_id == "" then
        return nil, "backend_id"
    end
    local custom = type(payload) == "table"
        and type(payload.CustomData) == "table" and payload.CustomData or nil
    if type(payload) ~= "table" or payload.ItemInstanceId ~= backend_id
            or type(payload.ItemId) ~= "string" or payload.ItemId == ""
            or not custom then
        return nil, "payload_identity"
    end
    if rawget(mirror._inventory_items, backend_id) ~= nil then
        return nil, "backend_id_exists"
    end

    if custom.cim_injection_owner ~= nil
            or custom.cim_injection_schema ~= nil
            or custom.cim_injection_nonce ~= nil then
        return nil, "payload_injection_marker_exists"
    end
    if type(nonce_factory) ~= "function" then
        return nil, "nonce_factory"
    end
    local nonce_ok, nonce = pcall(nonce_factory)
    local token = nonce_ok and M.mirror_ownership_token(
        backend_id, payload.ItemId, nonce, payload, record) or nil
    if not token then return nil, "nonce" end
    custom.cim_injection_owner = M.OWNER
    custom.cim_injection_schema = tostring(M.MIRROR_OWNERSHIP_SCHEMA)
    custom.cim_injection_nonce = nonce
    local added, add_error = pcall(mirror.add_item, mirror, backend_id, payload)
    if not added then
        local cleaned, cleanup_error = _cleanup_injected_payload(
            mirror, backend_id, token)
        local detail = tostring(add_error) .. "|cleanup="
            .. (cleaned and "complete" or tostring(cleanup_error))
        return nil, detail, nil, cleaned
    end
    local matched_call, matched = pcall(_mirror_row_matches,
        rawget(mirror._inventory_items, backend_id), token)
    if not matched_call or not matched then
        local cleaned, cleanup_error = _cleanup_injected_payload(
            mirror, backend_id, token)
        return nil, "mirror_postcondition:"
            .. tostring(matched_call and "mismatch" or matched) .. "|cleanup="
            .. (cleaned and "complete" or tostring(cleanup_error)), nil, cleaned
    end
    local rollback = function()
        return M.rollback_mirror_item(mirror, backend_id, token)
    end
    return true, nil, token, false, rollback
end

function M.rollback_mirror_item(mirror, backend_id, token)
    if type(mirror) ~= "table" or type(mirror.remove_item) ~= "function"
            or type(mirror._inventory_items) ~= "table" then
        return false, "mirror_contract_unavailable"
    end
    if not M.validate_mirror_ownership_token(
            token, backend_id, token and token.item_key) then
        return false, "ownership_token"
    end
    return _cleanup_owned_mirror_row(mirror, backend_id, token)
end

-- Finish the only throwable work that follows a successful mirror add.  If a
-- native refresh partially rebuilds its cache and then throws, remove the exact
-- owned row and force one second dirtify/refresh so that partial cache cannot
-- survive the failed craft.
function M.complete_mirror_injection_refresh(refresh_backend, rollback)
    if type(refresh_backend) ~= "function" or type(rollback) ~= "function" then
        return nil, "post-injection refresh contract unavailable"
    end
    local refresh_called, refresh_result, refresh_error = pcall(refresh_backend)
    if refresh_called and refresh_result == true then return true, nil end
    local initial_error = refresh_called
        and (refresh_error or refresh_result or "refresh_rejected")
        or refresh_result
    local called, removed, rollback_error = pcall(rollback)
    local contained = called and removed == true
    local cleanup_refreshed, cleanup_error = false, "rollback_incomplete"
    if contained then
        local cleanup_called, cleanup_result, cleanup_reason = pcall(refresh_backend)
        cleanup_refreshed = cleanup_called and cleanup_result == true
        cleanup_error = cleanup_called
            and (cleanup_reason or cleanup_result or "refresh_rejected")
            or cleanup_result
    end
    return nil, "post-injection refresh failed: " .. tostring(initial_error)
        .. "|rollback=" .. (contained and "complete" or "failed:"
            .. tostring(called and rollback_error or removed))
        .. "|post-cleanup-refresh=" .. (cleanup_refreshed and "complete"
            or "failed:" .. tostring(cleanup_error))
end

-- One canonical add/cleanup/cache transaction for every modern craft path.
-- `inject_mirror_item` owns exact row identity; this wrapper additionally owns
-- the engine caches that an add callback may partially rebuild before it
-- throws.  A removed row is not contained until those caches refresh too.
function M.inject_and_refresh_mirror_item(mirror, backend_id, payload,
        nonce_factory, record, refresh_backend)
    if type(refresh_backend) ~= "function" then
        return nil, "mirror_refresh_contract_unavailable"
    end
    local added, add_error, ownership_token, cleaned, rollback =
        M.inject_mirror_item(mirror, backend_id, payload, nonce_factory, record)
    if not added then
        local failure = tostring(add_error or "mirror_injection_failed")
        if cleaned == true then
            local called, refreshed, refresh_error = pcall(refresh_backend)
            if not called or refreshed ~= true then
                local reason = called
                    and (refresh_error or refreshed or "refresh_rejected")
                    or refreshed
                failure = failure .. "|post-cleanup-refresh=failed:"
                    .. tostring(reason)
            end
        elseif cleaned == false then
            failure = failure .. "|cleanup=failed"
        end
        return nil, failure
    end

    local rollback_fn = type(rollback) == "function" and rollback or function()
        return M.rollback_mirror_item(mirror, backend_id, ownership_token)
    end
    local refreshed, refresh_error = M.complete_mirror_injection_refresh(
        refresh_backend, rollback_fn)
    if not refreshed then return nil, refresh_error end
    return true, nil, ownership_token, rollback_fn
end

-- The native `can_craft_with` result is an acquisition-selector surface, not
-- an inventory surface.  Keep this classification beside canonical identity
-- so a CWV item cannot be treated as a definition token by one consumer and a
-- crafted instance by another.  Vanilla admits only default-rarity rows here
-- (backend_interface_common.lua `can_craft_with`); CIM's final selector seam
-- uses this same policy as a fail-closed guard against hook/mirror leakage.
local CRAFT_PICKER_SLOTS = {
    melee = true,
    ranged = true,
    ring = true,
    necklace = true,
    trinket = true,
}

local function _item_rarity(item)
    if type(item) ~= "table" then return nil end
    local data = type(item.data) == "table" and item.data or nil
    local custom = type(item.CustomData) == "table" and item.CustomData
        or (data and type(data.CustomData) == "table" and data.CustomData)
    local mod_data = type(item.mod_data) == "table" and item.mod_data
        or (data and type(data.mod_data) == "table" and data.mod_data)
    return item.rarity or (custom and custom.rarity) or (mod_data and mod_data.rarity)
end

function M.craft_picker_role(item)
    if type(item) ~= "table" then return "invalid" end
    local data = type(item.data) == "table" and item.data or nil
    local slot_type = data and data.slot_type or item.slot_type
    if not CRAFT_PICKER_SLOTS[slot_type] then return "other" end
    local rarity = _item_rarity(item)
    if rarity == nil or rarity == "default" then return "selector" end
    return "instance"
end

local function instance_key(item)
    return item and M.canonical_item_key(item)
end

function M.validate_instance(item, record)
    if type(item) ~= "table" or type(record) ~= "table" then
        return false, "not_owned"
    end
    local backend_id = item.backend_id or item.ItemInstanceId
    local item_key = instance_key(item)
    if M.is_immutable_relic_identity(
            item_key or record.item_key, item, backend_id) then
        return false, "immutable_relic"
    end
    if backend_id ~= record.backend_id then return false, "backend_id" end
    if record.owner ~= M.OWNER or record.schema_version ~= M.SCHEMA_VERSION then
        return false, "schema"
    end
    if item_key ~= record.item_key then return false, "item_key" end
    local slot_type = item.data and item.data.slot_type or record.slot_type
    if not SALVAGE_SLOTS[slot_type] then return false, "slot_type" end
    return true
end

-- `state` is deliberately explicit and engine-free. Runtime callers source it
-- from the same vanilla item interface / ItemHelper checks used by
-- BackendInterfaceCommon.can_salvage; offline tests exhaust the truth table.
function M.is_salvage_eligible(item, record, state)
    local valid, reason = M.validate_instance(item, record)
    if not valid then return false, reason end
    state = state or {}
    local rarity = item.rarity or record.rarity
    if UNSALVAGEABLE_RARITIES[rarity] then return false, "rarity" end
    if state.is_equipped then return false, "equipped" end
    if state.is_equipped_by_any_loadout then return false, "loadout" end
    if state.is_favorite then return false, "favorite" end
    return true
end

-- #628: vanilla ItemHelper.is_favorite_backend_id ends
-- `return favorite_item_ids and favorite_item_ids[item_id]` (decompile
-- scripts/helpers/item_helper.lua:453) - it returns NIL for a non-favorited
-- item, never false. The salvage state gate above only yields its fail-closed
-- `is_favorite = true` default to a real boolean, so an uncoerced pass-through
-- rejected EVERY recovered row with verdict=favorite. Runtime accessors route
-- the raw helper verdict through this shared coercion; keeping it here makes
-- the truthiness rule provable in the engine-free suite.
function M.coerce_favorite_verdict(raw)
    return raw and true or false
end

-- Reconsider exact CIM instances that vanilla excluded from its dense result.
-- The source inventory remains a backend-id keyed map, so this function owns
-- the `pairs` boundary and is executable under the engine-free Lua suite.
-- Runtime accessors are read-only and injected; unavailable/raising equip,
-- saved-loadout, or favorite queries fail closed.
function M.recover_salvage_items(items, result, access)
    if type(items) ~= "table" or type(result) ~= "table" then return result end
    access = type(access) == "table" and access or {}

    local seen = {}
    for _, row in ipairs(result) do
        local backend_id = type(row) == "table"
            and (row.backend_id or row.ItemInstanceId) or nil
        if backend_id then
            seen[backend_id] = true
        end
    end

    local function query(fn, ...)
        if type(fn) ~= "function" then return false, nil end
        local ok, value = pcall(fn, ...)
        return ok, value
    end

    for _, item in pairs(items) do
        local backend_id = type(item) == "table"
            and (item.backend_id or item.ItemInstanceId) or nil
        local record_ok, record = query(access.get_record, backend_id)
        if backend_id and record_ok and type(record) == "table" then
            local state = {
                is_equipped = true,
                is_equipped_by_any_loadout = true,
                is_favorite = true,
                backend_dirty = access.backend_dirty == true,
            }

            local careers_ok, careers = query(
                access.get_equipped_careers, backend_id)
            if careers_ok and type(careers) == "table" then
                state.is_equipped = #careers > 0
            else
                careers = { "query-error" }
            end

            local loadouts_ok, loadouts = query(
                access.get_saved_loadouts, backend_id)
            if loadouts_ok and type(loadouts) == "table" then
                state.is_equipped_by_any_loadout = #loadouts > 0
            else
                loadouts = { "query-error" }
            end

            local favorite_ok, favorite = query(
                access.is_favorite, backend_id, item)
            if favorite_ok and type(favorite) == "boolean" then
                state.is_favorite = favorite
            end

            local eligible, reason = M.is_salvage_eligible(item, record, state)
            if eligible and not seen[backend_id] then
                result[#result + 1] = item
                seen[backend_id] = true
            end
            if type(access.trace) == "function" then
                pcall(access.trace, item, record, state,
                    seen[backend_id] == true, eligible == true, reason,
                    careers, loadouts)
            end
        end
    end
    return result
end

-- Stable identity for the bounded issue-628 salvage diagnostic. Keeping this
-- engine-free lets offline tests prove unchanged UI refreshes deduplicate while
-- a changed equip/loadout/favorite/result state produces a new trace.
function M.salvage_trace_fingerprint(backend_id, visible, eligible, reason, state)
    state = state or {}
    return table.concat({
        tostring(backend_id),
        visible and "visible" or "hidden",
        eligible and "eligible" or "rejected",
        tostring(reason or "none"),
        state.is_equipped and "equipped" or "unequipped",
        state.is_equipped_by_any_loadout and "saved" or "unsaved",
        state.is_favorite and "favorite" or "not-favorite",
        state.backend_dirty and "dirty" or "clean",
    }, "|")
end

-- #277 uses the same closed slot set as crafting/salvage. ItemMasterList calls
-- the Charm slot `ring`; the runtime loadout carrier calls it `slot_ring`.
function M.is_craftable_slot_type(slot_type)
    return SALVAGE_SLOTS[slot_type] == true
end

-- One destructive-cleanup identity verdict shared by preview, confirmation,
-- and execution. Exact membership in CIM's forged map is supplied by the
-- caller; this contract proves the saved owner/schema stamp, canonical key,
-- live provider row, and craftable slot. It never infers ownership from rarity
-- or a backend-id prefix.
function M.classify_owned_record(backend_id, record, master)
    if type(backend_id) ~= "string" or backend_id == "" then return "unresolved" end
    if type(record) ~= "table" then return "unresolved" end
    if record.owner ~= M.OWNER or record.schema_version ~= M.SCHEMA_VERSION then
        return "unresolved"
    end
    local item_key = M.canonical_item_key(record, backend_id)
    if type(item_key) ~= "string" or item_key == "" then return "unresolved" end
    if type(master) ~= "table" then return "unresolved" end
    if not M.validate_provider(item_key, master) then return "unresolved" end
    if not M.is_craftable_slot_type(master.slot_type) then return "retained" end
    return "owned"
end

function M.partition_exact_ids(ids, records)
    local owned, foreign, seen = {}, {}, {}
    for i = 1, #(ids or {}) do
        local backend_id = ids[i]
        if type(backend_id) == "string" and not seen[backend_id] then
            seen[backend_id] = true
            if type(records) == "table" and records[backend_id] then
                owned[#owned + 1] = backend_id
            else
                foreign[#foreign + 1] = backend_id
            end
        end
    end
    return owned, foreign
end

-- #703: the Athanor list's lock badge is a vanilla OWNERSHIP gate, not an unlock
-- gate. `_sync_backend_loadout` resolves each row via
-- `backend_interface_items:get_item_from_key(item_key)` and stamps
-- `content.locked = not backend_id` (hero_window_weave_forge_weapons.lua:555 +
-- :565), which draws the `hero_icon_locked` pass (definitions :776-778) and
-- saturates the icon (`_animate_list_widget` :1424-1425). CWV provider
-- definitions remain distinct from CIM craft ownership (#592/#928); the one
-- provider-owned Blacksmith seed does not make every Athanor row a persisted
-- CIM craft. Classify through this contract's
-- provider ladder so provider=cwv rows are unlocked by definition while vanilla
-- and any other provider keep their vanilla lock state.
function M.is_cwv_provider_key(key)
    if type(key) ~= "string" or key == "" then return false end
    if type(M.provider_for) ~= "function" then return false end
    local iml = rawget(_G, "ItemMasterList")
    local master = iml and rawget(iml, key) or nil
    return M.provider_for(key, master) == "cwv"
end

return M
